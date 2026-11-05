-- StinkieUI: core, saved variables, fonts and text styles, events, movers, Blizzard frame hiding.
local addonName, ns = ...

ns.name = addonName
-- The version lives in one place: the TOC's "## Version:" line.
do
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local v = getMeta and getMeta(addonName, "Version")
	ns.version = (type(v) == "string" and v ~= "" and not v:find("^@")) and v or "dev"
end
ns.TEXTURE = [[Interface\Buttons\WHITE8X8]]
ns.MEDIA = {
	cross = [[Interface\AddOns\StinkieUI\Media\cross]],
	logo = [[Interface\AddOns\StinkieUI\Media\logo]],
	logoIcon = [[Interface\AddOns\StinkieUI\Media\logo_icon]], -- plus sign, same shape as the nameplate healer cross
	arrow = [[Interface\AddOns\StinkieUI\Media\arrow]], -- white arrowhead pointing up with a black outline (tinted)
	star = [[Interface\AddOns\StinkieUI\Media\star]],   -- white star with a black outline (tinted gold/silver)
	edge = [[Interface\AddOns\StinkieUI\Media\edge]],   -- square outline
	blank = [[Interface\AddOns\StinkieUI\Media\blank]],
	flag = [[Interface\AddOns\StinkieUI\Media\flag]], -- white flag, tinted per team
	roleHealer = [[Interface\AddOns\StinkieUI\Media\role_healer]], -- role icons (white, tinted)
	roleTank = [[Interface\AddOns\StinkieUI\Media\role_tank]],
	roleDamage = [[Interface\AddOns\StinkieUI\Media\role_damage]],
	damageFont = [[Interface\AddOns\StinkieUI\Media\StinkieRoleDamage.ttf]],
	orb = [[Interface\AddOns\StinkieUI\Media\orb]],   -- grey Kotmogu-style ball, tinted per orb
	magicGlow = [[Interface\AddOns\StinkieUI\Media\magic_glow]], -- blue glow ring for Magic (dispellable) debuffs
	-- role fonts: show a role icon from a (possibly secret) scoreboard role number, display-only.
	-- "4" (healer) draws a cross in the first, "1" (tank) draws a shield in the second; every
	-- other character is empty. See Media/README-fonts.txt.
	healerFont = [[Interface\AddOns\StinkieUI\Media\StinkieRoleHealer.ttf]],
	tankFont = [[Interface\AddOns\StinkieUI\Media\StinkieRoleTank.ttf]],
}
ns.TANK_COLOR = { 0.55, 0.75, 1.00 }
-- battleground role icons: healers are green on both teams
ns.ROLE_COLORS = { HEALER = { 0.15, 0.95, 0.25 }, TANK = { 0.55, 0.75, 1.00 }, DAMAGER = { 1.00, 0.40, 0.35 } }

-- Objective carriers (Enum.PvPUnitClassification) -> our own crisp icon + color, or a Blizzard atlas.
local HORDE_RED, ALLIANCE_BLUE = { 1.00, 0.18, 0.18 }, { 0.20, 0.55, 1.00 }
ns.CARRIER_STYLE = {
	FlagCarrierHorde = { tex = "flag", color = HORDE_RED },
	FlagCarrierAlliance = { tex = "flag", color = ALLIANCE_BLUE },
	FlagCarrierNeutral = { tex = "flag", color = { 1.00, 1.00, 1.00 } },
	OrbCarrierBlue = { tex = "orb", color = { 0.20, 0.60, 1.00 } },
	OrbCarrierGreen = { tex = "orb", color = { 0.20, 1.00, 0.30 } },
	OrbCarrierOrange = { tex = "orb", color = { 1.00, 0.60, 0.10 } },
	OrbCarrierPurple = { tex = "orb", color = { 0.75, 0.30, 1.00 } },
	CartRunnerHorde = { atlas = "nameplates-icon-cart-horde" },
	CartRunnerAlliance = { atlas = "nameplates-icon-cart-alliance" },
	AssassinHorde = { atlas = "nameplates-icon-bounty-horde" },
	AssassinAlliance = { atlas = "nameplates-icon-bounty-alliance" },
}
local carrierByValue
-- style for a readable classification value, or nil
function ns.CarrierStyle(value)
	if ns.issecret(value) or value == nil then return nil end
	if not carrierByValue then
		carrierByValue = {}
		local E = Enum and Enum.PvPUnitClassification
		if E then
			for key, style in pairs(ns.CARRIER_STYLE) do
				if E[key] ~= nil then carrierByValue[E[key]] = style end
			end
		end
	end
	return carrierByValue[value]
end

-- Puts a carrier style on a texture.
function ns.ApplyCarrierStyle(tex, style)
	if style.atlas then
		tex:SetAtlas(style.atlas)
		tex:SetVertexColor(1, 1, 1, 1)
	else
		tex:SetTexture(ns.MEDIA[style.tex], "CLAMP", "CLAMP", "TRILINEAR")
		tex:SetVertexColor(style.color[1], style.color[2], style.color[3], 1)
	end
end

-- Puts a role number (readable or secret) on a role-font string. Readable roles may also be
-- the strings "HEALER"/"TANK". Never compares or branches on a secret.
function ns.SetRoleText(fs, role)
	if ns.issecret(role) then
		fs:SetText(string.format("%d", role))
		return
	end
	if role == nil then fs:SetText("") return end
	if type(role) == "string" then
		fs:SetText(role == "HEALER" and "4" or role == "TANK" and "1" or role == "DAMAGER" and "2" or "")
		return
	end
	fs:SetText(string.format("%d", role))
end
-- WoW Forever (Classic+) runs the same 12.1.5 interface but has no arena
ns.IS_FOREVER = type(WOW_PROJECT_ID) == "number" and type(WOW_PROJECT_CAMELOT) == "number" and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
-- fallback if the project constants aren't there: Forever's interface number is 1xxxx (16001)
if not ns.IS_FOREVER and GetBuildInfo then
	local toc = select(4, GetBuildInfo())
	if type(toc) == "number" and toc >= 10000 and toc < 20000 then ns.IS_FOREVER = true end
end
ns.HAS_ARENA = not ns.IS_FOREVER
ns.HEALER_GREEN = { 0.15, 0.95, 0.25 }
ns.HEALER_RED = { 0.95, 0.15, 0.15 }
-- Brand colors, taken from the Stinkie logo (Media/logo.tga)
ns.BRAND = {
	bg = { 0.055, 0.050, 0.035 },      -- logo background (warm black)
	green = { 0.75, 0.80, 0.16 },      -- skull / fel flame
	plum = { 0.43, 0.20, 0.26 },       -- hood
	plumDark = { 0.17, 0.08, 0.11 },
	orange = { 0.93, 0.55, 0.12 },     -- trim
	cream = { 1.00, 0.98, 0.70 },      -- wordmark
}
ns.ACCENT = ns.BRAND.green
ns.ACCENT_HEX = "bfcc29"

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
ns.FONTS = {
	{ "PT Sans Narrow Bold", [[Interface\AddOns\StinkieUI\Media\PTSansNarrow-Bold.ttf]] },
	{ "Friz Quadrata", [[Fonts\FRIZQT__.TTF]] },
	{ "Arial Narrow", [[Fonts\ARIALN.TTF]] },
	{ "Morpheus", [[Fonts\MORPHEUS.ttf]] },
	{ "Skurri", [[Fonts\skurri.ttf]] },
	{ "2002", [[Fonts\2002.TTF]] },
	{ "2002 Bold", [[Fonts\2002B.TTF]] },
}
ns.DEFAULT_FONT = "PT Sans Narrow Bold"
ns.GAME_FONT = STANDARD_TEXT_FONT -- captured before anything can change it

local fontPathCache

function ns.GetFontPath()
	if not fontPathCache then
		local wanted = ns.db and ns.db.font or ns.DEFAULT_FONT
		for _, f in ipairs(ns.FONTS) do
			if f[1] == wanted then fontPathCache = f[2] end
		end
		fontPathCache = fontPathCache or ns.FONTS[1][2]
	end
	return fontPathCache
end

-- Every text Stinkie UI styles is remembered (weakly) with its size and flags, so it can be
-- set again later. At a cold login the font file can be refused for a few seconds, and text set
-- before the UI scale is applied renders at the wrong size; re-setting fixes both.
local fontRegistry = setmetatable({}, { __mode = "k" })
local fontFailed = setmetatable({}, { __mode = "k" })
local fontWarned = false

local function RetryFonts(final)
	local path = ns.GetFontPath()
	-- text inside aura buttons is locked while auras are secret: skip it then, and never let one
	-- refused object stop the rest
	local locked = ns.AurasLocked and ns.AurasLocked()
	for obj, args in pairs(fontRegistry) do
		if not (args[3] and locked) then pcall(ns.SetFont, obj, args[1], args[2]) end
	end
	if final and next(fontFailed) and not fontWarned then
		fontWarned = true
		ns:Print("Couldn't load font " .. path .. ". Using the game font. Type /stinkie fontcheck and send me the output.")
	end
