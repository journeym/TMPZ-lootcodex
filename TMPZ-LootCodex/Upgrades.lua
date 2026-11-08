-- Upgrade finder: scores items for your class and spec with simple stat weights and compares
-- them to what you're wearing. Also "can my class use this?", and the best quest reward marker.
-- Toggles: LootCodexDB.upgrades, LootCodexDB.questBest; spec: LootCodexDB.upgradeSpec ("auto" or "CLASS:n").

LootCodex = LootCodex or {}
local LC = LootCodex

-- record fields (see build_data_addon.py)
local NAME, QUALITY, ILVL, REQ, CLASS, SUBCLASS, SLOT, ICON, STATS, TEXT = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

-- Classic-style weights, per point (the % stats per 1%). Rough on purpose: they rank items, they
-- don't simulate. dps only counts on weapons.
local SPECS = {
    WARRIOR = {
        { "Arms / Fury", { str = 1, agi = 0.6, ap = 0.5, crit = 14, hit = 16, sta = 0.3, dps = 3 } },
        { "Arms / Fury", { str = 1, agi = 0.6, ap = 0.5, crit = 14, hit = 16, sta = 0.3, dps = 3 } },
        { "Protection", { sta = 1, def = 1.5, armor = 0.05, dodge = 12, parry = 12, block = 8, bv = 0.4,
            str = 0.5, agi = 0.5, hit = 8, dps = 1 } },
    },
    PALADIN = {
        { "Holy", { int = 1, heal = 0.6, sp = 0.6, mp5 = 2, scrit = 10, spi = 0.25, sta = 0.2 } },
        { "Protection", { sta = 1, def = 1.5, sp = 0.5, armor = 0.05, block = 8, bv = 0.5, str = 0.4,
            agi = 0.4, dodge = 10, parry = 10, int = 0.3 } },
        { "Retribution", { str = 1, agi = 0.6, ap = 0.5, crit = 14, hit = 14, sp = 0.3, int = 0.3, sta = 0.3, dps = 3 } },
    },
    HUNTER = {
        { "Hunter", { agi = 1, rap = 0.5, ap = 0.45, crit = 14, hit = 16, int = 0.4, sta = 0.3, mp5 = 1, dps = 2 } },
    },
    ROGUE = {
        { "Rogue", { agi = 1, str = 0.5, ap = 0.5, crit = 14, hit = 16, sta = 0.3, dps = 3 } },
    },
    PRIEST = {
        { "Discipline / Holy", { heal = 0.6, sp = 0.6, int = 1, spi = 0.8, mp5 = 2, scrit = 8, sta = 0.2 } },
        { "Discipline / Holy", { heal = 0.6, sp = 0.6, int = 1, spi = 0.8, mp5 = 2, scrit = 8, sta = 0.2 } },
        { "Shadow", { sp = 1, sdmg = 1, sshadow = 1, int = 0.4, spi = 0.3, shit = 12, scrit = 8, sta = 0.3 } },
    },
    SHAMAN = {
        { "Elemental", { sp = 1, sdmg = 1, snature = 1, sfire = 0.6, sfrost = 0.4, int = 0.5, scrit = 12,
            shit = 12, mp5 = 1.5, sta = 0.2 } },
        { "Enhancement", { str = 1, agi = 0.7, ap = 0.5, crit = 14, hit = 14, int = 0.3, sta = 0.3, dps = 3 } },
        { "Restoration", { heal = 0.6, sp = 0.6, int = 1, mp5 = 2.2, spi = 0.3, scrit = 8, sta = 0.2 } },
    },
    MAGE = {
        { "Mage", { sp = 1, sdmg = 1, sfire = 0.8, sfrost = 0.8, sarcane = 0.8, int = 0.5, spi = 0.3,
            scrit = 10, shit = 14, sta = 0.2 } },
    },
    WARLOCK = {
        { "Warlock", { sp = 1, sdmg = 1, sshadow = 0.9, sfire = 0.4, int = 0.4, sta = 0.4, spi = 0.2,
            scrit = 8, shit = 14 } },
    },
    DRUID = {
        { "Balance", { sp = 1, sdmg = 1, snature = 0.9, sarcane = 0.6, int = 0.5, spi = 0.3, scrit = 10,
            shit = 12, mp5 = 1 } },
        { "Feral", { agi = 1, str = 1, ap = 0.5, crit = 14, hit = 14, sta = 0.6, armor = 0.05, def = 0.5, dodge = 8 } },
        { "Restoration", { heal = 0.6, sp = 0.6, int = 1, spi = 0.6, mp5 = 2, sta = 0.2 } },
    },
}
-- used before a character has talent points
local DEFAULT_TAB = { WARRIOR = 1, PALADIN = 3, HUNTER = 1, ROGUE = 1, PRIEST = 2, SHAMAN = 2, MAGE = 1,
    WARLOCK = 1, DRUID = 2 }

