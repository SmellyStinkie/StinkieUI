-- StinkieUI: in-game options panel (/stinkie). Flat, no libraries.
local _, ns = ...

local O = {}
ns.Options = O

local ACCENT = ns.ACCENT
local BRAND = ns.BRAND
local ROW = 30
local COL_W = 300
local needsReload = false

local function Font() return ns.GetFontPath() end
local ShowTextPopup -- defined further down, used by the General page
local ShowLink

---------------------------------------------------------------------------
-- Throttled refresh
---------------------------------------------------------------------------
local refreshQueued = false
local function QueueRefresh()
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0.05, function()
		refreshQueued = false
		ns:Refresh()
	end)
end

local function MarkReload()
	needsReload = true
	if O.reloadButton then O.reloadButton:Show() end
end

local function Changed(reload)
	if reload then MarkReload() else QueueRefresh() end
end

---------------------------------------------------------------------------
-- Flat widgets
---------------------------------------------------------------------------
local function Flat(frame, r, g, b, a, layer)
	local t = frame:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints()
	t:SetColorTexture(r, g, b, a)
	return t
end

local function Label(parent, text, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	ns.SetFont(fs, size or 13)
	fs:SetShadowOffset(1, -1)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	if color then fs:SetTextColor(unpack(color)) end
	return fs
end

local function FlatButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 120, 22)
	b.bg = Flat(b, 0.15, 0.13, 0.11, 1)
	ns.CreateBackdrop(b, 0)
	b.text = Label(b, text, 13)
	b.text:SetPoint("CENTER")
	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
	b.bar:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
	b.bar:Hide()
	local P, PD = BRAND.plum, BRAND.plumDark
	local function paint(self)
		if self.selected then
			self.bg:SetColorTexture(P[1], P[2], P[3], 1)
			self.text:SetTextColor(BRAND.cream[1], BRAND.cream[2], BRAND.cream[3])
		else
			self.bg:SetColorTexture(0.15, 0.13, 0.11, 1)
			self.text:SetTextColor(1, 1, 1)
		end
		self.bar:SetShown(self.selected and true or false)
	end
	b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(P[1] * 0.6, P[2] * 0.6, P[3] * 0.6, 1) end end)
	b:SetScript("OnLeave", paint)
	b:SetScript("OnClick", onClick)
	b.SetSelected = function(self, selected)
		self.selected = selected
		paint(self)
	end
	return b
end

local function EditBox(parent, width)
	local eb = CreateFrame("EditBox", nil, parent)
	eb:SetSize(width, 20)
	eb:SetAutoFocus(false)
	ns.SetFont(eb, 13)
	eb:SetJustifyH("CENTER")
	eb:SetTextInsets(4, 4, 0, 0)
	Flat(eb, 0.12, 0.11, 0.09, 1)
	ns.CreateBackdrop(eb, 0)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return eb
end

-- Shared popup list for dropdowns.
local popup
local function ShowPopup(owner, items, current, onPick)
	if not popup then
		popup = CreateFrame("Frame", nil, UIParent)
		popup:SetFrameStrata("FULLSCREEN_DIALOG")
		popup:EnableMouse(true)
		Flat(popup, 0.08, 0.07, 0.05, 0.98)
		ns.CreateBackdrop(popup, 0)
		popup.buttons = {}
		popup.offset = 0
		popup:EnableMouseWheel(true)
		popup:SetScript("OnMouseWheel", function(self, delta)
			self.offset = math.max(0, math.min(#self.items - #self.buttons, self.offset - delta))
			self:Render()
		end)
		function popup:Render()
			for i, b in ipairs(self.buttons) do
				local item = self.items[i + self.offset]
				if item then
					b.text:SetText(item[2])
					b.value = item[1]
					b:SetSelected(item[1] == self.current)
					b:Show()
				else
					b:Hide()
				end
			end
		end
	end
	local visible = math.min(#items, 14)
	for i = #popup.buttons + 1, visible do
		local b = FlatButton(popup, "", 200, function(self)
			popup.onPick(self.value)
			popup:Hide()
		end)
		b.text:ClearAllPoints()
		b.text:SetPoint("LEFT", 8, 0)
		popup.buttons[i] = b
	end
	for i, b in ipairs(popup.buttons) do
		b:SetWidth(owner:GetWidth() - 4)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 22)
		if i > visible then b:Hide() end
	end
	popup.items, popup.current, popup.onPick, popup.offset = items, current, onPick, 0
	popup:SetSize(owner:GetWidth(), visible * 22 + 4)
	popup:ClearAllPoints()
	popup:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	popup:Render()
	popup:Show()
end

---------------------------------------------------------------------------
-- Pages: widgets laid out top to bottom in two columns, inside a scroll frame
---------------------------------------------------------------------------
local PageMixin = {}

function PageMixin:Next(height)
	local col = self.col
	local y = self.y[col]
	self.y[col] = y - (height or ROW)
	self:SetHeight(math.max(self:GetHeight(), -self.y[col] + 20))
	return 16 + (col - 1) * COL_W, y
end

function PageMixin:Column(col)
	self.col = col
end

function PageMixin:Gap(h)
	self:Next(h or 8)
end

function PageMixin:Header(text)
	local x, y = self:Next(ROW)
	local fs = Label(self, text, 15, { ACCENT[1], ACCENT[2], ACCENT[3] })
	fs:SetPoint("TOPLEFT", x, y - 8)
	return fs
end

function PageMixin:Note(text, height)
	local x, y = self:Next(height or 22)
	local fs = Label(self, text, 12, { 0.70, 0.68, 0.60 })
	fs:SetPoint("TOPLEFT", x, y - 2)
	fs:SetWidth(COL_W - 24)
	fs:SetWordWrap(true)
	return fs
end

function PageMixin:Add(w)
	table.insert(self.widgets, w)
	return w
end

function PageMixin:Check(text, get, set, reload)
	local x, y = self:Next()
	local b = CreateFrame("Button", nil, self)
	b:SetSize(COL_W - 24, 20)
	b:SetPoint("TOPLEFT", x, y)
	local box = CreateFrame("Frame", nil, b)
	box:SetSize(14, 14)
	box:SetPoint("LEFT")
	Flat(box, 0.12, 0.11, 0.09, 1)
	ns.CreateBackdrop(box, 0)
	local fill = box:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 3, -3)
	fill:SetPoint("BOTTOMRIGHT", -3, 3)
	fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
	local fs = Label(b, text .. (reload and " |cff888888*|r" or ""), 13)
	fs:SetPoint("LEFT", box, "RIGHT", 8, 0)
	local function sync() fill:SetShown(get() and true or false) end
	b:SetScript("OnClick", function()
		set(not get())
		sync()
		Changed(reload)
	end)
	b.Sync = sync
	sync()
	return self:Add(b)
end

function PageMixin:Slider(text, min, max, step, get, set, reload)
	local x, y = self:Next(44)
	local holder = CreateFrame("Frame", nil, self)
	holder:SetSize(COL_W - 24, 40)
	holder:SetPoint("TOPLEFT", x, y)
	local fs = Label(holder, text .. (reload and " |cff888888*|r" or ""), 13)
	fs:SetPoint("TOPLEFT")

	local s = CreateFrame("Slider", nil, holder)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(200, 10)
	s:SetPoint("TOPLEFT", 0, -22)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	Flat(s, 0.12, 0.11, 0.09, 1)
	ns.CreateBackdrop(s, 0)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
	thumb:SetSize(8, 14)
	s:SetThumbTexture(thumb)

	local eb = EditBox(holder, 56)
	eb:SetPoint("LEFT", s, "RIGHT", 10, 0)

	local function fmt(v)
		if step < 1 then return string.format("%.2f", v) end
		return tostring(math.floor(v + 0.5))
	end
	local syncing = false
	local function sync()
		syncing = true
		s:SetValue(get())
		eb:SetText(fmt(get()))
		syncing = false
	end
	s:SetScript("OnValueChanged", function(_, v)
		if syncing then return end
		v = math.floor(v / step + 0.5) * step
		set(v)
		eb:SetText(fmt(v))
		Changed(reload)
	end)
	eb:SetScript("OnEnterPressed", function(self)
		local v = tonumber(self:GetText())
		if v then
			v = math.max(min, math.min(max, v))
			set(v)
			Changed(reload)
		end
		sync()
		self:ClearFocus()
	end)
	holder.Sync = sync
	sync()
	return self:Add(holder)
end

-- Segmented choice: options = { { value, label }, ... }
function PageMixin:Choice(text, options, get, set, reload)
	local x, y = self:Next(46)
	local holder = CreateFrame("Frame", nil, self)
	holder:SetSize(COL_W - 24, 42)
	holder:SetPoint("TOPLEFT", x, y)
	local fs = Label(holder, text .. (reload and " |cff888888*|r" or ""), 13)
	fs:SetPoint("TOPLEFT")
	local buttons = {}
	local bw = math.floor((COL_W - 28) / #options)
	local function sync()
		for _, b in ipairs(buttons) do b:SetSelected(b.value == get()) end
	end
	for i, opt in ipairs(options) do
		local b = FlatButton(holder, opt[2], bw - 2, function(self)
			set(self.value)
			sync()
			Changed(reload)
		end)
		b.value = opt[1]
		b:SetHeight(20)
		b:SetPoint("TOPLEFT", (i - 1) * bw, -20)
		buttons[i] = b
	end
	holder.Sync = sync
	sync()
	return self:Add(holder)
end

-- Dropdown: items = list of { value, label } or a function returning one.
function PageMixin:Dropdown(text, items, get, set, reload)
	local x, y = self:Next(48)
	local holder = CreateFrame("Frame", nil, self)
	holder:SetSize(COL_W - 24, 44)
	holder:SetPoint("TOPLEFT", x, y)
	Label(holder, text .. (reload and " |cff888888*|r" or ""), 13):SetPoint("TOPLEFT")
	local function list() return type(items) == "function" and items() or items end
	local btn
	btn = FlatButton(holder, "", 220, function()
		ShowPopup(btn, list(), get(), function(v)
			set(v)
			holder.Sync()
			Changed(reload)
		end)
	end)
	btn:SetPoint("TOPLEFT", 0, -20)
	btn.text:ClearAllPoints()
	btn.text:SetPoint("LEFT", 8, 0)
	local arrow = Label(btn, "v", 12, { 0.6, 0.6, 0.65 })
	arrow:SetPoint("RIGHT", -8, 0)
	holder.Sync = function()
		local cur = get()
		for _, it in ipairs(list()) do
			if it[1] == cur then btn.text:SetText(it[2]) return end
		end
		btn.text:SetText(tostring(cur))
	end
	holder.Sync()
	return self:Add(holder)
end

-- Color swatch. get/set use { r, g, b } tables.
function PageMixin:Color(text, get, set)
	local x, y = self:Next(28)
	local b = CreateFrame("Button", nil, self)
	b:SetSize(COL_W - 24, 20)
	b:SetPoint("TOPLEFT", x, y)
	local sw = CreateFrame("Frame", nil, b)
	sw:SetSize(30, 16)
	sw:SetPoint("LEFT")
	ns.CreateBackdrop(sw, 0)
	local tex = Flat(sw, 1, 1, 1, 1, "ARTWORK")
	Label(b, text, 13):SetPoint("LEFT", sw, "RIGHT", 8, 0)
	local function sync()
		local c = get()
		tex:SetColorTexture(c[1], c[2], c[3], 1)
	end
	b:SetScript("OnClick", function()
		local c = get()
		local function apply()
			local r, g, bl = ColorPickerFrame:GetColorRGB()
			set({ r, g, bl })
			sync()
			QueueRefresh()
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = c[1], g = c[2], b = c[3],
			swatchFunc = apply,
			cancelFunc = function()
				local r, g, bl = ColorPickerFrame:GetPreviousValues()
				set({ r, g, bl })
				sync()
				QueueRefresh()
			end,
		})
	end)
	b.Sync = sync
	sync()
	return self:Add(b)
end

