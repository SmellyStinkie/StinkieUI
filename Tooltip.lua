-- StinkieUI: Tooltip. Size, where it shows (at the mouse with offsets, a fixed spot you drag, or
-- Blizzard's), hiding in combat, the health bar, the unit's target ("YOU" in red when it's you),
-- guild ranks, class-colored names and spell / item IDs.
-- Only touches the default-anchored tooltip (world units and frames that use Blizzard's default
-- spot); tooltips that other frames place themselves stay where they are. Lines are added through
-- Blizzard's tooltip data hooks. Anything the game hides from addons (names and classes in rated
-- PvP) is skipped rather than guessed.
local _, ns = ...

local T = {}
ns.Tooltip = T

local issecret = ns.issecret
local function readable(v) return v ~= nil and not issecret(v) end
local function cfg() return ns.db.tooltip end

---------------------------------------------------------------------------
-- Anchoring
---------------------------------------------------------------------------
local function PlaceFixed(tooltip)
	local c = cfg()
	tooltip:ClearAllPoints()
	tooltip:SetPoint(c.fixedPoint or "BOTTOMRIGHT", T.anchor, c.fixedPoint or "BOTTOMRIGHT", 0, 0)
end

-- called by Blizzard each time a tooltip goes to its default spot
local function OnDefaultAnchor(tooltip, parent)
	local c = cfg()
	if not c.enabled or tooltip ~= GameTooltip then return end
	if c.anchor == "mouse" then
		tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", c.offsetX, c.offsetY)
	elseif c.anchor == "fixed" and T.anchor then
		PlaceFixed(tooltip)
	end
end

-- World objects such as signs skip the default spot: the game pins them to the cursor itself. By
-- the time it shows, the text is in, so this moves it without SetOwner, which would clear it.
-- Only the game's own world tooltips: owned by UIParent and following the cursor.
function T.Reanchor(tooltip)
	local c = cfg()
	if c.anchor == "blizzard" or tooltip ~= GameTooltip or tooltip:GetOwner() ~= UIParent then return end
	local kind = tooltip:GetAnchorType()
	if kind ~= "ANCHOR_CURSOR" and kind ~= "ANCHOR_CURSOR_RIGHT" then return end
	if c.anchor == "mouse" then
		tooltip:SetAnchorType("ANCHOR_CURSOR_RIGHT", c.offsetX, c.offsetY)
	elseif T.anchor then
		tooltip:SetAnchorType("ANCHOR_NONE")
		PlaceFixed(tooltip)
	end
end

-- /stinkie tooltip: what the game reports for the tooltip under the mouse, a few seconds from now
-- so there's time to hover over something.
local DEBUG_DELAY = 4
function T.Debug()
	ns:Print("Hover over something: reading the tooltip in " .. DEBUG_DELAY .. " seconds.")
	C_Timer.After(DEBUG_DELAY, function()
		local owner = GameTooltip:GetOwner()
		local name = owner and owner.GetName and owner:GetName()
		ns:Print("Tooltip shown: " .. tostring(GameTooltip:IsShown()))
		ns:Print("Owner: " .. tostring(name or owner))
		ns:Print("Anchor: " .. tostring(GameTooltip:GetAnchorType()))
		ns:Print("First line: " .. tostring(_G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()))
	end)
end

function T.ApplyScale()
	local c = cfg()
	local scale = c.enabled and c.scale or 1
	for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }) do
		local tt = _G[name]
		if tt and tt.SetScale then tt:SetScale(scale) end
	end
end

---------------------------------------------------------------------------
-- Combat hiding and the health bar
---------------------------------------------------------------------------
function T.ShouldHide(isUnit)
	local c = cfg()
	if not c.enabled or c.combat == "show" then return false end
	if not (InCombatLockdown() or UnitAffectingCombat("player")) then return false end
	if c.combatShift and IsShiftKeyDown() then return false end
	if c.combat == "units" then return isUnit and true or false end
	return true -- "all"
end

local function OnShow(tooltip)
	local c = cfg()
	if not c.enabled then return end
	local _, unit = tooltip:GetUnit()
	if T.ShouldHide(issecret(unit) or unit ~= nil) then
		tooltip:Hide()
		return
	end
	local bar = _G.GameTooltipStatusBar
	if bar then bar:SetAlpha(c.healthBar and 1 or 0) end
	T.Reanchor(tooltip)
end

---------------------------------------------------------------------------
-- Unit lines: class-colored name, guild rank, target
---------------------------------------------------------------------------
local function ClassColor(unit)
	local ok, _, token = pcall(UnitClass, unit)
	if not ok or not readable(token) then return nil end
	return RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