end
ns.RetryFonts = RetryFonts
ns.ReapplyFonts = RetryFonts

-- outline setting -> font flags. Midnight takes "THICKOUTLINE" for the heavy outline.
local OUTLINE_FLAGS = { NONE = nil, OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE" }
function ns.OutlineFlags(outline)
	if outline == nil then return "OUTLINE" end
	return OUTLINE_FLAGS[outline]
end

-- Sets the chosen font on any font-bearing object. Falls back to the game font for that one
-- object only if the chosen file is refused, so a bad font can never blank or freeze the UI.
function ns.SetFont(obj, size, flags)
	local path = ns.GetFontPath()
	if flags == nil and not obj:IsObjectType("FontString") then flags = "" end -- EditBox/Font need a flags string
	local args = fontRegistry[obj]
	if args then args[1], args[2] = size, flags else fontRegistry[obj] = { size, flags, ns.inAuraInit or nil } end
	local ok = obj:SetFont(path, size, flags)
	if ok == false or obj:GetFont() == nil then
		obj:SetFont(ns.GAME_FONT, size, flags or "")
		fontFailed[obj] = true
		return false
	end
	fontFailed[obj] = nil
	return true
end

-- true if the client accepts this font file right now
function ns.FontLoads(path)
	ns.fontProbe = ns.fontProbe or UIParent:CreateFontString(nil, "BACKGROUND")
	return ns.fontProbe:SetFont(path, 12, "OUTLINE") ~= false
end

function ns.InvalidateFont()
	fontPathCache = nil
	fontWarned = false
	for size, name in pairs(ns.countdownFonts) do
		ns.SetFont(_G[name], size, "OUTLINE")
	end
end

-- Prints exactly what the client does with each font, for troubleshooting.
function ns:FontCheck()
	local fs = UIParent:CreateFontString(nil, "BACKGROUND")
	ns:Print("Selected font: " .. tostring(ns.db.font) .. " -> " .. ns.GetFontPath())
	for _, f in ipairs(ns.FONTS) do
		for _, flags in ipairs({ "OUTLINE", "" }) do
			local ok = fs:SetFont(f[2], 12, flags)
			local got = fs:GetFont()
			print(string.format("  %s [%s]: SetFont=%s GetFont=%s", f[1], flags == "" and "none" or flags, tostring(ok), tostring(got)))
		end
	end
	for _, flags in ipairs({ "OUTLINE", "THICKOUTLINE", "OUTLINE, THICK" }) do
		local ok = fs:SetFont(ns.GetFontPath(), 12, flags)
		local _, _, got = fs:GetFont()
		print(string.format("  flags %q: SetFont=%s, client reports %q", flags, tostring(ok), tostring(got)))
	end
	local _, build, _, toc = GetBuildInfo()
	print("  client " .. tostring(build) .. " / " .. tostring(toc))
end

-- Font objects for cooldown countdown numbers (Cooldown:SetCountdownFont takes a font object name).
ns.countdownFonts = {}
function ns.GetCountdownFont(size)
	size = math.max(8, math.floor(size + 0.5))
	local name = ns.countdownFonts[size]
	if not name then
		name = "StinkieUI_CountdownFont" .. size
		local font = CreateFont(name)
		ns.SetFont(font, size, "OUTLINE")
		ns.countdownFonts[size] = name
	end
	return name
end

-- Text style: { size, outline = "NONE"|"OUTLINE"|"THICKOUTLINE", color = {r,g,b}, classColor }
function ns.ApplyText(fs, style, r, g, b)
	local flags = ns.OutlineFlags(style.outline or "OUTLINE")
	ns.SetFont(fs, style.size or 12, flags)
	if not flags then
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 1)
	else
		fs:SetShadowOffset(0, 0)
	end
	if r then
		fs:SetTextColor(r, g, b)
	else
		local c = style.color or { 1, 1, 1 }
		fs:SetTextColor(c[1], c[2], c[3])
	end
end

---------------------------------------------------------------------------
-- Defaults. Points are { anchorPoint, x, y } relative to the same point on UIParent.
---------------------------------------------------------------------------
local function text(size, classColor)
	return { size = size, outline = "OUTLINE", color = { 1, 1, 1 }, classColor = classColor or false }
end
ns.TextDefaults = text

local function castbar(enabled, width, height, point, textSize)
	return {
		enabled = enabled,
		attached = false, -- true: sits under the unit frame and matches its width
		width = width,
		height = height,
		showText = true,
		showTime = true,
		textStyle = text(textSize or 11),
		point = point,
	}
end

local function unit(t)
	t.enabled = true
	t.showName = t.showName ~= false
	t.nameFormat = "full" -- full | first | last
	t.showLevel = false
	t.nameAbove = false
	t.healthText = "percent"
	t.shields = true -- absorb shield and overshield on the health bar
	t.nameStyle = text(t.textSize or 12)
	t.healthStyle = text(t.textSize or 12)
	t.textSize = nil
	return t
end

