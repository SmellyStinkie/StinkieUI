-- StinkieUI: aura icons via Blizzard's AuraContainer (works in restricted PvP/combat contexts).
local _, ns = ...

-- Filter presets. "!" negates a component, which keeps groups from showing duplicates.
ns.AuraFilters = {
	cc = "HARMFUL|CROWD_CONTROL",
	mine = "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY|!CROWD_CONTROL",
	anyDebuff = "HARMFUL|INCLUDE_NAME_PLATE_ONLY|!CROWD_CONTROL",
	bigDefensive = "HELPFUL|BIG_DEFENSIVE",
	externalDefensive = "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE",
	dispellable = "HARMFUL|RAID_PLAYER_DISPELLABLE|!CROWD_CONTROL",
}

-- Midnight: Blizzard locks every aura button against addon code right after this initializer
-- runs (DenyTaintedAccessWhenAurasAreSecret). While auras are secret (live PvP match, M+, boss
-- encounter) any later touch of a button or anything inside it errors. Everything a button needs
-- is therefore set here, at creation; later restyles wait until auras are no longer secret.
-- After a /reload inside a match, buttons are locked the moment they're made.
function ns.AurasLocked()
	return (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) == true
end

local pending = {}
local function RunSafe(fn)
	local ok, err = pcall(fn)
	if not ok then geterrorhandler()(err) end
end

-- Runs fn now if aura buttons can be touched, otherwise once they can (latest fn per key wins).
function ns.WhenAurasOpen(key, fn)
	if not ns.AurasLocked() then
		pending[key] = nil
		RunSafe(fn)
		return true
	end
	pending[key] = fn
	return false
end

local function FlushPending()
	if not next(pending) or ns.AurasLocked() then return end
	local list = pending
	pending = {}
	for _, fn in pairs(list) do RunSafe(fn) end