end

function T.TargetText(unit)
	local t = unit .. "target"
	local ok, exists = pcall(UnitExists, t)
	if not ok or not readable(exists) or not exists then return nil end
	local okMe, isMe = pcall(UnitIsUnit, t, "player")
	if okMe and readable(isMe) and isMe then return "|cffff3030YOU|r" end
	local name = UnitName(t)
	if not readable(name) then return nil end
	local col = UnitIsPlayer(t) and ClassColor(t)
	if col then return string.format("|cff%02x%02x%02x%s|r", col.r * 255, col.g * 255, col.b * 255, name) end
	return name
end

local function GuildLine(tooltip, unit)
	local c = cfg()
	local guild, rank = GetGuildInfo(unit)
	if not (readable(guild) and guild and readable(rank) and rank) then return end
	local mine = IsInGuild() and GetGuildInfo("player")
	local same = readable(mine) and mine == guild
	if (same and not c.rankOwn) or (not same and not c.rankOther) then return end
	for i = 2, tooltip:NumLines() do
		local fs = _G[tooltip:GetName() .. "TextLeft" .. i]
		local text = fs and fs:GetText()
		if readable(text) and text and text:find(guild, 1, true) and not text:find("(", 1, true) then
			fs:SetText(text .. " |cffaaaaaa(" .. rank .. ")|r")
			if same then fs:SetTextColor(0.40, 1.00, 0.40) end
			return
		end
	end
end

local function OnUnit(tooltip)
	local c = cfg()
	if not c.enabled or tooltip ~= GameTooltip then return end
	local _, unit = tooltip:GetUnit()
	if not readable(unit) or not unit then return end
	local isPlayer = UnitIsPlayer(unit)
	if not readable(isPlayer) then return end
	if isPlayer and c.classNames then
		local col = ClassColor(unit)
		local fs = _G.GameTooltipTextLeft1
		if col and fs then fs:SetTextColor(col.r, col.g, col.b) end
	end
	if isPlayer then pcall(GuildLine, tooltip, unit) end
	if c.target then
		local ok, text = pcall(T.TargetText, unit)
		if ok and text then tooltip:AddLine("Target: " .. text, 1, 0.82, 0) end
	end
	if T.ShouldHide(true) then tooltip:Hide() end
end

---------------------------------------------------------------------------
-- IDs
---------------------------------------------------------------------------
local function AddID(tooltip, label, id)
	if not (cfg().enabled and cfg().ids) or not readable(id) or not id then return end
	tooltip:AddDoubleLine(label, tostring(id), 0.6, 0.6, 0.6, 1, 1, 1)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function T:Init()
	local c = cfg()
	T.anchor = CreateFrame("Frame", "StinkieUI_TooltipAnchor", UIParent)
	T.anchor:SetSize(200, 80)
	ns:RegisterMover("tooltip", T.anchor, "Tooltip (fixed spot)",
		function() return cfg().point end,
		function(p) cfg().point = p end)
	if not c.enabled then return end
	if GameTooltip_SetDefaultAnchor then hooksecurefunc("GameTooltip_SetDefaultAnchor", OnDefaultAnchor) end
	GameTooltip:HookScript("OnShow", OnShow)
	local P = TooltipDataProcessor
	local TT = Enum and Enum.TooltipDataType
	if P and P.AddTooltipPostCall and TT then
		P.AddTooltipPostCall(TT.Unit, function(tt) local ok, err = pcall(OnUnit, tt); if not ok then T.lastError = err end end)
		if TT.Spell then P.AddTooltipPostCall(TT.Spell, function(tt, data) AddID(tt, "Spell ID", data and data.id) end) end
		if TT.UnitAura then P.AddTooltipPostCall(TT.UnitAura, function(tt, data) AddID(tt, "Spell ID", data and data.id) end) end
		if TT.Item then P.AddTooltipPostCall(TT.Item, function(tt, data) AddID(tt, "Item ID", data and data.id) end) end
	end
	-- combat started with a tooltip up
	ns:On("PLAYER_REGEN_DISABLED", function()
		if GameTooltip:IsShown() then
			local _, unit = GameTooltip:GetUnit()
			if T.ShouldHide(issecret(unit) or unit ~= nil) then GameTooltip:Hide() end
		end
	end)
	T:Refresh()
end

function T:Refresh()
	if not T.anchor then return end
	local c = cfg()
	ns:ApplyPoint(T.anchor, c.point)
	T.anchor:SetScale(ns.db.scale)
	T.anchor.SUIActive = (c.enabled and c.anchor == "fixed") and true or false
	T.ApplyScale()
end

ns:RegisterModule("Tooltip", T)
