-- StinkieUI: BG Timers. Countdown bars for assaulted bases, the predicted winner of resource
-- battlegrounds, and the next resurrection wave while you're dead.
--
-- Midnight hides battleground chat messages from addons during a match, so base timers come from
-- the map: a base's map icon changes when it's assaulted, and again when it turns or is defended.
-- The time a base takes to turn isn't exposed, so it's set per map (BG Timers page). The winner
-- prediction measures each team's score rate from the score bar, so it needs no per-map data.
-- Blitz on Arathi Basin and Deepwind Gorge runs bases on a fixed cycle instead: 30 seconds to turn,
-- 45 seconds locked behind a shield, 5 seconds shut, then open again. Those phases run on the clock,
-- because the shield and reset have no icon we can name; icon changes only start or correct them.
-- Runs only inside battlegrounds.
local _, ns = ...

local T = {}
ns.BGTimers = T

local issecret = ns.issecret
local function readable(v) return v ~= nil and not issecret(v) end
local function cfg() return ns.db.bgTimers end

---------------------------------------------------------------------------
-- Pure logic (testable outside the game)
---------------------------------------------------------------------------
local L = {}
T.Logic = L

-- "Arathi Basin = 60" lines -> { ["arathi basin"] = 60 }
function L.ParseDurations(list)
	local out = {}
	for _, line in ipairs(list or {}) do
		local name, secs = tostring(line):match("^%s*(.-)%s*=%s*(%d+%.?%d*)%s*$")
		if name and name ~= "" then out[name:lower()] = tonumber(secs) end
	end
	return out
end

-- Words in Blizzard's map icon names, when the icon is an atlas
function L.AtlasState(atlas)
	if type(atlas) ~= "string" or atlas == "" then return nil end
	local a = atlas:lower()
	local team = a:find("alliance") and "Alliance" or a:find("horde") and "Horde" or nil
	if a:find("contest") or a:find("assault") or a:find("conflict") then return "CONTESTED", team end
	if team then return "OWNED", team end
	return nil
end

-- A base's map icon changed. node = { timerEnd, recentEnd }. Returns "START", "STOP" or nil.
-- Without readable icon names: a change with no timer running is an assault (start); a change while
-- the timer runs is a defense (stop), unless it's the turn itself (around when the timer ends).
function L.OnNodeChange(node, now, duration, atlas)
	local state, team = L.AtlasState(atlas)
	if state == "CONTESTED" then
		node.timerEnd, node.team = now + duration, team
		return "START"
	elseif state == "OWNED" then
		if node.timerEnd then node.recentEnd = node.timerEnd end
		node.timerEnd = nil
		return "STOP"
	end
	if node.timerEnd then
		if now >= node.timerEnd - 3 then node.recentEnd = node.timerEnd end
		node.timerEnd = nil
		return "STOP"
	end
	if node.recentEnd and math.abs(now - node.recentEnd) < 6 then
		node.recentEnd = nil
		return nil -- the base just turned at the end of its timer
	end
	node.timerEnd, node.team = now + duration, nil
	return "START"
end

-- Blitz base cycle
L.PHASES = {
	assault = { secs = 30, nextPhase = "lock" },
	lock = { secs = 45, nextPhase = "reset" },
	reset = { secs = 5 },
}
local TURN_SLACK = 3 -- seconds either side of a phase ending when an icon change is that ending

function L.IsCycleMap(name)
	if type(name) ~= "string" then return false end
	local n = name:lower()
	return n:find("arathi basin", 1, true) ~= nil or n:find("deepwind gorge", 1, true) ~= nil
end

local function EnterPhase(node, phase, start, team)
	node.phase, node.phaseEnd, node.team = phase, start + L.PHASES[phase].secs, team
end

-- Moves a base on when its phase has run out. Returns true if anything changed.
function L.Advance(node, now)
	local moved = false
	while node.phase and now >= node.phaseEnd do
		moved = true
		local nextPhase = L.PHASES[node.phase].nextPhase
		if nextPhase then
			EnterPhase(node, nextPhase, node.phaseEnd, nextPhase == "lock" and node.team or nil)
		else
			node.recentEnd, node.phase, node.phaseEnd = node.phaseEnd, nil, nil
		end
	end
	return moved
