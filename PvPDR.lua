-- StinkieUI: PvP Assist DR timers for your own crowd control (Fear by default).
-- Midnight hides diminishing returns from addons, but your own casts stay readable. So when your
-- listed CC spell lands, this starts the DR window for that player and shows it on their
-- nameplate and in a small movable list:
--   level 1 = their next CC of that kind lasts 50%, level 2 = they're immune to it.
-- The window is an estimate: DR resets drReset seconds (20 since patch 12.1) after the CC ENDS,
-- and an addon can't see when it ends, so the timer assumes the CC ran its full length (drCC).
-- If the CC was broken early, DR really resets earlier than shown: the timer errs on the safe side.
local _, ns = ...

local DR = {}
ns.PvPDR = DR

local issecret = ns.issecret
local function cfg() return ns.db.arenaAssist end
local function readable(v) return not issecret(v) and v ~= nil end

DR.entries = {}    -- { key, cat, name, plate, level, start, expires, spellID }
local pending = {} -- castGUID -> { name, plate, spellID, cat }
local spellCat = {} -- spellID -> category

-- "5782 disorient Fear" -> [5782] = "disorient"
function DR.BuildSpells()
	wipe(spellCat)
	for _, line in ipairs(cfg().drSpells or {}) do
		local id, cat = tostring(line):match("^%s*(%d+)%s+(%a+)")
		if id then spellCat[tonumber(id)] = strlower(cat) end
	end
end

local function Active()
	local c = cfg()
	local AA = ns.ArenaAssist
	return c.dr and (not AA or not AA.Allowed or AA.Allowed(c.drWhere)) and true or false
end

