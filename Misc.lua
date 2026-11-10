-- StinkieUI: miscellaneous. GCD History (a strip of the spells you just cast, sliding along as
-- you cast more), APM (your casts per minute), Auto-Confirm Decor Purchases (skips the "are you sure" popup when buying
-- housing decor from a vendor) and small errands: quests, repairs, junk and releasing in PvP.
local _, ns = ...

local MISC = {}
ns.Misc = MISC

local issecret = ns.issecret
local function gcfg() return ns.db.misc.gcd end
local function dcfg() return ns.db.misc.decor end
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
