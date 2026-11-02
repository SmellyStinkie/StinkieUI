-- StinkieUI: class resource bar (soul shards, combo points, holy power, chi, arcane charges, essence).
-- One flat bar with 1px separators between segments. Destruction shows partial shards.
-- The player's own class resource is not a secret value, so plain math is fine here.
local _, ns = ...

local CP = {}
ns.ClassPower = CP

local PT = Enum.PowerType
local SPEC_MAGE_ARCANE, SPEC_MONK_WINDWALKER, SPEC_WARLOCK_DESTRUCTION = 1, 3, 3

-- default colors per resource (used unless a custom color is set)
local resourceColors = {
	[PT.SoulShards] = { 0.64, 0.36, 0.98 },
	[PT.ComboPoints] = { 1.00, 0.82, 0.15 },
	[PT.HolyPower] = { 0.95, 0.88, 0.45 },
	[PT.Chi] = { 0.35, 0.95, 0.75 },
	[PT.ArcaneCharges] = { 0.35, 0.60, 1.00 },
	[PT.Essence] = { 0.30, 0.80, 0.90 },
}
CP.resourceColors = resourceColors

-- Returns powerType, fractional (bool) for the current class/spec/form, or nil.
local function GetResource()
	local _, class = UnitClass("player")
	if not ns.IsUsable(class) then return end
	local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
	local spec = getSpec and getSpec()
	if class == "WARLOCK" then
		return PT.SoulShards, spec == SPEC_WARLOCK_DESTRUCTION
	elseif class == "ROGUE" then
		return PT.ComboPoints
	elseif class == "DRUID" then
		if UnitPowerType("player") == PT.Energy then return PT.ComboPoints end
	elseif class == "PALADIN" then
		return PT.HolyPower
	elseif class == "MONK" then
		if spec == SPEC_MONK_WINDWALKER then return PT.Chi end
	elseif class == "MAGE" then
		if spec == SPEC_MAGE_ARCANE then return PT.ArcaneCharges end
	elseif class == "EVOKER" then
		return PT.Essence
	end
end
CP.GetResource = GetResource

local function LayoutSeparators(bar, max)
	local cfg = ns.db.classPower
	local px = ns.Pixel(bar)
	for _, sep in ipairs(bar.separators) do sep:Hide() end
	if not cfg.separators or max < 2 then return end
	local w = bar:GetWidth()
	for i = 1, max - 1 do
		local sep = bar.separators[i]
		if not sep then
			sep = bar.sepLayer:CreateTexture(nil, "OVERLAY")
			sep:SetColorTexture(0, 0, 0, 1)
			bar.separators[i] = sep
		end
		sep:ClearAllPoints()
		sep:SetPoint("TOP", bar, "TOPLEFT", w * i / max, 0)
		sep:SetPoint("BOTTOM", bar, "BOTTOMLEFT", w * i / max, 0)
		sep:SetWidth(px * (cfg.separatorSize or 1))
		sep:Show()
	end
end

function CP:Update()
	local bar = CP.bar
	if not bar then return end
	local cfg = ns.db.classPower
	if not cfg.enabled or not CP.powerType then
		bar:Hide()
		return
	end
	local pt = CP.powerType
	local max = UnitPowerMax("player", pt)
	if not ns.IsUsable(max) or not max or max <= 0 then
		bar:Hide()
		return
	end
	local cur
	if CP.fractional then
		cur = UnitPower("player", pt, true) / UnitPowerDisplayMod(pt)
	else
		cur = UnitPower("player", pt)
	end
	if not ns.IsUsable(cur) then cur = 0 end

	if max ~= bar.max or bar.lastWidth ~= bar:GetWidth() then
		bar.max = max
		bar.lastWidth = bar:GetWidth()
		LayoutSeparators(bar, max)
	end
	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
	bar.Text:SetText(math.floor(cur + 0.001))
	bar.Text:SetShown(cfg.showText)
	bar:Show()
end

function CP:UpdateResource()
	CP.powerType, CP.fractional = GetResource()
	local cfg = ns.db.classPower
	local c = (cfg.useCustomColor or not resourceColors[CP.powerType]) and cfg.color or resourceColors[CP.powerType]
	if CP.bar then CP.bar:SetStatusBarColor(c[1], c[2], c[3]) end
	CP:Update()
end

function CP:Init()
	local cfg = ns.db.classPower
	local bar = CreateFrame("StatusBar", "StinkieUI_ClassPower", UIParent)
	bar:SetStatusBarTexture(ns.TEXTURE)
	bar:SetFrameStrata("MEDIUM")
	ns.CreateBackdrop(bar)
	bar.separators = {}
	bar.sepLayer = CreateFrame("Frame", nil, bar)
	bar.sepLayer:SetAllPoints()
	bar.sepLayer:SetFrameLevel(bar:GetFrameLevel() + 2)
	bar.Text = ns.CreateText(bar.sepLayer, 12, "CENTER")
	bar.Text:SetPoint("CENTER")
	bar:SetScript("OnSizeChanged", function(self)
		self.lastWidth = nil
		if self.max then LayoutSeparators(self, self.max) end
	end)
	bar:Hide()
	CP.bar = bar

	ns:RegisterMover("classPower", bar, "Class Resource",
		function() return ns.db.classPower.point end,
		function(p) ns.db.classPower.point = p end)

	bar:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	bar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	bar:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	bar:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	bar:RegisterEvent("PLAYER_ENTERING_WORLD")
	bar:RegisterEvent("SPELLS_CHANGED")
	bar:SetScript("OnEvent", function(_, event)
		if event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
			CP:Update()
		else
			CP:UpdateResource()
		end
	end)
	-- a preview so it can be positioned on any character
	table.insert(ns.lockCallbacks, function(unlocked)
		if unlocked and ns.db.classPower.enabled then
			bar:SetMinMaxValues(0, 5)
			bar:SetValue(2.4)
			LayoutSeparators(bar, 5)
			bar.max = nil
			bar.Text:SetText(2)
			bar:Show()
		else
			CP:Update()
		end
	end)
	CP:Refresh()
	if not cfg.enabled then bar:Hide() end
end

function CP:Refresh()
	local bar = CP.bar
	if not bar then return end
	local cfg = ns.db.classPower
	local playerFrame = ns.UF and ns.UF.frames.player
	bar:ClearAllPoints()
	if cfg.attached and playerFrame then
		local px = ns.Pixel(playerFrame)
		bar:SetScale(1)
		bar:SetParent(playerFrame)
		bar:SetPoint("BOTTOMLEFT", playerFrame, "TOPLEFT", 0, px * 3)
		bar:SetPoint("BOTTOMRIGHT", playerFrame, "TOPRIGHT", 0, px * 3)
		bar:SetHeight(cfg.height)
		bar.SUIActive = false
	else
		bar:SetParent(UIParent)
		bar:SetScale(ns.db.scale)
		bar:SetSize(cfg.width, cfg.height)
		ns:ApplyPoint(bar, cfg.point)
		bar.SUIActive = cfg.enabled
	end
	ns.UpdateBackdrop(bar)
	ns.ApplyText(bar.Text, cfg.textStyle)
	bar.lastWidth = nil
	CP:UpdateResource()
end

ns:RegisterModule("ClassPower", CP)
