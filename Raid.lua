-- StinkieUI: raid frames. What Blizzard's raid frames show, in the Stinkie UI look, with free sizes
-- and fonts.
--
-- The game's own group header does the roster work: it makes the unit buttons, gives each one its
-- unit, sorts them and shows or hides them, and it can do all of that in combat. This file only
-- says how a button looks. Every button is made up front, out of combat, so none is ever made in
-- the middle of a fight. Headers and buttons are protected: anything that moves, sizes, shows or
-- hides them goes through ns:RunOOC. What changes in combat is drawn on plain child frames.
local _, ns = ...

local UF = ns.UF
local Raid = {}
ns.Raid = Raid
Raid.buttons = {}  -- every unit button, in the order made
Raid.headers = {}  -- groups 1-8, then .tanks and .pets
Raid.byUnit = {}   -- "raid7" -> its button

local issecret = ns.issecret
local MAX_GROUPS, GROUP_SIZE = 8, 5
local ROLE_ORDER = "TANK,HEALER,DAMAGER,NONE"
local TANK_BUTTONS, PET_BUTTONS = 10, 40
local READY_SECONDS = 6 -- how long the ready check answers stay up once it's over
local RANGE_TICK = 0.2

local function cfg() return ns.db.raid end

local ROLE_ART = {
	TANK = { "roleTank", ns.TANK_COLOR },
	HEALER = { "roleHealer", ns.HEALER_GREEN },
	DAMAGER = { "roleDamage", { 0.95, 0.35, 0.35 } },
}
local READY_ART = {
	ready = [[Interface\RaidFrame\ReadyCheck-Ready]],
	notready = [[Interface\RaidFrame\ReadyCheck-NotReady]],
	waiting = [[Interface\RaidFrame\ReadyCheck-Waiting]],
}
local CENTER_ATLAS = {
	summonPending = "RaidFrame-Icon-SummonPending",
	summonAccepted = "RaidFrame-Icon-SummonAccepted",
	summonDeclined = "RaidFrame-Icon-SummonDeclined",
	resurrect = "RaidFrame-Icon-Rez",
	phase = "RaidFrame-Icon-Phasing",
	otherGroup = "RaidFrame-Icon-LFR",
}
local HEAL_COLOR, HEAL_ABSORB_COLOR = { 0.35, 0.95, 0.45, 0.45 }, { 0.55, 0.08, 0.08, 0.75 }
local AGGRO_FALLBACK = { 1, 0.2, 0.2 }

-- our frames are up and stand in for Blizzard's
function Raid.HidesBlizzard()
	return Raid.holder ~= nil and cfg().hideBlizzard and true or false
end

---------------------------------------------------------------------------
-- Which unit a button shows
---------------------------------------------------------------------------
-- raid7 -> raidpet7, party2 -> partypet2, player -> pet
function Raid.PetOf(unit)
	if unit == "player" then return "pet" end
	local kind, n = unit:match("^(%a+)(%d+)$")
	return kind and (kind .. "pet" .. n) or nil
end

-- Someone driving a vehicle shows as the vehicle, as on Blizzard's frames.
function Raid.DisplayUnit(unit)
	if not unit then return nil end
	if cfg().vehicles and UnitHasVehicleUI(unit) then
		local pet = Raid.PetOf(unit)
		if pet and UnitExists(pet) then return pet end
	end
	return unit
end

-- role of the player on the button (not of a vehicle); nil when the game hides it
local function RoleOf(f)
	local role = f.realUnit and UnitGroupRolesAssigned(f.realUnit)
	if issecret(role) then return nil end
	return role
end

---------------------------------------------------------------------------
-- The parts that change while you play
---------------------------------------------------------------------------
local function WantPower(f)
	if f.SUIRaid == "pet" then return false end
	local mode = cfg().power
	if mode == "none" then return false end
	if mode == "all" then return true end
	return RoleOf(f) == "HEALER"
end

function Raid.UpdatePower(f, showPower)
	local c = cfg()
	local h = f.SUIHeight or c.height
	f.Power:SetShown(showPower)
	f.PowerSeparator:SetShown(showPower)
	f.Health:SetHeight(showPower and (h - c.powerHeight - ns.Pixel(f)) or h)
	if showPower and not f.preview then UF.UpdatePower(f, true) end
end

function Raid.UpdateRole(f, role)
	local c = cfg()
	local art = role and ROLE_ART[role]
	local show = art ~= nil and f.SUIRaid ~= "pet"
		and (c.roleIcon == "all" or (c.roleIcon == "tankHealer" and role ~= "DAMAGER"))
	local icon = f.RoleIcon
	if show then
		icon:SetTexture(ns.MEDIA[art[1]])
		icon:SetVertexColor(art[2][1], art[2][2], art[2][3], 1)
	end
	icon:SetShown(show)
	-- the name starts after the icon when there is one
	f.Name:ClearAllPoints()
	if c.namePosition == "TOP" then
		f.Name:SetJustifyH("CENTER")
		f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
		f.Name:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
	else
		f.Name:SetJustifyH("LEFT")
		f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", show and (c.roleSize + 4) or 3, -3)
		f.Name:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
	end
end

function Raid.UpdateHighlight(f)
	if not cfg().targetHighlight or not f.unit then
		f.Highlight:SetAlpha(0)
		return
	end
	f.Highlight:SetAlphaFromBoolean(UnitIsUnit(f.unit, "target"), 1, 0)
end

