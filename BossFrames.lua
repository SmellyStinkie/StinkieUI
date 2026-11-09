-- StinkieUI: boss frames (boss1-5). The same flat frames as the other unit frames: health,
-- power, name, health text, raid marker, a castbar under each, and an outline on your target.
-- The game shows and hides each one (unit watch), so they work in combat. Blizzard's boss frames
-- are switched off the same way as its other unit frames.
local _, ns = ...

local BF = {}
ns.BossFrames = BF
BF.MAX = 5
BF.frames = {}

local UF = ns.UF
local function cfg() return ns.db.bossFrames end

local PREVIEW = {
	{ name = "Test Boss 1", hp = 0.82, power = 0.6 },
	{ name = "Test Boss 2", hp = 0.55, power = 0.3 },
	{ name = "Test Boss 3", hp = 0.34, power = 1 },
	{ name = "Test Boss 4", hp = 0.71, power = 0.8 },
	{ name = "Test Boss 5", hp = 0.12, power = 0.2 },
}

-- an outline inside the frame's edge, shown on your current target
local function CreateHighlight(f)
	local hl = CreateFrame("Frame", nil, f)
	hl:SetAllPoints()
	hl:SetFrameLevel(f.TextLayer:GetFrameLevel() + 1)
	hl.edges = {}
	for i = 1, 4 do
		local t = hl:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 1, 1, 0.9)
		hl.edges[i] = t
	end
	hl:SetAlpha(0)
	f.Highlight = hl
end

local function LayoutHighlight(f)
	local px = ns.Pixel(f) * 2
	local e = f.Highlight.edges
	for i = 1, 4 do e[i]:ClearAllPoints() end
	e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(px)
	e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(px)
	e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(px)
	e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(px)
end

function BF.UpdateHighlight(f)
	if f.preview then
		f.Highlight:SetAlpha((cfg().highlight and f.index == 1) and 1 or 0)
		return
	end
	if not cfg().highlight or not f:IsShown() then
		f.Highlight:SetAlpha(0)
		return
	end
	-- UnitIsUnit can be secret: the setter takes it as it is
	f.Highlight:SetAlphaFromBoolean(UnitIsUnit(f.unit, "target"), 1, 0)
end

local function CreateBossFrame(i, holder)
	local unit = "boss" .. i
	local f = UF.CreateFrame(unit, "StinkieUI_Boss" .. i)
	f.index = i
	f:SetParent(holder)
	CreateHighlight(f)
	f.Castbar = ns.CreateCastbar(f)
	f.Castbar.previewLabel = "Big Boss Spell"
	f.Castbar:SetUnit(unit)
	f:HookScript("OnShow", BF.UpdateHighlight)
	return f
end

local function ShowPreview(f, on)
	f.preview = on or nil
	if not on then
		if f.Castbar then f.Castbar:ForceUpdate() end
		UF.SafeUpdateAll(f)
		BF.UpdateHighlight(f)
		return
	end
	local d = PREVIEW[f.index]
	f.Health:SetMinMaxValues(0, 1)
	f.Health:SetValue(d.hp)
	f.Health:SetStatusBarColor(0.78, 0.25, 0.22)
	f.Power:SetMinMaxValues(0, 1)
	f.Power:SetValue(d.power)
	f.Power:SetStatusBarColor(0.25, 0.45, 0.95)
	f.Name:SetText(d.name)
	f.HealthText:SetText(math.floor(d.hp * 100) .. "%")
	UF.PreviewLevel(f)
	if f.Castbar and cfg().castbar.enabled and f.index <= 2 then
		local bar = f.Castbar
		bar.preview = true
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0.4 + f.index * 0.2)
		bar.Text:SetText(bar.previewLabel)
		bar.Time:SetText("")
		bar:Show()
	end
	BF.UpdateHighlight(f)
end

