-- DawnQuest
-- Every quest of the game: to search through, to see which are still open to this character, and to follow a
-- chain back to where it starts.
-- As with the NPC tab the data is not DawnTools' own: it is read, as the tab is used, from the QuestieDB addon
-- through its public API (LibQuestieDB.Quest). Nothing of it is copied or saved, and nothing goes to the guild.

local _, DT = ...
local Q = {}
DT.Quest = Q

-- db: types = { [type] = true } (ticked), min, max (quest level), hideDone, mine, obtainable, notLog, nested, sub = { Dungeon = name, Raid = name } (one instance of a ticked type), zoneOnly (the zone I am in), zone (one by name)

Q.BATCH = 200 -- quests read per frame where the client has no clock to time the reading by
local FIELDS = { "name", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "zoneOrSort", "preQuestGroup", "preQuestSingle",
	"nextQuestInChain", "questFlags", "specialFlags", "exclusiveTo", "requiredSkill", "startedBy", "parentQuest", "breadcrumbForQuestId",
	"requiredMinRep", "requiredMaxLevel" }

-- The game's own tag of a quest, where it has one
local TAGS = { [1] = "Group", [41] = "PvP", [62] = "Raid", [81] = "Dungeon", [82] = "World event", [83] = "Legendary", [84] = "Escort", [85] = "Heroic" }
-- A quest filed under no zone is filed under a "sort" (a negative number): what it is called, and what kind it is
-- ponytail: the old world's sorts, from memory; one that is not here shows as "Other"
local SORTS = {
	[-1] = "Epic", [-22] = "Seasonal", [-25] = "Battlegrounds", [-41] = "Day of the Dead", [-221] = "Treasure Map", [-241] = "Tournament",
	[-284] = "Special", [-344] = "Legendary", [-364] = "Darkmoon Faire", [-365] = "Ahn'Qiraj War", [-366] = "Lunar Festival",
	[-367] = "Reputation", [-368] = "Invasion", [-369] = "Midsummer", [-370] = "Brewfest",
	[-61] = "Warlock", [-81] = "Warrior", [-82] = "Shaman", [-141] = "Paladin", [-161] = "Mage", [-162] = "Rogue", [-261] = "Hunter",
	[-262] = "Priest", [-263] = "Druid",
	[-24] = "Herbalism", [-101] = "Fishing", [-121] = "Blacksmithing", [-181] = "Alchemy", [-182] = "Leatherworking", [-201] = "Engineering",
	[-264] = "Tailoring", [-304] = "Cooking", [-324] = "First Aid",
}
local SORT_KIND = {
	[-22] = "Seasonal", [-41] = "Seasonal", [-364] = "Seasonal", [-366] = "Seasonal", [-369] = "Seasonal", [-370] = "Seasonal", [-25] = "PvP",
	[-61] = "Class", [-81] = "Class", [-82] = "Class", [-141] = "Class", [-161] = "Class", [-162] = "Class", [-261] = "Class", [-262] = "Class", [-263] = "Class",
	[-24] = "Profession", [-101] = "Profession", [-121] = "Profession", [-181] = "Profession", [-182] = "Profession", [-201] = "Profession",
	[-264] = "Profession", [-304] = "Profession", [-324] = "Profession",
}
-- Where the game gives no tag: the old world's dungeons and raids, by the zone a quest is filed under
-- ponytail: English names, the old world only; Forever's own instances are known by their tag or not at all
local INSTANCE = {}
for _, name in ipairs({ "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep", "Blackfathom Deeps", "The Stockade", "Gnomeregan",
	"Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs", "Uldaman", "Zul'Farrak", "Maraudon", "Sunken Temple", "The Temple of Atal'Hakkar",
	"Blackrock Depths", "Blackrock Spire", "Dire Maul", "Stratholme", "Scholomance" }) do INSTANCE[name] = "Dungeon" end
for _, name in ipairs({ "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub", "Ruins of Ahn'Qiraj", "Ahn'Qiraj", "Temple of Ahn'Qiraj", "Naxxramas" }) do
	INSTANCE[name] = "Raid"
