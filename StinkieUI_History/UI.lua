-- StinkieUI Match History: the window (/mh). Matches tab (browsable list + full scoreboard of any
-- match) and Match Stats tab (win rates by map, comp, spec, teammate, time...; rating trend; CSV).
local _, H = ...

local SUI = StinkieUI_Shared
local D = H.Data
local W = SUI.Options.W
local ACCENT, BRAND = SUI.ACCENT, SUI.BRAND
local Label, FlatButton, Flat = W.Label, W.FlatButton, W.Flat

local WIN_W, WIN_H, HEAD_H = 1010, 660, 58
local ROW_H, LIST_ROWS = 24, 22 -- fills the window: 22 rows + header = the body height

---------------------------------------------------------------------------
-- Formatting helpers
---------------------------------------------------------------------------
local BRACKET_LABEL = SUI.MatchRecorder.BRACKET_LABEL
local WEEKDAYS = { [0] = "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

local specCache = {}
local function SpecInfo(id)
	if not id or id == 0 then return nil end
	local c = specCache[id]
	if c == nil then
		local ok, _, name, _, icon, role, classFile = pcall(GetSpecializationInfoByID, id)
		c = (ok and name) and { name = name, icon = icon, role = role, class = classFile } or false
		specCache[id] = c
	end
	return c or nil
end

local function SpecIcon(id, size)
	local s = SpecInfo(id)
	if not s then return "" end
	size = size or 16
	return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", tostring(s.icon), size, size)
end

local function SpecName(id)
	local s = SpecInfo(id)
	return s and s.name or (id and id ~= 0 and ("spec " .. id) or "?")
end

local function ClassColored(text, classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if not c then return text end
	return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text)
end

local heroCache = {}
local function HeroName(id)
	if not id then return "?" end
	if heroCache[id] == nil then
		local name
		pcall(function()
			local info = C_Traits.GetSubTreeInfo(C_ClassTalents.GetActiveConfigID(), id)
			name = info and info.name
		end)
		heroCache[id] = name or ("Hero tree " .. id)
	end
	return heroCache[id]
end

local function CompIcons(key, size)
	if not key or key == "" then return "" end
	local out = {}
	for id in tostring(key):gmatch("%d+") do out[#out + 1] = SpecIcon(tonumber(id), size) end
	return table.concat(out, "")
end

local function Clock(s)
	if not s then return "" end
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function Short(n)
	if not n then return "" end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.0fk", n / 1e3) end
	return tostring(n)
end

local function Pct(v) return v and string.format("%.0f%%", v * 100) or "-" end

local function Signed(n)
	if not n then return "" end
	n = math.floor(n + 0.5)
	if n > 0 then return "|cff55ff55+" .. n .. "|r" end
	if n < 0 then return "|cffff5555" .. n .. "|r" end
	return "0"
end

-- MMR the way the lists show it: 0 or missing means the game gave none
local function MMRText(v)
	if v == nil or v == 0 then return "N/A" end
	return tostring(v)
end

local function ResultText(s)
	if s.rounds and (s.bracket == "shuffle" or s.bracket == "shuffle-u") then
		local col = s.rounds > 3 and "55ff55" or s.rounds == 3 and "dddddd" or "ff5555"
		return string.format("|cff%s%d-%d|r", col, s.rounds, 6 - s.rounds)
	end
	if s.result == "W" then return "|cff55ff55Win|r" end
	if s.result == "L" then return "|cffff5555Loss|r" end
	if s.result == "D" then return "Draw" end
	return "-"
end

local GroupLabel
function GroupLabel(by, key)
	if by == "comp" or by == "allyComp" then return CompIcons(key, 18) end
	if by == "enemySpec" or by == "mySpec" then return SpecIcon(key, 16) .. " " .. SpecName(key) end
	if by == "hero" then return HeroName(key) end
	if by == "hour" then return string.format("%02d:00", key) end
	if by == "weekday" then return WEEKDAYS[key] or tostring(key) end
	if by == "bracket" then return BRACKET_LABEL[key] or key end
	if by == "mmrBand" then return key .. "-" .. (key + 99) end
	if by == "season" then return "Season " .. tostring(key) end
	if by == "faction" then
		if key == "Horde" then return "|cffe04040" .. (FACTION_HORDE or "Horde") .. "|r" end
		if key == "Alliance" then return "|cff4080ff" .. (FACTION_ALLIANCE or "Alliance") .. "|r" end
	end
	if by == "mapFaction" then
		local map, side = tostring(key):match("^(.*) %- (%a+)$")
		if map then return map .. "  " .. GroupLabel("faction", side) end
	end
	return tostring(key)
end

---------------------------------------------------------------------------
-- Small widgets
---------------------------------------------------------------------------
local function Text(parent, size, justify, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	SUI.SetFont(fs, size or 12, "OUTLINE")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	if color then fs:SetTextColor(color[1], color[2], color[3]) end
	return fs
end

local function Dropdown(parent, width, items, get, set)
	local btn
	btn = FlatButton(parent, "", width, function()
		W.ShowPopup(btn, type(items) == "function" and items() or items, get(), function(v)
			set(v)
			btn:Sync()
		end)
	end)
	btn.text:ClearAllPoints()
	btn.text:SetPoint("LEFT", 8, 0)
	btn.text:SetPoint("RIGHT", -16, 0)
	btn.text:SetJustifyH("LEFT")
	local arrow = Label(btn, "v", 11, { 0.6, 0.6, 0.65 })
	arrow:SetPoint("RIGHT", -6, 0)
	function btn:Sync()
		local cur = get()
		for _, it in ipairs(type(items) == "function" and items() or items) do
			if it[1] == cur then self.text:SetText(it[2]) return end
		end
		self.text:SetText(tostring(cur))
	end
	btn:Sync()
	return btn
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local win
local filters = { period = "all" }
local view = { tab = "matches", offset = 0, groupBy = "map", minGames = 1, sortCol = 2, sortDesc = true, statOffset = 0 }
local filtered = {}

local function CurrentFilter()
	local f = { bracket = filters.bracket, char = filters.char, season = filters.season, result = filters.result, spec = filters.spec }
	local now = time()
	if filters.period == "today" then
		local d = date("*t", now); d.hour, d.min, d.sec = 0, 0, 0
		f.since = time(d)
	elseif filters.period == "7" then f.since = now - 7 * 86400
	elseif filters.period == "30" then f.since = now - 30 * 86400 end
	if filters.search and filters.search ~= "" then f.search = filters.search:lower() end
	return f
end

local Refresh -- forward

local BRACKETS = {
	{ nil, "All brackets" }, { "arena", "Arena (2v2 + 3v3)" }, { "2v2", "2v2" }, { "3v3", "3v3" },
	{ "shuffleAll", "Solo Shuffle (all)" }, { "shuffle", "Solo Shuffle (rated)" },
	{ "blitzAll", "Blitz (all)" }, { "blitz", "Blitz (rated)" }, { "rbg", "Rated BG" },
	{ "skirmish", "Skirmish" }, { "bg", "Battleground" }, { "brawl", "Brawl" },
	{ "shuffle-round", "Shuffle rounds (imported)" },
}

local function CharItems()
	local seen, items = {}, { { nil, "All characters" } }
	for _, s in ipairs(D.summaries or {}) do
		if s.char and not seen[s.char] then seen[s.char] = true; items[#items + 1] = { s.char, s.char } end
	end
	return items
end

local function SpecItems()
	local seen, list = {}, {}
	for _, s in ipairs(D.summaries or {}) do
		if s.spec and not seen[s.spec] then seen[s.spec] = true; list[#list + 1] = s.spec end
	end
	table.sort(list, function(a, b) return SpecName(a) < SpecName(b) end)
	local items = { { nil, "All my specs" } }
	for _, id in ipairs(list) do items[#items + 1] = { id, SpecIcon(id, 14) .. " " .. SpecName(id) } end
	return items
end

local function SeasonItems()
	local seen, items = {}, { { nil, "All seasons" } }
	local list = {}
	for _, s in ipairs(D.summaries or {}) do
		if s.season and not seen[s.season] then seen[s.season] = true; list[#list + 1] = s.season end
	end
	table.sort(list, function(a, b) return a > b end)
	for _, v in ipairs(list) do items[#items + 1] = { v, "Season " .. v } end
	return items
end

---------------------------------------------------------------------------
-- Matches tab
---------------------------------------------------------------------------
local COLUMNS = {
	{ "Date", 92 }, { "Bracket", 98 }, { "Map", 140 }, { "Result", 52 }, { "Rating", 92 }, { "MMR", 52 },
	{ "Length", 48 }, { "Queue", 48 }, { "Me", 30 }, { "Opponents", 150 }, { "Damage", 56 }, { "Healing", 56 },
}

local function BuildMatches(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints()
	local x = 6
	for _, col in ipairs(COLUMNS) do
		local h = Text(p, 12, "LEFT", ACCENT)
		h:SetPoint("TOPLEFT", x, -4)
		h:SetText(col[1])
		x = x + col[2]
	end
	p.rows = {}
	for i = 1, LIST_ROWS do
		local r = CreateFrame("Button", nil, p)
		r:SetSize(WIN_W - 54, ROW_H - 2)
		r:SetPoint("TOPLEFT", 0, -22 - (i - 1) * ROW_H)
		r.bg = Flat(r, 1, 1, 1, i % 2 == 0 and 0.03 or 0.0)
		r.hl = r:CreateTexture(nil, "ARTWORK")
		r.hl:SetAllPoints()
		r.hl:SetColorTexture(BRAND.plum[1], BRAND.plum[2], BRAND.plum[3], 0.45)
		r.hl:Hide()
		r:SetScript("OnEnter", function(self) self.hl:Show() end)
		r:SetScript("OnLeave", function(self) self.hl:Hide() end)
		r:SetScript("OnClick", function(self) if self.summary then H.ShowDetail(self.summary) end end)
		r.cells = {}
		local cx = 6
		for c, col in ipairs(COLUMNS) do
			local fs = Text(r, 12, "LEFT")
			fs:SetPoint("LEFT", cx, 0)
			fs:SetWidth(col[2] - 6)
			r.cells[c] = fs
			cx = cx + col[2]
		end
		p.rows[i] = r
	end
	p.empty = Text(p, 14, "CENTER", { 0.7, 0.68, 0.6 })
	p.empty:SetPoint("CENTER")
	p:EnableMouseWheel(true)
	p:SetScript("OnMouseWheel", function(_, delta)
		view.offset = math.max(0, math.min(math.max(0, #filtered - LIST_ROWS), view.offset - delta * 3))
		H.RenderMatches()
	end)
	-- scroll bar: click anywhere on it to jump there, or drag the thumb
	local bar = CreateFrame("Button", nil, p)
	bar:SetWidth(12)
	bar:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -22)
	bar:SetHeight(LIST_ROWS * ROW_H)
	bar:SetFrameLevel(p:GetFrameLevel() + 10)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(1, 1, 1, 0.05)
	p.track = bar:CreateTexture(nil, "ARTWORK")
	p.track:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
	p.track:SetWidth(6)
	local function SeekTo()
		local _, cy = GetCursorPosition()
		local scale = bar:GetEffectiveScale()
		local top, h = bar:GetTop(), bar:GetHeight()
		if not (top and h and h > 0 and scale > 0) then return end
		local frac = math.max(0, math.min(1, (top - cy / scale) / h))
		local maxOff = math.max(0, #filtered - LIST_ROWS)
		view.offset = math.floor(frac * maxOff + 0.5)
		H.RenderMatches()
	end
	bar:SetScript("OnMouseDown", function(self)
		SeekTo()
		self:SetScript("OnUpdate", SeekTo)
	end)
	bar:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	bar:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	p.scrollBar = bar
	return p
end

function H.RenderMatches()
	local p = win.matches
	for i, r in ipairs(p.rows) do
		local s = filtered[view.offset + i]
		r.summary = s
		if s then
			local c = r.cells
			c[1]:SetText(date("%m/%d %H:%M", s.t))
			c[2]:SetText(BRACKET_LABEL[s.bracket] or s.bracket or "")
			c[3]:SetText(s.map or "")
			c[4]:SetText(ResultText(s))
			if s.ratingAfter and s.rating then
				c[5]:SetText(s.ratingAfter .. "  " .. Signed(s.ratingAfter - s.rating))
			else
				c[5]:SetText("")
			end
			c[6]:SetText(MMRText(s.mmrAfter or s.mmr))
			c[7]:SetText(Clock(s.dur))
			c[8]:SetText(Clock(s.queue))
			c[9]:SetText(SpecIcon(s.spec, 16))
			if #s.enemySpecs <= 6 then
				c[10]:SetText(CompIcons(s.enemyComp, 16))
			else
				c[10]:SetText(#s.enemySpecs .. " players")
			end
			c[11]:SetText(Short(s.dmg))
			c[12]:SetText(Short(s.heal))
			r:Show()
		else
			r:Hide()
		end
	end
	local total = #filtered
	p.empty:SetText(total == 0 and ((#(D.summaries or {}) == 0) and "No matches saved yet. They're saved automatically when a match ends." or "No matches match these filters.") or "")
	if total > LIST_ROWS then
		local viewH = LIST_ROWS * ROW_H
		local h = math.max(20, viewH * LIST_ROWS / total)
		local y = (viewH - h) * (view.offset / (total - LIST_ROWS))
		p.track:ClearAllPoints()
		p.track:SetPoint("TOP", p.scrollBar, "TOP", 0, -y)
		p.track:SetHeight(h)
		p.track:Show()
		p.scrollBar:Show()
	else
		p.track:Hide()
		p.scrollBar:Hide()
	end
	H.UpdateCount()
end

---------------------------------------------------------------------------
-- Match detail
---------------------------------------------------------------------------
local DETAIL_COLS = { { "Player", 190 }, { "Spec", 130 }, { "Damage", 70 }, { "Healing", 70 }, { "KB", 34 }, { "Deaths", 46 }, { "Rating", 60 }, { "Change", 54 }, { "MMR", 54 } }

local function BuildDetail(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints()
	p:Hide()
	local back = FlatButton(p, "< Back", 80, function() p:Hide(); win.matches:Show() end)
	back:SetPoint("TOPLEFT", 0, 0)
	p.title = Text(p, 16, "LEFT", BRAND.cream)
	p.title:SetPoint("LEFT", back, "RIGHT", 12, 0)
	p.line1 = Text(p, 13, "LEFT")
	p.line1:SetPoint("TOPLEFT", 0, -32)
	p.line2 = Text(p, 13, "LEFT", { 0.8, 0.78, 0.7 })
	p.line2:SetPoint("TOPLEFT", 0, -52)
	p.line3 = Text(p, 12, "LEFT", { 0.70, 0.68, 0.60 })
	p.line3:SetPoint("TOPLEFT", 0, -70)
	p.loadout = FlatButton(p, "Copy talent loadout", 160, function()
		if p.match and p.match.loadout then W.ShowTextPopup("Talent loadout", p.match.loadout) end
	end)
	p.loadout:SetPoint("TOPRIGHT", 0, 0)
	p.cells = {}
	p.statHeaders = {}
	p.rows = {}
	for i = 1, 24 do -- 15v15 fits; 40-player battlegrounds show the top 24
		local r = CreateFrame("Frame", nil, p)
		r:SetSize(WIN_W - 40, 18)
		r.bg = Flat(r, 1, 1, 1, i % 2 == 0 and 0.03 or 0)
		r.cells = {}
		p.rows[i] = r
	end
	return p
end

-- What a detail column sorts by. Stat columns (flag captures and so on) are keyed "s<id>" because
-- which ones show differs per match.
local DETAIL_SORT = {
	function(pl) return tostring(pl.name or ""):lower() end,
	function(pl) return tostring(SpecName(pl.spec) or ""):lower() end,
	function(pl) return pl.dmg or 0 end,
	function(pl) return pl.heal or 0 end,
	function(pl) return pl.kb or 0 end,
	function(pl) return pl.deaths or 0 end,
	function(pl) return pl.rating or 0 end,
	function(pl) return pl.rchg or 0 end,
	function(pl) return pl.mmr or 0 end,
}

function H.DetailHeader(ci) return win and win.detail.statHeaders[ci] end

-- One ranked list of everyone, by the column you clicked; ties keep the scoreboard's order
function H.SortDetail(list, key, desc)
	local value = DETAIL_SORT[key]
	local statID = type(key) == "string" and tonumber(key:match("^s(%d+)$"))
	for i, pl in ipairs(list) do
		pl._at = i
		if statID then
			pl._sort = tonumber(SUI.MatchRecorder.Codec.ParseStats(pl.stats)[statID]) or 0
		else
			pl._sort = value(pl)
		end
	end
	table.sort(list, function(a, b)
		if a._sort ~= b._sort then
			if desc then return a._sort > b._sort end
			return a._sort < b._sort
		end
		return a._at < b._at
	end)
end

function H.ShowDetail(summary)
	local m = D.Get(summary.i)
	if not m then return end
	local p = win.detail
	p.summary, p.match = summary, m
	win.matches:Hide()
	p:Show()
	p.title:SetText(string.format("%s  ·  %s  ·  %s", BRACKET_LABEL[m.bracket] or m.bracket, m.map or "?", date("%A %B %d, %H:%M", m.t)))
	local parts = { ResultText(summary), "Length " .. Clock(m.dur) }
	if m.rating and m.ratingAfter then parts[#parts + 1] = string.format("Rating %d > %d (%s)", m.rating, m.ratingAfter, Signed(m.ratingAfter - m.rating)) end
	if m.scoreA and m.scoreH then
		parts[#parts + 1] = string.format("Final score |cff4a9eff Alliance %d|r - |cffe0443a%d Horde|r", m.scoreA, m.scoreH)
	end
	if m.mmr and m.mmr ~= 0 then parts[#parts + 1] = "MMR " .. m.mmr .. ((m.mmrAfter and m.mmrAfter ~= 0) and (" > " .. m.mmrAfter) or "")
	elseif m.mmr == 0 then parts[#parts + 1] = "MMR N/A" end
	if m.teamMMR or m.enemyMMR then parts[#parts + 1] = string.format("Team MMR %s vs %s", MMRText(m.teamMMR), MMRText(m.enemyMMR)) end
	p.line1:SetText(table.concat(parts, "    "))
	local NR = "|cff888888not recorded|r"
	local build = { SpecIcon(m.spec, 16) .. " " .. SpecName(m.spec) }
	build[#build + 1] = "Hero: " .. (m.hero and HeroName(m.hero) or NR)
	if not (m.pvpTalents and m.pvpTalents ~= "") then build[#build + 1] = "PvP talents: " .. NR end
	if m.pvpTalents and m.pvpTalents ~= "" then
		local names = {}
		for id in m.pvpTalents:gmatch("%d+") do
			local ok, _, name = pcall(GetPvpTalentInfoByID, tonumber(id))
			names[#names + 1] = (ok and name) or id
		end
		build[#build + 1] = "PvP talents: " .. table.concat(names, ", ")
	end
	if m.queue then build[#build + 1] = "Queue " .. Clock(m.queue) end
	build[#build + 1] = m.char or ""
	p.line2:SetText(table.concat(build, "    "))
	-- Solo Shuffle rounds (imported from Rated Tracker): result, teammates, first death
	local extra = {}
	if m.srounds then
		local parts = {}
		for i, r in ipairs({ strsplit("/", m.srounds) }) do
			local won, dur, allies, fd = strsplit(".", r)
			local mates = {}
			for idx in tostring(allies or ""):gmatch("%d+") do
				local pl = m.players[tonumber(idx)]
				if pl and pl.name then mates[#mates + 1] = pl.name:match("^([^-]+)") end
			end
			local fdp = tonumber(fd) and m.players[tonumber(fd)]
			local mark = won == "1" and "|cff55ff55W|r" or won == "0" and "|cffff5555L|r" or "?"
			parts[#parts + 1] = string.format("R%d %s %s%s", i, mark, table.concat(mates, "+"),
				fdp and fdp.name and (" (died: " .. fdp.name:match("^([^-]+)") .. ")") or "")
		end
		extra[#extra + 1] = table.concat(parts, "   ")
	end
	if m.src == "RT" then extra[#extra + 1] = "|cff888888Imported from Rated Tracker|r" end
	p.line3:SetText(table.concat(extra, "    "))
	p.loadout:SetShown(m.loadout ~= nil)

	-- map stat columns (flag caps, bases...) in the order the game gave them
	local statIDs, seen = {}, {}
	for _, pl in ipairs(m.players) do
		for id in tostring(pl.stats or ""):gmatch("(%d+):") do
			id = tonumber(id)
			if not seen[id] then seen[id] = true; statIDs[#statIDs + 1] = id end
		end
	end
	local names = D.Archive().statNames
	local cols = {}
	for i, c in ipairs(DETAIL_COLS) do cols[#cols + 1] = { c[1], c[2], key = i } end
	for i = 1, math.min(4, #statIDs) do
		cols[#cols + 1] = { names[statIDs[i]] or ("Stat " .. statIDs[i]), 70, stat = statIDs[i], key = "s" .. statIDs[i] }
	end
	-- a sort on a stat this match doesn't have falls back to the normal order
	local sortKey
	for _, col in ipairs(cols) do
		if col.key == view.detailSort then sortKey = col.key end
	end

	-- header
	for _, h in ipairs(p.statHeaders) do h:Hide() end
	local x = 6
	for ci, col in ipairs(cols) do
		local h = p.statHeaders[ci]
		if not h then
			h = CreateFrame("Button", nil, p)
			h.text = Text(h, 12, "LEFT", ACCENT)
			h.text:SetPoint("LEFT")
			h:SetScript("OnClick", function(self)
				if view.detailSort == self.key then
					view.detailDesc = not view.detailDesc
				else
					-- names A-Z first, numbers high-low first
					view.detailSort, view.detailDesc = self.key, self.key ~= 1 and self.key ~= 2
				end
				H.ShowDetail(p.summary)
			end)
			p.statHeaders[ci] = h
		end
		h.key = col.key
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", x, -88)
		h:SetSize(col[2] - 4, 16)
		h.text:SetWidth(col[2] - 4)
		local active = sortKey == col.key
		h.text:SetText(col[1] .. (active and (view.detailDesc and " v" or " ^") or ""))
		local tint = active and BRAND.cream or ACCENT
		h.text:SetTextColor(tint[1], tint[2], tint[3])
		h:Show()
		x = x + col[2]
	end

	-- players: my team first, then the rest; each team sorted by damage + healing. A clicked
	-- column ranks everyone together instead, with the other team's rows tinted.
	local me = m.players[m.me or 0]
	local list = {}
	for i, pl in ipairs(m.players) do pl._i = i; list[#list + 1] = pl end
	local shuffle = m.bracket == "shuffle" or m.bracket == "shuffle-u"
	table.sort(list, function(a, b)
		local ta = (not shuffle and me and a.team == me.team) and 0 or 1
		local tb = (not shuffle and me and b.team == me.team) and 0 or 1
		if ta ~= tb then return ta < tb end
		return (a.dmg or 0) + (a.heal or 0) > (b.dmg or 0) + (b.heal or 0)
	end)
	if sortKey then H.SortDetail(list, sortKey, view.detailDesc) end
	local y = -108
	local lastTeam
	for ri, r in ipairs(p.rows) do
		local pl = list[ri]
		if pl then
			local team = (not shuffle and me and pl.team == me.team) and 0 or 1
			if sortKey then
				local enemy = not shuffle and me and team == 1
				r.bg:SetColorTexture(1, enemy and 0.2 or 1, enemy and 0.2 or 1, enemy and 0.07 or (ri % 2 == 0 and 0.03 or 0))
			else
				r.bg:SetColorTexture(1, 1, 1, ri % 2 == 0 and 0.03 or 0)
				if lastTeam ~= nil and team ~= lastTeam then y = y - 8 end
			end
			lastTeam = team
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 0, y)
			y = y - 18
			local info = SpecInfo(pl.spec)
			local classFile = info and info.class
			if not classFile and pl.class then local _, file = GetClassInfo(pl.class); classFile = file end
			local nameText = ClassColored(pl.name or "?", classFile)
			if pl._i == m.me then nameText = "|cff" .. SUI.ACCENT_HEX .. ">|r " .. nameText end
			local parsed = SUI.MatchRecorder.Codec.ParseStats(pl.stats)
			local values = { nameText, SpecIcon(pl.spec, 14) .. " " .. SpecName(pl.spec), Short(pl.dmg), Short(pl.heal), pl.kb or "", pl.deaths or "",
				(pl.rating and pl.rating > 0) and pl.rating or "", (pl.rchg and pl.rchg ~= 0) and Signed(pl.rchg) or "", (pl.mmr == 0) and "N/A" or pl.mmr or "" }
			for ci = #DETAIL_COLS + 1, #cols do values[ci] = parsed[cols[ci].stat] or "" end
			local cx = 6
			for ci, col in ipairs(cols) do
				local fs = r.cells[ci] or Text(r, 12, "LEFT")
				r.cells[ci] = fs
				fs:ClearAllPoints()
				fs:SetPoint("LEFT", cx, 0)
				fs:SetWidth(col[2] - 4)
				fs:SetText(tostring(values[ci] or ""))
				fs:Show()
				cx = cx + col[2]
			end
			for ci = #cols + 1, #r.cells do r.cells[ci]:Hide() end
			r:Show()
		else
			r:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Match Stats tab
---------------------------------------------------------------------------
local GROUP_ITEMS = {
	{ "map", "Map" }, { "comp", "Enemy comp" }, { "enemySpec", "Enemy spec" }, { "allyComp", "My team comp" },
	{ "teammate", "Teammate" }, { "opponent", "Opponent" }, { "faction", "Faction (battlegrounds)" }, { "mapFaction", "Map + faction (battlegrounds)" }, { "mySpec", "My spec" }, { "hero", "My hero talents" }, { "mmrBand", "MMR range (enemy)" },
	{ "length", "Match length" }, { "hour", "Time of day" }, { "weekday", "Day of week" },
	{ "bracket", "Bracket" }, { "char", "Character" }, { "season", "Season" },
}
local STAT_COLS = { { "", 250 }, { "Games", 52 }, { "Win %", 56 }, { "95% range", 90 }, { "W-L", 70 }, { "Rating/game", 76 },
	{ "Avg damage", 78 }, { "Avg healing", 78 }, { "Avg length", 70 }, { "Avg queue", 70 } }
local STAT_ROWS = 15

local function BuildStats(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints()
	p:Hide()
	p.summary = Text(p, 13, "LEFT")
	p.summary:SetPoint("TOPLEFT", 0, 0)
	p.summary:SetWidth(520)
	p.summary:SetWordWrap(true)
	p.summary:SetJustifyV("TOP")
	p.summary:SetHeight(110)
	p.summary:SetSpacing(4)

	-- rating trend
	local chart = CreateFrame("Frame", nil, p)
	chart:SetSize(400, 104)
	chart:SetPoint("TOPRIGHT", -6, -2)
	Flat(chart, 0.08, 0.07, 0.05, 1)
	SUI.CreateBackdrop(chart, 0)
	chart.title = Text(chart, 11, "LEFT", { 0.7, 0.68, 0.6 })
	chart.title:SetPoint("TOPLEFT", 4, -3)
	chart.hiText = Text(chart, 10, "RIGHT", { 0.7, 0.68, 0.6 })
	chart.hiText:SetPoint("TOPRIGHT", -4, -3)
	chart.loText = Text(chart, 10, "RIGHT", { 0.7, 0.68, 0.6 })
	chart.loText:SetPoint("BOTTOMRIGHT", -4, 3)
	chart.lines = {}
	p.chart = chart

	local gb = Label(p, "Group by", 13)
	gb:SetPoint("TOPLEFT", 0, -122)
	p.groupBy = Dropdown(p, 180, GROUP_ITEMS, function() return view.groupBy end, function(v) view.groupBy = v; view.statOffset = 0; H.RenderStats() end)
	p.groupBy:SetPoint("LEFT", gb, "RIGHT", 8, 0)
	local mg = Label(p, "At least", 13)
	mg:SetPoint("LEFT", p.groupBy, "RIGHT", 16, 0)
	p.minGames = Dropdown(p, 100, { { 1, "1 game" }, { 3, "3 games" }, { 5, "5 games" }, { 10, "10 games" }, { 20, "20 games" } },
		function() return view.minGames end, function(v) view.minGames = v; view.statOffset = 0; H.RenderStats() end)
	p.minGames:SetPoint("LEFT", mg, "RIGHT", 8, 0)
	local sb = Label(p, "Click a column heading to sort by it (again to reverse).", 12, { 0.65, 0.63, 0.56 })
	sb:SetPoint("LEFT", p.minGames, "RIGHT", 16, 0)
	local csv = FlatButton(p, "Export CSV", 110, function()
		W.ShowTextPopup("Match History CSV (filtered)", D.CSV(filtered, SpecName))
	end)
	csv:SetPoint("TOPRIGHT", -6, -118)

	local x = 6
	p.headers = {}
	for ci, col in ipairs(STAT_COLS) do
		local b = CreateFrame("Button", nil, p)
		b:SetSize(col[2] - 4, 18)
		b:SetPoint("TOPLEFT", x - 2, -147)
		b.text = Text(b, 12, "LEFT", ACCENT)
		b.text:SetPoint("LEFT", 2, 0)
		b.label = (ci == 1) and "Group" or col[1]
		b:SetScript("OnClick", function()
			if view.sortCol == ci then
				view.sortDesc = not view.sortDesc
			else
				view.sortCol, view.sortDesc = ci, ci ~= 1 -- names A-Z first, numbers high-low first
			end
			view.statOffset = 0
			H.RenderStats()
		end)
		b:SetScript("OnEnter", function(self) self.text:SetTextColor(BRAND.cream[1], BRAND.cream[2], BRAND.cream[3]) end)
		b:SetScript("OnLeave", function(self) H.PaintHeaders() end)
		p.headers[ci] = b
		x = x + col[2]
	end
	p.rows = {}
	for i = 1, STAT_ROWS do
		local r = CreateFrame("Frame", nil, p)
		r:SetSize(WIN_W - 40, 22)
		r:SetPoint("TOPLEFT", 0, -168 - (i - 1) * 24)
		r.bg = Flat(r, 1, 1, 1, i % 2 == 0 and 0.03 or 0)
		r.cells = {}
		local cx = 6
		for c, col in ipairs(STAT_COLS) do
			local fs = Text(r, 12, "LEFT")
			fs:SetPoint("LEFT", cx, 0)
			fs:SetWidth(col[2] - 6)
			r.cells[c] = fs
			cx = cx + col[2]
		end
		-- win-rate bar behind the win % cell
		r.bar = r:CreateTexture(nil, "BORDER")
		r.bar:SetPoint("LEFT", r.cells[3], "LEFT", -2, 0)
		r.bar:SetHeight(16)
		p.rows[i] = r
	end
	p:EnableMouseWheel(true)
	p:SetScript("OnMouseWheel", function(_, delta)
		local n = p.rowCount or 0
		view.statOffset = math.max(0, math.min(math.max(0, n - STAT_ROWS), view.statOffset - delta * 3))
		H.RenderStats()
	end)
	p.note = Text(p, 11, "LEFT", { 0.65, 0.63, 0.56 })
	p.note:SetPoint("BOTTOMLEFT", 0, 0)
	p.note:SetText("95% range: where your true win rate likely is, given the games played. Ranges that overlap aren't a real difference yet. Solo Shuffle counts rounds.")
	return p
end

-- value each stats column sorts by (95% range sorts by its low end, which rewards sample size)
local SORT_VALUE = {
	function(r) return r.label or "" end,
	function(r) return r.games end,
	function(r) return r.winRate or -1 end,
	function(r) return r.lo or -1 end,
	function(r) return r.w - r.l end,
	function(r) return r.avgNet or -math.huge end,
	function(r) return r.avgDmg or -1 end,
	function(r) return r.avgHeal or -1 end,
	function(r) return r.avgDur or -1 end,
	function(r) return r.avgQueue or -1 end,
}

function H.SortRows(rows)
	local col = view.sortCol or 2
	local desc = view.sortDesc
	if desc == nil then desc = true end
	local f = SORT_VALUE[col] or SORT_VALUE[2]
	for _, r in ipairs(rows) do
		if col == 1 then
			-- strip color and texture codes so names sort by their text
			r.label = tostring(GroupLabel(view.groupBy, r.key)):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
		end
	end
	table.sort(rows, function(a, b)
		local va, vb = f(a), f(b)
		if va == vb then return a.games > b.games end
		if desc then return va > vb end
		return va < vb
	end)
end

function H.PaintHeaders()
	local p = win and win.stats
	if not (p and p.headers) then return end
	for ci, b in ipairs(p.headers) do
		local active = (view.sortCol or 2) == ci
		local desc = view.sortDesc
		if desc == nil then desc = true end
		b.text:SetText(b.label .. (active and (desc and " v" or " ^") or ""))
		if active then b.text:SetTextColor(BRAND.cream[1], BRAND.cream[2], BRAND.cream[3])
		else b.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3]) end
	end
end

local function DrawChart(chart, series)
	for _, l in ipairs(chart.lines) do l:Hide() end
	local n = #series
	if n < 2 then
		chart.title:SetText("Rating trend (needs 2+ rated matches)")
		chart.hiText:SetText("")
		chart.loText:SetText("")
		return
	end
	-- at most 120 points
	local step = math.max(1, math.ceil(n / 120))
	local pts = {}
	for i = 1, n, step do pts[#pts + 1] = series[i] end
	if pts[#pts] ~= series[n] then pts[#pts + 1] = series[n] end
	local lo, hi = math.huge, -math.huge
	for _, v in ipairs(pts) do lo, hi = math.min(lo, v), math.max(hi, v) end
	if hi == lo then hi = lo + 1 end
	local w, h = chart:GetWidth() - 44, chart:GetHeight() - 26
	chart.title:SetText(string.format("Rating trend, %d matches", n))
	chart.hiText:SetText(hi)
	chart.loText:SetText(lo)
	for i = 2, #pts do
		local l = chart.lines[i - 1]
		if not l then
			l = chart:CreateLine(nil, "ARTWORK")
			l:SetThickness(2)
			chart.lines[i - 1] = l
		end
		local x1 = 6 + (i - 2) / (#pts - 1) * w
		local x2 = 6 + (i - 1) / (#pts - 1) * w
		local y1 = 8 + (pts[i - 1] - lo) / (hi - lo) * h
		local y2 = 8 + (pts[i] - lo) / (hi - lo) * h
		l:SetStartPoint("BOTTOMLEFT", chart, x1, y1)
		l:SetEndPoint("BOTTOMLEFT", chart, x2, y2)
		local up = pts[i] >= pts[i - 1]
		l:SetColorTexture(up and ACCENT[1] or 0.85, up and ACCENT[2] or 0.3, up and ACCENT[3] or 0.3, 1)
		l:Show()
	end
end

function H.RenderStats()
	local p = win.stats
	local all = D.Aggregate(filtered)
	local bestW, bestL, cur, curType = D.Streaks(filtered)
	local lines = {}
	if all.games == 0 then
		lines[1] = "No matches with these filters."
	else
		local shuffleOnly = filters.bracket == "shuffle" or filters.bracket == "shuffleAll"
		lines[#lines + 1] = string.format("|cff%s%d matches|r   %d wins, %d losses%s   %s %s (95%%: %s - %s)",
			SUI.ACCENT_HEX, all.games, all.w, all.l, all.d > 0 and (", " .. all.d .. " draws") or "",
			shuffleOnly and "Round win rate" or "Win rate", Pct(all.winRate), Pct(all.lo), Pct(all.hi))
		local latest
		for _, s in ipairs(filtered) do if s.ratingAfter then latest = s break end end
		local peak
		for _, s in ipairs(filtered) do if s.ratingAfter and (not peak or s.ratingAfter > peak) then peak = s.ratingAfter end end
		if all.rated > 0 then
			lines[#lines + 1] = string.format("Rating: net %s over %d rated (%s per game)%s%s", Signed(all.net), all.rated, Signed(all.avgNet),
				latest and ("   current " .. latest.ratingAfter .. " (" .. (BRACKET_LABEL[latest.bracket] or "") .. ")") or "", peak and ("   peak " .. peak) or "")
		end
		lines[#lines + 1] = string.format("Average: %s damage, %s healing, %s long, %.1f killing blows, %.1f deaths%s",
			Short(all.avgDmg and math.floor(all.avgDmg)), Short(all.avgHeal and math.floor(all.avgHeal)), Clock(all.avgDur and math.floor(all.avgDur)),
			all.kb / all.games, all.deaths / all.games,
			all.avgQueue and string.format(", %s in queue (%d with a queue time)", Clock(math.floor(all.avgQueue)), all.queueN) or "")
		lines[#lines + 1] = string.format("Streaks: best %d wins, worst %d losses, now %d %s", bestW, bestL, cur, curType == "W" and "wins" or curType == "L" and "losses" or "")
		-- best and worst map with enough games
		local maps = D.Group(filtered, "map")
		local best, worst
		for _, r in ipairs(maps) do
			if r.games >= 5 and r.winRate then
				if not best or r.winRate > best.winRate then best = r end
				if not worst or r.winRate < worst.winRate then worst = r end
			end
		end
		if best and worst and best ~= worst then
			lines[#lines + 1] = string.format("Best map: %s %s (%d)   Worst map: %s %s (%d)", best.key, Pct(best.winRate), best.games, worst.key, Pct(worst.winRate), worst.games)
		end
	end
	p.summary:SetText(table.concat(lines, "\n"))
	DrawChart(p.chart, D.RatingSeries(filtered))

	local rows = {}
	for _, r in ipairs(D.Group(filtered, view.groupBy)) do if r.games >= view.minGames then rows[#rows + 1] = r end end
	-- the search box also narrows the groups: searching a player while grouped by teammate or
	-- opponent shows that player's row, not everyone who shared a match with them
	local q = filters.search and filters.search ~= "" and filters.search:lower()
	if q then
		local hits = {}
		for _, r in ipairs(rows) do
			local label = tostring(GroupLabel(view.groupBy, r.key)):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
			if label:find(q, 1, true) or tostring(r.key):lower():find(q, 1, true) then hits[#hits + 1] = r end
		end
		if #hits > 0 then rows = hits end
	end
	H.SortRows(rows)
	H.PaintHeaders()
	p.rowCount = #rows
	for i, r in ipairs(p.rows) do
		local g = rows[view.statOffset + i]
		if g then
			local c = r.cells
			c[1]:SetText(GroupLabel(view.groupBy, g.key))
			c[2]:SetText(g.games)
			c[3]:SetText(Pct(g.winRate))
			c[4]:SetText(g.lo and (Pct(g.lo) .. " - " .. Pct(g.hi)) or "")
			c[5]:SetText(g.w .. "-" .. g.l)
			c[6]:SetText(g.avgNet and Signed(g.avgNet) or "")
			c[7]:SetText(Short(g.avgDmg and math.floor(g.avgDmg)))
			c[8]:SetText(Short(g.avgHeal and math.floor(g.avgHeal)))
			c[9]:SetText(Clock(g.avgDur and math.floor(g.avgDur)))
			c[10]:SetText(Clock(g.avgQueue and math.floor(g.avgQueue)))
			local wr = g.winRate or 0
			r.bar:SetWidth(math.max(1, 52 * wr))
			local good = wr >= 0.5
			r.bar:SetColorTexture(good and 0.25 or 0.6, good and 0.55 or 0.2, good and 0.2 or 0.2, 0.55)
			r:Show()
		else
			r:Hide()
		end
	end
	H.UpdateCount()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function Refresh()
	if not (win and win:IsShown()) then return end
	filtered = D.Filter(D.summaries, CurrentFilter())
	view.offset = math.min(view.offset, math.max(0, #filtered - LIST_ROWS))
	for _, dd in ipairs(win.dropdowns) do dd:Sync() end
	if view.tab == "matches" then
		win.stats:Hide()
		if not win.detail:IsShown() then win.matches:Show() end
		H.RenderMatches()
	else
		win.matches:Hide()
		win.detail:Hide()
		win.stats:Show()
		H.RenderStats()
	end
	win.tabMatches:SetSelected(view.tab == "matches")
	win.tabStats:SetSelected(view.tab == "stats")
end
H.Refresh = Refresh

local function CreateWindow()
	local w = CreateFrame("Frame", "StinkieUI_MatchHistory", UIParent)
	w:SetSize(WIN_W, WIN_H)
	w:SetPoint("CENTER")
	w:SetFrameStrata("HIGH")
	w:SetClampedToScreen(true)
	w:EnableMouse(true)
	w:SetMovable(true)
	w:RegisterForDrag("LeftButton")
	-- size and place are remembered (StinkieUIMatchHistory.window)
	local saved = D.Archive().window or {}
	D.Archive().window = saved
	w:SetScale(saved.scale or 1)
	if saved.point then
		w:ClearAllPoints()
		w:SetPoint(saved.point[1], UIParent, saved.point[1], saved.point[2], saved.point[3])
	end
	w:SetScript("OnDragStart", w.StartMoving)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saved.point = SUI.CalculatePoint(self)
		if saved.point then
			self:ClearAllPoints()
			self:SetPoint(saved.point[1], UIParent, saved.point[1], saved.point[2], saved.point[3])
		end
	end)
	-- drag the bottom-right corner to resize
	local grip = CreateFrame("Button", nil, w)
	grip:SetSize(18, 18)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(w:GetFrameLevel() + 20)
	for i = 1, 3 do
		local t = grip:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
		t:SetSize(i * 5, 1)
		t:SetPoint("BOTTOMRIGHT", 0, (i - 1) * 5)
	end
	grip:SetScript("OnMouseDown", function(self)
		local x = GetCursorPosition()
		self.startX, self.startScale = x, w:GetScale()
		self.startW = w:GetWidth() * w:GetEffectiveScale()
		self:SetScript("OnUpdate", function()
			local cx = GetCursorPosition()
			local scale = self.startScale * (self.startW + (cx - self.startX)) / self.startW
			scale = math.max(0.6, math.min(1.8, scale))
			w:SetScale(scale)
		end)
	end)
	grip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		saved.scale = math.floor(w:GetScale() * 100 + 0.5) / 100
		saved.point = SUI.CalculatePoint(w)
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Drag to resize")
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	Flat(w, BRAND.bg[1], BRAND.bg[2], BRAND.bg[3], 0.97)
	SUI.CreateBackdrop(w, 0)
	table.insert(UISpecialFrames, "StinkieUI_MatchHistory")

	local band = CreateFrame("Frame", nil, w)
	band:SetPoint("TOPLEFT"); band:SetPoint("TOPRIGHT"); band:SetHeight(HEAD_H)
	Flat(band, BRAND.plumDark[1], BRAND.plumDark[2], BRAND.plumDark[3], 1)
	local logo = band:CreateTexture(nil, "ARTWORK")
	logo:SetSize(HEAD_H - 10, HEAD_H - 10)
	logo:SetPoint("LEFT", 8, 0)
	logo:SetTexture(SUI.MEDIA.logo, "CLAMP", "CLAMP", "TRILINEAR")
	local title = Label(band, "MATCH |cff" .. SUI.ACCENT_HEX .. "HISTORY|r", 22, BRAND.cream)
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	w.tabMatches = FlatButton(band, "Matches", 110, function() view.tab = "matches"; w.detail:Hide(); Refresh() end)
	w.tabMatches:SetPoint("LEFT", title, "RIGHT", 30, 0)
	w.tabStats = FlatButton(band, "Match Stats", 110, function() view.tab = "stats"; Refresh() end)
	w.tabStats:SetPoint("LEFT", w.tabMatches, "RIGHT", 6, 0)
	local close = FlatButton(band, "x", 22, function() w:Hide() end)
	close:SetPoint("TOPRIGHT", -10, -10)
	-- no delete buttons (an accidental click can't lose history); importing Rated Tracker data is
	-- on the Stinkie UI options page (PvP > Match History)
	w.loadAll = FlatButton(band, "Load all", 80, function()
		D.loadAll = true
		D.summaries = nil
		D.BuildSummaries()
		Refresh()
	end)
	w.loadAll:SetPoint("RIGHT", close, "LEFT", -8, 0)
	w.loadAll:Hide()
	w.count = Text(band, 12, "RIGHT", { 0.78, 0.66, 0.70 })
	w.count:SetPoint("RIGHT", w.loadAll, "LEFT", -10, 0)

	-- filters
	local bar = CreateFrame("Frame", nil, w)
	bar:SetPoint("TOPLEFT", 12, -(HEAD_H + 8))
	bar:SetPoint("TOPRIGHT", -12, -(HEAD_H + 8))
	bar:SetHeight(24)
	w.dropdowns = {}
	local function add(dd, x)
		dd:SetPoint("LEFT", bar, "LEFT", x, 0)
		table.insert(w.dropdowns, dd)
	end
	add(Dropdown(bar, 160, BRACKETS, function() return filters.bracket end, function(v) filters.bracket = v; view.offset = 0; Refresh() end), 0)
	add(Dropdown(bar, 170, CharItems, function() return filters.char end, function(v) filters.char = v; view.offset = 0; Refresh() end), 166)
	add(Dropdown(bar, 150, SpecItems, function() return filters.spec end, function(v) filters.spec = v; view.offset = 0; Refresh() end), 342)
	add(Dropdown(bar, 110, SeasonItems, function() return filters.season end, function(v) filters.season = v; view.offset = 0; Refresh() end), 498)
	add(Dropdown(bar, 110, { { "all", "All time" }, { "30", "Last 30 days" }, { "7", "Last 7 days" }, { "today", "Today" } },
		function() return filters.period end, function(v) filters.period = v; view.offset = 0; Refresh() end), 614)
	add(Dropdown(bar, 90, { { nil, "All results" }, { "W", "Wins" }, { "L", "Losses" } },
		function() return filters.result end, function(v) filters.result = v; view.offset = 0; Refresh() end), 730)
	local search = W.EditBox(bar, 160)
	w.search = search
	search:SetPoint("LEFT", bar, "LEFT", 826, 0)
	search:SetJustifyH("LEFT")
	local hint = Text(search, 12, "LEFT", { 0.5, 0.5, 0.5 })
	hint:SetPoint("LEFT", 6, 0)
	hint:SetText("Search: map, player, spec, win...")
	search:SetScript("OnMouseDown", function(self) self:SetFocus() end)
	search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	search:SetScript("OnTextChanged", function(self)
		filters.search = self:GetText()
		hint:SetShown(filters.search == "")
		view.offset = 0
		Refresh()
	end)

	local body = CreateFrame("Frame", nil, w)
	body:SetPoint("TOPLEFT", 12, -(HEAD_H + 40))
	body:SetPoint("BOTTOMRIGHT", -12, 12)
	w.matches = BuildMatches(body)
	w.detail = BuildDetail(body)
	w.stats = BuildStats(body)
	w:SetScript("OnHide", function()
		-- drop the decoded summaries so the history costs nothing while closed; the next
		-- opening is back to recent matches only
		D.loadAll = nil
		filtered = {}
		D.Release()
	end)
	w:SetScript("OnShow", function()
		if not D.summaries then D.BuildSummaries() end
		Refresh()
	end)
	w:Hide()
	return w
end

function H.Toggle(tab)
	D.Archive()
	D.MergeInbox()
	win = win or CreateWindow()
	if tab then view.tab = tab end
	if win:IsShown() and not tab then win:Hide() return end
	if not D.summaries then D.BuildSummaries() end
	win:Show()
	Refresh()
end

function H.UpdateCount()
	if not win then return end
	local skipped = D.skipped or 0
	local text = string.format("%d matches  ·  %d saved  ·  %.0f KB", #filtered, #D.Archive().records, D.SizeBytes() / 1024)
	if skipped > 0 then text = text .. string.format("  ·  %d older not loaded", skipped) end
	win.count:SetText(text)
	win.loadAll:SetShown(skipped > 0)
end

-- Rated Tracker import with progress in chat; refreshes the window when done
function H.StartImport()
	local lastPct = -1
	local ok, err = H.Import.Run(function(done, total)
		local pct = math.floor(done / total * 4) * 25
		if pct ~= lastPct and pct < 100 then
			lastPct = pct
			SUI:Print(string.format("Importing Rated Tracker history: %d / %d", done, total))
		end
	end, function(report)
		SUI:Print(H.Import.ReportText(report))
		D.BuildSummaries()
		if win and win:IsShown() then Refresh() end
	end)
	if not ok then SUI:Print(err) end
	return ok
end

-- new matches while loaded go straight into the archive
SUI.MatchRecorder.receiver = function(line, statNames)
	D.Add(line, statNames)
	if D.summaries then
		local index = #D.Archive().records
		local m = D.Get(index)
		if m then table.insert(D.summaries, 1, D.Summarize(m, index)) end
		Refresh()
	end
end
