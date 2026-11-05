-- StinkieUI: battleground team frames, one block for the enemy team and one for your own.
--
-- What Midnight allows in battlegrounds, and how this module uses it:
--   * Roster: scoreboard name / class / race / faction are never secret -> always shown.
--   * Spec and role: scoreboard spec is readable before the match goes live (cached per player);
--     otherwise the class icon is shown. Rows sort healers, tanks, then damage.
--   * Enemies: health, dead state and range only for enemies we can tie to a live unit
--     (nameplate, target, focus, mouseover, and arena1..5, which is how Blizzard exposes flag and
--     orb carriers in battlegrounds). Matching is by name when readable, otherwise by a unique
--     class+race; ambiguous units are never guessed. Unmatched rows are faded.
--   * Allies: bound to their raid unit by name, so health and range are always live.
--   * Click a row to target that player; right click focuses (secure macros, set out of combat).
--   * Carrier icon from UnitPvpClassification; the flag / orb debuff and its stack count through
--     Blizzard's aura container. DRs and trinkets are not available to addons in battlegrounds.
--   * Live matches (Blitz especially): spec and role come only as secret scoreboard values. The
--     spec name is shown as text and the role through the role fonts (cross / shield), both
--     display-only, so nothing ever reads them.
local _, ns = ...

local BG = {}
ns.BGEnemies = BG

local issecret = ns.issecret
local MAX_ROWS = 15

local function readable(v) return not issecret(v) and v ~= nil end -- secret check first: secrets are never compared

-- flag carrier debuffs (Focused / Brutal Assault) and Temple of Kotmogu orbs
BG.OBJECTIVE_AURAS = { [46392] = true, [46393] = true, [121164] = true, [121175] = true, [121176] = true, [121177] = true }
BG.ALLY_AURAS = { [23333] = true, [23335] = true, [156618] = true, [156621] = true, [34976] = true }
for id in pairs(BG.OBJECTIVE_AURAS) do BG.ALLY_AURAS[id] = true end

local ROLE_RANK = { HEALER = 1, TANK = 2, DAMAGER = 3 }
-- scoreboard roleAssigned flags
local ROLE_FROM_FLAG = { [1] = "TANK", [2] = "DAMAGER", [4] = "HEALER", [8] = "DAMAGER" }
local function SortEntries(list)
	table.sort(list, function(a, b)
		local ra, rb = ROLE_RANK[a.role] or 4, ROLE_RANK[b.role] or 4
		if ra ~= rb then return ra < rb end
		if a.classToken ~= b.classToken then return (a.classToken or "") < (b.classToken or "") end
		return a.fullName < b.fullName
	end)
end

---------------------------------------------------------------------------
-- Spec lookup: localized spec name (scoreboard) -> icon + role, per class
---------------------------------------------------------------------------
local classIDByToken
local specIconCache = {}

local function ClassIDFor(token)
	if not classIDByToken then
		classIDByToken = {}
		for i = 1, (GetNumClasses and GetNumClasses() or 13) do
			local _, file, id = GetClassInfo(i)
			if file then classIDByToken[file] = id end
		end
	end
	return classIDByToken[token]
end

local function SpecIconFor(classToken, specName)
	if not (readable(classToken) and readable(specName)) or specName == "" then return nil end
	local key = classToken .. ":" .. specName
	local hit = specIconCache[key]
	if hit then return hit.icon or nil, hit.role end
	local classID = ClassIDFor(classToken)
	local icon, role = false, nil
	if classID and C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID then
		for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do
			local _, name, _, specIcon, specRole = GetSpecializationInfoForClassID(classID, i)
			if name == specName then icon, role = specIcon, specRole end
		end
	end
	specIconCache[key] = { icon = icon, role = role }
	return icon or nil, role
end

local specMemory = {} -- fullName -> { icon, role } remembered from before the match went live

local function MyTeam()
	local me = UnitName("player")
	for i = 1, (GetNumBattlefieldScores() or 0) do
		local info = C_PvP.GetScoreInfo(i)
		if info and info.name == me then return info.faction end
	end
	if GetBattlefieldArenaFaction then return GetBattlefieldArenaFaction() end
end

-- team index 0 = Horde, 1 = Alliance
local function TeamLabel(team)
	if team == 0 then return FACTION_HORDE or "Horde", { 0.90, 0.25, 0.25 } end
	return FACTION_ALLIANCE or "Alliance", { 0.30, 0.55, 1.00 }
end

---------------------------------------------------------------------------
-- Carrier icons
---------------------------------------------------------------------------
local function ClassificationStyle(unit)
	if not (unit and UnitPvpClassification) then return nil end
	local ok, c = pcall(UnitPvpClassification, unit)
	if ok then return ns.CarrierStyle(c) end
	return nil
end
BG.ClassificationStyle = ClassificationStyle

---------------------------------------------------------------------------
-- A team block (enemies or allies)
---------------------------------------------------------------------------
local Side = {}
Side.__index = Side

function Side:cfg() return ns.db[self.key] end

function Side:FindRowForUnit(unit)
	if not (UnitExists(unit) and UnitIsPlayer(unit)) then return nil end
	if self.enemy and not UnitIsEnemy("player", unit) then return nil end
	local name, realm = UnitName(unit)
	if readable(name) then
		local full = (readable(realm) and realm ~= "") and (name .. "-" .. realm) or name
		return self.rowByName[full] or self.rowByName[name]
	end
	if not self.enemy then return nil end
	-- name hidden: bind only when class (+race) points at exactly one unbound row
	local _, classToken = UnitClass(unit)
	if not readable(classToken) then return nil end
	local raceName = UnitRace(unit)
	local hit, count = nil, 0
	for _, row in ipairs(self.rows) do
		local e = row.entry
		if e and (not row.unit or row.unit == unit) and e.classToken == classToken
			and (not readable(raceName) or not e.race or e.race == raceName) then
			hit, count = row, count + 1
		end
	end
	if count == 1 then return hit end
	return nil
end

