-- Settings: Esc > Interface > AddOns > TMPZ-LootCodex, with three sub-pages (Tooltips, Learning &
-- Sharing, Features). Also opened by the window's Settings button, right-clicking the minimap
-- button, or /codex settings.
--
-- Each page is one column laid out top to bottom by the helpers below, every option with a short
-- grey line under it, so nothing overlaps whatever the UI scale.

LootCodex = LootCodex or {}
local LC = LootCodex

local LEFT, WIDTH = 16, 530      -- WIDTH leaves room for the scroll bar
local checkCount = 0

local function Refresh() if LC.RefreshIfOpen then LC.RefreshIfOpen() end end

-- Everything on a page goes through Place(), which remembers where it went. Text lines (Note, the
-- intro) are given one line's room when built; when the page is shown they are re-fitted to the real
-- width of the window and everything below a line that wraps moves down by the extra lines. Without
-- this, long notes ran off the right edge or wrapped into the next option (UI scale and font decide
-- how much fits).
local function Place(p, region, x, dy)
    region:SetPoint("TOPLEFT", x, p.y + (dy or 0))
    p.items[#p.items + 1] = { region = region, x = x, y = p.y + (dy or 0) }
    return p.items[#p.items]
end

-- a wrapping text line; room = the height it was given when built
local function Flow(p, item, room)
    item.flow, item.room = true, room
end

local function Reflow(p, scroll)
    local w = scroll:GetWidth()
    if not w or w <= 0 then return end
    local shift = 0
    for _, it in ipairs(p.items) do
        it.region:ClearAllPoints()
        it.region:SetPoint("TOPLEFT", it.x, it.y - shift)
        if it.flow then
            it.region:SetWidth(math.max(120, w - it.x - 14))
            local h = it.region:GetStringHeight() or 0
            if h > it.room + 2 then shift = shift + (h - it.room) end
        end
    end
    p.shift = shift
end
local function ForgetUnits() if LC.ForgetUnitDrops then LC.ForgetUnitDrops() end end

-- a page; parent = nil for the main page. The page's controls live in a scroll frame inside the panel
-- the Interface Options window shows, so a page with more options than fit gets a scroll bar instead
-- of running out of the bottom of the window. Returns the scroll content (p.panel is the panel).
local function Page(name, parent, intro)
    local panel = CreateFrame("Frame", "LootCodexSettings" .. (parent and name:gsub("%W", "") or ""), UIParent)
    panel.name = parent and name or "TMPZ-LootCodex"
    panel.parent = parent
    panel:Hide()
    local scroll = CreateFrame("ScrollFrame", panel:GetName() .. "Scroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local p = CreateFrame("Frame", nil, scroll)
    p:SetSize(WIDTH + 60, 1)
    scroll:SetScrollChild(p)
    p.panel = panel
    p.y = -16
    p.onShow = {}
    p.items = {}
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    Place(p, title, LEFT)
    title:SetText("|cff33ccffTMPZ-LootCodex|r" .. (parent and ("  -  " .. name) or ""))
    p.y = p.y - 24
    if intro then
        local t = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        t:SetWidth(WIDTH)
        t:SetJustifyH("LEFT")
        t:SetText(intro)
        Flow(p, Place(p, t, LEFT), 24)
        p.y = p.y - 30
    end
    panel:SetScript("OnShow", function()
        for _, f in ipairs(p.onShow) do f() end
        -- everything is laid out by now: text lines are fitted to the window's width (see Reflow), the
        -- content is as tall as the lowest control, and the scroll bar appears only when it's taller
        local w = scroll:GetWidth()
        if w and w > 0 then p:SetWidth(w) end
        Reflow(p, scroll)
        p:SetHeight(-p.y + 20 + (p.shift or 0))
        scroll:UpdateScrollChildRect()
    end)
    InterfaceOptions_AddCategory(panel)
    return p
end

local function Heading(p, text)
    p.y = p.y - 6
    local h = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    Place(p, h, LEFT)
    h:SetText(text)
    p.y = p.y - 20
end

-- a grey explanation line under the control above it
local function Note(p, text, indent)
    local t = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    t:SetWidth(WIDTH - (indent or 0) - 26)
    t:SetJustifyH("LEFT")
    t:SetText(text)
    Flow(p, Place(p, t, LEFT + (indent or 0) + 26, 4), 12)
    p.y = p.y - 16
    return t
end

-- a tick box for LootCodexDB[key]; invert: ticked means the field is false (minimapHide)
local function Check(p, label, note, key, opts)
    opts = opts or {}
    checkCount = checkCount + 1
    local cb = CreateFrame("CheckButton", "LootCodexSettingsCheck" .. checkCount, p, "InterfaceOptionsCheckButtonTemplate")
    Place(p, cb, LEFT + (opts.indent or 0))
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if opts.invert then on = not on end
        LootCodexDB[key] = on
        if opts.onChange then opts.onChange(on) end
    end)
    p.y = p.y - 26
    if note then Note(p, note, opts.indent) end
    p.y = p.y - 4
    p.onShow[#p.onShow + 1] = function()
        local v = LootCodexDB[key] and true or false
        if opts.invert then v = not v end
        cb:SetChecked(v)
    end
    return cb
end

local function Button(p, text, width, onClick, indent)
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    Place(p, b, LEFT + 4 + (indent or 0))
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    p.y = p.y - 28
    return b
end

local function Enable(widget, on)
    if on then widget:Enable() else widget:Disable() end
    local name = widget.GetName and widget:GetName()
    local text = name and _G[name .. "Text"]
    if text and text.SetTextColor then text:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5) end
end

------------------------------------------------------------------------
-- main page
------------------------------------------------------------------------
local main = Page("TMPZ-LootCodex", nil,
    "Search every item on Project Epoch and see where it comes from. More options are on the pages"
    .. " under TMPZ-LootCodex in the list on the left: Tooltips, Learning & Sharing, and Features.")

Button(main, "Open TMPZ-LootCodex", 200, function()
    InterfaceOptionsFrame:Hide()
    if LC.Toggle then LC.Toggle() end
end)
Note(main, "Or type /codex.  /codex help lists every command;  /codex status shows what was found.", -26)

Heading(main, "Display")
Check(main, "Show the minimap button", "Click it to open the window, right-click for these settings, drag to move it.",
    "minimapHide", { invert = true, onChange = function() if LC.UpdateMinimapButton then LC.UpdateMinimapButton() end end })
Check(main, "Status message when logging in", "One chat line: ready, and whether pfQuest and pfQuest-epoch were found.",
    "loginMessage")
Check(main, "Tell me when a newer version is out",
    "One chat line when a guild or group member runs a newer TMPZ-LootCodex. Needs sharing on.", "versionNotice")
Check(main, "Chat messages for background work",
    "Update checks and loading the item data. Guild/group sharing only shows here when the minimap badge is off.",
    "activityMessages")
Check(main, "Show TBC/WotLK leftovers and test items",
    "Items the server still knows but Project Epoch (classic) doesn't use. Hidden everywhere by default.",
    "showHidden", { onChange = function() ForgetUnits(); if LC.Refresh then LC.Refresh() end end })

------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------
local tips = Page("Tooltips", "TMPZ-LootCodex", "What TMPZ-LootCodex adds to item and creature tooltips.")

Heading(tips, "Item tooltips")
local itemBox = Check(tips, "Add TMPZ-LootCodex lines to item tooltips",
    "Off: item tooltips look like the game's own (no wishlist star, Reborn tag, upgrade line or sources).",
    "itemTooltip")
local srcBox = Check(tips, "Show where items come from", "Drops, crafting, quests, vendors and bosses under every item tooltip.",
    "tooltip", { indent = 24 })
local function UpdateItemOptions() Enable(srcBox, itemBox:GetChecked() and true or false) end
itemBox:HookScript("OnClick", UpdateItemOptions)
tips.onShow[#tips.onShow + 1] = function() Enable(srcBox, LootCodexDB.itemTooltip and true or false) end

Heading(tips, "Creature tooltips")
local unitBox = Check(tips, "Show what creatures drop", "Hover a mob to see its loot, best chance first.", "unitTooltip")
local greyBox = Check(tips, "Leave out grey (junk) items", nil, "unitHideGrey", { indent = 24, onChange = ForgetUnits })
local shiftBox = Check(tips, "Only while holding the key below", "Keeps creature tooltips short until you want the list.",
    "unitShift", { indent = 24 })

-- the key held for the longer lists (and, with the mouse wheel, to scroll them)
Heading(tips, "Longer lists")
local keyLabel = tips:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
Place(tips, keyLabel, LEFT + 4, -4)
keyLabel:SetText("Hold this key for the full list:")
local keyRadios = {}
for i, k in ipairs({ { "CTRL", "Ctrl" }, { "ALT", "Alt" } }) do
    local r = CreateFrame("CheckButton", "LootCodexSettingsKey" .. i, tips, "UIRadioButtonTemplate")
    Place(tips, r, LEFT + 200 + (i - 1) * 70, -2)
    _G[r:GetName() .. "Text"]:SetText(k[2])
    r.value = k[1]
    keyRadios[i] = r
end
tips.y = tips.y - 24
local keyNote = Note(tips, "", -26)

local slider = CreateFrame("Slider", "LootCodexSettingsLines", tips, "OptionsSliderTemplate")
Place(tips, slider, LEFT + 8, -16)
slider:SetWidth(240)
slider:SetMinMaxValues(3, 15)
slider:SetValueStep(1)
_G[slider:GetName() .. "Low"]:SetText("3")
_G[slider:GetName() .. "High"]:SetText("15")
tips.y = tips.y - 50

local function UpdateKeyNote()
    local bound = LC.BindWheel and LC.BindWheel()
    local name = LC.MoreKeyName()
    if InCombatLockdown() then
        keyNote:SetText("Scrolling switches over when combat ends.")
    elseif bound then
        keyNote:SetText("Item and creature tooltips: hold " .. name .. " for up to 15 lines; " .. name
            .. " + mouse wheel scrolls longer lists.")
    else
        keyNote:SetText("|cffff8040" .. name .. " + mouse wheel is bound to something else, so it won't scroll.|r")
    end
    for _, r in ipairs(keyRadios) do r:SetChecked(r.value == LC.MoreKey()) end
    _G[slider:GetName() .. "Text"]:SetText("Creature drops shown: " .. (LootCodexDB.unitLines or 6)
        .. "  (" .. name .. " shows more)")
end

for _, r in ipairs(keyRadios) do
    r:SetScript("OnClick", function(self)
        LootCodexDB.moreKey = self.value
        UpdateKeyNote()
    end)
end
slider:SetScript("OnValueChanged", function(self, v)
    LootCodexDB.unitLines = math.floor(v + 0.5)
    UpdateKeyNote()
end)

local function UpdateUnitOptions()
    local on = unitBox:GetChecked() and true or false
    Enable(greyBox, on)
    Enable(shiftBox, on)
    if on then slider:Enable() else slider:Disable() end
end
unitBox:HookScript("OnClick", UpdateUnitOptions)
tips.onShow[#tips.onShow + 1] = function()
    slider:SetValue(LootCodexDB.unitLines or 6)
    UpdateKeyNote()
    UpdateUnitOptions()
end

------------------------------------------------------------------------
-- Learning & Sharing
------------------------------------------------------------------------
local learn = Page("Learning & Sharing", "TMPZ-LootCodex",
    "TMPZ-LootCodex fills in what no database knows yet (Epoch's custom mobs, quests and new items) from"
    .. " what you and your guild actually see.")

Check(learn, "Record what I loot, what vendors sell and quest rewards",
    "Shown in tooltips as \"seen\", with real drop counts.", "record")
Check(learn, "Share with guild and group members using TMPZ-LootCodex",
    "Hidden addon messages, about one a second at most. Nothing shows in chat.", "share")
Check(learn, "Show new shared finds on the minimap button",
    "A green number on the button counts what others found since you last hovered it; hover to see them."
    .. " While it's on, sharing stays out of the chat window.",
    "sharedNotify", { indent = 24, onChange = function() if LC.UpdateSharedBadge then LC.UpdateSharedBadge() end end })
Check(learn, "Learn new items automatically",
    "Items the database doesn't have are saved when you see them and shared, so Epoch patches don't need a rescan.",
    "learnItems")
Heading(learn, "Updates")
local updateButton
updateButton = Button(learn, "Check for updates now", 220, function()
    if LC.UpdateCheckProgress() then LC.StopUpdateCheck() else LC.StartUpdateCheck() end
    updateButton:SetText(LC.UpdateCheckProgress() and "Stop checking" or "Check for updates now")
end, 22)
Note(learn, "Asks the server about new Epoch items and changes to known ones, in the background (a few minutes).", -4)
Check(learn, "Check automatically once a day, a minute after logging in", nil, "autoUpdateCheck")
learn.onShow[#learn.onShow + 1] = function()
    updateButton:SetText(LC.UpdateCheckProgress() and "Stop checking" or "Check for updates now")
end

Heading(learn, "Shared data")
Button(learn, "Forget what others shared", 220, function()
    LC.ForgetShared()
    ForgetUnits()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffTMPZ-LootCodex:|r forgot everything other players shared."
        .. " Your own records are kept.")
end, 22)
Note(learn, "Your own records are kept. /codex ignore <name> drops and blocks one player.", -4)

------------------------------------------------------------------------
-- Features
------------------------------------------------------------------------
local feat = Page("Features", "TMPZ-LootCodex", "Optional extras. Each one can be switched off on its own.")

Check(feat, "Show on map", "Right-click an item in the window to pin where it comes from (needs pfQuest).", "mapPins")
Check(feat, "Upgrade finder", "Arrows in the window and a line on item tooltips: better or worse than what you wear.",
    "upgrades", { onChange = Refresh })

local specLabel = feat:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
Place(feat, specLabel, LEFT + 30, -5)
specLabel:SetText("Score items for:")
local specButton = CreateFrame("Button", nil, feat, "UIPanelButtonTemplate")
specButton:SetSize(220, 20)
Place(feat, specButton, LEFT + 130)
feat.y = feat.y - 30
local function SpecText()
    local v = LootCodexDB.upgradeSpec or "auto"
    local name = LC.SpecName and LC.SpecName() or "?"
    specButton:SetText(v == "auto" and ("Auto (" .. name .. ")") or name)
end
specButton:SetScript("OnClick", function(self)
    local opts = { { "auto", "Auto: from my talents" } }
    for _, o in ipairs(LC.SpecChoices()) do opts[#opts + 1] = o end
    LC.ShowMenu(self, opts, function(v)
        LootCodexDB.upgradeSpec = v
        SpecText()
        Refresh()
    end)
end)
feat.onShow[#feat.onShow + 1] = SpecText

Check(feat, "Mark the best quest reward",
    "An arrow on the best upgrade among a quest's choices, or a coin on the one that sells for most.", "questBest")
Check(feat, "Wishlist alerts", "When a wishlisted item is in a loot window or up for roll.", "wishAlerts")
Check(feat, "Wishlist creature alerts",
    "Targeting or fighting a mob that drops a wishlisted item says so, and stars its portrait."
    .. " Once per kind of mob every 5 minutes.  /codex wishcheck asks about your target.",
    "wishMobAlerts", { onChange = function() if LC.ForgetMobAlerts then LC.ForgetMobAlerts() end end })

-- how both kinds of wishlist alert are shown (Wishlist.lua: LC.ALERT_STYLES)
local styleLabel = feat:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
Place(feat, styleLabel, LEFT + 30, -2)
styleLabel:SetText("Show wishlist alerts as:")
feat.y = feat.y - 16
local styleRadios = {}
local function SyncStyle()
    local cur = LC.WishAlertStyle and LC.WishAlertStyle() or "sound"
    for _, r in ipairs(styleRadios) do r:SetChecked(r.value == cur) end
end
for i, s in ipairs(LC.ALERT_STYLES or {}) do
    local r = CreateFrame("CheckButton", "LootCodexSettingsAlertStyle" .. i, feat, "UIRadioButtonTemplate")
    Place(feat, r, LEFT + 34 + ((i - 1) % 2) * 190, -math.floor((i - 1) / 2) * 20)
    _G[r:GetName() .. "Text"]:SetText(s[2])
    r.value = s[1]
    r:SetScript("OnClick", function(self)
        LootCodexDB.wishAlertStyle = self.value
        SyncStyle()
    end)
    styleRadios[i] = r
end
feat.y = feat.y - 44
Note(feat, "On screen = the big raid-warning text. Every choice except Off also puts a line in chat.  /codex alerts", 4)
feat.onShow[#feat.onShow + 1] = SyncStyle
Check(feat, "Remember recently viewed items", "The Recent tab: items you click in the window or open from chat links.",
    "trackRecent")
Check(feat, "Open on the dungeon you're in",
    "Inside a dungeon or raid, opening the window shows that dungeon's loot on the Dungeons tab.", "autoDungeon")

function LC.OpenSettings()
    -- the first call in 3.3.5 can land on the wrong page; the second one sticks
    InterfaceOptionsFrame_OpenToCategory(main.panel)
    InterfaceOptionsFrame_OpenToCategory(main.panel)
end
