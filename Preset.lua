-- StinkieUI: the default layout. These are Stinkie's own settings (sizes, positions, fonts,
-- glows), laid over the built-in defaults so a fresh install looks like the stream UI.
-- Only values that differ from the built-in defaults are listed. Loaded right after Core.lua,
-- before saved settings are read, so it only shapes what new profiles start with.
local _, ns = ...

local PRESET = {
	actionBars = {
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
			MicroMenuContainer = true,
			MultiBarBottomLeft = true,
			MultiBarBottomRight = true,
			MultiBarLeft = true,
			MultiBarRight = true,
			PetActionBar = true,
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
		precogGlowColor = { 1, 0.976, 0.973 },
		precogGlowThickness = 1,
		precogPoint = { "CENTER", 0, 0 },
		precogSize = 50,
		precogWhere = "always",
	},
	bgAllies = {
		carrierSide = "RIGHT",
		headerStyle = {
			size = 17,
		},
		healthStyle = {
			size = 14,
		},
		height = 35,
		nameStyle = {
			size = 14,
		},
		oorAlpha = 0.3,
		point = { "LEFT", 580, 30 },
		showHealthText = false,
		spacing = 2,
		stackSize = 30,
		width = 170,
	},
	bgEnemies = {
		headerStyle = {
			size = 17,
		},
		healthStyle = {
			outline = "NONE",
			size = 14,
		},
		height = 35,
		nameStyle = {
			size = 14,
		},
		oorAlpha = 0.3,
		point = { "RIGHT", -580, 30 },
		showHealthText = false,
		spacing = 2,
		specStyle = {
			size = 12,
		},
		stackSize = 30,
		width = 170,
	},
	bgWidgets = {
		capturePoint = { "TOP", 0, -120 },
		captureScale = 1.5,
		ghostPoint = { "TOP", 0, -190 },
		ghostScale = 1.2,
		scoreScale = 1.75,
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
		health = { 0.212, 0.212, 0.224 },
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
				entries = { "spell:1276452", "spell:119910", "spell:6789", "item:224464", "spell:5484", "slot:14" },
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
		ringColor = { 0.859, 0.69, 1 },
		ringCombatOnly = true,
		ringSize = 69,
	},
	damageMeter = {
		barBackgroundAlpha = 0.65,
		headerColor = { 0.039, 0.027, 0.071, 0.65 },
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
	minimap = {
		buttons = "hide",
		clockStyle = {
			outline = "NONE",
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
			outline = "NONE",
			size = 14,
		},
	},
	nameplates = {
		auraMode = "important",
		auraSize = 30,
		carrierSize = 80,
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
		healerSize = 40,
		height = 25,
		highlight = {
			arrowSize = 32,
			arrows = true,
			scale = 1.05,
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
		width = 180,
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
