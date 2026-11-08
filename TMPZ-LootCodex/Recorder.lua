-- Learn as you play: records what this account sees drop, what vendors sell and what quests
-- reward, into LootCodexLog (account-wide SavedVariables). Sync.lua shares the same records
-- with guild and group members running Loot Codex.
--
-- Everything is one record per fact, keyed so the same fact from two people is stored once:
--   "K"..corpseGUID          a looted corpse  {t="K", npc, name, zone, items="id,id,...", inst, cls}
--                            inst = the instance it died in, cls = w world boss, s skull, r rare, e elite, n normal
--   "E"..player..":"..npc..":"..time   n corpses of one mob that had no items (money only), counted
--                            together and saved every few minutes  {t="E", npc, name, zone, n, inst, cls}.
--                            They only add kills, which keeps learned drop chances right without
--                            one stored and shared record per empty corpse. Older versions ignore them.
--   "V"..npc..":"..item      a vendor sells   {t="V", npc, name, zone, item}
--   "Q"..title..":"..item    a quest rewards  {t="Q", title, zone, item, how}  how 1 reward, 2 choice
--   "T"..item..":"..prof     a trainer teaches the recipe for item at that skill  {t="T", prof, item, rank}
-- rt = when this client learned it (drives catch-up sync); src = who sent it (nil = recorded here).

LootCodex = LootCodex or {}
local LC = LootCodex

local log                       -- LootCodexLog
local shared                    -- LootCodexShared.rec (SharedLog.lua, merged offline)
local mobs, itemMobs, itemVendors, itemQuests = {}, {}, {}, {}
local trainerReq = {}           -- profession -> { crafted item -> skill a trainer asks for }
local counts = { mobs = 0, vendors = 0, quests = 0, records = 0, received = 0, senders = 0 }
local senders = {}
local fishCounter = 0
local EMPTY_FLUSH = 300         -- seconds between saving/sharing the counted empty corpses
local emptyPending = {}         -- npc -> the "E" record being counted
local emptySeen = {}            -- "K"..guid -> true: empty corpses already counted this session

