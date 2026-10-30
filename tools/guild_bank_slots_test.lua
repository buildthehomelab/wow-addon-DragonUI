-- Run from the repository root with Lua 5.1.
-- The guild bank's slots per tab: 98 until the realm whispers "EvermoreGuildBank" "slots:<n>".
local failures, checks = 0, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL: " .. label)
    end
end

local frames = {}
local methods = {}
methods.__index = function(_, key)
    if methods[key] then return methods[key] end
    if key:match("^%u") then return function() end end  -- widget methods; fields stay nil
end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h)
    self.height = h
    if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self) end
end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetID(id) self.id = id end
function methods:GetID() return self.id end
function methods:GetParent() return self.parent end
function methods:SetPoint(...) self.point = {...} end
function methods:SetScale(s) self.scale = s end
function methods:SetMaxResize(w, h) self.maxResize = {w, h} end
local function widget() return setmetatable({scripts = {}, events = {}}, methods) end
function methods:CreateTexture() return widget() end
function methods:CreateFontString() return widget() end
function methods:GetFrameLevel() return 1 end
for _, getter in ipairs({"GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture",
                         "GetDisabledTexture", "GetFontString", "GetRegions", "GetScrollChild"}) do
    methods[getter] = function(self)
        self["_" .. getter] = self["_" .. getter] or widget()
        return self["_" .. getter]
    end
end
function CreateFrame(_, name, parent)
    local f = setmetatable({name = name, parent = parent, scripts = {}, events = {}}, methods)
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent.height = 1000
local player = "Squishy"
function UnitName() return player end
local realm = "Evermore"
function GetRealmName() return realm end
function GetAuctionItemClasses() return "Weapon" end
function GetGuildBankItemInfo() return nil end
function GetGuildBankItemLink() return nil end
function SetItemButtonTexture() end
function SetItemButtonCount() end
function SetItemButtonDesaturated() end
GameTooltip = {IsOwned = function() return false end}

-- Everything else the window touches: callable, indexable and does nothing.
local stub
stub = setmetatable({}, {__index = function() return stub end, __call = function() return nil end})
setmetatable(_G, {__index = function(_, key)
    if key:match("^MAX_GUILDBANK") then return nil end  -- Blizzard_GuildBankUI isn't loaded
    return stub
end})

local mod = {}
function mod:NewClass()
    local class = {}
    function class:Bind(obj)
        for k, v in pairs(class) do
            if k ~= "Bind" and k ~= "New" then rawset(obj, k, v) end
        end
        return obj
    end
    return class
end
function mod.GetModuleConfig() return {item_spacing = 2} end
function mod.BagsterRetailItemSlot() end
mod.ItemSearch = {Find = function() return false end}
mod.BagsterModule = {applied = true}
setmetatable(mod, {__index = function(_, key) if key:match("^%u") then return stub end end})
mod.DB = false -- no saved variables yet
local addon = setmetatable({BagsterModule = mod, WindowSeat = {buttonBottom = 8}}, {__index = function() return stub end})

local listener
-- Loading the file again is a new session: nothing heard from the realm yet.
local function load()
    frames = {}
    assert(loadfile("DragonUI/modules/bagster/bagster_guild.lua"))("DragonUI", addon)
    for _, f in ipairs(frames) do
        if f.events.CHAT_MSG_ADDON then listener = f end
    end
end
load()
check(listener ~= nil, "a frame listens for CHAT_MSG_ADDON at load")
local function whisper(prefix, message, channel, sender)
    listener.scripts.OnEvent(listener, "CHAT_MSG_ADDON", prefix, message, channel or "WHISPER", sender or player)
end

check(addon.GetGuildBankSlots() == 98, "98 slots before the realm says anything")
whisper("EvermoreGuildBank", "slots:196", "WHISPER", "Someone")
check(addon.GetGuildBankSlots() == 98, "a whisper from another player is ignored")
whisper("EvermoreGuildBank", "slots:196", "GUILD")
check(addon.GetGuildBankSlots() == 98, "a guild channel message is ignored")
whisper("OtherPrefix", "slots:196")
check(addon.GetGuildBankSlots() == 98, "another prefix is ignored")
whisper("EvermoreGuildBank", "slots:250")
check(addon.GetGuildBankSlots() == 98, "more than 196 is ignored")
whisper("EvermoreGuildBank", "slots:50")
check(addon.GetGuildBankSlots() == 98, "fewer than 98 is ignored")
whisper("EvermoreGuildBank", "slots:abc")
check(addon.GetGuildBankSlots() == 98, "junk is ignored")

