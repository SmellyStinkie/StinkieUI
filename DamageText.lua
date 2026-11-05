-- StinkieUI: Damage Numbers. The damage and healing numbers that float over targets in the world
-- (Blizzard's floating combat text): the Stinkie UI font (applied while the world loads, so it
-- takes a relog), plus size, height above the target and spread, through the game's own
-- settings. Each setting is only applied if this game version still has it; /stinkie dmg lists
-- which ones it has. Values left at 0 hand the setting back to the game's default.
local _, ns = ...

local DT = {}
ns.DamageText = DT

local function cfg() return ns.db.damageText end

-- option key -> the game setting(s) it drives. Midnight renamed the world-text settings with a
-- "_v2" ending; each option drives whichever of its names this game version has.
DT.CVARS = {
	size = { "WorldTextScale_v2", "WorldTextScale" },               -- how big the numbers are
	-- Midnight: how far above the nameplate they start, as a share of the screen height
	-- (game defaults 0.015 for normal hits, 0.0275 for crits)
	screenY = { "WorldTextScreenY_v2" },
	critScreenY = { "WorldTextCritScreenY_v2" },
	critSize = { "WorldTextRampPowCrit_v2" },                       -- how big a crit's pop gets
	height = { "WorldTextNonRandomZ" },                             -- older clients: height above the target
	spread = { "WorldTextRandomXY_v2", "WorldTextStartPosRandomness_v2", "WorldTextRandomXY", "WorldTextStartPosRandomness" }, -- sideways scatter
	gravity = { "WorldTextGravity_v2", "WorldTextGravity" },        -- how fast they fall back down
	directional = { "floatingCombatTextCombatDamageDirectionalScale_v2", "floatingCombatTextCombatDamageDirectionalScale" }, -- low = numbers rise straight up
}
-- Scrolling text over your character: this is what shows healing you receive, such as Cannibalize.
-- The checkbox is the game's own setting, so it and the game's options always agree. It also shows
-- the other things Blizzard scrolls there, like damage you take.
function DT.ScrollingText()
	return GetCVarBool("enableFloatingCombatText") and true or false
end

function DT.SetScrollingText(on)
	SetCVar("enableFloatingCombatText", on and "1" or "0")
end

-- How that scrolling text looks. Blizzard draws a large font shrunk down to size, which spaces a
-- narrow font oddly, so each new line is set to a real size instead. Blizzard's own tables stay
-- untouched: this is a post-hook on the lines it makes, and its gap between lines on its frame.
DT.FLOAT_MODE = "floatingCombatTextFloatMode_v2"
local BLIZZARD_SPACING = 10

local function ScrollFont(fs, size)
	local c = cfg().scroll
	fs:SetFont(ns.GetFontPath(), size, ns.OutlineFlags(c.outline) or "")
	fs:SetTextHeight(size)
end

-- Heal or damage, from what Blizzard made: damage reads -123, heals +123 in green. Mana gains also
-- start with + but aren't green. A hidden (secret) line can't be read, so it scrolls as usual.
function DT.ScrollKind(message, r, g)
	if ns.issecret(message) or type(message) ~= "string" then return nil end
	local first = message:sub(1, 1)
	if first == "-" then return "damage" end
	if first == "+" and r == 0.1 and g == 1 then return "heal" end
end

-- Which way a line goes: 1 up, -1 down, nil for Blizzard's own direction.
function DT.ScrollLane(split, kind)
	if not kind or split == "same" then return nil end
	if split == "healsUp" then return kind == "heal" and 1 or -1 end
	return kind == "heal" and -1 or 1
end

-- Blizzard stacks every new line under all the others, so a line going the other way would drag
-- the rest after it. Each direction gets its own lane beside the middle, stacked on its own.
local LANE_X, LINE_HEIGHT = 40, 16

local function PlaceInLane(frame, fs, lane)
	local spot = frame.textLocations
	local step = LINE_HEIGHT + frame.textSpacing
	local y = spot.startY
	for _, line in ipairs(frame.activeFontStrings) do
		if line ~= fs and line.SUILane == lane then
			local below = line.yPos - lane * step
			if lane * (y - below) > 0 then y = below end
		end
	end
	if lane * (spot.startY - y) > frame.textOffsetMax then y = spot.startY - lane * frame.textOffsetMax end
	fs.SUILane = lane
	fs.startX = spot.startX + lane * LANE_X * frame.textScaleX
	fs.startY, fs.yPos = y, y
	fs.endY = spot.startY + lane * math.abs(spot.endY - spot.startY)
	fs.scrollFunction = CombatTextUtil.StandardScroll -- Arc doesn't use the end point
	fs:ClearAllPoints()
	fs:SetPoint("TOP", WorldFrame, "BOTTOM", fs.startX, y)
end