-- Red (or the game's threat color) outline on whoever a mob is attacking. The game hides threat
-- in some places; no outline then.
function Raid.UpdateAggro(f)
	local border = f.Aggro
	if not cfg().aggro or not f.unit then
		border:Hide()
		return
	end
	local status = UnitThreatSituation(f.unit)
	if issecret(status) or not status or status < 1 then
		border:Hide()
		return
	end
	local r, g, b = GetThreatStatusColor(status)
	if not r then r, g, b = AGGRO_FALLBACK[1], AGGRO_FALLBACK[2], AGGRO_FALLBACK[3] end
	for _, edge in ipairs(border.edges) do edge:SetColorTexture(r, g, b, 1) end
	border:Show()
end

-- summon, resurrection, phased, in another group: one icon in the middle, in that order
function Raid.CenterState(unit)
	local summon = C_IncomingSummon
	if summon and summon.HasIncomingSummon(unit) then
		local status, E = summon.IncomingSummonStatus(unit), Enum.SummonStatus
		if E and status == E.Pending then return "summonPending" end
		if E and status == E.Accepted then return "summonAccepted" end
		if E and status == E.Declined then return "summonDeclined" end
	end
	if UnitHasIncomingResurrection(unit) then return "resurrect" end
	local reason = UnitPhaseReason(unit)
	if not issecret(reason) and reason then return "phase" end
	if UnitInOtherParty(unit) then return "otherGroup" end
	return nil
end

function Raid.UpdateCenter(f)
	local icon = f.CenterIcon
	local state = cfg().centerIcons and f.realUnit and f.SUIRaid ~= "pet" and Raid.CenterState(f.realUnit)
	if state then
		icon:SetAtlas(CENTER_ATLAS[state])
		icon:Show()
	else
		icon:Hide()
	end
end

function Raid.ShowReady(f, status)
	f.readyStatus = status
	local art = status and READY_ART[status]
	if art and cfg().readyCheck then
		f.Ready:SetTexture(art)
		f.Ready:Show()
	else
		f.Ready:Hide()
	end
end

function Raid.UpdateReady(f)
	local unit = f.realUnit
	Raid.ShowReady(f, unit and f.SUIRaid ~= "pet" and GetReadyCheckStatus(unit) or nil)
end

-- The check is over: no answer counts as not ready, and the answers stay up for a few seconds.
function Raid.FinishReady()
	Raid.readyRun = (Raid.readyRun or 0) + 1
	local run = Raid.readyRun
	for _, f in ipairs(Raid.buttons) do
		if f.readyStatus == "waiting" then Raid.ShowReady(f, "notready") end
	end
	C_Timer.After(READY_SECONDS, function()
		if Raid.readyRun ~= run then return end -- another check started
		for _, f in ipairs(Raid.buttons) do Raid.ShowReady(f, nil) end
	end)
end

-- Incoming heals after the health, then shields after those; heal absorbs eat into the health from
-- its right edge. The numbers can be hidden values, so they only ever go to the bars.
function Raid.UpdatePrediction(f)
	local heal, eaten = f.HealPredict, f.HealAbsorb
	if not heal then return end
	local calc = f.calc
	local connected = f.unit and UnitIsConnected(f.unit)
	if not (calc and calc.GetIncomingHeals and cfg().healPrediction and connected) then
		heal:SetValue(0)
		eaten:SetValue(0)
		return
	end
	local max = UnitHealthMax(f.unit)
	heal:SetMinMaxValues(0, max)
	eaten:SetMinMaxValues(0, max)
	heal:SetValue((calc:GetIncomingHeals()))
	eaten:SetValue((calc:GetHealAbsorbs()))
end

-- Boss debuffs the game keeps from addons: it draws them itself at spots we give it. The spots
-- belong to a unit, so they're given again whenever the button's unit changes.
function Raid.UpdatePrivate(f)
	local api = C_UnitAuras
	f.privateIDs = f.privateIDs or {}
	for _, id in ipairs(f.privateIDs) do pcall(api.RemovePrivateAuraAnchor, id) end
	wipe(f.privateIDs)
	local c = cfg()
	local unit = f.unit
	if not (c.privateAuras and unit and not f.preview and f.SUIRaid ~= "pet" and api.AddPrivateAuraAnchor) then return end
	local size = c.privateSize
	for i = 1, c.privateMax do
		local ok, id = pcall(api.AddPrivateAuraAnchor, {
			unitToken = unit,
			auraIndex = i,
			parent = f.PrivateHolder,
			showCooldownFrame = true,
			showCountdownNumbers = false,
			iconInfo = {
				iconAnchor = { point = "TOPRIGHT", relativeTo = f.PrivateHolder, relativePoint = "TOPRIGHT",
					offsetX = -(i - 1) * (size + 1), offsetY = 0 },
				iconWidth = size, iconHeight = size,
			},
		})
		if ok and id then f.privateIDs[#f.privateIDs + 1] = id end
	end
end

---------------------------------------------------------------------------
-- Aura icons (made the first time a button has someone on it)
---------------------------------------------------------------------------
local function BuildAuras(f)
	if f.aurasBuilt or f.SUIRaid == "pet" then return end
	f.aurasBuilt = true
	local c, F = cfg(), ns.AuraFilters
	local noMouse = not c.auraTooltips -- icons that take the mouse would swallow clicks meant for the player
	-- bottom left: crowd control, then debuffs you can dispel (colored border), then the rest
	f.Debuffs = ns.CreateAuraContainer(f, {
		{ filter = F.cc, max = 1 },
		{ filter = F.dispellable, max = c.debuffMax, dispelBorder = true },
		{ filter = "HARMFUL|!RAID_PLAYER_DISPELLABLE|!CROWD_CONTROL", max = c.debuffMax },
	}, { size = c.debuffSize, spacing = 1, anchor = "BOTTOMLEFT", growthX = "RIGHT", growthY = "UP",
		maxWidth = (c.debuffSize + 1) * (c.debuffMax + 1), disableMouse = noMouse })
	-- bottom right: your own heals over time and the like
	f.Buffs = ns.CreateAuraContainer(f, { { filter = "HELPFUL|PLAYER|RAID_IN_COMBAT", max = c.buffMax } },
		{ size = c.buffSize, spacing = 1, anchor = "BOTTOMRIGHT", growthX = "LEFT", growthY = "UP",
			maxWidth = (c.buffSize + 1) * c.buffMax, disableMouse = noMouse })
	-- middle: a big defensive that's running
	f.Defensives = ns.CreateAuraContainer(f, {
		{ filter = F.bigDefensive, max = 1 },
		{ filter = F.externalDefensive, max = 1 },
	}, { size = c.defensiveSize, spacing = 1, anchor = "BOTTOMLEFT", growthX = "RIGHT", growthY = "UP",
		maxWidth = (c.defensiveSize + 1) * 2, disableMouse = true })
	-- the whole frame outlined in the color of a debuff you can dispel
	f.DispelGlow = ns.CreateAuraContainer(f, { { filter = F.dispellable, max = 1 } },
		{ outlineOnly = true, outlineWidth = c.width, outlineHeight = f.SUIHeight or c.height,
			size = c.height, spacing = 0, anchor = "TOPLEFT", growthX = "RIGHT", growthY = "DOWN", maxWidth = c.width + 1 })
	Raid.PlaceAuras(f)
end

function Raid.PlaceAuras(f)
	if not f.aurasBuilt then return end
	f.Debuffs:ClearAllPoints()
	f.Debuffs:SetPoint("BOTTOMLEFT", f.Health, "BOTTOMLEFT", 2, 2)
	f.Buffs:ClearAllPoints()
	f.Buffs:SetPoint("BOTTOMRIGHT", f.Health, "BOTTOMRIGHT", -2, 2)
	f.Defensives:ClearAllPoints()
	f.Defensives:SetPoint("CENTER", f.Health, "CENTER", 0, 0)
	f.DispelGlow:ClearAllPoints()
	f.DispelGlow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
end

local function WatchAuras(f)
	if not f.aurasBuilt then return end
	local c = cfg()
	local unit = not f.preview and f.unit or nil
	local function watch(container, on)
		ns.SetAuraUnit(container, on and unit or nil)
		container:SetShown(on and unit ~= nil)
	end
	watch(f.Debuffs, c.debuffs ~= "none")
	watch(f.Buffs, c.buffs)
	watch(f.Defensives, c.defensiveIcon)
	watch(f.DispelGlow, c.dispelHighlight)
	-- "dispellable only" keeps crowd control and what you can dispel, and drops the rest
	ns.SetAuraGroupEnabled(f.Debuffs, 3, c.debuffs == "all")
end

---------------------------------------------------------------------------
-- One button
---------------------------------------------------------------------------
-- after the shared health, name and marker updates (UF.UpdateAll)
local function PostUpdate(f)
	local role = RoleOf(f)
	Raid.UpdatePower(f, WantPower(f))
	Raid.UpdateRole(f, role)
	Raid.UpdateHighlight(f)
	Raid.UpdateAggro(f)
	Raid.UpdateCenter(f)
	Raid.UpdateReady(f)
	Raid.UpdatePrediction(f)
	BuildAuras(f)
	WatchAuras(f)
end

-- the button's own unit events, after UF has handled them
local function OnEventExtra(f, event)
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED"
		or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" or event == "UNIT_CONNECTION" then
		Raid.UpdatePrediction(f)
	end
end

local function WatchUnit(f)
	f:UnregisterAllEvents()
	local unit = f.unit
	if not unit then return end
	UF.RegisterUnitEvents(f)
	f:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit)
	f:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit)
