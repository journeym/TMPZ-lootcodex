-- Learns items the database doesn't have yet (new Epoch items after a patch): any item tooltip
-- for an unknown item is read and saved to LootCodexLog.items, added to the browser straight
-- away, and its ID is shared with guild/group, whose clients ask the server themselves.
-- Toggle: LootCodexDB.learnItems.

LootCodex = LootCodex or {}
local LC = LootCodex

local F_CUSTOM, F_HIDDEN, F_REBORN = 1, 2, 4

-- GetItemStats keys -> the short codes build_data_addon.py uses
local STAT_KEYS = {
    ITEM_MOD_STAMINA_SHORT = "sta", ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_SPELL_POWER_SHORT = "sp",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sdmg",
    ITEM_MOD_POWER_REGEN0_SHORT = "mp5", ITEM_MOD_HEALTH_REGEN_SHORT = "hp5", ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", ITEM_MOD_BLOCK_VALUE_SHORT = "bv", ITEM_MOD_CRIT_RATING_SHORT = "critr",
    ITEM_MOD_HIT_RATING_SHORT = "hitr", ITEM_MOD_HASTE_RATING_SHORT = "haster",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defr", ITEM_MOD_DODGE_RATING_SHORT = "dodger",
    ITEM_MOD_PARRY_RATING_SHORT = "parryr", ITEM_MOD_BLOCK_RATING_SHORT = "blockr",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "exp", ITEM_MOD_RESILIENCE_RATING_SHORT = "resil",
    ITEM_MOD_SPELL_PENETRATION_SHORT = "spen", ITEM_MOD_MANA_SHORT = "mana",
    RESISTANCE0_NAME = "armor", RESISTANCE1_NAME = "rholy", RESISTANCE2_NAME = "rfire",
    RESISTANCE3_NAME = "rnature", RESISTANCE4_NAME = "rfrost", RESISTANCE5_NAME = "rshadow",
    RESISTANCE6_NAME = "rarcane",
}
-- classic-style "Equip:" lines GetItemStats doesn't report
local EQUIP = {
    { "critical strike with melee and ranged attacks by (%d+)%%", { "crit" } },
    { "critical strike with spells by (%d+)%%", { "scrit" } },
    { "critical strike with all spells and attacks by (%d+)%%", { "crit", "scrit" } },
    { "chance to hit with melee and ranged attacks by (%d+)%%", { "hit" } },
    { "chance to hit with spells by (%d+)%%", { "shit" } },
    { "chance to hit with all spells and attacks by (%d+)%%", { "hit", "shit" } },
    { "Increased Defense %+(%d+)", { "def" } },
    { "chance to dodge an attack by (%d+)%%", { "dodge" } },
    { "chance to parry an attack by (%d+)%%", { "parry" } },
    { "chance to block attacks with a shield by (%d+)%%", { "block" } },
    { "casting speed .* by (%d+)%%", { "shaste" } },
}
-- the six schools build_data_addon.py reads ("magical spells" is plain spell power, not a school)
local SCHOOLS = { Shadow = true, Fire = true, Frost = true, Arcane = true, Nature = true, Holy = true }
local HIDE_NAME = { "deprecated", "^monster %-", "%[ph%]", "%f[%a]test%f[%A]", "%f[%a]qa%f[%A]", "unused" }

local queue, tries = {}, {}
local scan = CreateFrame("GameTooltip", "LootCodexLearnTip", nil, "GameTooltipTemplate")

local function Log() return LootCodexLog end

