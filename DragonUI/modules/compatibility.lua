-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local compatibility = {}
addon.compatibility = compatibility
local L = addon.L

--[[
* DragonUI Compatibility Manager
* 
* Modular system to detect specific addons and apply custom behaviors.
* Each addon can have its own detection and behavior logic.
]]

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local CONFIG = {
    warningDelay = 0.5,
    scanDelay = 0.1
}

local ADDON_REGISTRY

-- ============================================================================
-- OPTIMIZED SYSTEMS
-- ============================================================================

-- Timer helper: delegates to centralized addon:After() (note: arg order is func, delay)
local function DelayedCall(func, delay)
    addon:After(delay, func)
end

-- Cache system for addon loading checks
local addonLoadCache = {}
local function IsAddonLoadedCached(addonName)
    if addonLoadCache[addonName] == nil then
        addonLoadCache[addonName] = IsAddOnLoaded(addonName)
    end
    return addonLoadCache[addonName]
end

local function ResolveRegistryKey(addonName)
    if not addonName then return nil end
    if ADDON_REGISTRY and ADDON_REGISTRY[addonName] then
        return addonName
    end

    local lowered = string.lower(addonName)
    if ADDON_REGISTRY and ADDON_REGISTRY[lowered] then
        return lowered
    end

    return nil
end

local function IsRegistryAddonLoaded(addonName)
    return IsAddonLoadedCached(addonName)
end

-- ============================================================================
-- INTERFACE SETTINGS FIXER (UNIFIED BLIZZARD SETTINGS)
-- ============================================================================

local InterfaceSettingsFixer = {
    popupName = "DRAGONUI_INTERFACE_SETTINGS_FIXER",
    initialized = false,
    scanPending = false,
    popupVisible = false,
    applyingFixes = false,
    dismissedForSession = false,
    lastIssues = nil,
    settings = {
        {
            setting = "showPartyBackground",
            desiredValue = "0",
            type = "CVar",
            category = "conflict",
            displayName = "Party/Arena Background"
        },
        {
            setting = "statusText",
            desiredValue = "0",
            type = "CVar",
            category = "conflict",
            displayName = "Default Status Text"
        },
        {
            setting = "playerStatusText",
            desiredValue = "0",
            type = "CVar",
            category = "conflict",
            displayName = "Default Status Text"
        },
        {
            setting = "petStatusText",
            desiredValue = "0",
            type = "CVar",
            category = "conflict",
            displayName = "Default Status Text"
        },
        {
            setting = "partyStatusText",
            desiredValue = "0",
            type = "CVar",
            category = "conflict",
            displayName = "Default Status Text"
        },
        {
            setting = "targetStatusText",
            desiredValue = "0",
            type = "CVar",
            category = "conflict",
            displayName = "Default Status Text"
        },
        {
            setting = "statusTextPercentage",
            desiredValue = "0",
            type = "CVar",
            category = "conflict",
            displayName = "Default Status Text"
        },
        {
            setting = "xpBarText",
            desiredValue = "0",
            type = "CVar",
            category = "conflict",
            displayName = "Default Status Text"
        }
    }
}

local function NormalizeSettingValue(value)
    if value == nil then return "" end
    return tostring(value):lower()
end

local function GetSettingValue(def)
    if def.type == "CVar" then
        return GetCVar(def.setting)
    elseif def.type == "API" and def.getter then
        return def.getter()
    end
    return nil
end

local function SetSettingValue(def, value)
    if def.type == "CVar" then
        SetCVar(def.setting, tostring(value))
    elseif def.type == "API" and def.setter then
        def.setter(value)
    end
end

local function IsSettingOutOfSpec(def)
    local currentValue = GetSettingValue(def)

    -- If a CVar is unavailable in this client/version, skip it.
    if def.type == "CVar" and (currentValue == nil or currentValue == "") then
        return false
    end

    return NormalizeSettingValue(currentValue) ~= NormalizeSettingValue(def.desiredValue)
end

local function GetOutOfSpecInterfaceSettings()
    local issues = {}
    for _, def in ipairs(InterfaceSettingsFixer.settings) do
        if IsSettingOutOfSpec(def) then
            table.insert(issues, def)
        end
    end
    return issues
end

local function ApplyInterfaceSettingsFixes(issues)
    InterfaceSettingsFixer.applyingFixes = true
    for _, def in ipairs(issues) do
        SetSettingValue(def, def.desiredValue)
    end

    -- Force immediate visual refresh where Blizzard normally reacts to CVar changes.
    if MainMenuBar_Update then
        MainMenuBar_Update()
    end
    if UpdateTextStatusBarText then
        UpdateTextStatusBarText()
    end

    InterfaceSettingsFixer.applyingFixes = false
end

local function BuildInterfaceSettingsIssueLines(issues)
    local seen = {}
    local lines = {}

    for _, def in ipairs(issues) do
        local key = def.category .. ":" .. (def.displayName or def.setting)
        if not seen[key] then
            seen[key] = true
            local categoryLabel
            if def.category == "conflict" then
                categoryLabel = L["Conflict"] or "Conflict"
            else
                categoryLabel = L["Recommended"] or "Recommended"
            end
            local displayName = L[def.displayName] or def.displayName or def.setting
            table.insert(lines, string.format("- %s: %s", categoryLabel, displayName))
        end
    end

    return table.concat(lines, "\n")
end

local function ShowInterfaceSettingsFixerPopup(issues)
    if InterfaceSettingsFixer.popupVisible then
        return
    end

    InterfaceSettingsFixer.lastIssues = issues

    if not StaticPopupDialogs[InterfaceSettingsFixer.popupName] then
        StaticPopupDialogs[InterfaceSettingsFixer.popupName] = {
            text = "",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                local activeIssues = InterfaceSettingsFixer.lastIssues or GetOutOfSpecInterfaceSettings()
                ApplyInterfaceSettingsFixes(activeIssues)
                InterfaceSettingsFixer.dismissedForSession = false
                InterfaceSettingsFixer.popupVisible = false
                ReloadUI()
            end,
            OnCancel = function()
                InterfaceSettingsFixer.dismissedForSession = true
                InterfaceSettingsFixer.popupVisible = false
            end,
            OnHide = function()
                InterfaceSettingsFixer.popupVisible = false
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3
        }
    end

    local issueLines = BuildInterfaceSettingsIssueLines(issues)
    local popupText = "|cFF00CCFFDragonUI|r\n\n" ..
        (L["Some interface settings are not configured optimally for DragonUI."] or "Some interface settings are not configured optimally for DragonUI.") ..
        "\n\n" ..
        (L["This includes settings that conflict with DragonUI and settings recommended for the best visual experience."] or
        "This includes settings that conflict with DragonUI and settings recommended for the best visual experience.") ..
        "\n\n" ..
        (L["Affected settings:"] or "Affected settings:") .. "\n" ..
        issueLines ..
        "\n\n" ..
        (L["Do you want to fix them now?"] or "Do you want to fix them now?")

    StaticPopupDialogs[InterfaceSettingsFixer.popupName].text = popupText
    InterfaceSettingsFixer.popupVisible = true
    StaticPopup_Show(InterfaceSettingsFixer.popupName)
end

local function ScanAndPromptInterfaceSettingsFixer()
    if InterfaceSettingsFixer.applyingFixes then
        return
    end

    local issues = GetOutOfSpecInterfaceSettings()
    if #issues == 0 then
        InterfaceSettingsFixer.lastIssues = nil
        InterfaceSettingsFixer.dismissedForSession = false
        return
    end

    if InterfaceSettingsFixer.dismissedForSession then
        return
    end

    ShowInterfaceSettingsFixerPopup(issues)
