-- DawnTools :: BiS
-- The best gear for a spec: of what I own, and of a list of pre-raid gear. Local only: nothing is sent.
--   What an item gives is read from the game (GetItemStats and its tooltip's lines) once ever, in the background, and kept.
--   What I am without gear = the character sheet less what the gear I wear gives: talents and racials are in
--     it without being known one by one. Enchants are in it too (an item's stats are those of the bare item).
--   A profile says what a point of each stat is worth and where its caps are; its weights and caps can be
--     changed on the Weights view (kept per profile), and reset there to the defaults (Data/BisProfiles.lua).
--     They are not passed to the guild.
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
local FACTS = 5 --(the shape of what is kept in db.facts: raise it when BL.Stats counts something else, and every item is learned anew)
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
-- the facts kept by an older version: from 3, only what 4 reads otherwise is learned anew (dodge, parry and block
-- rating, counted one for one before; a weapon's damage per second, not read before); from any other, all of them
local WEAPON = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
function B.Upgrade(db)
	if db.factsV == FACTS then
	elseif (db.factsV == 3 or db.factsV == 4) and type(db.facts) == "table" then
		for id, it in pairs(db.facts) do
			if db.factsV == 3 and it and (WEAPON[it.loc or ""] or it.s and (it.s.dodge or it.s.parry or it.s.block)) then db.facts[id] = nil
			-- (from 4: hit and crit count for spells too, as BL.Stats reads them now; nothing is asked of the game again)
			elseif it and it.s then it.s.shit, it.s.scrit = it.s.shit or it.s.hit, it.s.scrit or it.s.crit end
		end
	else
		db.facts = {}
	end
	db.factsV = FACTS
	-- (armor kept by 0.56.0 and before: where the game gave no number, its tooltip is read now. An armor piece without
	-- any is learned anew, once)
	if not db.armorRead and type(db.facts) == "table" then
		for id, it in pairs(db.facts) do
			if B.NoArmor(it) then db.facts[id] = nil end
		end
	end
	db.armorRead = true
end
-- cloth, leather, mail, plate or a shield with no armor read: wrongly read (a row so is not taken either)
function B.NoArmor(it)
	local sub = it and it.class == 4 and it.s and not it.s.armor and it.sub
	return sub and (sub >= 1 and sub <= 4 or sub == 6) or false
end
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

-- An item's facts, from the game's answers: { id, loc, name, icon, q, lvl, class, sub, s, only, races, unique, boe, rep, repAt }
local function FactsOf(id, name, quality, minLevel, loc, icon, class, sub, lines)
	local get = (C_Item and C_Item.GetItemStats) or GetItemStats
	local ok, stats = pcall(function() return get and get("item:" .. id) end)
	local it = { id = id, loc = loc, name = name, icon = icon, q = quality or 1, lvl = minLevel or 0, class = class, sub = sub,
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
	return it
end

-- Shared with the guild through the game database (Core/DB.lua): "istat:<item>" = what the game said of it, as one
-- text; it passes with the rest of the store where sharing was agreed to. A member whose game says otherwise (a
-- patch) writes a newer row, and the newer row stands everywhere. FACTS is its first value: a row read another way
-- is left alone, and asked of the game anew.
-- ponytail: names and the "Classes:" / "Races:" lines are in the game's language; a guild of one language is assumed.
local DBL = DT.DBLogic
local function RowText(it)
	if not it then return DBL.Pack({ FACTS, false }, 2) end
	local words = {}
	for word in pairs(it.s) do words[#words + 1] = word end
	table.sort(words)
	for i, word in ipairs(words) do words[i] = word .. "=" .. DBL.Pack({ it.s[word] }, 1) end
	return DBL.Pack({ FACTS, it.loc, it.name, it.q, it.lvl, it.class, it.sub, table.concat(words, ";"), it.only, it.races,
		it.rep, it.repAt, it.unique or false, it.boe or false, it.icon }, 15)
end
B.RowText = RowText
local function FromRow(id, text)
	local v = DBL.Unpack(text or "")
	if not v or (v[1] ~= FACTS and v[1] ~= 4) then return nil end -- (4: read as 5 but for the spells' hit and crit, filled below)
	if v[2] == false then return false end
	if type(v[2]) ~= "string" or not WEARABLE[v[2]] or type(v[3]) ~= "string" then return nil end
	local s = {}
	for word, n in (type(v[8]) == "string" and v[8] or ""):gmatch("([%w_]+)=([%-%d%.]+)") do
		s[word] = tonumber(n)
		if s[word] and math.abs(s[word]) > 20000 then return nil end -- (no item gives that: a row gone wrong, or meant to mislead)
	end
	s.shit, s.scrit = s.shit or s.hit, s.scrit or s.crit
	local function Text(x) return type(x) == "string" and x ~= "" and x:gsub("[|%c]", "") or nil end
	if B.NoArmor({ class = tonumber(v[6]), sub = tonumber(v[7]), s = s }) then return nil end
	return { id = id, loc = v[2], name = Text(v[3]) or ("item " .. id), q = tonumber(v[4]) or 1, lvl = tonumber(v[5]) or 0,
		class = tonumber(v[6]), sub = tonumber(v[7]), s = s, only = Text(v[9]), races = Text(v[10]), rep = Text(v[11]),
		repAt = Text(v[12]), unique = v[13] == true or nil, boe = v[14] == true or nil, icon = tonumber(v[15]) or type(v[15]) == "string" and v[15] or nil, shared = true }
end
-- a guildmate's row for the item, taken for this session (nil: none, or not of this shape)
local function Shared(id)
	local row = DT.DB and DT.DB.Row and DT.DB.Row("istat:" .. id)
	local it = row and FromRow(id, row.v)
	if it ~= nil then items[id] = it end
	return it
end
B.Shared = Shared
-- what my game said, into the store where sharing was agreed to (written only where it says something new)
-- (gathered, and written a moment on, all at once: a chunk of the store is written once for many rows)
local toShare
local function Flush()
	local rows = toShare
	toShare = nil
	if rows and DT.DB and DT.DB.PutMany then DT.Timed("BiS: stats shared", DT.DB.PutMany, rows) end
end
local function Share(id, it)
	if not (DT.Shares and DT:Shares()) then return end
	if not toShare then
		toShare = {}
		if C_Timer and C_Timer.After then C_Timer.After(0.5, Flush) end
	end
	toShare["istat:" .. id] = RowText(it)
	if not (C_Timer and C_Timer.After) then Flush() end
end

-- An item's facts; false for what is not worn; nil while the game has not loaded it (asked again every few seconds, six times).
-- Where from, in this order: this session's, the saved file's (my game's own answers, kept), a guildmate's row,
-- and last the game, asked.
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
	if kept ~= nil then items[id] = kept return kept end -- (learned in an earlier session: not asked again)
	if not p then
		local shared = Shared(id)
		if shared ~= nil then return shared end
	end
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, _, quality, _, minLevel, _, _, _, loc, icon, _, class, sub = info(id)
	if name and not WEARABLE[loc or ""] then
		items[id] = false
		if B.db and B.db.facts then B.db.facts[id] = false end
		Share(id, false)
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
	it = FactsOf(id, name, quality, minLevel, loc, icon, class, sub, lines)
	-- (kept only with its tooltip: without, the stats its text gives are missing, and the next look may find them)
	if lines then
		items[id] = it
		if B.db and B.db.facts then B.db.facts[id] = it end
		Share(id, it)
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

-- the game will not tell of this item: asked for as often as we do, the last time a while ago; or so in the
-- last week, in this build of the game (db.never: not asked again every session)
local WEEK = 7 * 24 * 3600
function B.Never(id)
	local never, at = B.db and B.db.never, nil
	at = never and never[id]
	return at and time and time() - at < WEEK or false
end
function B.Gone(id)
	return B.Never(id) or (asked[id] or 0) >= ASKS and Now() - (askedAt[id] or 0) >= GAP
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
-- my side, "A" or "H"; and the other side's own reputations (its cities and battlegrounds), by the game's names
local function MySide() return UnitFactionGroup and UnitFactionGroup("player") == "Alliance" and "A" or "H" end
local THEIR_REPS = { A = { 76, 68, 81, 530, 729, 889, 510 }, H = { 72, 47, 69, 54, 730, 890, 509 } }
local theirReps
local function TheirRep(name)
	if not theirReps then
		theirReps = {}
		for _, id in ipairs(THEIR_REPS[MySide()]) do
			local ok, n = pcall(GetFactionInfoByID, id)
			if ok and type(n) == "string" then theirReps[n] = true end
		end
	end
	return theirReps[name] or false
end
B.TheirRep = TheirRep

-- Gear only the other faction can get: no drop and not made, and every quest that gives it and every vendor that
-- sells it are theirs. (A boss's drop is everyone's: it never comes here.)
local function Q(kind, id, field) local ok, v = pcall(DT.DB.Q, kind, id, field) return ok and v or nil end
-- a quest's side, "A", "H" or "": by its races, or where it names none (as most do) by whoever gives it, when they all agree
function B.QuestSide(quest)
	local side = DT.Quest and DT.Quest.SideOf and DT.Quest.SideOf(Q("quest", quest, "requiredRaces")) or ""
	if side ~= "" then return side end
	local by = Q("quest", quest, "startedBy")
	for _, npc in ipairs(type(by) == "table" and type(by[1]) == "table" and by[1] or {}) do
		local to = Q("npc", npc, "friendlyToFaction") or ""
		if to ~= "A" and to ~= "H" or side ~= "" and to ~= side then return "" end
		side = to
	end
	return side
end

function B.OtherSide(e)
	if e.src.Drop or e.src.Crafted or (DT.CraftSkill and DT.CraftSkill[e.id]) then return false end
	local mine, theirs = MySide(), false
	if e.src["Quest reward"] then
		for _, f in ipairs(DT.DB.RelTo("rewards", "item", e.id)) do
			local side = B.QuestSide(f.id)
			if side ~= "A" and side ~= "H" or side == mine then return false end
			theirs = true
		end
	end
	if e.src.Vendor then
		for _, f in ipairs(DT.DB.RelTo("sells", "item", e.id)) do
			local to = Q("npc", f.id, "friendlyToFaction")
			if to ~= "A" and to ~= "H" or to == mine then return false end
			theirs = true
		end
	end
	return theirs
end

-- the lightest armor a tank of the class wears (armor subclass: 2 leather, 3 mail, 4 plate): plate from level 40
local TANK_ARMOR = { WARRIOR = 4, PALADIN = 4, DRUID = 2 }
local function Usable(it, who, later)
	-- (a tank wears the heaviest armor its class has, cloaks aside: a protection warrior's leather is lost armor)
	if it.class == 4 and (it.sub or 0) >= 1 and it.sub <= 4 and it.loc ~= "INVTYPE_CLOAK" and B.db then
		local p = B.Profile()
		local min = p and p.raw.role == "tank" and TANK_ARMOR[p.raw.class] or 0
		if min == 4 and who.level < 40 then min = 3 end
		if it.sub < min then return false end
	end
	if it.rep and TheirRep(it.rep) then return false end -- (the other faction's reputation: never mine to have)
	if (it.q or 0) >= 5 then return false end -- (a legendary, Atiesh: nobody's pre-raid, nobody's plan)
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

-- The gear there is (Catalog, the loader and Pool, below): every wearable item, asked of the game once ever.
local catalog -- (built once the item list is read: see Catalog)
local Pool, Quick, Upgrades -- (below, with the slots they need)
local POOL = 6 -- (of the pool, the best this many for each place to wear go into the recommended set: it must stay quick to work out)
local function Clock() return GetServerTime and GetServerTime() or time and time() or 0 end
-- "5 min", "3 h", "2 days": how long ago a time of Clock was
local function Ago(t)
	local ago = math.max(0, Clock() - t)
	return ago < 3600 and (math.floor(ago / 60) .. " min") or ago < 172800 and (math.floor(ago / 3600) .. " h") or (math.floor(ago / 86400) .. " days")
end
-- how the item facts are read and what the item list is made of: a change of either, every set worked out anew
local function Stamp()
	-- (the addon's version: a set worked out by an older one is not shown for the new one's; and how many items a patch changed)
	local DB, out = DT.DB, { FACTS, "p1", tostring(DT.VERSION), B.refresh and B.refresh.changed or 0 }
	for _, source in ipairs({ "questie", "oneforall", "skillup" }) do out[#out + 1] = tostring(DB and DB.Base and DB.Base(source)) end
	return table.concat(out, "|")
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
	B.db.level[B.me], B.scroll = n ~= Level() and n or nil, 0
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
	B.db.settings.realistic, B.scroll = on and true or false, 0
	B.Stale()
end
-- "pre": no raid; a raid's name: that one ticked or unticked
function B.SetPhase(id)
	local on = type(B.db.phase[B.me]) == "table" and B.db.phase[B.me] or {}
	if id == "pre" then on = {} else on[id] = not on[id] or nil end
	B.db.phase[B.me], B.scroll = next(on) and on or nil, 0
	B.Stale()
end

-- may a dungeon's drops be looked for at this phase (a dungeon that is no raid always)
local function RaidOk(phase, d)
	local Dg = DT.Dungeon
	if not (phase and Dg and Dg.IsRaid and Dg.IsRaid(d)) or phase[3] == true then return true end
	for _, name in ipairs(phase[3]) do
		-- (a list may call it "Barrow Deeps" and another "Barrow Deeps Raid": the same raid)
		if Dg.Key(name):gsub("raid$", "") == (d.key or Dg.Key(d.name)):gsub("raid$", "") then return true end
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
function B.FromRaid(id, phase)
	if not phase or phase[3] == true then return false end
	local Q = DT.DB.Q
	for _, from in ipairs(FROM) do
		local list = Q("item", id, from[1])
		for _, thing in ipairs(type(list) == "table" and list or {}) do
			local d = RaidOf(Q(from[2], thing, from[3]))
			if d and not RaidOk(phase, d) then return true end
			-- (a quest a raid boss's drop starts: Nefarian's head goes to a city, its reward is the raid's all the same)
			local by = from[2] == "quest" and Q("quest", thing, "startedBy")
			for _, item in ipairs(type(by) == "table" and type(by[3]) == "table" and by[3] or {}) do
				local npcs = Q("item", item, "npcDrops")
				for _, npc in ipairs(type(npcs) == "table" and npcs or {}) do
					d = RaidOf(Q("npc", npc, "zoneID"))
					if d and not RaidOk(phase, d) then return true end
				end
			end
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
	-- for the other kind: a hunter's melee one counts a tenth; anyone else's ranged one nothing, it is for pulling.)
	if p.w.rdps == nil and p.w.dps then
		if raw.class == "HUNTER" then p.w.rdps, p.w.dps = p.w.dps, p.w.dps / 10 else p.w.rdps = 0 end
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
			if dirty and B.db and (wanted or (B.panel and B.panel:IsShown())) then wanted = nil DT.Timed("BiS: working out the sets", B.State) end
		end)
	end
end
local gen = 0 -- (counted up with every change: a working out that began before the last one is done again)
local function Stale()
	standings, theirReps = nil, nil -- (my reputations, and the other side's names: read again)
	dirty, gen = true, gen + 1
	if B.Refresh and B.panel and B.panel:IsShown() then B.redraw = true end
	Arm()
end
B.Want = function() if dirty then wanted = true Arm() end end -- (a tooltip wants a state that is not stale)
B.Stale = Stale

-- Locks: an item kept in a row (ROWS) by hand, for the sets to compare; per character and spec, kept over a /reload
local LOCKED = "|cffffd100[L]|r "
local REC = "|cff40ff40[R]|r " -- (a piece of the recommended set)
local function LockKey() local p = B.db and B.db.locks and B.Profile() return p and (B.me .. "|" .. p.id) end
function B.Locks() local k = LockKey() return k and B.db.locks[k] or {} end
-- (the same id again, or none: unlocked)
function B.Lock(r, id)
	local k = LockKey()
	if not k then return end
	local l = B.db.locks[k] or {}
	l[r] = l[r] ~= id and id or nil
	B.db.locks[k] = next(l) and l or nil
	Stale()
	if B.Refresh and B.panel and B.panel:IsShown() then B.Refresh() end -- (the mark at once; the sets a moment on)
end

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

-- an item's stats as worn in a row: a weapon in the off hand does half its damage (as the sets count it: BL's Cand)
local function StatsAt(it, r)
	if r ~= 16 or not it.s.dps then return it.s end
	local s = {}
	for word, n in pairs(it.s) do s[word] = n end
	s.dps = s.dps / 2
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
			if it then BL.Add(gear, StatsAt(it, r)) end
		end
	end
	return cur, gear, whole -- (gear: of what has loaded; whole: all of it, so the sheet may be read against it)
end

-- For the Mitigation tool, on a client that does not say the defense: five a level and what is on the gear I wear
-- now, read anew at every call (in a fight too: a shield or weapon changed there counts at once).
-- ponytail: talents, enchants and buffs that add defense are not in it: nothing on this client says them.
function B.WornDefense()
	local _, gear = Worn()
	return Level() * 5 + (gear.def or 0)
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

-- The enchants and consumables of Data/BisExtras.lua, as the game words them: { id, name, s }, nil while loading.
-- false: the game never answered (ASKS times, GAP seconds apart): left out.
local extras, extraAsks, extraAt = {}, {}, {}
B.extraWait = {} -- [item or spell number] = true while asked of the game (see the events at the bottom)
local function ExtraOf(id, spell)
	local key = (spell and "s" or "i") .. id
	if extras[key] ~= nil then return extras[key] end
	if extraAt[key] and Now() - extraAt[key] < GAP then return nil end
	if (extraAsks[key] or 0) >= ASKS then extras[key] = false return false end
	extraAsks[key], extraAt[key], B.extraWait[id] = (extraAsks[key] or 0) + 1, Now(), true
	local name, lines
	if spell then
		local ok, n = pcall(function() return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or GetSpellInfo and (GetSpellInfo(id)) end)
		local ok2, text = pcall(function() return C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id) or GetSpellDescription and GetSpellDescription(id) end)
		name, lines = ok and n or nil, ok2 and type(text) == "string" and text ~= "" and { text } or nil
		if not lines and C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
	else
		local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		name = info and info(id)
		lines = name and Lines(id)
		if not lines and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	end
	if not (name and lines) then return nil end -- (the game's answer comes as an event: see the bottom)
	B.extraWait[id] = nil
	extras[key] = { id = id, spell = spell, name = name, s = BL.UseStats(lines) }
	return extras[key]
end
B.ExtraOf = ExtraOf

-- The best enchant for each slot the hands allow, and the best consumable of each group, for a profile; and how
-- many are still loading. ponytail: one weapon enchant, even with two weapons.
local HANDS_SLOT = { Weapon2h = "2h", Shield = "shield" }
function B.Extras(prof)
	local X, list, waiting = DT.BisExtras or {}, {}, 0
	local hands = {}
	for _, h in ipairs(prof.hands or {}) do hands[h] = true end
	for _, e in ipairs(X.enchants or {}) do
		if not HANDS_SLOT[e[2]] or hands[HANDS_SLOT[e[2]]] then
			local x = ExtraOf(e[1], true)
			if x then list[#list + 1] = { id = x.id, spell = true, name = x.name, s = x.s, group = e[2] == "Weapon2h" and "Weapon" or e[2] } elseif x == nil then waiting = waiting + 1 end
		end
	end
	for _, e in ipairs(X.items or {}) do
		local x = ExtraOf(e[1])
		if x then list[#list + 1] = { id = x.id, name = x.name, s = x.s, group = e[2] } elseif x == nil then waiting = waiting + 1 end
	end
	return BL.BestExtras(list, prof), waiting
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
-- locks: { [row] = item id } kept in that row (an item not in the list is put in it)
local function Solve(list, s, locks)
	B.stats.solves = B.stats.solves + 1
	local need
	if locks and next(locks) then
		local has = {}
		for _, c in ipairs(list) do has[c.id] = true end
		list, need = { unpack(list) }, {}
		for r, id in pairs(locks) do
			local it = ROWS[r] and B.Item(id)
			if it then
				if not has[id] then has[id], list[#list + 1] = true, { id = id, loc = it.loc, s = it.s, n = 1 } end
				local i = ROWS[r][2]
				need[i] = need[i] or {}
				table.insert(need[i], id)
			end
		end
	end
	local slots = BL.Choices(list, s.prof, need)
	local picks, gear, score, short = BL.Solve(slots, s.base, s.prof, B.Tick)
	return { picks = picks, gear = gear, score = score, short = short }
end

-- What the sets and the upgrades are worked out from, as one text: the same text, the same answer. The weights and
-- caps (with what was typed), the level, the phase, the hands, what I wear, what I own, what was found; and how
-- the item facts are read (Stamp).
-- (mine: only what the best set of what I own and every gain hang on; not what I wear, nor what was found)
local function Sig(s, mine)
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
	for r = 1, mine and 0 or #ROWS do out[#out + 1] = tostring(s.cur[r] or 0) .. (B.suffixed[s.cur[r] or 0] or "") end
	for _, list in ipairs(mine and { s.own } or { s.own, s.all or {} }) do
		out[#out + 1] = "|"
		for _, c in ipairs(list) do out[#out + 1] = c.id .. "x" .. (c.n or 1) end
	end
	if not mine then
		local locks = {}
		for r, id in pairs(s.locks or {}) do locks[#locks + 1] = r .. "=" .. id end
		table.sort(locks)
		out[#out + 1] = "|" .. table.concat(locks, ",")
	end
	return table.concat(out, ";")
end

-- Kept in the saved file, per character and spec (db.saved): the two sets, so that a /reload shows them without
-- working them out. Not while items are still loading.
local function Bare(set) return set and { picks = set.picks, gear = set.gear, score = set.score, short = set.short } end
local function Save(s)
	if s.foreign or s.pending > 0 or not s.sig or s ~= state then return end
	s.at = Clock()
	B.db.saved[s.skey] = { sig = s.sig, at = s.at, best = Bare(s.best), bis = Bare(s.bis) }
end

-- a part of the working out, timed; one that fails leaves the rest to show, and the tab says which (B.err)
local function Try(name, fn, ...)
	DT.Timed(name, function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			B.failed = name .. ": " .. tostring(err)
			error(err, 0)
		end
	end, ...)
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
		-- (and the best enchants and consumables: what they give a capped stat counts toward it, the rest is listed)
		DT.Timed("BiS: extras read", function() s.extras = B.Extras(prof) end) -- (still loading: not waited for; once in, the base moves and all is worked out anew)
		for _, x in pairs(s.extras or {}) do
			for word, n in pairs(x.s) do
				if prof.caps[word] then s.base[word] = (s.base[word] or 0) + n end
			end
		end
	end
	s.locks = B.Locks()
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
	-- the list: what of it the game knows and this class may wear at the level looked at; and with it the best of
	-- the pool (every item there is that this class may wear and can get), a few of each place to wear
	s.list = DT.BisLists and DT.BisLists[prof.id]
	s.upg = {}
	local all, seen, found = {}, {}, {}
	local function Add(id, it)
		seen[id] = true
		all[#all + 1] = { id = id, loc = it.loc, s = it.s, n = 1 }
	end
	for id in pairs(s.list or {}) do
		local it = B.Item(id)
		if it == nil then
			s.pending = s.pending + 1
		elseif it and Usable(it, s.who) then
			Add(id, it)
		end
	end
	-- (and what I own: the recommended set never gives up a piece I have for a worse one)
	for _, o in ipairs(s.foreign and {} or s.own) do
		if not seen[o.id] then
			seen[o.id] = true
			all[#all + 1] = o
		end
	end
	Try("BiS: pool", function() s.pool = Pool(s.who) end)
	s.pool = s.pool or {}
	for _, c in ipairs(s.pool) do
		local it = not seen[c.id] and B.Item(c.id)
		if it then
			found[it.loc] = found[it.loc] or {}
			table.insert(found[it.loc], { id = c.id, it = it, s = it.s })
		end
	end
	for _, list in pairs(found) do
		local taken = BL.Few(list, prof, POOL)
		for _, e in ipairs(list) do
			if taken[e.id] then Add(e.id, e.it) end
		end
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
	end
	if #all > 0 then
		table.sort(all, function(a, b) return a.id < b.id end)
		s.all = all
	end
	-- what was worked out from the very same as now, in this session or an earlier one: taken as it is
	s.sig, s.gsig, s.skey = Sig(s), Sig(s, true), B.me .. "|" .. prof.id
	local saved = not s.foreign and B.db.saved[s.skey]
	local had
	B.stats.computes = B.stats.computes + 1
	-- (the same as what is worked out already: kept. Selling junk changes the bags, not what may be worn)
	if state and state.sig == s.sig and state.skey == s.skey then
		B.stats.kept = B.stats.kept + 1
		dirty = false
		state.extras = s.extras -- (the enchants and consumables as read now: they come in after the sets)
		-- (the pool grew, with items the loader brought, though not among the few that go into the sets: the upgrades anew)
		if s.pool.key ~= (state.pool or {}).key and not state.foreign then
			state.pool, state.upg, state.rank, gains = s.pool, {}, {}, {}
			DT.Timed("BiS: upgrades weighed", Upgrades, state)
		end
		return true
	end
	if saved and saved.sig == s.sig then
		s.best, s.bis, s.at, had = Bare(saved.best), Bare(saved.bis), saved.at, true
	else
		if state and state.gsig == s.gsig and state.skey == s.skey and not state.foreign then
			s.best = state.best -- (only what I wear, or the pool, moved: the best of what I own stands)
		else
			s.best = Solve(s.own, s) -- (not in Try: the working out pauses in here, which it cannot inside a pcall)
		end
		if s.all then s.bis = Solve(all, s, s.locks) end
	end
	s.best.rows = Lay(s.best.picks, s.cur)
	s.best.has = {}
	for _, id in pairs(s.best.rows) do s.best.has[id] = true end
	if s.bis then s.bis.rows = Lay(s.bis.picks, s.cur) end
	state, dirty, gains = s, false, {}
	if not s.foreign then Try("BiS: upgrades weighed", Upgrades, s) end
	if not had then Save(s) end
	return true
end

-- the Recalculate button: asked first, as it takes a while
if StaticPopupDialogs then
	StaticPopupDialogs.DAWNTOOLS_BIS_RECALC = {
		text = "DawnTools BiS: work everything out anew?\n\nThe item list is read again and the sets worked out anew.",
		button1 = "Recalculate", button2 = "Cancel",
		OnAccept = function() B.Recalc() end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
end
function B.AskRecalc()
	if StaticPopup_Show then StaticPopup_Show("DAWNTOOLS_BIS_RECALC") else B.Recalc() end
end

-- Worked out anew by hand (the Recalculate button): what was saved for the spec goes, the item list is read again,
-- (items the game did not answer for wait a week, or the game's next build: see B.Never)
function B.Recalc()
	local s = state
	if s and s.skey then B.db.saved[s.skey] = nil end
	-- (what is worked out goes too, or the same gear would be taken for the same answer; and what was asked once an item)
	state, gains, raidZone = nil, {}, {}
	B.Drop()
	B.Forget()
	B.Reload()
	Stale()
end

-- the state, worked out anew where something changed (in a fight: as it was)
-- Worked out over several frames, a few milliseconds in each: in one go the sets took a second, and the game stood
-- still for it. The working out is a coroutine (job) that pauses in the solver (B.Tick) when its time for the frame
-- is up; the worker's OnUpdate takes it up again. Until it is done, the state is the one before.
-- ponytail: only the solver pauses; the pool and the upgrades are done in one go each (some tens of ms).
local SLICE = 6 -- (ms a frame)
local job, jobGen, sliceEnd
local worker = CreateFrame("Frame")
worker:Hide()
function B.Tick()
	if job and sliceEnd and coroutine.running() == job and debugprofilestop() > sliceEnd then coroutine.yield() end
end
function B.Working() return job ~= nil end
function B.Drop() job = nil end -- (what is being worked out is of no use any more: Recalculate)
function B.State()
	if job and coroutine.running() == job then return state end -- (asked from inside the working out)
	if dirty and not Fight() then
		if not job then job, jobGen, B.failed = coroutine.create(B.Compute), gen, nil end
		local co, t0, m0 = job, DT.Mark()
		sliceEnd = debugprofilestop and not B.whole and debugprofilestop() + SLICE or nil
		local ok, err = coroutine.resume(co)
		DT.Note("BiS: sets, one frame's share", t0, m0)
		if job ~= co then return state end -- (dropped meanwhile)
		if coroutine.status(co) ~= "dead" then
			worker:Show()
			return state
		end
		job = nil
		worker:Hide()
		-- (a client that will not pause there: in one go from now on, as before)
		if not ok and not B.whole and tostring(err):find("yield", 1, true) then
			B.whole = true
			return B.State()
		end
		B.err = not ok and tostring(err) or B.failed -- (shown on the tab: an empty list must not hide it)
		if not ok then
			dirty = false -- (not tried again on every tooltip)
			geterrorhandler()(err)
		elseif jobGen ~= gen then
			dirty = true -- (something changed while it was worked out: once more)
			worker:Show()
		end
	end
	return state
end
DT.OnUpdate(worker, "BiS: sets worked out", function(self)
	if Fight() then return end
	if not (job or dirty) then self:Hide() return end
	B.State()
	if not job then
		self:Hide()
		if B.Refresh and B.panel and B.panel:IsShown() then B.Refresh() end
	end
end)

-- What an item would do for my best set (Quick, below): { d = gain in score, pct, slots = { names of the slots it
-- changes }, reach = { stats whose hard cap it gets me to }, breaks = { hard caps it takes me under }, owned, best,
-- no = cannot wear, level = wearable from }. nil while it cannot be said (not loaded, not gear, a fight with nothing
-- worked out). (lazy: with what was worked out last, for a tooltip, which must not wait for a new working out)
function B.Gain(id, lazy)
	local s = lazy and state or B.State()
	if not s then return nil end
	if gains[id] ~= nil then return gains[id] or nil end
	if Fight() then return nil end
	local g = Quick(s, id)
	if g == nil then return nil end
	gains[id] = g
	return g or nil
end

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
function B.IsUpgrade(id)
	if not B.db then return nil end -- (BiS switched off, or not started yet)
	local s = state or B.State() -- (the saved sets, where the BiS tab has not been open this session)
	if not s or s.foreign then return nil end
	local g = B.Gain(id, true)
	return g and g.up and not g.level and not g.owned or false
end

-- the words for a gain: "+12.4 (+1.8%)  Head, Rings"
function B.GainText(g)
	if g.owned then return "" end -- (the tooltip says what it does against what I wear)
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
	if dirty or not state then B.Want() end
	local s = state -- (never worked out here: a second and more after a login. Asked for, it shows from the next look)
	if not s or s.foreign then return end -- (another class looked at: nothing to say of my gear)
	local g = B.Gain(id, true)
	if not g or g.no then return end -- (not for my class: said nothing, as the game's own red lines say it)
	local rank = s.rank[id] and ("  |cffffd100#%d upgrade|r"):format(s.rank[id]) or ""
	-- (one I own but do not wear, or one that does not better the best set: what it does against what I wear now)
	local worn = false
	for _, w in pairs(s.cur) do worn = worn or w == id end
	local text = B.GainText(g)
	if worn then text = "|cff888888worn|r"
	elseif g.owned or not g.up then
		local _, d, p = B.VsWorn(s, id)
		if d and math.abs(d) > 0.05 then
			text = ("|cff%s%s%s|r"):format(d > 0 and "40ff40" or "c86464", Signed(d), p and (" (%+.1f%%)"):format(p) or "")
		elseif g.owned then text = "|cff888888no change|r" end
		if d and d > 0.05 and not g.up and g.breaks and #g.breaks > 0 then -- (more score, but under a cap I reach now)
			local names = {}
			for i, word in ipairs(g.breaks) do names[i] = LABEL[word] or word end
			text = text .. "  |cffc86464drops " .. table.concat(names, ", ") .. " below cap|r"
		end
	end
	tip:AddDoubleLine(DT.TIP .. "BiS  |cff888888" .. s.prof.title .. "|r", text .. rank, 0.78, 0.68, 0.37, 1, 1, 1)
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
local VIEWS = { { "gear", "Gear" }, { "up", "Upgrades" }, { "extras", "Extras" }, { "weights", "Weights" }, { "check", "Check" } }
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
		if self.lock then GameTooltip:AddLine(self.locked and "Right-click: unlock" or "Right-click: lock in this slot (the sets keep it)", 0.6, 0.6, 0.6) end
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
		if button == "RightButton" and self.lock then return self.lock() end
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
-- r = the row it is in (the off hand's: see StatsAt)
local function Worth(s, set, id, out, r)
	local it, gone = id and B.Item(id), out and B.Item(out)
	if not it then return nil end
	local g = BL.Add({}, set)
	if gone then BL.Add(g, StatsAt(gone, r), -1) end
	local without = BL.Score(g, s.base, s.prof)
	return BL.Score(BL.Add(g, StatsAt(it, r)), s.base, s.prof) - without
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

-- What an item does swapped in for what I wear, alone: in the place where it does most (of two rings or trinkets,
-- the weaker), the score of what I wear with it less without (a two-hander takes the off hand out too, an off hand
-- a two-hander), and that in percent of the weight of the piece it replaces: as the slot's list says it. A swap that
-- takes me under a hard cap I meet now is no upgrade, whatever it adds. See B.Gain.
-- ponytail: one piece at a time, the rest as worn; the recommended set is where pieces go together.
function Quick(s, id)
	local it = B.Item(id)
	if it == nil then return nil end
	if not it then return false end
	local g = {}
	if s.have[id] then g.owned, g.best = true, s.best.has[id] or false return g end
	if not Usable(it, s.who, true) then g.no = true return g end
	local rows, top = s.cur, nil
	for r = 1, #ROWS do
		if Fits(r, it.loc, s.prof) then
			local gear = BL.Add({}, s.curGear)
			local function Out(at)
				local o = rows[at] and B.Item(rows[at])
				if o then BL.Add(gear, StatsAt(o, at), -1) end
			end
			Out(r)
			if r == 15 and it.loc == "INVTYPE_2HWEAPON" then Out(16) end
			local mh = r == 16 and rows[15] and B.Item(rows[15])
			if mh and mh.loc == "INVTYPE_2HWEAPON" then Out(15) end
			BL.Add(gear, StatsAt(it, r))
			local score, short = BL.Score(gear, s.base, s.prof)
			local breaks = 0
			for word in pairs(short) do if not s.curShort[word] then breaks = breaks + 1 end end
			if not top or breaks < top.breaks or (breaks == top.breaks and score > top.score) then
				top = { score = score, short = short, r = r, breaks = breaks, gear = gear }
			end
		end
	end
	if not top then g.no = true return g end
	g.d = top.score - s.curScore
	local out = rows[top.r]
	local was = out and Worth(s, s.curGear, out, out, top.r) or 0
	g.pct = was > 0.05 and g.d / was * 100 or nil
	local name = ROWS[top.r][1]:gsub(" %d$", "")
	if it.loc == "INVTYPE_2HWEAPON" then name = "Two-hand" end
	g.slots, g.reach, g.breaks = { name }, {}, {}
	for word in pairs(s.curShort) do
		if not top.short[word] then g.reach[#g.reach + 1] = word end
	end
	-- (breaks: every cap I meet now that it takes me under, soft or hard; only a hard one stops it being an upgrade)
	for word, cap in pairs(s.prof.caps) do
		local before, after = (s.base[word] or 0) + (s.curGear[word] or 0), (s.base[word] or 0) + (top.gear[word] or 0)
		if before >= cap.cap - 1e-9 and after < cap.cap - 1e-9 then g.breaks[#g.breaks + 1] = word end
	end
	table.sort(g.reach)
	table.sort(g.breaks)
	if it.lvl > s.who.level then g.level = it.lvl end
	g.up = top.breaks == 0 and (g.d > 0.005 or #g.reach > 0)
	return g
end

-- every item of the pool and the list I do not own that would better what I wear: s.upg, the most first
function Upgrades(s)
	local seen = {}
	local function Try(id)
		if seen[id] or s.have[id] then return end
		seen[id] = true
		local g = B.Gain(id)
		if g and g.up and not g.level then s.upg[#s.upg + 1] = { id = id, g = g } end
	end
	for _, c in ipairs(s.pool or {}) do Try(c.id) end
	for id in pairs(s.list or {}) do Try(id) end
	table.sort(s.upg, function(a, b)
		if (#a.g.reach > 0) ~= (#b.g.reach > 0) then return #a.g.reach > 0 end
		if a.g.d ~= b.g.d then return a.g.d > b.g.d end
		return a.id < b.id
	end)
	for i, u in ipairs(s.upg) do s.rank[u.id] = i end
end

-- An item against the worn piece it would replace (the weaker of two rings or trinkets; none: an empty slot):
-- its weight there, the change, and that in percent of the worn piece's weight (nil for an empty slot).
-- nil where it cannot be said (not loaded, or worn in no slot this spec uses).
function B.VsWorn(s, id)
	local it = B.Item(id)
	if not it then return nil end
	local out, outW, any, at = nil, nil, false, nil
	for r = 1, #ROWS do
		if Fits(r, it.loc, s.prof) then
			any = true
			local w = s.cur[r] and Worth(s, s.curGear, s.cur[r], s.cur[r], r) or 0
			if not outW or w < outW then out, outW, at = s.cur[r], w, r end
		end
	end
	if not any then return nil end
	local worth = Worth(s, s.curGear, id, out, at)
	if not worth then return nil end
	local d = worth - (outW or 0)
	return worth, d, out and (outW or 0) > 0.05 and d / outW * 100 or nil, out
end

---------------------------------------------------------------------------
-- The gear there is
---------------------------------------------------------------------------
-- Which items there are is not DawnTools' own: read at runtime from QuestieDB as the Items tab reads it (quest
-- rewards, drops, vendors), from the dungeon list (Modules/Dungeon.lua) and the recipes (DT.CraftSkill). Every
-- wearable one is asked of the game once, ever, a few a frame in the background (the loader); what it gives is kept
-- in the saved file (db.facts). A spec's pool is then every one its class may wear at the level looked at and can
-- get, read from there: no item is left out for its level or its type.
-- ponytail: an item the game never answers for is left out for a week, or until the game's next build.

-- the words for where an item is from (the owner's: crafted, bought, found, quest); a boss's drop is a Raid where its dungeon is one
local TAG = { quest = "Quest", crafted = "Crafted", boe = "World Drop", vendor = "Vendor", dungeon = "Dungeon", owned = "Owned" }
local LISTKIND = { ["dungeon drop"] = "dungeon", crafted = "crafted", quest = "quest", ["world drop"] = "boe" } -- (the words of Data/BisLists.lua)
local RANK = { dungeon = 5, quest = 4, crafted = 3, boe = 2, vendor = 1 } -- (an item of two kinds is listed under the higher)

-- Every wearable item there is: { ids, kind = { [id] = where it is from }, entry = { [id] = the item list's },
-- boss = { [id] = the dungeon whose boss drops it } }; nil until the item list is read.
-- (made anew when the item list or the dungeon list is another, and the loader then goes over it again)
local function Catalog()
	local Item, Dg = DT.Item, DT.Dungeon
	if not (Item and Item.Ready and Item.Ready()) then return nil end
	local list, dl = Item.All and Item.All() or {}, Dg and Dg.All and Dg.All() or {}
	if catalog and catalog.list == list and catalog.dl == dl then return catalog end
	local c = { ids = {}, kind = {}, entry = {}, boss = {}, list = list, dl = dl }
	for _, d in ipairs(dl) do
		for _, boss in ipairs(d.bosses) do
			-- (dropped in two places: the first of the list, and a dungeon before a raid, so that a raid not ticked does not hide it)
			for id in pairs(boss.has) do
				local had = c.boss[id]
				if not had or (Dg.IsRaid and Dg.IsRaid(had) and not Dg.IsRaid(d)) then c.boss[id] = d end
			end
		end
	end
	local function Add(id, kind)
		if not c.kind[id] then c.ids[#c.ids + 1] = id end
		if (RANK[kind] or 0) > (RANK[c.kind[id]] or 0) then c.kind[id] = kind end
	end
	local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	for _, e in ipairs(list) do
		-- (no class in the item list (15, as Forever's own items may have): the game's own file says, no question to the server)
		local cls = e.c
		if cls == 15 and instant then cls = select(6, instant(e.id)) end
		if cls == 2 or cls == 4 then
			local kind = c.boss[e.id] and "dungeon" or e.src["Quest reward"] and "quest" or ((DT.CraftSkill and DT.CraftSkill[e.id]) or e.src.Crafted) and "crafted"
				or e.src.Drop and "boe" or e.src.Vendor and "vendor" or nil
			if kind then
				c.entry[e.id] = e
				Add(e.id, kind)
			end
		end
	end
	for id in pairs(c.boss) do Add(id, "dungeon") end
	table.sort(c.ids)
	catalog = c
	if B.loader and not B.loader:IsShown() then
		B.load.at, B.load.waiting, B.load.left = 1, 0, nil
		B.loader:Show()
	end
	return c
end
B.Catalog = Catalog

-- The loader: every item of the catalog asked of the game once (ItemOf keeps what it gives), out of a fight, a few
-- milliseconds a frame, and no more than RATE questions to the game a second (an item it never answers for is asked
-- ASKS times, GAP seconds apart, then left for the session). A pass over all of them that finds none waiting is the
-- last; while it goes, the sets are worked out anew every few seconds with what came in.
-- ponytail: twenty questions a second at most (8,700 items: some seven minutes, once ever); what a guildmate shared is no question
local RATE = 20
local checked = {} -- [id] = true: looked at this session for a row to share
local loader = CreateFrame("Frame")
local load = { at = 1, waiting = 0, left = nil, budget = RATE, last = nil, got = 0, shown = 0 }
B.load, B.loader = load, loader
DT.OnUpdate(loader, "BiS: item loader", function(self)
	if Fight() or not B.db then return end
	local c = Catalog()
	if not c then return end
	local now = Now()
	load.budget = math.min(RATE, load.budget + (now - (load.last or now)) * RATE)
	load.last = now
	local facts = B.db.facts or {}
	local t0 = debugprofilestop and debugprofilestop()
	for _ = 1, 400 do
		if load.at > #c.ids then
			load.left, load.at, load.waiting = load.waiting, 1, 0
			if load.left == 0 then
				self:Hide()
				Stale()
				if B.refresher then B.refresher:Show() end
				return
			end
		end
		local id = c.ids[load.at]
		local unknown = items[id] == nil and facts[id] == nil and not B.Never(id)
		if unknown and not partial[id] and Shared(id) ~= nil then unknown, load.got = false, load.got + 1 end -- (a guildmate's row)
		-- (what my game told me in an earlier session, and nobody has shared yet: shared)
		if not unknown and facts[id] ~= nil and not checked[id] then
			checked[id] = true
			if DT:Shares() and not DT.DB.Row("istat:" .. id) then Share(id, facts[id]) end
		end
		-- (one the game is asked about now: within the budget, or on from here next frame)
		-- (one the game already holds is read at once, outside the budget)
		local asks = unknown and (asked[id] or 0) < ASKS and (not askedAt[id] or now - askedAt[id] >= GAP)
			and not (C_Item and C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(id))
		if asks then
			if load.budget < 1 then break end
			load.budget = load.budget - 1
		end
		load.at = load.at + 1
		if unknown then
			if ItemOf(id) ~= nil then load.got = load.got + 1
			elseif B.Gone(id) then if B.db.never and time then B.db.never[id] = time() end
			else load.waiting = load.waiting + 1 end
		end
		if t0 and debugprofilestop() - t0 > 3 then break end
	end
	-- ponytail: the sets anew every 20 seconds while items come (a few hundred ms each with the tab open); the last at the end
	if load.got > 0 and now - load.shown >= 20 then
		load.got, load.shown = 0, now
		Stale()
	end
end)

-- Items changed by a patch: once a session, after the loader, every item my game told of is read again, ten a
-- second, from what the game holds at hand only (never a question to the server). Where it says otherwise now,
-- that is kept, and shared: the newer row stands in every member's store.
local refresh = { at = 1, budget = 0 }
B.refresh = refresh
B.refresher = CreateFrame("Frame")
B.refresher:Hide()
DT.OnUpdate(B.refresher, "BiS: items read again", function(self, elapsed)
	if Fight() or not B.db or loader:IsShown() then return end
	local cached, c = C_Item and C_Item.IsItemDataCachedByID, Catalog()
	if not (cached and c) then self:Hide() return end
	refresh.budget = math.min(10, refresh.budget + (tonumber(elapsed) or 0) * 10)
	while refresh.budget >= 1 do
		refresh.budget = refresh.budget - 1
		if refresh.at > #c.ids then self:Hide() return end
		local id = c.ids[refresh.at]
		refresh.at = refresh.at + 1
		local old = B.db.facts[id]
		if old and cached(id) then
			local name, _, quality, _, minLevel, _, _, _, loc, icon, _, class, sub = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
			local lines = name and WEARABLE[loc or ""] and Lines(id)
			if lines then
				local it = FactsOf(id, name, quality, minLevel, loc, icon, class, sub, lines)
				if RowText(it) ~= RowText(old) then
					B.db.facts[id], items[id] = it, it
					Share(id, it)
					B.refresh.changed = (B.refresh.changed or 0) + 1
					Stale()
				end
			end
		end
	end
end)

-- an answer is taken as it comes, not on the loader's next pass over the whole list
DT:On("GET_ITEM_INFO_RECEIVED", function(id, ok)
	if not (ok and loader:IsShown() and B.db and items[id] == nil and asked[id]) then return end
	if ItemOf(id) ~= nil then load.got = load.got + 1 end
end)

-- how many items are still to come from the game (0: all there is is known; nil: the item list is not read yet)
function B.Left()
	if not Catalog() then return nil end
	if not loader:IsShown() then return 0 end
	-- (counted, not kept: the items still unknown and not given up)
	local facts, n = B.db and B.db.facts or {}, 0
	for _, id in ipairs(catalog.ids) do
		if items[id] == nil and facts[id] == nil and not partial[id] and not B.Gone(id) then n = n + 1 end
	end
	return n
end

-- read again (the Recalculate button): the item list, and every item the game did not answer for
function B.Reload()
	catalog = nil
	for id in pairs(asked) do
		if items[id] == nil then asked[id], askedAt[id] = nil, nil end
	end
	load.at, load.waiting, load.left = 1, 0, nil
	loader:Show()
end

-- The pool for who (as Target gives it) at the phase looked at: { { id, kind }... } of every item of the catalog the
-- game has told of that they may wear and can get: not the other faction's, not a raid's the phase leaves out.
local otherSide, fromRaid = {}, {} -- (my side and a raid's place do not change in a session: asked once an item)
-- The level a quest's reward can be had at: of the quests that give it, the least of what a quest asks for, and no
-- less than five under the quest's own level (the item itself often asks for no level at all).
-- ponytail: five under the quest's level is a rule of thumb for "a quest I could do"; a quest that goes with my level counts as open.
local questAt = {}
function B.QuestLevel(id)
	if questAt[id] == nil then
		local least
		for _, f in ipairs(DT.DB.RelTo("rewards", "item", id)) do
			local need = math.max(tonumber(Q("quest", f.id, "requiredLevel")) or 0, (tonumber(Q("quest", f.id, "questLevel")) or 0) - 5)
			if not least or need < least then least = need end
		end
		questAt[id] = least or 0
	end
	return questAt[id]
end
function B.Forget() otherSide, fromRaid, questAt, B.wheres = {}, {}, {}, {} end -- (Recalculate: asked anew)
function Pool(who)
	local c = Catalog()
	if not c then return {} end
	local phase = B.Phase() or { "pre", "Pre-raid", {} } -- (below the last level: no raid's gear, as before any raid is ticked)
	local key = phase and phase[1] or "-"
	fromRaid[key] = fromRaid[key] or {}
	local raided = fromRaid[key]
	local out, ids = {}, {}
	for _, id in ipairs(c.ids) do
		local it = items[id]
		if it == nil and B.db.facts then it = B.db.facts[id] end
		if it and it.lvl <= who.level and (c.kind[id] ~= "boe" or it.boe) and Usable(it, who) then
			local d, e, ok = c.boss[id], c.entry[id], true
			if d then
				ok = RaidOk(phase, d)
			elseif e then
				if otherSide[id] == nil then otherSide[id] = B.OtherSide(e) end
				if raided[id] == nil then raided[id] = (e.ilvl or 0) >= 58 and B.FromRaid(id, phase) or false end
				ok = not otherSide[id] and not raided[id]
				-- (a quest's reward that is to be had no other way: not before the quest is. One also made, sold or dropped is)
				if ok and c.kind[id] == "quest" and not (e.src.Crafted or e.src.Vendor or e.src.Drop or (DT.CraftSkill and DT.CraftSkill[id])) then
					ok = B.QuestLevel(id) <= who.level
				end
			end
			if ok then out[#out + 1], ids[#ids + 1] = { id = id, kind = c.kind[id] }, id end
		end
	end
	out.key = table.concat(ids, ",") -- (the same items, the same pool)
	return out
end

-- /dt bis <item>: every step an item goes through, to see where it falls out
function B.Why(arg)
	if arg == "load" then -- (the loader: where it is, and a few of the items it still waits for)
		local c, facts, n = Catalog(), B.db and B.db.facts or {}, 0
		DT:Print("BiS loader: running %s, in a fight %s, item list %s, at %d of %d, waiting %d, last pass left %s, budget %.1f",
			tostring(loader:IsShown()), tostring(Fight()), c and "read" or "NOT read", load.at, c and #c.ids or 0, load.waiting,
			tostring(load.left), load.budget or 0)
		for _, id in ipairs(c and c.ids or {}) do
			if items[id] == nil and facts[id] == nil and not partial[id] and not B.Gone(id) then
				n = n + 1
				if n <= 5 then
					local name = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
					DT:Print("  waiting %d %s: asked %d, %.0fs ago, tooltip %s", id, tostring(name), asked[id] or 0,
						askedAt[id] and Now() - askedAt[id] or -1, Lines(id) and "yes" or "no")
				end
			end
		end
		local shared = 0
		for _, it in pairs(items) do if it and it.shared then shared = shared + 1 end end
		DT:Print("BiS loader: %d items unknown and not given up; %d from guildmates' rows this session%s; read again for a patch: %s, %d changed",
			n, shared, DT:Shares() and "" or " (sharing is off)", B.refresher:IsShown() and ("at %d"):format(refresh.at) or "not running", refresh.changed or 0)
		local never = 0
		for _, id in ipairs(catalog and catalog.ids or {}) do if B.Never(id) then never = never + 1 end end
		DT:Print("BiS loader: %d items the game never answered (asked again in a week, or in a new build of the game)", never)
		return
	end
	local id =tonumber(tostring(arg):match("item:(%d+)") or tostring(arg):match("^(%d+)$"))
	if not id then DT:Print("/dt bis <item link or number>") return end
	local s, c = B.State(), Catalog()
	local function Say(...) DT:Print("BiS %d: " .. select(1, ...), id, select(2, ...)) end
	if c then Say("catalog: %s%s", tostring(c.kind[id] or "NOT in it"), c.boss[id] and (", dropped in " .. tostring(c.boss[id].name)) or "")
	else Say("the item list is not read yet") end
	if c and not c.kind[id] then -- (why not: the item list's own type and sources for it)
		local entry
		for _, e in ipairs(DT.Item.All and DT.Item.All() or {}) do if e.id == id then entry = e break end end
		local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
		if entry then Say("item list: type %s (the game says %s), from: %s", tostring(entry.c), tostring(instant and select(6, instant(id))), entry.srcText ~= "" and entry.srcText or "nowhere known")
		else Say("item list: not in it") end
	end
	local it = items[id]
	if it == nil and B.db.facts then it = B.db.facts[id] end
	if it == nil then Say("not loaded (asked %d times%s)", asked[id] or 0, B.Gone(id) and ", given up" or "") return end
	if it == false then Say("the game says it is no gear") return end
	Say("%s, %s, class %s/%s, level %d%s: %s", tostring(it.name), tostring(it.loc), tostring(it.class), tostring(it.sub), it.lvl or 0,
		it.partial and " (no tooltip yet)" or "", B.StatText(it.s))
	if not s then Say("nothing worked out yet") return end
	Say("usable: %s; level %d <= %d: %s", tostring(Usable(it, s.who)), it.lvl or 0, s.who.level, tostring((it.lvl or 0) <= s.who.level))
	local inPool = false
	for _, p in ipairs(s.pool or {}) do inPool = inPool or p.id == id end
	Say("in the pool: %s", tostring(inPool))
	local g = B.Gain(id)
	if g then
		Say("vs worn: %s (%s%%), upgrade %s%s", tostring(g.d), tostring(g.pct), tostring(g.up),
			g.breaks and #g.breaks > 0 and (", breaks " .. table.concat(g.breaks, ", ")) or "")
	end
	for r, rid in pairs(s.bis and s.bis.rows or {}) do
		if rid == id then Say("in the recommended set, row %d", r) end
	end
end

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
--   two worn (rings, trinkets): each row against what is worn in it (ref = the row); what the other holds is not listed;
--   the worn item is the one to beat, not the best I own: an owned one that is not worn says so (kind owned).
-- ponytail: what is looked at is the pool (every item there is for the spec), what I own and the list's items; a hard cap
-- not yet reached counts as the weight of its stat only, as in every score: the sets (B.Perm) are where it comes first.
function B.Rank(r, above, below)
	local s = state
	if not s then return nil end
	above, below = above or 500, below or 4
	local function W(at) return s.cur[at] and Worth(s, s.curGear, s.cur[at], s.cur[at], at) or 0 end
	-- (two rings, two trinkets: each row against what is worn in it. What is worn in the other is not one to get: see "on")
	local ref = r
	local worn, on, seen, pool = s.cur[ref], {}, {}, {}
	for _, id in pairs(s.cur) do on[id] = true end -- (a ring on the other finger is not one to get)
	local wornW = W(ref)
	local wornIt = worn and B.Item(worn)
	local mh = s.cur[15] and B.Item(s.cur[15])
	local blocked = ref == 16 and mh and mh.loc == "INVTYPE_2HWEAPON" or false
	local function Add(id, kind)
		if blocked or seen[id] or on[id] then return end
		seen[id] = true
		local it = B.Item(id)
		if it and Fits(r, it.loc, s.prof) and Usable(it, s.who) then
			local g = BL.Add({}, s.curGear)
			if wornIt then BL.Add(g, StatsAt(wornIt, ref), -1) end
			local off = ref == 15 and it.loc == "INVTYPE_2HWEAPON" and s.cur[16] and B.Item(s.cur[16])
			if off then BL.Add(g, StatsAt(off, 16), -1) end
			local gain = BL.Score(BL.Add(g, StatsAt(it, ref)), s.base, s.prof) - s.curScore
			pool[#pool + 1] = { id = id, worth = wornW + gain, gain = gain, kind = s.have[id] and "owned" or kind,
				pct = wornW > 0.05 and gain / wornW * 100 or nil, new = not worn or nil }
		end
	end
	for _, o in ipairs(s.own) do Add(o.id, "owned") end
	for _, c in ipairs(s.pool or {}) do Add(c.id, c.kind) end
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

-- What I wear (1), and the recommended set (2: the best there is for the spec, the hard caps first, what is locked kept
-- in its place: s.bis; the best I own where the pool is empty).
B.scroll = 0 -- (how far the list on the right is scrolled)
function B.Perm(i)
	local s = state
	if not s or Fight() then return nil end
	if i == 1 then return { rows = s.cur, gear = s.curGear, score = s.curScore, short = s.curShort } end
	return s.bis or s.best
end

-- "Hit" for "Hit %"
function B.Short(word) return ((LABEL[word] or word):gsub("%s*%%$", "")) end

-- where an item is from, as far as the catalog and the list say (nil: not known)
function B.Kind(id)
	return catalog and catalog.kind[id] or state and state.list and LISTKIND[state.list[id]] or nil
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
		-- (a quest of my side, where both sides have one: Nefarian's head goes to Bolvar or to Thrall)
		local quest, mine = nil, MySide()
		for _, f in ipairs(DT.DB.RelTo("rewards", "item", id)) do
			local side = B.QuestSide(f.id)
			if side == mine or side == "" then quest = f.id break end
			quest = quest or f.id
		end
		local e = quest and Q and Q.Entry and Q.Entry(quest)
		if quest and not e and Q and Q.Start and Q.Start() then -- (the quests are still being read: read on, ask again)
			Q.Step(4)
			return "quest reward  |cff888888reading the quests...|r"
		end
		if e then
			local o = Q.Origin and Q.Origin(e)
			local side = B.QuestSide(quest)
			B.quests[id] = e
			text = ("|cffffd100%s|r%s  |cff888888%s|r%s"):format(o and o.text or "giver not known", e.zoneName and (", " .. e.zoneName) or "", e.name,
				side ~= "" and side ~= mine and "  |cffff4040other faction|r" or "")
		else
			text = text ~= "" and text or "quest reward"
		end
	elseif kind == "dungeon" and DT.Dungeon and DT.Dungeon.DropOf and DT.Dungeon.DropOf(id) then
		-- "Zul'Farrak, Nekrum Gutchewer (12%)"; "Zul'Farrak, trash"
		local Dg = DT.Dungeon
		local boss = Dg.DropOf(id)
		local chance = boss.name ~= "Trash" and Dg.Chance and Dg.Chance(boss, id)
		text = ("%s, %s%s"):format(boss.dungeon.name, boss.name == "Trash" and "trash" or boss.name,
			chance and (" (%s%%)"):format((("%.1f"):format(chance):gsub("%.0$", ""))) or "")
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
		local id = B.Locks()[self.row]
		if id then
			if not self.id then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
			GameTooltip:AddLine(("Locked: %s. Right-click: unlock"):format(Name(id)), 1, 0.82, 0, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self, button)
		if self.id and ItemClick(self.id, button) then return end
		if button == "RightButton" and B.Locks()[self.row] then return B.Lock(self.row) end
		picked, B.scroll = self.row, 0
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
	l.wt, l.diff, l.pct = Text(f, nil, "RIGHT"), Text(f, nil, "RIGHT"), Text(f, "GameFontDisableSmall", "RIGHT")
	l.from = Text(f)
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
	for c = 1, 5 do gear.cols[c] = Text(f, "GameFontNormalSmall", c <= 3 and "RIGHT" or "LEFT") end -- (the muted gold of the other tabs)
	-- (what is shown is kept from one session to the next: looked through and worked out anew on a click)
	gear.redo = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	gear.redo:SetSize(90, 18)
	gear.redo:SetText("Recalculate")
	gear.redo:SetScript("OnClick", function() B.AskRecalc() end)
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
	local worth = Worth(s, s.foreign and s.bis and s.bis.gear or s.curGear, shown, shown, r)
	local top = s.bis and Worth(s, s.bis.gear, bis, bis, r)
	local part = (bis and shown == bis) and 1 or (worth and top and top > 0) and worth / top or nil
	if part then b.tier:SetColorTexture(Tier(part)) else b.tier:SetColorTexture(1, 1, 1, shown and 0.25 or 0.08) end
	b.score:SetText(worth and (Fmt(worth) .. (part and (" |cff888888%d%%|r"):format(math.floor(part * 100 + 0.5)) or "")) or "")
	-- (a green mark: the recommended set has another piece here)
	b.name:SetText((not s.foreign and bis and bis ~= cur and "|cff40ff40>|r " or "") .. (B.Locks()[r] and LOCKED or "") .. (shown and Name(shown) or "|cff666666nothing worn|r"))
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
			or (B.Left() or 1) > 0 and "|cff888888Loading items...|r" or "|cff888888No gear found for this spec yet|r")
	elseif s.bis and s.bis.score > 0 then
		local part = s.curScore / s.bis.score
		gear.progress:Set(part, part >= 0.995 and "met" or "gold", ("%d%% of the recommended set%s"):format(math.floor(part * 100 + 0.5), s.list and "" or "  |cff888888(no pre-raid list yet)|r"))
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
	-- the right: the slot clicked, every item for it (the recommended one marked), what I wear among them
	local x, rw = LEFT_W + 10, w - LEFT_W - 24
	local phase = B.Phase()
	gear.head:ClearAllPoints()
	gear.head:SetPoint("TOPLEFT", x, -top)
	local nlock = 0
	for _ in pairs(B.Locks()) do nlock = nlock + 1 end
	gear.head:SetText(ROWS[picked][1] .. (nlock > 0 and (" |cff888888(%d locked)|r"):format(nlock) or ""))
	gear.redo:ClearAllPoints()
	gear.redo:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -top)
	gear.redo:SetShown(not s.foreign)
	local left = B.Left()
	local ready = left ~= nil
	gear.note:SetText(B.err and ("|cffff4040Could not work out the sets: %s|r"):format(B.err:sub(1, 200)) or not ready and "reading the item list..." or left > 0 and ("%d items still to load, the best so far are shown..."):format(left)
		or ("level %d, %s%s%s"):format(s.who.level, s.who.className, phase and (", " .. phase[2]:lower()) or "", s.at and (", worked out %s ago"):format(Ago(s.at)) or ""))
	-- the columns: icon, name, then right-aligned numbers (weight, difference, percent), the source
	local P = { icon = 2, name = 20, namew = 170, wt = 194, wtw = 44, diff = 242, diffw = 48, pct = 294, pctw = 50, kind = 352 }
	P.wherew = math.max(40, rw - P.kind)
	local hy = top + 22 -- (the column titles, one line above the rows)
	local titles = { { P.wt, "weight", P.wtw }, { P.diff, s.foreign and "" or "vs worn", P.diffw }, { P.pct, s.foreign and "" or "%", P.pctw },
		{ P.kind, "source", P.wherew }, { P.name, "item", P.namew } }
	for c, col in ipairs(gear.cols) do
		local t = titles[c]
		col:ClearAllPoints()
		if t then
			col:SetPoint("TOPLEFT", x + t[1], -hy)
			col:SetWidth(t[3])
		end
		col:SetText(t and t[2] or "")
	end
	local ry = hy + 16
	-- what there is to show, as lines: { head = a note } or { c = an item row }; then those that fit
	local rows = {}
	local function Add(head, c) rows[#rows + 1] = { head = head, c = c } end
	local rec = {} -- (the recommended set's pieces)
	for _, id in pairs(s.bis and s.bis.rows or {}) do rec[id] = true end
	local rank = ready and B.Rank(picked, 500, s.foreign and 0 or BELOW) or nil
	if rank then
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
			local worn = c and c.worn
			l.band:SetShown(worn and true or false)
			l.rule1:SetShown(worn and true or false)
			l.rule2:SetShown(worn and true or false)
			At(l.head, 4, rw - 8, row and row.head or "")
			local it = c and B.Item(c.id)
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
			l.item.quest, l.item.note = c and c.kind == "quest" and B.quests[c.id] or nil, where
			local lrow = not s.foreign and c and picked or nil
			l.item.locked = lrow and B.Locks()[lrow] == c.id or nil
			l.item.lock = lrow and function() B.Lock(lrow, c.id) end or nil
			-- (marks: locked here, and a piece of the recommended set)
			if c then l.item.text:SetText((l.item.locked and LOCKED or "") .. (rec[c.id] and REC or "") .. Name(c.id)) end
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
	up.redo:SetScript("OnClick", function() B.AskRecalc() end)
	up.heads = {}
	for c in ipairs(UPCOLS) do up.heads[c] = Text(f, "GameFontNormalSmall", UPCOLS[c][3]) end
end

local function DrawUp(f, s)
	local list = Filtered(s)
	local fit = math.max(1, math.floor((f:GetHeight() - 42) / ROW_H))
	offset = math.max(0, math.min(offset, math.max(0, #list - fit)))
	local left = 0
	local name = up.filter:sub(1, 2) == "d:" and up.filter:sub(3)
	for _, e in ipairs(FILTERS) do if e[1] == up.filter then name = e[2] end end
	up.pick.label:SetText(name or "All sources")
	local text = (s.foreign and "|cff888888Another class's spec: there is nothing of yours to upgrade.|r"
		or (B.Left() or 1) > 0 and ("|cff888888Loading the items there are: %s more to go. The list grows as they come.|r"):format(B.Left() or "the item list and")
		or not s.all and "|cff888888No gear found for this spec yet. The tooltip line still says what an item would gain over the gear you own.|r"
		or #s.upg == 0 and "|cff40ff40Nothing found would improve your best set.|r"
		or up.filter ~= "all" and (#list == 0 and ("|cffff8040None of the %d upgrades is from %s.|r"):format(#s.upg, name)
			or ("%d of the %d upgrades from %s, the biggest gain first."):format(#list, #s.upg, name))
		or ("%d would improve your best set, the biggest gain first. |cff888888A gain is in score, and in percent of the best set %s.|r"):format(#s.upg, s.list and "of the pre-raid list" or "found"))
	if s.at and B.Left() == 0 and not s.foreign then
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

-- (a weight as it is, to three places: 0.01 must not show as 0, or Enter in its box would make it 0)
local function Fine(n) return ("%g"):format(math.floor(n * 1000 + 0.5) / 1000) end
local function DrawWeights(_, s)
	local raw = s.prof.raw
	local edit = B.db.edit[raw.id]
	local edited = edit and (next(edit.w or {}) or next(edit.caps or {})) and "  |cffff8040(changed by you)|r" or ""
	-- (three lines, none wrapped: the rows begin right under them)
	weights.note:SetText(("|cffffd100%s %s|r%s  |cff888888client %s|r\n|cff888888Per 1%%: hit, crit, haste, expertise, dodge, parry, block; the rest per point. A cap is the sheet's total. Buffs: what consumables and buffs give at level 60. Enter takes a change, an empty box the default.|r\n|cff888888%s|r")
		:format(ClassName(raw.class), raw.title, edited, DT.BisBuild or "?", raw.note or ""))
	for word, row in pairs(weights.rows) do
		local cap = s.prof.caps[word]
		if not row.w:HasFocus() then row.w:SetText(s.prof.w[word] and Fine(s.prof.w[word]) or "") end
		if not row.cap:HasFocus() then row.cap:SetText(cap and Fine(cap.cap) or "") end
		if not row.over:HasFocus() then row.over:SetText(cap and Fine(cap.over or 0) or "") end
		if not row.buff:HasFocus() then row.buff:SetText(cap and cap.buff and Fine(cap.buff) or "") end
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

-- the enchants and consumables counted at the last level
local EXTRA_ORDER = { "Back", "Chest", "Wrist", "Hands", "Feet", "Weapon", "Shield",
	"flask", "agility", "strength", "attack", "armor", "health", "spell", "shadow", "fire", "frost", "intellect", "mana", "drink", "scroll", "food" }
local EXTRA_LABEL = { flask = "Flask", agility = "Agility elixir", strength = "Strength", attack = "Attack power", armor = "Armor elixir",
	health = "Health elixir", spell = "Spell damage", shadow = "Shadow damage", fire = "Fire damage", frost = "Frost damage",
	intellect = "Intellect elixir", mana = "Mana", drink = "Drink", scroll = "Blasted Lands", food = "Food" }
function B.ExtrasText(s)
	if s.who.level < B.MAX_LEVEL then return ("|cff888888Enchants and consumables are counted at level %d only.|r"):format(B.MAX_LEVEL) end
	local x = s.extras or {}
	local lines = { "|cffffd100Enchants and consumables|r  |cff888888The best of each by this spec's weights, as the game words them. What they give hit, defense and the other caps counts toward those; the sets are chosen with it.|r", " " }
	local head
	for _, g in ipairs(EXTRA_ORDER) do
		local e = x[g]
		if e then
			local enchant = e.spell
			if head ~= (enchant and 1 or 2) then
				head = enchant and 1 or 2
				lines[#lines + 1] = enchant and "|cffffd100Enchants|r" or " \n|cffffd100Consumables|r"
			end
			lines[#lines + 1] = ("|cffaaaaaa%s|r  %s  %s"):format(EXTRA_LABEL[g] or g, e.name, B.StatText(e.s))
		end
	end
	if not next(x) then lines[#lines + 1] = "|cff888888Nothing read yet: the game is still loading them.|r" end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- The bar on top, and the whole
---------------------------------------------------------------------------

local BUILD = { gear = BuildGear, up = BuildUp, weights = BuildWeights, check = BuildCheck, extras = function(f)
	check.extras = Text(f)
	check.extras:SetPoint("TOPLEFT", 8, -4)
	check.extras:SetWordWrap(true)
	check.extras:SetSpacing(2)
end }
local DRAW = { gear = DrawGear, up = DrawUp, weights = DrawWeights, check = function(f, s)
	check.text:SetWidth(f:GetWidth() - 16)
	check.text:SetText(B.CheckText(s))
end, extras = function(f, s)
	check.extras:SetWidth(f:GetWidth() - 16)
	check.extras:SetText(B.ExtrasText(s))
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
	status:SetText(not s and (B.err and ("|cffff4040Could not work out the sets: %s|r"):format(B.err:sub(1, 200)) or B.Working() and "|cff888888Working out the sets...|r" or "|cff888888Worked out once the fight is over.|r")
		or B.Working() and "|cff888888Working out the sets...|r"
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
	local nextUpdate = 0
	DT.OnUpdate(panel, "tab: BiS", function()
		if held and GetTime() >= held.at then -- (a button of the level held down: it goes on)
			held.at, fired = GetTime() + 0.07, true
			Step(held.d)
		end
		if not (dirty or B.redraw) or GetTime() < nextUpdate or Fight() then return end
		nextUpdate = GetTime() + 0.5
		Refresh()
	end)
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

DT:RegisterModule("bis", {
	title = "BiS",
	version = 1,
	slash = "/dtbis",
	defaults = { tooltip = true, roll = true, realistic = true },
	settings = {
		{ key = "tooltip", label = "BiS: what an item would gain over what I wear (DT: BiS)", tooltip = true },
		{ key = "roll", label = "When an item is rolled for: the same, as a line in the chat" },
		{ key = "realistic", label = "BiS realistic: leave out gear that needs a reputation standing I do not have yet" },
	},
	tab = { id = "bis", title = "BiS", defaultOrder = 61, group = 2, create = Build, onShow = Refresh },
	onEnable = function(mod)
		B.db, B.me = mod.db, UnitGUID("player")
		B.Upgrade(B.db)
		-- (what the game never answered: asked again in a new build of the game)
		local build = GetBuildInfo and table.concat({ GetBuildInfo() }, " ", 1, 2) or ""
		if type(B.db.never) ~= "table" or B.db.never.build ~= build then B.db.never = { build = build } end
		for _, key in ipairs({ "pick", "edit", "base", "last", "facts", "level", "phase", "seen", "saved", "locks" }) do
			if type(B.db[key]) ~= "table" then B.db[key] = {} end
		end
		B.db.kept = nil -- (the lists an older finder kept: the loader has no need of them)
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
		-- (an enchant or consumable asked of the game: worked out anew once it came, not when the game had none)
		DT:On("SPELL_DATA_LOAD_RESULT", function(id, ok) if B.extraWait[id] and ok then B.extraWait[id] = nil Stale() end end)
		DT:On("GET_ITEM_INFO_RECEIVED", function(id, ok)
			if B.extraWait[id] then
				if ok ~= false and ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id) then B.extraWait[id] = nil Stale() end
				return
			end
			if not asked[id] or items[id] ~= nil then return end
			if state and (state.have[id] or (state.list and state.list[id])) then Stale() end -- (the rest: the loader's, a few seconds on)
		end)
		DT:On("START_LOOT_ROLL", function(rollID) B.OnRoll(rollID) end)
		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(...) DT.Timed("tooltip: BiS", B.OnTooltip, ...) end)
		elseif GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetItem") then
			GameTooltip:HookScript("OnTooltipSetItem", B.OnTooltip)
			ItemRefTooltip:HookScript("OnTooltipSetItem", B.OnTooltip)
		end
	end,
	selfTest = function(_, Try)
		Try("bis", function() B.Compute() end)
	end,
})