end

-- A base's map icon changed. Returns true if its timer changed.
function L.OnCycleChange(node, now, atlas)
	local state, team = L.AtlasState(atlas)
	if state == "CONTESTED" then
		if node.phase == "assault" and node.team == team then return false end
		EnterPhase(node, "assault", now, team)
		return true
	elseif state == "OWNED" then
		if node.phase == "lock" then return false end
		EnterPhase(node, "lock", now, team)
		return true
	end
	if type(atlas) == "string" and atlas ~= "" then -- a named icon that's neither: back to neutral
		if node.phase ~= "assault" then return false end
		node.phase, node.phaseEnd, node.team = nil, nil, nil
		return true
	end
	-- no readable icon name: go by when it happened
	if node.phase == "assault" then
		if now >= node.phaseEnd - TURN_SLACK then
			EnterPhase(node, "lock", now, node.team)
		else
			EnterPhase(node, "assault", now, nil) -- the other team took the assault over
		end
		return true
	end
	if node.phase then return false end -- nothing can touch a base while it's locked or shut
	if node.recentEnd and math.abs(now - node.recentEnd) <= TURN_SLACK then
		node.recentEnd = nil
		return false -- the base opening again; a real assault takes a 4 second cast after that
	end
	EnterPhase(node, "assault", now, nil)
	return true
end

function L.PhaseLabel(name, phase)
	if phase == "lock" then return name .. " locked" end
	if phase == "reset" then return name .. " opens" end
	return name
end

-- Score samples { t, a, h } (oldest first) -> per-second rates over the window
function L.Rates(samples, now, window)
	window = window or 30
	local newest = samples[#samples]
	if not newest then return nil end
	local oldest
	for i = 1, #samples do
		if now - samples[i].t <= window then oldest = samples[i] break end
	end
	if not oldest or newest.t - oldest.t < 6 then return nil end
	local dt = newest.t - oldest.t
	return (newest.a - oldest.a) / dt, (newest.h - oldest.h) / dt
end

-- Predicted winner from current scores, rates and the score needed to win.
-- Returns winner ("Alliance"/"Horde"), seconds until they win, final loser score; or nil.
function L.Predict(a, h, rateA, rateH, max)
	if not (a and h and max and max > 0) then return nil end
	local tA = (rateA and rateA > 0) and (max - a) / rateA or math.huge
	local tH = (rateH and rateH > 0) and (max - h) / rateH or math.huge
	if tA == math.huge and tH == math.huge then return nil end
	if tA <= tH then
		return "Alliance", math.max(0, tA), math.min(max, h + (rateH or 0) * tA)
	end
	return "Horde", math.max(0, tH), math.min(max, a + (rateA or 0) * tH)
end

function L.Clock(s)
	s = math.max(0, math.floor(s + 0.5))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local bars = {}
local active = {} -- list of timers { key, label, endTime, total, team, kind }

local function TeamColor(team)
	local c = cfg()
	if team == "Alliance" then return c.allianceColor end
	if team == "Horde" then return c.hordeColor end
	return c.neutralColor
end

local function CreateTimerBar(i)
	local b = CreateFrame("StatusBar", nil, T.holder)
	b:SetStatusBarTexture(ns.TEXTURE)
	b:SetMinMaxValues(0, 1)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	ns.IconBorder(b)
	b.label = ns.CreateText(b, 12, "LEFT")
	b.time = ns.CreateText(b, 12, "RIGHT")
	b.time:SetPoint("RIGHT", -4, 0)
	b.label:SetPoint("LEFT", 4, 0)
	b.label:SetPoint("RIGHT", b.time, "LEFT", -4, 0)
	bars[i] = b
	return b
end

function T:Layout()
	local c = cfg()
	local h = T.holder
	h:SetScale(ns.db.scale)
	h:SetSize(c.width, c.height)
	ns:ApplyPoint(h, c.point)
	for i, b in ipairs(bars) do
		b:SetSize(c.width, c.height)
		b.bg:SetColorTexture(0.04, 0.04, 0.05, c.bgAlpha)
		ns.ApplyText(b.label, c.textStyle)
		ns.ApplyText(b.time, c.textStyle)
		b:ClearAllPoints()
		local step = (i - 1) * (c.height + c.spacing)
		if c.growth == "UP" then b:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, step)
		else b:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -step) end
	end
