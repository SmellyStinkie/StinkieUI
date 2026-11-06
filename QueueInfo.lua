-- StinkieUI: Queue Time & MMR. While you're queued for PvP, one row per queue: the bracket, how
-- long you've waited, Blizzard's estimated wait, and your MMR in that bracket. The game doesn't
-- tell addons your MMR outside a match, so it's the MMR after your last match in that bracket on
-- this character (saved by Match History, including imported Rated Tracker matches).
-- Updates once a second, only while a queue is up. Hidden inside arenas and battlegrounds.
--
-- Queue time for Match History: Blizzard's "time waited" keeps counting while you sit in another
-- match (your Blitz queue runs on while you play a Shuffle). We count only the time you were
-- waiting outside a PvP instance, per bracket, and hand it to the match when it is saved.
-- Kept in StinkieUIDB.queueTrack (epoch seconds) so it survives /reload.
local _, ns = ...

local Q = {}
ns.QueueInfo = Q

local issecret = ns.issecret
local function readable(v) return v ~= nil and not issecret(v) end
local function cfg() return ns.db.queueInfo end

local LABEL = { ["2v2"] = "2v2", ["3v3"] = "3v3", shuffle = "Solo Shuffle", blitz = "Blitz", rbg = "Rated BG",
	skirmish = "Skirmish", bg = "Battleground", brawl = "Brawl" }

-- GetBattlefieldStatus values -> our bracket key (nil = not shown)
function Q.Bracket(queueType, teamSize, registered, name)
	local qt = readable(queueType) and tostring(queueType):upper() or ""
	local n = readable(name) and tostring(name):lower() or ""
	if qt:find("SHUFFLE") or n:find("shuffle") then return "shuffle" end
	if qt:find("SOLORBG") or n:find("blitz") then return "blitz" end
	if qt == "ARENASKIRMISH" or n:find("skirmish") then return "skirmish" end
	if qt == "ARENA" then
		if teamSize == 2 then return "2v2" end
		if teamSize == 3 then return "3v3" end
		return registered and "3v3" or "skirmish"
	end
	if qt == "BATTLEGROUND" then return registered and "rbg" or "bg" end
	if qt:find("BRAWL") then return "brawl" end
	return nil
end

local function Clock(s)
	if not s or s < 0 then return "-" end
	s = math.floor(s + 0.5)
	if s >= 3600 then return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60) end
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
Q.Clock = Clock

local PER_SPEC = { shuffle = true, blitz = true }

local function CurrentSpec()
	local id
	pcall(function()
		local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
		local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
		local idx = getSpec and getSpec()
		id = idx and getInfo(idx) or nil
	end)
	return id
end

Q.CurrentSpec = CurrentSpec

-- the spec you're queued as (Blizzard assigns one per Shuffle / Blitz queue); else your current spec
function Q.QueuedSpec(index)
	local id
	if C_PvP and C_PvP.GetAssignedSpecForBattlefieldQueue then
		local ok, v = pcall(C_PvP.GetAssignedSpecForBattlefieldQueue, index)
		if ok and readable(v) and type(v) == "number" and v > 0 then id = v end
	end
	return id or CurrentSpec()
end

function Q.SpecInfo(id)
	if not (id and GetSpecializationInfoByID) then return nil end
	local ok, _, name, _, icon = pcall(GetSpecializationInfoByID, id)
	if ok and readable(name) then return name, icon end
	return nil
end

-- your last match in this bracket (for Solo Shuffle and Blitz: with the queued / current spec).
-- For those, a different spec's MMR is never shown: each spec has its own.
function Q.LastMMR(bracket, spec)
	local store = StinkieUIDB and StinkieUIDB.lastMMR
	local mine = store and store[ns.MatchRecorder.MyChar()]
	if not mine then return nil end
	if PER_SPEC[bracket] then
		spec = spec or CurrentSpec()
		if spec then
			if mine[bracket .. ":" .. spec] then return mine[bracket .. ":" .. spec] end
			-- older records without a spec are still a fair guess; another spec's are not
			local any = mine[bracket]
			if any and (any.spec == nil or any.spec == spec) then return any end
			return nil
		end
	end
	return mine[bracket]
end

-- in an arena or battleground (or its loading screen into one)
function Q.InPvP()
	local _, kind = IsInInstance()
	if kind == "arena" or kind == "pvp" then return true end
	return (C_PvP and C_PvP.IsActiveBattlefield and C_PvP.IsActiveBattlefield()) and true or false
end

