-- StinkieUI: action bar skin. Restyles Blizzard's own bars (layout, size and position stay in
-- Edit Mode), so keybinds, paging, vehicle bars and secure behaviour are untouched.
-- Look matches the Cooldown Manager skin: zoomed icon, 1px black edge, square swipe.
local _, ns = ...

local AB = {}
ns.ActionBars = AB

AB.BARS = {
	{ "MainActionBar", "Action Bar 1" },
	{ "MultiBarBottomLeft", "Action Bar 2" },
	{ "MultiBarBottomRight", "Action Bar 3" },
	{ "MultiBarRight", "Action Bar 4" },
	{ "MultiBarLeft", "Action Bar 5" },
	{ "MultiBar5", "Action Bar 6" },
	{ "MultiBar6", "Action Bar 7" },
	{ "MultiBar7", "Action Bar 8" },
	{ "StanceBar", "Stance Bar" },
	{ "PetActionBar", "Pet Bar" },
	{ "BagsBar", "Bag Bar", true },             -- fade only, not restyled
	{ "MicroMenuContainer", "Menu Icons", true },
}

local skinned = setmetatable({}, { __mode = "k" })

local function GetBar(name)
	local bar = _G[name]
	if not bar and name == "MainActionBar" then bar = _G.MainMenuBar end
	return bar
end

local function Hide(region)
	if region then region:SetAlpha(0) end
end

-- Blizzard re-applies its frame atlases whenever the bar layout changes; this re-strips them.
local function StripArt(b)
	Hide(b.NormalTexture or b:GetNormalTexture())
	Hide(b.SlotArt)
	Hide(b.SlotBackground)
	Hide(b.Border)
	Hide(b.NewActionTexture)
	local pushed = b:GetPushedTexture()
	if pushed then
		pushed:SetColorTexture(1, 1, 1, 0.25)
		pushed:ClearAllPoints()
		pushed:SetAllPoints(b)
	end
end

local function StyleText(b)
	local cfg = ns.db.actionBars
	if b.HotKey then
		local st = cfg.hotkeyStyle
		ns.ApplyText(b.HotKey, st)
		b.HotKey:ClearAllPoints()
		b.HotKey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
		b.HotKey:SetAlpha(cfg.hotkeys and 1 or 0)
	end
	if b.Count then
		ns.ApplyText(b.Count, cfg.countStyle)
		b.Count:ClearAllPoints()
		b.Count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
	end
	if b.Name then
		ns.ApplyText(b.Name, cfg.macroStyle)
		b.Name:ClearAllPoints()
		b.Name:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
		b.Name:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
		b.Name:SetAlpha(cfg.macroText and 1 or 0)
	end
end

function AB.SkinButton(b)
	if not b then return end
	local icon = b.icon or b.Icon
	if not skinned[b] then
		skinned[b] = true
		if icon and b.IconMask then
			icon:RemoveMaskTexture(b.IconMask)
			b.IconMask:Hide()
		end
		if icon then
			icon:ClearAllPoints()
			icon:SetAllPoints(b)
		end
		-- hover, checked (active stance / pet mode) and flash are outlines, never fills,
		-- so they can't darken or hide the icon
		local hl = b:GetHighlightTexture()
		if hl then
			hl:SetTexture(ns.MEDIA.edge)
			hl:SetVertexColor(1, 1, 1, 0.6)
			hl:SetTexCoord(0, 1, 0, 1)
			hl:ClearAllPoints()
			hl:SetAllPoints(b)
		end
		local checked = b.GetCheckedTexture and b:GetCheckedTexture()
		if checked then
			checked:SetTexture(ns.MEDIA.edge)
			checked:SetVertexColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 1)
			checked:SetTexCoord(0, 1, 0, 1)
			checked:ClearAllPoints()
			checked:SetAllPoints(b)
		end
		if b.SpellHighlightTexture then
			b.SpellHighlightTexture:ClearAllPoints()
			b.SpellHighlightTexture:SetAllPoints(b)
		end
		if b.Flash then
			b.Flash:SetTexture(ns.MEDIA.edge)
			b.Flash:SetVertexColor(1, 0.2, 0.2, 1)
			b.Flash:SetTexCoord(0, 1, 0, 1)
			b.Flash:ClearAllPoints()
			b.Flash:SetAllPoints(b)
		end
		-- pet buttons: the autocast swirl is sized for Blizzard's frame; fit it to the icon
		if b.AutoCastOverlay then
			b.AutoCastOverlay:ClearAllPoints()
			b.AutoCastOverlay:SetAllPoints(b)
		end
		for _, cd in ipairs({ b.cooldown, b.chargeCooldown, b.lossOfControlCooldown }) do
			if cd then
				cd:ClearAllPoints()
				cd:SetAllPoints(b)
				if cd.SetSwipeTexture then cd:SetSwipeTexture(ns.TEXTURE) end
			end
		end
		ns.IconBorder(b)
		if b.UpdateButtonArt then
			hooksecurefunc(b, "UpdateButtonArt", StripArt)
		end
	end
	if icon then ns.ZoomIcon(icon) end
	if b.cooldown and b.cooldown.SetCountdownFont then
		b.cooldown:SetCountdownFont(ns.GetCountdownFont(math.max(10, (b:GetWidth() or 36) * 0.4)))
	end
	StripArt(b)
	StyleText(b)