-- Text style block: size, outline, color, optional class color.
function PageMixin:TextStyle(title, getStyle, opts)
	opts = opts or {}
	self:Header(title)
	self:Slider("Size", 6, 32, 1, function() return getStyle().size end, function(v) getStyle().size = v end)
	self:Choice("Outline", { { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICKOUTLINE", "Thick" } },
		function() return getStyle().outline end, function(v) getStyle().outline = v end)
	self:Color("Color", function() return getStyle().color end, function(c) getStyle().color = c end)
	if opts.classColor then
		self:Check("Use class color instead", function() return getStyle().classColor end, function(v) getStyle().classColor = v end)
	end
end

-- Position block for a mover: anchor, X, Y with nudge buttons.
local anchorItems = {}
for _, a in ipairs(ns.ANCHORS) do table.insert(anchorItems, { a, a:sub(1, 1) .. a:sub(2):lower() }) end

function PageMixin:Position(title, getKey, note)
	self:Header(title or "Position")
	if note then self:Note(note, 22) end
	local function mover() return ns.movers[getKey()] end
	self:Dropdown("Anchor to screen", anchorItems,
		function() local m = mover() return m and m.getPoint()[1] or "CENTER" end,
		function(v) if mover() then ns:SetMoverAnchor(getKey(), v) end end)

	for idx, axis in ipairs({ "X", "Y" }) do
		local x, y = self:Next(28)
		local holder = CreateFrame("Frame", nil, self)
		holder:SetSize(COL_W - 24, 24)
		holder:SetPoint("TOPLEFT", x, y)
		Label(holder, axis, 13):SetPoint("LEFT")
		local eb = EditBox(holder, 64)
		eb:SetPoint("LEFT", 22, 0)
		local function sync()
			local m = mover()
			if not eb:HasFocus() then eb:SetText(m and m.getPoint()[idx + 1] or "") end
		end
		eb:SetScript("OnEnterPressed", function(self)
			local m, v = mover(), tonumber(self:GetText())
			if m and v then
				local p = m.getPoint()
				local np = { p[1], p[2], p[3] }
				np[idx + 1] = math.floor(v + 0.5)
				ns:SetMoverPoint(getKey(), np)
			end
			self:ClearFocus()
			sync()
		end)
		local prev = eb
		for _, step in ipairs({ -10, -1, 1, 10 }) do
			local b = FlatButton(holder, (step > 0 and "+" or "") .. step, 36, function()
				if mover() then
					ns:NudgeMover(getKey(), idx == 1 and step or 0, idx == 2 and step or 0)
					sync()
				end
			end)
			b:SetHeight(20)
			b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
			prev = b
		end
		holder.Sync = sync
		self:Add(holder)
	end
end

-- Read-only text box for links (WoW can't open URLs, so the text is selected for copying).
function PageMixin:CopyBox(label, text)
	local x, y = self:Next(28)
	local holder = CreateFrame("Frame", nil, self)
	holder:SetSize(COL_W - 24, 22)
	holder:SetPoint("TOPLEFT", x, y)
	Label(holder, label, 13):SetPoint("LEFT")
	local eb = EditBox(holder, COL_W - 100)
	eb:SetPoint("LEFT", 64, 0)
	eb:SetJustifyH("LEFT")
	eb:SetText(text)
	eb:SetCursorPosition(0)
	eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(text) self:HighlightText() end end)
	eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	eb:SetScript("OnMouseUp", function(self) self:SetFocus() self:HighlightText() end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return holder
end

-- Single-line text setting, saved on Enter or when focus leaves.
function PageMixin:EditText(text, get, set)
	local x, y = self:Next(46)
	local holder = CreateFrame("Frame", nil, self)
	holder:SetSize(COL_W - 24, 42)
	holder:SetPoint("TOPLEFT", x, y)
	Label(holder, text, 13):SetPoint("TOPLEFT")
	local eb = EditBox(holder, COL_W - 40)
	eb:SetPoint("TOPLEFT", 0, -18)
	eb:SetJustifyH("LEFT")
	local function commit(self)
		set(self:GetText())
		QueueRefresh()
	end
	eb:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
	eb:SetScript("OnEditFocusLost", commit)
	holder.Sync = function() eb:SetText(get() or "") end
	holder.Sync()
	return self:Add(holder)
end

-- Multi-line list editor: one entry per line. apply(text) runs on Save.
function PageMixin:TextList(title, height, getText, apply, note)
	self:Header(title)
	if note then self:Note(note, 36) end
	local x, y = self:Next(height + 34)
	local holder = CreateFrame("Frame", nil, self)
	holder:SetSize(COL_W - 24, height + 30)
	holder:SetPoint("TOPLEFT", x, y)
	local sf = CreateFrame("ScrollFrame", nil, holder)
	sf:SetPoint("TOPLEFT")
	sf:SetSize(COL_W - 24, height)
	Flat(sf, 0.12, 0.11, 0.09, 1)
	ns.CreateBackdrop(sf, 0)
	local eb = CreateFrame("EditBox", nil, sf)
	eb:SetMultiLine(true)
	eb:SetAutoFocus(false)
	ns.SetFont(eb, 12)
	eb:SetWidth(COL_W - 30)
	eb:SetTextInsets(4, 4, 4, 4)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	sf:SetScrollChild(eb)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, d)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - d * 20)))
	end)
	sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
	local save = FlatButton(holder, "Save list", 100, function()
		eb:ClearFocus()
		apply(eb:GetText())
		holder.Sync()
		QueueRefresh()
	end)
	save:SetHeight(20)
	save:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", 0, -6)
	holder.Sync = function() if not eb:HasFocus() then eb:SetText(getText()) end end
	holder.Sync()
	return self:Add(holder)
end

local function SplitLines(text)
	local out = {}
	for line in (text or ""):gmatch("[^\r\n,]+") do
		line = strtrim(line)
		if line ~= "" then table.insert(out, line) end
	end
	return out
end

-- spell list <-> text ("12345  Spell Name" per line). Names are looked up when possible.
local function SpellListText(list)
	local lines = {}
	for _, id in ipairs(list) do
		local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
		table.insert(lines, name and (id .. "  " .. name) or tostring(id))
	end
	return table.concat(lines, "\n")
end

local function ParseSpellList(text)
	local out, seen = {}, {}
	for _, line in ipairs(SplitLines(text)) do
		local id = tonumber(line:match("^(%d+)"))
		if not id then
			local info = C_Spell.GetSpellInfo(line)
			id = info and info.spellID
			if not id then ns:Print("Unknown spell: " .. line .. " (use the spell ID)") end
		end
		if id and not seen[id] then seen[id] = true; table.insert(out, id) end
	end
	return out
end

local function NewPage(scroll)
	local page = CreateFrame("Frame", nil, scroll)
	Mixin(page, PageMixin)
	page:SetSize(640, 10)
	page.y = { -10, -10 }
	page.col = 1
	page.widgets = {}
	page:Hide()
	function page:SyncAll()
		for _, w in ipairs(self.widgets) do if w.Sync then w.Sync() end end
		if self.OnShowPage then self:OnShowPage() end
	end
	page:SetScript("OnShow", page.SyncAll)
	return page
end

---------------------------------------------------------------------------
-- Page builders
---------------------------------------------------------------------------
local healthTextChoices = { { "none", "None" }, { "percent", "%" }, { "current", "HP" }, { "both", "Both" } }

local function Getter(t, k) return function() return t()[k] end end
local function Setter(t, k) return function(v) t()[k] = v end end

