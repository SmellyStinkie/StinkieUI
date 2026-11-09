-- StinkieUI: battleground score widgets. Moves and scales Blizzard's top-center score display
-- and the below-minimap widgets (cart / capture progress), and optionally restyles the score bars.
-- Only active inside battlegrounds; elsewhere Blizzard's own layout is left alone.
local _, ns = ...

local W = {}
ns.BGWidgets = W

local function cfg() return ns.db.bgWidgets end

local function InBattleground()
	local _, t = IsInInstance()
	return t == "pvp"
end

local function InArena()
	local _, t = IsInInstance()
	return t == "arena"
end
W.InArena = InArena

---------------------------------------------------------------------------
-- Pinning a Blizzard frame to one of our movers
---------------------------------------------------------------------------
local pins = {} -- key -> { frame, anchor, active, busy }

local function Pin(p)
	if not (p.active and p.frame) or p.busy then return end
	if InCombatLockdown() and p.frame.IsProtected and p.frame:IsProtected() then
		ns:RunOOC(function() Pin(p) end)
		return
	end
	p.busy = true
	p.frame:ClearAllPoints()
	-- dx: the arena info's centering nudge (see W:CenterArena)
	p.frame:SetPoint("TOP", p.use or p.anchor, "TOP", p.use and (p.dx or 0) or 0, 0)
	p.busy = false
end

local function MakePin(key, label, frameName, pointKey)
	local anchor = CreateFrame("Frame", "StinkieUI_" .. key .. "Anchor", UIParent)
	anchor:SetSize(220, 40)
	ns:RegisterMover(key, anchor, label,
		function() return cfg()[pointKey] end,
		function(pt) cfg()[pointKey] = pt end)
	local p = { anchor = anchor, frameName = frameName }
	pins[key] = p
	return p
end

local function Attach(p)
	local frame = _G[p.frameName]
	if not frame or p.frame then return end
	p.frame = frame
	-- Blizzard re-anchors these frames on every layout; put ours back right after
	hooksecurefunc(frame, "SetPoint", function() if p.active and not p.busy then Pin(p) end end)
end

---------------------------------------------------------------------------
-- Score bar texture
---------------------------------------------------------------------------
local function TexturePath()
	local t = cfg().texture
	if t == "flat" then return ns.TEXTURE end
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM and t ~= "blizzard" then return LSM:Fetch("statusbar", t, true) end
	return nil
end

local skinned = setmetatable({}, { __mode = "k" })

local function SkinBar(bar, color)
	local path = TexturePath()
	if not path or not bar.SetStatusBarTexture then return end
	bar:SetStatusBarTexture(path)
	local tex = bar:GetStatusBarTexture()
	if tex then
		tex:SetHorizTile(false)
		tex:SetVertexColor(color[1], color[2], color[3], 1)
	end
	for _, key in ipairs({ "BorderLeft", "BorderRight", "BorderCenter", "BG", "Spark" }) do
		if bar[key] then bar[key]:SetAlpha(0) end
	end
	if not skinned[bar] then
		skinned[bar] = true
		local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.6)
		bar.SUIBg = bg
		ns.IconBorder(bar)
	end
	bar.SUIBg:Show()
end

-- every text in a widget (and its child frames, one level down) in the Stinkie UI font
local function RestyleText(frame, size, depth)
	if not frame or not frame.GetRegions then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:IsObjectType("FontString") then ns.SetFont(r, size, "OUTLINE") end
	end
	if (depth or 0) < 2 and frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do RestyleText(child, size, (depth or 0) + 1) end
	end
end

-- Blizzard's own flag icons under the score: the flag banners show the same thing. Alpha only, and
-- it's undone wherever the banners aren't taking over (the frame is reused between matches).
function W:UpdateFlagRow()
	local container = _G.UIWidgetTopCenterContainerFrame
	if not (container and type(container.widgetFrames) == "table") then return end
	local row = Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.DoubleStateIconRow
	local FC = ns.FlagCap
	local ours = FC and FC.inPvP and FC.flagMap and ns.db.flagCap.enabled
	for _, widget in pairs(container.widgetFrames) do
		if row and widget.widgetType == row then widget:SetAlpha(ours and 0 or 1) end
	end
end

---------------------------------------------------------------------------
-- Arena info centering. Our bigger font makes Blizzard's round and wins texts wider than the
-- slots it sized for them, so they spill to one side. Measure where the text really is and
-- nudge the whole block so it sits centered under our anchor.
---------------------------------------------------------------------------
local issecret = ns.issecret

-- small textures (icons such as the ready check mark) count as content; big ones are backgrounds
local ICON_MAX = 48

