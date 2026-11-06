-- StinkieUI: Flag Cap Indicator (capture-the-flag battlegrounds: Warsong Gulch, Twin Peaks).
-- For each flag that's out: who carries it, how many yards they are from their cap spot, and
-- ON CAP / NOT ON CAP / DROPPED, so the team knows when a return wins the point.
--
-- Data: C_PvP.GetBattlefieldFlagPosition (map position of each flag that isn't at its base; not a
-- secret value) and C_Map.GetMapWorldSize (map size in yards). The game doesn't give the two bases,
-- so they're listed per map. A flag caps at the base it was NOT picked up from, which is worked out
-- from where it first appears, never from its team. On a map not listed the spots are learned from
-- pickups, kept per map (account-wide) and refined on caps.
-- Carrier names come from the arena1..5 units (enemy carriers, which the game exposes in
-- battlegrounds) and from your raid's flag-carrier classification, when those are readable.
-- Polls 5 times a second only while a flag map is active; does nothing anywhere else.
local _, ns = ...

local FC = {}
ns.FlagCap = FC

local issecret = ns.issecret
local function readable(v) return v ~= nil and not issecret(v) end
local function cfg() return ns.db.flagCap end

local POLL = 0.2
local IDLE_POLL = 1.0
-- Instance IDs of the two-flag maps, used only if the flag textures can't be matched to a faction
-- (Warsong Gulch old / current, Twin Peaks).
FC.CTF_INSTANCES = { [489] = true, [2106] = true, [726] = true }
-- texture paths the map uses for the two flags; resolved to file IDs at load
local FLAG_PATHS = {
	Alliance = { [[Interface\WorldStateFrame\AllianceFlag]] },
	Horde = { [[Interface\WorldStateFrame\HordeFlag]] },
}
local TEAM_COLOR = { Alliance = { 0.30, 0.60, 1.00 }, Horde = { 1.00, 0.25, 0.25 } }

-- The two flag rooms of each map, by uiMapID (Warsong Gulch old / current, Twin Peaks)
local WARSONG = { { x = 0.489, y = 0.113 }, { x = 0.530, y = 0.930 } }
FC.BASE_SPOTS = { [92] = WARSONG, [1339] = WARSONG, [206] = { { x = 0.609, y = 0.183 }, { x = 0.484, y = 0.849 } } }
-- a flag appearing further than this from both bases was dropped and picked up again
FC.BASE_RANGE = 50

---------------------------------------------------------------------------
-- Pure logic (no frames): kept separate so it can be tested outside the game
---------------------------------------------------------------------------
local L = {}
FC.Logic = L

-- distance in yards between two map points, given the map size in yards
function L.Yards(x1, y1, x2, y2, w, h)
	if not (x1 and x2 and w and h) then return nil end
	local dx, dy = (x1 - x2) * w, (y1 - y2) * h
	return math.sqrt(dx * dx + dy * dy)
end

-- running average of a base position; n is capped so later samples still count
function L.Learn(spot, x, y, maxN)
	maxN = maxN or 8
	if not spot.n or spot.n == 0 then
		spot.x, spot.y, spot.n = x, y, 1
		return spot
	end
	local n = math.min(spot.n, maxN - 1) + 1
	spot.x = spot.x + (x - spot.x) / n
	spot.y = spot.y + (y - spot.y) / n
	spot.n = n
	return spot
end

-- status for one flag: "ONCAP", "CARRIED", "DROPPED"
function L.Status(dist, radius, carried)
	if dist and dist <= radius then return "ONCAP" end
	if carried then return "CARRIED" end
	return "DROPPED"
end

-- One flag's tracker. Feed it samples with Step(now, x, y, w, h, carrierKnown); it keeps movement,
-- speed and the transitions the learner needs.
function L.NewFlag(key)
	return { key = key, present = false, seenHome = false, lastMoveT = 0, speed = 0 }
end

