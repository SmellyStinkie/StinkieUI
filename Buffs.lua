-- StinkieUI: Buff frame. Blizzard's buff and debuff icons (top right) with a flat look: zoomed
-- icons, a 1px border, and your font for the duration and stack count. Can hide them in arenas,
-- battlegrounds, dungeons, raids, everywhere, or in combat, and bring them back on mouseover.
-- Position, size, icons per row and direction stay in Edit Mode.
-- Hiding uses transparency only (never Hide/Show on Blizzard's frames), so nothing gets tainted.
-- Hidden icons are invisible but still there (a right-click on that spot still cancels a buff).
local _, ns = ...

local B = {}
ns.Buffs = B

local function cfg() return ns.db.buffs end

local function Frames()
	return _G.BuffFrame, _G.DebuffFrame
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local function SkinButton(button, debuff)
	local icon = button.Icon
	if not (icon and icon.SetTexCoord) then return end -- private aura anchors have no texture
	local c = cfg()
	local on = c.enabled and c.skin
	if on and c.zoom then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else icon:SetTexCoord(0, 1, 0, 1) end
	if not button.SUIEdge then
		local e = CreateFrame("Frame", nil, button)
		e:SetAllPoints(icon)
		ns.CreateBackdrop(e, 0)
		e.SUIBorder.bg:Hide()
		button.SUIEdge = e
	end
	button.SUIEdge:SetShown(on and c.border and true or false)
	if on and c.border then
		if button.TempEnchantBorder and button.TempEnchantBorder:IsShown() then
			ns.SetBorderColor(button.SUIEdge, 0.60, 0.25, 0.90, 1) -- weapon enchant: purple
		else
			ns.SetBorderColor(button.SUIEdge, 0, 0, 0, 1)
		end
		-- debuffs keep Blizzard's type-colored border (magic, poison ...); the round enchant art goes
		if button.TempEnchantBorder then button.TempEnchantBorder:SetAlpha(0) end
	elseif button.TempEnchantBorder then
		button.TempEnchantBorder:SetAlpha(1)
	end
	if on then
		if button.Duration then
			ns.ApplyText(button.Duration, c.durationStyle)
			if not button.SUIFontHook then
				-- some locales swap the duration font every frame; put ours back after it
				button.SUIFontHook = true
				hooksecurefunc(button.Duration, "SetFontObject", function(fs)
					local cc = cfg()
					if cc.enabled and cc.skin then ns.ApplyText(fs, cc.durationStyle) end
				end)
			end
		end
		if button.Count then
			ns.ApplyText(button.Count, c.countStyle)
			button.Count:ClearAllPoints()
			button.Count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 2)
		end
	end
end

local function SkinFrame(frame, debuff)
	if not (frame and frame.auraFrames) then return end
	for _, button in ipairs(frame.auraFrames) do SkinButton(button, debuff) end
end

function B.ApplySkin()
	local buffs, debuffs = Frames()
	SkinFrame(buffs, false)
	SkinFrame(debuffs, true)
end

---------------------------------------------------------------------------
-- Auto hide
---------------------------------------------------------------------------
function B.WantHidden()
	local c = cfg()
	if not c.enabled then return false end
	if c.hideCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then return true end
	if c.hideAlways then return true end
	local k = ns.Objectives and ns.Objectives.InstanceKind and ns.Objectives.InstanceKind() or "world"
	return (k == "arena" and c.hideArena) or (k == "pvp" and c.hideBG) or (k == "raid" and c.hideRaid)
		or ((k == "dungeon" or k == "mplus") and c.hideDungeon) or false
end

local function SetFrameAlpha(frame, alpha)
	if not frame then return end
	frame:SetAlpha(alpha)
	-- the expand / collapse arrow sits outside the buff frame's rectangle on some layouts
	if frame.CollapseAndExpandButton then frame.CollapseAndExpandButton:SetAlpha(alpha) end
end

local function MouseOver(frame)
	return frame and frame:IsVisible() and frame:IsMouseOver(8, -8, -8, 8)
end

function B.UpdateVisibility()
	local c = cfg()
	local buffs, debuffs = Frames()
	local hidden = B.WantHidden()
	local showBuffs = not hidden or (c.mouseover and MouseOver(buffs))
	SetFrameAlpha(buffs, showBuffs and 1 or 0)
	if c.debuffs then
		local showDebuffs = not hidden or (c.mouseover and MouseOver(debuffs))
		SetFrameAlpha(debuffs, showDebuffs and 1 or 0)
	elseif debuffs then
		SetFrameAlpha(debuffs, 1)
	end
	-- poll the mouse only while something is hidden and mouseover can bring it back
	B.poll:SetShown(hidden and c.mouseover and true or false)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function B:Init()
	B.poll = CreateFrame("Frame")
	B.poll:Hide()
	local acc = 0
	B.poll:SetScript("OnUpdate", function(_, dt)
		acc = acc + dt
		if acc < 0.15 then return end
		acc = 0
		B.UpdateVisibility()
	end)
	local buffs, debuffs = Frames()
	for _, f in ipairs({ buffs, debuffs }) do
		if f and f.UpdateAuraButtons then
			hooksecurefunc(f, "UpdateAuraButtons", function(self) SkinFrame(self, self == debuffs) end)
		end
	end
	local function Update() B.UpdateVisibility() end
	ns:On("PLAYER_ENTERING_WORLD", Update)
	ns:On("ZONE_CHANGED_NEW_AREA", Update)
	ns:On("PLAYER_REGEN_DISABLED", function() C_Timer.After(0, Update) end)
	ns:On("PLAYER_REGEN_ENABLED", Update)
	B.ApplySkin()
	Update()
end

function B:Refresh()
	if not B.poll then return end
	B.ApplySkin()
	B.UpdateVisibility()
end

ns:RegisterModule("Buffs", B)
