-- StinkieUI: player, target, target of target, focus and pet frames.
local _, ns = ...

local UF = {}
ns.UF = UF
UF.frames = {}

local SMOOTH = Enum.StatusBarInterpolation.ExponentialEaseOut
local IMMEDIATE = Enum.StatusBarInterpolation.Immediate

local unitLabels = {
	player = "Player", target = "Target", targettarget = "Target of Target",
	focus = "Focus", pet = "Pet",
}
UF.unitLabels = unitLabels
UF.unitOrder = { "player", "target", "targettarget", "focus", "pet" }

---------------------------------------------------------------------------
-- Element updates (shared with party frames)
---------------------------------------------------------------------------
function UF.UpdateHealth(f, immediate)
	local u = f.unit
	ns.UpdateHealthBar(f, u, immediate)
	if f.HealthText:IsShown() then
		f.HealthText:SetText(ns.FormatHealth(u, f.healthTextMode))
	end
end

function UF.UpdateHealthColor(f)
	local u = f.unit
	if UnitIsDeadOrGhost(u) then
		f.Health:SetStatusBarColor(0.35, 0.35, 0.35)
		return
	end
	local color = ns.GetHealthColor(u, f.forceClassColor)
	f.Health:SetStatusBarColor(color:GetRGB())
end

function UF.UpdatePower(f, immediate)
	if not f.Power:IsShown() then return end
	local u = f.unit
	f.Power:SetMinMaxValues(0, UnitPowerMax(u))
	f.Power:SetValue(UnitPower(u), (f.smooth and not immediate) and SMOOTH or IMMEDIATE)
	f.Power:SetStatusBarColor(ns.GetPowerColor(u))
end

function UF.UpdateName(f)
	if f.Name:IsShown() then
		f.Name:SetText(ns.ShortenName((UnitName(f.unit)), f.nameFormat))
		local style = f.nameStyle
		if style and style.classColor then
			f.Name:SetTextColor(ns.GetHealthColor(f.unit, true):GetRGB())
		elseif style then
			local c = style.color
			f.Name:SetTextColor(c[1], c[2], c[3])
		end
	end
end

-- Level, in the name's color. Bosses report -1 and show as ??.
function UF.UpdateLevel(f)
	local level = f.Level
	if not level:IsShown() then return end
	local value = UnitLevel(f.unit)
	if ns.issecret(value) or (value and value > 0) then
		level:SetText(value)
	else
		level:SetText("??")
	end
	local style = f.nameStyle
	if style and style.classColor then
		level:SetTextColor(ns.GetHealthColor(f.unit, true):GetRGB())
	elseif style then
		local c = style.color
		level:SetTextColor(c[1], c[2], c[3])
	end
end

-- Test mode and unlocked frames have no real unit to ask.
function UF.PreviewLevel(f)
	if f.Level:IsShown() then f.Level:SetText(UnitLevel("player")) end
end

-- Raid target marker (only frames that build one, and only when switched on).
function UF.UpdateMarker(f)
	if not f.Marker then return end
	if f.markerShown then ns.UpdateMarker(f.Marker, f.unit) else f.Marker:Hide() end
end

-- Elite / boss star (target and focus): gold for elite and bosses, silver for rares.
local STAR_GOLD, STAR_SILVER = { 1.00, 0.82, 0.20 }, { 0.80, 0.84, 0.90 }
function UF.UpdateElite(f)
	local star = f.Elite
	if not star then return end
	local cfg = ns.db.units[f.unit]
	if not (cfg and cfg.eliteIcon) then star:Hide() return end
	local c = UnitClassification(f.unit)
	if ns.issecret(c) or c == nil then star:Hide() return end
	local color = (c == "elite" or c == "worldboss") and STAR_GOLD
		or (c == "rareelite" or c == "rare") and STAR_SILVER or nil
	if color then
		star:SetVertexColor(color[1], color[2], color[3], 1)
		star:Show()
	else
		star:Hide()
	end
end