end

local function ScheduleInterfaceSettingsScan(delay)
    if InterfaceSettingsFixer.scanPending then
        return
    end

    InterfaceSettingsFixer.scanPending = true
    DelayedCall(function()
        InterfaceSettingsFixer.scanPending = false
        ScanAndPromptInterfaceSettingsFixer()
    end, delay or 0.2)
end

local function IsFixerMonitoredCVar(cvarName)
    if not cvarName then return false end

    for _, def in ipairs(InterfaceSettingsFixer.settings) do
        if def.type == "CVar" and def.setting == cvarName then
            return true
        end
    end

    return false
end

-- ============================================================================
-- BEHAVIOR SYSTEM
-- ============================================================================

local behaviors = {}

-- Behavior: Show conflict warning with disable option
behaviors.ConflictWarning = function(addonName, addonInfo)
    local popupName = "DRAGONUI_CONFLICT_" .. string.upper(addonName)
    
    StaticPopupDialogs[popupName] = {
        text = "|cFFFF0000" .. L["DragonUI Conflict Warning"] .. "|r\n\n" ..
            string.format(L["The addon |cFFFFFF00%s|r conflicts with DragonUI."], addonInfo.name) .. "\n\n" ..
            "|cFFFF9999" .. L["Reason:"] .. "|r " .. addonInfo.reason .. "\n\n" ..
            L["Disable the conflicting addon now?"],
        button1 = L["Disable"],
        button2 = L["Keep Both"],
        OnAccept = function()
            DisableAddOn(addonName)
            ReloadUI()
        end,
        OnCancel = function() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3
    }
    
    StaticPopup_Show(popupName)
end

-- Behavior: UnitFrameLayers overlap resolution
behaviors.UnitFrameLayersCompatibility = function(addonName, addonInfo)
    local popupName = "DRAGONUI_UNITFRAMELAYERS_DETECTED"

    StaticPopupDialogs[popupName] = {
        text = "|cFFFF0000" .. L["DragonUI Conflict Warning"] .. "|r\n\n" ..
            "|cFFFFFF00" .. L["DragonUI - UnitFrameLayers Detected"] .. "|r\n\n" ..
            L["DragonUI already includes Unit Frame Layers functionality (heal prediction, absorb shields, and animated health loss)."] .. "\n\n" ..
            L["Choose how to resolve this overlap:"] .. "\n" ..
            "- " .. L["Use DragonUI: disable external UnitFrameLayers and enable DragonUI layers."] .. "\n" ..
            "- " .. L["Disable Both: disable external UnitFrameLayers and keep DragonUI layers disabled."],
        button1 = L["Use DragonUI"],
        button2 = L["Disable Both"],
        OnAccept = function()
            DisableAddOn(addonName)

            addon.db = addon.db or {}
            addon.db.profile = addon.db.profile or {}
            addon.db.profile.modules = addon.db.profile.modules or {}
            addon.db.profile.modules.unitframe_layers = addon.db.profile.modules.unitframe_layers or {}
            addon.db.profile.modules.unitframe_layers.enabled = true

            ReloadUI()
        end,
        OnCancel = function()
            DisableAddOn(addonName)

            addon.db = addon.db or {}
            addon.db.profile = addon.db.profile or {}
            addon.db.profile.modules = addon.db.profile.modules or {}
            addon.db.profile.modules.unitframe_layers = addon.db.profile.modules.unitframe_layers or {}
            addon.db.profile.modules.unitframe_layers.enabled = false

            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3
    }

    StaticPopup_Show(popupName)
end

-- Behavior: prompt to enable nameplateAlphaCompat when a plate-buff/cooldown addon is
-- detected. Those addons read the nameplate's native alpha/IsShown as their identity
-- signal; DragonUI overrides native alpha by default, which breaks their plate matching.
local nameplateAlphaCompatPrompted = false
behaviors.NameplateAddonAlphaCompat = function(addonName, addonInfo)
    if nameplateAlphaCompatPrompted then
        return
    end

    local npCfg = addon.db and addon.db.profile and addon.db.profile.modules
        and addon.db.profile.modules.nameplates
    if not npCfg or npCfg.nameplateAlphaCompat == true then
        return
    end

    nameplateAlphaCompatPrompted = true

    local popupName = "DRAGONUI_NAMEPLATE_ALPHA_COMPAT"
    StaticPopupDialogs[popupName] = {
        text = "|cFF00CCFFDragonUI|r\n\n" ..
            string.format(L["Detected |cFFFFFF00%s|r. Enable Nameplate Addon Compatibility so it works correctly?"], addonInfo.name),
        button1 = L["Enable"],
        button2 = L["Not Now"],
        OnAccept = function()
            npCfg.nameplateAlphaCompat = true
            ReloadUI()
        end,
        OnCancel = function() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    }

    StaticPopup_Show(popupName)
end

-- Distinct from NameplateAddonAlphaCompat above: this skips the health-bar SetAlpha(0), not plate-root alpha.
local nameplateBarAlphaCompatPrompted = false
behaviors.NameplateBarAlphaCompat = function(addonName, addonInfo)
    if nameplateBarAlphaCompatPrompted then
        return
    end

    local npCfg = addon.db and addon.db.profile and addon.db.profile.modules
        and addon.db.profile.modules.nameplates
    if not npCfg or npCfg.nameplateBarAlphaCompat == true then
        return
    end

    nameplateBarAlphaCompatPrompted = true

    local popupName = "DRAGONUI_NAMEPLATE_BAR_ALPHA_COMPAT"
    StaticPopupDialogs[popupName] = {
        text = "|cFF00CCFFDragonUI|r\n\n" ..
            string.format(L["Detected |cFFFFFF00%s|r. Enable Nameplate Health Bar Compatibility so it works correctly?"], addonInfo.name),
        button1 = L["Enable"],
        button2 = L["Not Now"],
        OnAccept = function()
            npCfg.nameplateBarAlphaCompat = true
            ReloadUI()
        end,
        OnCancel = function() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    }

    StaticPopup_Show(popupName)
end

-- ============================================================================
-- ADDON REGISTRY
-- ============================================================================

-- Behavior: Carbonite minimap texture re-application
-- Carbonite resets minimap mask via SetMaskTexture during its ADDON_LOADED init,
-- and starts a repeating timer that calls SetBlipTexture every ~0.2s (node glow).
-- The SetBlipTexture override in minimap.lua blocks the timer calls, but we still
-- need to re-apply mask and POI textures after Carbonite's one-time init.
behaviors.CarboniteMinimapFix = function(addonName, addonInfo)
    -- Re-apply minimap textures after Carbonite finishes its init
    local elapsed = 0
    local reapplyFrame = CreateFrame("Frame")
    reapplyFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed > 1.5 then
            if addon.MinimapModule and addon.MinimapModule.applied
                and addon:IsModuleEnabled("minimap") then
                addon.MinimapModule.ReapplyMinimapTextures()
            end
            self:SetScript("OnUpdate", nil)
        end
    end)
end



-- ============================================================================
-- SEXYMAP COMPATIBILITY SYSTEM
-- ============================================================================

