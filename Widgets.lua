-- StinkieUI: shared flat widgets (bars, 1px borders, text) and color helpers.
local _, ns = ...

local issecret = ns.issecret

-- One physical pixel in a region's coordinate space.
function ns.Pixel(region)
	return PixelUtil.ConvertPixelsToUIForRegion(1, region)
end

-- Flat background plus a 1px black border drawn outside the frame edges.
function ns.CreateBackdrop(frame, alpha)
	if frame.SUIBorder then return frame.SUIBorder end
	local holder = {}
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetAllPoints()
	local c = ns.db.colors.background
	bg:SetColorTexture(c[1], c[2], c[3], alpha or c[4])
	holder.bg = bg

	local edges = {}
	for i = 1, 4 do
		local t = frame:CreateTexture(nil, "BORDER", nil, 7)
		t:SetColorTexture(0, 0, 0, 1)
		edges[i] = t
	end
	holder.edges = edges
	frame.SUIBorder = holder
	ns.UpdateBackdrop(frame)
	return holder
end

function ns.UpdateBackdrop(frame)
	local holder = frame.SUIBorder
	if not holder then return end
	local px = ns.Pixel(frame)
	local e = holder.edges
	e[1]:ClearAllPoints() -- top
	e[1]:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -px, 0)
	e[1]:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", px, 0)
	e[1]:SetHeight(px)
	e[2]:ClearAllPoints() -- bottom
	e[2]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -px, 0)
	e[2]:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", px, 0)
	e[2]:SetHeight(px)
	e[3]:ClearAllPoints() -- left
	e[3]:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
	e[3]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
	e[3]:SetWidth(px)
	e[4]:ClearAllPoints() -- right
	e[4]:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
	e[4]:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
	e[4]:SetWidth(px)
end

function ns.SetBorderColor(frame, r, g, b, a)
	local holder = frame.SUIBorder
	if not holder then return end
	for i = 1, 4 do holder.edges[i]:SetColorTexture(r, g, b, a or 1) end
end

