-- Run from the repository root with Lua 5.1.
local function newRegion(parent)
    local region = { parent = parent, shown = true, scripts = {}, events = {}, level = 1, width = 37 }
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown end
    function region:SetAllPoints() end
    function region:SetPoint() end
    function region:SetSize() end
    function region:SetTexture(t) self.texture = t end
    function region:SetBlendMode() end
    function region:SetVertexColor() end
    function region:SetTextColor() end
    function region:SetText(t) self.text = t end
    function region:GetWidth() return self.width end
    function region:SetFrameLevel(l) self.level = l end
    function region:GetFrameLevel() return self.level end
    function region:GetParent() return self.parent end
    function region:GetID() return self.id end
    function region:GetName() return self.name end
    function region:SetScript(event, fn) self.scripts[event] = fn end
    function region:RegisterEvent(event) self.events[event] = true end
    function region:CreateTexture() return newRegion(self) end
    function region:CreateFontString() return newRegion(self) end
    function region:CreateAnimationGroup()
        local group = { playing = false }
        function group:CreateAnimation()
            return { SetOrder = function() end, SetChange = function() end,
                SetDuration = function() end, SetSmoothing = function() end }
        end
        function group:SetLooping() end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        function group:IsPlaying() return self.playing end
        return group
    end
    return region
end

function CreateFrame(_, name, parent)
    local frame = newRegion(parent)
    frame.name = name
    return frame
end

local hooks = {}
function hooksecurefunc(name, fn) hooks[name] = fn end

NUM_BAG_SLOTS = 4
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
NUM_CONTAINER_FRAMES = 0
LOOTFRAME_NUMBUTTONS = 4

function GetAuctionItemClasses()
    return "Weapon", "Armor", "Container", "Consumable", "Glyph", "Trade Goods", "Projectile", "Quiver",
        "Recipe", "Gem", "Miscellaneous", "Quest"
end
function GetAuctionItemSubClasses(class)
    if class == 11 then return "Junk", "Reagent", "Pet", "Holiday", "Other", "Mount" end
    return "One-Handed Axes", "Two-Handed Axes", "Bows", "Guns", "One-Handed Maces", "Two-Handed Maces",
        "Polearms", "One-Handed Swords", "Two-Handed Swords", "Staves", "Fist Weapons", "Miscellaneous",
        "Daggers", "Thrown", "Crossbows", "Wands", "Fishing Poles"
end

-- id = { quality, class, subclass, vendor price }
local items = {
    [1] = { 0, "Miscellaneous", "Junk", 50 },       -- gray trash
    [2] = { 1, "Armor", "Cloth", 30 },               -- white gear
    [3] = { 2, "Armor", "Mail", 10 },                -- green gear
    [4] = { 1, "Consumable", "Food & Drink", 1 },   -- bread
    [5] = { 1, "Trade Goods", "Cloth", 2 },          -- linen
    [6] = { 1, "Recipe", "Cooking", 5 },
    [2901] = { 1, "Trade Goods", "Trade Goods", 4 }, -- Mining Pick
    [6256] = { 1, "Weapon", "Fishing Poles", 5 },   -- Fishing Pole
    [6948] = { 1, "Miscellaneous", "Junk", 0 },     -- Hearthstone
    [7] = { 1, "Quest", "Quest", 3 },
    [8] = { 1, "Armor", "Leather", 0 },              -- cannot be sold
    [9] = { 1, "Armor", "Leather", 200 },            -- loot: dear
    [10] = { 0, "Miscellaneous", "Junk", 1 },       -- loot: cheap
}
function GetItemInfo(id)
    if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
    local it = items[id]
    if not it then return end
    return "Item" .. id, "item:" .. id, it[1], 1, 1, it[2], it[3], 20, "", "", it[4]
end

local bags = {}
local function SetBags(contents)
    bags = { [0] = {}, {}, {}, {}, {} }
    for bag, slots in pairs(contents) do bags[bag] = slots end
end
local bagSize = { [0] = 4, 0, 0, 0, 0 }
function GetContainerNumSlots(bag) return bagSize[bag] or 0 end
function GetContainerNumFreeSlots(bag)
    local free = 0
    for slot = 1, GetContainerNumSlots(bag) do
        if not (bags[bag] and bags[bag][slot]) then free = free + 1 end
    end
    return free, 0
end
function GetContainerItemID(bag, slot)
    local cell = bags[bag] and bags[bag][slot]
    return cell and cell[1]
