-- DawnFish
-- Fish as a way to make gold: what each one sells for raw and cooked, where it is caught, and what a cast is
-- worth in each fishing spot at today's auction prices. The module sends and receives nothing itself: what it counts
-- of casts is rows of the game database (below), which the guild shares with the rest of it where the player agreed.
--
-- Three sources, in rising order of trust:
--   1. the lists below: old-world fish, their cooking recipes and waters (a starting point; Forever has waters
--      and recipes of its own that are not in them)
--   2. the Cooking window: every recipe this account knows is recorded when it is opened
--   3. casts: every fishing catch is counted per spot, mine and (once the game database is shared) the guild's,
--      which is what "per cast" is really made from

local _, DT = ...
local F = {}
DT.Fish = F
local DB, DBL = DT.DB, DT.DBLogic

-- db: recipes[output itemID] = { q = made per craft, r = { { itemID, qty }, ... } }   from the Cooking window
--     names[itemID] = name
-- Catches are counters of the game database, one per spot and origin (a random number per install: never a name):
--   "fcatch:<n>:<origin>" = casts, { item, qty, item, qty, ... }, the lowest fishing skill a catch was made at, the
--   spot's name (DBLogic.Pack). n is a number made of the spot's name, so that every install writes the same key for
--   the same spot. A spot is "Zone, Subzone" as the game names it (a client in another language has its own).
--   F.Catches() adds every origin's up: { [spot] = { casts, items = { [itemID] = qty }, skill, mine = my casts } }.
local MAX_KINDS = 100 -- ponytail: a spot's row holds the commonest 100 kinds of catch (a row may be 2000 bytes); more is junk

-- { raw fish, cooked, cooking skill, { extra mat, qty }... }
local MILD, HOT, SOOTHING, WATER = 2678, 2692, 3713, 159
local COOKED = {
	{ 6291, 6290, 1 }, { 6303, 787, 1 }, { 6289, 4592, 50 }, { 6317, 6316, 50, { MILD, 1 } }, { 6361, 5095, 50 },
	{ 21071, 21072, 80, { MILD, 1 } }, { 6522, 6657, 85, { MILD, 1 } }, { 6308, 4593, 100 }, { 6362, 4594, 175 },
	{ 21153, 21217, 175, { HOT, 1 } }, { 8365, 8364, 175 }, { 4603, 6887, 225 }, { 13754, 13927, 225, { SOOTHING, 1 } },
	{ 13758, 13930, 225 }, { 13756, 13929, 240, { HOT, 2 } }, { 13755, 13928, 240, { SOOTHING, 1 } }, { 13760, 13932, 250 },
	{ 13759, 13931, 250, { WATER, 1 } }, { 13889, 13935, 275, { SOOTHING, 1 } }, { 13888, 13933, 275, { WATER, 1 } },
	{ 13893, 13934, 275, { HOT, 1 }, { SOOTHING, 1 } },
}
-- fish worth catching that are not cooked: oily blackmouth, firefin snapper, stonescale eel, lightning eel
local OTHER = { 6358, 6359, 13422, 13757 }
-- what a vendor asks for the mats he sells (copper)
local VENDOR_COST = { [MILD] = 10, [HOT] = 40, [SOOTHING] = 160, [WATER] = 25 }
-- { fishing skill at which nothing gets away, { zones }, { fish } }
-- ponytail: from memory of the old world, with every fish of a water counted as equally likely. Good enough to
-- say where to try; "per cast" is only real once you have fished there (then your own catches replace this).
local WATERS = {
	{ 25, { "Elwynn Forest", "Dun Morogh", "Teldrassil", "Durotar", "Mulgore", "Tirisfal Glades" }, { 6291, 6303, 6289 } },
	{ 75, { "Stormwind City", "Ironforge", "Darnassus", "Orgrimmar", "Thunder Bluff", "Undercity" }, { 6291, 6289 } },
	{ 75, { "Westfall", "Darkshore", "Silverpine Forest" }, { 6289, 6361, 6358 } },
	{ 75, { "Loch Modan" }, { 6289, 6317, 6308 } },
	{ 75, { "The Barrens" }, { 6289, 6522, 6358, 6361 } },
	{ 150, { "Redridge Mountains", "Duskwood", "Stonetalon Mountains" }, { 6308, 21071 } },
	{ 150, { "Wetlands", "Hillsbrad Foothills", "Ashenvale" }, { 6308, 6361, 6359, 6358, 21071 } },
	{ 225, { "Stranglethorn Vale" }, { 6362, 6359, 6358, 4603, 8365 } },
	{ 225, { "Arathi Highlands", "Dustwallow Marsh", "Desolace", "Swamp of Sorrows" }, { 6362, 6359, 8365 } },
	{ 225, { "Alterac Mountains", "Thousand Needles" }, { 8365, 21153 } },
	{ 300, { "Tanaris" }, { 4603, 13422, 13754 } },
	{ 300, { "Feralas", "The Hinterlands" }, { 4603, 13758, 13759, 13760, 13422 } },
	{ 300, { "Felwood", "Un'Goro Crater" }, { 13758, 13759, 13760, 13757 } },
	{ 300, { "Western Plaguelands" }, { 13758, 13759, 13760 } },
	{ 300, { "Azshara" }, { 13422, 13754, 13755, 13756 } },
	{ 425, { "Eastern Plaguelands", "Winterspring", "Silithus" }, { 13889, 13757 } },
}
-- What raises fishing skill: { item, bonus, kind, where it comes from in the old world }
-- ponytail: sources from memory of the old world; Forever may hand them out elsewhere. The link on each row
-- (click it) leads to the item's page.
local GEAR = {
	{ 6533, 100, "Lure", "Fishing suppliers (limited stock); murlocs and naga drop it" },
	{ 6532, 75, "Lure", "Fishing suppliers" },
	{ 7307, 75, "Lure", "Dropped by rotting undead" },
	{ 6530, 50, "Lure", "Fishing suppliers" },
	{ 6811, 50, "Lure", "Made by engineers" },
	{ 6529, 25, "Lure", "Fishing suppliers" },
	{ 19970, 35, "Pole", "Prize of the Stranglethorn Fishing Extravaganza" },
	{ 19022, 25, "Pole", "Horde quest in The Hinterlands (Revantusk Village)" },
	{ 6367, 20, "Pole", "Shellfish traps off the Desolace coast" },
	{ 6366, 15, "Pole", "Fished up now and then, from skill 50 waters on" },
	{ 6365, 5, "Pole", "Fishing suppliers" },
	{ 12225, 3, "Pole", "Quest on the Darkshore coast" },
	{ 6256, 0, "Pole", "Fishing suppliers" },
	{ 19972, 5, "Hat", "Rare catch turned in at the Stranglethorn Fishing Extravaganza" },
	{ 19969, 5, "Boots", "Rare catch turned in at the Stranglethorn Fishing Extravaganza" },
}

