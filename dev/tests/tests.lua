-- Smoke and logic tests for Stinkie UI 0.27.0 (new features + options).
local ns = TEST_NS
local function print(...) local p = {} for i = 1, select("#", ...) do p[#p + 1] = tostring((select(i, ...))) end io.write(table.concat(p, " ") .. "\n") end
local passed, failed = 0, 0
local function check(name, cond, extra)
	if cond then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. (extra and (": " .. tostring(extra)) or "")) end
end
local function flushErrors(label)
	if #MOCK.errors > 0 then
		for _, e in ipairs(MOCK.errors) do io.write("ERROR [" .. label .. "] " .. e .. "\n") end
		failed = failed + #MOCK.errors
		MOCK.errors = {}
	end
end

-- boot
MOCK.Fire("ADDON_LOADED", "StinkieUI")
MOCK.Fire("PLAYER_LOGIN")
MOCK.Fire("PLAYER_ENTERING_WORLD", true, false)
MOCK.Advance(1)
flushErrors("boot")
ns.db.matchHistory.loadMonths = 0 -- the older tests count every match
check("db loaded", ns.db and ns.db.flagCap and ns.db.bgTimers and ns.db.matchHistory)

---------------------------------------------------------------------------
-- Flag Cap logic
---------------------------------------------------------------------------
local L = ns.FlagCap.Logic
check("yards", math.abs(L.Yards(0, 0, 0.003, 0.004, 1000, 1000) - 5) < 1e-6)
check("status oncap", L.Status(4, 8, true) == "ONCAP")
check("status carried", L.Status(40, 8, true) == "CARRIED")
check("status dropped", L.Status(40, 8, false) == "DROPPED")
local spot = L.Learn({}, 0.5, 0.5)
L.Learn(spot, 0.52, 0.5)
check("learn avg", math.abs(spot.x - 0.51) < 1e-9 and spot.n == 2)
local f = L.NewFlag("Alliance")
check("first absent no event", L.Step(f, 0, nil) == nil)
check("pickup event", L.Step(f, 1, 0.2, 0.2, 1000, 600, false) == "PICKUP")
check("moving = carried", (L.Step(f, 1.2, 0.202, 0.2, 1000, 600, false) == nil) and f.carried)
L.Step(f, 3, 0.202, 0.2, 1000, 600, false)
check("still 1.8s = not carried", not f.carried)
check("gone event", L.Step(f, 4, nil) == "GONE")

---------------------------------------------------------------------------
-- Flag Cap in a (mock) Warsong Gulch
---------------------------------------------------------------------------
MOCK.instanceType, MOCK.instanceName, MOCK.instanceID, MOCK.mapID = "pvp", "Warsong Gulch", 2106, 1339
MOCK.flags = { { tex = 137200 }, { tex = 137218 } } -- both at base (no position)
MOCK.Fire("PLAYER_ENTERING_WORLD", false, false)
MOCK.Advance(1.2)
check("flag map detected", ns.FlagCap.flagMap == true)
check("holder hidden with flags home", not ns.FlagCap.holder:IsShown())
-- Horde player picks up the Alliance flag at the Alliance base (0.5, 0.1)
MOCK.flags[1].x, MOCK.flags[1].y = 0.5, 0.1
MOCK.Advance(0.3)
-- Alliance player picks up the Horde flag at the Horde base (0.5, 0.9)
MOCK.flags[2].x, MOCK.flags[2].y = 0.5, 0.9
MOCK.Advance(0.3)
local bases = StinkieUIDB.flagCapBases[1339]
check("learned alliance base", bases and bases.Alliance and math.abs(bases.Alliance.y - 0.1) < 1e-9)
check("learned horde base", bases and bases.Horde and math.abs(bases.Horde.y - 0.9) < 1e-9)
-- the Alliance flag runs to the Horde base
for i = 1, 20 do MOCK.flags[1].y = 0.1 + i * 0.04; MOCK.Advance(0.2) end
MOCK.flags[1].y = 0.895
MOCK.Advance(0.25)
check("indicator shown", ns.FlagCap.holder:IsShown())
local found
for _, o in ipairs(MOCK.frames) do if o._kind == "FontString" and o._text == "ON CAP" then found = true end end
check("ON CAP shown", found)
-- Horde flag dropped mid-field: stops moving
MOCK.flags[2].y = 0.5
MOCK.Advance(2)
local dropped
for _, o in ipairs(MOCK.frames) do
	if o._kind == "FontString" and o._text == "DROPPED" and o._parent and o._parent._parent and o._parent._parent:IsShown() then dropped = true end
end
check("dropped flag not shown (nobody has it)", not dropped)
check("carried flag still shown", ns.FlagCap.holder:IsShown())
local flagIcon
for _, o in ipairs(MOCK.frames) do if o._kind == "Texture" and o._parent and o._parent._parent == ns.FlagCap.holder and o._tex == ns.MEDIA.flag then flagIcon = true end end
check("plain flag icon only", flagIcon)
flushErrors("flagcap")
ns.FlagCap.Debug()
flushErrors("flagcap debug")

---------------------------------------------------------------------------
-- BG Timers
---------------------------------------------------------------------------
local T = ns.BGTimers.Logic
local d = T.ParseDurations({ "Arathi Basin = 60", "Deepwind Gorge=45", "junk" })
check("durations parsed", d["arathi basin"] == 60 and d["deepwind gorge"] == 45)
local node = {}
check("assault starts", T.OnNodeChange(node, 100, 60, nil) == "START" and node.timerEnd == 160)
check("defended stops", T.OnNodeChange(node, 120, 60, nil) == "STOP" and node.timerEnd == nil)
check("re-assault starts", T.OnNodeChange(node, 130, 60, nil) == "START")
check("turn at end stops", T.OnNodeChange(node, 190, 60, nil) == "STOP" and node.recentEnd == 190)
check("turn after expiry ignored", T.OnNodeChange(node, 191, 60, nil) == nil)
check("atlas contested", T.OnNodeChange({}, 0, 60, "BG-Alliance-Stables-Contested") == "START")
local rA, rH = T.Rates({ { t = 0, a = 100, h = 100 }, { t = 10, a = 200, h = 130 } }, 10, 30)
check("rates", rA == 10 and rH == 3)
local w, secs, lose = T.Predict(1000, 1100, 10, 3, 1500)
check("predict alliance", w == "Alliance" and secs == 50 and lose == 1250)
check("predict none", T.Predict(1, 1, 0, 0, 1500) == nil)

MOCK.flags = {}
MOCK.instanceName, MOCK.instanceID, MOCK.mapID, MOCK.mapName = "Arathi Basin", 2107, 1366, "Arathi Basin"
MOCK.pois = { [1] = { name = "Stables", textureIndex = 10 }, [2] = { name = "Blacksmith", textureIndex = 15 }, [3] = { name = "Stables Graveyard", textureIndex = 4 } }
MOCK.widgets = { { widgetID = 7, widgetType = 3 } }
MOCK.widgetInfo = { [7] = { leftBarValue = 500, rightBarValue = 400, leftBarMax = 1500, rightBarMax = 1500 } }
MOCK.Fire("PLAYER_ENTERING_WORLD", false, false)
MOCK.Advance(1.1)
MOCK.pois[1].textureIndex = 11 -- assaulted
MOCK.Fire("AREA_POIS_UPDATED")
for i = 1, 12 do
	MOCK.widgetInfo[7].leftBarValue = 500 + i * 10
	MOCK.widgetInfo[7].rightBarValue = 400 + i * 4
	MOCK.Advance(1)
end
local labels = {}
for _, o in ipairs(MOCK.frames) do if o._kind == "FontString" and o._shown and o._parent and o._parent._parent == ns.BGTimers.holder then labels[o._text] = true end end
check("stables timer bar", labels["Stables"])
local winText
for k in pairs(labels) do if tostring(k):find("wins") then winText = k end end
check("win prediction bar", winText ~= nil, winText)
check("graveyard ignored", not labels["Stables Graveyard"])
MOCK.dead, MOCK.resTime = true, 17
MOCK.Advance(1.1)
local res
for _, o in ipairs(MOCK.frames) do if o._kind == "FontString" and o._text == "RESURRECT" then res = true end end
check("resurrection bar", res)
MOCK.dead = false
ns.BGTimers.Debug()
flushErrors("bgtimers")

---------------------------------------------------------------------------
-- Match recorder: a 3v3
---------------------------------------------------------------------------
MOCK.instanceType, MOCK.instanceName, MOCK.instanceID, MOCK.bracket = "arena", "Nagrand Arena", 1505, "arena"
MOCK.Fire("PLAYER_ENTERING_WORLD", false, false)
local function score(name, classToken, spec, team, dmg, heal, rating, rchg, mmr, mmrchg)
	return { name = name, guid = (name == "Stinkie") and "Player-1-ABC" or nil, classToken = classToken, talentSpec = spec, raceName = "Orc", faction = team,
		damageDone = dmg, healingDone = heal, killingBlows = 1, deaths = 0, honorableKills = 2, rating = rating, ratingChange = rchg,
		prematchMMR = mmr, mmrChange = mmrchg, roleAssigned = 8, stats = { { pvpStatID = 5, pvpStatValue = 2, name = "Flag, Captures" } } }