-- Test mode shows all five with stand-in bosses (the game only shows boss units in encounters)
function BF:SetTestMode(on)
	if not BF.active then return end
	if InCombatLockdown() then
		ns:Print("Can't toggle boss frame test mode in combat.")
		return
	end
	BF.testMode = on or nil
	for _, f in ipairs(BF.frames) do
		if on then
			UnregisterUnitWatch(f)
			f:Show()
		else
			if f.Castbar then f.Castbar.preview = nil end
			RegisterUnitWatch(f)
		end
		ShowPreview(f, on)
	end
end

local function LayoutBossFrame(f)
	local c = cfg()
	local lc = {
		width = c.width, height = c.height, showPower = c.showPower, powerHeight = c.powerHeight,
		healthText = c.healthText, shields = c.shields, nameStyle = c.nameStyle, healthStyle = c.healthStyle,
		nameFormat = c.nameFormat, showLevel = c.showLevel, showName = c.showName, leaderIcon = false,
	}
	UF.Layout(f, lc)
	LayoutHighlight(f)
	local cb = f.Castbar
	local on = c.castbar.enabled
	cb.SUIActive = false
	cb:SetParent(f)
	cb:ClearAllPoints()
	local gap = ns.Pixel(f) * 2
	cb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -gap)
	cb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -gap)
	cb:SetHeight(c.castbar.height)
	cb:ApplyConfig({ height = c.castbar.height, showText = true, showTime = true, textStyle = c.castbar.textStyle })
	if (cb.unit ~= nil) ~= on then cb:SetUnit(on and f.unit or nil) end
end

function BF:Init()
	local c = cfg()
	if not c.enabled then return end
	BF.active = true
	for i = 1, BF.MAX do ns.KillBlizzard("Boss" .. i .. "TargetFrame") end

	local holder = CreateFrame("Frame", "StinkieUI_BossHolder", UIParent)
	BF.holder = holder
	ns:RegisterMover("bossFrames", holder, "Boss Frames",
		function() return ns.db.bossFrames.point end,
		function(p) ns.db.bossFrames.point = p end)
	for i = 1, BF.MAX do BF.frames[i] = CreateBossFrame(i, holder) end

	-- boss units can change mob mid-fight; the target outline follows your target
	local driver = CreateFrame("Frame")
	for _, e in ipairs({ "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_TARGETABLE_CHANGED", "PLAYER_TARGET_CHANGED", "ENCOUNTER_END" }) do
		pcall(driver.RegisterEvent, driver, e)
	end
	driver:SetScript("OnEvent", function(_, event)
		for _, f in ipairs(BF.frames) do
			if not f.preview then
				if event ~= "PLAYER_TARGET_CHANGED" and f:IsShown() then
					UF.SafeUpdateAll(f)
					if f.Castbar.unit then f.Castbar:ForceUpdate() end
				end
				BF.UpdateHighlight(f)
			end
		end
	end)

	table.insert(ns.lockCallbacks, function(unlocked)
		if unlocked then
			BF.testFromUnlock = not BF.testMode
			BF:SetTestMode(true)
		elseif BF.testFromUnlock then
			BF.testFromUnlock = nil
			BF:SetTestMode(false)
		end
	end)
	BF:Refresh()
end

function BF:Refresh()
	if not BF.active then return end
	local c = cfg()
	local holder = BF.holder
	local px = ns.Pixel(holder)
	local power = (c.showPower and c.powerHeight > 0) and (c.powerHeight + px) or 0
	local castH = c.castbar.enabled and (c.castbar.height + px * 2) or 0
	local h = c.height + power
	local step = h + castH + c.spacing
	holder:SetScale(ns.db.scale)
	holder:SetSize(c.width, BF.MAX * step - c.spacing)
	ns:ApplyPoint(holder, c.point)
	for i, f in ipairs(BF.frames) do
		LayoutBossFrame(f)
		f:ClearAllPoints()
		if c.growth == "UP" then
			f:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, (i - 1) * step + castH)
		else
			f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * step)
		end
		if f.preview then ShowPreview(f, true) else UF.SafeUpdateAll(f) end
		BF.UpdateHighlight(f)
	end
end

ns:RegisterModule("BossFrames", BF)