local function ItemId(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- creature GUIDs in 3.3.5 are 0xF130 + 6-digit entry + 6-digit spawn counter (0xF150 for vehicles)
local function NpcId(guid)
    if not guid then return nil end
    local kind = guid:sub(3, 5)
    if kind ~= "F13" and kind ~= "F15" then return nil end
    return tonumber(guid:sub(7, 12), 16)
end

local function Zone() return GetRealZoneText() or "" end

local CLS_RANK = { n = 1, e = 2, r = 3, s = 4, w = 5 }

-- the dungeon or raid you are in (its map name), nil outside instances
local function Instance()
    local name, kind = GetInstanceInfo()
    if kind == "party" or kind == "raid" then return name end
end

local function Classify(unit)
    local c = UnitClassification(unit)
    if c == "worldboss" then return "w" end
    if UnitLevel(unit) == -1 then return "s" end
    if c == "rare" or c == "rareelite" then return "r" end
    if c == "elite" then return "e" end
    return "n"
end

-- "^", "~" and "|" separate fields on the wire and in chat escapes; names never need them
function LC.Clean(s) return (tostring(s or ""):gsub("[%^~|]", "")) end

------------------------------------------------------------------------
-- index: what the tooltip asks for, kept up to date record by record
------------------------------------------------------------------------
local function Index(r)
    counts.records = counts.records + 1
    if r.src then
        counts.received = counts.received + 1
        if not senders[r.src] then senders[r.src] = true; counts.senders = counts.senders + 1 end
    end
    if r.t == "K" or r.t == "E" then
        local m = mobs[r.npc]
        if not m then
            m = { name = r.name, zone = r.zone, kills = 0, items = {} }
            mobs[r.npc] = m
            counts.mobs = counts.mobs + 1
        end
        m.kills = m.kills + (r.t == "E" and (tonumber(r.n) or 1) or 1)
        m.inst = m.inst or r.inst
        if r.cls and (CLS_RANK[r.cls] or 0) > (CLS_RANK[m.cls] or 0) then m.cls = r.cls end
        if r.src then m.shared = true end
        for id in (r.items or ""):gmatch("%d+") do
            id = tonumber(id)
            m.items[id] = (m.items[id] or 0) + 1
            itemMobs[id] = itemMobs[id] or {}
            itemMobs[id][r.npc] = true
        end
        for id in pairs(m.items) do LC.ForgetSources(id) end   -- the kill count changed every chance
        if LC.ForgetUnitDrops then LC.ForgetUnitDrops() end
        if LC.ForgetLearnedBosses then LC.ForgetLearnedBosses() end
    elseif r.t == "V" then
        local t = itemVendors[r.item] or {}
        itemVendors[r.item] = t
        if not t[r.npc] then counts.vendors = counts.vendors + 1 end
        t[r.npc] = { name = r.name, zone = r.zone, shared = r.src ~= nil }
        LC.ForgetSources(r.item)
    elseif r.t == "Q" then
        local t = itemQuests[r.item] or {}
        itemQuests[r.item] = t
        if not t[r.title] then counts.quests = counts.quests + 1 end
        t[r.title] = { zone = r.zone, choice = r.how == 2, shared = r.src ~= nil }
        LC.ForgetSources(r.item)
    elseif r.t == "T" then
        trainerReq[r.prof] = trainerReq[r.prof] or {}
        trainerReq[r.prof][r.item] = r.rank
        LC.ForgetSources(r.item)
    end
end

-- the skill a trainer asks for to learn the recipe that makes item (nil = no trainer seen yet)
function LC.TrainerReq(prof, item) return trainerReq[prof] and trainerReq[prof][item] end

local function Reindex()
    wipe(mobs); wipe(itemMobs); wipe(itemVendors); wipe(itemQuests); wipe(senders); wipe(trainerReq)
    for k in pairs(counts) do counts[k] = 0 end
    for key, r in pairs(shared) do
        if not log.rec[key] then
            r.src = r.src or "shared file"
            Index(r)
        end
    end
    for _, r in pairs(log.rec) do Index(r) end
    LC.ForgetSources()
end

-- Adds a record unless it is already known. src = sender's name, nil when recorded here.
function LC.AddRecord(key, r, src)
    if log.rec[key] or shared[key] then return false end
    if src and log.ignore[src] then return false end
    r.rt, r.src = time(), src
    log.rec[key] = r
    Index(r)
    if src and LC.NoteShared then LC.NoteShared(r, src) end
    return true
end

------------------------------------------------------------------------
-- what other players' TMPZ-LootCodex has sent since you last looked (the minimap button's badge)
------------------------------------------------------------------------
local SHARED_RECENT = 6

local function ItemName(id)
    local name = GetItemInfo(id)
    local r = not name and LC.Item and LC.Item(id)
    return name or (r and r[1]) or ("item " .. id)
end

