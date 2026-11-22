-- DawnTools :: DB
-- One way to ask about the game's things and how they hang together, whatever knows the answer. The model, the
-- sources and their licences are written down in docs/DATA.md.
--
--   DB.Get(kind, id)           one thing: { kind, id, name, ..., src }, or nil where nobody knows it
--   DB.RelTo(rel, kind, id)    the facts that point AT it:  DB.RelTo("drops", "item", 872): who drops item 872
--   DB.Rel(rel, kind, id)      the facts that start FROM it: DB.Rel("rewards", "quest", 102): what quest 102 gives
--
-- A fact is { kind, id, src, ... }: the thing at its other end, where the fact is from, and what the relation
-- carries (chance in percent; ours: n = times looted, k = times seen; price; count; choice).
-- src: "own" (I saw it), "guild" (a member did), "shipped" (DawnTools' own data files), "questie" (QuestieDB,
-- read live), "oneforall", "atlasloot" (read live while installed; never stored).
-- Facts come in that order, ours first.
--
-- ponytail: only the relations in ANSWERS are answered yet; the rest of DB.RELS is the model the store (further
-- down: DB.Put, DB.Row, DB.Take) will fill (see the phases in docs/DATA.md). The answers are not cached: the
-- callers ask on a click.

local _, DT = ...
local DB = {}
DT.DB = DB

-- The model: a relation's name = { what it starts from, what it points at }.
DB.KINDS = { "item", "npc", "object", "quest", "zone", "recipe", "dungeon", "faction", "itemset" }
DB.RELS = {
	drops = { { "npc", "object", "item" }, "item" },
	pickpocket = { { "npc" }, "item" }, skinning = { { "npc" }, "item" }, gathering = { { "object" }, "item" },
	sells = { { "npc" }, "item" },
	rewards = { { "quest" }, "item" },
	starts = { { "npc", "object", "item" }, "quest" }, ends = { { "npc", "object" }, "quest" },
	requires = { { "quest" }, "quest" },
	objective = { { "quest" }, "npc" },
	spawns = { { "npc", "object" }, "zone" },
	makes = { { "recipe" }, "item" },
	teaches = { { "item", "npc" }, "recipe" },
	disenchants = { { "item" }, "item" },
	partof = { { "item" }, "itemset" },
	bossof = { { "npc" }, "dungeon" }, questof = { { "quest" }, "dungeon" }, keyof = { { "item", "quest" }, "dungeon" },
	catch = { { "zone" }, "item" },
	within = { { "zone" }, "zone" },
	belongs = { { "npc" }, "faction" },
	flight = { { "npc" }, "zone" },
}

---------------------------------------------------------------------------
-- QuestieDB, read live
---------------------------------------------------------------------------

local ENTITY = { item = "Item", npc = "Npc", object = "Object", quest = "Quest" }

local function Questie()
	local lib = LibQuestieDB
	if type(lib) ~= "table" then return nil end
	if lib.RequireContract then
		local ok, good = pcall(lib.RequireContract, 4)
		if not (ok and good) then return nil end
	end
	return lib
end

DB.Questie = Questie

-- one field of one thing, or nil: of QuestieDB, else of the store's rows (DB.Lib, further down)
local function Q(kind, id, field)
	local lib = DB.Lib()
	local entity = lib and lib[ENTITY[kind]]
	if not (entity and entity.Get) then return nil end
	local ok, value = pcall(entity.Get, id, field)
	if ok then return value end
end
DB.Q = Q