end
MOCK.scores = {
	score("Stinkie", "WARLOCK", "Destruction", 0, 3200000, 400000, 1850, 14, 1900, 12),
	score("Pinkie-Area 52", "PRIEST", "Discipline", 0, 900000, 4000000, 1840, 14, 1880, 10),
	score("Minkie", "ROGUE", "Subtlety", 0, 2500000, 100000, 1860, 14, 1910, 9),
	score("Enemy1-Stormrage", "MAGE", "Frost", 1, 2000000, 200000, 1830, -13, 1870, -11),
	score("Enemy2-Stormrage", "ROGUE", "Assassination", 1, 2200000, 100000, 1830, -13, 1870, -11),
	score("Enemy3-Stormrage", "PRIEST", "Holy", 1, 600000, 3800000, 1830, -13, 1870, -11),
}
MOCK.team, MOCK.winner = 0, 0
MOCK.Fire("PVP_MATCH_ACTIVE")
MOCK.Fire("PVP_MATCH_COMPLETE", 0, 312)
MOCK.Advance(1.1)
flushErrors("recorder")
check("inbox has match", StinkieUIMatchInbox and #StinkieUIMatchInbox.records == 1, StinkieUIMatchInbox and #StinkieUIMatchInbox.records)
local C = ns.MatchRecorder.Codec
local m = C.Decode(StinkieUIMatchInbox.records[1])
check("decoded bracket", m and m.bracket == "3v3", m and m.bracket)
check("decoded result", m and m.result == "W")
check("decoded rating", m and m.rating == 1850 and m.ratingAfter == 1864)
check("decoded me", m and m.players[m.me].name == "Stinkie-Tichondrius")
check("decoded enemy spec", m and m.players[4].spec == 64)
check("decoded loadout", m and m.loadout and #m.loadout > 20)
check("decoded pvp talents", m and m.pvpTalents == "3508+5379+5386")
check("stat names kept", StinkieUIMatchInbox.statNames[5] == "Flag, Captures")
check("line size", #StinkieUIMatchInbox.records[1] < 700, #StinkieUIMatchInbox.records[1])
print("3v3 line bytes: " .. #StinkieUIMatchInbox.records[1])
-- a second match never double-saves
MOCK.Fire("PVP_MATCH_COMPLETE", 0, 312)
MOCK.Advance(2)
check("no double save", #StinkieUIMatchInbox.records == 1)

-- Solo Shuffle: rounds from the custom victory stat
MOCK.bracket, MOCK.victoryStat = "shuffle", 99
for _, s in ipairs(MOCK.scores) do s.stats = { { pvpStatID = 99, pvpStatValue = (s.name == "Stinkie") and 4 or 2, name = "Rounds Won" } } end
MOCK.Fire("PVP_MATCH_ACTIVE")
MOCK.Fire("PVP_MATCH_COMPLETE", 0, 300)
MOCK.Advance(1.1)
local sm = C.Decode(StinkieUIMatchInbox.records[2] or "")
check("shuffle saved", sm and sm.bracket == "shuffle" and sm.rounds == 4 and sm.result == "W", sm and (tostring(sm.bracket) .. tostring(sm.rounds)))
flushErrors("recorder shuffle")

-- synthetic history: 300 more matches through the codec
math.randomseed(7)
local maps = { "Nagrand Arena", "Blade's Edge Arena", "Dalaran Sewers", "Ruins of Lordaeron", "Mugambala" }
for i = 1, 300 do
	local mm = C.Decode(StinkieUIMatchInbox.records[1])
	mm.t = mm.t - i * 3600
	mm.map = maps[(i % #maps) + 1]
	local win = math.random() < 0.55
	mm.result = win and "W" or "L"
	mm.ratingAfter = mm.rating + (win and 12 or -12)
	mm.players[4].spec = (i % 3 == 0) and 63 or 64
	table.insert(StinkieUIMatchInbox.records, C.Encode(mm))
end

---------------------------------------------------------------------------
-- History addon (load on demand) + window
---------------------------------------------------------------------------
SlashCmdList.STINKIEMH("")
flushErrors("history open")
local H = StinkieUI_History
check("history loaded", H and H.Data)
local D = H.Data
check("inbox merged", #D.Archive().records == 302 and #StinkieUIMatchInbox.records == 0, #D.Archive().records)
check("summaries built", D.summaries and #D.summaries == 302)
local inlineBytes = 0
for i = 1, 300 do inlineBytes = inlineBytes + 0 end
print(string.format("archive: %d matches, %.1f KB (%.0f bytes/match incl. shared strings)", #D.Archive().records, D.SizeBytes() / 1024, D.SizeBytes() / #D.Archive().records))
local agg = D.Aggregate(D.summaries)
check("aggregate games", agg.games == 302)
check("wilson sane", agg.lo < agg.winRate and agg.winRate < agg.hi)
local lo, hi = D.Wilson(50, 100)
check("wilson 50/100", math.abs(lo - 0.404) < 0.01 and math.abs(hi - 0.596) < 0.01, lo .. " " .. hi)
local byMap = D.Group(D.summaries, "map")
check("group by map", #byMap == 5, #byMap)
local byComp = D.Group(D.summaries, "comp")
check("group by comp", #byComp >= 2)
local byMate = D.Group(D.summaries, "teammate")
check("group by teammate", byMate[1] and byMate[1].games >= 300)
local only3 = D.Filter(D.summaries, { bracket = "arena" })
check("filter arena", #only3 == 301, #only3)
local search = D.Filter(D.summaries, { search = "pinkie" })
check("search player", #search == 302)
local csv = D.CSV(only3, function(id) return tostring(id) end)
check("csv rows", select(2, csv:gsub("\n", "")) == 301)
for _, by in ipairs({ "map", "comp", "enemySpec", "allyComp", "teammate", "mySpec", "hero", "mmrBand", "length", "hour", "weekday", "bracket", "char", "season" }) do
	local ok, err = pcall(D.Group, D.summaries, by)
	check("group " .. by, ok, err)
end
-- window renders both tabs and a detail view
H.Toggle("stats")
flushErrors("stats tab")
H.Toggle("matches")
H.ShowDetail(D.summaries[1])
flushErrors("detail")
-- a new match while the window is loaded goes straight in
MOCK.bracket = "arena"
for _, s in ipairs(MOCK.scores) do s.stats = {} end
MOCK.Fire("PVP_MATCH_ACTIVE")
MOCK.Fire("PVP_MATCH_COMPLETE", 0, 312)
MOCK.Advance(1.1)
check("live receive", #D.Archive().records == 303 and #StinkieUIMatchInbox.records == 0)
flushErrors("live")
-- reopen after close releases summaries
StinkieUI_MatchHistory:Hide()
check("released on close", D.summaries == nil)
-- archive round trip: dict tokens resolve
local first = D.Get(1)
check("archive decode", first and first.players[2].name == "Pinkie-Area 52", first and first.players[2].name)

---------------------------------------------------------------------------
-- Party targets
---------------------------------------------------------------------------
MOCK.instanceType = "none"
ns.db.partyTargets.enabled = true
ns.PartyTargets:Init()
ns.PartyTargets:Refresh()
check("party target frames", #ns.PartyTargets.frames == 4)
do
	-- your own row needs a group; party members' rows don't change
	local PT, driver, watched = ns.PartyTargets, nil, nil
	local oldDriver, oldWatch = RegisterStateDriver, RegisterUnitWatch
	RegisterStateDriver = function(_, state, rule) driver = state .. " " .. rule end
	RegisterUnitWatch = function(f) watched = f end
	local own, member = { unit = "target" }, { unit = "party1target" }
	PT.Watch(own)
	check("own target row only in a group", driver == "visibility [group,@target,exists] show; hide" and watched == nil, driver)
	driver = nil
	PT.Watch(member)
	check("party member row follows its unit", watched == member and driver == nil)
	RegisterStateDriver, RegisterUnitWatch = oldDriver, oldWatch
end
ns.PartyTargets:SetTestMode(true)
check("party target preview", ns.PartyTargets.frames[2].Name._text == "Pinkie")
ns.PartyTargets:SetTestMode(false)
flushErrors("partytargets")

---------------------------------------------------------------------------
-- Options: open every page
---------------------------------------------------------------------------
ns:ToggleOptions()
flushErrors("options open")
local navButtons = {}
for _, o in ipairs(MOCK.frames) do
	if o._kind == "Button" and o.text and o._scripts.OnClick and o._parent and o._parent._w == 150 then navButtons[#navButtons + 1] = o end
end
check("nav buttons", #navButtons >= 20, #navButtons)
local labels = {}
for _, b in ipairs(navButtons) do
	labels[#labels + 1] = b.text._text
	b:Click()
	flushErrors("page " .. tostring(b.text._text))
	-- open groups' children
end
for _, b in ipairs(navButtons) do b:Click(); flushErrors("page2 " .. tostring(b.text._text)) end
print("nav: " .. table.concat(labels, " | "))
-- test buttons and refresh
ns.FlagCap:SetTestMode(true); ns.BGTimers:SetTestMode(true)
ns:Refresh(); MOCK.Advance(0.2)
ns.FlagCap:SetTestMode(false); ns.BGTimers:SetTestMode(false)
ns:SetLocked(false); ns:SetLocked(true)
flushErrors("test modes")

---------------------------------------------------------------------------
-- Queue Time & MMR
---------------------------------------------------------------------------
local Q = ns.QueueInfo
check("queue bracket blitz", Q.Bracket("RATEDSOLORBG", 0, true, "Battleground Blitz") == "blitz")
check("queue bracket 3v3", Q.Bracket("ARENA", 3, true, "Arena") == "3v3")
check("queue bracket shuffle", Q.Bracket("ARENA", 0, true, "Solo Shuffle") == "shuffle")
check("queue bracket rbg", Q.Bracket("BATTLEGROUND", 10, true, "Rated Battleground") == "rbg")
StinkieUIDB.lastMMR["Stinkie-Tichondrius"].blitz = { mmr = 2773, rating = 2677, t = 1 }
MOCK.queues = { { status = "queued", name = "Battleground Blitz", size = 0, rated = true, qt = "RATEDSOLORBG", waited = 192000, est = 160000 } }
MOCK.Fire("UPDATE_BATTLEFIELD_STATUS")
check("queue holder shown", ns.QueueInfo.holder:IsShown())
local qtext = {}
for _, o in ipairs(MOCK.frames) do if o._kind == "FontString" and o._parent and o._parent._parent == ns.QueueInfo.holder then qtext[#qtext + 1] = o._text end end
local joined = table.concat(qtext, " | ")
check("queue text", joined:find("Blitz") and joined:find("3:12") and joined:find("est 2:40") and joined:find("MMR 2773"), joined)
MOCK.queues = {}
MOCK.Fire("UPDATE_BATTLEFIELD_STATUS")
check("queue holder hidden", not ns.QueueInfo.holder:IsShown())
-- recorder remembers MMR
check("recorder MMR cache", StinkieUIDB.lastMMR["Stinkie-Tichondrius"]["3v3"] and StinkieUIDB.lastMMR["Stinkie-Tichondrius"]["3v3"].mmr == 1912)
flushErrors("queue")

-- 0.32: queue spec icon, header, MMR unknown, hide in PvP, idle-only queue time
ns.db.queueInfo.header = true -- (Stinkie's preset has it off)
C_PvP.GetAssignedSpecForBattlefieldQueue = function(i) return MOCK.queues[i] and MOCK.queues[i].spec or 0 end
MOCK.queues = { { status = "queued", name = "Solo Shuffle", size = 0, rated = true, qt = "ARENA", waited = 2000, est = 60000, spec = 265 } }
MOCK.instanceType = "none"
MOCK.Fire("UPDATE_BATTLEFIELD_STATUS")
qtext = {}
for _, o in ipairs(MOCK.frames) do if o._kind == "FontString" and o._parent and o._parent._parent == ns.QueueInfo.holder and o._parent:IsShown() then qtext[#qtext + 1] = o._text end end
joined = table.concat(qtext, " | ")
check("queued as header", joined:find("Queued as Affliction"), joined)
check("MMR unknown for spec with no games", joined:find("MMR unknown"), joined)
check("header spec icon", ns.QueueInfo.header.icon._tex == 365, tostring(ns.QueueInfo.header.icon._tex))
local track = StinkieUIDB.queueTrack["Stinkie-Tichondrius"]
check("queue tracked", track.live.shuffle and track.live.shuffle.since ~= nil)
MOCK.time = MOCK.time + 100
-- walk into another match: the shuffle queue stops counting
MOCK.instanceType = "pvp"
MOCK.Fire("PLAYER_ENTERING_WORLD")
check("queue hidden in pvp", not ns.QueueInfo.holder:IsShown())
check("idle 100 while in match", track.live.shuffle.idle == 100 and track.live.shuffle.since == nil, tostring(track.live.shuffle.idle))
MOCK.time = MOCK.time + 900
MOCK.instanceType = "none"
MOCK.Fire("PLAYER_ENTERING_WORLD")
check("queue shown again outside", ns.QueueInfo.holder:IsShown())
MOCK.time = MOCK.time + 50
MOCK.queues[1].status = "confirm"
MOCK.Fire("UPDATE_BATTLEFIELD_STATUS")
check("pop saved idle-only", track.popped.shuffle and track.popped.shuffle.secs == 150, track.popped.shuffle and track.popped.shuffle.secs)
check("take queue", ns.QueueInfo.TakeQueue("shuffle") == 150)
check("take queue once", ns.QueueInfo.TakeQueue("shuffle") == nil)
MOCK.queues = {}
MOCK.Fire("UPDATE_BATTLEFIELD_STATUS")
check("left queue cleared", next(track.live) == nil)
ns.db.queueInfo.hideInPvP = true
flushErrors("queue 0.32")

---------------------------------------------------------------------------
-- Rated Tracker import (synthetic)
---------------------------------------------------------------------------
local Imp = StinkieUI_History.Import
local function rtMatch(ts, extra)
	local m = { _bracketID = 1, _ownerCharKey = "Stinkie-Ner'zhul", timestamp = ts, mapName = "Nagrand Arena", map = 1505, duration = 200,
		preMatchRating = 2300, postMatchRating = 2310, mmrPre = 2350, mmrPost = 2360, won = true, season = 42, playerClass = "WARLOCK", playerSpec = "Destruction",
		players = { { name = "Stinkie", classToken = "WARLOCK", spec = "Destruction", faction = 1, damage = 100, healing = 5, kills = 1, deaths = 0, rating = 2300, ratingChange = 10 },
			{ name = "Pinkie", classToken = "PRIEST", spec = "Holy", faction = 1, damage = 1, healing = 9 },
			{ name = "Foe-Area 52", classToken = "MAGE", spec = "Frost", faction = 0, damage = 50, healing = 1, bgStats = { ["Flag Captures"] = 2 } } } }
	for k, v in pairs(extra or {}) do m[k] = v end
	return m
end
RatedTrackerDB = { profiles = { Default = { matches = { US = { ["Stinkie-Ner'zhul"] = {
	lastMatch = rtMatch(5000),
	["1"] = { rtMatch(5000), rtMatch(5100, { duration = 90, mapName = "Dalaran Sewers" }), rtMatch(5300, { finalScores = { "Round: 2/6" } }) },
	["6"] = { Demonology = { rtMatch(6000, { _bracketID = 6, roundsWon = 4, shuffleRounds = { { won = true, duration = 100, allies = { { name = "Stinkie-Ner'zhul", isSelf = true }, { name = "Pinkie" } }, firstDeath = { name = "Foe-Area52" } } } }) } },
	["9"] = { rtMatch(7000, { _bracketID = 9 }) },
} } } } } }
-- Rated Tracker's "unknown" saved as 4294967295 (crashed the 0.27 import)
RatedTrackerDB.profiles.Default.matches.US["Stinkie-Ner'zhul"]["1"][2].players[3].honorableKills = 4294967295
RatedTrackerDB.profiles.Default.matches.US["Stinkie-Ner'zhul"]["1"][2].players[2].damage = 3000000000
check("codec big numbers", ns.MatchRecorder.Codec.Encode({ t = 1, players = { { dmg = 3000000000, hk = 4294967295 } } }):find("3000000000"))
local before = #StinkieUI_History.Data.Archive().records
ns.MatchRecorder.Import()
for _ = 1, 20 do MOCK.Advance(0.02) end
local after = #StinkieUI_History.Data.Archive().records
check("import added 4", after - before == 4, after - before)
local big
for i = before + 1, after do local m = StinkieUI_History.Data.Get(i); for _, p in ipairs(m.players) do if p.dmg == 3000000000 then big = p end end end
check("import keeps huge damage", big ~= nil)
local found3v3, foundRound, foundShuffle
for i = before + 1, after do
	local m = StinkieUI_History.Data.Get(i)
	if m.bracket == "3v3" and m.map == "Nagrand Arena" then found3v3 = m end
	if m.bracket == "shuffle-round" then foundRound = m end
	if m.bracket == "shuffle" then foundShuffle = m end
end
check("imported 3v3 fields", found3v3 and found3v3.char == "Stinkie-Ner'zhul" and found3v3.ratingAfter == 2310 and found3v3.mmrAfter == 2360 and found3v3.result == "W" and found3v3.src == "RT")
check("imported names", found3v3 and found3v3.players[1].name == "Stinkie-Ner'zhul" and found3v3.players[3].name == "Foe-Area52")
check("imported stat", found3v3 and found3v3.players[3].stats ~= nil)
check("shuffle round separated", foundRound ~= nil)
check("shuffle rounds string", foundShuffle and foundShuffle.srounds == "1.100.2.3" and foundShuffle.rounds == 4 and foundShuffle.result == "W", foundShuffle and foundShuffle.srounds)
check("imported MMR remembered", StinkieUIDB.lastMMR["Stinkie-Ner'zhul"] and StinkieUIDB.lastMMR["Stinkie-Ner'zhul"]["3v3"].mmr == 2360)
local reportLine = MOCK.prints[#MOCK.prints]
check("import report", reportLine:find("Imported 4 of 5") and reportLine:find("bracket"), reportLine)
ns.MatchRecorder.Import()
for _ = 1, 20 do MOCK.Advance(0.02) end
check("re-import adds nothing", #StinkieUI_History.Data.Archive().records == after)
RatedTrackerDB = nil
ns.MatchRecorder.Import()
check("import without RT explains", MOCK.prints[#MOCK.prints]:find("Enable Rated Tracker"))
StinkieUI_History.Toggle("matches")
for _, s in ipairs(StinkieUI_History.Data.summaries) do if s.bracket == "shuffle" and s.src == "RT" then StinkieUI_History.ShowDetail(s) end end
flushErrors("import")

---------------------------------------------------------------------------
-- Character Sheet
---------------------------------------------------------------------------
local CS = ns.CharacterSheet
MOCK.items = {
	[1] = { link = "item:1001::::::::90", name = "Helm of Stink", quality = 4, ilvl = 723, up = { trackString = "Hero", currentLevel = 6, maxLevel = 6 },
		lines = { { type = 31, leftText = "Item Level 723" }, { type = 0, leftText = "PvP Item Level 730" } }, sockets = { 213746, false }, stats = { ITEM_MOD_CRIT_RATING_SHORT = 500 } },
	[11] = { link = "item:1002:7334:::::::90", name = "Ring", quality = 5, ilvl = 730, up = { trackString = "Myth", currentLevel = 6, maxLevel = 6 },
		lines = { { type = 15, leftText = "Enchanted: Radiant Mastery" } }, stats = { ITEM_MOD_MASTERY_RATING_SHORT = 300 } },
	[17] = { link = "item:1003::::::::90", name = "Shield", quality = 4, ilvl = 720, classID = 4, lines = {} },
}
local h = CS.ReadSlot("player", 1)
check("cs ilvl", h.ilvl == 723)
check("cs pvp", h.pvp == 730)
check("cs track", h.track == "Hero" and h.cur == 6)
check("cs sockets", #h.sockets == 2 and h.sockets[1] == 4242 and h.sockets[2] == false)
check("cs not enchanted, enchantable", h.enchanted == false and h.enchantable == true)
ns.db.character.compact, ns.db.character.enchantIcons = false, false -- the full layout first
local l1, l2, l3 = CS.Lines(h, ns.db.character)
check("cs line1 name", l1:find("Helm of Stink"))
check("cs line2", l2:find("723") and l2:find("PvP 730") and l2:find("Hero 6/6"), l2)
check("cs missing enchant", l3:find("Enchant Missing"))
local r = CS.ReadSlot("player", 11)
local _, _, r3 = CS.Lines(r, ns.db.character)
check("cs enchant name", r3:find("Radiant Mastery"), r3)
local sh = CS.ReadSlot("player", 17)
check("cs shield not enchantable", sh.enchantable == false)
ns.db.character.line1 = "track"
local t1 = CS.Lines(h, ns.db.character)
check("cs track only", t1:find("Hero 6/6") and not t1:find("Helm"), t1)
check("cs ilvl on the track line", t1:find("723") and t1:find("PvP 730"), t1)
ns.db.character.line1 = "name"
-- compact: short name, short track, P for PvP, enchant icon instead of a line
ns.db.character.compact, ns.db.character.enchantIcons = true, true
local c1, c2, c3 = CS.Lines(h, ns.db.character)
check("compact line2", c2:find("723") and c2:find("PvP 730") and c2:find("H6/6") and c2:find("ReadyCheck%-NotReady"), c2)
check("compact no enchant line", c3 == "")
local _, rc2 = CS.Lines(r, ns.db.character)
check("compact enchanted icon", rc2:find("ReadyCheck%-Ready"), rc2)
check("short name drops set prefix", CS.ShortName("Venomous Gladiator's Amulet", 16) == "Amulet")
check("short name cap", CS.ShortName("Thalassian Competitor's Plate Sabatons of Doom", 10) == "Plate Saba..", CS.ShortName("Thalassian Competitor's Plate Sabatons of Doom", 10))
check("short name no prefix", CS.ShortName("Black Swashbuckler's Shirt", 0) == "Shirt")
check("short track", CS.ShortTrack("Champion") == "C" and CS.ShortTrack("Adventurer") == "Ad")
local tab = { slot = 19, name = "Tabard of Brute Force", quality = 1 }
check("no shirt / tabard text", CS.Lines(tab, ns.db.character) == "")
local tr, tg, tb = CS.TrackColor("Myth", 4)
check("cs myth color orange", tr == 1 and tg == 0.5)
check("cs stat label", CS.StatForLabel("Critical Strike:") == "crit" and CS.StatForLabel("Movement Speed:") == "speed")
for _, s in ipairs(CS.SLOTS) do CS.UpdateButton(_G["Character" .. s[2]], "player", s[1], s[3]) end
CS.Highlight("Character", "crit")
check("cs highlight crit on helm", CharacterHeadSlot.SUISheet.highlight:IsShown() and not CharacterFinger0Slot.SUISheet.highlight:IsShown())
CS.Highlight("Character", nil)
check("cs highlight off", not CharacterHeadSlot.SUISheet.highlight:IsShown())
local choices = CS.BackgroundChoices()
for _, v in ipairs(choices) do print("choice", v[1], v[2]) end
check("cs warband choices", #choices == 5 and choices[4][1] == "warband:3", #choices)
CharacterModelScene._w, CharacterModelScene._h = 231, 320
ns.db.character.background = "warband:7"
CS.ApplyBackground(CharacterModelScene)
check("cs warband bg across the window", (CharacterFrame.SUIWide and CharacterFrame.SUIWide.bg._tex == 5000) or CharacterModelScene.SUIBg._tex == 5000)
check("wide bg: model copy hidden", not CharacterFrame.SUIWide or not CharacterModelScene.SUIBg:IsShown())
CharacterStatsPane.ItemLevelFrame = MOCK.NewObj("Frame", nil, CharacterStatsPane)
CharacterStatsPane.ItemLevelFrame.Value = MOCK.NewObj("FontString", nil, CharacterStatsPane.ItemLevelFrame)
CS.UpdateItemLevel()
check("cs ilvl decimals", CharacterStatsPane.ItemLevelFrame.Value._text == "718.60", CharacterStatsPane.ItemLevelFrame.Value._text)
InspectFrame.unit = "target"
for _, s in ipairs(CS.SLOTS) do CS.UpdateButton(_G["Inspect" .. s[2]], "target", s[1], s[3]) end
CS.UpdateInspectItemLevel()
check("cs inspect ilvl", InspectPaperDollFrame.SUIIlvl._text:find("721.33"), InspectPaperDollFrame.SUIIlvl._text)
flushErrors("charsheet")

---------------------------------------------------------------------------
-- Objectives
---------------------------------------------------------------------------
ObjectiveTrackerFrame.NineSlice = MOCK.NewObj("Frame", nil, ObjectiveTrackerFrame)
ns.Objectives:Init()
MOCK.instanceType = "arena"
check("objectives hide in arena", ns.Objectives.WantHidden())
ns.Objectives.ApplyFrame()
check("objectives hidden by alpha, never Hide()", ObjectiveTrackerFrame._alpha == 0 and ObjectiveTrackerFrame:IsShown())
MOCK.instanceType = "none"
ns.Objectives.ApplyFrame()
check("objectives back", ObjectiveTrackerFrame._alpha == 1)
MOCK.instanceType = "arena"
MOCK.instanceType = "none"
check("objectives shown in world", not ns.Objectives.WantHidden())
ns.Objectives:Refresh()
check("objectives bg", ns.Objectives.bg and ns.Objectives.bg:IsShown())
flushErrors("objectives")

---------------------------------------------------------------------------
-- 0.28: flat skins and sizing
---------------------------------------------------------------------------
CharacterFrame.NineSlice = MOCK.NewObj("Frame", nil, CharacterFrame)
CharacterFrame.PortraitContainer = MOCK.NewObj("Frame", nil, CharacterFrame)
CharacterHeadSlotFrame:SetAlpha(1)
ns.CharacterSheet.ApplySkin()
check("skin hides frame art", CharacterFrame.NineSlice._alpha == 0 and CharacterFrame.PortraitContainer._alpha == 0)
check("skin hides slot frame", CharacterHeadSlotFrame._alpha == 0)
check("skin flat bg", CharacterFrame.SUIFlat ~= nil)
ns.CharacterSheet.ApplyScale()
check("character scale", math.abs(CharacterFrame._scale - ns.defaults.character.scale) < 1e-6, CharacterFrame._scale)
check("resizer", CharacterFrame.SUIResizer ~= nil)
ns.CharacterSheet.UpdateButton(CharacterHeadSlot, "player", 1, "RIGHT")
ns.Objectives.ApplyFlat()
check("objectives bg default 0", ns.db.objectives.bgAlpha == 0)
local mig = { version = 5, objectives = { bgAlpha = 0.5 }, units = {} }
ns.Migrate(mig)
check("migrate objectives alpha", mig.objectives.bgAlpha == 0)
flushErrors("flat")

-- 0.32: Blizzard's stat table is never edited (taint broke the window in rated PvP); our own rows instead
PAPERDOLL_STATCATEGORIES = { { categoryFrame = "EnhancementsCategory", stats = { { stat = "CRITCHANCE", hideAt = 0 }, { stat = "LIFESTEAL", hideAt = 0 } } } }
check("no ApplyStatRows any more", ns.CharacterSheet.ApplyStatRows == nil)
local function StatFrame(label, bottom)
	local f = MOCK.NewObj("Frame", nil, CharacterStatsPane)
	f.Label = MOCK.NewObj("FontString", nil, f); f.Label:SetText(label)
	f.GetBottom = function() return bottom end
	f.IsShown = function() return true end
	return f
end
local statFrames = { StatFrame("Critical Strike:", 300), StatFrame("Haste:", 285), StatFrame("Mastery:", 270) }
CharacterStatsPane.statsFramePool = { EnumerateActive = function() local i = 0; return function() i = i + 1; return statFrames[i] end end }
GetLifesteal = function() return 0 end
GetAvoidance = function() return 0 end
GetSpeed = function() return 0 end
GetUnitSpeed = function() return 7, 7, 4.5, 4.7 end
GetCombatRatingBonus = function() return 3 end
GetVersatilityBonus = function() return 0 end
CR_VERSATILITY_DAMAGE_DONE = 29
ns.db.character.hideZeroStats, ns.db.character.moveSpeed = false, true
ns.CharacterSheet.UpdateExtraStats()
local shownRows = {}
for _, r in ipairs(CharacterStatsPane.SUIExtraRows or {}) do if r:IsShown() then shownRows[#shownRows + 1] = r.Label._text .. " " .. r.Value._text end end
check("extra stat rows", #shownRows == 5 and shownRows[2] == "Leech: 0.00%" and shownRows[5] == "Movement Speed: 100.00%", table.concat(shownRows, ", "))
check("blizzard stat table untouched", PAPERDOLL_STATCATEGORIES[1].stats[1].hideAt == 0 and #PAPERDOLL_STATCATEGORIES[1].stats == 2)
GetLifesteal = function() return { __secret = true } end
ns.db.character.hideZeroStats = true
ns.CharacterSheet.UpdateExtraStats()
shownRows = {}
for _, r in ipairs(CharacterStatsPane.SUIExtraRows) do if r:IsShown() then shownRows[#shownRows + 1] = r.Label._text end end
check("hide zero keeps movement speed only", #shownRows == 1 and shownRows[1] == "Movement Speed:", table.concat(shownRows, ", "))
ns.db.character.hideZeroStats = false
ns.CharacterSheet.UpdateExtraStats()
shownRows = 0
for _, r in ipairs(CharacterStatsPane.SUIExtraRows) do if r:IsShown() then shownRows = shownRows + 1 end end
check("secret value row skipped", shownRows == 4, shownRows)

ns.CharacterSheet.HoverRow(statFrames[1], true)
check("hovered stat row tinted", statFrames[1].SUIHover and statFrames[1].SUIHover:IsShown())
ns.CharacterSheet.HoverRow(statFrames[1], false)
check("hover tint off", not statFrames[1].SUIHover:IsShown())
local nonPvp = { slot = 2, ilvl = 720, pvp = 720, quality = 4, sockets = {} }
local _, nl2 = ns.CharacterSheet.Lines(nonPvp, ns.db.character)
check("no PvP ilvl when same", not nl2:find("PvP"), nl2)
local all = 0
for _, s in ipairs(ns.CharacterSheet.SLOTS) do if _G["Character" .. s[2]].SUISheet and _G["Character" .. s[2]].SUISheet.line2 then all = all + 1 end end
check("every slot got its overlay", all == #ns.CharacterSheet.SLOTS, all)
flushErrors("stats")

-- 0.29: stats sorting by column, opponent / faction groups, my-spec filter, unrated not saved
local Dh = StinkieUI_History.Data
Dh.BuildSummaries()
local opp = Dh.Group(Dh.summaries, "opponent")
check("group by opponent", opp[1] and opp[1].key:find("Enemy") or opp[1].key:find("Foe"), opp[1] and opp[1].key)
check("faction group exists", type(Dh.GROUP_BY.faction) == "function")
local bgSum = Dh.Summarize({ bracket = "blitz", t = 1, me = 1, players = { { name = "Me-R", team = 0 }, { name = "Them-R", team = 1 } } }, 1)
check("faction from blitz team", bgSum.side == "Horde")
local arenaSum = Dh.Summarize({ bracket = "3v3", t = 1, me = 1, players = { { name = "Me-R", team = 0 } } }, 1)
check("no faction in arena", arenaSum.side == nil)
local specFiltered = Dh.Filter(Dh.summaries, { spec = 267 })
check("my spec filter", #specFiltered > 0 and #specFiltered < #Dh.summaries, #specFiltered)
local rows = Dh.Group(Dh.summaries, "map")
StinkieUI_History.Toggle("stats")
StinkieUI_History.SortRows(rows)
local okDesc = true
for i = 2, #rows do if rows[i - 1].games < rows[i].games then okDesc = false end end
check("sort by games desc", okDesc)
check("migrate unrated off", (function() local d = { version = 6, units = {}, matchHistory = { skirmish = true, battleground = true, brawl = true } }; ns.Migrate(d); return d.matchHistory.skirmish == false and d.matchHistory.brawl == false end)())
MOCK.bracket = "arena"
local was = #StinkieUIMatchInbox.records + #Dh.Archive().records
local oldRated = C_PvP.IsRatedArena
C_PvP.IsRatedArena = function() return false end -- a skirmish
MOCK.Fire("PVP_MATCH_ACTIVE")
MOCK.Fire("PVP_MATCH_COMPLETE", 0, 100)
MOCK.Advance(1.2)
check("skirmish not saved", #StinkieUIMatchInbox.records + #Dh.Archive().records == was)
C_PvP.IsRatedArena = oldRated
flushErrors("0.29")

-- 0.30: MMR change, roomy layout, outside gems, remembered window sizes
ns.MatchRecorder.RememberMMR({ char = "Stinkie-Tichondrius", bracket = "shuffle", spec = 267, mmr = 2700, mmrAfter = 2773, ratingAfter = 2800, t = 2000000000 })
local q = ns.QueueInfo.LastMMR("shuffle")
check("mmr per spec with delta", q and q.mmr == 2773 and q.delta == 73, q and q.delta)
check("delta text green", ns.QueueInfo.DeltaText(73):find("55ff55") and ns.QueueInfo.DeltaText(-40):find("ff5555") and ns.QueueInfo.DeltaText(-40):find("-40"))
ns.CharacterSheet.ApplyLayout()
check("roomy model size", CharacterModelScene._w == 231 + 90 and CharacterModelScene._h == 320 + 70, CharacterModelScene._w)
check("roomy frame height", CharacterFrame._h == 424 + 70)
check("opacity default 0.9", ns.db.character.frameAlpha == 0.9)
MOCK.items[1].sockets = { 213746, false }
ns.CharacterSheet.UpdateButton(CharacterHeadSlot, "player", 1, "RIGHT")
local gem = CharacterHeadSlot.SUISheet.gems[1]
local gp = gem and { gem:GetPoint() }
check("gems outside the icon", gem and gem:IsShown())
local mig8 = { version = 7, units = {}, character = { frameAlpha = 0.95, textWidth = 110 } }
ns.Migrate(mig8)
check("migrate to 0.9 / 140", mig8.character.frameAlpha == 0.9 and mig8.character.textWidth == 140)
StinkieUI_History.Toggle("matches")
check("history window remembers", StinkieUIMatchHistory.window ~= nil)
flushErrors("0.30")

-- 0.31: Window Mover
local WMv = ns.WindowMover
WMv.HookAll()
check("mover hooked character frame", CharacterFrame.SUIMove)
check("mover hooked spells (auto global)", PlayerSpellsFrame.SUIMove)
CharacterFrame._scripts.OnMouseDown(CharacterFrame, "LeftButton")
CharacterFrame._scripts.OnMouseUp(CharacterFrame, "LeftButton")
check("mover saved point", ns.db.windowMover.frames.CharacterFrame and ns.db.windowMover.frames.CharacterFrame.point)
local before = CharacterFrame:GetScale()
IsControlKeyDown = function() return true end
CollectionsJournal:SetScale(1)
CollectionsJournal._scripts.OnMouseWheel(CollectionsJournal, 1)
check("ctrl wheel scales", math.abs(CollectionsJournal:GetScale() - 1.05) < 1e-9, CollectionsJournal:GetScale())
check("ctrl wheel saved", ns.db.windowMover.frames.CollectionsJournal.scale == 1.05)
CharacterFrame:SetScale(1.2)
CharacterFrame._scripts.OnMouseWheel(CharacterFrame, -1)
check("character size is the character sheet setting", ns.db.character.scale == 1.15, ns.db.character.scale)
IsControlKeyDown = nil
WMv.Apply("CollectionsJournal")
WMv.Reset("CollectionsJournal")
check("reset one", ns.db.windowMover.frames.CollectionsJournal == nil)
WMv.ResetAll()
check("reset all", next(ns.db.windowMover.frames) == nil and ns.db.character.scale == ns.defaults.character.scale)
flushErrors("windowmover")

---------------------------------------------------------------------------
-- 0.32: buff frame, sidebar tabs, equipment buttons, arena target border, DR tracker gone
---------------------------------------------------------------------------
local function AuraButton(parent)
	local b = MOCK.NewObj("Button", nil, parent)
	b.Icon = MOCK.NewObj("Texture", nil, b)
	b.Duration = MOCK.NewObj("FontString", nil, b)
	b.Count = MOCK.NewObj("FontString", nil, b)
	b.TempEnchantBorder = MOCK.NewObj("Texture", nil, b)
	b.TempEnchantBorder:Hide()
	return b
end
BuffFrame = MOCK.NewObj("Frame", "BuffFrame", UIParent)
BuffFrame.auraFrames = { AuraButton(BuffFrame), AuraButton(BuffFrame), MOCK.NewObj("Frame", nil, BuffFrame) }
BuffFrame.CollapseAndExpandButton = MOCK.NewObj("Button", nil, BuffFrame)
DebuffFrame = MOCK.NewObj("Frame", "DebuffFrame", UIParent)
DebuffFrame.auraFrames = { AuraButton(DebuffFrame) }
ns.Buffs.ApplySkin()
check("buff icons get a border", BuffFrame.auraFrames[1].SUIEdge ~= nil and DebuffFrame.auraFrames[1].SUIEdge ~= nil)
MOCK.instanceType = "arena"
ns.Buffs.UpdateVisibility()
check("buffs hidden in arena", BuffFrame._alpha == 0 and BuffFrame.CollapseAndExpandButton._alpha == 0)
check("debuffs stay in arena by default", DebuffFrame._alpha == 1)
ns.db.buffs.debuffs = true
ns.Buffs.UpdateVisibility()
check("debuffs hidden when chosen", DebuffFrame._alpha == 0)
MOCK.instanceType = "none"
ns.Buffs.UpdateVisibility()
check("buffs back outside", BuffFrame._alpha == 1 and DebuffFrame._alpha == 1)
ns.db.buffs.debuffs = false
flushErrors("buffs")

for i = 1, 3 do
	local t = MOCK.NewObj("Button", "PaperDollSidebarTab" .. i, CharacterFrame)
	t.TabBg = MOCK.NewObj("Texture", nil, t); t.Hider = MOCK.NewObj("Texture", nil, t); t.Highlight = MOCK.NewObj("Texture", nil, t); t.Icon = MOCK.NewObj("Texture", nil, t)
	t.GetID = function() return i end
	t.IsEnabled = function() return true end
end
local panes = { MOCK.NewObj("Frame", nil, CharacterFrame), MOCK.NewObj("Frame", nil, CharacterFrame), MOCK.NewObj("Frame", nil, CharacterFrame) }
panes[2]:Hide(); panes[3]:Hide()
GetPaperDollSideBarFrame = function(i) return panes[i] end
PaperDollFrame.EquipmentManagerPane = MOCK.NewObj("Frame", nil, PaperDollFrame)
for _, k in ipairs({ "EquipSet", "SaveSet" }) do
	local b = MOCK.NewObj("Button", nil, PaperDollFrame.EquipmentManagerPane)
	b.Left, b.Middle, b.Right = MOCK.NewObj("Texture", nil, b), MOCK.NewObj("Texture", nil, b), MOCK.NewObj("Texture", nil, b)
	b.IsEnabled = function() return true end
	PaperDollFrame.EquipmentManagerPane[k] = b
end
ns.CharacterSheet.ApplySkin("Character")
check("sidebar tab flat", PaperDollSidebarTab1.SUIFlat ~= nil and PaperDollSidebarTab1.TabBg._alpha == 0 and PaperDollSidebarTab1.Hider._alpha == 0)
check("open tab gets the line", PaperDollSidebarTab1.SUILine:IsShown() and not PaperDollSidebarTab2.SUILine:IsShown())
local eq = PaperDollFrame.EquipmentManagerPane.EquipSet
check("equip button flat", eq.SUIFill ~= nil and eq.Left._alpha == 0 and eq.Middle._alpha == 0 and eq.Right._alpha == 0)
flushErrors("sidebar")

check("arena target border default", ns.db.arena.targetBorder == 3)
check("DR tracker gone", ns.PvPDR == nil and ns.db.arenaAssist.drSpells == nil)
local mig9 = { version = 8, queueInfo = { width = 300 }, arenaAssist = { dr = true, drSpells = {}, drPoint = {}, kickSize = 40 }, units = {} }
ns.Migrate(mig9)
check("migrate v9", mig9.queueInfo.width == 440 and mig9.arenaAssist.dr == nil and mig9.arenaAssist.drSpells == nil and mig9.arenaAssist.kickSize == 40)
flushErrors("0.32")
-- the queue time is attached to the next saved match of that bracket
StinkieUIDB.queueTrack["Stinkie-Tichondrius"].popped["3v3"] = { secs = 83, t = time() }
MOCK.instanceType, MOCK.bracket = "arena", "arena"
for _, sc in ipairs(MOCK.scores) do sc.stats = {} end
local before = #D.Archive().records
MOCK.Fire("PVP_MATCH_ACTIVE")
MOCK.Fire("PVP_MATCH_COMPLETE", 0, 312)
MOCK.Advance(1.1)
local qm = D.Get(#D.Archive().records)
check("match got its queue time", #D.Archive().records == before + 1 and qm and qm.queue == 83, tostring(qm and qm.queue))
MOCK.instanceType = "none"
H.Toggle("matches")
local qcell
for _, r in ipairs(StinkieUI_MatchHistory.matches and StinkieUI_MatchHistory.matches.rows or {}) do if r.summary and r.summary.queue == 83 then qcell = r.cells[8]._text end end
check("queue column", qcell == "1:23", tostring(qcell))
H.Toggle("stats")
flushErrors("queue column")

---------------------------------------------------------------------------
-- 0.33
---------------------------------------------------------------------------
-- healer cross never on classes without a healing spec
local oldClass = UnitClass
UnitClass = function() return "Mage", "MAGE", 8 end
check("mage can't heal", ns.CanHeal("nameplate1") == false)
UnitClass = function() return "Priest", "PRIEST", 5 end
check("priest can heal", ns.CanHeal("nameplate1") == true)
UnitClass = function() return { __secret = true }, { __secret = true }, 0 end
check("hidden class falls back to role sources", ns.CanHeal("nameplate1") == true)
UnitClass = oldClass

-- queue: equal columns, N/A for unrated, unknown without a match
MOCK.instanceType = "none"
ns.db.queueInfo.hideInPvP = true
MOCK.queues = { { status = "queued", name = "Arena Skirmish", size = 2, rated = false, qt = "ARENASKIRMISH", waited = 5000, est = 30000 },
	{ status = "queued", name = "Arena", size = 3, rated = true, qt = "ARENA", waited = 65000, est = 120000 } }
StinkieUIDB.lastMMR["Stinkie-Tichondrius"]["3v3"] = { rating = 1864, t = 5 } -- a match with no MMR from the game
MOCK.Fire("UPDATE_BATTLEFIELD_STATUS")
local qrows = {}
for _, o in ipairs(MOCK.frames) do if o.cells and o._parent == ns.QueueInfo.holder then qrows[#qrows + 1] = o end end
local function rowText(r) local t = { r.label._text }; for _, c in ipairs(r.cells) do t[#t + 1] = c._text end; return table.concat(t, " | ") end
local all3 = {}
for _, r in ipairs(qrows) do if r:IsShown() then all3[#all3 + 1] = rowText(r) end end
local qj = table.concat(all3, " // ")
check("skirmish MMR N/A", qj:find("Skirmish | 0:05 | est 0:30 | |cffaaaaaaMMR N/A|r", 1, true), qj)
check("3v3 without MMR is N/A", qj:find("3v3 | 1:05 | est 2:00 | |cffaaaaaaMMR N/A|r", 1, true), qj)
MOCK.queues = {}
MOCK.Fire("UPDATE_BATTLEFIELD_STATUS")
flushErrors("queue 0.33")

-- recorder waits for the rating / MMR change
check("no changes yet", ns.MatchRecorder.HasChanges({ me = 1, players = { { rchg = 0, mmrchg = 0 } } }) == false)
check("has change", ns.MatchRecorder.HasChanges({ me = 1, players = { { rchg = 14, mmrchg = 0 } } }) == true)

-- arena DEAD / FEIGN
local af = ns.Arena.frames[1]
UnitIsFeignDeath = function() return false end
MOCK.dead = true
af.preview = nil
af.unit = "arena1"
af:PostUpdate()
check("arena dead text", af.Status:IsShown() and af.Status._text:find("DEAD"), af.Status._text)
UnitIsFeignDeath = function() return true end
af:PostUpdate()
check("arena feign text", af.Status._text:find("FEIGN"), af.Status._text)
MOCK.dead = false
UnitIsFeignDeath = function() return false end
af:PostUpdate()
check("arena status clears", not af.Status:IsShown())
flushErrors("arena status")

-- flag cap only on Warsong Gulch / Twin Peaks
check("kotmogu is the orb map", ns.BGEnemies.KOTMOGU == 998)
local oldInfo = GetInstanceInfo
GetInstanceInfo = function() return "Temple of Kotmogu", "pvp", 0, "", 10, 0, false, 998 end
check("kotmogu detected", ns.BGEnemies.IsKotmogu())
GetInstanceInfo = oldInfo

-- match stats: map + faction grouping, search narrows groups
check("map faction key", D.GROUP_BY.mapFaction({ map = "Warsong Gulch", side = "Horde" }) == "Warsong Gulch - Horde")
check("no faction in arena", D.GROUP_BY.mapFaction({ map = "Nagrand Arena" }) == nil)

-- vehicle exit keeps showing on a faded bar
MainMenuBarVehicleLeaveButton = MOCK.NewObj("Button", "MainMenuBarVehicleLeaveButton", UIParent)
local ign
MainMenuBarVehicleLeaveButton.SetIgnoreParentAlpha = function(_, v) ign = v end
ns.ActionBars.KeepVehicleExit()
check("vehicle exit ignores bar fade", ign == true)

-- unticking a bar the preset hides: the choice survives a reload
do
	local db = ns.CopyDefaults(ns.defaults, { actionBars = { mouseover = { MainActionBar = false } } })
	check("preset hides Action Bar 1", ns.defaults.actionBars.mouseover.MainActionBar == true)
	check("unticked bar stays unticked after reload", db.actionBars.mouseover.MainActionBar == false)
	check("other preset bars keep their default", db.actionBars.mouseover.MultiBarLeft == true)
end

-- lock buttons: the game's own setting
ns.ActionBars.SetButtonsLocked(true)
check("lock buttons on", ns.ActionBars.ButtonsLocked() == true and MOCK.cvars.lockActionBars == "1")
ns.ActionBars.SetButtonsLocked(false)
check("lock buttons off", ns.ActionBars.ButtonsLocked() == false and MOCK.cvars.lockActionBars == "0")

-- first / last / both
local Short = ns.ShortenName
check("name: both is untouched", Short("Stormwind Guard", "full") == "Stormwind Guard" and Short("Stormwind Guard") == "Stormwind Guard")
check("name: last", Short("Stormwind Guard", "last") == "Guard")
check("name: first", Short("Stormwind Guard", "first") == "Stormwind")
check("name: one word", Short("Stinkie", "last") == "Stinkie" and Short("Stinkie", "first") == "Stinkie")
check("name: title after comma", Short("Thrall, Warchief of the Horde", "last") == "Thrall")
check("name: stray spaces", Short("Lady Liadrin ", "last") == "Liadrin" and Short(" Lady Liadrin", "first") == "Lady")
check("name: accents", Short("Élan Vitàl", "last") == "Vitàl" and Short("Vitàl Élan", "first") == "Vitàl")
check("name: nothing to shorten", Short(nil, "last") == nil and Short("", "first") == "")
do
	local secret, old = {}, ns.issecret
	ns.issecret = function(v) return v == secret end
	check("name: secret passes through untouched", Short(secret, "last") == secret)
	ns.issecret = old
end
do
	local f = ns.UF.frames.player
	local oldUnitName, oldShown = UnitName, f.Name:IsShown()
	UnitName = function(u) if u == f.unit then return "Stormwind Guard" end return oldUnitName(u) end
	f.Name:SetShown(true)
	f.nameFormat = "full"
	ns.UF.UpdateName(f)
	check("unit frame: full name by default", f.Name:GetText() == "Stormwind Guard", f.Name:GetText())
	f.nameFormat = "last"
	ns.UF.UpdateName(f)
	check("unit frame: last name", f.Name:GetText() == "Guard", f.Name:GetText())
	f.nameFormat = "first"
	ns.UF.UpdateName(f)
	check("unit frame: first name", f.Name:GetText() == "Stormwind", f.Name:GetText())
	f.nameFormat = "full"
	UnitName = oldUnitName
	f.Name:SetShown(oldShown)
end

-- player frame level
do
	local f = ns.UF.frames.player
	local cfg = ns.db.units.player
	MOCK.unitLevels = { player = 90 }
	check("level off by default", cfg.showLevel == false and not f.Level:IsShown())
	cfg.showLevel = true
	ns.UF.Layout(f, cfg)
	ns.UF.UpdateLevel(f)
	check("level shows", f.Level:IsShown() and tostring(f.Level:GetText()) == "90", f.Level:GetText())
	MOCK.unitLevels.player = 91
	f:GetScript("OnEvent")(f, "UNIT_LEVEL", "player")
	check("level updates on ding", tostring(f.Level:GetText()) == "91", f.Level:GetText())
	cfg.showLevel = false
	ns.UF.Layout(f, cfg)
	check("level hides again", not f.Level:IsShown())
	-- every unit frame has one, and a boss reads ??
	local t = ns.UF.frames.target
	local tc = ns.db.units.target
	MOCK.unitLevels.target = -1
	tc.showLevel = true
	ns.UF.Layout(t, tc)
	ns.UF.UpdateLevel(t)
	check("boss level reads ??", t.Level:IsShown() and t.Level:GetText() == "??", t.Level:GetText())
	tc.showLevel = false
	ns.UF.Layout(t, tc)
	for _, key in ipairs({ "player", "target", "targettarget", "focus", "pet" }) do
		check(key .. " has the level option", ns.db.units[key].showLevel == false and ns.db.units[key].nameFormat == "full")
	end
	for _, key in ipairs({ "party", "arena", "partyTargets" }) do
		check(key .. " has the level option", ns.db[key].showLevel == false and ns.db[key].nameFormat == "full")
	end
end

-- party frames: the level comes first and the name follows it, both in the top corner
do
	local f = MOCK.NewObj("Frame", "PlaceNameFrame", UIParent)
	f.Name, f.Level = MOCK.NewObj("Frame", "PlaceName", f), MOCK.NewObj("Frame", "PlaceLevel", f)
	local levelAnchor, nameAnchor
	f.Level.SetPoint = function(_, p) levelAnchor = p end
	f.Name.SetPoint = function(_, p, rel) if p == "LEFT" or p == "TOPLEFT" then nameAnchor = { p, rel } end end
	f.Level:Show()
	ns.UF.PlaceNameTopLeft(f)
	check("level in the corner", levelAnchor == "TOPLEFT")
	check("name after the level", nameAnchor[1] == "LEFT" and nameAnchor[2] == f.Level)
	f.Level:Hide()
	ns.UF.PlaceNameTopLeft(f)
	check("name in the corner without level", nameAnchor[1] == "TOPLEFT" and nameAnchor[2] == f)
end

-- target markers
do
	local tex = MOCK.NewObj("Texture", "MarkerTex", UIParent)
	local set
	local oldIndex, oldSet = GetRaidTargetIndex, SetRaidTargetIconTexture
	SetRaidTargetIconTexture = function(_, i) set = i end
	GetRaidTargetIndex = function() return nil end
	tex:Show()
	ns.UpdateMarker(tex, "party1")
	check("no marker: hidden", not tex:IsShown())
	GetRaidTargetIndex = function() return 8 end
	ns.UpdateMarker(tex, "party1")
	check("marker shown", tex:IsShown() and set == 8, set)
	-- a secret index goes straight to the setter; a refusal keeps it hidden
	local secret, oldSecret = {}, ns.issecret
	GetRaidTargetIndex = function() return secret end
	ns.issecret = function(v) return v == secret end
	ns.UpdateMarker(tex, "party1")
	check("secret marker reaches the setter", tex:IsShown() and set == secret)
	SetRaidTargetIconTexture = function() error("refused") end
	ns.UpdateMarker(tex, "party1")
	check("refused marker stays hidden", not tex:IsShown())
	ns.issecret = oldSecret
	GetRaidTargetIndex, SetRaidTargetIconTexture = oldIndex, oldSet
	check("marker defaults", ns.db.nameplates.marker == true and ns.db.party.marker == false)
end

-- keybinds off: shown only on the bar under the mouse
do
	local AB, cfg = ns.ActionBars, ns.db.actionBars
	local function Button(bar)
		local b = MOCK.NewObj("Button", nil, bar)
		b.HotKey = MOCK.NewObj("FontString", nil, b)
		return b
	end
	local hovered = false
	local bar = MOCK.NewObj("Frame", "MultiBar7", UIParent)
	bar.actionButtons = { Button(bar), Button(bar) }
	bar.IsMouseOver = function() return hovered end
	_G.MultiBar7 = bar
	local key = bar.actionButtons[1].HotKey
	local oldHot, oldHover = cfg.hotkeys, cfg.hotkeysHover
	key:SetAlpha(0)
	cfg.hotkeys, cfg.hotkeysHover = false, false
	hovered = true
	AB.UpdateHotkeyHover()
	check("hover option off: keybinds stay hidden", key:GetAlpha() == 0)
	cfg.hotkeysHover = true
	AB.UpdateHotkeyHover()
	check("hovering shows the bar's keybinds", key:GetAlpha() == 1 and bar.actionButtons[2].HotKey:GetAlpha() == 1)
	hovered = false
	AB.UpdateHotkeyHover()
	check("leaving hides them", key:GetAlpha() == 0)
	hovered = true
	AB.UpdateHotkeyHover()
	AB.SkinBar(bar) -- a reskin hides them again; the next tick has to bring them back
	check("reskin hides keybinds", key:GetAlpha() == 0)
	AB.UpdateHotkeyHover()
	check("still hovering after a reskin", key:GetAlpha() == 1)
	cfg.hotkeys = true
	hovered = false
	AB.SkinBar(bar)
	AB.UpdateHotkeyHover()
	check("keybinds on: hover changes nothing", key:GetAlpha() == 1)
	cfg.hotkeys, cfg.hotkeysHover = oldHot, oldHover
	_G.MultiBar7 = nil
end

-- quest marker: follows Blizzard's tracked spot, and stands in for its diamond
do
	local QA, c = ns.QuestArrow, ns.db.misc.questArrow
	local pi = math.pi
	local function near(a, b) return math.abs(a - b) < 0.0001 end
	check("marker off by default", c.enabled == false and not QA.holder:IsShown())
	-- textures rotate counter-clockwise from up
	check("off screen above", near(QA.EdgeRotation(100, 200, 100, 100), 0))
	check("off screen to the right", near(QA.EdgeRotation(200, 100, 100, 100), -pi / 2))
	check("off screen to the left", near(QA.EdgeRotation(0, 100, 100, 100), pi / 2))
	check("off screen below", near(math.abs(QA.EdgeRotation(100, 0, 100, 100)), pi))

	do
		local x, y = QA.EdgePosition(250, 0, 900, 480)
		check("edge: straight out to the side", near(x, 900) and near(y, 0), x)
		x, y = QA.EdgePosition(-250, 0, 900, 480)
		check("edge: the left side too", near(x, -900) and near(y, 0), x)
		x, y = QA.EdgePosition(0, 100, 900, 480)
		check("edge: straight up", near(x, 0) and near(y, 480), y)
		x, y = QA.EdgePosition(100, 100, 900, 480)
		check("edge: a corner stops at the nearer edge", near(x, 480) and near(y, 480), x)
		x, y = QA.EdgePosition(0, 0, 900, 480)
		check("edge: nothing to go on", x == 0 and y == 0)
	end
	check("close up: full size", near(QA.DistanceScale(0), 1) and near(QA.DistanceScale(50), 1))
	check("far away: smallest", near(QA.DistanceScale(1000), 0.6) and near(QA.DistanceScale(5000), 0.6))
	check("in between: on the way down", near(QA.DistanceScale(525), 0.8))

	local saved = {}
	local function stub(name, v) saved[name] = _G[name] == nil and false or _G[name]; _G[name] = v end
	local nav, clamped, distance, kind, quest = true, false, 42.4, 1, 77
	local validScreen, navState = true, 2
	stub("C_Navigation", {
		GetFrame = function() return nav end,
		WasClampedToScreen = function() return clamped end,
		GetDistance = function() return distance end,
		HasValidScreenPosition = function() return validScreen end,
		GetTargetState = function() return navState end,
	})
	stub("C_SuperTrack", {
		GetHighestPrioritySuperTrackingType = function() return kind end,
		GetSuperTrackedQuestID = function() return quest end,
	})
	local inArea, questDone = false, false
	stub("C_QuestLog", {
		GetTitleForQuestID = function(id) return "Quest " .. id end,
		IsComplete = function() return questDone end,
	})
	stub("C_Minimap", { IsInsideQuestBlob = function() return inArea end })
	local oldType = Enum.SuperTrackingType
	Enum.SuperTrackingType = { Quest = 1, Corpse = 5 }
	local oldState = Enum.NavigationState
	Enum.NavigationState = { Invalid = 0, Occluded = 1, InRange = 2, Disabled = 3 }
	local blizzard = MOCK.NewObj("Frame", "SuperTrackedFrame", UIParent)
	blizzard.Icon = MOCK.NewObj("Texture", nil, blizzard)
	blizzard.Arrow = MOCK.NewObj("Texture", nil, blizzard)
	blizzard.DistanceText = MOCK.NewObj("FontString", nil, blizzard)
	blizzard.GetCenter = function() return 900, 100 end
	stub("SuperTrackedFrame", blizzard)
	local oldWorld = WorldFrame
	WorldFrame = { GetCenter = function() return 500, 100 end }
	local oldScale = UIParent.GetEffectiveScale
	UIParent.GetEffectiveScale = function() return 1 end
	local oldWidth, oldHeight = UIParent.GetWidth, UIParent.GetHeight
	UIParent.GetWidth = function() return 1000 end
	UIParent.GetHeight = function() return 600 end
	local h = QA.holder
	local turned
	h.Arrow.SetRotation = function(_, r) turned = r end

	QA.Update()
	check("off: Blizzard's diamond stays", blizzard.Icon:GetAlpha() == 1 and not h:IsShown())

	c.enabled = true
	ns:Refresh(); MOCK.Advance(0.2)
	check("marker shows", h:IsShown())
	check("Blizzard's diamond hidden", blizzard.Icon:GetAlpha() == 0 and blizzard.DistanceText:GetAlpha() == 0 and blizzard.Arrow:GetAlpha() == 0)
	check("marker shows yards", h.Distance:GetText() == "42 yd", h.Distance:GetText())
	-- raised off the spot on screen, but not at the screen edge
	local raised
	h.SetPoint = function(_, _, _, _, _, y) raised = y end
	c.height = 90
	ns:Refresh(); MOCK.Advance(0.2)
	check("height setting raises the marker", raised == 90, raised)
	clamped = true
	QA.Update()
	check("edge arrow isn't raised", raised == 0, raised)
	-- Blizzard has it 400 right of center; it goes out to 60 from the 1000 wide screen edge
	local atX
	h.SetPoint = function(_, _, _, _, x) atX = x end
	c.edgeMargin = 60
	QA.Update()
	check("edge arrow sits near the screen edge", near(atX, 440), atX)
	c.edgeMargin = 200
	QA.Update()
	check("edge gap is a setting", near(atX, 300), atX)
	c.edgeMargin = ns.defaults.misc.questArrow.edgeMargin
	h.SetPoint = function(_, _, _, _, _, y) raised = y end
	clamped = false
	QA.Update()
	check("raised again back on screen", raised == 90, raised)
	h.SetPoint = nil
	c.height = ns.defaults.misc.questArrow.height
	local scaled
	h.SetScale = function(_, s) scaled = s end
	distance = 1000
	QA.Update()
	check("far away: the marker shrinks", near(scaled, 0.6), scaled)
	clamped = true
	QA.Update()
	check("off screen: the arrow stays full size", scaled == 1, scaled)
	clamped = false
	distance = 42.4
	QA.Update()
	check("close up: full size again", near(scaled, 1), scaled)
	h.SetScale = nil
	check("marker names the quest", h.Name:GetText() == "Quest 77", h.Name:GetText())
	check("on screen: plate with the arrow pointing down", h.Plate:IsShown() and near(turned, pi))

	check("yards draw above the plate", h.Distance:GetParent() == h.TextLayer)
	blizzard:SetAlpha(0.2) -- Blizzard's fade near the mouse
	QA.Update()
	check("the mouse doesn't fade the marker", h:GetAlpha() == 1)
	blizzard:SetAlpha(1)
	navState = 1
	QA.Update()
	check("something in the way dims it", h:GetAlpha() == 0.6)
	clamped = true
	QA.Update()
	check("the edge arrow stays bright", h:GetAlpha() == 1)
	clamped = false
	navState = 0
	QA.Update()
	check("invalid state with a screen position: still shown", h:GetAlpha() == 1)
	navState = 3
	QA.Update()
	check("disabled: hidden", h:GetAlpha() == 0)
	navState = 2
	validScreen = false
	QA.Update()
	check("no screen position: hidden", h:GetAlpha() == 0)
	validScreen = true
	QA.Update()

	clamped = true
	QA.Update()
	check("off screen: arrow only", not h.Plate:IsShown())
	check("off screen: arrow points the way", near(turned, -pi / 2), turned)
	check("off screen: yards stay", h.Distance:GetText() == "42 yd")
	clamped = false
	QA.Update()
	check("back on screen", h.Plate:IsShown() and near(turned, pi))

	quest = 88
	QA.Update()
	check("a new tracked quest is picked up", h.Name:GetText() == "Quest 88")

	-- in the quest area with things left to find: nothing to point at
	inArea = true
	QA.Update()
	check("in the quest area: marker gone", not h:IsShown())
	check("in the quest area: Blizzard's diamond stays hidden too", blizzard.Icon:GetAlpha() == 0)
	questDone = true
	QA.Update()
	check("finished quest: still points at the turn-in", h:IsShown())
	questDone = false
	inArea = false
	QA.Update()
	check("leaving the area: marker back", h:IsShown())
	C_Minimap = {}
	QA.Update()
	check("a client without the area check: marker stays", h:IsShown())
	C_Minimap = { IsInsideQuestBlob = function() return inArea end }

	-- dead: your corpse, even where a quest area would hide the marker
	kind = 5
	inArea = true
	QA.Update()
	check("corpse: marker shows", h:IsShown() and blizzard.Icon:GetAlpha() == 0)
	check("corpse: named", h.Name:GetText() == "Your corpse", h.Name:GetText())
	kind = 1
	inArea = false
	QA.Update()
	check("alive again: back to the quest", h.Name:GetText() == "Quest 88", h.Name:GetText())

	-- a map pin or anything else: Blizzard's own marker comes back
	kind = 2
	QA.Update()
	check("not a quest: marker gone", not h:IsShown() and blizzard.Icon:GetAlpha() == 1)
	kind = 1
	nav = nil
	QA.Update()
	check("nothing to navigate to: marker gone", not h:IsShown() and blizzard.Icon:GetAlpha() == 1)
	nav = true
	quest = 0
	QA.Update()
	check("no quest tracked: marker gone", not h:IsShown())
	quest = 77

	c.enabled = false
	ns:Refresh(); MOCK.Advance(0.2)
	check("turned off: Blizzard's diamond back", not h:IsShown() and blizzard.Icon:GetAlpha() == 1)

	-- /stinkie quest reports each step
	do
		local lines, oldPrint = {}, ns.Print
		ns.Print = function(_, m) lines[#lines + 1] = m end
		quest = 77
		QA.Debug()
		ns.Print = oldPrint
		local text = table.concat(lines, "\n")
		check("debug names the tracked quest", text:find("tracked quest: 77", 1, true) ~= nil, text)
		check("debug reports navigation", text:find("navigation frame: true", 1, true) ~= nil, text)
		check("debug reports the marker", text:find("marker shown", 1, true) ~= nil, text)
	end

	-- a client without Blizzard's frame
	SuperTrackedFrame = nil
	QA.Update()
	check("no Blizzard frame: nothing breaks", true)

	Enum.SuperTrackingType = oldType
	Enum.NavigationState = oldState
	WorldFrame = oldWorld
	UIParent.GetEffectiveScale = oldScale
	UIParent.GetWidth, UIParent.GetHeight = oldWidth, oldHeight
	h.Arrow.SetRotation = nil
	QA.blizzardShown, QA.clamped, QA.target = nil, nil, nil
	for k, v in pairs(saved) do _G[k] = v or nil end
end
flushErrors("quest arrow")

-- swing timers: Blizzard's bars restyled, and clients without them are fine
do
	local ST = ns.SwingTimers
	ST.SkinAll() -- no such frames here: nothing to do, nothing breaks
	check("no swing timers: no error", true)
	local function Tex(parent) return MOCK.NewObj("Texture", nil, parent) end
	local function Bar(name)
		local f = MOCK.NewObj("Frame", name, UIParent)
		f.Background, f.Border = Tex(f), Tex(f)
		f.StatusBar = MOCK.NewObj("StatusBar", nil, f)
		local b = f.StatusBar
		b.Pip, b.TypeLabelShadow = Tex(b), Tex(b)
		b.TypeLabel, b.TimeLabel = MOCK.NewObj("FontString", nil, b), MOCK.NewObj("FontString", nil, b)
		local colors = {}
		b.TimeLabel.SetTextColor = function(_, r, g, bl) colors.time = { r, g, bl } end
		b.SetStatusBarColor = function(_, r, g, bl) colors.bar = { r, g, bl } end
		b.GetStatusBarTexture = function() return b.fill end
		b.fill = Tex(b)
		f.colors = colors
		f.outOfRange = false
		f.IsOutOfRange = function(self) return self.outOfRange end
		f.ApplyRangePresentation = function() end
		f.HasSwingTimer = function(self) return self.swinging == true end
		f.ResetSwingTimer = function(self) self.swinging = true end
		f.ClearSwingTimer = function(self) self.swinging = nil end
		f.SetIsInEditMode = function(self, on) self.isInEditMode = on end
		return f
	end
	local main, off, ranged = Bar("SwingTimerMainHandFrame"), Bar("SwingTimerOffHandFrame"), Bar("SwingTimerRangedFrame")
	_G.SwingTimerMainHandFrame, _G.SwingTimerOffHandFrame, _G.SwingTimerRangedFrame = main, off, ranged
	local cfg = ns.db.swingTimers
	cfg.enabled = false
	ST.SkinAll()
	check("swing timers: off leaves Blizzard's look", main.SUISwingSkin == nil)
	cfg.enabled = true
	ST.SkinAll()
	check("all three skinned", main.SUISwingSkin and off.SUISwingSkin and ranged.SUISwingSkin)
	check("melee color", main.colors.bar[1] == cfg.mainColor[1] and main.colors.bar[3] == cfg.mainColor[3])
	check("off-hand color", off.colors.bar[1] == cfg.offColor[1])
	check("ranged color", ranged.colors.bar[1] == cfg.rangedColor[1])
	check("flat border", main.SUIBorder ~= nil)
	check("label shadow gone", main.StatusBar.TypeLabelShadow:GetAlpha() == 0)
	-- Blizzard's own range update can't undo the look: text color follows, red stays red
	cfg.textStyle.color = { 0.1, 0.2, 0.3 }
	main.colors.time = nil
	main:ApplyRangePresentation()
	check("text color survives Blizzard's update", main.colors.time and main.colors.time[1] == 0.1, main.colors.time)
	main.outOfRange = true
	main.colors.time = nil
	main:ApplyRangePresentation()
	check("out of range keeps Blizzard's red", main.colors.time == nil)
	main.outOfRange = false
	cfg.textStyle.color = { 1, 1, 1 }
	cfg.showTime = false
	ST:Refresh()
	check("time can be hidden", main.StatusBar.TimeLabel:GetAlpha() == 0)
	cfg.showTime = true
	ST:Refresh()
	check("time comes back", main.StatusBar.TimeLabel:GetAlpha() == 1)
	-- Blizzard's addon loading after ours is picked up
	local late = Bar("SwingTimerRangedFrame")
	_G.SwingTimerRangedFrame = late
	ST.SkinAll()
	check("late bar skinned", late.SUISwingSkin == true)
	_G.SwingTimerRangedFrame = ranged

	-- only show while attacking
	check("idle hiding off by default", cfg.hideIdle == false and main:GetAlpha() == 1)
	cfg.hideIdle = true
	ST:Refresh()
	check("idle: all hidden", main:GetAlpha() == 0 and off:GetAlpha() == 0 and ranged:GetAlpha() == 0)
	MOCK.Fire("PLAYER_ENTER_COMBAT")
	check("auto attack shows melee bars only", main:GetAlpha() == 1 and off:GetAlpha() == 1 and ranged:GetAlpha() == 0)
	MOCK.Fire("PLAYER_LEAVE_COMBAT")
	check("auto attack off hides them", main:GetAlpha() == 0)
	MOCK.Fire("START_AUTOREPEAT_SPELL")
	check("auto shot shows the ranged bar only", ranged:GetAlpha() == 1 and main:GetAlpha() == 0)
	MOCK.Fire("STOP_AUTOREPEAT_SPELL")
	main:ResetSwingTimer()
	check("a swing under way stays visible", main:GetAlpha() == 1)
	main:ClearSwingTimer()
	check("hides when that swing ends", main:GetAlpha() == 0)
	ranged:SetIsInEditMode(true)
	check("Edit Mode always sees it", ranged:GetAlpha() == 1)
	ranged:SetIsInEditMode(false)
	check("back to hidden after Edit Mode", ranged:GetAlpha() == 0)
	-- with the flat look off, the option still works
	cfg.enabled = false
	ST.SkinAll()
	check("idle hiding without the flat look", main:GetAlpha() == 0)
	cfg.enabled, cfg.hideIdle = true, false
	ST:Refresh()
	check("option off shows them again", main:GetAlpha() == 1 and ranged:GetAlpha() == 1)
	_G.SwingTimerMainHandFrame, _G.SwingTimerOffHandFrame, _G.SwingTimerRangedFrame = nil, nil, nil
end

-- healing numbers: the game's switch, on whichever name this client has
do
	local DT, c = ns.DamageText, ns.db.damageText
	local old, set = C_CVar, {}
	local have = { floatingCombatTextCombatHealing_v2 = "0" }
	C_CVar = { GetCVar = function(n) return have[n] end, SetCVar = function(n, v) set[n] = v end, GetCVarDefault = function() return "1" end }
	check("healing numbers on by default", c.healing == true)
	DT.Apply()
	check("healing switched on", set.floatingCombatTextCombatHealing_v2 == "1")
	check("a name this client lacks is left alone", set.floatingCombatTextCombatHealing == nil)
	c.healing = false
	DT.Apply()
	check("healing switched off", set.floatingCombatTextCombatHealing_v2 == "0")
	c.healing = true
	c.enabled = false
	DT.Apply()
	check("healing doesn't depend on the size and position switch", set.floatingCombatTextCombatHealing_v2 == "1")
	c.enabled = true
	C_CVar = old
end

-- ally buffs: all of them, or only yours
do
	local BG, c = ns.BGEnemies, ns.db.bgAllies
	local A, E = BG.allies, BG.enemies
	check("ally buffs off by default", c.buffs == false and c.buffsMine == false)
	check("all buffs filter", BG.BuffFilter(c) == "HELPFUL")
	c.buffsMine = true
	check("my buffs filter", BG.BuffFilter(c) == "HELPFUL|PLAYER")
	c.buffsMine = false
	check("enemies get no buffs", E.rows[1].Buffs == nil and ns.db.bgEnemies.buffs == nil)
	local row = A.rows[1]
	check("ally rows have buffs", row.Buffs ~= nil)
	local unit, enabled, filter, max
	local b = row.Buffs
	b.SetUnit = function(_, u) unit = u end
	b.GetUnit = function() return unit end
	b.SetEnabled = function(_, on) enabled = on end
	b.SetAuraGroupFilterString = function(_, _, f) filter = f end
	b.SetAuraGroupMaxFrameCount = function(_, _, n) max = n end
	b.UpdateAllAuras = function() end

	row.unit = "raid3"
	A:UpdateBuffs(row)
	check("off: nothing watched", enabled == false)
	c.buffs = true
	A:LayoutRow(row)
	check("on: watches the ally", enabled == true and unit == "raid3", unit)
	check("on: icons shown", b:IsShown())
	check("buff count applied", max == c.buffMax, max)
	c.buffsMine = true
	A:LayoutRow(row)
	check("only mine changes the filter live", filter == "HELPFUL|PLAYER", filter)
	row.preview = true
	A:UpdateBuffs(row)
	check("test mode: your own buffs", unit == "player")
	row.preview = nil
	row.unit = nil
	A:UpdateBuffs(row)
	check("unbound row watches nobody", enabled == false)
	c.buffs, c.buffsMine = false, false
	A:LayoutRow(row)
	check("off again: icons hidden", not b:IsShown())
end
flushErrors("ally buffs")

-- /rl reloads
do
	local old, reloaded = ReloadUI, false
	ReloadUI = function() reloaded = true end
	check("/rl registered", SLASH_STINKIERELOAD1 == "/rl")
	SlashCmdList.STINKIERELOAD("")
	check("/rl reloads", reloaded)
	ReloadUI = old
end

-- window skins: side tabs keep their icon, text tabs lose all their art
do
	local SK = ns.Skins
	local function Tab(name, parent, side)
		local t = MOCK.NewObj("Button", name, parent)
		_G[name] = t
		t.Art = MOCK.NewObj("Texture", nil, t)
		local regions = { t.Art }
		if side then
			t.Icon = MOCK.NewObj("Texture", nil, t)
			t.SelectedTexture = MOCK.NewObj("Texture", nil, t)
			regions[2], regions[3] = t.Icon, t.SelectedTexture
			t.SetChecked = function() end
		end
		t.GetRegions = function() return unpack(regions) end
		return t
	end
	local window = MOCK.NewObj("Frame", "SkinTestWindow", UIParent)
	_G.SkinTestWindow = window
	local side = Tab("SkinTestTab1", window, true)
	local text = Tab("SkinTestTab2", window, false)
	side.Icon:SetAlpha(1)
	SK.SkinWindow({ key = "collections", frame = "SkinTestWindow", tabs = "SkinTestTab%d" })
	check("side tab keeps its icon", side.Icon:GetAlpha() == 1, side.Icon:GetAlpha())
	check("side tab art is hidden", side.Art:GetAlpha() == 0 and side.SelectedTexture:GetAlpha() == 0)
	check("text tab art is hidden", text.Art:GetAlpha() == 0)
	local painted
	side.SUIFlat.tex.SetColorTexture = function(_, _, _, _, a) painted = a end
	side:SetChecked(true)
	check("selected side tab fills solid", painted == 1, painted)
	side:SetChecked(false)
	check("unselected side tab goes back", painted == ns.db.character.tabAlpha, painted)
	_G.SkinTestWindow, _G.SkinTestTab1, _G.SkinTestTab2 = nil, nil, nil
end
flushErrors("side tabs")

-- healing you receive: the game's scrolling text setting
do
	local DT = ns.DamageText
	DT.SetScrollingText(true)
	check("scrolling text on", DT.ScrollingText() == true and MOCK.cvars.enableFloatingCombatText == "1")
	DT.SetScrollingText(false)
	check("scrolling text off", DT.ScrollingText() == false and MOCK.cvars.enableFloatingCombatText == "0")
end

-- party targets sit on their own party frame
do
	local PT, c = ns.PartyTargets, ns.db.partyTargets
	local oldParty = ns.Party.frames
	local mine, first = { unit = "player" }, { unit = "party1" }
	ns.Party.frames = { first, mine }
	check("my target goes on my frame", PT.PartyFrameFor({ unit = "target" }) == mine)
	check("a party target goes on that member", PT.PartyFrameFor({ unit = "party1target" }) == first)
	check("no frame for that member", PT.PartyFrameFor({ unit = "party3target" }) == nil)
	check("attaching is off by default", c.attachAbove == false)

	local f = PT.frames[1]
	local placed
	local oldSet = f.SetPoint
	f.SetPoint = function(_, p, rel, _, _, y) placed = { p, rel, y } end
	local oldEnabled = c.enabled
	c.attachAbove, c.attachGap = true, 5
	ns.Party.frames = { { unit = f.unit:match("^(party%d)target$") } }
	local partyFrame = ns.Party.frames[1]
	PT:Refresh()
	check("row sits on its party frame", placed[1] == "BOTTOMLEFT" and placed[2] == partyFrame and placed[3] == 5)
	check("attached rows have no mover", PT.holder.SUIActive == false)
	c.attachAbove, c.attachGap = false, 3
	PT:Refresh()
	check("back to its own position", placed[2] == PT.holder, placed[2])
	check("mover back", PT.holder.SUIActive == true)
	f.SetPoint = oldSet
	c.enabled = oldEnabled
	ns.Party.frames = oldParty
end

-- the bar behind the zone name, on either client
do
	local MM, c = ns.MinimapSkin, ns.db.minimap
	local old, oldHide = MinimapCluster, c.hideHeaderArt
	local function Tex() return MOCK.NewObj("Texture", nil, UIParent) end
	-- retail: its own texture
	MinimapCluster = { BorderTop = Tex() }
	c.hideHeaderArt = true
	MM.ApplyHeaderArt()
	check("retail bar hidden", MinimapCluster.BorderTop:GetAlpha() == 0)
	c.hideHeaderArt = false
	MM.ApplyHeaderArt()
	check("retail bar back", MinimapCluster.BorderTop:GetAlpha() == 1)
	-- WoW Forever: the zone button's art, relit by Blizzard on hover
	local zone = { StateTexture = Tex(), AddTexture = Tex() }
	zone.OnButtonStateChanged = function(self) self.AddTexture:SetAlpha(0.1) end
	MinimapCluster = { ZoneTextButton = zone }
	c.hideHeaderArt = true
	MM.ApplyHeaderArt()
	check("Forever bar hidden", zone.StateTexture:GetAlpha() == 0)
	zone:OnButtonStateChanged()
	check("Forever bar stays hidden on hover", zone.AddTexture:GetAlpha() == 0)
	c.hideHeaderArt = false
	MM.ApplyHeaderArt()
	check("Forever bar back", zone.StateTexture:GetAlpha() == 1)
	zone:OnButtonStateChanged()
	check("Forever hover works again", zone.AddTexture:GetAlpha() == 0.1)
	MinimapCluster, c.hideHeaderArt = old, oldHide
end
check("Omnium Folio follows the client", ns.HAS_FOLIO == not ns.IS_FOREVER)

-- whispers: where they show, and that they aren't lost
do
	local CH, c = ns.Chat, ns.db.chat
	check("whispers default to both", ns.defaults.chat.whisperDisplay == "both" and c.whisperDisplay == "both")
	local oldGet, mode = GetCVar, "inline"
	GetCVar = function(n) if n == "whisperMode" then return mode end return oldGet(n) end
	local oldSet = SetCVar
	SetCVar = function(n, v) if n == "whisperMode" then mode = v else oldSet(n, v) end end
	CH.ApplyCVars()
	check("both is the game's both mode", mode == "popout_and_inline", mode)
	c.whisperDisplay = "tab"
	CH.ApplyCVars()
	check("own tab only", mode == "popout", mode)
	c.whisperDisplay = "main"
	CH.ApplyCVars()
	check("main tab only", mode == "inline", mode)
	c.whisperDisplay = "both"
	CH.ApplyCVars()
	check("both is left alone once set", mode == "popout_and_inline", mode)

	-- temporary whisper tabs: nothing else holds tab-only whispers, so history goes to the main window
	local tempTab = { isTemporary = true, chatType = "WHISPER", GetID = function() return 12 end }
	local bnTab = { isTemporary = true, chatType = "BN_WHISPER", GetID = function() return 13 end }
	local other = { isTemporary = true, chatType = "GUILD", GetID = function() return 14 end }
	local normal = { GetID = function() return 4 end }
	check("normal window keeps its own history", CH.HistoryID(normal) == 4)
	check("both: main already has it, so no second copy", CH.HistoryID(tempTab) == nil)
	mode = "popout"
	check("tab only: character whisper kept", CH.HistoryID(tempTab) == 1, CH.HistoryID(tempTab))
	check("tab only: Battle.net whisper kept", CH.HistoryID(bnTab) == 1, CH.HistoryID(bnTab))
	check("other temporary windows aren't", CH.HistoryID(other) == nil)
	GetCVar, SetCVar = oldGet, oldSet

	-- the whisper that opens a new tab arrives right away, so the hook can't wait a frame
	local name = "ChatFrame27"
	local f = MOCK.NewObj("Frame", name, UIParent)
	f.AddMessage = function() end
	_G[name] = f
	local before = f.AddMessage
	local oldFrames, oldTextures = CHAT_FRAMES, CHAT_FRAME_TEXTURES
	CHAT_FRAMES, CHAT_FRAME_TEXTURES = { name }, {}
	CH.OnTemporaryWindow()
	check("new whisper tab is hooked at once", f.AddMessage ~= before)
	MOCK.Advance(0.1)
	CHAT_FRAMES, CHAT_FRAME_TEXTURES = oldFrames, oldTextures
	_G[name] = nil

	-- older profiles
	local kept = { version = 13, units = {}, chat = { whisperTabs = true, whisperDisplay = "both" } }
	ns.Migrate(kept)
	check("tab users move to both", kept.chat.whisperDisplay == "both" and kept.chat.whisperTabs == nil)
	local off = { version = 13, units = {}, chat = { whisperTabs = false, whisperDisplay = "both" } }
	ns.Migrate(off)
	check("main tab users stay there", off.chat.whisperDisplay == "main" and off.chat.whisperTabs == nil)
end
flushErrors("whispers")

-- hide error messages: only the red event, and only what we changed
do
	local M, A = ns.Misc, ns.db.misc.auto
	local oldFrame, log = UIErrorsFrame, {}
	UIErrorsFrame = {
		UnregisterEvent = function(_, e) log[#log + 1] = "off " .. e end,
		RegisterEvent = function(_, e) log[#log + 1] = "on " .. e end,
	}
	check("errors shown by default", A.hideErrors == false)
	M.ApplyHideErrors()
	check("off does nothing, so another addon's choice stands", #log == 0)
	A.hideErrors = true
	M.ApplyHideErrors()
	M.ApplyHideErrors()
	check("hides red errors once", #log == 1 and log[1] == "off UI_ERROR_MESSAGE", log[1])
	A.hideErrors = false
	M:Refresh()
	check("turning it off brings them back", #log == 2 and log[2] == "on UI_ERROR_MESSAGE", log[2])
	UIErrorsFrame = oldFrame
end

-- automation: nothing happens until it's switched on, and decisions stay with the player
do
	local M, A = ns.Misc, ns.db.misc.auto
	local calls = {}
	local function log(name) return function(...) calls[#calls + 1] = name; calls[name] = { ... } end end
	local saved = {}
	local function stub(name, fn) saved[name] = _G[name]; _G[name] = fn end
	local function reset() for k in pairs(calls) do calls[k] = nil end end
	for _, k in ipairs({ "questAccept", "questTurnIn", "repair", "repairGuild", "sellJunk", "releasePvP" }) do
		check("off by default: " .. k, A[k] == false)
	end
	A.announce = false
	stub("IsShiftKeyDown", function() return false end)
	stub("AcceptQuest", log("AcceptQuest"))
	stub("AcknowledgeAutoAcceptQuest", log("Ack"))
	stub("QuestFlagsPVP", function() return false end)
	stub("QuestGetAutoAccept", function() return false end)
	stub("CompleteQuest", log("CompleteQuest"))
	stub("IsQuestCompletable", function() return true end)
	stub("GetQuestMoneyToGet", function() return 0 end)
	stub("GetNumQuestCurrencies", function() return 0 end)
	stub("GetNumQuestChoices", function() return 1 end)
	stub("GetQuestReward", log("GetQuestReward"))
	stub("C_GossipInfo", {
		GetActiveQuests = function() return { { questID = 1, isComplete = false }, { questID = 2, isComplete = true } } end,
		GetAvailableQuests = function() return { { questID = 3, isIgnored = true }, { questID = 4 } } end,
		SelectActiveQuest = log("SelectActive"), SelectAvailableQuest = log("SelectAvailable"),
	})

	M.OnQuestDetail(); M.OnQuestProgress(); M.OnQuestComplete(); M.OnGossip()
	check("quests: off does nothing", #calls == 0)
	A.questAccept, A.questTurnIn = true, true
	M.OnGossip()
	check("gossip: finished quest first", calls.SelectActive and calls.SelectActive[1] == 2 and not calls.SelectAvailable)
	reset()
	A.questTurnIn = false
	M.OnGossip()
	check("gossip: skips ignored quests", calls.SelectAvailable and calls.SelectAvailable[1] == 4)
	A.questTurnIn = true
	reset()
	M.OnQuestDetail()
	check("accepts", calls.AcceptQuest ~= nil)
	reset()
	QuestFlagsPVP = function() return true end
	M.OnQuestDetail()
	check("PvP-flagging quest left alone", #calls == 0)
	QuestFlagsPVP = function() return false end
	QuestGetAutoAccept = function() return true end
	M.OnQuestDetail()
	check("auto-accept quest acknowledged", calls.Ack ~= nil and calls.AcceptQuest == nil)
	reset()
	IsShiftKeyDown = function() return true end
	M.OnQuestDetail(); M.OnQuestProgress(); M.OnQuestComplete(); M.OnGossip()
	check("Shift pauses all of it", #calls == 0)
	IsShiftKeyDown = function() return false end
	M.OnQuestProgress()
	check("turns in", calls.CompleteQuest ~= nil)
	reset()
	GetNumQuestCurrencies = function() return 1 end
	M.OnQuestProgress()
	check("quest that costs currency left alone", #calls == 0)
	GetNumQuestCurrencies = function() return 0 end
	GetQuestMoneyToGet = function() return 100 end
	M.OnQuestProgress(); M.OnQuestComplete()
	check("quest that costs gold left alone", #calls == 0)
	GetQuestMoneyToGet = function() return 0 end
	M.OnQuestComplete()
	check("single reward taken", calls.GetQuestReward and calls.GetQuestReward[1] == 1)
	reset()
	GetNumQuestChoices = function() return 0 end
	M.OnQuestComplete()
	check("no reward choice", calls.GetQuestReward and calls.GetQuestReward[1] == 0)
	reset()
	GetNumQuestChoices = function() return 3 end
	M.OnQuestComplete()
	check("a choice of rewards waits for you", #calls == 0)

	-- vendors
	stub("CanMerchantRepair", function() return true end)
	stub("GetRepairAllCost", function() return 5000, true end)
	stub("RepairAllItems", log("Repair"))
	stub("GetMoney", function() return 10000 end)
	stub("CanGuildBankRepair", function() return false end)
	stub("GetGuildBankWithdrawMoney", function() return 100000 end)
	stub("GetGuildBankMoney", function() return 100000 end)
	stub("C_MerchantFrame", { IsSellAllJunkEnabled = function() return true end, GetNumJunkItems = function() return 2 end, SellAllJunkItems = log("SellJunk") })
	reset()
	M.OnMerchant()
	check("vendor: off does nothing", #calls == 0)
	A.repair, A.sellJunk = true, true
	M.OnMerchant()
	check("junk goes before repairs", calls[1] == "SellJunk" and calls[2] == "Repair")
	check("repairs with your gold", calls.Repair and calls.Repair[1] == nil)
	reset()
	A.repairGuild = true
	CanGuildBankRepair = function() return true end
	M.Repair()
	check("repairs with guild funds", calls.Repair and calls.Repair[1] == true)
	reset()
	GetGuildBankWithdrawMoney = function() return 100 end
	M.Repair()
	check("guild limit too low: your gold", calls.Repair and calls.Repair[1] == nil)
	reset()
	GetGuildBankWithdrawMoney = function() return -1 end
	M.Repair()
	check("no guild limit", calls.Repair and calls.Repair[1] == true)
	reset()
	CanGuildBankRepair = function() return false end
	GetMoney = function() return 1 end
	M.Repair()
	check("can't afford it: no repair", #calls == 0)
	GetRepairAllCost = function() return 0, false end
	GetMoney = function() return 10000 end
	M.Repair()
	check("nothing to repair", #calls == 0)
	CanMerchantRepair = function() return false end
	GetRepairAllCost = function() return 5000, true end
	M.Repair()
	check("vendor can't repair", #calls == 0)
	C_MerchantFrame = { IsSellAllJunkEnabled = function() return true end, GetNumJunkItems = function() return 0 end, SellAllJunkItems = log("SellJunk") }
	M.SellJunk()
	check("no junk: nothing sold", #calls == 0)
	-- clients without Blizzard's sell-all button
	C_MerchantFrame = {}
	stub("C_Container", {
		GetContainerNumSlots = function(bag) return bag == 0 and 3 or 0 end,
		GetContainerItemInfo = function(_, slot)
			if slot == 1 then return { quality = 0 } end
			if slot == 2 then return { quality = 1 } end
			return { quality = 0, hasNoValue = true }
		end,
		UseContainerItem = log("Use"),
	})
	M.SellJunk()
	check("fallback sells only valuable grays", #calls == 1 and calls.Use[2] == 1)
	reset()

	-- release
	stub("RepopMe", log("Repop"))
	stub("IsInInstance", function() return true, "pvp" end)
	stub("C_DeathInfo", { GetSelfResurrectOptions = function() return {} end })
	M.OnDead()
	check("release: off does nothing", #calls == 0)
	A.releasePvP = true
	M.OnDead()
	check("releases in a battleground", calls.Repop ~= nil)
	reset()
	IsInInstance = function() return true, "arena" end
	M.OnDead()
	check("no release in arena", #calls == 0)
	IsInInstance = function() return false, "none" end
	M.OnDead()
	check("no release in the world", #calls == 0)
	IsInInstance = function() return true, "pvp" end
	C_DeathInfo = { GetSelfResurrectOptions = function() return { { name = "Soulstone" } } end }
	M.OnDead()
	check("self-resurrect: your choice", #calls == 0)

	for k, v in pairs(saved) do _G[k] = v end
	for _, k in ipairs({ "questAccept", "questTurnIn", "repair", "repairGuild", "sellJunk", "releasePvP" }) do A[k] = false end
	A.announce = true
end

-- Character Sheet: window opacity reaches what's on screen
do
	local CS = ns.CharacterSheet
	local panel = MOCK.NewObj("Frame", "OpacityPanel", UIParent)
	local fill = {}
	panel.SUIFlat = { tex = { SetColorTexture = function(_, _, _, _, a) fill.a = a end } }
	local model = MOCK.NewObj("Frame", "OpacityModel", panel)
	local ch = ns.db.character
	local oldAlpha = ch.frameAlpha
	ch.frameAlpha = 0.4
	local tex = CS.WideBackground(model, panel)
	check("wide background built", tex ~= nil and tex ~= false, tex)
	check("window opacity reaches the picture", panel.SUIWide:GetAlpha() == 0.4, panel.SUIWide:GetAlpha())
	check("no second layer under the picture", fill.a == 0, fill.a)
	panel.SUIWide:Hide()
	CS.PaintWindowFill(panel)
	check("other tabs use the fill", fill.a == 0.4, fill.a)
	ch.frameAlpha = oldAlpha
end
flushErrors("new options")

-- options search finds pages
ns:ToggleOptions()
ns.Options.search:SetText("buff")
local sh = ns.Options.search:GetScript("OnTextChanged"); if sh then sh(ns.Options.search) end
check("options search active", ns.Options.searchActive == true and ns.Options.searchIndex ~= nil)
ns.Options.search:SetText("")
if sh then sh(ns.Options.search) end
check("options search off", ns.Options.searchActive == false)
ns:ToggleOptions()
flushErrors("0.33")

-- 0.34: target found by its nameplate frame (secret-proof)
local plateA, plateB = MOCK.NewObj("Frame", nil, UIParent), MOCK.NewObj("Frame", nil, UIParent)
local oldGet = C_NamePlate.GetNamePlateForUnit
rawset(C_NamePlate, "GetNamePlateForUnit", function(u) if u == "target" then return plateA end end)
check("target plate by frame", ns.Nameplates.IsTargetPlate({ nameplate = plateA, unit = "nameplate1" }) == true)
check("other plate not target", ns.Nameplates.IsTargetPlate({ nameplate = plateB, unit = "nameplate2" }) == false)
-- target marker on a real plate: built by plate setup, follows the marker event
do
	local plate = MOCK.NewObj("Frame", nil, UIParent)
	rawset(C_NamePlate, "GetNamePlateForUnit", function(u) if u == "nameplate9" then return plate end end)
	local oldPlates = C_NamePlate.GetNamePlates
	rawset(C_NamePlate, "GetNamePlates", function() return { plate } end)
	local oldIndex, oldSet = GetRaidTargetIndex, SetRaidTargetIconTexture
	local index, set = 4, nil
	GetRaidTargetIndex = function() return index end
	SetRaidTargetIconTexture = function(_, i) set = i end
	ns.Nameplates.SetupPlate("nameplate9")
	local f = plate.SUIFrame
	check("plate built", f ~= nil and f.unit == "nameplate9")
	check("plate marker shown on setup", f.Marker:IsShown() and set == 4, set)
	index = nil
	ns.Nameplates.driver:GetScript("OnEvent")(ns.Nameplates.driver, "RAID_TARGET_UPDATE")
	check("plate marker follows the event", not f.Marker:IsShown())
	index = 2
	ns.db.nameplates.marker = false
	ns.Nameplates.UpdateMarker(f)
	check("plate marker off", not f.Marker:IsShown())
	ns.db.nameplates.marker = true
	f.nameFormat = nil
	ns.db.nameplates.nameFormat = "last"
	local oldUnitName = UnitName
	UnitName = function() return "Stormwind Guard" end
	ns.Nameplates.SetupPlate("nameplate9")
	check("plate name follows the option", f.Name:GetText() == "Guard", f.Name:GetText())
	ns.db.nameplates.nameFormat = "full"
	UnitName = oldUnitName
	GetRaidTargetIndex, SetRaidTargetIconTexture = oldIndex, oldSet
	rawset(C_NamePlate, "GetNamePlates", oldPlates)
end
flushErrors("plate marker")
rawset(C_NamePlate, "GetNamePlateForUnit", oldGet)
check("important aura marker default", ns.db.nameplates.important.auraMarker == true and ns.db.nameplates.important.auraIDs[1] == "8178")
flushErrors("0.34")

-- 0.34.1: each flag sits under the score of the team carrying it
local FL = ns.FlagCap.Logic
local sl = FL.Slots({ { faction = "Alliance", carrier = { name = "Wind" } } }, "SIDE", false)
check("Horde carrier of the Alliance flag goes right, left empty", sl[1] == nil and sl[2] and sl[2].carrier.name == "Wind")
sl = FL.Slots({ { faction = "Alliance" }, { faction = "Horde" } }, "SIDE", false)
check("both flags under their carriers' scores", sl[1].faction == "Horde" and sl[2].faction == "Alliance")
sl = FL.Slots({ { faction = "Alliance" } }, "SIDE", true)
check("swapped sides", sl[1].faction == "Alliance")
sl = FL.Slots({ { faction = "Alliance" } }, "STACK", false)
check("stack fills from top", sl[1].faction == "Alliance")
check("unknown art keeps the nearest team", FL.NearestFaction({ Alliance = { x = 0.5, y = 0.2 }, Horde = { lastX = 0.5, lastY = 0.8 } }, 0.52, 0.75) == "Horde")
check("taken team skipped", FL.NearestFaction({ Alliance = { x = 0.5, y = 0.2 }, Horde = { x = 0.5, y = 0.8 } }, 0.5, 0.79, { Horde = true }) == "Alliance")

-- 0.36: tooltip
local TT = ns.Tooltip
check("tooltip defaults", ns.db.tooltip.anchor == "mouse" and ns.db.tooltip.offsetX == 128 and ns.db.tooltip.offsetY == 25)
ns.db.tooltip.combat = "units"
check("tooltip shown out of combat", TT.ShouldHide(true) == false)
local oldIC = InCombatLockdown
InCombatLockdown = function() return true end
check("unit tooltip hidden in combat", TT.ShouldHide(true) == true and TT.ShouldHide(false) == false)
IsShiftKeyDown = function() return true end
check("shift shows it", TT.ShouldHide(true) == false)
IsShiftKeyDown = function() return false end
InCombatLockdown = oldIC
ns.db.tooltip.combat = "show"
local oldUIU, oldUE, oldUN = UnitIsUnit, UnitExists, UnitName
UnitExists = function() return true end
UnitIsUnit = function(a, b) return b == "player" end
check("target YOU", TT.TargetText("mouseover"):find("YOU"))
UnitIsUnit = function() return false end
UnitName = function() return "Pinkie" end
check("target name", TT.TargetText("mouseover"):find("Pinkie"))
UnitIsUnit = function() return { __secret = true } end
UnitName = function() return { __secret = true } end
check("hidden target left out", TT.TargetText("mouseover") == nil)
UnitIsUnit, UnitExists, UnitName = oldUIU, oldUE, oldUN
flushErrors("tooltip")

-- 0.37: collapse arrow, centered header
CharacterFrame.InsetRight = CharacterFrame.InsetRight or MOCK.NewObj("Frame", nil, CharacterFrame)
CharacterFrame.Inset = CharacterFrame.Inset or MOCK.NewObj("Frame", nil, CharacterFrame)
CharacterFrame.TitleContainer = MOCK.NewObj("Frame", nil, CharacterFrame)
CharacterFrame.TitleContainer.TitleText = MOCK.NewObj("FontString", nil, CharacterFrame.TitleContainer)
ns.db.character.collapsed = true
ns.CharacterSheet.ApplyLayout()
MOCK.Advance(0.1)
check("collapse parks the stat side", CharacterFrame.InsetRight.SUIParked ~= nil)
check("collapse arrow made", ns.CharacterSheet.collapseButton and ns.CharacterSheet.collapseButton.text._text == ">")
ns.db.character.collapsed = false
ns.CharacterSheet.ApplyLayout()
check("expand puts it back", CharacterFrame.InsetRight.SUIParked == nil and ns.CharacterSheet.collapseButton.text._text == "<")
ns.CharacterSheet.CenterHeader()
flushErrors("collapse")

-- 0.37 (round 3): history search, scroll bar, stacking
check("plates don't stack by default", ns.defaults.nameplates.stacking.enemies == false and ns.defaults.nameplates.stacking.friendly == false)
local mig13 = { version = 12, units = {}, nameplates = { stacking = { enemies = true, friendly = true } } }
ns.Migrate(mig13)
check("migrate stacking off", mig13.nameplates.stacking.enemies == false and mig13.nameplates.stacking.friendly == false)
H.Toggle("matches")
local mw = StinkieUI_MatchHistory
local function SearchFor(t) mw.search:SetText(t); mw.search:GetScript("OnTextChanged")(mw.search, true); return tonumber(mw.count._text:match("^(%d+)")) end
local everything = SearchFor("")
check("search nobody", SearchFor("zzzz-nobody") == 0)
local frost = SearchFor("frost")
check("search a spec name", frost > 0 and frost <= everything, frost)
local two = SearchFor("pinkie nagrand")
check("search two words narrows", two <= SearchFor("pinkie"), two)
SearchFor("")
local importBtn = false
for _, o in ipairs(MOCK.frames) do if o._text == "Import Rated Tracker" then importBtn = true end end
check("import button gone from the window", not importBtn)
check("scroll bar is a button", mw.matches.scrollBar and mw.matches.scrollBar:GetScript("OnMouseDown") ~= nil)
flushErrors("history search")

-- 0.38: the window loads recent matches unless asked for all
ns.db.matchHistory.loadMonths = 1
Dh.summaries = nil
local Arch = Dh.Archive()
Arch.records[#Arch.records + 1] = Arch.records[1]:gsub("^(v%d+;)%d+", "%1" .. (time() - 400 * 86400))
Dh.BuildSummaries()
check("old match not loaded", (Dh.skipped or 0) >= 1, Dh.skipped)
Dh.loadAll = true
Dh.BuildSummaries()
check("load all", Dh.skipped == 0)
Dh.loadAll = nil
table.remove(Arch.records)
ns.db.matchHistory.loadMonths = 0
Dh.BuildSummaries()
flushErrors("recent")

-- 0.38: window skins, durability, party in raid, profiler
local fr = MOCK.NewObj("Frame", "FriendsFrame", UIParent)
fr.NineSlice = MOCK.NewObj("Frame", nil, fr)
fr.PortraitContainer = MOCK.NewObj("Frame", nil, fr)
local t1 = MOCK.NewObj("Button", "FriendsFrameTab1", fr)
t1.Left = MOCK.NewObj("Texture", nil, t1)
check("skin friends", ns.Skins.SkinWindow(ns.Skins.WINDOWS[1]) and fr.SUISkin ~= nil and fr.NineSlice._alpha == 0 and FriendsFrameTab1.SUIFlat ~= nil)
local r, g, b = ns.CharacterSheet.DurabilityColor(1)
local r2, g2 = ns.CharacterSheet.DurabilityColor(0)
check("durability colors", g > r and r2 == 1 and g2 == 0, string.format("%.2f %.2f / %.2f %.2f", r, g, r2, g2))
GetInventoryItemDurability = function(slot) return 30, 100 end
ns.CharacterSheet.UpdateButton(CharacterHeadSlot, "player", 1, "RIGHT")
check("durability line shown", CharacterHeadSlot.SUISheet.dura:IsShown())
check("party hidden in raids by default", ns.db.party.hideInRaid == true)
ns.StartProfile(1)
MOCK.Fire("PLAYER_TARGET_CHANGED")
MOCK.Advance(1.2)
check("profiler stops itself", ns.profile.on == false)
check("defaults: ring combat only, GCD History off", ns.defaults.cursor.ringCombatOnly == true and ns.defaults.misc.gcd.enabled == false)
flushErrors("0.38")

-- 0.38: title bars and the Achievements header
local ach = MOCK.NewObj("Frame", "AchievementFrame", UIParent)
ach.Header = MOCK.NewObj("Frame", nil, ach)
for _, k in ipairs({ "Left", "Right", "PointBorder", "Shield" }) do ach.Header[k] = MOCK.NewObj("Texture", nil, ach.Header) end
ach.Header.Title = MOCK.NewObj("FontString", nil, ach.Header)
ach.Header.Points = MOCK.NewObj("FontString", nil, ach.Header)
local achDef
for _, d in ipairs(ns.Skins.WINDOWS) do if d.frame == "AchievementFrame" then achDef = d end end
check("achievements skinned", ns.Skins.SkinWindow(achDef) and ach.Header.Left._alpha == 0 and ach.Header.Shield._alpha == 1 and ach.SUISkin.band ~= nil)
fr.TitleContainer = MOCK.NewObj("Frame", nil, fr)
fr.TitleContainer.TitleText = MOCK.NewObj("FontString", nil, fr.TitleContainer)
ns.Skins.SkinWindow(ns.Skins.WINDOWS[1])
check("title band on friends", fr.SUISkin.band ~= nil)
flushErrors("titles")

-- achievements title: Statistics tab
ach.Header.Title:SetText("Warband Achievement Points")
PanelTemplates_GetSelectedTab = function() return 3 end
ns.Skins.AchievementTitleForTab()
check("statistics title", ach.Header.Title._text == (STATISTICS or "Statistics") and not ach.Header.Points:IsShown(), ach.Header.Title._text)
PanelTemplates_GetSelectedTab = function() return 1 end
ns.Skins.AchievementTitleForTab()
check("back to the achievements title", ach.Header.Title._text == "Warband Achievement Points" and ach.Header.Points:IsShown())
flushErrors("ach tabs")

-- damage numbers
local setTo = {}
local oldCV = C_CVar
C_CVar = { GetCVar = function(n) return n == "WorldTextNonRandomZ" and "1" or nil end, SetCVar = function(n, v) setTo[n] = v end, GetCVarDefault = function() return "1" end }
check("height setting available", ns.DamageText.Available("height") and not ns.DamageText.Available("size"))
ns.db.damageText.height = 3
ns.DamageText.Apply()
check("height applied", setTo.WorldTextNonRandomZ == "3", setTo.WorldTextNonRandomZ)
ns.db.damageText.height = 0
ns.DamageText.Apply()
check("height back to default", setTo.WorldTextNonRandomZ == "1")
C_CVar = oldCV
flushErrors("damage numbers")

-- final battleground score
do
	local R = ns.MatchRecorder
	MOCK.widgets = { { widgetID = 7, widgetType = 3, orderIndex = 1 } }
	MOCK.widgetInfo = { [7] = { leftBarValue = 1500, rightBarValue = 1230, leftBarMax = 1500, rightBarMax = 1500 } }
	local a, h = R.ReadScore()
	check("score: resource bars", a == 1500 and h == 1230)
	local oldIT = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo
	Enum.UIWidgetVisualizationType.IconAndText = 0
	MOCK.widgets = { { widgetID = 2, widgetType = 0, orderIndex = 2 }, { widgetID = 1, widgetType = 0, orderIndex = 1 } }
	rawset(C_UIWidgetManager, "GetIconAndTextWidgetVisualizationInfo", function(id)
		return ({ [1] = { shownState = 1, text = "2/3" }, [2] = { shownState = 1, text = "1/3" } })[id]
	end)
	a, h = R.ReadScore()
	check("score: flag counts in order", a == 2 and h == 1, tostring(a) .. " " .. tostring(h))
	rawset(C_UIWidgetManager, "GetIconAndTextWidgetVisualizationInfo", oldIT)
	MOCK.widgets, MOCK.widgetInfo = nil, nil
	check("score: none without a score bar", R.ReadScore() == nil)
	local C = R.Codec
	local line = C.Encode({ t = 1, char = "A-B", bracket = "blitz", map = "X", result = "W", scoreA = 1500, scoreH = 980, players = {} })
	local m = C.Decode(line)
	check("score: saved and read back", m and m.scoreA == 1500 and m.scoreH == 980)
	-- a line saved before the score fields existed (two fewer top fields) keeps its players
	local full = C.Encode({ t = 1, char = "A-B", bracket = "3v3", map = "X", result = "W", players = { { name = "Me-R", dmg = 5 }, { name = "Them-R", dmg = 7 } } })
	local parts = C.Split(full, ";")
	table.remove(parts, #parts - 1); table.remove(parts, #parts - 1)
	local old = C.Decode(table.concat(parts, ";"))
	check("old line: players kept", old and #old.players == 2 and old.players[2].dmg == 7 and old.scoreA == nil and old.map == "X")
	-- a line with an empty player list
	local empty = C.Decode(C.Encode({ t = 1, char = "A-B", bracket = "bg", map = "Y", scoreA = 3, scoreH = 1, players = {} }))
	check("empty players: score kept", empty and #empty.players == 0 and empty.scoreA == 3 and empty.scoreH == 1)
end
flushErrors("final score")

-- calls to names the mock doesn't know: any that match one of our own local functions means a
-- function used before (or outside) its definition, which is a real error in the game
local locals = {}
for line in io.lines(LOCALFUNCS_PATH) do locals[line] = true end
local unknown = {}
for name, n in pairs(MOCK.unknownCalls) do
	unknown[#unknown + 1] = name
	check("not an out-of-scope local: " .. name, not locals[name])
end
table.sort(unknown)
print("unknown globals called (mocked as no-ops): " .. table.concat(unknown, ", "))

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