-- Like FindRowForUnit but ignores existing bindings (carrier marker).
function Side:FindRowLoose(unit)
	if not UnitExists(unit) then return nil end
	local name, realm = UnitName(unit)
	if readable(name) then
		local full = (readable(realm) and realm ~= "") and (name .. "-" .. realm) or name
		return self.rowByName[full] or self.rowByName[name]
	end
	local _, classToken = UnitClass(unit)
	if not readable(classToken) then return nil end
	local hit, count = nil, 0
	for _, row in ipairs(self.rows) do
		if row.entry and row.entry.classToken == classToken then hit, count = row, count + 1 end
	end
	return count == 1 and hit or nil
end

BG.MAX_BUFFS = 8

function BG.BuffFilter(c)
	return c.buffsMine and "HELPFUL|PLAYER" or "HELPFUL"
end

-- Ally rows only. In test mode there's no unit, so the icons show your own buffs.
function Side:UpdateBuffs(row)
	if not row.Buffs then return end
	ns.SetAuraUnit(row.Buffs, self:cfg().buffs and (row.preview and "player" or row.unit) or nil)
end

function Side:Unbind(row)
	if row.unit then self.rowByUnit[row.unit] = nil end
	row.unit = nil
	ns.SetAuraUnit(row.Stacks, nil)
	self:UpdateBuffs(row)
end

function Side:UpdateRowHealth(row, immediate)
	local unit = row.unit
	if not unit then return end
	local c = self:cfg()
	ns.UpdateHealthBar(row, unit, immediate)
	row.hasHealth = true
	if UnitIsDeadOrGhost(unit) then
		row.Health:SetStatusBarColor(0.35, 0.35, 0.35)
		row.Status:SetText(DEAD)
	else
		local col = C_ClassColor.GetClassColor(row.entry.classToken)
		if col then row.Health:SetStatusBarColor(col:GetRGB()) end
		row.Status:SetText(c.showHealthText and ns.FormatHealth(unit, "percent") or "")
	end
end

-- Is this row a healer? Known role first (scoreboard, or group role for allies). A hidden
-- (secret) role can't be tested, so it only counts if "mana users" fallback is on.
function Side:RowIsHealer(row)
	local e = row.entry
	if not e then return false end
	if e.role then return e.role == "HEALER" end
	if row.preview then return false end
	local unit = row.unit
	if unit and not self.enemy then
		local r = UnitGroupRolesAssigned(unit)
		if readable(r) and r ~= "NONE" then return r == "HEALER" end
	end
	if self:cfg().powerManaFallback and unit then
		local pType = UnitPowerType(unit)
		if readable(pType) then return pType == (Enum.PowerType and Enum.PowerType.Mana or 0) end
	end
	return false
end

function Side:UpdateRowPower(row)
	local c = self:cfg()
	local mode = c.power or "healers"
	local show = mode == "all" or (mode == "healers" and self:RowIsHealer(row))
	row.Power:SetShown(show and true or false)
	if not show then return end
	if row.preview then
		row.Power:SetMinMaxValues(0, 1)
		row.Power:SetValue(row.previewPower or 0.7)
		return
	end
	local unit = row.unit
	if unit then
		local mana = Enum.PowerType and Enum.PowerType.Mana or 0
		-- mana for healers (a resto druid in cat form still shows mana); secrets go straight to the bar
		local pt = mode == "all" and nil or mana
		row.Power:SetMinMaxValues(0, UnitPowerMax(unit, pt))
		row.Power:SetValue(UnitPower(unit, pt))
		if mode == "all" then
			row.Power:SetStatusBarColor(ns.GetPowerColor(unit))
		else
			local col = PowerBarColor and PowerBarColor.MANA
			if col then row.Power:SetStatusBarColor(col.r, col.g, col.b) end
		end
		row.hasPower = true
	elseif not row.hasPower then
		-- never seen: a full bar, like health
		row.Power:SetMinMaxValues(0, 1)
		row.Power:SetValue(1)
	end
end

function Side:Bind(row, unit)
	if row.unit == unit then return end
	local old = self.rowByUnit[unit]
	if old and old ~= row then self:Unbind(old) end
	self:Unbind(row)
	row.unit = unit
	self.rowByUnit[unit] = row
	if self:cfg().stacks then ns.SetAuraUnit(row.Stacks, unit) end
	self:UpdateBuffs(row)
	self:UpdateRowHealth(row, true)
	if not self.enemy then self:UpdateHealer(row) end -- allies: group role from the raid unit
	self:UpdateRowPower(row)
end

function Side:TryBind(unit)
	local row = self:FindRowForUnit(unit)
	if row then self:Bind(row, unit) end
end

function Side:ApplyRange(row)
	if row.preview then return end
	local c = self:cfg()
	if not row.unit then
		row:SetAlpha(c.oorAlpha)
		-- Out of sight: keep the last health we saw (faded). Never seen: full bar, no text.
		if not row.hasHealth then
			row.Health:SetMinMaxValues(0, 1)
			row.Health:SetValue(1)
			row.Absorb:SetValue(0)
			row.OverAbsorb:SetAlpha(0)
			row.Status:SetText("")
		end
		return
	end
	if self.enemy then
		local inRange = row.unit:match("^nameplate") ~= nil or UnitIsVisible(row.unit)
		if issecret(inRange) then inRange = true end
		row:SetAlpha(inRange and 1 or c.oorAlpha)
	else
		local inRange = UnitInRange(row.unit)
		if inRange == nil then
			row:SetAlpha(1)
		else
			row:SetAlphaFromBoolean(inRange, 1, c.oorAlpha)
		end
	end
end

-- The icon slot left of each row. "role" mode: a healer cross (always green), tank shield or
-- damage sword. A secret live-match role is written in the role fonts, so it shows without ever
-- being read. If the role is unknown, the spec icon (or class icon) is shown instead.
local ROLE_TEX = { HEALER = "roleHealer", TANK = "roleTank", DAMAGER = "roleDamage" }

