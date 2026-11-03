-- StinkieUI: Queue Time & MMR. While you're queued for PvP, one row per queue: the bracket, how
-- long you've waited, Blizzard's estimated wait, and your MMR in that bracket. The game doesn't
-- tell addons your MMR outside a match, so it's the MMR after your last match in that bracket on
-- this character (saved by Match History, including imported Rated Tracker matches).
-- Updates once a second, only while a queue is up.
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

-- your last match in this bracket (for Solo Shuffle and Blitz: with your current spec)
function Q.LastMMR(bracket)
	local store = StinkieUIDB and StinkieUIDB.lastMMR
	local mine = store and store[ns.MatchRecorder.MyChar()]
	if not mine then return nil end
	if PER_SPEC[bracket] then
		local spec = CurrentSpec()
		if spec and mine[bracket .. ":" .. spec] then return mine[bracket .. ":" .. spec] end
	end
	return mine[bracket]
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
	r.label = ns.CreateText(r, 14, "LEFT")
	r.label:SetPoint("LEFT", 6, 0)
	r.time = ns.CreateText(r, 14, "LEFT")
	r.extra = ns.CreateText(r, 14, "RIGHT")
	r.extra:SetPoint("RIGHT", -6, 0)
	rows[i] = r
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
	for i, r in ipairs(rows) do
		r:SetSize(c.width, c.height)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -4 - (i - 1) * (c.height + c.spacing))
		ns.ApplyText(r.label, c.labelStyle)
		ns.ApplyText(r.time, c.textStyle)
		ns.ApplyText(r.extra, c.textStyle)
		r.time:ClearAllPoints()
		r.time:SetPoint("LEFT", r, "LEFT", math.floor(c.width * 0.36), 0)
	end
end

local function Render(list)
	local c = cfg()
	for i, q in ipairs(list) do
		local r = rows[i]
		if not r then r = CreateRow(i); Q:Layout() end
		r.label:SetText(q.label)
		if q.status == "confirm" then
			r.time:SetText("|cff55ff55Ready!|r")
		elseif q.suspended then
			r.time:SetText("paused")
		else
			r.time:SetText(Clock(q.waited))
		end
		local extra = {}
		if c.estimate then extra[#extra + 1] = "est " .. (q.estimate and Clock(q.estimate) or "-") end
		if (c.mmr or c.rating) and q.bracket then
			local last = q.mmrData or Q.LastMMR(q.bracket)
			if c.mmr then
				extra[#extra + 1] = "MMR " .. ((last and last.mmr) and tostring(last.mmr) or "-")
					.. ((c.mmrChange and last) and Q.DeltaText(last.delta) or "")
			end
			if c.rating then extra[#extra + 1] = "CR " .. ((last and last.rating) and tostring(last.rating) or "-") end
		end
		r.extra:SetText(table.concat(extra, "   "))
		r:Show()
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
	local h = Q.holder
	h:SetSize(c.width, math.max(c.height, #list * (c.height + c.spacing) - c.spacing) + 8)
	h:SetShown(#list > 0)
end

local PREVIEW = {
	{ label = "Blitz", waited = 192, estimate = 160, status = "queued", bracket = "blitz", mmrData = { mmr = 2773, rating = 2677, delta = 74 } },
	{ label = "Solo Shuffle", waited = 75, estimate = 420, status = "queued", bracket = "shuffle", mmrData = { mmr = 2795, rating = 2817, delta = -22 } },
}

function Q:Update()
	if not cfg().enabled then Q.holder:Hide() return end
	if Q.testMode or ns.unlocked then Render(PREVIEW) return end
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
	ns:On("UPDATE_BATTLEFIELD_STATUS", function() Q:Update() end)
	ns:On("PLAYER_ENTERING_WORLD", function() Q:Update() end)
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
