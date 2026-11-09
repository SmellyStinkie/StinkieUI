-- StinkieUI: chat. Restyles Blizzard's own chat windows instead of replacing them, so Blizzard
-- still receives and formats every message (whispers, links, class colors, popouts, censoring).
-- This module adds: a flat background and flat tabs, font / size / outline / spacing, messages
-- kept across reloads, a copy window, timestamps, shorter channel and name formatting, sender
-- levels, per-type colors, whispers in their own tab, tab flashing and hide-until-mouseover.
--
-- How lines are edited: a secure post-hook on each window's AddMessage, then the window's
-- TransformMessages (one of the functions Blizzard exposes so addons can customise message
-- frames). Nothing is written into Blizzard's chat tables and no Blizzard global is changed.
--
-- Midnight: in arenas, battlegrounds, dungeons, raids and encounters, chat text reaches addons
-- as a secret value. Those lines still get a timestamp (joining strings is allowed on secrets),
-- but they can't be reworded, saved for after a reload, or copied. Blizzard's own class colors
-- still apply to them.
local _, ns = ...

local CH = {}
ns.Chat = CH

local issecret = ns.issecret

-- In a match a chat widget's own state can come back hidden (HasFocus, IsShown, GetAlpha...), and
-- a hidden answer can't be tested. So each check says what to assume when it can't tell.
local function Known(v, default)
	if issecret(v) then return default end
	return v
end
local function cfg() return ns.db.chat end

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local objects = setmetatable({}, { __mode = "k" }) -- chat frame -> our widgets
local hooked = setmetatable({}, { __mode = "k" })
local showUntil = setmetatable({}, { __mode = "k" }) -- chat frame -> time it stays shown after a message
local flashing = setmetatable({}, { __mode = "k" })

-- chat types typed by players (tab flashing can be limited to these)
local PLAYER_TYPES = {
	SAY = true, YELL = true, EMOTE = true, TEXT_EMOTE = true, GUILD = true, OFFICER = true,
	PARTY = true, PARTY_LEADER = true, RAID = true, RAID_LEADER = true, RAID_WARNING = true,
	INSTANCE_CHAT = true, INSTANCE_CHAT_LEADER = true, WHISPER = true, WHISPER_INFORM = true,
	BN_WHISPER = true, BN_WHISPER_INFORM = true, CHANNEL = true, COMMUNITIES_CHANNEL = true,
}
local WHISPER_TYPES = { WHISPER = true, BN_WHISPER = true }

-- short channel tags, by chat type
local SHORT = {
	GUILD = "G", OFFICER = "O", PARTY = "P", PARTY_LEADER = "PL", PARTY_GUIDE = "PG",
	RAID = "R", RAID_LEADER = "RL", RAID_WARNING = "RW",
	INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
}

-- Colors offered in the options: { chat type, label }
CH.COLOR_TYPES = {
	{ "SAY", "Say" }, { "YELL", "Yell" }, { "EMOTE", "Emote" },
	{ "PARTY", "Party" }, { "PARTY_LEADER", "Party leader" },
	{ "RAID", "Raid" }, { "RAID_LEADER", "Raid leader" }, { "RAID_WARNING", "Raid warning" },
	{ "INSTANCE_CHAT", "Instance" }, { "INSTANCE_CHAT_LEADER", "Instance leader" },
	{ "GUILD", "Guild" }, { "OFFICER", "Officer" },
	{ "WHISPER", "Whisper (from)" }, { "WHISPER_INFORM", "Whisper (to)" },
	{ "BN_WHISPER", "Battle.net whisper (from)" }, { "BN_WHISPER_INFORM", "Battle.net whisper (to)" },
	{ "SYSTEM", "System" }, { "LOOT", "Loot" }, { "MONEY", "Money" }, { "CURRENCY", "Currency" },
	{ "ACHIEVEMENT", "Achievement" }, { "GUILD_ACHIEVEMENT", "Guild achievement" },
	{ "SKILL", "Skill" }, { "COMBAT_XP_GAIN", "Experience" }, { "COMBAT_HONOR_GAIN", "Honor" },
	{ "COMBAT_FACTION_CHANGE", "Reputation" },
	{ "MONSTER_SAY", "NPC say" }, { "MONSTER_YELL", "NPC yell" }, { "RAID_BOSS_EMOTE", "Boss emote" },
}
CH.CHANNEL_SLOTS = 10

-- player chat types whose sender names can be class colored
local CLASS_COLOR_TYPES = {
	"SAY", "YELL", "EMOTE", "TEXT_EMOTE", "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
	"RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "WHISPER", "WHISPER_INFORM",
	"GUILD_ACHIEVEMENT", "ACHIEVEMENT",
}
for i = 1, CH.CHANNEL_SLOTS do table.insert(CLASS_COLOR_TYPES, "CHANNEL" .. i) end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function IsFrame(f)
	return type(f) == "table" and type(f.GetName) == "function" and type(f.AddMessage) == "function"
end