ns.DB_VERSION = 13
ns.defaults = {
	version = ns.DB_VERSION,
	scale = 1,
	font = ns.DEFAULT_FONT,
	globalFont = true,      -- also apply the font to Blizzard's UI (tooltips, buffs, meters, settings, ...)
	combatTextFont = false, -- floating combat text (needs relog)
	worldNameFont = true,   -- names and guild names above characters, yours included (needs relog)
	classColorHealth = true,
	colors = {
		background = { 0.06, 0.06, 0.07, 0.85 },
		health = { 0.30, 0.30, 0.32 },      -- used when class colors are off
		castInterruptible = { 1.00, 0.70, 0.10 },
		castNotInterruptible = { 0.55, 0.55, 0.60 },
		castFailed = { 0.85, 0.20, 0.20 },
		healthBackground = { 0.17, 0.17, 0.18, 1 }, -- empty part of health bars
		absorb = { 1.00, 0.82, 0.25, 0.55 },     -- shield, drawn after current health
		overAbsorb = { 1.00, 0.88, 0.40, 0.85 }, -- shield larger than missing health, drawn backwards over the top half
	},
	units = {
		player = unit({
			width = 150, height = 24, showPower = false, powerHeight = 6,
			point = { "BOTTOM", -230, 240 },
			castbar = castbar(true, 220, 18, { "BOTTOM", 0, 190 }, 12),
		}),
		target = unit({
			width = 150, height = 24, showPower = true, powerHeight = 6,
			point = { "BOTTOM", 230, 240 },
			eliteIcon = true, eliteSize = 16, eliteCorner = "TOPLEFT", -- gold star: elite / boss, silver: rare
			auras = { enabled = true, size = 24, max = 8, position = "BELOW", showSmall = true, ccIcon = true, ccIconSize = 0, ccIconSide = "RIGHT" },
			castbar = castbar(true, 180, 16, { "BOTTOM", 230, 300 }),
		}),
		targettarget = unit({
			width = 80, height = 16, showPower = false, powerHeight = 4, textSize = 10,
			point = { "BOTTOM", -400, 290 },
		}),
		focus = unit({
			width = 120, height = 18, showPower = true, powerHeight = 4, textSize = 11,
			point = { "BOTTOM", 230, 400 },
			eliteIcon = true, eliteSize = 14, eliteCorner = "TOPLEFT",
			auras = { enabled = true, size = 20, max = 6, position = "BELOW", showSmall = true, ccIcon = true, ccIconSize = 0, ccIconSide = "RIGHT" },
			castbar = castbar(true, 160, 14, { "BOTTOM", 230, 365 }),
		}),
		pet = unit({
			width = 80, height = 12, showPower = false, powerHeight = 3, textSize = 9,
			showName = false,
			point = { "BOTTOM", -265, 212 },
		}),
	},
	party = {
		enabled = true, width = 130, height = 34,
		power = "all", -- all | healer | none
		powerHeight = 5,
		spacing = 10,
		growth = "DOWN", -- DOWN | UP
		showPlayer = false,
		trinketSide = "LEFT", -- trinket + defensives side; crowd control sits on the other side
		ccIcon = true, defensiveIcon = true, dispelIcons = true,
		ccSize = 0, -- 0 = frame height
		ccMax = 2,
		dispelPosition = "BELOW", -- BELOW (row under the frame) | SIDE (after the CC icons)
		healthText = "percent",
		nameFormat = "full", showLevel = false,
		marker = false, markerSize = 16, -- raid target marker on the frame's top edge
		rangeFade = true,
		healerIcon = true, healerSize = 12,
		nameStyle = text(12),
		healthStyle = text(12),
		castbar = { enabled = false, height = 10, textStyle = text(10) },
		trinket = true, trinketSize = 26,
		hideInBattlegrounds = true,
		hideInRaid = true, -- hidden while you're in a raid group
		point = { "LEFT", 330, 120 },
	},
	minimap = {
		enabled = true,
		shape = "ROUND", -- ROUND | SQUARE
		border = true, borderColor = { 0, 0, 0 }, borderSize = 1,
		hideHeaderArt = false,
		buttons = "show", -- show | mouseover | hide (tracking, addon list, expansion button, zoom, addon buttons)
		calendar = true, calendarScale = 1,
		zoneText = true, zoneStyle = text(13),
		clock = true, clockStyle = text(12),
		-- coords = nil leaves Blizzard's "show coordinates" setting as it is
		coordStyle = text(11), coordPosition = "BOTTOM", coordX = 0, coordY = 0,
		hideArena = false, hidePvP = false, hideMPlus = false, hideRaid = false,
		headerGap = 2, -- square: space between the zone bar and the map
		mailCorner = "TOPRIGHT", -- square: TOPLEFT / TOPRIGHT / BOTTOMLEFT / BOTTOMRIGHT / DEFAULT
		folio = true, folioCorner = "BOTTOMLEFT", folioScale = 0.7, folioInset = 14, folioX = 0, folioY = 0, -- Omnium Folio (expansion button)
	},
	arenaAssist = {
		countdownScale = 1.3, -- timer numbers on PvP Assist and party CC / trinket icons
		-- party frame extras
		ccGlow = "pulse", ccGlowColor = { 1.00, 0.25, 0.25 }, ccGlowThickness = 2,
		magicGlow = true, -- party CC and healer-in-CC icons glow blue when the CC is Magic (Singe Magic can remove it)
		trinketGlow = "none", trinketGlowColor = { 0.75, 0.80, 0.16 }, trinketGlowThickness = 2,
		-- "Healer in CC" warning
		healerCC = true,
		healerWhere = "pvp", -- arena | pvp (arena + battlegrounds) | always
		healerText = "Healer in CC!",
		healerTextStyle = { size = 40, outline = "THICKOUTLINE", color = { 1.00, 0.20, 0.20 } },
		healerIcons = true, healerIconSize = 44,
		healerGlow = "pulse", healerGlowColor = { 1.00, 0.20, 0.20 }, healerGlowThickness = 2,
		healerSound = false,
		healerPoint = { "CENTER", 0, 230 },
		-- Precognition (and any other buffs listed) on you
		precog = true,
		precogSpells = { "377362 Precognition" },
		precogSize = 44,
		precogGlow = "pulse", precogGlowColor = { 0.75, 0.80, 0.16 }, precogGlowThickness = 2,
		precogWhere = "pvp",
		precogPoint = { "CENTER", 0, -110 },
		-- enemy interrupts
		kicks = true,
		kickSize = 36, kickMax = 3,
		kickNames = true, kickNameStyle = text(10),
		kickGrowth = "RIGHT",
		kickGlow = "none", kickGlowColor = { 1.00, 0.55, 0.12 }, kickGlowThickness = 2,
		kickPoint = { "CENTER", 0, -170 },
		-- Big Debuffs: crowd control, defensives and offensive cooldowns, big, right of enemy nameplates
		bigAuras = true,
		bigWhere = "always", -- arena | pvp | always
		bigCC = true, bigCCMax = 2,
		bigDef = true, bigDefMax = 1,
		bigOff = true, bigOffMax = 1,
		bigSize = 36, bigX = 4, bigY = 0,
		bigCCSide = "RIGHT", bigBuffSide = "LEFT", -- which side of the nameplate each row sits on
		bigHideSmall = true, -- don't repeat CC / defensives in the small row above the plate
		bigGlow = "pulse", bigGlowColor = { 1.00, 0.25, 0.25 }, bigGlowThickness = 2,
	},
	nameplates = {
		enabled = true,
		width = 130, height = 12, castHeight = 10,
		showLevel = true, showHealthText = false,
		nameInBar = false,
		minionScale = 1, -- width of pet / guardian / totem plates relative to normal
		auraSize = 22, maxAuras = 6,
		auraMode = "all", -- all | important | whitelist
		auraOnlyMine = true,
		auraWhitelist = {},
		auraBlacklist = {},
		showCC = true, showDefensives = true,
		highlight = { thickness = 1, outset = 0, color = { 1, 1, 1 }, arrows = false, arrowSize = 16 },
		unitTypes = { pets = true, guardians = false, totems = true, minor = false }, -- applied to Blizzard's settings
		important = {
			enabled = true,
			color = { 1.00, 0.40, 0.80 },
			clickPad = 14,
			widthScale = 1.5, heightScale = 1.5, border = true, -- size vs a normal enemy plate
			-- where the game hides names and NPC IDs (rated PvP): a big glowing icon for units that
			-- carry one of these auras on themselves. 8178 = Grounding Totem Effect
			auraMarker = true, auraSize = 34, auraIDs = { "8178" },
			units = {
				"Grounding Totem", "Tremor Totem", "Spirit Link Totem", "Capacitor Totem",
				"Healing Tide Totem", "Earthgrab Totem", "Static Field Totem", "Counterstrike Totem",
				"Skyfury Totem", "Poison Cleansing Totem", "Windfury Totem", "Earthen Wall Totem",
				"Ancestral Protection Totem", "Psyfiend", "War Banner",
				"5925", "5913", "53006", "61245", "59764", "60561", "179867", "105451", "101398",
			},
		},
		clickPadX = 10, clickPadY = 6,
		friendlyWidth = 60, friendlyHeight = 3,
		friendlyClickThrough = true,
		friendlyTargetFull = true, -- your friendly target gets the full-size plate and target border
		-- how plates push each other apart. enemies / friendly are seeded from the game's setting.
		-- boxHeight 0 = auto (bar + castbar + 24). spacing / speed / topInset 0 = game default.
		stacking = { enemies = false, friendly = false, boxHeight = 0, spacing = 0, speed = 0, topInset = 0 }, -- plates don't push each other apart
		healerIcon = true,
		enemyHealerIcon = true,
		healerSize = 20,
		inspectHealers = true, -- inspect nearby players outside groups to find healers
		friendlyNameInBar = false,
		eliteIcon = true, eliteSize = 14,
		carrierIcon = true, carrierSize = 40, -- flag / orb carrier icon (battlegrounds)
		carrierAnchor = "ABOVE", carrierX = 0, carrierY = 0, -- ABOVE (just over the name) | LEFT (left of the bar) | TOP (above the icon slot)
		specIcons = false, specIconsFriendly = false, specIconSize = 20,
		specAnchor = "LEFT", -- LEFT / RIGHT of the cross, CENTER (cross to its right) or ABOVE (centered, cross on top)
		nameMaxChars = 0, nameEllipsis = true, -- 0 = full names
		nameFormat = "full", -- full | first | last
		marker = true, markerSize = 28, -- raid target marker above the plate
		specX = 0, specY = 0,
		softIconScale = 1.5, softIconY = 4, -- Blizzard's soft-target (quest / interact) icon
		friendlyLower = 0, -- push friendly plates down to make room above them
		nameStyle = text(11),
		healthStyle = text(9),
		castStyle = text(9),
		friendlyNameStyle = text(10, true),
	},
	classPower = {
		enabled = true,
		attached = false, -- true: sits above the player frame and matches its width
		width = 180, height = 12,
		separators = true,
		separatorSize = 1, -- 1 thin, 2 thick, 3 extra thick (physical pixels)
		showText = true,
		useCustomColor = false,
		color = { 0.64, 0.36, 0.98 },
		textStyle = text(12),
		point = { "BOTTOM", 0, 270 },
	},
	arena = {
		enabled = true,
		width = 170, height = 32,
		spacing = 22,
		growth = "DOWN",
		power = "healer", -- all | healer | none
		powerHeight = 5,
		healthText = "percent",
		nameFormat = "full", showLevel = false,
		nameStyle = text(12),
		healthStyle = text(12),
		castbar = { enabled = true, height = 12, textStyle = text(10) },
		specIcon = true,
		healerIcon = true,
		trinket = true, trinketSize = 34,
		dr = true, drSize = 26, drSide = "RIGHT", drOnlyMine = false,
		drCategories = { Stun = true, Incapacitate = true, Disorient = true, Silence = true, Root = true, Disarm = true, Taunt = false, AoEKnockback = false },
		deadText = true, deadSize = 0.6, -- big DEAD / FEIGN across the frame (size = share of frame height)
		targetBorder = 3, targetColor = { 1, 1, 1, 1 }, -- border around the frame you have targeted (pixels)
		targetDots = true, dotSize = 7,
		dotColor = { 0.20, 1.00, 0.20 }, dotClassColor = false, -- bright green squares by default
		healerSize = 14, healerAnchor = "BOTTOMRIGHT", -- TOPLEFT | TOPRIGHT | BOTTOMLEFT | BOTTOMRIGHT
		rightClick = "focus", -- focus | target | menu | none
		point = { "RIGHT", -260, 120 },
	},
	bgEnemies = {
		enabled = true,
		width = 150, height = 20, spacing = 3,
		columns = 1, maxRows = 15,
		power = "healers", -- none | healers | all: mana strip along the bottom of the row
		powerHeight = 3,
		powerManaFallback = false, -- role hidden: treat mana users as healers
		specIcon = true,
		showHealthText = true, shortNames = true,
		oorAlpha = 0.4,
		iconMode = "role", -- role | spec (the icon left of each row)
		specText = true, specStyle = text(9),
		carrier = true, carrierSide = "LEFT",
		stacks = true, stackSize = 20, -- flag / orb debuff with its stack count
		header = true,
		rightClick = "focus", -- focus | target | none
		targetHighlight = true, targetThickness = 2, targetColor = { 1, 1, 1 },
		nameStyle = text(11),
		healthStyle = text(10),
		headerStyle = text(13),
		point = { "LEFT", 30, 60 },
	},
	bgAllies = {
		enabled = true,
		width = 150, height = 20, spacing = 3,
		columns = 1, maxRows = 15,
		power = "healers", -- none | healers | all: mana strip along the bottom of the row
		powerHeight = 3,
		powerManaFallback = false, -- role hidden: treat mana users as healers
		specIcon = true,
		showHealthText = true, shortNames = true,
		oorAlpha = 0.4,
		iconMode = "role", -- role | spec (the icon left of each row)
		specText = true, specStyle = text(9),
		carrier = true, carrierSide = "LEFT",
		stacks = true, stackSize = 20,
		buffs = false, buffsMine = false, -- buffs beside each ally; only the ones you cast
		buffMax = 4, buffSize = 18, buffSide = "RIGHT",
		header = true,
		targetHighlight = true, targetThickness = 2, targetColor = { 1, 1, 1 },
		rightClick = "focus",
		nameStyle = text(11),
		healthStyle = text(10),
		headerStyle = text(13),
		point = { "LEFT", 30, 340 },
	},
	combat = {
		enabled = true,
		icon = true,
		size = 22,
		attached = true, -- on the player frame
		attachPoint = "TOPRIGHT", attachX = 0, attachY = 0,
		point = { "BOTTOM", -150, 275 },
		text = true,
		textStyle = text(22),
		textDuration = 1.2,
		enterColor = { 1.00, 0.25, 0.25 },
		leaveColor = { 0.35, 1.00, 0.45 },
		textPoint = { "CENTER", 0, 160 },
	},
	-- flat look for Blizzard's swing timers, on clients that have them
	swingTimers = {
		enabled = true,
		mainColor = { 0.75, 0.80, 0.16 },
		offColor = { 0.55, 0.36, 0.70 },
		rangedColor = { 0.30, 0.65, 0.90 },
		showLabel = true, showTime = true,
		hideIdle = false, -- hidden unless you're auto attacking or a swing is under way
		textStyle = text(11),
	},
	actionBars = {
		enabled = true,
		hideArt = true,
		macroText = false,
		hotkeys = true,
		hotkeysHover = false, -- keybinds off: they still show on the bar under the mouse
		hotkeyStyle = text(11),
		countStyle = text(12),
		macroStyle = text(10),
		mouseover = {}, -- bar name -> true: hidden until the mouse is over it
		fadeAlpha = 0,
		cooldownNumbers = true, -- countdown numbers on the buttons (overrides the game's own setting)
		cooldownScale = 1,      -- size of those numbers relative to the button
	},
	chat = {
		enabled = true,
		-- window
		bgColor = { 0.04, 0.04, 0.05 }, bgAlpha = 0.45, border = true,
		tabColor = { 0.10, 0.09, 0.08 }, tabAlpha = 0.7, tabInactiveAlpha = 0.55,
		tabStyle = text(12),
		mouseover = false, fadeAlpha = 0, showOnMessage = false, showOnMessageTime = 5,
		buttons = "show", -- side buttons: show | hide
		copyButton = true, dragCopy = false,
		-- text
		fontSize = 0, -- 0: each window keeps its size from Blizzard's chat settings
		outline = "NONE", spacing = 1, indent = true,
		timestamps = "hm", -- none | hm | hms
		clock24 = true,
		timestampMode = "inline", -- inline | column
		timestampColor = { 0.55, 0.55, 0.55 },
		columnGap = 8,
		-- history
		history = "session", -- session (this and the previous login) | reload (reloads only) | off
		historyLines = 300, maxLines = 500, restoreDivider = true,
		-- formatting
		classColors = true, showLevel = false, levelHideMax = true,
		channelStyle = "short", -- full | short | name
		removeBrackets = false, hideRealms = false, shortWhispers = false,
		whisperTabs = false, flashTabs = true, flashPlayerOnly = true,
		colors = {}, -- chat type -> { r, g, b }, only the ones changed here
	},
	misc = {
		gcd = {
			enabled = false,
			size = 34, count = 6, spacing = 4,
			direction = "RIGHT", -- the way older icons move: RIGHT | LEFT | UP | DOWN
			duration = 10, -- seconds an icon stays
			where = "always", -- always | combat | pvp
			showInterrupted = true,
			ignore = { 6603, 75 }, -- Auto Attack, Auto Shot
			point = { "BOTTOM", 0, 330 },
		},
		decor = {
			enabled = false,
			maxGold = 0, -- 0: no limit
			announce = true,
		},
		-- a small nameplate in the world on the quest you're actively tracking
		questArrow = {
			enabled = false,
			size = 24, color = { 0.75, 0.80, 0.16 },
			height = 60, -- raised off the spot, so it clears the target's own nameplate
			edgeMargin = 60, -- how far the off-screen arrow stays from the edge of the screen
			showName = true,
			textStyle = text(13),
		},
		-- errands done for you; each one is off until it's asked for
		auto = {
			questAccept = false, questTurnIn = false,
			repair = false, repairGuild = false,
			sellJunk = false,
			releasePvP = false,
			hideErrors = false, -- red messages like "Not enough mana"
			announce = true,
		},
	},
	cursor = {
		-- size: cursorSizePreferred (-1 default, 0..4 = 32/48/64/96/128); read from the game on first load
		ring = false,
		ringSize = 48,
		ringThickness = "thin", -- thin | thick
		ringColor = { 0.61, 0.36, 1.00 },
		ringAlpha = 0.8,
		ringCombatOnly = true, -- only in combat (it follows the mouse every frame while shown)
	},
	bgWidgets = {
		enabled = true,
		moveScore = true, scorePoint = { "TOP", 0, -15 }, scoreScale = 1,
		moveCapture = true, capturePoint = { "TOP", 0, -70 }, captureScale = 1,
		moveGhost = true, ghostPoint = { "TOP", 0, -130 }, ghostScale = 1, -- "Return to Graveyard" button
		-- arenas and Solo Shuffle: Blizzard's top-center info (round 3 of 6, match timer)
		moveArena = true, arenaPoint = { "TOP", 0, -15 }, arenaScale = 1.15, arenaText = true, arenaTextSize = 16,
		texture = "flat", -- blizzard | flat | any LibSharedMedia statusbar
		hideRaidFrames = true, -- Blizzard raid frames off in Blitz / battlegrounds up to 15 players
		leftColor = { 0.25, 0.55, 1.00 },  -- Alliance side of the score bar
		rightColor = { 0.95, 0.25, 0.25 }, -- Horde side
	},
	damageMeter = {
		enabled = true,
		texture = "flat", -- flat | any LibSharedMedia statusbar
		barBackgroundAlpha = 0.35,
		barBorder = true,
		windowBorder = true,
		hideScrollBar = false,
		headerColor = { 0.06, 0.06, 0.07, 0.95 },
		backgroundColor = { 0.06, 0.06, 0.07 },
		nameStyle = text(12),
		valueStyle = text(12),
		titleStyle = text(12),
	},
	combatLog = {
		enabled = true,
		arena = true, shuffle = true, blitz = true, battleground = false,
		mplus = false, dungeon = false, raid = false,
		advanced = true,
		singleFile = false, -- once started, keep logging until logout (one file for the session)
		quiet = false,
		startedByUs = false,
	},
	-- party members' targets: a small frame beside each party frame. Blank in arenas and
	-- battlegrounds (Blizzard refuses compound unit tokens there), so hidden there by default.
	partyTargets = {
		enabled = false,
		width = 90, height = 18, showPower = false, powerHeight = 3,
		showName = true, nameAbove = false, healthText = "percent", shields = false,
		nameFormat = "full", showLevel = false,
		nameStyle = text(10, true), healthStyle = text(10),
		hideInPvP = true,
		attachAbove = false, attachGap = 3, -- each row on top of its own party frame
		point = { "LEFT", 560, 120 },
	},
	-- Flag Cap Indicator (Warsong Gulch, Twin Peaks): who carries each flag, yards to their cap
	-- spot, ON CAP / NOT ON CAP / DROPPED. Sits under the battleground score by default.
	flagCap = {
		enabled = true,
		attach = true, attachX = 0, attachY = -4, -- under the score display
		point = { "TOP", 0, -80 },               -- when not attached
		scale = 1,
		width = 240, height = 22, spacing = 2,
		layout = "STACK", -- STACK (one under the other) | SIDE (side by side)
		swapSides = false, -- side by side: each flag under the carrying team's score (Alliance left; true = Horde left)
		names = true, classColors = true, realms = false,
		distance = true, onlyYardsWhenNotOnCap = false, eta = true,
		radius = 8, -- yards from the cap spot that count as on cap
		textStyle = text(13),
		statusStyle = { size = 13, outline = "THICKOUTLINE", color = { 1, 1, 1 }, classColor = false },
		bgAlpha = 0.75,
		onCapColor = { 0.95, 0.20, 0.15 },
		notOnCapColor = { 0.25, 0.25, 0.28 },
		droppedColor = { 0.95, 0.75, 0.15 },
		flashOnCap = true,
	},
	-- BG Timers: base captures, predicted winner, resurrection wave
	bgTimers = {
		enabled = true,
		nodes = true, win = true, respawn = true,
		width = 200, height = 18, spacing = 3,
		growth = "DOWN",
		textStyle = text(12),
		allianceColor = { 0.25, 0.55, 1.00 }, hordeColor = { 0.95, 0.25, 0.25 }, neutralColor = { 0.75, 0.70, 0.55 },
		bgAlpha = 0.7,
		-- seconds an assaulted base takes to turn, per map name. Maps not listed get no base timers.
		durations = { "Arathi Basin = 60", "Battle for Gilneas = 60", "Deepwind Gorge = 60" },
		point = { "TOP", 330, -20 },
	},
	-- Match History: every rated and unrated PvP match is saved at the end. The browser and
	-- stats (/mh) live in the StinkieUI_History addon, which only loads when you open it.
	matchHistory = {
		enabled = true,
		arena = true, shuffle = true, blitz = true, rbg = true,
		skirmish = false, battleground = false, brawl = false, unrated = false, -- unrated games aren't saved by default
		talents = true, -- save your talent loadout string with each match
		announce = true, -- one chat line after each match ("Saved: 3v3 Nagrand Arena, win, +14")
		loadMonths = 12, -- the window loads this many months back (0 = everything); "Load all" for more
	},
	-- Character Sheet: additions to Blizzard's character and inspect frames
	character = {
		enabled = true,
		inspect = true, -- same look when inspecting others
		background = "dark", -- blizzard | dark | custom | warband:<id>
		customTexture = "", ownedOnly = false,
		dim = 0.25, -- darkening over the background in the character area
		durability = true, durabilityWidth = 2, -- thin line beside each item: green (repaired) -> yellow -> red
		collapsed = false, collapseButton = true, -- arrow under the trinkets hides / shows the stats side
		centerHeader = true, -- name and level centered over the character
		wideBackground = true, outerDim = 0.6, -- background across the whole window, darker outside the character
		line1 = "name", -- name | track ("Mythic 6/6") | none
		track = true, ilvl = true, pvp = true, gems = true, gemSize = 14,
		enchants = true, enchantNames = true, missing = true,
		-- compact (less busy): set prefix dropped from names ("Gladiator's Amulet" -> "Amulet"),
		-- names capped at nameChars, short track ("C1/6"), "P344" for PvP item level, enchants as a
		-- check / red cross icon instead of their own line, weapon text under the weapons
		compact = true, nameChars = 16, enchantIcons = true, hideShirt = true,
		statHighlight = true, highlightColor = { 0.75, 0.80, 0.16 },
		hideZeroStats = false, -- false: every secondary / tertiary stat shows, even at 0
		moveSpeed = true,      -- movement speed row in the stat list
		ilvlDecimals = true,
		textWidth = 140, -- with the roomier layout the model area is ~320 px wide
		flat = true, frameColor = { 0.05, 0.05, 0.06 }, frameAlpha = 0.9, tabAlpha = 0.9,
		roomy = true, extraWidth = 90, extraHeight = 70, weaponGap = 40, -- more room around the character
		scale = 1.2, inspectScale = 1.2, resizer = true,
		nameStyle = text(11),
		infoStyle = text(10),
	},
	-- Objectives (quest / objective tracker)
	objectives = {
		enabled = true,
		lineSize = 12, headerSize = 14, outline = "OUTLINE",
		scale = 1,
		background = true, bgColor = { 0.04, 0.04, 0.05 }, bgAlpha = 0, border = false, padding = 4,
		hideBlizzardBg = true,
		flat = true, -- flat headers, progress bars and quest item buttons (no gradients)
		hideArena = true, hideBG = true, hideRaid = true, hideMPlus = false, hideDungeon = false,
	},
	-- Damage Numbers: floating combat text over targets (0 = the game's default for each)
	damageText = { healing = true, enabled = true, size = 0, height = 0, screenY = 0, critScreenY = 0, critSize = 0, spread = 0, gravity = 0, directional = 0 },
	-- Window Skins: the Character Sheet's flat look on other Blizzard windows (safe set only)
	skins = {
		enabled = true,
		alpha = 0.9, -- window background opacity (color = the Character Sheet's)
		friends = true, groupFinder = true, adventure = true, collections = true, achievements = true,
		guild = true, professions = true, housing = true, gameMenu = true,
	},
	-- Tooltip: size, position, combat hiding, health bar, target line, guild ranks
	tooltip = {
		enabled = true,
		scale = 1,
		anchor = "mouse", -- mouse | fixed | blizzard
		offsetX = 128, offsetY = 25, -- from the mouse
		point = { "BOTTOMRIGHT", -40, 120 }, fixedPoint = "BOTTOMRIGHT", -- the fixed spot (drag it when unlocked)
		combat = "show", -- show | units (hide unit tooltips in combat) | all
		combatShift = true, -- hold Shift to see them anyway
		healthBar = true,
		target = true, -- "Target: <name>" (class colored), YOU in red
		rankOwn = true, rankOther = true, -- guild rank after the guild name
		classNames = true, -- player names in class color
		ids = false, -- spell and item IDs
	},
	-- Buff frame: Blizzard's buff / debuff icons, flat look and auto hide (layout stays in Edit Mode)
	buffs = {
		enabled = true,
		skin = true, zoom = true, border = true,
		durationStyle = { size = 11, outline = "OUTLINE", color = { 1.00, 0.82, 0.00 }, classColor = false },
		countStyle = text(12),
		hideArena = true, hideBG = true, hideDungeon = false, hideRaid = false, hideAlways = false, hideCombat = false,
		debuffs = false,  -- also hide debuffs (off: debuffs always show)
		mouseover = true, -- mouse over the spot to see them while hidden
	},
	-- Window Mover (replaces BlizzMove): drag Blizzard windows, Ctrl + wheel to resize
	windowMover = {
		enabled = true,
		wheel = true,       -- Ctrl + mouse wheel over a window changes its size
		modifier = "none",  -- none | alt | shift | ctrl: key to hold while dragging
		remember = true,    -- keep positions and sizes across sessions
		frames = {},        -- window name -> { point, scale }
		extra = {},         -- more window names to make movable
	},
	-- Queue Time & MMR: while you're queued, each queue's bracket, time waited, Blizzard's estimate
	-- and your MMR there (from your last match in that bracket on this character)
	queueInfo = {
		enabled = true,
		estimate = true, mmr = true, mmrChange = true, rating = false,
		specIcon = true, header = true, hideInPvP = true, -- queued spec icon per row, "Queued as" line
		width = 440, height = 22, spacing = 2, scale = 1,
		background = true, bgColor = { 0.04, 0.04, 0.05 }, bgAlpha = 0.65, border = true,
		textStyle = text(14),
		labelStyle = { size = 14, outline = "OUTLINE", color = { 0.75, 0.80, 0.16 }, classColor = false },
		point = { "TOP", 0, -200 },
	},
	cooldowns = {
		centerEssential = true, centerUtility = true, centerBuffs = true,
		skinBlizzard = true,
		iconZoom = 0.08, -- fraction cropped from each icon edge (custom bars and skinned Blizzard icons)
		bars = {
			{
				enabled = true, size = 36, spacing = 4, perRow = 12, showCount = true,
				countStyle = text(12),
				entries = { "slot:13", "slot:14", "racial", "item:5512" },
				point = { "BOTTOM", 0, 140 },
			},
			{
				enabled = false, size = 32, spacing = 4, perRow = 12, showCount = true,
				countStyle = text(12),
				entries = {},
				point = { "BOTTOM", 0, 100 },
			},
		},
	},
}

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local function CopyDefaults(src, dst)
	if type(dst) ~= "table" then dst = {} end
	for k, v in pairs(src) do
		if type(v) == "table" then
			if dst[k] == nil then
				dst[k] = CopyDefaults(v, {})
			elseif type(dst[k]) == "table" then
				if #v == 0 then
					CopyDefaults(v, dst[k]) -- record: merge new keys
				elseif type(v[1]) == "table" then
					-- list of records (custom bars): merge each existing record
					for i = 1, #v do
						dst[k][i] = CopyDefaults(v[i], dst[k][i])
					end
				end
				-- lists of plain values (points, colors, entries) are kept as saved
			end
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end
ns.CopyDefaults = CopyDefaults

-- One-time changes for people upgrading from an older version.
local function Migrate(db)
	local v = db.version or 1
	if v < 2 then
		for _, cfg in pairs(db.units or {}) do
			if cfg.nameAbove == true then cfg.nameAbove = false end
			if cfg.healthText == "none" then cfg.healthText = "percent" end
		end
		db.fontSize = nil
	end
	-- v3: nothing to convert; "THICKOUTLINE" styles are mapped to "OUTLINE, THICK" when applied
	if v < 4 then
		-- shields switch from the old white default to yellow
		local a = db.colors and db.colors.absorb
		if a and a[1] == 1 and a[2] == 1 and a[3] == 1 then db.colors.absorb = { 1.00, 0.82, 0.25, 0.55 } end
	end
	if v < 5 then
		-- battleground blocks: 15 rows by default (was 10)
		for _, key in ipairs({ "bgEnemies", "bgAllies" }) do
			if db[key] and db[key].maxRows == 10 then db[key].maxRows = 15 end
		end
	end
	if v < 6 then
		-- objectives background: new default is 0% opacity (0.27 started at 50%)
		if db.objectives and db.objectives.bgAlpha == 0.5 then db.objectives.bgAlpha = 0 end
	end
	if v < 7 then
		-- Match History: unrated games (skirmish, brawls, unrated battlegrounds) are no longer saved
		local mh = db.matchHistory
		if mh then mh.skirmish, mh.battleground, mh.brawl, mh.unrated = false, false, false, false end
	end
	if v < 8 then
		-- Character Sheet: 55% window opacity and wider item text (roomier layout), if still at 0.28's values
		local ch = db.character
		if ch then
			if ch.frameAlpha == 0.95 then ch.frameAlpha = 0.55 end
			if ch.textWidth == 110 then ch.textWidth = 140 end
		end
	end
	if v < 9 then
		-- Queue display: wider for the spec icon and "MMR unknown"; the personal DR timers are gone
		local qi = db.queueInfo
		if qi and qi.width == 300 then qi.width = 360 end
		local aa = db.arenaAssist
		if aa then
			for k in pairs(aa) do if k == "dr" or (k:match("^dr%u")) then aa[k] = nil end end
		end
	end
	if v < 10 then
		-- Queue display: four equal columns need a little more width
		local qi = db.queueInfo
		if qi and (qi.width == 300 or qi.width == 360) then qi.width = 440 end
	end
	if v < 11 then
		-- Character Sheet: smaller text (feedback: too busy) if still on the old sizes
		local ch = db.character
		if ch then
			if ch.nameStyle and ch.nameStyle.size == 12 then ch.nameStyle.size = 11 end
			if ch.infoStyle and ch.infoStyle.size == 11 then ch.infoStyle.size = 10 end
		end
	end
	if v < 12 then
		-- Character Sheet: window opacity 90% (0.30-0.35 had 55%)
		local ch = db.character
		if ch and ch.frameAlpha == 0.55 then ch.frameAlpha = 0.9 end
	end
	if v < 13 then
		-- Nameplates: stacking off for enemies and friendlies (it used to copy the game's setting)
		local st = db.nameplates and db.nameplates.stacking
		if st then st.enemies, st.friendly = false, false end
	end
	db.version = ns.DB_VERSION
end
ns.Migrate = Migrate

---------------------------------------------------------------------------
-- Export / import (C_EncodingUtil: CBOR -> deflate -> base64)
---------------------------------------------------------------------------
local EXPORT_PREFIX = "STINKIEUI1:"

local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = DeepCopy(v) end
	return c
end

function ns:ExportProfile()
	local E = C_EncodingUtil
	if not (E and E.SerializeCBOR) then return nil, "This client has no encoding API." end
	local copy = DeepCopy(ns.db)
	if copy.combatLog then copy.combatLog.startedByUs = nil end
	local ok, out = pcall(function()
		return E.EncodeBase64(E.CompressString(E.SerializeCBOR(copy)))
	end)
	if not ok then return nil, tostring(out) end
	return EXPORT_PREFIX .. out
end

-- Returns the decoded profile table, or nil and an error message. Does not apply it.
function ns:DecodeProfile(text)
	local E = C_EncodingUtil
	if not (E and E.DeserializeCBOR) then return nil, "This client has no encoding API." end
	text = strtrim(text or ""):gsub("%s+", "")
	if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
		return nil, "That isn't a Stinkie UI export string."
	end
	local ok, t = pcall(function()
		return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(text:sub(#EXPORT_PREFIX + 1))))
	end)
	if not ok or type(t) ~= "table" or type(t.units) ~= "table" then
		return nil, "The string is damaged or incomplete. Copy the whole thing and try again."
	end
	return t
end

---------------------------------------------------------------------------
-- Profiles. StinkieUIDB = { profiles = { [name] = settings }, chars = { ["Name - Realm"] = name } }
-- Every character uses "Default" until it is given its own profile. ns.db is the active profile.
---------------------------------------------------------------------------
ns.DEFAULT_PROFILE = "Default"

local function Store() return StinkieUIDB end

function ns.CharKey()
	local name = UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or ""
	return name .. " - " .. realm
end

function ns:CurrentProfileName()
	return ns.profileName or ns.DEFAULT_PROFILE
end

function ns:GetProfileNames()
	local list = {}
	for name in pairs(Store().profiles) do table.insert(list, name) end
	table.sort(list, function(a, b)
		if a == ns.DEFAULT_PROFILE then return true end
		if b == ns.DEFAULT_PROFILE then return false end
		return a < b
	end)
	return list
end

-- Points this character at a profile (created as a copy of the current one if new).
-- Takes effect after a reload.
function ns:SetProfile(name, copyCurrent)
	name = strtrim(name or "")
	if name == "" then return false, "Give the profile a name." end
	local store = Store()
	if not store.profiles[name] then
		local base = copyCurrent and DeepCopy(ns.db) or {}
		if base.combatLog then base.combatLog.startedByUs = false end
		store.profiles[name] = CopyDefaults(ns.defaults, base)
		store.profiles[name].version = ns.DB_VERSION
	end
	store.chars[ns.CharKey()] = name
	return true
end

function ns:DeleteProfile(name)
	local store = Store()
	if name == ns.DEFAULT_PROFILE then return false, "The Default profile can't be deleted." end
	if name == ns:CurrentProfileName() then return false, "That profile is in use on this character." end
	if not store.profiles[name] then return false, "No profile called " .. tostring(name) .. "." end
	store.profiles[name] = nil
	for char, p in pairs(store.chars) do
		if p == name then store.chars[char] = nil end -- falls back to Default
	end
	return true
end

-- Copies another profile's settings over the active one. Takes effect after a reload.
function ns:CopyProfile(from)
	local src = Store().profiles[from]
	if not src or from == ns:CurrentProfileName() then return false end
	local t = CopyDefaults(ns.defaults, DeepCopy(src))
	if t.combatLog then t.combatLog.startedByUs = false end
	Store().profiles[ns:CurrentProfileName()] = t
	ns.db = t
	return true
end

function ns:ImportProfile(text)
	local t, err = ns:DecodeProfile(text)
	if not t then return false, err end
	t.version = t.version or 1
	t = CopyDefaults(ns.defaults, t)
	ns.Migrate(t)
	if t.combatLog then t.combatLog.startedByUs = false end
	Store().profiles[ns:CurrentProfileName()] = t
	ns.db = t
	return true
end

function ns:ResetProfile()
	local t = CopyDefaults(ns.defaults, {})
	Store().profiles[ns:CurrentProfileName()] = t
	ns.db = t
end

-- Loads the store, converting the pre-0.9 single-profile layout into profiles.Default.
local function LoadStore()
	local raw = StinkieUIDB
	local store
	if type(raw) == "table" and type(raw.profiles) == "table" then
		store = raw
	else
		store = { profiles = {}, chars = {} }
		if type(raw) == "table" and next(raw) ~= nil then
			if raw.version == nil then raw.version = 1 end
			store.profiles[ns.DEFAULT_PROFILE] = raw
		end
	end
	store.chars = store.chars or {}
	StinkieUIDB = store
	local name = store.chars[ns.CharKey()]
	if not (name and store.profiles[name]) then name = ns.DEFAULT_PROFILE end
	local db = CopyDefaults(ns.defaults, store.profiles[name])
	if db.version ~= ns.DB_VERSION then Migrate(db) end
	store.profiles[name] = db
	ns.profileName = name
	return db
end
ns.LoadStore = LoadStore

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

---------------------------------------------------------------------------
-- Profiler (/stinkie cpu): off unless asked for; when off each timed spot costs one test.
---------------------------------------------------------------------------
ns.profile = { on = false, ms = {}, calls = {} }
local profile = ns.profile
local function Account(key, start)
	local dt = debugprofilestop() - start
	profile.ms[key] = (profile.ms[key] or 0) + dt
	profile.calls[key] = (profile.calls[key] or 0) + 1
end
ns.ProfileAccount = Account

-- wraps a function so its time counts under key while profiling
function ns.Timed(key, fn)
	return function(...)
		if not profile.on then return fn(...) end
		local start = debugprofilestop()
		local a, b, c, d = fn(...)
		Account(key, start)
		return a, b, c, d
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		if profile.on then
			local start = debugprofilestop()
			for i = 1, #list do list[i](event, ...) end
			Account("events: " .. event, start)
			return
		end
		for i = 1, #list do list[i](event, ...) end
	end
end)

function ns.StartProfile(seconds)
	seconds = seconds or 30
	wipe(profile.ms); wipe(profile.calls)
	profile.on = true
	profile.started = GetTime()
	ns:Print(string.format("Measuring CPU for %d seconds. Play normally (or do the thing that feels slow).", seconds))
	C_Timer.After(seconds, function() ns.StopProfile() end)
end

function ns.StopProfile()
	if not profile.on then return end
	profile.on = false
	local elapsed = math.max(0.001, GetTime() - (profile.started or GetTime()))
	local list, total = {}, 0
	for key, ms in pairs(profile.ms) do
		list[#list + 1] = { key = key, ms = ms, calls = profile.calls[key] or 0 }
		total = total + ms
	end
	table.sort(list, function(a, b) return a.ms > b.ms end)
	ns:Print(string.format("CPU over %.0f s: %.1f ms per second measured in total (%.2f%% of one core).", elapsed, total / elapsed, total / elapsed / 10))
	for i = 1, math.min(12, #list) do
		local e = list[i]
		ns:Print(string.format("  %5.2f ms/s  %6d calls  %s", e.ms / elapsed, e.calls, e.key))
	end
	local P, M = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
	if P and P.GetAddOnMetric and M and M.RecentAverageTime then
		local ok, v = pcall(P.GetAddOnMetric, "StinkieUI", M.RecentAverageTime)
		if ok and type(v) == "number" then ns:Print(string.format("Game's own figure for Stinkie UI (recent average): %.3f ms per frame.", v)) end
	end
end

-- Run protected work now, or as soon as combat ends.
local combatQueue = {}
function ns:RunOOC(fn)
	if InCombatLockdown() then
		table.insert(combatQueue, fn)
	else
		fn()
	end
end
ns:On("PLAYER_REGEN_ENABLED", function()
	while #combatQueue > 0 do
		table.remove(combatQueue, 1)()
	end
end)

function ns:Print(msg)
	print("|cff" .. ns.ACCENT_HEX .. "Stinkie UI|r: " .. tostring(msg))
end

-- Secret-value helpers (Midnight). Never compare or branch on a secret.
local issecretvalue = issecretvalue or function() return false end
ns.issecret = issecretvalue
function ns.IsUsable(v)
	return not issecretvalue(v)
end

---------------------------------------------------------------------------
-- Positioning and movers
---------------------------------------------------------------------------
function ns:ApplyPoint(frame, p)
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

ns.ANCHORS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

-- Expresses a frame's current position relative to an anchor. With no anchor given, picks the
-- nearest screen edge or corner (thirds) so layouts survive resolution and aspect changes.
function ns.CalculatePoint(frame, forced)
	local cx, cy = frame:GetCenter()
	if not cx then return nil end
	local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	cx, cy = cx * s, cy * s
	local W, H = UIParent:GetSize()
	local fw, fh = frame:GetWidth() * s, frame:GetHeight() * s

	local hp, vp
	if forced then
		hp = forced:find("LEFT") and "LEFT" or forced:find("RIGHT") and "RIGHT" or ""
		vp = forced:find("TOP") and "TOP" or forced:find("BOTTOM") and "BOTTOM" or ""
	else
		hp = (cx < W / 3 and "LEFT") or (cx > W * 2 / 3 and "RIGHT") or ""
		vp = (cy > H * 2 / 3 and "TOP") or (cy < H / 3 and "BOTTOM") or ""
	end
	local x = (hp == "LEFT" and cx - fw / 2) or (hp == "RIGHT" and cx + fw / 2 - W) or (cx - W / 2)
	local y = (vp == "TOP" and cy + fh / 2 - H) or (vp == "BOTTOM" and cy - fh / 2) or (cy - H / 2)
	local point = vp .. hp
	if point == "" then point = "CENTER" end
	return { point, math.floor(x / s + 0.5), math.floor(y / s + 0.5) }
end

ns.movers = {}
ns.moverOrder = {}

-- frame: the thing to move. getPoint/setPoint read and write the saved table.
function ns:RegisterMover(key, frame, label, getPoint, setPoint)
	local m = ns.movers[key]
	if not m then
		m = { key = key }
		ns.movers[key] = m
		table.insert(ns.moverOrder, key)
	end
	m.frame, m.label, m.getPoint, m.setPoint = frame, label, getPoint, setPoint
	return m
end

function ns:IsMoverActive(key)
	local m = ns.movers[key]
	return m and m.frame and m.frame.SUIActive ~= false
end

-- Sets a mover's saved point and moves the frame (out of combat).
function ns:SetMoverPoint(key, p)
	local m = ns.movers[key]
	if not m then return end
	m.setPoint(p)
	ns:RunOOC(function() ns:ApplyPoint(m.frame, p) end)
	if ns.nudgePanel and ns.selectedMover == m then ns.nudgePanel:Sync() end
end

function ns:NudgeMover(key, dx, dy)
	local m = ns.movers[key]
	if not m then return end
	local p = m.getPoint()
	ns:SetMoverPoint(key, { p[1], p[2] + dx, p[3] + dy })
end

-- Re-expresses the same screen position relative to a different anchor.
function ns:SetMoverAnchor(key, anchor)
	local m = ns.movers[key]
	if not m then return end
	local p = ns.CalculatePoint(m.frame, anchor) or { anchor, 0, 0 }
	ns:SetMoverPoint(key, p)
end

local function UpdateOverlayColor(m)
	local o = m.overlay
	if not o then return end
	local a = (ns.selectedMover == m) and 0.75 or 0.4
	o.tex:SetColorTexture(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], a)
end

local function CreateNudgePanel()
	local p = CreateFrame("Frame", "StinkieUINudge", UIParent)
	p:SetSize(250, 74)
	p:SetPoint("TOP", 0, -120)
	p:SetFrameStrata("FULLSCREEN_DIALOG")
	p:EnableMouse(true)
	p:SetMovable(true)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", p.StartMoving)
	p:SetScript("OnDragStop", p.StopMovingOrSizing)
	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.07, 0.07, 0.08, 0.95)

	local title = p:CreateFontString(nil, "OVERLAY")
	ns.SetFont(title, 13, "OUTLINE")
	title:SetPoint("TOPLEFT", 8, -6)
	p.title = title
	local hint = p:CreateFontString(nil, "OVERLAY")
	ns.SetFont(hint, 10)
	hint:SetTextColor(0.6, 0.6, 0.65)
	hint:SetPoint("BOTTOMLEFT", 8, 6)
	hint:SetText("Arrow keys nudge 1, Shift+arrow 10")

	local function box(label, x, idx)
		local l = p:CreateFontString(nil, "OVERLAY")
		ns.SetFont(l, 12)
		l:SetPoint("TOPLEFT", x, -30)
		l:SetText(label)
		local eb = CreateFrame("EditBox", nil, p)
		eb:SetSize(60, 18)
		eb:SetPoint("LEFT", l, "RIGHT", 6, 0)
		eb:SetAutoFocus(false)
		ns.SetFont(eb, 12)
		eb:SetJustifyH("CENTER")
		local t = eb:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints()
		t:SetColorTexture(0.15, 0.15, 0.17, 1)
		eb:SetScript("OnEnterPressed", function(self)
			local m = ns.selectedMover
			local v = tonumber(self:GetText())
			if m and v then
				local pt = m.getPoint()
				local np = { pt[1], pt[2], pt[3] }
				np[idx] = math.floor(v + 0.5)
				ns:SetMoverPoint(m.key, np)
			end
			self:ClearFocus()
			p:Sync()
		end)
		eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); p:Sync() end)
		return eb
	end
	p.x = box("X", 8, 2)
	p.y = box("Y", 100, 3)
	local anchor = p:CreateFontString(nil, "OVERLAY")
	ns.SetFont(anchor, 11)
	anchor:SetTextColor(0.7, 0.7, 0.75)
	anchor:SetPoint("TOPRIGHT", -8, -8)
	p.anchor = anchor

	function p:Sync()
		local m = ns.selectedMover
		if not m then self:Hide() return end
		local pt = m.getPoint()
		self.title:SetText(m.label)
		self.anchor:SetText(pt[1])
		if not self.x:HasFocus() then self.x:SetText(pt[2]) end
		if not self.y:HasFocus() then self.y:SetText(pt[3]) end
	end

	-- arrow-key nudging while unlocked
	p:EnableKeyboard(true)
	p:SetScript("OnKeyDown", function(self, key)
		local m = ns.selectedMover
		local step = IsShiftKeyDown() and 10 or 1
		local dx, dy = 0, 0
		if key == "UP" then dy = step elseif key == "DOWN" then dy = -step
		elseif key == "LEFT" then dx = -step elseif key == "RIGHT" then dx = step end
		if m and (dx ~= 0 or dy ~= 0) and not InCombatLockdown() then
			self:SetPropagateKeyboardInput(false)
			ns:NudgeMover(m.key, dx, dy)
		elseif not InCombatLockdown() then
			self:SetPropagateKeyboardInput(true)
		end
	end)
	p:Hide()
	return p
end

function ns:SelectMover(m)
	local old = ns.selectedMover
	ns.selectedMover = m
	if old then UpdateOverlayColor(old) end
	if m then UpdateOverlayColor(m) end
	ns.nudgePanel = ns.nudgePanel or CreateNudgePanel()
	if m then
		ns.nudgePanel:Show()
		ns.nudgePanel:Sync()
	else
		ns.nudgePanel:Hide()
	end
end

local function CreateOverlay(m)
	local o = CreateFrame("Frame", nil, UIParent)
	o:SetFrameStrata("DIALOG")
	o:EnableMouse(true)
	o:RegisterForDrag("LeftButton")
	local tex = o:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints()
	o.tex = tex
	local label = o:CreateFontString(nil, "OVERLAY")
	ns.SetFont(label, 11, "OUTLINE")
	label:SetPoint("CENTER")
	o.label = label
	o:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		ns:SelectMover(m)
		m.frame:SetMovable(true)
		m.frame:StartMoving()
	end)
	o:SetScript("OnDragStop", function()
		m.frame:StopMovingOrSizing()
		local p = ns.CalculatePoint(m.frame)
		if p then ns:SetMoverPoint(m.key, p) end
	end)
	o:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then ns:SelectMover(m) end
	end)
	o:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then ns:ToggleOptions() end
	end)
	m.overlay = o
	return o
