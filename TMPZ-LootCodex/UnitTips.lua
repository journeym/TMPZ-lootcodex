-- Creature tooltips: hovering a mob lists what it drops, from pfQuest, Epoch's AtlasLoot boss
-- tables and what Loot Codex has seen looted. Options live in Settings.lua.

LootCodex = LootCodex or {}
local LC = LootCodex

local WORLD_DROP_UNITS = 30      -- same cut as Sources.lua: bigger reference tables are world drops
local LINES, LINES_FULL = 6, 15

local unitItems, worldRefs       -- npc -> { item = chance }, npc -> number of world-drop tables
local bossItems                  -- lowercase boss name -> { item = chance }
local cache = {}
local triedData = false
local scroll, scrollNpc = 0, nil  -- mouse wheel position in the long list
local wheelBound = false
local shown                      -- the scrollable list currently in the tooltip, see OnUnit

local function BuildIndex()
    unitItems, worldRefs, bossItems = {}, {}, {}
    local function put(npc, item, chance)
        local t = unitItems[npc]
        if not t then t = {}; unitItems[npc] = t end
        if not t[item] or (chance or 0) > t[item] then t[item] = chance or 0 end
    end
    if pfDB and pfDB.items and pfDB.items.data then
        local refItems = {}
        for item, d in pairs(pfDB.items.data) do
            if type(d) == "table" then
                if d.U then
                    for npc, chance in pairs(d.U) do
                        if chance > 0 then put(npc, item, chance) end
                    end
                end
                if d.R then
                    for ref, chance in pairs(d.R) do
                        refItems[ref] = refItems[ref] or {}
                        refItems[ref][item] = chance
                    end
                end
            end
        end
        local refloot = pfDB.refloot and pfDB.refloot.data or {}
        for ref, items in pairs(refItems) do
            local r = refloot[ref]
            if r and r.U then
                local n = 0
                for _ in pairs(r.U) do n = n + 1 end
                for npc in pairs(r.U) do
                    if n > WORLD_DROP_UNITS then
                        worldRefs[npc] = (worldRefs[npc] or 0) + 1
                    else
                        for item, chance in pairs(items) do put(npc, item, chance) end
                    end
                end
            end
        end
    end
    for item, list in pairs(LootCodexSources and LootCodexSources.boss or {}) do
        for _, b in ipairs(list) do
            if (b[4] == 1 or b[4] == 2) and b[1] ~= "" then
                local key = b[1]:lower()
                bossItems[key] = bossItems[key] or {}
                bossItems[key][item] = b[3]
            end
        end
    end
end

function LC.ForgetUnitDrops() wipe(cache) end

-- npc -> { item = chance } from pfQuest (built once; also used by the Dungeons tab)
function LC.UnitDropIndex()
    if not unitItems then BuildIndex() end
    return unitItems
end

