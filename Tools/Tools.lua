-- DawnTools :: Tools
-- A tab of small tools, each on a sub-tab of its own: a row of buttons like the window's own tabs, and the
-- picked tool's panel beneath. A tool is not a module's whole tab but something a module adds here:
--   DT:RegisterTool({ id = "range", title = "Range", order = 10, create = function(parent) end, onShow = fn,
--                     active = function() return true / false end })   optional: a tool that can be on or off;
--                     its sub-tab's name is green while it is on, yellow while it is off
-- (called from the module's onEnable, so a module that is switched off has no sub-tab).

local _, DT = ...
local T = { list = {} }
DT.Tools = T

function DT:RegisterTool(tool)
	T.list[#T.list + 1] = tool
	table.sort(T.list, function(a, b)
		if (a.order or 100) ~= (b.order or 100) then return (a.order or 100) < (b.order or 100) end
		return a.id < b.id
	end)
end

local function Find(id)
	for _, tool in ipairs(T.list) do
		if tool.id == id then return tool end
	end
end

function T.Has(id)
	return Find(id) ~= nil
end

local panel, body, none
local buttons, panels, current = {}, {}, nil

-- shows a tool: the one asked for, else the last one used, else the first
function T.Show(id)
	if not panel then return end
	local tool = Find(id or T.want) or Find(current) or Find(T.db.last) or T.list[1]
	T.want = nil
	none:SetShown(tool == nil)
	for i = 1, math.max(#T.list, #buttons) do
		local t, b = T.list[i], buttons[i]
		if t and not b then
			b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			b:SetSize(84, 22)
			b:SetPoint("TOPLEFT", 2 + (i - 1) * 88, -2)
			b:SetScript("OnClick", function(self) T.Show(self.id) end)
			buttons[i] = b
		end
		if b then
			b:SetShown(t ~= nil)
			if t then
				b.id = t.id
				local on = t.active and t.active()
				b:SetText(on == nil and t.title or ((on and "|cff40ff40" or "|cffffd100") .. t.title .. "|r"))
				if t == tool then b:LockHighlight() else b:UnlockHighlight() end
			end
		end
	end
	if not tool then return end
	if current and current ~= tool.id and panels[current] then panels[current]:Hide() end
	current, T.db.last = tool.id, tool.id
	if not panels[tool.id] then
		local p = CreateFrame("Frame", nil, body)
		p:SetAllPoints()
		local ok, err = pcall(tool.create, p)
		if not ok then
			p:Hide()
			geterrorhandler()(err)
			return
		end
		panels[tool.id] = p
	end
	panels[tool.id]:Show()
	if tool.onShow then tool.onShow() end
end
T.buttons = buttons

-- opens the window on the Tools tab, at one tool
function T.Open(id)
	T.want = id -- (the tab's own showing then goes straight to it)
	DT.UI:Show("tools")
end

local function Build(parent)
	panel = parent
	body = CreateFrame("Frame", nil, panel)
	body:SetPoint("TOPLEFT", 0, -30)
	body:SetPoint("BOTTOMRIGHT", 0, 0)
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.12)
	line:SetPoint("TOPLEFT", 0, -27)
	line:SetPoint("TOPRIGHT", 0, -27)
	line:SetHeight(1)
	none = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	none:SetPoint("TOPLEFT", 6, -8)
	none:SetText("No tool is switched on. (Settings: Modules.)")
end

DT:RegisterModule("tools", {
	profile = { "last" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "Tools",
	version = 1,
	slash = "/dttools",
	-- group 3: behind a separator of its own, after Combat
	tab = { id = "tools", title = "Tools", defaultOrder = 70, group = 3, create = Build, onShow = function() T.Show() end },
	onEnable = function(mod)
		T.db = mod.db
	end,
	selfTest = function(_, Try)
		for _, tool in ipairs(T.list) do
			Try("tool " .. tool.id, function() T.Show(tool.id) end)
		end
	end,
})
