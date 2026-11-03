-- StinkieUI: Window Mover (replaces BlizzMove). Drag Blizzard's windows (character, spellbook and
-- talents, collections, group finder, map, bags, mail, vendors...) by any empty part of them, and
-- Ctrl + mouse wheel over a window to make it bigger or smaller. Positions and sizes are
-- remembered, and re-applied whenever the window opens or Blizzard re-lays out its panels.
-- Alt + right-click a window to reset it. Windows that Blizzard protects only move out of combat.
-- Turns itself off while BlizzMove is loaded (both would fight over the same windows).
local _, ns = ...

local WM = {}
ns.WindowMover = WM

local function cfg() return ns.db.windowMover end

-- window name -> label; load-on-demand windows are picked up when their addon loads
WM.FRAMES = {
	{ "CharacterFrame", "Character" }, { "InspectFrame", "Inspect" }, { "PlayerSpellsFrame", "Spellbook & Talents" },
	{ "ProfessionsBookFrame", "Professions book" }, { "CollectionsJournal", "Collections" }, { "EncounterJournal", "Adventure Guide" },
	{ "PVEFrame", "Group Finder / PvP" }, { "AchievementFrame", "Achievements" }, { "CommunitiesFrame", "Guild & Communities" },
	{ "FriendsFrame", "Social" }, { "WorldMapFrame", "Map & Quest Log" }, { "QuestFrame", "Quest" }, { "QuestLogPopupDetailFrame", "Quest details" },
	{ "GossipFrame", "Gossip" }, { "MerchantFrame", "Vendor" }, { "MailFrame", "Mail" }, { "OpenMailFrame", "Open mail" },
	{ "BankFrame", "Bank" }, { "GuildBankFrame", "Guild bank" }, { "ContainerFrameCombinedBags", "Bags" },
	{ "DressUpFrame", "Dressing room" }, { "TradeFrame", "Trade" }, { "LootFrame", "Loot" }, { "ItemTextFrame", "Books / letters" },
	{ "ProfessionsFrame", "Professions" }, { "AuctionHouseFrame", "Auction House" }, { "ItemUpgradeFrame", "Item upgrade" },
	{ "WeeklyRewardsFrame", "Great Vault" }, { "MacroFrame", "Macros" }, { "AddonList", "AddOns" }, { "ChannelFrame", "Chat channels" },
	{ "CalendarFrame", "Calendar" }, { "TimeManagerFrame", "Clock" }, { "ClassTrainerFrame", "Trainer" }, { "StableFrame", "Stable" },
	{ "ScrappingMachineFrame", "Scrapper" }, { "BlackMarketFrame", "Black Market" }, { "ChallengesKeystoneFrame", "Keystone" },
	{ "GenericTraitFrame", "Trait trees" }, { "DelvesCompanionConfigurationFrame", "Delve companion" }, { "ExpansionLandingPage", "Expansion summary" },
	{ "HousingDashboardFrame", "Housing dashboard" }, { "PlayerChoiceFrame", "Choices" }, { "TokenFramePopup", "Currency options" },
	{ "PVPMatchScoreboard", "PvP scoreboard" }, { "PVPMatchResults", "PvP results" }, { "SettingsPanel", "Settings" },
}

-- windows whose size is also a Stinkie UI setting (kept in step with the Character Sheet page)
local SCALE_SETTING = {
	CharacterFrame = function() return ns.db.character, "scale" end,
	InspectFrame = function() return ns.db.character, "inspectScale" end,
}

local session = {} -- positions kept for this session only (when "remember" is off)

local function Store()
	if cfg().remember then
		cfg().frames = cfg().frames or {}
		return cfg().frames
	end
	return session
end

function WM.GetScale(name)
	local s = SCALE_SETTING[name]
	if s then
		local t, k = s()
		if t and t.enabled ~= false then return t[k] or 1 end
	end
	local e = Store()[name]
	return e and e.scale or nil
end

function WM.SetScale(name, scale)
	local s = SCALE_SETTING[name]
	if s then
		local t, k = s()
		if t then t[k] = scale end
	end
	local st = Store()
	st[name] = st[name] or {}
	st[name].scale = scale
end

function WM.Active()
	return cfg().enabled and not WM.blocked
end

local function CanTouch(frame)
	return not (InCombatLockdown() and frame:IsProtected())
end

-- puts a window where (and at the size) it was left
function WM.Apply(name)
	if not WM.Active() then return end
	local frame = _G[name]
	if not frame or not frame.SUIMove then return end
	if not CanTouch(frame) then
		ns:RunOOC(function() WM.Apply(name) end)
		return
	end
	local scale = WM.GetScale(name)
	if scale and math.abs(frame:GetScale() - scale) > 0.001 then frame:SetScale(scale) end
	local e = Store()[name]
	if e and e.point then
		frame:ClearAllPoints()
		frame:SetPoint(e.point[1], UIParent, e.point[1], e.point[2], e.point[3])
	end
end

local function SavePoint(name, frame)
	local p = ns.CalculatePoint(frame)
	if not p then return end
	local st = Store()
	st[name] = st[name] or {}
	st[name].point = p
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

