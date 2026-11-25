-- DawnInventory
-- What each of my characters has in its bags and bank, in one searchable list. It stays on this machine:
-- the module has no hello and no messages, so nothing of it ever reaches the guild.

local _, DT = ...
local I = {}
DT.Inventory = I

-- db: chars[guid] = { name, class, bags = { [itemID] = qty }, bank = { [itemID] = qty }, bankT = when the bank was read }
--     names[itemID] = name (from the item's link, so the search needs no item cache)
-- Characters are keyed by GUID. On Forever a character is "First Surname": UnitName gives the first name alone,
-- UnitFullName the surname as its second value (where other clients give the realm).

local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local BAGS, BANK = {}, { BANK_CONTAINER or -1, REAGENTBANK_CONTAINER or -3 }
for bag = 0, LAST_BAG do BAGS[#BAGS + 1] = bag end
-- ponytail: the bank as its bags are numbered after the carried ones. A client with the newer bank tabs under
-- other numbers needs them added here.
for bag = LAST_BAG + 1, LAST_BAG + (NUM_BANKBAGSLOTS or 7) do BANK[#BANK + 1] = bag end

local dirty = true

local function Count(bags)
	local out, slots = {}, 0
	for _, bag in ipairs(bags) do
		slots = slots + (C_Container.GetContainerNumSlots(bag) or 0)
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1)
				local name = info.hyperlink and info.hyperlink:match("%[(.-)%]")
				if name then I.db.names[info.itemID] = name end
			end
		end
	end
	return out, slots
end

local bankOpen
local function Scan()
	local me = I.db.chars[I.me]
	me.bags = Count(BAGS)
	-- the bank can only be read while it is open
	if bankOpen then
		-- (no slot of the bank answered: its bags go by other numbers here; what was known is kept, not emptied)
		local bank, slots = Count(BANK)
		if slots > 0 then me.bank, me.bankT = bank, DT.Now() end
	end
	dirty = true
end

-- For the other tabs. Units of an item in a character's bags, and in its bank as last seen
-- (guid as UnitGUID gives it; left out = the character logged in).
DawnInventory = { API = {
	Count = function(itemID, guid)
		local c = I.db and I.db.chars[guid or I.me]
		if not c then return 0, 0 end
		return c.bags[itemID] or 0, c.bank[itemID] or 0
	end,
} }

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local ROW_H, TOP_H = 18, 28
local panel, search, countText, bar, showButton, menu
local rows, list, offset = {}, {}, 0
local Refresh

-- Item, then this selection's bags / bank / total, the total over every character, and who holds it
local COLS = {
	{ key = "name", title = "Item", x = 4, width = 250 },
	{ key = "bags", title = "Bags", x = 258, width = 50, right = true },
	{ key = "bank", title = "Bank", x = 312, width = 50, right = true },
	{ key = "total", title = "Total", x = 366, width = 50, right = true },
	{ key = "all", title = "All chars", x = 420, width = 62, right = true, tip = "On all your characters together, bags and banks." },
	{ key = "who", title = "Held by", x = 494 }, -- (to the right edge)
}

-- class icon, then the name in the class colour
local function Label(guid)
	local c = I.db.chars[guid]
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class] and RAID_CLASS_COLORS[c.class].colorStr or "ffffffff"
	local t = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class]
	local icon = t and ("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:14:14:0:0:256:256:%d:%d:%d:%d|t "):format(
		math.floor(t[1] * 256), math.floor(t[2] * 256), math.floor(t[3] * 256), math.floor(t[4] * 256)) or ""
	return icon .. "|c" .. color .. (c.name or "?") .. "|r"
end