local function ChatFrames()
	local list, seen = {}, {}
	local names = type(CHAT_FRAMES) == "table" and CHAT_FRAMES or {}
	for _, name in ipairs(names) do
		local f = _G[name]
		if IsFrame(f) and not seen[f] then seen[f] = true; list[#list + 1] = f end
	end
	for i = 1, (tonumber(NUM_CHAT_WINDOWS) or 10) do
		local f = _G["ChatFrame" .. i]
		if IsFrame(f) and not seen[f] then seen[f] = true; list[#list + 1] = f end
	end
	return list
end
CH.ChatFrames = ChatFrames

local function Part(f, suffix) return _G[f:GetName() .. suffix] end

-- The combat log window: its lines are protected strings, so it's skinned but never edited.
local function IsCombatLogFrame(f)
	if f ~= _G.ChatFrame2 then return false end
	if type(IsCombatLog) == "function" then
		local ok, r = pcall(IsCombatLog, f)
		return ok and r and true or false
	end
	return true
end

local function IsTemporary(f) return f.isTemporary == true end

-- Where whispers show, as the game's own setting. It covers Battle.net whispers too.
CH.WHISPER_MODES = { both = "popout_and_inline", main = "inline", tab = "popout" }

---------------------------------------------------------------------------
-- History (per character: StinkieUIChatHistory)
---------------------------------------------------------------------------
local store
local pending = {}   -- lines recorded before the first loading screen decides the session
local sessionReady = false

local function Store()
	if store then return store end
	local s = rawget(_G, "StinkieUIChatHistory")
	if type(s) ~= "table" then s = {} end
	s.session = tonumber(s.session) or 0
	s.lines = type(s.lines) == "table" and s.lines or {}
	_G.StinkieUIChatHistory = s
	store = s
	return s
end

-- Which window's history a line belongs to. Whisper tabs are temporary, and the game closes them
-- on a reload. When whispers only go there, nothing else holds them, so they're kept with the main
-- window. In the other modes the main window has its own copy.
function CH.HistoryID(f)
	if not IsTemporary(f) then return f:GetID() end
	if WHISPER_TYPES[f.chatType] and GetCVar("whisperMode") == CH.WHISPER_MODES.tab then return 1 end
end

local function Record(f, msg, r, g, b, event)
	local c = cfg()
	if c.history == "off" or IsCombatLogFrame(f) then return end
	local id = CH.HistoryID(f)
	if type(id) ~= "number" then return end
	local line = { t = time(), m = msg, r = r, g = g, b = b, e = event }
	if not sessionReady then
		pending[#pending + 1] = { id, line }
		return
	end
	local s = Store()
	line.s = s.session
	local list = s.lines[id]
	if not list then list = {}; s.lines[id] = list end
	list[#list + 1] = line
	local max = c.historyLines or 300
	while #list > max do table.remove(list, 1) end
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local measure
local widthCache = {}
local function TextWidth(text)
	local w = widthCache[text]
	if w then return w end
	if not measure then
		measure = UIParent:CreateFontString(nil, "BACKGROUND")
		measure:SetAlpha(0)
	end
	local c = cfg()
	pcall(measure.SetFont, measure, ns.GetFontPath(), c.fontSize > 0 and c.fontSize or 14, ns.OutlineFlags(c.outline) or "")
	measure:SetText(text)
	w = measure:GetStringWidth() or 0
	if type(w) ~= "number" or issecret(w) then w = 0 end
	widthCache[text] = w
	return w
end
function CH.ResetMeasure() wipe(widthCache) end

local function Hex(c) return string.format("%02x%02x%02x", (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255) end

-- Timestamp prefix for a line at time t (nil when timestamps are off).
function CH.Stamp(t)
	local c = cfg()
	if c.timestamps ~= "hm" and c.timestamps ~= "hms" then return nil end
	local fmt
	if c.timestamps == "hms" then fmt = c.clock24 and "%H:%M:%S" or "%I:%M:%S" else fmt = c.clock24 and "%H:%M" or "%I:%M" end
	local s = date(fmt, t or time())
	local text = "|cff" .. Hex(c.timestampColor) .. s .. "|r"
	if c.timestampMode == "column" then
		-- a fixed-width cell: pad with an empty inline texture so every message starts at the same x
		local widest = TextWidth(c.timestamps == "hms" and "00:00:00" or "00:00")
		local pad = math.floor(widest - TextWidth(s) + (c.columnGap or 8) + 0.5)
		if pad < 1 then pad = 1 end
		return text .. "|T" .. ns.MEDIA.blank .. ":1:" .. pad .. "|t"
	end
	return text .. " "
end

-- level cache: name (with and without realm) -> level
local levels = {}
local function NoteLevel(name, level)
	if type(name) ~= "string" or issecret(name) or type(level) ~= "number" or issecret(level) or level <= 0 then return end
	levels[name] = level
	local short = name:match("^([^%-]+)")
	if short then levels[short] = level end
end
CH.NoteLevel = NoteLevel

local function NoteUnit(unit)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
	local name, realm = UnitName(unit)
	if issecret(name) or issecret(realm) then return end
	local level = UnitLevel(unit)
	if realm and realm ~= "" then NoteLevel(name .. "-" .. realm, level) else NoteLevel(name, level) end
end

local function ScanGroup()
	if IsInRaid() then
		for i = 1, 40 do NoteUnit("raid" .. i) end
	else
		for i = 1, 4 do NoteUnit("party" .. i) end
	end
	NoteUnit("player")
end

local function ScanGuild()
	if not (IsInGuild and IsInGuild()) or type(GetNumGuildMembers) ~= "function" then return end
	local n = GetNumGuildMembers()
	if type(n) ~= "number" then return end
	for i = 1, n do
		local name, _, _, level = GetGuildRosterInfo(i)
		NoteLevel(name, level)
	end
end

local function ScanFriends()
	if not (C_FriendList and C_FriendList.GetNumFriends) then return end
	local n = C_FriendList.GetNumFriends()
	if type(n) ~= "number" then return end
	for i = 1, n do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if type(info) == "table" then NoteLevel(info.name, info.level) end
	end
end

local function MaxLevel()
	local m = GetMaxLevelForLatestExpansion and GetMaxLevelForLatestExpansion() or (GetMaxPlayerLevel and GetMaxPlayerLevel())
	return type(m) == "number" and m or 90
end

local function ChannelLabel(label, chatType)
	local c = cfg()
	local text = label
	if c.channelStyle == "short" then
		if chatType == "CHANNEL" then
			text = label:match("^(%d+)") or label
		else
			text = SHORT[chatType] or label:sub(1, 1)
		end
	elseif c.channelStyle == "name" and chatType == "CHANNEL" then
		local name = label:match("^%d+%.%s*(.+)$") or label
		text = name:match("^(.-)%s+%-%s+.+$") or name -- "Trade - City" -> "Trade"
	end
	if c.removeBrackets then return text end
	return "[" .. text .. "]"
end

local whisperPatterns
local function WhisperPatterns()
	if whisperPatterns then return whisperPatterns end
	whisperPatterns = {}
	for _, key in ipairs({ "CHAT_WHISPER_GET", "CHAT_BN_WHISPER_GET" }) do
		local fmt = _G[key]
		if type(fmt) == "string" and fmt:find("%%s") then
			local escaped = fmt:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1") -- "%s" becomes "%%s"
			local pat = "^" .. escaped:gsub("%%%%s", "(.-)", 1)
			table.insert(whisperPatterns, pat)
		end
	end
	return whisperPatterns
end

-- Rewords a readable line. chatType is the CHAT_MSG_ suffix (nil for system/addon lines).
function CH.Reword(text, chatType)
	local c = cfg()
	-- channel tag: |Hchannel:...|h[Label]|h
	if c.channelStyle ~= "full" or c.removeBrackets then
		text = text:gsub("(|Hchannel:[^|]*|h)%[([^%]]*)%](|h)", function(open, label, close)
			return open .. ChannelLabel(label, chatType) .. close
		end, 1)
	end
	-- player names: |Hplayer:Name-Realm:...|h[Name]|h  (also Battle.net links)
	text = text:gsub("(|H(B?N?player):([^|]*)|h)(.-)(|h)", function(open, kind, target, display, close)
		if c.removeBrackets then display = display:gsub("^%[(.*)%]$", "%1") end
		if c.hideRealms and kind == "player" then
			display = display:gsub("%-[^|%]%s]+", "", 1)
		end
		if c.showLevel and kind == "player" then
			local name = target:match("^([^:]+)")
			local lvl = name and (levels[name] or levels[name:match("^([^%-]+)") or ""])
			if lvl and not (c.levelHideMax and lvl >= MaxLevel()) then
				local inner = display:match("^%[(.*)%]$")
				if inner then
					display = "[|cffa0a0a0" .. lvl .. "|r:" .. inner .. "]"
				else
					display = "|cffa0a0a0" .. lvl .. "|r:" .. display
				end
			end
		end
		return open .. display .. close
	end)
	if c.shortWhispers and chatType and WHISPER_TYPES[chatType] then
		for _, pat in ipairs(WhisperPatterns()) do
			local replaced, n = text:gsub(pat, "%1: ", 1)
			if n > 0 then
				text = (GetLocale and GetLocale() == "enUS") and ("From " .. replaced) or replaced
				break
			end
		end
	end
	return text
end

-- Final text for a line: reworded when readable, timestamp in front either way.
local function Join(a, b) return a .. b end
local function Compose(msg, chatType, t)
	local out = msg
	if not issecret(msg) then out = CH.Reword(msg, chatType) end
	local stamp = CH.Stamp(t)
	if stamp then
		local ok, joined = pcall(Join, stamp, out)
		if ok then out = joined end
	end
	return out
end
CH.Compose = Compose

---------------------------------------------------------------------------
-- New lines
---------------------------------------------------------------------------
local function ChatTypeOf(event)
	if type(event) ~= "string" or issecret(event) then return nil end
	return event:match("^CHAT_MSG_(.+)$")
end

local function StartFlash(f, chatType)
	local c = cfg()
	if not c.flashTabs or Known(f:IsShown(), false) then return end
	if c.flashPlayerOnly and not (chatType and PLAYER_TYPES[chatType]) then return end
	flashing[f] = true
end

-- Blizzard stops a whisper tab's flash when you reply, as you've seen it in the main tab. In a
-- match it can pass a hidden frame, which can't be looked up, so that tab flashes until you open it.
function CH.StopFlash(f)
	if issecret(f) then return end
	flashing[f] = nil
end
function CH.IsFlashing(f) return flashing[f] == true end

local function OnAddMessage(f, msg, r, g, b, id, accessID, typeID, event, eventArgs)
	if CH.busy then return end
	local secret = issecret(msg)
	if not secret and type(msg) ~= "string" then return end
	local chatType = ChatTypeOf(event)
	local c = cfg()
	if c.showOnMessage and c.mouseover then showUntil[f] = GetTime() + (c.showOnMessageTime or 5) end
	StartFlash(f, chatType)
	if IsCombatLogFrame(f) then return end
	if not secret then Record(f, msg, r, g, b, chatType) end

	local now = time()
	local newText = Compose(msg, chatType, now)
	if not secret and newText == msg then return end
	if secret and not CH.Stamp(now) then return end
	-- find this exact line: by Blizzard's per-message event table when there is one, otherwise by
	-- its (readable) text. Secret entries are never compared.
	local predicate
	if type(eventArgs) == "table" then
		predicate = function(_, _, _, _, ...)
			local v = select(5, ...)
			return not issecret(v) and v == eventArgs
		end
	elseif not secret then
		predicate = function(m)
			return not issecret(m) and m == msg
		end
	else
		return
	end
	CH.busy = true
	pcall(f.TransformMessages, f, predicate, function(_, rr, gg, bb, ...)
		return newText, rr, gg, bb, ...
	end)
	CH.busy = false
end

---------------------------------------------------------------------------
-- Restore after a reload / login
---------------------------------------------------------------------------
local DIVIDER = "|cff7f7f7f-- earlier messages --|r"

local function Restore()
	local s = Store()
	local c = cfg()
	for _, f in ipairs(ChatFrames()) do
		local list = s.lines[f:GetID()]
		if list and #list > 0 and not IsTemporary(f) and not IsCombatLogFrame(f) then
			CH.busy = true
			if c.restoreDivider then pcall(f.BackFillMessage, f, DIVIDER, 1, 1, 1) end
			for i = #list, 1, -1 do
				local line = list[i]
				if type(line.m) == "string" then
					pcall(f.BackFillMessage, f, Compose(line.m, line.e, line.t), line.r, line.g, line.b)
				end
			end
			CH.busy = false
		end
	end
end

-- First loading screen of this login or reload: decide the session, prune, restore.
local function OnFirstEnteringWorld(isInitialLogin)
	if sessionReady then return end
	local s = Store()
	local c = cfg()
	if isInitialLogin then
		s.session = s.session + 1
		local keepFrom = (c.history == "session") and (s.session - 1) or s.session
		for id, list in pairs(s.lines) do
			local kept = {}
			for _, line in ipairs(list) do
				if (tonumber(line.s) or 0) >= keepFrom then kept[#kept + 1] = line end
			end
			s.lines[id] = kept
		end
	end
	if c.history == "off" then wipe(s.lines) end
	if c.history ~= "off" then Restore() end
	sessionReady = true
	for _, p in ipairs(pending) do
		local id, line = p[1], p[2]
		line.s = s.session
		local list = s.lines[id]
		if not list then list = {}; s.lines[id] = list end
		list[#list + 1] = line
	end
	wipe(pending)
end
CH.OnFirstEnteringWorld = OnFirstEnteringWorld

function CH.ClearHistory()
	local s = Store()
	wipe(s.lines)
end

---------------------------------------------------------------------------
-- Copy window
---------------------------------------------------------------------------
local function Plain(s)
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
	s = s:gsub("|H.-|h(.-)|h", "%1")
	s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return s
end
CH.Plain = Plain

function CH.CopyText(f)
	local lines = {}
	local n = f.GetNumMessages and f:GetNumMessages() or 0
	if type(n) ~= "number" then n = 0 end
	for i = 1, n do
		local msg = f:GetMessageInfo(i)
		if issecret(msg) then
			lines[#lines + 1] = "(hidden: sent during restricted content)"
		elseif type(msg) == "string" then
			lines[#lines + 1] = Plain(msg)
		end
	end
	return table.concat(lines, "\n")
end

local copyWindow
local function CopyWindow()
	if copyWindow then return copyWindow end
	local p = CreateFrame("Frame", "StinkieUIChatCopy", UIParent)
	p:SetSize(640, 420)
	p:SetPoint("CENTER")
	p:SetFrameStrata("DIALOG")
	p:EnableMouse(true)
	p:SetMovable(true)
	p:SetClampedToScreen(true)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", p.StartMoving)
	p:SetScript("OnDragStop", p.StopMovingOrSizing)
	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.055, 0.050, 0.035, 0.97)
	ns.CreateBackdrop(p, 0)
	table.insert(UISpecialFrames, "StinkieUIChatCopy")
	local title = p:CreateFontString(nil, "OVERLAY")
	ns.SetFont(title, 15, "OUTLINE")
	title:SetTextColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3])
	title:SetPoint("TOPLEFT", 12, -10)
	p.title = title
	local hint = p:CreateFontString(nil, "OVERLAY")
	ns.SetFont(hint, 12, "")
	hint:SetTextColor(0.70, 0.68, 0.60)
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	hint:SetText("Select text with the mouse (or Ctrl+A for everything), then Ctrl+C.")
	local close = CreateFrame("Button", nil, p)
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -8, -8)
	local ct = close:CreateFontString(nil, "OVERLAY")
	ns.SetFont(ct, 14, "OUTLINE")
	ct:SetPoint("CENTER")
	ct:SetText("x")
	close:SetScript("OnClick", function() p:Hide() end)

	local sf = CreateFrame("ScrollFrame", nil, p)
	sf:SetPoint("TOPLEFT", 12, -52)
	sf:SetPoint("BOTTOMRIGHT", -12, 12)
	local sbg = sf:CreateTexture(nil, "BACKGROUND")
	sbg:SetAllPoints()
	sbg:SetColorTexture(0.12, 0.11, 0.09, 1)
	local eb = CreateFrame("EditBox", nil, sf)
	eb:SetMultiLine(true)
	eb:SetAutoFocus(false)
	ns.SetFont(eb, 13)
	eb:SetWidth(610)
	eb:SetTextInsets(6, 6, 6, 6)
	eb:SetScript("OnEscapePressed", function() p:Hide() end)
	eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(p.text or "") end end)
	sf:SetScrollChild(eb)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, d)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - d * 40)))
	end)
	sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
	p.eb, p.sf = eb, sf
	copyWindow = p
	return p
