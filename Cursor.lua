-- StinkieUI: cursor size (Blizzard's own setting) and an optional colored ring that follows
-- the cursor. The cursor image itself is drawn by the system and can't be recolored by addons.
local _, ns = ...

local CU = {}
ns.Cursor = CU

local RINGS = {
	thin = [[Interface\AddOns\StinkieUI\Media\ring_thin]],
	thick = [[Interface\AddOns\StinkieUI\Media\ring_thick]],
}

CU.SIZES = {
	{ -1, "Default" }, { 0, "32" }, { 1, "48" }, { 2, "64" }, { 3, "96" }, { 4, "128" },
}

local function OnUpdate(self)
	local cfg = ns.db.cursor
	local hidden = (IsMouselooking and IsMouselooking()) or (cfg.ringCombatOnly and not InCombatLockdown())
	if hidden then
		self.tex:Hide()
		return
	end
	self.tex:Show()
	local x, y = GetCursorPosition()
	local scale = self:GetEffectiveScale()
	self.tex:ClearAllPoints()
	self.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

function CU:Apply()
	local cfg = ns.db.cursor
	ns:RunOOC(function()
		local cur = tonumber(C_CVar.GetCVar("cursorSizePreferred"))
		if cur ~= cfg.size then pcall(C_CVar.SetCVar, "cursorSizePreferred", tostring(cfg.size)) end
	end)

	if not cfg.ring then
		if CU.frame then CU.frame:Hide() end
		return
	end
	local f = CU.frame
	if not f then
		f = CreateFrame("Frame", nil, UIParent)
		f:SetAllPoints(UIParent)
		f:SetFrameStrata("TOOLTIP")
		f:SetFrameLevel(9999)
		f:EnableMouse(false)
		f.tex = f:CreateTexture(nil, "OVERLAY")
		f:SetScript("OnUpdate", OnUpdate)
		CU.frame = f
	end
	local c = cfg.ringColor
	f.tex:SetTexture(RINGS[cfg.ringThickness] or RINGS.thin, "CLAMP", "CLAMP", "TRILINEAR")
	f.tex:SetVertexColor(c[1], c[2], c[3], 1)
	f.tex:SetAlpha(cfg.ringAlpha)
	f.tex:SetSize(cfg.ringSize, cfg.ringSize)
	f:Show()
end

function CU:Init()
	-- remember what the player had so the setting isn't changed until they touch it here
	if ns.db.cursor.size == nil then
		ns.db.cursor.size = tonumber(C_CVar.GetCVar("cursorSizePreferred")) or -1
	end
	CU:Apply()
end

function CU:Refresh()
	CU:Apply()
end

ns:RegisterModule("Cursor", CU)
