-- Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)

local max, min = math.max, math.min

-- The 3.3.5 client drops the minimap zoom on every login and /reload. It keeps one level outdoors
-- and another indoors, so remember both for each character and put each back the first time the
-- minimap is in that mode after a loading screen.
local ready     -- nothing is remembered before the first restore: login-time zoom calls are not the player's
local busy      -- our own SetZoom calls (probing the mode, restoring) are not the player's either
local restored = {}

local function Saved(create)
    local char = addon.db and addon.db.char
    if not char then return end
    if create and not char.minimap_zoom then char.minimap_zoom = {} end
    return char.minimap_zoom
end

-- The client mirrors the live zoom into minimapZoom outdoors and minimapInsideZoom indoors. When
-- both hold the same level, step the zoom for a moment to see which one follows.
local function CurrentMode()
    local outside, inside = GetCVar("minimapZoom"), GetCVar("minimapInsideZoom")
    if not (outside and inside) then return IsIndoors() and "inside" or "outside" end
    local zoom = Minimap:GetZoom()
    if outside ~= inside then
        return tonumber(outside) == zoom and "outside" or "inside"
    end
    local wasBusy = busy
    busy = true
    Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
    local mode = tonumber(GetCVar("minimapZoom")) == Minimap:GetZoom() and "outside" or "inside"
    Minimap:SetZoom(zoom)
    busy = wasBusy
    return mode
end

-- Stock Minimap.lua only re-enables the buttons on its own clicks and MINIMAP_UPDATE_ZOOM.
local function SyncButtons()
    if not (MinimapZoomIn and MinimapZoomOut) then return end
    local zoom = Minimap:GetZoom()
    if zoom < Minimap:GetZoomLevels() - 1 then MinimapZoomIn:Enable() else MinimapZoomIn:Disable() end
    if zoom > 0 then MinimapZoomOut:Enable() else MinimapZoomOut:Disable() end
end

local function Remember()
    if busy or not ready then return end
    local saved = Saved(true)
    if not saved then return end
    local mode = CurrentMode()
    saved[mode] = Minimap:GetZoom()
    -- The player picked this level: never lay an older saved one over it.
    restored[mode] = true
end

local function Restore()
    if busy then return end
    local saved = Saved()
    if not saved then return end
    local mode = CurrentMode()
    if restored[mode] then return end
    restored[mode] = true
    local level = saved[mode]
    if not level then return end
    level = max(0, min(level, Minimap:GetZoomLevels() - 1))
    if level ~= Minimap:GetZoom() then
        busy = true
        Minimap:SetZoom(level)
        busy = false
    end
    SyncButtons()
end

hooksecurefunc(Minimap, "SetZoom", Remember)

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Fires when the minimap swaps between its indoor and outdoor level.
driver:RegisterEvent("MINIMAP_UPDATE_ZOOM")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        wipe(restored)
        Restore()
        ready = true
    else
        Restore()
    end
end)
