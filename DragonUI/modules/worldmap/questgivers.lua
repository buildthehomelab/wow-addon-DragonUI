-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local WM = addon.WorldMap

-- Quest givers on the zone map on screen. The client only knows the creatures within visibility
-- range, so the list comes from the server's mod-quest-map; without it, the map shows none.
-- Protocol: https://github.com/buildthehomelab/wow-mod-quest-map#protocol

local PREFIX = "QMP"
local PROTOCOL = 1
local HELLO_GIVERS = 1
local QUEST_REPEATABLE, QUEST_TRIVIAL = 1, 2
-- No answer to the hello by then: no module on this server, and nothing more is asked.
local HELLO_WAIT = 5
-- An answer still unfinished by then is dropped; the map asks again on its next update.
local ANSWER_WAIT = 10
-- Kept this long at most, for what no event says changed (a daily reset, a reputation rank).
local STALE_AFTER = 300
local BUSY_RETRIES, BUSY_WAIT = 3, 1
-- Still busy after the retries: the shown map tries again this much later.
local BUSY_AGAIN = 4
-- The quest log fires in bursts; the shown map is asked again once it settles.
local SETTLE = 0.5

local server = "unknown" -- "asking", "ready" or "absent"
local nextReq = 0
local pending = {}
local cache = {}
local asked = {}
-- Bumped by whatever changes which quests the player can take; a cached map from before is stale.
local generation = 0
local questCount
local refreshQueued = false

local function send(msg)
    SendAddonMessage(PREFIX, msg, "WHISPER", UnitName("player"))
end

local function unescape(text)
    if text == "-" then return "" end
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function shownArea()
    return WorldMapFrame:IsShown() and (GetCurrentMapAreaID() or 0) - 1 or nil
end

local function refreshShownMap()
    if refreshQueued or not WorldMapFrame:IsShown() then return end
    refreshQueued = true
    addon:After(SETTLE, function()
        refreshQueued = false
        WM.RefreshMapPins()
    end)
end

local function request(area, tries)
    nextReq = nextReq + 1
    local req = tostring(nextReq)
    pending[req] = { area = area, givers = {}, byIndex = {}, started = GetTime(), generation = generation, tries = tries or 0 }
    asked[area] = req
    send("A:" .. req .. ":" .. area)
end

local function hello()
    server = "asking"
    send("HELLO:0:" .. PROTOCOL)
    addon:After(HELLO_WAIT, function()
        if server == "asking" then server = "absent" end
    end)
end

-- What a pin needs, worked out once per answer: the quests it lists with trivial ones and without.
local function finishGiver(giver)
    local normal = {}
    for _, quest in ipairs(giver.quests) do
        if not quest.trivial then normal[#normal + 1] = quest end
    end
    giver.normal = normal
end

local function onRows(p, text)
    for row in text:gmatch("[^;]+") do
        local n, x, y, name = row:match("^G,(%d+),(%d+),(%d+),(.*)$")
        if n then
            local giver = { x = tonumber(x) / 10000, y = tonumber(y) / 10000, name = unescape(name), quests = {} }
            p.byIndex[n] = giver
            p.givers[#p.givers + 1] = giver
        else
            local id, level, flags, title
            n, id, level, flags, title = row:match("^Q,(%d+),(%d+),(%-?%d+),(%d+),(.*)$")
            local giver = n and p.byIndex[n]
            if giver then
                flags = tonumber(flags)
                giver.quests[#giver.quests + 1] = {
                    id = tonumber(id),
                    level = tonumber(level),
                    title = unescape(title),
                    repeatable = bit.band(flags, QUEST_REPEATABLE) ~= 0,
                    trivial = bit.band(flags, QUEST_TRIVIAL) ~= 0,
                }
            end
        end
    end
end

local function onMessage(message)
    local code, req, rest = message:match("^(%u+):([^:]*):?(.*)$")
    if not code then return end
    if code == "HI" then
        local version, flags = rest:match("^(%d+):(%d+)")
        local ready = tonumber(version) == PROTOCOL and bit.band(tonumber(flags) or 0, HELLO_GIVERS) ~= 0
        server = ready and "ready" or "absent"
        if ready then refreshShownMap() end
        return
    elseif code == "OFF" then
        server = "absent"
        return
    end

    local p = pending[req]
    if not p then return end
    if code == "AD" then
        onRows(p, rest)
    elseif code == "AE" then
        pending[req] = nil
        if asked[p.area] == req then asked[p.area] = nil end
        for _, giver in ipairs(p.givers) do finishGiver(giver) end
        cache[p.area] = { givers = p.givers, generation = p.generation, time = GetTime() }
        refreshShownMap()
    elseif code == "ERR" then
        pending[req] = nil
        if asked[p.area] == req then asked[p.area] = nil end
        -- Only for the map still on screen: retries for maps flicked past would use up the budget.
        if rest == "busy" and p.tries < BUSY_RETRIES then
            addon:After(BUSY_WAIT * (p.tries + 1), function()
                if not asked[p.area] and shownArea() == p.area then request(p.area, p.tries + 1) end
            end)
        elseif rest == "busy" then
            addon:After(BUSY_AGAIN, function()
                if shownArea() == p.area then refreshShownMap() end
            end)
        end
    end
end

-- The givers of a WorldMapArea id (GetCurrentMapAreaID() - 1), nil while none are known. A stale
-- or missing list is asked for, and the map refreshes when it comes.
function WM.QuestGivers(area)
    if server == "unknown" then hello() end
    if server == "absent" then return nil end

    local entry = cache[area]
    local fresh = entry and entry.generation == generation and GetTime() - entry.time < STALE_AFTER
    if server == "ready" and not fresh then
        local req = asked[area]
        if req and pending[req] and GetTime() - pending[req].started > ANSWER_WAIT then
            pending[req] = nil
            req = nil
        end
        if not req then request(area) end
    end
    return entry and entry.givers
end

local function questsChanged()
    generation = generation + 1
    refreshShownMap()
end

local function onEvent(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix == PREFIX and sender == UnitName("player") then onMessage(message) end
    elseif event == "QUEST_LOG_UPDATE" then
        -- Fires for every objective; only a quest taken, handed in or abandoned changes the list.
        local _, count = GetNumQuestLogEntries()
        if count ~= questCount then
            if questCount then questsChanged() end
            questCount = count
        end
    else
        questsChanged()
    end
end

function WM.BuildQuestGivers()
    local events = CreateFrame("Frame")
    events:RegisterEvent("CHAT_MSG_ADDON")
    events:RegisterEvent("QUEST_LOG_UPDATE")
    events:RegisterEvent("QUEST_ACCEPTED")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    -- The server answers for the zone you stand in with your phase, for any other with the normal one.
    events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    events:SetScript("OnEvent", onEvent)
end
