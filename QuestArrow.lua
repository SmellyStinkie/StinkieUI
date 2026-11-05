-- StinkieUI: quest arrow. Points at the objective of the quest you're actively tracking (the one
-- with the diamond on screen), relative to the way your character faces, with the distance in
-- yards. Blizzard's navigation gives a distance but no direction, so the direction comes from map
-- positions. The game hides your position in many instances: no position, no arrow.
local _, ns = ...

local QA = {}
ns.QuestArrow = QA

local TICK, RETARGET = 0.05, 1 -- seconds between arrow updates / fresh looks at where the quest is
local MAX_MAP_LEVELS = 4       -- this map and its parents (zone, then continent)

local function cfg() return ns.db.misc.questArrow end

-- World x runs north and y runs west; facing is radians counter-clockwise from north, and textures
-- rotate counter-clockwise too, so this is the arrow's rotation.
function QA.Bearing(fromX, fromY, toX, toY, facing)
	return math.atan2(toY - fromY, toX - fromX) - facing
end

function QA.Distance(fromX, fromY, toX, toY)
	local dx, dy = toX - fromX, toY - fromY
	return math.sqrt(dx * dx + dy * dy)
end

-- The next step on the way (a portal or flight master) when the quest is elsewhere, otherwise the
-- quest's own spot on this map or one above it.
function QA.FindTarget(questID)
	local map, x, y = C_QuestLog.GetNextWaypoint(questID)
	if map and x and y then return map, x, y end
	local m = C_Map.GetBestMapForUnit("player")
	for _ = 1, MAX_MAP_LEVELS do
		if not m or m == 0 then return end
		for _, q in ipairs(C_QuestLog.GetQuestsOnMap(m) or {}) do
			if q.questID == questID and q.x and q.y then return m, q.x, q.y end
		end
		local info = C_Map.GetMapInfo(m)
		m = info and info.parentMapID
	end
end

function QA.Retarget()
	QA.sinceRetarget = 0
	QA.target, QA.questID, QA.label = nil, nil, nil
	if not (C_SuperTrack and C_QuestLog and C_Map) then return end
	local questID = C_SuperTrack.GetSuperTrackedQuestID()
	if not questID or questID == 0 then return end
	QA.questID = questID
	local waypoint = C_QuestLog.GetNextWaypointText(questID)
	QA.label = (waypoint and waypoint ~= "") and waypoint or C_QuestLog.GetTitleForQuestID(questID)
	local map, x, y = QA.FindTarget(questID)
	if not map then return end
	local continent, world = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
	if world then QA.target = { continent = continent, x = world.x, y = world.y } end
end

local function PlayerWorld()
	local map = C_Map.GetBestMapForUnit("player")
	local pos = map and C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return end
	local continent, world = C_Map.GetWorldPosFromMapPos(map, pos)
	if world then return continent, world.x, world.y end
end

-- Blizzard's own distance, only while its diamond is on this quest.
local function NavigationDistance()
	local N, S = C_Navigation, C_SuperTrack
	if not (N and N.GetFrame and N.GetFrame()) then return end
	if S.GetHighestPrioritySuperTrackingType() ~= Enum.SuperTrackingType.Quest then return end
	local d = N.GetDistance()
	if d and d > 0 then return d end
end

local function Paint(rotation, distance, label)
	local h = QA.holder
	h.Arrow:SetShown(rotation ~= nil)
	if rotation then h.Arrow:SetRotation(rotation) end
	h.Distance:SetText(distance and (math.floor(distance + 0.5) .. " yd") or "")
	h.Name:SetText(cfg().showName and label or "")
end

function QA.Update()
	local h = QA.holder
	if not h then return end
	if ns.unlocked then
		Paint(0, 123, "Quest Arrow") -- so it can be seen while moving it
		return
	end
	local rotation, distance
	if QA.questID then
		local t = QA.target
		if t then
			local continent, x, y = PlayerWorld()
			local facing = GetPlayerFacing()
			if continent and continent == t.continent then
				distance = QA.Distance(x, y, t.x, t.y)
				if facing then rotation = QA.Bearing(x, y, t.x, t.y, facing) end
			end
		end
		distance = distance or NavigationDistance()
	end
	if rotation or distance then
		Paint(rotation, distance, QA.label)
	else
		Paint(nil, nil, nil)
	end
end

local function OnUpdate(_, elapsed)
	QA.sinceUpdate = QA.sinceUpdate + elapsed
	if QA.sinceUpdate < TICK then return end
	QA.sinceRetarget = QA.sinceRetarget + QA.sinceUpdate
	QA.sinceUpdate = 0
	if QA.dirty or QA.sinceRetarget >= RETARGET then
		QA.dirty = false
		QA.Retarget()
	end
	QA.Update()
end

local function MarkDirty() QA.dirty = true end

function QA:Init()
	local h = CreateFrame("Frame", "StinkieUI_QuestArrow", UIParent)
	QA.holder = h
	QA.sinceUpdate, QA.sinceRetarget, QA.dirty = 0, 0, true
	h:SetFrameStrata("MEDIUM")
	h.Arrow = h:CreateTexture(nil, "ARTWORK")
	h.Arrow:SetTexture(ns.MEDIA.arrow, "CLAMP", "CLAMP", "TRILINEAR")
	h.Arrow:Hide()
	h.Distance = ns.CreateText(h, 13, "CENTER")
	h.Name = ns.CreateText(h, 13, "CENTER")
	QA.onUpdate = ns.Timed("Quest arrow", OnUpdate)
	ns:RegisterMover("questArrow", h, "Quest Arrow",
		function() return cfg().point end,
		function(p) cfg().point = p end)
	for _, event in ipairs({ "SUPER_TRACKING_CHANGED", "QUEST_LOG_UPDATE", "ZONE_CHANGED",
		"ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		ns:On(event, MarkDirty)
	end
	table.insert(ns.lockCallbacks, QA.Update)
	QA:Refresh()
end

function QA:Refresh()
	local h = QA.holder
	if not h then return end
	local c = cfg()
	h.SUIActive = c.enabled -- no mover box while it's off
	h:SetSize(math.max(c.size, 160), c.size + 2 * c.textStyle.size + 12)
	ns:ApplyPoint(h, c.point)
	h.Arrow:SetSize(c.size, c.size)
	h.Arrow:ClearAllPoints()
	h.Arrow:SetPoint("TOP", h, "TOP", 0, 0)
	h.Arrow:SetVertexColor(c.color[1], c.color[2], c.color[3], 1)
	ns.ApplyText(h.Distance, c.textStyle)
	ns.ApplyText(h.Name, c.textStyle)
	h.Distance:ClearAllPoints()
	h.Distance:SetPoint("TOP", h.Arrow, "BOTTOM", 0, -3)
	h.Name:ClearAllPoints()
	h.Name:SetPoint("TOP", h.Distance, "BOTTOM", 0, -2)
	h.Name:SetWidth(280)
	h:SetShown(c.enabled)
	h:SetScript("OnUpdate", c.enabled and QA.onUpdate or nil)
	QA.dirty = true
end

ns:RegisterModule("QuestArrow", QA)