-- the left and right edge of every visible text in a widget (and its children), in screen pixels;
-- with icons, small visible textures count too
local function TextBounds(frame, b, depth, icons)
	if not frame or not frame.GetRegions then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if icons and r:IsObjectType("Texture") and r:IsVisible() and r:GetAlpha() > 0 then
			local l, rt = r:GetLeft(), r:GetRight()
			if type(l) == "number" and type(rt) == "number" and not issecret(l) and not issecret(rt)
				and rt > l and rt - l <= ICON_MAX then
				local s = r:GetEffectiveScale()
				b.l = math.min(b.l or math.huge, l * s)
				b.r = math.max(b.r or -math.huge, rt * s)
			end
		elseif r:IsObjectType("FontString") and r:IsVisible() then
			local text = r:GetText()
			local l, rt = r:GetLeft(), r:GetRight()
			if type(text) == "string" and text ~= "" and type(l) == "number" and type(rt) == "number"
				and not issecret(l) and not issecret(rt) then
				-- a wide box with short text: only the text's own width counts, placed by its justify
				local w = r:GetStringWidth()
				if type(w) == "number" and not issecret(w) and w < rt - l then
					local j = r:GetJustifyH()
					if j == "LEFT" then rt = l + w
					elseif j == "RIGHT" then l = rt - w
					else local mid = (l + rt) / 2; l, rt = mid - w / 2, mid + w / 2 end
				end
				local s = r:GetEffectiveScale()
				b.l = math.min(b.l or math.huge, l * s)
				b.r = math.max(b.r or -math.huge, rt * s)
			end
		end
	end
	if (depth or 0) < 2 and frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do TextBounds(child, b, (depth or 0) + 1, icons) end
	end
end
W.TextBounds = TextBounds

-- The width a widget should have so its content (left..right, screen pixels) keeps the same
-- inset on both sides, in the widget's own units. nil when it already fits.
function W.FitWidth(widgetLeft, oldWidth, left, right, scale)
	if not (widgetLeft and oldWidth and left and right and scale and scale > 0) then return nil end
	local inset = math.max(0, left - widgetLeft)
	local want = (right - widgetLeft + inset) / scale
	if want <= 0 or math.abs(want - oldWidth) < 1 then return nil end
	return want
end

-- Blizzard sizes a text widget for its own font and centers it by that width. In our font the
-- text is a different width, so the line sits off center: give the widget its text's width.
-- Bars (the timer, team bars) keep their size.
local function FitWidget(widget)
	if widget.Bar or widget.LeftBar or widget.RightBar then return end
	local b = {}
	TextBounds(widget, b, 0, true)
	local wl, w = widget:GetLeft(), widget:GetWidth()
	if not b.l or type(wl) ~= "number" or type(w) ~= "number" or issecret(wl) or issecret(w) then return end
	local s = widget:GetEffectiveScale()
	local want = W.FitWidth(wl * s, w, b.l, b.r, s)
	if want then widget:SetWidth(want) end
end

