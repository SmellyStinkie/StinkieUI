-- StinkieUI: miscellaneous. GCD History (a strip of the spells you just cast, sliding along as
-- you cast more), APM (your casts per minute), Auto-Confirm Decor Purchases (skips the "are you sure" popup when buying
-- housing decor from a vendor) and small errands: quests, repairs, junk and releasing in PvP.
local _, ns = ...

local MISC = {}
ns.Misc = MISC

local issecret = ns.issecret
local function gcfg() return ns.db.misc.gcd end
local function dcfg() return ns.db.misc.decor end
local function qcfg() return ns.db.misc.quickBuy end
local function acfg() return ns.db.misc.auto end

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
	if MISC.Animate then holder:SetScript("OnUpdate", MISC.Animate) end
end

local function Animate(self, elapsed)
	-- nothing on screen: stop running every frame until the next cast
	if #icons == 0 then self:SetScript("OnUpdate", nil) return end
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

-- where: always | combat | pvp
local function ShouldShow(where, forced)
	if forced then return true end
	if where == "combat" then return UnitAffectingCombat("player") and true or false end
	if where == "pvp" then
		local _, kind = IsInInstance()
		return kind == "arena" or kind == "pvp"
	end
	return true
end

local function UpdateShown()
	if not holder then return end
	holder.SUIActive = gcfg().enabled -- no mover box while it's off
	holder:SetShown(gcfg().enabled and ShouldShow(gcfg().where, ns.unlocked or MISC.testing))
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
	MISC.Animate = ns.Timed("GCD History", Animate)
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
-- APM: your actions per minute, counted from your own successful casts (auto attacks and auto
-- shots left out) or from your key presses. The number is the casts of the last few seconds scaled to a minute; next to it
-- the average over the current fight, or the last one once it's over.
---------------------------------------------------------------------------
local function apcfg() return ns.db.misc.apm end
local APM = { times = {} }
MISC.APM = APM
local AUTO = { [6603] = true, [75] = true } -- Auto Attack, Auto Shot
APM.SAMPLE = "42"
APM.SAMPLE_FIGHT = "38"

