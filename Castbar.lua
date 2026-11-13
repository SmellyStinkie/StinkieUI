-- StinkieUI: castbars. Secret-safe: bars are driven by duration objects, colors by booleans.
local _, ns = ...

local issecret = ns.issecret
local HOLD_TIME = 0.5

local castEvents = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
	"UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local timeFormatter
local function GetTimeFormatter()
	if not timeFormatter then
		timeFormatter = C_StringUtil.CreateSecondsFormatter()
		timeFormatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
		timeFormatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
		timeFormatter:SetMillisecondsThreshold(60)
	end
	return timeFormatter
end

local colorCache = {}
local function GetColor(key)
	local t = ns.db.colors[key]
	local c = colorCache[key]
	if not c then
		c = CreateColor(t[1], t[2], t[3], 1)
		colorCache[key] = c
	else
		c:SetRGBA(t[1], t[2], t[3], 1)
	end
	return c
end

local function ApplyInterruptColor(bar, notInterruptible)
	local tex = bar:GetStatusBarTexture()
	if issecret(notInterruptible) or type(notInterruptible) == "boolean" then
		tex:SetVertexColorFromBoolean(notInterruptible, GetColor("castNotInterruptible"), GetColor("castInterruptible"))
	else
		local c = ns.db.colors.castInterruptible
		tex:SetVertexColor(c[1], c[2], c[3], 1)
	end
end

---------------------------------------------------------------------------
-- Empower ranks (Evoker): a line on the bar where each rank is reached, with the rank's number.
-- The game gives each stage's share of the whole cast, the hold at full power last. Where it
-- hides those numbers (other players' casts in restricted PvP), there's nothing to place and the
-- bar shows without marks.
---------------------------------------------------------------------------
local RANK_NUMBER_MIN_HEIGHT = 14 -- thinner bars get the lines only

-- shares of the cast -> where along the bar (0 to 1) each rank is reached; nil when unknown
function ns.EmpowerMarks(parts)
	if issecret(parts) or type(parts) ~= "table" then return nil end
	local n = #parts
	if n < 2 then return nil end
	local total = 0
	for i = 1, n do
		local v = parts[i]
		if issecret(v) or type(v) ~= "number" then return nil end
		total = total + v
	end
	if total <= 0 then return nil end
	local marks, sum = {}, 0
	for i = 1, n - 1 do
		sum = sum + parts[i]
		marks[i] = sum / total
	end
	return marks
end

local function HideRanks(bar)
	if not bar.RankMarks then return end
	for _, m in ipairs(bar.RankMarks) do
		m.line:Hide()
		m.text:Hide()
	end
end

local function ShowRanks(bar)
	HideRanks(bar)
	if not (ns.db.castEmpowerRanks and bar.empowering and bar.unit and UnitEmpoweredStagePercentages) then return end
	local ok, parts = pcall(UnitEmpoweredStagePercentages, bar.unit)
	local marks = ok and ns.EmpowerMarks(parts) or nil
	if not marks then return end
	local width, height = bar:GetWidth() or 0, bar:GetHeight() or 0
	if width <= 0 then return end
	local px = ns.Pixel(bar)
	bar.RankMarks = bar.RankMarks or {}
	for i, at in ipairs(marks) do
		local m = bar.RankMarks[i]
		if not m then
			m = { line = bar:CreateTexture(nil, "OVERLAY", nil, 6), text = ns.CreateText(bar, 9, "RIGHT") }
			m.line:SetColorTexture(1, 1, 1, 0.9)
			m.text:SetTextColor(1, 1, 1, 0.9)
			bar.RankMarks[i] = m
		end
		m.line:ClearAllPoints()
		m.line:SetPoint("TOP", bar, "TOPLEFT", width * at, 0)
		m.line:SetPoint("BOTTOM", bar, "BOTTOMLEFT", width * at, 0)
		m.line:SetWidth(px * 2)
		m.line:Show()
		-- the number sits just before its line: the stretch that ends there is that rank charging
		m.text:ClearAllPoints()
		m.text:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", width * at - 2, 1)
		m.text:SetText(i)
		m.text:SetShown(height >= RANK_NUMBER_MIN_HEIGHT)
	end
end

local function Reset(bar)
	bar.casting, bar.channeling, bar.empowering = nil, nil, nil
	bar.castID = nil
	HideRanks(bar)
end

local function CastStart(bar, event)
	local unit = bar.unit
	if not unit then return end

	local direction = Enum.StatusBarTimerDirection.ElapsedTime
	local duration
	local name, displayName, _, _, _, isTradeSkill, _, notInterruptible, _, castID = UnitCastingInfo(unit)
	local isEmpowered
	if name then
		Reset(bar)
		bar.casting = true
		duration = UnitCastingDuration(unit)
	else
		name, displayName, _, _, _, isTradeSkill, notInterruptible, _, isEmpowered, _, castID = UnitChannelInfo(unit)
		if name then
			Reset(bar)
			if isEmpowered then
				bar.empowering = true
				duration = UnitEmpoweredChannelDuration(unit)
			else
				bar.channeling = true
				duration = UnitChannelDuration(unit)
				direction = Enum.StatusBarTimerDirection.RemainingTime
			end
		end
	end

	if not name then
		if bar.holdTime <= 0 or event ~= "UNIT_CHANGED" then
			Reset(bar)
			bar:Hide()
		end
		return
	end

	bar.holdTime = 0
	bar.castID = castID
	bar:SetAlpha(1)
	bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, direction)
	if bar.Time.binding then bar.Time.binding:SetDuration(duration) end
	if bar.Text then bar.Text:SetText(displayName) end
	ApplyInterruptColor(bar, bar.unit == "player" and false or notInterruptible)
	bar:Show()
	ShowRanks(bar)
