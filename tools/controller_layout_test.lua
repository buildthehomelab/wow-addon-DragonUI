-- Run from the repository root with Lua 5.1.
-- Covers modules/controller.lua against a pretend controller DLL (C_Controller) and pretend action buttons.

local checks, failures = 0, 0
local function check(ok, what)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL: " .. what)
    end
end

-- Widgets: every method a no-op unless listed, so only what matters is modelled.
local Widget = {}
Widget.__index = function(_, key)
    local method = rawget(Widget, key)
    if method then return method end
    -- Methods start with a capital; any other missing field is plain nil, as on a real widget.
    if type(key) == "string" and key:match("^%u") then return function() end end
end
local function new(kind, name)
    local widget = setmetatable({ kind = kind, shown = true, alpha = 1, level = 1, scripts = {}, registered = {} }, Widget)
    if name then _G[name] = widget end
    return widget
end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:IsShown() return self.shown end
function Widget:SetAlpha(a) self.alpha = a end
function Widget:GetAlpha() return self.alpha end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:HookScript(name, fn) self.scripts[name] = fn end
function Widget:GetFrameLevel() return self.level end
function Widget:SetFrameLevel(level) self.level = level end
function Widget:GetName() return self.name end
function Widget:SetTexture(path) self.texture = path end
function Widget:SetTexCoord(l, r, t, b) self.coords = { l, r, t, b } end
function Widget:CreateTexture() return new("Texture") end
function Widget:SetText(text) self.text = text end
function Widget:GetText() return self.text end
function Widget:GetFontString() return self end
function Widget:GetStringWidth() return #(self.text or "") * 6 end
function Widget:GetWidth() return self.width or 0 end
function Widget:SetWidth(w) self.width = w end
function Widget:RegisterEvent(event) self.registered[event] = true end
function Widget:UnregisterEvent(event) self.registered[event] = nil end
function Widget:Click() self.scripts.OnClick(self) end

