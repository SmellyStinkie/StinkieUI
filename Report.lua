-- StinkieUI: /stinkie report, one block to paste for support, and a record of recent errors.
local _, ns = ...

local R = {}
ns.Report = R

R.SESSION_MAX, R.SAVED_MAX, R.MSG_MAX = 20, 10, 400

---------------------------------------------------------------------------
-- Errors: everything Stinkie UI catches goes through ns.Error, which notes it and then hands it
-- to the game's error handler as before (BugSack and the like still see it). The game's handler
-- itself is left alone.
---------------------------------------------------------------------------
R.session = {}

local function Clean(msg)
	msg = tostring(msg or "?")
	msg = msg:gsub("Interface[/\\]AddOns[/\\]", "")
	if #msg > R.MSG_MAX then msg = msg:sub(1, R.MSG_MAX) .. "..." end
	return msg
end

function R.Record(msg)
	msg = Clean(msg)
	local now = GetTime and GetTime() or 0
	for _, e in ipairs(R.session) do
		if e.msg == msg then
			e.count, e.t = e.count + 1, now
			return
		end
	end
	table.insert(R.session, 1, { msg = msg, count = 1, t = now })
	if #R.session > R.SESSION_MAX then table.remove(R.session) end
	-- the last few survive a reload, so a report after a /reload still has them
	if type(StinkieUIDB) == "table" then
		local saved = StinkieUIDB.errors
		if type(saved) ~= "table" then saved = {}; StinkieUIDB.errors = saved end
		for i, e in ipairs(saved) do
			if e.m == msg then table.remove(saved, i) break end
		end
		table.insert(saved, 1, { m = msg, v = ns.version, at = time and time() or 0 })
		while #saved > R.SAVED_MAX do table.remove(saved) end
	end
end

function ns.Error(err)
	pcall(R.Record, err)
	geterrorhandler()(err)
end

-- the game blocking something Stinkie UI tried (taint)
local function Blocked(event, addon, func)
	if addon == ns.name then R.Record((event == "ADDON_ACTION_FORBIDDEN" and "Forbidden: " or "Blocked: ") .. tostring(func)) end
end
ns:On("ADDON_ACTION_BLOCKED", Blocked)
ns:On("ADDON_ACTION_FORBIDDEN", Blocked)

