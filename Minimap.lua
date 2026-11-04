-- StinkieUI: minimap styling. Square or round, flat border, fonts for the zone name, clock and
-- coordinates, button hiding, and auto-hide in arena / battlegrounds / Mythic+.
-- Position and size stay in Edit Mode.
local _, ns = ...

local MM = {}
ns.MinimapSkin = MM

local function cfg() return ns.db.minimap end

local SQUARE_MASK = [[Interface\Buttons\WHITE8X8]]
local ROUND_MASK = [[Textures\MinimapMask]]

-- Buttons that "Hide buttons" covers. The mail / crafting-order indicator stays, and so does the
-- Omnium Folio while its own option is on.
local function BlizzardButtons()
	local list = {}
	local cluster = MinimapCluster
	local function add(f) if f then table.insert(list, f) end end
	add(cluster and cluster.Tracking)
	add(_G.AddonCompartmentFrame)
	if not cfg().folio then add(_G.ExpansionLandingPageMinimapButton) end
	add(Minimap and Minimap.ZoomIn)
	add(Minimap and Minimap.ZoomOut)
	return list
end

-- Addon buttons made with LibDBIcon (the usual minimap buttons) are named LibDBIcon10_<addon>.
local function AddonButtons()
	local list = {}
	for _, child in ipairs({ Minimap:GetChildren() }) do
		local name = child.GetName and child:GetName()
		if name and name:find("^LibDBIcon10_") then table.insert(list, child) end
	end
	return list
end

local function SetButtonVisible(f, visible)
	f:SetAlpha(visible and 1 or 0)
	if not InCombatLockdown() and f.EnableMouse and not (f.IsProtected and f:IsProtected()) then
		f:EnableMouse(visible)
	end
end

function MM:UpdateButtons()
	local c = cfg()
	local mode = c.buttons or "show"
	local over = mode == "mouseover" and MinimapCluster and MinimapCluster:IsMouseOver()
	local visible = mode == "show" or over
	for _, f in ipairs(BlizzardButtons()) do
		-- the zoom buttons manage their own hover visibility; just don't force them on
		if f == Minimap.ZoomIn or f == Minimap.ZoomOut then
			if not visible then f:SetAlpha(0) else f:SetAlpha(1) end
		else
			SetButtonVisible(f, visible)
		end
	end
	for _, f in ipairs(AddonButtons()) do SetButtonVisible(f, visible) end
	-- the Omnium Folio follows its own option, not the button mode
	if c.folio and _G.ExpansionLandingPageMinimapButton then SetButtonVisible(_G.ExpansionLandingPageMinimapButton, true) end
	if _G.GameTimeFrame then
		_G.GameTimeFrame:SetAlpha(c.calendar and 1 or 0)
		_G.GameTimeFrame:SetScale(c.calendarScale or 1)
	end
end

---------------------------------------------------------------------------
-- Square layout: zone bar + calendar centered right on top of the map (no gap), mail and the
-- Omnium Folio (expansion button) tucked into corners. Round hands everything back to Blizzard.
---------------------------------------------------------------------------
local CORNER = {
	TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 },
}

local function HeaderUnderneath()
	local top = MinimapCluster and MinimapCluster.BorderTop
	if MM.headerUnder ~= nil then return MM.headerUnder end
	if not top or not top.GetPoint then return false end
	local point, rel = top:GetPoint(1)
	-- Blizzard anchors it to the cluster's bottom when the header is underneath
	return point == "BOTTOM" and rel == MinimapCluster
end

