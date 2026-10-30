-- Run from the repository root with Lua 5.1.
-- Loads stockpanels.lua against a stock-shaped LFRParentFrame and checks the Raid Browser skin.
local unpack = unpack or table.unpack
local function noop() end
local methods = {}
local made = {}

local function newObject(kind, name, parent)
    local o = { kind = kind, name = name, parent = parent, scripts = {}, points = {}, regions = {},
        children = {}, shown = true, width = 0, height = 0 }
    -- Any other widget method is a no-op; plain fields (the skin's _dui flags) stay nil.
    setmetatable(o, { __index = function(_, key)
        return methods[key] or (key:find("^%u") and noop) or nil
    end })
    if name then _G[name] = o end
    if parent and kind ~= "Texture" and kind ~= "FontString" then
        parent.children[#parent.children + 1] = o
    elseif parent then
        parent.regions[#parent.regions + 1] = o
    end
    made[#made + 1] = o
    return o
end

function methods:GetObjectType() return self.kind end
function methods:GetName() return self.name end
function methods:GetParent() return self.parent end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:IsShown() return self.shown end
function methods:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:SetAlpha(a) self.alpha = a end
function methods:ClearAllPoints() self.points = {} end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:GetNumPoints() return #self.points end
function methods:GetPoint(i) return unpack(self.points[i or 1]) end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:HookScript(event, fn)
    local previous = self.scripts[event]
    self.scripts[event] = function(...)
        if previous then previous(...) end
        fn(...)
    end
end
function methods:GetRegions() return unpack(self.regions) end
function methods:GetChildren() return unpack(self.children) end
function methods:GetTexture() return self.file end
function methods:SetTexture(file) self.file = file end
function methods:CreateTexture(name) return newObject("Texture", name, self) end
function methods:GetFrameLevel() return 1 end
function methods:GetNormalTexture() return self.normal end
function methods:GetText() return self.text end
function methods:GetStringWidth() return #(self.text or "") * 7 end

function CreateFrame(kind, name, parent) return newObject(kind, name, parent) end
function InCombatLockdown() return false end
function UpdateUIPanelPositions() end
function hooksecurefunc(key, fn)
    local original = _G[key]
    _G[key] = function(...)
        local result = { original(...) }
        fn(...)
        return unpack(result)
    end
end
function PanelTemplates_SetNumTabs(frame, n) frame.numTabs = n end
NUM_LFR_CHOICE_BUTTONS = 14

-- DragonUI pieces stockpanels leans on.
local reskinnedTabs, redButtons = {}, {}
local addon = {
    _dir = "Interface\\AddOns\\DragonUI\\",
    WindowSeat = { left = 4.5, right = -5.5, bottom = 4.5, gap = 3 },
    L = {},
    CharacterPanel = {
        ReskinTab = function(tab) reskinnedTabs[tab] = true end,
        ModernizeCloseButton = function(button) button._duiModernized = true end,
        ReskinScrollBar = function(scroll)
            local bar = _G[scroll.name .. "ScrollBar"]
            if bar then bar._duiReskinned = true end
        end,
    },
    SkinRedButton = function(button) redButtons[button] = true; button._duiRedButton = {} end,
}
local seat = addon.WindowSeat
seat.buttonLeft, seat.buttonRight, seat.buttonBottom = seat.left + seat.gap, seat.right - seat.gap, seat.bottom + seat.gap

-- The stock Raid Browser (LFRFrame.xml), only what the skin touches.
UIParent = newObject("Frame", "UIParent")
local window = newObject("Frame", "LFRParentFrame", UIParent)
window:SetSize(355, 440)
window.shown = false
local close = newObject("Button", nil, window)
close.normal = newObject("Texture", nil, close)
close.normal.file = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up"
newObject("Texture", "LFRParentFrameIcon", window)

local queue = newObject("Frame", "LFRQueueFrame", window)
newObject("Texture", "LFRQueueFrameLayout", queue)
newObject("FontString", "LFRQueueFrameTitleText", queue)
for _, role in ipairs({ "Tank", "Healer", "DPS" }) do
    newObject("Button", "LFRQueueFrameRoleButton" .. role, queue):SetSize(48, 48)
end
newObject("EditBox", "LFRQueueFrameComment", queue):SetSize(313, 41)
local specific = newObject("Frame", "LFRQueueFrameSpecific", queue)
for i = 1, 14 do
    newObject("Frame", "LFRQueueFrameSpecificListButton" .. i, specific):SetSize(295, 16)
end
local raidScroll = newObject("ScrollFrame", "LFRQueueFrameSpecificListScrollFrame", specific)
newObject("Slider", "LFRQueueFrameSpecificListScrollFrameScrollBar", raidScroll)
local cover = newObject("Frame", "LFRQueueFrameNoLFRWhileLFD", queue)

local panelButtons = {}
local function panelButton(name, parent, width)
    local button = newObject("Button", name, parent)
    button:SetSize(width, 22)
    for _, part in ipairs({ "Left", "Middle", "Right" }) do
        newObject("Texture", name .. part, button).file = "Interface\\Buttons\\UI-Panel-Button-Up"
    end
    panelButtons[#panelButtons + 1] = button
    return button
end
local find = panelButton("LFRQueueFrameFindGroupButton", queue, 125)
local accept = panelButton("LFRQueueFrameAcceptCommentButton", queue, 115)
panelButton("LFRQueueFrameNoLFRWhileLFDLeaveQueueButton", cover, 153)

local browse = newObject("Frame", "LFRBrowseFrame", window)
browse.shown = false
newObject("Texture", "LFRBrowseFrameLayout", browse)
newObject("FontString", "LFRBrowseFrameTitleText", browse)
local menu = newObject("Frame", "LFRBrowseFrameRaidDropDown", browse)
newObject("FontString", "LFRBrowseFrameRaidDropDownName", menu).text = "Browsing"
newObject("Button", "LFRBrowseFrameColumnHeader1", browse):SetSize(97, 24)
for i = 1, 19 do
    newObject("Button", "LFRBrowseFrameListButton" .. i, browse):SetSize(298, 16)
end
local browseScroll = newObject("ScrollFrame", "LFRBrowseFrameListScrollFrame", browse)
newObject("Slider", "LFRBrowseFrameListScrollFrameScrollBar", browseScroll)
local send = panelButton("LFRBrowseFrameSendMessageButton", browse, 113)
local invite = panelButton("LFRBrowseFrameInviteButton", browse, 100)
local refresh = panelButton("LFRBrowseFrameRefreshButton", browse, 104)

for i = 1, 2 do newObject("Button", "LFRParentFrameTab" .. i, window) end
PanelTemplates_SetNumTabs(window, 2)
function LFRQueueFrameSpecificList_Update()
    for i = 1, 14 do _G["LFRQueueFrameSpecificListButton" .. i]:SetWidth(raidScroll:IsShown() and 295 or 315) end
end

assert(loadfile("DragonUI/modules/stockpanels.lua"))("DragonUI", addon)
local boot = made[#made]
assert(boot.scripts.OnEvent, "stockpanels registers its boot frame")
boot.scripts.OnEvent(boot, "PLAYER_LOGIN")
assert(not window._duiStockSkinned, "built on first open, not at login")
window:Show()
assert(window._duiStockSkinned, "first open builds the skin")

-- Stock art gone, close button modernised.
for _, name in ipairs({ "LFRParentFrameIcon", "LFRQueueFrameLayout", "LFRBrowseFrameLayout" }) do
    assert(_G[name]._duiNeutered, name .. " hidden")
end
assert(close._duiModernized, "unnamed close button found and seated")

-- Every panel button red, its named stone hidden.
for _, button in ipairs(panelButtons) do
    assert(redButtons[button], button.name .. " is a red button")
    for _, part in ipairs({ "Left", "Middle", "Right" }) do
        assert(_G[button.name .. part]._duiNeutered, button.name .. part .. " hidden")
    end
end

-- Offsets of a point relative to the window's top-left (x right, y up), for TOPLEFT / BOTTOMRIGHT
-- anchors off the window or the chrome host.
local host = window._duiChrome
local function topOffset(region, point)
    for _, p in ipairs(region.points) do
        if p[1] == point then
            if p[2] == window and p[3] == "TOPLEFT" then return p[4], p[5] end
            if p[2] == window and p[3] == "BOTTOMRIGHT" then return 355 + p[4], -440 + p[5] end
            if p[2] == host and p[3] == "BOTTOMLEFT" then return 12 + p[4], -440 + 2 + p[5] end
            if p[2] == host and p[3] == "BOTTOMRIGHT" then return 355 - 6 + p[4], -440 + 2 + p[5] end
        end
    end
    error((region.name or "region") .. " has no " .. point .. " anchor off the window")
end
local function insetsOf(page)
    local list = {}
    for _, child in ipairs(page.children) do
        if not child.name and #child.points == 2 then list[#list + 1] = child end
    end
    return list
end

-- Choose Raid: roles under the band, raid list inset over the comment inset over the button row.
local tankX, tankY = topOffset(_G.LFRQueueFrameRoleButtonTank, "TOPLEFT")
assert(tankY == -48, "roles keep the Dungeon Finder's row")
-- The content runs from the seat gap inside the left rail to the one inside the right rail.
local centre = (12 + seat.left + seat.gap + 355 - 6 + seat.right - seat.gap) / 2
assert(math.abs(tankX + (48 * 3 + 40 * 2) / 2 - centre) < 0.01, "roles centred on the content")
local insets = insetsOf(queue)
assert(#insets == 2, "the Choose Raid page owns its two insets")
local listInset, commentInset = insets[1], insets[2]
local _, listTop = topOffset(listInset, "TOPLEFT")
local _, listBottom = topOffset(listInset, "BOTTOMRIGHT")
local _, commentTop = topOffset(commentInset, "TOPLEFT")
local _, commentBottom = topOffset(commentInset, "BOTTOMRIGHT")
assert(listTop <= -48 - 48 - 16, "list inset clears the role glows")
local _, rowTop = topOffset(_G.LFRQueueFrameSpecificListButton1, "TOPLEFT")
assert(rowTop < listTop and rowTop - 14 * 16 - 2 >= listBottom, "14 raid rows and their faux frame fit the list inset")
assert(commentTop < listBottom, "comment inset under the list inset")
local boxX, boxY = topOffset(_G.LFRQueueFrameComment, "TOPLEFT")
local commentLeft = topOffset(commentInset, "TOPLEFT")
local commentRight = topOffset(commentInset, "BOTTOMRIGHT")
assert(boxY < commentTop and boxY - 41 >= commentBottom, "comment box inside its inset vertically")
assert(boxX > commentLeft and boxX + 313 <= commentRight, "comment box inside its inset horizontally")
local _, findBottom = topOffset(find, "BOTTOMLEFT")
assert(findBottom + 22 <= commentBottom, "List Me sits under the comment inset")
local _, acceptBottom = topOffset(accept, "BOTTOMRIGHT")
assert(acceptBottom == findBottom, "List Me and Set Comment share the seat row")
assert(cover.points[1][2] == listInset and cover.points[2][2] == commentInset, "LFD-queue cover spans both insets")
raidScroll.shown = false
LFRQueueFrameSpecificList_Update()
assert(_G.LFRQueueFrameSpecificListButton1:GetWidth() == 311, "raid rows trimmed to the inset")
raidScroll.shown = true
LFRQueueFrameSpecificList_Update()
assert(_G.LFRQueueFrameSpecificListButton1:GetWidth() == 291, "raid rows beside the bar trimmed too")

-- Browse: one inset; headers then 19 rows fit; the three buttons spread across the seats.
local browseInsets = insetsOf(browse)
assert(#browseInsets == 1, "the Browse page owns one inset")
local _, browseTop = topOffset(browseInsets[1], "TOPLEFT")
local _, browseBottom = topOffset(browseInsets[1], "BOTTOMRIGHT")
local _, headerTop = topOffset(_G.LFRBrowseFrameColumnHeader1, "TOPLEFT")
local _, memberTop = topOffset(_G.LFRBrowseFrameListButton1, "TOPLEFT")
assert(headerTop < browseTop and memberTop <= headerTop - 24, "headers above the member rows inside the inset")
assert(memberTop - 19 * 16 - 2 >= browseBottom, "19 member rows fit the inset")
local sendX, sendY = topOffset(send, "BOTTOMLEFT")
local refreshX, refreshY = topOffset(refresh, "BOTTOMRIGHT")
assert(sendY == refreshY and sendY == findBottom, "Browse buttons on the same seat row")
local gap = invite.points[1][4]
assert(invite.points[1][2] == send and gap >= 1, "Invite follows Send Message")
assert(math.abs(sendX + 113 + gap + 100 + gap + 104 - refreshX) < 0.01, "even gaps between the three buttons")

assert(_G.LFRQueueFrameSpecificListScrollFrameScrollBar._duiReskinned
    and _G.LFRBrowseFrameListScrollFrameScrollBar._duiReskinned, "both lists get the minimal bar")

-- Tabs: both stock tabs chained off the window; RaidFinder's third joins the strip later.
local tab1, tab2 = _G.LFRParentFrameTab1, _G.LFRParentFrameTab2
assert(reskinnedTabs[tab1] and reskinnedTabs[tab2], "stock tabs reskinned")
assert(tab1.points[1][2] == host and tab2.points[1][2] == tab1, "stock tabs chained under the window")
local tab3 = newObject("Button", "LFRParentFrameTab3", window)
tab3:SetPoint("LEFT", tab2, "RIGHT", -15, 0)
PanelTemplates_SetNumTabs(window, 3)
assert(reskinnedTabs[tab3], "a tab added after the build is reskinned")
assert(#tab3.points == 1 and tab3.points[1][1] == "TOPLEFT" and tab3.points[1][2] == tab2,
    "the added tab joins the chain")
-- Re-anchored by its owner again: the next open puts it back.
tab3:ClearAllPoints()
tab3:SetPoint("LEFT", tab2, "RIGHT", -15, 0)
window:Hide()
window:Show()
assert(tab3.points[1][1] == "TOPLEFT" and tab3.points[1][2] == tab2, "the strip re-chains on open")
tab2:Hide()
assert(tab3.points[1][2] == tab1, "a hidden tab drops out of the chain, the added one included")

print("raid_browser_skin_test: ok")