end

-- Any text you may want out of the game, in the same window
function CH.ShowText(title, text)
	local p = CopyWindow()
	p.title:SetText(title)
	p.text = text
	p.eb:SetText(text)
	p.sf:SetVerticalScroll(0)
	p:Show()
	p.eb:SetFocus()
	return p
end

function CH.ShowCopy(f)
	local p = CH.ShowText("Copy chat", CH.CopyText(f or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME))
	-- start at the newest line
	C_Timer.After(0, function()
		if p.sf.GetVerticalScrollRange then p.sf:SetVerticalScroll(p.sf:GetVerticalScrollRange() or 0) end
	end)
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local TAB_TEXTURES = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
	"HighlightLeft", "HighlightMiddle", "HighlightRight" }
local EDIT_TEXTURES = { "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }

local function HideRegion(region)
	if region and region.SetParent then region:SetParent(hiddenParent) end
end

local function ApplyFont(f)
	local c = cfg()
	local size = c.fontSize
	if not size or size <= 0 then
		-- the window's own size from Blizzard's chat settings (0 means its default, 14)
		local cur = FCF_GetChatWindowInfo and select(2, FCF_GetChatWindowInfo(f:GetID()))
		size = type(cur) == "number" and cur > 0 and cur or 14
	end
	local flags = ns.OutlineFlags(c.outline) or ""
	pcall(f.SetFont, f, ns.GetFontPath(), size, flags)
	if flags == "" then
		pcall(f.SetShadowOffset, f, 1, -1)
		pcall(f.SetShadowColor, f, 0, 0, 0, 1)
	else
		pcall(f.SetShadowOffset, f, 0, 0)
	end
	pcall(f.SetSpacing, f, c.spacing or 0)
	pcall(f.SetIndentedWordWrap, f, c.indent and true or false)
end

local function Skin(f)
	local c = cfg()
	local o = objects[f]
	if not o then
		o = {}
		objects[f] = o
		local box = Part(f, "Background") or f
		-- flat background behind the text, sized to Blizzard's box (follows resizing)
		local bg = CreateFrame("Frame", nil, f)
		bg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
		bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
		bg:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
		bg.tex = bg:CreateTexture(nil, "BACKGROUND", nil, -6)
		bg.tex:SetAllPoints()
		ns.CreateBackdrop(bg, 0)
		o.bg = bg
		for _, name in ipairs(CHAT_FRAME_TEXTURES or {}) do HideRegion(Part(f, name)) end

		-- copy button, shown while the mouse is over the window
		local copy = CreateFrame("Button", nil, bg)
		copy:SetSize(34, 16)
		copy:SetPoint("TOPRIGHT", bg, "TOPRIGHT", -4, -4)
		copy:SetFrameLevel((f:GetFrameLevel() or 1) + 6)
		copy.tex = copy:CreateTexture(nil, "BACKGROUND")
		copy.tex:SetAllPoints()
		copy.tex:SetColorTexture(0.12, 0.11, 0.09, 0.9)
		ns.CreateBackdrop(copy, 0)
		copy.text = copy:CreateFontString(nil, "OVERLAY")
		ns.SetFont(copy.text, 11, "OUTLINE")
		copy.text:SetPoint("CENTER")
		copy.text:SetText("Copy")
		copy:SetScript("OnClick", function() CH.ShowCopy(f) end)
		copy:SetScript("OnEnter", function(self) self.text:SetTextColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3]) end)
		copy:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)
		copy:Hide()
		o.copy = copy

		-- tab: flat block, accent line under the selected tab, pulsing fill while flashing
		local tab = Part(f, "Tab")
		if tab then
			o.tab = tab
			for _, key in ipairs(TAB_TEXTURES) do HideRegion(tab[key]) end
			if c.flashTabs then HideRegion(tab.glow) end
			local tb = CreateFrame("Frame", nil, tab)
			tb:SetPoint("TOPLEFT", 2, -6)
			tb:SetPoint("BOTTOMRIGHT", -2, 2)
			tb:SetFrameLevel(math.max(0, (tab:GetFrameLevel() or 1) - 1))
			if tb.SetIgnoreParentAlpha then tb:SetIgnoreParentAlpha(true) end
			tb.fill = tb:CreateTexture(nil, "BACKGROUND", nil, -5)
			tb.fill:SetAllPoints()
			tb.flash = tb:CreateTexture(nil, "BACKGROUND", nil, -4)
			tb.flash:SetAllPoints()
			tb.flash:SetColorTexture(ns.BRAND.orange[1], ns.BRAND.orange[2], ns.BRAND.orange[3], 0)
			tb.line = tb:CreateTexture(nil, "BORDER")
			tb.line:SetPoint("BOTTOMLEFT")
			tb.line:SetPoint("BOTTOMRIGHT")
			tb.line:SetHeight(2)
			tb.line:SetColorTexture(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 1)
			o.tabBg = tb
			local fs = tab.GetFontString and tab:GetFontString()
			if fs and fs.SetIgnoreParentAlpha then fs:SetIgnoreParentAlpha(true) end
			o.tabText = fs
		end

		-- input box: flat, same font
		local eb = f.editBox or Part(f, "EditBox")
		if eb and not InCombatLockdown() then
			o.edit = eb
			for _, key in ipairs(EDIT_TEXTURES) do HideRegion(Part(eb, key)) end
			local ebg = CreateFrame("Frame", nil, eb)
			ebg:SetPoint("TOPLEFT", 4, -5)
			ebg:SetPoint("BOTTOMRIGHT", -4, 5)
			ebg:SetFrameLevel(math.max(0, (eb:GetFrameLevel() or 1) - 1))
			ebg.tex = ebg:CreateTexture(nil, "BACKGROUND")
			ebg.tex:SetAllPoints()
			ns.CreateBackdrop(ebg, 0)
			o.editBg = ebg
		end

		f:HookScript("OnShow", function() flashing[f] = nil end)
	end

	local bc = c.bgColor
	o.bg.tex:SetColorTexture(bc[1], bc[2], bc[3], c.bgAlpha)
	o.bg.SUIBorder.bg:SetAlpha(0)
	for _, e in ipairs(o.bg.SUIBorder.edges) do e:SetAlpha(c.border and c.bgAlpha > 0 and 1 or 0) end
	if o.tabBg then
		local tc = c.tabColor
		o.tabBg.fill:SetColorTexture(tc[1], tc[2], tc[3], 1)
		if o.tabText then ns.ApplyText(o.tabText, c.tabStyle) end
	end
	if o.editBg then
		o.editBg.tex:SetColorTexture(bc[1], bc[2], bc[3], math.max(c.bgAlpha, 0.6))
		local eb = o.edit
		pcall(eb.SetFont, eb, ns.GetFontPath(), (c.fontSize > 0 and c.fontSize or 14), ns.OutlineFlags(c.outline) or "")
		if eb.header then pcall(eb.header.SetFont, eb.header, ns.GetFontPath(), (c.fontSize > 0 and c.fontSize or 14), ns.OutlineFlags(c.outline) or "") end
	end
	ApplyFont(f)
	if not IsCombatLogFrame(f) then
		local lines = c.history ~= "off" and math.max(c.maxLines, c.historyLines + 20) or c.maxLines
		pcall(f.SetMaxLines, f, lines)
	end
	pcall(f.SetTextCopyable, f, c.dragCopy and true or false)
