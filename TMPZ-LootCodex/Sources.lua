-- Where an item comes from. Four places are combined:
--   pfQuest's database (pfDB), read live when pfQuest is installed -- mob drops, objects, vendors
--   LootCodexSources (SourcesData.lua, generated) -- crafting, AtlasLoot bosses/reputation/events,
--     stock TrinityCore quest rewards, and which dungeon a mob lives in
--   LootCodexLog (Recorder.lua) -- what this account has actually seen drop, sold or rewarded
-- Nothing is copied out of pfQuest, so Loot Codex works (with fewer sources) without it.

LootCodex = LootCodex or {}
local LC = LootCodex

local RANK = { ["1"] = "Elite", ["2"] = "Rare Elite", ["3"] = "Boss", ["4"] = "Rare" }
local WORLD_DROP_UNITS = 30   -- a reference table this big is a world drop, not a named mob
local TIP_LINES, TIP_LINES_FULL = 6, 15
local BOSS_PREFIX = { [2] = "World boss: ", [3] = "Reputation: ", [4] = "Event: ", [5] = "PvP: " }

-- display order: drops, then crafting, quests, vendors, reputation/events/PvP
local GROUP = { U = 1, O = 1, W = 1, B = 1, L = 1, C = 2, Q = 3, V = 4, R = 5 }

local cache = {}

-- the key held for the longer lists (and, with the mouse wheel, to scroll creature drops); set in Settings
local MORE_KEYS = {
    CTRL = { "Ctrl", function() return IsControlKeyDown() end },
    ALT = { "Alt", function() return IsAltKeyDown() end },
}
function LC.MoreKey()
    local k = LootCodexDB and LootCodexDB.moreKey
    return MORE_KEYS[k] and k or "CTRL"
end
function LC.MoreKeyDown() return MORE_KEYS[LC.MoreKey()][2]() end
function LC.MoreKeyName() return MORE_KEYS[LC.MoreKey()][1] end

local function Static() return LootCodexSources or {} end

local function HasPf()
    return pfDB and pfDB.items and pfDB.items.data and pfDB.units and pfDB.units.data and true or false
end
LC.HasPfQuest = HasPf

function LC.ForgetSources(id)
    if id then cache[id] = nil else wipe(cache) end
end

local function Name(db, id)
    local t = pfDB[db]
    if not t then return nil end
    local names = t.loc or t[GetLocale()] or t.enUS
    return names and names[id]
end

-- the zone most of a unit's or object's spawns are in
local function MainZone(coords)
    if not coords then return nil end
    local count, best, bestN = {}, nil, 0
    for _, c in pairs(coords) do
        local z = c[3]
        if z then
            count[z] = (count[z] or 0) + 1
            if count[z] > bestN then best, bestN = z, count[z] end
        end
    end
    return best and Name("zones", best)
end

local function ItemName(id)
    local name = GetItemInfo(id)
    if name then return name end
    local r = LootCodexData and LootCodexData.items[id]
    return r and r[1] or ("item " .. id)
end

