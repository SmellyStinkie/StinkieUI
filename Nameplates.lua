-- StinkieUI: nameplates. Enemies: health, name, level, castbar, my debuffs + CC + big defensives.
-- Friendlies: small class-colored name, thin health line, healer cross.
local _, ns = ...

local NP = {}
ns.Nameplates = NP
local issecret = ns.issecret
local function readable(v) return v ~= nil and not issecret(v) end

local SMOOTH = Enum.StatusBarInterpolation.ExponentialEaseOut

-- Auras a flag / orb carrier has: WSG / Twin Peaks flags (old and current IDs), Eye of the Storm
-- flag, Temple of Kotmogu orbs
NP.CARRY_AURAS = { [23333] = true, [23335] = true, [156618] = true, [156621] = true, [34976] = true,
	[121164] = true, [121175] = true, [121176] = true, [121177] = true }

-- spell IDs of auras that important units carry on themselves (for when their name is hidden)
function NP.ApplyImportantAuras(f)
	if not f.ImpAura then return end
	local ids = {}
	for _, v in ipairs(ns.db.nameplates.important.auraIDs or {}) do
		local n = tonumber(v)
		if n then ids[n] = true end
	end
	ns.SetAuraGroupCandidates(f.ImpAura, 1, { includeSpellIDs = ids })
end

-- Important enemy units (totems, Psyfiend, ...), matched by NPC ID or English name.
-- Both are hidden from addons when Blizzard restricts unit identity, so matching can miss there.
local importantIDs, importantNames = {}, {}
function NP.BuildImportant()
	wipe(importantIDs)
	wipe(importantNames)
	for _, v in ipairs(ns.db.nameplates.important.units) do
		local n = tonumber(v)
		if n then
			importantIDs[n] = true
		elseif type(v) == "string" and strtrim(v) ~= "" then
			importantNames[strlower(strtrim(v))] = true
		end
	end
end

local function IsImportant(unit)
	local imp = ns.db.nameplates.important
	if not imp.enabled then return false end
	local isPlayer = UnitIsPlayer(unit)
	if issecret(isPlayer) or isPlayer then return false end
	if UnitCreatureID then
		local id = UnitCreatureID(unit)
		if not issecret(id) and id ~= nil and importantIDs[id] then return true end
	end
	local name = UnitName(unit)
	if not issecret(name) and name ~= nil and importantNames[strlower(name)] then return true end
	return false
end
NP.IsImportant = IsImportant

local function IsMinion(unit)
	if not UnitIsMinion then return false end
	local m = UnitIsMinion(unit)
	return not issecret(m) and m == true
end

local plateEvents = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_LEVEL", "UNIT_FLAGS", "UNIT_CLASSIFICATION_CHANGED",
	"UNIT_THREAT_LIST_UPDATE",
}

local function UpdateHealth(f, immediate)
	local u = f.unit
	ns.UpdateHealthBar(f, u, immediate)
	if f.HealthText:IsShown() then
		f.HealthText:SetText(ns.FormatHealth(u, "percent"))
	end
end

local function UpdateColor(f)
	local cfg = ns.db.nameplates
	if f.important then
		local c = cfg.important.color
		f.Health:SetStatusBarColor(c[1], c[2], c[3])
	else
		local color = ns.GetHealthColor(f.unit, true)
		f.Health:SetStatusBarColor(color:GetRGB())
	end
	local style = f.friendly and cfg.friendlyNameStyle or cfg.nameStyle
	if style.classColor then
		f.Name:SetTextColor(ns.GetHealthColor(f.unit, true):GetRGB())
	else
		local c = style.color
		f.Name:SetTextColor(c[1], c[2], c[3])
	end
end

-- First n characters of a UTF-8 string (accented and non-Latin names count one per letter).
local function Utf8Head(str, n)
	local count, i, len = 0, 1, #str
	while i <= len do
		local b = str:byte(i)
		local size = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
		count = count + 1
		if count > n then return str:sub(1, i - 1), true end
		i = i + size
	end
	return str, false
end
NP.Utf8Head = Utf8Head

local function UpdateName(f)
	local u = f.unit
	local cfg = ns.db.nameplates
	if (f.friendly and cfg.friendlyShowLevel) or (not f.friendly and cfg.showLevel) then
		local level = UnitLevel(u)
		local text
		if level and level > 0 then
			local c = GetCreatureDifficultyColor(level)
			text = string.format("|cff%02x%02x%02x%d|r ", c.r * 255, c.g * 255, c.b * 255, level)
		else
			text = "|cffff3333??|r "
		end
		f.Level:SetText(text)
		f.Level:Show()
	else
		f.Level:Hide()
	end
	local name = ns.UnitDisplayName(u, f.friendly and cfg.friendlyNameFormat or cfg.nameFormat)
	local limit = (f.friendly and cfg.friendlyNameMaxChars or cfg.nameMaxChars) or 0
	-- hidden (secret) names can't be shortened; they're clipped to the plate width instead
	if limit > 0 and not ns.issecret(name) and type(name) == "string" then
		local head, cut = Utf8Head(name, limit)
		if cut then name = head .. (cfg.nameEllipsis ~= false and "…" or "") end
	end
	f.Name:SetText(name)
end

local function UpdateMarker(f)
	local cfg = ns.db.nameplates
	local wanted = f.friendly and cfg.friendlyMarker or (not f.friendly and cfg.marker)
	if wanted then ns.UpdateMarker(f.Marker, f.unit) else f.Marker:Hide() end
end
NP.UpdateMarker = UpdateMarker

local ARENA_ROLE_MAP = { HEALER = ns.MEDIA.cross, TANK = ns.MEDIA.blank, DAMAGER = ns.MEDIA.blank }
local UNIT_ROLE_OPTIONS = { displayRoleIcon = true, textureMap = { HEALER = ns.MEDIA.cross, TANK = ns.MEDIA.blank, DAMAGER = ns.MEDIA.blank } }

local function InArena()
	local _, t = IsInInstance()
	return t == "arena"
end

-- Fallbacks for when the role isn't readable. Returns true if one of them is in charge.
local function UpdateSecretRole(f, color)
	local roles = f.SecretRoles
	local U = UnitFrameUtil
	local unit = f.unit
	local used = false
	for i = 1, 5 do roles.arena[i]:SetAlpha(0) end
	roles.unit:SetAlpha(0)
	roles.text:SetText("")

	if not f.friendly and InArena() and U and U.UpdateArenaOpponentSpecDisplay then
		for i = 1, 5 do
			local tex = roles.arena[i]
			tex:SetVertexColor(color[1], color[2], color[3], 1)
			if pcall(U.UpdateArenaOpponentSpecDisplay, { roleIcon = tex }, i, ARENA_ROLE_MAP) then
				local ok, same = pcall(UnitIsUnit, unit, "arena" .. i)
				if ok then pcall(tex.SetAlphaFromBoolean, tex, same, 1, 0) end
			end
		end
		roles:Show()
		return true
	end
	-- Blizzard's role helper: works for group members, and for enemies wherever the game
	-- assigns them a role (Blitz queues by role)
	if U and U.GetUnitRoleIconDisplayInfo then
		local ok, info = pcall(U.GetUnitRoleIconDisplayInfo, unit, UNIT_ROLE_OPTIONS)
		if ok and type(info) == "table" then
			roles.unit:SetVertexColor(color[1], color[2], color[3], 1)
			if pcall(roles.unit.SetTexture, roles.unit, info.roleIconTexture)
				and pcall(roles.unit.SetAlphaFromBoolean, roles.unit, info.showRoleIcon, 1, 0) then
				used = true
			end
		end
	end
	-- battlegrounds: the scoreboard role, written in the role font (on top of the above; both
	-- only ever draw a cross for a healer)
	if ns.BGEnemies and ns.BGEnemies.RawRoleForUnit then
		local raw = ns.BGEnemies.RawRoleForUnit(unit)
		if issecret(raw) or raw ~= nil then
			roles.text:SetTextColor(color[1], color[2], color[3])
			ns.SetRoleText(roles.text, raw)
			used = true
		end
	end
	roles:SetShown(used)
	return used
