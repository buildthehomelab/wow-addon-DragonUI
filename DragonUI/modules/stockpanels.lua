-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
if not addon then return end

local _G = _G
local ipairs = ipairs
local type = type
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local UpdateUIPanelPositions = UpdateUIPanelPositions

-- The stock windows DragonUI has no window of its own for: Quest Log, Dungeon Finder, PvP,
-- Achievements, Macros, the Game Menu and the popups. Like social_skin.lua this is a reskin, not a rebuild:
-- each keeps its stock size and every Blizzard anchor, and the bronze window is drawn over the rect
-- its old art showed.
local StockPanels = { initialized = false, applied = false }

local function localized(key)
    local strings = addon.L
    local text = strings and strings[key]
    if type(text) ~= "string" or text == "" then
        return key
    end
    return text
end

if addon.RegisterModule then
    addon:RegisterModule("stockpanels", StockPanels,
        localized("Stock Windows"),
        localized("Retail-style quest log, dungeon finder, PvP, achievements, game menu and popup chrome"),
        { lifecyclePrefix = "StockPanels", loadOnce = true })
end

local DIR = addon._dir
local ROCK = DIR .. "UI\\ui-background-rock"
local MARBLE = DIR .. "UI\\ui-background-marble"

local SLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

-- Bottom tab strip, the character panel's own start and gap off the drawn window's bottom edge.
local TAB_START_X, TAB_START_Y, TAB_GAP = 11, 2, 1

local function IsModuleEnabled()
    if addon.IsModuleEnabled then
        return addon:IsModuleEnabled("stockpanels")
    end
    return true
end

local function neuterTexture(tex)
    if not tex or tex._duiNeutered then return end
    tex._duiNeutered = true
    tex:SetAlpha(0)
    tex:Hide()
    tex.Show = tex.Hide
end

local function neuterFrame(frame)
    if not frame or frame._duiNeutered then return end
    frame._duiNeutered = true
    frame:SetAlpha(0)
    frame:Hide()
    frame.Show = frame.Hide
end

local function fileOf(region)
    local tex = region and region.GetTexture and region:GetTexture()
    return type(tex) == "string" and tex:lower() or ""
end

-- Several stock chrome pieces are unnamed in the XML, so they are found by their file.
local function hideArtByFile(frame, patterns)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            local file = fileOf(region)
            for _, pattern in ipairs(patterns) do
                if file:find(pattern) then
                    neuterTexture(region)
                    break
                end
            end
        end
    end
end

local function hideNamed(names)
    for _, name in ipairs(names) do
        local object = _G[name]
        if object and object.GetObjectType then
            if object:GetObjectType() == "Texture" then
                neuterTexture(object)
            else
                neuterFrame(object)
            end
        end
    end
end

-- The unnamed title string, found by the text Blizzard gave it.
local function fontStringByText(frame, text)
    if not frame or not text then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" and region:GetText() == text then
            return region
        end
    end
end

-- On the frame, not in UIPanelWindows: tainting that table blocks the first panel open in combat.
-- Pulls the drawn window onto the spot retail windows use (CharacterFrame nudges to x = 6).
local function nudgePanel(window, x, y)
    if not window or not window.SetAttribute then return end
    if window:GetAttribute("UIPanelLayout-xoffset") == x and window:GetAttribute("UIPanelLayout-yoffset") == y then
        return
    end
    window:SetAttribute("UIPanelLayout-xoffset", x)
    window:SetAttribute("UIPanelLayout-yoffset", y)
    if window:IsShown() and UpdateUIPanelPositions then
        UpdateUIPanelPositions(window)
    end
end

-- The pieces are the window's own regions anchored to `anchor`: a child frame holding them would
-- tie with Blizzard's subframes and could draw over their rows. This client ignores sublevels, so
-- `layer` overrides the layout's when a piece must sit above another region of the same frame.
local function applySlicesOn(owner, anchor, layoutName, regions, layer)
    local slicer = _G.DragonUI_NineSlice
    local layout = slicer and slicer.GetLayout and slicer.GetLayout(layoutName)
    if not (layout and slicer.ApplyLayout) then return end
    for _, piece in ipairs(SLICE_PIECES) do
        local spec = layout[piece]
        if spec and not anchor[piece] then
            local tex = owner:CreateTexture(nil, layer or spec.layer or "BORDER", nil, spec.subLevel or 0)
            anchor[piece] = tex
            if regions then regions[#regions + 1] = tex end
        end
    end
    slicer.ApplyLayout(anchor, layout)
end

-- `rect` is { left, top, right, bottom }: TOPLEFT offsets from the window's top-left, BOTTOMRIGHT
-- offsets from its bottom-right. The body is rock under the 21px title band, streaks fading below.
local function paintChrome(window, rect)
    local host = CreateFrame("Frame", nil, window)
    host:EnableMouse(false)
    host:SetPoint("TOPLEFT", window, "TOPLEFT", rect[1], rect[2])
    host:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", rect[3], rect[4])

    local rock = window:CreateTexture(nil, "BACKGROUND")
    rock:SetTexture(ROCK, "REPEAT", "REPEAT")
    rock:SetHorizTile(true)
    rock:SetVertTile(true)
    rock:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -21)
    rock:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)

    local streaks = window:CreateTexture(nil, "BACKGROUND")
    if streaks.SetAtlasTexture then
        streaks:SetAtlasTexture("_UI-Frame-TopTileStreaks")
        streaks:SetHorizTile(true)
        streaks:SetPoint("TOPLEFT", host, "TOPLEFT", 6, -21)
        streaks:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", -2, -64)
    else
        streaks:Hide()
    end

    applySlicesOn(window, host, "NoPortraitFrameTemplate")
    window._duiChrome = host
    return host
end

-- Ground on BORDER and the filigree on ARTWORK, both the window's own regions so every subframe
-- draws above them (on BACKGROUND the ground ties with the rock and the rock wins). The ground is
-- marble, or the quest parchment for a pane whose text was written for paper.
-- `bounds` are offsets from the window's corners, or from `bounds.topLeft` / `bounds.bottomRight`
-- when the inset follows a pane Blizzard resizes.
local function addInset(window, bounds, parchment)
    local inset = CreateFrame("Frame", nil, window)
    inset:EnableMouse(false)
    inset:SetPoint("TOPLEFT", bounds.topLeft or window, "TOPLEFT", bounds[1], bounds[2])
    inset:SetPoint("BOTTOMRIGHT", bounds.bottomRight or window, "BOTTOMRIGHT", bounds[3], bounds[4])

    local ground = window:CreateTexture(nil, "BORDER")
    if parchment and ground.SetAtlasTexture then
        ground:SetAtlasTexture("questbg-parchment")
    else
        ground:SetTexture(MARBLE, "REPEAT", "REPEAT")
        ground:SetHorizTile(true)
        ground:SetVertTile(true)
    end
    ground:SetAllPoints(inset)

    applySlicesOn(window, inset, "InsetFrameTemplate", nil, "ARTWORK")
    return inset