local function DescribeRecord(r)
    if r.t == "K" then
        local names = {}
        for id in (r.items or ""):gmatch("%d+") do
            if #names < 2 then names[#names + 1] = ItemName(tonumber(id)) end
        end
        return (r.name or "?") .. " dropped " .. (#names > 0 and table.concat(names, ", ") or "nothing")
    elseif r.t == "E" then
        return (r.name or "?") .. ": " .. (r.n or 1) .. " more kill" .. ((r.n or 1) == 1 and "" or "s") .. " with no items"
    elseif r.t == "V" then
        return (r.name or "?") .. " sells " .. ItemName(r.item)
    elseif r.t == "Q" then
        return "\"" .. (r.title or "?") .. "\" rewards " .. ItemName(r.item)
    elseif r.t == "T" then
        return (r.prof or "?") .. " trainer: " .. ItemName(r.item) .. " at " .. (r.rank or "?")
    end
    return r.text or "?"
end

-- r: a record, or { text = "..." } for anything else; from: the sender's name
function LC.NoteShared(r, from)
    local db = LootCodexDB
    if not db then return end
    db.sharedUnseen = (db.sharedUnseen or 0) + 1
    db.sharedRecent = db.sharedRecent or {}
    table.insert(db.sharedRecent, 1, { text = DescribeRecord(r), from = from, t = time() })
    while #db.sharedRecent > SHARED_RECENT do table.remove(db.sharedRecent) end
    if LC.UpdateSharedBadge then LC.UpdateSharedBadge() end
end

function LC.SharedUnseen() return LootCodexDB and LootCodexDB.sharedUnseen or 0 end
function LC.SharedRecent() return LootCodexDB and LootCodexDB.sharedRecent or {} end

function LC.MarkSharedSeen()
    if LootCodexDB then LootCodexDB.sharedUnseen = 0 end
    if LC.UpdateSharedBadge then LC.UpdateSharedBadge() end
end

function LC.Records() return log and log.rec or {} end

------------------------------------------------------------------------
-- wire format, shared with Sync.lua
------------------------------------------------------------------------
function LC.Encode(key, r)
    local C = LC.Clean
    if r.t == "K" then
        -- inst and cls ride at the end: older versions read the first six fields and ignore the rest
        return table.concat({ "K", key:sub(2), r.npc, C(r.name), C(r.zone), r.items or "", C(r.inst), r.cls or "" }, "^")
    elseif r.t == "E" then
        return table.concat({ "E", key:sub(2), r.npc, C(r.name), C(r.zone), r.n or 1, C(r.inst), r.cls or "" }, "^")
    elseif r.t == "V" then
        return table.concat({ "V", r.npc, C(r.name), C(r.zone), r.item }, "^")
    elseif r.t == "Q" then
        return table.concat({ "Q", C(r.title), C(r.zone), r.item, r.how }, "^")
    elseif r.t == "T" then
        return table.concat({ "T", C(r.prof), r.item, r.rank }, "^")
    end
end

function LC.Decode(s)
    local f = {}
    for part in (s .. "^"):gmatch("([^%^]*)%^") do f[#f + 1] = part end
    local t = f[1]
    if t == "K" and #f >= 6 and f[2] ~= "" then
        return "K" .. f[2], { t = "K", npc = tonumber(f[3]) or f[3], name = f[4], zone = f[5], items = f[6],
            inst = f[7] ~= "" and f[7] or nil, cls = CLS_RANK[f[8] or ""] and f[8] or nil }
    elseif t == "E" and #f >= 6 and f[2] ~= "" and tonumber(f[3]) then
        local n = tonumber(f[6])
        if not n or n < 1 or n > 500 then return nil end
        return "E" .. f[2], { t = "E", npc = tonumber(f[3]), name = f[4], zone = f[5], n = math.floor(n),
            inst = f[7] ~= "" and f[7] or nil, cls = CLS_RANK[f[8] or ""] and f[8] or nil }
    elseif t == "V" and #f >= 5 and tonumber(f[5]) then
        local npc = tonumber(f[2]) or f[2]
        return "V" .. npc .. ":" .. f[5], { t = "V", npc = npc, name = f[3], zone = f[4], item = tonumber(f[5]) }
    elseif t == "Q" and #f >= 5 and tonumber(f[4]) and f[2] ~= "" then
        return "Q" .. f[2] .. ":" .. f[4], { t = "Q", title = f[2], zone = f[3], item = tonumber(f[4]), how = tonumber(f[5]) or 1 }
    elseif t == "T" and #f >= 4 and tonumber(f[3]) and tonumber(f[4]) and f[2] ~= "" then
        return "T" .. f[3] .. ":" .. f[2], { t = "T", prof = f[2], item = tonumber(f[3]), rank = tonumber(f[4]) }
    end
end

------------------------------------------------------------------------
-- recording
------------------------------------------------------------------------
local function Learned(key, r)
    if LC.AddRecord(key, r) and LC.ShareLive then LC.ShareLive(LC.Encode(key, r)) end
end

local function CorpseUnit()
    for _, unit in ipairs({ "mouseover", "target" }) do
        if UnitExists(unit) and UnitIsDead(unit) and not UnitIsPlayer(unit) then return unit end
    end
end

local function OnLoot()
    local key, npc, name, cls
    if IsFishingLoot() then
        fishCounter = fishCounter + 1
        npc, name = "fishing:" .. Zone(), "Fishing"
        key = "K" .. "F" .. LC.Clean(UnitName("player")) .. time() .. fishCounter
    else
        local unit = CorpseUnit()
        local guid = unit and UnitGUID(unit)
        npc = NpcId(guid)
        if not npc then return end
        key, name, cls = "K" .. guid, UnitName(unit), Classify(unit)
    end
    local ids = {}
    for slot = 1, GetNumLootItems() do
        if LootSlotIsItem(slot) then
            local id = ItemId(GetLootSlotLink(slot))
            if id then ids[#ids + 1] = id end
        end
    end
    if #ids == 0 and key:sub(2, 2) ~= "F" then
        -- money only: counted with the mob's other empty corpses (see FlushEmpty), unless this corpse was
        -- already recorded with items (it's been opened before and the items taken)
        if log.rec[key] or shared[key] or emptySeen[key] then return end
        emptySeen[key] = true
        local p = emptyPending[npc]
        if not p then
            p = { t = "E", npc = npc, name = name, zone = Zone(), n = 0, inst = cls and Instance(), cls = cls }
            emptyPending[npc] = p
        end
        p.n = p.n + 1
        if cls and (CLS_RANK[cls] or 0) > (CLS_RANK[p.cls] or 0) then p.cls = cls end
        return
    end
    Learned(key, { t = "K", npc = npc, name = name, zone = Zone(), items = table.concat(ids, ","),
        inst = cls and Instance(), cls = cls })
end

-- saves (and shares) the empty corpses counted since the last call: one record per mob
local function FlushEmpty()
    if not next(emptyPending) then return end
    local me, now = LC.Clean(UnitName("player")), time()
    for npc, p in pairs(emptyPending) do
        Learned("E" .. me .. ":" .. npc .. ":" .. now, p)
    end
    wipe(emptyPending)
end

local function OnMerchant()
    local npc = NpcId(UnitGUID("npc"))
    if not npc then return end
    local name, zone = UnitName("npc"), Zone()
    for i = 1, GetMerchantNumItems() do
        local id = ItemId(GetMerchantItemLink(i))
        if id then Learned("V" .. npc .. ":" .. id, { t = "V", npc = npc, name = name, zone = zone, item = id }) end
    end
end

-- a profession trainer lists every recipe with the skill it needs; the trainer window's filters are
-- opened up for the read and put back afterwards
local function OnTrainer()
    if not GetNumTrainerServices or not GetTrainerServiceSkillReq then return end
    local saved = {}
    for _, kind in ipairs({ "available", "unavailable", "used" }) do
        saved[kind] = GetTrainerServiceTypeFilter(kind) and true or false   -- (nil would vanish from pairs)
        if not saved[kind] then SetTrainerServiceTypeFilter(kind, 1) end
    end
    for i = 1, GetNumTrainerServices() do
        local prof, rank = GetTrainerServiceSkillReq(i)
        local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
        local id = link and ItemId(link)
        rank = tonumber(rank)
        if prof and rank and id then
            local key = "T" .. id .. ":" .. LC.Clean(prof)
            local old = log.rec[key]
            if old and old.rank ~= rank then log.rec[key] = nil end      -- the trainer changed it: replace
            Learned(key, { t = "T", prof = LC.Clean(prof), item = id, rank = rank })
        end
    end
    for kind, was in pairs(saved) do
        if not was then SetTrainerServiceTypeFilter(kind, 0) end
    end
end

local function OnQuest()
    local title = LC.Clean(GetTitleText())
    if title == "" then return end
    local zone = Zone()
    for _, kind in ipairs({ "reward", "choice" }) do
        local n = kind == "reward" and GetNumQuestRewards() or GetNumQuestChoices()
        for i = 1, n do
            local id = ItemId(GetQuestItemLink(kind, i))
            if id then
                Learned("Q" .. title .. ":" .. id,
                    { t = "Q", title = title, zone = zone, item = id, how = kind == "reward" and 1 or 2 })
            end
        end
    end
end

------------------------------------------------------------------------
-- lookups used by Sources.lua and the window
------------------------------------------------------------------------
function LC.LearnedFor(id)
    local list
    local function put(e) list = list or {}; list[#list + 1] = e end
    for npc in pairs(itemMobs[id] or {}) do
        local m = mobs[npc]
        put({ kind = "L", name = m.name, zone = m.zone, count = m.items[id], kills = m.kills, shared = m.shared })
    end
    for _, v in pairs(itemVendors[id] or {}) do
        put({ kind = "V", name = v.name, zone = v.zone, shared = v.shared })
    end
    for title, q in pairs(itemQuests[id] or {}) do
        put({ kind = "Q", name = title, zone = q.zone, choice = q.choice, shared = q.shared })
    end
    return list
end

-- Bosses learned from kills, for the Dungeons tab: mobs looted inside a dungeon that are a world boss,
-- skull level, a rare that's new to pfQuest or drops a blue (Reborn's Dootch in the Stockade), or that
-- pfQuest ranks Boss and drops a blue. Plain elites never count on their own, however good their loot:
-- /codex boss adds (or removes) one by hand (LootCodexDB.bossMarks, npc -> true in / false out).
-- Records from before 1.6 have no instance: their zone stands in.
function LC.LearnedBosses()
    local out = {}
    local units = pfDB and pfDB.units and pfDB.units.data
    local marks = LootCodexDB and LootCodexDB.bossMarks or {}
    for npc, m in pairs(mobs) do
        local where = m.inst or m.zone
        if type(npc) == "number" and where and where ~= "" and marks[npc] ~= false then
            local blue = false
            for id in pairs(m.items) do
                local r = LC.Item and LC.Item(id)
                local q, slot
                if r then q, slot = r[2], r[7] else
                    local _, _, iq, _, _, _, _, _, equip = GetItemInfo(id)
                    q, slot = iq, equip and equip ~= "" and 1 or 0
                end
                if (q or 0) >= 3 and (slot or 0) ~= 0 then blue = true end
            end
            local u = units and units[npc]
            -- a rare spawn counts when it's new to pfQuest (Reborn's, like Dootch) or drops a blue
            local boss = marks[npc] or m.cls == "w" or m.cls == "s"
                or (m.cls == "r" and (blue or (units and not u)))
                or (blue and u and u.rnk == "3")
            if boss then
                out[#out + 1] = { npc = npc, name = m.name, inst = where, inInstance = m.inst ~= nil, rare = m.cls == "r",
                    marked = marks[npc],
                    kills = m.kills, items = m.items,
                    shared = m.shared, new = units ~= nil and not u }
            end
        end
    end
    return out
end

-- /codex boss: flips whether npc is listed as a boss. Returns the new state, the mob's name and where
-- it was looted (nil when nobody has looted it yet: it shows up after the first kill).
function LC.ToggleBossMark(npc, name)
    LootCodexDB.bossMarks = LootCodexDB.bossMarks or {}
    local listed = false
    for _, b in ipairs(LC.LearnedBosses()) do if b.npc == npc then listed = true end end
    LootCodexDB.bossMarks[npc] = not listed
    if LC.ForgetLearnedBosses then LC.ForgetLearnedBosses() end
    local m = mobs[npc]
    return not listed, m and m.name or name, m and (m.inst or m.zone)
end

LC.NpcId = NpcId

-- what this account (and anyone sharing) has looted from one creature: {name, zone, kills, items={id=count}}
function LC.LearnedMob(npc) return mobs[npc] end

function LC.LearnedHas(id, kind)
    if kind == "L" then return itemMobs[id] ~= nil end
    if kind == "V" then return itemVendors[id] ~= nil end
    if kind == "Q" then return itemQuests[id] ~= nil end
    return false
end

function LC.LearnedCounts() return counts end

-- drop everything other players sent (optionally only one of them), and stop listening to them
function LC.ForgetShared(who)
    for key, r in pairs(log.rec) do
        if r.src and (not who or r.src:lower() == who:lower()) then log.rec[key] = nil end
    end
    if who then log.ignore[who] = true end
    Reindex()
end

------------------------------------------------------------------------
-- startup
------------------------------------------------------------------------
-- version 1 logs kept totals per mob, which can't be merged without double counting;
-- turn them into one record per kill so nothing already recorded is lost
local function Upgrade()
    if log.version == 2 then return end
    local rec = {}
    local now = time()
    for npc, m in pairs(log.mobs or {}) do
        local per = {}
        for i = 1, m.kills or 0 do per[i] = {} end
        for id, n in pairs(m.items or {}) do
            for i = 1, math.min(n, #per) do table.insert(per[i], id) end
        end
        for i, ids in ipairs(per) do
            rec["Kold:" .. npc .. ":" .. i] = { t = "K", npc = npc, name = m.name, zone = m.zone,
                items = table.concat(ids, ","), rt = now }
        end
    end
    for npc, v in pairs(log.vendors or {}) do
        for id in pairs(v.items or {}) do
            rec["V" .. npc .. ":" .. id] = { t = "V", npc = npc, name = v.name, zone = v.zone, item = id, rt = now }
        end
    end
    for title, q in pairs(log.quests or {}) do
        for id, how in pairs(q.items or {}) do
            rec["Q" .. title .. ":" .. id] = { t = "Q", title = title, zone = q.zone, item = id, how = how, rt = now }
        end
    end
    log.mobs, log.vendors, log.quests = nil, nil, nil
    log.rec = rec
    log.version = 2
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= "TMPZ-LootCodex" then return end
        LootCodexLog = LootCodexLog or { version = 2 }
        log = LootCodexLog
        Upgrade()
        log.realm = log.realm or GetRealmName()
        log.rec = log.rec or {}
        log.ignore = log.ignore or {}
        shared = LootCodexShared and LootCodexShared.rec or {}
        Reindex()
        self:RegisterEvent("LOOT_OPENED")
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("QUEST_DETAIL")
        self:RegisterEvent("QUEST_COMPLETE")
        self:RegisterEvent("TRAINER_SHOW")
        self:RegisterEvent("PLAYER_LOGOUT")          -- also fires on /reload
        if LC.SyncStart then LC.SyncStart(log) end
        return
    end
    if event == "PLAYER_LOGOUT" then
        FlushEmpty()     -- saved now, shared at the next login's catch-up
        return
    end
    if LootCodexDB and LootCodexDB.record == false then return end
    if event == "LOOT_OPENED" then
        OnLoot()
    elseif event == "MERCHANT_SHOW" then
        OnMerchant()
    elseif event == "TRAINER_SHOW" then
        OnTrainer()
    else
        OnQuest()
    end
end)

local flushWait = EMPTY_FLUSH
ev:SetScript("OnUpdate", function(_, elapsed)
    flushWait = flushWait - elapsed
    if flushWait > 0 then return end
    flushWait = EMPTY_FLUSH
    if log then FlushEmpty() end
end)
LC.FlushEmptyKills = FlushEmpty