-- Behavior: SexyMap compatibility with 3-option popup
-- Detects SexyMap and offers:  Use SexyMap only / Use DragonUI only / Hybrid mode
behaviors.SexyMapCompatibility = function(addonName, addonInfo)
    -- Check if user has already made a choice (stored in DB)
    local minimapConfig = addon.db and addon.db.profile and addon.db.profile.modules
        and addon.db.profile.modules.minimap
    if not minimapConfig then return end

    local savedMode = minimapConfig.sexymap_mode

    -- If a mode was already chosen, apply it silently
    if savedMode then
        -- Delay application to ensure both addons have finished loading
        DelayedCall(function()
            behaviors._ApplySexyMapMode(savedMode)
        end, 1.0)
        return
    end

    -- Show the 3-option popup after a short delay (let both addons finish loading)
    DelayedCall(function()
        behaviors._ShowSexyMapPopup()
    end, 1.5)
end

-- Internal: Show the SexyMap compatibility popup with 3 options
behaviors._ShowSexyMapPopup = function()
    local popupName = "DRAGONUI_SEXYMAP_COMPAT"

    StaticPopupDialogs[popupName] = {
        text = "|cFF00CCFF" .. L["DragonUI - SexyMap Detected"] .. "|r\n\n" ..
            L["Which minimap do you want to use?"] .. "\n\n" ..
            "|cFFFFFF00" .. L["Hybrid"] .. " (" .. L["Recommended"] .. "):|r " .. L["SexyMap visuals with DragonUI editor and positioning."],
        button1 = L["SexyMap"],
        button2 = L["DragonUI"],
        button3 = L["Hybrid"],
        OnAccept = function()
            -- Button1: Use SexyMap Only
            behaviors._SaveSexyMapMode("sexymap")
            -- Pre-disable button skins so they don't conflict with SexyMap
            if addon.db and addon.db.profile and addon.db.profile.minimap then
                addon.db.profile.minimap.addon_button_skin = false
            end
            ReloadUI()
        end,
        OnCancel = function()
            -- Button2: Use DragonUI Only
            behaviors._SaveSexyMapMode("dragonui")
            DisableAddOn("SexyMap")
            ReloadUI()
        end,
        OnAlt = function()
            -- Button3: Hybrid Mode
            behaviors._SaveSexyMapMode("hybrid")
            -- Pre-disable button skins so they don't flash on reload
            if addon.db and addon.db.profile and addon.db.profile.minimap then
                addon.db.profile.minimap.addon_button_skin = false
            end
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3,
        showAlert = true
    }

    StaticPopup_Show(popupName)
end

-- Internal: Save the user's SexyMap mode choice to DB
behaviors._SaveSexyMapMode = function(mode)
    if addon.db and addon.db.profile and addon.db.profile.modules
        and addon.db.profile.modules.minimap then
        addon.db.profile.modules.minimap.sexymap_mode = mode
    end
end

-- Internal: Exempt MiniMapLFGFrame (Dungeon Eye) from SexyMap's hover-fade.
-- DragonUI's micromenu reparents MiniMapLFGFrame out of MinimapCluster into
-- its own moveable wrapper.  SexyMap's Buttons module registers it as a hover
-- button (fades to alpha 0 when mouse is not over the minimap), but since the
-- frame is no longer a child of MinimapCluster the mouse-over detection never
-- fires → the Dungeon Eye becomes permanently invisible.
-- Fix: Unregister it from SexyMap's hover system and hook SetAlpha as safety net.
behaviors._ExemptLFGFromSexyMapFade = function()
    if not MiniMapLFGFrame then return end
    -- Already applied?
    if MiniMapLFGFrame._DragonUI_SexyMapFadeExempt then return end
    MiniMapLFGFrame._DragonUI_SexyMapFadeExempt = true

    local sexyMapObj = _G["SexyMap"]
    -- Unregister from SexyMap's hover system
    if sexyMapObj and sexyMapObj.UnregisterHoverButton then
        sexyMapObj:UnregisterHoverButton(MiniMapLFGFrame)
    end
    -- Force full alpha
    MiniMapLFGFrame:SetAlpha(1)

    -- Safety net: hook SetAlpha to prevent SexyMap from fading it
    local origLFGSetAlpha = MiniMapLFGFrame.SetAlpha
    MiniMapLFGFrame.SetAlpha = function(self, alpha)
        -- If DragonUI has reparented the LFG frame out of the minimap
        -- hierarchy, block external fade attempts
        local parent = self:GetParent()
        if parent and parent ~= Minimap and parent ~= MinimapCluster
           and parent ~= MinimapBackdrop then
            origLFGSetAlpha(self, 1)
            return
        end
        origLFGSetAlpha(self, alpha)
    end
end

local function OnCollectorManagedButtonSetAlpha(self, alpha)
    if not self.DragonUI_ForceCollectorAlpha then
        return
    end

    if alpha and alpha >= 0.99 then
        return
    end

    local collector = _G.DragonUI_MinimapIconCollector
    if not collector or not collector.isOpen or self:GetParent() ~= collector then
        return
    end

    if self.DragonUI_CollectorAlphaFixing then
        return
    end

    self.DragonUI_CollectorAlphaFixing = true
    self:SetAlpha(1)
    self.DragonUI_CollectorAlphaFixing = nil
end

function compatibility:ApplySexyMapCollectorVisibilityFix(button, collector)
    if not button then
        return
    end

    if not self:IsSexyMapHybridMode() or not IsAddOnLoaded("SexyMap") then
        button.DragonUI_ForceCollectorAlpha = nil
        return
    end

    button.DragonUI_ForceCollectorAlpha = true

    local sexyMapObj = _G["SexyMap"]
    if sexyMapObj and sexyMapObj.UnregisterHoverButton then
        sexyMapObj:UnregisterHoverButton(button)
    end

    if not button.DragonUI_CollectorAlphaHooked then
        button.DragonUI_CollectorAlphaHooked = true
        hooksecurefunc(button, "SetAlpha", OnCollectorManagedButtonSetAlpha)
    end

    -- Force visible now so collector-open state does not depend on minimap hover.
    button:SetAlpha(1)
end

local function HideCalendarDayTextIfPresent()
    if not GameTimeFrame or not GameTimeFrame.GetFontString then
        return
    end

    local dayText = GameTimeFrame:GetFontString()
    if dayText then
        dayText:Hide()
    end
end

function compatibility:ApplySexyMapHybridCalendarFix()
    if not self:IsSexyMapHybridMode() or not IsAddOnLoaded("SexyMap") then
        return false
    end

    HideCalendarDayTextIfPresent()

    if GameTimeFrame and not GameTimeFrame.DragonUI_HybridCalendarTextHooked then
        GameTimeFrame.DragonUI_HybridCalendarTextHooked = true
        GameTimeFrame:HookScript("OnShow", HideCalendarDayTextIfPresent)
        GameTimeFrame:HookScript("OnEvent", HideCalendarDayTextIfPresent)
    end

    return true
end

local function UpdateCollectorToggleHoverVisibility()
    local button = compatibility._collectorToggleButton
    if not button then
        return
    end

    if not compatibility:IsSexyMapHybridMode() or not IsAddOnLoaded("SexyMap") then
        return
    end

    if Minimap and Minimap:IsMouseOver() then
        button:SetAlpha(1)
    else
        button:SetAlpha(0)
    end
end

function compatibility:ApplySexyMapCollectorToggleVisibilityFix(button)
    if not button then
        return false
    end

    if not self:IsSexyMapHybridMode() or not IsAddOnLoaded("SexyMap") then
        button.DragonUI_HybridCollectorHoverManaged = nil
        return false
    end

    button.DragonUI_HybridCollectorHoverManaged = true
    self._collectorToggleButton = button

    local sexyMapObj = _G["SexyMap"]
    if sexyMapObj and sexyMapObj.RegisterHoverButton then
        sexyMapObj:RegisterHoverButton(button)
        return true
    end

    if Minimap and not self._collectorToggleHoverHooksInstalled then
        self._collectorToggleHoverHooksInstalled = true
        Minimap:HookScript("OnEnter", UpdateCollectorToggleHoverVisibility)
        Minimap:HookScript("OnLeave", UpdateCollectorToggleHoverVisibility)
    end

    UpdateCollectorToggleHoverVisibility()
    return true
