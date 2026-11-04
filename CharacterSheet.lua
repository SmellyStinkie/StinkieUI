-- StinkieUI: Character Sheet. Adds to Blizzard's character frame (and the inspect frame, so
-- they look the same):
--   * a background behind the model: any warband camp scene, a flat dark one, Blizzard's own,
--     or any texture / atlas you name
--   * next to each item: its name or its upgrade track ("Mythic 6/6", track-colored), item level,
--     PvP item level for gear that scales in PvP, gem icons (empty sockets shown), the enchant,
--     or "Enchant Missing" in red on slots that can be enchanted
--   * hovering a secondary or tertiary stat highlights the items that have it
--   * item level to two decimals: equipped, overall and PvP
--   * a flat look (no frame art, gradients or portrait; 1px borders) and a scale with a drag corner
-- Blizzard's frames are added to, not replaced; equipping, the model and the stat pane are theirs.
local _, ns = ...

local CS = {}
ns.CharacterSheet = CS

local issecret = ns.issecret
local function readable(v) return v ~= nil and not issecret(v) end
local function cfg() return ns.db.character end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
-- id, frame name suffix, side the text goes (RIGHT of a left-column icon, LEFT of a right-column one)
CS.SLOTS = {
	{ 1, "HeadSlot", "RIGHT" }, { 2, "NeckSlot", "RIGHT" }, { 3, "ShoulderSlot", "RIGHT" }, { 15, "BackSlot", "RIGHT" },
	{ 5, "ChestSlot", "RIGHT" }, { 4, "ShirtSlot", "RIGHT" }, { 19, "TabardSlot", "RIGHT" }, { 9, "WristSlot", "RIGHT" },
	{ 10, "HandsSlot", "LEFT" }, { 6, "WaistSlot", "LEFT" }, { 7, "LegsSlot", "LEFT" }, { 8, "FeetSlot", "LEFT" },
	{ 11, "Finger0Slot", "LEFT" }, { 12, "Finger1Slot", "LEFT" }, { 13, "Trinket0Slot", "LEFT" }, { 14, "Trinket1Slot", "LEFT" },
	{ 16, "MainHandSlot", "LEFT" }, { 17, "SecondaryHandSlot", "RIGHT" },
}
-- slots that take a permanent enchant in Midnight: helm, shoulders, chest, legs, boots, rings, weapons
CS.ENCHANTABLE = { [1] = true, [3] = true, [5] = true, [7] = true, [8] = true, [11] = true, [12] = true, [16] = true, [17] = "weapon" }
CS.NO_INFO = { [4] = true, [19] = true } -- shirt, tabard: name only

-- secondary / tertiary stats: stat pane label -> item stat key
CS.STAT_KEYS = {
	crit = "ITEM_MOD_CRIT_RATING_SHORT", haste = "ITEM_MOD_HASTE_RATING_SHORT", mastery = "ITEM_MOD_MASTERY_RATING_SHORT",
	versatility = "ITEM_MOD_VERSATILITY", speed = "ITEM_MOD_CR_SPEED_SHORT", leech = "ITEM_MOD_CR_LIFESTEAL_SHORT",
	avoidance = "ITEM_MOD_CR_AVOIDANCE_SHORT",
}
local function StatForLabel(label)
	if not readable(label) then return nil end
	label = label:gsub(":%s*$", ""):gsub("%s+$", "")
	local map = {
		[STAT_CRITICAL_STRIKE or "Critical Strike"] = "crit", [STAT_HASTE or "Haste"] = "haste", [STAT_MASTERY or "Mastery"] = "mastery",
		[STAT_VERSATILITY or "Versatility"] = "versatility", [STAT_SPEED or "Speed"] = "speed", [STAT_LIFESTEAL or "Leech"] = "leech",
		[STAT_AVOIDANCE or "Avoidance"] = "avoidance", [STAT_MOVEMENT_SPEED or "Movement Speed"] = "speed",
	}
	return map[label]
end
CS.StatForLabel = StatForLabel

---------------------------------------------------------------------------
-- Upgrade track colors (Adventurer white ... Myth orange); unknown tracks use the item quality
---------------------------------------------------------------------------
local TRACK_QUALITY = { explorer = 0, adventurer = 1, veteran = 2, champion = 3, hero = 4, myth = 5, mythic = 5 }
function CS.TrackColor(track, quality)
	local q = track and TRACK_QUALITY[tostring(track):lower()] or quality
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