end

-- The unit to draw: the player on the button, or their vehicle. Called when the header hands the
-- button a new unit and when someone gets in or out of a vehicle.
function Raid.Resolve(f)
	local unit = f.realUnit
	if unit and f.SUIRaid ~= "pet" then unit = Raid.DisplayUnit(unit) end
	local same = unit and UnitIsUnit(unit, "player")
	f.isMe = unit ~= nil and not issecret(same) and same and true or false
	if unit == f.unit then return end
	f.unit = unit
	if f.preview then return end
	WatchUnit(f)
	Raid.UpdatePrivate(f)
	if unit and f:IsShown() then UF.SafeUpdateAll(f) end
end

function Raid.SetUnit(f, unit)
	if f.realUnit == unit then return end
	if f.realUnit and Raid.byUnit[f.realUnit] == f then Raid.byUnit[f.realUnit] = nil end
	f.realUnit = unit
	if unit then Raid.byUnit[unit] = f end
	Raid.Resolve(f)
end

local function OnAttributeChanged(f, name, value)
	if name == "unit" then Raid.SetUnit(f, value) end
end

local function NewBorder(f, level)
	local border = CreateFrame("Frame", nil, f)
	border:SetAllPoints()
	border:SetFrameLevel(level)
	border.edges = {}
	for i = 1, 4 do
		local t = border:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 1, 1, 1)
		border.edges[i] = t
	end
	return border
end

local function LayoutBorder(border, thickness)
	local e = border.edges
	e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(thickness)
	e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(thickness)
	e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(thickness)
	e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(thickness)
end

-- Size and place everything on a button. Out of combat only: it sizes the button itself.
function Raid.LayoutButton(f)
	local c = cfg()
	local pet = f.SUIRaid == "pet"
	local w, h = c.width, pet and c.petHeight or c.height
	f.SUIHeight = h
	f.forceClassColor = c.classColor and true or nil
	UF.Layout(f, {
		width = w, height = h,
		showPower = false, -- split from the health in UpdatePower, as on the party frames
		powerHeight = c.powerHeight,
		showName = c.showName, nameAbove = false, nameFormat = c.nameFormat, nameMaxChars = c.nameMaxChars, showLevel = false,
		leaderIcon = c.leaderIcon and not pet, healthText = pet and "none" or c.healthText,
		nameStyle = c.nameStyle, healthStyle = c.healthStyle, shields = c.shields,
	})
	local px = ns.Pixel(f)
	f.Power:ClearAllPoints()
	f.Power:SetPoint("BOTTOMLEFT")
	f.Power:SetPoint("BOTTOMRIGHT")
	f.Power:SetHeight(c.powerHeight)
	f.PowerSeparator:ClearAllPoints()
	f.PowerSeparator:SetPoint("BOTTOMLEFT", f.Power, "TOPLEFT")
	f.PowerSeparator:SetPoint("BOTTOMRIGHT", f.Power, "TOPRIGHT")
	f.PowerSeparator:SetHeight(px)

	-- With the health text off, "Dead" and "Offline" still show: an unknown mode makes the shared
	-- text function return just those.
	if not pet and c.healthText == "none" then
		f.healthTextMode = "status"
		f.HealthText:Show()
	end
	f.HealthText:ClearAllPoints()
	f.HealthText:SetJustifyH("CENTER")
	if c.healthPosition == "BOTTOM" then
		f.HealthText:SetPoint("BOTTOM", f.Health, "BOTTOM", 0, 3)
	elseif c.healthPosition == "TOPRIGHT" then
		f.HealthText:SetJustifyH("RIGHT")
		f.HealthText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
	else
		f.HealthText:SetPoint("CENTER", f.Health, "CENTER", 0, -2)
	end

	f.RoleIcon:SetSize(c.roleSize, c.roleSize)
	f.RoleIcon:ClearAllPoints()
	f.RoleIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
	f.markerShown = c.marker and not pet
	f.Marker:SetSize(c.markerSize, c.markerSize)
	f.Marker:ClearAllPoints()
	f.Marker:SetPoint("CENTER", f, "TOP", 0, 0)
	local s = math.min(c.statusIconSize, h - 2)
	f.Ready:SetSize(s, s)
	f.CenterIcon:SetSize(s, s)
	f.PrivateHolder:SetSize(math.max(1, c.privateMax * (c.privateSize + 1)), c.privateSize)

	LayoutBorder(f.Highlight, px)
	LayoutBorder(f.Aggro, px * 2)
	for _, edge in ipairs(f.Highlight.edges) do edge:SetColorTexture(1, 1, 1, 1) end

	f.HealPredict:SetSize(w, h)
	f.HealPredict:SetStatusBarColor(HEAL_COLOR[1], HEAL_COLOR[2], HEAL_COLOR[3], HEAL_COLOR[4])
	f.HealAbsorb:SetSize(w, h)
	f.HealAbsorb:SetStatusBarColor(HEAL_ABSORB_COLOR[1], HEAL_ABSORB_COLOR[2], HEAL_ABSORB_COLOR[3], HEAL_ABSORB_COLOR[4])
	Raid.PlaceAuras(f)
	Raid.UpdateRole(f, f.preview and f.previewRole or RoleOf(f))