function UF.UpdateAll(f)
	if f.preview or not UnitExists(f.unit) then return end
	UF.UpdateElite(f)
	UF.UpdateHealthColor(f)
	UF.UpdateHealth(f, true) -- full refresh (new target, focus, roster): snap, don't animate
	UF.UpdatePower(f, true)
	UF.UpdateName(f)
	UF.UpdateLevel(f)
	UF.UpdateMarker(f)
	if f.PostUpdate then f:PostUpdate() end
	if f.Auras then ns.SetAuraUnit(f.Auras, f.unit) end
	if f.CCIcon then ns.SetAuraUnit(f.CCIcon, f.unit) end
	if f.Castbar and f.Castbar.unit then f.Castbar:ForceUpdate() end
end

local function SafeUpdateAll(f)
	-- target-of-target uses a compound unit token, which PvP matches refuse for addons
	if f.compound then
		local ok = pcall(UF.UpdateAll, f)
		if not ok then
			f.Name:SetText("")
			f.Level:SetText("")
			f.HealthText:SetText("")
		end
	else
		UF.UpdateAll(f)
	end
end
UF.SafeUpdateAll = SafeUpdateAll

local function OnEvent(f, event, unit)
	if f.preview then return end -- test mode: keep the stand-in values
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
		UF.UpdateHealth(f)
		if event == "UNIT_HEALTH" then UF.UpdateHealthColor(f) end
	elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
		UF.UpdatePower(f)
	elseif event == "UNIT_NAME_UPDATE" then
		UF.UpdateName(f)
	elseif event == "UNIT_LEVEL" then
		UF.UpdateLevel(f)
	elseif event == "RAID_TARGET_UPDATE" then
		UF.UpdateMarker(f)
	elseif event == "UNIT_CLASSIFICATION_CHANGED" then
		UF.UpdateElite(f)
	elseif event == "UNIT_CONNECTION" or event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
		UF.UpdateHealthColor(f)
		UF.UpdateHealth(f)
	else
		-- PLAYER_TARGET_CHANGED, PLAYER_FOCUS_CHANGED, UNIT_PET, GROUP_ROSTER_UPDATE, ...
		SafeUpdateAll(f)
	end
	if f.OnEventExtra then f:OnEventExtra(event, unit) end
end

local unitEvents = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
	"UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_CONNECTION", "UNIT_FACTION", "UNIT_FLAGS",
}

function UF.RegisterUnitEvents(f)
	local u = f.unit
	if f.compound then return end -- polled instead
	for _, e in ipairs(unitEvents) do
		f:RegisterUnitEvent(e, u)
	end
	if u == "target" then f:RegisterEvent("PLAYER_TARGET_CHANGED") end
	if u == "focus" then f:RegisterEvent("PLAYER_FOCUS_CHANGED") end
	if u == "target" or u == "focus" then f:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", u) end
	if u == "pet" then f:RegisterUnitEvent("UNIT_PET", "player") end
end

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------
local function OnEnter(self)
	GameTooltip_SetDefaultAnchor(GameTooltip, self)
	GameTooltip:SetUnit(self.unit)
	GameTooltip:Show()
end

local function OnLeave()
	GameTooltip:Hide()
end

-- Pinging a unit frame: Blizzard's ping code copies the unit's GUID and errors if it's a hidden
-- value, which leaves the ping cursor stuck until the next press. Asked from our (addon) frames
-- the GUID can be hidden, so a frame only offers itself as a ping target while it's readable;
-- otherwise the ping fails with Blizzard's normal "can't ping that" message.
local function PingGUID(self)
	local u = self.unit or self:GetAttribute("unit")
	if not u then return nil end
	local guid = UnitGUID(u)
	if issecretvalue and issecretvalue(guid) then return nil end
	return guid
end
local function PingIsPingable(self) return PingGUID(self) ~= nil end
local function PingTargetInfo(self) return { guid = PingGUID(self) } end

