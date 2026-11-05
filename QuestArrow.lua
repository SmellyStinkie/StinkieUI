-- StinkieUI: quest marker. A small nameplate in the world on the quest you're actively tracking,
-- with the distance in yards. When the spot is off screen it becomes an arrow at the edge of the
-- screen, pointing the way. Blizzard's SuperTrackedFrame already sits on the spot, stays on screen
-- and fades, so the marker follows it and Blizzard's own diamond is hidden while it does.
local _, ns = ...

local QA = {}
ns.QuestArrow = QA

local TICK = 0.05
local PLATE_WIDTH, PLATE_WIDTH_NO_NAME = 200, 64
local NEAR_YARDS, FAR_YARDS, FAR_SCALE = 50, 1000, 0.6 -- full size up to NEAR, smallest from FAR

local function cfg() return ns.db.misc.questArrow end

-- Which way the arrow points when the spot is off screen. Textures rotate counter-clockwise.
function QA.EdgeRotation(x, y, centerX, centerY)
	return math.atan2(centerX - x, y - centerY)
end

-- Smaller the further away, like a distant nameplate. A straight line between the two sizes.
function QA.DistanceScale(yards)
	local t = math.max(0, math.min(1, (yards - NEAR_YARDS) / (FAR_YARDS - NEAR_YARDS)))
	return 1 - t * (1 - FAR_SCALE)
end

function QA.TrackedQuest()
	if not (C_SuperTrack and C_Navigation and C_Navigation.GetFrame()) then return end
	if C_SuperTrack.GetHighestPrioritySuperTrackingType() ~= Enum.SuperTrackingType.Quest then return end
	local questID = C_SuperTrack.GetSuperTrackedQuestID()
	if questID and questID ~= 0 then return questID end
end

local function ShowBlizzardMarker(show)
	local f = _G.SuperTrackedFrame
	if not f or QA.blizzardShown == show then return end
	QA.blizzardShown = show
	local alpha = show and 1 or 0
	f.Icon:SetAlpha(alpha)
	f.Arrow:SetAlpha(alpha)
	f.DistanceText:SetAlpha(alpha)
end

-- On screen: plate above an arrow pointing down at the spot. Off screen: the arrow on the spot,
-- with the distance under it.
local function LayoutMarker(clamped)
	local h = QA.holder
	local c = cfg()
	h.Plate:SetShown(not clamped)
	h.Name:SetShown(c.showName)
	h.Plate:SetSize(c.showName and PLATE_WIDTH or PLATE_WIDTH_NO_NAME, c.textStyle.size + 8)
	h.Arrow:ClearAllPoints()
	h.Distance:ClearAllPoints()
	h.Plate:ClearAllPoints()
	if clamped then
		h.Arrow:SetPoint("CENTER", h, "CENTER", 0, 0)
		h.Distance:SetPoint("TOP", h.Arrow, "BOTTOM", 0, -2)
	else
		h.Arrow:SetRotation(math.pi)
		h.Arrow:SetPoint("BOTTOM", h, "CENTER", 0, 0)
		h.Plate:SetPoint("BOTTOM", h.Arrow, "TOP", 0, 2)
		h.Distance:SetPoint("RIGHT", h.Plate, "RIGHT", -6, 0)
	end
end

-- Blizzard's frame also fades near the mouse, so its alpha can't be borrowed: the game's own state
-- says whether the spot can be shown, and dims it when something is in the way.
function QA.MarkerAlpha(clamped)
	if not C_Navigation.HasValidScreenPosition() then return 0 end
	local state, N = C_Navigation.GetTargetState(), Enum.NavigationState
	if state == N.Invalid or state == N.Disabled then return 0 end
	return (state == N.Occluded and not clamped) and 0.6 or 1
end

function QA.Update()
	local h, f = QA.holder, _G.SuperTrackedFrame
	if not (h and f and f.Icon and f.Arrow and f.DistanceText) then return end
	local questID = cfg().enabled and QA.TrackedQuest()
	ShowBlizzardMarker(not questID)
	if not questID then
		h:Hide()
		return
	end
	if not QA.anchored then
		QA.anchored = true
		h:SetPoint("CENTER", f, "CENTER", 0, 0)
	end
	local clamped = C_Navigation.WasClampedToScreen() and true or false
	h:SetAlpha(QA.MarkerAlpha(clamped))
	if clamped ~= QA.clamped then
		QA.clamped = clamped
		LayoutMarker(clamped)
	end
	if clamped then
		local x, y = f:GetCenter()
		local worldX, worldY = WorldFrame:GetCenter()
		local scale = UIParent:GetEffectiveScale()
		if x and worldX then h.Arrow:SetRotation(QA.EdgeRotation(x, y, worldX / scale, worldY / scale)) end
	end
	local yards = C_Navigation.GetDistance()
	h.Distance:SetText(math.floor(yards + 0.5) .. " yd")
	h:SetScale(clamped and 1 or QA.DistanceScale(yards)) -- the edge arrow stays easy to see
	if questID ~= QA.questID then
		QA.questID = questID
		h.Name:SetText(C_QuestLog.GetTitleForQuestID(questID) or "")
	end
	h:Show()
end

local function OnUpdate(_, elapsed)
	QA.sinceUpdate = QA.sinceUpdate + elapsed
	if QA.sinceUpdate < TICK then return end
	QA.sinceUpdate = 0
	QA.Update()
end

function QA:Init()
	local h = CreateFrame("Frame", "StinkieUI_QuestMarker", UIParent)
	QA.holder = h
	QA.sinceUpdate = 0
	h:SetSize(1, 1)
	h:SetFrameStrata("BACKGROUND")
	h:Hide()
	h.Arrow = h:CreateTexture(nil, "ARTWORK")
	h.Arrow:SetTexture(ns.MEDIA.arrow, "CLAMP", "CLAMP", "TRILINEAR")
	h.Plate = CreateFrame("Frame", nil, h)
	ns.CreateBackdrop(h.Plate)
	h.Name = ns.CreateText(h.Plate, 13, "LEFT")
	-- on its own layer: the plate is a child frame, so it would draw over text on the holder
	h.TextLayer = CreateFrame("Frame", nil, h)
	h.TextLayer:SetFrameLevel(h.Plate:GetFrameLevel() + 2)
	h.Distance = ns.CreateText(h.TextLayer, 13, "RIGHT")
	QA.driver = CreateFrame("Frame")
	QA.onUpdate = ns.Timed("Quest marker", OnUpdate)
	QA:Refresh()
end

function QA:Refresh()
	local h = QA.holder
	if not h then return end
	local c = cfg()
	h.Arrow:SetSize(c.size, c.size)
	h.Arrow:SetVertexColor(c.color[1], c.color[2], c.color[3], 1)
	ns.ApplyText(h.Name, c.textStyle)
	ns.ApplyText(h.Distance, c.textStyle)
	h.Name:ClearAllPoints()
	h.Name:SetPoint("LEFT", h.Plate, "LEFT", 6, 0)
	h.Name:SetPoint("RIGHT", h.Plate, "RIGHT", -58, 0)
	QA.clamped = nil -- lay it out again on the next update
	QA.driver:SetScript("OnUpdate", c.enabled and QA.onUpdate or nil)
	QA.Update()
end

ns:RegisterModule("QuestArrow", QA)