function MM.PinSquare()
	if not MM.active or MM.pinning then return end
	local c = cfg()
	local square = c.shape == "SQUARE"
	local cluster = MinimapCluster
	if not cluster then return end
	MM.pinning = true
	local top = cluster.BorderTop
	local cal = _G.GameTimeFrame
	if square and top then
		-- the calendar sits to the right of the bar; shift so bar + calendar are centered together
		local calW = (cal and c.calendar and (cal:GetWidth() * (c.calendarScale or 1) + 1)) or 0
		local dx = -calW / 2
		local gap = (c.headerGap or 2) + (c.border and (c.borderSize or 1) or 0)
		top:ClearAllPoints()
		if HeaderUnderneath() then
			top:SetPoint("TOP", Minimap, "BOTTOM", dx, -gap)
		else
			top:SetPoint("BOTTOM", Minimap, "TOP", dx, gap)
		end
		MM.pinnedHeader = true
	elseif MM.pinnedHeader and top then
		MM.pinnedHeader = nil
		if ResetFramePoints then ResetFramePoints(top) end
		if cluster.SetHeaderUnderneath and MM.headerUnder then pcall(cluster.SetHeaderUnderneath, cluster, true) end
	end
	-- mail / crafting-order indicator
	local ind = cluster.IndicatorFrame
	if ind then
		if square and c.mailCorner ~= "DEFAULT" then
			local corner = c.mailCorner or "TOPRIGHT"
			local o = CORNER[corner] or CORNER.TOPRIGHT
			ind:ClearAllPoints()
			ind:SetPoint(corner, Minimap, corner, o[1] * 3, o[2] * 3)
			ind:SetFrameLevel(Minimap:GetFrameLevel() + 6)
			MM.pinnedMail = true
		elseif MM.pinnedMail then
			MM.pinnedMail = nil
			ind:ClearAllPoints()
			if _G.MiniMapIndicatorFrame_UpdatePosition then pcall(_G.MiniMapIndicatorFrame_UpdatePosition) end
		end
	end
	-- Omnium Folio (Blizzard's expansion button)
	local folio = _G.ExpansionLandingPageMinimapButton
	if folio then
		if c.folio and square then
			-- The button's frame is much bigger than its art (room for glows), so its corner can't
			-- be used. Instead the icon's center goes just inside the map corner.
			local corner = c.folioCorner or "BOTTOMLEFT"
			local o = CORNER[corner] or CORNER.BOTTOMLEFT
			local scale = c.folioScale or 0.7
			folio:SetScale(scale)
			folio:ClearAllPoints()
			local inset = (c.folioInset or 14) -- screen pixels from the corner to the icon's center
			folio:SetPoint("CENTER", Minimap, corner, (o[1] * inset + (c.folioX or 0)) / scale, (o[2] * inset + (c.folioY or 0)) / scale)
			MM.pinnedFolio = true
		elseif MM.pinnedFolio then
			MM.pinnedFolio = nil
			folio:SetScale(1)
			if folio.UpdateIcon then pcall(folio.UpdateIcon, folio) end
		end
	end
	MM.pinning = nil
end

local function ApplyShape()
	local c = cfg()
	local square = c.shape == "SQUARE"
	if square then
		Minimap:SetMaskTexture(SQUARE_MASK)
		MM.changedMask = true
	elseif MM.changedMask then
		Minimap:SetMaskTexture(ROUND_MASK)
		MM.changedMask = nil
	end
	-- LibDBIcon and other addons ask this to place their buttons
	function _G.GetMinimapShape() return square and "SQUARE" or "ROUND" end
	if MinimapCompassTexture then
		MinimapCompassTexture:SetShown(not square and c.border)
	end
	MM.edge:SetShown(square and c.border)
	if square and c.border then
		local col = c.borderColor or { 0, 0, 0 }
		local t = math.max(1, c.borderSize or 1) * ns.Pixel(Minimap)
		local e = MM.edge.edges
		for i = 1, 4 do e[i]:SetColorTexture(col[1], col[2], col[3], 1) end
		e[1]:ClearAllPoints(); e[1]:SetPoint("BOTTOMLEFT", Minimap, "TOPLEFT", -t, 0); e[1]:SetPoint("BOTTOMRIGHT", Minimap, "TOPRIGHT", t, 0); e[1]:SetHeight(t)
		e[2]:ClearAllPoints(); e[2]:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", -t, 0); e[2]:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", t, 0); e[2]:SetHeight(t)
		e[3]:ClearAllPoints(); e[3]:SetPoint("TOPRIGHT", Minimap, "TOPLEFT"); e[3]:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT"); e[3]:SetWidth(t)
		e[4]:ClearAllPoints(); e[4]:SetPoint("TOPLEFT", Minimap, "TOPRIGHT"); e[4]:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMRIGHT"); e[4]:SetWidth(t)
	end
	-- the zone-map overlay Blizzard uses in some places has its own round mask
	local hybrid = _G.HybridMinimap
	if hybrid and hybrid.CircleMask then
		hybrid.CircleMask:SetTexture(square and SQUARE_MASK or ROUND_MASK)
	end
	if MinimapCluster and MinimapCluster.BorderTop then
		MinimapCluster.BorderTop:SetAlpha(c.hideHeaderArt and 0 or 1)
	end
	MM.PinSquare()
end

local function ApplyFonts()
	local c = cfg()
	-- size and outline only: Blizzard colors the zone name by PvP status
	local function font(fs, style)
		if fs and style then ns.SetFont(fs, style.size or 12, ns.OutlineFlags(style.outline or "OUTLINE")) end
	end
	if _G.MinimapZoneText then
		font(_G.MinimapZoneText, c.zoneStyle)
		if MinimapCluster.ZoneTextButton then MinimapCluster.ZoneTextButton:SetShown(c.zoneText) end
	end
	if _G.TimeManagerClockTicker then
		ns.ApplyText(_G.TimeManagerClockTicker, c.clockStyle)
		_G.TimeManagerClockButton:SetShown(c.clock)
	end
	local coords = MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.PlayerCoords
	if coords then
		ns.ApplyText(coords.CoordText, c.coordStyle)
		MM.PlaceCoords()
	end