end

local function StripBarArt(bar)
	if not ns.db.actionBars.hideArt then return end
	Hide(bar.BorderArt)
	Hide(bar.EndCaps)
	Hide(bar.ActionBarPageNumber)
	Hide(bar.Background)
end

function AB.SkinBar(bar)
	if not bar then return end
	StripBarArt(bar)
	for _, b in ipairs(bar.actionButtons or {}) do AB.SkinButton(b) end
end

local function SkinAll()
	for _, def in ipairs(AB.BARS) do
		if not def[3] then AB.SkinBar(GetBar(def[1])) end
	end
end

---------------------------------------------------------------------------
-- Mouseover fade. SetAlpha is allowed on secure frames in combat, so this works everywhere.
---------------------------------------------------------------------------
local function BarHovered(bar)
	if bar:IsMouseOver() then return true end
	-- keep the bar up while one of its flyouts is open or something is being dragged onto it
	local flyout = _G.SpellFlyout
	if flyout and flyout:IsShown() then
		local parent = flyout:GetParent()
		if parent and parent.bar == bar then return true end
	end
	if GetCursorInfo() then return true end
	return false
end

local function UpdateFade()
	local cfg = ns.db.actionBars
	local editing = EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive()
	for _, def in ipairs(AB.BARS) do
		local bar = GetBar(def[1])
		if bar then
			local alpha = 1
			if cfg.mouseover[def[1]] and not editing and not ns.unlocked and not BarHovered(bar) then
				alpha = cfg.fadeAlpha or 0
			end
			if bar:GetAlpha() ~= alpha then bar:SetAlpha(alpha) end
		end
	end
end

function AB:Init()
	if not ns.db.actionBars.enabled then return end
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		for _, other in ipairs({ "Bartender4", "Dominos", "ElvUI" }) do
			if C_AddOns.IsAddOnLoaded(other) then
				ns:Print("Action bar skin is off because " .. other .. " is loaded.")
				return
			end
		end
	end
	AB.active = true
	SkinAll()
	-- bars and buttons Blizzard builds or re-lays out later
	for _, def in ipairs(AB.BARS) do
		local bar = not def[3] and GetBar(def[1])
		if bar and bar.UpdateGridLayout then
			hooksecurefunc(bar, "UpdateGridLayout", function(self) AB.SkinBar(self) end)
		end
		if bar and bar.UpdateEndCaps then
			hooksecurefunc(bar, "UpdateEndCaps", StripBarArt)
		end
	end
	ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(0, function() ns:RunOOC(SkinAll) end) end)
	ns:On("UPDATE_BINDINGS", function() C_Timer.After(0, function() ns:RunOOC(SkinAll) end) end)
	AB.ticker = C_Timer.NewTicker(0.1, UpdateFade)
end

function AB:Refresh()
	if not AB.active then return end
	SkinAll()
	UpdateFade()
end

ns:RegisterModule("ActionBars", AB)
