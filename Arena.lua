-- StinkieUI: arena frames (arena1-3).
--
-- Midnight makes arena data secret, so this module leans on Blizzard's own secure pieces:
--   * spec icon / healer icon / prep-phase class color: UnitFrameUtil.UpdateArenaOpponentSpecDisplay
--   * trinket: Blizzard's CcRemoverFrame, moved into our frame and restyled
--   * DR: Blizzard's SpellDiminishStatusTray, moved into our frame, restyled and re-ordered
--   * teammates targeting: UnitIsUnit("partyNtarget", arenaN) applied with SetAlphaFromBoolean
-- Nothing is written into Blizzard's tables; per-frame state lives in our own weak tables.
local _, ns = ...

local UF = ns.UF
local A = {}
ns.Arena = A
A.frames = {}

local MAX = 3
local issecret = ns.issecret
local BLANK = [[Interface\AddOns\StinkieUI\Media\blank.tga]]
-- a green cross (thin black outline) for healers (a texture file, which Blizzard's spec delegate accepts like an atlas)
local ROLE_MAP = { HEALER = ns.MEDIA.cross, TANK = BLANK, DAMAGER = BLANK }
local TEAMMATES = { "party1", "party2" }

A.DR_ORDER = { "Stun", "Incapacitate", "Disorient", "Silence", "Root", "Disarm", "Taunt", "AoEKnockback" }
A.DR_LABELS = {
	Stun = "Stun", Incapacitate = "Incapacitate", Disorient = "Disorient (fear)", Silence = "Silence",
	Root = "Root", Disarm = "Disarm", Taunt = "Taunt", AoEKnockback = "Knockback",
}

local trays = setmetatable({}, { __mode = "k" })     -- Blizzard DR tray -> our frame
local drKey = setmetatable({}, { __mode = "k" })     -- DR tray item -> category key (or false if unreadable)
local styled = setmetatable({}, { __mode = "k" })
local anchorFns = setmetatable({}, { __mode = "k" })
local anchorGuard = setmetatable({}, { __mode = "k" })

local function cfg() return ns.db.arena end

local function OtherArenaAddon()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
	if not loaded then return nil end
	for _, name in ipairs({ "sArena_Reloaded", "sArena", "sArena_Updated2_by_sammers", "Gladius", "GladiusEx" }) do
		if loaded(name) then return name end
	end
end

---------------------------------------------------------------------------
-- Health / power split (healer power bars)
---------------------------------------------------------------------------
local function IsHealer(unit)
	local role = UnitGroupRolesAssigned(unit)
	if not issecret(role) and role and role ~= "NONE" then
		return role == "HEALER"
	end
	-- role is hidden in rated arena: fall back to "uses mana" (healers plus a few casters)
	local pType = UnitPowerType(unit)
	if issecret(pType) then return true end
	return pType == Enum.PowerType.Mana
end

local function ShouldShowPower(f)
	local mode = cfg().power
	if mode == "none" then return false end
	if mode == "all" then return true end
	if f.preview then return f.previewHealer end
	return IsHealer(f.unit)
end

local function SplitPower(f, showPower)
	local c = cfg()
	local px = ns.Pixel(f)
	f.Power:SetShown(showPower)
	f.PowerSeparator:SetShown(showPower)
	f.Health:SetHeight(showPower and (c.height - c.powerHeight - px) or c.height)
end

local function PostUpdate(f)
	local show = ShouldShowPower(f)
	SplitPower(f, show)
	if show then UF.UpdatePower(f, true) end
	f.Highlight:SetAlphaFromBoolean(UnitIsUnit(f.unit, "target"), 1, 0)
end

---------------------------------------------------------------------------
-- Spec icon, healer icon, prep-phase display
---------------------------------------------------------------------------
local function UpdateSpec(f)
	local U = UnitFrameUtil
	if not (U and U.UpdateArenaOpponentSpecDisplay) or f.preview then return end
	local c = cfg()
	local exists = UnitExists(f.unit)
	if issecret(exists) then exists = true end
	local elements = {
		specPortrait = c.specIcon and f.Spec.tex or nil,
		roleIcon = c.healerIcon and f.Role or nil,
		specNameText = (not exists) and f.Name or nil,
		barTexture = (not exists) and f.Health:GetStatusBarTexture() or nil,
	}
	pcall(U.UpdateArenaOpponentSpecDisplay, elements, f.index, ROLE_MAP)
	if not exists then
		-- before gates open: full bar in the spec's class color, spec name as the name
		f.Health:SetMinMaxValues(0, 1)
		f.Health:SetValue(1)
		f.HealthText:SetText("")
	end
end

---------------------------------------------------------------------------
-- Teammates targeting this enemy: one square per teammate, lit when they target it
---------------------------------------------------------------------------
local function UpdateDots(f)
	local show = cfg().targetDots
	for j, unit in ipairs(TEAMMATES) do
		local dot = f.Dots[j]
		if f.preview then
			dot:SetAlpha(show and j <= f.previewDots and 1 or 0)
			local dc = cfg().dotColor
			dot.tex:SetVertexColor(dc[1], dc[2], dc[3])
		elseif show and UnitExists(unit) then
			if cfg().dotClassColor then
				dot.tex:SetVertexColor(ns.GetUnitClassColor(unit):GetRGB())
			else
				local dc = cfg().dotColor
				dot.tex:SetVertexColor(dc[1], dc[2], dc[3])
			end
			local ok, isTarget = pcall(UnitIsUnit, unit .. "target", f.unit)
			if not (ok and pcall(dot.SetAlphaFromBoolean, dot, isTarget, 1, 0)) then
				dot:SetAlpha(0)
			end
		else
			dot:SetAlpha(0)
		end
	end
end

---------------------------------------------------------------------------
-- Blizzard DR tray: restyle items, filter categories, order them
---------------------------------------------------------------------------
local function CategoryKey(category)
	local E = Enum.SpellDiminishCategory
	if not E or issecret(category) or category == nil then return nil end
	for _, k in ipairs(A.DR_ORDER) do
		if E[k] == category then return k end
	end
end

function A.StyleDRItem(item, info)
	local tray = item:GetParent()
	local f = tray and trays[tray]
	if not f then return end
	local c = cfg()
	if info then
		drKey[item] = CategoryKey(info.category) or false
	end
	if not styled[item] then
		styled[item] = true
		if item.Icon then ns.ZoomIcon(item.Icon) end
		ns.IconBorder(item)
		if item.Cooldown then
			item.Cooldown:SetSwipeTexture(ns.TEXTURE)
			item.Cooldown:SetCountdownFont(ns.GetCountdownFont(c.drSize * 0.42))
		end
	end
	item:SetSize(c.drSize, c.drSize)
	local key = drKey[item]
	local enabled = (not key) or (c.drCategories[key] ~= false)
	item:SetAlpha(enabled and 1 or 0)
end

function A.LayoutDR(tray)
	local f = trays[tray]
	if not f then return end
	local c = cfg()
	local items = {}
	for _, child in ipairs({ tray:GetChildren() }) do
		if child:IsShown() and child.Icon then
			A.StyleDRItem(child)
			if child:GetAlpha() > 0 then table.insert(items, child) end
		end
	end
	local order = {}
	for i, k in ipairs(A.DR_ORDER) do order[k] = i end
	local rank = {}
	for i, item in ipairs(items) do rank[item] = (order[drKey[item] or ""] or 50) * 100 + i end
	table.sort(items, function(a, b) return rank[a] < rank[b] end)
	local step = c.drSize + 3
	for i, item in ipairs(items) do
		item:ClearAllPoints()
		if c.drSide == "LEFT" then
			item:SetPoint("RIGHT", f.DRAnchor, "RIGHT", -(i - 1) * step, 0)
		else
			item:SetPoint("LEFT", f.DRAnchor, "LEFT", (i - 1) * step, 0)
		end
	end
end

-- Keeps a moved Blizzard frame on our anchor even when Blizzard re-points it.
local function PinTo(frame, fn)
	if not anchorFns[frame] then
		hooksecurefunc(frame, "SetPoint", function(self)
			if anchorGuard[self] then return end
			local pin = anchorFns[self]
			if pin then
				anchorGuard[self] = true
				pin(self)
				anchorGuard[self] = nil
			end
		end)
	end
	anchorFns[frame] = fn
	anchorGuard[frame] = true
	fn(frame)
	anchorGuard[frame] = nil
end

function A:HookDRMixin()
	if A.drHooked or not SpellDiminishStatusTrayItemMixin then return end
	A.drHooked = true
	hooksecurefunc(SpellDiminishStatusTrayItemMixin, "SetCategoryInfo", function(item, info)
		A.StyleDRItem(item, info)
	end)
end

---------------------------------------------------------------------------
-- Take over Blizzard's arena trinket + DR widgets and hide its arena frames
---------------------------------------------------------------------------
function A:AttachBlizzard()
	if A.attached or not A.active then return end
	local caf = _G.CompactArenaFrame
	if not (caf and caf.memberUnitFrames) then return end
	if InCombatLockdown() then
		ns:RunOOC(function() A:AttachBlizzard() end)
		return
	end
	A.attached = true
	A:HookDRMixin()
	if caf.SetRolesets then caf:SetRolesets("alwaysBlocked") end
	local prep = _G.ArenaPreMatchFramesContainer
	if prep and prep.SetRolesets then prep:SetRolesets("alwaysBlocked") end

	local c = cfg()
	for i = 1, MAX do
		local m, f = caf.memberUnitFrames[i], A.frames[i]
		if m and f then
			local cc = m.CcRemoverFrame
			if cc and c.trinket then
				cc:SetParent(f.Trinket)
				cc:SetFrameLevel(f.Trinket:GetFrameLevel() + 2)
				PinTo(cc, function(self)
					self:ClearAllPoints()
					self:SetAllPoints(f.Trinket)
				end)
				if cc.Icon then ns.ZoomIcon(cc.Icon) end
				ns.IconBorder(cc)
				if cc.Cooldown then
					cc.Cooldown:SetSwipeTexture(ns.TEXTURE)
					cc.Cooldown:SetCountdownFont(ns.GetCountdownFont(c.trinketSize * 0.4))
				end
				f.blizzTrinket = cc
			end
			local tray = m.SpellDiminishStatusTray
			if tray and c.dr then
				trays[tray] = f
				tray:SetParent(f.DRAnchor)
				tray:ClearAllPoints()
				tray:SetPoint("CENTER", f.DRAnchor, "CENTER")
				if tray.RefreshTrayLayout then
					hooksecurefunc(tray, "RefreshTrayLayout", function(t) A.LayoutDR(t) end)
				end
				A.LayoutDR(tray)
				f.blizzTray = tray
			end
		end
	end
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function OnEventExtra(f, event)
	if event == "ARENA_OPPONENT_UPDATE" or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
		UpdateSpec(f)
		-- a new opponent in this slot (next game / next Solo Shuffle round): refresh the name too
		if not f.preview then UF.SafeUpdateAll(f) end
	end
end

-- Wipes what the last game left on a frame, so old names never carry over.
local function ClearFrame(f)
	if f.preview then return end
	f.Name:SetText("")
	f.HealthText:SetText("")
	f.Health:SetMinMaxValues(0, 1)
	f.Health:SetValue(1)
end

local function CreateHighlight(f)
	local hl = CreateFrame("Frame", nil, f)
	hl:SetAllPoints()
	hl:SetFrameLevel(f.TextLayer:GetFrameLevel() + 1)
	hl.edges = {}
	for i = 1, 4 do
		local t = hl:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 1, 1, 1)
		hl.edges[i] = t
	end
	hl:SetAlpha(0)
	f.Highlight = hl