local OWN_CASTS = 20 -- from this many casts on, a spot's own catches are believed over the list above
-- ponytail: a cast, the wait for the bite and the looting take some 20 seconds; no lure breaks, no walking counted
local CASTS_PER_HOUR = 170

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- An item the game has not loaded yet has no name and no vendor price for now: the tables are drawn again
-- when it comes (asking is enough to make the game fetch it).
local dirty = true
local awaited = {}
local function Info(id)
	local name, _, quality, _, _, _, _, _, _, icon, sell = C_Item.GetItemInfo(id)
	if not name then awaited[id] = true end
	return name, quality, icon, sell
end

local function Vendor(id)
	local _, _, _, sell = Info(id)
	return sell and sell > 0 and sell or nil
end

-- the auction price in the house the Market tab shows
local function Auction(id)
	return (DawnMarket.API.GetLatest(id))
end

-- what one is worth to sell: at auction if it is seen there, else to a vendor
local function Worth(id)
	return Auction(id) or Vendor(id) or 0
end

-- what one costs to get: the cheaper of auction and the vendor who sells it (as seen at a vendor's, else the
-- list above). Neither known: what it would sell for, rather than nothing (a mat is never free).
local function Cost(id)
	local a, v = Auction(id), (DawnMarket.API.GetVendor and DawnMarket.API.GetVendor(id)) or VENDOR_COST[id]
	return a and v and math.min(a, v) or a or v or Vendor(id) or 0
end

local function Name(id)
	return F.db.names[id] or Info(id) or ("item " .. id)
end

local function Text(id)
	local name, quality, icon = Info(id)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
	return (icon and ("|T%s:14|t "):format(icon) or "") .. color .. (name or Name(id)) .. "|r"
end

-- a price: white from the auction house, grey with "v" when only a vendor's
local function Shown(id)
	local a = Auction(id)
	if a then return DT.Money(a) end
	local v = Vendor(id)
	return v and ("|cff888888" .. DT.Money(v) .. " v|r") or "|cff888888-|r"
end

---------------------------------------------------------------------------
-- What is known
---------------------------------------------------------------------------