end

-- Internal: Apply the chosen SexyMap compatibility mode (called on login with saved choice)
behaviors._ApplySexyMapMode = function(mode)
    if mode == "hybrid_v2" then
        behaviors._SaveSexyMapMode("dragonui")
        mode = "dragonui"
    end

    if mode == "sexymap" then
        -- ================================================================
        -- USE SEXYMAP ONLY: DragonUI minimap module skips initialization
        -- when sexymap_mode == "sexymap" is in DB (checked in Initialize/Apply).
        -- Also disable addon button skin to avoid conflicts.
        -- Ensure SexyMap is enabled at addon level (may have been disabled
        -- by a previous "dragonui" mode switch).
        -- ================================================================
        EnableAddOn("SexyMap")
        if addon.db and addon.db.profile and addon.db.profile.minimap then
            addon.db.profile.minimap.addon_button_skin = false
        end
        -- Exempt LFG icon from SexyMap fade (DragonUI micromenu reparents it)
        DelayedCall(behaviors._ExemptLFGFromSexyMapFade, 2.0)

    elseif mode == "dragonui" then
        -- ================================================================
        -- USE DRAGONUI ONLY: Disable SexyMap addon so it won't load
        -- on next reload. Also disable if currently loaded.
        -- ================================================================
        DisableAddOn("SexyMap")

    elseif mode == "hybrid" then
        -- ================================================================
        -- HYBRID MODE: Mark module for hybrid behavior
        -- The minimap module reads sexymap_mode from DB during init
        -- and adjusts its ReplaceBlizzardFrame/RemoveBlizzardFrames logic.
        -- Ensure SexyMap is enabled at addon level (may have been disabled
        -- by a previous "dragonui" mode switch).
        -- ================================================================
        EnableAddOn("SexyMap")
        if addon.MinimapModule then
            addon.MinimapModule.sexyMapHybridMode = true
        end
        -- Apply runtime adjustments after minimap is initialized
        behaviors._WaitAndAdjustHybrid()
    end
end

-- Internal: Wait for minimap module to initialize then apply hybrid adjustments
behaviors._WaitAndAdjustHybrid = function()
    if addon.MinimapModule and addon.MinimapModule.applied then
        behaviors._AdjustForHybridMode()
    else
        local waitFrame = CreateFrame("Frame")
        local waitElapsed = 0
        waitFrame:SetScript("OnUpdate", function(self, dt)
            waitElapsed = waitElapsed + dt
            if waitElapsed > 3.0 then
                if addon.MinimapModule and addon.MinimapModule.applied then
                    behaviors._AdjustForHybridMode()
                end
                self:SetScript("OnUpdate", nil)
            end
        end)
    end
end

-- Internal: Adjust DragonUI minimap for hybrid coexistence with SexyMap
-- In hybrid mode:
--   SexyMap controls: borders, shapes/mask, fading, button orbit/visibility
--   DragonUI controls: positioning (editor mode), tracking icons, calendar,
--                      instance difficulty, POI textures, blip textures
behaviors._AdjustForHybridMode = function()
    -- 1. Hide DragonUI's custom border top (SexyMap hides the default and uses its own)
    if MinimapBorderTop then
        MinimapBorderTop:Hide()
    end

    -- 2. Allow SexyMap to control the minimap mask (shape)
    if addon.MinimapModule then
        addon.MinimapModule._allowExternalMask = true
    end

    -- 3. Allow SexyMap to control MinimapBorder visibility
    if addon.MinimapModule then
        addon.MinimapModule._allowExternalBorderControl = true
    end

    -- 4. Hide DragonUI's custom border frame and circle texture (conflicts with SexyMap borders)
    if addon.MinimapModule and addon.MinimapModule.borderFrame then
        addon.MinimapModule.borderFrame:Hide()
        addon.MinimapModule._borderHiddenForHybrid = true
    end
    if Minimap and Minimap.Circle then
        Minimap.Circle:Hide()
    end

    -- 5. Fix zone text: Let SexyMap's ZoneText module handle styling/position
    --    but preserve DragonUI's click-to-open-map functionality
    if MinimapZoneTextButton then
        local sexyMapObj = _G["SexyMap"]
        local sexyMapZoneText = sexyMapObj and sexyMapObj.GetModule and sexyMapObj:GetModule("ZoneText", true)
        if sexyMapZoneText then
            -- Re-apply click handler after SexyMap modifies the button
            MinimapZoneTextButton:EnableMouse(true)
            MinimapZoneTextButton:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" then
                    if WorldMapFrame:IsShown() then
                        HideUIPanel(WorldMapFrame)
                    else
                        ShowUIPanel(WorldMapFrame)
                    end
                end
            end)
        end
    end

    -- 6. Lock SexyMap's built-in drag so DragonUI editor handles positioning
    local sexyMapObj = _G["SexyMap"]
    if sexyMapObj then
        local sexyMapGeneral = sexyMapObj.GetModule and sexyMapObj:GetModule("General", true)
        if sexyMapGeneral then
            if sexyMapGeneral.db and sexyMapGeneral.db.profile then
                sexyMapGeneral.db.profile.lock = true
            end
            -- Also call SetLock directly to clear any drag scripts already set up
            if sexyMapGeneral.SetLock then
                sexyMapGeneral:SetLock(true)
            end
        end
    end

    -- 7. Let SexyMap's Borders, Fader, and Buttons modules work freely
    --    (no interference needed — they operate on Minimap children)

    -- 8. Restore SexyMap's mask if it was overridden by DragonUI
    if sexyMapObj then
        local sexyMapShapes = sexyMapObj.GetModule and sexyMapObj:GetModule("Shapes", true)
        if sexyMapShapes and sexyMapShapes.Apply then
            -- Let SexyMap re-apply its shape
            sexyMapShapes:Apply()
        end
    end

    -- 9. Disable DragonUI's addon button skin (conflicts with SexyMap button management)
    if addon.db and addon.db.profile and addon.db.profile.minimap then
        addon.db.profile.minimap.addon_button_skin = false
    end

    -- Also unskin any buttons already skinned this session so no second reload is needed
    if addon.MinimapModule and addon.MinimapModule.UnskinAllMinimapButtons then
        addon.MinimapModule.UnskinAllMinimapButtons()
    end

    -- 10. Re-trigger SexyMap's button hover/hide system so buttons hide properly after unskinning
    if sexyMapObj then
        local sexyMapButtons = sexyMapObj.GetModule and sexyMapObj:GetModule("Buttons", true)
        if sexyMapButtons and sexyMapButtons.Update then
            sexyMapButtons:Update()
        end
    end

    -- 11. Exempt LFG icon from SexyMap fade (shared with sexymap-only mode)
    behaviors._ExemptLFGFromSexyMapFade()

    -- 12. Hide calendar day text in hybrid (SexyMap icon already contains the day number)
    compatibility:ApplySexyMapHybridCalendarFix()

end

-- Public API: Check if hybrid mode is active
function compatibility:IsSexyMapHybridMode()
    if not addon.db or not addon.db.profile or not addon.db.profile.modules
        or not addon.db.profile.modules.minimap then
        return false
    end
    local mode = addon.db.profile.modules.minimap.sexymap_mode
    return mode == "hybrid"