-- Stinkie UI errors BugSack (BugGrabber) caught, newest first
function R.BugGrabberErrors()
	local out = {}
	local BG = _G.BugGrabber
	if type(BG) ~= "table" or type(BG.GetDB) ~= "function" then return out end
	local ok, db = pcall(BG.GetDB, BG)
	if not ok or type(db) ~= "table" then return out end
	for i = #db, 1, -1 do
		local e = db[i]
		local msg = type(e) == "table" and e.message
		if type(msg) == "string" and msg:find("StinkieUI", 1, true) then
			out[#out + 1] = { msg = Clean(msg), count = tonumber(e.counter) or 1 }
			if #out >= 10 then break end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------
local function AddOnAPI(name) return (C_AddOns and C_AddOns[name]) or _G[name] end

-- other addons loaded right now (names only)
function R.OtherAddOns()
	local out = {}
	local num, info, loaded = AddOnAPI("GetNumAddOns"), AddOnAPI("GetAddOnInfo"), AddOnAPI("IsAddOnLoaded")
	if not (num and info and loaded) then return out end
	local ok, n = pcall(num)
	if not ok or type(n) ~= "number" then return out end
	for i = 1, n do
		local okInfo, name = pcall(info, i)
		if okInfo and type(name) == "string" and not name:find("^StinkieUI") then
			local okLoaded, isLoaded = pcall(loaded, name)
			if okLoaded and isLoaded then out[#out + 1] = name end
		end
	end
	table.sort(out)
	return out
end

-- a profile named after a character is shown without the name
local function ProfileLabel()
	local name = ns:CurrentProfileName()
	local chars = StinkieUIDB and StinkieUIDB.chars or {}
	local named = name:find(" - ", 1, true) ~= nil or chars[name] ~= nil
	local how = (select(2, ns.WantedProfile(ns.CurrentSpec()))) and "spec profile" or "character profile"
	return (named and "(a character's own)" or name) .. ", " .. how
end

local function Where()
	local inside, kind = IsInInstance()
	if not inside then return "open world" end
	return tostring(kind)
end

function R.Build()
	local M = ns.Modules
	local lines = {}
	local function add(s) lines[#lines + 1] = s end

	add("Stinkie UI " .. tostring(ns.version) .. " report")
	local version, build, _, toc = GetBuildInfo()
	add(string.format("Client: %s %s (build %s), interface %s", ns.IS_FOREVER and "WoW Forever" or "Midnight",
		tostring(version), tostring(build), tostring(toc)))
	local w, h = 0, 0
	if GetPhysicalScreenSize then w, h = GetPhysicalScreenSize() end
	add(string.format("Locale %s, UI scale %.2f, Stinkie scale %.2f, screen %sx%s", tostring(GetLocale and GetLocale() or "?"),
		UIParent and UIParent:GetScale() or 1, ns.db and ns.db.scale or 1, tostring(w), tostring(h)))
	local _, class = UnitClass("player")
	local specName = "none"
	local spec = ns.CurrentSpec()
	for _, s in ipairs(ns.SpecList()) do if s[1] == spec then specName = s[2] end end
	add("Class " .. tostring(class) .. ", spec " .. specName .. ", in " .. Where() .. ", " .. (InCombatLockdown() and "in combat" or "out of combat"))
	add("Profile: " .. ProfileLabel() .. (ns.SpecProfilesOn() and ", per-spec profiles on" or ""))

	local on, off, unavailable, blocked, pending = {}, {}, {}, {}, {}
	for _, m in ipairs(M.LIST) do
		local conflict = M.Conflict(m.id)
		if not M.Available(m.id) then
			unavailable[#unavailable + 1] = m.id
		elseif conflict then
			blocked[#blocked + 1] = m.id .. " (" .. conflict .. ")"
		elseif M.Loaded(m.id) then
			on[#on + 1] = m.id .. (M.FeatureOn(m.id) and "" or " [its Enabled box is off]")
		else
			off[#off + 1] = m.id
		end
		if M.Available(m.id) and not conflict and M.Loads(m.id) ~= M.Loaded(m.id) then pending[#pending + 1] = m.id end
	end
	add(string.format("Modules on (%d): %s", #on, #on > 0 and table.concat(on, ", ") or "none"))
	add("Modules off: " .. (#off > 0 and table.concat(off, ", ") or "none"))
	if #pending > 0 then add("Changed, waiting for a /reload: " .. table.concat(pending, ", ")) end
	if #unavailable > 0 then add("Not on this game version: " .. table.concat(unavailable, ", ")) end
	add("Off because another addon is loaded: " .. (#blocked > 0 and table.concat(blocked, ", ") or "none"))

	local others = R.OtherAddOns()
	add(string.format("Other addons loaded (%d): %s", #others, #others > 0 and table.concat(others, ", ") or "none"))

	add("")
	add("Recent Stinkie UI errors this session:")
	if #R.session == 0 then add("  none") end
	for _, e in ipairs(R.session) do add(string.format("  [x%d] %s", e.count, e.msg)) end
	local saved = StinkieUIDB and StinkieUIDB.errors or {}
	local older = {}
	for _, e in ipairs(saved) do
		local seen = false
		for _, s in ipairs(R.session) do if s.msg == e.m then seen = true end end
		if not seen then older[#older + 1] = e end
	end
	if #older > 0 then
		add("Earlier sessions:")
		for _, e in ipairs(older) do add(string.format("  (%s) %s", tostring(e.v), e.m)) end
	end
	local bug = R.BugGrabberErrors()
	if #bug > 0 then
		add("From BugSack:")
		for _, e in ipairs(bug) do add(string.format("  [x%d] %s", e.count, e.msg)) end
	end
	return table.concat(lines, "\n")
end

function R.Show()
	local text = R.Build()
	local W = ns.Options and ns.Options.W
	if W and W.ShowTextPopup then
		W.ShowTextPopup("Stinkie UI report", text)
	else
		print(text)
	end
end