end

-- only these classes have a healing spec: anyone else never gets a cross, whatever a role source
-- claims (a scoreboard row matched to the wrong player, a stale inspect, Blizzard's role helper)
local HEALER_CLASSES = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true, MONK = true, EVOKER = true }
ns.HEALER_CLASSES = HEALER_CLASSES

function ns.CanHeal(unit)
	local ok, _, token = pcall(UnitClass, unit)
	if not ok or not readable(token) or token == nil then return true end -- unknown: let the role sources decide
	return HEALER_CLASSES[token] and true or false
end

local function UpdateRole(f)
	local cfg = ns.db.nameplates
	local wanted = f.friendly and cfg.healerIcon or (not f.friendly and cfg.enemyHealerIcon)
	f.SecretRoles:Hide()
	if not wanted or not f.unit or not ns.CanHeal(f.unit) then
		f.Healer:Hide()
		return
	end
	local c = f.friendly and ns.HEALER_GREEN or ns.HEALER_RED
	local role = ns.Roles.GetRole(f.unit)
	if role == nil then
		ns.Roles.Request(f.unit)
		f.Healer:Hide()
		UpdateSecretRole(f, c)
		return
	end
	f.Healer.tex:SetVertexColor(c[1], c[2], c[3], 1)
	f.Healer:SetShown(role == "HEALER")
end

local GOLD, SILVER = { 1.00, 0.82, 0.20 }, { 0.80, 0.84, 0.90 }
local SPEC_ROLE_MAP = { HEALER = ns.MEDIA.blank, TANK = ns.MEDIA.blank, DAMAGER = ns.MEDIA.blank }

local function UpdateSpecIcon(f)
	local cfg = ns.db.nameplates
	local spec = f.SpecIcon
	local unit = f.unit
	local wanted = unit and (f.friendly and cfg.specIconsFriendly or (not f.friendly and cfg.specIcons))
	local isPlayer = unit and UnitIsPlayer(unit)
	if not wanted or issecret(isPlayer) or not isPlayer then
		spec:Hide()
		return
	end
	for i = 1, 5 do spec.arena[i]:SetAlpha(0) end
	spec.tex:SetAlpha(1)
	local U = UnitFrameUtil
	if not f.friendly and InArena() and U and U.UpdateArenaOpponentSpecDisplay then
		-- arena: Blizzard's secure helper fills one icon per slot; only this plate's slot shows
		spec.tex:SetAlpha(0)
		for i = 1, 5 do
			local t = spec.arena[i]
			if pcall(U.UpdateArenaOpponentSpecDisplay, { specPortrait = t }, i, SPEC_ROLE_MAP) then
				ns.ZoomIcon(t)
				local ok, same = pcall(UnitIsUnit, unit, "arena" .. i)
				if ok then pcall(t.SetAlphaFromBoolean, t, same, 1, 0) end
			end
		end
		spec:Show()
		return
	end
	local icon = ns.Roles.GetSpecIcon(unit)
	if not icon and ns.BGEnemies and ns.BGEnemies.SpecIconForUnit then icon = ns.BGEnemies.SpecIconForUnit(unit) end
	if icon then
		spec.tex:SetTexture(icon)
		ns.ZoomIcon(spec.tex)
		spec:Show()
	else
		ns.Roles.Request(unit, true)
		spec:Hide()
	end
end
NP.UpdateSpecIcon = UpdateSpecIcon

local function UpdateCarrier(f)
	local style
	if ns.db.nameplates.carrierIcon and f.unit and ns.BGEnemies and ns.BGEnemies.ClassificationStyle then
		style = ns.BGEnemies.ClassificationStyle(f.unit)
	end
	if style then
		ns.ApplyCarrierStyle(f.Carrier, style)
		f.Carrier:Show()
	else
		f.Carrier:Hide()
	end
end

local function UpdateClassification(f)
	UpdateCarrier(f)
	if not (ns.db.nameplates.eliteIcon and not f.friendly and f.unit) then
		f.Elite:Hide()
		return
	end
	local c = UnitClassification(f.unit)
	if issecret(c) or c == nil then f.Elite:Hide() return end
	local color
	if c == "elite" or c == "worldboss" then
		color = GOLD
	elseif c == "rareelite" or c == "rare" then
		color = SILVER
	end
	if color then
		f.Elite:SetVertexColor(color[1], color[2], color[3], 1)
		f.Elite:Show()
	else
		f.Elite:Hide()
	end
end

-- Which plate is the target's. In Blitz and rated PvP "is this unit my target" comes back
-- secret, so friendlies never got the target look. The target's nameplate frame itself is a
-- plain object: comparing frames needs no secret.
function NP.TargetPlate()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	if ok and plate and not issecret(plate) then return plate end
	return nil
end

function NP.IsTargetPlate(f)
	local plate = NP.TargetPlate()
	if plate then return plate == f.nameplate end
	local ok, is = pcall(UnitIsUnit, f.unit, "target")
	if ok and not issecret(is) then return is and true or false end
	return nil -- unknown
end

-- How far the target border reaches past the bar. Only the target has it, so only that plate moves
-- what sits around the bar. If the game won't say which plate is the target, nothing moves.
function NP.BorderReach(f)
	if not (f.Highlight:IsShown() and NP.IsTargetPlate(f)) then return 0 end
	return (ns.db.nameplates.highlight.outset or 0) * ns.Pixel(f)
end

local THREAT_SPOTS = { LEFT = { "BOTTOMLEFT", "TOPLEFT" }, CENTER = { "BOTTOM", "TOP" }, RIGHT = { "BOTTOMRIGHT", "TOPRIGHT" } }

-- Everything just above and below the bar, kept clear of the target border.
function NP.PlaceAroundBar(f)
	local reach = NP.BorderReach(f)
	local gap = ns.Pixel(f) * 2
	f.Castbar:ClearAllPoints()
	f.Castbar:SetPoint("TOPLEFT", f.Health, "BOTTOMLEFT", 0, -gap - reach)
	f.Castbar:SetPoint("TOPRIGHT", f.Health, "BOTTOMRIGHT", 0, -gap - reach)
	f.Auras:ClearAllPoints()
	f.Auras:SetPoint("BOTTOMLEFT", f.Health, "TOPLEFT", 0, (f.auraY or 4) + reach)
	local spot = THREAT_SPOTS[ns.db.nameplates.threatSide] or THREAT_SPOTS.RIGHT
	f.Threat:ClearAllPoints()
	f.Threat:SetPoint(spot[1], f.HealthFrame, spot[2], 0, 2 + reach)
	-- the name, when it sits above the bar
	if f.aboveBar then f.aboveBar:SetPoint("BOTTOMLEFT", f.Health, "TOPLEFT", 0, 3 + reach) end
