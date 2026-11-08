-- Loot Codex: search and filter every item on the server.
-- Item data lives in the LootCodex_Data addon (LoadOnDemand), loaded the first
-- time the window opens. Sources come from Sources.lua.

LootCodex = LootCodex or {}
local LC = LootCodex

local ROWS, ROW_H = 17, 30
local LIST_W = 584
local F_CUSTOM, F_HIDDEN, F_REBORN = 1, 2, 4   -- F_REBORN: likely added by Epoch Reborn

-- record fields (see build_data_addon.py)
local NAME, QUALITY, ILVL, REQ, CLASS, SUBCLASS, SLOT, ICON, STATS, TEXT, FLAGS = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11

-- top tabs; "classes" are item class names, "other" takes whatever no other tab claims
local TABS = {
    { key = "all", label = "All Items" },
    { key = "gear", label = "Equipment", classes = { "Armor", "Weapon", "Projectile", "Quiver" } },
    { key = "cons", label = "Consumables", classes = { "Consumable" } },
    { key = "prof", label = "Professions" },
    { key = "dung", label = "Dungeons" },
    { key = "sets", label = "Sets", classes = { "Armor", "Weapon" } },
    { key = "quest", label = "Quest Items", classes = { "Quest", "Key" } },
    { key = "other", label = "Other", other = true },
    { key = "wish", label = "Wishlist" },
    { key = "recent", label = "Recent" },
}

-- which filter controls each tab shows, top to bottom
local LAYOUT = {
    all = { "search", "category", "type", "slot", "quality", "stat", "source", "sort", "level" },
    gear = { "search", "type", "slot", "usable", "quality", "stat", "source", "sort", "level" },
    dung = { "dungeon", "boss", "search", "usable", "quality", "sort" },
    sets = { "setback", "search", "type", "usable", "level" },
    wish = { "search", "wishmap", "sort" },
    recent = { "search", "recentclear" },
    cons = { "search", "type", "quality", "source", "sort", "level" },
    prof = { "professions", "view", "search", "sort" },
    quest = { "search", "quality", "source", "sort", "level" },
    other = { "search", "category", "type", "quality", "source", "sort", "level" },
}

local PROFESSIONS = {
    { "Alchemy", "Trade_Alchemy" }, { "Blacksmithing", "Trade_BlackSmithing" },
    { "Enchanting", "Trade_Engraving" }, { "Engineering", "Trade_Engineering" },
    { "Leatherworking", "INV_Misc_ArmorKit_17" }, { "Tailoring", "Trade_Tailoring" },
    { "Mining", "Trade_Mining" }, { "Herbalism", "Trade_Herbalism" }, { "Skinning", "INV_Misc_Pelt_Wolf_01" },
    { "Cooking", "INV_Misc_Food_15" }, { "First Aid", "Spell_Holy_SealOfSacrifice" }, { "Fishing", "Trade_Fishing" },
}
-- what gathering professions bring in, by Trade Goods type
local GATHERED = { Mining = "Metal & Stone", Herbalism = "Herb", Skinning = "Leather" }
local VIEWS = { { "crafted", "Crafted items" }, { "recipes", "Recipes" }, { "materials", "Materials" } }

