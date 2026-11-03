-- StinkieUI: party targets. A small frame for each party member's target, lined up with the
-- party frames. partyNtarget is a compound unit token, which Blizzard refuses to addons inside
-- arenas and battlegrounds, so these are blank there and hidden there by default. They poll 5
-- times a second while shown (compound tokens have no events).
local _, ns = ...

local PT = {}
ns.PartyTargets = PT
PT.frames = {}

local UF = ns.UF
local function cfg() return ns.db.partyTargets end

local PREVIEW = {
	{ name = "Training Dummy", class = nil, hp = 0.72 },
	{ name = "Pinkie", class = "PRIEST", hp = 0.45 },
	{ name = "Stinkie", class = "WARLOCK", hp = 0.9 },
	{ name = "Minkie", class = "MAGE", hp = 0.3 },
	{ name = "Winkie", class = "ROGUE", hp = 0.6 },
}

local function PartyUnits()
	local units = {}
	if ns.db.party.showPlayer then units[#units + 1] = "target" end
	for i = 1, 4 do units[#units + 1] = "party" .. i .. "target" end
	return units
end

-- the vertical step between party frames, so target rows line up with them
local function PartyStep()
	local p = ns.db.party
	local castH = (p.castbar.enabled and (p.castbar.height + 2)) or 0
	if p.dispelIcons and p.dispelPosition ~= "SIDE" then castH = castH + math.floor(p.height * 0.6) + 3 end
	return p.height + castH + p.spacing, castH
end

function PT:UpdateVisibility()
	local h = PT.holder
	if not h then return end
	ns:RunOOC(function()
		local _, t = IsInInstance()
		local pvp = (t == "pvp" or t == "arena")
		local partyHidden = ns.db.party.hideInBattlegrounds and t == "pvp"
		local hide = (cfg().hideInPvP and pvp) or partyHidden
		if ns.unlocked or PT.testMode then hide = false end
		h:SetShown(not hide)
	end)
end

function PT:Init()
	local c = cfg()
	if not c.enabled then return end
	local h = CreateFrame("Frame", "StinkieUI_PartyTargetHolder", UIParent)
	PT.holder = h
	ns:RegisterMover("partyTargets", h, "Party Targets",
		function() return cfg().point end,
		function(p) cfg().point = p end)
	for i, unit in ipairs(PartyUnits()) do
		local f = UF.CreateFrame(unit, "StinkieUI_PartyTarget" .. i)
		f.forceClassColor = true
		f:SetParent(h)
		PT.frames[i] = f
	end
	ns:On("PLAYER_ENTERING_WORLD", function() PT:UpdateVisibility() end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() PT:UpdateVisibility() end)
	table.insert(ns.lockCallbacks, function(unlocked)
		if unlocked then
			PT.fromUnlock = not PT.testMode
			PT:SetTestMode(true)
		elseif PT.fromUnlock then
			PT.fromUnlock = nil
			PT:SetTestMode(false)
		end
	end)
	PT:Refresh()
end

function PT:Refresh()
	local h = PT.holder
	if not h then return end
	local c = cfg()
	local step = PartyStep()
	local grow = ns.db.party.growth
	local n = #PT.frames
	h:SetScale(ns.db.scale)
	h:SetSize(c.width, math.max(c.height, n * step - ns.db.party.spacing))
	ns:ApplyPoint(h, c.point)
	for i, f in ipairs(PT.frames) do
		UF.Layout(f, c)
		f:ClearAllPoints()
		-- centered on the party frame's health row
		local y = (ns.db.party.height - c.height) / 2
		if grow == "UP" then
			local _, castH = PartyStep()
			f:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, (i - 1) * step + castH + y)
		else
			f:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -(i - 1) * step - y)
		end
		if f.preview then PT.FillPreview(f, i) else UF.SafeUpdateAll(f) end
	end
	PT:UpdateVisibility()
end

function PT.FillPreview(f, i)
	local d = PREVIEW[i] or PREVIEW[1]
	f.Name:SetText(d.name)
	local col = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
	if col then f.Health:SetStatusBarColor(col.r, col.g, col.b) else f.Health:SetStatusBarColor(0.8, 0.2, 0.2) end
	f.Health:SetMinMaxValues(0, 1)
	f.Health:SetValue(d.hp)
	f.HealthText:SetText(math.floor(d.hp * 100) .. "%")
end

function PT:SetTestMode(on)
	if not PT.holder then return end
	if InCombatLockdown() then return end
	PT.testMode = on or nil
	for i, f in ipairs(PT.frames) do
		if on then
			UnregisterUnitWatch(f)
			f.preview = true
			f:Show()
			PT.FillPreview(f, i)
		else
			f.preview = nil
			RegisterUnitWatch(f)
			UF.SafeUpdateAll(f)
		end
	end
	PT:UpdateVisibility()
end

ns:RegisterModule("PartyTargets", PT)
