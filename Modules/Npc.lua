-- DawnNpc
-- Every NPC of the game, to search through and to set a waypoint to.
-- The data is not DawnTools' own: it is read, as the tab is used, from the QuestieDB addon through its public
-- API (LibQuestieDB.Npc). Nothing of it is copied or saved, and nothing here goes to the guild. Without
-- QuestieDB the tab says so and stays empty.

local _, DT = ...
local N = {}
DT.Npc = N

-- db: favs = { [npcID] = true }, types = { [type] = true } (ticked), side, min, max, zoneOnly (the zone I am in), zone (one by name), located

N.BATCH = 200 -- NPCs read per frame where the client has no clock to time the reading by
local FIELDS = { "name", "minLevel", "maxLevel", "rank", "zoneID", "friendlyToFaction", "subName", "npcFlags", "spawns" }

-- What an NPC is. One may be several. In the order they are named in.
-- flag: a name in QuestieDB's npcFlags; rank: creature ranks (1 elite, 2 rare elite, 3 boss, 4 rare);
-- title: words to find in the NPC's title ("Fishing Supplies"), lower-case.
-- ponytail: the title words are a plain keyword match; an NPC with an unusual title has its flag types only
local TYPES = {
	{ "Vendor", flag = { "VENDOR" } },
	{ "Repairs", flag = { "REPAIR" } },
	{ "Trainer", flag = { "TRAINER" } },
	{ "Class trainer", title = { "warrior trainer", "paladin trainer", "hunter trainer", "rogue trainer", "priest trainer", "shaman trainer",
		"mage trainer", "warlock trainer", "druid trainer" } },
	{ "Quest giver", flag = { "QUEST_GIVER" } },
	{ "Flight master", flag = { "FLIGHT_MASTER" } },
	{ "Innkeeper", flag = { "INNKEEPER" } },
	{ "Banker", flag = { "BANKER" } },
	{ "Auctioneer", flag = { "AUCTIONEER" } },
	{ "Stable master", flag = { "STABLEMASTER" } },
	{ "Spirit healer", flag = { "SPIRIT_HEALER", "SPIRIT_GUIDE" } },
	{ "Battlemaster", flag = { "BATTLEMASTER" } },
	{ "Guild services", flag = { "PETITIONER", "TABARD_DESIGNER" } },
	{ "Rare", rank = { [2] = true, [4] = true } },
	{ "Elite", rank = { [1] = true, [2] = true } },
	{ "Boss", rank = { [3] = true } },
	{ "Alchemy", title = { "alchem" } },
	{ "Blacksmithing", title = { "blacksmith" } },
	{ "Cooking", title = { "cook", "chef" } },
	{ "Enchanting", title = { "enchant" } },
	{ "Engineering", title = { "engineer" } },
	{ "First Aid", title = { "first aid", "physician", "bandage" } },
	{ "Fishing", title = { "fish" } },
	{ "Herbalism", title = { "herbalis" } },
	{ "Leatherworking", title = { "leatherwork" } },
	{ "Mining", title = { "mining", "miner" } },
	{ "Skinning", title = { "skinn" } },
	{ "Tailoring", title = { "tailor" } },
	{ "Food & drink", title = { "food", "drink", "baker", "butcher", "bartender", "barmaid", "waitress", "fruit", "mushroom", "cheese", "meat", "wine", "brew" } },
	{ "Trade goods", title = { "trade" } },
	{ "Reagents", title = { "reagent" } },
	{ "Weapons", title = { "weapon", "blade", "sword", "axe", "mace", "gun", "bow", "staff", "dagger" } },
	{ "Armour", title = { "armor", "armour", "shield", "cloth", "mail" } },
	{ "General goods", title = { "general" } },
	{ "Ammo", title = { "ammo", "ammunition", "arrow", "bullet", "fletcher" } },
	{ "Mounts", title = { "mount", "breeder", "riding" } },
}

local index = {}  -- every NPC: { id, name, nameL, sub, min, max, rank, zone, zoneName, side, types, typeText, hay, spots }
local reading     -- the coroutine that fills it
local ready, missing = false, false

---------------------------------------------------------------------------
-- Reading QuestieDB
---------------------------------------------------------------------------

local function Lib()
	local lib = LibQuestieDB
	if not (lib and lib.Npc and lib.Npc.GetAllIds and lib.Npc.GetAll) then return end
	if lib.RequireContract then
		local ok, good = pcall(lib.RequireContract, 4)
		if not (ok and good) then return end
	end
	return lib
