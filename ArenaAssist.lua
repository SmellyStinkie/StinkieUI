-- StinkieUI: PvP Assist (saved settings keep the old key, arenaAssist). Extras for arena and battlegrounds:
--   * "Healer in CC!" warning with the crowd-control icon, movable and sized
--   * Precognition (or any buff you list) on you, big and glowing
--   * enemy interrupt tracker: who kicked you or a teammate, and roughly when it's back
--   * Big Debuffs: crowd control, defensives and offensive cooldowns, big, right of enemy nameplates
--     (built on each nameplate in Nameplates.lua; settings live here)
-- Party trinkets and the party crowd-control glow live on the party frames (Party.lua).
--
-- Midnight rules this follows: aura matching is done by Blizzard's AuraContainer, and the
-- interrupter (name, class) arrives as hidden values that are only ever handed back to the game
-- for display, never read.
local _, ns = ...

local AA = {}
ns.ArenaAssist = AA

local issecret = ns.issecret
local function cfg() return ns.db.arenaAssist end
local function readable(v) return not issecret(v) and v ~= nil end

local function InstanceType()
	local _, t = IsInInstance()
	return t
end

local function Allowed(where)
	local t = InstanceType()
	if where == "always" then return true end
	if where == "arena" then return t == "arena" end
	return t == "arena" or t == "pvp"
end
AA.Allowed = Allowed

local function GlowCfg(prefix)
	local c = cfg()
	return { glow = c[prefix .. "Glow"], glowColor = c[prefix .. "GlowColor"], glowThickness = c[prefix .. "GlowThickness"] }
end