local function PlateFrameFor(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	return plate and plate.SUIFrame or nil
end

local function ReadableName(unit)
	local n = UnitName(unit)
	if readable(n) then return n end
	return nil
end

---------------------------------------------------------------------------
-- Display: icons on nameplates and the movable list
---------------------------------------------------------------------------
local LEVEL_TEXT = { "50%", "IMM" }
local LEVEL_COLOR = { { 1.00, 0.85, 0.20 }, { 1.00, 0.25, 0.25 } }

local function MakeIcon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	ns.ZoomIcon(f.tex)
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	f.cd:SetDrawEdge(false)
	f.cd:SetReverse(true)
	ns.IconBorder(f)
	local tl = CreateFrame("Frame", nil, f)
	tl:SetAllPoints()
	tl:SetFrameLevel(f.cd:GetFrameLevel() + 2)
	f.level = ns.CreateText(tl, math.max(8, math.floor(size * 0.38)), "CENTER")
	f.level:SetPoint("BOTTOM", f, "BOTTOM", 0, 1)
	return f
end

local function FillIcon(icon, e)
	local c = cfg()
	icon.tex:SetTexture(C_Spell.GetSpellTexture(e.spellID))
	icon.cd:SetCooldown(e.start, e.expires - e.start)
	icon.cd:SetCountdownFont(ns.AssistCountdownFont(icon:GetWidth()))
	icon.cd:SetHideCountdownNumbers(not c.drNumbers)
	local col = LEVEL_COLOR[e.level] or LEVEL_COLOR[1]
	icon.level:SetText(LEVEL_TEXT[e.level] or "")
	icon.level:SetTextColor(col[1], col[2], col[3])
	icon:Show()
end

-- nameplate icons, a row under the plate (below the castbar)
local function LayoutPlateIcons(f)
	local c = cfg()
	f.SUIDR = f.SUIDR or {}
	local list = {}
	if c.drPlate then
		for _, e in ipairs(DR.entries) do
			if e.plate == f then list[#list + 1] = e end
		end
	end
	local size = c.drPlateSize or 22
	for i = 1, math.max(#list, #f.SUIDR) do
		local e = list[i]
		local icon = f.SUIDR[i]
		if e then
			if not icon then
				icon = MakeIcon(f, size)
				f.SUIDR[i] = icon
			end
			icon:SetSize(size, size)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", f.Castbar, "BOTTOMLEFT", (c.drPlateX or 0) + (i - 1) * (size + 3), (c.drPlateY or -3))
			FillIcon(icon, e)
		elseif icon then
			icon:Hide()
		end
	end
end

local function RefreshPlates()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local f = plate.SUIFrame
		if f and (f.SUIDR or DR.HasPlate(f)) then LayoutPlateIcons(f) end
	end
end

function DR.HasPlate(f)
	for _, e in ipairs(DR.entries) do if e.plate == f then return true end end
	return false
end

-- movable list: icon, timer, level, player name
DR.rows = {}
local function RefreshList()
	local c = cfg()
	local holder = DR.holder
	local size = c.drListSize or 24
	local shown = {}
	if c.drList then
		for _, e in ipairs(DR.entries) do shown[#shown + 1] = e end
		table.sort(shown, function(a, b) return a.start > b.start end)
	end
	local max = c.drMax or 3
	holder:SetSize(size + 130, max * (size + 3))
	for i = 1, math.max(math.min(#shown, max), #DR.rows) do
		local e = (i <= max) and shown[i] or nil
		local row = DR.rows[i]
		if e then
			if not row then
				row = MakeIcon(holder, size)
				row.name = ns.CreateText(row, 12, "LEFT")
				row.name:SetPoint("LEFT", row, "RIGHT", 6, 0)
				row.name:SetWidth(120)
				DR.rows[i] = row
			end
			row:SetSize(size, size)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * (size + 3))
			ns.ApplyText(row.name, c.drNameStyle)
			-- the name may be a hidden value: it only ever goes to SetText
			if e.name ~= nil then row.name:SetText(e.name) else row.name:SetText("?") end
			FillIcon(row, e)
		elseif row then
			row:Hide()
		end
	end
end

function DR:Refresh()
	if not DR.holder then return end
	DR.BuildSpells()
	DR.holder:SetScale(ns.db.scale)
	ns:ApplyPoint(DR.holder, cfg().drPoint)
	RefreshList()
	RefreshPlates()
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------
local function FindEntry(key, cat)
	for _, e in ipairs(DR.entries) do
		if e.key == key and e.cat == cat then return e end
	end
end

local function Apply(p)
	local c = cfg()
	local now = GetTime()
	local reset, cc = c.drReset or 20, c.drCC or 6
	local key = p.name and ("n:" .. p.name) or (p.plate and p.plate) or ("c:" .. tostring(now))
	local e = FindEntry(key, p.cat)
	if e and now < e.expires then
		if e.level >= 2 then
			-- they were immune: nothing landed, so the window doesn't move
			return
		end
		-- this one landed at 50%
		e.level = 2
		e.start, e.expires = now, now + cc * 0.5 + reset
		e.spellID = p.spellID
		e.plate = p.plate or e.plate
	else
		if e then
			e.level, e.start, e.expires, e.spellID = 1, now, now + cc + reset, p.spellID
			e.plate = p.plate or e.plate
		else
			table.insert(DR.entries, {
				key = key, cat = p.cat, name = p.nameText, plate = p.plate,
				level = 1, start = now, expires = now + cc + reset, spellID = p.spellID,
			})
		end
	end
	RefreshList()
	RefreshPlates()
end

-- which unit the cast is going at: matched by readable name among target / focus / mouseover,
-- otherwise your target (the usual case for a plain /cast)
local function ResolveUnit(nameArg)
	if readable(nameArg) and nameArg ~= "" then
		for _, u in ipairs({ "target", "focus", "mouseover" }) do
			if UnitExists(u) then
				local n = ReadableName(u)
				if n and (n == nameArg or Ambiguate(n, "short") == Ambiguate(nameArg, "short")) then return u end
			end
		end
	end
	return UnitExists("target") and "target" or nil
end

local function OnEvent(_, event, unit, ...)
	if event == "UNIT_SPELLCAST_SENT" then
		local nameArg, castGUID, spellID = ...
		if issecret(spellID) or issecret(castGUID) or not Active() then return end
		local cat = spellCat[spellID]
		if not cat then return end
		local u = ResolveUnit(nameArg)
		local nameText = readable(nameArg) and nameArg ~= "" and nameArg or (u and UnitName(u)) or nil
		pending[castGUID] = {
			cat = cat, spellID = spellID,
			name = (u and ReadableName(u)) or (readable(nameArg) and nameArg ~= "" and nameArg or nil),
			nameText = nameText,
			plate = u and PlateFrameFor(u) or nil,
			t = GetTime(),
		}
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local castGUID = ...
		if issecret(castGUID) then return end
		local p = pending[castGUID]
		if p then
			pending[castGUID] = nil
			Apply(p)
		end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		local castGUID = ...
		if not issecret(castGUID) and castGUID then pending[castGUID] = nil end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		-- a player we feared comes back into view: put their timer on the new plate
		local f = PlateFrameFor(unit)
		local n = f and ReadableName(unit)
		if n then
			for _, e in ipairs(DR.entries) do
				if e.key == "n:" .. n then e.plate = f end
			end
			LayoutPlateIcons(f)
		end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local f = PlateFrameFor(unit)
		if f then
			local any = false
			for _, e in ipairs(DR.entries) do
				if e.plate == f then e.plate = nil; any = true end
			end
			if any or f.SUIDR then LayoutPlateIcons(f) end
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "PVP_MATCH_STATE_CHANGED" then
		if not DR.testMode then wipe(DR.entries) end
		wipe(pending)
		DR:Refresh()
	end
end

local function Expire()
	local now, changed = GetTime(), false
	for i = #DR.entries, 1, -1 do
		local e = DR.entries[i]
		if e.expires <= now then
			table.remove(DR.entries, i)
			changed = true
		end
	end
	for g, p in pairs(pending) do
		if now - p.t > 10 then pending[g] = nil end
	end
	if changed then
		RefreshList()
		RefreshPlates()
	end
end

---------------------------------------------------------------------------
-- Test mode (with PvP Assist's test mode / unlock)
---------------------------------------------------------------------------
function DR:SetTestMode(on)
	DR.testMode = on or nil
	wipe(DR.entries)
	if on then
		local now = GetTime()
		local c = cfg()
		local reset, cc = c.drReset or 20, c.drCC or 6
		table.insert(DR.entries, { key = "t1", cat = "disorient", name = "Stinkie", level = 1, start = now, expires = now + cc + reset, spellID = 5782 })
		table.insert(DR.entries, { key = "t2", cat = "disorient", name = "Pinkie", level = 2, start = now - 4, expires = now - 4 + cc * 0.5 + reset, spellID = 5782 })
	end
	DR:Refresh()
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function DR:Init()
	local h = CreateFrame("Frame", "StinkieUI_DRTimers", UIParent)
	h:SetFrameStrata("HIGH")
	h:SetSize(150, 80)
	ns:RegisterMover("drTimers", h, "DR Timers",
		function() return cfg().drPoint end,
		function(p) cfg().drPoint = p end)
	DR.holder = h

	local ev = CreateFrame("Frame")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
	for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
		"ZONE_CHANGED_NEW_AREA", "PVP_MATCH_STATE_CHANGED" }) do
		ev:RegisterEvent(e)
	end
	ev:SetScript("OnEvent", function(...)
		local ok, err = pcall(OnEvent, ...)
		if not ok then geterrorhandler()(err) end
	end)
	local elapsed = 0
	ev:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.25 then return end
		elapsed = 0
		if #DR.entries > 0 and not DR.testMode then Expire() end
	end)

	table.insert(ns.lockCallbacks, function(unlocked)
		if unlocked then
			DR.testFromUnlock = not DR.testMode
			DR:SetTestMode(true)
		elseif DR.testFromUnlock then
			DR.testFromUnlock = nil
			DR:SetTestMode(false)
		end
	end)
	DR:Refresh()
end

ns:RegisterModule("PvPDR", DR)