-- every way to cook a fish: { out, q, n = fish per craft, mats = { { id, qty } }, skill }
local function Recipes(fish)
	local out = {}
	for _, c in ipairs(COOKED) do
		if c[1] == fish then
			local mats = {}
			for i = 4, #c do mats[#mats + 1] = c[i] end
			out[#out + 1] = { out = c[2], q = 1, n = 1, mats = mats, skill = c[3] }
		end
	end
	for made, rec in pairs(F.db.recipes) do
		local n, mats, listed = nil, {}, false
		for _, r in ipairs(rec.r) do
			if r[1] == fish then n = r[2] else mats[#mats + 1] = r end
		end
		for _, o in ipairs(out) do listed = listed or o.out == made end
		if n and not listed then out[#out + 1] = { out = made, q = rec.q, n = n, mats = mats } end
	end
	return out
end

-- the best of them at today's prices: recipe, what cooking adds per fish (can be negative)
local function BestCooked(fish)
	local best, bestGain
	for _, rec in ipairs(Recipes(fish)) do
		local cost = 0
		for _, m in ipairs(rec.mats) do cost = cost + Cost(m[1]) * m[2] end
		local gain = (Worth(rec.out) * rec.q - cost) / rec.n - Worth(fish)
		if not best or gain > bestGain then best, bestGain = rec, gain end
	end
	return best, bestGain
end

local function IsFish(id)
	for _, c in ipairs(COOKED) do
		if c[1] == id then return true end
	end
	for _, other in ipairs(OTHER) do
		if other == id then return true end
	end
	for _, rec in pairs(F.db.recipes) do
		for _, r in ipairs(rec.r) do
			if r[1] == id then return true end
		end
	end
	return false
end

-- the fishing skill a zone asks for, by the list (nil: not in it)
local function Need(zone)
	for _, w in ipairs(WATERS) do
		for _, name in ipairs(w[2]) do
			if name == zone then return w[1] end
		end
	end
end

-- what the best thing to do with one fish brings: sold raw, or cooked first where that adds something
local function Best(id)
	local _, gain = BestCooked(id)
	return Worth(id) + math.max(0, gain or 0)
end

---------------------------------------------------------------------------
-- Catches: the counters
---------------------------------------------------------------------------

local function Plain(text) -- (a name as it is kept: no colour code, link or line break)
	return (tostring(text or ""):gsub("[|%c]", ""):sub(1, 60))
end

local function Key(spot)
	return ("fcatch:%d:%s"):format(tonumber(DBL.Hash(spot):sub(1, 6), 16), DB.Origin())
end
F.Key = Key

-- a row's values as { casts, items = { [item] = qty }, skill, name }; nil where it is not of the shape (it may
-- have come over the wire: sane sizes only)
local function Parse(text)
	local v = DBL.Unpack(text)
	if not v or type(v[1]) ~= "number" or v[1] < 1 or v[1] >= 1e7 or type(v[4]) ~= "string" or Plain(v[4]) == "" then return nil end
	local flat = v[2]
	if type(flat) ~= "table" or #flat % 2 ~= 0 or #flat > 2 * MAX_KINDS then return nil end
	local items = {}
	for i = 1, #flat, 2 do
		if type(flat[i]) ~= "number" or type(flat[i + 1]) ~= "number" or flat[i + 1] < 0 or flat[i + 1] >= 1e7 then return nil end
		items[flat[i]] = flat[i + 1]
	end
	return { casts = v[1], items = items, skill = type(v[3]) == "number" and v[3] > 0 and v[3] < 1000 and v[3] or nil, name = Plain(v[4]) }
end

-- my counter of a spot written: c = { casts, items, skill }
local function Save(spot, c)
	local ids = {}
	for id in pairs(c.items) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b)
		if c.items[a] ~= c.items[b] then return c.items[a] > c.items[b] end
		return a < b
	end)
	for i = MAX_KINDS + 1, #ids do ids[i] = nil end
	table.sort(ids)
	local flat = {}
	for _, id in ipairs(ids) do flat[#flat + 1], flat[#flat + 2] = id, c.items[id] end
	DB.Put(Key(spot), DBL.Pack({ c.casts, flat, c.skill, spot }, 4))
end

local sums = {} -- { stamp, by }: worked out once until the store changes
function F.Catches()
	if sums.stamp == DB.Stamp() then return sums.by end
	local by, me = {}, DB.Origin()
	DB.Each("fcatch", function(key, row)
		local origin = key:match("^fcatch:%d+:(%x+)$")
		local p = origin and Parse(row.v)
		if p then
			local c = by[p.name]
			if not c then
				c = { casts = 0, items = {}, mine = 0 }
				by[p.name] = c
			end
			c.casts = c.casts + p.casts
			if origin == me then c.mine = c.mine + p.casts end
			for id, qty in pairs(p.items) do c.items[id] = (c.items[id] or 0) + qty end
			if p.skill and (not c.skill or p.skill < c.skill) then c.skill = p.skill end
		end
	end)
	sums = { stamp = DB.Stamp(), by = by }
	return by
end

-- The catches saved before (db.catches[spot] = { casts, items, skill }) laid under my origin: the larger of each number
-- and what the store holds of mine for the spot, so that a second run, or one on a half-moved file, changes nothing;
-- then the table goes.
function F.Migrate(db)
	for spot, c in pairs(type(db.catches) == "table" and db.catches or {}) do
		local casts = type(c) == "table" and math.floor(tonumber(c.casts) or 0)
		if type(spot) == "string" and Plain(spot) ~= "" and casts and casts >= 1 and casts < 1e7 then
			spot = Plain(spot)
			local items, skill = {}, tonumber(c.skill)
			for id, qty in pairs(type(c.items) == "table" and c.items or {}) do
				id, qty = tonumber(id), tonumber(qty)
				if id and id > 0 and qty and qty >= 0 and qty < 1e7 then items[id] = math.floor(qty) end
			end
			local row = DB.Row(Key(spot))
			local have = row and Parse(row.v)
			if have then
				casts = math.max(casts, have.casts)
				for id, qty in pairs(have.items) do items[id] = math.max(items[id] or 0, qty) end
				if have.skill and (not skill or have.skill < skill) then skill = have.skill end
			end
			Save(spot, { casts = casts, items = items, skill = skill })
		end
	end
	db.catches = nil
	db.moved = true
end

-- Spots, best per cast first: { name, skill (needed), caught (lowest skill I caught at), casts (nil = from the
-- list), mine (of them mine), per = copper per cast, fish = { { id, share } }, best = { id, copper }: the dearest single catch }
local function Spots()
	local spots, fished = {}, {}
	local function Dearest(ids)
		local best
		for _, id in ipairs(ids) do
			local value = Best(id)
			if value > 0 and (not best or value > best[2]) then best = { id, value } end
		end
		return best
	end
	for name, c in pairs(F.Catches()) do
		local zone = name:match("^(.-), ") or name
		if c.casts >= OWN_CASTS then fished[zone] = true end
		local per, fish = 0, {}
		for id, qty in pairs(c.items) do
			per = per + qty * Worth(id)
			fish[#fish + 1] = { id, qty / c.casts, qty * Worth(id) }
		end
		table.sort(fish, function(a, b) return a[3] > b[3] end)
		local ids = {}
		for id in pairs(c.items) do ids[#ids + 1] = id end
		spots[#spots + 1] = { name = name, zone = zone, skill = Need(zone), caught = c.skill, casts = c.casts, mine = c.mine, per = per / c.casts, fish = fish, best = Dearest(ids) }
	end
	for _, w in ipairs(WATERS) do
		for _, zone in ipairs(w[2]) do
			if not fished[zone] then
				local per, fish = 0, {}
				for _, id in ipairs(w[3]) do
					per = per + Worth(id) / #w[3]
					fish[#fish + 1] = { id, 1 / #w[3], Worth(id) }
				end
				table.sort(fish, function(a, b) return a[3] > b[3] end)
				spots[#spots + 1] = { name = zone, zone = zone, skill = w[1], per = per, fish = fish, best = Dearest(w[3]) }
			end
		end
	end
	table.sort(spots, function(a, b)
		if a.per ~= b.per then return a.per > b.per end
		return a.name < b.name
	end)
	return spots
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function Spot()
	local zone = GetRealZoneText and GetRealZoneText() or "?"
	local sub = GetSubZoneText and GetSubZoneText() or ""
	return sub ~= "" and sub ~= zone and (zone .. ", " .. sub) or zone
end

-- my fishing skill; withBonus: as it stands with pole, gear and lure
local function FishingSkill(withBonus)
	if not (GetProfessions and GetProfessionInfo) then
		-- (the older skill list: name, header, expanded, rank, temporary points, modifier)
		if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank, _, bonus = GetSkillLineInfo(i)
			if not header and name == (PROFESSIONS_FISHING or "Fishing") then return (rank or 0) + (withBonus and bonus or 0) end
		end
		return nil
	end
	local _, _, _, fishing = GetProfessions()
	if not fishing then return nil end
	local _, _, level, _, _, _, _, bonus = GetProfessionInfo(fishing)
	return level and (level + (withBonus and bonus or 0)) or nil
end

local looting
local function Catch()
	if looting or not (IsFishingLoot and IsFishingLoot()) then return end
	looting = true -- (the game may announce one loot window more than once)
	local spot = Plain(Spot())
	local row = DB.Row(Key(spot))
	local c = row and Parse(row.v) or { casts = 0, items = {} }
	c.casts = c.casts + 1
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		local id = link and tonumber(link:match("item:(%d+)"))
		if id then
			local _, _, qty = GetLootSlotInfo(slot)
			c.items[id] = (c.items[id] or 0) + (qty or 1)
			F.db.names[id] = link:match("%[(.-)%]") or F.db.names[id]
		end
	end
	local skill = FishingSkill()
	if skill and (not c.skill or skill < c.skill) then c.skill = skill end
	Save(spot, c)
	dirty = true
end

-- the Cooking window: what this account can cook
-- ponytail: learned recipes only (the game is not asked about the others)
local function ReadCooking()
	local T = C_TradeSkillUI
	if not (T and T.GetBaseProfessionInfo and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetRecipeSchematic) then return end
	-- (somebody else's linked window is not what this account can cook)
	if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild()) then return end
	local base = T.GetBaseProfessionInfo()
	if not base or not (base.profession == 5 or base.professionName == (PROFESSIONS_COOKING or "Cooking")) then return end
	local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
	for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
		local info = T.GetRecipeInfo(id)
		local s = info and info.learned and T.GetRecipeSchematic(id, false)
		if s and s.outputItemID and s.outputItemID > 0 then
			local r = {}
			for _, slot in ipairs(s.reagentSlotSchematics or {}) do
				local reagent = slot.reagents and slot.reagents[1]
				if slot.reagentType == basic and reagent and reagent.itemID then r[#r + 1] = { reagent.itemID, slot.quantityRequired or 1 } end
			end
			if r[1] then F.db.recipes[s.outputItemID] = { q = s.quantityMin or 1, r = r } end
		end
	end
	dirty = true
end

---------------------------------------------------------------------------
-- The tab: two tables, "Fish" and "Spots"
---------------------------------------------------------------------------

local ROW_H, TOP_H = 18, 48 -- (top: the buttons and the search box, then a line of notes)
local VIEWS = {
	fish = {
		{ title = "Fish", width = 190 }, { title = "Raw", width = 80, right = true }, { title = "Cooked into", width = 190 },
		{ title = "Cooked", width = 80, right = true }, { title = "Cooking adds", width = 96, right = true },
		{ title = "Where (fishing skill)", width = 0 },
	},
	spots = {
		{ title = "Spot", width = 190 }, { title = "Levels", width = 54, right = true }, { title = "Skill", width = 50, right = true }, { title = "Casts", width = 70, right = true },
		{ title = "Per cast", width = 104, right = true }, { title = "Per hour", width = 104, right = true }, { title = "Best catch", width = 200 },
		{ title = "What bites (per cast)", width = 0 },
	},
	gear = {
		{ title = "Item", width = 230 }, { title = "Fishing", width = 60, right = true }, { title = "Kind", width = 60 },
		{ title = "You have", width = 70, right = true }, { title = "Auction", width = 104, right = true },
		{ title = "Where it comes from (old world; click the row for a link)", width = 0 },
	},
}
local view = "spots"
-- per table: the column it is sorted by, and which way
local sortBy = { spots = { col = 5, desc = true }, fish = { col = 2, desc = true }, gear = { col = 2, desc = true } }
local panel, bar, note, search
local rows, heads, viewButtons, list, offset = {}, {}, {}, {}, 0

local function Signed(copper)
	copper = math.floor(copper + 0.5)
	return (copper >= 0 and "|cff40ff40+" or "|cffff4040-") .. DT.Money(math.abs(copper)) .. "|r"
end

local function FishRows()
	local ids, seen = {}, {}
	local function Add(id)
		if not seen[id] then seen[id], ids[#ids + 1] = true, id end
	end
	for _, c in ipairs(COOKED) do Add(c[1]) end
	for _, id in ipairs(OTHER) do Add(id) end
	for _, c in pairs(F.Catches()) do
		for id in pairs(c.items) do
			if IsFish(id) or Auction(id) then Add(id) end
		end
	end
	local spots, out = Spots(), {}
	for _, id in ipairs(ids) do
		local rec, gain = BestCooked(id)
		local where = {}
		for _, s in ipairs(spots) do
			for _, f in ipairs(s.fish) do
				if f[1] == id and #where < 6 then
					where[#where + 1] = s.name .. (s.casts and (" |cff40ff40%d%%|r"):format(math.floor(f[2] * 100 + 0.5)) or (" |cff888888(%d)|r"):format(s.skill or 0))
				end
			end
		end
		local mats = {}
		for _, m in ipairs(rec and rec.mats or {}) do mats[#mats + 1] = ("%dx %s"):format(m[2], Name(m[1])) end
		out[#out + 1] = { id = id, cooked = rec and rec.out, worth = Worth(id), tip = rec and (#mats > 0 and ("Also needs: " .. table.concat(mats, ", ")) or "Needs nothing else.")
			.. (rec.skill and (" Cooking skill " .. rec.skill .. ".") or ""),
			Text(id), Shown(id), rec and Text(rec.out) or "|cff888888not cooked|r", rec and Shown(rec.out) or "",
			rec and Signed(gain) or "", table.concat(where, ", "),
			-- what each column sorts by
			sort = { Name(id), Worth(id), rec and Name(rec.out) or "", rec and Worth(rec.out) or 0, rec and gain or -math.huge,
				table.concat(where, ", ") } }
	end
	return out
end

-- Green: nothing gets away at my skill as it stands (pole, gear and lure counted). Yellow: I can cast there
-- but fish get away (from 95 below). Red: I cannot fish there yet.
local function SkillText(need, mine)
	if not need then return "" end
	if not mine then return tostring(need) end
	return "|c" .. (mine >= need and "ff40ff40" or mine >= need - 95 and "ffffd100" or "ffff4040") .. need .. "|r"
end

-- How many casts in a hundred land a fish: 5 at the least skill to cast (95 below the zone's), all of them at
-- the zone's skill. Nothing when either number is missing.
-- ponytail: the old-world rule (a point of skill, a point of chance). Forever may count otherwise: shown as "about".
local function Chance(need, mine)
	if not (need and mine) then return nil end
	if mine < need - 95 then return 0 end
	return math.min(100, mine - need + 100)
end
F.Chance = Chance

-- the levels of a zone's mobs in a colour for my own level, and the lowest of them (to sort by); "" and 0
-- until the Zones tab's data can be worked out (QuestieDB read) or where it knows no levels
local function ZoneLevels(zone)
	local Z = DT.Zone
	local z = Z and Z.Ensure and Z.Ensure() and Z.Get(zone)
	if not (z and z.lo) then return "", 0 end
	return Z.LevelColor(z, UnitLevel and UnitLevel("player") or 0) .. Z.Levels(z) .. "|r", z.lo
end

local GOLD, GREY, GREEN = "|cffffd100", "|cff888888", "|cff40ff40"

local function SpotRows()
	local out, mine = {}, FishingSkill(true)
	for _, s in ipairs(Spots()) do
		local fish = {}
		for i = 1, math.min(4, #s.fish) do
			fish[i] = ("%s %d%%"):format(Name(s.fish[i][1]), math.floor(s.fish[i][2] * 100 + 0.5))
		end
		local levels, lowest = ZoneLevels(s.zone)
		local own = s.casts and s.casts >= OWN_CASTS
		local perCast = (own and "" or GREY .. "~|r") .. DT.Money(math.floor(s.per + 0.5))
		local perHour = GOLD .. DT.Money(math.floor(s.per * CASTS_PER_HOUR + 0.5)) .. "|r"
		local best = s.best and (Name(s.best[1]) .. " " .. GREEN .. DT.Money(math.floor(s.best[2] + 0.5)) .. "|r")
		-- the hover: what | value
		local tips = {}
		if levels ~= "" then tips[#tips + 1] = { "Zone levels", levels } end
		if s.skill then
			tips[#tips + 1] = { "Fishing skill", SkillText(s.skill, mine) .. GREY .. ("  (cast from %d)|r"):format(math.max(1, s.skill - 95)) }
			local chance = Chance(s.skill, mine)
			if chance then
				tips[#tips + 1] = { "At your " .. mine, chance >= 100 and (GREEN .. "nothing gets away|r")
					or chance > 0 and ("|cffffd100about %d%% of casts land|r"):format(chance) or "|cffff4040cannot cast here yet|r" }
			end
		end
		tips[#tips + 1] = { "Per cast", perCast }
		tips[#tips + 1] = { "Per hour", perHour .. GREY .. ("  (%d casts)|r"):format(CASTS_PER_HOUR) }
		if best then tips[#tips + 1] = { "Best catch", best } end
		if s.fish[1] then
			tips[#tips + 1] = " "
			tips[#tips + 1] = GOLD .. "What bites|r" .. GREY .. "  (share of casts, price each)|r"
			for i = 1, math.min(10, #s.fish) do
				local id, share = s.fish[i][1], s.fish[i][2]
				tips[#tips + 1] = { "  " .. Name(id), ("%s%s%d%%|r  %s"):format(own and "" or GREY .. "~|r", GREEN, math.floor(share * 100 + 0.5), DT.Money(math.floor(Worth(id) + 0.5))) }
			end
			if #s.fish > 10 then tips[#tips + 1] = GREY .. ("  and %d more|r"):format(#s.fish - 10) end
		end
		tips[#tips + 1] = " "
		-- (where the numbers are from: my own counts, and the guild's where the game database is shared)
		local first = s.caught and (", the first at skill " .. s.caught) or ""
		tips[#tips + 1] = GREY .. (s.casts and (s.mine == s.casts and ("From your own %d cast%s here%s."):format(s.casts, s.casts == 1 and "" or "s", first)
			or ("From %d cast%s here: %d yours, the rest the guild's%s."):format(s.casts, s.casts == 1 and "" or "s", s.mine or 0, first))
			or "~ A guess from the built-in list, until you or the guild have fished here.") .. "|r"
		out[#out + 1] = {
			tips = tips,
			s.name, levels, SkillText(s.skill, mine), s.casts and tostring(s.casts) or GREY .. "-|r",
			perCast, perHour, best or GREY .. "-|r",
			table.concat(fish, ", "),
			sort = { s.name, lowest, s.skill or 0, s.casts or 0, s.per, s.per, s.best and s.best[2] or 0, table.concat(fish, ", ") } }
	end
	return out
end

-- what raises fishing skill; one lure at a time, on top of pole, hat and boots
local function GearRows()
	local out = {}
	for _, g in ipairs(GEAR) do
		local id = g[1]
		local bags, bank = 0, 0
		if DawnInventory then bags, bank = DawnInventory.API.Count(id) end
		out[#out + 1] = { id = id, tip = g[4] .. ".",
			Text(id), "+" .. g[2], g[3], bags + bank > 0 and tostring(bags + bank) or "|cff888888-|r", Shown(id), g[4],
			sort = { Name(id), g[2], g[3], bags + bank, Auction(id) or 0, g[4] } }
	end
	return out
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -TOP_H - ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -12, 0)
	row.cols = {}
	for c = 1, 8 do
		row.cols[c] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.cols[c]:SetWordWrap(false)
	end
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if d.id then GameTooltip:SetHyperlink("item:" .. d.id) else GameTooltip:AddLine(d[1]) end
		if d.tip then GameTooltip:AddLine(d.tip, 1, 1, 1, true) end
		-- (a spot: lines of "what | value", and plain lines between them)
		for _, t in ipairs(d.tips or {}) do
			if type(t) == "table" then GameTooltip:AddDoubleLine(t[1], t[2], 0.75, 0.75, 0.75, 1, 1, 1) else GameTooltip:AddLine(t, 1, 1, 1, true) end
		end
		if d.id then GameTooltip:AddLine("Click: a link to read up on it.", 0.6, 0.6, 0.6) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- a click on an item's row: the link to read up on it
	row:SetScript("OnMouseUp", function(self, button)
		local d = self.data
		if not (d and d.id) or DT:ItemClick(d.id, Name(d.id), button) then return end
		DT:ShowLink(Name(d.id), DT:ItemLink(d.id))
	end)
	-- over the "cooked" columns of the Fish table: the cooked food's own tooltip and link (Refresh places it)
	row.over = CreateFrame("Frame", nil, row)
	row.over:SetHeight(ROW_H)
	row.over:EnableMouse(true)
	row.over:SetScript("OnEnter", function(self)
		local d = row.data
		if not (d and d.cooked) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. d.cooked)
		if d.tip then GameTooltip:AddLine(d.tip, 1, 1, 1, true) end
		GameTooltip:AddLine("Click: a link to read up on it.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row.over:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.over:SetScript("OnMouseUp", function(_, button)
		local d = row.data
		if not (d and d.cooked) or DT:ItemClick(d.cooked, Name(d.cooked), button) then return end
		DT:ShowLink(Name(d.cooked), DT:ItemLink(d.cooked))
	end)
	rows[i] = row
	return row
end

-- the rows of the table shown, searched and sorted
local function Rebuild()
	list = view == "fish" and FishRows() or view == "gear" and GearRows() or SpotRows()
	local q = (search:GetText() or ""):lower()
	if q ~= "" then
		local kept = {}
		for _, d in ipairs(list) do
			local hay = {}
			for _, v in ipairs(d.sort) do hay[#hay + 1] = type(v) == "string" and v or nil end
			if table.concat(hay, " "):lower():find(q, 1, true) then kept[#kept + 1] = d end
		end
		list = kept
	end
	local by = sortBy[view]
	table.sort(list, function(a, b)
		local x, y = a.sort[by.col], b.sort[by.col]
		if x ~= y then
			if by.desc then return x > y end
			return x < y
		end
		return a.sort[1] < b.sort[1]
	end)
end

-- scrolled = only the window moved: the tables are not worked out again
local function Refresh(scrolled)
	if not panel then return end
	if scrolled ~= true then
		dirty = false
		Rebuild()
	end
	local cols, by = VIEWS[view], sortBy[view]
	local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H - ROW_H) / ROW_H))
	local max = math.max(0, #list - fit)
	offset = math.max(0, math.min(offset, max))
	bar:SetMinMaxValues(0, max)
	bar:SetValue(offset)
	bar:SetShown(max > 0)
	bar.thumb:SetSize(8, math.max(16, fit * ROW_H * fit / math.max(fit, #list)))
	-- the last column takes the width that is left
	local x, xs = 4, {}
	for c, col in ipairs(cols) do
		xs[c] = x
		x = x + col.width
		local h = heads[c]
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", xs[c], -TOP_H)
		h:SetSize(col.width > 0 and col.width - 6 or math.max(60, panel:GetWidth() - xs[c] - 16), ROW_H)
		h.text:SetJustifyH(col.right and "RIGHT" or "LEFT")
		h.text:SetText("|cffffd100" .. col.title .. (by.col == c and (by.desc and " v" or " ^") or "") .. "|r")
		h:Show()
	end
	for c = #cols + 1, #heads do heads[c]:Hide() end
	for i = 1, math.max(fit, #rows) do
		local d = i <= fit and list[offset + i]
		local row = rows[i] or (d and MakeRow(i))
		if row then
			row.data = d or nil
			row:SetShown(d and true or false)
			row.over:SetShown(view == "fish" and d and d.cooked and true or false)
			if view == "fish" then
				row.over:ClearAllPoints()
				row.over:SetPoint("LEFT", xs[3], 0)
				row.over:SetWidth(cols[3].width + cols[4].width)
			end
			for c, cell in ipairs(row.cols) do
				local col = cols[c]
				cell:SetText(d and col and d[c] or "")
				if col then
					cell:ClearAllPoints()
					cell:SetPoint("LEFT", xs[c], 0)
					cell:SetWidth(col.width > 0 and col.width - 6 or math.max(60, panel:GetWidth() - xs[c] - 16))
					cell:SetJustifyH(col.right and "RIGHT" or "LEFT")
				end
			end
		end
	end
	for key, b in pairs(viewButtons) do
		if key == view then b:LockHighlight() else b:UnlockHighlight() end
	end
	local casts, mine = 0, 0
	for _, c in pairs(F.Catches()) do casts, mine = casts + c.casts, mine + c.mine end
	note:SetText(("|cff888888Prices: %s auction house (grey v = vendor only). %d casts counted: %d yours%s. ~ = a guess from the built-in list. Skill: green = nothing gets away, yellow = some do, red = cannot cast.|r"):format(
		DT.Market.HOUSE_NAMES[DT.Market.view] or "?", casts, mine, casts > mine and ", the rest the guild's" or ""))
end
F.Refresh = Refresh
F.Spots, F.Name, F.Worth = Spots, Name, Worth -- (for the Zones tab)

local function Build(parent)
	panel = parent
	local x = 4
	for _, v in ipairs({ { "spots", "Spots", "Where a cast is worth the most, at today's prices." },
		{ "fish", "Fish", "Each fish: its price raw and cooked, what cooking adds, and where it bites." },
		{ "gear", "Gear", "Lures, poles and clothes that raise fishing skill, and where they come from." } }) do
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(70, 22)
		b:SetPoint("TOPLEFT", x, -2)
		b:SetText(v[2])
		b:SetScript("OnClick", function()
			view, offset = v[1], 0
			Refresh()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(v[3], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		viewButtons[v[1]] = b
		x = x + 72
	end
	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("LEFT", viewButtons.gear, "RIGHT", 16, 0)
	F.search = search
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function() -- (hooked: the template's own handler shows the "Search" hint)
		offset, dirty = 0, true
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 6, -29)
	note:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
	note:SetJustifyH("LEFT")
	note:SetWordWrap(false)
	-- column headers: click to sort, again to turn it round
	for c = 1, 8 do
		local h = CreateFrame("Button", nil, panel)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetWordWrap(false)
		h:SetScript("OnClick", function()
			local by = sortBy[view]
			if by.col == c then
				by.desc = not by.desc
			else
				-- (numbers start with the biggest, names with A)
				by.col, by.desc = c, VIEWS[view][c] and VIEWS[view][c].right or false
			end
			Refresh()
		end)
		heads[c] = h
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
		Refresh(true)
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Refresh(true)
	end)
	panel:SetScript("OnSizeChanged", Refresh)
	local nextUpdate = 0
	DT.OnUpdate(panel, "tab: Fishing", function()
		if GetTime() < nextUpdate then return end
		nextUpdate = GetTime() + 0.5
		if dirty then Refresh() end
	end)
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

DT:RegisterModule("fish", {
	title = "Fishing",
	version = 1,
	slash = "/dtfish",
	tab = { id = "fish", title = "Fishing", defaultOrder = 40, under = "craft", create = Build, onShow = Refresh },
	onEnable = function(mod)
		F.db = mod.db
		F.db.recipes, F.db.names = F.db.recipes or {}, F.db.names or {}
		if F.db.catches then
			local ok, err = pcall(F.Migrate, F.db)
			if not ok then geterrorhandler()(err) end -- (what was not moved is still there for the next login)
		end
		-- (a member's catches are on show at once)
		DT:On("DT_DB_UPDATE", function(chunk) if chunk and chunk:find("^fcatch:") then dirty = true end end)
		DT:On("LOOT_READY", Catch)
		DT:On("LOOT_OPENED", Catch)
		DT:On("LOOT_CLOSED", function() looting = false end)
		DT:On("TRADE_SKILL_SHOW", function() C_Timer.After(1, ReadCooking) end)
		DT:On("DT_MARKET_UPDATE", function() dirty = true end)
		DT:On("GET_ITEM_INFO_RECEIVED", function(id)
			if awaited[id] then awaited[id], dirty = nil, true end
		end)
	end,
	selfTest = function(_, Try)
		for _, v in ipairs({ "fish", "spots", "gear" }) do
			Try("fish tab, " .. v, function()
				local was = view
				view = v
				Refresh()
				view = was
				Refresh()
			end)
		end
	end,
})