end

-- right-click action -> secure button type (nil = does nothing)
local RIGHT_CLICK = { focus = "focus", target = "target", menu = "togglemenu", none = nil }

local function CreateArenaFrame(i, holder)
	local f = UF.CreateFrame("arena" .. i, "StinkieUI_Arena" .. i, true)
	f:SetParent(holder)
	f:Hide()
	f.index = i
	f.forceClassColor = true
	f:SetAttribute("*type2", "focus")
	f.PostUpdate = PostUpdate
	f.OnEventExtra = OnEventExtra
	f:RegisterEvent("ARENA_OPPONENT_UPDATE")
	f:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")

	CreateHighlight(f)

	-- spec icon (left)
	local spec = CreateFrame("Frame", nil, f)
	spec.tex = spec:CreateTexture(nil, "ARTWORK")
	spec.tex:SetAllPoints()
	ns.ZoomIcon(spec.tex)
	ns.IconBorder(spec)
	f.Spec = spec

	-- healer icon (Blizzard sizes it to 12x12; the holder scales it)
	local roleHolder = CreateFrame("Frame", nil, f.TextLayer)
	roleHolder:SetSize(12, 12)
	local role = roleHolder:CreateTexture(nil, "OVERLAY")
	role:SetPoint("CENTER")
	role:SetSize(12, 12)
	role:SetVertexColor(ns.HEALER_GREEN[1], ns.HEALER_GREEN[2], ns.HEALER_GREEN[3], 1)
	f.RoleHolder, f.Role = roleHolder, role

	-- teammates targeting
	f.Dots = {}
	for j = 1, #TEAMMATES do
		local dot = CreateFrame("Frame", nil, f.TextLayer)
		dot.tex = dot:CreateTexture(nil, "OVERLAY")
		dot.tex:SetAllPoints()
		dot.tex:SetColorTexture(1, 1, 1, 1)
		ns.CreateBackdrop(dot, 0)
		dot:SetAlpha(0)
		f.Dots[j] = dot
	end

	-- trinket slot (right) and DR anchor
	local trinket = CreateFrame("Frame", nil, f)
	trinket.preview = trinket:CreateTexture(nil, "ARTWORK")
	trinket.preview:SetAllPoints()
	trinket.preview:SetTexture([[Interface\Icons\INV_Jewelry_TrinketPVP_01]])
	ns.ZoomIcon(trinket.preview)
	trinket.preview:Hide()
	f.Trinket = trinket
	f.DRAnchor = CreateFrame("Frame", nil, f)
	f.DRPreview = {}

	-- castbar
	if cfg().castbar.enabled then
		f.Castbar = ns.CreateCastbar(f)
		f.Castbar.previewLabel = "Polymorph"
		f.Castbar:SetUnit(f.unit)
	end
	return f
