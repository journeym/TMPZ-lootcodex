-- Wishlist (per character), alerts when a wishlisted item drops, recently viewed items, and
-- "Show on map" through pfQuest, and alerts for creatures that drop a wishlisted item.
-- Toggles: LootCodexDB.wishAlerts, .wishMobAlerts, .wishMobSound, .trackRecent, .mapPins.

LootCodex = LootCodex or {}
local LC = LootCodex

local RECENT_MAX = 60
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14:14|t"
LC.STAR = STAR

local function CharKey() return (GetRealmName() or "") .. "-" .. (UnitName("player") or "") end

local function Store(key)
    LootCodexDB[key] = LootCodexDB[key] or {}
    local per = LootCodexDB[key][CharKey()]
    if not per then
        per = {}
        LootCodexDB[key][CharKey()] = per
    end
    return per
end

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffTMPZ-LootCodex:|r " .. msg) end

local function ItemLinkOrName(id)
    local _, link = GetItemInfo(id)
    if link then return link end
    local r = LC.Item(id)
    return r and ("[" .. r[1] .. "]") or ("item " .. id)
end

------------------------------------------------------------------------
-- wishlist
------------------------------------------------------------------------
function LC.Wishlist() return Store("wish") end
function LC.IsWished(id) return LootCodexDB and LootCodexDB.wish and Store("wish")[id] ~= nil end

function LC.ToggleWish(id)
    local w = Store("wish")
    if w[id] then
        w[id] = nil
        Print(ItemLinkOrName(id) .. " removed from your wishlist.")
    else
        w[id] = time()
        Print(ItemLinkOrName(id) .. " added to your wishlist.")
    end
    if LC.ForgetUnitDrops then LC.ForgetUnitDrops() end
    if LC.ForgetMobAlerts then LC.ForgetMobAlerts() end
    if LC.RefreshIfOpen then LC.RefreshIfOpen() end
end

local function Alert(id, where)
    if not (LootCodexDB and LootCodexDB.wishAlerts) then return end
    local msg = STAR .. " Wishlist item " .. where .. ": " .. ItemLinkOrName(id)
    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    PlaySound("RaidWarning")
    Print(msg)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("START_LOOT_ROLL")