function ns.CreateBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(ns.TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	return bar
end

function ns.CreateText(parent, size, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	ns.SetFont(fs, size or 12, "OUTLINE")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

-- A raid target marker on a texture. In Midnight the index can be secret: it can't be tested, so
-- it goes straight to Blizzard's setter, and if that refuses it the marker stays hidden.
ns.MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
function ns.UpdateMarker(tex, unit)
	local index = unit and GetRaidTargetIndex(unit)
	if not issecret(index) and index == nil then
		tex:Hide()
		return
	end
	tex:SetShown(pcall(SetRaidTargetIconTexture, tex, index))
end

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------
local reactionColors = {
	[1] = CreateColor(0.78, 0.20, 0.20), [2] = CreateColor(0.78, 0.20, 0.20),
	[3] = CreateColor(0.80, 0.40, 0.20), [4] = CreateColor(0.90, 0.80, 0.20),
	[5] = CreateColor(0.25, 0.70, 0.30), [6] = CreateColor(0.25, 0.70, 0.30),
	[7] = CreateColor(0.25, 0.70, 0.30), [8] = CreateColor(0.25, 0.70, 0.30),
}
local grey = CreateColor(0.5, 0.5, 0.5)

-- Returns a ColorMixin. Works when the unit's class is a secret value.
function ns.GetUnitClassColor(unit)
	local _, class = UnitClass(unit)
	if issecret(class) then
		return C_ClassColor.GetClassColor(class)
	elseif class then
		return C_ClassColor.GetClassColor(class) or grey
	end
	return grey
end

function ns.GetHealthColor(unit, forceClass)
	if not UnitIsConnected(unit) then return grey end
	if UnitIsPlayer(unit) or UnitInPartyIsAI(unit) then
		if forceClass or ns.db.classColorHealth then
			return ns.GetUnitClassColor(unit)
		end
		local c = ns.db.colors.health
		return CreateColor(c[1], c[2], c[3])
	end
	if not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then return grey end
	local reaction = UnitReaction(unit, "player")
	return reaction and reactionColors[reaction] or grey
end

function ns.GetPowerColor(unit)
	local pType, pToken = UnitPowerType(unit)
	-- either can be secret on enemy units: check before using them as table keys
	local c
	if not issecret(pToken) and pToken ~= nil then c = PowerBarColor[pToken] end
	if not c and not issecret(pType) and pType ~= nil then c = PowerBarColor[pType] end
	c = c or PowerBarColor.MANA
	return c.r, c.g, c.b
end

---------------------------------------------------------------------------
-- Health text (secret-safe: only format/abbreviate, never compare)
---------------------------------------------------------------------------
function ns.FormatHealth(unit, mode)
	if mode == "none" then return "" end
	if UnitIsDeadOrGhost(unit) then return DEAD end
	if not UnitIsConnected(unit) then return PLAYER_OFFLINE end
	if mode == "percent" then
		return string.format("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
	elseif mode == "current" then
		return AbbreviateNumbers(UnitHealth(unit))
	elseif mode == "both" then
		return string.format("%s  %d%%", AbbreviateNumbers(UnitHealth(unit)), UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
	end
	return ""
end

---------------------------------------------------------------------------
-- Health bar layers: dark empty area, shield after current health, and an
-- "overshield" drawn backwards over the top half when the shield is bigger
-- than the missing health. Secret-safe: the overflow test comes from Blizzard's
-- heal prediction calculator and is applied with SetAlphaFromBoolean.
---------------------------------------------------------------------------
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

function ns.CreateHealthLayers(owner, health)
	local bg = health:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	owner.HealthBg = bg

	local absorb = ns.CreateBar(health)
	absorb:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT")
	absorb:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT")
	owner.Absorb = absorb

	local over = ns.CreateBar(health)
	over:SetReverseFill(true)
	over:SetPoint("TOPLEFT")
	over:SetPoint("TOPRIGHT")
	over:SetFrameLevel(health:GetFrameLevel() + 2)
	over:SetAlpha(0)
	owner.OverAbsorb = over

	if CreateUnitHealPredictionCalculator then
		local calc = CreateUnitHealPredictionCalculator()
		if calc.SetDamageAbsorbClampMode and Enum.UnitDamageAbsorbClampMode then
			calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals)
		end
		owner.calc = calc
	end
	ns.ColorHealthLayers(owner)
end

function ns.ColorHealthLayers(owner)
	local c = ns.db.colors
	local bg, a, o = c.healthBackground, c.absorb, c.overAbsorb
	owner.HealthBg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
	owner.Absorb:SetStatusBarColor(a[1], a[2], a[3], a[4] or 0.55)
	owner.OverAbsorb:SetStatusBarColor(o[1], o[2], o[3], o[4] or 0.85)
end

function ns.LayoutHealthLayers(owner, w, h)
	owner.Absorb:SetSize(w, h)
	owner.OverAbsorb:SetHeight(math.max(1, math.floor(h / 2 + 0.5)))
	ns.ColorHealthLayers(owner)
end

-- immediate: snap instead of animating (new target/focus/unit), so bars never "fill up".
function ns.UpdateHealthBar(owner, unit, immediate)
	local health = owner.Health
	-- disconnected: a full grey bar. The game can report 0 max health for an offline player,
	-- which would leave the bar empty, so it's drawn on its own 0..1 scale.
	local connected = UnitIsConnected(unit)
	if not issecret(connected) and not connected then
		health:SetMinMaxValues(0, 1)
		health:SetValue(1, IMMEDIATE)
		if health.SetToTargetValue then health:SetToTargetValue() end
		owner.Absorb:SetValue(0)
		owner.OverAbsorb:SetAlpha(0)
		return
	end
	local max = UnitHealthMax(unit)
	health:SetMinMaxValues(0, max)
	health:SetValue(UnitHealth(unit), immediate and IMMEDIATE or SMOOTH)
	if immediate and health.SetToTargetValue then health:SetToTargetValue() end

	local total = UnitGetTotalAbsorbs(unit)
	owner.Absorb:SetMinMaxValues(0, max)
	owner.OverAbsorb:SetMinMaxValues(0, max)
	local calc = owner.calc
	if calc then
		UnitGetDetailedHealPrediction(unit, "player", calc)
		local amount, clamped = calc:GetDamageAbsorbs()
		owner.Absorb:SetValue(amount)
		owner.OverAbsorb:SetValue(total)
		owner.OverAbsorb:SetAlphaFromBoolean(clamped, 1, 0)
	else
		owner.Absorb:SetValue(total)
		owner.OverAbsorb:SetAlpha(0)
	end
end

---------------------------------------------------------------------------
-- Shared square icon style (custom cooldown bars and skinned Blizzard icons).
-- Borders live on a child frame we own, so nothing is written into Blizzard's tables.
---------------------------------------------------------------------------
local iconBorders = setmetatable({}, { __mode = "k" })

function ns.IconBorder(frame)
	local b = iconBorders[frame]
	if not b then
		b = CreateFrame("Frame", nil, frame)
		b:SetAllPoints()
		ns.CreateBackdrop(b, 0) -- edges only (drawn outside the icon), so it can never cover the icon
		iconBorders[frame] = b
	end
	ns.UpdateBackdrop(b)
	return b
end

function ns.ZoomIcon(texture)
	local z = (ns.db and ns.db.cooldowns.iconZoom) or 0.08
	texture:SetTexCoord(z, 1 - z, z, 1 - z)
end

---------------------------------------------------------------------------
-- Glow: a colored ring just outside a frame, optionally pulsing. It's a child of the frame,
-- so it only shows while the frame does (aura icons included).
---------------------------------------------------------------------------
local glows = setmetatable({}, { __mode = "k" })

function ns.ApplyGlow(frame, cfg)
	local g = glows[frame]
	if not g then
		g = CreateFrame("Frame", nil, frame)
		g:SetFrameLevel(frame:GetFrameLevel() + 8)
		g.edges = {}
		for i = 1, 4 do g.edges[i] = g:CreateTexture(nil, "OVERLAY") end
		-- soft halo fading out from the ring
		g.soft = {}
		for i = 1, 4 do
			local t = g:CreateTexture(nil, "ARTWORK")
			t:SetTexture([[Interface\Buttons\WHITE8X8]])
			t:SetBlendMode("ADD")
			g.soft[i] = t
		end
		local anim = g:CreateAnimationGroup()
		anim:SetLooping("BOUNCE")
		local a = anim:CreateAnimation("Alpha")
		a:SetFromAlpha(1)
		a:SetToAlpha(0.35)
		a:SetDuration(0.6)
		a:SetSmoothing("IN_OUT")
		g.anim = anim
		glows[frame] = g
	end
	local style = cfg and cfg.glow or "none"
	if style == "none" then
		g:Hide()
		g.anim:Stop()
		return g
	end
	local c = cfg.glowColor or { 1, 0.85, 0.2 }
	local px = ns.Pixel(frame)
	local t = math.max(1, cfg.glowThickness or 2) * px
	local o = px + t -- outside the 1px black border
	g:ClearAllPoints()
	g:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
	g:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
	local e = g.edges
	for i = 1, 4 do e[i]:SetColorTexture(c[1], c[2], c[3], 1) end
	e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(t)
	e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(t)
	e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(t)
	e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(t)
	local h = 2 * t + 3 * px -- halo width
	local near = CreateColor(c[1], c[2], c[3], 0.6)
	local far = CreateColor(c[1], c[2], c[3], 0)
	local sft = g.soft
	sft[1]:ClearAllPoints(); sft[1]:SetPoint("BOTTOMLEFT", g, "TOPLEFT", 0, 0); sft[1]:SetPoint("BOTTOMRIGHT", g, "TOPRIGHT", 0, 0); sft[1]:SetHeight(h)
	sft[1]:SetGradient("VERTICAL", near, far)
	sft[2]:ClearAllPoints(); sft[2]:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, 0); sft[2]:SetPoint("TOPRIGHT", g, "BOTTOMRIGHT", 0, 0); sft[2]:SetHeight(h)
	sft[2]:SetGradient("VERTICAL", far, near)
	sft[3]:ClearAllPoints(); sft[3]:SetPoint("TOPRIGHT", g, "TOPLEFT", 0, h); sft[3]:SetPoint("BOTTOMRIGHT", g, "BOTTOMLEFT", 0, -h); sft[3]:SetWidth(h)
	sft[3]:SetGradient("HORIZONTAL", far, near)
	sft[4]:ClearAllPoints(); sft[4]:SetPoint("TOPLEFT", g, "TOPRIGHT", 0, h); sft[4]:SetPoint("BOTTOMLEFT", g, "BOTTOMRIGHT", 0, -h); sft[4]:SetWidth(h)
	sft[4]:SetGradient("HORIZONTAL", near, far)
	g:Show()
	if style == "pulse" then g.anim:Play() else g.anim:Stop(); g:SetAlpha(1) end
	return g
end

-- Countdown numbers for PvP Assist and party CC / trinket icons, scaled by the user's setting.
function ns.AssistCountdownFont(size)
	local scale = (ns.db and ns.db.arenaAssist and ns.db.arenaAssist.countdownScale) or 1
	return ns.GetCountdownFont(size * 0.42 * scale)
end
