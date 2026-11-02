-- StinkieUI: miscellaneous. GCD History (a strip of the spells you just cast, sliding along as
-- you cast more) and Auto-Confirm Decor Purchases (skips the "are you sure" popup when buying
-- housing decor from a vendor).
local _, ns = ...

local MISC = {}
ns.Misc = MISC

local issecret = ns.issecret
local function gcfg() return ns.db.misc.gcd end
local function dcfg() return ns.db.misc.decor end

---------------------------------------------------------------------------
-- GCD History
-- Your own casts are readable (UNIT_SPELLCAST_SUCCEEDED for "player"). If a spell's ID is ever
-- secret, its icon still shows (the texture call accepts secrets); the ignore list just can't
-- match it.
---------------------------------------------------------------------------
local holder
local icons = {}      -- active entries, newest first: { frame, born, x, y }
local pool = {}
local lastCast

local function Step()
	local c = gcfg()
	return c.size + c.spacing
end

local function Offset(index)
	local c = gcfg()
	local d = (index - 1) * Step()
	if c.direction == "LEFT" then return -d, 0
	elseif c.direction == "UP" then return 0, d
	elseif c.direction == "DOWN" then return 0, -d end
	return d, 0
end

local function LayoutHolder()
	local c = gcfg()
	local long = c.count * c.size + (c.count - 1) * c.spacing
	if c.direction == "UP" or c.direction == "DOWN" then
		holder:SetSize(c.size, long)
	else
		holder:SetSize(long, c.size)
	end
	ns:ApplyPoint(holder, c.point)
end

-- the first icon sits at the end the strip grows from
local function Origin()
	local c = gcfg()
	if c.direction == "LEFT" then return "RIGHT"
	elseif c.direction == "UP" then return "BOTTOM"
	elseif c.direction == "DOWN" then return "TOP" end
	return "LEFT"
end

local function Acquire()
	local f = table.remove(pool)
	if not f then
		f = CreateFrame("Frame", nil, holder)
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetAllPoints()
		f.mark = f:CreateTexture(nil, "OVERLAY")
		f.mark:SetAllPoints()
		f.mark:SetColorTexture(0.9, 0.1, 0.1, 0.45)
		ns.IconBorder(f)
	end
	local c = gcfg()
	f:SetSize(c.size, c.size)
	ns.ZoomIcon(f.icon)
	f:SetAlpha(1)
	f:Show()
	return f
end

local function Release(entry)
	entry.frame:Hide()
	entry.frame:ClearAllPoints()
	table.insert(pool, entry.frame)
end

local function Place(entry, x, y)
	entry.x, entry.y = x, y
	entry.frame:ClearAllPoints()
	local o = Origin()
	entry.frame:SetPoint(o, holder, o, x, y)
end

local function Ignored(spellID)
	if issecret(spellID) or type(spellID) ~= "number" then return false end
	for _, id in ipairs(gcfg().ignore or {}) do
		if id == spellID then return true end
	end
	return false
end

function MISC.AddCast(spellID, interrupted)
	if not holder then return end
	local c = gcfg()
	if not issecret(spellID) and Ignored(spellID) then return end
	local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
	if not issecret(tex) and tex == nil then return end
	local f = Acquire()
	f.icon:SetTexture(tex)
	f.mark:SetShown(interrupted and true or false)
	-- the new icon appears one step "before" the origin and slides in
	local sx, sy = Offset(0)
	local entry = { frame = f, born = GetTime() }
	Place(entry, sx, sy)
	table.insert(icons, 1, entry)
	while #icons > c.count do Release(table.remove(icons)) end
end

local function Animate(_, elapsed)
	local c = gcfg()
	local now = GetTime()
	local k = math.min(1, (elapsed or 0.016) * 12)
	for i = #icons, 1, -1 do
		local e = icons[i]
		local age = now - e.born
		if age >= c.duration then
			Release(table.remove(icons, i))
		else
			local tx, ty = Offset(i)
			local x = e.x + (tx - e.x) * k
			local y = e.y + (ty - e.y) * k
			if math.abs(tx - x) < 0.5 then x = tx end
			if math.abs(ty - y) < 0.5 then y = ty end
			if x ~= e.x or y ~= e.y then Place(e, x, y) end
			-- fade during the last second, and fade in over the first 0.15s
			local a = 1
			if age > c.duration - 1 then a = c.duration - age end
			if age < 0.15 then a = math.min(a, age / 0.15) end
			e.frame:SetAlpha(math.max(0, a))
		end
	end
end

local function ShouldShow()
	local c = gcfg()
	if ns.unlocked or MISC.testing then return true end
	if c.where == "combat" then return UnitAffectingCombat("player") and true or false end
	if c.where == "pvp" then
		local _, kind = IsInInstance()
		return kind == "arena" or kind == "pvp"
	end
	return true
end

local function UpdateShown()
	if not holder then return end
	holder.SUIActive = gcfg().enabled -- no mover box while it's off
	holder:SetShown(gcfg().enabled and ShouldShow())