end

function ns:SetLocked(locked, silent)
	if not locked and InCombatLockdown() then
		ns:Print("Can't unlock in combat.")
		return
	end
	ns.unlocked = not locked
	for _, key in ipairs(ns.moverOrder) do
		local m = ns.movers[key]
		if ns:IsMoverActive(key) then
			local o = m.overlay or CreateOverlay(m)
			if locked then
				o:Hide()
			else
				o:ClearAllPoints()
				o:SetAllPoints(m.frame)
				o.label:SetText(m.label)
				UpdateOverlayColor(m)
				o:Show()
			end
		elseif m.overlay then
			m.overlay:Hide()
		end
	end
	if locked then ns:SelectMover(nil) end
	for _, fn in ipairs(ns.lockCallbacks) do fn(not locked) end
	if not locked and not silent then ns:Print("Unlocked. Drag boxes or click one and use arrow keys. /stinkie lock when done.") end
end
ns.lockCallbacks = {}
ns:On("PLAYER_REGEN_DISABLED", function()
	if ns.unlocked then ns:SetLocked(true) end
end)

---------------------------------------------------------------------------
-- Hiding Blizzard frames (12.x: unregister, hide, and keep them hidden)
---------------------------------------------------------------------------
local function KillBlizzard(frame)
	if type(frame) == "string" then frame = _G[frame] end
	if not frame then return end
	frame:UnregisterAllEvents()
	if frame.SetRolesets then
		frame:SetRolesets("alwaysBlocked")
	else
		frame:Hide()
	end
	for _, key in ipairs({ "healthBar", "healthbar", "HealthBar", "manabar", "ManaBar", "spellbar", "castBar", "CastingBarFrame", "BuffFrame", "AurasFrame", "DebuffFrame", "totFrame", "petFrame", "PetFrame" }) do
		local child = frame[key]
		if type(child) == "table" and child.UnregisterAllEvents then child:UnregisterAllEvents() end
	end