function APM.Add(spellID, now)
	if spellID ~= nil and not issecret(spellID) and AUTO[spellID] then return end
	APM.times[#APM.times + 1] = now
	if APM.fightStart then APM.fightCount = APM.fightCount + 1 end
end

-- Key presses. The game only hands keys to an addon frame by routing them through it, and a key
-- bind run from there runs as the addon: protected actions then fail (the world map in combat)
-- and Blizzard code it touches is tainted. So no keyboard frame: each frame we ask whether the
-- keys people bind are down, and count a key when it goes down. A held key counts once; Shift,
-- Ctrl and Alt alone aren't in the list. While you type in a chat box nothing is counted.
local function KeyList()
	local keys = {}
	for c = string.byte("A"), string.byte("Z") do keys[#keys + 1] = string.char(c) end
	for i = 0, 9 do keys[#keys + 1] = tostring(i); keys[#keys + 1] = "NUMPAD" .. i end
	for i = 1, 12 do keys[#keys + 1] = "F" .. i end
	for _, k in ipairs({ "SPACE", "TAB", "ENTER", "BACKSPACE", "ESCAPE", "UP", "DOWN", "LEFT", "RIGHT",
		"INSERT", "DELETE", "HOME", "END", "PAGEUP", "PAGEDOWN", "NUMPADPLUS", "NUMPADMINUS",
		"NUMPADMULTIPLY", "NUMPADDIVIDE", "NUMPADDECIMAL", "-", "=", "[", "]", ";", "'", ",", ".", "/",
		"`", "\\", "BUTTON3", "BUTTON4", "BUTTON5" }) do keys[#keys + 1] = k end
	-- a name this client doesn't know is dropped once, here
	local ok = {}
	for _, k in ipairs(keys) do
		local fine, down = pcall(IsKeyDown, k)
		if fine and (down == true or down == false or down == nil) then ok[#ok + 1] = k end
	end
	return ok
end

APM.down = {}

function APM.PollKeys(now)
	if not APM.keyList then APM.keyList = KeyList() end
	local typing = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	local down = APM.down
	for _, k in ipairs(APM.keyList) do
		local d = IsKeyDown(k) and true or false
		if d and not down[k] and not typing then APM.Add(nil, now) end
		down[k] = d or nil
	end
end

local function WantKeys() return apcfg().enabled and apcfg().count == "keys" end

-- its own frame, so polling stops whenever key presses are off (no combat rules involved)
function APM.ApplyKeys()
	local want = WantKeys() and true or false
	if not APM.keys then
		if not want then return end
		APM.keys = CreateFrame("Frame", nil, UIParent)
		-- 50 times a second is enough to see a tap, and at high frame rates it's far fewer checks
		local since = 0
		APM.keys:SetScript("OnUpdate", function(_, dt)
			since = since + dt
			if since < 0.02 then return end
			since = 0
			APM.PollKeys(GetTime())
		end)
	end
	if want and not APM.keysOn then APM.down = {} end
	APM.keys:SetShown(want)
	APM.keysOn = want
end

function APM.Current(now)
	local t, window = APM.times, apcfg().window
	local cutoff = now - window
	while t[1] and t[1] < cutoff do table.remove(t, 1) end
	return math.floor(#t * 60 / window + 0.5)
end

-- nil for the first few seconds of a fight, when one cast would read as a huge number
function APM.FightAverage(now)
	if not APM.fightStart then return APM.lastFight end
	local secs = now - APM.fightStart
	if secs < 5 then return APM.lastFight end
	return math.floor(APM.fightCount * 60 / secs + 0.5)
end

function APM.StartFight(now) APM.fightStart, APM.fightCount = now, 0 end
function APM.EndFight(now)
	if not APM.fightStart then return end
	local secs = now - APM.fightStart
	if secs >= 5 then APM.lastFight = math.floor(APM.fightCount * 60 / secs + 0.5) end
	APM.fightStart = nil
end

function APM.Text(now)
	local c = apcfg()
	local cur, fight
	if ns.unlocked and #APM.times == 0 then
		cur, fight = APM.SAMPLE, APM.SAMPLE_FIGHT -- something to place it by
	else
		cur, fight = APM.Current(now), APM.FightAverage(now)
	end
	local s = (c.label and "APM " or "") .. cur
	if c.showFight and fight then s = s .. "  |cff999999fight " .. fight .. "|r" end
	return s
end

function APM.Paint()
	if not APM.frame then return end
	APM.frame.text:SetText(APM.Text(GetTime()))
end

function APM.Layout()
	local f, c = APM.frame, apcfg()
	ns.ApplyText(f.text, c.textStyle)
	local size = c.textStyle.size or 16
	f:SetSize(size * 8, size + 8)
	f.text:ClearAllPoints()
	f.text:SetPoint("CENTER")
	ns:ApplyPoint(f, c.point)
end

function APM.UpdateShown()
	if not APM.frame then return end
	local on = apcfg().enabled
	APM.frame.SUIActive = on
	APM.frame:SetShown(on and ShouldShow(apcfg().where, ns.unlocked) or false)
	APM.Paint()
end

local function InitAPM()
	local f = CreateFrame("Frame", "StinkieUI_APM", UIParent)
	f:SetFrameStrata("MEDIUM")
	f.text = f:CreateFontString(nil, "OVERLAY")
	APM.frame = f
	APM.Layout()
	ns:RegisterMover("apm", f, "APM",
		function() return apcfg().point end,
		function(p) apcfg().point = p end)
	-- the number moves while you're idle too (old casts drop out), so repaint twice a second
	local acc = 0
	f:SetScript("OnUpdate", function(_, dt)
		acc = acc + dt
		if acc < 0.5 then return end
		acc = 0
		APM.Paint()
	end)
	local events = CreateFrame("Frame")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	events:SetScript("OnEvent", function(_, _, unit, _, spellID)
		if unit == "player" and apcfg().enabled and apcfg().count ~= "keys" then APM.Add(spellID, GetTime()) end
	end)
	ns:On("PLAYER_REGEN_DISABLED", function() APM.StartFight(GetTime()); APM.UpdateShown() end)
	ns:On("PLAYER_REGEN_ENABLED", function() APM.EndFight(GetTime()); APM.UpdateShown() end)
	ns:On("PLAYER_ENTERING_WORLD", APM.UpdateShown)
	table.insert(ns.lockCallbacks, APM.UpdateShown)
	APM.UpdateShown()
	APM.ApplyKeys()
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

-- Putting an item that can still be refunded into the warband bank asks first.
local BANK_REFUND_POPUPS = {
	ACCOUNT_BANK_DEPOSIT_NO_REFUND_CONFIRM = true,
	ACCOUNT_BANK_DEPOSIT_ALL_NO_REFUND_CONFIRM = true,
}

-- Answers that popup with "yes": does the deposit the popup was asking about, then closes it.
-- data is what Blizzard gave the popup: the item, and the bank slot it was dropped on (if any).
function MISC.OnBankPopup(which, data)
	local q = qcfg()
	if not (q.enabled and q.bankRefund) then return false end
	local account = Enum.BankType and Enum.BankType.Account
	if not (account and C_Bank) then return false end
	local ok, done = pcall(function()
		if which == "ACCOUNT_BANK_DEPOSIT_ALL_NO_REFUND_CONFIRM" then
			C_Bank.AutoDepositItemsIntoBank(account)
			return true
		end
		if type(data) ~= "table" or not data.itemToDeposit then return false end
		if data.targetItemLocation then -- dropped on a slot: the item is still on the cursor
			local bag, slot = data.targetItemLocation:GetBagAndSlot()
			if not (bag and slot) then return false end
			C_Container.PickupContainerItem(bag, slot)
			return true
		end
		local bag, slot = data.itemToDeposit:GetItemLocation():GetBagAndSlot() -- right clicked in the bags
		if not (bag and slot) then return false end
		C_Container.UseContainerItem(bag, slot, nil, account, false)
		return true
	end)
	if not (ok and done) then return false end
	StaticPopup_Hide(which)
	return true
end

function MISC.OnPopup(which, data)
	if BANK_REFUND_POPUPS[which] then MISC.OnBankPopup(which, data) return end
	if not CONFIRM_POPUPS[which] then return end
	local c, q = dcfg(), qcfg()
	local every = q.enabled and q.skipConfirm -- every purchase, not only decor
	if not (every or c.enabled) then return end
	if not (MerchantFrame and MerchantFrame:IsShown()) then return end
	local index, count = MerchantFrame.itemIndex, MerchantFrame.count or 1
	if type(index) ~= "number" then return end
	local link = GetMerchantItemLink(index)
	local decor = c.enabled and IsDecor(link)
	if decor and (c.maxGold or 0) > 0 and TotalCopper(index, count) > c.maxGold * 10000 then decor = false end
	if not (every or decor) then return end
	StaticPopup_Hide(which)
	BuyMerchantItem(index, count)
	if decor and c.announce then
		ns:Print("Bought " .. (count > 1 and (count .. "x ") or "") .. link .. " (decor, confirmed for you).")
	elseif not decor and q.announce then
		ns:Print("Bought " .. (count > 1 and (count .. "x ") or "") .. tostring(link) .. ".")
	end
end

local function InitDecor()
	if type(StaticPopup_Show) ~= "function" then return end
	hooksecurefunc("StaticPopup_Show", function(which, _, _, data) MISC.OnPopup(which, data) end)
end

---------------------------------------------------------------------------
-- Quick Buy
-- Shift + right click on a vendor item opens a small box: type a number, or press Stack or Max,
-- then Buy. The box shows the total cost and is the confirmation: the purchase goes straight to
-- the vendor, so the game's own "are you sure" popups don't come up. Blizzard's stack-split box
-- (one stack at most, stackable items only) is closed in its favor.
---------------------------------------------------------------------------
local QB = {}
MISC.QuickBuy = QB
QB.MAX_CALLS = 250 -- purchases sent for one Buy, at most

-- free slots in the ordinary bags
function QB.FreeSlots()
	local free = 0
	for bag = 0, type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS or 4 do
		local n, family = C_Container.GetContainerNumFreeSlots(bag)
		if type(n) == "number" and (family == nil or family == 0) then free = free + n end
	end
	return free
end

-- What a vendor slot sells: the price of one purchase ("bundle" items at a time), what else it
-- costs, and how many you could buy. afford: what your gold, currencies and the vendor's stock
-- allow. max: that, and what fits in your free bag slots.
function QB.Info(index)
	if type(index) ~= "number" or not (C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return nil end
	local info = C_MerchantFrame.GetItemInfo(index)
	if type(info) ~= "table" or not info.name then return nil end
	local bundle = math.max(1, tonumber(info.stackCount) or 1)
	local maxStack = math.max(1, tonumber(GetMerchantItemMaxStack(index)) or 1)
	local price = tonumber(info.price) or 0
	local limit -- in purchases; nil = nothing limits it
	local function cap(n)
		n = math.max(0, math.floor(n))
		if not limit or n < limit then limit = n end
	end
	if price > 0 then cap(GetMoney() / price) end
	local costs = {}
	if info.hasExtendedCost then
		for i = 1, type(MAX_ITEM_COST) == "number" and MAX_ITEM_COST or 3 do
			local texture, value, link, currencyName = GetMerchantItemCostItem(index, i)
			if type(value) == "number" and value > 0 and (link or currencyName) then
				local have
				if currencyName then
					local cur = link and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink and C_CurrencyInfo.GetCurrencyInfoFromLink(link)
					have = type(cur) == "table" and cur.quantity or nil
				else
					have = C_Item.GetItemCount(link, false, false, true)
				end
				costs[#costs + 1] = { value = value, texture = texture, name = currencyName or (type(link) == "string" and link:match("%[(.-)%]")) or "?" }
				if type(have) == "number" then cap(have / value) end
			end
		end
	end
	local stock = tonumber(info.numAvailable)
	if stock and stock >= 0 then cap(stock) end
	local stack = math.max(bundle, math.floor(maxStack / bundle) * bundle) -- the most one purchase call takes
	local fits = math.floor(QB.FreeSlots() * maxStack / bundle)
	local afford = limit or math.max(fits, stack / bundle)
	return {
		index = index, name = info.name, texture = info.texture, link = GetMerchantItemLink(index),
		bundle = bundle, stack = stack, price = price, costs = costs,
		afford = afford * bundle, max = math.min(afford, fits) * bundle,
	}
end

-- A typed number as one you can buy: whole purchases, no more than you can pay for.
function QB.Clamp(d, qty)
	qty = math.floor((tonumber(qty) or 0) / d.bundle) * d.bundle
	return math.max(0, math.min(qty, d.afford, QB.MAX_CALLS * d.stack))
end

function QB.CostText(d, qty)
	local n = qty / d.bundle
	local parts = {}
	if d.price > 0 then
		local copper = d.price * n
		local coins = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
		parts[#parts + 1] = coins and coins(copper) or (math.floor(copper / 10000) .. "g")
	end
	for _, c in ipairs(d.costs) do
		-- the currency's (or item's) icon after the number, as the vendor window shows it
		parts[#parts + 1] = (c.value * n) .. " " .. (c.texture and ("|T" .. c.texture .. ":14:14:0:0|t") or c.name)
	end
	if #parts == 0 then return "Free" end
	return table.concat(parts, ", ")
end

-- Buys qty of the item in that vendor slot, a stack at a time. Returns how many were asked for.
function QB.Buy(index, qty, link)
	local d = QB.Info(index)
	if not d or (link and d.link ~= link) then return 0 end -- the vendor's list changed under the box
	qty = QB.Clamp(d, qty)
	local left = qty
	while left > 0 do
		local n = math.min(left, d.stack)
		BuyMerchantItem(index, n)
		left = left - n
	end
	if qty > 0 and qcfg().announce then
		ns:Print("Bought " .. qty .. "x " .. tostring(d.link or d.name) .. " for " .. QB.CostText(d, qty) .. ".")
	end
	return qty
end

local function QBUpdate(f)
	local d = f.info
	local qty = QB.Clamp(d, f.edit:GetText())
	if qty > 0 then
		f.cost:SetText("Total: " .. QB.CostText(d, qty) .. (qty ~= tonumber(f.edit:GetText()) and ("  (buys " .. qty .. ")") or ""))
	elseif d.afford <= 0 then
		f.cost:SetText("You can't pay for one.")
	else
		f.cost:SetText(d.bundle > 1 and ("Sold " .. d.bundle .. " at a time.") or "Type how many.")
	end
end

local function QBCreate()
	local f = CreateFrame("Frame", "StinkieUIQuickBuy", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetSize(250, 150)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.08, 0.07, 0.06, 0.96)
	ns.CreateBackdrop(f, 0)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(20, 20)
	f.icon:SetPoint("TOPLEFT", 10, -10)
	f.name = ns.CreateText(f, 13, "LEFT")
	f.name:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
	f.name:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	f.name:SetWordWrap(false)

	local eb = CreateFrame("EditBox", nil, f)
	eb:SetSize(90, 22)
	eb:SetPoint("TOP", f, "TOP", 0, -40) -- the number has a row of its own, an arrow on each side
	eb:SetAutoFocus(false)
	ns.SetFont(eb, 13)
	eb:SetJustifyH("CENTER")
	if eb.SetNumeric then eb:SetNumeric(true) end
	if eb.SetMaxLetters then eb:SetMaxLetters(6) end
	eb.bg = eb:CreateTexture(nil, "BACKGROUND")
	eb.bg:SetAllPoints()
	eb.bg:SetColorTexture(0.15, 0.15, 0.17, 1)
	eb:SetScript("OnTextChanged", function() if f.info then QBUpdate(f) end end)
	eb:SetScript("OnEnterPressed", function() f.buy:GetScript("OnClick")(f.buy) end)
	eb:SetScript("OnEscapePressed", function() f:Hide() end)
	f.edit = eb

	-- the buttons light up under the mouse like the buttons in the options window's list
	local P = ns.BRAND.plum
	local function button(text, width)
		local b = ns.DialogButton(f)
		b:SetSize(width, 22)
		b.text:SetText(text)
		b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(P[1] * 0.6, P[2] * 0.6, P[3] * 0.6, 1) end)
		b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.15, 0.13, 0.11, 1) end)
		return b
	end
	local function set(n)
		eb:SetText(tostring(n))
		QBUpdate(f)
		eb:SetFocus()
	end
	-- one purchase fewer / more (one item, or one bundle where the vendor sells several at a time)
	local function step(dir)
		local d = f.info
		local now = math.floor((tonumber(eb:GetText()) or 0) / d.bundle) * d.bundle
		set(math.max(d.bundle, math.min(now + dir * d.bundle, math.max(d.afford, d.bundle))))
	end
	f.less = button("<", 24)
	f.less:SetPoint("RIGHT", eb, "LEFT", -6, 0)
	f.less:SetScript("OnClick", function() step(-1) end)
	f.more = button(">", 24)
	f.more:SetPoint("LEFT", eb, "RIGHT", 6, 0)
	f.more:SetScript("OnClick", function() step(1) end)

	f.stack = button("Stack", 112)
	f.stack:SetPoint("TOPLEFT", 10, -68)
	f.stack:SetScript("OnClick", function() set(math.min(f.info.stack, math.max(f.info.afford, 0))) end)
	f.max = button("Max", 112)
	f.max:SetPoint("TOPRIGHT", -10, -68)
	f.max:SetScript("OnClick", function() set(f.info.max) end)

	f.cost = ns.CreateText(f, 12, "LEFT")
	f.cost:SetPoint("TOPLEFT", 10, -98)
	f.cost:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	f.cost:SetWordWrap(false)

	f.buy = button("Buy", 112)
	f.buy:SetPoint("BOTTOMLEFT", 10, 10)
	f.buy:SetScript("OnClick", function()
		local d = f.info
		f:Hide()
		if d then QB.Buy(d.index, eb:GetText(), d.link) end
	end)
	f.cancel = button("Cancel", 112)
	f.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
	f.cancel:SetScript("OnClick", function() f:Hide() end)
	f:Hide()
	QB.frame = f
	return f
end

-- Opens the box for a vendor slot, beside the button that was clicked.
function QB.Open(index, anchor)
	local d = QB.Info(index)
	if not d then return nil end
	local f = QB.frame or QBCreate()
	f.info = d
	f.icon:SetTexture(d.texture)
	f.name:SetText(d.name)
	f.stack.text:SetText("Stack (" .. d.stack .. ")")
	f.max.text:SetText("Max (" .. d.max .. ")")
	f:ClearAllPoints()
	if anchor then f:SetPoint("BOTTOMLEFT", anchor, "TOPRIGHT", 4, 4) else f:SetPoint("CENTER") end
	f.edit:SetText(tostring(math.min(d.bundle, d.afford)))
	QBUpdate(f)
	f:Show()
	f.edit:SetFocus()
	f.edit:HighlightText()
	return f
end

-- after Blizzard's own handling of a click on a vendor item
function QB.OnClick(button, mouse)
	if not qcfg().enabled or mouse ~= "RightButton" or not IsShiftKeyDown() then return end
	if not MerchantFrame or MerchantFrame.selectedTab ~= 1 then return end -- not the buyback tab
	-- typing somewhere (Shift + click put a link in chat): leave it
	local focus = GetCurrentKeyboardFocus and GetCurrentKeyboardFocus()
	if focus and focus ~= (QB.frame and QB.frame.edit) then return end
	if StackSplitFrame and StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
	QB.Open(button:GetID(), button)
end

local function InitQuickBuy()
	for i = 1, 12 do
		local b = _G["MerchantItem" .. i .. "ItemButton"]
		if b and b.HookScript then b:HookScript("OnClick", QB.OnClick) end
	end
	local function close() if QB.frame then QB.frame:Hide() end end
	ns:On("MERCHANT_CLOSED", close)
	ns:On("MERCHANT_FILTER_ITEM_UPDATE", close)
end

---------------------------------------------------------------------------
-- Auto quests. Hold Shift while talking to an NPC to do it by hand. Anything that needs a decision
-- is left alone: a choice of rewards, a quest that costs gold or currency, and a quest that flags
-- you for PvP (the game asks you to confirm those).
---------------------------------------------------------------------------
local function Say(msg)
	if acfg().announce then ns:Print(msg) end
end

function MISC.OnGossip()
	local c = acfg()
	if IsShiftKeyDown() or not C_GossipInfo then return end
	if c.questTurnIn then
		for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if q.isComplete then C_GossipInfo.SelectActiveQuest(q.questID) return end
		end
	end
	if c.questAccept then
		for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
			if not q.isIgnored then C_GossipInfo.SelectAvailableQuest(q.questID) return end
		end
	end
end

-- the older quest list, from NPCs that have nothing else to say
function MISC.OnQuestGreeting()
	local c = acfg()
	if IsShiftKeyDown() then return end
	if c.questTurnIn then
		for i = 1, GetNumActiveQuests() do
			local _, isComplete = GetActiveTitle(i)
			if isComplete then SelectActiveQuest(i) return end
		end
	end
	if c.questAccept and GetNumAvailableQuests() > 0 then SelectAvailableQuest(1) end
end

function MISC.OnQuestDetail()
	if not acfg().questAccept or IsShiftKeyDown() or QuestFlagsPVP() then return end
	if QuestGetAutoAccept() then AcknowledgeAutoAcceptQuest() else AcceptQuest() end
end

function MISC.OnQuestProgress()
	if not acfg().questTurnIn or IsShiftKeyDown() or not IsQuestCompletable() then return end
	if (GetQuestMoneyToGet() or 0) > 0 or (GetNumQuestCurrencies() or 0) > 0 then return end
	CompleteQuest()
end

function MISC.OnQuestComplete()
	if not acfg().questTurnIn or IsShiftKeyDown() then return end
	if (GetQuestMoneyToGet() or 0) > 0 then return end
	local choices = GetNumQuestChoices()
	if choices > 1 then
		Say("This quest has a choice of rewards, so that one's yours to pick.")
		return
	end
	GetQuestReward(choices)
end

---------------------------------------------------------------------------
-- Auto repair and junk, when a vendor opens. Junk goes first: its gold can pay for the repairs.
---------------------------------------------------------------------------
local function Coins(copper)
	local fmt = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
	return fmt and fmt(copper) or tostring(copper)
end

function MISC.SellJunk()
	local M = C_MerchantFrame
	if M and M.SellAllJunkItems and M.IsSellAllJunkEnabled and M.IsSellAllJunkEnabled() then
		local n = M.GetNumJunkItems and M.GetNumJunkItems() or 0
		if n == 0 then return end
		M.SellAllJunkItems()
		Say("Sold " .. n .. " junk item" .. (n == 1 and "" or "s") .. ".")
		return
	end
	-- clients without Blizzard's own button
	local n = 0
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == 0 and not info.hasNoValue and not info.isLocked then
				C_Container.UseContainerItem(bag, slot)
				n = n + 1
			end
		end
	end
	if n > 0 then Say("Sold " .. n .. " junk item" .. (n == 1 and "" or "s") .. ".") end
end

-- what the guild will pay right now; 0 if it can't or won't
local function GuildFunds()
	if not (CanGuildBankRepair and CanGuildBankRepair()) then return 0 end
	local limit, bank = GetGuildBankWithdrawMoney(), GetGuildBankMoney()
	if limit < 0 then return bank end -- no daily limit
	return math.min(limit, bank)
end

function MISC.Repair()
	if not CanMerchantRepair() then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end
	if acfg().repairGuild and GuildFunds() >= cost then
		RepairAllItems(true)
		Say("Repaired for " .. Coins(cost) .. " (guild funds).")
	elseif GetMoney() >= cost then
		RepairAllItems()
		Say("Repaired for " .. Coins(cost) .. ".")
	else
		Say("Not enough gold to repair (" .. Coins(cost) .. ").")
	end
end

function MISC.OnMerchant()
	local c = acfg()
	if c.sellJunk then MISC.SellJunk() end
	if c.repair then MISC.Repair() end
end

---------------------------------------------------------------------------
-- Auto release in battlegrounds. Arenas have nothing to release to. With a way to come back on the
-- spot (soulstone, reincarnation), the choice stays yours.
---------------------------------------------------------------------------
function MISC.OnDead()
	if not acfg().releasePvP then return end
	local _, kind = IsInInstance()
	if kind ~= "pvp" then return end
	local options = C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions and C_DeathInfo.GetSelfResurrectOptions()
	if options and #options > 0 then return end
	RepopMe()
end

---------------------------------------------------------------------------
-- Hide error messages. Red errors reach Blizzard's message frame on their own event, which also
-- plays their voice line. Yellow messages (quest progress) use another event and stay. We only
-- undo what we did, so another addon doing the same is left alone.
---------------------------------------------------------------------------
function MISC.ApplyHideErrors()
	local frame = _G.UIErrorsFrame
	if not frame then return end
	local hide = acfg().hideErrors and true or false
	if hide == (MISC.errorsHidden or false) then return end
	MISC.errorsHidden = hide
	if hide then
		frame:UnregisterEvent("UI_ERROR_MESSAGE")
	else
		frame:RegisterEvent("UI_ERROR_MESSAGE")
	end
end

local function InitAuto()
	ns:On("GOSSIP_SHOW", MISC.OnGossip)
	ns:On("QUEST_GREETING", MISC.OnQuestGreeting)
	ns:On("QUEST_DETAIL", MISC.OnQuestDetail)
	ns:On("QUEST_PROGRESS", MISC.OnQuestProgress)
	ns:On("QUEST_COMPLETE", MISC.OnQuestComplete)
	ns:On("MERCHANT_SHOW", MISC.OnMerchant)
	ns:On("PLAYER_DEAD", MISC.OnDead)
	MISC.ApplyHideErrors()
end

---------------------------------------------------------------------------
function MISC:Init()
	InitGCD()
	InitAPM()
	InitDecor()
	InitQuickBuy()
	InitAuto()
end

function MISC:Refresh()
	MISC.ApplyHideErrors()
	if not holder then return end
	LayoutHolder()
	for _, e in ipairs(icons) do
		e.frame:SetSize(gcfg().size, gcfg().size)
		ns.ZoomIcon(e.frame.icon)
		ns.IconBorder(e.frame)
	end
	UpdateShown()
	if APM.frame then
		APM.Layout()
		APM.UpdateShown()
		APM.ApplyKeys()
	end
end

ns:RegisterModule("Misc", MISC)