function Side:UpdateHealer(row)
	local c = self:cfg()
	local slot = row.Spec
	local e = row.entry
	local role = e and e.role
	if not role and row.unit and not self.enemy then
		local r = UnitGroupRolesAssigned(row.unit)
		if readable(r) and r ~= "NONE" then role = r end
	end
	for _, fs in ipairs(slot.fonts) do fs:SetText("") end
	slot.role:Hide()
	if (c.iconMode or "role") ~= "role" or not e then
		slot.tex:Show()
		return
	end
	if role and ROLE_TEX[role] then
		local col = ns.ROLE_COLORS[role]
		slot.role:SetTexture(ns.MEDIA[ROLE_TEX[role]], "CLAMP", "CLAMP", "TRILINEAR")
		slot.role:SetVertexColor(col[1], col[2], col[3], 1)
		slot.role:Show()
		slot.tex:Hide()
	elseif issecret(e.roleRaw) then
		-- no and/or or comparisons on this value: it's secret
		for _, fs in ipairs(slot.fonts) do ns.SetRoleText(fs, e.roleRaw) end
		slot.tex:Hide()
	else
		slot.tex:Show()
	end
end

-- Which row is my target: by name (or a unique class for hidden enemy names); otherwise ask the
-- game whether a bound row's unit is the target.
function Side:UpdateTargetHighlight()
	local c = self:cfg()
	local hit
	if c.targetHighlight ~= false and UnitExists("target") then
		local isEnemy = UnitIsEnemy("player", "target")
		if readable(isEnemy) and (isEnemy and true or false) == (self.enemy and true or false) then
			hit = self:FindRowLoose("target")
		end
	end
	for _, row in ipairs(self.rows) do
		if row.preview then
			-- test mode: highlight the first row so it can be seen
		elseif c.targetHighlight == false then
			row.TargetHL:SetAlpha(0)
		elseif hit then
			row.TargetHL:SetAlpha(row == hit and 1 or 0)
		elseif row.unit then
			row.TargetHL:SetAlphaFromBoolean(UnitIsUnit(row.unit, "target"), 1, 0)
		else
			row.TargetHL:SetAlpha(0)
		end
	end
end

function Side:UpdateCarriers()
	local found = {}
	if self.enemy then
		for i = 1, 5 do
			local u = "arena" .. i
			if UnitExists(u) then
				local row = self:FindRowLoose(u)
				if row then
					-- the enemy is carrying our team's flag
					local mine = UnitFactionGroup("player")
					found[row] = ClassificationStyle(u)
						or ns.CARRIER_STYLE[mine == "Horde" and "FlagCarrierHorde" or "FlagCarrierAlliance"]
				end
			end
		end
	end
	for _, row in ipairs(self.rows) do
		if row.unit and not found[row] then found[row] = ClassificationStyle(row.unit) end
	end
	local show = self:cfg().carrier
	for _, row in ipairs(self.rows) do
		if not row.preview then
			local atlas = found[row]
			if atlas and show then
				ns.ApplyCarrierStyle(row.Carrier.tex, atlas)
				row.Carrier:Show()
			else
				row.Carrier:Hide()
			end
		end
	end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