-- the nudge (in the container's own units) that puts text spanning left..right (screen pixels)
-- centered on center (screen pixels)
function W.CenterNudge(left, right, center, scale)
	if not (left and right and center and scale and scale > 0) then return 0 end
	return (center - (left + right) / 2) / scale
end

function W:CenterArena()
	local p = pins.bgScore
	if not (p and p.active and p.use and p.frame) then return end
	local container = p.frame
	if type(container.widgetFrames) ~= "table" then return end
	for _, widget in pairs(container.widgetFrames) do
		if widget:IsShown() then FitWidget(widget) end
	end
	local b = {}
	for _, widget in pairs(container.widgetFrames) do
		if widget:IsShown() then TextBounds(widget, b, 0) end
	end
	local cx = W.arenaAnchor:GetCenter()
	if not (b.l and type(cx) == "number") or issecret(cx) then return end
	local dx = W.CenterNudge(b.l, b.r, cx * W.arenaAnchor:GetEffectiveScale(), container:GetEffectiveScale())
	-- under a pixel is close enough, and keeps a ticking timer from jiggling it
	if math.abs(dx) < 1 then return end
	p.dx = (p.dx or 0) + dx
	Pin(p)
end

function W:SkinScore()
	W:UpdateFlagRow()
	local c = cfg()
	if not c.enabled then return end
	local inBG, inArena = InBattleground(), InArena()
	if not (inBG or inArena) then return end
	local container = _G.UIWidgetTopCenterContainerFrame
	if not (container and type(container.widgetFrames) == "table") then return end
	for _, widget in pairs(container.widgetFrames) do
		if widget.LeftBar and widget.RightBar then
			SkinBar(widget.LeftBar, c.leftColor)
			SkinBar(widget.RightBar, c.rightColor)
		elseif widget.Bar and inArena then
			SkinBar(widget.Bar, ns.ACCENT)
		end
		-- arena and Solo Shuffle: match timer, "Round 3 of 6" and the rest in our font and size
		if inArena and c.arenaText then pcall(RestyleText, widget, c.arenaTextSize or 16, 0) end
	end
	-- measure after Blizzard has placed the new text
	if inArena and not W.centerQueued then
		W.centerQueued = true
		C_Timer.After(0, function()
			W.centerQueued = nil
			local ok, err = pcall(W.CenterArena, W)
			if not ok then ns.Error(err) end
		end)
	end
end

---------------------------------------------------------------------------
-- Test mode: stand-ins on the movers, drawn with the chosen texture, colors and size
---------------------------------------------------------------------------
local function PreviewBar(parent, w, h)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(w, h)
	bar:SetMinMaxValues(0, 1)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	ns.IconBorder(bar)
	bar.Label = ns.CreateText(bar, 11, "CENTER")
	bar.Label:SetPoint("CENTER")
	return bar
end

local function BuildPreviews()
	if W.previews then return end
	local score = CreateFrame("Frame", nil, pins.bgScore.anchor)
	score:SetSize(264, 22)
	score:SetPoint("TOP")
	score.left = PreviewBar(score, 130, 16)
	score.left:SetPoint("LEFT")
	score.left:SetValue(0.62)
	score.left.Label:SetText("1240")
	score.right = PreviewBar(score, 130, 16)
	score.right:SetPoint("RIGHT")
	score.right:SetReverseFill(true)
	score.right:SetValue(0.41)
	score.right.Label:SetText("810")
	local capture = CreateFrame("Frame", nil, pins.bgCapture.anchor)
	capture:SetSize(200, 16)
	capture:SetPoint("TOP")
	capture.bar = PreviewBar(capture, 200, 14)
	capture.bar:SetPoint("CENTER")
	capture.bar:SetValue(0.55)
	capture.bar.Label:SetText("Cart 55%")
	local ghost = CreateFrame("Frame", nil, pins.bgGhost.anchor)
	ghost:SetSize(180, 26)
	ghost:SetPoint("TOP")
	local gbg = ghost:CreateTexture(nil, "BACKGROUND")
	gbg:SetAllPoints()
	gbg:SetColorTexture(0.12, 0.12, 0.14, 0.95)
	ns.IconBorder(ghost)
	ghost.Label = ns.CreateText(ghost, 12, "CENTER")
	ghost.Label:SetPoint("CENTER")
	ghost.Label:SetText("Return to Graveyard")
	W.previews = { score = score, capture = capture, ghost = ghost }
end

function W:UpdatePreview()
	local show = (W.testMode or ns.unlocked) and cfg().enabled
	if not show then
		if W.previews then
			W.previews.score:Hide()
			W.previews.capture:Hide()
			W.previews.ghost:Hide()
		end
		return
	end
	BuildPreviews()
	local c = cfg()
	local path = TexturePath() or [[Interface\TargetingFrame\UI-StatusBar]]
	local p = W.previews
	for _, pair in ipairs({ { p.score.left, c.leftColor }, { p.score.right, c.rightColor }, { p.capture.bar, { 0.9, 0.8, 0.3 } } }) do
		local bar, col = pair[1], pair[2]
		bar:SetStatusBarTexture(path)
		bar:GetStatusBarTexture():SetVertexColor(col[1], col[2], col[3], 1)
	end
	p.score:SetScale(c.scoreScale)
	p.capture:SetScale(c.captureScale)
	p.score:SetShown(c.moveScore)
	p.capture:SetShown(c.moveCapture)
	p.ghost:SetScale(c.ghostScale or 1)
	p.ghost:SetShown(c.moveGhost)
end

function W:SetTestMode(on)
	W.testMode = on or nil
	W:UpdatePreview()
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local PIN_KEYS = {
	bgScore = { move = "moveScore", scale = "scoreScale", point = "scorePoint", bgOnly = true,
		-- the same Blizzard frame holds the arena / Solo Shuffle info (round, timer): own spot and size
		arena = { move = "moveArena", scale = "arenaScale" } },
	bgCapture = { move = "moveCapture", scale = "captureScale", point = "capturePoint", bgOnly = true },
	bgGhost = { move = "moveGhost", scale = "ghostScale", point = "ghostPoint" }, -- "Return to Graveyard"
}

function W:Apply()
	local c = cfg()
	local inBG = c.enabled and InBattleground()
	for key, p in pairs(pins) do
		Attach(p)
		local k = PIN_KEYS[key]
		local arena = k.arena and c.enabled and c[k.arena.move] and InArena()
		local want = c.enabled and c[k.move] and (inBG or not k.bgOnly) or arena
		ns:ApplyPoint(p.anchor, c[k.point])
		p.anchor:SetScale(ns.db.scale)
		p.anchor.SUIActive = c.enabled and true or false
		if W.arenaAnchor then
			ns:ApplyPoint(W.arenaAnchor, c.arenaPoint)
			W.arenaAnchor:SetScale(ns.db.scale)
			W.arenaAnchor.SUIActive = c.enabled and true or false
		end
		if not arena then p.dx = nil end -- a fresh measure each arena
		p.use = arena and W.arenaAnchor or nil
		if p.frame then
			if want then
				p.active = true
				p.frame:SetScale((arena and c[k.arena.scale]) or c[k.scale] or 1)
				Pin(p)
			elseif p.active then
				-- hand it back: Blizzard re-anchors it on its next layout
				p.active = false
				p.frame:SetScale(1)
				if key == "bgScore" then
					p.busy = true
					p.frame:ClearAllPoints()
					p.frame:SetPoint("TOP", UIParent, "TOP", 0, -15)
					p.busy = false
				elseif key == "bgGhost" then
					local top = _G.UIWidgetTopCenterContainerFrame
					p.busy = true
					p.frame:ClearAllPoints()
					if top then p.frame:SetPoint("TOP", top, "BOTTOM", 0, -4) else p.frame:SetPoint("TOP", UIParent, "TOP", 0, -60) end
					p.busy = false
				end
			end
		end
	end
	W:SkinScore()
	W:UpdatePreview()
end

---------------------------------------------------------------------------
-- Blizzard raid frames: hidden in Blitz and normal battlegrounds (up to 15 players), where the
-- battleground frames already cover your team. 40-player battlegrounds and everywhere else are
-- left to Blizzard. The container is protected, so it only changes out of combat.
---------------------------------------------------------------------------
local raidHidden = false
local function WantRaidHidden()
	if not cfg().hideRaidFrames or not InBattleground() then return false end
	local BG = ns.BGEnemies
	return not (BG and BG.IsLargeBattleground and BG.IsLargeBattleground())
end

local function HideRaidNow()
	local container = _G.CompactRaidFrameContainer
	if container and container:IsShown() and WantRaidHidden() then
		ns:RunOOC(function()
			if WantRaidHidden() then container:Hide() end
		end)
	end
end

function W:UpdateRaidFrames()
	local container = _G.CompactRaidFrameContainer
	if not container then return end
	if WantRaidHidden() then
		raidHidden = true
		HideRaidNow()
	elseif raidHidden then
		raidHidden = false
		ns:RunOOC(function()
			if CompactRaidFrameManager_UpdateContainerVisibility then CompactRaidFrameManager_UpdateContainerVisibility() end
		end)
	end
end

function W:Init()
	MakePin("bgScore", "Battleground Score", "UIWidgetTopCenterContainerFrame", "scorePoint")
	MakePin("bgCapture", "Capture / Cart Progress", "UIWidgetBelowMinimapContainerFrame", "capturePoint")
	MakePin("bgGhost", "Return to Graveyard", "GhostFrame", "ghostPoint")
	-- arena / Solo Shuffle info (round, timer): same Blizzard frame as the battleground score
	W.arenaAnchor = CreateFrame("Frame", "StinkieUI_arenaInfoAnchor", UIParent)
	W.arenaAnchor:SetSize(220, 40)
	ns:RegisterMover("arenaInfo", W.arenaAnchor, "Arena / Shuffle Info",
		function() return cfg().arenaPoint end,
		function(pt) cfg().arenaPoint = pt end)
	local container = _G.UIWidgetTopCenterContainerFrame
	if container then
		if container.UpdateWidgetLayout then hooksecurefunc(container, "UpdateWidgetLayout", function() W:SkinScore() end) end
		if container.ProcessWidget then hooksecurefunc(container, "ProcessWidget", function() W:SkinScore() end) end
	end
	ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(0.5, function() W:Apply(); W:UpdateRaidFrames() end) end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() W:Apply(); W:UpdateRaidFrames() end)
	ns:On("PVP_MATCH_STATE_CHANGED", function() W:UpdateRaidFrames() end)
	ns:On("UPDATE_BATTLEFIELD_SCORE", function() if raidHidden ~= WantRaidHidden() then W:UpdateRaidFrames() end end)
	-- Blizzard shows the container again on roster changes; hide it again right after
	if CompactRaidFrameManager_UpdateContainerVisibility then
		hooksecurefunc("CompactRaidFrameManager_UpdateContainerVisibility", HideRaidNow)
	end
	if _G.CompactRaidFrameContainer then _G.CompactRaidFrameContainer:HookScript("OnShow", HideRaidNow) end
	table.insert(ns.lockCallbacks, function() W:UpdatePreview() end)
	W:Apply()
end

function W:Refresh()
	W:Apply()
	W:UpdateRaidFrames()
end

ns:RegisterModule("BGWidgets", W)