end

local function UpdateTarget(f)
	if not f.unit then return end
	local is = NP.IsTargetPlate(f)
	NP.PlaceAroundBar(f)
	if is ~= nil then
		f.Highlight:SetAlpha(is and 1 or 0)
		return
	end
	f.Highlight:SetAlphaFromBoolean(UnitIsUnit(f.unit, "target"), 1, 0)
end

-- Green while you're safe, red when you hold aggro for good. Steps 0 to 3, the same scale as the
-- game's own threat level.
local THREAT_COLORS = {
	[0] = { 0.25, 1.00, 0.25 }, -- green
	[1] = { 1.00, 1.00, 0.00 }, -- yellow
	[2] = { 1.00, 0.55, 0.00 }, -- orange
	[3] = { 1.00, 0.15, 0.15 }, -- red
}
local THREAT_NEUTRAL = { 1, 1, 1 }

-- Threat tends to jump rather than climb, so the percent alone skips the middle colors. The game's
-- level knows what it can't: at 100% you have aggro, and level 2 means someone is about to take it.
-- A hidden percent can't be compared (the game's color curves refuse it from addons too), but the
-- level is restricted separately and can still be readable.
function NP.ThreatColor(percent, status)
	local c = ns.db.nameplates
	local level = (status ~= nil and not ns.issecret(status)) and status or nil
	if percent == nil or ns.issecret(percent) then
		return level and THREAT_COLORS[level] or THREAT_NEUTRAL
	end
	if percent >= 100 then return THREAT_COLORS[level or 3] or THREAT_NEUTRAL end
	local step = percent >= c.threatOrange and 2 or percent >= c.threatYellow and 1 or 0
	return THREAT_COLORS[math.max(step, math.min(level or 0, 2))]
end

-- Threat % on your target's plate. It can be hidden from addons: a hidden number can't be
-- compared, so it goes straight to the text, and the plate stays clean if the game refuses it.
function NP.UpdateThreat(f)
	local cfg = ns.db.nameplates
	if not (cfg.threatText and f.unit and not f.friendly and NP.IsTargetPlate(f)) then
		f.Threat:Hide()
		return
	end
	local _, _, percent = UnitDetailedThreatSituation("player", f.unit)
	if issecret(percent) then
		f.Threat:SetShown(pcall(f.Threat.SetFormattedText, f.Threat, "%.0f%%", percent))
	elseif percent == nil then
		f.Threat:Hide()
	else
		f.Threat:SetFormattedText("%.0f%%", percent)
		f.Threat:Show()
	end
	local c = NP.ThreatColor(percent, UnitThreatSituation("player", f.unit))
	f.Threat:SetTextColor(c[1], c[2], c[3])
end

-- Clickable area: our health bar plus padding (more for important units). Blizzard decides
-- which plate wins where two overlap; a bigger area only helps where nothing else is.
local function ApplyHitTest(f)
	local np = f:GetParent()
	if not (np and np.SetHitTestPoints) or f.friendly or not f.unit then return end
	if np.CanChangeHitTestPoints and not np:CanChangeHitTestPoints() then return end
	local cfg = ns.db.nameplates
	local extra = f.important and cfg.important.clickPad or 0
	local px, py = cfg.clickPadX + extra, cfg.clickPadY + extra
	local top = py
	if not cfg.nameInBar then top = top + cfg.nameStyle.size + 3 end
	pcall(np.SetHitTestPoints, np, {
		{ point = "TOPLEFT", relativeTo = f.HealthFrame, relativePoint = "TOPLEFT", offsetX = -px, offsetY = top },
		{ point = "BOTTOMRIGHT", relativeTo = f.HealthFrame, relativePoint = "BOTTOMRIGHT", offsetX = px, offsetY = -py },
	})
end
NP.ApplyHitTest = ApplyHitTest

local function OnEvent(f, event, unit)
	if unit ~= f.unit then return end
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
		UpdateHealth(f)
	elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
		if event == "UNIT_NAME_UPDATE" and NP.RecheckImportant then NP.RecheckImportant(f) end
		UpdateName(f)
	elseif event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
		-- hostility can change while a plate stays up (Solo Shuffle reshuffles teams each round,
		-- arena gates opening). Friendly plates get no auras or castbar, so set the plate up again.
		local hostile = UnitCanAttack("player", unit)
		if not issecret(hostile) and (not hostile) ~= f.friendly and NP.SetupPlate then
			NP.SetupPlate(unit)
		else
			UpdateColor(f)
		end
	elseif event == "UNIT_CLASSIFICATION_CHANGED" then
		UpdateClassification(f)
	elseif event == "UNIT_THREAT_LIST_UPDATE" then
		NP.UpdateThreat(f)
	end
end

-- Big Debuffs groups. IMPORTANT = buffs Blizzard flags to show on enemy nameplates (mostly
-- offensive cooldowns); defensives are excluded from it so nothing shows twice.
local BIG = {
	cc = "HARMFUL|CROWD_CONTROL",
	def = "HELPFUL|BIG_DEFENSIVE",
	ext = "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE",
	off = "HELPFUL|IMPORTANT|!BIG_DEFENSIVE|!EXTERNAL_DEFENSIVE",
}
local function BigGlow()
	local A = ns.db.arenaAssist
	return { glow = A.bigGlow, glowColor = A.bigGlowColor, glowThickness = A.bigGlowThickness }
end

local function BigWanted(f)
	local A = ns.db.arenaAssist
	local AA = ns.ArenaAssist
	return not f.friendly and A.bigAuras and (not AA or not AA.Allowed or AA.Allowed(A.bigWhere)) and true or false
end

