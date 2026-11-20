-- DawnTools :: BiS
-- The best gear for a spec: of what I own, and of a list of pre-raid gear. Local only: nothing is sent.
--   What an item gives is read from the game (GetItemStats and its tooltip's lines), once per item a session.
--   What I am without gear = the character sheet less what the gear I wear gives: talents and racials are in
--     it without being known one by one. Enchants are in it too (an item's stats are those of the bare item).
--   A profile says what a point of each stat is worth and where its caps are; its weights and caps can be
--     changed on the Weights view (kept per profile). The profiles are NOT in the addon: their numbers are
--     from two websites and not cleared for passing on (THIRD_PARTY_LICENSES.txt), so they lie in the seed
--     addon beside it (DawnTools_Seed/BisProfiles.lua, made by tools/bisweights.js), on its keeper's
--     machine only, and are not passed to the guild. Without them there is no BiS tab.
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
if type(DawnToolsSeed) == "table" then
	DT.BisProfiles, DT.BisBuild = DT.BisProfiles or DawnToolsSeed.BisProfiles, DT.BisBuild or DawnToolsSeed.BisBuild
end

local LABEL = {
	str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", armor = "Armor",
	dps = "Weapon DPS", ap = "Attack power", rap = "Ranged attack power", fap = "Feral attack power",
	def = "Defense", dodge = "Dodge %", parry = "Parry %", block = "Block %", bv = "Block value",
	hit = "Hit %", exp = "Expertise %", crit = "Crit %", haste = "Haste %", arp = "Armor penetration",
	shit = "Spell hit %", scrit = "Spell crit %", sp = "Spell power", heal = "Healing", mp5 = "Mana per 5",
	spen = "Spell penetration", sp_shadow = "Shadow damage", sp_fire = "Fire damage", sp_frost = "Frost damage",
	sp_arcane = "Arcane damage", sp_nature = "Nature damage", sp_holy = "Holy damage",
}
local ORDER = { "sta", "armor", "def", "dodge", "parry", "block", "bv", "str", "agi", "ap", "rap", "fap", "dps", "hit", "exp", "crit",
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
local FACTS = 1 -- (the shape of what is kept in db.facts: raise it when BL.Stats counts something else, and every item is learned anew)
local ASKS, GAP = 6, 4 -- (an item is asked of the game this many times, this many seconds apart, then left alone)
local function Now() return GetTime and GetTime() or 0 end
local CLASSES = (ITEM_CLASSES_ALLOWED or "Classes: %s"):match("^(.-)%%s") or "Classes: "

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
function B.Item(id)
	local it = items[id]
	if it ~= nil then return it end
	if partial[id] then return partial[id] end
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
	for _, text in ipairs(lines or {}) do
		if text:sub(1, #CLASSES) == CLASSES then it.only = text:sub(#CLASSES + 1) end
		if text == (ITEM_BIND_ON_EQUIP or "Binds when equipped") then it.boe = true end
	end
	-- (kept only with its tooltip: without, the stats its text gives are missing, and the next look may find them)
	if lines then
		items[id] = it
		if B.db and B.db.facts then B.db.facts[id] = it end
	else
		partial[id] = it
	end
	return it
end

-- the game will not tell of this item: asked for as often as we do, the last time a while ago
function B.Gone(id)
	return (asked[id] or 0) >= ASKS and Now() - (askedAt[id] or 0) >= GAP
end

-- may this character wear it (level aside when "later" is set: gear to grow into)
local function Usable(it, who, later)
	if not later and it.lvl > who.level then return false end
	if it.only and not it.only:find(who.className, 1, true) then return false end
	local V = DT.Market and DT.Market.View
	if V and V.MayUse and it.class then
		local ok, may = pcall(V.MayUse, it.class, it.sub, who.who)
		if ok and may == false then return false end
	end
	return true
end

local function Who()
	local V = DT.Market and DT.Market.View
	local ok, who = pcall(function() return V and V.Character and V.Character(Level()) end)
	local name = UnitClass and UnitClass("player") or ""
	return { level = Level(), className = name, who = ok and who or nil }
end

-- Who gear is looked for: me, or for the spec of another class its own at the last level (what it may wear
-- by Classic's rules: the game says nothing of what another class has trained).
local function Target()
	local class = B.Raw().class
	if class == B.MyClass() then return class, Who() end
	return class, { level = B.MAX_LEVEL, className = ClassName(class), who = { me = class, level = B.MAX_LEVEL, trained = false } }
end

-- The gear there is to get, found by Sift below: what to look at, what was kept, where each is from. Looked at
-- anew with a level gained, another class picked, and once the item list has been read.
local finder = { todo = {}, got = {}, kind = {}, tries = {}, gone = 0 }
local POOL = 6 -- (of the gear found, the best this many for each place to wear go into the best set: it must stay quick to work out)
local function FinderKey()
	local Item = DT.Item
	local class, who = Target()
	return ("%d:%s:%s:%s"):format(who.level, class, tostring(Item and Item.Ready and Item.Ready() or false), tostring(DT.Dungeon ~= nil))
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

-- the profile picked, of any class; to begin with the first of my own
function B.Raw()
	local want, mine = B.db.pick[B.me], B.MyClass()
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
	local p = { id = raw.id, title = raw.title, hands = hands, w = {}, caps = {}, raw = raw }
	for word, n in pairs(raw.w) do p.w[word] = n end
	-- The caps are those of the last level. Below it the defense cap is lower, five a level (it is what a boss
	-- three levels up asks for: 440 at 60), and it is not yet a thing to reach before all else.
	local below = math.max(0, B.MAX_LEVEL - Level())
	for word, cap in pairs(raw.caps) do
		p.caps[word] = { cap = cap.cap - (word == "def" and below * 5 or 0), over = cap.over, hard = cap.hard and below == 0 or nil }
	end
	for word, n in pairs(edit.w or {}) do p.w[word] = n end
	for word, cap in pairs(edit.caps or {}) do
		if cap == false then
			p.caps[word] = nil
		else
			local at = p.caps[word] or { over = 0 }
			at.cap, at.over = cap.cap or at.cap, cap.over or at.over
			p.caps[word] = at.cap and at or nil
		end
	end
	for word in pairs(p.caps) do p.w[word] = p.w[word] or 0 end
	resolved = p
	return p
end

local dirty, state, gains = true, nil, {}
local waiting
local function Stale()
	dirty = true
	if B.Refresh and B.panel and B.panel:IsShown() then B.redraw = true end
	if not waiting and C_Timer and C_Timer.After then
		waiting = true
		C_Timer.After(1.5, function()
			waiting = nil
			if dirty and B.db then B.State() end
		end)
	end
end
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
	local want, first = B.db.last[class], nil
	for _, p in ipairs(DT.BisProfiles or {}) do
		if p.class == class and (not first or p.id == want) then first = p.id end
	end
	if first then B.Pick(first) end
end

-- A weight or a cap changed by hand: field "w", "cap" or "over"; value nil puts the profile's own back.
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

local function Num(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok or type(a) ~= "number" or (issecretvalue and issecretvalue(a)) then return nil end
	return a, type(b) == "number" and b or nil
end

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
	for r, row in ipairs(ROWS) do
		local id = GetInventoryItemID and GetInventoryItemID("player", row[4])
		if type(id) == "number" then
			cur[r] = id
			local it = B.Item(id)
			if it == nil then whole = false elseif it then BL.Add(gear, it.s) end
		end
	end
	return cur, whole and gear or nil
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

local function Solve(list, s)
	local slots = BL.Choices(list, s.prof)
	local picks, gear, score, short = BL.Solve(slots, s.base, s.prof)
	return { picks = picks, gear = gear, score = score, short = short }
end

local worker = CreateFrame("Frame")
worker:Hide()

-- Everything worked out anew: what I wear, the best of what I own, the best of the list. False in a fight.
function B.Compute()
	if Fight() then return false end
	local prof = B.Profile()
	if not prof then return false end
	local s = { prof = prof, have = {}, own = {}, pending = 0, rank = {} }
	s.who = select(2, Target())
	-- (a spec of another class looked at: my gear is not its gear, so only its list and weights are shown)
	s.foreign = prof.raw.class ~= B.MyClass()
	local gear
	s.cur, gear = Worn()
	if s.foreign then s.cur, gear = {}, {} end
	s.base = (not s.foreign and Base(gear)) or { def = Level() * 5 }
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
			s.own[#s.own + 1] = { id = id, loc = it.loc, s = it.s, n = n }
		end
	end
	table.sort(s.own, function(a, b) return a.id < b.id end)
	s.best = Solve(s.own, s)
	s.best.rows = Lay(s.best.picks, s.cur)
	s.best.has = {}
	for _, id in pairs(s.best.rows) do s.best.has[id] = true end
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
		elseif it and Usable(it, s.who, true) then
			Add(id, it)
		end
	end
	finder.used = finder.key == FinderKey() and #finder.got or nil
	for _, c in ipairs(finder.used and finder.got or {}) do
		local it = not seen[c.id] and B.Item(c.id)
		if it then
			found[it.loc] = found[it.loc] or {}
			table.insert(found[it.loc], { id = c.id, it = it, v = (BL.Score(it.s, {}, prof)) })
		end
	end
	for _, list in pairs(found) do
		table.sort(list, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.id < b.id end)
		for i = 1, math.min(#list, POOL) do Add(list[i].id, list[i].it) end
	end
	if #all > 0 then
		table.sort(all, function(a, b) return a.id < b.id end)
		table.sort(s.queue)
		s.all = all
		s.bis = Solve(all, s)
		s.bis.rows = Lay(s.bis.picks, s.cur)
	end
	state, dirty, gains = s, false, {}
	worker:SetShown(#s.queue > 0)
	return true
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
	local id = table.remove(s.queue)
	local g = B.Gain(id)
	if g and g.up then s.upg[#s.upg + 1] = { id = id, g = g } end
	if #s.queue == 0 then
		table.sort(s.upg, function(a, b)
			if (#a.g.reach > 0) ~= (#b.g.reach > 0) then return #a.g.reach > 0 end
			if a.g.d ~= b.g.d then return a.g.d > b.g.d end
			return a.id < b.id
		end)
		for i, u in ipairs(s.upg) do s.rank[u.id] = i end
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
	local s = state or B.State()
	if not s or s.foreign then return end -- (another class looked at: nothing to say of my gear)
	local g = B.Gain(id, true)
	if not g or g.no then return end -- (not for my class: said nothing, as the game's own red lines say it)
	local rank = s.rank[id] and ("  |cffffd100#%d upgrade|r"):format(s.rank[id]) or ""
	tip:AddDoubleLine("BiS  |cff888888" .. s.prof.title .. "|r", B.GainText(g) .. rank, 0.78, 0.68, 0.37, 1, 1, 1)
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

local function Bar(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:SetHeight(16)
	b.back = b:CreateTexture(nil, "BACKGROUND")
	b.back:SetAllPoints()
	b.back:SetColorTexture(1, 1, 1, 0.08)
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetPoint("TOPLEFT", 0, 0)
	b.fill:SetHeight(16)
	b.text = Text(b, "GameFontHighlightSmall", "CENTER")
	b.text:SetAllPoints()
	-- part: 0 to 1; good: reached (green), else gold
	function b:Set(part, good, text)
		part = math.max(0, math.min(1, part))
		self.fill:SetWidth(math.max(1, (self.width or self:GetWidth()) * part)) -- (width: said by who lays it out, before the game has)
		self.fill:SetShown(part > 0)
		if good then self.fill:SetColorTexture(0.2, 0.7, 0.3, 0.8) else self.fill:SetColorTexture(0.78, 0.68, 0.37, 0.7) end
		self.text:SetText(text)
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

---------------------------------------------------------------------------
-- What there is to get: quest rewards, dungeon drops, crafted and world-drop gear of about my level
---------------------------------------------------------------------------
-- Which items there are is not DawnTools' own: read at runtime from QuestieDB as the Items tab reads it (quest
-- rewards, drops), from the dungeon list (Modules/Dungeon.lua) and the recipes (DT.Recipes: from the store, Core/DBSeed.lua). What each
-- gives is asked of the game, a batch a pass, and rated with the profile in use.
-- ponytail: gear asking for a level up to WINDOW below mine (the game is asked for every one of them once a
-- session); a quest reward counts whichever side gives the quest.

local WINDOW, TOP_N = 15, 5
local function Cap(type) return type < 300 and 60 or type < 402 and 150 or 100 end -- (asked of the game for a weapon type, for rings, necks, trinkets and cloaks, for an armor type)
local KINDS = { { "quest", "Quest rewards" }, { "dungeon", "Dungeon drops" }, { "crafted", "Crafted" }, { "boe", "World drops (bind on equip)" }, { "vendor", "Vendors" } }
local RANK = { dungeon = 5, quest = 4, crafted = 3, boe = 2, vendor = 1 } -- (an item of two kinds is listed under the higher)
B.finder, B.KINDS = finder, KINDS

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
	local lo = level - WINDOW
	local V = DT.Market and DT.Market.View
	local drops, Dg = {}, DT.Dungeon
	for _, d in ipairs(Dg and Dg.All and Dg.All() or {}) do
		if (d.lo or 0) <= level and (d.hi or 99) >= lo then
			for _, boss in ipairs(d.bosses) do
				for id in pairs(boss.has) do drops[id] = true end
			end
		end
	end
	-- what the item list says without the game loading anything: gear, of a kind the class may use, of a level that suits
	local want, seen = {}, {}
	for _, e in ipairs(Item and Item.All and Item.All() or {}) do
		local boss = drops[e.id]
		if boss then seen[e.id] = true end
		-- (no level asked for: many a ring and cloak; its level is seen once the game has loaded it)
		if (e.c == 2 or e.c == 4) and e.req <= level and (boss or e.req == 0 or e.req >= lo) then
			local ok, may = pcall(function() return not (V and V.MayUse) or V.MayUse(e.c, e.s, who.who) end)
			if not ok or may ~= false then
				local kind = boss and "dungeon" or e.src["Quest reward"] and "quest" or ((DT.CraftSkill and DT.CraftSkill[e.id]) or e.src.Crafted) and "crafted"
					or e.src.Drop and "boe" or e.src.Vendor and "vendor" or nil
				if kind then
					finder.kind[e.id] = kind
					want[#want + 1] = { id = e.id, ilvl = e.ilvl or 0, type = e.c * 100 + e.s }
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
	local types = {}
	for _, w in ipairs(want) do
		types[w.type] = types[w.type] or {}
		table.insert(types[w.type], w)
	end
	local kept = {}
	for kind, list in pairs(types) do
		table.sort(list, function(a, b) if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end return a.id < b.id end)
		for i, w in ipairs(list) do
			if kind == 0 or i <= Cap(kind) then w.rank, kept[#kept + 1] = kind == 0 and 0 or i, w else finder.kind[w.id] = nil end
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

-- a batch of them asked of the game; what is gear the class may wear is kept. Once all are looked at, what was
-- found goes into the best set (and its upgrades).
local function Sift()
	if Fight() or not Gather() or #finder.todo == 0 then return end
	-- (at most 300 looked at a pass, and no more than 40 of them asked of the server; the best prospects come first)
	local who = finder.who
	local keep, later, done, unloaded = {}, {}, 0, 0
	for _, id in ipairs(finder.todo) do
		if done >= 300 or unloaded >= 40 then
			keep[#keep + 1] = id
		else
			done = done + 1
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
	if #finder.got ~= finder.used and (#keep == 0 or Now() - (finder.shown or 0) >= 3) then
		finder.shown = Now()
		Stale()
	end
end
B.Sift = Sift

-- The best of a kind for a row: { id, worth = what it would add in the place of what is worn there, gain =
-- that less what the worn one adds }, the most first.
function B.Top(r, kind, n)
	local s, out = state, {}
	if not s then return out end
	local worn, on = s.cur[r], {}
	for _, id in pairs(s.cur) do on[id] = true end -- (a ring on the other finger is not one to get)
	local base = Worth(s, s.curGear, worn, worn) or 0
	for _, c in ipairs(finder.got) do
		if c.kind == kind and not on[c.id] and Fits(r, c.loc, s.prof) then
			local worth = Worth(s, s.curGear, c.id, worn) or 0
			out[#out + 1] = { id = c.id, worth = worth, gain = worth - base }
		end
	end
	table.sort(out, function(a, b)
		if a.worth ~= b.worth then return a.worth > b.worth end
		return a.id < b.id
	end)
	for i = #out, (n or TOP_N) + 1, -1 do out[i] = nil end
	return out
end

-- where one of them is from, in a few words
B.wheres, B.quests = {}, {} -- (quests: [item] = the quest that gives it, for a click on its line)
function B.Where(id, kind)
	local wheres = B.wheres
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
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(1, 0.82, 0, 0.14)
	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.06)
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
		picked = self.row
		B.Refresh()
	end)
	return b
end

-- a line of the right side: a heading, or an item with its level, worth, gain over the worn one, and source
local function Line(f)
	local l = { head = Text(f, "GameFontNormalSmall"), n = Text(f, nil, "RIGHT"), icon = f:CreateTexture(nil, "ARTWORK"), item = ItemCell(f),
		lvl = Text(f, nil, "RIGHT"), worth = Text(f, nil, "RIGHT"), gain = Text(f, nil, "RIGHT"), from = Text(f) }
	l.icon:SetSize(12, 12)
	return l
end

local function BuildGear(f)
	gear.progress = Bar(f)
	gear.progress:SetPoint("TOPLEFT", 6, -2)
	gear.progress:SetWidth(LEFT_W - 6)
	for i = 1, 4 do gear.caps[i] = Bar(f) end
	gear.stats = Text(f)
	gear.stats:SetPoint("TOPLEFT", 6, -22)
	gear.stats:SetPoint("TOPRIGHT", -6, -22)
	for r = 1, #ROWS do gear.slots[r] = Slot(f, r) end
	-- the right side: of the slot clicked, what I own and the list's pick, then the best of each kind
	gear.head = Text(f, "GameFontNormal")
	gear.note = Text(f, "GameFontDisableSmall")
	gear.ownLabel, gear.own = Text(f, "GameFontDisableSmall"), ItemCell(f)
	gear.listLabel, gear.list = Text(f, "GameFontDisableSmall"), ItemCell(f)
	gear.cols = { Text(f, "GameFontDisableSmall", "RIGHT"), Text(f, "GameFontDisableSmall", "RIGHT"), Text(f, "GameFontDisableSmall", "RIGHT") }
	for i = 1, #KINDS * (TOP_N + 1) do gear.lines[i] = Line(f) end
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

local function DrawGear(f, s)
	local w, h = f:GetWidth(), f:GetHeight()
	if w < LEFT_W + 120 then return end -- (not laid out yet)
	-- along the top: how far along, the caps, the stats that count
	gear.progress.width = LEFT_W - 6
	if s.foreign then
		gear.progress:Set(0, false, s.bis and ("%s: %s"):format(s.list and "Best pre-raid set" or "Best set found", Fmt(s.bis.score))
			or #finder.todo > 0 and "|cff888888Looking for gear...|r" or "|cff888888No gear found for this spec yet|r")
	elseif s.bis and s.bis.score > 0 then
		local part = s.curScore / s.bis.score
		gear.progress:Set(part, part >= 0.995, ("%d%% of the best %s"):format(math.floor(part * 100 + 0.5), s.list and "pre-raid set" or "set found"))
	else
		local part = s.best.score > 0 and s.curScore / s.best.score or 0
		gear.progress:Set(part, part >= 0.995, ("%d%% of the best I own  |cff888888(no pre-raid list yet)|r"):format(math.floor(part * 100 + 0.5)))
	end
	local words = {}
	for word in pairs(s.prof.caps) do words[#words + 1] = word end
	table.sort(words)
	local n = math.min(#words, #gear.caps)
	local capW = n > 0 and (w - LEFT_W - 12) / n or 0
	local set = s.foreign and s.bis and s.bis.gear or s.curGear
	for i, bar in ipairs(gear.caps) do
		local word = words[i]
		bar:SetShown(i <= n)
		if i <= n then
			local cap = s.prof.caps[word]
			local now, best = (s.base[word] or 0) + (set[word] or 0), (s.base[word] or 0) + (s.best.gear[word] or 0)
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", LEFT_W + 6 + (i - 1) * capW, -2)
			bar:SetWidth(capW - 4)
			bar.width = capW - 4
			bar:Set(cap.cap > 0 and now / cap.cap or 0, now >= cap.cap - 1e-9, ("%s %s / %s%s"):format(LABEL[word] or word, Fmt(now), Fmt(cap.cap),
				not s.foreign and math.abs(best - now) > 0.05 and ("  |cff888888(owned: %s)|r"):format(Fmt(best)) or ""))
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
	-- the right: the slot clicked
	local x, rw = LEFT_W + 10, w - LEFT_W - 16
	local cur, best, bis = s.cur[picked], s.best.rows[picked], s.bis and s.bis.rows[picked]
	gear.head:ClearAllPoints()
	gear.head:SetPoint("TOPLEFT", x, -top)
	gear.head:SetText(ROWS[picked][1])
	local function Pick(label, cell, at, title, id, mark)
		label:ClearAllPoints()
		label:SetPoint("TOPLEFT", x + at, -top - 2)
		label:SetText(title)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", x + at + label:GetStringWidth() + 4, -top + 2)
		cell:SetWidth(math.max(60, rw * 0.36 - label:GetStringWidth()))
		cell.id = id or nil
		cell.text:SetText(id and (mark .. Name(id)) or "|cff555555-|r")
	end
	Pick(gear.ownLabel, gear.own, 76, "Best I own", not s.foreign and best or nil, best == cur and "|cff555555=|r " or "|cff40ff40>|r ")
	Pick(gear.listLabel, gear.list, 76 + rw * 0.4, "Pre-raid list", bis, bis and s.have[bis] and "|cff40ff40+|r " or "")
	local ready = not s.foreign and Gather()
	local left = #finder.todo
	gear.note:ClearAllPoints()
	gear.note:SetPoint("TOPLEFT", x, -top - 16)
	gear.note:SetWidth(204)
	gear.note:SetText(s.foreign and "" or not ready and "reading the item list..." or left > 0 and ("%d items still to look at, the best so far are shown..."):format(left)
		or ("levels %d-%d, %s"):format(math.max(1, s.who.level - WINDOW), s.who.level, s.who.className))
	local lineH = math.max(10.5, math.min(18, (h - top - 30) / #gear.lines))
	local fromW = math.max(60, rw - 20 - 190 - 30 - 46 - 52 - 8)
	local cx = { x + 20 + 190, x + 20 + 190 + 30, x + 20 + 190 + 30 + 46 } -- level, worth, gain
	for c, title in ipairs({ "lvl", "worth", "vs worn" }) do
		gear.cols[c]:ClearAllPoints()
		gear.cols[c]:SetPoint("TOPLEFT", cx[c], -top - 16)
		gear.cols[c]:SetWidth(({ 28, 44, 50 })[c])
		gear.cols[c]:SetText(s.foreign and "" or title)
	end
	local i = 0
	local function Put(head, c, rank, kind)
		i = i + 1
		local l = gear.lines[i]
		local y = -top - 28 - (i - 1) * lineH
		local function At(fs, at, width, text)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", at, y - (fs == l.item and 0 or 1))
			fs:SetWidth(width)
			if fs == l.item then fs.text:SetText(text) else fs:SetText(text) end
		end
		local it = c and B.Item(c.id)
		At(l.head, x, rw, head or "")
		At(l.n, x, 14, c and ("|cff888888%d|r"):format(rank) or "")
		l.icon:ClearAllPoints()
		l.icon:SetPoint("TOPLEFT", x + 18, y - 1)
		l.icon:SetTexture(it and it.icon or nil)
		l.icon:SetShown(c and true or false)
		l.item:SetHeight(lineH)
		l.item.id = c and c.id or nil
		l.item:SetShown(c and true or false)
		At(l.item, x + 34, 172, c and Name(c.id) or "")
		At(l.lvl, cx[1], 28, it and tostring(it.lvl) or "")
		At(l.worth, cx[2], 44, c and Fmt(c.worth) or "")
		At(l.gain, cx[3], 50, not c and "" or c.gain > 0.05 and ("|cff40ff40%+.1f|r"):format(c.gain) or c.gain < -0.05 and ("|cffff6060%+.1f|r"):format(c.gain) or "|cff8888880|r")
		local where = c and B.Where(c.id, kind) or ""
		At(l.from, cx[3] + 58, fromW, where)
		l.item.quest, l.item.note = c and kind == "quest" and B.quests[c.id] or nil, where
	end
	for _, kind in ipairs(KINDS) do
		local list = ready and B.Top(picked, kind[1], TOP_N) or {}
		Put(("|cffffd100%s|r%s"):format(kind[2], s.foreign and "" or ready and #list == 0 and "  |cff888888nothing for this slot|r" or ""))
		for rank = 1, TOP_N do
			if list[rank] then Put(nil, list[rank], rank, kind[1]) else Put() end
		end
	end
end

---------------------------------------------------------------------------
-- Upgrades, Weights, Check
---------------------------------------------------------------------------

-- Upgrades: the list's items I do not own, the one that gains the most first
local up = { rows = {} }
B.up = up
local function BuildUp(f)
	up.note = Text(f)
	up.note:SetPoint("TOPLEFT", 8, -4)
	up.note:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -4)
end

local function DrawUp(f, s)
	local fit = math.max(1, math.floor((f:GetHeight() - 24) / ROW_H))
	offset = math.max(0, math.min(offset, math.max(0, #s.upg - fit)))
	local left = #s.queue
	up.note:SetText(s.foreign and "|cff888888Another class's spec: there is nothing of yours to upgrade.|r"
		or #finder.todo > 0 and ("|cff888888Looking through the gear there is for this spec: %d more to go...|r"):format(#finder.todo)
		or left > 0 and ("|cff888888Working out %d more...|r"):format(left)
		or not s.all and "|cff888888No gear found for this spec yet. The tooltip line still says what an item would gain over the gear you own.|r"
		or #s.upg == 0 and "|cff40ff40Nothing found would improve your best set.|r"
		or ("%d would improve your best set, the biggest gain first. |cff888888A gain is in score, and in percent of the best set %s.|r"):format(#s.upg, s.list and "of the pre-raid list" or "found"))
	for i = 1, math.max(fit, #up.rows) do
		local u = i <= fit and left == 0 and not s.foreign and s.upg[offset + i]
		local row = up.rows[i]
		if u and not row then
			row = { n = Text(f, nil, "RIGHT"), icon = f:CreateTexture(nil, "ARTWORK"), item = ItemCell(f), gain = Text(f), from = Text(f) }
			local y = -22 - (i - 1) * ROW_H
			row.n:SetPoint("TOPLEFT", 4, y - 3)
			row.n:SetWidth(24)
			row.icon:SetSize(16, 16)
			row.icon:SetPoint("TOPLEFT", 34, y - 1)
			row.item:SetPoint("TOPLEFT", 54, y)
			row.item:SetWidth(210)
			row.gain:SetPoint("TOPLEFT", 270, y - 3)
			row.gain:SetWidth(250)
			row.from:SetPoint("TOPLEFT", 526, y - 3)
			row.from:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y - 3)
			up.rows[i] = row
		end
		if row then
			local it = u and B.Item(u.id)
			row.item.id = u and u.id or nil
			row.n:SetText(u and ("|cffffd100%d|r"):format(offset + i) or "")
			row.icon:SetTexture(it and it.icon or nil)
			row.icon:SetShown(u and true or false)
			row.item.text:SetText(u and Name(u.id) or "")
			local reach = {}
			for _, word in ipairs(u and u.g.reach or {}) do reach[#reach + 1] = "reaches " .. (LABEL[word] or word) end
			row.gain:SetText(u and (B.GainText(u.g) .. (#reach > 0 and ("  |cff40ff40" .. table.concat(reach, ", ") .. "|r") or "")) or "")
			row.from:SetText(u and B.Source(u.id) or "")
			row.item:SetShown(u and true or false)
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
		for c, title in ipairs({ "Stat", "Worth", "Cap", "Past cap" }) do
			local head = Text(f, "GameFontNormalSmall")
			head:SetPoint("TOPLEFT", 8 + col * 370 + ({ 0, 150, 204, 258 })[c], -58)
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
		row.w:SetPoint("TOPLEFT", x + 150, y)
		row.cap = Box(f, function(n) B.Edit(word, "cap", n) end)
		row.cap:SetPoint("TOPLEFT", x + 204, y)
		row.over = Box(f, function(n) B.Edit(word, "over", n) end)
		row.over:SetPoint("TOPLEFT", x + 258, y)
		row.hard = Text(f)
		row.hard:SetPoint("TOPLEFT", x + 310, y - 2)
		weights.rows[word] = row
	end
end

local function DrawWeights(_, s)
	local raw = s.prof.raw
	local edit = B.db.edit[raw.id]
	local edited = edit and (next(edit.w or {}) or next(edit.caps or {})) and "  |cffff8040(changed by you)|r" or ""
	-- (four lines, none wrapped: the rows begin right under them)
	weights.note:SetText(("|cffffd100%s %s|r%s  |cff888888client %s|r\n|cff888888Per 1%%: hit, crit, haste, expertise, dodge, parry, block; the rest per point. A cap is the sheet's total. Enter takes a change, an empty box the default.|r\n|cff888888%s|r\n|cff888888%s|r")
		:format(ClassName(raw.class), raw.title, edited, DT.BisBuild or "?", table.concat(raw.src or {}, "   "), raw.note or ""))
	for word, row in pairs(weights.rows) do
		local cap = s.prof.caps[word]
		if not row.w:HasFocus() then row.w:SetText(s.prof.w[word] and Fmt(s.prof.w[word]) or "") end
		if not row.cap:HasFocus() then row.cap:SetText(cap and Fmt(cap.cap) or "") end
		if not row.over:HasFocus() then row.over:SetText(cap and Fmt(cap.over or 0) or "") end
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
	local x = 6
	local mine = B.Mine()
	for i = 1, math.max(#mine, #specButtons) do
		local spec = mine[i]
		local b = specButtons[i] or (spec and SpecButton(i))
		if b then
			b:SetShown(spec ~= nil)
			if spec then
				b.spec = spec
				b.icon:SetTexture(spec.icon and ("Interface\\Icons\\" .. spec.icon) or EMPTY_ART)
				b.label:SetText(spec.title)
				b.sel:SetShown(spec == raw)
				local w = 28 + b.label:GetStringWidth() + 6
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
	view, offset = which, 0
	Refresh()
end

local function Build(parent)
	panel = parent
	B.panel = panel
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
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		if view ~= "up" then return end
		offset = offset - delta * 3
		Refresh()
	end)
	panel:SetScript("OnSizeChanged", Refresh)
	local nextUpdate, nextSift = 0, 0
	panel:SetScript("OnUpdate", function()
		-- (the gear there is to get: looked at a batch at a time, while the tab is up)
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

-- (no profiles on this machine: no tab, no tooltip line, nothing)
if not (type(DT.BisProfiles) == "table" and DT.BisProfiles[1]) then return end

DT:RegisterModule("bis", {
	title = "BiS",
	version = 1,
	slash = "/dtbis",
	defaults = { tooltip = true, roll = true },
	settings = {
		{ key = "tooltip", label = "On item tooltips: what the item would gain over my best set" },
		{ key = "roll", label = "When an item is rolled for: the same, as a line in the chat" },
	},
	tab = { id = "bis", title = "BiS", defaultOrder = 61, group = 2, create = Build, onShow = Refresh },
	onEnable = function(mod)
		B.db, B.me = mod.db, UnitGUID("player")
		if B.db.factsV ~= FACTS then B.db.facts, B.db.factsV = {}, FACTS end
		for _, key in ipairs({ "pick", "edit", "base", "last", "facts" }) do
			if type(B.db[key]) ~= "table" then B.db[key] = {} end
		end
		for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_CLOSED", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "PLAYER_REGEN_ENABLED" }) do
			DT:On(event, Stale)
		end
		DT:On("PLAYER_LEVEL_UP", function() resolved = nil end) -- (the caps go with the level)
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