end

-- The social button, just above the side buttons, level with the chat tabs. Blizzard's alert system
-- places it, so this runs again after each time it does.
local placingSocial = false
function CH.PlaceSocial()
	local b, side = _G.QuickJoinToastButton, _G.ChatFrame1ButtonFrame
	if placingSocial or not (b and side and CH.active and cfg().socialByTabs) then return end
	placingSocial = true
	b:ClearAllPoints()
	b:SetPoint("BOTTOM", side, "TOP", 0, 1)
	placingSocial = false
end

-- Side buttons (menu, channels, voice) and the social button. Blizzard fades them itself, so
-- "hide" really hides them (out of combat) and keeps them hidden.
local buttonHooked, hiddenByUs = {}, {}
local socialHooked = false
local function ApplyButtons()
	if InCombatLockdown() then return end
	local social = _G.QuickJoinToastButton
	if type(social) == "table" and social.SetPoint and not socialHooked then
		socialHooked = true
		hooksecurefunc(social, "SetPoint", CH.PlaceSocial)
	end
	CH.PlaceSocial()
	local hide = cfg().buttons == "hide"
	for _, b in ipairs({ _G.ChatFrame1ButtonFrame, _G.QuickJoinToastButton }) do
		if type(b) == "table" and b.Hide then
			if not buttonHooked[b] then
				buttonHooked[b] = true
				b:HookScript("OnShow", function(self)
					if CH.active and cfg().buttons == "hide" and not InCombatLockdown() then self:Hide() end
				end)
			end
			if hide then
				if Known(b:IsShown(), false) then hiddenByUs[b] = true; b:Hide() end
			elseif hiddenByUs[b] then
				hiddenByUs[b] = nil
				b:Show()
			end
		end
	end