local function CreatePlateFrame(nameplate)
	local f = CreateFrame("Frame", nil, nameplate)
	f.nameplate = nameplate
	f:SetAllPoints()
	f:SetFrameLevel(nameplate:GetFrameLevel() + 1)

	-- border lives on a container so the clipping health bar can't clip it
	local container = CreateFrame("Frame", nil, f)
	ns.CreateBackdrop(container)
	f.HealthFrame = container
	local health = ns.CreateBar(container)
	health:SetAllPoints()
	health:SetClipsChildren(true)
	f.Health = health

	ns.CreateHealthLayers(f, health)

	-- on the container, not the health bar: the bar clips children and the highlight can sit outside it
	local hl = CreateFrame("Frame", nil, container)
	hl:SetFrameLevel(health:GetFrameLevel() + 3)
	hl.edges = {}
	for i = 1, 4 do
		local t = hl:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 1, 1, 1)
		hl.edges[i] = t
	end
	hl.Left = ns.CreateText(hl, 16, "RIGHT")
	hl.Left:SetText(">")
	hl.Right = ns.CreateText(hl, 16, "LEFT")
	hl.Right:SetText("<")
	f.Highlight = hl

	-- text sits above the health bar so "name inside the bar" isn't covered
	local textLayer = CreateFrame("Frame", nil, f)
	textLayer:SetAllPoints()
	textLayer:SetFrameLevel(health:GetFrameLevel() + 4)
	f.Name = ns.CreateText(textLayer, 11, "LEFT")
	f.Level = ns.CreateText(textLayer, 11, "LEFT")
	f.HealthText = ns.CreateText(textLayer, 9, "RIGHT")
	f.Threat = ns.CreateText(textLayer, 14, "LEFT")
	f.Threat:Hide()
	f.Marker = textLayer:CreateTexture(nil, "OVERLAY")
	f.Marker:SetTexture(ns.MARKER_TEXTURE)
	f.Marker:Hide()

	-- healer cross: white plus with a thin black outline, tinted green (friendly) or red (enemy)
	local healer = CreateFrame("Frame", nil, f)
	healer.tex = healer:CreateTexture(nil, "OVERLAY")
	healer.tex:SetAllPoints()
	healer.tex:SetTexture(ns.MEDIA.cross, "CLAMP", "CLAMP", "TRILINEAR")
	healer:Hide()
	f.Healer = healer

	-- Secret-safe role markers, used when the game won't tell addons a role directly:
	--  * Arena: one 12x12 icon per arena slot filled by Blizzard's secure spec helper; only the
	--    slot this plate belongs to is visible (UnitIsUnit -> SetAlphaFromBoolean).
	--  * Groups: Blizzard's role-icon helper for this unit (healers only).
	--  * Battlegrounds: the scoreboard role number written in the role font.
	local roles = CreateFrame("Frame", nil, f)
	roles:SetSize(12, 12)
	roles.arena = {}
	for i = 1, 5 do
		local tex = roles:CreateTexture(nil, "OVERLAY")
		tex:SetPoint("CENTER")
		tex:SetSize(12, 12)
		roles.arena[i] = tex
	end
	roles.unit = roles:CreateTexture(nil, "OVERLAY")
	roles.unit:SetPoint("CENTER")
	roles.unit:SetSize(12, 12)
	roles.text = roles:CreateFontString(nil, "OVERLAY")
	roles.text:SetPoint("CENTER")
	roles:Hide()
	f.SecretRoles = roles

	-- own texture (star with a black outline) so it doesn't depend on Blizzard atlas names
	-- spec icon above the plate (left of the healer cross)
	local spec = CreateFrame("Frame", nil, textLayer)
	spec.tex = spec:CreateTexture(nil, "ARTWORK")
	spec.tex:SetAllPoints()
	spec.arena = {}
	for i = 1, 5 do
		local t = spec:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints()
		t:SetAlpha(0)
		spec.arena[i] = t
	end
	-- no border: in arena the slot can be up before Blizzard fills the icon, which left an empty box
	spec:Hide()
	f.SpecIcon = spec

	-- flag / orb / cart carrier, above the plate
	f.Carrier = textLayer:CreateTexture(nil, "OVERLAY", nil, 7)
	f.Carrier:Hide()

	f.Elite = textLayer:CreateTexture(nil, "OVERLAY", nil, 7)
	f.Elite:SetTexture(ns.MEDIA.star, "CLAMP", "CLAMP", "TRILINEAR")
	f.Elite:Hide()

	f.Castbar = ns.CreateCastbar(f)

	local F = ns.AuraFilters
	local cfg = ns.db.nameplates
	f.Auras = ns.CreateAuraContainer(f, {
		{ filter = F.cc, max = 2 },
		{ filter = F.bigDefensive, max = 2 },
		{ filter = F.externalDefensive, max = 1 },
		{ filter = F.mine, max = cfg.maxAuras },
	}, {
		size = cfg.auraSize, spacing = 2, anchor = "BOTTOMLEFT", growthX = "RIGHT", growthY = "UP",
		maxWidth = cfg.width, disableMouse = true,
	})

	-- PvP Assist Big Debuffs: two rows beside the plate, each on its own side (bigCCSide /
	-- bigBuffSide): crowd control, and defensives + offensive cooldowns.
	-- Sizes and glow are set here because aura icons are locked during matches (Auras.lua).
	local A = ns.db.arenaAssist
	local bigOpts = function()
		return {
			size = A.bigSize or 36, spacing = 3, anchor = "TOPLEFT", growthX = "RIGHT", growthY = "DOWN",
			maxWidth = ((A.bigSize or 36) + 3) * 8, disableMouse = true, assistCountdown = true,
			glow = BigGlow,
		}
	end
	f.BigCC = ns.CreateAuraContainer(f, {
		{ filter = BIG.cc, max = A.bigCCMax or 2 },
	}, bigOpts())
	f.BigBuffs = ns.CreateAuraContainer(f, {
		{ filter = BIG.def, max = A.bigDefMax or 1 },
		{ filter = BIG.ext, max = A.bigDefMax or 1 },
		{ filter = BIG.off, max = A.bigOffMax or 1 },
	}, bigOpts())

	-- important units where rated PvP hides their name and NPC ID: their own aura (Grounding
	-- Totem has one) still shows through Blizzard's container, which matches spell IDs for us
	f.ImpAura = ns.CreateAuraContainer(f, {
		{ filter = "HELPFUL", max = 1 },
	}, { size = ns.db.nameplates.important.auraSize or 34, spacing = 0, anchor = "CENTER", growthX = "RIGHT", growthY = "DOWN", disableMouse = true })
	NP.ApplyImportantAuras(f)
	ns.SetAuraUnit(f.ImpAura, nil)

	-- friendly flag / orb carriers: the game gives no carrier classification for teammates, so
	-- their carry aura is shown instead (Blizzard's aura container matches the spell IDs)
	f.FlagAura = ns.CreateAuraContainer(f, {
		{ filter = "HELPFUL", max = 1 },
		{ filter = "HARMFUL", max = 1 },
	}, { size = ns.db.nameplates.carrierSize or 40, spacing = 0, anchor = "CENTER", growthX = "RIGHT", growthY = "DOWN", disableMouse = true })
	ns.SetAuraGroupCandidates(f.FlagAura, 1, { includeSpellIDs = NP.CARRY_AURAS })
	ns.SetAuraGroupCandidates(f.FlagAura, 2, { includeSpellIDs = NP.CARRY_AURAS })
	ns.SetAuraUnit(f.FlagAura, nil)

	f:SetScript("OnEvent", ns.Timed("Nameplates (plate updates)", OnEvent))
	nameplate.SUIFrame = f
	return f
end

local function LayoutHighlight(f, px)
	local hc = ns.db.nameplates.highlight
	local hl = f.Highlight
	local o = (hc.outset or 0) * px
	local t = math.max(1, hc.thickness or 1) * px
	hl:ClearAllPoints()
	hl:SetPoint("TOPLEFT", f.HealthFrame, "TOPLEFT", -o, o)
	hl:SetPoint("BOTTOMRIGHT", f.HealthFrame, "BOTTOMRIGHT", o, -o)
	local e = hl.edges
	local c = hc.color
	for i = 1, 4 do e[i]:SetColorTexture(c[1], c[2], c[3], 1) end
	e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(t)
	e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(t)
	e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(t)
	e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(t)
	local style = { size = hc.arrowSize or 16, outline = "OUTLINE", color = c }
	ns.ApplyText(hl.Left, style)
	ns.ApplyText(hl.Right, style)
	hl.Left:ClearAllPoints()
	hl.Left:SetPoint("RIGHT", hl, "LEFT", -3, 0)
	hl.Right:ClearAllPoints()
	hl.Right:SetPoint("LEFT", hl, "RIGHT", 3, 0)
	hl.Left:SetShown(hc.arrows)
	hl.Right:SetShown(hc.arrows)
	hl:SetShown(not f.friendly or f.friendTarget and true or false)
end

-- a friendly player you target gets the full (enemy-size) plate and the target border
local function FriendTarget(f)
	if not (f.friendly and f.unit and ns.db.nameplates.friendlyTargetFull) then return false end
	return NP.IsTargetPlate(f) and true or false
end

local function LayoutPlate(f)
	local cfg = ns.db.nameplates
	local px = ns.Pixel(f)
	f.friendTarget = FriendTarget(f)
	local friendly = f.friendly and not f.friendTarget
	local w = friendly and cfg.friendlyWidth or cfg.width
	local h = friendly and cfg.friendlyHeight or cfg.height
	if not friendly and f.minion and not f.important then
		w = math.floor(w * (cfg.minionScale or 1) + 0.5)
	end
	-- important units (Grounding, Psyfiend, ...): bigger than a normal plate
	if not friendly and f.important then
		w = math.floor(w * (cfg.important.widthScale or 1.5) + 0.5)
		h = math.floor(h * (cfg.important.heightScale or 1.5) + 0.5)
	end

	f.HealthFrame:ClearAllPoints()
	-- friendly plates can sit lower, leaving room above them for quest / interact icons
	f.HealthFrame:SetPoint("CENTER", f, "CENTER", 0, friendly and (-4 - (cfg.friendlyLower or 0)) or 0)
	f.HealthFrame:SetSize(w, h)
	ns.LayoutHealthLayers(f, w, h)
	ns.UpdateBackdrop(f.HealthFrame)
	-- pink 1px edge on important units so they stand out even when the bar is nearly empty
	if not friendly and f.important and cfg.important.border then
		local c = cfg.important.color
		ns.SetBorderColor(f.HealthFrame, c[1], c[2], c[3], 1)
	else
		ns.SetBorderColor(f.HealthFrame, 0, 0, 0, 1)
	end
	LayoutHighlight(f, px)

	local nameStyle = friendly and cfg.friendlyNameStyle or cfg.nameStyle
	local fontSize = nameStyle.size
	ns.ApplyText(f.Name, nameStyle)
	ns.ApplyText(f.Level, nameStyle)
	ns.ApplyText(f.HealthText, friendly and cfg.friendlyHealthStyle or cfg.healthStyle)
	f.HealthText:ClearAllPoints()
	f.HealthText:SetPoint("RIGHT", f.Health, "RIGHT", -2, 0)
	ns.ApplyText(f.Threat, cfg.threatStyle)
	f.aboveBar = nil -- placed with the rest in NP.PlaceAroundBar; threat goes above the bar there too,
	-- where it can't be mistaken for health percent inside it
	local showHP = cfg.showHealthText
	if friendly then showHP = cfg.friendlyHealthText end
	f.HealthText:SetShown(showHP)

	f.Name:ClearAllPoints()
	f.Level:ClearAllPoints()
	local showLevel = cfg.showLevel
	if friendly then showLevel = cfg.friendlyShowLevel end
	local nameInBar = not friendly and cfg.nameInBar
	if friendly then
		f.Name:SetJustifyH("CENTER")
		if cfg.friendlyNameInBar then
			-- centered on the bar and allowed to run past its ends
			f.Name:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
			f.Name:SetWidth(0)
		else
			f.Name:SetPoint("BOTTOM", f.Health, "TOP", 0, 2)
			-- a level beside the name needs the name to be only as wide as its text
			f.Name:SetWidth(showLevel and 0 or cfg.width)
		end
		if showLevel then f.Level:SetPoint("RIGHT", f.Name, "LEFT", -2, 0) end
	else
		f.Name:SetWidth(0)
		f.Name:SetJustifyH("LEFT")
		local right = showHP and f.HealthText or nil
		if nameInBar then
			if showLevel then
				f.Level:SetPoint("LEFT", f.Health, "LEFT", 3, 0)
				f.Name:SetPoint("LEFT", f.Level, "RIGHT", 0, 0)
			else
				f.Name:SetPoint("LEFT", f.Health, "LEFT", 3, 0)
			end
			if right then
				f.Name:SetPoint("RIGHT", right, "LEFT", -2, 0)
			else
				f.Name:SetPoint("RIGHT", f.Health, "RIGHT", -2, 0)
			end
		else
			if showLevel then
				f.aboveBar = f.Level
				f.Name:SetPoint("LEFT", f.Level, "RIGHT", 0, 0)
			else
				f.aboveBar = f.Name
			end
			f.Name:SetPoint("RIGHT", f.Health, "RIGHT", 0, 0)
		end
		f.Name:SetWordWrap(false)
	end

	local hs = (friendly and cfg.friendlyHealerSize or cfg.healerSize) or 20
	local ss = cfg.specIconSize or 20
	-- the slot above the plate: the healer cross sits here, or the spec icon when it's centered
	local function Slot(frame, dx, dy)
		if friendly then
			if cfg.friendlyNameInBar then
				frame:SetPoint("BOTTOM", f.HealthFrame, "TOP", dx, 2 + dy)
			else
				frame:SetPoint("BOTTOM", f.Name, "TOP", dx, 2 + dy)
			end
		else
			-- above the aura row so the two never overlap
			local y = (nameInBar and 4 or (fontSize + 6)) + cfg.auraSize + 4
			frame:SetPoint("BOTTOM", f.HealthFrame, "TOP", dx, y + dy)
		end
	end
	local specOn = (friendly and cfg.specIconsFriendly) or (not friendly and cfg.specIcons)
	local centered = specOn and (cfg.specAnchor == "CENTER" or cfg.specAnchor == "ABOVE")
	local crossAbove = specOn and cfg.specAnchor == "ABOVE"
	local sx, sy = cfg.specX or 0, cfg.specY or 0
	f.Healer:SetSize(hs, hs)
	f.Healer:ClearAllPoints()
	f.SpecIcon:SetSize(ss, ss)
	f.SpecIcon:ClearAllPoints()
	if centered then
		-- spec icon centered over the plate; the cross moves to its right
		Slot(f.SpecIcon, sx, sy)
		if crossAbove then
			f.Healer:SetPoint("BOTTOM", f.SpecIcon, "TOP", 0, 2)
		else
			f.Healer:SetPoint("LEFT", f.SpecIcon, "RIGHT", 3, 0)
		end
	else
		Slot(f.Healer, 0, 0)
		if cfg.specAnchor == "RIGHT" then
			f.SpecIcon:SetPoint("LEFT", f.Healer, "RIGHT", 3 + sx, sy)
		else
			f.SpecIcon:SetPoint("RIGHT", f.Healer, "LEFT", -3 + sx, sy)
		end
	end
	-- carrier and quest icons stack above whatever is centered
	f.TopSlot = (centered and not crossAbove) and f.SpecIcon or f.Healer
	-- the target marker goes above that slot, so a healer's cross never covers it
	local markerSize = friendly and cfg.friendlyMarkerSize or cfg.markerSize
	f.Marker:SetSize(markerSize, markerSize)
	f.Marker:ClearAllPoints()
	f.Marker:SetPoint("BOTTOM", f.TopSlot, "TOP", 0, 2)
	UpdateMarker(f)
	-- Blizzard's helpers fix their icons at 12x12, so the holder is scaled to the chosen size
	local roles = f.SecretRoles
	roles:SetScale(hs / 12)
	roles:ClearAllPoints()
	roles:SetPoint("CENTER", f.Healer, "CENTER", 0, 0)
	pcall(roles.text.SetFont, roles.text, ns.MEDIA.healerFont, 12, "OUTLINE")


	local cs = cfg.carrierSize or 40
	f.Carrier:SetSize(cs, cs)
	f.Carrier:ClearAllPoints()
	local cx, cy = cfg.carrierX or 0, cfg.carrierY or 0
	if cfg.carrierAnchor == "LEFT" then
		f.Carrier:SetPoint("RIGHT", f.HealthFrame, "LEFT", -4 + cx, cy)
	elseif cfg.carrierAnchor == "TOP" then
		-- the old spot: above the healer / spec icon slot
		f.Carrier:SetPoint("BOTTOM", f.TopSlot, "TOP", cx, 2 + cy)
	else
		-- just above the name, centered on the bar
		f.Carrier:SetPoint("BOTTOM", f.HealthFrame, "TOP", cx, (nameInBar and 2 or (fontSize + 4)) + cy)
	end

	if f.ImpAura then
		f.ImpAura:ClearAllPoints()
		f.ImpAura:SetPoint("BOTTOM", f.HealthFrame, "TOP", 0, (nameInBar and 2 or (fontSize + 4)))
		ns.RestyleAuraButtons(f.ImpAura, { glow = "static", glowColor = cfg.important.color, glowThickness = 2 }, cfg.important.auraSize or 34)
	end
	if f.FlagAura then
		f.FlagAura:ClearAllPoints()
		f.FlagAura:SetPoint("CENTER", f.Carrier, "CENTER", 0, 0)
		ns.RestyleAuraButtons(f.FlagAura, nil, cs)
	end

	local es = cfg.eliteSize or 14
	f.Elite:SetSize(es, es)
	f.Elite:ClearAllPoints()
	f.Elite:SetPoint("CENTER", f.HealthFrame, "TOPLEFT", 0, 0)

	f.Castbar:SetHeight(cfg.castHeight)
	f.Castbar:ApplyConfig({ height = cfg.castHeight, showText = true, showTime = true, textStyle = cfg.castStyle })

	f.auraY = nameInBar and 4 or (fontSize + 6)
	NP.PlaceAroundBar(f)
	NP.UpdateThreat(f) -- the style above painted the text plain, and threat may not change again soon

	-- Big Debuffs beside the bar, clear of the target > < arrows. Each row grows away from the bar.
	-- Our code can't anchor to an aura container, so when both rows share a side the outer one
	-- leaves room for the inner (crowd control) row at its full icon count.
	local A = ns.db.arenaAssist
	local hc = cfg.highlight
	local arrowW = (hc and hc.arrows) and math.floor((hc.arrowSize or 16) * 0.55 + 3) or 0
	local bs = A.bigSize or 36
	local gap = (A.bigX or 4) + arrowW
	local function PlaceBig(container, side, reserve)
		container:ClearAllPoints()
		if side == "LEFT" then
			container:SetPoint("RIGHT", f.HealthFrame, "LEFT", -(gap + reserve), A.bigY or 0)
			ns.SetAuraGrowth(container, "TOPRIGHT", "LEFT", "DOWN")
		else
			container:SetPoint("LEFT", f.HealthFrame, "RIGHT", gap + reserve, A.bigY or 0)
			ns.SetAuraGrowth(container, "TOPLEFT", "RIGHT", "DOWN")
		end
	end
	local ccSide = A.bigCCSide == "LEFT" and "LEFT" or "RIGHT"
	local buffSide = A.bigBuffSide == "RIGHT" and "RIGHT" or "LEFT"
	PlaceBig(f.BigCC, ccSide, 0)
	local reserve = (ccSide == buffSide and A.bigCC) and (A.bigCCMax or 2) * (bs + 3) or 0
	PlaceBig(f.BigBuffs, buffSide, reserve)

	-- important units draw above other plates
	f:SetFrameLevel(f:GetParent():GetFrameLevel() + (f.important and 20 or 1))

	-- Blizzard's soft-target icon (quest / talk / loot when you soft-target a unit): bigger and above our plate
	local soft = f:GetParent().SUISoftTarget
	if soft then
		soft:ClearAllPoints()
		soft:SetPoint("BOTTOM", f.TopSlot or f.Healer, "TOP", 0, cfg.softIconY or 4)
		soft:SetScale(cfg.softIconScale or 1)
		soft:SetFrameLevel(f:GetFrameLevel() + 30)
	end
end

-- Which of my debuffs show: all, only the ones Blizzard flags for nameplates, or a whitelist.
-- Blacklist applies in all modes. Spell IDs can only be matched for debuffs on enemies.
NP.auraVersion = 1
local function ApplyAuraConfig(f)
	if f.auraVersion == NP.auraVersion then return end
	f.auraVersion = NP.auraVersion
	local cfg = ns.db.nameplates
	local c = f.Auras
	local A = ns.db.arenaAssist
	local dup = A.bigAuras and A.bigHideSmall
	ns.SetAuraGroupEnabled(c, 1, cfg.showCC and not (dup and A.bigCC))
	ns.SetAuraGroupEnabled(c, 2, cfg.showDefensives and not (dup and A.bigDef))
	ns.SetAuraGroupEnabled(c, 3, cfg.showDefensives and not (dup and A.bigDef))

	local bcc, bb = f.BigCC, f.BigBuffs
	ns.SetAuraGroupEnabled(bcc, 1, A.bigCC)
	ns.SetAuraGroupMax(bcc, 1, A.bigCCMax or 2)
	ns.SetAuraGroupEnabled(bb, 1, A.bigDef)
	ns.SetAuraGroupEnabled(bb, 2, A.bigDef)
	ns.SetAuraGroupEnabled(bb, 3, A.bigOff)
	ns.SetAuraGroupMax(bb, 1, A.bigDefMax or 1)
	ns.SetAuraGroupMax(bb, 2, A.bigDefMax or 1)
	ns.SetAuraGroupMax(bb, 3, A.bigOffMax or 1)
	for _, b in ipairs({ bcc, bb }) do
		b:SetFlowLayoutMaximumLineSize(((A.bigSize or 36) + 3) * 8)
		-- size / glow changes reach existing icons now, or after the match if auras are secret
		ns.RestyleAuraButtons(b, BigGlow(), A.bigSize or 36, true)
	end
	ns.SetAuraGroupMax(c, 4, cfg.maxAuras)
	ns.SetAuraGroupFilter(c, 4, cfg.auraOnlyMine and ns.AuraFilters.mine or ns.AuraFilters.anyDebuff)
	local filters
	if cfg.auraMode == "whitelist" then
		filters = { includeSpellIDs = ns.SpellSet(cfg.auraWhitelist) or {} }
	elseif cfg.auraMode == "important" then
		filters = { nameplateShowPersonal = true, excludeSpellIDs = ns.SpellSet(cfg.auraBlacklist) }
	else
		local bl = ns.SpellSet(cfg.auraBlacklist)
		filters = bl and { excludeSpellIDs = bl } or nil
	end
	ns.SetAuraGroupCandidates(c, 4, filters)
end

local function HideBlizzardPlate(nameplate)
	local uf = nameplate.UnitFrame
	if not uf then return end
	ns.KillBlizzard(uf)
	if uf.WidgetContainer then
		uf.WidgetContainer:SetParent(nameplate)
		uf.WidgetContainer:ClearAllPoints()
		uf.WidgetContainer:SetPoint("TOP", nameplate, "BOTTOM")
	end
	if uf.SoftTargetFrame then
		uf.SoftTargetFrame:SetParent(nameplate)
		nameplate.SUISoftTarget = uf.SoftTargetFrame
	end
end

local plateUpdates = { UpdateColor, UpdateHealth, UpdateName, UpdateClassification, UpdateRole, UpdateSpecIcon, UpdateTarget }

-- re-test "important" (the name or NPC ID may only now be readable) and re-lay the plate if it changed
function NP.RecheckImportant(f)
	if not f.unit or f.friendly then return end
	local imp = IsImportant(f.unit) and true or false
	if imp == (f.important and true or false) then return end
	f.important = imp
	LayoutPlate(f)
	UpdateColor(f)
	ApplyHitTest(f)
end

local function OnPlateAdded(unit)
	local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
	if not nameplate then return end -- forbidden plates are left to Blizzard
	HideBlizzardPlate(nameplate)

	local f = nameplate.SUIFrame or CreatePlateFrame(nameplate)
	f.unit = unit
	if UnitNameplateShowsWidgetsOnly(unit) or UnitIsGameObject(unit) then
		f:Hide()
		f.Castbar:SetUnit(nil)
		ns.SetAuraUnit(f.Auras, nil)
		ns.SetAuraUnit(f.BigCC, nil)
		ns.SetAuraUnit(f.BigBuffs, nil)
		return
	end

	f.friendly = not UnitCanAttack("player", unit)
	f.important = not f.friendly and IsImportant(unit)
	f.minion = not f.friendly and IsMinion(unit)
	LayoutPlate(f)
	if not f.friendly then ApplyAuraConfig(f) end

	f:UnregisterAllEvents()
	for _, e in ipairs(plateEvents) do f:RegisterUnitEvent(e, unit) end

	f.Castbar:SetUnit(not f.friendly and unit or nil)
	local _, itype = IsInInstance()
	local isPlayer = UnitIsPlayer(unit)
	if issecret(isPlayer) then isPlayer = true end -- unknown: watch anyway, the aura filter decides
	local flagWatch = f.friendly and itype == "pvp" and ns.db.nameplates.carrierIcon and isPlayer
	ns.SetAuraUnit(f.FlagAura, flagWatch and unit or nil)
	f.FlagAura:SetShown(flagWatch and true or false)
	local impWatch = not f.friendly and not isPlayer and ns.db.nameplates.important.enabled and ns.db.nameplates.important.auraMarker
	ns.SetAuraUnit(f.ImpAura, impWatch and unit or nil)
	f.ImpAura:SetShown(impWatch and true or false)
	ns.SetAuraUnit(f.Auras, not f.friendly and unit or nil)
	f.Auras:SetShown(not f.friendly)
	local big = BigWanted(f)
	for _, b in ipairs({ f.BigCC, f.BigBuffs }) do
		ns.SetAuraUnit(b, big and unit or nil)
		b:SetShown(big)
	end

	-- each piece on its own, so an error in one can't skip the others
	for _, fn in ipairs(plateUpdates) do
		local ok, err = pcall(fn, f, true)
		if not ok then geterrorhandler()(err) end
	end
	f:Show()

	ApplyHitTest(f)
	-- Blizzard sets its own hit area while the plate is being set up; ours goes on after it
	C_Timer.After(0, function() if f.unit == unit then ApplyHitTest(f) end end)
	-- a fresh totem's name often arrives a moment after its plate: check again
	if not f.friendly and not f.important then
		C_Timer.After(0.3, function() if f.unit == unit then NP.RecheckImportant(f) end end)
	end
	local uf = nameplate.UnitFrame
	if uf and uf.UpdateHitTestArea and not f.hitHooked then
		f.hitHooked = true
		hooksecurefunc(uf, "UpdateHitTestArea", function() ApplyHitTest(f) end)
	end
end

NP.SetupPlate = OnPlateAdded

-- /stinkie auras: what the target's nameplate aura icons are set to (for bug reports)
function NP.DebugTarget()
	local function show(label, v)
		if issecret(v) then v = "<secret>" end
		ns:Print(label .. ": " .. tostring(v))
	end
	show("auras secret now", ns.AurasLocked and ns.AurasLocked())
	local plate = C_NamePlate.GetNamePlateForUnit("target")
	local f = plate and plate.SUIFrame
	if not f then ns:Print("No Stinkie nameplate for your target.") return end
	show("plate unit", f.unit)
	show("treated as friendly", f.friendly)
	show("found as target plate", NP.IsTargetPlate(f))
	show("full friendly target plate", f.friendTarget)
	show("name (secret = hidden by the game)", UnitName("target"))
	show("NPC ID (secret = hidden by the game)", UnitCreatureID and UnitCreatureID("target"))
	show("minion (pet / totem / guardian)", UnitIsMinion and UnitIsMinion("target"))
	show("target marker (secret = hidden by the game)", GetRaidTargetIndex("target"))
	local _, detailedStatus, threatPercent = UnitDetailedThreatSituation("player", "target")
	show("threat % (secret = hidden by the game)", threatPercent)
	show("threat level from the same call", detailedStatus)
	show("threat level on its own", UnitThreatSituation("player", "target"))
	show("important unit", f.important)
	show("UnitCanAttack now", UnitCanAttack("player", "target"))
	local c = f.Auras
	local ok, u = pcall(c.GetUnit, c)
	show("aura icons watching", ok and u or ("error: " .. tostring(u)))
	show("aura icons shown", c:IsShown())
	for label, b in pairs({ ["big CC"] = f.BigCC, ["big defensives/offensives"] = f.BigBuffs }) do
		local okb, ub = pcall(b.GetUnit, b)
		show(label .. " watching", okb and ub or ("error: " .. tostring(ub)))
		show(label .. " shown", b:IsShown())
	end
	local cfg = ns.db.nameplates
	show("show CC", cfg.showCC)
	show("aura mode", cfg.auraMode)
	show("only mine", cfg.auraOnlyMine)
end

local function OnPlateRemoved(unit)
	local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
	local f = nameplate and nameplate.SUIFrame
	if not f then return end
	f:UnregisterAllEvents()
	f.Castbar:SetUnit(nil)
	ns.SetAuraUnit(f.Auras, nil)
	ns.SetAuraUnit(f.BigCC, nil)
	ns.SetAuraUnit(f.BigBuffs, nil)
	ns.SetAuraUnit(f.FlagAura, nil)
	ns.SetAuraUnit(f.ImpAura, nil)
	f.unit = nil
	f:Hide()
end

local hitInset = 10000
local function SetCV(name, on)
	pcall(C_CVar.SetCVar, name, on and "1" or "0")
end

-- Enemy unit types are Blizzard's own settings: the options read and write them directly, so
-- what the checkboxes show is always what the game is doing. Pets, guardians and totems also
-- need the parent "minions" setting on.
NP.UNIT_TYPE_CVARS = {
	pets = "nameplateShowEnemyPets",
	guardians = "nameplateShowEnemyGuardians",
	totems = "nameplateShowEnemyTotems",
	minor = "nameplateShowEnemyMinus",
}
local MINION_TYPES = { pets = true, guardians = true, totems = true }

-- The checkboxes are the source of truth: every change writes ALL of Blizzard's settings
-- together (parent "minions" + each type), so one box never switches others on or off.
-- Defaults: pets and totems on, guardians and trivial units off.
function NP.WriteUnitTypes()
	local ut = ns.db.nameplates.unitTypes
	ns:RunOOC(function()
		SetCV("nameplateShowEnemyMinions", ut.pets or ut.guardians or ut.totems)
		for key, cvar in pairs(NP.UNIT_TYPE_CVARS) do SetCV(cvar, ut[key]) end
	end)
end

function NP.GetUnitType(key)
	return ns.db.nameplates.unitTypes[key] and true or false
end

function NP.SetUnitType(key, on)
	ns.db.nameplates.unitTypes[key] = on and true or false
	NP.WriteUnitTypes()
end

-- Stacking: the game moves overlapping plates apart until their boxes (SetNamePlateSize) stop
-- overlapping, so a shorter box means plates climb less. 12.1.5's own settings only use
-- nameplateStackingTypes; the older spacing CVars are applied only if the game still has them.
local STACK_CVARS = {
	spacing = { "nameplateOverlapV" },
	speed = { "nameplateMotionSpeed" },
	topInset = { "nameplateOtherTopInset", "nameplateLargeTopInset" },
}
NP.STACK_CVARS = STACK_CVARS

local function HasCVar(name)
	local ok, v = pcall(C_CVar.GetCVar, name)
	return ok and v ~= nil
end

local function ApplyStacking(cfg)
	local st = cfg.stacking
	local E = Enum.NamePlateStackType
	if E and SetCVarBitfield and HasCVar("nameplateStackingTypes") then
		if st.enemies ~= nil then pcall(SetCVarBitfield, "nameplateStackingTypes", E.Enemy, st.enemies and true or false) end
		if st.friendly ~= nil then pcall(SetCVarBitfield, "nameplateStackingTypes", E.Friendly, st.friendly and true or false) end
	end
	st.touched = st.touched or {}
	for key, names in pairs(STACK_CVARS) do
		local v = st[key]
		for _, name in ipairs(names) do
			if HasCVar(name) then
				if v and v > 0 then
					pcall(C_CVar.SetCVar, name, tostring(v))
					st.touched[name] = true
				elseif st.touched[name] then
					-- back to 0: hand the setting back to the game's default
					local okd, def = pcall(C_CVar.GetCVarDefault, name)
					if okd and def then pcall(C_CVar.SetCVar, name, def) end
					st.touched[name] = nil
				end
			end
		end
	end
end

-- /stinkie plates: which stacking settings this game version has, and their values
function NP.PrintStacking()
	local function line(name)
		local ok, v = pcall(C_CVar.GetCVar, name)
		ns:Print(name .. ": " .. ((ok and v ~= nil) and tostring(v) or "not in this game version"))
	end
	local E = Enum.NamePlateStackType
	if E and GetCVarBitfield and HasCVar("nameplateStackingTypes") then
		ns:Print("stacking enemies: " .. tostring(GetCVarBitfield("nameplateStackingTypes", E.Enemy)) ..
			", friendlies: " .. tostring(GetCVarBitfield("nameplateStackingTypes", E.Friendly)))
	else
		line("nameplateStackingTypes")
	end
	for _, names in pairs(STACK_CVARS) do
		for _, name in ipairs(names) do line(name) end
	end
	local cfg = ns.db.nameplates
	local bh = cfg.stacking.boxHeight
	ns:Print("stacking box height: " .. ((bh and bh > 0) and bh or (cfg.height + cfg.castHeight + 24) .. " (auto)"))
end

function NP:ApplyCVars()
	ns:RunOOC(function()
		local cfg = ns.db.nameplates
		local bh = cfg.stacking.boxHeight
		C_NamePlate.SetNamePlateSize(cfg.width + 10, (bh and bh > 0) and bh or (cfg.height + cfg.castHeight + 24))
		pcall(ApplyStacking, cfg)
		if cfg.highlight.scale then
			pcall(C_CVar.SetCVar, "nameplateSelectedScale", tostring(cfg.highlight.scale))
		end
		if C_NamePlateManager and C_NamePlateManager.SetNamePlateHitTestInsets then
			local inset = cfg.friendlyClickThrough and hitInset or -hitInset
			C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly, inset, inset, inset, inset)
		end
	end)
