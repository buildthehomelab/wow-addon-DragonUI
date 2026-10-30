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
MinimapBackdrop = newRegion(MinimapCluster)
-- A texture, as in the client: no GetEffectiveScale of its own.
Minimap.Circle = newRegion(MinimapBackdrop)
Minimap.Circle.GetEffectiveScale = nil
function Minimap.Circle:GetParent() return self.parent end
function Minimap.Circle:GetBottom() return 494 end
DurabilityFrame = newRegion(UIParent)
DurabilityFrame.shown = false
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

function GetUnitSpeed() return 0 end
function UnitInVehicle() return false end
function UnitName() return 'Panda' end
local now = 100
function GetTime() return now end
local sent = {}
function SendAddonMessage(prefix, message, channel, target)
    sent[#sent + 1] = { prefix = prefix, message = message, channel = channel, target = target }
end

local editable = {}
local editorActive = false
local profile = {
    minimap = { movement_speed = true, latency = true, style = "dragonui" },
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
local speedDriver = frames[1]
assert(loadfile('DragonUI/modules/minimap_latency.lua'))('DragonUI', addon)
local driver = frames[2]

-- Nothing runs before the world is entered.
assert(driver.events.PLAYER_ENTERING_WORLD and driver.events.CHAT_MSG_ADDON and not driver.scripts.OnUpdate)
speedDriver.scripts.OnEvent(speedDriver, 'PLAYER_ENTERING_WORLD')
driver.scripts.OnEvent(driver, 'PLAYER_ENTERING_WORLD')
assert(driver.scripts.OnUpdate)
local function step(seconds)
    now = now + (seconds or 0.1)
    speedDriver.scripts.OnUpdate(speedDriver, 0.1)
    driver.scripts.OnUpdate(driver, 0.1)
end
local function reply(message, sender, channel, prefix)
    driver.scripts.OnEvent(driver, 'CHAT_MSG_ADDON', prefix or 'DragonUILag', message,
        channel or 'WHISPER', sender or 'Panda')
end

step()
local holder
for _, frame in ipairs(frames) do
    if frame.name == 'DragonUILatency' then holder = frame end
end
assert(holder and holder.parent == MinimapCluster)
local label, sizer = holder.fonts[1], holder.fonts[2]
local mover = editable.latency.frame
local speedMover = editable.movespeed.frame
local function colour() return table.concat(label.color, ',') end
local function lastPoint() return mover.points[#mover.points] end

-- The first tick whispers ourselves; no reading yet, in grey.
assert(#sent == 1 and sent[1].prefix == 'DragonUILag' and sent[1].channel == 'WHISPER' and sent[1].target == 'Panda')
assert(label.text == 'Lag --' and colour() == '0.5,0.5,0.5', tostring(label.text))
assert(sizer.text == 'Lag 8888 ms' and not sizer.shown)
assert(mover.w == #'Lag 8888 ms' * 6 and mover.h == 16)

-- Hangs under the speed line.
local point, anchor, rel, x, y = unpack(lastPoint())
assert(point == 'TOP' and anchor == speedMover and rel == 'BOTTOM' and x == 0 and y == 0)

-- The answer gives the round trip, in green; nothing else is sent while one is in flight.
step(); step()
assert(#sent == 1)
now = now + 0.0453
reply(sent[1].message)
assert(label.text == 'Lag 245 ms' and colour() == '0,1,0', label.text)

-- Others' messages, other prefixes and stale sequence numbers are ignored.
step(5.1)
assert(#sent == 2 and sent[2].message ~= sent[1].message)
reply(sent[2].message, 'Someone')
reply(sent[2].message, nil, 'PARTY')
reply(sent[2].message, nil, nil, 'Other')
reply(sent[1].message)
assert(label.text == 'Lag 245 ms')
now = now + 0.4
reply(sent[2].message)
assert(label.text == 'Lag 400 ms' and colour() == '1,1,0', label.text)

-- The next ping waits PING_EVERY seconds after the answer.
step(4.8)
assert(#sent == 2)
step(0.3)
assert(#sent == 3)

-- A stalled server: the reading climbs with the wait, in red, and the ping is sent again at 30 s.
step(1)
assert(label.text == 'Lag 1000 ms' and colour() == '1,0,0', label.text)
step(29.5)
assert(label.text == 'Lag 30500 ms' and #sent == 4, label.text)
-- The resent ping is timed from its own send; the climbing wait spans both.
step(2)
assert(label.text == 'Lag 32500 ms', label.text)
now = now + 0.05
reply(sent[4].message)
assert(label.text == 'Lag 2050 ms', label.text)

-- A loading screen drops what was in flight; the next world pings straight away.
step(5.1)
assert(#sent == 5)
driver.scripts.OnEvent(driver, 'PLAYER_LEAVING_WORLD')
assert(not driver.scripts.OnUpdate)
now = now + 40
driver.scripts.OnEvent(driver, 'PLAYER_ENTERING_WORLD')
reply(sent[5].message)
assert(label.text == 'Lag 2050 ms', 'a ping from before the loading screen was counted')
step()
assert(#sent == 6)
now = now + 0.03
reply(sent[6].message)
assert(label.text == 'Lag 30 ms', label.text)

-- Speed line off: the lag line takes its spot under the ring (6px overhang + 2px gap, less padding).
profile.minimap.movement_speed = false; step()
point, anchor, rel, x, y = unpack(lastPoint())
assert(point == 'TOP' and anchor == Minimap and rel == 'BOTTOM' and y == 3 - 8, tostring(y))
DurabilityFrame.shown = true; step()
point, anchor, rel = unpack(lastPoint())
assert(point == 'TOPLEFT' and anchor == DurabilityFrame and rel == 'TOPRIGHT')
DurabilityFrame.shown = false
profile.minimap.movement_speed = true; step()
assert(lastPoint()[2] == speedMover)

-- Unchanged layout is not re-anchored every tick.
local count = #mover.points
step(); step()
assert(#mover.points == count)

-- Editor mode: a sample reading, no live updates, and a drag saves the on-screen centre.
editorActive = true
editable.latency.showTest()
assert(label.text == 'Lag 45 ms')
step(6)
assert(label.text == 'Lag 45 ms', 'live update while the editor is open')
mover.center = { 60.6, -20.2 }
mover.scripts.OnDragStop(mover)
local widget = profile.widgets.latency
assert(widget.custom_position and widget.posX == 61 and widget.posY == -20)
point, anchor, rel, x, y = unpack(lastPoint())
assert(point == 'CENTER' and anchor == UIParent and x == 61 and y == -20)
assert(not editable.latency.isDefaultPosition())
editable.latency.hideTest()
assert(label.text ~= 'Lag 45 ms')
editorActive = false

-- Reset goes back under the speed line on the next tick.
editable.latency.resetPosition()
assert(editable.latency.isDefaultPosition())
step()
assert(lastPoint()[2] == speedMover)

-- Toggle off hides it, stops pinging and the editor stops offering it; back on shows it again.
profile.minimap.latency = false; step()
local before = #sent
step(10)
assert(not holder.shown and not editable.latency.editorVisible() and #sent == before)
profile.minimap.latency = true
addon.RefreshLatency()
driver.scripts.OnUpdate(driver, 0)
assert(holder.shown and #sent == before + 1, 'refresh did not apply on the next frame')

-- Minimap module off counts as off.
profile.modules.minimap.enabled = false; step()
assert(not holder.shown)

print('latency: ok')
