-- Shares what Loot Codex learns with guild and group members who also run it, using hidden
-- addon messages (nothing shows in chat).
--
--   live      every new record goes straight to GUILD and PARTY/RAID
--   catch-up  on login a client asks the guild "what did you learn since I was last on?"
--             (S^proto^since). Whoever answers first claims it (C^name) so only one person
--             replies, then whispers the records. The asker whispers back whatever it learned
--             since its own last push, so things recorded while nobody else was online spread too.
--
-- Records are keyed (see Recorder.lua), so duplicates from relays or two looters are dropped.
-- Everything goes through one queue at one message per SEND_GAP seconds.

LootCodex = LootCodex or {}
local LC = LootCodex

local PREFIX, PROTO = "LCdx", 1
local SEND_GAP = 1.0            -- seconds between any two messages we send
local MAX_LEN = 240             -- addon message text limit is 254 including the prefix
local CLOCK_MARGIN = 3600       -- other people's clocks may be off; ask for a bit more than needed
local ASK_DELAY = 15            -- seconds after login before asking the guild
local CLAIM_MIN, CLAIM_MAX = 2, 8

local log
local me
local queue = {}                -- { channel, target, text }
local whisperedAt = {}          -- name -> GetTime() of our last whisper to them (see SystemFilter)
local live = {}                 -- encoded records waiting to be packed and broadcast
local pendingFor, pendingAt, pendingSince   -- a catch-up request we may answer
local busyUntil = 0
local asked = false
local catchup                   -- { from, added, last } while a guildmate is sending us what we missed

local function Enabled() return not LootCodexDB or LootCodexDB.share ~= false end

