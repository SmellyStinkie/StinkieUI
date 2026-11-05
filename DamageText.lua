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
	ns:Print("Font: " .. (ns.db.combatTextFont and "Stinkie UI (after a relog)" or "Blizzard's"))
	ns:Print("Game's damage font: " .. tostring(DAMAGE_TEXT_FONT))
	if ns.db.combatTextFont then
		ns:Print("Font file ready when the game was given it: " .. tostring(ns.damageFontReady))
	end
end

function DT:Init()
	ns:On("PLAYER_ENTERING_WORLD", function() DT.Apply() end)
end

function DT:Refresh()
	DT.Apply()
end

ns:RegisterModule("DamageText", DT)
