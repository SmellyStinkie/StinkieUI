-- StinkieUI Match History: the archive (compact lines + a shared string table) and the stats.
-- Pure Lua apart from the saved variables, so it can be tested outside the game.
local _, H = ...
StinkieUI_History = H

local SUI = StinkieUI_Shared
local Codec = SUI.MatchRecorder.Codec

local D = {}
H.Data = D

---------------------------------------------------------------------------
-- Archive: StinkieUIMatchHistory = { v = 1, dict = { strings }, records = { lines }, statNames = {} }
-- Strings that repeat (player names, maps, races, loadouts) are stored once in dict and written
-- as "#n" in the lines.
---------------------------------------------------------------------------
local archive, reverse

function D.Archive()
	if archive then return archive end
	if type(StinkieUIMatchHistory) ~= "table" then StinkieUIMatchHistory = {} end
	archive = StinkieUIMatchHistory
	archive.v = 1
	archive.dict = archive.dict or {}
	archive.records = archive.records or {}
	archive.statNames = archive.statNames or {}
	return archive
end

function D.SetArchive(t) archive, reverse = t, nil; return D.Archive() end -- tests

local function Reverse()
	if reverse then return reverse end
	reverse = {}
	for i, s in ipairs(D.Archive().dict) do reverse[s] = i end
	return reverse
end