end

local function LayoutArenaFrame(f)
	local c = cfg()
	UF.Layout(f, {
		width = c.width, height = c.height,
		showPower = false, powerHeight = c.powerHeight,
		showName = true, nameAbove = false,
		healthText = c.healthText,
		nameStyle = c.nameStyle, healthStyle = c.healthStyle,
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
	f.Name:ClearAllPoints()
	f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
	f.Name:SetPoint("RIGHT", f, "RIGHT", -40, 0)
	f.HealthText:ClearAllPoints()
	f.HealthText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -3)

	-- target border: thickness in pixels, drawn just outside the frame so it never covers the bars
	local e = f.Highlight.edges
	local t = px * (c.targetBorder or 3)
	local tc = c.targetColor or { 1, 1, 1, 1 }
	for i = 1, 4 do e[i]:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1) end
	e[1]:ClearAllPoints(); e[1]:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -t, 0); e[1]:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", t, 0); e[1]:SetHeight(t)
	e[2]:ClearAllPoints(); e[2]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -t, 0); e[2]:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", t, 0); e[2]:SetHeight(t)
	e[3]:ClearAllPoints(); e[3]:SetPoint("TOPRIGHT", f, "TOPLEFT"); e[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT"); e[3]:SetWidth(t)
	e[4]:ClearAllPoints(); e[4]:SetPoint("TOPLEFT", f, "TOPRIGHT"); e[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT"); e[4]:SetWidth(t)

	local gap = 3
	local h = c.height
	f.Spec:SetShown(c.specIcon)
	f.Spec:SetSize(h, h)
	f.Spec:ClearAllPoints()
	f.Spec:SetPoint("TOPRIGHT", f, "TOPLEFT", -gap, 0)
	ns.IconBorder(f.Spec)

	-- Blizzard forces the icon to 12x12, so size comes from scaling its holder
	local rs = c.healerSize or 14
	local inset = 3 * 12 / rs
	local anchor = c.healerAnchor or "BOTTOMRIGHT"
	local sx = anchor:find("LEFT") and inset or -inset
	local sy = anchor:find("TOP") and -inset or inset
	f.RoleHolder:SetShown(c.healerIcon)
	f.RoleHolder:SetScale(rs / 12)
	f.RoleHolder:ClearAllPoints()
	f.RoleHolder:SetPoint(anchor, f.Health, anchor, sx, sy)

	local ds = c.dotSize or 7
	for j, dot in ipairs(f.Dots) do
		dot:SetSize(ds, ds)
		dot:ClearAllPoints()
		dot:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -(j - 1) * (ds + 3), 3)
		ns.UpdateBackdrop(dot)
	end

	f.Trinket:SetShown(c.trinket)
	f.Trinket:SetSize(c.trinketSize, c.trinketSize)
	f.Trinket:ClearAllPoints()
	f.Trinket:SetPoint("TOPLEFT", f, "TOPRIGHT", gap, 0)

	f.DRAnchor:SetShown(c.dr)
	f.DRAnchor:SetSize(c.drSize, c.drSize)
	f.DRAnchor:ClearAllPoints()
	if c.drSide == "LEFT" then
		f.DRAnchor:SetPoint("TOPRIGHT", c.specIcon and f.Spec or f, "TOPLEFT", -gap, 0)
	else
		f.DRAnchor:SetPoint("TOPLEFT", c.trinket and f.Trinket or f, "TOPRIGHT", gap, 0)
	end
	if f.blizzTray then A.LayoutDR(f.blizzTray) end

	if f.Castbar then
		f.Castbar:ClearAllPoints()
		f.Castbar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -px * 2)
		f.Castbar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -px * 2)
		f.Castbar:SetHeight(c.castbar.height)
		f.Castbar:ApplyConfig({ height = c.castbar.height, showText = true, showTime = true, textStyle = c.castbar.textStyle })
	end
