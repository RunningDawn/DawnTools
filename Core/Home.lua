-- DawnHome
-- The first tab, with a house on its button instead of a word: who the addon is for and by, where things are,
-- and what changed. What a new user sees on first opening the window; after that the window opens on
-- whatever was last looked at, as ever. It can be hidden on the Settings tab like any other.

local _, DT = ...
local H = {}
DT.Home = H

local LINE_H = 14
local panel, guide, log, logLines, logOffset = nil, {}, nil, {}, 0

-- what is where: one line per tab on the bar, its sub-tabs named behind it
local ABOUT = {
	market = "Auction prices, shared with the guild.",
	inventory = "What every character of yours carries and banks.",
	craft = "Fishing spots worth the cast; who in the guild cooks what.",
	world = "Every NPC, quest, item and zone: search, waypoints, chains, sources.",
	combat = "Who killed you, whom you killed, and how.",
	tools = "Small helpers: range, the five-second rule, a target tracker.",
	settings = "Tabs, modules, and each module's switches.",
}

local function Changelog()
	local lines = {}
	for _, entry in ipairs(DT.CHANGELOG or {}) do
		lines[#lines + 1] = ("|cffffd100%s|r  |cff888888%s|r"):format(entry[1], entry[2])
		for _, text in ipairs(entry[3]) do lines[#lines + 1] = "  - " .. text end
		lines[#lines + 1] = ""
	end
	return lines
end
H.Changelog = Changelog

local function DrawLog()
	-- as many rows as there is room for now (the panel's height is not known when it is built)
	local fit = math.max(4, math.floor((panel:GetHeight() - 128 - 22 - 18) / LINE_H))
	for i = #log.rows + 1, fit do
		local row = log:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row:SetPoint("TOPLEFT", 0, -22 - (i - 1) * LINE_H)
		row:SetPoint("RIGHT", 0, 0)
		row:SetJustifyH("LEFT")
		row:SetWordWrap(false)
		log.rows[i] = row
	end
	logOffset = math.max(0, math.min(logOffset, #logLines - fit))
	for i, row in ipairs(log.rows) do row:SetText(i <= fit and logLines[i + logOffset] or "") end
	log.more:SetText(#logLines > fit and ("|cff888888mouse wheel: %d above, %d below|r"):format(logOffset, math.max(0, #logLines - fit - logOffset)) or "")
end

local function Refresh()
	if not panel then return end
	-- the tabs there are now, in the order they stand in
	local tabs = DT.UI:TabList()
	tabs[#tabs + 1] = { id = "settings", title = "Settings" }
	local n = 0
	for _, tab in ipairs(tabs) do
		if tab.id ~= "home" then
			n = n + 1
			local b = guide[n]
			if not b then
				b = CreateFrame("Button", nil, panel)
				b:SetHeight(18)
				b:SetPoint("TOPLEFT", 4, -150 - (n - 1) * 20)
				b:SetPoint("RIGHT", panel, "CENTER", -10, 0)
				local glow = b:CreateTexture(nil, "HIGHLIGHT")
				glow:SetAllPoints()
				glow:SetColorTexture(1, 1, 1, 0.08)
				b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				b.label:SetPoint("LEFT", 4, 0)
				b.label:SetPoint("RIGHT", -4, 0)
				b.label:SetJustifyH("LEFT")
				b.label:SetWordWrap(false)
				b:SetScript("OnClick", function(self) DT.UI:Show(self.tab) end)
				guide[n] = b
			end
			local subs = {}
			for i, sub in ipairs(tab.subs or {}) do subs[i] = sub.title end
			b.tab = tab.id
			b.label:SetText(("|cffffd100%s|r%s  |cffaaaaaa%s|r"):format(tab.title, subs[1] and (" |cff888888(" .. table.concat(subs, ", ") .. ")|r") or "",
				ABOUT[tab.id] or ""))
			b:Show()
		end
	end
	for i = n + 1, #guide do guide[i]:Hide() end
	logLines = Changelog()
	DrawLog()
end
H.Refresh = Refresh

local function Build(parent)
	panel = parent
	local logo = panel:CreateTexture(nil, "ARTWORK")
	logo:SetSize(56, 56)
	logo:SetPoint("TOPLEFT", 8, -8)
	logo:SetTexture(DT.LOGO)
	local function Text(font, x, y, text)
		local fs = panel:CreateFontString(nil, "OVERLAY", font)
		fs:SetPoint("TOPLEFT", x, y)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
		return fs
	end
	H.title = Text("GameFontNormalLarge", 76, -10, "DawnTools  |cff888888" .. (DT.VERSION or "") .. "|r")
	H.forWhom = Text("GameFontHighlight", 76, -34, "Built for |cffffd100Running Dawn|r")
	H.byWhom = Text("GameFontHighlight", 76, -52, "Built by |cffffd100Forgehaven|r")
	Text("GameFontHighlightSmall", 8, -84, "|cff888888Prices, inventories and the rest stay on your own machine, except what you agreed to share with the guild\n"
		.. "(auction prices, and which food you can cook). /dt opens this window; the minimap button too.|r")
	Text("GameFontNormal", 8, -128, "Where things are")

	-- what changed, on the right, moved by the mouse wheel
	log = CreateFrame("Frame", nil, panel)
	log:SetPoint("TOPLEFT", panel, "TOP", 10, -128)
	log:SetPoint("BOTTOMRIGHT", -4, 4)
	local head = log:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	head:SetPoint("TOPLEFT", 0, 0)
	head:SetText("What changed")
	log.rows = {}
	log.more = log:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	log.more:SetPoint("BOTTOMLEFT", 0, 0)
	log:EnableMouseWheel(true)
	log:SetScript("OnMouseWheel", function(_, delta)
		logOffset = logOffset - delta * 3
		DrawLog()
	end)
	H.log, H.guide = log, guide
	panel:SetScript("OnSizeChanged", function() DrawLog() end)
end

DT:RegisterModule("home", {
	title = "Home",
	version = 1,
	slash = "/dthome",
	-- icon: the button on the bar shows this instead of the title (see UI:Layout). A house where the game has
	-- one among its map signs, else the hearthstone.
	tab = { id = "home", title = "Home", defaultOrder = 1, create = Build, onShow = Refresh,
		icon = { atlas = "poi-town", texture = "Interface\\Icons\\INV_Misc_Rune_01" } },
})