------------------------------------------------------------------------
-- what a class can use (classic proficiencies)
------------------------------------------------------------------------
local WEAPONS = {
    WARRIOR = "Daggers,Fist Weapons,One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,"
        .. "One-Handed Swords,Two-Handed Swords,Polearms,Staves,Bows,Crossbows,Guns,Thrown",
    PALADIN = "One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,One-Handed Swords,"
        .. "Two-Handed Swords,Polearms",
    HUNTER = "Daggers,Fist Weapons,One-Handed Axes,Two-Handed Axes,One-Handed Swords,Two-Handed Swords,"
        .. "Polearms,Staves,Bows,Crossbows,Guns,Thrown",
    ROGUE = "Daggers,Fist Weapons,One-Handed Maces,One-Handed Swords,Bows,Crossbows,Guns,Thrown",
    PRIEST = "Daggers,One-Handed Maces,Staves,Wands",
    SHAMAN = "Daggers,Fist Weapons,One-Handed Axes,Two-Handed Axes,One-Handed Maces,Two-Handed Maces,Staves",
    MAGE = "Daggers,One-Handed Swords,Staves,Wands",
    WARLOCK = "Daggers,One-Handed Swords,Staves,Wands",
    DRUID = "Daggers,Fist Weapons,One-Handed Maces,Two-Handed Maces,Staves",
}
local ARMOR = {   -- best armor type now, and from level 40
    WARRIOR = { "Mail", "Plate" }, PALADIN = { "Mail", "Plate" }, HUNTER = { "Leather", "Mail" },
    SHAMAN = { "Leather", "Mail" }, ROGUE = { "Leather", "Leather" }, DRUID = { "Leather", "Leather" },
    PRIEST = { "Cloth", "Cloth" }, MAGE = { "Cloth", "Cloth" }, WARLOCK = { "Cloth", "Cloth" },
}
local ARMOR_RANK = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }
local SHIELDS = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELICS = { Librams = "PALADIN", Idols = "DRUID", Totems = "SHAMAN" }

local weaponSet = {}
for class, list in pairs(WEAPONS) do
    weaponSet[class] = {}
    for w in list:gmatch("[^,]+") do weaponSet[class][w] = true end
end

local function PlayerClass()
    local localized, token = UnitClass("player")
    return token, localized
end

-- can the player's class use this item (ignoring level, except for the level-40 armor upgrade)?
function LC.CanUse(r)
    local class, localized = PlayerClass()
    local text = r[TEXT]
    local classes = text:match("Classes: ([^\n]+)")
    if classes and localized and not classes:find(localized, 1, true) then return false end
    local enum = LootCodexData and LootCodexData.enum
    if not enum then return true end
    local cls = enum.class[r[CLASS]]
    local sub = enum.subclass[r[SUBCLASS]]
    if cls == "Weapon" then
        if sub == "Fishing Poles" or sub == "Miscellaneous" then return true end
        return weaponSet[class] and weaponSet[class][sub] or false
    end
    if cls == "Armor" then
        if sub == "Shields" then return SHIELDS[class] or false end
        if RELICS[sub] then return RELICS[sub] == class end
        local rank = ARMOR_RANK[sub]
        if not rank then return true end
        local level = math.max(UnitLevel("player"), r[REQ])
        local best = ARMOR[class] and ARMOR[class][level >= 40 and 2 or 1] or "Plate"
        return rank <= ARMOR_RANK[best]
    end
    return true
end