function D.Intern(s)
	local r = Reverse()
	local i = r[s]
	if not i then
		local dict = D.Archive().dict
		dict[#dict + 1] = s
		i = #dict
		r[s] = i
	end
	return "#" .. i
end

function D.Resolve(v)
	if v:sub(1, 1) == "#" then
		local i = tonumber(v:sub(2))
		return i and D.Archive().dict[i] or v
	end
	return v
end

-- inline line (from the recorder) -> archive line
function D.Add(line, statNames)
	local m = Codec.Decode(line)
	if not m then return false end
	local a = D.Archive()
	a.records[#a.records + 1] = Codec.Encode(m, D.Intern)
	for id, name in pairs(statNames or {}) do a.statNames[id] = name end
	D.dirty = true
	return true
end

-- a match table (already decoded) -> archive line
function D.AddMatch(m)
	local a = D.Archive()
	a.records[#a.records + 1] = Codec.Encode(m, D.Intern)
	D.dirty = true
end

-- after a bulk add (import): summaries are rebuilt next time they're needed
function D.SortArchive()
	D.summaries = nil
end

-- moves everything waiting in the recorder's inbox into the archive
function D.MergeInbox()
	local box = StinkieUIMatchInbox
	if type(box) ~= "table" or type(box.records) ~= "table" then return 0 end
	local n = 0
	for _, line in ipairs(box.records) do
		if D.Add(line, box.statNames) then n = n + 1 end
	end
	box.records = {}
	return n
end

function D.Get(index)
	local line = D.Archive().records[index]
	return line and Codec.Decode(line, D.Resolve)
end

function D.Delete(index)
	table.remove(D.Archive().records, index)
	D.dirty = true
end

function D.SizeBytes()
	local n = 0
	local a = D.Archive()
	for _, l in ipairs(a.records) do n = n + #l + 4 end
	for _, s in ipairs(a.dict) do n = n + #s + 4 end
	return n
end

---------------------------------------------------------------------------
-- Summaries: one small table per match for lists and stats. Built on open, dropped on close.
---------------------------------------------------------------------------
D.BG_BRACKETS = { blitz = true, ["blitz-u"] = true, rbg = true, bg = true }

local function SortedKey(list)
	table.sort(list)
	return table.concat(list, "+")
end

function D.Summarize(m, index)
	local me = m.players[m.me or 0]
	local s = {
		i = index, t = m.t or 0, char = m.char, bracket = m.bracket, map = m.map, mapID = m.mapID,
		dur = m.dur, result = m.result, rating = m.rating, ratingAfter = m.ratingAfter,
		mmr = m.mmr, mmrAfter = m.mmrAfter, teamMMR = m.teamMMR, enemyMMR = m.enemyMMR,
		spec = m.spec, hero = m.hero, rounds = m.rounds, season = m.season, queue = m.queue, src = m.src,
		dmg = me and me.dmg, heal = me and me.heal, kb = me and me.kb, deaths = me and me.deaths,
		enemySpecs = {}, enemies = {}, allies = {}, allySpecs = {}, names = {},
	}
	if not me then return s end
	local shuffle = m.bracket == "shuffle" or m.bracket == "shuffle-u"
	local teamDmg = {}
	for pi, p in ipairs(m.players) do
		if p.name then s.names[#s.names + 1] = p.name:lower() end
		if pi ~= m.me then
			if shuffle or p.team ~= me.team then
				s.enemySpecs[#s.enemySpecs + 1] = p.spec or 0
				if p.name then s.enemies[#s.enemies + 1] = p.name end
			else
				s.allies[#s.allies + 1] = p.name
				s.allySpecs[#s.allySpecs + 1] = p.spec or 0
			end
		end
		if p.team == me.team and p.dmg then teamDmg[#teamDmg + 1] = p.dmg end
	end
	local specs = {}
	for i, v in ipairs(s.enemySpecs) do specs[i] = v end
	s.enemyComp = SortedKey(specs)
	-- the side you fought on, in battlegrounds and Blitz (scoreboard team 0 = Horde, 1 = Alliance)
	if D.BG_BRACKETS[m.bracket] and (me.team == 0 or me.team == 1) then s.side = me.team == 0 and "Horde" or "Alliance" end
	table.sort(teamDmg, function(a, b) return a > b end)
	for rank, v in ipairs(teamDmg) do if v == me.dmg then s.dmgRank = rank break end end
	s.teamSize = #teamDmg
	return s
end

-- How far back the window loads: the last N months (Stinkie UI option, default 12), or all of
-- it once "Load all" is clicked (for this session). Older matches stay saved, just not decoded,
-- which keeps the window's memory down with big imported histories.
function D.LoadSince()
	if D.loadAll then return nil end
	local SH = StinkieUI_Shared
	local months = SH and SH.db and SH.db.matchHistory and SH.db.matchHistory.loadMonths or 12
	if not months or months <= 0 then return nil end
	return time() - months * 30 * 86400
end

-- a saved line's time without decoding it ("v<version>;<time>;...")
function D.LineTime(line)
	return tonumber(line:match("^v%d+;(%d+)") or "") or 0
end

function D.BuildSummaries(onProgress)
	local a = D.Archive()
	local out = {}
	local since = D.LoadSince()
	D.skipped = 0
	for i, line in ipairs(a.records) do
		if since and D.LineTime(line) < since then
			D.skipped = D.skipped + 1
		else
			local m = Codec.Decode(line, D.Resolve)
			if m then out[#out + 1] = D.Summarize(m, i) end
		end
		if onProgress and i % 500 == 0 then onProgress(i, #a.records) end
	end
	table.sort(out, function(x, y) return x.t > y.t end)
	D.summaries = out
	D.dirty = false
	return out
end

function D.Release()
	D.summaries = nil
	collectgarbage("collect")
end

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------
-- f = { bracket = "3v3"|"arena"|..|nil, char, season, since (epoch), search (lowercase) }
local GROUPS = {
	arena = { ["2v2"] = true, ["3v3"] = true },
	shuffleAll = { shuffle = true, ["shuffle-u"] = true },
	blitzAll = { blitz = true, ["blitz-u"] = true },
	bgAll = { bg = true, rbg = true, blitz = true, ["blitz-u"] = true, brawl = true },
}
D.BRACKET_GROUPS = GROUPS

function D.Match(s, f)
	-- single imported Shuffle rounds only show when picked, so they never count twice
	if not f.bracket and s.bracket == "shuffle-round" then return false end
	if f.bracket then
		local g = GROUPS[f.bracket]
		if g then if not g[s.bracket] then return false end
		elseif s.bracket ~= f.bracket then return false end
	end
	if f.char and s.char ~= f.char then return false end
	if f.spec and s.spec ~= f.spec then return false end
	if f.season and s.season ~= f.season then return false end
	if f.since and s.t < f.since then return false end
	if f.result and s.result ~= f.result then return false end
	if f.search and f.search ~= "" then
		-- every word must match something: map, a player, a spec / class, bracket, result, comp
		local text = D.SearchText(s)
		for word in f.search:gmatch("%S+") do
			if not text:find(word, 1, true) then return false end
		end
	end
	return true
end

-- one lowercase string per match with everything the search box looks at (built once, kept)
local RESULT_WORDS = { W = "win won victory", L = "loss lost defeat", D = "draw" }
function D.SearchText(s)
	if s.searchText then return s.searchText end
	local parts = { s.map or "", s.bracket or "", RESULT_WORDS[s.result or ""] or "", s.char or "" }
	local SH = StinkieUI_Shared
	local labels = SH and SH.MatchRecorder and SH.MatchRecorder.BRACKET_LABEL
	local label = labels and labels[s.bracket or ""]
	if label then parts[#parts + 1] = label end
	for _, n in ipairs(s.names or {}) do parts[#parts + 1] = n end
	local specs = {}
	if s.spec then specs[#specs + 1] = s.spec end
	for _, id in ipairs(s.enemySpecs or {}) do specs[#specs + 1] = id end
	for _, id in ipairs(s.allySpecs or {}) do specs[#specs + 1] = id end
	if GetSpecializationInfoByID then
		for _, id in ipairs(specs) do
			if id and id ~= 0 then
				local ok, _, name, _, _, _, classFile = pcall(GetSpecializationInfoByID, id)
				if ok and type(name) == "string" then parts[#parts + 1] = name end
				if ok and type(classFile) == "string" then parts[#parts + 1] = classFile end
			end
		end
	end
	s.searchText = table.concat(parts, " "):lower()
	return s.searchText
end

function D.Filter(list, f)
	local out = {}
	for _, s in ipairs(list or {}) do if D.Match(s, f) then out[#out + 1] = s end end
	return out
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------
-- Wilson score interval: the range the true win rate likely sits in (95%), given wins out of n.
function D.Wilson(wins, n, z)
	if not n or n == 0 then return nil, nil end
	z = z or 1.96
	local p = wins / n
	local z2 = z * z
	local denom = 1 + z2 / n
	local center = (p + z2 / (2 * n)) / denom
	local half = z * math.sqrt(p * (1 - p) / n + z2 / (4 * n * n)) / denom
	return math.max(0, center - half), math.min(1, center + half)
end

local function IsShuffle(s) return s.bracket == "shuffle" or s.bracket == "shuffle-u" end

-- Accumulates a set of summaries. Solo Shuffle counts rounds (6 per match) for the win rate.
function D.Aggregate(list)
	local a = { games = 0, w = 0, l = 0, d = 0, rw = 0, rn = 0, net = 0, rated = 0, dmg = 0, heal = 0, dmgN = 0, healN = 0,
		dur = 0, durN = 0, queue = 0, queueN = 0, kb = 0, deaths = 0 }
	for _, s in ipairs(list) do
		a.games = a.games + 1
		if s.result == "W" then a.w = a.w + 1 elseif s.result == "L" then a.l = a.l + 1 elseif s.result == "D" then a.d = a.d + 1 end
		if IsShuffle(s) and s.rounds then
			a.rw, a.rn = a.rw + s.rounds, a.rn + 6
		elseif s.result == "W" then
			a.rw, a.rn = a.rw + 1, a.rn + 1
		elseif s.result == "L" then
			a.rn = a.rn + 1
		end
		if s.rating and s.ratingAfter then a.net, a.rated = a.net + (s.ratingAfter - s.rating), a.rated + 1 end
		if s.dmg then a.dmg, a.dmgN = a.dmg + s.dmg, a.dmgN + 1 end
		if s.heal then a.heal, a.healN = a.heal + s.heal, a.healN + 1 end
		if s.dur then a.dur, a.durN = a.dur + s.dur, a.durN + 1 end
		if s.queue then a.queue, a.queueN = a.queue + s.queue, a.queueN + 1 end
		a.kb = a.kb + (s.kb or 0)
		a.deaths = a.deaths + (s.deaths or 0)
	end
	a.winRate = a.rn > 0 and a.rw / a.rn or nil
	a.lo, a.hi = D.Wilson(a.rw, a.rn)
	a.avgDmg = a.dmgN > 0 and a.dmg / a.dmgN or nil
	a.avgHeal = a.healN > 0 and a.heal / a.healN or nil
	a.avgDur = a.durN > 0 and a.dur / a.durN or nil
	a.avgQueue = a.queueN > 0 and a.queue / a.queueN or nil
	a.avgNet = a.rated > 0 and a.net / a.rated or nil
	return a
end

-- group key functions: return one key, or a list of keys (a match counts in each)
D.GROUP_BY = {
	map = function(s) return s.map or "?" end,
	comp = function(s) return s.enemyComp ~= "" and s.enemyComp or nil end,
	enemySpec = function(s)
		local seen, out = {}, {}
		for _, id in ipairs(s.enemySpecs) do if id ~= 0 and not seen[id] then seen[id] = true; out[#out + 1] = id end end
		return out
	end,
	mySpec = function(s) return s.spec end,
	hero = function(s) return s.hero end,
	teammate = function(s) return #s.allies > 0 and s.allies or nil end,
	opponent = function(s) return #s.enemies > 0 and s.enemies or nil end,
	faction = function(s) return s.side end,
	-- each battleground map split by the side you fought on ("Warsong Gulch - Horde")
	mapFaction = function(s) return s.side and ((s.map or "?") .. " - " .. s.side) or nil end,
	allyComp = function(s)
		local specs = {}
		for i, v in ipairs(s.allySpecs) do specs[i] = v end
		if s.spec then specs[#specs + 1] = s.spec end
		return #specs > 0 and SortedKey(specs) or nil
	end,
	hour = function(s) return tonumber(date("%H", s.t)) end,
	weekday = function(s) return tonumber(date("%w", s.t)) end,
	length = function(s)
		if not s.dur then return nil end
		local m = math.floor(s.dur / 60)
		if m < 3 then return "0-2 min" elseif m < 6 then return "3-5 min" elseif m < 10 then return "6-9 min"
		elseif m < 15 then return "10-14 min" else return "15+ min" end
	end,
	mmrBand = function(s)
		local v = s.enemyMMR or s.mmr
		if not v then return nil end
		local b = math.floor(v / 100) * 100
		return b
	end,
	char = function(s) return s.char end,
	bracket = function(s) return s.bracket end,
	season = function(s) return s.season end,
}

function D.Group(list, by)
	local fn = D.GROUP_BY[by]
	local buckets = {}
	for _, s in ipairs(list) do
		local k = fn(s)
		if type(k) == "table" then
			for _, kk in ipairs(k) do
				buckets[kk] = buckets[kk] or {}
				table.insert(buckets[kk], s)
			end
		elseif k ~= nil then
			buckets[k] = buckets[k] or {}
			table.insert(buckets[k], s)
		end
	end
	local rows = {}
	for k, items in pairs(buckets) do
		local agg = D.Aggregate(items)
		agg.key = k
		rows[#rows + 1] = agg
	end
	table.sort(rows, function(x, y)
		if x.games ~= y.games then return x.games > y.games end
		return tostring(x.key) < tostring(y.key)
	end)
	return rows
end

-- rating after each match, oldest first (for the trend line)
function D.RatingSeries(list)
	local out = {}
	for i = #list, 1, -1 do
		local s = list[i]
		if s.ratingAfter then out[#out + 1] = s.ratingAfter end
	end
	return out
end

-- longest win and loss streaks, and the current streak (list newest first)
function D.Streaks(list)
	local bestW, bestL, cur, curType = 0, 0, 0, nil
	for i = #list, 1, -1 do
		local r = list[i].result
		if r == "W" or r == "L" then
			if r == curType then cur = cur + 1 else cur, curType = 1, r end
			if r == "W" then bestW = math.max(bestW, cur) else bestL = math.max(bestL, cur) end
		end
	end
	return bestW, bestL, cur, curType
end

---------------------------------------------------------------------------
-- CSV export of a filtered list
---------------------------------------------------------------------------
local function csvField(v)
	v = tostring(v == nil and "" or v)
	if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
	return v
end

function D.CSV(list, specName)
	specName = specName or tostring
	local lines = { "date,character,bracket,map,result,rounds,rating_before,rating_after,mmr_before,mmr_after,team_mmr,enemy_mmr,duration_s,my_spec,damage,healing,killing_blows,deaths,allies,enemy_specs" }
	for _, s in ipairs(list) do
		local enemies = {}
		for i, id in ipairs(s.enemySpecs) do enemies[i] = specName(id) end
		local row = { date("%Y-%m-%d %H:%M", s.t), s.char, s.bracket, s.map, s.result, s.rounds, s.rating, s.ratingAfter, s.mmr, s.mmrAfter,
			s.teamMMR, s.enemyMMR, s.dur, specName(s.spec), s.dmg, s.heal, s.kb, s.deaths, table.concat(s.allies, " "), table.concat(enemies, " ") }
		for i = 1, 20 do row[i] = csvField(row[i]) end
		lines[#lines + 1] = table.concat(row, ",", 1, 20)
	end
	return table.concat(lines, "\n")
end
