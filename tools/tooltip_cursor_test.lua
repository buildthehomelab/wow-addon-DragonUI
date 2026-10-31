-- Run from the repository root with Lua 5.1. Mocks GameTooltip, the mouseover unit and the cursor.
RAID_CLASS_COLORS = {}
UIParent = { name = 'UIParent' }
local mouseover = false
function UnitExists(unit) return unit == 'mouseover' and mouseover end
function GetCursorPosition() return 500, 400 end

local frames = {}
function CreateFrame()
    local f = { scripts = {} }
    function f:SetScript(script, fn) self.scripts[script] = fn end
    function f:RegisterEvent() end
    function f:Hide() end
    function f:Show() end
    frames[#frames + 1] = f
    return f
end

function hooksecurefunc(a, b, c)
    if c then
        local original = a[b]
        a[b] = function(...) original(...); c(...) end
    else
        local original = _G[a]
        _G[a] = function(...) original(...); b(...) end
    end
end

local tt = { shown = false, hooks = {} }
function tt:HookScript(script, fn) self.hooks[script] = fn end
function tt:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
function tt:IsOwned(frame) return self.owner == frame end
function tt:SetUnit(unit) self.unit = unit; self.shown = true; if self.hooks.OnTooltipSetUnit then self.hooks.OnTooltipSetUnit(self) end end
function tt:IsUnit(unit) return self.unit == unit end
function tt:Hide() self.shown = false end
function tt:ClearAllPoints() end
function tt:SetPoint(...) self.point = { ... } end
function tt:GetEffectiveScale() return 1 end
function tt:Update() if self.shown then self.hooks.OnUpdate(self) end end
GameTooltip = tt
function GameTooltip_SetDefaultAnchor(tooltip, parent) tooltip:SetOwner(parent, 'ANCHOR_NONE') end

local config = { anchor_cursor = true, anchor_cursor_x = 20, anchor_cursor_y = 20 }
local addon = { L = setmetatable({}, { __index = function(_, k) return k end }) }
function addon:GetModuleConfig() return config end
function addon:IsModuleEnabled() return false end
assert(loadfile('DragonUI/modules/tooltip.lua'))('DragonUI', addon)
for _, f in ipairs(frames) do
    if f.scripts.OnEvent then f.scripts.OnEvent(f, 'ADDON_LOADED', 'DragonUI') end
end
assert(tt.hooks.OnUpdate, 'Cursor follow hook not installed')

-- A world unit under the cursor: the tip follows the cursor with the offsets.
mouseover = true
GameTooltip_SetDefaultAnchor(tt, UIParent)
tt:SetUnit('mouseover')
tt:Update()
assert(tt.shown and tt.point[4] == 520 and tt.point[5] == 420, 'Tip should follow the cursor at the offsets')

-- Leaving the unit hides it at once, as the engine's ANCHOR_CURSOR tip did, instead of a 2-3 s linger.
mouseover = false
tt:Update()
assert(not tt.shown, 'Tip should go the moment the world unit is left')

-- A unit frame hover (owned by the frame) is left to its own OnLeave fade.
local frame = { name = 'PlayerFrame' }
GameTooltip_SetDefaultAnchor(tt, frame)
tt:SetUnit('player')
tt:Update()
assert(tt.shown, 'Unit frame tips are not the world tip')

-- A world object (no unit) never had a mouseover unit to lose.
GameTooltip_SetDefaultAnchor(tt, UIParent)
tt.unit = nil
tt.shown = true
tt:Update()
assert(tt.shown, 'Object tips are left to the engine')

-- Zero offsets use the engine's own ANCHOR_CURSOR, untouched.
config.anchor_cursor_x, config.anchor_cursor_y = 0, 0
mouseover = true
GameTooltip_SetDefaultAnchor(tt, UIParent)
assert(tt.anchor == 'ANCHOR_CURSOR', 'Zero offsets should use the engine follow')
tt:SetUnit('mouseover')
mouseover = false
tt:Update()
assert(tt.shown, 'The engine hides its own ANCHOR_CURSOR tip')

print('tooltip cursor test passed')