end

local function dressTitle(host, label)
    if not (host and label) then return end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", host, "TOPLEFT", 24, -5)
    label:SetPoint("TOPRIGHT", host, "TOPRIGHT", -24, -5)
    label:SetHeight(16)
    label:SetJustifyH("CENTER")
    if label.SetDrawLayer then label:SetDrawLayer("OVERLAY") end
end

local function dressCloseButton(cb, host, window)
    local CP = addon.CharacterPanel
    if not (cb and CP and CP.ModernizeCloseButton) or cb._duiModernized then return end
    CP.ModernizeCloseButton(cb, host)
    cb:SetFrameLevel((window:GetFrameLevel() or 1) + 20)
end

-- Same strip as the Social window: retail tabs chained off the drawn window's bottom-left. With
-- `onTop` ({ anchor, x, y }) they stand nose up on that frame's top-left instead, like the Social
-- window's Friends / Ignore tabs on their list.
local function dressTabs(host, prefix, count, onTop)
    local CP = addon.CharacterPanel
    if not (CP and CP.ReskinTab) then return end
    local function relayout()
        local prev
        for i = 1, count do
            local tab = _G[prefix .. i]
            if tab then
                tab._duiRelayout = relayout
                if tab:IsShown() then
                    CP.ReskinTab(tab, onTop and true)
                    tab:ClearAllPoints()
                    if onTop then
                        if prev then
                            tab:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", TAB_GAP, 0)
                        else
                            tab:SetPoint("BOTTOMLEFT", onTop.anchor, "TOPLEFT", onTop.x, onTop.y)
                        end
                    elseif prev then
                        tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", TAB_GAP, 0)
                    else
                        tab:SetPoint("TOPLEFT", host, "BOTTOMLEFT", TAB_START_X, TAB_START_Y)
                    end
                    prev = tab
                end
            end
        end
    end
    for i = 1, count do
        local tab = _G[prefix .. i]
        if tab and not tab._duiStockTabHooked then
            tab._duiStockTabHooked = true
            tab:HookScript("OnShow", relayout)
            tab:HookScript("OnHide", relayout)
        end
    end
    relayout()
end

-- The stock gutter art behind a UIPanelScrollFrameTemplate bar, replaced by the minimal bar that
-- hangs `x` right of the scroll frame.
local function dressScrollBar(scrollName, x)
    local scroll = _G[scrollName]
    local CP = addon.CharacterPanel
    if not (scroll and CP and CP.ReskinScrollBar) or scroll._duiStockBar then return end
    scroll._duiStockBar = true
    hideArtByFile(scroll, { "ui%-character%-scrollbar", "ui%-classtrainer%-scrollbar" })
    neuterTexture(scroll.scrollBarBackground)
    scroll.hideThumbWhenUnscrollable = true
    CP.ReskinScrollBar(scroll, scroll, 0, 0, 0, true)
    local bar = _G[scrollName .. "ScrollBar"]
    if bar and bar._duiReskinned then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", x, 0)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", x, 0)
    end
end

-- Draws the bronze window over `spec.rect` of the stock frame. Everything else is the caller's.
local function skinWindow(window, spec)
    local host = paintChrome(window, spec.rect)
    nudgePanel(window, 6 - spec.rect[1], -spec.rect[2])
    if spec.hit and window.SetHitRectInsets then
        window:SetHitRectInsets(spec.hit[1], spec.hit[2], spec.hit[3], spec.hit[4])
    end
    dressTitle(host, spec.title)
    dressCloseButton(spec.close, host, window)
    for _, bounds in ipairs(spec.insets or {}) do
        addInset(window, bounds, bounds.parchment)
    end
    return host
end

-- ============================================================================
-- QUEST LOG (682x447 double-wide; the dual-pane art fills it below a 12px lip)
-- ============================================================================

-- The bottom row sits the seat's height above the rail (stock it hung 13 in from the left and 1.5
-- off the right rail), and the insets' outer sides and bottoms keep the seat's gap to the rails and
-- the row. The control panel is 26 tall with its 21 buttons centred 1 high, so it sits 3.5 under
-- their bottom edge.
local QUEST_ROW_BOTTOM = 2 + addon.WindowSeat.buttonBottom
local QUEST_INSET_BOTTOM = QUEST_ROW_BOTTOM + 21 + addon.WindowSeat.gap
-- List: QuestLogScrollFrame (305x335) plus its hybrid bar's 16px on the right, moved 5 left of its
-- stock 19,-75 so it sits 6.5 / 7 inside the inset.
local QUEST_LIST_SCROLL_X = 14
local QUEST_LIST_INSET = { addon.WindowSeat.buttonLeft, -70, -340, QUEST_INSET_BOTTOM }
-- Details: QuestLogDetailScrollFrame hangs TOPRIGHT -32,-77 (298x333), its bar 8 right of that.
-- Parchment, not marble: QuestInfo writes its text in the dark ink of the stock paper pane.
local QUEST_DETAIL_INSET = { 349, -70, addon.WindowSeat.buttonRight, QUEST_INSET_BOTTOM, parchment = true }

local QUEST_PANEL_X, QUEST_PANEL_Y = QUEST_LIST_INSET[1], QUEST_ROW_BOTTOM - 3.5

-- Blizzard re-anchors the panel each time the log or the detached detail window shows or hides.
local function placeQuestControls()
    local panel, window = _G.QuestLogControlPanel, _G.QuestLogFrame
    if not (panel and window and window._duiStockSkinned) or panel:GetParent() ~= window then return end
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", QUEST_PANEL_X, QUEST_PANEL_Y)
end

local function buildQuestLog()
    local window = _G.QuestLogFrame
    if not window or window._duiStockSkinned then return end
    window._duiStockSkinned = true

    hideArtByFile(window, { "ui%-questlogdualpane", "ui%-questlog%-bookicon" })
    skinWindow(window, {
        rect = { 0, -12, 0, 2 },
        title = _G.QuestLogTitleText,
        close = _G.QuestLogFrameCloseButton,
        insets = { QUEST_LIST_INSET, QUEST_DETAIL_INSET },
    })
    dressScrollBar("QuestLogDetailScrollFrame", 8)
    local list = _G.QuestLogScrollFrame
    if list and list:GetNumPoints() == 1 then
        local point, relativeTo, relativePoint, _, y = list:GetPoint(1)
        list:ClearAllPoints()
        list:SetPoint(point, relativeTo, relativePoint, QUEST_LIST_SCROLL_X, y)
    end

    local cancel = _G.QuestLogFrameCancelButton
    if cancel then
        cancel:ClearAllPoints()
        cancel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", QUEST_DETAIL_INSET[3], QUEST_ROW_BOTTOM)
    end
    if _G.QuestLogControlPanel_UpdatePosition then
        hooksecurefunc("QuestLogControlPanel_UpdatePosition", placeQuestControls)
    end
    placeQuestControls()