function Side:CreateRow(i)
	local row = CreateFrame("Button", "StinkieUI_" .. (self.enemy and "BGEnemy" or "BGAlly") .. i, self.holder, "SecureActionButtonTemplate")
	row:RegisterForClicks("AnyUp", "AnyDown")
	row:SetAttribute("type1", "macro")
	row:SetAttribute("type2", "macro")
	ns.CreateBackdrop(row)
	local health = ns.CreateBar(row)
	health:SetAllPoints()
	health:SetClipsChildren(true)
	row.Health = health
	ns.CreateHealthLayers(row, health)

	-- healer mana strip along the bottom, over the health bar, with a 1px black line above it
	local power = ns.CreateBar(row)
	power:SetFrameLevel(health:GetFrameLevel() + 2)
	power:SetMinMaxValues(0, 1)
	power:SetValue(1)
	local pc = PowerBarColor and PowerBarColor.MANA
	power:SetStatusBarColor(pc and pc.r or 0, pc and pc.g or 0.44, pc and pc.b or 0.87)
	power.sep = power:CreateTexture(nil, "OVERLAY")
	power.sep:SetColorTexture(0, 0, 0, 1)
	power:Hide()
	row.Power = power

	local text = CreateFrame("Frame", nil, row)
	text:SetAllPoints()
	text:SetFrameLevel(health:GetFrameLevel() + 3)
	row.Name = ns.CreateText(text, 12, "LEFT")
	row.Status = ns.CreateText(text, 12, "RIGHT")
	-- spec name as text, for live matches where only a secret spec name is available
	row.SpecText = ns.CreateText(text, 9, "LEFT")
	row.SpecText:SetTextColor(0.8, 0.8, 0.8)

	-- icon slot: role icon, or spec / class icon
	local spec = CreateFrame("Frame", nil, row)
	spec.bg = spec:CreateTexture(nil, "BACKGROUND")
	spec.bg:SetAllPoints()
	spec.bg:SetColorTexture(0.08, 0.08, 0.09, 1)
	spec.tex = spec:CreateTexture(nil, "ARTWORK")
	spec.tex:SetAllPoints()
	spec.role = spec:CreateTexture(nil, "OVERLAY")
	spec.role:Hide()
	spec.fonts = {}
	for k, key in ipairs({ "healerFont", "tankFont", "damageFont" }) do
		local fs = spec:CreateFontString(nil, "OVERLAY")
		fs.fontKey = key
		local role = k == 1 and "HEALER" or k == 2 and "TANK" or "DAMAGER"
		fs.color = ns.ROLE_COLORS[role]
		spec.fonts[k] = fs
	end
	row.Spec = spec


	-- target highlight: a border around the row, outside it, above everything else on the row
	local hl = CreateFrame("Frame", nil, row)
	hl:SetFrameLevel(health:GetFrameLevel() + 6)
	hl.edges = {}
	for k = 1, 4 do hl.edges[k] = hl:CreateTexture(nil, "OVERLAY") end
	hl:SetAlpha(0)
	row.TargetHL = hl

	local carrier = CreateFrame("Frame", nil, row)
	carrier.tex = carrier:CreateTexture(nil, "ARTWORK")
	carrier.tex:SetAllPoints()
	carrier:Hide()
	row.Carrier = carrier

	-- flag / orb debuff with stack count (Blizzard's container does the spell matching)
	local c = self:cfg()
	row.Stacks = ns.CreateAuraContainer(row, {
		{ filter = "HARMFUL", max = 1 },
		{ filter = "HELPFUL", max = 1 },
	}, { size = c.stackSize, spacing = 2, anchor = "TOPRIGHT", growthX = "LEFT", growthY = "DOWN", disableMouse = true })
	ns.SetAuraGroupCandidates(row.Stacks, 1, { includeSpellIDs = BG.OBJECTIVE_AURAS })
	-- teammates: also the flag / orb carry aura itself, since the game gives no carrier icon for them
	ns.SetAuraGroupCandidates(row.Stacks, 2, { includeSpellIDs = self.enemy and BG.OBJECTIVE_AURAS or BG.ALLY_AURAS })
	ns.SetAuraUnit(row.Stacks, nil)

	-- teammates: their buffs, through the same container, so it keeps working in live matches
	if not self.enemy then
		row.Buffs = ns.CreateAuraContainer(row, { { filter = BG.BuffFilter(c), max = c.buffMax } }, {
			size = c.buffSize, spacing = 2, anchor = "TOPLEFT", growthX = "RIGHT", growthY = "DOWN",
			maxWidth = (c.buffSize + 2) * BG.MAX_BUFFS, disableMouse = true,
		})
		ns.SetAuraUnit(row.Buffs, nil)
	end

	row:Hide()
	return row
end

function Side:LayoutRow(row)
	local c = self:cfg()
	row:SetSize(c.width, c.height)
	ns.UpdateBackdrop(row)
	ns.LayoutHealthLayers(row, c.width, c.height)
	ns.ApplyText(row.Name, c.nameStyle)
	ns.ApplyText(row.Status, c.healthStyle)
	row.Status:ClearAllPoints()
	row.Status:SetPoint("RIGHT", -4, 0)
	row.Spec:SetShown(c.specIcon)
	row.Spec:SetSize(c.height, c.height)
	row.Spec:ClearAllPoints()
	row.Spec:SetPoint("RIGHT", row, "LEFT", -3, 0)
	ns.ZoomIcon(row.Spec.tex)
	ns.IconBorder(row.Spec)

	local pw = row.Power
	local ppx = ns.Pixel(row)
	pw:ClearAllPoints()
	pw:SetPoint("BOTTOMLEFT")
	pw:SetPoint("BOTTOMRIGHT")
	pw:SetHeight(math.max(1, c.powerHeight or 3))
	pw.sep:ClearAllPoints()
	pw.sep:SetPoint("BOTTOMLEFT", pw, "TOPLEFT")
	pw.sep:SetPoint("BOTTOMRIGHT", pw, "TOPRIGHT")
	pw.sep:SetHeight(ppx)

	-- role icon / role fonts inside the slot
	local inset = math.max(2, math.floor(c.height * 0.12))
	local slot = row.Spec
	slot.role:ClearAllPoints()
	slot.role:SetPoint("TOPLEFT", inset, -inset)
	slot.role:SetPoint("BOTTOMRIGHT", -inset, inset)
	local fsize = math.max(6, c.height - 2 * inset)
	for _, fs in ipairs(slot.fonts) do
		-- if a symbol font can't load, hide it rather than show plain digits
		fs:SetAlpha(fs:SetFont(ns.MEDIA[fs.fontKey], fsize, "OUTLINE") == false and 0 or 1)
		fs:SetTextColor(fs.color[1], fs.color[2], fs.color[3])
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", slot, "CENTER", 0, 0)
	end
	ns.ApplyText(row.SpecText, c.specStyle or ns.TextDefaults(9))
	row.SpecText:SetJustifyH("LEFT")
	self:PlaceName(row)

	local hl = row.TargetHL
	local px = ns.Pixel(row)
	local t = math.max(1, c.targetThickness or 2) * px
	local o = t + px -- outside the 1px black border
	local tc = c.targetColor or { 1, 1, 1 }
	hl:ClearAllPoints()
	hl:SetPoint("TOPLEFT", row, "TOPLEFT", -o, o)
	hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", o, -o)
	local e = hl.edges
	for k = 1, 4 do e[k]:SetColorTexture(tc[1], tc[2], tc[3], 1) end
	e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(t)
	e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(t)
	e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(t)
	e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(t)

	-- carrier icon, then the debuff stack icon further out on the same side
	local cs = c.height + 4
	row.Carrier:SetSize(cs, cs)
	row.Carrier:ClearAllPoints()
	row.Stacks:ClearAllPoints()
	if c.carrierSide == "RIGHT" then
		local after = row
		row.Carrier:SetPoint("LEFT", after, "RIGHT", 3, 0)
		row.Stacks:SetPoint("TOPLEFT", row.Carrier, "TOPRIGHT", 2, 0)
		ns.SetAuraGrowth(row.Stacks, "TOPLEFT", "RIGHT", "DOWN")
	else
		local before = (c.specIcon and row.Spec) or row
		row.Carrier:SetPoint("RIGHT", before, "LEFT", -3, 0)
		row.Stacks:SetPoint("TOPRIGHT", row.Carrier, "TOPLEFT", -2, 0)
		ns.SetAuraGrowth(row.Stacks, "TOPRIGHT", "LEFT", "DOWN")
	end
	row.Stacks:SetShown(c.stacks)
	-- Temple of Kotmogu: the orb icon and the orb debuff icon look like two orbs. There the
	-- debuff (with its stack count) sits right on top of the orb, same size: one orb, plus stacks.
	-- Where the debuff can't be read (enemies out of sight) the plain orb still shows.
	if c.stacks and BG.IsKotmogu() then
		row.Stacks:ClearAllPoints()
		row.Stacks:SetPoint("CENTER", row.Carrier, "CENTER", 0, 0)
		row.Stacks:SetFrameLevel(row.Carrier:GetFrameLevel() + 3)
		ns.RestyleAuraButtons(row.Stacks, nil, cs)
		row.SUIOrbStacks = true
	elseif row.SUIOrbStacks then
		ns.RestyleAuraButtons(row.Stacks, nil, c.stackSize)
		row.SUIOrbStacks = nil
	end

	if row.Buffs then
		-- beyond the carrier and stack icons when they're on the same side
		local past = c.carrierSide == c.buffSide and (cs + c.stackSize + 5) or 0
		row.Buffs:ClearAllPoints()
		if c.buffSide == "LEFT" then
			local spec = c.specIcon and (c.height + 3) or 0
			row.Buffs:SetPoint("TOPRIGHT", row, "TOPLEFT", -(3 + spec + past), 0)
			ns.SetAuraGrowth(row.Buffs, "TOPRIGHT", "LEFT", "DOWN")
		else
			row.Buffs:SetPoint("TOPLEFT", row, "TOPRIGHT", 3 + past, 0)
			ns.SetAuraGrowth(row.Buffs, "TOPLEFT", "RIGHT", "DOWN")
		end
		row.Buffs:SetShown(c.buffs)
		ns.SetAuraGroupFilter(row.Buffs, 1, BG.BuffFilter(c))
		ns.SetAuraGroupMax(row.Buffs, 1, c.buffMax)
		self:UpdateBuffs(row)
	end

	-- right click: focus (default), target, or nothing. Callers run this out of combat.
	row:SetAttribute("type2", (c.rightClick or "focus") ~= "none" and "macro" or nil)
end

-- Name (and the spec text under it, when there is one) left-aligned, centered as a block.
function Side:PlaceName(row)
	local c = self:cfg()
	row.Name:ClearAllPoints()
	row.SpecText:ClearAllPoints()
	if row.twoLine then
		local nameH = c.nameStyle.size
		local specH = (c.specStyle and c.specStyle.size) or 9
		local top = math.max(0, math.floor((c.height - nameH - specH) / 2 + 0.5))
		row.Name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -top)
		row.Name:SetPoint("RIGHT", row, "RIGHT", -36, 0)
		row.SpecText:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, 0)
		row.SpecText:SetPoint("RIGHT", row, "RIGHT", -36, 0)
	else
		row.Name:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.Name:SetPoint("RIGHT", row, "RIGHT", -36, 0)
		row.SpecText:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, 0)
	end
