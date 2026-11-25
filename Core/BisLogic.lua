-- DawnTools :: BiS logic
-- Pure: what an item's tooltip is worth in stats, what a set of gear scores, and which set scores best. No game
-- API, so tests/run.lua can check it outside the game.
--
-- Stats go by short words. Those the game counts in "rating" are kept in what the rating buys (hit, crit,
-- haste, expertise, dodge, parry and block in percent; defense in skill points), so a cap reads as on the
-- character sheet: hit 8, exp 6.5, def 440.
--   str agi sta int spi armor dps ap rap fap (in cat and bear form) sp heal mp5 spen arp bv def hit shit crit scrit
--   haste exp dodge parry block, and sp_shadow, sp_fire, ... for the spell damage of one school
--
-- A profile is { w = { [stat] = worth of one }, caps = { [stat] = { cap = total, over = worth of one past it,
-- hard = true: to be reached before anything else counts } }, hands = { "shield", ... } }.

local _, DT = ...
DT = DT or {}
local BL = {}
DT.BisLogic = BL

-- How much rating buys one percent (one point of defense). Client 1.60.1, at level 60: hit, haste and expertise 10,
-- crit 14, dodge 12 (Warrior's Embrace: 18 rating, 1.5% on the sheet), parry 15, block 5.
-- ponytail: parry and block from the same level-60 table, not yet read off a sheet; defense one for one, as
-- Forever's items give it in skill points. BL.RATING is the knob (and FACTS in Modules/Bis.lua, to read items anew).
BL.RATING = { hit = 10, shit = 10, haste = 10, exp = 10, crit = 14, scrit = 14, def = 1, dodge = 12, parry = 15, block = 5 }

-- the game's own numbers (GetItemStats): key = our word, or { word, rating = true }
local GAME = {
	ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
	ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
	ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
	ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5", ITEM_MOD_SPELL_PENETRATION_SHORT = "spen",
	ITEM_MOD_BLOCK_VALUE_SHORT = "bv",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = { "def" }, ITEM_MOD_HIT_RATING_SHORT = { "hit" }, ITEM_MOD_HIT_MELEE_RATING_SHORT = { "hit" },
	ITEM_MOD_HIT_SPELL_RATING_SHORT = { "shit" }, ITEM_MOD_CRIT_RATING_SHORT = { "crit" }, ITEM_MOD_CRIT_MELEE_RATING_SHORT = { "crit" },
	ITEM_MOD_CRIT_SPELL_RATING_SHORT = { "scrit" }, ITEM_MOD_HASTE_RATING_SHORT = { "haste" }, ITEM_MOD_EXPERTISE_RATING_SHORT = { "exp" },
	ITEM_MOD_DODGE_RATING_SHORT = { "dodge" }, ITEM_MOD_PARRY_RATING_SHORT = { "parry" }, ITEM_MOD_BLOCK_RATING_SHORT = { "block" },
	ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arp",
}

-- A tooltip line (lower case), in the order tried: { pattern, word, rating = true: the number is rating,
-- spell = word for a line that speaks of spells }. The first that fits a line takes it.
local NUM = "(%d+%.?%d*)"
local TEXT = {
	{ "increased defense %+" .. NUM, "def", points = true },
	{ "defense rating by " .. NUM, "def", rating = true },
	{ "defense by " .. NUM, "def", points = true },
	{ "defense skill by " .. NUM, "def", points = true },
	{ "expertise rating by " .. NUM, "exp", rating = true },
	{ "expertise by " .. NUM .. "%%", "exp" },
	{ "dodged or parried by " .. NUM .. "%%", "exp" },
	{ "expertise by " .. NUM, "exp", rating = true },
	{ "hit rating by " .. NUM, "hit", rating = true, spell = "shit" },
	{ "chance to hit[%a ]* by " .. NUM .. "%%", "hit", spell = "shit" },
	{ "critical strike rating by " .. NUM, "crit", rating = true, spell = "scrit" },
	{ "crit rating by " .. NUM, "crit", rating = true, spell = "scrit" },
	{ "critical strike[%a ]* by " .. NUM .. "%%", "crit", spell = "scrit" },
	{ "haste rating by " .. NUM, "haste", rating = true },
	{ "haste by " .. NUM .. "%%", "haste" },
	{ "dodge rating by " .. NUM, "dodge", rating = true },
	{ "dodge an attack by " .. NUM .. "%%", "dodge" },
	{ "parry rating by " .. NUM, "parry", rating = true },
	{ "parry an attack by " .. NUM .. "%%", "parry" },
	{ "block value of your shield by " .. NUM, "bv" },
	{ "block rating by " .. NUM, "block", rating = true },
	{ "block attacks with a shield by " .. NUM .. "%%", "block" },
	{ "^" .. NUM .. " block$", "bv" },
	{ "armor penetration[%a ]* by " .. NUM, "arp" },
	{ "spell penetration by " .. NUM, "spen" },
	{ "attack power by " .. NUM .. " in cat", "fap" },
	{ "ranged attack power by " .. NUM, "rap" },
	{ "%+" .. NUM .. " ranged attack power", "rap" },
	{ "attack power by " .. NUM, "ap" },
	{ "%+" .. NUM .. " attack power", "ap" },
	{ "damage done by magical spells and effects by up to " .. NUM, "sp" },
	{ "damage done by (%a+) spells and effects by up to " .. NUM, "sp_", school = true },
	{ "damage and healing done by magical spells and effects by up to " .. NUM, "sp", also = "heal" },
	{ "spell power by " .. NUM, "sp", also = "heal" },
	{ "spell damage by up to " .. NUM, "sp" },
	{ "ignore " .. NUM .. " of your opponent's armor", "arp" },
	{ "healing done by spells and effects by up to " .. NUM, "heal" },
	{ "healing power by " .. NUM, "heal" },
	{ "restores " .. NUM .. " mana per 5 sec", "mp5" },
	{ "^%(" .. NUM .. " damage per second%)$", "dps" },
	{ "^" .. NUM .. " armor$", "armor" },
}
-- only what is always on: a "Use:" or "Chance on hit:" line is not the item's stats
local SKIP = { "^use:", "^chance on hit:", "^set:", "^%(%d%) set" }

-- The stats of an item: game = what GetItemStats gave ({ [the game's key] = number }), lines = its tooltip's
-- lines. A stat the game gave a number for is not read from the text a second time.
function BL.Stats(game, lines)
	local s, given = {}, {}
	for key, value in pairs(game or {}) do
		local word = GAME[key]
		if word and type(value) == "number" then
			if type(word) == "table" then word, value = word[1], value / (BL.RATING[word[1]] or 1) end
			-- (two of the game's keys for one stat, "hit" and "melee hit": the same number twice, not two to add)
			s[word], given[word] = s[word] and math.max(s[word], value) or value, true
		end
	end
	-- (the game's one "spell power" is damage and healing both: a healer counts it as healing, unless the game says the healing itself)
	if given.sp and not given.heal and (game or {}).ITEM_MOD_SPELL_POWER_SHORT and not (game or {}).ITEM_MOD_SPELL_DAMAGE_DONE_SHORT then
		s.heal, given.heal = game.ITEM_MOD_SPELL_POWER_SHORT, true
	end
	local text = {}
	for _, line in ipairs(lines or {}) do
		line = type(line) == "string" and line:lower() or ""
		local skip = false
		for _, p in ipairs(SKIP) do skip = skip or line:find(p) ~= nil end
		if not skip then
			for _, t in ipairs(TEXT) do
				local n, second = line:match(t[1])
				local school = t.school and n
				n = tonumber(t.school and second or n)
				-- (a bonus that holds against some foes only is not counted: "+30 Attack Power when fighting Undead")
				if n and (t[2] == "ap" or t[2] == "rap") and (line:find(" when ") or line:find(" against ") or line:find(" while ") or line:find(" versus ")) then break end
				if n then
					local word = t.school and (t[2] .. school) or t[2]
					if t.spell and line:find("spell", 1, true) then word = t.spell end
					if t.rating then n = n / (BL.RATING[word] or 1) end
					text[word] = (text[word] or 0) + n
					if t.also then text[t.also] = (text[t.also] or 0) + n end
					break
				end
			end
		end
	end
	for word, n in pairs(text) do
		if not given[word] then s[word] = n end
	end
	-- (Forever: one hit and one crit for melee, ranged and spells alike. A plain one counts for spells too; one that
	-- says "spell" for spells only)
	s.shit, s.scrit = s.shit or s.hit, s.scrit or s.crit
	return s
end

-- What a consumable or an enchant gives, from its "Use:" line or its spell's text ("Permanently enchant bracers to
-- increase Strength by 9", "gain 25 Stamina and Spirit"). A short effect ("for 15 sec": a proc) is not counted.
-- ponytail: health counts as Stamina, ten to one; a proc (Crusader) counts nothing.
local PRIMARY = { strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi" }
local EXTRA = {
	{ "armor[%a ,]* by " .. NUM, "armor" }, { "%+" .. NUM .. " armor", "armor" }, { NUM .. " additional armor", "armor" },
	{ "maximum health by " .. NUM, "hp" }, { "%+" .. NUM .. " health", "hp" },
	{ "critical hit by " .. NUM .. "%%", "crit" }, { "healing[%a ]* by up to " .. NUM, "heal" }, { "spell damage by up to " .. NUM, "sp" },
	{ NUM .. " mana per 5 sec", "mp5" }, { NUM .. " mana every 5", "mp5" }, { "mana regen[%a ]* by " .. NUM, "mp5" },
}
function BL.UseStats(lines)
	local s, rest = {}, {}
	for _, line in ipairs(lines or {}) do
		line = type(line) == "string" and line:lower():gsub("^use: ", "") or ""
		if not line:find("for %d+ sec") then
			rest[#rest + 1] = line
			for a, n, b, c in line:gmatch("((%d+) (%a+) and (%a+))") do -- ("25 stamina and spirit")
				for _, w in ipairs({ b, c }) do if PRIMARY[w] then s[PRIMARY[w]] = (s[PRIMARY[w]] or 0) + tonumber(n) end end
				line = line:gsub(a:gsub("%p", "%%%0"), "", 1)
			end
			local all = line:match("all stats by " .. NUM)
			for name, word in pairs(PRIMARY) do
				local n = all or line:match(name .. " by " .. NUM) or line:match("%+?" .. NUM .. " " .. name)
				if n then s[word] = (s[word] or 0) + tonumber(n) end
			end
			for _, e in ipairs(EXTRA) do
				local n = line:match(e[1])
				if n then s[e[2]] = (s[e[2]] or 0) + tonumber(n) break end
			end
		end
	end
	if s.hp then s.sta, s.hp = (s.sta or 0) + s.hp / 10, nil end
	for word, n in pairs(BL.Stats(nil, rest)) do
		if not s[word] and word ~= "armor" and word ~= "mp5" then s[word] = n end
	end
	return s
end

-- Of each group (one elixir of a kind, one food, one enchant a slot), the one worth most to a profile:
-- list = { { id, group, s } }; returns { [group] = entry }. Capped stats count their full weight.
function BL.BestExtras(list, prof)
	local best, at = {}, {}
	for _, e in ipairs(list) do
		local v = 0
		for word, n in pairs(e.s or {}) do v = v + n * (prof.w[word] or 0) end
		if v > 0 and (not at[e.group] or v > at[e.group]) then best[e.group], at[e.group] = e, v end
	end
	return best
end

-- Of the items for one place to wear, { id, s }, the few worth trying in a set: the best n as worth with every cap
-- still to reach, and the best n as worth with every cap reached (a set short of its caps is made of the first, one
-- that has them of the second, most of both). Returns { [id] = true }.
function BL.Few(list, prof, n)
	local full, taken = {}, {}
	for word, cap in pairs(prof.caps or {}) do full[word] = cap.cap end
	for _, base in ipairs({ full, {} }) do
		local by = {}
		for i, e in ipairs(list) do by[i] = { e.id, (BL.Score(e.s, base, prof)) } end
		table.sort(by, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
		for i = 1, math.min(#by, n) do taken[by[i][1]] = true end
	end
	return taken
end

function BL.Add(into, s, times)
	for word, n in pairs(s) do into[word] = (into[word] or 0) + n * (times or 1) end
	return into
end

-- What a set of gear scores: gear = its summed stats, base = the character without gear. A capped stat is
-- worth its weight up to the cap (counted from where the character stands without gear) and "over" past it.
-- Also returns short = { [stat] = how far a hard cap is from being reached }.
function BL.Score(gear, base, prof)
	local score, short = 0, {}
	for word, w in pairs(prof.w) do
		local g, cap = gear[word] or 0, prof.caps and prof.caps[word]
		if cap then
			local b = base[word] or 0
			local under = math.min(b + g, cap.cap) - math.min(b, cap.cap)
			score = score + w * under + (cap.over or 0) * (g - under)
		else
			score = score + w * g
		end
	end
	for word, cap in pairs(prof.caps or {}) do
		local miss = cap.cap - (base[word] or 0) - (gear[word] or 0)
		if cap.hard and miss > 1e-9 then short[word] = miss end
	end
	return score, short
end

---------------------------------------------------------------------------
-- The slots, and what may go in each
---------------------------------------------------------------------------

BL.SLOTS = {
	{ "Head", { INVTYPE_HEAD = 1 } }, { "Neck", { INVTYPE_NECK = 1 } }, { "Shoulder", { INVTYPE_SHOULDER = 1 } },
	{ "Back", { INVTYPE_CLOAK = 1 } }, { "Chest", { INVTYPE_CHEST = 1, INVTYPE_ROBE = 1 } }, { "Wrist", { INVTYPE_WRIST = 1 } },
	{ "Hands", { INVTYPE_HAND = 1 } }, { "Waist", { INVTYPE_WAIST = 1 } }, { "Legs", { INVTYPE_LEGS = 1 } },
	{ "Feet", { INVTYPE_FEET = 1 } }, { "Rings", { INVTYPE_FINGER = 1 }, pair = true }, { "Trinkets", { INVTYPE_TRINKET = 1 }, pair = true },
	{ "Weapons", hands = true },
	{ "Ranged", { INVTYPE_RANGED = 1, INVTYPE_RANGEDRIGHT = 1, INVTYPE_THROWN = 1, INVTYPE_RELIC = 1 } },
}
-- what is held in the hands, by the name a profile gives it: { main hand, off hand (nil: nothing) }
local MAIN = { INVTYPE_WEAPON = 1, INVTYPE_WEAPONMAINHAND = 1 }
BL.HANDS = {
	shield = { MAIN, { INVTYPE_SHIELD = 1 } },
	dw = { MAIN, { INVTYPE_WEAPON = 1, INVTYPE_WEAPONOFFHAND = 1 } },
	held = { MAIN, { INVTYPE_HOLDABLE = 1 } },
	["2h"] = { { INVTYPE_2HWEAPON = 1 } },
}

-- the part of an item's worth that does not depend on the rest of the set, and its capped stats
local function Weigh(s, prof)
	local lin = 0
	for word, n in pairs(s) do
		local cap = prof.caps and prof.caps[word]
		lin = lin + n * (cap and (cap.over or 0) or (prof.w[word] or 0))
	end
	return lin
end

local function Cand(items, prof, hands)
	local c = { ids = {}, s = {} }
	for i, item in ipairs(items) do
		c.ids[i] = item.id
		BL.Add(c.s, item.s)
	end
	-- (two weapons: the off hand does half the damage; of two that could be either, the weaker is in it, and second)
	local a, b = items[1], items[2]
	local off = b
	if b and a.loc == "INVTYPE_WEAPON" and MAIN[b.loc] and (a.s.dps or 0) < (b.s.dps or 0) then off, c.ids[1], c.ids[2] = a, b.id, a.id end
	if hands and off and off.s.dps then c.s.dps = c.s.dps - off.s.dps / 2 end
	c.lin = Weigh(c.s, prof)
	return c
end

-- b is at least as good as a, whatever else is worn
local function Beats(b, a, prof)
	if b.lin < a.lin then return false end
	for word in pairs(prof.caps or {}) do
		if (b.s[word] or 0) < (a.s[word] or 0) then return false end
	end
	return true
end

-- candidates no other candidate is at least as good as (of two alike, the first stays)
local function Prune(cands, prof)
	local out = {}
	for i, a in ipairs(cands) do
		local beaten = false
		for j, b in ipairs(cands) do
			if i ~= j and Beats(b, a, prof) and (j < i or not Beats(a, b, prof)) then
				beaten = true
				break
			end
		end
		if not beaten then out[#out + 1] = a end
	end
	return out
end

-- a choice that holds every id of ids (an id twice: two of it)
local function Holds(c, ids)
	local left = {}
	for _, id in ipairs(c.ids) do left[id] = (left[id] or 0) + 1 end
	for _, id in ipairs(ids) do
		if (left[id] or 0) == 0 then return false end
		left[id] = left[id] - 1
	end
	return true
end

-- The choices of every slot from a list of items { id, loc = "INVTYPE_HEAD", s = stats, n = how many there are }.
-- Two rings, two trinkets, and what the two hands hold are one choice each. Every slot may also stay empty.
-- need[slot index] = { ids }: locked there, only choices that hold them (none fits: the slot stays empty).
function BL.Choices(items, prof, need)
	local slots = {}
	for i, slot in ipairs(BL.SLOTS) do
		local cands = {}
		local function Pairs(first, second)
			for _, a in ipairs(items) do
				if first[a.loc] then
					if not second then cands[#cands + 1] = Cand({ a }, prof) end
					for _, b in ipairs(second and items or {}) do
						-- (a pair of two alike: once, and only where there are two of it)
						local alike = first[b.loc] and second[a.loc]
						if second[b.loc] and (a ~= b or (a.n or 1) > 1) and not (alike and b.id < a.id) and not (a == b and not alike) then
							cands[#cands + 1] = Cand({ a, b }, prof, slot.hands)
						end
					end
					-- (one hand full, the other empty: better than nothing)
					if second then cands[#cands + 1] = Cand({ a }, prof) end
				end
			end
		end
		if slot.hands then
			for _, name in ipairs(prof.hands or { "2h", "dw", "shield", "held" }) do
				local h = BL.HANDS[name]
				if h then Pairs(h[1], h[2]) end
			end
		elseif slot.pair then
			Pairs(slot[2], slot[2])
		else
			Pairs(slot[2])
		end
		local must = need and need[i]
		if must then
			local keep = {}
			for _, c in ipairs(cands) do if Holds(c, must) then keep[#keep + 1] = c end end
			cands = keep
		end
		cands = Prune(cands, prof)
		if not must or #cands == 0 then cands[#cands + 1] = { ids = {}, s = {}, lin = 0 } end
		slots[i] = { name = slot[1], cands = cands }
	end
	return slots
end

---------------------------------------------------------------------------
-- The best set
---------------------------------------------------------------------------

local HARD = 1e7 -- what a point towards a hard cap is worth: more than any set of gear
local FIRST = { def = 1000 } -- (and of hard caps, defense before all else: a tank uncrittable first, then hit)

-- The best choice for every slot at once. Exact: slot after slot, the best worth is kept for every amount of
-- the capped stats reached so far (counted up to what is still missing to the cap, in steps), as past a cap
-- only the amount of a stat decides, not which items gave it.
-- Returns picks[slot index] = candidate, the gear's summed stats, its score and what hard caps still miss.
-- tick: called now and then while it works (the caller may pause there: Modules/Bis.lua works it out over several frames).
local Solve1
function BL.Solve(slots, base, prof, tick)
	local picks, gear, score, short = Solve1(slots, base, prof, tick)
	-- (a cap to reach first that no set reaches: not chased at any price. It counts by its weight, and the set is
	-- chosen anew; what is still missing to it is said all the same)
	if next(short) then
		local caps = {}
		for word, cap in pairs(prof.caps) do caps[word] = short[word] and { cap = cap.cap, over = cap.over, step = cap.step } or cap end
		picks, gear = Solve1(slots, base, { w = prof.w, caps = caps, hands = prof.hands }, tick)
		score, short = BL.Score(gear, base, prof)
	end
	return picks, gear, score, short
end
function Solve1(slots, base, prof, tick)
	local caps = {}
	-- (the steps of all caps together stay under STATES: three caps of a hundred steps each are a million states a
	-- slot, seconds of work. ponytail: coarser steps can miss a cap's last point; a set of two caps is still exact)
	local STATES, ncaps = 20000, 0
	for word, cap in pairs(prof.caps or {}) do if cap.cap - (base[word] or 0) > 0 then ncaps = ncaps + 1 end end
	local steps = math.max(8, math.floor(STATES ^ (1 / math.max(ncaps, 1))))
	for word, cap in pairs(prof.caps or {}) do
		local need = math.max(cap.cap - (base[word] or 0), 0)
		-- (steps: a point of defense, a tenth of a percent; coarser where a cap typed in is so far off that the
		-- steps to it would not fit their part of the key, or where many caps are counted at once)
		local step = math.max(cap.step or (word == "def" and 1 or 0.1), need / 4000, need / steps)
		caps[#caps + 1] = { word = word, need = need, step = step, top = math.floor(need / step + 0.5) + 1,
			gain = (prof.w[word] or 0) - (cap.over or 0) + (cap.hard and HARD * (FIRST[word] or 1) or 0) }
	end
	table.sort(caps, function(a, b) return a.word < b.word end)
	local n = #caps
	local states, trail = { [n > 4 and "" or 0] = { v = 0, g = {} } }, {}
	local g, min, floor = {}, math.min, math.floor -- (g: worked out in place; a table is made only for a state that wins)
	local done = 0
	for i, slot in ipairs(slots) do
		local nextStates, back = {}, {}
		if tick then tick() end
		for key, st in pairs(states) do
			done = done + 1
			if tick and done % 32 == 0 then tick() end
			local sg, sv = st.g, st.v
			for ci, cand in ipairs(slot.cands) do
				local k, cs = n > 4 and "" or 0, cand.s -- (more caps than fit a number: the key as text)
				for c = 1, n do
					local cap = caps[c]
					local got = min((sg[c] or 0) + (cs[cap.word] or 0), cap.need)
					g[c] = got
					-- (the cap reached is a step of its own: a cap off the steps, 2.45 in tenths, is not one with "nearly")
					local at = got >= cap.need and cap.top or min(floor(got / cap.step + 0.5), cap.top - 1)
					if n > 4 then k = k .. at .. ":" else k = k * 4096 + at end
				end
				local v = sv + cand.lin
				-- (of two in one step, the one worth more with what each has toward the caps: steps may be coarse)
				local w = v
				for c = 1, n do w = w + caps[c].gain * g[c] end
				local at = nextStates[k]
				if not at then
					local copy = {}
					for c = 1, n do copy[c] = g[c] end
					nextStates[k], back[k] = { v = v, w = w, g = copy }, { key, ci }
				elseif w > at.w or (w == at.w and ci < back[k][2]) then
					at.v, at.w = v, w
					for c = 1, n do at.g[c] = g[c] end
					back[k][1], back[k][2] = key, ci
				end
			end
		end
		states, trail[i] = nextStates, back
	end
	local bestKey, bestV
	for key, st in pairs(states) do
		local v = st.v
		for c = 1, n do v = v + caps[c].gain * st.g[c] end
		if not bestV or v > bestV or (v == bestV and key < bestKey) then bestKey, bestV = key, v end
	end
	local picks, gear, key = {}, {}, bestKey
	for i = #slots, 1, -1 do
		local b = trail[i][key]
		picks[i] = slots[i].cands[b[2]]
		BL.Add(gear, picks[i].s)
		key = b[1]
	end
	local score, short = BL.Score(gear, base, prof)
	return picks, gear, score, short
end

---------------------------------------------------------------------------
-- Which spec a character is
---------------------------------------------------------------------------

-- the talent trees of each class in the order the game lists them
BL.TREES = {
	WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
	HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
	PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
	MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
	DRUID = { "Balance", "Feral", "Restoration" },
}

-- The profile id for talent points (points[tree] = spent): the tree with the most (the first of equals), and of
-- the profiles of that class the one named for the tree ("warrior-fury"); a variant of it (threat only, melee
-- weave, bear) is for a click. nil where no point is spent or no such profile is there.
function BL.SpecId(class, points, profiles)
	local names, most, at = BL.TREES[class or ""], 0, nil
	if not names then return nil end
	for i = 1, #names do
		if (points[i] or 0) > most then most, at = points[i], i end
	end
	if not at then return nil end
	local id = class:lower() .. "-" .. (names[at]:lower():gsub("%s", ""))
	for _, p in ipairs(profiles or {}) do
		if p.id == id then return id end
	end
	return nil
end

return BL
