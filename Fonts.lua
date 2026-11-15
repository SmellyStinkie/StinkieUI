-- StinkieUI: puts the chosen font on Blizzard's own font objects, so tooltips, buff timers,
-- spec names, the character sheet, the damage meter, zone text and the settings panel follow it.
-- Sizes and outlines are kept; only the font file changes.
local _, ns = ...

local GF = {}
ns.GlobalFont = GF

local original = {} -- font object name -> { path, size, flags }, so turning it off restores
local applied = false

-- PT Sans Narrow has Latin and Cyrillic glyphs only.
local CJK = { koKR = true, zhCN = true, zhTW = true }

local function ShouldSkip(name)
	return name:find("^StinkieUI") ~= nil
end

local function Each(fn)
	if not GetFonts then return end
	for _, name in ipairs(GetFonts()) do
		local obj = _G[name]
		if type(obj) == "table" and obj.GetFont and obj.SetFont and not ShouldSkip(name) then
			fn(name, obj)
		end
	end
end

-- Text that was seen in game keeping another font although its font object was changed: on the
-- Group Finder's Premade Groups page (the same page serves the PvP tab), the first category
-- button ("Questing", "Arenas"). That button is made when the game loads; the others are made
-- later and follow the font. The page's title and every category button get the font set on the
-- text itself.
local function PremadeGroupsText(out)
	local sel = _G.LFGListFrame and _G.LFGListFrame.CategorySelection
	if type(sel) ~= "table" then return end
	out[#out + 1] = sel.Label
	if type(sel.CategoryButtons) == "table" then
		for _, b in ipairs(sel.CategoryButtons) do out[#out + 1] = b.Label end
	end
end
local stringOriginal = {} -- the text -> { path, size, flags }

local function EachString(fn)
	local list = {}
	pcall(PremadeGroupsText, list)
	for _, s in ipairs(list) do
		if type(s) == "table" and s.GetFont and s.SetFont then fn(s) end
	end
end

function GF:Apply()
	if not ns.db.globalFont then
		if applied then GF:Restore() end
		return
	end
	if CJK[GetLocale()] then return end
	local path = ns.GetFontPath()
	if not ns.FontLoads(path) then return end
	Each(function(name, obj)
		local p, size, flags = obj:GetFont()
		if not size or size <= 0 then return end
		if not original[name] then original[name] = { p, size, flags } end
		if p ~= path then obj:SetFont(path, size, flags or "") end
	end)
	EachString(function(s)
		local p, size, flags = s:GetFont()
		if not size or size <= 0 then return end
		if not stringOriginal[s] then stringOriginal[s] = { p, size, flags } end
		if p ~= path then s:SetFont(path, size, flags or "") end
	end)
	applied = true
end

function GF:Restore()
	Each(function(name, obj)
		local o = original[name]
		if o and o[1] then obj:SetFont(o[1], o[2], o[3] or "") end
	end)
	EachString(function(s)
		local o = stringOriginal[s]
		if o and o[1] then s:SetFont(o[1], o[2], o[3] or "") end
	end)
	applied = false
end

-- Blizzard addons that load later (damage meter, talents, collections, ...) bring new font objects.
local pending = false
local function Queue()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = false
		GF:Apply()
	end)
end

local hooked = {}
local function HookShow(name)
	local frame = _G[name]
	if frame and not hooked[name] and frame.HookScript then
		hooked[name] = true
		frame:HookScript("OnShow", Queue)
	end
end

function GF:Init()
	GF:Apply()
	ns:On("ADDON_LOADED", function()
		Queue()
		HookShow("CharacterFrame")
		HookShow("InspectFrame")
		HookShow("PVEFrame")
	end)
	-- a cold login can refuse the font file for a few seconds; try again later
	ns:On("PLAYER_ENTERING_WORLD", function()
		Queue()
		C_Timer.After(2, Queue)
		C_Timer.After(6, Queue)
		C_Timer.After(15, Queue)
	end)
	HookShow("CharacterFrame")
	HookShow("PVEFrame")
end

function GF:Refresh()
	GF:Apply()
end

ns:RegisterModule("GlobalFont", GF)
