-- Run from the repository root with Lua 5.1.
local frames = {}
local function fire(event)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event) end
    end
end

function CreateFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    frames[#frames + 1] = frame
    return frame
end

function hooksecurefunc(object, method, hook)
    local original = object[method]
    object[method] = function(...)
        local a, b = original(...)
        hook(...)
        return a, b
    end
end

function wipe(t)
    for key in pairs(t) do t[key] = nil end
    return t
end

-- The client: one zoom level per mode, mirrored into a CVar each, both lost on a reload.
local client = { mode = "outside", zoom = { outside = 0, inside = 0 }, cvars = true, events = true }
local function resetClient(mode)
    client.mode = mode
    client.zoom = { outside = 0, inside = 0 }
end
function GetCVar(name)
    if not client.cvars then return nil end
    if name == "minimapZoom" then return tostring(client.zoom.outside) end
    if name == "minimapInsideZoom" then return tostring(client.zoom.inside) end
end
function IsIndoors() return client.mode == "inside" end

Minimap = {}
function Minimap:GetZoom() return client.zoom[client.mode] end
function Minimap:GetZoomLevels() return 6 end
function Minimap:SetZoom(level)
    client.zoom[client.mode] = math.max(0, math.min(level, 5))
    -- Worst case: the client answers a zoom change at once, inside the call.
    if client.events then fire("MINIMAP_UPDATE_ZOOM") end
end

local function newButton()
    local button = { enabled = true }
    function button:Enable() self.enabled = true end
    function button:Disable() self.enabled = false end
    return button
end
MinimapZoomIn, MinimapZoomOut = newButton(), newButton()

local char = {}
local addon = { db = {} }

local originalSetZoom = Minimap.SetZoom
local function freshClient(mode)
    resetClient(mode)
    Minimap.SetZoom = originalSetZoom
    frames = {}
    assert(loadfile('DragonUI/modules/minimap_zoom.lua'))('DragonUI', addon)
end

local function walk(mode)
    client.mode = mode
    fire("MINIMAP_UPDATE_ZOOM")
end

-- Before AceDB exists nothing is touched.
freshClient("outside")
Minimap:SetZoom(2)
assert(char.minimap_zoom == nil)

-- First login: nothing saved, zoom calls made before the world is entered are not the player's.
addon.db.char = char
freshClient("outside")
Minimap:SetZoom(4)
assert(char.minimap_zoom == nil, "zoom before PLAYER_ENTERING_WORLD is not remembered")
Minimap:SetZoom(0)
fire("PLAYER_ENTERING_WORLD")
assert(Minimap:GetZoom() == 0)

-- The player zooms outdoors, walks into a building and zooms there too.
Minimap:SetZoom(3)
assert(char.minimap_zoom.outside == 3)
walk("inside")
assert(Minimap:GetZoom() == 0, "nothing saved indoors yet")
Minimap:SetZoom(1)
assert(char.minimap_zoom.inside == 1)
assert(char.minimap_zoom.outside == 3, "indoor zoom leaves the outdoor level alone")
walk("outside")
assert(Minimap:GetZoom() == 3, "the client keeps its own outdoor level")

-- /reload outdoors: the client forgets, the module puts the outdoor level back, then the indoor one.
freshClient("outside")
fire("PLAYER_ENTERING_WORLD")
assert(Minimap:GetZoom() == 3, "outdoor zoom restored after reload")
assert(MinimapZoomIn.enabled and MinimapZoomOut.enabled, "zoom buttons follow the restored level")
walk("inside")
assert(Minimap:GetZoom() == 1, "indoor zoom restored on first indoor visit")
Minimap:SetZoom(2)
walk("outside")
walk("inside")
assert(Minimap:GetZoom() == 2, "a later visit keeps the player's new level")
assert(char.minimap_zoom.inside == 2)

-- Logging in indoors restores the indoor level first.
freshClient("inside")
fire("PLAYER_ENTERING_WORLD")
assert(Minimap:GetZoom() == 2)
walk("outside")
assert(Minimap:GetZoom() == 3)

-- Fully zoomed in: the in button stays disabled; a stale level past the top is clamped.
char.minimap_zoom.outside = 9
freshClient("outside")
fire("PLAYER_ENTERING_WORLD")
assert(Minimap:GetZoom() == 5)
assert(not MinimapZoomIn.enabled and MinimapZoomOut.enabled)

-- Zoomed all the way out: the out button stays disabled.
char.minimap_zoom.outside = 0
freshClient("outside")
client.zoom.outside = 2
MinimapZoomOut.enabled = true
fire("PLAYER_ENTERING_WORLD")
assert(Minimap:GetZoom() == 0 and not MinimapZoomOut.enabled)

-- The client does not reset across a loading screen: restoring is a no-op and keeps the level.
Minimap:SetZoom(4)
fire("PLAYER_ENTERING_WORLD")
assert(Minimap:GetZoom() == 4)

-- Both levels equal: the probe works out the mode and leaves the zoom where it was.
char.minimap_zoom = { outside = 2, inside = 2 }
freshClient("inside")
client.zoom.outside, client.zoom.inside = 2, 2
fire("PLAYER_ENTERING_WORLD")
Minimap:SetZoom(4)
assert(char.minimap_zoom.inside == 4 and char.minimap_zoom.outside == 2)
assert(client.zoom.outside == 2)

-- Without the CVars the mode comes from IsIndoors.
client.cvars = false
char.minimap_zoom = { outside = 1, inside = 3 }
freshClient("inside")
fire("PLAYER_ENTERING_WORLD")
assert(Minimap:GetZoom() == 3)
walk("outside")
assert(Minimap:GetZoom() == 1)
client.cvars = true

-- A client that never fires the event from SetZoom behaves the same.
client.events = false
char.minimap_zoom = { outside = 2 }
freshClient("outside")
fire("PLAYER_ENTERING_WORLD")
assert(Minimap:GetZoom() == 2)
Minimap:SetZoom(5)
assert(char.minimap_zoom.outside == 5)

print("minimap zoom test passed")
