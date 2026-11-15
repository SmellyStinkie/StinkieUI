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
-- Error Catcher (a module): stands in for the BugGrabber + BugSack pair. It becomes the game's
-- error handler, so Lua errors from any addon are kept quietly (message, where it happened and
-- the local values) instead of popping up, and /stinkie errors shows them in a window to read
-- and copy. With BugGrabber loaded it stays off: two handlers would fight over the same errors.
-- Kept for the account in StinkieUIDB.bugs = { session = n, list = { oldest ... newest } }.
---------------------------------------------------------------------------
local E = {}
ns.Errors = E
E.CONFLICTS = { "!BugGrabber", "BugGrabber" } -- also shown in the module list
E.MSG_MAX, E.STACK_MAX, E.LOCALS_MAX = 1200, 3000, 2500
E.CHAT_EVERY = 10 -- seconds between chat lines
E.view, E.index = "session", 1

-- its settings are ns.defaults.errors, in Core.lua
local function ecfg() return (ns.db and ns.db.errors) or ns.defaults.errors end

function E.Store()
	if type(StinkieUIDB) ~= "table" then
		E.loose = E.loose or { session = 0, list = {} }
		return E.loose
	end
	local s = StinkieUIDB.bugs
	if type(s) ~= "table" or type(s.list) ~= "table" then
		s = { session = 0, list = {} }
		StinkieUIDB.bugs = s
	end
	s.session = tonumber(s.session) or 0
	return s
end

local function Cut(text, max)
	if type(text) ~= "string" then return nil end
	if #text > max then return text:sub(1, max) .. "\n..." end
	return text
end