end
local function FlushSoon() C_Timer.After(0.5, FlushPending) end
for _, e in ipairs({ "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	"PVP_MATCH_STATE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
	ns:On(e, FlushSoon)
end

local function StyleButtonBody(size, opts, button)
	button:SetSize(size, size)
	button.SUISize = size -- our own record: an aura button's GetWidth can be a secret value
	button:EnableMouse(not opts.disableMouse)
	if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0) end

	local icon = button:CreateTexture(nil, "BORDER")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.Icon = icon
	button:SetIcon(icon)

	ns.CreateBackdrop(button, 1)

	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	cd:SetReverse(true)
	cd:SetHideCountdownNumbers(opts.hideTimer or false)
	cd:SetCountdownFont(opts.assistCountdown and ns.AssistCountdownFont(size) or ns.GetCountdownFont(size * 0.42))
	button.Cooldown = cd
	button:SetDurationCooldown(cd)

	local textParent = CreateFrame("Frame", nil, button)
	textParent:SetAllPoints()
	textParent:SetFrameLevel(cd:GetFrameLevel() + 1)

	local count = ns.CreateText(textParent, math.max(8, math.floor(size * 0.42)), "RIGHT")
	count:SetPoint("BOTTOMRIGHT", -1, 1)
	button.Count = count
	button:SetApplicationCount(count, {})

	-- extras: a glow (opts.glow returns the current glow settings), a hook for when an icon
	-- appears (sound alerts), and any decoration the caller wants on every icon
	local owner = opts.owner
	if owner then
		owner.SUIButtons = owner.SUIButtons or {}
		table.insert(owner.SUIButtons, button)
	end
	if opts.glow then ns.ApplyGlow(button, opts.glow()) end
	if opts.decorate then opts.decorate(button, textParent) end

	if opts.dispelBorder then
		local border = textParent:CreateTexture(nil, "OVERLAY")
		border:SetAllPoints()
		button.DispelBorder = border
		button:AddDispelTypeTexture(border, {
			style = Enum.CustomAuraButtonDispelTypeTextureStyle.Border,
			showWhenHarmful = true,
			showWhenHelpful = false,
		})
	end

	-- Blue glow when the aura is Magic (dispellable). Blizzard's own code picks the texture per
	-- dispel type, so this works while the aura's details are hidden from addons: only "Magic"
	-- maps to the glow; every other type gets no texture.
	if opts.magicGlow and opts.magicGlow() then
		local holder = CreateFrame("Frame", nil, button)
		holder:SetAllPoints()
		holder:SetFrameLevel(button:GetFrameLevel() + 12)
		local tex = holder:CreateTexture(nil, "OVERLAY")
		local o = math.floor(size * 0.35 + 0.5)
		tex:SetPoint("TOPLEFT", button, "TOPLEFT", -o, o)
		tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", o, -o)
		tex:SetBlendMode("ADD")
		button:AddDispelTypeTexture(tex, {
			style = Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset,
			showWhenHarmful = true,
			showWhenHelpful = false,
			customDispelAssetMap = { Magic = { asset = ns.MEDIA.magicGlow } },
		})
		-- gentle pulse on our own holder frame (the texture's look stays Blizzard's)
		local ag = holder:CreateAnimationGroup()
		ag:SetLooping("BOUNCE")
		local a = ag:CreateAnimation("Alpha")
		a:SetFromAlpha(1)
		a:SetToAlpha(0.45)
		a:SetDuration(0.45)
		ag:Play()
		button.SUIMagicGlow = holder
	end

	-- last, and allowed to fail: aura buttons forbid addon scripts, so this hook is refused
	-- whenever the button is created under secret auras
	if opts.onShow then pcall(button.HookScript, button, "OnShow", opts.onShow) end
end

local function StyleButton(size, opts, button)
	ns.inAuraInit = true -- fonts set now are skipped by font retries while auras are secret
	local ok, err = pcall(StyleButtonBody, size, opts, button)
	ns.inAuraInit = false
	if not ok then geterrorhandler()(err) end
end

-- Creates one AuraContainer with one or more groups.
-- groups: list of { filter = string, max = n, decorate = its own decorate (optional) }
-- opts: { size, spacing, growthX ("RIGHT"|"LEFT"), growthY ("UP"|"DOWN"), anchor, maxWidth, dispelBorder, disableMouse,
--         magicGlow (function -> true to add the blue Magic glow; read once, at creation),
--         glow (function -> glow settings), onShow (icon appeared), decorate(button, textParent) }
function ns.CreateAuraContainer(parent, groups, opts)
	local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	local size = opts.size or 22
	opts.owner = opts.owner or container
	local spacing = opts.spacing or 2

	container:SetFlowLayoutAnchorPoint(opts.anchor or "BOTTOMLEFT")
	container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
	container:SetFlowLayoutMaximumLineSize(opts.maxWidth or (size + spacing) * 8)
	container:SetFlowLayoutGrowthDirection(opts.growthX == "LEFT" and -1 or 1, opts.growthY == "DOWN" and -1 or 1)
	container:SetFlowLayoutPadding(0, 0, 0, 0)

	container.SUIGroupKeys = {}
	for i, g in ipairs(groups) do
		local key = "SUIGroup" .. i
		local groupOpts = g.decorate and setmetatable({ decorate = g.decorate }, { __index = opts }) or opts
		container:AddAuraGroup(key, g.filter, {
			maxFrameCount = g.max or 4,
			sortMethod = AuraContainerSortMethod.ExpirationOnly,
			sortDirection = AuraContainerSortDirection.Normal,
			initializeFrame = GenerateClosure(StyleButton, g.size or size, groupOpts),
			layout = {
				elementSpacing = spacing,
				lineSpacing = spacing,
				groupSpacing = spacing,
				groupLineSpacing = spacing,
			},
		})
		container.SUIGroupKeys[i] = key
	end
	return container
end

function ns.SetAuraUnit(container, unit)
	if not container then return end
	if not unit then
		container:SetEnabled(false)
		return
	end
	container:SetEnabled(true)
	if container:GetUnit() ~= unit then
		container:SetUnit(unit)
	else
		container:UpdateAllAuras()
	end
end

function ns.SetAuraGroupMax(container, index, max)
	local key = container and container.SUIGroupKeys[index]
	if key then container:SetAuraGroupMaxFrameCount(key, max) end
end

-- Re-points an existing container's flow layout (aura rows above or below something).
function ns.SetAuraGrowth(container, anchor, growthX, growthY)
	if not container then return end
	container:SetFlowLayoutAnchorPoint(anchor)
	container:SetFlowLayoutGrowthDirection(growthX == "LEFT" and -1 or 1, growthY == "DOWN" and -1 or 1)
end

function ns.SetAuraGroupFilter(container, index, filter)
	local key = container and container.SUIGroupKeys[index]
	if key and container.SUIFilter ~= nil and container.SUIFilter[index] == filter then return end
	if key then
		container.SUIFilter = container.SUIFilter or {}
		container.SUIFilter[index] = filter
		container:SetAuraGroupFilterString(key, filter)
	end
end

-- candidateFilters is checked by Blizzard's own container code, which may read spell IDs
-- and flags that addon code can't. nil clears the filters.
function ns.SetAuraGroupCandidates(container, index, filters)
	local key = container and container.SUIGroupKeys[index]
	if not key then return end
	local ok, err = pcall(container.SetAuraGroupCandidateFilters, container, key, filters)
	if not ok then geterrorhandler()(err) end
end

-- list of spell IDs (numbers or "123 Name" strings) -> { [id] = true } or nil when empty
function ns.SpellSet(list)
	local set, any = {}, false
	for _, v in ipairs(list or {}) do
		local id = tonumber(v) or tonumber(tostring(v):match("^%s*(%d+)"))
		if id then set[id] = true; any = true end
	end
	return any and set or nil
end

function ns.SetAuraGroupEnabled(container, index, enabled)
	local key = container and container.SUIGroupKeys[index]
	if key then container:SetAuraGroupEnabled(key, enabled and true or false) end
end

-- Re-applies glow settings (and size) to every icon a container has made so far.
-- Deferred while auras are secret (see ns.AurasLocked); buttons already carry their creation style.
local function RestyleOne(b, glowCfg, size, assistCountdown)
	if size then b:SetSize(size, size); b.SUISize = size end
	local s = size or b.SUISize
	if b.Cooldown and s then
		b.Cooldown:SetCountdownFont(assistCountdown and ns.AssistCountdownFont(s) or ns.GetCountdownFont(s * 0.42))
	end
	if glowCfg then ns.ApplyGlow(b, glowCfg) end
end

function ns.RestyleAuraButtons(container, glowCfg, size, assistCountdown)
	if not container or not container.SUIButtons then return end
	ns.WhenAurasOpen(container, function()
		for _, b in ipairs(container.SUIButtons) do
			local ok, err = pcall(RestyleOne, b, glowCfg, size, assistCountdown)
			if not ok then geterrorhandler()(err); return end
		end
	end)
end
