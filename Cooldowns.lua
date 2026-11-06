-- StinkieUI: Cooldown Manager centering + custom cooldown bars (spells, items, trinkets, racial).
-- Custom bar icons are ping receivers: hover one and press your ping key to call it out.
local _, ns = ...

local CD = {}
ns.Cooldowns = CD
CD.bars = {}

---------------------------------------------------------------------------
-- Blizzard Cooldown Manager: center each row
---------------------------------------------------------------------------
local viewers = {
	{ global = "EssentialCooldownViewer", key = "centerEssential" },
	{ global = "UtilityCooldownViewer", key = "centerUtility" },
	{ global = "BuffIconCooldownViewer", key = "centerBuffs" },
	{ global = "BuffBarCooldownViewer" }, -- skin only
}

---------------------------------------------------------------------------
-- Square skin for Blizzard Cooldown Manager icons and bars
---------------------------------------------------------------------------
local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local skinned = {}

local function Restyle(fs, outline)
	if not fs or not fs.GetFont then return end
	local _, size = fs:GetFont()
	ns.SetFont(fs, size or 14, outline or "OUTLINE")
	fs:SetShadowOffset(0, 0)
end

local function SquareIcon(holder, icon)
	for _, r in ipairs({ holder:GetRegions() }) do
		if r:IsObjectType("MaskTexture") then
			icon:RemoveMaskTexture(r)
		elseif r ~= icon and r:IsObjectType("Texture") and r:GetAtlas() == OVERLAY_ATLAS then
			r:SetAlpha(0)
		end
	end
	ns.ZoomIcon(icon)
end

-- Idempotent: safe to run on every Blizzard relayout, so anything Blizzard resets is put back.
local function SkinItem(item)
	if not ns.db.cooldowns.skinBlizzard then return end
	local first = not skinned[item]
	skinned[item] = true
	if item.Bar then
		-- buff bar row: icon frame + status bar
		local iconFrame = item.Icon
		if iconFrame and iconFrame.Icon then
			SquareIcon(iconFrame, iconFrame.Icon)
			ns.IconBorder(iconFrame)
			if first then Restyle(iconFrame.Applications) end
		end
		local bar = item.Bar
		bar:SetStatusBarTexture(ns.TEXTURE)
		if first then bar:SetStatusBarColor(ns.GetUnitClassColor("player"):GetRGB()) end
		if bar.BarBG then
			local c = ns.db.colors.healthBackground
			bar.BarBG:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		end
		if bar.Pip then bar.Pip:SetAlpha(0) end
		ns.IconBorder(bar)
		if first then
			Restyle(bar.Name)
			Restyle(bar.Duration)
		end
		return
	end
	if item.Icon and item.Icon.IsObjectType and item.Icon:IsObjectType("Texture") then
		SquareIcon(item, item.Icon)
	end
	ns.IconBorder(item)
	if item.OutOfRange then item.OutOfRange:SetColorTexture(0, 0, 0, 0.55) end
	if item.CooldownFlash then item.CooldownFlash:SetAlpha(0) end
	local cd = item.Cooldown
	if cd and first then
		cd:SetSwipeTexture(ns.TEXTURE)
		cd:SetDrawEdge(false)
		cd:SetCountdownFont(ns.GetCountdownFont(item:GetWidth() * 0.42))
	end
	if first then
		if item.ChargeCount then Restyle(item.ChargeCount.Current) end
		if item.Applications then Restyle(item.Applications.Applications) end
	end
end
CD.SkinItem = SkinItem

---------------------------------------------------------------------------
-- Gray out abilities you can't use right now (Execute until it's usable or procs). Blizzard already
-- checks this on each icon and only darkens it, so this follows its updates. Hooks and widget calls
-- only: nothing is written into Blizzard's items.
---------------------------------------------------------------------------
function CD.Unusable(spellID)
	if not (ns.db.cooldowns.grayUnusable and spellID) then return false end
	local usable = C_Spell.IsSpellUsable(spellID)
	if ns.issecret(usable) then return false end -- can't be read: leave the icon as Blizzard has it
	return not usable
end

local grayed = setmetatable({}, { __mode = "k" })