end

local function CastUpdate(bar, event, castID)
	if not bar:IsShown() or not castID or bar.castID ~= castID then return end
	local unit = bar.unit
	local duration
	local direction = Enum.StatusBarTimerDirection.ElapsedTime
	if event == "UNIT_SPELLCAST_DELAYED" then
		duration = UnitCastingDuration(unit)
	elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
		duration = UnitEmpoweredChannelDuration(unit)
	else
		duration = UnitChannelDuration(unit)
		direction = Enum.StatusBarTimerDirection.RemainingTime
	end
	if not duration then return end
	bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, direction)
	if bar.Time.binding then bar.Time.binding:SetDuration(duration) end
	if event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then ShowRanks(bar) end
end

local function ShowEnd(bar, failed)
	if failed then
		local c = ns.db.colors.castFailed
		bar:GetStatusBarTexture():SetVertexColor(c[1], c[2], c[3], 1)
		if bar.Text then bar.Text:SetText(failed == "FAILED" and FAILED or INTERRUPTED) end
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar.holdTime = HOLD_TIME
	else
		bar.holdTime = 0
		bar:Hide()
	end
	Reset(bar)
end

local function OnEvent(bar, event, unit, ...)
	if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
		bar.holdTime = 0
		return CastStart(bar, event)
	end
	if unit ~= bar.unit then return end

	if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
		CastStart(bar, event)
	elseif event == "UNIT_SPELLCAST_STOP" then
		local _, _, castID = ...
		if bar:IsShown() and castID and bar.castID == castID then ShowEnd(bar) end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		local _, _, interruptedBy, castID = ...
		if bar:IsShown() and castID and bar.castID == castID then ShowEnd(bar, interruptedBy and "INTERRUPTED") end
	elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
		local _, _, _, interruptedBy, castID = ...
		if bar:IsShown() and castID and bar.castID == castID then ShowEnd(bar, interruptedBy and "INTERRUPTED") end
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
		local _, _, _, castID = ...
		if bar:IsShown() and castID and bar.castID == castID then ShowEnd(bar, "INTERRUPTED") end
	elseif event == "UNIT_SPELLCAST_FAILED" then
		local _, _, castID = ...
		if bar:IsShown() and castID and bar.castID == castID then ShowEnd(bar, "FAILED") end
	elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
		local _, _, castID = ...
		CastUpdate(bar, event, castID)
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		if bar:IsShown() and (bar.casting or bar.channeling or bar.empowering) and bar.unit ~= "player" then
			ApplyInterruptColor(bar, event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
		end
	end
end

local function OnUpdate(bar, elapsed)
	if bar.holdTime > 0 then
		bar.holdTime = bar.holdTime - elapsed
		bar:SetAlpha(math.max(0, bar.holdTime / HOLD_TIME))
		if bar.holdTime <= 0 then
			bar.holdTime = 0
			bar:Hide()
			bar:SetAlpha(1)
		end
	end
end

local CastbarMixin = {}

function CastbarMixin:SetUnit(unit)
	self:UnregisterAllEvents()
	self.unit = unit
	self.holdTime = 0
	Reset(self)
	if not unit then
		self:Hide()
		return
	end
	for _, e in ipairs(castEvents) do
		self:RegisterUnitEvent(e, unit)
	end
	if unit == "target" then self:RegisterEvent("PLAYER_TARGET_CHANGED") end
	if unit == "focus" then self:RegisterEvent("PLAYER_FOCUS_CHANGED") end
	CastStart(self, "UNIT_CHANGED")
end

function CastbarMixin:ForceUpdate()
	if self.unit then CastStart(self, "UNIT_CHANGED") end
end

-- cfg: { height, showText, showTime, textStyle } ; size and anchoring are done by the owner.
function CastbarMixin:ApplyConfig(cfg)
	local style = cfg.textStyle or ns.TextDefaults(11)
	ns.ApplyText(self.Text, style)
	ns.ApplyText(self.Time, style)
	self.Text:SetShown(cfg.showText ~= false)
	self.Time:SetShown(cfg.showTime ~= false)
	if self.Time.binding then self.Time.binding:SetEnabled(cfg.showTime ~= false) end
	ns.UpdateBackdrop(self)
end

-- Creates a castbar. The owner sets size/points and calls :SetUnit(unit).
function ns.CreateCastbar(parent, name)
	local bar = CreateFrame("StatusBar", name, parent)
	Mixin(bar, CastbarMixin)
	bar:SetStatusBarTexture(ns.TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:SetFrameLevel(parent:GetFrameLevel() + 5)
	ns.CreateBackdrop(bar)
	bar.holdTime = 0

	local text = ns.CreateText(bar, 11, "LEFT")
	text:SetPoint("LEFT", 4, 0)
	text:SetPoint("RIGHT", bar, "RIGHT", -40, 0)
	bar.Text = text

	local time = ns.CreateText(bar, 11, "RIGHT")
	time:SetPoint("RIGHT", -4, 0)
	bar.Time = time
	if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
		local binding = C_DurationUtil.CreateDurationTextBinding()
		binding:SetFormatter(GetTimeFormatter())
		binding:SetFontString(time)
		binding:SetEnabled(true)
		time.binding = binding
	end

	bar:SetScript("OnEvent", OnEvent)
	bar:SetScript("OnUpdate", ns.Timed("Castbars", OnUpdate))
	bar:Hide()
	return bar
end