end
ns.KillBlizzard = KillBlizzard

function ns:HideBlizzardCastbar(which)
	local bar = which == "player" and PlayerCastingBarFrame
		or which == "target" and TargetFrameSpellBar
		or which == "focus" and FocusFrameSpellBar
	if bar then
		bar:UnregisterAllEvents()
		bar:Hide()
	end
	if which == "player" and PetCastingBarFrame then
		PetCastingBarFrame:UnregisterAllEvents()
		PetCastingBarFrame:Hide()
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
ns.modules = {}
function ns:RegisterModule(name, mod)
	ns.modules[name] = mod
	table.insert(ns.modules, mod)
end

ns:On("ADDON_LOADED", function(_, name)
	if name ~= addonName then return end
	local db = LoadStore()
	ns.db = db
	-- Floating combat text and world names read these once while the world loads, so this
	-- has to happen here (before PLAYER_LOGIN) and takes a relog to change.
	if db.combatTextFont then
		local path = ns.GetFontPath()
		ns.damageFontReady = ns.FontLoads(path) -- /stinkie dmg reports this: a cold login can refuse it
		DAMAGE_TEXT_FONT = path
	end
	if db.worldNameFont then UNIT_NAME_FONT = ns.GetFontPath() end
end)

-- Share the bundled font with other addons that use LibSharedMedia, and offer theirs here.
local function HookSharedMedia()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if not LSM then return end
	LSM:Register("font", ns.DEFAULT_FONT, ns.FONTS[1][2])
	local known = {}
	for _, f in ipairs(ns.FONTS) do known[f[1]] = true end
	for _, fontName in ipairs(LSM:List("font")) do
		if not known[fontName] then
			table.insert(ns.FONTS, { fontName, LSM:Fetch("font", fontName) })
			known[fontName] = true
		end
	end
