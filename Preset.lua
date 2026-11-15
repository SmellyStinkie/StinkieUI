-- StinkieUI: the default layout. These are Stinkie's own settings (sizes, positions, fonts,
-- glows), laid over the built-in defaults so a fresh install looks like the stream UI.
-- Only values that differ from the built-in defaults are listed. Loaded right after Core.lua,
-- before saved settings are read, so it only shapes what new profiles start with.
local _, ns = ...

local PRESET = {
	actionBars = {
		cooldownScale = 1.2,
		countStyle = {
			size = 21,
		},
		hotkeyStyle = {
			size = 14,
		},
		macroStyle = {
			size = 14,
		},
		macroText = true,
		mouseover = {
			BagsBar = true,
			MainActionBar = true,
			MainStatusTrackingBarContainer = true,
			MicroMenuContainer = true,
			MultiBarBottomLeft = true,
			MultiBarBottomRight = true,
			MultiBarLeft = true,
			MultiBarRight = true,
			PetActionBar = true,
			SecondaryStatusTrackingBarContainer = true,
		},
	},
	arena = {
		castbar = {
			height = 20,
			textStyle = {
				size = 12,
			},
		},
		dotSize = 20,
		drCategories = {
			Disarm = false,
			Incapacitate = false,
			Root = false,
			Silence = false,
			Stun = false,
		},
		drOnlyMine = true,
		drSide = "LEFT",
		drSize = 40,
		healerAnchor = "BOTTOMLEFT",
		healerSize = 25,
		healthStyle = {
			outline = "NONE",
		},
		healthText = "none",
		height = 55,
		nameStyle = {
			size = 17,
		},
		point = { "RIGHT", -560, 160 },
		spacing = 20,
		trinketSize = 55,
		width = 200,
	},
	arenaAssist = {
		bigCCMax = 3,
		bigSize = 60,
		ccGlow = "static",
		healerGlowThickness = 4,
		healerIconSize = 95,
		healerPoint = { "CENTER", 0, 360 },
		healerText = "HEALER CC",
		healerWhere = "arena",
		kickGlow = "static",
		kickGlowThickness = 1,
		kickNames = false,
		kickPoint = { "CENTER", 0, -120 },
		kickSize = 40,
		precogGlow = "static",
		precogGlowColor = { 1, 0.976471, 0.972549 },
		precogPoint = { "CENTER", 0, 0 },
		precogSize = 55,
		precogWhere = "always",
	},
	bgAllies = {
		buffSide = "LEFT",
		buffSize = 35,
		buffsMine = true,
		carrierSide = "RIGHT",
		headerStyle = {
			size = 18,
		},
		healthStyle = {
			size = 14,
		},
		height = 35,
		nameStyle = {
			size = 14,
		},
		oorAlpha = 0.5,
		point = { "LEFT", 580, -80 },
		showHealthText = false,
		spacing = 2,
		specStyle = {
			size = 12,
		},
		stackSize = 30,
		width = 170,
	},
	bgEnemies = {
		headerStyle = {
			size = 18,
		},
		healthStyle = {
			outline = "NONE",
			size = 14,
		},
		height = 35,
		nameStyle = {
			size = 14,
		},
		oorAlpha = 0.5,
		point = { "RIGHT", -580, -80 },
		powerManaFallback = true,
		showHealthText = false,
		spacing = 2,
		specStyle = {
			size = 12,
		},
		stackSize = 30,
		width = 170,
	},
	bgTimers = {
		height = 26,
		point = { "TOP", 910, -740 },
		textStyle = {
			size = 15,
		},
		width = 270,
	},
	bgWidgets = {
		arenaScale = 1.3,
		arenaTextSize = 18,
		capturePoint = { "TOP", 0, -120 },
		captureScale = 1.5,
		ghostPoint = { "TOP", 0, -230 },
		ghostScale = 1.2,
		scoreScale = 1.75,
	},
	blitzMap = {
		enabled = true,
		iconSize = 28,
		nameStyle = {
			size = 13,
		},
		nodeSize = 20,
		point = { "TOPLEFT", 0, 0 },
		views = {
			[1366] = {
				u = 0.495076,
				v = 0.481364,
				zoom = 1.5625,
			},
			[206] = {
				u = 0.570833,
				v = 0.513636,
				zoom = 1.25,
			},
			[397] = {
				u = 0.514788,
				v = 0.508318,
				zoom = 1.953125,
			},
			[417] = {
				u = 0.480622,
				v = 0.539715,
				zoom = 1.5625,
			},
			[423] = {
				u = 0.507955,
				v = 0.540341,
				zoom = 1.25,
			},
		},
		width = 440,
	},
	bossFrames = {
		point = { "RIGHT", -490, 100 },
	},
	character = {
		background = "warband:146",
		dim = 0.55,
		extraHeight = 100,
		extraWidth = 100,
		gemSize = 13,
		nameChars = 20,
		outerDim = 0.55,
		ownedOnly = true,
		scale = 1.4,
	},
	chat = {
		bgAlpha = 0.6,
		clock24 = false,
		fontSize = 19,
		removeBrackets = true,
		shortWhispers = true,
		spacing = 0,
		tabAlpha = 0.85,
		tabInactiveAlpha = 0.75,
		tabStyle = {
			outline = "NONE",
			size = 13,
		},
		timestampColor = { 0.694118, 0.694118, 0.694118 },
	},
	classPower = {
		height = 25,
		point = { "BOTTOM", 0, 343 },
		separatorSize = 2,
		showText = false,
		textStyle = {
			size = 20,
		},
		width = 280,
	},
	colors = {
		background = { 0, 0, 0, 0.85 },
		health = { 0.211765, 0.211765, 0.223529 },
	},
	combat = {
		attachPoint = "TOPLEFT",
		size = 35,
		textDuration = 1.5,
		textPoint = { "CENTER", 0, 100 },
		textStyle = {
			size = 25,
		},
	},
	combatLog = {
		singleFile = true,
	},
	combatTextFont = true,
	cooldowns = {
		bars = {
			{
				countStyle = {
					classColor = false,
					color = { 1, 1, 1 },
					outline = "OUTLINE",
					size = 20,
				},
				enabled = true,
				entries = { "spell:1276452", "spell:119898", "spell:6789", "item:224464", "item:235895", "spell:5484", "slot:14" },
				perRow = 12,
				point = { "BOTTOM", 0, 275 },
				showCount = true,
				size = 40,
				spacing = 0,
			},
			{
				countStyle = {
					classColor = false,
					color = { 1, 1, 1 },
					outline = "OUTLINE",
					size = 20,
				},
				enabled = true,
				entries = { "spell:333889", "spell:353753", "spell:256948", "spell:212295", "spell:104773", "spell:48020" },
				perRow = 12,
				point = { "BOTTOM", 0, 234 },
				showCount = true,
				size = 40,
				spacing = 0,
			},
		},
		iconZoom = 0.1,
	},
	cursor = {
		ring = true,
		ringAlpha = 0.95,
		ringColor = { 0.858824, 0.690196, 1 },
		ringCombatOnly = false,
		ringSize = 69,
	},
	damageMeter = {
		barBackgroundAlpha = 0.65,
		headerColor = { 0.039216, 0.027451, 0.070588, 0.65 },
		nameStyle = {
			size = 14,
		},
		titleStyle = {
			size = 14,
		},
		valueStyle = {
			size = 14,
		},
		windowBorder = false,
	},
	damageText = {
		critScreenY = 0.045,
		critSize = 2,
		height = 9.75,
		screenY = 0.045,
	},
	errors = {
		fontSize = 14,
		keep = 60,
	},
	flagCap = {
		eta = false,
		height = 40,
		layout = "SIDE",
		notOnCapColor = { 1, 0, 0.2 },
		onCapColor = { 0, 1, 0.082353 },
		onlyYardsWhenNotOnCap = true,
		point = { "TOP", 0, -59 },
		spacing = 20,
		statusStyle = {
			size = 18,
		},
		textStyle = {
			size = 17,
		},
		width = 185,
	},
	minimap = {
		buttons = "hide",
		clockStyle = {
			size = 14,
		},
		coordStyle = {
			size = 12,
		},
		hideArena = true,
		hideHeaderArt = true,
		hideMPlus = true,
		hidePvP = true,
		hideRaid = true,
		mailCorner = "TOPLEFT",
		shape = "SQUARE",
		zoneStyle = {
			size = 14,
		},
	},
	misc = {
		apm = {
			count = "keys",
			point = { "BOTTOM", -650, 0 },
			textStyle = {
				size = 20,
			},
		},
		auto = {
			sellJunk = true,
		},
		decor = {
			enabled = true,
			maxGold = 10000,
		},
		gcd = {
			direction = "LEFT",
			point = { "BOTTOM", -380, 0 },
			spacing = 0,
		},
		questArrow = {
			enabled = true,
			height = 70,
			size = 30,
			textStyle = {
				size = 25,
			},
		},
	},
	nameplates = {
		auraMode = "important",
		auraSize = 30,
		carrierSize = 70,
		castHeight = 20,
		castStyle = {
			size = 17,
		},
		eliteSize = 16,
		friendlyHealerSize = 60,
		friendlyHeight = 9,
		friendlyLower = 20,
		friendlyMarkerSize = 40,
		friendlyNameInBar = true,
		friendlyNameMaxChars = 17,
		friendlyNameStyle = {
			classColor = false,
			size = 16,
		},
		friendlyWidth = 90,
		healerSize = 60,
		healthStyle = {
			size = 14,
		},
		height = 25,
		highlight = {
			arrowSize = 50,
			arrows = true,
			outset = 6,
			thickness = 4,
		},
		important = {
			auraSize = 80,
			clickPad = 40,
			heightScale = 2.5,
			widthScale = 2,
		},
		markerSize = 40,
		minionScale = 0.8,
		nameInBar = true,
		nameMaxChars = 20,
		nameStyle = {
			size = 18,
		},
		showLevel = false,
		softIconScale = 1.7,
		specAnchor = "ABOVE",
		specIconSize = 30,
		specIcons = true,
		specIconsFriendly = true,
		stacking = {
			spacing = 0.35,
			topInset = 0.13,
		},
		width = 210,
	},
	objectives = {
		headerSize = 15,
		lineSize = 14,
		questText = {
			enabled = true,
			point = { "TOP", 0, -320 },
		},
		zoneGroups = true,
	},
	party = {
		castbar = {
			enabled = true,
			height = 15,
			textStyle = {
				size = 12,
			},
		},
		dispelPosition = "HEALTH",
		dispelSize = 20,
		healerSize = 25,
		height = 55,
		leaderIcon = true,
		nameStyle = {
			size = 17,
		},
		point = { "LEFT", 560, 85 },
		power = "healer",
		showPlayer = true,
		spacing = 20,
		tankIcon = true,
		tankSize = 25,
		targetThickness = 3,
		trinketSize = 0,
		width = 200,
	},
	partyTargets = {
		enabled = true,
		healthText = "none",
		height = 16,
		hideInPvP = false,
		nameStyle = {
			size = 12,
		},
	},
	queueInfo = {
		bgAlpha = 0.75,
		eyeMove = true,
		eyePoint = { "BOTTOM", 450, 0 },
		eyeScale = 1.4,
		height = 24,
		labelStyle = {
			size = 17,
		},
		point = { "TOP", 0, -10 },
		scale = 1.55,
		textStyle = {
			size = 17,
		},
		width = 523,
	},
	raid = {
		aggro = false,
		buffSize = 12,
		buffs = false,
		debuffSize = 20,
		debuffs = "dispellable",
		defensiveSize = 25,
		dispelHighlight = false,
		groupSpacing = 7,
		height = 50,
		hideInBattlegrounds = true,
		keepGroups = false,
		leaderIcon = true,
		maxColumns = 6,
		nameStyle = {
			size = 12,
		},
		perColumn = 7,
		point = { "TOPLEFT", 350, -350 },
		privateAuras = false,
		privateSize = 32,
		rangeAlpha = 0.55,
		roleIcon = "tankHealer",
		roleSize = 15,
		sort = "ROLE",
		spacing = 1,
		targetThickness = 4,
		width = 90,
	},
	swingTimers = {
		hideIdle = true,
		rangedColor = { 0.239216, 0.513726, 0.713726 },
		textStyle = {
			size = 15,
		},
	},
	units = {
		focus = {
			auras = {
				showSmall = false,
			},
			castbar = {
				attached = true,
				height = 25,
				showTime = false,
				textStyle = {
					size = 13,
				},
			},
			healthText = "none",
			height = 40,
			nameStyle = {
				size = 16,
			},
			point = { "CENTER", 267, -119 },
			shields = false,
			showPower = false,
			width = 180,
		},
		pet = {
			healthText = "none",
			height = 35,
			nameStyle = {
				size = 14,
			},
			point = { "BOTTOMLEFT", 427, 309 },
			showName = true,
			width = 138,
		},
		player = {
			castbar = {
				height = 25,
				point = { "BOTTOM", 0, 317 },
				textStyle = {
					size = 15,
				},
				width = 280,
			},
			height = 46,
			nameStyle = {
				size = 17,
			},
			point = { "BOTTOM", -250, 229 },
			width = 210,
		},
		target = {
			castbar = {
				attached = true,
				height = 25,
				point = { "BOTTOM", 272, 214 },
				showTime = false,
				textStyle = {
					size = 14,
				},
			},
			height = 40,
			nameStyle = {
				size = 17,
			},
			point = { "BOTTOM", 250, 228 },
			width = 210,
		},
		targettarget = {
			healthText = "none",
			height = 25,
			nameStyle = {
				size = 13,
			},
			point = { "BOTTOMRIGHT", -592, 228 },
			shields = false,
			width = 114,
		},
	},
}

local function Merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" and #v == 0 and next(v) ~= nil then
			Merge(dst[k], v)
		else
			dst[k] = v
		end
	end
end

Merge(ns.defaults, PRESET)
