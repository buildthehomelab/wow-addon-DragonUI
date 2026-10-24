-- Run from the repository root with Lua 5.1.
local function newRegion(parent)
    local region = { parent = parent, shown = true, scripts = {}, events = {}, points = {}, fonts = {}, scale = 1 }
    function region:SetSize(w, h) self.w, self.h = w, h end
    function region:SetFrameStrata() end
    function region:EnableMouse() end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown end
    function region:ClearAllPoints() self.points = {} end
    function region:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function region:SetScript(event, fn) self.scripts[event] = fn end
    function region:HookScript(event, fn) self.scripts[event] = fn end
    function region:RegisterEvent(event) self.events[event] = true end
    function region:UnregisterEvent(event) self.events[event] = nil end
    function region:GetEffectiveScale() return self.scale end
    function region:CreateFontString()
        local text = newRegion(self)
        function text:SetText(value) self.text = value end
        function text:SetTextColor(r, g, b) self.color = { r, g, b } end
        function text:GetStringWidth() return #(self.text or "") * 6 end
        function text:GetStringHeight() return 10 end
        self.fonts[#self.fonts + 1] = text
        return text
    end
    return region
end

local frames = {}
function CreateFrame(_, name, parent)
    local frame = newRegion(parent)
    frame.name = name
    frames[#frames + 1] = frame
    return frame
end

UIParent = newRegion()
MinimapCluster = newRegion(UIParent)
Minimap = newRegion(MinimapCluster)
function Minimap:GetBottom() return 500 end
Minimap.Circle = newRegion(Minimap)
function Minimap.Circle:GetBottom() return 494 end
DurabilityFrame = newRegion(UIParent)
DurabilityFrame.shown = false
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

local speeds = { player = 0, vehicle = 0 }
local inVehicle = false
function GetUnitSpeed(unit) return speeds[unit] end
function UnitInVehicle() return inVehicle end

local editable = {}
local editorActive = false
local profile = {
    minimap = { movement_speed = true, style = "dragonui" },
    widgets = {},
    modules = { minimap = { enabled = true } },
}
local addon = {
    db = { profile = profile },
    L = setmetatable({}, { __index = function(_, key) return key end }),
    EditorMode = { IsActive = function() return editorActive end },
}
function addon:IsModuleEnabled(name) return self.db.profile.modules[name].enabled end
function addon:RegisterEditableFrame(info) editable[info.name] = info end
function addon.CreateUIFrame()
    local mover = newRegion(UIParent)
    mover.center = { 0, 0 }
    return mover
end
function addon.GetAnchorOffset(frame) return frame.center[1], frame.center[2] end

assert(loadfile('DragonUI/modules/minimap_speed.lua'))('DragonUI', addon)
local driver = frames[1]

-- Nothing runs before the world is entered.
assert(driver.events.PLAYER_ENTERING_WORLD and not driver.scripts.OnUpdate)
driver.scripts.OnEvent(driver, 'PLAYER_ENTERING_WORLD')
assert(driver.scripts.OnUpdate and not driver.events.PLAYER_ENTERING_WORLD)
local function step() driver.scripts.OnUpdate(driver, 0.1) end

step()
local holder = frames[2]
assert(holder.name == 'DragonUIMovementSpeed' and holder.parent == MinimapCluster)
local label, sizer = holder.fonts[1], holder.fonts[2]
local mover = editable.movespeed.frame
local function grey() return label.color[1] == GRAY_FONT_COLOR.r end
local function lastPoint() return mover.points[#mover.points] end

-- Standing still at login: no reading yet, in grey; the mover is sized for the widest reading.
assert(label.text == 'Speed --' and grey(), tostring(label.text))
assert(sizer.text == 'Speed 888%' and not sizer.shown)
assert(mover.w == #'Speed 888%' * 6 and mover.h == 16)

-- Below the ring: its 6px overhang plus the 2px gap, less half the mover's padding (16 - 10).
local point, anchor, rel, x, y = unpack(lastPoint())
assert(point == 'TOP' and anchor == Minimap and rel == 'BOTTOM' and x == 0 and y == 3 - 8, tostring(y))

-- Running, mounted, slowed: rounded percent of 7 yd/s, in gold.
speeds.player = 7; step()
assert(label.text == 'Speed 100%' and not grey())
speeds.player = 15.4; step()
assert(label.text == 'Speed 220%')
speeds.player = 4.375; step()
assert(label.text == 'Speed 63%')

-- Stopping keeps the last reading, dimmed.
speeds.player = 0; step()
assert(label.text == 'Speed 63%' and grey())

-- In a vehicle the vehicle's speed counts.
inVehicle, speeds.vehicle = true, 14; step()
assert(label.text == 'Speed 200%' and not grey())
inVehicle, speeds.vehicle = false, 0

-- No ring (SexyMap): a fixed gap below the bare map. Square frames use their own fixed drop.
Minimap.Circle.shown = false; step()
assert(select(5, unpack(lastPoint())) == 3 - 6)
Minimap.Circle.shown = true
profile.minimap.style = 'dragonui_square'; step()
assert(select(5, unpack(lastPoint())) == 3 - 6)
profile.minimap.style = 'dragonui'; step()
assert(select(5, unpack(lastPoint())) == 3 - 8)

-- A damaged-gear figure at its default spot pushes the text beside it; a dragged figure does not.
DurabilityFrame.shown = true; step()
point, anchor, rel = unpack(lastPoint())
assert(point == 'TOPLEFT' and anchor == DurabilityFrame and rel == 'TOPRIGHT')
profile.widgets.durability = { custom_position = true }; step()
assert(lastPoint()[2] == Minimap)
DurabilityFrame.shown, profile.widgets.durability = false, nil

-- Unchanged layout is not re-anchored every tick.
local count = #mover.points
step(); step()
assert(#mover.points == count)

-- Editor mode: a sample reading, no live updates, and a drag saves the on-screen centre.
editorActive = true
editable.movespeed.showTest()
assert(label.text == 'Speed 100%')
speeds.player = 21; step()
assert(label.text == 'Speed 100%', 'live update while the editor is open')
mover.center = { -40.4, 120.6 }
mover.scripts.OnDragStop(mover)
local widget = profile.widgets.movespeed
assert(widget.custom_position and widget.posX == -40 and widget.posY == 121)
point, anchor, rel, x, y = unpack(lastPoint())
assert(point == 'CENTER' and anchor == UIParent and x == -40 and y == 121)
assert(not editable.movespeed.isDefaultPosition())
editable.movespeed.hideTest()
assert(label.text == 'Speed 300%')
editorActive = false

-- Reset goes back under the minimap on the next tick.
editable.movespeed.resetPosition()
assert(editable.movespeed.isDefaultPosition())
step()
assert(lastPoint()[2] == Minimap)

-- Toggle off hides it (and the editor stops offering it); back on shows it again.
profile.minimap.movement_speed = false; step()
assert(not holder.shown and not editable.movespeed.editorVisible())
profile.minimap.movement_speed = true
addon.RefreshMovementSpeed()
driver.scripts.OnUpdate(driver, 0)
assert(holder.shown, 'refresh did not apply on the next frame')

-- Minimap module off counts as off.
profile.modules.minimap.enabled = false; step()
assert(not holder.shown)

print('movement speed: ok')