end

-- ============================================================================
-- DUNGEON FINDER (355x440; the art's frame runs 12 in from the top-left)
-- ============================================================================

local LFD_RECT = { 12, -12, -6, 2 }
local LFD_BUTTON_H = 22

-- Top to bottom under the band: the role row, the Type row, then one inset holding the random and
-- specific panes. The 48 role buttons' 80 glows run from the band's bottom edge (32 down) to the
-- top of the Type row's art.
local LFD_ROLE_TOP, LFD_ROLE_GAP = -48, 24
local LFD_ROLES = { "Tank", "Healer", "DPS", "Leader" }
local LFD_TYPE_Y = -124 -- centre of the Type row
local LFD_INSET_TOP = -144
local LFD_PAD = 4 -- the panes inside the inset
-- LFDQueueFrameTypeDropDown_SetUp sizes the menu 180, so the frame is 230: its art starts 18 in from
-- the frame's left and ends 20 short of its right (measured from an in-game screenshot).
local LFD_TYPE_FRAME_W, LFD_TYPE_ART_LEFT, LFD_TYPE_ART_RIGHT = 230, 18, 20
local LFD_TYPE_LABEL_GAP = 6
-- The minimal bar (characterpanel/scrollbar.lua) is 8 wide; both panes end it LFD_PAD inside.
local LFD_BAR_W = 8
-- Stock rows are 315 wide, or 295 beside the list's bar: both lose what the inset's padding takes.
local LFD_ROW_TRIM = 2

-- Everything inside keeps the seat's gap off the rails (nineslice.lua), as the bottom buttons do.
-- Returns the content's left, right and bottom offsets from the window's corners.
local function lfdContent()
    local seat = addon.WindowSeat
    return LFD_RECT[1] + seat.left + seat.gap,
        LFD_RECT[3] + seat.right - seat.gap,
        LFD_RECT[4] + seat.buttonBottom + LFD_BUTTON_H + seat.gap
end

-- LFDParentFrame's close button is the one child the XML leaves unnamed.
local function lfdCloseButton(window)
    for _, child in ipairs({ window:GetChildren() }) do
        local isButton = child:GetObjectType() == "Button"
        if isButton and fileOf(child:GetNormalTexture()):find("ui%-panel%-minimizebutton") then
            return child
        end
    end
end

-- Stock the roles start 65 in with gaps of 25, 23 and 32: centred on the content with even gaps.
local function placeRoles(window, centre)
    local buttons, total = {}, 0
    for _, role in ipairs(LFD_ROLES) do
        local button = _G["LFDQueueFrameRoleButton" .. role]
        if button then
            buttons[#buttons + 1] = button
            total = total + button:GetWidth()
        end
    end
    if #buttons == 0 then return end
    total = total + LFD_ROLE_GAP * (#buttons - 1)
    for i, button in ipairs(buttons) do
        button:ClearAllPoints()
        if i == 1 then
            button:SetPoint("TOPLEFT", window, "TOPLEFT", centre - total / 2, LFD_ROLE_TOP)
        else
            button:SetPoint("LEFT", buttons[i - 1], "RIGHT", LFD_ROLE_GAP, 0)
        end
    end
end

-- Stock the label hung 115 wide off the menu's transparent left and the menu ran onto the right
-- rail; now "Type:" and the menu's art are one row, centred.
local function placeTypeRow(window, centre)
    local menu, label = _G.LFDQueueFrameTypeDropDown, _G.LFDQueueFrameTypeDropDownName
    if not menu then return end
    local labelW = label and label:GetStringWidth() or 0
    local artW = LFD_TYPE_FRAME_W - LFD_TYPE_ART_LEFT - LFD_TYPE_ART_RIGHT
    local rowLeft = centre - (labelW + LFD_TYPE_LABEL_GAP + artW) / 2
    menu:ClearAllPoints()
    menu:SetPoint("LEFT", window, "TOPLEFT",
        rowLeft + labelW + LFD_TYPE_LABEL_GAP - LFD_TYPE_ART_LEFT, LFD_TYPE_Y)
    if label then
        label:ClearAllPoints()
        label:SetPoint("RIGHT", menu, "LEFT", LFD_TYPE_ART_LEFT - LFD_TYPE_LABEL_GAP, 2)
    end
end

local function trimSpecificRows()
    local scroll = _G.LFDQueueFrameSpecificListScrollFrame
    local count = _G.NUM_LFD_CHOICE_BUTTONS or 15
    for i = 1, count do
        local row = _G["LFDQueueFrameSpecificListButton" .. i]
        if row then
            row:SetWidth((scroll and scroll:IsShown() and 295 or 315) - 2 * LFD_ROW_TRIM)
        end
    end
end

local function buildLFD()
    local window = _G.LFDParentFrame
    if not window or window._duiStockSkinned then return end
    window._duiStockSkinned = true

    -- The parchment goes too: its text is white and gold, written for the dark inset it now sits on.
    hideNamed({ "LFDQueueFrameLayout", "LFDQueueFrameBackground", "LFDParentFramePortrait" })
    local host = skinWindow(window, {
        rect = LFD_RECT,
        hit = { 12, 6, 12, 2 },
        title = _G.LFDQueueFrameTitleText,
        close = lfdCloseButton(window),
    })

    local left, right, bottom = lfdContent()
    local centre = (left + window:GetWidth() + right) / 2
    placeRoles(window, centre)
    placeTypeRow(window, centre)
    local inset = addInset(window, { left, LFD_INSET_TOP, right, bottom })

    -- Random: one scroll pane inside the inset, the minimal bar LFD_BAR_W right of it in place of
    -- the stock gutter.
    local paneTop, paneBottom = LFD_INSET_TOP - LFD_PAD, bottom + LFD_PAD
    local barLeft = right - LFD_PAD - LFD_BAR_W -- from the window's right, like `right`
    local scroll = _G.LFDQueueFrameRandomScrollFrame
    if scroll then
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", window, "TOPLEFT", left + LFD_PAD, paneTop)
        scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", barLeft - LFD_BAR_W, paneBottom)
        dressScrollBar("LFDQueueFrameRandomScrollFrame", LFD_BAR_W)
    end

    -- Specific: the 16-tall rows start under the inset's top; their faux scroll frame spans them 7
    -- over and under, so the first row drops 7 more to keep that frame inside the inset too.
    local first = _G.LFDQueueFrameSpecificListButton1
    if first then
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", window, "TOPLEFT", left + LFD_PAD, paneTop - 7)
    end
    if _G.LFDQueueFrameSpecificList_Update then
        hooksecurefunc("LFDQueueFrameSpecificList_Update", trimSpecificRows)
    end
    trimSpecificRows()
    local list = _G.LFDQueueFrameSpecificListScrollFrame
    if list then
        -- The bar ends where Random's does: the frame's right is the 293 rows' plus 1.
        local listRight = left + LFD_PAD + 295 - 2 * LFD_ROW_TRIM + 1
        local barX = window:GetWidth() + barLeft - listRight
        dressScrollBar("LFDQueueFrameSpecificListScrollFrame", barX)
    end

    -- Stock, both buttons sit on the bottom rail and Close half into the right one.
    local seat = addon.WindowSeat
    local find, cancel = _G.LFDQueueFrameFindGroupButton, _G.LFDQueueFrameCancelButton
    if find then
        find:ClearAllPoints()
        find:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", seat.buttonLeft, seat.buttonBottom)
    end
    if cancel then
        cancel:ClearAllPoints()
        cancel:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", seat.buttonRight, seat.buttonBottom)
    end
    -- The cooldown, backfill and raid-finder covers take mouse input and ended where the buttons
    -- began; on the inset they cover the panes without reaching the raised buttons.
    local covers = { "LFDQueueFrameCooldownFrame", "LFDQueueFramePartyBackfill", "LFDQueueFrameNoLFDWhileLFR" }
    for _, name in ipairs(covers) do
        local cover = _G[name]
        if cover then
            cover:ClearAllPoints()
            cover:SetAllPoints(inset)
        end
    end
end

-- ============================================================================
-- PVP (384x512 like the old character window; art at 2,-1, so 14 in from the left)
-- ============================================================================

local PVP_RECT = { 14, -13, -32, 75 }
local PVP_HIT = { 14, 32, 13, 75 }
-- Group Join / Join / Cancel ran 136 + 109 + 2 + 83 = 330, past the 322 between the seats.
local PVP_GROUP_JOIN_W = 128

-- Both pages keep the seat's gap off the rails; offsets are from PVPParentFrame's corners.
local PVP_LEFT = PVP_RECT[1] + addon.WindowSeat.buttonLeft
local PVP_RIGHT = PVP_RECT[3] + addon.WindowSeat.buttonRight
local PVP_BOTTOM = PVP_RECT[4] + addon.WindowSeat.buttonBottom
local PVP_PAD = 4
local PVP_BUTTON_H = 22

-- PvP page: the Honor and Arena rows stay on the stone where Blizzard put them (-48 and -141), the
-- honor stats (-66..-121) and the three team slots (-168..-421) each get an inset. The slots' poles
-- hung 2 left of the inset, so the slots move 2 right.
local PVP_HONOR_TOP, PVP_HONOR_BOTTOM = -61, -127
local PVP_ARENA_TOP = -154
local PVP_TEAM_X, PVP_TEAM_Y = 15, { 85, 0, -85 }

-- Battlegrounds page: the Battleground header and the Wintergrasp timer share one row above the
-- five 16-tall list rows, then the info pane takes the rest down to the button row.
local BG_HEADER_Y = -54 -- centre of the header row
local BG_HEADER_X = 72
local BG_INSET_TOP = -37 -- the band's bottom plus the seat's gap
local BG_LIST_TOP, BG_LIST_BOTTOM = -72, -160
local BG_INFO_TOP = -163
local BG_ROW_W = 295
local BG_BAR_W = 8
-- The win and loss rows were 319 wide and ran past the 298 scroll pane onto its bar.
local BG_REWARD_W = 297

-- The insets belong to one page each: drawn on PVPFrame or PVPBattlegroundFrame, anchored to the
-- parent's corners (the Battlegrounds page sits 2,-1 off them).
local function addPageInset(page, window, left, top, right, bottom, parchment)
    return addInset(page, {
        left, top, right, bottom, topLeft = window, bottomRight = window,
    }, parchment)
end

local function buildPvPPage(window)
    local page = _G.PVPFrame
    if not page then return end
    local height = window:GetHeight()
    addPageInset(page, window, PVP_LEFT, PVP_HONOR_TOP, PVP_RIGHT, height + PVP_HONOR_BOTTOM)
    addPageInset(page, window, PVP_LEFT, PVP_ARENA_TOP, PVP_RIGHT, PVP_BOTTOM)

    local background = _G.PVPFrameBackground
    for i, y in ipairs(PVP_TEAM_Y) do
        local standard = _G["PVPTeam" .. i .. "Standard"]
        if standard and background then
            standard:ClearAllPoints()
            standard:SetPoint("LEFT", background, "LEFT", PVP_TEAM_X, y)
        end
    end
    local toggle = _G.PVPFrameToggleButton
    if toggle then
        toggle:ClearAllPoints()
        toggle:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", PVP_RIGHT - PVP_PAD, PVP_BOTTOM + PVP_PAD)
    end
end

local function buildBattlegroundPage(window)
    local page = _G.PVPBattlegroundFrame
    if not page then return end
    local width = window:GetWidth()
    local infoBottom = PVP_BOTTOM + PVP_BUTTON_H + addon.WindowSeat.gap
    addPageInset(page, window, PVP_LEFT, BG_INSET_TOP, PVP_RIGHT, window:GetHeight() + BG_LIST_BOTTOM)
    -- Parchment: the map text is written in the dark ink of the stock paper pane. The map painting
    -- under it (PvpRandomBg and the others) has its own metal frame baked in, so it goes.
    addPageInset(page, window, PVP_LEFT, BG_INFO_TOP, PVP_RIGHT, infoBottom, true)
    hideNamed({ "PVPBattlegroundFrameBGTex" })

    -- Same layer as the insets' ground on this frame, which would win the tie.
    local header = _G.PVPBattlegroundFrameNameHeader
    if header then
        header:ClearAllPoints()
        header:SetPoint("LEFT", window, "TOPLEFT", BG_HEADER_X, BG_HEADER_Y)
        header:SetDrawLayer("OVERLAY")
    end
    local timer = _G.WintergraspTimer
    if timer then
        timer:ClearAllPoints()
        timer:SetPoint("RIGHT", window, "TOPLEFT", width + PVP_RIGHT - PVP_PAD, BG_HEADER_Y)
    end

    local rowLeft = PVP_LEFT + PVP_PAD
    local first = _G.BattlegroundType1
    if first then
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", window, "TOPLEFT", rowLeft, BG_LIST_TOP)
    end
    -- Both bars end PVP_PAD inside the inset; the list's faux frame ends with its rows.
    local barLeft = width + PVP_RIGHT - PVP_PAD - BG_BAR_W
    dressScrollBar("PVPBattlegroundFrameTypeScrollFrame", barLeft - (rowLeft + BG_ROW_W))

    local info = _G.PVPBattlegroundFrameInfoScrollFrame
    if info then
        info:ClearAllPoints()
        info:SetPoint("TOPLEFT", window, "TOPLEFT", rowLeft, BG_INFO_TOP - PVP_PAD)
        info:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT",
            PVP_RIGHT - PVP_PAD - 2 * BG_BAR_W, infoBottom + PVP_PAD)
        dressScrollBar("PVPBattlegroundFrameInfoScrollFrame", BG_BAR_W)
    end
    local rewards = _G.PVPBattlegroundFrameInfoScrollFrameChildFrameRewardsInfo
    if rewards then
        for _, row in ipairs({ rewards.winReward, rewards.lossReward }) do
            row:SetWidth(BG_REWARD_W)
        end
    end
end

local function buildPvP()
    local window = _G.PVPParentFrame
    if not window or window._duiStockSkinned then return end
    window._duiStockSkinned = true

    -- PVPFrameBackground (the honor and arena painting) ran under every rail and had the portrait's
    -- shadow in its top-left corner; the insets below replace it.
    hideArtByFile(_G.PVPFrame, { "ui%-character%-general" })
    hideArtByFile(_G.PVPBattlegroundFrame, { "ui%-battlefield%-top", "ui%-queuefromanywhere%-bot" })
    hideNamed({ "PVPFramePortrait", "PVPBattlegroundFramePortrait", "PVPFrameBackground" })

    local host = skinWindow(window, {
        rect = PVP_RECT,
        hit = PVP_HIT,
        close = _G.PVPParentFrameCloseButton,
    })
    -- PVPFrame takes the mouse over the parent's whole 384x512, tab strip included, and the reskin
    -- puts an unselected tab on its level: from the PvP page the Battlegrounds tab lost that tie and
    -- never got the click. PVPBattlegroundFrame already stops 75 short of the bottom in the XML.
    local pvpFrame = _G.PVPFrame
    if pvpFrame and pvpFrame.SetHitRectInsets then
        pvpFrame:SetHitRectInsets(PVP_HIT[1], PVP_HIT[2], PVP_HIT[3], PVP_HIT[4])
    end
    -- Each tab's own title, both re-seated in the one title band.
    dressTitle(host, fontStringByText(_G.PVPFrame, _G.PLAYER_V_PLAYER))
    dressTitle(host, _G.PVPBattlegroundFrameFrameLabel)
    dressTabs(host, "PVPParentFrameTab", 2)

    -- Stock, the queue row hung 2 past the right rail; it takes the seat (the rest of the row hangs
    -- off Cancel). The team toggle moves into the arena inset.
    local seat = addon.WindowSeat
    local cancel, groupJoin = _G.PVPBattlegroundFrameCancelButton, _G.PVPBattlegroundFrameGroupJoinButton
    if cancel then
        cancel:ClearAllPoints()
        cancel:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", seat.buttonRight, seat.buttonBottom)
    end
    if groupJoin then groupJoin:SetWidth(PVP_GROUP_JOIN_W) end
    buildPvPPage(window)
    buildBattlegroundPage(window)
end

-- ============================================================================
-- GAME MENU (a 195-wide dialog box; the bronze window takes its whole rect)
-- ============================================================================

local function buildGameMenu()
    local window = _G.GameMenuFrame
    if not window or window._duiStockSkinned then return end
    window._duiStockSkinned = true

    if window.SetBackdrop then window:SetBackdrop(nil) end
    local header = _G.GameMenuFrameHeader
    local title = fontStringByText(window, _G.MAIN_MENU)
    neuterTexture(header)
    local host = paintChrome(window, { 0, 0, 0, 0 })
    dressTitle(host, title)
end

-- ============================================================================
-- ACHIEVEMENTS (768x500 load-on-demand; wood border, metal rails and a header hung above the top)
-- ============================================================================

-- The bronze title band takes the room the stock header used above the frame, so the window grows
-- by one toolbar strip under the band for the Filter dropdown and DragonUI's Search button.
local ACH_RECT = { 10, 7, -16, 8 }
local ACH_TOOLBAR_H = 26
local ACH_CATEGORIES_TOP = -19 - ACH_TOOLBAR_H
-- Content inset: the panes' left edge (the category scroll bar sits in the gap before it), out to
-- the achievement list's scroll bar, then the seat's gap inside the right and bottom rails.
local ACH_CONTENT_RIGHT, ACH_CONTENT_BOTTOM = -26, 17
local ACH_PAD = 3
-- A pane's own scroll bar hangs 1 right of it; the summary has none and spans that column too.
local ACH_BAR_COLUMN = 17
local ACH_TOOLBAR_Y = -17

local function stripPane(pane, keepNamed)
    if not pane then return end
    for _, region in ipairs({ pane:GetRegions() }) do
        if region:GetObjectType() == "Texture" and not (keepNamed and keepNamed[region:GetName() or ""]) then
            neuterTexture(region)
        end
    end
    -- The tooltip-border boxes are unnamed setAllPoints children.
    for _, child in ipairs({ pane:GetChildren() }) do
        if not child:GetName() and child.SetBackdrop then
            child:SetBackdrop(nil)
        end
    end
end

-- Blizzard re-anchors a tab's label on click (0,-5 selected / 0,-3 other) after SelectTab, so the
-- label is re-synced afterwards. Addons such as Overachiever add more tabs on the same template.
local function achievementTabCount()
    local count = 2
    while _G["AchievementFrameTab" .. (count + 1)] do count = count + 1 end
    return count
end

local function dressAchievementTabs(host)
    local CP = addon.CharacterPanel
    local count = achievementTabCount()
    for i = 1, count do
        local tab = _G["AchievementFrameTab" .. i]
        if tab and not tab._duiAchievementTab then
            tab._duiAchievementTab = true
            local name = tab:GetName()
            hideNamed({ name .. "LeftHighlight", name .. "MiddleHighlight", name .. "RightHighlight" })
            tab:HookScript("OnClick", function()
                for j = 1, achievementTabCount() do
                    local other = _G["AchievementFrameTab" .. j]
                    if other and other._duiReskinned and CP and CP.ReskinTab then CP.ReskinTab(other) end
                end
            end)
        end
    end
    dressTabs(host, "AchievementFrameTab", count)
end

-- Toolbar: Search button at the content inset's right edge, the Filter dropdown (label + arrow, no
-- box of its own) to its left.
local function placeAchievementToolbar(window)
    local search = addon.AchievementSearch
    local button = search and search.button
    if button then
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", window, "TOPRIGHT", ACH_CONTENT_RIGHT, ACH_TOOLBAR_Y)
    end
    local filter = _G.AchievementFrameFilterDropDown
    if filter then
        filter:ClearAllPoints()
        if button then
            filter:SetPoint("TOPRIGHT", button, "TOPLEFT", -8, 1)
        else
            filter:SetPoint("TOPRIGHT", window, "TOPRIGHT", ACH_CONTENT_RIGHT, ACH_TOOLBAR_Y + 1)
        end
    end
end

local function buildAchievements()
    local window = _G.AchievementFrame
    if not window or window._duiStockSkinned then return end
    window._duiStockSkinned = true
    -- Built on ADDON_LOADED, which reaches achievement_search.lua's handler in no set order.
    if not addon.AchievementSearch and addon.InstallAchievementSearch then addon.InstallAchievementSearch() end

    if window.SetBackdrop then window:SetBackdrop(nil) end
    hideNamed({
        "AchievementFrameBackground", "AchievementFrameCategoriesBG", "AchievementFrameWaterMark",
        "AchievementFrameMetalBorderLeft", "AchievementFrameMetalBorderRight",
        "AchievementFrameMetalBorderTop", "AchievementFrameMetalBorderBottom",
        "AchievementFrameMetalBorderTopLeft", "AchievementFrameMetalBorderTopRight",
        "AchievementFrameMetalBorderBottomLeft", "AchievementFrameMetalBorderBottomRight",
        "AchievementFrameWoodBorderTopLeft", "AchievementFrameWoodBorderTopRight",
        "AchievementFrameWoodBorderBottomLeft", "AchievementFrameWoodBorderBottomRight",
        "AchievementFrameHeaderLeft", "AchievementFrameHeaderRight",
        "AchievementFrameHeaderPointBorder", "AchievementFrameHeaderRightDDLInset",
    })
    -- The header frame hangs 67 above the window and would swallow clicks on the title band.
    local header = _G.AchievementFrameHeader
    if header then header:EnableMouse(false) end

    window:SetHeight(window:GetHeight() + ACH_TOOLBAR_H)
    local categories = _G.AchievementFrameCategories
    if categories then
        categories:ClearAllPoints()
        categories:SetPoint("TOPLEFT", window, "TOPLEFT", 21, ACH_CATEGORIES_TOP)
        categories:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 21, 20)
        categories:SetBackdrop(nil)
    end

    local title = _G.AchievementFrameHeaderTitle
    if title then title:SetText(_G.ACHIEVEMENTS or title:GetText()) end
    local host = skinWindow(window, {
        rect = ACH_RECT,
        hit = { ACH_RECT[1], -ACH_RECT[3], 0, ACH_RECT[4] },
        title = title,
        close = _G.AchievementFrameCloseButton,
    })

    -- Points and shield at the right of the band, clear of the close button.
    local shield, points = _G.AchievementFrameHeaderShield, _G.AchievementFrameHeaderPoints
    if shield and points then
        shield:ClearAllPoints()
        shield:SetPoint("RIGHT", host, "TOPRIGHT", -28, -11)
        points:ClearAllPoints()
        points:SetPoint("RIGHT", shield, "LEFT", -2, 1)
    end

    -- Every pane draws on the insets' grounds instead of its own paper and tooltip border.
    local list = _G.AchievementFrameAchievements
    stripPane(list)
    stripPane(_G.AchievementFrameSummary)
    stripPane(_G.AchievementFrameStats)
    hideNamed({ "AchievementFrameStatsBG" })
    local comparison = _G.AchievementFrameComparison
    stripPane(comparison, { AchievementFrameComparisonWatermark = true })

    -- The summary was 529 wide off the category list's edge and ran into the right rail; it now
    -- spans the achievement list plus that list's scroll-bar column.
    local summary = _G.AchievementFrameSummary
    if summary and list then
        summary:ClearAllPoints()
        summary:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
        summary:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", ACH_BAR_COLUMN, 0)
    end

    if categories then
        addInset(window, { -ACH_PAD, ACH_PAD, ACH_PAD, -ACH_PAD, topLeft = categories, bottomRight = categories })
    end
    if list then
        addInset(window, { -ACH_PAD, ACH_PAD, ACH_CONTENT_RIGHT, ACH_CONTENT_BOTTOM, topLeft = list })
    end

    for _, scroll in ipairs({
        "AchievementFrameCategoriesContainer", "AchievementFrameAchievementsContainer",
        "AchievementFrameStatsContainer", "AchievementFrameComparisonContainer",
        "AchievementFrameComparisonStatsContainer",
    }) do
        dressScrollBar(scroll, 1)
    end

    -- DragonUI's search panel covered the old content rect; it now covers the content inset.
    local search = addon.AchievementSearch
    if search and search.panel and list then
        search.panel:ClearAllPoints()
        search.panel:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
        search.panel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT",
            ACH_CONTENT_RIGHT - ACH_PAD, ACH_CONTENT_BOTTOM + ACH_PAD)
    end
    placeAchievementToolbar(window)
    dressAchievementTabs(host)
    window:HookScript("OnShow", function() dressAchievementTabs(host) end)
    -- Overachiever adds its tabs during the first show, after its own OnShow juggling (see hookWindows).
    hooksecurefunc("PanelTemplates_SetNumTabs", function(frame)
        if frame == window then dressAchievementTabs(host) end
    end)

    -- Comparison writes its own x offsets (38 wide, 80 back) on show and hide; the bronze window
    -- keeps the left edge every other DragonUI window uses.
    if comparison then
        local function reseat()
            nudgePanel(window, 6 - ACH_RECT[1], -ACH_RECT[2])
        end
        comparison:HookScript("OnShow", reseat)
        comparison:HookScript("OnHide", reseat)
    end
