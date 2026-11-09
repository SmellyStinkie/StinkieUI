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
-- narrow font oddly, so each new line is set to a real size instead.
-- Hooks only, and only widget calls on Blizzard's lines. Never write a value into its frame or
-- lines, or call its methods: its code does sums on secret numbers, which it may only do untainted,
-- so one value written from here breaks it (seen as "secret number value" at CombatText.lua:360).
-- What this needs to remember lives in its own tables.
DT.FLOAT_MODE = "floatingCombatTextFloatMode_v2"
local LANE_X, LINE_HEIGHT = 40, 16
local lineSize = setmetatable({}, { __mode = "k" }) -- line -> the height it keeps
local lineLane = setmetatable({}, { __mode = "k" }) -- line -> its place in a heal / damage lane
local hookedLine = setmetatable({}, { __mode = "k" })
local placing = false

local function LaneY(s, now)
	local t = math.min(1, (now - s.born) / CombatTextConstants.MessageScrollSpeed)
	return s.startY + s.lane * s.distance * t
end

-- Blizzard moves each line every frame; these put it back where it belongs straight after.
local function KeepPlace(fs)
	local s = lineLane[fs]
	if placing or not s then return end
	placing = true
	fs:SetPoint("TOP", WorldFrame, "BOTTOM", s.x, LaneY(s, GetTime()))
	placing = false
end

local function KeepSize(fs)
	local size = lineSize[fs]
	if placing or not size then return end
	placing = true
	fs:SetTextHeight(size)
	placing = false
end

local function ScrollFont(fs, size)
	local c = cfg().scroll
	placing = true
	fs:SetFont(ns.GetFontPath(), size, ns.OutlineFlags(c.outline) or "")
	fs:SetTextHeight(size)
	placing = false
	lineSize[fs] = size
end

-- Heal or damage. Readable lines by their text: damage reads -123, heals +123 in green (mana gains
-- also start with + but aren't green). Hidden (secret) numbers can't be read, but their color can.
function DT.ScrollKind(message, r, g)
	if ns.issecret(message) then
		if r == 0.1 and g == 1 then return "heal" end
		if (r == 1 and g == 0.1) or (r == 0.79 and g == 0.3) then return "damage" end
		return nil
	end
	if type(message) ~= "string" then return nil end
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

-- Each direction has its own lane beside the middle, stacked on its own: Blizzard's stacking puts a
-- new line under all the others, so a line going the other way would drag the rest after it.
local function JoinLane(frame, fs, lane)
	local now = GetTime()
	local spot = frame.textLocations
	local step = LINE_HEIGHT + cfg().scroll.spacing * frame.textScaleY
	local y = spot.startY
	for line, s in pairs(lineLane) do
		if line ~= fs and s.lane == lane and now - s.born < CombatTextConstants.MessageScrollSpeed then
			local below = LaneY(s, now) - lane * step
			if lane * (y - below) > 0 then y = below end
		end
	end
	if lane * (spot.startY - y) > frame.textOffsetMax then y = spot.startY - lane * frame.textOffsetMax end
	lineLane[fs] = {
		lane = lane, born = now, startY = y,
		x = spot.startX + lane * LANE_X * frame.textScaleX,
		distance = math.abs(spot.endY - spot.startY),
	}
	KeepPlace(fs)
end

function DT.StyleScrollLine(_, message, _, r, g)
	local frame = _G.CombatText
	local c = cfg().scroll
	local list = frame and frame.activeFontStrings
	local fs = list and list[#list]
	if not fs then return end
	lineLane[fs], lineSize[fs] = nil, nil
	if not c.enabled then return end
	if not hookedLine[fs] then
		hookedLine[fs] = true
		hooksecurefunc(fs, "SetPoint", KeepPlace)
		hooksecurefunc(fs, "SetTextHeight", KeepSize)
	end
	local lane = DT.ScrollLane(c.split, DT.ScrollKind(message, r, g))
	if lane then JoinLane(frame, fs, lane) end
	if not fs.isCrit then
		ScrollFont(fs, c.size)
	elseif not c.critPop then
		ScrollFont(fs, c.critSize)
	end
end
DT.LaneOf = function(fs) return lineLane[fs] end
DT.SizeOf = function(fs) return lineSize[fs] end
DT.ForgetLines = function() lineLane, lineSize = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" }) end

-- Blizzard's scrolling text is its own addon, loaded when it's first needed.
function DT.HookScrollingText()
	local frame = _G.CombatText
	if DT.scrollHooked or not (frame and frame.AddMessage) then return end
	DT.scrollHooked = true
	hooksecurefunc(frame, "AddMessage", DT.StyleScrollLine)
end

-- One choice, so the directions can't disagree: the game's own Up, Down or Arc, or heals and damage
-- going opposite ways (then everything else scrolls up). The game reads its setting when the UI
-- loads, and calling Blizzard's update from here would taint it, so this needs a reload.
function DT.ScrollMode()
	local split = cfg().scroll.split
	if split ~= "same" then return split end
	return GetCVar(DT.FLOAT_MODE)
end

function DT.SetScrollMode(mode)
	local c = cfg().scroll
	if mode == "healsUp" or mode == "healsDown" then
		c.split = mode
		SetCVar(DT.FLOAT_MODE, "1")
	else
		c.split = "same"
		SetCVar(DT.FLOAT_MODE, mode)
	end
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
		if HasCVar(name) then
			ns.Modules.Remember("damageText", name)
			pcall(C_CVar.SetCVar, name, c.healing and "1" or "0")
		end
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
					ns.Modules.Remember("damageText", name)
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
end

ns:RegisterModule("DamageText", DT)