-- the wishlisted items one creature drops, as a list of { id, chance } best first (nil if none).
-- Same three sources as the tooltip (pfQuest, AtlasLoot boss names, learned loot) but without the
-- tooltip's grey/hidden filters, so a wished item is never left out. Used by the wishlist mob alerts.
function LC.WishedDrops(npc, name)
    if not (npc and LootCodexDB and LC.Wishlist) then return nil end
    local wish = LC.Wishlist()
    if not next(wish) then return nil end
    if not unitItems then BuildIndex() end
    local u = unitItems[npc]
    local b = name and bossItems[name:lower()]
    local m = LC.LearnedMob and LC.LearnedMob(npc)
    local out
    for id in pairs(wish) do
        local chance = (u and u[id]) or (b and b[id])
        if m and m.kills > 0 and m.items[id] and (not chance or chance == 0) then
            chance = 100 * m.items[id] / m.kills
        end
        if chance then
            out = out or {}
            out[#out + 1] = { id = id, chance = chance }
        end
    end
    if out then
        table.sort(out, function(a, c)
            if a.chance ~= c.chance then return a.chance > c.chance end
            return a.id < c.id
        end)
    end
    return out
end

-- list of { id, chance, seen } for one creature, best first
local function Drops(npc, name)
    local key = npc .. ":" .. (name or "")
    if cache[key] then return cache[key] end
    if not unitItems then BuildIndex() end

    local merged, seen = {}, {}
    for item, chance in pairs(unitItems[npc] or {}) do merged[item] = chance end
    for item, chance in pairs(name and bossItems[name:lower()] or {}) do
        if not merged[item] or merged[item] == 0 then merged[item] = chance end
    end
    local m = LC.LearnedMob and LC.LearnedMob(npc)
    if m and m.kills > 0 then
        for item, n in pairs(m.items) do
            seen[item] = n
            if not merged[item] or merged[item] == 0 then merged[item] = 100 * n / m.kills end
        end
    end

    local hideGrey = LootCodexDB.unitHideGrey
    local list = {}
    for item, chance in pairs(merged) do
        local r = LC.Item(item)
        local keep = true
        if r then
            if LC.IsHiddenItem(r) and not LootCodexDB.showHidden then keep = false end
            if hideGrey and r[2] == 0 then keep = false end
        end
        if keep then list[#list + 1] = { id = item, chance = chance, seen = seen[item], r = r } end
    end
    table.sort(list, function(a, b)
        if a.chance ~= b.chance then return a.chance > b.chance end
        return a.id < b.id
    end)
    list.world = worldRefs[npc]
    list.kills = m and m.kills or 0
    cache[key] = list
    return list
end

local function Chance(c)
    if not c or c <= 0 then return "?" end
    if c >= 10 then return string.format("%d%%", c + 0.5) end
    if c >= 1 then return string.format("%.1f%%", c) end
    return string.format("%.2f%%", c)
end

local function ItemText(e)
    local r = e.r
    local name = r and r[1] or GetItemInfo(e.id)
        or (pfDB and pfDB.items and pfDB.items.loc and pfDB.items.loc[e.id]) or ("item " .. e.id)
    local q = r and r[2] or select(3, GetItemInfo(e.id)) or 1
    local c = ITEM_QUALITY_COLORS[q] or ITEM_QUALITY_COLORS[1]
    local star = LC.IsWished and LC.IsWished(e.id) and (LC.STAR .. " ") or ""
    return star .. (c.hex or "|cffffffff") .. name .. "|r"
end

local function RightText(e)
    local right = Chance(e.chance)
    if e.seen then right = right .. " |cff88ff88(" .. e.seen .. ")|r" end
    return right
end

local function OnUnit(tip)
    if not LootCodexDB or not LootCodexDB.unitTooltip then return end
    if LootCodexDB.unitShift and not LC.MoreKeyDown() then return end
    local _, unit = tip:GetUnit()
    if not unit or UnitIsPlayer(unit) then return end
    local npc = LC.NpcId(UnitGUID(unit))
    if not npc then return end
    if not triedData then           -- names, quality and the TBC/WotLK filter; loads once
        triedData = true
        LC.EnsureData()
    end
    local list = Drops(npc, UnitName(unit))
    if #list == 0 and not list.world then return end

    -- holding the "more" key (Ctrl by default) shows a longer window that key + mouse wheel scrolls
    if npc ~= scrollNpc then scrollNpc, scroll = npc, 0 end
    local full = LC.MoreKeyDown()
    local max = full and LINES_FULL or (LootCodexDB.unitLines or LINES)
    local first = 1
    if full then
        scroll = math.max(0, math.min(scroll, #list - max))
        first = scroll + 1
    end
    local last = math.min(#list, first + max - 1)
    tip:AddLine(" ")
    if LC.IsWished then
        for _, e in ipairs(list) do
            if LC.IsWished(e.id) then
                tip:AddLine(LC.STAR .. " Drops something on your wishlist", 1, 0.82, 0)
                break
            end
        end
    end
    if full and #list > max then
        tip:AddLine(string.format("Drops (%d-%d of %d):", first, last, #list), 0.2, 0.8, 1)
        -- remember where the drop lines are, so the wheel can rewrite them in place
        shown = { npc = npc, list = list, header = tip:NumLines(), max = max }
    else
        tip:AddLine("Drops:", 0.2, 0.8, 1)
        shown = nil
    end
    for i = first, last do
        local e = list[i]
        tip:AddDoubleLine(ItemText(e), RightText(e), 1, 1, 1, 1, 0.82, 0)
    end
    if #list > max then
        if not full then
            tip:AddLine(string.format("+%d more (hold %s)", #list - max, LC.MoreKeyName()), 0.6, 0.6, 0.6)
        elseif wheelBound then
            tip:AddLine(LC.MoreKeyName() .. " + mouse wheel to scroll", 0.6, 0.6, 0.6)
        else
            tip:AddLine(string.format("+%d more  (/codex to see them all)", #list - last), 0.6, 0.6, 0.6)
        end
    end
    if list.world then tip:AddLine("Also drops random world items.", 0.6, 0.6, 0.6) end
    if list.kills > 0 then
        tip:AddLine(string.format("Looted %d time%s (yours and shared).", list.kills, list.kills == 1 and "" or "s"),
            0.5, 0.5, 0.5)
    end
    tip:Show()
end

local function Redraw()
    local _, unit = GameTooltip:GetUnit()
    if unit and UnitExists(unit) and not UnitIsPlayer(unit) then GameTooltip:SetUnit(unit) end
end

-- Shift/Ctrl/Alt + mouse wheel: over the 3D world the plain wheel is camera zoom and can't be caught,
-- but the modified versions are unbound by default. They're claimed with override bindings (which can't
-- change in combat, so this waits for combat to end) and only if the player hasn't bound them.
-- scrolling rewrites the drop lines already in the tooltip instead of rebuilding it, so it doesn't blink
local function ScrollInPlace(delta)
    local list, max = shown.list, shown.max
    local new = math.max(0, math.min(scroll + delta, #list - max))
    if new == scroll then return end
    scroll = new
    local first = scroll + 1
    local last = math.min(#list, first + max - 1)
    _G["GameTooltipTextLeft" .. shown.header]:SetText(string.format("Drops (%d-%d of %d):", first, last, #list))
    for i = first, last do
        local line = shown.header + (i - first) + 1
        local e = list[i]
        _G["GameTooltipTextLeft" .. line]:SetText(ItemText(e))
        _G["GameTooltipTextRight" .. line]:SetText(RightText(e))
    end
    GameTooltip:Show()          -- re-fits the width to the new names; it's already up, so no flicker
end

local function WheelButton(name, delta)
    local b = CreateFrame("Button", name, UIParent)
    -- a wheel notch only ever sends a key "down" (there's no release), and a button clicked by a
    -- binding fires on the release by default, so it has to fire on the down instead
    b:RegisterForClicks("AnyDown")
    b:SetScript("OnClick", function()
        -- a creature tooltip, else an item tooltip under the mouse, else the pinned chat-link tooltip
        local _, unit = GameTooltip:GetUnit()
        if GameTooltip:IsShown() and unit and LootCodexDB and LootCodexDB.unitTooltip then
            if shown and shown.npc == LC.NpcId(UnitGUID(unit)) then
                ScrollInPlace(delta)
            else
                scroll = scroll + delta
                Redraw()
            end
        elseif not LC.ScrollItemTip(GameTooltip, delta) then
            LC.ScrollItemTip(ItemRefTooltip, delta)
        end
    end)
end
WheelButton("LootCodexWheelUp", -1)
WheelButton("LootCodexWheelDown", 1)

local ev = CreateFrame("Frame")

-- default bindings that do nothing on a classic server (no vehicles), so they don't count as taken
local FREE_ACTIONS = { [""] = true, VEHICLEAIMINCREMENT = true, VEHICLEAIMDECREMENT = true }

local function Free(key) return FREE_ACTIONS[GetBindingAction(key) or ""] end

local function BindWheel()
    if InCombatLockdown() then
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ClearOverrideBindings(ev)
    wheelBound = false
    local up, down = LC.MoreKey() .. "-MOUSEWHEELUP", LC.MoreKey() .. "-MOUSEWHEELDOWN"
    if Free(up) and Free(down) then
        SetOverrideBindingClick(ev, false, up, "LootCodexWheelUp")
        SetOverrideBindingClick(ev, false, down, "LootCodexWheelDown")
        wheelBound = true
    end
end
LC.BindWheel = function()
    BindWheel()
    return wheelBound
end
LC.WheelBound = function() return wheelBound end

ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("MODIFIER_STATE_CHANGED")
ev:SetScript("OnEvent", function(self, event, key)
    if event == "PLAYER_LOGIN" then
        GameTooltip:HookScript("OnTooltipSetUnit", OnUnit)
        BindWheel()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        BindWheel()
        return
    end
    -- pressing or letting go of the "more" key while a creature tooltip is up: redraw it, so the
    -- longer list (or the key-only list) appears without moving the mouse off and back on
    if key ~= "L" .. LC.MoreKey() and key ~= "R" .. LC.MoreKey() then return end
    if not GameTooltip:IsShown() then return end
    if GameTooltip:GetUnit() then
        if LootCodexDB and LootCodexDB.unitTooltip then Redraw() end
    elseif GameTooltip:GetItem() and LootCodexDB and LootCodexDB.tooltip then
        -- an item tooltip: ask whatever is under the mouse (bag slot, character slot, loot or vendor
        -- button...) to show it again, which keeps its sell price, comparison and so on
        local owner = GameTooltip:GetOwner()
        local onEnter = owner and owner:GetScript("OnEnter")
        if onEnter then onEnter(owner) end
    end
end)