end

local function Render(now)
	table.sort(active, function(x, y)
		if x.kind ~= y.kind then return x.kind == "win" end -- the prediction on top
		return (x.endTime or 0) < (y.endTime or 0)
	end)
	for i, t in ipairs(active) do
		local b = bars[i]
		if not b then
			b = CreateTimerBar(i)
			T:Layout()
		end
		local left = (t.endTime or now) - now
		local col = TeamColor(t.team)
		b:SetStatusBarColor(col[1], col[2], col[3], 0.85)
		b:SetValue((t.total and t.total > 0) and math.max(0, math.min(1, left / t.total)) or 1)
		b.label:SetText(t.label)
		b.time:SetText(t.timeText or L.Clock(left))
		b:Show()
	end
	for i = #active + 1, #bars do bars[i]:Hide() end
	T.holder:SetShown(#active > 0)
end

local function SetTimer(key, kind, label, endTime, total, team, timeText)
	for _, t in ipairs(active) do
		if t.key == key then
			t.label, t.endTime, t.total, t.team, t.timeText = label, endTime, total, team, timeText
			return
		end
	end
	table.insert(active, { key = key, kind = kind, label = label, endTime = endTime, total = total, team = team, timeText = timeText })
end

local function ClearTimer(key)
	for i = #active, 1, -1 do
		if active[i].key == key then table.remove(active, i) end
	end
end

---------------------------------------------------------------------------
-- Bases (map icons)
---------------------------------------------------------------------------
local nodes = {} -- poiID -> { sig, timerEnd, recentEnd, team, name }
local mapID, duration

local function IsIgnoredPOI(name)
	if not readable(name) or name == "" then return true end
	local n = name:lower()
	return n:find("graveyard") ~= nil
end

local function MapDuration()
	local list = L.ParseDurations(cfg().durations)
	local instName = GetInstanceInfo()
	if readable(instName) and list[instName:lower()] then return list[instName:lower()] end
	local info = mapID and C_Map.GetMapInfo(mapID)
	if info and readable(info.name) and list[info.name:lower()] then return list[info.name:lower()] end
	return nil
end

-- Blitz can take a moment after loading in to report itself, so this is asked each time
function T.UsesCycle()
	if ns.CombatLog.MatchType() ~= "blitz" then return false end
	local instName = GetInstanceInfo()
	if readable(instName) and L.IsCycleMap(instName) then return true end
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info ~= nil and readable(info.name) and L.IsCycleMap(info.name)
end

local function SyncCycleTimer(id, node)
	if node.phase then
		SetTimer("node" .. id, "node", L.PhaseLabel(node.name, node.phase), node.phaseEnd, L.PHASES[node.phase].secs, node.team)
	else
		ClearTimer("node" .. id)
	end
end

function T:ScanNodes(first)
	local cycle = T.UsesCycle()
	if not (cfg().nodes and mapID and (cycle or (duration and duration > 0))) then return end
	local ids = C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}
	local now = GetTime()
	local seen = {}
	for _, id in ipairs(ids) do
		local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
		if info and not IsIgnoredPOI(info.name) then
			seen[id] = true
			local atlas = readable(info.atlasName) and info.atlasName or nil
			local tex = readable(info.textureIndex) and info.textureIndex or nil
			local sig = tostring(atlas) .. "|" .. tostring(tex)
			local node = nodes[id]
			if not node then
				nodes[id] = { sig = sig, name = info.name }
				-- joining mid-match: an icon already showing "contested" gets a timer of unknown length
				local state, team = L.AtlasState(atlas)
				if state == "CONTESTED" and not first then
					nodes[id].timerEnd, nodes[id].team = now + duration, team
				end
			elseif node.sig ~= sig and cycle then
				node.sig = sig
				if L.OnCycleChange(node, now, atlas) then SyncCycleTimer(id, node) end
			elseif node.sig ~= sig then
				node.sig = sig
				local result = L.OnNodeChange(node, now, duration, atlas)
				if result == "START" then
					SetTimer("node" .. id, "node", node.name, node.timerEnd, duration, node.team)
				elseif result == "STOP" then
					ClearTimer("node" .. id)
				end
			end
		end
	end
	for id in pairs(nodes) do
		if not seen[id] then nodes[id] = nil; ClearTimer("node" .. id) end
	end