------------------------------------------------------------------------
-- spec and scoring
------------------------------------------------------------------------
function LC.SpecChoices()
    local out = {}
    for class, list in pairs(SPECS) do
        local seen = {}
        for i, s in ipairs(list) do
            if not seen[s[1]] then              -- two talent trees can share one set of weights
                seen[s[1]] = true
                out[#out + 1] = { class .. ":" .. i, s[1] .. " (" .. class:sub(1, 1) .. class:sub(2):lower() .. ")" }
            end
        end
    end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

local function CurrentSpec()
    local class = PlayerClass()
    local choice = LootCodexDB and LootCodexDB.upgradeSpec
    if choice and choice ~= "auto" then
        local c, i = choice:match("^(%u+):(%d+)$")
        if SPECS[c] and SPECS[c][tonumber(i)] then return c, tonumber(i) end
    end
    if not SPECS[class] then return nil end
    local best, bestPoints = DEFAULT_TAB[class], 0
    for tab = 1, (GetNumTalentTabs and GetNumTalentTabs() or 0) do
        local _, _, points = GetTalentTabInfo(tab)
        if (points or 0) > bestPoints then best, bestPoints = tab, points end
    end
    if not SPECS[class][best] then best = 1 end
    return class, best
end

function LC.SpecName()
    local class, i = CurrentSpec()
    if not class then return "?" end
    local name = SPECS[class][i][1]
    if #SPECS[class] == 1 then return name end
    return name .. " " .. class:sub(1, 1) .. class:sub(2):lower()
end

local WEAPON_SLOTS = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

local function SlotName(r)
    local enum = LootCodexData and LootCodexData.enum
    return enum and r[SLOT] > 0 and enum.slot[r[SLOT]] or nil
end

function LC.Score(r)
    local class, i = CurrentSpec()
    if not class then return 0 end
    local w = SPECS[class][i][2]
    local score = 0
    for code, v in pairs(r[STATS]) do
        if code ~= "dps" or WEAPON_SLOTS[SlotName(r)] then
            score = score + (w[code] or 0) * v
        end
    end
    return score
end

-- inventory slots an item would go in; two entries = pick the weaker one to replace
local INV = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

local equippedCache = {}
local function EquippedScore(slot)
    local link = GetInventoryItemLink("player", slot)
    local id = link and tonumber(link:match("item:(%d+)"))
    if not id then return nil, nil end
    if equippedCache[slot] and equippedCache[slot].id == id then return equippedCache[slot].score, id end
    local r = LC.Item(id)
    local score = r and LC.Score(r) or 0
    equippedCache[slot] = { id = id, score = score }
    return score, id
end

-- difference against what's equipped: number (nil = can't compare, e.g. not gear or unusable)
function LC.UpgradeDelta(id)
    local r = LC.Item(id)
    if not r then return nil end
    local slotName = SlotName(r)
    local slots = slotName and INV[slotName]
    if not slots or slotName == "INVTYPE_BODY" then return nil end
    if not LC.CanUse(r) then return nil end
    local new = LC.Score(r)
    if new <= 0 then return nil end
    local current
    for _, slot in ipairs(slots) do
        local s, eid = EquippedScore(slot)
        if eid == id then return 0 end                      -- already wearing it
        s = s or 0
        if not current or s < current then current = s end
    end
    if slotName == "INVTYPE_2HWEAPON" then                  -- a two-hander replaces both hands
        current = current + (EquippedScore(17) or 0)
    end
    return new - current
end

local UP = "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:2|t"
local DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-2|t"

function LC.UpgradeText(delta)
    if not delta then return nil end
    if delta > 0.05 then return string.format("%s|cff20ff20+%.1f|r", UP, delta) end
    if delta < -0.05 then return string.format("%s|cffff4040%.1f|r", DOWN, delta) end
    return "|cffaaaaaa=|r"
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:SetScript("OnEvent", function()
    wipe(equippedCache)
    if LC.RefreshIfOpen then LC.RefreshIfOpen() end    -- the window's upgrade arrows
end)

-- one tooltip line for item tooltips
function LC.AddUpgradeLine(tip, id)
    if not (LootCodexDB and LootCodexDB.upgrades) or not LC.Item(id) then return end
    local r = LC.Item(id)
    local delta = LC.UpgradeDelta(id)
    if delta == nil then
        if SlotName(r) and INV[SlotName(r)] and not LC.CanUse(r) then
            tip:AddLine("Your class can't use this", 0.6, 0.6, 0.6)
        end
        return
    end
    local lvl = LC.EffReq and LC.EffReq(r) or r[REQ]
    local note = lvl > UnitLevel("player") and ("  |cff888888(around level " .. lvl .. ")|r") or ""
    tip:AddDoubleLine("Upgrade for " .. LC.SpecName() .. ":", LC.UpgradeText(delta) .. note, 0.2, 0.8, 1, 1, 1, 1)
end

------------------------------------------------------------------------
-- best quest reward: marks the best upgrade among the choices, or the best sell price if none
------------------------------------------------------------------------
local marks = {}

local function Mark(button, kind)
    local m = marks[button]
    if not m then
        m = button:CreateTexture(nil, "OVERLAY")
        m:SetSize(18, 18)
        m:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
        marks[button] = m
    end
    if kind == "up" then
        m:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
    else
        m:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    end
    m:Show()
end

local function MarkQuestRewards()
    for _, m in pairs(marks) do m:Hide() end
    if not (LootCodexDB and LootCodexDB.questBest) then return end
    local bestUp, bestUpDelta, bestSell, bestSellPrice
    for i = 1, 10 do
        local b = _G["QuestInfoItem" .. i]
        if b and b:IsShown() and b.type == "choice" then
            local link = GetQuestItemLink("choice", b:GetID())
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                local delta = LC.UpgradeDelta(id)
                if delta and delta > 0.05 and (not bestUpDelta or delta > bestUpDelta) then
                    bestUp, bestUpDelta = b, delta
                end
                local price = select(11, GetItemInfo(link)) or 0
                if price > 0 and (not bestSellPrice or price > bestSellPrice) then bestSell, bestSellPrice = b, price end
            end
        end
    end
    if bestUp then
        Mark(bestUp, "up")
    elseif bestSell then
        Mark(bestSell, "sell")
    end
end

if QuestInfo_Display then
    hooksecurefunc("QuestInfo_Display", function() MarkQuestRewards() end)
end
local q = CreateFrame("Frame")
q:RegisterEvent("QUEST_COMPLETE")
q:RegisterEvent("QUEST_DETAIL")
q:SetScript("OnEvent", function() MarkQuestRewards() end)
