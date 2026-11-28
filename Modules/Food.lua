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
	return DT:Shares()
end

local function Short(sender)
	return DT.Name(sender)
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
-- A food that names none of them: what its tooltip says is gained ("gain 5 Swiftness for 10 min": Swiftness), else
-- "Special" where the use is not about health at all (a transformation, a breath of fire).
local GIVES = { "Fishing", "Stamina", "Spirit", "Strength", "Agility", "Intellect", "Attack Power", "Spell", "Mana",
	"Critical", "Hit", "Haste", "Defense", "Armor", "Dodge", "Resistance", "Healing", "Energy", "energy" }
local SHOWN = { Spell = "Spell power", Fishing = "Fishing skill", Critical = "Crit", Healing = "Healing Power", energy = "Energy" }
local TYPES = 5 -- (how foods are told apart: raise it with GIVES, and every food is read anew)

local function Type(id)
	local db = Food.db
	if db.types[id] then return db.types[id] end
	local fallback = db.foods[id] and db.foods[id].cat or "Other"
	local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
	if not (data and data.lines) then return fallback end
	local parts = {}
	for i, line in ipairs(data.lines) do parts[#parts + 1] = i > 1 and line.leftText or "" end -- (not the name: "Hit..." would decide)
	local text = table.concat(parts, " ")
	if not text:find("Use:", 1, true) then return fallback end -- (not loaded yet, or nothing to eat)
	local gives = (text:find("camp feature", 1, true) or text:find("Use: Places", 1, true)) and "Camp" or nil -- (a campfire, an oven: cooked, not eaten)
	for _, word in ipairs(gives and {} or GIVES) do
		if text:find(word, 1, true) then
			gives = SHOWN[word] or word
			break
		end
	end
	if not gives then
		local gain = (text:match("gain (.-) for %d") or text:match("increase your (.-) by %d") or ""):gsub(" while .*", ""):gsub("[%d%%%.%+]+", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
		if gain ~= "" then
			gives = (gain:sub(1, 1):upper() .. gain:sub(2)):sub(1, 20)
		else
			gives = text:lower():find("heal", 1, true) and "Health only" or "Special"
		end
	end
	db.types[id] = gives
	-- ponytail: the tooltip of a food that fell through is kept in the saved file, to see what Forever words differently; drop once the groups are right
	if gives == "Health only" or gives == "Special" then db.plain[id] = text:sub(1, 400) end
	return gives
end
Food.Type = Type

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local ROW_H, SIDE_W, TOP_H, SIDE_H = 18, 150, 28, 20
-- (a column of width 0 takes what is left; those of a width below 0 sit at the right edge, that wide, side by side)
local RECIPE_W, WHERE_W, PROFIT_W, VENDOR_W = 170, 250, 92, 104
-- "Cooking skill": the band of its recipe (DT.CraftSkill): learned at, yellow, green, grey; blank where none is known
-- "Profit (AH)" / "Profit (vendor)": what one cooking earns at today's prices, sold on the auction house or to a
-- vendor (DT.Craft.Profit); hover the row for how it is made up
local COLS = { { "Food", 168 }, { "Level", 52, true }, { "Cooking skill", 120 }, { "Gives", 84 }, { "This character", 84 }, { "Who can cook it", 0 },
	{ "Recipe", -RECIPE_W }, { "Where to get it", -WHERE_W }, { "Profit (AH)", -PROFIT_W, true }, { "Profit (vendor)", -VENDOR_W, true } }
-- how far from the right edge a column of the right-hand group ends (the last: 0), and how wide that group is
local function RightOf(c)
	local w = 0
	for i = c + 1, #COLS do
		if COLS[i][2] < 0 then w = w - COLS[i][2] end
	end
	return w
end
local RIGHT_W = RightOf(0)

-- Where a recipe item comes from: a vendor (of my side, where there is one), else a mob that drops it, else a
-- quest. { kind = "buy" / "drop" / "quest", npc = id, name =, text = "Name  Zone", more = how many others,
-- quest = id, lines = every source, as the Items tab lists them }; nil for none known (or no QuestieDB).
-- Read through the Items tab's own listing of an item's sources; kept for the session.
-- ponytail: the first vendor of my side as QuestieDB lists them, not the nearest; a drop names one mob of
-- several and no chance (none is known here). The Items tab has them all: Shift-click the cell.
local sources = {}
local function Friendly(npc)
	local ok, to = pcall(function() return DT.DB.Q("npc", npc, "friendlyToFaction") end)
	if not ok or type(to) ~= "string" then return true end
	local mine = UnitFactionGroup and UnitFactionGroup("player")
	return to == "AH" or type(mine) ~= "string" or to == mine:sub(1, 1)
end

function Food.Source(scroll)
	if sources[scroll] ~= nil then return sources[scroll] or nil end
	local I = DT.Item
	if not (I and I.Sources and DT.DB.Lib()) then return nil end
	local ok, lines = pcall(I.Sources, { id = scroll, src = {} })
	if not ok then return nil end
	local by, head = {}, nil
	for _, line in ipairs(lines) do
		if line.head then
			head = line.head:match("^(.-) %(%d+%)$") or line.head
			by[head] = { n = tonumber(line.head:match("%((%d+)%)$")) or 0 }
		elseif head and (line.npc or line.quest) then
			table.insert(by[head], line)
		end
	end
	local found
	local function Pick(kind, list, friendly)
		if found or not (list and list[1]) then return end
		local line = list[1]
		for _, l in ipairs(friendly and list or {}) do
			if Friendly(l.npc) then line = l break end
		end
		found = { kind = kind, npc = line.npc, quest = line.quest, name = line.name or line.text, text = line.text, more = math.max(0, list.n - 1),
			foe = friendly and not Friendly(line.npc) or nil, lines = lines }
	end
	Pick("buy", by["Sold by"], true)
	Pick("drop", by["Dropped by"])
	Pick("quest", by["Reward of the quest"])
	sources[scroll] = found or false
	return found
end

-- the Items tab's own window on an item: everywhere it comes from, each a click for a waypoint
function Food.OpenItem(id, name)
	local I = DT.Item
	if not (id and I and I.ShowInfo) then return end
	local ok = pcall(I.ShowInfo, { id = id, name = name or ("item " .. id), nameL = (name or ""):lower(), req = 0, ilvl = 0, c = 9, s = 0, src = {} })
	if not ok then DT:Print("Could not open that item's sources.") end
end

-- The frame over a row's "Where to get it" cell (the row's data has .src, .scroll, .scrollName): every source
-- on hover; a click sets a waypoint to the vendor or mob (a quest: its chain); Shift-click opens the recipe's
-- sources. `right`: how far from the row's right edge the cell ends. Used by the profession tabs too.
function Food.WhereFrame(row, width, right)
	local where = CreateFrame("Frame", nil, row)
	where:SetPoint("TOPRIGHT", -(right or 0), 0)
	where:SetPoint("BOTTOMRIGHT", -(right or 0), 0)
	where:SetWidth(width)
	where:EnableMouse(true)
	where:SetScript("OnEnter", function(self)
		local d = row.data
		if not (d and d.src) then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(d.scrollName or "Recipe")
		for _, line in ipairs(d.src.lines) do
			if line.head then GameTooltip:AddLine(line.head, 1, 0.82, 0) else GameTooltip:AddLine("  " .. line.text, 1, 1, 1) end
		end
		GameTooltip:AddLine(d.src.quest and "Click: the quest's chain." or "Click: a waypoint to " .. (d.src.name or "it") .. ".", 0.5, 0.8, 1)
		GameTooltip:AddLine("Shift-click: the recipe on the Items tab.", 0.5, 0.8, 1)
		GameTooltip:Show()
	end)
	where:SetScript("OnLeave", function() GameTooltip:Hide() end)
	where:SetScript("OnMouseUp", function()
		local d = row.data
		if not (d and d.src) then return end
		if IsShiftKeyDown and IsShiftKeyDown() then return Food.OpenItem(d.scroll, d.scrollName) end
		if d.src.quest then
			local quest = DT.Quest and DT.Quest.Entry and DT.Quest.Entry(d.src.quest)
			if quest then DT.Quest.ShowChain(quest) else DT:Print("Open World, Quests once, then click again: the quests are not read yet.") end
		elseif d.src.npc then
			DT.Npc.Waypoint({ id = d.src.npc, name = d.src.name, zone = 0 })
		end
	end)
	return where
end

local KIND = { buy = "|cffffd100Buy|r", drop = "|cffff8040Drop|r", quest = "|cff66aaffQuest|r" }
-- the cell's words: "Buy 4s  Kira Cook  Booty Bay (+2)"
local function WhereText(scroll, src)
	if not src then return "" end
	local price = ""
	if src.kind == "buy" then
		local copper, _, _, limited = nil, nil, nil, nil
		if DawnMarket and DawnMarket.API.GetVendor then copper, _, _, limited = DawnMarket.API.GetVendor(scroll) end
		copper = copper or (DT.VendorPrice and DT.VendorPrice[scroll])
		price = " " .. (copper and DT.Money(copper) or "|cff888888price ?|r") .. (limited and " |cff888888(limited)|r" or "")
	end
	return KIND[src.kind] .. price .. "  " .. src.text .. (src.foe and " |cffff4040(other side)|r" or "") .. (src.more > 0 and (" |cff888888(+%d)|r"):format(src.more) or "")
end
Food.WhereText = WhereText
local panel, side, search, countText, bar
local rows, heads, sideButtons, list, offset = {}, {}, {}, {}, 0
local picked -- the type picked on the left (nil = all)
local filter = {} -- the boxes ticked beside the search box (DT.Craft.FILTERS): known, missing, profit, mats
Food.filter = filter
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

-- (an item the game has not loaded yet: the list is drawn again when its name comes)
local awaited = {}
local function Rebuild()
	local q, me, counts = (search:GetText() or ""):lower(), Me(), {}
	list = {}
	for id in pairs(Food.db.foods) do
		local name, _, quality, _, level, _, _, _, _, icon = C_Item.GetItemInfo(id)
		if not name then awaited[id] = true end
		local kind, known = Type(id), me.ids[id] or false
		-- (what Cooking makes for the camp, the campfires and the like, is listed on the Campsite tab, not here)
		local camp = DT.Craft and DT.Craft.IsCampItem and DT.Craft.IsCampItem(id)
		-- (a character whose Cooking window was never read, or who has no Cooking, knows none: all are missing)
		-- what cooking one earns (the profession tabs' sum: Modules/Craft.lua), and whether it passes the boxes ticked
		local C = DT.Craft
		local profit = C and C.Profit and C.Profit(C.ByItem(id)) or nil
		if not camp and (not C or C.Passes(filter, known, profit, C.Have(profit))) and (q == "" or (name or ""):lower():find(q, 1, true)) then
			counts[kind] = (counts[kind] or 0) + 1
			if not picked or picked == kind then
				local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
				local cooks = Cooks(id)
				local band, b = DT.CraftBand(id), DT.CraftSkill and DT.CraftSkill[id]
				local skill = b and (b[2] > 0 and b[2] or b[3]) -- (sorted by where it is learned; not known: by where it turns yellow)
				-- the recipe item that teaches it; none: a trainer does
				local scroll = b and b[6] and b[6] > 0 and b[6] or nil
				local sName, _, sQuality = nil, nil, nil
				if scroll then
					sName, _, sQuality = C_Item.GetItemInfo(scroll)
					if not sName then awaited[scroll] = true end
				end
				local sColor = sQuality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[sQuality] and ITEM_QUALITY_COLORS[sQuality].hex or "|cffffffff"
				local recipe = scroll and (sColor .. (sName or ("item " .. scroll)) .. "|r") or b and "|cff888888trainer|r" or ""
				-- where to get the recipe: a vendor, a mob, a quest; a recipe without an item is taught by a trainer
				local src = scroll and Food.Source(scroll) or nil
				local where = scroll and WhereText(scroll, src) or b and "|cff888888Cooking trainer|r" or ""
				list[#list + 1] = { id = id, name = name or ("item " .. id), level = level or 0, cooks = cooks, scroll = scroll, scrollName = sName, src = src, profit = profit,
					(icon and ("|T%s:14|t "):format(icon) or "") .. color .. (name or ("item " .. id)) .. "|r",
					level and level > 1 and tostring(level) or "", band and ("  " .. band) or "", kind,
					not me.t and "|cff888888?|r" or known and "|cff40ff40known|r" or "|cffff4040missing|r",
					cooks[1] and table.concat(cooks, ", ") or "|cff888888nobody known|r", recipe, where, profit and C.ProfitText(profit) or "", profit and C.ProfitText(profit, true) or "",
					-- what each column sorts by ("who can cook it": by how many can; "where": by kind, then name)
					sort = { name or ("item " .. id), level or 0, skill or 0, kind, not me.t and 1 or known and 2 or 0, #cooks, scroll and (sName or "") or b and "~" or "~~",
						src and (src.kind .. " " .. (src.name or "")) or b and not scroll and "trainer" or "~~",
						profit and profit.profit or -math.huge, profit and profit.vendorProfit or -math.huge } }
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
		if col[2] > 0 then
			fs:SetWidth(col[2] - 6)
		elseif col[2] == 0 then
			fs:SetPoint("RIGHT", -RIGHT_W - 6, 0)
		else
			fs:ClearAllPoints()
			fs:SetPoint("RIGHT", -RightOf(c) - 6, 0)
			fs:SetWidth(-col[2] - 6)
		end
		fs:SetJustifyH(col[3] and "RIGHT" or "LEFT")
		fs:SetWordWrap(false)
		row.fcols[c] = fs
		x = x + math.max(0, col[2])
	end
	row.where = Food.WhereFrame(row, WHERE_W, PROFIT_W + VENDOR_W)
	-- over the Recipe column: the recipe's own tooltip and link, not the food's
	row.over = CreateFrame("Frame", nil, row)
	row.over:SetPoint("TOPRIGHT", -WHERE_W - PROFIT_W - VENDOR_W, 0)
	row.over:SetPoint("BOTTOMRIGHT", -WHERE_W - PROFIT_W - VENDOR_W, 0)
	row.over:SetWidth(RECIPE_W)
	row.over:EnableMouse(true)
	row.over:SetScript("OnEnter", function(self)
		local d = row.data
		if not (d and d.scroll) then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetHyperlink("item:" .. d.scroll)
		GameTooltip:AddLine("Click: a link to read up on it.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row.over:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.over:SetScript("OnMouseUp", function(_, button)
		local d = row.data
		if not (d and d.scroll) or DT:ItemClick(d.scroll, d.scrollName, button) then return end
		DT:ShowLink(d.scrollName or ("item " .. d.scroll), DT:ItemLink(d.scroll))
	end)
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. d.id)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(d.cooks[1] and ("Can cook it: " .. table.concat(d.cooks, ", ")) or "Nobody known who can cook it.", 1, 1, 1, true)
		if d.profit and DT.Craft then DT.Craft.ProfitTip(GameTooltip, d.profit) end
		GameTooltip:AddLine("Click: a link to read up on it.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self, button)
		if not self.data or DT:ItemClick(self.data.id, self.data.name, button) then return end
		DT:ShowLink(self.data.name, DT:ItemLink(self.data.id))
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
			row.over:SetShown(d and d.scroll and true or false) -- (no recipe item: the row's own hover, the food)
			row.where:SetShown(d and d.src and true or false)
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
	local me = Me()
	countText:SetText(not next(Food.db.foods) and "|cff888888Open your Cooking window once: the food list is read from it.|r"
		or not me.t and (filter.known and "|cff888888Nothing known on this character: it has no Cooking, or its Cooking window was never opened.|r"
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
	-- what to list: known, missing, profitable, what I have the materials for (the same boxes as the profession tabs)
	local last = search
	if DT.Craft and DT.Craft.Ticks then
		Food.ticks, last = DT.Craft.Ticks(panel, search, filter, function()
			offset = 0
			Refresh()
		end)
	end
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", last, "RIGHT", 12, 0)
	countText:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	countText:SetJustifyH("LEFT")
	countText:SetWordWrap(false)

	local x = SIDE_W + 8
	for c, col in ipairs(COLS) do
		-- click to sort, again to turn it round
		local h = CreateFrame("Button", nil, panel)
		if col[2] < 0 then h:SetPoint("TOPRIGHT", -12 - RightOf(c) - 6, -TOP_H) else h:SetPoint("TOPLEFT", x, -TOP_H) end
		h:SetSize(col[2] > 0 and col[2] - 6 or col[2] < 0 and -col[2] - 6 or 160, ROW_H)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetJustifyH(col[3] and "RIGHT" or "LEFT")
		h.text:SetWordWrap(false)
		h:SetScript("OnClick", function()
			if sortBy.col == c then
				sortBy.desc = not sortBy.desc
			else
				-- (names and levels from the start; "this character" and "who can cook it" from the most)
				sortBy.col, sortBy.desc = c, c == 5 or c == 6 or c == 9 or c == 10
			end
			Refresh()
		end)
		heads[c] = h
		x = x + math.max(0, col[2])
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
	DT.OnUpdate(panel, "tab: Cooking", function()
		if GetTime() < nextUpdate then return end
		nextUpdate = GetTime() + 0.5
		if dirty then Refresh() end
	end)
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

DT:RegisterModule("food", {
	title = "Cooking",
	version = 1,
	slash = "/dtfood",
	tab = { id = "food", title = "Cooking", defaultOrder = 50, under = "craft", create = Build, onShow = function() Refresh() end },
	onEnable = function(mod)
		local db = mod.db
		db.foods, db.mine, db.guild, db.types = db.foods or {}, db.mine or {}, db.guild or {}, db.types or {}
		db.plain = db.plain or {}
		if db.typesV ~= TYPES then db.types, db.plain, db.typesV = {}, {}, TYPES end
		Food.db, Food.me = db, UnitGUID("player")
		local me = db.mine[Food.me] or { ids = {} }
		db.mine[Food.me] = me
		local first, surname = UnitName("player"), nil
		if UnitFullName then first, surname = UnitFullName("player") end
		me.name = (first or "?") .. (surname and surname ~= "" and (" " .. surname) or "")

		-- (the window fires both events in bursts: one read, a second after the first)
		local pending
		local function Soon()
			if pending then return end
			pending = true
			C_Timer.After(1, function() pending = nil; ReadCooking() end)
		end
		DT:On("TRADE_SKILL_SHOW", Soon)
		DT:On("TRADE_SKILL_LIST_UPDATE", Soon)
		DT:On("GET_ITEM_INFO_RECEIVED", function(id)
			if awaited[id] then awaited[id], dirty = nil, true end
		end)
		DT:On("DT_MARKET_UPDATE", function() dirty = true end) -- (the profit columns)
		DT:On("DT_SETTINGS", function(name, key)
			if name == "food" and key == "share" then Send() end
		end)
		C_Timer.After(30, Send) -- once a session, for members who came to the addon since
	end,
	held = function()
		return ("what %d guild characters can cook"):format(Count(Food.db.guild))
	end,
	progress = function()
		-- every Cooking recipe there is (the shipped list), or the foods heard of where that is more
		local all, heard, have = 0, 0, 0
		for _, b in pairs(DT.CraftSkill or {}) do
			if b[1] == 185 then all = all + 1 end
		end
		for id in pairs(Food.db.foods) do
			heard = heard + 1
			local known = false
			for _, c in pairs(Food.db.mine) do known = known or c.ids[id] or false end
			for _, c in pairs(Food.db.guild) do known = known or c.ids[id] or false end
			if known then have = have + 1 end
		end
		return {
			{ "Cooking recipes heard of", heard, math.max(all, heard), "open the Cooking window: it lists them" },
			{ "Foods somebody can cook", have, math.max(all, heard), "you, your characters, or the guild" },
		}
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
