-- StinkieUI: Window Skins. Blizzard's other windows in the Character Sheet's flat look: frame art,
-- portrait and marble background hidden, a flat background with a 1px border, flat tabs.
-- Done once per window when it first opens (no ongoing cost). Only decoration is touched:
-- textures are made transparent and our own frames are added; Blizzard's code, buttons and
-- layout are left alone. Protected windows (bags, talents / spellbook, map / quest log) are not
-- skinned, and the Game Menu only gets its background.
local _, ns = ...

local SK = {}
ns.Skins = SK

local function cfg() return ns.db.skins end

-- key -> { frame name, addon that creates it (nil = always there), tab name pattern, background only }
SK.WINDOWS = {
	{ key = "friends", label = "Friends / Social", frame = "FriendsFrame", tabs = "FriendsFrameTab%d" },
	{ key = "groupFinder", label = "Group Finder and PvP", frame = "PVEFrame", tabs = "PVEFrameTab%d" },
	{ key = "adventure", label = "Adventure Guide", frame = "EncounterJournal", addon = "Blizzard_EncounterJournal" },
	{ key = "collections", label = "Warband Collections", frame = "CollectionsJournal", addon = "Blizzard_Collections", tabs = "CollectionsJournalTab%d" },
	{ key = "achievements", label = "Achievements", frame = "AchievementFrame", addon = "Blizzard_AchievementUI", tabs = "AchievementFrameTab%d" },
	{ key = "guild", label = "Guild and Communities", frame = "CommunitiesFrame", addon = "Blizzard_Communities" },
	{ key = "professions", label = "Professions", frame = "ProfessionsFrame", addon = "Blizzard_Professions" },
	{ key = "housing", label = "Housing Dashboard", frame = "HousingDashboardFrame", addon = "Blizzard_HousingDashboard" },
	{ key = "gameMenu", label = "Game Menu (background only)", frame = "GameMenuFrame", backgroundOnly = true },
}

local function Hide(region)
	if region and region.SetAlpha then region:SetAlpha(0) end
end

local function Strip(frame)
	if not (frame and frame.GetRegions) then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:IsObjectType("Texture") then r:SetAlpha(0) end
	end
end

local function Color()
	local ch = ns.db.character
	return ch.frameColor or { 0.05, 0.05, 0.06 }
end

local function Backdrop(frame, alpha)
	if not frame.SUISkin then
		local f = CreateFrame("Frame", nil, frame)
		f:SetAllPoints()
		f:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
		f.tex = f:CreateTexture(nil, "BACKGROUND", nil, -8)
		f.tex:SetAllPoints()
		ns.CreateBackdrop(f, 0)
		frame.SUISkin = f
	end
	local col = Color()
	frame.SUISkin.tex:SetColorTexture(col[1], col[2], col[3], alpha)
	frame.SUISkin:Show()
	return frame.SUISkin
end

-- tabs: flat fill, plum when selected (painted by the Character Sheet's tab hook for old-style
-- tabs, and here for tab-system tabs)
local function PaintTab(tab, selected)
	local f = tab and tab.SUIFlat
	if not f then return end
	if selected then
		local p = ns.BRAND.plum
		f.tex:SetColorTexture(p[1], p[2], p[3], 1)
	else
		local col = Color()
		f.tex:SetColorTexture(col[1], col[2], col[3], ns.db.character.tabAlpha or 0.9)
	end
end
SK.PaintTab = PaintTab