---------------------------------------------------------------------------
-- The sound. The game has no volume for one sound, so a quieter one works as the queue pop
-- volume does: the master volume drops for as long as the sound lasts, then goes back. The old
-- volume is kept in StinkieUIDB (the same place the queue pop uses, so the two never save each
-- other's lowered level), and a /reload in those seconds still restores it.
---------------------------------------------------------------------------
E.SOUNDS = ns.SOUNDS -- the list is in Core.lua
E.SOUND_SECS = 2
local MASTER = "Sound_MasterVolume"
local volumeToken = 0

function E.SoundKit(key) return ns.SoundKit(key) end

function E.RestoreVolume()
	local was = StinkieUIDB and StinkieUIDB.popVolumeWas
	if not was then return end
	StinkieUIDB.popVolumeWas = nil
	pcall(C_CVar.SetCVar, MASTER, was)
end

-- lowers the master volume to the chosen share of what it is, for the length of the sound
function E.LowerVolume()
	local pct = tonumber(ecfg().volume) or 100
	if pct >= 100 or type(StinkieUIDB) ~= "table" or StinkieUIDB.popVolumeWas then return false end
	local cur = tonumber(C_CVar.GetCVar(MASTER))
	if not cur then return false end
	StinkieUIDB.popVolumeWas = tostring(cur)
	if not pcall(C_CVar.SetCVar, MASTER, tostring(cur * math.max(pct, 0) / 100)) then E.RestoreVolume() return false end
	volumeToken = volumeToken + 1
	local token = volumeToken
	C_Timer.After(E.SOUND_SECS, function()
		if token == volumeToken then E.RestoreVolume() end
	end)
	return true
end

-- the chosen sound, at the chosen volume (also the options page's "Play it")
function E.PlaySound()
	if not PlaySound then return end
	pcall(E.LowerVolume)
	PlaySound(E.SoundKit(ecfg().soundName), "Master")
end

function E.IsOurs(e)
	return (e.m and e.m:find("StinkieUI", 1, true) ~= nil) or (e.s and e.s:find("StinkieUI", 1, true) ~= nil) or false
end

-- Notes an error. The same message again in this session only counts up.
function E.Catch(msg, stack, locals)
	if ns.issecret and ns.issecret(msg) then msg = "(an error whose message the game hides)" end
	msg = Cut(tostring(msg or "?"), E.MSG_MAX)
	local store = E.Store()
	local list, id = store.list, E.sessionId or store.session
	for i = #list, 1, -1 do
		local e = list[i]
		if e.ses ~= id then break end
		if e.m == msg then
			e.n, e.t = (e.n or 1) + 1, time and time() or 0
			if E.frame and E.frame:IsShown() then E.Render() end
			return e, false
		end
	end
	local e = { m = msg, s = Cut(stack, E.STACK_MAX), l = Cut(locals, E.LOCALS_MAX), n = 1, t = time and time() or 0, ses = id, v = ns.version }
	list[#list + 1] = e
	local keep = math.max(10, tonumber(ecfg().keep) or 50)
	while #list > keep do table.remove(list, 1) end
	E.Notify(e)
	return e, true
end

function E.Notify(e)
	local c = ecfg()
	local ours = E.IsOurs(e)
	local now = GetTime and GetTime() or 0
	if (c.chat == "all" or (c.chat == "stinkie" and ours)) and (not E.lastChat or now - E.lastChat >= E.CHAT_EVERY) then
		E.lastChat = now
		local first = (e.m:match("^[^\n]*") or e.m):gsub("Interface[/\\]AddOns[/\\]", "")
		if #first > 140 then first = first:sub(1, 140) .. "..." end
		ns:Print("Caught an error" .. (ours and " in Stinkie UI" or "") .. ": " .. first .. "  (/stinkie errors)")
	end
	if c.sound then pcall(E.PlaySound) end
	if c.popup then
		E.view, E.index = "session", 1
		E.Show()
	elseif E.frame and E.frame:IsShown() then
		E.Render()
	end
end

-- The game's error handler while the module is on. It must never raise an error itself.
local busy = false
function E.Handler(msg)
	if busy then return end
	busy = true
	local stack = debugstack and debugstack(3) or nil
	local locals = (debuglocals and not InCombatLockdown()) and debuglocals(3) or nil
	pcall(E.Catch, msg, stack, locals)
	if ecfg().blizzard and E.previous then pcall(E.previous, msg) end
	busy = false
end

-- the game stopping an addon from doing something protected
local function OnBlocked(event, addon, func)
	if not E.installed then return end
	pcall(E.Catch, ("%s: the game %s it from calling %s."):format(tostring(addon),
		event == "ADDON_ACTION_FORBIDDEN" and "forbade" or "blocked", tostring(func)))
end

E.OnBlocked = OnBlocked

function E.Install()
	if E.installed then return true end
	if type(seterrorhandler) ~= "function" or type(geterrorhandler) ~= "function" then return false end
	if not ns.Modules.Loads("errors") or ns.Modules.Conflict("errors") then return false end
	local store = E.Store()
	store.session = store.session + 1
	E.sessionId = store.session
	pcall(E.RestoreVolume) -- left over from a /reload while the sound was playing
	E.previous = geterrorhandler()
	seterrorhandler(E.Handler)
	E.installed = true
	ns:On("ADDON_ACTION_BLOCKED", OnBlocked)
	ns:On("ADDON_ACTION_FORBIDDEN", OnBlocked)
	return true
end

function E:Init() E.Install() end

-- as early as the saved settings allow, so errors while the rest loads are caught too
ns:On("ADDON_LOADED", function(_, name)
	if name == ns.name then pcall(E.Install) end
end)

---------------------------------------------------------------------------
-- The errors window
---------------------------------------------------------------------------
E.VIEWS = { { "session", "This session" }, { "last", "Last session" }, { "all", "All" } }

-- the errors of a view, newest first
function E.List(view)
	local store = E.Store()
	local id = E.sessionId or store.session
	local out = {}
	for i = #store.list, 1, -1 do
		local e = store.list[i]
		if view == "all" or (view == "session" and e.ses == id) or (view == "last" and e.ses == id - 1) then
			out[#out + 1] = e
		end
	end
	return out
end

-- one error as text: what to read, and what to paste when asking for a fix
function E.Text(e)
	local lines = {}
	local when = (date and e.t and e.t > 0) and date("%Y-%m-%d %H:%M", e.t) or "?"
	lines[#lines + 1] = ("[x%d] %s, Stinkie UI %s"):format(e.n or 1, when, tostring(e.v or "?"))
	lines[#lines + 1] = e.m
	if e.s and e.s ~= "" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Stack:"
		lines[#lines + 1] = e.s
	end
	if e.l and e.l ~= "" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Locals:"
		lines[#lines + 1] = e.l
	end
	return table.concat(lines, "\n")
end

ns.Dialogs.WIPE_ERRORS = {
	text = "Wipe all %s saved errors? This can't be undone.",
	button1 = "Wipe", button2 = "Keep",
	OnAccept = function() E.Wipe() ns:Print("Saved errors wiped.") end,
}

-- asks first; nothing saved: nothing to ask
function E.AskWipe()
	local n = #E.Store().list
	if n == 0 then ns:Print("No saved errors to wipe.") return end
	ns.ShowDialog("WIPE_ERRORS", n)
end

function E.Wipe()
	local store = E.Store()
	for i = #store.list, 1, -1 do store.list[i] = nil end
	E.index = 1
	if E.frame and E.frame:IsShown() then E.Render() end
end

local function ViewLabel(view)
	for _, v in ipairs(E.VIEWS) do if v[1] == view then return v[2] end end
	return view
end

function E.Render()
	local f = E.frame
	if not f then return end
	local list = E.List(E.view)
	E.index = math.max(1, math.min(E.index, math.max(#list, 1)))
	local e = list[E.index]
	local label = ViewLabel(E.view)
	if e then
		f.title:SetText(("Errors: %s, %d of %d"):format(label:lower(), E.index, #list))
		f.shown = E.Text(e)
	else
		f.title:SetText("Errors: " .. label:lower())
		f.shown = "No errors here."
	end
	f.edit:SetText(f.shown)
	f.scroll:SetVerticalScroll(0)
	local P = ns.BRAND.plum
	for _, tab in ipairs(f.tabs) do
		local on = tab.view == E.view
		tab.selected = on
		if on then tab.bg:SetColorTexture(P[1], P[2], P[3], 1) else tab.bg:SetColorTexture(0.15, 0.13, 0.11, 1) end
	end
end

local function CreateErrorsWindow()
	local f = CreateFrame("Frame", "StinkieUIErrors", UIParent)
	-- above the options window (DIALOG), under Stinkie UI's yes / no box and the report
	f:SetFrameStrata("FULLSCREEN")
	f:SetSize(680, 430)
	f:SetPoint("CENTER", 0, 40)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.055, 0.050, 0.035, 0.98)
	ns.CreateBackdrop(f, 0)
	f.title = ns.CreateText(f, 15, "LEFT")
	f.title:SetPoint("TOPLEFT", 12, -11)
	f.title:SetTextColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3])

	local P = ns.BRAND.plum
	local function button(text, width, onClick)
		local b = ns.DialogButton(f)
		b:SetSize(width, 22)
		b.text:SetText(text)
		b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(P[1] * 0.6, P[2] * 0.6, P[3] * 0.6, 1) end end)
		b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0.15, 0.13, 0.11, 1) end end)
		b:SetScript("OnClick", onClick)
		return b
	end
	f.close = button("Close", 70, function() f:Hide() end)
	f.close:SetPoint("TOPRIGHT", -10, -8)

	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:SetPoint("TOPLEFT", 12, -38)
	sf:SetPoint("BOTTOMRIGHT", -12, 72)
	sf.bg = sf:CreateTexture(nil, "BACKGROUND")
	sf.bg:SetAllPoints()
	sf.bg:SetColorTexture(0.12, 0.11, 0.09, 1)
	ns.CreateBackdrop(sf, 0)
	local eb = CreateFrame("EditBox", nil, sf)
	eb:SetMultiLine(true)
	eb:SetAutoFocus(false)
	ns.SetFont(eb, ecfg().fontSize or 12)
	eb:SetWidth(644)
	eb:SetTextInsets(6, 6, 6, 6)
	eb:SetScript("OnEscapePressed", function() f:Hide() end)
	-- it's there to read and copy: typing puts the text back
	eb:SetScript("OnTextChanged", function(self, user) if user and f.shown then self:SetText(f.shown) end end)
	sf:SetScrollChild(eb)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, d)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange() or 0, (self:GetVerticalScroll() or 0) - d * 40)))
	end)
	sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
	f.scroll, f.edit = sf, eb

	local function move(by)
		E.index = E.index + by
		E.Render()
	end
	f.prev = button("< Newer", 150, function() move(-1) end)
	f.prev:SetPoint("BOTTOMLEFT", 12, 40)
	f.next = button("Older >", 150, function() move(1) end)
	f.next:SetPoint("BOTTOMRIGHT", -12, 40)
	f.copy = button("Select all (then Ctrl+C)", 0, function()
		eb:SetFocus()
		eb:HighlightText()
	end)
	f.copy:SetPoint("LEFT", f.prev, "RIGHT", 8, 0)
	f.copy:SetPoint("RIGHT", f.next, "LEFT", -8, 0)

	f.tabs = {}
	for i, v in ipairs(E.VIEWS) do
		local tab = button(v[2], 110, function()
			E.view, E.index = v[1], 1
			E.Render()
		end)
		tab.view = v[1]
		tab:SetPoint("BOTTOMLEFT", 12 + (i - 1) * 116, 10)
		f.tabs[i] = tab
	end
	f.wipe = button("Wipe saved errors", 150, function() E.AskWipe() end)
	f.wipe:SetPoint("BOTTOMRIGHT", -12, 10)
	f.report = button("Support report", 130, function() R.Show() end)
	f.report:SetPoint("RIGHT", f.wipe, "LEFT", -8, 0)
	-- Escape closes it, as it does Stinkie UI's other windows
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "StinkieUIErrors") end
	f:Hide()
	E.frame = f
	return f
end

function E.Show()
	local f = E.frame or CreateErrorsWindow()
	ns.SetFont(f.edit, ecfg().fontSize or 12)
	E.Render()
	f:Show()
	return f
end

function E.Toggle()
	if E.frame and E.frame:IsShown() then E.frame:Hide() return end
	if not E.installed then
		local other = ns.Modules.Conflict("errors")
		ns:Print(other and ("Error Catcher is off because " .. other .. " is loaded. What it kept earlier is still here.")
			or "Error Catcher is off. Turn it on in /stinkie modules. What it kept earlier is still here.")
	end
	E.index = 1
	E.Show()
end

function E:Refresh()
	if E.frame and E.frame:IsShown() then
		ns.SetFont(E.frame.edit, ecfg().fontSize or 12)
		E.Render()
	end
end

ns:RegisterModule("Errors", E)

-- Stinkie UI's own errors the catcher kept, newest first: the message and where it happened.
-- No local values here: those can hold names.
function R.CaughtErrors(max)
	local out = {}
	for _, e in ipairs(E.List("all")) do
		if E.IsOurs(e) then
			local where = {}
			for line in (e.s or ""):gmatch("[^\n]+") do
				if #where >= 4 then break end
				where[#where + 1] = line
			end
			out[#out + 1] = { msg = Clean(e.m), count = e.n or 1, where = where, v = e.v }
			if #out >= (max or 8) then break end
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
	local caught = R.CaughtErrors()
	if #caught > 0 then
		add("From the Error Catcher (Stinkie UI's, newest first):")
		for _, e in ipairs(caught) do
			add(string.format("  [x%d] (%s) %s", e.count, tostring(e.v), e.msg))
			for _, line in ipairs(e.where) do add("      " .. line) end
		end
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
