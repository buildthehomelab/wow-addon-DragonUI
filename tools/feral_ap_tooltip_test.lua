-- Run from the repository root with Lua 5.1. Mocks a GameTooltip's line font strings.
ITEM_MOD_FERAL_ATTACK_POWER = 'Increases attack power by %d in Cat, Bear, Dire Bear, and Moonkin forms only.'
local RED, WHITE, GREEN = { 1, 0.125, 0.125 }, { 1, 1, 1 }, { 0, 1, 0 }
local playerClass = 'DRUID'
function UnitClass() return 'Druid', playerClass end

local function fontString(text, color)
    local fs = { text = text, color = color or WHITE, shown = text ~= nil }
    function fs:GetText() return self.text end
    function fs:SetText(t) self.text = t end
    function fs:IsShown() return self.shown end
    function fs:GetTextColor() return self.color[1], self.color[2], self.color[3] end
    return fs
end

local function tooltip(name)
    local tt = { name = name, lines = 0, shows = 0 }
    function tt:GetName() return self.name end
    function tt:NumLines() return self.lines end
    function tt:GetItem() return self.item, self.item and 'link' end
    function tt:Show() self.shows = self.shows + 1 end
    function tt:HookScript(script, fn) self[script] = fn end
    -- rows: { left, right, rightColor, leftColor }
    function tt:Fill(item, rows)
        self.item, self.lines, self.shows = item, #rows, 0
        for i, row in ipairs(rows) do
            _G[name .. 'TextLeft' .. i] = fontString(row[1], row[4])
            _G[name .. 'TextRight' .. i] = fontString(row[2], row[3])
        end
        self:OnTooltipSetItem()
    end
    _G[name] = tt
    return tt
end

local tt = tooltip('GameTooltip')
local ref = tooltip('ItemRefTooltip')
assert(loadfile('DragonUI/modules/feral_ap_tooltip.lua'))('DragonUI', {})
assert(tt.OnTooltipSetItem and ref.OnTooltipSetItem, 'Item tooltips not hooked')

local FERAL = 'Increases attack power by 139 in Cat, Bear, Dire Bear, and Moonkin forms only.'
local function blade(typeColor)
    return {
        { 'Obsidian Edged Blade' }, { 'Soulbound' }, { 'Two-Hand', 'Sword', typeColor },
        { '176 - 264 Damage', 'Speed 3.40' }, { '+42 Strength' },
        { FERAL, nil, nil, GREEN }, { 'Equip: Increases your expertise rating by 19.', nil, nil, GREEN },
    }
end

-- Druid, red Sword: feral line blanked, the rest kept, tooltip resized once.
tt:Fill('sword', blade(RED))
assert(GameTooltipTextLeft6.text == '', 'Feral line should be blanked on a red weapon type')
assert(GameTooltipTextLeft7.text:find('^Equip:'), 'Lines after the feral line must stay')
assert(tt.shows == 1, 'Tooltip should be re-shown to resize')

-- Druid, usable staff (type not red): kept.
tt:Fill('staff', blade(WHITE))
assert(GameTooltipTextLeft6.text == FERAL, 'Feral line must stay on a usable weapon')
assert(tt.shows == 0, 'No resize when nothing changed')

-- Chat links go through ItemRefTooltip.
ref:Fill('sword', blade(RED))
assert(ItemRefTooltipTextLeft6.text == '', 'Chat link tooltip should drop the line too')

-- A red line after the feral line (e.g. trade timer, addon text) doesn't count.
local rows = blade(WHITE)
rows[#rows + 1] = { 'Requires Level 80', 'x', RED }
tt:Fill('staff', rows)
assert(GameTooltipTextLeft6.text == FERAL, 'Only red text above the feral line counts')

-- Other classes never see the line; nothing to do and nothing touched.
playerClass = 'WARRIOR'
tt:Fill('sword', blade(RED))
assert(GameTooltipTextLeft6.text == FERAL and tt.shows == 0, 'Non-druids are left alone')
playerClass = 'DRUID'

-- No item on the tooltip (spell/unit): ignored.
tt:Fill(nil, blade(RED))
assert(GameTooltipTextLeft6.text == FERAL, 'Non-item tooltips are left alone')

print('feral_ap_tooltip_test: ok')
