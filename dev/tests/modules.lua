-- Module system scenarios. run.py runs this once per scenario, each in a fresh mock client:
-- SCENARIO names the case, ARG is a module id for "one-off".
local ns = TEST_NS
local M = ns.Modules
local function print(...) local p = {} for i = 1, select("#", ...) do p[#p + 1] = tostring((select(i, ...))) end io.write(table.concat(p, " ") .. "\n") end
local passed, failed = 0, 0
-- unset globals are stubs in the mock, so read these raw
local ARG = rawget(_G, "ARG")
local label = SCENARIO .. (ARG and (" " .. ARG) or "")
local function check(name, cond, extra)
	if cond then passed = passed + 1 else
		failed = failed + 1
		print("FAIL [" .. label .. "] " .. name .. (extra ~= nil and (": " .. tostring(extra)) or ""))
	end
end
local function flushErrors(stage)
	if #MOCK.errors > 0 then
		for _, e in ipairs(MOCK.errors) do io.write("ERROR [" .. label .. " / " .. stage .. "] " .. e .. "\n") end
		failed = failed + #MOCK.errors
		MOCK.errors = {}
	end
end
local function printed(text)
	local n = 0
	for _, p in ipairs(MOCK.prints) do if p:find(text, 1, true) then n = n + 1 end end
	return n
end

-- saved variables from an older version: a profile at DB version 16, with no module choices
local function oldStore(profile)
	profile = profile or {}
	profile.version = 16
	return { profiles = { [ns.DEFAULT_PROFILE] = profile }, chars = {} }
end
-- saved variables from 0.43.0 on, with module choices
local function store(modules, extra)
	local s = { profiles = { [ns.DEFAULT_PROFILE] = { version = ns.DB_VERSION, modules = modules } }, chars = {}, modulesSeen = true }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end
local function allChoices(on)
	local t = {}
	for _, m in ipairs(M.LIST) do t[m.id] = on end
	return t
end

-- record which modules' Init runs
local inits = {}
local function watchInits()
	for _, mod in ipairs(ns.modules) do
		local init, name = mod.Init, mod.SUIName
		if init then mod.Init = function(...) inits[name] = true; return init(...) end end
	end
end

local function bootUp()
	watchInits()
	MOCK.Fire("ADDON_LOADED", "StinkieUI")
	MOCK.Fire("PLAYER_LOGIN")
	MOCK.Fire("PLAYER_ENTERING_WORLD", true, false)
	MOCK.Advance(1)
	flushErrors("boot")
end

-- what an evening of play throws at the addon
local function play()
	MOCK.Fire("PLAYER_TARGET_CHANGED"); MOCK.Fire("UNIT_AURA", "player"); MOCK.Fire("GROUP_ROSTER_UPDATE")
	MOCK.Fire("PLAYER_REGEN_DISABLED"); MOCK.Advance(0.5); MOCK.Fire("PLAYER_REGEN_ENABLED")
	MOCK.instanceType, MOCK.instanceName, MOCK.instanceID, MOCK.mapID = "arena", "Nagrand Arena", 1505, 1505
	MOCK.Fire("PLAYER_ENTERING_WORLD", false, false); MOCK.Fire("ZONE_CHANGED_NEW_AREA")
	MOCK.Fire("ARENA_OPPONENT_UPDATE", "arena1", "seen"); MOCK.Advance(1)
	MOCK.instanceType, MOCK.instanceName, MOCK.instanceID, MOCK.mapID = "pvp", "Warsong Gulch", 2106, 1339
	MOCK.Fire("PLAYER_ENTERING_WORLD", false, false); MOCK.Fire("ZONE_CHANGED_NEW_AREA")
	MOCK.Fire("UPDATE_BATTLEFIELD_SCORE"); MOCK.Fire("PVP_MATCH_STATE_CHANGED"); MOCK.Advance(1)
	MOCK.Fire("PVP_MATCH_COMPLETE"); MOCK.Advance(1)
	MOCK.instanceType, MOCK.instanceName, MOCK.instanceID, MOCK.mapID = "none", "Dornogal", 2552, 2339
	MOCK.Fire("PLAYER_ENTERING_WORLD", false, false); MOCK.Fire("ZONE_CHANGED_NEW_AREA"); MOCK.Advance(1)
	ns:Refresh(); MOCK.Advance(0.2)
	flushErrors("play")
	for _, cmd in ipairs({ "quest", "map", "tooltip", "dmg", "plates", "auras", "flags", "timers", "score", "fontcheck", "unlock", "lock" }) do
		SlashCmdList.STINKIEUI(cmd)
		flushErrors("/stinkie " .. cmd)
	end
end

-- every options page, built the way the search box builds them
local function buildPages()
	if not ns.Options.window then ns:ToggleOptions() end
	flushErrors("options open")
	local O = ns.Options
	O.searchIndex = nil
	O.search:SetText("aura")
	O.search:GetScript("OnTextChanged")(O.search, true)
	flushErrors("options pages")
	return O.searchIndex or {}
end
local function indexHas(idx, text)
	for _, e in ipairs(idx) do if e.text == text then return true end end
	return false
end
-- pages built with the "this module is off" banner (the mock can't list a page's text)
local function banners()
	local n = 0
	for _, o in ipairs(MOCK.frames) do if o.moduleBanner then n = n + 1 end end
	return n
end

local function click(b) b:GetScript("OnClick")(b, "LeftButton") end
local function row(id)
	for _, r in ipairs(ns.Options.modules.rows) do if r.id == id then return r end end
end

---------------------------------------------------------------------------
if SCENARIO == "fresh" then
	StinkieUIDB = nil
	bootUp()
	local f = ns.Options.modules
	check("picker opens on a fresh install", f and f:IsShown() and f.view == "picker")
	check("no upgrade line on a fresh install", printed("New: choose which") == 0)
	check("seen is saved", StinkieUIDB.modulesSeen == true)
	check("no legacy mark on a fresh install", not StinkieUIDB.cvarLegacy)
	for _, m in ipairs(M.LIST) do
		if M.Available(m.id) then check("loads by default: " .. m.id, M.Loaded(m.id)) end
	end
	-- "Choose modules" steps to the list and keeps the panel's choices
	click(f.pickButton)
	check("choose modules shows the list", f.list:IsShown() and not f.intro:IsShown() and f.view == "list")
	-- unticking Party drops Party Targets, and says so
	click(row("party").box)
	check("party unticked", f.choices.party == false)
	check("party targets follows it", f.choices.partyTargets == false)
	check("the panel says why", (f.warn:GetText() or ""):find("Party Targets", 1, true) ~= nil, f.warn:GetText())
	-- ticking Party Targets ticks Party back on
	click(row("partyTargets").box)
	check("party targets ticks party", f.choices.partyTargets == true and f.choices.party == true)
	click(row("classPower").box)
	click(f.applyButton)
	check("apply saves an off module", ns.db.modules.classPower == false)
	check("apply keeps the others", ns.db.modules.party == true and ns.db.modules.nameplates == true)
	check("still loaded until the reload", M.Loaded("classPower"))
	-- the page now says it turns off... it's still loaded, so no banner yet
	-- Full UI turns everything back on
	ns.Options.ShowModules("picker")
	click(f.fullButton)
	check("full UI turns everything on", ns.db.modules.classPower == true)
	-- the header button opens the list
	ns:ToggleOptions()
	click(ns.Options.modulesButton)
	check("header button opens the list", f:IsShown() and f.view == "list")
	-- /stinkie setup and modules
	f:Hide()
	SlashCmdList.STINKIEUI("setup")
	check("/stinkie setup opens the picker", f:IsShown() and f.view == "picker")
	SlashCmdList.STINKIEUI("modules")
	check("/stinkie modules opens the list", f:IsShown() and f.view == "list")
	flushErrors("panel")

elseif SCENARIO == "fresh-in-match" then
	StinkieUIDB = nil
	MOCK.instanceType, MOCK.instanceName, MOCK.instanceID, MOCK.mapID = "arena", "Nagrand Arena", 1505, 1505
	bootUp()
	check("not in an arena", not (ns.Options.modules and ns.Options.modules:IsShown()))
	MOCK.instanceType, MOCK.instanceName = "none", "Dornogal"
	MOCK.Fire("ZONE_CHANGED_NEW_AREA")
	check("opens once out of the match", ns.Options.modules and ns.Options.modules:IsShown() and ns.Options.modules.view == "picker")
	-- combat: deferred, then opens when it ends
	ns.Options.modules:Hide()
	local old = InCombatLockdown
	InCombatLockdown = function() return true end
	M.Open("list")
	check("not in combat", not ns.Options.modules:IsShown())
	check("says when", printed("Modules will open after combat") == 1)
	InCombatLockdown = old
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check("opens after combat", ns.Options.modules:IsShown() and ns.Options.modules.view == "list")
	flushErrors("deferred")

elseif SCENARIO == "upgrade" then
	StinkieUIDB = oldStore({ chat = { enabled = true } })
	MOCK.Fire("ADDON_LOADED", "StinkieUI")
	-- before any module starts: the migrated profile is the defaults, plus all modules on
	local same = true
	for k, v in pairs(ns.defaults) do
		if k ~= "version" and k ~= "modules" and type(v) ~= "table" and ns.db[k] ~= v then same = false end
	end
	check("settings untouched by the upgrade", same)
	check("version bumped", ns.db.version == ns.DB_VERSION)
	check("legacy mark set", StinkieUIDB.cvarLegacy == true)
	watchInits()
	MOCK.Fire("PLAYER_LOGIN")
	MOCK.Fire("PLAYER_ENTERING_WORLD", true, false)
	MOCK.Advance(1)
	flushErrors("boot")
	check("no picker on an upgrade", not (ns.Options.modules and ns.Options.modules:IsShown()))
	check("one chat line", printed("New: choose which Stinkie UI modules load — /stinkie modules") == 1)
	for _, m in ipairs(M.LIST) do
		if M.Available(m.id) then
			check("everything still loads: " .. m.id, M.Loaded(m.id) and ns.db.modules[m.id] == true)
		end
	end
	for _, mod in ipairs(ns.modules) do
		if mod.Init then check("init ran: " .. mod.SUIName, inits[mod.SUIName]) end
	end
	-- the next login says nothing
	M.OnLogin()
	check("only once", printed("New: choose which") == 1)
	-- an export carries the module choices, an import restores them
	-- the mock has no encoding API: pass the table through by number
	local stash, same = {}, function(x) return x end
	C_EncodingUtil = { SerializeCBOR = function(t) stash[#stash + 1] = t; return tostring(#stash) end,
		CompressString = same, EncodeBase64 = same, DecodeBase64 = same, DecompressString = same,
		DeserializeCBOR = function(x) return stash[tonumber(x)] end }
	ns.db.modules.cursor = false
	local s = ns:ExportProfile()
	ns.db.modules.cursor = true
	local ok = ns:ImportProfile(s)
	check("import works", ok)
	check("export carries module choices", ns.db.modules and ns.db.modules.cursor == false and ns.db.modules.chat == true)
	flushErrors("export")

elseif SCENARIO == "all-on" or SCENARIO == "all-off" then
	local on = SCENARIO == "all-on"
	StinkieUIDB = store(allChoices(on))
	bootUp()
	check("no picker once seen", not (ns.Options.modules and ns.Options.modules:IsShown()))
	check("no upgrade line once seen", printed("New: choose which") == 0)
	for _, m in ipairs(M.LIST) do
		local want = on and M.Available(m.id)
		check("loaded: " .. m.id, M.Loaded(m.id) == want)
		for _, file in ipairs(m.files) do
			check("init " .. (want and "ran" or "never ran") .. ": " .. file, (inits[file] or false) == want)
		end
	end
	play()
	local idx = buildPages()
	check("every page is still searchable", indexHas(idx, "Nameplates > Enemy") and indexHas(idx, "Interface > Chat") and indexHas(idx, "General") and indexHas(idx, "PvP > Blitz Map") and indexHas(idx, "Quality of Life > Automation") and indexHas(idx, "Quality of Life > Quest Marker"))
	check("off banner " .. (on and "absent" or "shown"), (banners() > 0) == not on, banners())

elseif SCENARIO == "one-off" then
	local choices = allChoices(true)
	choices[ARG] = false
	StinkieUIDB = store(choices)
	bootUp()
	check("off", not M.Loaded(ARG))
	for _, dep in ipairs(M.Dependents(ARG)) do check("dependent off: " .. dep.id, not M.Loaded(dep.id)) end
	for _, file in ipairs(M.byId[ARG].files) do check("init never ran: " .. file, not inits[file]) end
	play()
	local idx = buildPages()
	if M.byId[ARG].pages then
		-- its pages and those of what needs it (Nameplates is a group of six pages)
		local want = 0
		for _, m in ipairs(M.LIST) do
			if not M.Loaded(m.id) and m.pages then want = want + (m.id == "nameplates" and 6 or #m.pages) end
		end
		check("its pages show the banner", banners() == want, banners() .. " of " .. want)
		local page, found = M.byId[ARG].pages[1], false
		for _, e in ipairs(idx) do
			if e.page and (e.text == page or e.text:sub(-#page - 3) == " > " .. page) then found = true end
		end
		check("its page is still searchable", found or ARG == "nameplates")
	end
	-- the panel shows it unticked
	ns.Options.ShowModules("list")
	local r = row(ARG)
	if M.Available(ARG) then check("unticked in the list", r and r.box.checked == false) end
	flushErrors("panel")

elseif SCENARIO == "restore" then
	-- 0.43.0 recorded these as the settings before Stinkie changed them
	local key = ns.CharKey()
	StinkieUIDB = store(allChoices(true), { cvarRestore = { [key] = {
		nameplateOverlapV = { m = "nameplates", name = "nameplateOverlapV", v = "1.1" },
		nameplateSelectedScale = { m = "nameplates", name = "nameplateSelectedScale", def = true },
		whisperMode = { m = "chat", name = "whisperMode", v = "popout" },
	} } })
	StinkieUIDB.profiles[ns.DEFAULT_PROFILE].modules.nameplates = false
	MOCK.cvars = { nameplateOverlapV = "0.6", nameplateSelectedScale = "1.4", whisperMode = "inline" }
	MOCK.cvarDefaults = { nameplateSelectedScale = "1.2" }
	bootUp()
	check("a setting goes back to what it was", MOCK.cvars.nameplateOverlapV == "1.1", MOCK.cvars.nameplateOverlapV)
	check("an older one goes back to Blizzard's default", MOCK.cvars.nameplateSelectedScale == "1.2", MOCK.cvars.nameplateSelectedScale)
	local rec = StinkieUIDB.cvarRestore[key]
	check("its records are dropped", rec.nameplateOverlapV == nil and rec.nameplateSelectedScale == nil)
	check("a loaded module's record stays", rec.whisperMode ~= nil)
	-- only once: a later load leaves the setting alone
	MOCK.cvars.nameplateOverlapV = "0.9"
	M.RestoreDisabled()
	check("only once", MOCK.cvars.nameplateOverlapV == "0.9")
	-- recording: the first value is kept, later ones aren't
	MOCK.cvars.someSetting = "3"
	M.Remember("damageText", "someSetting")
	MOCK.cvars.someSetting = "7"
	M.Remember("damageText", "someSetting")
	check("records the value before", rec.someSetting and rec.someSetting.v == "3")
	-- an older install records Blizzard's default instead
	StinkieUIDB.cvarLegacy = true
	M.Remember("damageText", "otherSetting")
	check("legacy records the default", rec.otherSetting and rec.otherSetting.def == true)
	flushErrors("restore")
	-- Chat off: Blizzard's own timestamps come back
	ns.db.chat.blizzardTimestamps = "%H:%M "
	MOCK.cvars.showTimestamps = "none"
	M.loaded.chat = false
	M.RestoreDisabled()
	check("chat timestamps come back", MOCK.cvars.showTimestamps == "%H:%M ")
	check("whisper mode comes back", MOCK.cvars.whisperMode == "popout")
	M.loaded.chat = true
	flushErrors("chat undo")

elseif SCENARIO == "spec-profiles" then
	-- a Warlock with Affliction, Demonology, Destruction; Destruction has its own profile
	local spec = 3
	C_SpecializationInfo = {
		GetSpecialization = function() return spec end,
		GetNumSpecializations = function() return 3 end,
		GetSpecializationInfo = function(i) return 264 + i, ({ "Affliction", "Demonology", "Destruction" })[i], "", 0 end,
	}
	local shown = {}
	StaticPopup_Show = function(which, a, b) shown[#shown + 1] = { which, a, b } end
	local key = ns.CharKey()
	StinkieUIDB = store(allChoices(true), { specProfiles = { [key] = { enabled = true, [3] = "Destro" } } })
	StinkieUIDB.profiles.Destro = { version = ns.DB_VERSION, scale = 0.8 }
	bootUp()
	check("the spec's profile loads", ns:CurrentProfileName() == "Destro" and ns.db.scale == 0.8, ns:CurrentProfileName())
	check("spec list", #ns.SpecList() == 3 and ns.SpecList()[2][2] == "Demonology")
	MOCK.Advance(2)
	check("no prompt when it already matches", #shown == 0)
	-- swap to Affliction (no profile of its own): offers the character's profile
	spec = 1
	MOCK.Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
	check("prompt on a spec change", #shown == 1 and shown[1][1] == "STINKIEUI_SPEC_PROFILE" and shown[1][2] == "Affliction" and shown[1][3] == ns.DEFAULT_PROFILE,
		shown[1] and (tostring(shown[1][2]) .. " / " .. tostring(shown[1][3])))
	MOCK.Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
	check("asked once", #shown == 1)
	check("another unit's spec change is ignored", (function() MOCK.Fire("PLAYER_SPECIALIZATION_CHANGED", "party1"); return #shown == 1 end)())
	-- in combat: waits
	local old = InCombatLockdown
	InCombatLockdown = function() return true end
	spec = 3
	MOCK.Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
	spec = 2
	ns.SpecStore(true)[2] = "Destro"
	MOCK.Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
	check("no prompt in combat", #shown == 1)
	InCombatLockdown = old
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check("matching profile after combat: nothing to ask", #shown == 1)
	-- the last spec is remembered for a login that doesn't know it yet
	check("last spec saved", StinkieUIDB.lastSpec[key] == 2)
	-- switching profile while the spec has its own changes the spec's choice
	ns:SetProfile("Raid", true)
	check("switching sets the spec's profile", ns.SpecStore()[2] == "Raid" and StinkieUIDB.chars[key] == nil)
	ns.SpecStore()[2] = nil
	ns:SetProfile("Raid")
	check("a spec without its own sets the character's", StinkieUIDB.chars[key] == "Raid")
	-- deleting a profile clears the specs using it
	ns.SpecStore()[1] = "Raid"
	StinkieUIDB.chars[key] = nil
	local okDel = ns:DeleteProfile("Raid")
	check("delete clears the spec", okDel and ns.SpecStore()[1] == nil)
	-- a cold login: no spec yet, the last one picks the profile
	spec = 0
	StinkieUIDB.lastSpec[key] = 3
	check("cold login uses the last spec", ns.WantedProfile(ns.CurrentSpec() or StinkieUIDB.lastSpec[key]) == "Destro")
	-- off: the character's profile again
	ns.SpecStore().enabled = nil
	check("off uses the character's profile", ns.WantedProfile(3) == ns.DEFAULT_PROFILE)
	flushErrors("spec")
	-- the options page builds with the spec rows
	buildPages()

elseif SCENARIO == "report" then
	StinkieUIDB = store(allChoices(true))
	StinkieUIDB.profiles[ns.DEFAULT_PROFILE].modules.cursor = false
	BugGrabber = { GetDB = function() return {
		{ message = "Interface/AddOns/StinkieUI/Chat.lua:10: boom", counter = 4 },
		{ message = "Interface/AddOns/OtherAddon/x.lua:1: not ours", counter = 1 },
	} end }
	bootUp()
	ns.Error("StinkieUI/Party.lua:5: first")
	ns.Error("StinkieUI/Party.lua:5: first")
	check("the game's handler still gets them", #MOCK.errors == 2)
	MOCK.errors = {}
	MOCK.Fire("ADDON_ACTION_BLOCKED", "StinkieUI", "CastSpellByName()")
	MOCK.Fire("ADDON_ACTION_BLOCKED", "OtherAddon", "Foo()")
	local text = ns.Report.Build()
	check("version", text:find("Stinkie UI " .. ns.version .. " report", 1, true) ~= nil)
	check("client", text:find("Client: Midnight 12.1.5 (build 70688), interface 120105", 1, true) ~= nil)
	check("modules on", text:find("Modules on (", 1, true) ~= nil and text:find("nameplates", 1, true) ~= nil)
	check("modules off", text:find("Modules off: cursor", 1, true) ~= nil)
	check("pending reload", (function()
		ns.db.modules.chat = false
		local t = ns.Report.Build()
		ns.db.modules.chat = true
		return t:find("waiting for a /reload: chat", 1, true) ~= nil
	end)())
	check("caught errors, counted", text:find("[x2] StinkieUI/Party.lua:5: first", 1, true) ~= nil)
	check("taint blocks, ours only", text:find("Blocked: CastSpellByName()", 1, true) ~= nil and text:find("Foo()", 1, true) == nil)
	check("BugSack, ours only", text:find("[x4] StinkieUI/Chat.lua:10: boom", 1, true) ~= nil and text:find("not ours", 1, true) == nil)
	check("no character name", text:find("Stinkie - ", 1, true) == nil and text:find("Tichondrius", 1, true) == nil)
	check("errors saved for the next session", StinkieUIDB.errors and StinkieUIDB.errors[1].m == "Blocked: CastSpellByName()")
	-- a profile named after a character stays anonymous
	ns.profileName = ns.CharKey()
	check("own profile anonymous", ns.Report.Build():find("Profile: (a character's own)", 1, true) ~= nil)
	ns.profileName = ns.DEFAULT_PROFILE
	-- the slash command and the module list button open it
	SlashCmdList.STINKIEUI("report")
	ns.Options.ShowModules("list")
	click(ns.Options.modules.reportButton)
	flushErrors("report")

elseif SCENARIO == "no-restart" then
	-- the TOC's new files missing (a /reload after an update): core still works
	check("files missing", ns.Report == nil and ns.BossFrames == nil)
	StinkieUIDB = store(allChoices(true))
	bootUp()
	check("party still starts", ns.Party.holder ~= nil and #ns.Party.frames >= 4)
	-- a layout error in a match: the catch must not fail, and every frame stays placed
	MOCK.instanceType, MOCK.instanceName = "arena", "Nagrand Arena"
	local real = ns.UF.Layout
	ns.UF.Layout = function() error("layout broke") end
	ns.Party:Refresh()
	ns.UF.Layout = real
	check("the error still reaches the game", #MOCK.errors > 0)
	MOCK.errors = {}
	local placed = true
	for _, f in ipairs(ns.Party.frames) do if not f:GetPoint() then placed = false end end
	check("party frames stay placed", placed)
	SlashCmdList.STINKIEUI("report")
	check("report asks for a restart", printed("Restart the game") == 1)
	play()
	buildPages()

elseif SCENARIO == "forever" or SCENARIO == "forever-off" then
	check("Forever client", ns.IS_FOREVER == true and not ns.HAS_ARENA)
	StinkieUIDB = SCENARIO == "forever" and nil or store(allChoices(false))
	bootUp()
	check("arena is unavailable", not M.Available("arena") and not M.Loaded("arena"))
	check("blitz map is unavailable", not M.Available("blitzMap") and not M.Loaded("blitzMap"))
	check("full UI leaves them out", M.FullChoices().arena == nil and M.FullChoices().blitzMap == nil)
	ns.Options.ShowModules("list")
	check("not in the list", row("arena") == nil and row("blitzMap") == nil and row("chat") ~= nil)
	play()
	buildPages()
end

flushErrors("end")
RESULT = { passed = passed, failed = failed }
