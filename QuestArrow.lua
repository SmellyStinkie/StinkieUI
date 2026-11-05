-- StinkieUI: quest marker. A small nameplate in the world on the quest you're actively tracking,
-- or your corpse while you're dead, with the distance in yards. When the spot is off screen it becomes an arrow at the edge of the
-- screen, pointing the way. The marker follows Blizzard's navigation frame, not its SuperTrackedFrame:
-- that one jumps to a small oval around the middle of the screen as the spot goes off screen, which
-- would drag the plate there for a moment. Blizzard's own diamond is hidden while the marker shows.
local _, ns = ...

local QA = {}
ns.QuestArrow = QA

local TICK = 0.05
local SETTLE = 0.4 -- how long a change has to hold before the marker or Blizzard's diamond switches
local CORPSE = "corpse" -- what the marker follows while you're dead, in place of a quest ID
local PLATE_WIDTH, PLATE_WIDTH_NO_NAME = 200, 64
local NEAR_YARDS, FAR_YARDS, FAR_SCALE = 50, 1000, 0.6 -- full size up to NEAR, smallest from FAR

local function cfg() return ns.db.misc.questArrow end

-- Which way the arrow points when the spot is off screen. Textures rotate counter-clockwise.
function QA.EdgeRotation(x, y, centerX, centerY)
	return math.atan2(centerX - x, y - centerY)
end

-- Blizzard keeps an off-screen spot on a small oval around the screen center. This goes the same
-- way from the center, out to a box just inside the screen edge.
function QA.EdgePosition(dx, dy, halfWidth, halfHeight)
	if dx == 0 and dy == 0 then return 0, 0 end
	local toSide = dx ~= 0 and halfWidth / math.abs(dx) or math.huge
	local toTop = dy ~= 0 and halfHeight / math.abs(dy) or math.huge
	local reach = math.min(toSide, toTop)
	return dx * reach, dy * reach
end

-- Smaller the further away, like a distant nameplate. A straight line between the two sizes.
function QA.DistanceScale(yards)
	local t = math.max(0, math.min(1, (yards - NEAR_YARDS) / (FAR_YARDS - NEAR_YARDS)))
	return 1 - t * (1 - FAR_SCALE)
end

-- What Blizzard is navigating to, if it's something the marker shows.
function QA.TrackedTarget()
	if not (C_SuperTrack and C_Navigation and C_Navigation.GetFrame()) then return end
	local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType()
	if kind == Enum.SuperTrackingType.Corpse then return CORPSE end
	if kind ~= Enum.SuperTrackingType.Quest then return end
	local questID = C_SuperTrack.GetSuperTrackedQuestID()
	if questID and questID ~= 0 then return questID end
end

-- With objectives left there's no one spot to point at once you're there: inside the quest's shaded
-- map area the things to find are spread around, and close to it Blizzard's point swings about as
-- you move. A finished quest still points at wherever it's turned in.
function QA.InQuestArea(questID)
	if questID == CORPSE or C_QuestLog.IsComplete(questID) then return false end
	if C_Navigation.GetDistance() < cfg().hideYards then return true end
	local M = C_Minimap
	return (M and M.IsInsideQuestBlob and M.IsInsideQuestBlob(questID)) and true or false
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

-- On screen: plate above an arrow pointing down at the spot, raised by the height setting. Off
-- screen: the arrow on the spot, with the distance under it.
local function LayoutMarker(clamped)
	local h = QA.holder
	local c = cfg()
	h:ClearAllPoints()
	if not clamped then h:SetPoint("CENTER", C_Navigation.GetFrame(), "CENTER", 0, c.height) end
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

-- Blizzard's frame also fades near the mouse and in the "Invalid" state, so its alpha can't be
-- borrowed. Invalid doesn't mean there's no target: WoW Forever reported it at both 618 and 10
-- yards with a real distance and screen position, so only the screen position decides.
function QA.MarkerAlpha(clamped)
	if not C_Navigation.HasValidScreenPosition() then return 0 end
	local state, N = C_Navigation.GetTargetState(), Enum.NavigationState
	if state == N.Disabled then return 0 end
	return (state == N.Occluded and not clamped) and 0.6 or 1
end

-- Off screen: the marker's place and the arrow's direction. Runs every frame, as nothing else moves
-- it here.
function QA.UpdateEdge()
	local h, f = QA.holder, _G.SuperTrackedFrame
	local x, y = f:GetCenter()
	local worldX, worldY = WorldFrame:GetCenter()
	if not (x and worldX) then return end
	local scale = UIParent:GetEffectiveScale()
	local centerX, centerY = worldX / scale, worldY / scale
	local margin = cfg().edgeMargin
	-- dead center tells nothing about direction: stay put rather than sit in the middle of the screen
	if math.abs(x - centerX) < 1 and math.abs(y - centerY) < 1 then return end
	local px, py = QA.EdgePosition(x - centerX, y - centerY,
		UIParent:GetWidth() / 2 - margin, UIParent:GetHeight() / 2 - margin)
	h:ClearAllPoints()
	h:SetPoint("CENTER", UIParent, "CENTER", px, py)
	h.Arrow:SetRotation(QA.EdgeRotation(x, y, centerX, centerY))
