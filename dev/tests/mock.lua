-- Minimal WoW client mock for smoke-testing Stinkie UI outside the game.
-- Unknown globals resolve to a permissive stub; frames record text, shown state and scripts.
MOCK = { unknownCalls = {}, time = 1000, timers = {}, events = {}, frames = {}, errors = {}, prints = {} }

local stubMT = {}
local STUB = setmetatable({}, stubMT)
stubMT.__index = function() return STUB end
stubMT.__call = function() return nil end
MOCK.STUB = STUB

-- frames ------------------------------------------------------------------
local Frame = {}
local METHODS = {}
for _, n in ipairs({ "Add","AddUnit","ClearUnits","FinalizeUnits","SetUiMapID","AddAuraGroup","AddDispelTypeTexture","AddKick","AddLine","Apply","ApplyCVars","ApplyConfig","ApplyPoint","ApplyRange","ApplyRoster","AttachBlizzard","Bind","BindAll","Button","CanChangeHitTestPoints","Check","Choice","Clear","ClearAllPoints","ClearFocus","Color","Column","CopyBox","CopyProfile","CreateAnimation","CreateAnimationGroup","CreateFontString","CreateLine","CreateRow","CreateTexture","CurrentProfileName","DecodeProfile","DeleteProfile","Dropdown","EditText","EnableKeyboard","EnableMouse","EnableMouseWheel","EnumerateActive","Evaluate","ExportProfile","Fetch","FillRow","FindRowForUnit","FindRowLoose","FontCheck","ForceUpdate","Gap","GetAllowRadialWheel","GetAlpha","GetAtlas","GetAttribute","GetCenter","GetCheckedTexture","GetChildren","GetColorRGB","GetDamageAbsorbs","GetEffectiveScale","GetFont","GetFontString","GetFrameLevel","GetHeight","GetHighlightTexture","GetID","GetMessageInfo","GetName","GetNormalTexture","GetNumMessages","GetParent","GetPoint","GetPreviousValues","GetProfileNames","GetPushedTexture","GetRGB","GetRegions","GetScale","GetScrollChild","GetSize","GetStatusBarTexture","GetStringWidth","GetText","GetTexture","GetTextureFileID","GetUnit","GetVertexColor","GetVerticalScroll","GetVerticalScrollRange","GetWidth","HasFocus","Hide","HideBlizzardCastbar","HighlightText","HookDRMixin","HookScript","ImportProfile","IsEditModeActive","IsEditing","IsMouseOver","IsMoverActive","IsObjectType","IsProtected","IsSelectingText","IsShown","LayoutRow","List","Next","Note","NudgeMover","On","OnChange","PlaceName","Play","Position","PreviewStacks","Print","ReadRoster","Register","RegisterEvent","RegisterForClicks","RegisterForDrag","RegisterModule","RegisterMover","RegisterUnitEvent","RemoveMaskTexture","Render","ResetProfile","Restore","RowIsHealer","RunOOC","SelectMover","SetAllPoints","SetAlpha","SetAlphaFromBoolean","SetApplicationCount","SetAtlas","SetAttribute","SetAuraGroupEnabled","SetAuraGroupFilterString","SetAuraGroupMaxFrameCount","SetAutoFocus","SetBlendMode","SetClampedToScreen","SetClipsChildren","SetColorTexture","SetCooldown","SetCooldownFromDurationObject","SetCountdownFont","SetCursorPosition","SetDamageAbsorbClampMode","SetDefaultAbbreviation","SetDesaturated","SetDrawEdge","SetDuration","SetDurationCooldown","SetEnabled","SetEndPoint","SetFlowLayoutAnchorPoint","SetFlowLayoutAxis","SetFlowLayoutGrowthDirection","SetFlowLayoutMaximumLineSize","SetFlowLayoutPadding","SetFocus","SetFont","SetFontString","SetFormatter","SetFrameLevel","SetFrameStrata","SetFromAlpha","SetGradient","SetHeight","SetHideCountdownNumbers","SetHorizTile","SetIcon","SetIgnoreParentAlpha","SetInventoryItem","SetItemByID","SetJustifyH","SetJustifyV","SetLocked","SetLooping","SetMaskTexture","SetMillisecondsThreshold","SetMinInterval","SetMinMaxValues","SetMovable","SetMoverAnchor","SetMoverPoint","SetMultiLine","SetObeyStepOnDrag","SetOrientation","SetOwner","SetParent","SetPoint","SetProfile","SetPropagateKeyboardInput","SetRGBA","SetReverse","SetReverseFill","SetRolesets","SetRotation","SetScale","SetScript","SetScrollChild","SetShadowColor","SetShadowOffset","SetShown","SetSize","SetSmoothing","SetSnapToPixelGrid","SetSpacing","SetSpellByID","SetStartPoint","SetStatusBarColor","SetStatusBarTexture","SetSwipeTexture","SetTestMode","SetTexCoord","SetTexelSnappingBias","SetText","SetTextColor","SetTextInsets","SetTexture","SetThickness","SetThumbTexture","SetTimerDuration","SetToAlpha","SetToTargetValue","SetTooltipAnchorPoint","SetUnit","SetValue","SetValueStep","SetVertexColor","SetVertexColorFromBoolean","SetVerticalScroll","SetWidth","SetWordWrap","SetupColorPickerAndShow","Show","ShowPreview","SkinAll","SkinScore","Slider","StartMoving","Stop","StopMovingOrSizing","TextList","TextStyle","ToggleOptions","TryBind","Unbind","UnregisterAllEvents","Update","UpdateActive","UpdateAllAuras","UpdateButtons","UpdateCarriers","UpdateHeader","UpdateHealer","UpdatePrediction","UpdatePreview","UpdateRaidFrames","UpdateResource","UpdateRespawn","UpdateRowHealth","UpdateRowPower","UpdateTargetHighlight","UpdateVisibility" }) do METHODS[n] = true end
local noop = function() return nil end
local FrameMT = { __index = function(t, k)
	local v = Frame[k]
	if v ~= nil then return v end
	if METHODS[k] then return noop end -- any other widget method: no-op
	return nil
end, __call = function(self) if self._autoGlobal then MOCK.unknownCalls[self._name] = (MOCK.unknownCalls[self._name] or 0) + 1 end return nil end }