end
local SKILLS = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism", [185] = "Cooking",
	[186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning", [762] = "Riding" }
-- the labels a quest can carry, in the order they are named in
local TYPE_ORDER = { "Open world", "Dungeon", "Raid", "Group", "PvP", "Escort", "Heroic", "Legendary", "World event", "Class", "Profession",
	"Seasonal", "Daily", "Repeatable", "Reputation", "Chain start", "In chain", "Breadcrumb", "From an item" }

local index, byId = {}, {} -- every quest: see Entry; and by its number
local followers = {}        -- [quest] = { the quests it opens }
local reading
local ready, missing = false, false

---------------------------------------------------------------------------
-- Reading QuestieDB
---------------------------------------------------------------------------

local function Lib()
	local lib = LibQuestieDB
	if not (lib and lib.Quest and lib.Quest.GetAllIds and lib.Quest.GetAll) then return end
	if lib.RequireContract then
		local ok, good = pcall(lib.RequireContract, 4)
		if not (ok and good) then return end
	end
	return lib
end

local function Has(flags, bit) -- (no bit library in every Lua this runs in)
	return bit and bit > 0 and math.floor((flags or 0) / bit) % 2 == 1
end

local zoneNames = {}
local function ZoneName(zone)
	if not zone or zone == 0 then return "" end
	if zone < 0 then return SORTS[zone] or "Other" end
	if not zoneNames[zone] then
		zoneNames[zone] = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(zone) or ("Zone " .. zone)
	end
	return zoneNames[zone]
end

local function Tag(id)
	if C_QuestLog and C_QuestLog.GetQuestTagInfo then
		local ok, info = pcall(C_QuestLog.GetQuestTagInfo, id)
		if ok and type(info) == "table" then return TAGS[info.tagID] or (info.tagName ~= "" and info.tagName) or nil end
	elseif GetQuestTagInfo then
		local ok, tag, name = pcall(GetQuestTagInfo, id)
		if ok and tag then return TAGS[tag] or (name ~= "" and name) or nil end
	end
end

local function Ids(list) -- a list of quest numbers (a "must be active" one is told by a minus: taken as the quest)
	local out = {}
	for _, id in ipairs(type(list) == "table" and list or {}) do out[#out + 1] = math.abs(id) end
	return out
end

local function Entry(id, v)
	local e = { id = id, name = v[1], nameL = v[1]:lower(), min = v[2] or 0, level = v[3] or 0, races = v[4] or 0, classes = v[5] or 0,
		zone = v[6] or 0, preAll = Ids(v[7]), preAny = Ids(v[8]), next = v[9], excl = Ids(v[12]), skill = type(v[13]) == "table" and v[13] or nil,
		starts = type(v[14]) == "table" and v[14] or {}, parent = v[15], rep = type(v[17]) == "table" and v[17] or nil, maxLevel = v[18], types = {} }
	e.zoneName = ZoneName(e.zone)
	local t = e.types
	local tag = Tag(id) or INSTANCE[e.zoneName]
	if tag then t[tag] = true end
	local kind = SORT_KIND[e.zone]
	if kind then t[kind] = true end
	if e.classes ~= 0 then t.Class = true end
	if e.skill then t.Profession = true end
	if e.rep then t.Reputation = true end
	if Has(v[10], 4096) then t.Daily = true end
	if Has(v[11], 1) then t.Repeatable = true end
	if (v[16] or 0) > 0 then
		t.Breadcrumb = true
		e.crumb = v[16] -- (the quest this one only leads to)
	end
	if type(e.starts[3]) == "table" and e.starts[3][1] then t["From an item"] = true end
	if e.zone > 0 and not (t.Dungeon or t.Raid or t.PvP) then t["Open world"] = true end
	return e
end

-- after all are read: who opens whom, where chains start, and the words to search each quest by
local function Link()
	for _, e in ipairs(index) do
		local seen = {}
		for _, list in ipairs({ e.preAny, e.preAll }) do
			for _, pre in ipairs(list) do
				if byId[pre] and not seen[pre] then
					seen[pre] = true
					followers[pre] = followers[pre] or {}
					table.insert(followers[pre], e)
				end
			end
		end
	end
	for _, e in ipairs(index) do
		local after = e.next and byId[e.next]
		-- (named as the next one, though it does not say so itself; only between quests for the same people:
		-- the other side's version of a quest is no step towards mine)
		if after and #after.preAny + #after.preAll == 0 and after.races == e.races and after.classes == e.classes then
			followers[e.id] = followers[e.id] or {}
			table.insert(followers[e.id], after)
			after.preAny = { e.id }
		end
	end
	for _, e in ipairs(index) do
		if #e.preAny + #e.preAll > 0 then
			e.types["In chain"] = true
		elseif followers[e.id] then
			e.types["Chain start"] = true
		end
		local names = {}
		for _, type in ipairs(TYPE_ORDER) do
			if e.types[type] then names[#names + 1] = type end
		end
		for type in pairs(e.types) do -- (a tag of the game's that is none of ours)
			local listed = false
			for _, n in ipairs(names) do listed = listed or n == type end
			if not listed then names[#names + 1] = type end
		end
		e.typeText = table.concat(names, ", ")
		e.hay = (e.name .. " " .. e.zoneName .. " " .. e.typeText):lower()
	end
end

local function ReadAll(lib)
	local ids = lib.Quest.GetAllIds()
	local stop = debugprofilestop and debugprofilestop() + (Q.budget or 8)
	for i, id in ipairs(ids) do
		local ok, v = pcall(lib.Quest.GetAll, id, FIELDS)
		if ok and v and type(v[1]) == "string" and v[1] ~= "" then
			local made, e = pcall(Entry, id, v) -- (one odd record is left out, not the end of the reading)
			if made then index[#index + 1], byId[id] = e, e end
		end
		Q.progress = i / #ids
		if (stop and debugprofilestop() > stop) or (not stop and i % Q.BATCH == 0) then
			coroutine.yield()
			stop = debugprofilestop and debugprofilestop() + (Q.budget or 8)
		end
	end
	Link()
	ready = true
end

---------------------------------------------------------------------------
-- This character: what is done, what is in the log, what it may take
---------------------------------------------------------------------------

local me -- { level, race, class (their bits), done = fn(id), on = fn(id), skills = { [name] = rank } or nil }; nil = read anew
local function Me()
	if me then return me end
	me = { level = UnitLevel and UnitLevel("player") or 0 }
	local race, class, _
	if UnitRace then _, _, race = UnitRace("player") end
	if UnitClass then _, _, class = UnitClass("player") end
	-- (the data's own table of race bits where it has one: not every race's bit is two to its number)
	local masks = LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.raceMaskById
	me.race, me.class = race and ((type(masks) == "table" and masks[race]) or 2 ^ (race - 1)), class and 2 ^ (class - 1)
	local set
	if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
		set = {}
		for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do set[id] = true end
	elseif GetQuestsCompleted then
		set = GetQuestsCompleted() or {}
	end
	local flagged = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
	me.done = set and function(id) return set[id] or false end or flagged or function() return false end
	me.on = (C_QuestLog and C_QuestLog.IsOnQuest) or function() return false end
	if GetNumSkillLines and GetSkillLineInfo then
		me.skills = {}
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank = GetSkillLineInfo(i)
			if name and not header then me.skills[name] = rank or 0 end
		end
	elseif GetProfessions and GetProfessionInfo then
		me.skills = {}
		local mine = { GetProfessions() }
		for i = 1, 6 do
			if mine[i] then
				local name, _, rank = GetProfessionInfo(mine[i])
				if name then me.skills[name] = rank or 0 end
			end
		end
	end
	return me
end

local function QuestName(id)
	return byId[id] and byId[id].name or ("quest " .. id)
end

-- Where a quest stands for this character: a word for the kind, and what to say.
--   done / log (I have it) / open (I can take it now) / later (not yet: says what is in the way) /
--   never (not for this character: other side or class, or shut by another quest)
function Q.Status(e)
	local m = Me()
	if m.done(e.id) and not e.types.Repeatable and not e.types.Daily then return "done", "done" end
	if m.on(e.id) then return "log", "in your log" end
	if e.races ~= 0 and m.race and not Has(e.races, m.race) then return "never", "other race or side" end
	if e.classes ~= 0 and m.class and not Has(e.classes, m.class) then return "never", "other class" end
	for _, other in ipairs(e.excl) do
		if m.done(other) then return "never", "shut by: " .. QuestName(other) end
		if m.on(other) then return "never", "shut while you have: " .. QuestName(other) end
	end
	-- what follows it is done or in hand, or the quest it only leads to is: there is nothing left in it
	if e.next and e.next > 0 and (m.done(e.next) or m.on(e.next)) then return "done", "past it: " .. QuestName(e.next) end
	if e.crumb and (m.done(e.crumb) or m.on(e.crumb)) then return "done", "no longer needed for: " .. QuestName(e.crumb) end
	if e.maxLevel and e.maxLevel > 0 and m.level > e.maxLevel then return "never", ("only up to level %d"):format(e.maxLevel) end
	if m.level < e.min then return "later", ("needs level %d"):format(e.min) end
	for _, pre in ipairs(e.preAll) do
		-- (a quest done in place of it, one of those that shut each other out, counts for it)
		local met = m.done(pre)
		for _, alt in ipairs(not met and byId[pre] and byId[pre].excl or {}) do met = met or m.done(alt) end
		if not met then return "later", "after: " .. QuestName(pre) end
	end
	if e.preAny[1] then
		local any = false
		for _, pre in ipairs(e.preAny) do any = any or m.done(pre) end
		if not any then return "later", "after: " .. QuestName(e.preAny[1]) end
	end
	if e.parent and e.parent > 0 and byId[e.parent] and not m.on(e.parent) then return "later", "during: " .. QuestName(e.parent) end
	if e.skill and m.skills then
		local name = SKILLS[e.skill[1]]
		if name and (m.skills[name] or -1) < (e.skill[2] or 0) then return "later", ("needs %s %d"):format(name, e.skill[2] or 0) end
	end
	return "open", "open to you"
end

-- the quests that fit the filters and the search, best first: { e = entry, score =, status =, why = }
function Q.Find(text, f)
	local words = {}
	for word in text:lower():gmatch("%S+") do words[#words + 1] = word end
	local here = f.zoneOnly and GetRealZoneText and GetRealZoneText() or nil
	local pool, state = {}, {}
	for _, e in ipairs(index) do
		local ok = (not f.min or e.level >= f.min) and (not f.max or (e.level <= f.max and e.level > 0)) and (not here or e.zoneName == here)
			and (not f.zone or e.zoneName == f.zone)
		for type in pairs(f.types or {}) do ok = ok and e.types[type] end
		for type, name in pairs(f.sub or {}) do
			if f.types and f.types[type] then ok = ok and e.zoneName == name end
		end
		if ok then
			local status, why = Q.Status(e)
			if not ((f.hideDone and status == "done") or (f.mine and status == "never" and why:find("^other"))
				or (f.obtainable and (status == "later" or status == "never")) or (f.notLog and status == "log")) then
				pool[#pool + 1], state[e] = e, { status, why }
			end
		end
	end
	local found = DT.Npc.Match(pool, words)
	for _, r in ipairs(found) do r.status, r.why = state[r.e][1], state[r.e][2] end
	return found
end

---------------------------------------------------------------------------
-- Chains
---------------------------------------------------------------------------

-- The whole chain a quest is part of, from where it starts: { { e = quest, depth =, again = listed before } }.
-- A quest that needs two others stands under each of them; the second time it is only named.
local CHAIN_MAX = 200
function Q.Chain(e)
	local roots, seen = {}, {}
	local function Up(q)
		if seen[q] then return end
		seen[q] = true
		local any = false
		for _, list in ipairs({ q.preAny, q.preAll }) do
			for _, pre in ipairs(list) do
				if byId[pre] then
					any = true
					Up(byId[pre])
				end
			end
		end
		if not any then roots[#roots + 1] = q end
	end
	Up(e)
	local function ByLevel(a, b)
		if a.level ~= b.level then return a.level < b.level end
		return a.id < b.id
	end
	table.sort(roots, ByLevel)
	local lines, listed = {}, {}
	local function Down(q, depth)
		if #lines >= CHAIN_MAX then return end
		lines[#lines + 1] = { e = q, depth = depth, again = listed[q] or nil }
		if listed[q] then return end
		listed[q] = true
		local next = {}
		for _, f in ipairs(followers[q.id] or {}) do next[#next + 1] = f end
		table.sort(next, ByLevel)
		for _, f in ipairs(next) do Down(f, depth + 1) end
	end
	for _, root in ipairs(roots) do Down(root, 0) end
	return lines
end

-- who gives a quest: the name of its first NPC (or nil), and that NPC for a waypoint
local starters = {}
local function Starter(e)
	local id = type(e.starts[1]) == "table" and e.starts[1][1]
	if not id then return end
	if starters[id] == nil then
		local lib = Lib()
		local ok, name = pcall(function() return lib.Npc.Get(id, "name") end)
		starters[id] = ok and type(name) == "string" and name or false
	end
	return starters[id] or nil, id
end

local STATUS_COLOR = { done = "|cff40a040", log = "|cffffd100", open = "|cffffffff", later = "|cff999999", never = "|cff905050" }

-- Rewards seen: what the quest giver's window says the quest in it gives. Kept on this machine (db.seen), in the
-- shape of Data/QuestRewards.lua, which tools/harvest.js fills from it for the next release.
-- ponytail: experience is what it gave at the level it was seen at; at the level cap the game may turn it into
-- money, which is then kept as the quest's money. Keep both per level if that ever matters.
local function SeenItems(kind, n)
	local out = {}
	for i = 1, tonumber(n) or 0 do
		local _, _, count, _, _, id = GetQuestItemInfo(kind, i)
		if type(id) ~= "number" and GetQuestItemLink then
			id = tonumber(tostring(GetQuestItemLink(kind, i) or ""):match("item:(%d+)"))
		end
		if type(id) == "number" then out[#out + 1] = { id, tonumber(count) or 1 } end
	end
	return out
end

function Q.SeeRewards()
	local id = GetQuestID and GetQuestID()
	if type(id) ~= "number" or id <= 0 or not Q.db then return end
	Q.db.seen = Q.db.seen or {}
	Q.db.seen[id] = { m = tonumber(GetRewardMoney and GetRewardMoney()) or 0, x = tonumber(GetRewardXP and GetRewardXP()) or 0,
		l = UnitLevel and UnitLevel("player") or 0,
		r = GetQuestItemInfo and SeenItems("reward", GetNumQuestRewards and GetNumQuestRewards()) or {},
		c = GetQuestItemInfo and SeenItems("choice", GetNumQuestChoices and GetNumQuestChoices()) or {} }
end

-- What a quest gives. Nothing of it is ours: read where it lies, when asked.
--   xp, xpLevel   from QuestieDB's table: what it gives to a character of the quest's level
--   xpNow, money  the game's own answer, which it has for quests it knows the rewards of (those in my log)
--   items         { { id, name, sell } }: from the Items tab's reading (each item's "reward of"); sell = what a vendor pays
--   itemsRead     whether that reading is done
-- Where a quest giver has shown the quest (to me, or to whoever filled Data/QuestRewards.lua), that is believed
-- instead: seen = true, money and items as shown, each item with count and choose (one of several).
function Q.Rewards(e)
	local r = { items = {} }
	local seen = (Q.db and Q.db.seen and Q.db.seen[e.id]) or (DT.QuestRewards and DT.QuestRewards[e.id])
	local ok, xp = pcall(function() return LibQuestieDB.Support.Get("QuestXP").db[e.id] end)
	if ok and type(xp) == "table" then r.xpLevel, r.xp = tonumber(xp[1]), tonumber(xp[2]) end
	local function Game(fn)
		if not fn then return end
		local good, v = pcall(fn, e.id)
		v = good and tonumber(v)
		return v and v > 0 and v or nil
	end
	r.xpNow, r.money = Game(GetQuestLogRewardXP), Game(GetQuestLogRewardMoney)
	local I = DT.Item
	r.itemsRead = I and I.Ready() or false
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local function Add(id, name, count, choose)
		local sell
		if info then
			local good, known, _, _, _, _, _, _, _, _, _, price = pcall(info, id)
			sell, name = good and tonumber(price) or nil, name or (good and type(known) == "string" and known) or nil
		end
		r.items[#r.items + 1] = { id = id, name = name or ("Item " .. id), sell = sell, count = count or 1, choose = choose or false }
	end
	if type(seen) == "table" then
		r.seen, r.itemsRead = true, true
		r.money = r.money or tonumber(seen.m) or 0
		if (tonumber(seen.x) or 0) > 0 and not r.xp then r.xp, r.xpLevel = seen.x, seen.l end
		for _, it in ipairs(type(seen.r) == "table" and seen.r or {}) do Add(it[1], nil, it[2], false) end
		for _, it in ipairs(type(seen.c) == "table" and seen.c or {}) do Add(it[1], nil, it[2], true) end
	else
		for _, item in ipairs(I and I.rewards[e.id] or {}) do Add(item.id, item.name) end
	end
	table.sort(r.items, function(a, b)
		if a.choose ~= b.choose then return b.choose end
		return a.name < b.name
	end)
	return r
end

-- the same, as lines of text for the chain window
local MAX_ITEMS = 8
function Q.RewardLines(e)
	local r, lines = Q.Rewards(e), {}
	local xp = r.xpNow and (r.xpNow .. " XP") or (r.xp and r.xp > 0 and ("%d XP |cff888888(at level %d; less when far above it)|r"):format(r.xp, r.xpLevel or e.level))
		or "|cff888888XP not known|r"
	-- ponytail: money only where the game tells it (quests in the log); nothing installed lists it for the rest
	local money = r.money and (r.money > 0 and DT.Money(r.money) or "|cff888888no money|r")
		or "|cff888888money: not seen yet (known once a quest giver has shown the quest)|r"
	lines[1] = "|cffffd100Rewards of " .. e.name .. ":|r  " .. xp .. "   " .. money
	if not r.itemsRead and not r.items[1] then
		lines[2] = "|cff888888Items: not read yet. Open World > Items once, then click the quest again.|r"
	elseif not r.items[1] then
		lines[2] = "|cff888888No item rewards known.|r"
	end
	for i = 1, math.min(#r.items, MAX_ITEMS) do
		local item = r.items[i]
		lines[#lines + 1] = "    " .. item.name .. (item.count > 1 and (" x" .. item.count) or "") .. (item.choose and "  |cff66aaff(choose one)|r" or "")
			.. "  |cff888888vendor:|r " .. (item.sell and item.sell > 0 and DT.Money(item.sell * item.count) or "|cff888888-|r")
	end
	if #r.items > MAX_ITEMS then lines[#lines + 1] = ("    |cff888888and %d more|r"):format(#r.items - MAX_ITEMS) end
	return lines
end

local chain
local CW, CH, CROWS = 560, 17, 28
local chainLines, chainOffset, chainOf = {}, 0, nil
local function DrawChain()
	chainOffset = math.max(0, math.min(chainOffset, #chainLines - CROWS))
	for i = 1, CROWS do
		local d, row = chainLines[i + chainOffset], chain.rows[i]
		row.data = d
		row:SetShown(d ~= nil)
		if d then
			local status = Q.Status(d.e)
			local giver = Starter(d.e)
			row.text:SetText(("    "):rep(d.depth) .. (d.depth > 0 and "|cff666666> |r" or "") .. STATUS_COLOR[status]
				.. ("[%d] %s"):format(d.e.level, d.e.name) .. "|r" .. (d.again and " |cff666666(above)|r" or "")
				.. ((giver and not d.again) and ("  |cff6699cc" .. giver .. "|r") or ""))
			row.here:SetShown(d.e == chainOf)
		end
	end
	chain.more:SetText(#chainLines > CROWS and ("|cff888888mouse wheel: %d above, %d below|r"):format(chainOffset, math.max(0, #chainLines - CROWS - chainOffset)) or "")
end

-- the rewards of one quest, under the chain's rows; the window grows to hold them
function Q.ShowRewards(e)
	local lines, n = Q.RewardLines(e), math.min(#chainLines, CROWS)
	chain.rewards:ClearAllPoints()
	chain.rewards:SetPoint("TOPLEFT", 10, -46 - n * CH - 6)
	chain.rewards:SetText(table.concat(lines, "\n"))
	chain:SetSize(CW, 46 + n * CH + 24 + 8 + #lines * 13)
end

function Q.ShowChain(e)
	if not chain then
		chain = CreateFrame("Frame", "DawnToolsQuestChain", UIParent, "BackdropTemplate")
		chain:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		chain:SetBackdropColor(0.06, 0.06, 0.07, 0.97)
		chain:SetBackdropBorderColor(0.78, 0.68, 0.37, 1)
		chain:SetFrameStrata("DIALOG")
		chain:SetClampedToScreen(true)
		chain:SetMovable(true)
		chain:EnableMouse(true)
		chain:RegisterForDrag("LeftButton")
		chain:SetScript("OnDragStart", chain.StartMoving)
		chain:SetScript("OnDragStop", chain.StopMovingOrSizing)
		chain:SetPoint("CENTER", 0, 40)
		if UISpecialFrames then table.insert(UISpecialFrames, "DawnToolsQuestChain") end -- Esc closes it
		local shut = CreateFrame("Button", nil, chain, "UIPanelCloseButton")
		shut:SetPoint("TOPRIGHT", 2, 2)
		shut:SetScript("OnClick", function() chain:Hide() end) -- (the template's own closing goes through the game's panel code, which is barred to addons in combat: a plain Hide is not)
		chain.title = chain:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		chain.title:SetPoint("TOPLEFT", 10, -8)
		chain.note = chain:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		chain.note:SetPoint("TOPLEFT", 10, -28)
		chain.note:SetText("|cff40a040done|r  |cffffd100in your log|r  |cffffffffopen to you|r  |cff999999not yet|r  |cff905050not for you|r      |cff888888Click a quest: waypoint, and its rewards.|r")
		chain.more = chain:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		chain.more:SetPoint("BOTTOMLEFT", 10, 6)
		chain.rewards = chain:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		chain.rewards:SetJustifyH("LEFT")
		chain.rows = {}
		for i = 1, CROWS do
			local row = CreateFrame("Button", nil, chain)
			row:SetHeight(CH)
			row:SetPoint("TOPLEFT", 8, -46 - (i - 1) * CH)
			row:SetPoint("RIGHT", -8, 0)
			row.here = row:CreateTexture(nil, "BACKGROUND")
			row.here:SetAllPoints()
			row.here:SetColorTexture(1, 0.82, 0, 0.16)
			local highlight = row:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.08)
			row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.text:SetPoint("LEFT", 4, 0)
			row.text:SetPoint("RIGHT", -4, 0)
			row.text:SetJustifyH("LEFT")
			row.text:SetWordWrap(false)
			row:SetScript("OnClick", function(self)
				if self.data then
					Q.Waypoint(self.data.e)
					Q.ShowRewards(self.data.e) -- (and what that step gives)
				end
			end)
			row:SetScript("OnEnter", function(self)
				if self.data then Q.Tooltip(self, self.data.e) end
			end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
			chain.rows[i] = row
		end
		chain:EnableMouseWheel(true)
		chain:SetScript("OnMouseWheel", function(_, delta)
			chainOffset = chainOffset - delta * 3
			DrawChain()
		end)
		Q.chain = chain
	end
	chainLines, chainOf, chainOffset = Q.Chain(e), e, 0
	for i, d in ipairs(chainLines) do -- (opens with the quest asked about in view)
		if d.e == e and not d.again then chainOffset = i - 5 end
	end
	local done = 0
	for _, d in ipairs(chainLines) do
		if not d.again and Q.Status(d.e) == "done" then done = done + 1 end
	end
	chain.title:SetText(#chainLines > 1 and ("Chain of: %s"):format(e.name) or e.name)
	Q.ShowRewards(e)
	chain:Show()
	DrawChain()
	return chainLines
end

function Q.Waypoint(e)
	local name, id = Starter(e)
	if not id then
		return DT:Print("%s: started by no NPC that is known (an item, an object, or nobody).", e.name)
	end
	DT.Npc.Waypoint({ id = id, name = (name or "NPC") .. " (" .. e.name .. ")", zone = e.zone > 0 and e.zone or 0 })
end

function Q.Tooltip(owner, e)
	local status, why = Q.Status(e)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(e.name)
	GameTooltip:AddLine(("Level %d%s"):format(e.level, e.min > 0 and (", from level " .. e.min) or ""), 1, 1, 1)
	if e.zoneName ~= "" then GameTooltip:AddLine(e.zoneName, 0.6, 0.8, 1) end
	if e.typeText ~= "" then GameTooltip:AddLine(e.typeText, 1, 0.82, 0, true) end
	GameTooltip:AddLine(STATUS_COLOR[status] .. why:sub(1, 1):upper() .. why:sub(2) .. "|r")
	local giver = Starter(e)
	if giver then GameTooltip:AddLine("Given by " .. giver, 0.4, 0.6, 0.8) end
	local opens = followers[e.id]
	if opens then
		local names = {}
		for i = 1, math.min(4, #opens) do names[i] = opens[i].name end
		GameTooltip:AddLine("Opens: " .. table.concat(names, ", ") .. (#opens > 4 and (" and %d more"):format(#opens - 4) or ""), 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine("Click: its chain and rewards. Shift-click: its page.", 0.5, 0.8, 1)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local ROW_H, SIDE_W, TOP_H, SIDE_H = 18, 150, 50, 17
local COLS = { { "Name", 240 }, { "Level", 44 }, { "Types", 200 }, { "Zone", 140 }, { "For you", 0 } }
local STATUS_RANK = { log = 1, open = 2, later = 3, never = 4, done = 5 }
local panel, side, search, countText, bar, minBox, maxBox, zoneButton
local rows, heads, typeButtons, ticks, list, offset = {}, {}, {}, {}, {}, 0
local sortCol, sortDesc -- nil: best match first
local dirty, searchAt = true, nil

-- A quest's level in the colour the game gives its difficulty: red (far above me), orange, yellow (about my
-- level), green, grey (gives nothing any more).
local function LevelText(level, mine)
	if level <= 0 then return "" end
	local c = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
	if c and c.r then return ("|cff%02x%02x%02x%d|r"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), level) end
	-- (the old world's rule, where the game does not say)
	local grey = mine <= 5 and 0 or mine <= 39 and (mine - math.floor(mine / 10) - 5) or (mine - math.floor(mine / 5) - 1)
	local color = level >= mine + 5 and "ff2020" or level >= mine + 3 and "ff8040" or level >= mine - 2 and "ffff00" or level > grey and "40c040" or "808080"
	return "|cff" .. color .. level .. "|r"
end

local function InOrder(a, b)
	if sortCol then
		local x, y = a.sort[sortCol], b.sort[sortCol]
		if x ~= y then
			if sortDesc then return x > y end
			return x < y
		end
	elseif a.score ~= b.score then
		return a.score > b.score
	end
	if a.e.level ~= b.e.level then return a.e.level < b.e.level end
	if a.e.nameL ~= b.e.nameL then return a.e.nameL < b.e.nameL end
	return a.e.id < b.e.id
end

-- Nested: every quest stands, indented, under the quest that opens it. Only the quests listed take part: a
-- step that is not listed (done and hidden, filtered out, not found) is squeezed out, and what it opens moves
-- up to the nearest earlier step that is listed, or to the left edge when there is none. So with the done
-- ones hidden a chain begins at its first open step.
-- A quest that needs two others stands under one of them (the lower number).
local function Nest(rowsOf)
	local above = {} -- [quest] = the nearest listed quest before it, false for none
	local function Above(e)
		if above[e] ~= nil then return above[e] or nil end
		above[e] = false -- (a ring in the data ends here)
		local best
		for _, pres in ipairs({ e.preAny, e.preAll }) do
			for _, pre in ipairs(pres) do
				local p = byId[pre]
				local hit = p and p ~= e and (rowsOf[p] and p or Above(p))
				if hit and hit ~= e and (not best or hit.id < best.id) then best = hit end
			end
		end
		above[e] = best or false
		return best
	end
	local under, tops = {}, {}
	for e, row in pairs(rowsOf) do
		local p = Above(e)
		if p then
			under[p] = under[p] or {}
			table.insert(under[p], row)
		else
			tops[#tops + 1] = row
		end
	end
	local out, placed = {}, {}
	local function Place(row, depth)
		if placed[row] then return end
		placed[row] = true
		row.depth = depth
		out[#out + 1] = row
		local below = under[row.e]
		if below then
			table.sort(below, InOrder)
			for _, child in ipairs(below) do Place(child, depth + 1) end
		end
	end
	table.sort(tops, InOrder)
	for _, row in ipairs(tops) do Place(row, 0) end
	for _, row in pairs(rowsOf) do Place(row, 0) end -- (none should be left; a ring would be)
	return out
end

local function Rebuild()
	local found = ready and Q.Find(search:GetText() or "", Q.db) or {}
	local rowsOf, mine = {}, Me().level
	list = {}
	for i, r in ipairs(found) do
		local e = r.e
		list[i] = { e = e, score = r.score, depth = 0, name = STATUS_COLOR[r.status] .. e.name .. "|r",
			"", LevelText(e.level, mine), e.typeText, e.zoneName, STATUS_COLOR[r.status] .. r.why .. "|r",
			sort = { e.nameL, e.level, e.typeText, e.zoneName, STATUS_RANK[r.status] } }
		rowsOf[e] = list[i]
	end
	-- (a click on a column header sorts the list flat; a new search or Clear nests it again)
	if Q.db.nested and not sortCol then list = Nest(rowsOf) else table.sort(list, InOrder) end
	for _, row in ipairs(list) do
		row[1] = ("    "):rep(math.min(row.depth, 8)) .. (row.depth > 0 and "|cff666666> |r" or "") .. row.name
	end
end

-- Under a ticked "Dungeon" (or "Raid"): each instance by name, to pick one. With it how many of its quests
-- are done out of those this character can ever do; green when that is all of them.
local SUBS = { Dungeon = true, Raid = true }
local function Instances(type)
	local by, names = {}, {}
	for _, e in ipairs(index) do
		if e.types[type] and e.zoneName ~= "" then
			local status = Q.Status(e)
			if status ~= "never" then
				local d = by[e.zoneName]
				if not d then
					d = { name = e.zoneName, of = type, done = 0, total = 0 }
					by[e.zoneName], names[#names + 1] = d, d
				end
				d.total = d.total + 1
				if status == "done" then d.done = d.done + 1 end
			end
		end
	end
	table.sort(names, function(a, b) return a.name < b.name end)
	return names
end

-- The types on the left are those the quests now listed have, the commonest first; ticked ones stay on top.
local function SideList(fit)
	local count, order = {}, {}
	for _, row in ipairs(list) do
		for type in pairs(row.e.types) do count[type] = (count[type] or 0) + 1 end
	end
	for type in pairs(Q.db.types) do count[type] = count[type] or 0 end
	for type in pairs(count) do order[#order + 1] = type end
	table.sort(order, function(a, b)
		local ta, tb = Q.db.types[a] and 1 or 0, Q.db.types[b] and 1 or 0
		if ta ~= tb then return ta > tb end
		if count[a] ~= count[b] then return count[a] > count[b] end
		return a < b
	end)
	local entries = {} -- a type, or (under a ticked Dungeon or Raid) one of its instances
	Q.db.sub = Q.db.sub or {}
	for _, type in ipairs(order) do
		entries[#entries + 1] = { type = type }
		if SUBS[type] and Q.db.types[type] then
			for _, d in ipairs(Instances(type)) do entries[#entries + 1] = { sub = d } end
		end
	end
	for i = 1, math.max(fit, #typeButtons) do
		local entry = i <= fit and entries[i]
		local type = entry and entry.type
		local b = typeButtons[i]
		if entry and not b then
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
				if self.sub then
					local d = self.sub
					Q.db.sub[d.of] = Q.db.sub[d.of] ~= d.name and d.name or nil -- (again: all of them)
				elseif self.qtype then
					Q.db.types[self.qtype] = not Q.db.types[self.qtype] or nil
					if not Q.db.types[self.qtype] then Q.db.sub[self.qtype] = nil end
				else
					return
				end
				offset = 0
				Q.Refresh()
			end)
			typeButtons[i] = b
		end
		if b then
			b.qtype, b.sub = type or nil, entry and entry.sub or nil
			b:SetShown(entry and true or false)
			if type then
				b.label:SetText(("%s%s|r |cff888888%d|r"):format(Q.db.types[type] and "|cffffd100" or "|cffffffff", type, count[type]))
				b.sel:SetShown(Q.db.types[type] and true or false)
			elseif entry then
				local d = entry.sub
				local all, on = d.total > 0 and d.done == d.total, Q.db.sub[d.of] == d.name
				b.label:SetText(("    %s%s|r %s%d/%d|r"):format(all and "|cff40ff40" or on and "|cffffd100" or "|cffffffff", d.name,
					all and "|cff40a040" or "|cff888888", d.done, d.total))
				b.sel:SetShown(on)
			end
		end
	end
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", SIDE_W + 8, -TOP_H - ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -12, 0)
	local shade = row:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
	row.qcols = {}
	for c = 1, #COLS do
		row.qcols[c] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.qcols[c]:SetJustifyH("LEFT")
		row.qcols[c]:SetWordWrap(false)
	end
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if self.data then Q.Tooltip(self, self.data.e) end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self)
		local d = self.data
		if not d then return end
		if IsShiftKeyDown and IsShiftKeyDown() then
			DT:ShowLink(d.e.name, "https://www.wowhead.com/forever/quest=" .. d.e.id)
		else
			Q.ShowChain(d.e)
		end
	end)
	rows[i] = row
	return row
end

-- scrolled = only the window moved: the quests are not gone through again
function Q.Refresh(scrolled)
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
		heads[c].text:SetText("|cffffd100" .. col[1] .. (sortCol == c and (sortDesc and " v" or " ^") or "") .. "|r")
	end
	for i = 1, math.max(fit, #rows) do
		local d = i <= fit and list[offset + i]
		local row = rows[i] or (d and MakeRow(i))
		if row then
			row.data = d or nil
			row:SetShown(d and true or false)
			for c, cell in ipairs(row.qcols) do
				cell:SetText(d and d[c] or "")
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", xs[c], 0)
				cell:SetWidth(widths[c])
			end
		end
	end
	if scrolled == true then return end
	SideList(math.max(1, math.floor((panel:GetHeight() - 4) / SIDE_H)))
	for key, box in pairs(ticks) do box:SetChecked(Q.db[key] and true or false) end
	local here = GetRealZoneText and GetRealZoneText() or "?"
	zoneButton.label:SetText(Q.db.zoneOnly and ("Zone: here (" .. here .. ")") or Q.db.zone and ("Zone: " .. Q.db.zone) or "Zone: any")
	if missing then
		countText:SetText("|cffff8080Needs the QuestieDB addon (Questie itself is not needed): the list of quests is read from it.|r")
	elseif not ready then
		countText:SetText(("|cff888888Reading quests... %d%%|r"):format(math.floor((Q.progress or 0) * 100)))
	else
		countText:SetText(("%d of %d quests%s"):format(#list, #index, sortCol and (Q.db.nested and ", sorted flat (Clear nests again)" or "")
			or (search:GetText() or "") ~= "" and ", best match first" or ""))
	end
end

-- The zone: nil = any, "@here" = the one I am in (it follows me), or a zone (or a kind: "Mage", "Fishing") by name.
function Q.PickZone(zone)
	Q.db.zoneOnly, Q.db.zone = zone == "@here" or false, zone ~= "@here" and zone or nil
	offset = 0
	Q.Refresh()
end

-- A zone is green when every quest in it that this character can ever do is done (as the instances on the left).
local function ZoneEntries()
	local count, names, left, can = {}, {}, {}, {}
	for _, e in ipairs(index) do
		if e.zoneName ~= "" then
			if not count[e.zoneName] then names[#names + 1] = e.zoneName end
			count[e.zoneName] = (count[e.zoneName] or 0) + 1
			local status = Q.Status(e)
			if status ~= "never" then
				can[e.zoneName] = true
				if status ~= "done" then left[e.zoneName] = true end
			end
		end
	end
	table.sort(names)
	local function Green(name) return can[name] and not left[name] and "|cff40a040" or nil end
	local here = GetRealZoneText and GetRealZoneText() or "?"
	local out = { { text = "Any zone", always = true }, { value = "@here", text = "Where I am (" .. here .. ")", n = count[here] or 0, always = true, color = Green(here) } }
	for _, name in ipairs(names) do out[#out + 1] = { value = name, text = name, n = count[name], color = Green(name) } end
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
		sortCol, offset, searchAt = nil, 0, GetTime() + 0.15
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	Q.search = search
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", search, "RIGHT", 12, 0)
	countText:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
	countText:SetJustifyH("LEFT")
	countText:SetWordWrap(false)

	-- the second line: quest level from-to, then what to leave out
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
		box:SetText(Q.db[key] and tostring(Q.db[key]) or "")
		box:SetScript("OnTextChanged", function(self)
			Q.db[key] = tonumber(self:GetText())
			offset, dirty = 0, true
		end)
		box:SetScript("OnEnterPressed", box.ClearFocus)
		box:SetScript("OnEscapePressed", box.ClearFocus)
		return box
	end
	minBox = LevelBox("min", Label("Level"))
	maxBox = LevelBox("max", Label("to", minBox, 4))
	local function Tick(key, text, tip, after)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("LEFT", after, "RIGHT", 10, 0)
		local label = Label(text, box, 0)
		box:SetScript("OnClick", function(self)
			Q.db[key] = self:GetChecked() and true or false
			offset = 0
			Q.Refresh()
		end)
		box:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		box:SetScript("OnLeave", function() GameTooltip:Hide() end)
		ticks[key] = box
		return label
	end
	local last = Tick("nested", "Nested", "Each quest stands under the one that opens it. A step that is not listed (done and hidden, filtered out) is squeezed out, so a chain begins at its first open step. A click on a column header sorts the list flat instead.", maxBox)
	last = Tick("hideDone", "Hide done", "Leaves out the quests this character has completed.", last)
	last = Tick("mine", "Mine only", "Leaves out quests of the other side, another race or another class.", last)
	last = Tick("notLog", "Not in log", "Leaves out the quests already in your quest log: what is left is what there is still to pick up.", last)
	last = Tick("obtainable", "Can take now", "Leaves out what this character cannot take yet: level too low, an earlier quest not done, a profession missing.", last)
	Q.ticks = ticks
	zoneButton = DT:Dropdown(panel, 180, { search = true, menuWidth = 240, entries = ZoneEntries, pick = Q.PickZone,
		picked = function() return Q.db.zoneOnly and "@here" or Q.db.zone end })
	zoneButton:SetPoint("LEFT", last, "RIGHT", 12, 0)
	Q.zoneButton = zoneButton
	last = zoneButton
	local clear = CreateFrame("Button", nil, panel)
	clear:SetSize(40, 18)
	clear:SetPoint("LEFT", last, "RIGHT", 12, 0)
	clear.label = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	clear.label:SetPoint("LEFT")
	clear.label:SetText("|cff80c0ffClear|r")
	clear:SetScript("OnClick", function()
		local db = Q.db
		db.types, db.min, db.max, db.hideDone, db.mine, db.obtainable, db.zoneOnly, db.zone = {}, nil, nil, true, true, false, false, nil
		db.nested, db.notLog, db.sub, sortCol = true, false, {}, nil
		zoneButton.menu:Hide()
		minBox:SetText("")
		maxBox:SetText("")
		search:SetText("")
		offset = 0
		Q.Refresh()
	end)
	Q.clear = clear

	-- column headers: click to sort, again to turn it round
	for c = 1, #COLS do
		local h = CreateFrame("Button", nil, panel)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetJustifyH("LEFT")
		h.text:SetWordWrap(false)
		h:SetScript("OnClick", function()
			if sortCol == c then sortDesc = not sortDesc else sortCol, sortDesc = c, false end
			Q.Refresh()
		end)
		heads[c] = h
	end
	Q.heads = heads

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
		Q.Refresh(true)
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Q.Refresh(true)
	end)
	panel:SetScript("OnSizeChanged", function() Q.Refresh(true) end) -- (the same quests, laid out anew)
	panel:SetScript("OnUpdate", function()
		-- the reading goes on a little every frame, and says how far it is
		if reading then
			Q.Step(8)
			Q.Refresh()
			return
		end
		if searchAt and GetTime() >= searchAt then searchAt, dirty = nil, true end
		if dirty then Q.Refresh() end
	end)
end

-- The quests are read the first time the tab is looked at: not at login, when nobody may want them.
-- Begins the reading, if it has not been done or begun. Says whether there is reading to do.
function Q.Start()
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

-- Reads on for about so many milliseconds. Says whether it is done.
function Q.Step(ms)
	if not reading then return true end
	Q.budget = ms
	local ok, err = coroutine.resume(reading)
	if not ok then
		DT:Debug("quest", "reading stopped: %s", tostring(err))
		pcall(Link) -- (what was read is made whole and is what there is: not begun again on top of itself)
		ready = true
	end
	if coroutine.status(reading) == "dead" then reading = nil end
	return reading == nil
end

function Q.Ready()
	return ready
end

function Q.All()
	return index
end

-- a quest by its number (nil while the quests are not read, or for one there is not)
function Q.Entry(id)
	return ready and byId[id] or nil -- (half-read ones are not whole yet)
end

local function Show()
	Q.Start()
	me = nil -- (what is done and in the log is read anew at each look)
	Q.Refresh()
end

DT:RegisterModule("quest", {
	profile = { "types", "sub", "min", "max", "hideDone", "mine", "obtainable", "zoneOnly", "zone", "nested", "notLog" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "Quests",
	version = 1,
	slash = "/dtquest",
	tab = { id = "quest", title = "Quests", defaultOrder = 57, under = "world", create = Build, onShow = Show },
	onEnable = function(mod)
		Q.db = mod.db
		local db = Q.db
		db.types = db.types or {}
		DT:Background({ Start = Q.Start, Step = Q.Step })
		-- (done and not-mine are left out unless asked for; what cannot be taken yet stays in)
		if db.hideDone == nil then db.hideDone = true end
		if db.mine == nil then db.mine = true end
		if db.nested == nil then db.nested = true end
		-- (the quest giver's window, offering a quest or taking it back: what it gives is on show)
		for _, event in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE" }) do
			DT:On(event, function() pcall(Q.SeeRewards) end)
		end
		for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do
			DT:On(event, function() me, dirty = nil, true end)
		end
	end,
	selfTest = function(_, Try)
		Try("quest tab", function() Q.Refresh() end)
		Try("quest search", function()
			if ready then Q.Find("the", Q.db) end
		end)
	end,
})
