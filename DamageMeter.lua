-- StinkieUI: restyles Blizzard's built-in damage meter (Midnight) to match the rest of the UI:
-- flat bars with a 1px edge, flat header and background, our font, zoomed icons.
-- Size, bar height, spacing, class colors and which meters show stay in Edit Mode.
local _, ns = ...

local DM = {}
ns.DamageMeterSkin = DM

local function cfg() return ns.db.damageMeter end

local function BarTexture()
	local t = cfg().texture
	if t == "flat" then return ns.TEXTURE end
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM then
		local path = LSM:Fetch("statusbar", t, true)
		if path then return path end
	end
	return ns.TEXTURE
end

local entryDone = setmetatable({}, { __mode = "k" })
local windowDone = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
-- Blizzard re-applies its atlases whenever a bar's style changes; this puts ours back.
local function StyleEntry(frame)
	local c = cfg()
	local bar = frame.StatusBar
	if not bar then return end
	local tex = bar:GetStatusBarTexture()
	-- keep Blizzard's color (class color etc.) across the texture swap
	local r, g, b = 1, 1, 1
	if tex then r, g, b = tex:GetVertexColor() end
	bar:SetStatusBarTexture(BarTexture())
	tex = bar:GetStatusBarTexture()
	if tex then
		tex:SetHorizTile(false)
		tex:SetVertexColor(r, g, b, 1)
	end
	if bar.Background then
		bar.Background:SetColorTexture(0, 0, 0, c.barBackgroundAlpha)
		bar.Background:ClearAllPoints()
		bar.Background:SetAllPoints(bar)
	end
	if bar.BackgroundEdge then bar.BackgroundEdge:SetAlpha(0) end
	if bar.SUIBorder then bar.SUIBorder:SetShown(c.barBorder) end
	if bar.Name then ns.ApplyText(bar.Name, c.nameStyle) end
	if bar.Value then ns.ApplyText(bar.Value, c.valueStyle) end
	local icon = frame.Icon and frame.Icon.Icon
	if icon then
		ns.ZoomIcon(icon)
		ns.IconBorder(frame.Icon)
	end
end

local function SkinEntry(frame)
	if not frame or not frame.StatusBar then return end
	if not entryDone[frame] then
		entryDone[frame] = true
		local border = CreateFrame("Frame", nil, frame.StatusBar)
		border:SetAllPoints()
		ns.CreateBackdrop(border, 0) -- 1px edges, outside the bar
		frame.StatusBar.SUIBorder = border
		if frame.UpdateStyle then hooksecurefunc(frame, "UpdateStyle", StyleEntry) end
	end
	StyleEntry(frame)
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
local function Flat(tex, color, alpha)
	if not tex then return end
	tex:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end

local function StyleWindow(win)
	local c = cfg()
	Flat(win.Header, c.headerColor, c.headerColor[4] or 1)
	local mc = win.MinimizeContainer
	if mc and mc.Background then
		-- Edit Mode's "background opacity" still sets this texture's alpha
		Flat(mc.Background, c.backgroundColor, 1)
	end
	if mc and mc.ScrollBar then mc.ScrollBar:SetShown(not c.hideScrollBar) end
	if mc and mc.ResizeButton then
		-- keep Blizzard's resize handle usable but quiet
		mc.ResizeButton:SetAlpha(0)
	end
	for _, fs in ipairs({ win.SessionTimer }) do
		if fs then ns.ApplyText(fs, c.titleStyle) end
	end
	local function dd(key, textKey)
		local d = win[key]
		local fs = d and d[textKey]
		if fs then ns.ApplyText(fs, c.titleStyle) end
	end
	dd("SessionDropdown", "SessionName")
	dd("DamageMeterTypeDropdown", "TypeName")
	if mc and mc.NotActive then ns.ApplyText(mc.NotActive, c.titleStyle) end
	if win.SUIEdge then win.SUIEdge:SetShown(c.windowBorder) end

	-- breakdown window (click a bar)
	local src = mc and mc.SourceWindow
	if src and src.Background then
		Flat(src.Background, c.backgroundColor, 0.95)
		if not src.SUIEdge then
			src.SUIEdge = CreateFrame("Frame", nil, src)
			src.SUIEdge:SetAllPoints()
			ns.CreateBackdrop(src.SUIEdge, 0)
		end
	end

	if win.ForEachEntryFrame then pcall(win.ForEachEntryFrame, win, SkinEntry) end
	if mc and mc.LocalPlayerEntry then SkinEntry(mc.LocalPlayerEntry) end
end

local function SkinWindow(win)
	if not win then return end
	if not windowDone[win] then
		windowDone[win] = true
		win.SUIEdge = CreateFrame("Frame", nil, win)
		win.SUIEdge:SetAllPoints()
		ns.CreateBackdrop(win.SUIEdge, 0)
		if win.InitEntry then hooksecurefunc(win, "InitEntry", function(_, frame) SkinEntry(frame) end) end
		local src = win.MinimizeContainer and win.MinimizeContainer.SourceWindow
		if src and src.InitEntry then hooksecurefunc(src, "InitEntry", function(_, frame) SkinEntry(frame) end) end
		if win.RefreshLayout then hooksecurefunc(win, "RefreshLayout", function(self) StyleWindow(self) end) end
	end
	StyleWindow(win)
end

function DM:SkinAll()
	if not DM.active then return end
	local meter = _G.DamageMeter
	if meter and meter.ForEachSessionWindow then
		pcall(meter.ForEachSessionWindow, meter, SkinWindow)
	end
	for i = 1, 5 do
		local win = _G["DamageMeterSessionWindow" .. i]
		if win then SkinWindow(win) end
	end
end

local hooked = false
local function Hook()
	local meter = _G.DamageMeter
	if hooked or not meter then return end
	hooked = true
	if meter.SetupSessionWindow then
		hooksecurefunc(meter, "SetupSessionWindow", function() DM:SkinAll() end)
	end
	DM:SkinAll()
end

function DM:Init()
	if not cfg().enabled then return end
	DM.active = true
	Hook()
	ns:On("ADDON_LOADED", function(_, name)
		if name == "Blizzard_DamageMeter" then Hook() end
	end)
	ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() DM:SkinAll() end) end)
end

function DM:Refresh()
	DM:SkinAll()
end

ns:RegisterModule("DamageMeterSkin", DM)