local function NewObj(kind, name, parent)
	local o = setmetatable({ _kind = kind, _shown = true, _scripts = {}, _events = {}, _text = "", _w = 100, _h = 20, _parent = parent, _alpha = 1, _scale = 1, _children = {} }, FrameMT)
	if name then _G[name] = o; o._name = name end
	table.insert(MOCK.frames, o)
	return o
end
MOCK.NewObj = NewObj

function Frame:CreateTexture(name) return NewObj("Texture", name, self) end
function Frame:CreateFontString(name) return NewObj("FontString", name, self) end
function Frame:CreateLine(name) return NewObj("Line", name, self) end
function Frame:CreateMaskTexture(name) return NewObj("MaskTexture", name, self) end
function Frame:CreateAnimationGroup() return NewObj("AnimationGroup", nil, self) end
function Frame:CreateAnimation() return NewObj("Animation", nil, self) end
function Frame:SetText(t) self._text = t end
function Frame:GetText() return self._text end
function Frame:SetFormattedText(f, ...) self._text = string.format(f, ...) end
function Frame:Show() self._shown = true end
function Frame:Hide() if self._shown and self._scripts.OnHide then local f = self._scripts.OnHide; self._shown = false; f(self) end self._shown = false end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() return self._shown end
function Frame:SetScript(k, f) self._scripts[k] = f end
function Frame:GetScript(k) return self._scripts[k] end
function Frame:HookScript(k, f)
	local old = self._scripts[k]
	self._scripts[k] = function(...) if old then old(...) end f(...) end