local function SkinTab(tab)
	if not tab or tab.SUIFlat then return end
	Strip(tab)
	for _, k in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do Hide(tab[k]) end
	local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
	if hl then hl:SetAlpha(0) end
	-- side tabs (WoW Forever's Collections) have no text: the icon is the tab
	local sideTab = tab.Icon and tab.SelectedTexture
	if sideTab then tab.Icon:SetAlpha(1) end
	local f = CreateFrame("Frame", nil, tab)
	f:SetPoint("TOPLEFT", 3, -2)
	f:SetPoint("BOTTOMRIGHT", -3, 4)
	f:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
	f.tex = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	f.tex:SetAllPoints()
	ns.CreateBackdrop(f, 0)
	tab.SUIFlat = f
	-- tab-system tabs (Professions, Housing) report selection through SetTabSelected
	if tab.SetTabSelected then hooksecurefunc(tab, "SetTabSelected", function(self, selected) PaintTab(self, selected) end) end
	-- side tabs report it through SetChecked
	if sideTab and tab.SetChecked then hooksecurefunc(tab, "SetChecked", function(self, checked) PaintTab(self, checked) end) end
	local selected = tab.isSelected or (tab.GetID and PanelTemplates_GetSelectedTab and tab:GetParent()
		and PanelTemplates_GetSelectedTab(tab:GetParent()) == tab:GetID())
	PaintTab(tab, selected and true or false)
end

---------------------------------------------------------------------------
-- Title bars: a slightly darker band across the top with a thin accent line under it, and the
-- window name in the Stinkie UI font, centered on the whole window (Blizzard leaves room for the
-- portrait, which is hidden here, so its title sat off center).
---------------------------------------------------------------------------
local BAND_H = 24

local function TitleBand(frame, height, top)
	local skin = frame.SUISkin
	if not skin then return end
	if not skin.band then
		skin.band = skin:CreateTexture(nil, "BACKGROUND", nil, -7)
		skin.line = skin:CreateTexture(nil, "BACKGROUND", nil, -6)
	end
	skin.band:ClearAllPoints()
	skin.band:SetPoint("TOPLEFT", skin, "TOPLEFT", 0, top or 0)
	skin.band:SetPoint("TOPRIGHT", skin, "TOPRIGHT", 0, top or 0)
	skin.band:SetHeight(height)
	skin.band:SetColorTexture(0, 0, 0, 0.35)
	skin.line:ClearAllPoints()
	skin.line:SetPoint("TOPLEFT", skin.band, "BOTTOMLEFT")
	skin.line:SetPoint("TOPRIGHT", skin.band, "BOTTOMRIGHT")
	skin.line:SetHeight(1)
	skin.line:SetColorTexture(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 0.6)
end

local function StyleTitle(fs, size)
	if not fs then return end
	ns.SetFont(fs, size or 14, "OUTLINE")
	local c = ns.BRAND.cream
	fs:SetTextColor(c[1], c[2], c[3])
	fs:SetShadowOffset(0, 0)
end

local function SkinTitle(frame)
	local tc = frame.TitleContainer
	if not tc then return end
	tc:ClearAllPoints()
	tc:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -1)
	tc:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -1)
	tc:SetHeight(20)
	StyleTitle(tc.TitleText, 14)
	TitleBand(frame, BAND_H)
end

-- Achievements: its name and points sit on a big banner above the window. The banner art is
-- gone, so the window's background reaches up to make a two-line title bar, centered:
-- the name on top ("Warband Achievement Points"), the points and shield under it.
-- On the Statistics tab it just says "Statistics" (points don't apply there).
local ACH_RISE, ACH_BAND = 40, 44

local function AchievementTitleForTab()
	local frame = _G.AchievementFrame
	local h = frame and frame.Header
	if not (h and h.Title and frame.SUISkin) then return end
	local tab = PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(frame)
	local stats = tab == 3
	if stats then
		h.SUIBlizzTitle = h.SUIBlizzTitle or h.Title:GetText()
		h.Title:SetText(STATISTICS or "Statistics")
	elseif h.SUIStatsShown and h.SUIBlizzTitle then
		h.Title:SetText(h.SUIBlizzTitle)
	end
	if not stats then h.SUIBlizzTitle = nil end
	h.SUIStatsShown = stats
	if h.Points then h.Points:SetShown(not stats) end
	if h.Shield then h.Shield:SetShown(not stats) end
end
SK.AchievementTitleForTab = AchievementTitleForTab

local function SkinAchievementHeader(frame)
	local h = frame.Header
	if not h then return end
	for _, k in ipairs({ "Left", "Right", "PointBorder", "RightDDLInset" }) do Hide(h[k]) end
	if h.Shield then h.Shield:SetAlpha(1) end
	local skin = frame.SUISkin
	skin:ClearAllPoints()
	skin:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, ACH_RISE)
	skin:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	if h.Title then
		h.Title:ClearAllPoints()
		h.Title:SetPoint("TOP", skin, "TOP", 0, -6)
		h.Title:SetWidth(420)
		h.Title:SetJustifyH("CENTER")
		if h.Title.SetMaxLines then h.Title:SetMaxLines(1) end
		StyleTitle(h.Title, 15)
	end
	if h.Points then
		h.Points:ClearAllPoints()
		-- centered under the name; the shield hangs off its right side, so shift left by half of it
		h.Points:SetPoint("TOP", h.Title or skin, "BOTTOM", -11, -4)
		StyleTitle(h.Points, 14)
	end
	TitleBand(frame, ACH_BAND)
	if not SK.achHooked then
		SK.achHooked = true
		if AchievementFrame_UpdateTabs then hooksecurefunc("AchievementFrame_UpdateTabs", function() AchievementTitleForTab() end) end
		if AchievementFrame_RefreshView then hooksecurefunc("AchievementFrame_RefreshView", function() AchievementTitleForTab() end) end
	end
	AchievementTitleForTab()
