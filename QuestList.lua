-- StinkieUI: quests in the objective tracker, grouped by zone, with a plus/minus on each zone. Our own
-- list stands in for Blizzard's two quest sections. Blizzard's tracker keeps running: after each of
-- its layouts the quest sections are moved off screen and the sections below are hung under our list.
-- Only anchors change. Nothing is written into Blizzard's frames and its update code is never called.
-- The list shows what the quest APIs say, so quests Blizzard ran out of room for are still here.
-- Quest item buttons are secure, so they can't be created, moved or hidden in combat. They sit on
-- UIParent, not on the list, or the list would be locked in combat too. While one is up in combat
-- only the text changes, and the layout catches up when combat ends.
local _, ns = ...

local QL = {}
ns.QuestList = QL

local ITEM_SIZE = 26
local ZONE_GAP, QUEST_GAP, TEXT_GAP = 7, 4, 1
local BOX = 9 -- plus/minus
local FOCUS_DOT = 10
local FOCUS_COLOR, UNFOCUSED_COLOR = { 1, 0.9, 0 }, { 0.42, 0.38, 0.05 }
local OUTLINE = { repeatable = { 0.2, 0.6, 1 }, campaign = { 0.75, 0.4, 1 } }
local EMPTY = { 0, 0, 0 }
local INDENT = { offer = 0, header = 7, zone = BOX + 5, quest = 22, line = 30 }
local GOLD, GREEN, RED, GRAY = { 1, 0.82, 0 }, { 0.25, 1, 0.25 }, { 1, 0.2, 0.2 }, { 0.8, 0.8, 0.8 }

QL.zoneOf = {} -- a quest under a header collapsed in the quest log isn't listed: keep what we saw
QL.rows, QL.buttons, QL.itemRows = {}, {}, {}
QL.shownItems = 0

local function cfg() return ns.db.objectives end

-- Blizzard's own tracker colors, so the list matches the sections around it
local function TrackerColor(key, fallback)
	local colors = _G.OBJECTIVE_TRACKER_COLOR
	local c = colors and colors[key]
	return c and { c.r, c.g, c.b } or fallback
end
local function Tracker() return _G.ObjectiveTrackerFrame end

function QL.Wanted()
	local c = cfg()
	return c.enabled and c.zoneGroups and true or false
end

function QL.Active()
	return QL.list ~= nil and QL.Wanted()
end

local function IsQuestModule(m)
	return m == _G.QuestObjectiveTracker or m == _G.CampaignQuestObjectiveTracker
end

---------------------------------------------------------------------------
-- What to show
---------------------------------------------------------------------------
-- The quest log's headers are the zones. Returns each zone's place in the log.
function QL.ScanZones()
	local rank, zone, n = {}, nil, 0
	for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
		local info = C_QuestLog.GetInfo(i)
		if info and info.isHeader then
			zone = info.title
			if zone and not rank[zone] then
				n = n + 1
				rank[zone] = n
			end
		elseif info and info.questID and zone then
			QL.zoneOf[info.questID] = zone
		end
	end
	return rank
end

local function WaypointLine(questID, format)
	local text = C_QuestLog.GetNextWaypointText(questID)
	if not text then return nil end
	return { text = format and format:format(text) or text, color = GRAY }
end

