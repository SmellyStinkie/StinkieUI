-- StinkieUI: flat look for Blizzard's swing timers (melee, off-hand, ranged). Restyles Blizzard's
-- own bars, so swing tracking, range checks, size and position (Edit Mode) stay Blizzard's.
-- Clients without these bars simply have nothing to restyle.
local _, ns = ...

local ST = {}
ns.SwingTimers = ST

ST.BARS = {
	{ "SwingTimerMainHandFrame", "mainColor" },
	{ "SwingTimerOffHandFrame", "offColor" },
	{ "SwingTimerRangedFrame", "rangedColor" },
}

local function cfg() return ns.db.swingTimers end

-- Blizzard turns the text white or red whenever range changes. Red stays (out of range); white
-- becomes our color.
local function ColorText(f)
	if f:IsOutOfRange() then return end
	local c = cfg().textStyle.color
	local bar = f.StatusBar
	bar.TypeLabel:SetTextColor(c[1], c[2], c[3])
	bar.TimeLabel:SetTextColor(c[1], c[2], c[3])
end

-- First time only. Background and Border are repainted, not faded: Blizzard sets their alpha itself
-- to dim the bar out of range, which would bring faded art straight back.
local function FirstSkin(f)
	local col = ns.db.colors.background
	f.Background:SetColorTexture(col[1], col[2], col[3], col[4])
	f.Border:SetColorTexture(0, 0, 0, 0)
	ns.CreateBackdrop(f, 0)
	f.StatusBar.TypeLabelShadow:SetAlpha(0)
	f.StatusBar.Pip:SetColorTexture(1, 1, 1, 0.9)
	hooksecurefunc(f, "ApplyRangePresentation", ColorText)
end

local function Skin(f, colorKey)
	if not (f and f.StatusBar) then return end
	if not f.SUISwingSkin then
		f.SUISwingSkin = true
		FirstSkin(f)
	end
	local c = cfg()
	local bar = f.StatusBar
	local px = ns.Pixel(f)
	ns.UpdateBackdrop(f)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", px, -px)
	bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -px, px)
	bar:SetStatusBarTexture(ns.TEXTURE)
	local col = c[colorKey]
	bar:SetStatusBarColor(col[1], col[2], col[3])
	-- the pip is the bright leading edge of the fill: a thin line, the height of the bar
	local fill, pip = bar:GetStatusBarTexture(), bar.Pip
	pip:ClearAllPoints()
	pip:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
	pip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	pip:SetWidth(px * 2)
	ns.ApplyText(bar.TypeLabel, c.textStyle)
	ns.ApplyText(bar.TimeLabel, c.textStyle)
	bar.TypeLabel:SetAlpha(c.showLabel and 1 or 0)
	bar.TimeLabel:SetAlpha(c.showTime and 1 or 0)
	ColorText(f)
end

function ST.SkinAll()
	if not cfg().enabled then return end
	for _, def in ipairs(ST.BARS) do Skin(_G[def[1]], def[2]) end
end

function ST:Init()
	ns:RunOOC(ST.SkinAll)
	-- Blizzard's addon may load after ours
	ns:On("ADDON_LOADED", function(_, name)
		if name == "Blizzard_SwingTimer" then ns:RunOOC(ST.SkinAll) end
	end)
end

function ST:Refresh()
	ST.SkinAll()
end

ns:RegisterModule("SwingTimers", ST)