end

function SK.SkinWindow(def)
	local frame = _G[def.frame]
	if not frame then return false end
	local c = cfg()
	if def.backgroundOnly then
		Hide(frame.Border)
		Hide(frame.NineSlice)
		Backdrop(frame, c.alpha)
		-- Game Menu: the header plaque becomes a flat band with the name
		local hd = frame.Header
		if hd then
			Strip(hd)
			for _, child in ipairs({ hd:GetRegions() }) do
				if child:IsObjectType("FontString") then StyleTitle(child, 14) end
			end
			if hd.Text then StyleTitle(hd.Text, 14) end
		end
		frame.SUISkinned = true
		return true
	end
	Hide(frame.NineSlice)
	Hide(frame.Bg)
	Hide(frame.TopTileStreaks)
	Hide(frame.Background)
	if frame.PortraitContainer then frame.PortraitContainer:SetAlpha(0) end
	if frame.portrait then frame.portrait:SetAlpha(0) end
	if frame.SetBackdrop and frame.backdropInfo then pcall(frame.SetBackdrop, frame, nil) end
	Strip(frame)
	if frame.Header then Strip(frame.Header) end
	for _, key in ipairs({ "Inset", "LeftInset", "RightInset" }) do
		local inset = frame[key]
		if inset then Hide(inset.NineSlice); Hide(inset.Bg); Strip(inset) end
	end
	Backdrop(frame, c.alpha)
	if def.frame == "AchievementFrame" then
		SkinAchievementHeader(frame)
	else
		SkinTitle(frame)
	end
	if def.tabs then
		for i = 1, 12 do
			local tab = _G[def.tabs:format(i)]
			if not tab then break end
			SkinTab(tab)
		end
	end
	if frame.TabSystem and frame.TabSystem.tabs then
		for _, tab in ipairs(frame.TabSystem.tabs) do SkinTab(tab) end
	end
	frame.SUISkinned = true
	return true
end

-- skin when the window first opens (and colors again on later opens)
local function Hook(def)
	local frame = _G[def.frame]
	if not frame or frame.SUISkinHook then return end
	frame.SUISkinHook = true
	frame:HookScript("OnShow", function()
		local c = cfg()
		if not (c.enabled and c[def.key]) then return end
		local ok, err = pcall(SK.SkinWindow, def)
		if not ok then ns.Error(err) end
	end)
	if frame:IsShown() and cfg().enabled and cfg()[def.key] then pcall(SK.SkinWindow, def) end
end

function SK:Init()
	if not cfg().enabled then return end
	for _, def in ipairs(SK.WINDOWS) do Hook(def) end
	-- windows from load-on-demand addons appear later
	ns:On("ADDON_LOADED", function(_, name)
		for _, def in ipairs(SK.WINDOWS) do
			if def.addon == name or _G[def.frame] then Hook(def) end
		end
	end)
end

function SK:Refresh()
	local c = cfg()
	for _, def in ipairs(SK.WINDOWS) do
		local frame = _G[def.frame]
		if frame and frame.SUISkin then
			local col = Color()
			frame.SUISkin.tex:SetColorTexture(col[1], col[2], col[3], c.alpha)
			frame.SUISkin:SetShown(c.enabled and c[def.key] and true or false)
		end
	end
end

ns:RegisterModule("Skins", SK)
