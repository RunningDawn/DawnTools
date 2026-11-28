-- DawnTools :: UI
-- One movable window. Every enabled module that registered a `tab` gets a button along the top and a panel
-- (built the first time it is opened). Settings is always the last tab.

local _, DT = ...
local UI = {}
DT.UI = UI

local WIDTH, HEIGHT = 960, 560
local MIN_W, MIN_H = 900, 420 -- the Settings tab and the Market columns need this much
local panels, buttons, separators, current = {}, {}, {}, nil
local settingsTab

local frame = DT:SkinFrame(CreateFrame("Frame", "DawnToolsFrame", UIParent, "BackdropTemplate"), "window")
frame:SetSize(WIDTH, HEIGHT)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
if frame.SetToplevel then frame:SetToplevel(true) end -- (a click brings it in front of other windows of its layer)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relative, x, y = self:GetPoint(1)
	DT.db.pos = { point, relative, x, y }
end)
frame:Hide()
table.insert(UISpecialFrames, "DawnToolsFrame") -- Esc closes it

local logo = frame:CreateTexture(nil, "ARTWORK")
logo:SetSize(22, 22)
logo:SetPoint("TOPLEFT", 8, -6)
logo:SetTexture(DT.LOGO)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
title:SetText("DawnTools")

local close = DT:SkinCloseButton(CreateFrame("Button", nil, frame, "UIPanelCloseButton"))
close:SetPoint("TOPRIGHT", 2, 2)
close:SetScript("OnClick", function() frame:Hide() end) -- (the template's own closing goes through the game's panel code, which is barred to addons in combat: a plain Hide is not)

-- drag the bottom right corner to resize; tabs lay themselves out again on their panel's OnSizeChanged
frame:SetResizable(true)
if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H) elseif frame.SetMinResize then frame:SetMinResize(MIN_W, MIN_H) end
local grip = CreateFrame("Button", nil, frame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -1, 1)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
-- The window may be no bigger than the screen (less a margin), however it is pulled.
local function Fit(w, h)
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	-- (the screen's size not known, or not told in plain numbers: a size that fits any screen in use, never
	-- "as big as it is pulled". Without this there was no upper limit at all at such a moment.)
	local known = type(sw) == "number" and type(sh) == "number" and not (issecretvalue and (issecretvalue(sw) or issecretvalue(sh)))
		and sw >= MIN_W + 40 and sh >= MIN_H + 40
	if not known then sw, sh = MIN_W + 500, MIN_H + 400 end
	if type(w) ~= "number" or w ~= w then w = MIN_W end -- (no number, or not one that can be compared: the least)
	if type(h) ~= "number" or h ~= h then h = MIN_H end
	return math.max(MIN_W, math.min(w, sw - 40)), math.max(MIN_H, math.min(h, sh - 40))
end
-- (the corner is above whatever lies under it: a list's scroll bar ends in that corner too)
if grip.SetFrameLevel and frame.GetFrameLevel then grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 100) end

-- The corner is pulled by a sum of our own, not by the game's sizing: the size the window had when the corner
-- was taken, plus how far the mouse has moved since. The game's own StartSizing made the window leap to its
-- largest size on some clicks; a sum cannot leap. Meanwhile the window hangs by its top left corner, so that it
-- grows to the right and down, under the mouse.
local pull -- { x, y, w, h }: where the mouse was and how big the window, when the corner was taken
local function Mouse()
	if not GetCursorPosition then return nil end
	local x, y = GetCursorPosition()
	local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
	if type(x) ~= "number" or type(y) ~= "number" or type(scale) ~= "number" or scale <= 0 then return nil end
	return x / scale, y / scale
end
local function Drop()
	if not pull then return end
	pull = nil
	grip:SetScript("OnUpdate", nil)
	frame:SetSize(Fit(frame:GetWidth(), frame:GetHeight()))
	DT.db.size = { frame:GetWidth(), frame:GetHeight() }
	-- (the window was hung anew: remember where it is now)
	local point, _, relative, x, y = frame:GetPoint(1)
	if point then DT.db.pos = { point, relative, x, y } end
end
grip:SetScript("OnMouseDown", function()
	-- (hung by its centre, as it is until first moved, it would grow both ways. Only where the game tells
	-- where the window stands in plain numbers: else it is left hanging as it is.)
	local left, top = frame:GetLeft(), frame:GetTop()
	local plain = type(left) == "number" and type(top) == "number" and not (issecretvalue and (issecretvalue(left) or issecretvalue(top)))
	if plain then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	local x, y = Mouse()
	pull = { x = x, y = y, w = frame:GetWidth(), h = frame:GetHeight() }
	grip:SetScript("OnUpdate", function()
		if not pull then return end
		-- (the button let go somewhere the corner did not hear of it: the window is put down)
		if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return Drop() end
		local mx, my = Mouse()
		if not (mx and pull.x) then return end
		local w, h = Fit(pull.w + (mx - pull.x), pull.h - (my - pull.y))
		if w ~= frame:GetWidth() or h ~= frame:GetHeight() then frame:SetSize(w, h) end
	end)
end)
grip:SetScript("OnMouseUp", Drop)
UI.frame, UI.grip = frame, grip -- (for the self test and the checks)

local body = CreateFrame("Frame", nil, frame)
body:SetPoint("TOPLEFT", 8, -36)
body:SetPoint("BOTTOMRIGHT", -8, 8)

local bodyInset = DT:SkinFrame(CreateFrame("Frame", nil, frame, "BackdropTemplate"), "inset")
bodyInset:SetPoint("TOPLEFT", body, "TOPLEFT", -4, 4)
bodyInset:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 4, -4)
bodyInset:SetFrameLevel(math.max(1, body:GetFrameLevel() - 1))

local function UpdateWindowChrome()
	local classic = DT:Theme().classic and true or false
	logo:ClearAllPoints()
	close:ClearAllPoints()
	grip:ClearAllPoints()
	body:ClearAllPoints()
	if classic then
		logo:SetPoint("TOPLEFT", 14, -11)
		close:SetPoint("TOPRIGHT", -5, -5)
		grip:SetPoint("BOTTOMRIGHT", -7, 7)
		body:SetPoint("TOPLEFT", 14, -42)
		body:SetPoint("BOTTOMRIGHT", -14, 14)
	else
		logo:SetPoint("TOPLEFT", 8, -6)
		close:SetPoint("TOPRIGHT", 2, 2)
		grip:SetPoint("BOTTOMRIGHT", -1, 1)
		body:SetPoint("TOPLEFT", 8, -36)
		body:SetPoint("BOTTOMRIGHT", -8, 8)
	end
	bodyInset:SetShown(classic)
end
UpdateWindowChrome()
DT:On("DT_THEME", UpdateWindowChrome)

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function Rank(tab)
	return DT.db.tabs.rank[tab.id] or tab.defaultOrder or 100
end

-- Places: some tabs stand together under one. A module's tab that names a place (tab.under = "world") is a
-- sub-tab there: the place is the button on the bar, with a row of its sub-tabs beneath, as the Tools tab has.
-- A place is there while a module with a tab under it is switched on.
local PLACES = {
	craft = { title = "Craft", defaultOrder = 45 }, -- Fishing, Cooking, and a tab for each profession
	world = { title = "World", defaultOrder = 55 }, -- NPC, Quests
}
local places = {} -- [id] = the tab that stands for the place: { id, title, defaultOrder, subs = { tab, ... }, place = true }
local ShowSub