end

local function Hook(f)
	if hooked[f] then return end
	hooked[f] = true
	hooksecurefunc(f, "AddMessage", OnAddMessage)
end

function CH.SetupAll()
	for _, f in ipairs(ChatFrames()) do
		local ok, err = pcall(Skin, f)
		if not ok then ns.Error(err) end
		Hook(f)
	end
	ApplyButtons()
end

-- Right away: the game delivers the whisper that opened this window as soon as it returns, and
-- that line needs the hook (tab flash, history). Then once more, when its tab has settled.
function CH.OnTemporaryWindow()
	CH.SetupAll()
	C_Timer.After(0, CH.SetupAll)
end

---------------------------------------------------------------------------
-- Game settings this module manages
---------------------------------------------------------------------------
local function ApplyColors()
	local c = cfg()
	for chatType, col in pairs(c.colors) do
		if type(col) == "table" and ChangeChatColor then
			pcall(ChangeChatColor, chatType, col[1], col[2], col[3])
		end
	end
end
CH.ApplyColors = ApplyColors

local function ApplyClassColors()
	if not SetChatColorNameByClass then return end
	local want = cfg().classColors and true or false
	for _, chatType in ipairs(CLASS_COLOR_TYPES) do
		local info = ChatTypeInfo and ChatTypeInfo[chatType]
		if type(info) == "table" and (info.colorNameByClass and true or false) ~= want then
			pcall(SetChatColorNameByClass, chatType, want)
		end
	end