end
function Frame:RegisterEvent(e) self._events[e] = true; MOCK.events[e] = MOCK.events[e] or {}; MOCK.events[e][self] = true end
function Frame:RegisterUnitEvent(e) self:RegisterEvent(e) end
function Frame:UnregisterEvent(e) self._events[e] = nil; if MOCK.events[e] then MOCK.events[e][self] = nil end end
function Frame:UnregisterAllEvents() for e in pairs(self._events) do self:UnregisterEvent(e) end end
function Frame:IsEventRegistered(e) return self._events[e] end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:GetSize() return self._w, self._h end
function Frame:GetCenter() return 500, 300 end
function Frame:GetLeft() return 450 end
function Frame:GetRight() return 550 end
function Frame:GetTop() return 310 end
function Frame:GetBottom() return 290 end
function Frame:GetScale() return self._scale end
function Frame:SetScale(s) self._scale = s end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetFrameStrata() return "MEDIUM" end
function Frame:SetClipsChildren(v) self._clips = v end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:GetAlpha() return self._alpha end
function Frame:GetFrameLevel() return self._level or 1 end
function Frame:SetFrameLevel(n) self._level = n end
function Frame:GetParent() return self._parent end
function Frame:SetParent(p) self._parent = p end
function Frame:SetFont() return true end
function Frame:GetFont() return "font", 12, "" end
function Frame:IsObjectType(t) return self._kind == t end
function Frame:GetObjectType() return self._kind end
function Frame:GetStatusBarTexture() self._sbt = self._sbt or NewObj("Texture", nil, self); return self._sbt end
function Frame:GetMinMaxValues() return self._min or 0, self._max or 1 end
function Frame:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Frame:GetValue() return self._value or 0 end
function Frame:SetValue(v) self._value = v end
function Frame:GetTextureFileID() return self._fileID end
function Frame:SetTexture(t) self._tex = t; if type(t) == "string" then self._fileID = MOCK.FILE_IDS[t] end end
function Frame:SetColorTexture(r, g, b, a) self._tex = "color" end
function Frame:GetStringWidth() return #(tostring(self._text)) * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:GetNumPoints() return 1 end
function Frame:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
function Frame:IsMouseOver() return false end
function Frame:HasFocus() return false end
function Frame:GetVerticalScroll() return 0 end
function Frame:GetVerticalScrollRange() return 0 end
function Frame:GetScrollChild() return self._scrollChild end
function Frame:SetScrollChild(c) self._scrollChild = c end
function Frame:IsProtected() return false end
function Frame:IsMouseEnabled() return self._mouse end
function Frame:EnableMouse(v) self._mouse = v end
function Frame:GetName() return self._name end
function Frame:GetChildren() return end
function Frame:GetRegions() return end
function Frame:GetAttribute(k) return self._attr and self._attr[k] end
function Frame:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function Frame:Click() if self._scripts.OnClick then self._scripts.OnClick(self, "LeftButton") end end
function Frame:CanChangeHitTestPoints() return true end
function Frame:SetAuraGroupCandidateFilters() end
function Frame:GetCursorPosition() return 0 end

MOCK.FILE_IDS = { ["Interface\\WorldStateFrame\\AllianceFlag"] = 137200, ["Interface\\WorldStateFrame\\HordeFlag"] = 137218 }

function CreateFrame(kind, name, parent) return NewObj(kind or "Frame", name, parent) end
UIParent = NewObj("Frame", "UIParent")
WorldFrame = NewObj("Frame", "WorldFrame")
function CreateFont(name) return NewObj("Font", name) end

function MOCK.Fire(event, ...)
	for f in pairs(MOCK.events[event] or {}) do
		local h = f._scripts.OnEvent
		if h then
			local ok, err = pcall(h, f, event, ...)
			if not ok then table.insert(MOCK.errors, event .. ": " .. tostring(err)) end
		end
	end
end

function MOCK.Advance(dt)
	local steps = math.max(1, math.floor(dt / 0.05))
	for _ = 1, steps do
		MOCK.time = MOCK.time + dt / steps
		for _, f in ipairs(MOCK.frames) do
			local u = f._scripts.OnUpdate
			if u and f._shown then
				local ok, err = pcall(u, f, dt / steps)
				if not ok then table.insert(MOCK.errors, "OnUpdate: " .. tostring(err)) end
			end
		end
	end
	local due = {}
	for i = #MOCK.timers, 1, -1 do
		if MOCK.timers[i].at <= MOCK.time then table.insert(due, table.remove(MOCK.timers, i)) end
	end
	for i = #due, 1, -1 do
		local ok, err = pcall(due[i].fn)
		if not ok then table.insert(MOCK.errors, "timer: " .. tostring(err)) end
	end
end

