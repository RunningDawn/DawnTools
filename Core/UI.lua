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

local frame = CreateFrame("Frame", "DawnToolsFrame", UIParent, "BackdropTemplate")
frame:SetSize(WIDTH, HEIGHT)
frame:SetPoint("CENTER")
frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
frame:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
frame:SetBackdropBorderColor(0, 0, 0, 1)
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

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
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
	local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
	if sw < MIN_W + 40 or sh < MIN_H + 40 then return math.max(MIN_W, w), math.max(MIN_H, h) end -- (screen size not known yet)
	return math.max(MIN_W, math.min(w, sw - 40)), math.max(MIN_H, math.min(h, sh - 40))
end
grip:SetScript("OnMouseDown", function()
	-- Sizing pulls the bottom right corner, so the window must hang by its top left one: hung by its
	-- centre (as it is until first moved) it grows both ways and jumps out from under the mouse.
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	local w, h = Fit(math.huge, math.huge)
	if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H, w, h) end
	frame:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
	frame:StopMovingOrSizing()
	frame:SetSize(Fit(frame:GetWidth(), frame:GetHeight()))
	DT.db.size = { frame:GetWidth(), frame:GetHeight() }
	-- sizing re-anchors the window: remember where it is now
	local point, _, relative, x, y = frame:GetPoint(1)
	DT.db.pos = { point, relative, x, y }
end)

local body = CreateFrame("Frame", nil, frame)
body:SetPoint("TOPLEFT", 8, -36)
body:SetPoint("BOTTOMRIGHT", -8, 8)

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
		panel:SetScript("OnSizeChanged", function() if p.current then ShowSub(p) end end) -- (a wider window: fewer rows)
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
function ShowSub(p)
	if not p.panel then return end
	DT.db.tabs.sub = DT.db.tabs.sub or {}
	local sub, last = p.want, p.current or DT.db.tabs.sub[p.id]
	p.want = nil
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
			b = CreateFrame("Button", nil, p.panel, "UIPanelButtonTemplate")
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
	if not sub then return end
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
	-- tabs of a different group (tab.group, 1 if not given) stand apart, behind a thin line
	local x, lines = 120, 0
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
			line:SetPoint("TOPLEFT", x + 5, -8)
			line:Show()
			x = x + 14
		end
		local b = buttons[i]
		if not b then
			b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
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
		if tab == settingsTab then b:SetPoint("TOPRIGHT", -34, -6) else b:SetPoint("TOPLEFT", x, -6) end
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
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
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
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
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
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
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
			b.sel = b:CreateTexture(nil, "BACKGROUND")
			b.sel:SetAllPoints()
			b.sel:SetColorTexture(1, 0.82, 0, 0.18)
			local glow = b:CreateTexture(nil, "HIGHLIGHT")
			glow:SetAllPoints()
			glow:SetColorTexture(1, 1, 1, 0.08)
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

-- Tabs & Modules
UI:Section("tabs", "Tabs & Modules", 30, function(panel)
	local y = -2
	Text(panel, "GameFontNormal", 4, y, "On the bar")
	Text(panel, "GameFontDisableSmall", 90, y - 2, "A hidden tab keeps working; /dt <name> still opens it. The arrows move it along the bar.")
	y = y - 22
	-- one row per position: its tab changes as they are moved
	for i = 1, #UI:TabList(true) do
		local function Tab() return UI:TabList(true)[i] end
		local cb = Toggle(panel, 56, y, "",
			function(self)
				local subs = {}
				for n, sub in ipairs(Tab().subs or {}) do subs[n] = sub.title end
				self.label:SetText(Tab().title .. (subs[1] and ("  |cff888888(" .. table.concat(subs, ", ") .. ")|r") or ""))
				return not DT.db.tabs.hidden[Tab().id]
			end,
			function(on) DT.db.tabs.hidden[Tab().id] = not on or nil end)
		cb.up = Arrow(panel, 4, y - 1, "^", function() UI:MoveTab(Tab().id, -1) end)
		cb.down = Arrow(panel, 28, y - 1, "v", function() UI:MoveTab(Tab().id, 1) end)
		y = y - 22
	end
	-- the modules, in a second column
	y = -2
	Text(panel, "GameFontNormal", 330, y, "Modules")
	Text(panel, "GameFontDisableSmall", 396, y - 2, "Off = not loaded at all. After /reload.")
	y = y - 22
	for _, name in ipairs(DT.order) do
		local mod = DT.modules[name]
		Toggle(panel, 330, y, mod.title or name,
			function() return DT.db.modules[name] ~= false end,
			function(on)
				DT.db.modules[name] = on
				DT:Print("%s %s after /reload.", mod.title or name, on and "is back" or "is off")
			end)
		y = y - 22
	end
end)