end

-- The game can report nothing tracked, or the edge of a quest area, for a moment (a quest update,
-- walking along the edge). Reacting at once would flash the marker or Blizzard's diamond for a
-- frame, so a new state only counts once it has held for a moment. Returns the state to act on.
function QA.Settled(state, now)
	if state == QA.state or QA.state == nil then
		QA.state, QA.pending = state, nil
		return state
	end
	if state ~= QA.pending then QA.pending, QA.pendingAt = state, now end
	if now - QA.pendingAt < SETTLE then return nil end -- still waiting: nothing changes
	QA.state, QA.pending = state, nil
	return state
end

-- settle: from the regular ticks. Other callers (a setting changed) want the answer now.
function QA.Update(settle)
	local h, f = QA.holder, _G.SuperTrackedFrame
	if not (h and f and f.Icon and f.Arrow and f.DistanceText) then return end
	local target = cfg().enabled and QA.TrackedTarget()
	local state = not target and "none" or QA.InQuestArea(target) and "hidden" or "shown"
	if settle then
		state = QA.Settled(state, GetTime())
		if not state then return end
	else
		QA.state, QA.pending = state, nil
	end
	ShowBlizzardMarker(state == "none")
	if state ~= "shown" then
		h:Hide()
		return
	end
	local clamped = C_Navigation.WasClampedToScreen() and true or false
	h:SetAlpha(QA.MarkerAlpha(clamped))
	-- Blizzard can replace the navigation frame, and an anchor to the old one goes nowhere
	local nav = C_Navigation.GetFrame()
	if clamped ~= QA.clamped or nav ~= QA.nav then
		QA.clamped, QA.nav = clamped, nav
		LayoutMarker(clamped)
	end
	local yards = C_Navigation.GetDistance()
	h.Distance:SetText(math.floor(yards + 0.5) .. " yd")
	h:SetScale(clamped and 1 or QA.DistanceScale(yards)) -- the edge arrow stays easy to see
	if clamped then QA.UpdateEdge() end
	if target ~= QA.target then
		QA.target = target
		h.Name:SetText(target == CORPSE and "Your corpse" or C_QuestLog.GetTitleForQuestID(target) or "")
	end
	h:Show()
end

-- /stinkie quest: each thing the marker needs, in order, as the game reports it
function QA.Debug()
	local function show(label, v)
		if ns.issecret(v) then v = "<secret>" end
		ns:Print(label .. ": " .. tostring(v))
	end
	local f, N, S = _G.SuperTrackedFrame, C_Navigation, C_SuperTrack
	show("marker enabled", cfg().enabled)
	show("Blizzard's marker frame", f ~= nil)
	show("its parts", f and f.Icon ~= nil and f.Arrow ~= nil and f.DistanceText ~= nil)
	if not (N and S) then
		show("navigation API", false)
		return
	end
	local kind = S.GetHighestPrioritySuperTrackingType()
	show("tracking type (quest = " .. tostring(Enum.SuperTrackingType.Quest)
		.. ", corpse = " .. tostring(Enum.SuperTrackingType.Corpse) .. ")", kind)
	local questID = S.GetSuperTrackedQuestID()
	show("tracked quest", questID)
	if questID and questID ~= 0 and C_QuestLog then
		show("quest name", C_QuestLog.GetTitleForQuestID(questID))
		show("quest complete", C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID))
		show("inside the quest area", C_Minimap and C_Minimap.IsInsideQuestBlob and C_Minimap.IsInsideQuestBlob(questID))
	end
	show("navigation frame", N.GetFrame() ~= nil)
	show("valid screen position", N.HasValidScreenPosition())
	show("target state", N.GetTargetState())
	show("off screen", N.WasClampedToScreen())
	show("distance", N.GetDistance())
	local h = QA.holder
	if h then
		show("marker shown", h:IsShown())
		show("marker alpha", h:GetAlpha())
	end
end

-- Every frame while it's up: anything that moves it must not wait for the next tick, or it's seen
-- in the wrong place for a moment.
local function EveryFrame()
	local clamped = C_Navigation.WasClampedToScreen() and true or false
	if clamped ~= QA.clamped then
		QA.clamped = clamped
		LayoutMarker(clamped)
	end
	QA.holder:SetAlpha(QA.MarkerAlpha(clamped))
	if clamped then QA.UpdateEdge() end
end

local function OnUpdate(_, elapsed)
	if QA.holder:IsShown() and C_Navigation.GetFrame() then EveryFrame() end
	QA.sinceUpdate = QA.sinceUpdate + elapsed
	if QA.sinceUpdate < TICK then return end
	QA.sinceUpdate = 0
	QA.Update(true)
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