local MODIFIERS = {
	none = function() return true end,
	alt = IsAltKeyDown, shift = IsShiftKeyDown, ctrl = IsControlKeyDown,
}

-- the size a window goes back to: Stinkie UI's default for the character / inspect windows, else 1
local function DefaultScale(name)
	if name == "CharacterFrame" then return ns.defaults.character.scale end
	if name == "InspectFrame" then return ns.defaults.character.inspectScale end
	return 1
end

function WM.Reset(name)
	local frame = _G[name]
	if SCALE_SETTING[name] then
		local t, k = SCALE_SETTING[name]()
		if t then t[k] = DefaultScale(name) end
	end
	Store()[name] = nil
	if frame and CanTouch(frame) then frame:SetScale(DefaultScale(name)) end
	ns:Print((name) .. " reset. Blizzard places it again the next time it opens.")
end

local function Hook(frame, name)
	if frame.SUIMove then return end
	frame.SUIMove = true
	if not (InCombatLockdown() and frame:IsProtected()) then
		frame:SetMovable(true)
		if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
		if not frame:IsMouseEnabled() then frame:EnableMouse(true) end
		if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
	end
	frame:HookScript("OnMouseDown", function(self, button)
		if not WM.Active() then return end
		if button == "LeftButton" then
			local mod = MODIFIERS[cfg().modifier] or MODIFIERS.none
			if mod() and CanTouch(self) then
				self:SetMovable(true)
				self:StartMoving()
				self.SUIMoving = true
			end
		elseif button == "RightButton" and IsAltKeyDown() then
			WM.Reset(name)
		end
	end)
	frame:HookScript("OnMouseUp", function(self)
		if self.SUIMoving then
			self.SUIMoving = nil
			self:StopMovingOrSizing()
			if self.SetUserPlaced then self:SetUserPlaced(false) end -- we remember it, not the game's layout cache
			SavePoint(name, self)
		end
	end)
	frame:HookScript("OnHide", function(self)
		if self.SUIMoving then
			self.SUIMoving = nil
			self:StopMovingOrSizing()
			SavePoint(name, self)
		end
	end)
	frame:HookScript("OnMouseWheel", function(self, delta)
		if not (WM.Active() and cfg().wheel and IsControlKeyDown() and CanTouch(self)) then return end
		local old = self:GetScale()
		local new = math.max(0.5, math.min(2, math.floor((old + delta * 0.05) * 100 + 0.5) / 100))
		if new == old then return end
		-- keep the window's center where it is
		local cx, cy = self:GetCenter()
		self:SetScale(new)
		if cx then
			self:ClearAllPoints()
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * old / new, cy * old / new)
			SavePoint(name, self)
		end
		WM.SetScale(name, new)
	end)
	frame:HookScript("OnShow", function() WM.Apply(name) end)
	if frame:IsShown() then WM.Apply(name) end
end

function WM.HookAll()
	if not WM.Active() then return end
	for _, f in ipairs(WM.FRAMES) do
		local frame = _G[f[1]]
		if type(frame) == "table" and frame.HookScript and frame.GetObjectType then pcall(Hook, frame, f[1]) end
	end
	for _, name in ipairs(cfg().extra or {}) do
		local frame = _G[name]
		if type(frame) == "table" and frame.HookScript and frame.GetObjectType then pcall(Hook, frame, name) end
	end
end

function WM.ResetAll()
	wipe(session)
	for name in pairs(SCALE_SETTING) do
		local s = SCALE_SETTING[name]
		local t, k = s()
		if t then t[k] = DefaultScale(name) end
	end
	cfg().frames = {}
	for _, f in ipairs(WM.FRAMES) do
		local frame = _G[f[1]]
		if frame and frame.SUIMove and CanTouch(frame) then frame:SetScale(DefaultScale(f[1])) end
	end
	ns:Print("All windows reset. Blizzard places them again the next time they open.")
end

function WM:Init()
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if isLoaded and isLoaded("BlizzMove") then
		WM.blocked = true
		if cfg().enabled then ns:Print("Window Mover is off while BlizzMove is enabled. Disable BlizzMove to use it.") end
		return
	end
	WM.HookAll()
	ns:On("ADDON_LOADED", function() WM.HookAll() end)
	-- Blizzard re-lays out its side panels when one opens or closes; put moved ones back
	if _G.UpdateUIPanelPositions then
		hooksecurefunc("UpdateUIPanelPositions", function()
			if not WM.Active() then return end
			for _, f in ipairs(WM.FRAMES) do
				local frame = _G[f[1]]
				if frame and frame.SUIMove and frame:IsShown() and Store()[f[1]] then WM.Apply(f[1]) end
			end
		end)
	end
end

function WM:Refresh()
	if WM.blocked then return end
	WM.HookAll()
	for _, f in ipairs(WM.FRAMES) do
		local frame = _G[f[1]]
		if frame and frame.SUIMove and frame:IsShown() then WM.Apply(f[1]) end
	end
end

ns:RegisterModule("WindowMover", WM)
