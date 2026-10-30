-- Run from the repository root with Lua 5.1.
local loaded = {}
local frames = {}
local combat = false
function IsAddOnLoaded(name) return loaded[name] or false end
function GetNumAddOns() return 0 end
function GetAddOnInfo() return nil end
function GetCVar() return nil end
function InCombatLockdown() return combat end
function UnitHasVehicleUI() return false end
local hooks = {}
function hooksecurefunc(name, fn) hooks[name] = fn end
function CreateFrame()
    local frame = { scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    frames[#frames + 1] = frame
    return frame
end
StaticPopupDialogs, SlashCmdList = {}, {}
local printed = {}
function print(text) printed[#printed + 1] = text end

local function fire(event)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame, event) end
    end
end

-- The screen: UIParent at 0.8 effective scale, 1280 x 960 units.
UIParent = {
    GetEffectiveScale = function() return 0.8 end,
    GetWidth = function() return 1280 end,
    GetHeight = function() return 960 end,
}

-- Slots with an action; HasAction reads these.
local actions = {}
function HasAction(slot) return actions[slot] or false end

local function newBar(visible)
    return { IsVisible = function() return visible end }
end

-- Stock action buttons as Bartender4's HideBlizzard leaves them: hidden, every event gone. On a reload a slot
-- with an action still has eventsRegistered set. `top` past DragonUI's count is the off-screen parking spot.
local function newButton(name, parent, slot, left, bottom, size, scale)
    local button = { name = name, action = slot, shown = false, events = {}, attributes = { showgrid = 0 } }
    if slot and actions[slot] then button.eventsRegistered = true end
    function button:RegisterEvent(event) self.events[event] = true end
    function button:Show() self.shown = true end
    function button:GetParent() return parent end
    -- An empty slot is hidden but keeps its spot in the grid.
    function button:IsVisible() return parent.IsVisible() and slot ~= nil and actions[slot] == true end
    function button:GetEffectiveScale() return scale end
    function button:GetLeft() return left end
    function button:GetRight() return left + size end
    function button:GetBottom() return bottom end
    function button:GetTop() return bottom + size end
    function button:GetAttribute(key) return self.attributes[key] end
    function button:SetAttribute(key, value) self.attributes[key] = value end
    _G[name] = button
    return button
end

-- DragonUI's layout, at 0.8 of UIParent's scale (a 36 px button is 28.8 units): main bar one row of 12;
-- bottom left two rows of 6 with spells in 1-4 only; bottom right and left turned off; right bar a column of
-- 8 (9-12 parked); pet and stance bars rows of 10 with a pet out. Positions are in each button's own units.
local function layOutButtons()
    actions = {}
    for slot = 1, 12 do actions[slot] = true end
    for slot = 61, 64 do actions[slot] = true end
    for slot = 25, 32 do actions[slot] = true end
    local main, left6, off, right = newBar(true), newBar(true), newBar(false), newBar(true)
    local pet, stance = newBar(true), newBar(true)
    for i = 1, 12 do
        newButton("ActionButton" .. i, main, i, 400 + (i - 1) * 40, 30, 36, 0.64)
        local row, col = math.floor((i - 1) / 6), (i - 1) % 6
        newButton("MultiBarBottomLeftButton" .. i, left6, 60 + i, 500 + col * 40, 120 - row * 40, 36, 0.64)
        newButton("MultiBarBottomRightButton" .. i, off, 48 + i, 0, 0, 36, 0.64)
        if i <= 8 then
            newButton("MultiBarRightButton" .. i, right, 24 + i, 1500, 600 - (i - 1) * 40, 36, 0.64)
        else
            newButton("MultiBarRightButton" .. i, right, 24 + i, 0, -1100, 36, 0.64)
        end
        newButton("MultiBarLeftButton" .. i, off, 36 + i, 0, 0, 36, 0.64)
    end
    for i = 1, 10 do
        local button = newButton("PetActionButton" .. i, pet, nil, 600 + (i - 1) * 34, 300, 30, 0.64)
        button.IsVisible = function() return true end
        local form = newButton("ShapeshiftButton" .. i, stance, nil, 600 + (i - 1) * 34, 400, 30, 0.64)
        form.IsVisible = function() return true end
    end
end
layOutButtons()

local mainMenuShown = false
MainMenuBar = { Show = function() mainMenuShown = true end }
PossessBarFrame = { events = {} }
function PossessBarFrame:RegisterEvent(event) self.events[event] = true end
local possessUpdates = 0
function PossessBar_Update() possessUpdates = possessUpdates + 1 end
MultiActionBar_UpdateGrid = function() end -- Bartender4's empty stand-in
local bartenderGrid = MultiActionBar_UpdateGrid
NUM_MULTIBAR_BUTTONS = 12
local grids = {}
function ActionButton_ShowGrid(button) grids[button.name] = true end
function ActionButton_HideGrid(button) grids[button.name] = false end

-- Bartender4's AceAddon modules as its OnInitialize leaves them: state set, not yet enabled.
local function newBartenderModule(enabled, profile)
    profile = profile or {}
    profile.enabled = enabled
    local module = { db = { profile = profile }, enabledState = enabled, live = false }
    function module:SetEnabledState(state) self.enabledState = state end
    function module:IsEnabled() return self.live end
    function module:Disable() self.live = false end
    function module:Enable() self.live = true end
    function module:ToggleModule(info, value)
        if value ~= nil then self.db.profile.enabled = value end
        self.live = self.db.profile.enabled
    end
    return module
end

local bartenderModules
local unlocked
local function newBartender(blizzardVehicle)
    local actionbars = {}
    for i = 1, 10 do actionbars[i] = { enabled = i < 7, position = { scale = 1, growVertical = "DOWN" } } end
    bartenderModules = {
        ActionBars = newBartenderModule(true, { actionbars = actionbars }),
        PetBar = newBartenderModule(true, { position = {} }),
        StanceBar = newBartenderModule(true, { position = {} }),
        MultiCast = newBartenderModule(true),
        Vehicle = newBartenderModule(true),
        BlizzardArt = newBartenderModule(false),
        MicroMenu = newBartenderModule(true),
        BagBar = newBartenderModule(true),
        XPBar = newBartenderModule(true),
        RepBar = newBartenderModule(false),
    }
    unlocked = nil
    local vehicleCalls = {}
    Bartender4 = {
        db = { profile = { blizzardVehicle = blizzardVehicle } },
        vehicleCalls = vehicleCalls,
        GetModule = function(_, name) return bartenderModules[name] end,
        UpdateBlizzardVehicle = function(self)
            vehicleCalls[#vehicleCalls + 1] = self.db.profile.blizzardVehicle
            -- Its "off" branch enables the vehicle bar module directly.
            local vehicle = bartenderModules.Vehicle
            if not self.db.profile.blizzardVehicle and vehicle.db.profile.enabled then vehicle:Enable() end
        end,
        Unlock = function() unlocked = true end,
        Lock = function() unlocked = false end,
    }
end
newBartender(false)

local HANDED = { "vehicle", "stance", "petbar", "multicast", "buttons" }
local KEPT = { "mainbars", "noop", "micromenu", "keypress", "minimap" }
local BAR_MODULES = { "ActionBars", "PetBar", "StanceBar", "MultiCast", "Vehicle", "BlizzardArt" }

local function newProfile()
    local modules = {}
    for _, name in ipairs(HANDED) do modules[name] = { enabled = true } end
    for _, name in ipairs(KEPT) do modules[name] = { enabled = true } end
    -- The database defaults.
    return { modules = modules, compatibility = { bartender_actionbars = "bartender4", bartender_micromenu = "dragonui" } }
end

local function newAddon(profile)
    local addon = {
        db = { profile = profile or newProfile() },
        L = setmetatable({}, { __index = function(_, key) return key end }),
        After = function() end,
    }
    function addon:IsModuleEnabled(name)
        local cfg = self.db.profile.modules[name]
        return cfg and cfg.enabled or false
    end
    frames = {}
    assert(loadfile('DragonUI/modules/compatibility.lua'))('DragonUI', addon)
    addon.compatibility:ApplyBartenderHandoff()
    return addon, addon.compatibility, addon.db.profile.modules, addon.db.profile.compatibility
end

local function login()
    printed = {}
    fire('PLAYER_LOGIN')
    local lines = {}
    for _, text in ipairs(printed) do
        if text:find('action bars', 1, true) then lines.actionbars = true end
        if text:find('micro menu', 1, true) then lines.micromenu = true end
    end
    return lines
end

-- Without Bartender4 nothing changes, and nothing of it is touched.
local addon, compat, modules, cfg = newAddon()
assert(compat.bartenderActive == false)
for _, name in ipairs(HANDED) do assert(modules[name].enabled, name .. ' changed without Bartender4') end
assert(cfg.bartender_handed == nil)
assert(next(login()) == nil, 'login line without Bartender4')
assert(not ActionButton1.events.PLAYER_ENTERING_WORLD, 'stock bars restored without Bartender4')

-- With Bartender4: the bars go to it, the XP bars (mainbars, noop), micro menu and key press stay.
loaded.Bartender4 = true
addon, compat, modules, cfg = newAddon()
assert(compat.bartenderActive == true and compat.bartenderOwned.micromenu == false)
for _, name in ipairs(HANDED) do assert(modules[name].enabled == false, name .. ' still on with Bartender4') end
for _, name in ipairs(KEPT) do assert(modules[name].enabled, name .. ' was switched off') end
for _, name in ipairs(HANDED) do assert(cfg.bartender_handed[name]) end
local lines = login()
assert(lines.actionbars and not lines.micromenu, 'login line wrong on the load that handed the bars over')
assert(not ActionButton1.events.PLAYER_ENTERING_WORLD, 'stock bars restored under Bartender4')

-- Bartender4's micro menu, bag bar and XP/Rep bars stay off without touching its saved settings;
-- its bars are untouched.
local micro, bags = bartenderModules.MicroMenu, bartenderModules.BagBar
assert(micro.enabledState == false and bags.enabledState == false)
assert(bartenderModules.XPBar.enabledState == false and bartenderModules.RepBar.enabledState == false)
assert(micro.db.profile.enabled and bags.db.profile.enabled, 'Bartender4 settings were changed')
for _, name in ipairs(BAR_MODULES) do
    assert(bartenderModules[name].enabledState == bartenderModules[name].db.profile.enabled, name .. ' changed')
end
micro:ToggleModule()             -- Bartender4 profile switch
micro:ToggleModule(nil, true)    -- its options checkbox
assert(not micro:IsEnabled(), 'Bartender4 micro menu came back')
assert(micro.db.profile.enabled == true)

-- Editor mode unlocks Bartender4's bars with DragonUI's movers.
compat:SetBartenderUnlocked(true)
assert(unlocked == true)
compat:SetBartenderUnlocked(false)
assert(unlocked == false)

-- A later RefreshConfig (profile switch) keeps the load's decision.
cfg.bartender_actionbars = "dragonui"
compat:ApplyBartenderHandoff()
assert(compat.bartenderActive == true, 'active state changed mid-session')
assert(modules.stance.enabled == false, 'bars restored mid-session, over Bartender4')
assert(cfg.bartender_handed.stance, 'hand-off record dropped before the next load')
cfg.bartender_actionbars = "bartender4"

-- The next load finds nothing new to hand over and stays quiet.
local savedProfile = addon.db.profile
addon, compat, modules, cfg = newAddon(savedProfile)
assert(cfg.bartender_handed.stance and cfg.bartender_handed.buttons)
assert(next(login()) == nil, 'login line repeated on a load that changed nothing')

-- Bartender4 removed: the handed modules come back.
loaded.Bartender4 = false
addon, compat, modules, cfg = newAddon(savedProfile)
for _, name in ipairs(HANDED) do assert(modules[name].enabled, name .. ' not restored') end
assert(cfg.bartender_handed == nil)

-- Action bars set to DragonUI with Bartender4 loaded: DragonUI's bars come back, Bartender4's whole bar set
-- stays off (its art too), and the stock buttons its OnInitialize stripped work again.
loaded.Bartender4 = true
newBartender(true)
addon, compat, modules, cfg = newAddon(savedProfile)
assert(modules.stance.enabled == false)
cfg.bartender_actionbars = "dragonui"
newBartender(true)
layOutButtons()
addon, compat, modules, cfg = newAddon(savedProfile)
assert(not compat:BartenderOwnsBars() and compat.bartenderActive == false)
assert(modules.stance.enabled and modules.buttons.enabled)
assert(cfg.bartender_handed == nil)
for _, name in ipairs(BAR_MODULES) do
    assert(bartenderModules[name].enabledState == false, 'Bartender4 ' .. name .. ' left on next to DragonUI bars')
end
assert(bartenderModules.ActionBars.db.profile.enabled, 'Bartender4 settings were changed')
-- Events only: no stock handler run and no field written from addon code (that would taint the buttons).
assert(ActionButton1.events.PLAYER_ENTERING_WORLD and ActionButton1.events.ACTIONBAR_SLOT_CHANGED)
assert(ActionButton1.events.ACTIONBAR_UPDATE_COOLDOWN, 'per-action events left off after a reload')
assert(ActionButton1.eventsRegistered == true and ActionButton1.shown)
local empty = MultiBarBottomLeftButton12
assert(empty.events.PLAYER_ENTERING_WORLD and not empty.events.ACTIONBAR_UPDATE_COOLDOWN, 'multi bar buttons not restored')
assert(empty.eventsRegistered == nil and not empty.shown, 'empty slot shown')
assert(mainMenuShown, 'MainMenuBar left hidden')
assert(PossessBarFrame.events.UNIT_AURA and PossessBarFrame.events.UPDATE_BONUS_ACTIONBAR)
assert(possessUpdates == 0, 'possess bar updated from addon code')
assert(not PossessBarFrame.events.ACTIONBAR_PAGE_CHANGED, 'possess bar page event back with noop on')
assert(MultiActionBar_UpdateGrid ~= bartenderGrid)
MultiActionBar_UpdateGrid("MultiBarRight", true)
assert(grids.MultiBarRightButton1 and grids.MultiBarRightButton12)
-- ActionButton_ShowGrid skips the count outside secure code, so the copy keeps it.
assert(MultiBarRightButton1.attributes.showgrid == 1)
MultiActionBar_UpdateGrid("MultiBarRight", false)
MultiActionBar_UpdateGrid("MultiBarRight", false)
assert(MultiBarRightButton1.attributes.showgrid == 0 and grids.MultiBarRightButton1 == false)
-- In combat (the spellbook closing) nothing is shown or hidden; the grid catches up when combat ends.
MultiActionBar_UpdateGrid("MultiBarRight", true)
grids.MultiBarRightButton1 = nil
combat = true
MultiActionBar_UpdateGrid("MultiBarRight", false)
assert(grids.MultiBarRightButton1 == nil and MultiBarRightButton1.attributes.showgrid == 1, 'grid hidden in combat')
combat = false
fire('PLAYER_REGEN_ENABLED')
assert(grids.MultiBarRightButton1 == false and MultiBarRightButton1.attributes.showgrid == 0)
assert(type(hooks.TalentFrame_LoadUI) == 'function', 'talent frame event not put back')
-- "Use Blizzard Vehicle UI" was on: applied once more as off, its setting kept.
assert(Bartender4.vehicleCalls[1] == false and Bartender4.db.profile.blizzardVehicle == true)
Bartender4:UpdateBlizzardVehicle()
assert(Bartender4.vehicleCalls[2] == false, 'Blizzard vehicle UI let back on')
-- Its "off" branch enables Bartender4's vehicle bar directly; it stays off next to DragonUI's bars.
assert(not bartenderModules.Vehicle:IsEnabled(), 'Bartender4 vehicle bar back next to DragonUI bars')
-- Bartender4 runs nothing: editor mode leaves it alone.
unlocked = nil
compat:SetBartenderUnlocked(true)
assert(unlocked == nil)

-- At logout DragonUI's layout is kept; the next load that gives Bartender4 the bars puts them there.
fire('PLAYER_LOGOUT')
local layout = cfg.bartender_layout
assert(layout and layout.bar1 and layout.bar6 and layout.bar3, 'layout not saved at logout')
assert(layout.bar5.hidden and layout.bar4.hidden, 'hidden bars measured')
-- Main bar: 12 buttons of 28.8 units, 3.2 apart, from x 320, top 52.8. Bartender4's bar is a 1x1 frame at its
-- top-left corner, 5 left of and 3 above its first button, in bar units (scale 0.8).
local function near(a, b) return math.abs(a - b) < 0.01 end
assert(near(layout.bar1.x, 320 - 4), layout.bar1.x)
assert(near(layout.bar1.y, 52.8 + 2.4 - 960), layout.bar1.y)
assert(near(layout.bar1.scale, 0.8) and layout.bar1.rows == 1 and layout.bar1.padding == 4 and layout.bar1.buttons == 12)
-- Empty slots still count (laid out, just hidden); parked ones past DragonUI's count do not.
assert(layout.bar6.rows == 2 and layout.bar6.buttons == 12 and not layout.bar6.hidden)
assert(layout.bar3.rows == 8 and layout.bar3.buttons == 8)
-- Pet buttons are 30 px in Bartender4: 24 units is scale 0.8, not 0.67.
assert(layout.pet and near(layout.pet.scale, 0.8) and layout.pet.padding == 4 and near(layout.pet.x, 480 - 4))
assert(layout.stance and near(layout.stance.scale, 0.8), 'stance bar sized as action buttons')

cfg.bartender_actionbars = "bartender4"
newBartender(false)
addon, compat, modules, cfg = newAddon(savedProfile)
local bars = bartenderModules.ActionBars.db.profile.actionbars
assert(bars[1].position.point == "TOPLEFT" and near(bars[1].position.x, layout.bar1.x))
assert(bars[1].position.scale == layout.bar1.scale and bars[1].position.growVertical == "DOWN")
assert(bars[1].position.growHorizontal == "RIGHT" and bars[3].buttons == 8)
local petProfile = bartenderModules.PetBar.db.profile
assert(petProfile.position.point == "TOPLEFT" and near(petProfile.position.scale, 0.8))
assert(bars[1].padding == 4 and bars[6].rows == 2 and bars[3].rows == 8)
assert(bars[5].enabled == false and bars[4].enabled == false, 'Bartender4 bar left on where DragonUI had none')
assert(bars[2].enabled == false, 'Bartender4 second bar left on')
assert(bars[6].enabled and bars[3].enabled)
assert(cfg.bartender_last_bars == "bartender4")
-- Seeded once: later moves in Bartender4 are its own.
bars[1].position.x = 12
addon, compat, modules, cfg = newAddon(savedProfile)
assert(bars[1].position.x == 12, 'Bartender4 bar moved back on a later load')

-- A reload in combat restores the stock bars once combat ends.
cfg.bartender_actionbars = "dragonui"
newBartender(true)
layOutButtons()
combat = true
local refreshed = 0
addon, compat, modules, cfg = newAddon(savedProfile)
addon.RefreshMainbarsSystem = function() refreshed = refreshed + 1 end
assert(not ActionButton1.events.PLAYER_ENTERING_WORLD and not ActionButton1.shown, 'stock bars touched in combat')
assert(#Bartender4.vehicleCalls == 0, 'vehicle UI state drivers changed in combat')
combat = false
fire('PLAYER_REGEN_ENABLED')
assert(Bartender4.vehicleCalls[1] == false)
assert(ActionButton1.events.ACTIONBAR_SLOT_CHANGED and ActionButton1.shown)
assert(refreshed == 1, 'bars not laid out again after combat')

-- A profile switch mid-session to one that gives Bartender4 the bars waits for the reload: DragonUI's stay.
cfg.bartender_actionbars = "bartender4"
compat:ApplyBartenderHandoff()
assert(modules.stance.enabled and cfg.bartender_handed == nil, 'bars handed over mid-session, none left running')
-- Nor does it bring back modules the saved choice still hands over.
modules.petbar.enabled, cfg.bartender_handed = false, { petbar = true }
compat:ApplyBartenderHandoff()
assert(modules.petbar.enabled == false and cfg.bartender_handed.petbar, 'handed module restored against the saved choice')
modules.petbar.enabled, cfg.bartender_handed = true, nil
cfg.bartender_actionbars = "dragonui"

-- Stock bars this session (main bars module off): the saved layout is dropped, it would be out of date.
savedProfile.modules.mainbars.enabled = false
addon, compat, modules, cfg = newAddon(savedProfile)
assert(cfg.bartender_layout == nil)
savedProfile.modules.mainbars.enabled = true

-- Micro menu and bags set to Bartender4: DragonUI's module is handed over, Bartender4's are left alone.
cfg.bartender_micromenu = "bartender4"
newBartender(false)
addon, compat, modules, cfg = newAddon(savedProfile)
assert(compat.bartenderOwned.micromenu and not compat.bartenderActive)
assert(modules.micromenu.enabled == false and cfg.bartender_handed.micromenu)
assert(compat:BartenderTakesModule("micromenu") and not compat:BartenderTakesModule("stance"))
assert(bartenderModules.MicroMenu.enabledState == true and bartenderModules.BagBar.enabledState == true)
assert(bartenderModules.ActionBars.enabledState == false, 'Bartender4 bars back next to DragonUI bars')
lines = login()
assert(lines.micromenu and not lines.actionbars)
compat:SetBartenderUnlocked(true)
assert(unlocked == true, 'editor mode skipped Bartender4 micro menu')
-- And back: the micro menu returns on the next load.
cfg.bartender_micromenu = "dragonui"
newBartender(false)
addon, compat, modules, cfg = newAddon(savedProfile)
assert(modules.micromenu.enabled and cfg.bartender_handed == nil)
assert(bartenderModules.MicroMenu.enabledState == false and bartenderModules.BagBar.enabledState == false,
    'both micro menus on the load that gives DragonUI its micro menu back')

-- "Use Bartender4" turned off before the split becomes DragonUI action bars.
local legacy = newProfile()
legacy.compatibility = { bartender_bars = false }
newBartender(false)
addon, compat, modules, cfg = newAddon(legacy)
assert(cfg.bartender_bars == nil and cfg.bartender_actionbars == "dragonui")
assert(compat.bartenderActive == false and modules.stance.enabled)

-- A bar the player turned off before Bartender4 arrived stays off after it leaves.
local profile = newProfile()
profile.modules.stance.enabled = false
addon, compat, modules, cfg = newAddon(profile)
assert(not cfg.bartender_handed.stance)
loaded.Bartender4 = false
addon, compat, modules, cfg = newAddon(profile)
assert(modules.stance.enabled == false and modules.petbar.enabled)

-- With DragonUI's micro menu or main bars module off, Bartender4 keeps its own micro menu or XP bar.
loaded.Bartender4 = true
newBartender(false)
profile = newProfile()
profile.modules.micromenu.enabled = false
profile.modules.mainbars.enabled = false
addon = newAddon(profile)
assert(bartenderModules.MicroMenu.enabledState == true, 'Bartender4 micro menu blocked with no DragonUI one')
assert(bartenderModules.XPBar.enabledState == true, 'Bartender4 XP bar blocked with no DragonUI one')

io.write('bartender hand-off test passed\n')
