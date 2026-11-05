-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.
-- Game data (c) Blizzard Entertainment; not covered by DragonUI's MIT license.

local addon = select(2, ...)
local WM = addon.WorldMap

-- A client patch can bring WoW Forever's Redridge map, drawn 110.417 yards further east and with its own overlays. The
-- tables in the other data files describe the client's own Redridge, so on such a client this replaces its fog and moves
-- its pins. From WoW Forever's WorldMapOverlay and UiMapAssignment. Forever's Render's Camp overlay is four files and the
-- client's two, so the third file says which map this client has. Without it nothing here runs.
local REDRIDGE_SHIFT = -110.417 / 2170.834

local REDRIDGE_FOG = {
    ["ALTHERSMILL"] = 99134801162,
    ["GALARDELLVALLEY"] = 575052203,
    ["LAKEEVERSTILL"] = 239444740731,
    ["LAKERIDGEHIGHWAY"] = 348016415182,
    ["LAKESHIRE"] = 200789944750,
    ["REDRIDGECANYONS"] = 52768143,
    ["RENDERSCAMP"] = 212100561,
    ["RENDERSVALLEY"] = 373018635770,
    ["STONEWATCH"] = 94946912543,
    ["STONEWATCHFALLS"] = 286179796432,
    ["THREECORNERS"] = 279173267787,
}

function WM.ApplyPatchedZones()
    local probe = CreateFrame("Frame"):CreateTexture()
    if not probe:SetTexture("Interface\\WorldMap\\Redridge\\RENDERSCAMP3") then return end
    WM.FogData.Redridge = REDRIDGE_FOG
    for _, entry in ipairs(WM.FlightPoints.Redridge) do entry.x = entry.x + REDRIDGE_SHIFT end
    for _, inn in ipairs(WM.Inns.Redridge) do inn[1] = inn[1] + REDRIDGE_SHIFT end
    for _, point in ipairs(WM.Graveyards.Redridge) do point[1] = point[1] + REDRIDGE_SHIFT end
    -- mod-quest-map works out givers from the server's WorldMapArea.dbc, which still has the client's own Redridge.
    WM.QuestGiverShift = { [36] = REDRIDGE_SHIFT }
end