local function Pack(strings)
    local out, cur = {}, ""
    for _, s in ipairs(strings) do
        if #s <= MAX_LEN then
            if cur ~= "" and #cur + 1 + #s > MAX_LEN then
                out[#out + 1] = cur
                cur = s
            else
                cur = cur == "" and s or (cur .. "~" .. s)
            end
        end
    end
    if cur ~= "" then out[#out + 1] = cur end
    return out
end

local function Queue(channel, target, text, front)
    local m = { channel = channel, target = target, text = text }
    if front then table.insert(queue, 1, m) else queue[#queue + 1] = m end
end

local function GroupChannel()
    if select(2, IsInInstance()) == "pvp" then return nil end   -- battleground raids aren't our group
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
end

-- called by Recorder.lua for every record learned here
function LC.ShareLive(encoded)
    if Enabled() and encoded then live[#live + 1] = encoded end
end

local function FlushLive()
    if #live == 0 then return end
    local msgs = Pack(live)
    wipe(live)
    local group = GroupChannel()
    -- live messages jump the catch-up queue, in order
    for i = #msgs, 1, -1 do
        if group then Queue(group, nil, msgs[i], true) end
        if IsInGuild() then Queue("GUILD", nil, msgs[i], true) end
    end
end

local function RecordsSince(since)
    local out = {}
    for key, r in pairs(LC.Records()) do
        if (r.rt or 0) > since then out[#out + 1] = LC.Encode(key, r) end
    end
    for id, t in pairs(LC.LearnedItemTimes and LC.LearnedItemTimes() or {}) do
        if t > since then out[#out + 1] = "N^" .. id end
    end
    return out
end

local function Whisper(target, strings)
    for _, text in ipairs(Pack(strings)) do Queue("WHISPER", target, text) end
    busyUntil = GetTime() + (#queue + 1) * SEND_GAP
end

------------------------------------------------------------------------
-- new-version notice. Each client says which version it runs (R^1.5.5) to its guild (and group) once
-- at login; anyone who hears a newer one gets one chat line per session (repeated at later logins
-- until they update). Someone on an older version logging in is answered by one client (random short
-- delay; whoever speaks first, the rest stay quiet), so they hear about it even if nobody newer
-- logs in after them. Versions older than this feature never send or show it, and ignore R messages.
------------------------------------------------------------------------
-- where to get updates, shown in the notice; "" = "wherever you downloaded this one"
LC.DOWNLOAD_URL = "https://project-epoch.org/forums/?topic=318&page=last#post-1131"

local MY_VERSION = GetAddOnMetadata and GetAddOnMetadata("TMPZ-LootCodex", "Version") or "0"
local noticed = false
local versionReplyAt            -- GetTime() to answer an older client's R, or nil

local function VersionParts(v)
    local t = {}
    for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

-- true when a is a later version than b
local function Newer(a, b)
    local x, y = VersionParts(a), VersionParts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

-- one step up from ours at most (1.5.5 -> 1.x or 2.x), so a joke "R^99.0" can't nag the guild
local function Plausible(v)
    local x, y = VersionParts(v), VersionParts(MY_VERSION)
    return x[1] ~= nil and y[1] ~= nil and x[1] <= y[1] + 1
end

local function Notice(v)
    if noticed or not (LootCodexDB and LootCodexDB.versionNotice ~= false) then return end
    noticed = true
    local where = LC.DOWNLOAD_URL ~= "" and ("Download: " .. LC.DOWNLOAD_URL)
        or "Get it from wherever you downloaded this one."
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff33ccffTMPZ-LootCodex:|r |cffffd100version %s is out|r (you have %s). %s", v, MY_VERSION, where))
end

local function HeardVersion(v, sender)
    if not v or not Plausible(v) or (log and log.ignore[sender]) then return end
    if Newer(v, MY_VERSION) then
        if LootCodexDB and Newer(v, LootCodexDB.newestVersion or "0") then LootCodexDB.newestVersion = v end
        Notice(v)
    elseif Newer(MY_VERSION, v) then
        versionReplyAt = versionReplyAt or (GetTime() + 3 + math.random() * 9)
    else
        versionReplyAt = nil        -- someone on our version (or newer) answered already
    end
end

function LC.VersionInfo() return MY_VERSION, LootCodexDB and LootCodexDB.newestVersion end

------------------------------------------------------------------------
-- receiving
------------------------------------------------------------------------
local function OnMessage(msg, channel, sender)
    local kind = msg:sub(1, 1)
    if kind == "R" then
        HeardVersion(msg:match("^R%^([%d%.]+)$"), sender)
        return
    end
    if kind == "S" then
        local proto, since = msg:match("^S%^(%d+)%^(%d+)")
        if tonumber(proto) ~= PROTO or channel ~= "GUILD" or GetTime() < busyUntil or pendingFor then return end
        since = tonumber(since) - CLOCK_MARGIN
        for _, r in pairs(LC.Records()) do
            if (r.rt or 0) > since then
                pendingFor, pendingAt = sender, GetTime() + CLAIM_MIN + math.random() * (CLAIM_MAX - CLAIM_MIN)
                pendingSince = since
                return
            end
        end
        return
    end
    if kind == "C" then
        local who = msg:match("^C%^(.+)$")
        if who == pendingFor then pendingFor = nil end            -- someone else is answering
        if who == me and channel == "GUILD" then
            -- someone is sending us their records: send ours back to them
            local mine = RecordsSince(log.lastPush or 0)
            Whisper(sender, mine)
            log.lastPush = time()
            catchup = { from = sender, added = 0, last = GetTime() }
            LC.ShareActivity(string.format("catching up with the guild: %s is sending what you missed%s.", sender,
                #mine > 0 and string.format(" (sending them your %d finds too)", #mine) or ""))
        end
        return
    end
    local added = 0
    for part in (msg .. "~"):gmatch("([^~]*)~") do
        local item = part:match("^N%^(%d+)$")          -- a new item someone learned (Learn.lua)
        if item then
            if LC.LearnFromNetwork then LC.LearnFromNetwork(tonumber(item), sender) end
        else
            local key, r = LC.Decode(part)
            if key and LC.AddRecord(key, r, sender) then added = added + 1 end
        end
    end
    if catchup and sender == catchup.from then
        catchup.added, catchup.last = catchup.added + added, GetTime()
    end
end

------------------------------------------------------------------------
-- driver
------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local nextSend, nextFlush, nextSeen, askAt = 0, 0, 0, nil

driver:SetScript("OnUpdate", function()
    local now = GetTime()
    if askAt and now >= askAt then
        askAt = nil
        if Enabled() and IsInGuild() then
            Queue("GUILD", nil, "S^" .. PROTO .. "^" .. (log.lastSeen or 0))
            asked = true
        end
        if Enabled() then
            if IsInGuild() then Queue("GUILD", nil, "R^" .. MY_VERSION) end
            local group = GroupChannel()
            if group then Queue(group, nil, "R^" .. MY_VERSION) end
        end
        -- still behind a version heard at an earlier login: say so again
        local newest = LootCodexDB and LootCodexDB.newestVersion
        if newest and Newer(newest, MY_VERSION) then Notice(newest) end
    end
    if versionReplyAt and now >= versionReplyAt then
        versionReplyAt = nil
        if Enabled() and IsInGuild() then Queue("GUILD", nil, "R^" .. MY_VERSION, true) end
    end
    if pendingFor and now >= pendingAt then
        local who, since = pendingFor, pendingSince
        pendingFor = nil
        Queue("GUILD", nil, "C^" .. who, true)
        local out = RecordsSince(since)
        Whisper(who, out)
        LC.ShareActivity(string.format("sharing %d finds with %s, who just logged in.", #out, who))
    end
    if catchup and now - catchup.last > 15 then           -- nothing more for a while: it's finished
        LC.ShareActivity(string.format("caught up: %d new finds from %s.", catchup.added, catchup.from))
        catchup = nil
    end
    if now >= nextFlush then
        nextFlush = now + SEND_GAP
        FlushLive()
    end
    if now >= nextSeen then
        nextSeen = now + 60
        if asked then log.lastSeen = time() end    -- only after we've asked, or we'd skip what we missed
    end
    if now >= nextSend and #queue > 0 then
        nextSend = now + SEND_GAP
        local m = table.remove(queue, 1)
        if Enabled() then
            if m.channel == "WHISPER" then whisperedAt[m.target] = now end
            SendAddonMessage(PREFIX, m.text, m.channel, m.target)
        end
    end
end)

------------------------------------------------------------------------
-- someone we're whispering a catch-up to logs out: the server answers every further whisper with
-- "No player named 'X' is currently playing." in chat, once a second until the queue runs dry.
-- Drop everything still queued for them as soon as we hear they've gone, and hide those lines.
------------------------------------------------------------------------
-- splits a global string like "No player named '%s' is currently playing." around its %s
local function Around(fmt)
    if type(fmt) ~= "string" then return nil end
    local pre, post = fmt:match("^(.-)%%s(.*)$")
    if pre then return { pre, post } end
end
local NOT_PLAYING = Around(ERR_CHAT_PLAYER_NOT_FOUND_S)    -- the whisper error
local WENT_OFFLINE = Around(ERR_FRIEND_OFFLINE_S)          -- "%s has gone offline." (guild and friends)

local function NameIn(msg, parts)
    if not parts or type(msg) ~= "string" then return nil end
    local pre, post = parts[1], parts[2]
    if #msg <= #pre + #post or msg:sub(1, #pre) ~= pre or msg:sub(#msg - #post + 1) ~= post then return nil end
    local name = msg:sub(#pre + 1, #msg - #post)
    return (name:gsub("|H.-|h%[?(.-)%]?|h", "%1"))       -- the offline line links the name
end

local function Gone(name)
    local dropped = false
    for i = #queue, 1, -1 do
        if queue[i].channel == "WHISPER" and queue[i].target == name then
            table.remove(queue, i)
            dropped = true
        end
    end
    if dropped then busyUntil = GetTime() + #queue * SEND_GAP end   -- free to answer the next guildmate
    if pendingFor == name then pendingFor = nil end
    if catchup and catchup.from == name then catchup = nil end
end
LC.SyncGone = Gone

local function SystemFilter(_, _, msg)
    local who = NameIn(msg, NOT_PLAYING)
    if who and whisperedAt[who] and GetTime() - whisperedAt[who] < 60 then
        Gone(who)
        return true                -- ours: don't show it
    end
    who = NameIn(msg, WENT_OFFLINE)
    if who then Gone(who) end      -- not ours to hide
end
if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemFilter) end
LC.SyncSystemFilter = SystemFilter

driver:RegisterEvent("CHAT_MSG_ADDON")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        askAt = GetTime() + ASK_DELAY
        return
    end
    if prefix ~= PREFIX or not log or not Enabled() then return end
    me = me or UnitName("player")
    if sender == me then return end
    OnMessage(msg, channel, sender)
end)

function LC.SyncStart(l)
    log = l
    me = UnitName("player")
end

function LC.SyncQueued() return #queue end