end

---------------------------------------------------------------------------
-- Visibility: shown for every opponent slot during an arena match (stay visible while
-- an enemy is stealthed, dimmed), hidden elsewhere. Only changed out of combat.
---------------------------------------------------------------------------
function A:UpdateVisibility()
	if A.testMode then return end
	local _, instanceType = IsInInstance()
	local n = 0
	if instanceType == "arena" then
		n = math.max(GetNumArenaOpponentSpecs and GetNumArenaOpponentSpecs() or 0, GetNumArenaOpponents and GetNumArenaOpponents() or 0)
		n = math.min(n, MAX)
	end
	ns:RunOOC(function()
		for i, f in ipairs(A.frames) do
			if i <= n then
				if not f:IsShown() then f:Show() end
				UpdateSpec(f)
				UF.SafeUpdateAll(f)
			elseif f:IsShown() then
				f:Hide()
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Test mode (also shown while frames are unlocked)
---------------------------------------------------------------------------
local previewData = {
	{ name = "Stinkie", class = "WARLOCK", icon = [[Interface\Icons\ClassIcon_Warlock]], hp = 0.82, dots = 1, healer = false },
	{ name = "Pinkie", class = "PRIEST", icon = [[Interface\Icons\ClassIcon_Priest]], hp = 0.55, dots = 0, healer = true },
	{ name = "Minkie", class = "MAGE", icon = [[Interface\Icons\ClassIcon_Mage]], hp = 0.31, dots = 2, healer = false },
}
local previewDR = { [[Interface\Icons\Ability_Rogue_KidneyShot]], [[Interface\Icons\Spell_Shadow_Possession]], [[Interface\Icons\Spell_Nature_Polymorph]] }

local function ShowPreview(f, on)
	local d = previewData[f.index]
	f.preview = on or nil
	f.previewHealer = d.healer
	f.previewDots = d.dots
	f.Trinket.preview:SetShown(on and cfg().trinket)
	for k = 1, #previewDR do
		local p = f.DRPreview[k]
		if not p then
			p = CreateFrame("Frame", nil, f.DRAnchor)
			p.tex = p:CreateTexture(nil, "ARTWORK")
			p.tex:SetAllPoints()
			p.tex:SetTexture(previewDR[k])
			ns.ZoomIcon(p.tex)
			ns.IconBorder(p)
			f.DRPreview[k] = p
		end
		local size = cfg().drSize
		p:SetSize(size, size)
		p:ClearAllPoints()
		if cfg().drSide == "LEFT" then
			p:SetPoint("RIGHT", f.DRAnchor, "RIGHT", -(k - 1) * (size + 3), 0)
		else
			p:SetPoint("LEFT", f.DRAnchor, "LEFT", (k - 1) * (size + 3), 0)
		end
		ns.IconBorder(p)
		p:SetShown(on and cfg().dr and k <= f.index)
	end
	if not on then
		if f.Castbar then f.Castbar:ForceUpdate() end
		return
	end
	f.Health:SetMinMaxValues(0, 1)
	f.Health:SetValue(d.hp)
	local col = C_ClassColor.GetClassColor(d.class)
	f.Health:SetStatusBarColor(col:GetRGB())
	f.Name:SetText(d.name)
	f.HealthText:SetText(math.floor(d.hp * 100) .. "%")
	f.Spec.tex:SetTexture(d.icon)
	if d.healer then f.Role:SetTexture(ns.MEDIA.cross) end
	f.Role:SetShown(d.healer)
	SplitPower(f, ShouldShowPower(f))
	f.Power:SetMinMaxValues(0, 1)
	f.Power:SetValue(0.7)
	f.Power:SetStatusBarColor(0, 0.44, 0.87)
	f.Absorb:SetValue(0)
	f.OverAbsorb:SetAlpha(0)
	UpdateDots(f)
	if f.Castbar and f.index == 3 then
		f.Castbar:SetMinMaxValues(0, 1)
		f.Castbar:SetValue(0.6)
		f.Castbar.Text:SetText("Polymorph")
		f.Castbar:GetStatusBarTexture():SetVertexColor(unpack(ns.db.colors.castInterruptible))
		f.Castbar:Show()
	end
end

function A:SetTestMode(on)
	if not A.active then return end
	if InCombatLockdown() then
		ns:Print("Can't toggle arena test mode in combat.")
		return
	end
	A.testMode = on or nil
	for _, f in ipairs(A.frames) do
		if on then f:Show() end
		ShowPreview(f, on)
	end
	if not on then A:UpdateVisibility() end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function A:Init()
	local c = cfg()
	if not c.enabled or not ns.HAS_ARENA then return end
	local other = OtherArenaAddon()
	if other then
		C_Timer.After(6, function()
			ns:Print("Arena frames are off because " .. other .. " is running. Disable one of them.")
		end)
		return
	end
	A.active = true

	local holder = CreateFrame("Frame", "StinkieUI_ArenaHolder", UIParent)
	A.holder = holder
	ns:RegisterMover("arena", holder, "Arena",
		function() return ns.db.arena.point end,
		function(p) ns.db.arena.point = p end)
	for i = 1, MAX do
		A.frames[i] = CreateArenaFrame(i, holder)
	end

	ns:RunOOC(function()
		if c.dr then SetCVar("spellDiminishPVPEnemiesEnabled", "1") end
		SetCVar("spellDiminishPVPOnlyTriggerableByMe", c.drOnlyMine and "1" or "0")
	end)

	A:HookDRMixin()
	if CompactArenaFrame_Generate then
		hooksecurefunc("CompactArenaFrame_Generate", function() A:AttachBlizzard() end)
	end
	ns:On("ADDON_LOADED", function(_, name)
		if name == "Blizzard_SpellDiminishUI" then A:HookDRMixin() end
	end)

	local driver = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ARENA_OPPONENT_UPDATE",
		"ARENA_PREP_OPPONENT_SPECIALIZATIONS", "PVP_MATCH_STATE_CHANGED", "UNIT_TARGET", "PLAYER_TARGET_CHANGED",
		"GROUP_ROSTER_UPDATE" }) do
		driver:RegisterEvent(e)
	end
	driver:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
			for _, f in ipairs(A.frames) do ClearFrame(f) end
		end
		if event == "UNIT_TARGET" or event == "PLAYER_TARGET_CHANGED" then
			for _, f in ipairs(A.frames) do
				if f:IsShown() then
					UpdateDots(f)
					if not f.preview then f.Highlight:SetAlphaFromBoolean(UnitIsUnit(f.unit, "target"), 1, 0) end
				end
			end
			return
		end
		A:AttachBlizzard()
		A:UpdateVisibility()
	end)
	-- dim enemies you can't see (stealth), keep dots fresh
	local elapsed = 0
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.2 then return end
		elapsed = 0
		for _, f in ipairs(A.frames) do
			if f:IsShown() and not f.preview then
				local exists = UnitExists(f.unit)
				if issecret(exists) then exists = true end
				f:SetAlpha(exists and 1 or 0.45)
				UpdateDots(f)
			end
		end
	end)

	table.insert(ns.lockCallbacks, function(unlocked)
		if unlocked then
			A.testFromUnlock = not A.testMode
			A:SetTestMode(true)
		elseif A.testFromUnlock then
			A.testFromUnlock = nil
			A:SetTestMode(false)
		end
	end)

	A:Refresh()
	A:AttachBlizzard()
end

function A:Refresh()
	if not A.active then return end
	local c = cfg()
	local holder = A.holder
	local castH = (c.castbar.enabled and (c.castbar.height + 2)) or 0
	local step = c.height + castH + c.spacing
	holder:SetScale(ns.db.scale)
	holder:SetSize(c.width, MAX * step - c.spacing)
	ns:ApplyPoint(holder, c.point)
	for i, f in ipairs(A.frames) do
		LayoutArenaFrame(f)
		f:ClearAllPoints()
		if c.growth == "UP" then
			f:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, (i - 1) * step + castH)
		else
			f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * step)
		end
		if f.preview then ShowPreview(f, true) else UF.SafeUpdateAll(f) end
		f:SetAttribute("*type2", RIGHT_CLICK[c.rightClick or "focus"])
	end
	SetCVar("spellDiminishPVPOnlyTriggerableByMe", c.drOnlyMine and "1" or "0")
end

ns:RegisterModule("Arena", A)
