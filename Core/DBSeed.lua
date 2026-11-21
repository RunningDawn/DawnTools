-- DawnTools :: DB seed
-- The game data DawnTools once carried in its download is no longer in it: every recipe with its skill band,
-- what vendors ask for reagents, the dungeons with their bosses and loot. It lives in the store (Core/DB.lua) as
-- base rows and reaches a member as the rest of the store does: from guildmates who share the game database.
--
-- It gets INTO the store on a machine that has the (unpublished) seed addon beside DawnTools (and, for the dungeons, on
-- one with OneForAll installed: see Live, below): a folder that is in no
-- download and no repository, holding the data files as tools/craftskill.js and tools/dungeons.js write them
-- (global DawnToolsSeed: Recipes, VendorPrice, Dungeons, SkillUpVersion, OneForAllVersion). At load its tables
-- are written into the store, once per version of each source:
--   recipe:<spell>  = profession, learned at, yellow, green, grey, scroll, item made, how many, { reagent, count, ... }
--   vprice:<item>   = copper a vendor asks                                          (both: source "skillup")
--   boss:<n>        = dungeon, lowest level, highest, boss, NPC, rare, { item, chance, ... }   (source "oneforall";
--                     n: its place in the list, the bosses of a dungeon one after the other)
--   base:skillup, base:oneforall = which version the rows are of (and, of bosses, how many there are)
-- For a time the number of the source's version (DBLogic.VersionTime), as all base rows: every seed of the same
-- version writes the same text, and a later version's rows stand over an earlier one's wherever they meet.
--
-- And OUT of it for the tabs: DT.Recipes, DT.CraftSkill, DT.VendorPrice and DT.Dungeons are put together from
-- those rows at login and whenever a guildmate's rows come, in the shapes the data files had. Nothing is put in
-- place of a table whose rows the store does not hold.
-- Sources and licences (both GPL-3.0-or-later): THIRD_PARTY_LICENSES.txt.
-- ponytail: a recipe a later version of the source no longer has stays in the store (rows are never taken
-- out); a source that drops recipes wants a row that says "gone".

local ADDON, DT = ...
local DB, L = DT.DB, DT.DBLogic
local S = { FORMAT = 4, counts = {} }
DT.DBSeed = S

local KINDS = { recipe = true, vprice = true, boss = true, base = true }

---------------------------------------------------------------------------
-- In: the seed addon's tables as rows
---------------------------------------------------------------------------

-- the bosses of a list of dungeons as rows, and the row that says which version they are of and how many there are
local function BossRows(dungeons, version)
	local rows, n = {}, 0
	for _, d in ipairs(dungeons) do
		for _, b in ipairs(type(d) == "table" and type(d[4]) == "table" and d[4] or {}) do
			n = n + 1
			rows["boss:" .. n] = L.Pack({ d[1], d[2], d[3], b[1], b[2], b[3], b[4] }, 7)
		end
	end
	rows["base:oneforall"] = version .. ";" .. n
	return rows
end

-- the seed's tables as rows: of SkillUp Forever's, of OneForAll's ({ [key] = values }); nil where it has none
local function Rows(seed, source)
	if source == "skillup" then
		if type(seed.SkillUpVersion) ~= "string" or type(seed.Recipes) ~= "table" then return nil end
		local rows = { ["base:skillup"] = seed.SkillUpVersion }
		for spell, r in pairs(seed.Recipes) do
			if type(spell) == "number" and type(r) == "table" then rows["recipe:" .. spell] = L.Pack(r, 9) end
		end
		for item, copper in pairs(type(seed.VendorPrice) == "table" and seed.VendorPrice or {}) do
			if type(item) == "number" and type(copper) == "number" then rows["vprice:" .. item] = L.Pack({ copper }, 1) end
		end
		return rows, seed.SkillUpVersion
	end
	if type(seed.OneForAllVersion) ~= "string" or type(seed.Dungeons) ~= "table" then return nil end
	return BossRows(seed.Dungeons, seed.OneForAllVersion), seed.OneForAllVersion
end