end

local function ScheduleFontPasses()
	RetryFonts(false)
	C_Timer.After(1, function() RetryFonts(false) end)
	C_Timer.After(4, function() RetryFonts(false) end)
	C_Timer.After(10, function() RetryFonts(true) end)
end
ns:On("PLAYER_ENTERING_WORLD", ScheduleFontPasses)
ns:On("UI_SCALE_CHANGED", function() C_Timer.After(0, function() RetryFonts(false) end) end)
ns:On("DISPLAY_SIZE_CHANGED", function() C_Timer.After(0, function() RetryFonts(false) end) end)

ns:On("PLAYER_LOGIN", function()
	pcall(HookSharedMedia)
	for _, mod in ipairs(ns.modules) do
		if mod.Init then
			local ok, err = pcall(mod.Init, mod)
			if not ok then geterrorhandler()(err) end
		end
	end
end)

-- Which part of a name to show: "first", "last", anything else keeps it whole. "Stormwind Guard"
-- -> "Stormwind" / "Guard". A title after a comma isn't part of the name ("Thrall, Warchief of the
-- Horde" -> "Thrall"). A hidden (secret) name can't be read, so it's returned whole. Spaces are
-- matched literally: %s can take a byte of an accented letter for a space.
function ns.ShortenName(name, format)
	if format ~= "first" and format ~= "last" then return name end
	if ns.issecret(name) or type(name) ~= "string" then return name end
	local beforeComma = name:match("^[^,]+") or name
	if format == "first" then return beforeComma:match("^ *([^ ]+)") or name end
	return beforeComma:match("([^ ]+) *$") or name
