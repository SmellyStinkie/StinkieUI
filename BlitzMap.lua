-- StinkieUI: Blitz Map. The zone map of a Blitz in a flat square window, with class colored dots (a
-- plus for healers) and names for your team, our own flag and orb icons, and the bases and objectives the map reports.
-- Wheel to zoom, drag to look around, Shift+drag to move the window. Only our own frames; shows only
-- in Blitz (or test mode).
-- Tiles sit on a canvas that scales with the zoom. Pins sit on their own layer and are placed by
-- hand, so they stay the same size at any zoom. Both are clipped to the window.
local _, ns = ...

local BM = {}
ns.BlitzMap = BM

local issecret = ns.issecret
local function readable(v) return v ~= nil and not issecret(v) end
local function cfg() return ns.db.blitzMap end

local TEST_MAP = 1366 -- Arathi Basin
local POI_ICONS = [[Interface\Minimap\POIIcons]]
local TICK = 0.1
local MAX_ZOOM, ZOOM_STEP = 6, 1.25

local TEAM = { Alliance = { 0.25, 0.55, 1 }, Horde = { 0.95, 0.25, 0.25 }, Neutral = { 1, 0.85, 0.3 } }
local ORB = { cyan = { 0.2, 0.9, 1 }, green = { 0.3, 0.95, 0.3 }, orange = { 1, 0.55, 0.1 }, purple = { 0.75, 0.35, 1 } }

---------------------------------------------------------------------------
-- Pure logic (testable outside the game). Window positions run down and right from the top left;
-- pan is where the map's top left sits, so it's zero or negative.
---------------------------------------------------------------------------
local L = {}
BM.Logic = L

-- The game gives a file for each marker. These are Blizzard's art for them.
local ICONS = {
	[137200] = { kind = "flag", color = TEAM.Alliance },
	[137218] = { kind = "flag", color = TEAM.Horde },
	[625754] = { kind = "orb", color = ORB.cyan },
	[625755] = { kind = "orb", color = ORB.green },
	[625756] = { kind = "orb", color = ORB.orange },
	[625757] = { kind = "orb", color = ORB.purple },
}

function L.Icon(texture)
	local known = ICONS[texture]
	if known then return known end
	if type(texture) == "string" then
		local t = texture:lower()
		if t:find("allianceflag", 1, true) then return ICONS[137200] end
		if t:find("hordeflag", 1, true) then return ICONS[137218] end
		local orb = t:match("ball_(%a+)")
		if orb and ORB[orb] then return { kind = "orb", color = ORB[orb] } end
	end
	return { kind = "flag", color = TEAM.Neutral }
end

function L.IsGraveyard(name)
	return type(name) == "string" and name:lower():find("graveyard", 1, true) ~= nil
end

function L.IsFlagName(name)
	return type(name) == "string" and name:lower():find("flag", 1, true) ~= nil
end

function L.ClampPan(panX, panY, zoom, w, h)
	return math.min(0, math.max(w - w * zoom, panX)), math.min(0, math.max(h - h * zoom, panY))
end

-- New pan for a zoom that keeps the point under the cursor where it is
function L.ZoomAt(zoom, newZoom, panX, panY, cursorX, cursorY, w, h)
	local x = cursorX - (cursorX - panX) / zoom * newZoom
	local y = cursorY - (cursorY - panY) / zoom * newZoom
	return L.ClampPan(x, y, newZoom, w, h)
end

function L.Place(u, v, zoom, panX, panY, w, h)
	return panX + u * w * zoom, panY + v * h * zoom
end

-- The spot on the map at the middle of the window, 0 to 1. Saved views use this rather than pixels,
-- so they still fit after the window's width changes.
function L.ViewCenter(panX, panY, zoom, w, h)
	return (w / 2 - panX) / (w * zoom), (h / 2 - panY) / (h * zoom)
end

