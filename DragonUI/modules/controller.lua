-- Licensed under the MIT License; see LICENSE.

-- Controller layout. With the controller DLL (wow-client-controller) next to Wow.exe, pressing a controller button
-- turns the main, bottom left and bottom right bars into the controller's: each slot shows the button and triggers
-- that use it, the slots of the trigger layer being held stand out and the rest dim, and the controller's own cross of
-- abilities steps aside since the bars now say the same thing. A button by the bars swaps back to the keyboard
-- layout, and while a controller is plugged in, swaps to the controller one again. Without the DLL there's no
-- C_Controller and none of this shows.
--
-- Everything here is our own frames and the hotkey text's alpha, so it works the same in combat. The controller only
-- hands out plain values and never calls into DragonUI; this file polls it.

local addon = select(2, ...)
local L = addon.L

local ControllerModule = { applied = false }

if addon.RegisterModule then
    addon:RegisterModule("controller", ControllerModule,
        L["Controller Layout"],
        L["Shows the controller's buttons on the action bars while a controller is in use."])
end

local BARS = {
    { key = "main", prefix = "ActionButton" },
    { key = "bottomleft", prefix = "MultiBarBottomLeftButton" },
    { key = "bottomright", prefix = "MultiBarBottomRightButton" },
}
local TRIGGERS = { BASE = {}, LT = { "LT" }, RT = { "RT" }, BOTH = { "LT", "RT" } }
local GLYPH_SIZE = 18
local TRIGGER_SIZE = 13
local DIM_ALPHA = 0.6
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SWAP_HEIGHT = 20

local overlays = {}      -- action button -> its overlay
local layout = "keyboard"
local wasActive = false
local paintedFamily, paintedLayer
local swap, mover

local function Settings()
    return addon:GetModuleConfig("controller")
end

-- Off while Bartender4 runs the action bars: DragonUI's buttons aren't the ones on screen then, so the controller keeps
-- its own cross.
local function Enabled()
    local compatibility = addon.compatibility
    if compatibility and compatibility.bartenderActive then return false end
    return addon:IsModuleEnabled("controller")
end

local function Api()
    return _G.C_Controller
end

-- ============================================================================
-- OVERLAYS
-- ============================================================================

local function MakeOverlay(button, position, layer)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    -- Above the cooldown spiral, which sits one level over the button.
    overlay:SetFrameLevel(button:GetFrameLevel() + 3)
    overlay:EnableMouse(false)

    local icon = _G[button:GetName() .. "Icon"] or button
    overlay.shade = overlay:CreateTexture(nil, "ARTWORK")
    overlay.shade:SetAllPoints(icon)
    overlay.shade:SetTexture(WHITE)
    overlay.shade:SetVertexColor(0, 0, 0)

    overlay.glyph = overlay:CreateTexture(nil, "OVERLAY")
    overlay.glyph:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    overlay.glyph:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 3, 3)
    overlay.triggers = {}
    for index = 1, 2 do
        local trigger = overlay:CreateTexture(nil, "OVERLAY")
        trigger:SetSize(TRIGGER_SIZE, TRIGGER_SIZE)
        if index == 1 then
            trigger:SetPoint("RIGHT", overlay.glyph, "LEFT", 1, 0)
        else
            trigger:SetPoint("RIGHT", overlay.triggers[1], "LEFT", 1, 0)
        end
        overlay.triggers[index] = trigger
    end

    overlay.position, overlay.layer = position, layer
    overlay:Hide()
    return overlay
end

local function EnsureOverlays(api)
    for _, bar in ipairs(BARS) do
        for index = 1, 12 do
            local button = _G[bar.prefix .. index]
            if button and not overlays[button] then
                overlays[button] = MakeOverlay(button, api.GetBinding(bar.key, index))
            end
        end
    end
end

local function PaintGlyph(texture, api, name)
    local path, left, right, top, bottom = api.GetGlyph(name)
    if path then
        texture:SetTexture(path)
        texture:SetTexCoord(left, right, top, bottom)
        texture:Show()
    else
        texture:Hide()
    end
end