end

-- Public API: Get current SexyMap mode
function compatibility:GetSexyMapMode()
    if not addon.db or not addon.db.profile or not addon.db.profile.modules
        or not addon.db.profile.modules.minimap then
        return nil
    end
    return addon.db.profile.modules.minimap.sexymap_mode
end

-- Public API: Reset SexyMap mode choice (will re-prompt on next login)
function compatibility:ResetSexyMapMode()
    if addon.db and addon.db.profile and addon.db.profile.modules
        and addon.db.profile.modules.minimap then
        addon.db.profile.modules.minimap.sexymap_mode = nil
    end
end

ADDON_REGISTRY = {
    ["unitframelayers"] = {
        name = "UnitFrameLayers",
        reason = L["Conflicts with DragonUI's custom unit frame textures and power bar system."],
        behavior = behaviors.UnitFrameLayersCompatibility,
        checkOnce = true
    },
    ["platebuffs"] = {
        name = "PlateBuffs",
        reason = L["Reads native nameplate alpha to identify the target's plate; conflicts with DragonUI's default anti-dim behavior."],
        behavior = behaviors.NameplateAddonAlphaCompat,
        checkOnce = true
    },
    ["crosshairs"] = {
        name = "Crosshairs",
        reason = L["Reads native nameplate alpha to identify the target's plate; conflicts with DragonUI's default anti-dim behavior."],
        behavior = behaviors.NameplateAddonAlphaCompat,
        checkOnce = true
    },
    ["icicle"] = {
        name = "Icicle",
        reason = L["Parents its cooldown icons to the native health bar; conflicts with DragonUI's default health-bar hiding."],
        behavior = behaviors.NameplateBarAlphaCompat,
        checkOnce = true
    },
    ["nameplatesct"] = {
        name = "NameplateSCT",
        reason = L["Reads native nameplate alpha to identify the target's plate; conflicts with DragonUI's default anti-dim behavior."],
        behavior = behaviors.NameplateAddonAlphaCompat,
        checkOnce = true
    },
    ["classicnumbers"] = {
        name = "ClassicNumbers",
        reason = L["Reads native nameplate alpha to identify the target's plate; conflicts with DragonUI's default anti-dim behavior."],
        behavior = behaviors.NameplateAddonAlphaCompat,
        checkOnce = true
    },
    ["carbonite"] = {
        name = "Carbonite",
        reason = L["Resets minimap mask and blip textures. DragonUI re-applies its custom textures automatically."],
        behavior = behaviors.CarboniteMinimapFix,
        checkOnce = true
    },
    ["sexymap"] = {
        name = "SexyMap",
        reason = L["SexyMap modifies the minimap borders, shape, and zone text which conflicts with DragonUI's minimap module."],
        behavior = behaviors.SexyMapCompatibility,
        checkOnce = true
    },
}

-- ============================================================================
-- STATE TRACKING
-- ============================================================================

local state = {
    processedAddons = {},
    activeAddons = {},
    initialized = false
}

local function GetCompatibilityConfig()
    if not addon.db or not addon.db.profile then
        return nil
    end

    addon.db.profile.compatibility = addon.db.profile.compatibility or {}
    return addon.db.profile.compatibility
end

-- ============================================================================
-- BARTENDER4 HAND-OFF
-- ============================================================================

-- Each part is DragonUI's or Bartender4's (compatibility.bartender_<key>). `modules` are the DragonUI modules
-- Bartender4 stands in for, `bartender` its modules kept off while DragonUI's `keeper` module runs the part.
-- Under Bartender4's bars the main bars module stays on for the XP and reputation bars, noop for their art.
local BARTENDER_PARTS = {
    {
        key = "actionbars", keeper = "mainbars",
        modules = { "vehicle", "stance", "petbar", "multicast", "buttons" },
        bartender = { "ActionBars", "PetBar", "StanceBar", "MultiCast", "Vehicle", "BlizzardArt" },
    },
    {
        key = "micromenu", keeper = "micromenu",
        modules = { "micromenu" },
        bartender = { "MicroMenu", "BagBar" },
    },
}
compatibility.BARTENDER_PARTS = BARTENDER_PARTS

local BARTENDER_DEFAULT_OWNER = { actionbars = "bartender4", micromenu = "dragonui" }

-- The XP and reputation bars stay DragonUI's either way: noop strips the stock art Bartender4's would show.
local BARTENDER_XP = { "XPBar", "RepBar" }

local function PartOfModule(name)
    for _, part in ipairs(BARTENDER_PARTS) do
        for _, moduleName in ipairs(part.modules) do
            if moduleName == name then return part end
        end
    end
end

-- The saved choice, "dragonui" or "bartender4"; what this session runs is in bartenderOwned.
function compatibility:BartenderOwner(key)
    local cfg = GetCompatibilityConfig()
    return cfg and cfg["bartender_" .. key] or BARTENDER_DEFAULT_OWNER[key]
end

function compatibility:BartenderOwns(key)
    return IsAddOnLoaded("Bartender4") and self:BartenderOwner(key) == "bartender4"
end

function compatibility:BartenderOwnsBars()
    return self:BartenderOwns("actionbars")
end

-- Whether the saved choice switches this DragonUI module off for Bartender4.
function compatibility:BartenderTakesModule(name)
    local part = PartOfModule(name)
    return part ~= nil and self:BartenderOwns(part.key)
end

-- They read SetEnabledState at PLAYER_LOGIN and are not built yet. Nothing is saved: once the part is
-- handed over, or DragonUI is gone, they come back as Bartender4's own settings say.
local function KeepBartenderModuleOff(bartender, name)
    local module = bartender:GetModule(name, true)
    if not module then return end
    module:SetEnabledState(false)
    if module:IsEnabled() then
        module:Disable()
    end
    -- Its profile switch and options checkbox call this; a stored "on" must not bring the bar back.
    module.ToggleModule = function(self, info, value)
        if value ~= nil then
            self.db.profile.enabled = value
        end
    end
end

-- State drivers and secure attributes: a reload in combat leaves these for when it ends.
local function OutOfCombat(fn)
    if not InCombatLockdown() then
        fn()
        return
    end
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    waiter:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        fn()
    end)
end

-- "Use Blizzard Vehicle UI" brings back the stock vehicle bar, which takes the micro buttons on every vehicle
-- and state-hides the possess bar. Next to DragonUI's bars or micro menu it is off for the session, unsaved.
local function KeepBartenderVehicleUIOff(bartender, keepVehicleBarOff)
    local update = bartender.UpdateBlizzardVehicle
    if not update or bartender.DragonUI_VehicleUIOff then return end
    bartender.DragonUI_VehicleUIOff = true
    bartender.UpdateBlizzardVehicle = function(self, ...)
        local profile = self.db and self.db.profile
        local saved = profile and profile.blizzardVehicle
        if saved then profile.blizzardVehicle = false end
        update(self, ...)
        if saved then profile.blizzardVehicle = saved end
        -- Its "off" branch enables its own vehicle bar directly, past the ToggleModule override.
        if keepVehicleBarOff then
            KeepBartenderModuleOff(self, "Vehicle")
        end
    end
    -- Its OnInitialize already switched the stock vehicle bar on.
    local profile = bartender.db and bartender.db.profile
    if profile and profile.blizzardVehicle then
        OutOfCombat(function() bartender:UpdateBlizzardVehicle() end)
    end
end

local BLIZZARD_ACTION_BUTTONS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton",
}