function L.PanForCenter(u, v, zoom, w, h)
	return L.ClampPan(w / 2 - u * w * zoom, h / 2 - v * h * zoom, zoom, w, h)
end

function L.NextZoom(zoom, delta)
	local z = delta > 0 and zoom * ZOOM_STEP or zoom / ZOOM_STEP
	z = math.max(1, math.min(MAX_ZOOM, z))
	return z < 1.01 and 1 or z
end

-- Column and row counts of a map's art. Tiles are numbered across, row by row.
function L.TileGrid(layer)
	return math.ceil(layer.layerWidth / layer.tileWidth), math.ceil(layer.layerHeight / layer.tileHeight)
end

local TEAMMATES = {
	{ "Stinkie", "DRUID" }, { "Vile", "WARLOCK" }, { "Phankrit", "PALADIN" }, { "Shaakorak", "SHAMAN" },
	{ "Garrick", "WARRIOR" }, { "Crenna", "HUNTER" }, { "Meredy", "PRIEST" }, { "Huxworth", "MAGE" },
}

-- rough spots on Arathi Basin, with one of the game's icons for each
local TEST_BASES = {
	{ "Stables", 0.38, 0.30, 36 }, { "Gold Mine", 0.58, 0.31, 16 }, { "Blacksmith", 0.47, 0.46, 26 },
	{ "Lumber Mill", 0.40, 0.56, 21 }, { "Farm", 0.56, 0.60, 31 },
}

