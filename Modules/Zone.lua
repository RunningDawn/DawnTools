-- DawnZone
-- The zones of the game: on the left each with the levels it is for and whose it is; on the right, for the
-- one picked, what is to be had there: quests, dungeons, rares, services, fish, herbs and ore, and the
-- dearest things its mobs drop. Local only; nothing is saved but which zone was looked at.
--
-- No addon on this machine gives a zone's levels or its side to read, so both are worked out from the NPCs
-- (which covers Forever's own zones too): estimates, not official numbers, as the panel says.
--   levels: the levels of the zone's ordinary hostile mobs that stand somewhere on the map, without the
--           lowest and the highest tenth (one stray mob does not stretch it)
--   side:   whose service NPCs and quest givers stand there
-- Everything else is read where it lives: NPCs, quests and items from QuestieDB through the other tabs'
-- lists, dungeons from Questie's zone table, fish from the Fish tab, herbs and ore from the player's own
-- GatherMate2 store, prices from the Market.

local _, DT = ...
local Z = {}
DT.Zone = Z

local SERVICES = { "Flight master", "Innkeeper", "Repairs", "Vendor", "Trainer", "Banker", "Auctioneer", "Stable master" }
-- (the old-world rule: what a skinned beast of a level gives)
local LEATHER = { { 1, 20, "Light Leather" }, { 15, 30, "Medium Leather" }, { 25, 40, "Heavy Leather" }, { 35, 50, "Thick Leather" }, { 45, 99, "Rugged Leather" } }
local DROPS = 10
local MAX_LEVEL = 65

local zones, byName = {}, {}
local built = false

---------------------------------------------------------------------------
-- The zones, from the NPCs and the quests
---------------------------------------------------------------------------

local function ZoneDB()
	local ok, db = pcall(function() return QuestieLoader:ImportModule("ZoneDB") end)
	return ok and type(db) == "table" and db or nil
end

local function Add(name, area)
	local z = byName[name]
	if not z then
		z = { name = name, nameL = name:lower(), hay = name:lower(), area = area, areas = {}, npcs = 0, levels = {}, inside = {}, rares = {}, services = {}, ids = {}, quests = {}, a = 0, h = 0 }
		byName[name], zones[#zones + 1] = z, z
	end
	z.areas[area] = true -- (a place may go under several numbers: the wings of a dungeon)
	return z
end

function Z.Build()
	zones, byName, built = {}, {}, true
	for _, e in ipairs(DT.Npc.All()) do
		if e.zoneName ~= "" then
			local z = Add(e.zoneName, e.zone)
			z.npcs, z.ids[e.id] = z.npcs + 1, true
			-- (a level past 65 is no level: bosses and scripted things carry 9999 or the like)
			if e.max > MAX_LEVEL and e.max < 1000 then z.over = (z.over or 0) + 1 end
			if e.max > 0 and e.max <= MAX_LEVEL and e.side == "" then
				if e.rank == 0 and e.spots > 0 then z.levels[#z.levels + 1] = e.max end
				if e.rank <= 1 then z.inside[#z.inside + 1] = e.max end -- (elites too, placed or not: what a dungeon is made of)
			end
			if e.rank == 2 or e.rank == 4 then z.rares[#z.rares + 1] = e end
			local serves = e.types["Quest giver"]
			for _, t in ipairs(SERVICES) do
				if e.types[t] then z.services[t], serves = (z.services[t] or 0) + 1, true end
			end
			if serves then
				if e.side == "A" then z.a = z.a + 1 elseif e.side == "H" then z.h = z.h + 1 end
			end
		end
	end
	if DT.Quest.Ready() then
		for _, e in ipairs(DT.Quest.All()) do
			if e.zone > 0 and e.zoneName ~= "" then
				local z = Add(e.zoneName, e.zone)
				z.quests[#z.quests + 1] = e
			end
		end
	end
	local zdb = ZoneDB()
	Z.noZdb = true -- (until Questie's list of dungeons has been had: see Rebuild)
	-- which places are dungeons: by their number, or by their name (Questie's list; its check takes the number
	-- alone, not the table: a plain function, not a method)
	local dungeonArea, dungeonName = {}, {}
	if zdb and zdb.GetDungeons then
		local ok, all = pcall(function() return zdb:GetDungeons() end)
		for area, d in pairs(ok and type(all) == "table" and all or {}) do
			dungeonArea[area], Z.noZdb = true, false
			if type(d[1]) == "string" then dungeonName[d[1]] = true end
			for _, other in ipairs(type(d[2]) == "table" and d[2] or {}) do dungeonArea[other] = true end
		end
	end
	local function Percentiles(list)
		table.sort(list)
		local count = #list
		if count >= 3 then return list[math.floor(count * 0.1) + 1], list[math.max(1, math.ceil(count * 0.9))] end
		if count > 0 then return list[1], list[count] end
	end
	for _, z in ipairs(zones) do
		z.dungeon = dungeonName[z.name] or false
		for area in pairs(z.areas) do
			if dungeonArea[area] then z.dungeon = true end
			if not z.dungeon and zdb and zdb.IsDungeonZone then
				local ok, dungeon = pcall(zdb.IsDungeonZone, area)
				if ok and dungeon then z.dungeon = true end
			end
		end
		-- Levels. The quests filed under a place say best what level it is for; where there are too few, its
		-- mobs do: the ordinary ones outdoors (critters aside), elites and all in a dungeon.
		local quests = {}
		for _, q in ipairs(z.quests) do
			if q.level > 0 and q.level <= MAX_LEVEL then quests[#quests + 1] = q.level end
		end
		if #quests >= 4 then
			z.lo, z.hi = Percentiles(quests)
			z.by = "quests"
		else
			if z.dungeon or #z.levels < 3 then z.levels = z.inside end
			table.sort(z.levels)
			local middle = z.levels[math.ceil(#z.levels / 2)]
			if middle and middle >= 8 then -- (the rabbits and rats of a grown-up zone are level 1: not what it is for)
				local kept = {}
				for _, level in ipairs(z.levels) do
					if level > 2 then kept[#kept + 1] = level end
				end
				z.levels = kept
			end
			z.lo, z.hi = Percentiles(z.levels)
			z.by = z.lo and "mobs" or nil
		end
		-- (places that are nothing to list: nameless ones, and those with one stray NPC and no quest)
		z.junk = z.name:find("^Zone %d") ~= nil or (z.npcs < 2 and #z.quests == 0 and not z.dungeon)
			or (not z.lo and (z.over or 0) > 0) -- (only mobs beyond this game's levels: a place of another game version)
		-- whose: one side's people only, or far more of one than of the other; both about even, or nobody's: contested
		if z.a > 0 and z.h == 0 or (z.h > 0 and z.a >= 4 * z.h) then
			z.side = "Alliance"
		elseif z.h > 0 and z.a == 0 or (z.a > 0 and z.h >= 4 * z.a) then
			z.side = "Horde"
		elseif z.lo or z.a > 0 then
			z.side = "Contested"
		else
			z.side = ""
		end
		table.sort(z.rares, function(a, b)
			if a.max ~= b.max then return a.max < b.max end
			return a.name < b.name
		end)
	end
	-- a dungeon belongs to the zone its door is in: listed under it
	local doors, byArea = {}, {}
	if zdb and zdb.GetDungeons then
		local ok, all = pcall(zdb.GetDungeons, zdb)
		for area, d in pairs(ok and type(all) == "table" and all or {}) do doors[area] = d[3] end
	end
	for _, zone in ipairs(zones) do
		for area in pairs(zone.areas) do byArea[area] = zone end
	end
	for _, zone in ipairs(zones) do
		if zone.dungeon then
			local parent
			for area in pairs(zone.areas) do parent = parent or doors[area] end
			zone.parent = parent and byArea[parent] ~= zone and byArea[parent] or nil
		end
	end
end

function Z.Get(name)
	return byName[name]
end

-- For other tabs: the zones are worked out if they can be (the NPC and quest lists read). True when they are.
function Z.Ensure()
	if not built and DT.Npc.Ready() and DT.Quest.Ready() then Z.Build() end
	return built
end

local function Levels(z)
	if not z.lo then return "" end
	return z.lo == z.hi and tostring(z.lo) or ("%d-%d"):format(z.lo, z.hi)
end
Z.Levels = Levels

-- a zone's levels in a colour for my own level: grey = long outgrown, green = easy, yellow = about right,
-- orange = hard at its top, red = too high
local LevelColor
function Z.LevelColor(z, mine) return LevelColor(z, mine) end
function LevelColor(z, mine)
	if not z.lo then return "|cff888888" end
	if mine < z.lo - 3 then return "|cffff4040" end
	if mine < z.lo then return "|cffff8040" end
	if mine <= z.hi then return "|cffffff00" end
	if mine <= z.hi + 5 then return "|cff40c040" end
	return "|cff808080"
end

-- the zones that fit: { e = zone, score = }
function Z.Find(text, f)
	local words = {}
	for word in text:lower():gmatch("%S+") do words[#words + 1] = word end
	local mine = UnitLevel and UnitLevel("player") or 0
	local pool = {}
	for _, z in ipairs(zones) do
		-- (a dungeon goes with the zone it is in: where that zone is filtered out, so is the dungeon)
		local by = z.dungeon and z.parent or z
		local ok = not z.junk and (not f.mine or (by.lo and mine >= by.lo - 2 and mine <= by.hi + 2)) and (not f.side or by.side == f.side)
			and (f.dungeons or not z.dungeon)
		if ok then pool[#pool + 1] = z end
	end
	return DT.Npc.Match(pool, words)
end

---------------------------------------------------------------------------
-- What a zone has
---------------------------------------------------------------------------

local function Money(copper)
	return DT.Money(math.floor(copper + 0.5))
end

-- herbs or ore of a zone, from the player's own GatherMate2 store: "Peacebloom 143, Silverleaf 96", or nil
-- and why not
function Z.Nodes(z, kind)
	local ok, gm = pcall(function() return LibStub("AceAddon-3.0"):GetAddon("GatherMate2", true) end)
	if not (ok and gm and gm.gmdbs) then return nil, "needs the GatherMate2 addon" end
	local map = DT.Npc.MapOf(z.area)
	local store
	pcall(function() store = map and gm.gmdbs[kind] and gm.gmdbs[kind][map] end)
	if type(store) ~= "table" or not next(store) then return nil, "none recorded here yet (GatherMate2's Import fills these in)" end
	local count, names = {}, {}
	for _, node in pairs(store) do
		local name
		pcall(function() name = gm:GetNameForNode(kind, node) end)
		name = name or ("node " .. tostring(node))
		if not count[name] then names[#names + 1] = name end
		count[name] = (count[name] or 0) + 1
	end
	table.sort(names, function(a, b)
		if count[a] ~= count[b] then return count[a] > count[b] end
		return a < b
	end)
	local out = {}
	for i = 1, math.min(8, #names) do out[i] = ("%s |cff888888%d|r"):format(names[i], count[names[i]]) end
	return table.concat(out, ", ") .. (#names > 8 and (" |cff888888and %d more kinds|r"):format(#names - 8) or "")
end

function Z.Leather(z)
	if not z.lo then return nil end
	local out = {}
	for _, tier in ipairs(LEATHER) do
		if z.hi >= tier[1] and z.lo <= tier[2] then out[#out + 1] = tier[3] end
	end
	return out[1] and table.concat(out, ", ") or nil
end

-- The dearest things this zone's mobs and objects drop, by the guild's auction prices. Every priced item's
-- sources have to be read once (kept for the session), which takes a moment: done a few milliseconds a
-- frame, the block saying so meanwhile.
local sourcesOf, objectZone = {}, {}
local dropJob, dropsFor = nil, {}

local function Sources(lib, id)
	local s = sourcesOf[id]
	if s == nil then
		local ok, npcs = pcall(function() return lib.Item.Get(id, "npcDrops") end)
		local ok2, objects = pcall(function() return lib.Item.Get(id, "objectDrops") end)
		s = { npcs = ok and type(npcs) == "table" and npcs or {}, objects = ok2 and type(objects) == "table" and objects or {} }
		sourcesOf[id] = s
	end
	return s
end

local function StartDrops(z)
	local lib = LibQuestieDB
	local api = DawnMarket and DawnMarket.API
	if not (lib and lib.Item and lib.Item.Get and api and api.Each) then
		dropsFor[z.name] = {}
		return
	end
	local priced = {}
	api.Each(function(id, price) if price and price > 0 then priced[#priced + 1] = { id, price } end end)
	dropJob = coroutine.create(function()
		local found = {}
		local stop = debugprofilestop and debugprofilestop() + 6
		for i, p in ipairs(priced) do
			local s = Sources(lib, p[1])
			local from
			for _, npc in ipairs(s.npcs) do
				if z.ids[npc] then from = npc break end
			end
			if not from then
				for _, object in ipairs(s.objects) do
					if objectZone[object] == nil then
						local ok, area = pcall(function() return lib.Object.Get(object, "zoneID") end)
						objectZone[object] = ok and area or false
					end
					if objectZone[object] == z.area then from = -object break end
				end
			end
			if from then found[#found + 1] = { id = p[1], price = p[2], from = from } end
			if (stop and debugprofilestop() > stop) or (not stop and i % 200 == 0) then
				coroutine.yield()
				stop = debugprofilestop and debugprofilestop() + 6
			end
		end
		table.sort(found, function(a, b)
			if a.price ~= b.price then return a.price > b.price end
			return a.id < b.id
		end)
		for i = #found, DROPS + 1, -1 do found[i] = nil end
		dropsFor[z.name] = found
	end)
	Z.dropZone = z.name
end

-- the lines of the right-hand side for a zone: { head = } or { text =, click = function, item = an item's number (its tooltip on hover) }
function Z.Lines(z)
	local out = {}
	local function Head(text)
		if out[1] then out[#out + 1] = { text = "" } end -- (a line of air between the blocks)
		out[#out + 1] = { head = text }
	end
	local function Line(text, click, item) out[#out + 1] = { text = text, click = click, item = item } end
	local lib = LibQuestieDB
	local function NameOf(entity, id)
		local ok, name = pcall(function() return lib[entity].Get(id, "name") end)
		return ok and type(name) == "string" and name or nil
	end

	-- quests
	if z.quests[1] then
		local open, done, later = 0, 0, 0
		for _, q in ipairs(z.quests) do
			local status = DT.Quest.Status(q)
			if status == "open" or status == "log" then open = open + 1 elseif status == "done" then done = done + 1 elseif status == "later" then later = later + 1 end
		end
		Head("Quests")
		Line(("%d open to you, %d not yet, %d done, %d in all  |cff80c0ff(show them)|r"):format(open, later, done, #z.quests), function()
			DT.Quest.PickZone(z.name)
			DT.UI:Show("quest")
		end)
	end

	-- dungeons whose door is here
	local zdb = ZoneDB()
	local dungeons = {}
	if zdb and zdb.GetDungeons then
		local ok, all = pcall(zdb.GetDungeons, zdb)
		for area, d in pairs(ok and type(all) == "table" and all or {}) do
			local door = type(d[4]) == "table" and d[4][1]
			if z.areas[d[3]] or (door and z.areas[door[1]]) then dungeons[#dungeons + 1] = { name = d[1], area = area, door = door } end
		end
	end
	if dungeons[1] then
		table.sort(dungeons, function(a, b) return tostring(a.name) < tostring(b.name) end)
		Head("Dungeons")
		for _, d in ipairs(dungeons) do
			local inside = byName[d.name]
			Line(("%s%s%s"):format(tostring(d.name), inside and inside.lo and ("  |cff888888" .. Levels(inside) .. "|r") or "",
				d.door and "  |cff80c0ff(waypoint to its door)|r" or ""), d.door and function()
				DT.Npc.Pin(d.door[1], d.door[2], d.door[3], tostring(d.name))
			end or nil)
		end
	end

	-- rares
	if z.rares[1] then
		Head(("Rare mobs (%d)"):format(#z.rares))
		for i = 1, math.min(12, #z.rares) do
			local e = z.rares[i]
			Line(("%s  |cff888888level %d%s|r"):format(e.name, e.max, e.rank == 2 and ", elite" or ""), function() DT.Npc.Waypoint(e) end)
		end
		if #z.rares > 12 then Line(("|cff888888and %d more: the NPC tab lists them (type Rare, this zone)|r"):format(#z.rares - 12)) end
	end

	-- services
	local services = {}
	for _, t in ipairs(SERVICES) do
		if z.services[t] then services[#services + 1] = t end
	end
	if services[1] then
		Head("Services")
		for _, t in ipairs(services) do
			Line(("%s  |cff888888%d|r  |cff80c0ff(show)|r"):format(t, z.services[t]), function()
				local db = DT.Npc.db
				db.zone, db.zoneOnly, db.types = z.name, nil, { [t] = true }
				DT.UI:Show("npc")
			end)
		end
	end

	-- fish
	if DT.modules.fish and DT.modules.fish.enabled and DT.Fish.Spots then
		local best
		for _, s in ipairs(DT.Fish.Spots()) do
			if s.name == z.name or s.name:sub(1, #z.name + 2) == z.name .. ", " then
				if not best or (s.casts or 0) > (best.casts or 0) then best = s end
			end
		end
		if best then
			Head("Fish" .. (best.skill and ("  |cff888888fishing skill " .. best.skill .. "|r") or ""))
			for i = 1, math.min(5, #best.fish) do
				local f = best.fish[i]
				Line(("%s  |cff888888%d%% of casts, %s each|r"):format(DT.Fish.Name(f[1]), math.floor(f[2] * 100 + 0.5), Money(DT.Fish.Worth(f[1]))), nil, f[1])
			end
			Line(("|cff888888%s About %s a cast.|r"):format(best.casts and ("From your own " .. best.casts .. " casts.") or "A guess from the built-in list.", Money(best.per)))
		end
	end

	-- gathering
	Head("Gathering")
	local herbs, whyHerbs = Z.Nodes(z, "Herb Gathering")
	local ore, whyOre = Z.Nodes(z, "Mining")
	if herbs or ore then
		Line("Herbs: " .. (herbs or "|cff888888none recorded|r"))
		Line("Ore: " .. (ore or "|cff888888none recorded|r"))
	else
		Line("|cff888888Herbs and ore: " .. (whyHerbs or whyOre) .. "|r")
	end
	local leather = Z.Leather(z)
	if leather then Line("Leather: " .. leather .. "  |cff888888(by the level of its mobs)|r") end

	-- the dearest drops
	Head("Valuable drops  |cff888888by the auction prices the guild has seen|r")
	local drops = dropsFor[z.name]
	if not drops then
		if not dropJob then StartDrops(z) end
		Line("|cff888888Working it out...|r")
	elseif not drops[1] then
		Line("|cff888888Nothing with a known auction price drops here.|r")
	else
		local items
		for _, d in ipairs(drops) do
			local from = d.from > 0 and NameOf("Npc", d.from) or NameOf("Object", -d.from)
			local name = NameOf("Item", d.id) or ("item " .. d.id)
			Line(("%s  |cffffd100%s|r  |cff888888%s|r"):format(name, Money(d.price), from or ""), function()
				if not items then
					items = {}
					for _, e in ipairs(DT.Item.All()) do items[e.id] = e end
				end
				if items[d.id] then DT.Item.ShowInfo(items[d.id]) end
			end, d.id)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The tab: zones on the left, the one picked on the right
---------------------------------------------------------------------------

local ROW_H, LEFT_W, TOP_H, LINE_H = 18, 330, 50, 16
local COLS = { { "Zone", 180 }, { "Levels", 70 }, { "Side", 80 } }
local SIDE_COLOR = { Alliance = "|cff6090ff", Horde = "|cffff5050", Contested = "|cffffd100", [""] = "|cff888888" }
local panel, search, countText, bar, right, mineBox, dungeonBox, sideButton
local rows, heads, list, offset = {}, {}, {}, 0
local sortCol, sortDesc
local lines, lineOffset, picked = {}, 0, nil
local linesFor, linesStale -- the zone the lines are of; something changed since
local dirty, searchAt = true, nil

local function Waiting()
	return not (DT.Npc.Ready() and DT.Quest.Ready())
end

local function Rebuild()
	if Waiting() then
		list = {}
		return
	end
	-- (built once; again, a few times at most, while Questie had no dungeons to tell of yet)
	if not built or (Z.noZdb and (Z.tries or 0) < 5) then
		Z.tries = (Z.tries or 0) + 1
		Z.Build()
		if picked then picked = byName[picked.name] end
	end
	local mine = UnitLevel and UnitLevel("player") or 0
	list = {}
	for i, r in ipairs(Z.Find(search:GetText() or "", Z.db)) do
		local z = r.e
		list[i] = { z = z, score = r.score,
			(z.dungeon and "|cffc080ff" or "|cffffffff") .. z.name .. "|r", LevelColor(z, mine) .. Levels(z) .. "|r", SIDE_COLOR[z.side] .. (z.dungeon and "Dungeon" or z.side) .. "|r",
			sort = { z.nameL, z.lo or 999, z.dungeon and "Dungeon" or z.side } }
	end
	table.sort(list, function(a, b)
		if sortCol then
			local x, y = a.sort[sortCol], b.sort[sortCol]
			if x ~= y then
				if sortDesc then return x > y end
				return x < y
			end
		elseif a.score ~= b.score then
			return a.score > b.score
		end
		if (a.z.lo or 999) ~= (b.z.lo or 999) then return (a.z.lo or 999) < (b.z.lo or 999) end
		return a.z.nameL < b.z.nameL
	end)
	-- Dungeons stand, indented, under the zone their door is in (as quests stand under the quest that opens
	-- them). One whose zone is not listed (filtered out, not found) stands at the edge.
	if Z.db.dungeons then
		local listed, under, out = {}, {}, {}
		for _, row in ipairs(list) do listed[row.z] = true end
		for _, row in ipairs(list) do
			local parent = row.z.dungeon and row.z.parent
			if parent and listed[parent] then
				under[parent] = under[parent] or {}
				table.insert(under[parent], row)
			end
		end
		for _, row in ipairs(list) do
			if not (row.z.dungeon and row.z.parent and listed[row.z.parent]) then
				out[#out + 1] = row
				for _, child in ipairs(under[row.z] or {}) do
					child.depth = 1
					child[1] = "    |cff666666> |r" .. child[1]
					out[#out + 1] = child
				end
			end
		end
		list = out
	end
end

local MakeLine
local function DrawRight()
	-- as many rows as there is room for now (the panel's height is not known when it is built)
	local fit = math.max(6, math.floor((panel:GetHeight() - 48 - 22) / LINE_H))
	for i = #right.rows + 1, fit do right.rows[i] = MakeLine(i) end
	lineOffset = math.max(0, math.min(lineOffset, #lines - fit))
	for i, row in ipairs(right.rows) do
		local d = i <= fit and lines[i + lineOffset] or nil
		row.data = d
		row:SetShown(d ~= nil)
		if d then
			row.text:SetText(d.head and ("|cffffd100" .. d.head .. "|r") or ("    " .. d.text))
			row:EnableMouse((d.click or d.item) and true or false)
		end
	end
	right.more:SetText(#lines > fit and ("|cff888888mouse wheel: %d above, %d below|r"):format(lineOffset, math.max(0, #lines - fit - lineOffset)) or "")
end

-- the map a zone is drawn on: its own, or (a dungeon without one) that of the zone its door is in
function Z.MapOf(z)
	for area in pairs(z.areas) do -- (a place may go under several numbers)
		local map = DT.Npc.MapOf(area)
		if map then return map end
	end
	return z.parent and Z.MapOf(z.parent) or nil
end

-- opens the game's map on a zone
function Z.OpenMap(z)
	local map = Z.MapOf(z)
	if not map then return DT:Print("%s: no map known for it.", z.name) end
	if InCombatLockdown and InCombatLockdown() then return DT:Print("The map cannot be opened by an addon in combat.") end
	if OpenWorldMap then
		OpenWorldMap(map)
	elseif WorldMapFrame and WorldMapFrame.SetMapID then
		if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
		WorldMapFrame:SetMapID(map)
	else
		DT:Print("%s: this game version gives an addon no way to open the map.", z.name)
	end
end

function Z.Pick(z)
	picked = z
	Z.db.last = z and z.name or nil
	lineOffset = 0
	Z.Refresh()
end

-- scrolled = only the list moved
function Z.Refresh(scrolled)
	if not panel then return end
	if scrolled ~= true then
		dirty = false
		Rebuild()
	end
	local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H - ROW_H) / ROW_H))
	local max = math.max(0, #list - fit)
	offset = math.max(0, math.min(offset, max))
	bar:SetMinMaxValues(0, max)
	bar:SetValue(offset)
	bar:SetShown(max > 0)
	bar.thumb:SetSize(8, math.max(16, fit * ROW_H * fit / math.max(fit, #list)))
	local x = 0
	for c, col in ipairs(COLS) do
		heads[c]:ClearAllPoints()
		heads[c]:SetPoint("TOPLEFT", 4 + x, -TOP_H)
		heads[c]:SetSize(col[2] - 6, ROW_H)
		heads[c].text:SetText("|cffffd100" .. col[1] .. (sortCol == c and (sortDesc and " v" or " ^") or "") .. "|r")
		x = x + col[2]
	end
	for i = 1, math.max(fit, #rows) do
		local d = i <= fit and list[offset + i]
		local row = rows[i]
		if d and not row then
			row = CreateFrame("Button", nil, panel)
			row:SetHeight(ROW_H)
			row:SetPoint("TOPLEFT", 0, -TOP_H - ROW_H - (i - 1) * ROW_H)
			row:SetWidth(LEFT_W)
			row.sel = row:CreateTexture(nil, "BACKGROUND")
			row.sel:SetAllPoints()
			row.sel:SetColorTexture(1, 0.82, 0, 0.18)
			local glow = row:CreateTexture(nil, "HIGHLIGHT")
			glow:SetAllPoints()
			glow:SetColorTexture(1, 1, 1, 0.08)
			row.zcols = {}
			local cx = 4
			for c, col in ipairs(COLS) do
				row.zcols[c] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.zcols[c]:SetPoint("LEFT", cx, 0)
				row.zcols[c]:SetWidth(col[2] - 6)
				row.zcols[c]:SetJustifyH("LEFT")
				row.zcols[c]:SetWordWrap(false)
				cx = cx + col[2]
			end
			row:SetScript("OnClick", function(self)
				if self.data then Z.Pick(self.data.z) end
			end)
			rows[i] = row
		end
		if row then
			row.data = d or nil
			row:SetShown(d and true or false)
			if d then
				for c, cell in ipairs(row.zcols) do cell:SetText(d[c]) end
				row.sel:SetShown(d.z == picked)
			end
		end
	end
	if scrolled == true then return end
	mineBox:SetChecked(Z.db.mine and true or false)
	dungeonBox:SetChecked(Z.db.dungeons and true or false)
	sideButton.label:SetText(Z.db.side or "Any side")
	-- the right-hand side
	if not picked and Z.db.last and byName[Z.db.last] then picked = byName[Z.db.last] end
	if picked then
		local mine = UnitLevel and UnitLevel("player") or 0
		right.title:SetText(picked.name)
		right.sub:SetText(("%s%s|r   %s%s|r   |cff888888%s|r"):format(
			LevelColor(picked, mine), picked.lo and ("Levels " .. Levels(picked)) or "Levels not known", SIDE_COLOR[picked.side] or "",
			picked.dungeon and ("Dungeon" .. (picked.parent and (" in " .. picked.parent.name) or "")) or picked.side,
			picked.by == "quests" and "(levels: from its quests)" or picked.by == "mobs" and "(levels: from its mobs)" or ""))
		-- (worked out when another zone is picked or something changed, not at every redraw)
		if linesFor ~= picked or linesStale then
			lines, linesFor, linesStale = Z.Lines(picked), picked, false
		end
		right.map:SetShown(Z.MapOf(picked) ~= nil)
	else
		right.map:Hide()
		right.title:SetText("")
		right.sub:SetText("|cff888888Click a zone on the left.|r")
		lines, linesFor = {}, nil
	end
	DrawRight()
	if Waiting() then
		countText:SetText(LibQuestieDB and "|cff888888Reading NPCs and quests...|r"
			or "|cffff8080Needs the QuestieDB addon (Questie itself is not needed): the zones are worked out from its NPCs and quests.|r")
	else
		local all = 0
		for _, zone in ipairs(zones) do
			if not zone.junk then all = all + 1 end
		end
		countText:SetText(("%d of %d zones"):format(#list, all))
	end
end

local function Build(parent)
	panel = parent
	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(190, 20)
	search:SetPoint("TOPLEFT", 8, -3)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function()
		sortCol, offset, searchAt = nil, 0, GetTime() + 0.15
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	Z.search = search
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", search, "RIGHT", 10, 0)
	countText:SetJustifyH("LEFT")
	local function Tick(key, text, x, tip)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("TOPLEFT", x, -26)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", box, "RIGHT", 0, 0)
		label:SetText(text)
		box:SetScript("OnClick", function(self)
			Z.db[key] = self:GetChecked() and true or nil
			offset = 0
			Z.Refresh()
		end)
		box:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		box:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return box
	end
	mineBox = Tick("mine", "For my level", 4, "Only zones whose levels are about your own.")
	dungeonBox = Tick("dungeons", "Show dungeons", 104, "Lists dungeons and raids too (purple), each under the zone its door is in.")
	sideButton = DT:Dropdown(panel, 100, {
		entries = function()
			return { { text = "Any side" }, { value = "Horde", text = "Horde" }, { value = "Alliance", text = "Alliance" }, { value = "Contested", text = "Contested" } }
		end,
		picked = function() return Z.db.side end,
		pick = function(side)
			Z.db.side, offset = side, 0
			Z.Refresh()
		end,
	})
	sideButton:SetPoint("TOPLEFT", 226, -28)
	Z.mineBox, Z.dungeonBox, Z.sideButton = mineBox, dungeonBox, sideButton
	for c = 1, #COLS do
		local h = CreateFrame("Button", nil, panel)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetJustifyH("LEFT")
		h:SetScript("OnClick", function()
			if sortCol == c then sortDesc = not sortDesc else sortCol, sortDesc = c, false end
			Z.Refresh()
		end)
		heads[c] = h
	end
	Z.heads = heads
	bar = CreateFrame("Slider", nil, panel)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(8)
	bar:SetPoint("TOPLEFT", LEFT_W + 2, -TOP_H - ROW_H)
	bar:SetPoint("BOTTOMLEFT", LEFT_W + 2, 2)
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
		if value == offset then return end
		offset = value
		Z.Refresh(true)
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Z.Refresh(true)
	end)

	-- the right-hand side: the zone picked
	right = CreateFrame("Frame", nil, panel)
	right:SetPoint("TOPLEFT", LEFT_W + 18, -2)
	right:SetPoint("BOTTOMRIGHT", -2, 2)
	local back = right:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(1, 1, 1, 0.03)
	right.title = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	right.title:SetPoint("TOPLEFT", 8, -6)
	right.sub = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	right.sub:SetPoint("TOPLEFT", 8, -28)
	right.sub:SetPoint("RIGHT", -8, 0)
	right.sub:SetJustifyH("LEFT")
	right.sub:SetWordWrap(false)
	right.more = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	right.more:SetPoint("BOTTOMLEFT", 8, 4)
	-- top right: the game's map, opened on this zone
	right.map = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	right.map:SetSize(60, 20)
	right.map:SetPoint("TOPRIGHT", -6, -4)
	right.map:SetText("Map")
	right.map:SetScript("OnClick", function()
		if picked then Z.OpenMap(picked) end
	end)
	right.map:Hide()
	right.rows = {}
	function MakeLine(i)
		local row = CreateFrame("Button", nil, right)
		row:SetHeight(LINE_H)
		row:SetPoint("TOPLEFT", 6, -46 - (i - 1) * LINE_H)
		row:SetPoint("RIGHT", -6, 0)
		local glow = row:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 0.08)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self)
			if self.data and self.data.click then self.data.click() end
		end)
		-- over an item (a fish, a drop): the game's own tooltip of it
		row:SetScript("OnEnter", function(self)
			local d = self.data
			if not (d and d.item) then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetHyperlink("item:" .. d.item)
			if d.click then GameTooltip:AddLine("Click: where it comes from.", 0.5, 0.8, 1) end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return row
	end
	right:EnableMouseWheel(true)
	right:SetScript("OnMouseWheel", function(_, delta)
		lineOffset = lineOffset - delta * 3
		DrawRight()
	end)
	Z.right = right

	panel:SetScript("OnSizeChanged", function()
		Z.Refresh(true)
		DrawRight()
	end)
	panel:SetScript("OnUpdate", function()
		-- (in a fight the game cuts off a script that takes long: reading and searching the list wait for its end)
		if InCombatLockdown and InCombatLockdown() then return end
		-- the lists this tab is worked out from are read if they have not been
		if Waiting() then
			DT.Npc.Step(6)
			if DT.Npc.Ready() then DT.Quest.Step(6) end
			if not Waiting() then dirty = true end
			return
		end
		if dropJob then
			local ok, err = coroutine.resume(dropJob)
			if not ok then DT:Debug("zone", "drops stopped: %s", tostring(err)) end
			if coroutine.status(dropJob) == "dead" then
				dropJob = nil
				if Z.dropZone and not dropsFor[Z.dropZone] then dropsFor[Z.dropZone] = {} end
				dirty, linesStale = true, true
			end
		end
		if searchAt and GetTime() >= searchAt then searchAt, dirty = nil, true end
		if dirty then Z.Refresh() end
	end)
end

local function Show()
	DT.Npc.Start()
	DT.Quest.Start()
	DT.Item.Start() -- (for the names behind "valuable drops"; read in its own time)
	linesStale = true -- (quests done, prices seen, nodes found since the last look)
	Z.Refresh()
end

DT:RegisterModule("zone", {
	title = "Zones",
	version = 1,
	slash = "/dtzone",
	profile = { "mine", "dungeons", "side", "last" },
	tab = { id = "zone", title = "Zones", defaultOrder = 59, under = "world", create = Build, onShow = Show },
	onEnable = function(mod)
		Z.db = mod.db
	end,
	selfTest = function(_, Try)
		Try("zone tab", function() Z.Refresh() end)
	end,
})
