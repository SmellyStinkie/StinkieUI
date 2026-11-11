-- StinkieUI: Objectives (Blizzard's quest / objective tracker). Font, text sizes, scale, a flat
-- look (no gradients), a background with opacity, and hiding it in arenas, battlegrounds, raids or Mythic+.
-- Position and height stay in Edit Mode. Scale changes wait for combat to end.
-- Taint rules (0.33): never call the tracker's own update code (Update / UpdateAll) and never
-- Hide() it from here. Doing either ran Blizzard's tracker as Stinkie UI, which broke its layout
-- (gaps after finishing a quest) and threw "Auras cannot be accessed when secret while tainted"
-- through the scenario / Maw buff check and Edit Mode. Hiding is transparency only.
local _, ns = ...

local OB = {}
ns.Objectives = OB

local function cfg() return ns.db.objectives end

local function Tracker() return _G.ObjectiveTrackerFrame end

local function InstanceKind()
	local _, t, difficulty = GetInstanceInfo()
	if t == "arena" then return "arena" end
	if t == "pvp" then return "pvp" end
	if t == "raid" then return "raid" end
	if t == "party" then
		local mplus = (difficulty == 8) or (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive())
		return mplus and "mplus" or "dungeon"
	end
	return "world"
end

OB.InstanceKind = InstanceKind

function OB.WantHidden()
	local c = cfg()
	if not c.enabled then return false end
	local k = InstanceKind()
	return (k == "arena" and c.hideArena) or (k == "pvp" and c.hideBG) or (k == "raid" and c.hideRaid)
		or (k == "mplus" and c.hideMPlus) or (k == "dungeon" and c.hideDungeon) or false
end

---------------------------------------------------------------------------
-- Fonts: Blizzard's two font objects; every tracker line and header inherits them
---------------------------------------------------------------------------
function OB.ApplyFonts()
	local c = cfg()
	if not c.enabled then return end
	local flags = ns.OutlineFlags(c.outline) or ""
	if _G.ObjectiveTrackerLineFont then ns.SetFont(_G.ObjectiveTrackerLineFont, c.lineSize, flags) end
	if _G.ObjectiveTrackerHeaderFont then ns.SetFont(_G.ObjectiveTrackerHeaderFont, c.headerSize, flags) end
end

---------------------------------------------------------------------------
-- Background: our flat texture where Blizzard draws its own (it follows the tracker's content)
---------------------------------------------------------------------------
function OB.ApplyBackground()
	local t = Tracker()
	if not (t and t.NineSlice) then return end
	local c = cfg()
	if not OB.bg then
		OB.bg = CreateFrame("Frame", nil, t)
		OB.bg:SetFrameLevel(math.max(0, t:GetFrameLevel() - 1))
		OB.bg.tex = OB.bg:CreateTexture(nil, "BACKGROUND")
		OB.bg.tex:SetAllPoints()
		ns.CreateBackdrop(OB.bg, 0)
	end
	local bg = OB.bg
	bg:ClearAllPoints()
	if ns.QuestList.Active() then
		-- Blizzard's background leaves a strip on the left for its quest icons; our list has none
		bg:SetPoint("TOP", t.NineSlice, "TOP", 0, c.padding)
		bg:SetPoint("LEFT", t, "LEFT", -c.padding, 0)
	else
		bg:SetPoint("TOPLEFT", t.NineSlice, "TOPLEFT", -c.padding, c.padding)
	end
	bg:SetPoint("BOTTOMRIGHT", t.NineSlice, "BOTTOMRIGHT", c.padding, -c.padding)
	local col = c.bgColor
	bg.tex:SetColorTexture(col[1], col[2], col[3], c.bgAlpha)
	if bg.SUIBorder then for _, e in ipairs(bg.SUIBorder.edges) do e:SetShown(c.border) end end
	local on = c.enabled and c.background
	bg:SetShown(on and t.NineSlice:IsShown() and true or false)
	-- Blizzard's own background off while ours is on
	if c.enabled and c.hideBlizzardBg then
		t.NineSlice:SetAlpha(0)
	elseif OB.nineSliceTouched then
		t.NineSlice:SetAlpha(1)
	end
	OB.nineSliceTouched = c.enabled and c.hideBlizzardBg
end

-- Folded with its minus button, the tracker hides its sections but keeps their heights, and still
-- ends the background at the last hidden one. Ours follows that background, so end it at the header.
function OB.FitCollapsed()
	local t = Tracker()
	if OB.fitting or not (t and t.isCollapsed and t.Header and t.NineSlice and cfg().enabled) then return end
	OB.fitting = true
	t.NineSlice:SetPoint("BOTTOM", t.Header, "BOTTOM", 0, 0)
	OB.fitting = false
end

---------------------------------------------------------------------------
-- Flat look: no header gradients or bar art. Headers get a thin accent line, progress bars a flat
-- fill with a 1px border, quest item buttons a zoomed icon with a 1px border.
---------------------------------------------------------------------------
local function Hide(r) if r and r.SetAlpha then r:SetAlpha(0) end end

local function FlatHeader(header)
	if not header then return end
	Hide(header.Background)
	if not header.SUILine then
		header.SUILine = header:CreateTexture(nil, "ARTWORK")
		header.SUILine:SetHeight(1)
		header.SUILine:SetPoint("BOTTOMLEFT", 0, 1)
		header.SUILine:SetPoint("BOTTOMRIGHT", -24, 1)
	end
	header.SUILine:SetColorTexture(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 0.7)
	header.SUILine:Show()
end

local function FlatBar(pb)
	local bar = pb and pb.Bar
	if not bar or bar.SUIFlat then return end
	bar.SUIFlat = true
	for _, k in ipairs({ "BorderLeft", "BorderRight", "BorderMid", "BarFrame", "BarFrame2", "BarFrame3", "BarGlow", "Sheen", "Starburst", "IconBG", "BarBG" }) do Hide(bar[k]) end
	if bar.SetStatusBarTexture then bar:SetStatusBarTexture(ns.TEXTURE) end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if tex then tex:SetVertexColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 1) end
	local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)
	ns.CreateBackdrop(bar, 0)
	if bar.Icon then bar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
