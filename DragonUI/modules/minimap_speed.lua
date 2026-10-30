-- Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local L = addon.L

local max, floor = math.max, math.floor

-- Yards a second at 100%: the plain run speed. Swimming and flying count against it too, as on retail.
local BASE_SPEED = 7
local TICK = 0.1
-- Room between the text and the ring, and below a bare map (SexyMap, ring hidden).
local GAP, BARE_GAP = 2, 6
-- The square frames' art runs well past the drawn line, so their bottom edge says nothing.
local SQUARE_DROP = 6
-- The editor's 16px corners overlap on anything shorter.
local MOVER_MIN_HEIGHT = 16

local Speed = {}
local lastPercent      -- the last speed seen while moving; shown dimmed once standing
local elapsed = 0

local function enabled()
    local settings = addon.db and addon.db.profile.minimap
    return settings and settings.movement_speed ~= false and addon:IsModuleEnabled("minimap")
end

local function GetWidget(create)
    local widgets = addon.db and addon.db.profile and addon.db.profile.widgets
    if widgets and create and not widgets.movespeed then
        widgets.movespeed = {}
    end
    return widgets and widgets.movespeed
end

local function IsCustomPlaced()
    local widget = GetWidget()
    return widget and widget.custom_position and widget.posX ~= nil and widget.posY ~= nil or false
end

-- The durability figure hangs off the minimap's bottom at its own default spot; the text steps aside.
local function DurabilityInTheWay()
    if not (DurabilityFrame and DurabilityFrame:IsShown()) then return false end
    local widgets = addon.db.profile.widgets
    return not (widgets and widgets.durability and widgets.durability.custom_position)
end

-- How far the ring hangs below the map itself, in UIParent units.
local function RingDrop()
    local circle = Minimap.Circle
    if not (circle and circle:IsVisible()) then return BARE_GAP end
    local style = addon.db.profile.minimap.style
    if style == "dragonui_square" or style == "forever_square" then return SQUARE_DROP end
    local mapBottom, ringBottom = Minimap:GetBottom(), circle:GetBottom()
    if not (mapBottom and ringBottom) then return BARE_GAP end
    -- The ring is a texture: it has no scale of its own and draws in its parent frame's.
    local drop = mapBottom * Minimap:GetEffectiveScale() - ringBottom * circle:GetParent():GetEffectiveScale()
    return max(0, drop / UIParent:GetEffectiveScale()) + GAP
end

-- The default spot for a readout under the minimap: beside the durability figure, or this far below the map.
function addon.MinimapReadoutSpot()
    if DurabilityInTheWay() then return true, false end
    return false, RingDrop()
end

local function Layout()
    local mover, sizer = Speed.mover, Speed.sizer
    local ratio = Speed.holder:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local width, height = sizer:GetStringWidth() * ratio, sizer:GetStringHeight() * ratio
    local moverHeight = max(height, MOVER_MIN_HEIGHT)

    local custom, widget = IsCustomPlaced(), GetWidget()
    local beside, drop
    if not custom then beside, drop = addon.MinimapReadoutSpot() end
    local key = table.concat({ width, moverHeight, tostring(custom), tostring(beside), tostring(drop),
        custom and widget.posX or "", custom and widget.posY or "" }, ":")
    if key == Speed.layoutKey then return end
    Speed.layoutKey = key

    mover:SetSize(width, moverHeight)
    mover:ClearAllPoints()
    if custom then
        mover:SetPoint("CENTER", UIParent, "CENTER", widget.posX, widget.posY)
    elseif beside then
        mover:SetPoint("TOPLEFT", DurabilityFrame, "TOPRIGHT", 2, (moverHeight - height) / 2)
    else
        mover:SetPoint("TOP", Minimap, "BOTTOM", 0, (moverHeight - height) / 2 - drop)
    end
end

local function Show(percent, moving)
    local text = Speed.text
    text:SetText(percent and string.format(L["Speed %d%%"], percent) or L["Speed --"])
    local color = moving and NORMAL_FONT_COLOR or GRAY_FONT_COLOR
    text:SetTextColor(color.r, color.g, color.b)
end

local function Read()
    local unit = UnitInVehicle("player") and "vehicle" or "player"
    local speed = GetUnitSpeed(unit) or 0
    if speed > 0 then
        lastPercent = floor(speed / BASE_SPEED * 100 + 0.5)
        Show(lastPercent, true)
    else
        Show(lastPercent, false)
    end
end

-- No configPath on purpose: GetPoint offsets read back skewed, so the on-screen centre is stored instead.
local function SaveMoved()
    local x, y = addon.GetAnchorOffset(Speed.mover, "CENTER")
    local widget = GetWidget(true)
    if not (x and widget) then return end
    widget.anchor, widget.posX, widget.posY = "CENTER", floor(x + 0.5), floor(y + 0.5)
    widget.custom_position = true
    Layout()
end

local function ResetPosition()
    local widget = GetWidget()
    if widget then
        widget.custom_position, widget.anchor, widget.posX, widget.posY = false, nil, nil, nil
    end
    Speed.layoutKey = nil
end

local function Create()
    if Speed.holder then return end

    -- On the minimap cluster, so it scales, fades and hides along with the minimap.
    local holder = CreateFrame("Frame", "DragonUIMovementSpeed", MinimapCluster)
    holder:SetSize(1, 1)
    holder:SetFrameStrata("LOW")
    holder:EnableMouse(false)
    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", holder, "CENTER", 0, 0)
    -- Sizes the mover for the widest reading, so it never jumps as the number grows.
    local sizer = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizer:SetText(string.format(L["Speed %d%%"], 888))
    sizer:Hide()
    Speed.holder, Speed.text, Speed.sizer = holder, text, sizer

    local mover = addon.CreateUIFrame(70, MOVER_MIN_HEIGHT, "MovementSpeedAnchor")
    mover:HookScript("OnDragStop", SaveMoved)
    holder:SetPoint("CENTER", mover, "CENTER", 0, 0)
    Speed.mover = mover

    addon:RegisterEditableFrame({
        name = "movespeed",
        frame = mover,
        hasTarget = enabled,
        editorVisible = enabled,
        showTest = function() Show(100, true) end,
        hideTest = Read,
        onNudge = SaveMoved,
        resetPosition = ResetPosition,
        isDefaultPosition = function() return not IsCustomPlaced() end,
        module = Speed,
    })
end

-- Polled rather than event-driven: the client fires nothing when speed changes, and polling also
-- picks up profile switches and minimap style/scale changes without hooks.
local function OnUpdate(_, delta)
    elapsed = elapsed + delta
    if elapsed < TICK then return end
    elapsed = 0
    if not enabled() then
        if Speed.holder then Speed.holder:Hide() end
        return
    end
    Create()
    Speed.holder:Show()
    -- The editor shows a sample and owns the mover while it is open.
    if addon.EditorMode and addon.EditorMode:IsActive() then return end
    Layout()
    Read()
end

-- Entry point for the options toggle: apply on the next frame instead of the next tick.
function addon.RefreshMovementSpeed()
    elapsed = TICK
end

addon.ResetMovementSpeedPosition = ResetPosition

-- The speed line's mover while it is on screen, so the latency line can hang below it.
function addon.MovementSpeedMover()
    return enabled() and Speed.mover or nil
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:SetScript("OnUpdate", OnUpdate)
end)