-- The item grid on its own.
local grid = mod.GuildItemFrame:New(UIParent)
check(#grid.items == 98 and grid:GetRows() == 7, "the grid starts with 98 buttons in 7 rows")
grid.width, grid.height = 14 * 40, 14 * 40
grid:SetSlotCount(196)
grid:Layout()
check(#grid.items == 196 and grid:GetRows() == 14, "196 slots make 196 buttons in 14 rows")
local last = grid.items[196]
check(last.shown and last.point[4] == 13 * 40 + 2 and last.point[5] == -(13 * 40 + 2), "slot 196 sits at row 14, column 14")
check(math.abs(last.scale - 1) < 1e-9, "icons keep their size when the grid is 14 rows tall")
grid:SetSlotCount(98)
grid:Layout()
check(#grid.items == 196 and not grid.items[99].shown and grid.items[98].shown, "back to 98 hides slots 99-196")

-- The window (its row fitting, on a bare frame): 14 rows need a taller window at the same width.
local sets = {w = 590, h = 382}
local function newWindow(count)
    local w = mod.GuildFrame:Bind(CreateFrame("Frame", nil, UIParent))
    w.sets, w.width, w.height = sets, sets.w, sets.h
    w.itemFrame = mod.GuildItemFrame:New(w)
    w.itemFrame:SetSlotCount(count)
    w.logFrame, w.infoBox, w.infoEdit = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
    w:SetScript("OnSizeChanged", function(self) self.sets.h = self:GetHeight() end)
    return w
end
local window = newWindow(98)
window:FitRows()
check(window.height == 382 and sets.rows == 7, "98 slots keep a height saved without rows")
whisper("EvermoreGuildBank", "slots:196")
check(addon.GetGuildBankSlots() == 196, "the realm's 196 is taken")
window:SetSlotCount(196)
-- width 590 -> grid 560 = 14 * 40 at scale 1: 14 rows of 40 + 92
check(window.height == 14 * 40 + 92, "the 7-row height grows to fit 14 rows (" .. tostring(window.height) .. ")")
check(sets.rows == 14 and sets.h == window.height, "the new height and its rows are saved")
check(window.maxResize and window.maxResize[2] == 14 * 60 + 96, "the resize cap follows 14 rows")
local again = newWindow(196)
again:FitRows()
check(again.height == 14 * 40 + 92, "a window made later with 196 slots keeps the saved height")
UIParent.height = 500
sets.rows = 7
local small = newWindow(196)
small:FitRows()
check(small.height == 460, "never taller than the screen")
local back = newWindow(98)
sets.rows, sets.h = 14, 652
back.height = 652
back:FitRows()
check(back.height < 652 and sets.rows == 7, "on a 98-slot realm a 14-row height shrinks back")

check(math.abs(back.height - 372) < 1e-9, "back to 7 rows at width 590 (" .. tostring(back.height) .. ")")
local narrow = newWindow(98)
sets.w, sets.rows = 384, 14
narrow.width = 384
narrow:FitRows()
check(narrow.height == 350, "never under the window's 350 minimum (" .. tostring(narrow.height) .. ")")

-- The realm's count is remembered by realm name, for the next session's first open.
mod.DB = {guild = {}}
load()
check(addon.GetGuildBankSlots() == 98, "a new session on a realm never heard from: 98")
whisper("EvermoreGuildBank", "slots:196")
check(mod.DB.guild.realmSlots and mod.DB.guild.realmSlots.Evermore == 196, "the realm's 196 is saved under its name")
load()
check(addon.GetGuildBankSlots() == 196, "the next session starts with the saved 196, before any whisper")
local seeded = mod.GuildItemFrame:New(UIParent)
check(#seeded.items == 196, "a window made then has 196 buttons at once")
realm = "Other"
check(addon.GetGuildBankSlots() == 98, "another realm doesn't get it")
realm = "Evermore"
whisper("EvermoreGuildBank", "slots:98")
check(addon.GetGuildBankSlots() == 98 and mod.DB.guild.realmSlots.Evermore == nil, "the realm going back to 98 is heard and forgotten")
load()
check(addon.GetGuildBankSlots() == 98, "and stays 98 the session after")

-- Which window opens. With the Bagster bags off, DragonUI's window still replaces the stock vault
-- once the realm says its tabs are bigger: the stock one has 98 buttons.
local function stockLoader() end
local watcher
local opened
local function openBank()
    watcher.scripts.OnEvent(watcher, "GUILDBANKFRAME_OPENED")
end
local function fresh(applied, db)
    GuildBankFrame_LoadUI = stockLoader
    mod.BagsterModule.applied = applied
    mod.DB = db
    load()
    for _, f in ipairs(frames) do
        if f.events.GUILDBANKFRAME_OPENED then watcher = f end
    end
    mod.guildFrame, opened = nil, 0
    mod.GuildFrame.New = function()
        local w = {itemFrame = {}}
        function w.Show() opened = opened + 1 end
        function w.Hide() end
        function w.SetSlotCount() end
        return w
    end
end
mod.SetupDatabase = function() mod.DB = {guild = {}} end

fresh(false, false) -- no layout db: the Bagster bags never ran
check(watcher ~= nil, "a frame watches GUILDBANKFRAME_OPENED")
openBank()
check(opened == 0 and GuildBankFrame_LoadUI == stockLoader, "Bagster off, 98-slot realm: the stock vault opens")
whisper("EvermoreGuildBank", "slots:98")
openBank()
check(opened == 0 and GuildBankFrame_LoadUI == stockLoader, "a realm saying 98 keeps the stock vault")
whisper("EvermoreGuildBank", "slots:196")
check(GuildBankFrame_LoadUI ~= stockLoader, "Bagster off, realm says 196: the stock vault's loader is blanked")
check(mod.DB and mod.DB.guild.realmSlots.Evermore == 196, "and the count is saved without the Bagster bags")
openBank()
check(opened == 1, "DragonUI's window opens instead")
whisper("EvermoreGuildBank", "slots:98")
check(GuildBankFrame_LoadUI == stockLoader, "the realm going back to 98 gives the stock vault back")
openBank()
check(opened == 1, "and DragonUI's window stays shut")

fresh(true, {guild = {}})
mod.UpdateGuildBankOwner()
check(GuildBankFrame_LoadUI ~= stockLoader, "Bagster on: the stock vault's loader is blanked")
openBank()
check(opened == 1, "Bagster on, 98-slot realm: DragonUI's window opens")
whisper("EvermoreGuildBank", "slots:196")
mod.BagsterModule.applied = false
mod.UpdateGuildBankOwner()
check(GuildBankFrame_LoadUI ~= stockLoader, "turning Bagster off on a 196-slot realm keeps DragonUI's window")
whisper("EvermoreGuildBank", "slots:98")
check(GuildBankFrame_LoadUI == stockLoader, "and a 98-slot realm then gets the stock vault back")

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