function UF.CreateFrame(unit, name, noUnitWatch)
	local f = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
	f.GetIsPingable = PingIsPingable
	f.GetTargetInfo = PingTargetInfo
	f.unit = unit
	f.compound = unit:match("%wtarget$") ~= nil
	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:RegisterForClicks("AnyUp")
	f:SetFrameStrata("LOW")
	if f.SetRolesets then f:SetRolesets("unitFrames") end
	ns.CreateBackdrop(f)

	local health = ns.CreateBar(f)
	health:SetClipsChildren(true)
	f.Health = health

	ns.CreateHealthLayers(f, health)

	local power = ns.CreateBar(f)
	f.Power = power
	local sep = f:CreateTexture(nil, "BORDER")
	sep:SetColorTexture(0, 0, 0, 1)
	f.PowerSeparator = sep

	-- text sits on its own layer above the bars
	local textLayer = CreateFrame("Frame", nil, f)
	textLayer:SetAllPoints()
	textLayer:SetFrameLevel(health:GetFrameLevel() + 3)
	f.TextLayer = textLayer
	f.Name = ns.CreateText(textLayer, 12, "LEFT")
	f.HealthText = ns.CreateText(textLayer, 12, "RIGHT")
	f.Level = ns.CreateText(textLayer, 12, "LEFT")
	if unit == "target" or unit == "focus" then
		f.Elite = textLayer:CreateTexture(nil, "OVERLAY", nil, 7)
		f.Elite:SetTexture(ns.MEDIA.star, "CLAMP", "CLAMP", "TRILINEAR")
		f.Elite:Hide()
	end

	f:SetScript("OnEnter", OnEnter)
	f:SetScript("OnLeave", OnLeave)
	f:SetScript("OnEvent", ns.Timed("Unit frames", OnEvent))
	f:HookScript("OnShow", SafeUpdateAll)

	if f.compound then
		f.elapsed = 0
		f:SetScript("OnUpdate", function(self, elapsed)
			self.elapsed = self.elapsed + elapsed
			if self.elapsed > 0.2 then
				self.elapsed = 0
				SafeUpdateAll(self)
			end
		end)
	end

	UF.RegisterUnitEvents(f)
	if not noUnitWatch then RegisterUnitWatch(f) end
	return f
end