end

local zoneNames = {}
local function ZoneName(area)
	if not area or area <= 0 then return "" end
	if not zoneNames[area] then
		zoneNames[area] = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area) or ("Zone " .. area)
	end
	return zoneNames[area]
end

-- The map a zone is drawn on, for a waypoint: Questie knows (QuestieDB holds the table, Questie the lookup).
-- Without Questie the table is read straight from QuestieDB (kept there as text to be run, or as a table).
local maps, areaMaps = {}, nil
local function FromTable(area)
	if areaMaps == nil then
		local ok, t = pcall(function() return LibQuestieDB.Support.Get("ZoneDB").private.areaIdToUiMapId end)
		if ok and type(t) == "string" then ok, t = pcall(function() return (loadstring or load)(t)() end) end
		areaMaps = ok and type(t) == "table" and t or nil -- (not there yet: asked again next time)
	end
	return areaMaps and areaMaps[area] or nil
end

local function MapOf(area)
	if maps[area] == nil then
		local ok, map = pcall(function() return QuestieLoader:ImportModule("ZoneDB"):GetUiMapIdByAreaId(area) end)
		if not ok then
			map = FromTable(area)
			if not areaMaps then return nil end -- (neither is ready yet: asked again, not held against the zone for good)
		end
		map = type(map) == "number" and map > 0 and map or false
		-- (Questie's table knows maps of other game versions too: one this game has not is no map)
		if map and C_Map and C_Map.GetMapInfo and not C_Map.GetMapInfo(map) then map = false end
		maps[area] = map
	end
	return maps[area] or nil
end

-- Where a place can be pinned. Its own map where it has one and the spot is a real one; else, for a dungeon
-- (no map of its own here, its mobs without real spots), the dungeon's door in the zone outside; else the
-- zone the place is a part of. Returns area, map, x, y, and true when it is the door.
local function Pinnable(area, x, y)
	local real = x and y and x >= 0 and y >= 0
	local map = MapOf(area)
	if map and real then return area, map, x, y end
	local ok, zdb = pcall(function() return QuestieLoader:ImportModule("ZoneDB") end)
	if not ok or type(zdb) ~= "table" then return end
	local okDoor, doors = pcall(function() return zdb:GetDungeonLocation(area) end)
	local door = okDoor and type(doors) == "table" and doors[1]
	if type(door) == "table" and MapOf(door[1]) then return door[1], MapOf(door[1]), door[2], door[3], true end
	local okUp, parent = pcall(function() return zdb:GetParentZoneId(area) end)
	if okUp and type(parent) == "number" and parent ~= area and real and MapOf(parent) then return parent, MapOf(parent), x, y end
end

N.MapOf = MapOf

local function Has(flags, bit) -- (no bit library in every Lua this runs in)
	return bit and bit > 0 and math.floor(flags / bit) % 2 == 1
end

local function Entry(id, v, flagBits)
	local e = { id = id, name = v[1], sub = v[7] or "", min = v[2] or 0, max = v[3] or 0, rank = v[4] or 0, side = v[6] or "", spots = 0 }
	local zone = v[5]
	for area, spots in pairs(type(v[9]) == "table" and v[9] or {}) do
		-- (a mob inside a dungeon has a "spot" of -1, -1: that is no place on a map)
		for _, s in ipairs(spots) do
			if type(s) == "table" and (s[1] or -1) >= 0 and (s[2] or -1) >= 0 then e.spots = e.spots + 1 end
		end
		if not zone or zone <= 0 then zone = area end
	end
	e.zone, e.zoneName = zone or 0, ZoneName(zone)
	local flags, title, names = v[8] or 0, e.sub:lower(), {}
	e.types = {}
	for _, t in ipairs(TYPES) do
		local is = t.rank and t.rank[e.rank]
		for _, name in ipairs(t.flag or {}) do is = is or Has(flags, flagBits[name]) end
		for _, word in ipairs(t.title or {}) do is = is or (title ~= "" and title:find(word, 1, true) ~= nil) end
		if is then e.types[t[1]], names[#names + 1] = true, t[1] end
	end
	e.typeText = table.concat(names, ", ")
	e.nameL = e.name:lower()
	e.hay = (e.name .. " " .. e.sub .. " " .. e.zoneName .. " " .. e.typeText):lower()
	return e
end

-- Each read decodes a packed record, so the lot is read a few milliseconds at a time, frame by frame.
local function ReadAll(lib)
	local ids = lib.Npc.GetAllIds()
	local flagBits = lib.Enum and lib.Enum.npcFlags or {}
	local stop = debugprofilestop and debugprofilestop() + (N.budget or 8)
	for i, id in ipairs(ids) do
		local ok, v = pcall(lib.Npc.GetAll, id, FIELDS)
		if ok and v and type(v[1]) == "string" then index[#index + 1] = Entry(id, v, flagBits) end
		N.progress = i / #ids
		if (stop and debugprofilestop() > stop) or (not stop and i % N.BATCH == 0) then
			coroutine.yield()
			stop = debugprofilestop and debugprofilestop() + (N.budget or 8)
		end
	end
	ready = true
end

---------------------------------------------------------------------------
-- Searching: every word of what was typed has to match somewhere; the better it matches, the higher up
---------------------------------------------------------------------------

-- how well one word fits an NPC; nil when it does not. fuzzy: letters in order and misspellings count too
local function Edits(a, b, most) -- (Levenshtein, given up on past `most`)
	local la, lb = #a, #b
	if math.abs(la - lb) > most then return most + 1 end
	local prev = {}
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		local cur, best = { [0] = i }, i
		for j = 1, lb do
			local cost = a:byte(i) == b:byte(j) and 0 or 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
			if cur[j] < best then best = cur[j] end
		end
		if best > most then return most + 1 end
		prev = cur
	end
	return prev[lb]
end

local function Fits(e, word, fuzzy)
	local at = e.nameL:find(word, 1, true)
	if at == 1 then return #e.nameL == #word and 110 or 100 end
	if at then return e.nameL:sub(at - 1, at - 1) == " " and 90 or 80 end
	at = e.hay:find(word, 1, true)
	if at then return e.hay:sub(at - 1, at - 1) == " " and 70 or 60 end
	if not fuzzy or #word < 3 or word:find("[^%a%d]") then return end
	-- the letters in order, in the name: "grk" for Gorak
	if e.nameL:find((word:gsub(".", "%0.-"))) then return 40 end
	-- a misspelling of one of its words: one letter out, two in a long word; the first letter has to be right
	if #word >= 4 then
		local most, first = #word >= 7 and 2 or 1, word:byte(1)
		for w in e.hay:gmatch("%a+") do
			if w:byte(1) == first and Edits(word, w, most) <= most then return 30 end
		end
	end
end

-- Of a pool of entries (each with nameL and hay, lower-case), those every word fits, each with how well:
-- { e = entry, score = }. The Quests tab searches with this too.
function N.Match(pool, words)
	local function Pass(fuzzy, skip)
		local out = {}
		for _, e in ipairs(pool) do
			if not skip[e] then
				local score = 0
				for _, word in ipairs(words) do
					local s = Fits(e, word, fuzzy)
					if not s then score = nil break end
					score = score + s
				end
				if score then out[#out + 1] = { e = e, score = score } end
			end
		end
		return out
	end
	local found = Pass(false, {})
	-- ponytail: the slow, forgiving pass only when the plain one found less than a screenful, and for one or two words
	if words[1] and #found < 30 and #words <= 2 then
		local have = {}
		for _, r in ipairs(found) do have[r.e] = true end
		for _, r in ipairs(Pass(true, have)) do found[#found + 1] = r end
	end
	return found
end

-- the NPCs that fit the filters and the search, best first: { e = entry, score = }
function N.Find(text, f)
	local words = {}
	for word in text:lower():gmatch("%S+") do words[#words + 1] = word end
	local here = f.zoneOnly and GetRealZoneText and GetRealZoneText() or nil
	local mine = UnitFactionGroup and UnitFactionGroup("player") == "Alliance" and "A" or "H"
	local pool = {}
	for _, e in ipairs(index) do
		local ok = (not f.min or e.max >= f.min) and (not f.max or (e.min <= f.max and e.max > 0))
			and (not here or e.zoneName == here) and (not f.zone or e.zoneName == f.zone) and (not f.located or e.spots > 0)
			and (f.side ~= "friendly" or e.side:find(mine, 1, true) ~= nil) and (f.side ~= "hostile" or not e.side:find(mine, 1, true))
			and (f.side ~= "noenemy" or e.side ~= (mine == "A" and "H" or "A")) -- (the other faction's own NPCs out; neutral ones stay)
		for type in pairs(f.types or {}) do
			if type == "Favourites" then ok = ok and N.db.favs[e.id] else ok = ok and e.types[type] end
		end
		if ok then pool[#pool + 1] = e end
	end
	return N.Match(pool, words)
end

---------------------------------------------------------------------------
-- Waypoints
---------------------------------------------------------------------------

-- the spot to go to: the nearest on the map I am on, else the first on a map that can take a pin
function N.Spot(e)
	local lib = Lib()
	local ok, spawns = pcall(function() return lib.Npc.Get(e.id, "spawns") end)
	if not ok or type(spawns) ~= "table" then return end
	local myMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local pos = myMap and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(myMap, "player")
	local px, py
	if pos and pos.GetXY then px, py = pos:GetXY() end
	local best, bestD, first, any
	for area, spots in pairs(spawns) do
		for _, s in ipairs(spots) do
			local at, map, x, y, door = Pinnable(area, s[1], s[2])
			local spot = { area = at or area, map = map, x = x or s[1], y = y or s[2], door = door }
			if map or (spot.x >= 0 and spot.y >= 0) then any = any or spot end
			if map and (not first or area == e.zone and first.area ~= e.zone) then first = spot end
			if map and map == myMap and px and not door then
				local d = (spot.x / 100 - px) ^ 2 + (spot.y / 100 - py) ^ 2
				if not bestD or d < bestD then best, bestD = spot, d end
			end
		end
	end
	-- nothing with a map, or no spot at all (a dungeon's mob): the door of where it lives
	if not (best or first) and e.zone and e.zone > 0 then
		local at, map, x, y, door = Pinnable(e.zone)
		if map then return { area = at, map = map, x = x, y = y, door = door } end
	end
	return best or first or any
end

function N.Waypoint(e)
	local spot = N.Spot(e)
	if not spot then return DT:Print("%s: no known location.", e.name) end
	local where = ("%s %.1f, %.1f"):format(ZoneName(spot.area), spot.x, spot.y) .. (spot.door and " (the door of the dungeon it is in)" or "")
	if not spot.map then return DT:Print("%s is at %s, but that map takes no waypoint.", e.name, where) end
	if TomTom and TomTom.AddWaypoint then
		TomTom:AddWaypoint(spot.map, spot.x / 100, spot.y / 100, { title = e.name, from = "DawnTools" })
	elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(spot.map)) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(spot.map, spot.x / 100, spot.y / 100))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
	else
		return DT:Print("%s is at %s. (No waypoint: neither TomTom nor the game's own map pin is there.)", e.name, where)
	end
	DT:Print("Waypoint: %s, %s", e.name, where)
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local ROW_H, SIDE_W, TOP_H, SIDE_H = 18, 170, 50, 17
local COLS = { { "", 18 }, { "Name", 170 }, { "Title", 140 }, { "Types", 170 }, { "Level", 46 }, { "Side", 56 }, { "Zone", 0 } }
local RANK = { [1] = "|cffffd100", [2] = "|cffc080ff", [3] = "|cffff4040", [4] = "|cff80c0ff" } -- elite, rare elite, boss, rare
local RANK_NAME = { [1] = "Elite", [2] = "Rare elite", [3] = "Boss", [4] = "Rare" }
local SIDE = { A = "|cff6090ffAlliance|r", H = "|cffff5050Horde|r", AH = "Both", [""] = "|cff888888-|r" }
local SIDES = { { nil, "Side: any" }, { "noenemy", "Side: hide other faction" }, { "friendly", "Side: friendly to me" }, { "hostile", "Side: not friendly" } }
local panel, side, search, countText, bar, minBox, maxBox, sideButton, zoneButton, locatedBox
local rows, heads, typeButtons, list, offset = {}, {}, {}, {}, 0
local sortCol, sortDesc -- nil: best match first
local dirty, searchAt = true, nil

local function Level(e)
	if e.max <= 0 then return "" end
	return e.min == e.max and tostring(e.max) or (e.min .. "-" .. e.max)
end

local function Rebuild()
	local db = N.db
	local found = ready and N.Find(search:GetText() or "", db) or {}
	list = {}
	for i, r in ipairs(found) do
		local e = r.e
		list[i] = { e = e, score = r.score, fav = db.favs[e.id] and 1 or 0,
			db.favs[e.id] and "|cffffd100*|r" or "|cff555555*|r", (RANK[e.rank] or "|cffffffff") .. e.name .. "|r", e.sub, e.typeText, Level(e),
			SIDE[e.side] or e.side, e.spots > 0 and e.zoneName or ("|cff888888" .. (e.zoneName ~= "" and e.zoneName or "no known location") .. "|r"),
			sort = { db.favs[e.id] and 1 or 0, e.nameL, e.sub, e.typeText, e.max, e.side, e.zoneName } }
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
		elseif a.fav ~= b.fav then
			return a.fav > b.fav
		end
		if a.e.nameL ~= b.e.nameL then return a.e.nameL < b.e.nameL end
		return a.e.id < b.e.id
	end)
end

-- The types on the left are those the NPCs now listed have, the commonest first; ticked ones stay on top.
local function SideList(fit)
	local count, order = { Favourites = 0 }, {}
	for _, row in ipairs(list) do
		if row.fav == 1 then count.Favourites = count.Favourites + 1 end
		for type in pairs(row.e.types) do count[type] = (count[type] or 0) + 1 end
	end
	for type in pairs(N.db.types) do count[type] = count[type] or 0 end
	for type in pairs(count) do order[#order + 1] = type end
	table.sort(order, function(a, b)
		local ta, tb = N.db.types[a] and 1 or 0, N.db.types[b] and 1 or 0
		if ta ~= tb then return ta > tb end
		if (a == "Favourites") ~= (b == "Favourites") then return a == "Favourites" end
		if count[a] ~= count[b] then return count[a] > count[b] end
		return a < b
	end)
	for i = 1, math.max(fit, #typeButtons) do
		local type = i <= fit and order[i]
		local b = typeButtons[i]
		if type and not b then
			b = CreateFrame("Button", nil, side)
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
			b.label:SetJustifyH("LEFT")
			b:SetScript("OnClick", function(self)
				if not self.type then return end
				N.db.types[self.type] = not N.db.types[self.type] or nil
				offset = 0
				N.Refresh()
			end)
			typeButtons[i] = b
		end
		if b then
			b.type = type or nil
			b:SetShown(type and true or false)
			if type then
				b.label:SetText(("%s%s|r |cff888888%d|r"):format(N.db.types[type] and "|cffffd100" or "|cffffffff", type, count[type]))
				b.sel:SetShown(N.db.types[type] and true or false)
			end
		end
	end
end

local function Tooltip(self)
	local d = self.data
	if not d then return end
	local e, lib = d.e, Lib()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine((RANK[e.rank] or "|cffffffff") .. e.name .. "|r")
	if e.sub ~= "" then GameTooltip:AddLine("<" .. e.sub .. ">", 0.8, 0.8, 0.8) end
	local about = {}
	if Level(e) ~= "" then about[#about + 1] = "Level " .. Level(e) end
	if RANK_NAME[e.rank] then about[#about + 1] = RANK_NAME[e.rank] end
	if e.side ~= "" then about[#about + 1] = e.side == "AH" and "friendly to both sides" or (e.side == "A" and "Alliance" or "Horde") end
	if about[1] then GameTooltip:AddLine(table.concat(about, ", "), 1, 1, 1) end
	if e.typeText ~= "" then GameTooltip:AddLine(e.typeText, 1, 0.82, 0, true) end
	local function Read(field)
		local ok, v = pcall(function() return lib.Npc.Get(e.id, field) end)
		return ok and type(v) == "table" and v or {}
	end
	-- where: each zone with its spots
	local zones, spots = 0, 0
	for area, all in pairs(Read("spawns")) do
		local at = {}
		for _, s in ipairs(all) do
			if type(s) == "table" and (s[1] or -1) >= 0 and (s[2] or -1) >= 0 then at[#at + 1] = s end
		end
		if at[1] then
			zones, spots = zones + 1, spots + #at
			if zones <= 4 then
				local some = {}
				for i = 1, math.min(3, #at) do some[i] = ("%.1f, %.1f"):format(at[i][1], at[i][2]) end
				GameTooltip:AddLine(("%s: %s%s"):format(ZoneName(area), table.concat(some, "; "), #at > 3 and (" and %d more"):format(#at - 3) or ""), 0.6, 0.8, 1, true)
			end
		elseif all[1] then
			GameTooltip:AddLine(ZoneName(area) .. ": inside (a click sets a waypoint to the door, where that is known)", 0.6, 0.8, 1, true)
		end
	end
	if zones > 4 then GameTooltip:AddLine(("and %d more zones"):format(zones - 4), 0.6, 0.8, 1) end
	if spots == 0 then
		GameTooltip:AddLine("No known location (often: inside a dungeon, or it only appears for a quest).", 1, 0.5, 0.5, true)
	elseif spots == 1 then
		GameTooltip:AddLine("Only one known spot.", 0.8, 0.8, 0.8)
	else
		GameTooltip:AddLine(("Seen in %d spots: a click picks the nearest."):format(spots), 0.8, 0.8, 0.8)
	end
	if next(Read("waypoints")) then GameTooltip:AddLine("Patrols: may be away from its spot.", 1, 0.82, 0) end
	local starts, ends = #Read("questStarts"), #Read("questEnds")
	if starts + ends > 0 then GameTooltip:AddLine(("Starts %d quest%s, ends %d."):format(starts, starts == 1 and "" or "s", ends), 0.8, 0.8, 0.8) end
	-- what DawnTools has itself seen it sell
	local sells = {}
	for id, v in pairs(DT.Market and DT.Market.db and DT.Market.db.vendors or {}) do
		if v.v == e.name and #sells < 6 then sells[#sells + 1] = (GetItemInfo and GetItemInfo(id)) or ("item " .. id) end
	end
	if sells[1] then GameTooltip:AddLine("Seen selling: " .. table.concat(sells, ", "), 0.5, 1, 0.5, true) end
	GameTooltip:AddLine("Click: waypoint. Shift-click: its page. Star: favourite.", 0.5, 0.8, 1)
	GameTooltip:Show()
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", SIDE_W + 8, -TOP_H - ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -12, 0)
	local highlight = row:CreateTexture(nil, "BACKGROUND")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
	row.ncols = {}
	for c = 1, #COLS do
		row.ncols[c] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.ncols[c]:SetJustifyH("LEFT")
		row.ncols[c]:SetWordWrap(false)
	end
	row:EnableMouse(true)
	row:SetScript("OnEnter", Tooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self)
		local d = self.data
		if not d then return end
		if IsShiftKeyDown and IsShiftKeyDown() then
			DT:ShowLink(d.e.name, "https://www.wowhead.com/forever/npc=" .. d.e.id)
		else
			N.Waypoint(d.e)
		end
	end)
	-- the star, over the first column
	row.star = CreateFrame("Button", nil, row)
	row.star:SetSize(COLS[1][2], ROW_H)
	row.star:SetPoint("LEFT", 0, 0)
	row.star:SetScript("OnClick", function()
		local d = row.data
		if not d then return end
		N.db.favs[d.e.id] = not N.db.favs[d.e.id] or nil
		N.Refresh()
	end)
	rows[i] = row
	return row
end

-- scrolled = only the window moved: the 15k NPCs are not searched and sorted again
function N.Refresh(scrolled)
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
	local x, xs, widths = 0, {}, {}
	for c, col in ipairs(COLS) do
		xs[c], widths[c] = x, col[2] > 0 and col[2] - 6 or math.max(60, panel:GetWidth() - SIDE_W - 8 - x - 16)
		x = x + col[2]
		heads[c]:ClearAllPoints()
		heads[c]:SetPoint("TOPLEFT", SIDE_W + 8 + xs[c], -TOP_H)
		heads[c]:SetSize(widths[c], ROW_H)
		heads[c].text:SetText("|cffffd100" .. (c == 1 and "*" or col[1]) .. (sortCol == c and (sortDesc and " v" or " ^") or "") .. "|r")
	end
	for i = 1, math.max(fit, #rows) do
		local d = i <= fit and list[offset + i]
		local row = rows[i] or (d and MakeRow(i))
		if row then
			row.data = d or nil
			row:SetShown(d and true or false)
			for c, cell in ipairs(row.ncols) do
				cell:SetText(d and d[c] or "")
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", xs[c], 0)
				cell:SetWidth(widths[c])
			end
		end
	end
	if scrolled ~= true then SideList(math.max(1, math.floor((panel:GetHeight() - 4) / SIDE_H))) end
	local here = GetRealZoneText and GetRealZoneText() or "?"
	zoneButton.label:SetText(N.db.zoneOnly and ("Zone: here (" .. here .. ")") or N.db.zone and ("Zone: " .. N.db.zone) or "Zone: any")
	sideButton.label:SetText(SIDES[N.db.side == "noenemy" and 2 or N.db.side == "friendly" and 3 or N.db.side == "hostile" and 4 or 1][2])
	if missing then
		countText:SetText("|cffff8080Needs the QuestieDB addon (Questie itself is not needed): the list of NPCs is read from it.|r")
	elseif not ready then
		countText:SetText(("|cff888888Reading NPCs... %d%%|r"):format(math.floor((N.progress or 0) * 100)))
	else
		countText:SetText(("%d of %d NPCs%s"):format(#list, #index, sortCol and "" or (search:GetText() or "") ~= "" and ", best match first" or ""))
	end
end

local function Changed()
	offset, dirty = 0, true
end

-- The zone: nil = any, "@here" = the one I am in (it follows me), or a zone by name.
function N.PickZone(zone)
	N.db.zoneOnly, N.db.zone = zone == "@here" or nil, zone ~= "@here" and zone or nil
	offset = 0
	N.Refresh()
end

-- The list under the zone button: any, where I am, then every zone an NPC lives in, by name, with how many.
local function ZoneEntries()
	local count, names = {}, {}
	for _, e in ipairs(index) do
		if e.zoneName ~= "" then
			if not count[e.zoneName] then names[#names + 1] = e.zoneName end
			count[e.zoneName] = (count[e.zoneName] or 0) + 1
		end
	end
	table.sort(names)
	local here = GetRealZoneText and GetRealZoneText() or "?"
	local out = { { text = "Any zone", always = true }, { value = "@here", text = "Where I am (" .. here .. ")", n = count[here] or 0, always = true } }
	for _, name in ipairs(names) do out[#out + 1] = { value = name, text = name, n = count[name] } end
	return out
end

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
	search:SetSize(220, 20)
	search:SetPoint("TOPLEFT", SIDE_W + 16, -3)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function() -- (hooked: the template's own handler shows the "Search" hint)
		-- (a new search is listed best match first again; and it waits for the typing to stop)
		sortCol, offset, searchAt = nil, 0, GetTime() + 0.15
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	N.search = search
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", search, "RIGHT", 12, 0)
	countText:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
	countText:SetJustifyH("LEFT")
	countText:SetWordWrap(false)

	-- the second line: level from-to, side, this zone, with a location
	local function Label(text, after, gap)
		local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if after then fs:SetPoint("LEFT", after, "RIGHT", gap or 6, 0) else fs:SetPoint("TOPLEFT", SIDE_W + 12, -30) end
		fs:SetText(text)
		return fs
	end
	local function LevelBox(key, after)
		local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
		box:SetSize(30, 18)
		box:SetPoint("LEFT", after, "RIGHT", 8, 0)
		box:SetAutoFocus(false)
		box:SetNumeric(true)
		box:SetText(N.db[key] and tostring(N.db[key]) or "")
		box:SetScript("OnTextChanged", function(self)
			N.db[key] = tonumber(self:GetText())
			Changed()
		end)
		box:SetScript("OnEnterPressed", box.ClearFocus)
		box:SetScript("OnEscapePressed", box.ClearFocus)
		return box
	end
	minBox = LevelBox("min", Label("Level"))
	maxBox = LevelBox("max", Label("to", minBox, 4))
	N.minBox, N.maxBox = minBox, maxBox
	sideButton = DT:Dropdown(panel, 150, {
		entries = function()
			local out = {}
			for i, s in ipairs(SIDES) do out[i] = { value = s[1], text = s[2] } end
			return out
		end,
		picked = function() return N.db.side end,
		pick = function(value)
			N.db.side, offset = value, 0
			N.Refresh()
		end,
	})
	sideButton:SetPoint("LEFT", maxBox, "RIGHT", 12, 0)
	N.sideButton = sideButton
	local function Tick(key, text, after)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("LEFT", after, "RIGHT", 10, 0)
		box:SetChecked(N.db[key] and true or false)
		local label = Label(text, box, 0)
		box:SetScript("OnClick", function(self)
			N.db[key] = self:GetChecked() and true or nil
			offset = 0
			N.Refresh()
		end)
		return box, label
	end
	zoneButton = DT:Dropdown(panel, 190, { search = true, menuWidth = 240, entries = ZoneEntries, pick = N.PickZone,
		picked = function() return N.db.zoneOnly and "@here" or N.db.zone end })
	zoneButton:SetPoint("LEFT", sideButton, "RIGHT", 10, 0)
	N.zoneButton = zoneButton
	local locatedLabel
	locatedBox, locatedLabel = Tick("located", "With a known location", zoneButton)
	N.locatedBox = locatedBox
	local clear = CreateFrame("Button", nil, panel)
	clear:SetSize(40, 18)
	clear:SetPoint("LEFT", locatedLabel, "RIGHT", 12, 0)
	clear.label = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	clear.label:SetPoint("LEFT")
	clear.label:SetText("|cff80c0ffClear|r")
	clear:SetScript("OnClick", function()
		local db = N.db
		db.types, db.side, db.min, db.max, db.zoneOnly, db.zone, db.located = {}, nil, nil, nil, nil, nil, nil
		zoneButton.menu:Hide()
		sideButton.menu:Hide()
		minBox:SetText("")
		maxBox:SetText("")
		locatedBox:SetChecked(false)
		search:SetText("")
		offset = 0
		N.Refresh()
	end)
	N.clear = clear

	-- column headers: click to sort, again to turn it round
	for c = 1, #COLS do
		local h = CreateFrame("Button", nil, panel)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetJustifyH("LEFT")
		h.text:SetWordWrap(false)
		h:SetScript("OnClick", function()
			if sortCol == c then
				sortDesc = not sortDesc
			else
				sortCol, sortDesc = c, c == 1 -- (favourites first; names from A)
			end
			N.Refresh()
		end)
		heads[c] = h
	end
	N.heads = heads

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
		N.Refresh(true)
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		N.Refresh(true)
	end)
	panel:SetScript("OnSizeChanged", function() N.Refresh(true) end) -- (the same NPCs, laid out anew)
	panel:SetScript("OnUpdate", function()
		-- the reading goes on a little every frame, and says how far it is
		if reading then
			N.Step(8)
			N.Refresh()
			return
		end
		if searchAt and GetTime() >= searchAt then searchAt, dirty = nil, true end
		if dirty then N.Refresh() end
	end)
end

-- The NPCs are read the first time the tab is looked at: not at login, when nobody may want them.
-- Begins the reading, if it has not been done or begun. Says whether there is reading to do.
function N.Start()
	if not ready and not reading and not missing then
		local lib = Lib()
		if lib then
			reading = coroutine.create(function() ReadAll(lib) end)
		else
			missing = true
		end
	end
	return reading ~= nil
end

-- Reads on for about so many milliseconds. Says whether it is done. (The tab reads 8 a frame while it is
-- looked at; the background reading after login a gentler 2.)
function N.Step(ms)
	if not reading then return true end
	N.budget = ms
	local ok, err = coroutine.resume(reading)
	if not ok then DT:Debug("npc", "reading stopped: %s", tostring(err)) end
	if coroutine.status(reading) == "dead" then reading, ready = nil, true end
	return reading == nil
end

function N.Ready()
	return ready
end

-- for the Zones tab: every NPC read, and the map a zone is drawn on
function N.All()
	return index
end

function N.MapOf(area)
	return MapOf(area)
end

-- a waypoint at a place that is no NPC's (a dungeon's door): zone, x and y on 0-100
function N.Pin(area, x, y, title)
	local at, map, px, py = Pinnable(area, x, y)
	if map then area, x, y = at, px, py end
	local where = ("%s %.1f, %.1f"):format(ZoneName(area), x, y)
	if not map then return DT:Print("%s is at %s, but that map takes no waypoint.", title, where) end
	if TomTom and TomTom.AddWaypoint then
		TomTom:AddWaypoint(map, x / 100, y / 100, { title = title, from = "DawnTools" })
	elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(map)) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
	else
		return DT:Print("%s is at %s. (No waypoint: neither TomTom nor the game's own map pin is there.)", title, where)
	end
	DT:Print("Waypoint: %s, %s", title, where)
end

local function Show()
	N.Start()
	N.Refresh()
end

DT:RegisterModule("npc", {
	profile = { "types", "side", "min", "max", "zoneOnly", "zone", "located" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "NPCs",
	version = 1,
	slash = "/dtnpc",
	tab = { id = "npc", title = "NPC", defaultOrder = 55, under = "world", create = Build, onShow = Show },
	onEnable = function(mod)
		N.db = mod.db
		N.db.favs, N.db.types = N.db.favs or {}, N.db.types or {}
		DT:Background({ Start = N.Start, Step = N.Step })
	end,
	selfTest = function(_, Try)
		Try("npc tab", function() N.Refresh() end)
		Try("npc search", function()
			if ready then N.Find("fish org", {}) end
		end)
	end,
})