function QL.QuestLines(quest)
	local lines = {}
	local id = quest.id
	local function add(text, color) lines[#lines + 1] = { text = text, color = color } end
	if quest.complete then
		if quest.autoComplete then
			add(_G.QUEST_WATCH_QUEST_COMPLETE or "Quest complete", GRAY)
			add(_G.QUEST_WATCH_CLICK_TO_COMPLETE or "Click to complete", GRAY)
		else
			local done = quest.index and GetQuestLogCompletionText(quest.index)
			local waypoint = WaypointLine(id, done and quest.tracked and _G.WAYPOINT_OBJECTIVE_FORMAT_OPTIONAL)
			if waypoint and (quest.tracked or not done) then lines[1] = waypoint end
			if done then
				add(done, GRAY) -- only "Ready for turn-in" is green, as on Blizzard's tracker
			elseif not waypoint then
				add(_G.QUEST_WATCH_QUEST_READY or "Ready for turn-in", TrackerColor("Complete", GREEN))
			end
		end
	elseif quest.failed then
		add(_G.FAILED or "Failed", TrackerColor("Failed", RED))
	else
		if quest.tracked then
			local waypoint = WaypointLine(id, _G.WAYPOINT_OBJECTIVE_FORMAT_OPTIONAL)
			if waypoint then lines[1] = waypoint end
		end
		-- finished objectives go away, as they do on Blizzard's tracker
		for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
			if o.text and o.text ~= "" and not o.finished then add(o.text, GRAY) end
		end
	end
	return lines
end

local function QuestItem(index, complete)
	if not index then return nil end
	local link, texture, charges, showWhenComplete = GetQuestLogSpecialItemInfo(index)
	if not (link and texture) or (complete and not showWhenComplete) then return nil end
	local itemID = link:match("item:(%d+)")
	if not itemID then return nil end
	return { id = itemID, texture = texture, charges = charges }
end

-- "campaign", "repeatable" or nil, the way Blizzard picks a quest's icon. Meta quests are weekly by
-- frequency, but Blizzard doesn't count those as repeatable.
function QL.QuestType(id, info)
	local classes = Enum.QuestClassification
	local system = C_QuestInfoSystem
	local class = classes and system and system.GetQuestClassification and system.GetQuestClassification(id)
	if class then
		if class == classes.Campaign then return "campaign" end
		if class == classes.Recurring or class == classes.Calling then return "repeatable" end
		if class == classes.Meta then return nil end
	end
	if ((info and info.frequency) or 0) > 0 then return "repeatable" end
	if C_QuestLog.IsRepeatableQuest and C_QuestLog.IsRepeatableQuest(id) then return "repeatable" end
	return nil
end

-- outline and middle of the focus box
function QL.FocusColors(quest)
	local outline = OUTLINE[quest.questType]
	if quest.tracked then return outline or FOCUS_COLOR, FOCUS_COLOR end
	return outline or UNFOCUSED_COLOR, EMPTY
end

-- The title as this client shows it. Blizzard's function only builds text: on Forever that's the
-- level in front and the difficulty color (if that game setting is on), on Midnight the plain title.
function QL.DisplayTitle(id, title)
	local tags = QuestUtilsOverrides and QuestUtilsOverrides.GetQuestTagText
	local tag = tags and tags(id)
	if tag then title = title .. " " .. tag end
	return SetQuestTitleLevelAndDifficultyColor and SetQuestTitleLevelAndDifficultyColor(id, title) or title
end

-- watched quests by zone, zones in quest log order
function QL.Build()
	local _, instanceType = IsInInstance()
	if instanceType == "arena" then return {} end -- Blizzard shows no quests there either
	local rank = QL.ScanZones()
	local groups, byZone = {}, {}
	local tracked = C_SuperTrack.GetSuperTrackedQuestID()
	local fallback = _G.OTHER or "Other"
	for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do
		local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		local index = id and C_QuestLog.GetLogIndexForQuestID(id)
		local info = index and C_QuestLog.GetInfo(index)
		if id and not (info and (info.isTask or info.isBounty)) then
			local zone = QL.zoneOf[id] or fallback
			local group = byZone[zone]
			if not group then
				group = { zone = zone, rank = rank[zone] or math.huge, first = i, quests = {} }
				byZone[zone] = group
				groups[#groups + 1] = group
			end
			local quest = {
				id = id, index = index,
				title = (info and info.title) or C_QuestLog.GetTitleForQuestID(id) or "",
				complete = C_QuestLog.IsComplete(id) and true or false,
				failed = C_QuestLog.IsFailed(id) and true or false,
				autoComplete = info and info.isAutoComplete and true or false,
				tracked = id == tracked,
				questType = QL.QuestType(id, info),
			}
			quest.display = QL.DisplayTitle(id, quest.title)
			quest.item = QuestItem(index, quest.complete)
			group.quests[#group.quests + 1] = quest
		end
	end
	table.sort(groups, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.first < b.first
	end)
	return groups
end

-- Blizzard shows these pop-ups inside the quest section, so they'd go with it
function QL.Offers()
	local offers = {}
	for i = 1, GetNumAutoQuestPopUps() or 0 do
		local id, kind = GetAutoQuestPopUp(i)
		local title = id and C_QuestLog.GetTitleForQuestID(id)
		if title then offers[#offers + 1] = { id = id, kind = kind, title = title } end
	end
	return offers
end

-- one flat list of rows; key says which row it is from one update to the next
function QL.Flatten(groups, offers)
	local rows = {}
	local collapsed = cfg().collapsedZones
	local titleColor = TrackerColor("Header", GOLD)
	for _, o in ipairs(offers) do
		local label = o.kind == "OFFER" and "New quest: " or "Complete: "
		rows[#rows + 1] = { key = "offer:" .. o.id, kind = "offer", text = label .. o.title, color = titleColor, offer = o }
	end
	-- in a dungeon the whole list folds under one header, like the section above it
	local _, instanceType = IsInInstance()
	if #groups > 0 and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario") then
		local total = 0
		for _, group in ipairs(groups) do total = total + #group.quests end
		local closed = cfg().questsCollapsed and true or false
		rows[#rows + 1] = { key = "header", kind = "header", closed = closed, color = GOLD,
			text = ("%s (%d)"):format(_G.TRACKER_HEADER_QUESTS or "Quests", total) }
		if closed then return rows end
	end
	for _, group in ipairs(groups) do
		local closed = collapsed[group.zone] and true or false
		rows[#rows + 1] = { key = "zone:" .. group.zone, kind = "zone", zone = group.zone, closed = closed,
			text = ("%s (%d)"):format(group.zone, #group.quests), color = ns.ACCENT }
		if not closed then
			for _, quest in ipairs(group.quests) do
				rows[#rows + 1] = { key = "quest:" .. quest.id, kind = "quest", text = quest.display, color = titleColor, quest = quest }
				for n, line in ipairs(QL.QuestLines(quest)) do
					rows[#rows + 1] = { key = "line:" .. quest.id .. ":" .. n, kind = "line", text = line.text,
						color = line.color, quest = quest }
				end
			end
		end
	end
	return rows
end

---------------------------------------------------------------------------
-- Clicks: what a click on Blizzard's quest does
---------------------------------------------------------------------------
local function SecuredQuests()
	local rule = Enum.GameRule and Enum.GameRule.SecuredQuests
	return rule and C_GameRules and C_GameRules.IsGameRuleActive(rule) or false
end

-- The one place this calls Blizzard UI code: nothing else opens the quest log. It runs from your own
-- click and never in combat, when the map can't open from an addon.
function QL.OpenQuest(questID)
	if InCombatLockdown() then return end
	if SecuredQuests() then
		QuestUtil.OpenQuestDetails(questID)
	else
		QuestMapFrame_OpenToQuestDetails(questID)
	end
end

function QL.ClickOffer(offer)
	if offer.kind == "OFFER" then ShowQuestOffer(offer.id) else ShowQuestComplete(offer.id) end
	RemoveAutoQuestPopUp(offer.id)
	QL.Schedule()
end

function QL.ToggleTracked(questID)
	C_SuperTrack.SetSuperTrackedQuestID(C_SuperTrack.GetSuperTrackedQuestID() == questID and 0 or questID)
end

function QL.Menu(row, quest)
	local id = quest.id
	if not MenuUtil then return QL.ToggleTracked(id) end
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateTitle(quest.title)
		local tracked = C_SuperTrack.GetSuperTrackedQuestID() == id
		root:CreateButton(tracked and _G.STOP_SUPER_TRACK_QUEST or _G.SUPER_TRACK_QUEST, function() QL.ToggleTracked(id) end)
		root:CreateButton(_G.OBJECTIVES_VIEW_IN_QUESTLOG, function() QL.OpenQuest(id) end)
		if not SecuredQuests() and QuestUtil.CanRemoveQuestWatch() then
			root:CreateButton(_G.OBJECTIVES_STOP_TRACKING, function() C_QuestLog.RemoveQuestWatch(id) end)
		end
		if C_QuestLog.IsPushableQuest(id) and IsInGroup() then
			root:CreateButton(_G.SHARE_QUEST, function() QuestUtil.ShareQuest(id) end)
		end
	end)
end

function QL.ClickQuest(row, quest, button)
	local id = quest.id
	if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID and ChatFrameUtil.TryInsertQuestLinkForQuestID(id) then return end
	if button == "RightButton" then return QL.Menu(row, quest) end
	if not SecuredQuests() and IsModifiedClick("QUESTWATCHTOGGLE") then
		if QuestUtil.CanRemoveQuestWatch() then C_QuestLog.RemoveQuestWatch(id) end
	elseif quest.autoComplete and quest.complete then
		RemoveAutoQuestPopUp(id)
		ShowQuestComplete(id)
	else
		QL.OpenQuest(id)
	end
end

function QL.ToggleZone(zone)
	local collapsed = cfg().collapsedZones
	collapsed[zone] = (not collapsed[zone]) and true or nil
	QL.Update()
end

function QL.ToggleAll()
	local c = cfg()
	c.questsCollapsed = not c.questsCollapsed
	QL.Update()
end

local function OnRowClick(row, button)
	local data = row.data
	if not data then return end
	if data.kind == "header" then
		QL.ToggleAll()
	elseif data.kind == "zone" then
		QL.ToggleZone(data.zone)
	elseif data.kind == "offer" then
		QL.ClickOffer(data.offer)
	else
		QL.ClickQuest(row, data.quest, button)
	end
end

-- Hover: in a group, the party's progress on the quest, as on Blizzard's own quest blocks.
-- The tooltip fills itself from the quest ID; on clients without it there's no tooltip.
function QL.ShowPartyProgress(row, quest)
	if not (quest and IsInGroup() and GameTooltip.SetQuestPartyProgress) then return false end
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("TOPRIGHT", row, "TOPLEFT", 0, 0)
	GameTooltip:SetOwner(row, "ANCHOR_PRESERVE")
	GameTooltip:SetQuestPartyProgress(quest.id)
	return true
end

local function OnRowEnter(row)
	local data = row.data
	if data and (data.kind == "quest" or data.kind == "line") then
		row.tip = QL.ShowPartyProgress(row, data.quest) or nil
	end
end

local function OnRowLeave(row)
	if row.tip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
	row.tip = nil
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function GetRow(i)
	local row = QL.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, QL.list)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", OnRowClick)
	row:SetScript("OnEnter", OnRowEnter)
	row:SetScript("OnLeave", OnRowLeave)
	row.text = row:CreateFontString(nil, "OVERLAY")
	row.text:SetJustifyH("LEFT")
	row.text:SetJustifyV("TOP")
	local glow = row:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 1, 1, 0.06)
	-- plus/minus as two lines: every font has its own idea of how wide those are
	row.dash = row:CreateTexture(nil, "OVERLAY")
	row.dash:SetSize(BOX, 1)
	row.bar = row:CreateTexture(nil, "OVERLAY")
	row.bar:SetSize(1, BOX)
	row.bar:SetPoint("CENTER", row.dash, "CENTER")
	-- the line under the dungeon Quests header, as on the section headers around it
	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetHeight(1)
	row.rule:SetPoint("BOTTOMLEFT", 0, 0)
	row.rule:SetPoint("BOTTOMRIGHT", -24, 0)
	-- focus: the quest the quest marker points at
	local focus = CreateFrame("Button", nil, row)
	focus:SetSize(16, 16)
	focus:SetPoint("TOPLEFT", row, "TOPLEFT", 3, 2)
	focus:RegisterForClicks("LeftButtonUp")
	focus.dot = focus:CreateTexture(nil, "ARTWORK")
	focus.dot:SetSize(FOCUS_DOT, FOCUS_DOT)
	focus.dot:SetPoint("CENTER")
	-- outline and middle, set for each quest
	focus.hole = focus:CreateTexture(nil, "OVERLAY")
	focus.hole:SetSize(FOCUS_DOT - 4, FOCUS_DOT - 4)
	focus.hole:SetPoint("CENTER")
	local focusGlow = focus:CreateTexture(nil, "HIGHLIGHT")
	focusGlow:SetSize(FOCUS_DOT + 4, FOCUS_DOT + 4)
	focusGlow:SetPoint("CENTER")
	focusGlow:SetColorTexture(1, 1, 1, 0.25)
	focus:SetScript("OnClick", function(self)
		local data = self:GetParent().data
		if data and data.quest then QL.ToggleTracked(data.quest.id) end
	end)
	row.focus = focus
	QL.rows[i] = row
	return row
end

local function SetRowFont(row, size, flags)
	if row.fontSize == size and row.fontFlags == flags then return end
	row.fontSize, row.fontFlags = size, flags
	ns.SetFont(row.text, size, flags)
end

local function Paint(row, data)
	row.data = data
	row.text:SetText(data.text)
	row.text:SetTextColor(data.color[1], data.color[2], data.color[3])
	local isQuest = data.kind == "quest"
	row.focus:SetShown(isQuest)
	if isQuest then
		local outline, middle = QL.FocusColors(data.quest)
		row.focus.dot:SetColorTexture(outline[1], outline[2], outline[3], 1)
		row.focus.hole:SetColorTexture(middle[1], middle[2], middle[3], 1)
	end
end

-- returns the list's height
local function Layout(rows)
	local c = cfg()
	local flags = ns.OutlineFlags(c.outline) or ""
	local width = QL.list:GetWidth() or 0
	local y, blockEnd = 0, 0
	wipe(QL.itemRows)
	for i, data in ipairs(rows) do
		local row = GetRow(i)
		local isHeader = data.kind == "header"
		local isZone = data.kind == "zone" or isHeader
		if isZone or data.kind == "quest" or data.kind == "offer" then
			y = math.max(y, blockEnd) -- a quest item stands taller than a short quest
			if i > 1 then y = y + (isZone and ZONE_GAP or QUEST_GAP) end
		else
			y = y + TEXT_GAP
		end
		SetRowFont(row, isZone and c.headerSize or c.lineSize, flags)
		local item = data.quest and data.quest.item
		local indent = INDENT[data.kind]
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", indent, 0)
		row.text:SetWidth(math.max(1, width - indent - (item and ITEM_SIZE + 4 or 0)))
		Paint(row, data)
		local h = math.max(row.text:GetStringHeight() or 0, 1)
		if isHeader then h = h + 4 end -- room for the line
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", QL.list, "TOPLEFT", 0, -y)
		row:SetPoint("TOPRIGHT", QL.list, "TOPRIGHT", 0, -y)
		row:SetHeight(h)
		row.rule:SetShown(isHeader and c.flat and true or false)
		if isHeader then row.rule:SetColorTexture(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 0.7) end
		row.dash:SetShown(isZone)
		row.bar:SetShown(isZone and data.closed)
		if isZone then
			row.dash:ClearAllPoints()
			if isHeader then
				row.dash:SetPoint("RIGHT", row, "RIGHT", -3, 2) -- where Blizzard's sections have theirs
			else
				row.dash:SetPoint("LEFT", row, "LEFT", 1, 0)
			end
			row.dash:SetColorTexture(data.color[1], data.color[2], data.color[3], 1)
			row.bar:SetColorTexture(data.color[1], data.color[2], data.color[3], 1)
		end
		row:Show()
		if data.kind == "quest" and item then
			QL.itemRows[#QL.itemRows + 1] = { row = row, quest = data.quest }
			blockEnd = y + ITEM_SIZE
		end
		y = y + h
	end
	for i = #rows + 1, #QL.rows do
		QL.rows[i].data = nil
		QL.rows[i]:Hide()
	end
	return math.max(y, blockEnd)
end

-- in combat with an item button up: the words change, nothing moves
local function Retext(rows)
	local byKey = {}
	for _, data in ipairs(rows) do byKey[data.key] = data end
	for _, row in ipairs(QL.rows) do
		local data = row.data and byKey[row.data.key]
		if data then Paint(row, data) end
	end
	QL.dirty = true
end

---------------------------------------------------------------------------
-- Quest item buttons
---------------------------------------------------------------------------
local function CreateItemButton(i)
	local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	b:SetSize(ITEM_SIZE, ITEM_SIZE)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "item")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ns.CreateBackdrop(b, 0)
	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()
	b.count = b:CreateFontString(nil, "OVERLAY")
	b.count:SetPoint("BOTTOMRIGHT", -1, 1)
	ns.SetFont(b.count, 11, "OUTLINE")
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if self.logIndex then GameTooltip:SetQuestLogSpecialItem(self.logIndex) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:Hide()
	QL.buttons[i] = b
	return b
end

function QL.UpdateCooldowns()
	for _, b in ipairs(QL.buttons) do
		if b:IsShown() and b.logIndex then
			local start, duration = GetQuestLogSpecialItemCooldown(b.logIndex)
			if start and not ns.issecret(start) and not ns.issecret(duration) then
				b.cooldown:SetCooldown(start, duration)
			end
		end
	end
end

function QL.PlaceItems()
	if InCombatLockdown() then
		QL.dirty = true
		return
	end
	local list = QL.list
	local show = list and list:IsVisible() and not ns.Objectives.WantHidden()
	local n = 0
	if show then
		for i, entry in ipairs(QL.itemRows) do
			n = i
			local b, row, quest = QL.buttons[i] or CreateItemButton(i), entry.row, entry.quest
			local item = quest.item
			b:SetFrameStrata(list:GetFrameStrata())
			b:SetFrameLevel(list:GetFrameLevel() + 10)
			b:SetScale(list:GetEffectiveScale() / UIParent:GetEffectiveScale())
			b:SetAttribute("item", "item:" .. item.id)
			b.logIndex = quest.index
			b.icon:SetTexture(item.texture)
			b.count:SetText(item.charges and item.charges > 1 and item.charges or "")
			b:ClearAllPoints()
			-- same scale as the list, so its screen position works as an offset from UIParent's corner
			b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", list:GetRight() or 0, row:GetTop() or 0)
			b:Show()
		end
	end
	for i = n + 1, #QL.buttons do QL.buttons[i]:Hide() end
	QL.shownItems = n
	QL.placedLeft, QL.placedTop = list and list:GetLeft(), list and list:GetTop()
	QL.UpdateCooldowns()
end

---------------------------------------------------------------------------
-- Update and placement
---------------------------------------------------------------------------
local Update = ns.Timed("Quest list", function()
	local t, list = Tracker(), QL.list
	if not (t and list and QL.Wanted()) then return end
	local rows = QL.Flatten(QL.Build(), QL.Offers())
	if InCombatLockdown() and QL.shownItems > 0 then return Retext(rows) end
	QL.dirty = false
	local height = Layout(rows)
	list:SetHeight(math.max(height, 1))
	local has = #rows > 0
	local changed = has ~= QL.hasRows
	QL.hasRows = has
	list:SetShown(has and not t.isCollapsed)
	if changed then QL.Place() end
	QL.PlaceItems()
end)
QL.Update = Update

function QL.Schedule()
	if QL.scheduled or not QL.list then return end
	QL.scheduled = true
	C_Timer.After(0.2, function()
		QL.scheduled = false
		QL.Update()
	end)
end

local function Below(frame, prev, t, spacing, leftMargin)
	frame:ClearAllPoints()
	if prev then
		frame:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
	else
		frame:SetPoint("TOP", t, "TOP", 0, -(t.topModulePadding or 0))
	end
	frame:SetPoint("LEFT", t, "LEFT", leftMargin or 0, 0)
end

-- The same stacking as Blizzard's, with our list where its quest sections were. After Blizzard's
-- layout and straight away, so nothing is drawn in between.
function QL.Place()
	if QL.placing then return end -- our own background anchor, below
	local t, list = Tracker(), QL.list
	if not (t and list and t.modules) then return end
	local spacing = t.moduleSpacing or 0
	local showList = QL.hasRows and not t.isCollapsed
	local prev, past = nil, false
	for _, m in ipairs(t.modules) do
		if IsQuestModule(m) then
			m:ClearAllPoints()
			m:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -4000, 0)
			if not past and showList then
				Below(list, prev, t, spacing, 0)
				list:SetPoint("RIGHT", t, "RIGHT", 0, 0)
				prev = list
			end
			past = true
		elseif (m.contentsHeight or 0) > 0 and m:IsShown() then
			if past then Below(m, prev, t, spacing, m.leftMargin) end
			prev = m
		end
	end
	list:SetShown(showList and past or false)
	if prev and t.NineSlice and not t.isCollapsed then
		QL.placing = true
		t.NineSlice:SetPoint("BOTTOM", prev, "BOTTOM", 0, -(t.bottomModulePadding or 0))
		QL.placing = false
	end
end

function QL.Refresh()
	if QL.Active() then QL.Update() end
end

function QL.Setup()
	local t = Tracker()
	if QL.list or not (t and QL.Wanted()) then return end
	local list = CreateFrame("Frame", nil, t)
	QL.list = list
	list:SetFrameLevel(t:GetFrameLevel() + 2)
	list:SetWidth(t:GetWidth() or 0)
	list:SetHeight(1)
	-- buttons are on UIParent: bring them along when the tracker moves or goes away
	local since = 0
	list:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < 0.25 then return end
		since = 0
		if #QL.itemRows > 0 and not InCombatLockdown()
			and (list:GetLeft() ~= QL.placedLeft or list:GetTop() ~= QL.placedTop) then
			QL.PlaceItems()
		end
	end)
	list:SetScript("OnHide", QL.PlaceItems)
	list:SetScript("OnShow", QL.PlaceItems)
	-- Hooking Update alone isn't enough: Blizzard keeps its own copy of that function for routine
	-- updates, which skip the hook. Both kinds end by anchoring the background, so that's hooked too.
	-- Update still is, for when the tracker folds and there's no section left to anchor it to.
	local place = ns.Timed("Quest list", QL.Place)
	hooksecurefunc(t, "Update", place)
	if t.NineSlice then hooksecurefunc(t.NineSlice, "SetPoint", place) end
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_AUTOCOMPLETE", "QUEST_TURNED_IN",
		"QUEST_REMOVED", "SUPER_TRACKING_CHANGED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
		ns:On(event, QL.Schedule)
	end
	ns:On("BAG_UPDATE_COOLDOWN", function()
		if QL.shownItems > 0 then QL.UpdateCooldowns() end
	end)
	ns:On("PLAYER_REGEN_ENABLED", function()
		if QL.dirty then QL.Update() end
	end)
	QL.Update()
	QL.Place()
end