end

-- Turns a button the header made into a raid frame. kind: "raid", "tank" or "pet".
function Raid.Dress(f, kind)
	if f.SUIRaid then return end
	f.SUIRaid = kind
	UF.Dress(f, nil)
	f:SetAttribute("toggleForVehicle", true) -- a click on someone in a vehicle targets the vehicle
	f.PostUpdate = PostUpdate
	f.OnEventExtra = OnEventExtra

	local layer = f.TextLayer
	f.Marker = layer:CreateTexture(nil, "OVERLAY")
	f.Marker:SetTexture(ns.MARKER_TEXTURE)
	f.Marker:Hide()
	f.RoleIcon = layer:CreateTexture(nil, "OVERLAY")
	f.RoleIcon:Hide()
	f.Ready = layer:CreateTexture(nil, "OVERLAY", nil, 6)
	f.Ready:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.Ready:Hide()
	f.CenterIcon = layer:CreateTexture(nil, "OVERLAY", nil, 5)
	f.CenterIcon:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.CenterIcon:Hide()

	f.Highlight = NewBorder(f, layer:GetFrameLevel() + 1)
	f.Highlight:SetAlpha(0)
	f.Aggro = NewBorder(f, layer:GetFrameLevel())
	f.Aggro:Hide()

	-- incoming heals sit between the health and the shield; heal absorbs cover the health's end
	local health = f.Health
	local heal = ns.CreateBar(health)
	heal:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT")
	heal:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT")
	f.HealPredict = heal
	f.Absorb:ClearAllPoints()
	f.Absorb:SetPoint("TOPLEFT", heal:GetStatusBarTexture(), "TOPRIGHT")
	f.Absorb:SetPoint("BOTTOMLEFT", heal:GetStatusBarTexture(), "BOTTOMRIGHT")
	local eaten = ns.CreateBar(health)
	eaten:SetReverseFill(true)
	eaten:SetPoint("TOPRIGHT", health:GetStatusBarTexture(), "TOPRIGHT")
	eaten:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT")
	eaten:SetFrameLevel(health:GetFrameLevel() + 1)
	f.HealAbsorb = eaten

	f.PrivateHolder = CreateFrame("Frame", nil, f)
	f.PrivateHolder:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.PrivateHolder:SetFrameLevel(layer:GetFrameLevel() + 2)

	f:HookScript("OnAttributeChanged", OnAttributeChanged)
	Raid.buttons[#Raid.buttons + 1] = f
	Raid.LayoutButton(f)
	Raid.SetUnit(f, f:GetAttribute("unit"))
end

---------------------------------------------------------------------------
-- Headers
---------------------------------------------------------------------------
-- what the header runs on each button it makes (the game's restricted code, so plain text)
local function ButtonSetup(height)
	return ([[
		self:SetWidth(%d)
		self:SetHeight(%d)
		self:SetAttribute("*type1", "target")
		self:SetAttribute("*type2", "togglemenu")
		self:SetAttribute("toggleForVehicle", true)
	]]):format(cfg().width, height)
end

local function NewHeader(name, kind, template)
	local h = CreateFrame("Frame", name, Raid.holder, template or "SecureGroupHeaderTemplate")
	h.SUIKind = kind
	h:SetAttribute("template", UF.BUTTON_TEMPLATE)
	h:SetAttribute("templateType", "Button")
	return h
end

-- Every button a header has made that isn't a raid frame yet.
function Raid.Adopt(h)
	local i = 1
	while true do
		local button = h:GetAttribute("child" .. i)
		if not button then break end
		if not button.SUIRaid then Raid.Dress(button, h.SUIKind) end
		i = i + 1
	end
end

-- Sets a header up. While it's hidden the header doesn't react, so the list goes in as one change.
-- Asking it to start "count" places before the first unit makes it build that many buttons now.
-- attrs: { name, value, name, value, ... } (a value may be nil)
function Raid.Configure(h, attrs, n, count)
	h:Hide()
	-- The header only clears the anchors of buttons it hides. One that stays shown would keep its
	-- old anchor next to the new one after a change of shape, and the block comes out as a staircase.
	local k = 1
	while true do
		local button = h:GetAttribute("child" .. k)
		if not button then break end
		button:ClearAllPoints()
		k = k + 1
	end
	for i = 1, n, 2 do h:SetAttribute(attrs[i], attrs[i + 1]) end
	h:SetAttribute("initialConfigFunction", ButtonSetup(h.SUIKind == "pet" and cfg().petHeight or cfg().height))
	h:SetAttribute("startingIndex", 1 - count)
	h:Show()
	h:SetAttribute("startingIndex", h.SUIPreview and (1 - h.SUIPreview) or 1)
	Raid.Adopt(h)
end

local function GroupList(n)
	local t = {}
	for i = 1, n do t[i] = i end
	return table.concat(t, ",")
end

-- the attribute list for each header, from the settings. Returns { header = { attrs, n, count } }.
function Raid.HeaderPlan()
	local c = cfg()
	local columns = c.layout ~= "ROWS"
	local point = columns and "TOP" or "LEFT"
	local xOffset, yOffset = columns and 0 or c.spacing, columns and -c.spacing or 0
	local sortMethod = c.sort == "NAME" and "NAME" or "INDEX"
	local byRole = c.sort == "ROLE" -- tanks, then healers, then damage
	local plan = {}
	local function base(showRaid, showParty)
		return { "showRaid", showRaid, "showParty", showParty, "showPlayer", true, "showSolo", false,
			"point", point, "xOffset", xOffset, "yOffset", yOffset, "sortDir", "ASC",
			"columnSpacing", c.spacing, "columnAnchorPoint", columns and "LEFT" or "TOP" }
	end
	-- a value can be nil (clearing an attribute), so the list keeps its own length
	local function put(t, k, v) local n = (t.n or #t); t[n + 1] = k; t[n + 2] = v; t.n = n + 2 end
	for i = 1, MAX_GROUPS do
		local t
		if c.keepGroups then
			local on = i <= c.groups
			t = base(on, (on and i == 1 and c.showParty) and true or false)
			t.n = #t
			put(t, "groupFilter", tostring(i))
			-- by role works inside each group too
			put(t, "groupBy", byRole and "ASSIGNEDROLE" or nil); put(t, "groupingOrder", byRole and ROLE_ORDER or nil)
			put(t, "sortMethod", sortMethod); put(t, "unitsPerColumn", GROUP_SIZE); put(t, "maxColumns", 1)
			plan[i] = { t, t.n, GROUP_SIZE }
		else
			-- one list: the first header holds everyone, the rest stay empty
			local on = i == 1
			t = base(on, (on and c.showParty) and true or false)
			t.n = #t
			put(t, "groupFilter", GroupList(c.groups))
			if byRole then
				put(t, "groupBy", "ASSIGNEDROLE"); put(t, "groupingOrder", ROLE_ORDER)
			elseif c.sort == "NAME" then
				put(t, "groupBy", nil); put(t, "groupingOrder", nil)
			else
				put(t, "groupBy", "GROUP"); put(t, "groupingOrder", GroupList(MAX_GROUPS))
			end
			put(t, "sortMethod", sortMethod); put(t, "unitsPerColumn", c.perColumn)
			put(t, "maxColumns", c.maxColumns) -- anyone past perColumn x maxColumns isn't shown
			plan[i] = { t, t.n, on and MAX_GROUPS * GROUP_SIZE or 1 }
		end
	end
	local function extra(on, count)
		local t = base(on and true or false, on and c.showParty and true or false)
		t.n = #t
		put(t, "sortMethod", sortMethod); put(t, "unitsPerColumn", GROUP_SIZE)
		put(t, "maxColumns", math.ceil(count / GROUP_SIZE))
		return t
	end
	local tanks = extra(c.mainTanks, TANK_BUTTONS)
	put(tanks, "roleFilter", "MAINTANK,MAINASSIST"); put(tanks, "groupFilter", nil)
	plan.tanks = { tanks, tanks.n, c.mainTanks and TANK_BUTTONS or 1 }
	local pets = extra(c.pets, PET_BUTTONS)
	plan.pets = { pets, pets.n, c.pets and PET_BUTTONS or 1 }
	return plan
end

-- how big a block of "rows" units by "cols" columns is, either way round
local function BlockSize(c, perColumn, numColumns, gap, unitHeight)
	local along = perColumn * unitHeight + (perColumn - 1) * c.spacing
	local alongW = perColumn * c.width + (perColumn - 1) * c.spacing
	if c.layout ~= "ROWS" then
		return numColumns * (c.width + gap) - gap, along
	end
	return alongW, numColumns * (unitHeight + gap) - gap
end

-- groups that have someone in them, for closing the gaps empty ones would leave
function Raid.FilledGroups()
	local filled = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() or 0 do
			local _, _, subgroup = GetRaidRosterInfo(i)
			if subgroup then filled[subgroup] = true end
		end
	else
		filled[1] = true
	end
	return filled
end

-- Where each header goes. Runs out of combat; a group that fills or empties in a fight keeps its
-- place until the fight is over.
function Raid.Arrange()
	local holder = Raid.holder
	if not holder then return end
	local c = cfg()
	local columns = c.layout ~= "ROWS"
	local previewGroups = Raid.testMode and math.ceil(c.previewSize / GROUP_SIZE) or 0
	local filled = (c.compact and c.keepGroups and not Raid.testMode) and Raid.FilledGroups() or nil
	local slot = 0
	local key = {}
	for i = 1, MAX_GROUPS do
		local h = Raid.headers[i]
		local used = not filled or filled[i]
		if c.keepGroups and Raid.testMode then used = i <= previewGroups end
		if not c.keepGroups then used = i == 1 end
		h:ClearAllPoints()
		if used then
			if columns then
				h:SetPoint("TOPLEFT", holder, "TOPLEFT", slot * (c.width + c.groupSpacing), 0)
			else
				h:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -slot * (c.height + c.groupSpacing))
			end
			slot = slot + 1
		else
			h:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
		end
		key[i] = used and "1" or "0"
	end
	Raid.arranged = table.concat(key)

	-- the main block, then main tanks, then pets, one after another across the groups' direction
	local mainW, mainH
	if c.keepGroups then
		mainW, mainH = BlockSize(c, GROUP_SIZE, c.groups, c.groupSpacing, c.height)
	else
		local lines = math.min(c.maxColumns, math.ceil(c.groups * GROUP_SIZE / c.perColumn))
		mainW, mainH = BlockSize(c, c.perColumn, lines, c.spacing, c.height)
	end
	local offset = (columns and mainH or mainW) + c.groupSpacing
	local totalW, totalH = mainW, mainH
	local function place(h, on, numColumns, unitHeight)
		h:ClearAllPoints()
		if columns then h:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -offset) else h:SetPoint("TOPLEFT", holder, "TOPLEFT", offset, 0) end
		if not on then return end
		local w, hgt = BlockSize(c, GROUP_SIZE, numColumns, c.spacing, unitHeight)
		if columns then
			totalH = offset + hgt
			totalW = math.max(totalW, w)
			offset = offset + hgt + c.groupSpacing
		else
			totalW = offset + w
			totalH = math.max(totalH, hgt)
			offset = offset + w + c.groupSpacing
		end
	end
	place(Raid.headers.tanks, c.mainTanks, TANK_BUTTONS / GROUP_SIZE, c.height)
	place(Raid.headers.pets, c.pets, PET_BUTTONS / GROUP_SIZE, c.petHeight)
	holder:SetSize(math.max(totalW, 1), math.max(totalH, 1))
end

-- has a group filled or emptied since the headers were last placed?
function Raid.NeedsArrange()
	local c = cfg()
	if not (c.compact and c.keepGroups) or Raid.testMode then return false end
	local filled = Raid.FilledGroups()
	local key = {}
	for i = 1, MAX_GROUPS do key[i] = filled[i] and "1" or "0" end
	return table.concat(key) ~= Raid.arranged
end

-- Headers, buttons and places, from the settings. Out of combat.
function Raid.Build()
	local plan = Raid.HeaderPlan()
	for i = 1, MAX_GROUPS do
		local p = plan[i]
		Raid.Configure(Raid.headers[i], p[1], p[2], p[3])
	end
	Raid.Configure(Raid.headers.tanks, plan.tanks[1], plan.tanks[2], plan.tanks[3])
	Raid.Configure(Raid.headers.pets, plan.pets[1], plan.pets[2], plan.pets[3])
	for _, f in ipairs(Raid.buttons) do
		local ok, err = pcall(Raid.LayoutButton, f)
		if not ok then ns.Error(err) end
	end
	Raid.Arrange()
end

---------------------------------------------------------------------------
-- Blizzard's raid frames
---------------------------------------------------------------------------
local function HideBlizzardNow()
	local container = _G.CompactRaidFrameContainer
	if not (container and container:IsShown() and Raid.HidesBlizzard()) then return end
	ns:RunOOC(function()
		if Raid.HidesBlizzard() and container:IsShown() then container:Hide() end
	end)
end

local function WatchBlizzard()
	if _G.CompactRaidFrameManager_UpdateContainerVisibility then
		hooksecurefunc("CompactRaidFrameManager_UpdateContainerVisibility", HideBlizzardNow)
	end
	if _G.CompactRaidFrameContainer then _G.CompactRaidFrameContainer:HookScript("OnShow", HideBlizzardNow) end
	HideBlizzardNow()
end

---------------------------------------------------------------------------
-- Where it shows
---------------------------------------------------------------------------
-- Not in arenas by default: Solo Shuffle counts as a raid group, and the party frames are your
-- team there.
function Raid:UpdateVisibility()
	local holder = Raid.holder
	if not holder then return end
	ns:RunOOC(function()
		local c = cfg()
		local _, t = IsInInstance()
		local hide = (c.hideInArena and t == "arena") or (c.hideInBattlegrounds and t == "pvp")
		if ns.unlocked or Raid.testMode then hide = false end
		holder:SetShown(not hide)
	end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function Each(fn)
	for _, f in ipairs(Raid.buttons) do
		if f.unit and not f.preview and f:IsShown() then fn(f) end
	end
end

local function ForUnit(fn)
	return function(_, unit)
		if issecret(unit) or unit == nil then return Each(fn) end
		local f = Raid.byUnit[unit]
		if f and not f.preview then fn(f) end
	end
end

local function UpdateRange()
	local c = cfg()
	local fade, alpha = c.rangeFade, c.rangeAlpha
	for _, f in ipairs(Raid.buttons) do
		if f:IsShown() then
			if f.preview then
				f:SetAlpha(f.previewAlpha or 1)
			elseif not f.unit or not fade or f.isMe then
				f:SetAlpha(1)
			else
				f:SetAlphaFromBoolean(UnitInRange(f.unit), 1, alpha)
			end
		end
	end
end

local function OnRoster()
	Each(function(f)
		local role = RoleOf(f)
		Raid.UpdatePower(f, WantPower(f))
		Raid.UpdateRole(f, role)
		Raid.UpdateCenter(f)
	end)
	if not Raid.holder then return end
	ns:RunOOC(function()
		-- buttons the header had to make in a fight get their look now
		for i = 1, MAX_GROUPS do Raid.Adopt(Raid.headers[i]) end
		Raid.Adopt(Raid.headers.tanks)
		Raid.Adopt(Raid.headers.pets)
		if Raid.NeedsArrange() then Raid.Arrange() end
	end)
end

local function RegisterEvents()
	ns:On("GROUP_ROSTER_UPDATE", OnRoster)
	ns:On("PLAYER_ROLES_ASSIGNED", OnRoster)
	ns:On("PLAYER_REGEN_ENABLED", OnRoster)
	ns:On("PLAYER_ENTERING_WORLD", function() Raid:UpdateVisibility(); OnRoster() end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() Raid:UpdateVisibility() end)
	ns:On("PLAYER_TARGET_CHANGED", function() Each(Raid.UpdateHighlight) end)
	ns:On("RAID_TARGET_UPDATE", function() Each(UF.UpdateMarker) end)
	ns:On("UNIT_THREAT_SITUATION_UPDATE", ForUnit(Raid.UpdateAggro))
	ns:On("INCOMING_RESURRECT_CHANGED", ForUnit(Raid.UpdateCenter))
	ns:On("INCOMING_SUMMON_CHANGED", ForUnit(Raid.UpdateCenter))
	ns:On("UNIT_PHASE", ForUnit(Raid.UpdateCenter))
	ns:On("UNIT_OTHER_PARTY_CHANGED", ForUnit(Raid.UpdateCenter))
	ns:On("UNIT_ENTERED_VEHICLE", ForUnit(Raid.Resolve))
	ns:On("UNIT_EXITED_VEHICLE", ForUnit(Raid.Resolve))
	ns:On("READY_CHECK", function() Raid.readyRun = (Raid.readyRun or 0) + 1; Each(Raid.UpdateReady) end)
	ns:On("READY_CHECK_CONFIRM", function() Each(Raid.UpdateReady) end)
	ns:On("READY_CHECK_FINISHED", Raid.FinishReady)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function Raid:Init()
	local c = cfg()
	if not c.enabled then return end
	local holder = CreateFrame("Frame", "StinkieUI_RaidHolder", UIParent)
	Raid.holder = holder
	holder:SetSize(1, 1)
	ns:RegisterMover("raid", holder, "Raid Frames",
		function() return cfg().point end,
		function(p) cfg().point = p end)
	for i = 1, MAX_GROUPS do
		Raid.headers[i] = NewHeader("StinkieUI_RaidGroup" .. i, "raid")
	end
	Raid.headers.tanks = NewHeader("StinkieUI_RaidTanks", "tank")
	Raid.headers.pets = NewHeader("StinkieUI_RaidPets", "pet", "SecureGroupPetHeaderTemplate")

	Raid.rangeDriver = CreateFrame("Frame")
	local since = 0
	Raid.rangeDriver:SetScript("OnUpdate", ns.Timed("Raid frames", function(_, elapsed)
		since = since + elapsed
		if since < RANGE_TICK then return end
		since = 0
		UpdateRange()
	end))

	RegisterEvents()
	WatchBlizzard()
	table.insert(ns.lockCallbacks, function(unlocked)
		if unlocked then
			Raid.testFromUnlock = not Raid.testMode
			Raid:SetTestMode(true)
		elseif Raid.testFromUnlock then
			Raid.testFromUnlock = nil
			Raid:SetTestMode(false)
		end
	end)
	Raid:Refresh()
end

function Raid:Refresh()
	local holder = Raid.holder
	if not holder then return end
	ns:RunOOC(function()
		holder:SetScale(ns.db.scale)
		ns:ApplyPoint(holder, cfg().point)
		Raid.Build()
		-- a setting can change which header holds how many stand-ins (one list or groups, how many)
		if Raid.testMode then Raid.ApplyPreview() end
		for i, f in ipairs(Raid.buttons) do
			if f.preview then
				local ok, err = pcall(Raid.FillPreview, f, f.previewIndex or i)
				if not ok then ns.Error(err) end
			elseif f.unit and f:IsShown() then
				UF.SafeUpdateAll(f)
			end
		end
		Raid:UpdateVisibility()
		HideBlizzardNow()
	end)
end

---------------------------------------------------------------------------
-- Test mode: stand-in raiders, so the frames can be sized and placed without a raid
---------------------------------------------------------------------------
local PREVIEW_NAMES = { "Tankie", "Pinkie", "Minkie", "Winkie", "Hinkie", "Einkie", "Monkie", "Zinkie", "Rinkie", "Linkie" }
local PREVIEW_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "HUNTER", "EVOKER", "MONK", "DRUID", "PALADIN", "SHAMAN",
	"WARLOCK", "DEATHKNIGHT", "DEMONHUNTER" }
local PREVIEW_HEALTH = { 1, 0.82, 0.64, 1, 0.37, 0.93, 0, 0.71, 1, 0.55 }

-- which stand-in (by place) has what
local PREVIEW_DEFENSIVES = { [1] = 871, [8] = 642, [15] = 45438 }
local PREVIEW_DEBUFFS = { [2] = 1, [4] = 2, [6] = 1, [10] = 3, [13] = 3, [18] = 2 }
local PREVIEW_BOSS = { [3] = 1, [11] = 2, [16] = 1 }
local PREVIEW_SPELLS = { debuff = { 589, 172, 980 }, buff = { 774, 139, 17 }, boss = { 348, 603 } }
local MAGIC_COLOR = { 0.2, 0.6, 1 }

-- who stands on the i-th preview button: every group gets a tank-or-damage mix and one healer
function Raid.PreviewData(i)
	local inGroup = (i - 1) % GROUP_SIZE + 1
	local hp = PREVIEW_HEALTH[(i - 1) % #PREVIEW_HEALTH + 1]
	local dead = hp == 0
	return {
		name = PREVIEW_NAMES[(i - 1) % #PREVIEW_NAMES + 1],
		class = PREVIEW_CLASSES[(i - 1) % #PREVIEW_CLASSES + 1],
		hp = hp, dead = hp == 0,
		role = (i <= 2 and "TANK") or (inGroup == 2 and "HEALER") or "DAMAGER",
		ready = (i % 7 == 0 and "notready") or (i % 5 == 0 and "waiting") or nil,
		aggro = i == 1, target = i == 3, heal = (i % 4 == 0) and 0.15 or 0,
		def = not dead and PREVIEW_DEFENSIVES[i] or nil, -- a big defensive that's running
		far = i == 9 or i == 14,                         -- out of range
		debuffs = not dead and PREVIEW_DEBUFFS[i] or 0,  -- how many debuffs
		dispel = i == 4 or i == 13,                      -- the first of them is one you can dispel
		boss = not dead and PREVIEW_BOSS[i] or 0,        -- boss debuffs (the game's own icons, top right)
		buffs = dead and 0 or (i % 3 == 2 and 2) or (i % 5 == 0 and 1) or 0,
	}
end

local function PreviewIcon(f, key)
	f.SUIPreviewIcons = f.SUIPreviewIcons or {}
	local p = f.SUIPreviewIcons[key]
	if not p then
		p = CreateFrame("Frame", nil, f)
		p:SetFrameLevel(f.TextLayer:GetFrameLevel() + 2)
		p.tex = p:CreateTexture(nil, "ARTWORK")
		p.tex:SetAllPoints()
		ns.IconBorder(p)
		f.SUIPreviewIcons[key] = p
	end
	return p
end

function Raid.HidePreview(f)
	f.previewAlpha = nil
	if f.SUIPreviewIcons then
		for _, p in pairs(f.SUIPreviewIcons) do p:Hide() end
	end
	if f.PreviewDispel then f.PreviewDispel:Hide() end
end

-- Stand-in icons, drawn by us where the real ones go (the real ones are the game's, and need a unit).
function Raid.LayoutPreview(f, d)
	local c = cfg()
	if f.SUIRaid == "pet" then return Raid.HidePreview(f) end
	local px = ns.Pixel(f)
	local function icon(key, spell, size, on, point, x, y)
		local p = PreviewIcon(f, key)
		p:SetSize(size, size)
		p:ClearAllPoints()
		p:SetPoint(point, f.Health, point, x, y)
		p.tex:SetTexture(C_Spell.GetSpellTexture(spell) or 134400)
		ns.ZoomIcon(p.tex)
		p:SetShown(on and true or false)
		return p
	end
	local def = icon("def", d.def or PREVIEW_SPELLS.debuff[1], c.defensiveSize, c.defensiveIcon and d.def, "CENTER", 0, 0)
	if not def.cd then
		def.cd = CreateFrame("Cooldown", nil, def, "CooldownFrameTemplate")
		def.cd:SetAllPoints()
		def.cd:SetDrawEdge(false)
		def.cd:SetReverse(true)
		def.cd:SetHideCountdownNumbers(true)
	end
	if d.def then def.cd:SetCooldown(GetTime() - 2, 8) end
	for k = 1, #PREVIEW_SPELLS.debuff do
		local canDispel = d.dispel and k == 1
		local on = k <= math.min(d.debuffs, c.debuffMax) and (c.debuffs == "all" or (c.debuffs ~= "none" and canDispel))
		local p = icon("debuff" .. k, PREVIEW_SPELLS.debuff[k], c.debuffSize, on, "BOTTOMLEFT", 2 + (k - 1) * (c.debuffSize + 1), 2)
		if k == 1 then
			p.edge = p.edge or NewBorder(p, p:GetFrameLevel() + 1)
			LayoutBorder(p.edge, px)
			for _, e in ipairs(p.edge.edges) do e:SetColorTexture(MAGIC_COLOR[1], MAGIC_COLOR[2], MAGIC_COLOR[3], 1) end
			p.edge:SetShown(canDispel and true or false)
		end
	end
	for k = 1, #PREVIEW_SPELLS.buff do
		icon("buff" .. k, PREVIEW_SPELLS.buff[k], c.buffSize, c.buffs and k <= math.min(d.buffs, c.buffMax),
			"BOTTOMRIGHT", -2 - (k - 1) * (c.buffSize + 1), 2)
	end
	for k = 1, #PREVIEW_SPELLS.boss do
		local p = icon("boss" .. k, PREVIEW_SPELLS.boss[k], c.privateSize, c.privateAuras and k <= math.min(d.boss, c.privateMax),
			"TOPRIGHT", 0, 0)
		p:ClearAllPoints()
		p:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2 - (k - 1) * (c.privateSize + 1), -2)
	end
	-- the outline a debuff you can dispel puts round the whole frame
	if not f.PreviewDispel then f.PreviewDispel = NewBorder(f, f.TextLayer:GetFrameLevel() + 1) end
	LayoutBorder(f.PreviewDispel, px * 2)
	for _, e in ipairs(f.PreviewDispel.edges) do e:SetColorTexture(MAGIC_COLOR[1], MAGIC_COLOR[2], MAGIC_COLOR[3], 1) end
	f.PreviewDispel:SetShown(c.dispelHighlight and d.dispel and d.debuffs > 0 and c.debuffs ~= "none" or false)
	f.previewAlpha = (c.rangeFade and d.far) and c.rangeAlpha or 1
end

function Raid.FillPreview(f, i)
	local d = Raid.PreviewData(i)
	local c = cfg()
	f.previewIndex, f.previewRole = i, d.role
	f.Health:SetMinMaxValues(0, 1)
	f.Health:SetValue(d.hp)
	local col = C_ClassColor.GetClassColor(d.class)
	if d.dead then
		f.Health:SetStatusBarColor(0.35, 0.35, 0.35)
	elseif col and c.classColor then
		f.Health:SetStatusBarColor(col:GetRGB())
	else
		local hc = ns.db.colors.health
		f.Health:SetStatusBarColor(hc[1], hc[2], hc[3])
	end
	local limit = c.nameMaxChars or 0
	f.Name:SetText(limit > 0 and ns.Utf8Head(d.name, limit) or d.name)
	local pet = f.SUIRaid == "pet"
	if pet then
		f.HealthText:SetText("")
	elseif d.dead then
		f.HealthText:SetText(DEAD)
	elseif c.healthText == "none" then
		f.HealthText:SetText("")
	else
		f.HealthText:SetText(math.floor(d.hp * 100) .. "%")
	end
	f.Absorb:SetValue(0)
	f.OverAbsorb:SetAlpha(0)
	f.HealPredict:SetMinMaxValues(0, 1)
	f.HealPredict:SetValue(c.healPrediction and not d.dead and d.heal or 0)
	f.HealAbsorb:SetValue(0)
	local showPower = not pet and (c.power == "all" or (c.power == "healer" and d.role == "HEALER"))
	Raid.UpdatePower(f, showPower)
	f.Power:SetMinMaxValues(0, 1)
	f.Power:SetValue(0.7)
	f.Power:SetStatusBarColor(0, 0.44, 0.87)
	Raid.UpdateRole(f, d.role)
	f.Leader:SetAlpha(1)
	f.Leader:SetShown(f.leaderShown and i == 1 or false)
	if f.markerShown and i <= 8 then SetRaidTargetIconTexture(f.Marker, i) end
	f.Marker:SetShown(f.markerShown and i <= 2 or false)
	Raid.ShowReady(f, not pet and d.ready or nil)
	f.CenterIcon:Hide()
	f.Highlight:SetAlpha(c.targetHighlight and d.target and 1 or 0)
	for _, edge in ipairs(f.Aggro.edges) do edge:SetColorTexture(AGGRO_FALLBACK[1], AGGRO_FALLBACK[2], AGGRO_FALLBACK[3], 1) end
	f.Aggro:SetShown(c.aggro and d.aggro and true or false)
	Raid.LayoutPreview(f, d)
	f:SetAlpha(f.previewAlpha or 1)
end

-- how many stand-ins a header shows in test mode
local function PreviewCount(key)
	local c = cfg()
	if key == "tanks" then return c.mainTanks and 2 or nil end
	if key == "pets" then return c.pets and GROUP_SIZE or nil end
	if not c.keepGroups then return key == 1 and c.previewSize or nil end
	return key <= math.ceil(c.previewSize / GROUP_SIZE) and GROUP_SIZE or nil
end

function Raid:SetTestMode(on)
	if not Raid.holder then return end
	if InCombatLockdown() then
		ns:Print("Can't toggle raid test mode in combat.")
		return
	end
	Raid.testMode = on or nil
	Raid.ApplyPreview()
	Raid.Arrange()
	Raid:UpdateVisibility()
end

-- Puts the stand-ins on (or takes them off) each header's buttons, from the settings as they are now.
function Raid.ApplyPreview()
	local on = Raid.testMode
	local n = 0
	local function apply(key)
		local h = Raid.headers[key]
		h.SUIPreview = on and PreviewCount(key) or nil
		-- starting before the first unit shows that many buttons with nobody on them
		h:SetAttribute("startingIndex", h.SUIPreview and (1 - h.SUIPreview) or 1)
		Raid.Adopt(h)
		local i = 1
		while true do
			local f = h:GetAttribute("child" .. i)
			if not f then break end
			if h.SUIPreview and i <= h.SUIPreview then
				n = n + 1
				if not f.preview then
					f.preview = true
					f:UnregisterAllEvents()
					WatchAuras(f)
				end
				local ok, err = pcall(Raid.FillPreview, f, n)
				if not ok then ns.Error(err) end
			elseif f.preview then
				f.preview, f.previewIndex, f.previewRole = nil, nil, nil
				Raid.ShowReady(f, nil)
				f.Aggro:Hide()
				f.Highlight:SetAlpha(0)
				Raid.HidePreview(f)
				f:SetAlpha(1)
				f.unit = nil -- so the unit it really has is set up again
				Raid.Resolve(f)
			end
			i = i + 1
		end
	end
	for i = 1, MAX_GROUPS do apply(i) end
	apply("tanks")
	apply("pets")
end

ns:RegisterModule("Raid", Raid)
