-- Run from the repository root with Lua 5.1.
-- Wrath supplies bit.band; standalone Lua 5.1 does not. Flags here are nonnegative integers.
bit = bit or { band = function(a, b)
    local result, place = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end }
local now = 100
format = string.format
function GetTime() return now end

local timers = {}
local addon = { L = setmetatable({}, { __index = function(_, key) return key end }), WorldMap = {} }
function addon:After(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end
local function advance(seconds)
    now = now + seconds
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= now then
            due[#due + 1] = timers[i]
            table.remove(timers, i)
        end
    end
    for i = #due, 1, -1 do due[i].fn() end
end

local function newRegion()
    local region = { shown = true, scripts = {}, events = {}, points = {}, scale = 1 }
    function region:SetSize(w, h) self.w, self.h = w, h end
    function region:GetWidth() return self.w or 0 end
    function region:GetHeight() return self.h or 0 end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:ClearAllPoints() self.points = {} end
    function region:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function region:SetAllPoints() end
    function region:SetScript(event, fn) self.scripts[event] = fn end
    function region:RegisterEvent(event) self.events[event] = true end
    function region:SetScale(value) self.scale = value end
    function region:SetFrameLevel() end
    function region:GetFrameLevel() return 1 end
    function region:SetTexture(path) self.texture = path end
    function region:SetTexCoord() end
    function region:SetBlendMode() end
    function region:SetAlpha() end
    function region:SetDesaturated(value) self.desaturated = value and true or false end
    function region:SetAtlasTexture(name) self.texture = "atlas:" .. name end
    function region:CreateTexture() return newRegion() end
    return region
end

local frames = {}
function CreateFrame()
    local frame = newRegion()
    frames[#frames + 1] = frame
    return frame
end
function hooksecurefunc() end

local sent = {}
function SendAddonMessage(prefix, msg, channel, target)
    assert(prefix == "QMP" and channel == "WHISPER" and target == "Me")
    sent[#sent + 1] = msg
end
function UnitName() return "Me" end
function UnitFactionGroup() return "Alliance" end
function GetLocale() return "enUS" end
function GetBindLocation() return "" end
function GetMapInfo() return "Elwynn" end
function GetCurrentMapDungeonLevel() return 0 end
local mapArea = 31
function GetCurrentMapAreaID() return mapArea end
function GetQuestDifficultyColor(level) return { r = level, g = 0, b = 0 } end
local questCount = 5
function GetNumQuestLogEntries() return questCount + 2, questCount end
GameTooltip = { lines = {} }
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:SetText(text) self.lines[#self.lines + 1] = text end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:Show() end
function GameTooltip:Hide() end

WorldMapFrame = newRegion()
WorldMapButton = newRegion()
WorldMapButton:SetSize(1000, 667)

local WM = addon.WorldMap
local config = { questGivers = true, trivialQuests = false }
function WM:Config() return config end
function WM.OnTerrainFloor() return true end
WM.canvasScale = 1
WM.FlightPointName, WM.InnAreaIDs, WM.InnAreaName, WM.InnRoomName = {}, {}, {}, {}
WM.Entrances, WM.FlightPoints, WM.Inns, WM.Graveyards = {}, {}, {}, {}

assert(loadfile("DragonUI/modules/worldmap/questgivers.lua"))("DragonUI", addon)
assert(loadfile("DragonUI/modules/worldmap/mappins.lua"))("DragonUI", addon)
WM.BuildQuestGivers()
WM.BuildMapPins()
local events = frames[1]
assert(events.events.CHAT_MSG_ADDON and events.events.QUEST_LOG_UPDATE)

local function receive(message, sender)
    events.scripts.OnEvent(events, "CHAT_MSG_ADDON", "QMP", message, "WHISPER", sender or "Me")
end
local function event(name)
    events.scripts.OnEvent(events, name)
end
local function shownPins()
    local pins = {}
    for _, frame in ipairs(frames) do
        if frame.icon and frame.shown then pins[#pins + 1] = frame end
    end
    return pins
end

-- 1. Without the server module: one hello, its echo ignored, then nothing more.
WM.RefreshMapPins()
assert(#sent == 1 and sent[1] == "HELLO:0:1", sent[1])
receive(sent[1])
advance(5)
WM.RefreshMapPins()
mapArea = 15
WM.RefreshMapPins()
assert(#sent == 1, "asked again without a server")
assert(#shownPins() == 0)
print("ok - no server: one hello, no requests, no pins")

-- 2. A fresh load with the server: hello, then the shown map is asked for.
for k in pairs(package.loaded) do if k:match("questgivers") then package.loaded[k] = nil end end
frames, sent, timers = {}, {}, {}
addon.WorldMap = {}
WM = addon.WorldMap
function WM:Config() return config end
function WM.OnTerrainFloor() return true end
WM.canvasScale = 1
WM.FlightPointName, WM.InnAreaIDs, WM.InnAreaName, WM.InnRoomName = {}, {}, {}, {}
WM.Entrances, WM.FlightPoints, WM.Inns, WM.Graveyards = {}, {}, {}, {}
assert(loadfile("DragonUI/modules/worldmap/questgivers.lua"))("DragonUI", addon)
assert(loadfile("DragonUI/modules/worldmap/mappins.lua"))("DragonUI", addon)
WM.BuildQuestGivers()
WM.BuildMapPins()
events = frames[1]
mapArea = 31
event("QUEST_LOG_UPDATE") -- the first count is only remembered

WM.RefreshMapPins()
assert(sent[1] == "HELLO:0:1")
receive("HI:0:1:1")
advance(0.5)
assert(sent[2] == "A:1:30", tostring(sent[2]))
-- The echo of our own request is not an answer.
receive(sent[2])
receive("AR:1:30:3")
receive("AD:1:G,0,5000,2500,Marshal Dughan;Q,0,40,10,0,A Fishy Peril;Q,0,35,7,2,Further Concerns")
receive("AD:1:G,1,1000,9000,Wanted%3A Hogger;Q,1,176,11,0,Wanted%3A %22Hogger%22;G,2,200,200,Old Timer;Q,2,9000,1,2,Grey One")
receive("AD:1:G,3,300,300,Daily Gal;Q,3,9001,10,1,Every Day")
receive("AE:1")
advance(0.5)
local pins = shownPins()
assert(#pins == 3, "trivial-only giver should be hidden, got " .. #pins)
local byName = {}
for _, pin in ipairs(pins) do byName[pin.name] = pin end
assert(byName["Marshal Dughan"] and byName["Wanted: Hogger"] and byName["Daily Gal"])
assert(#byName["Marshal Dughan"].quests == 1, "trivial quest listed")
assert(byName["Wanted: Hogger"].quests[1].title == 'Wanted: "Hogger"')
assert(byName["Daily Gal"].icon.texture:match("DailyQuestIcon"))
assert(byName["Marshal Dughan"].icon.texture:match("AvailableQuestIcon") and not byName["Marshal Dughan"].icon.desaturated)
byName["Marshal Dughan"].scripts.OnEnter(byName["Marshal Dughan"])
assert(GameTooltip.lines[1] == "Marshal Dughan" and GameTooltip.lines[2]:match("%[10%] A Fishy Peril"))
print("ok - server answer parsed, pins drawn, trivial quests hidden")

-- 3. Cached: another refresh asks nothing.
local before = #sent
WM.RefreshMapPins()
assert(#sent == before)

-- 4. Trivial quests on: the grey giver shows, desaturated.
config.trivialQuests = true
WM.RefreshMapPins()
pins = shownPins()
assert(#pins == 4)
for _, pin in ipairs(pins) do
    if pin.name == "Old Timer" then assert(pin.icon.desaturated) end
    if pin.name == "Marshal Dughan" then assert(#pin.quests == 2 and not pin.icon.desaturated) end
end
config.trivialQuests = false
print("ok - trivial toggle")

-- 5. An objective update changes nothing; a quest taken makes the map stale.
event("QUEST_LOG_UPDATE")
WM.RefreshMapPins()
assert(#sent == before, "objective update re-asked")
questCount = 6
event("QUEST_LOG_UPDATE")
advance(0.5)
assert(sent[#sent] == "A:2:30", tostring(sent[#sent]))
-- The stale pins stay up until the answer.
assert(#shownPins() == 3)
receive("AR:2:30:0")
receive("AE:2")
advance(0.5)
assert(#shownPins() == 0)
print("ok - quest log change refetches; objective updates do not")

-- 6. Busy: retried once later; a lost answer is asked again after the wait.
event("PLAYER_LEVEL_UP")
advance(0.5)
local busyReq = sent[#sent]:match("^A:(%d+):30$")
assert(busyReq)
receive("ERR:" .. busyReq .. ":busy")
advance(1)
assert(sent[#sent]:match("^A:%d+:30$") and sent[#sent] ~= "A:" .. busyReq .. ":30")
before = #sent
WM.RefreshMapPins()
assert(#sent == before, "asked twice while waiting")
advance(11)
WM.RefreshMapPins()
assert(#sent == before + 1, "lost answer not asked again")
-- A map flicked past is not retried; the shown one, out of retries, tries again a little later.
mapArea = 16
WM.RefreshMapPins()
local flicked = sent[#sent]:match("^A:(%d+):15$")
assert(flicked)
mapArea = 31
receive("ERR:" .. flicked .. ":busy")
before = #sent
advance(3)
assert(#sent == before, "retried a map no longer shown")
local function lastAsk(area)
    for i = #sent, 1, -1 do
        local req = sent[i]:match("^A:(%d+):" .. area .. "$")
        if req then return req, i end
    end
end
-- Three retries, then one more try a little later: each answer below is busy.
local asks = 0
for _ = 1, 5 do
    local req, at = lastAsk(30)
    receive("ERR:" .. req .. ":busy")
    advance(5)
    advance(1) -- the refresh a late try queues
    local _, nextAt = lastAsk(30)
    if nextAt > at then asks = asks + 1 end
end
assert(asks == 5, "shown map given up after busy: " .. asks)
print("ok - busy retry, lost answer, flicked-past maps")

-- 6b. Entering another zone makes cached maps stale (the phase may differ there).
local req = lastAsk(30)
receive("AR:" .. req .. ":30:0")
receive("AE:" .. req)
advance(0.5)
before = #sent
WM.RefreshMapPins()
assert(#sent == before)
event("ZONE_CHANGED_NEW_AREA")
advance(0.5)
assert(#sent == before + 1 and sent[#sent]:match("^A:%d+:30$"))
req = sent[#sent]:match("^A:(%d+):30$")
receive("AE:" .. req)
advance(0.5)
print("ok - zone change refetches")

-- 7. Off: no pins and no requests; a floor or a continent asks nothing.
config.questGivers = false
before = #sent
WM.RefreshMapPins()
assert(#sent == before and #shownPins() == 0)
config.questGivers = true
mapArea = 0
WM.RefreshMapPins()
assert(#sent == before)
print("ok - toggle off, continents")