local function Place(id)
	local p = places[id]
	if p then return p end
	local def = PLACES[id] or { title = id, defaultOrder = 100 }
	p = { id = id, title = def.title, defaultOrder = def.defaultOrder, group = def.group, subs = {}, place = true, buttons = {}, panels = {} }
	p.create = function(panel)
		p.body = CreateFrame("Frame", nil, panel)
		p.body:SetPoint("TOPLEFT", 0, -30)
		p.body:SetPoint("BOTTOMRIGHT", 0, 0)
		local line = panel:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(1, 1, 1, 0.12)
		line:SetPoint("TOPLEFT", 0, -27)
		line:SetPoint("TOPRIGHT", 0, -27)
		line:SetHeight(1)
		p.rule = line -- (moved down where the sub-tabs take more than one row)
		p.panel = panel
		-- (a wider window: fewer rows of buttons. Only they are laid out: the sub-tab itself hears of its
		-- new size from its own panel, and is not shown anew for every step of a pull at the corner.)
		panel:SetScript("OnSizeChanged", function() if p.current then ShowSub(p, true) end end)
	end
	p.onShow = function() ShowSub(p) end
	p.onHide = function()
		for _, sub in ipairs(p.subs) do
			if sub.id == p.current and sub.onHide then sub.onHide() end
		end
	end
	places[id] = p
	return p
end

