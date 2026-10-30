-- Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)
local L = addon.L

local max, floor = math.max, math.floor

local TICK = 0.1
-- The client's own latency (GetNetStats) is answered on the server's network thread, so a stalled
-- world update never shows in it. An addon whisper to ourselves goes through the world update loop.
local PREFIX = "DragonUILag"
local PING_EVERY = 5
-- An unanswered ping is sent again after this long; the reading keeps climbing meanwhile.
local RESEND_AFTER = 30
local MOVER_MIN_HEIGHT = 16

local Lag = {}
local elapsed = 0
local seq = 0
local sentAt            -- GetTime() of the ping in flight
local waitingSince      -- the first unanswered ping; survives resends
local lastMs            -- the last answered round trip
local nextPing = 0

local function enabled()
    local settings = addon.db and addon.db.profile.minimap
    return settings and settings.latency ~= false and addon:IsModuleEnabled("minimap")
end

local function GetWidget(create)
    local widgets = addon.db and addon.db.profile and addon.db.profile.widgets
    if widgets and create and not widgets.latency then
        widgets.latency = {}
    end
    return widgets and widgets.latency
end

local function IsCustomPlaced()
    local widget = GetWidget()
    return widget and widget.custom_position and widget.posX ~= nil and widget.posY ~= nil or false
end

local function Layout()
    local mover, sizer = Lag.mover, Lag.sizer
    local ratio = Lag.holder:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local width, height = sizer:GetStringWidth() * ratio, sizer:GetStringHeight() * ratio
    local moverHeight = max(height, MOVER_MIN_HEIGHT)

    local custom, widget = IsCustomPlaced(), GetWidget()
    -- Under the speed line wherever that is; in its spot when it is switched off.
    local speed = not custom and addon.MovementSpeedMover and addon.MovementSpeedMover()
    local beside, drop
    if not custom and not speed then beside, drop = addon.MinimapReadoutSpot() end
    local key = table.concat({ width, moverHeight, tostring(custom), tostring(speed), tostring(beside),
        tostring(drop), custom and widget.posX or "", custom and widget.posY or "" }, ":")
    if key == Lag.layoutKey then return end
    Lag.layoutKey = key

    mover:SetSize(width, moverHeight)
    mover:ClearAllPoints()
    if custom then
        mover:SetPoint("CENTER", UIParent, "CENTER", widget.posX, widget.posY)
    elseif speed then
        mover:SetPoint("TOP", speed, "BOTTOM", 0, 0)
    elseif beside then
        mover:SetPoint("TOPLEFT", DurabilityFrame, "TOPRIGHT", 2, (moverHeight - height) / 2)
    else
        mover:SetPoint("TOP", Minimap, "BOTTOM", 0, (moverHeight - height) / 2 - drop)
    end
end

-- The stock latency meter's thresholds and colours.
local function Colour(ms)
    if ms <= (PERFORMANCEBAR_LOW_LATENCY or 300) then return 0, 1, 0 end
    if ms <= (PERFORMANCEBAR_MEDIUM_LATENCY or 600) then return 1, 1, 0 end
    return 1, 0, 0
end

local function Show(ms)
    local text = Lag.text
    if ms then
        text:SetText(string.format(L["Lag %d ms"], ms))
        text:SetTextColor(Colour(ms))
    else
        text:SetText(L["Lag --"])
        text:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
    end
end

-- While the server is slow to answer, the time waited so far is the better reading.
local function Read(now)
    local waited = waitingSince and floor((now - waitingSince) * 1000 + 0.5)
    if lastMs and waited then
        Show(max(lastMs, waited))
    else
        Show(lastMs)
    end
end

local function Ping(now)
    seq = seq + 1
    sentAt = now
    waitingSince = waitingSince or now
    SendAddonMessage(PREFIX, tostring(seq), "WHISPER", UnitName("player"))
end

local function OnPong(message)
    if not sentAt or message ~= tostring(seq) then return end
    local now = GetTime()
    lastMs = floor((now - sentAt) * 1000 + 0.5)
    sentAt, waitingSince = nil, nil
    nextPing = now + PING_EVERY
    if Lag.holder and Lag.holder:IsShown() and not (addon.EditorMode and addon.EditorMode:IsActive()) then
        Read(now)
    end
end

-- A loading screen stops the clock on our side; whatever was in flight says nothing about the server.
local function Forget()
    sentAt, waitingSince = nil, nil
    nextPing = 0
end

-- No configPath on purpose: GetPoint offsets read back skewed, so the on-screen centre is stored instead.
local function SaveMoved()
    local x, y = addon.GetAnchorOffset(Lag.mover, "CENTER")
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
    Lag.layoutKey = nil
end

local function Create()
    if Lag.holder then return end

    -- On the minimap cluster, so it scales, fades and hides along with the minimap.
    local holder = CreateFrame("Frame", "DragonUILatency", MinimapCluster)
    holder:SetSize(1, 1)
    holder:SetFrameStrata("LOW")
    holder:EnableMouse(false)
    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", holder, "CENTER", 0, 0)
    -- Sizes the mover for a wide reading, so it never jumps as the number grows.
    local sizer = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizer:SetText(string.format(L["Lag %d ms"], 8888))
    sizer:Hide()
    Lag.holder, Lag.text, Lag.sizer = holder, text, sizer

    local mover = addon.CreateUIFrame(70, MOVER_MIN_HEIGHT, "LatencyAnchor")
    mover:HookScript("OnDragStop", SaveMoved)
    holder:SetPoint("CENTER", mover, "CENTER", 0, 0)
    Lag.mover = mover

    addon:RegisterEditableFrame({
        name = "latency",
        frame = mover,
        hasTarget = enabled,
        editorVisible = enabled,
        showTest = function() Show(45) end,
        hideTest = function() Read(GetTime()) end,
        onNudge = SaveMoved,
        resetPosition = ResetPosition,
        isDefaultPosition = function() return not IsCustomPlaced() end,
        module = Lag,
    })
end

local function OnUpdate(_, delta)
    elapsed = elapsed + delta
    if elapsed < TICK then return end
    elapsed = 0
    if not enabled() then
        if Lag.holder then Lag.holder:Hide() end
        Forget()
        return
    end
    Create()
    Lag.holder:Show()
    local now = GetTime()
    if sentAt then
        if now - sentAt >= RESEND_AFTER then Ping(now) end
    elseif now >= nextPing then
        Ping(now)
    end
    -- The editor shows a sample and owns the mover while it is open.
    if addon.EditorMode and addon.EditorMode:IsActive() then return end
    Layout()
    Read(now)
end

-- Entry point for the options toggle: apply on the next frame instead of the next tick.
function addon.RefreshLatency()
    elapsed = TICK
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_LEAVING_WORLD")
driver:RegisterEvent("CHAT_MSG_ADDON")
driver:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if prefix == PREFIX and channel == "WHISPER" and sender == UnitName("player") then OnPong(message) end
    elseif event == "PLAYER_LEAVING_WORLD" then
        self:SetScript("OnUpdate", nil)
        Forget()
    else
        Forget()
        self:SetScript("OnUpdate", OnUpdate)
    end
end)