end

-- ============================================================================
-- POPUPS (StaticPopup1..4: the dialog box every confirm, timer and prompt shows in)
-- ============================================================================

-- The Dialog rail's inner edge sits 7 in (DIALOG_INSET), so the ground starts there. The popup has
-- no title band, so the close button gets a 16 square 1 unit inside the rail's corner.
local POPUP_INSET = 7
local POPUP_CLOSE_SIZE, POPUP_CLOSE_X = 16, -(POPUP_INSET + 1)

-- Rock ground under the bronze Dialog rail, over the whole of `frame`.
local function paintDialog(frame)
    local ground = frame:CreateTexture(nil, "BACKGROUND")
    ground:SetTexture(ROCK, "REPEAT", "REPEAT")
    ground:SetHorizTile(true)
    ground:SetVertTile(true)
    ground:SetPoint("TOPLEFT", frame, "TOPLEFT", POPUP_INSET, -POPUP_INSET)
    ground:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -POPUP_INSET, POPUP_INSET)
    -- Shaded with the other dialogs by the dark background setting.
    local CP = addon.CharacterPanel
    if CP then
        CP.DialogGrounds = CP.DialogGrounds or {}
        CP.DialogGrounds[#CP.DialogGrounds + 1] = ground
        if CP.ApplyBodyBackground then CP.ApplyBodyBackground() end
    end

    local host = CreateFrame("Frame", nil, frame)
    host:EnableMouse(false)
    host:SetAllPoints(frame)
    applySlicesOn(frame, host, "Dialog")
    return host
end

-- StaticPopup_Show sets the close button's art again on every show that has one.
local function dressPopupClose(popup)
    local cb = _G[popup:GetName() .. "CloseButton"]
    local CP = addon.CharacterPanel
    if not (cb and CP and CP.ModernizeCloseButton) then return end
    local info = popup.which and _G.StaticPopupDialogs[popup.which]
    if info and info.closeButtonIsHide then return end
    cb._duiModernized = nil
    CP.ModernizeCloseButton(cb, popup, POPUP_CLOSE_X, POPUP_CLOSE_X)
    cb:SetSize(POPUP_CLOSE_SIZE, POPUP_CLOSE_SIZE)
end

local function buildStaticPopup(index)
    local popup = _G["StaticPopup" .. index]
    if not popup or popup._duiStockSkinned then return end
    popup._duiStockSkinned = true

    if popup.SetBackdrop then popup:SetBackdrop(nil) end
    paintDialog(popup)

    if addon.SkinRedButton then
        for i = 1, 3 do
            addon.SkinRedButton(_G[popup:GetName() .. "Button" .. i])
        end
    end
    -- The edit box's chat-input border is unnamed, so it goes by file before the DragonUI box.
    local editBox = _G[popup:GetName() .. "EditBox"]
    local ForeverUI = addon.ForeverUI
    if editBox and ForeverUI and ForeverUI.SkinEditBox then
        hideArtByFile(editBox, { "ui%-chatinputborder" })
        ForeverUI.SkinEditBox(editBox, { font = _G.ChatFontNormal, height = 20 })
    end
    dressPopupClose(popup)
end

-- ============================================================================
-- MACROS (384x512 load-on-demand, the old character window's art: 12 in, 34 / 76 short of the rect)
-- ============================================================================

local MACRO_RECT = { 12, -12, -34, 76 }
local MACRO_HIT = { 12, 34, 12, 76 }
-- The window seat in MacroFrame space: insets' sides and the bottom row keep its gap off the rails.
local MACRO_LEFT = MACRO_RECT[1] + addon.WindowSeat.buttonLeft
local MACRO_RIGHT = MACRO_RECT[3] + addon.WindowSeat.buttonRight
local MACRO_ROW_BOTTOM = MACRO_RECT[4] + addon.WindowSeat.buttonBottom
local MACRO_PAD = 4 -- content inside the insets
local MACRO_BAR_W, MACRO_BAR_GAP = 8, 4
-- Grid: the tabs stand on its inset, nose up. MacroButtonScrollFrame lays rows of 36 + 10 from 6 in,
-- so 140 holds exactly three (the stock 146 showed 2px of a fourth) with 10 above and below them.
local MACRO_GRID_TOP, MACRO_GRID_X, MACRO_GRID_H = -78, 23, 140
local MACRO_GRID_SCROLL_Y = MACRO_GRID_TOP - MACRO_PAD
local MACRO_GRID_INSET = {
    MACRO_LEFT, MACRO_GRID_TOP, MACRO_RIGHT, 512 + MACRO_GRID_SCROLL_Y - MACRO_GRID_H - MACRO_PAD,
}
-- The selected macro's slot art; its button sits 14 in, under the grid's first column. The name,
-- Change Name/Icon and the Enter Macro Commands label hang off it.
local MACRO_SLOT_X, MACRO_SLOT_Y = 15, -222
-- Text: one inset down to the bottom row. Its label and the character count share the line above.
local MACRO_TEXT_TOP, MACRO_TEXT_X = -302, MACRO_LEFT + 6
local MACRO_TEXT_INSET = { MACRO_LEFT, MACRO_TEXT_TOP, MACRO_RIGHT, MACRO_ROW_BOTTOM + 22 + addon.WindowSeat.gap }
-- The first tab stands 6 in and 2 into the grid inset's trim, like the Social window's list tabs.
local MACRO_TAB_X, MACRO_TAB_Y = 6, -2

-- The icon picker hangs off the window's right rail instead of 6 over it. Four icon rows end 253
-- down; the 22 tall buttons sit 8 under them and 20 off the bottom, clear of the Dialog rail.
local MACRO_POPUP_GAP, MACRO_POPUP_Y, MACRO_POPUP_H = 2, -28, 303
local MACRO_POPUP_BUTTON_INSET = 20
-- The bar's column, right of the icon grid; ReskinScrollBar insets its track 7 from each end.
local MACRO_POPUP_BAR_RIGHT, MACRO_POPUP_BAR_TOP, MACRO_POPUP_BAR_BOTTOM = 24, 85 - 7, 253 + 7

local function buildMacros()
    local window = _G.MacroFrame
    if not window or window._duiStockSkinned then return end
    window._duiStockSkinned = true

    hideArtByFile(window, { "ui%-character%-general", "macroframe%-bot", "ui%-classtrainer%-horizontalbar" })
    hideNamed({ "MacroFramePortrait", "MacroFrameTextBackground" })
    local host = skinWindow(window, {
        rect = MACRO_RECT,
        hit = MACRO_HIT,
        title = fontStringByText(window, _G.CREATE_MACROS),
        close = _G.MacroFrameCloseButton,
    })
    local grid = addInset(window, MACRO_GRID_INSET)
    local text = addInset(window, MACRO_TEXT_INSET)
    dressTabs(host, "MacroFrameTab", 2, { anchor = grid, x = MACRO_TAB_X, y = MACRO_TAB_Y })

    -- Both scroll bars share one column MACRO_PAD inside the insets' right edge.
    local barLeft = window:GetWidth() + MACRO_RIGHT - MACRO_PAD - MACRO_BAR_W
    local gridScroll = _G.MacroButtonScrollFrame
    if gridScroll then
        gridScroll:ClearAllPoints()
        gridScroll:SetPoint("TOPLEFT", window, "TOPLEFT", MACRO_GRID_X, MACRO_GRID_SCROLL_Y)
        gridScroll:SetHeight(MACRO_GRID_H)
        dressScrollBar("MacroButtonScrollFrame", barLeft - MACRO_GRID_X - gridScroll:GetWidth())
    end

    local slot = _G.MacroFrameSelectedMacroBackground
    if slot then
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", window, "TOPLEFT", MACRO_SLOT_X, MACRO_SLOT_Y)
    end

    -- The edit box fills the inset beside the bar; the stock tooltip box behind it is gone.
    local textScroll = _G.MacroFrameScrollFrame
    if textScroll then
        local width = barLeft - MACRO_BAR_GAP - MACRO_TEXT_X
        local height = window:GetHeight() + MACRO_TEXT_TOP - MACRO_TEXT_INSET[4] - 2 * MACRO_PAD
        textScroll:ClearAllPoints()
        textScroll:SetPoint("TOPLEFT", window, "TOPLEFT", MACRO_TEXT_X, MACRO_TEXT_TOP - MACRO_PAD)
        textScroll:SetSize(width, height)
        for _, name in ipairs({ "MacroFrameText", "MacroFrameTextButton" }) do
            local object = _G[name]
            if object then object:SetSize(width, height) end
        end
        dressScrollBar("MacroFrameScrollFrame", MACRO_BAR_GAP)
    end
    local label, count = _G.MacroFrameEnterMacroText, _G.MacroFrameCharLimitText
    if label then
        label:ClearAllPoints()
        label:SetPoint("BOTTOMLEFT", text, "TOPLEFT", MACRO_PAD, MACRO_PAD)
    end
    if count then
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", text, "TOPRIGHT", -MACRO_PAD, MACRO_PAD)
    end

    -- Stock, the row sat on the bottom rail.
    local seat = addon.WindowSeat
    local delete, new, exit = _G.MacroDeleteButton, _G.MacroNewButton, _G.MacroExitButton
    if delete then
        delete:ClearAllPoints()
        delete:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", seat.buttonLeft, seat.buttonBottom)
    end
    if exit then
        exit:ClearAllPoints()
        exit:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", seat.buttonRight, seat.buttonBottom)
        if new then
            new:ClearAllPoints()
            new:SetPoint("RIGHT", exit, "LEFT", -1, 0)
        end
    end
    if addon.SkinRedButton then
        for _, button in ipairs({ delete, new, exit, _G.MacroEditButton }) do
            addon.SkinRedButton(button)
        end
    end
end

local function buildMacroPopup()
    local popup = _G.MacroPopupFrame
    if not popup or popup._duiStockSkinned then return end
    popup._duiStockSkinned = true

    hideArtByFile(popup, { "macropopup%-" })
    hideNamed({ "MacroPopupNameLeft", "MacroPopupNameMiddle", "MacroPopupNameRight" })
    -- Its two labels are BACKGROUND, where the rock would tie with them.
    for _, region in ipairs({ popup:GetRegions() }) do
        if region:GetObjectType() == "FontString" then region:SetDrawLayer("ARTWORK") end
    end
    popup:SetHeight(MACRO_POPUP_H)
    paintDialog(popup)

    local chrome = _G.MacroFrame and _G.MacroFrame._duiChrome
    if chrome then
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", chrome, "TOPRIGHT", MACRO_POPUP_GAP, MACRO_POPUP_Y)
    end

    local editBox = _G.MacroPopupEditBox
    local ForeverUI = addon.ForeverUI
    if editBox and ForeverUI and ForeverUI.SkinEditBox then
        ForeverUI.SkinEditBox(editBox, { font = _G.ChatFontNormal, height = 20 })
    end

    local cancel = _G.MacroPopupCancelButton
    if cancel then
        cancel:ClearAllPoints()
        cancel:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -MACRO_POPUP_BUTTON_INSET, MACRO_POPUP_BUTTON_INSET)
    end
    if addon.SkinRedButton then
        addon.SkinRedButton(_G.MacroPopupOkayButton)
        addon.SkinRedButton(cancel)
    end

    -- The scroll frame's own regions are the carved trainer groove.
    local scroll, CP = _G.MacroPopupScrollFrame, addon.CharacterPanel
    if scroll and CP and CP.ReskinScrollBar then
        for _, region in ipairs({ scroll:GetRegions() }) do
            if region:GetObjectType() == "Texture" then neuterTexture(region) end
        end
        local column = CreateFrame("Frame", nil, popup)
        -- Without a width it has no rect at all, and the bar anchored to it gets none either.
        column:SetWidth(1)
        column:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -MACRO_POPUP_BAR_RIGHT, -MACRO_POPUP_BAR_TOP)
        column:SetPoint("BOTTOMRIGHT", popup, "TOPRIGHT", -MACRO_POPUP_BAR_RIGHT, -MACRO_POPUP_BAR_BOTTOM)
        CP.ReskinScrollBar(scroll, column, 0, 0, 0, true)
    end
