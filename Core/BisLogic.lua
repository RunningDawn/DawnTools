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

-- How much rating buys one percent (one point of defense). Client 1.60.1: hit, haste and expertise 10, crit 14.
-- ponytail: defense, dodge, parry and block rating are taken one for one until somebody reads them off a
-- character sheet; BL.RATING is the knob.
BL.RATING = { hit = 10, shit = 10, haste = 10, exp = 10, crit = 14, scrit = 14, def = 1, dodge = 1, parry = 1, block = 1 }

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
	{ "damage done by (%a+) spells and effects by up to " .. NUM, "sp_", school = true },
	{ "damage and healing done by magical spells and effects by up to " .. NUM, "sp", also = "heal" },
	{ "spell power by " .. NUM, "sp", also = "heal" },
	{ "healing done by spells and effects by up to " .. NUM, "heal" },
	{ "healing power by " .. NUM, "heal" },
	{ "restores " .. NUM .. " mana per 5 sec", "mp5" },
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
			s[word], given[word] = (s[word] or 0) + value, true
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
	return s
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
	-- (two weapons: the off hand does half the damage; of two that could be either, the slower is in it)
	local a, b = items[1], items[2]
	local off = b
	if b and MAIN[a.loc] and MAIN[b.loc] and (a.s.dps or 0) < (b.s.dps or 0) then off = a end
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

-- The choices of every slot from a list of items { id, loc = "INVTYPE_HEAD", s = stats, n = how many there are }.
-- Two rings, two trinkets, and what the two hands hold are one choice each. Every slot may also stay empty.
function BL.Choices(items, prof)
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
		cands = Prune(cands, prof)
		cands[#cands + 1] = { ids = {}, s = {}, lin = 0 }
		slots[i] = { name = slot[1], cands = cands }
	end
	return slots
end

---------------------------------------------------------------------------
-- The best set
---------------------------------------------------------------------------

local HARD = 1e7 -- what a point towards a hard cap is worth: more than any set of gear

-- The best choice for every slot at once. Exact: slot after slot, the best worth is kept for every amount of
-- the capped stats reached so far (counted up to what is still missing to the cap, in steps), as past a cap
-- only the amount of a stat decides, not which items gave it.
-- Returns picks[slot index] = candidate, the gear's summed stats, its score and what hard caps still miss.
function BL.Solve(slots, base, prof)
	local caps = {}
	for word, cap in pairs(prof.caps or {}) do
		local need = math.max(cap.cap - (base[word] or 0), 0)
		-- (steps: a point of defense, a tenth of a percent; coarser where a cap typed in is so far off that the
		-- steps to it would not fit their part of the key)
		local step = math.max(cap.step or (word == "def" and 1 or 0.1), need / 4000)
		caps[#caps + 1] = { word = word, need = need, step = step,
			gain = (prof.w[word] or 0) - (cap.over or 0) + (cap.hard and HARD or 0) }
	end
	table.sort(caps, function(a, b) return a.word < b.word end)
	local n = #caps
	local states, trail = { [n > 4 and "" or 0] = { v = 0, g = {} } }, {}
	for i, slot in ipairs(slots) do
		local nextStates, back = {}, {}
		for key, st in pairs(states) do
			for ci, cand in ipairs(slot.cands) do
				local g, k = {}, n > 4 and "" or 0 -- (more caps than fit a number: the key as text)
				for c = 1, n do
					local cap = caps[c]
					local got = math.min((st.g[c] or 0) + (cand.s[cap.word] or 0), cap.need)
					g[c] = got
					local at = math.floor(got / cap.step + 0.5)
					if n > 4 then k = k .. at .. ":" else k = k * 4096 + at end
				end
				local v = st.v + cand.lin
				local at = nextStates[k]
				if not at or v > at.v or (v == at.v and ci < back[k][2]) then
					nextStates[k], back[k] = { v = v, g = g }, { key, ci }
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