end

local function ApplyCVars()
	local c = cfg()
	-- timestamps are added here, so Blizzard's own are turned off
	if GetCVar("showTimestamps") ~= "none" then
		c.blizzardTimestamps = GetCVar("showTimestamps")
		SetCVar("showTimestamps", "none")
	end
	local mode = CH.WHISPER_MODES[c.whisperDisplay] or CH.WHISPER_MODES.both
	if GetCVar("whisperMode") ~= mode then
		ns.Modules.Remember("chat", "whisperMode")
		SetCVar("whisperMode", mode)
	end
end
CH.ApplyCVars = ApplyCVars

-- Current color of a chat type (the saved override, else what the game uses now).
function CH.GetColor(chatType)
	local col = cfg().colors[chatType]
	if type(col) == "table" then return col end
	local info = ChatTypeInfo and ChatTypeInfo[chatType]
	if type(info) == "table" and type(info.r) == "number" then return { info.r, info.g, info.b } end
	return { 1, 1, 1 }
end

function CH.SetColor(chatType, col)
	cfg().colors[chatType] = { col[1], col[2], col[3] }
	if ChangeChatColor then pcall(ChangeChatColor, chatType, col[1], col[2], col[3]) end
end

-- Channel slots with their current names, for the color list.
function CH.ChannelName(i)
	if type(GetChannelName) ~= "function" then return nil end
	local _, name = GetChannelName(i)
	if type(name) == "string" and not issecret(name) and name ~= "" then return name end
	return nil