end

local popupShowHooked = false
local function hookPopupShow()
    if popupShowHooked or not _G.StaticPopup_Show then return end
    popupShowHooked = true
    hooksecurefunc("StaticPopup_Show", function()
        if not IsModuleEnabled() then return end
        for i = 1, _G.STATICPOPUP_NUMDIALOGS or 4 do
            local popup = _G["StaticPopup" .. i]
            if popup and popup._duiStockSkinned and popup:IsShown() then
                dressPopupClose(popup)
            end
        end
    end)
end

local BUILDERS = {
    { frame = "QuestLogFrame", build = buildQuestLog },
    { frame = "LFDParentFrame", build = buildLFD },
    { frame = "PVPParentFrame", build = buildPvP },
    { frame = "AchievementFrame", build = buildAchievements, atLoad = true },
    { frame = "GameMenuFrame", build = buildGameMenu },
    { frame = "MacroFrame", build = buildMacros },
    { frame = "MacroPopupFrame", build = buildMacroPopup },
}
for i = 1, _G.STATICPOPUP_NUMDIALOGS or 4 do
    BUILDERS[#BUILDERS + 1] = { frame = "StaticPopup" .. i, build = function() buildStaticPopup(i) end, atLoad = true }
end

-- Built on first open, like the Social window; only the panel offsets would matter before that and
-- skinWindow sets them, so the first build also re-seats a window that is already up.
-- `atLoad` windows are built as soon as they exist: Overachiever's first-show hook hides the
-- Achievement window and shows it again with OnShow cleared, and the hooks after its own are skipped
-- that once, so the first open stayed stock.
local function hookWindows()
    hookPopupShow()
    for _, entry in ipairs(BUILDERS) do
        local window = _G[entry.frame]
        if window and not window._duiStockShowHooked then
            window._duiStockShowHooked = true
            local function build()
                if not IsModuleEnabled() or window._duiStockSkinned then return end
                local ok, err = pcall(entry.build)
                if not ok and addon.Error then
                    addon:Error(entry.frame .. " skin failed: " .. tostring(err))
                end
            end
            window:HookScript("OnShow", build)
            if entry.atLoad or window:IsShown() then build() end
        end
    end
end

function addon.ApplyStockPanelsSystem()
    if not IsModuleEnabled() then return end
    StockPanels.initialized = true
    StockPanels.applied = true
    if InCombatLockdown() and addon.CombatQueue then
        addon.CombatQueue:Add("stockpanels_apply", hookWindows)
        return
    end
    hookWindows()
end

function addon.RestoreStockPanelsSystem()
    StockPanels.applied = false
end

function addon.RefreshStockPanelsSystem()
    if IsModuleEnabled() then
        addon.ApplyStockPanelsSystem()
    else
        addon.RestoreStockPanelsSystem()
    end
end

-- The Achievement and Macro windows are load-on-demand: hooked when their addon loads.
local LOAD_ON_DEMAND = { Blizzard_AchievementUI = true, Blizzard_MacroUI = true }
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        addon.ApplyStockPanelsSystem()
    elseif LOAD_ON_DEMAND[name] then
        if StockPanels.initialized then addon.ApplyStockPanelsSystem() end
    end
end)
