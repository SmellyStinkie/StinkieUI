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

local function StyleButton(size, opts, button)
	button:SetSize(size, size)
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
	if opts.onShow then button:HookScript("OnShow", opts.onShow) end
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
end

-- Creates one AuraContainer with one or more groups.
-- groups: list of { filter = string, max = n }
-- opts: { size, spacing, growthX ("RIGHT"|"LEFT"), growthY ("UP"|"DOWN"), anchor, maxWidth, dispelBorder, disableMouse,
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
		container:AddAuraGroup(key, g.filter, {
			maxFrameCount = g.max or 4,
			sortMethod = AuraContainerSortMethod.ExpirationOnly,
			sortDirection = AuraContainerSortDirection.Normal,
			initializeFrame = GenerateClosure(StyleButton, g.size or size, opts),
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
function ns.RestyleAuraButtons(container, glowCfg, size, assistCountdown)
	if not container or not container.SUIButtons then return end
	for _, b in ipairs(container.SUIButtons) do
		if size then b:SetSize(size, size) end
		local s = size or b:GetWidth()
		if b.Cooldown and s and s > 0 then
			b.Cooldown:SetCountdownFont(assistCountdown and ns.AssistCountdownFont(s) or ns.GetCountdownFont(s * 0.42))
		end
		if glowCfg then ns.ApplyGlow(b, glowCfg) end
	end
end