local function Guids()
	local guids = {}
	for guid in pairs(I.db.chars) do guids[#guids + 1] = guid end
	table.sort(guids, function(a, b) return (a == I.me and "" or a) < (b == I.me and "" or b) end) -- this character first
	return guids
end

-- For the other tabs (Market): units of an item over all my characters, and who holds them:
-- total, { "Name: 3 in bags, 5 in bank", ... } (this character first)
function DawnInventory.API.Held(itemID)
	local total, who = 0, {}
	for _, guid in ipairs(I.db and Guids() or {}) do
		local c = I.db.chars[guid]
		local bags, bank = c.bags[itemID] or 0, c.bank[itemID] or 0
		if bags + bank > 0 then
			total = total + bags + bank
			who[#who + 1] = Label(guid) .. ": " .. (bags > 0 and (bags .. " in bags") or "") .. (bags > 0 and bank > 0 and ", " or "")
				.. (bank > 0 and (bank .. " in bank") or "")
		end
	end
	return total, who
end

-- Whose things are listed: one character (this one, until another is picked) or "all".
local function Shown()
	local show = I.show or I.me
	return (show == "all" or I.db.chars[show]) and show or I.me
end

function I.Pick(show)
	I.show, offset = show, 0
	if menu then menu:Hide() end
	Refresh()
end

-- A character that was deleted (or is of no interest): its bags and bank are forgotten. Not this one: it
-- would be back at the next look into the bags.
function I.Forget(guid)
	if guid == I.me or not I.db.chars[guid] then return end
	I.db.chars[guid] = nil
	if I.show == guid then I.show = nil end
	if menu then menu:Hide() end
	Refresh()
end

-- Every item is counted over all characters (the "All chars" column, and who holds it); listed are those the
-- selection has.
local function Rebuild()
	local text, byId, unseen = (search:GetText() or ""):lower(), {}, {}
	local show = Shown()
	for _, guid in ipairs(Guids()) do
		local c = I.db.chars[guid]
		local counted = show == "all" or guid == show
		if counted and not c.bankT then unseen[#unseen + 1] = Label(guid) end
		local has = {} -- [itemID] = this character's units, bags and bank
		for _, place in ipairs({ "bags", "bank" }) do
			for id, qty in pairs(c[place]) do
				local e = byId[id]
				if not e then
					e = { id = id, bags = 0, bank = 0, all = 0, who = {} }
					byId[id] = e
				end
				e.all = e.all + qty
				if counted then e[place], e.listed = e[place] + qty, true end
				has[id] = (has[id] or 0) + qty
			end
		end
		for id, qty in pairs(has) do
			local who = byId[id].who
			who[#who + 1] = Label(guid) .. " " .. qty
		end
	end
	list = {}
	for id, e in pairs(byId) do
		if e.listed then
			e.name = I.db.names[id] or C_Item.GetItemInfo(id) or ("item " .. id)
			if text == "" or e.name:lower():find(text, 1, true) then list[#list + 1] = e end
		end
	end
	table.sort(list, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	return unseen
end

local function Place(fs, col)
	fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
	fs:SetWordWrap(false)
	fs:SetPoint("LEFT", col.x, 0)
	if col.width then fs:SetWidth(col.width) else fs:SetPoint("RIGHT", 0, 0) end
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row.invRow = true
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -TOP_H - ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -12, 0)
	local shade = row:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
	row.cols = {}
	for _, col in ipairs(COLS) do
		row.cols[col.key] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		Place(row.cols[col.key], col)
	end
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. self.id)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self, button) if self.id then DT:ItemClick(self.id, nil, button) end end)
	rows[i] = row
	return row
end

local function Number(n)
	return n > 0 and tostring(n) or "|cff555555-|r"
end

function Refresh()
	if not panel then return end
	dirty = false
	local unseen = Rebuild()
	local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H - ROW_H) / ROW_H))
	local max = math.max(0, #list - fit)
	offset = math.max(0, math.min(offset, max))
	bar:SetMinMaxValues(0, max)
	bar:SetValue(offset)
	bar:SetShown(max > 0)
	bar.thumb:SetSize(8, math.max(16, fit * ROW_H * fit / math.max(fit, #list)))
	for i = 1, math.max(fit, #rows) do
		local e = i <= fit and list[offset + i]
		local row = rows[i] or (e and MakeRow(i))
		if row then row:SetShown(e and true or false) end
		if e then
			local _, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(e.id)
			local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
			local cells = row.cols
			row.id = e.id
			cells.name:SetText((icon and ("|T%s:14|t "):format(icon) or "") .. color .. e.name .. "|r")
			cells.bags:SetText(Number(e.bags))
			cells.bank:SetText(Number(e.bank))
			cells.total:SetText(tostring(e.bags + e.bank))
			-- gold where other characters hold some too
			cells.all:SetText((e.all > e.bags + e.bank and "|cffffd100" or "") .. e.all)
			cells.who:SetText(table.concat(e.who, ", "))
		end
	end
	showButton.label:SetText(Shown() == "all" and "All characters" or Label(Shown()))
	countText:SetText(("%d items"):format(#list)
		.. (#unseen > 0 and ("  |cff888888Bank not seen yet on: " .. table.concat(unseen, ", ") .. " (open it once)|r") or ""))
end
I.Refresh = Refresh

-- The list under the button: this character, all of them, each of the others; an x forgets one of the others.
local MENU_H = 20
local function OpenMenu()
	if menu:IsShown() then return menu:Hide() end
	local entries = { { show = I.me, text = Label(I.me) }, { show = "all", text = "All characters" } }
	for _, guid in ipairs(Guids()) do
		if guid ~= I.me then entries[#entries + 1] = { show = guid, text = Label(guid), forget = true } end
	end
	for i = 1, math.max(#entries, #menu.entries) do
		local e, b = entries[i], menu.entries[i]
		if e and not b then
			b = CreateFrame("Button", nil, menu)
			b:SetHeight(MENU_H)
			b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * MENU_H)
			b:SetPoint("RIGHT", -2, 0)
			local highlight = b:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.12)
			b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.label:SetPoint("LEFT", 6, 0)
			b:SetScript("OnClick", function(self) I.Pick(self.show) end)
			b.forget = CreateFrame("Button", nil, b)
			b.forget:SetSize(MENU_H, MENU_H)
			b.forget:SetPoint("RIGHT", 0, 0)
			b.forget.label = b.forget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.forget.label:SetPoint("CENTER")
			b.forget.label:SetText("|cffff6060x|r")
			b.forget:SetScript("OnClick", function()
				local guid = b.show
				local c = I.db.chars[guid]
				if not c then return end
				menu:Hide()
				StaticPopup_Show("DAWNTOOLS_INV_FORGET", c.name or "?", nil, guid)
			end)
			b.forget:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine("Forget this character")
				GameTooltip:AddLine("For one that was deleted: its bags and bank leave the list. Logging in on it brings it back.", 1, 1, 1, true)
				GameTooltip:Show()
			end)
			b.forget:SetScript("OnLeave", function() GameTooltip:Hide() end)
			menu.entries[i] = b
		end
		if b then
			b:SetShown(e ~= nil)
			if e then
				b.show = e.show
				b.label:SetText((e.show == Shown() and "|cffffd100> |r" or "   ") .. e.text)
				b.forget:SetShown(e.forget or false)
			end
		end
	end
	menu:SetHeight(#entries * MENU_H + 4)
	menu:Show()
end

local function Build(parent)
	panel = parent
	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(240, 20)
	search:SetPoint("TOPLEFT", 8, -3)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function() -- (hooked: the template's own handler shows the "Search" hint)
		offset, dirty = 0, true
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	showButton = CreateFrame("Button", nil, panel)
	showButton:SetSize(190, 20)
	showButton:SetPoint("LEFT", search, "RIGHT", 10, 0)
	local shade = showButton:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, 0.08)
	showButton.label = showButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	showButton.label:SetPoint("LEFT", 6, 0)
	local arrow = showButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrow:SetPoint("RIGHT", -6, 0)
	arrow:SetText("|cffffd100v|r")
	showButton:SetScript("OnClick", OpenMenu)
	I.showButton = showButton
	menu = CreateFrame("Frame", nil, panel)
	menu:SetFrameStrata("DIALOG")
	menu:SetPoint("TOPLEFT", showButton, "BOTTOMLEFT", 0, -1)
	menu:SetWidth(190)
	menu:EnableMouse(true)
	local back = menu:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.06, 0.06, 0.06, 0.97)
	menu.entries = {}
	menu:Hide()
	I.menu = menu
	StaticPopupDialogs.DAWNTOOLS_INV_FORGET = {
		text = "Forget what %s has in bags and bank?\n\nFor a character that was deleted. Logging in on it brings it back.",
		button1 = YES or "Yes", button2 = NO or "No",
		OnAccept = function(_, guid) I.Forget(guid) end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", showButton, "RIGHT", 12, 0)
	countText:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
	countText:SetJustifyH("LEFT")
	countText:SetWordWrap(false)

	local head = CreateFrame("Frame", nil, panel)
	head:SetHeight(ROW_H)
	head:SetPoint("TOPLEFT", 0, -TOP_H)
	head:SetPoint("RIGHT", -12, 0)
	for _, col in ipairs(COLS) do
		local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		Place(fs, col)
		fs:SetText(col.title)
	end

	bar = CreateFrame("Slider", nil, panel)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(8)
	bar:SetPoint("TOPRIGHT", -1, -TOP_H - ROW_H)
	bar:SetPoint("BOTTOMRIGHT", -1, 2)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.3)
	bar.thumb = bar:CreateTexture(nil, "OVERLAY")
	bar.thumb:SetColorTexture(0.78, 0.68, 0.37, 0.9)
	bar:SetThumbTexture(bar.thumb)
	bar:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value + 0.5)
		if value == offset then return end -- (Refresh sets the bar too)
		offset = value
		Refresh()
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Refresh()
	end)
	panel:SetScript("OnSizeChanged", Refresh)
	local nextUpdate = 0
	DT.OnUpdate(panel, "tab: Inventory", function()
		if GetTime() < nextUpdate then return end
		nextUpdate = GetTime() + 0.2
		if dirty then Refresh() end
	end)
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

DT:RegisterModule("inventory", {
	title = "Inventory",
	version = 1,
	slash = "/dtinv",
	tab = { id = "inventory", title = "Inventory", defaultOrder = 30, create = Build, onShow = Refresh },
	onEnable = function(mod)
		I.db, I.me = mod.db, UnitGUID("player")
		I.db.chars, I.db.names = I.db.chars or {}, I.db.names or {}
		local me = I.db.chars[I.me] or { bags = {}, bank = {} }
		I.db.chars[I.me] = me
		local first, surname = UnitName("player"), nil
		if UnitFullName then first, surname = UnitFullName("player") end
		me.name = (first or "?") .. (surname and surname ~= "" and (" " .. surname) or "")
		me.class = select(2, UnitClass("player"))
		DT:On("BAG_UPDATE_DELAYED", Scan)
		DT:On("PLAYERBANKSLOTS_CHANGED", Scan)
		DT:On("PLAYERREAGENTBANKSLOTS_CHANGED", Scan)
		DT:On("BANKFRAME_OPENED", function()
			bankOpen = true
			Scan()
		end)
		DT:On("BANKFRAME_CLOSED", function() bankOpen = false end)
	end,
	selfTest = function(_, Try)
		Try("inventory list", Refresh)
		Try("inventory api", function() assert(type(DawnInventory.API.Count(1)) == "number") end)
	end,
})