function CD.ApplyUsable(item)
	local icon = item:GetIconTexture()
	if CD.Unusable(item:GetSpellID()) then
		grayed[item] = true
		icon:SetDesaturated(true)
	elseif grayed[item] then
		-- usable again: back to what Blizzard wants, which is gray if it's on cooldown
		grayed[item] = nil
		local onCooldown = item.cooldownDesaturated
		if ns.issecret(onCooldown) then
			icon:SetDesaturated(onCooldown)
		else
			icon:SetDesaturated(onCooldown and not item:IsExpired() or false)
		end
	end
end

local watchedUsable = setmetatable({}, { __mode = "k" })
local function WatchUsable(item)
	if watchedUsable[item] or not (item.RefreshIconColor and item.RefreshIconDesaturation) then return end
	watchedUsable[item] = true
	hooksecurefunc(item, "RefreshIconColor", CD.ApplyUsable)
	hooksecurefunc(item, "RefreshIconDesaturation", CD.ApplyUsable)
	CD.ApplyUsable(item)
end
CD.WatchUsable = WatchUsable

local pending = {}
local scheduler = CreateFrame("Frame")
scheduler:Hide()

local function CenterViewer(viewer)
	if not viewer or not viewer.isHorizontal then return end
	if viewer.IsEditing and viewer:IsEditing() then return end
	local items, total = {}, 0
	if viewer.itemFramePool then
		for item in viewer.itemFramePool:EnumerateActive() do
			if item.layoutIndex then
				total = total + 1
				if item:IsShown() then table.insert(items, item) end
			end
		end
	end
	if #items == 0 then return end
	table.sort(items, function(a, b) return a.layoutIndex < b.layoutIndex end)

	local stride = math.max(1, viewer.stride or viewer.iconLimit or #items)
	local pad = viewer.childXPadding or 2
	local padY = viewer.childYPadding or pad
	local first = items[1]
	local scale = first:GetScale()
	local w, h = first:GetWidth() * scale, first:GetHeight() * scale
	local goingUp = viewer.layoutFramesGoingUp

	-- Blizzard shrinks the viewer to fit only the icons it shows, and Edit Mode keeps whichever
	-- edge the viewer is anchored by. So the center of a full row (stride icons) is the reference:
	-- the viewer's center when it's anchored by a centered point, else measured from its anchored edge.
	local point = viewer:GetPoint(1)
	-- as wide as the viewer is in Edit Mode, where every icon shows
	local fullCount = math.min(stride, math.max(total, #items))
	local fullWidth = fullCount * w + (fullCount - 1) * pad
	local edge, base = "", 0
	if type(point) == "string" and point:find("LEFT") then
		edge, base = "LEFT", fullWidth / 2
	elseif type(point) == "string" and point:find("RIGHT") then
		edge, base = "RIGHT", -fullWidth / 2
	end
	local vAnchor = goingUp and "BOTTOM" or "TOP"
	local relPoint = vAnchor .. edge

	local rows = math.ceil(#items / stride)
	for row = 0, rows - 1 do
		local startIndex = row * stride + 1
		local count = math.min(stride, #items - row * stride)
		local rowWidth = count * w + (count - 1) * pad
		for i = 0, count - 1 do
			local item = items[startIndex + i]
			local x = base - rowWidth / 2 + i * (w + pad)
			local y = row * (h + padY)
			item:ClearAllPoints()
			if goingUp then
				item:SetPoint("BOTTOMLEFT", viewer, relPoint, x / scale, y / scale)
			else
				item:SetPoint("TOPLEFT", viewer, relPoint, x / scale, -y / scale)
			end
		end
	end
end

local function Schedule(viewer)
	pending[viewer] = true
	scheduler:Show()
end

scheduler:SetScript("OnUpdate", function(self)
	self:Hide()
	for viewer in pairs(pending) do
		pending[viewer] = nil
		if ns.db.cooldowns.skinBlizzard and viewer.itemFramePool then
			for item in viewer.itemFramePool:EnumerateActive() do SkinItem(item) end
		end
		local enabled
		for _, v in ipairs(viewers) do
			if _G[v.global] == viewer and v.key then enabled = ns.db.cooldowns[v.key] end
		end
		if enabled then CenterViewer(viewer) end
	end
end)

local hookedItems = {}
local function HookViewer(viewer)
	if not viewer or viewer.SUIHooked then return end
	viewer.SUIHooked = true
	if viewer.Layout then
		hooksecurefunc(viewer, "Layout", function(v) Schedule(v) end)
	end
	if viewer.OnAcquireItemFrame then
		hooksecurefunc(viewer, "OnAcquireItemFrame", function(v, item)
			SkinItem(item)
			WatchUsable(item)
			if not hookedItems[item] then
				hookedItems[item] = true
				item:HookScript("OnShow", function() Schedule(v) end)
				item:HookScript("OnHide", function() Schedule(v) end)
			end
		end)
	end
	if viewer.itemFramePool then
		for item in viewer.itemFramePool:EnumerateActive() do
			SkinItem(item)
			WatchUsable(item)
		end
	end
	Schedule(viewer)
end

---------------------------------------------------------------------------
-- Racial lookup (by name, resolved against your spellbook)
---------------------------------------------------------------------------
local racials = {
	Human = "Will to Survive", Orc = "Blood Fury", Dwarf = "Stoneform", NightElf = "Shadowmeld",
	Scourge = "Will of the Forsaken", Tauren = "War Stomp", Gnome = "Escape Artist", Troll = "Berserking",
	Goblin = "Rocket Jump", BloodElf = "Arcane Torrent", Draenei = "Gift of the Naaru", Worgen = "Darkflight",
	Pandaren = "Quaking Palm", Nightborne = "Arcane Pulse", HighmountainTauren = "Bull Rush",
	VoidElf = "Spatial Rift", LightforgedDraenei = "Light's Judgment", ZandalariTroll = "Regeneratin'",
	KulTiran = "Haymaker", DarkIronDwarf = "Fireblood", Vulpera = "Bag of Tricks", MagharOrc = "Ancestral Call",
	Mechagnome = "Hyper Organic Light Originator", Dracthyr = "Tail Swipe", EarthenDwarf = "Azerite Surge",
}

-- true when the player can actually use this spell right now (learned, talented, this spec)
local function SpellKnown(id)
	local SB = C_SpellBook
	if SB then
		if SB.IsSpellKnownOrInSpellBook and SB.IsSpellKnownOrInSpellBook(id) then return true end
		if SB.IsSpellKnown and SB.IsSpellKnown(id) then return true end
	end
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	return false
end
CD.SpellKnown = SpellKnown

local function ResolveSpell(input)
	if not input then return end
	local info = C_Spell.GetSpellInfo(tonumber(input) or input)
	return info and info.spellID, info
end

local function GetRacialSpell()
	local _, race = UnitRace("player")
	local name = race and racials[race]
	if not name then return end
	local id = ResolveSpell(name)
	if id and C_SpellBook.IsSpellKnown and not C_SpellBook.IsSpellKnown(id) then return end
	return id
end

---------------------------------------------------------------------------
-- Entries: "spell:ID", "item:ID", "slot:13", "racial"
---------------------------------------------------------------------------
local function ParseEntry(entry)
	if entry == "racial" then
		local id = GetRacialSpell()
		return id and "spell" or nil, id
	end
	local kind, id = entry:match("^(%a+):(%d+)$")
	return kind, tonumber(id)
end
CD.ParseEntry = ParseEntry

function CD.DescribeEntry(entry)
	local kind, id = ParseEntry(entry)
	if entry == "racial" then
		return "Racial" .. (id and (": " .. (C_Spell.GetSpellName(id) or id)) or " (none found)")
	elseif kind == "spell" then
		return (C_Spell.GetSpellName(id) or "Spell") .. "  |cff888888" .. id .. "|r"
	elseif kind == "proc" then
		return (C_Spell.GetSpellName(id) or "Spell") .. ", only when upgraded  |cff888888" .. id .. "|r"
	elseif kind == "item" then
		return (C_Item.GetItemNameByID(id) or "Item") .. "  |cff888888" .. id .. "|r"
	elseif kind == "slot" then
		return id == 13 and "Trinket 1" or id == 14 and "Trinket 2" or ("Slot " .. id)
	end
	return entry
end

function CD.EntryTexture(entry)
	local kind, id = ParseEntry(entry)
	if (kind == "spell" or kind == "proc") and id then
		return C_Spell.GetSpellTexture(id)
	elseif kind == "item" and id then
		return C_Item.GetItemIconByID(id)
	elseif kind == "slot" and id then
		return GetInventoryItemTexture("player", id)
	end
	return 134400 -- question mark
end

function CD.MoveEntry(barIndex, from, to)
	local entries = ns.db.cooldowns.bars[barIndex].entries
	if from == to or not entries[from] then return end
	local e = table.remove(entries, from)
	to = math.max(1, math.min(to, #entries + 1))
	table.insert(entries, to, e)
end

-- Turns user input (spell/item name or id, or "item:ID") into an entry string.
function CD.EntryFromInput(text)
	text = strtrim(text or "")
	if text == "" then return end
	if text:match("^%a+:%d+$") or text == "racial" then return text end
	local procName = text:match("^[Pp]roc:%s*(.+)$")
	if procName then
		local procID = ResolveSpell(procName)
		return procID and ("proc:" .. procID) or nil
	end
	local spellID = ResolveSpell(text)
	if spellID then return "spell:" .. spellID end
	local itemID = C_Item.GetItemInfoInstant(tonumber(text) or text)
	if itemID then return "item:" .. itemID end
end

-- Turns whatever is on the cursor (spellbook spell, bag item) into an entry string.
function CD.EntryFromCursor()
	local kind, a, _, d = GetCursorInfo()
	if kind == "spell" and d then
		return "spell:" .. d
	elseif kind == "item" and a then
		return "item:" .. a
	end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local ButtonMixin = CreateFromMixins(PingableTypeMixin)

function ButtonMixin:GetAllowRadialWheel()
	return false
end

function ButtonMixin:GetTargetInfo()
	if self.kind == "spell" then
		return { spellID = self.id }
	elseif self.kind == "item" or self.kind == "slot" then
		return { itemID = self.itemID }
	end
	return {}
end

function ButtonMixin:GetIsPingable()
	return self.kind ~= nil
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if self.kind == "spell" then
		GameTooltip:SetSpellByID(self.id)
	elseif self.kind == "slot" then
		GameTooltip:SetInventoryItem("player", self.id)
	elseif self.kind == "item" then
		GameTooltip:SetItemByID(self.id)
	end
	GameTooltip:Show()
end

local function CreateButton(bar)
	local b = CreateFrame("Frame", nil, bar)
	Mixin(b, ButtonMixin)
	b:SetAttribute("ping-receiver", true)
	b:EnableMouse(true)
	ns.CreateBackdrop(b, 1)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	ns.ZoomIcon(icon)
	b.Icon = icon

	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	b.Cooldown = cd

	local textLayer = CreateFrame("Frame", nil, b)
	textLayer:SetAllPoints()
	textLayer:SetFrameLevel(cd:GetFrameLevel() + 1)
	b.Count = ns.CreateText(textLayer, 12, "RIGHT")
	b.Count:SetPoint("BOTTOMRIGHT", -2, 2)

	b:SetScript("OnEnter", OnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

-- Spells like Command Demon (119898) are stand-ins whose real spell changes (here: with your
-- demon). Cooldowns live on the current override, and a pet ability's cooldown is reported by
-- its pet bar slot (PET_BAR_UPDATE_COOLDOWN), not by the player spell cooldown API.
local function CurrentSpell(id)
	local ok, over = pcall(C_Spell.GetOverrideSpell, id)
	if ok and not ns.issecret(over) and type(over) == "number" and over ~= 0 then return over end
	return id
end

local function PetSlotFor(spellID)
	if not (PetHasActionBar and PetHasActionBar()) then return nil end
	for i = 1, NUM_PET_ACTION_SLOTS or 10 do
		local sid = select(7, GetPetActionInfo(i))
		if not ns.issecret(sid) and sid == spellID then return i end
	end
	return nil
end

local function UpdateButton(b)
	local kind, id = b.kind, b.id
	-- "proc:" entries: only seen while a proc has turned the spell into another one (Slam into
	-- Heroic Strike). It keeps its place in the bar, so nothing moves and it works in combat.
	if kind == "proc" then
		local upgraded = CurrentSpell(id) ~= id
		b:SetAlpha(upgraded and 1 or 0)
		if not upgraded then return end
		kind = "spell"
	end
	if kind == "spell" then
		id = CurrentSpell(id)
		local tex = C_Spell.GetSpellTexture(id)
		if tex then b.Icon:SetTexture(tex) end
		local petSlot = PetSlotFor(id)
		if petSlot then
			local start, dur = GetPetActionCooldown(petSlot)
			-- values may be hidden in combat: hand them straight to the cooldown frame
			local ok = pcall(b.Cooldown.SetCooldown, b.Cooldown, start or 0, dur or 0)
			if not ok then b.Cooldown:Clear() end
			b.Count:SetText("")
			local desat = false
			if not ns.issecret(dur) and type(dur) == "number" then desat = dur > 1.5 end
			b.Icon:SetDesaturated(desat)
			return
		end
		local charges = C_Spell.GetSpellCharges(id)
		local hasCharges = charges and ns.IsUsable(charges.maxCharges) and charges.maxCharges > 1
		local duration
		if hasCharges then
			duration = C_Spell.GetSpellChargeDuration(id)
			b.Count:SetText(string.format("%d", charges.currentCharges))
		else
			duration = C_Spell.GetSpellCooldownDuration(id, true)
			b.Count:SetText("")
		end
		if duration then
			b.Cooldown:SetCooldownFromDurationObject(duration)
		else
			b.Cooldown:Clear()
		end
		local info = C_Spell.GetSpellCooldown(id)
		local onCD = info and info.isActive and not info.isOnGCD and not hasCharges
		b.Icon:SetDesaturated((onCD or CD.Unusable(id)) and true or false)
	elseif kind == "slot" then
		local start, dur, enable = GetInventoryItemCooldown("player", id)
		if start and dur and enable and enable ~= 0 then
			b.Cooldown:SetCooldown(start, dur)
		else
			b.Cooldown:Clear()
		end
		b.Count:SetText("")
		b.Icon:SetDesaturated(dur and dur > 1.5 or false)
	elseif kind == "item" then
		local start, dur, enable = C_Item.GetItemCooldown(id)
		if start and dur and enable then
			b.Cooldown:SetCooldown(start, dur)
		else
			b.Cooldown:Clear()
		end
		local count = C_Item.GetItemCount(id, false, true)
		b.Count:SetText(b.showCount and count > 1 and count or "")
		b.Icon:SetDesaturated((dur and dur > 1.5) or false)
	end
end

-- Resolves an entry into the button. Returns false if it should not be shown.
local function SetupButton(b, entry)
	local kind, id = ParseEntry(entry)
	b.kind, b.id, b.itemID = nil, nil, nil
	b:SetAlpha(1)
	if (kind == "spell" or kind == "proc") and id then
		local tex = C_Spell.GetSpellTexture(CurrentSpell(id)) or C_Spell.GetSpellTexture(id)
		if not tex or not SpellKnown(id) then return false end -- not learned / not this spec
		b.kind, b.id = kind, id
		b.Icon:SetTexture(tex)
	elseif kind == "slot" and id then
		local itemID = GetInventoryItemID("player", id)
		if not itemID or not C_Item.GetItemSpell(itemID) then return false end -- not an on-use trinket
		b.kind, b.id, b.itemID = "slot", id, itemID
		b.Icon:SetTexture(GetInventoryItemTexture("player", id))
	elseif kind == "item" and id then
		if C_Item.GetItemCount(id, false, true) == 0 then return false end -- none in your bags
		b.kind, b.id, b.itemID = "item", id, id
		b.Icon:SetTexture(C_Item.GetItemIconByID(id))
	else
		return false
	end
	return true
end

CD.SetupButton, CD.UpdateButton = SetupButton, UpdateButton

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local function LayoutBar(bar)
	local cfg = bar.cfg
	local shown = {}
	for _, b in ipairs(bar.buttons) do
		if b:IsShown() then table.insert(shown, b) end
	end
	local size, pad = cfg.size, cfg.spacing
	local perRow = math.max(1, cfg.perRow)
	local n = math.max(1, #shown)
	local cols = math.min(n, perRow)
	local rows = math.ceil(n / perRow)
	bar:SetSize(cols * size + (cols - 1) * pad, rows * size + (rows - 1) * pad)
	for i, b in ipairs(shown) do
		local row = math.floor((i - 1) / perRow)
		local inRow = math.min(perRow, #shown - row * perRow)
		local col = (i - 1) % perRow
		local rowWidth = inRow * size + (inRow - 1) * pad
		b:SetSize(size, size)
		ns.UpdateBackdrop(b)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", bar, "TOP", -rowWidth / 2 + col * (size + pad), -row * (size + pad))
		ns.ApplyText(b.Count, cfg.countStyle)
		ns.ZoomIcon(b.Icon)
		b.Cooldown:SetCountdownFont(ns.GetCountdownFont(size * 0.42))
	end
end

function CD.RebuildBar(index)
	local bar = CD.bars[index]
	local cfg = ns.db.cooldowns.bars[index]
	if not bar then return end
	bar.cfg = cfg
	for _, b in ipairs(bar.buttons) do b:Hide() end
	local i = 0
	for _, entry in ipairs(cfg.entries) do
		i = i + 1
		local b = bar.buttons[i] or CreateButton(bar)
		bar.buttons[i] = b
		b.showCount = cfg.showCount
		if SetupButton(b, entry) then
			b:Show()
			UpdateButton(b)
		else
			b:Hide()
		end
	end
	bar:SetScale(ns.db.scale)
	LayoutBar(bar)
	ns:ApplyPoint(bar, cfg.point)
	bar:SetShown(cfg.enabled)
	bar.SUIActive = cfg.enabled
end

local function UpdateAllButtons()
	for _, bar in ipairs(CD.bars) do
		if bar:IsShown() then
			for _, b in ipairs(bar.buttons) do
				if b:IsShown() and b.kind then UpdateButton(b) end
			end
		end
	end
end

local function RebuildAll()
	for i in ipairs(CD.bars) do CD.RebuildBar(i) end
end

function CD:Init()
	for i, cfg in ipairs(ns.db.cooldowns.bars) do
		local bar = CreateFrame("Frame", "StinkieUI_CooldownBar" .. i, UIParent)
		bar:SetFrameStrata("MEDIUM")
		bar.buttons = {}
		bar.cfg = cfg
		CD.bars[i] = bar
		ns:RegisterMover("cdbar" .. i, bar, "Cooldown Bar " .. i,
			function() return ns.db.cooldowns.bars[i].point end,
			function(p) ns.db.cooldowns.bars[i].point = p end)
	end

	local f = CreateFrame("Frame")
	for _, e in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN",
		"PET_BAR_UPDATE_COOLDOWN", "SPELL_UPDATE_ICON", "SPELL_UPDATE_USABLE",
		"SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }) do
		f:RegisterEvent(e)
	end
	f:SetScript("OnEvent", UpdateAllButtons)

	local r = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED",
		"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "LEARNED_SPELL_IN_SKILL_LINE",
		"PET_BAR_UPDATE" }) do
		r:RegisterEvent(e)
	end
	-- a new demon changes what Command Demon (and similar stand-ins) points at
	r:RegisterUnitEvent("UNIT_PET", "player")
	r:SetScript("OnEvent", function() RebuildAll() end)

	-- Blizzard Cooldown Manager may load on demand
	local function TryHook()
		for _, v in ipairs(viewers) do HookViewer(_G[v.global]) end
	end
	TryHook()
	ns:On("ADDON_LOADED", function(_, name)
		if name == "Blizzard_CooldownViewer" then TryHook() end
	end)

	RebuildAll()
end

function CD:Refresh()
	RebuildAll()
	for _, v in ipairs(viewers) do
		local viewer = _G[v.global]
		if viewer then
			-- turning centering off takes effect on the next Blizzard relayout or /reload
			if v.key and ns.db.cooldowns[v.key] then Schedule(viewer) end
			if viewer.itemFramePool then
				for item in viewer.itemFramePool:EnumerateActive() do
					if watchedUsable[item] then CD.ApplyUsable(item) end
				end
			end
		end
	end
end

ns:RegisterModule("Cooldowns", CD)