-- What ActionButton_OnLoad registers, and what ActionButton_Update adds once a slot has an action.
local ACTION_BUTTON_EVENTS = {
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "ACTIONBAR_PAGE_CHANGED",
    "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "UPDATE_SHAPESHIFT_FORM",
}
local ACTION_EVENTS = {
    "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN", "UPDATE_INVENTORY_ALERTS",
    "PLAYER_TARGET_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
    "COMPANION_UPDATE", "UNIT_INVENTORY_CHANGED", "LEARNED_SPELL_IN_TAB",
}

-- Bartender4 loads first and its OnInitialize strips the stock bars for its own; DragonUI's are built on them.
-- Its other changes (MainMenuBarArtFrame, the shapeshift and bonus bars) noop makes as well. Only events are
-- put back: running the stock handlers or writing their fields from here would taint the buttons.
local function RestoreBlizzardBars()
    for _, prefix in ipairs(BLIZZARD_ACTION_BUTTONS) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button then
                for _, event in ipairs(ACTION_BUTTON_EVENTS) do
                    button:RegisterEvent(event)
                end
                -- Set when the slot had an action at load (a reload): ActionButton_Update won't register these again.
                if button.eventsRegistered then
                    for _, event in ipairs(ACTION_EVENTS) do
                        button:RegisterEvent(event)
                    end
                end
                if button.action and HasAction(button.action) then
                    button:Show()
                end
            end
        end
    end
    -- The bars' parent: hidden, it would take the multi bars, the possess bar and the XP bar with it.
    if MainMenuBar then MainMenuBar:Show() end
    -- PLAYER_ENTERING_WORLD then updates it from the stock handler.
    if PossessBarFrame then
        PossessBarFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        PossessBarFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
        PossessBarFrame:RegisterEvent("UNIT_AURA")
        -- noop keeps this one off: on a page change it re-Shows the bonus bar the keybinds would then land on.
        if not addon:IsModuleEnabled("noop") then
            PossessBarFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
        end
    end
    -- Stock FrameXML's, which Bartender4 swaps for an empty one. Run from here, ActionButton_ShowGrid and
    -- HideGrid skip the showgrid count (they check issecure), so it is kept here. In combat their Show/Hide
    -- would be blocked (the spellbook opens and closes in combat), so the grid catches up when it ends.
    local gridPending
    MultiActionBar_UpdateGrid = function(barName, show)
        if InCombatLockdown() then
            gridPending = true
            return
        end
        for i = 1, NUM_MULTIBAR_BUTTONS do
            local button = _G[barName .. "Button" .. i]
            local count = button:GetAttribute("showgrid") or 0
            button:SetAttribute("showgrid", show and count + 1 or math.max(count - 1, 0))
            if show then
                ActionButton_ShowGrid(button)
            else
                ActionButton_HideGrid(button)
            end
        end
    end
    local gridWatcher = CreateFrame("Frame")
    gridWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    gridWatcher:SetScript("OnEvent", function()
        if not gridPending then return end
        gridPending = nil
        -- What MultiActionBar_ShowAllGrids/HideAllGrids would have left: open spellbook or the option.
        local show = (SpellBookFrame and SpellBookFrame:IsShown())
            or ALWAYS_SHOW_MULTIBARS == "1" or ALWAYS_SHOW_MULTIBARS == 1
        for _, barName in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }) do
            for i = 1, NUM_MULTIBAR_BUTTONS do
                local button = _G[barName .. "Button" .. i]
                button:SetAttribute("showgrid", show and 1 or 0)
                if show then
                    ActionButton_ShowGrid(button)
                else
                    ActionButton_HideGrid(button)
                end
            end
        end
    end)
    -- The talent frame refreshes on a spec switch again.
    if PlayerTalentFrame then
        PlayerTalentFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    elseif hooksecurefunc then
        -- Runs after Bartender4's own hook, which unregisters it each time the frame loads.
        hooksecurefunc("TalentFrame_LoadUI", function()
            if PlayerTalentFrame then
                PlayerTalentFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
            end
        end)
    end
end

-- DragonUI's bars and the Bartender4 bar that takes each over: an action bar id or a module, and the size
-- of Bartender4's buttons on it.
local BARTENDER_LAYOUT = {
    { key = "bar1", bar = 1, prefix = "ActionButton", count = 12, size = 36 },
    { key = "bar3", bar = 3, prefix = "MultiBarRightButton", count = 12, size = 36 },
    { key = "bar4", bar = 4, prefix = "MultiBarLeftButton", count = 12, size = 36 },
    { key = "bar5", bar = 5, prefix = "MultiBarBottomRightButton", count = 12, size = 36 },
    { key = "bar6", bar = 6, prefix = "MultiBarBottomLeftButton", count = 12, size = 36 },
    { key = "pet", module = "PetBar", prefix = "PetActionButton", count = 10, size = 30 },
    { key = "stance", module = "StanceBar", prefix = "ShapeshiftButton", count = 10, size = 30 },
}
compatibility.BARTENDER_LAYOUT = BARTENDER_LAYOUT

-- Bartender4's first button sits this far in from its bar's top-left corner (ButtonBar:UpdateButtonLayout).
local BARTENDER_INSET_X, BARTENDER_INSET_Y = 5, 3

-- A bar in UIParent units, as LibWindow stores Bartender4's positions: its TOPLEFT corner, scale, rows, gap,
-- button count. Empty slots are hidden but laid out; the slots past DragonUI's count are parked off screen.
local function MeasureBar(entry)
    local uiScale = UIParent:GetEffectiveScale()
    local left, top, width, gap, shown
    local buttons, rows, tops = 0, 0, {}
    local previous
    for i = 1, entry.count do
        local button = _G[entry.prefix .. i]
        local bar = button and button:GetParent()
        if bar and bar:IsVisible() and button:GetLeft() then
            local s = button:GetEffectiveScale() / uiScale
            local l, r, t = button:GetLeft() * s, button:GetRight() * s, button:GetTop() * s
            if t > 0 then
                buttons = buttons + 1
                shown = shown or button:IsVisible()
                left, top = math.min(left or l, l), math.max(top or t, t)
                width = width or (r - l)
                local row = math.floor(t + 0.5)
                if not tops[row] then
                    tops[row] = true
                    rows = rows + 1
                end
                if previous and not gap and math.abs(previous.t - t) < 1 and l > previous.r then
                    gap = l - previous.r
                end
                previous = { t = t, r = r }
            end
        end
    end
    -- An empty bar the player turned on still counts: "Always Show Action Bars" may be off.
    if buttons == 0 or width <= 0 then return nil end
    local scale = width / entry.size
    return {
        x = left - BARTENDER_INSET_X * scale,
        y = top + BARTENDER_INSET_Y * scale - UIParent:GetHeight(),
        scale = scale,
        rows = rows,
        buttons = buttons,
        padding = gap and math.floor(gap / scale + 0.5) or nil,
        shown = shown,
    }
end

-- Runs at logout while DragonUI's bars are up. A pet or stance bar not shown then keeps its last spot.
function compatibility:SnapshotBarLayout()
    local cfg = GetCompatibilityConfig()
    if not cfg or not UIParent or (UnitHasVehicleUI and UnitHasVehicleUI("player")) then return end
    -- The main bar hidden means a possess or vehicle page: nothing on screen is the player's layout.
    local main = MeasureBar(BARTENDER_LAYOUT[1])
    if not main then return end
    local layout = cfg.bartender_layout or {}
    for _, entry in ipairs(BARTENDER_LAYOUT) do
        local measured = MeasureBar(entry)
        if entry.bar then
            layout[entry.key] = measured or { hidden = true }
        elseif measured and measured.shown then
            layout[entry.key] = measured
        end
    end
    cfg.bartender_layout = layout