---------------------------------------------------------------------------
-- Reading one equipped item (player or inspected unit)
---------------------------------------------------------------------------
-- Turns a Blizzard format string ("PvP Item Level %d", "Enchanted: %s") into a pattern that
-- captures the value.
local function esc(str) return (str:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")) end
local function FormatPattern(f, token, capture)
	if type(f) ~= "string" then return false end
	local a, b = f:match("^(.-)%%" .. token .. "(.*)$")
	if not a then return false end
	return "^" .. esc(a) .. capture .. esc(b) .. "$"
end
CS.FormatPattern = FormatPattern

local pvpPattern
local function PvPPattern()
	if pvpPattern == nil then pvpPattern = FormatPattern(PVP_ITEM_LEVEL_TOOLTIP, "d", "(%d+)") end
	return pvpPattern
end

local enchantPattern
local function EnchantText(s)
	if enchantPattern == nil then enchantPattern = FormatPattern(ENCHANTED_TOOLTIP_LINE or "Enchanted: %s", "s", "(.+)") end
	return (enchantPattern and s:match(enchantPattern)) or s
end

-- item info for a slot: { link, quality, name, ilvl, pvp, track, cur, max, sockets = { icon|false }, enchant, enchantable }
function CS.ReadSlot(unit, slot)
	local link = GetInventoryItemLink(unit, slot)
	if not readable(link) then return nil end
	local info = { link = link, slot = slot }
	local name, _, quality, _, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(link)
	info.name, info.quality, info.classID = name, quality or GetInventoryItemQuality(unit, slot), classID
	-- item level: exact for yourself, from the tooltip (or the link) for someone else
	if unit == "player" and ItemLocation and C_Item.GetCurrentItemLevel then
		local ok, lvl = pcall(C_Item.GetCurrentItemLevel, ItemLocation:CreateFromEquipmentSlot(slot))
		if ok and readable(lvl) then info.ilvl = lvl end
	end
	-- tooltip: PvP item level, enchant text, item level for inspected units
	local data = C_TooltipInfo and C_TooltipInfo.GetInventoryItem and C_TooltipInfo.GetInventoryItem(unit, slot)
	local pat = PvPPattern()
	local LT = Enum and Enum.TooltipDataLineType or {}
	for _, line in ipairs(data and data.lines or {}) do
		local text = readable(line.leftText) and line.leftText or nil
		if text then
			if pat and not info.pvp then
				local v = text:match(pat)
				if v then info.pvp = tonumber(v) end
			end
			if line.type == LT.ItemEnchantmentPermanent then info.enchant = EnchantText(text) end
			if line.type == LT.ItemLevel and not info.ilvl then info.ilvl = tonumber(text:match("(%d+)")) end
		end
	end
	if not info.ilvl and C_Item.GetDetailedItemLevelInfo then info.ilvl = C_Item.GetDetailedItemLevelInfo(link) end
	-- upgrade track
	local ok, up = pcall(C_Item.GetItemUpgradeInfo, link)
	if ok and type(up) == "table" and readable(up.trackString) and up.trackString ~= "" then
		info.track, info.cur, info.max = up.trackString, up.currentLevel, up.maxLevel
	end
	-- gems
	info.sockets = {}
	local n = C_Item.GetItemNumSockets and C_Item.GetItemNumSockets(link) or 0
	for i = 1, (readable(n) and n or 0) do
		local _, gemLink = C_Item.GetItemGem(link, i)
		local icon = false
		if gemLink then icon = C_Item.GetItemIconByID(gemLink) or GetItemIcon and GetItemIcon(gemLink) or 134400 end
		info.sockets[i] = icon
	end
	-- enchant: the link's enchant field
	local enchantID = tonumber(link:match("item:%d+:(%d*)") or "") or 0
	info.enchanted = enchantID > 0
	local e = CS.ENCHANTABLE[slot]
	info.enchantable = (e == true) or (e == "weapon" and classID == (Enum.ItemClass and Enum.ItemClass.Weapon or 2))
	info.equipLoc = equipLoc
	return info
end

---------------------------------------------------------------------------
-- Overlays on a slot button
---------------------------------------------------------------------------
local EMPTY_SOCKET = [[Interface\ItemSocketingFrame\UI-EmptySocket-Prismatic]]

local function Overlay(button, side)
	if button.SUISheet then return button.SUISheet end
	local o = CreateFrame("Frame", nil, button)
	o:SetSize(1, 1)
	o:SetFrameLevel(button:GetFrameLevel() + 2)
	o.side = side
	o.line1 = o:CreateFontString(nil, "OVERLAY")
	o.line2 = o:CreateFontString(nil, "OVERLAY")
	o.line3 = o:CreateFontString(nil, "OVERLAY")
	o.gems = {}
	-- stat highlight: a bright edge around the icon
	local hl = CreateFrame("Frame", nil, button)
	hl:SetPoint("TOPLEFT", -2, 2)
	hl:SetPoint("BOTTOMRIGHT", 2, -2)
	hl:SetFrameLevel(button:GetFrameLevel() + 5)
	hl.edges = {}
	for i = 1, 4 do
		local t = hl:CreateTexture(nil, "OVERLAY")
		hl.edges[i] = t
	end
	local e = hl.edges
	e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(2)
	e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(2)
	e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(2)
	e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(2)
	hl:Hide()
	o.highlight = hl
	button.SUISheet = o
	return o
end

local function LayoutOverlay(o, button)
	local c = cfg()
	local side = o.side
	local justify = side == "RIGHT" and "LEFT" or "RIGHT"
	local anchor = side == "RIGHT" and "LEFT" or "RIGHT"
	local gap = side == "RIGHT" and 6 or -6
	o:ClearAllPoints()
	o:SetPoint(anchor, button, side, gap, 0)
	for _, fs in ipairs({ o.line1, o.line2, o.line3 }) do
		fs:SetJustifyH(justify)
		fs:SetWordWrap(false)
		fs:SetWidth(c.textWidth)
	end
	ns.ApplyText(o.line1, c.nameStyle)
	ns.ApplyText(o.line2, c.infoStyle)
	ns.ApplyText(o.line3, c.infoStyle)
	local col = c.highlightColor
	for _, t in ipairs(o.highlight.edges) do t:SetColorTexture(col[1], col[2], col[3], 1) end
end

-- gem icons outside the slot icon, on the side away from the text: stacked left of left-column
-- icons, right of right-column icons, in a row above the weapons
local BOTTOM_SLOTS = { [16] = true, [17] = true }
local function PlaceGems(o, button, slot, sockets, size)
	for _, t in ipairs(o.gems) do t:Hide() end
	local n = #sockets
	for i, icon in ipairs(sockets) do
		local t = o.gems[i]
		if not t then t = o:CreateTexture(nil, "OVERLAY"); o.gems[i] = t end
		t:SetSize(size, size)
		if icon then
			t:SetTexture(icon)
			t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		else
			t:SetTexture(EMPTY_SOCKET) -- empty socket
			t:SetTexCoord(0, 1, 0, 1)
		end
		t:ClearAllPoints()
		local offset = ((n - 1) / 2 - (i - 1)) * (size + 2)
		if BOTTOM_SLOTS[slot] then
			t:SetPoint("BOTTOM", button, "TOP", -offset, 3)
		elseif o.side == "RIGHT" then
			t:SetPoint("RIGHT", button, "LEFT", -3, offset)
		else
			t:SetPoint("LEFT", button, "RIGHT", 3, offset)
		end
		t:Show()
	end
end

local GREEN, RED = "|cff40ff40", "|cffff3030"

-- Text for one item. Returns line1, line2, line3 (line3 excludes the gem icons, which are drawn)
function CS.Lines(info, c)
	if not info then return "", "", "" end
	local r, g, b = CS.TrackColor(nil, info.quality)
	local qhex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
	local trackText
	if info.track and info.cur and info.max then
		local tr, tg, tb = CS.TrackColor(info.track, info.quality)
		trackText = string.format("|cff%02x%02x%02x%s %d/%d|r", tr * 255, tg * 255, tb * 255, info.track, info.cur, info.max)
	end
	local name = info.name and ("|cff" .. qhex .. info.name .. "|r") or nil
	if CS.NO_INFO[info.slot] then return (c.line1 ~= "none" and name) or "", "", "" end
	-- item level, PvP item level (only where it differs) and the upgrade track share one line
	local parts = {}
	if c.ilvl and info.ilvl then parts[#parts + 1] = "|cff" .. qhex .. info.ilvl .. "|r" end
	if c.pvp and info.pvp and info.pvp ~= info.ilvl then parts[#parts + 1] = "|cffb0b0ffPvP " .. info.pvp .. "|r" end
	local showTrack = trackText and (c.line1 == "track" or c.track)
	if showTrack then parts[#parts + 1] = trackText end
	local levels = table.concat(parts, "  ")
	local line1, line2
	if c.line1 == "name" then
		line1, line2 = name or "", levels
	elseif c.line1 == "track" then
		-- track instead of the name: the levels and track are the first line (name if there's no track)
		if trackText then line1, line2 = levels, "" else line1, line2 = name or "", levels end
	else
		line1, line2 = levels, ""
	end
	local line3 = ""
	if c.enchants then
		if info.enchanted and info.enchant then
			line3 = GREEN .. (c.enchantNames and info.enchant or "Enchanted") .. "|r"
		elseif info.enchanted then
			line3 = GREEN .. "Enchanted|r"
		elseif info.enchantable and c.missing then
			line3 = RED .. "Enchant Missing|r"
		end
	end
	return line1, line2, line3
end

function CS.UpdateButton(button, unit, slot, side)
	local c = cfg()
	local o = Overlay(button, side)
	LayoutOverlay(o, button)
	local ok, info = pcall(CS.ReadSlot, unit, slot)
	if not ok then info = nil end
	o.info = info
	local l1, l2, l3 = CS.Lines(info, c)
	local sockets = (c.gems and info and not CS.NO_INFO[slot]) and info.sockets or {}
	PlaceGems(o, button, slot, sockets, c.gemSize)
	local rows = {}
	if l1 ~= "" then rows[#rows + 1] = { o.line1, l1 } else o.line1:Hide() end
	if l2 ~= "" then rows[#rows + 1] = { o.line2, l2 } else o.line2:Hide() end
	if l3 ~= "" then rows[#rows + 1] = { o.line3, l3 } else o.line3:Hide() end
	-- rows stacked around the icon's middle
	local lh = c.infoStyle.size + 3
	local total = #rows * lh
	local anchor = side == "RIGHT" and "LEFT" or "RIGHT"
	for i, row in ipairs(rows) do
		local fs, text = row[1], row[2]
		fs:ClearAllPoints()
		fs:SetPoint(anchor, o, anchor, 0, total / 2 - (i - 0.5) * lh)
		fs:SetWidth(c.textWidth)
		fs:SetText(text)
		fs:Show()
	end
	o:SetShown(c.enabled and true or false)
	if c.enabled and c.flat and button.SUIEdge and CS.ColorSlotBorder then CS.ColorSlotBorder(button, info and info.quality) end
end

---------------------------------------------------------------------------
-- Frames (player and inspect)
---------------------------------------------------------------------------
local function EachSlot(prefix, fn)
	for _, s in ipairs(CS.SLOTS) do
		local b = _G[prefix .. s[2]]
		if b then fn(b, s[1], s[3]) end
	end
end

local function UpdateAll(prefix, unit)
	if not cfg().enabled then
		EachSlot(prefix, function(b) if b.SUISheet then b.SUISheet:Hide() end end)
		return
	end
	EachSlot(prefix, function(b, slot, side) CS.UpdateButton(b, unit, slot, side) end)
end

local pending = {}
local function Queue(prefix, unit)
	if pending[prefix] then return end
	pending[prefix] = true
	C_Timer.After(0.05, function()
		pending[prefix] = nil
		local ok, err = pcall(UpdateAll, prefix, unit)
		if not ok then geterrorhandler()(err) end
		if prefix == "Character" then CS.UpdateItemLevel() else CS.UpdateInspectItemLevel() end
	end)
end
CS.Queue = Queue

-- stat highlight
function CS.Highlight(prefix, statKey)
	local key = statKey and CS.STAT_KEYS[statKey]
	EachSlot(prefix, function(b)
		local o = b.SUISheet
		if o then
			local on = false
			if key and o.info and o.info.link then
				local stats = C_Item.GetItemStats(o.info.link)
				on = stats and readable(stats[key]) and stats[key] > 0 or false
			end
			o.highlight:SetShown(on and cfg().statHighlight and true or false)
		end
	end)
end

-- the stat row under the mouse gets a tint in the highlight color
function CS.HoverRow(row, on)
	if not row.SUIHover then
		row.SUIHover = row:CreateTexture(nil, "ARTWORK", nil, 1)
		row.SUIHover:SetAllPoints()
		row.SUIHover:Hide()
	end
	local c = cfg()
	if on and c.enabled and c.statHighlight then
		local col = c.highlightColor
		row.SUIHover:SetColorTexture(col[1], col[2], col[3], 0.22)
		row.SUIHover:Show()
	else
		row.SUIHover:Hide()
	end
end

local function HookStatFrames()
	local pane = _G.CharacterStatsPane
	if not (pane and pane.statsFramePool) then return end
	for f in pane.statsFramePool:EnumerateActive() do
		if not f.SUIStatHook then
			f.SUIStatHook = true
			f:HookScript("OnEnter", function(self)
				CS.HoverRow(self, true)
				if not cfg().statHighlight then return end
				local stat = self.Label and StatForLabel(self.Label:GetText())
				if stat then CS.Highlight("Character", stat) end
			end)
			f:HookScript("OnLeave", function(self) CS.HoverRow(self, false); CS.Highlight("Character", nil) end)
		end
	end
end

---------------------------------------------------------------------------
-- Stat list extras. Blizzard hides leech, avoidance, speed (and any stat at 0). We never edit
-- Blizzard's PAPERDOLL_STATCATEGORIES: doing that tainted the stat update, and in rated PvP
-- (secret stat values) it broke the whole character window. Instead we draw our own rows under
-- Blizzard's list, only for stats Blizzard left out, and only when the values are readable.
---------------------------------------------------------------------------
local EXTRA_STATS = {
	{ key = "versatility", label = function() return STAT_VERSATILITY or "Versatility" end,
		value = function()
			local d = GetCombatRatingBonus and CR_VERSATILITY_DAMAGE_DONE and GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
			local b = GetVersatilityBonus and CR_VERSATILITY_DAMAGE_DONE and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
			if not (readable(d) and readable(b)) then return nil end
			return (d or 0) + (b or 0)
		end },
	{ key = "leech", label = function() return STAT_LIFESTEAL or "Leech" end, value = function() return GetLifesteal and GetLifesteal() end },
	{ key = "avoidance", label = function() return STAT_AVOIDANCE or "Avoidance" end, value = function() return GetAvoidance and GetAvoidance() end },
	{ key = "speed", label = function() return STAT_SPEED or "Speed" end, value = function() return GetSpeed and GetSpeed() end },
	{ key = "move", label = function() return STAT_MOVEMENT_SPEED or "Movement Speed" end, move = true,
		value = function()
			if not GetUnitSpeed then return nil end
			local _, run = GetUnitSpeed("player")
			if not readable(run) or not run then return nil end
			return run / 7 * 100
		end },
}
CS.EXTRA_STATS = EXTRA_STATS

local function ExtraRow(pane, i)
	pane.SUIExtraRows = pane.SUIExtraRows or {}
	local r = pane.SUIExtraRows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, pane)
	r:SetHeight(15)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.Label = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.Label:SetPoint("LEFT", 11, 0)
	r.Value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.Value:SetPoint("RIGHT", -8, 0)
	r:EnableMouse(true)
	r:SetScript("OnEnter", function(self)
		CS.HoverRow(self, true)
		if cfg().statHighlight and self.statKey and CS.STAT_KEYS[self.statKey] then CS.Highlight("Character", self.statKey) end
	end)
	r:SetScript("OnLeave", function(self) CS.HoverRow(self, false); CS.Highlight("Character", nil) end)
	pane.SUIExtraRows[i] = r
	return r
end

function CS.UpdateExtraStats()
	local pane = _G.CharacterStatsPane
	if not pane then return end
	local c = cfg()
	local shown, lowest = {}, nil
	if pane.statsFramePool then
		for f in pane.statsFramePool:EnumerateActive() do
			local t = f.Label and f.Label:GetText()
			if readable(t) and t then shown[(t:gsub(":%s*$", ""):gsub("%s+$", ""))] = true end
			local bottom = f:IsShown() and f:GetBottom()
			if readable(bottom) and bottom and (not lowest or bottom < lowest:GetBottom()) then lowest = f end
		end
	end
	local n = 0
	if c.enabled and lowest then
		for _, st in ipairs(EXTRA_STATS) do
			local want = st.move and c.moveSpeed or (not st.move and not c.hideZeroStats)
			local label = st.label()
			if want and not shown[label] then
				local ok, v = pcall(st.value)
				if ok and readable(v) and v then
					n = n + 1
					local r = ExtraRow(pane, n)
					r:ClearAllPoints()
					r:SetPoint("TOPLEFT", lowest, "BOTTOMLEFT", 0, -(n - 1) * 15)
					r:SetPoint("TOPRIGHT", lowest, "BOTTOMRIGHT", 0, -(n - 1) * 15)
					r.statKey = st.key
					r.Label:SetText(label .. ":")
					r.Value:SetText(string.format("%.2f%%", v))
					r.bg:SetColorTexture(1, 1, 1, (n % 2 == 1) and 0.04 or 0)
					r:Show()
				end
			end
		end
	end
	for i = n + 1, #(pane.SUIExtraRows or {}) do pane.SUIExtraRows[i]:Hide() end
end

---------------------------------------------------------------------------
-- Item level with decimals
---------------------------------------------------------------------------
function CS.UpdateItemLevel()
	local f = _G.CharacterStatsPane and _G.CharacterStatsPane.ItemLevelFrame
	if not (f and f.Value) then return end
	local c = cfg()
	if not f.SUIExtra then
		f.SUIExtra = f:CreateFontString(nil, "OVERLAY")
		f.SUIExtra:SetPoint("TOP", f.Value, "BOTTOM", 0, -1)
		f.SUIBaseHeight = f:GetHeight()
	end
	if not (c.enabled and c.ilvlDecimals) then
		f.SUIExtra:Hide()
		if f.SUIBaseHeight then f:SetHeight(f.SUIBaseHeight) end
		return
	end
	local avg, equipped, pvp = GetAverageItemLevel()
	if not readable(equipped) then return end
	f.Value:SetText(string.format("%.2f", equipped))
	ns.ApplyText(f.SUIExtra, c.infoStyle)
	local text = string.format("Overall %.2f", avg or equipped)
	if readable(pvp) and pvp and math.abs(pvp - equipped) >= 0.005 then text = text .. string.format("   |cffb0b0ffPvP %.2f|r", pvp) end
	f.SUIExtra:SetText(text)
	f.SUIExtra:Show()
	f:SetHeight((f.SUIBaseHeight or 30) + c.infoStyle.size + 2)
end

function CS.UpdateInspectItemLevel()
	local holder = _G.InspectPaperDollFrame
	local unit = _G.InspectFrame and _G.InspectFrame.unit
	if not (holder and unit) then return end
	local c = cfg()
	if not holder.SUIIlvl then
		holder.SUIIlvl = holder:CreateFontString(nil, "OVERLAY")
		local model = _G.InspectModelFrame
		holder.SUIIlvl:SetPoint("TOP", model or holder, "TOP", 0, -4)
	end
	if not (c.enabled and c.ilvlDecimals and c.inspect) then holder.SUIIlvl:Hide() return end
	local equipped = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and C_PaperDollInfo.GetInspectItemLevel(unit)
	-- PvP: average of each item's PvP level (or its normal level where it doesn't scale)
	local sum, n, sumPvP = 0, 0, 0
	EachSlot("Inspect", function(b, slot)
		local o = b.SUISheet
		if o and o.info and o.info.ilvl and not CS.NO_INFO[slot] then
			local count = 1
			if slot == 16 and not GetInventoryItemLink(unit, 17) then count = 2 end -- two-hander counts twice
			sum, n = sum + o.info.ilvl * count, n + count
			sumPvP = sumPvP + (o.info.pvp or o.info.ilvl) * count
		end
	end)
	if not readable(equipped) or not equipped or equipped == 0 then equipped = n > 0 and sum / n or nil end
	ns.ApplyText(holder.SUIIlvl, c.nameStyle)
	if equipped then
		local pvpAvg = n > 0 and sumPvP / n or nil
		holder.SUIIlvl:SetText(string.format("Item Level %.2f%s", equipped,
			(pvpAvg and math.abs(pvpAvg - (sum / n)) > 0.004) and string.format("   |cffb0b0ffPvP %.2f|r", pvpAvg) or ""))
		holder.SUIIlvl:Show()
	else
		holder.SUIIlvl:Hide()
	end
end

---------------------------------------------------------------------------
-- Backgrounds
---------------------------------------------------------------------------
-- list for the options: { value, label }
function CS.BackgroundChoices()
	local items = { { "blizzard", "Blizzard (race)" }, { "dark", "Flat dark" }, { "custom", "Custom texture / atlas" } }
	local W = C_WarbandScene
	if W and W.SearchWarbandSceneEntries then
		local ok, ids = pcall(W.SearchWarbandSceneEntries, { ownedOnly = cfg().ownedOnly and true or false, favoritesOnly = false })
		if ok and type(ids) == "table" then
			local list = {}
			for _, id in ipairs(ids) do
				local e = W.GetWarbandSceneEntry(id)
				if e and readable(e.name) then list[#list + 1] = { "warband:" .. id, "Camp: " .. e.name } end
			end
			table.sort(list, function(a, b) return a[2] < b[2] end)
			for _, it in ipairs(list) do items[#items + 1] = it end
		end
	end
	return items
end

-- fills a region with an atlas, cropped (not stretched) to the region's shape
local function SetAtlasCropped(tex, atlas, w, h)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	if not (info and info.file and w and h and w > 0 and h > 0) then
		tex:SetAtlas(atlas)
		return
	end
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local aw, ah = info.width, info.height
	if aw and ah and aw > 0 and ah > 0 then
		local target, src = w / h, aw / ah
		if src > target then
			local keep = (r - l) * target / src
			local mid = (l + r) / 2
			l, r = mid - keep / 2, mid + keep / 2
		elseif src < target then
			local keep = (b - t) * src / target
			local mid = (t + b) / 2
			t, b = mid - keep / 2, mid + keep / 2
		end
	end
	tex:SetTexture(info.file)
	tex:SetTexCoord(l, r, t, b)
end
CS.SetAtlasCropped = SetAtlasCropped

local function ApplyBackground(model)
	if not model then return end
	local c = cfg()
	local mode = c.enabled and c.background or "blizzard"
	local blizz = { model.BackgroundTopLeft, model.BackgroundTopRight, model.BackgroundBotLeft, model.BackgroundBotRight, model.BackgroundOverlay }
	if not model.SUIBg then
		model.SUIBg = model:CreateTexture(nil, "BACKGROUND", nil, 2)
		model.SUIBg:SetAllPoints()
		model.SUIDim = model:CreateTexture(nil, "BACKGROUND", nil, 3)
		model.SUIDim:SetAllPoints()
		model.SUIDim:SetColorTexture(0, 0, 0, 1)
	end
	local bg, dim = model.SUIBg, model.SUIDim
	if mode == "blizzard" then
		for _, t in ipairs(blizz) do if t then t:SetAlpha(t == model.BackgroundOverlay and t:GetAlpha() or 1) end end
		bg:Hide(); dim:Hide()
		return
	end
	for _, t in ipairs(blizz) do if t then t:SetAlpha(0) end end
	local w, h = model:GetWidth(), model:GetHeight()
	bg:SetTexCoord(0, 1, 0, 1)
	bg:SetVertexColor(1, 1, 1, 1)
	if mode == "dark" then
		bg:SetColorTexture(0.06, 0.06, 0.07, 1)
	elseif mode == "custom" then
		local s = strtrim(c.customTexture or "")
		if s == "" then
			bg:SetColorTexture(0.06, 0.06, 0.07, 1)
		elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(s) then
			SetAtlasCropped(bg, s, w, h)
		else
			bg:SetTexture(tonumber(s) or s)
		end
	elseif mode:find("^warband:") then
		local id = tonumber(mode:match("^warband:(%d+)"))
		local e = id and C_WarbandScene and C_WarbandScene.GetWarbandSceneEntry(id)
		if e and readable(e.textureKit) then SetAtlasCropped(bg, e.textureKit, w, h) else bg:SetColorTexture(0.06, 0.06, 0.07, 1) end
	end
	bg:Show()
	dim:SetAlpha(c.dim)
	dim:SetShown(c.dim > 0)
end
CS.ApplyBackground = ApplyBackground

---------------------------------------------------------------------------
-- Flat skin: Blizzard's frame art, portrait, marble background, slot frames and stat-pane
-- gradients are hidden and replaced by a flat background with 1px borders. Item icons are
-- zoomed with a 1px border in the item's quality color.
---------------------------------------------------------------------------
local function Hide(region)
	if region and region.SetAlpha then region:SetAlpha(0) end
end

local function FlatBackdrop(frame, alphaKey)
	local c = cfg()
	if not frame.SUIFlat then
		local f = CreateFrame("Frame", nil, frame)
		f:SetAllPoints()
		f:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
		f.tex = f:CreateTexture(nil, "BACKGROUND", nil, -8)
		f.tex:SetAllPoints()
		ns.CreateBackdrop(f, 0)
		frame.SUIFlat = f
	end
	local col = c.frameColor
	frame.SUIFlat.tex:SetColorTexture(col[1], col[2], col[3], c[alphaKey or "frameAlpha"])
	frame.SUIFlat:Show()
	return frame.SUIFlat
end

local function StripRegions(frame, keep)
	if not frame or not frame.GetRegions then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:IsObjectType("Texture") and not (keep and keep[r]) then r:SetAlpha(0) end
	end
end

-- a panel built from ButtonFrameTemplate (CharacterFrame, InspectFrame)
local function SkinPanel(frame, inset)
	if not frame then return end
	Hide(frame.NineSlice)
	Hide(frame.Bg)
	Hide(frame.TopTileStreaks)
	Hide(frame.Background)
	if frame.PortraitContainer then frame.PortraitContainer:SetAlpha(0) end
	if frame.portrait then frame.portrait:SetAlpha(0) end
	local name = frame:GetName()
	for _, key in ipairs({ "Inset", "InsetRight" }) do
		local i = frame[key] or (inset and name and _G[name .. key])
		if i then Hide(i.NineSlice); Hide(i.Bg); StripRegions(i) end
	end
	FlatBackdrop(frame)
	-- tabs along the bottom
	for i = 1, 4 do
		local tab = name and _G[name .. "Tab" .. i]
		if tab then
			StripRegions(tab)
			for _, k in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do Hide(tab[k]) end
			local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
			if hl then hl:SetAlpha(0) end
			local f = FlatBackdrop(tab, "tabAlpha")
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", 3, -2)
			f:SetPoint("BOTTOMRIGHT", -3, 4)
		end
	end
end

local function SkinSlot(button)
	if not button then return end
	local name = button:GetName()
	Hide(name and _G[name .. "Frame"]) -- the ornate slot frame
	local nt = button.GetNormalTexture and button:GetNormalTexture()
	Hide(nt)
	Hide(button.IconBorder)
	local icon = button.icon or (name and _G[name .. "IconTexture"])
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	if not button.SUIEdge then
		ns.CreateBackdrop(button, 0)
		button.SUIEdge = true
	end
end

-- quality-colored 1px border on a slot, gray when empty
local function ColorSlotBorder(button, quality)
	local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c and quality >= 2 then
		ns.SetBorderColor(button, c.r, c.g, c.b, 1)
	else
		ns.SetBorderColor(button, 0.25, 0.25, 0.27, 1)
	end
end
CS.ColorSlotBorder = ColorSlotBorder

local function SkinModel(model)
	if not model then return end
	for _, r in ipairs({ model:GetRegions() }) do
		if r:IsObjectType("Texture") and r ~= model.SUIBg and r ~= model.SUIDim
			and r ~= model.BackgroundTopLeft and r ~= model.BackgroundTopRight and r ~= model.BackgroundBotLeft
			and r ~= model.BackgroundBotRight and r ~= model.BackgroundOverlay then
			r:SetAlpha(0) -- corner and edge art around the model
		end
	end
	local name = model:GetName()
	if name then
		for _, part in ipairs({ "BorderTopLeft", "BorderTopRight", "BorderBottomLeft", "BorderBottomRight", "BorderLeft", "BorderRight", "BorderTop", "BorderBottom", "BorderBottom2", "InnerShadow" }) do
			Hide(_G[name .. part])
		end
	end
	if not model.SUIEdge then
		ns.CreateBackdrop(model, 0)
		model.SUIEdge = true
	end
	ns.SetBorderColor(model, 0, 0, 0, 1)
end

local function SkinStats()
	local pane = _G.CharacterStatsPane
	if not pane then return end
	Hide(pane.ClassBackground)
	local c = cfg()
	for _, key in ipairs({ "ItemLevelCategory", "AttributesCategory", "EnhancementsCategory" }) do
		local cat = pane[key]
		if cat and cat.Background then
			cat.Background:SetAlpha(0)
			if not cat.SUILine then
				cat.SUILine = cat:CreateTexture(nil, "ARTWORK")
				cat.SUILine:SetPoint("BOTTOMLEFT", 6, 2)
				cat.SUILine:SetPoint("BOTTOMRIGHT", -6, 2)
				cat.SUILine:SetHeight(1)
			end
			cat.SUILine:SetColorTexture(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 0.8)
		end
	end
	if pane.ItemLevelFrame then Hide(pane.ItemLevelFrame.Background) end
	if pane.statsFramePool then
		for f in pane.statsFramePool:EnumerateActive() do
			if f.Background then
				-- alternating rows: a flat stripe instead of the gradient art
				f.Background:SetColorTexture(1, 1, 1, 0.04)
				f.Background:ClearAllPoints()
				f.Background:SetAllPoints()
			end
		end
	end
end

-- selected tab: plum fill (the tab art that showed it is hidden)
local function PaintTab(tab, selected)
	local f = tab and tab.SUIFlat
	if not f then return end
	local c = cfg()
	if selected then
		local p = ns.BRAND.plum
		f.tex:SetColorTexture(p[1], p[2], p[3], 1)
	else
		local col = c.frameColor
		f.tex:SetColorTexture(col[1], col[2], col[3], c.tabAlpha)
	end
end
if _G.PanelTemplates_SelectTab then hooksecurefunc("PanelTemplates_SelectTab", function(tab) PaintTab(tab, true) end) end
if _G.PanelTemplates_DeselectTab then hooksecurefunc("PanelTemplates_DeselectTab", function(tab) PaintTab(tab, false) end) end

-- Blizzard panel button (Equip, Save): flat fill, 1px border, plum on hover. Blizzard swaps the
-- Left/Middle/Right textures on press and disable; they stay at alpha 0, so only our look shows.
function CS.SkinButton(b)
	if not b then return end
	for _, k in ipairs({ "Left", "Middle", "Right" }) do Hide(b[k]) end
	local hl = b.GetHighlightTexture and b:GetHighlightTexture()
	if hl then hl:SetAlpha(0) end
	if b.SUIFill then return end
	b.SUIFill = b:CreateTexture(nil, "BACKGROUND", nil, -6)
	b.SUIFill:SetAllPoints()
	ns.CreateBackdrop(b, 0)
	local P = ns.BRAND.plum
	local function paint(self, over)
		if not self:IsEnabled() then
			self.SUIFill:SetColorTexture(0.10, 0.09, 0.08, 0.9)
		elseif over then
			self.SUIFill:SetColorTexture(P[1], P[2], P[3], 1)
		else
			self.SUIFill:SetColorTexture(0.15, 0.13, 0.11, 1)
		end
	end
	b:HookScript("OnEnter", function(self) paint(self, true) end)
	b:HookScript("OnLeave", function(self) paint(self, false) end)
	b:HookScript("OnEnable", function(self) paint(self, false) end)
	b:HookScript("OnDisable", function(self) paint(self, false) end)
	paint(b, false)
	local fs = b.GetFontString and b:GetFontString()
	if fs then ns.SetFont(fs, 12) end
end

-- the three sidebar tabs (stats, titles, equipment sets): flat squares, plum + green line when open
local function PaintSidebarTab(tab)
	local f = tab.SUIFlat
	if not f then return end
	Hide(tab.TabBg); Hide(tab.Hider); Hide(tab.Highlight)
	local index = tab:GetID()
	local pane = _G.GetPaperDollSideBarFrame and index and _G.GetPaperDollSideBarFrame(index)
	local open = pane and pane:IsShown()
	local c = cfg()
	if open then
		local p = ns.BRAND.plum
		f.tex:SetColorTexture(p[1], p[2], p[3], 1)
	else
		local col = c.frameColor
		f.tex:SetColorTexture(col[1], col[2], col[3], c.tabAlpha)
	end
	tab.SUILine:SetShown(open and true or false)
	if tab.Icon then tab.Icon:SetDesaturated(not open and not tab:IsEnabled()) end
end
CS.PaintSidebarTab = PaintSidebarTab

function CS.SkinSidebarTabs()
	for i = 1, 3 do
		local tab = _G["PaperDollSidebarTab" .. i]
		if tab then
			if not tab.SUIFlat then
				local f = FlatBackdrop(tab, "tabAlpha")
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", 1, -1)
				f:SetPoint("BOTTOMRIGHT", -1, 1)
				tab.SUILine = f:CreateTexture(nil, "ARTWORK")
				tab.SUILine:SetPoint("BOTTOMLEFT")
				tab.SUILine:SetPoint("BOTTOMRIGHT")
				tab.SUILine:SetHeight(2)
				tab.SUILine:SetColorTexture(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 1)
				if tab.Icon then
					tab.Icon:ClearAllPoints()
					tab.Icon:SetPoint("TOPLEFT", 3, -3)
					tab.Icon:SetPoint("BOTTOMRIGHT", -3, 3)
				end
				tab:HookScript("OnEnter", function(self) if self.SUIFlat and not self.SUILine:IsShown() then local p = ns.BRAND.plum; self.SUIFlat.tex:SetColorTexture(p[1] * 0.6, p[2] * 0.6, p[3] * 0.6, 1) end end)
				tab:HookScript("OnLeave", PaintSidebarTab)
			end
			PaintSidebarTab(tab)
		end
	end
end
if _G.PaperDollFrame_UpdateSidebarTabs then
	hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", function()
		local c = cfg()
		if c.enabled and c.flat then for i = 1, 3 do local t = _G["PaperDollSidebarTab" .. i]; if t then PaintSidebarTab(t) end end end
	end)
end

function CS.ApplySkin(which)
	local c = cfg()
	if not (c.enabled and c.flat) then return end
	if which ~= "Inspect" then
		SkinPanel(_G.CharacterFrame, true)
		SkinModel(_G.CharacterModelScene)
		SkinStats()
		EachSlot("Character", function(b) SkinSlot(b) end)
		CS.SkinSidebarTabs()
		local em = _G.PaperDollFrame and _G.PaperDollFrame.EquipmentManagerPane
		if em then CS.SkinButton(em.EquipSet); CS.SkinButton(em.SaveSet) end
	end
	if which ~= "Character" and c.inspect then
		SkinPanel(_G.InspectFrame, true)
		SkinModel(_G.InspectModelFrame)
		EachSlot("Inspect", function(b) SkinSlot(b) end)
	end
end

---------------------------------------------------------------------------
-- Size: a scale for the character and inspect windows, plus a drag corner to resize
---------------------------------------------------------------------------
local function AddResizer(frame, key)
	if not frame or frame.SUIResizer then return end
	local g = CreateFrame("Button", nil, frame)
	g:SetSize(16, 16)
	g:SetPoint("BOTTOMRIGHT", -2, 2)
	g:SetFrameLevel(frame:GetFrameLevel() + 20)
	for i = 1, 3 do
		local t = g:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 0.8)
		t:SetSize(i * 4, 1)
		t:SetPoint("BOTTOMRIGHT", 0, (i - 1) * 4)
	end
	g:SetScript("OnMouseDown", function(self)
		if InCombatLockdown() then return end
		local x, y = GetCursorPosition()
		self.startX, self.startScale = x, frame:GetScale()
		self.startW = frame:GetWidth() * frame:GetEffectiveScale()
		self:SetScript("OnUpdate", function()
			local cx = GetCursorPosition()
			local scale = self.startScale * (self.startW + (cx - self.startX)) / self.startW
			scale = math.max(0.7, math.min(2, scale))
			cfg()[key] = math.floor(scale * 100 + 0.5) / 100
			frame:SetScale(cfg()[key])
		end)
	end)
	g:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		frame:SetScale(cfg()[key]) -- saved in your profile; applied every time the window opens
	end)
	g:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Drag to resize")
		GameTooltip:Show()
	end)
	g:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.SUIResizer = g
end

---------------------------------------------------------------------------
-- Roomier layout: wider and taller window and model, more space between slots, weapons apart
---------------------------------------------------------------------------
local LEFT_CHAIN = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
local RIGHT_CHAIN = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local BASE_W, BASE_H, MODEL_W, MODEL_H = 338, 424, 231, 320

function CS.Extra()
	local c = cfg()
	if not (c.enabled and c.roomy) then return 0, 0, 5 end
	return c.extraWidth, c.extraHeight, c.weaponGap
end

local function LayoutSlots(prefix, model)
	local ew, eh, wgap = CS.Extra()
	local gap = 4 + eh / 7
	for _, chain in ipairs({ LEFT_CHAIN, RIGHT_CHAIN }) do
		for i = 2, #chain do
			local b, prev = _G[prefix .. chain[i]], _G[prefix .. chain[i - 1]]
			if b and prev then
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
			end
		end
	end
	local main, off = _G[prefix .. "MainHandSlot"], _G[prefix .. "SecondaryHandSlot"]
	if main and off then
		local parent = main:GetParent()
		main:ClearAllPoints()
		main:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 130 + ew / 2 - (wgap - 5) / 2, 16)
		off:ClearAllPoints()
		off:SetPoint("TOPLEFT", main, "TOPRIGHT", wgap, 0)
	end
	if model then model:SetSize(MODEL_W + ew, MODEL_H + eh) end
end

function CS.ApplyLayout()
	ns:RunOOC(function()
		local ew, eh = CS.Extra()
		local cf = _G.CharacterFrame
		if cf then
			cf:SetHeight(BASE_H + eh)
			-- same width Blizzard would set, plus ours (without calling Blizzard's sizing code)
			local onPaperDoll = (cf.activeSubframe == nil) or (cf.activeSubframe == "PaperDollFrame")
			if onPaperDoll then
				local panelW = tonumber(PANEL_DEFAULT_WIDTH) or BASE_W
				local base = cf.Expanded and (tonumber(CHARACTERFRAME_EXPANDED_WIDTH) or 540) or panelW
				cf:SetWidth(base + ew)
				if cf.Inset then
					cf.Inset:SetPoint("BOTTOMRIGHT", cf, "BOTTOMLEFT", panelW + (tonumber(PANEL_INSET_RIGHT_OFFSET) or -6) + ew, tonumber(PANEL_INSET_BOTTOM_OFFSET) or 4)
				end
			end
			LayoutSlots("Character", _G.CharacterModelScene)
		end
		local inf = _G.InspectFrame
		if inf and cfg().inspect then
			inf:SetSize(BASE_W + ew, BASE_H + eh)
			LayoutSlots("Inspect", _G.InspectModelFrame)
		end
	end)
end

-- after Blizzard sizes the character window, add the extra room on the character tab
local function HookCharacterSize()
	local cf = _G.CharacterFrame
	if not cf or cf.SUISizeHook or not cf.UpdateSize then return end
	cf.SUISizeHook = true
	hooksecurefunc(cf, "UpdateSize", function(self)
		local ew, eh = CS.Extra()
		self:SetHeight(BASE_H + eh)
		local onPaperDoll = (self.activeSubframe == nil) or (self.activeSubframe == "PaperDollFrame")
		if ew > 0 and onPaperDoll then
			self:SetWidth(self:GetWidth() + ew)
			if self.Inset then
				self.Inset:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", (tonumber(PANEL_DEFAULT_WIDTH) or BASE_W) + (tonumber(PANEL_INSET_RIGHT_OFFSET) or -6) + ew, tonumber(PANEL_INSET_BOTTOM_OFFSET) or 4)
			end
		end
	end)
end

function CS.ApplyScale()
	local c = cfg()
	ns:RunOOC(function()
		if _G.CharacterFrame then
			_G.CharacterFrame:SetScale(c.enabled and c.scale or 1)
			AddResizer(_G.CharacterFrame, "scale")
			_G.CharacterFrame.SUIResizer:SetShown(c.enabled and c.resizer and true or false)
		end
		if _G.InspectFrame then
			_G.InspectFrame:SetScale((c.enabled and c.inspect) and c.inspectScale or 1)
			AddResizer(_G.InspectFrame, "inspectScale")
			_G.InspectFrame.SUIResizer:SetShown(c.enabled and c.inspect and c.resizer and true or false)
		end
	end)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local function HookInspect()
	if CS.inspectHooked or not _G.InspectPaperDollItemSlotButton_Update then return end
	CS.inspectHooked = true
	hooksecurefunc("InspectPaperDollItemSlotButton_Update", function()
		if cfg().inspect and _G.InspectFrame and _G.InspectFrame.unit then Queue("Inspect", _G.InspectFrame.unit) end
	end)
	if _G.InspectPaperDollFrame_OnShow then
		hooksecurefunc("InspectPaperDollFrame_OnShow", function()
			if cfg().inspect then
				ApplyBackground(_G.InspectModelFrame)
				CS.ApplySkin("Inspect")
				CS.ApplyScale()
				CS.ApplyLayout()
			end
		end)
	end
end

function CS:Init()
	local c = cfg()
	if _G.PaperDollItemSlotButton_Update then
		hooksecurefunc("PaperDollItemSlotButton_Update", function() if cfg().enabled then Queue("Character", "player") end end)
	end
	if _G.PaperDollFrame_UpdateStats then
		hooksecurefunc("PaperDollFrame_UpdateStats", function()
			HookStatFrames()
			if cfg().enabled then
				CS.UpdateItemLevel()
				if cfg().flat then SkinStats() end
			end
			CS.UpdateExtraStats()
		end)
	end
	if _G.PaperDollFrame then
		_G.PaperDollFrame:HookScript("OnShow", function()
			ApplyBackground(_G.CharacterModelScene)
			CS.ApplySkin("Character")
			CS.ApplyScale()
			CS.ApplyLayout()
			Queue("Character", "player")
		end)
	end
	if _G.CharacterFrame then
		HookCharacterSize()
		_G.CharacterFrame:HookScript("OnShow", function() CS.ApplyScale() end)
	end
	local function RefreshOpen()
		if _G.PaperDollFrame and _G.PaperDollFrame:IsShown() then Queue("Character", "player") end
	end
	ns:On("PLAYER_EQUIPMENT_CHANGED", RefreshOpen)
	ns:On("PLAYER_AVG_ITEM_LEVEL_UPDATE", RefreshOpen)
	ns:On("ZONE_CHANGED_NEW_AREA", RefreshOpen)
	ns:On("PVP_MATCH_STATE_CHANGED", RefreshOpen)
	ns:On("GET_ITEM_INFO_RECEIVED", function()
		if _G.PaperDollFrame and _G.PaperDollFrame:IsShown() then Queue("Character", "player") end
		if _G.InspectFrame and _G.InspectFrame:IsShown() and _G.InspectFrame.unit then Queue("Inspect", _G.InspectFrame.unit) end
	end)
	ns:On("INSPECT_READY", function()
		if cfg().inspect and _G.InspectFrame and _G.InspectFrame:IsShown() and _G.InspectFrame.unit then Queue("Inspect", _G.InspectFrame.unit) end
	end)
	ns:On("ADDON_LOADED", function(_, name) if name == "Blizzard_InspectUI" then HookInspect(); CS.ApplyScale() end end)
	HookInspect()
	CS.ApplyScale()
end

function CS:Refresh()
	if _G.PaperDollFrame and _G.PaperDollFrame:IsShown() then CS.UpdateExtraStats() end
	CS.ApplyScale()
	CS.ApplyLayout()
	CS.ApplySkin()
	if _G.CharacterModelScene then ApplyBackground(_G.CharacterModelScene) end
	if _G.InspectModelFrame and cfg().inspect then ApplyBackground(_G.InspectModelFrame) end
	if _G.PaperDollFrame and _G.PaperDollFrame:IsShown() then Queue("Character", "player") end
	if _G.InspectFrame and _G.InspectFrame:IsShown() and _G.InspectFrame.unit then Queue("Inspect", _G.InspectFrame.unit) end
end

ns:RegisterModule("CharacterSheet", CS)