local SLOTS = {
    { "Head", "INVTYPE_HEAD" }, { "Neck", "INVTYPE_NECK" }, { "Shoulder", "INVTYPE_SHOULDER" },
    { "Back", "INVTYPE_CLOAK" }, { "Chest", "INVTYPE_CHEST", "INVTYPE_ROBE" }, { "Shirt", "INVTYPE_BODY" },
    { "Tabard", "INVTYPE_TABARD" }, { "Wrist", "INVTYPE_WRIST" }, { "Hands", "INVTYPE_HAND" },
    { "Waist", "INVTYPE_WAIST" }, { "Legs", "INVTYPE_LEGS" }, { "Feet", "INVTYPE_FEET" },
    { "Finger", "INVTYPE_FINGER" }, { "Trinket", "INVTYPE_TRINKET" },
    { "One-Hand", "INVTYPE_WEAPON" }, { "Main Hand", "INVTYPE_WEAPONMAINHAND" },
    { "Off Hand weapon", "INVTYPE_WEAPONOFFHAND" }, { "Two-Hand", "INVTYPE_2HWEAPON" },
    { "Shield", "INVTYPE_SHIELD" }, { "Held in Off-hand", "INVTYPE_HOLDABLE" },
    { "Ranged", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" }, { "Relic", "INVTYPE_RELIC" },
    { "Bag", "INVTYPE_BAG" }, { "Ammo", "INVTYPE_AMMO" },
}

local STAT_LIST = {
    { "sp", "Spell Power" }, { "heal", "Healing" }, { "sdmg", "Spell Damage" }, { "mp5", "Mana per 5" },
    { "int", "Intellect" }, { "spi", "Spirit" }, { "sta", "Stamina" }, { "str", "Strength" },
    { "agi", "Agility" }, { "ap", "Attack Power" }, { "rap", "Ranged AP" }, { "dps", "Weapon DPS" },
    { "crit", "Crit %" }, { "scrit", "Spell Crit %" }, { "hit", "Hit %" }, { "shit", "Spell Hit %" },
    { "def", "Defense" }, { "dodge", "Dodge %" }, { "parry", "Parry %" }, { "block", "Block %" },
    { "bv", "Block Value" }, { "armor", "Armor" }, { "hp5", "Health per 5" }, { "spen", "Spell Pen." },
    { "sshadow", "Shadow Dmg" }, { "sfire", "Fire Dmg" }, { "sfrost", "Frost Dmg" }, { "sarcane", "Arcane Dmg" },
    { "snature", "Nature Dmg" }, { "sholy", "Holy Dmg" }, { "rfire", "Fire Resist" }, { "rnature", "Nature Resist" },
    { "rfrost", "Frost Resist" }, { "rshadow", "Shadow Resist" }, { "rarcane", "Arcane Resist" },
}
local STAT_LABEL = {}
for _, s in ipairs(STAT_LIST) do STAT_LABEL[s[1]] = s[2] end
-- shown in the row summary, in this order
local SUMMARY = { "sp", "heal", "sdmg", "mp5", "int", "spi", "sta", "str", "agi", "ap", "crit", "scrit", "hit", "shit", "def", "dps" }
local SHORT = { sp = "SP", heal = "Heal", sdmg = "SDmg", mp5 = "Mp5", int = "Int", spi = "Spi", sta = "Sta",
    str = "Str", agi = "Agi", ap = "AP", crit = "Crit%", scrit = "SCrit%", hit = "Hit%", shit = "SHit%",
    def = "Def", dps = "DPS" }

local QUALITIES = { "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact" }

local SORTS = {
    { "ilvl", "Item level" }, { "req", "Required level" }, { "name", "Name" }, { "quality", "Quality" },
    { "stat", "Chosen stat" }, { "upgrade", "Upgrade for me" },
}
local DUNG_SORTS = { { "boss", "Boss" }, { "chance", "Drop chance" }, { "ilvl", "Item level" },
    { "upgrade", "Upgrade for me" } }
local PROF_SORTS = { { "skill", "Skill" }, { "name", "Name" }, { "quality", "Quality" }, { "ilvl", "Item level" } }

local SOURCES = {
    { "drop", "Drops from mobs" }, { "boss", "Dungeon & world bosses" }, { "craft", "Crafted" },
    { "quest", "Quest rewards" }, { "vendor", "Sold by vendors" }, { "rep", "Reputation rewards" },
    { "event", "World events" }, { "pvp", "PvP rewards" }, { "none", "No known source" },
}

local DEFAULTS = { tooltip = true, record = true, share = true, tab = "gear", prof = "Blacksmithing",
    unitTooltip = true, unitHideGrey = true, unitShift = false, unitLines = 6,
    mapPins = true, upgrades = true, upgradeSpec = "auto", questBest = true, wishAlerts = true,
    wishMobAlerts = true, wishMobSound = true,
    trackRecent = true, learnItems = true, sharedNotify = true, autoUpdateCheck = false,
    loginMessage = true, activityMessages = true, autoDungeon = true }
local function TabDefaults(key)
    if key == "prof" then return { text = "", sort = "skill", view = "crafted" } end
    if key == "dung" then return { text = "", sort = "boss" } end
    return { text = "", sort = "ilvl" }
end

local D, enum            -- LootCodexData.items / .enum once loaded
local allIds, lname, ltext = {}, {}, {}
local results = {}
local filters, tab       -- the current tab's filter table and its TABS entry
local frame, rows, scroll, countText, helpText

-- built from the data on first open
local tabClasses = {}    -- tab key -> set of class indexes
local profs = {}         -- professions that have anything, in PROFESSIONS order
local profIcon = {}
local crafted = {}       -- prof -> { item = skill rank to sort by }
local craftInfo = {}     -- prof -> { item = {profession, learn, recipe, reagents, yellow, grey} }
local recipes = {}       -- prof -> { item = skill rank or 0 }
local materials = {}     -- prof -> { item = number of recipes using it }
local reagentsOf = {}    -- prof -> { item = "id:n,..." }
local dungeons = {}      -- instance -> { boss -> { item = chance } }
local fromPfQuest = {}   -- instances filled from pfQuest because AtlasLoot has none
local CLASSIC_EXTRA = { ["Molten Core"] = true, ["Blackwing Lair"] = true, ["Onyxia's Lair"] = true,
    ["Zul'Gurub"] = true, ["Ruins of Ahn'Qiraj"] = true, ["Ahn'Qiraj Temple"] = true, ["Naxxramas"] = true,
    ["Dire Maul"] = true }
local allDungeons = {}   -- dungeons plus bosses learned from kills (Reborn's new ones); see Dungeons()
local learnedBoss = {}   -- instance -> { boss = npc } for the ones learned from kills
local learnedDirty = true
local setList = {}       -- { id, name, pieces = {ids}, bonuses, minReq, maxReq, sub, quality, icon }
local tabExtra = {}      -- per-row extra for the current tab: dungeons { item = {boss, chance} }

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffTMPZ-LootCodex:|r " .. msg) end

local function HasFlag(r, f) return math.floor(r[FLAGS] / f) % 2 == 1 end

-- the level an item is really for: some classic gear has no level requirement but is endgame
-- quality (Cap of the Scarlet Savant, item level 63; Epoch's Malistar's Mallet says level 1 at item
-- level 67), so gear with no real requirement counts as item level - 5
local function EffReq(r)
    if r[REQ] > 1 or r[SLOT] == 0 or r[ILVL] <= 10 then return r[REQ] end
    return r[ILVL] - 5
end
LC.EffReq = EffReq

local function ItemName(id)
    local r = D[id]
    return r and r[NAME] or GetItemInfo(id) or ("item " .. id)
end

------------------------------------------------------------------------
-- data
------------------------------------------------------------------------
local function IndexOf(list, name)
    for i, v in ipairs(list) do if v == name then return i end end
end

local function BuildIndexes()
    local claimed = {}
    for _, t in ipairs(TABS) do
        if t.classes then
            local set = {}
            for _, name in ipairs(t.classes) do
                local i = IndexOf(enum.class, name)
                if i then set[i] = true; claimed[i] = true end
            end
            tabClasses[t.key] = set
        end
    end
    local other = {}
    local recipeClass = IndexOf(enum.class, "Recipe")
    for i in ipairs(enum.class) do
        if not claimed[i] and i ~= recipeClass then other[i] = true end
    end
    tabClasses.other = other

    for _, p in ipairs(PROFESSIONS) do
        crafted[p[1]], recipes[p[1]], materials[p[1]], reagentsOf[p[1]], craftInfo[p[1]] = {}, {}, {}, {}, {}
        profIcon[p[1]] = p[2]
    end
    for item, list in pairs(LootCodexSources and LootCodexSources.craft or {}) do
        for _, c in ipairs(list) do
            local p = c[1]
            local rank = c[2] > 0 and c[2] or c[5] or 0
            if crafted[p] and D[item] and (not crafted[p][item] or rank < crafted[p][item]) then
                crafted[p][item] = rank
                craftInfo[p][item] = c
                reagentsOf[p][item] = c[4]
                for rid in c[4]:gmatch("(%d+):%d+") do
                    rid = tonumber(rid)
                    if D[rid] then materials[p][rid] = (materials[p][rid] or 0) + 1 end
                end
            end
        end
    end
    local tradeGoods = IndexOf(enum.class, "Trade Goods")
    for id, r in pairs(D) do
        if r[CLASS] == recipeClass then
            -- the "Requires Tailoring (270)" line wins: Epoch's own recipes report type Cooking
            local p, rank = r[TEXT]:match("Requires ([%a ]+) %((%d+)%)")
            if not recipes[p] then
                p, rank = r[SUBCLASS] > 0 and enum.subclass[r[SUBCLASS]], 0
            end
            if recipes[p] then recipes[p][id] = tonumber(rank) or 0 end
        end
        if r[CLASS] == tradeGoods and r[SUBCLASS] > 0 then
            for p, sub in pairs(GATHERED) do
                if enum.subclass[r[SUBCLASS]] == sub and not materials[p][id] then materials[p][id] = 0 end
            end
        end
    end
    for _, p in ipairs(PROFESSIONS) do
        if next(crafted[p[1]]) or next(recipes[p[1]]) or next(materials[p[1]]) then profs[#profs + 1] = p[1] end
    end

    -- Dungeons tab: AtlasLoot's instance bosses, and world bosses under one heading
    for item, list in pairs(LootCodexSources and LootCodexSources.boss or {}) do
        if D[item] then
            for _, b in ipairs(list) do
                local who, where, chance, kind = b[1], b[2], b[3], b[4]
                if kind == 1 or kind == 2 then
                    local inst = kind == 2 and "World Bosses" or where
                    local boss = kind == 2 and where or (who ~= "" and who or "Various")
                    dungeons[inst] = dungeons[inst] or {}
                    dungeons[inst][boss] = dungeons[inst][boss] or {}
                    dungeons[inst][boss][item] = chance
                end
            end
        end
    end

    -- classic dungeons and raids Epoch's AtlasLoot has no tables for: filled from pfQuest's classic
    -- drop data and the dungeon each mob lives in (TrinityCore spawns). Labelled "classic data".
    if pfDB and pfDB.units and pfDB.units.data and LC.UnitDropIndex and LootCodexSources.unitzone then
        local drops = LC.UnitDropIndex()
        local names = pfDB.units.loc or pfDB.units.enUS or {}
        local fromAtlas, ranked = {}, {}
        for inst in pairs(dungeons) do fromAtlas[inst] = true end
        for npc, inst in pairs(LootCodexSources.unitzone) do
            local u = pfDB.units.data[npc]
            if u and u.rnk == "3" then ranked[inst] = true end
        end
        for npc, inst in pairs(LootCodexSources.unitzone) do
            if CLASSIC_EXTRA[inst] and not fromAtlas[inst] then
                -- a boss is what pfQuest ranks Boss; in a dungeon where it ranks none (Dire Maul), a mob that
                -- drops blue-or-better gear at 5% or more, or from a shared boss loot table (chance 0)
                local u = pfDB.units.data[npc]
                local boss = u and u.rnk == "3"
                for item, chance in pairs(ranked[inst] and {} or drops[npc] or {}) do
                    if not boss and (chance >= 5 or chance == 0) and D[item] and D[item][QUALITY] >= 3 and D[item][SLOT] > 0 then
                        boss = true
                    end
                end
                local who = boss and names[npc] or "Trash Mobs"
                for item, chance in pairs(drops[npc] or {}) do
                    if D[item] then
                        fromPfQuest[inst] = true
                        dungeons[inst] = dungeons[inst] or {}
                        dungeons[inst][who] = dungeons[inst][who] or {}
                        if (dungeons[inst][who][item] or -1) < chance then dungeons[inst][who][item] = chance end
                    end
                end
            end
        end
    end

    -- Sets tab
    for setId, st in pairs(LootCodexSources and LootCodexSources.sets or {}) do
        local pieces, subs = {}, {}
        local entry = { id = setId, name = st[1], bonuses = st[3], minReq = 99, maxReq = 0, quality = 0 }
        for pid in st[2]:gmatch("%d+") do
            pid = tonumber(pid)
            local r = D[pid]
            if r then
                pieces[#pieces + 1] = pid
                entry.minReq = math.min(entry.minReq, r[REQ])
                entry.maxReq = math.max(entry.maxReq, r[REQ])
                entry.quality = math.max(entry.quality, r[QUALITY])
                entry.icon = entry.icon or r[ICON]
                entry.hidden = (entry.hidden == nil or entry.hidden) and HasFlag(r, F_HIDDEN)
                subs[r[SUBCLASS]] = (subs[r[SUBCLASS]] or 0) + 1
            end
        end
        if #pieces > 0 then
            local best, n = 0, 0
            for sub, c in pairs(subs) do if c > n then best, n = sub, c end end
            entry.sub, entry.pieces = best, pieces
            entry.lname = entry.name:lower()
            setList[#setList + 1] = entry
        end
    end
    table.sort(setList, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.minReq < b.minReq
    end)
end

local function EnsureData()
    if D then return true end
    if not LootCodexData then
        local ok, reason = LoadAddOn("TMPZ-LootCodex_Data")
        if not ok then
            Print("couldn't load the TMPZ-LootCodex_Data addon (" .. tostring(reason) ..
                "). Make sure it is in your AddOns folder and enabled.")
            return false
        end
    end
    D, enum = LootCodexData.items, LootCodexData.enum
    for id, r in pairs(D) do
        allIds[#allIds + 1] = id
        lname[id] = r[NAME]:lower()
    end
    table.sort(allIds)
    if LC.MergeLearnedItems then LC.MergeLearnedItems() end
    BuildIndexes()
    return true
end

LC.EnsureData = EnsureData

-- an item learned in game (Learn.lua): browsable straight away
function LC.AddLearnedItem(id, rec)
    if not D or D[id] then return end
    D[id] = rec
    allIds[#allIds + 1] = id
    lname[id] = rec[NAME]:lower()
end

-- an item the update check found changed on the server: replaces what the database had
function LC.ReplaceItem(id, rec)
    if not D then return end
    if not D[id] then allIds[#allIds + 1] = id end
    D[id] = rec
    lname[id] = rec[NAME]:lower()
    ltext[id] = nil
    LC.ForgetSources(id)
end

function LC.AllItemIds() return allIds end
function LC.IsCustomItem(r) return HasFlag(r, F_CUSTOM) end
function LC.IsRebornItem(r) return HasFlag(r, F_REBORN) end

-- an item's record from LootCodex_Data (nil until it's loaded) and whether it's hidden by default
function LC.Item(id) return D and D[id] end
function LC.IsHiddenItem(r) return HasFlag(r, F_HIDDEN) end

local function ItemLink(id)
    local _, link = GetItemInfo(id)
    if link then return link end
    local r = D[id]
    local c = ITEM_QUALITY_COLORS[r[QUALITY]]
    return (c and c.hex or "|cffffffff") .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. r[NAME] .. "]|h|r"
end

local function SetById(setId)
    for _, st in ipairs(setList) do if st.id == setId then return st end end
end

-- instance map names (GetInstanceInfo) and zone names whose Dungeons tab entry is spelled differently
local DUNGEON_ALIAS = {
    ["Stormwind Stockade"] = "The Stockade", ["Deadmines"] = "The Deadmines",
    ["Scarlet Monastery"] = "Scarlet Monestery", ["Blackrock Spire"] = "Lower Blackrock Spire",
    ["The Temple of Atal'Hakkar"] = "Sunken Temple", ["Tol Barad"] = "Baradin Hold",
    ["Ahn'Qiraj"] = "Ahn'Qiraj Temple",
}

local function Simple(s)
    s = s:lower():gsub("^the ", "")
    s = s:gsub("[^%a]", "")
    return s
end

-- the Dungeons tab's name for an instance or zone name, or nil
local function DungeonNamed(name, list)
    if not name or name == "" then return end
    if list[name] then return name end
    local a = DUNGEON_ALIAS[name]
    if a and list[a] then return a end
    local s = Simple(name)
    for inst in pairs(list) do if Simple(inst) == s then return inst end end
end

-- the dungeon lists plus bosses learned from kills that no list has (Reborn's additions); rebuilt
-- when a kill is recorded or shared. A learned boss whose blue drops are all listed already is a
-- known boss under another name, and stays out.
local function Dungeons()
    if not learnedDirty then return allDungeons end
    learnedDirty = false
    wipe(allDungeons); wipe(learnedBoss)
    for inst, bosses in pairs(dungeons) do allDungeons[inst] = bosses end
    for _, b in ipairs(LC.LearnedBosses and LC.LearnedBosses() or {}) do
        local inst = DungeonNamed(b.inst, dungeons) or (b.inInstance and b.inst)
        local known = dungeons[inst]
        local new = inst and not (known and known[b.name])
        if new and known and not b.marked then
            local listed, blues = {}, 0
            for _, items in pairs(known) do for id in pairs(items) do listed[id] = true end end
            new = false
            for id in pairs(b.items) do
                local r = D[id]
                if r and r[QUALITY] >= 3 and r[SLOT] > 0 then
                    blues = blues + 1
                    if not listed[id] then new = true end
                end
            end
            if blues == 0 then new = true end
        end
        if new then
            if allDungeons[inst] == known then          -- copy first: the built list stays as it is
                local copy = {}
                for k, v in pairs(known or {}) do copy[k] = v end
                allDungeons[inst] = copy
            end
            -- green or better only: potions, cloth and grey junk drop from every mob, and boss lists
            -- leave them out (the creature tooltip still shows everything)
            local items = {}
            for id, n in pairs(b.items) do
                local r = D[id]
                if r and r[QUALITY] >= 2 then items[id] = math.floor(n / b.kills * 1000 + 0.5) / 10 end
            end
            allDungeons[inst][b.name] = items
            learnedBoss[inst] = learnedBoss[inst] or {}
            learnedBoss[inst][b.name] = b
        end
    end
    return allDungeons
end

function LC.ForgetLearnedBosses() learnedDirty = true end

-- the Dungeons tab entry for the instance you are in, and the instance's own name
local function CurrentDungeon()
    local name, kind = GetInstanceInfo()
    if kind ~= "party" and kind ~= "raid" then return end
    local list = Dungeons()
    return DungeonNamed(name, list) or DungeonNamed(GetRealZoneText(), list), name
end

-- the ids a special tab shows (nil = filter the whole database by class)
local function TabIds()
    wipe(tabExtra)
    if tab.key == "dung" then
        local set = {}
        for inst, bosses in pairs(Dungeons()) do
            if not filters.dungeon or filters.dungeon == inst then
                for boss, items in pairs(bosses) do
                    if not filters.boss or filters.boss == boss then
                        for item, chance in pairs(items) do
                            set[item] = true
                            local old = tabExtra[item]
                            if not old or chance > old[2] then tabExtra[item] = { boss, chance, inst } end
                        end
                    end
                end
            end
        end
        return set
    elseif tab.key == "sets" and filters.set then
        local st, set = SetById(filters.set), {}
        for _, pid in ipairs(st and st.pieces or {}) do set[pid] = true end
        return set
    elseif tab.key == "wish" then
        local set = {}
        for id in pairs(LC.Wishlist()) do if D[id] then set[id] = true end end
        return set
    elseif tab.key == "recent" then
        local set = {}
        for i, id in ipairs(LC.Recent()) do
            if D[id] then set[id] = true; tabExtra[id] = i end
        end
        return set
    end
end

-- the profession view currently shown: item -> skill rank (or use count for materials)
local function ProfSet()
    local p = LootCodexDB.prof
    local view = filters.view or "crafted"
    if view == "recipes" then return recipes[p] or {} end
    if view == "materials" then return materials[p] or {} end
    -- crafted: sort by the real learn level where a trainer has told us, else the client's yellow level
    local out = {}
    for item, rank in pairs(crafted[p] or {}) do
        local c = craftInfo[p][item]
        out[item] = (c and c[2] > 0 and c[2]) or (LC.TrainerReq and LC.TrainerReq(p, item)) or rank
    end
    return out
end

------------------------------------------------------------------------
-- filtering
------------------------------------------------------------------------
local slotSet, profSet, idSet

local function Matches(id, r, words)
    local f = filters
    -- wishlist and recent show exactly what you put there, hidden or not
    local listed = tab.key == "wish" or tab.key == "recent"
    if not listed and not LootCodexDB.showHidden and HasFlag(r, F_HIDDEN) then return false end
    if not listed and LootCodexDB.customOnly and not HasFlag(r, F_CUSTOM) then return false end
    if not listed and LootCodexDB.rebornOnly and not HasFlag(r, F_REBORN) then return false end
    if profSet then
        if not profSet[id] then return false end
    elseif idSet then
        if not idSet[id] then return false end
    elseif tabClasses[tab.key] and not tabClasses[tab.key][r[CLASS]] then
        return false
    end
    if f.usable and LC.CanUse and not LC.CanUse(r) then return false end
    if f.class and r[CLASS] ~= f.class then return false end
    if f.subclass and r[SUBCLASS] ~= f.subclass then return false end
    if slotSet and not slotSet[r[SLOT]] then return false end
    if f.quality and r[QUALITY] < f.quality then return false end
    if f.minReq and EffReq(r) < f.minReq then return false end
    if f.maxReq and EffReq(r) > f.maxReq then return false end
    if f.stat and not (r[STATS][f.stat] and r[STATS][f.stat] > 0) then return false end
    if words then
        local hay = lname[id]
        if f.searchText then
            local t = ltext[id]
            if not t then t = r[TEXT]:lower(); ltext[id] = t end
            hay = hay .. "\n" .. t
        end
        for _, w in ipairs(words) do
            if not hay:find(w, 1, true) then return false end
        end
    end
    if f.source and not LC.HasSourceKind(id, f.source) then return false end
    if f.upgradesOnly and LootCodexDB.upgrades then
        local d = LC.UpgradeDelta(id)
        if not d or d <= 0.05 then return false end
    end
    return true
end

-- Sets tab, before a set is picked: the rows are sets
local function SetMatches(st, words)
    local f = filters
    if not LootCodexDB.showHidden and st.hidden then return false end
    if f.subclass and st.sub ~= f.subclass then return false end
    if f.minReq and st.maxReq < f.minReq then return false end
    if f.maxReq and st.minReq > f.maxReq then return false end
    if f.usable and LC.CanUse and not LC.CanUse(D[st.pieces[1]]) then return false end
    if words then
        for _, w in ipairs(words) do
            if not st.lname:find(w, 1, true) then return false end
        end
    end
    return true
end

local function Sorter()
    local by, stat = filters.sort, filters.stat
    if by == "stat" and not stat then by = "ilvl" end
    local skills = profSet
    if by == "skill" and filters.view == "materials" then by = "uses" end
    if by == "upgrade" and not LootCodexDB.upgrades then by = "ilvl" end
    local delta = {}
    if by == "upgrade" then
        for _, id in ipairs(results) do delta[id] = LC.UpgradeDelta(id) or -9999 end
    end
    return function(a, b)
        local ra, rb = D[a], D[b]
        if by == "upgrade" then
            if delta[a] ~= delta[b] then return delta[a] > delta[b] end
        elseif by == "boss" and tabExtra[a] and tabExtra[b] then
            if tabExtra[a][1] ~= tabExtra[b][1] then return tabExtra[a][1] < tabExtra[b][1] end
            if tabExtra[a][2] ~= tabExtra[b][2] then return tabExtra[a][2] > tabExtra[b][2] end
        elseif by == "chance" and tabExtra[a] and tabExtra[b] then
            if tabExtra[a][2] ~= tabExtra[b][2] then return tabExtra[a][2] > tabExtra[b][2] end
        elseif by == "name" then
            if ra[NAME] ~= rb[NAME] then return ra[NAME] < rb[NAME] end
        elseif by == "req" then
            if ra[REQ] ~= rb[REQ] then return ra[REQ] > rb[REQ] end
        elseif by == "quality" then
            if ra[QUALITY] ~= rb[QUALITY] then return ra[QUALITY] > rb[QUALITY] end
        elseif by == "stat" then
            local sa, sb = ra[STATS][stat] or 0, rb[STATS][stat] or 0
            if sa ~= sb then return sa > sb end
        elseif by == "skill" and skills then
            if skills[a] ~= skills[b] then return skills[a] < skills[b] end
            if ra[NAME] ~= rb[NAME] then return ra[NAME] < rb[NAME] end
        elseif by == "uses" and skills then
            if skills[a] ~= skills[b] then return skills[a] > skills[b] end
        end
        if ra[ILVL] ~= rb[ILVL] then return ra[ILVL] > rb[ILVL] end
        return a < b
    end
end

local UpdateList

local function Refresh()
    if not D or not frame then return end
    slotSet = nil
    if filters.slot and SLOTS[filters.slot] then
        slotSet = {}
        for i = 2, #SLOTS[filters.slot] do
            local n = IndexOf(enum.slot, SLOTS[filters.slot][i])
            if n then slotSet[n] = true end
        end
    end
    profSet = tab.key == "prof" and ProfSet() or nil
    idSet = TabIds()
    local words
    local text = (filters.text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" then
        words = {}
        for w in text:gmatch("%S+") do words[#words + 1] = w end
    end
    wipe(results)
    if tab.key == "sets" and not filters.set then
        -- set rows are stored as negative indexes into setList
        for i, st in ipairs(setList) do
            if SetMatches(st, words) then results[#results + 1] = -i end
        end
    else
        for id in pairs(idSet or {}) do
            if D[id] and Matches(id, D[id], words) then results[#results + 1] = id end
        end
        if not idSet then
            for _, id in ipairs(allIds) do
                if Matches(id, D[id], words) then results[#results + 1] = id end
            end
        end
        if tab.key == "recent" then
            table.sort(results, function(a, b) return tabExtra[a] < tabExtra[b] end)
        else
            table.sort(results, Sorter())
        end
    end
    FauxScrollFrame_SetOffset(scroll, 0)
    _G["LootCodexScrollScrollBar"]:SetValue(0)
    UpdateList()
end
LC.Refresh = Refresh

-- after something changes that the rows show (wishlist, gear, recent): re-list only where it matters
function LC.RefreshIfOpen()
    if not frame or not frame:IsShown() then return end
    if tab.key == "wish" or tab.key == "recent" then Refresh() else UpdateList() end
end

------------------------------------------------------------------------
-- picker: a button that opens a column list of choices
------------------------------------------------------------------------
local menu, menuCatcher, menuButtons = nil, nil, {}

local function HideMenu()
    if menu then menu:Hide(); menuCatcher:Hide() end
end

local function ShowMenu(owner, options, onPick)
    if not menu then
        menuCatcher = CreateFrame("Button", nil, UIParent)
        menuCatcher:SetAllPoints(UIParent)
        menuCatcher:SetFrameStrata("FULLSCREEN")
        menuCatcher:SetScript("OnClick", HideMenu)
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        menu:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        menu:EnableMouse(true)
    end
    local PER_COL, W, H = 18, 150, 16
    for i, opt in ipairs(options) do
        local b = menuButtons[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetSize(W, H)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            b:GetHighlightTexture():SetBlendMode("ADD")
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetPoint("RIGHT", -4, 0)
            b.text:SetJustifyH("LEFT")
            menuButtons[i] = b
        end
        local col, row = math.floor((i - 1) / PER_COL), (i - 1) % PER_COL
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 8 + col * W, -8 - row * H)
        b.text:SetText(opt[2])
        b:SetScript("OnClick", function() HideMenu(); onPick(opt[1], opt[2]) end)
        b:Show()
    end
    for i = #options + 1, #menuButtons do menuButtons[i]:Hide() end
    local cols = math.ceil(#options / PER_COL)
    menu:SetSize(16 + cols * W, 16 + math.min(#options, PER_COL) * H)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:SetClampedToScreen(true)
    menuCatcher:Show()
    menu:Show()
end

LC.ShowMenu = ShowMenu

------------------------------------------------------------------------
-- options for the pickers
------------------------------------------------------------------------
local function ClassOptions()
    local opts = {}
    local allowed = tabClasses[tab.key]
    for i, name in ipairs(enum.class) do
        if not allowed or allowed[i] then opts[#opts + 1] = { i, name } end
    end
    table.sort(opts, function(a, b) return a[2] < b[2] end)
    return opts
end

local function SubclassOptions()
    local seen, opts = {}, {}
    local allowed = tabClasses[tab.key]
    for _, id in ipairs(allIds) do
        local r = D[id]
        if r[SUBCLASS] > 0 and not seen[r[SUBCLASS]] and (not allowed or allowed[r[CLASS]])
            and (not filters.class or r[CLASS] == filters.class) then
            seen[r[SUBCLASS]] = true
            opts[#opts + 1] = { r[SUBCLASS], enum.subclass[r[SUBCLASS]] }
        end
    end
    table.sort(opts, function(a, b) return a[2] < b[2] end)
    return opts
end

local function ListOptions(list)
    return function()
        local opts = {}
        for i, s in ipairs(list) do opts[#opts + 1] = { s[2] and s[1] or i, s[2] or s[1] } end
        return opts
    end
end

local function SlotOptions()
    local opts = {}
    for i, s in ipairs(SLOTS) do opts[#opts + 1] = { i, s[1] } end
    return opts
end

local function QualityOptions()
    local opts = {}
    for q = 0, #QUALITIES - 1 do
        local c = ITEM_QUALITY_COLORS[q]
        opts[#opts + 1] = { q, (c and c.hex or "") .. QUALITIES[q + 1] .. "|r or better" }
    end
    return opts
end

local function ViewOptions()
    local p = LootCodexDB.prof
    local opts = {}
    if next(crafted[p] or {}) then opts[#opts + 1] = { "crafted", "Crafted items" } end
    if next(recipes[p] or {}) then opts[#opts + 1] = { "recipes", "Recipes" } end
    if next(materials[p] or {}) then
        opts[#opts + 1] = { "materials", GATHERED[p] and not next(crafted[p]) and "Gathered" or "Materials" }
    end
    return opts
end

local function DungeonOptions()
    local opts = {}
    for inst in pairs(Dungeons()) do
        local note = fromPfQuest[inst] and "classic data" or not dungeons[inst] and "from kills"
        opts[#opts + 1] = { inst, note and (inst .. "  |cff888888(" .. note .. ")|r") or inst }
    end
    table.sort(opts, function(a, b)
        if (a[1] == "World Bosses") ~= (b[1] == "World Bosses") then return b[1] == "World Bosses" end
        return a[1] < b[1]
    end)
    return opts
end

local function BossOptions()
    local opts = {}
    local learned = filters.dungeon and learnedBoss[filters.dungeon] or {}
    for boss in pairs(filters.dungeon and Dungeons()[filters.dungeon] or {}) do
        local b = learned[boss]
        local label = boss
        if b then
            local what = (b.new and "Reborn " or "") .. (b.rare and "rare" or "")
            label = boss .. "  |cff888888(" .. (what ~= "" and (what:gsub(" $", "") .. ", ") or "") .. "from kills)|r"
        end
        opts[#opts + 1] = { boss, label }
    end
    table.sort(opts, function(a, b) return a[1] < b[1] end)
    return opts
end

local function SortList()
    if tab.key == "prof" then return PROF_SORTS end
    if tab.key == "dung" then return DUNG_SORTS end
    return SORTS
end

local function LabelOf(list, v)
    for _, s in ipairs(list) do if s[1] == v then return s[2] end end
end

local function PickerText(b)
    local v = filters[b.key]
    if b.key == "sort" then
        return "Sort: " .. (LabelOf(SortList(), v) or "Item level")
    end
    if b.key == "view" then
        return LabelOf(ViewOptions(), v or "crafted") or "Crafted items"
    end
    if v == nil then return b.empty end
    if b.key == "class" then return enum.class[v] end
    if b.key == "subclass" then return enum.subclass[v] end
    if b.key == "slot" then return SLOTS[v] and SLOTS[v][1] or b.empty end
    if b.key == "quality" then return QUALITIES[v + 1] .. " or better" end
    if b.key == "stat" then return STAT_LABEL[v] end
    if b.key == "source" then return LabelOf(SOURCES, v) end
    if b.key == "boss" and not filters.dungeon then return "Pick a dungeon first" end
    return tostring(v)
end

------------------------------------------------------------------------
-- result rows
------------------------------------------------------------------------
local function Summary(r)
    local bits = {}
    for _, code in ipairs(SUMMARY) do
        local v = r[STATS][code]
        if v and v > 0 then
            if code == "dps" then v = string.format("%.1f", v) end
            bits[#bits + 1] = "+" .. v .. " " .. SHORT[code]
        end
        if #bits >= 5 then break end
    end
    return table.concat(bits, "  ")
end

local function Kind(r)
    local slot = r[SLOT] > 0 and _G[enum.slot[r[SLOT]]] or nil
    local sub = r[SUBCLASS] > 0 and enum.subclass[r[SUBCLASS]] or nil
    if sub and slot then sub = sub:gsub("^One%-Handed ", ""):gsub("^Two%-Handed ", "") end
    if slot and sub and sub ~= "Miscellaneous" then return slot .. " " .. sub end
    return slot or sub or (r[CLASS] > 0 and enum.class[r[CLASS]]) or ""
end

local function UseText(r)
    local use = r[TEXT]:match("Use: ([^\n]+)") or r[TEXT]:match("Equip: ([^\n]+)")
    return use or ""
end

local function Reagents(list)
    local parts = {}
    for rid, n in (list or ""):gmatch("(%d+):(%d+)") do
        parts[#parts + 1] = n .. "x " .. ItemName(tonumber(rid))
    end
    return table.concat(parts, ", ")
end

-- line 2 and the right-hand text of a row, by tab
local function Details(id, r)
    local info, right
    local lvl = (r[REQ] > 0 and ("Req " .. r[REQ] .. "   ") or "") .. "iLvl " .. r[ILVL]
    if LootCodexDB.upgrades and r[SLOT] > 0 and LC.UpgradeDelta then
        local up = LC.UpgradeText(LC.UpgradeDelta(id))
        if up then lvl = up .. "   " .. lvl end
    end
    if LC.IsWished(id) then lvl = LC.STAR .. " " .. lvl end
    if tab.key == "dung" then
        local x = tabExtra[id]
        local s = Summary(r)
        info = (x and ("|cffffd100" .. x[1] .. "|r" .. (x[2] > 0 and string.format("  %.1f%%", x[2]) or "")) or "")
            .. (s ~= "" and ("   |cffaaaaaa" .. s .. "|r") or "")
        return info, lvl
    elseif tab.key == "wish" then
        local src = LC.GetSources(id)
        info = src and src[1] and (LC.DescribeSource(src[1])) or Kind(r)
        if GetItemCount(id, true) > 0 then lvl = "|cff20ff20owned|r   " .. lvl end
        return info, lvl
    end
    if tab.key == "prof" then
        local view, p = filters.view or "crafted", LootCodexDB.prof
        if view == "crafted" then
            -- skill colours as in the trade skill window: learn (orange, when a recipe says), yellow, grey
            -- the learn level from the recipe item or a trainer seen in game; otherwise "trainer"
            local c = craftInfo[p][id]
            local learn = c[2] > 0 and c[2] or (LC.TrainerReq and LC.TrainerReq(p, id))
            info = Reagents(reagentsOf[p][id])
            right = (learn and ("|cffff8040" .. learn .. "|r  ") or "|cff888888trainer|r  ")
                .. "|cffffff00" .. (c[5] or "?") .. "|r  |cff808080" .. (c[6] or "?") .. "|r"
        elseif view == "recipes" then
            info = "Teaches " .. (r[NAME]:match(":%s*(.+)$") or r[NAME])
            right = (profSet[id] or 0) > 0 and ("Skill " .. profSet[id]) or ""
        else
            local n = profSet[id] or 0
            info = n > 0 and string.format("Used in %d %s recipe%s", n, p, n == 1 and "" or "s") or Kind(r)
            right = lvl
        end
    elseif tab.key == "cons" then
        info, right = UseText(r), lvl
    elseif tab.key == "quest" then
        info = r[TEXT]:find("This Item Begins a Quest", 1, true) and "|cffffd100Starts a quest|r" or Kind(r)
        right = lvl
    else
        local s = Summary(r)
        info = Kind(r) .. (s ~= "" and ("   |cffaaaaaa" .. s .. "|r") or "")
        right = lvl
    end
    return info, right
end

-- the server tooltip if the client has the item cached, else one drawn from our data
local warm = CreateFrame("GameTooltip", "LootCodexWarmTip", UIParent, "GameTooltipTemplate")
local function ShowItemTooltip(owner, id)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GetItemInfo(id) then
        GameTooltip:SetHyperlink("item:" .. id)
        return
    end
    warm:SetOwner(UIParent, "ANCHOR_NONE")
    warm:SetHyperlink("item:" .. id)   -- asks the server, so next time it is the real tooltip
    local r = D[id]
    local c = ITEM_QUALITY_COLORS[r[QUALITY]] or ITEM_QUALITY_COLORS[1]
    GameTooltip:AddLine(r[NAME], c.r, c.g, c.b)
    for line in (r[TEXT] .. "\n"):gmatch("(.-)\n") do
        local left, rightText = line:match("^(.-)\t(.*)$")
        if left then
            GameTooltip:AddDoubleLine(left, rightText, 1, 1, 1, 1, 1, 1)
        elseif line:find("^Equip:") or line:find("^Use:") or line:find("^Chance on hit:") then
            GameTooltip:AddLine(line, 0, 1, 0, true)
        elseif line:find("^%(%d+%) Set:") then
            GameTooltip:AddLine(line, 0.5, 0.5, 0.5, true)
        else
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    end
    if LootCodexDB.tooltip then LC.AddSourceLines(GameTooltip, id) end
    GameTooltip:Show()
end

local function SetRow(row, st)
    local c = ITEM_QUALITY_COLORS[st.quality] or ITEM_QUALITY_COLORS[1]
    row.id, row.set = nil, st
    row.icon:SetTexture("Interface\\Icons\\" .. (st.icon ~= "" and st.icon or "INV_Misc_QuestionMark"))
    row.name:SetText(st.name)
    row.name:SetTextColor(c.r, c.g, c.b)
    local nb = 0
    for _ in (st.bonuses .. "\n"):gmatch("[^\n]+\n") do nb = nb + 1 end
    row.info:SetText(string.format("%d pieces   %s   %d bonus%s", #st.pieces,
        st.sub > 0 and enum.subclass[st.sub] or "", nb, nb == 1 and "" or "es"))
    row.right:SetText(st.minReq == st.maxReq and ("Req " .. st.minReq) or ("Req " .. st.minReq .. "-" .. st.maxReq))
    row.badge:Hide()
end

local function SetTooltip(row, st)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local c = ITEM_QUALITY_COLORS[st.quality] or ITEM_QUALITY_COLORS[1]
    GameTooltip:AddLine(st.name, c.r, c.g, c.b)
    for _, pid in ipairs(st.pieces) do
        local r = D[pid]
        local pc = ITEM_QUALITY_COLORS[r[QUALITY]] or ITEM_QUALITY_COLORS[1]
        GameTooltip:AddDoubleLine(r[NAME], Kind(r), pc.r, pc.g, pc.b, 0.7, 0.7, 0.7)
    end
    if st.bonuses ~= "" then
        GameTooltip:AddLine(" ")
        for n, text in st.bonuses:gmatch("(%d+)|([^\n]+)") do
            GameTooltip:AddLine("(" .. n .. ") Set: " .. text, 0, 1, 0, true)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to see the pieces", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

UpdateList = function()
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, ROWS do
        local row = rows[i]
        local id = results[offset + i]
        row.set = nil
        if id and id < 0 then
            SetRow(row, setList[-id])
            if (offset + i) % 2 == 0 then row.stripe:Show() else row.stripe:Hide() end
            row:Show()
        elseif id then
            local r = D[id]
            local c = ITEM_QUALITY_COLORS[r[QUALITY]] or ITEM_QUALITY_COLORS[1]
            local info, right = Details(id, r)
            row.id = id
            row.icon:SetTexture("Interface\\Icons\\" .. (r[ICON] ~= "" and r[ICON] or "INV_Misc_QuestionMark"))
            row.name:SetText(r[NAME])
            row.name:SetTextColor(c.r, c.g, c.b)
            row.info:SetText(info)
            row.right:SetText(right)
            if HasFlag(r, F_REBORN) then
                row.badge:SetText("|cffff9933Reborn|r"); row.badge:Show()
            elseif HasFlag(r, F_CUSTOM) then
                row.badge:SetText("|cff33ccffEpoch|r"); row.badge:Show()
            else
                row.badge:Hide()
            end
            if (offset + i) % 2 == 0 then row.stripe:Show() else row.stripe:Hide() end
            row:Show()
        else
            row.id = nil
            row:Hide()
        end
    end
    FauxScrollFrame_Update(scroll, #results, ROWS, ROW_H)
    local what, noun = tab.label, #results == 1 and "item" or "items"
    if tab.key == "prof" then
        what = LootCodexDB.prof .. " - " .. (PickerText({ key = "view" }) or "")
    elseif tab.key == "dung" then
        what = (filters.dungeon or "All dungeons") .. (filters.boss and (" - " .. filters.boss) or "")
    elseif tab.key == "sets" then
        local st = filters.set and SetById(filters.set)
        if st then what = st.name else noun = #results == 1 and "set" or "sets" end
    end
    countText:SetText(string.format("%s  |cffaaaaaa%d %s|r", what, #results, noun))
    if tab.key == "prof" and (filters.view or "crafted") == "crafted" then
        helpText:SetText("Skill: |cffff8040learn|r  |cffffff00yellow|r  |cff808080grey|r   (|cff888888trainer|r: visit one to learn it)")
    else
        helpText:SetText("Click: pin   Right-click: wishlist, map   Shift-click: link")
    end
end

local function MakeRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(LIST_W - 22, ROW_H)
    row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:GetHighlightTexture():SetBlendMode("ADD")

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetTexture(1, 1, 1, 0.04)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 6, ROW_H - 6)
    row.icon:SetPoint("LEFT", 3, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, 1)
    row.name:SetPoint("RIGHT", -150, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetHeight(14)

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 0)
    row.info:SetPoint("RIGHT", -6, 0)
    row.info:SetJustifyH("LEFT")
    row.info:SetHeight(12)
    row.info:SetTextColor(0.8, 0.8, 0.8)

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("TOPRIGHT", -6, -3)

    row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.badge:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.badge:SetText("|cff33ccffEpoch|r")

    row:SetScript("OnEnter", function(self)
        if self.set then SetTooltip(self, self.set) elseif self.id then ShowItemTooltip(self, self.id) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        if self.set then
            filters.set = self.set.id
            LC.SyncControls(); Refresh(); LC.Layout()
            return
        end
        if not self.id then return end
        local link = ItemLink(self.id)
        if button == "RightButton" then
            local id = self.id
            local opts = { { "wish", LC.IsWished(id) and "Remove from wishlist" or (LC.STAR .. " Add to wishlist") } }
            if LC.CanShowOnMap() then
                opts[#opts + 1] = { "map", "Show on map" }
                opts[#opts + 1] = { "clear", "Clear map pins" }
            end
            opts[#opts + 1] = { "link", "Link in chat" }
            ShowMenu(self, opts, function(v)
                if v == "wish" then LC.ToggleWish(id)
                elseif v == "map" then LC.ShowItemOnMap(id)
                elseif v == "clear" then LC.ClearMapPins()
                elseif v == "link" and not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
            end)
            return
        end
        LC.NoteRecent(self.id)
        if IsModifiedClick("CHATLINK") and ChatEdit_InsertLink(link) then return end
        if IsModifiedClick("DRESSUP") then DressUpItemLink(link) return end
        -- plain click pins the item, with the full source list
        ShowUIPanel(ItemRefTooltip)
        if not ItemRefTooltip:IsShown() then ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
        ItemRefTooltip:SetHyperlink("item:" .. self.id)
    end)
    return row
end

------------------------------------------------------------------------
-- filter panel: every control is a block that Layout() stacks for the current tab
------------------------------------------------------------------------
local controls, blocks, pickers = {}, {}, {}
local tabButtons, profButtons = {}, {}
local panel
local syncing = false

local function Block(key, height)
    local b = CreateFrame("Frame", nil, panel)
    b:SetSize(196, height)
    blocks[key] = b
    return b
end

local function Label(parent, text)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", 2, 0)
    l:SetText(text)
    return l
end

local function Picker(key, label, getOptions, emptyText, noEmpty)
    local blk = Block(key == "class" and "category" or key == "subclass" and "type" or key, 36)
    Label(blk, label)
    local b = CreateFrame("Button", nil, blk, "UIPanelButtonTemplate")
    b:SetSize(194, 20)
    b:SetPoint("TOPLEFT", 0, -12)
    b:SetText(" ")   -- makes sure the button's font string exists before it is positioned
    b:GetFontString():SetPoint("LEFT", 8, 0)
    b:GetFontString():SetPoint("RIGHT", -8, 0)
    b:GetFontString():SetJustifyH("LEFT")
    b.empty, b.key, b.getOptions, b.noEmpty = emptyText, key, getOptions, noEmpty
    b:SetScript("OnClick", function(self)
        if menu and menu:IsShown() then HideMenu() return end
        local opts = self.noEmpty and {} or { { false, self.empty } }
        for _, o in ipairs(self.getOptions()) do opts[#opts + 1] = o end
        ShowMenu(self, opts, function(value)
            filters[self.key] = value or nil
            if self.key == "class" then filters.subclass = nil end
            if self.key == "dungeon" then filters.boss = nil end
            if self.key == "stat" and value and filters.sort == "ilvl" then filters.sort = "stat" end
            if self.key == "stat" and not value and filters.sort == "stat" then filters.sort = "ilvl" end
            LC.SyncControls()
            Refresh()
        end)
    end)
    pickers[#pickers + 1] = b
    return b
end

local function Check(parent, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", cb, "RIGHT", 1, 1)
    t:SetText(label)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb
end

local function NumBox(parent, x, key)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(34, 20)
    eb:SetPoint("TOPLEFT", x, -12)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(2)
    eb:SetScript("OnTextChanged", function(self)
        if syncing then return end
        filters[key] = tonumber(self:GetText())
        Refresh()
    end)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

local function Layout()
    for _, b in pairs(blocks) do b:Hide() end
    if controls.setback then
        if filters.set then controls.setback:Enable() else controls.setback:Disable() end
    end
    local y = -8
    for _, key in ipairs(LAYOUT[tab.key]) do
        local b = blocks[key]
        if b then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
            b:Show()
            y = y - b:GetHeight() - 6
        end
    end
    for _, t in ipairs(tabButtons) do t:SetSelected(t.key == tab.key) end
    for _, p in ipairs(profButtons) do p:SetSelected(p.prof == LootCodexDB.prof) end
end
LC.Layout = Layout

function LC.SyncControls()
    if not frame then return end
    syncing = true
    for _, b in ipairs(pickers) do b:SetText(PickerText(b)) end
    controls.search:SetText(filters.text or "")
    controls.searchText:SetChecked(filters.searchText)
    controls.minReq:SetText(filters.minReq and tostring(filters.minReq) or "")
    controls.maxReq:SetText(filters.maxReq and tostring(filters.maxReq) or "")
    controls.custom:SetChecked(LootCodexDB.customOnly)
    controls.reborn:SetChecked(LootCodexDB.rebornOnly)
    controls.hidden:SetChecked(LootCodexDB.showHidden)
    controls.usable:SetChecked(filters.usable)
    controls.upgradesOnly:SetChecked(filters.upgradesOnly)
    if LootCodexDB.upgrades then controls.upgradesOnly:Show() else controls.upgradesOnly:Hide() end
    for _, a in ipairs({ controls.bossPrev, controls.bossNext }) do
        if filters.dungeon then a:Enable() else a:Disable() end
    end
    syncing = false
end

local function SelectTab(key)
    for _, t in ipairs(TABS) do if t.key == key then tab = t end end
    LootCodexDB.tab = tab.key
    LootCodexDB.tabs[tab.key] = LootCodexDB.tabs[tab.key] or TabDefaults(tab.key)
    filters = LootCodexDB.tabs[tab.key]
    if tab.key == "prof" then
        local views = ViewOptions()
        if not LabelOf(views, filters.view) and views[1] then filters.view = views[1][1] end
    end
    HideMenu()
    Layout()
    LC.SyncControls()
    Refresh()
end

-- inside a dungeon, the first time the window opens it goes to that dungeon's loot; after that your
-- own choices stand until the next loading screen
local autoDone
local function AutoDungeon()
    if not LootCodexDB.autoDungeon then return end
    local inst, raw = CurrentDungeon()
    if not inst or autoDone == raw then return end
    autoDone = raw
    LootCodexDB.tabs.dung = LootCodexDB.tabs.dung or TabDefaults("dung")
    local f = LootCodexDB.tabs.dung
    -- Blackrock Spire is one instance with two loot lists: keep Upper if that's the one you picked
    local spire = raw == "Blackrock Spire" and f.dungeon and f.dungeon:find("Blackrock Spire", 1, true)
    if f.dungeon ~= inst and not spire then f.dungeon, f.boss = inst, nil end
    SelectTab("dung")
end

local function SelectProfession(p)
    LootCodexDB.prof = p
    SelectTab("prof")
end

-- flat buttons with a selected state, used for the tabs and the profession list
local function FlatButton(parent, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b:GetHighlightTexture():SetBlendMode("ADD")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    function b:SetSelected(on)
        self.bg:SetTexture(on and 0.16 or 0.07, on and 0.42 or 0.07, on and 0.65 or 0.09, on and 0.9 or 0.8)
        self.text:SetTextColor(on and 1 or 0.85, on and 1 or 0.82, on and 1 or 0.6)
    end
    return b
end

local function Build()
    frame = CreateFrame("Frame", "LootCodexFrame", UIParent)
    frame:SetSize(836, 660)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", HideMenu)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    tinsert(UISpecialFrames, "LootCodexFrame")   -- Escape closes it

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("TOPLEFT", 18, -15)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("|cff33ccffTMPZ-LootCodex|r")
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
    subtitle:SetText(string.format("%d items  -  %s", LootCodexData.count,
        LootCodexData.realm ~= "" and LootCodexData.realm or "this server"))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    local settings = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settings:SetSize(80, 20)
    settings:SetPoint("RIGHT", close, "LEFT", -2, 0)
    settings:SetText("Settings")
    settings:SetScript("OnClick", function()
        frame:Hide()
        LC.OpenSettings()
    end)

    -- tabs
    local x = 16
    for _, t in ipairs(TABS) do
        local b = FlatButton(frame, 0, 24)
        b.text:SetFontObject("GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(t.label)
        b:SetWidth(b.text:GetStringWidth() + 20)
        b:SetPoint("TOPLEFT", x, -44)
        x = x + b:GetWidth() + 4
        b.key = t.key
        b:SetScript("OnClick", function() SelectTab(t.key) end)
        tabButtons[#tabButtons + 1] = b
    end
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(0.16, 0.42, 0.65, 0.9)
    rule:SetHeight(2)
    rule:SetPoint("TOPLEFT", 16, -68)
    rule:SetPoint("TOPRIGHT", -16, -68)

    -- left: filter panel
    panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", 14, -76)
    panel:SetPoint("BOTTOMLEFT", 14, 40)
    panel:SetWidth(212)
    panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0, 0, 0, 0.45)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4)

    -- professions list (Professions tab)
    local plist = Block("professions", #profs * 19 + 4)
    for i, p in ipairs(profs) do
        local b = FlatButton(plist, 194, 18)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 19)
        local ic = b:CreateTexture(nil, "ARTWORK")
        ic:SetSize(16, 16)
        ic:SetPoint("LEFT", 3, 0)
        ic:SetTexture("Interface\\Icons\\" .. profIcon[p])
        ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.text:SetFontObject("GameFontNormalSmall")
        b.text:SetPoint("LEFT", ic, "RIGHT", 6, 0)
        b.text:SetText(p)
        b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.count:SetPoint("RIGHT", -6, 0)
        local n = 0
        for _ in pairs(crafted[p]) do n = n + 1 end
        b.count:SetText(n > 0 and n or "")
        b.prof = p
        b:SetScript("OnClick", function() SelectProfession(p) end)
        profButtons[#profButtons + 1] = b
    end

    -- search
    local sblk = Block("search", 56)
    Label(sblk, "Search")
    local search = CreateFrame("EditBox", "LootCodexSearchBox", sblk, "InputBoxTemplate")
    search:SetSize(186, 20)
    search:SetPoint("TOPLEFT", 6, -12)
    search:SetAutoFocus(false)
    local pending = 0
    local debounce = CreateFrame("Frame")
    debounce:Hide()
    debounce:SetScript("OnUpdate", function(self, elapsed)
        pending = pending - elapsed
        if pending <= 0 then self:Hide(); Refresh() end
    end)
    search:SetScript("OnTextChanged", function(self)
        if syncing then return end
        filters.text = self:GetText()
        pending = 0.25
        debounce:Show()
    end)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    controls.search = search
    controls.searchText = Check(sblk, "Also search tooltip text", function(v) filters.searchText = v; Refresh() end)
    controls.searchText:SetPoint("TOPLEFT", -2, -33)

    Picker("view", "Show", ViewOptions, "", true)
    Picker("dungeon", "Dungeon", DungeonOptions, "All dungeons")
    -- previous / next arrows beside the boss picker: step through the dungeon's bosses, wrapping round
    local bossPicker = Picker("boss", "Boss", BossOptions, "All bosses")
    bossPicker:SetWidth(146)
    local function StepBoss(dir)
        local opts = BossOptions()
        if #opts == 0 then return end
        local at = 0
        for i, o in ipairs(opts) do if o[1] == filters.boss then at = i end end
        if at == 0 then at = dir > 0 and 1 or #opts else at = (at - 1 + dir) % #opts + 1 end
        filters.boss = opts[at][1]
        HideMenu()
        LC.SyncControls()
        Refresh()
    end
    for i, dir in ipairs({ -1, 1 }) do
        local a = CreateFrame("Button", nil, bossPicker:GetParent())
        a:SetSize(22, 22)
        a:SetPoint("LEFT", bossPicker, "RIGHT", i == 1 and 2 or 26, 0)
        local page = dir < 0 and "Prev" or "Next"
        a:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. page .. "Page-Up")
        a:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. page .. "Page-Down")
        a:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. page .. "Page-Disabled")
        a:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        a:SetScript("OnClick", function() StepBoss(dir) end)
        a:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(dir < 0 and "Previous boss" or "Next boss")
            GameTooltip:Show()
        end)
        a:SetScript("OnLeave", function() GameTooltip:Hide() end)
        controls[dir < 0 and "bossPrev" or "bossNext"] = a
    end

    local ublk = Block("usable", 44)
    controls.usable = Check(ublk, "Usable by my class", function(v) filters.usable = v or nil; Refresh() end)
    controls.usable:SetPoint("TOPLEFT", -2, 0)
    controls.upgradesOnly = Check(ublk, "Upgrades only", function(v) filters.upgradesOnly = v or nil; Refresh() end)
    controls.upgradesOnly:SetPoint("TOPLEFT", -2, -20)

    local sbk = Block("setback", 24)
    controls.setback = CreateFrame("Button", nil, sbk, "UIPanelButtonTemplate")
    controls.setback:SetSize(194, 22)
    controls.setback:SetPoint("TOPLEFT")
    controls.setback:SetText("<< All sets")
    controls.setback:SetScript("OnClick", function()
        filters.set = nil
        LC.SyncControls(); Refresh(); Layout()
    end)

    local wblk = Block("wishmap", 62)
    local wmap = CreateFrame("Button", nil, wblk, "UIPanelButtonTemplate")
    wmap:SetSize(194, 22)
    wmap:SetPoint("TOPLEFT")
    wmap:SetText("Show all on map")
    wmap:SetScript("OnClick", function() LC.ShowWishlistOnMap() end)
    local wnote = wblk:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wnote:SetPoint("TOPLEFT", 2, -28)
    wnote:SetWidth(192)
    wnote:SetJustifyH("LEFT")
    wnote:SetText("Right-click any item in another tab to add it.")

    local rblk = Block("recentclear", 62)
    local rclear = CreateFrame("Button", nil, rblk, "UIPanelButtonTemplate")
    rclear:SetSize(194, 22)
    rclear:SetPoint("TOPLEFT")
    rclear:SetText("Clear the list")
    rclear:SetScript("OnClick", function() LC.ClearRecent() end)
    local rnote = rblk:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rnote:SetPoint("TOPLEFT", 2, -28)
    rnote:SetWidth(192)
    rnote:SetJustifyH("LEFT")
    rnote:SetText("Items you clicked here or opened from chat links, newest first.")
    Picker("class", "Category", ClassOptions, "All categories")
    Picker("subclass", "Type", SubclassOptions, "All types")
    Picker("slot", "Slot", SlotOptions, "All slots")
    Picker("quality", "Quality", QualityOptions, "Any quality")
    Picker("stat", "Has stat", ListOptions(STAT_LIST), "Any stats")
    Picker("source", "Source", ListOptions(SOURCES), "Any source")
    Picker("sort", "Sort by", function() return ListOptions(SortList())() end, "", true)

    local lblk = Block("level", 36)
    Label(lblk, "Required level")
    controls.minReq = NumBox(lblk, 6, "minReq")
    local to = lblk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    to:SetPoint("TOPLEFT", 46, -17)
    to:SetText("to")
    controls.maxReq = NumBox(lblk, 64, "maxReq")
    local mine = CreateFrame("Button", nil, lblk, "UIPanelButtonTemplate")
    mine:SetSize(86, 20)
    mine:SetPoint("TOPLEFT", 108, -12)
    mine:SetText("My level")
    mine:SetScript("OnClick", function()
        filters.maxReq = UnitLevel("player")
        LC.SyncControls(); Refresh()
    end)

    -- panel bottom: settings that apply to every tab, and reset
    controls.custom = Check(panel, "Epoch custom / changed only", function(v) LootCodexDB.customOnly = v; Refresh() end)
    controls.custom:SetPoint("BOTTOMLEFT", 6, 72)
    controls.reborn = Check(panel, "Reborn additions only", function(v) LootCodexDB.rebornOnly = v; Refresh() end)
    controls.reborn:SetPoint("BOTTOMLEFT", 6, 52)
    controls.hidden = Check(panel, "Show TBC/WotLK & test items", function(v)
        LootCodexDB.showHidden = v
        if LC.ForgetUnitDrops then LC.ForgetUnitDrops() end
        Refresh()
    end)
    controls.hidden:SetPoint("BOTTOMLEFT", 6, 32)
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(194, 22)
    reset:SetPoint("BOTTOMLEFT", 9, 8)
    reset:SetText("Reset filters")
    reset:SetScript("OnClick", function()
        LootCodexDB.tabs[tab.key] = TabDefaults(tab.key)
        SelectTab(tab.key)
    end)

    -- right: results
    countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countText:SetPoint("TOPLEFT", 236, -82)
    helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helpText:SetPoint("TOPRIGHT", -22, -84)

    local list = CreateFrame("Frame", nil, frame)
    list:SetSize(LIST_W, ROWS * ROW_H + 4)
    list:SetPoint("TOPLEFT", 234, -98)
    list:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    list:SetBackdropColor(0, 0, 0, 0.45)
    list:SetBackdropBorderColor(0.4, 0.4, 0.4)

    scroll = CreateFrame("ScrollFrame", "LootCodexScroll", list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", -24, 2)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, UpdateList)
    end)

    -- rows sit above the scroll frame so they get the clicks; the wheel still scrolls
    rows = {}
    for i = 1, ROWS do
        local row = MakeRow(list, i)
        row:SetFrameLevel(scroll:GetFrameLevel() + 2)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            local bar = _G["LootCodexScrollScrollBar"]
            bar:SetValue(bar:GetValue() - delta * ROW_H * 3)
        end)
        rows[i] = row
    end

    local foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("BOTTOMLEFT", 20, 20)
    foot:SetPoint("BOTTOMRIGHT", -20, 20)
    foot:SetJustifyH("LEFT")
    local function FootText()
        local c = LC.LearnedCounts()
        foot:SetText(string.format("%s   Learned: %d mobs, %d vendor items, %d quest rewards  (%d shared by %d players)",
            LC.HasPfQuest() and "Drops from pfQuest." or "Install pfQuest for mob drops.",
            c.mobs, c.vendors, c.quests, c.received, c.senders))
    end
    FootText()
    frame:SetScript("OnShow", FootText)
end

function LC.Toggle()
    if frame and frame:IsShown() then frame:Hide() return end
    if not EnsureData() then return end
    if not frame then
        Build()
        SelectTab(LootCodexDB.tab)
    end
    AutoDungeon()
    frame:Show()
end

-- every loading screen: forget the last jump, and jump now if the window is already open
local zoneWatch = CreateFrame("Frame")
zoneWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneWatch:SetScript("OnEvent", function()
    autoDone = nil
    if frame and frame:IsShown() then AutoDungeon() end
end)

------------------------------------------------------------------------
-- startup
------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
    if name ~= "TMPZ-LootCodex" then return end
    self:UnregisterEvent("ADDON_LOADED")
    LootCodexDB = LootCodexDB or {}
    for k, v in pairs(DEFAULTS) do
        if LootCodexDB[k] == nil then LootCodexDB[k] = v end
    end
    LootCodexDB.filters = nil          -- 1.x kept one filter set; each tab has its own now
    LootCodexDB.tabs = LootCodexDB.tabs or {}
    for _, t in ipairs(TABS) do
        if t.key == LootCodexDB.tab then tab = t end
    end
    tab = tab or TABS[2]
    LootCodexDB.tabs[tab.key] = LootCodexDB.tabs[tab.key] or TabDefaults(tab.key)
    filters = LootCodexDB.tabs[tab.key]
    LC.HookTooltips()
end)

-- a few seconds after each login (so chat is up): a one-line status, saying which helper addons were
-- found; the longer "install pfQuest" explanation only once per account
local notice = CreateFrame("Frame")
notice:RegisterEvent("PLAYER_ENTERING_WORLD")
notice:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local base = IsAddOnLoaded("pfQuest-wotlk") or IsAddOnLoaded("pfQuest")
    local epoch = IsAddOnLoaded("pfQuest-epoch")
    local wait = 6
    self:SetScript("OnUpdate", function(f, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        f:SetScript("OnUpdate", nil)
        local function state(v) return v and "|cff20ff20found|r" or "|cffff4040missing|r" end
        if LootCodexDB.loginMessage then
            Print("ready (/codex to open).  pfQuest: " .. state(base) .. ",  pfQuest-epoch: " .. state(epoch) .. ".")
        end
        if (base and epoch) or LootCodexDB.pfQuestNoticeShown then return end
        LootCodexDB.pfQuestNoticeShown = true
        if not base then
            Print("for mob drops, drop chances, vendors and map pins, also install |cffffd100pfQuest-wotlk|r"
                .. " and |cffffd100pfQuest-epoch|r (github.com/Bennylavaa/pfQuest-epoch).")
        else
            Print("pfQuest is installed but |cffffd100pfQuest-epoch|r isn't: add it (github.com/Bennylavaa/pfQuest-epoch)"
                .. " so drops and mobs match Project Epoch.")
        end
        Print("Everything else works without it. (This explanation only shows once.)")
    end)
end)

-- chat lines for work running in the background (update check, catching up with the guild,
-- fetching shared items, loading the item data); off with Settings > Display
function LC.Activity(msg)
    if LootCodexDB and LootCodexDB.activityMessages then Print(msg) end
end

-- the same, for guild/group sharing: when the minimap badge is counting those finds, it says it
-- instead of the chat window
function LC.ShareActivity(msg)
    if LootCodexDB and LootCodexDB.sharedNotify and not LootCodexDB.minimapHide then return end
    LC.Activity(msg)
end

SLASH_LOOTCODEX1, SLASH_LOOTCODEX2 = "/codex", "/lootcodex"
SlashCmdList.LOOTCODEX = function(msg)
    local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = raw:lower()
    if msg == "help" then
        Print("/codex  open the window   /codex <words>  search all items")
        Print("/codex settings  all the options below, with tick boxes")
        Print("/codex status  which helper addons were found, and what has been learned")
        Print("/codex update  check the server for new and changed items (again to stop)")
        Print("/codex tooltip  sources in tooltips on/off   /codex record  learning on/off")
        Print("/codex share  sharing with guild/group on/off   /codex minimap  minimap button on/off")
        Print("/codex forget  drop everything others shared   /codex ignore <name>  drop and block one player")
        Print("/codex boss  add your target to its dungeon's boss list, or take it off again")
        Print("/codex wishcheck  does your target drop anything on your wishlist?   /codex mobalerts  those alerts on/off")
        return
    end
    if msg == "boss" then
        local npc = UnitExists("target") and not UnitIsPlayer("target") and LC.NpcId(UnitGUID("target"))
        if not npc then Print("target a creature first, then /codex boss.") return end
        local on, name, where = LC.ToggleBossMark(npc, UnitName("target"))
        if not on then
            Print(name .. " is off the boss lists. /codex boss again to put it back.")
        elseif where then
            Print(name .. " is now listed as a boss (" .. (DungeonNamed(where, dungeons) or where) .. ").")
        else
            Print(name .. " will be listed as a boss once someone loots it inside its dungeon.")
        end
        LC.RefreshIfOpen()
        return
    end
    if msg == "wishcheck" or msg == "wish" then
        LC.WishCheckTarget()
        return
    end
    if msg == "mobalerts" or msg == "mobalert" then
        LootCodexDB.wishMobAlerts = not LootCodexDB.wishMobAlerts
        if LC.ForgetMobAlerts then LC.ForgetMobAlerts() end
        Print("alerts for creatures that drop wishlist items " .. (LootCodexDB.wishMobAlerts and "on." or "off."))
        return
    end
    if msg == "update" or msg == "updates" then
        if LC.UpdateCheckProgress() then LC.StopUpdateCheck() else LC.StartUpdateCheck() end
        return
    end
    if msg == "status" then
        local function yes(v) return v and "|cff20ff20found|r" or "|cffff4040missing|r" end
        local base = IsAddOnLoaded("pfQuest-wotlk") or IsAddOnLoaded("pfQuest")
        Print("pfQuest: " .. yes(base) .. ",  pfQuest-epoch: " .. yes(IsAddOnLoaded("pfQuest-epoch"))
            .. (LC.HasPfQuest() and "" or "  (mob drops, vendors and map pins are off)"))
        Print("Item data: " .. (D and ("loaded, " .. #allIds .. " items") or "not loaded yet (opens with the window)"))
        local c = LC.LearnedCounts()
        Print(string.format("Learned: %d mobs, %d vendor items, %d quest rewards, %d shared by %d players.",
            c.mobs, c.vendors, c.quests, c.received, c.senders))
        return
    end
    if msg == "wheel" then
        -- what the game has on <key> + mouse wheel right now, for when scrolling doesn't work
        local up = LC.MoreKey() .. "-MOUSEWHEELUP"
        local claimed = LC.BindWheel()
        Print(string.format("key %s, scrolling %s. %s is bound to: %s (your own binding: %s)",
            LC.MoreKeyName(), claimed and "on" or (InCombatLockdown() and "waiting for combat to end" or "off"),
            up, tostring(GetBindingAction(up, true)), tostring(GetBindingAction(up))))
        return
    end
    if msg == "settings" or msg == "options" or msg == "config" then
        LC.OpenSettings()
        return
    end
    if msg == "minimap" then
        LootCodexDB.minimapHide = not LootCodexDB.minimapHide
        LC.UpdateMinimapButton()
        Print("minimap button " .. (LootCodexDB.minimapHide and "hidden." or "shown."))
        return
    end
    if msg == "share" then
        LootCodexDB.share = not LootCodexDB.share
        Print("sharing with guild and group members " .. (LootCodexDB.share and "on." or "off."))
        return
    end
    if msg == "forget" then
        LC.ForgetShared()
        Print("forgot everything other players shared. Your own records are kept.")
        return
    end
    local who = raw:match("^[Ii][Gg][Nn][Oo][Rr][Ee]%s+(%S+)$")
    if who then
        who = who:sub(1, 1):upper() .. who:sub(2):lower()
        LC.ForgetShared(who)
        Print("removed and now ignoring everything shared by " .. who .. ".")
        return
    end
    if msg == "record" then
        LootCodexDB.record = not LootCodexDB.record
        Print("recording loot, vendors and quest rewards " .. (LootCodexDB.record and "on." or "off."))
        return
    end
    if msg == "tooltip" then
        LootCodexDB.tooltip = not LootCodexDB.tooltip
        Print("sources in item tooltips " .. (LootCodexDB.tooltip and "on." or "off."))
        return
    end
    if msg ~= "" then
        if not frame then LC.Toggle() elseif not frame:IsShown() then frame:Show() end
        if not frame then return end
        LootCodexDB.tabs.all = LootCodexDB.tabs.all or TabDefaults("all")
        LootCodexDB.tabs.all.text = raw
        SelectTab("all")
        return
    end
    LC.Toggle()
end