local function PaintGlyphs(api)
    for _, overlay in pairs(overlays) do
        if overlay.position then
            PaintGlyph(overlay.glyph, api, overlay.position)
        else
            overlay.glyph:Hide()
        end
        local triggers = TRIGGERS[overlay.layer] or TRIGGERS.BASE
        for index = 1, 2 do
            -- Right to left, so the order reads LT then RT.
            local name = triggers[#triggers - index + 1]
            if name then
                PaintGlyph(overlay.triggers[index], api, name)
            else
                overlay.triggers[index]:Hide()
            end
        end
    end
end

-- What the buttons do right now stays bright; everything else dims.
local function PaintLayer(held)
    for _, overlay in pairs(overlays) do
        overlay.shade:SetAlpha((overlay.position and overlay.layer == held) and 0 or DIM_ALPHA)
    end
end

-- Whether the controller layout has this button's hotkey text hidden; buttons.lua asks before it shows one.
function addon.ControllerOwnsHotkey(button)
    return layout == "controller" and overlays[button] ~= nil and overlays[button].position ~= nil
end

local function ApplyHotkeys()
    for button in pairs(overlays) do
        local hotkey = _G[button:GetName() .. "HotKey"]
        if hotkey then
            hotkey:SetAlpha(addon.ControllerOwnsHotkey(button) and 0 or 1)
        end
    end
    -- Puts back the keyboard text exactly as the Buttons settings have it (some hide it).
    if layout ~= "controller" and addon.RefreshAllHotkeys then
        addon.RefreshAllHotkeys()
    end
end

-- ============================================================================
-- SWAP BUTTON
-- ============================================================================

local function UpdateSwapButton()
    if not swap then return end
    swap:SetText(layout == "controller" and L["Keyboard"] or L["Controller"])
    swap:SetWidth(swap:GetFontString():GetStringWidth() + 20)
    mover:SetSize(swap:GetWidth(), SWAP_HEIGHT)
end

local function SetLayout(kind)
    if layout == kind then return end
    layout = kind
    local api = Api()
    if api then
        api.SetBarsShown(kind == "controller")
        if kind == "controller" then EnsureOverlays(api) end
    end
    paintedFamily, paintedLayer = nil, nil
    for button, overlay in pairs(overlays) do
        if kind == "controller" then
            -- The bars re-level their buttons now and then (editor mode, the gryphons), so check each time.
            overlay:SetFrameLevel(button:GetFrameLevel() + 3)
            overlay:Show()
        else
            overlay:Hide()
        end
    end
    ApplyHotkeys()
    UpdateSwapButton()
end

local function GetWidget(create)
    local widgets = addon.db and addon.db.profile and addon.db.profile.widgets
    if widgets and create and not widgets.controllerswap then
        widgets.controllerswap = {}
    end
    return widgets and widgets.controllerswap
end

local function IsCustomPlaced()
    local widget = GetWidget()
    return widget and widget.custom_position and widget.posX ~= nil and widget.posY ~= nil or false
end

-- Default spot: just above the main bar's first button, clear of the buttons and the end cap art.
local function PlaceMover()
    mover:ClearAllPoints()
    local widget = GetWidget()
    local first = _G.ActionButton1
    if IsCustomPlaced() then
        mover:SetPoint("CENTER", UIParent, "CENTER", widget.posX, widget.posY)
    elseif first then
        mover:SetPoint("BOTTOMLEFT", first, "TOPLEFT", 0, 6)
    else
        mover:SetPoint("BOTTOM", UIParent, "BOTTOM", -300, 20)
    end
    -- The main bar's art sits 15 levels over its buttons.
    if first then
        swap:SetFrameLevel(first:GetFrameLevel() + 20)
    end
end

local function SaveMoved()
    local x, y = addon.GetAnchorOffset(mover, "CENTER")
    local widget = GetWidget(true)
    if not (x and widget) then return end
    widget.anchor, widget.posX, widget.posY = "CENTER", math.floor(x + 0.5), math.floor(y + 0.5)
    widget.custom_position = true
    PlaceMover()
end

local function ResetPosition()
    local widget = GetWidget()
    if widget then
        widget.custom_position, widget.anchor, widget.posX, widget.posY = false, nil, nil, nil
    end
    PlaceMover()
end

local function ControllerPluggedIn()
    local api = Api()
    return api ~= nil and (api.GetState()) and true or false
end

local function CreateSwapButton()
    if swap then return end
    mover = addon.CreateUIFrame(80, SWAP_HEIGHT, "ControllerSwapAnchor")
    mover:HookScript("OnDragStop", SaveMoved)

    swap = CreateFrame("Button", "DragonUIControllerSwap", UIParent, "UIPanelButtonTemplate")
    swap:SetHeight(SWAP_HEIGHT)
    swap:SetPoint("CENTER", mover, "CENTER", 0, 0)
    -- MEDIUM like the bars, so windows still cover it; PlaceMover lifts it over their art.
    swap:SetFrameStrata("MEDIUM")
    swap:SetNormalFontObject("GameFontNormalSmall")
    swap:SetHighlightFontObject("GameFontHighlightSmall")
    swap:SetText(L["Controller"])
    swap:SetScript("OnClick", function()
        if layout == "controller" then
            SetLayout("keyboard")
            -- The controller goes quiet too, until its next button press swaps back.
            local api = Api()
            if api then api.Rest() end
        else
            SetLayout("controller")
        end
    end)
    swap:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if layout == "controller" then
            GameTooltip:SetText(L["Keyboard layout"])
            GameTooltip:AddLine(L["Back to the keyboard's key labels. Pressing a controller button switches again."], 1, 1, 1, true)
        else
            GameTooltip:SetText(L["Controller layout"])
            GameTooltip:AddLine(L["Shows the controller's buttons on the action bars."], 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    swap:SetScript("OnLeave", GameTooltip_Hide)
    swap:Hide()

    PlaceMover()
    UpdateSwapButton()

    addon:RegisterEditableFrame({
        name = "controllerswap",
        frame = mover,
        hasTarget = ControllerPluggedIn,
        editorVisible = function() return Enabled() and ControllerPluggedIn() end,
        -- The editor hides the mover when there's no controller; it doesn't show it again by itself.
        showTest = function()
            mover:Show()
            swap:Show()
        end,
        onNudge = SaveMoved,
        resetPosition = ResetPosition,
        isDefaultPosition = function() return not IsCustomPlaced() end,
        module = ControllerModule,
    })
end

-- ============================================================================
-- DRIVER
-- ============================================================================

local function OnUpdate()
    local api = Api()
    if not api or not Enabled() then
        SetLayout("keyboard")
        if swap then swap:Hide() end
        return
    end

    local connected, active, family, held = api.GetState()
    -- A controller button pressed after keyboard play, or after the swap button handed back to the keyboard.
    if active and not wasActive then
        local settings = Settings()
        if not settings or settings.auto ~= false then SetLayout("controller") end
    end
    wasActive = active
    if not connected then SetLayout("keyboard") end

    CreateSwapButton()
    if connected and not (addon.EditorMode and addon.EditorMode:IsActive()) then
        swap:Show()
    elseif not connected then
        swap:Hide()
    end

    if layout == "controller" then
        if family ~= paintedFamily then
            paintedFamily = family
            PaintGlyphs(api)
        end
        if held ~= paintedLayer then
            paintedLayer = held
            PaintLayer(held)
        end
    end
end

local driver = CreateFrame("Frame")

function addon.ApplyControllerSystem()
    ControllerModule.applied = true
    driver:SetScript("OnUpdate", OnUpdate)
end

function addon.RestoreControllerSystem()
    ControllerModule.applied = false
    SetLayout("keyboard")
    if swap then swap:Hide() end
    driver:SetScript("OnUpdate", nil)
end

function addon.RefreshControllerSystem()
    -- A profile switch can bring another spot for the button.
    if mover then PlaceMover() end
    if Enabled() then
        addon.ApplyControllerSystem()
    else
        addon.RestoreControllerSystem()
    end
end

addon.ResetControllerSwapPosition = ResetPosition

-- C_Controller appears after addons load, so start polling once in the world, whatever the registry does first.
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if Enabled() then addon.ApplyControllerSystem() end
end)

-- For the checks in tools/controller_layout_test.lua.
addon._controllerLayout = {
    OnUpdate = OnUpdate,
    SetLayout = SetLayout,
    Layout = function() return layout end,
    Overlays = overlays,
    Swap = function() return swap end,
}