-- returns an event: "PICKUP" (appeared from base), "GONE" (left the map: capped or returned) or nil
function L.Step(flag, now, x, y, w, h, carrierKnown)
	if not x then
		local ev = nil
		if flag.present then ev = "GONE" end
		flag.wasCarried = flag.present and flag.carried or false
		flag.lastX, flag.lastY = flag.x, flag.y
		flag.present = false
		flag.seenHome = true -- it's at its base (or not in play): the next appearance is a pickup
		flag.x, flag.y = nil, nil
		flag.speed = 0
		return ev
	end
	local ev = nil
	if not flag.present then
		if flag.seenHome then ev = "PICKUP" end
		flag.present = true
		flag.x, flag.y, flag.t = x, y, now
		flag.lastMoveT = now
		flag.speed = 0
	else
		local moved = L.Yards(x, y, flag.x, flag.y, w or 1, h or 1) or 0
		local dt = now - (flag.t or now)
		if moved > 0.3 then flag.lastMoveT = now end
		if dt > 0 then
			local v = moved / dt
			flag.speed = flag.speed * 0.6 + v * 0.4
		end
		flag.x, flag.y, flag.t = x, y, now
	end
	flag.carried = carrierKnown or (now - flag.lastMoveT) < 1.0
	return ev
end

-- The base a flag caps at, for a flag that just appeared at (x, y): the one it didn't start from.
-- nil when it appeared away from both bases, so a flag picked up mid-field keeps the one it had.
function L.CapSpot(spots, x, y, w, h, range)
	for i, spot in ipairs(spots) do
		local d = L.Yards(x, y, spot.x, spot.y, w, h)
		if d and d <= range then return spots[i == 1 and 2 or 1] end
	end
	return nil
end