-- shows a place's sub-tab: the one asked for (p.want), else the last one used there, else the first
-- (layoutOnly: only its row of buttons is laid out again, for a window that changed its width)
function ShowSub(p, layoutOnly)
	if not p.panel then return end
	DT.db.tabs.sub = DT.db.tabs.sub or {}
	local sub, last = (not layoutOnly) and p.want or nil, p.current or DT.db.tabs.sub[p.id]
	if not layoutOnly then p.want = nil end
	for _, s in ipairs(p.subs) do
		if not sub and s.id == last then sub = s end
	end
	sub = sub or p.subs[1]
	-- A button a sub-tab, as wide as its title asks for. Where the group changes along the row (tab.group, 1 if
	-- not given) there is a gap with a thin line in it, as between the groups of the bar above. What does not
	-- fit the window's width goes on to a second row, and the sub-tab's own space begins below that.
	p.lines = p.lines or {}
	local x, lines, row = 2, 0, 0
	local limit = p.panel.GetWidth and p.panel:GetWidth() or 0
	if not limit or limit < 200 then limit = 900 end
	for i = 1, math.max(#p.subs, #p.buttons) do
		local s, b = p.subs[i], p.buttons[i]
		if s and not b then
			b = DT:SkinButton(CreateFrame("Button", nil, p.panel, "UIPanelButtonTemplate"))
			b:SetScript("OnClick", function(self)
				p.want = self.sub
				ShowSub(p)
			end)
			p.buttons[i] = b
		end
		if b then
			b:SetShown(s ~= nil)
			if s then
				local width = math.max(60, #s.title * 6 + 20)
				local gap = i > 1 and (s.group or 1) ~= (p.subs[i - 1].group or 1)
				-- (no room left on this row: the next one; a group's line is not drawn at a row's start)
				if x > 2 and (s.row or x + (gap and 14 or 0) + width > limit) then x, row, gap = 2, row + 1, gap and "row" end -- (tab.row: it begins a row)
				if gap then
					lines = lines + 1
					local line = p.lines[lines] or p.panel:CreateTexture(nil, "ARTWORK")
					p.lines[lines] = line
					line:SetColorTexture(1, 1, 1, 0.25)
					line:ClearAllPoints()
					line:SetPoint("TOPLEFT", x + 5, -4 - row * 24)
					line:SetSize(1, 18)
					line:SetShown(gap ~= "row")
					if gap ~= "row" then x = x + 14 end
				end
				b.sub, b.id, b.x, b.gap, b.row = s, s.id, x, lines, row
				b:ClearAllPoints()
				b:SetSize(width, 22)
				b:SetPoint("TOPLEFT", x, -2 - row * 24)
				b:SetText(s.title)
				x = x + width + 4
				if s == sub then b:LockHighlight() else b:UnlockHighlight() end
			end
		end
	end
	for i = lines + 1, #p.lines do p.lines[i]:Hide() end
	if p.rows ~= row then
		p.rows = row
		p.rule:ClearAllPoints()
		p.rule:SetPoint("TOPLEFT", 0, -27 - row * 24)
		p.rule:SetPoint("TOPRIGHT", 0, -27 - row * 24)
		p.body:ClearAllPoints()
		p.body:SetPoint("TOPLEFT", 0, -30 - row * 24)
		p.body:SetPoint("BOTTOMRIGHT", 0, 0)
	end
	if not sub or layoutOnly then return end
	if p.current and p.current ~= sub.id and p.panels[p.current] then
		p.panels[p.current]:Hide()
		for _, s in ipairs(p.subs) do
			if s.id == p.current and s.onHide then s.onHide() end
		end
	end
	p.current, DT.db.tabs.sub[p.id] = sub.id, sub.id
	if not p.panels[sub.id] then
		local panel = CreateFrame("Frame", nil, p.body)
		panel:SetAllPoints()
		-- (kept only once it is built: one that failed is built anew at the next look, not left half-made)
		local ok, err = pcall(sub.create, panel)
		if not ok then
			panel:Hide()
			geterrorhandler()(err)
			return
		end
		p.panels[sub.id] = panel
	end
	p.panels[sub.id]:Show()
	if sub.onShow then sub.onShow() end
end

-- the tabs on the bar (modules' own, and the places) in the user's order; `all` includes the hidden ones
function UI:TabList(all)
	local list, listed, hidden = {}, {}, DT.db.tabs.hidden
	for _, p in pairs(places) do p.subs = {} end
	for _, mod in DT:Enabled() do
		-- (a module has one tab, or several: mod.tabs)
		for _, tab in ipairs(mod.tabs or { mod.tab }) do
			if tab.under then
				local p = Place(tab.under)
				p.subs[#p.subs + 1] = tab
				if not listed[p] and (all or not hidden[p.id]) then listed[p], list[#list + 1] = true, p end
			elseif all or not hidden[tab.id] then
				list[#list + 1] = tab
			end
		end
	end
	for _, p in pairs(places) do
		table.sort(p.subs, function(a, b)
			if (a.defaultOrder or 100) ~= (b.defaultOrder or 100) then return (a.defaultOrder or 100) < (b.defaultOrder or 100) end
			return a.id < b.id
		end)
	end
	table.sort(list, function(a, b)
		if Rank(a) ~= Rank(b) then return Rank(a) < Rank(b) end
		return a.id < b.id
	end)
	return list
end

-- a tab by its name: one on the bar, or a sub-tab (then its place, and the sub-tab)
local function Find(id)
	if id == "settings" then return settingsTab end
	local list = UI:TabList(true)
	for _, tab in ipairs(list) do
		if tab.id == id then return tab end
	end
	for _, tab in ipairs(list) do
		for _, sub in ipairs(tab.subs or {}) do
			if sub.id == id then return tab, sub end
		end
	end
end

function UI:HasTab(id)
	return Find(id) ~= nil
end

-- dir -1 = earlier, 1 = later
function UI:MoveTab(id, dir)
	local list, rank = self:TabList(true), DT.db.tabs.rank
	for i, tab in ipairs(list) do rank[tab.id] = i end
	for i, tab in ipairs(list) do
		local other = list[i + dir]
		if tab.id == id and other then rank[tab.id], rank[other.id] = rank[other.id], rank[tab.id] end
	end
	self:Layout()
end

function UI:Layout()
	local list = self:TabList()
	list[#list + 1] = settingsTab
	local classic = DT:Theme().classic and true or false
	local topY = classic and -11 or -6
	-- tabs of a different group (tab.group, 1 if not given) stand apart, behind a thin line
	local x, lines = classic and 126 or 120, 0
	for i, tab in ipairs(list) do
		local before = list[i - 1]
		if before and tab ~= settingsTab and (tab.group or 1) ~= (before.group or 1) then
			lines = lines + 1
			local line = separators[lines]
			if not line then
				line = frame:CreateTexture(nil, "ARTWORK")
				line:SetColorTexture(1, 1, 1, 0.25)
				line:SetSize(1, 18)
				separators[lines] = line
			end
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", x + 5, topY - 2)
			line:Show()
			x = x + 14
		end
		local b = buttons[i]
		if not b then
			b = DT:SkinButton(CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"))
			b:SetScript("OnClick", function(self) UI:Show(self.id) end)
			b:SetScript("OnEnter", function(self)
				if not self.tip then return end
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				GameTooltip:AddLine(self.tip)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			b.icon = b:CreateTexture(nil, "OVERLAY")
			b.icon:SetSize(16, 16)
			b.icon:SetPoint("CENTER")
			buttons[i] = b
		end
		b.id = tab.id
		-- a tab may show a picture instead of its name (tab.icon = { atlas =, texture = }): a narrow button,
		-- its name on hover
		local icon = tab.icon
		b:SetSize(icon and 28 or 84, 22)
		b.icon:SetShown(icon and true or false)
		b.tip, b.isIcon = icon and tab.title or nil, icon and true or false
		if icon then
			local atlas = icon.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(icon.atlas) and icon.atlas
			if atlas and b.icon.SetAtlas then b.icon:SetAtlas(atlas) else b.icon:SetTexture(icon.texture) end
		end
		-- Settings sits apart, on the right: it is not one of the working tabs
		b:ClearAllPoints()
		if tab == settingsTab then b:SetPoint("TOPRIGHT", classic and -38 or -34, topY) else b:SetPoint("TOPLEFT", x, topY) end
		b.x = x
		x = x + (icon and 32 or 88)
		b:SetText(icon and "" or tab.title)
		b:Show()
		if tab.id == current then b:LockHighlight() else b:UnlockHighlight() end
	end
	for i = #list + 1, #buttons do buttons[i]:Hide() end
	for i = lines + 1, #separators do separators[i]:Hide() end
end

-- Opens the window on a tab: the one asked for (hidden ones too), else the last one used, else the first.
function UI:Show(id)
	local tab, sub = Find(id)
	if not tab then tab = Find(current) or Find(DT.db.lastTab) end
	if not tab or (not id and tab ~= settingsTab and DT.db.tabs.hidden[tab.id]) then tab = self:TabList()[1] or settingsTab end
	if tab.place then tab.want = sub end -- (a sub-tab asked for by name: its place opens on it)
	if current and current ~= tab.id and panels[current] then
		panels[current]:Hide()
		local old = Find(current)
		if old and old.onHide then old.onHide() end
	end
	current, DT.db.lastTab = tab.id, tab.id
	if not panels[tab.id] then
		local panel = CreateFrame("Frame", nil, body)
		panel:SetAllPoints()
		local ok, err = pcall(tab.create, panel)
		if not ok then
			panel:Hide()
			frame:Show()
			self:Layout()
			geterrorhandler()(err)
			return
		end
		panels[tab.id] = panel
	end
	panels[tab.id]:Show()
	frame:Show()
	self:Layout()
	if tab.onShow then tab.onShow() end
end

-- the window back to the size and place it began with (a way out when it has got off the screen)
function UI:ResetWindow()
	DT.db.pos, DT.db.size = nil, nil
	frame:StopMovingOrSizing()
	frame:ClearAllPoints()
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	self:Show()
end

function UI:Toggle()
	if frame:IsShown() then frame:Hide() else self:Show() end
end

DT:On("PLAYER_LOGIN", function()
	local pos, size = DT.db.pos, DT.db.size
	if size then frame:SetSize(Fit(size[1], size[2])) end -- (a size saved too big for this screen is cut down)
	if pos then
		frame:ClearAllPoints()
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	end
end)

---------------------------------------------------------------------------
-- Settings tab: sections down the left, the picked one on the right
---------------------------------------------------------------------------
-- UI:Section(id, title, order, build): build(panel, kit) is run once, the first time the Settings tab is opened.
-- kit = { Text, Toggle, Arrow, Button, controls }; a control with a :Load() in kit.controls is brought up to
-- date whenever something changes (UI:Refresh).

local controls = {} -- each has :Load()
local sections, sectionButtons, sectionPanels = {}, {}, {}
local settingsPanel, settingsBody
local SECTION_W = 150

function UI:Section(id, title, order, build)
	sections[#sections + 1] = { id = id, title = title, order = order, build = build }
	table.sort(sections, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.title < b.title
	end)
end

local function Text(parent, font, x, y, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetJustifyH("LEFT")
	fs:SetText(text or "")
	return fs
end

local function Toggle(parent, x, y, text, get, set)
	local cb = DT:SkinCheckBox(CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"))
	cb:SetSize(22, 22)
	cb:SetPoint("TOPLEFT", x, y)
	cb.label = Text(cb, "GameFontHighlightSmall", 26, -5, text)
	cb.Load = function(self) self:SetChecked(get(self) and true or false) end
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false, self)
		UI:Refresh()
	end)
	controls[#controls + 1] = cb
	return cb
end

local function Arrow(parent, x, y, text, click)
	local b = DT:SkinButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
	b:SetSize(22, 20)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", function()
		click()
		UI:Refresh()
	end)
	return b
end

local function Button(parent, x, y, width, text, click)
	local b = DT:SkinButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
	b:SetSize(width, 20)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", function()
		click()
		UI:Refresh()
	end)
	return b
end

UI.kit = { Text = Text, Toggle = Toggle, Arrow = Arrow, Button = Button, controls = controls }

-- shows a section: the one asked for, else the one last looked at, else the first
function UI:ShowSection(id)
	if not settingsPanel then return end
	local pick
	for _, s in ipairs(sections) do
		if s.id == (id or DT.db.settingsSection) then pick = s end
	end
	pick = pick or sections[1]
	DT.db.settingsSection = pick.id
	local gap = 0
	for i, s in ipairs(sections) do
		local b = sectionButtons[i]
		if not b then
			b = CreateFrame("Button", nil, settingsPanel)
			b:SetHeight(20)
			b:SetWidth(SECTION_W - 4)
			b.sel = DT:SkinSelection(b:CreateTexture(nil, "BACKGROUND"), 0.18)
			b.sel:SetAllPoints()
			local glow = DT:SkinHighlight(b:CreateTexture(nil, "HIGHLIGHT"), 0.10, 0.08)
			glow:SetAllPoints()
			b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.label:SetPoint("LEFT", 6, 0)
			b:SetScript("OnClick", function(self) UI:ShowSection(self.id) end)
			sectionButtons[i] = b
		end
		-- (a thin line with room about it before the first section that is no setting: Data Sync)
		if s.order >= 900 and i > 1 and sections[i - 1].order < 900 then
			gap = 13
			UI.sectionLine = UI.sectionLine or settingsPanel:CreateTexture(nil, "ARTWORK")
			UI.sectionLine:SetColorTexture(1, 1, 1, 0.18)
			UI.sectionLine:ClearAllPoints()
			UI.sectionLine:SetPoint("TOPLEFT", 8, -2 - (i - 1) * 21 - 6)
			UI.sectionLine:SetSize(SECTION_W - 16, 1)
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 21 - gap)
		b.gap = gap
		b.id = s.id
		b.label:SetText((s == pick and "|cffffd100" or "|cffffffff") .. s.title .. "|r")
		b.sel:SetShown(s == pick)
		if not sectionPanels[s.id] then
			local panel = CreateFrame("Frame", nil, settingsBody)
			panel:SetAllPoints()
			local ok, err = pcall(s.build, panel, UI.kit)
			if ok then sectionPanels[s.id] = panel else panel:Hide() geterrorhandler()(err) end
		end
		if sectionPanels[s.id] then sectionPanels[s.id]:SetShown(s == pick) end
	end
	UI.sectionButtons, UI.sectionPanels = sectionButtons, sectionPanels
	self:Refresh()
end

-- General
UI:Section("general", "General", 10, function(panel)
	local y = -2
	Text(panel, "GameFontNormal", 4, y, "General")
	y = y - 22
	Toggle(panel, 4, y, "Minimap button",
		function() return not DT.db.minimap.hide end,
		function(on) DT:ShowMinimap(on) end)
	y = y - 22
	Toggle(panel, 4, y, "Coin icons for prices (off: 1g 20s 5c)",
		function() return DT.db.settings.coins end,
		function(on) DT.db.settings.coins = on end)
	y = y - 22
	Toggle(panel, 4, y, "Share with the guild, and receive what it shares: the game database, prices, recipes known, quest rewards, boss loot",
		function() return DT.db.settings.share == true end,
		function(on) DT:SetSharing(on) end)
	y = y - 22
	Toggle(panel, 4, y, "Send guild messages in instances too",
		function() return DT.db.settings.instances end,
		function(on) DT.db.settings.instances = on end)
	y = y - 22
	Toggle(panel, 4, y, "Read NPCs, quests and items in the background after login (their tabs then open at once; a few MB of memory)",
		function() return DT.db.settings.background end,
		function(on)
			DT.db.settings.background = on
			DT:ReadInBackground(on)
		end)
	y = y - 34
	UI.resetWindow = Button(panel, 6, y, 190, "Reset window size and place", function() UI:ResetWindow() end)
	Text(panel, "GameFontDisableSmall", 204, y - 4, "Also: /dt reset, should the window ever be out of reach.")
end)

-- Themes
UI:Section("themes", "Themes", 20, function(panel)
	local THEME_NOTES = {
		original  = "The look DawnTools always had: dark, with the game's own buttons.",
		modern    = "Slate dark panels with crisp 1px borders and cool cyan accents.",
		ellesmere = "Ultra-dark minimal panels matched to EllesmereUI or your class color.",
		classic   = "Classic WoW stone and marble window chrome with gold tooltip borders.",
	}
	local y = -2
	Text(panel, "GameFontNormal", 4, y, "Themes")
	y = y - 20
	Text(panel, "GameFontDisableSmall", 4, y, "Switches at once, on every tab.")
	y = y - 28
	for _, id in ipairs(DT.THEME_ORDER) do
		local def = DT.THEMES[id]
		local b = Button(panel, 6, y, 118, def.name, function() DT:SetTheme(id) end)
		b.Load = function(self)
			if DT:Theme().id == id then self:LockHighlight() else self:UnlockHighlight() end
		end
		controls[#controls + 1] = b
		Text(panel, "GameFontHighlightSmall", 134, y - 4, THEME_NOTES[id] or "")
		y = y - 28
	end
end)

-- Tabs & Modules: the tabs on the left, each with the pages under it listed beneath its name; the modules in
-- three columns on the right, by kind (a module's `kind`): what has a tab or a page of its own (two columns),
-- the tools ("tool"), and under the first two what works behind the scenes ("internal": nothing to look at;
-- its `about` is said when hovered).
-- At the window's least size the body is some 720 wide and 330 high: everything on the left keeps left of the
-- modules, and the lists end within the window.
local MODULES_X, MODULE_COL_W, MODULE_ROW = 310, 135, 20
local TAB_TEXT_W = MODULES_X - 56 - 26 - 12 -- a tab's name and its pages: this wide, then the modules begin
UI:Section("tabs", "Tabs & Modules", 30, function(panel)
	Text(panel, "GameFontNormal", 4, -2, "On the bar")
	local note = Text(panel, "GameFontDisableSmall", 4, -20, "A hidden tab keeps working: /dt <name> still opens it. The arrows move a tab along the bar.")
	note:SetWidth(MODULES_X - 16)
	note:SetWordWrap(true)
	-- one row per position: its tab changes as they are moved. Under a tab's name, the pages it holds; a row is
	-- as tall as that list, so each row is placed under the one before when it is read.
	UI.tabBoxes = {}
	local y
	for i = 1, #UI:TabList(true) do
		local function Tab() return UI:TabList(true)[i] end
		local cb
		cb = Toggle(panel, 56, 0, "",
			function(self)
				local subs = {}
				for n, sub in ipairs(Tab().subs or {}) do subs[n] = sub.title end
				local pages = table.concat(subs, ", ")
				self.label:SetText(Tab().title)
				self.pages:SetText(pages)
				if i == 1 then y = -48 end
				self:ClearAllPoints()
				self:SetPoint("TOPLEFT", panel, "TOPLEFT", 56, y)
				self.y = y
				local tall = 0
				if pages ~= "" then
					tall = self.pages.GetStringHeight and self.pages:GetStringHeight() or 0
					if not tall or tall <= 0 then tall = math.ceil(#pages * 5.5 / TAB_TEXT_W) * 11 end -- (not laid out yet: by its length)
					tall = tall + 5
				end
				y = y - 22 - tall
				self.bottom = y
				return not DT.db.tabs.hidden[Tab().id]
			end,
			function(on) DT.db.tabs.hidden[Tab().id] = not on or nil end)
		cb.pages = Text(cb, "GameFontDisableSmall", 26, -21, "")
		cb.pages:SetWidth(TAB_TEXT_W)
		cb.pages:SetWordWrap(true)
		cb.label:SetWidth(TAB_TEXT_W)
		cb.label:SetWordWrap(false)
		cb.up = Arrow(panel, 0, 0, "^", function() UI:MoveTab(Tab().id, -1) end)
		cb.down = Arrow(panel, 0, 0, "v", function() UI:MoveTab(Tab().id, 1) end)
		cb.up:ClearAllPoints()
		cb.up:SetPoint("TOPLEFT", cb, "TOPLEFT", -52, -1)
		cb.down:ClearAllPoints()
		cb.down:SetPoint("TOPLEFT", cb, "TOPLEFT", -28, -1)
		UI.tabBoxes[i] = cb
	end
	-- the modules, by kind
	Text(panel, "GameFontNormal", MODULES_X, -2, "Modules")
	Text(panel, "GameFontDisableSmall", MODULES_X + 66, -4, "Off = not loaded at all. After /reload.")
	local kinds = { page = {}, tool = {}, internal = {} }
	for _, name in ipairs(DT.order) do
		local list = kinds[DT.modules[name].kind or "page"] or kinds.page
		list[#list + 1] = name
	end
	UI.moduleBoxes = {}
	local half = math.ceil(#kinds.page / 2)
	local function Head(x, top, text) Text(panel, "GameFontNormalSmall", x + 2, top - 4, text) end
	local function Box(name, x, top)
		local mod = DT.modules[name]
		local cb = Toggle(panel, x, top, mod.title or name,
			function() return DT.db.modules[name] ~= false end,
			function(on)
				DT.db.modules[name] = on
				DT:Print("%s %s after /reload.", mod.title or name, on and "is back" or "is off")
			end)
		cb.label:SetWidth(MODULE_COL_W - 30)
		cb.label:SetWordWrap(false)
		if mod.about then
			cb:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(mod.title or name)
				GameTooltip:AddLine(mod.about, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		cb.x, cb.y, cb.module = x, top, name
		UI.moduleBoxes[#UI.moduleBoxes + 1] = cb
	end
	local top = -24
	Head(MODULES_X, top, "Tabs and pages")
	for n, name in ipairs(kinds.page) do
		Box(name, MODULES_X + (n > half and MODULE_COL_W or 0), top - MODULE_ROW - ((n - 1) % half) * MODULE_ROW)
	end
	Head(MODULES_X + 2 * MODULE_COL_W, top, "Tools")
	for n, name in ipairs(kinds.tool) do Box(name, MODULES_X + 2 * MODULE_COL_W, top - n * MODULE_ROW) end
	if kinds.internal[1] then
		top = top - (half + 1) * MODULE_ROW - 8
		Head(MODULES_X, top, "Behind the scenes  |cff888888(hover for what it does)|r")
		for n, name in ipairs(kinds.internal) do Box(name, MODULES_X, top - n * MODULE_ROW) end
	end
end)

-- Data Sync: what has gone to the guild and come from it, counted (Comms:Totals); Data Storage: what is held
local function Size(bytes)
	if bytes < 1024 then return bytes .. " B" end
	if bytes < 1024 * 1024 then return ("%.1f KB"):format(bytes / 1024) end
	return ("%.1f MB"):format(bytes / 1024 / 1024)
end

function UI:SyncReport()
	local sync, lines = DT.Comms:Totals(), {}
	local names, all = {}, { o = 0, ob = 0, i = 0, ib = 0 }
	for name in pairs(sync.mods) do names[#names + 1] = name end
	table.sort(names)
	local function Line(title, m)
		return ("|cffffd100%s|r  sent %d messages (%s), received %d (%s)"):format(title, m.o, Size(m.ob), m.i, Size(m.ib))
	end
	lines[#lines + 1] = ("Guild messages since %s:"):format(date("%d %b %Y", sync.since))
	for _, name in ipairs(names) do
		local m = sync.mods[name]
		for key in pairs(all) do all[key] = all[key] + (tonumber(m[key]) or 0) end
		lines[#lines + 1] = Line(name == "core" and "Who has the addon" or DT.modules[name] and DT.modules[name].title or name, m)
	end
	lines[#lines + 1] = names[1] and Line("Total", all) or "|cff888888Nothing sent or received yet.|r"
	if DT.DBSync and DT.DBSync.Report then
		lines[#lines + 1] = " "
		lines[#lines + 1] = "Game database, by whisper (this session):"
		for _, line in ipairs(DT.DBSync.Report()) do lines[#lines + 1] = "|cffaaaaaa" .. line .. "|r" end
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] = "This session:"
	for _, line in ipairs(DT.Comms:Report()) do lines[#lines + 1] = "|cffaaaaaa" .. line .. "|r" end
	return table.concat(lines, "\n")
end

-- Data Storage: what is held on this computer, and the other addons it is read from
function UI:StorageReport()
	local lines = { "Held on this computer:" }
	local held = false
	for _, mod in DT:Enabled() do
		if mod.held then
			held = true
			lines[#lines + 1] = ("|cffffd100%s|r  %s"):format(mod.title or mod.name, mod.held())
		end
	end
	if not held then lines[#lines + 1] = "|cff888888Nothing.|r" end
	lines[#lines + 1] = " "
	lines[#lines + 1] = "Other addons DawnTools reads if you have them (none is required):"
	local STATE = { loaded = "|cff40ff40installed|r", off = "|cffffd100installed, switched off|r", missing = "|cff888888not installed|r" }
	for _, dep in ipairs(UI.DEPS) do
		lines[#lines + 1] = ("|cffffd100%s|r  %s  |cffaaaaaa%s|r"):format(dep[1], STATE[UI:AddonState(dep[1])], dep[2])
	end
	return table.concat(lines, "\n")
end

-- The other addons DawnTools reads when they are there (all optional), and what for
UI.DEPS = {
	{ "QuestieDB", "|cffffd100the one to have:|r the NPC, Quests, Items and Zones tabs, a dungeon's quests, who sells or drops what, where a recipe comes from" },
	{ "Questie", "not needed: QuestieDB alone is enough" },
	{ "Auctionator", "extra: its price history, for you only" },
	{ "TomTom", "extra: waypoint arrows (without it: the game's map pin)" },
	{ "GatherMate2", "extra: herb and ore nodes you found, on the Zones tab" },
	{ "AtlasLootClassic", "extra: raids and drop chances on the Dungeons tab; which items are crafted" },
	{ "OneForAll", "extra: its dungeon bosses and drops go into the game database (and so to guildmates); the quests of Forever's own dungeons" },
}

-- "loaded", "off" (installed, not switched on) or "missing"
function UI:AddonState(name)
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	local ok, is = pcall(function() return loaded(name) end)
	if ok and is then return "loaded" end
	local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	local got, _, _, _, _, reason = pcall(function() return info(name) end)
	if got and reason ~= nil and reason ~= "MISSING" then return "off" end
	return "missing"
end

-- How complete each kind of data is: every module that has a `progress` gives rows of
--   { label, have, total (nil: cannot be counted yet), note, sub = a part of `have` drawn as a thin second bar, subNote = what that is }
function UI:SyncProgress()
	local rows = {}
	for _, mod in DT:Enabled() do
		local ok, list = pcall(mod.progress or function() end)
		for _, row in ipairs(ok and list or {}) do rows[#rows + 1] = row end
	end
	return rows
end

local BAR_X, BAR_W, BAR_H = 250, 220, 14
UI:Section("sync", "Data Sync", 900, function(panel)
	Text(panel, "GameFontNormal", 4, -2, "Data Sync")
	local note = Text(panel, "GameFontDisableSmall", 4, -22, "What DawnTools has sent to the guild and received from it, and the game database's requests each way. Only what you agreed to share is ever sent. To copy: click in the box, Ctrl+A, Ctrl+C.")
	note:SetWidth(560)
	note:SetWordWrap(true)
	-- the report in a box that scrolls and can be copied from (click in it, Ctrl+A, Ctrl+C): plain text, no colours
	local back = panel:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", 4, -52)
	back:SetPoint("BOTTOMRIGHT", -6, 36)
	back:SetColorTexture(0, 0, 0, 0.35)
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -56)
	scroll:SetPoint("BOTTOMRIGHT", -28, 40)
	local report = CreateFrame("EditBox", nil, scroll)
	report:SetMultiLine(true)
	report:SetAutoFocus(false)
	report:SetFontObject(GameFontHighlightSmall)
	report:SetWidth(540)
	report:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scroll:SetScrollChild(report)
	-- (not while it is being copied from: a new text would undo the selection)
	report.Load = function(self)
		if self:HasFocus() then return end
		self:SetText((UI:SyncReport():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
	end
	controls[#controls + 1] = report
	UI.syncText = report
	local reset = Button(panel, 4, -8, 150, "Start counting anew", function() DT.Comms:ResetTotals() end)
	reset:ClearAllPoints()
	reset:SetPoint("BOTTOMLEFT", 4, 8)
	UI.syncReset = reset
	local now = Button(panel, 4, -8, 150, "Sync now", function() DT.DB.Slash("sync") if UI.Refresh then UI:Refresh() end end)
	now:ClearAllPoints()
	now:SetPoint("BOTTOMLEFT", 160, 8)
	UI.syncNow = now
end)

UI:Section("storage", "Data Storage", 905, function(panel)
	Text(panel, "GameFontNormal", 4, -2, "Data Storage")
	local note = Text(panel, "GameFontDisableSmall", 4, -22, "How complete each kind of data is on this computer, what is held, and the other addons it is read from.")
	note:SetWidth(560)
	note:SetWordWrap(true)
	local bars = {}
	UI.storageBars = bars
	local function Bar(i)
		local b = CreateFrame("Frame", nil, panel)
		b:SetSize(700, 20)
		b:SetPoint("TOPLEFT", 4, -54 - (i - 1) * 21)
		b.label = Text(b, "GameFontHighlightSmall", 0, -3)
		b.back = b:CreateTexture(nil, "BACKGROUND")
		b.back:SetPoint("TOPLEFT", BAR_X, -3)
		b.back:SetSize(BAR_W, BAR_H)
		b.back:SetColorTexture(1, 1, 1, 0.08)
		b.fill = b:CreateTexture(nil, "ARTWORK")
		b.fill:SetPoint("TOPLEFT", BAR_X, -3)
		b.fill:SetHeight(BAR_H)
		b.sub = b:CreateTexture(nil, "OVERLAY") -- (a thin bright stripe along the foot of the bar)
		b.sub:SetPoint("TOPLEFT", BAR_X, -3 - BAR_H + 3)
		b.sub:SetHeight(3)
		b.sub:SetColorTexture(0.4, 0.8, 1, 0.95)
		b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.count:SetPoint("CENTER", b.back, "CENTER", 0, 0)
		b.note = Text(b, "GameFontDisableSmall", BAR_X + BAR_W + 8, -3)
		bars[i] = b
		return b
	end
	local report = Text(panel, "GameFontHighlightSmall", 4, -52)
	report:SetWidth(560)
	report:SetWordWrap(true)
	report:SetSpacing(3)
	report.Load = function(self)
		-- (worked out only while the page is the one looked at: counting goes through the long lists)
		if DT.db.settingsSection ~= "storage" then return end
		local rows = UI:SyncProgress()
		for i = 1, math.max(#rows, #bars) do
			local row, b = rows[i], bars[i] or (rows[i] and Bar(i))
			if b then
				b:SetShown(row ~= nil)
				if row then
					local have, total = row[2] or 0, row[3]
					local share = total and total > 0 and math.min(1, have / total) or 0
					b.share = share
					b.label:SetText(row[1])
					b.fill:SetWidth(math.max(1, share * BAR_W))
					-- red when hardly begun, through gold, to green when nearly all there
					if share >= 0.9 then b.fill:SetColorTexture(0.25, 0.8, 0.25, 0.75) elseif share >= 0.3 then b.fill:SetColorTexture(0.9, 0.75, 0.2, 0.75) else b.fill:SetColorTexture(0.85, 0.35, 0.25, 0.75) end
					b.fill:SetShown(total ~= nil)
					b.count:SetText(total and ("%d / %d  (%d%%)"):format(have, total, math.floor(share * 100 + 0.5)) or ("%d  |cff888888of ?|r"):format(have))
					local sub = row.sub and total and total > 0 and math.min(1, row.sub / total) or nil
					b.subShare = sub
					b.sub:SetShown(sub ~= nil)
					b.sub:SetWidth(math.max(1, (sub or 0) * BAR_W))
					b.note:SetText((row.sub and ("|cff66ccff%d %s|r  "):format(row.sub, row.subNote or "") or "") .. (row[4] or ""))
				end
			end
		end
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", 4, -54 - #rows * 21 - 12)
		self:SetText(UI:StorageReport())
	end
	controls[#controls + 1] = report
	UI.storageText = report
end)

-- Data Debug: what the addons cost (memory, time), as lines to copy into a bug report. Reads, changes nothing.
-- Per-addon time needs the game's script profiling (/console scriptProfile 1, then /reload; it slows everything:
-- turn it off after).
local Usage = {}
DT.Usage = Usage
local function Addons()
	local A = C_AddOns or {}
	local num, info, loaded = A.GetNumAddOns or GetNumAddOns, A.GetAddOnInfo or GetAddOnInfo, A.IsAddOnLoaded or IsAddOnLoaded
	local out = {}
	for i = 1, num and num() or 0 do
		if loaded and loaded(i) then out[#out + 1] = { i = i, name = (info(i)) } end
	end
	return out
end
local function Gc(what) local ok, n = pcall(collectgarbage, what) return ok and n or 0 end -- (not in every Lua)
local function Profiling() return GetCVar and GetCVar("scriptProfile") == "1" and UpdateAddOnCPUUsage and GetAddOnCPUUsage and true or false end
local function Top(list, key, n, fmt)
	table.sort(list, function(a, b) return a[key] > b[key] end)
	local out = {}
	for k = 1, math.min(n, #list) do out[#out + 1] = ("  %-28s " .. fmt):format(list[k].name, list[k][key]) end
	return out
end
function Usage.Head()
	local version, build = GetBuildInfo and GetBuildInfo()
	return ("DawnTools %s, client %s (%s), %s"):format(DT.VERSION, tostring(version), tostring(build), date and date("%Y-%m-%d %H:%M") or "")
end
function Usage.Memory()
	local list = Addons()
	if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
	for _, a in ipairs(list) do a.mb = (GetAddOnMemoryUsage and GetAddOnMemoryUsage(a.i) or 0) / 1024 end
	local out = { ("Memory: %.1f MB in use by all addons (Lua)."):format(Gc("count") / 1024), "The most:" }
	for _, line in ipairs(Top(list, "mb", 12, "%7.1f MB")) do out[#out + 1] = line end
	local b = DT.Bis and DT.Bis.stats
	if b then out[#out + 1] = ("DawnTools BiS since the /reload: worked out %d times (%d kept as they were), %d sets solved."):format(b.computes, b.kept, b.solves) end
	return out
end
function Usage.Cpu()
	if not Profiling() then
		return { "Time per addon: script profiling is off. Type /console scriptProfile 1, /reload, play a few minutes, press again.",
			"(It slows the game while on: /console scriptProfile 0 and /reload after.)" }
	end
	UpdateAddOnCPUUsage()
	local list, secs = Addons(), GetTime and GetTime() or 1
	for _, a in ipairs(list) do a.ms = GetAddOnCPUUsage(a.i) end
	local out = { "Time per addon since the /reload (ms of script time):" }
	for _, line in ipairs(Top(list, "ms", 12, "%9.0f ms")) do out[#out + 1] = line end
	return out
end
-- The world map opened and timed: the opening itself, then the longest of the next frames (map pins are often
-- drawn a frame or more later), the garbage made, and with profiling on what each addon spent in it all.
local FRAMES = 10
function Usage.Map(done)
	if InCombatLockdown and InCombatLockdown() then return done({ "Map: not in a fight. Try again out of combat." }) end
	if not (ToggleWorldMap and WorldMapFrame) then return done({ "Map: no world map to open." }) end
	if WorldMapFrame:IsShown() then ToggleWorldMap() end
	local list, cpu = Addons(), Profiling()
	if cpu then
		UpdateAddOnCPUUsage()
		for _, a in ipairs(list) do a.was = GetAddOnCPUUsage(a.i) end
	end
	Gc("stop") -- (so a garbage collection step in between does not hide what was made)
	local mem, t0 = Gc("count"), debugprofilestop()
	ToggleWorldMap()
	local open = debugprofilestop() - t0
	local watch, frames, longest, last = CreateFrame("Frame"), 0, 0, debugprofilestop()
	watch:SetScript("OnUpdate", function(self)
		local now = debugprofilestop()
		longest, last, frames = math.max(longest, now - last), now, frames + 1
		if frames < FRAMES then return end
		self:SetScript("OnUpdate", nil)
		local made = (Gc("count") - mem) / 1024
		Gc("restart")
		local out = { ("Map: opened in %.0f ms; the longest of the next %d frames %.0f ms; %.1f MB of garbage made."):format(open, FRAMES, longest, math.max(0, made)) }
		if cpu then
			UpdateAddOnCPUUsage()
			for _, a in ipairs(list) do a.ms = GetAddOnCPUUsage(a.i) - (a.was or 0) end
			out[#out + 1] = "Script time per addon over it:"
			for _, line in ipairs(Top(list, "ms", 8, "%7.1f ms")) do out[#out + 1] = line end
		else
			out[#out + 1] = "For each addon's share: /console scriptProfile 1, /reload, run it again (turn it off after)."
		end
		done(out)
	end)
end
-- /dt map: the same, said in the chat
function DT.MapTime()
	Usage.Map(function(lines)
		for _, line in ipairs(lines) do DT:Print("%s", line) end
		DT.db.debugLog = Usage.Head() .. "\n" .. table.concat(lines, "\n")
	end)
end

UI:Section("debug", "Data Debug", 910, function(panel)
	Text(panel, "GameFontNormal", 4, -2, "Data Debug")
	local note = Text(panel, "GameFontDisableSmall", 4, -22, "What the addons cost in memory and time. Press a button; the lines come in the box below. Click in it, Ctrl+A, Ctrl+C, and paste them where they are asked for.")
	note:SetWidth(560)
	note:SetWordWrap(true)
	local back = panel:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", 4, -86)
	back:SetPoint("BOTTOMRIGHT", -6, 8)
	back:SetColorTexture(0, 0, 0, 0.35)
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -90)
	scroll:SetPoint("BOTTOMRIGHT", -28, 12)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	box:SetWidth(540)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scroll:SetScrollChild(box)
	UI.debugBox = box
	local function Show(lines)
		local text = box:GetText() or ""
		box:SetText((text ~= "" and (text .. "\n\n") or (Usage.Head() .. "\n")) .. table.concat(lines, "\n"))
		DT.db.debugLog = box:GetText() -- (kept in the saved file at the next /reload: readable outside the game)
	end
	local x = 4
	for _, b in ipairs({ { "Memory", 90, function() Show(Usage.Memory()) end }, { "Time (CPU)", 90, function() Show(Usage.Cpu()) end },
		{ "Open the map", 110, function() Show({ "Map: opening..." }) Usage.Map(Show) end }, { "Clear", 70, function() box:SetText("") end } }) do
		Button(panel, x, -54, b[2], b[1], b[3])
		x = x + b[2] + 6
	end
end)

local function BuildSettings(panel)
	settingsPanel = panel
	local side = DT:SkinFrame(CreateFrame("Frame", nil, panel, "BackdropTemplate"), "sidebar")
	side:SetPoint("TOPLEFT", 0, 0)
	side:SetPoint("BOTTOMLEFT", 0, 0)
	side:SetWidth(SECTION_W)
	settingsBody = CreateFrame("Frame", nil, panel)
	settingsBody:SetPoint("TOPLEFT", SECTION_W + 10, 0)
	settingsBody:SetPoint("BOTTOMRIGHT", 0, 0)
	local function Switch(p, y, mod, s)
		Toggle(p, 4, y, s.label,
			function() return mod.db.settings[s.key] end,
			function(on)
				mod.db.settings[s.key] = on
				DT:Fire("DT_SETTINGS", mod.name, s.key)
			end)
	end
	-- every line DawnTools puts on a tooltip, all modules' together, in one section (a switch marked tooltip = true)
	local tips = {}
	for _, mod in DT:Enabled() do
		for _, s in ipairs(mod.settings or {}) do
			if s.tooltip then tips[#tips + 1] = { mod, s } end
		end
	end
	if tips[1] then
		UI:Section("tooltips", "Tooltips", 45, function(p)
			Text(p, "GameFontNormal", 4, -2, "Tooltips")
			local y = -24
			for _, t in ipairs(tips) do
				Switch(p, y, t[1], t[2])
				y = y - 22
			end
		end)
	end
	-- a section for every module that has switches of its own (other than its tooltip lines)
	local order = 50
	for _, mod in DT:Enabled() do
		local own = {}
		for _, s in ipairs(mod.settings or {}) do
			if not s.tooltip then own[#own + 1] = s end
		end
		if own[1] then
			order = order + 1
			UI:Section("module:" .. mod.name, mod.title or mod.name, order, function(p)
				local y = -2
				Text(p, "GameFontNormal", 4, y, mod.title or mod.name)
				y = y - 22
				for _, s in ipairs(own) do
					Switch(p, y, mod, s)
					y = y - 22
				end
				if mod.status then
					local status = Text(p, "GameFontDisableSmall", 8, y - 6)
					status:SetWidth(520)
					status:SetWordWrap(true)
					status.Load = function(self) self:SetText(mod:status()) end
					controls[#controls + 1] = status
				end
			end)
		end
	end
end

settingsTab = { id = "settings", title = "Settings", create = BuildSettings, onShow = function() UI:ShowSection() end }

-- redraws what the core owns: the tab bar and the Settings controls
function UI:Refresh()
	self:Layout()
	for _, c in ipairs(controls) do c:Load() end
end

---------------------------------------------------------------------------
-- /dt selftest
---------------------------------------------------------------------------
-- Opens every tab with the real widgets and runs each module's own checks. Changes nothing. Errors are
-- listed in chat instead of stopping at the first one.

function UI:SelfTest()
	local failures, count = {}, 0
	local function Try(name, fn)
		count = count + 1
		local ok, err = pcall(fn)
		if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
	end
	local wasShown, wasTab = frame:IsShown(), current
	local tabs = self:TabList(true)
	tabs[#tabs + 1] = settingsTab
	for _, tab in ipairs(tabs) do
		Try(tab.id .. " tab", function() UI:Show(tab.id) end)
		for _, sub in ipairs(tab.subs or {}) do
			Try(sub.id .. " tab", function() UI:Show(sub.id) end)
		end
	end
	for _, mod in DT:Enabled() do
		if mod.selfTest then mod:selfTest(Try) end
		if mod.status then Try(mod.name .. " status", function() assert(type(mod:status()) == "string") end) end
		if mod.hello then Try(mod.name .. " hello", function() mod:hello() end) end
	end
	Try("message packing", function()
		local LD, text = LibStub("LibDeflate"), ("123,4500,20,1700000000,Name;"):rep(40)
		local wire = LD:EncodeForWoWAddonChannel(LD:CompressDeflate(text))
		assert(LD:DecompressDeflate(LD:DecodeForWoWAddonChannel(wire)) == text)
	end)
	Try("restore", function()
		if wasTab then UI:Show(wasTab) end
		if not wasShown then frame:Hide() end
	end)

	if #failures == 0 then
		DT:Print("selftest: %d checks passed.", count)
	else
		DT:Print("selftest: %d of %d checks FAILED:", #failures, count)
		for _, f in ipairs(failures) do DT:Print("  " .. f) end
	end
	return #failures
end

---------------------------------------------------------------------------
-- A dropdown: a button that opens a list to pick from
---------------------------------------------------------------------------
-- DT:Dropdown(parent, width, o) -> the button (its .label is the caller's to set; .menu is the list)
--   o.entries = function() -> { { value =, text =, n = a count shown in grey, always = stays while searching, color = "|cff..." instead of white }, ... }
--   o.picked  = function() -> the value picked now (its entry is lit, and the list opens at it)
--   o.pick    = function(value)
--   o.search  = true: a box to type in on top; the list narrows to what contains the text, Enter takes the first
--   o.rows    = most entries shown at once (18); the mouse wheel moves the rest
--   o.menuWidth
local DROP_H = 18
function DT:Dropdown(parent, width, o)
	local b = DT:SkinFrame(CreateFrame("Button", nil, parent, "BackdropTemplate"), "panel")
	b:SetSize(width, 18)
	local btnHover = DT:SkinHighlight(b:CreateTexture(nil, "HIGHLIGHT"), 0.12, 0)
	btnHover:SetAllPoints()
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", 6, 0)
	b.label:SetPoint("RIGHT", -16, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetWordWrap(false)
	local arrow = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrow:SetPoint("RIGHT", -5, 0)
	arrow:SetText("|cffffd100v|r")

	local menuWidth, most = o.menuWidth or math.max(width, 200), o.rows or 18
	local menu = DT:SkinFrame(CreateFrame("Frame", nil, parent, "BackdropTemplate"), "menu")
	menu:SetFrameStrata("DIALOG")
	menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -1)
	menu:SetWidth(menuWidth)
	menu:EnableMouse(true)
	local top = 2
	local all, shown, offset = {}, {}, 0

	local function Draw()
		offset = math.max(0, math.min(offset, #shown - most))
		local picked = o.picked()
		local _, _, _, _, accentHex = DT:Theme()
		for i = 1, most do
			local e, row = shown[i + offset], menu.rows[i]
			row.entry = e
			row:SetShown(e ~= nil)
			if e then
				row.label:SetText((e.value == picked and accentHex or e.color or "|cffffffff") .. e.text .. "|r" .. (e.n and (" |cff888888" .. e.n .. "|r") or ""))
			end
		end
		local over = #shown > most
		menu.more:SetText(over and ("|cff888888mouse wheel: %d above, %d below|r"):format(offset, math.max(0, #shown - most - offset)) or "")
		menu:SetHeight(top + math.max(1, math.min(#shown, most)) * DROP_H + (over and 20 or 4))
	end
	local function Narrow()
		local q = menu.box and (menu.box:GetText() or ""):lower() or ""
		shown = {}
		for _, e in ipairs(all) do
			if q == "" or e.always or e.text:lower():find(q, 1, true) then shown[#shown + 1] = e end
		end
		Draw()
	end
	local function Take(e)
		menu:Hide()
		if menu.box then menu.box:ClearFocus() end
		o.pick(e.value)
	end

	if o.search then
		top = 26
		menu.box = DT:SkinEditBox(CreateFrame("EditBox", nil, menu, "SearchBoxTemplate"))
		menu.box:SetSize(menuWidth - 18, 18)
		menu.box:SetPoint("TOPLEFT", 11, -4)
		menu.box:SetAutoFocus(false)
		menu.box:HookScript("OnTextChanged", function()
			offset = 0
			Narrow()
		end)
		menu.box:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
			menu:Hide()
		end)
		-- Enter: the first that fits what was typed (not the ones that are always there)
		menu.box:SetScript("OnEnterPressed", function(self)
			local typed = (self:GetText() or "") ~= ""
			for _, e in ipairs(shown) do
				if not (typed and e.always) then return Take(e) end
			end
		end)
	end
	menu.rows = {}
	for i = 1, most do
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(DROP_H)
		row:SetPoint("TOPLEFT", 2, -top - (i - 1) * DROP_H)
		row:SetPoint("RIGHT", -2, 0)
		local highlight = DT:SkinHighlight(row:CreateTexture(nil, "HIGHLIGHT"), 0.14, 0.12)
		highlight:SetAllPoints()
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.label:SetPoint("LEFT", 6, 0)
		row:SetScript("OnClick", function(self)
			if self.entry then Take(self.entry) end
		end)
		menu.rows[i] = row
	end
	menu.more = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	menu.more:SetPoint("BOTTOMLEFT", 8, 4)
	menu:EnableMouseWheel(true)
	menu:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Draw()
	end)
	menu:Hide()
	-- its tab or the window goes away: the list is closed, not left to come back open
	menu:SetScript("OnHide", function(self)
		if self.box then self.box:ClearFocus() end
		self:Hide()
	end)

	b:SetScript("OnClick", function()
		if menu:IsShown() then return menu:Hide() end
		all, offset = o.entries(), 0
		if menu.box then menu.box:SetText("") end
		Narrow()
		local picked = o.picked()
		for i, e in ipairs(shown) do -- (opens at what is picked)
			if picked ~= nil and e.value == picked then offset = i - 3 end
		end
		Draw()
		menu:Show()
		if menu.box then menu.box:SetFocus() end
	end)
	b.menu = menu
	return b
end
