-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- ============================================================================
-- DragonUI - Feral attack power on weapons a druid can't use
-- The 3.3.5a client adds "Increases attack power by N in Cat, Bear, Dire Bear,
-- and Moonkin forms only." to every fast melee weapon a druid looks at, swords
-- and axes included. The bonus only counts while the weapon is equipped, so the
-- line is blanked when the tooltip shows the weapon type in red.
-- ============================================================================

local FERAL_AP = ITEM_MOD_FERAL_ATTACK_POWER
    or "Increases attack power by %d in Cat, Bear, Dire Bear, and Moonkin forms only."
local FERAL_PREFIX, FERAL_SUFFIX = FERAL_AP:match("^(.-)%%d(.+)$")

local TOOLTIPS = {
    "GameTooltip", "ItemRefTooltip",
    "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "ItemRefShoppingTooltip3",
}

local function IsFeralLine(text)
    return text:sub(1, #FERAL_PREFIX) == FERAL_PREFIX and text:sub(-#FERAL_SUFFIX) == FERAL_SUFFIX
end

-- The client reddens the weapon type ("Sword") on the right of the slot line for a type the class lacks.
local function IsRed(fs)
    if not fs or not fs:IsShown() or not fs:GetText() then return false end
    local r, g, b = fs:GetTextColor()
    return r > 0.9 and g < 0.2 and b < 0.2
end

local function HideUnusableFeralLine(tooltip)
    local _, classFile = UnitClass("player")
    if classFile ~= "DRUID" or not FERAL_PREFIX then return end
    if not tooltip:GetItem() then return end

    local name = tooltip:GetName()
    local unusable = false
    for i = 2, tooltip:NumLines() do
        local left = _G[name .. "TextLeft" .. i]
        local text = left and left:GetText()
        if text and IsFeralLine(text) then
            if unusable then
                left:SetText("")
                tooltip:Show()
            end
            return
        end
        unusable = unusable or IsRed(_G[name .. "TextRight" .. i])
    end
end

for _, tooltipName in ipairs(TOOLTIPS) do
    local tooltip = _G[tooltipName]
    if tooltip and tooltip.HookScript then
        tooltip:HookScript("OnTooltipSetItem", HideUnusableFeralLine)
    end
end