-- API -----------------------------------------------------------------
function GetTime() return MOCK.time end
function time() return 1762000000 + math.floor(MOCK.time) end
C_Timer = {
	After = function(s, fn) table.insert(MOCK.timers, { at = MOCK.time + s, fn = fn }) end,
	NewTicker = function(s, fn) return { Cancel = function() end } end,
	NewTimer = function(s, fn) table.insert(MOCK.timers, { at = MOCK.time + s, fn = fn }); return { Cancel = function() end } end,
}
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end table.insert(MOCK.prints, table.concat(t, " ")) end
function geterrorhandler() return function(e) table.insert(MOCK.errors, "handler: " .. tostring(e)) end end
function issecretvalue(v) return type(v) == "table" and v.__secret == true end
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function strlower(s) return string.lower(s) end
strsplit = function(sep, s) local out = {} local esc = sep:gsub("%p", "%%%0") for p in (s .. sep):gmatch("(.-)" .. esc) do out[#out + 1] = p end return unpack(out) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
function Mixin(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
function CreateFromMixins(...) return Mixin({}, ...) end
function hooksecurefunc(a, b, c)
	if type(a) == "table" then
		local old = a[b]
		a[b] = function(...) local r = { old and old(...) } c(...) return unpack(r) end
	else
		local old = _G[a]
		_G[a] = function(...) local r = { old and old(...) } b(...) return unpack(r) end
	end
end
bit = bit or { band = function(a, b)
	local out, place = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then out = out + place end
		a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
	end
	return out
end }
function InCombatLockdown() return false end
function UnitAffectingCombat() return false end
function IsInInstance() return MOCK.instanceType ~= "none", MOCK.instanceType end
MOCK.instanceType = "none"
function GetInstanceInfo() return MOCK.instanceName or "Stormwind", MOCK.instanceType, 0, "", MOCK.maxPlayers or 5, 0, false, MOCK.instanceID or 0 end
function UnitName(u) if u == "player" then return "Stinkie", nil end return MOCK.unitNames and MOCK.unitNames[u] end
function UnitClass(u) return "Warlock", "WARLOCK", 9 end
function UnitGUID(u) if u == "player" then return "Player-1-ABC" end return nil end
function UnitExists(u) return u == "player" or (MOCK.unitNames and MOCK.unitNames[u] ~= nil) end
function UnitFactionGroup() return "Horde" end
function UnitIsDeadOrGhost() return MOCK.dead or false end
function UnitPvpClassification(u) return MOCK.classification and MOCK.classification[u] end
function GetRealmName() return "Tichondrius" end
function GetNormalizedRealmName() return "Tichondrius" end
function GetNumGroupMembers() return 0 end
function IsInRaid() return false end
function IsInGroup() return false end
function GetBattlefieldArenaFaction() return MOCK.team or 0 end
function GetNumBattlefieldScores() return MOCK.scores and #MOCK.scores or 0 end
function GetNumBattlefieldFlagPositions() return MOCK.flags and #MOCK.flags or 0 end
function RequestBattlefieldScoreData() end
function GetAreaSpiritHealerTime() return MOCK.resTime or 0 end
function GetCurrentArenaSeason() return 40 end
function GetMaxBattlefieldID() return MOCK.queues and #MOCK.queues or 0 end
function GetBattlefieldStatus(i) local q = MOCK.queues[i]; if q then return q.status, q.name, q.size, q.rated, false, q.qt end return "none" end
function GetBattlefieldTimeWaited(i) return MOCK.queues[i].waited end
function GetBattlefieldEstimatedWaitTime(i) return MOCK.queues[i].est end
function GetAverageItemLevel() return 720, 718.6, 730 end
function GetClassInfo(i)
	local list = { { "Warrior", "WARRIOR", 1 }, { "Paladin", "PALADIN", 2 }, { "Hunter", "HUNTER", 3 }, { "Rogue", "ROGUE", 4 },
		{ "Priest", "PRIEST", 5 }, { "Death Knight", "DEATHKNIGHT", 6 }, { "Shaman", "SHAMAN", 7 }, { "Mage", "MAGE", 8 },
		{ "Warlock", "WARLOCK", 9 }, { "Monk", "MONK", 10 }, { "Druid", "DRUID", 11 }, { "Demon Hunter", "DEMONHUNTER", 12 }, { "Evoker", "EVOKER", 13 } }
	local c = list[i]
	if c then return c[1], c[2], c[3] end
end
function GetNumClasses() return 13 end
local SPECS = { [9] = { { 265, "Affliction" }, { 266, "Demonology" }, { 267, "Destruction" } }, [5] = { { 256, "Discipline" }, { 257, "Holy" }, { 258, "Shadow" } },
	[4] = { { 259, "Assassination" }, { 260, "Outlaw" }, { 261, "Subtlety" } }, [8] = { { 62, "Arcane" }, { 63, "Fire" }, { 64, "Frost" } } }
function GetSpecializationInfoForClassID(classID, i) local s = SPECS[classID] and SPECS[classID][i]; if s then return s[1], s[2], "", 100 + s[1], "DAMAGER" end end
function GetSpecializationInfoByID(id)
	for classID, list in pairs(SPECS) do for _, s in ipairs(list) do if s[1] == id then local _, file = GetClassInfo(classID) return id, s[2], "", 100 + id, "DAMAGER", file end end end
end
function GetSpecialization() return 3 end
function GetSpecializationInfo(i) return 267, "Destruction" end
function GetPvpTalentInfoByID(id) return id, "Talent" .. id end
function LoggingCombat() return false end
function GetCVar(name) return MOCK.cvars and MOCK.cvars[name] or "0" end
-- settings with a stored value and Blizzard's default (MOCK.cvarDefaults, else "0")
C_CVar = {
	GetCVar = function(name) return MOCK.cvars and MOCK.cvars[name] or "0" end,
	SetCVar = function(name, value) MOCK.cvars = MOCK.cvars or {}; MOCK.cvars[name] = tostring(value) end,
	GetCVarDefault = function(name) return MOCK.cvarDefaults and MOCK.cvarDefaults[name] or "0" end,
}
function GetCVarBool(name) return MOCK.cvars ~= nil and MOCK.cvars[name] == "1" end
function SetCVar(name, value) MOCK.cvars = MOCK.cvars or {}; MOCK.cvars[name] = value end
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
function UnitLevel(u) return MOCK.unitLevels and MOCK.unitLevels[u] end
function GetBuildInfo() return "12.1.5", "70688", "", 120105 end
function ReloadUI() end
function PlaySound() end
function RegisterUnitWatch() end
function UnregisterUnitWatch() end
function date(fmt, t) return os.date(fmt, t) end
StaticPopupDialogs = {}
function StaticPopup_Show() end
UISpecialFrames = {}
SlashCmdList = {}
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 0.5, g = 0.5, b = 0.5, colorStr = "ff888888" } end })
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
PixelUtil = { ConvertPixelsToUIForRegion = function(n) return n end, SetPoint = function() end, SetSize = function() end }
C_AddOns = { GetAddOnMetadata = function(a, k) if k == "Version" then return "0.27.0" end end, LoadAddOn = function(name) return MOCK.LoadAddOn(name) end, IsAddOnLoaded = function() return false end }
C_PvP = setmetatable({
	GetBattlefieldFlagPosition = function(i) local f = MOCK.flags[i]; if f then return f.x, f.y, f.tex end end,
	GetScoreInfo = function(i) return MOCK.scores[i] end,
	GetActiveMatchWinner = function() return MOCK.winner end,
	GetActiveMatchDuration = function() return 312 end,
	GetTeamInfo = function(i) return { ratingMMR = 1800 + i * 50 } end,
	GetCustomVictoryStatID = function() return MOCK.victoryStat or 0 end,
	IsRatedArena = function() return MOCK.bracket == "arena" end,
	IsArena = function() return MOCK.bracket == "arena" end,
	IsRatedSoloShuffle = function() return MOCK.bracket == "shuffle" end,
	IsSoloShuffle = function() return MOCK.bracket == "shuffle" end,
	IsRatedSoloRBG = function() return MOCK.bracket == "blitz" end,
	IsSoloRBG = function() return MOCK.bracket == "blitz" end,
	IsBattleground = function() return MOCK.bracket == "blitz" end,
	IsInBrawl = function() return false end,
	IsRatedBattleground = function() return false end,
	IsMatchComplete = function() return false end,
}, { __index = function() return function() return nil end end })
C_Map = setmetatable({
	GetBestMapForUnit = function() return MOCK.mapID end,
	GetMapWorldSize = function() return 1000, 600 end,
	GetMapInfo = function(id) return { name = MOCK.mapName or "Map" } end,
}, { __index = function() return function() return nil end end })
C_AreaPoiInfo = {
	GetAreaPOIForMap = function() local ids = {} for id in pairs(MOCK.pois or {}) do ids[#ids + 1] = id end table.sort(ids) return ids end,
	GetAreaPOIInfo = function(_, id) return MOCK.pois[id] end,
	GetAreaPOISecondsLeft = function() return nil end,
}
C_UIWidgetManager = setmetatable({
	GetTopCenterWidgetSetID = function() return 1 end,
	GetAllWidgetsBySetID = function() return MOCK.widgets or {} end,
	GetDoubleStatusBarWidgetVisualizationInfo = function(id) return MOCK.widgetInfo and MOCK.widgetInfo[id] end,
}, { __index = function() return function() return nil end end })
Enum = setmetatable({
	UIWidgetVisualizationType = { DoubleStatusBar = 3, DoubleStateIconRow = 7 },
	TooltipDataLineType = { ItemLevel = 31, ItemEnchantmentPermanent = 15, GemSocket = 3 },
	ItemClass = { Weapon = 2, Armor = 4 },
	PvPUnitClassification = { FlagCarrierHorde = 0, FlagCarrierAlliance = 1, FlagCarrierNeutral = 2 },
	StatusBarInterpolation = { ExponentialEaseOut = 1, Immediate = 0 },
}, { __index = function() return setmetatable({}, { __index = function() return 0 end }) end })
C_ClassTalents = { GetActiveConfigID = function() return 1 end, GetActiveHeroTalentSpec = function() return 58 end }
C_Traits = { GenerateImportString = function() return "C0PAAAAAAAAAAAAAAAAAAAAAAAAAAzMjZmZGGzMzMMDzYmZmZmZYGzMzMDAAAAAAgZbmZmZGzwMAAAAA" end, GetSubTreeInfo = function() return { name = "Diabolist" } end }
C_SpecializationInfo = { GetNumSpecializationsForClassID = function(c) return SPECS[c] and #SPECS[c] or 0 end, GetAllSelectedPvpTalentIDs = function() return { 3508, 5379, 5386 } end,
	GetSpecialization = function() return 3 end, GetSpecializationInfo = function() return 267, "Destruction" end }
C_EncodingUtil = nil

-- everything else: permissive stubs
MEMBERS_PER_RAID_GROUP = 5
PVP_ITEM_LEVEL_TOOLTIP = "PvP Item Level %d"
ENCHANTED_TOOLTIP_LINE = "Enchanted: %s"
STAT_CRITICAL_STRIKE = "Critical Strike"; STAT_HASTE = "Haste"; STAT_MASTERY = "Mastery"; STAT_VERSATILITY = "Versatility"
STAT_SPEED = "Speed"; STAT_LIFESTEAL = "Leech"; STAT_AVOIDANCE = "Avoidance"; STAT_MOVEMENT_SPEED = "Movement Speed"
ITEM_QUALITY_COLORS = { [0] = { r = 0.6, g = 0.6, b = 0.6 }, { r = 1, g = 1, b = 1 }, { r = 0.1, g = 1, b = 0 }, { r = 0, g = 0.44, b = 0.87 }, { r = 0.64, g = 0.21, b = 0.93 }, { r = 1, g = 0.5, b = 0 } }
MOCK.items = {}
function GetInventoryItemLink(unit, slot) local i = MOCK.items[slot]; return i and i.link end
function GetInventoryItemQuality(unit, slot) local i = MOCK.items[slot]; return i and i.quality end
ItemLocation = { CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end }
C_TooltipInfo = { GetInventoryItem = function(unit, slot) local i = MOCK.items[slot]; return i and { lines = i.lines } end }
C_WarbandScene = { SearchWarbandSceneEntries = function() return { 3, 7 } end, GetWarbandSceneEntry = function(id) return { name = "Camp " .. id, textureKit = "camp-" .. id } end }
C_Texture = { GetAtlasInfo = function(a) if a:find("^camp") then return { file = 5000, width = 1600, height = 900, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end end }
C_PaperDollInfo = { GetInspectItemLevel = function() return 721.333 end, GetMinItemLevel = function() return 0 end }
function GetFonts() return {} end
function CreateUnitHealPredictionCalculator() return setmetatable({}, { __index = function() return function() end end }) end
C_NamePlate = setmetatable({ GetNamePlates = function() return {} end }, { __index = function() return function() return nil end end })
C_Item = setmetatable({ GetItemCount = function() return 0 end,
	GetItemInfo = function(link) for _, i in pairs(MOCK.items) do if i.link == link then return i.name, link, i.quality, 1, 1, "", "", 1, i.loc, 1, 1, i.classID or 4 end end end,
	GetCurrentItemLevel = function(loc) local i = MOCK.items[loc.slot]; return i and i.ilvl end,
	GetDetailedItemLevelInfo = function() return nil end,
	GetItemUpgradeInfo = function(link) for _, i in pairs(MOCK.items) do if i.link == link then return i.up end end end,
	GetItemNumSockets = function(link) for _, i in pairs(MOCK.items) do if i.link == link then return i.sockets and #i.sockets or 0 end end return 0 end,
	GetItemGem = function(link, n) for _, i in pairs(MOCK.items) do if i.link == link and i.sockets and i.sockets[n] then return "Gem", "item:" .. i.sockets[n] end end end,
	GetItemIconByID = function() return 4242 end,
	GetItemStats = function(link) for _, i in pairs(MOCK.items) do if i.link == link then return i.stats end end end }, { __index = function() return function() return nil end end })
LibStub = nil
AnchorUtil = { FlowLayoutAxis = { Horizontal = 1, Vertical = 2 } }
C_DurationUtil = false
C_ClassColor = { GetClassColor = function() return CreateColor(0.5, 0.5, 0.5) end }
function UnitHealthPercent() return 100 end
function UnitHealth() return 1000 end
function UnitHealthMax() return 1000 end
CurveConstants = { ScaleTo100 = 1 }
function AbbreviateNumbers(n) return tostring(n) end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGB = function(self) return self.r, self.g, self.b end, GetRGBA = function(self) return self.r, self.g, self.b, self.a end } end
function UnitIsConnected() return true end
function UnitIsPlayer(u) return u == "player" end
function UnitReaction() return 2 end
NUM_CHAT_WINDOWS = 10
setmetatable(_G, { __index = function(t, k)
	if type(k) ~= "string" then return nil end
	if k:match("^StinkieUI") or k:match("^SLASH_") or k:match("^RatedTracker") then return nil end -- saved variables start empty
	if k:match("^[A-Z_]+$") then return k end -- localized string constants
	if k:match("^[a-z]") then return nil end -- lowercase globals (Lua / addon locals leaking)
	if k:match("^C_") or k:match("^Lib") then return STUB end
	-- Blizzard frames and functions: a mock frame that is also callable (returns nil)
	local o = NewObj("Frame", nil, nil)
	o._name = k
	o._autoGlobal = true
	rawset(t, k, o)
	return o
end })
-- WoW's string.format("%d") only takes 32-bit integers
local rawformat = string.format
string.format = function(fmt, ...)
	if type(fmt) == "string" and fmt:find("%%[%-%d]*d") then
		local args = { ... }
		local i = 0
		for spec in fmt:gmatch("%%[%-%+ #0]*%d*%.?%d*[%a%%]") do
			if spec ~= "%%" then
				i = i + 1
				if spec:sub(-1) == "d" and type(args[i]) == "number" and (args[i] > 2147483647 or args[i] < -2147483648) then
					error("integer overflow attempting to store " .. rawformat("%.0f", args[i]), 2)
				end
			end
		end
	end
	return rawformat(fmt, ...)
end
local rawpcall = pcall
function pcall(f, ...)
	local n, args = select("#", ...), { ... }
	return xpcall(function() return f(unpack(args, 1, n)) end, function(e) return tostring(e) .. "\n" .. debug.traceback("", 2):sub(1, 600) end)
end
function GetCursorPosition() return 500, 400 end
function debugprofilestop() return os.clock() * 1000 end