-- Made-up team and markers wandering around the map, and the bases if they're wanted
function L.TestPins(now, withBases)
	local pins = {}
	for i, mate in ipairs(TEAMMATES) do
		local a = now * 0.25 + i * 0.8
		pins[i] = { kind = "unit", me = i == 1, name = mate[1], class = mate[2], healer = mate[2] == "PRIEST",
			x = 0.5 + math.cos(a) * (0.1 + i * 0.03), y = 0.5 + math.sin(a * 1.3) * (0.08 + i * 0.03) }
	end
	local function marker(texture, x, y)
		local icon = L.Icon(texture)
		pins[#pins + 1] = { kind = icon.kind, color = icon.color, x = x, y = y }
	end
	marker(137200, 0.3 + math.sin(now * 0.4) * 0.05, 0.3)
	marker(137218, 0.7, 0.68 + math.cos(now * 0.4) * 0.05)
	marker(625754, 0.2, 0.7)
	marker(625757, 0.8, 0.25)
	pins[#pins + 1] = { kind = "cart", atlas = "vehicle-silvershardmines-minecartblue", x = 0.6 + math.cos(now * 0.3) * 0.08,
		y = 0.42, facing = now * 0.3 }
	if withBases then
		for _, base in ipairs(TEST_BASES) do
			pins[#pins + 1] = { kind = "node", name = base[1], x = base[2], y = base[3], poiIndex = base[4] }
		end
	end
	return pins
end

---------------------------------------------------------------------------
-- What's on the map
---------------------------------------------------------------------------
-- Units the addon can't get a position for (the game only promises the player and party members,
-- and a Blitz team is a raid): the game draws those dots itself, see UpdateGameDots.
BM.gameDots = {}

-- A plus has less to it than a filled dot, so it's drawn a little bigger to read the same
BM.HEALER_SCALE = 1.4

-- A hidden role can't be tested, so that unit stays a dot
function BM.IsHealer(unit)
	local role = UnitGroupRolesAssigned(unit)
	return readable(role) and role == "HEALER"
end

local function UnitPin(pins, mapID, unit, me)
	local pos = C_Map.GetPlayerMapPosition(mapID, unit)
	local x, y
	if pos then x, y = pos.x, pos.y end
	if not (x and y and readable(x) and readable(y)) or (x == 0 and y == 0) then
		local dots = BM.gameDots
		dots[#dots + 1] = unit
		return
	end
	pins[#pins + 1] = { kind = "unit", unit = unit, me = me, x = x, y = y, healer = BM.IsHealer(unit) }
end

local function HidesVignettes(mapID)
	local info = C_Map.GetMapInfo(mapID)
	local hide = Enum.UIMapFlag and Enum.UIMapFlag.HideVignettes
	return info and info.flags and hide and bit.band(info.flags, hide) ~= 0
end

-- Bases come from the map's points of interest, other objectives (a flag waiting to be picked up)
-- from its vignettes: the same two lists Blizzard's map draws from. Their icons already show who
-- owns a base and if it's contested, so a base uses the game's icon.
function BM.ReadObjectives(mapID)
	local found = {}
	for _, id in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}) do
		local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
		local pos = info and info.position
		local name = info and readable(info.name) and info.name or nil
		if pos and readable(pos.x) and readable(pos.y) and not L.IsGraveyard(name) then
			local atlas = readable(info.atlasName) and info.atlasName or nil
			local index = readable(info.textureIndex) and info.textureIndex or nil
			if atlas or index then
				found[#found + 1] = { kind = "node", name = name, x = pos.x, y = pos.y, atlas = atlas, poiIndex = index }
			end
		end
	end
	if C_VignetteInfo and not HidesVignettes(mapID) then
		for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
			local info = C_VignetteInfo.GetVignetteInfo(guid)
			if info and info.onWorldMap and not info.isDead then
				local pos = C_VignetteInfo.GetVignettePosition(guid, mapID)
				local name = readable(info.name) and info.name or nil
				if pos and readable(pos.x) and readable(pos.y) then
					if L.IsFlagName(name) then
						found[#found + 1] = { kind = "flag", color = TEAM.Neutral, x = pos.x, y = pos.y }
					elseif readable(info.atlasName) then
						found[#found + 1] = { kind = "node", name = name, x = pos.x, y = pos.y, atlas = info.atlasName }
					end
				end
			end
		end
	end
	return found
end

-- Carts come from the game's vehicle list, the one Blizzard's map draws. Each brings its own icon,
-- picked by the game. Only carts: the same list can hold other maps' vehicles.
function L.IsCart(atlas)
	if type(atlas) ~= "string" then return false end
	local a = atlas:lower()
	return a:find("cart", 1, true) ~= nil or a:find("silvershardmines", 1, true) ~= nil
end

function BM.ReadCarts(mapID, pins)
	if not C_PvP.GetBattlefieldVehicles then return end
	for _, info in ipairs(C_PvP.GetBattlefieldVehicles(mapID) or {}) do
		local x, y, atlas = info.x, info.y, info.atlas
		if readable(x) and readable(y) and readable(atlas) and L.IsCart(atlas)
			and readable(info.isAlive) and info.isAlive and not (readable(info.isPlayer) and info.isPlayer) then
			pins[#pins + 1] = { kind = "cart", atlas = atlas, x = x, y = y, facing = readable(info.facing) and info.facing or 0 }
		end
	end
end

function BM.Collect(mapID)
	wipe(BM.gameDots)
	if BM.Preview() then return L.TestPins(GetTime(), cfg().nodes) end
	local pins = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid" .. i
			-- a hidden answer just draws you twice, in the same spot
			local isMe = UnitIsUnit(unit, "player")
			if not (readable(isMe) and isMe) then UnitPin(pins, mapID, unit, false) end
		end
	else
		for i = 1, GetNumSubgroupMembers() do UnitPin(pins, mapID, "party" .. i, false) end
	end
	UnitPin(pins, mapID, "player", true) -- last, so you're on top
	for i = 1, GetNumBattlefieldFlagPositions() do
		local x, y, texture = C_PvP.GetBattlefieldFlagPosition(i, mapID)
		if readable(x) and readable(y) and (x ~= 0 or y ~= 0) then
			local icon = L.Icon(readable(texture) and texture or nil)
			pins[#pins + 1] = { kind = icon.kind, color = icon.color, x = x, y = y }
		end
	end
	BM.ReadCarts(mapID, pins)
	for _, pin in ipairs(BM.objectives) do pins[#pins + 1] = pin end
	return pins
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local tiles, pinFrames = {}, {}
local zoom, panX, panY = 1, 0, 0
local viewW, viewH = 1, 1

local function GetPin(i)
	local p = pinFrames[i]
	if p then return p end
	p = CreateFrame("Frame", nil, BM.pins)
	p.icon = p:CreateTexture(nil, "ARTWORK")
	p.icon:SetAllPoints()
	p.ring = p:CreateTexture(nil, "ARTWORK", nil, -1) -- behind the dot: your own white rim
	p.ring:SetTexture(ns.MEDIA.dot, "CLAMP", "CLAMP", "TRILINEAR")
	p.ring:SetPoint("CENTER")
	p.label = p:CreateFontString(nil, "OVERLAY")
	p.label:SetPoint("TOP", p, "BOTTOM", 0, -1)
	pinFrames[i] = p
	return p
end

local function SetArt(p, pin)
	local art = pin.atlas or pin.poiIndex or (pin.healer and "cross") or pin.kind
	if p.art == art then return end
	p.art = art
	p.icon:SetTexCoord(0, 1, 0, 1)
	if pin.atlas then
		p.icon:SetAtlas(pin.atlas)
	elseif pin.poiIndex then
		p.icon:SetTexture(POI_ICONS, "CLAMP", "CLAMP", "TRILINEAR")
		p.icon:SetTexCoord(C_Minimap.GetPOITextureCoords(pin.poiIndex))
	else
		p.icon:SetTexture(art == "unit" and ns.MEDIA.dot or ns.MEDIA[art], "CLAMP", "CLAMP", "TRILINEAR")
	end
end

local function ColorFor(pin)
	if pin.kind == "node" or pin.kind == "cart" then return 1, 1, 1 end
	if pin.color then return pin.color[1], pin.color[2], pin.color[3] end
	local c
	if pin.class then
		c = C_ClassColor.GetClassColor(pin.class)
	else
		c = ns.GetUnitClassColor(pin.unit)
	end
	return c.r, c.g, c.b -- can be hidden values: they only go to widget setters
end

-- The game's own unit dots: it places them, so they work with no position to read. The layer is
-- part of the map, so the size is divided by the zoom to stay the same on screen. No name can go
-- with these dots, because the addon never learns where they are.
local function AddGameDot(layer, unit, size)
	local c = ns.GetUnitClassColor(unit)
	local art = ns.MEDIA.dot
	if BM.IsHealer(unit) then art, size = ns.MEDIA.cross, size * BM.HEALER_SCALE end
	-- a hidden color is refused here, where a texture would take it
	if not pcall(layer.AddUnit, layer, unit, art, size, size, c.r, c.g, c.b, 1, 7, false) then
		layer:AddUnit(unit, art, size, size, 1, 1, 1, 1, 7, false)
	end
end

function BM.UpdateGameDots()
	local layer = BM.gameLayer
	if not layer then return end
	local dots = BM.gameDots
	if #dots == 0 and not BM.gameDotsUp then return end
	BM.gameDotsUp = #dots > 0
	layer:ClearUnits()
	local size = cfg().dotSize / zoom
	for _, unit in ipairs(dots) do pcall(AddGameDot, layer, unit, size) end
	layer:FinalizeUnits()
end

-- Names for the game's own dots. The addon never learns where those are, so a name can't sit beside
-- each one; the game will say which of them the mouse is over, though, and those get named there.
BM.HOVER_LINES = 5

-- the units whose game-drawn dot is under the mouse
function BM.HoverUnits()
	local layer = BM.gameLayer
	if not layer or not layer.GetMouseOverUnits or #BM.gameDots == 0 then return nil end
	if not cfg().names or not BM.frame:IsMouseOver() then return nil end
	local found = { pcall(layer.GetMouseOverUnits, layer) }
	if not found[1] then return nil end
	local units = {}
	for i = 2, #found do
		local unit = found[i]
		if readable(unit) and type(unit) == "string" and #units < BM.HOVER_LINES then units[#units + 1] = unit end
	end
	return #units > 0 and units or nil
end

function BM.UpdateHover()
	local hover = BM.hover
	if not hover then return end
	local units = BM.HoverUnits()
	if not units then
		hover:Hide()
		return
	end
	if hover.styled ~= BM.styleRound then
		hover.styled = BM.styleRound
		for _, line in ipairs(hover.lines) do ns.ApplyText(line, cfg().nameStyle) end
	end
	for i, line in ipairs(hover.lines) do
		local unit = units[i]
		line:SetShown(unit ~= nil)
		if unit then
			local c = ns.GetUnitClassColor(unit)
			line:SetText(UnitName(unit)) -- can be hidden: it goes straight to the text
			line:SetTextColor(c.r, c.g, c.b)
		end
	end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	hover:ClearAllPoints()
	hover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 10, y / scale + 6)
	hover:Show()
end

local function Draw(mapID)
	local c = cfg()
	local pins = BM.Collect(mapID)
	for i, pin in ipairs(pins) do
		local p = GetPin(i)
		local r, g, b = ColorFor(pin)
		local isUnit = pin.kind == "unit"
		local isNode = pin.kind == "node"
		local size = isNode and c.nodeSize or isUnit and (pin.me and c.dotSize + 4 or c.dotSize) or c.iconSize
		if pin.healer then size = size * BM.HEALER_SCALE end
		p:SetSize(size, size)
		p:SetFrameLevel(BM.pins:GetFrameLevel() + (isNode and 0 or isUnit and (pin.me and 3 or 1) or 5))
		SetArt(p, pin)
		local facing = pin.facing or 0
		if facing ~= (p.facing or 0) then
			p.facing = facing
			p.icon:SetRotation(facing)
		end
		p.icon:SetVertexColor(r, g, b)
		p.ring:SetShown(pin.me and true or false)
		if pin.me then p.ring:SetSize(size + 4, size + 4) end
		local named = isUnit and c.names
		p.label:SetShown(named and true or false)
		if named then
			if p.styled ~= BM.styleRound then
				p.styled = BM.styleRound
				ns.ApplyText(p.label, c.nameStyle)
			end
			-- a unit's name can be hidden: it goes straight to the text
			p.label:SetText(pin.name or UnitName(pin.unit))
			p.label:SetTextColor(r, g, b)
		end
		local x, y = L.Place(pin.x, pin.y, zoom, panX, panY, viewW, viewH)
		p:ClearAllPoints()
		p:SetPoint("CENTER", BM.pins, "TOPLEFT", x, -y)
		p:Show()
	end
	for i = #pins + 1, #pinFrames do pinFrames[i]:Hide() end
	BM.shownPins = #pins
	BM.UpdateGameDots()
end

local function ApplyView()
	BM.canvas:SetScale(zoom)
	BM.canvas:ClearAllPoints()
	-- offsets are in the canvas's own scaled units
	BM.canvas:SetPoint("TOPLEFT", BM.view, "TOPLEFT", panX / zoom, -panY / zoom)
	if BM.mapID then Draw(BM.mapID) end
end

-- Each map remembers how you left it; a fully zoomed out map needs nothing saved
function BM.SaveView()
	if not BM.mapID then return end
	if zoom == 1 then
		cfg().views[BM.mapID] = nil
	else
		local u, v = L.ViewCenter(panX, panY, zoom, viewW, viewH)
		cfg().views[BM.mapID] = { zoom = zoom, u = u, v = v }
	end
end

local function RestoreView(mapID)
	local saved = cfg().views[mapID]
	if saved then
		zoom = math.max(1, math.min(MAX_ZOOM, saved.zoom))
		panX, panY = L.PanForCenter(saved.u, saved.v, zoom, viewW, viewH)
	else
		zoom, panX, panY = 1, 0, 0
	end
end

-- Returns false if the game has no art for this map
function BM.LoadMap(mapID)
	local layer = (C_Map.GetMapArtLayers(mapID) or {})[1]
	local files = layer and C_Map.GetMapArtLayerTextures(mapID, 1)
	if not (layer and files) then return false end
	local c = cfg()
	local f = BM.frame
	viewW, viewH = c.width, c.width * layer.layerHeight / layer.layerWidth
	f:SetScale(ns.db.scale)
	f:SetSize(viewW, viewH)
	BM.canvas:SetSize(viewW, viewH)
	local cols, rows = L.TileGrid(layer)
	local tileW, tileH = layer.tileWidth * viewW / layer.layerWidth, layer.tileHeight * viewH / layer.layerHeight
	local n = 0
	for row = 1, rows do
		for col = 1, cols do
			n = n + 1
			local t = tiles[n]
			if not t then
				t = BM.canvas:CreateTexture(nil, "ARTWORK")
				tiles[n] = t
			end
			t:SetTexture(files[n], "CLAMP", "CLAMP", "TRILINEAR")
			t:SetSize(tileW, tileH)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", BM.canvas, "TOPLEFT", (col - 1) * tileW, -(row - 1) * tileH)
			t:Show()
		end
	end
	for i = n + 1, #tiles do tiles[i]:Hide() end
	RestoreView(mapID)
	BM.mapID, BM.loadedWidth = mapID, c.width
	if BM.gameLayer then BM.gameLayer:SetUiMapID(mapID) end
	return true
end

---------------------------------------------------------------------------
-- When it shows
---------------------------------------------------------------------------
function BM.Preview()
	return (BM.testMode or ns.unlocked) and true or false
end

function BM.InBlitz()
	local _, instanceType = IsInInstance()
	return instanceType == "pvp" and ns.CombatLog.MatchType() == "blitz"
end

function BM.Check()
	local f = BM.frame
	local c = cfg()
	local preview = BM.Preview()
	f.SUIActive = c.enabled and true or false
	local mapID
	if preview then
		mapID = TEST_MAP
	elseif c.enabled and BM.InBlitz() then
		mapID = C_Map.GetBestMapForUnit("player")
	end
	if not mapID then
		f:Hide()
		return
	end
	if mapID ~= BM.mapID or BM.loadedWidth ~= c.width then
		if not BM.LoadMap(mapID) then
			f:Hide()
			return
		end
		ApplyView()
	end
	BM.UpdateObjectives()
	f:Show()
end

BM.objectives = {}
function BM.UpdateObjectives()
	if cfg().nodes and BM.mapID and not BM.Preview() then
		BM.objectives = BM.ReadObjectives(BM.mapID)
	else
		BM.objectives = {}
	end
end

local accum, slow = 0, 0
local function OnUpdate(_, elapsed)
	if BM.panning then BM.UpdatePan() end
	accum, slow = accum + elapsed, slow + elapsed
	if accum < TICK then return end
	accum = 0
	-- Blitz can take a moment to report itself, and a map can have more than one level
	if slow >= 1 then
		slow = 0
		BM.Check()
	end
	if BM.frame:IsShown() and BM.mapID then Draw(BM.mapID) end
	BM.UpdateHover()
end

function BM.UpdateTicker()
	local _, instanceType = IsInInstance()
	BM.ticker:SetShown(BM.Preview() or (cfg().enabled and instanceType == "pvp"))
end

---------------------------------------------------------------------------
-- Moving and zooming
---------------------------------------------------------------------------
local function CursorInView()
	local f = BM.frame
	local s = f:GetEffectiveScale()
	local x, y = GetCursorPosition()
	return x / s - f:GetLeft(), f:GetTop() - y / s
end

function BM.OnWheel(delta)
	local newZoom = L.NextZoom(zoom, delta)
	if newZoom == zoom then return end
	local x, y = CursorInView()
	panX, panY = L.ZoomAt(zoom, newZoom, panX, panY, x, y, viewW, viewH)
	zoom = newZoom
	ApplyView()
	BM.SaveView()
end

function BM.UpdatePan()
	local x, y = CursorInView()
	local p = BM.panning
	panX, panY = L.ClampPan(p.panX + x - p.x, p.panY + y - p.y, zoom, viewW, viewH)
	ApplyView()
end

local function SavePosition()
	local f = BM.frame
	local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local x, y = f:GetCenter()
	local ux, uy = UIParent:GetCenter()
	cfg().point = { "CENTER", x - ux / s, y - uy / s }
	ns:ApplyPoint(f, cfg().point)
end

local function OnDragStart(self)
	if IsShiftKeyDown() then
		self:StartMoving()
		BM.moving = true
	else
		local x, y = CursorInView()
		BM.panning = { x = x, y = y, panX = panX, panY = panY }
	end
end

local function OnDragStop(self)
	if BM.panning then BM.SaveView() end
	BM.panning = nil
	if BM.moving then
		BM.moving = nil
		self:StopMovingOrSizing()
		SavePosition()
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function BM:SetTestMode(on)
	BM.testMode = on or nil
	BM:Refresh()
end

function BM:Init()
	local f = CreateFrame("Frame", "StinkieUI_BlitzMap", UIParent)
	BM.frame = f
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	f:RegisterForDrag("LeftButton", "RightButton")
	f:SetScript("OnDragStart", OnDragStart)
	f:SetScript("OnDragStop", OnDragStop)
	f:SetScript("OnHide", OnDragStop)
	f:SetScript("OnMouseWheel", function(_, delta) BM.OnWheel(delta) end)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0, 0, 0, 1)

	BM.view = CreateFrame("Frame", nil, f)
	BM.view:SetAllPoints()
	BM.view:SetClipsChildren(true)
	BM.canvas = CreateFrame("Frame", nil, BM.view)
	local ok, layer = pcall(CreateFrame, "UnitPositionFrame", nil, BM.canvas)
	if ok and layer then
		layer:SetAllPoints(BM.canvas)
		layer:EnableMouse(false)
		BM.gameLayer = layer
	end
	BM.pins = CreateFrame("Frame", nil, BM.view)
	BM.pins:SetAllPoints()
	BM.pins:SetFrameLevel(BM.view:GetFrameLevel() + 5)
	-- the game's dots stay on the canvas to zoom with the map, but draw over the bases (level +0
	-- on the pins) and under you and the flags (+3 and +5)
	if BM.gameLayer then BM.gameLayer:SetFrameLevel(BM.pins:GetFrameLevel() + 2) end

	-- names of the game-drawn dots under the mouse (not clipped by the view, so it's on the window)
	local hover = CreateFrame("Frame", nil, f)
	hover:SetSize(1, 1)
	hover:SetFrameStrata("TOOLTIP")
	hover.lines = {}
	for i = 1, BM.HOVER_LINES do
		local line = hover:CreateFontString(nil, "OVERLAY")
		ns.ApplyText(line, cfg().nameStyle)
		if i == 1 then
			line:SetPoint("BOTTOMLEFT", hover, "BOTTOMLEFT", 0, 0)
		else
			line:SetPoint("BOTTOMLEFT", hover.lines[i - 1], "TOPLEFT", 0, 1)
		end
		hover.lines[i] = line
	end
	hover:Hide()
	BM.hover = hover

	-- on its own frame: the clipped view would draw over a border on this one
	BM.edge = CreateFrame("Frame", nil, f)
	BM.edge:SetAllPoints()
	BM.edge:SetFrameLevel(BM.view:GetFrameLevel() + 20)
	ns.CreateBackdrop(BM.edge, 0)

	ns:RegisterMover("blitzMap", f, "Blitz Map",
		function() return cfg().point end,
		function(p) cfg().point = p end)
	BM.ticker = CreateFrame("Frame")
	BM.ticker:SetScript("OnUpdate", ns.Timed("Blitz Map", OnUpdate))
	BM.ticker:Hide()
	local function Enter()
		BM.UpdateTicker()
		BM.Check()
	end
	ns:On("PLAYER_ENTERING_WORLD", Enter)
	ns:On("ZONE_CHANGED_NEW_AREA", Enter)
	local function Changed()
		if BM.frame:IsShown() then BM.UpdateObjectives() end
	end
	ns:On("AREA_POIS_UPDATED", Changed)
	ns:On("VIGNETTES_UPDATED", Changed)
	table.insert(ns.lockCallbacks, function() BM:Refresh() end)
	f:Hide()
	BM:Refresh()
end

BM.styleRound = 0

function BM:Refresh()
	if not BM.frame then return end
	BM.styleRound = BM.styleRound + 1 -- name text picks up the options on the next draw
	if not BM.moving then ns:ApplyPoint(BM.frame, cfg().point) end
	if BM.Preview() then
		BM.frame:SetFrameStrata("HIGH")
	else
		BM.frame:SetFrameStrata("MEDIUM")
	end
	BM.UpdateTicker()
	BM.Check()
end

-- /stinkie map: what the game gives us, to see why something isn't on the map
function BM.Debug()
	local lines = {}
	local function add(line)
		print(line)
		lines[#lines + 1] = readable(line) and line or "  (hidden by the game)"
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	local layer = mapID and (C_Map.GetMapArtLayers(mapID) or {})[1]
	add(string.format("Blitz Map: map %s, in Blitz %s, art %s, showing %s", tostring(mapID), tostring(BM.InBlitz()),
		layer and (layer.layerWidth .. "x" .. layer.layerHeight) or "none", tostring(BM.frame:IsShown())))
	local function unitLine(unit)
		local pos = mapID and C_Map.GetPlayerMapPosition(mapID, unit)
		local text = "no position"
		if pos then
			text = readable(pos.x) and string.format("%.3f, %.3f", pos.x, pos.y) or "hidden"
		end
		add("  " .. unit .. ": " .. text)
	end
	add(string.format("  game dots: %s, %d now", BM.gameLayer and "ready" or "not available", #BM.gameDots))
	if C_PvP.GetBattlefieldVehicles and mapID then
		for i, info in ipairs(C_PvP.GetBattlefieldVehicles(mapID) or {}) do
			add(string.format("  vehicle %d: %s %s", i, tostring(info.atlas), tostring(info.isAlive)))
		end
	end
	unitLine("player")
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() or 0 do unitLine("raid" .. i) end
	else
		for i = 1, GetNumSubgroupMembers() or 0 do unitLine("party" .. i) end
	end
	for i = 1, mapID and GetNumBattlefieldFlagPositions() or 0 do
		local x, y, texture = C_PvP.GetBattlefieldFlagPosition(i, mapID)
		add(string.format("  marker %d: %s, %s  file %s", i, tostring(x), tostring(y), tostring(texture)))
	end
	for _, id in ipairs(mapID and C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}) do
		local p = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
		if p then
			add(string.format("  base %d: %s  atlas=%s  texture=%s", id, tostring(p.name), tostring(p.atlasName), tostring(p.textureIndex)))
		end
	end
	for _, guid in ipairs(mapID and C_VignetteInfo and C_VignetteInfo.GetVignettes() or {}) do
		local v = C_VignetteInfo.GetVignetteInfo(guid)
		if v then
			add(string.format("  vignette: %s  atlas=%s  on map=%s", tostring(v.name), tostring(v.atlasName), tostring(v.onWorldMap)))
		end
	end
	-- chat text can't be selected, so the report opens where it can be copied
	if ns.Chat and ns.Chat.ShowText then ns.Chat.ShowText("Blitz Map report", table.concat(lines, "\n")) end
end

ns:RegisterModule("BlitzMap", BM)