end

---------------------------------------------------------------------------
-- Visibility: hide-until-mouseover, selected tab, flashing
---------------------------------------------------------------------------
local lastFocus = {}

-- the last answer we could read stands in for a hidden one, so chat doesn't fade as you type
local function Focused(eb)
	local v = eb:HasFocus()
	if issecret(v) then return lastFocus[eb] or false end
	lastFocus[eb] = v
	return v
end

local function Hovered(f)
	local box = Part(f, "Background") or f
	if Known(box:IsMouseOver(30, -4, -4, 4), false) then return true end
	local o = objects[f]
	if o and o.tab and Known(o.tab:IsMouseOver(), false) then return true end
	local eb = f.editBox or Part(f, "EditBox")
	if eb and eb.HasFocus and Focused(eb) then return true end
	if f.IsSelectingText and Known(f:IsSelectingText(), false) then return true end
	return false
end

CH.Hovered = Hovered

-- a hidden alpha can't be compared, so it's just set again
local function SetAlphaTo(frame, a)
	local cur = frame:GetAlpha()
	if issecret(cur) or cur ~= a then frame:SetAlpha(a) end
end

local function Tick()
	local c = cfg()
	local now = GetTime()
	local frames = ChatFrames()
	-- docked windows share one dock, so they fade together
	local dockShown = not c.mouseover
	if c.mouseover then
		if GeneralDockManager and Known(GeneralDockManager:IsMouseOver(), false) then dockShown = true end
		for _, f in ipairs(frames) do
			if f.isDocked and (Hovered(f) or (showUntil[f] and showUntil[f] > now)) then dockShown = true end
		end
		if rawget(_G, "MOVING_CHATFRAME") or ns.unlocked then dockShown = true end
	end
	local pulse = 0.25 + 0.25 * math.sin(now * 5)
	for _, f in ipairs(frames) do
		local shown = not c.mouseover
		if c.mouseover then
			if f.isDocked then shown = dockShown
			else shown = Hovered(f) or (showUntil[f] and showUntil[f] > now) or false end
		end
		local a = shown and 1 or (c.fadeAlpha or 0)
		SetAlphaTo(f, a)
		local o = objects[f]
		if o then
			o.copy:SetShown(c.copyButton and shown and Known(f:IsShown(), false) and Hovered(f) or false)
			if o.tabBg then
				local tab = o.tab
				local visible = Known(tab:IsShown(), true)
				local selected = Known(f:IsShown(), false)
				local hover = Known(tab:IsMouseOver(), false)
				local base = selected and 1 or (hover and 1 or c.tabInactiveAlpha)
				o.tabBg:SetAlpha(visible and a or 0)
				o.tabBg.fill:SetAlpha(c.tabAlpha)
				o.tabBg.line:SetShown(selected)
				if flashing[f] and not selected then
					o.tabBg.flash:SetAlpha(pulse)
				else
					o.tabBg.flash:SetAlpha(0)
				end
				if o.tabText then o.tabText:SetAlpha(visible and a * base or 0) end
			end
		end
	end
	if GeneralDockManager and GeneralDockManager.SetAlpha then
		local a = (dockShown and 1) or (c.fadeAlpha or 0)
		SetAlphaTo(GeneralDockManager, a)
	end