end

---------------------------------------------------------------------------
-- Winner prediction (score bar)
---------------------------------------------------------------------------
local samples = {}

local function ReadScore()
	local W = C_UIWidgetManager
	if not (W and W.GetTopCenterWidgetSetID and W.GetAllWidgetsBySetID) then return nil end
	local setID = W.GetTopCenterWidgetSetID()
	if not setID then return nil end
	local DOUBLE = Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.DoubleStatusBar
	for _, w in ipairs(W.GetAllWidgetsBySetID(setID) or {}) do
		if w.widgetType == DOUBLE then
			local info = W.GetDoubleStatusBarWidgetVisualizationInfo(w.widgetID)
			if info and readable(info.leftBarValue) and readable(info.rightBarValue) and readable(info.leftBarMax)
				and info.leftBarMax > 0 and info.leftBarMax == info.rightBarMax then
				return info.leftBarValue, info.rightBarValue, info.leftBarMax
			end
		end
	end
	return nil
end

function T:UpdatePrediction(now)
	if not cfg().win then ClearTimer("win") return end
	local a, h, max = ReadScore()
	if not a then ClearTimer("win") return end
	local last = samples[#samples]
	if not last or now - last.t >= 1 then table.insert(samples, { t = now, a = a, h = h }) end
	while #samples > 40 do table.remove(samples, 1) end
	local rA, rH = L.Rates(samples, now, 30)
	local winner, secs, loserFinal = L.Predict(a, h, rA, rH, max)
	if not winner or secs > 1800 then ClearTimer("win") return end
	local text = string.format("%s wins %d - %d", winner == "Alliance" and (FACTION_ALLIANCE or "Alliance") or (FACTION_HORDE or "Horde"),
		max, math.floor(loserFinal + 0.5))
	SetTimer("win", "win", text, now + secs, math.max(secs, 300), winner)
end

---------------------------------------------------------------------------
-- Resurrection wave
---------------------------------------------------------------------------
function T:UpdateRespawn(now)
	if not (cfg().respawn and UnitIsDeadOrGhost("player")) then ClearTimer("res") return end
	local secs = GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()
	if readable(secs) and secs > 0 then
		SetTimer("res", "res", RESURRECT or "Resurrection", now + secs, 30, nil)
	else
		ClearTimer("res")
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local accum, slow = 0, 0
local function OnUpdate(_, elapsed)
	accum, slow = accum + elapsed, slow + elapsed
	if accum < 0.1 then return end
	accum = 0
	local now = GetTime()
	if slow >= 1 then
		slow = 0
		local ok, err = pcall(function()
			T:ScanNodes()
			T:UpdatePrediction(now)
			T:UpdateRespawn(now)
		end)
		if not ok and not T.errored then T.errored = true; geterrorhandler()(err) end
	end
	-- Blitz bases move through their phases on the clock
	for id, node in pairs(nodes) do
		if node.phase and L.Advance(node, now) then SyncCycleTimer(id, node) end
	end
	-- drop finished base timers
	for i = #active, 1, -1 do
		local t = active[i]
		if t.kind == "node" and t.endTime and t.endTime < now - 1 then table.remove(active, i) end
	end
	if not T.testMode then Render(now) end
end

function T:UpdateActive()
	local c = cfg()
	local _, t = IsInInstance()
	T.inBG = (t == "pvp")
	wipe(nodes); wipe(samples); wipe(active)
	T.errored = nil
	mapID = T.inBG and C_Map.GetBestMapForUnit("player") or nil
	duration = mapID and MapDuration() or nil
	local run = c.enabled and T.inBG
	T.ticker:SetShown(run and true or false)
	if run then
		pcall(T.ScanNodes, T, true)
	elseif not (T.testMode or ns.unlocked) then
		T.holder:Hide()
	end
end

local PREVIEW = {
	{ key = "w", kind = "win", label = "Horde wins 1500 - 1240", left = 151, total = 300, team = "Horde" },
	{ key = "a", kind = "node", label = "Stables", left = 23, total = 60, team = "Alliance" },
	{ key = "b", kind = "node", label = "Blacksmith", left = 47, total = 60, team = "Horde" },
	{ key = "r", kind = "res", label = "Resurrection", left = 12, total = 30 },
}

function T:ShowPreview()
	local now = GetTime()
	wipe(active)
	for _, p in ipairs(PREVIEW) do
		table.insert(active, { key = p.key, kind = p.kind, label = p.label, endTime = now + p.left, total = p.total, team = p.team })
	end
	Render(now)
	T.holder:Show()
	T.previewing = true
end

function T:SetTestMode(on)
	T.testMode = on or nil
	T:Refresh()
end

function T:Init()
	T.holder = CreateFrame("Frame", "StinkieUI_BGTimers", UIParent)
	T.holder:SetFrameStrata("MEDIUM")
	ns:RegisterMover("bgTimers", T.holder, "BG Timers",
		function() return cfg().point end,
		function(p) cfg().point = p end)
	T.ticker = CreateFrame("Frame")
	T.ticker:SetScript("OnUpdate", ns.Timed("BG Timers", OnUpdate))
	T.ticker:Hide()
	ns:On("PLAYER_ENTERING_WORLD", function() T:UpdateActive() end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() T:UpdateActive() end)
	ns:On("AREA_POIS_UPDATED", function()
		if T.inBG and cfg().enabled then pcall(T.ScanNodes, T) end
	end)
	table.insert(ns.lockCallbacks, function() T:Refresh() end)
	T:Layout()
	T:UpdateActive()
end

function T:Refresh()
	if not T.holder then return end
	T.holder.SUIActive = cfg().enabled and true or false
	T:Layout()
	local c = cfg()
	if c.enabled and (T.testMode or ns.unlocked) then
		T:ShowPreview()
		return
	end
	if T.previewing then wipe(active); T.previewing = nil end
	T.ticker:SetShown(c.enabled and T.inBG and true or false)
	if c.enabled and T.inBG then
		if mapID then duration = MapDuration() end
		Render(GetTime())
	else
		wipe(active)
		T.holder:Hide()
	end
end

-- /stinkie timers: what the map reports, for adding maps and fixing timers
function T.Debug()
	local m = C_Map.GetBestMapForUnit("player")
	local info = m and C_Map.GetMapInfo(m)
	ns:Print(string.format("BG Timers: map %s (%s), instance %s, base timer %s s", tostring(m), tostring(info and info.name),
		tostring((GetInstanceInfo())), tostring(duration)))
	for _, id in ipairs(m and C_AreaPoiInfo.GetAreaPOIForMap(m) or {}) do
		local p = C_AreaPoiInfo.GetAreaPOIInfo(m, id)
		if p then print(string.format("  %d %s  atlas=%s  texture=%s", id, tostring(p.name), tostring(p.atlasName), tostring(p.textureIndex))) end
	end
	print("  Blitz base cycle: " .. tostring(T.UsesCycle()))
	local a, h, max = ReadScore()
	print("  score: " .. tostring(a) .. " / " .. tostring(h) .. " of " .. tostring(max))
end

ns:RegisterModule("BGTimers", T)