---------------------------------------------------------------------------
-- Queue pop volume
---------------------------------------------------------------------------
-- The game has no volume for one sound, and an addon can't turn Blizzard's sound up or down. So
-- the master volume moves to the chosen level for as long as the sound lasts, then goes back. The
-- old volume is kept in StinkieUIDB, so a /reload or logout in those seconds still restores it.
Q.POP_SECS = 3
local MASTER = "Sound_MasterVolume"
local popToken = 0
local popSeen = {}

function Q.RestoreVolume()
	local was = StinkieUIDB and StinkieUIDB.popVolumeWas
	if not was then return end
	StinkieUIDB.popVolumeWas = nil
	pcall(C_CVar.SetCVar, MASTER, was)
end

function Q.PopVolume()
	if not StinkieUIDB then return end
	if not StinkieUIDB.popVolumeWas then
		local cur = C_CVar.GetCVar(MASTER)
		if not tonumber(cur) then return end
		StinkieUIDB.popVolumeWas = cur
	end
	if not pcall(C_CVar.SetCVar, MASTER, tostring(cfg().popVolume)) then return Q.RestoreVolume() end
	popToken = popToken + 1
	local token = popToken
	C_Timer.After(Q.POP_SECS, function()
		if token == popToken then Q.RestoreVolume() end
	end)
end

-- the options button: hear the sound at the chosen level
function Q.TestPopSound()
	Q.PopVolume()
	PlaySound(SOUNDKIT.PVP_THROUGH_QUEUE, "Master")
end

---------------------------------------------------------------------------
-- Queue time tracking (time spent waiting outside other matches)
---------------------------------------------------------------------------
local function TrackStore()
	if not StinkieUIDB then return nil end
	StinkieUIDB.queueTrack = StinkieUIDB.queueTrack or {}
	local key = ns.MatchRecorder.MyChar()
	local t = StinkieUIDB.queueTrack[key]
	if not t then t = { live = {}, popped = {} }; StinkieUIDB.queueTrack[key] = t end
	return t
end

function Q.Track(now)
	local store = TrackStore()
	if not store then return end
	now = now or time()
	local busy = Q.InPvP()
	local seen = {}
	local max = GetMaxBattlefieldID and GetMaxBattlefieldID() or 0
	for i = 1, max do
		local status, name, teamSize, registered, suspended, queueType = GetBattlefieldStatus(i)
		-- once per pop, whatever the queue: Blizzard's sound plays for all of them
		local popped = status == "confirm"
		if popped and not popSeen[i] and cfg().popSound then Q.PopVolume() end
		popSeen[i] = popped or nil
		local bracket = (status == "queued" or status == "confirm") and Q.Bracket(queueType, teamSize, registered, name)
		if bracket then
			seen[bracket] = true
			local q = store.live[bracket]
			if status == "queued" then
				if not q then
					-- new queue; if we missed its start (addon just installed), take Blizzard's number
					local waited = GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(i)
					waited = (readable(waited) and waited > 0) and math.floor(waited / 1000) or 0
					q = { idle = (waited > 5 and not busy) and waited or 0 }
					store.live[bracket] = q
				end
				local paused = busy or (readable(suspended) and suspended)
				if paused and q.since then
					q.idle, q.since = q.idle + math.max(0, now - q.since), nil
				elseif not paused and not q.since then
					q.since = now
				end
			elseif q then -- popped
				store.popped[bracket] = { secs = q.idle + (q.since and math.max(0, now - q.since) or 0), t = now }
				store.live[bracket] = nil
			end
		end
	end
	for bracket in pairs(store.live) do
		if not seen[bracket] then store.live[bracket] = nil end -- left the queue
	end
	for i in pairs(popSeen) do
		if i > max then popSeen[i] = nil end -- the list shrinks when a queue ends
	end
end

-- seconds queued for the match being saved (once); nil if we didn't see it pop in the last 3 hours
function Q.TakeQueue(bracket)
	local store = TrackStore()
	if not (store and bracket) then return nil end
	local key = tostring(bracket):gsub("%-u$", "")
	local p = store.popped[key]
	if not p then return nil end
	store.popped[key] = nil
	if time() - (p.t or 0) > 3 * 3600 then return nil end
	return p.secs
end

-- "+73" in green / "-40" in red
function Q.DeltaText(d)
	if not d or d == 0 then return d == 0 and " |cffaaaaaa+0|r" or "" end
	if d > 0 then return string.format(" |cff55ff55+%d|r", d) end
	return string.format(" |cffff5555%d|r", d)
end