-- Applies size, bar layout and text placement. cfg fields: width, height, showPower,
-- powerHeight, showName, nameAbove, healthText.
function UF.Layout(f, cfg)
	local px = ns.Pixel(f)
	local w, h = cfg.width, cfg.height
	local showPower = cfg.showPower and cfg.powerHeight > 0
	local ph = showPower and cfg.powerHeight or 0
	f:SetSize(w, h + (showPower and (ph + px) or 0))
	f.smooth = true
	f.healthTextMode = cfg.healthText or "none"
	ns.UpdateBackdrop(f)

	f.Health:ClearAllPoints()
	f.Health:SetPoint("TOPLEFT")
	f.Health:SetPoint("TOPRIGHT")
	f.Health:SetHeight(h)
	ns.LayoutHealthLayers(f, w, h)
	-- shields can be turned off per frame (hiding the bars keeps Blizzard's values flowing harmlessly)
	local shields = cfg.shields ~= false
	f.Absorb:SetShown(shields)
	f.OverAbsorb:SetShown(shields)

	f.Power:SetShown(showPower)
	f.PowerSeparator:SetShown(showPower)
	if showPower then
		f.PowerSeparator:ClearAllPoints()
		f.PowerSeparator:SetPoint("TOPLEFT", f.Health, "BOTTOMLEFT")
		f.PowerSeparator:SetPoint("TOPRIGHT", f.Health, "BOTTOMRIGHT")
		f.PowerSeparator:SetHeight(px)
		f.Power:ClearAllPoints()
		f.Power:SetPoint("BOTTOMLEFT")
		f.Power:SetPoint("BOTTOMRIGHT")
		f.Power:SetHeight(ph)
	end

	f.nameStyle = cfg.nameStyle
	f.nameFormat = cfg.nameFormat
	ns.ApplyText(f.Name, cfg.nameStyle)
	ns.ApplyText(f.HealthText, cfg.healthStyle)

	-- the level sits at the left of the bar; a name on the bar starts after it
	local showLevel = cfg.showLevel == true
	ns.ApplyText(f.Level, cfg.nameStyle)
	f.Level:SetShown(showLevel)
	f.Level:ClearAllPoints()
	f.Level:SetPoint("LEFT", f.Health, "LEFT", 4, 0)

	f.Name:SetShown(cfg.showName ~= false)
	f.Name:ClearAllPoints()
	if cfg.nameAbove then
		f.Name:SetJustifyH("CENTER")
		f.Name:SetPoint("BOTTOM", f, "TOP", 0, 3)
		f.Name:SetWidth(w + 40)
	else
		f.Name:SetJustifyH("LEFT")
		if showLevel then
			f.Name:SetPoint("LEFT", f.Level, "RIGHT", 4, 0)
		else
			f.Name:SetPoint("LEFT", f.Health, "LEFT", 4, 0)
		end
		f.Name:SetPoint("RIGHT", f.Health, "RIGHT", -44, 0)
	end

	f.HealthText:SetShown(f.healthTextMode ~= "none")
	f.HealthText:ClearAllPoints()
	f.HealthText:SetPoint("RIGHT", f.Health, "RIGHT", -4, 0)

	if f.Elite then
		local es = cfg.eliteSize or 16
		f.Elite:SetSize(es, es)
		f.Elite:ClearAllPoints()
		f.Elite:SetPoint("CENTER", f, cfg.eliteCorner or "TOPLEFT", 0, 0) -- centered on the chosen corner
		if f.preview == nil and UnitExists(f.unit) then UF.UpdateElite(f) end
	end
end

-- Party and arena frames keep their name in the top left corner, above the power split.
function UF.PlaceNameTopLeft(f)
	f.Name:ClearAllPoints()
	if f.Level:IsShown() then
		f.Level:ClearAllPoints()
		f.Level:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
		f.Name:SetPoint("LEFT", f.Level, "RIGHT", 4, 0)
	else
		f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
	end
	f.Name:SetPoint("RIGHT", f, "RIGHT", -40, 0)
end

---------------------------------------------------------------------------
-- Castbars attached to or floating near unit frames
---------------------------------------------------------------------------
function UF.LayoutCastbar(f, ccfg, key, label)
	local bar = f.Castbar
	if not bar then
		bar = ns.CreateCastbar(UIParent, nil)
		f.Castbar = bar
		bar.previewLabel = label
		ns:RegisterMover(key, bar, label,
			function() return ccfg.point end,
			function(p) ccfg.point = p end)
	end
	local m = ns.movers[key]
	m.getPoint = function() return ccfg.point end
	m.setPoint = function(p) ccfg.point = p end

	bar:SetScale(ns.db.scale)
	if ccfg.attached then
		bar:SetParent(f)
		bar:ClearAllPoints()
		local gap = ns.Pixel(f) * 2
		bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -gap)
		bar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -gap)
		bar:SetHeight(ccfg.height)
		bar:SetScale(1)
		bar.SUIActive = false -- not separately movable
	else
		bar:SetParent(UIParent)
		bar:SetSize(ccfg.width, ccfg.height)
		ns:ApplyPoint(bar, ccfg.point)
		bar.SUIActive = true
	end
	bar:SetFrameStrata("MEDIUM")
	bar:ApplyConfig(ccfg)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local blizzardFrames = {
	player = "PlayerFrame", target = "TargetFrame", focus = "FocusFrame",
	pet = "PetFrame", targettarget = "TargetFrameToT",
}

local function BuildAuras(f, acfg, ucfg)
	if f.Auras then return end
	local F = ns.AuraFilters
	f.Auras = ns.CreateAuraContainer(f, {
		{ filter = F.cc, max = 2 },
		{ filter = F.bigDefensive, max = 2 },
		{ filter = F.externalDefensive, max = 2 },
		{ filter = F.mine, max = acfg.max },
	}, { size = acfg.size, spacing = 3, anchor = "BOTTOMLEFT", growthX = "RIGHT", growthY = "UP", maxWidth = (acfg.size + 3) * 10 })
	-- one big crowd-control icon beside the frame (fear, stun, poly...), with its timer
	-- (size is fixed when the icon is built, so changing it needs a reload)
	local frameH = ucfg.height + (ucfg.showPower and ucfg.powerHeight or 0)
	local size = (acfg.ccIconSize and acfg.ccIconSize > 0) and acfg.ccIconSize or frameH
	f.CCIcon = ns.CreateAuraContainer(f, { { filter = F.cc, max = 1 } }, {
		size = size, spacing = 0, anchor = "TOPLEFT", growthX = "RIGHT", growthY = "DOWN", maxWidth = size,
	})
end