local function Ids(list)
	local out = {}
	for _, id in ipairs(type(list) == "table" and list or {}) do
		if type(id) == "number" and id > 0 then out[#out + 1] = id end
	end
	return out
end

local function Add(out, kind, ids, src, more)
	for _, id in ipairs(ids) do
		local fact = { kind = kind, id = id, src = src }
		for key, value in pairs(more and more(id) or {}) do fact[key] = value end
		out[#out + 1] = fact
	end
end

---------------------------------------------------------------------------
-- One thing
---------------------------------------------------------------------------

local GET = {
	item = function(id)
		local name = Q("item", id, "name")
		if type(name) == "string" and name ~= "" then
			return { name = name, level = Q("item", id, "requiredLevel") or 0, ilvl = Q("item", id, "itemLevel") or 0,
				class = Q("item", id, "class"), sub = Q("item", id, "subClass"), src = "questie" }
		end
		-- (an item QuestieDB does not have: what the game says of it, once it has loaded it)
		local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		local ok, known, _, _, ilvl, level, _, _, _, _, _, _, class, sub = pcall(function() return info(id) end)
		if ok and known then return { name = known, level = level or 0, ilvl = ilvl or 0, class = class, sub = sub, src = "game" } end
	end,
	npc = function(id)
		local name = Q("npc", id, "name")
		if type(name) ~= "string" or name == "" then return nil end
		return { name = name, min = Q("npc", id, "minLevel"), max = Q("npc", id, "maxLevel"), zone = Q("npc", id, "zoneID"),
			side = Q("npc", id, "friendlyToFaction"), src = "questie" }
	end,
	object = function(id)
		local name = Q("object", id, "name")
		if type(name) ~= "string" or name == "" then return nil end
		return { name = name, zone = Q("object", id, "zoneID"), src = "questie" }
	end,
	quest = function(id)
		local name = Q("quest", id, "name")
		if type(name) ~= "string" or name == "" then return nil end
		return { name = name, level = Q("quest", id, "questLevel"), min = Q("quest", id, "requiredLevel"), src = "questie" }
	end,
}

function DB.Get(kind, id)
	local get = GET[kind]
	local thing = get and type(id) == "number" and get(id) or nil
	if not thing and get and type(id) == "number" then
		-- (what QuestieDB has no entry for, and we wrote down in play)
		local stored = DB.Stored(kind, id)
		if stored and stored.name and stored.name ~= "" then thing = { name = stored.name, max = stored.maxLevel, src = "guild" } end
	end
	if thing then thing.kind, thing.id = kind, id end
	return thing
end

-- the name of a thing, or "npc 12" where nobody knows it
function DB.Name(kind, id)
	local thing = DB.Get(kind, id)
	return thing and thing.name or (kind .. " " .. tostring(id))
end

---------------------------------------------------------------------------
-- Relations
---------------------------------------------------------------------------

-- the dungeon bosses that drop an item, with the chance stated and what was seen: ours first
local function BossDrops(out, item)
	local Dg = DT.Dungeon
	if not (Dg and Dg.All) then return end
	for _, d in ipairs(Dg.All()) do
		for _, boss in ipairs(d.bosses) do
			if boss.has[item] and boss.npc then
				local fact = { kind = "npc", id = boss.npc, src = "shipped", chance = Dg.Chance and Dg.Chance(boss, item) or nil,
					boss = boss.name, dungeon = d.name }
				local n, k = 0, 0
				if Dg.Seen then
					local ok, kills, items = pcall(Dg.Seen, boss)
					if ok and type(items) == "table" then n, k = kills or 0, items[item] or 0 end
				end
				if n > 0 then fact.n, fact.k = n, k end
				out[#out + 1] = fact
			end
		end
	end
end

-- [relation][kind asked about] = function(id) -> facts
local TO = {
	drops = { item = function(id)
		local out = {}
		BossDrops(out, id)
		Add(out, "npc", Ids(Q("item", id, "npcDrops")), "questie")
		Add(out, "object", Ids(Q("item", id, "objectDrops")), "questie")
		Add(out, "item", Ids(Q("item", id, "itemDrops")), "questie")
		return out
	end },
	sells = { item = function(id)
		local out = {}
		-- (what a vendor was seen to ask: mine, or a member's; the store does not say whose)
		local seen = DB.Vendor(id)
		if seen then out[#out + 1] = { kind = "npc", src = "guild", price = seen.p, limited = seen.l, name = seen.v, place = seen.z } end
		Add(out, "npc", Ids(Q("item", id, "vendors")), "questie")
		local price = DT.VendorPrice and DT.VendorPrice[id]
		if price then for _, fact in ipairs(out) do fact.price = fact.price or price end end
		return out
	end },
	rewards = { item = function(id)
		local out = {}
		Add(out, "quest", Ids(Q("item", id, "questRewards")), "questie")
		return out
	end },
	makes = { item = function(id)
		local out = {}
		for spell, r in pairs(DT.Recipes or {}) do
			if r[7] == id then out[#out + 1] = { kind = "recipe", id = spell, src = "shipped", line = r[1], learn = r[2], yield = r[8] } end
		end
		return out
	end },
}

local FROM = {
	starts = { item = function(id)
		local quest = Q("item", id, "startQuest")
		return type(quest) == "number" and quest > 0 and { { kind = "quest", id = quest, src = "questie" } } or {}
	end },
	drops = { npc = function(id)
		local out = {}
		local Dg = DT.Dungeon
		local boss = Dg and Dg.BossOf and Dg.BossOf(id)
		for _, item in ipairs(boss and boss.items or {}) do
			out[#out + 1] = { kind = "item", id = item, src = "shipped", chance = Dg.Chance(boss, item) }
		end
		return out
	end },
	bossof = { npc = function(id)
		local Dg = DT.Dungeon
		local boss = Dg and Dg.BossOf and Dg.BossOf(id)
		return boss and { { kind = "dungeon", id = boss.dungeon.key, src = "shipped", name = boss.dungeon.name, rare = boss.rare } } or {}
	end },
}
DB.ANSWERS = { to = TO, from = FROM }

local function Ask(table, rel, kind, id)
	local fn = table[rel] and table[rel][kind]
	if not fn or type(id) ~= "number" then return {} end
	local ok, facts = pcall(fn, id)
	if not ok then
		DT:Debug("db", "%s %s %s: %s", rel, kind, tostring(id), tostring(facts))
		return {}
	end
	return facts
end

function DB.RelTo(rel, kind, id) return Ask(TO, rel, kind, id) end
function DB.Rel(rel, kind, id) return Ask(FROM, rel, kind, id) end

-- the facts of one kind and one source out of a list (src nil: of any)
function DB.Only(facts, kind, src)
	local out = {}
	for _, fact in ipairs(facts) do
		if fact.kind == kind and (not src or fact.src == src) then out[#out + 1] = fact end
	end
	return out
end

-- A drop chance as it is shown: what a source states, and what we saw. "12%", "7 of 52 looted (13%)", or both.
-- Ours leads once enough was looted to mean something.
DB.ENOUGH = 50
function DB.ChanceText(fact)
	local stated = fact.chance and fact.chance > 0 and (("%g%%"):format(fact.chance)) or nil
	local ours = fact.n and fact.n > 0 and ("%d of %d looted (%d%%)"):format(fact.k or 0, fact.n, math.floor((fact.k or 0) / fact.n * 100 + 0.5)) or nil
	if ours and stated then
		return fact.n >= DB.ENOUGH and (ours .. ", stated " .. stated) or (stated .. ", seen " .. ours)
	end
	return ours or stated or ""
end

---------------------------------------------------------------------------
-- The store: what DawnTools keeps of the game itself (phase 3 of docs/DATA.md)
---------------------------------------------------------------------------
-- DawnToolsDB.db = { v = 1, origin = "1f3a9c" (this install's, random; never a name),
--                    chunks = { [chunk] = its rows as one text }, hash = { [chunk] = that text's hash } }
-- Rows, keys and chunks: Core/DBLogic.lua. A chunk is read (its text taken apart) only when a row of it is
-- looked at, and a few stay open.
-- ponytail: nothing fills it yet but DB.Put: the modules' own stores move in, and the sync that passes chunks
-- between members comes, with the phases still open.

local L = DT.DBLogic
local store
local open, opened = {}, 0 -- [chunk] = its rows, taken apart
local stamp = 0            -- counts the writes: what was worked out from rows is good while it stands
local stampOf = {}         -- the same, per kind of row ("qreward"): a loot count does not undo the quest rewards

local function Store()
	if store then return store end
	local db = DawnToolsDB.db
	if type(db) ~= "table" or db.v ~= 1 then db = { v = 1 } end
	if type(db.chunks) ~= "table" then db.chunks = {} end
	if type(db.hash) ~= "table" then db.hash = {} end
	if type(db.origin) ~= "string" or not db.origin:find("^%x%x%x%x%x%x$") then
		db.origin = ("%06x"):format(math.random(0, 0xffffff))
	end
	DawnToolsDB.db, store = db, db
	return db
end

local function Rows(chunk)
	local rows = open[chunk]
	if not rows then
		if opened >= 32 then open, opened = {}, 0 end -- (ponytail: all closed when many are open; they open again on the next look)
		rows = L.Parse(Store().chunks[chunk])
		open[chunk], opened = rows, opened + 1
	end
	return rows
end

local function Write(chunk, rows)
	local db = Store()
	local text = L.Build(rows)
	stamp = stamp + 1
	local kind = chunk:match("^(%a+):")
	if kind then stampOf[kind] = (stampOf[kind] or 0) + 1 end
	if text == "" then
		db.chunks[chunk], db.hash[chunk] = nil, nil
	else
		db.chunks[chunk], db.hash[chunk] = text, L.Hash(text)
	end
end

function DB.Origin() return Store().origin end

-- a row by its key: { t, src, v }, or nil
function DB.Row(key)
	return Rows(L.ChunkOf(key))[key]
end

-- A row learned: kept if there is none under its key or its values differ. src: "guild" unless said: what we
-- learned, whoever of us did (a row does not say whose it is: two installs holding the same rows must hold
-- the same text, or their hashes would never agree; and nobody is to be named).
-- Returns true where something changed.
function DB.Put(key, value, src, t)
	key, value = L.Clean(key), L.Clean(value)
	local chunk = L.ChunkOf(key)
	local rows = Rows(chunk)
	local at = rows[key]
	if at and at.v == value and at.src == (src or "guild") then return false end
	rows[key] = { t = t or DT.Now(), src = src or "guild", v = value }
	Write(chunk, rows)
	return true
end

-- A row from a store of before (a module's own saved table), kept where none is held under its key or the one
-- held is older: so that moving a file twice, or a half-moved one, loses nothing and writes nothing twice.
function DB.Keep(key, value, t)
	t = math.min(tonumber(t) or 1, DT.Now())
	local at = DB.Row(L.Clean(key))
	if at and at.t >= t then return false end
	return DB.Put(key, value, "guild", t)
end

-- every row "what:<id>" as { [id] = what parse gives }: parse(values as text) returns a table (nil: not of the
-- shape, left out), which is given t, the row's time. Worked out once, until the store changes.
local tables = {}
function DB.Table(what, parse)
	local held = tables[what]
	if held and held.stamp == (stampOf[what] or 0) then return held.rows end
	local rows = {}
	for chunk, text in pairs(Store().chunks) do
		if chunk:match("^(%a+):") == what then
			for key, row in pairs(L.Parse(text)) do
				local id = tonumber(key:match("^%a+:(%d+)$"))
				local x = id and parse(row.v)
				if x then x.t, rows[id] = row.t, x end
			end
		end
	end
	tables[what] = { stamp = stampOf[what] or 0, rows = rows }
	return rows
end

-- fn(key, row) for every row of every chunk of one kind ("fcatch"); stamp: counts the writes, so that what a caller
-- worked out from rows is good while it stands
function DB.Each(what, fn)
	for chunk, text in pairs(Store().chunks) do
		if chunk:match("^(%a+):") == what then
			for key, row in pairs(L.Parse(text)) do fn(key, row) end
		end
	end
end
function DB.Stamp() return stamp end

-- What a vendor asks: "vendor:<item>" = price for one, limited stock (1 or 0), the vendor's name, where. One row an
-- item: the cheapest seller seen (Market/Capture.lua), the newest sighting where members meet. Of the player: nothing.
-- A row from the wire is read for what it is: a name has no colour code or link in it.
local function ParseVendor(text)
	local v = L.Unpack(text)
	local p, name, place = v and v[1], v and v[3], v and v[4]
	if type(p) ~= "number" or p <= 0 or p >= 1e10 or type(name) ~= "string" or name == "" then return nil end
	local function Plain(s) return type(s) == "string" and s:gsub("[|%c]", ""):sub(1, 60) or "" end
	return { p = p, l = v[2] == 1 or nil, v = Plain(name), z = Plain(place) }
end

-- { p = copper, l = limited stock, v = vendor, z = place, t = seen }, or nil
function DB.Vendor(item)
	local row = type(item) == "number" and DB.Row("vendor:" .. item)
	local x = row and ParseVendor(row.v)
	if x then x.t = row.t end
	return x
end

-- all of them: { [item] = as DB.Vendor gives it }
function DB.Vendors() return DB.Table("vendor", ParseVendor) end

-- the row's text for a price seen
function DB.VendorText(price, limited, vendor, place)
	return L.Pack({ price, limited and 1 or 0, vendor, place }, 4)
end

-- Many rows of one chunk at once, from a source that is not us (the import of base rows): a row is put in where
-- there is none, one we wrote down in play (L.Wins: a source's row stands over a sighting of the same thing),
-- or one of the same source that is older or, of the same time, says something else. A newer one stays: it came
-- from a guildmate who has a later version of the source than this machine.
function DB.Fill(chunk, values, src, t)
	local rows, changed = Rows(chunk), false
	for key, value in pairs(values) do
		value = L.Clean(value)
		local at = rows[key]
		if not at or not L.Base(at) or (at.src == src and (at.t < t or (at.t == t and at.v ~= value))) then
			rows[key], changed = { t = t, src = src, v = value }, true
		end
	end
	if changed then Write(chunk, rows) end
end

-- rows of any chunks at once: { [key] = value }, each into the chunk it belongs in
function DB.FillRows(values, src, t)
	local chunks = {}
	for key, value in pairs(values) do
		local chunk = L.ChunkOf(key)
		chunks[chunk] = chunks[chunk] or {}
		chunks[chunk][key] = value
	end
	for chunk, rows in pairs(chunks) do DB.Fill(chunk, rows, src, t) end
end

-- The fingerprints of a source's rows, a chunk each: { ["fp:<source>:<chunk>"] = hash } for the rows given
-- ({ [key] = value }). They are rows of the source themselves, written beside what they are of.
function DB.Prints(values, src)
	local chunks, out = {}, {}
	for key, value in pairs(values) do
		local chunk = L.ChunkOf(key)
		chunks[chunk] = chunks[chunk] or {}
		chunks[chunk][key] = L.Clean(value)
	end
	for chunk, rows in pairs(chunks) do out["fp:" .. src .. ":" .. chunk] = L.PrintOf(rows) end
	return out
end

-- which version of a source the base rows are of (version given: it is set)
function DB.Base(source, version)
	local db = Store()
	if type(db.base) ~= "table" then db.base = {} end
	if version then db.base[source] = version end
	return db.base[source]
end

-- every chunk's hash, and the one hash of the whole: two installs with the same rows have the same
function DB.Hashes() return Store().hash end
function DB.Root() return L.Roll(Store().hash) end
function DB.Text(chunk) return Store().chunks[chunk] end

-- Who can say what a source's row should be: a machine that has the source itself (QuestieDB installed, the
-- seed addon). DB.Referee("questie", function(key) return the row's values as this machine's source gives them,
-- and the time rows of this version carry; nothing where it cannot say end)
local referees = {}
function DB.Referee(src, fn) referees[src] = fn end

-- A chunk as another install has it, laid into mine: the rows of theirs that are newer are taken, as they are.
-- My own counters are never taken from the wire. Returns how many rows were taken.
-- A row taken that this machine's own source contradicts (same source, same version, other values: a broken
-- or meddled-with store somewhere) is put right, a moment later than the wrong one, so that the right one
-- stands here and wherever the two meet from now on.
function DB.Take(chunk, text)
	if type(chunk) ~= "string" or type(text) ~= "string" then return 0 end
	-- (a chunk name is what ChunkOf makes: letters, then a number or "s" and a sum; a peer's own names would grow the store without end)
	local what, s, n = chunk:match("^(%a+):(s?)(%d+)$")
	if not what or #what > 12 or tonumber(n) > (s == "" and 4000 or 63) then return 0 end
	local theirs = {}
	for key, row in pairs(L.Parse(text)) do
		-- (only rows that belong in this chunk: a row filed elsewhere would never be found again)
		if L.ChunkOf(key) == chunk then theirs[key] = row end
	end
	-- A source's rows are checked against the fingerprint its importer wrote for this chunk, where I hold it
	-- (it comes first in a fill): rows of that version that do not add up to it are wrong somewhere, and as
	-- there is no telling where, none of them is taken from this member. A machine without the source can so
	-- tell a broken copy from a whole one. (Rows of another version than the fingerprint's are not its to say.)
	local bySrc = {}
	for key, row in pairs(theirs) do
		if L.Base(row) then
			bySrc[row.src] = bySrc[row.src] or {}
			bySrc[row.src][key] = row
		end
	end
	for src, rows in pairs(bySrc) do
		local print = DB.Row("fp:" .. src .. ":" .. chunk)
		if print and print.src == src then
			local t0, values = print.t - print.t % 10, {}
			for key, row in pairs(rows) do
				if row.t >= t0 and row.t <= t0 + L.REPAIRS then values[key] = row.v end
			end
			if next(values) and L.PrintOf(values) ~= print.v then
				for key in pairs(values) do
					theirs[key] = nil
					DB.refused = (DB.refused or 0) + 1
				end
			end
		end
	end
	local mine = Rows(chunk)
	local me = ":" .. DB.Origin() .. "$"
	local taken = L.Merge(mine, theirs, DT.Now(), function(key) return key:find(me) ~= nil end)
	if taken > 0 then
		for key, row in pairs(theirs) do
			local at, judge = mine[key], referees[row.src or ""]
			if judge and at and at.t == row.t and at.v == row.v then
				local ok, want, t = pcall(judge, key)
				if ok and type(want) == "string" and type(t) == "number" and row.t >= t and row.t < t + L.REPAIRS and L.Clean(want) ~= row.v then
					mine[key] = { t = row.t + 1, src = row.src, v = L.Clean(want) }
					DB.repaired = (DB.repaired or 0) + 1
				end
			end
		end
		Write(chunk, mine)
		if chunk:find("^o?loot:") then DB.ForgetHolders() end
	end
	return taken
end

-- what is in it, for /dt db
function DB.Stats()
	local db = Store()
	local chunks, bytes, rows = 0, 0, 0
	for _, text in pairs(db.chunks) do
		chunks, bytes = chunks + 1, bytes + #text
		rows = rows + select(2, text:gsub("[^\n]+", ""))
	end
	return { chunks = chunks, bytes = bytes, rows = rows, root = DB.Root(), origin = db.origin }
end

---------------------------------------------------------------------------
-- The store, read the way QuestieDB is read
---------------------------------------------------------------------------
-- DB.Lib(): QuestieDB where it is installed. Else the store: the base rows a guildmate's QuestieDB was imported
-- into (Core/DBImport.lua; they come with the sync) and what was written down in play (Modules/Finds.lua),
-- answering in QuestieDB's own shapes, so that the tabs read either the same way:
--   lib.Npc / Item / Quest / Object: GetAllIds(), Get(id, field), GetAll(id, fields)
--   lib.Enum.npcFlags, lib.Enum.raceMaskById; lib.Support.Get("QuestXP").db[quest], ("ZoneDB").private.areaIdToUiMapId
--   lib.store = true: it is the store that answers
-- nil where neither is there.
--
-- A base row is "name;values": the values of DB.FIELDS[kind], in that order (DBLogic.Pack). Every field
-- QuestieDB has of a thing, bar its translations; long lists and paths are
-- cut short (Core/DBImport.lua says where). A new field goes at the END of its list, so that rows written
-- before it are still read right; and I.FORMAT (Core/DBImport.lua) goes up, so that everyone imports anew.
-- A row written down in play is "name;..." as Modules/Finds.lua writes it: DB.Sighting takes it apart.
DB.FIELDS = {
	npc = { "minLevel", "maxLevel", "rank", "zoneID", "friendlyToFaction", "subName", "npcFlags", "spawns", "questStarts", "questEnds", "waypoints",
		"factionID" },
	item = { "requiredLevel", "itemLevel", "class", "subClass", "npcDrops", "objectDrops", "itemDrops", "vendors", "questRewards", "startQuest", "teachesSpell",
		"flags", "foodType", "ammoType", "relatedQuests" },
	quest = { "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "zoneOrSort", "preQuestGroup", "preQuestSingle", "nextQuestInChain",
		"questFlags", "specialFlags", "exclusiveTo", "requiredSkill", "startedBy", "parentQuest", "breadcrumbForQuestId", "requiredMinRep",
		"requiredMaxLevel", "finishedBy", "sourceItemId", "objectivesText", "xp",
		"objectives", "triggerEnd", "childQuests", "inGroupWith", "requiredMaxRep", "requiredSourceItems", "reputationReward", "breadcrumbs",
		"extraObjectives", "requiredSpell", "requiredSpecialization", "availableUntilCompleted", "availableStartingWith", "requiredRanks", "disabledByQuest" },
	object = { "zoneID", "spawns", "questStarts", "questEnds", "factionID", "waypoints" },
}

-- What a row written down in play says: { name, level (an NPC's), giver (a quest's), quality (an item's),
-- zone (its name), x, y (0-100, on the map I was on), near (I stood at it), map (that map's number) }
function DB.Sighting(kind, v)
	local name, rest = (v or ""):match("^([^;]*);?(.*)$")
	local p = {}
	for part in (rest .. ";"):gmatch("([^;]*);") do p[#p + 1] = part end
	local s = { name = name }
	if kind == "item" then
		s.quality = tonumber(p[1])
		return s
	end
	if kind == "npc" then s.level = tonumber(p[1]) elseif kind == "quest" then s.giver = tonumber(p[1]) end
	s.zone, s.x, s.y = p[2] ~= "" and p[2] or nil, tonumber(p[3]), tonumber(p[4])
	s.near = p[5] == "1" or (kind == "quest" and s.x ~= nil) -- (a quest is offered by someone I stand at)
	s.map = tonumber(rest:match(";m(%d+)"))
	return s
end

local shim, thing = nil, {} -- (thing: the last one taken apart, as several fields of one are asked for in a row)

local function Thing(kind, id)
	if type(id) ~= "number" then return nil end
	local key = kind .. ":" .. id
	if thing.key == key and thing.stamp == stamp then return thing.fields end
	local row, fields = DB.Row(key), nil
	if row and L.Base(row) then
		local name, rest = row.v:match("^([^;]*);?(.*)$")
		local values = L.Unpack(rest) or {}
		fields = { name = name }
		for i, field in ipairs(DB.FIELDS[kind] or {}) do fields[field] = values[i] end
	elseif row then
		local s = DB.Sighting(kind, row.v)
		fields = { name = s.name, seen = s, minLevel = s.level, maxLevel = s.level, startedBy = s.giver and { { s.giver } } or nil }
	end
	thing = { key = key, stamp = stamp, fields = fields }
	return fields
end
DB.Stored = Thing -- what the store itself holds of a thing, whoever else knows it: its fields by name, or nil

local function Entity(kind)
	return {
		GetAllIds = function()
			local ids = {}
			for chunk, text in pairs(Store().chunks) do
				if chunk:match("^(%a+):") == kind then
					for id in ("\n" .. text):gmatch("\n" .. kind .. ":(%d+)\t") do ids[#ids + 1] = tonumber(id) end
				end
			end
			table.sort(ids)
			return ids
		end,
		Get = function(id, field)
			local fields = Thing(kind, id)
			return fields and fields[field]
		end,
		GetAll = function(id, names)
			local fields = Thing(kind, id)
			if not fields then return nil end
			local out = {}
			for i, field in ipairs(names) do out[i] = fields[field] end
			return out
		end,
	}
end

-- a table of QuestieDB's own (what its flags are called, which bit a race is), kept as one row
local function Enum(name)
	local row = DB.Row("enum:" .. tostring(name))
	local list = row and (L.Unpack(row.v) or {})[1]
	if type(list) ~= "table" then return nil end
	if type(list[1]) ~= "string" then return list end
	local out = {} -- (names cannot be keys of a packed list: kept as name, value, name, value)
	for i = 1, #list, 2 do out[list[i]] = list[i + 1] end
	return out
end

local function Shim()
	if shim then return shim end
	shim = { store = true, Enum = setmetatable({}, { __index = function(_, name) return Enum(name) end }) }
	for kind, entity in pairs(ENTITY) do shim[entity] = Entity(kind) end
	local support = {
		QuestXP = { db = setmetatable({}, { __index = function(_, id) return shim.Quest.Get(id, "xp") end }) },
		ZoneDB = { private = { areaIdToUiMapId = setmetatable({}, { __index = function(_, area)
			local row = type(area) == "number" and DB.Row("zone:" .. area)
			return row and tonumber(row.v) or nil
		end }) } },
	}
	shim.Support = { Get = function(name) return support[name] end }
	return shim
end

-- what a tab says where there is neither
DB.NEEDS = "Nothing to list yet. Install the QuestieDB addon (Questie itself is not needed), or share the game database (/dt db) and a guildmate who has it fills yours."

local holds = { stamp = -1 } -- does the store hold things at all
function DB.Lib()
	local lib = Questie()
	if lib then return lib end
	if holds.stamp ~= stamp then
		holds = { stamp = stamp, any = false }
		for chunk in pairs(Store().chunks) do
			if chunk:find("^npc:") or chunk:find("^item:") or chunk:find("^quest:") then holds.any = true break end
		end
	end
	return holds.any and Shim() or nil
end

---------------------------------------------------------------------------
-- Loot: every corpse and every thing gathered or opened, counted (phase 4 of docs/DATA.md)
---------------------------------------------------------------------------
-- A counter a mob (or object) and origin: "loot:<npc>:<origin>" / "oloot:<object>:<origin>" = times looted, and
-- for each item of uncommon quality or better how often it was in there. Counted once a corpse a session, and
-- only where I see all of the loot: alone, or in a group with free-for-all loot or with me as master looter.
-- ponytail: a corpse looted in a group that rolls is not counted at all (the relation without a count is not
-- recorded yet); a corpse opened a second time (skinning after the kill) is left out, so one pickpocketed
-- before the kill counts the pickpocket's loot as the kill's; an empty corpse never opens, so a chance reads
-- a little high. Fishing is Fish.lua's.

local looted = {} -- [corpse] = true: counted this session
local byItem      -- [item] = { [what .. id] = true }: who was seen to hold an item; built on the first ask

local function SeeAll()
	-- (inside a dungeon or raid the window is counted whatever the loot method: what Dungeons did before its count and this one were one)
	local inside, kind
	if IsInInstance then inside, kind = IsInInstance() end
	if inside and (kind == "party" or kind == "raid") then return true end
	if not (IsInGroup and IsInGroup()) then return true end
	if not GetLootMethod then return false end
	local method, master = GetLootMethod()
	return method == "freeforall" or (method == "master" and master == 0)
end

-- what was looted of a mob or object by all origins together: times, { [item] = times seen }
-- (kind "boss": a dungeon boss the list knows by no NPC number, id its "dungeon/boss" key: "bloot:<key>:<origin>",
-- filed by its letters, so every chunk of that kind is read; there are few)
function DB.Looted(kind, id)
	local prefix = (kind == "boss" and "bloot:" or kind == "object" and "oloot:" or "loot:") .. id .. ":"
	local n, items = 0, {}
	local function Add(rows)
		for key, row in pairs(rows) do
			if key:sub(1, #prefix) == prefix then
				local times, seen = L.Counted(row.v)
				n = n + times
				for item, k in pairs(seen) do items[item] = (items[item] or 0) + k end
			end
		end
	end
	if kind == "boss" then
		for chunk, text in pairs(Store().chunks) do
			if chunk:find("^bloot:") then Add(L.Parse(text)) end
		end
	else
		Add(Rows(L.ChunkOf(prefix .. "x")))
	end
	return n, items
end

local function Holders(item)
	if not byItem then
		byItem = {}
		for chunk in pairs(Store().chunks) do
			if chunk:find("^o?loot:") then
				for key, row in pairs(L.Parse(Store().chunks[chunk])) do
					local what, id = key:match("^(o?loot):(%d+):")
					local _, seen = L.Counted(row.v)
					for it in pairs(what and seen or {}) do
						byItem[it] = byItem[it] or {}
						byItem[it][(what == "oloot" and "object:" or "npc:") .. id] = true
					end
				end
			end
		end
	end
	return byItem[item] or {}
end

function DB.ForgetHolders() byItem = nil end

-- (a count of mine laid into the holders at once: rebuilding them reads every loot chunk, a lag at the next tooltip)
local function Held(what, id, items)
	if not byItem or (what ~= "loot" and what ~= "oloot") then return end
	for item in pairs(items) do
		byItem[item] = byItem[item] or {}
		byItem[item][(what == "oloot" and "object:" or "npc:") .. id] = true
	end
end

-- My own counter of a mob, chest or boss: its key, how many times, and { [item] = times seen }
local function Mine(what, id)
	local key = what .. ":" .. id .. ":" .. DB.Origin()
	local row = DB.Row(key)
	local n, seen = L.Counted(row and row.v)
	return key, n, seen
end

-- one more corpse, chest or node of mine: what = "loot" (a mob), "oloot" (an object) or "bloot" (a dungeon boss
-- with no NPC number); items = { [item] = true }, what was in it
function DB.Count(what, id, items)
	local key, n, seen = Mine(what, id)
	for item in pairs(items) do seen[item] = (seen[item] or 0) + 1 end
	DB.Put(key, L.Counter(n + 1, seen))
	Held(what, id, items)
end

-- A count from a store of before (the Dungeons tab's own) laid under my origin: the larger of it and what I hold,
-- per item too, so that nothing is lost, nothing is counted twice, and running it again changes nothing.
function DB.Raise(what, id, n, items)
	local key, had, seen = Mine(what, id)
	for item, k in pairs(items) do seen[item] = math.max(seen[item] or 0, k) end
	DB.Put(key, L.Counter(math.max(had, n), seen))
	Held(what, id, items)
end

-- the loot window is open
-- (DB.lootSeen, DB.lootSaid: how many loot windows this session, and what became of the last: for /dt db, as
-- nobody has seen yet what this server's loot window tells an addon)
DB.lootSeen, DB.lootSaid, DB.lootCounted, DB.lootEmpty = 0, "none yet", 0, 0
function DB.Loot()
	DB.lootSeen = DB.lootSeen + 1
	if not (GetNumLootItems and GetLootSourceInfo) then DB.lootSaid = "the game has no GetLootSourceInfo here" return end
	if not SeeAll() then DB.lootSaid = "in a group whose loot I do not see all of (" .. tostring(GetLootMethod and GetLootMethod()) .. ")" return end
	if IsFishingLoot and IsFishingLoot() then DB.lootSaid = "fishing: Fish's" return end
	-- (with auto loot the window is told of twice, the second time empty: that says nothing, and is only counted)
	if (GetNumLootItems() or 0) == 0 then DB.lootEmpty = DB.lootEmpty + 1 return end
	DB.lootSaid = ("%d slots, no source named for any"):format(GetNumLootItems())
	local by = {} -- [corpse] = { [item] = true }
	for slot = 1, GetNumLootItems() do
		-- (one slot may be the loot of several corpses, looted at once: corpse, how many, corpse, how many, ...)
		local sources = { GetLootSourceInfo(slot) }
		local link = GetLootSlotLink and GetLootSlotLink(slot)
		local item = link and tonumber(tostring(link):match("item:(%d+)"))
		local _, _, _, _, quality = GetLootSlotInfo(slot)
		for i = 1, #sources, 2 do
			local guid = sources[i]
			if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
				by[guid] = by[guid] or {}
				if item and (tonumber(quality) or 0) >= 2 then by[guid][item] = true end
			end
		end
	end
	for guid, items in pairs(by) do
		local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
		local what = (kind == "Creature" or kind == "Vehicle") and "loot" or kind == "GameObject" and "oloot" or nil
		DB.lootSaid = not what and ("a source that is neither mob nor object: " .. guid) or looted[guid] and ("counted already: " .. guid) or ("counted: " .. guid)
		if what and not looted[guid] then
			DB.lootCounted = DB.lootCounted + 1
			looted[guid] = true
			DB.Count(what, id, items)
		end
	end
end
DT:On("LOOT_OPENED", function() DB.Loot() end)
DT:On("LOOT_READY", function() DB.Loot() end)

-- what we counted, laid into the answers: a mob's drops, and who drops an item
local function Ours(facts, kind, n, k)
	for _, fact in ipairs(facts) do
		if fact.kind == kind.kind and fact.id == kind.id and not fact.n then
			fact.n, fact.k = n, k
			return
		end
	end
	facts[#facts + 1] = { kind = kind.kind, id = kind.id, src = "guild", n = n, k = k }
end

local shippedDropsOfNpc, shippedDropsOfItem = FROM.drops.npc, TO.drops.item
FROM.drops.npc = function(id)
	local facts = shippedDropsOfNpc(id)
	local n, items = DB.Looted("npc", id)
	for item, k in pairs(items) do Ours(facts, { kind = "item", id = item }, n, k) end
	return facts
end
FROM.drops.object = function(id)
	local facts = {}
	local n, items = DB.Looted("object", id)
	for item, k in pairs(items) do Ours(facts, { kind = "item", id = item }, n, k) end
	return facts
end
TO.drops.item = function(id)
	local facts = shippedDropsOfItem(id)
	for holder in pairs(Holders(id)) do
		local kind, from = holder:match("^(%a+):(%d+)$")
		from = tonumber(from)
		local n, items = DB.Looted(kind, from)
		if n > 0 then Ours(facts, { kind = kind, id = from }, n, items[id] or 0) end
	end
	return facts
end

---------------------------------------------------------------------------
-- Measuring (phase 2 of docs/DATA.md: goes when the numbers are in)
---------------------------------------------------------------------------
-- Two things nobody knows yet and the store and its sync are sized by:
--   what a saved file of 60,000 rows costs at login and in memory    /dt db bench make, /reload, /dt db bench read
--   how many addon whispers the server lets through                   /dt db bench send [count] [name], and on
--                                                                     the other character /dt db bench got
-- ponytail: a test, not a feature. Nothing of it runs unless typed.

local PREFIX = "DAWNB"
local got = { n = 0, bytes = 0 }

local function Memory()
	if not collectgarbage then return 0 end
	collectgarbage("collect")
	return collectgarbage("count")
end

local function Make()
	local before = Memory()
	local chunks, rows, bytes = {}, 0, 0
	for c = 1, 240 do
		local lines = {}
		for r = 1, 250 do
			local id = c * 256 + r
			lines[r] = ("%d;o%02d;%d;%d;%d:%d,%d:%d,%d:%d"):format(id, r % 30, 20 + r % 80, 1760000000 + id, 2000 + r, r % 9, 3000 + r, r % 5, 4000 + r, r % 3)
		end
		chunks[c] = table.concat(lines, "\n")
		rows, bytes = rows + #lines, bytes + #chunks[c]
	end
	DawnToolsDB.dbBench = chunks
	DT:Print("db bench: %d rows in %d chunks, %.1f MB of text, %.1f MB of memory. Now /reload (time it by hand), then /dt db bench read.", rows, #chunks, bytes / 1048576, (Memory() - before) / 1024)
end

local function Read()
	local chunks = DawnToolsDB.dbBench
	if type(chunks) ~= "table" then return DT:Print("db bench: nothing made yet (/dt db bench make).") end
	local t0, rows = debugprofilestop and debugprofilestop() or 0, 0
	for _, chunk in ipairs(chunks) do
		for line in chunk:gmatch("[^\n]+") do
			if line:match("^(%d+);") then rows = rows + 1 end
		end
	end
	DT:Print("db bench: %d rows read through in %.0f ms (every chunk; a look at one thing reads one chunk). Memory in use by all addons: %.1f MB.", rows, (debugprofilestop and debugprofilestop() or 0) - t0, Memory() / 1024)
end

local probes = {} -- [a way of writing a name] = true once a probe sent to it came in

-- The ways a character might be addressed here: on Forever a character is "First Surname", and how a whisper
-- wants that written is not known: each is tried with one whisper, and the one that arrives is used.
local function Addresses(unit)
	local first, last = UnitName(unit), nil
	if UnitFullName then first, last = UnitFullName(unit) end
	local out = {}
	if type(first) ~= "string" then return out end
	if type(last) == "string" and last ~= "" then
		out = { first .. "-" .. last, first .. " " .. last, first .. last, first .. "-" .. last:gsub("%s", "") }
	end
	out[#out + 1] = first
	return out
end

local Send
local function Probe(count, unit)
	local tries = Addresses(unit)
	if #tries == 0 or not ChatThrottleLib then return DT:Print("db bench: no name to whisper to: /dt db bench send 200 Name") end
	probes = {}
	for _, name in ipairs(tries) do
		ChatThrottleLib:SendAddonMessage("BULK", PREFIX, "probe;" .. name, "WHISPER", name)
	end
	DT:Print("db bench: finding how a whisper to %s is addressed (the game will say \"no player named\" for the ways that are wrong)...", tries[#tries])
	C_Timer.After(4, function()
		for _, name in ipairs(tries) do
			if probes[name] then
				DT:Print("db bench: a whisper addressed to \"%s\" arrives.", name)
				return Send(count, name)
			end
		end
		DT:Print("db bench: none of these arrived: %s. If that was another player, they need this version of DawnTools too.", table.concat(tries, " / "))
	end)
end

function Send(count, name)
	count = math.max(1, math.min(tonumber(count) or 200, 2000))
	-- (nobody named: the player targeted, else myself. A whisper to oneself goes to the server and back all the same.)
	if not name or name == "" then
		return Probe(count, UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") and "target" or "player")
	end
	if not ChatThrottleLib then return end
	local t0, sent = GetTime(), 0
	local body = ("x"):rep(220)
	for i = 1, count do
		ChatThrottleLib:SendAddonMessage("BULK", PREFIX, ("%d/%d;%s"):format(i, count, body), "WHISPER", name, nil, function()
			sent = sent + 1
			if sent == count then
				DT:Print("db bench: %d whispers of %d bytes handed to the game in %.0f s (%.0f bytes a second). On %s: /dt db bench got", count, #body + 10, GetTime() - t0, count * (#body + 10) / math.max(0.1, GetTime() - t0), name)
			end
		end)
	end
	DT:Print("db bench: %d whispers to %s queued. Then /dt db bench got (on that character). If none arrive, try the name with its surname.", count, name)
end

local function Got()
	if got.n == 0 then return DT:Print("db bench: no test whispers have come in.") end
	local span = math.max(0.1, (got.last or 0) - (got.first or 0))
	DT:Print("db bench: %d of %d whispers came in from %s, %d bytes in %.0f s (%.0f bytes a second). Missing: %d.", got.n, got.of or 0, tostring(got.from), got.bytes, span, got.bytes / span, (got.of or 0) - got.n)
	got = { n = 0, bytes = 0 }
end

function DB.Slash(rest)
	if (rest or ""):match("^%s*sync%s*$") then
		local n = DT.DBSync and DT.DBSync.Now()
		if n == nil then return DT:Print("db sync: sharing is off (/dt settings).") end
		return DT:Print("db sync: a hello sent; asked %d sharing member%s for their game database list now. Settings, Data Sync shows how it goes.", n, n == 1 and "" or "s")
	end
	local cmd, a, b = (rest or ""):match("^%s*bench%s*(%S*)%s*(%d*)%s*(.-)%s*$")
	if cmd == "make" then Make()
	elseif cmd == "read" then Read()
	elseif cmd == "clear" then
		DawnToolsDB.dbBench = nil
		DT:Print("db bench: the test rows are gone (after the next /reload, from the saved file too).")
	elseif cmd == "send" then Send(a, b)
	elseif cmd == "got" then Got()
	else
		if DT.DBSync then DT.DBSync.Ask() end
		local s = DB.Stats()
		DT:Print("db: %d rows in %d chunks, %.1f KB; hash %s; this install's origin %s.", s.rows, s.chunks, s.bytes / 1024, s.root, s.origin)
		local Im = DT.DBImport
		DT:Print("db: base rows: %s.", DB.Base("questie") and ("of QuestieDB " .. DB.Base("questie")) or Im and Im.total > 0 and Im.done < Im.total and ("being imported from QuestieDB, %d of %d"):format(Im.done, Im.total)
			or DB.Row("base:questie") and ("a guildmate's, of QuestieDB " .. DB.Row("base:questie").v)
			or "none of this install's own (QuestieDB not installed, or not read yet); a guildmate's come with sharing")
		if DT.DBSeed then DT:Print("db: %s.", DT.DBSeed.Status()) end
		if (DB.refused or 0) > 0 then DT:Print("db: %d rows offered by guild members were not taken: they did not add up to what their source should give.", DB.refused) end
		if (DB.repaired or 0) > 0 then DT:Print("db: %d rows that came from the guild were wrong by this machine's own source, and were put right.", DB.repaired) end
		DT:Print("db: %d loot windows seen since the last /reload (%d of them empty when looked at), %d corpses, chests or nodes counted; the last that held something: %s.", DB.lootSeen, DB.lootEmpty, DB.lootCounted, DB.lootSaid)
		DT:Print("/dt db sync | bench make | read | clear | send [count] [name] | got")
	end
end

DT:On("PLAYER_LOGIN", function()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end)
DT:On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
	if prefix ~= PREFIX or type(text) ~= "string" then return end
	local ack = text:match("^probeack;(.+)$")
	if ack then
		probes[ack] = true
		return
	end
	local probe = text:match("^probe;(.+)$")
	if probe then
		-- (one of mine come back to me; or another's come in, who is told which way of writing my name arrived.
		-- The sender as the game names it is an address that works.)
		probes[probe] = true
		if type(sender) == "string" and ChatThrottleLib then ChatThrottleLib:SendAddonMessage("BULK", PREFIX, "probeack;" .. probe, "WHISPER", sender) end
		return
	end
	local of = tonumber(text:match("^%d+/(%d+);"))
	got.n, got.bytes, got.of, got.from = got.n + 1, got.bytes + #text, of or got.of, sender
	got.first, got.last = got.first or GetTime(), GetTime()
end)