end

-- Re-apply sizes, fonts, colors and positions after an options change.
function ns:Refresh()
	ns:RunOOC(function()
		for _, mod in ipairs(ns.modules) do
			if mod.Refresh then
				local ok, err = pcall(mod.Refresh, mod)
				if not ok then geterrorhandler()(err) end
			end
		end
		if ns.unlocked then ns:SetLocked(false, true) end
	end)
end

SLASH_STINKIERELOAD1 = "/rl"
SlashCmdList.STINKIERELOAD = function() ReloadUI() end

SLASH_STINKIEUI1 = "/stinkie"
SLASH_STINKIEUI2 = "/sui"
SLASH_STINKIEUI3 = "/st"
SlashCmdList.STINKIEUI = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "unlock" or msg == "move" then
		ns:SetLocked(false)
	elseif msg == "lock" then
		ns:SetLocked(true)
	elseif msg == "fontcheck" then
		ns:FontCheck()
	elseif msg == "quest" then
		ns.QuestArrow.Debug()
	elseif msg == "dmg" then
		if ns.DamageText then ns.DamageText.Print() end
	elseif msg == "cpu" then
		if ns.profile.on then ns.StopProfile() else ns.StartProfile(30) end
	elseif msg == "plates" then
		if ns.Nameplates and ns.Nameplates.PrintStacking then ns.Nameplates.PrintStacking() end
	elseif msg == "auras" then
		if ns.Nameplates and ns.Nameplates.DebugTarget then ns.Nameplates.DebugTarget() end
	elseif msg == "flags" then
		if ns.FlagCap then ns.FlagCap.Debug() end
	elseif msg == "flags reset" then
		if ns.FlagCap then ns.FlagCap.ResetLearned() end
	elseif msg == "timers" then
		if ns.BGTimers then ns.BGTimers.Debug() end
	elseif msg == "score" then
		if ns.MatchRecorder and ns.MatchRecorder.DebugScore then ns.MatchRecorder.DebugScore() end
	elseif msg == "history" or msg == "mh" or msg == "m" then
		if ns.MatchRecorder then ns.MatchRecorder.Open() end
	elseif msg == "reset" then
		ns:ResetProfile()
		ReloadUI()
	else
		ns:ToggleOptions()
	end
end

function StinkieUI_OnAddonCompartmentClick()
	ns:ToggleOptions()
end