end
CH.Tick = Tick

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local CONFLICTS = { "Chattynator", "Prat-3.0", "ElvUI", "ls_Glass", "Glass" }
CH.CONFLICTS = CONFLICTS -- also shown in the module list

function CH:Init()
	local c = cfg()
	if not c.enabled then
		-- give Blizzard its timestamps back if this module had turned them off
		if c.blizzardTimestamps and GetCVar("showTimestamps") == "none" then
			SetCVar("showTimestamps", c.blizzardTimestamps)
			c.blizzardTimestamps = nil
		end
		return
	end
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		for _, other in ipairs(CONFLICTS) do
			if C_AddOns.IsAddOnLoaded(other) then
				ns:Print("Chat is off because " .. other .. " is loaded.")
				return
			end
		end
	end
	CH.active = true
	Store()
	ApplyCVars()
	ApplyColors()
	ApplyClassColors()
	CH.SetupAll()
	if FCF_OpenTemporaryWindow then
		hooksecurefunc("FCF_OpenTemporaryWindow", CH.OnTemporaryWindow)
	end
	if FCF_StopAlertFlash then hooksecurefunc("FCF_StopAlertFlash", CH.StopFlash) end
	if FCF_SetChatWindowFontSize then
		hooksecurefunc("FCF_SetChatWindowFontSize", function(_, chatFrame)
			if cfg().fontSize > 0 and chatFrame then ApplyFont(chatFrame) end
		end)
	end
	ns:On("UPDATE_CHAT_WINDOWS", function() C_Timer.After(0, CH.SetupAll) end)
	ns:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
		if not sessionReady then OnFirstEnteringWorld(isInitialLogin and true or false) end
		C_Timer.After(1, CH.SetupAll)
		ScanGroup()
	end)
	ns:On("GROUP_ROSTER_UPDATE", ScanGroup)
	ns:On("GUILD_ROSTER_UPDATE", ScanGuild)
	ns:On("FRIENDLIST_UPDATE", ScanFriends)
	ns:On("PLAYER_TARGET_CHANGED", function() NoteUnit("target") end)
	ns:On("UPDATE_MOUSEOVER_UNIT", function() NoteUnit("mouseover") end)
	CH.ticker = C_Timer.NewTicker(0.2, ns.Timed("Chat tabs", Tick)) -- tab fade / flash / mouseover; 5x a second is plenty
end

function CH:Refresh()
	if not CH.active then return end
	CH.ResetMeasure()
	ApplyCVars()
	ApplyClassColors()
	CH.SetupAll()
	Tick()
end

ns:RegisterModule("Chat", CH)
