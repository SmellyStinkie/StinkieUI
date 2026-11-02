-- StinkieUI: party frames, styled like arena frames (CC / defensive icons on the side).
local _, ns = ...

local UF = ns.UF
local Party = {}
ns.Party = Party
Party.frames = {}

local issecret = ns.issecret

local function ShouldShowPower(f)
	local mode = ns.db.party.power
	if mode == "none" then return false end
	if mode == "all" then return true end
	local role = UnitGroupRolesAssigned(f.unit)
	if issecret(role) then return true end
	return role == "HEALER"
end

-- Health/power split is done on the non-secure bars, so it can change in combat.
local function PostUpdate(f)
	local cfg = ns.db.party
	local px = ns.Pixel(f)
	local showPower = ShouldShowPower(f)
	local h = cfg.height
	f.Power:SetShown(showPower)
	f.PowerSeparator:SetShown(showPower)
	if showPower then
		f.Health:SetHeight(h - cfg.powerHeight - px)
		UF.UpdatePower(f, true)
	else
		f.Health:SetHeight(h)
	end

	local role = UnitGroupRolesAssigned(f.unit)
	if cfg.healerIcon ~= false and not issecret(role) and role == "HEALER" then
		f.RoleIcon:Show()
	else
		f.RoleIcon:Hide()
	end
	Party.UpdateTargetHighlight(f)
	-- the aura containers watch this frame's unit (they show nothing until told which one)
	local function watch(container, on)
		if not container then return end
		ns.SetAuraUnit(container, on and f.unit or nil)
		container:SetShown(on and true or false)
	end
	watch(f.CCIcons, cfg.ccIcon)
	watch(f.DefIcons, cfg.defensiveIcon)
	watch(f.DispelIcons, cfg.dispelIcons)
end

function Party.UpdateTargetHighlight(f)
	f.Highlight:SetAlphaFromBoolean(UnitIsUnit(f.unit, "target"), 1, 0)
end

local function UpdateRange(f)
	if f.preview or f.unit == "player" or not ns.db.party.rangeFade then
		f:SetAlpha(1)
		return
	end
	local inRange = UnitInRange(f.unit)
	f:SetAlphaFromBoolean(inRange, 1, 0.45)
end

local function OnEventExtra(f, event)
	if event == "PLAYER_TARGET_CHANGED" then
		Party.UpdateTargetHighlight(f)
	end
end

local function CreateHighlight(f)
	local hl = CreateFrame("Frame", nil, f)
	hl:SetAllPoints()
	hl:SetFrameLevel(f.TextLayer:GetFrameLevel() + 1)
	local edges = {}
	for i = 1, 4 do
		local t = hl:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 1, 1, 1)
		edges[i] = t
	end
	hl.edges = edges
	f.Highlight = hl
	return hl
end

local function LayoutHighlight(f)
	local px = ns.Pixel(f)
	local e = f.Highlight.edges
	e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(px)
	e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(px)
	e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(px)
	e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(px)
end