-- Which bar each flag goes in: under the score of the team CARRYING it. The Alliance flag is
-- carried by a Horde player, so it sits under the Horde bar (right), and the Horde flag under the
-- Alliance bar (left); swap if your score shows Horde on the left. Each side keeps its spot even
-- when only one flag is out (it used to fill from the left, so a lone flag showed under the wrong
-- team). One under the other: filled from the top, Alliance team's carrier first.
local CARRIED_BY = { Alliance = "Horde", Horde = "Alliance" }
function L.Slots(shown, layout, swap)
	local slots = {}
	local left, right = "Alliance", "Horde"
	if swap then left, right = right, left end
	local rest = {}
	for _, e in ipairs(shown) do
		local team = CARRIED_BY[e.faction or ""]
		if layout == "SIDE" and team == left and not slots[1] then slots[1] = e
		elseif layout == "SIDE" and team == right and not slots[2] then slots[2] = e
		else rest[#rest + 1] = e end
	end
	if layout ~= "SIDE" then
		table.sort(rest, function(a, b)
			local ta, tb = CARRIED_BY[a.faction or ""], CARRIED_BY[b.faction or ""]
			local ra = (ta == left and 1) or (ta == right and 2) or 3
			local rb = (tb == left and 1) or (tb == right and 2) or 3
			return ra < rb
		end)
	end
	-- anything without a known team takes a free bar
	for _, e in ipairs(rest) do
		if not slots[1] then slots[1] = e elseif not slots[2] then slots[2] = e end
	end
	return slots
end

-- the team of the tracked flag last seen closest to (x, y), not already taken this poll
function L.NearestFaction(flags, x, y, used)
	local best, bestD
	for _, faction in ipairs({ "Alliance", "Horde" }) do
		local f = flags[faction]
		local fx, fy = f and (f.x or f.lastX), f and (f.y or f.lastY)
		if fx and not (used and used[faction]) then
			local d = (fx - x) ^ 2 + (fy - y) ^ 2
			if not bestD or d < bestD then best, bestD = faction, d end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Faction of a flag texture
---------------------------------------------------------------------------
local textureFaction -- fileID -> "Alliance" | "Horde"
local function ResolveTextures()
	if textureFaction then return end
	textureFaction = {}
	local probe = UIParent:CreateTexture(nil, "BACKGROUND")
	probe:Hide()
	for faction, list in pairs(FLAG_PATHS) do
		for _, path in ipairs(list) do
			probe:SetTexture(path)
			local id = probe.GetTextureFileID and probe:GetTextureFileID()
			if id then textureFaction[id] = faction end
		end
	end
end

function FC.FactionForTexture(tex)
	ResolveTextures()
	if type(tex) == "string" then
		local s = tex:lower()
		if s:find("alliance") then return "Alliance" end
		if s:find("horde") then return "Horde" end
		return nil
	end
	return textureFaction[tex]
end

---------------------------------------------------------------------------
-- Learned bases: StinkieUIDB.flagCapBases[mapID][key] = { x, y, n }
---------------------------------------------------------------------------
local function Bases(mapID)
	local store = StinkieUIDB
	if not store then return {} end
	store.flagCapBases = store.flagCapBases or {}
	local t = store.flagCapBases[mapID]
	if not t then t = {}; store.flagCapBases[mapID] = t end
	return t
end

---------------------------------------------------------------------------
-- Carriers
---------------------------------------------------------------------------
-- flag faction ("Alliance"/"Horde") -> carrier { name, class }
local carriers = {}
local CLASSIFICATION_FACTION = { FlagCarrierHorde = "Horde", FlagCarrierAlliance = "Alliance" }
local classificationKey -- Enum value -> key name
local function FlagOfUnit(unit)
	if not UnitPvpClassification then return nil end
	local ok, c = pcall(UnitPvpClassification, unit)
	if not ok or not readable(c) then return nil end
	if not classificationKey then
		classificationKey = {}
		local E = Enum and Enum.PvPUnitClassification
		if E then for k, v in pairs(E) do classificationKey[v] = k end end
	end
	return CLASSIFICATION_FACTION[classificationKey[c] or ""]
end

local function NameOf(unit)
	local name, realm = UnitName(unit)
	if not readable(name) then return nil end
	if cfg().realms and readable(realm) and realm ~= "" then name = name .. "-" .. realm end
	local _, class = UnitClass(unit)
	return name, readable(class) and class or nil
end

local function ScanCarriers()
	wipe(carriers)
	-- enemy carriers: the game binds them to arena1..5 inside battlegrounds
	for i = 1, 5 do
		local u = "arena" .. i
		if UnitExists(u) then
			local flag = FlagOfUnit(u)
			local name, class = NameOf(u)
			if name then
				if not flag then
					-- an enemy carries our flag
					local mine = FC.myFaction
					flag = mine
				end
				if flag and not carriers[flag] then carriers[flag] = { name = name, class = class } end
			end
		end
	end
	-- our carriers
	local n = GetNumGroupMembers() or 0
	local prefix = IsInRaid() and "raid" or "party"
	for i = 1, n do
		local u = prefix .. i
		if prefix == "party" and i == n then u = "player" end
		if UnitExists(u) then
			local flag = FlagOfUnit(u)
			if flag and not carriers[flag] then
				local name, class = NameOf(u)
				if name then carriers[flag] = { name = name, class = class } end
			end
		end
	end
	if not IsInRaid() and n == 0 then
		local flag = FlagOfUnit("player")
		if flag then
			local name, class = NameOf("player")
			carriers[flag] = { name = name, class = class }
		end
	end
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local banners = {}

local function CreateBanner(parent)
	local b = CreateFrame("Frame", nil, parent)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	ns.IconBorder(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.name = ns.CreateText(b, 13, "LEFT")
	b.chip = CreateFrame("Frame", nil, b)
	b.chip.bg = b.chip:CreateTexture(nil, "ARTWORK")
	b.chip.bg:SetAllPoints()
	b.status = ns.CreateText(b.chip, 13, "CENTER")
	b.status:SetPoint("CENTER")
	b.dist = ns.CreateText(b, 13, "RIGHT")
	b:Hide()
	return b
end

local function LayoutBanner(b, width)
	local c = cfg()
	width = width or c.width
	b:SetSize(width, c.height)
	b.bg:SetColorTexture(0.04, 0.04, 0.05, c.bgAlpha)
	local h = c.height
	b.icon:SetSize(h - 2, h - 2)
	b.icon:ClearAllPoints()
	b.icon:SetPoint("LEFT", 2, 0)
	local chipW = math.max(60, math.floor(width * 0.34))
	b.chip:SetSize(chipW, h)
	b.chip:ClearAllPoints()
	b.chip:SetPoint("RIGHT")
	ns.ApplyText(b.status, c.statusStyle)
	ns.ApplyText(b.name, c.textStyle)
	ns.ApplyText(b.dist, c.textStyle)
	b.dist:ClearAllPoints()
	b.dist:SetPoint("RIGHT", b.chip, "LEFT", -4, 0)
	b.name:ClearAllPoints()
	b.name:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
	b.name:SetPoint("RIGHT", b.dist, "LEFT", -4, 0)
end

-- info = { texture, faction, carrier = { name, class }, dist, status, eta }
local function FillBanner(b, info)
	local c = cfg()
	-- always our plain flag in the team color (the map's own flag art includes its base)
	b.icon:SetTexture(ns.MEDIA.flag)
	local col = TEAM_COLOR[info.faction or ""] or { 0.8, 0.8, 0.8 }
	b.icon:SetVertexColor(col[1], col[2], col[3], 1)
	local name = ""
	if c.names and info.carrier and info.carrier.name then
		name = info.carrier.name
		local col = c.classColors and info.carrier.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.carrier.class]
		if col then
			b.name:SetTextColor(col.r, col.g, col.b)
		else
			local tc = c.textStyle.color
			b.name:SetTextColor(tc[1], tc[2], tc[3])
		end
	elseif info.status == "DROPPED" then
		name = ""
	end
	b.name:SetText(name)

	local yards = info.dist and string.format("%d yd", math.floor(info.dist + 0.5)) or nil
	local distText = ""
	if c.distance and yards and info.status ~= "ONCAP" then
		distText = yards
		if c.eta and info.eta and info.status == "CARRIED" then distText = distText .. string.format("  ~%ds", math.floor(info.eta + 0.5)) end
	end
	local statusText, color
	if info.status == "HASFLAG" then
		-- carried, but the game isn't showing where (no distance possible)
		statusText, color = "HAS FLAG", c.notOnCapColor
	elseif info.status == "ONCAP" then
		statusText, color = "ON CAP", c.onCapColor
	elseif info.status == "DROPPED" then
		statusText, color = "DROPPED", c.droppedColor
	else
		color = c.notOnCapColor
		if c.onlyYardsWhenNotOnCap and yards then
			statusText = yards
			distText = (c.eta and info.eta) and string.format("~%ds", math.floor(info.eta + 0.5)) or ""
		else
			statusText = "NOT ON CAP"
		end
	end
	b.dist:SetText(distText)
	b.status:SetText(statusText)
	b.chip.bg:SetColorTexture(color[1], color[2], color[3], 0.95)
	b.flash = (info.status == "ONCAP") and c.flashOnCap
	if not b.flash then b.chip:SetAlpha(1) end
	b:Show()
end

-- the score bar to sit under: the widget with the two team bars, else the whole score frame
-- (or its mover outside a battleground)
local function ScoreBars()
	local score = _G.UIWidgetTopCenterContainerFrame
	if FC.inPvP and score and score:IsShown() then
		if type(score.widgetFrames) == "table" then
			for _, w in pairs(score.widgetFrames) do
				if w.LeftBar and w.RightBar and w:IsShown() then return w.LeftBar, w.RightBar end
			end
		end
		return score, score
	end
	local pin = _G.StinkieUI_bgScoreAnchor
	if pin then return pin, pin end
	return UIParent, UIParent
end

local function AnchorHolder()
	local h, c = FC.holder, cfg()
	h:SetScale((c.scale or 1) * ns.db.scale)
	h:ClearAllPoints()
	if c.attach then
		-- locked under the score bar, exactly as wide as it
		local left, right = ScoreBars()
		local y = (c.attachY or -4) / h:GetScale()
		h:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, y)
		h:SetPoint("TOPRIGHT", right, "BOTTOMRIGHT", 0, y)
		FC.anchoredTo = left
		h.SUIActive = false
	else
		ns:ApplyPoint(h, c.point)
		FC.anchoredTo = nil
		h.SUIActive = c.enabled and true or false
	end
end

function FC:Layout()
	local c = cfg()
	local h = FC.holder
	AnchorHolder()
	local total = c.width * ((c.layout == "SIDE") and 2 or 1) + ((c.layout == "SIDE") and c.spacing or 0)
	if c.attach then
		local w = h:GetWidth()
		if w and w > 20 then total = w end
	end
	local bw = (c.layout == "SIDE") and math.floor((total - c.spacing) / 2) or total
	FC.layoutWidth = total
	for i = 1, 2 do
		banners[i] = banners[i] or CreateBanner(h)
		LayoutBanner(banners[i], bw)
		banners[i]:ClearAllPoints()
		if i == 1 then
			banners[i]:SetPoint("TOPLEFT")
		elseif c.layout == "SIDE" then
			banners[i]:SetPoint("LEFT", banners[1], "RIGHT", c.spacing, 0)
		else
			banners[i]:SetPoint("TOP", banners[1], "BOTTOM", 0, -c.spacing)
		end
	end
	local height = (c.layout == "SIDE") and c.height or (c.height * 2 + c.spacing)
	if c.attach then h:SetHeight(height) else h:SetSize(total, height) end
end

-- the score bar changed size or got replaced: lay out again
function FC.CheckAnchor()
	local c = cfg()
	if not c.attach then return end
	local left = ScoreBars()
	local w = FC.holder:GetWidth()
	if left ~= FC.anchoredTo or (w and FC.layoutWidth and math.abs(w - FC.layoutWidth) > 1) then FC:Layout() end
end

local PREVIEW = {
	{ faction = "Alliance", carrier = { name = "Pinkie", class = "PRIEST" }, dist = 3, status = "ONCAP" },
	{ faction = "Horde", carrier = { name = "Stinkie", class = "WARLOCK" }, dist = 42, status = "CARRIED", eta = 6 },
}

function FC:ShowPreview()
	local slots = L.Slots(PREVIEW, cfg().layout, cfg().swapSides)
	for i = 1, 2 do if slots[i] then FillBanner(banners[i], slots[i]) end end
	FC.holder:Show()
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------
local flags = {} -- index -> tracker
local mapID, mapW, mapH
local accum, scanAccum, flashT = 0, 0, 0

-- a two-flag map: at least two flag slots, and either a known capture-the-flag map or flag
-- textures that match the Alliance / Horde flags (orbs and single neutral flags don't count)
local function FlagMap()
	-- only Warsong Gulch and Twin Peaks: never Kotmogu orbs, Eye of the Storm or other maps.
	-- A known map counts at once, even with no flag out yet (it used to wait for both flags to be
	-- picked up, so a single carried flag never showed).
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	if readable(instanceID) then
		if FC.CTF_INSTANCES[instanceID] then return true end
		local n2 = readable(name) and tostring(name):lower() or ""
		return (n2:find("warsong", 1, true) or n2:find("twin peaks", 1, true)) and true or false
	end
	local n = GetNumBattlefieldFlagPositions and GetNumBattlefieldFlagPositions() or 0
	if n < 2 then return false end
	local m = C_Map.GetBestMapForUnit("player")
	if not m then return false end
	local found = 0
	for i = 1, n do
		local _, _, tex = C_PvP.GetBattlefieldFlagPosition(i, m)
		if readable(tex) and FC.FactionForTexture(tex) then found = found + 1 end
	end
	return found >= 2
end

-- the flag tracker for the other team (its base is this flag's cap spot)
local function OtherKey(key)
	for k in pairs(flags) do if k ~= key then return k end end
end

function FC:Poll()
	local c = cfg()
	local now = GetTime()
	mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return end
	if not (mapW and FC.sizeMap == mapID) then
		mapW, mapH = C_Map.GetMapWorldSize(mapID)
		FC.sizeMap = mapID
		if not readable(mapW) or mapW == 0 then mapW, mapH = nil, nil end
	end
	local n = GetNumBattlefieldFlagPositions() or 0
	local bases = Bases(mapID)
	local shown, seenFaction, usedFaction = {}, {}, {}
	for i = 1, math.min(n, 4) do
		local x, y, tex = C_PvP.GetBattlefieldFlagPosition(i, mapID)
		if not readable(x) then x, y = nil, nil end
		local faction = readable(tex) and FC.FactionForTexture(tex) or nil
		if not faction and x then
			-- some flag states (dropped after a carrier dies, picked up again) use other art that
			-- doesn't name a team: it's whichever flag was last seen nearest to this spot
			faction = L.NearestFaction(flags, x, y, usedFaction)
		end
		if faction then usedFaction[faction] = true end
		local key = faction or ("flag" .. i)
		local f = flags[key]
		if not f then f = L.NewFlag(key); flags[key] = f end
		f.index, f.faction = i, faction
		if readable(tex) then f.texture = tex end
		local carrier = faction and carriers[faction] or nil
		local wasPresent = f.present
		local ev = L.Step(f, now, x, y, mapW, mapH, carrier ~= nil)
		local known = FC.BASE_SPOTS[mapID]
		if known then
			if f.present and not wasPresent then
				f.capSpot = L.CapSpot(known, f.x, f.y, mapW, mapH, FC.BASE_RANGE) or f.capSpot
			end
		elseif ev == "PICKUP" then
			bases[key] = L.Learn(bases[key] or {}, f.x, f.y)
		elseif ev == "GONE" and f.wasCarried and f.lastX then
			-- vanished while carried: most likely capped at the other base, right where it disappeared
			local other = OtherKey(key)
			local spot = other and bases[other]
			if spot and spot.x and L.Yards(f.lastX, f.lastY, spot.x, spot.y, mapW, mapH) and
				L.Yards(f.lastX, f.lastY, spot.x, spot.y, mapW, mapH) < 25 then
				L.Learn(spot, f.lastX, f.lastY)
			end
		end
		if f.present then
			local other = OtherKey(key)
			local spot = known and f.capSpot or (not known and other and bases[other]) or nil
			local dist = (spot and spot.x) and L.Yards(f.x, f.y, spot.x, spot.y, mapW, mapH) or nil
			local status = L.Status(dist, c.radius, f.carried)
			local eta = (status == "CARRIED" and dist and f.speed > 2) and (dist - c.radius) / f.speed or nil
			if eta and eta < 0 then eta = nil end
			-- only while someone has it: a dropped flag isn't shown
			if status ~= "DROPPED" then
				table.insert(shown, { faction = faction, carrier = carrier, dist = dist, status = status, eta = eta })
				if faction then seenFaction[faction] = true end
			end
		end
	end
	-- a carrier we know of whose flag the map isn't showing: still shown, without distance
	for _, faction in ipairs({ "Alliance", "Horde" }) do
		if carriers[faction] and not seenFaction[faction] then
			table.insert(shown, { faction = faction, carrier = carriers[faction], status = "HASFLAG" })
		end
	end
	FC.CheckAnchor()
	if ns.unlocked or FC.testMode then return end
	local slots = L.Slots(shown, c.layout, c.swapSides)
	for i = 1, 2 do
		if slots[i] then FillBanner(banners[i], slots[i]) else banners[i]:Hide() end
	end
	FC.holder:SetShown(#shown > 0)
end

local function OnUpdate(_, elapsed)
	accum = accum + elapsed
	flashT = flashT + elapsed
	for i = 1, 2 do
		local b = banners[i]
		if b and b.flash and b:IsShown() then b.chip:SetAlpha(0.55 + 0.45 * math.abs(math.sin(flashT * 4))) end
	end
	local active = FC.flagMap
	if accum < (active and POLL or IDLE_POLL) then return end
	accum = 0
	if not active then
		FC.flagMap = FlagMap()
		if not FC.flagMap then return end
		if ns.BGWidgets then ns.BGWidgets:UpdateFlagRow() end
	end
	scanAccum = scanAccum + 1
	if scanAccum >= 3 then -- carriers ~1.7 times a second
		scanAccum = 0
		pcall(ScanCarriers)
	end
	local ok, err = pcall(FC.Poll, FC)
	if not ok then
		FC.errors = (FC.errors or 0) + 1
		if FC.errors == 1 then geterrorhandler()(err) end
	end
end

function FC:UpdateActive()
	local c = cfg()
	local _, t = IsInInstance()
	FC.inPvP = (t == "pvp")
	local want = c.enabled and FC.inPvP
	wipe(flags)
	wipe(carriers)
	mapW, mapH, FC.sizeMap = nil, nil, nil
	FC.flagMap = false
	accum = 0
	if GetBattlefieldArenaFaction then
		local team = GetBattlefieldArenaFaction()
		FC.myFaction = (team == 0 and "Horde") or (team == 1 and "Alliance") or UnitFactionGroup("player")
	end
	FC.ticker:SetShown(want and true or false)
	if not want then
		FC.holder:SetShown((FC.testMode or ns.unlocked) and c.enabled and true or false)
	end
	if banners[1] then FC:Layout() else AnchorHolder() end
end

function FC:SetTestMode(on)
	FC.testMode = on or nil
	FC:Refresh()
end

function FC:Init()
	local h = CreateFrame("Frame", "StinkieUI_FlagCap", UIParent)
	h:SetFrameStrata("MEDIUM")
	FC.holder = h
	ns:RegisterMover("flagCap", h, "Flag Cap Indicator",
		function() return cfg().point end,
		function(p) cfg().point = p end)
	FC.ticker = CreateFrame("Frame")
	FC.ticker:SetScript("OnUpdate", ns.Timed("Flag Cap", OnUpdate))
	FC.ticker:Hide()
	FC:Layout()
	ns:On("PLAYER_ENTERING_WORLD", function() FC:UpdateActive() end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() FC:UpdateActive() end)
	ns:On("GROUP_ROSTER_UPDATE", function() if FC.flagMap then pcall(ScanCarriers) end end)
	ns:On("ARENA_OPPONENT_UPDATE", function() if FC.flagMap then pcall(ScanCarriers) end end)
	-- the score display moves when Blizzard lays it out; follow it
	local score = _G.UIWidgetTopCenterContainerFrame
	if score then
		score:HookScript("OnShow", function() if cfg().attach then FC:Layout() end end)
		score:HookScript("OnHide", function() if cfg().attach then FC:Layout() end end)
	end
	table.insert(ns.lockCallbacks, function() FC:Refresh() end)
	FC:UpdateActive()
	FC:Refresh()
end

function FC:Refresh()
	if not FC.holder then return end
	FC:Layout()
	local c = cfg()
	if c.enabled and (FC.testMode or ns.unlocked) then
		FC:ShowPreview()
	elseif not (c.enabled and FC.inPvP and FC.flagMap) then
		FC.holder:Hide()
	end
	FC.ticker:SetShown(c.enabled and FC.inPvP and true or false)
	-- the flash needs the ticker; keep it running in test mode too
	if c.enabled and FC.testMode then FC.ticker:Show() end
end

-- /stinkie flags: what the game reports, for troubleshooting
function FC.Debug()
	local m = C_Map.GetBestMapForUnit("player")
	local n = GetNumBattlefieldFlagPositions and GetNumBattlefieldFlagPositions() or 0
	local w, hh = m and C_Map.GetMapWorldSize(m)
	ns:Print(string.format("Flag Cap: map %s, %s x %s yd, %d flag slots, my faction %s", tostring(m), tostring(w), tostring(hh), n, tostring(FC.myFaction)))
	for i = 1, n do
		local x, y, tex = C_PvP.GetBattlefieldFlagPosition(i, m)
		print(string.format("  flag %d: %s, %s  texture %s -> %s", i, tostring(x), tostring(y), tostring(tex), tostring(readable(tex) and FC.FactionForTexture(tex))))
	end
	for key, b in pairs(m and Bases(m) or {}) do
		print(string.format("  learned base %s: %.4f, %.4f (%d samples)", key, b.x or 0, b.y or 0, b.n or 0))
	end
	for key, f in pairs(flags) do
		if f.capSpot then print(string.format("  %s flag caps at: %.3f, %.3f", key, f.capSpot.x, f.capSpot.y)) end
	end
	for faction, cinfo in pairs(carriers) do print("  carrier of " .. faction .. " flag: " .. tostring(cinfo.name)) end
end

-- /stinkie flags reset: forget the learned cap spots on this map
function FC.ResetLearned()
	local m = C_Map.GetBestMapForUnit("player")
	if m and StinkieUIDB and StinkieUIDB.flagCapBases then StinkieUIDB.flagCapBases[m] = nil end
	ns:Print("Flag Cap: learned cap spots cleared for this map.")
end

ns:RegisterModule("FlagCap", FC)