end

-- Before Bartender4's PLAYER_LOGIN builds its bars, so they come up where DragonUI's were. The bar is a 1x1
-- frame at its grow corner, so the corner is pinned: TOPLEFT, growing down and right.
local function SeedBartenderLayout(bartender, layout)
    for _, entry in ipairs(BARTENDER_LAYOUT) do
        local saved = layout[entry.key]
        local module = bartender:GetModule(entry.module or "ActionBars", true)
        local profile = module and module.db and module.db.profile
        local config = profile and (entry.bar and profile.actionbars and profile.actionbars[entry.bar] or not entry.bar and profile)
        if saved and config then
            if entry.bar then
                config.enabled = not saved.hidden
                config.buttons = saved.buttons or config.buttons
            end
            if saved.x then
                local position = config.position or {}
                position.point, position.x, position.y, position.scale = "TOPLEFT", saved.x, saved.y, saved.scale
                position.growVertical, position.growHorizontal = "DOWN", "RIGHT"
                config.position = position
                config.rows = saved.rows
                config.padding = saved.padding or config.padding
            end
        end
    end
    -- DragonUI pages its main bar instead of showing a second one.
    local actionBars = bartender:GetModule("ActionBars", true)
    local bars = actionBars and actionBars.db and actionBars.db.profile.actionbars
    if bars and bars[2] and layout.bar1 then
        bars[2].enabled = false
    end
end

-- The load's split, set once: Bartender4's modules, the stock bars and the layout hand-over.
function compatibility:SetupBartenderSession(cfg)
    local owned = self.bartenderOwned
    local runsBars = not owned.actionbars and addon:IsModuleEnabled("mainbars")
    local bartender = IsAddOnLoaded("Bartender4") and _G.Bartender4
    if bartender and bartender.GetModule then
        local runsMicro = not owned.micromenu and addon:IsModuleEnabled("micromenu")
        -- First: switching the stock vehicle bar off re-enables Bartender4's own vehicle bar.
        if runsBars or runsMicro then
            KeepBartenderVehicleUIOff(bartender, runsBars)
        end
        for _, part in ipairs(BARTENDER_PARTS) do
            if not owned[part.key] and addon:IsModuleEnabled(part.keeper) then
                for _, name in ipairs(part.bartender) do
                    KeepBartenderModuleOff(bartender, name)
                end
            end
        end
        if addon:IsModuleEnabled("mainbars") then
            for _, name in ipairs(BARTENDER_XP) do
                KeepBartenderModuleOff(bartender, name)
            end
        end
        if runsBars then
            -- After combat PLAYER_ENTERING_WORLD is past: the buttons catch up on their next slot, form or
            -- cooldown event, and the bars are laid out again over the shown buttons.
            local deferred = InCombatLockdown()
            OutOfCombat(function()
                RestoreBlizzardBars()
                if deferred and addon.RefreshMainbarsSystem then
                    addon.RefreshMainbarsSystem()
                end
            end)
        end
        if owned.actionbars and cfg.bartender_last_bars ~= "bartender4" and cfg.bartender_layout then
            SeedBartenderLayout(bartender, cfg.bartender_layout)
        end
    end

    cfg.bartender_last_bars = owned.actionbars and "bartender4" or nil
    if runsBars then
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("PLAYER_LOGOUT")
        watcher:SetScript("OnEvent", function() compatibility:SnapshotBarLayout() end)
    elseif not owned.actionbars then
        -- Stock bars this session: a layout from before would be out of date by the time Bartender4 comes.
        cfg.bartender_layout = nil
    end
end

-- Whether Bartender4 runs any part this session.
function compatibility:BartenderRunsAny()
    if not self.bartenderOwned then return false end
    for _, part in ipairs(BARTENDER_PARTS) do
        if self.bartenderOwned[part.key] then return true end
    end
    return false
end

-- Editor mode moves Bartender4's bars too, through its own unlock.
function compatibility:SetBartenderUnlocked(unlocked)
    local bartender = _G.Bartender4
    if not (self:BartenderRunsAny() and bartender and bartender.Unlock and bartender.Lock) then return end
    if unlocked then
        bartender:Unlock()
    else
        bartender:Lock()
    end
end

-- Runs from RefreshConfig, before any bar module applies. Only modules switched off here come back,
-- so a bar the player had turned off themselves stays off once Bartender4 is gone.
function compatibility:ApplyBartenderHandoff()
    local cfg = GetCompatibilityConfig()
    local modules = cfg and addon.db.profile.modules
    if not modules then return end

    -- "Use Bartender4" turned off, from before the parts were split.
    if cfg.bartender_bars ~= nil then
        if cfg.bartender_bars == false then
            cfg.bartender_actionbars = "dragonui"
        end
        cfg.bartender_bars = nil
    end

    -- The first run is the load; the modules that read this build once, so it holds until a reload.
    local firstRun = self.bartenderOwned == nil
    if firstRun then
        self.bartenderOwned = {}
        for _, part in ipairs(BARTENDER_PARTS) do
            self.bartenderOwned[part.key] = self:BartenderOwns(part.key)
        end
        self.bartenderActive = self.bartenderOwned.actionbars
    end

    -- Both ways only for what this session's split already says: a profile switch mid-session waits for the
    -- reload, or a part would be left with neither addon's bars.
    local handed = cfg.bartender_handed or {}
    for _, part in ipairs(BARTENDER_PARTS) do
        local owns = self:BartenderOwns(part.key)
        if owns and self.bartenderOwned[part.key] then
            for _, name in ipairs(part.modules) do
                local moduleCfg = modules[name]
                if moduleCfg and moduleCfg.enabled then
                    moduleCfg.enabled = false
                    handed[name] = true
                    self.bartenderJustHanded = self.bartenderJustHanded or {}
                    self.bartenderJustHanded[part.key] = true
                end
            end
        elseif not owns and not self.bartenderOwned[part.key] then
            for _, name in ipairs(part.modules) do
                if handed[name] then
                    if modules[name] then
                        modules[name].enabled = true
                    end
                    handed[name] = nil
                end
            end
        end
    end
    cfg.bartender_handed = next(handed) and handed or nil

    -- After the hand-over: a micro menu coming back is its own keeper, so Bartender4's must see it on.
    if firstRun then
        self:SetupBartenderSession(cfg)
    end
end

-- ============================================================================
-- EVENT SYSTEM (ADDON SPECIFIC)
-- ============================================================================

local activeEventFrames = {}

local function RegisterEventsForAddon(addonName, addonInfo)
    if not addonInfo.listenToRaidEvents then
        return
    end
    
    local eventFrame = CreateFrame("Frame", "DragonUI_Events_" .. addonName)
    eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")

    eventFrame:SetScript("OnEvent", function(self, event)
        if compatibility.raidUpdateHandlers and compatibility.raidUpdateHandlers[addonName] then
            compatibility.raidUpdateHandlers[addonName]()
        end
    end)
    
    activeEventFrames[addonName] = eventFrame
end

local function UnregisterEventsForAddon(addonName)
    if activeEventFrames[addonName] then
        activeEventFrames[addonName]:UnregisterAllEvents()
        activeEventFrames[addonName] = nil
    end
end

-- ============================================================================
-- CORE DETECTION & EXECUTION
-- ============================================================================

local function ValidateRegistryEntry(addonName, addonInfo)
    if not addonInfo.name or not addonInfo.reason or not addonInfo.behavior then
        return false
    end
    return true
end

