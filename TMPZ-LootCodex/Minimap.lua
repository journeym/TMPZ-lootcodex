-- Minimap button: click to open Loot Codex, drag to move it around the minimap edge.
-- Built the same way as Blizzard's tracking button, so minimap-button collectors pick it up.

LootCodex = LootCodex or {}
local LC = LootCodex

local DEFAULT_ANGLE = 200          -- degrees, 0 = right of the minimap, counter-clockwise

local btn = CreateFrame("Button", "LootCodexMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local overlay = btn:CreateTexture(nil, "OVERLAY")
overlay:SetSize(53, 53)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetPoint("TOPLEFT")

local bg = btn:CreateTexture(nil, "BACKGROUND")
bg:SetSize(20, 20)
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetPoint("TOPLEFT", 7, -5)

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
icon:SetPoint("TOPLEFT", 7, -6)

-- a small green number: finds other players shared since you last hovered the button
local badgeBg = btn:CreateTexture(nil, "OVERLAY")
badgeBg:SetSize(16, 14)
badgeBg:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 2, 1)
badgeBg:SetTexture(0, 0, 0, 0.75)
local badge = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
badge:SetPoint("CENTER", badgeBg, "CENTER", 0, 0)
badge:SetTextColor(0.3, 1, 0.3)

function LC.UpdateSharedBadge()
    local n = LC.SharedUnseen and LC.SharedUnseen() or 0
    if n > 0 and LootCodexDB and LootCodexDB.sharedNotify then
        badge:SetText(n > 99 and "99+" or tostring(n))
        badgeBg:SetWidth(n > 9 and 22 or 16)
        badge:Show(); badgeBg:Show()
    else
        badge:Hide(); badgeBg:Hide()
    end
end

-- while an update check runs: the icon turns into a spyglass with the percentage under it
local scanText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
scanText:SetPoint("BOTTOM", btn, "BOTTOM", 0, -2)
scanText:SetTextColor(1, 0.82, 0)
scanText:Hide()
local scanWatch = CreateFrame("Frame")
local scanElapsed = 0

function LC.UpdateScanIndicator()
    local pct = LC.UpdateCheckProgress and LC.UpdateCheckProgress()
    if pct then
        icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
        scanText:SetText(pct .. "%")
        scanText:Show()
        scanWatch:Show()
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        scanText:Hide()
        scanWatch:Hide()
    end
end

scanWatch:Hide()
scanWatch:SetScript("OnUpdate", function(_, dt)
    scanElapsed = scanElapsed + dt
    if scanElapsed < 1 then return end
    scanElapsed = 0
    LC.UpdateScanIndicator()
end)

local function Ago(t)
    local s = time() - (t or time())
    if s < 60 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " d ago"
end

local function Place()
    local a = math.rad(LootCodexDB.minimapAngle or DEFAULT_ANGLE)
    local r = Minimap:GetWidth() / 2 + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    LootCodexDB.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
    Place()
end

btn:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", FollowCursor)
end)
btn:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
end)

btn:SetScript("OnClick", function(_, button)
    GameTooltip:Hide()
    if button == "RightButton" then LC.OpenSettings() else LC.Toggle() end
end)

btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff33ccffTMPZ-LootCodex|r")
    GameTooltip:AddLine("Click to search every item on the server.", 1, 1, 1)
    local c = LC.LearnedCounts and LC.LearnedCounts()
    if c then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Mobs learned", c.mobs, 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Vendor items", c.vendors, 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Quest rewards", c.quests, 1, 0.82, 0, 1, 1, 1)
        if c.senders > 0 then
            GameTooltip:AddDoubleLine("Shared with you", c.received .. " from " .. c.senders .. " players",
                1, 0.82, 0, 0.4, 0.8, 1)
        end
    end
    -- what other players have sent since you last looked
    local unseen = LC.SharedUnseen and LC.SharedUnseen() or 0
    local recent = LC.SharedRecent and LC.SharedRecent() or {}
    if LootCodexDB.sharedNotify and unseen > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("New from guild/group: %d", unseen), 0.3, 1, 0.3)
        for i = 1, math.min(unseen, #recent) do
            local e = recent[i]
            GameTooltip:AddDoubleLine("  " .. e.text, (e.from or "?") .. ", " .. Ago(e.t), 1, 1, 1, 0.6, 0.6, 0.6)
        end
        if unseen > #recent then
            GameTooltip:AddLine(string.format("  ...and %d more", unseen - #recent), 0.6, 0.6, 0.6)
        end
    elseif recent[1] then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Last shared: " .. recent[1].text, (recent[1].from or "?") .. ", " .. Ago(recent[1].t),
            0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    end
    -- (called directly: "x and f()" would keep only the first of its three values)
    local pct, new, changed
    if LC.UpdateCheckProgress then pct, new, changed = LC.UpdateCheckProgress() end
    if pct then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("Checking for updates: %d%%  (%d new, %d changed so far)", pct, new, changed),
            1, 0.82, 0)
    end
    local queued = LC.SyncQueued and LC.SyncQueued() or 0
    if queued > 0 then
        GameTooltip:AddLine(string.format("Sharing: %d messages to send", queued), 0.4, 0.8, 1)
    elseif LootCodexDB.share == false then
        GameTooltip:AddLine("Sharing is off (/codex share)", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click: settings.  Drag to move.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
    if LC.SharedUnseen and LC.SharedUnseen() > 0 then LC.MarkSharedSeen() end   -- you've seen them now
end)

function LC.UpdateMinimapButton()
    if LootCodexDB.minimapHide then btn:Hide() else Place(); btn:Show() end
    LC.UpdateSharedBadge()
end

btn:Hide()
btn:RegisterEvent("PLAYER_LOGIN")
btn:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    LC.UpdateMinimapButton()
end)