function LC.GetSources(id)
    if cache[id] then return cache[id] end

    local list, seen, names = {}, {}, {}
    local S = Static()

    local function add(key, entry)
        local old = seen[key]
        if old then
            if (entry.chance or 0) > (old.chance or 0) then old.chance = entry.chance end
            return old
        end
        seen[key] = entry
        list[#list + 1] = entry
        if entry.name then names[entry.name:lower()] = entry end
        return entry
    end

    -- pfQuest
    if HasPf() then
        local item = pfDB.items.data[id]
        local function addUnit(uid, chance, kind)
            local name = Name("units", uid)
            if not name then return end
            local u = pfDB.units.data[uid]
            local zone = u and MainZone(u.coords) or (S.unitzone and S.unitzone[uid])
            add((kind or "U") .. uid, { kind = kind or "U", name = name, chance = chance,
                zone = zone, lvl = u and u.lvl, rank = u and RANK[u.rnk] })
        end
        local function addObject(oid, chance)
            local name = Name("objects", oid)
            if not name then return end
            local o = pfDB.objects and pfDB.objects.data[oid]
            add("O" .. oid, { kind = "O", name = name, chance = chance, zone = o and MainZone(o.coords) })
        end
        if item then
            if item.U then
                for uid, chance in pairs(item.U) do
                    if chance > 0 then addUnit(uid, chance) end
                end
            end
            if item.O then
                for oid, chance in pairs(item.O) do
                    if chance > 0 then addObject(oid, chance) end
                end
            end
            if item.R and pfDB.refloot and pfDB.refloot.data then
                for ref, chance in pairs(item.R) do
                    local r = pfDB.refloot.data[ref]
                    local c = chance > 0 and chance or nil
                    if r and r.U then
                        local n = 0
                        for _ in pairs(r.U) do n = n + 1 end
                        if n > WORLD_DROP_UNITS then
                            add("W" .. ref, { kind = "W", name = "World drop", count = n, chance = c })
                        else
                            for uid in pairs(r.U) do addUnit(uid, c) end
                        end
                    end
                    if r and r.O then
                        for oid in pairs(r.O) do addObject(oid, c) end
                    end
                end
            end
            if item.V then
                for uid in pairs(item.V) do addUnit(uid, nil, "V") end
            end
        end
    end

    -- AtlasLoot: bosses (skipped when pfQuest already named the same mob), reputation, events, PvP
    for _, b in ipairs(S.boss and S.boss[id] or {}) do
        local who, where, chance, kind = b[1], b[2], b[3], b[4]
        if kind == 1 then
            local existing = who ~= "" and names[who:lower()]
            if existing then
                existing.zone = existing.zone or where
                if (existing.chance or 0) == 0 and chance > 0 then existing.chance = chance end
            else
                add("B" .. who .. where, { kind = "B", name = who ~= "" and who or where,
                    zone = who ~= "" and where or nil, chance = chance > 0 and chance or nil })
            end
        else
            add("R" .. kind .. where, { kind = kind == 2 and "B" or "R", name = BOSS_PREFIX[kind] .. where,
                chance = chance > 0 and chance or nil })
        end
    end

    -- crafting
    for _, c in ipairs(S.craft and S.craft[id] or {}) do
        -- c = {profession, learn rank (0 = unknown), recipe item, reagents, yellow, grey}
        -- the real level comes from the recipe item or from a trainer seen in game; the client's
        -- files only know when it turns yellow, which Epoch's trainers don't always follow
        local learn = c[2] > 0 and c[2] or (LC.TrainerReq and LC.TrainerReq(c[1], id))
        add("C" .. c[1], { kind = "C", name = c[1], learn = learn, yellow = c[5],
            recipe = c[3] ~= 0 and c[3] or nil, reagents = c[4] })
    end

    -- quests: stock TrinityCore data first, then anything this account has seen (which overrides it)
    for _, q in ipairs(S.quest and S.quest[id] or {}) do
        add("Q" .. q[1], { kind = "Q", name = q[1], lvl = q[2], zone = q[3] ~= "" and q[3] or nil,
            choice = q[4] == 1, stock = true })
    end

    -- what this account has seen
    local log = LC.LearnedFor and LC.LearnedFor(id)
    if log then
        for _, e in ipairs(log) do
            if e.kind == "Q" then
                local q = add("Q" .. e.name, { kind = "Q", name = e.name, zone = e.zone, choice = e.choice })
                q.stock, q.seen, q.shared = nil, true, e.shared
            elseif e.kind == "V" then
                local existing = names[e.name:lower()]
                if not (existing and existing.kind == "V") then
                    add("LV" .. e.name, { kind = "V", name = e.name, zone = e.zone, seen = true, shared = e.shared })
                end
            else
                local existing = names[e.name:lower()]
                local entry = existing or add("L" .. e.name, { kind = "L", name = e.name, zone = e.zone })
                entry.seen, entry.shared = true, e.shared
                entry.looted, entry.kills = e.count, e.kills
                if not existing or not existing.chance then entry.chance = 100 * e.count / e.kills end
            end
        end
    end

    table.sort(list, function(a, b)
        local ga, gb = GROUP[a.kind] or 9, GROUP[b.kind] or 9
        if ga ~= gb then return ga < gb end
        if (a.chance or 0) ~= (b.chance or 0) then return (a.chance or 0) > (b.chance or 0) end
        return a.name < b.name
    end)

    cache[id] = list
    return list
end

-- for the browser's "Source" filter: cheap checks that don't build the full list
function LC.HasSourceKind(id, want)
    local S = Static()
    if want == "craft" then return S.craft and S.craft[id] ~= nil end
    if want == "quest" then return (S.quest and S.quest[id] ~= nil) or (LC.LearnedHas and LC.LearnedHas(id, "Q")) end
    if want == "boss" or want == "rep" or want == "event" or want == "pvp" then
        local kinds = want == "boss" and { [1] = true, [2] = true } or
            { [want == "rep" and 3 or want == "event" and 4 or 5] = true }
        for _, b in ipairs(S.boss and S.boss[id] or {}) do
            if kinds[b[4]] then return true end
        end
        return false
    end
    local pf = HasPf() and pfDB.items.data[id]
    if want == "vendor" then return (pf and pf.V ~= nil) or (LC.LearnedHas and LC.LearnedHas(id, "V")) end
    if want == "drop" then
        if pf and (pf.U or pf.O or pf.R) then return true end
        for _, b in ipairs(S.boss and S.boss[id] or {}) do
            if b[4] <= 2 then return true end
        end
        return LC.LearnedHas and LC.LearnedHas(id, "L") or false
    end
    if want == "none" then
        return #LC.GetSources(id) == 0
    end
    return true
end

local function Chance(c)
    if not c then return "" end
    if c >= 10 then return string.format("%d%%", c + 0.5) end
    if c >= 1 then return string.format("%.1f%%", c) end
    return string.format("%.2f%%", c)
end

-- quests the original Project Epoch data (pfQuest + pfQuest-epoch) doesn't know: likely Reborn's
local questTitles
local function IsRebornQuest(title)
    if not (pfDB and pfDB.quests and pfDB.quests.loc) then return false end
    if not questTitles then
        questTitles = {}
        for _, q in pairs(pfDB.quests.loc) do
            if type(q) == "table" and q.T then questTitles[q.T] = true end
        end
    end
    return not questTitles[title]
end
LC.IsRebornQuest = IsRebornQuest

local function Describe(s)
    local bits = {}
    local left, right = s.name, Chance(s.chance)
    if s.kind == "W" then
        return "World drop", s.count .. " creatures" .. (s.chance and (", " .. Chance(s.chance)) or "")
    elseif s.kind == "V" then
        left, right = "Vendor: " .. s.name, ""
    elseif s.kind == "O" then
        left = s.name .. " (object)"
    elseif s.kind == "C" then
        if s.learn then
            left = "Crafted: " .. s.name .. " (skill " .. s.learn .. ")"
        else
            left = "Crafted: " .. s.name .. " (trainer" .. (s.yellow and (", yellow at " .. s.yellow) or "") .. ")"
        end
        right = ""
        if s.recipe then bits[#bits + 1] = "needs " .. ItemName(s.recipe) end
    elseif s.kind == "Q" then
        left = "Quest: " .. s.name
        if s.seen and not s.stock and IsRebornQuest(s.name) then left = left .. " |cffff9933(Reborn)|r" end
        right = s.choice and "choice" or "reward"
        if s.stock then right = right .. "*" end
    end
    if s.kind ~= "C" then
        if s.lvl then bits[#bits + 1] = "Lv " .. s.lvl end
        if s.rank then bits[#bits + 1] = s.rank end
        if s.zone then bits[#bits + 1] = s.zone end
    end
    -- green: seen by you; blue: includes what guild/group members' Loot Codex shared
    local seenColor = s.shared and "|cff66ccff" or "|cff88ff88"
    if s.looted then
        right = right .. string.format(" %s(%d/%d)|r", seenColor, s.looted, s.kills)
    elseif s.seen and s.kind ~= "Q" then
        right = right .. " " .. seenColor .. (s.shared and "shared" or "seen") .. "|r"
    end
    if #bits > 0 then left = left .. "  |cff888888" .. table.concat(bits, ", ") .. "|r" end
    return left, right
end

-- one source as a single line of text (the window's Wishlist tab)
function LC.DescribeSource(s)
    local left, right = Describe(s)
    return right ~= "" and (left .. "  " .. right) or left
end

local function Reagents(s)
    if not s.reagents or s.reagents == "" then return nil end
    local parts = {}
    for rid, n in s.reagents:gmatch("(%d+):(%d+)") do
        parts[#parts + 1] = n .. "x " .. ItemName(tonumber(rid))
    end
    return "    " .. table.concat(parts, ", ")
end

-- Appends "Where to get it" lines to any tooltip. full = show more.
-- Appends "Where to get it" lines to any tooltip. full = the longer list (the "more" key is held,
-- or it's the pinned chat-link tooltip). A longer list than fits is scrollable: tip.lcScroll
-- remembers where its lines are so LC.ScrollItemTip can rewrite them in place.
local scrollPos = {}            -- tooltip -> { id, offset }

function LC.AddSourceLines(tip, id, full)
    tip.lcScroll = nil
    local list = LC.GetSources(id)
    if not list or #list == 0 then return end
    full = full or LC.MoreKeyDown()
    local max = full and TIP_LINES_FULL or TIP_LINES
    local scrolling = full and #list > max
    local pos = scrollPos[tip]
    if not pos or pos.id ~= id then
        pos = { id = id, offset = 0 }
        scrollPos[tip] = pos
    end
    local first = 1
    if scrolling then
        pos.offset = math.max(0, math.min(pos.offset, #list - max))
        first = pos.offset + 1
    end
    local last = math.min(#list, first + max - 1)

    tip:AddLine(" ")
    if scrolling then
        tip:AddLine(string.format("Where to get it (%d-%d of %d):", first, last, #list), 0.2, 0.8, 1)
        tip.lcScroll = { list = list, header = tip:NumLines(), max = max, pos = pos }
    else
        tip:AddLine("Where to get it:", 0.2, 0.8, 1)
    end
    local stock = false
    for i = first, last do
        local s = list[i]
        local left, right = Describe(s)
        tip:AddDoubleLine(left, right, 1, 1, 1, 1, 0.82, 0)
        -- reagents get their own line, except while scrolling, where every entry must be one line
        if full and not scrolling and s.kind == "C" then
            local r = Reagents(s)
            if r then tip:AddLine(r, 0.6, 0.6, 0.6) end
        end
    end
    for _, s in ipairs(list) do
        if s.stock then stock = true end
    end
    if #list > max then
        if not full then
            tip:AddLine(string.format("+%d more (hold %s)", #list - max, LC.MoreKeyName()), 0.6, 0.6, 0.6)
        elseif LC.WheelBound and LC.WheelBound() then
            tip:AddLine(LC.MoreKeyName() .. " + mouse wheel to scroll", 0.6, 0.6, 0.6)
        end
    end
    if stock then
        tip:AddLine("* quest data from standard WoW; Epoch may differ", 0.5, 0.5, 0.5)
    end
end

-- moves a scrollable "Where to get it" list by delta lines, rewriting the lines already shown
function LC.ScrollItemTip(tip, delta)
    local sc = tip.lcScroll
    if not sc or not tip:IsShown() then return false end
    local list, max, pos = sc.list, sc.max, sc.pos
    local new = math.max(0, math.min(pos.offset + delta, #list - max))
    if new == pos.offset then return true end
    pos.offset = new
    local first = new + 1
    local last = math.min(#list, first + max - 1)
    local name = tip:GetName()
    _G[name .. "TextLeft" .. sc.header]:SetText(string.format("Where to get it (%d-%d of %d):", first, last, #list))
    for i = first, last do
        local line = sc.header + (i - first) + 1
        local left, right = Describe(list[i])
        _G[name .. "TextLeft" .. line]:SetText(left)
        _G[name .. "TextRight" .. line]:SetText(right)
    end
    tip:Show()                  -- re-fits the width; it's already up, so no flicker
    return true
end

-- every item tooltip in the game gets the source lines, once per showing
local function Hook(tip)
    tip:HookScript("OnTooltipSetItem", function(self)
        if self.lootCodexDone or not LootCodexDB then return end
        local _, link = self:GetItem()
        local id = link and tonumber(link:match("item:(%d+)"))
        if not id then return end
        self.lootCodexDone = true
        if LC.LearnFromTooltip then LC.LearnFromTooltip(self, id, link) end
        if self == ItemRefTooltip and LC.NoteRecent then LC.NoteRecent(id) end
        if LC.IsWished and LC.IsWished(id) then self:AddLine(LC.STAR .. " On your wishlist", 1, 0.82, 0) end
        local rec = LC.Item and LC.Item(id)
        if rec and LC.IsRebornItem(rec) then self:AddLine("Epoch Reborn addition", 1, 0.6, 0.2) end
        if LC.AddUpgradeLine then LC.AddUpgradeLine(self, id) end
        if LootCodexDB.tooltip then LC.AddSourceLines(self, id, self == ItemRefTooltip) end
        self:Show()
    end)
    tip:HookScript("OnTooltipCleared", function(self)
        self.lootCodexDone = nil
        self.lcScroll = nil
    end)
end

function LC.HookTooltips()
    Hook(GameTooltip)
    Hook(ItemRefTooltip)
    -- the pinned chat-link tooltip sits still under the mouse, so the plain wheel scrolls it too
    ItemRefTooltip:EnableMouseWheel(true)
    ItemRefTooltip:HookScript("OnMouseWheel", function(self, delta) LC.ScrollItemTip(self, -delta) end)
end