end

function Side:FillRow(row, e)
	local c = self:cfg()
	if not (row.entry and row.entry.fullName == e.fullName) then row.hasHealth = nil; row.hasPower = nil end
	row.entry = e
	-- spec name text only when there's no icon for it (secret values go straight to the text)
	local twoLine = c.specText and not e.specIcon and (issecret(e.specText) or e.specText ~= nil)
	if twoLine then
		row.SpecText:SetText(e.specText)
	else
		row.SpecText:SetText("")
	end
	twoLine = twoLine and true or false
	if row.twoLine ~= twoLine then
		row.twoLine = twoLine
		self:PlaceName(row)
	end
	row.Name:SetText(c.shortNames and e.baseName or e.fullName)
	local col = C_ClassColor.GetClassColor(e.classToken)
	if col then row.Health:SetStatusBarColor(col:GetRGB()) end
	if e.specIcon then
		row.Spec.tex:SetTexture(e.specIcon)
		ns.ZoomIcon(row.Spec.tex)
	elseif e.classToken then
		row.Spec.tex:SetAtlas("classicon-" .. e.classToken:lower())
	end
	self:UpdateRowPower(row)
	row:SetAttribute("macrotext1", "/targetexact " .. e.fullName)
	local rc = c.rightClick or "focus"
	if rc == "focus" then
		-- target them, focus, then go back to what you had targeted
		row:SetAttribute("macrotext2", "/targetexact " .. e.fullName .. "\n/focus\n/targetlasttarget")
	elseif rc == "target" then
		row:SetAttribute("macrotext2", "/targetexact " .. e.fullName)
	else
		row:SetAttribute("macrotext2", nil)
	end
	self:UpdateHealer(row)
end

function Side:ReadRoster()
	wipe(self.roster)
	if not (C_PvP and C_PvP.GetScoreInfo) then return end
	local mine = MyTeam()
	if mine == nil then return end
	self.team = self.enemy and (1 - mine) or mine
	for i = 1, (GetNumBattlefieldScores() or 0) do
		local info = C_PvP.GetScoreInfo(i)
		local isMine = info and info.faction == mine
		if info and readable(info.name) and ((self.enemy and not isMine) or (not self.enemy and isMine)) then
			local entry = {
				fullName = info.name,
				baseName = info.name:match("^[^%-]+") or info.name,
				classToken = info.classToken,
				race = info.raceName,
			}
			local icon, role = SpecIconFor(info.classToken, info.talentSpec)
			if not role and readable(info.roleAssigned) then role = ROLE_FROM_FLAG[info.roleAssigned] end
			if icon or role then
				local old = specMemory[info.name]
				specMemory[info.name] = { icon = icon or (old and old.icon), role = role or (old and old.role) }
			end
			local mem = specMemory[info.name]
			entry.specIcon = mem and mem.icon
			entry.role = mem and mem.role
			if not entry.role and issecret(info.roleAssigned) then
				entry.roleRaw = info.roleAssigned -- secret: display-only through the role fonts
			end
			if not entry.specIcon and (issecret(info.talentSpec) or (info.talentSpec ~= nil and info.talentSpec ~= "")) then
				entry.specText = info.talentSpec -- may be secret: display-only
			end
			table.insert(self.roster, entry)
		end
	end
	SortEntries(self.roster)
end