-- An installed OneForAll as a source, as QuestieDB is (Core/DBImport.lua): its dungeons, bosses and drops in the
-- seed's own list shape, put together by the very rules tools/dungeons.js has for the data file, so that the same
-- version gives the same rows whichever way they came. Dungeons by level and name, a boss only where it drops
-- something, the trash last, an item once, a chance 0 where it has none.
-- nil, nil where it is not installed, has no version or has no list yet.
local function Live()
	local OFA = OneForAll
	if type(OFA) ~= "table" or type(OFA.DUNGEONS) ~= "table" then return nil end
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local got, version = pcall(function() return meta and meta("OneForAll", "Version") end)
	if not (got and type(version) == "string" and version ~= "") then return nil end
	local chances = type(OFA.DUNGEON_DROP_CHANCE) == "table" and OFA.DUNGEON_DROP_CHANCE or {}
	local list = {}
	for _, od in ipairs(OFA.DUNGEONS) do
		if type(od) == "table" and type(od.name) == "string" then
			local lo, hi = tostring(od.level or ""):match("(%d+)%D+(%d+)")
			if not lo then
				lo = tostring(od.level or ""):match("(%d+)")
				hi = lo
			end
			local byBoss = type(chances[od.name]) == "table" and chances[od.name] or {}
			local bosses = {}
			local function Boss(name, npc, rare, loot)
				local flat, seen = {}, {}
				for _, it in ipairs(type(loot) == "table" and loot or {}) do
					local id = type(it) == "table" and tonumber(it.id or it[1])
					if id and id > 0 and not seen[id] then
						seen[id] = true
						flat[#flat + 1], flat[#flat + 2] = id, tonumber(type(byBoss[name]) == "table" and byBoss[name][id]) or 0
					end
				end
				if flat[1] then bosses[#bosses + 1] = { name, tonumber(npc) or 0, rare and 1 or 0, flat } end
			end
			for _, b in ipairs(type(od.bosses) == "table" and od.bosses or {}) do
				if type(b) == "table" and type(b.name) == "string" then Boss(b.name, b.npcID, b.rare, b.loot) end
			end
			Boss("Trash", 0, false, od.trashLoot)
			if bosses[1] then list[#list + 1] = { od.name, tonumber(lo) or 0, tonumber(hi) or 0, bosses } end
		end
	end
	if not list[1] then return nil end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then return a[2] < b[2] end
		return a[1] < b[1]
	end)
	return list, version
end

-- True where something was written. The source of a version: the seed addon's tables and, for OneForAll, an
-- installed OneForAll as well; of the two the later version is written, whole, and the other not at all (never
-- a mix; and not each in turn at every login). Of the same version the seed's.
function S.Seed()
	local seed = type(DawnToolsSeed) == "table" and DawnToolsSeed or {}
	local did = false
	for _, source in ipairs({ "skillup", "oneforall" }) do
		local rows, version = Rows(seed, source)
		if source == "oneforall" then
			local live, lv = Live()
			if live and (not rows or L.VersionTime(lv, S.FORMAT) > L.VersionTime(version, S.FORMAT)) then
				rows, version = BossRows(live, lv), lv
			end
		end
		-- (with the fingerprint of each chunk of them, for those who get them from a guildmate)
		for key, value in pairs(rows and DB.Prints(rows, source) or {}) do rows[key] = value end
		if rows and DB.Base(source) ~= version .. "/" .. S.FORMAT then
			DB.FillRows(rows, source, L.VersionTime(version, S.FORMAT))
			DB.Base(source, version .. "/" .. S.FORMAT)
			did = true
		end
		-- (this machine has the seed: it can say what a row of its version should be; DB.Take puts a wrong one right)
		if rows then
			local t = L.VersionTime(version, S.FORMAT)
			DB.Referee(source, function(key) return rows[key], t end)
		end
	end
	return did
end

---------------------------------------------------------------------------
-- Out: the tables the tabs read, from the rows
---------------------------------------------------------------------------

local function Numbers(list, from, to)
	for i = from, to do
		if type(list[i]) ~= "number" then return false end
	end
	return true
end

-- a list of numbers and nothing else, of an even length (item, count, item, count)
local function Pairs(list)
	if type(list) ~= "table" or #list % 2 ~= 0 then return nil end
	for _, v in ipairs(list) do
		if type(v) ~= "number" then return nil end
	end
	return list
end

-- Rows come from other machines: one that is not of the shape is left out, not believed.
function S.Rebuild()
	local recipes, prices, bosses = {}, {}, {}
	local n = { recipe = 0, vprice = 0, boss = 0 }
	for chunk in pairs(DB.Hashes()) do
		local kind = chunk:match("^(%a+):")
		if kind == "recipe" or kind == "vprice" or kind == "boss" then
			for key, row in pairs(L.Parse(DB.Text(chunk))) do
				local id = tonumber(key:match("^%a+:(%d+)$"))
				local v = id and L.Base(row) and L.Unpack(row.v)
				if v and kind == "recipe" and Numbers(v, 1, 8) and Pairs(v[9] or {}) then
					recipes[id], n.recipe = { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9] or {} }, n.recipe + 1
				elseif v and kind == "vprice" and type(v[1]) == "number" then
					prices[id], n.vprice = v[1], n.vprice + 1
				elseif v and kind == "boss" and type(v[1]) == "string" and type(v[4]) == "string" and Numbers(v, 2, 3) and Numbers(v, 5, 6) and Pairs(v[7] or {}) then
					bosses[#bosses + 1], n.boss = { n = id, v = v }, n.boss + 1
				end
			end
		end
	end
	S.counts = n
	if n.recipe > 0 then
		-- (for an item: the band of the recipe that makes it and turns yellow soonest; the lower number between equals)
		local craft, by = {}, {}
		for spell, r in pairs(recipes) do
			local item, was = r[7], by[r[7]]
			if item > 0 and (not was or r[3] < recipes[was][3] or (r[3] == recipes[was][3] and spell < was)) then
				by[item], craft[item] = spell, { r[1], r[2], r[3], r[4], r[5], r[6] }
			end
		end
		DT.Recipes, DT.CraftSkill = recipes, craft
	end
	if n.vprice > 0 then DT.VendorPrice = prices end
	if n.boss > 0 then
		-- (only as many as the list has now: a longer one of before left rows behind)
		local base = DB.Row("base:oneforall")
		local most = base and tonumber(base.v:match(";(%d+)$")) or math.huge
		table.sort(bosses, function(a, b) return a.n < b.n end)
		local list, by = {}, {}
		for _, b in ipairs(bosses) do
			local v = b.v
			if b.n <= most then
				local d = by[v[1]]
				if not d then
					d = { v[1], v[2], v[3], {} }
					by[v[1]], list[#list + 1] = d, d
				end
				d[4][#d[4] + 1] = { v[4], v[5], v[6], v[7] or {} }
			end
		end
		DT.Dungeons = list
	end
	DT:Fire("DT_DATA_UPDATE")
end

-- for /dt db: what of it the store holds, and of which version
function S.Status()
	local function Of(source)
		local row = DB.Row("base:" .. source)
		return row and row.v:match("^[^;]*") or "?"
	end
	local n = S.counts
	if (n.recipe or 0) + (n.boss or 0) == 0 then
		return "no recipes or dungeons yet: they come from guildmates, with the game database shared"
	end
	return ("%d recipes and %d vendor prices (SkillUp Forever %s), %d bosses (OneForAll %s)%s"):format(n.recipe or 0, n.vprice or 0, Of("skillup"), n.boss or 0, Of("oneforall"),
		type(DawnToolsSeed) == "table" and "; this machine has the seed" or "")
end

local pending = false
-- (as the saved file is there, before any module is switched on: the tables are in place when a tab asks)
DT:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	local ok, err = pcall(S.Seed)
	if not ok then geterrorhandler()(err) end
	S.Rebuild()
end)
-- (rows of a guildmate's came: put together anew, once for a run of chunks)
DT:On("DT_DB_UPDATE", function(chunk)
	if pending or (chunk and not KINDS[chunk:match("^(%a+):") or ""]) then return end
	pending = true
	C_Timer.After(2, function()
		pending = false
		S.Rebuild()
	end)
end)
-- (an installed OneForAll may fill its lists after this addon was loaded: looked at again after login, and a
-- while after it; what is written already is not written again)
DT:On("PLAYER_LOGIN", function()
	local function Again()
		local ok, did = pcall(S.Seed)
		if ok and did then S.Rebuild() end
	end
	Again()
	C_Timer.After(10, Again)
end)