-- current queues: { { bracket, label, waited, estimate, status } }
function Q.Read()
	local out = {}
	local max = GetMaxBattlefieldID and GetMaxBattlefieldID() or 0
	for i = 1, max do
		local status, name, teamSize, registered, suspended, queueType = GetBattlefieldStatus(i)
		if status == "queued" or status == "confirm" then
			local bracket = Q.Bracket(queueType, teamSize, registered, name)
			local waited = GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(i)
			local est = GetBattlefieldEstimatedWaitTime and GetBattlefieldEstimatedWaitTime(i)
			out[#out + 1] = {
				bracket = bracket,
				label = (bracket and LABEL[bracket]) or (readable(name) and name) or "Queue",
				waited = readable(waited) and waited / 1000 or nil,
				estimate = (readable(est) and est > 0) and est / 1000 or nil,
				status = status, suspended = suspended,
				spec = Q.QueuedSpec(i),
			}
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local rows = {}

local function CreateRow(i)
	local r = CreateFrame("Frame", nil, Q.holder)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.label = ns.CreateText(r, 14, "LEFT")
	r.cells = {}
	for k = 1, 4 do r.cells[k] = ns.CreateText(r, 14, "LEFT") end -- time, estimate, MMR, rating
	rows[i] = r
	return r
end

local function HeaderRow()
	if Q.header then return Q.header end
	local r = CreateFrame("Frame", nil, Q.holder)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.text = ns.CreateText(r, 14, "LEFT")
	Q.header = r
	return r
end

