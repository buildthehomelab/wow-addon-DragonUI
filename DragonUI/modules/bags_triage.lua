-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- Loot triage for full bags: numbers the cheapest items in the bags as the ones to delete first,
-- and puts a coin on loot worth more than the cheapest of them. Works on Bagster and the stock bags.
local addon = select(2, ...)
local L = addon.L

local LootTriage = {}
addon.LootTriage = LootTriage

local _G, pairs, ipairs, wipe, sort, select = _G, pairs, ipairs, wipe, table.sort, select
local GetContainerItemID, GetContainerItemInfo = GetContainerItemID, GetContainerItemInfo

local HEARTHSTONE = 6948
-- Free general bag slots at or under which "nearly full" bags get their marks.
local NEARLY_FULL_FREE = 4
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0
local BORDER_TEXTURE = [[Interface\Buttons\UI-ActionButton-Border]]
local STAR_TEXTURE = [[Interface\TargetingFrame\UI-RaidTargetingIcon_1]]
local COIN_TEXTURE = [[Interface\MoneyFrame\UI-GoldIcon]]

-- Profession tools sell for a few copper but are the last thing to throw away.
local TOOLS = {
    [2901] = true,  -- Mining Pick
    [5956] = true,  -- Blacksmith Hammer
    [7005] = true,  -- Skinning Knife
    [4471] = true,  -- Flint and Tinder
    [5060] = true,  -- Thieves' Tools
    [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true, -- Runed enchanting rods
    [22461] = true, [22462] = true, [22463] = true, [44452] = true,
    [6219] = true,  -- Arclight Spanner
    [10498] = true, -- Gyromatic Micro-Adjustor
    [9149] = true,  -- Philosopher's Stone
    [20815] = true, -- Jeweler's Kit
    [39505] = true, -- Virtuoso Inking Set
    [40772] = true, -- Gnomish Army Knife
}

local classNames
local function Classes()
    if classNames then return classNames end
    local weapon, _, _, consumable, _, trade, projectile, _, recipe, gem, misc, quest = GetAuctionItemClasses()
    local _, reagent = GetAuctionItemSubClasses(11)
    local fishing = select(17, GetAuctionItemSubClasses(1))
    classNames = {
        weapon = weapon, consumable = consumable, trade = trade, projectile = projectile, recipe = recipe,
        gem = gem, misc = misc, quest = quest, reagent = reagent, fishing = fishing,
    }
    return classNames
end

local function Config() return addon.db.profile.bags end

local function Mode()
    local cfg = addon.db and addon.db.profile and Config()
    return cfg and cfg.triage_mode or "off"
end

local function Kept(create)
    local char = addon.db and addon.db.char
    if not char then return end
    if create and not char.triage_keep then char.triage_keep = {} end
    return char.triage_keep
end

-- Vendor price of one unit when the item may be suggested for deletion, else nil.
function LootTriage:UnitPrice(itemID, bag, slot)
    local name, _, quality, _, _, class, subclass, _, _, _, price = GetItemInfo(itemID)
    if not name or not price or price <= 0 or itemID == HEARTHSTONE then return end
    local cfg = Config()
    if (quality or 0) > (cfg.triage_quality or 1) then return end
    local kept = Kept(false)
    if kept and kept[itemID] then return end
    local c = Classes()
    if class == c.quest or (bag and GetContainerItemQuestInfo and GetContainerItemQuestInfo(bag, slot)) then return end
    if cfg.triage_keep_consumables ~= false and (class == c.consumable or class == c.projectile) then return end
    if cfg.triage_keep_materials ~= false
        and (class == c.trade or class == c.gem or (class == c.misc and subclass == c.reagent)) then return end
    if cfg.triage_keep_recipes ~= false and class == c.recipe then return end
    if cfg.triage_keep_tools ~= false and (TOOLS[itemID] or (class == c.weapon and subclass == c.fishing)) then return end
    return price
end

function LootTriage:IsKept(itemID)
    local kept = Kept(false)
    return kept and itemID and kept[itemID] or false
end

-- Bag sort puts candidates last (cheapest in the very last slot) while this is on.
function LootTriage:SortsJunkLast()
    return Mode() ~= "off" and Config().triage_sort ~= false
end

-- ============================================================================
-- STATE
-- ============================================================================

local candidates, rank = {}, {}
for bag = 0, NUM_BAG_SLOTS do rank[bag] = {} end
local cheapest, freeSlots, lootNeed, looting, active = nil, 0, 0, false, false

local function ByValue(a, b)
    if a.value ~= b.value then return a.value < b.value end
    if a.bag ~= b.bag then return a.bag > b.bag end
    return a.slot > b.slot
end

local function CountLootItems()
    local need = 0
    for i = 1, GetNumLootItems() do
        if LootSlotIsItem(i) then need = need + 1 end
    end
    return need
end

local function Recompute()
    for bag = 0, NUM_BAG_SLOTS do wipe(rank[bag]) end
    wipe(candidates)
    cheapest, freeSlots = nil, 0
    local mode = Mode()
    if mode == "off" then active = false return end

    for bag = 0, NUM_BAG_SLOTS do
        local free, family = GetContainerNumFreeSlots(bag)
        if family == 0 then freeSlots = freeSlots + (free or 0) end
        for slot = 1, GetContainerNumSlots(bag) do
            local id = GetContainerItemID(bag, slot)
            local price = id and LootTriage:UnitPrice(id, bag, slot)
            if price then
                local count = select(2, GetContainerItemInfo(bag, slot)) or 1
                candidates[#candidates + 1] = { bag = bag, slot = slot, value = price * count }
            end
        end
    end
    sort(candidates, ByValue)
    local marks = Config().triage_marks or 3
    for i, c in ipairs(candidates) do
        if i > marks then break end
        rank[c.bag][c.slot] = i
    end
    cheapest = candidates[1] and candidates[1].value

    lootNeed = looting and CountLootItems() or 0
    local short = looting and lootNeed > freeSlots
    if mode == "always" then
        active = true
    elseif mode == "nearly" then
        active = short or freeSlots <= NEARLY_FULL_FREE
    else
        active = short
    end
end

function LootTriage:GetState()
    return active, cheapest, freeSlots, lootNeed, candidates
end

-- ============================================================================
-- BAG SLOT MARKS
-- ============================================================================

local function AddAlpha(group, order, change, duration)
    local anim = group:CreateAnimation("Alpha")
    anim:SetOrder(order); anim:SetChange(change); anim:SetDuration(duration); anim:SetSmoothing("IN_OUT")
end

local function CreateMark(button)
    local mark = CreateFrame("Frame", nil, button)
    mark:SetAllPoints(button)
    local size = (button:GetWidth() or 37) * 1.8

    mark.border = mark:CreateTexture(nil, "OVERLAY")
    mark.border:SetTexture(BORDER_TEXTURE)
    mark.border:SetBlendMode("ADD")
    mark.border:SetVertexColor(GOLD_R, GOLD_G, GOLD_B)
    mark.border:SetSize(size, size)
    mark.border:SetPoint("CENTER", button, "CENTER", 0, 0)
    mark.pulse = mark.border:CreateAnimationGroup()
    AddAlpha(mark.pulse, 1, -0.7, 0.6)
    AddAlpha(mark.pulse, 2, 0.7, 0.6)
    mark.pulse:SetLooping("REPEAT")

    mark.number = mark:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    mark.number:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -2)
    mark.number:SetTextColor(GOLD_R, GOLD_G, GOLD_B)

    mark.star = mark:CreateTexture(nil, "OVERLAY")
    mark.star:SetTexture(STAR_TEXTURE)
    mark.star:SetSize(13, 13)
    -- Bottom left: the sort lock's padlock sits top right, the item level bottom centre.
    mark.star:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)

    button._duiTriage = mark
    return mark
