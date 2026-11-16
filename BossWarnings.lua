-- StinkieUI: Boss Warnings. The game's own boss warnings (Midnight's text warnings in dungeons and
-- raids, three frames: critical, medium and minor), switched on and off from here and given your
-- font, outline and text size. The switches are the game's own settings, so they and the game's
-- options always agree. Where the warnings sit, their overall size, icons and transparency stay
-- in the game's Edit Mode.
--
-- Hooks only, and only widget calls on Blizzard's text. Nothing is written into its frames and
-- none of its methods are called: a warning's text can be secret, and Blizzard's code may only
-- work on it untainted. What this needs to remember lives in its own tables.
local _, ns = ...

local BW = {}
ns.BossWarnings = BW

local issecret = ns.issecret
local function cfg() return ns.db.bossWarnings end

-- Blizzard's frame, the setting that holds its text size
BW.FRAMES = {
	{ "CriticalEncounterWarnings", "critical" },
	{ "MediumEncounterWarnings", "medium" },
	{ "MinorEncounterWarnings", "minor" },
}
BW.MASTER = "combatWarningsEnabled"        -- Blizzard's "Enable Boss Warnings": warnings and timeline both need it
BW.TEXT = "encounterWarningsEnabled"       -- the text warnings
BW.LEVEL = "encounterWarningsLevel"        -- the least important warning that still shows
BW.MINE = "encounterWarningsHideIfNotTargetingPlayer"
BW.TIMELINE = "encounterTimelineEnabled"
BW.LEVELS = { { "minor", "Low" }, { "medium", "Medium" }, { "critical", "High" } } -- our key, Enum.EncounterEventSeverity's

local function Get(name)
	local ok, v = pcall(C_CVar.GetCVar, name)
	if ok and v ~= nil and not issecret(v) then return v end
	return nil
end

local function Set(name, value)
	if Get(name) == nil then return false end
	return (pcall(C_CVar.SetCVar, name, value))
end

-- does this game version have the setting?
function BW.Has(name) return Get(name) ~= nil end
function BW.Available() return BW.Has(BW.TEXT) end

local function On(name) return Get(name) == "1" end

function BW.Enabled() return On(BW.MASTER) and On(BW.TEXT) end

function BW.SetEnabled(on)
	if on then Set(BW.MASTER, "1") end -- left alone when turning off: the timeline uses it too
	Set(BW.TEXT, on and "1" or "0")
end

function BW.Timeline() return On(BW.MASTER) and On(BW.TIMELINE) end

function BW.SetTimeline(on)
	if on then Set(BW.MASTER, "1") end
	Set(BW.TIMELINE, on and "1" or "0")
end

function BW.OnlyMine() return On(BW.MINE) end
function BW.SetOnlyMine(on) Set(BW.MINE, on and "1" or "0") end

local function LevelValue(i)
	local e = Enum and Enum.EncounterEventSeverity
	local v = e and e[BW.LEVELS[i][2]]
	return type(v) == "number" and v or (i - 1)
end

function BW.Level()
	local v = tonumber(Get(BW.LEVEL))
	for i, level in ipairs(BW.LEVELS) do
		if v == LevelValue(i) then return level[1] end
	end
	return BW.LEVELS[1][1]
end

function BW.SetLevel(key)
	for i, level in ipairs(BW.LEVELS) do
		if level[1] == key then Set(BW.LEVEL, tostring(LevelValue(i))) end
	end
end

---------------------------------------------------------------------------
-- The look. Blizzard gives the text its own font each time a warning starts; right after that the
-- text gets your font, outline and size. The game's font is remembered per text, so a setting put
-- back to "the game's" really goes back.
---------------------------------------------------------------------------
local base = setmetatable({}, { __mode = "k" })   -- text -> { path, size, flags } as the game set it
local keyOf = setmetatable({}, { __mode = "k" })  -- text -> "critical" | "medium" | "minor"

function BW.Style(fs)
	local key, b = keyOf[fs], base[fs]
	if not (key and b) then return end
	local c = cfg()
	local path, size, flags = b[1], b[2], b[3]
	if c.font then
		path = ns.GetFontPath()
		flags = ns.OutlineFlags(c.outline) or ""
	end
	local want = tonumber(c[key]) or 0
	if want > 0 then size = want end
	fs:SetFont(path, size, flags)
	if c.noCut then BW.Fit(fs, tonumber(c.wrapWidth) or 0) end
end

-- The game gives a warning's text a fixed box (two lines at most) and shrinks long text to fit,
-- down to a smallest size; past that the text is cut off. Here the text keeps its size and gets
-- the room it needs: on one line while it fits in the widest line allowed, wrapped onto as many
-- lines as it takes when it doesn't. A text whose width the game hides is left as the game set it.
function BW.Fit(fs, widest)
	if not (fs.SetTextScale and fs.SetWidth and fs.SetHeight) then return false end
	local measure = fs.GetUnboundedStringWidth or fs.GetStringWidth
	if not measure then return false end
	fs:SetTextScale(1)
	local width = measure(fs)
	if issecret(width) or type(width) ~= "number" then return false end
	if widest > 0 and width > widest then
		fs:SetWidth(widest) -- wraps
	else
		fs:SetWidth(0)      -- as wide as the text
	end
	fs:SetHeight(0)         -- as tall as its lines
	return true
end

-- after Blizzard's own setup of a warning's text
function BW.OnTextInit(fs)
	local path, size, flags = fs:GetFont()
	if not path or issecret(path) or issecret(size) or issecret(flags) then return end
	base[fs] = { path, size, flags }
	BW.Style(fs)
end

function BW.Hook()
	for _, entry in ipairs(BW.FRAMES) do
		local frame = _G[entry[1]]
		local fs = frame and frame.View and frame.View.Text
		if fs and not keyOf[fs] and type(fs.Init) == "function" and fs.GetFont and fs.SetFont then
			keyOf[fs] = entry[2]
			hooksecurefunc(fs, "Init", function(self)
				local ok, err = pcall(BW.OnTextInit, self)
				if not ok then ns.Error(err) end
			end)
		end
	end
end

function BW:Init()
	BW.Hook()
	ns:On("ADDON_LOADED", function(_, name)
		if name == "Blizzard_EncounterWarnings" then BW.Hook() end
	end)
end

-- a warning on screen (or Edit Mode's sample) takes a changed setting straight away
function BW:Refresh()
	for fs in pairs(base) do
		local ok, err = pcall(BW.Style, fs)
		if not ok then ns.Error(err) end
	end
end

ns:RegisterModule("BossWarnings", BW)