end

-- Coordinates: Blizzard's own (the "minimapShowPlayerCoords" setting), restyled and moved.
local COORD_POINTS = {
	BOTTOM = { "BOTTOM", "BOTTOM", 1 },  -- inside, bottom edge
	TOP = { "TOP", "TOP", -1 },          -- inside, top edge
	BELOW = { "TOP", "BOTTOM", -1 },     -- under the minimap
	ABOVE = { "BOTTOM", "TOP", 1 },      -- over the minimap
}
function MM.PlaceCoords()
	local coords = MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.PlayerCoords
	if not coords then return end
	local c = cfg()
	local p = COORD_POINTS[c.coordPosition] or COORD_POINTS.BOTTOM
	MM.placing = true
	coords:ClearAllPoints()
	coords:SetPoint(p[1], Minimap, p[2], c.coordX or 0, p[3] * 4 + (c.coordY or 0))
	coords:SetSize(120, (c.coordStyle.size or 11) + 4)
	MM.placing = nil
end

function MM:UpdateVisibility()
	local c = cfg()
	if not MinimapCluster then return end
	local _, t = IsInInstance()
	local mplus = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
	local hide = (c.hideArena and t == "arena") or (c.hidePvP and t == "pvp") or (c.hideMPlus and mplus)
		or (c.hideRaid and t == "raid")
	if ns.unlocked then hide = false end
	ns:RunOOC(function() MinimapCluster:SetShown(not hide) end)
end

function MM:Init()
	local c = cfg()
	if not c.enabled or not Minimap then return end
	MM.active = true
	local edge = CreateFrame("Frame", nil, Minimap)
	edge:SetAllPoints()
	edge:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	edge.edges = {}
	for i = 1, 4 do edge.edges[i] = edge:CreateTexture(nil, "OVERLAY") end
	MM.edge = edge

	-- keep our coordinate spot when Blizzard re-lays out the cluster
	local coords = MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.PlayerCoords
	if coords then
		hooksecurefunc(coords, "SetPoint", function()
			if not MM.placing and MM.active then MM.PlaceCoords() end
		end)
	end

	-- learn the Edit Mode header position before we move the bar
	if MM.headerUnder == nil then MM.headerUnder = HeaderUnderneath() end
	-- Blizzard re-anchors these (Edit Mode header position, mail / landing page updates): pin again
	local function repin() if not MM.pinning then MM.PinSquare() end end
	if MinimapCluster then
		if MinimapCluster.BorderTop then hooksecurefunc(MinimapCluster.BorderTop, "SetPoint", repin) end
		if MinimapCluster.IndicatorFrame then hooksecurefunc(MinimapCluster.IndicatorFrame, "SetPoint", repin) end
		if MinimapCluster.SetHeaderUnderneath then
			hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", function(_, under)
				MM.headerUnder = under and true or false
				repin()
			end)
		end
	end
	if _G.ExpansionLandingPageMinimapButton then
		hooksecurefunc(_G.ExpansionLandingPageMinimapButton, "SetPoint", repin)
	end

	local ev = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
		"CHALLENGE_MODE_RESET", "ADDON_LOADED" }) do
		ev:RegisterEvent(e)
	end
	ev:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if name == "Blizzard_TimeManager" or name == "Blizzard_HybridMinimap" then MM:Refresh() end
			return
		end
		MM:UpdateVisibility()
		if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(2, function() MM:Refresh() end) end
	end)
	-- button fade polling runs only in mouseover mode (its own frame, hidden otherwise)
	local elapsed = 0
	MM.poll = CreateFrame("Frame")
	MM.poll:SetScript("OnUpdate", ns.Timed("Minimap buttons", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.2 then return end
		elapsed = 0
		MM:UpdateButtons()
	end))
	MM.poll:SetShown(cfg().buttons == "mouseover")
	table.insert(ns.lockCallbacks, function() MM:UpdateVisibility() end)
	MM:Refresh()
end

function MM:Refresh()
	if not MM.active then return end
	local c = cfg()
	if MM.poll then MM.poll:SetShown(c.buttons == "mouseover") end
	if c.coords ~= nil and C_CVar and C_CVar.SetCVar then
		pcall(C_CVar.SetCVar, "minimapShowPlayerCoords", c.coords and "1" or "0")
	end
	ApplyShape()
	ApplyFonts()
	MM:UpdateButtons()
	MM:UpdateVisibility()
end

ns:RegisterModule("Minimap", MM)