end
function GetContainerItemInfo(bag, slot)
    local cell = bags[bag] and bags[bag][slot]
    if cell then return "tex", cell[2] or 1, nil, items[cell[1]][1], nil, nil, "item:" .. cell[1] end
end
function GetContainerItemQuestInfo() return nil end

local loot = {}
function GetNumLootItems() return #loot end
function LootSlotIsItem(i) return loot[i] ~= nil end
function GetLootSlotLink(i) return "item:" .. loot[i][1] end
function GetLootSlotInfo(i) return "tex", "Item", loot[i][2] or 1, 1, nil end

local alt = false
function IsAltKeyDown() return alt end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }

local function Button(name, bag, slot)
    local parent = newRegion()
    parent.id = bag
    local button = newRegion(parent)
    button.name, button.id = name, slot
    _G[name] = button
    return button
end

local profile = {
    bags = {
        triage_mode = "always", triage_style = "border", triage_quality = 1, triage_marks = 3,
        triage_keep_consumables = true, triage_keep_materials = true, triage_keep_tools = true,
        triage_keep_recipes = true, triage_sort = true,
    },
    modules = { bagsort = { enabled = true, lock_hotkey = "ALT_LEFT" } },
}
local addon = {
    db = { profile = profile, char = {} },
    L = setmetatable({}, { __index = function(_, key) return key end }),
}
-- The deferred-recompute driver is the module's one unnamed frame with an OnUpdate script.
local created = {}
do
    local origCreate = CreateFrame
    CreateFrame = function(...)
        local f = origCreate(...)
        created[#created + 1] = f
        return f
    end
    assert(loadfile("DragonUI/modules/bags_triage.lua"))("DragonUI", addon)
    CreateFrame = origCreate
end
local LT = addon.LootTriage
local driver
for _, f in ipairs(created) do
    if f.scripts.OnUpdate then driver = f end
end
assert(driver, "driver frame")

local failures = 0
local function check(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

-- Runs the recompute the client would run on the next frame.
local function Update(event)
    if event then driver.scripts.OnEvent(driver, event) end
    driver.scripts.OnUpdate(driver)
end

-- Ranking: cheapest stack first, consumables/materials/tools/recipes/quest/unsellable/Hearthstone skipped.
SetBags({ [0] = { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 20 } } })
bagSize[0] = 4
local s1, s2, s3, s4 = Button("Slot1", 0, 1), Button("Slot2", 0, 2), Button("Slot3", 0, 3), Button("Slot4", 0, 4)
local container = newRegion()
container.name, container.id, container.size = "ContainerFrame1", 0, 4
ContainerFrame1Item1, ContainerFrame1Item2, ContainerFrame1Item3, ContainerFrame1Item4 = s1, s2, s3, s4
s1.name, s2.name, s3.name, s4.name = "ContainerFrame1Item1", "ContainerFrame1Item2", "ContainerFrame1Item3", "ContainerFrame1Item4"
Update("BAG_UPDATE")
local active, cheapest, free = LT:GetState()
check(active, "always mode is active")
check(cheapest == 30, "white cloth (30c) is the cheapest candidate, got " .. tostring(cheapest))
check(free == 0, "no free slots")
LT:UpdateContainer(container)
check(s2._duiTriage and s2._duiTriage:IsShown() and s2._duiTriage.number.text == 1, "white gear numbered 1")
check(s1._duiTriage and s1._duiTriage.number.text == 2, "gray (50c) numbered 2")
check(not (s3._duiTriage and s3._duiTriage:IsShown()), "green skipped at quality 1")
check(not (s4._duiTriage and s4._duiTriage:IsShown()), "bread skipped as a consumable")

-- Stack value: 20 bread at 1c = 20c, cheaper than the white gear once consumables are allowed.
profile.bags.triage_keep_consumables = false
Update()
LT:UpdateContainer(container)
check(s4._duiTriage.number.text == 1, "bread stack (20c) numbered 1 when consumables allowed")
profile.bags.triage_keep_consumables = true

-- Greens join at quality 2.
profile.bags.triage_quality = 2
Update()
LT:UpdateContainer(container)
check(s3._duiTriage and s3._duiTriage.number.text == 1, "green (10c) numbered 1 at quality 2")
profile.bags.triage_quality = 1

-- Marks cap.
profile.bags.triage_marks = 1
Update()
LT:UpdateContainer(container)
check(not s1._duiTriage:IsShown(), "only one item numbered with marks = 1")
profile.bags.triage_marks = 3

-- Never suggested.
for _, id in ipairs({ 5, 6, 2901, 6256, 6948, 7, 8 }) do
    check(LT:UnitPrice(id) == nil, "item " .. id .. " never suggested")
end
profile.bags.triage_keep_tools = false
check(LT:UnitPrice(6256) == 5, "fishing pole suggested when tools allowed")
profile.bags.triage_keep_tools = true

-- Pulse style plays the animation.
profile.bags.triage_style = "pulse"
Update()
LT:UpdateContainer(container)
check(s2._duiTriage.pulse:IsPlaying(), "pulse style animates")
profile.bags.triage_style = "border"
Update()
LT:UpdateContainer(container)
check(not s2._duiTriage.pulse:IsPlaying(), "border style is static")

-- Star: Alt + Right Click keeps the item and shows the star; Alt + Left (bag sort lock) does nothing.
alt = true
hooks.ContainerFrameItemButton_OnModifiedClick(s2, "LeftButton")
check(not LT:IsKept(2), "alt-left does not star")
hooks.ContainerFrameItemButton_OnModifiedClick(s2, "RightButton")
check(LT:IsKept(2), "alt-right stars")
check(printed[1] and printed[1]:find("never suggest"), "star prints a line")
Update()
LT:UpdateContainer(container)
check(s2._duiTriage.star:IsShown() and not s2._duiTriage.number:IsShown(), "starred item shows the star, no number")
check(s1._duiTriage.number.text == 1, "gray moves up to 1 once the white is starred")
AuctionFrame = newRegion()
hooks.ContainerFrameItemButton_OnModifiedClick(s2, "RightButton")
check(LT:IsKept(2), "no toggle while the auction house is open")
AuctionFrame = nil
profile.modules.bagsort.lock_hotkey = "ALT_RIGHT"
hooks.ContainerFrameItemButton_OnModifiedClick(s2, "RightButton")
check(LT:IsKept(2), "bag sort's lock wins when it uses Alt + Right Click")
profile.modules.bagsort.lock_hotkey = "ALT_LEFT"
hooks.ContainerFrameItemButton_OnModifiedClick(s2, "RightButton")
check(not LT:IsKept(2), "alt-right again unstars")
alt = false

-- Loot coins: only loot worth more than the cheapest candidate, and quest items.
local l1, l2, l3 = Button("LootButton1", nil, 1), Button("LootButton2", nil, 2), Button("LootButton3", nil, 3)
l1.slot, l2.slot, l3.slot = 1, 2, 3
loot = { { 9, 1 }, { 10, 5 }, { 7, 1 } }
Update("LOOT_OPENED")
check(l1._duiTriageCoin and l1._duiTriageCoin:IsShown(), "200c leather gets a coin")
check(not (l2._duiTriageCoin and l2._duiTriageCoin:IsShown()), "5c of gray loot gets none")
check(l3._duiTriageCoin and l3._duiTriageCoin:IsShown(), "quest item gets a coin")

-- Loot mode: only while the loot does not fit.
profile.bags.triage_mode = "loot"
Update()
check((LT:GetState()), "loot mode active: 3 items, 0 free")
Update("LOOT_CLOSED")
check(not (LT:GetState()), "loot mode inactive once looting ends")
LT:UpdateContainer(container)
check(not s1._duiTriage:IsShown(), "marks hidden outside looting in loot mode")
bags[0][1], bags[0][2], bags[0][3] = nil, nil, nil
loot = { { 9, 1 } }
Update("LOOT_OPENED")
check(not (LT:GetState()), "loot mode inactive when the loot fits")
Update("LOOT_CLOSED")

-- Nearly full: active at 4 or fewer free slots without looting.
SetBags({ [0] = { { 1, 1 } } })
bagSize[0] = 10
profile.bags.triage_mode = "nearly"
Update()
check(not (LT:GetState()), "nearly mode inactive with 9 free")
bagSize[0] = 5
Update()
check((LT:GetState()), "nearly mode active with 4 free")

-- Off clears everything.
profile.bags.triage_mode = "off"
Update()
check(not (LT:GetState()), "off mode inactive")
check(not LT:SortsJunkLast(), "no junk-last sort when off")
profile.bags.triage_mode = "loot"
check(LT:SortsJunkLast(), "junk-last sort on by default")

if failures > 0 then
    print(failures .. " check(s) failed")
    os.exit(1)
end
print("loot triage: all checks passed")