function Q:Layout()
	local c = cfg()
	local h = Q.holder
	h:SetScale((c.scale or 1) * ns.db.scale)
	ns:ApplyPoint(h, c.point)
	h.bg:SetColorTexture(c.bgColor[1], c.bgColor[2], c.bgColor[3], c.bgAlpha)
	h.bg:SetShown(c.background)
	if h.SUIBorder then
		for _, e in ipairs(h.SUIBorder.edges) do e:SetShown(c.background and c.border) end
	end
	local icon = c.specIcon and (c.height - 4) or 0
	local top = 4
	local hr = HeaderRow()
	hr:SetSize(c.width, c.height)
	hr:ClearAllPoints()
	hr:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -top)
	hr.icon:SetSize(c.height - 4, c.height - 4)
	hr.icon:ClearAllPoints()
	hr.icon:SetPoint("LEFT", 6, 0)
	hr.text:ClearAllPoints()
	hr.text:SetPoint("LEFT", hr.icon, "RIGHT", 5, 0)
	ns.ApplyText(hr.text, c.labelStyle)
	if c.header then top = top + c.height + c.spacing end
	for i, r in ipairs(rows) do
		r:SetSize(c.width, c.height)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -top - (i - 1) * (c.height + c.spacing))
		r.icon:SetSize(math.max(icon, 1), math.max(icon, 1))
		r.icon:ClearAllPoints()
		r.icon:SetPoint("LEFT", 6, 0)
		r.label:ClearAllPoints()
		if icon > 0 then r.label:SetPoint("LEFT", r.icon, "RIGHT", 4, 0) else r.label:SetPoint("LEFT", 6, 0) end
		ns.ApplyText(r.label, c.labelStyle)
		-- equal columns: bracket | time in queue | estimate | MMR (| rating)
		local cols = Q.Columns(c)
		local w = c.width / (#cols + 1)
		r.label:SetWidth(math.max(10, w - 8 - (icon > 0 and icon + 4 or 0)))
		r.label:SetWordWrap(false)
		for k, fs in ipairs(r.cells) do
			ns.ApplyText(fs, c.textStyle)
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", r, "LEFT", math.floor(w * k) + 4, 0)
			fs:SetWidth(math.max(10, w - 6))
			fs:SetWordWrap(false)
			fs:SetShown(k <= #cols)
		end
	end
end

-- which value columns are on, in order
function Q.Columns(c)
	local cols = { "time" }
	if c.estimate then cols[#cols + 1] = "est" end
	if c.mmr then cols[#cols + 1] = "mmr" end
	if c.rating then cols[#cols + 1] = "cr" end
	return cols
end

-- brackets with MMR / rating; the rest show N/A
Q.RATED = { ["2v2"] = true, ["3v3"] = true, shuffle = true, blitz = true, rbg = true }

function Q.MMRText(q, last)
	if not (q.bracket and Q.RATED[q.bracket]) then return "|cffaaaaaaMMR N/A|r" end
	if last and last.mmr then
		-- Blitz and Shuffle matches saved before 0.42.2 all have a 0 the game gave us, not a real one
		local delta = last.delta
		if PER_SPEC[q.bracket] and delta == 0 then delta = nil end
		return "MMR " .. tostring(last.mmr) .. ((cfg().mmrChange and Q.DeltaText(delta)) or "")
	end
	-- a saved match there but the game gave no MMR for it: not trackable
	if last then return "|cffaaaaaaMMR N/A|r" end
	return "|cffaaaaaaMMR unknown|r" -- no match in this bracket / spec yet
end

local function Render(list)
	local c = cfg()
	local hr = HeaderRow()
	local firstSpec = list[1] and list[1].spec
	local sname, sicon = Q.SpecInfo(firstSpec)
	local showHeader = c.header and #list > 0 and sname ~= nil
	if showHeader then
		hr.icon:SetTexture(sicon)
		hr.text:SetText("Queued as " .. sname)
	end
	hr:SetShown(showHeader and true or false)
	for i, q in ipairs(list) do
		local r = rows[i]
		if not r then r = CreateRow(i); Q:Layout() end
		local _, icon = Q.SpecInfo(q.spec)
		r.icon:SetTexture(icon)
		r.icon:SetShown(c.specIcon and icon ~= nil)
		r.label:SetText(q.label)
		local values = {}
		if q.status == "confirm" then
			values.time = "|cff55ff55Ready!|r"
		elseif q.suspended then
			values.time = "paused"
		else
			values.time = Clock(q.waited)
		end
		values.est = "est " .. (q.estimate and Clock(q.estimate) or "-")
		local last = q.mmrData or (q.bracket and Q.RATED[q.bracket] and Q.LastMMR(q.bracket, q.spec)) or nil
		values.mmr = Q.MMRText(q, last)
		values.cr = (q.bracket and Q.RATED[q.bracket]) and ("CR " .. ((last and last.rating) and tostring(last.rating) or "-")) or "|cffaaaaaaCR N/A|r"
		local cols = Q.Columns(c)
		for k, fs in ipairs(r.cells) do fs:SetText(cols[k] and values[cols[k]] or "") end
		r:Show()
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
	local h = Q.holder
	local n = #list + (c.header and 1 or 0)
	h:SetSize(c.width, math.max(c.height, n * (c.height + c.spacing) - c.spacing) + 8)
	h:SetShown(#list > 0)
end

local PREVIEW = {
	{ label = "Blitz", waited = 192, estimate = 160, status = "queued", bracket = "blitz", spec = 265, mmrData = { mmr = 2773, rating = 2677, delta = 74 } },
	{ label = "Solo Shuffle", waited = 75, estimate = 420, status = "queued", bracket = "shuffle", spec = 265, mmrData = { mmr = 2795, rating = 2817, delta = -22 } },
	{ label = "3v3", waited = 40, estimate = 300, status = "queued", bracket = "3v3", spec = 265 },
}

function Q:Update()
	if not cfg().enabled then Q.holder:Hide() return end
	if Q.testMode or ns.unlocked then Render(PREVIEW) return end
	if cfg().hideInPvP and Q.InPvP() then Q.holder:Hide(); Q.ticker:Hide() return end
	local ok, list = pcall(Q.Read)
	if not ok then list = {} end
	Render(list)
	Q.ticker:SetShown(#list > 0)
end

function Q:SetTestMode(on)
	Q.testMode = on or nil
	Q:Update()
end

function Q:Init()
	Q.RestoreVolume() -- left over from a /reload or logout while the sound was playing
	local h = CreateFrame("Frame", "StinkieUI_QueueInfo", UIParent)
	h:SetFrameStrata("MEDIUM")
	h.bg = h:CreateTexture(nil, "BACKGROUND")
	h.bg:SetAllPoints()
	ns.CreateBackdrop(h, 0)
	h:Hide()
	Q.holder = h
	ns:RegisterMover("queueInfo", h, "Queue Time & MMR",
		function() return cfg().point end,
		function(p) cfg().point = p end)
	Q.ticker = CreateFrame("Frame")
	local acc = 0
	Q.ticker:SetScript("OnUpdate", function(_, dt)
		acc = acc + dt
		if acc >= 1 then acc = 0; Q:Update() end
	end)
	Q.ticker:Hide()
	local function Track() local ok, err = pcall(Q.Track); if not ok then geterrorhandler()(err) end end
	ns:On("UPDATE_BATTLEFIELD_STATUS", function() Track(); Q:Update() end)
	ns:On("PLAYER_ENTERING_WORLD", function() Track(); Q:Update() end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() Track(); Q:Update() end)
	table.insert(ns.lockCallbacks, function() Q:Update() end)
	Q:Layout()
	Q:Update()
end

function Q:Refresh()
	if not Q.holder then return end
	Q.holder.SUIActive = cfg().enabled and true or false
	Q:Layout()
	Q:Update()
end

ns:RegisterModule("QueueInfo", Q)