end

local function PaintSlot(button, bag, slot)
    local mark = button._duiTriage
    local n = bag and rank[bag] and active and rank[bag][slot]
    local star = bag and Mode() ~= "off" and LootTriage:IsKept(GetContainerItemID(bag, slot))
    if not (n or star) then
        if mark and mark:IsShown() then mark.pulse:Stop(); mark:Hide() end
        return
    end
    mark = mark or CreateMark(button)
    mark:SetFrameLevel(button:GetFrameLevel() + 3)
    mark:Show()
    if n then
        mark.number:SetText(n)
        mark.number:Show()
        mark.border:Show()
        if Config().triage_style == "pulse" then
            if not mark.pulse:IsPlaying() then mark.pulse:Play() end
        else
            mark.pulse:Stop()
        end
    else
        mark.pulse:Stop()
        mark.number:Hide()
        mark.border:Hide()
    end
    if star then mark.star:Show() else mark.star:Hide() end
end

local function InventoryBag(bag)
    return bag and bag >= 0 and bag <= NUM_BAG_SLOTS and bag or nil
end

-- Bagster slot (other characters' cached bags never get marks).
function LootTriage:UpdateSlot(item)
    local bag = not item:IsCached() and InventoryBag(item:GetBag())
    PaintSlot(item, bag, item:GetID())
end

function LootTriage:UpdateContainer(frame)
    local name, bag = frame:GetName(), InventoryBag(frame:GetID())
    for i = 1, frame.size or 0 do
        local button = _G[name .. "Item" .. i]
        if button then PaintSlot(button, bag, button:GetID()) end
    end
end

local function BagsterOn()
    local b = addon.BagsterModule
    return b and b.BagsterModule.applied and b.IsModuleEnabled()
end

local function RepaintBags()
    if BagsterOn() then
        for _, f in pairs(addon.BagsterModule.frames) do
            if not f.isBank and f:IsVisible() then
                for _, item in pairs(f.itemFrame.items) do
                    if item:IsVisible() then LootTriage:UpdateSlot(item) end
                end
            end
        end
    end
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = _G["ContainerFrame" .. i]
        if f and f:IsShown() then LootTriage:UpdateContainer(f) end
    end
end

-- ============================================================================
-- LOOT WINDOW COINS
-- ============================================================================

local function LootWorth(slot)
    local link = GetLootSlotLink(slot)
    if not link then return end
    local _, _, _, _, _, class, _, _, _, _, price = GetItemInfo(link)
    if class == Classes().quest then return true end
    local quantity = select(3, GetLootSlotInfo(slot)) or 1
    return price and price * quantity > cheapest
end

local function PaintLootButton(button)
    local slot = button:IsShown() and button.slot
    local worth = active and cheapest and slot and LootSlotIsItem(slot) and LootWorth(slot)
    local coin = button._duiTriageCoin
    if not worth then
        if coin then coin:Hide() end
        return
    end
    if not coin then
        coin = button:CreateTexture(nil, "OVERLAY")
        coin:SetTexture(COIN_TEXTURE)
        coin:SetSize(14, 14)
        coin:SetPoint("TOPRIGHT", button, "TOPRIGHT", 3, 3)
        button._duiTriageCoin = coin
    end
    coin:Show()
end

-- The loot skin adds rows past the stock four; they share the stock buttons' slot field.
local function RepaintLoot()
    for i = 1, LOOTFRAME_NUMBUTTONS or 4 do
        local button = _G["LootButton" .. i]
        if button then PaintLootButton(button) end
    end
    local i = LOOTFRAME_NUMBUTTONS or 4
    while _G["DragonUILootRow" .. i] do
        PaintLootButton(_G["DragonUILootRow" .. i])
        i = i + 1
    end
end

-- ============================================================================
-- KEEP STAR (Alt + Right Click)
-- ============================================================================

local function KeyIsFree()
    -- Auctionator, Postal and the trade window use Alt-clicks on bag items of their own.
    if (AuctionFrame and AuctionFrame:IsShown()) or (MailFrame and MailFrame:IsShown())
        or (TradeFrame and TradeFrame:IsShown()) then
        return false
    end
    local bagsort = addon.db.profile.modules and addon.db.profile.modules.bagsort
    return not (bagsort and bagsort.enabled and bagsort.lock_hotkey == "ALT_RIGHT")
end

local driver = CreateFrame("Frame")
driver:Hide()

function LootTriage:Refresh()
    driver:Show()
end

function LootTriage:ToggleKept(bag, slot)
    local id = GetContainerItemID(bag, slot)
    if not id then return end
    local kept = Kept(true)
    if not kept then return end
    kept[id] = not kept[id] or nil
    local link = select(7, GetContainerItemInfo(bag, slot)) or id
    local text = kept[id] and L["Loot Triage will never suggest deleting %s."]
        or L["Loot Triage may suggest deleting %s again."]
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900DragonUI|r: " .. text:format(link))
    self:Refresh()
end

hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(button, mouseButton)
    if mouseButton ~= "RightButton" or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    if Mode() == "off" or (button.IsCached and button:IsCached()) or not KeyIsFree() then return end
    local bag = InventoryBag(button:GetParent():GetID())
    if bag then LootTriage:ToggleKept(bag, button:GetID()) end
end)

hooksecurefunc("ContainerFrame_Update", function(frame) LootTriage:UpdateContainer(frame) end)

-- ============================================================================
-- EVENTS
-- ============================================================================

-- One recompute per frame however many bag and loot events land together; the loot skin
-- fills its extra rows in its own LootFrame_Update hook, which may run after ours.
driver:SetScript("OnUpdate", function(self)
    self:Hide()
    Recompute()
    RepaintBags()
    RepaintLoot()
end)

driver:SetScript("OnEvent", function(self, event)
    if event == "LOOT_OPENED" then
        looting = true
    elseif event == "LOOT_CLOSED" then
        looting = false
    end
    self:Show()
end)

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE", "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED" }) do
    driver:RegisterEvent(event)
end

hooksecurefunc("LootFrame_Update", function() driver:Show() end)
