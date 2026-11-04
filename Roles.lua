-- StinkieUI: who is a healer. Sources, best first:
--   1. group role (party/raid members),
--   2. the battleground scoreboard (enemy specs learned before the gates open),
--   3. inspecting nearby players (town, open world), one at a time, out of combat only.
-- Anything Blizzard returns as secret is treated as unknown.
local _, ns = ...

local R = {}
ns.Roles = R

local issecret = ns.issecret
local function readable(v) return not issecret(v) and v ~= nil end -- secret check first: secrets are never compared

local byGUID = {}   -- guid -> role from an inspect
local iconByGUID = {} -- guid -> spec icon from an inspect
local callbacks = {}

function R:OnChange(fn) table.insert(callbacks, fn) end
local function Changed()
	for _, fn in ipairs(callbacks) do fn() end
end

function R.GetRole(unit)
	if not unit then return nil end
	local role = UnitGroupRolesAssigned(unit)
	if readable(role) and role ~= "NONE" then return role end
	local guid = UnitGUID(unit)
	if readable(guid) and byGUID[guid] then return byGUID[guid] end
	if ns.BGEnemies and ns.BGEnemies.RoleForUnit then
		local r = ns.BGEnemies.RoleForUnit(unit)
		if r then return r end
	end
	return nil
end

---------------------------------------------------------------------------
-- Inspect queue
---------------------------------------------------------------------------
local queue, queued = {}, {}
local pending -- { unit, guid, time }

-- Spec icon for a unit: the player's own spec, or one learned by inspecting.
function R.GetSpecIcon(unit)
	if not unit then return nil end
	local guid = UnitGUID(unit)
	if readable(guid) and iconByGUID[guid] then return iconByGUID[guid] end
	return nil
end

function R.Request(unit, forSpec)
	local np = ns.db.nameplates
	if not (np.inspectHealers or (forSpec and np.specIcons)) then return end
	local isPlayer = UnitIsPlayer(unit)
	if not readable(isPlayer) or not isPlayer then return end
	local guid = UnitGUID(unit)
	if not readable(guid) or (byGUID[guid] and (not forSpec or iconByGUID[guid])) or queued[guid] or #queue >= 40 then return end
	queued[guid] = true
	table.insert(queue, { unit = unit, guid = guid })
end

local function Busy()
	if InCombatLockdown() then return true end
	-- don't fight the player's own inspect window
	if InspectFrame and InspectFrame:IsShown() then return true end
	local _, instanceType = IsInInstance()
	if instanceType == "arena" or instanceType == "pvp" then return true end
	return false
end

local function Next()
	if pending and GetTime() - pending.time < 4 then return end
	pending = nil
	if Busy() then return end
	while #queue > 0 do
		local item = table.remove(queue, 1)
		queued[item.guid] = nil
		local u = item.unit
		local guid = UnitExists(u) and UnitGUID(u)
		if guid and readable(guid) and guid == item.guid and not iconByGUID[guid] then
			local ok, can = pcall(CanInspect, u)
			if ok and readable(can) and can then
				pending = { unit = u, guid = guid, time = GetTime() }
				NotifyInspect(u)
				return
			end
		end
	end
end

function R:Init()
	local f = CreateFrame("Frame")
	f:RegisterEvent("INSPECT_READY")
	f:SetScript("OnEvent", function(_, _, guid)
		if not (pending and guid == pending.guid) then return end
		local u = pending.unit
		pending = nil
		if UnitExists(u) and UnitGUID(u) == guid then
			local specID = GetInspectSpecialization and GetInspectSpecialization(u)
			if readable(specID) and specID > 0 and GetSpecializationInfoByID then
				local _, _, _, icon, role = GetSpecializationInfoByID(specID)
				if readable(role) then byGUID[guid] = role end
				if readable(icon) then iconByGUID[guid] = icon end
				Changed()
			end
		end
		if not (InspectFrame and InspectFrame:IsShown()) then ClearInspectPlayer() end
	end)
	C_Timer.NewTicker(1.5, ns.Timed("Healer inspects", Next))
end

ns:RegisterModule("Roles", R)
