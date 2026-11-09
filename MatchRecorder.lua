-- StinkieUI: Match History recorder. At the end of every PvP match it reads Blizzard's final
-- scoreboard (readable once the match is over) and saves one compact line: bracket, map, result,
-- rating and MMR before/after, duration, your spec, hero talents, talent loadout and PvP talents,
-- and every player's class, spec, race, team, damage, healing, kills, deaths, rating, MMR and the
-- map's own stats (flag caps, bases, orbs...).
--
-- The recorder stays small: matches go into StinkieUIMatchInbox (a few hundred bytes each). The
-- full archive, browser and stats are the StinkieUI_History addon, which only loads when you open
-- it (/mh), so a big history never costs memory or loading time otherwise.
local _, ns = ...

local R = {}
ns.MatchRecorder = R

local issecret = ns.issecret
local function readable(v) return v ~= nil and not issecret(v) end
local function cfg() return ns.db.matchHistory end

---------------------------------------------------------------------------
-- Codec: one match <-> one line of text
--   top fields separated by ";", players by "^", player fields by ",", lists by "+", pairs by ":"
--   strings go through intern(s) -> token (the archive replaces repeated strings with "#n")
---------------------------------------------------------------------------
local C = {}
R.Codec = C
C.VERSION = 1

-- New fields go at the end so older lines keep decoding (missing trailing fields read as nil).
-- ilvl is no longer recorded (0.38.0); its slot stays so saved lines keep their layout.
-- queue: seconds in queue; srounds: Solo Shuffle rounds "won.duration.ally:ally.firstDeath/..."
-- (won 1/0/x, players by index); src: where the line came from ("RT" = Rated Tracker import).
C.TOP = { "t", "char", "bracket", "map", "mapID", "dur", "result", "rating", "ratingAfter", "mmr", "mmrAfter",
	"teamMMR", "enemyMMR", "spec", "hero", "loadout", "pvpTalents", "ilvl", "rounds", "season", "me", "team", "winner",
	"queue", "srounds", "src", "scoreA", "scoreH" }
C.TOP_STRING = { char = true, bracket = true, map = true, loadout = true, pvpTalents = true, result = true, srounds = true, src = true }
C.NO_INTERN = { srounds = true, pvpTalents = true } -- unique per match: kept inline
C.PLAYER = { "name", "class", "spec", "race", "team", "role", "dmg", "heal", "kb", "deaths", "hk", "rating", "rchg", "mmr", "mmrchg", "stats" }
C.PLAYER_STRING = { name = true, race = true, stats = true }

local function clean(s)
	s = tostring(s or "")
	return (s:gsub("[;%^,#]", "_"))
end
C.Clean = clean

local function num(v)
	if type(v) ~= "number" then return "" end
	-- WoW's %d only takes 32-bit numbers; bigger whole numbers (huge damage, or "-1" stored as
	-- 4294967295 by other addons) are written with %.0f instead
	if v == math.floor(v) then
		if v >= -2147483648 and v <= 2147483647 then return string.format("%d", v) end
		return string.format("%.0f", v)
	end
	return string.format("%.1f", v)
end

