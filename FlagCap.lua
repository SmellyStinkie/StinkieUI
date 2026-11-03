-- StinkieUI: Flag Cap Indicator (capture-the-flag battlegrounds: Warsong Gulch, Twin Peaks).
-- For each flag that's out: who carries it, how many yards they are from their cap spot, and
-- ON CAP / NOT ON CAP / DROPPED, so the team knows when a return wins the point.
--
-- Data: C_PvP.GetBattlefieldFlagPosition (map position of each flag that isn't at its base; not a
-- secret value) and C_Map.GetMapWorldSize (map size in yards). Cap spots aren't exposed by the game,
-- so they're learned: a flag first appears where it's picked up, which is its own base, and a team
-- caps at its own flag's base. Learned spots are kept per map (account-wide) and refined on caps.
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

local function LayoutBanner(b)
	local c = cfg()
	b:SetSize(c.width, c.height)
	b.bg:SetColorTexture(0.04, 0.04, 0.05, c.bgAlpha)
	local h = c.height
	b.icon:SetSize(h - 2, h - 2)
	b.icon:ClearAllPoints()
	b.icon:SetPoint("LEFT", 2, 0)
	local chipW = math.max(60, math.floor(c.width * 0.34))
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
	if info.texture then
		b.icon:SetTexture(info.texture)
		b.icon:SetVertexColor(1, 1, 1, 1)
	else
		b.icon:SetTexture(ns.MEDIA.flag)
		local col = TEAM_COLOR[info.faction or ""] or { 0.8, 0.8, 0.8 }
		b.icon:SetVertexColor(col[1], col[2], col[3], 1)
	end
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
	if info.status == "ONCAP" then
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

local function AnchorHolder()
	local h, c = FC.holder, cfg()
	h:SetScale((c.scale or 1) * ns.db.scale)
	h:ClearAllPoints()
	if c.attach then
		local score = _G.UIWidgetTopCenterContainerFrame
		local pin = _G.StinkieUI_bgScoreAnchor
		local inBG = FC.inPvP
		local target = (inBG and score and score:IsShown()) and score or pin or score or UIParent
		h:SetPoint("TOP", target, "BOTTOM", c.attachX / h:GetScale(), c.attachY / h:GetScale())
		h.SUIActive = false
	else
		ns:ApplyPoint(h, c.point)
		h.SUIActive = c.enabled and true or false
	end
end

function FC:Layout()
	local c = cfg()
	local h = FC.holder
	for i = 1, 2 do
		banners[i] = banners[i] or CreateBanner(h)
		LayoutBanner(banners[i])
		banners[i]:ClearAllPoints()
		if i == 1 then
			banners[i]:SetPoint("TOPLEFT")
		elseif c.layout == "SIDE" then
			banners[i]:SetPoint("LEFT", banners[1], "RIGHT", c.spacing, 0)
		else
			banners[i]:SetPoint("TOP", banners[1], "BOTTOM", 0, -c.spacing)
		end
	end
	if c.layout == "SIDE" then
		h:SetSize(c.width * 2 + c.spacing, c.height)
	else
		h:SetSize(c.width, c.height * 2 + c.spacing)
	end
	AnchorHolder()
end

local PREVIEW = {
	{ faction = "Alliance", carrier = { name = "Pinkie", class = "PRIEST" }, dist = 3, status = "ONCAP" },
	{ faction = "Horde", carrier = { name = "Stinkie", class = "WARLOCK" }, dist = 42, status = "CARRIED", eta = 6 },
}

function FC:ShowPreview()
	for i = 1, 2 do FillBanner(banners[i], PREVIEW[i]) end
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
	local n = GetNumBattlefieldFlagPositions and GetNumBattlefieldFlagPositions() or 0
	if n < 2 then return false end
	local instanceID = select(8, GetInstanceInfo())
	if readable(instanceID) and FC.CTF_INSTANCES[instanceID] then return true end
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
	local shown = {}
	for i = 1, math.min(n, 4) do
		local x, y, tex = C_PvP.GetBattlefieldFlagPosition(i, mapID)
		if not readable(x) then x, y = nil, nil end
		local faction = readable(tex) and FC.FactionForTexture(tex) or nil
		local key = faction or ("flag" .. i)
		local f = flags[key]
		if not f then f = L.NewFlag(key); flags[key] = f end
		f.index, f.faction = i, faction
		if readable(tex) then f.texture = tex end
		local carrier = faction and carriers[faction] or nil
		local ev = L.Step(f, now, x, y, mapW, mapH, carrier ~= nil)
		if ev == "PICKUP" then
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
			local spot = other and bases[other]
			local dist = (spot and spot.x) and L.Yards(f.x, f.y, spot.x, spot.y, mapW, mapH) or nil
			local status = L.Status(dist, c.radius, f.carried)
			local eta = (status == "CARRIED" and dist and f.speed > 2) and (dist - c.radius) / f.speed or nil
			if eta and eta < 0 then eta = nil end
			table.insert(shown, { texture = f.texture, faction = faction, carrier = carrier, dist = dist, status = status, eta = eta })
		end
	end
	if ns.unlocked or FC.testMode then return end
	for i = 1, 2 do
		if shown[i] then FillBanner(banners[i], shown[i]) else banners[i]:Hide() end
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
	AnchorHolder()
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
	FC.ticker:SetScript("OnUpdate", OnUpdate)
	FC.ticker:Hide()
	FC:Layout()
	ns:On("PLAYER_ENTERING_WORLD", function() FC:UpdateActive() end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() FC:UpdateActive() end)
	ns:On("GROUP_ROSTER_UPDATE", function() if FC.flagMap then pcall(ScanCarriers) end end)
	ns:On("ARENA_OPPONENT_UPDATE", function() if FC.flagMap then pcall(ScanCarriers) end end)
	-- the score display moves when Blizzard lays it out; follow it
	local score = _G.UIWidgetTopCenterContainerFrame
	if score then
		score:HookScript("OnShow", function() if cfg().attach then AnchorHolder() end end)
		score:HookScript("OnHide", function() if cfg().attach then AnchorHolder() end end)
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
	for faction, cinfo in pairs(carriers) do print("  carrier of " .. faction .. " flag: " .. tostring(cinfo.name)) end
end

-- /stinkie flags reset: forget the learned cap spots on this map
function FC.ResetLearned()
	local m = C_Map.GetBestMapForUnit("player")
	if m and StinkieUIDB and StinkieUIDB.flagCapBases then StinkieUIDB.flagCapBases[m] = nil end
	ns:Print("Flag Cap: learned cap spots cleared for this map.")
end

ns:RegisterModule("FlagCap", FC)