local function CreatePartyFrame(unit, index)
	local f = UF.CreateFrame(unit, "StinkieUI_Party" .. index)
	f.forceClassColor = true
	f.PostUpdate = PostUpdate
	f.OnEventExtra = OnEventExtra
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("PLAYER_ROLES_ASSIGNED")

	-- simple green cross, same shape as the nameplate healer cross
	local role = f.TextLayer:CreateTexture(nil, "OVERLAY")
	role:SetTexture(ns.MEDIA.cross)
	role:SetVertexColor(ns.HEALER_GREEN[1], ns.HEALER_GREEN[2], ns.HEALER_GREEN[3], 1)
	role:Hide()
	f.RoleIcon = role

	CreateHighlight(f)

	local F = ns.AuraFilters
	local cfg = ns.db.party
	local AA = ns.db.arenaAssist
	local iconSize = cfg.height
	local side = cfg.trinketSide == "RIGHT" and "RIGHT" or "LEFT" -- trinket + defensives
	local other = side == "LEFT" and "RIGHT" or "LEFT"           -- crowd control
	local function grow(s) return s == "LEFT" and "LEFT" or "RIGHT" end
	local function anchorFor(s) return s == "LEFT" and "TOPRIGHT" or "TOPLEFT" end

	do
		local cs = (cfg.ccSize and cfg.ccSize > 0) and cfg.ccSize or iconSize
		f.CCIcons = ns.CreateAuraContainer(f, { { filter = F.cc, max = cfg.ccMax or 2 } }, {
			size = cs, spacing = 3, anchor = anchorFor(other), growthX = grow(other), growthY = "DOWN",
			maxWidth = (cs + 3) * 4,
			assistCountdown = true,
			glow = function()
				return { glow = AA.ccGlow, glowColor = AA.ccGlowColor, glowThickness = AA.ccGlowThickness }
			end,
		})
	end
	do
		f.DefIcons = ns.CreateAuraContainer(f, {
			{ filter = F.bigDefensive, max = 1 },
			{ filter = F.externalDefensive, max = 1 },
		}, {
			size = iconSize, spacing = 3, anchor = anchorFor(side), growthX = grow(side), growthY = "DOWN",
			maxWidth = (iconSize + 3) * 4,
		})
	end
	do
		local s = math.floor(iconSize * 0.6)
		local below = cfg.dispelPosition ~= "SIDE"
		f.DispelIcons = ns.CreateAuraContainer(f, { { filter = F.dispellable, max = 3 } }, {
			size = s, spacing = 2, dispelBorder = true,
			anchor = below and "TOPLEFT" or anchorFor(other),
			growthX = below and "RIGHT" or grow(other), growthY = "DOWN",
			maxWidth = (s + 2) * 3,
		})
	end

	-- PvP trinket: Blizzard's arena crowd-control tracker for this party member (arena only).
	local trinket = CreateFrame("Frame", nil, f)
	trinket.tex = trinket:CreateTexture(nil, "ARTWORK")
	trinket.tex:SetAllPoints()
	trinket.tex:SetTexture([[Interface\Icons\INV_Jewelry_TrinketPVP_01]])
	trinket.cd = CreateFrame("Cooldown", nil, trinket, "CooldownFrameTemplate")
	trinket.cd:SetAllPoints()
	trinket.cd:SetSwipeTexture(ns.TEXTURE)
	trinket.cd:SetDrawEdge(false)
	trinket:Hide()
	f.Trinket = trinket

	if cfg.castbar.enabled then
		f.Castbar = ns.CreateCastbar(f)
		f.Castbar.previewLabel = "Party Castbar"
		f.Castbar:SetUnit(unit)
	end

	f.rangeElapsed = 0
	f:HookScript("OnUpdate", function(self, elapsed)
		self.rangeElapsed = self.rangeElapsed + elapsed
		if self.rangeElapsed > 0.25 then
			self.rangeElapsed = 0
			UpdateRange(self)
		end
	end)
	return f
end

