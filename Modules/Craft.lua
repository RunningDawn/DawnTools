-- DawnTools :: Craft
-- A tab for each crafting profession under "Craft" (beside Fishing and Cooking, which are modules of their own):
-- every recipe there is (DT.Recipes: rows of the game database, Core/DBSeed.lua), its skill band, what its materials
-- cost and what it earns at today's prices, which of them this character knows, who can make it, and where the
-- recipe comes from.
--
-- Where it comes from:
--   the recipes, their materials and skill   the shipped list (no profession window need be opened to see them)
--   prices                                   the Market's (auction house, vendors) and the shipped vendor prices
--   what a character knows                   read when a profession's window is opened
--   the guild                                members tell each other which recipes their characters know, under
--                                            the same switch as Cooking's (DT.Food.db.settings.share). Nothing else.
--
-- db: mine[guid] = { name, t, ids = { [recipe] = true }, lines = { [skill line] = true (its window was read) } }
--     guild[name] = { t, from = sender, ids = { [recipe] = true } }
-- On the wire:  KNOWN  "<character>;<recipe>,<recipe>,..."     REQUEST  "<member>": that member, send yours
-- The HELLO summary is how many recipes my character knows.

local _, DT = ...
local Craft = {}
DT.Craft = Craft

-- The tabs, in their order. On the first row, with Fishing and Cooking: First Aid; behind a line Mining; behind
-- another Campsite: what every profession makes for the camp (Forever's own: the tent, the chair, the campfires,
-- the workbenches), taken out of the professions' own tabs and listed together, each with its profession.
-- The crafting professions have the second row to themselves (row = true: it begins a row).
Craft.PROFESSIONS = {
	{ line = 129, title = "First Aid", order = 52, group = 1 },
	{ line = 186, title = "Mining", order = 54, group = 2 },
	{ camp = true, title = "Campsite", order = 56, group = 3 },
	{ line = 171, title = "Alchemy", order = 60, group = 4, row = true },
	{ line = 164, title = "Blacksmithing", order = 61, group = 4 },
	{ line = 333, title = "Enchanting", order = 62, group = 4 },
	{ line = 202, title = "Engineering", order = 63, group = 4 },
	{ line = 165, title = "Leatherworking", order = 64, group = 4 },
	{ line = 197, title = "Tailoring", order = 65, group = 4 },
}
local LINE_NAMES = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism", [185] = "Cooking",
	[186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }

-- Is a recipe one for the camp: does it make one of Forever's campsite items (they are numbered together)?
-- ponytail: told by the item's number, 279900 to 279999. A campsite item numbered elsewhere would stay in its
-- profession's tab; list such by hand here if one turns up.
function Craft.IsCamp(spell)
	local r = spell and DT.Recipes and DT.Recipes[spell]
	return r ~= nil and r[7] >= 279900 and r[7] <= 279999
end
-- the same asked of the item made (for the Cooking tab, which goes by items)
function Craft.IsCampItem(item)
	return type(item) == "number" and item >= 279900 and item <= 279999
