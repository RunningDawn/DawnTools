-- DawnMarket :: UI
-- The Market tab, laid out like the auction house: categories down the left, a search box above a sortable
-- price table, and the selected item's history underneath. Also the tooltip line and the module's
-- registration with the core.

local _, DT = ...
local M, L = DT.Market, DT.Logic
-- class / group / leaf: the category picked on the left, as deep as it was picked (nil = all at that depth);
-- fav: favourites only
-- minLevel / maxLevel (required level), qualities ({ [quality] = true }, nil = all), usable: the filters above the table
local V = { sort = "t", desc = true, rows = 0 }
M.View = V

local ROW_H, DAYS = 18, L.KEEP_DAYS
local SIDE_W, TOP_H, DETAIL_H = 150, 54, 116 -- (top: the search line, then the filter line)
local COLS = {
	{ key = "name", title = "Item", width = 80 }, -- takes whatever width is left
	{ key = "lvl", title = "Lvl", width = 34, right = true }, -- level needed to use it
	{ key = "ilvl", title = "iLvl", width = 38, right = true },
	{ key = "p", title = "Last price", width = 98, right = true }, -- (money columns: room for 99g 99s 99c with coin pictures)
	{ key = "t", title = "Age", width = 56, right = true },
	{ key = "q", title = "Qty", width = 44, right = true },
	{ key = "med", title = "7d median", width = 98, right = true },
	{ key = "trend", title = "Trend", width = 44, right = true },
	{ key = "vendor", title = "Vendor pays", width = 98, right = true },
	{ key = "vbuy", title = "Vendor sells", width = 98, right = true }, -- (known once someone here has opened that vendor)
	{ key = "o", title = "Seen by", width = 80 },
}
-- item classes in the auction house's order; any other class found in the data follows
local CLASS_ORDER = { 2, 4, 1, 3, 8, 0, 16, 7, 9, 19, 17, 12, 15 }
-- The categories are a tree, laid out as the auction house lays its own out: class > group > leaf.
--   weapons: One-Handed / Two-Handed / Ranged / Miscellaneous > the weapon type
--   armor:   Plate / Mail / Leather / Cloth > where it is worn; Miscellaneous > neck, back, finger...; shields
--   others:  their sub-category, no leaves
local SubName -- (defined below)
local WEAPON, ARMOR = 2, 4
local WEAPON_GROUPS = { "1h", "2h", "ranged", "misc" }
local WEAPON_LABEL = { ["1h"] = AUCTION_SUBCATEGORY_ONE_HANDED or "One-Handed", ["2h"] = AUCTION_SUBCATEGORY_TWO_HANDED or "Two-Handed",
	ranged = AUCTION_SUBCATEGORY_RANGED or "Ranged", misc = AUCTION_SUBCATEGORY_MISCELLANEOUS or "Miscellaneous" }
-- [weapon subclass] = group: axes, maces, swords, warglaives, fist weapons, daggers, wands; the two-handed ones,
-- polearms, staves; bows, guns, thrown, crossbows. Anything else is "misc".
local GROUP_OF = { [0] = "1h", [4] = "1h", [7] = "1h", [9] = "1h", [13] = "1h", [15] = "1h", [19] = "1h",
	[1] = "2h", [5] = "2h", [8] = "2h", [6] = "2h", [10] = "2h", [2] = "ranged", [3] = "ranged", [16] = "ranged", [18] = "ranged" }
