-- DawnTools :: BiS
-- The best gear for a spec: of what I own, and of a list of pre-raid gear. Local only: nothing is sent.
--   What an item gives is read from the game (GetItemStats and its tooltip's lines), once per item a session.
--   What I am without gear = the character sheet less what the gear I wear gives: talents and racials are in
--     it without being known one by one. Enchants are in it too (an item's stats are those of the bare item).
--   A profile says what a point of each stat is worth and where its caps are; its weights and caps can be
--     changed on the Weights view (kept per profile). The profiles are NOT in the addon or its download: a
--     separate, unpublished addon may hand them over (global DawnToolsSeed.BisProfiles), on its keeper's
--     machine only; they are not passed to the guild. Without them there is no BiS tab.
--   The best set is found exactly (Core/BisLogic.lua), never in a fight.
-- Any class and spec can be looked at; my own gear is rated for a spec of my own class.
-- Shown: the tab (Gear, Upgrades, Weights, Check), a line on item tooltips, a chat line when an item is rolled for.
-- ponytail: stats per item number, so a "... of the Bear" item counts as its bare self; the bank as it was
-- when last opened (Inventory's); buffs on the sheet when it is read end up in "without gear".

local _, DT = ...
local BL = DT.BisLogic
local unpack = unpack or table.unpack
local B = {}
DT.Bis = B
-- the profiles, from a seed addon where one is installed (it may load after DawnTools: looked for again)
local function Profiles()
	if type(DawnToolsSeed) == "table" then
		DT.BisProfiles, DT.BisBuild = DT.BisProfiles or DawnToolsSeed.BisProfiles, DT.BisBuild or DawnToolsSeed.BisBuild
	end
	return type(DT.BisProfiles) == "table" and DT.BisProfiles[1] ~= nil
end

local LABEL = {
	str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", armor = "Armor",
	dps = "Weapon DPS", rdps = "Ranged weapon DPS", ap = "Attack power", rap = "Ranged attack power", fap = "Feral attack power",
	def = "Defense", dodge = "Dodge %", parry = "Parry %", block = "Block %", bv = "Block value",
	hit = "Hit %", exp = "Expertise %", crit = "Crit %", haste = "Haste %", arp = "Armor penetration",
	shit = "Spell hit %", scrit = "Spell crit %", sp = "Spell power", heal = "Healing", mp5 = "Mana per 5",
	spen = "Spell penetration", sp_shadow = "Shadow damage", sp_fire = "Fire damage", sp_frost = "Frost damage",
	sp_arcane = "Arcane damage", sp_nature = "Nature damage", sp_holy = "Holy damage",
}
local ORDER = { "sta", "armor", "def", "dodge", "parry", "block", "bv", "str", "agi", "ap", "rap", "fap", "dps", "rdps", "hit", "exp", "crit",
	"haste", "arp", "int", "spi", "sp", "heal", "mp5", "shit", "scrit", "spen", "sp_shadow", "sp_fire", "sp_frost", "sp_arcane", "sp_nature", "sp_holy" }
B.LABEL, B.ORDER = LABEL, ORDER

-- the rows of the grid: title, slot of BL.SLOTS, which of that slot's items, the game's inventory slot
local ROWS = {
	{ "Head", 1, 1, 1 }, { "Neck", 2, 1, 2 }, { "Shoulder", 3, 1, 3 }, { "Back", 4, 1, 15 }, { "Chest", 5, 1, 5 },
	{ "Wrist", 6, 1, 9 }, { "Hands", 7, 1, 10 }, { "Waist", 8, 1, 6 }, { "Legs", 9, 1, 7 }, { "Feet", 10, 1, 8 },
	{ "Ring 1", 11, 1, 11 }, { "Ring 2", 11, 2, 12 }, { "Trinket 1", 12, 1, 13 }, { "Trinket 2", 12, 2, 14 },
	{ "Main hand", 13, 1, 16 }, { "Off hand", 13, 2, 17 }, { "Ranged", 14, 1, 18 },
}
local WEARABLE = {}
for _, slot in ipairs(BL.SLOTS) do
	for loc in pairs(slot[2] or {}) do WEARABLE[loc] = true end
end
for _, hands in pairs(BL.HANDS) do
	for _, locs in ipairs(hands) do
		for loc in pairs(locs) do WEARABLE[loc] = true end
	end
end

local function Num(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok or type(a) ~= "number" or (issecretvalue and issecretvalue(a)) then return nil end
	return a, type(b) == "number" and b or nil
end
local function Fight() return InCombatLockdown and InCombatLockdown() or false end
local function Level() return UnitLevel and UnitLevel("player") or 0 end
local function ClassName(class)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or (class:sub(1, 1) .. class:sub(2):lower())
end

---------------------------------------------------------------------------
-- What an item gives
---------------------------------------------------------------------------

local partial = {} -- [id] = an item whose tooltip never came: its stats as far as the game gave them, for this session
local items, asked, askedAt = {}, {}, {} -- [id] = { id, loc, s, name, q, lvl, class, sub, only } or false (not gear); [id] = times asked, and when last
local FACTS = 3 --(the shape of what is kept in db.facts: raise it when BL.Stats counts something else, and every item is learned anew)
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local RETRY, tried = 30, {} -- (a bare-stats item is looked at again after RETRY seconds; tried = how often)
local ASKS, GAP = 6, 4 -- (an item is asked of the game this many times, this many seconds apart, then left alone)
local function Now() return GetTime and GetTime() or 0 end
local CLASSES = (ITEM_CLASSES_ALLOWED or "Classes: %s"):match("^(.-)%%s") or "Classes: "
local UNIQUE = ITEM_UNIQUE or "Unique" -- ("Unique" and "Unique (2)": one to carry; "Unique-Equipped": one to wear)
local RACES = (ITEM_RACES_ALLOWED or "Races: %s"):match("^(.-)%%s") or "Races: "
-- "Requires Theramore Expeditionary Force - Exalted": the game's own words, made a pattern (faction, standing)
local REP = "^" .. (ITEM_REQ_REPUTATION or "Requires %s - %s"):gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"

local function Lines(id)
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return {} end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
	local lines = ok and type(data) == "table" and data.lines
	if type(lines) ~= "table" or #lines < 1 then return nil end
	local out = {}
	for _, line in ipairs(lines) do
		if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
		local text = line.leftText
		if issecretvalue and issecretvalue(text) then return nil end
		if type(text) == "string" then
			if RETRIEVING_ITEM_INFO and text == RETRIEVING_ITEM_INFO then return nil end
			out[#out + 1] = text
		end
	end
	return out
end

-- An item's facts; false for what is not worn; nil while the game has not loaded it (asked again every few seconds, six times).
local function ItemOf(id)
	local it = items[id]
	if it ~= nil then return it end
	local p = partial[id]
	if p then
		-- (a bare-stats item is looked at again after RETRY seconds, three times: its tooltip may have come since)
		if (tried[id] or 0) >= 3 or Now() - p.at < RETRY then return p end
		partial[id], asked[id], tried[id] = nil, nil, (tried[id] or 0) + 1
	end
	local kept = B.db and B.db.facts and B.db.facts[id]
	if kept then items[id] = kept return kept end -- (learned in an earlier session: not asked again)
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, _, quality, _, minLevel, _, _, _, loc, icon, _, class, sub = info(id)
	if name and not WEARABLE[loc or ""] then
		items[id] = false
		return false
	end
	local lines = name and Lines(id)
	if not name or (lines == nil and (asked[id] or 0) < ASKS) then
		if (asked[id] or 0) < ASKS and (not askedAt[id] or Now() - askedAt[id] >= GAP) and C_Item and C_Item.RequestLoadItemDataByID then
			asked[id], askedAt[id] = (asked[id] or 0) + 1, Now()
			pcall(C_Item.RequestLoadItemDataByID, id)
		end
		return nil
	end
	local get = (C_Item and C_Item.GetItemStats) or GetItemStats
	local ok, stats = pcall(function() return get and get("item:" .. id) end)
	it = { id = id, loc = loc, name = name, icon = icon, q = quality or 1, lvl = minLevel or 0, class = class, sub = sub,
		s = BL.Stats(ok and type(stats) == "table" and stats or nil, lines) }
	-- (a bow's or wand's damage is the ranged weapon's: another word, as a profile weighs it apart)
	if it.s.dps and RANGED[loc or ""] then it.s.rdps, it.s.dps = it.s.dps, nil end
	for _, text in ipairs(lines or {}) do
		if text:sub(1, #CLASSES) == CLASSES then it.only = text:sub(#CLASSES + 1) end
		if text:sub(1, #RACES) == RACES then it.races = text:sub(#RACES + 1) end
		if text:sub(1, #UNIQUE) == UNIQUE or text == (ITEM_UNIQUE_EQUIPPABLE or "Unique-Equipped") then it.unique = true end
		if text == (ITEM_BIND_ON_EQUIP or "Binds when equipped") then it.boe = true end
		local faction, standing = text:match(REP)
		if faction then it.rep, it.repAt = faction, standing end
	end
	-- (kept only with its tooltip: without, the stats its text gives are missing, and the next look may find them)
	if lines then
		items[id] = it
		if B.db and B.db.facts then B.db.facts[id] = it end
	else
		it.partial, it.at = true, Now()
		partial[id] = it
		if (tried[id] or 0) < 3 and C_Timer and C_Timer.After then C_Timer.After(RETRY + 1, function() B.Stale() end) end
	end
	return it
end

-- Gear worn with a random suffix (Bonelink Armor of the Bandit): its stats are of the link, not of the bare item.
-- [item number] = the suffix part of its link, while one such is worn (see Worn); its facts kept for the session.
-- ponytail: the worn one only. One of the same number in the bags with another suffix reads as the worn one.
B.suffixed = {}
local byLink = {}
function B.Item(id)
	local link = B.suffixed[id]
	local it = ItemOf(id)
	if not (link and it) then return it end
	if byLink[link] then return byLink[link] end
	local get = (C_Item and C_Item.GetItemStats) or GetItemStats
	local ok, stats = pcall(function() return get and get(link) end)
	local lines
	if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
		local fine, data = pcall(C_TooltipInfo.GetHyperlink, link)
		if fine and type(data) == "table" and type(data.lines) == "table" then
			lines = {}
			for _, line in ipairs(data.lines) do
				if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
				if type(line.leftText) == "string" and not (issecretvalue and issecretvalue(line.leftText)) then lines[#lines + 1] = line.leftText end
			end
		end
	end
	if not (ok and type(stats) == "table" and next(stats)) and not lines then return it end -- (not loaded yet: the bare item for now)
	local mine = {}
	for k, v in pairs(it) do mine[k] = v end
	mine.s = BL.Stats(ok and type(stats) == "table" and stats or nil, lines)
	if mine.s.dps and RANGED[mine.loc or ""] then mine.s.rdps, mine.s.dps = mine.s.dps, nil end
	local name = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(link)
	mine.name = name or it.name
	if lines then byLink[link] = mine end
	return mine
end

-- the game will not tell of this item: asked for as often as we do, the last time a while ago
function B.Gone(id)
	return (asked[id] or 0) >= ASKS and Now() - (askedAt[id] or 0) >= GAP
end

-- Realistic (db.settings.realistic): gear that asks for a standing I do not have is left out.
-- My standing with each faction by name (1 Hated .. 8 Exalted), read once per working out (B.Stale clears it).
-- ponytail: factions under a header folded shut in the Reputation window are not seen, so their gear counts as
-- out of reach; a standing gained shows after Recalculate or the next change of gear.
local standings
local function Standing(faction)
	if not standings then
		standings = {}
		local n = Num(GetNumFactions) or 0
		for i = 1, n do
			local ok, name, _, standing = pcall(GetFactionInfo, i)
			if ok and type(name) == "string" and type(standing) == "number" then standings[name] = standing end
		end
	end
	return standings[faction] or 0
end
local LABELS
local function Needed(label)
	if not LABELS then
		LABELS = {}
		for n = 1, 8 do
			for _, g in ipairs({ "FACTION_STANDING_LABEL" .. n, "FACTION_STANDING_LABEL" .. n .. "_FEMALE" }) do
				if type(_G[g]) == "string" then LABELS[_G[g]] = n end
			end
		end
	end
	return LABELS[label] or 8
end
function B.RepOk(it)
	return not (it and it.rep) or Standing(it.rep) >= Needed(it.repAt)
end
local function Realistic() return B.db and B.db.settings.realistic and true or false end

-- may this character wear it (level aside when "later" is set: gear to grow into)
local function Usable(it, who, later)
	if it.rep and Realistic() and not who.foreign and not B.RepOk(it) then return false end
	if not later and it.lvl > who.level then return false end
	if it.only and not it.only:find(who.className, 1, true) then return false end
	if it.races and who.race and not it.races:find(who.race, 1, true) then return false end -- (a faction's gear: Races: lists)
	local V = DT.Market and DT.Market.View
	if V and V.MayUse and it.class then
		local ok, may = pcall(V.MayUse, it.class, it.sub, who.who)
		if ok and may == false then return false end
	end
	return true
end

local function Who()
	local V = DT.Market and DT.Market.View
	local level = B.ViewLevel()
	local ok, who = pcall(function() return V and V.Character and V.Character(level) end)
	-- (a level other than mine: what I have trained says nothing of it, so Classic's rules)
	if ok and who and level ~= Level() then who.trained = false end
	local name = UnitClass and UnitClass("player") or ""
	return { level = level, className = name, race = UnitRace and UnitRace("player") or nil, who = ok and who or nil }
end

-- Who gear is looked for: me, or for the spec of another class its own at the last level (what it may wear
-- by Classic's rules: the game says nothing of what another class has trained).
local function Target()
	local class = B.Raw().class
	if class == B.MyClass() then return class, Who() end
	local level = B.ViewLevel()
	return class, { level = level, className = ClassName(class), foreign = true, who = { me = class, level = level, trained = false } }
end

-- The gear there is to get, found by Sift below: what to look at, what was kept, where each is from. Looked at
-- anew with a level gained, another class picked, and once the item list has been read.
local finder = { todo = {}, got = {}, kind = {}, ckind = {}, tries = {}, gone = 0 }
local POOL = 6 -- (of the gear found, the best this many for each place to wear go into the best set: it must stay quick to work out)
local function FinderKey()
	local Item = DT.Item
	local class, who = Target()
	local phase = B.Phase()
	return ("%d:%s:%s:%s:%s:%s"):format(who.level, class, tostring(Item and Item.Ready and Item.Ready() or false), tostring(DT.Dungeon ~= nil), phase and phase[1] or "-", tostring(Realistic()))
end

---------------------------------------------------------------------------
-- What the finder found, kept in the saved file
---------------------------------------------------------------------------
-- The gear there is to get (Gather and Sift below) takes the whole item index and a walk through it; what it comes to
-- is a short list of item numbers and kinds. That list is kept per key (level, class, phase), with the item facts
-- (db.facts), so that a new session shows the lists of a slot and the sets at once, without reading the index. It is
-- looked at again, quietly, when it is older than KEEP_AGE; and it is thrown away whole where what it was built from
-- changed (the shape of the facts, the versions of QuestieDB, OneForAll's dungeons and the skill-ups in the store).
-- The last KEEP_KEYS keys used are kept, no more.
-- ponytail: the dungeon list that AtlasLoot adds and a guild's news are not in the stamp: they come with the look again after KEEP_AGE.
local KEEP_KEYS, KEEP_AGE = 6, 30 * 86400 -- (looked through again by hand, the Recalculate button; or where some never loaded)
local keptList = setmetatable({}, { __mode = "k" }) -- (an entry's saved pairs, as rows)
local function Clock() return GetServerTime and GetServerTime() or time and time() or 0 end
-- "5 min", "3 h", "2 days": how long ago a time of Clock was
local function Ago(t)
	local ago = math.max(0, Clock() - t)
	return ago < 3600 and (math.floor(ago / 60) .. " min") or ago < 172800 and (math.floor(ago / 3600) .. " h") or (math.floor(ago / 86400) .. " days")
end
local function Stamp()
	local DB, out = DT.DB, { FACTS, "k5" } -- ("k2": how the kept list itself is made; a change of that throws old ones away)
	for _, source in ipairs({ "questie", "oneforall", "skillup" }) do out[#out + 1] = tostring(DB and DB.Base and DB.Base(source)) end
	return table.concat(out, "|")
end
local function BaseKey()
	local class, who = Target()
	local phase = B.Phase()
	return ("%d:%s:%s:%s"):format(who.level, class, phase and phase[1] or "-", Realistic() and "r" or "a")
end
-- the kept entry for what is looked at now, or nil
local function Entry()
	local k = B.db and B.db.kept
	if not k then return nil end
	local stamp = Stamp()
	if k.stamp ~= stamp then
		k.stamp, k.keys, k.order = stamp, {}, {} -- (built from something else: none of it is right)
		finder.key, finder.keptKey = nil, nil
	end
	return k.keys[BaseKey()]
end
-- the entry, if it is young enough to be taken as it is
local function Fresh()
	local e = Entry()
	return e and Clock() - (e.at or 0) < KEEP_AGE and e or nil
end
-- what has been found, for the key looked at: what the finder has once it is done, else what was kept, else what it has so far
local function Cands()
	local mine = finder.key == FinderKey()
	if mine and #finder.todo == 0 then return finder.got end
	local e = Entry()
	if e then
		local list = keptList[e]
		if not list then
			list = {}
			for i = 1, #e.got, 2 do
				list[#list + 1] = { id = e.got[i], kind = e.got[i + 1] }
				finder.ckind[e.got[i]] = e.got[i + 1]
			end
			keptList[e] = list
		end
		return list
	end
	return mine and finder.got or {}
end
local function Touch(key)
	local order = B.db.kept.order
	if order[1] == key then return end
	for i = #order, 1, -1 do
		if order[i] == key then table.remove(order, i) end
	end
	table.insert(order, 1, key)
	while #order > KEEP_KEYS do B.db.kept.keys[table.remove(order)] = nil end
end
-- the finder is done: what it found is kept under its key (by item number, so the same finds are the same list), and
-- where that differs from what was kept the sets are worked out anew
local function Keep()
	local k = B.db and B.db.kept
	if finder.keptKey == finder.key or not k or k.stamp ~= Stamp() then return end
	finder.keptKey = finder.key
	local sorted = {}
	for i, c in ipairs(finder.got) do sorted[i] = c end
	table.sort(sorted, function(a, b) return a.id < b.id end)
	local flat = {}
	for _, c in ipairs(sorted) do
		flat[#flat + 1] = c.id
		flat[#flat + 1] = c.kind
	end
	local key, old = BaseKey(), k.keys[BaseKey()]
	local same = old and #old.got == #flat
	for i = 1, same and #flat or 0 do
		if old.got[i] ~= flat[i] then same = false break end
	end
	k.keys[key] = same and old or { got = flat }
	-- (some never loaded: the list is looked at again in a quarter of an hour, not after KEEP_AGE)
	k.keys[key].at = Clock() - (finder.gone > 0 and KEEP_AGE - 900 or 0)
	Touch(key)
	if not same then B.Stale() end
end

local function Name(id)
	local it = id and B.Item(id)
	if not id then return "" end
	if not it then return ("|cff888888item %d|r"):format(id) end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.q]
	return (c and c.hex or "|cffffffff") .. it.name .. "|r"
end
B.Name = Name

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------

local resolved
B.MAX_LEVEL = 60

function B.MyClass()
	local _, class = UnitClass("player")
	return class
end

-- The level looked at: the one picked for this character, else my own (a spec of another class: the last level).
function B.ViewLevel()
	local set = B.db and B.db.level[B.me]
	if set then return set end
	return B.Raw().class == B.MyClass() and Level() or B.MAX_LEVEL
end

-- a level picked (nil: mine)
function B.SetLevel(n)
	n = tonumber(n)
	n = n and math.max(1, math.min(B.MAX_LEVEL, math.floor(n))) or nil
	B.db.level[B.me], B.slotMode, B.scroll = n ~= Level() and n or nil, false, 0
	resolved = nil
	B.Stale()
end

-- At the last level, which raids count: each one ticked on its own (what a guild can do, ten, twenty or forty of
-- them), none = pre-raid. Forever's own first (AtlasLoot's Forever list: Onyxia's Lair, Mount Hyjal, the Barrow
-- Deeps), then the old world's, which Forever has not opened. Kept per character: B.db.phase[me] = { [raid] = true }.
-- ponytail: no raid sizes or dates: Forever's data does not have them. The player ticks what their guild runs.
B.RAIDS = { "Onyxia's Lair", "Mount Hyjal", "Barrow Deeps Raid", "Molten Core", "Zul'Gurub", "Blackwing Lair", "Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj", "Naxxramas" }
B.FOREVER_RAIDS = 3
-- { id, name, raids } of what is ticked; nil below the last level
function B.Phase()
	if B.ViewLevel() < B.MAX_LEVEL then return nil end
	local on = type(B.db.phase[B.me]) == "table" and B.db.phase[B.me] or {}
	local raids = {}
	for _, name in ipairs(B.RAIDS) do
		if on[name] then raids[#raids + 1] = name end
	end
	if not raids[1] then return { "pre", "Pre-raid", raids } end
	return { table.concat(raids, "+"), "Pre-raid + " .. table.concat(raids, ", "), raids }
end
function B.SetRealistic(on)
	B.db.settings.realistic, B.slotMode, B.scroll = on and true or false, false, 0
	B.Stale()
end
-- "pre": no raid; a raid's name: that one ticked or unticked
function B.SetPhase(id)
	local on = type(B.db.phase[B.me]) == "table" and B.db.phase[B.me] or {}
	if id == "pre" then on = {} else on[id] = not on[id] or nil end
	B.db.phase[B.me], B.slotMode, B.scroll = next(on) and on or nil, false, 0
	B.Stale()
end

-- may a dungeon's drops be looked for at this phase (a dungeon that is no raid always)
local function RaidOk(phase, d)
	local Dg = DT.Dungeon
	if not (phase and Dg and Dg.IsRaid and Dg.IsRaid(d)) or phase[3] == true then return true end
	for _, name in ipairs(phase[3]) do
		if Dg.Key(name) == (d.key or Dg.Key(d.name)) then return true end
	end
	return false
end

-- A raid the dungeon list does not have still drops its gear, which the item list then knows as a plain drop or
-- a quest's reward. Told apart by where it comes from: the zone the mobs or chests that drop it stand in, and the
-- zone the quest that gives it is filed under, against the raids D.IsRaid knows by name.
-- ponytail: gear MADE of what a raid drops (crafted from its materials, bought with its tokens) is not told.
-- (the old world's raids by the number of their zone: the name the game gives a zone is not always the raid's.
-- Any other zone: by its name, for a raid of Forever's own that D.IsRaid has)
local RAID_AREA = DT.Dungeon.RAID_AREA
local raidZone = {} -- [area] = { name = } of the raid that zone is, or false
local function RaidOf(area)
	if type(area) ~= "number" or area <= 0 then return nil end
	if raidZone[area] == nil then
		local Dg = DT.Dungeon
		local ok, name = pcall(function() return RAID_AREA[area] or C_Map.GetAreaInfo(area) end)
		local d = ok and type(name) == "string" and { name = name } or nil
		raidZone[area] = d and Dg and Dg.IsRaid and Dg.IsRaid(d) and d or false
	end
	return raidZone[area] or nil
end

-- is an item from a raid this phase does not have (see above)
local FROM = { { "npcDrops", "npc", "zoneID" }, { "objectDrops", "object", "zoneID" }, { "questRewards", "quest", "zoneOrSort" } }
local function FromRaid(id, phase)
	if not phase or phase[3] == true then return false end
	local Q = DT.DB.Q
	for _, from in ipairs(FROM) do
		local list = Q("item", id, from[1])
		for _, thing in ipairs(type(list) == "table" and list or {}) do
			local d = RaidOf(Q(from[2], thing, from[3]))
			if d and not RaidOk(phase, d) then return true end
		end
	end
	return false
end

-- Points spent in each talent tree, in the game's order. Which of these this client has is not known before it
-- is seen: every call is guarded, and a client that has none of them gives an empty list.
local function Points()
	local get = GetTalentTabInfo or (C_SpecializationInfo and C_SpecializationInfo.GetTalentTabInfo)
	local points, any = {}, false
	if type(get) == "function" then
		for i = 1, math.min(Num(GetNumTalentTabs) or 3, 3) do
			local ok, a, _, c, _, e = pcall(get, i)
			-- (Classic: name, icon, points spent; later clients: id, name, description, icon, points spent)
			local spent = ok and (type(a) == "number" and e or c)
			if type(spent) == "number" and not (issecretvalue and issecretvalue(spent)) then points[i], any = spent, true end
		end
	end
	if not any then -- (a client that names the active spec only: its place is the tree)
		local at = Num(GetSpecialization) or Num(C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
		if at and at >= 1 then points[math.floor(at)] = 1 end
	end
	return points
end

-- The spec I am: the tree with the most points, as the profile named for it (BL.SpecId); nil where it cannot be told.
-- ponytail: a tree with a tank and a damage profile (Feral: cat and bear) gives the plain one, the cat.
function B.Default()
	return BL.SpecId(B.MyClass(), Points(), DT.BisProfiles or {})
end

-- the profile picked, of any class; to begin with my spec, else the first of my class
function B.Raw()
	local want, mine = B.db.pick[B.me] or B.Default(), B.MyClass()
	local first
	for _, p in ipairs(DT.BisProfiles or {}) do
		if p.id == want then return p end
		if not first and p.class == mine then first = p end
	end
	return first or (DT.BisProfiles or {})[1]
end

-- the profiles of the class looked at
function B.Mine()
	local raw, list = B.Raw(), {}
	for _, p in ipairs(DT.BisProfiles or {}) do
		if raw and p.class == raw.class then list[#list + 1] = p end
	end
	return list
end

-- the profile in use, with what was changed on the Weights view laid over it
function B.Profile()
	if resolved then return resolved end
	local raw = B.Raw()
	if not raw then return nil end
	local edit = B.db.edit[raw.id] or {}
	-- (no hands said: what the class may do, which is not to wield two weapons for all but four of them)
	local hands = raw.hands or ((raw.class == "WARRIOR" or raw.class == "ROGUE" or raw.class == "HUNTER" or raw.class == "SHAMAN") and { "2h", "dw", "shield", "held" } or { "2h", "shield", "held" })
	-- (two weapons: my own class at my own level, the client says; else the profile's hands, and none before level 20)
	-- ponytail: the level-20 gate is a guess for another level or class; the client cannot say what it would be there.
	local no
	if raw.class == B.MyClass() and B.ViewLevel() == Level() then
		if CanDualWield then no = not CanDualWield()
		elseif IsSpellKnown then no = not IsSpellKnown(674) end
	end
	if no == nil then no = B.ViewLevel() < 20 end
	if no then
		local out, has = {}, {}
		for _, name in ipairs(hands) do
			if name ~= "dw" then out[#out + 1], has[name] = name, true end
		end
		for _, name in ipairs({ "2h", "shield", "held" }) do
			if not has[name] then out[#out + 1] = name end
		end
		hands = out
	end
	local p = { id = raw.id, title = raw.title, hands = hands, w = {}, caps = {}, raw = raw }
	for word, n in pairs(raw.w) do p.w[word] = n end
	-- (profiles weigh "dps" for the weapon the class fights with: a hunter's is the ranged one, anyone else's the melee one;
	-- the other kind counts a tenth. ponytail: one tenth for all, until the sims say what an off kind is worth.)
	if p.w.rdps == nil and p.w.dps then
		if raw.class == "HUNTER" then p.w.rdps, p.w.dps = p.w.dps, p.w.dps / 10 else p.w.rdps = p.w.dps / 10 end
	end
	-- The caps are those of the last level. Below it the defense cap is lower, five a level (it is what a boss
	-- three levels up asks for: 440 at 60), and it is not yet a thing to reach before all else.
	local below = math.max(0, B.MAX_LEVEL - B.ViewLevel())
	for word, cap in pairs(raw.caps) do
		p.caps[word] = { cap = cap.cap - (word == "def" and below * 5 or 0), over = cap.over, hard = cap.hard and below == 0 or nil, buff = cap.buff }
	end
	for word, n in pairs(edit.w or {}) do p.w[word] = n end
	for word, cap in pairs(edit.caps or {}) do
		if cap == false then
			p.caps[word] = nil
		else
			local at = p.caps[word] or { over = 0 }
			at.cap, at.over, at.buff = cap.cap or at.cap, cap.over or at.over, cap.buff or at.buff
			p.caps[word] = at.cap and at or nil
		end
	end
	for word in pairs(p.caps) do p.w[word] = p.w[word] or 0 end
	resolved = p
	return p
end

local dirty, state, gains = true, nil, {}
local waiting, wanted
-- (worked out a moment on, and only while the tab is up or a tooltip has asked: not for every bag change)
local function Arm()
	if not waiting and C_Timer and C_Timer.After then
		waiting = true
		C_Timer.After(1.5, function()
			waiting = nil
			if dirty and B.db and (wanted or (B.panel and B.panel:IsShown())) then wanted = nil B.State() end
		end)
	end
end
local function Stale()
	standings = nil -- (my reputations: read again)
	dirty = true
	if B.Refresh and B.panel and B.panel:IsShown() then B.redraw = true end
	Arm()
end
B.Want = function() if dirty then wanted = true Arm() end end -- (a tooltip wants a state that is not stale)
B.Stale = Stale

-- a spec picked, by its id
function B.Pick(id)
	B.db.pick[B.me] = id
	local raw = B.Raw()
	if raw then B.db.last[raw.class] = raw.id end
	resolved = nil
	Stale()
end

-- a class picked: its spec looked at last, else its first
function B.PickClass(class)
	local want, first = B.db.last[class], class == B.MyClass() and B.Default() or nil
	for _, p in ipairs(DT.BisProfiles or {}) do
		if p.class == class and (not first or p.id == want) then first = p.id end
	end
	if first then B.Pick(first) end
end

-- A weight or a cap changed by hand: field "w", "cap", "over" or "buff"; value nil puts the profile's own back.
function B.Edit(word, field, value)
	local raw = B.Raw()
	local edit = B.db.edit[raw.id] or { w = {}, caps = {} }
	if field == "w" then
		edit.w[word] = value
	else
		if field ~= "cap" and (edit.caps[word] == false or not (raw.caps[word] or edit.caps[word])) then return end -- (no cap to change)
		local cap = type(edit.caps[word]) == "table" and edit.caps[word] or {}
		cap[field] = value
		edit.caps[word] = cap
		-- (the cap emptied: back to the default, as the weights are)
		if field == "cap" and not value then edit.caps[word] = nil end
		if type(edit.caps[word]) == "table" and not next(edit.caps[word]) then edit.caps[word] = nil end -- (back to the default)
	end
	B.db.edit[raw.id] = (next(edit.w) or next(edit.caps)) and edit or nil -- (nothing changed any more: nothing kept)
	resolved = nil
	Stale()
end

function B.ResetEdits()
	B.db.edit[B.Raw().id] = nil
	resolved = nil
	Stale()
end

---------------------------------------------------------------------------
-- The character sheet, and what is left of it without gear
---------------------------------------------------------------------------

-- What the character sheet says, of what we can ask it; a stat it does not answer for is left out.
-- ponytail: which of the game's calls this client answers is not known before it is seen in game; the Check
-- view shows what came back, to be held against the character pane.
function B.Sheet()
	local s = {}
	local skill, bonus = Num(UnitDefense, "player")
	if skill then s.def = skill + (bonus or 0) end
	local rating = function(index) return Num(GetCombatRatingBonus, index) end
	local hit, hitRating = Num(GetHitModifier), rating(CR_HIT_MELEE or 6)
	if hit or hitRating then s.hit = (hit or 0) + (hitRating or 0) end
	local shit, shitRating = Num(GetSpellHitModifier), rating(CR_HIT_SPELL or 8)
	if shit or shitRating then s.shit = (shit or 0) + (shitRating or 0) end
	local points = Num(GetExpertise)
	s.exp = Num(GetExpertisePercent) or (points and points * 0.25) or rating(CR_EXPERTISE or 24)
	s.dodge, s.parry, s.block, s.crit = Num(GetDodgeChance), Num(GetParryChance), Num(GetBlockChance), Num(GetCritChance)
	s.bv = Num(GetShieldBlock)
	for i, word in ipairs({ "str", "agi", "sta", "int", "spi" }) do
		local _, value = Num(UnitStat, "player", i)
		s[word] = value
	end
	local _, armor = Num(UnitArmor, "player")
	s.armor = armor
	return s
end

-- what I wear: [row] = item number; and its summed stats, or nil while an item of it is not loaded yet
local function Worn()
	local cur, gear, whole = {}, {}, true
	B.suffixed = {}
	for r, row in ipairs(ROWS) do
		local id = GetInventoryItemID and GetInventoryItemID("player", row[4])
		if type(id) == "number" then
			cur[r] = id
			-- (a random suffix: the sixth number after the item number in its link, not 0)
			local link = GetInventoryItemLink and GetInventoryItemLink("player", row[4])
			local suffix = type(link) == "string" and link:match("item:%-?%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d+)")
			if suffix and suffix ~= "0" then B.suffixed[id] = link end
			local it = B.Item(id)
			if it == nil or (it and it.partial) then whole = false end
			if it then BL.Add(gear, it.s) end
		end
	end
	return cur, gear, whole -- (gear: of what has loaded; whole: all of it, so the sheet may be read against it)
end

-- The capped stats without gear. Kept per character, as it cannot be read in a fight.
local BASED = { "def", "hit", "shit", "exp" }
local function Base(gear)
	local kept = B.db.base[B.me]
	if not gear or Fight() then return kept end
	local sheet, base = B.Sheet(), {}
	for _, word in ipairs(BASED) do
		if sheet[word] then base[word] = sheet[word] - (gear[word] or 0) end
	end
	-- (a client that does not say the defense: what the level gives)
	base.def = base.def or Level() * 5
	B.db.base[B.me] = base
	return base
end

---------------------------------------------------------------------------
-- The sets
---------------------------------------------------------------------------

local function Key(pick)
	if not pick.key then
		local ids = { unpack(pick.ids) }
		table.sort(ids)
		pick.key = table.concat(ids, "+")
	end
	return pick.key
end

-- picks laid out by row; two rings or trinkets stay where the same one is worn now
local function Lay(picks, cur)
	local out = {}
	for r, row in ipairs(ROWS) do
		local ids = picks[row[2]] and picks[row[2]].ids or {}
		out[r] = ids[row[3]]
	end
	for _, r in ipairs({ 11, 13 }) do
		if out[r] and out[r + 1] and (out[r] == cur[r + 1] or out[r + 1] == cur[r]) and out[r] ~= cur[r] then
			out[r], out[r + 1] = out[r + 1], out[r]
		end
	end
	return out
end

B.stats = { computes = 0, kept = 0, solves = 0 } -- (since the /reload: for Data Debug)
local function Solve(list, s)
	B.stats.solves = B.stats.solves + 1
	local slots = BL.Choices(list, s.prof)
	local picks, gear, score, short = BL.Solve(slots, s.base, s.prof)
	return { picks = picks, gear = gear, score = score, short = short }
end

local worker = CreateFrame("Frame")
worker:Hide()

-- What the sets and the upgrades are worked out from, as one text: the same text, the same answer. The weights and
-- caps (with what was typed), the level, the phase, the hands, what I wear, what I own, what was found; and how
-- the item facts are read (Stamp).
local function Sig(s)
	local p = s.prof
	local out = { Stamp(), p.id, s.who.level, tostring((B.Phase() or {})[1]), tostring(Realistic()), table.concat(p.hands or {}, ",") }
	local words = {}
	for word in pairs(p.w) do words[#words + 1] = word end
	table.sort(words)
	for _, word in ipairs(words) do
		local c = p.caps[word]
		out[#out + 1] = word .. "=" .. tostring(p.w[word]) .. (c and ("/" .. tostring(c.cap) .. "/" .. tostring(c.over) .. "/" .. tostring(c.hard)) or "")
	end
	for _, word in ipairs({ "def", "hit", "shit", "exp" }) do out[#out + 1] = ("%.2f"):format(s.base[word] or 0) end
	for r = 1, #ROWS do out[#out + 1] = tostring(s.cur[r] or 0) .. (B.suffixed[s.cur[r] or 0] or "") end
	for _, list in ipairs({ s.own, s.all or {} }) do
		out[#out + 1] = "|"
		for _, c in ipairs(list) do out[#out + 1] = c.id .. "x" .. (c.n or 1) end
	end
	out[#out + 1] = "|" .. table.concat(s.queue, ",")
	return table.concat(out, ";")
end

-- Kept in the saved file, per character and spec (db.saved): the two sets and the upgrades, with every gain worked
-- out, so that a /reload shows them without working anything out. Not while items are still loading.
local function Bare(set) return set and { picks = set.picks, gear = set.gear, score = set.score, short = set.short } end
local function Save(s)
	if s.foreign or s.pending > 0 or not s.sig or s ~= state then return end
	s.at = Clock()
	B.db.saved[s.skey] = { sig = s.sig, at = s.at, best = Bare(s.best), bis = Bare(s.bis), upg = s.upg, gains = gains }
end

-- Everything worked out anew: what I wear, the best of what I own, the best of the list. False in a fight.
function B.Compute()
	if Fight() then return false end
	local prof = B.Profile()
	if not prof then return false end
	local s = { prof = prof, have = {}, own = {}, pending = 0, rank = {} }
	s.who = select(2, Target())
	-- (a spec of another class looked at: my gear is not its gear, so only its list and weights are shown)
	s.foreign = prof.raw.class ~= B.MyClass()
	local gear, whole
	s.cur, gear, whole = Worn()
	if s.foreign then s.cur, gear, whole = {}, {}, false end
	s.base = (not s.foreign and Base(whole and gear or nil)) or { def = s.who.level * 5 }
	-- (a level other than mine: the defense skill without gear goes five a level with it; what the sheet calls the
	-- skill itself, as the bar on top shows it, goes along)
	local skill = not s.foreign and Num(UnitDefense, "player")
	local moved = (s.who.level - Level()) * 5
	if skill then s.skill = math.max(0, skill + moved) end
	local own = s.base
	s.base = {}
	for word, n in pairs(own) do s.base[word] = n end
	if not s.foreign and moved ~= 0 then s.base.def = math.max(0, (own.def or 0) + moved) end
	-- (at the last level: what consumables and buffs give a capped stat, as typed on the Weights view)
	if s.who.level >= B.MAX_LEVEL then
		for word, cap in pairs(prof.caps) do
			if cap.buff then s.base[word] = (s.base[word] or 0) + cap.buff end
		end
	end
	s.curGear = gear or {}
	s.curScore, s.curShort = BL.Score(s.curGear, s.base, prof)
	for _, id in pairs(s.cur) do s.have[id] = (s.have[id] or 0) + 1 end
	local Inv = DT.Inventory
	local mine = Inv and Inv.db and Inv.db.chars and Inv.db.chars[Inv.me]
	for _, bag in ipairs(s.foreign and {} or { mine and mine.bags or {}, mine and mine.bank or {} }) do
		for id, n in pairs(bag) do s.have[id] = (s.have[id] or 0) + n end
	end
	for id, n in pairs(s.have) do
		local it = B.Item(id)
		if it == nil then
			s.pending = s.pending + 1
		elseif it and Usable(it, s.who) then
			s.own[#s.own + 1] = { id = id, loc = it.loc, s = it.s, n = it.unique and 1 or n }
		end
	end
	table.sort(s.own, function(a, b) return a.id < b.id end)
	-- the list: what of it the game knows and this class may wear, whatever the level; and with it the best of
	-- what the finder (below) found for this class in the quests, dungeons, crafts and drops, a few of each place to wear
	s.list = DT.BisLists and DT.BisLists[prof.id]
	s.queue, s.upg = {}, {}
	local all, seen, found = {}, {}, {}
	local function Add(id, it)
		seen[id] = true
		all[#all + 1] = { id = id, loc = it.loc, s = it.s, n = 1 }
		if not s.have[id] and not s.foreign then s.queue[#s.queue + 1] = id end
	end
	for id in pairs(s.list or {}) do
		local it = B.Item(id)
		if it == nil then
			s.pending = s.pending + 1
		elseif it and Usable(it, s.who) then -- (only what may be worn at the level looked at: the list is what to aim for there)
			Add(id, it)
		end
	end
	local cands = Cands()
	finder.used = #cands
	for _, c in ipairs(cands) do
		local it = not seen[c.id] and B.Item(c.id)
		-- (a kept list may be older than what I have learned to wear since)
		if it and Usable(it, s.who) then
			found[it.loc] = found[it.loc] or {}
			table.insert(found[it.loc], { id = c.id, it = it, v = (BL.Score(it.s, {}, prof)) })
		end
	end
	-- (the least of what I wear in each place: a find past the best few of its place that beats it is still looked
	-- at for Upgrades, though it does not go into the best set; one for a place I wear nothing in, too)
	local worn = {}
	for _, id in pairs(s.cur) do
		local it = B.Item(id)
		if it then
			local v = BL.Score(it.s, {}, prof)
			if not worn[it.loc] or v < worn[it.loc] then worn[it.loc] = v end
		end
	end
	for _, list in pairs(found) do
		table.sort(list, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.id < b.id end)
		local taken = {}
		for i = 1, math.min(#list, POOL) do taken[list[i].id] = true Add(list[i].id, list[i].it) end
		-- (and the most of each hard-capped stat, which the score may rank low and the solver needs to reach the cap)
		for word, cap in pairs(prof.caps) do
			if cap.hard then
				local by = { unpack(list) }
				table.sort(by, function(a, b)
					local x, y = a.it.s[word] or 0, b.it.s[word] or 0
					if x ~= y then return x > y end
					return a.id < b.id
				end)
				for i = 1, math.min(#by, 2) do
					if (by[i].it.s[word] or 0) > 0 and not taken[by[i].id] then taken[by[i].id] = true Add(by[i].id, by[i].it) end
				end
			end
		end
		-- ponytail: by the item alone against the worn one; a find that only helps a cap through the set is missed past the best few
		for i = POOL + 1, #list do
			local c = list[i]
			if not s.foreign and not seen[c.id] and not s.have[c.id] and (not worn[c.it.loc] or c.v > worn[c.it.loc]) then s.queue[#s.queue + 1] = c.id end
		end
	end
	if #all > 0 then
		table.sort(all, function(a, b) return a.id < b.id end)
		table.sort(s.queue)
		s.all = all
	end
	-- what was worked out from the very same as now, in this session or an earlier one: taken as it is
	s.sig, s.skey = Sig(s), B.me .. "|" .. prof.id
	local saved = not s.foreign and B.db.saved[s.skey]
	local had
	B.stats.computes = B.stats.computes + 1
	-- (the same as what is worked out already, or still being worked out: kept, with what the worker has done so far.
	-- Selling junk changes the bags, not what may be worn: every sale at a vendor began it all anew)
	if state and state.sig == s.sig and state.skey == s.skey then
		B.stats.kept = B.stats.kept + 1
		dirty = false
		return true
	end
	if saved and saved.sig == s.sig then
		s.best, s.bis, s.upg, s.queue, s.at, had = Bare(saved.best), Bare(saved.bis), saved.upg, {}, saved.at, saved.gains
		for i, u in ipairs(s.upg) do s.rank[u.id] = i end
	else
		s.best = Solve(s.own, s)
		if s.all then s.bis = Solve(all, s) end
	end
	s.best.rows = Lay(s.best.picks, s.cur)
	s.best.has = {}
	for _, id in pairs(s.best.rows) do s.best.has[id] = true end
	if s.bis then s.bis.rows = Lay(s.bis.picks, s.cur) end
	state, dirty, gains = s, false, had or {}
	if not had and #s.queue == 0 then Save(s) end
	worker:SetShown(#s.queue > 0)
	return true
end

-- Worked out anew by hand (the Recalculate button): what was saved for the spec, and the gear found for it, go
function B.Recalc()
	local s = state
	if s and s.skey then B.db.saved[s.skey] = nil end
	if B.db.kept.keys then B.db.kept.keys[BaseKey()] = nil end
	finder.key, finder.keptKey = nil, nil
	Stale()
end

-- the state, worked out anew where something changed (in a fight: as it was)
function B.State()
	if dirty and not Fight() then
		local ok, err = pcall(B.Compute)
		if not ok then
			dirty = false -- (not tried again on every tooltip)
			geterrorhandler()(err)
		end
	end
	return state
end

-- What an item would do for my best set: { d = gain in score, pct, slots = { names of the slots it changes },
-- reach = { stats whose hard cap it gets me to }, owned, best, no = cannot wear, level = wearable from }.
-- nil while it cannot be said (not loaded, not gear, a fight with nothing worked out).
-- (lazy: with what was worked out last, for a tooltip, which must not wait for a new working out)
function B.Gain(id, lazy)
	local s = lazy and state or B.State()
	if not s then return nil end
	if gains[id] ~= nil then return gains[id] or nil end
	if Fight() then return nil end -- (nothing asked of the game, nothing worked out, in a fight)
	local it = B.Item(id)
	if it == nil then return nil end
	if lazy and not s.have[id] then
		-- (a tooltip does not wait for a full solve: one the worker has in line goes to the front and shows when done)
		for i, q in ipairs(s.queue) do
			if q == id then
				table.remove(s.queue, i)
				s.queue[#s.queue + 1] = id
				worker:Show()
				return nil
			end
		end
	end
	local g = false
	if it then
		g = {}
		if s.have[id] then
			g.owned, g.best = true, s.best.has[id] or false
		elseif not Usable(it, s.who, true) then
			g.no = true
		elseif Fight() then
			return nil
		else
			local list = { unpack(s.own) }
			list[#list + 1] = { id = id, loc = it.loc, s = it.s, n = 1 }
			local with = Solve(list, s)
			local den = s.bis and s.bis.score or s.best.score
			g.d, g.slots, g.reach = with.score - s.best.score, {}, {}
			g.pct = den > 0 and g.d / den * 100 or nil
			for i, pick in ipairs(with.picks) do
				if Key(pick) ~= Key(s.best.picks[i]) then
					-- (a ring or trinket takes one place; the hands say which: two-hand, main hand, off hand)
					local name = BL.SLOTS[i][1]
					if i == 11 or i == 12 then name = name:sub(1, -2) end
					if i == 13 then
						name = it.loc == "INVTYPE_2HWEAPON" and "Two-hand" or (pick.ids[2] == id or it.loc == "INVTYPE_SHIELD" or it.loc == "INVTYPE_HOLDABLE") and "Off hand" or "Main hand"
					end
					g.slots[#g.slots + 1] = name
				end
			end
			for word in pairs(s.best.short) do
				if not with.short[word] then g.reach[#g.reach + 1] = word end
			end
			if it.lvl > s.who.level then g.level = it.lvl end
			-- (nothing gained, though it reaches a cap: it does help)
			g.up = g.d > 0.005 or #g.reach > 0
		end
	end
	gains[id] = g
	return g or nil
end

-- the list's items I do not own, one a frame: what each would gain, the most first
worker:SetScript("OnUpdate", function(self)
	local s = state
	if not s or dirty or #s.queue == 0 then return self:Hide() end
	if Fight() then return end
	-- ponytail: a solve takes tens of ms and cannot be cut short: one a frame at most, then about nine times as long
	-- left alone. A cheaper gain (only the slots the item touches) would be the next step.
	local now = GetTime and GetTime() or 0
	if now < (self.rest or 0) then return end
	local t0 = debugprofilestop and debugprofilestop()
	local id = table.remove(s.queue)
	local g = B.Gain(id)
	if t0 then self.rest = now + (debugprofilestop() - t0) * 9 / 1000 end
	if g and g.up and not g.level then s.upg[#s.upg + 1] = { id = id, g = g } end
	if #s.queue == 0 then
		table.sort(s.upg, function(a, b)
			if (#a.g.reach > 0) ~= (#b.g.reach > 0) then return #a.g.reach > 0 end
			if a.g.d ~= b.g.d then return a.g.d > b.g.d end
			return a.id < b.id
		end)
		for i, u in ipairs(s.upg) do s.rank[u.id] = i end
		Save(s)
		B.redraw = true
		self:Hide()
	end
end)

-- where an item of the list is from: the boss that drops it, the profession that makes it; else the list's word
function B.Source(id)
	local ok, where = pcall(function() return DT.FavTab and DT.FavTab.Where and DT.FavTab.Where(id) or "" end)
	if ok and where ~= "" then return where end
	local list = state and state.list
	return list and type(list[id]) == "string" and list[id] or ""
end

---------------------------------------------------------------------------
-- Tooltip and roll
---------------------------------------------------------------------------

local function Signed(n) return ("%+.1f"):format(n) end

-- an item that would improve my best set, as worked out (Upgrades); nil where not known or another class is looked at
-- ponytail: what is worked out so far only. An item not looked at yet (or still in line) says nothing.
function B.IsUpgrade(id)
	if not B.db then return nil end -- (BiS switched off, or not started yet)
	local s = state or B.State() -- (the saved sets, where the BiS tab has not been open this session)
	if not s or s.foreign then return nil end
	local g = gains[id]
	return g and g.up and not g.level and not g.owned or false
end

-- the words for a gain: "+12.4 (+1.8%)  Head, Rings"
function B.GainText(g)
	if g.owned then return g.best and "|cff40ff40in your best set|r" or "|cff888888owned, not in your best set|r" end
	if g.no then return "|cff888888not for your class|r" end
	if not g.up then return "|cff888888no gain|r" end
	local text = "|cff40ff40" .. Signed(g.d) .. "|r"
	if g.pct then text = text .. (" |cff40ff40(%+.1f%%)|r"):format(g.pct) end
	if #g.slots > 0 then text = text .. "  " .. table.concat(g.slots, ", ") end
	if g.level then text = text .. ("  |cffff8040at level %d|r"):format(g.level) end
	return text
end

local function TooltipLine(tip, data)
	if not (B.db and B.db.settings.tooltip) or type(tip) ~= "table" or not tip.AddDoubleLine then return end
	local id = type(data) == "table" and data.id
	if not id and tip.GetItem then
		local _, link = tip:GetItem()
		id = link and tonumber(link:match("item:(%d+)"))
	end
	if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then return end
	if dirty then B.Want() end
	local s = state or B.State()
	if not s or s.foreign then return end -- (another class looked at: nothing to say of my gear)
	local g = B.Gain(id, true)
	if not g or g.no then return end -- (not for my class: said nothing, as the game's own red lines say it)
	local rank = s.rank[id] and ("  |cffffd100#%d upgrade|r"):format(s.rank[id]) or ""
	-- (one I own but do not wear, or one that does not better the best set: what it does against what I wear now)
	local worn = false
	for _, w in pairs(s.cur) do worn = worn or w == id end
	local vs = ""
	if not worn and (g.owned or not g.up) then
		local _, d, p = B.VsWorn(s, id)
		if d and math.abs(d) > 0.05 then
			vs = ("  |cff%s%s%s vs worn|r"):format(d > 0 and "40ff40" or "c86464", Signed(d), p and (" (%+.1f%%)"):format(p) or "")
		end
	end
	tip:AddDoubleLine(DT.TIP .. "BiS  |cff888888" .. s.prof.title .. "|r", B.GainText(g) .. vs .. rank, 0.78, 0.68, 0.37, 1, 1, 1)
	for _, word in ipairs(g.reach or {}) do
		tip:AddDoubleLine(" ", ("|cff40ff40reaches %s %g|r"):format(LABEL[word] or word, s.prof.caps[word].cap), 1, 1, 1, 1, 1, 1)
	end
end
-- (it runs on every item tooltip there is: whatever goes wrong in it stays in it)
function B.OnTooltip(tip, data)
	local ok, err = pcall(TooltipLine, tip, data)
	if not ok then DT:Debug("bis", "tooltip: %s", tostring(err)) end
end

-- an item is rolled for: a line in the chat with what it would do
-- ponytail: a chat line, and the tooltip line on the roll frame's item; nothing is drawn on the roll frame itself.
local function RollLine(rollID)
	if not B.db.settings.roll or not GetLootRollItemLink then return end
	local ok, link = pcall(GetLootRollItemLink, rollID)
	local id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
	local s = id and B.State()
	local g = s and not s.foreign and B.Gain(id)
	if not g or g.no or g.owned then return end
	local reach = {}
	for _, word in ipairs(g.reach or {}) do reach[#reach + 1] = ("reaches %s %g"):format(LABEL[word] or word, state.prof.caps[word].cap) end
	DT:Print("BiS (%s): %s  %s%s", state.prof.title, link, B.GainText(g), #reach > 0 and ("  |cff40ff40" .. table.concat(reach, ", ") .. "|r") or "")
end
function B.OnRoll(rollID)
	local ok, err = pcall(RollLine, rollID)
	if not ok then DT:Debug("bis", "roll: %s", tostring(err)) end
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
-- On top the nine classes, as their pictures, and under them the specs of the class picked. Below, Gear: how far
-- along I am, the caps and the stats along the top; every slot with what I wear down the left; and on the right,
-- for the slot clicked, the best I own, the list's pick, and the best quest rewards, dungeon drops, crafted and
-- world-drop gear of my level.

local TOP_H, ROW_H = 58, 18
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_ART = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local EMPTY_ART = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local VIEWS = { { "gear", "Gear" }, { "up", "Upgrades" }, { "weights", "Weights" }, { "check", "Check" } }
local panel, status
local frames, viewButtons, classButtons, specButtons = {}, {}, {}, {}
local view, offset, picked = "gear", 0, 1 -- (picked: the row of ROWS whose items the middle lists)
B.classButtons, B.specButtons = classButtons, specButtons

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local function ClassColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 1, 0.82, 0
end

local function ShowItem(owner, id, anchor)
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. id)
	GameTooltip:Show()
	DT:CompareTip(owner)
end

-- a click on an item, as on any item row: with Shift its link, with Alt a favourite. True when it was one of those.
local function ItemClick(id, button)
	local it = B.Item(id)
	local name = it and it.name or ("item " .. id)
	return DT:LinkClick(button, DT:GameItemLink(id, name), name, DT:ItemLink(id), id)
end

-- a cell that shows an item: hover for its tooltip, click as on any item row
local function ItemCell(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(ROW_H)
	b.text = Text(b)
	b.text:SetAllPoints()
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnEnter", function(self)
		if not self.id then return end
		ShowItem(self, self.id)
		-- (a quest reward: where the quest is picked up, in full, and what a click does)
		for _, text in ipairs(self.swap or {}) do GameTooltip:AddLine(text, 1, 1, 1, true) end -- (a piece of a set: what it does to the set I wear)
		GameTooltip:Show()
		if self.quest then
			if self.note then GameTooltip:AddLine(self.note, 1, 1, 1, true) end
			GameTooltip:AddLine("Click: a waypoint to where the quest is picked up", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self, button)
		if not self.id or ItemClick(self.id, button) then return end
		if self.quest and DT.Quest and DT.Quest.Waypoint then DT.Quest.Waypoint(self.quest) end
	end)
	return b
end

-- fill colours by state: short of the cap amber, reached green, well over a cooler tone; gold for progress
local BAR = { gold = { 0.78, 0.68, 0.37, 0.7 }, met = { 0.2, 0.7, 0.3, 0.8 }, short = { 0.85, 0.6, 0.2, 0.8 }, over = { 0.3, 0.6, 0.85, 0.8 } }
local function Bar(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:SetHeight(16)
	b:EnableMouse(true)
	b.back = b:CreateTexture(nil, "BACKGROUND")
	b.back:SetAllPoints()
	b.back:SetColorTexture(1, 1, 1, 0.08)
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetPoint("TOPLEFT", 0, 0)
	b.fill:SetHeight(16)
	b.value = Text(b, "GameFontHighlightSmall", "RIGHT")
	b.value:SetPoint("RIGHT", -4, 0)
	b.text = Text(b, "GameFontHighlightSmall")
	b.text:SetPoint("LEFT", 4, 0)
	b.sub = Text(parent, "GameFontDisableSmall") -- (a line under it, for what does not fit the bar)
	b.sub:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 2, -1)
	b:SetScript("OnEnter", function(self)
		if not self.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		for _, line in ipairs(self.tip) do GameTooltip:AddLine(line, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- part: 0 to 1; state: short, met, over or gold; label on the left, value on the right
	function b:Set(part, state, label, value, sub, tip)
		part = math.max(0, math.min(1, part))
		self.fill:SetWidth(math.max(1, (self.width or self:GetWidth()) * part)) -- (width: said by who lays it out, before the game has)
		self.fill:SetShown(part > 0)
		local c = BAR[state] or BAR.gold
		self.fill:SetColorTexture(c[1], c[2], c[3], c[4])
		self.text:SetText(label)
		self.value:SetText(value or "")
		self.sub:SetWidth(self.width or self:GetWidth())
		self.sub:SetText(sub or "")
		self.tip = tip
	end
	return b
end

local function Fmt(n) return ("%g"):format(math.floor(n * 10 + 0.5) / 10) end

-- "Defense 12, Stamina 20": an item's stats in words
function B.StatText(s)
	local parts = {}
	for _, word in ipairs(ORDER) do
		if s[word] and s[word] ~= 0 then parts[#parts + 1] = ("%s %s"):format(LABEL[word], Fmt(s[word])) end
	end
	return table.concat(parts, ", ")
end

-- Defense as the character sheet gives it: the base skill, the most it can be at the level looked at, and what gear
-- (and anything else on the sheet) adds to it; then the total. A client that does not say the skill (UnitDefense):
-- the skill is what the tab works out without gear, up to the most.
function B.Defense(s)
	local set = s.foreign and s.bis and s.bis.gear or s.curGear
	local total = (s.base.def or 0) + (set.def or 0)
	local max = s.who.level * 5
	local skill = s.skill or math.min(max, s.base.def or 0)
	return skill, max, total - skill, total
end

-- What an item adds to a set: the set's score with it, less the score without. set = the set's summed stats,
-- out = the item it would take the place of (itself, for one that is in the set). A capped stat so counts only
-- as far as it counts in that set.
local function Worth(s, set, id, out)
	local it, gone = id and B.Item(id), out and B.Item(out)
	if not it then return nil end
	local g = BL.Add({}, set)
	if gone then BL.Add(g, gone.s, -1) end
	local without = BL.Score(g, s.base, s.prof)
	return BL.Score(BL.Add(g, it.s), s.base, s.prof) - without
end
B.Worth = Worth

-- may an item worn there (loc) go in this row
local function Fits(r, loc, prof)
	local row = ROWS[r]
	local slot = BL.SLOTS[row[2]]
	if not slot.hands then return slot[2][loc] and true or false end
	for _, name in ipairs(prof.hands or { "2h", "dw", "shield", "held" }) do
		local h = BL.HANDS[name]
		if h and h[row[3]] and h[row[3]][loc] then return true end
	end
	return false
end

-- An item against the worn piece it would replace (the weaker of two rings or trinkets; none: an empty slot):
-- its weight there, the change, and that in percent of the worn piece's weight (nil for an empty slot).
-- nil where it cannot be said (not loaded, or worn in no slot this spec uses).
function B.VsWorn(s, id)
	local it = B.Item(id)
	if not it then return nil end
	local out, outW, any = nil, nil, false
	for r = 1, #ROWS do
		if Fits(r, it.loc, s.prof) then
			any = true
			local w = s.cur[r] and Worth(s, s.curGear, s.cur[r], s.cur[r]) or 0
			if not outW or w < outW then out, outW = s.cur[r], w end
		end
	end
	if not any then return nil end
	local worth = Worth(s, s.curGear, id, out)
	if not worth then return nil end
	local d = worth - (outW or 0)
	return worth, d, out and (outW or 0) > 0.05 and d / outW * 100 or nil, out
end

---------------------------------------------------------------------------
-- What there is to get: quest rewards, dungeon drops, crafted and world-drop gear of about my level
---------------------------------------------------------------------------
-- Which items there are is not DawnTools' own: read at runtime from QuestieDB as the Items tab reads it (quest
-- rewards, drops), from the dungeon list (Modules/Dungeon.lua) and the recipes (DT.Recipes: from the store, Core/DBSeed.lua). What each
-- gives is asked of the game, a batch a pass, and rated with the profile in use.
-- ponytail: gear asking for a level up to WINDOW below mine (the game is asked for every one of them once a
-- session); a quest reward counts whichever side gives the quest.

local WINDOW = 15
local function Cap(type) return type < 300 and 60 or type < 402 and 150 or 100 end -- (asked of the game for a weapon type, for rings, necks, trinkets and cloaks, for an armor type)
-- the words for where an item is from (the owner's: crafted, bought, found, quest); a boss's drop is a Raid where its dungeon is one
local TAG = { quest = "Quest", crafted = "Crafted", boe = "World Drop", vendor = "Vendor", dungeon = "Dungeon", owned = "Owned" }
local LISTKIND = { ["dungeon drop"] = "dungeon", crafted = "crafted", quest = "quest", ["world drop"] = "boe" } -- (the words of Data/BisLists.lua)
local RANK = { dungeon = 5, quest = 4, crafted = 3, boe = 2, vendor = 1 } -- (an item of two kinds is listed under the higher)
B.finder = finder

-- the items to look at, for the class picked and its level; false while the item list is still being read
local function Gather()
	local Item = DT.Item
	local class, who = Target()
	local level = who.level
	if finder.key == FinderKey() then return true end
	if Fight() then return false end -- (a walk through every item there is: not in a fight)
	if Item and Item.Start and Item.Start() then -- (still reading: read on a little)
		Item.Step(4)
		if not Item.Ready() then return false end
	end
	finder.key, finder.todo, finder.got, finder.kind, finder.tries, finder.who, finder.gone, B.wheres = FinderKey(), {}, {}, {}, {}, who, 0, {}
	finder.keptKey = nil -- (looked through anew: what it comes to is kept again)
	local lo = level - WINDOW
	local V = DT.Market and DT.Market.View
	-- (far: a boss's drop of a dungeon that is not for this level. It is not looked for as that dungeon's, but
	-- where the item list has it anyway it is still called a dungeon's drop, not a world drop)
	local drops, barred, far, Dg, phase = {}, {}, {}, DT.Dungeon, B.Phase()
	for _, d in ipairs(Dg and Dg.All and Dg.All() or {}) do
		local near, ok = (d.lo or 0) <= level and (d.hi or 99) >= lo, RaidOk(phase, d)
		for _, boss in ipairs(d.bosses) do
			for id in pairs(boss.has) do
				-- (a raid this phase does not have: its drops are not looked for elsewhere either)
				if not near then far[id] = true elseif ok then drops[id] = true else barred[id] = true end
			end
		end
	end
	-- what the item list says without the game loading anything: gear, of a kind the class may use, of a level that suits
	local want, seen = {}, {}
	for _, e in ipairs(Item and Item.All and Item.All() or {}) do
		local boss = drops[e.id]
		if boss then seen[e.id] = true end
		-- (no level asked for: many a ring and cloak; its level is seen once the game has loaded it)
		-- (FromRaid: only asked of gear of a raid's item level, and only where the phase leaves raids out)
		if (e.c == 2 or e.c == 4) and e.req <= level and (boss or (e.req == 0 or e.req >= lo) and not barred[e.id])
			and not ((e.ilvl or 0) >= 58 and FromRaid(e.id, phase)) then
			local ok, may = pcall(function() return not (V and V.MayUse) or V.MayUse(e.c, e.s, who.who) end)
			if not ok or may ~= false then
				local kind = (boss or far[e.id] and not drops[e.id]) and "dungeon" or e.src["Quest reward"] and "quest" or ((DT.CraftSkill and DT.CraftSkill[e.id]) or e.src.Crafted) and "crafted"
					or e.src.Drop and "boe" or e.src.Vendor and "vendor" or nil
				if kind then
					finder.kind[e.id] = kind
					want[#want + 1] = { id = e.id, ilvl = e.ilvl or 0, type = e.c * 100 + e.s, boss = boss }
				end
			end
		end
	end
	for id in pairs(drops) do -- (a boss's drop the item list does not know: looked at first, there are few)
		if not seen[id] then finder.kind[id], want[#want + 1] = "dungeon", { id = id, ilvl = 999, type = 0 } end
	end
	-- ponytail: of each armor or weapon type only the best few by item level (see Cap) are asked of the game, the
	-- best of every type first (item level tracks strength closely enough; a plain piece for a slot that has few
	-- high ones can be missed). A slot cap needs the slot, which only the game's loading says.
	-- A boss's drop of a dungeon for this level is never cut: few, and the ones a list most often names (Sunken
	-- Temple's plate at 60 stood below a hundred higher pieces of plate and was never looked at).
	local types = {}
	for _, w in ipairs(want) do
		types[w.type] = types[w.type] or {}
		table.insert(types[w.type], w)
	end
	local kept = {}
	for kind, list in pairs(types) do
		table.sort(list, function(a, b) if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end return a.id < b.id end)
		for i, w in ipairs(list) do
			if kind == 0 or w.boss or i <= Cap(kind) then w.rank, kept[#kept + 1] = kind == 0 and 0 or math.min(i, Cap(kind)), w else finder.kind[w.id] = nil end
		end
	end
	table.sort(kept, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
		return a.id < b.id
	end)
	for i, w in ipairs(kept) do finder.todo[i] = w.id end
	return true
end

-- how many are still to look at for the key looked at
function B.Left() return finder.key == FinderKey() and #finder.todo or 0 end

-- a batch of them asked of the game; what is gear the class may wear is kept. Once all are looked at, what was
-- found goes into the best set (and its upgrades).
local function Sift()
	if Fight() then return end
	local fresh = Fresh()
	if fresh then return Touch(BaseKey()) end -- (kept, and not old: the index is not read at all)
	if not Gather() then return end
	if #finder.todo == 0 then return Keep() end
	-- (about 8 ms looked at a pass, and no more than 40 of them asked of the server; the best prospects come first)
	local who = finder.who
	local keep, later, unloaded = {}, {}, 0
	local t0, over = debugprofilestop and debugprofilestop(), false
	for n, id in ipairs(finder.todo) do
		if not over and t0 and n % 8 == 0 and debugprofilestop() - t0 > 8 then over = true end
		if over or n > 300 or unloaded >= 40 then
			keep[#keep + 1] = id
		else
			local it = B.Item(id)
			if it == nil then
				-- (not loaded yet: behind the rest, asked again, until the game is not going to say)
				unloaded = unloaded + 1
				if B.Gone(id) then finder.gone = finder.gone + 1 else later[#later + 1] = id end
			elseif it then
				local kind = finder.kind[id]
				if it.lvl <= who.level and (kind == "dungeon" or it.lvl >= who.level - WINDOW) and (kind ~= "boe" or it.boe) and Usable(it, who) then
					finder.got[#finder.got + 1] = { id = id, loc = it.loc, kind = kind }
				end
			end
		end
	end
	for _, id in ipairs(later) do keep[#keep + 1] = id end
	finder.todo = keep
	B.redraw = true
	-- (the set is worked out with what was found as it comes in, every few seconds, and once more when all are looked at)
	if Cands() == finder.got and #finder.got ~= finder.used and (#keep == 0 or Now() - (finder.shown or 0) >= 3) then
		finder.shown = Now()
		Stale()
	end
	if #keep == 0 then Keep() end
end
B.Sift = Sift

-- Two rings, two trinkets: the row of the other one
local PAIR = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }

-- Every usable item for a row, the most worth to this spec first, as the worn one stands among them: { above = the
-- best `above` that beat it, more = how many beat it that are not listed, worn = its row or nil, below = the best
-- `below` of the rest, none = no one of them, ref = the row whose item is the one to beat, blocked = a two-hander
-- is wielded, so no off hand }. Each row: { id, worth = its weight, gain, pct, new, kind = quest, crafted, boe,
-- vendor, dungeon or owned }.
--   gain = the real change to the score of the set I wear if it took the place of the one to beat (stats past a
--     cap count what past the cap is worth, a stat short of a cap what it brings nearer it; a two-hander in the
--     main hand takes the off hand out too);
--   worth (the weight) = the weight of the one to beat + the gain, so a row's weight less the worn row's is its
--     gain. The weight of the one to beat is what it adds to the set I wear (the set's score less the set's score
--     without it), so a stat that is capped counts as far as the cap only;
--   pct = the gain as a part of the weight of the one to beat (none where that is nothing: an empty slot is "new");
--   two worn (rings, trinkets): the one to beat is the weaker, and ref says which;
--   the worn item is the one to beat, not the best I own: an owned one that is not worn says so (kind owned).
-- ponytail: what is looked at is what the finder kept (B.finder.got), what I own and the list's items; a hard cap
-- not yet reached counts as the weight of its stat only, as in every score: the sets (B.Perm) are where it comes first.
function B.Rank(r, above, below)
	local s = state
	if not s then return nil end
	above, below = above or 500, below or 4
	local function W(id) return id and Worth(s, s.curGear, id, id) or 0 end
	local ref = r
	if PAIR[r] and W(s.cur[PAIR[r]]) < W(s.cur[r]) then ref = PAIR[r] end
	local worn, on, seen, pool = s.cur[ref], {}, {}, {}
	for _, id in pairs(s.cur) do on[id] = true end -- (a ring on the other finger is not one to get)
	local wornW = W(worn)
	local wornIt = worn and B.Item(worn)
	local mh = s.cur[15] and B.Item(s.cur[15])
	local blocked = ref == 16 and mh and mh.loc == "INVTYPE_2HWEAPON" or false
	local function Add(id, kind)
		if blocked or seen[id] or on[id] then return end
		seen[id] = true
		local it = B.Item(id)
		if it and Fits(r, it.loc, s.prof) and Usable(it, s.who) then
			local g = BL.Add({}, s.curGear)
			if wornIt then BL.Add(g, wornIt.s, -1) end
			local off = ref == 15 and it.loc == "INVTYPE_2HWEAPON" and s.cur[16] and B.Item(s.cur[16])
			if off then BL.Add(g, off.s, -1) end
			local gain = BL.Score(BL.Add(g, it.s), s.base, s.prof) - s.curScore
			pool[#pool + 1] = { id = id, worth = wornW + gain, gain = gain, kind = s.have[id] and "owned" or kind,
				pct = wornW > 0.05 and gain / wornW * 100 or nil, new = not worn or nil }
		end
	end
	for _, o in ipairs(s.own) do Add(o.id, "owned") end
	for _, c in ipairs(Cands()) do Add(c.id, c.kind) end
	for id, word in pairs(s.list or {}) do Add(id, LISTKIND[word] or "dungeon") end
	table.sort(pool, function(a, b)
		if a.worth ~= b.worth then return a.worth > b.worth end
		return a.id < b.id
	end)
	local out = { above = {}, below = {}, more = 0, none = #pool == 0, ref = ref, blocked = blocked,
		worn = worn and { id = worn, worth = wornW, worn = true } or nil }
	for _, c in ipairs(pool) do
		if c.gain > 0.05 then
			if #out.above < above then out.above[#out.above + 1] = c else out.more = out.more + 1 end
		elseif #out.below < below then
			out.below[#out.below + 1] = c
		end
	end
	return out
end

-- the short word for where an item is from: Owned, Quest, Crafted, Vendor, World Drop, Dungeon, Raid
function B.Tag(id, kind)
	if kind == "dungeon" then
		local Dg = DT.Dungeon
		local boss = Dg and Dg.DropOf and Dg.DropOf(id)
		if boss and Dg.IsRaid and Dg.IsRaid(boss.dungeon) then return "Raid" end
	end
	return TAG[kind] or "World Drop"
end

-- Whole sets to compare at the last level, each worked out from the same candidates (the list's and what the finder
-- found) with BL.Solve, when asked for and kept until the state is worked out anew:
--   What I wear: the set worn, to stand beside the others on every cap
--   Best set: the set with the best score (s.bis; the best I own where nothing was found)
--   Every cap reached: the same with every cap a hard one, so as close to each as the gear there is goes before score
--   Owned + 3 best finds: what I own and the three biggest upgrades there are (s.upg), and nothing else
B.scroll = 0 -- (how far the list on the right is scrolled)
B.PERMS, B.perm = { "What I wear", "Best set", "Every cap reached", "Owned + 3 best finds" }, 2
function B.Perm(i)
	local s = state
	if not s or Fight() then return nil end
	s.perms = s.perms or {}
	if s.perms[i] then return s.perms[i] end
	local set
	if i == 1 then
		set = { rows = s.cur, gear = s.curGear, score = s.curScore, short = s.curShort }
	elseif i == 2 then
		set = s.bis or s.best
	elseif i == 3 then
		local prof = {}
		for k, v in pairs(s.prof) do prof[k] = v end
		prof.caps = {}
		for word, cap in pairs(s.prof.caps) do prof.caps[word] = { cap = cap.cap, over = cap.over, hard = true } end
		set = Solve(s.all or s.own, { prof = prof, base = s.base })
		set.rows = Lay(set.picks, s.cur)
	else
		local list = { unpack(s.own) }
		for k = 1, math.min(3, #s.upg) do
			local it = B.Item(s.upg[k].id)
			if it then list[#list + 1] = { id = s.upg[k].id, loc = it.loc, s = it.s, n = 1 } end
		end
		set = Solve(list, s)
		set.rows = Lay(set.picks, s.cur)
	end
	-- (the upgrades are still being worked out: not kept, so the set is made again once they are)
	if i ~= 4 or #s.queue == 0 then s.perms[i] = set end
	return set
end

-- "Hit" for "Hit %"
function B.Short(word) return ((LABEL[word] or word):gsub("%s*%%$", "")) end

-- What swapping just one piece of a set into the set I wear does, for every slot where they differ: { r, id, d = the
-- change in score, pct (of the weight of the piece it replaces), caps = { [stat] = { before, after } }, words = the
-- capped stats, breaks = those it takes from reached to short, order, needs = { { word, by = the slot whose piece
-- brings most of that stat } } }. The order: swaps that break no cap I meet now first, the biggest gain first, then
-- those that break one (each says which piece to get first: the one that adds most of what it takes away).
-- ponytail: one swap at a time; two that only work together (a ring for a ring) are said as "after the other".
function B.Swaps(s, set)
	if set.swaps then return set.swaps end
	local swaps, list, words = {}, {}, {}
	for word in pairs(s.prof.caps) do words[#words + 1] = word end
	table.sort(words)
	for r = 1, #ROWS do
		local id, cur = set.rows[r], s.cur[r]
		local it = id and id ~= cur and B.Item(id)
		if it then
			local g = BL.Add({}, s.curGear)
			local function Out(x)
				local o = x and B.Item(x)
				if o then BL.Add(g, o.s, -1) end
			end
			Out(cur)
			if r == 15 and it.loc == "INVTYPE_2HWEAPON" then Out(s.cur[16]) end
			BL.Add(g, it.s)
			local w = { r = r, id = id, d = BL.Score(g, s.base, s.prof) - s.curScore, caps = {}, breaks = {}, words = words }
			local was = cur and Worth(s, s.curGear, cur, cur) or 0
			w.pct = was > 0.05 and w.d / was * 100 or nil
			for _, word in ipairs(words) do
				local cap = s.prof.caps[word].cap
				local before, after = (s.base[word] or 0) + (s.curGear[word] or 0), (s.base[word] or 0) + (g[word] or 0)
				w.caps[word] = { before = before, after = after }
				if before >= cap - 1e-9 and after < cap - 1e-9 then w.breaks[#w.breaks + 1] = word end
			end
			swaps[r], list[#list + 1] = w, w
		end
	end
	table.sort(list, function(a, b)
		if (#a.breaks == 0) ~= (#b.breaks == 0) then return #a.breaks == 0 end
		if a.d ~= b.d then return a.d > b.d end
		return a.r < b.r
	end)
	for k, w in ipairs(list) do
		w.order, w.needs = k, {}
		for j, word in ipairs(w.breaks) do
			local most, at = 0.05, nil
			for _, o in ipairs(list) do
				local got = o ~= w and o.caps[word].after - o.caps[word].before or 0
				if got > most then most, at = got, o end
			end
			w.needs[j] = { word = word, by = at and at.r }
		end
	end
	set.swaps = swaps
	return swaps
end

-- where an item of the list is from, as far as the finder and the list say (nil: not known)
function B.Kind(id)
	return finder.kind[id] or finder.ckind[id] or state and state.list and LISTKIND[state.list[id]] or nil
end

local PLAIN = { ["world drop"] = true, ["quest reward"] = true, ["sold by a vendor"] = true, dungeon = true, crafted = true }
-- "Dungeon", "Boss, Dungeon": where an item is from, and where exactly (worn: its own source, not that it is owned)
function B.SourceText(id, worn)
	local s = state
	local kind = not worn and s and s.have[id] and "owned" or B.Kind(id)
	local tag = kind and B.Tag(id, kind) or worn and "Equipped" or "World Drop"
	local where = kind and B.Where(id, kind) or ""
	if kind == "dungeon" or kind == "crafted" then where = where:gsub("^|c%x%x%x%x%x%x%x%x%a+|r%s*", "") end
	if PLAIN[where:lower()] then where = "" end
	return tag, where
end

-- where I have it: the bags or the bank (a thing worn is not asked about)
function B.Held(id)
	local Inv = DT.Inventory
	local mine = Inv and Inv.db and Inv.db.chars and Inv.db.chars[Inv.me]
	if mine and mine.bags and (mine.bags[id] or 0) > 0 then return "in your bags" end
	if mine and mine.bank and (mine.bank[id] or 0) > 0 then return "in your bank" end
	return "owned"
end

-- where one of them is from, in a few words
B.wheres, B.quests = {}, {} -- (quests: [item] = the quest that gives it, for a click on its line)
function B.Where(id, kind)
	local wheres = B.wheres
	if kind == "owned" then return B.Held(id) end -- (not kept: the bags change)
	if wheres[id] then return wheres[id] end
	local text = B.Source(id)
	if kind == "quest" then
		-- where the quest is picked up comes first: who gives it and in which zone, then its name
		local Q = DT.Quest
		local fact = DT.DB.RelTo("rewards", "item", id)[1]
		local quest = fact and fact.id
		local e = quest and Q and Q.Entry and Q.Entry(quest)
		if quest and not e and Q and Q.Start and Q.Start() then -- (the quests are still being read: read on, ask again)
			Q.Step(4)
			return "quest reward  |cff888888reading the quests...|r"
		end
		if e then
			local o = Q.Origin and Q.Origin(e)
			local side = Q.Side and Q.Side(e) or ""
			local mine = UnitFactionGroup and UnitFactionGroup("player") == "Alliance" and "A" or "H"
			B.quests[id] = e
			text = ("|cffffd100%s|r%s  |cff888888%s|r%s"):format(o and o.text or "giver not known", e.zoneName and (", " .. e.zoneName) or "", e.name,
				side ~= "" and side ~= mine and "  |cffff4040other faction|r" or "")
		else
			text = text ~= "" and text or "quest reward"
		end
	elseif kind == "boe" then
		local api = DawnMarket and DawnMarket.API
		local price = api and api.GetLatest and (api.GetLatest(id))
		return price and ("|cff888888auction|r  " .. DT.Money(price)) or "world drop" -- (a price moves: not kept)
	elseif text == "" then
		text = kind == "crafted" and "crafted" or kind == "vendor" and "sold by a vendor" or "dungeon"
	end
	wheres[id] = text
	return text
end

---------------------------------------------------------------------------
-- Gear: what I wear down the left, the stats along the top, and for the slot clicked what there is to get
---------------------------------------------------------------------------

local LEFT_W = 300
local gear = { slots = {}, caps = {}, lines = {} }
B.gear = gear

-- how good what is worn in a row is, held against the list's item for it: the colour of its mark
local function Tier(part)
	if part >= 0.995 then return 0.2, 0.9, 0.35 end -- as good as the list's
	if part >= 0.85 then return 1, 0.82, 0
	elseif part >= 0.6 then return 0.75, 0.75, 0.75 end
	return 0.8, 0.3, 0.3
end

-- one slot: a mark in the colour of how good it is, the item's picture, the slot's name, the item, its worth
local function Slot(f, r)
	local b = CreateFrame("Button", nil, f)
	b.row = r
	b.tint = b:CreateTexture(nil, "BACKGROUND")
	b.tint:SetAllPoints()
	b.tint:SetColorTexture(1, 1, 1, 0.04)
	b.tint:SetShown(r % 2 == 0)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(1, 0.82, 0, 0.14)
	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	b.tier = b:CreateTexture(nil, "ARTWORK")
	b.tier:SetPoint("TOPLEFT", 0, -1)
	b.tier:SetPoint("BOTTOMLEFT", 0, 1)
	b.tier:SetWidth(3)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(16, 16)
	b.icon:SetPoint("LEFT", 6, 0)
	b.title = Text(b, "GameFontDisableSmall")
	b.title:SetPoint("LEFT", 26, 0)
	b.title:SetWidth(58)
	b.score = Text(b, nil, "RIGHT")
	b.score:SetPoint("RIGHT", -3, 0)
	b.score:SetWidth(62)
	b.name = Text(b)
	b.name:SetPoint("LEFT", 86, 0)
	b.name:SetPoint("RIGHT", b.score, "LEFT", -2, 0)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnEnter", function(self)
		if self.id then ShowItem(self, self.id) end
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self, button)
		if self.id and ItemClick(self.id, button) then return end
		picked, B.slotMode, B.scroll = self.row, true, 0
		B.Refresh()
	end)
	return b
end

-- the steady colour of each kind of source (as World > Finds colours its kinds)
local KIND = { Owned = "40ff40", Quest = "ffd100", Dungeon = "ff8040", Raid = "ff5060", Crafted = "40c0ff", Vendor = "e0c080", ["World Drop"] = "c080ff", Equipped = "888888" }
local ROW, GREY, BELOW = 18, "|cff888888", 4 -- (BELOW: how many worse items stand under the worn one)

-- a line of the right side, made when the window has room for it: a note, or an item in the columns of the list
local function Line(f)
	local l = { f = f }
	l.tint = f:CreateTexture(nil, "BACKGROUND")
	l.tint:SetColorTexture(1, 1, 1, 0.04)
	l.band = f:CreateTexture(nil, "BACKGROUND") -- (the worn item: a quiet band between two thin rules)
	l.band:SetColorTexture(1, 0.82, 0, 0.10)
	l.rule1, l.rule2 = f:CreateTexture(nil, "ARTWORK"), f:CreateTexture(nil, "ARTWORK")
	l.rule1:SetColorTexture(1, 0.82, 0, 0.35)
	l.rule2:SetColorTexture(1, 0.82, 0, 0.35)
	l.head = Text(f, "GameFontDisableSmall")
	l.icon = f:CreateTexture(nil, "ARTWORK")
	l.icon:SetSize(14, 14)
	l.item = ItemCell(f)
	local highlight = l.item:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	l.n, l.wt, l.diff, l.pct = Text(f, "GameFontDisableSmall"), Text(f, nil, "RIGHT"), Text(f, nil, "RIGHT"), Text(f, "GameFontDisableSmall", "RIGHT")
	l.from, l.warn = Text(f), Text(f)
	return l
end

local function BuildGear(f)
	gear.f = f
	gear.progress = Bar(f)
	gear.progress:SetPoint("TOPLEFT", 6, -2)
	gear.progress:SetWidth(LEFT_W - 6)
	for i = 1, 4 do gear.caps[i] = Bar(f) end
	gear.stats = Text(f)
	gear.stats:SetPoint("TOPLEFT", 6, -22)
	gear.stats:SetWidth(LEFT_W - 12)
	for r = 1, #ROWS do gear.slots[r] = Slot(f, r) end
	-- the right side: of the slot clicked, one list: what beats the worn item, the worn item, and a few that do not
	gear.head = Text(f, "GameFontNormal")
	gear.note = Text(f, "GameFontDisableSmall")
	gear.note:SetPoint("LEFT", gear.head, "RIGHT", 10, 0)
	gear.note:SetPoint("RIGHT", f, "RIGHT", -206, 0)
	gear.cols = {}
	for c = 1, 7 do gear.cols[c] = Text(f, "GameFontNormalSmall", c >= 2 and c <= 4 and "RIGHT" or "LEFT") end -- (the muted gold of the other tabs)
	-- (the last level: the whole set to begin with, in a few versions to compare as tabs; a way back to it from a slot)
	gear.perms = {}
	for k, name in ipairs(B.PERMS) do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(150, 18)
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetAllPoints()
		b.sel:SetColorTexture(1, 0.82, 0, 0.18)
		local highlight = b:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)
		b.label = Text(b, "GameFontHighlightSmall", "CENTER")
		b.label:SetAllPoints()
		b.label:SetText(name)
		b:SetScript("OnClick", function() B.perm, B.scroll = k, 0 B.Refresh() end)
		gear.perms[k] = b
	end
	gear.back = CreateFrame("Button", nil, f)
	gear.back:SetSize(90, 18)
	local shade = gear.back:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, 0.08)
	gear.back.label = Text(gear.back, "GameFontHighlightSmall", "CENTER")
	gear.back.label:SetAllPoints()
	gear.back.label:SetText("Whole set")
	gear.back:SetScript("OnClick", function() B.slotMode, B.scroll = false, 0 B.Refresh() end)
	-- (what is shown is kept from one session to the next: looked through and worked out anew on a click)
	gear.redo = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	gear.redo:SetSize(90, 18)
	gear.redo:SetText("Recalculate")
	gear.redo:SetScript("OnClick", function() B.Recalc() end)
	gear.sum = {} -- (the set's score and caps beside mine: a small table of its own above the items)
	-- the thin scroll bar of the NPC tab, for a list that is longer than the panel
	gear.bar = CreateFrame("Slider", nil, f)
	gear.bar:SetOrientation("VERTICAL")
	gear.bar:SetWidth(8)
	gear.bar:SetPoint("TOPRIGHT", -1, -2)
	gear.bar:SetPoint("BOTTOMRIGHT", -1, 2)
	gear.bar:SetValueStep(1)
	gear.bar:SetObeyStepOnDrag(true)
	local track = gear.bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.3)
	gear.bar.thumb = gear.bar:CreateTexture(nil, "OVERLAY")
	gear.bar.thumb:SetColorTexture(0.78, 0.68, 0.37, 0.9)
	gear.bar:SetThumbTexture(gear.bar.thumb)
	gear.bar:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value + 0.5)
		if value == B.scroll then return end -- (Refresh sets the bar too)
		B.scroll = value
		B.Refresh()
	end)
	gear.bar:Hide()
end

local function DrawSlot(b, r, s)
	local cur, best, bis = s.cur[r], s.best.rows[r], s.bis and s.bis.rows[r]
	-- (another class looked at: the list's set is what there is to show)
	local shown = cur or (s.foreign and bis) or nil
	local it = shown and B.Item(shown)
	b.id = shown or bis or best
	b.sel:SetShown(picked == r)
	b.icon:SetTexture(it and it.icon or EMPTY_ART)
	b.title:SetText(ROWS[r][1])
	-- (what the item adds to the set it is in: mine, and the list's)
	local worth = Worth(s, s.foreign and s.bis and s.bis.gear or s.curGear, shown, shown)
	local top = s.bis and Worth(s, s.bis.gear, bis, bis)
	local part = (bis and shown == bis) and 1 or (worth and top and top > 0) and worth / top or nil
	if part then b.tier:SetColorTexture(Tier(part)) else b.tier:SetColorTexture(1, 1, 1, shown and 0.25 or 0.08) end
	b.score:SetText(worth and (Fmt(worth) .. (part and (" |cff888888%d%%|r"):format(math.floor(part * 100 + 0.5)) or "")) or "")
	-- (a green mark: something I own is better here)
	b.name:SetText((not s.foreign and best and best ~= cur and "|cff40ff40>|r " or "") .. (shown and Name(shown) or "|cff666666nothing worn|r"))
end

-- a number with its sign, in green or a muted red; nothing worth saying: grey
local function Signed(n, fmt)
	if n > 0.05 then return ("|cff40ff40" .. fmt .. "|r"):format(n) end
	if n < -0.05 then return ("|cffc86464" .. fmt .. "|r"):format(n) end
	return "|cff8888880|r"
end

local function DrawGear(f, s)
	local w, h = f:GetWidth(), f:GetHeight()
	if w < LEFT_W + 120 then return end -- (not laid out yet)
	-- along the top: how far along, the caps (one height, label left and value right, the fill by state), the stats that count
	gear.progress.width = LEFT_W - 6
	if s.foreign then
		gear.progress:Set(0, "gold", s.bis and ("%s: %s"):format(s.list and "Best pre-raid set" or "Best set found", Fmt(s.bis.score))
			or B.Left() > 0 and "|cff888888Looking for gear...|r" or "|cff888888No gear found for this spec yet|r")
	elseif s.bis and s.bis.score > 0 then
		local part = s.curScore / s.bis.score
		gear.progress:Set(part, part >= 0.995 and "met" or "gold", ("%d%% of the best %s"):format(math.floor(part * 100 + 0.5), s.list and "pre-raid set" or "set found"))
	else
		local part = s.best.score > 0 and s.curScore / s.best.score or 0
		gear.progress:Set(part, part >= 0.995 and "met" or "gold", ("%d%% of the best I own  |cff888888(no pre-raid list yet)|r"):format(math.floor(part * 100 + 0.5)))
	end
	local words = {}
	for word in pairs(s.prof.caps) do words[#words + 1] = word end
	table.sort(words)
	local n = math.min(#words, #gear.caps)
	local capW = (w - LEFT_W - 12) / math.max(1, n)
	local set = s.foreign and s.bis and s.bis.gear or s.curGear
	for i, bar in ipairs(gear.caps) do
		local word = words[i]
		bar:SetShown(i <= n)
		if i > n then
			bar.sub:SetText("")
		else
			local cap = s.prof.caps[word]
			local now, best = (s.base[word] or 0) + (set[word] or 0), (s.base[word] or 0) + (s.best.gear[word] or 0)
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", LEFT_W + 6 + (i - 1) * capW, -2)
			bar:SetWidth(capW - 4)
			bar.width = capW - 4
			local state = now < cap.cap - 1e-9 and "short" or now >= cap.cap * 1.1 and "over" or "met"
			local value = ("%s / %s"):format(Fmt(now), Fmt(cap.cap)) .. (not s.foreign and math.abs(best - now) > 0.05 and ("  |cff888888(owned: %s)|r"):format(Fmt(best)) or "")
			local sub, tip
			if word == "def" then
				-- (defense: the base skill over the most it can be at the level, and what gear adds: a line under the bar and its tooltip)
				local skill, max, bonus, total = B.Defense(s)
				local plus = (bonus >= 0 and "+" or "") .. Fmt(bonus)
				sub = ("%sskill %s/%s %s gear|r"):format(GREY, Fmt(skill), Fmt(max), plus)
				tip = { ("Defense skill %s of %s at level %d"):format(Fmt(skill), Fmt(max), s.who.level), ("Gear and anything else on the sheet: %s"):format(plus),
					("Total %s, the cap is %s"):format(Fmt(total), Fmt(cap.cap)) }
			end
			bar:Set(cap.cap > 0 and now / cap.cap or 0, state, LABEL[word] or word, value, sub, tip)
		end
	end
	local parts = { ("|cffffd100Score %s|r"):format(Fmt(s.foreign and s.bis and s.bis.score or s.curScore)) }
	for _, word in ipairs(ORDER) do
		if (s.prof.w[word] or 0) > 0 and not s.prof.caps[word] and (set[word] or 0) ~= 0 then
			parts[#parts + 1] = ("%s |cffffffff%s|r"):format(LABEL[word], Fmt(set[word]))
		end
	end
	gear.stats:SetText("|cffaaaaaa" .. table.concat(parts, "   ") .. "|r")
	-- down the left: every slot
	local top = 40
	local rowH = math.max(16, math.min(22, math.floor((h - top) / #ROWS)))
	for r, b in ipairs(gear.slots) do
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 6, -top - (r - 1) * rowH)
		b:SetSize(LEFT_W - 6, rowH - 1)
		DrawSlot(b, r, s)
	end
	-- the right: at the last level the whole set to begin with (a breakpoint game: the set I wear and sets to compare,
	-- where each stands on its caps, and what each piece alone would do); below it, and at the last level once a slot
	-- is clicked, one list for the slot
	local x, rw = LEFT_W + 10, w - LEFT_W - 24
	local phase = B.Phase()
	local showSet = phase ~= nil and not B.slotMode
	local vis = s.foreign and { 2, 3 } or { 1, 2, 3, 4 } -- (the sets shown: not "what I wear" for another class)
	if s.foreign and (B.perm == 1 or B.perm == 4) then B.perm = 2 end
	local perm = showSet and B.Perm(B.perm) or nil
	gear.head:ClearAllPoints()
	gear.head:SetPoint("TOPLEFT", x, -top)
	gear.head:SetText(showSet and "Whole set" or ROWS[picked][1])
	gear.back:ClearAllPoints()
	gear.back:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -top)
	gear.back:SetShown(phase ~= nil and not showSet)
	gear.redo:ClearAllPoints()
	gear.redo:SetPoint("TOPRIGHT", f, "TOPRIGHT", -108, -top)
	gear.redo:SetShown(not s.foreign)
	for _, b in ipairs(gear.perms) do b:Hide() end
	for k, idx in ipairs(vis) do
		local b = gear.perms[idx]
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", x + (k - 1) * 154, -top - 20)
		b:SetShown(showSet)
		b.sel:SetShown(idx == B.perm)
	end
	local ready = Fresh() and true or Gather()
	local left = B.Left()
	gear.note:SetText(not ready and "reading the item list..." or left > 0 and ("%d items still to look at, the best so far are shown..."):format(left)
		or ("level %d, %s%s%s"):format(s.who.level, s.who.className, phase and (", " .. phase[2]:lower()) or "", s.at and (", worked out %s ago"):format(Ago(s.at)) or ""))
	-- the columns: icon, name, then right-aligned numbers (weight, difference, percent), the source and, in a set, a warning
	local P
	if showSet then
		P = { n = 0, nw = 54, icon = 56, name = 74, namew = 142, diff = 220, diffw = 48, pct = 272, pctw = 50, kind = 330, warnw = 128 }
	else
		P = { icon = 2, name = 20, namew = 170, wt = 194, wtw = 44, diff = 242, diffw = 48, pct = 294, pctw = 50, kind = 352 }
	end
	P.warn = showSet and rw - P.warnw or nil
	P.wherew = math.max(40, (P.warn and P.warn - 6 or rw) - P.kind)
	-- the caps, as I stand and as the set would: reached (over by how much) or short by how much
	local function Standing(total, cap)
		if total >= cap - 1e-9 then
			return ("|cff%s%s %s%s|r"):format(total >= cap * 1.1 and "60a8e0" or "40ff40", Fmt(total), total >= cap * 1.1 and "well over" or "reached", total > cap + 0.05 and (", +" .. Fmt(total - cap)) or "")
		end
		return ("|cffe8a030%s short by %s|r"):format(Fmt(total), Fmt(cap - total))
	end
	-- the whole set: its score and every cap beside mine, as a small table of their own above the items
	local sum = {}
	if showSet and perm then
		local mine, other = not s.foreign, B.perm ~= 1
		sum[1] = { "", mine and "|cffffd100You now|r" or "", other and ("|cffffd100" .. B.PERMS[B.perm] .. "|r") or "" }
		sum[2] = { "Score", mine and Fmt(s.curScore) or "", other and Fmt(perm.score) or "" }
		for _, word in ipairs(words) do
			local cap = s.prof.caps[word].cap
			local now, there = (s.base[word] or 0) + (s.curGear[word] or 0), (s.base[word] or 0) + (perm.gear[word] or 0)
			sum[#sum + 1] = { ("%s %scap %s|r"):format(LABEL[word] or word, GREY, Fmt(cap)), mine and Standing(now, cap) or "", other and Standing(there, cap) or "" }
		end
	end
	for k = 1, math.max(#sum, #gear.sum) do
		local l = gear.sum[k]
		if not l and sum[k] then
			l = { Text(f, "GameFontNormalSmall"), Text(f), Text(f) }
			gear.sum[k] = l
		end
		for c = 1, l and 3 or 0 do
			l[c]:ClearAllPoints()
			l[c]:SetPoint("TOPLEFT", x + ({ 4, 134, 334 })[c], -(top + 42 + (k - 1) * 14))
			l[c]:SetWidth(c == 1 and 126 or 196)
			l[c]:SetText(sum[k] and sum[k][c] or "")
		end
	end
	local hy = showSet and top + 42 + #sum * 14 + (#sum > 0 and 8 or 0) or top + 22 -- (the column titles, one line above the rows)
	local titles = { { P.n, "slot", P.nw }, { P.wt, "weight", P.wtw }, { P.diff, s.foreign and "" or "vs worn", P.diffw }, { P.pct, s.foreign and "" or "%", P.pctw },
		{ P.kind, "source", P.wherew }, { P.warn, "breakpoints", P.warnw }, { P.name, "item", P.namew } }
	for c, t in ipairs(titles) do
		gear.cols[c]:ClearAllPoints()
		if t[1] then
			gear.cols[c]:SetPoint("TOPLEFT", x + t[1], -hy)
			gear.cols[c]:SetWidth(t[3])
		end
		gear.cols[c]:SetText(t[1] and t[2] or "")
	end
	local ry = hy + 16
	-- what there is to show, as lines: { head = a note } or { c = an item row, label = the slot in a set }; then those that fit
	local rows = {}
	local function Add(head, c, label) rows[#rows + 1] = { head = head, c = c, label = label } end
	if showSet and perm then
		local swaps = B.perm > 1 and not s.foreign and B.Swaps(s, perm) or {}
		for r = 1, #ROWS do
			local id, cur = perm.rows[r], s.cur[r]
			if id then
				local c = { id = id, kind = s.have[id] and id ~= cur and "owned" or B.Kind(id), worn = id == cur, swap = swaps[r] }
				if swaps[r] then c.gain, c.pct = swaps[r].d, swaps[r].pct end
				Add(nil, c, ROWS[r][1])
			else
				Add(GREY .. ROWS[r][1] .. ": nothing|r")
			end
		end
	elseif not showSet then
		local extra = PAIR[picked] and 1 or 0
		local rank = ready and B.Rank(picked, 500, s.foreign and 0 or BELOW) or nil
		if rank then
			if extra == 1 and not s.foreign then
				Add(("%sTwo of them: compared with your weaker one%s|r"):format(GREY, rank.ref ~= picked and (" (" .. ROWS[rank.ref][1] .. ")") or ""))
			end
			for _, c in ipairs(rank.above) do Add(nil, c) end
			if not s.foreign then
				if rank.blocked then Add(GREY .. "You wield a two-hander: no off hand to compare.|r") end
				if #rank.above == 0 and not rank.blocked then Add("|cff40ff40Nothing found beats what you wear here.|r") end
				if rank.worn then Add(nil, rank.worn) else Add(GREY .. "nothing worn|r") end
				for _, c in ipairs(rank.below) do Add(nil, c) end
			elseif rank.none then
				Add(GREY .. "nothing for this slot|r")
			end
		end
	end
	-- (as many lines as the panel has room for; the mouse wheel and the bar move the rest)
	local fit = math.max(3, math.floor((h - ry - 4) / ROW))
	B.scroll = math.max(0, math.min(B.scroll, #rows - fit))
	gear.bar:SetShown(#rows > fit)
	gear.bar:SetMinMaxValues(0, math.max(0, #rows - fit))
	gear.bar:SetValue(B.scroll)
	for k = 1, math.max(fit, #gear.lines) do
		local l = gear.lines[k]
		if not l and k <= fit then l = Line(f) gear.lines[k] = l end
		if l then
			local row = k <= fit and rows[B.scroll + k] or nil
			local c, y = row and row.c, -ry - (k - 1) * ROW
			local function At(fs, at, width, text)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", at and x + at or x, y - 3)
				fs:SetWidth(width or 10)
				fs:SetText(text or "")
			end
			l.tint:ClearAllPoints()
			l.tint:SetPoint("TOPLEFT", x, y)
			l.tint:SetSize(rw, ROW)
			l.tint:SetShown(row ~= nil and k % 2 == 0 and not (c and c.worn))
			for _, t in ipairs({ l.band, l.rule1, l.rule2 }) do t:ClearAllPoints() end
			l.band:SetPoint("TOPLEFT", x, y)
			l.band:SetSize(rw, ROW)
			l.rule1:SetPoint("TOPLEFT", x, y)
			l.rule1:SetSize(rw, 1)
			l.rule2:SetPoint("TOPLEFT", x, y - ROW + 1)
			l.rule2:SetSize(rw, 1)
			local worn = c and c.worn and not showSet
			l.band:SetShown(worn and true or false)
			l.rule1:SetShown(worn and true or false)
			l.rule2:SetShown(worn and true or false)
			At(l.head, 4, rw - 8, row and row.head or "")
			local it = c and B.Item(c.id)
			At(l.n, P.n, P.nw or 10, c and row.label and GREY .. row.label .. "|r" or "")
			l.icon:ClearAllPoints()
			l.icon:SetPoint("TOPLEFT", x + P.icon, y - 2)
			l.icon:SetTexture(it and it.icon or nil)
			l.icon:SetShown(c and true or false)
			l.item:ClearAllPoints()
			l.item:SetPoint("TOPLEFT", x, y)
			l.item:SetSize(rw, ROW)
			l.item.text:ClearAllPoints()
			l.item.text:SetPoint("TOPLEFT", l.item, "TOPLEFT", P.name, -3)
			l.item.text:SetWidth(P.namew)
			l.item.id = c and c.id or nil
			l.item:SetShown(c and true or false)
			l.item.text:SetText(c and Name(c.id) or "")
			At(l.wt, P.wt, P.wtw, P.wt and c and c.worth and Fmt(c.worth) or "")
			-- (the difference is the real change to the set's score were it swapped in; the percent is of the worn item's weight)
			local g = c and c.gain
			local diff, pct = "", ""
			if g and not s.foreign and not c.worn then
				diff = Signed(g, "%+.1f")
				pct = c.pct and Signed(c.pct, "%+.1f%%") or c.new and GREY .. "new|r" or ""
			end
			At(l.diff, P.diff, P.diffw, diff)
			At(l.pct, P.pct, P.pctw, pct)
			local tag, where = "", ""
			if c then tag, where = B.SourceText(c.id, c.worn) end
			At(l.from, P.kind, P.wherew, c and ("|cff%s%s|r%s"):format(KIND[tag] or "c080ff", tag, where ~= "" and ("  " .. GREY .. where .. "|r") or "") or "")
			-- (a set: what this piece alone does to the set I wear, in amber where it breaks a cap; else its place in the order to buy in)
			local sw = c and c.swap
			local warn, tip = "", nil
			if sw then
				local deltas, lines = {}, { ("Just this piece in your set: %+.1f score%s"):format(sw.d, sw.pct and (" (%+.1f%%)"):format(sw.pct) or "") }
				for _, word in ipairs(sw.words) do
					local capw, c2 = s.prof.caps[word], sw.caps[word]
					local d = c2.after - c2.before
					if math.abs(d) > 0.05 then deltas[#deltas + 1] = ("%s %+.1f"):format(B.Short(word), d) end
					lines[#lines + 1] = ("%s %s: %s -> %s"):format(LABEL[word] or word, Fmt(capw.cap), Fmt(c2.before), Fmt(c2.after))
				end
				local names = {}
				for j, word in ipairs(sw.breaks) do
					names[j] = B.Short(word)
					local need = sw.needs and sw.needs[j]
					lines[#lines + 1] = ("|cffe8a030Takes you under the %s cap you meet now%s|r"):format(LABEL[word] or word,
						need and need.by and (": get the " .. ROWS[need.by][1]:lower() .. " first") or " and nothing else found makes it up")
				end
				if #sw.breaks > 0 then
					local need = sw.needs and sw.needs[1]
					warn = ("|cffe8a030! %s %s|r"):format(table.concat(names, ","), need and need.by and ("after " .. ROWS[need.by][1]:lower()) or "no fix found")
				else
					warn = ("%s#%d %s|r"):format(GREY, sw.order, table.concat(deltas, " ", 1, math.min(2, #deltas)))
				end
				tip = lines
			end
			At(l.warn, P.warn, P.warnw or 10, warn)
			l.item.quest, l.item.note, l.item.swap = c and c.kind == "quest" and B.quests[c.id] or nil, where, tip
		end
	end
end

---------------------------------------------------------------------------
-- Upgrades, Weights, Check
---------------------------------------------------------------------------

-- Upgrades: the list's items I do not own, the one that gains the most first
local up = { rows = {}, filter = "all" }
B.up = up
-- the filter: where an upgrade is from. "all", a kind ("quest", "crafted", "vendor", "boe", "dungeon": any dungeon
-- or raid), or "d:" .. a dungeon's name
local FILTERS = { { "all", "All sources" }, { "dungeon", "Any dungeon or raid" }, { "quest", "Quest" }, { "crafted", "Crafted" }, { "vendor", "Vendor" }, { "boe", "World Drop" } }
local function DungeonOf(id)
	local boss = DT.Dungeon and DT.Dungeon.DropOf and DT.Dungeon.DropOf(id)
	return boss and boss.dungeon and boss.dungeon.name
end
function B.Passes(id, filter)
	if filter == "all" then return true end
	if filter:sub(1, 2) == "d:" then return DungeonOf(id) == filter:sub(3) end
	local kind = B.Kind(id) or "boe"
	return kind == filter
end
local function Filtered(s)
	if up.filter == "all" then return s.upg end
	local out = {}
	for _, u in ipairs(s.upg) do
		if B.Passes(u.id, up.filter) then out[#out + 1] = u end
	end
	return out
end

-- the columns: { x, width (nil: to the right edge), justify, title, field of a row, font }
local BOSS_X = 210 -- (where the boss stands in the source column, past "Dungeon" and the dungeon's name)
local UPCOLS = { { 4, 24, "RIGHT", "#", "n" }, { 32, 16, "LEFT", "" }, { 50, 170, "LEFT", "item" }, { 224, 110, "LEFT", "slot", "slot", "GameFontDisableSmall" },
	{ 338, 44, "RIGHT", "weight", "wt" }, { 386, 48, "RIGHT", "vs worn", "diff" }, { 438, 50, "RIGHT", "%", "pct", "GameFontDisableSmall" },
	{ 494, 60, "RIGHT", "set gain", "gain" }, { 562, nil, "LEFT", "source", "from" } }
local function BuildUp(f)
	up.note = Text(f)
	up.note:SetPoint("TOPLEFT", 8, -4)
	up.note:SetPoint("TOPRIGHT", f, "TOPRIGHT", -404, -4)
	up.pick = DT:Dropdown(f, 170, { search = true, menuWidth = 240,
		entries = function()
			local out, n, s = {}, {}, state
			for _, u in ipairs(s and s.upg or {}) do
				local d = DungeonOf(u.id)
				if d then n[d] = (n[d] or 0) + 1 end
			end
			for _, e in ipairs(FILTERS) do out[#out + 1] = { value = e[1], text = e[2], always = true } end
			-- every dungeon and raid, the lowest first, with how many of the upgrades it drops
			-- ("Only with upgrades" ticked: those with none are left out, but for the one picked)
			local hide = B.db and B.db.settings.upHide
			for _, d in ipairs(DT.Dungeon and DT.Dungeon.All and DT.Dungeon.All() or {}) do
				if not (hide and not n[d.name] and up.filter ~= "d:" .. d.name) then out[#out + 1] = { value = "d:" .. d.name, text = d.name .. (d.lo and ("  |cff888888%d-%d|r"):format(d.lo, d.hi or d.lo) or (DT.Dungeon.IsRaid(d) and "  |cff888888raid|r" or "")), n = tostring(n[d.name] or 0), color = not n[d.name] and "|cff888888" or nil } end
			end
			return out
		end,
		picked = function() return up.filter end,
		pick = function(v) up.filter, offset = v, 0 B.Refresh() end })
	up.pick:SetPoint("TOPRIGHT", f, "TOPRIGHT", -128, -2)
	up.hide = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	up.hide:SetSize(22, 22)
	up.hide:SetPoint("TOPRIGHT", f, "TOPRIGHT", -100, -1)
	up.hide.label = Text(up.hide, "GameFontHighlightSmall")
	up.hide.label:SetPoint("LEFT", up.hide, "RIGHT", 0, 0)
	up.hide.label:SetText("Only with upgrades")
	up.hide:SetChecked(B.db and B.db.settings.upHide and true or false)
	up.hide:SetScript("OnClick", function(self) B.db.settings.upHide = self:GetChecked() and true or false end)
	-- (the sets and upgrades are kept from one session to the next: worked out anew, with the gear there is looked through again, on a click)
	up.redo = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	up.redo:SetSize(90, 20)
	up.redo:SetText("Recalculate")
	up.redo:SetPoint("TOPRIGHT", f, "TOPRIGHT", -306, -1)
	up.redo:SetScript("OnClick", function() B.Recalc() end)
	up.heads = {}
	for c in ipairs(UPCOLS) do up.heads[c] = Text(f, "GameFontNormalSmall", UPCOLS[c][3]) end
end

local function DrawUp(f, s)
	local list = Filtered(s)
	local fit = math.max(1, math.floor((f:GetHeight() - 42) / ROW_H))
	offset = math.max(0, math.min(offset, math.max(0, #list - fit)))
	local left = #s.queue
	local name = up.filter:sub(1, 2) == "d:" and up.filter:sub(3)
	for _, e in ipairs(FILTERS) do if e[1] == up.filter then name = e[2] end end
	up.pick.label:SetText(name or "All sources")
	local text = (s.foreign and "|cff888888Another class's spec: there is nothing of yours to upgrade.|r"
		or B.Left() > 0 and ("|cff888888Looking through the gear there is for this spec: %d more to go...|r"):format(B.Left())
		or left > 0 and ("|cff888888Working out %d more...|r"):format(left)
		or not s.all and "|cff888888No gear found for this spec yet. The tooltip line still says what an item would gain over the gear you own.|r"
		or #s.upg == 0 and "|cff40ff40Nothing found would improve your best set.|r"
		or up.filter ~= "all" and (#list == 0 and ("|cffff8040None of the %d upgrades is from %s.|r"):format(#s.upg, name)
			or ("%d of the %d upgrades from %s, the biggest gain first."):format(#list, #s.upg, name))
		or ("%d would improve your best set, the biggest gain first. |cff888888A gain is in score, and in percent of the best set %s.|r"):format(#s.upg, s.list and "of the pre-raid list" or "found"))
	if s.at and left == 0 and B.Left() == 0 and not s.foreign then
		text = text .. ("  |cff888888Worked out %s ago.|r"):format(Ago(s.at))
	end
	up.note:SetText(text)
	-- the column titles, as the Gear view has them
	for c, col in ipairs(UPCOLS) do
		up.heads[c]:ClearAllPoints()
		up.heads[c]:SetPoint("TOPLEFT", col[1], -24)
		if col[2] then up.heads[c]:SetWidth(col[2]) else up.heads[c]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -24) end
		up.heads[c]:SetText(s.foreign and "" or col[4])
	end
	for i = 1, math.max(fit, #up.rows) do
		local u = i <= fit and left == 0 and not s.foreign and list[offset + i]
		local row = up.rows[i]
		if u and not row then
			row = { icon = f:CreateTexture(nil, "ARTWORK"), item = ItemCell(f), tint = f:CreateTexture(nil, "BACKGROUND") }
			local y = -40 - (i - 1) * ROW_H
			row.tint:SetColorTexture(1, 1, 1, 0.04)
			row.tint:SetPoint("TOPLEFT", 2, y)
			row.tint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y)
			row.tint:SetHeight(ROW_H)
			row.icon:SetSize(16, 16)
			row.icon:SetPoint("TOPLEFT", 32, y - 1)
			row.item:SetPoint("TOPLEFT", 50, y)
			row.item:SetWidth(UPCOLS[3][2])
			for c, col in ipairs(UPCOLS) do
				if col[5] then
					local t = Text(f, col[6], col[3])
					t:SetPoint("TOPLEFT", col[1], y - 3)
					if col[2] then t:SetWidth(col[2]) else t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y - 3) end
					row[col[5]] = t
				end
			end
			-- (a dungeon's drop: the boss and its chance, lined up past the dungeon's name)
			row.y, row.boss = y, Text(f, "GameFontHighlightSmall", "LEFT")
			row.boss:SetPoint("TOPLEFT", UPCOLS[#UPCOLS][1] + BOSS_X, y - 3)
			row.boss:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y - 3)
			up.rows[i] = row
		end
		if row then
			local it = u and B.Item(u.id)
			row.item.id = u and u.id or nil
			row.tint:SetShown(u and i % 2 == 0 or false)
			row.n:SetText(u and ("|cffffd100%d|r"):format(s.rank[u.id] or offset + i) or "") -- (its place among all, filtered or not)
			row.icon:SetTexture(it and it.icon or nil)
			row.icon:SetShown(u and true or false)
			row.item.text:SetText(u and Name(u.id) or "")
			row.item:SetShown(u and true or false)
			-- weight: what it adds in place of the worn piece it would replace (the weaker of two rings or trinkets);
			-- vs worn and %: against that piece's own weight; set gain: what the best set gains with it, all slots moved
			local wt, diff, pct, slot = "", "", "", ""
			if u and it then
				local worth, d, p, out = B.VsWorn(s, u.id)
				if worth then
					wt, diff = Fmt(worth), Signed(d, "%+.1f")
					-- (no percent of nothing: "new" for a slot I wear nothing in, a dash where what I wear there counts for nothing)
					pct = p and Signed(p, "%+.1f%%") or out and GREY .. "-|r" or GREY .. "new|r"
				end
				local reach = {}
				for _, word in ipairs(u.g.reach or {}) do reach[#reach + 1] = B.Short(word) end
				slot = table.concat(u.g.slots or {}, ", ") .. (#reach > 0 and ("  |cff40ff40reaches " .. table.concat(reach, ", ") .. "|r") or "")
			end
			row.wt:SetText(wt)
			row.diff:SetText(diff)
			row.pct:SetText(pct)
			row.gain:SetText(u and Signed(u.g.d, "%+.1f") .. (u.g.level and (" |cffff8040L%d|r"):format(u.g.level) or "") or "")
			row.slot:SetText(slot)
			local tag, where = "", ""
			if u then tag, where = B.SourceText(u.id) end
			local Dg = DT.Dungeon
			local boss = u and B.Kind(u.id) == "dungeon" and Dg and Dg.DropOf and Dg.DropOf(u.id)
			local chance = boss and Dg.Chance and Dg.Chance(boss, u.id)
			if boss and boss.dungeon then where = boss.dungeon.name end
			row.from:ClearAllPoints()
			row.from:SetPoint("TOPLEFT", UPCOLS[#UPCOLS][1], row.y - 3)
			if boss then row.from:SetWidth(BOSS_X - 6) else row.from:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, row.y - 3) end
			row.from:SetText(u and ("|cff%s%s|r%s"):format(KIND[tag] or "c080ff", tag, where ~= "" and ("  " .. GREY .. where .. "|r") or "") or "")
			row.boss:SetText(boss and (boss.name .. (chance and (" |cff888888(%s%%)|r"):format(chance % 1 == 0 and ("%d"):format(chance) or ("%.1f"):format(chance)) or "")) or "")
			row.item.quest, row.item.note = u and B.Kind(u.id) == "quest" and B.quests[u.id] or nil, u and where or nil
		end
	end
end

-- Weights: what a point of each stat is worth, its cap, and what it is worth past the cap; all to be changed
local weights = { rows = {} }
B.weights = weights
local function Box(parent, onSet)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(46, 16)
	e:SetAutoFocus(false)
	local function Take(self)
		local text = self:GetText() or ""
		local n = tonumber(text)
		if n or text == "" then onSet(n) end
		self:ClearFocus()
	end
	e:SetScript("OnEnterPressed", Take)
	e:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		B.redraw = true
	end)
	return e
end

local function BuildWeights(f)
	weights.note = Text(f)
	weights.note:SetPoint("TOPLEFT", 8, -4)
	weights.note:SetPoint("TOPRIGHT", f, "TOPRIGHT", -150, -4)
	weights.note:SetSpacing(1)
	weights.reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	weights.reset:SetSize(130, 20)
	weights.reset:SetPoint("TOPRIGHT", -8, -4)
	weights.reset:SetText("Reset to default")
	weights.reset:SetScript("OnClick", B.ResetEdits)
	local half = math.ceil(#ORDER / 2)
	for col = 0, 1 do
		for c, title in ipairs({ "Stat", "Worth", "Cap", "Past cap", "Buffs" }) do
			local head = Text(f, "GameFontNormalSmall")
			head:SetPoint("TOPLEFT", 8 + col * 370 + ({ 0, 140, 190, 240, 290 })[c], -58)
			head:SetText(title)
		end
	end
	for i, word in ipairs(ORDER) do
		local col, line = i > half and 1 or 0, (i - 1) % half
		local x, y = 8 + col * 370, -74 - line * 17
		local row = { label = Text(f) }
		row.label:SetPoint("TOPLEFT", x, y - 2)
		row.label:SetText(LABEL[word])
		row.w = Box(f, function(n) B.Edit(word, "w", n) end)
		row.w:SetPoint("TOPLEFT", x + 140, y)
		row.cap = Box(f, function(n) B.Edit(word, "cap", n) end)
		row.cap:SetPoint("TOPLEFT", x + 190, y)
		row.over = Box(f, function(n) B.Edit(word, "over", n) end)
		row.over:SetPoint("TOPLEFT", x + 240, y)
		row.buff = Box(f, function(n) B.Edit(word, "buff", n) end)
		row.buff:SetPoint("TOPLEFT", x + 290, y)
		row.hard = Text(f)
		row.hard:SetPoint("TOPLEFT", x + 340, y - 2)
		weights.rows[word] = row
	end
end

local function DrawWeights(_, s)
	local raw = s.prof.raw
	local edit = B.db.edit[raw.id]
	local edited = edit and (next(edit.w or {}) or next(edit.caps or {})) and "  |cffff8040(changed by you)|r" or ""
	-- (four lines, none wrapped: the rows begin right under them)
	weights.note:SetText(("|cffffd100%s %s|r%s  |cff888888client %s|r\n|cff888888Per 1%%: hit, crit, haste, expertise, dodge, parry, block; the rest per point. A cap is the sheet's total. Buffs: what consumables and buffs give at level 60. Enter takes a change, an empty box the default.|r\n|cff888888%s|r\n|cff888888%s|r")
		:format(ClassName(raw.class), raw.title, edited, DT.BisBuild or "?", table.concat(raw.src or {}, "   "), raw.note or ""))
	for word, row in pairs(weights.rows) do
		local cap = s.prof.caps[word]
		if not row.w:HasFocus() then row.w:SetText(s.prof.w[word] and Fmt(s.prof.w[word]) or "") end
		if not row.cap:HasFocus() then row.cap:SetText(cap and Fmt(cap.cap) or "") end
		if not row.over:HasFocus() then row.over:SetText(cap and Fmt(cap.over or 0) or "") end
		if not row.buff:HasFocus() then row.buff:SetText(cap and cap.buff and Fmt(cap.buff) or "") end
		row.hard:SetText(cap and cap.hard and "|cffff8040first|r" or "")
	end
end

-- Check: what was read of each item I wear, the sheet, and what is left without gear; to hold against the game
local check = {}
B.check = check
local function BuildCheck(f)
	check.text = Text(f)
	check.text:SetPoint("TOPLEFT", 8, -4)
	check.text:SetWidth(740)
	check.text:SetWordWrap(true)
	check.text:SetSpacing(2)
end

function B.CheckText(s)
	if s.foreign then return "|cff888888Another class's spec is picked. Pick one of your own class to see what was read of the gear you wear.|r" end
	local lines = { "|cffffd100What was read of the gear you wear|r  |cff888888Hold each line against the item's tooltip: a stat missing or wrong here is one the reading got wrong. Enchants are not an item's own.|r" }
	for r, row in ipairs(ROWS) do
		local id = s.cur[r]
		local it = id and B.Item(id)
		if id then lines[#lines + 1] = ("|cffaaaaaa%s|r  %s  %s"):format(row[1], Name(id), it and B.StatText(it.s) or "|cff888888not loaded yet|r") end
	end
	local sheet = Fight() and {} or B.Sheet()
	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cffffd100Gear in all|r  " .. B.StatText(s.curGear)
	lines[#lines + 1] = "|cffffd100Character sheet|r  " .. (next(sheet) and B.StatText(sheet) or "|cff888888not readable now|r")
	local missing = {}
	for _, word in ipairs(BASED) do
		if not sheet[word] then missing[#missing + 1] = LABEL[word] end
	end
	if next(sheet) and #missing > 0 then lines[#lines + 1] = "|cffff8040The game did not answer for: " .. table.concat(missing, ", ") .. " (counted as none without gear).|r" end
	local def = s.base.def or 0
	lines[#lines + 1] = ("|cffffd100Without gear|r  %s  |cff888888Defense: level %d gives %d, so %s comes from talents, racials and enchants.|r"):format(B.StatText(s.base), s.who.level, s.who.level * 5, Fmt(def - s.who.level * 5))
	lines[#lines + 1] = "|cff888888Sheet less gear = without gear, for the capped stats. It should not move when you change an item: if it does, that item was read wrong.|r"
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- The bar on top, and the whole
---------------------------------------------------------------------------

local BUILD = { gear = BuildGear, up = BuildUp, weights = BuildWeights, check = BuildCheck }
local DRAW = { gear = DrawGear, up = DrawUp, weights = DrawWeights, check = function(f, s)
	check.text:SetWidth(f:GetWidth() - 16)
	check.text:SetText(B.CheckText(s))
end }

-- a spec of the class picked: its picture and its name
local function SpecButton(i)
	local b = CreateFrame("Button", nil, panel)
	b:SetHeight(22)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(1, 0.82, 0, 0.18)
	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(18, 18)
	b.icon:SetPoint("LEFT", 2, 0)
	b.label = Text(b)
	b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
	b:SetScript("OnClick", function(self)
		B.Pick(self.spec.id)
		B.Refresh()
	end)
	b:SetScript("OnEnter", function(self)
		local raw = self.spec
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine(ClassName(raw.class) .. ": " .. raw.title)
		if raw.note then GameTooltip:AddLine(raw.note, 0.7, 0.7, 0.7, true) end
		for _, url in ipairs(raw.src or {}) do GameTooltip:AddLine(url, 0.5, 0.7, 1) end
		GameTooltip:AddLine(DT.BisLists and DT.BisLists[raw.id] and "Has a pre-raid list." or "No pre-raid list yet: weights and caps only.", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	specButtons[i] = b
	return b
end

local function Refresh()
	if not panel then return end
	B.redraw = false
	local s = B.State()
	local raw = B.Raw()
	for class, b in pairs(classButtons) do b.sel:SetShown(raw ~= nil and raw.class == class) end
	-- the level and phase, on the right of the second row; the specs on the left, as wide as they are, or as pictures
	-- alone (their names on hover) where the names would run into them
	local lvl, phase = B.ViewLevel(), B.Phase()
	local shift = phase and 0 or -120
	local C = B.level
	local shown = B.pendingLevel or lvl
	if not C.box:HasFocus() then C.box:SetText(tostring(shown)) end
	for _, e in ipairs(C.at) do
		e[1]:ClearAllPoints()
		e[1]:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -e[2] - shift - 0, e[1] == C.box and -33 or e[1] == C.label and -36 or -32)
	end
	C.mine:SetShown(shown ~= Level())
	C.mine.label:SetText(("My level (%d)"):format(Level()))
	C.phase:ClearAllPoints()
	C.phase:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -34)
	C.phase:SetShown(phase ~= nil)
	C.phase.label:SetText(phase and (#phase[3] == 0 and "Pre-raid" or #phase[3] == 1 and phase[3][1] or (#phase[3] .. " raids")) or "")
	local mine = B.Mine()
	local total = 0
	for i, spec in ipairs(mine) do
		local b = specButtons[i] or SpecButton(i)
		b.label:SetText(spec.title)
		total = total + 28 + b.label:GetStringWidth() + 6 + 4
	end
	local pictures = total + 6 > (panel:GetWidth() or 960) - 340 -- (what gives way: the names, not the controls)
	local x = 6
	for i = 1, math.max(#mine, #specButtons) do
		local spec = mine[i]
		local b = specButtons[i]
		if b then
			b:SetShown(spec ~= nil)
			if spec then
				b.spec = spec
				b.icon:SetTexture(spec.icon and ("Interface\\Icons\\" .. spec.icon) or EMPTY_ART)
				b.label:SetShown(not pictures)
				b.sel:SetShown(spec == raw)
				local w = pictures and 24 or 28 + b.label:GetStringWidth() + 6
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", x, -32)
				b:SetWidth(w)
				x = x + w + 4
			end
		end
	end
	for _, v in ipairs(VIEWS) do
		viewButtons[v[1]].sel:SetShown(view == v[1])
		viewButtons[v[1]].label:SetText(v[2])
		frames[v[1]]:SetShown(view == v[1] and s ~= nil)
	end
	status:SetText(not s and "|cff888888Worked out once the fight is over.|r"
		or dirty and "|cff888888As it was before the fight.|r"
		or s.pending > 0 and ("|cff888888%d item%s not loaded yet...|r"):format(s.pending, s.pending == 1 and "" or "s")
		or s.foreign and "|cff888888Not your class: its pre-raid set and weights.|r" or "")
	if s then DRAW[view](frames[view], s) end
end
B.Refresh = Refresh

function B.Show(which)
	view, offset, B.scroll = which, 0, 0
	Refresh()
end

-- a small flat button, as the pick-lists and tabs of the other windows look
local function Small(parent, text, w)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, 20)
	local shade = b:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, 0.08)
	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.12)
	b.label = Text(b, "GameFontHighlightSmall", "CENTER")
	b.label:SetAllPoints()
	b.label:SetText(text)
	return b
end

local function Build(parent)
	panel = parent
	B.panel = panel
	-- (the header band: classes and views above; below, the specs on the left and the level and phase on the right)
	local band = panel:CreateTexture(nil, "BACKGROUND")
	band:SetPoint("TOPLEFT", 0, 0)
	band:SetPoint("TOPRIGHT", 0, 0)
	band:SetHeight(TOP_H - 2)
	band:SetColorTexture(1, 1, 1, 0.04)
	-- the classes
	for i, class in ipairs(CLASS_ORDER) do
		local b = CreateFrame("Button", nil, panel)
		b:SetSize(26, 26)
		b:SetPoint("TOPLEFT", 6 + (i - 1) * 28, -3)
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetAllPoints()
		b.sel:SetColorTexture(ClassColor(class))
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(22, 22)
		b.icon:SetPoint("CENTER", 0, 0)
		b.icon:SetTexture(CLASS_ART)
		local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
		if coords then b.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
		local highlight = b:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.15)
		b:SetScript("OnClick", function()
			B.PickClass(class)
			Refresh()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
			GameTooltip:AddLine(ClassName(class), ClassColor(class))
			if class == B.MyClass() then GameTooltip:AddLine("Your class.", 1, 1, 1) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		classButtons[class] = b
	end
	local viewX = 6 + #CLASS_ORDER * 28 + 14
	for i, v in ipairs(VIEWS) do
		local b = CreateFrame("Button", nil, panel)
		b:SetSize(72, 22)
		b:SetPoint("TOPLEFT", viewX + (i - 1) * 76, -5)
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetAllPoints()
		b.sel:SetColorTexture(1, 0.82, 0, 0.18)
		local highlight = b:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)
		b.label = Text(b, "GameFontHighlightSmall", "CENTER")
		b.label:SetAllPoints()
		b:SetScript("OnClick", function() B.Show(v[1]) end)
		viewButtons[v[1]] = b
		local f = CreateFrame("Frame", nil, panel)
		f:SetPoint("TOPLEFT", 0, -TOP_H)
		f:SetPoint("BOTTOMRIGHT", 0, 0)
		frames[v[1]] = f
		BUILD[v[1]](f)
	end
	B.viewButtons = viewButtons
	status = Text(panel)
	status:SetPoint("TOPLEFT", viewX + #VIEWS * 76 + 8, -10)
	status:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -10)
	B.status = status
	-- the level looked at: - 40 + (the box can be typed in; a click or a hold changes it, and the list is made anew once it has
	-- settled), a way back to mine when it is not mine, and at the last level the phase as a pick-list
	local level = {}
	B.level = level
	local seq, held, fired = 0, nil, false
	local function Settle(n)
		seq, B.pendingLevel = seq + 1, nil
		B.SetLevel(n)
		Refresh()
	end
	local function Step(d)
		local to = math.max(1, math.min(B.MAX_LEVEL, (B.pendingLevel or B.ViewLevel()) + d))
		B.pendingLevel, seq = to, seq + 1
		level.box:SetText(tostring(to))
		level.mine:SetShown(to ~= Level())
		local mine = seq
		if C_Timer and C_Timer.After then
			C_Timer.After(0.35, function() if seq == mine and B.pendingLevel then Settle(B.pendingLevel) end end)
		else
			Settle(to)
		end
	end
	local function Arrow(text, d)
		local b = Small(panel, text, 20)
		b:SetScript("OnMouseDown", function() held, fired = { d = d, at = GetTime() + 0.4 }, false end)
		b:SetScript("OnMouseUp", function() held = nil end)
		b:SetScript("OnClick", function()
			if fired then fired = false return end
			Step(d)
		end)
		return b
	end
	level.minus, level.plus = Arrow("-", -1), Arrow("+", 1)
	level.box = Box(panel, function(n) Settle(n) end)
	level.box:SetSize(30, 18)
	level.label = Text(panel, "GameFontNormalSmall", "RIGHT")
	level.label:SetText("Level")
	level.label:SetWidth(34)
	level.mine = Small(panel, "", 86)
	level.mine:SetScript("OnClick", function() Settle(nil) end)
	level.phase = DT:Dropdown(panel, 112, { menuWidth = 230,
		entries = function()
			-- pre-raid, then each raid with a tick: a click ticks or unticks it
			local on = type(B.db.phase[B.me]) == "table" and B.db.phase[B.me] or {}
			local out = { { value = "pre", text = "Pre-raid only (no raids)" } }
			for i, name in ipairs(B.RAIDS) do
				out[#out + 1] = { value = name, text = (on[name] and "|cff40ff40[x]|r " or "|cff888888[  ]|r ") .. name
					.. (i > B.FOREVER_RAIDS and "  |cff888888old world|r" or "") }
			end
			out[#out + 1] = { value = "realistic", text = (Realistic() and "|cff40ff40[x]|r " or "|cff888888[  ]|r ") .. "Realistic: no gear behind a standing I lack" }
			return out
		end,
		picked = function() local p = B.Phase() return p and p[1] == "pre" and "pre" or nil end,
		pick = function(id)
			if id == "realistic" then B.SetRealistic(not Realistic()) else B.SetPhase(id) end
			Refresh()
		end })
	-- from the right edge: (phase) + box - label, the way back left of them; they slide right where there is no phase
	level.at = { { level.plus, 128, 20 }, { level.box, 152, 30 }, { level.minus, 186, 20 }, { level.label, 210, 34 }, { level.mine, 250, 86 } }
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		if view == "up" then
			offset = offset - delta * 3
		elseif view == "gear" then
			B.scroll = B.scroll - delta * 3
		else
			return
		end
		Refresh()
	end)
	panel:SetScript("OnSizeChanged", Refresh)
	local nextUpdate, nextSift = 0, 0
	panel:SetScript("OnUpdate", function()
		-- (the gear there is to get: looked at a batch at a time, while the tab is up)
		if held and GetTime() >= held.at then -- (a button of the level held down: it goes on)
			held.at, fired = GetTime() + 0.07, true
			Step(held.d)
		end
		if state and GetTime() >= nextSift then
			nextSift = GetTime() + 0.2
			Sift()
		end
		if not (dirty or B.redraw) or GetTime() < nextUpdate or Fight() then return end
		nextUpdate = GetTime() + 0.5
		Refresh()
	end)
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

-- (no profiles on this machine: no tab, no tooltip line, nothing. An addon loaded after this one may bring them:
-- all are loaded before login, when the modules are switched on)
local registered = false
local function Register()
	if registered or not Profiles() then return end
	registered = true
DT:RegisterModule("bis", {
	title = "BiS",
	version = 1,
	slash = "/dtbis",
	defaults = { tooltip = true, roll = true, realistic = true },
	settings = {
		{ key = "tooltip", label = "BiS: what an item would gain over my best set (DT: BiS)", tooltip = true },
		{ key = "roll", label = "When an item is rolled for: the same, as a line in the chat" },
		{ key = "realistic", label = "BiS realistic: leave out gear that needs a reputation standing I do not have yet" },
	},
	tab = { id = "bis", title = "BiS", defaultOrder = 61, group = 2, create = Build, onShow = Refresh },
	onEnable = function(mod)
		B.db, B.me = mod.db, UnitGUID("player")
		if B.db.factsV ~= FACTS then B.db.facts, B.db.factsV = {}, FACTS end
		for _, key in ipairs({ "pick", "edit", "base", "last", "facts", "level", "phase", "kept", "seen", "saved" }) do
			if type(B.db[key]) ~= "table" then B.db[key] = {} end
		end
		B.db.kept.keys, B.db.kept.order = type(B.db.kept.keys) == "table" and B.db.kept.keys or {}, type(B.db.kept.order) == "table" and B.db.kept.order or {}
		for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_CLOSED", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "PLAYER_REGEN_ENABLED" }) do
			DT:On(event, Stale)
		end
		DT:On("PLAYER_LEVEL_UP", function() resolved = nil end) -- (the caps go with the level)
			-- (the talents: the spec I am, unless one was picked; they may not be there yet when the tab is first looked at)
			for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do
				DT:On(event, function()
					-- (a respec to another tree: the spec picked by hand for my class goes, the new one shows)
					local now, mine = B.Default(), (B.MyClass() or ""):lower() .. "-"
					if now and B.db.seen[B.me] and B.db.seen[B.me] ~= now and (B.db.pick[B.me] or ""):sub(1, #mine) == mine then B.db.pick[B.me] = nil end
					if now then B.db.seen[B.me] = now end
					resolved = nil
					Stale()
				end)
			end
			DT:On("CHARACTER_POINTS_CHANGED", function() resolved = nil end)
		DT:On("GET_ITEM_INFO_RECEIVED", function(id)
			if not asked[id] or items[id] ~= nil then return end
			if not state or state.have[id] or (state.list and state.list[id]) then Stale() else B.redraw = true end
		end)
		DT:On("START_LOOT_ROLL", function(rollID) B.OnRoll(rollID) end)
		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, B.OnTooltip)
		elseif GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetItem") then
			GameTooltip:HookScript("OnTooltipSetItem", B.OnTooltip)
			ItemRefTooltip:HookScript("OnTooltipSetItem", B.OnTooltip)
		end
	end,
	selfTest = function(_, Try)
		Try("bis", function() B.Compute() end)
	end,
})
end
Register()
DT:On("ADDON_LOADED", Register)