function Side:UpdateHeader()
	local c = self:cfg()
	local h = self.header
	ns.ApplyText(h, c.headerStyle)
	local team = self.team
	if team == nil then
		local mineIsHorde = UnitFactionGroup("player") == "Horde"
		local myTeam = mineIsHorde and 0 or 1
		team = self.enemy and (1 - myTeam) or myTeam
	end
	local label, color = TeamLabel(team)
	h:SetText(label)
	h:SetTextColor(color[1], color[2], color[3])
	h:ClearAllPoints()
	h:SetJustifyH("CENTER")
	-- centered over icon + bar: the icon column sits left of the holder
	local shift = c.specIcon and -(c.height + 3) / 2 or 0
	h:SetPoint("BOTTOM", self.holder, "TOP", shift, 4)
	h:SetShown(c.header and (BG.active or self.testMode) and true or false)
end

-- Assigns roster entries to rows. Changes secure attributes, so out of combat only.
function Side:ApplyRoster()
	ns:RunOOC(function()
		local c = self:cfg()
		wipe(self.rowByName)
		local maxRows = math.min(c.maxRows, MAX_ROWS)
		for i, row in ipairs(self.rows) do
			local e = self.roster[i]
			if e and i <= maxRows and BG.active then
				local keepUnit = row.entry and row.entry.fullName == e.fullName and row.unit
				if not keepUnit then self:Unbind(row) end
				self:FillRow(row, e)
				self.rowByName[e.fullName] = row
				if e.baseName ~= e.fullName and not self.rowByName[e.baseName] then self.rowByName[e.baseName] = row end
				row:Show()
				self:ApplyRange(row)
				if row.unit then self:UpdateRowHealth(row, true) end
			else
				self:Unbind(row)
				row.entry = nil
				row:Hide()
			end
		end
		if BG.active then self:BindAll() end
		self:UpdateHeader()
	end)
end

function Side:BindAll()
	if self.enemy then
		for i = 1, 40 do
			local u = "nameplate" .. i
			if UnitExists(u) then self:TryBind(u) end
		end
		for _, u in ipairs({ "target", "focus", "arena1", "arena2", "arena3", "arena4", "arena5" }) do self:TryBind(u) end
	else
		for i = 1, 40 do
			local u = "raid" .. i
			if UnitExists(u) then self:TryBind(u) end
		end
		if not IsInRaid() then
			for i = 1, 4 do self:TryBind("party" .. i) end
			self:TryBind("player")
		end
	end
	for _, row in ipairs(self.rows) do
		if row:IsShown() then
			self:ApplyRange(row)
			self:UpdateHealer(row)
		end
	end
	self:UpdateCarriers()
end

function Side:Layout()
	local holder = self.holder
	local c = self:cfg()
	local cols = math.max(1, c.columns)
	local perCol = math.ceil(math.min(c.maxRows, MAX_ROWS) / cols)
	local colGap = 8 + (c.specIcon and (c.height + 3) or 0)
		+ (c.carrier and (c.height + 7) or 0) + (c.stacks and (c.stackSize + 2) or 0)
		+ (c.buffs and c.buffMax * (c.buffSize + 2) or 0)
	holder:SetScale(ns.db.scale)
	holder:SetSize(cols * c.width + (cols - 1) * colGap, perCol * (c.height + c.spacing) - c.spacing)
	ns:ApplyPoint(holder, c.point)
	for i, row in ipairs(self.rows) do
		self:LayoutRow(row)
		local col = math.floor((i - 1) / perCol)
		local r = (i - 1) % perCol
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", holder, "TOPLEFT", col * (c.width + colGap), -r * (c.height + c.spacing))
	end
end

---------------------------------------------------------------------------
-- Test mode
---------------------------------------------------------------------------
local PREVIEW_SPEC = {
	WARLOCK = "Affliction", PRIEST = "Discipline", MAGE = "Frost", HUNTER = "Marksmanship", WARRIOR = "Protection",
	DRUID = "Restoration", EVOKER = "Devastation", MONK = "Windwalker", DEMONHUNTER = "Havoc",
}
local previewRoster = {
	{ "Stinkie", "WARLOCK", 0.92, "DAMAGER" },
	{ "Pinkie", "PRIEST", 0.55, "HEALER" },
	{ "Minkie", "MAGE", 0.71, "DAMAGER", "FlagCarrierAlliance", 4 },
	{ "Hinkie", "HUNTER", 0.18, "DAMAGER" },
	{ "Winkie", "WARRIOR", 1.0, "TANK" },
	{ "Dinkie", "DRUID", 0.83, "HEALER" },
	{ "Einkie", "EVOKER", 0.44, "DAMAGER" },
	{ "Monkie", "MONK", 0.66, "DAMAGER" },
	{ "Dhinkie", "DEMONHUNTER", 0.0, "DAMAGER" },
}

function Side:ShowPreview(on)
	self.testMode = on or nil
	local c = self:cfg()
	if not on then
		for _, row in ipairs(self.rows) do
			row.preview = nil
			if row.StackPreview then row.StackPreview:Hide() end
			self:UpdateBuffs(row)
		end
		return
	end
	local list = {}
	for _, d in ipairs(previewRoster) do
		table.insert(list, { fullName = d[1] .. "-Stormrage", baseName = d[1], classToken = d[2], role = d[4], hp = d[3], carrier = d[5], stacks = d[6], specText = PREVIEW_SPEC[d[2]] })
	end
	SortEntries(list)
	for i, row in ipairs(self.rows) do
		local e = list[i]
		if e and i <= math.min(c.maxRows, MAX_ROWS) then
			row.preview = true
			row.previewPower = 0.35 + 0.1 * (i % 6)
			self:FillRow(row, e)
			row.Health:SetMinMaxValues(0, 1)
			row.Health:SetValue(e.hp)
			row.Absorb:SetValue(0)
			row.OverAbsorb:SetAlpha(0)
			row.Status:SetText(e.hp == 0 and DEAD or (c.showHealthText and (math.floor(e.hp * 100) .. "%") or ""))
			if e.hp == 0 then row.Health:SetStatusBarColor(0.35, 0.35, 0.35) end
			row:SetAlpha((i % 4 == 0) and c.oorAlpha or 1)
			row.Carrier:SetShown(c.carrier and e.carrier ~= nil)
			if e.carrier then ns.ApplyCarrierStyle(row.Carrier.tex, ns.CARRIER_STYLE[e.carrier]) end
			self:PreviewStacks(row, c.stacks and e.stacks)
			self:UpdateBuffs(row)
			row.TargetHL:SetAlpha((i == 2 and c.targetHighlight ~= false) and 1 or 0)
			row:Show()
		else
			row.preview = nil
			self:PreviewStacks(row, nil)
			self:UpdateBuffs(row)
			row:Hide()
		end
	end
	self:UpdateHeader()