-- Data Sync: what has gone to the guild and come from it, counted (Comms:Totals), and what is held
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
	lines[#lines + 1] = " "
	lines[#lines + 1] = "Held on this computer:"
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
	lines[#lines + 1] = " "
	lines[#lines + 1] = "This session:"
	for _, line in ipairs(DT.Comms:Report()) do lines[#lines + 1] = "|cffaaaaaa" .. line .. "|r" end
	return table.concat(lines, "\n")
end

-- The other addons DawnTools reads when they are there (all optional), and what for
UI.DEPS = {
	{ "QuestieDB", "the NPC, Quests, Items and Zones tabs; who sells what" },
	{ "Questie", "not needed: QuestieDB alone is enough" },
	{ "Auctionator", "its price history, for you only" },
	{ "TomTom", "waypoint arrows (without it: the map pin)" },
	{ "GatherMate2", "herb and ore nodes you found, on the Zones tab" },
	{ "AtlasLootClassic", "which items are crafted" },
	{ "OneForAll", "the quests of Forever's own dungeons" },
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
	local note = Text(panel, "GameFontDisableSmall", 4, -22, "How complete each kind of data is on this computer, and what DawnTools has sent to the guild and received from it. Only what you agreed to share is ever sent: see each module's section.")
	note:SetWidth(560)
	note:SetWordWrap(true)
	local bars = {}
	UI.syncBars = bars
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
		if DT.db.settingsSection ~= "sync" then return end
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
		self:SetText(UI:SyncReport())
	end
	controls[#controls + 1] = report
	UI.syncText = report
	local reset = Button(panel, 4, -8, 150, "Start counting anew", function() DT.Comms:ResetTotals() end)
	reset:ClearAllPoints()
	reset:SetPoint("BOTTOMLEFT", 4, 8)
	UI.syncReset = reset
end)

local function BuildSettings(panel)
	settingsPanel = panel
	local side = panel:CreateTexture(nil, "BACKGROUND")
	side:SetPoint("TOPLEFT", 0, 0)
	side:SetPoint("BOTTOMLEFT", 0, 0)
	side:SetWidth(SECTION_W)
	side:SetColorTexture(1, 1, 1, 0.04)
	settingsBody = CreateFrame("Frame", nil, panel)
	settingsBody:SetPoint("TOPLEFT", SECTION_W + 10, 0)
	settingsBody:SetPoint("BOTTOMRIGHT", 0, 0)
	-- a section for every module that has switches of its own
	local order = 50
	for _, mod in DT:Enabled() do
		if mod.settings then
			order = order + 1
			UI:Section("module:" .. mod.name, mod.title or mod.name, order, function(p)
				local y = -2
				Text(p, "GameFontNormal", 4, y, mod.title or mod.name)
				y = y - 22
				for _, s in ipairs(mod.settings) do
					Toggle(p, 4, y, s.label,
						function() return mod.db.settings[s.key] end,
						function(on)
							mod.db.settings[s.key] = on
							DT:Fire("DT_SETTINGS", mod.name, s.key)
						end)
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
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 18)
	local shade = b:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, 0.08)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", 6, 0)
	b.label:SetPoint("RIGHT", -16, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetWordWrap(false)
	local arrow = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrow:SetPoint("RIGHT", -5, 0)
	arrow:SetText("|cffffd100v|r")

	local menuWidth, most = o.menuWidth or math.max(width, 200), o.rows or 18
	local menu = CreateFrame("Frame", nil, parent)
	menu:SetFrameStrata("DIALOG")
	menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -1)
	menu:SetWidth(menuWidth)
	menu:EnableMouse(true)
	local back = menu:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.06, 0.06, 0.06, 0.97)
	local top = 2
	local all, shown, offset = {}, {}, 0

	local function Draw()
		offset = math.max(0, math.min(offset, #shown - most))
		local picked = o.picked()
		for i = 1, most do
			local e, row = shown[i + offset], menu.rows[i]
			row.entry = e
			row:SetShown(e ~= nil)
			if e then
				row.label:SetText((e.value == picked and "|cffffd100" or e.color or "|cffffffff") .. e.text .. "|r" .. (e.n and (" |cff888888" .. e.n .. "|r") or ""))
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
		menu.box = CreateFrame("EditBox", nil, menu, "SearchBoxTemplate")
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
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.12)
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