ev:SetScript("OnEvent", function(self, event, arg)
    if not LootCodexDB or not LootCodexDB.wish then return end
    if event == "LOOT_OPENED" then
        for slot = 1, GetNumLootItems() do
            local link = LootSlotIsItem(slot) and GetLootSlotLink(slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id and LC.IsWished(id) then Alert(id, "in this loot") end
        end
    elseif event == "START_LOOT_ROLL" then
        local link = GetLootRollItemLink(arg)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and LC.IsWished(id) then Alert(id, "up for roll") end
    end
end)

------------------------------------------------------------------------
-- recently viewed: items opened from chat links and items looked at in the Loot Codex window
------------------------------------------------------------------------
function LC.Recent() return Store("recent") end

function LC.NoteRecent(id)
    if not (LootCodexDB and LootCodexDB.trackRecent) or not id then return end
    local list = Store("recent")
    for i = #list, 1, -1 do
        if list[i] == id then table.remove(list, i) end
    end
    table.insert(list, 1, id)
    while #list > RECENT_MAX do table.remove(list) end
end

function LC.ClearRecent()
    wipe(Store("recent"))
    if LC.RefreshIfOpen then LC.RefreshIfOpen() end
end

------------------------------------------------------------------------
-- show on map (pfQuest draws the pins; ours are tagged so they can be cleared on their own)
------------------------------------------------------------------------
local PIN_TAG = "TMPZ-LootCodex"

function LC.CanShowOnMap()
    return LootCodexDB and LootCodexDB.mapPins and pfMap and pfDatabase and pfDatabase.SearchItemID and true or false
end

-- pfQuest opens a zone by finding its name in the world map's zone list, so a zone that isn't on
-- the world map (dungeon interiors, sub-zones) silently leaves the map where it was. Only zones
-- the world map can open are picked here.
local worldMapZones
local function OnWorldMap(zone)
    if not worldMapZones then
        worldMapZones = {}
        for cid in pairs({ GetMapContinents() }) do
            for _, name in pairs({ GetMapZones(cid) }) do worldMapZones[name] = true end
        end
    end
    local name = pfDB.zones and pfDB.zones.loc and pfDB.zones.loc[zone]
    return name and worldMapZones[name] and true or false
end

local function UnitName_(uid) return pfDB.units.loc and pfDB.units.loc[uid] or "?" end
local function ObjectName(oid) return pfDB.objects and pfDB.objects.loc and pfDB.objects.loc[oid] or "?" end

-- every place a source spawns, as { zone, chance, spawns, who }
local function AddSpawns(out, coords, chance, who)
    local per = {}
    for _, c in pairs(coords or {}) do
        if c[3] then per[c[3]] = (per[c[3]] or 0) + 1 end
    end
    for zone, n in pairs(per) do out[#out + 1] = { zone = zone, chance = chance, spawns = n, who = who } end
end

-- Mobs inside dungeons have no world-map position, so a dungeon drop points at the zone with the
-- dungeon's entrance. Names as AtlasLoot and the client's Map.dbc spell them (both are used).
local ENTRANCES = {
    ["Ragefire Chasm"] = "Orgrimmar", ["Wailing Caverns"] = "The Barrens", ["The Deadmines"] = "Westfall",
    ["Deadmines"] = "Westfall", ["Shadowfang Keep"] = "Silverpine Forest", ["Blackfathom Deeps"] = "Ashenvale",
    ["The Stockade"] = "Stormwind City", ["Stormwind Stockade"] = "Stormwind City", ["Gnomeregan"] = "Dun Morogh",
    ["Razorfen Kraul"] = "The Barrens", ["Razorfen Downs"] = "The Barrens", ["Scarlet Monastery"] = "Tirisfal Glades",
    ["Scarlet Monestery"] = "Tirisfal Glades", ["Uldaman"] = "Badlands", ["Zul'Farrak"] = "Tanaris",
    ["Maraudon"] = "Desolace", ["Sunken Temple"] = "Swamp of Sorrows", ["The Temple of Atal'Hakkar"] = "Swamp of Sorrows",
    ["Blackrock Depths"] = "Searing Gorge", ["Blackrock Mountain"] = "Searing Gorge", ["Molten Core"] = "Searing Gorge",
    ["Blackrock Spire"] = "Burning Steppes", ["Lower Blackrock Spire"] = "Burning Steppes",
    ["Upper Blackrock Spire"] = "Burning Steppes", ["Blackwing Lair"] = "Burning Steppes", ["Dire Maul"] = "Feralas",
    ["Scholomance"] = "Western Plaguelands", ["Stratholme"] = "Eastern Plaguelands", ["Naxxramas"] = "Eastern Plaguelands",
    ["Onyxia's Lair"] = "Dustwallow Marsh", ["Onyxia (Level 80)"] = "Dustwallow Marsh", ["Zul'Gurub"] = "Stranglethorn Vale",
    ["Ruins of Ahn'Qiraj"] = "Silithus", ["Ahn'Qiraj Temple"] = "Silithus", ["Blasted Fortress"] = "Blasted Lands",
}

local function EntranceZone(dungeon)
    local zoneName = dungeon and ENTRANCES[dungeon]
    return zoneName and pfMap:GetMapIDByName(zoneName)
end

local function AddDungeon(out, dungeon, chance, who)
    local zone = EntranceZone(dungeon)
    if zone then
        out[#out + 1] = { zone = zone, chance = chance, spawns = 0, who = who, dungeon = dungeon }
    end
end

-- where to look for an item, best first: highest drop chance (vendors count as certain), then most spawns
local function ItemPlaces(id)
    local out = {}
    local unitzone = LootCodexSources and LootCodexSources.unitzone or {}
    -- Epoch's AtlasLoot bosses, including custom drops pfQuest doesn't know
    for _, b in ipairs(LootCodexSources and LootCodexSources.boss and LootCodexSources.boss[id] or {}) do
        if b[4] == 1 then AddDungeon(out, b[2], b[3], b[1] ~= "" and b[1] or b[2]) end
    end
    local item = pfDB.items.data[id]
    if not item then
        table.sort(out, function(a, b) return a.chance > b.chance end)
        return out
    end
    local units, objects = pfDB.units.data, pfDB.objects and pfDB.objects.data or {}
    for uid, chance in pairs(item.U or {}) do
        local u = units[uid]
        if u and u.coords and next(u.coords) then
            AddSpawns(out, u.coords, chance, UnitName_(uid))
        elseif unitzone[uid] then
            AddDungeon(out, unitzone[uid], chance, UnitName_(uid))
        end
    end
    for oid, chance in pairs(item.O or {}) do
        if objects[oid] then AddSpawns(out, objects[oid].coords, chance, ObjectName(oid)) end
    end
    for ref, chance in pairs(item.R or {}) do
        local r = pfDB.refloot and pfDB.refloot.data[ref]
        for uid in pairs(r and r.U or {}) do
            local u = units[uid]
            if u and u.coords and next(u.coords) then
                AddSpawns(out, u.coords, chance, UnitName_(uid))
            elseif unitzone[uid] then
                AddDungeon(out, unitzone[uid], chance, UnitName_(uid))
            end
        end
        for oid in pairs(r and r.O or {}) do
            if objects[oid] then AddSpawns(out, objects[oid].coords, chance, ObjectName(oid)) end
        end
    end
    for uid in pairs(item.V or {}) do
        if units[uid] then AddSpawns(out, units[uid].coords, 100, "Vendor: " .. UnitName_(uid)) end
    end
    table.sort(out, function(a, b)
        if a.chance ~= b.chance then return a.chance > b.chance end
        return a.spawns > b.spawns
    end)
    return out
end

local function Chance(c)
    if c >= 100 then return "" end
    if c <= 0 then return "" end
    return string.format(" (%s%%)", c >= 1 and string.format("%.1f", c) or string.format("%.2f", c))
end

-- opens the world map on the first place that can be shown; says in chat what it's showing
local function ShowBest(places, what)
    pfMap:UpdateNodes()
    for _, p in ipairs(places) do
        if OnWorldMap(p.zone) then
            pfMap:ShowMapID(p.zone)
            if p.dungeon then
                Print(string.format("%s%s is inside %s: showing %s, where the entrance is.", p.who, Chance(p.chance),
                    p.dungeon, pfDB.zones.loc[p.zone]))
            else
                Print("Showing " .. pfDB.zones.loc[p.zone] .. ": " .. p.who .. Chance(p.chance) .. ".")
            end
            return true
        end
    end
    if places[1] then
        Print(what .. " only comes from places the world map can't show (inside dungeons): "
            .. (places[1].who or "?") .. ".")
    else
        Print("pfQuest doesn't know where " .. what .. " comes from.")
    end
end


function LC.ShowItemOnMap(id, keep)
    if not LC.CanShowOnMap() then return end
    if not keep then pfMap:DeleteNode(PIN_TAG) end
    pfDatabase:SearchItemID(id, { addon = PIN_TAG })      -- pins for every source
    ShowBest(ItemPlaces(id), ItemLinkOrName(id))
end

function LC.ShowMobOnMap(npc, name)
    if not LC.CanShowOnMap() then return end
    pfMap:DeleteNode(PIN_TAG)
    pfDatabase:SearchMobID(npc, { addon = PIN_TAG })
    local places = {}
    AddSpawns(places, pfDB.units.data[npc] and pfDB.units.data[npc].coords, 100, name or UnitName_(npc))
    table.sort(places, function(a, b) return a.spawns > b.spawns end)
    ShowBest(places, name or "that creature")
end

-- pins every wishlist item, then opens the zone where the most of them are best found
function LC.ShowWishlistOnMap()
    if not LC.CanShowOnMap() then return end
    pfMap:DeleteNode(PIN_TAG)
    local votes, first = {}, {}
    for id in pairs(Store("wish")) do
        pfDatabase:SearchItemID(id, { addon = PIN_TAG })
        for _, p in ipairs(ItemPlaces(id)) do
            if OnWorldMap(p.zone) then
                votes[p.zone] = (votes[p.zone] or 0) + 1
                first[p.zone] = first[p.zone] or p
                break
            end
        end
    end
    local best, n = nil, 0
    for zone, v in pairs(votes) do if v > n then best, n = zone, v end end
    if best then
        pfMap:UpdateNodes()
        pfMap:ShowMapID(best)
        Print(string.format("Showing %s: the best place for %d of your wishlist items.", pfDB.zones.loc[best], n))
    else
        Print("pfQuest can't show anything on your wishlist on the world map.")
    end
end

function LC.ClearMapPins()
    if pfMap then
        pfMap:DeleteNode(PIN_TAG)
        pfMap:UpdateNodes()
    end
end

------------------------------------------------------------------------
-- creature alerts: targeting or fighting a mob that drops something on the wishlist puts a
-- raid-warning line on screen ("<mob> drops: [item] (chance)"), a chat line and a sound, and a
-- star on the target frame's portrait for as long as it's targeted.
--
-- Not spammy: each mob (by GUID) is looked at once, and the same kind of mob (NPC id) is announced
-- at most once every MOB_COOLDOWN seconds, so pulling a pack of six Defias only alerts once.
-- Changing the wishlist clears both, so a newly added item is announced straight away.
------------------------------------------------------------------------
local MOB_COOLDOWN = 300
local MOB_SHOWN = 3                -- items named in the alert; the rest are counted
local OURS = 0x3                   -- COMBATLOG_OBJECT_AFFILIATION_MINE | _PARTY: me, my pet, my party
local NPC = 0x800                  -- COMBATLOG_OBJECT_TYPE_NPC
local FRIENDLY = 0x10              -- COMBATLOG_OBJECT_REACTION_FRIENDLY

local lookedAt, lookedCount = {}, 0   -- GUID -> true
local announced = {}                  -- NPC id -> GetTime() of the last alert
local marker

local function DropsText(list)
    local parts = {}
    for i = 1, math.min(#list, MOB_SHOWN) do
        parts[i] = ItemLinkOrName(list[i].id) .. Chance(list[i].chance)
    end
    local s = table.concat(parts, ", ")
    if #list > MOB_SHOWN then s = s .. string.format(" and %d more", #list - MOB_SHOWN) end
    return s
end

-- returns the wished drops (or nil); announces them unless this mob or its kind was done recently
local function CheckMob(guid, name, force)
    if not guid or not LootCodexDB then return nil end
    if not force then
        if not LootCodexDB.wishMobAlerts or lookedAt[guid] then return nil end
        lookedAt[guid] = true
        lookedCount = lookedCount + 1
        if lookedCount > 3000 then wipe(lookedAt); lookedCount = 0 end
    end
    local npc = LC.NpcId and LC.NpcId(guid)
    local list = npc and LC.WishedDrops and LC.WishedDrops(npc, name)
    if not list then return nil end
    local now = GetTime()
    if not force and announced[npc] and now - announced[npc] < MOB_COOLDOWN then return list end
    announced[npc] = now
    local msg = STAR .. " " .. (name or "This creature") .. " drops " .. DropsText(list)
    RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    if LootCodexDB.wishMobSound then PlaySound("RaidWarning") end
    Print(msg)
    return list
end

-- the star on the target frame: shown while the target drops something wished, no cooldown
local function UpdateMarker()
    if not marker then
        if not TargetFrame then return end
        marker = CreateFrame("Frame", "LootCodexWishMarker", TargetFrame)   -- no mouse: never blocks clicks
        marker:SetFrameLevel(TargetFrame:GetFrameLevel() + 5)
        marker:SetSize(20, 20)
        marker:SetPoint("CENTER", TargetFramePortrait or TargetFrame, "BOTTOMLEFT", 6, 6)
        local t = marker:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    end
    local show = LootCodexDB and LootCodexDB.wishMobAlerts and UnitExists("target") and not UnitIsPlayer("target")
        and LC.NpcId and LC.WishedDrops and LC.WishedDrops(LC.NpcId(UnitGUID("target")), UnitName("target"))
    if show then marker:Show() else marker:Hide() end
end
LC.UpdateWishMarker = UpdateMarker

function LC.ForgetMobAlerts()
    wipe(lookedAt)
    lookedCount = 0
    wipe(announced)
    UpdateMarker()
end

-- /codex wishcheck: what the current target drops from the wishlist, announced even if it just was
function LC.WishCheckTarget()
    if not UnitExists("target") or UnitIsPlayer("target") or not LC.NpcId(UnitGUID("target")) then
        Print("target a creature first, then /codex wishcheck.")
        return
    end
    if not CheckMob(UnitGUID("target"), UnitName("target"), true) then
        local n = 0
        for _ in pairs(Store("wish")) do n = n + 1 end
        Print(UnitName("target") .. " (NPC " .. LC.NpcId(UnitGUID("target")) .. ") drops nothing from your wishlist ("
            .. n .. " item" .. (n == 1 and "" or "s") .. ") as far as pfQuest, AtlasLoot and your loot records know.")
    end
end

local mob = CreateFrame("Frame")
mob:RegisterEvent("PLAYER_LOGIN")
mob:RegisterEvent("PLAYER_TARGET_CHANGED")
mob:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
mob:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- 3.3.5 layout: timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags
        local _, _, sGUID, sName, sFlags, dGUID, dName, dFlags = ...
        sFlags, dFlags = sFlags or 0, dFlags or 0
        if bit.band(sFlags, OURS) > 0 and bit.band(dFlags, NPC) > 0 and bit.band(dFlags, FRIENDLY) == 0 then
            if not lookedAt[dGUID] then CheckMob(dGUID, dName) end
        elseif bit.band(dFlags, OURS) > 0 and bit.band(sFlags, NPC) > 0 and bit.band(sFlags, FRIENDLY) == 0 then
            if not lookedAt[sGUID] then CheckMob(sGUID, sName) end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") and not UnitIsPlayer("target") and not UnitIsDead("target") then
            CheckMob(UnitGUID("target"), UnitName("target"))
        end
        UpdateMarker()
    elseif event == "PLAYER_LOGIN" then
        -- makes the star frame and builds the creature drop index now, behind the loading screen,
        -- so the first target or pull doesn't stutter
        UpdateMarker()
        if LootCodexDB and LootCodexDB.wishMobAlerts and next(Store("wish")) and LC.UnitDropIndex then
            LC.UnitDropIndex()
        end
    end
end)