local function LayoutPartyFrame(f, index)
	local cfg = ns.db.party
	UF.Layout(f, {
		width = cfg.width, height = cfg.height,
		showPower = false, -- power is split from health in PostUpdate
		powerHeight = cfg.powerHeight,
		showName = true, nameAbove = false,
		healthText = cfg.healthText,
		nameStyle = cfg.nameStyle, healthStyle = cfg.healthStyle,
	})
	-- power bar is always laid out at the bottom; PostUpdate decides if it is visible
	local px = ns.Pixel(f)
	f.Power:ClearAllPoints()
	f.Power:SetPoint("BOTTOMLEFT")
	f.Power:SetPoint("BOTTOMRIGHT")
	f.Power:SetHeight(cfg.powerHeight)
	f.PowerSeparator:ClearAllPoints()
	f.PowerSeparator:SetPoint("BOTTOMLEFT", f.Power, "TOPLEFT")
	f.PowerSeparator:SetPoint("BOTTOMRIGHT", f.Power, "TOPRIGHT")
	f.PowerSeparator:SetHeight(px)

	f.Name:ClearAllPoints()
	f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
	f.Name:SetPoint("RIGHT", f, "RIGHT", -40, 0)
	f.HealthText:ClearAllPoints()
	f.HealthText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -3)
	local rs = cfg.healerSize or 12
	f.RoleIcon:SetSize(rs, rs)
	f.RoleIcon:ClearAllPoints()
	f.RoleIcon:SetPoint("BOTTOMRIGHT", f.Health, "BOTTOMRIGHT", -3, 3)
	LayoutHighlight(f)

	local AA = ns.db.arenaAssist
	local side = cfg.trinketSide == "RIGHT" and "RIGHT" or "LEFT"
	local gap = 3
	local function Beside(frame, s, offset)
		frame:ClearAllPoints()
		if s == "LEFT" then
			frame:SetPoint("TOPRIGHT", f, "TOPLEFT", -offset, 0)
		else
			frame:SetPoint("TOPLEFT", f, "TOPRIGHT", offset, 0)
		end
	end
	local other = side == "LEFT" and "RIGHT" or "LEFT"
	-- trinket next to the frame, defensives beyond it
	local ts = (cfg.trinketSize and cfg.trinketSize > 0) and cfg.trinketSize or cfg.height
	f.Trinket:SetSize(ts, ts)
	Beside(f.Trinket, side, gap)
	ns.ZoomIcon(f.Trinket.tex)
	ns.IconBorder(f.Trinket)
	ns.ApplyGlow(f.Trinket, { glow = AA.trinketGlow, glowColor = AA.trinketGlowColor, glowThickness = AA.trinketGlowThickness })
	f.Trinket.cd:SetCountdownFont(ns.AssistCountdownFont(ts))
	if not cfg.trinket then f.Trinket:Hide() end
	-- the containers' own growth follows the side too, so the side can change without a reload
	local function anchorFor(s) return s == "LEFT" and "TOPRIGHT" or "TOPLEFT" end
	if f.DefIcons then
		Beside(f.DefIcons, side, gap + (cfg.trinket and (ts + gap) or 0))
		ns.SetAuraGrowth(f.DefIcons, anchorFor(side), side, "DOWN")
	end
	-- crowd control on the other side
	local cs = (cfg.ccSize and cfg.ccSize > 0) and cfg.ccSize or cfg.height
	if f.CCIcons then
		Beside(f.CCIcons, other, gap)
		ns.SetAuraGrowth(f.CCIcons, anchorFor(other), other, "DOWN")
		ns.RestyleAuraButtons(f.CCIcons, { glow = AA.ccGlow, glowColor = AA.ccGlowColor, glowThickness = AA.ccGlowThickness }, nil, true)
	end
	if f.DispelIcons then
		if cfg.dispelPosition == "SIDE" then
			Beside(f.DispelIcons, other, gap + (cfg.ccIcon and (cs + gap) * (cfg.ccMax or 2) or 0))
			ns.SetAuraGrowth(f.DispelIcons, anchorFor(other), other, "DOWN")
		else
			-- a row under the frame (under the castbar when there is one)
			f.DispelIcons:ClearAllPoints()
			local under = f.Castbar and cfg.castbar.enabled and f.Castbar or f
			f.DispelIcons:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -3)
			ns.SetAuraGrowth(f.DispelIcons, "TOPLEFT", "RIGHT", "DOWN")
		end
	end
	if f.preview then Party.LayoutPreview(f) end
	if f.Castbar then
		f.Castbar:ClearAllPoints()
		f.Castbar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -px * 2)
		f.Castbar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -px * 2)
		f.Castbar:SetHeight(cfg.castbar.height)
		f.Castbar:ApplyConfig({ height = cfg.castbar.height, showText = true, showTime = false, textStyle = cfg.castbar.textStyle })
	end
end