local ARMOR_GROUPS = { 4, 3, 2, 1, 0 } -- plate, mail, leather, cloth, miscellaneous; any other (shields...) follows
-- where armor is worn, in the auction house's order: first the eight of a set, then what Miscellaneous holds
local SLOTS = { "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST",
	"INVTYPE_HAND", "INVTYPE_NECK", "INVTYPE_CLOAK", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_HOLDABLE", "INVTYPE_BODY" }
local SLOT_RANK = {}
for i, slot in ipairs(SLOTS) do SLOT_RANK[slot] = i end
local SLOT_SAME = { INVTYPE_ROBE = "INVTYPE_CHEST" }

-- an item's group and leaf within its class (leaf nil: its group has no leaves for it)
local function Place(item)
	local sub, slot = item.s or 0, item.e or ""
	if item.c == WEAPON then return GROUP_OF[sub] or "misc", sub end
	if item.c == ARMOR then
		slot = SLOT_SAME[slot] or slot
		if slot == "" then slot = nil end
		-- (a cloak is cloth by its type, but the auction house files it under Miscellaneous)
		if slot == "INVTYPE_CLOAK" or sub == 0 then return 0, slot end
		if sub >= 1 and sub <= 4 then return sub, slot end
	end
	return sub, nil
end

local function GroupLabel(class, group)
	if class == WEAPON then return WEAPON_LABEL[group] end
	return SubName(class, group)
end

local function LeafLabel(class, leaf)
	if class == WEAPON then return SubName(class, leaf) end
	return _G[leaf] or leaf -- (the game's own word for the slot: INVTYPE_HEAD = "Head")
end

-- keys of a set in the order to list them: those of `first` as they stand there, then the rest sorted
local function Ordered(set, first, rank)
	local out, rest = {}, {}
	for _, key in ipairs(first or {}) do
		if set[key] then out[#out + 1] = key end
	end
	for key in pairs(set) do
		local listed = false
		for _, k in ipairs(out) do listed = listed or k == key end
		if not listed then rest[#rest + 1] = key end
	end
	table.sort(rest, function(a, b)
		local x, y = rank and rank[a] or a, rank and rank[b] or b
		if type(x) ~= type(y) then return type(x) == "number" end
		return x < y
	end)
	for _, key in ipairs(rest) do out[#out + 1] = key end
	return out
end

local function ClassName(class)
	local fn = C_Item.GetItemClassInfo or GetItemClassInfo
	return fn and fn(class) or ("Class " .. class)
end

function SubName(class, sub)
	local fn = C_Item.GetItemSubClassInfo or GetItemSubClassInfo
	local name = fn and fn(class, sub)
	return name and name ~= "" and name or "Other"
end

local function Vendor(id)
	local _, _, _, _, _, _, _, _, _, _, sell = C_Item.GetItemInfo(id)
	return sell or 0
end

local SORT = {
	name = function(_, item) return (item.n or ""):lower() end,
	p = function(_, item) return item.p end,
	t = function(_, item) return item.t end,
	q = function(_, item) return item.q or 0 end,
	med = function(_, item, now) return L.Median(item, 7, now) or 0 end,
	trend = function(_, item, now) return L.Trend(item, now) or 0 end,
	vendor = Vendor,
	vbuy = function(id) return M.db.vendors[id] and M.db.vendors[id].p or 0 end,
	lvl = function(id) return select(5, C_Item.GetItemInfo(id)) or 0 end,
	ilvl = function(id) return select(4, C_Item.GetItemInfo(id)) or 0 end,
	o = function(_, item) return item.o or "" end,
}

-- "Sold by Kira, Booty Bay for 10c (limited stock)", or nil
local function VendorText(id)
	local v = M.db.vendors[id]
	return v and ("Sold by %s, %s for %s%s"):format(v.v, v.z, DT.Money(v.p), v.l and " (limited stock)" or "") or nil
end

local function AgeText(seconds)
	local color = seconds < 3600 and "ff40ff40" or seconds < 86400 and "ffffd100" or "ffff4040"
	return "|c" .. color .. L.Ago(seconds) .. "|r"
end

-- dearer than the week's median is red, cheaper green
local function TrendText(trend)
	if not trend then return "" end
	local pct = math.floor(trend * 100 + 0.5)
	if pct == 0 then return "|cff888888=|r" end
	return ("|c%s%+d%%|r"):format(pct > 0 and "ffff4040" or "ff40ff40", pct)
end

local function ItemText(id, item)
	local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
	if name and not item.n then M:Resolve(id) end
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
	return (M.db.favs[id] and "|cffffd100*|r " or "") .. (icon and ("|T%s:14|t "):format(icon) or "")
		.. color .. (name or item.n or ("item " .. id)) .. "|r"
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local list, sections, offset, dirty = {}, {}, 0, true
local sideOffset, SIDE_H = 0, 20 -- categories scrolled past; height of one
local panel, area, side, search, countText, scanButton, listBar, atButton, atText
local houseButtons = {}

-- The filters, as the auction house has them. An item the game has not loaded yet cannot be judged and is left out.
-- Usable by this character, from what is known at once and stays the same: the item's kind and required level,
-- what the character has trained, and its professions. (The red lines of the item's tooltip would say more,
-- but the game fetches tooltips bit by bit: the answer kept changing while it did.)
--   weapons and armour: the proficiency is a spell the character knows ("Staves", "Cloth"). Where the game
--     does not tell (not even Cloth is known), what the class can learn, by Classic's rules;
--   recipes: the character has that profession.
--   a skill the item asks for ("Requires Engineering (150)": goggles, recipes, bombs): the character has it,
--     that high. That line is only on the tooltip. It never changes, so it is read once per item and kept
--     with its price (item.rq); see Requirement below.
--   recipes, pets, mounts the character already knows: out (AlreadyKnown below).
-- ponytail: not items for one class or race, nor reputation. Only the tooltip's red knows those.
local WEAPON_SPELL = { [0] = 196, [1] = 197, [2] = 264, [3] = 266, [4] = 198, [5] = 199, [6] = 200, [7] = 201, [8] = 202,
	[10] = 227, [13] = 15590, [15] = 1180, [16] = 2567, [18] = 5011, [19] = 5009 }
local ARMOR_SPELL = { [1] = 9078, [2] = 9077, [3] = 8737, [4] = 750, [6] = 9116 }
local WEAR = { -- { below 40, from 40, shield / relic kinds }
	WARRIOR = { 3, 4, { [6] = true } }, PALADIN = { 3, 4, { [6] = true, [7] = true } },
	HUNTER = { 2, 3, {} }, SHAMAN = { 2, 3, { [6] = true, [9] = true } },
	ROGUE = { 2, 2, {} }, DRUID = { 2, 2, { [8] = true } },
	MAGE = { 1, 1, {} }, PRIEST = { 1, 1, {} }, WARLOCK = { 1, 1, {} },
}
local function Kinds(list)
	local set = {}
	for _, kind in ipairs(list) do set[kind] = true end
	return set
end
-- 0 axe, 1 two-handed axe, 2 bow, 3 gun, 4 mace, 5 two-handed mace, 6 polearm, 7 sword, 8 two-handed sword,
-- 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand (14 miscellaneous, 20 fishing pole: anyone)
local WIELD = {
	WARRIOR = Kinds { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = Kinds { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = Kinds { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = Kinds { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = Kinds { 4, 10, 15, 19 }, SHAMAN = Kinds { 0, 1, 4, 5, 10, 13, 15 }, MAGE = Kinds { 7, 10, 15, 19 },
	WARLOCK = Kinds { 7, 10, 15, 19 }, DRUID = Kinds { 4, 5, 10, 13, 15 },
}
local WEAPON_CLASS, ARMOR_CLASS, RECIPE_CLASS = 2, 4, 9

local function Knows(spell)
	return (IsPlayerSpell and IsPlayerSpell(spell)) or (IsSpellKnown and IsSpellKnown(spell)) or false
end

-- the character, read once per pass over the list: { me = class, level, trained (the game tells proficiencies),
-- profs = { [profession name] = true } or nil where the game does not list them }
local function Character(myLevel)
	local _, me = UnitClass("player")
	local profs -- [skill name] = how high
	if GetNumSkillLines and GetSkillLineInfo then -- (every skill: riding too)
		profs = {}
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank = GetSkillLineInfo(i)
			if name and not header then profs[name] = rank or 0 end
		end
	elseif GetProfessions and GetProfessionInfo then
		-- ponytail: professions only. An item asking for another skill (riding) counts as not usable here.
		profs = {}
		local mine = { GetProfessions() } -- (two main ones, then the secondary ones; any may be nil)
		for i = 1, 6 do
			if mine[i] then
				local name, _, rank = GetProfessionInfo(mine[i])
				if name then profs[name] = rank or 0 end
			end
		end
	end
	return { me = me, level = myLevel, trained = Knows(ARMOR_SPELL[1]), profs = profs }
end

local function MayUse(class, sub, who)
	sub = sub or 0
	if class == WEAPON_CLASS then
		if sub == 14 or sub == 20 then return true end
		if who.trained and WEAPON_SPELL[sub] then return Knows(WEAPON_SPELL[sub]) end
		return not WIELD[who.me] or WIELD[who.me][sub] or false
	elseif class == ARMOR_CLASS and sub > 0 then -- (0: rings, cloaks and the like)
		if who.trained and ARMOR_SPELL[sub] then return Knows(ARMOR_SPELL[sub]) end
		local wear = WEAR[who.me]
		if not wear then return true end
		if sub <= 4 then return sub <= wear[who.level >= 40 and 2 or 1] end
		return wear[3][sub] or false
	elseif class == RECIPE_CLASS and sub > 0 and who.profs then -- (0: books)
		local get = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
		local name = get and get(class, sub)
		if name then return who.profs[name] or false end
	end
	return true
end

-- The skill an item asks for: item.rq = "Engineering:150", or "" for none; nil while not known.
-- Read from the tooltip's text, once, and kept. The game fetches tooltips bit by bit, so "none" is only
-- believed when a second look, a pass later, finds the tooltip the same length; a skill line found is believed
-- at once. Until it is known the item counts as usable. A few hundred tooltips per pass, not thousands: the
-- rest wait for the next pass (which comes by itself).
local SKILL_LINE = (ITEM_MIN_SKILL or "Requires %s (%d)"):gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
SKILL_LINE = "^" .. SKILL_LINE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
local PER_PASS = 300
local budget, unsettled, lengths = 0, false, {}
local looks = {} -- [itemID] = times its tooltip was looked at without an answer (after a few it is left at "none")
local function Requirement(id, item)
	if item.rq then return item.rq end
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return "" end
	looks[id] = (looks[id] or 0) + 1
	if looks[id] > 5 then return "" end -- (a tooltip that never comes whole: not asked after for ever)
	unsettled = true
	if budget <= 0 then return nil end
	budget = budget - 1
	local data = C_TooltipInfo.GetItemByID(id)
	local lines = data and data.lines
	if not lines or #lines == 0 then return nil end
	for _, line in ipairs(lines) do
		local text = line.leftText or ""
		if RETRIEVING_ITEM_INFO and text == RETRIEVING_ITEM_INFO then return nil end
		local skill, rank = text:match(SKILL_LINE)
		if skill then
			item.rq = skill .. ":" .. rank
			return item.rq
		end
	end
	if lengths[id] == #lines then
		item.rq, lengths[id] = "", nil
		return ""
	end
	lengths[id] = #lines
	return nil
end

-- "Already known" on a recipe (or a pet, a mount): nothing more to use it for. That is about this character,
-- so it is not kept with the price: read once per session, the same careful way, and again after a recipe
-- is learned.
local RECIPE, MISC = 9, 15
local known, knownLength, knownLooks = {}, {}, {} -- [itemID] = true / false, settled; = lines at the last look; = looks
local function AlreadyKnown(id)
	local k = known[id]
	if k ~= nil then return k end
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
	knownLooks[id] = (knownLooks[id] or 0) + 1
	if knownLooks[id] > 5 then return false end -- (as above)
	unsettled = true
	if budget <= 0 then return false end
	budget = budget - 1
	local data = C_TooltipInfo.GetItemByID(id)
	local lines = data and data.lines
	if not lines or #lines == 0 then return false end
	for _, line in ipairs(lines) do
		local text = line.leftText or ""
		if RETRIEVING_ITEM_INFO and text == RETRIEVING_ITEM_INFO then return false end
		if text == (ITEM_SPELL_KNOWN or "Already known") then
			known[id] = true
			return true
		end
	end
	if knownLength[id] == #lines then known[id] = false end
	knownLength[id] = #lines
	return false
end
DT:On("NEW_RECIPE_LEARNED", function() known, knownLength, knownLooks, dirty = {}, {}, {}, true end)

-- What a filter needs of an item (required level, quality) is kept with its price once the game has told it:
-- from then on nothing is asked of the game, and the answer is the same every time.
-- An item the game has not loaded cannot be judged yet: it is asked for, and the list drawn again a little
-- later. (Three times at most: the game drops requests when thousands come at once, and some never come.)
local asked, waiting, redraw = {}, {}, false
local function Later() -- one more pass over the list, a little later, for all that changes until then
	if redraw then return end
	redraw = true
	C_Timer.After(1.5, function() redraw, dirty = false, true end)
end
DT:On("GET_ITEM_INFO_RECEIVED", function(id)
	if not waiting[id] then return end
	waiting[id] = nil
	Later()
end)

local function Passes(id, item, myLevel, who)
	local lv, ql = item.lv, item.ql
	if not (lv and ql and item.c) then
		local name, _, quality, _, minLevel, _, _, _, _, _, _, class, sub = C_Item.GetItemInfo(id)
		if not name then
			if not waiting[id] and (asked[id] or 0) < 3 then
				asked[id], waiting[id] = (asked[id] or 0) + 1, true
				C_Item.RequestLoadItemDataByID(id)
			end
			return false
		end
		lv, ql = minLevel or 0, quality or 0
		item.lv, item.ql, item.c, item.s = lv, ql, item.c or class, item.s or sub or 0
	end
	if V.minLevel and lv < V.minLevel then return false end
	if V.maxLevel and lv > V.maxLevel then return false end
	if V.qualities and not V.qualities[math.min(ql, 4)] then return false end -- (the Epic box: epic and better)
	if who then
		if lv > myLevel or not MayUse(item.c, item.s, who) then return false end
		local rq = Requirement(id, item)
		if rq and rq ~= "" and who.profs then
			local skill, rank = rq:match("^(.*):(%d+)$")
			if (who.profs[skill] or -1) < tonumber(rank) then return false end
		end
		if (item.c == RECIPE or item.c == MISC) and AlreadyKnown(id) then return false end
	end
	return true
end
local rows, headers, sideButtons, detail = {}, {}, {}, {}

-- the items that match the search and the category, sorted; and the categories there are to pick from
local function Filter(now)
	local q = (search:GetText() or ""):lower()
	local favs, classes, groups = M.db.favs, {}, {} -- groups of the class picked: [group] = { [leaf] = true }
	local filtering = V.minLevel or V.maxLevel or V.qualities or V.usable
	local myLevel = UnitLevel and UnitLevel("player") or 0
	local who = V.usable and Character(myLevel) or nil
	budget, unsettled = PER_PASS, false
	list = {}
	for id, item in pairs(M.items) do
		if item.t then
			local group, leaf
			if item.c then
				classes[item.c] = true
				if item.c == V.class then
					group, leaf = Place(item)
					groups[group] = groups[group] or {}
					if leaf ~= nil then groups[group][leaf] = true end
				end
			end
			if (not V.fav or favs[id]) and (not V.class or item.c == V.class)
				and (V.group == nil or group == V.group) and (V.leaf == nil or leaf == V.leaf)
				and (q == "" or (item.n or ""):lower():find(q, 1, true)) and (not filtering or Passes(id, item, myLevel, who))
				and (not V.vendorOnly or M.db.vendors[id]) then
				list[#list + 1] = id
			end
		end
	end
	if unsettled then Later() end
	local key, vals = SORT[V.sort], {}
	for _, id in ipairs(list) do vals[id] = key(id, M.items[id], now) end
	table.sort(list, function(a, b)
		local x, y = vals[a], vals[b]
		if x ~= y then
			if V.desc then return x > y end
			return x < y
		end
		return a < b
	end)

	sections = { { label = "All items" }, { label = "Favourites", fav = true } }
	local function Add(class)
		if not classes[class] then return end
		classes[class] = nil
		sections[#sections + 1] = { label = ClassName(class), class = class }
		if class ~= V.class then return end
		local order = Ordered(groups, class == WEAPON and WEAPON_GROUPS or class == ARMOR and ARMOR_GROUPS or nil)
		-- (elsewhere, one sub-category is no choice)
		if #order < 2 and class ~= WEAPON and class ~= ARMOR then return end
		for _, group in ipairs(order) do
			sections[#sections + 1] = { label = GroupLabel(class, group), class = class, group = group, depth = 1 }
			for _, leaf in ipairs(V.group == group and Ordered(groups[group], nil, SLOT_RANK) or {}) do
				sections[#sections + 1] = { label = LeafLabel(class, leaf), class = class, group = group, leaf = leaf, depth = 2 }
			end
		end
	end
	for _, class in ipairs(CLASS_ORDER) do Add(class) end
	local rest = {}
	for class in pairs(classes) do rest[#rest + 1] = class end
	table.sort(rest)
	for _, class in ipairs(rest) do Add(class) end
end

local function DrawDetail(now)
	local id = V.selected
	local item = id and M.items[id]
	-- (no item picked: no history box, the table has the room)
	detail.box:SetShown(item ~= nil)
	if not item then return end
	local history, byDay, top, low, high, total = L.History(item), {}, 1, nil, nil, 0
	for _, h in ipairs(history) do
		byDay[h.day] = h
		if h.median > top then top = h.median end
		if not low or h.min < low then low = h.min end
		if not high or h.median > high then high = h.median end
		total = total + h.n
	end
	local today = math.floor(now / L.DAY)
	for i, bar in ipairs(detail.bars) do
		local day = today - DAYS + i
		local h = byDay[day]
		bar.day, bar.h = day, h
		bar.fill:SetHeight(h and math.max(2, 64 * h.median / top) or 1)
		bar.fill:SetColorTexture(h and 0.78 or 0.3, h and 0.68 or 0.3, h and 0.37 or 0.3, 1)
		bar:Show()
	end
	local median = L.Median(item, 7, now)
	local lines = {
		ItemText(id, item),
		("Last %s, %s%s, seen by %s"):format(DT.Money(item.p), AgeText(now - item.t),
			item.q > 0 and (", %d listed"):format(item.q) or "", item.o ~= "" and item.o or "the guild"),
		("7-day median %s    %d-day low %s, high %s"):format(median and DT.Money(median) or "-", DAYS,
			low and DT.Money(low) or "-", high and DT.Money(high) or "-"),
		("%d observations on %d days"):format(total, #history) .. (VendorText(id) and ("    |cffffd100" .. VendorText(id) .. "|r") or ""),
	}
	for i = #history, math.max(1, #history - 3), -1 do
		local h = history[i]
		lines[#lines + 1] = ("|cff888888%s|r   min %s   median %s   |cff888888(%d)|r"):format(
			date("%d %b", h.day * L.DAY + 43200), DT.Money(h.min), DT.Money(h.median), h.n)
	end
	detail.text:SetText(table.concat(lines, "\n"))
	detail.fav:SetText(M.db.favs[id] and "Unfavourite" or "Favourite")
	detail.fav:Show()
	detail.ah:SetEnabled(M.ahOpen and true or false)
	detail.ah:Show()
end

local function SideButton(i)
	local b = CreateFrame("Button", nil, side)
	b:SetHeight(SIDE_H)
	b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * SIDE_H)
	b:SetPoint("RIGHT", -11, 0)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(1, 0.82, 0, 0.18)
	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("LEFT", 6, 0)
	b.text:SetPoint("RIGHT", -4, 0)
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	b:SetScript("OnClick", function(self)
		local e = self.entry
		if not e then return end
		-- what is picked, clicked again, goes back up one step
		if e.leaf ~= nil and V.group == e.group and V.leaf == e.leaf then
			V.leaf = nil
		elseif e.group ~= nil and e.leaf == nil and V.class == e.class and V.group == e.group and V.leaf == nil then
			V.group = nil
		else
			V.fav, V.class, V.group, V.leaf = e.fav or false, e.class, e.group, e.leaf
		end
		offset = 0
		V:Refresh()
	end)
	return b
end

local function Row(i)
	local row = CreateFrame("Button", nil, area)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -10, 0)
	row.sel = row:CreateTexture(nil, "BACKGROUND")
	row.sel:SetAllPoints()
	row.sel:SetColorTexture(1, 0.82, 0, 0.15)
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.06)
	row.cells = {}
	for _, col in ipairs(COLS) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
		fs:SetWordWrap(false)
		row.cells[col.key] = fs
	end
	row:SetScript("OnClick", function(self)
		V.selected = V.selected ~= self.id and self.id or nil
		V:Refresh(true)
	end)
	row:SetScript("OnEnter", function(self)
		if not self.id then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. self.id)
		if VendorText(self.id) then GameTooltip:AddLine(VendorText(self.id), 1, 0.82, 0, true) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

-- fits the table to the panel: as many rows as there is height for (all of it, less the history box while an
-- item is picked), the Item column as wide as is left
local function Layout()
	local detailH = V.selected and DETAIL_H or 0
	area:ClearAllPoints()
	area:SetPoint("TOPLEFT", SIDE_W + 8, -TOP_H)
	area:SetPoint("BOTTOMRIGHT", 0, detailH)
	local width = math.max(panel:GetWidth() - SIDE_W - 8 - 10, 0) -- (10: the scroll bar)
	local height = panel:GetHeight() - TOP_H - detailH
	local fixed = 0
	for i = 2, #COLS do fixed = fixed + COLS[i].width end
	COLS[1].width = math.max(80, width - fixed)
	local x = 0
	for i, col in ipairs(COLS) do
		col.x = x
		x = x + col.width
		local h = headers[i]
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", col.x, 0)
		h:SetSize(col.width, ROW_H)
	end
	V.rows = math.max(1, math.floor((height - ROW_H) / ROW_H))
	for i = 1, math.max(V.rows, #rows) do
		rows[i] = rows[i] or Row(i)
		for _, col in ipairs(COLS) do
			local fs = rows[i].cells[col.key]
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", col.x, 0)
			fs:SetWidth(col.width - 4)
		end
	end
end

-- same = the list itself is as it was (a scroll, a row picked): the thousands of items are not gone through
-- and sorted again
function V:Refresh(same)
	if not panel then return end -- the tab was never opened
	if same ~= true then dirty = false end
	local now = DT.Now()
	local picked = V.selected and M.items[V.selected]
	if not (picked and picked.t) then V.selected = nil end
	Layout()
	if same ~= true then Filter(now) end
	local over = math.max(0, #list - V.rows)
	offset = math.max(0, math.min(offset, over))
	listBar:SetShown(over > 0)
	if over > 0 then
		listBar.thumb:SetSize(8, math.max(16, V.rows * ROW_H * V.rows / #list))
		listBar:SetMinMaxValues(0, over)
		listBar:SetValue(offset)
	end
	for i, row in ipairs(rows) do
		local id = i <= V.rows and list[i + offset] or nil
		local item = id and M.items[id]
		row.id = id
		row:SetShown(item ~= nil)
		if item then
			local median = L.Median(item, 7, now)
			local sell = Vendor(id)
			local cells = row.cells
			local _, _, _, ilvl, minLevel = C_Item.GetItemInfo(id)
			cells.lvl:SetText(minLevel and minLevel > 1 and tostring(minLevel) or "")
			cells.ilvl:SetText(ilvl and ilvl > 1 and tostring(ilvl) or "")
			cells.name:SetText(ItemText(id, item))
			cells.p:SetText(DT.Money(item.p))
			cells.t:SetText(AgeText(now - item.t))
			cells.q:SetText(item.q > 0 and tostring(item.q) or "")
			cells.med:SetText(median and DT.Money(median) or "")
			cells.trend:SetText(TrendText(L.Trend(item, now)))
			cells.vendor:SetText(sell > 0 and DT.Money(sell) or "")
			-- gold where the auction price is above what the vendor asks; * = limited stock
			local sold = M.db.vendors[id]
			cells.vbuy:SetText(sold and ((item.p > sold.p and "|cffffd100" or "") .. DT.Money(sold.p) .. (sold.l and "*" or "")
				.. (item.p > sold.p and "|r" or "")) or "")
			cells.o:SetText(item.o ~= "" and item.o or "guild")
			row.sel:SetShown(id == V.selected)
		end
	end
	for _, h in ipairs(headers) do
		h.text:SetText(h.col.title .. (h.col.key == V.sort and (V.desc and " v" or " ^") or ""))
	end
	-- the categories scroll when they do not fit: mouse wheel, or drag the bar on their right
	local fit = math.max(1, math.floor((panel:GetHeight() - 6) / SIDE_H))
	sideOffset = math.max(0, math.min(sideOffset, #sections - fit))
	side.bar:SetShown(#sections > fit)
	if #sections > fit then
		side.bar.thumb:SetSize(8, math.max(16, fit * SIDE_H * fit / #sections))
		side.bar:SetMinMaxValues(0, #sections - fit)
		side.bar:SetValue(sideOffset)
	end
	for i = 1, math.max(fit, #sideButtons) do
		local e = i <= fit and sections[i + sideOffset] or nil
		local b = sideButtons[i]
		if e and not b then
			b = SideButton(i)
			sideButtons[i] = b
		end
		if b then
			b.entry = e
			b:SetShown(e ~= nil)
			if e then
				b.text:SetText(("    "):rep(e.depth or 0) .. e.label)
				local on
				if e.leaf ~= nil then
					on = V.class == e.class and V.group == e.group and V.leaf == e.leaf
				elseif e.group ~= nil then
					on = V.class == e.class and V.group == e.group and V.leaf == nil
				elseif e.class then
					on = V.class == e.class and V.group == nil
				else
					on = not V.class and (e.fav or false) == (V.fav or false)
				end
				b.sel:SetShown(on)
			end
		end
	end
	countText:SetText((M.scanStatus and ("|cff888888" .. M.scanStatus .. "|r  ") or "")
		.. (#list == 0 and (next(M.items) and "|cff888888Nothing matches.|r"
		or "|cff888888No prices yet. They are recorded as you (or the guild) look at the auction house.|r")
		or ("%d items%s"):format(#list, V.selected and "" or "  |cff888888click one for its history|r")))
	scanButton:SetEnabled(M.ahOpen and not M.scanning or false)
	-- the house shown is the lit one of the pair
	for _, b in ipairs(houseButtons) do
		local on = b.house == M.view
		b:SetText((on and "|cffffd100" or "|cff999999") .. M.HOUSE_NAMES[b.house] .. "|r")
		if on then b:LockHighlight() else b:UnlockHighlight() end
	end
	atButton:SetShown(M.at ~= nil)
	atText:SetText(M.at and ("You are at: |cffffd100" .. M.HOUSE_NAMES[M.at] .. "|r") or "")
	DrawDetail(now)
end

-- A search for exactly this item, so its price here is fresh. The player's click is what sends it.
local function CheckPrice(id)
	if not (M.ahOpen and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then return end
	C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(id), {}, false)
end

local function Build(parent)
	panel = parent
	V.panel = panel

	-- left: categories, as the auction house has them
	side = CreateFrame("Frame", nil, panel)
	side:SetPoint("TOPLEFT", 0, -2)
	side:SetPoint("BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDE_W)
	local shade = side:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, 0.04)
	local bar = CreateFrame("Slider", nil, side)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(8)
	bar:SetPoint("TOPRIGHT", -1, -2)
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
		if value == sideOffset then return end -- (Refresh sets the bar too)
		sideOffset = value
		V:Refresh(true)
	end)
	side.bar = bar
	side:EnableMouseWheel(true)
	side:SetScript("OnMouseWheel", function(_, delta)
		sideOffset = sideOffset - delta * 2
		V:Refresh(true)
	end)

	-- top: the search box
	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(190, 20)
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
	-- the player's click is what starts it; only at the auction house
	scanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	scanButton:SetSize(140, 22)
	scanButton:SetPoint("TOPRIGHT", -2, -2)
	scanButton:SetText("Scan Auction House")
	StaticPopupDialogs.DAWNTOOLS_SCAN = {
		text = "Scan the auction house.\n\n|cffffd100Quick|r: the lowest price of every item, about half a minute. For gear that price may be a bid.\n\n"
			.. "|cffffd100Full|r: every auction, exact buyouts. Once per 15 minutes; the game may stand still for a few seconds.\n\n%s",
		button1 = "Quick", button2 = CANCEL or "Cancel", button3 = "Full",
		OnAccept = function()
			M:Scan()
			V:Refresh()
		end,
		OnAlt = function()
			M:Scan(true)
			V:Refresh()
		end,
		-- Full is greyed out while the game would not take one
		OnShow = function(self)
			local full = self.button3 or (self.GetButton3 and self:GetButton3())
			if full then full:SetEnabled(M:FullWait() == 0 and C_AuctionHouse.ReplicateItems ~= nil) end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	scanButton:SetScript("OnClick", function()
		local wait = M:FullWait()
		StaticPopup_Show("DAWNTOOLS_SCAN", wait > 0 and ("|cffff8080Full: possible again in %d min.|r"):format(math.ceil(wait / 60)) or "|cff80ff80Full: ready.|r")
	end)
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", search, "RIGHT", 12, 0)
	local function Tip(button, ...)
		local lines = { ... }
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			for i, line in ipairs(lines) do GameTooltip:AddLine(line, i > 1 and 1 or nil, i > 1 and 1 or nil, i > 1 and 1 or nil, true) end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	-- which auction house's prices are shown: one button each, the lit one is shown
	local anchor = scanButton
	for i, house in ipairs({ "X", M.faction }) do
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(house == "X" and 78 or 66, 22)
		b:SetPoint("RIGHT", anchor, "LEFT", i == 1 and -8 or 0, 0)
		b.house = house
		b:SetScript("OnClick", function()
			M:SetView(house)
			offset = 0
			V:Refresh()
		end)
		Tip(b, M.HOUSE_NAMES[house] .. " auction house",
			house == "X" and "Show the prices of the cross-faction auction house." or "Show the prices of your faction's own auction house.",
			"The two have their own prices. At an auctioneer the right one is picked by itself.")
		houseButtons[#houseButtons + 1] = b
		anchor = b
	end
	-- at an auctioneer: which house DawnTools takes it for, and a way to put that right
	atButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	atButton:SetSize(96, 20)
	atButton:SetPoint("TOPRIGHT", -2, -31)
	atButton:SetText("Wrong house?")
	atButton:SetScript("OnClick", function()
		M:SetAt(M.at == "X" and M.faction or "X")
		V:Refresh()
	end)
	Tip(atButton, "Not the house you are at?",
		"Prices you see at this auctioneer are filed under the house named beside this button. If that is the wrong one, click: it switches to the other and remembers that for this auctioneer.")
	atText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	atText:SetPoint("RIGHT", atButton, "LEFT", -6, 0)
	countText:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
	countText:SetJustifyH("RIGHT")
	countText:SetWordWrap(false)

	-- the filter line: required level from - to, quality at least, usable by this character
	local levelText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	levelText:SetPoint("TOPLEFT", SIDE_W + 12, -34)
	levelText:SetText("Level")
	local function LevelBox(key, anchor, x)
		local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
		eb:SetSize(30, 18)
		eb:SetPoint("LEFT", anchor, "RIGHT", x, 0)
		eb:SetAutoFocus(false)
		eb:SetScript("OnTextChanged", function(self)
			V[key] = tonumber(self:GetText())
			offset, dirty = 0, true
		end)
		eb:SetScript("OnEnterPressed", eb.ClearFocus)
		eb:SetScript("OnEscapePressed", function(self)
			self:SetText("")
			self:ClearFocus()
		end)
		return eb
	end
	local minBox = LevelBox("minLevel", levelText, 10)
	local dash = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dash:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
	dash:SetText("-")
	local maxBox = LevelBox("maxLevel", dash, 9)
	-- one box per quality; none ticked = all of them
	local last, lastWidth = maxBox, 10
	for quality = 0, 4 do
		local short = ({ [0] = "Poor", "Com", "Unc", "Rare", "Epic" })[quality]
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetSize(20, 20)
		cb:SetPoint("LEFT", last, "RIGHT", lastWidth, 0)
		cb.quality = quality
		local hex = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
		local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("LEFT", cb, "RIGHT", 0, 0)
		text:SetText(hex .. short .. "|r")
		cb:SetScript("OnClick", function(self)
			local set = V.qualities or {}
			set[quality] = self:GetChecked() and true or nil
			V.qualities = next(set) and set or nil
			offset = 0
			V:Refresh()
		end)
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(hex .. (_G["ITEM_QUALITY" .. quality .. "_DESC"] or short) .. (quality == 4 and " and better" or "") .. "|r")
			GameTooltip:AddLine("Tick the qualities to list. None ticked: all of them.", 1, 1, 1)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		last, lastWidth = cb, 32
	end
	local usable = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	usable:SetSize(22, 22)
	usable:SetPoint("LEFT", last, "RIGHT", 38, 0)
	local usableText = usable:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	usableText:SetPoint("LEFT", usable, "RIGHT", 2, 0)
	usableText:SetText("Usable")
	usable:SetScript("OnClick", function(self)
		V.usable = self:GetChecked() and true or nil
		offset = 0
		V:Refresh()
	end)
	-- only what a vendor is known to sell
	local vendorOnly = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	vendorOnly:SetSize(22, 22)
	vendorOnly:SetPoint("LEFT", usable, "RIGHT", 52, 0)
	local vendorText = vendorOnly:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vendorText:SetPoint("LEFT", vendorOnly, "RIGHT", 2, 0)
	vendorText:SetText("Vendor sells")
	vendorOnly:SetScript("OnClick", function(self)
		V.vendorOnly = self:GetChecked() and true or nil
		offset = 0
		V:Refresh()
	end)
	Tip(vendorOnly, "Sold by a vendor",
		"Lists only what a vendor is known to sell. Sort by \"Vendor sells\": gold prices are below the auction price, so worth buying to resell, or worth telling someone to buy there instead.",
		"A vendor is known once you have opened their shop with DawnTools running.")

	-- middle: the table. Column headers: click to sort, again to turn it round
	area = CreateFrame("Frame", nil, panel) -- (Layout places it)
	listBar = CreateFrame("Slider", nil, area)
	listBar:SetOrientation("VERTICAL")
	listBar:SetWidth(8)
	listBar:SetPoint("TOPRIGHT", -1, -ROW_H)
	listBar:SetPoint("BOTTOMRIGHT", -1, 2)
	listBar:SetValueStep(1)
	listBar:SetObeyStepOnDrag(true)
	local listTrack = listBar:CreateTexture(nil, "BACKGROUND")
	listTrack:SetAllPoints()
	listTrack:SetColorTexture(0, 0, 0, 0.3)
	listBar.thumb = listBar:CreateTexture(nil, "OVERLAY")
	listBar.thumb:SetColorTexture(0.78, 0.68, 0.37, 0.9)
	listBar:SetThumbTexture(listBar.thumb)
	listBar:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value + 0.5)
		if value == offset then return end -- (Refresh sets the bar too)
		offset = value
		V:Refresh(true)
	end)
	for i, col in ipairs(COLS) do
		local h = CreateFrame("Button", nil, area)
		h.col = col
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetPoint(col.right and "RIGHT" or "LEFT", col.right and -4 or 0, 0)
		h:SetScript("OnClick", function()
			if V.sort == col.key then
				V.desc = not V.desc
			else
				V.sort, V.desc = col.key, col.key ~= "name" and col.key ~= "o"
			end
			V:Refresh()
		end)
		headers[i] = h
	end
	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		V:Refresh(true)
	end)

	-- bottom: the selected item. A bar per day (height = that day's median), then the figures
	local box = CreateFrame("Frame", nil, panel)
	box:SetPoint("BOTTOMLEFT", SIDE_W + 8, 0)
	box:SetPoint("BOTTOMRIGHT", 0, 0)
	box:SetHeight(DETAIL_H - 6)
	detail.box = box
	detail.bars = {}
	for i = 1, DAYS do
		local bar = CreateFrame("Frame", nil, box)
		bar:SetSize(14, 66)
		bar:SetPoint("TOPLEFT", 2 + (i - 1) * 16, -4)
		bar:EnableMouse(true)
		bar.fill = bar:CreateTexture(nil, "ARTWORK")
		bar.fill:SetPoint("BOTTOMLEFT")
		bar.fill:SetPoint("BOTTOMRIGHT")
		bar:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(date("%A %d %b", self.day * L.DAY + 43200))
			local h = self.h
			if h then
				GameTooltip:AddLine(("min %s, median %s"):format(DT.Money(h.min), DT.Money(h.median)), 1, 1, 1)
				GameTooltip:AddLine(("%d observations, up to %d listed"):format(h.n, h.q), 1, 1, 1)
			else
				GameTooltip:AddLine("not seen", 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
		end)
		bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
		detail.bars[i] = bar
	end
	detail.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	detail.text:SetPoint("TOPLEFT", 240, 0)
	detail.text:SetPoint("RIGHT", -130, 0)
	detail.text:SetJustifyH("LEFT")
	detail.text:SetWordWrap(false)

	local function DetailButton(text, y, click)
		local b = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
		b:SetSize(120, 22)
		b:SetPoint("TOPRIGHT", -4, y)
		b:SetText(text)
		b:SetScript("OnClick", function()
			if V.selected then click(V.selected) end
			V:Refresh()
		end)
		return b
	end
	detail.fav = DetailButton("Favourite", 0, function(id) M.db.favs[id] = not M.db.favs[id] or nil end)
	detail.ah = DetailButton("Check price at AH", -26, CheckPrice)
	detail.link = DetailButton("Link", -52, function(id) DT:ShowLink(M.items[id] and M.items[id].n or ("item " .. id), DT:ItemLink(id)) end)

	Layout()
	panel:SetScript("OnSizeChanged", function()
		Layout()
		V:Refresh()
	end)
	local nextUpdate = 0
	panel:SetScript("OnUpdate", function()
		if GetTime() < nextUpdate then return end
		nextUpdate = GetTime() + 0.2
		if dirty then V:Refresh() end
	end)

	-- Shift-click an item anywhere while the search box has the cursor: its name goes into the box
	local function OnLink(link)
		local name = search:HasFocus() and type(link) == "string" and link:match("%[(.-)%]")
		if name then search:SetText(name) end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", OnLink)
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", OnLink)
	end
end

---------------------------------------------------------------------------
-- Item tooltips
---------------------------------------------------------------------------

-- n: for so many of it (Shift over a stack)
function V.TooltipText(id, n)
	local item = M.items[id]
	if not (item and item.t) then return nil end
	n = n and n > 1 and n or 1
	local now = DT.Now()
	local median = L.Median(item, 7, now)
	return ("%s%s (%s)%s"):format(DT.Money(item.p * n), n > 1 and (" x" .. n) or "", L.Ago(now - item.t), median and (" · 7d median " .. DT.Money(median * n)) or "")
end

local function OnTooltipItem(tip, data)
	if not M.db.settings.tooltip or (tip ~= GameTooltip and tip ~= ItemRefTooltip) then return end
	local id = data and data.id
	if not id and tip.GetItem then
		local _, link = tip:GetItem()
		id = link and tonumber(link:match("item:(%d+)"))
	end
	-- Shift held over a stack (a bag or bank button, which knows how many it holds): the price of all of it
	-- ponytail: only where the button under the tooltip has a count; elsewhere the price of one.
	local n = 1
	if IsShiftKeyDown and IsShiftKeyDown() and tip.GetOwner then
		local ok, owner = pcall(tip.GetOwner, tip)
		local count = ok and type(owner) == "table" and owner.count
		if type(count) == "number" and count > 1 and not (issecretvalue and issecretvalue(count)) then n = count end
	end
	local text = id and V.TooltipText(id, n)
	if text then tip:AddDoubleLine("Guild AH", text, 0.78, 0.68, 0.37, 1, 1, 1) end
	local sold = id and M.db.vendors[id]
	if sold then tip:AddDoubleLine("Vendor", ("%s%s at %s, %s%s"):format(DT.Money(sold.p * n), n > 1 and (" x" .. n) or "", sold.v, sold.z, sold.l and " (limited)" or ""), 0.78, 0.68, 0.37, 1, 1, 1) end
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

-- for the Items tab, which is laid out the same way: the category tree, and who may use what
V.cat = { Place = Place, GroupLabel = GroupLabel, LeafLabel = LeafLabel, Ordered = Ordered, ClassName = ClassName, CLASS_ORDER = CLASS_ORDER,
	WEAPON = WEAPON, ARMOR = ARMOR, WEAPON_GROUPS = WEAPON_GROUPS, ARMOR_GROUPS = ARMOR_GROUPS, SLOT_RANK = SLOT_RANK }
V.MayUse, V.Character = MayUse, Character

DT:RegisterModule("market", {
	profile = { "view" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "Market",
	version = 1,
	defaults = {
		-- share: not set until the player has answered the question
		name = true,
		auctionator = true,
		tooltip = true,
	},
	settings = {
		{ key = "share", label = "Share prices with the guild (and receive theirs)" },
		{ key = "name", label = "Show my name as the observer" },
		{ key = "auctionator", label = "Use Auctionator's price history (for me only)" },
		{ key = "tooltip", label = "Price line on item tooltips" },
	},
	slash = "/dtmarket",
	tab = {
		id = "market", title = "Market", defaultOrder = 10, create = Build,
		onShow = function() V:Refresh() end,
	},
	onEnable = function(mod)
		M:Enable(mod)
		M.Sync:Enable()
		DT:On("DT_MARKET_UPDATE", function() dirty = true end)
		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipItem)
		elseif GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetItem") then
			GameTooltip:HookScript("OnTooltipSetItem", OnTooltipItem)
			ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipItem)
		end
	end,
	hello = function() return M.Sync:Hello() end,
	onHello = function(_, sender, summary) M.Sync:OnHello(sender, summary) end,
	onMessage = function(_, kind, payload, sender) M.Sync:OnMessage(kind, payload, sender) end,
	status = function() return M.Sync:Status() end,
	selfTest = function(_, Try)
		local id = next(M.items)
		Try("market list", function() V:Refresh() end)
		if id then
			Try("market detail", function()
				local was = V.selected
				V.selected = id
				V:Refresh()
				V.selected = was
				V:Refresh()
			end)
			Try("market tooltip", function() assert(V.TooltipText(id)) end)
			Try("market api", function() assert(DawnMarket.API.GetLatest(id) and DawnMarket.API.GetHistory(id)) end)
		end
	end,
})
