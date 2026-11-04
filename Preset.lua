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
		point = { "RIGHT", -560, 105 },
		spacing = 10,
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
		capturePoint = { "TOP", 0, -120 },
		captureScale = 1.5,
		ghostPoint = { "TOP", 0, -190 },
		ghostScale = 1.2,
		scoreScale = 1.75,
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
		whisperTabs = true,
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
		mplus = true,
		singleFile = true,
	},
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
				entries = { "spell:1276452", "spell:119898", "spell:6789", "item:224464", "spell:5484", "slot:14" },
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
		ringAlpha = 0.85,
		ringColor = { 0.858824, 0.690196, 1 },
		ringCombatOnly = true,
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
	flagCap = {
		eta = false,
		height = 40,
		layout = "SIDE",
		notOnCapColor = { 1, 0, 0.2 },
		onCapColor = { 0, 1, 0.082353 },
		onlyYardsWhenNotOnCap = true,
		point = { "TOP", 0, -59 },
		spacing = 6,
		statusStyle = {
			size = 18,
		},
		textStyle = {
			size = 17,
		},
		width = 229,
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
		decor = {
			enabled = true,
		},
		gcd = {
			direction = "LEFT",
			enabled = true,
			point = { "BOTTOM", -380, 0 },
			spacing = 0,
		},
	},
	nameplates = {
		auraMode = "important",
		auraSize = 30,
		carrierSize = 70,
		castHeight = 15,
		eliteSize = 16,
		friendlyHeight = 5,
		friendlyLower = 20,
		friendlyNameInBar = true,
		friendlyNameStyle = {
			classColor = false,
			size = 17,
		},
		friendlyWidth = 90,
		healerSize = 60,
		height = 25,
		highlight = {
			arrowSize = 50,
			arrows = true,
			scale = 1.15,
			thickness = 3,
		},
		important = {
			clickPad = 18,
		},
		nameInBar = true,
		nameMaxChars = 10,
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
			enemies = true,
			friendly = true,
			spacing = 0.6,
			speed = 0.05,
			topInset = 0.17,
		},
		width = 210,
	},
	party = {
		castbar = {
			enabled = true,
		},
		dispelIcons = false,
		healerSize = 25,
		height = 55,
		nameStyle = {
			size = 17,
		},
		point = { "LEFT", 560, 84 },
		power = "healer",
		width = 200,
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
