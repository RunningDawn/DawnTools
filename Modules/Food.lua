-- DawnFood
-- Every food there is to cook, by what it gives, with who in the guild can cook it and which recipes this
-- character still lacks.
--
-- Where it comes from:
--   the Cooking window: opening it records every recipe it lists, and which of them this character knows
--   the guild: members who agreed tell each other which food their characters can cook (settings.share;
--   asked once, when the tab is first opened; off until then). Nothing else is sent.

local _, DT = ...
local Food = {}
DT.Food = Food

-- db: foods[itemID] = { cat = the Cooking window's own heading for it }     every food heard of
--     mine[guid] = { name, t, ids = { [itemID] = true } }                   what my characters can cook
--     guild[name] = { t, from = sender, ids = { [itemID] = true } }         what guild members said they can
--     types[itemID] = "Stamina"                                             worked out from the tooltip
-- On the wire:  KNOWN  "<character>;<itemID>,<itemID>,..."     REQUEST  "<member>": that member, send yours
-- The HELLO summary is how many foods my character can cook.

local MAX_IDS = 1000 -- foods taken from one message
local dirty = true

local function On()
	return Food.db.settings.share == true
end

local function Short(sender)
	return Ambiguate and Ambiguate(sender, "guild") or sender
end

local function Count(set)
	local n = 0
	for _ in pairs(set or {}) do n = n + 1 end
	return n
end

local function Me()
	return Food.db.mine[Food.me]
end

---------------------------------------------------------------------------
-- The Cooking window
---------------------------------------------------------------------------

-- the item a recipe makes (the game may refuse to say for one that is not learned: then nothing)
local function OutputOf(T, recipe)
	local ok, id = pcall(function()
		local data = T.GetRecipeOutputItemData and T.GetRecipeOutputItemData(recipe)
		if data and data.itemID then return data.itemID end
		local s = T.GetRecipeSchematic(recipe, false)
		return s and s.outputItemID
	end)
	return ok and type(id) == "number" and id > 0 and id or nil
end

local function Send()
	local me = Me()
	if not (On() and me and next(me.ids)) then return end
	local ids = {}
	for id in pairs(me.ids) do ids[#ids + 1] = id end
	table.sort(ids)
	DT.Comms:Send("food", "KNOWN", me.name .. ";" .. table.concat(ids, ","), true)
end

local function ReadCooking()
	local T = C_TradeSkillUI
	if not (T and T.GetBaseProfessionInfo and T.GetAllRecipeIDs) then return end
	if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild()) then return end
	local base = T.GetBaseProfessionInfo()
	if not base or not (base.profession == 5 or base.professionName == (PROFESSIONS_COOKING or "Cooking")) then return end
	local me, ids = Me(), {}
	for _, recipe in ipairs(T.GetAllRecipeIDs() or {}) do
		local info = T.GetRecipeInfo(recipe)
		local id = info and OutputOf(T, recipe)
		if id then
			local cat = info.categoryID and T.GetCategoryInfo and T.GetCategoryInfo(info.categoryID)
			Food.db.foods[id] = Food.db.foods[id] or {}
			Food.db.foods[id].cat = cat and cat.name or Food.db.foods[id].cat
			if info.learned then ids[id] = true end
		end
	end
	local changed = Count(ids) ~= Count(me.ids)
	me.ids, me.t = ids, DT.Now()
	dirty = true
	if changed then Send() end
end

---------------------------------------------------------------------------
-- The guild
---------------------------------------------------------------------------

local replied = {} -- [requester] = GetTime() of my last answer

local function OnMessage(kind, payload, sender)
	if not On() then return end
	if kind == "KNOWN" then
		local name, list = payload:match("^([^;]+);([%d,]*)$")
		if not name or #name > 40 then return end
		for _, c in pairs(Food.db.mine) do
			if c.name == name then return end -- one of my own: I know better
		end
		local ids, n = {}, 0
		for id in list:gmatch("%d+") do
			if n >= MAX_IDS then break end
			id = tonumber(id)
			ids[id], n = true, n + 1
			Food.db.foods[id] = Food.db.foods[id] or {}
		end
		Food.db.guild[name] = { t = DT.Now(), from = Short(sender), ids = ids }
		dirty = true
	elseif kind == "REQUEST" then
		if payload ~= DT.Comms.self then return end
		if replied[sender] and GetTime() - replied[sender] < 60 then return end
		replied[sender] = GetTime()
		Send()
	end
end

-- a member whose count is not what I hold for them is asked for their list
-- ponytail: if all of an account's characters share one name on the wire, each login of another of them asks
-- again. One small message; the answer is limited to once a minute.
local asked = {}
local function OnHello(sender, summary)
	local theirs = tonumber(summary)
	if not On() or not theirs or asked[sender] == theirs then return end
	local who = Short(sender)
	for _, c in pairs(Food.db.guild) do
		if c.from == who and Count(c.ids) == theirs then return end
	end
	asked[sender] = theirs
	C_Timer.After(math.random() * 3, function() DT.Comms:Send("food", "REQUEST", sender) end)
end

---------------------------------------------------------------------------
-- What a food gives
---------------------------------------------------------------------------

-- the first of these its tooltip names; a food that names none only restores health
-- ponytail: reads the English tooltip. Another language, or a client without tooltip data, falls back to the
-- Cooking window's own heading.
local GIVES = { "Stamina", "Spirit", "Strength", "Agility", "Intellect", "Attack Power", "Spell", "Mana" }

local function Type(id)
	local db = Food.db
	if db.types[id] then return db.types[id] end
	local fallback = db.foods[id] and db.foods[id].cat or "Other"
	local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
	if not (data and data.lines) then return fallback end
	local parts = {}
	for _, line in ipairs(data.lines) do parts[#parts + 1] = line.leftText or "" end
	local text = table.concat(parts, " ")
	if not text:find("Use:", 1, true) then return fallback end -- (not loaded yet, or nothing to eat)
	local gives = "Health only"
	for _, word in ipairs(GIVES) do
		if text:find(word, 1, true) then
			gives = word == "Spell" and "Spell power" or word
			break
		end
	end
	db.types[id] = gives
	return gives
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local ROW_H, SIDE_W, TOP_H, SIDE_H = 18, 150, 28, 20
local COLS = { { "Food", 230 }, { "Level", 44, true }, { "Gives", 96 }, { "This character", 96 }, { "Who can cook it", 0 } }
local panel, side, search, countText, missingButton, bar
local rows, heads, sideButtons, list, offset = {}, {}, {}, {}, 0
local picked, hideMissing -- the type picked on the left (nil = all); whether recipes I lack are left out
local sortBy = { col = 2, desc = false } -- the column the table is sorted by, and which way

-- everyone who can cook it: this character first, then my others, then the guild
local function Cooks(id)
	local names = {}
	for guid, c in pairs(Food.db.mine) do
		if c.ids[id] and guid ~= Food.me then names[#names + 1] = "|cffffd100" .. c.name .. "|r" end
	end
	for name, c in pairs(Food.db.guild) do
		if c.ids[id] then names[#names + 1] = name end
	end
	table.sort(names)
	if Me().ids[id] then table.insert(names, 1, "|cff40ff40You|r") end
	return names
end

local function Rebuild()
	local q, me, counts = (search:GetText() or ""):lower(), Me(), {}
	list = {}
	for id in pairs(Food.db.foods) do
		local name, _, quality, _, level, _, _, _, _, icon = C_Item.GetItemInfo(id)
		local kind, known = Type(id), me.ids[id] or false
		-- (a character whose Cooking window was never read, or who has no Cooking, knows none: all are missing)
		if not (hideMissing and not known) and (q == "" or (name or ""):lower():find(q, 1, true)) then
			counts[kind] = (counts[kind] or 0) + 1
			if not picked or picked == kind then
				local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
				local cooks = Cooks(id)
				list[#list + 1] = { id = id, name = name or ("item " .. id), level = level or 0, cooks = cooks,
					(icon and ("|T%s:14|t "):format(icon) or "") .. color .. (name or ("item " .. id)) .. "|r",
					level and level > 1 and tostring(level) or "", kind,
					not me.t and "|cff888888?|r" or known and "|cff40ff40known|r" or "|cffff4040missing|r",
					cooks[1] and table.concat(cooks, ", ") or "|cff888888nobody known|r",
					-- what each column sorts by ("who can cook it": by how many can)
					sort = { name or ("item " .. id), level or 0, kind, not me.t and 1 or known and 2 or 0, #cooks } }
			end
		end
	end
	table.sort(list, function(a, b)
		local x, y = a.sort[sortBy.col], b.sort[sortBy.col]
		if x ~= y then
			if sortBy.desc then return x > y end
			return x < y
		end
		if a.level ~= b.level then return a.level < b.level end
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	local kinds, total = {}, 0
	for kind, n in pairs(counts) do
		kinds[#kinds + 1] = kind
		total = total + n
	end
	table.sort(kinds)
	local sections = { { label = ("All food (%d)"):format(total) } }
	for _, kind in ipairs(kinds) do sections[#sections + 1] = { label = ("%s (%d)"):format(kind, counts[kind]), kind = kind } end
	return sections
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", SIDE_W + 8, -TOP_H - ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -12, 0)
	row.fcols = {}
	local x = 0
	for c, col in ipairs(COLS) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", x, 0)
		if col[2] > 0 then fs:SetWidth(col[2] - 6) else fs:SetPoint("RIGHT", 0, 0) end
		fs:SetJustifyH(col[3] and "RIGHT" or "LEFT")
		fs:SetWordWrap(false)
		row.fcols[c] = fs
		x = x + col[2]
	end
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. d.id)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(d.cooks[1] and ("Can cook it: " .. table.concat(d.cooks, ", ")) or "Nobody known who can cook it.", 1, 1, 1, true)
		GameTooltip:AddLine("Click: a link to read up on it.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self)
		if self.data then DT:ShowLink(self.data.name, DT:ItemLink(self.data.id)) end
	end)
	rows[i] = row
	return row
end

local function SideButton(i)
	local b = CreateFrame("Button", nil, side)
	b:SetHeight(SIDE_H)
	b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * SIDE_H)
	b:SetPoint("RIGHT", -2, 0)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(1, 0.82, 0, 0.18)
	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", 6, 0)
	b.label:SetPoint("RIGHT", -4, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetWordWrap(false)
	b:SetScript("OnClick", function(self)
		if not self.section then return end
		picked, offset = self.section.kind, 0
		Food.Refresh()
	end)
	sideButtons[i] = b
	return b
end

local asking
local function Refresh()
	if not panel then return end
	dirty = false
	local sections = Rebuild()
	local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H - ROW_H) / ROW_H))
	local max = math.max(0, #list - fit)
	offset = math.max(0, math.min(offset, max))
	bar:SetMinMaxValues(0, max)
	bar:SetValue(offset)
	bar:SetShown(max > 0)
	bar.thumb:SetSize(8, math.max(16, fit * ROW_H * fit / math.max(fit, #list)))
	for i = 1, math.max(fit, #rows) do
		local d = i <= fit and list[offset + i]
		local row = rows[i] or (d and MakeRow(i))
		if row then
			row.data = d or nil
			row:SetShown(d and true or false)
			for c, cell in ipairs(row.fcols) do cell:SetText(d and d[c] or "") end
		end
	end
	for i = 1, math.max(#sections, #sideButtons) do
		local s = sections[i]
		local b = sideButtons[i] or (s and SideButton(i))
		if b then
			b.section = s
			b:SetShown(s ~= nil)
			if s then
				b.label:SetText(s.label)
				b.sel:SetShown(s.kind == picked)
			end
		end
	end
	for c, h in ipairs(heads) do
		h.text:SetText("|cffffd100" .. COLS[c][1] .. (sortBy.col == c and (sortBy.desc and " v" or " ^") or "") .. "|r")
	end
	missingButton:SetText(hideMissing and "Show missing" or "Hide missing")
	local me = Me()
	countText:SetText(not next(Food.db.foods) and "|cff888888Open your Cooking window once: the food list is read from it.|r"
		or not me.t and (hideMissing and "|cff888888Nothing known on this character: it has no Cooking, or its Cooking window was never opened.|r"
			or ("%d foods  |cff888888Open the Cooking window on this character to see what it lacks.|r"):format(#list))
		or ("%d foods, %d of them known to this character"):format(#list, Count(me.ids)))
end
Food.Refresh = Refresh

local function Build(parent)
	panel = parent
	side = CreateFrame("Frame", nil, panel)
	side:SetPoint("TOPLEFT", 0, -2)
	side:SetPoint("BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDE_W)
	local shade = side:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, 0.04)

	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("TOPLEFT", SIDE_W + 16, -3)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function() -- (hooked: the template's own handler shows the "Search" hint)
		offset, dirty = 0, true
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	-- recipes this character lacks: listed, or left out
	missingButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	missingButton:SetSize(110, 22)
	missingButton:SetPoint("TOPRIGHT", -2, -2)
	missingButton:SetScript("OnClick", function()
		hideMissing, offset = not hideMissing, 0
		Refresh()
	end)
	missingButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Lists, or leaves out, the food this character has no recipe for.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	missingButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", search, "RIGHT", 12, 0)
	countText:SetPoint("RIGHT", missingButton, "LEFT", -8, 0)
	countText:SetJustifyH("LEFT")
	countText:SetWordWrap(false)

	local x = SIDE_W + 8
	for c, col in ipairs(COLS) do
		-- click to sort, again to turn it round
		local h = CreateFrame("Button", nil, panel)
		h:SetPoint("TOPLEFT", x, -TOP_H)
		h:SetSize(col[2] > 0 and col[2] - 6 or 160, ROW_H)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetJustifyH(col[3] and "RIGHT" or "LEFT")
		h.text:SetWordWrap(false)
		h:SetScript("OnClick", function()
			if sortBy.col == c then
				sortBy.desc = not sortBy.desc
			else
				-- (names and levels from the start; "this character" and "who can cook it" from the most)
				sortBy.col, sortBy.desc = c, c >= 4
			end
			Refresh()
		end)
		heads[c] = h
		x = x + col[2]
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
	panel:SetScript("OnUpdate", function()
		if GetTime() < nextUpdate then return end
		nextUpdate = GetTime() + 0.5
		if dirty then Refresh() end
	end)
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

DT:RegisterModule("food", {
	title = "Food",
	version = 1,
	slash = "/dtfood",
	settings = {
		{ key = "share", label = "Tell the guild which food my characters can cook (and see theirs)" },
	},
	tab = {
		id = "food", title = "Food", defaultOrder = 50, under = "craft", create = Build,
		onShow = function()
			Refresh()
			-- asked once, the first time the tab is looked at
			if Food.db.settings.share == nil and IsInGuild() and not asking then
				asking = true
				StaticPopup_Show("DAWNTOOLS_FOOD_SHARE")
			end
		end,
	},
	onEnable = function(mod)
		local db = mod.db
		db.foods, db.mine, db.guild, db.types = db.foods or {}, db.mine or {}, db.guild or {}, db.types or {}
		Food.db, Food.me = db, UnitGUID("player")
		local me = db.mine[Food.me] or { ids = {} }
		db.mine[Food.me] = me
		local first, surname = UnitName("player"), nil
		if UnitFullName then first, surname = UnitFullName("player") end
		me.name = (first or "?") .. (surname and surname ~= "" and (" " .. surname) or "")

		StaticPopupDialogs.DAWNTOOLS_FOOD_SHARE = {
			text = "DawnTools Food: tell the guild which food your characters can cook?\n\n"
				.. "Sent to guild members who use DawnTools: each character's name and the food it has recipes for. "
				.. "In return you see who can cook what.\n\nNothing else is sent, and you can switch it off at any time: /dt settings.",
			button1 = "Share", button2 = "Not now",
			OnAccept = function()
				db.settings.share = true
				Send()
			end,
			-- (only a real no: a popup pushed aside by another one asks again next time)
			OnCancel = function(_, _, reason)
				if reason == "clicked" then db.settings.share = false end
				asking = false
			end,
			timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
		}
		DT:On("TRADE_SKILL_SHOW", function() C_Timer.After(1, ReadCooking) end)
		DT:On("TRADE_SKILL_LIST_UPDATE", function() C_Timer.After(1, ReadCooking) end)
		DT:On("DT_SETTINGS", function(name, key)
			if name == "food" and key == "share" then Send() end
		end)
		C_Timer.After(30, Send) -- once a session, for members who came to the addon since
	end,
	hello = function()
		return On() and tostring(Count(Me().ids)) or nil
	end,
	onHello = function(_, sender, summary) OnHello(sender, summary) end,
	onMessage = function(_, kind, payload, sender) OnMessage(kind, payload, sender) end,
	status = function()
		return On() and ("Sharing: %d guild characters have told what they cook."):format(Count(Food.db.guild))
			or "Not sharing: nobody is told what you cook, and nobody's list comes in."
	end,
	selfTest = function(_, Try)
		Try("food list", Refresh)
	end,
})