end

function NP:Init()
	if not ns.db.nameplates.enabled then return end
	NP.BuildImportant()
	local hc = ns.db.nameplates.highlight
	if hc.scale == nil then
		hc.scale = tonumber(C_CVar.GetCVar("nameplateSelectedScale")) or 1
	end
	-- start from whatever stacking the game is set to, so nothing changes until it's edited here
	local st = ns.db.nameplates.stacking
	local E = Enum.NamePlateStackType
	if E and GetCVarBitfield and HasCVar("nameplateStackingTypes") then
		if st.enemies == nil then st.enemies = GetCVarBitfield("nameplateStackingTypes", E.Enemy) and true or false end
		if st.friendly == nil then st.friendly = GetCVarBitfield("nameplateStackingTypes", E.Friendly) and true or false end
	end
	local driver = CreateFrame("Frame")
	driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	driver:RegisterEvent("PLAYER_TARGET_CHANGED")
	driver:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	driver:RegisterEvent("GROUP_ROSTER_UPDATE")
	driver:RegisterEvent("ARENA_OPPONENT_UPDATE")
	driver:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
	driver:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
	driver:RegisterEvent("RAID_TARGET_UPDATE")
	driver:SetScript("OnEvent", ns.Timed("Nameplates (add / remove / target)", function(_, event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			OnPlateAdded(unit)
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			OnPlateRemoved(unit)
		elseif event == "PLAYER_TARGET_CHANGED" then
			for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
				local f = plate.SUIFrame
				if f and f.unit then
					if f.friendly and FriendTarget(f) ~= (f.friendTarget and true or false) then
						LayoutPlate(f)
						UpdateName(f)
						UpdateColor(f)
					end
					UpdateTarget(f)
					NP.UpdateThreat(f)
				end
			end
		elseif event == "RAID_TARGET_UPDATE" then
			for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
				if plate.SUIFrame and plate.SUIFrame.unit then UpdateMarker(plate.SUIFrame) end
			end
		else
			for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
				if plate.SUIFrame and plate.SUIFrame.unit then UpdateRole(plate.SUIFrame); UpdateSpecIcon(plate.SUIFrame) end
			end
		end
	end))
	NP.driver = driver
	-- 0.12 and older kept a "manage" switch and had guardians on; move to the new defaults once
	local ut = ns.db.nameplates.unitTypes
	if ut.manage ~= nil then
		ut.manage = nil
		ut.pets, ut.totems, ut.guardians, ut.minor = true, true, false, false
	end
	NP.WriteUnitTypes()
	ns.Roles:OnChange(function()
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			if plate.SUIFrame and plate.SUIFrame.unit then UpdateRole(plate.SUIFrame); UpdateSpecIcon(plate.SUIFrame) end
		end
	end)
	NP:ApplyCVars()
end

function NP:Refresh()
	if not NP.driver then return end
	NP:ApplyCVars()
	NP.BuildImportant()
	NP.auraVersion = NP.auraVersion + 1
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local f = plate.SUIFrame
		if f then NP.ApplyImportantAuras(f) end
		if f and f.unit then
			OnPlateAdded(f.unit)
		end
	end
end

function NP.RefreshImportantAuras()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		if plate.SUIFrame then NP.ApplyImportantAuras(plate.SUIFrame) end
	end
end

ns:RegisterModule("Nameplates", NP)
