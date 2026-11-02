-- StinkieUI: combat indicator (icon on the player frame or anywhere) and a short
-- "Entering Combat" / "Leaving Combat" message.
local _, ns = ...

local CB = {}
ns.CombatIndicator = CB

local ATLAS = "UI-HUD-UnitFrame-Player-CombatIcon"

local function cfg() return ns.db.combat end

local function InCombat()
	return UnitAffectingCombat("player") or InCombatLockdown()
end

function CB:UpdateIcon()
	local c = cfg()
	local f = CB.icon
	if not f then return end
	f:SetShown(c.icon and (InCombat() or ns.unlocked) and true or false)
end

local function Flash(text, color)
	local c = cfg()
	if not c.text then return end
	local t = CB.text
	t.fs:SetText(text)
	t.fs:SetTextColor(color[1], color[2], color[3])
	t.elapsed = 0
	t:SetAlpha(1)
	t:Show()
end

local function TextOnUpdate(self, dt)
	if ns.unlocked then self:SetAlpha(1) return end
	self.elapsed = (self.elapsed or 0) + dt
	local hold = cfg().textDuration
	if self.elapsed > hold then
		local a = 1 - (self.elapsed - hold) / 0.4
		if a <= 0 then self:Hide() return end
		self:SetAlpha(a)
	end
end

function CB:Init()
	local c = cfg()
	if not c.enabled then return end

	local icon = CreateFrame("Frame", "StinkieUI_CombatIcon", UIParent)
	icon.tex = icon:CreateTexture(nil, "OVERLAY")
	icon.tex:SetAllPoints()
	icon.tex:SetAtlas(ATLAS)
	icon:Hide()
	CB.icon = icon
	ns:RegisterMover("combatIcon", icon, "Combat Icon",
		function() return ns.db.combat.point end,
		function(p) ns.db.combat.point = p end)

	local text = CreateFrame("Frame", "StinkieUI_CombatText", UIParent)
	text:SetSize(240, 30)
	text:SetFrameStrata("HIGH")
	text.fs = ns.CreateText(text, 20, "CENTER")
	text.fs:SetPoint("CENTER")
	text:SetScript("OnUpdate", TextOnUpdate)
	text:Hide()
	CB.text = text
	ns:RegisterMover("combatText", text, "Combat Text",
		function() return ns.db.combat.textPoint end,
		function(p) ns.db.combat.textPoint = p end)

	ns:On("PLAYER_REGEN_DISABLED", function()
		CB:UpdateIcon()
		Flash("Entering Combat", cfg().enterColor)
	end)
	ns:On("PLAYER_REGEN_ENABLED", function()
		CB:UpdateIcon()
		Flash("Leaving Combat", cfg().leaveColor)
	end)
	ns:On("PLAYER_ENTERING_WORLD", function() CB:UpdateIcon() end)

	table.insert(ns.lockCallbacks, function(unlocked)
		CB:UpdateIcon()
		if unlocked then
			if cfg().text then
				text.fs:SetText("Entering Combat")
				local col = cfg().enterColor
				text.fs:SetTextColor(col[1], col[2], col[3])
				text:SetAlpha(1)
				text:Show()
			end
		else
			text:Hide()
		end
	end)
	CB:Refresh()
end

function CB:Refresh()
	local icon, text = CB.icon, CB.text
	if not icon then return end
	local c = cfg()
	icon:SetSize(c.size, c.size)
	icon:SetScale(ns.db.scale)
	icon:SetFrameStrata("HIGH")
	local player = ns.UF and ns.UF.frames and ns.UF.frames.player
	icon:ClearAllPoints()
	if c.attached and player then
		icon:SetParent(player)
		icon:SetScale(1)
		icon:SetPoint("CENTER", player, c.attachPoint, c.attachX, c.attachY)
		icon.SUIActive = false -- not separately movable
	else
		icon:SetParent(UIParent)
		ns:ApplyPoint(icon, c.point)
		icon.SUIActive = true
	end
	CB:UpdateIcon()

	ns.ApplyText(text.fs, c.textStyle)
	text:SetSize(math.max(120, c.textStyle.size * 12), c.textStyle.size + 10)
	text:SetScale(ns.db.scale)
	ns:ApplyPoint(text, c.textPoint)
	text.SUIActive = c.text
end

ns:RegisterModule("Combat", CB)