end
local COOKING = 185 -- (the Food module's: its recipes are not kept or sent here)
local MAX_IDS = 4000 -- recipes taken from one message
local ASK = 100 -- items asked of the game per pass, for names it does not know yet

local views = {}
Craft.asked = {} -- [item] = true: its name was asked of the game this session

-- something the rows rest on changed (prices, what is known, a name): each tab works its rows out anew when
-- it is next drawn
local function Stale()
	for _, v in pairs(views) do v.dirty, v.stale = true, true end
end

local function Count(set)
	local n = 0
	for _ in pairs(set or {}) do n = n + 1 end
	return n
end

local function Me()
	return Craft.db.mine[Craft.me]
end

local function Short(sender)
	return DT.Name(sender)
end

---------------------------------------------------------------------------
-- Prices and profit
---------------------------------------------------------------------------

local function Auction(item)
	local api = DawnMarket and DawnMarket.API
	return api and api.GetLatest and (api.GetLatest(item)) or nil
end

-- What one of an item costs to get: the cheaper of the auction house and a vendor, and which ("auction",
-- "vendor"); nothing when neither is known.
function Craft.Cost(item)
	local api = DawnMarket and DawnMarket.API
	local ah = Auction(item)
	local vendor = (api and api.GetVendor and (api.GetVendor(item))) or (DT.VendorPrice and DT.VendorPrice[item]) or nil
	if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
	if ah then return ah, "auction" end
end

-- the recipe that makes an item (the one that turns yellow soonest, where there are several); nil for none
local byItem
local data = 0 -- counts the times the recipes were put together anew (Core/DBSeed.lua: rows of a guildmate's came)
DT:On("DT_DATA_UPDATE", function()
	byItem, data = nil, data + 1
	Stale()
end)
function Craft.ByItem(item)
	if not byItem then
		byItem = {}
		for spell, r in pairs(DT.Recipes or {}) do
			local made, was = r[7], byItem[r[7]]
			if made > 0 and (not was or r[3] < DT.Recipes[was][3] or (r[3] == DT.Recipes[was][3] and spell < was)) then byItem[made] = spell end
		end
	end
	return byItem[item]
end

-- What one making of a recipe costs and earns at today's prices:
--   { parts = { { item, n, each, from } }, mats = their sum where known, missing = { item, ... } (no price),
--     made, yield, price (auction, each), sells (all of them, less the house's 5%), profit (sells - mats) }
-- profit is nil while a price is missing, and for a recipe that makes no item (an enchantment).
-- ponytail: the latest auction price, not a median; what is in the bags already is not counted, nor the deposit.
function Craft.Profit(spell)
	local r = spell and DT.Recipes and DT.Recipes[spell]
	if not r then return nil end
	local p = { parts = {}, missing = {}, mats = 0, made = r[7] > 0 and r[7] or nil, yield = r[8] }
	local list = r[9]
	for i = 1, #list, 2 do
		local each, from = Craft.Cost(list[i])
		p.parts[#p.parts + 1] = { item = list[i], n = list[i + 1], each = each, from = from }
		if each then p.mats = p.mats + each * list[i + 1] else p.missing[#p.missing + 1] = list[i] end
	end
	if p.made then
		p.price = Auction(p.made)
		if p.price then p.sells = math.floor(p.price * p.yield * 0.95) end
		if p.sells and not p.missing[1] then p.profit = p.sells - p.mats end
		-- sold to a vendor instead: what a vendor pays for it (the game's own figure; none for what cannot be sold)
		local pays = C_Item and C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(p.made))
		if type(pays) == "number" and pays > 0 then
			p.vendorSells = math.floor(pays * p.yield)
			if not p.missing[1] then p.vendorProfit = p.vendorSells - p.mats end
		end
	end
	return p
end

-- have I the materials for one making: in the bags or the bank of my characters (the Inventory tab's count)?
function Craft.Have(p)
	local count = DawnInventory and DawnInventory.API and DawnInventory.API.Count
	if not (count and p and p.parts[1]) then return false end
	for _, part in ipairs(p.parts) do
		local bags, bank = count(part.item)
		if (bags or 0) + (bank or 0) < part.n then return false end
	end
	return true
end

-- The tick boxes beside the search box of every crafting tab: what to list.
Craft.FILTERS = {
	{ "known", "Known", "Only what this character knows." },
	{ "missing", "Missing", "Only what this character does not know yet." },
	{ "profit", "Profitable", "Only what earns something at today's prices, on the auction house or sold to a vendor." },
	{ "mats", "Have mats", "Only what you have the materials for, in the bags or the bank of your characters." },
}

-- does a recipe pass the boxes ticked? (known: this character knows it; p: its sum; have: the materials are there)
function Craft.Passes(filter, known, p, have)
	if filter.known and not known then return false end
	if filter.missing and known then return false end
	if filter.profit and not (p and ((p.profit or 0) > 0 or (p.vendorProfit or 0) > 0)) then return false end
	if filter.mats and not have then return false end
	return true
end

-- Builds the boxes to the right of `anchor`; filter[key] is set by them, changed() called after. Returns the
-- boxes by key, and the last label (to put something after).
function Craft.Ticks(panel, anchor, filter, changed)
	local boxes, after = {}, anchor
	for i, f in ipairs(Craft.FILTERS) do
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("LEFT", after, "RIGHT", i == 1 and 8 or 6, 0)
		box.label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		box.label:SetPoint("LEFT", box, "RIGHT", 0, 0)
		box.label:SetText(f[2])
		box:SetScript("OnClick", function(self)
			filter[f[1]] = self:GetChecked() and true or nil
			-- ("known" and "missing" cannot both be: the one just ticked stands)
			if f[1] == "known" and filter.known then filter.missing = nil elseif f[1] == "missing" and filter.missing then filter.known = nil end
			for key, b in pairs(boxes) do b:SetChecked(filter[key] and true or false) end
			changed()
		end)
		box:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(f[3], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		box:SetScript("OnLeave", function() GameTooltip:Hide() end)
		boxes[f[1]], after = box, box.label
	end
	return boxes, after
end

local GREY, GREEN, RED = "|cff888888", "|cff40ff40", "|cffff4040"

local function ItemName(item)
	local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item)
	return name or ("item " .. item)
end

-- "1s 20c", or with a price missing "1s 20c +?" (what is known, and more), or "?"
function Craft.MatsText(p)
	if not p.parts[1] then return GREY .. "-|r" end
	if not p.missing[1] then return DT.Money(p.mats) end
	return (p.mats > 0 and (DT.Money(p.mats) .. " ") or "") .. GREY .. "+?|r"
end

-- the profit as text: sold on the auction house, or (vendor = true) sold to a vendor
function Craft.ProfitText(p, vendor)
	local profit = vendor and p.vendorProfit or (not vendor and p.profit) or nil
	if profit then return (profit >= 0 and GREEN .. "+" or RED .. "-") .. DT.Money(math.abs(profit)) .. "|r" end
	-- (nothing made, or nothing a vendor will pay for: a dash; a price missing: a question)
	if not p.made or (vendor and not p.vendorSells) then return GREY .. "-|r" end
	return GREY .. "?|r"
end

-- the sum, line by line, for a tooltip
function Craft.ProfitTip(tip, p)
	tip:AddLine(" ")
	tip:AddLine("Materials for one making:", 1, 0.82, 0)
	for _, part in ipairs(p.parts) do
		tip:AddDoubleLine(("  %dx %s"):format(part.n, ItemName(part.item)),
			part.each and ("%s  %s(%s%s)|r"):format(DT.Money(part.each * part.n), GREY, part.from, part.n > 1 and (", " .. DT.Money(part.each) .. " each") or "")
				or (RED .. "no price known|r"), 1, 1, 1, 1, 1, 1)
	end
	tip:AddDoubleLine("Materials", Craft.MatsText(p), 0.75, 0.75, 0.75, 1, 1, 1)
	if p.made then
		tip:AddDoubleLine(p.yield ~= 1 and ("Sells for (%g made, less the 5%% cut)"):format(p.yield) or "Sells for (less the 5% cut)",
			p.sells and DT.Money(p.sells) or (RED .. "no auction price known|r"), 0.75, 0.75, 0.75, 1, 1, 1)
		tip:AddDoubleLine("Profit on the auction house", Craft.ProfitText(p), 0.75, 0.75, 0.75, 1, 1, 1)
		tip:AddDoubleLine("Sold to a vendor instead", p.vendorSells and DT.Money(p.vendorSells) or (GREY .. "a vendor pays nothing for it|r"), 0.75, 0.75, 0.75, 1, 1, 1)
		tip:AddDoubleLine("Profit at a vendor", Craft.ProfitText(p, true), 0.75, 0.75, 0.75, 1, 1, 1)
	else
		tip:AddLine("Makes no item to sell: no profit to work out.", 0.6, 0.6, 0.6)
	end
end

---------------------------------------------------------------------------
-- What a character knows, and the guild
---------------------------------------------------------------------------

local function On()
	return DT.Food ~= nil and DT.Food.db ~= nil and DT:Shares()
end

local function Send()
	local me = Me()
	if not (On() and me and next(me.ids)) then return end
	local ids = {}
	for id in pairs(me.ids) do ids[#ids + 1] = id end
	table.sort(ids)
	DT.Comms:Send("crafts", "KNOWN", me.name .. ";" .. table.concat(ids, ","), true)
end

-- The profession window: which of its recipes this character has learned. (Every profession's window; of
-- Cooking's only what it makes for the camp, the rest being the Food module's. Somebody else's linked window
-- is not mine to read.)
local function ReadWindow()
	local T = C_TradeSkillUI
	if not (Craft.db and T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
	if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild()) then return end
	local learned, lines = {}, {}
	for _, recipe in ipairs(T.GetAllRecipeIDs() or {}) do
		local r = DT.Recipes and DT.Recipes[recipe]
		if r and (r[1] ~= COOKING or Craft.IsCamp(recipe)) then
			lines[r[1]] = true
			local info = T.GetRecipeInfo(recipe)
			if info and info.learned then learned[recipe] = true end
		end
	end
	if not next(lines) then return end
	local me, changed = Me(), false
	-- (what was known of the professions this window lists is replaced; the others' stays)
	for id in pairs(me.ids) do
		local r = DT.Recipes[id]
		if r and lines[r[1]] and not learned[id] then me.ids[id], changed = nil, true end
	end
	for id in pairs(learned) do
		if not me.ids[id] then me.ids[id], changed = true, true end
	end
	me.lines = me.lines or {}
	for line in pairs(lines) do me.lines[line] = true end
	me.t = DT.Now()
	Stale()
	if changed then Send() end
end
Craft.ReadWindow = ReadWindow

local replied = {} -- [requester] = GetTime() of my last answer

local function OnMessage(kind, payload, sender)
	if not On() then return end
	if kind == "KNOWN" then
		local name, list = payload:match("^([^;]+);([%d,]*)$")
		if not name or #name > 40 then return end
		for _, c in pairs(Craft.db.mine) do
			if c.name == name then return end -- one of my own: I know better
		end
		local ids, n = {}, 0
		for id in list:gmatch("%d+") do
			if n >= MAX_IDS then break end
			ids[tonumber(id)], n = true, n + 1
		end
		Craft.db.guild[name] = { t = DT.Now(), from = Short(sender), ids = ids }
		Stale()
	elseif kind == "REQUEST" then
		if payload ~= DT.Comms.self then return end
		if replied[sender] and GetTime() - replied[sender] < 60 then return end
		replied[sender] = GetTime()
		Send()
	end
end

-- a member whose count is not what I hold for them is asked for their list (as the Food module does)
local asked = {}
local function OnHello(sender, summary)
	local theirs = tonumber(summary)
	if not On() or not theirs or asked[sender] == theirs then return end
	local who = Short(sender)
	for _, c in pairs(Craft.db.guild) do
		if c.from == who and Count(c.ids) == theirs then return end
	end
	asked[sender] = theirs
	C_Timer.After(math.random() * 3, function() DT.Comms:Send("crafts", "REQUEST", sender) end)
end

-- everyone who can make a recipe: this character first, then my others, then the guild
local function Makers(spell)
	local names = {}
	for guid, c in pairs(Craft.db.mine) do
		if c.ids[spell] and guid ~= Craft.me then names[#names + 1] = "|cffffd100" .. c.name .. "|r" end
	end
	for name, c in pairs(Craft.db.guild) do
		if c.ids[spell] then names[#names + 1] = name end
	end
	table.sort(names)
	if Me().ids[spell] then table.insert(names, 1, GREEN .. "You|r") end
	return names
end
Craft.Makers = Makers

---------------------------------------------------------------------------
-- A profession's tab
---------------------------------------------------------------------------

local ROW_H, SIDE_W, TOP_H, SIDE_H = 18, 150, 28, 20
local WHERE_W = 250
-- (a column of width 0 takes what is left; the one of a width below 0 sits at the right edge, that wide)
-- "Profit (AH)": made and sold on the auction house; "Profit (vendor)": made and sold to a vendor
local CAMP_COLS = { { "Item", 180 }, { "Profession", 100 }, { "Skill", 116 }, { "Mats", 80, true }, { "Profit (AH)", 92, true }, { "Profit (vendor)", 104, true },
	{ "This character", 90 }, { "Who can make it", 0 }, { "Where to get it", -WHERE_W } }
-- (these begin with the most when first clicked; the others with the least)
local DESC_FIRST = { ["Profit (AH)"] = true, ["Profit (vendor)"] = true, ["This character"] = true, ["Who can make it"] = true }
local COLS = { { "Item", 196 }, { "Skill", 116 }, { "Mats", 80, true }, { "Profit (AH)", 92, true }, { "Profit (vendor)", 104, true }, { "This character", 90 }, { "Who can make it", 0 },
	{ "Where to get it", -WHERE_W } }

-- what the game calls a recipe that makes no item
local function SpellName(spell)
	local get = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
	local ok, name = pcall(function() return get(spell) end)
	return ok and type(name) == "string" and name ~= "" and name or ("recipe " .. spell)
end

-- the game's own link of a recipe that makes no item; else the old client's enchant link, written out
function Craft.SpellLink(spell, name)
	local get = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
	local ok, link = pcall(function() return get(spell) end)
	return ok and type(link) == "string" and link or ("|cffffd000|Henchant:%d|h[%s]|h|r"):format(spell, name or ("recipe " .. spell))
end

-- the kind of thing an item is ("Armor", "Weapon", "Consumable"...), as the game names it
local function KindOf(item)
	local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	if instant then
		local ok, _, kind = pcall(instant, item)
		if ok and type(kind) == "string" and kind ~= "" then return kind end
	end
	return "Other"
end

local function NewView(prof)
	local COLS = prof.camp and CAMP_COLS or COLS
	local v = { prof = prof, dirty = true, rows = {}, heads = {}, sideButtons = {}, list = {}, offset = 0, sortBy = { col = prof.camp and 3 or 2, desc = false }, filter = {} }
	local panel, side, search, countText, bar

	-- the recipes of this profession, once
	local function Recipes()
		if not v.spells or v.data ~= data then
			v.spells, v.data = {}, data
			for spell, r in pairs(DT.Recipes or {}) do
				-- (what is made for the camp is the Campsite tab's, whatever profession makes it)
				local camp = Craft.IsCamp(spell)
				if (prof.camp and camp) or (r[1] == prof.line and not camp) then v.spells[#v.spells + 1] = spell end
			end
			table.sort(v.spells)
		end
		return v.spells
	end

	-- Every recipe of the profession as a row, with its names, sums and who knows it. Worked out when something
	-- it rests on changed (v.stale: prices, what is known, a name that arrived); searching, picking a kind and
	-- sorting only go through the rows there are.
	local function Rows()
		local me, budget = Me(), ASK
		local anyRead = false
		local F = DT.Food
		local all = {}
		for _, spell in ipairs(Recipes()) do
			local r = DT.Recipes[spell]
			local made = r[7] > 0 and r[7] or nil
			local name, quality, icon
			if made then
				local _
				name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(made)
				-- (one the game has not told us about yet: asked for once a session, a batch a pass; the tab is
				-- drawn again as the answers come. One that never comes is not asked for again.)
				if not name and budget > 0 and not Craft.asked[made] and C_Item.RequestLoadItemDataByID then
					budget = budget - 1
					Craft.asked[made] = true
					pcall(C_Item.RequestLoadItemDataByID, made)
				end
			else
				name = SpellName(spell)
			end
			local known = me.ids[spell] or false
			-- (was this recipe's profession ever read on this character? Cooking's by the Food module)
			local read = (me.lines and me.lines[r[1]]) or (r[1] == COOKING and F and F.db and F.db.mine[F.me] and F.db.mine[F.me].t ~= nil) or false
			anyRead = anyRead or read
			local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
			local makers, p = Makers(spell), Craft.Profit(spell)
			local scroll = r[6] > 0 and r[6] or nil
			local src = scroll and F and F.Source(scroll) or nil
			local where = scroll and F and F.WhereText(scroll, src) or not scroll and (GREY .. "trainer|r") or ""
			local shown = name or ("item " .. made)
			all[#all + 1] = { spell = spell, id = made, name = shown, nameL = shown:lower(), kind = prof.camp and (LINE_NAMES[r[1]] or "Other") or made and KindOf(made) or "Enchantments", known = known,
				makers = makers, profit = p, have = Craft.Have(p), scroll = scroll, src = src, scrollName = scroll and ItemName(scroll) or nil,
				(icon and ("|T%s:14|t "):format(icon) or "") .. color .. shown .. "|r" .. (r[8] > 1 and (GREY .. " x%g|r"):format(r[8]) or ""),
				("|cffff8040%s|r |cffffff00%d|r |cff40c040%d|r |cff808080%d|r"):format(r[2] > 0 and r[2] or "?", r[3], r[4], r[5]),
				Craft.MatsText(p), Craft.ProfitText(p), Craft.ProfitText(p, true),
				not read and (GREY .. "?|r") or known and (GREEN .. "known|r") or (RED .. "missing|r"),
				makers[1] and table.concat(makers, ", ") or (GREY .. "nobody known|r"), where,
				-- what each column sorts by (profit and mats not known: last)
				sort = { shown, r[2] > 0 and r[2] or r[3], p.missing[1] and math.huge or p.mats, p.profit or -math.huge, p.vendorProfit or -math.huge,
					not read and 1 or known and 2 or 0, #makers, src and (src.kind .. " " .. (src.name or "")) or not scroll and "trainer" or "~~" } }
			-- (the Campsite tab: the profession, as a column of its own after the item)
			if prof.camp then
				local row = all[#all]
				table.insert(row, 2, LINE_NAMES[r[1]] or "?")
				table.insert(row.sort, 2, LINE_NAMES[r[1]] or "?")
			end
		end
		return all, anyRead
	end

	local function Rebuild()
		if v.stale or not v.all then
			v.all, v.read = Rows()
			v.stale = false
		end
		local q, counts, read = (search:GetText() or ""):lower(), {}, v.read
		v.list = {}
		for _, d in ipairs(v.all) do
			if Craft.Passes(v.filter, d.known, d.profit, d.have) and (q == "" or d.nameL:find(q, 1, true)) then
				counts[d.kind] = (counts[d.kind] or 0) + 1
				if not v.picked or v.picked == d.kind then v.list[#v.list + 1] = d end
			end
		end
		local by = v.sortBy
		table.sort(v.list, function(a, b)
			local x, y = a.sort[by.col], b.sort[by.col]
			if x ~= y then
				if by.desc then return x > y end
				return x < y
			end
			local s = prof.camp and 3 or 2 -- (then by skill)
			if a.sort[s] ~= b.sort[s] then return a.sort[s] < b.sort[s] end
			if a.name ~= b.name then return a.name < b.name end
			return a.spell < b.spell
		end)
		local kinds, total = {}, 0
		for kind, n in pairs(counts) do
			kinds[#kinds + 1] = kind
			total = total + n
		end
		table.sort(kinds)
		local sections = { { label = ("All (%d)"):format(total) } }
		for _, kind in ipairs(kinds) do sections[#sections + 1] = { label = ("%s (%d)"):format(kind, counts[kind]), kind = kind } end
		return sections, read
	end

	local function MakeRow(i)
		local row = CreateFrame("Frame", nil, panel)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", SIDE_W + 8, -TOP_H - ROW_H - (i - 1) * ROW_H)
		row:SetPoint("RIGHT", -12, 0)
		row.pcols = {}
		local x = 0
		for c, col in ipairs(COLS) do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			if col[2] > 0 then
				fs:SetPoint("LEFT", x, 0)
				fs:SetWidth(col[2] - 6)
			elseif col[2] == 0 then
				fs:SetPoint("LEFT", x, 0)
				fs:SetPoint("RIGHT", -WHERE_W - 6, 0)
			else
				fs:SetPoint("RIGHT", -6, 0)
				fs:SetWidth(-col[2] - 6)
			end
			fs:SetJustifyH(col[3] and "RIGHT" or "LEFT")
			fs:SetWordWrap(false)
			row.pcols[c] = fs
			x = x + math.max(0, col[2])
		end
		if DT.Food and DT.Food.WhereFrame then row.where = DT.Food.WhereFrame(row, WHERE_W, 0) end
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			local d = self.data
			if not d then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			-- (a recipe that makes no item, an enchantment: the game's own tooltip of the spell, where it gives one)
			if d.id then GameTooltip:SetHyperlink("item:" .. d.id)
			elseif not (GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, d.spell) and (GameTooltip:NumLines() or 0) > 0) then
				GameTooltip:AddLine(d.name)
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(d.makers[1] and ("Can make it: " .. table.concat(d.makers, ", ")) or "Nobody known who can make it.", 1, 1, 1, true)
			Craft.ProfitTip(GameTooltip, d.profit)
			if d.id then
				GameTooltip:AddLine("Shift-click: link in chat. Shift-right-click: its web page. Hold Shift: compare.", 0.5, 0.8, 1)
				DT.Favs.Hint(GameTooltip, d.id)
			else
				GameTooltip:AddLine("Shift-click: link in chat. Shift-right-click: its web page.", 0.5, 0.8, 1)
			end
			GameTooltip:Show()
			if d.id then DT:CompareTip(self) end
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnMouseUp", function(self, button)
			local d = self.data
			if d and d.id then DT:LinkClick(button, DT:GameItemLink(d.id, d.name), d.name, DT:ItemLink(d.id), d.id)
			elseif d then DT:LinkClick(button, Craft.SpellLink(d.spell, d.name), d.name, "https://www.wowhead.com/forever/spell=" .. d.spell) end
		end)
		v.rows[i] = row
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
			v.picked, v.offset = self.section.kind, 0
			v.Refresh()
		end)
		v.sideButtons[i] = b
		return b
	end

	function v.Refresh()
		if not panel then return end
		v.dirty = false
		local sections, read = Rebuild()
		local list, rows = v.list, v.rows
		local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H - ROW_H) / ROW_H))
		local max = math.max(0, #list - fit)
		v.offset = math.max(0, math.min(v.offset, max))
		bar:SetMinMaxValues(0, max)
		bar:SetValue(v.offset)
		bar:SetShown(max > 0)
		bar.thumb:SetSize(8, math.max(16, fit * ROW_H * fit / math.max(fit, #list)))
		for i = 1, math.max(fit, #rows) do
			local d = i <= fit and list[v.offset + i]
			local row = rows[i] or (d and MakeRow(i))
			if row then
				row.data = d or nil
				row:SetShown(d and true or false)
				for c, cell in ipairs(row.pcols) do cell:SetText(d and d[c] or "") end
				if row.where then row.where:SetShown(d and d.src and true or false) end
			end
		end
		for i = 1, math.max(#sections, #v.sideButtons) do
			local s = sections[i]
			local b = v.sideButtons[i] or (s and SideButton(i))
			if b then
				b.section = s
				b:SetShown(s ~= nil)
				if s then
					b.label:SetText(s.label)
					b.sel:SetShown(s.kind == v.picked)
				end
			end
		end
		for c, h in ipairs(v.heads) do
			h.text:SetText("|cffffd100" .. COLS[c][1] .. (v.sortBy.col == c and (v.sortBy.desc and " v" or " ^") or "") .. "|r")
		end
		countText:SetText(not next(DT.Recipes or {}) and (GREY .. "No recipes known yet. DawnTools does not come with them: they reach you from guild members, with the game database shared (/dt db).|r")
			or ("%d recipes%s"):format(#list, read and (", %d of them known to this character"):format(Count(Me().ids) > 0 and (function()
			local n = 0
			for _, d in ipairs(list) do if Me().ids[d.spell] then n = n + 1 end end
			return n
		end)() or 0) or ("  " .. GREY .. (prof.camp and "Open your profession windows on this character to see what it knows.|r" or ("Open your " .. prof.title .. " window on this character to see what it knows.|r")))))
	end

	function v.Build(parent)
		panel = parent
		v.panel = panel
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
			v.offset, v.dirty = 0, true
		end)
		search:SetScript("OnEnterPressed", search.ClearFocus)
		search:SetScript("OnEscapePressed", function(self)
			self:SetText("")
			self:ClearFocus()
		end)
		v.search = search
		-- what to list: known, missing, profitable, what I have the materials for
		local last
		v.ticks, last = Craft.Ticks(panel, search, v.filter, function()
			v.offset = 0
			v.Refresh()
		end)
		countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		countText:SetPoint("LEFT", last, "RIGHT", 12, 0)
		countText:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
		countText:SetJustifyH("LEFT")
		countText:SetWordWrap(false)
		v.countText = countText

		local x = SIDE_W + 8
		for c, col in ipairs(COLS) do
			-- click to sort, again to turn it round
			local h = CreateFrame("Button", nil, panel)
			if col[2] < 0 then h:SetPoint("TOPRIGHT", -12 - 6, -TOP_H) else h:SetPoint("TOPLEFT", x, -TOP_H) end
			h:SetSize(col[2] > 0 and col[2] - 6 or col[2] < 0 and -col[2] - 6 or 160, ROW_H)
			h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			h.text:SetAllPoints()
			h.text:SetJustifyH(col[3] and "RIGHT" or "LEFT")
			h.text:SetWordWrap(false)
			h:SetScript("OnClick", function()
				if v.sortBy.col == c then
					v.sortBy.desc = not v.sortBy.desc
				else
					-- (names, skill and cost from the least; the profits, "this character" and "who can make it" from the most)
					v.sortBy.col, v.sortBy.desc = c, DESC_FIRST[col[1]] or false
				end
				v.Refresh()
			end)
			v.heads[c] = h
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
			if value == v.offset then return end -- (Refresh sets the bar too)
			v.offset = value
			v.Refresh()
		end)
		panel:EnableMouseWheel(true)
		panel:SetScript("OnMouseWheel", function(_, delta)
			v.offset = v.offset - delta * 3
			v.Refresh()
		end)
		panel:SetScript("OnSizeChanged", v.Refresh)
		local nextUpdate = 0
		panel:SetScript("OnUpdate", function()
			if not v.dirty or GetTime() < nextUpdate then return end
			-- (hundreds of recipes, each with its sum: only the tab that is looked at, and once a second at most;
			-- one that was not looked at is worked out when it is shown)
			if not v.shown or (panel.IsVisible and not panel:IsVisible()) then return end
			-- (in a fight the game cuts off a script that takes long: going through the recipes waits for its end)
			if InCombatLockdown and InCombatLockdown() then return end
			nextUpdate = GetTime() + 1
			v.Refresh()
		end)
	end

	return v
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

local tabs = {}
for _, prof in ipairs(Craft.PROFESSIONS) do
	local v = NewView(prof)
	local key = prof.camp and "camp" or prof.line
	views[key] = v
	tabs[#tabs + 1] = { id = "craft" .. key, title = prof.title, defaultOrder = prof.order, group = prof.group, row = prof.row, under = "craft",
		create = v.Build,
		-- (v.shown: this is the sub-tab being looked at; another one, or another tab, and it rests)
		onShow = function()
			v.shown, v.stale = true, true -- (what is in the bags may have changed since it was last looked at)
			v.Refresh()
		end,
		onHide = function() v.shown = false end }
end
Craft.views = views

DT:RegisterModule("crafts", {
	title = "Professions",
	version = 1,
	tabs = tabs,
	onEnable = function(mod)
		local db = mod.db
		db.mine, db.guild = db.mine or {}, db.guild or {}
		Craft.db, Craft.me = db, UnitGUID("player")
		local me = db.mine[Craft.me] or { ids = {} }
		db.mine[Craft.me] = me
		local first, surname = UnitName("player"), nil
		if UnitFullName then first, surname = UnitFullName("player") end
		me.name = (first or "?") .. (surname and surname ~= "" and (" " .. surname) or "")
		-- (the window fires both events in bursts: one read, a second after the first)
		local pending
		local function Soon()
			if pending then return end
			pending = true
			C_Timer.After(1, function() pending = nil; ReadWindow() end)
		end
		DT:On("TRADE_SKILL_SHOW", Soon)
		DT:On("TRADE_SKILL_LIST_UPDATE", Soon)
		-- (prices changed, an item's name arrived: the sums and names are worked out again)
		DT:On("DT_MARKET_UPDATE", Stale)
		-- (only for an item one of these tabs asked about: the game sends this for every item anybody looks at)
		DT:On("GET_ITEM_INFO_RECEIVED", function(item) if Craft.asked[item] then Stale() end end)
		-- (Cooking's switch is the one this goes by: switched on, what I know is told)
		DT:On("DT_SETTINGS", function(name, key)
			if name == "food" and key == "share" then
				Send()
				Stale()
			end
		end)
	end,
	held = function()
		return ("which recipes %d guild characters know"):format(Count(Craft.db.guild))
	end,
	progress = function()
		-- every recipe listed on these tabs (the professions that have one, and what is made for the camp); of them,
		-- those somebody (I, my characters, the guild) can make
		local lines, all, have = {}, 0, 0
		for _, prof in ipairs(Craft.PROFESSIONS) do
			if prof.line then lines[prof.line] = true end
		end
		local known = {}
		for _, c in pairs(Craft.db.mine) do for id in pairs(c.ids) do known[id] = true end end
		for _, c in pairs(Craft.db.guild) do for id in pairs(c.ids) do known[id] = true end end
		for spell, r in pairs(DT.Recipes or {}) do
			if lines[r[1]] or Craft.IsCamp(spell) then
				all = all + 1
				if known[spell] then have = have + 1 end
			end
		end
		return { { "Profession recipes somebody can make", have, all, "you, your characters, or the guild" } }
	end,
	hello = function()
		if not On() then return nil end
		return tostring(Count(Me().ids))
	end,
	onHello = function(_, sender, summary) OnHello(sender, summary) end,
	onMessage = function(_, kind, payload, sender) OnMessage(kind, payload, sender) end,
})