---------------------------------------------------------------------------
-- Trinkets
---------------------------------------------------------------------------
local function InArena()
	local _, t = IsInInstance()
	return t == "arena"
end

local DEFAULT_TRINKET = 336126 -- Gladiator's Medallion

local function TrinketWanted(f)
	return ns.db.party.trinket and InArena() and not f.preview and UnitExists(f.unit)
end

local function UpdateTrinketCooldown(f)
	if not TrinketWanted(f) then return end
	if not C_PvP.GetArenaCrowdControlDuration then return end
	local ok, duration = pcall(C_PvP.GetArenaCrowdControlDuration, f.unit)
	if ok and duration then
		f.Trinket.cd:SetCooldownFromDurationObject(duration)
	end
end

local function SetTrinketIcon(f, spellID)
	local tex
	if not issecret(spellID) and spellID ~= nil and spellID > 0 then tex = C_Spell.GetSpellTexture(spellID) end
	tex = tex or C_Spell.GetSpellTexture(DEFAULT_TRINKET) or [[Interface\Icons\INV_Jewelry_TrinketPVP_01]]
	f.Trinket.tex:SetTexture(tex)
	ns.ZoomIcon(f.Trinket.tex)
end

local function OnTrinketSpell(f, spellID)
	if not TrinketWanted(f) then return end
	SetTrinketIcon(f, spellID)
	f.Trinket:Show()
	UpdateTrinketCooldown(f)
end

-- In arena every party member shows their trinket; the cooldown fills in from Blizzard's
-- arena cooldown updates.
local function RequestTrinkets()
	for _, f in ipairs(Party.frames) do
		if not f.preview then
			f.Trinket.cd:Clear()
			if TrinketWanted(f) then
				SetTrinketIcon(f, nil)
				f.Trinket:Show()
				if C_PvP.RequestCrowdControlSpell then pcall(C_PvP.RequestCrowdControlSpell, f.unit) end
				UpdateTrinketCooldown(f)
			else
				f.Trinket:Hide()
			end
		end
	end
end

---------------------------------------------------------------------------
-- Hidden in battlegrounds / Blitz (the battleground frames cover your team there)
---------------------------------------------------------------------------
function Party:UpdateVisibility()
	local holder = Party.holder
	if not holder then return end
	ns:RunOOC(function()
		local _, t = IsInInstance()
		local hide = ns.db.party.hideInBattlegrounds and t == "pvp" and not ns.unlocked and not Party.testMode
		holder:SetShown(not hide)
	end)
end

function Party:Init()
	local cfg = ns.db.party
	if not cfg.enabled then return end

	-- hide Blizzard party frames
	if PartyFrame then
		ns.KillBlizzard(PartyFrame)
		if PartyFrame.PartyMemberFramePool then
			for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
				ns.KillBlizzard(frame)
			end
		end
	end
	if CompactPartyFrame then
		ns.KillBlizzard(CompactPartyFrame)
		for i = 1, (MEMBERS_PER_RAID_GROUP or 5) do
			ns.KillBlizzard("CompactPartyFrameMember" .. i)
		end
	end

	local holder = CreateFrame("Frame", "StinkieUI_PartyHolder", UIParent)
	Party.holder = holder
	ns:RegisterMover("party", holder, "Party",
		function() return ns.db.party.point end,
		function(p) ns.db.party.point = p end)

	local units = {}
	if cfg.showPlayer then table.insert(units, "player") end
	for i = 1, 4 do table.insert(units, "party" .. i) end
	for i, unit in ipairs(units) do
		local f = CreatePartyFrame(unit, i)
		f:SetParent(holder)
		Party.frames[i] = f
	end

	local ev = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ARENA_PREP_OPPONENT_SPECIALIZATIONS",
		"GROUP_ROSTER_UPDATE", "PVP_MATCH_STATE_CHANGED", "ARENA_CROWD_CONTROL_SPELL_UPDATE", "ARENA_COOLDOWNS_UPDATE" }) do
		ev:RegisterEvent(e)
	end
	ev:SetScript("OnEvent", function(_, event, unit, spellID)
		if event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" then
			for _, f in ipairs(Party.frames) do
				if f.unit == unit then OnTrinketSpell(f, spellID) end
			end
		elseif event == "ARENA_COOLDOWNS_UPDATE" then
			for _, f in ipairs(Party.frames) do
				if f.unit == unit or unit == nil then UpdateTrinketCooldown(f) end
			end
		else
			if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then Party:UpdateVisibility() end
			RequestTrinkets()
		end
	end)
	table.insert(ns.lockCallbacks, function(unlocked)
		if unlocked then
			Party.testFromUnlock = not Party.testMode
			Party:SetTestMode(true)
		elseif Party.testFromUnlock then
			Party.testFromUnlock = nil
			Party:SetTestMode(false)
		end
		Party:UpdateVisibility()
	end)
	Party:Refresh()