end

local function FlatItemButton(b)
	if not b or b.SUIFlat then return end
	b.SUIFlat = true
	Hide(b.NormalTexture or (b.GetNormalTexture and b:GetNormalTexture()))
	local icon = b.icon or b.Icon
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:ClearAllPoints()
		icon:SetAllPoints()
	end
	ns.CreateBackdrop(b, 0)
end

function OB.ApplyFlat()
	local t = Tracker()
	if not (t and cfg().enabled and cfg().flat) then return end
	FlatHeader(t.Header)
	if t.ForEachModule then
		t:ForEachModule(function(module)
			FlatHeader(module.Header)
			for _, pb in pairs(module.usedProgressBars or {}) do pcall(FlatBar, pb) end
			for _, pb in pairs(module.usedTimerBars or {}) do pcall(FlatBar, pb) end
			-- usedBlocks: template -> { key -> block }
			for _, list in pairs(module.usedBlocks or {}) do
				if type(list) == "table" then
					for _, block in pairs(list) do
						if type(block) == "table" and block.ItemButton then pcall(FlatItemButton, block.ItemButton) end
					end
				end
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Scale and visibility (out of combat only)
---------------------------------------------------------------------------
-- hidden = fully transparent (still there for the mouse); Blizzard keeps running it untouched,
-- so its layout stays right
function OB.ApplyAlpha()
	local t = Tracker()
	if not t then return end
	local hide = OB.WantHidden()
	if hide then
		t:SetAlpha(0)
		OB.hidden = true
	elseif OB.hidden then
		t:SetAlpha(1)
		OB.hidden = false
	end
end

function OB.ApplyFrame()
	local t = Tracker()
	if not t then return end
	OB.ApplyAlpha()
	ns:RunOOC(function()
		local c = cfg()
		if c.enabled then
			t:SetScale(c.scale)
			OB.scaled = true
		elseif OB.scaled then
			t:SetScale(1)
			OB.scaled = false
		end
	end)
end

---------------------------------------------------------------------------
-- Quest progress text ("Boars slain: 3/10"). Blizzard prints these yellow messages in its
-- message frame at the top of the screen, together with the red errors. With this on, the
-- yellow ones come to our own frame instead, which can be moved and sized; the red errors stay.
-- We only undo what we did, so another addon doing the same is left alone.
---------------------------------------------------------------------------
local QT = { lines = {} }
OB.QuestText = QT
QT.LINES = 3
QT.FADE = 0.6
local function qcfg() return cfg().questText end
local issecret = ns.issecret

local function LayoutLines()
	local c = qcfg()
	local step = (c.textStyle.size or 18) + 6
	QT.frame:SetSize(520, step * QT.LINES)
	QT.frame:SetScale(ns.db.scale)
	for i, line in ipairs(QT.lines) do
		ns.ApplyText(line.fs, c.textStyle)
		line.fs:ClearAllPoints()
		line.fs:SetPoint("TOP", QT.frame, "TOP", 0, -(i - 1) * step)
		line.fs:SetWidth(1000)
		line.fs:SetJustifyH("CENTER")
	end
	ns:ApplyPoint(QT.frame, c.point)
end

-- fade each line out once its time is up; the updater stops when nothing is showing
local function OnUpdate(_, dt)
	local any = false
	local hold = qcfg().duration or 3
	for _, line in ipairs(QT.lines) do
		if line.fs:IsShown() and not QT.preview then
			line.age = line.age + dt
			if line.age >= hold + QT.FADE then
				line.fs:Hide()
			else
				line.fs:SetAlpha(line.age <= hold and 1 or (1 - (line.age - hold) / QT.FADE))
				any = true
			end
		end
	end
	if not any and not QT.preview then QT.frame:SetScript("OnUpdate", nil) end
end

-- newest on top; the same text again just starts over (Blizzard does the same)
-- r, g, b: this line's own color (a battleground announcement); none = the color from the options
function QT.Add(msg, r, g, b)
	if msg == nil or not QT.frame then return end
	local top = QT.lines[1]
	local same = top.fs:IsShown() and not issecret(msg) and not issecret(top.text) and top.text == msg
	if not same then
		for i = QT.LINES, 2, -1 do
			local a, b2 = QT.lines[i], QT.lines[i - 1]
			a.text, a.age, a.color = b2.text, b2.age, b2.color
			a.fs:SetText(b2.text or "")
			a.fs:SetShown(b2.fs:IsShown())
			a.fs:SetAlpha(b2.fs:GetAlpha())
			if a.color then a.fs:SetTextColor(a.color[1], a.color[2], a.color[3]) end
		end
		top.text = msg
		top.fs:SetText(msg) -- a secret message can still be shown
	end
	if not r then
		local sc = qcfg().textStyle.color or { 1, 0.82, 0 }
		r, g, b = sc[1], sc[2], sc[3]
	end
	top.color = { r, g, b }
	top.fs:SetTextColor(r, g, b)
	top.age = 0
	top.fs:SetAlpha(1)
	top.fs:Show()
	QT.frame:SetScript("OnUpdate", OnUpdate)
end

-- unlocked (or the options' Show sample): a stand-in to place it by
function QT.SetPreview(on)
	if not QT.frame then return end
	QT.preview = on or nil
	if on then
		QT.lines[1].text, QT.lines[1].age = "Boars slain: 3/10", 0
		QT.lines[1].fs:SetText("Boars slain: 3/10")
		QT.lines[1].fs:SetAlpha(1)
		QT.lines[1].fs:Show()
		for i = 2, QT.LINES do QT.lines[i].fs:Hide() end
	else
		for _, line in ipairs(QT.lines) do line.fs:Hide() end
	end
end

---------------------------------------------------------------------------
-- Battleground announcements ("The mine cart has arrived...") in the same box. Blizzard shows them
-- in its warning frame in the top middle. Inside a battleground, and only for the events one of
-- its frames was really listening to, they come to ours instead; leaving hands them back.
---------------------------------------------------------------------------
QT.ANNOUNCE_EVENTS = { "RAID_BOSS_EMOTE", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL" }
QT.ANNOUNCE_FRAMES = { "RaidWarningFrame", "RaidBossEmoteFrame" }
QT.ANNOUNCE_COLORS = {
	RAID_BOSS_EMOTE = "RAID_BOSS_EMOTE",
	CHAT_MSG_BG_SYSTEM_ALLIANCE = "BG_SYSTEM_ALLIANCE",
	CHAT_MSG_BG_SYSTEM_HORDE = "BG_SYSTEM_HORDE",
	CHAT_MSG_BG_SYSTEM_NEUTRAL = "BG_SYSTEM_NEUTRAL",
}
QT.taking = {} -- { frame, event } pairs taken from Blizzard's frames

local function InBattleground()
	local _, t = IsInInstance()
	return t == "pvp"
end

function QT.ApplyAnnounce()
	if not QT.frame then return end
	local c = qcfg()
	local want = (c.enabled and c.bgAnnounce and InBattleground()) and true or false
	if want == (QT.announcing or false) then return end
	QT.announcing = want
	if want then
		for _, event in ipairs(QT.ANNOUNCE_EVENTS) do
			local took = false
			for _, name in ipairs(QT.ANNOUNCE_FRAMES) do
				local frame = _G[name]
				if frame and frame.IsEventRegistered and frame:IsEventRegistered(event) then
					frame:UnregisterEvent(event)
					QT.taking[#QT.taking + 1] = { frame, event }
					took = true
				end
			end
			-- one nobody was showing on screen stays where it was (the chat window)
			if took then QT.frame:RegisterEvent(event) end
		end
	else
		for _, pair in ipairs(QT.taking) do
			pair[1]:RegisterEvent(pair[2])
			QT.frame:UnregisterEvent(pair[2])
		end
		wipe(QT.taking)
	end
end

function QT.OnAnnounce(event, message, playerName, _, playSound)
	local body = message
	if event == "RAID_BOSS_EMOTE" then
		-- the text can have a place for a name; if it can't be filled in here it's shown as it came
		local ok, text = pcall(string.format, message, playerName, playerName)
		if ok then body = text end
		if not issecret(playSound) and playSound and SOUNDKIT and SOUNDKIT.RAID_BOSS_EMOTE_WARNING then
			PlaySound(SOUNDKIT.RAID_BOSS_EMOTE_WARNING)
		end
	end
	local info = ChatTypeInfo and ChatTypeInfo[QT.ANNOUNCE_COLORS[event]]
	if info and info.r then QT.Add(body, info.r, info.g, info.b) else QT.Add(body) end
end

function OB.ApplyQuestText()
	local c = qcfg()
	local on = c.enabled and true or false
	if on and not QT.frame then
		local f = CreateFrame("Frame", "StinkieUI_QuestText", UIParent)
		f:SetFrameStrata("HIGH")
		QT.frame = f
		for i = 1, QT.LINES do
			local fs = f:CreateFontString(nil, "OVERLAY")
			fs:SetWordWrap(false)
			fs:Hide()
			QT.lines[i] = { fs = fs, age = 0 }
		end
		ns:RegisterMover("questText", f, "Quest Progress Text",
			function() return qcfg().point end,
			function(p) qcfg().point = p end)
		f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
			if event == "UI_INFO_MESSAGE" then
				QT.Add(a2)
			else
				local ok, err = pcall(QT.OnAnnounce, event, a1, a2, a3, a4)
				if not ok then ns.Error(err) end
			end
		end)
		ns:On("PLAYER_ENTERING_WORLD", function() QT.ApplyAnnounce() end)
		ns:On("ZONE_CHANGED_NEW_AREA", function() QT.ApplyAnnounce() end)
		table.insert(ns.lockCallbacks, function(unlocked)
			if qcfg().enabled then QT.SetPreview(unlocked) end
		end)
	end
	if QT.frame then
		LayoutLines()
		if on then QT.frame:RegisterEvent("UI_INFO_MESSAGE") else QT.frame:UnregisterEvent("UI_INFO_MESSAGE") end
		QT.frame:SetShown(on)
	end
	-- hand Blizzard's frame its yellow messages back only if we took them
	local blizz = _G.UIErrorsFrame
	if blizz and on ~= (QT.taken or false) then
		QT.taken = on
		if on then blizz:UnregisterEvent("UI_INFO_MESSAGE") else blizz:RegisterEvent("UI_INFO_MESSAGE") end
	end
	QT.ApplyAnnounce()
end

function OB:Init()
	-- the quest progress text doesn't need the tracker
	OB.ApplyQuestText()
	local t = Tracker()
	if not t then
		-- the tracker addon loads later on some logins
		ns:On("ADDON_LOADED", function(_, name)
			if name == "Blizzard_ObjectiveTracker" and not OB.ready and Tracker() then OB:Init() end
		end)
		return
	end
	if OB.ready then return end
	OB.ready = true
	-- Blizzard swaps the font objects when its text size setting changes; put ours back
	if _G.ObjectiveTrackerManager and _G.ObjectiveTrackerManager.SetTextSize then
		hooksecurefunc(_G.ObjectiveTrackerManager, "SetTextSize", function() OB.ApplyFonts() end)
	end
	-- the tracker shows itself whenever it has content; hide it again where it should be hidden
	t:HookScript("OnShow", function()
		OB.ApplyAlpha()
		OB.ApplyBackground()
	end)
	if t.NineSlice then
		t.NineSlice:HookScript("OnShow", function() OB.ApplyBackground() end)
		t.NineSlice:HookScript("OnHide", function() if OB.bg then OB.bg:Hide() end end)
	end
	-- restyle after Blizzard lays the tracker out (new quests, bars, item buttons)
	if t.Update then
		local queued = false
		hooksecurefunc(t, "Update", function()
			OB.FitCollapsed()
			if queued then return end
			queued = true
			C_Timer.After(0, function() queued = false; pcall(OB.ApplyFlat) end)
		end)
	end
	-- Blizzard's routine updates skip the Update hook but always anchor this
	if t.NineSlice then hooksecurefunc(t.NineSlice, "SetPoint", OB.FitCollapsed) end
	ns:On("PLAYER_ENTERING_WORLD", function() OB.ApplyFrame() end)
	ns:On("ZONE_CHANGED_NEW_AREA", function() OB.ApplyFrame() end)
	ns:On("CHALLENGE_MODE_START", function() OB.ApplyFrame() end)
	ns.QuestList.Setup()
	OB:Refresh()
end

function OB:Refresh()
	OB.ApplyQuestText()
	if not Tracker() then return end
	OB.ApplyFonts()
	OB.ApplyBackground()
	pcall(OB.ApplyFlat)
	OB.ApplyFrame()
	ns.QuestList.Refresh()
	-- new text sizes show on the tracker's next update (any quest change, zone or /reload)
end

ns:RegisterModule("Objectives", OB)