function DT.StyleScrollLine(_, message, _, r, g)
	local frame = _G.CombatText
	local c = cfg().scroll
	local list = frame and frame.activeFontStrings
	local fs = list and list[#list]
	if not (c.enabled and fs) then return end
	local lane = DT.ScrollLane(c.split, DT.ScrollKind(message, r, g))
	if lane then PlaceInLane(frame, fs, lane) else fs.SUILane = nil end
	if fs.isCrit then
		if c.critPop then return end -- Blizzard grows and shrinks it
		fs.isCrit = nil
		ScrollFont(fs, c.critSize)
	else
		ScrollFont(fs, c.size)
	end
end

-- Blizzard works its gap out again whenever the screen or a setting changes.
function DT.ApplyScrollSpacing()
	local frame = _G.CombatText
	if not (frame and frame.textScaleY) then return end
	local c = cfg().scroll
	frame.textSpacing = (c.enabled and c.spacing or BLIZZARD_SPACING) * frame.textScaleY
end

-- Blizzard's scrolling text is its own addon, loaded when it's first needed.
function DT.HookScrollingText()
	local frame = _G.CombatText
	if DT.scrollHooked or not (frame and frame.AddMessage and frame.UpdateDisplayedMessages) then return end
	DT.scrollHooked = true
	hooksecurefunc(frame, "AddMessage", DT.StyleScrollLine)
	hooksecurefunc(frame, "UpdateDisplayedMessages", DT.ApplyScrollSpacing)
	DT.ApplyScrollSpacing()
end

function DT.ScrollDirection()
	return GetCVar(DT.FLOAT_MODE)
end

function DT.SetScrollDirection(mode)
	SetCVar(DT.FLOAT_MODE, mode)
	local frame = _G.CombatText
	if frame and frame.UpdateDisplayedMessages then frame:UpdateDisplayedMessages() end
end

-- Your own healing numbers. On/off rather than a value, and Blizzard's settings have no box for it.
DT.HEALING = { "floatingCombatTextCombatHealing_v2", "floatingCombatTextCombatHealing" }
DT.ORDER = { "screenY", "height", "size", "critScreenY", "critSize", "spread", "gravity", "directional" }

local function HasCVar(name)
	local ok, v = pcall(C_CVar.GetCVar, name)
	return ok and v ~= nil
end
DT.HasCVar = HasCVar

-- does this game have any setting behind this option?
function DT.Available(key)
	for _, name in ipairs(DT.CVARS[key] or {}) do
		if HasCVar(name) then return true end
	end
	return false
end

local function Restore(name)
	local ok, def = pcall(C_CVar.GetCVarDefault, name)
	if ok and def then pcall(C_CVar.SetCVar, name, def) end
end

function DT.Apply()
	local c = cfg()
	for _, name in ipairs(DT.HEALING) do
		if HasCVar(name) then pcall(C_CVar.SetCVar, name, c.healing and "1" or "0") end
	end
	c.touched = c.touched or {}
	-- settings an earlier version changed that no option drives any more go back to the default
	local driven = {}
	for _, names in pairs(DT.CVARS) do for _, n in ipairs(names) do driven[n] = true end end
	for name in pairs(c.touched) do
		if not driven[name] then
			if HasCVar(name) then Restore(name) end
			c.touched[name] = nil
		end
	end
	for key, names in pairs(DT.CVARS) do
		local v = c.enabled and c[key]
		for _, name in ipairs(names) do
			if HasCVar(name) then
				if v and v ~= 0 then
					pcall(C_CVar.SetCVar, name, tostring(v))
					c.touched[name] = true
				elseif c.touched[name] then
					Restore(name)
					c.touched[name] = nil
				end
			end
		end
	end
end

-- /stinkie dmg: which settings this game has and their values, plus every world-text setting
-- the game lists with its value
function DT.Print()
	for _, key in ipairs(DT.ORDER) do
		local found = {}
		for _, name in ipairs(DT.CVARS[key]) do
			local ok, v = pcall(C_CVar.GetCVar, name)
			if ok and v ~= nil then found[#found + 1] = name .. " = " .. tostring(v) end
		end
		ns:Print(key .. ": " .. (#found > 0 and table.concat(found, ", ") or "not in this game version"))
	end
	local ok, all = pcall(ConsoleGetAllCommands)
	if ok and type(all) == "table" then
		local names = {}
		for _, c in ipairs(all) do
			local n = type(c) == "table" and c.command
			if type(n) == "string" and n:find("^WorldText") then
				local okv, v = pcall(C_CVar.GetCVar, n)
				names[#names + 1] = n .. " = " .. tostring(okv and v or "?")
			end
		end
		table.sort(names)
		ns:Print("World text settings (" .. #names .. "): " .. (#names > 0 and table.concat(names, ", ") or "none"))
	end
	for _, name in ipairs(DT.HEALING) do
		local ok, v = pcall(C_CVar.GetCVar, name)
		if ok and v ~= nil then ns:Print("Healing numbers: " .. name .. " = " .. tostring(v)) end
	end
	ns:Print("Healing you receive (scrolling text): enableFloatingCombatText = " .. tostring(DT.ScrollingText()))
	local okp, periodic = pcall(C_CVar.GetCVar, "floatingCombatTextCombatLogPeriodicSpells_v2")
	if okp and periodic ~= nil then ns:Print("Periodic spells: floatingCombatTextCombatLogPeriodicSpells_v2 = " .. tostring(periodic)) end
	ns:Print("Font: " .. (ns.db.combatTextFont and "Stinkie UI (after a relog)" or "Blizzard's"))
	ns:Print("Game's damage font: " .. tostring(DAMAGE_TEXT_FONT))
	if ns.db.combatTextFont then
		ns:Print("Font file ready when the game was given it: " .. tostring(ns.damageFontReady))
	end
end

function DT:Init()
	ns:On("PLAYER_ENTERING_WORLD", function() DT.Apply() end)
	DT.HookScrollingText()
	ns:On("ADDON_LOADED", function(_, name)
		if name == "Blizzard_CombatText" then DT.HookScrollingText() end
	end)
end

function DT:Refresh()
	DT.Apply()
	DT.ApplyScrollSpacing()
end

ns:RegisterModule("DamageText", DT)