end

function Party:Refresh()
	local holder = Party.holder
	if not holder then return end
	local cfg = ns.db.party
	local n = #Party.frames
	local castH = (cfg.castbar.enabled and (cfg.castbar.height + 2)) or 0
	if cfg.dispelIcons and cfg.dispelPosition ~= "SIDE" then castH = castH + math.floor(cfg.height * 0.6) + 3 end
	local step = cfg.height + castH + cfg.spacing
	holder:SetScale(ns.db.scale)
	holder:SetSize(cfg.width, n * step - cfg.spacing)
	ns:ApplyPoint(holder, cfg.point)
	for i, f in ipairs(Party.frames) do
		LayoutPartyFrame(f, i)
		f:ClearAllPoints()
		if cfg.growth == "UP" then
			f:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, (i - 1) * step + castH)
		else
			f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * step)
		end
		if f.preview then
			local ok, err = pcall(Party.FillPreview, f, i)
			if not ok then geterrorhandler()(err) end
		else
			UF.SafeUpdateAll(f)
		end
	end
	Party:UpdateVisibility()
end

---------------------------------------------------------------------------
-- Test mode: stand-in teammates with trinket, crowd control, defensive and dispel icons
---------------------------------------------------------------------------
-- party: a tank, a healer and two damage dealers; arena: you plus two teammates, both in CC
local PREVIEW = {
	party = {
		{ name = "Tankie", class = "WARRIOR", hp = 0.91, def = 871, dispel = 0 },
		{ name = "Pinkie", class = "PRIEST", hp = 0.62, healer = true, cc = 118, dispel = 2 },
		{ name = "Minkie", class = "MAGE", hp = 0.34, cc = 853, dispel = 0, trinketCD = 74 },
		{ name = "Winkie", class = "ROGUE", hp = 0.88, def = 31224, dispel = 1 },
		{ name = "Dinkie", class = "SHAMAN", hp = 1.00, dispel = 0 },
	},
	arena = {
		{ name = "Pinkie", class = "PRIEST", hp = 0.62, healer = true, cc = 118, dispel = 1 },
		{ name = "Minkie", class = "MAGE", hp = 0.41, cc = 5782, def = 45438, dispel = 0, trinketCD = 74 },
	},
}
local DISPEL_PREVIEW = { 589, 172 }
-- looping test casts: { spell, cast time, offset, can't be interrupted }
local PREVIEW_CASTS = {
	{ 8690, 3.0, 0.0 },        -- Hearthstone
	{ 2061, 1.5, 0.7 },        -- Flash Heal
	{ 116, 2.0, 1.4, true },   -- Frostbolt (shown as not interruptible)
	{ 1804, 2.5, 0.3 },        -- Pick Lock
	{ 403, 2.0, 1.1 },         -- Lightning Bolt
}

local castTicker
local function SpellName(id)
	return (C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or "Casting"
end

local function UpdatePreviewCasts()
	local now = GetTime()
	local colors = ns.db.colors
	for i, f in ipairs(Party.frames) do
		local bar = f.Castbar
		if bar and f.preview and f:IsShown() and ns.db.party.castbar.enabled then
			local c = PREVIEW_CASTS[((i - 1) % #PREVIEW_CASTS) + 1]
			local total = c[2] + 0.8 -- cast, then a short pause
			local t = (now + c[3]) % total
			if t < c[2] then
				bar:SetMinMaxValues(0, c[2])
				bar:SetValue(t)
				bar.Text:SetText(SpellName(c[1]))
				bar.Time:SetText(string.format("%.1f", c[2] - t))
				local col = c[4] and colors.castNotInterruptible or colors.castInterruptible
				bar:GetStatusBarTexture():SetVertexColor(col[1], col[2], col[3], 1)
				bar:SetAlpha(1)
				bar:Show()
			else
				bar:Hide()
			end
		end
	end
end

local function PreviewIcon(f, key)
	f.SUIPreview = f.SUIPreview or {}
	local p = f.SUIPreview[key]
	if not p then
		p = CreateFrame("Frame", nil, f)
		p.tex = p:CreateTexture(nil, "ARTWORK")
		p.tex:SetAllPoints()
		p.cd = CreateFrame("Cooldown", nil, p, "CooldownFrameTemplate")
		p.cd:SetAllPoints()
		p.cd:SetDrawEdge(false)
		p.cd:SetReverse(true)
		ns.IconBorder(p)
		f.SUIPreview[key] = p
	end
	return p
end

-- Stand-ins are positioned from the party frame itself, never from Blizzard's aura containers
-- (anchoring to those isn't allowed, and an error there used to stop the whole test mode).
function Party.LayoutPreview(f)
	local cfg, AA = ns.db.party, ns.db.arenaAssist
	local d = f.previewData
	if not d then return end
	local h = cfg.height
	local gap = 3
	local side = cfg.trinketSide == "RIGHT" and "RIGHT" or "LEFT"
	local other = side == "LEFT" and "RIGHT" or "LEFT"
	local cs = (cfg.ccSize and cfg.ccSize > 0) and cfg.ccSize or h
	local ts = (cfg.trinketSize and cfg.trinketSize > 0) and cfg.trinketSize or h
	local function Beside(p, s, offset, size)
		p:SetSize(size, size)
		p:ClearAllPoints()
		if s == "LEFT" then
			p:SetPoint("TOPRIGHT", f, "TOPLEFT", -offset, 0)
		else
			p:SetPoint("TOPLEFT", f, "TOPRIGHT", offset, 0)
		end
	end
	-- crowd control, on the side away from the trinket
	local cc = PreviewIcon(f, "cc")
	Beside(cc, other, gap, cs)
	cc.cd:SetCountdownFont(ns.AssistCountdownFont(cs))
	cc:SetShown(cfg.ccIcon and d.cc ~= nil)
	if d.cc then cc.tex:SetTexture(C_Spell.GetSpellTexture(d.cc)); ns.ZoomIcon(cc.tex); cc.cd:SetCooldown(GetTime() - 2, 8) end
	ns.ApplyGlow(cc, { glow = AA.ccGlow, glowColor = AA.ccGlowColor, glowThickness = AA.ccGlowThickness })
	-- defensive, beyond the trinket
	local def = PreviewIcon(f, "def")
	Beside(def, side, gap + (cfg.trinket and (ts + gap) or 0), h)
	def:SetShown(cfg.defensiveIcon and d.def ~= nil)
	if d.def then def.tex:SetTexture(C_Spell.GetSpellTexture(d.def)); ns.ZoomIcon(def.tex); def.cd:SetCooldown(GetTime() - 1, 8) end
	-- dispellable debuffs
	local ds = math.floor(h * 0.6)
	for k = 1, 2 do
		local p = PreviewIcon(f, "dispel" .. k)
		p:SetSize(ds, ds)
		p:ClearAllPoints()
		if cfg.dispelPosition == "SIDE" then
			local offset = gap + (cfg.ccIcon and (cs + gap) * (cfg.ccMax or 2) or 0) + (k - 1) * (ds + 2)
			Beside(p, other, offset, ds)
		else
			local under = (f.Castbar and cfg.castbar.enabled) and f.Castbar or f
			p:SetPoint("TOPLEFT", under, "BOTTOMLEFT", (k - 1) * (ds + 2), -3)
		end
		p:SetShown(cfg.dispelIcons and k <= (d.dispel or 0))
		p.tex:SetTexture(C_Spell.GetSpellTexture(DISPEL_PREVIEW[k]))
		ns.ZoomIcon(p.tex)
	end
	-- trinket
	f.Trinket:SetShown(cfg.trinket and true or false)
	f.Trinket.tex:SetTexture(C_Spell.GetSpellTexture(DEFAULT_TRINKET) or [[Interface\Icons\INV_Jewelry_TrinketPVP_01]])
	ns.ZoomIcon(f.Trinket.tex)
	if d.trinketCD then f.Trinket.cd:SetCooldown(GetTime() - (120 - d.trinketCD), 120) else f.Trinket.cd:Clear() end
end

function Party.FillPreview(f, i)
	local list = PREVIEW[Party.testPreset or "party"] or PREVIEW.party
	local d = list[i]
	if not d then
		f:Hide()
		return
	end
	f:Show()
	f.previewData = d
	f.Health:SetMinMaxValues(0, 1)
	f.Health:SetValue(d.hp)
	local col = C_ClassColor.GetClassColor(d.class)
	if col then f.Health:SetStatusBarColor(col:GetRGB()) end
	f.Name:SetText(d.name)
	f.HealthText:SetText(math.floor(d.hp * 100) .. "%")
	f.Absorb:SetValue(0)
	f.OverAbsorb:SetAlpha(0)
	local cfg = ns.db.party
	local showPower = cfg.power == "all" or (cfg.power ~= "none" and d.healer)
	f.Power:SetShown(showPower)
	f.PowerSeparator:SetShown(showPower)
	f.Health:SetHeight(showPower and (cfg.height - cfg.powerHeight - ns.Pixel(f)) or cfg.height)
	f.Power:SetMinMaxValues(0, 1)
	f.Power:SetValue(0.7)
	f.Power:SetStatusBarColor(0, 0.44, 0.87)
	f.RoleIcon:SetShown(cfg.healerIcon ~= false and d.healer and true or false)
	f.Highlight:SetAlpha(i == 2 and 1 or 0)
	f:SetAlpha(1)
	Party.LayoutPreview(f)
end

-- preset: "party" (tank, healer, two damage) or "arena" (two teammates)
function Party:SetTestMode(on, preset)
	if not Party.holder then return end
	if InCombatLockdown() then
		ns:Print("Can't toggle party test mode in combat.")
		return
	end
	Party.testMode = on or nil
	Party.testPreset = on and (preset or "party") or nil
	for i, f in ipairs(Party.frames) do
		if on then
			UnregisterUnitWatch(f)
			f.preview = true
			f:Show()
			local ok, err = pcall(Party.FillPreview, f, i)
			if not ok then geterrorhandler()(err) end
		else
			f.preview = nil
			f.previewData = nil
			if f.SUIPreview then for _, p in pairs(f.SUIPreview) do p:Hide() end end
			f.Trinket.cd:Clear()
			f.Trinket:Hide()
			RegisterUnitWatch(f)
			UF.SafeUpdateAll(f)
		end
	end
	-- cast bars cast on a loop while testing
	if not castTicker then
		castTicker = CreateFrame("Frame")
		castTicker:SetScript("OnUpdate", UpdatePreviewCasts)
	end
	for _, f in ipairs(Party.frames) do
		if f.Castbar then
			if on then f.Castbar:SetUnit(nil) else f.Castbar:SetUnit(f.unit) end
		end
	end
	castTicker:SetShown(on and true or false)
	if not on then RequestTrinkets() end
	Party:UpdateVisibility()
end

ns:RegisterModule("Party", Party)