local frames = {}
function CreateFrame(kind, name, parent)
    local frame = new(kind, name)
    frame.parent = parent
    frames[#frames + 1] = frame
    return frame
end
UIParent = new("Frame")
GameTooltip = new("GameTooltip")
GameTooltip_Hide = function() end

local buttons = {}
for _, prefix in ipairs { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton" } do
    for index = 1, 12 do
        local name = prefix .. index
        local button = new("CheckButton", name)
        button.name = name
        button.level = 5
        new("FontString", name .. "HotKey")
        new("Texture", name .. "Icon")
        buttons[name] = button
    end
end

-- The controller DLL, as wow-client-controller's lua/api.lua describes it.
local pad = { connected = false, active = false, family = "ltr", layer = "BASE", mode = "world", rests = 0, bars = {} }
local BINDINGS = {}
do
    local sequence = {}
    for _, bar in ipairs { "main", "bottomleft", "bottomright" } do
        for index = 1, 12 do sequence[#sequence + 1] = { bar, index } end
    end
    local n = 1
    for _, layer in ipairs { "BASE", "LT", "RT", "BOTH" } do
        for _, position in ipairs { "SOUTH", "EAST", "WEST", "NORTH", "UP", "RIGHT", "DOWN", "LEFT" } do
            if not (layer == "BASE" and position == "SOUTH") then
                local slot = sequence[n]
                BINDINGS[slot[1] .. slot[2]] = { position, layer }
                n = n + 1
            end
        end
    end
end
local fakeApi = {
    GetState = function() return pad.connected, pad.active, pad.family, pad.layer, pad.mode end,
    GetBinding = function(bar, index)
        local entry = BINDINGS[bar .. index]
        if entry then return entry[1], entry[2] end
    end,
    GetGlyph = function(button) return "Interface\\GamePad\\" .. pad.family, 0, 1, 0, 1, button end,
    Rest = function() pad.rests = pad.rests + 1 pad.active = false end,
    SetBarsShown = function(shown) pad.bars[#pad.bars + 1] = shown end,
}

-- DragonUI's side.
local config = { enabled = true, auto = true }
local hotkeyRefreshes = 0
local addon = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    db = { profile = { widgets = {} } },
}
function addon:RegisterModule() end
function addon:GetModuleConfig(name) return name == "controller" and config or nil end
function addon:IsModuleEnabled(name) return name == "controller" and config.enabled end
function addon.CreateUIFrame() return new("Frame") end
function addon:RegisterEditableFrame(info) addon.editable = info end
function addon.GetAnchorOffset() return 10, 20 end
function addon.RefreshAllHotkeys() hotkeyRefreshes = hotkeyRefreshes + 1 end

assert(loadfile("DragonUI/modules/controller.lua"))("DragonUI", addon)
local T = addon._controllerLayout
local function frame() T.OnUpdate() end
local function overlayOf(name) return T.Overlays[buttons[name]] end
local function hotkey(name) return _G[name .. "HotKey"] end

-- ---- no controller DLL ----------------------------------------------------------------------------------------
frame()
check(T.Layout() == "keyboard" and T.Swap() == nil, "without C_Controller nothing appears")
check(addon.ControllerOwnsHotkey(buttons.ActionButton1) == false, "and the hotkeys stay DragonUI's")

-- ---- DLL, no controller plugged in ----------------------------------------------------------------------------
C_Controller = fakeApi
frame()
check(T.Layout() == "keyboard", "no controller, keyboard layout")
check(not T.Swap():IsShown(), "no swap button without a controller")
check(addon.editable and addon.editable.name == "controllerswap", "the swap button is in editor mode")
check(addon.editable.hasTarget() == false, "and only shows there with a controller")

-- ---- plugged in, not used yet ---------------------------------------------------------------------------------
pad.connected = true
frame()
check(T.Layout() == "keyboard", "plugging in alone changes nothing")
check(T.Swap():IsShown() and T.Swap().text == "Controller", "the swap button offers the controller layout")

-- ---- a controller button pressed ------------------------------------------------------------------------------
pad.active = true
frame()
check(T.Layout() == "controller", "a press swaps to the controller layout")
check(pad.bars[#pad.bars] == true, "the controller's own cross steps aside")
check(T.Swap().text == "Keyboard", "the swap button now offers the keyboard")
local main1, main8 = overlayOf("ActionButton1"), overlayOf("ActionButton8")
check(main1:IsShown() and main1.level > buttons.ActionButton1.level, "overlay over the button")
check(main1.glyph.shown and main1.glyph.texture == "Interface\\GamePad\\ltr", "main 1 shows its button")
check(main1.position == "EAST" and main1.layer == "BASE", "main 1 is East")
check(not main1.triggers[1].shown, "no trigger on the base layer")
check(main8.position == "SOUTH" and main8.layer == "LT" and main8.triggers[1].shown and not main8.triggers[2].shown,
    "main 8 shows LT + South")
local both = overlayOf("MultiBarBottomRightButton1")
check(both.layer == "BOTH" and both.triggers[1].shown and both.triggers[2].shown, "both triggers shown for BOTH")
local unused = overlayOf("MultiBarBottomRightButton8")
check(unused.position == nil and not unused.glyph.shown, "an unused slot has no button picture")
check(hotkey("ActionButton1").alpha == 0, "the key text gives way to the picture")
check(addon.ControllerOwnsHotkey(buttons.ActionButton1), "buttons.lua is told to keep it hidden")
check(not addon.ControllerOwnsHotkey(buttons.MultiBarBottomRightButton8), "an unused slot keeps its key text")
check(hotkey("MultiBarBottomRightButton8").alpha == 1, "and shows it")

-- ---- layers ---------------------------------------------------------------------------------------------------
check(main1.shade.alpha == 0 and main8.shade.alpha > 0 and unused.shade.alpha > 0, "base layer bright, others dim")
pad.layer = "LT"
frame()
check(main1.shade.alpha > 0 and main8.shade.alpha == 0, "holding LT lights the LT slots")
pad.layer = "BOTH"
frame()
check(both.shade.alpha == 0 and main8.shade.alpha > 0, "both triggers light the BOTH slots")
pad.layer = "BASE"
frame()

-- ---- another controller ---------------------------------------------------------------------------------------
pad.family = "shp"
frame()
check(main1.glyph.texture == "Interface\\GamePad\\shp", "a PlayStation pad gets its own pictures")

-- ---- swap back ------------------------------------------------------------------------------------------------
local refreshesBefore = hotkeyRefreshes
T.Swap():Click()
check(T.Layout() == "keyboard", "the swap button goes back to the keyboard layout")
check(pad.rests == 1, "and the controller goes quiet")
check(pad.bars[#pad.bars] == false, "and gets its cross back for next time")
check(not main1:IsShown(), "overlays gone")
check(hotkey("ActionButton1").alpha == 1 and hotkeyRefreshes > refreshesBefore, "key text back, restyled")
frame()
check(T.Layout() == "keyboard", "stays on the keyboard while the controller rests")
pad.active = true
frame()
check(T.Layout() == "controller", "the next controller press swaps again")

-- ---- manual only ----------------------------------------------------------------------------------------------
T.Swap():Click()
config.auto = false
pad.active = true
frame()
check(T.Layout() == "keyboard", "with switching off, a press doesn't swap")
T.Swap():Click()
check(T.Layout() == "controller", "the swap button still does")
config.auto = true

-- ---- unplugged, turned off ------------------------------------------------------------------------------------
pad.connected, pad.active = false, false
frame()
check(T.Layout() == "keyboard" and not T.Swap():IsShown(), "unplugging goes back to the keyboard")
pad.connected, pad.active = true, false
frame()
pad.active = true
frame()
check(T.Layout() == "controller", "plugged in and pressed again")
config.enabled = false
frame()
check(T.Layout() == "keyboard" and not T.Swap():IsShown(), "turning the module off puts the keyboard back")
config.enabled = true

pad.connected, pad.active = true, false
frame()
pad.active = true
frame()
addon.compatibility = { bartenderActive = true }
frame()
check(T.Layout() == "keyboard" and pad.bars[#pad.bars] == false,
    "with Bartender4 running the bars, the controller keeps its own cross")
addon.compatibility = nil

print(checks .. " checks, " .. failures .. " failures")
os.exit(failures == 0 and 0 or 1)