local function ProcessAddon(addonName, addonInfo)
    if not ValidateRegistryEntry(addonName, addonInfo) then
        return
    end

    if addonInfo.checkOnce and state.processedAddons[addonName] then
        return
    end

    if addonInfo.checkOnce then
        state.processedAddons[addonName] = true
    end

    state.activeAddons[addonName] = addonInfo

    if addonInfo.behavior then
        addonInfo.behavior(addonName, addonInfo)
    end
    
    if addonInfo.listenToRaidEvents then
        RegisterEventsForAddon(addonName, addonInfo)
    end
end

local function ScanForRegisteredAddons()
    local foundAddons = {}
    
    for addonName, addonInfo in pairs(ADDON_REGISTRY) do
        if IsRegistryAddonLoaded(addonName) then
            foundAddons[addonName] = addonInfo
        end
    end
    
    return foundAddons
end

-- ============================================================================
-- MAIN EVENT SYSTEM
-- ============================================================================

local function InitializeEvents()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("CVAR_UPDATE")

    eventFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
        if event == "ADDON_LOADED" then
            if loadedAddonName then
                addonLoadCache[loadedAddonName] = true
                addonLoadCache[string.lower(loadedAddonName)] = true
            end

            if loadedAddonName == "DragonUI" then
                -- Auto-reset SexyMap mode ONLY if SexyMap is completely uninstalled
                -- (not in the addon list at all). If it's just disabled, the user's
                -- chosen mode should persist so it applies when they re-enable it.
                local minimapCfg = addon.db and addon.db.profile and addon.db.profile.modules
                    and addon.db.profile.modules.minimap
                if minimapCfg and minimapCfg.sexymap_mode then
                    local sexyMapExists = false
                    for i = 1, GetNumAddOns() do
                        local name = GetAddOnInfo(i)
                        if name and name:lower() == "sexymap" then
                            sexyMapExists = true
                            break
                        end
                    end
                    if not sexyMapExists then
                        local oldMode = minimapCfg.sexymap_mode
                        minimapCfg.sexymap_mode = nil
                        -- Restore addon_button_skin if sexymap/hybrid mode had disabled it
                        if oldMode and oldMode ~= "dragonui" and addon.db.profile.minimap then
                            addon.db.profile.minimap.addon_button_skin = true
                        end
                    end
                end

                DelayedCall(function()
                    local foundAddons = ScanForRegisteredAddons()
                    for addonName, addonInfo in pairs(foundAddons) do
                        ProcessAddon(addonName, addonInfo)
                    end
                end, CONFIG.scanDelay)

            else
                local registryKey = ResolveRegistryKey(loadedAddonName)
                if registryKey then
                DelayedCall(function()
                        ProcessAddon(registryKey, ADDON_REGISTRY[registryKey])
                end, CONFIG.warningDelay)
                end
            end

        elseif event == "PLAYER_LOGIN" then
            state.initialized = true

            if not InterfaceSettingsFixer.initialized then
                InterfaceSettingsFixer.initialized = true
                ScheduleInterfaceSettingsScan(0.5)
            end

            local handed, owned = compatibility.bartenderJustHanded, compatibility.bartenderOwned
            if handed and owned then
                if handed.actionbars and owned.actionbars then
                    print("|cFF00CCFFDragonUI:|r " .. L["Bartender4 now runs your action bars. DragonUI keeps the XP bars. Switch this in DragonUI options > Modules."])
                end
                if handed.micromenu and owned.micromenu then
                    print("|cFF00CCFFDragonUI:|r " .. L["Bartender4 now runs your micro menu and bags. Switch this in DragonUI options > Modules."])
                end
            end

        elseif event == "CVAR_UPDATE" then
            local cvarName = loadedAddonName
            if InterfaceSettingsFixer.initialized and IsFixerMonitoredCVar(cvarName) then
                ScheduleInterfaceSettingsScan(0.2)
            end
        end
    end)
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

local function InitializeCommands()
    SLASH_DRAGONUI_COMPAT1 = "/duicomp"
    
    SlashCmdList["DRAGONUI_COMPAT"] = function(msg)
        local cmd = msg and msg:lower():trim() or ""
        
        if cmd == "sexymap reset" then
            -- Reset SexyMap mode choice — will re-prompt on next login
            compatibility:ResetSexyMapMode()
            print("|cFF00CCFFDragonUI:|r " .. L["SexyMap compatibility mode has been reset. Reload UI to choose again."])
            return
        elseif cmd == "sexymap" then
            -- Show current SexyMap mode
            local mode = compatibility:GetSexyMapMode()
            if mode then
                print("|cFF00CCFFDragonUI:|r " .. string.format(L["Current SexyMap mode: |cFFFFFF00%s|r"], mode))
            else
                print("|cFF00CCFFDragonUI:|r " .. L["No SexyMap mode selected (SexyMap not detected or not yet chosen)."])
            end
            return
        end
        
        -- Default: list loaded addons
        print("|cFF00CCFF" .. L["DragonUI Compatibility:"] .. "|r")
        print("  /duicomp sexymap - " .. L["Show current SexyMap compatibility mode"])
        print("  /duicomp sexymap reset - " .. L["Reset SexyMap mode choice (re-prompts on reload)"])
        print("")
        print(L["Loaded addons:"])
        for i = 1, GetNumAddOns() do
            local name = select(1, GetAddOnInfo(i))
            local title = GetAddOnMetadata(i, "Title") or "Unknown"
            local loaded = IsAddOnLoaded(i)
            if loaded then
                print("  - " .. title .. " |cFFFFFF00(" .. name .. ")|r")
            end
        end
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function compatibility:RegisterAddon(addonName, addonInfo)
    if not ValidateRegistryEntry(addonName, addonInfo) then
        return false
    end
    
    ADDON_REGISTRY[addonName] = addonInfo
    
    if IsAddonLoadedCached(addonName) then
        ProcessAddon(addonName, addonInfo)
    end
    
    return true
end

function compatibility:UnregisterAddon(addonName)
    if ADDON_REGISTRY[addonName] then
        UnregisterEventsForAddon(addonName)
        state.activeAddons[addonName] = nil
        if compatibility.raidUpdateHandlers then
            compatibility.raidUpdateHandlers[addonName] = nil
        end
        
        ADDON_REGISTRY[addonName] = nil
        
        return true
    end
    return false
end

function compatibility:IsRegistered(addonName)
    return ADDON_REGISTRY[addonName] ~= nil
end

function compatibility:GetActiveAddons()
    return state.activeAddons
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

InitializeEvents()
InitializeCommands()

-- ============================================================================
-- OPTIONS PANEL: SexyMap mode selector (registered from compatibility module
-- so it is visible regardless of minimap module state)
-- ============================================================================

local function IsSexyMapInstalled()
    -- Check if SexyMap exists in the addon list at all (enabled or disabled).
    -- We do NOT check enabled state because DragonUI itself disables SexyMap
    -- in "DragonUI Only" mode, and the user needs the options to switch back.
    for i = 1, GetNumAddOns() do
        local name = GetAddOnInfo(i)
        if name and name:lower() == "sexymap" then
            return true
        end
    end
    return false
end

-- Cache result at load time (addon list doesn't change mid-session)
local sexyMapInstalled = IsSexyMapInstalled()
-- Expose on addon object so options panel can read it without re-detecting
addon._sexyMapInstalled = sexyMapInstalled

if sexyMapInstalled then
    StaticPopupDialogs["DRAGONUI_SEXYMAP_MODE_RELOAD"] = {
        text = "|cFF00CCFFDragonUI|r\n\n" .. L["Minimap mode changed. Reload UI to apply?"],
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    }
end