local function BuildUnitPage(page, unit)
	local function cfg() return ns.db.units[unit] end
	page:Column(1)
	page:Header(ns.UF.unitLabels[unit])
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Slider("Width", 40, 400, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Health height", 4, 80, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Check("Show power bar", Getter(cfg, "showPower"), Setter(cfg, "showPower"))
	page:Slider("Power height", 1, 30, 1, Getter(cfg, "powerHeight"), Setter(cfg, "powerHeight"))
	page:Check("Shields (absorbs and overshield)", function() return cfg().shields ~= false end, Setter(cfg, "shields"))
	if unit == "target" or unit == "focus" then
		page:Check("Elite / boss star (gold; silver for rares)", Getter(cfg, "eliteIcon"), Setter(cfg, "eliteIcon"))
		page:Slider("Star size", 8, 40, 1, Getter(cfg, "eliteSize"), Setter(cfg, "eliteSize"))
		page:Dropdown("Star corner", { { "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" }, { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" } },
			Getter(cfg, "eliteCorner"), Setter(cfg, "eliteCorner"))
	end
	page:Position(nil, function() return unit end)
	if ns.db.units[unit].auras then
		local function acfg() return ns.db.units[unit].auras end
		page:Header("Auras")
		page:Note("Your debuffs, crowd control and major defensives.")
		page:Check("Auras (master switch)", Getter(acfg, "enabled"), Setter(acfg, "enabled"), true)
		page:Slider("Icon size", 12, 48, 1, Getter(acfg, "size"), Setter(acfg, "size"), true)
		page:Slider("Max own debuffs", 0, 16, 1, Getter(acfg, "max"), Setter(acfg, "max"))
		page:Choice("Position", { { "BELOW", "Below" }, { "ABOVE", "Above" } }, Getter(acfg, "position"), Setter(acfg, "position"))
		page:Check("Small aura icons (debuffs, CC, defensives)", Getter(acfg, "showSmall"), Setter(acfg, "showSmall"))
		page:Check("Big crowd-control icon beside the frame", Getter(acfg, "ccIcon"), Setter(acfg, "ccIcon"))
		page:Choice("CC icon side", { { "LEFT", "Left" }, { "RIGHT", "Right" } }, Getter(acfg, "ccIconSide"), Setter(acfg, "ccIconSide"))
		page:Slider("CC icon size (0 = frame height)", 0, 80, 1, Getter(acfg, "ccIconSize"), Setter(acfg, "ccIconSize"), true)
		page:Note("Below sits under the castbar when it's attached, otherwise under the frame.", 36)
	end
	if unit == "targettarget" then
		page:Note("Blizzard blocks addons from target-of-target inside arenas and battlegrounds, so this frame stays blank there.", 48)
	end

	page:Column(2)
	page:Header("Text")
	page:Check("Show name", Getter(cfg, "showName"), Setter(cfg, "showName"))
	page:Check("Name above frame", Getter(cfg, "nameAbove"), Setter(cfg, "nameAbove"))
	page:Choice("Health text", healthTextChoices, Getter(cfg, "healthText"), Setter(cfg, "healthText"))
	page:TextStyle("Name text", function() return cfg().nameStyle end, { classColor = true })
	page:TextStyle("Health text", function() return cfg().healthStyle end)
end

local function BuildCastbarPage(page)
	page.unit = "player"
	local function cfg() return ns.db.units[page.unit].castbar end
	page:Column(1)
	page:Header("Castbars")
	page:Choice("Editing", { { "player", "Player" }, { "target", "Target" }, { "focus", "Focus" } },
		function() return page.unit end,
		function(v) page.unit = v; page:SyncAll() end)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Check("Attach to unit frame", Getter(cfg, "attached"), Setter(cfg, "attached"))
	page:Slider("Width (floating)", 60, 500, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Height", 6, 40, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Check("Spell name", Getter(cfg, "showText"), Setter(cfg, "showText"))
	page:Check("Cast time", Getter(cfg, "showTime"), Setter(cfg, "showTime"))
	page:Position("Position (floating)", function() return page.unit .. "Castbar" end)
	page:Column(2)
	page:TextStyle("Castbar text", function() return cfg().textStyle end)
	page:Header("Colors (all castbars)")
	local colors = function() return ns.db.colors end
	page:Color("Interruptible", Getter(colors, "castInterruptible"), Setter(colors, "castInterruptible"))
	page:Color("Can't be interrupted", Getter(colors, "castNotInterruptible"), Setter(colors, "castNotInterruptible"))
	page:Color("Interrupted / failed", Getter(colors, "castFailed"), Setter(colors, "castFailed"))
end

local function BuildPartyPage(page)
	local function cfg() return ns.db.party end
	local function ccfg() return ns.db.party.castbar end
	page:Column(1)
	page:Header("Party frames")
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Button("Test mode on / off", function() if ns.Party.SetTestMode then ns.Party:SetTestMode(not ns.Party.testMode) end end)
	page:Check("Include me", Getter(cfg, "showPlayer"), Setter(cfg, "showPlayer"), true)
	page:Slider("Width", 60, 400, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Height", 12, 80, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Slider("Spacing", 0, 60, 1, Getter(cfg, "spacing"), Setter(cfg, "spacing"))
	page:Choice("Grow", { { "DOWN", "Down" }, { "UP", "Up" } }, Getter(cfg, "growth"), Setter(cfg, "growth"))
	page:Header("Power")
	page:Choice("Show power", { { "all", "All" }, { "healer", "Healers" }, { "none", "None" } }, Getter(cfg, "power"), Setter(cfg, "power"))
	page:Slider("Power height", 1, 20, 1, Getter(cfg, "powerHeight"), Setter(cfg, "powerHeight"))
	page:Header("Icons")
	page:Choice("Trinket side", { { "LEFT", "Left" }, { "RIGHT", "Right" } }, Getter(cfg, "trinketSide"), Setter(cfg, "trinketSide"))
	page:Note("Defensives sit beyond the trinket; crowd control sits on the other side.", 36)
	page:Check("Crowd control icons", Getter(cfg, "ccIcon"), Setter(cfg, "ccIcon"))
	page:Slider("Crowd control size (0 = frame height)", 0, 80, 1, Getter(cfg, "ccSize"), Setter(cfg, "ccSize"), true)
	page:Slider("Crowd control icons at once", 1, 3, 1, Getter(cfg, "ccMax"), Setter(cfg, "ccMax"), true)
	page:Check("Defensive icons", Getter(cfg, "defensiveIcon"), Setter(cfg, "defensiveIcon"))
	page:Check("Debuffs (dispellable)", Getter(cfg, "dispelIcons"), Setter(cfg, "dispelIcons"))
	page:Note("Turning debuffs off keeps the crowd control icons.", 22)
	page:Choice("Dispellable debuffs go", { { "BELOW", "Below" }, { "SIDE", "After CC" } }, Getter(cfg, "dispelPosition"), Setter(cfg, "dispelPosition"), true)
	page:Check("Fade when out of range", Getter(cfg, "rangeFade"), Setter(cfg, "rangeFade"))
	page:Check("Green cross on healers", Getter(cfg, "healerIcon"), Setter(cfg, "healerIcon"))
	page:Slider("Healer cross size", 6, 100, 1, Getter(cfg, "healerSize"), Setter(cfg, "healerSize"))
	page:Check("Castbars", Getter(ccfg, "enabled"), Setter(ccfg, "enabled"), true)
	page:Note("Test mode shows looping casts on enabled castbars.", 22)
	page:Slider("Castbar height", 4, 30, 1, Getter(ccfg, "height"), Setter(ccfg, "height"))
	page:Check("PvP trinket in arena", Getter(cfg, "trinket"), Setter(cfg, "trinket"))
	page:Slider("Trinket size (0 = frame height)", 0, 80, 1, Getter(cfg, "trinketSize"), Setter(cfg, "trinketSize"))
	page:Note("Glow options for these icons are on the PvP Assist page.", 22)
	page:Check("Hide in battlegrounds and Blitz", Getter(cfg, "hideInBattlegrounds"), Setter(cfg, "hideInBattlegrounds"))
	page:Note("Big and external defensives show while they're active.", 22)
	page:Position(nil, function() return "party" end)

	page:Column(2)
	page:Header("Text")
	page:Choice("Health text", healthTextChoices, Getter(cfg, "healthText"), Setter(cfg, "healthText"))
	page:TextStyle("Name text", function() return cfg().nameStyle end, { classColor = true })
	page:TextStyle("Health text", function() return cfg().healthStyle end)
	page:TextStyle("Castbar text", function() return ccfg().textStyle end)
end

local glowChoices = { { "none", "Off" }, { "static", "On" }, { "pulse", "Pulse" } }
local function GlowOptions(page, cfg, prefix, label)
	page:Choice(label or "Glow", glowChoices, Getter(cfg, prefix .. "Glow"), Setter(cfg, prefix .. "Glow"))
	page:Color("Glow color", Getter(cfg, prefix .. "GlowColor"), Setter(cfg, prefix .. "GlowColor"))
	page:Slider("Glow thickness", 1, 6, 1, Getter(cfg, prefix .. "GlowThickness"), Setter(cfg, prefix .. "GlowThickness"))
end
local whereChoices = { { "arena", "Arena" }, { "pvp", "Arena + BGs" }, { "always", "Always" } }

local function BuildArenaAssistPage(page)
	local function cfg() return ns.db.arenaAssist end
	page:Column(1)
	page:Header("PvP Assist")
	page:Button("Test mode on / off", function()
		local AA = ns.ArenaAssist
		AA:SetTestMode(not AA.testMode)
		if ns.Party.SetTestMode then ns.Party:SetTestMode(AA.testMode, "arena") end
	end)
	page:Slider("Countdown text size", 0.5, 2.5, 0.05, Getter(cfg, "countdownScale"), Setter(cfg, "countdownScale"))
	page:Note("Timer numbers on party CC, trinkets, the healer warning, Precognition, kicks and Big Debuffs.", 36)
	page:Header("Healer in CC")
	page:Check("Warn when your healer is crowd controlled", Getter(cfg, "healerCC"), Setter(cfg, "healerCC"))
	page:Choice("Where", whereChoices, Getter(cfg, "healerWhere"), Setter(cfg, "healerWhere"))
	page:EditText("Warning text", Getter(cfg, "healerText"), Setter(cfg, "healerText"))
	page:Check("Show the CC icon", Getter(cfg, "healerIcons"), Setter(cfg, "healerIcons"))
	page:Slider("Icon size", 16, 120, 1, Getter(cfg, "healerIconSize"), Setter(cfg, "healerIconSize"))
	page:Check("Play a sound", Getter(cfg, "healerSound"), Setter(cfg, "healerSound"))
	GlowOptions(page, cfg, "healer")
	page:Position(nil, function() return "healerCC" end)
	page:Header("Party frame icons")
	page:Check("Blue glow when the CC is Magic (Singe Magic can remove it)", Getter(cfg, "magicGlow"), Setter(cfg, "magicGlow"))
	page:Note("Party CC icons and the healer warning. Takes effect after /reload.", 22)
	GlowOptions(page, cfg, "cc", "Crowd control glow")
	GlowOptions(page, cfg, "trinket", "Trinket glow")

	page:Header("Big Debuffs (enemy nameplates)")
	page:Check("Show big icons right of enemy nameplates", Getter(cfg, "bigAuras"), Setter(cfg, "bigAuras"))
	page:Choice("Where", whereChoices, Getter(cfg, "bigWhere"), Setter(cfg, "bigWhere"))
	page:Check("Crowd control (Fear, Mortal Coil, stuns...)", Getter(cfg, "bigCC"), Setter(cfg, "bigCC"))
	page:Slider("Crowd control icons", 1, 4, 1, Getter(cfg, "bigCCMax"), Setter(cfg, "bigCCMax"))
	page:Check("Major defensives (own and external)", Getter(cfg, "bigDef"), Setter(cfg, "bigDef"))
	page:Slider("Defensive icons (each kind)", 1, 3, 1, Getter(cfg, "bigDefMax"), Setter(cfg, "bigDefMax"))
	page:Check("Major offensive cooldowns", Getter(cfg, "bigOff"), Setter(cfg, "bigOff"))
	page:Slider("Offensive icons", 1, 4, 1, Getter(cfg, "bigOffMax"), Setter(cfg, "bigOffMax"))
	page:Note("Offensive = the buffs Blizzard flags as important for enemy nameplates.", 22)
	page:Choice("Crowd control side", { { "LEFT", "Left" }, { "RIGHT", "Right" } }, Getter(cfg, "bigCCSide"), Setter(cfg, "bigCCSide"))
	page:Choice("Defensives / offensives side", { { "LEFT", "Left" }, { "RIGHT", "Right" } }, Getter(cfg, "bigBuffSide"), Setter(cfg, "bigBuffSide"))
	page:Note("On the same side, crowd control sits next to the bar.", 22)
	page:Slider("Icon size", 16, 100, 1, Getter(cfg, "bigSize"), Setter(cfg, "bigSize"))
	page:Slider("Gap from the bar", -50, 100, 1, Getter(cfg, "bigX"), Setter(cfg, "bigX"))
	page:Slider("Y offset", -50, 50, 1, Getter(cfg, "bigY"), Setter(cfg, "bigY"))
	page:Check("Don't repeat them in the small aura row", Getter(cfg, "bigHideSmall"), Setter(cfg, "bigHideSmall"))
	GlowOptions(page, cfg, "big", "Big Debuffs glow")
	page:Note("Size and glow changes made during a match apply once it ends (Blizzard locks aura icons while auras are hidden).", 36)

	page:Column(2)
	page:TextStyle("Warning text style", function() return cfg().healerTextStyle end)
	page:Header("Precognition")
	page:Check("Show Precognition on you", Getter(cfg, "precog"), Setter(cfg, "precog"))
	page:Choice("Where", whereChoices, Getter(cfg, "precogWhere"), Setter(cfg, "precogWhere"))
	page:Slider("Icon size", 16, 120, 1, Getter(cfg, "precogSize"), Setter(cfg, "precogSize"))
	GlowOptions(page, cfg, "precog")
	page:TextList("Buffs to show", 60, function() return table.concat(cfg().precogSpells, "\n") end, function(text)
		local list = {}
		for line in text:gmatch("[^\n]+") do
			line = strtrim(line)
			if line ~= "" then table.insert(list, line) end
		end
		cfg().precogSpells = list
	end, "One spell ID per line (a name after the ID is fine).")
	page:Position(nil, function() return "precog" end)
	page:Header("Enemy kicks")
	page:Check("Track enemy interrupts in arena", Getter(cfg, "kicks"), Setter(cfg, "kicks"))
	page:Note("Shows who interrupted you or a teammate. The timer is exact for kicks on you (by class) and an estimate (15 sec) for kicks on teammates. Kicks that don't hit a cast can't be seen.", 76)
	page:Slider("Icon size", 16, 80, 1, Getter(cfg, "kickSize"), Setter(cfg, "kickSize"))
	page:Slider("Icons at once", 1, 6, 1, Getter(cfg, "kickMax"), Setter(cfg, "kickMax"))
	page:Choice("Grow", { { "RIGHT", "Right" }, { "LEFT", "Left" } }, Getter(cfg, "kickGrowth"), Setter(cfg, "kickGrowth"))
	page:Check("Kicker's name", Getter(cfg, "kickNames"), Setter(cfg, "kickNames"))
	page:TextStyle("Name text", function() return cfg().kickNameStyle end)
	GlowOptions(page, cfg, "kick")
	page:Position(nil, function() return "enemyKicks" end)
end

local function BuildMinimapPage(page)
	local function cfg() return ns.db.minimap end
	page:Column(1)
	page:Header("Minimap")
	page:Check("Restyle the minimap", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Note("Position and size stay in Edit Mode.", 22)
	page:Choice("Shape", { { "ROUND", "Round" }, { "SQUARE", "Square" } }, Getter(cfg, "shape"), Setter(cfg, "shape"))
	page:Check("Border", Getter(cfg, "border"), Setter(cfg, "border"))
	page:Color("Border color (square)", Getter(cfg, "borderColor"), Setter(cfg, "borderColor"))
	page:Slider("Border thickness (square)", 1, 6, 1, Getter(cfg, "borderSize"), Setter(cfg, "borderSize"))
	page:Check("Hide the bar behind the zone name", Getter(cfg, "hideHeaderArt"), Setter(cfg, "hideHeaderArt"))
	page:Slider("Gap above the map (square)", 0, 20, 1, Getter(cfg, "headerGap"), Setter(cfg, "headerGap"))
	page:Dropdown("Mail icon (square)", { { "TOPRIGHT", "Top right corner" }, { "TOPLEFT", "Top left corner" },
		{ "BOTTOMRIGHT", "Bottom right corner" }, { "BOTTOMLEFT", "Bottom left corner" }, { "DEFAULT", "Blizzard's spot" } },
		Getter(cfg, "mailCorner"), Setter(cfg, "mailCorner"))
	page:Check("Omnium Folio button", Getter(cfg, "folio"), Setter(cfg, "folio"))
	page:Dropdown("Omnium Folio corner (square)", { { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" },
		{ "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" } }, Getter(cfg, "folioCorner"), Setter(cfg, "folioCorner"))
	page:Slider("Omnium Folio size", 0.4, 1.2, 0.05, Getter(cfg, "folioScale"), Setter(cfg, "folioScale"))
	page:Slider("Omnium Folio distance from corner", 0, 40, 1, Getter(cfg, "folioInset"), Setter(cfg, "folioInset"))
	page:Slider("Omnium Folio X nudge", -30, 30, 1, Getter(cfg, "folioX"), Setter(cfg, "folioX"))
	page:Slider("Omnium Folio Y nudge", -30, 30, 1, Getter(cfg, "folioY"), Setter(cfg, "folioY"))
	page:Choice("Buttons", { { "show", "Show" }, { "mouseover", "Mouseover" }, { "hide", "Hide" } }, Getter(cfg, "buttons"), Setter(cfg, "buttons"))
	page:Note("Tracking, addon list, zoom and addon minimap buttons. Mail and the Omnium Folio have their own options.", 36)
	page:Check("Calendar button", Getter(cfg, "calendar"), Setter(cfg, "calendar"))
	page:Slider("Calendar size", 0.5, 2, 0.05, Getter(cfg, "calendarScale"), Setter(cfg, "calendarScale"))
	page:Header("Hide automatically in")
	page:Check("Arena", Getter(cfg, "hideArena"), Setter(cfg, "hideArena"))
	page:Check("Battlegrounds", Getter(cfg, "hidePvP"), Setter(cfg, "hidePvP"))
	page:Check("Mythic+", Getter(cfg, "hideMPlus"), Setter(cfg, "hideMPlus"))
	page:Check("Raids", Getter(cfg, "hideRaid"), Setter(cfg, "hideRaid"))
	page:Column(2)
	page:Header("Text")
	page:Check("Zone name", Getter(cfg, "zoneText"), Setter(cfg, "zoneText"))
	page:TextStyle("Zone name", function() return cfg().zoneStyle end)
	page:Check("Clock", Getter(cfg, "clock"), Setter(cfg, "clock"))
	page:TextStyle("Clock", function() return cfg().clockStyle end)
	page:Header("Coordinates")
	page:Check("Show coordinates", function()
		if cfg().coords ~= nil then return cfg().coords end
		return GetCVarBool and GetCVarBool("minimapShowPlayerCoords") or false
	end, Setter(cfg, "coords"))
	page:Choice("Place", { { "BOTTOM", "Bottom" }, { "TOP", "Top" }, { "BELOW", "Below" }, { "ABOVE", "Above" } },
		Getter(cfg, "coordPosition"), Setter(cfg, "coordPosition"))
	page:Slider("X offset", -100, 100, 1, Getter(cfg, "coordX"), Setter(cfg, "coordX"))
	page:Slider("Y offset", -100, 100, 1, Getter(cfg, "coordY"), Setter(cfg, "coordY"))
	page:TextStyle("Coordinates", function() return cfg().coordStyle end)
end

local function BuildNameplatePage(page)
	local function cfg() return ns.db.nameplates end
	local function hcfg() return ns.db.nameplates.highlight end
	page:Column(1)
	page:Header("Enemy nameplates")
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Slider("Width", 40, 300, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Health height", 2, 40, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Slider("Castbar height", 4, 30, 1, Getter(cfg, "castHeight"), Setter(cfg, "castHeight"))
	page:Check("Show level", Getter(cfg, "showLevel"), Setter(cfg, "showLevel"))
	page:Check("Name inside the bar", Getter(cfg, "nameInBar"), Setter(cfg, "nameInBar"))
	page:Check("Health percent", Getter(cfg, "showHealthText"), Setter(cfg, "showHealthText"))
	page:Header("Target highlight")
	page:Slider("Border thickness", 1, 6, 1, Getter(hcfg, "thickness"), Setter(hcfg, "thickness"))
	page:Slider("Border outside the bar", 0, 6, 1, Getter(hcfg, "outset"), Setter(hcfg, "outset"))
	page:Color("Border color", Getter(hcfg, "color"), Setter(hcfg, "color"))
	page:Check("Show > < around the target", Getter(hcfg, "arrows"), Setter(hcfg, "arrows"))
	page:Slider("Arrow size", 8, 80, 1, Getter(hcfg, "arrowSize"), Setter(hcfg, "arrowSize"))
	page:Slider("Target plate scale", 1, 1.6, 0.05, function() return hcfg().scale or 1 end, Setter(hcfg, "scale"))
	page:Header("Stacking (plates pushing each other up)")
	local function scfg() return ns.db.nameplates.stacking end
	page:Check("Stack enemy nameplates", Getter(scfg, "enemies"), Setter(scfg, "enemies"))
	page:Check("Stack friendly nameplates", Getter(scfg, "friendly"), Setter(scfg, "friendly"))
	page:Note("Off: plates stay over their units and may overlap. On: they move apart, upward.", 36)
	page:Slider("Stacking box height (0 = auto)", 0, 80, 1, Getter(scfg, "boxHeight"), Setter(scfg, "boxHeight"))
	page:Note("How much room each plate claims. Lower = stacked plates climb less but sit closer (castbars and auras may overlap). Auto = bar + castbar + 24.", 48)
	page:Slider("Vertical spacing (0 = game default)", 0, 2, 0.05, Getter(scfg, "spacing"), Setter(scfg, "spacing"))
	page:Slider("Slide speed (0 = game default)", 0, 0.2, 0.005, Getter(scfg, "speed"), Setter(scfg, "speed"))
	page:Slider("Distance kept from screen top (0 = default)", 0, 0.5, 0.01, Getter(scfg, "topInset"), Setter(scfg, "topInset"))
	page:Note("These three are older game settings that may no longer exist; /stinkie plates shows which ones this game version has.", 36)
	page:Header("Clicking")
	page:Slider("Extra click area, sides", 0, 30, 1, Getter(cfg, "clickPadX"), Setter(cfg, "clickPadX"))
	page:Slider("Extra click area, top/bottom", 0, 20, 1, Getter(cfg, "clickPadY"), Setter(cfg, "clickPadY"))
	page:Header("Friendly nameplates")
	page:Slider("Width", 10, 200, 1, Getter(cfg, "friendlyWidth"), Setter(cfg, "friendlyWidth"))
	page:Slider("Health height", 1, 20, 1, Getter(cfg, "friendlyHeight"), Setter(cfg, "friendlyHeight"))
	page:Check("Click-through", Getter(cfg, "friendlyClickThrough"), Setter(cfg, "friendlyClickThrough"))
	page:Check("Name on the health bar", Getter(cfg, "friendlyNameInBar"), Setter(cfg, "friendlyNameInBar"))
	page:Header("Names (all nameplates)")
	page:Slider("Max name length (0 = full)", 0, 40, 1, Getter(cfg, "nameMaxChars"), Setter(cfg, "nameMaxChars"))
	page:Check("Add … when shortened", Getter(cfg, "nameEllipsis"), Setter(cfg, "nameEllipsis"))
	page:Header("Healers and elites")
	page:Check("Green cross over friendly healers", Getter(cfg, "healerIcon"), Setter(cfg, "healerIcon"))
	page:Check("Red cross over enemy healers", Getter(cfg, "enemyHealerIcon"), Setter(cfg, "enemyHealerIcon"))
	page:Slider("Cross size", 6, 100, 1, Getter(cfg, "healerSize"), Setter(cfg, "healerSize"))
	page:Check("Inspect nearby players to find healers", Getter(cfg, "inspectHealers"), Setter(cfg, "inspectHealers"))
	page:Note("Outside a group the game doesn't say who is a healer, so Stinkie UI inspects nearby players one at a time (out of combat, not in arena or battlegrounds).", 62)
	page:Check("Elite / boss star", Getter(cfg, "eliteIcon"), Setter(cfg, "eliteIcon"))
	page:Slider("Star size", 8, 30, 1, Getter(cfg, "eliteSize"), Setter(cfg, "eliteSize"))
	page:Check("Spec icon above enemy players", Getter(cfg, "specIcons"), Setter(cfg, "specIcons"))
	page:Check("Spec icon above friendly players", Getter(cfg, "specIconsFriendly"), Setter(cfg, "specIconsFriendly"))
	page:Slider("Spec icon size", 10, 60, 1, Getter(cfg, "specIconSize"), Setter(cfg, "specIconSize"))
	page:Dropdown("Spec icon position", { { "LEFT", "Left of the healer cross" }, { "RIGHT", "Right of the healer cross" },
		{ "CENTER", "Centered, cross to the right" }, { "ABOVE", "Centered, cross above" } },
		Getter(cfg, "specAnchor"), Setter(cfg, "specAnchor"))
	page:Slider("Spec icon X offset", -60, 60, 1, Getter(cfg, "specX"), Setter(cfg, "specX"))
	page:Slider("Spec icon Y offset", -30, 60, 1, Getter(cfg, "specY"), Setter(cfg, "specY"))
	page:Note("Spec comes from Blizzard's arena helper in arena, the scoreboard in battlegrounds, and a quiet inspect elsewhere (out of combat).", 48)
	page:Header("Quest / interact icon")
	page:Slider("Icon size", 0.5, 4, 0.1, Getter(cfg, "softIconScale"), Setter(cfg, "softIconScale"))
	page:Slider("Icon height above the plate", -10, 60, 1, Getter(cfg, "softIconY"), Setter(cfg, "softIconY"))
	page:Slider("Lower friendly plates by", 0, 60, 1, Getter(cfg, "friendlyLower"), Setter(cfg, "friendlyLower"))
	page:Note("The icon over the unit you soft-target (quest, talk, loot).", 22)
	page:Check("Flag / orb carrier icon (battlegrounds)", Getter(cfg, "carrierIcon"), Setter(cfg, "carrierIcon"))
	page:Slider("Carrier icon size", 16, 120, 1, Getter(cfg, "carrierSize"), Setter(cfg, "carrierSize"))
	page:Choice("Carrier icon position", { { "ABOVE", "Above name" }, { "LEFT", "Left of bar" }, { "TOP", "Top (old)" } },
		Getter(cfg, "carrierAnchor"), Setter(cfg, "carrierAnchor"))
	page:Slider("Carrier X offset", -60, 60, 1, Getter(cfg, "carrierX"), Setter(cfg, "carrierX"))
	page:Slider("Carrier Y offset", -60, 60, 1, Getter(cfg, "carrierY"), Setter(cfg, "carrierY"))

	page:Column(2)
	page:TextStyle("Enemy name", function() return cfg().nameStyle end, { classColor = true })
	page:TextStyle("Friendly name", function() return cfg().friendlyNameStyle end, { classColor = true })
	page:TextStyle("Castbar text", function() return cfg().castStyle end)
	page:TextStyle("Health text", function() return cfg().healthStyle end)
end

local function BuildPlateAurasPage(page)
	local function cfg() return ns.db.nameplates end
	local function ut() return ns.db.nameplates.unitTypes end
	local function imp() return ns.db.nameplates.important end
	page:Column(1)
	page:Header("Nameplate auras")
	page:Slider("Aura size", 12, 48, 1, Getter(cfg, "auraSize"), Setter(cfg, "auraSize"), true)
	page:Check("Crowd control", Getter(cfg, "showCC"), Setter(cfg, "showCC"))
	page:Check("Big and external defensives", Getter(cfg, "showDefensives"), Setter(cfg, "showDefensives"))
	page:Slider("Max debuffs", 0, 12, 1, Getter(cfg, "maxAuras"), Setter(cfg, "maxAuras"))
	page:Check("Only my debuffs", Getter(cfg, "auraOnlyMine"), Setter(cfg, "auraOnlyMine"))
	page:Choice("Debuffs shown", { { "all", "All" }, { "important", "Important" }, { "whitelist", "Whitelist" } },
		Getter(cfg, "auraMode"), Setter(cfg, "auraMode"))
	page:Note("Important = the debuffs Blizzard flags for nameplates (your key DoTs, slows, roots). Whitelist = only the spells listed. The blacklist always applies.", 62)
	page:TextList("Whitelist", 90, function() return SpellListText(cfg().auraWhitelist) end,
		function(t) cfg().auraWhitelist = ParseSpellList(t) end,
		"One spell ID or spell name per line.")
	page:TextList("Blacklist", 90, function() return SpellListText(cfg().auraBlacklist) end,
		function(t) cfg().auraBlacklist = ParseSpellList(t) end)

	page:Column(2)
	page:Header("Enemy unit types")
	local NPm = ns.Nameplates
	local function UT(key) return function() return NPm.GetUnitType(key) end, function(v) NPm.SetUnitType(key, v) end end
	page:Check("Pets (hunter, warlock, unholy ghoul)", UT("pets"))
	page:Check("Guardians / minor pets (temporary summons)", UT("guardians"))
	page:Check("Totems", UT("totems"))
	page:Check("Trivial units", UT("minor"))
	page:Slider("Pet / totem plate width %", 30, 100, 5, function() return math.floor((cfg().minionScale or 1) * 100 + 0.5) end,
		function(v) cfg().minionScale = v / 100 end)
	page:Note("Hiding totems also hides important totems.", 22)
	page:Header("Important units")
	page:Check("Highlight important units", Getter(imp, "enabled"), Setter(imp, "enabled"))
	page:Color("Color", Getter(imp, "color"), Setter(imp, "color"))
	page:Slider("Extra click area", 0, 40, 1, Getter(imp, "clickPad"), Setter(imp, "clickPad"))
	page:TextList("Units", 140, function() return table.concat(imp().units, "\n") end,
		function(t) imp().units = SplitLines(t) end,
		"English unit names or NPC IDs, one per line. Important plates are drawn on top, full width.")
	page:Note("Some PvP instances hide unit names from addons, so pink coloring may not apply there.", 36)
end

local function BuildActionBarPage(page)
	local function cfg() return ns.db.actionBars end
	page:Column(1)
	page:Header("Action bars")
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Note("Restyles Blizzard's bars. Size, rows, padding and position stay in Edit Mode. Turns itself off if Bartender, Dominos or ElvUI is loaded.", 62)
	page:Check("Hide Blizzard bar art", Getter(cfg, "hideArt"), Setter(cfg, "hideArt"), true)
	page:Check("Show macro names", Getter(cfg, "macroText"), Setter(cfg, "macroText"))
	page:Check("Show keybinds", Getter(cfg, "hotkeys"), Setter(cfg, "hotkeys"))
	page:Slider("Icon zoom (shared with cooldowns)", 0, 0.2, 0.01, function() return ns.db.cooldowns.iconZoom end,
		function(v) ns.db.cooldowns.iconZoom = v end)
	page:Check("Show cooldown numbers", Getter(cfg, "cooldownNumbers"), Setter(cfg, "cooldownNumbers"))
	page:Slider("Cooldown number size", 0.5, 2, 0.05, Getter(cfg, "cooldownScale"), Setter(cfg, "cooldownScale"))
	page:Header("Show only on mouseover")
	for _, def in ipairs(ns.ActionBars.BARS) do
		page:Check(def[2], function() return cfg().mouseover[def[1]] and true or false end,
			function(v) cfg().mouseover[def[1]] = v or nil end)
	end
	page:Slider("Faded opacity", 0, 0.5, 0.05, Getter(cfg, "fadeAlpha"), Setter(cfg, "fadeAlpha"))
	page:Column(2)
	page:TextStyle("Keybind text", function() return cfg().hotkeyStyle end)
	page:TextStyle("Charges / count text", function() return cfg().countStyle end)
	page:TextStyle("Macro name text", function() return cfg().macroStyle end)
end

local function BuildChatPage(page)
	local function cfg() return ns.db.chat end
	local CH = ns.Chat
	page:Column(1)
	page:Header("Chat")
	page:Check("Restyle chat", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Note("Restyles Blizzard's chat windows. Tabs, channels and window size and position stay in Blizzard's chat settings. Turns itself off if Chattynator, Prat or ElvUI is loaded.", 62)
	page:Header("Window")
	page:Color("Background color", Getter(cfg, "bgColor"), Setter(cfg, "bgColor"))
	page:Slider("Background opacity", 0, 1, 0.05, Getter(cfg, "bgAlpha"), Setter(cfg, "bgAlpha"))
	page:Check("Border", Getter(cfg, "border"), Setter(cfg, "border"))
	page:Color("Tab color", Getter(cfg, "tabColor"), Setter(cfg, "tabColor"))
	page:Slider("Tab opacity", 0, 1, 0.05, Getter(cfg, "tabAlpha"), Setter(cfg, "tabAlpha"))
	page:Slider("Unselected tab text opacity", 0, 1, 0.05, Getter(cfg, "tabInactiveAlpha"), Setter(cfg, "tabInactiveAlpha"))
	page:TextStyle("Tab text", function() return cfg().tabStyle end)
	page:Header("Visibility")
	page:Check("Hide until mouseover", Getter(cfg, "mouseover"), Setter(cfg, "mouseover"))
	page:Slider("Faded opacity", 0, 0.5, 0.05, Getter(cfg, "fadeAlpha"), Setter(cfg, "fadeAlpha"))
	page:Check("Show briefly on new messages", Getter(cfg, "showOnMessage"), Setter(cfg, "showOnMessage"))
	page:Slider("Seconds shown", 1, 30, 1, Getter(cfg, "showOnMessageTime"), Setter(cfg, "showOnMessageTime"))
	page:Choice("Side buttons (menu, channels, social)", { { "show", "Show" }, { "hide", "Hide" } }, Getter(cfg, "buttons"), Setter(cfg, "buttons"))
	page:Header("Tabs")
	page:Check("Flash tabs on new messages", Getter(cfg, "flashTabs"), Setter(cfg, "flashTabs"), true)
	page:Check("Only flash for messages from players", Getter(cfg, "flashPlayerOnly"), Setter(cfg, "flashPlayerOnly"))
	page:Check("New whispers open in their own tab", Getter(cfg, "whisperTabs"), Setter(cfg, "whisperTabs"))
	page:Header("Copy")
	page:Check("Copy button (top right, on mouseover)", Getter(cfg, "copyButton"), Setter(cfg, "copyButton"))
	page:Check("Drag over chat text to copy it", Getter(cfg, "dragCopy"), Setter(cfg, "dragCopy"))
	page:Button("Copy chat now", function() if CH and CH.ShowCopy then CH.ShowCopy() end end)
	page:Header("Saved messages")
	page:Choice("Keep messages", { { "session", "Next login" }, { "reload", "Reloads only" }, { "off", "Off" } },
		Getter(cfg, "history"), Setter(cfg, "history"))
	page:Note("Next login: messages come back after a reload and after your next login, then drop off. Lines sent while you're in an arena, battleground, dungeon or raid can't be saved; the game hides their text from addons there.", 76)
	page:Slider("Messages kept per window", 50, 1000, 50, Getter(cfg, "historyLines"), Setter(cfg, "historyLines"))
	page:Check("Line above restored messages", Getter(cfg, "restoreDivider"), Setter(cfg, "restoreDivider"))
	page:Button("Clear saved messages", function() if CH and CH.ClearHistory then CH.ClearHistory() ns:Print("Saved chat cleared.") end end)

	page:Column(2)
	page:Header("Text")
	page:Slider("Font size (0 = each window's own)", 0, 24, 1, Getter(cfg, "fontSize"), Setter(cfg, "fontSize"))
	page:Choice("Outline", { { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICKOUTLINE", "Thick" } }, Getter(cfg, "outline"), Setter(cfg, "outline"))
	page:Slider("Message spacing", 0, 10, 1, Getter(cfg, "spacing"), Setter(cfg, "spacing"))
	page:Check("Indent wrapped lines", Getter(cfg, "indent"), Setter(cfg, "indent"))
	page:Header("Timestamps")
	page:Choice("Timestamps", { { "none", "None" }, { "hm", "HH:MM" }, { "hms", "HH:MM:SS" } }, Getter(cfg, "timestamps"), Setter(cfg, "timestamps"))
	page:Check("24-hour clock", Getter(cfg, "clock24"), Setter(cfg, "clock24"))
	page:Choice("Layout", { { "inline", "In the line" }, { "column", "Own column" } }, Getter(cfg, "timestampMode"), Setter(cfg, "timestampMode"))
	page:Slider("Column gap", 2, 30, 1, Getter(cfg, "columnGap"), Setter(cfg, "columnGap"))
	page:Color("Timestamp color", Getter(cfg, "timestampColor"), Setter(cfg, "timestampColor"))
	page:Note("Own column pads every time to the same width so messages start at the same spot. Wrapped lines use the game's indent, which addons can't size.", 50)
	page:Header("Names and channels")
	page:Choice("Channel names", { { "full", "Full" }, { "short", "Short" }, { "name", "Name" } }, Getter(cfg, "channelStyle"), Setter(cfg, "channelStyle"))
	page:Note("[2. Trade - City] becomes [2] (Short) or [Trade] (Name). Party, Raid, Guild and Instance become P, R, G and I.", 36)
	page:Check("Remove brackets", Getter(cfg, "removeBrackets"), Setter(cfg, "removeBrackets"))
	page:Check("Hide realm names", Getter(cfg, "hideRealms"), Setter(cfg, "hideRealms"))
	page:Check("\"From Name:\" for incoming whispers", Getter(cfg, "shortWhispers"), Setter(cfg, "shortWhispers"))
	page:Check("Class colors for names", Getter(cfg, "classColors"), Setter(cfg, "classColors"))
	page:Check("Show player level", Getter(cfg, "showLevel"), Setter(cfg, "showLevel"))
	page:Check("Not at max level", Getter(cfg, "levelHideMax"), Setter(cfg, "levelHideMax"))
	page:Note("Levels are known for your group, guild and friends, and for players you target or mouse over. New settings apply to new lines.", 50)
	page:Header("Colors")
	if CH and CH.COLOR_TYPES then
		for _, def in ipairs(CH.COLOR_TYPES) do
			page:Color(def[2], function() return CH.GetColor(def[1]) end, function(c) CH.SetColor(def[1], c) end)
		end
		for i = 1, CH.CHANNEL_SLOTS do
			local key = "CHANNEL" .. i
			local name = CH.ChannelName and CH.ChannelName(i)
			page:Color("Channel " .. i .. (name and (" (" .. name .. ")") or ""), function() return CH.GetColor(key) end, function(c) CH.SetColor(key, c) end)
		end
	end
end

local function BuildMiscPage(page)
	local function gcd() return ns.db.misc.gcd end
	local function decor() return ns.db.misc.decor end
	page:Column(1)
	page:Header("GCD History")
	page:Check("Enabled", Getter(gcd, "enabled"), Setter(gcd, "enabled"))
	page:Note("Icons of the spells you cast, newest first, sliding along as you cast more.", 36)
	page:Button("Test", function() if ns.Misc and ns.Misc.TestGCD then ns.Misc.TestGCD() end end)
	page:Slider("Icon size", 16, 80, 1, Getter(gcd, "size"), Setter(gcd, "size"))
	page:Slider("Icons shown", 2, 12, 1, Getter(gcd, "count"), Setter(gcd, "count"))
	page:Slider("Spacing", 0, 20, 1, Getter(gcd, "spacing"), Setter(gcd, "spacing"))
	page:Dropdown("Older icons move", { { "RIGHT", "Right" }, { "LEFT", "Left" }, { "UP", "Up" }, { "DOWN", "Down" } },
		Getter(gcd, "direction"), Setter(gcd, "direction"))
	page:Slider("Seconds on screen", 2, 30, 1, Getter(gcd, "duration"), Setter(gcd, "duration"))
	page:Choice("Show", { { "always", "Always" }, { "combat", "In combat" }, { "pvp", "Arena + BGs" } }, Getter(gcd, "where"), Setter(gcd, "where"))
	page:Check("Interrupted casts (red)", Getter(gcd, "showInterrupted"), Setter(gcd, "showInterrupted"))
	page:Position(nil, function() return "gcdHistory" end)
	page:TextList("Ignored spells", 90, function() return SpellListText(gcd().ignore) end,
		function(text) gcd().ignore = ParseSpellList(text) end, "One spell ID or name per line. Auto Attack and Auto Shot are ignored by default.")

	page:Column(2)
	page:Header("Auto-Confirm Decor Purchases")
	page:Check("Enabled", Getter(decor, "enabled"), Setter(decor, "enabled"))
	page:Note("Buying housing decor from a vendor skips the \"are you sure\" popup. Other items still ask. Never used for the in-game shop.", 50)
	page:Slider("Only up to this many gold (0 = any price)", 0, 10000, 100, Getter(decor, "maxGold"), Setter(decor, "maxGold"))
	page:Check("Say in chat what was bought", Getter(decor, "announce"), Setter(decor, "announce"))
end

local function BuildCombatPage(page)
	local function cfg() return ns.db.combat end
	page:Column(1)
	page:Header("Combat indicator")
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Check("Show icon in combat", Getter(cfg, "icon"), Setter(cfg, "icon"))
	page:Slider("Icon size", 10, 64, 1, Getter(cfg, "size"), Setter(cfg, "size"))
	page:Check("Attach to player frame", Getter(cfg, "attached"), Setter(cfg, "attached"))
	page:Dropdown("Spot on the player frame", {
		{ "TOPLEFT", "Top left" }, { "TOP", "Top" }, { "TOPRIGHT", "Top right" }, { "LEFT", "Left" },
		{ "CENTER", "Center" }, { "RIGHT", "Right" }, { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" },
	}, Getter(cfg, "attachPoint"), Setter(cfg, "attachPoint"))
	page:Slider("Offset X (attached)", -60, 60, 1, Getter(cfg, "attachX"), Setter(cfg, "attachX"))
	page:Slider("Offset Y (attached)", -60, 60, 1, Getter(cfg, "attachY"), Setter(cfg, "attachY"))
	page:Position("Position (not attached)", function() return "combatIcon" end)
	page:Column(2)
	page:Header("Entering / Leaving Combat text")
	page:Check("Show message", Getter(cfg, "text"), Setter(cfg, "text"))
	page:Slider("Seconds on screen", 0.5, 4, 0.1, Getter(cfg, "textDuration"), Setter(cfg, "textDuration"))
	page:Color("Entering color", Getter(cfg, "enterColor"), Setter(cfg, "enterColor"))
	page:Color("Leaving color", Getter(cfg, "leaveColor"), Setter(cfg, "leaveColor"))
	page:Position("Message position", function() return "combatText" end)
	page:TextStyle("Message text", function() return cfg().textStyle end)
end

local function BuildCursorPage(page)
	local function cfg() return ns.db.cursor end
	page:Column(1)
	page:Header("Cursor")
	page:Dropdown("Cursor size", ns.Cursor.SIZES, function() return cfg().size or -1 end, Setter(cfg, "size"))
	page:Header("Ring around the cursor")
	page:Check("Show ring", Getter(cfg, "ring"), Setter(cfg, "ring"))
	page:Check("Only in combat", Getter(cfg, "ringCombatOnly"), Setter(cfg, "ringCombatOnly"))
	page:Slider("Size", 16, 160, 1, Getter(cfg, "ringSize"), Setter(cfg, "ringSize"))
	page:Choice("Thickness", { { "thin", "Thin" }, { "thick", "Thick" } }, Getter(cfg, "ringThickness"), Setter(cfg, "ringThickness"))
	page:Color("Color", Getter(cfg, "ringColor"), Setter(cfg, "ringColor"))
	page:Slider("Opacity", 0.1, 1, 0.05, Getter(cfg, "ringAlpha"), Setter(cfg, "ringAlpha"))
	page:Note("The ring hides while you hold right-click to turn the camera.", 36)
end

local function BuildClassPowerPage(page)
	local function cfg() return ns.db.classPower end
	page:Column(1)
	page:Header("Class resource")
	page:Note("Soul shards, combo points, holy power, chi, arcane charges or essence, depending on class and spec.", 36)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"))
	page:Check("Attach above player frame", Getter(cfg, "attached"), Setter(cfg, "attached"))
	page:Slider("Width (floating)", 40, 500, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Height", 2, 40, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Check("Lines between segments", Getter(cfg, "separators"), Setter(cfg, "separators"))
	page:Choice("Line thickness", { { 1, "Thin" }, { 2, "Thick" }, { 3, "Extra thick" } }, Getter(cfg, "separatorSize"), Setter(cfg, "separatorSize"))
	page:Check("Number in the middle", Getter(cfg, "showText"), Setter(cfg, "showText"))
	page:Check("Use my color", Getter(cfg, "useCustomColor"), Setter(cfg, "useCustomColor"))
	page:Color("My color", Getter(cfg, "color"), Setter(cfg, "color"))
	page:Position("Position (floating)", function() return "classPower" end)
	page:Column(2)
	page:TextStyle("Number text", function() return cfg().textStyle end)
end

local function BuildArenaPage(page)
	local function cfg() return ns.db.arena end
	local function ccfg() return ns.db.arena.castbar end
	page:Column(1)
	page:Header("Arena frames")
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Note("Turn off sArena (or Gladius) first; only one arena addon can own Blizzard's trinket and DR icons.", 36)
	page:Button("Test mode on / off", function() ns.Arena:SetTestMode(not ns.Arena.testMode) end)
	page:Slider("Width", 60, 400, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Height", 12, 80, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Slider("Spacing", 0, 80, 1, Getter(cfg, "spacing"), Setter(cfg, "spacing"))
	page:Choice("Grow", { { "DOWN", "Down" }, { "UP", "Up" } }, Getter(cfg, "growth"), Setter(cfg, "growth"))
	page:Choice("Power bar", { { "all", "All" }, { "healer", "Healers" }, { "none", "None" } }, Getter(cfg, "power"), Setter(cfg, "power"))
	page:Note("Rated arena hides enemy roles, so 'Healers' falls back to mana users there (healers plus some casters).", 36)
	page:Slider("Power height", 1, 20, 1, Getter(cfg, "powerHeight"), Setter(cfg, "powerHeight"))
	page:Check("Castbar", Getter(ccfg, "enabled"), Setter(ccfg, "enabled"), true)
	page:Slider("Castbar height", 4, 30, 1, Getter(ccfg, "height"), Setter(ccfg, "height"))
	page:Header("Icons")
	page:Check("Spec icon", Getter(cfg, "specIcon"), Setter(cfg, "specIcon"))
	page:Check("Healer icon", Getter(cfg, "healerIcon"), Setter(cfg, "healerIcon"))
	page:Slider("Healer cross size", 6, 100, 1, Getter(cfg, "healerSize"), Setter(cfg, "healerSize"))
	page:Dropdown("Healer cross corner", { { "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" }, { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" } },
		Getter(cfg, "healerAnchor"), Setter(cfg, "healerAnchor"))
	page:Check("Teammates targeting (one square each)", Getter(cfg, "targetDots"), Setter(cfg, "targetDots"))
	page:Slider("Square size", 3, 20, 1, Getter(cfg, "dotSize"), Setter(cfg, "dotSize"))
	page:Color("Square color", Getter(cfg, "dotColor"), Setter(cfg, "dotColor"))
	page:Check("Use the teammate's class color instead", Getter(cfg, "dotClassColor"), Setter(cfg, "dotClassColor"))
	page:Check("Trinket", Getter(cfg, "trinket"), Setter(cfg, "trinket"), true)
	page:Slider("Trinket size", 14, 64, 1, Getter(cfg, "trinketSize"), Setter(cfg, "trinketSize"))
	page:Choice("Right click", { { "focus", "Focus" }, { "target", "Target" }, { "menu", "Menu" }, { "none", "None" } },
		Getter(cfg, "rightClick"), Setter(cfg, "rightClick"))
	page:Position(nil, function() return "arena" end)

	page:Column(2)
	page:Header("Diminishing returns")
	page:Check("Show DRs", Getter(cfg, "dr"), Setter(cfg, "dr"), true)
	page:Slider("DR icon size", 12, 56, 1, Getter(cfg, "drSize"), Setter(cfg, "drSize"))
	page:Choice("DR side", { { "LEFT", "Left" }, { "RIGHT", "Right" } }, Getter(cfg, "drSide"), Setter(cfg, "drSide"))
	page:Check("Only DRs I can apply (Blizzard filter)", Getter(cfg, "drOnlyMine"), Setter(cfg, "drOnlyMine"))
	page:Header("DR categories")
	local function cats() return ns.db.arena.drCategories end
	for _, key in ipairs(ns.Arena.DR_ORDER) do
		page:Check(ns.Arena.DR_LABELS[key], Getter(cats, key), Setter(cats, key))
	end
	page:Note("Category picking needs Blizzard to tell us which category each icon is. If it hides that in rated games, every category shows; 'Only DRs I can apply' always works.", 62)
	page:Header("Text")
	page:Choice("Health text", healthTextChoices, Getter(cfg, "healthText"), Setter(cfg, "healthText"))
	page:TextStyle("Name text", function() return cfg().nameStyle end, { classColor = true })
	page:TextStyle("Health text", function() return cfg().healthStyle end)
	page:TextStyle("Castbar text", function() return ccfg().textStyle end)
end

local function BuildBGPage(page)
	page.side = "bgEnemies"
	local function cfg() return ns.db[page.side] end
	page:Column(1)
	page:Header("Battleground frames")
	page:Choice("Editing", { { "bgEnemies", "Enemies" }, { "bgAllies", "Allies" } },
		function() return page.side end,
		function(v) page.side = v; page:SyncAll() end)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Button("Test mode on / off", function() ns.BGEnemies:SetTestMode(not ns.BGEnemies.testMode) end)
	page:Check("Show Horde / Alliance title", Getter(cfg, "header"), Setter(cfg, "header"))
	page:Slider("Width", 60, 300, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Row height", 10, 50, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Slider("Spacing", 0, 20, 1, Getter(cfg, "spacing"), Setter(cfg, "spacing"))
	page:Slider("Columns", 1, 3, 1, Getter(cfg, "columns"), Setter(cfg, "columns"))
	page:Slider("Max rows", 1, 15, 1, Getter(cfg, "maxRows"), Setter(cfg, "maxRows"))
	page:Check("Icon beside each row", Getter(cfg, "specIcon"), Setter(cfg, "specIcon"))
	page:Check("Health percent", Getter(cfg, "showHealthText"), Setter(cfg, "showHealthText"))
	page:Check("Hide realm names", Getter(cfg, "shortNames"), Setter(cfg, "shortNames"))
	page:Slider("Out of range opacity", 0.1, 1, 0.05, Getter(cfg, "oorAlpha"), Setter(cfg, "oorAlpha"))
	page:Choice("Icon beside each row", { { "role", "Role" }, { "spec", "Spec / class" } }, Getter(cfg, "iconMode"), Setter(cfg, "iconMode"))
	page:Note("Role: green cross for healers (both teams), shield for tanks, sword for damage. Falls back to the spec or class icon when the role isn't known.", 48)
	page:Check("Spec name as text when there's no spec icon", Getter(cfg, "specText"), Setter(cfg, "specText"))
	page:Choice("Power bar", { { "none", "Off" }, { "healers", "Healers" }, { "all", "Everyone" } }, Getter(cfg, "power"), Setter(cfg, "power"))
	page:Slider("Power bar height", 1, 10, 1, Getter(cfg, "powerHeight"), Setter(cfg, "powerHeight"))
	page:Check("Role hidden: count mana users as healers", Getter(cfg, "powerManaFallback"), Setter(cfg, "powerManaFallback"))
	page:Note("Enemy power updates while they're visible. Where a role is hidden, the mana option treats every mana user as a healer.", 48)
	page:Check("Flag / orb carrier icon", Getter(cfg, "carrier"), Setter(cfg, "carrier"))
	page:Choice("Carrier icon side", { { "LEFT", "Left" }, { "RIGHT", "Right" } }, Getter(cfg, "carrierSide"), Setter(cfg, "carrierSide"))
	page:Check("Flag / orb debuff with stack count", Getter(cfg, "stacks"), Setter(cfg, "stacks"))
	page:Slider("Debuff icon size", 10, 40, 1, Getter(cfg, "stackSize"), Setter(cfg, "stackSize"), true)
	page:Choice("Right click", { { "focus", "Focus" }, { "target", "Target" }, { "none", "None" } },
		Getter(cfg, "rightClick"), Setter(cfg, "rightClick"))
	page:Check("Target highlight", Getter(cfg, "targetHighlight"), Setter(cfg, "targetHighlight"))
	page:Slider("Highlight thickness", 1, 6, 1, Getter(cfg, "targetThickness"), Setter(cfg, "targetThickness"))
	page:Color("Highlight color", Getter(cfg, "targetColor"), Setter(cfg, "targetColor"))
	page:Position(nil, function() return page.side end)
	page:Column(2)
	page:Header("How it works")
	page:Note("Rows sort healers, tanks, then damage. Click to target; right click focuses (then returns to your target). Off in 40-player battlegrounds.", 48)
	page:Note("Enemies show live health while visible (nameplate, target, focus, mouseover, carriers) and keep their last known health, faded, when out of sight.", 48)
	page:Note("Once a match is live, specs may only be available as text and roles can't be used for sorting.", 36)
	page:TextStyle("Horde / Alliance title", function() return cfg().headerStyle end)
	page:TextStyle("Name text", function() return cfg().nameStyle end)
	page:TextStyle("Health text", function() return cfg().healthStyle end)
	page:TextStyle("Spec text", function() return cfg().specStyle end)
end

local function BuildBGScorePage(page)
	local function cfg() return ns.db.bgWidgets end
	page:Column(1)
	page:Header("Battleground score")
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"))
	page:Note("Only inside battlegrounds. Elsewhere these stay where Blizzard puts them.", 36)
	page:Check("Hide Blizzard raid frames in Blitz and battlegrounds", Getter(cfg, "hideRaidFrames"), Setter(cfg, "hideRaidFrames"))
	page:Note("Not in 40-player battlegrounds. Works even when the score options are off.", 24)
	page:Button("Test mode on / off", function() ns.BGWidgets:SetTestMode(not ns.BGWidgets.testMode) end)
	page:Check("Move the score display (top of screen)", Getter(cfg, "moveScore"), Setter(cfg, "moveScore"))
	page:Slider("Score size", 0.5, 2, 0.05, Getter(cfg, "scoreScale"), Setter(cfg, "scoreScale"))
	page:Position("Score position", function() return "bgScore" end)
	page:Header("Score bar look")
	page:Dropdown("Bar texture", function()
		local items = { { "blizzard", "Blizzard" }, { "flat", "Flat" } }
		local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
		if LSM then for _, n in ipairs(LSM:List("statusbar")) do table.insert(items, { n, n }) end end
		return items
	end, Getter(cfg, "texture"), Setter(cfg, "texture"), true)
	page:Color("Alliance side", Getter(cfg, "leftColor"), Setter(cfg, "leftColor"))
	page:Color("Horde side", Getter(cfg, "rightColor"), Setter(cfg, "rightColor"))
	page:Column(2)
	page:Header("Capture / cart progress")
	page:Note("The progress widgets Blizzard normally puts under the minimap (cart, capture bars).", 36)
	page:Check("Move it", Getter(cfg, "moveCapture"), Setter(cfg, "moveCapture"))
	page:Slider("Size", 0.5, 2, 0.05, Getter(cfg, "captureScale"), Setter(cfg, "captureScale"))
	page:Position("Position", function() return "bgCapture" end)
	page:Header("Return to Graveyard button")
	page:Check("Move it", Getter(cfg, "moveGhost"), Setter(cfg, "moveGhost"))
	page:Slider("Size", 0.5, 2, 0.05, Getter(cfg, "ghostScale"), Setter(cfg, "ghostScale"))
	page:Position("Position", function() return "bgGhost" end)
	page:Note("Unlock frames (/stinkie unlock) to drag both boxes. They're easiest to place inside a battleground, where the real widgets show.", 48)
end

local function BuildDamageMeterPage(page)
	local function cfg() return ns.db.damageMeter end
	page:Column(1)
	page:Header("Damage meter")
	page:Check("Restyle Blizzard's damage meter", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Note("Window size, bar height, spacing, class colors, background opacity and which meters show are in Edit Mode (Damage Meter). This page changes the look.", 62)
	page:Header("Bars")
	page:Dropdown("Bar texture", function()
		local items = { { "flat", "Flat" } }
		local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
		if LSM then for _, n in ipairs(LSM:List("statusbar")) do table.insert(items, { n, n }) end end
		return items
	end, Getter(cfg, "texture"), Setter(cfg, "texture"))
	page:Slider("Bar background opacity", 0, 1, 0.05, Getter(cfg, "barBackgroundAlpha"), Setter(cfg, "barBackgroundAlpha"))
	page:Check("1px border around bars", Getter(cfg, "barBorder"), Setter(cfg, "barBorder"))
	page:Header("Window")
	page:Check("1px border around the window", Getter(cfg, "windowBorder"), Setter(cfg, "windowBorder"))
	page:Color("Background color", Getter(cfg, "backgroundColor"), Setter(cfg, "backgroundColor"))
	page:Color("Header color", Getter(cfg, "headerColor"), function(c) cfg().headerColor = { c[1], c[2], c[3], cfg().headerColor[4] or 0.95 } end)
	page:Slider("Header opacity", 0, 1, 0.05, function() return cfg().headerColor[4] or 0.95 end, function(v) cfg().headerColor[4] = v end)
	page:Check("Hide the scroll bar", Getter(cfg, "hideScrollBar"), Setter(cfg, "hideScrollBar"))
	page:Column(2)
	page:TextStyle("Names", function() return cfg().nameStyle end)
	page:TextStyle("Numbers", function() return cfg().valueStyle end)
	page:TextStyle("Header text", function() return cfg().titleStyle end)
end

local function BuildCombatLogPage(page)
	local function cfg() return ns.db.combatLog end
	page:Column(1)
	page:Header("Automatic combat logging")
	page:Note("Turns /combatlog on when you enter the content below, off when you leave, and back on after a /reload. Logging you start yourself is never turned off.", 48)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"))
	page:Header("Log in")
	page:Check("Arena (rated 2v2/3v3, skirmish, war games)", Getter(cfg, "arena"), Setter(cfg, "arena"))
	page:Check("Solo Shuffle", Getter(cfg, "shuffle"), Setter(cfg, "shuffle"))
	page:Check("Blitz", Getter(cfg, "blitz"), Setter(cfg, "blitz"))
	page:Check("Regular battlegrounds", Getter(cfg, "battleground"), Setter(cfg, "battleground"))
	page:Check("Mythic+ (starts when the key starts)", Getter(cfg, "mplus"), Setter(cfg, "mplus"))
	page:Check("Other dungeons (normal, heroic, mythic 0)", Getter(cfg, "dungeon"), Setter(cfg, "dungeon"))
	page:Check("Raids", Getter(cfg, "raid"), Setter(cfg, "raid"))
	page:Header("Options")
	page:Check("Turn on Advanced Combat Logging", Getter(cfg, "advanced"), Setter(cfg, "advanced"))
	page:Check("No chat messages", Getter(cfg, "quiet"), Setter(cfg, "quiet"))
	page:Check("Keep one log for the whole session", Getter(cfg, "singleFile"), Setter(cfg, "singleFile"))
	page:Note("Logging stays on until you log out, so a session's matches share one file.", 36)
	page:Column(2)
	page:Header("Status")
	local status = page:Note("", 66)
	function page:OnShowPage()
		local match = ns.CombatLog.MatchType()
		status:SetText(string.format("Logging: %s\nAdvanced logging: %s\nCurrent match: %s",
			LoggingCombat() and "|cff55ff55on|r" or "|cffaaaaaaoff|r",
			GetCVar("advancedCombatLogging") == "1" and "|cff55ff55on|r" or "|cffaaaaaaoff|r",
			match and ns.CombatLog.labels[match] or "none"))
	end
	page:Note("The log is written to World of Warcraft\\_retail_\\Logs\\WoWCombatLog-*.txt for Warcraft Logs, wowarenalogs and similar tools.", 48)
end

local function BuildCooldownPage(page)
	local function cd() return ns.db.cooldowns end
	page.barIndex = 1
	local function bcfg() return ns.db.cooldowns.bars[page.barIndex] end

	page:Column(1)
	page:Header("Blizzard Cooldown Manager")
	page:Check("Style like the custom bars", Getter(cd, "skinBlizzard"), Setter(cd, "skinBlizzard"), true)
	page:Slider("Icon zoom (all bars)", 0, 0.3, 0.01, Getter(cd, "iconZoom"), Setter(cd, "iconZoom"))
	page:Check("Center Essential row", Getter(cd, "centerEssential"), Setter(cd, "centerEssential"))
	page:Check("Center Utility row", Getter(cd, "centerUtility"), Setter(cd, "centerUtility"))
	page:Check("Center Buff icons", Getter(cd, "centerBuffs"), Setter(cd, "centerBuffs"))
	page:Note("Move the Blizzard rows in Edit Mode.", 22)

	page:Header("Custom bars")
	page:Choice("Editing", { { 1, "Bar 1" }, { 2, "Bar 2" } }, function() return page.barIndex end, function(v)
		page.barIndex = v
		page:SyncAll()
	end)
	page:Check("Enabled", Getter(bcfg, "enabled"), Setter(bcfg, "enabled"))
	page:Slider("Icon size", 16, 64, 1, Getter(bcfg, "size"), Setter(bcfg, "size"))
	page:Slider("Spacing", 0, 20, 1, Getter(bcfg, "spacing"), Setter(bcfg, "spacing"))
	page:Slider("Icons per row", 1, 24, 1, Getter(bcfg, "perRow"), Setter(bcfg, "perRow"))
	page:Check("Show item counts", Getter(bcfg, "showCount"), Setter(bcfg, "showCount"))
	page:Position(nil, function() return "cdbar" .. page.barIndex end)
	page:TextStyle("Count text", function() return bcfg().countStyle end)

	-- icon grid (column 2)
	page:Column(2)
	page:Header("Icons on this bar")
	page:Note("Drag icons to reorder. Right-click to remove. Hover for details. On the bar itself, spells you haven't learned (or not in this spec) and items you have none of are hidden.", 48)

	local ICON, PAD, PER_ROW = 36, 6, 6
	local gx, gy = page:Next(0)
	local grid = CreateFrame("Frame", nil, page)
	grid:SetPoint("TOPLEFT", gx, gy)
	grid:SetSize(PER_ROW * (ICON + PAD), ICON)
	grid.icons = {}

	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetSize(ICON, ICON)
	ghost:SetFrameStrata("TOOLTIP")
	ghost.tex = ghost:CreateTexture(nil, "ARTWORK")
	ghost.tex:SetAllPoints()
	ghost.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ghost:SetAlpha(0.8)
	ghost:Hide()
	ghost:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local s = UIParent:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
	end)

	-- the slot under the cursor: index of the icon hovered, or one past the end
	local function DropIndex()
		local n = #bcfg().entries
		for i = 1, n do
			local icon = grid.icons[i]
			if icon and icon:IsShown() and icon:IsMouseOver() then return i end
		end
		if grid:IsMouseOver(0, -ICON * 2, 0, 0) then return n end
	end

	local function Render() end -- forward

	local function MakeIcon(i)
		local b = CreateFrame("Button", nil, grid)
		b:SetSize(ICON, ICON)
		b:RegisterForDrag("LeftButton")
		b:RegisterForClicks("RightButtonUp")
		ns.CreateBackdrop(b, 1)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.num = Label(b, "", 11, { 0.8, 0.8, 0.85 })
		b.num:SetPoint("TOPLEFT", 2, -1)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(ns.Cooldowns.DescribeEntry(bcfg().entries[self.index] or ""))
			GameTooltip:AddLine("Drag to move, right-click to remove", 0.6, 0.6, 0.65)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				table.remove(bcfg().entries, self.index)
				Render()
				QueueRefresh()
			end
		end)
		b:SetScript("OnDragStart", function(self)
			ghost.tex:SetTexture(self.tex:GetTexture())
			ghost:Show()
			self:SetAlpha(0.3)
			grid.dragFrom = self.index
		end)
		b:SetScript("OnDragStop", function(self)
			ghost:Hide()
			self:SetAlpha(1)
			local from, to = grid.dragFrom, DropIndex()
			grid.dragFrom = nil
			if from and to and from ~= to then
				ns.Cooldowns.MoveEntry(page.barIndex, from, to)
				Render()
				QueueRefresh()
			end
		end)
		grid.icons[i] = b
		return b
	end

	Render = function()
		local entries = bcfg().entries
		for _, b in ipairs(grid.icons) do b:Hide() end
		for i, entry in ipairs(entries) do
			local b = grid.icons[i] or MakeIcon(i)
			b.index = i
			b.tex:SetTexture(ns.Cooldowns.EntryTexture(entry) or 134400)
			b.num:SetText(i)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", ((i - 1) % PER_ROW) * (ICON + PAD), -math.floor((i - 1) / PER_ROW) * (ICON + PAD))
			b:Show()
		end
		local rows = math.max(1, math.ceil(#entries / PER_ROW))
		grid:SetHeight(rows * (ICON + PAD))
		page.addArea:ClearAllPoints()
		page.addArea:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -10)
	end

	-- add area under the grid: drop box, text input, shortcuts
	local add = CreateFrame("Frame", nil, page)
	add:SetSize(COL_W - 24, 120)
	page.addArea = add
	page:Next(260) -- reserve space for grid + add area in the scroll height

	local drop = CreateFrame("Button", nil, add)
	drop:SetSize(COL_W - 24, 30)
	drop:SetPoint("TOPLEFT")
	Flat(drop, ACCENT[1] * 0.25, ACCENT[2] * 0.25, ACCENT[3] * 0.25, 1)
	ns.CreateBackdrop(drop, 0)
	Label(drop, "Drop a spell or item here to add it", 13):SetPoint("CENTER")

	local input = EditBox(add, 200)
	input:SetJustifyH("LEFT")
	input:SetTextInsets(6, 6, 0, 0)
	input:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -10)
	local addBtn = FlatButton(add, "Add", 64)
	addBtn:SetPoint("LEFT", input, "RIGHT", 8, 0)
	local hint = Label(add, "Type a spell or item name or ID. Shortcuts: racial, slot:13, slot:14, item:5512 (Healthstone)", 12, { 0.55, 0.55, 0.6 })
	hint:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -8)
	hint:SetWidth(COL_W - 24)
	hint:SetWordWrap(true)

	local function AddEntry(entry)
		if not entry then
			ns:Print("Couldn't find that spell or item. Spells must be in your spellbook; items can be added by ID.")
			return
		end
		table.insert(bcfg().entries, entry)
		Render()
		QueueRefresh()
	end
	drop:SetScript("OnReceiveDrag", function()
		AddEntry(ns.Cooldowns.EntryFromCursor())
		ClearCursor()
	end)
	drop:SetScript("OnClick", function()
		if GetCursorInfo() then
			AddEntry(ns.Cooldowns.EntryFromCursor())
			ClearCursor()
		end
	end)
	local function submit()
		AddEntry(ns.Cooldowns.EntryFromInput(input:GetText()))
		input:SetText("")
		input:ClearFocus()
	end
	input:SetScript("OnEnterPressed", submit)
	addBtn:SetScript("OnClick", submit)

	page.OnShowPage = Render
	O.RenderCooldownGrid = Render
end

local function BuildGeneralPage(page)
	local function db() return ns.db end
	page:Column(1)
	page:Header("General")
	page:Dropdown("Font (everything)", function()
		-- only list fonts the client can actually load (some shared-media fonts point at missing files)
		local items = {}
		for _, f in ipairs(ns.FONTS) do
			if f[1] == ns.db.font or ns.FontLoads(f[2]) then table.insert(items, { f[1], f[1] }) end
		end
		return items
	end, Getter(db, "font"), function(v)
		ns.db.font = v
		ns.InvalidateFont()
		-- rebuild this window in the new font
		C_Timer.After(0.1, function()
			if O.window then O.window:Hide() end
			O.window = nil
			ns:ToggleOptions()
		end)
	end)
	page:Check("Use it for Blizzard's UI too", Getter(db, "globalFont"), Setter(db, "globalFont"))
	page:Check("Names above characters (yours too)", Getter(db, "worldNameFont"), Setter(db, "worldNameFont"), true)
	page:Check("Floating combat text", Getter(db, "combatTextFont"), Setter(db, "combatTextFont"), true)
	page:Note("Blizzard UI: tooltips, buff timers, spec names, character sheet, damage meter, zone text, settings. Names above characters and combat text need a full logout, not just a reload.", 62)
	page:Slider("Scale", 0.5, 2, 0.05, Getter(db, "scale"), Setter(db, "scale"))
	page:Check("Class-colored health", Getter(db, "classColorHealth"), Setter(db, "classColorHealth"))
	page:Color("Health color (when not class colored)", function() return ns.db.colors.health end, function(c) ns.db.colors.health = c end)
	page:Color("Empty health", function() return ns.db.colors.healthBackground end, function(c)
		ns.db.colors.healthBackground = { c[1], c[2], c[3], 1 }
	end)
	page:Color("Shield (absorb)", function() return ns.db.colors.absorb end, function(c)
		ns.db.colors.absorb = { c[1], c[2], c[3], ns.db.colors.absorb[4] or 0.55 }
	end)
	page:Color("Overshield (top half, backwards)", function() return ns.db.colors.overAbsorb end, function(c)
		ns.db.colors.overAbsorb = { c[1], c[2], c[3], ns.db.colors.overAbsorb[4] or 0.85 }
	end)
	page:Color("Frame background", function() return ns.db.colors.background end, function(c)
		local a = ns.db.colors.background[4] or 0.85
		ns.db.colors.background = { c[1], c[2], c[3], a }
		MarkReload()
	end)
	page:Header("Layout")
	page:Button("Unlock / lock frames", function() ns:SetLocked(ns.unlocked) end)
	page:Note("While unlocked: drag a box, or click it and use the arrow keys (Shift = 10). Every page also has exact X/Y fields.", 48)
	page:Column(2)
	page:Header("Community")
	page:Note("Questions or ideas? Ask in #stinkie-ui on Discord, or drop by the stream.", 36)
	page:Button("Discord", function() ShowLink("Discord", "https://discord.gg/abb8n4T3rc") end, nil, true)
	page:Button("Twitch", function() ShowLink("Twitch", "https://twitch.tv/smellystinkie") end, nil, true)
	page:Button("YouTube", function() ShowLink("YouTube", "https://www.youtube.com/@SmellyStinkie") end, nil, true)
	page:Header("Profiles")
	local function profileItems(skipCurrent)
		return function()
			local items = {}
			for _, n in ipairs(ns:GetProfileNames()) do
				if not (skipCurrent and n == ns:CurrentProfileName()) then table.insert(items, { n, n }) end
			end
			if #items == 0 then items[1] = { "", "(none)" } end
			return items
		end
	end
	page:Dropdown("Profile on this character", profileItems(false), function() return ns:CurrentProfileName() end, function(v)
		if v ~= ns:CurrentProfileName() then StaticPopup_Show("STINKIEUI_SWITCH_PROFILE", v, nil, v) end
	end)
	page:Button("Give this character its own profile", function()
		local name = ns.CharKey()
		if ns:CurrentProfileName() == name then ns:Print("This character already uses its own profile.") return end
		StaticPopup_Show("STINKIEUI_NEW_PROFILE", name, nil, name)
	end, 260)
	page:Dropdown("Copy settings from", profileItems(true), function() return "" end, function(v)
		if v ~= "" then StaticPopup_Show("STINKIEUI_COPY_PROFILE", v, ns:CurrentProfileName(), v) end
	end)
	page:Dropdown("Delete a profile", profileItems(true), function() return "" end, function(v)
		if v ~= "" then StaticPopup_Show("STINKIEUI_DELETE_PROFILE", v, nil, v) end
	end)
	page:Note("New characters use Default. Profile changes reload the UI.", 22)
	page:Header("Share")
	page:Button("Export profile", function()
		local str, err = ns:ExportProfile()
		if str then ShowTextPopup("Export profile", str) else ns:Print(err) end
	end)
	page:Button("Import profile", function()
		ShowTextPopup("Import profile", "", function(text)
			local t, err = ns:DecodeProfile(text)
			if not t then ns:Print(err) return end
			StaticPopup_Show("STINKIEUI_IMPORT", nil, nil, text)
		end)
	end)
	page:Button("Reset this profile", function() StaticPopup_Show("STINKIEUI_RESET") end)
	page:Note("Settings marked * apply after a reload.", 22)
	page:Note("Slash commands: /stinkie, /stinkie unlock, /stinkie lock, /stinkie fontcheck, /stinkie auras, /stinkie plates, /stinkie reset", 36)
	page:Note("PT Sans Narrow is bundled under the SIL Open Font License (Media folder).", 36)
end

function PageMixin:Button(text, onClick, width, outlined)
	local x, y = self:Next(32)
	local b = FlatButton(self, text, width or 180, onClick)
	b:SetPoint("TOPLEFT", x, y - 4)
	if outlined then
		-- a 1px brand-green outline so link buttons stand out from the dark page
		-- drawn on its own frame above the button, unsnapped, so no edge can round away to 0px
		local edge = CreateFrame("Frame", nil, b)
		edge:SetAllPoints()
		edge:SetFrameLevel(b:GetFrameLevel() + 3)
		local px = math.max(ns.Pixel(b), 1 / (b:GetEffectiveScale() > 0 and b:GetEffectiveScale() or 1))
		local e = {}
		for i = 1, 4 do
			e[i] = edge:CreateTexture(nil, "OVERLAY")
			e[i]:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
			if e[i].SetSnapToPixelGrid then
				e[i]:SetSnapToPixelGrid(false)
				e[i]:SetTexelSnappingBias(0)
			end
		end
		e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(px)
		e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(px)
		e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(px)
		e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(px)
	end
	return b
end

-- Small window with one link, selected and ready for Ctrl+C.
local linkPopup
function ShowLink(title, url)
	if not linkPopup then
		local p = CreateFrame("Frame", "StinkieUILinkPopup", UIParent)
		p:SetSize(420, 96)
		p:SetPoint("CENTER", 0, 120)
		p:SetFrameStrata("FULLSCREEN_DIALOG")
		p:EnableMouse(true)
		p:SetMovable(true)
		p:RegisterForDrag("LeftButton")
		p:SetScript("OnDragStart", p.StartMoving)
		p:SetScript("OnDragStop", p.StopMovingOrSizing)
		Flat(p, BRAND.plumDark[1], BRAND.plumDark[2], BRAND.plumDark[3], 0.98)
		ns.CreateBackdrop(p, 0)
		table.insert(UISpecialFrames, "StinkieUILinkPopup")
		p.title = Label(p, "", 15, { ACCENT[1], ACCENT[2], ACCENT[3] })
		p.title:SetPoint("TOPLEFT", 12, -10)
		local close = FlatButton(p, "x", 22, function() p:Hide() end)
		close:SetPoint("TOPRIGHT", -8, -8)
		local eb = EditBox(p, 396)
		eb:SetPoint("TOP", 0, -38)
		eb:SetJustifyH("LEFT")
		eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(p.url) self:HighlightText() end end)
		eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
		eb:SetScript("OnMouseUp", function(self) self:SetFocus() self:HighlightText() end)
		eb:SetScript("OnEscapePressed", function() p:Hide() end)
		eb:SetScript("OnEnterPressed", function() p:Hide() end)
		p.eb = eb
		p.hint = Label(p, "Press Ctrl+C to copy, then paste it in your browser.", 12, { 0.78, 0.66, 0.70 })
		p.hint:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -8)
		linkPopup = p
	end
	linkPopup.url = url
	linkPopup.title:SetText(title)
	linkPopup.eb:SetText(url)
	linkPopup:Show()
	linkPopup.eb:SetFocus()
	linkPopup.eb:HighlightText()
end

-- Copy/paste window for export and import strings.
local textPopup
function ShowTextPopup(title, text, onImport)
	if not textPopup then
		local p = CreateFrame("Frame", "StinkieUITextPopup", UIParent)
		p:SetSize(520, 300)
		p:SetPoint("CENTER")
		p:SetFrameStrata("FULLSCREEN_DIALOG")
		p:EnableMouse(true)
		p:SetMovable(true)
		p:RegisterForDrag("LeftButton")
		p:SetScript("OnDragStart", p.StartMoving)
		p:SetScript("OnDragStop", p.StopMovingOrSizing)
		Flat(p, 0.055, 0.050, 0.035, 0.98)
		ns.CreateBackdrop(p, 0)
		table.insert(UISpecialFrames, "StinkieUITextPopup")
		p.title = Label(p, "", 15, { ACCENT[1], ACCENT[2], ACCENT[3] })
		p.title:SetPoint("TOPLEFT", 12, -10)
		p.hint = Label(p, "", 12, { 0.70, 0.68, 0.60 })
		p.hint:SetPoint("TOPLEFT", 12, -30)

		local sf = CreateFrame("ScrollFrame", nil, p)
		sf:SetPoint("TOPLEFT", 12, -52)
		sf:SetPoint("BOTTOMRIGHT", -12, 44)
		Flat(sf, 0.12, 0.11, 0.09, 1)
		ns.CreateBackdrop(sf, 0)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		ns.SetFont(eb, 11)
		eb:SetWidth(490)
		eb:SetTextInsets(6, 6, 6, 6)
		eb:SetScript("OnEscapePressed", function() p:Hide() end)
		sf:SetScrollChild(eb)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(self, d)
			self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - d * 30)))
		end)
		sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
		p.eb = eb

		p.action = FlatButton(p, "Import", 120, function()
			if p.onImport then p.onImport(eb:GetText()) end
		end)
		p.action:SetPoint("BOTTOMRIGHT", -12, 12)
		local close = FlatButton(p, "Close", 90, function() p:Hide() end)
		close:SetPoint("RIGHT", p.action, "LEFT", -8, 0)
		textPopup = p
	end
	local p = textPopup
	p.title:SetText(title)
	p.onImport = onImport
	p.action:SetShown(onImport ~= nil)
	p.hint:SetText(onImport and "Paste a Stinkie UI string (Ctrl+V), then Import." or "Ctrl+C to copy, then share it.")
	p.eb:SetText(text or "")
	p:Show()
	p.eb:SetFocus()
	p.eb:HighlightText()
end

StaticPopupDialogs["STINKIEUI_IMPORT"] = {
	text = "Replace this profile's settings with the imported ones and reload?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, data)
		local ok, err = ns:ImportProfile(data)
		if ok then ReloadUI() else ns:Print(err) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["STINKIEUI_SWITCH_PROFILE"] = {
	text = "Use the profile \"%s\" on this character and reload?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, name) ns:SetProfile(name); ReloadUI() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["STINKIEUI_NEW_PROFILE"] = {
	text = "Create the profile \"%s\" from your current settings, use it on this character and reload?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, name) ns:SetProfile(name, true); ReloadUI() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["STINKIEUI_COPY_PROFILE"] = {
	text = "Copy every setting from \"%s\" into \"%s\" and reload?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, name) if ns:CopyProfile(name) then ReloadUI() end end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["STINKIEUI_DELETE_PROFILE"] = {
	text = "Delete the profile \"%s\"? Characters using it go back to Default.",
	button1 = YES, button2 = NO,
	OnAccept = function(_, name)
		local ok, err = ns:DeleteProfile(name)
		ns:Print(ok and ("Deleted profile " .. name .. ".") or err)
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["STINKIEUI_RESET"] = {
	text = "Reset every setting in this profile and reload?",
	button1 = YES,
	button2 = NO,
	OnAccept = function() ns:ResetProfile(); ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local pages = {
	{ "General", BuildGeneralPage },
	{ "Player", function(p) BuildUnitPage(p, "player") end },
	{ "Target", function(p) BuildUnitPage(p, "target") end },
	{ "Target of Target", function(p) BuildUnitPage(p, "targettarget") end },
	{ "Focus", function(p) BuildUnitPage(p, "focus") end },
	{ "Pet", function(p) BuildUnitPage(p, "pet") end },
	{ "Party", BuildPartyPage },
	{ "Arena", BuildArenaPage },
	{ "PvP Assist", BuildArenaAssistPage },
	{ "Battlegrounds", BuildBGPage },
	{ "BG Score", BuildBGScorePage },
	{ "Castbars", BuildCastbarPage },
	{ "Class Resource", BuildClassPowerPage },
	{ "Nameplates", BuildNameplatePage },
	{ "Plate Auras & Units", BuildPlateAurasPage },
	{ "Action Bars", BuildActionBarPage },
	{ "Cooldowns", BuildCooldownPage },
	{ "Damage Meter", BuildDamageMeterPage },
	{ "Minimap", BuildMinimapPage },
	{ "Chat", BuildChatPage },
	{ "Combat Logging", BuildCombatLogPage },
	{ "Combat", BuildCombatPage },
	{ "Cursor", BuildCursorPage },
	{ "Miscellaneous", BuildMiscPage },
}

local HEADER_H, WIN_H = 92, 680
local NAV_STEP = 23 -- 24 pages must fit the 568px nav column

local function CreateWindow()
	local w = CreateFrame("Frame", "StinkieUIOptions", UIParent)
	w:SetSize(820, WIN_H)
	w:SetPoint("CENTER")
	w:SetFrameStrata("DIALOG")
	w:SetClampedToScreen(true)
	w:EnableMouse(true)
	w:SetMovable(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", w.StartMoving)
	w:SetScript("OnDragStop", w.StopMovingOrSizing)
	w:SetScript("OnHide", function() if popup then popup:Hide() end end)
	Flat(w, 0.055, 0.050, 0.035, 0.97)
	ns.CreateBackdrop(w, 0)
	table.insert(UISpecialFrames, "StinkieUIOptions")

	-- header band in the hood's plum, with the logo
	local band = CreateFrame("Frame", nil, w)
	band:SetPoint("TOPLEFT"); band:SetPoint("TOPRIGHT"); band:SetHeight(HEADER_H)
	Flat(band, BRAND.plumDark[1], BRAND.plumDark[2], BRAND.plumDark[3], 1, "BACKGROUND")
	local line = band:CreateTexture(nil, "ARTWORK")
	line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(2)
	line:SetColorTexture(BRAND.plum[1], BRAND.plum[2], BRAND.plum[3], 1)
	local logo = band:CreateTexture(nil, "ARTWORK")
	logo:SetSize(HEADER_H - 12, HEADER_H - 12)
	logo:SetPoint("LEFT", 10, -1)
	logo:SetTexture(ns.MEDIA.logo, "CLAMP", "CLAMP", "TRILINEAR")
	local cream, hex = BRAND.cream, ns.ACCENT_HEX
	local title = Label(band, "STINKIE |cff" .. hex .. "UI|r", 26, { cream[1], cream[2], cream[3] })
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 14, -10)
	local sub = Label(band, "v" .. ns.version .. "  ·  profile: " .. ns:CurrentProfileName() .. "  ·  |cff" .. hex .. "twitch.tv/smellystinkie|r", 13, { 0.78, 0.66, 0.70 })
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -6)
	w.title, w.subtitle = title, sub

	local close = FlatButton(w, "x", 22, function() w:Hide() end)
	close:SetPoint("TOPRIGHT", -12, -12)

	local reload = FlatButton(w, "Reload to apply *", 150, function() ReloadUI() end)
	reload:SetPoint("RIGHT", close, "LEFT", -8, 0)
	reload.bg:SetColorTexture(BRAND.orange[1] * 0.75, BRAND.orange[2] * 0.75, BRAND.orange[3] * 0.75, 1)
	reload:SetScript("OnEnter", nil)
	reload:SetScript("OnLeave", nil)
	reload:SetShown(needsReload)
	O.reloadButton = reload

	local nav = CreateFrame("Frame", nil, w)
	nav:SetPoint("TOPLEFT", 10, -(HEADER_H + 10))
	nav:SetPoint("BOTTOMLEFT", 10, 10)
	nav:SetWidth(150)
	Flat(nav, 0.08, 0.07, 0.05, 1)

	local scroll = CreateFrame("ScrollFrame", nil, w)
	scroll:SetPoint("TOPLEFT", nav, "TOPRIGHT", 10, 0)
	scroll:SetPoint("BOTTOMRIGHT", -14, 10)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, (self:GetScrollChild() and self:GetScrollChild():GetHeight() or 0) - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
	end)
	local track = CreateFrame("Frame", nil, w)
	track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
	track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
	track:SetWidth(3)
	local thumb = track:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.6)
	thumb:SetWidth(3)
	scroll:SetScript("OnScrollRangeChanged", nil)
	scroll:SetScript("OnUpdate", function(self)
		local child = self:GetScrollChild()
		local total = child and child:GetHeight() or 1
		local view = self:GetHeight()
		if total <= view + 1 then thumb:Hide() return end
		thumb:Show()
		local h = math.max(20, view * view / total)
		local y = (view - h) * (self:GetVerticalScroll() / (total - view))
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -y)
	end)

	local navButtons, built = {}, {}
	local function SelectPage(i)
		for j, b in ipairs(navButtons) do b:SetSelected(i == j) end
		for _, p in pairs(built) do p:Hide() end
		if not built[i] then
			local page = NewPage(scroll)
			pages[i][2](page)
			built[i] = page
		end
		scroll:SetScrollChild(built[i])
		scroll:SetVerticalScroll(0)
		built[i]:Show()
		if popup then popup:Hide() end
	end
	for i, def in ipairs(pages) do
		local b = FlatButton(nav, def[1], 142, function() SelectPage(i) end)
		b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * NAV_STEP)
		b.text:ClearAllPoints()
		b.text:SetPoint("LEFT", 10, 0)
		navButtons[i] = b
	end
	scroll:SetSize(820 - 150 - 44, WIN_H - HEADER_H - 20)
	SelectPage(1)
	w:Hide()
	return w
end

function ns:ToggleOptions()
	if not O.window then O.window = CreateWindow() end
	O.window:SetShown(not O.window:IsShown())
end

-- Entry in the Blizzard settings panel that opens the window.
function O:Init()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local panel = CreateFrame("Frame")
	local btn = FlatButton(panel, "Open Stinkie UI", 160, function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		if not O.window or not O.window:IsShown() then ns:ToggleOptions() end
	end)
	local logo = panel:CreateTexture(nil, "ARTWORK")
	logo:SetSize(128, 128)
	logo:SetPoint("TOPLEFT", 16, -16)
	logo:SetTexture(ns.MEDIA.logo, "CLAMP", "CLAMP", "TRILINEAR")
	btn:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -12)
	local category = Settings.RegisterCanvasLayoutCategory(panel, "Stinkie UI")
	Settings.RegisterAddOnCategory(category)
end

ns:RegisterModule("Options", O)