local function IconFrame(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	f.cd:SetDrawEdge(false)
	f.cd:SetReverse(true)
	ns.IconBorder(f)
	return f
end

---------------------------------------------------------------------------
-- Healer in CC
---------------------------------------------------------------------------
local MAX_HEALERS = 8
local healerWatch = {} -- [i] = { container, unit }
AA.healerWatch = healerWatch
local lastSound = 0

local function HealerLabelStyle(fs)
	local c = cfg()
	ns.ApplyText(fs, c.healerTextStyle)
	fs:SetText(c.healerText or "")
end

local function StyleHealerButton(b)
	local c = cfg()
	local size = c.healerIconSize
	b:SetSize(size, size)
	local show = c.healerIcons and 1 or 0
	b.Icon:SetAlpha(show)
	if b.Cooldown then
		b.Cooldown:SetAlpha(show)
		b.Cooldown:SetCountdownFont(ns.AssistCountdownFont(size))
	end
	if b.SUIBorder and b.SUIBorder.SetAlpha then b.SUIBorder:SetAlpha(show) end
	ns.ApplyGlow(b, c.healerIcons and GlowCfg("healer") or { glow = "none" })
	if b.SUIWarning then HealerLabelStyle(b.SUIWarning) end
end

local function DecorateHealerButton(button, textParent)
	-- the warning text belongs to the icon, so it shows exactly while a CC icon does
	local fs = textParent:CreateFontString(nil, "OVERLAY")
	fs:SetPoint("BOTTOM", button, "TOP", 0, 6)
	button.SUIWarning = fs
	-- full style now: once created, the button can't be touched again during a match
	StyleHealerButton(button)
end

local function OnHealerIconShown()
	local c = cfg()
	if not c.healerSound or AA.testMode then return end
	local now = GetTime()
	if now - lastSound < 3 then return end
	lastSound = now
	PlaySound(SOUNDKIT.RAID_WARNING, "Master")
end

-- Restyles existing icons; waits until auras aren't secret (Auras.lua, ns.WhenAurasOpen).
local function StyleHealerButtons(container)
	if not container or not container.SUIButtons then return end
	ns.WhenAurasOpen(container, function()
		for _, b in ipairs(container.SUIButtons) do
			local ok, err = pcall(StyleHealerButton, b)
			if not ok then geterrorhandler()(err); return end
		end
	end)
end

local function HealerContainer(i)
	local w = healerWatch[i]
	if w then return w end
	local c = cfg()
	local container = ns.CreateAuraContainer(AA.healerHolder, { { filter = ns.AuraFilters.cc, max = 1 } }, {
		size = c.healerIconSize, spacing = 4, anchor = "TOPLEFT", growthX = "RIGHT", growthY = "DOWN",
		disableMouse = true, assistCountdown = true,
		glow = function() return GlowCfg("healer") end,
		onShow = OnHealerIconShown,
		decorate = DecorateHealerButton,
	})
	w = { container = container }
	healerWatch[i] = w
	return w
end

local function LayoutHealer()
	local c = cfg()
	local holder = AA.healerHolder
	local size = c.healerIconSize
	local textH = (c.healerTextStyle.size or 40) + 6
	holder:SetSize(math.max(size, 320), size + textH)
	ns:ApplyPoint(holder, c.healerPoint)
	for _, w in ipairs(healerWatch) do
		w.container:ClearAllPoints()
		-- one icon, centered under the text
		w.container:SetPoint("TOPLEFT", holder, "TOP", -size / 2, -textH)
		StyleHealerButtons(w.container)
	end
	local p = AA.healerPreview
	p:SetSize(size, size)
	p:ClearAllPoints()
	p:SetPoint("TOP", holder, "TOP", 0, -textH)
	p.tex:SetAlpha(c.healerIcons and 1 or 0)
	p.cd:SetCountdownFont(ns.AssistCountdownFont(size))
	ns.ApplyGlow(p, c.healerIcons and GlowCfg("healer") or { glow = "none" })
	HealerLabelStyle(AA.healerLabel)
	AA.healerLabel:ClearAllPoints()
	AA.healerLabel:SetPoint("BOTTOM", p, "TOP", 0, 6)
end

-- Healers to watch: your party's healer(s) in arena, every healer in a battleground raid.
local function FindHealers()
	local list = {}
	if UnitGroupRolesAssigned("player") == "HEALER" then return list end
	local prefix, n = "party", 4
	if IsInRaid() and InstanceType() ~= "arena" then prefix, n = "raid", 40 end
	for i = 1, n do
		local u = prefix .. i
		local isMe = UnitIsUnit(u, "player")
		if issecret(isMe) then isMe = false end
		if UnitExists(u) and not isMe then
			local role = UnitGroupRolesAssigned(u)
			if readable(role) and role == "HEALER" then
				table.insert(list, u)
				if #list >= MAX_HEALERS then break end
			end
		end
	end
	return list
end

function AA:UpdateHealers()
	local c = cfg()
	local on = c.healerCC and Allowed(c.healerWhere) and not AA.testMode
	local units = on and FindHealers() or {}
	for i = 1, math.max(#units, #healerWatch) do
		local u = units[i]
		if u then
			local w = HealerContainer(i)
			w.unit = u
			ns.SetAuraUnit(w.container, u)
			StyleHealerButtons(w.container)
		elseif healerWatch[i] then
			healerWatch[i].unit = nil
			ns.SetAuraUnit(healerWatch[i].container, nil)
		end
	end
	LayoutHealer()
end

-- Far-away raid members: Blizzard stops evaluating their auras, so don't watch them then.
local function GateFarHealers()
	for _, w in ipairs(healerWatch) do
		if w.unit then
			local visible = UnitIsVisible(w.unit)
			if issecret(visible) then visible = true end
			ns.SetAuraUnit(w.container, visible and w.unit or nil)
		end
	end
end

---------------------------------------------------------------------------
-- Precognition (and any other buffs on you)
---------------------------------------------------------------------------
function AA:UpdatePrecog()
	local c = cfg()
	local holder = AA.precogHolder
	local size = c.precogSize
	holder:SetSize(size, size)
	ns:ApplyPoint(holder, c.precogPoint)
	if not AA.precog then
		AA.precog = ns.CreateAuraContainer(holder, { { filter = "HELPFUL", max = 3 } }, {
			size = size, spacing = 4, anchor = "TOPLEFT", growthX = "RIGHT", growthY = "DOWN",
			disableMouse = true, assistCountdown = true,
			glow = function() return GlowCfg("precog") end,
		})
		AA.precog:SetPoint("TOPLEFT", holder, "TOPLEFT")
	end
	ns.SetAuraGroupCandidates(AA.precog, 1, { includeSpellIDs = ns.SpellSet(c.precogSpells) or { [377362] = true } })
	ns.RestyleAuraButtons(AA.precog, GlowCfg("precog"), size, true)
	local on = c.precog and Allowed(c.precogWhere) and not AA.testMode
	ns.SetAuraUnit(AA.precog, on and "player" or nil)
	local p = AA.precogPreview
	p:SetSize(size, size)
	p.cd:SetCountdownFont(ns.AssistCountdownFont(size))
	ns.ApplyGlow(p, GlowCfg("precog"))
end

---------------------------------------------------------------------------
-- Enemy interrupts
---------------------------------------------------------------------------
-- Each class's main interrupt, used only when the kicker's class is readable (a kick on you).
-- The class alone can't tell specs apart, so where specs differ this is the spec most often seen
-- in arena. Cooldowns from warcraft.wiki.gg and Blizzard's 12.0 patch notes (checked Nov 2026):
--   melee interrupts are 15 s; Counter Shot, Counterspell and Spell Lock 24 s; Wind Shear 12 s
--   (30 s for Restoration); Quell 40 s, or 20 s with the usual talent; Shadow's Silence is 30 s
--   since 12.0.0; Balance's Solar Beam is 60 s.
local INTERRUPTS = {
	--  class          spell id   seconds   which spec this covers
	{ "ROGUE",        1766,      15 },   -- Kick
	{ "WARRIOR",      6552,      15 },   -- Pummel
	{ "DEATHKNIGHT",  47528,     15 },   -- Mind Freeze
	{ "DEMONHUNTER",  183752,    15 },   -- Disrupt
	{ "MONK",         116705,    15 },   -- Spear Hand Strike (Windwalker / Brewmaster)
	{ "PALADIN",      96231,     15 },   -- Rebuke (Retribution / Protection)
	{ "DRUID",        106839,    15 },   -- Skull Bash (Feral; Balance's Solar Beam is 60)
	{ "HUNTER",       147362,    24 },   -- Counter Shot (BM / MM; Survival's Muzzle is 15)
	{ "MAGE",         2139,      24 },   -- Counterspell
	{ "WARLOCK",      132409,    24 },   -- Spell Lock (Felhunter)
	{ "SHAMAN",       57994,     12 },   -- Wind Shear (Elemental / Enhancement; Restoration 30)
	{ "EVOKER",       351338,    20 },   -- Quell, with its cooldown talent
	{ "PRIEST",       15487,     30 },   -- Silence (Shadow)
}
local KICK_BY_CLASS = {}
for _, row in ipairs(INTERRUPTS) do
	KICK_BY_CLASS[row[1]] = { spell = row[2], seconds = row[3] }
end
local UNKNOWN_KICK = { spell = 1766, seconds = 15 } -- kicker's class hidden: Kick icon, 15 s estimate
local WATCH = { "player", "party1", "party2" }

AA.kicks = {}
local claimed = {}
local kickPool = {}

local function NewKickFrame()
	local f = table.remove(kickPool)
	if f then return f end
	f = IconFrame(AA.kickHolder)
	f.name = ns.CreateText(f, 10, "CENTER")
	f.name:SetPoint("TOP", f, "BOTTOM", 0, -2)
	f.name:SetWordWrap(false)
	return f
end

function AA:LayoutKicks()
	local c = cfg()
	local size = c.kickSize
	local holder = AA.kickHolder
	holder:SetSize(size * c.kickMax + 4 * (c.kickMax - 1), size + (c.kickNames and (c.kickNameStyle.size + 4) or 0))
	ns:ApplyPoint(holder, c.kickPoint)
	local dir = c.kickGrowth == "LEFT" and -1 or 1
	local anchor = dir == 1 and "TOPLEFT" or "TOPRIGHT"
	for i, f in ipairs(AA.kicks) do
		f:SetSize(size, size)
		f:ClearAllPoints()
		f:SetPoint(anchor, holder, anchor, dir * (i - 1) * (size + 4), 0)
		f.cd:SetCountdownFont(ns.AssistCountdownFont(size))
		ns.ApplyText(f.name, c.kickNameStyle)
		f.name:SetWidth(size + 16)
		f.name:SetShown(c.kickNames)
		ns.ApplyGlow(f, GlowCfg("kick"))
	end
end

local function RemoveKick(f)
	for i, k in ipairs(AA.kicks) do
		if k == f then
			table.remove(AA.kicks, i)
			f:Hide()
			f.cd:Clear()
			f.expires = nil
			table.insert(kickPool, f)
			break
		end
	end
	AA:LayoutKicks()
end

-- name / class may be hidden values: they go straight to SetText / SetAtlas, never compared.
function AA:AddKick(name, class, test)
	local c = cfg()
	local spell, duration
	local known = readable(class) and KICK_BY_CLASS[class]
	if known then
		spell, duration = known.spell, known.seconds
	end
	while #AA.kicks >= c.kickMax do RemoveKick(AA.kicks[1]) end
	local f = NewKickFrame()
	if spell then
		f.tex:SetTexture(C_Spell.GetSpellTexture(spell))
		ns.ZoomIcon(f.tex)
	else
		-- class icon from the hidden class token, or the generic Kick icon
		local ok = false
		if issecret(class) or class ~= nil then -- issecret first: a hidden value is never compared
			ok = pcall(f.tex.SetAtlas, f.tex, string.format("classicon-%s", class))
		end
		if not ok then
			f.tex:SetTexture(C_Spell.GetSpellTexture(UNKNOWN_KICK.spell))
			ns.ZoomIcon(f.tex)
		end
	end
	duration = duration or UNKNOWN_KICK.seconds
	if issecret(name) or name ~= nil then f.name:SetText(name) else f.name:SetText("") end
	f.cd:SetCooldown(GetTime(), duration)
	f.expires = (not test) and (GetTime() + duration) or nil
	table.insert(AA.kicks, f)
	f:Show()
	AA:LayoutKicks()
end

-- drop kicks whose cooldown has run out
local function ExpireKicks()
	local now = GetTime()
	for i = #AA.kicks, 1, -1 do
		local f = AA.kicks[i]
		if f.expires and f.expires <= now then RemoveKick(f) end
	end
end

local START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true }

local function OnCastEvent(unit, event, ...)
	local target = ...
	if not issecret(target) and target ~= nil and target ~= unit then return end
	if START[event] then
		claimed[unit] = nil
		return
	end
	if claimed[unit] then return end
	local interruptedBy
	if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		interruptedBy = select(4, ...)
	elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
		interruptedBy = select(5, ...)
	end
	-- nil / empty = the cast just ended. A hidden value means someone interrupted it.
	if not issecret(interruptedBy) and (interruptedBy == nil or interruptedBy == "") then return end
	claimed[unit] = true
	local name = UnitNameFromGUID and UnitNameFromGUID(interruptedBy)
	local class = UnitClassFromGUID and select(2, UnitClassFromGUID(interruptedBy))
	AA:AddKick(name, class)
end

local kickFrames = {}
function AA:UpdateKickEvents()
	local c = cfg()
	local on = c.kicks and InstanceType() == "arena" and not AA.testMode
	for _, unit in ipairs(WATCH) do
		local f = kickFrames[unit]
		if not f then
			f = CreateFrame("Frame")
			f:SetScript("OnEvent", function(_, event, ...) OnCastEvent(unit, event, ...) end)
			kickFrames[unit] = f
		end
		f:UnregisterAllEvents()
		if on then
			for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
				"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP" }) do
				f:RegisterUnitEvent(e, unit)
			end
		end
		claimed[unit] = nil
	end
	if not on and not AA.testMode then
		while #AA.kicks > 0 do RemoveKick(AA.kicks[1]) end
	end
end

---------------------------------------------------------------------------
-- Test mode (also while frames are unlocked)
---------------------------------------------------------------------------
local TEST_KICKS = { { "Emberfall", "MAGE" }, { "Longshot", "HUNTER" }, { "Nightblade", "ROGUE" } }

function AA:SetTestMode(on)
	AA.testMode = on or nil
	local c = cfg()
	AA.healerPreview:SetShown(on and c.healerCC and true or false)
	AA.healerLabel:SetShown(on and c.healerCC and true or false)
	if on then AA.healerPreview.cd:SetCooldown(GetTime(), 6) end
	AA.precogPreview:SetShown(on and c.precog and true or false)
	if on then AA.precogPreview.cd:SetCooldown(GetTime(), 4) end
	while #AA.kicks > 0 do RemoveKick(AA.kicks[1]) end
	if on and c.kicks then
		for i = 1, math.min(c.kickMax, #TEST_KICKS) do
			AA:AddKick(TEST_KICKS[i][1], TEST_KICKS[i][2], true)
		end
	end
	AA:Refresh()
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local function Holder(name, key, label, pointKey)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetFrameStrata("HIGH")
	f:SetSize(40, 40)
	ns:RegisterMover(key, f, label,
		function() return cfg()[pointKey] end,
		function(p) cfg()[pointKey] = p end)
	return f
end

function AA:Init()
	AA.healerHolder = Holder("StinkieUI_HealerCC", "healerCC", "Healer in CC", "healerPoint")
	AA.precogHolder = Holder("StinkieUI_Precog", "precog", "Precognition", "precogPoint")
	AA.kickHolder = Holder("StinkieUI_EnemyKicks", "enemyKicks", "Enemy Kicks", "kickPoint")

	-- test-mode stand-ins
	local hp = IconFrame(AA.healerHolder)
	hp.tex:SetTexture(C_Spell.GetSpellTexture(118)) -- Polymorph
	ns.ZoomIcon(hp.tex)
	hp:Hide()
	AA.healerPreview = hp
	AA.healerLabel = AA.healerHolder:CreateFontString(nil, "OVERLAY")
	AA.healerLabel:Hide()
	local pp = IconFrame(AA.precogHolder)
	pp:SetAllPoints()
	pp.tex:SetTexture(C_Spell.GetSpellTexture(377362) or [[Interface\Icons\Spell_Holy_HolyGuidance]])
	ns.ZoomIcon(pp.tex)
	pp:Hide()
	AA.precogPreview = pp

	local ev = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
		"PVP_MATCH_STATE_CHANGED", "ARENA_PREP_OPPONENT_SPECIALIZATIONS" }) do
		ev:RegisterEvent(e)
	end
	ev:SetScript("OnEvent", function() AA:Refresh() end)
	local elapsed = 0
	ev:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.5 then return end
		elapsed = 0
		if IsInRaid() and not AA.testMode then GateFarHealers() end
		if #AA.kicks > 0 then ExpireKicks() end
	end)

	table.insert(ns.lockCallbacks, function(unlocked)
		if unlocked then
			AA.testFromUnlock = not AA.testMode
			AA:SetTestMode(true)
		elseif AA.testFromUnlock then
			AA.testFromUnlock = nil
			AA:SetTestMode(false)
		end
	end)
	AA:Refresh()
end

function AA:Refresh()
	if not AA.healerHolder then return end
	for _, h in ipairs({ AA.healerHolder, AA.precogHolder, AA.kickHolder }) do h:SetScale(ns.db.scale) end
	-- each part on its own, so a failure in one can't switch off the others
	for _, fn in ipairs({ AA.UpdateHealers, AA.UpdatePrecog, AA.UpdateKickEvents, AA.LayoutKicks }) do
		local ok, err = pcall(fn, AA)
		if not ok then geterrorhandler()(err) end
	end
end

ns:RegisterModule("ArenaAssist", AA)
