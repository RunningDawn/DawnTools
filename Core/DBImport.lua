-- DawnTools :: DB import
-- The base rows of the store (Core/DB.lua): what an installed QuestieDB knows of NPCs, items, quests and objects,
-- written into the store once per version of it, in the background. A member without QuestieDB then gets these
-- rows from guildmates with the rest of the store, where the game database is shared (Core/DBSync.lua), and the
-- tabs read them as they would read QuestieDB (DB.Lib).
--
--   npc:<n> / item:<n> / quest:<n> / object:<n>  = name;values    the values of DB.FIELDS[kind], packed (DBLogic.Pack)
--   zone:<area>                                  = the number of the map that area is drawn on
--   enum:npcFlags, enum:raceMaskById             = QuestieDB's own tables of what a flag or a race's bit is
--   base:questie                                 = which QuestieDB these rows are of
-- Source "questie", and for a time the number of its version (DBLogic.VersionTime): every install that imports
-- the same QuestieDB writes the very same text, so their chunks hash the same and nothing needs passing between
-- them; and where two members have different versions, the later one's rows stand for the whole guild. Zones
-- are kept by number, not by name, so that a client in another language writes the same.
-- Every field QuestieDB has of a thing is taken (DB.FIELDS), cut short where it is long: of a thing's places
-- the first SPOTS, of a list (who drops an item, which quests an NPC gives) the first LIST, of what a quest
-- asks the first TEXT letters, of the paths an NPC or object walks the first STEPS steps. Not taken:
-- translations (the names are those of the importing machine's QuestieDB: English). A row that is still too
-- long loses its last fields, one by one, until it fits.
-- Licence: see docs/DATA.md and THIRD_PARTY_LICENSES.txt.

local _, DT = ...
local DB, L = DT.DB, DT.DBLogic
local I = { BATCH = 100, done = 0, total = 0, SPOTS = 8, STEPS = 16, LIST = 40, TEXT = 300 }
DT.DBImport = I
I.FORMAT = 6 -- (the shape of the rows: a change of it imports anew)

local ENTITIES = { { "npc", "Npc" }, { "item", "Item" }, { "quest", "Quest" }, { "object", "Object" } }
local work -- { e = which entity, at, chunk, rows, version }

local function Lib()
	local lib = DB.Questie()
	if not lib then return nil end
	for _, e in ipairs(ENTITIES) do
		if not (lib[e[2]] and lib[e[2]].GetAllIds and lib[e[2]].Get) then return nil end
	end
	return lib
end

-- which QuestieDB this is: its build, else its version (number: its version alone, which says which is later)
function I.Version(number)
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	for _, field in ipairs(number and { "Version" } or { "X-BUILD-COMMIT", "Version" }) do
		local ok, value = pcall(function() return meta and meta("QuestieDB", field) end)
		if ok and type(value) == "string" and value ~= "" then return value end
	end
	return "1"
end

-- a list of numbers, the first so many of it
local function Short(list, most)
	if type(list) ~= "table" then return nil end
	local out = {}
	for i = 1, math.min(#list, most) do
		if type(list[i]) == "number" then out[#out + 1] = list[i] end
	end
	return out[1] and out or nil
end

-- { { npcs }, { objects }, { items } }: who starts or ends a quest, each list cut short
local function Who(who, most)
	if type(who) ~= "table" then return nil end
	local out = {}
	for i = 1, 3 do out[i] = Short(who[i], most) end
	return next(out) and out or nil
end

-- the areas a thing has places in, its own zone first
local function Areas(by, zone)
	local areas = {}
	for area, list in pairs(by) do
		if type(area) == "number" and type(list) == "table" then areas[#areas + 1] = area end
	end
	table.sort(areas, function(a, b)
		if (a == zone) ~= (b == zone) then return a == zone end
		return a < b
	end)
	return areas
end

local function Tenth(n) return math.floor(n * 10 + 0.5) / 10 end

-- { [area] = { path, ... } }, a path { { x, y }, ... }: the first so many steps of what it walks, to one decimal
local function Paths(paths, zone, most)
	if type(paths) ~= "table" then return nil end
	local out, n = {}, 0
	for _, area in ipairs(Areas(paths, zone)) do
		for _, path in ipairs(paths[area]) do
			local steps = {}
			for _, s in ipairs(type(path) == "table" and path or {}) do
				if n < most and type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then
					steps[#steps + 1], n = { Tenth(s[1]), Tenth(s[2]) }, n + 1
				end
			end
			if steps[1] then
				out[area] = out[area] or {}
				table.insert(out[area], steps)
			end
		end
	end
	return next(out) and out or nil
end

-- { [area] = { { x, y }, ... } }: the first so many places, those of its own zone first, to one decimal
local function Spots(spawns, zone, most)
	if type(spawns) ~= "table" then return nil end
	local areas = Areas(spawns, zone)
	local out, n = {}, 0
	for _, area in ipairs(areas) do
		for _, s in ipairs(spawns[area]) do
			if n < most and type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then
				out[area] = out[area] or {}
				table.insert(out[area], { Tenth(s[1]), Tenth(s[2]) })
				n = n + 1
			end
		end
	end
	return next(out) and out or nil
end

-- a field as it is kept: cut short where it can be long (most: how long a list may be; of places, SPOTS to LIST of that)
local KEEP = {
	spawns = function(v, get, most) return Spots(v, get("zoneID"), math.max(1, math.floor(most * I.SPOTS / I.LIST))) end,
	waypoints = function(v, get, most) return Paths(v, get("zoneID"), math.max(2, math.floor(most * I.STEPS / I.LIST))) end,
	startedBy = function(v, _, most) return Who(v, most) end,
	finishedBy = function(v, _, most) return Who(v, most) end,
	objectivesText = function(v)
		local out = {}
		for _, text in ipairs(type(v) == "table" and v or {}) do
			if type(text) == "string" and #out < 3 then out[#out + 1] = text:sub(1, I.TEXT) end
		end
		return out[1] and out or nil
	end,
}

local function Kept(field, v, get, most)
	if KEEP[field] then return KEEP[field](v, get, most) end
	if type(v) == "table" then
		-- (a short record, as "the skill asked for and how high", whole; a list of numbers cut short)
		for _, x in ipairs(v) do
			if type(x) ~= "number" then return v end
		end
		if next(v) == nil then return nil end
		return #v <= 4 and v or Short(v, most)
	end
	if type(v) == "number" or type(v) == "string" then return v end
end

-- the row of one thing, or nil where it has no name. most: how long its lists may be
function I.Row(lib, kind, entity, id, most)
	local function get(field)
		local ok, value = pcall(lib[entity].Get, id, field)
		if ok then return value end
	end
	local name = get("name")
	if type(name) ~= "string" or name == "" then return nil end
	local fields, values = DB.FIELDS[kind], {}
	for i, field in ipairs(fields) do
		local v
		if field == "xp" then
			local ok, xp = pcall(function() return lib.Support.Get("QuestXP").db[id] end)
			v = ok and type(xp) == "table" and { tonumber(xp[1]) or 0, tonumber(xp[2]) or 0 } or nil
		else
			v = get(field)
		end
		values[i] = Kept(field, v, get, most or I.LIST)
	end
	local head = L.Clean(name):gsub(";", ",") .. ";"
	local row = head .. L.Pack(values, #fields)
	-- (a row longer than the store takes: its lists shorter still; then without its last fields, as many as it takes)
	if #row > L.MAX_VALUE and (most or I.LIST) > 5 then return I.Row(lib, kind, entity, id, 5) end
	local last = #fields
	while #row > L.MAX_VALUE and last > 0 do
		values[last], last = nil, last - 1
		row = head .. L.Pack(values, #fields)
	end
	return row
end

-- QuestieDB's own small tables, as rows: which map an area is drawn on, and what its flags and race bits are;
-- and "base:questie", which says to whoever gets these rows which QuestieDB they are of
local function Tables(lib, version, t)
	local out = { ["base:questie"] = version }
	local ok, maps = pcall(function() return lib.Support.Get("ZoneDB").private.areaIdToUiMapId end)
	if ok and type(maps) == "string" then ok, maps = pcall(function() return (loadstring or load)(maps)() end) end
	for area, map in pairs(ok and type(maps) == "table" and maps or {}) do
		if type(area) == "number" and area > 0 and type(map) == "number" and map > 0 then out["zone:" .. area] = tostring(map) end
	end
	local enum = type(lib.Enum) == "table" and lib.Enum or {}
	if type(enum.npcFlags) == "table" then
		local names, list = {}, {}
		for name, bit in pairs(enum.npcFlags) do
			if type(name) == "string" and type(bit) == "number" then names[#names + 1] = name end
		end
		table.sort(names)
		for _, name in ipairs(names) do list[#list + 1], list[#list + 2] = name, enum.npcFlags[name] end
		out["enum:npcFlags"] = L.Pack({ list }, 1)
	end
	if type(enum.raceMaskById) == "table" then
		local list = {}
		for race, mask in pairs(enum.raceMaskById) do
			if type(race) == "number" and type(mask) == "number" then list[race] = mask end
		end
		out["enum:raceMaskById"] = L.Pack({ list }, 1)
	end
	for key, value in pairs(DB.Prints(out, "questie")) do out[key] = value end
	DB.FillRows(out, "questie", t)
end

-- is there something to import; begins it
function I.Start()
	if work then return true end
	local lib = Lib()
	if not lib or InCombatLockdown() then return false end
	local version = I.Version() .. "/" .. I.FORMAT
	if DB.Base("questie") == version then return false end
	work = { e = 1, at = 0, version = version, rows = {}, prints = {}, t = L.VersionTime(I.Version(true), I.FORMAT) }
	I.done, I.total = 0, 0
	for _, e in ipairs(ENTITIES) do
		local ok, ids = pcall(lib[e[2]].GetAllIds)
		e.ids = ok and type(ids) == "table" and ids or {}
		table.sort(e.ids)
		I.total = I.total + #e.ids
	end
	return true
end

-- a little more of it; true when all is in
function I.Step(ms)
	if not work then return true end
	local lib = Lib()
	if not lib then
		work = nil
		return true
	end
	local stop = debugprofilestop and debugprofilestop() + (ms or 2)
	local n = 0
	while work do
		local e = ENTITIES[work.e]
		local kind = e[1]
		work.at = work.at + 1
		local id = e.ids[work.at]
		-- (a chunk is written when the next id lies in another, and at the end of a kind)
		local chunk = id and L.ChunkOf(kind .. ":" .. id)
		if work.chunk and chunk ~= work.chunk then
			DB.Fill(work.chunk, work.rows, "questie", work.t)
			-- (and its fingerprint, for those who get this chunk from a guildmate: written at the end)
			for key, value in pairs(DB.Prints(work.rows, "questie")) do work.prints[key] = value end
			work.rows = {}
		end
		work.chunk = chunk
		if not id then
			work.e, work.at, work.chunk = work.e + 1, 0, nil
			if not ENTITIES[work.e] then
				pcall(Tables, lib, work.version, work.t)
				DB.FillRows(work.prints, "questie", work.t)
				DB.Base("questie", work.version)
				work = nil
				DT:Fire("DT_DB_UPDATE")
				return true
			end
		else
			local ok, row = pcall(I.Row, lib, kind, e[2], id)
			if ok and row then work.rows[kind .. ":" .. id] = row end
			I.done, n = I.done + 1, n + 1
			if (stop and debugprofilestop() > stop) or (not stop and n >= I.BATCH) then return false end
		end
	end
	return true
end

-- This machine has QuestieDB: it can say what a row of its version should be (DB.Take puts a wrong one right).
-- Only once its own import is done, and only of the things themselves.
local ENTITY = { npc = "Npc", item = "Item", quest = "Quest", object = "Object" }
DB.Referee("questie", function(key)
	local kind, id = key:match("^(%a+):(%d+)$")
	local print, n = key:match("^fp:questie:(%a+):(%d+)$")
	local lib = (ENTITY[kind] or ENTITY[print]) and Lib()
	if not lib or work or DB.Base("questie") ~= I.Version() .. "/" .. I.FORMAT then return nil end
	local t = L.VersionTime(I.Version(true), I.FORMAT)
	if kind then return I.Row(lib, kind, ENTITY[kind], tonumber(id)), t end
	-- (a fingerprint: of the rows this QuestieDB gives for the chunk)
	local rows, lo = {}, tonumber(n) * L.SPAN
	for _, at in ipairs(lib[ENTITY[print]].GetAllIds()) do
		if at >= lo and at < lo + L.SPAN then rows[print .. ":" .. at] = I.Row(lib, print, ENTITY[print], at) end
	end
	return next(rows) and DB.Prints(rows, "questie")[key] or nil, t
end)

-- (after the tabs' own lists, which are wanted sooner)
DT:On("PLAYER_LOGIN", function()
	DT:Background({ name = "QuestieDB into the store", Start = I.Start, Step = I.Step })
end)