end
MISC.UpdateGCDShown = UpdateShown

local function OnCast(event, unit, castGUID, spellID)
	if unit ~= "player" or not gcfg().enabled then return end
	if not issecret(castGUID) and castGUID ~= nil then
		if castGUID == lastCast then return end
		lastCast = castGUID
	end
	MISC.AddCast(spellID, false)
end

local function OnInterrupted(event, unit, castGUID, spellID)
	if unit ~= "player" or not gcfg().enabled or not gcfg().showInterrupted then return end
	MISC.AddCast(spellID, true)
end

-- Preview: a few Warlock spells, one every 0.7s.
local TEST_SPELLS = { 686, 172, 980, 5782, 6789, 30283, 17962, 116858 }
function MISC.TestGCD()
	if not holder then return end
	MISC.testing = true
	UpdateShown()
	for i, id in ipairs(TEST_SPELLS) do
		C_Timer.After((i - 1) * 0.7, function() MISC.AddCast(id, i == 4) end)
	end
	C_Timer.After(#TEST_SPELLS * 0.7 + gcfg().duration, function()
		MISC.testing = false
		UpdateShown()
	end)
end

local function InitGCD()
	holder = CreateFrame("Frame", "StinkieUI_GCDHistory", UIParent)
	holder:SetFrameStrata("MEDIUM")
	LayoutHolder()
	holder:SetScript("OnUpdate", Animate)
	ns:RegisterMover("gcdHistory", holder, "GCD History",
		function() return gcfg().point end,
		function(p) gcfg().point = p end)
	-- player-only registration, so other units' casts never wake this up
	local events = CreateFrame("Frame")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
	events:SetScript("OnEvent", function(_, event, ...)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then OnCast(event, ...) else OnInterrupted(event, ...) end
	end)
	ns:On("PLAYER_REGEN_DISABLED", UpdateShown)
	ns:On("PLAYER_REGEN_ENABLED", UpdateShown)
	ns:On("PLAYER_ENTERING_WORLD", UpdateShown)
	table.insert(ns.lockCallbacks, UpdateShown)
	UpdateShown()
end

---------------------------------------------------------------------------
-- Auto-Confirm Decor Purchases
-- Blizzard asks for confirmation on non-refundable, currency/item-cost and expensive vendor
-- purchases. For housing decor only, this buys right away and closes the popup. It runs inside
-- your own click on the vendor (the popup opens from that click), and never touches the
-- real-money shop.
---------------------------------------------------------------------------
local CONFIRM_POPUPS = {
	CONFIRM_PURCHASE_NONREFUNDABLE_ITEM = true,
	CONFIRM_PURCHASE_TOKEN_ITEM = true,
	CONFIRM_HIGH_COST_ITEM = true,
}

local function IsDecor(link)
	if type(link) ~= "string" then return false end
	if C_Item and C_Item.IsDecorItem then
		local ok, r = pcall(C_Item.IsDecorItem, link)
		if ok and r then return true end
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, link)
		local housing = Enum and Enum.ItemClass and Enum.ItemClass.Housing or 20
		if ok and classID == housing then return true end
	end
	return false
end
MISC.IsDecor = IsDecor

local function TotalCopper(index, count)
	if not (C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return 0 end
	local info = C_MerchantFrame.GetItemInfo(index)
	if type(info) ~= "table" or type(info.price) ~= "number" then return 0 end
	local stack = (type(info.stackCount) == "number" and info.stackCount > 0) and info.stackCount or 1
	return info.price * math.max(1, (count or 1) / stack)
end

function MISC.OnPopup(which)
	local c = dcfg()
	if not c.enabled or not CONFIRM_POPUPS[which] then return end
	if not (MerchantFrame and MerchantFrame:IsShown()) then return end
	local index, count = MerchantFrame.itemIndex, MerchantFrame.count or 1
	if type(index) ~= "number" then return end
	local link = GetMerchantItemLink(index)
	if not IsDecor(link) then return end
	local copper = TotalCopper(index, count)
	if (c.maxGold or 0) > 0 and copper > c.maxGold * 10000 then return end
	StaticPopup_Hide(which)
	BuyMerchantItem(index, count)
	if c.announce then
		ns:Print("Bought " .. (count > 1 and (count .. "x ") or "") .. link .. " (decor, confirmed for you).")
	end
end

local function InitDecor()
	if type(StaticPopup_Show) ~= "function" then return end
	hooksecurefunc("StaticPopup_Show", function(which) MISC.OnPopup(which) end)
end

---------------------------------------------------------------------------
function MISC:Init()
	InitGCD()
	InitDecor()
end

function MISC:Refresh()
	if not holder then return end
	LayoutHolder()
	for _, e in ipairs(icons) do
		e.frame:SetSize(gcfg().size, gcfg().size)
		ns.ZoomIcon(e.frame.icon)
		ns.IconBorder(e.frame)
	end
	UpdateShown()
end

ns:RegisterModule("Misc", MISC)