function C.Encode(m, intern)
	intern = intern or function(s) return s end
	local out = { "v" .. C.VERSION }
	for _, k in ipairs(C.TOP) do
		local v = m[k]
		if C.TOP_STRING[k] then
			out[#out + 1] = (v ~= nil and v ~= "") and (C.NO_INTERN[k] and clean(v) or intern(clean(v))) or ""
		else
			out[#out + 1] = num(v)
		end
	end
	local players = {}
	for _, p in ipairs(m.players or {}) do
		local f = {}
		for _, k in ipairs(C.PLAYER) do
			local v = p[k]
			if C.PLAYER_STRING[k] then
				f[#f + 1] = (v ~= nil and v ~= "") and ((k == "stats") and clean(v) or intern(clean(v))) or ""
			else
				f[#f + 1] = num(v)
			end
		end
		players[#players + 1] = table.concat(f, ",")
	end
	out[#out + 1] = table.concat(players, "^")
	return table.concat(out, ";")
end

local function split(s, ch)
	local out = {}
	if s == nil or s == "" then return out end
	local esc = ch:gsub("%p", "%%%0")
	for piece in (s .. ch):gmatch("(.-)" .. esc) do out[#out + 1] = piece end
	return out
end
C.Split = split

function C.Decode(line, resolve)
	resolve = resolve or function(s) return s end
	local parts = split(line, ";")
	if parts[1] ~= "v1" then return nil end
	-- the player list is always the last part: lines saved before a field was added have fewer
	-- top fields, so their missing ones read as nil
	local last = #parts
	local m = {}
	for i, k in ipairs(C.TOP) do
		local v = (i + 1 < last) and parts[i + 1] or nil
		if v == nil or v == "" then
			m[k] = nil
		elseif C.TOP_STRING[k] then
			m[k] = C.NO_INTERN[k] and v or resolve(v)
		else
			m[k] = tonumber(v)
		end
	end
	m.players = {}
	local plist = (last >= 2) and parts[last] or ""
	if plist ~= "" then
		for _, pl in ipairs(split(plist, "^")) do
			local fields = split(pl, ",")
			local p = {}
			for i, k in ipairs(C.PLAYER) do
				local v = fields[i]
				if v == nil or v == "" then
					p[k] = nil
				elseif C.PLAYER_STRING[k] then
					p[k] = (k == "stats") and v or resolve(v)
				else
					p[k] = tonumber(v)
				end
			end
			m.players[#m.players + 1] = p
		end
	end
	return m
end

-- "12:3+44:1" -> { [12] = 3, [44] = 1 }
function C.ParseStats(s)
	local t = {}
	for id, v in tostring(s or ""):gmatch("(%d+):(%-?%d+)") do t[tonumber(id)] = tonumber(v) end
	return t
end

---------------------------------------------------------------------------
-- Reading the finished match
---------------------------------------------------------------------------
-- realm names the way the scoreboard writes them: spaces removed ("Area52", "Mal'Ganis")
function R.Realm(r) return (tostring(r or ""):gsub("%s", "")) end
local function MyRealm() return R.Realm(GetRealmName and GetRealmName() or "") end

local specByClassAndName = {}
local function SpecID(classID, specName)
	if not (classID and readable(specName)) or specName == "" then return nil end
	local key = classID .. ":" .. specName
	if specByClassAndName[key] ~= nil then return specByClassAndName[key] or nil end
	local found = false
	local n = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID and C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
	for i = 1, n do
		local id, name = GetSpecializationInfoForClassID(classID, i)
		if name == specName then found = id end
	end
	specByClassAndName[key] = found
	return found or nil
end

R.SpecID = function(...) return SpecID(...) end
local classIDByToken
local function ClassID(token)
	if not readable(token) then return nil end
	if not classIDByToken then
		classIDByToken = {}
		for i = 1, (GetNumClasses and GetNumClasses() or 13) do
			local _, file, id = GetClassInfo(i)
			if file then classIDByToken[file] = id end
		end
	end
	return classIDByToken[token]
end

function R.Bracket()
	local P = C_PvP
	if P.IsInBrawl and P.IsInBrawl() then return "brawl" end
	if P.IsRatedSoloShuffle and P.IsRatedSoloShuffle() then return "shuffle" end
	if P.IsSoloShuffle and P.IsSoloShuffle() then return "shuffle-u" end
	if P.IsRatedSoloRBG and P.IsRatedSoloRBG() then return "blitz" end
	if P.IsSoloRBG and P.IsSoloRBG() then return "blitz-u" end
	if P.IsRatedBattleground and P.IsRatedBattleground() then return "rbg" end
	if P.IsRatedArena and P.IsRatedArena() then return "arena" end -- 2v2 / 3v3 decided from the team size
	if P.IsArena and P.IsArena() then return "skirmish" end
	if P.IsBattleground and P.IsBattleground() then return "bg" end
	return nil
end

-- bracket -> settings key
R.ClassID = function(t) return ClassID(t) end

R.BRACKET_SETTING = {
	["2v2"] = "arena", ["3v3"] = "arena", arena = "arena",
	shuffle = "shuffle", ["shuffle-u"] = "unrated",
	blitz = "blitz", ["blitz-u"] = "unrated",
	rbg = "rbg", skirmish = "skirmish", bg = "battleground", brawl = "brawl",
}

local function StatsString(stats, names)
	if type(stats) ~= "table" then return nil end
	local parts = {}
	for _, s in ipairs(stats) do
		if readable(s.pvpStatID) and readable(s.pvpStatValue) then
			parts[#parts + 1] = s.pvpStatID .. ":" .. math.floor(s.pvpStatValue)
			if names and readable(s.name) and s.name ~= "" then names[s.pvpStatID] = s.name end
		end
	end
	return table.concat(parts, "+")
end

local function MyLoadout()
	if not cfg().talents then return nil end
	local ok, s = pcall(function()
		local configID = C_ClassTalents.GetActiveConfigID()
		return configID and C_Traits.GenerateImportString(configID)
	end)
	return (ok and readable(s)) and s or nil
end

local function MyPvpTalents()
	local ok, list = pcall(function() return C_SpecializationInfo.GetAllSelectedPvpTalentIDs() end)
	if not (ok and type(list) == "table") then return nil end
	local out = {}
	for _, id in ipairs(list) do if readable(id) then out[#out + 1] = tostring(id) end end
	return table.concat(out, "+")
end

-- Final battleground score from the score bar at the top of the screen: Alliance (left), Horde
-- (right). Resource maps use the two-bar widget; flag maps show a count per side ("2/3").
-- Returns nil when the score bar isn't there or its numbers are hidden.
local function Num(text)
	if not readable(text) then return nil end
	local n = tostring(text):match("(%d+)%s*/%s*%d+") or tostring(text):match("^%s*(%d+)%s*$")
	return n and tonumber(n) or nil
end

function R.ReadScore()
	local W = C_UIWidgetManager
	local T = Enum.UIWidgetVisualizationType
	if not (W and T and W.GetTopCenterWidgetSetID and W.GetAllWidgetsBySetID) then return nil end
	local setID = W.GetTopCenterWidgetSetID()
	if not setID then return nil end
	local widgets = {}
	for _, w in ipairs(W.GetAllWidgetsBySetID(setID) or {}) do widgets[#widgets + 1] = w end
	table.sort(widgets, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
	local singles = {}
	for _, w in ipairs(widgets) do
		if w.widgetType == T.DoubleStatusBar and W.GetDoubleStatusBarWidgetVisualizationInfo then
			local i = W.GetDoubleStatusBarWidgetVisualizationInfo(w.widgetID)
			if i and readable(i.leftBarValue) and readable(i.rightBarValue) then return i.leftBarValue, i.rightBarValue end
		elseif T.DoubleIconAndText and w.widgetType == T.DoubleIconAndText and W.GetDoubleIconAndTextWidgetVisualizationInfo then
			local i = W.GetDoubleIconAndTextWidgetVisualizationInfo(w.widgetID)
			local a, h = i and Num(i.leftText), i and Num(i.rightText)
			if a and h then return a, h end
		elseif w.widgetType == T.IconAndText and W.GetIconAndTextWidgetVisualizationInfo then
			local i = W.GetIconAndTextWidgetVisualizationInfo(w.widgetID)
			local n = i and readable(i.shownState) and i.shownState ~= 0 and Num(i.text)
			if n then singles[#singles + 1] = n end
		end
	end
	if #singles == 2 then return singles[1], singles[2] end
	return nil
end

-- /stinkie score: what the score bar holds right now (for checking a map the reader gets wrong)
function R.DebugScore()
	local W = C_UIWidgetManager
	local setID = W and W.GetTopCenterWidgetSetID and W.GetTopCenterWidgetSetID()
	if not setID then ns:Print("No score bar here.") return end
	for _, w in ipairs(W.GetAllWidgetsBySetID(setID) or {}) do
		local text = ""
		pcall(function()
			local i = W.GetIconAndTextWidgetVisualizationInfo(w.widgetID)
			if i and readable(i.text) then text = i.text end
		end)
		ns:Print(string.format("widget %s type %s order %s %s", tostring(w.widgetID), tostring(w.widgetType), tostring(w.orderIndex), text))
	end
	local a, h = R.ReadScore()
	ns:Print("Score read: " .. (a and (a .. " - " .. h) or "none"))
end

-- Reads the scoreboard. Returns the match table, or nil + reason if it isn't readable yet.
function R.Read(statNames)
	local bracket = R.Bracket()
	if not bracket then return nil, "not a PvP match" end
	local n = GetNumBattlefieldScores() or 0
	if n == 0 then return nil, "no scores yet" end
	local myGUID = UnitGUID("player")
	local myName = UnitName("player")
	local players, me = {}, nil
	for i = 1, n do
		local s = C_PvP.GetScoreInfo(i)
		if s then
			if not readable(s.damageDone) then return nil, "scores still hidden" end
			local classID = ClassID(s.classToken)
			local full = s.name
			if readable(full) and not full:find("-") then
				full = full .. "-" .. MyRealm()
			end
			local p = {
				name = full, class = classID, spec = SpecID(classID, s.talentSpec), race = s.raceName,
				team = s.faction, role = readable(s.roleAssigned) and s.roleAssigned or nil,
				dmg = s.damageDone, heal = s.healingDone, kb = s.killingBlows, deaths = s.deaths, hk = s.honorableKills,
				rating = s.rating, rchg = s.ratingChange,
				-- 0 MMR means the game didn't give one (not trackable), not an MMR of 0
				mmr = (readable(s.prematchMMR) and s.prematchMMR ~= 0) and s.prematchMMR or nil,
				mmrchg = readable(s.mmrChange) and s.mmrChange or nil,
				mmrpost = (readable(s.postmatchMMR) and s.postmatchMMR ~= 0) and s.postmatchMMR or nil,
				stats = StatsString(s.stats, statNames),
			}
			players[#players + 1] = p
			local isMe = (readable(s.guid) and readable(myGUID) and s.guid == myGUID)
				or (readable(s.name) and s.name:match("^([^-]+)") == myName)
			if isMe and not me then me = #players end
		end
	end
	if not me then return nil, "you aren't on the scoreboard yet" end
	local mine = players[me]
	local myTeam = GetBattlefieldArenaFaction and GetBattlefieldArenaFaction() or mine.team
	if bracket == "arena" or bracket == "skirmish" then
		local size = 0
		for _, p in ipairs(players) do if p.team == mine.team then size = size + 1 end end
		if bracket == "arena" then bracket = (size <= 2) and "2v2" or "3v3" end
	end
	local winner = C_PvP.GetActiveMatchWinner and C_PvP.GetActiveMatchWinner()
	if not readable(winner) then winner = nil end
	local result
	local rounds
	local victoryStat = C_PvP.GetCustomVictoryStatID and C_PvP.GetCustomVictoryStatID() or 0
	if bracket == "shuffle" or bracket == "shuffle-u" then
		if readable(victoryStat) and victoryStat > 0 then
			rounds = C.ParseStats(mine.stats)[victoryStat]
		end
		if rounds then result = (rounds > 3 and "W") or (rounds == 3 and "D") or "L" end
	end
	if not result and winner ~= nil and myTeam ~= nil then
		result = (winner == myTeam and "W") or (winner == (myTeam + 1) % 2 and "L") or "D"
	end
	local teams = {}
	for i = 0, 1 do
		local ok, t = pcall(C_PvP.GetTeamInfo, i)
		teams[i + 1] = ok and t or nil
	end
	local function teamMMR(idx)
		local t = idx and teams[idx + 1]
		return (t and readable(t.ratingMMR) and t.ratingMMR > 0) and t.ratingMMR or nil
	end
	-- Solo Shuffle: the first entry is your own MMR, the second the average of your role's lobby
	local isShuffle = bracket == "shuffle" or bracket == "shuffle-u"
	local myMMRIndex, enemyMMRIndex = myTeam, myTeam and (myTeam + 1) % 2
	if isShuffle then myMMRIndex, enemyMMRIndex = 0, 1 end
	local instName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local mySpec
	pcall(function()
		local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
		local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
		local idx = getSpec and getSpec()
		mySpec = idx and getInfo(idx) or nil
	end)
	local hero
	pcall(function() hero = C_ClassTalents.GetActiveHeroTalentSpec() end)
	local m = {
		t = time(),
		char = UnitName("player") .. "-" .. MyRealm(),
		bracket = bracket,
		map = readable(instName) and instName or "?",
		mapID = readable(instanceID) and instanceID or nil,
		dur = C_PvP.GetActiveMatchDuration and math.floor(C_PvP.GetActiveMatchDuration() or 0) or nil,
		result = result,
		rating = mine.rating, ratingAfter = (mine.rating and mine.rchg) and (mine.rating + mine.rchg) or nil,
		mmr = mine.mmr, mmrAfter = mine.mmrpost or ((mine.mmr and mine.mmrchg) and (mine.mmr + mine.mmrchg)) or nil,
		teamMMR = teamMMR(myMMRIndex), enemyMMR = teamMMR(enemyMMRIndex),
		spec = mySpec or mine.spec,
		hero = hero,
		loadout = MyLoadout(),
		pvpTalents = MyPvpTalents(),
		rounds = rounds,
		season = GetCurrentArenaSeason and GetCurrentArenaSeason() or nil,
		me = me,
		team = myTeam,
		winner = winner,
		players = players,
	}
	if bracket ~= "arena" and bracket ~= "skirmish" and bracket ~= "2v2" and bracket ~= "3v3" and not isShuffle then
		local ok, a, h = pcall(R.ReadScore)
		if ok and a then m.scoreA, m.scoreH = a, h end
	end
	return m
end

---------------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------------
local function Inbox()
	if type(StinkieUIMatchInbox) ~= "table" then StinkieUIMatchInbox = {} end
	local box = StinkieUIMatchInbox
	box.records = box.records or {}
	box.statNames = box.statNames or {}
	return box
end
R.Inbox = Inbox

local BRACKET_LABEL = { ["2v2"] = "2v2", ["3v3"] = "3v3", shuffle = "Solo Shuffle", ["shuffle-u"] = "Shuffle (unrated)",
	blitz = "Blitz", ["blitz-u"] = "Blitz (unrated)", rbg = "Rated BG", skirmish = "Skirmish", bg = "Battleground", brawl = "Brawl",
	["shuffle-round"] = "Shuffle round" }
R.BRACKET_LABEL = BRACKET_LABEL

-- Latest MMR and rating per character and bracket, for the queue display (StinkieUIDB.lastMMR).
-- Matches can arrive in any order (imports), so only a newer match replaces the stored one.
function R.RememberMMR(m)
	if not (m and m.char and m.bracket and StinkieUIDB) then return end
	local mmr = m.mmrAfter or m.mmr
	if not (mmr or m.ratingAfter) then return end
	StinkieUIDB.lastMMR = StinkieUIDB.lastMMR or {}
	local byChar = StinkieUIDB.lastMMR[m.char] or {}
	StinkieUIDB.lastMMR[m.char] = byChar
	local delta = (m.mmrAfter and m.mmr) and (m.mmrAfter - m.mmr) or nil
	-- Blitz and Solo Shuffle report a change of 0: Blizzard only gives the MMR going into a match
	local noChange = delta == nil or delta == 0
	local function put(key)
		local cur = byChar[key]
		if cur and cur.t and m.t and cur.t > m.t then return end -- keep the newest
		local d = delta
		-- so the change is how far it moved since the last match we saw
		if noChange then
			if cur and cur.t == m.t then d = cur.delta
			elseif cur and cur.mmr and mmr then d = mmr - cur.mmr
			else d = nil end -- nothing to compare with yet: no number, not a false +0
		end
		byChar[key] = { mmr = mmr, rating = m.ratingAfter or m.rating, t = m.t, delta = d, spec = m.spec }
	end
	put(m.bracket)
	-- Solo Shuffle and Blitz have their own rating and MMR per spec
	if m.spec then put(m.bracket .. ":" .. m.spec) end
end

function R.MyChar() return UnitName("player") .. "-" .. MyRealm() end

-- what happened to the last match, kept in the saved variables to read when a match goes missing
function R.Note(status, m, why)
	if not StinkieUIDB then return end
	local me = m and m.players and m.players[m.me]
	StinkieUIDB.lastRecord = {
		t = time(), status = status, why = why and tostring(why) or nil, bracket = m and m.bracket, char = m and m.char,
		mmr = m and m.mmr, mmrAfter = m and m.mmrAfter, rchg = me and me.rchg, mmrchg = me and me.mmrchg, mmrpost = me and me.mmrpost,
	}
end

function R.Save(m)
	-- the queue display's number must never cost us the match itself
	local ok, err = pcall(R.RememberMMR, m)
	if not ok then
		R.Note("mmr failed", m, err)
		ns.Error(err)
	end
	local box = Inbox()
	local line = C.Encode(m)
	if R.receiver then
		-- the history window is loaded: hand it over directly
		local ok, err = pcall(R.receiver, line, box.statNames)
		if not ok then ns.Error(err); table.insert(box.records, line) end
	else
		table.insert(box.records, line)
	end
	if cfg().announce then
		local res = (m.result == "W" and "|cff55ff55win|r") or (m.result == "L" and "|cffff5555loss|r") or (m.result == "D" and "draw") or "done"
		if m.rounds then res = res .. " (" .. m.rounds .. "-" .. (6 - m.rounds) .. ")" end
		local delta = ""
		if m.rating and m.ratingAfter then
			local d = m.ratingAfter - m.rating
			delta = string.format(", %s%d (%d)", d >= 0 and "+" or "", d, m.ratingAfter)
		end
		ns:Print(string.format("Match saved: %s %s, %s%s. /mh to browse.", BRACKET_LABEL[m.bracket] or m.bracket, m.map, res, delta))
	end
end

R.RATED = { ["2v2"] = true, ["3v3"] = true, shuffle = true, blitz = true, rbg = true }

-- the scoreboard has this match's rating or MMR change (a real 0 for both is rare)
function R.HasChanges(m)
	local me = m.players and m.players[m.me]
	if not me then return true end
	return (me.rchg ~= nil and me.rchg ~= 0) or (me.mmrchg ~= nil and me.mmrchg ~= 0)
end

local state = { done = false, tries = 0 }

local function TryRecord()
	if state.done or not state.pending then return end
	state.tries = state.tries + 1
	local box = Inbox()
	local ok, m, why = pcall(R.Read, box.statNames)
	-- rated: the game fills in rating and MMR changes a moment after the scoreboard appears.
	-- Saved too early, a win or loss looked like +0. Wait for them (up to ~8 s), then save anyway.
	if ok and m and R.RATED[m.bracket] and state.tries < 8 and not R.HasChanges(m) then
		RequestBattlefieldScoreData()
		C_Timer.After(1, TryRecord)
		return
	end
	if ok and m then
		state.done, state.pending = true, false
		local key = R.BRACKET_SETTING[m.bracket]
		-- queue time (waiting outside other matches only), taken even if this bracket isn't saved
		local queued = ns.QueueInfo and ns.QueueInfo.TakeQueue and ns.QueueInfo.TakeQueue(m.bracket)
		if key and cfg()[key] == false then R.Note("bracket off", m) return end
		if queued and not m.queue then m.queue = queued end
		R.Note("saved", m)
		R.Save(m)
		return
	end
	if not ok then why = m end
	R.lastFailure = why
	if state.tries < 20 then
		C_Timer.After(1, TryRecord)
	else
		state.pending = false
		R.Note("unreadable", nil, why)
		ns:Print("Match History: couldn't read the final scoreboard (" .. tostring(why) .. ").")
	end
end

function R:Init()
	ns:On("PVP_MATCH_ACTIVE", function() state.done, state.pending, state.tries = false, false, 0 end)
	ns:On("PLAYER_ENTERING_WORLD", function()
		if not (C_PvP.IsMatchComplete and C_PvP.IsMatchComplete()) then state.done, state.pending, state.tries = false, false, 0 end
	end)
	ns:On("PVP_MATCH_COMPLETE", function()
		if not cfg().enabled or state.done or state.pending then return end
		if C_Commentator and C_Commentator.IsSpectating and C_Commentator.IsSpectating() then return end
		state.pending, state.tries = true, 0
		R.Note("match ended")
		RequestBattlefieldScoreData()
		C_Timer.After(1, TryRecord)
	end)
	ns:On("UPDATE_BATTLEFIELD_SCORE", function()
		if state.pending and not state.done and state.tries > 0 then TryRecord() end
	end)
end

---------------------------------------------------------------------------
-- Opening the history window (/mh)
---------------------------------------------------------------------------
StinkieUI_Shared = ns -- the history addon builds on Stinkie UI's widgets and fonts

function R.Open(tab)
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if not (StinkieUI_History and StinkieUI_History.Toggle) then
		local loaded, reason = load("StinkieUI_History")
		if not loaded then
			ns:Print("Match History needs the StinkieUI_History addon folder next to StinkieUI (" .. tostring(reason) .. "). Enable it on the AddOns screen.")
			return
		end
	end
	if StinkieUI_History and StinkieUI_History.Toggle then StinkieUI_History.Toggle(tab) end
end

-- Loads the history addon (without opening the window) and imports Rated Tracker's matches
function R.Import()
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if not (StinkieUI_History and StinkieUI_History.StartImport) then
		local loaded, reason = load("StinkieUI_History")
		if not loaded then
			ns:Print("Match History needs the StinkieUI_History addon folder next to StinkieUI (" .. tostring(reason) .. ").")
			return
		end
	end
	StinkieUI_History.Data.Archive()
	StinkieUI_History.Data.MergeInbox()
	StinkieUI_History.StartImport()
end

SLASH_STINKIEMH1 = "/mh"
SLASH_STINKIEMH2 = "/matchhistory"
SlashCmdList.STINKIEMH = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "import" then R.Import() return end
	R.Open((msg == "stats") and "stats" or nil)
end

ns:RegisterModule("MatchRecorder", R)