local function LayoutCCIcon(f, cfg)
	local icon = f.CCIcon
	if not icon then return end
	local a = cfg.auras
	icon:ClearAllPoints()
	if a.ccIconSide == "LEFT" then
		ns.SetAuraGrowth(icon, "TOPRIGHT", "LEFT", "DOWN")
		icon:SetPoint("TOPRIGHT", f, "TOPLEFT", -3, 0)
	else
		ns.SetAuraGrowth(icon, "TOPLEFT", "RIGHT", "DOWN")
		icon:SetPoint("TOPLEFT", f, "TOPRIGHT", 3, 0)
	end
	icon:SetShown(a.enabled and a.ccIcon)
end

function UF:Init()
	for _, unit in ipairs(UF.unitOrder) do
		local cfg = ns.db.units[unit]
		if cfg.enabled then
			ns.KillBlizzard(blizzardFrames[unit])
			local f = UF.CreateFrame(unit, "StinkieUI_" .. unit)
			UF.frames[unit] = f
			ns:RegisterMover(unit, f, unitLabels[unit],
				function() return cfg.point end,
				function(p) cfg.point = p end)

			if cfg.auras and cfg.auras.enabled then
				BuildAuras(f, cfg.auras, cfg)
			end

			if cfg.castbar and cfg.castbar.enabled then
				ns:HideBlizzardCastbar(unit)
				UF.LayoutCastbar(f, cfg.castbar, unit .. "Castbar", unitLabels[unit] .. " Castbar")
				f.Castbar:SetUnit(unit)
			end
		end
	end
	-- player castbar can be used without the custom player frame
	local pc = ns.db.units.player
	if not pc.enabled and pc.castbar.enabled then
		ns:HideBlizzardCastbar("player")
		local holder = CreateFrame("Frame", nil, UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint("CENTER")
		holder.unit = "player"
		local tmp = { castbar = pc.castbar }
		tmp.castbar.attached = false
		UF.LayoutCastbar(holder, tmp.castbar, "playerCastbar", "Player Castbar")
		holder.Castbar:SetUnit("player")
		UF.frames.playerCastbarOnly = holder
	end
	UF:Refresh()
	table.insert(ns.lockCallbacks, UF.Preview)
end

function UF:Refresh()
	for _, unit in ipairs(UF.unitOrder) do
		local f = UF.frames[unit]
		local cfg = ns.db.units[unit]
		if f then
			f:SetScale(ns.db.scale)
			UF.Layout(f, cfg)
			ns:ApplyPoint(f, cfg.point)
			if f.Auras then
				local a = cfg.auras
				f.Auras:ClearAllPoints()
				if a.position == "ABOVE" then
					local y = (cfg.showName ~= false and cfg.nameAbove) and (cfg.nameStyle.size + 6) or 4
					ns.SetAuraGrowth(f.Auras, "BOTTOMLEFT", "RIGHT", "UP")
					f.Auras:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, y)
				else
					-- below the attached castbar when there is one, otherwise below the frame
					local cb = cfg.castbar
					local under = (cb and cb.enabled and cb.attached and f.Castbar) or f
					ns.SetAuraGrowth(f.Auras, "TOPLEFT", "RIGHT", "DOWN")
					f.Auras:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -4)
				end
				f.Auras:SetShown(a.enabled and a.showSmall ~= false)
				ns.SetAuraGroupMax(f.Auras, 4, a.max)
				LayoutCCIcon(f, cfg)
			end
			if f.Castbar then
				UF.LayoutCastbar(f, cfg.castbar, unit .. "Castbar", unitLabels[unit] .. " Castbar")
			end
			SafeUpdateAll(f)
		end
	end
	local holder = UF.frames.playerCastbarOnly
	if holder then
		UF.LayoutCastbar(holder, ns.db.units.player.castbar, "playerCastbar", "Player Castbar")
	end
end

-- Show placeholder castbars while unlocked so they can be positioned.
function UF.Preview(unlocked)
	local function each(bar)
		if not bar then return end
		if unlocked then
			bar.preview = true
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(0.6)
			bar.Text:SetText(bar.previewLabel or "")
			bar.Time:SetText("")
			bar:Show()
		elseif bar.preview then
			bar.preview = nil
			bar:Hide()
			bar:ForceUpdate()
		end
	end
	for _, f in pairs(UF.frames) do each(f.Castbar) end
end

ns:RegisterModule("UnitFrames", UF)
