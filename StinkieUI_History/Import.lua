-- StinkieUI Match History: one-time import of Rated Tracker's match history (RatedTrackerDB).
-- An addon can only read another addon's saved data while that addon is enabled, so Rated
-- Tracker must be enabled for the session you import in. Its files are never changed.
-- Runs in small batches over several frames so the game doesn't stall.
local _, H = ...

local SUI = StinkieUI_Shared
local R = SUI.MatchRecorder
local D = H.Data

local I = {}
H.Import = I
local Codec = SUI.MatchRecorder.Codec

-- Rated Tracker's bracket keys -> ours (seen in its data: 0, 1, 6, 8; 3 is its rated BG key)
I.BRACKETS = { ["0"] = "2v2", ["1"] = "3v3", ["3"] = "rbg", ["6"] = "shuffle", ["8"] = "blitz" }

local function Realm(r) return R.Realm(r) end

-- "Name-Realm" in the scoreboard's style; names without a realm get the owner's realm
local function FullName(name, ownerRealm)
	if type(name) ~= "string" or name == "" then return nil end
	local n, realm = name:match("^([^-]+)-(.+)$")
	if n then return n .. "-" .. Realm(realm) end
	return name .. "-" .. Realm(ownerRealm)
end
I.FullName = FullName

-- Rated Tracker sometimes saved "-1" (unknown) as 4294967295 or 2^64-1: anything that large is
-- treated as missing
local function Num(v)
	if type(v) ~= "number" or v ~= v then return nil end
	if v >= 4294967295 or v <= -4294967295 then return nil end
	return math.floor(v + 0.5)
end
local function Pos(v) v = Num(v) return (v and v > 0) and v or nil end

