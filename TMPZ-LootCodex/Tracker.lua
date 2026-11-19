-- The map tracker: a small window listing everything tracked on the map (Wishlist.lua keeps the list,
-- LC.Tracked()). It shows by itself while something is tracked.
--   Left-click an entry: open the world map where it's best found.   Right-click: stop tracking it.
--   Shift-click an item: link it.   "Clear" stops tracking everything.
-- Closing it with X hides it until something new is tracked (LootCodexDB.trackerHidden);
-- /codex tracker brings it back. Drag the title to move it (LootCodexDB.trackerPos).

LootCodex = LootCodex or {}
local LC = LootCodex

local ROWS, ROW_H, WIDTH = 10, 30, 230
local MOB_ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"

local f = CreateFrame("Frame", "LootCodexTracker", UIParent)
f:SetSize(WIDTH, 52)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
f:SetBackdropColor(0, 0, 0, 0.75)
f:SetBackdropBorderColor(0.4, 0.4, 0.4)
f:Hide()

f:SetScript("OnDragStart", function(self) self:StartMoving() end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    LootCodexDB.trackerPos = { point, rel, x, y }
end)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", 10, -8)
title:SetText("|cff33ccffLootCodex|r  tracking on map")

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetSize(22, 22)
close:SetPoint("TOPRIGHT", 0, 0)
close:SetScript("OnClick", function()
    LootCodexDB.trackerHidden = true
    f:Hide()
end)

local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
clear:SetSize(60, 18)
clear:SetPoint("BOTTOMRIGHT", -8, 7)
clear:SetText("Clear")
clear:SetScript("OnClick", function() LC.ClearMapPins() end)

local more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
more:SetPoint("BOTTOMLEFT", 10, 11)

local rows = {}

local function RowEnter(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if e.k == "i" and GetItemInfo(e.id) then
        GameTooltip:SetHyperlink("item:" .. e.id)
    else
        GameTooltip:AddLine(self.name:GetText() or "?")
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: show on the world map", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: stop tracking", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function RowClick(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" then
        GameTooltip:Hide()
        LC.UntrackOnMap(self.index)
    elseif IsShiftKeyDown() and e.k == "i" then
        local _, link = GetItemInfo(e.id)
        if link and not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
    else
        LC.GoToTracked(e)
    end
end

for i = 1, ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(WIDTH - 16, ROW_H - 2)
    r:SetPoint("TOPLEFT", 8, -22 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 5, -1)
    r.name:SetPoint("RIGHT", -2, 0)
    r.name:SetJustifyH("LEFT")
    r.zone = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.zone:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 5, 1)
    r.zone:SetPoint("RIGHT", -2, 0)
    r.zone:SetJustifyH("LEFT")
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", RowClick)
    rows[i] = r
end

local function ItemText(id)
    local name, _, quality, _, _, _, _, _, _, tex = GetItemInfo(id)
    local rec = LC.Item and LC.Item(id)
    name = name or (rec and rec[1]) or ("item " .. id)
    quality = quality or (rec and rec[2]) or 1
    tex = tex or GetItemIcon(id)
        or (rec and rec[8] and rec[8] ~= "" and ("Interface\\Icons\\" .. rec[8])) or "Interface\\Icons\\INV_Misc_QuestionMark"
    local c = ITEM_QUALITY_COLORS[quality] or ITEM_QUALITY_COLORS[1]
    return c.hex .. name .. "|r", tex
end

local function Place()
    f:ClearAllPoints()
    local p = LootCodexDB.trackerPos
    if p then f:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4])
    else f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80) end
end

local function Update()
    if not LootCodexDB then return end
    local list = LC.Tracked()
    if #list == 0 or not LC.CanShowOnMap() or LootCodexDB.trackerHidden then
        f:Hide()
        return
    end
    local n = math.min(#list, ROWS)
    for i = 1, ROWS do
        local r, e = rows[i], list[i]
        if i <= n then
            r.entry, r.index = e, i
            if e.k == "m" then
                r.name:SetText("|cffffd100" .. (e.name or ("NPC " .. e.id)) .. "|r")
                r.icon:SetTexture(MOB_ICON)
            else
                local text, tex = ItemText(e.id)
                r.name:SetText(text)
                r.icon:SetTexture(tex)
            end
            local zone, p = LC.TrackedBestZone(e)
            if zone then
                r.zone:SetText(zone .. (p and p.dungeon and (" (" .. p.dungeon .. ")") or ""))
            else
                r.zone:SetText("not on the world map")
            end
            r:Show()
        else
            r.entry = nil
            r:Hide()
        end
    end
    more:SetText(#list > ROWS and string.format("+%d more", #list - ROWS) or "")
    f:SetHeight(22 + n * ROW_H + 30)
    Place()
    f:Show()
end

-- Wishlist.lua calls this whenever the tracked list changes. Tracking something new brings a closed
-- tracker back; removing entries leaves it as it was.
local lastCount         -- nil until the login call, so logging in doesn't reopen a closed tracker
function LC.TrackerChanged()
    if not LootCodexDB then return end
    local count = #LC.Tracked()
    if lastCount and count > lastCount then LootCodexDB.trackerHidden = nil end
    lastCount = count
    Update()
end

-- /codex tracker
function LC.ToggleTracker()
    if f:IsShown() then
        LootCodexDB.trackerHidden = true
        f:Hide()
        return "hidden"
    end
    LootCodexDB.trackerHidden = nil
    Update()
    if f:IsShown() then return "shown" end
    return LC.CanShowOnMap() and "empty" or "nomap"
end

-- item names arrive from the server a moment after the first GetItemInfo (3.3.5 has no event for it):
-- redraw a couple of times after the tracker opens
local REDRAW = { 1.5, 4 }      -- seconds after opening
local wait, step = 0, 1
f:SetScript("OnShow", function() wait, step = 0, 1 end)
f:SetScript("OnUpdate", function(self, dt)
    if not REDRAW[step] then return end
    wait = wait + dt
    if wait >= REDRAW[step] then
        step = step + 1
        Update()
    end
end)