local function EnumIndex(kind, name)
    if not name or name == "" then return 0 end
    local list = LootCodexData.enum[kind]
    for i, v in ipairs(list) do if v == name then return i end end
    list[#list + 1] = name
    return #list
end

local function TooltipLines(tip)
    local name, lines = tip:GetName(), {}
    for i = 2, tip:NumLines() do
        local l = _G[name .. "TextLeft" .. i]
        local r = _G[name .. "TextRight" .. i]
        local left = l and l:GetText() or ""
        local right = r and r:IsShown() and r:GetText() or nil
        lines[#lines + 1] = right and right ~= "" and (left .. "\t" .. right) or left
    end
    return table.concat(lines, "\n")
end

-- builds a record in the same layout as LootCodex_Data
local function Capture(id, link, text)
    local name, _, quality, ilvl, req, class, subclass, _, equipLoc, texture = GetItemInfo(link or ("item:" .. id))
    if not name then return nil end
    local stats = {}
    for k, v in pairs(GetItemStats(link or ("item:" .. id)) or {}) do
        local code = STAT_KEYS[k]
        if code and v ~= 0 then stats[code] = (stats[code] or 0) + v end
    end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line:find("^Equip:") then
            for _, e in ipairs(EQUIP) do
                local n = line:match(e[1])
                if n then for _, code in ipairs(e[2]) do stats[code] = stats[code] or tonumber(n) end end
            end
            local school, n = line:match("damage done by (%a+) spells and effects by up to (%d+)")
            if school and SCHOOLS[school] then
                stats["s" .. school:lower()] = (stats["s" .. school:lower()] or 0) + tonumber(n)
            end
        end
    end
    local flags = F_CUSTOM
    -- in Epoch's range but unknown to the original Epoch data (pfQuest-epoch): likely Reborn's
    if id >= 60000 and not (pfDB and pfDB.items and pfDB.items.loc and pfDB.items.loc[id]) then
        flags = flags + F_REBORN
    end
    local lname = name:lower()
    local hidden = (req or 0) > 60 or (ilvl or 0) > 92
    for _, pat in ipairs(HIDE_NAME) do if lname:find(pat) then hidden = true end end
    if hidden then flags = flags + F_HIDDEN end
    return { name, quality or 1, ilvl or 0, req or 0, EnumIndex("class", class), EnumIndex("subclass", subclass),
        EnumIndex("slot", equipLoc), (texture or ""):match("([^\\]+)$") or "", stats, text, flags }
end

local function Store(id, rec, from)
    local log = Log()
    log.items = log.items or {}
    log.itemTimes = log.itemTimes or {}
    log.items[id] = rec
    log.itemTimes[id] = time()
    LC.AddLearnedItem(id, rec)
    if not from and LC.ShareLive then LC.ShareLive("N^" .. id) end
    if type(from) == "string" and LC.NoteShared then LC.NoteShared({ text = "New item: " .. rec[1] }, from) end
end

local function Enabled()
    return LootCodexDB and LootCodexDB.learnItems and LootCodexData and LC.Item and Log()
end

-- item tooltips call this (Sources.lua) before adding their own lines
function LC.LearnFromTooltip(tip, id, link)
    if not Enabled() or LC.Item(id) then return end
    local rec = Capture(id, link, TooltipLines(tip))
    if rec then Store(id, rec) end
end

-- an ID another player's Loot Codex learned: ask the server, record it when the answer arrives
local fetching                 -- { added, learned } while shared item IDs are being fetched

function LC.LearnFromNetwork(id, from)
    if not Enabled() or LC.Item(id) or queue[id] then return end
    if not fetching then
        fetching = { added = 0, learned = 0 }
        LC.ShareActivity("fetching new items found by " .. (type(from) == "string" and from or "your guild")
            .. " from the server...")
    end
    fetching.added = fetching.added + 1
    queue[id], tries[id] = from or true, 0
end

-- adds saved items to the database when it loads (LootCodex.lua calls this)
function LC.MergeLearnedItems()
    local log = Log()
    for id, rec in pairs(log and log.items or {}) do LC.AddLearnedItem(id, rec) end
end

function LC.LearnedItemTimes() return Log() and Log().itemTimes or {} end

local ticker = CreateFrame("Frame")
local elapsed, loadAt = 0, nil
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 then return end
    elapsed = 0
    -- the item data is needed for "do we know this?" and for upgrade scores; load it shortly after
    -- login, out of combat, instead of on the first tooltip
    if loadAt and GetTime() >= loadAt and not InCombatLockdown() then
        loadAt = nil
        if LootCodexDB and (LootCodexDB.learnItems or LootCodexDB.upgrades) and LC.EnsureData() then
            LC.Activity(string.format("item database loaded: %d items.", #LC.AllItemIds()))
        end
    end
    for id, from in pairs(queue) do
        if LC.Item(id) then
            queue[id] = nil
        elseif GetItemInfo(id) then
            scan:SetOwner(WorldFrame, "ANCHOR_NONE")
            scan:SetHyperlink("item:" .. id)
            local rec = Capture(id, nil, TooltipLines(scan))
            scan:Hide()
            if rec then
                Store(id, rec, from)
                if fetching then fetching.learned = fetching.learned + 1 end
            end
            queue[id] = nil
        else
            tries[id] = tries[id] + 1
            if tries[id] > 5 then
                queue[id] = nil                          -- the server doesn't know it either
            else
                scan:SetOwner(WorldFrame, "ANCHOR_NONE")
                scan:SetHyperlink("item:" .. id)        -- asks the server
                scan:Hide()
            end
        end
        break                                            -- one item a second is plenty
    end
    if fetching and not next(queue) then
        LC.ShareActivity(string.format("fetched %d new item%s (now in the window).", fetching.learned,
            fetching.learned == 1 and "" or "s"))
        fetching = nil
    end
end)
-- PLAYER_LOGIN runs while the loading screen is still up (at login and on every /reload), so the
-- database's ~0.3-0.5 s of loading is hidden there instead of freezing the game 20 s into play.
-- (WoW keeps nothing between sessions except SavedVariables, which are re-read the same way, so
-- there is no faster "cache" to load it from: the loading screen is the cheapest place to pay.)
ticker:RegisterEvent("PLAYER_LOGIN")
ticker:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    loadAt = GetTime()
    if LootCodexDB and (LootCodexDB.learnItems or LootCodexDB.upgrades) and LC.EnsureData() then
        loadAt = nil
        LC.Activity(string.format("item database loaded: %d items.", #LC.AllItemIds()))
    end
end)

------------------------------------------------------------------------
-- Check for updates (Settings > Learning & Sharing, /codex update): asks the server about the IDs
-- around the top of Epoch's item range (new items) and about every Epoch item already known
-- (changed items), in the background. New and changed items are saved like learned ones.
--
-- The game keeps its own item cache (the Cache folder) and answers from it for items it has seen
-- before, so a changed item only shows up as changed once that cache has been refreshed.
------------------------------------------------------------------------
local CHECK_RATE = 16          -- server questions per second, the scanner's Fast speed
local PROBE_BELOW, PROBE_ABOVE = 2000, 500
local WAIT, TRIES = 3, 2       -- seconds to wait for an answer, and how often to ask

local check                    -- the running check, or nil

local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffTMPZ-LootCodex:|r " .. msg) end

local function StatsDiffer(a, b)
    for k, v in pairs(a) do if math.abs((b[k] or 0) - v) > 0.05 then return true end end
    for k, v in pairs(b) do if math.abs((a[k] or 0) - v) > 0.05 then return true end end
    return false
end

local function Changed(new, old)
    return new[1] ~= old[1] or new[2] ~= old[2] or new[3] ~= old[3] or new[4] ~= old[4] or StatsDiffer(new[9], old[9])
end

function LC.UpdateCheckProgress()
    if not check then return nil end
    return math.floor(100 * check.done / math.max(1, #check.list)), check.new, check.changed
end

function LC.StopUpdateCheck(quiet)
    if check and not quiet then Say("update check stopped.") end
    check = nil
    if LC.UpdateScanIndicator then LC.UpdateScanIndicator() end
end

function LC.StartUpdateCheck()
    if check then return end
    if not LC.EnsureData() then return end
    local list, top = {}, 60000
    for _, id in ipairs(LC.AllItemIds()) do
        if id > top and id < 200000 then top = id end
    end
    for id = top - PROBE_BELOW, top + PROBE_ABOVE do
        if not LC.Item(id) then list[#list + 1] = { id = id, new = true } end
    end
    for _, id in ipairs(LC.AllItemIds()) do
        local r = LC.Item(id)
        if r and LC.IsCustomItem(r) then list[#list + 1] = { id = id } end
    end
    check = { list = list, next = 1, pending = {}, done = 0, new = 0, changed = 0, names = {}, acc = 0 }
    if LC.UpdateScanIndicator then LC.UpdateScanIndicator() end
    LootCodexDB.lastUpdateCheck = time()
    local fresh = 0
    for _, e in ipairs(list) do if e.new then fresh = fresh + 1 end end
    Say(string.format("checking for updates in the background: %d possible new item IDs and %d known Epoch items"
        .. " (about %d min; pauses in combat).", fresh, #list - fresh, math.ceil(#list / CHECK_RATE / 60)))
end

local function Finish()
    local c = check
    check = nil
    local summary
    if c.new + c.changed == 0 then
        summary = "no new or changed items"
        Say("|cffffd100Update check finished:|r no new or changed items found. (If Epoch just patched and"
            .. " items look stale, exit WoW, delete its Cache folder, and check again.)")
    else
        summary = string.format("%d new, %d changed", c.new, c.changed)
        Say(string.format("|cffffd100Update check finished:|r |cff20ff20%d new|r and |cffffd100%d changed|r items,"
            .. " saved and in the window now.%s", c.new, c.changed,
            #c.names > 0 and (" e.g. " .. table.concat(c.names, ", ")) or ""))
    end
    -- a short line mid-screen too, since the check runs for minutes and chat may have moved on
    if UIErrorsFrame then UIErrorsFrame:AddMessage("TMPZ-LootCodex: update check finished (" .. summary .. ")", 1, 0.82, 0) end
    if LC.RefreshIfOpen then LC.RefreshIfOpen() end
    if LC.UpdateScanIndicator then LC.UpdateScanIndicator() end
end

local function Evaluate(e)
    if not GetItemInfo(e.id) then
        if e.tries < TRIES then
            e.tries, e.asked = e.tries + 1, GetTime()
            scan:SetOwner(WorldFrame, "ANCHOR_NONE")
            scan:SetHyperlink("item:" .. e.id)
            scan:Hide()
            return false                 -- ask again, keep waiting
        end
        return true                      -- the server doesn't have it
    end
    scan:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan:SetHyperlink("item:" .. e.id)
    local rec = Capture(e.id, nil, TooltipLines(scan))
    scan:Hide()
    if not rec then return true end
    if e.new then
        if not LC.Item(e.id) then
            Store(e.id, rec)
            check.new = check.new + 1
            if #check.names < 4 then check.names[#check.names + 1] = rec[1] end
        end
    else
        local old = LC.Item(e.id)
        if old and Changed(rec, old) then
            rec[11] = old[11]            -- keep the custom / hidden flags,
            rec[5], rec[6] = old[5], old[6]   -- and the worked-out types (the server says plain "Consumable")
            local log = Log()
            log.items = log.items or {}
            log.itemTimes = log.itemTimes or {}
            log.items[e.id], log.itemTimes[e.id] = rec, time()
            LC.ReplaceItem(e.id, rec)
            check.changed = check.changed + 1
            if #check.names < 4 then check.names[#check.names + 1] = rec[1] end
        end
    end
    return true
end

local runner = CreateFrame("Frame")
runner:SetScript("OnUpdate", function(_, dt)
    if not check or InCombatLockdown() then return end
    check.acc = check.acc + dt
    while check and check.acc >= 1 / CHECK_RATE do
        check.acc = check.acc - 1 / CHECK_RATE
        -- answer the oldest question that has had time to come back
        local head = check.pending[1]
        if head and GetTime() - head.asked >= WAIT then
            table.remove(check.pending, 1)
            if Evaluate(head) then
                check.done = check.done + 1
            else
                check.pending[#check.pending + 1] = head
            end
        end
        if not check then return end
        -- ask the next one
        local e = check.list[check.next]
        if e then
            check.next = check.next + 1
            e.tries, e.asked = 1, GetTime()
            if not GetItemInfo(e.id) then
                scan:SetOwner(WorldFrame, "ANCHOR_NONE")
                scan:SetHyperlink("item:" .. e.id)
                scan:Hide()
            end
            check.pending[#check.pending + 1] = e
        elseif #check.pending == 0 then
            Finish()
            return
        end
    end
end)

-- automatic check: at most once a day, a minute after logging in
local auto = CreateFrame("Frame")
auto:RegisterEvent("PLAYER_ENTERING_WORLD")
auto:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if not (LootCodexDB and LootCodexDB.autoUpdateCheck) then return end
    if time() - (LootCodexDB.lastUpdateCheck or 0) < 86400 then return end
    local wait = 60
    self:SetScript("OnUpdate", function(f, dt)
        wait = wait - dt
        if wait > 0 then return end
        f:SetScript("OnUpdate", nil)
        LC.StartUpdateCheck()
    end)
end)
