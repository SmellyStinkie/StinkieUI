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
	eb:EnableMouse(true)
	eb:EnableKeyboard(true)
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
	if popup and popup:IsShown() and popup.owner == owner then popup:Hide() return end
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
		-- a click anywhere else closes the list (a click on its own button toggles it below), and
		-- so does the window it opened from closing
		popup:SetScript("OnEvent", function(self)
			if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
		end)
		pcall(popup.RegisterEvent, popup, "GLOBAL_MOUSE_DOWN")
		popup:SetScript("OnUpdate", function(self)
			if self.owner and not self.owner:IsVisible() then self:Hide() end
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
	popup.items, popup.current, popup.onPick, popup.offset, popup.owner = items, current, onPick, 0, owner
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
		if step < 0.01 then return string.format("%.3f", v) end
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
	if not opts.noColor then
		self:Color("Color", function() return getStyle().color end, function(c) getStyle().color = c end)
	end
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

local nameChoices = { { "full", "Both" }, { "first", "First" }, { "last", "Last" } }

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
	page:Choice("Name shows", nameChoices, Getter(cfg, "nameFormat"), Setter(cfg, "nameFormat"))
	page:Check("Name above frame", Getter(cfg, "nameAbove"), Setter(cfg, "nameAbove"))
	page:Check("Show level", Getter(cfg, "showLevel"), Setter(cfg, "showLevel"))
	if unit == "player" or unit == "target" or unit == "focus" then
		page:Check("Group leader icon", Getter(cfg, "leaderIcon"), Setter(cfg, "leaderIcon"))
	end
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
	local function swing() return ns.db.swingTimers end
	page:Header("Swing timers")
	page:Check("Flat look", Getter(swing, "enabled"), Setter(swing, "enabled"), true)
	page:Note("Restyles Blizzard's melee, off-hand and ranged swing timers, on clients that have them. Size and position stay in Edit Mode.", 48)
	page:Check("Only show while attacking", Getter(swing, "hideIdle"), Setter(swing, "hideIdle"))
	page:Note("Hidden unless auto attack or Auto Shot is on, or a swing is still finishing. Works with or without the flat look.", 36)
	page:Color("Melee", Getter(swing, "mainColor"), Setter(swing, "mainColor"))
	page:Color("Off-hand", Getter(swing, "offColor"), Setter(swing, "offColor"))
	page:Color("Ranged", Getter(swing, "rangedColor"), Setter(swing, "rangedColor"))
	page:Check("Show weapon name", Getter(swing, "showLabel"), Setter(swing, "showLabel"))
	page:Check("Show time", Getter(swing, "showTime"), Setter(swing, "showTime"))
	page:TextStyle("Swing timer text", function() return swing().textStyle end)
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
	page:Check("Target marker", Getter(cfg, "marker"), Setter(cfg, "marker"))
	page:Slider("Target marker size", 10, 40, 1, Getter(cfg, "markerSize"), Setter(cfg, "markerSize"))
	page:Check("Group leader icon", Getter(cfg, "leaderIcon"), Setter(cfg, "leaderIcon"))
	page:Check("Castbars", Getter(ccfg, "enabled"), Setter(ccfg, "enabled"), true)
	page:Note("Test mode shows looping casts on enabled castbars.", 22)
	page:Slider("Castbar height", 4, 30, 1, Getter(ccfg, "height"), Setter(ccfg, "height"))
	page:Check("PvP trinket in arena", Getter(cfg, "trinket"), Setter(cfg, "trinket"))
	page:Slider("Trinket size (0 = frame height)", 0, 80, 1, Getter(cfg, "trinketSize"), Setter(cfg, "trinketSize"))
	page:Note("Glow options for these icons are on the PvP Assist page.", 22)
	page:Check("Hide in battlegrounds and Blitz", Getter(cfg, "hideInBattlegrounds"), Setter(cfg, "hideInBattlegrounds"))
	page:Check("Hide in raid groups", Getter(cfg, "hideInRaid"), Setter(cfg, "hideInRaid"))
	page:Note("Big and external defensives show while they're active.", 22)
	page:Position(nil, function() return "party" end)

	page:Column(2)
	page:Header("Text")
	page:Choice("Name shows", nameChoices, Getter(cfg, "nameFormat"), Setter(cfg, "nameFormat"))
	page:Check("Show level", Getter(cfg, "showLevel"), Setter(cfg, "showLevel"))
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
	page:Slider("Gap above the map (square)", -10, 20, 1, Getter(cfg, "headerGap"), Setter(cfg, "headerGap"))
	page:Dropdown("Mail icon (square)", { { "TOPRIGHT", "Top right corner" }, { "TOPLEFT", "Top left corner" },
		{ "BOTTOMRIGHT", "Bottom right corner" }, { "BOTTOMLEFT", "Bottom left corner" }, { "DEFAULT", "Blizzard's spot" } },
		Getter(cfg, "mailCorner"), Setter(cfg, "mailCorner"))
	if ns.IS_FOREVER then
		page:Dropdown("Day / night icon (square)", { { "TOPLEFT", "Top left corner" }, { "TOPRIGHT", "Top right corner" },
			{ "BOTTOMLEFT", "Bottom left corner" }, { "BOTTOMRIGHT", "Bottom right corner" },
			{ "DEFAULT", "Blizzard's spot" }, { "HIDE", "Hidden" } }, Getter(cfg, "dielCorner"), Setter(cfg, "dielCorner"))
	end
	if ns.HAS_FOLIO then
		page:Check("Omnium Folio button", Getter(cfg, "folio"), Setter(cfg, "folio"))
		page:Dropdown("Omnium Folio corner (square)", { { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" },
			{ "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" } }, Getter(cfg, "folioCorner"), Setter(cfg, "folioCorner"))
		page:Slider("Omnium Folio size", 0.4, 1.2, 0.05, Getter(cfg, "folioScale"), Setter(cfg, "folioScale"))
		page:Slider("Omnium Folio distance from corner", 0, 40, 1, Getter(cfg, "folioInset"), Setter(cfg, "folioInset"))
		page:Slider("Omnium Folio X nudge", -30, 30, 1, Getter(cfg, "folioX"), Setter(cfg, "folioX"))
		page:Slider("Omnium Folio Y nudge", -30, 30, 1, Getter(cfg, "folioY"), Setter(cfg, "folioY"))
	end
	page:Choice("Buttons", { { "show", "Show" }, { "mouseover", "Mouseover" }, { "hide", "Hide" } }, Getter(cfg, "buttons"), Setter(cfg, "buttons"))
	page:Note(ns.HAS_FOLIO and "Tracking, addon list, zoom and addon minimap buttons. Mail and the Omnium Folio have their own options."
		or "Tracking, addon list, zoom and addon minimap buttons. Mail has its own option.", 36)
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

local function BuildPlateGeneralPage(page)
	local function cfg() return ns.db.nameplates end
	local function scfg() return ns.db.nameplates.stacking end
	page:Column(1)
	page:Header("Nameplates")
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Check("Add \226\128\166 when a name is shortened", Getter(cfg, "nameEllipsis"), Setter(cfg, "nameEllipsis"))
	page:Header("Stacking (plates pushing each other up)")
	page:Check("Stack enemy nameplates", Getter(scfg, "enemies"), Setter(scfg, "enemies"))
	page:Check("Stack friendly nameplates", Getter(scfg, "friendly"), Setter(scfg, "friendly"))
	page:Note("Off: plates stay over their units and may overlap. On: they move apart, upward.", 36)
	page:Slider("Stacking box height (0 = auto)", 0, 80, 1, Getter(scfg, "boxHeight"), Setter(scfg, "boxHeight"))
	page:Note("How much room each plate claims. Lower = stacked plates climb less but sit closer (castbars and auras may overlap). Auto = bar + castbar + 24.", 48)
	page:Slider("Vertical spacing (0 = game default)", 0, 2, 0.05, Getter(scfg, "spacing"), Setter(scfg, "spacing"))
	page:Slider("Slide speed (0 = game default)", 0, 0.2, 0.005, Getter(scfg, "speed"), Setter(scfg, "speed"))
	page:Slider("Distance kept from screen top (0 = default)", 0, 0.5, 0.01, Getter(scfg, "topInset"), Setter(scfg, "topInset"))
	page:Note("These three are older game settings that may no longer exist; /stinkie plates shows which ones this game version has.", 36)
end

local function BuildPlateEnemyPage(page)
	local function cfg() return ns.db.nameplates end
	page:Column(1)
	page:Header("Enemy nameplates")
	page:Slider("Width", 40, 300, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Health height", 2, 40, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Slider("Castbar height", 4, 30, 1, Getter(cfg, "castHeight"), Setter(cfg, "castHeight"))
	page:Check("Show level", Getter(cfg, "showLevel"), Setter(cfg, "showLevel"))
	page:Check("Health percent", Getter(cfg, "showHealthText"), Setter(cfg, "showHealthText"))
	page:Check("Name inside the bar", Getter(cfg, "nameInBar"), Setter(cfg, "nameInBar"))
	page:Choice("Name shows", nameChoices, Getter(cfg, "nameFormat"), Setter(cfg, "nameFormat"))
	page:Note("Stormwind Guard: First is Stormwind, Last is Guard. Names the game hides in PvP stay whole.", 36)
	page:Slider("Max name length (0 = full)", 0, 40, 1, Getter(cfg, "nameMaxChars"), Setter(cfg, "nameMaxChars"))
	page:Header("Clicking")
	page:Slider("Extra click area, sides", 0, 30, 1, Getter(cfg, "clickPadX"), Setter(cfg, "clickPadX"))
	page:Slider("Extra click area, top/bottom", 0, 20, 1, Getter(cfg, "clickPadY"), Setter(cfg, "clickPadY"))
	page:Column(2)
	page:TextStyle("Name", function() return cfg().nameStyle end, { classColor = true })
	page:TextStyle("Health text", function() return cfg().healthStyle end)
	page:TextStyle("Castbar text", function() return cfg().castStyle end)
end

local function BuildPlateFriendlyPage(page)
	local function cfg() return ns.db.nameplates end
	page:Column(1)
	page:Header("Friendly nameplates")
	page:Slider("Width", 10, 300, 1, Getter(cfg, "friendlyWidth"), Setter(cfg, "friendlyWidth"))
	page:Slider("Health height", 1, 40, 1, Getter(cfg, "friendlyHeight"), Setter(cfg, "friendlyHeight"))
	page:Check("Show level", Getter(cfg, "friendlyShowLevel"), Setter(cfg, "friendlyShowLevel"))
	page:Check("Health percent", Getter(cfg, "friendlyHealthText"), Setter(cfg, "friendlyHealthText"))
	page:Check("Name on the health bar", Getter(cfg, "friendlyNameInBar"), Setter(cfg, "friendlyNameInBar"))
	page:Choice("Name shows", nameChoices, Getter(cfg, "friendlyNameFormat"), Setter(cfg, "friendlyNameFormat"))
	page:Slider("Max name length (0 = full)", 0, 40, 1, Getter(cfg, "friendlyNameMaxChars"), Setter(cfg, "friendlyNameMaxChars"))
	page:Slider("Lower friendly plates by", 0, 60, 1, Getter(cfg, "friendlyLower"), Setter(cfg, "friendlyLower"))
	page:Note("Makes room above them for quest and interact icons.", 22)
	page:Check("Click-through", Getter(cfg, "friendlyClickThrough"), Setter(cfg, "friendlyClickThrough"))
	page:Check("Your target gets the full plate and target border", Getter(cfg, "friendlyTargetFull"), Setter(cfg, "friendlyTargetFull"))
	page:Column(2)
	page:TextStyle("Name", function() return cfg().friendlyNameStyle end, { classColor = true })
	page:TextStyle("Health text", function() return cfg().friendlyHealthStyle end)
end

local function BuildPlateTargetPage(page)
	local function cfg() return ns.db.nameplates end
	local function hcfg() return ns.db.nameplates.highlight end
	page:Column(1)
	page:Header("Target highlight")
	page:Slider("Border thickness", 1, 6, 1, Getter(hcfg, "thickness"), Setter(hcfg, "thickness"))
	page:Slider("Border outside the bar", 0, 6, 1, Getter(hcfg, "outset"), Setter(hcfg, "outset"))
	page:Color("Border color", Getter(hcfg, "color"), Setter(hcfg, "color"))
	page:Check("Show > < around the target", Getter(hcfg, "arrows"), Setter(hcfg, "arrows"))
	page:Slider("Arrow size", 8, 80, 1, Getter(hcfg, "arrowSize"), Setter(hcfg, "arrowSize"))
	page:Slider("Target plate scale", 1, 1.6, 0.05, function() return hcfg().scale or 1 end, Setter(hcfg, "scale"))
	page:Header("Threat")
	page:Check("Threat % on your enemy target", Getter(cfg, "threatText"), Setter(cfg, "threatText"))
	page:Choice("Spot above the health bar", { { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" } }, Getter(cfg, "threatSide"), Setter(cfg, "threatSide"))
	page:Slider("Yellow from (%)", 1, 99, 1, Getter(cfg, "threatYellow"), Setter(cfg, "threatYellow"))
	page:Slider("Orange from (%)", 1, 99, 1, Getter(cfg, "threatOrange"), Setter(cfg, "threatOrange"))
	page:Note("Green to start, red when you hold aggro. Orange at 100% means you have aggro but someone is about to take it. It only shows while the game gives a number. Where the game hides the number, the color follows its threat level instead.", 62)
	page:TextStyle("Threat text", function() return cfg().threatStyle end, { noColor = true })
end

local function BuildPlateIconsPage(page)
	local function cfg() return ns.db.nameplates end
	page:Column(1)
	page:Header("Target markers")
	page:Check("Above enemy nameplates", Getter(cfg, "marker"), Setter(cfg, "marker"))
	page:Slider("Enemy marker size", 12, 64, 1, Getter(cfg, "markerSize"), Setter(cfg, "markerSize"))
	page:Check("Above friendly nameplates", Getter(cfg, "friendlyMarker"), Setter(cfg, "friendlyMarker"))
	page:Slider("Friendly marker size", 12, 64, 1, Getter(cfg, "friendlyMarkerSize"), Setter(cfg, "friendlyMarkerSize"))
	page:Header("Healers and elites")
	page:Check("Red cross over enemy healers", Getter(cfg, "enemyHealerIcon"), Setter(cfg, "enemyHealerIcon"))
	page:Slider("Enemy cross size", 6, 100, 1, Getter(cfg, "healerSize"), Setter(cfg, "healerSize"))
	page:Check("Green cross over friendly healers", Getter(cfg, "healerIcon"), Setter(cfg, "healerIcon"))
	page:Slider("Friendly cross size", 6, 100, 1, Getter(cfg, "friendlyHealerSize"), Setter(cfg, "friendlyHealerSize"))
	page:Check("Inspect nearby players to find healers", Getter(cfg, "inspectHealers"), Setter(cfg, "inspectHealers"))
	page:Note("Outside a group the game doesn't say who is a healer, so Stinkie UI inspects nearby players one at a time (out of combat, not in arena or battlegrounds).", 62)
	page:Check("Elite / boss star", Getter(cfg, "eliteIcon"), Setter(cfg, "eliteIcon"))
	page:Slider("Star size", 8, 30, 1, Getter(cfg, "eliteSize"), Setter(cfg, "eliteSize"))
	page:Column(2)
	page:Header("Spec icons")
	page:Check("Above enemy players", Getter(cfg, "specIcons"), Setter(cfg, "specIcons"))
	page:Check("Above friendly players", Getter(cfg, "specIconsFriendly"), Setter(cfg, "specIconsFriendly"))
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
	page:Note("The icon over the unit you soft-target (quest, talk, loot).", 22)
	page:Header("Flag / orb carriers")
	page:Check("Carrier icon (battlegrounds)", Getter(cfg, "carrierIcon"), Setter(cfg, "carrierIcon"))
	page:Slider("Carrier icon size", 16, 120, 1, Getter(cfg, "carrierSize"), Setter(cfg, "carrierSize"))
	page:Choice("Carrier icon position", { { "ABOVE", "Above name" }, { "LEFT", "Left of bar" }, { "TOP", "Top (old)" } },
		Getter(cfg, "carrierAnchor"), Setter(cfg, "carrierAnchor"))
	page:Slider("Carrier X offset", -60, 60, 1, Getter(cfg, "carrierX"), Setter(cfg, "carrierX"))
	page:Slider("Carrier Y offset", -60, 60, 1, Getter(cfg, "carrierY"), Setter(cfg, "carrierY"))
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
	page:Slider("Width (x normal plate)", 0.5, 3, 0.05, Getter(imp, "widthScale"), Setter(imp, "widthScale"))
	page:Slider("Height (x normal plate)", 0.5, 4, 0.05, Getter(imp, "heightScale"), Setter(imp, "heightScale"))
	page:Check("Border in the same color", Getter(imp, "border"), Setter(imp, "border"))
	page:Slider("Extra click area", 0, 40, 1, Getter(imp, "clickPad"), Setter(imp, "clickPad"))
	page:TextList("Units", 140, function() return table.concat(imp().units, "\n") end,
		function(t) imp().units = SplitLines(t) end,
		"English unit names or NPC IDs, one per line. Important plates are drawn on top, at the size above.")
	page:Note("Rated PvP can hide unit names and NPC IDs from addons. Then the list above can't match, and nothing can recolor or resize the plate. What still works there: a big glowing icon for units carrying one of these auras.", 62)
	page:Check("Aura icon on important units (works when names are hidden)", Getter(imp, "auraMarker"), Setter(imp, "auraMarker"))
	page:Slider("Aura icon size", 16, 80, 1, Getter(imp, "auraSize"), Setter(imp, "auraSize"))
	page:TextList("Auras (spell IDs)", 60, function() return table.concat(imp().auraIDs or {}, "\n") end,
		function(t) imp().auraIDs = SplitLines(t); if ns.Nameplates.RefreshImportantAuras then ns.Nameplates.RefreshImportantAuras() end end,
		"One spell ID per line. 8178 = Grounding Totem Effect. /stinkie plates on a targeted totem shows whether its name is hidden.")
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
	page:Check("Keybinds off: show them when hovering a bar", Getter(cfg, "hotkeysHover"), Setter(cfg, "hotkeysHover"))
	page:Check("Lock buttons", ns.ActionBars.ButtonsLocked, ns.ActionBars.SetButtonsLocked)
	page:Note("Stops buttons being dragged off the bars. This is the game's own Lock Action Bars setting. Shift still moves them while locked.", 48)
	page:Slider("Icon zoom (shared with cooldowns)", 0, 0.2, 0.01, function() return ns.db.cooldowns.iconZoom end,
		function(v) ns.db.cooldowns.iconZoom = v end)
	page:Check("Show cooldown numbers", Getter(cfg, "cooldownNumbers"), Setter(cfg, "cooldownNumbers"))
	page:Slider("Cooldown number size", 0.5, 2, 0.05, Getter(cfg, "cooldownScale"), Setter(cfg, "cooldownScale"))
	page:Header("Show only on mouseover")
	for _, def in ipairs(ns.ActionBars.BARS) do
		page:Check(def[2], function() return cfg().mouseover[def[1]] and true or false end,
			function(v) cfg().mouseover[def[1]] = v and true or false end) -- nil would bring the default back on reload
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
	page:Check("Social button beside the chat tabs", Getter(cfg, "socialByTabs"), Setter(cfg, "socialByTabs"), true)
	page:Header("Tabs")
	page:Check("Flash tabs on new messages", Getter(cfg, "flashTabs"), Setter(cfg, "flashTabs"), true)
	page:Check("Only flash for messages from players", Getter(cfg, "flashPlayerOnly"), Setter(cfg, "flashPlayerOnly"))
	page:Choice("Whispers show in", { { "both", "Both" }, { "main", "Main tab" }, { "tab", "Own tab" } }, Getter(cfg, "whisperDisplay"), Setter(cfg, "whisperDisplay"))
	page:Note("Character and Battle.net whispers. Both: a tab for each person, plus the main tab, so closing a tab loses nothing.", 36)
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
	local function auto() return ns.db.misc.auto end
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
	page:Header("Error messages")
	page:Check("Hide error messages", Getter(auto, "hideErrors"), Setter(auto, "hideErrors"))
	page:Note("Hides the red text like Not enough mana, and its voice line. Yellow quest progress text stays.", 36)
	page:Header("Quests")
	page:Check("Accept quests", Getter(auto, "questAccept"), Setter(auto, "questAccept"))
	page:Check("Turn in quests", Getter(auto, "questTurnIn"), Setter(auto, "questTurnIn"))
	page:Note("Hold Shift while talking to an NPC to do it yourself. You still pick from a choice of rewards, and quests that cost gold or currency or flag you for PvP are left to you.", 62)
	page:Header("Vendors")
	page:Check("Repair", Getter(auto, "repair"), Setter(auto, "repair"))
	page:Check("Use guild funds first", Getter(auto, "repairGuild"), Setter(auto, "repairGuild"))
	page:Check("Sell junk", Getter(auto, "sellJunk"), Setter(auto, "sellJunk"))
	page:Header("Battlegrounds")
	page:Check("Release when you die", Getter(auto, "releasePvP"), Setter(auto, "releasePvP"))
	page:Note("Battlegrounds and Blitz only. With a soulstone or similar, the choice stays yours.", 36)
	page:Check("Say in chat what was done", Getter(auto, "announce"), Setter(auto, "announce"))
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
	page:Check("Big DEAD / FEIGN text", Getter(cfg, "deadText"), Setter(cfg, "deadText"))
	page:Slider("DEAD text size (share of frame height)", 0.3, 1, 0.05, Getter(cfg, "deadSize"), Setter(cfg, "deadSize"))
	page:Slider("My target: border thickness", 1, 8, 1, Getter(cfg, "targetBorder"), Setter(cfg, "targetBorder"))
	page:Color("My target: border color", Getter(cfg, "targetColor"), Setter(cfg, "targetColor"))
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
	page:Choice("Name shows", nameChoices, Getter(cfg, "nameFormat"), Setter(cfg, "nameFormat"))
	page:Check("Show level", Getter(cfg, "showLevel"), Setter(cfg, "showLevel"))
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
	page:Check("Hide Blizzard raid frames in Blitz and battlegrounds", function() return ns.db.bgWidgets.hideRaidFrames end, function(v) ns.db.bgWidgets.hideRaidFrames = v end)
	page:Note("Both sides. Not in 40-player battlegrounds.", 22)
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
	page:Choice("Icon type", { { "role", "Role" }, { "spec", "Spec / class" } }, Getter(cfg, "iconMode"), Setter(cfg, "iconMode"))
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
	local function allies() return ns.db.bgAllies end
	page:Header("Buffs on allies")
	page:Check("Show buffs", Getter(allies, "buffs"), Setter(allies, "buffs"))
	page:Check("Only buffs I cast", Getter(allies, "buffsMine"), Setter(allies, "buffsMine"))
	page:Slider("Buffs shown", 1, ns.BGEnemies.MAX_BUFFS, 1, Getter(allies, "buffMax"), Setter(allies, "buffMax"))
	page:Slider("Buff icon size", 10, 40, 1, Getter(allies, "buffSize"), Setter(allies, "buffSize"), true)
	page:Choice("Buffs side", { { "LEFT", "Left" }, { "RIGHT", "Right" } }, Getter(allies, "buffSide"), Setter(allies, "buffSide"))
	page:Note("Always the Allies block, whichever side you're editing. Test mode shows your own buffs on each row.", 36)
	page:TextStyle("Horde / Alliance title", function() return cfg().headerStyle end)
	page:TextStyle("Name text", function() return cfg().nameStyle end)
	page:TextStyle("Health text", function() return cfg().healthStyle end)
	page:TextStyle("Spec text", function() return cfg().specStyle end)
end

local function BuildBGScorePage(page)
	local function cfg() return ns.db.bgWidgets end
	local function fc() return ns.db.flagCap end
	page:Column(1)
	page:Header("Battleground score")
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"))
	page:Note("Only inside battlegrounds. Elsewhere these stay where Blizzard puts them.", 36)
	page:Button("Test mode on / off", function()
		local on = not ns.BGWidgets.testMode
		ns.BGWidgets:SetTestMode(on)
		if ns.FlagCap then ns.FlagCap:SetTestMode(on) end
	end)
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
	page:Header("Capture / cart progress")
	page:Note("The progress widgets Blizzard normally puts under the minimap (cart, capture bars).", 36)
	page:Check("Move it", Getter(cfg, "moveCapture"), Setter(cfg, "moveCapture"))
	page:Slider("Size", 0.5, 2, 0.05, Getter(cfg, "captureScale"), Setter(cfg, "captureScale"))
	page:Position("Position", function() return "bgCapture" end)
	page:Header("Return to Graveyard button")
	page:Check("Move it", Getter(cfg, "moveGhost"), Setter(cfg, "moveGhost"))
	page:Slider("Size", 0.5, 2, 0.05, Getter(cfg, "ghostScale"), Setter(cfg, "ghostScale"))
	page:Position("Position", function() return "bgGhost" end)
	page:Header("Arena / Solo Shuffle info")
	page:Note("Blizzard's top-center info in arenas: round (3 of 6), match timer and the like.", 36)
	page:Check("Move it", Getter(cfg, "moveArena"), Setter(cfg, "moveArena"))
	page:Slider("Size", 0.5, 2.5, 0.05, Getter(cfg, "arenaScale"), Setter(cfg, "arenaScale"))
	page:Check("Stinkie UI font", Getter(cfg, "arenaText"), Setter(cfg, "arenaText"))
	page:Slider("Text size", 8, 32, 1, Getter(cfg, "arenaTextSize"), Setter(cfg, "arenaTextSize"))
	page:Position("Position", function() return "arenaInfo" end)
	page:Note("Unlock frames (/stinkie unlock) to drag the boxes. They're easiest to place inside a battleground, where the real widgets show.", 48)

	page:Column(2)
	page:Header("Flag Cap Indicator")
	page:Note("Warsong Gulch and Twin Peaks: a bar for each flag someone is carrying (hidden when it's at home or dropped), with the carrier, yards from their cap spot, and ON CAP when they're standing on it.", 62)
	page:Check("Enabled", Getter(fc, "enabled"), Setter(fc, "enabled"))
	page:Button("Test mode on / off", function() if ns.FlagCap then ns.FlagCap:SetTestMode(not ns.FlagCap.testMode) end end)
	page:Check("Sit under the score (locked there, same width as the score bar)", Getter(fc, "attach"), Setter(fc, "attach"))
	page:Slider("Gap under the score", -40, 20, 1, Getter(fc, "attachY"), Setter(fc, "attachY"))
	page:Position("Position (not under the score)", function() return "flagCap" end)
	page:Slider("Size", 0.5, 2.5, 0.05, Getter(fc, "scale"), Setter(fc, "scale"))
	page:Slider("Width (when not under the score)", 120, 500, 1, Getter(fc, "width"), Setter(fc, "width"))
	page:Slider("Height", 14, 48, 1, Getter(fc, "height"), Setter(fc, "height"))
	page:Choice("Two flags", { { "STACK", "One under the other" }, { "SIDE", "Side by side" } }, Getter(fc, "layout"), Setter(fc, "layout"))
	page:Check("Side by side: my score shows Horde on the left", Getter(fc, "swapSides"), Setter(fc, "swapSides"))
	page:Slider("Spacing", 0, 20, 1, Getter(fc, "spacing"), Setter(fc, "spacing"))
	page:Check("Carrier names", Getter(fc, "names"), Setter(fc, "names"))
	page:Check("Class-colored names", Getter(fc, "classColors"), Setter(fc, "classColors"))
	page:Check("Realm names", Getter(fc, "realms"), Setter(fc, "realms"))
	page:Check("Distance to cap (yards)", Getter(fc, "distance"), Setter(fc, "distance"))
	page:Check("Yards instead of NOT ON CAP", Getter(fc, "onlyYardsWhenNotOnCap"), Setter(fc, "onlyYardsWhenNotOnCap"))
	page:Check("Seconds until they reach the cap", Getter(fc, "eta"), Setter(fc, "eta"))
	page:Slider("On cap within (yards)", 3, 20, 1, Getter(fc, "radius"), Setter(fc, "radius"))
	page:Check("Flash ON CAP", Getter(fc, "flashOnCap"), Setter(fc, "flashOnCap"))
	page:Color("ON CAP color", Getter(fc, "onCapColor"), Setter(fc, "onCapColor"))
	page:Color("NOT ON CAP color", Getter(fc, "notOnCapColor"), Setter(fc, "notOnCapColor"))
	page:Slider("Background opacity", 0, 1, 0.05, Getter(fc, "bgAlpha"), Setter(fc, "bgAlpha"))
	page:Note("The game doesn't say where cap spots are, so they're learned: each flag shows up where it's picked up (its base). The first time you play a map, distance appears once both flags have been picked up; after that it's remembered. /stinkie flags shows what the game reports, /stinkie flags reset relearns a map.", 90)
	page:TextStyle("Name and distance text", function() return fc().textStyle end, {})
	page:TextStyle("Status text", function() return fc().statusStyle end, {})
end

local function BuildBGTimersPage(page)
	local function cfg() return ns.db.bgTimers end
	page:Column(1)
	page:Header("BG Timers")
	page:Note("Bars for assaulted bases, the predicted winner and your next resurrection. Battlegrounds and Blitz only.", 36)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"))
	page:Button("Test mode on / off", function() ns.BGTimers:SetTestMode(not ns.BGTimers.testMode) end)
	page:Header("Timers")
	page:Check("Base captures", Getter(cfg, "nodes"), Setter(cfg, "nodes"))
	page:Note("Starts when a base is assaulted; gone when it turns or is defended. Uses the seconds set for the map (right).", 36)
	page:Check("Predicted winner and final score", Getter(cfg, "win"), Setter(cfg, "win"))
	page:Note("From each team's points per second over the last 30 seconds, on maps with a resource score bar.", 36)
	page:Check("Resurrection (while you're dead)", Getter(cfg, "respawn"), Setter(cfg, "respawn"))
	page:Header("Look")
	page:Slider("Width", 100, 400, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Height", 10, 40, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Slider("Spacing", 0, 12, 1, Getter(cfg, "spacing"), Setter(cfg, "spacing"))
	page:Choice("Grow", { { "DOWN", "Down" }, { "UP", "Up" } }, Getter(cfg, "growth"), Setter(cfg, "growth"))
	page:Slider("Background opacity", 0, 1, 0.05, Getter(cfg, "bgAlpha"), Setter(cfg, "bgAlpha"))
	page:Color("Alliance", Getter(cfg, "allianceColor"), Setter(cfg, "allianceColor"))
	page:Color("Horde", Getter(cfg, "hordeColor"), Setter(cfg, "hordeColor"))
	page:Color("Unknown team / resurrection", Getter(cfg, "neutralColor"), Setter(cfg, "neutralColor"))
	page:Position(nil, function() return "bgTimers" end)
	page:Column(2)
	page:TextList("Base capture time per map", 150, function() return table.concat(cfg().durations, "\n") end, function(text)
		local list = {}
		for line in text:gmatch("[^\r\n]+") do
			line = strtrim(line)
			if line ~= "" then table.insert(list, line) end
		end
		cfg().durations = list
	end, "One map per line: Map name = seconds. Maps not listed get no base timers (maps without bases, like Warsong Gulch, need nothing).")
	page:Note("Map names as the game shows them on entry. /stinkie timers inside a battleground prints the map name and what each base icon reports, to add or correct a map.", 62)
	page:TextStyle("Bar text", function() return cfg().textStyle end, {})
end

local function BuildMatchHistoryPage(page)
	local function cfg() return ns.db.matchHistory end
	page:Column(1)
	page:Header("Match History")
	page:Note("Every match is saved when it ends: result, rating and MMR before and after, map, length, comps, your spec, hero talents, PvP talents and talent loadout, and every player's full scoreboard line.", 62)
	page:Button("Open Match History (/mh)", function() ns.MatchRecorder.Open() end, 220)
	page:Button("Open Match Stats (/mh stats)", function() ns.MatchRecorder.Open("stats") end, 220)
	page:Check("Save matches", Getter(cfg, "enabled"), Setter(cfg, "enabled"))
	page:Check("One chat line after each match", Getter(cfg, "announce"), Setter(cfg, "announce"))
	page:Check("Save my talent loadout with each match", Getter(cfg, "talents"), Setter(cfg, "talents"))
	page:Header("Save these")
	page:Check("Rated arena (2v2, 3v3)", Getter(cfg, "arena"), Setter(cfg, "arena"))
	page:Check("Solo Shuffle", Getter(cfg, "shuffle"), Setter(cfg, "shuffle"))
	page:Check("Blitz", Getter(cfg, "blitz"), Setter(cfg, "blitz"))
	page:Check("Rated battlegrounds", Getter(cfg, "rbg"), Setter(cfg, "rbg"))
	page:Header("Unrated (off by default)")
	page:Check("Skirmishes", Getter(cfg, "skirmish"), Setter(cfg, "skirmish"))
	page:Check("Unrated battlegrounds", Getter(cfg, "battleground"), Setter(cfg, "battleground"))
	page:Check("Unrated Solo Shuffle and Blitz", Getter(cfg, "unrated"), Setter(cfg, "unrated"))
	page:Check("Brawls", Getter(cfg, "brawl"), Setter(cfg, "brawl"))
	page:Header("Import")
	page:Note("Bring in your Rated Tracker history. Rated Tracker has to be enabled for the session you import in (an addon can only read another addon's data while it's loaded); disable it afterwards. Its own files aren't changed, and matches already here are skipped.", 76)
	page:Button("Import Rated Tracker history", function() ns.MatchRecorder.Import() end, 240)
	page:Column(2)
	page:Header("Memory")
	page:Slider("Window loads the last ... months (0 = all)", 0, 60, 1, Getter(cfg, "loadMonths"), Setter(cfg, "loadMonths"))
	page:Note("Older matches stay saved; the window's Load all button brings them in for that session. Fewer loaded matches = less memory while the window is open.", 50)
	page:Note("The history window is its own addon (StinkieUI_History) and only loads when you open it. Until then a new match costs a few hundred bytes. After you close the window its decoded data is released; the archive itself stays loaded until your next /reload.", 90)
	page:Note("Matches are stored as compact text with names, maps and loadouts kept once each: about 0.5 KB per arena match and 1-1.5 KB per Blitz match.", 50)
	page:Header("Match Stats")
	page:Note("Win rates by map, enemy comp, enemy spec, your team comp, teammate, your spec and hero talents, enemy MMR, match length, time of day and day of week, with a 95% range on each so you can tell real differences from luck. Rating trend, streaks and CSV export.", 90)
end

local function BuildQueueInfoPage(page)
	local function cfg() return ns.db.queueInfo end
	page:Column(1)
	page:Header("Queue Time & MMR")
	page:Note("While you're queued: each queue's bracket, how long you've waited, Blizzard's estimate, and your MMR there.", 36)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"))
	page:Button("Test mode on / off", function() ns.QueueInfo:SetTestMode(not ns.QueueInfo.testMode) end)
	page:Check("Estimated wait", Getter(cfg, "estimate"), Setter(cfg, "estimate"))
	page:Check("MMR", Getter(cfg, "mmr"), Setter(cfg, "mmr"))
	page:Check("MMR change from your last game (+73 green / -40 red)", Getter(cfg, "mmrChange"), Setter(cfg, "mmrChange"))
	page:Check("Rating (CR)", Getter(cfg, "rating"), Setter(cfg, "rating"))
	page:Check("Spec icon (the spec you're queued as)", Getter(cfg, "specIcon"), Setter(cfg, "specIcon"))
	page:Check("\"Queued as\" line on top", Getter(cfg, "header"), Setter(cfg, "header"))
	page:Check("Hide while in an arena or battleground", Getter(cfg, "hideInPvP"), Setter(cfg, "hideInPvP"))
	page:Note("The game only shows MMR at the end of a match, so this is your MMR after your last match in that bracket on this character (recorded or imported), and how much that match changed it. Solo Shuffle and Blitz use the spec you queued as. It says 'MMR unknown' until you play a match there (per spec for Shuffle and Blitz), and N/A where the game gives no MMR (unrated queues, or a bracket whose matches came without one).", 76)
	page:Header("Size")
	page:Slider("Size", 0.5, 2.5, 0.05, Getter(cfg, "scale"), Setter(cfg, "scale"))
	page:Slider("Width", 150, 600, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Row height", 12, 48, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Slider("Spacing", 0, 12, 1, Getter(cfg, "spacing"), Setter(cfg, "spacing"))
	page:Position(nil, function() return "queueInfo" end)
	page:Column(2)
	page:Header("Background")
	page:Check("Background", Getter(cfg, "background"), Setter(cfg, "background"))
	page:Check("1px border", Getter(cfg, "border"), Setter(cfg, "border"))
	page:Color("Color", Getter(cfg, "bgColor"), Setter(cfg, "bgColor"))
	page:Slider("Opacity", 0, 1, 0.05, Getter(cfg, "bgAlpha"), Setter(cfg, "bgAlpha"))
	page:TextStyle("Bracket text", function() return cfg().labelStyle end, {})
	page:TextStyle("Time and MMR text", function() return cfg().textStyle end, {})
end

local function BuildCharacterPage(page)
	local function cfg() return ns.db.character end
	local function bgChanged() if ns.CharacterSheet then ns.CharacterSheet:Refresh() end end
	page:Column(1)
	page:Header("Character Sheet")
	page:Note("Adds to Blizzard's character window: item details beside each slot, a background behind your character, stat highlighting and exact item levels. Open your character (C) to see changes.", 62)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"))
	page:Check("Same look when inspecting others", Getter(cfg, "inspect"), Setter(cfg, "inspect"))
	page:Header("Look and size")
	page:Check("Flat look (no frame art, portrait or gradients; 1px borders)", Getter(cfg, "flat"), Setter(cfg, "flat"), true)
	page:Color("Window color", Getter(cfg, "frameColor"), Setter(cfg, "frameColor"))
	page:Slider("Window opacity", 0, 1, 0.05, Getter(cfg, "frameAlpha"), Setter(cfg, "frameAlpha"))
	page:Slider("Character window size", 0.7, 2, 0.05, Getter(cfg, "scale"), Setter(cfg, "scale"))
	page:Slider("Inspect window size", 0.7, 2, 0.05, Getter(cfg, "inspectScale"), Setter(cfg, "inspectScale"))
	page:Check("Drag corner to resize (bottom right)", Getter(cfg, "resizer"), Setter(cfg, "resizer"))
	page:Check("Roomier layout (bigger character area)", Getter(cfg, "roomy"), Setter(cfg, "roomy"))
	page:Slider("Extra width", 0, 200, 1, Getter(cfg, "extraWidth"), Setter(cfg, "extraWidth"))
	page:Slider("Extra height", 0, 160, 1, Getter(cfg, "extraHeight"), Setter(cfg, "extraHeight"))
	page:Slider("Space between weapons", 5, 120, 1, Getter(cfg, "weaponGap"), Setter(cfg, "weaponGap"))
	page:Note("Item borders take the item's quality color. Turning the flat look off needs a reload.", 36)
	page:Header("Background")
	page:Dropdown("Background", function() return ns.CharacterSheet.BackgroundChoices() end, Getter(cfg, "background"), function(v) cfg().background = v; bgChanged() end)
	page:Check("Only warband camps I own", Getter(cfg, "ownedOnly"), Setter(cfg, "ownedOnly"))
	page:EditText("Custom texture or atlas", Getter(cfg, "customTexture"), function(v) cfg().customTexture = v; bgChanged() end)
	page:Note("For Custom: an atlas name or a file path / ID, e.g. Interface\\Glues\\... Warband camps are cropped to fit, not stretched.", 48)
	page:Check("Arrow under the trinkets to hide / show stats, titles and sets", Getter(cfg, "collapseButton"), function(v) cfg().collapseButton = v; bgChanged() end)
	page:Check("Name and level centered over the character", Getter(cfg, "centerHeader"), function(v) cfg().centerHeader = v; bgChanged() end)
	page:Check("Background across the whole window (flat look)", Getter(cfg, "wideBackground"), function(v) cfg().wideBackground = v; bgChanged() end)
	page:Slider("Darken background (character area)", 0, 0.9, 0.05, Getter(cfg, "dim"), function(v) cfg().dim = v; bgChanged() end)
	page:Slider("Darken background (names and stats)", 0, 1, 0.05, Getter(cfg, "outerDim"), function(v) cfg().outerDim = v; bgChanged() end)
	page:Header("Item details")
	page:Check("Compact (less busy)", Getter(cfg, "compact"), Setter(cfg, "compact"))
	page:Note("Drops the set name from items (Gladiator's Amulet -> Amulet), short track (C1/6 = Champion 1/6), and puts the weapons' text under the weapons.", 50)
	page:Slider("Longest item name (characters, 0 = no limit)", 0, 40, 1, Getter(cfg, "nameChars"), Setter(cfg, "nameChars"))
	page:Check("Enchants as an icon (check / red cross) on the item level line", Getter(cfg, "enchantIcons"), Setter(cfg, "enchantIcons"))
	page:Check("No text on shirt and tabard", Getter(cfg, "hideShirt"), Setter(cfg, "hideShirt"))
	page:Choice("First line", { { "name", "Item name" }, { "track", "Upgrade track" }, { "none", "Nothing" } }, Getter(cfg, "line1"), Setter(cfg, "line1"))
	page:Note("Item level, PvP item level and the upgrade track (e.g. Mythic 6/6, in the track's color) share one line. With Upgrade track it's the first line, in place of the name; items without a track show their name.", 62)
	page:Check("Item level", Getter(cfg, "ilvl"), Setter(cfg, "ilvl"))
	page:Check("Upgrade track on the item level line (with names)", Getter(cfg, "track"), Setter(cfg, "track"))
	page:Check("PvP item level (only on gear that scales up in PvP)", Getter(cfg, "pvp"), Setter(cfg, "pvp"))
	page:Check("Durability line beside each item (green, yellow, red)", Getter(cfg, "durability"), Setter(cfg, "durability"))
	page:Slider("Durability line width", 1, 6, 1, Getter(cfg, "durabilityWidth"), Setter(cfg, "durabilityWidth"))
	page:Check("Gems beside each icon, on the outside (empty sockets too)", Getter(cfg, "gems"), Setter(cfg, "gems"))
	page:Slider("Gem icon size", 8, 28, 1, Getter(cfg, "gemSize"), Setter(cfg, "gemSize"))
	page:Check("Enchants", Getter(cfg, "enchants"), Setter(cfg, "enchants"))
	page:Check("Enchant names (when not shown as an icon)", Getter(cfg, "enchantNames"), Setter(cfg, "enchantNames"))
	page:Check("Enchant Missing in red", Getter(cfg, "missing"), Setter(cfg, "missing"))
	page:Note("Checked slots: helm, shoulders, chest, legs, boots, rings and weapons (an off-hand only if it's a weapon).", 36)
	page:Slider("Text width", 80, 300, 1, Getter(cfg, "textWidth"), Setter(cfg, "textWidth"))
	page:Column(2)
	page:Header("Stats and item level")
	page:Check("Hovering a stat highlights it and the items with it", Getter(cfg, "statHighlight"), Setter(cfg, "statHighlight"))
	page:Color("Highlight color", Getter(cfg, "highlightColor"), Setter(cfg, "highlightColor"))
	page:Note("Critical strike, haste, mastery, versatility, speed (also movement speed), leech and avoidance.", 36)
	page:Check("Hide stats you have none of (Blizzard's default)", Getter(cfg, "hideZeroStats"), Setter(cfg, "hideZeroStats"))
	page:Check("Movement speed in the stat list", Getter(cfg, "moveSpeed"), Setter(cfg, "moveSpeed"))
	page:Note("Extra rows (stats at 0, movement speed) are added under Blizzard's list and skipped in rated PvP, where the game hides the numbers.", 36)
	page:Check("Item level to two decimals, with overall and PvP", Getter(cfg, "ilvlDecimals"), Setter(cfg, "ilvlDecimals"))
	page:Note("Inspected players show their item level and PvP item level at the top of the window.", 36)
	page:TextStyle("First line text", function() return cfg().nameStyle end, {})
	page:TextStyle("Item level / enchant text", function() return cfg().infoStyle end, {})
end

local function BuildObjectivesPage(page)
	local function cfg() return ns.db.objectives end
	page:Column(1)
	page:Header("Objectives")
	page:Note("Blizzard's quest and objective tracker. Move it and set its height in Edit Mode.", 36)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Header("Text")
	page:Note("Uses the Stinkie UI font (General page).", 22)
	page:Slider("Objective text size", 8, 24, 1, Getter(cfg, "lineSize"), Setter(cfg, "lineSize"))
	page:Slider("Header text size", 8, 28, 1, Getter(cfg, "headerSize"), Setter(cfg, "headerSize"))
	page:Choice("Outline", { { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICKOUTLINE", "Thick" } }, Getter(cfg, "outline"), Setter(cfg, "outline"))
	page:Header("Size")
	page:Slider("Scale", 0.5, 2, 0.05, Getter(cfg, "scale"), Setter(cfg, "scale"))
	page:Header("Look")
	page:Check("Flat headers, bars and quest item buttons", Getter(cfg, "flat"), Setter(cfg, "flat"), true)
	page:Note("Headers get a thin accent line instead of Blizzard's gradient; progress bars a flat fill with a 1px border.", 36)
	page:Column(2)
	page:Header("Background")
	page:Check("Background", Getter(cfg, "background"), Setter(cfg, "background"))
	page:Check("Hide Blizzard's background", Getter(cfg, "hideBlizzardBg"), Setter(cfg, "hideBlizzardBg"))
	page:Check("1px border", Getter(cfg, "border"), Setter(cfg, "border"))
	page:Color("Color", Getter(cfg, "bgColor"), Setter(cfg, "bgColor"))
	page:Slider("Opacity", 0, 1, 0.05, Getter(cfg, "bgAlpha"), Setter(cfg, "bgAlpha"))
	page:Slider("Padding", 0, 20, 1, Getter(cfg, "padding"), Setter(cfg, "padding"))
	page:Header("Hide in")
	page:Check("Arenas", Getter(cfg, "hideArena"), Setter(cfg, "hideArena"))
	page:Check("Battlegrounds and Blitz", Getter(cfg, "hideBG"), Setter(cfg, "hideBG"))
	page:Check("Raids", Getter(cfg, "hideRaid"), Setter(cfg, "hideRaid"))
	page:Check("Mythic+", Getter(cfg, "hideMPlus"), Setter(cfg, "hideMPlus"))
	page:Check("Other dungeons", Getter(cfg, "hideDungeon"), Setter(cfg, "hideDungeon"))
	page:Note("Hidden means invisible (it stays where it is). New text sizes show on the tracker's next update or a /reload.", 36)
	local function arrow() return ns.db.misc.questArrow end
	page:Header("Quest marker")
	page:Check("Enabled", Getter(arrow, "enabled"), Setter(arrow, "enabled"))
	page:Note("A small nameplate in the world on the quest you're actively tracking, or your corpse while you're dead, with the distance in yards, in place of Blizzard's marker. Off screen it becomes an arrow at the edge of the screen. It goes wherever Blizzard's marker would.", 76)
	page:Slider("Height above the spot", 0, 300, 5, Getter(arrow, "height"), Setter(arrow, "height"))
	page:Slider("Hide this close to an objective (yards)", 0, 100, 5, Getter(arrow, "hideYards"), Setter(arrow, "hideYards"))
	page:Slider("Off-screen arrow: gap to screen edge", 20, 300, 5, Getter(arrow, "edgeMargin"), Setter(arrow, "edgeMargin"))
	page:Slider("Arrow size", 12, 64, 1, Getter(arrow, "size"), Setter(arrow, "size"))
	page:Color("Arrow color", Getter(arrow, "color"), Setter(arrow, "color"))
	page:Check("Show quest name", Getter(arrow, "showName"), Setter(arrow, "showName"))
	page:TextStyle("Quest marker text", function() return arrow().textStyle end)
end

local function BuildDamageTextPage(page)
	local function cfg() return ns.db.damageText end
	local function db() return ns.db end
	local DT = ns.DamageText
	page:Column(1)
	page:Header("Damage Numbers")
	page:Note("The damage and healing numbers that float over targets in the world.", 22)
	page:Check("Show your healing numbers", Getter(cfg, "healing"), Setter(cfg, "healing"))
	page:Note("The game's own switch, which its settings don't show. It covers healing you do.", 22)
	page:Check("Show healing you receive (scrolling text)", DT.ScrollingText, DT.SetScrollingText)
	page:Note("Blizzard's scrolling text over your character. It covers heals like Cannibalize, but also shows the other things Blizzard scrolls there, like damage you take.", 48)
	local function scroll() return ns.db.damageText.scroll end
	page:Check("Stinkie UI look for scrolling text", Getter(scroll, "enabled"), Setter(scroll, "enabled"))
	page:Dropdown("Direction", { { "1", "Up" }, { "2", "Down" }, { "3", "Arc" },
		{ "healsUp", "Heals up, damage down" }, { "healsDown", "Heals down, damage up" } }, DT.ScrollMode, DT.SetScrollMode, true)
	page:Note("With heals and damage split, they scroll side by side and everything else scrolls up.", 36)
	page:Slider("Text size", 10, 48, 1, Getter(scroll, "size"), Setter(scroll, "size"))
	page:Slider("Crit size", 10, 64, 1, Getter(scroll, "critSize"), Setter(scroll, "critSize"))
	page:Check("Crits pop (Blizzard's size)", Getter(scroll, "critPop"), Setter(scroll, "critPop"))
	page:Slider("Gap between lines (split directions)", 0, 40, 1, Getter(scroll, "spacing"), Setter(scroll, "spacing"))
	page:Choice("Outline", { { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICKOUTLINE", "Thick" } }, Getter(scroll, "outline"), Setter(scroll, "outline"))
	page:Check("Stinkie UI font", Getter(db, "combatTextFont"), Setter(db, "combatTextFont"), true)
	page:Note("The game reads this font while the world loads: log out fully and back in (a /reload isn't enough).", 36)
	page:Check("Change size and position", Getter(cfg, "enabled"), Setter(cfg, "enabled"))
	local function Opt(key, label, min, max, step, note)
		if DT.Available(key) then
			page:Slider(label, min, max, step, Getter(cfg, key), Setter(cfg, key))
		else
			page:Note(label .. ": not in this game version.", 22)
		end
	end
	Opt("screenY", "Height above the target (0 = default 0.015)", 0, 0.2, 0.005)
	if not DT.Available("screenY") then Opt("height", "Height above the target (0 = game default)", 0, 10, 0.25) end
	Opt("size", "Size (0 = game default)", 0, 3, 0.05)
	page:Header("Critical hits")
	Opt("critScreenY", "Crit height above the target (0 = default 0.0275)", 0, 0.2, 0.005)
	Opt("critSize", "Crit pop size (0 = game default)", 0, 5, 0.1)
	page:Note("Crits pop up bigger than normal hits, then shrink back. Pop size sets how big that pop gets; Size above still scales everything.", 36)
	Opt("spread", "Sideways scatter (0 = game default)", 0, 3, 0.05)
	Opt("gravity", "Fall speed (0 = game default)", 0, 5, 0.1)
	Opt("directional", "Sideways flight (0 = default, low = straight up)", 0, 5, 0.1)
	page:Note("These use the game's own settings, so they also change what other addons see. Height is measured from the target's nameplate, as a share of your screen's height (0.05 = 5% of the screen). /stinkie dmg shows which settings this game version has and their values.", 62)
end

local function BuildSkinsPage(page)
	local function cfg() return ns.db.skins end
	page:Column(1)
	page:Header("Window Skins")
	page:Note("Blizzard's other windows in the Character Sheet's flat look: no frame art or portrait, a flat background with a 1px border, flat tabs. Each window is restyled once when it first opens, so it costs nothing while you play.", 62)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Slider("Background opacity", 0, 1, 0.05, Getter(cfg, "alpha"), Setter(cfg, "alpha"))
	page:Note("Background color is the Character Sheet's window color.", 22)
	page:Column(2)
	page:Header("Windows")
	for _, def in ipairs(ns.Skins.WINDOWS) do
		page:Check(def.label, Getter(cfg, def.key), Setter(cfg, def.key), true)
	end
	page:Note("Turning a window off fully restores Blizzard's look after a /reload. Bags, talents and spellbook, and the map / quest log are left alone: Blizzard protects them, and restyling them risks errors in combat.", 62)
end

local function BuildTooltipPage(page)
	local function cfg() return ns.db.tooltip end
	page:Column(1)
	page:Header("Tooltip")
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Slider("Size", 0.5, 2, 0.05, Getter(cfg, "scale"), Setter(cfg, "scale"))
	page:Header("Where it shows")
	page:Choice("Anchor", { { "mouse", "Mouse" }, { "fixed", "Fixed spot" }, { "blizzard", "Blizzard" } }, Getter(cfg, "anchor"), Setter(cfg, "anchor"))
	page:Slider("Offset X (from the mouse)", -300, 300, 1, Getter(cfg, "offsetX"), Setter(cfg, "offsetX"))
	page:Slider("Offset Y (from the mouse)", -300, 300, 1, Getter(cfg, "offsetY"), Setter(cfg, "offsetY"))
	page:Dropdown("Fixed spot: tooltip corner", { { "BOTTOMRIGHT", "Bottom right" }, { "BOTTOMLEFT", "Bottom left" }, { "TOPRIGHT", "Top right" }, { "TOPLEFT", "Top left" } },
		Getter(cfg, "fixedPoint"), Setter(cfg, "fixedPoint"))
	page:Position("Fixed spot", function() return "tooltip" end)
	page:Note("Applies to tooltips that go to Blizzard's default spot (units in the world, most buttons). Tooltips other windows place themselves stay where they are.", 50)
	page:Column(2)
	page:Header("Combat")
	page:Choice("In combat", { { "show", "Show" }, { "units", "Hide units" }, { "all", "Hide all" } }, Getter(cfg, "combat"), Setter(cfg, "combat"))
	page:Check("Hold Shift to show them anyway", Getter(cfg, "combatShift"), Setter(cfg, "combatShift"))
	page:Header("Units")
	page:Check("Health bar", Getter(cfg, "healthBar"), Setter(cfg, "healthBar"))
	page:Check("Their target (YOU in red when it's you)", Getter(cfg, "target"), Setter(cfg, "target"))
	page:Check("Player names in class color", Getter(cfg, "classNames"), Setter(cfg, "classNames"))
	page:Check("Guild rank: my guild", Getter(cfg, "rankOwn"), Setter(cfg, "rankOwn"))
	page:Check("Guild rank: other guilds", Getter(cfg, "rankOther"), Setter(cfg, "rankOther"))
	page:Note("Rated PvP hides names and classes from addons; the target line and colors are left out there rather than guessed.", 36)
	page:Header("Extra")
	page:Check("Spell and item IDs", Getter(cfg, "ids"), Setter(cfg, "ids"))
end

local function BuildBuffsPage(page)
	local function cfg() return ns.db.buffs end
	page:Column(1)
	page:Header("Buff frame")
	page:Note("Blizzard's buff and debuff icons. Move them, change the size, icons per row and direction in Edit Mode.", 36)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Header("Look")
	page:Check("Flat look (your fonts on duration and stacks)", Getter(cfg, "skin"), Setter(cfg, "skin"))
	page:Check("Zoom icons (crop the edges)", Getter(cfg, "zoom"), Setter(cfg, "zoom"))
	page:Check("1px border", Getter(cfg, "border"), Setter(cfg, "border"))
	page:Note("Debuffs keep Blizzard's colored border by type. Turning the flat look off fully undoes the fonts after a /reload.", 36)
	page:TextStyle("Duration text", function() return cfg().durationStyle end, {})
	page:TextStyle("Stack count text", function() return cfg().countStyle end, {})
	page:Column(2)
	page:Header("Auto hide")
	page:Check("In arenas", Getter(cfg, "hideArena"), Setter(cfg, "hideArena"))
	page:Check("In battlegrounds and Blitz", Getter(cfg, "hideBG"), Setter(cfg, "hideBG"))
	page:Check("In dungeons and Mythic+", Getter(cfg, "hideDungeon"), Setter(cfg, "hideDungeon"))
	page:Check("In raids", Getter(cfg, "hideRaid"), Setter(cfg, "hideRaid"))
	page:Check("In combat (anywhere)", Getter(cfg, "hideCombat"), Setter(cfg, "hideCombat"))
	page:Check("Always", Getter(cfg, "hideAlways"), Setter(cfg, "hideAlways"))
	page:Check("Hide debuffs too", Getter(cfg, "debuffs"), Setter(cfg, "debuffs"))
	page:Check("Show them while the mouse is over the spot", Getter(cfg, "mouseover"), Setter(cfg, "mouseover"))
	page:Note("Hidden means invisible: the icons are still there, so a right-click on that spot still cancels a buff.", 36)
end

local function BuildWindowMoverPage(page)
	local function cfg() return ns.db.windowMover end
	page:Column(1)
	page:Header("Window Mover")
	page:Note("Move Blizzard's windows by dragging any empty part of them, and hold Ctrl and scroll over a window to make it bigger or smaller. Positions and sizes are remembered. Replaces BlizzMove (it switches itself off while BlizzMove is enabled).", 76)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Check("Ctrl + mouse wheel changes size", Getter(cfg, "wheel"), Setter(cfg, "wheel"))
	page:Choice("Hold to drag", { { "none", "Nothing" }, { "alt", "Alt" }, { "shift", "Shift" }, { "ctrl", "Ctrl" } }, Getter(cfg, "modifier"), Setter(cfg, "modifier"))
	page:Check("Remember across sessions", Getter(cfg, "remember"), Setter(cfg, "remember"))
	page:Note("Off: windows go back to Blizzard's spots after a logout or reload.", 36)
	page:Button("Reset all windows", function() ns.WindowMover.ResetAll() end)
	page:Note("Alt + right-click a window to reset just that one. Windows Blizzard protects (spellbook, map) only move out of combat. Character and inspect window sizes are the same setting as on the Character Sheet page.", 62)
	page:Column(2)
	page:Header("Windows")
	local names = {}
	for _, f in ipairs(ns.WindowMover.FRAMES) do names[#names + 1] = f[2] end
	page:Note(table.concat(names, ", ") .. ".", 210)
	page:TextList("More windows", 90, function() return table.concat(cfg().extra or {}, "\n") end, function(text)
		local list = {}
		for line in text:gmatch("[^\r\n,]+") do
			line = strtrim(line)
			if line ~= "" then table.insert(list, line) end
		end
		cfg().extra = list
	end, "Frame names of any other window to make movable, one per line (/fstack shows names).")
end

local function BuildPartyTargetsPage(page)
	local function cfg() return ns.db.partyTargets end
	page:Column(1)
	page:Header("Party targets")
	page:Note("A small frame for each party member's target, in line with the party frames.", 36)
	page:Check("Enabled", Getter(cfg, "enabled"), Setter(cfg, "enabled"), true)
	page:Note("Blizzard blocks addons from party members' targets inside arenas and battlegrounds, so these frames stay blank there.", 48)
	page:Check("Hide in arenas and battlegrounds", Getter(cfg, "hideInPvP"), Setter(cfg, "hideInPvP"))
	page:Check("Sit above each party frame", Getter(cfg, "attachAbove"), Setter(cfg, "attachAbove"))
	page:Slider("Gap above the party frame", 0, 20, 1, Getter(cfg, "attachGap"), Setter(cfg, "attachGap"))
	page:Note("They follow the party frames, so the position below isn't used. Needs enough party spacing to fit.", 36)
	page:Slider("Width", 30, 300, 1, Getter(cfg, "width"), Setter(cfg, "width"))
	page:Slider("Height", 6, 60, 1, Getter(cfg, "height"), Setter(cfg, "height"))
	page:Check("Show power bar", Getter(cfg, "showPower"), Setter(cfg, "showPower"))
	page:Slider("Power height", 1, 20, 1, Getter(cfg, "powerHeight"), Setter(cfg, "powerHeight"))
	page:Check("Shields", Getter(cfg, "shields"), Setter(cfg, "shields"))
	page:Note("Rows follow the party frames' height, spacing and growth. Party test mode (or unlocking) shows stand-ins.", 36)
	page:Position(nil, function() return "partyTargets" end)
	page:Column(2)
	page:Header("Text")
	page:Check("Show name", Getter(cfg, "showName"), Setter(cfg, "showName"))
	page:Choice("Name shows", nameChoices, Getter(cfg, "nameFormat"), Setter(cfg, "nameFormat"))
	page:Check("Show level", Getter(cfg, "showLevel"), Setter(cfg, "showLevel"))
	page:Choice("Health text", healthTextChoices, Getter(cfg, "healthText"), Setter(cfg, "healthText"))
	page:TextStyle("Name text", function() return cfg().nameStyle end, { classColor = true })
	page:TextStyle("Health text", function() return cfg().healthStyle end)
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
	page:Check("Gray out abilities you can't use", Getter(cd, "grayUnusable"), Setter(cd, "grayUnusable"))
	page:Note("For Blizzard's rows and spells on the custom bars. Execute, say, stays gray until it's usable or procs.", 36)
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
	page:Note("Blizzard UI: tooltips, buff timers, spec names, character sheet, damage meter, zone text, settings. Names above characters need a full logout, not just a reload. Damage numbers: Miscellaneous > Damage Numbers.", 62)
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
	page:Note("Slash commands: /stinkie, /stinkie unlock, /stinkie lock, /mh (match history), /mh stats, /stinkie flags, /stinkie timers, /stinkie fontcheck, /stinkie auras, /stinkie plates, /stinkie reset", 50)
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
-- Top-level pages; an entry with children opens a group in the list.
local pages = {
	{ "General", BuildGeneralPage },
	{ "Unit Frames", children = {
		{ "Player", function(p) BuildUnitPage(p, "player") end },
		{ "Target", function(p) BuildUnitPage(p, "target") end },
		{ "Target of Target", function(p) BuildUnitPage(p, "targettarget") end },
		{ "Focus", function(p) BuildUnitPage(p, "focus") end },
		{ "Pet", function(p) BuildUnitPage(p, "pet") end },
		{ "Party", BuildPartyPage },
		{ "Party Targets", BuildPartyTargetsPage },
	} },
	{ "Nameplates", children = {
		{ "General", BuildPlateGeneralPage },
		{ "Enemy", BuildPlateEnemyPage },
		{ "Friendly", BuildPlateFriendlyPage },
		{ "Target", BuildPlateTargetPage },
		{ "Icons", BuildPlateIconsPage },
		{ "Auras & Units", BuildPlateAurasPage },
	} },
	{ "Action Bars", BuildActionBarPage },
	{ "Cooldowns", BuildCooldownPage },
	{ "PvP Assist", BuildArenaAssistPage },
	{ "Arena Frames", BuildArenaPage },
	{ "Battleground Frames", BuildBGPage },
	{ "BG Score", BuildBGScorePage },
	{ "BG Timers", BuildBGTimersPage },
	{ "Character Sheet", BuildCharacterPage },
	{ "Combat Indicator", BuildCombatPage },
	{ "Match History", children = {
		{ "History & Import", BuildMatchHistoryPage },
		{ "Queue Time & MMR", BuildQueueInfoPage },
	} },
	{ "Castbars", BuildCastbarPage },
	{ "Class Resource", BuildClassPowerPage },
	{ "Chat", BuildChatPage },
	{ "Combat Logging", BuildCombatLogPage },
	{ "Cursor", BuildCursorPage },
	{ "Miscellaneous", children = {
		{ "GCD History & Decor", BuildMiscPage },
		{ "Minimap", BuildMinimapPage },
		{ "Damage Meter", BuildDamageMeterPage },
		{ "Objectives", BuildObjectivesPage },
		{ "Buff Frame", BuildBuffsPage },
		{ "Tooltip", BuildTooltipPage },
		{ "Window Skins", BuildSkinsPage },
		{ "Damage Numbers", BuildDamageTextPage },
		{ "Window Mover", BuildWindowMoverPage },
	} },
}

local HEADER_H, WIN_H = 92, 700
local NAV_STEP, NAV_CHILD_STEP = 20, 18 -- search box + 20 entries + the largest open group (8) fit the 588px column

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

	-- every leaf page gets an index; groups open in place when clicked
	local leaves = {}
	local top = {} -- { button, def, leafIndex | children = { { button, leafIndex } } }
	local built, current, openGroup = {}, nil, nil
	local Layout
	local function SelectPage(i)
		current = i
		for _, p in pairs(built) do p:Hide() end
		if not built[i] then
			local page = NewPage(scroll)
			leaves[i].build(page)
			built[i] = page
		end
		scroll:SetScrollChild(built[i])
		scroll:SetVerticalScroll(0)
		built[i]:Show()
		if popup then popup:Hide() end
		openGroup = leaves[i].group or openGroup
		if leaves[i].group == nil then openGroup = nil end
		Layout()
	end
	function Layout()
		local y = -30 -- under the search box
		local searching = O.searchActive
		for _, t in ipairs(top) do
			t.button:SetShown(not searching)
			t.button:ClearAllPoints()
			t.button:SetPoint("TOPLEFT", 4, y)
			y = y - NAV_STEP
			if t.children then
				local open = (openGroup == t)
				local selected = false
				for _, c in ipairs(t.children) do
					c.button:SetShown(open and not searching)
					if open then
						c.button:ClearAllPoints()
						c.button:SetPoint("TOPLEFT", 16, y + 1)
						y = y - NAV_CHILD_STEP
					end
					c.button:SetSelected(current == c.leaf)
					if current == c.leaf then selected = true end
				end
				t.button.arrow:SetText(open and "-" or "+")
				t.button:SetSelected(selected and not open)
			else
				t.button:SetSelected(current == t.leaf)
			end
		end
	end
	for _, def in ipairs(pages) do
		local t = { def = def }
		if def.children then
			t.children = {}
			t.button = FlatButton(nav, def[1], 142, function()
				if openGroup == t then
					openGroup = nil
					Layout()
				else
					openGroup = t
					local pick = t.lastLeaf or t.children[1].leaf
					SelectPage(pick)
				end
			end)
			t.button.arrow = Label(t.button, "+", 13, { 0.6, 0.6, 0.65 })
			t.button.arrow:SetPoint("RIGHT", -8, 0)
			for _, cdef in ipairs(def.children) do
				leaves[#leaves + 1] = { build = cdef[2], group = t, name = def[1] .. " > " .. cdef[1] }
				local leaf = #leaves
				local c = { leaf = leaf }
				c.button = FlatButton(nav, cdef[1], 130, function() t.lastLeaf = leaf; SelectPage(leaf) end)
				c.button:SetHeight(17)
				c.button.text:ClearAllPoints()
				c.button.text:SetPoint("LEFT", 10, 0)
				ns.SetFont(c.button.text, 12)
				c.button:Hide()
				table.insert(t.children, c)
			end
		else
			leaves[#leaves + 1] = { build = def[2], name = def[1] }
			t.leaf = #leaves
			t.button = FlatButton(nav, def[1], 142, function() SelectPage(t.leaf) end)
		end
		t.button:SetHeight(19)
		t.button.text:ClearAllPoints()
		t.button.text:SetPoint("LEFT", 10, 0)
		table.insert(top, t)
	end
	-- search: every option label on every page; results replace the menu while typing
	local search = EditBox(nav, 142)
	search:SetPoint("TOPLEFT", 4, -4)
	search:SetJustifyH("LEFT")
	ns.SetBorderColor(search, ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
	local hint = Label(search, "Search all options...", 12, { 0.6, 0.6, 0.6 })
	hint:SetPoint("LEFT", 6, 0)
	local results = {}
	local function Texts(frame, out, depth)
		for _, r in ipairs({ frame:GetRegions() }) do
			if r:IsObjectType("FontString") and r:IsShown() then
				local t = r:GetText()
				if type(t) == "string" and t ~= "" then out[#out + 1] = { text = t, region = r } end
			end
		end
		if depth < 3 then for _, ch in ipairs({ frame:GetChildren() }) do Texts(ch, out, depth + 1) end end
	end
	local function Index()
		if O.searchIndex then return O.searchIndex end
		local idx = {}
		for i, leaf in ipairs(leaves) do
			if not built[i] then
				local page = NewPage(scroll)
				-- one page failing to build must not stop the search
				local ok, err = pcall(leaf.build, page)
				if not ok then geterrorhandler()(err) end
				built[i] = page
			end
			local list = {}
			pcall(Texts, built[i], list, 0)
			for _, e in ipairs(list) do
				-- strip color codes so "|cff..x|r" style labels match plain text
				local plain = e.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
				idx[#idx + 1] = { leaf = i, text = plain, lower = plain:lower(), region = e.region }
			end
			idx[#idx + 1] = { leaf = i, text = leaf.name, lower = leaf.name:lower(), page = true }
		end
		O.searchIndex = idx
		return idx
	end
	local function GoTo(hit)
		SelectPage(hit.leaf)
		local page = built[hit.leaf]
		if hit.region and page:GetTop() and hit.region:GetTop() then
			local y = page:GetTop() - hit.region:GetTop() - 40
			local max = math.max(0, page:GetHeight() - scroll:GetHeight())
			scroll:SetVerticalScroll(math.max(0, math.min(max, y)))
		end
	end
	local function ShowResults(q)
		local hits, seen = {}, {}
		if q ~= "" then
			for _, e in ipairs(Index()) do
				if #hits >= 26 then break end
				local key = e.leaf .. ":" .. e.lower
				if e.lower:find(q, 1, true) and not seen[key] then
					seen[key] = true
					hits[#hits + 1] = e
				end
			end
		end
		for i = 1, math.max(#hits, #results) do
			local b = results[i]
			if not b and hits[i] then
				b = FlatButton(nav, "", 142, function(self) if self.hit then GoTo(self.hit) end end)
				b:SetHeight(20)
				b.text:ClearAllPoints()
				b.text:SetPoint("LEFT", 6, 0)
				b.text:SetPoint("RIGHT", -4, 0)
				b.text:SetJustifyH("LEFT")
				b.text:SetWordWrap(false)
				ns.SetFont(b.text, 11)
				results[i] = b
			end
			if b then
				local h = hits[i]
				b.hit = h
				if h then
					local where = leaves[h.leaf].name:match("([^>]+)$"):gsub("^%s+", "")
					b.text:SetText(h.page and ("|cff" .. ns.ACCENT_HEX .. h.text .. "|r") or (h.text .. "  |cff8a8a8a" .. where .. "|r"))
					b:ClearAllPoints()
					b:SetPoint("TOPLEFT", 4, -30 - (i - 1) * 21)
					b:Show()
				else
					b:Hide()
				end
			end
		end
		if O.searchEmpty == nil then
			O.searchEmpty = Label(nav, "No match", 12, { 0.6, 0.6, 0.6 })
			O.searchEmpty:SetPoint("TOPLEFT", 10, -34)
		end
		O.searchEmpty:SetShown(q ~= "" and #hits == 0)
	end
	search:SetScript("OnMouseDown", function(self) self:SetFocus() end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if results[1] and results[1]:IsShown() and results[1].hit then GoTo(results[1].hit) end
	end)
	search:SetScript("OnTextChanged", function(self)
		local q = strtrim(self:GetText() or ""):lower()
		hint:SetShown(q == "")
		O.searchActive = q ~= ""
		ShowResults(q)
		Layout()
	end)
	O.search = search

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

-- shared with the Match History window (StinkieUI_History)
O.W = {
	Flat = Flat, Label = Label, FlatButton = FlatButton, EditBox = EditBox,
	ShowPopup = function(...) return ShowPopup(...) end,
	ShowTextPopup = function(...) return ShowTextPopup(...) end,
}

ns:RegisterModule("Options", O)