end

-- a stand-in for the container's icon while in test mode
function Side:PreviewStacks(row, count)
	local p = row.StackPreview
	if not count then
		if p then p:Hide() end
		return
	end
	local c = self:cfg()
	if not p then
		p = CreateFrame("Frame", nil, row)
		p.tex = p:CreateTexture(nil, "ARTWORK")
		p.tex:SetAllPoints()
		p.tex:SetTexture([[Interface\Icons\Spell_Magic_GreaterBlessingofKings]])
		p.count = ns.CreateText(p, 10, "RIGHT")
		p.count:SetPoint("BOTTOMRIGHT", -1, 1)
		row.StackPreview = p
	end
	p:SetSize(c.stackSize, c.stackSize)
	ns.ZoomIcon(p.tex)
	ns.IconBorder(p)
	ns.SetFont(p.count, math.max(8, math.floor(c.stackSize * 0.5)), "OUTLINE")
	p.count:SetText(count)
	p:ClearAllPoints()
	if c.carrierSide == "RIGHT" then
		p:SetPoint("LEFT", row.Carrier, "RIGHT", 2, 0)
	else
		p:SetPoint("RIGHT", row.Carrier, "LEFT", -2, 0)
	end
	p:Show()
end

local function NewSide(key, enemy)
	return setmetatable({ key = key, enemy = enemy, rows = {}, roster = {}, rowByName = {}, rowByUnit = {}, rosterKey = "" }, Side)
end

BG.sides = {}

---------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------
-- Large (epic, 40-player) battlegrounds are left alone: too many players for a list.
local function IsLargeBattleground()
	local maxPlayers = select(5, GetInstanceInfo())
	if readable(maxPlayers) and type(maxPlayers) == "number" and maxPlayers > 15 then return true end
	return (GetNumBattlefieldScores() or 0) > 32
end
BG.IsLargeBattleground = IsLargeBattleground

local function InBattleground()
	local _, instanceType = IsInInstance()
	return instanceType == "pvp" and not IsLargeBattleground()
end

local function EachSide(fn)
	for _, side in ipairs(BG.sides) do fn(side) end
end

BG.KOTMOGU = 998 -- Temple of Kotmogu instance ID
function BG.IsKotmogu()
	local _, _, _, _, _, _, _, id = GetInstanceInfo()
	return id == BG.KOTMOGU
end

function BG:UpdateActive()
	local was = BG.active
	BG.active = InBattleground() and not BG.testMode
	if BG.active and not was then
		wipe(specMemory)
		RequestBattlefieldScoreData()
	end
	-- the Kotmogu orb layout depends on the map: lay the rows out again when it changes
	local kot = BG.IsKotmogu()
	if kot ~= BG.wasKotmogu then
		BG.wasKotmogu = kot
		ns:RunOOC(function() EachSide(function(side) side:Layout() end) end)
	end
	if BG.testMode then return end
	EachSide(function(side)
		if BG.active then side:ReadRoster() else wipe(side.roster); side.team = nil end
		side:ApplyRoster()
	end)
end

function BG:SetTestMode(on)
	if InCombatLockdown() then
		ns:Print("Can't toggle battleground test mode in combat.")
		return
	end
	BG.testMode = on or nil
	EachSide(function(side) side:ShowPreview(on) end)
	if not on then BG:UpdateActive() end
end

-- role for any unit we can tie to a row (used by nameplate healer crosses)
-- The secret scoreboard role for a unit, if its row only has that (for the nameplate marker).
function BG.RawRoleForUnit(unit)
	if not BG.active then return nil end
	local isEnemy = UnitIsEnemy("player", unit)
	for _, side in ipairs(BG.sides) do
		local row = side.rowByUnit[unit]
		if not row and readable(isEnemy) and (isEnemy and true or false) == (side.enemy and true or false) then
			row = side:FindRowLoose(unit)
		end
		if row and row.entry and not row.entry.role then return row.entry.roleRaw end
	end
	-- straight from the scoreboard by GUID, when the GUID itself is readable
	local guid = UnitGUID(unit)
	if not issecret(guid) and guid ~= nil and C_PvP.GetScoreInfoByPlayerGuid then
		local ok, info = pcall(C_PvP.GetScoreInfoByPlayerGuid, guid)
		if ok and type(info) == "table" then return info.roleAssigned end
	end
	return nil
end

-- Spec icon for a unit from its battleground row (learned before the gates opened).
function BG.SpecIconForUnit(unit)
	if not BG.active then return nil end
	local isEnemy = UnitIsEnemy("player", unit)
	for _, side in ipairs(BG.sides) do
		local row = side.rowByUnit[unit]
		if not row and readable(isEnemy) and (isEnemy and true or false) == (side.enemy and true or false) then
			row = side:FindRowLoose(unit)
		end
		if row and row.entry and row.entry.specIcon then return row.entry.specIcon end
	end
	return nil
end

function BG.RoleForUnit(unit)
	if not BG.active then return nil end
	for _, side in ipairs(BG.sides) do
		local row = side.rowByUnit[unit]
		if not row then
			local name = UnitName(unit)
			if readable(name) then row = side.rowByName[name] end
		end
		if row and row.entry and row.entry.role then return row.entry.role end
	end
	return nil
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local function MakeSide(key, enemy, label)
	local c = ns.db[key]
	if not c.enabled then return end
	local side = NewSide(key, enemy)
	local holder = CreateFrame("Frame", "StinkieUI_" .. (enemy and "BGHolder" or "BGAllyHolder"), UIParent)
	side.holder = holder
	side.header = ns.CreateText(holder, 13, "LEFT")
	ns:RegisterMover(key, holder, label,
		function() return ns.db[key].point end,
		function(p) ns.db[key].point = p end)
	for i = 1, MAX_ROWS do side.rows[i] = side:CreateRow(i) end
	table.insert(BG.sides, side)
	return side
