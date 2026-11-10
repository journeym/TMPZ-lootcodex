-- Settings: Esc > Interface > AddOns > TMPZ-LootCodex, with three sub-pages (Tooltips, Learning &
-- Sharing, Features). Also opened by the window's Settings button, right-clicking the minimap
-- button, or /codex settings.
--
-- Each page is one column laid out top to bottom by the helpers below, every option with a short
-- grey line under it, so nothing overlaps whatever the UI scale.

LootCodex = LootCodex or {}
local LC = LootCodex

local LEFT, WIDTH = 16, 560
local checkCount = 0

local function Refresh() if LC.RefreshIfOpen then LC.RefreshIfOpen() end end
local function ForgetUnits() if LC.ForgetUnitDrops then LC.ForgetUnitDrops() end end

-- a page; parent = nil for the main page
local function Page(name, parent, intro)
    local p = CreateFrame("Frame", "LootCodexSettings" .. (parent and name:gsub("%W", "") or ""), UIParent)
    p.name = parent and name or "TMPZ-LootCodex"
    p.parent = parent
    p:Hide()
    p.y = -16
    p.onShow = {}
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", LEFT, p.y)
    title:SetText("|cff33ccffTMPZ-LootCodex|r" .. (parent and ("  -  " .. name) or ""))
    p.y = p.y - 24
    if intro then
        local t = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", LEFT, p.y)
        t:SetWidth(WIDTH)
        t:SetJustifyH("LEFT")
        t:SetText(intro)
        p.y = p.y - 30
    end
    p:SetScript("OnShow", function() for _, f in ipairs(p.onShow) do f() end end)
    InterfaceOptions_AddCategory(p)
    return p
end

local function Heading(p, text)
    p.y = p.y - 6
    local h = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", LEFT, p.y)
    h:SetText(text)
    p.y = p.y - 20
end

-- a grey explanation line under the control above it
local function Note(p, text, indent)
    local t = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    t:SetPoint("TOPLEFT", LEFT + (indent or 0) + 26, p.y + 4)
    t:SetWidth(WIDTH - (indent or 0) - 26)
    t:SetJustifyH("LEFT")
    t:SetText(text)
    p.y = p.y - 16
    return t
end

-- a tick box for LootCodexDB[key]; invert: ticked means the field is false (minimapHide)
local function Check(p, label, note, key, opts)
    opts = opts or {}
    checkCount = checkCount + 1
    local cb = CreateFrame("CheckButton", "LootCodexSettingsCheck" .. checkCount, p, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", LEFT + (opts.indent or 0), p.y)
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
    b:SetPoint("TOPLEFT", LEFT + 4 + (indent or 0), p.y)
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
keyLabel:SetPoint("TOPLEFT", LEFT + 4, tips.y - 4)
keyLabel:SetText("Hold this key for the full list:")
local keyRadios = {}
for i, k in ipairs({ { "CTRL", "Ctrl" }, { "ALT", "Alt" } }) do
    local r = CreateFrame("CheckButton", "LootCodexSettingsKey" .. i, tips, "UIRadioButtonTemplate")
    r:SetPoint("TOPLEFT", LEFT + 200 + (i - 1) * 70, tips.y - 2)
    _G[r:GetName() .. "Text"]:SetText(k[2])
    r.value = k[1]
    keyRadios[i] = r
end
tips.y = tips.y - 24
local keyNote = Note(tips, "", -26)

local slider = CreateFrame("Slider", "LootCodexSettingsLines", tips, "OptionsSliderTemplate")
slider:SetPoint("TOPLEFT", LEFT + 8, tips.y - 16)
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
specLabel:SetPoint("TOPLEFT", LEFT + 30, feat.y - 5)
specLabel:SetText("Score items for:")
local specButton = CreateFrame("Button", nil, feat, "UIPanelButtonTemplate")
specButton:SetSize(220, 20)
specButton:SetPoint("TOPLEFT", LEFT + 130, feat.y)
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
Check(feat, "Wishlist alerts", "Raid-warning text and a sound when a wishlisted item is in a loot window or up for roll.",
    "wishAlerts")
local mobBox = Check(feat, "Wishlist creature alerts",
    "Targeting or fighting a mob that drops a wishlisted item says so on screen and stars its portrait."
    .. " Once per kind of mob every 5 minutes.  /codex wishcheck asks about your target.",
    "wishMobAlerts", { onChange = function() if LC.ForgetMobAlerts then LC.ForgetMobAlerts() end end })
local mobSound = Check(feat, "Play a sound with them", nil, "wishMobSound", { indent = 24 })
mobBox:HookScript("OnClick", function(self) Enable(mobSound, self:GetChecked() and true or false) end)
feat.onShow[#feat.onShow + 1] = function() Enable(mobSound, LootCodexDB.wishMobAlerts and true or false) end
Check(feat, "Remember recently viewed items", "The Recent tab: items you click in the window or open from chat links.",
    "trackRecent")
Check(feat, "Open on the dungeon you're in",
    "Inside a dungeon or raid, opening the window shows that dungeon's loot on the Dungeons tab.", "autoDungeon")

function LC.OpenSettings()
    -- the first call in 3.3.5 can land on the wrong page; the second one sticks
    InterfaceOptionsFrame_OpenToCategory(main)
    InterfaceOptionsFrame_OpenToCategory(main)
end
