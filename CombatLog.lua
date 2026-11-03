-- StinkieUI: automatic combat logging in PvP instances, Mythic+, dungeons and raids.
-- Starts /combatlog when you enter a selected PvP match type, stops it when you leave,
-- and turns it back on after a /reload inside a match. Logging you started yourself is left alone.
local _, ns = ...

local CL = {}
ns.CombatLog = CL

CL.labels = {
	arena = "Arena", shuffle = "Solo Shuffle", blitz = "Blitz", battleground = "Battleground",
	mplus = "Mythic+", dungeon = "Dungeon", raid = "Raid",
}
local MYTHIC_KEYSTONE = 8 -- DifficultyUtil.ID.DungeonChallenge

local function call(fn)
	return fn and fn() or false
end

-- Returns "arena" | "shuffle" | "blitz" | "battleground" | "mplus" | "dungeon" | "raid" | nil
function CL.MatchType()
	local inInstance, instanceType = IsInInstance()
	if not inInstance then return nil end
	local pvp = C_PvP or {}
	if instanceType == "arena" then
		if call(pvp.IsSoloShuffle) or call(pvp.IsRatedSoloShuffle) or call(pvp.IsBrawlSoloShuffle) then
			return "shuffle"
		end
		return "arena"
	elseif instanceType == "pvp" then
		if call(pvp.IsSoloRBG) or call(pvp.IsRatedSoloRBG) or call(pvp.IsBrawlSoloRBG) then
			return "blitz"
		end
		return "battleground"
	elseif instanceType == "party" then
		local difficultyID = select(3, GetInstanceInfo())
		local keystone = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
		if keystone or difficultyID == MYTHIC_KEYSTONE then return "mplus" end
		return "dungeon"
	elseif instanceType == "raid" then
		return "raid"
	end
end

local function Say(msg)
	if not ns.db.combatLog.quiet then ns:Print(msg) end
end

-- What we've done this visit: nil, or the match type we turned logging on for. Each instance
-- visit fires several events (loading, zone, match state, a delayed re-check), and the client can
-- report logging as off for a moment after it was turned on; without this, every one of them
-- turned it on again and each printed a message.
local ours
local seen -- logging was already on when we arrived (yours, or kept across a /reload)

function CL:Evaluate()
	local cfg = ns.db.combatLog
	local match = CL.MatchType()
	local want = cfg.enabled and match and cfg[match]
	local logging = LoggingCombat()
	if ns.issecret(logging) then logging = nil end

	if want then
		if cfg.advanced and GetCVar("advancedCombatLogging") ~= "1" then
			ns:RunOOC(function() SetCVar("advancedCombatLogging", "1") end)
		end
		if ours or seen then return end
		if logging then
			seen = true -- already on: started by you, or by us before a /reload (startedByUs stays as saved)
			return
		end
		LoggingCombat(true)
		ours = match
		cfg.startedByUs = true
		Say("Combat logging on (" .. CL.labels[match] .. ").")
	else
		seen = nil
		if (ours or cfg.startedByUs) and not cfg.singleFile then
			if logging ~= false then
				LoggingCombat(false)
				Say("Combat logging off.")
			end
			cfg.startedByUs = false
		end
		ours = nil
	end
end

-- several events arrive together on every loading screen: evaluate once, shortly after
local scheduled = false
local function Schedule(delay)
	if scheduled then return end
	scheduled = true
	C_Timer.After(delay or 0.2, function()
		scheduled = false
		CL:Evaluate()
	end)
end

function CL:Init()
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PVP_MATCH_ACTIVE", "PVP_MATCH_STATE_CHANGED",
		"CHALLENGE_MODE_START", "PLAYER_DIFFICULTY_CHANGED" }) do
		f:RegisterEvent(e)
	end
	f:SetScript("OnEvent", function(_, event)
		Schedule()
		-- match type (Shuffle / Blitz) can resolve a moment after loading in
		if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
			C_Timer.After(3, function() CL:Evaluate() end)
		end
	end)
end

function CL:Refresh()
	CL:Evaluate()
end

ns:RegisterModule("CombatLog", CL)