-- stat names (Rated Tracker stores names, not Blizzard's stat IDs) -> ids in our archive.
-- Known names reuse the id the game gave them in matches we recorded; others get 90000+.
local statIDByName
local function StatID(name)
	local a = D.Archive()
	if not statIDByName then
		statIDByName = {}
		for id, n in pairs(a.statNames) do statIDByName[n] = id end
	end
	local id = statIDByName[name]
	if not id then
		id = 90000
		while a.statNames[id] do id = id + 1 end
		a.statNames[id] = name
		statIDByName[name] = id
	end
	return id
end

local function StatsString(bgStats, columns)
	if type(bgStats) ~= "table" then return nil end
	local parts, done = {}, {}
	for k, v in pairs(bgStats) do
		local name
		if type(k) == "string" then
			name = k:gsub("|n", " ")
		elseif type(k) == "number" and type(columns) == "table" then
			for _, c in ipairs(columns) do
				if c.orderIndex == k and type(c.name) == "string" then name = c.name:gsub("|n", " ") end
			end
		end
		if name and type(v) == "number" and not done[name] then
			done[name] = true
			parts[#parts + 1] = StatID(name) .. ":" .. math.floor(v)
		end
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, "+") or nil
end

-- Solo Shuffle rounds -> "won.dur.ally:ally.firstDeath/..." with players as list indexes
local function RoundsString(rounds, indexByName, ownerRealm)
	if type(rounds) ~= "table" or #rounds == 0 then return nil end
	local out = {}
	for _, r in ipairs(rounds) do
		local won = (r.won == true and "1") or (r.won == false and "0") or "x"
		local allies = {}
		for _, a in ipairs(r.allies or {}) do
			local idx = indexByName[FullName(a.name, ownerRealm) or ""]
			if idx and not a.isSelf then allies[#allies + 1] = idx end
		end
		local fd = 0
		if type(r.firstDeath) == "table" then fd = indexByName[FullName(r.firstDeath.name, ownerRealm) or ""] or 0 end
		out[#out + 1] = table.concat({ won, tostring(Num(r.duration) or 0), table.concat(allies, ":"), tostring(fd) }, ".")
	end
	return table.concat(out, "/")
end

-- One Rated Tracker match -> our match table, or nil + reason.
function I.Convert(rt, bucket)
	local bracket = I.BRACKETS[tostring(rt._bracketID or rt.bracket or bucket)]
	if not bracket then return nil, "bracket" end
	-- Rated Tracker filed some single Solo Shuffle rounds as 2v2 / 3v3 games ("Round: 2/6" on the
	-- scoreboard). They're kept as their own bracket so they never count as arena games.
	if bracket == "2v2" or bracket == "3v3" then
		for _, line in ipairs(type(rt.finalScores) == "table" and rt.finalScores or {}) do
			if type(line) == "string" and line:find("^Round: %d+/6") then bracket = "shuffle-round" break end
		end
	end
	if type(rt.timestamp) ~= "number" or type(rt.players) ~= "table" then return nil, "incomplete" end
	local owner = rt._ownerCharKey or ""
	local ownerName, ownerRealm = owner:match("^([^-]+)-(.+)$")
	ownerRealm = ownerRealm or rt._recordingRealm or ""
	ownerName = ownerName or owner
	local players, indexByName, me = {}, {}, nil
	for _, p in ipairs(rt.players) do
		local full = FullName(p.name, ownerRealm)
		local classID = R.ClassID(p.classToken)
		local row = {
			name = full, class = classID, spec = R.SpecID(classID, p.spec), race = p.raceName,
			team = Num(p.faction), dmg = Num(p.damage), heal = Num(p.healing), kb = Num(p.kills), deaths = Num(p.deaths),
			hk = Num(p.honorableKills), rating = Pos(p.rating), rchg = Num(p.ratingChange), mmr = Pos(p.mmr),
			stats = StatsString(p.bgStats, rt.statColumns),
		}
		players[#players + 1] = row
		if full then indexByName[full] = #players end
		local base = type(p.name) == "string" and p.name:match("^([^-]+)") or nil
		if not me and base == ownerName and (not p.name:find("-") or full == FullName(owner, ownerRealm)) then me = #players end
	end
	if not me then return nil, "self" end
	local shuffle = bracket == "shuffle"
	local rounds = shuffle and Num(rt.roundsWon) or nil
	local result
	if shuffle and rounds then
		result = (rounds > 3 and "W") or (rounds == 3 and "D") or "L"
	elseif rt.isDraw then
		result = "D"
	elseif rt.won ~= nil then
		result = rt.won and "W" or "L"
	end
	local classID = R.ClassID(rt.playerClass)
	local m = {
		t = Num(rt.timestamp),
		char = ownerName .. "-" .. Realm(ownerRealm),
		bracket = bracket,
		map = rt.mapName or "?",
		mapID = Num(rt.map),
		dur = Num(rt.duration),
		result = result,
		rating = Pos(rt.preMatchRating),
		ratingAfter = Pos(rt.postMatchRating),
		mmr = Pos(rt.mmrPre), mmrAfter = Pos(rt.mmrPost),
		teamMMR = Pos(rt.teamMMR), enemyMMR = Pos(rt.enemyMMR),
		spec = R.SpecID(classID, rt.playerSpec) or players[me].spec,
		loadout = type(rt.blitzTalentExport) == "string" and rt.blitzTalentExport ~= "" and rt.blitzTalentExport or nil,
		rounds = rounds,
		season = Num(rt.season),
		me = me,
		team = players[me].team,
		winner = Num(rt.winner),
		queue = Num(rt.queueWaitSec),
		srounds = shuffle and RoundsString(rt.shuffleRounds, indexByName, ownerRealm) or nil,
		src = "RT",
		players = players,
	}
	return m
end

-- every match in RatedTrackerDB as { rt, bucket }
function I.Collect(db)
	local list = {}
	for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
		local regions = type(profile) == "table" and profile.matches
		for _, chars in pairs(type(regions) == "table" and regions or {}) do
			for _, buckets in pairs(type(chars) == "table" and chars or {}) do
				for bucket, entries in pairs(type(buckets) == "table" and buckets or {}) do
					if bucket ~= "lastMatch" and type(entries) == "table" then
						if entries[1] ~= nil or next(entries) == nil then
							for _, m in ipairs(entries) do list[#list + 1] = { m, tostring(bucket) } end
						else
							-- Solo Shuffle and Blitz are kept per spec
							for _, sub in pairs(entries) do
								if type(sub) == "table" then
									for _, m in ipairs(sub) do list[#list + 1] = { m, tostring(bucket) } end
								end
							end
						end
					end
				end
			end
		end
	end
	return list
end

-- Matches already in the archive (recorded or imported): character|bracket -> times
-- A match counts as already saved when the same character, bracket and map has a match with the
-- same length (within 3 s) ending within 15 minutes of it (the recorder and Rated Tracker stamp
-- the time at slightly different moments), or one within 20 s when a length is missing.
local function ExistingIndex()
	local idx = {}
	for i = 1, #D.Archive().records do
		local m = D.Get(i)
		if m and m.t then
			local key = tostring(m.char) .. "|" .. tostring(m.bracket)
			idx[key] = idx[key] or {}
			table.insert(idx[key], { t = m.t, map = m.map, dur = m.dur })
		end
	end
	return idx
end
I.ExistingIndex = ExistingIndex

function I.IsDuplicate(idx, m)
	local list = idx[tostring(m.char) .. "|" .. tostring(m.bracket)]
	if not list then return false end
	for _, e in ipairs(list) do
		local dt = math.abs(e.t - m.t)
		if e.dur and m.dur then
			if e.map == m.map and math.abs(e.dur - m.dur) <= 3 and dt <= 900 then return true end
		elseif dt <= 20 then
			return true
		end
	end
	return false
end
local IsDuplicate = I.IsDuplicate

-- Runs the import. onProgress(done, total), onDone(report). Returns false + message if it can't start.
function I.Run(onProgress, onDone, batch)
	if I.running then return false, "An import is already running." end
	local db = _G.RatedTrackerDB
	if type(db) ~= "table" then
		return false, "Rated Tracker's data isn't loaded. Enable Rated Tracker on the AddOns screen, log in (or /reload), then import again. You can disable it afterwards."
	end
	local list = I.Collect(db)
	if #list == 0 then return false, "Rated Tracker has no saved matches." end
	I.running = true
	statIDByName = nil
	local idx = ExistingIndex()
	local report = { total = #list, added = 0, duplicates = 0, skipped = {}, shuffles = 0, shuffleRounds = 0, loadouts = 0, queues = 0, singleRounds = 0 }
	local pos = 0
	batch = batch or 200
	local step
	local function run()
		local ok, err = pcall(step)
		if not ok then
			-- never leave the importer stuck "running": stop, keep what was added, and say so
			I.running = false
			D.SortArchive()
			geterrorhandler()(err)
			if onDone then report.failedAt = pos; onDone(report) end
		end
	end
	step = function()
		local stop = math.min(#list, pos + batch)
		for i = pos + 1, stop do
			local rt, bucket = list[i][1], list[i][2]
			local ok, m, why = pcall(I.Convert, rt, bucket)
			if ok and m then
				-- a match that can't be saved is counted and skipped; it never stops the import
				local encoded = pcall(Codec.Encode, m)
				if not encoded then ok, m, why = false, nil, nil end
			end
			if not ok then
				report.skipped.error = (report.skipped.error or 0) + 1
			elseif not m then
				report.skipped[why] = (report.skipped[why] or 0) + 1
			elseif IsDuplicate(idx, m) then
				report.duplicates = report.duplicates + 1
			else
				D.AddMatch(m)
				local key = m.char .. "|" .. m.bracket
				idx[key] = idx[key] or {}
				table.insert(idx[key], { t = m.t, map = m.map, dur = m.dur })
				SUI.MatchRecorder.RememberMMR(m)
				report.added = report.added + 1
				if m.bracket == "shuffle" then
					report.shuffles = report.shuffles + 1
					if m.srounds then report.shuffleRounds = report.shuffleRounds + 1 end
				end
				if m.bracket == "shuffle-round" then report.singleRounds = report.singleRounds + 1 end
				if m.loadout then report.loadouts = report.loadouts + 1 end
				if m.queue then report.queues = report.queues + 1 end
			end
		end
		pos = stop
		if onProgress then onProgress(pos, #list) end
		if pos < #list then
			C_Timer.After(0, run)
		else
			I.running = false
			D.SortArchive()
			if onDone then onDone(report) end
		end
	end
	run()
	return true
end

-- A readable summary of an import report
function I.ReportText(r)
	local skipped = 0
	for _, n in pairs(r.skipped) do skipped = skipped + n end
	local lines = {
		string.format("Imported %d of %d Rated Tracker matches.", r.added, r.total),
	}
	if r.failedAt then lines[#lines + 1] = string.format("The import stopped at match %d after an error; import again to continue (matches already brought in are skipped).", r.failedAt) end
	if r.duplicates > 0 then lines[#lines + 1] = string.format("%d were already in your history and were skipped.", r.duplicates) end
	if skipped > 0 then
		local why = {}
		for k, n in pairs(r.skipped) do why[#why + 1] = n .. " " .. ((k == "self" and "without you on the scoreboard") or (k == "bracket" and "from a bracket Stinkie UI doesn't know") or (k == "incomplete" and "with missing data") or "that failed to convert") end
		lines[#lines + 1] = "Skipped " .. table.concat(why, ", ") .. "."
	end
	lines[#lines + 1] = string.format("Talent loadouts on %d, queue times on %d, Solo Shuffle round details on %d of %d shuffles.", r.loadouts, r.queues, r.shuffleRounds, r.shuffles)
	if r.singleRounds > 0 then
		lines[#lines + 1] = string.format("%d single Solo Shuffle rounds that Rated Tracker had saved as 2v2 / 3v3 games are under \"Shuffle rounds (imported)\", so they don't count as arena games.", r.singleRounds)
	end
	lines[#lines + 1] = "Rated Tracker didn't save hero talents, PvP talents or item level, so imported matches show those as not recorded."
	lines[#lines + 1] = "You can disable Rated Tracker now."
	return table.concat(lines, " ")
end
