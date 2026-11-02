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
	p.frame:SetPoint("TOP", p.anchor, "TOP", 0, 0)
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

function W:SkinScore()
	if not (cfg().enabled and InBattleground()) then return end
	local container = _G.UIWidgetTopCenterContainerFrame
	if not (container and type(container.widgetFrames) == "table") then return end
	local c = cfg()
	for _, widget in pairs(container.widgetFrames) do
		if widget.LeftBar and widget.RightBar then
			SkinBar(widget.LeftBar, c.leftColor)
			SkinBar(widget.RightBar, c.rightColor)
		end
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
	bgScore = { move = "moveScore", scale = "scoreScale", point = "scorePoint", bgOnly = true },
	bgCapture = { move = "moveCapture", scale = "captureScale", point = "capturePoint", bgOnly = true },
	bgGhost = { move = "moveGhost", scale = "ghostScale", point = "ghostPoint" }, -- "Return to Graveyard"
}

function W:Apply()
	local c = cfg()
	local inBG = c.enabled and InBattleground()
	for key, p in pairs(pins) do
		Attach(p)
		local k = PIN_KEYS[key]
		local want = c.enabled and c[k.move] and (inBG or not k.bgOnly)
		ns:ApplyPoint(p.anchor, c[k.point])
		p.anchor:SetScale(ns.db.scale)
		p.anchor.SUIActive = c.enabled and true or false
		if p.frame then
			if want then
				p.active = true
				p.frame:SetScale(c[k.scale] or 1)
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

function W:Init()
	MakePin("bgScore", "Battleground Score", "UIWidgetTopCenterContainerFrame", "scorePoint")
	MakePin("bgCapture", "Capture / Cart Progress", "UIWidgetBelowMinimapContainerFrame", "capturePoint")
	MakePin("bgGhost", "Return to Graveyard", "GhostFrame", "ghostPoint")
	local container = _G.UIWidgetTopCenterContainerFrame
	if container then
		if container.UpdateWidgetLayout then hooksecurefunc(container, "UpdateWidgetLayout", function() W:SkinScore() end) end
		if container.ProcessWidget then hooksecurefunc(container, "ProcessWidget", function() W:SkinScore() end) end
	end
	ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(0.5, function() W:Apply() end) end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() W:Apply() end)
	table.insert(ns.lockCallbacks, function() W:UpdatePreview() end)
	W:Apply()
end

function W:Refresh()
	W:Apply()
end

ns:RegisterModule("BGWidgets", W)
