-- StinkieUI: modules. Which parts of the addon load at all, picked by the player (per profile,
-- ns.db.modules[id]). A module that's off never runs its Init: no events, no hooks, no frames and
-- no game settings written. Its file still loads, so its options page and helpers stay available.
-- Changes take effect on /reload.
--
-- The small core is always on and isn't listed here: options, profiles, fonts and media, slash
-- commands, roles (healer lookup the frames share) and castbars (built by the frame modules).
--
-- Each module may also have its own "Enabled" box on its options page. That one still turns the
-- feature on and off live; this one decides whether its code loads.
local _, ns = ...

local M = {}
ns.Modules = M

M.CATEGORIES = { "Unit Frames", "PvP", "Interface", "Quality of Life" }

local function notForever() return not ns.IS_FOREVER end

-- id, name, desc, category, files = registered module names (ns:RegisterModule), pages = options
-- pages it owns, enabled = its own settings with an "enabled" box, requires = module ids,
-- conflicts = addons that turn it off (the module's own check does the turning off)
M.LIST = {
	{ id = "unitFrames", name = "Unit Frames", category = "Unit Frames", files = { "UnitFrames" },
		desc = "Player, target, target of target, focus and pet frames.",
		pages = { "Player", "Target", "Target of Target", "Focus", "Pet" } },
	{ id = "party", name = "Party Frames", category = "Unit Frames", files = { "Party" }, enabled = { "party" },
		desc = "Party frames with crowd control and defensive icons on the side.", pages = { "Party" } },
	{ id = "partyTargets", name = "Party Targets", category = "Unit Frames", files = { "PartyTargets" },
		enabled = { "partyTargets" }, requires = { "party" },
		desc = "A small frame for each party member's target, beside the party frames.", pages = { "Party Targets" } },
	{ id = "bossFrames", name = "Boss Frames", category = "Unit Frames", files = { "BossFrames" }, enabled = { "bossFrames" },
		desc = "Flat frames for up to five bosses, with castbars and your target outlined.", pages = { "Boss Frames" } },
	{ id = "arena", name = "Arena Frames", category = "PvP", files = { "Arena" }, enabled = { "arena" },
		available = function() return ns.HAS_ARENA end, conflicts = function() return ns.Arena.CONFLICTS end,
		desc = "Enemy arena frames with trinkets, diminishing returns and specs.", pages = { "Arena Frames" } },
	{ id = "pvpAssist", name = "PvP Assist", category = "PvP", files = { "ArenaAssist" },
		desc = "Healer in CC warnings, big buff and debuff icons, and other arena and BG helpers.", pages = { "PvP Assist" } },

	{ id = "bgFrames", name = "Battleground Frames", category = "PvP", files = { "BGEnemies" },
		enabled = { "bgEnemies", "bgAllies" },
		desc = "Frames for the enemy team and your own in battlegrounds and Blitz.", pages = { "Battleground Frames" } },
	{ id = "bgScore", name = "BG Score", category = "PvP", files = { "BGWidgets" }, enabled = { "bgWidgets" },
		desc = "Moves, scales and restyles the battleground score bars.", pages = { "BG Score" } },
	{ id = "flagCap", name = "Flag Cap Indicator", category = "PvP", files = { "FlagCap" },
		enabled = { "flagCap" }, requires = { "bgScore" },
		desc = "Who carries each flag and how far they are from capping it." },
	{ id = "bgTimers", name = "BG Timers", category = "PvP", files = { "BGTimers" }, enabled = { "bgTimers" },
		desc = "Base capture timers, the predicted winner and the next resurrection.", pages = { "BG Timers" } },
	{ id = "blitzMap", name = "Blitz Map", category = "PvP", files = { "BlitzMap" }, enabled = { "blitzMap" },
		available = notForever,
		desc = "A zoomable Blitz map with your team, flags, carts and bases.", pages = { "Blitz Map" } },
	{ id = "matchHistory", name = "Match History", category = "PvP", files = { "MatchRecorder" },
		enabled = { "matchHistory" }, desc = "Saves every PvP match for the /mh window.", pages = { "History & Import" } },
	{ id = "queueInfo", name = "Queue Time & MMR", category = "PvP", files = { "QueueInfo" },
		enabled = { "queueInfo" }, desc = "Queue times and your MMR while you wait, and the queue pop volume.",
		pages = { "Queue Time & MMR" } },

	{ id = "nameplates", name = "Nameplates", category = "Interface", files = { "Nameplates" }, enabled = { "nameplates" },
		desc = "Flat nameplates with your debuffs, crowd control, castbars, roles and carrier icons.",
		pages = { "Nameplates" } },
	{ id = "actionBars", name = "Action Bars", category = "Interface", files = { "ActionBars" },
		enabled = { "actionBars" }, conflicts = function() return ns.ActionBars.CONFLICTS end,
		desc = "Restyles Blizzard's action bars, with mouseover fading and text options.", pages = { "Action Bars" } },
	{ id = "cooldowns", name = "Cooldowns", category = "Interface", files = { "Cooldowns" },
		desc = "Centers Blizzard's Cooldown Manager and adds your own cooldown bars.", pages = { "Cooldowns" } },
	{ id = "chat", name = "Chat", category = "Interface", files = { "Chat" }, enabled = { "chat" },
		conflicts = function() return ns.Chat.CONFLICTS end,
		desc = "Flat chat with a copy window, timestamps, whisper handling and tab flashing.", pages = { "Chat" } },
	{ id = "minimap", name = "Minimap", category = "Interface", files = { "Minimap" }, enabled = { "minimap" },
		desc = "Square or round flat minimap, button hiding and auto-hide in matches.", pages = { "Minimap" } },
	{ id = "buffs", name = "Buff Frame", category = "Interface", files = { "Buffs" }, enabled = { "buffs" },
		desc = "Your buff and debuff icons with a flat look, and when to hide them.", pages = { "Buff Frame" } },
	{ id = "tooltip", name = "Tooltip", category = "Interface", files = { "Tooltip" }, enabled = { "tooltip" },
		desc = "Tooltip placement, target line, health bar, class colors and IDs.", pages = { "Tooltip" } },
	{ id = "objectives", name = "Objectives", category = "Interface", files = { "Objectives" },
		enabled = { "objectives" },
		desc = "Objective tracker restyle, quests grouped by zone, and hiding it in matches.", pages = { "Objectives" } },
	{ id = "characterSheet", name = "Character Sheet", category = "Interface", files = { "CharacterSheet" },
		enabled = { "character" },
		desc = "A roomier character sheet with item levels, enchants and backgrounds.", pages = { "Character Sheet" } },
	{ id = "skins", name = "Window Skins", category = "Interface", files = { "Skins" }, enabled = { "skins" },
		desc = "Blizzard's other windows in the same flat look.", pages = { "Window Skins" } },
	{ id = "damageMeter", name = "Damage Meter Skin", category = "Interface", files = { "DamageMeterSkin" },
		enabled = { "damageMeter" }, desc = "Flat bars and your font on Blizzard's damage meter.", pages = { "Damage Meter" } },
	{ id = "gameFonts", name = "Game Fonts", category = "Interface", files = { "GlobalFont" },
		desc = "Your font on Blizzard's UI, on names above characters and on damage numbers." },
	{ id = "classPower", name = "Class Resource", category = "Interface", files = { "ClassPower" },
		enabled = { "classPower" }, requires = { "unitFrames" },
		desc = "Soul shards, combo points, holy power and other class resources as one flat bar.", pages = { "Class Resource" } },
	{ id = "combat", name = "Combat Indicator", category = "Interface", files = { "Combat" }, enabled = { "combat" },
		requires = { "unitFrames" },
		desc = "An icon on your frame in combat, and an Entering / Leaving Combat message.", pages = { "Combat Indicator" } },
	{ id = "swingTimers", name = "Swing Timers", category = "Interface", files = { "SwingTimers" },
		enabled = { "swingTimers" }, desc = "A flat look for Blizzard's melee and ranged swing timers." },

	{ id = "cursor", name = "Cursor", category = "Quality of Life", files = { "Cursor" },
		desc = "Cursor size and a colored ring that follows the cursor.", pages = { "Cursor" } },
	{ id = "misc", name = "Misc", category = "Quality of Life", files = { "Misc" },
		desc = "GCD history, decor purchase confirm, and quest, repair, junk and release errands.",
		pages = { "GCD History & Decor" } },
	{ id = "windowMover", name = "Window Mover", category = "Quality of Life", files = { "WindowMover" },
		enabled = { "windowMover" }, conflicts = function() return ns.WindowMover.CONFLICTS end,
		desc = "Drag Blizzard's windows anywhere and Ctrl + wheel to resize them.", pages = { "Window Mover" } },
	{ id = "combatLog", name = "Combat Logging", category = "Quality of Life", files = { "CombatLog" },
		enabled = { "combatLog" }, desc = "Turns /combatlog on in the matches and instances you pick.",
		pages = { "Combat Logging" } },
	{ id = "questArrow", name = "Quest Marker", category = "Quality of Life", files = { "QuestArrow" },
		desc = "A marker on your tracked quest or corpse, with an arrow when it's off screen." },
	{ id = "damageText", name = "Damage Numbers", category = "Quality of Life", files = { "DamageText" },
		desc = "Size, height and spread of the damage and healing numbers over targets.", pages = { "Damage Numbers" } },
}

M.byId, M.byFile, M.byPage = {}, {}, {}
for _, m in ipairs(M.LIST) do
	M.byId[m.id] = m
	for _, f in ipairs(m.files) do M.byFile[f] = m end
	for _, p in ipairs(m.pages or {}) do M.byPage[p] = m end
end

-- every module starts on
ns.defaults.modules = {}
for _, m in ipairs(M.LIST) do ns.defaults.modules[m.id] = true end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
function M.Available(id)
	local m = M.byId[id]
	return m ~= nil and (not m.available or m.available() and true or false)
end

-- the player's choice in this profile
function M.Chosen(id)
	local mods = ns.db and ns.db.modules
	return not (mods and mods[id] == false)
end

-- the first loaded addon that keeps this module off, or nil
function M.Conflict(id)
	local m = M.byId[id]
	if not (m and m.conflicts) then return nil end
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if not loaded then return nil end
	local ok, list = pcall(m.conflicts)
	for _, name in ipairs(ok and list or {}) do
		if loaded(name) then return name end
	end
	return nil
end

-- does this module's code load this session? Chosen, available here, and its requirements load
function M.Loads(id, seen)
	if not M.Available(id) or not M.Chosen(id) then return false end
	seen = seen or {}
	if seen[id] then return true end
	seen[id] = true
	for _, req in ipairs(M.byId[id].requires or {}) do
		if not M.Loads(req, seen) then return false end
	end
	return true
end

-- what loaded when this session started (choices made since need a /reload)
M.loaded = {}
function M.Loaded(id) return M.loaded[id] == true end
function M.FileLoaded(name)
	local m = M.byFile[name]
	return not m or M.Loaded(m.id)
end
function M.Snapshot()
	for _, m in ipairs(M.LIST) do M.loaded[m.id] = M.Loads(m.id) end
end

-- modules that need this one
function M.Dependents(id)
	local out = {}
	for _, m in ipairs(M.LIST) do
		for _, req in ipairs(m.requires or {}) do
			if req == id then out[#out + 1] = m end
		end
	end
	return out
end

-- Is the feature on, as the picker shows it: the module chosen, and its own Enabled box ticked
-- (any of them, for a module with several).
function M.FeatureOn(id)
	local m = M.byId[id]
	if not M.Chosen(id) then return false end
	if not m.enabled then return true end
	for _, key in ipairs(m.enabled) do
		local t = ns.db[key]
		if type(t) == "table" and t.enabled ~= false then return true end
	end
	return false
end

-- Saves picker choices: { [id] = true/false }. A module turned on from off also gets its own
-- Enabled box ticked, so it shows after the reload; one left as it was isn't touched.
function M.Apply(choices)
	ns.db.modules = ns.db.modules or {}
	for id, on in pairs(choices) do
		local m = M.byId[id]
		if m then
			local was = M.FeatureOn(id)
			ns.db.modules[id] = on and true or false
			if on and not was then
				for _, key in ipairs(m.enabled or {}) do
					if type(ns.db[key]) == "table" then ns.db[key].enabled = true end
				end
			end
		end
	end
end

-- "Stinkie's Full UI": every module that can load here
function M.FullChoices()
	local out = {}
	for _, m in ipairs(M.LIST) do
		if M.Available(m.id) and not M.Conflict(m.id) then out[m.id] = true end
	end
	return out
end

---------------------------------------------------------------------------
-- Game settings a module forces, and putting them back once it's off
---------------------------------------------------------------------------
-- StinkieUIDB.cvarRestore[character][key] = { m = module id, name, bit, v = value before, def = true }
-- Recorded the first time a module changes a setting. On the first load with that module off,
-- each one goes back and the record is dropped, so it happens once. Settings that only mirror a
-- choice the player makes in Blizzard's own options aren't recorded (see the 0.43.0 notes).
local function Store()
	if not StinkieUIDB then return nil end
	StinkieUIDB.cvarRestore = StinkieUIDB.cvarRestore or {}
	local key = ns.CharKey and ns.CharKey() or "?"
	StinkieUIDB.cvarRestore[key] = StinkieUIDB.cvarRestore[key] or {}
	return StinkieUIDB.cvarRestore[key]
end

local function Get(name, bit)
	if bit then
		if not GetCVarBitfield then return nil end
		local ok, v = pcall(GetCVarBitfield, name, bit)
		if ok and v ~= nil then return v and true or false end
		return nil
	end
	local ok, v = pcall(C_CVar.GetCVar, name)
	if ok then return v end
	return nil
end

-- Call before a module writes a setting it forces. bit: index for a bitfield setting.
function M.Remember(id, name, bit)
	local store = Store()
	if not store then return end
	local key = bit and (name .. "#" .. bit) or name
	if store[key] then return end
	-- before 0.43.0 nothing was recorded, so on an older install the setting may already be ours:
	-- Blizzard's default is the only safe value to go back to
	if StinkieUIDB.cvarLegacy then
		store[key] = { m = id, name = name, bit = bit, def = true }
		return
	end
	local v = Get(name, bit)
	if v == nil then return end -- this game version doesn't have it
	store[key] = { m = id, name = name, bit = bit, v = v }
end

local function Put(rec)
	if rec.bit then
		if not SetCVarBitfield then return end
		local v = rec.v
		if rec.def then
			local ok, def = pcall(C_CVar.GetCVarDefault, rec.name)
			if not (ok and def) then return end
			pcall(C_CVar.SetCVar, rec.name, def)
			return
		end
		pcall(SetCVarBitfield, rec.name, rec.bit, v and true or false)
		return
	end
	local v = rec.v
	if rec.def then
		local ok, def = pcall(C_CVar.GetCVarDefault, rec.name)
		if not (ok and def) then return end
		v = def
	end
	pcall(C_CVar.SetCVar, rec.name, tostring(v))
end

-- First load with a module off: its forced settings go back, then any extra undo it has.
M.UNDO = {
	-- Blizzard's chat timestamps, which Chat turns off to draw its own
	chat = function()
		local c = ns.db.chat
		if c and c.blizzardTimestamps and GetCVar("showTimestamps") == "none" then
			SetCVar("showTimestamps", c.blizzardTimestamps)
			c.blizzardTimestamps = nil
		end
	end,
	-- the master volume, if a /reload or logout came while the queue pop sound played
	queueInfo = function() if ns.QueueInfo then ns.QueueInfo.RestoreVolume() end end,
}

function M.RestoreDisabled()
	local store = Store()
	local restored = {}
	if store then
		for key, rec in pairs(store) do
			if rec.m and not M.Loaded(rec.m) then
				ns:RunOOC(function() Put(rec) end)
				store[key] = nil
				restored[#restored + 1] = key
			end
		end
	end
	for id, undo in pairs(M.UNDO) do
		if M.byId[id] and not M.Loaded(id) then
			local ok, err = pcall(undo)
			if not ok then ns.Error(err) end
		end
	end
	return restored
end

---------------------------------------------------------------------------
-- The picker: on a fresh install it opens once the world is up, outside combat and matches.
---------------------------------------------------------------------------
function M.CanOpen()
	if InCombatLockdown() then return false, "after combat" end
	local _, kind = IsInInstance()
	if kind == "arena" or kind == "pvp" then return false, "after the match" end
	return true
end

local waiting
local function TryOpen()
	if not waiting then return end
	if not M.CanOpen() then return end
	waiting = nil
	if ns.Options and ns.Options.ShowModules then ns.Options.ShowModules(M.waitingView or "picker") end
end

-- open the panel now if allowed, otherwise as soon as it is
function M.Open(view, quiet)
	local ok, why = M.CanOpen()
	M.waitingView = view
	if ok and M.worldUp then
		waiting = true
		TryOpen()
		return true
	end
	waiting = true
	if not quiet and why then ns:Print("Modules will open " .. why .. ".") end
	return false
end

function M.OnLogin()
	M.Snapshot()
	local ok, err = pcall(M.RestoreDisabled)
	if not ok then ns.Error(err) end
	if not StinkieUIDB then return end
	if ns.freshInstall and not StinkieUIDB.modulesSeen then
		StinkieUIDB.modulesSeen = true
		M.Open("picker", true)
	elseif not StinkieUIDB.modulesSeen then
		StinkieUIDB.modulesSeen = true
		ns:Print("New: choose which Stinkie UI modules load — /stinkie modules")
	end
end

ns:On("PLAYER_ENTERING_WORLD", function() M.worldUp = true; TryOpen() end)
ns:On("PLAYER_REGEN_ENABLED", TryOpen)
ns:On("ZONE_CHANGED_NEW_AREA", TryOpen)