end

function BG:Init()
	BG.enemies = MakeSide("bgEnemies", true, "Battleground Enemies")
	BG.allies = MakeSide("bgAllies", false, "Battleground Allies")
	if #BG.sides == 0 then return end
	BG.rows = BG.enemies and BG.enemies.rows or BG.allies.rows
	BG.holder = (BG.enemies or BG.allies).holder

	local f = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "UPDATE_BATTLEFIELD_SCORE",
		"PVP_MATCH_STATE_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
		"PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED",
		"UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
		"PLAYER_REGEN_ENABLED",
		"ARENA_OPPONENT_UPDATE", "UNIT_CLASSIFICATION_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
		"UNIT_IN_RANGE_UPDATE", "UNIT_DISTANCE_CHECK_UPDATE", "UNIT_FLAGS" }) do
		f:RegisterEvent(e)
	end
	local E, A = BG.enemies, BG.allies
	f:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "PVP_MATCH_STATE_CHANGED" then
			BG:UpdateActive()
			return
		end
		if not BG.active then return end
		if event == "UPDATE_BATTLEFIELD_SCORE" and IsLargeBattleground() then
			BG:UpdateActive()
			return
		end
		if event == "UPDATE_BATTLEFIELD_SCORE" then
			EachSide(function(side)
				side:ReadRoster()
				local parts = {}
				for _, e in ipairs(side.roster) do parts[#parts + 1] = e.fullName .. (e.role or "") .. (e.specIcon and "*" or "") end
				local key = table.concat(parts, ",")
				if key ~= side.rosterKey then
					side.rosterKey = key
					side:ApplyRoster()
				end
			end)
		elseif event == "PLAYER_REGEN_ENABLED" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
			EachSide(function(side) side:ApplyRoster() end)
		elseif event == "NAME_PLATE_UNIT_ADDED" then
			if E then E:TryBind(unit) end
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			local row = E and E.rowByUnit[unit]
			if row then
				E:Unbind(row)
				-- the same player may still be our target, focus or a carrier unit
				for _, u in ipairs({ "target", "focus", "arena1", "arena2", "arena3", "arena4", "arena5" }) do E:TryBind(u) end
				E:ApplyRange(row)
			end
		elseif event == "PLAYER_TARGET_CHANGED" then
			if E then E:TryBind("target") end
			EachSide(function(side) side:UpdateTargetHighlight() end)
		elseif event == "PLAYER_FOCUS_CHANGED" then
			if E then E:TryBind("focus") end
		elseif event == "UPDATE_MOUSEOVER_UNIT" then
			if E then E:TryBind("mouseover") end
		elseif event == "ARENA_OPPONENT_UPDATE" then
			if E then
				if unit and UnitExists(unit) then E:TryBind(unit) end
				E:UpdateCarriers()
			end
		elseif event == "UNIT_IN_RANGE_UPDATE" or event == "UNIT_DISTANCE_CHECK_UPDATE" or event == "UNIT_FLAGS" then
			-- the game's own range-change signal (what Blizzard's raid frames use): fade at once
			-- (payloads are secret; ApplyRange asks the game again)
			EachSide(function(side)
				local row = unit and side.rowByUnit[unit]
				if row and row:IsShown() then side:ApplyRange(row) end
			end)
		elseif event == "UNIT_CLASSIFICATION_CHANGED" then
			EachSide(function(side) side:UpdateCarriers() end)
		elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
			EachSide(function(side)
				local row = unit and side.rowByUnit[unit]
				if row then side:UpdateRowPower(row) end
			end)
		else
			EachSide(function(side)
				local row = unit and side.rowByUnit[unit]
				if row then side:UpdateRowHealth(row) end
			end)
		end
	end)

	-- periodic: refresh scoreboard, drop stale target/focus/mouseover bindings, range, carriers.
	-- Range is also pushed by UNIT_IN_RANGE_UPDATE; this 0.1 s pass catches anything it misses.
	local rangeElapsed, elapsed, scoreElapsed = 0, 0, 0
	f:SetScript("OnUpdate", ns.Timed("Battleground frames", function(_, dt)
		if not BG.active then return end
		rangeElapsed, elapsed, scoreElapsed = rangeElapsed + dt, elapsed + dt, scoreElapsed + dt
		if scoreElapsed > 5 then
			scoreElapsed = 0
			RequestBattlefieldScoreData()
		end
		if rangeElapsed >= 0.1 then
			rangeElapsed = 0
			EachSide(function(side)
				for _, row in ipairs(side.rows) do
					if row:IsShown() then side:ApplyRange(row) end
				end
			end)
		end
		if elapsed < 0.25 then return end
		elapsed = 0
		EachSide(function(side)
			for _, row in ipairs(side.rows) do
				if row:IsShown() and row.unit and side.enemy then
					local u = row.unit
					if not u:match("^nameplate") then
						-- target/focus/mouseover/arena may now point at someone else
						if side:FindRowForUnit(u) ~= row then side:Unbind(row); side:ApplyRange(row) end
					end
				end
			end
			side:UpdateCarriers()
			side:UpdateTargetHighlight()
		end)
	end))

	table.insert(ns.lockCallbacks, function(unlocked)
		if unlocked then
			BG.testFromUnlock = not BG.testMode
			BG:SetTestMode(true)
		elseif BG.testFromUnlock then
			BG.testFromUnlock = nil
			BG:SetTestMode(false)
		end
	end)
	BG:Refresh()
end

function BG:Refresh()
	if #BG.sides == 0 then return end
	EachSide(function(side)
		side:Layout()
		if BG.testMode then side:ShowPreview(true) else side:ApplyRoster() end
	end)
end

ns:RegisterModule("BGEnemies", BG)
