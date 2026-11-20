-- DawnTools self-check: the price maths, then whole addons (one per fake guild member) talking over a fake
-- guild channel. Run with:  cd tests && npm install && npm test   (needs Lua 5.2+ for loadfile's env; fengari is 5.3)

local DIR = ADDON_DIR or ""
local checks = 0
local function check(cond, what)
	checks = checks + 1
	if not cond then error("FAILED: " .. what, 2) end
end
local function eq(got, want, what)
	check(got == want, ("%s: got %s, want %s"):format(what, tostring(got), tostring(want)))
end

---------------------------------------------------------------------------
-- 1. Logic
---------------------------------------------------------------------------

local L = assert(loadfile(DIR .. "Core/Logic.lua"))()
local BASE = 1700000000 -- 80000 seconds into its day
local DAY = L.DAY

do
	local now, items = BASE, {}
	local function ob(id, p, q, t, o) return { id = id, p = p, q = q, t = t, o = o } end

	check(L.Observe(items, ob(1, 100, 5, now - 10, "A"), now), "an observation is taken")
	eq(items[1].p, 100, "latest price"); eq(items[1].q, 5, "latest quantity"); eq(items[1].o, "A", "latest observer")
	local ok, why = L.Observe(items, ob(1, 100, 5, now - 10, "B"), now)
	eq(ok, false, "the same observation twice"); eq(why, "dup", "is a duplicate")
	check(L.Observe(items, ob(1, 90, 9, now - 100, "C"), now), "an older observation is taken")
	eq(items[1].p, 100, "but the newest stays the latest"); eq(items[1].o, "A", "with its observer")
	eq(select(2, L.Observe(items, ob(1, 100, 1, now + 301, "A"), now)), "future", "from the future")
	check(L.Observe(items, ob(1, 110, 1, now + 50, "A"), now), "a clock a little ahead is fine")
	eq(select(2, L.Observe(items, ob(1, 100, 1, now - 14 * DAY - 1, "A"), now)), "old", "older than the history")
	eq(select(2, L.Observe(items, ob(1, 0, 1, now, "A"), now)), "bad", "no price")
	eq(select(2, L.Observe(items, ob(0, 5, 1, now, "A"), now)), "bad", "no item")
	eq(L.Observe({}, { id = 1, t = now }, now), false, "no price field")

	local med, n = L.Median(items[1], 7, now)
	eq(med, 100, "median of 90, 100, 110"); eq(n, 3, "over three observations")
	eq(L.Median({ d = {} }, 7, now), nil, "no median without data")

	-- outliers: kept, flagged, not believed; my own eyes are believed
	ok, why = L.Observe(items, ob(1, 600, 1, now + 100, "M"), now)
	eq(ok, true, "an outlier is kept"); eq(why, "outlier", "and flagged"); eq(items[1].p, 110, "but is not the latest")
	eq(select(2, L.Observe(items, ob(1, 19, 1, now + 101, "M"), now)), "outlier", "far too cheap is one too")
	eq(select(2, L.Observe(items, ob(1, 600, 1, now + 100, "M"), now)), "dup", "an outlier is not taken twice")
	eq(select(2, L.Median(items[1], 7, now)), 3, "outliers stay out of the median")
	ok, why = L.Observe(items, ob(1, 500, 1, now + 102, "M"), now)
	eq(why, nil, "five times the median is still believed")
	ok, why = L.Observe(items, ob(1, 3000, 2, now + 103, "me"), now, true)
	eq(why, nil, "what I saw myself is believed"); eq(items[1].p, 3000, "and is the latest")

	check(L.Observe(items, ob(1, 2900, 4, now + 103, "me"), now, true), "my second look in the same second")
	eq(items[1].p, 2900, "replaces the first"); eq(select(2, L.Median(items[1], 7, now)), 5, "without counting twice")

	-- history and trend
	local items2 = {}
	for i, p in ipairs({ 100, 120, 110 }) do L.Observe(items2, ob(2, p, i, now - 2 * DAY + i, "A"), now) end
	L.Observe(items2, ob(2, 200, 7, now - 5, "A"), now)
	local h = L.History(items2[2])
	eq(#h, 2, "two days of history"); eq(h[1].min, 100, "day min"); eq(h[1].median, 110, "day median")
	eq(h[1].n, 3, "day count"); eq(h[1].q, 3, "most listed that day"); eq(h[2].median, 200, "today")
	check(h[1].day < h[2].day, "oldest first")
	eq(L.Median(items2[2], 7, now), 115, "an even count takes the middle of the middle two")
	check(math.abs(L.Trend(items2[2], now) - (200 / 115 - 1)) < 1e-9, "trend against the 7-day median")
	eq(L.Median(items2[2], 1, now), 200, "median over one day")

	-- the cap per day
	local items3 = {}
	for i = 1, 20 do L.Observe(items3, ob(3, 100 + i, 1, now - 100 + i, "A"), now, true) end
	eq(L.History(items3[3])[1].n, L.MAX_PER_DAY, "a day keeps so many"); eq(items3[3].p, 120, "the latest still moves")

	-- a local fill-in: one price for its day, never passed on
	local items4 = {}
	check(L.Observe(items4, { id = 4, p = 77, q = 0, t = now - 50, o = "Auctionator", loc = true }, now, true), "a fill-in is taken")
	eq(items4[4].p, 77, "as the latest"); eq(L.History(items4[4])[1].min, 77, "and as that day's price")
	L.Observe(items4, { id = 4, p = 70, q = 0, t = now - 45, o = "Auctionator", loc = true }, now, true)
	eq(L.History(items4[4])[1].n, 1, "one a day, however often it is read"); eq(L.Median(items4[4], 7, now), 70, "counted in the median")
	eq(#L.Since(items4, 0, 100), 0, "so it is never passed on")
	L.Observe(items4, ob(4, 80, 3, now - 40, "A"), now)
	eq(items4[4].p, 80, "a real observation replaces it")

	-- since
	local since = L.Since(items, now - 50, 100)
	eq(since[1].t, now + 103, "newest first"); eq(since[2].o, "", "observer only known for the latest")
	for _, s in ipairs(since) do check(s.p ~= 600 and s.p ~= 19, "outliers are not passed on") end
	local found
	for _, s in ipairs(since) do if s.t == now + 103 then found = s end end
	eq(found and found.o, "me", "the latest carries its observer"); eq(found and found.q, 4, "and its quantity")
	eq(#L.Since(items, now - 50, 2), 2, "capped")
	eq(#L.Since(items, now + 1000, 100), 0, "nothing newer")

	-- wire format
	local text = L.Encode({ ob(1, 100, 5, now, "Al,i;ce"), ob(22, 3, 0, now + 1, "") })
	eq(text, ("1,100,5,%d,Alice;22,3,0,%d,"):format(now, now + 1), "encoded")
	local back = L.Decode(text .. ";garbage;1,2,3;9,9,9,9,x,y;-1,5,5,5,z")
	eq(#back, 2, "garbage is skipped"); eq(back[1].o, "Alice", "observer"); eq(back[2].id, 22, "second id"); eq(back[2].o, "", "no observer")
	eq(back[1].t, now, "time survives")
	eq(L.Encode({ ob(1, 1, 1, 1, "a"), ob(2, 2, 2, 2, "b"), ob(3, 3, 3, 3, "c") }, 2, 2), "2,2,2,2,b", "a slice")
	local many = {}
	for i = 1, L.MAX_DECODE + 50 do many[i] = ob(i, 1, 1, now, "") end
	eq(#L.Decode(L.Encode(many)), L.MAX_DECODE, "a message is read up to a limit")

	-- prune
	local items5 = {}
	L.Observe(items5, ob(5, 10, 1, now - 13 * DAY, "A"), now)
	L.Observe(items5, ob(6, 10, 1, now - 3 * DAY, "A"), now)
	L.Observe(items5, ob(6, 12, 1, now - 100, "A"), now)
	L.Observe(items5, ob(7, 10, 1, now - 50, "A"), now)
	eq(L.Prune(items5, now + 2 * DAY), 2, "an item not seen for 14 days goes"); eq(items5[5], nil, "gone")
	eq(L.Prune(items5, now + 12 * DAY), 2, "items stay while seen in time"); eq(#L.History(items5[6]), 1, "their old days go")
	local keep = L.MAX_ITEMS
	L.MAX_ITEMS = 1
	eq(L.Prune(items5, now), 1, "over the cap"); check(items5[7] and not items5[6], "the longest unseen goes first")
	L.MAX_ITEMS = keep

	eq(L.Money(12345), "1g 23s 45c", "money"); eq(L.Money(240), "2s 40c", "silver"); eq(L.Money(7), "7c", "copper")
	eq(L.Ago(30), "just now", "seconds"); eq(L.Ago(12 * 60), "12m ago", "minutes"); eq(L.Ago(3 * 3600 + 5), "3h ago", "hours")
	eq(L.Ago(2 * DAY + 5), "2d ago", "days")
	check(L.Newer("0.2.0", "0.1.9") and L.Newer("1.10", "1.9") and not L.Newer("0.1.0", "0.1.0") and not L.Newer("0.1", "0.2"), "versions")
end

---------------------------------------------------------------------------
-- 1b. BiS logic: what a tooltip is worth, what a set scores, the best set
---------------------------------------------------------------------------

do
	local BL = assert(loadfile(DIR .. "Core/BisLogic.lua"))()
	local s = BL.Stats({ ITEM_MOD_STAMINA_SHORT = 20, RESISTANCE0_NAME = 500, ITEM_MOD_HIT_RATING_SHORT = 10, ITEM_MOD_CRIT_RATING_SHORT = 28 }, {
		"Helm of Tests", "Equip: Increased Defense +7.", "Equip: Improves your chance to hit by 1%.", "Equip: Increases your expertise rating by 13.",
		"Use: Increases defense by 50 for 10 sec.", "Equip: Increases damage done by Shadow spells and effects by up to 20.", "38 Block",
		"Equip: Improves your chance to get a critical strike with spells by 1%.", "Equip: Increases the block value of your shield by 12.",
		"Equip: Increases damage and healing done by magical spells and effects by up to 9.", "Equip: +30 Attack Power.", "Equip: Restores 4 mana per 5 sec." })
	eq(s.sta, 20, "the game's own numbers are taken"); eq(s.armor, 500, "armor too")
	eq(s.hit, 1, "ten hit rating is a percent, and a stat the game gave is not read from the text again"); eq(s.crit, 2, "fourteen crit rating a percent")
	eq(s.def, 7, "defense from its Equip line"); check(math.abs(s.exp - 1.3) < 1e-9, "expertise rating in percent")
	eq(s.sp_shadow, 20, "the damage of one school"); eq(s.bv, 50, "a shield's block and what adds to it"); eq(s.scrit, 1, "a line that speaks of spells is the spell stat")
	eq(s.sp, 9, "spell power"); eq(s.heal, 9, "which heals too"); eq(s.ap, 30, "attack power"); eq(s.mp5, 4, "mana per 5")
	eq(BL.Stats(nil, { "Use: Increases defense by 50 for 10 sec.", "Chance on hit: Increases attack power by 100." }).def, nil, "a Use line is not a stat of the item")

	local prof = { w = { sta = 1, def = 15, hit = 4, str = 0.5 }, caps = { def = { cap = 440, over = 0.2, hard = true }, hit = { cap = 8, over = 0 } }, hands = { "shield" } }
	local score, short = BL.Score({ sta = 10, def = 20, hit = 2 }, { def = 425, hit = 7.5 }, prof)
	eq(score, 10 + 15 * 15 + 0.2 * 5 + 4 * 0.5, "a capped stat is worth its weight up to the cap, counted from the character without gear"); eq(next(short), nil, "the hard cap is reached")
	eq(select(2, BL.Score({ def = 5 }, { def = 425 }, prof)).def, 10, "or how far it is")

	-- the solver against every combination tried one by one
	local seed = 7
	local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return seed % n end
	local function sum(list)
		local g = {}
		for _, it in ipairs(list) do BL.Add(g, it.s) end
		local sc, sh = BL.Score(g, { def = 400, hit = 5 }, prof)
		return sc - 1e7 * (sh.def or 0)
	end
	for round = 1, 12 do
		local items, by = {}, {}
		local function add(loc, n)
			by[loc] = {}
			for _ = 1, n do
				local it = { id = #items + 1, loc = loc, s = { sta = rnd(30), def = rnd(4) == 0 and rnd(25) or 0, hit = rnd(3) == 0 and rnd(3) or 0, str = rnd(20) } }
				items[#items + 1] = it
				by[loc][#by[loc] + 1] = it
			end
			by[loc][#by[loc] + 1] = false
		end
		add("INVTYPE_HEAD", 3) add("INVTYPE_CHEST", 3) add("INVTYPE_LEGS", 2) add("INVTYPE_FINGER", 4) add("INVTYPE_WEAPON", 2) add("INVTYPE_SHIELD", 2)
		add("INVTYPE_2HWEAPON", 1) -- (not for one who holds a shield)
		items[#items].s.sta = 500
		local best
		for _, h in ipairs(by.INVTYPE_HEAD) do for _, c in ipairs(by.INVTYPE_CHEST) do for _, l in ipairs(by.INVTYPE_LEGS) do
			for i, r1 in ipairs(by.INVTYPE_FINGER) do for j, r2 in ipairs(by.INVTYPE_FINGER) do
				if j > i or not r2 then
					for _, w in ipairs(by.INVTYPE_WEAPON) do for _, sh in ipairs(by.INVTYPE_SHIELD) do
						local list = {}
						for _, it in pairs({ h, c, l, r1, r2, w, sh }) do if it then list[#list + 1] = it end end
						local v = sum(list)
						if not best or v > best then best = v end
					end end
				end
			end end
		end end end
		local slots = BL.Choices(items, prof)
		local picks = BL.Solve(slots, { def = 400, hit = 5 }, prof)
		local list, seen = {}, {}
		for _, p in ipairs(picks) do
			for _, id in ipairs(p.ids) do
				check(not seen[id], "an item is worn once")
				seen[id] = true
				list[#list + 1] = items[id]
				check(items[id].loc ~= "INVTYPE_2HWEAPON", "what the profile's hands do not hold is left out")
			end
		end
		check(math.abs(sum(list) - best) < 1e-6, ("round %d: the solver finds the best set (%s, by trying all %s)"):format(round, sum(list), best))
	end
	-- two of the same ring only where there are two
	local one = BL.Choices({ { id = 1, loc = "INVTYPE_FINGER", s = { sta = 5 }, n = 1 } }, prof)
	eq(#BL.Solve(one, {}, prof)[11].ids, 1, "one ring is worn once")
	local two = BL.Choices({ { id = 1, loc = "INVTYPE_FINGER", s = { sta = 5 }, n = 2 } }, prof)
	eq(#BL.Solve(two, {}, prof)[11].ids, 2, "two of it, twice")
end

---------------------------------------------------------------------------
-- 1c. DB logic: rows, chunks, hashes, and two copies becoming one
---------------------------------------------------------------------------

do
	local D = assert(loadfile(DIR .. "Core/DBLogic.lua"))()
	eq(D.ChunkOf("item:872"), "item:3", "a row lies in the chunk of its number"); eq(D.ChunkOf("drops:644:872"), "drops:2", "a relation by what it starts from")
	eq(D.ChunkOf("item:0"), "item:0", "the first chunk"); eq(D.ChunkOf("item:255"), "item:0", "holds 256 numbers"); eq(D.ChunkOf("item:256"), "item:1", "then the next")
	check(D.ChunkOf("catch:Durotar"):find("^catch:s%d+$"), "a key without a number lies by its letters"); eq(D.ChunkOf("catch:Durotar"), D.ChunkOf("catch:Durotar"), "always the same place")
	local rows = { ["item:872"] = { t = 100, src = "own", v = "Rockhide Strongfish;35" }, ["item:870"] = { t = 90, src = "guild", v = "" } }
	local text = D.Build(rows)
	eq(text, "item:870\t90\tguild\t\nitem:872\t100\town\tRockhide Strongfish;35", "a chunk is its rows, a line each, in the order of their keys")
	local back = D.Parse(text)
	eq(back["item:872"].v, "Rockhide Strongfish;35", "and reads back"); eq(back["item:872"].t, 100, "with its time"); eq(back["item:870"].src, "guild", "and source")
	eq(D.Build(back), text, "to the same text"); eq(next(D.Parse("rubbish\nmore of it")), nil, "what is no row is left out")
	eq(D.Clean("a\tb\nc"), "a b c", "nothing in a row breaks its line")
	eq(#D.Hash(text), 16, "a hash is 16 hex digits"); eq(D.Hash(text), D.Hash(D.Build(back)), "the same rows hash the same")
	check(D.Hash(text) ~= D.Hash(text .. " "), "another text another hash"); check(D.Hash("ab") ~= D.Hash("ba"), "the order counts too")
	eq(D.Roll({ a = "1", b = "2" }), D.Roll({ b = "2", a = "1" }), "the hash of many does not depend on the order they are named in")
	-- which row wins
	local now = 1000
	eq(D.Wins({ t = 5, v = "x" }, nil, now), true, "a row I have none of is taken"); eq(D.Wins({ t = 6, v = "x" }, { t = 5, v = "y" }, now), true, "a newer one too")
	eq(D.Wins({ t = 4, v = "x" }, { t = 5, v = "y" }, now), false, "an older one not"); eq(D.Wins({ t = now + 301, v = "x" }, nil, now), false, "nor one from the future")
	eq(D.Wins({ t = 5, v = ("x"):rep(2001) }, nil, now), false, "nor one far too long"); eq(D.Wins({ t = 5 }, nil, now), false, "nor one that is no row")
	eq(D.Wins({ t = 5, v = "b" }, { t = 5, v = "a" }, now), true, "of two of one second the later text"); eq(D.Wins({ t = 5, v = "a" }, { t = 5, v = "b" }, now), false, "on both sides the same")
	-- two copies that each know what the other does not end the same
	local mine = { ["npc:1"] = { t = 10, src = "own", v = "Wolf" }, ["npc:2"] = { t = 10, src = "own", v = "Boar" } }
	local theirs = { ["npc:2"] = { t = 20, src = "own", v = "Big Boar" }, ["npc:3"] = { t = 5, src = "own", v = "Bat" } }
	eq(D.Merge(mine, theirs, now), 2, "theirs laid into mine: two rows taken"); eq(D.Merge(theirs, mine, now), 1, "mine into theirs: one")
	eq(D.Build(mine), D.Build(theirs), "and both hold the same"); eq(mine["npc:2"].v, "Big Boar", "the newer of what both had")
	eq(D.Merge(mine, theirs, now), 0, "a second time nothing is taken")
	eq(D.Merge({}, theirs, now, function(key) return key == "npc:3" end), 2, "a row may be refused")
	eq(table.concat(D.Differ({ a = "1", b = "2", c = "3" }, { a = "1", b = "9", d = "4" }), ","), "b,c,d", "what two copies must exchange: the chunks that differ or that one lacks")
	-- counters
	eq(D.Counter(52, { [872] = 7, [5] = 60 }), "52;5:52,872:7", "a counter: looted, and each item seen (never more often than looted)")
	local n, items = D.Counted("52;5:52,872:7")
	eq(n, 52, "read back"); eq(items[872], 7, "with its items"); eq(select(1, D.Counted("rubbish")), 0, "rubbish counts nothing")
	eq(select(2, D.Counted("3;9:50"))[9], 3, "a count above what was looted is cut down")
end

---------------------------------------------------------------------------
-- 2. A fake game, one per guild member, on one clock and one guild channel
---------------------------------------------------------------------------

local now, timers, clients, sent = 0, {}, {}, {}
-- A stand-in for LibDeflate: the real one compresses correctly under fengari but does not inflate (not even a
-- stored block), so it cannot run here. It is checked in the game instead, by /dt selftest ("message packing").
local LibDeflate = {
	CompressDeflate = function(_, text) return "Z" .. text end,
	DecompressDeflate = function(_, text) return text:sub(1, 1) == "Z" and text:sub(2) or nil end,
	EncodeForWoWAddonChannel = function(_, text) return text end,
	DecodeForWoWAddonChannel = function(_, text) return text end,
	-- (for print: as hex here; the real one has its own alphabet)
	EncodeForPrint = function(_, text) return (text:gsub(".", function(ch) return ("%02x"):format(ch:byte()) end)) end,
	DecodeForPrint = function(_, text)
		if #text % 2 ~= 0 or text:find("[^0-9a-f]") then return nil end
		return (text:gsub("..", function(h) return string.char(tonumber(h, 16)) end))
	end,
}
-- ("../DawnTools_Seed/": the data files, kept out of the addon: see Core/DBSeed.lua)
local FILES = { "Core/Logic.lua", "Core/BisLogic.lua", "Core/Core.lua", "Core/Comms.lua", "Core/UI.lua", "Core/Builtins.lua", "Core/Profiles.lua", "Core/DBLogic.lua", "Core/DB.lua", "Core/DBImport.lua", "Core/DBSeed.lua", "Market/Capture.lua", "Market/Sync.lua", "Market/UI.lua", "../DawnTools_Seed/CraftSkill.lua", "../DawnTools_Seed/Dungeons.lua", "../DawnTools_Seed/BisProfiles.lua", "Data/BisLists.lua", "Modules/Inventory.lua", "Modules/Fish.lua", "Modules/Food.lua", "Modules/Craft.lua", "Modules/Npc.lua", "Modules/Quest.lua", "Modules/Item.lua", "Modules/Zone.lua", "Modules/Dungeon.lua", "Modules/Favs.lua", "Modules/Finds.lua", "Modules/Combat.lua", "Modules/Bis.lua", "Tools/Tools.lua", "Tools/Range.lua", "Tools/Mp5.lua", "Tools/Tracker.lua", "Tools/Enemies.lua", "Tools/Carrot.lua", "Tools/ChatHistory.lua", "Core/DBSync.lua", "Core/Changelog.lua", "Core/Home.lua" }

local function after(delay, fn, owner) timers[#timers + 1] = { at = now + delay, fn = fn, owner = owner } end
local function Now() return BASE + math.floor(now) end

local function step(seconds)
	for _ = 1, math.floor(seconds / 0.05 + 0.5) do
		now = now + 0.05
		local due = {}
		for i = #timers, 1, -1 do
			if timers[i].at <= now then due[#due + 1] = table.remove(timers, i) end
		end
		table.sort(due, function(a, b) return a.at < b.at end)
		for _, t in ipairs(due) do
			local gone = t.owner and t.owner.gone -- a member who logged out: their timers died with their client
			if not gone then t.fn() end
			if t.every and not t.cancelled and not gone then
				t.at = now + t.every
				timers[#timers + 1] = t
			end
		end
		for _, c in ipairs(clients) do
			for _, w in ipairs(c.updaters) do
				if w.shown and w.scripts.OnUpdate then w.scripts.OnUpdate(w, 0.05) end
			end
		end
	end
end

-- items: name, quality, stack, vendor sell price, commodity, class, subclass
local ITEMS = {
	[100] = { "Copper Bar", 1, 20, 10, true, 7, 7 },
	[110] = { "Copper Ore", 1, 20, 5, true, 7, 7 },
	[300] = { "Linen Cloth", 1, 20, 30, true, 7, 5 },
	[400] = { "Sword", 2, 1, 1000, false, 2, lvl = 20, ilvl = 25 },
	[500] = { "Bid Only Axe", 2, 1, 1000, false, 2 },
	[600] = { "Grey Fang", 0, 20, 100, true, 15 },
	[820] = { "Minor Potion", 1, 5, 10, true, 0 },
	[821] = { "Herb", 1, 20, 2, true, 7, 9 },
	[830] = { "Coarse Thread", 1, 20, 2, true, 7, 5 },
}

-- Widgets only have the methods the real ones have for their type: a call to anything else is the same
-- "attempt to call a nil value" the game would raise.
local function Methods(base, names)
	local set = {}
	for name in pairs(base or {}) do set[name] = true end
	for name in names:gmatch("%S+") do set[name] = true end
	return set
end
local REGION = Methods(nil, "SetPoint ClearAllPoints SetAllPoints GetPoint GetLeft GetTop GetRight GetCenter SetSize SetWidth SetHeight GetWidth GetHeight Show Hide IsShown SetShown GetParent")
local FRAME = Methods(REGION, [[SetScript GetScript HookScript HasScript RegisterEvent UnregisterEvent UnregisterAllEvents
	CreateFontString CreateTexture SetAttribute GetAttribute SetBackdrop SetBackdropColor SetBackdropBorderColor SetFrameStrata SetFrameLevel GetEffectiveScale SetClampedToScreen
	SetMovable EnableMouse EnableMouseWheel RegisterForDrag StartMoving StopMovingOrSizing SetResizable SetResizeBounds
	StartSizing]])
local BUTTON = Methods(FRAME, [[SetText GetText RegisterForClicks SetEnabled Enable Disable LockHighlight UnlockHighlight SetNormalTexture
	SetHighlightTexture SetPushedTexture]])
local METHODS = {
	Frame = FRAME, Button = BUTTON,
	CheckButton = Methods(BUTTON, "SetChecked GetChecked"),
	EditBox = Methods(FRAME, "SetText GetText SetAutoFocus SetNumeric SetFocus ClearFocus HasFocus"),
	FontString = Methods(REGION, "SetText GetText SetJustifyH SetWordWrap SetTextColor SetSpacing SetFont SetShadowColor SetShadowOffset GetStringWidth"),
	Texture = Methods(REGION, "SetColorTexture SetTexture SetTexCoord SetAtlas"),
	GameTooltip = Methods(FRAME, "SetOwner AddLine AddDoubleLine GetItem SetHyperlink"),
	Slider = Methods(FRAME, "SetOrientation SetMinMaxValues SetValue GetValue SetValueStep SetObeyStepOnDrag SetThumbTexture"),
}

local function NewClient(name, opts)
	opts = opts or {}
	local c = {
		name = name, wire = name .. "-Forever", widgets = {}, updaters = {}, listeners = {}, printed = {}, popups = {}, queries = {},
		guild = true, combat = false, instance = false, searched = {}, browse = {}, replicate = {}, bags = {},
		browseQueries = {}, more = 0, pages = {}, bank = {},
		npc = "Creature-0-1-2-3-8719-00001A", npcFaction = "Horde", -- the auctioneer talked to: a Horde one
		uncached = { [400] = true }, -- the first GetItemInfo of these returns nothing, as for an item never seen
	}
	local env = setmetatable({}, { __index = _G })
	env._G = env
	c.env = env

	local Widget
	local BEHAVIOUR = {
		SetScript = function(self, script, fn)
			if script == "OnUpdate" and not self.updater then
				self.updater = true
				c.updaters[#c.updaters + 1] = self
			end
			self.scripts[script] = fn
		end,
		GetScript = function(self, script) return self.scripts[script] end,
		HookScript = function(self, script, fn)
			if script == "OnUpdate" and not self.updater then
				self.updater = true
				c.updaters[#c.updaters + 1] = self
			end
			local old = self.scripts[script]
			self.scripts[script] = old and function(...) old(...) fn(...) end or fn
		end,
		-- a panel is as big as the window's body, unless a test says otherwise
		GetWidth = function(self) return self.w or 764 end,
		GetHeight = function(self) return self.h or 426 end,
		HasScript = function() return false end,
		CreateFontString = function() return Widget("FontString") end,
		CreateTexture = function() return Widget("Texture") end,
		Show = function(self) self.shown = true end,
		Hide = function(self) self.shown = false end,
		SetShown = function(self, v) self.shown = v and true or false end,
		IsShown = function(self) return self.shown end,
		RegisterEvent = function(self, e) c.listeners[e] = c.listeners[e] or self end,
		SetText = function(self, v)
			self.text = v
			if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
		end,
		GetText = function(self) return self.text end,
		SetEnabled = function(self, v) self.enabled = v and true or false end,
		SetTexture = function(self, texture) self.texture = texture end,
		SetChecked = function(self, v) self.checked = v and true or false end,
		GetChecked = function(self) return self.checked end,
		SetMinMaxValues = function(self, min, max) self.min, self.max = min, max end,
		GetValue = function(self) return self.value end,
		SetValue = function(self, v) -- as the game does: kept within its range, and the script hears of a change
			v = math.max(self.min or v, math.min(self.max or v, v))
			if v == self.value then return end
			self.value = v
			if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
		end,
		HasFocus = function(self) return self.focus or false end,
		GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
		SetAttribute = function(self, key, value)
			self.attr = self.attr or {}
			self.attr[key] = value
		end,
		GetAttribute = function(self, key) return self.attr and self.attr[key] end,
		GetStringWidth = function(self) return #((self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 end,
		GetLeft = function(self) return self.left end,
		GetRight = function(self) return self.right end,
		GetCenter = function(self) if self.left then return (self.left + self.right) / 2, self.mid end end,
		AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
		SetHyperlink = function(self, link) self.lines[#self.lines + 1] = link end,
		AddDoubleLine = function(self, left, right) self.lines[#self.lines + 1] = left .. " " .. right end,
	}
	function Widget(kind)
		local methods = assert(METHODS[kind or "Frame"], "unknown widget type " .. tostring(kind))
		local w = { scripts = {}, shown = true, kind = kind or "Frame", lines = {} }
		c.widgets[#c.widgets + 1] = w
		return setmetatable(w, { __index = function(_, k)
			if not methods[k] then return nil end
			return BEHAVIOUR[k] or function() end
		end })
	end

	function c.fire(event, ...)
		local f = c.listeners[event]
		if f then f.scripts.OnEvent(f, event, ...) end
	end

	env.GetTime = function() return now end
	env.time, env.GetServerTime, env.date = Now, Now, os.date
	env.geterrorhandler = function() return function(err) error(err, 0) end end
	env.hooksecurefunc = function(tbl, fname, hook)
		if type(tbl) ~= "table" then tbl, fname, hook = env, tbl, fname end
		local orig = tbl[fname]
		tbl[fname] = function(...) orig(...) hook(...) end
	end
	env.print = function(...) c.printed[#c.printed + 1] = table.concat({ ... }, " ") end
	env.CreateFrame = function(kind) return Widget(kind) end
	env.SecureHandlerWrapScript = function(_, _, _, body) c.wrapBody = body end
	env.UIParent, env.UISpecialFrames = Widget(), {}
	env.GameTooltip, env.ItemRefTooltip = Widget("GameTooltip"), Widget("GameTooltip")
	env.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn)
		local old = c.tooltipHook -- (every module that adds lines is heard, in the order they asked)
		c.tooltipHook = old and function(...) old(...) fn(...) end or fn
	end }
	env.Enum = { TooltipDataType = { Item = 0 }, AuctionHouseSortOrder = { Price = 0 },
		AuctionHouseFilter = setmetatable({}, { __index = function(_, k) return k end }) }
	-- the auction house answers a list query, or a request for more, with its next page
	c.page = function()
		local rows = table.remove(c.pages, 1)
		local first = #c.browse == 0
		for _, row in ipairs(rows) do c.browse[#c.browse + 1] = row end
		if first then c.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") else c.fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", rows) end
	end
	env.ITEM_QUALITY_COLORS = { [0] = { hex = "|cff9d9d9d" }, [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" } }
	env.SlashCmdList = {}
	env.GetItemClassInfo = function(class) return ({ [0] = "Consumables", [2] = "Weapons", [4] = "Armor", [7] = "Trade Goods", [15] = "Miscellaneous" })[class] end
	env.GetItemSubClassInfo = function(_, sub) return "Sub " .. sub end
	env.StaticPopupDialogs = {}
	env.StaticPopup_Show = function(which) c.popups[#c.popups + 1] = which end
	env.ChatEdit_InsertLink = function() end
	env.UnitName = function(unit)
		if unit == "npc" then return c.npcName end
		return name
	end
	env.UnitGUID = function(unit) return unit == "npc" and c.npc or ("Player-" .. name) end
	env.UnitFactionGroup = function(unit)
		if unit == "npc" then return c.npcFaction end
		return "Horde"
	end
	env.UnitFullName = function() return name, "Smith" end -- on Forever: first name, surname
	env.UnitLevel = function() return 10 end
	-- the combat log: a test puts an event in c.log and fires COMBAT_LOG_EVENT_UNFILTERED
	env.CombatLogGetCurrentEventInfo = function() return table.unpack(c.log or {}, 1, 21) end
	env.UnitClass = function() return "Warrior", "WARRIOR" end
	env.GetGuildInfo = function() return "Running Dawn" end
	env.IsInGuild = function() return c.guild end
	env.InCombatLockdown = function() return c.combat end
	env.IsInInstance = function() return c.instance, c.instance and "party" or "none" end
	env.Ambiguate = function(full) return (full:match("^[^-]+")) end
	env.C_Timer = {
		After = function(delay, fn) after(delay, fn, c) end,
		NewTicker = function(every, fn)
			local t = { at = now + every, fn = fn, every = every, owner = c }
			t.Cancel = function(self) self.cancelled = true end
			timers[#timers + 1] = t
			return t
		end,
	}
	env.C_Item = {
		GetItemInfo = function(id)
			local i = ITEMS[id]
			if not i or c.uncached[id] then return nil end
			return i[1], "[" .. i[1] .. "]", i[2], i.ilvl or 1, i.lvl or 1, "", "", i[3], i.slot or "", 1000 + id, i[4], i[6], i[7] or 0
		end,
		RequestLoadItemDataByID = function(id)
			after(0.2, function()
				if c.gone then return end
				c.uncached[id] = nil
				c.fire("GET_ITEM_INFO_RECEIVED", id, ITEMS[id] ~= nil)
			end)
		end,
	}
	env.C_AuctionHouse = {
		GetNumCommoditySearchResults = function(id) return #(c.searched[id] or {}) end,
		GetCommoditySearchResultInfo = function(id, i)
			local l = c.searched[id][i]
			return { unitPrice = l[1], quantity = l[2] }
		end,
		GetNumItemSearchResults = function(key) return #(c.searched[key.itemID] or {}) end,
		GetItemSearchResultInfo = function(key, i)
			local l = c.searched[key.itemID][i]
			return { buyoutAmount = l[1], quantity = l[2] }
		end,
		GetBrowseResults = function() return c.browse end,
		SendBrowseQuery = function(query) c.browseQueries[#c.browseQueries + 1] = query end,
		RequestMoreBrowseResults = function() c.more = c.more + 1 end,
		HasFullBrowseResults = function() return #c.pages == 0 end,
		IsThrottledMessageSystemReady = function() return true end,
		GetItemKeyInfo = function(key) return { isCommodity = ITEMS[key.itemID][5] } end,
		GetNumReplicateItems = function() return #c.replicate end,
		ReplicateItems = function() c.replicated = (c.replicated or 0) + 1 end,
		GetReplicateItemInfo = function(i)
			local r = c.replicate[i + 1] -- the game counts these from 0
			return "", 0, r[2], 1, true, 1, "", 0, 0, r[3], 0, nil, nil, "", "", 0, r[1], true
		end,
		MakeItemKey = function(id) return { itemID = id } end,
		SendSearchQuery = function(key) c.queries[#c.queries + 1] = key.itemID end,
	}
	env.C_Container = {
		-- a slot is an item ID, or { item ID, stack size }; the bank (-1) only answers while it is open
		GetContainerNumSlots = function(bag) return bag == 0 and #c.bags or (bag == -1 and c.bankOpen) and #c.bank or 0 end,
		GetContainerItemInfo = function(bag, slot)
			local v = (bag == -1 and c.bank or c.bags)[slot]
			if type(v) == "table" then
				return { itemID = v[1], stackCount = v[2], hyperlink = "|Hitem:" .. v[1] .. "|h[" .. ITEMS[v[1]][1] .. "]|h" }
			end
			return v and { itemID = v } or nil
		end,
	}
	if opts.auctionator then
		env.Auctionator = { Constants = { SCAN_DAY_0 = opts.day0 }, Database = { db = opts.auctionator }, API = { v1 = {
			RegisterForDBUpdate = function(_, fn) c.auctionatorUpdate = fn end,
		} } }
	end

	-- the guild channel: everyone in the guild hears a message, its sender too
	local AceComm = { Embed = function(_, target)
		-- (each prefix has its listener; a whisper reaches the one it is addressed to, the rest the whole guild)
		target.RegisterComm = function(t, prefix, method)
			c.hears = c.hears or {}
			c.hears[prefix] = function(...) t[method](t, ...) end
			c.hear = function(heard, ...)
				if c.hears[heard] then c.hears[heard](heard, ...) end
			end
		end
		target.SendCommMessage = function(_, prefix, text, distribution, to, prio, told)
			assert(#prefix <= 16 and not text:find("%z"), "a message the game would refuse")
			assert(not c.combat and not (c.instance and not c.DT.db.settings.instances), "sent where addon messages are restricted")
			sent[#sent + 1] = { from = name, text = text, prio = prio, prefix = prefix, distribution = distribution, to = to }
			if told then told(nil, #text, #text, c.refuse or 0) end -- (the game's answer: 0 is "taken")
			after(0.1, function()
				for _, other in ipairs(clients) do
					if other.guild and other.hear and (distribution ~= "WHISPER" or other.wire == to) then other.hear(prefix, text, distribution, c.wire) end
				end
			end)
		end
	end }
	local icon = { Register = function() end, Show = function() c.minimap = true end, Hide = function() c.minimap = false end }
	local libs = { ["AceComm-3.0"] = AceComm, LibDeflate = LibDeflate, ["LibDBIcon-1.0"] = icon,
		["LibDataBroker-1.1"] = { NewDataObject = function(_, _, obj) c.launcher = obj return obj end },
		-- how far a unit is: c.ranges[unit] = { nearest, furthest } (as the range library answers)
		["LibRangeCheck-3.0"] = { GetHarmCheckers = function()
			local list, i = { 30, 5, 28, 30 }, 0
			return function() i = i + 1 return list[i] end
		end, GetRange = function(_, unit)
			c.rangeAsked = (c.rangeAsked or 0) + 1
			local r = c.ranges and c.ranges[unit]
			if r then return r[1], r[2] end
		end } }
	env.LibStub = setmetatable({}, { __call = function(_, lib) return libs[lib] end })

	if opts.globals then opts.globals(env) end
	env.DawnToolsDB = opts.db
	local DT = {}
	c.DT = DT
	for _, file in ipairs(FILES) do
		-- (the recipes and dungeons are not in the addon: here they are put straight into its tables, as if the
		-- store had been filled; a client made with noData starts without, as a new member does)
		local SEED = "../DawnTools_Seed/"
		local data = file:sub(1, #SEED) == SEED
		if not (data and opts.noData) then
			local chunk = loadfile(DIR .. file, "t", env)
			if not chunk and data then error("the checks need the game data beside the addon: " .. SEED .. " (make it with tools/craftskill.js and tools/dungeons.js)") end
			assert(chunk, file)("DawnTools", DT)
		end
	end
	if opts.before then opts.before(DT) end
	clients[#clients + 1] = c
	c.fire("ADDON_LOADED", "DawnTools")
	c.fire("PLAYER_LOGIN")
	DT.db.settings.coins = false -- (prices as plain text here: the coin pictures have their own checks)
	c.M = DT.Market
	c.items = function() return DT.Market.items end
	c.slash = function(text) env.SlashCmdList.DAWNTOOLS(text) end
	return c
end

local function leave(c)
	c.fire("PLAYER_LOGOUT")
	c.hear, c.gone = nil, true
	for i, other in ipairs(clients) do
		if other == c then table.remove(clients, i) end
	end
end

-- messages on the channel of one kind (and from one member, if given)
local function count(kind, from, mod) -- (the Market's kinds are counted of the Market alone: other modules share under the same switch now)
	local n = 0
	mod = mod or ({ REQUEST = "market", DATA = "market", PUSH = "market" })[kind]
	local what = (mod and mod or "") .. "	" .. kind .. "	"
	for _, m in ipairs(sent) do
		if m.text:find(what, 1, true) and (not from or m.from == from) then n = n + 1 end
	end
	return n
end

local function packed(kind, payload, proto)
	if (kind == "PUSH" or kind == "DATA") and not payload:find("^%a|") then payload = "H|" .. payload end -- (the Horde house, unless the test says)
	return table.concat({ "market", kind, proto or 1, "z", LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(payload)) }, "\t")
end

local function wire(id, p, q, t, o) return ("%d,%d,%d,%d,%s"):format(id, p, q, t, o or "") end

---------------------------------------------------------------------------
-- 3. One member, not sharing: capture, tooltip, API
---------------------------------------------------------------------------

local A = NewClient("Alice")
local updates = 0
A.env.DawnMarket.API.RegisterForUpdate(function() updates = updates + 1 end)
eq(A.popups[1], nil, "the question waits a moment")
step(6)
eq(A.popups[1], "DAWNTOOLS_SHARE", "first launch asks about sharing")
eq(A.DT.db.settings.share, nil, "and nothing is decided for the player")

A.searched[100] = { { 50, 10 }, { 100, 10 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(A.items()[100].p, 50, "commodity: lowest unit price"); eq(A.items()[100].q, 20, "commodity: everything listed")
eq(A.items()[100].o, "Alice", "seen by me"); eq(A.items()[100].t, Now(), "at server time")

A.searched[400] = { { 900, 1 }, { 300, 9 }, { 0, 1 } }
A.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 400 })
eq(A.items()[400].p, 300, "item: lowest buyout, which is for one however many are sold at it"); eq(A.items()[400].q, 10, "item: auctions without a buyout are left out")

A.browse = { { itemKey = { itemID = 300 }, minPrice = 5, totalQuantity = 50 }, { itemKey = { itemID = 500 }, minPrice = 100, totalQuantity = 1 }, { itemKey = { itemID = 500, itemSuffix = 7 }, minPrice = 140, totalQuantity = 2 },
	{ itemKey = { itemID = 110 }, minPrice = 0, totalQuantity = 0 } }
A.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
eq(A.items()[300].p, 5, "browse row of a commodity"); eq(A.items()[300].q, 50, "with its quantity")
eq(A.items()[500].p, 100, "gear is taken from the list too: the cheapest of its rows"); eq(A.items()[110], nil, "an empty row is nothing")
A.items()[500] = nil -- (what follows was written without it)
A.fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { { itemKey = { itemID = 110 }, minPrice = 8, totalQuantity = 40 } })
eq(A.items()[110].p, 8, "rows added to a browse")

A.replicate = { { 600, 5, 100 }, { 600, 1, 15 }, { 600, 1, 0 }, { 821, 20, 400 } }
A.M.ahOpen = true -- (a full scan only comes at the auction house)
A.fire("REPLICATE_ITEM_LIST_UPDATE")
step(0.2)
A.M.ahOpen = false
eq(A.items()[600].p, 15, "full scan: lowest unit buyout"); eq(A.items()[600].q, 6, "full scan: units with a buyout")
eq(A.items()[821].p, 20, "full scan: a stack's price per unit")

-- the same price again is not a new observation, a new price is, and so is the same price much later
local seen = A.M.db.stats.n
step(60)
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(A.M.db.stats.n, seen, "an unchanged price is not recorded again at once")
A.searched[100][1][1] = 45
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(A.M.db.stats.n, seen + 1, "a changed price is"); eq(A.items()[100].p, 45, "and is the latest")
step(901)
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(A.M.db.stats.n, seen + 2, "and the same price after a quarter of an hour"); eq(A.items()[100].t, Now(), "so its age is honest")

eq(A.items()[100].n, "Copper Bar", "item name kept for the search"); eq(A.items()[100].c, 7, "and its class")
eq(A.items()[400].n, "Sword", "an item the client had to load is named once it has")
check(updates > 0, "API listeners hear about new prices")

local API = A.env.DawnMarket.API
local p, q, t, o = API.GetLatest(100)
eq(p, 45, "API price"); eq(q, 20, "API quantity"); eq(t, Now(), "API time"); eq(o, "Alice", "API observer")
local each = 0
API.Each(function(id, price, _, at) if id == 100 then each = price == p and at == t and 1 or -1 end end)
eq(each, 1, "API: every latest price can be walked")
eq(API.GetLatest(999), nil, "API: unknown item"); eq(API.GetMedian(100), 45, "API median")
eq(API.GetMedian(999), nil, "API: no median"); eq(#API.GetHistory(100), 1, "API history"); eq(#API.GetHistory(999), 0, "API: no history")

A.tooltipHook(A.env.GameTooltip, { id = 100 })
local line = A.env.GameTooltip.lines[#A.env.GameTooltip.lines]
check(line:find("Guild AH 45c (just now)", 1, true) and line:find("7d median 45c", 1, true), "tooltip line: " .. tostring(line))
A.tooltipHook(A.env.GameTooltip, { id = 999 })
eq(#A.env.GameTooltip.lines, 1, "no line for an item without a price")
A.M.db.settings.tooltip = false
A.tooltipHook(A.env.GameTooltip, { id = 100 })
eq(#A.env.GameTooltip.lines, 1, "and none when switched off")
A.M.db.settings.tooltip = true
do -- Shift over a stack: the price of all of it
	local tip = A.env.GameTooltip
	local lines, owner = tip.lines, tip.GetOwner
	tip.lines, tip.GetOwner = {}, function() return { count = 20 } end
	A.env.IsShiftKeyDown = function() return true end
	A.tooltipHook(tip, { id = 100 })
	check(tostring(tip.lines[1]):find("Guild AH 9s 0c x20", 1, true), "Shift over a stack of 20: twenty times the price: " .. tostring(tip.lines[1]))
	A.env.IsShiftKeyDown = nil
	tip.lines = {}
	A.tooltipHook(tip, { id = 100 })
	check(tostring(tip.lines[1]):find("Guild AH 45c (", 1, true), "without Shift: the price of one")
	tip.lines, tip.GetOwner = lines, owner
end

-- not sharing: the core says hello, the market says nothing
step(700)
check(count("HELLO", "Alice") >= 2, "the core says hello now and then")
for _, m in ipairs(sent) do check(not m.text:find("market", 1, true), "nothing about the market is sent before a yes") end
eq(A.DT.Comms.self, "Alice-Forever", "my own hello tells me my name on the wire")
eq(next(A.DT.Comms.peers), nil, "and I am not my own peer")
eq(A.M.Sync.queued, 0, "nothing is even queued")

---------------------------------------------------------------------------
-- 4. Two members sharing: HELLO, REQUEST, DATA, PUSH
---------------------------------------------------------------------------

A.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
eq(A.DT.db.settings.share, true, "Alice says yes")

local B = NewClient("Bob")
B.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
step(30)
check(A.DT.Comms.peers["Bob-Forever"], "Alice heard Bob"); check(B.DT.Comms.peers["Alice-Forever"], "Bob heard Alice, who answered a newcomer")
eq(B.DT.Comms.peers["Alice-Forever"].version, A.DT.VERSION, "with her version")
eq(count("REQUEST", "Bob"), 1, "Bob asks for what he missed"); eq(count("REQUEST", "Alice"), 0, "Alice has nothing to ask an empty Bob")
eq(count("DATA", "Alice"), 1, "Alice answers")
eq(B.items()[100] and B.items()[100].p, 45, "Bob has Alice's price"); eq(B.items()[100].o, "Alice", "and who saw it")
eq(B.items()[400].p, 300, "and the others"); eq(B.M.Sync.done, true, "Bob is in step")
step(2)
eq(B.items()[100].n, "Copper Bar", "names are looked up for merged items too")
for _, m in ipairs(sent) do
	if m.text:find("\tDATA\t", 1, true) then eq(m.prio, "BULK", "data goes out at low priority") end
end
eq(#L.History(A.items()[100]), 1, "Alice does not merge her own messages back")
local aliceCount = A.M.db.stats.n

-- a new price is pushed
A.searched[100][1][1] = 40
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(B.items()[100].p, 45, "not at once")
step(50)
eq(count("PUSH", "Alice"), 1, "one push"); eq(B.items()[100].p, 40, "Bob has the new price"); eq(B.items()[100].o, "Alice", "from Alice")
eq(A.M.db.stats.n, aliceCount + 1, "Alice counted it once")
step(100)
eq(count("PUSH", "Alice"), 1, "nothing new, nothing sent")

-- without my name
A.M.db.settings.name = false
A.searched[110] = { { 9, 30 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 110)
step(50)
eq(B.items()[110].p, 9, "pushed without a name"); eq(B.items()[110].o, "", "Bob does not know who")
eq(A.items()[110].o, "Alice", "Alice still does")
A.M.db.settings.name = true

-- combat and instances: wait, then send
A.combat = true
A.searched[300] = { { 6, 10 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 300)
step(50)
eq(B.items()[300].p, 5, "nothing is sent in combat"); eq(A.M.Sync.queued, 1, "it waits")
A.combat, A.instance = false, true
step(50)
eq(B.items()[300].p, 5, "nor in an instance")
A.DT.db.settings.instances = true
step(50)
eq(B.items()[300].p, 6, "unless that is allowed")
A.DT.db.settings.instances, A.instance = false, false

-- both see things; Bob relays nothing of Alice's as his own
B.searched[820] = { { 200, 30 } }
B.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 820)
step(50)
eq(A.items()[820].p, 200, "Alice has Bob's price"); eq(A.items()[820].o, "Bob", "seen by Bob")

---------------------------------------------------------------------------
-- 5. What is not believed
---------------------------------------------------------------------------

local function inject(c, sender, text, distribution) c.hear("DAWN", text, distribution or "GUILD", sender) end
local T = Now()

inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T + 1000, "=")))
eq(B.items()[7000], nil, "a price from the future is dropped")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T - 15 * DAY, "=")))
eq(B.items()[7000], nil, "and one older than the history")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T, "="), 0))
eq(B.items()[7000], nil, "and a message in a protocol older than supported")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T, "="), 99))
eq(B.items()[7000], nil, "and one in a protocol not yet known")
check(B.printed[#B.printed]:find("update", 1, true), "which says an update is due")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T, "=")), "WHISPER")
eq(B.items()[7000], nil, "and anything not on the guild channel")
inject(B, "Mallory-Forever", "market\tPUSH\t1\tz\tnot deflate at all")
inject(B, "Mallory-Forever", "nonsense")
inject(B, "Mallory-Forever", packed("NOPE", "x"))
inject(B, "Mallory-Forever", packed("PUSH", "x;y;;;1,2"))
inject(B, "Mallory-Forever", packed("REQUEST", "nobody"))
eq(B.items()[7000], nil, "garbage does no harm")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T, "=")))
eq(B.items()[7000].p, 5, "a sound one is taken"); eq(B.items()[7000].o, "Mallory", "under the sender's name")

-- an outlier against a known price
for i = 1, 3 do inject(B, "Carol-Forever", packed("PUSH", wire(100, 40 + i, 10, B.items()[100].t - 10 * i, "="))) end
eq(B.items()[100].p, 40, "older observations do not move the latest")
inject(B, "Mallory-Forever", packed("PUSH", wire(100, 4000, 10, T + 5, "=")))
eq(B.items()[100].p, 40, "a hundred times the median is not believed"); eq(B.items()[100].o, "Alice", "the latest stands")
inject(B, "Mallory-Forever", packed("PUSH", wire(100, 60, 10, T + 6, "=")))
eq(B.items()[100].p, 60, "a plausible change is")

-- one sender flooding
for i = 1, 60 do inject(B, "Spammer-Forever", packed("PUSH", wire(8000 + i, 5, 1, T, "="))) end
local flood = 0
for id in pairs(B.items()) do if id > 8000 and id < 9000 then flood = flood + 1 end end
eq(flood, 40, "a sender is heard so many times a minute")

---------------------------------------------------------------------------
-- 6. Logging out and in; sharing switched off; Auctionator
---------------------------------------------------------------------------

leave(B)
local saved = B.env.DawnToolsDB
eq(saved.market.synced, T + 6, "logging out in step is remembered, up to the newest price held")
step(120)
local requests = count("REQUEST", "Bob")
-- Auctionator's table: per item, the last price (m) and per day the highest low (h), lowest low (l), most listed (a).
-- Its day 500 is today, and started 80000 seconds before BASE.
local DAY0 = BASE - 80000 - 500 * DAY
local auctionator = {
	["830"] = { m = 21, h = { ["500"] = 22, ["499"] = 30 }, l = { ["499"] = 20 }, a = { ["500"] = 7 } },
	["820"] = { m = 150, h = { ["499"] = 150 }, l = {} },
	["300"] = { m = 99, h = { ["460"] = 99 }, l = {} },
	["g:400:20"] = { m = 5, h = { ["500"] = 5 }, l = {} },
	["110"] = "not a table", ["600"] = { m = 1 },
}
local B2 = NewClient("Bob", { db = saved, auctionator = auctionator, day0 = DAY0 })
eq(B2.items()[100].p, 60, "prices are saved"); eq(B2.items()[100].n, "Copper Bar", "with their names")
eq(B2.popups[1], nil, "the question is not asked twice")
step(40)
eq(count("REQUEST", "Bob"), requests, "nothing happened meanwhile: nothing for Bob to ask for")
eq(count("REQUEST", "Alice"), 1, "Alice, who never caught up with anyone, asks Bob")
eq(A.items()[7000] and A.items()[7000].p, 5, "and gets what Bob heard from others"); eq(A.M.Sync.done, true, "so she is in step too")
check(B2.DT.Comms.peers["Alice-Forever"], "though Alice is heard")

-- Auctionator's history: every item and day it has, for me only
local thread = B2.items()[830]
eq(thread.p, 21, "an item only Auctionator knows: its last price"); eq(thread.o, "Auctionator", "which says where it is from")
eq(thread.q, 7, "with the most it saw listed"); eq(thread.n, "Coarse Thread", "and a name to search by")
check(thread.t < Now() - 3600 and thread.t > Now() - DAY, "placed within its day, not at this minute")
local th = L.History(thread)
eq(#th, 2, "one price per day Auctionator scanned"); eq(th[1].min, 20, "an older day: the lowest it saw"); eq(th[2].min, 21, "today")
eq(B2.items()[820].p, 200, "a newer price of our own stays the latest"); eq(B2.items()[820].o, "Bob", "under its observer")
eq(#L.History(B2.items()[820]), 2, "while Auctionator's earlier day joins its history")
eq(B2.items()[300].p, 6, "days older than the history are left out"); eq(B2.items()[400].p, 300, "gear by item level is skipped")
eq(B2.items()[110].p, 9, "and what is not a price record does no harm"); eq(B2.items()[600].p, 15, "nor one without days")
eq(B2.M.Sync.queued, 0, "Auctionator's prices are not shared")
for _, o in ipairs(L.Since(B2.items(), 0, 99999)) do check(o.id ~= 830 and o.p ~= 150, "not when asked for everything either") end
eq(count("PUSH", "Bob"), 1, "Bob pushed only what he saw himself")
check(B2.auctionatorUpdate, "registered for Auctionator's updates")
auctionator["830"].m = 19
B2.auctionatorUpdate()
step(5)
eq(B2.items()[830].p, 19, "a scan by Auctionator is taken over"); eq(#L.History(B2.items()[830]), 2, "into the same days")
B2.M.db.settings.auctionator = false
auctionator["830"].m = 18
B2.auctionatorUpdate()
step(5)
eq(B2.items()[830].p, 19, "unless that is switched off")

-- Alice saw something while Bob was away
leave(B2)
A.searched[830] = { { 25, 60 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 830)
step(120)
local B3 = NewClient("Bob", { db = B2.env.DawnToolsDB })
step(40)
eq(count("REQUEST", "Bob"), requests + 1, "Bob asks for what he missed"); eq(B3.items()[830].p, 25, "and gets it")
eq(B3.items()[830].o, "Alice", "a real observation replaces the fill-in")
local answered = count("DATA", "Alice")
inject(A, "Bob-Forever", "market\tREQUEST\t1\t-\tAlice-Forever;0")
step(5)
eq(count("DATA", "Alice"), answered, "asking again within a minute gets no second answer")
inject(A, "Dave-Forever", "market\tREQUEST\t1\t-\tSomeone-Else;0")
step(5)
eq(count("DATA", "Alice"), answered, "a request for someone else is not mine to answer")

-- sharing off: deaf and mute
B3.DT.db.settings.share = false
local pushes, answers = count("PUSH", "Bob"), count("DATA", "Bob")
B3.searched[600] = { { 12, 5 } }
B3.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 600)
eq(B3.items()[600].p, 12, "prices are still recorded for me")
A.searched[100] = { { 33, 10 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
step(700)
eq(count("PUSH", "Bob"), pushes, "nothing is sent with sharing off"); eq(B3.items()[100].p, 60, "and nothing is taken in")
inject(B3, "Alice-Forever", "market\tREQUEST\t1\t-\tBob-Forever;0")
step(5)
eq(count("DATA", "Bob"), answers, "nor are requests answered")
check(not sent[#sent].text:find("market=", 1, true) or sent[#sent].from ~= "Bob", "Bob's hello no longer mentions the market")
check(B3.M.Sync:Status():find("Not sharing", 1, true), "the status says so")
check(A.M.Sync:Status():find("guild members seen", 1, true), "Alice's status counts peers")

---------------------------------------------------------------------------
-- 7. The window, the tabs, the commands
---------------------------------------------------------------------------

local C = NewClient("Carol", {
	globals = function(env) env.SLASH_OTHERADDON1 = "/dt" end,
	before = function(DT)
		DT:RegisterModule("demo", { title = "Demo", tab = { id = "demo", title = "Demo", defaultOrder = 20, create = function() end } })
		DT:RegisterModule("early", { title = "Early", tab = { id = "early", title = "Early", defaultOrder = 5, create = function() end } })
	end,
})
local function ids(list)
	local out = {}
	for i, tab in ipairs(list) do out[i] = tab.id end
	return table.concat(out, " ")
end
local UI = C.DT.UI
eq(C.env.SLASH_DAWNTOOLS1, "/dawntools", "the long command"); eq(C.env.SLASH_DAWNTOOLS2, nil, "/dt is left to the addon that has it")
eq(A.env.SLASH_DAWNTOOLS2, "/dt", "and taken when free"); eq(A.env.SLASH_DAWNTOOLS_MARKET1, "/dtmarket", "the module's short command")
eq(ids(UI:TabList()), "home early market favs demo inventory craft world combat bis tools", "tabs in their default order")
UI:MoveTab("demo", -1)
eq(ids(UI:TabList()), "home early market demo favs inventory craft world combat bis tools", "a tab moved up")
UI:MoveTab("home", -1)
eq(ids(UI:TabList()), "home early market demo favs inventory craft world combat bis tools", "the first cannot go higher")
UI:MoveTab("early", 1)
UI:MoveTab("early", 1)
eq(ids(UI:TabList()), "home market demo early favs inventory craft world combat bis tools", "moved down twice")
C.DT.db.tabs.hidden.market = true
eq(ids(UI:TabList()), "home demo early favs inventory craft world combat bis tools", "a hidden tab is off the bar"); eq(ids(UI:TabList(true)), "home market demo early favs inventory craft world combat bis tools", "but still there")
C.searched[100] = { { 50, 10 } }
C.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(C.items()[100].p, 50, "and its module keeps working")
C.slash("")
eq(C.DT.db.lastTab, "home", "the window opens on the first tab shown: Home, for someone new")
do
	local Home = C.DT.Home
	local homeB
	for _, w in ipairs(C.widgets) do if w.kind == "Button" and w.id == "home" and w.x then homeB = w end end
	eq(homeB.isIcon, true, "Home's button shows a picture"); eq(homeB.text, "", "not its name"); eq(homeB.tip, "Home", "which is said on hover")
	eq(homeB.x, 120, "it is the first on the bar")
	check(Home.forWhom.text:find("Running Dawn", 1, true), "built for Running Dawn"); check(Home.byWhom.text:find("Forgehaven", 1, true), "built by Forgehaven")
	check(Home.title.text:find(C.DT.VERSION, 1, true), "with the version")
	local lines = Home.Changelog()
	check(lines[1]:find(C.DT.VERSION, 1, true), "the changelog begins with this version: " .. lines[1]); check(lines[2]:find("^  %- "), "its lines beneath")
	eq(Home.log.rows[1].text, lines[1], "and is drawn, newest first")
	local guide = {}
	for _, b in ipairs(Home.guide) do if b.shown then guide[#guide + 1] = b.tab end end
	eq(table.concat(guide, " "), "demo early favs inventory craft world combat bis tools settings", "where things are: the tabs on the bar, in order (hidden ones left out)")
	local craftLine
	for _, b in ipairs(Home.guide) do if b.tab == "craft" then craftLine = b end end
	check(craftLine.label.text:find("(Fishing, Cooking, First Aid, Mining, Campsite, Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring)", 1, true), "a place names what is under it: " .. craftLine.label.text)
	craftLine.scripts.OnClick(craftLine)
	eq(C.DT.db.lastTab, "craft", "a click on a line opens that tab")
	C.slash("")
	C.slash("")
	eq(C.DT.db.lastTab, "craft", "closed and opened again: the tab last looked at, not Home")
	C.DT.db.tabs.hidden.home = true
	eq(ids(UI:TabList()):find("home"), nil, "Home can be hidden like any tab")
	C.DT.db.tabs.hidden.home = nil
end
C.slash("market")
eq(C.DT.db.lastTab, "market", "/dt market opens a hidden tab all the same")
C.env.SlashCmdList.DAWNTOOLS_MARKET()
C.slash("settings")
eq(C.DT.db.lastTab, "settings", "/dt settings")
C.slash("debug market")
check(C.DT.db.debug.market, "debug on")
C.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
C.searched[100][1][1] = 51
C.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
check(C.printed[#C.printed]:find("saw item 100", 1, true), "debug logs a capture")
C.slash("debug market")
C.slash("probe")
check(C.printed[#C.printed]:find("Carol", 1, true), "the probe names me")
C.slash("help")
check(C.printed[#C.printed]:find("/dt market", 1, true), "help lists the tabs")
C.launcher.OnClick(nil, "RightButton")
C.launcher.OnClick(nil, "LeftButton")
C.launcher.OnTooltipShow(C.env.GameTooltip)
C.env.DawnTools_OnAddonCompartmentClick()
C.DT:ShowMinimap(false)
check(C.DT.db.minimap.hide, "minimap button off")
-- prices with coin pictures, or as letters
C.DT.db.settings.coins = true
check(C.DT.Money(12345):find("^1|T.-GoldIcon.-|t 23|T.-SilverIcon.-|t 45|T.-CopperIcon.-|t$"), "a price with the game's coins: " .. C.DT.Money(12345))
check(C.DT.Money(45):find("^45|T.-CopperIcon.-|t$") and C.DT.Money(-205):find("^%-2|T"), "only the coins there are, and a minus where it is one")
C.DT.db.settings.coins = false
eq(C.DT.Money(12345), "1g 23s 45c", "switched off: letters")
-- what goes out and comes in is counted, for /dt sync
do
	local st = C.DT.Comms.stats
	local okBefore, blockedBefore = st.ok, st.blocked
	C.printed = {}
	C.env.SlashCmdList.DAWNTOOLS("sync")
	check(st.ok > okBefore or st.blocked > blockedBefore, "/dt sync says HELLO (or notes why it could not)")
	local said = table.concat(C.printed, "\n")
	check(said:find("Sent: %d+ pieces") and said:find("My HELLO:") and said:find("Heard: %d+ messages"), "and prints the counts: " .. said)
	local n = st.ok + st.blocked
	C.env.SlashCmdList.DAWNTOOLS("sync")
	eq(st.ok + st.blocked, n, "asked again within the minute: no second HELLO")
	local report = table.concat(C.DT.Comms:Report(), "\n")
	if C.DT.Market.Sync:On() then check(C.DT.Market.Sync:Status():find("Sent: %d+ pieces"), "the Market status carries the same lines") end
	-- a send the game refuses is counted as that, with its answer
	local refused = st.refused
	C.refuse = 7
	C.DT.Comms:Send("core", "TEST", "x")
	C.refuse = nil
	eq(st.refused, refused + 1, "a refused send is counted"); check(C.DT.Comms:Report()[1]:find("last answer: 7", 1, true), "with the game's answer")
end
-- the minimap button is our own: no library draws it
do
	C.env.Minimap = C.env.CreateFrame("Frame")
	C.DT:ShowMinimap(true)
	local b = C.DT.minimapButton
	check(b and b.shown, "the minimap button is there without any library")
	check(b.icon ~= nil, "with the sun on it")
	C.DT.UI:Show("market")
	b.scripts.OnClick(b, "RightButton")
	eq(C.DT.db.lastTab, "settings", "a right click opens the settings")
	C.DT:ShowMinimap(false)
	eq(b.shown, false, "hidden when switched off"); check(C.DT.db.minimap.hide, "which is remembered")
	eq(#C.DT.Comms:Report(), 3, "the report is three lines")
	eq(C.DT.Comms.stats.started, true, "and says the guild messages were started")
end

-- a module switched off is not there at all
leave(C)
local off = C.env.DawnToolsDB.modules
off.market, off.inventory, off.fish, off.food, off.combat, off.npc, off.quest, off.tools, off.range, off.mp5, off.tracker, off.home, off.item, off.zone = false, false, false, false, false, false, false, false, false, false, false, false, false, false
off.crafts, off.dungeon, off.dungeonlist, off.favs, off.chathistory, off.carrot, off.enemies, off.bis, off.finds = false, false, false, false, false, false, false, false, false
local D = NewClient("Carol", { db = C.env.DawnToolsDB })
eq(ids(D.DT.UI:TabList(true)), "", "no tab for a module switched off")
D.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(D.env.DawnMarket.API.GetLatest(100), nil, "its API knows nothing"); eq(#D.env.DawnMarket.API.GetHistory(100), 0, "and breaks nothing")
eq(D.env.SLASH_DAWNTOOLS_MARKET1, nil, "no command either")
D.slash("market")
D.slash("")
eq(D.DT.db.lastTab, "settings", "only Settings is left")
step(700)
eq(D.DT.UI:SelfTest(), 0, "selftest passes without modules")
leave(D)

-- the Market tab on Alice, who has prices
local V = A.M.View
UI = A.DT.UI
A.slash("market")
local function find(kind, text)
	for _, w in ipairs(A.widgets) do
		if w.kind == kind and w.text == text then return w end
	end
end
local function shown()
	local n = 0
	for _, w in ipairs(A.widgets) do
		if w.cells and w.shown then n = n + 1 end
	end
	return n
end
local function click(w, button) w.scripts.OnClick(w, button or "LeftButton") end
local total = 0
for _ in pairs(A.items()) do total = total + 1 end
eq(shown(), 19, "a screenful of rows"); check(find("FontString", total .. " items  |cff888888click one for its history|r"), "and a count of all " .. total)
local search
for _, w in ipairs(A.widgets) do if w.kind == "EditBox" and not search then search = w end end -- (the level boxes come after it)
search:SetText("copper")
step(0.5)
eq(shown(), 2, "search by part of a name")
search:SetText("")
local function section(label)
	for _, w in ipairs(A.widgets) do
		if w.entry and w.shown and w.entry.label == label then return w end
	end
end
local function sectionNames()
	local names = {}
	for _, w in ipairs(A.widgets) do
		if w.entry and w.shown then names[#names + 1] = w.entry.label end
	end
	return table.concat(names, ", ")
end
eq(sectionNames(), "All items, Favourites, Weapons, Consumables, Trade Goods, Miscellaneous", "the categories there are prices for, in auction house order")
click(section("Trade Goods"))
eq(shown(), 5, "trade goods only")
eq(sectionNames(), "All items, Favourites, Weapons, Consumables, Trade Goods, Sub 5, Sub 7, Sub 9, Miscellaneous", "its sub-categories open under it")
click(section("Sub 7"))
eq(shown(), 2, "a sub-category"); eq(section("Sub 7").text.text, "    Sub 7", "shown indented")
click(section("Sub 7"))
eq(shown(), 5, "clicked again: back to the whole category")
click(section("Weapons"))
eq(shown(), 1, "another category"); check(not section("Sub 7"), "closes the first; one sub-category is no list")
click(section("All items"))
eq(shown(), 19, "everything again")

-- more categories than fit: they scroll instead of running out of the window
click(section("Trade Goods"))
V.panel.h = 110
V.panel.scripts.OnSizeChanged(V.panel)
eq(sectionNames(), "All items, Favourites, Weapons, Consumables, Trade Goods", "only as many categories as fit")
local sidebar
for _, w in ipairs(A.widgets) do if w.bar then sidebar = w end end
eq(sidebar.bar.shown, true, "with a scroll bar")
sidebar.scripts.OnMouseWheel(sidebar, -1)
eq(sectionNames(), "Weapons, Consumables, Trade Goods, Sub 5, Sub 7", "the wheel scrolls them")
for _ = 1, 5 do sidebar.scripts.OnMouseWheel(sidebar, -1) end
eq(sectionNames(), "Trade Goods, Sub 5, Sub 7, Sub 9, Miscellaneous", "to the end and no further")
eq(sidebar.bar.value, 4, "the bar follows the wheel")
sidebar.bar:SetValue(1)
eq(sectionNames(), "Favourites, Weapons, Consumables, Trade Goods, Sub 5", "dragging the bar scrolls them")
sidebar.bar:SetValue(99)
eq(sectionNames(), "Trade Goods, Sub 5, Sub 7, Sub 9, Miscellaneous", "as far as its end")
click(section("Sub 9"))
eq(V.group, 9, "a scrolled category is the one clicked")
V.panel.h = nil
V.panel.scripts.OnSizeChanged(V.panel)
eq(sidebar.bar.shown, false, "no scroll bar when everything fits"); check(section("All items"), "and back at the top")
click(section("All items"))

-- the table has the whole height until an item is picked; then the history box takes its share
V.selected = 100
V:Refresh()
eq(V.rows, 13, "fewer rows beside the history box")
V.selected = nil
V:Refresh()
eq(V.rows, 19, "all of them again without it")

-- the filters: required level, quality, usable by me (the fake player is level 10; the Sword needs 20)
local function rowsShown()
	local out, n = {}, 0
	for _, w in ipairs(A.widgets) do
		if w.cells and w.shown then out[w.id], n = true, n + 1 end
	end
	return out, n
end
local function tick(quality, on)
	for _, w in ipairs(A.widgets) do
		if w.kind == "CheckButton" and w.quality == quality then
			w.checked = on
			click(w)
		end
	end
end
eq(V.qualities, nil, "no quality ticked: all of them")
tick(2, true)
local got, n = rowsShown()
check(n > 0 and got[400], "uncommon ticked: the green sword passes")
for id in pairs(got) do eq(ITEMS[id][2], 2, "and only uncommon is listed") end
tick(1, true)
got = rowsShown()
check(got[400] and got[100], "a second box adds its quality")
tick(2, false)
check(not rowsShown()[400] and rowsShown()[100], "a box cleared takes its quality out")
tick(1, false)
eq(V.qualities, nil, "all boxes cleared: all of them again")
V.minLevel = 10
V:Refresh()
got, n = rowsShown()
check(got[400] and n == 1, "only what needs level 10 or more")
local lvlCell
for _, w in ipairs(A.widgets) do if w.cells and w.shown then lvlCell = w.cells end end
eq(lvlCell.lvl.text, "20", "its level column"); eq(lvlCell.ilvl.text, "25", "and item level")
V.minLevel, V.maxLevel = nil, 5
V:Refresh()
check(not rowsShown()[400], "a highest level leaves it out")
V.maxLevel, V.usable = nil, true
V:Refresh()
got, n = rowsShown()
check(not got[400] and n > 0, "usable by me: not what needs a higher level")
local sword = A.items()[400]
eq(sword.lv, 20, "what a filter needs is kept with the item"); eq(sword.ql, 2, "level and quality")
local function usable() V:Refresh() return rowsShown()[400] end
sword.lv = 5
check(usable(), "a weapon my class wields, at my level: usable")
-- where the game does not tell proficiencies: what the class can learn
A.env.UnitClass = function() return "Mage", "MAGE" end
sword.s = 0 -- an axe
V:Refresh()
got = rowsShown()
check(not got[400] and got[100], "not a weapon my class cannot wield; what is no gear stays")
sword.c, sword.s = 4, 1
check(usable(), "cloth on a mage: usable")
sword.s = 3
check(not usable(), "mail on a mage: not")
A.env.UnitClass = function() return "Warrior", "WARRIOR" end
check(usable(), "mail on a warrior: usable")
sword.s = 4
check(not usable(), "plate before level 40: not yet")
-- where it does (everyone knows Cloth): what the character has trained
local known = { [9078] = true, [227] = true }
A.env.IsPlayerSpell = function(spell) return known[spell] or false end
sword.c, sword.s = 2, 7
check(not usable(), "a sword without the sword skill: not usable, whatever the class could learn")
known[201] = true
check(usable(), "trained: usable")
sword.s = 10
check(usable(), "a staff, trained")
sword.c, sword.s = 4, 3
check(not usable(), "mail not trained: not")
sword.s = 0
check(usable(), "a ring or cloak: anyone")
A.env.IsPlayerSpell = nil
-- recipes: only of a profession I have
sword.c, sword.s = 9, 3
A.env.C_Item.GetItemSubClassInfo = function(class, sub) return class == 9 and sub == 3 and "Engineering" or "Other" end
check(usable(), "a recipe, where the game does not list professions: left in")
A.env.GetProfessions = function() return 1, nil, nil, nil, 5 end
A.env.GetProfessionInfo = function(i) return i == 1 and "Tailoring" or "Cooking" end
check(not usable(), "an engineering recipe without engineering: not usable")
A.env.GetProfessionInfo = function(i) return i == 1 and "Engineering" or "Cooking" end
check(usable(), "with it: usable")
sword.s = 0
check(usable(), "a book: anyone")
A.env.GetProfessions, A.env.GetProfessionInfo, A.env.C_Item.GetItemSubClassInfo = nil, nil, nil
-- a skill the item asks for, that high: goggles, recipes. Read once from the tooltip's text, then kept
sword.c, sword.s = 4, 0
local tips, reads = { [400] = { { leftText = "Goggles" }, { leftText = "Requires Engineering (150)" } } }, 0
A.env.C_TooltipInfo = { GetItemByID = function(id)
	reads = reads + 1
	return { lines = tips[id] or { { leftText = "Thing" }, { leftText = "Requires Level 1" } } }
end }
A.env.GetNumSkillLines = function() return 3 end
local skills = { { "Professions", true }, { "Tailoring", false, 200 }, { "Engineering", false, 100 } }
A.env.GetSkillLineInfo = function(i) return skills[i][1], skills[i][2], false, skills[i][3] end
check(not usable(), "goggles that ask for Engineering 150, at 100: not usable"); eq(sword.rq, "Engineering:150", "what it asks for is kept with the item")
skills[3][3] = 150
check(usable(), "at 150: usable")
skills[3][1] = "Mining"
check(not usable(), "without the profession at all: not")
skills[3][1] = "Engineering"
sword.c, sword.s = 9, 3
A.env.C_Item.GetItemSubClassInfo = function() return "Engineering" end
check(usable(), "a recipe goes by the same line")
tips[400][3] = { leftText = "Already known" }
check(not usable(), "a recipe I already know: not usable")
reads = 0
check(not usable(), "still not"); eq(reads, 0, "and not read again")
tips[400][3] = nil
A.fire("NEW_RECIPE_LEARNED")
check(usable(), "after a recipe is learned they are read anew")
skills[3][3] = 149
check(not usable(), "one point short: not")
skills[3][3] = 150
A.env.C_Item.GetItemSubClassInfo = nil
A.items()[100].rq = nil
V:Refresh()
eq(A.items()[100].rq, nil, "no skill line seen once is not yet believed (the tooltip may be half fetched)")
check(rowsShown()[100], "and the item is listed meanwhile")
step(3)
eq(A.items()[100].rq, "", "seen the same a pass later, by itself: settled as asking for nothing")
reads = 0
V:Refresh()
V:Refresh()
eq(reads, 0, "once known, no tooltip is read again")
tips[400] = { { leftText = "Retrieving item information" } }
A.env.RETRIEVING_ITEM_INFO = "Retrieving item information"
sword.c, sword.s = 4, 0
sword.rq = nil
check(usable(), "a tooltip still being fetched says nothing: listed meanwhile"); eq(sword.rq, nil, "and nothing is kept of it")
tips[400] = { { leftText = "Goggles" }, { leftText = "Requires Engineering (300)" } }
step(3)
check(not rowsShown()[400], "read again by itself once it is there"); eq(sword.rq, "Engineering:300", "and kept then")
A.env.C_TooltipInfo, A.env.GetNumSkillLines, A.env.GetSkillLineInfo = nil, nil, nil
sword.rq = nil
for _, item in pairs(A.items()) do item.rq = nil end
sword.c, sword.s = 2, 0
-- the same answer every time, and the game is not asked again
local calls, real = 0, A.env.C_Item.GetItemInfo
A.env.C_Item.GetItemInfo = function(id)
	calls = calls + 1
	return real(id)
end
V.minLevel = 1
V:Refresh()
local first = select(2, rowsShown())
A.env.C_Item.GetItemInfo = function(id) calls = calls + 1 end -- (as if the game had forgotten every item)
V:Refresh()
eq(select(2, rowsShown()), first, "ticked again: the same items, though the game no longer knows them")
V.minLevel = nil
A.env.C_Item.GetItemInfo = real
-- an item the game has not loaded yet
ITEMS[400].lvl = 5
sword.lv, sword.ql = nil, nil
A.uncached[400] = true
check(not usable(), "an item the game has not loaded yet is left out for now")
A.uncached[400] = nil
step(3)
check(rowsShown()[400], "but asked for, and listed by itself once it has come")
sword.lv, sword.ql = nil, nil
local loads, load = 0, A.env.C_Item.RequestLoadItemDataByID
A.env.C_Item.RequestLoadItemDataByID = function(id) if id == 400 then loads = loads + 1 end end
A.uncached[400] = true
for _ = 1, 5 do V:Refresh() step(1) end
check(loads <= 2, "an item the game never delivers is not asked for on every redraw") -- (asked, then waiting for an answer)
A.uncached[400], A.env.C_Item.RequestLoadItemDataByID = nil, load
V:Refresh()
ITEMS[400].lvl, sword.lv = 20, 20
V.usable = nil
V:Refresh()
eq(select(2, rowsShown()), 19, "filters off: everything again")

-- resizing: more rows, a wider Item column
V.panel.w, V.panel.h = 1000, 700
V.panel.scripts.OnSizeChanged(V.panel)
eq(V.rows, 34, "a taller window has more rows"); eq(shown(), 34, "all filled")
V.panel.w, V.panel.h = nil, nil
V.panel.scripts.OnSizeChanged(V.panel)
eq(shown(), 19, "and smaller again")
for _, w in ipairs(A.widgets) do
	if w.scripts.OnMouseDown then
		w.scripts.OnMouseDown(w)
		w.scripts.OnMouseUp(w)
	end
end
check(A.DT.db.size and A.DT.db.size[1] > 0, "the window's size is saved")
;(function() -- the corner is pulled by a sum of our own: start size plus how far the mouse went, never a leap
	local frame, grip = A.DT.UI.frame, A.DT.UI.grip
	check(frame and grip, "(the window and its corner)")
	local e = A.env
	local mouse, down = { 500, 300 }, true
	e.GetCursorPosition = function() return mouse[1], mouse[2] end
	e.IsMouseButtonDown = function() return down end
	local sized = 0
	local wasSize, wasStart = frame.SetSize, frame.StartSizing
	frame.SetSize = function(self, w, h) sized = sized + 1 self.w, self.h = w, h end
	frame.GetWidth = function(self) return self.w or 1000 end
	frame.GetHeight = function(self) return self.h or 600 end
	frame.StartSizing = function() error("the game's own sizing is not used") end
	frame.w, frame.h = 1000, 600
	grip.scripts.OnMouseDown(grip)
	eq(sized, 0, "taking the corner changes nothing by itself: no leap")
	mouse = { 560, 260 } -- (60 to the right, 40 down: the screen's y grows upward)
	grip.scripts.OnUpdate(grip, 0.02)
	eq(frame.w, 1060, "the window is as much wider as the mouse went right"); eq(frame.h, 640, "and as much taller as it went down")
	mouse = { 100, 900 }
	grip.scripts.OnUpdate(grip, 0.02)
	eq(frame.w, 900, "pulled far in: no smaller than the least"); eq(frame.h, 420, "either way")
	mouse = { 99999, -99999 }
	grip.scripts.OnUpdate(grip, 0.02)
	eq(frame.w, 900 + 500 - 40, "pulled far out with the screen's size not known: a limit all the same, not as far as it is pulled"); eq(frame.h, 420 + 400 - 40, "both ways")
	local up = e.UIParent
	local wasW, wasH, wasGH = up.w, up.h, up.GetHeight
	up.w, up.h = 1920, 1080
	up.GetHeight = function(self) return self.h end
	grip.scripts.OnUpdate(grip, 0.02)
	eq(frame.w, 1880, "with the screen known: the screen less a margin"); eq(frame.h, 1040, "both ways")
	up.w, up.h, up.GetHeight = wasW, wasH, wasGH
	mouse = { 600, 250 }
	grip.scripts.OnUpdate(grip, 0.02)
	grip.scripts.OnMouseUp(grip)
	eq(A.DT.db.size[1], 1100, "let go: the size is saved"); eq(A.DT.db.size[2], 650, "both ways"); eq(grip.scripts.OnUpdate, nil, "and the pulling is over")
	-- let go where the corner did not hear of it
	grip.scripts.OnMouseDown(grip)
	down = false
	grip.scripts.OnUpdate(grip, 0.02)
	eq(grip.scripts.OnUpdate, nil, "the button let go elsewhere: the window is put down, not left hanging on the mouse")
	frame.SetSize, frame.StartSizing, frame.GetWidth, frame.GetHeight = wasSize, wasStart, nil, nil
	e.GetCursorPosition, e.IsMouseButtonDown = nil, nil
end)()

local firstRow
for _, w in ipairs(A.widgets) do if w.cells and not firstRow then firstRow = w end end
eq(firstRow.id, 100, "newest first by default")
local header
for _, w in ipairs(A.widgets) do if w.col and w.col.key == "p" then header = w end end
click(header)
check(firstRow.cells.p.text == "3s 0c" and firstRow.id == 400, "sorted by price, dearest first")
click(header)
eq(firstRow.id, 7000, "and cheapest first")
for _, w in ipairs(A.widgets) do
	if w.col then
		click(w)
		click(w)
	end
end

click(firstRow)
eq(V.selected, firstRow.id, "a row is selected")
local detail
for _, w in ipairs(A.widgets) do
	if w.kind == "FontString" and type(w.text) == "string" and w.text:find("observations on", 1, true) then detail = w end
end
check(detail and detail.text:find("7-day median", 1, true), "the detail shows its figures")
local id = V.selected
click(find("Button", "Favourite"))
check(A.M.db.favs[id], "starred")
click(section("Favourites"))
eq(shown(), 1, "favourites only")
click(section("All items"))
click(find("Button", "Unfavourite"))
eq(A.M.db.favs[id], nil, "unstarred")

local ah = find("Button", "Check price at AH")
eq(ah.enabled, false, "no price check away from the auction house")
A.fire("AUCTION_HOUSE_SHOW")
step(1)
eq(ah.enabled, true, "possible at the auction house")
click(ah)
eq(A.queries[1], id, "one search, for that item")
A.fire("AUCTION_HOUSE_CLOSED")

search.focus = true
A.env.ChatEdit_InsertLink("|cffffffff|Hitem:821::|h[Herb]|h|r")
eq(search.text, "Herb", "a shift-clicked link fills the search box")
search.focus = false
A.env.ChatEdit_InsertLink("|cffffffff|Hitem:100::|h[Copper Bar]|h|r")
eq(search.text, "Herb", "only while the box has the cursor")
search:SetText("")

-- Every script of every widget is run (hover, click with both buttons, wheel, drag, typing), on every tab.
-- Nothing may raise an error and no text may show a formatting accident.
local function UseEverything(label)
	for _, tab in ipairs({ "home", "market", "inventory", "fish", "food", "npc", "quest", "item", "zone", "combat", "bis", "tools", "settings" }) do
		A.slash(tab)
		for _, w in ipairs(A.widgets) do
			local s = w.scripts
			if s.OnEnter then s.OnEnter(w) end
			if s.OnLeave then s.OnLeave(w) end
			if s.OnMouseWheel then
				s.OnMouseWheel(w, -1)
				s.OnMouseWheel(w, 1)
			end
			if s.OnDragStart then
				s.OnDragStart(w)
				s.OnDragStop(w)
			end
			if s.OnEnterPressed then
				w:SetText("er")
				s.OnEnterPressed(w)
				s.OnEscapePressed(w)
			end
			if s.OnClick and w.enabled ~= false then
				click(w, "LeftButton")
				click(w, "RightButton")
				A.slash(tab) -- a tab button may have switched tabs
			end
		end
		step(0.5)
		for _, w in ipairs(A.widgets) do
			if type(w.text) == "string" then
				check(not w.text:find("nil", 1, true) and not w.text:find("%%[ds]"), label .. ", " .. tab .. ": bad text '" .. w.text .. "'")
			end
		end
	end
end
eq(A.DT.UI:SelfTest(), 0, "the in-game self test passes")
check(A.printed[#A.printed]:find("checks passed", 1, true), "and says so")
UseEverything("with prices")
V.qualities = nil
V.selected = next(A.items())
UseEverything("with a selection")
V.qualities, V.minLevel, V.maxLevel, V.usable = nil, nil, nil, nil
eq(#A.queries, 1, "no amount of clicking searches the auction house while it is closed")
A.slash("market")
A.slash("")

-- the scan button: only at the auction house, only on a click; one list read page by page
local scanB = find("Button", "Scan Auction House")
eq(scanB.enabled, false, "no scan away from the auction house"); eq(#A.browseQueries, 0, "and none was ever sent unasked")
A.fire("AUCTION_HOUSE_SHOW")
step(1)
eq(scanB.enabled, true, "possible at the auction house")
A.pages = { { { itemKey = { itemID = 821 }, minPrice = 3, totalQuantity = 40 } }, { { itemKey = { itemID = 830 }, minPrice = 8, totalQuantity = 9 } } }
A.browse = {}
local scanPopup = A.env.StaticPopupDialogs.DAWNTOOLS_SCAN
click(scanB)
eq(A.popups[#A.popups], "DAWNTOOLS_SCAN", "the button asks which kind of scan"); eq(#A.browseQueries, 0, "and sends nothing yet")
scanPopup.OnAccept()
eq(#A.browseQueries, 1, "quick: one list query"); eq(scanB.enabled, false, "and the button waits")
scanPopup.OnAccept()
eq(#A.browseQueries, 1, "a second one sends nothing more")
step(1)
eq(A.more, 0, "the next page is not asked for before the first has come")
A.page()
step(1)
eq(A.more, 1, "then it is")
A.page()
step(2)
eq(A.items()[821].p, 3, "prices from the first page"); eq(A.items()[830].p, 8, "and from the next")
check(A.M.scanStatus:find("Scan done: 2 items", 1, true), "the scan says when it is done"); eq(scanB.enabled, true, "and can be run again")
step(5)
eq(#A.browseQueries, 1, "it does not repeat itself"); eq(A.more, 1, "nor ask for pages there are not")
A.pages = { {}, {} }
scanPopup.OnAccept()
A.fire("AUCTION_HOUSE_CLOSED")
step(2)
check(A.M.scanStatus:find("closed", 1, true), "closing the auction house ends a scan"); eq(A.more, 1, "at once")
-- the full scan: every auction, real buyouts; once per 15 minutes
A.pages = {}
A.fire("AUCTION_HOUSE_SHOW")
step(1)
A.M.db.lastFull = nil
eq(A.M:FullWait(), 0, "a full scan is possible when none was run")
A.replicate = { { 821, 5, 500 }, { 821, 1, 90 }, { 830, 2, 60 } }
scanPopup.OnAlt()
eq(A.replicated, 1, "full: asks the game for every auction"); eq(scanB.enabled, false, "and the button waits")
check(A.M:FullWait() > 14 * 60, "the 15 minutes count from the asking")
A.fire("REPLICATE_ITEM_LIST_UPDATE")
step(2)
eq(A.items()[821].p, 90, "the lowest buyout for one"); eq(A.items()[830].p, 30, "a stack's buyout is shared out")
check(A.M.scanStatus:find("Full scan done: 3 auctions, 2 items", 1, true), "it says when it is done"); eq(scanB.enabled, true, "and the button is free again")
scanPopup.OnAlt()
local fullB = { SetEnabled = function(self, on) self.on = on end }
scanPopup.OnShow({ button3 = fullB })
eq(fullB.on, false, "the popup greys Full out while it is not possible")
eq(A.replicated, 1, "no second one inside 15 minutes"); check(A.M.scanStatus:find("possible again in 15 min", 1, true), "it says how long")
scanPopup.OnAccept()
eq(#A.browseQueries, 3, "a quick scan works meanwhile")
A.fire("AUCTION_HOUSE_CLOSED")
step(2)
-- cancelled: the auction house closes before the answer is read
A.fire("AUCTION_HOUSE_SHOW")
step(1)
A.M.db.lastFull = nil
A.replicate = { { 821, 1, 7 } }
scanPopup.OnShow({ button3 = fullB })
eq(fullB.on, true, "and offers it when it is")
scanPopup.OnAlt()
A.fire("AUCTION_HOUSE_CLOSED")
A.fire("REPLICATE_ITEM_LIST_UPDATE")
step(2)
check(A.M.scanStatus:find("cancelled: nothing recorded", 1, true), "closing the auction house cancels a full scan")
eq(A.items()[821].p, 90, "and nothing of it is recorded"); check(A.M:FullWait() > 14 * 60, "but the game's turn is used up"); eq(scanB.enabled, false, "the button is off away from the auction house")

-- Inventory: bags always, the bank while it is open; every character of the account; nothing to the guild
local Inv, me = A.DT.Inventory, "Player-Alice"
local Count = A.env.DawnInventory.API.Count
A.bags, A.bank = { { 110, 16 }, { 110, 4 }, 100 }, { { 100, 8 } }
A.fire("BAG_UPDATE_DELAYED")
eq(Count(110), 20, "stacks in the bags add up"); eq(Count(100), 1, "a slot without a stack size is one")
eq(select(2, Count(100)), 0, "the bank is not known before it was opened")
A.bankOpen = true
A.fire("BANKFRAME_OPENED")
eq(select(2, Count(100)), 8, "the bank is read when it opens")
A.bankOpen = false
A.fire("BANKFRAME_CLOSED")
A.bags = { { 110, 2 } }
A.fire("BAG_UPDATE_DELAYED")
eq(Count(110), 2, "the bags follow"); eq(select(2, Count(100)), 8, "the bank stays as last seen")
eq(Count(110, "Player-Nobody"), 0, "an unknown character has nothing")
Inv.db.chars["Player-Alt"] = { name = "Alice Alt", class = "DRUID", bags = { [110] = 5 }, bank = {} }
eq(Count(110, "Player-Alt"), 5, "another character's bags")
A.slash("inventory")
local function text(part)
	for _, w in ipairs(A.widgets) do
		if w.kind == "FontString" and w.shown ~= false and type(w.text) == "string" and w.text:find(part, 1, true) then return w.text end
	end
end
local function invRow(id)
	for _, w in ipairs(A.widgets) do
		if w.invRow and w.shown ~= false and w.id == id then
			local c = w.cols
			return c.bags.text .. " / " .. c.bank.text .. " / " .. c.total.text .. " / " .. c.all.text .. " / " .. c.who.text
		end
	end
end
local NONE = "|cff555555-|r"
Inv.Pick(nil) -- (the sweep over every button above picked something)
check(text("2 items"), "this character's items, to begin with"); eq(Inv.showButton.label.text, "|cffffffffAlice Smith|r", "the button says whose")
eq(invRow(110), "2 / " .. NONE .. " / 2 / |cffffd1007 / |cffffffffAlice Smith|r 2, |cffffffffAlice Alt|r 5",
	"bags, bank, total, then all characters together (gold: others have some), and who holds it, this character first")
eq(invRow(100), NONE .. " / 8 / 8 / 8 / |cffffffffAlice Smith|r 8", "what is in the bank; all characters = mine where nobody else has any")
check(not text("Bank not seen yet"), "and no word of another character's bank")
-- the list under the button
click(Inv.showButton)
local entries = Inv.menu.entries
eq(Inv.menu.shown, true, "a click on the button opens the list"); eq(#entries, 3, "this character, all, the other one")
eq(entries[1].label.text, "|cffffd100> |r|cffffffffAlice Smith|r", "the one shown is marked"); eq(entries[2].label.text, "   All characters", "all of them")
eq(entries[1].forget.shown, false, "this character cannot be forgotten"); eq(entries[3].forget.shown, true, "another can")
click(entries[2])
eq(Inv.menu.shown, false, "a pick closes the list"); eq(Inv.showButton.label.text, "All characters", "and is shown")
check(text("2 items"), "both items listed"); check(text("Bank not seen yet on: |cffffffffAlice Alt"), "and which bank was never opened")
eq(invRow(110), "7 / " .. NONE .. " / 7 / 7 / |cffffffffAlice Smith|r 2, |cffffffffAlice Alt|r 5", "everyone's bags added up")
Inv.db.chars[me].bags[100] = 3
Inv.Refresh()
eq(invRow(100), "3 / 8 / 11 / 11 / |cffffffffAlice Smith|r 11", "bags and bank side by side, with their sum")
click(Inv.showButton)
click(entries[3])
eq(Inv.showButton.label.text, "|cffffffffAlice Alt|r", "the other character"); check(text("1 items") and not invRow(100), "alone")
eq(invRow(110), "5 / " .. NONE .. " / 5 / |cffffd1007 / |cffffffffAlice Smith|r 2, |cffffffffAlice Alt|r 5", "its own figures")
-- a character that was deleted is forgotten from the list
Inv.db.chars["Player-Gone"] = { name = "Gone", class = "MAGE", bags = { [110] = 50 }, bank = {} }
click(Inv.showButton)
click(Inv.showButton)
click(Inv.showButton)
eq(#entries, 4, "a further character is in the list")
click(entries[4].forget)
eq(A.popups[#A.popups], "DAWNTOOLS_INV_FORGET", "the x asks first"); check(Inv.db.chars["Player-Gone"], "and forgets nothing yet")
Inv.Pick("Player-Gone")
A.env.StaticPopupDialogs.DAWNTOOLS_INV_FORGET.OnAccept(nil, "Player-Gone")
eq(Inv.db.chars["Player-Gone"], nil, "yes: its bags and bank are gone"); eq(Inv.showButton.label.text, "|cffffffffAlice Smith|r", "and the list is back on this character")
eq(invRow(110), "2 / " .. NONE .. " / 2 / |cffffd1007 / |cffffffffAlice Smith|r 2, |cffffffffAlice Alt|r 5", "its units no longer count")
Inv.Forget(me)
check(Inv.db.chars[me], "this character is never forgotten")
Inv.Pick("all")
for _, w in ipairs(A.widgets) do
	if w.kind == "EditBox" and w.shown ~= false and w ~= search then w:SetText("ore") end
end
step(0.5)
check(text("1 items"), "search by part of a name")
check(not A.DT.modules.inventory.hello and not A.DT.modules.inventory.onMessage, "the module has nothing to say to the guild")
eq(A.env.SLASH_DAWNTOOLS_INVENTORY1, "/dtinv", "its short command")

-- Settings sits apart from the working tabs
check(find("Button", "Settings") and find("Button", "Inventory"), "tab buttons")

-- Weapons in the categories: One-Handed and the like, the weapon types under the group picked
A.slash("market")
click(section("All items"))
click(section("Weapons"))
local oneHanded = section("One-Handed")
check(oneHanded, "weapons open into their groups"); eq(oneHanded.text.text, "    One-Handed", "indented once")
check(not section("Two-Handed"), "a group nothing was seen of is not listed"); check(not section("Sub 0"), "the types wait for their group")
click(oneHanded)
eq(V.group, "1h", "a group picked"); check(section("Sub 0"), "shows its weapon types")
eq(section("Sub 0").text.text, "        Sub 0", "indented twice")
for _, w in ipairs(A.widgets) do
	if w.cells and w.shown then eq(ITEMS[w.id][6], 2, "only weapons are listed") end
end
click(section("Sub 0"))
eq(V.leaf, 0, "a weapon type picked")
click(section("Sub 0"))
check(V.leaf == nil and V.group == "1h", "clicked again: back to its group")
click(section("One-Handed"))
check(V.group == nil and V.class == 2, "the group clicked again: back to all weapons")
click(section("All items"))
check(V.group == nil and V.class == nil, "and out again")

-- Armor: by type, then by where it is worn; a cloak is filed under Miscellaneous, as the auction house has it
ITEMS[900] = { "Plate Helm", 2, 1, 500, false, 4, 4, slot = "INVTYPE_HEAD" }
ITEMS[901] = { "Linen Cloak", 1, 1, 50, false, 4, 1, slot = "INVTYPE_CLOAK" }
ITEMS[902] = { "Plate Gloves", 2, 1, 400, false, 4, 4, slot = "INVTYPE_HAND" }
ITEMS[903] = { "Plate Robe", 2, 1, 400, false, 4, 4, slot = "INVTYPE_ROBE" }
for id = 900, 903 do
	A.searched[id] = { { 100 + id, 1 } }
	A.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = id })
end
step(3)
eq(A.items()[900].e, "INVTYPE_HEAD", "where an item is worn is kept with it")
local function listed()
	local ids = {}
	for _, w in ipairs(A.widgets) do
		if w.cells and w.shown then ids[#ids + 1] = w.id end
	end
	table.sort(ids)
	return table.concat(ids, " ")
end
local function labels()
	local out = {}
	for _, w in ipairs(A.widgets) do
		if w.entry and w.shown then out[#out + 1] = w.entry.label end
	end
	return table.concat(out, ",")
end
click(section("Armor"))
check(labels():find("Armor,Sub 4,Sub 0", 1, true), "armor opens into its types: plate, then miscellaneous for the cloak")
eq(listed(), "900 901 902 903", "all armor")
click(section("Sub 4"))
check(labels():find("Sub 4,INVTYPE_HEAD,INVTYPE_CHEST,INVTYPE_HAND,Sub 0", 1, true), "a type opens into its slots, in the auction house's order")
eq(listed(), "900 902 903", "plate only")
click(section("INVTYPE_HAND"))
eq(listed(), "902", "one slot")
click(section("INVTYPE_CHEST"))
eq(listed(), "903", "a robe is a chest piece")
click(section("Sub 0"))
check(labels():find("Sub 0,INVTYPE_CLOAK", 1, true), "miscellaneous has the cloak slot"); eq(listed(), "901", "and the cloak")
click(section("All items"))

-- Vendors: what a shop sells is recorded when it is opened, and shown beside the auction price
local shop = { { 100, 400, 20, -1 }, { 110, 9000, 1, 2 }, { 821, 50, 5, -1, true } } -- item, price, stack, left, other cost
A.env.GetMerchantNumItems = function() return #shop end
A.env.GetMerchantItemID = function(i) return shop[i][1] end
A.env.C_MerchantFrame = { GetItemInfo = function(i)
	return { price = shop[i][2], stackCount = shop[i][3], numAvailable = shop[i][4], hasExtendedCost = shop[i][5] or false }
end }
A.env.GetRealZoneText = function() return "Stranglethorn Vale" end
A.env.GetSubZoneText = function() return "Booty Bay" end
A.npcName = "Kira"
A.fire("MERCHANT_SHOW")
step(1)
local GetVendor = A.env.DawnMarket.API.GetVendor
local vp, vname, vzone, vlimited = GetVendor(100)
eq(vp, 20, "a vendor's price for one"); eq(vname, "Kira", "who sells it"); eq(vzone, "Booty Bay, Stranglethorn Vale", "where"); eq(vlimited, false, "stock not limited")
eq(select(4, GetVendor(110)), true, "limited stock is marked"); eq(GetVendor(821), nil, "what is not paid for in money is left out")
A.npcName, shop = "Dearer Dan", { { 100, 2000, 20, -1 } }
A.fire("MERCHANT_SHOW")
eq(select(2, GetVendor(100)), "Kira", "the cheapest seller is kept")
A.npcName, shop = "Kira", { { 100, 600, 20, -1 } }
A.fire("MERCHANT_SHOW")
eq(GetVendor(100), 30, "a seller's own price is brought up to date")
A.npcName = nil
click(section("All items"))
;(function() -- vendor prices are rows of the store: they go to the guild with it, under the same switch, and no name is in them
	local V1, V2 = NewClient("Vera"), NewClient("Walt")
	local function open(c, npc, goods)
		c.env.GetMerchantNumItems = function() return #goods end
		c.env.GetMerchantItemID = function(i) return goods[i][1] end
		c.env.C_MerchantFrame = { GetItemInfo = function(i) return { price = goods[i][2], stackCount = 1, numAvailable = goods[i][3] or -1, hasExtendedCost = false } end }
		c.env.GetRealZoneText = function() return "Durotar" end
		c.env.GetSubZoneText = function() return "Razor Hill" end
		c.npcName = npc
		c.fire("MERCHANT_SHOW")
		c.npcName = nil
	end
	local first = #sent + 1
	local function whispers() -- (the store's sync: whispers of the game database since this block began)
		local n = 0
		for i = first, #sent do if sent[i].prefix == "DAWND" then n = n + 1 end end
		return n
	end
	local d1, d2 = V1.DT.DB, V2.DT.DB
	open(V1, "Grimtak", { { 7001, 40 }, { 7002, 500, 1 } })
	step(700)
	eq(whispers(), 0, "sharing not agreed to: a vendor's prices stay here"); eq(d2.Vendor(7001), nil, "and none come in"); eq(V1.M.db.vendors, nil, "(there is no saved table of them beside the store)")
	V1.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
	V2.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
	check(V1.env.StaticPopupDialogs.DAWNTOOLS_SHARE.text:find("what vendors", 1, true), "the question says vendor prices are part of it")
	step(700)
	-- Walt had nothing: the store's sync gives him what Vera saw
	local got = d2.Vendor(7001)
	eq(got and got.p, 40, "the price arrives"); eq(got.v, "Grimtak", "with the vendor"); eq(got.z, "Razor Hill, Durotar", "and the place")
	eq(d2.Row("vendor:7001").src, "guild", "as a row of what the guild learned"); eq(d2.Vendor(7002).l, true, "limited stock too")
	eq(select(1, V2.env.DawnMarket.API.GetVendor(7001)), 40, "and it is used like one seen here"); eq(d1.Root(), d2.Root(), "both hold the same")
	check(whispers() > 0, "by whisper, as the store goes")
	-- a new sighting travels by itself; one only seen again changes nothing
	open(V1, "Grimtak", { { 7001, 40 }, { 7003, 9 } })
	step(700)
	eq(d2.Vendor(7003).p, 9, "something new at a vendor is taken in")
	local root, t = d1.Root(), d1.Row("vendor:7001").t
	step(100)
	open(V1, "Grimtak", { { 7001, 40 }, { 7003, 9 } })
	eq(d1.Root(), root, "the same prices seen again: nothing changes"); eq(d1.Row("vendor:7001").t, t, "not even the time")
	-- a cheaper seller is kept; a seller's own price is brought up to date; between members the newer sighting stands
	open(V2, "Cheap Chad", { { 7003, 5 } })
	eq(d2.Vendor(7003).p, 5, "a cheaper seller is taken"); eq(d2.Vendor(7003).v, "Cheap Chad", "with its name")
	open(V2, "Dear Dan", { { 7003, 50 } })
	eq(d2.Vendor(7003).v, "Cheap Chad", "a dearer one is not")
	open(V2, "Cheap Chad", { { 7003, 6 } })
	eq(d2.Vendor(7003).p, 6, "the cheap one's own price is brought up to date")
	step(700)
	eq(d1.Vendor(7003).p, 6, "and the guild has it"); eq(d1.Root(), d2.Root(), "both hold the same")
	-- a name of a player is in none of it
	for chunk in pairs(d1.Hashes()) do
		check(not d1.Text(chunk):find("Vera", 1, true) and not d1.Text(chunk):find("Walt", 1, true), "no player's name in a row of " .. chunk)
	end
	-- rows from the wire are read for what they are
	local rows, at = {}, Now() + 100
	for key, values in pairs({ [7009] = { 0, 0, "X", "Y" }, [7010] = { 7, 0 }, [7011] = { 7, 0, "Good Name", "Pla" }, [7012] = { 7, 0, "Hon|cffff0000est Hal", "Here" }, [7013] = { 7, 0, "", "Here" } }) do
		rows[#rows + 1] = ("vendor:%d\t%d\tguild\t%s"):format(key, at, V1.DT.DBLogic.Pack(values, 4))
	end
	check(d1.Take("vendor:27", table.concat(rows, "\n")) == 5, "rows of any shape may come over the wire")
	eq(d1.Vendor(7012).p, 7, "the good one is read"); eq(d1.Vendor(7012).v, "Honcffff0000est Hal", "a name's colour code is taken apart")
	eq(d1.Vendor(7009), nil, "a price of nothing is not read"); eq(d1.Vendor(7010), nil, "nor a row without a vendor"); eq(d1.Vendor(7013), nil, "nor one with an empty name")
	eq(d1.Vendor(7011).v, "Good Name", "one with less than the whole is read as far as it goes")
	-- the counts, kept for the Data Sync page: the four old kinds are gone from it
	local totals = V1.DT.Comms:Totals()
	eq(totals.mods.vendors, nil, "no message is counted as the vendors' own any more"); check(totals.mods.core.i >= 1, "the hellos are")
	V1.slash("settings")
	V1.DT.UI:ShowSection("sync")
	local text = V1.DT.UI.syncText.text
	check(not text:find("Vendor price sharing", 1, true), "the Data Sync page has no line of their own: " .. text)
	check(text:find("Total|r  sent", 1, true) and text:find("Who has the addon", 1, true), "with the hellos and a total")
	check(text:find("%d+ vendor prices"), "and what is held: " .. text)
	-- how complete each kind of data is, as bars
	local bars, by = V1.DT.UI.syncBars, {}
	for _, b in ipairs(bars) do if b.shown then by[b.label.text] = b end end
	check(by["Auction prices"] and by["Vendor prices"] and by["Cooking recipes heard of"] and by["Quest rewards seen at a quest giver"], "a bar for each kind of data")
	check(by["Vendor prices"].count.text:find("of ?", 1, true), "what cannot be counted yet says so: " .. by["Vendor prices"].count.text); eq(by["Vendor prices"].fill.shown, false, "and has no bar")
	check(by["Vendor prices"].note.text:find("Items", 1, true), "with a word on what would count it")
	local wasItem = V1.DT.Item.Ready, V1.DT.Item.All
	local wasAll = V1.DT.Item.All
	V1.DT.Item.Ready = function() return true end
	V1.DT.Item.All = function() return { { id = 7001, src = { Vendor = true } }, { id = 7002, src = { Vendor = true } }, { id = 8888, src = { Vendor = true } }, { id = 8889, src = { Vendor = true } }, { id = 9000, src = {} },
		{ id = 9001, c = 12, src = {} }, { id = 9002, c = 13, src = {} }, { id = 9003, src = {} }, { id = 9004, src = {} }, { id = 9005, src = {} } } end
	check(by["Auction prices"].count.text:find("of ?", 1, true), "auction prices cannot be set against anything before the items are read")
	local now = V1.DT.Now()
	V1.M.db.houses.H = { [7001] = { p = 5, q = 1, t = now - 100, d = {} }, [9003] = { p = 5, q = 1, t = now - 3 * 86400, d = {} } }
	V1.DT.UI:Refresh()
	eq(by["Auction prices"].count.text, "2 / 8  (25%)", "every item ever priced, against the items there are (quest items and keys left out)")
	eq(by["Auction prices"].subShare, 1 / 8, "a thin second bar for those seen in the last day"); eq(by["Auction prices"].sub.shown, true, "shown")
	check(by["Auction prices"].note.text:find("1 seen in the last day", 1, true), "and said in words: " .. by["Auction prices"].note.text)
	eq(by["Vendor prices"].sub.shown, false, "a bar without such a part has no second bar")
	eq(by["Vendor prices"].count.text, "2 / 4  (50%)", "counted against what vendors sell, once the items are read"); eq(by["Vendor prices"].share, 0.5, "the bar half full")
	V1.DT.Item.Ready, V1.DT.Item.All = wasItem, wasAll
	local sync, food
	for _, b in ipairs(V1.DT.UI.sectionButtons) do
		if b.id == "sync" then sync = b elseif b.id == "module:market" then food = b end
	end
	check(sync.gap > 0 and food.gap == 0 and V1.DT.UI.sectionLine, "a line and some room part Data Sync from the settings above it")
	-- the other addons it reads, and whether they are there
	V1.env.IsAddOnLoaded = function(name) return name == "QuestieDB" end
	V1.env.GetAddOnInfo = function(name) if name == "TomTom" then return name, name, "", false, "DISABLED" end return name, nil, nil, false, "MISSING" end
	eq(V1.DT.UI:AddonState("QuestieDB"), "loaded", "an addon that is loaded"); eq(V1.DT.UI:AddonState("TomTom"), "off", "one installed but switched off"); eq(V1.DT.UI:AddonState("Auctionator"), "missing", "one not there")
	V1.DT.UI:Refresh()
	local deps = V1.DT.UI.syncText.text
	check(deps:find("QuestieDB|r  |cff40ff40installed|r", 1, true) and deps:find("TomTom|r  |cffffd100installed, switched off|r", 1, true) and deps:find("Auctionator|r  |cff888888not installed|r", 1, true), "the page lists them with what they are for")
	V1.env.IsAddOnLoaded, V1.env.GetAddOnInfo = nil, nil
	-- Built-ins: the game's own switches
	;(function()
		local Bi, e, cvars = V1.DT.Builtins, V1.env, { autoLootDefault = "0", statusText = "0", statusTextDisplay = "NONE", Sound_EnableErrorSpeech = "1", enableMultiActionBars = "1" }
		V1.DT.UI:ShowSection("builtins")
		eq(Bi.boxes.autoLoot.enabled, false, "a client without the setting: its box cannot be ticked")
		check(Bi.boxes.autoLoot.label.text:find("not a setting of this client", 1, true), "and says why"); eq(Bi.boxes.raidParty, nil, "raid-style party frames are not offered: no setting to switch")
		e.GetCVar = function(name) return cvars[name] end
		e.SetCVar = function(name, value) cvars[name] = tostring(value) end
		V1.DT.UI:Refresh()
		eq(Bi.boxes.autoLoot.enabled, true, "with the setting: it can"); eq(Bi.boxes.autoLoot.checked, false, "and shows what the game is set to"); eq(Bi.boxes.errorSpeech.checked, false, "error speech still on: its box (silence it) is not ticked")
		Bi.boxes.autoLoot.checked = true
		click(Bi.boxes.autoLoot)
		eq(cvars.autoLootDefault, "1", "a tick sets the game's own setting")
		Bi.boxes.statusText.checked = true
		click(Bi.boxes.statusText)
		eq(cvars.statusText, "1", "status text on"); eq(cvars.statusTextDisplay, "BOTH", "as both number and percent"); eq(Bi.boxes.statusText.checked, true, "the box ticked")
		cvars.statusTextDisplay = "PERCENT"
		V1.DT.UI:Refresh()
		eq(Bi.boxes.statusText.checked, false, "changed in the game's menu to percent alone: the box is not ticked")
		local updated = 0
		e.MultiActionBar_Update = function() updated = updated + 1 end
		Bi.boxes.actionBars.checked = true
		click(Bi.boxes.actionBars)
		eq(cvars.enableMultiActionBars, "127", "all action bars: every bar's bit"); eq(updated, 1, "and the bars are told to look again")
		V1.combat = true
		Bi.boxes.errorSpeech.checked = true
		click(Bi.boxes.errorSpeech)
		eq(cvars.Sound_EnableErrorSpeech, "1", "in combat nothing is changed"); eq(Bi.boxes.errorSpeech.checked, false, "and the box goes back")
		V1.combat = false
		Bi.boxes.errorSpeech.checked = true
		click(Bi.boxes.errorSpeech)
		eq(cvars.Sound_EnableErrorSpeech, "0", "after it: ticked, error speech is off"); eq(Bi.boxes.errorSpeech.checked, true, "and the box stays ticked")
		Bi.boxes.errorSpeech.checked = false
		click(Bi.boxes.errorSpeech)
		eq(cvars.Sound_EnableErrorSpeech, "1", "unticked: the voice is back")
		for _, entry in ipairs(Bi.LIST) do check(Bi.boxes[entry.id], "a box for " .. entry.id) end
		e.GetCVar, e.SetCVar, e.MultiActionBar_Update = nil, nil, nil
		V1.DT.UI:ShowSection("sync")
	end)()
	click(V1.DT.UI.syncReset)
	eq(next(V1.DT.Comms:Totals().mods), nil, "the counting can be started anew"); check(V1.DT.UI.syncText.text:find("Nothing sent or received yet", 1, true), "and the page says so")
	leave(V1); leave(V2)
end)()
;(function() -- what quests give is a row of the store: it goes with it, where agreed to, with the level it was seen at
	local Q1, Q2 = NewClient("Quinn"), NewClient("Rosa")
	local function see(c, id, money, xp, level, given, choice)
		local e = c.env
		e.GetQuestID = function() return id end
		e.GetRewardMoney = function() return money end
		e.GetRewardXP = function() return xp end
		e.UnitLevel = function() return level end
		e.GetNumQuestRewards = function() return #given end
		e.GetNumQuestChoices = function() return #choice end
		e.GetQuestItemInfo = function(kind, i)
			local it = (kind == "reward" and given or choice)[i]
			return "x", nil, it[2], nil, nil, it[1]
		end
		c.fire("QUEST_DETAIL")
	end
	local first = #sent + 1
	local function whispers()
		local n = 0
		for i = first, #sent do if sent[i].prefix == "DAWND" then n = n + 1 end end
		return n
	end
	local d1, d2, seen2 = Q1.DT.DB, Q2.DT.DB, Q2.DT.Quest.SeenAll
	see(Q1, 501, 250, 900, 12, { { 6001, 1 } }, { { 6002, 1 }, { 6003, 5 } })
	step(700)
	eq(whispers(), 0, "not agreed to: what a quest gives stays here"); eq(seen2()[501], nil, "and none comes in"); eq(Q1.DT.modules.quest.db.seen, nil, "(there is no saved table of them beside the store)")
	check(Q1.env.StaticPopupDialogs.DAWNTOOLS_SHARE.text:find("the level you were", 1, true), "the question says what is sent, the level too")
	Q1.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
	Q2.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
	step(700)
	local got = seen2()[501]
	check(got, "a member who saw a quest's rewards: what they saw arrives with the store")
	eq(got.m, 250, "its money"); eq(got.x, 900, "its experience"); eq(got.l, 12, "the level it was seen at"); eq(d2.Row("qreward:501").src, "guild", "a row of what the guild learned")
	eq(#got.r, 1, "what is given"); eq(got.r[1][1], 6001, "by item"); eq(#got.c, 2, "what there is to choose from"); eq(got.c[2][1], 6003, "by item"); eq(got.c[2][2], 5, "and how many")
	local r = Q2.DT.Quest.Rewards({ id = 501, name = "Q501", level = 12 })
	eq(r.seen, true, "the tab knows it as seen"); eq(r.money, 250, "its money"); eq(#r.items, 3, "and items")
	-- a new sighting goes out by itself, one only seen again changes nothing
	see(Q1, 502, 0, 40, 12, {}, {})
	step(700)
	eq(seen2()[502].x, 40, "a quest seen for the first time is taken in")
	local root = d1.Root()
	see(Q1, 502, 0, 40, 12, {}, {})
	eq(d1.Root(), root, "looked at again, nothing changed: nothing is written")
	-- the newer look stands, on both machines
	see(Q2, 501, 250, 700, 30, { { 6001, 1 } }, { { 6002, 1 }, { 6003, 5 } }) -- (Rosa is level 30: less experience)
	eq(seen2()[501].x, 700, "my own later look at the quest giver replaces what the guild said")
	step(700)
	eq(Q1.DT.Quest.SeenAll()[501].x, 700, "and the guild has it"); eq(d1.Root(), d2.Root(), "both hold the same")
	for chunk in pairs(d1.Hashes()) do
		check(not d1.Text(chunk):find("Quinn", 1, true) and not d1.Text(chunk):find("Rosa", 1, true), "no player's name in a row of " .. chunk)
	end
	-- rows from the wire are read for what they are
	local at, DL = Now() + 100, Q2.DT.DBLogic
	local text = ("qreward:777\t%d\tguild\t%s\nqreward:778\t%d\tguild\t%s\nqreward:779\t%d\tguild\t%s"):format(at, DL.Pack({ 5, 5, 200, {}, {} }, 5), at, DL.Pack({ 5, 5, 5, { 1, 1, 2, 2 }, {} }, 5), at, DL.Pack({ 5, 5, 5, { 1 }, {} }, 5))
	check(d2.Take("qreward:3", text) == 3, "rows of any shape may come over the wire")
	Q2.DT.DBSeed.Rebuild()
	eq(seen2()[777], nil, "a level that cannot be is not read"); eq(seen2()[778] and #seen2()[778].r, 2, "(a good row is)"); eq(seen2()[779], nil, "an odd list of items is not read either")
	leave(Q1); leave(Q2)
end)()
;(function() -- Chat History: Up and Down in the chat line, and what was sent kept for the next login
	local function Box()
		local box = { alt = "untouched", history = {} }
		box.SetAltArrowKeyMode = function(self, on) self.alt = on end
		box.AddHistoryLine = function(self, text) self.history[#self.history + 1] = text end
		return box
	end
	local X = NewClient("Hugo")
	local H = X.DT.ChatHistory
	local one, two = Box(), Box()
	X.env._G.ChatFrame1EditBox, X.env._G.ChatFrame2EditBox = one, two
	X.env.NUM_CHAT_WINDOWS = 3
	X.fire("UPDATE_CHAT_WINDOWS")
	eq(H.db.settings.on, false, "off to begin with"); eq(one.alt, true, "the chat line is left as the game has it: the arrows only with Alt")
	X.DT.Tools.Open("chathistory")
	local tab
	for _, w in ipairs(X.DT.Tools.buttons) do if w.id == "chathistory" then tab = w end end
	H.boxes.on.checked = true
	click(H.boxes.on)
	eq(one.alt, false, "ticked: the plain arrow keys reach the chat line"); eq(two.alt, false, "of every chat window"); eq(tab.text, "|cff40ff40Chat History|r", "and its sub-tab is green")
	-- what the game adds to its history is kept
	one:AddHistoryLine("hello there")
	one:AddHistoryLine("hello there")
	two:AddHistoryLine("/dance")
	eq(#H.db.lines, 2, "a line sent is kept; the same twice running, once"); eq(H.db.lines[2], "/dance", "from whichever chat window")
	check(H.boxes.on and X.DT.Tools.Show, "(the page)")
	for i = 1, 60 do one:AddHistoryLine("line " .. i) end
	eq(#H.db.lines, 50, "the last fifty are kept"); eq(H.db.lines[50], "line 60", "the newest last"); eq(H.db.lines[1], "line 11", "the oldest gone")
	H.boxes.keep.checked = false
	click(H.boxes.keep)
	one:AddHistoryLine("not this one")
	eq(H.db.lines[50], "line 60", "remembering switched off: nothing more is kept")
	H.boxes.keep.checked = true
	click(H.boxes.keep)
	H.boxes.on.checked = false
	click(H.boxes.on)
	eq(one.alt, true, "unticked: back to the arrows with Alt")
	H.boxes.on.checked = true
	click(H.boxes.on)
	-- the next login: the lines are handed back to the game's history, and not kept a second time
	leave(X)
	local Y = NewClient("Hugo", { db = X.env.DawnToolsDB })
	local three = Box()
	Y.env._G.ChatFrame1EditBox = three
	Y.fire("UPDATE_CHAT_WINDOWS")
	local Hy = Y.DT.ChatHistory
	eq(three.alt, false, "the switch is remembered"); eq(#three.history, 50, "the lines kept are handed back to the chat line"); eq(three.history[1], "line 11", "oldest first")
	eq(three.history[50], "line 60", "so that Up brings the newest back first"); eq(#Hy.db.lines, 50, "and they are not kept a second time")
	Y.fire("UPDATE_CHAT_WINDOWS")
	eq(#three.history, 50, "nor handed back twice")
	Y.DT.Tools.Open("chathistory")
	click(Hy.forget)
	eq(#Hy.db.lines, 0, "Forget empties what was kept")
	leave(Y)
end)()
;(function() -- Favourites: the tab with the star; an Alt-click anywhere makes an item one
	local X = NewClient("Fern")
	local Favs, e = X.DT.Favs, X.env
	local tab
	for _, tb in ipairs(X.DT.UI:TabList(true)) do if tb.id == "favs" then tab = tb end end
	check(tab and tab.icon, "a tab of its own, with a picture for a name")
	local order = {}
	for i, tb in ipairs(X.DT.UI:TabList(true)) do order[tb.id] = i end
	eq(order.favs, order.market + 1, "beside Market")
	eq(Favs.Is(872), false, "nothing is a favourite to begin with")
	local tip = e.GameTooltip
	local was = tip.lines
	tip.lines = {}
	Favs.Hint(tip, 872)
	check(tip.lines[1]:find("Alt-click: make it a favourite", 1, true), "an item's tooltip says what an Alt-click does")
	Favs.Toggle(872)
	tip.lines = {}
	Favs.Hint(tip, 872)
	check(tip.lines[1]:find("Alt-click: no longer a favourite", 1, true), "and the other way for one that is a favourite")
	Favs.Toggle(872)
	tip.lines = was
	eq(Favs.Toggle(872, "Rockslicer"), true, "made one"); eq(Favs.Is(872), true, "and it is"); check(X.printed[#X.printed]:find("Rockslicer: a favourite now", 1, true), "said in chat")
	eq(X.M.db.favs[872], true, "kept where the Market tab keeps its own: one list for both")
	eq(Favs.Toggle(872), false, "and unmade")
	-- Alt-click on an item row of ours
	e.IsAltKeyDown = function() return true end
	eq(X.DT:LinkClick("LeftButton", "[x]", "Rockslicer", "url", 872), true, "an Alt-click on an item row is dealt with"); eq(Favs.Is(872), true, "it makes the item a favourite")
	eq(X.DT:LinkClick("LeftButton", "[q]", "A quest", "url"), false, "a row that is no item is left alone")
	-- Alt-click anywhere in the game
	X.DT.FavTab.OnModifiedClick("|cffffffff|Hitem:1475::::|h[Large Venom Sac]|h|r")
	eq(Favs.Is(1475), true, "an Alt-click on an item anywhere in the game makes it one too")
	e.IsShiftKeyDown = function() return true end
	X.DT.FavTab.OnModifiedClick("|cffffffff|Hitem:2589::::|h[Linen Cloth]|h|r")
	eq(Favs.Is(2589), false, "not with Shift held as well: that is the game's own click")
	e.IsShiftKeyDown = nil
	e.IsAltKeyDown = function() return false end
	X.DT.FavTab.OnModifiedClick("|cffffffff|Hitem:2589::::|h[Linen Cloth]|h|r")
	eq(Favs.Is(2589), false, "nor without Alt")
	-- the tab
	X.items()[872] = { p = 5000, q = 1, t = Now(), o = "", d = {} }
	X.DT.UI:Show("favs")
	local rows = {}
	for _, w in ipairs(X.widgets) do if w.vcols and w.shown and w.data then rows[#rows + 1] = w end end
	eq(#rows, 2, "the favourites are listed"); check(X.DT.FavTab.note.text:find("2 favourites", 1, true), "and counted")
	local rock
	for _, w in ipairs(rows) do if w.data.id == 872 then rock = w end end
	check(rock.data[5]:find("Drop|r  Rhahk'Zor, The Deadmines", 1, true), "where it comes from: the dungeon boss that drops it: " .. rock.data[5])
	eq(rock.data[6], X.DT.Money(5000), "its auction price")
	check(X.DT.FavTab.Where(2679):find("Made|r  Cooking", 1, true), "one a profession makes says which: " .. X.DT.FavTab.Where(2679))
	eq(X.DT.FavTab.Where(999999999), "", "one nothing is known of: nothing said")
	X.DT.FavTab.heads[6].scripts.OnClick(X.DT.FavTab.heads[6])
	rows = {}
	for _, w in ipairs(X.widgets) do if w.vcols and w.shown and w.data then rows[#rows + 1] = w end end
	eq(rows[1].data.id, 872, "a click on Auction: the dearest first")
	X.DT.FavTab.search:SetText("deadmines")
	X.DT.FavTab.Refresh()
	rows = {}
	for _, w in ipairs(X.widgets) do if w.vcols and w.shown and w.data then rows[#rows + 1] = w end end
	eq(#rows, 1, "the search box finds by where it comes from too")
	X.DT.FavTab.search:SetText("")
	e.IsAltKeyDown = function() return true end
	rows[1].scripts.OnMouseUp(rows[1], "LeftButton")
	eq(Favs.Is(872), false, "an Alt-click on a row here: no longer a favourite")
	e.IsAltKeyDown = nil
	Favs.Toggle(1475)
	X.DT.FavTab.Refresh()
	check(X.DT.FavTab.note.text:find("No favourites yet", 1, true), "none left: the tab says how to make one")
	leave(X)
end)()
;(function() -- World > Dungeons: the dungeons with their levels, the bosses of one and what they drop
	local X = NewClient("Dana")
	local Dg = X.DT.Dungeon
	-- the shipped list: no other addon needed
	local all = Dg.All()
	eq(#all, 35, "the shipped list: every dungeon that has loot known, without any other addon")
	local dm
	for i, d in ipairs(all) do
		if d.name == "The Deadmines" then dm = d end
		if i > 1 then check((all[i - 1].lo or 999) <= (d.lo or 999), "(the lowest first)") end
	end
	eq(dm.lo, 17, "a dungeon's levels"); eq(dm.hi, 26, "to"); eq(dm.bosses[1].name, "Rhahk'Zor", "its bosses in their order"); eq(dm.bosses[1].npc, 644, "by NPC")
	eq(dm.bosses[1].items[1], 872, "what a boss drops"); eq(dm.bosses[2].rare, true, "a rare one is marked"); eq(dm.bosses[#dm.bosses].name, "Trash", "and last what the other mobs drop")
	eq(Dg.Key("The Deadmines"), "deadmines", "a name as a key: its letters, without the The"); eq(Dg.Key("|cffffffffDeadmines|TInterface\\x:18|t|r"), "deadmines", "nor colour codes or pictures")
	X.DT.UI:Show("dungeon")
	local side = {}
	for _, w in ipairs(X.widgets) do if w.dungeon and w.shown then side[#side + 1] = w end end
	check(#side >= 5, "the dungeons on the left"); eq(side[1].label.text, all[1].name, "by name"); check(side[1].levels.text:find(tostring(all[1].lo), 1, true), "with their levels")
	eq(side[1].sel.shown, true, "the first is the one shown to begin with")
	local function rows()
		local out = {}
		for _, w in ipairs(X.widgets) do if w.dcols and w.shown and w.data then out[#out + 1] = w end end
		return out
	end
	Dg.db.picked = dm.key
	Dg.Refresh()
	local r = rows()
	-- (the first line is about its quests: not read on this client, and it says so)
	check(r[1].data[1]:find("Quests: open World", 1, true), "the picked dungeon: first a word on its quests")
	table.remove(r, 1)
	check(r[1].data.boss and r[1].data[1]:find("Rhahk'Zor", 1, true) and r[1].data[1]:find("[-]", 1, true), "then a boss, open"); eq(r[2].data.item, 872, "then what it drops")
	eq(r[2].data[5], "|cff888888-|r", "never seen to drop: a dash")
	-- a boss folds shut with a click, and that is remembered
	r[1].scripts.OnMouseUp(r[1], "LeftButton")
	eq(Dg.db.closed["644"], true, "a click on a boss folds it shut, and it is remembered")
	r = rows()
	table.remove(r, 1)
	check(r[1].data[1]:find("[+]", 1, true) and r[2].data.boss and r[2].data.boss.name ~= "Rhahk'Zor", "its drops are put away: the next boss follows")
	r[1].scripts.OnMouseUp(r[1], "LeftButton")
	eq(Dg.db.closed["644"], nil, "another click opens it again")
	-- the trash stands apart
	local list = {}
	for i = 1, 400 do local w = rows()[i] if not w then break end list[#list + 1] = w.data end
	local allRows, trashAt = {}, nil
	Dg.Refresh()
	for _, w in ipairs(X.widgets) do if w.dcols and w.data then allRows[#allRows + 1] = w.data end end
	check(#allRows > 0, "(rows)")
	-- my level range only: the list on the left
	local n = 0
	for _, w in ipairs(X.widgets) do if w.dungeon and w.shown then n = n + 1 end end
	Dg.mineBox.checked = true
	click(Dg.mineBox)
	local few = {}
	for _, w in ipairs(X.widgets) do if w.dungeon and w.shown then few[#few + 1] = w.dungeon end end
	check(#few > 0 and #few < 35, "My level range: only the dungeons about my level (10): " .. #few)
	for _, dg in ipairs(few) do check(10 >= dg.lo - 3 and 10 <= dg.hi + 5, "(" .. dg.name .. " is about my level)") end
	Dg.mineBox.checked = false
	click(Dg.mineBox)
	Dg.db.picked = dm.key
	Dg.Refresh()
	eq(Dg.db.hideDone, true, "done quests are hidden to begin with"); eq(Dg.doneBox.checked, true, "and the box shows it")
	Dg.doneBox.checked = false
	click(Dg.doneBox)
	eq(Dg.db.hideDone, false, "unticked: they are listed")
	Dg.doneBox.checked = true
	click(Dg.doneBox)
	-- whose quests
	eq(Dg.db.side, "H", "the quests of my own side to begin with"); check(Dg.sideButton.text:find("Horde", 1, true), "the button says so")
	click(Dg.sideButton)
	eq(Dg.db.side, "A", "a click: the other side"); click(Dg.sideButton); eq(Dg.db.side, "B", "then both"); click(Dg.sideButton); eq(Dg.db.side, "H", "and round again")
	r = rows()
	table.remove(r, 1)
	check(Dg.note.text:find("The Deadmines", 1, true) and Dg.note.text:find("bosses", 1, true), "the count says what is shown: " .. Dg.note.text)
	local went
	local wasWay = X.DT.Npc.Waypoint
	X.DT.Npc.Waypoint = function(to) went = to end
	r[1].scripts.OnMouseUp(r[1], "RightButton")
	eq(went and went.id, 644, "a right-click on a boss: a waypoint to it")
	X.DT.Npc.Waypoint = wasWay
	local linked
	local wasLink = X.env.GameTooltip.SetHyperlink
	X.env.GameTooltip.SetHyperlink = function(_, link) linked = link end
	r[2].scripts.OnEnter(r[2])
	eq(linked, "item:872", "hovering a drop shows the item")
	X.env.GameTooltip.SetHyperlink = wasLink
	-- the loot window of a boss, in a dungeon: what was in it is counted, once a corpse
	local e = X.env
	local loot, corpse = { { 872, 3 }, { 2589, 1 } }, "Creature-0-1-2-3-644-00000001"
	e.GetNumLootItems = function() return #loot end
	e.GetLootSourceInfo = function() return corpse end
	e.GetLootSlotLink = function(slot) return "|cffffffff|Hitem:" .. loot[slot][1] .. "::::|h[x]|h|r" end
	e.GetLootSlotInfo = function(slot) return "icon", "x", 1, nil, loot[slot][2] end
	X.fire("LOOT_OPENED")
	local kills, seen = Dg.Seen(dm.bosses[1])
	eq(kills, 1, "every corpse is counted (DB.Loot), a boss's too: it was looted once"); eq(seen[872], 1, "and its item seen once"); eq(seen[2589], nil, "a common thing is not counted")
	X.instance = true
	X.fire("LOOT_OPENED")
	eq((Dg.Seen(dm.bosses[1])), 1, "in a dungeon the same corpse is not counted again: the tab's count and the store's are one")
	X.fire("LOOT_READY")
	eq((Dg.Seen(dm.bosses[1])), 1, "the same corpse told twice: once")
	corpse, loot = "Creature-0-1-2-3-644-00000002", { { 7777, 4 } }
	X.fire("LOOT_OPENED")
	kills, seen = Dg.Seen(dm.bosses[1])
	eq(kills, 2, "another kill: twice"); eq(seen[7777], 1, "with something the list does not know")
	eq(X.DT.modules.dungeon.db.seen, nil, "(nothing is kept in the tab's own saved table)")
	-- a group that rolls: inside a dungeon it is counted as the tab always did, outside one it is not (not all of it is seen)
	e.IsInGroup, e.GetLootMethod = function() return true end, function() return "group" end
	corpse, loot = "Creature-0-1-2-3-" .. dm.bosses[2].npc .. "-00000005", { { 874, 3 } }
	X.fire("LOOT_OPENED")
	eq((Dg.Seen(dm.bosses[2])), 1, "in a dungeon a group that rolls is counted too")
	X.instance = false
	corpse = "Creature-0-1-2-3-" .. dm.bosses[2].npc .. "-00000006"
	X.fire("LOOT_OPENED")
	eq((Dg.Seen(dm.bosses[2])), 1, "outside one it is not")
	X.instance = true
	e.IsInGroup, e.GetLootMethod = nil, nil
	-- a boss with no NPC number in the list is told by its name
	corpse, loot = "Creature-0-1-2-3-424242-00000004", { { 6641, 3 } }
	e.UnitGUID = function(unit) return unit == "target" and corpse or "Player-Dana" end
	local wasName = e.UnitName
	e.UnitName = function(unit) if unit == "target" then return "Lordaeron Captain" end return wasName(unit) end
	X.fire("LOOT_OPENED")
	local captain = Dg.BossOf(nil, "Lordaeron Captain")
	eq((Dg.Seen(captain)), 1, "one without a number: by its name, under its dungeon"); eq(captain.npc, nil, "(a boss the list gives no NPC number)")
	eq((X.DT.DB.Looted("npc", 424242)), 1, "and, as every corpse, by the number the game gave it")
	e.UnitName = wasName
	X.instance = false
	Dg.Refresh()
	r = rows()
	table.remove(r, 1)
	check(r[1].data[5]:find("looted 2 times", 1, true), "the boss says how often it was looted: " .. r[1].data[5])
	-- the trash stands apart: a line of room before it, and a heading of its own
	local lines2 = {}
	Dg.search:SetText("")
	for i = 1, 60 do
		Dg.Refresh()
		for _, w in ipairs(rows()) do lines2[#lines2 + 1] = w.data end
		break
	end
	local sawTrash = false
	for _, dg in ipairs(Dg.All()) do
		if dg.key == dm.key then sawTrash = dg.bosses[#dg.bosses].name == "Trash" end
	end
	eq(sawTrash, true, "(the Deadmines have trash loot)")
	check(r[2].data[5]:find("1 of 2", 1, true) and r[2].data[5]:find("(50%)", 1, true), "an item how often it dropped: " .. r[2].data[5])
	local extra
	for _, w in ipairs(r) do if w.data.item == 7777 then extra = w.data end end
	check(extra and extra[1]:find("seen by the guild", 1, true), "what was seen and is not in the list is listed after it, marked")
	Dg.search:SetText("zzzz")
	Dg.Refresh()
	eq(#rows(), 0, "the search box leaves the drops it finds")
	Dg.search:SetText("")
	-- AtlasLoot, where installed: what the shipped list lacks, and its chances
	local Y = NewClient("Yara")
	local loaded = 0
	local store
	Y.env.LoadAddOn = function(name) if name == "AtlasLootClassic_DungeonsAndRaids" then loaded = loaded + 1 store = {
		__atlaslootdata = {},
		Deadmines = { name = "|cffffffffDeadmines|TInterface\\AddOns\\x:18:18|t|r", LevelRange = { 10, 17, 24 }, items = { { name = "Other Boss", npcID = 1, [1] = { { 1, 100 } } } } },
		Raid = { name = "Big Raid|TInterface\\AddOns\\x:18:18|t", LevelRange = { 60, 60, 60 }, items = {
			{ name = "Raid Boss", npcID = { 502, 503 }, [1] = { { 1, 100 }, { 16, "INV_Box_01", nil, "A heading" } }, [2] = { { 1, 100 }, { 2, 400 } } },
			{ name = "Nothing Dropper", [1] = { { 1, "INV_Box_01" } } } } },
	} end end
	Y.env.AtlasLoot = { ItemDB = { Get = function(_, name) return name == "AtlasLootClassic_DungeonsAndRaids" and store or nil end },
		Data = { Droprate = { GetData = function(_, npc, item) return npc == 644 and item == 872 and 12.5 or nil end } } }
	local Yd = Y.DT.Dungeon
	local both = Yd.All()
	eq(loaded, 1, "AtlasLoot's dungeon part is loaded when first asked for"); eq(#both, 36, "a raid the shipped list lacks is added; a dungeon it has is not listed twice")
	local raid, ydm
	for _, d in ipairs(both) do
		if d.name == "Big Raid" then raid = d elseif d.name == "The Deadmines" then ydm = d end
	end
	check(raid, "its name without AtlasLoot's badge"); eq(#raid.bosses, 1, "a boss that drops nothing is left out"); eq(raid.bosses[1].npc, 502, "a boss of several NPCs goes by the first")
	eq(table.concat(raid.bosses[1].items, ","), "100,400", "every list of its, each item once, headings left out")
	eq(ydm.bosses[1].name, "Rhahk'Zor", "the shipped dungeon stays as shipped")
	eq(Yd.Chance(ydm.bosses[1], 872), 12.5, "a chance the shipped list has not is AtlasLoot's"); eq(Dg.Chance(dm.bosses[1], 872), nil, "none without it")
	-- the guild: what was seen to drop is the store's counters: they pass with it, where agreed to
	local first = #sent + 1
	local function whispers()
		local n = 0
		for i = first, #sent do if sent[i].prefix == "DAWND" then n = n + 1 end end
		return n
	end
	step(700)
	eq(whispers(), 0, "not agreed to: what was seen stays here"); eq((Yd.Seen(ydm.bosses[1])), 0, "and none comes in")
	check(e.StaticPopupDialogs.DAWNTOOLS_SHARE.text:find("how often you looted it", 1, true), "the question says what is sent")
	e.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
	Y.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
	step(700)
	local kills, items = Yd.Seen(ydm.bosses[1])
	eq(kills, 2, "a member who looted bosses: what they counted arrives with the store"); eq(items[872], 1, "which items"); eq(items[7777], 1, "all of them")
	eq((Yd.Seen(Yd.BossOf(nil, "Lordaeron Captain"))), 1, "one known by its name too")
	for chunk in pairs(Y.DT.DB.Hashes()) do
		check(not Y.DT.DB.Text(chunk):find("Dana", 1, true) and not Y.DT.DB.Text(chunk):find("Yara", 1, true), "no player's name in a row of " .. chunk)
	end
	-- my own kill of the same boss adds to theirs, and is theirs in turn
	Y.env.GetNumLootItems = function() return 1 end
	Y.env.GetLootSourceInfo = function() return "Creature-0-1-2-3-644-00000009" end
	Y.env.GetLootSlotLink = function() return "|Hitem:872::::|h[x]|h" end
	Y.env.GetLootSlotInfo = function() return "icon", "x", 1, nil, 3 end
	Y.instance = true
	Y.fire("LOOT_OPENED")
	Y.instance = false
	kills, items = Yd.Seen(ydm.bosses[1])
	eq(kills, 3, "my own kill adds to the guild's"); eq(items[872], 2, "and its item")
	step(700)
	eq((Dg.Seen(dm.bosses[1])), 3, "so both of us see the same sum")
	local at = Now() + 100
	check(Y.DT.DB.Take("loot:2", ("loot:645:aaaaaa\t%d\tguild\t3;1:9"):format(at)) == 1, "a counter may come over the wire")
	local n645, seen645 = Y.DT.DB.Looted("npc", 645)
	eq(n645, 3, "its count"); eq(seen645[1], 3, "an item is never seen more often than the boss was looted")
	local bars = Y.DT.modules.dungeon.progress()
	check(bars[1][2] >= 2 and bars[1][3] > 250, "the bar: bosses whose loot was seen, of all: " .. bars[1][2] .. " / " .. bars[1][3])
	leave(Y)
	leave(X)
end)()
;(function() -- an installed OneForAll is a source of the dungeon list, as QuestieDB is of the NPCs: its rows go into the store, the later version stands, whole
	local function oneforall(version)
		return function(env)
			env.GetAddOnMetadata = function(addon, field) return addon == "OneForAll" and field == "Version" and version or nil end
			env.OneForAll = {
				DUNGEONS = {
					{ name = "The Deadmines", level = "17-26", bosses = {
						{ name = "Rhahk'Zor", npcID = 644, loot = { { id = 872 }, { id = 888001 } } },       -- one drop more than the seed has
						{ name = "Brand New Boss", npcID = 888500, rare = true, loot = { { id = 888002 } } }, -- a boss more
					}, trashLoot = { { id = 888004 } } },
					{ name = "Fresh Dungeon", level = "30-35", bosses = { { name = "Fresh Boss", loot = { { id = 888003 } } } } },
				},
				DUNGEON_DROP_CHANCE = { ["The Deadmines"] = { ["Rhahk'Zor"] = { [888001] = 7.5 } } },
			}
		end
	end
	local function seed(env)
		env.DawnToolsSeed = { OneForAllVersion = "7.0", Dungeons = { { "Hall of Tests", 13, 20, { { "First Boss", 9001, 0, { 872, 3.9 } } } } } }
	end
	local Z = NewClient("Zed", { globals = oneforall("6.2.12"), noData = true })
	local d, T = Z.DT.DB, Z.DT
	eq(d.Base("oneforall"), "6.2.12/4", "an installed OneForAll is written into the store, once per version"); eq(d.Row("base:oneforall").v, "6.2.12;4", "marked with its version and how many bosses it has")
	eq(d.Row("boss:1").v, "\"The Deadmines\",17,26,\"Rhahk'Zor\",644,0,{872,0,888001,7.5}", "a boss with its dungeon and what it drops, as the seed's rows are")
	eq(d.Row("boss:2").v, "\"The Deadmines\",17,26,\"Brand New Boss\",888500,1,{888002,0}", "a rare one"); eq(d.Row("boss:3").v, "\"The Deadmines\",17,26,\"Trash\",0,0,{888004,0}", "the trash last")
	eq(d.Row("boss:4").v, "\"Fresh Dungeon\",30,35,\"Fresh Boss\",0,0,{888003,0}", "a dungeon of its own, a boss with no number")
	eq(d.Row("boss:1").src, "oneforall", "of its source"); eq(d.Row("boss:1").t, 760212040, "of a time that is its version"); check(d.Row("fp:oneforall:boss:0"), "with the fingerprint of the chunk")
	eq(#T.Dungeons, 2, "the dungeon list is put together from them"); eq(T.Dungeon.DropOf(888003).name, "Fresh Boss", "the Dungeons tab has the new dungeon")
	local boss = T.Dungeon.DropOf(888001)
	eq(boss.name, "Rhahk'Zor", "a drop the seed has not, on its boss"); eq(T.Dungeon.Chance(boss, 888001), 7.5, "with its chance"); eq(T.Dungeon.DropOf(888004).name, "Trash", "and the trash")
	eq(T.modules.dungeonlist, nil, "the list sharing of before is gone"); eq(T.Dungeon.PutLine, nil, "and its lines"); eq(T.Dungeon.Additions, nil, "and its sync")
	local root = d.Root()
	leave(Z)
	local Z2 = NewClient("Zed", { db = Z.env.DawnToolsDB, noData = true, globals = oneforall("6.2.12") })
	eq(Z2.DT.DB.Root(), root, "the same version at the next login: nothing is written again")
	-- it passes to a member who has no OneForAll, with the rest of the store
	Z2.DT.db.settings.share = true
	local M1 = NewClient("Mo2", { noData = true })
	M1.DT.db.settings.share = true
	step(700)
	eq(M1.DT.DB.Root(), Z2.DT.DB.Root(), "shared: both hold the same"); check(M1.DT.Dungeon.DropOf(888003), "a member without OneForAll has the new dungeon")
	eq(M1.DT.Dungeon.Chance(M1.DT.Dungeon.DropOf(888001), 888001), 7.5, "with the chance")
	-- a row of its version that says something else is not taken by a member without it: it does not add up to the fingerprint
	local right, t0 = Z2.DT.DB.Row("boss:1").v, Z2.DT.DB.Row("boss:1").t
	eq(M1.DT.DB.Take("boss:0", ("boss:1\t%d\toneforall\tZZ Wrong"):format(t0)), 0, "rows that do not add up to the fingerprint are not taken"); eq(M1.DT.DB.Row("boss:1").v, right, "its own stand")
	leave(M1)
	leave(Z2)
	-- the seed holds 7.0, OneForAll 6.2.12: the later one is written whole, the other not at all: no mix
	local S1 = NewClient("Sid2", { globals = function(env) seed(env) oneforall("6.2.12")(env) end, noData = true })
	eq(S1.DT.DB.Row("base:oneforall").v, "7.0;1", "the seed is the later version: it is written"); eq(#S1.DT.Dungeons, 1, "alone"); eq(S1.DT.Dungeons[1][1], "Hall of Tests", "its dungeon")
	eq(S1.DT.Dungeon.DropOf(888003), nil, "nothing of the installed one's")
	leave(S1)
	-- the seed holds 7.0, OneForAll 7.1: the installed one is the later: it stands, and nothing of the seed with it
	local S2 = NewClient("Sid3", { globals = function(env) seed(env) oneforall("7.1")(env) end, noData = true })
	eq(S2.DT.DB.Row("base:oneforall").v, "7.1;4", "OneForAll is the later version: it is written"); eq(#S2.DT.Dungeons, 2, "alone"); eq(S2.DT.Dungeons[1][1], "The Deadmines", "its dungeons")
	eq(S2.DT.Dungeon.DropOf(872).name, "Rhahk'Zor", "and none of the seed's: no mix"); check(S2.DT.DB.Row("boss:1").v:find("The Deadmines", 1, true) and not S2.DT.DB.Row("boss:1").v:find("Hall of Tests", 1, true), "the first row is its own")
	-- and a seed that is the later one at last stands over the old rows
	leave(S2)
	local S3 = NewClient("Sid3", { db = S2.env.DawnToolsDB, globals = function(env)
		seed(env)
		env.DawnToolsSeed.OneForAllVersion = "7.2"
		oneforall("7.1")(env)
	end, noData = true })
	eq(S3.DT.DB.Row("base:oneforall").v, "7.2;1", "the next seed, the later again, replaces them"); eq(#S3.DT.Dungeons, 1, "and a shorter list leaves none of the old behind")
	leave(S3)
end)()
;(function() -- the profession tabs: every recipe from the shipped list, what it costs and earns, who knows it
	local P1, P2 = NewClient("Pat"), NewClient("Rex")
	local Craft = P1.DT.Craft
	eq(Craft.SpellLink(7421, "Enchant Bracer"), "|cffffd000|Henchant:7421|h[Enchant Bracer]|h|r", "a recipe that makes no item links as an enchantment where the game gives no link of its own")
	local function price(c, id, copper) c.items()[id] = copper and { p = copper, q = 1, t = Now(), o = "", d = {} } or nil end
	local function crafts(kind, from)
		local n = 0
		for _, m in ipairs(sent) do
			if m.text:find("^crafts\t" .. kind .. "\t") and (not from or m.from == from) then n = n + 1 end
		end
		return n
	end
	-- the shipped list
	local r = P1.DT.Recipes[7934] -- Anti-Venom: First Aid, three made from one Large Venom Sac
	eq(r[1], 129, "a recipe's profession"); eq(r[7], 6452, "what it makes"); eq(r[8], 3, "how many"); eq(r[9][1], 1475, "of what"); eq(r[9][2], 1, "and how much of it")
	eq(P1.DT.Recipes[7418][7], 0, "an enchantment makes no item")
	eq(Craft.ByItem(6452), 7934, "the recipe that makes an item is found")
	-- what it costs and earns
	local p = Craft.Profit(7934)
	eq(p.profit, nil, "no prices known: no profit said"); eq(p.missing[1], 1475, "and what has no price is named"); check(Craft.ProfitText(p):find("?", 1, true), "shown as a question mark")
	check(Craft.MatsText(p):find("+?", 1, true), "the materials too: " .. Craft.MatsText(p))
	price(P1, 1475, 100)
	p = Craft.Profit(7934)
	eq(p.mats, 100, "the materials at the auction price"); eq(p.profit, nil, "what is made has no price yet: still no profit")
	price(P1, 6452, 60)
	p = Craft.Profit(7934)
	eq(p.sells, 171, "what is made: three of them, less the house's 5%"); eq(p.profit, 71, "less the materials: the profit")
	check(Craft.ProfitText(p):find("|cff40ff40+", 1, true), "in green"); eq(Craft.MatsText(p), P1.DT.Money(100), "the materials as money")
	price(P1, 1475, 400)
	check(Craft.ProfitText(Craft.Profit(7934)):find("|cffff4040-", 1, true), "a loss in red")
	P1.DT.DB.Put("vendor:1475", P1.DT.DB.VendorText(30, false, "Sam", "Here"))
	local each, from = Craft.Cost(1475)
	eq(each, 30, "a material a vendor sells cheaper is counted at the vendor's price"); eq(from, "vendor", "and said so")
	eq(Craft.Profit(7934).profit, 141, "which the profit goes by")
	eq(select(2, Craft.Cost(2678)), "vendor", "the shipped vendor prices count too (Mild Spices)")
	local enchant = Craft.Profit(7418)
	eq(enchant.made, nil, "an enchantment: nothing made"); eq(enchant.profit, nil, "no profit"); check(Craft.ProfitText(enchant):find("-|r", 1, true), "a dash, not a question")
	eq(Craft.Profit(999999999), nil, "no such recipe: nothing")
	local tip = P1.env.GameTooltip
	local was = tip.lines
	tip.lines = {}
	Craft.ProfitTip(tip, Craft.Profit(7934))
	local text = table.concat(tip.lines, "|")
	check(text:find("1x", 1, true) and text:find("(vendor)", 1, true) and text:find("Sells for (3 made", 1, true) and text:find("Profit", 1, true), "the sum, line by line, for a tooltip: " .. text)
	tip.lines = was
	-- the tab: every recipe, without any profession window opened
	P1.DT.UI:Show("craft129")
	local view = Craft.views[129]
	check(#view.list >= 20, "First Aid lists its recipes from the shipped list: " .. #view.list)
	local row
	for _, d in ipairs(view.list) do if d.spell == 7934 then row = d end end
	check(row and row[3] == P1.DT.Money(30) and row[4]:find("+", 1, true), "a row has its materials and its profit: " .. tostring(row and row[4]))
	check(row[2]:find("|cffffff0080|r", 1, true), "its skill band"); eq(row[6], "|cff888888?|r", "and, the profession's window never opened, a question for whether I know it")
	check(view.countText.text:find("Open your First Aid window", 1, true), "the tab says how to find out")
	for _, d in ipairs(view.list) do check(d.kind ~= nil and d.sort[2] ~= nil, "(every row is whole)") break end
	-- sorted by profit: the best first
	view.heads[4].scripts.OnClick(view.heads[4])
	eq(view.list[1].spell, 7934, "a click on Profit: the one that earns most first")
	view.search:SetText("anti")
	view.Refresh()
	check(#view.list <= 2, "the search box narrows the list")
	view.search:SetText("")
	-- the profession's window: what this character has learned
	P1.env.C_TradeSkillUI = { GetAllRecipeIDs = function() return { 7934, 3275, 2538 } end, GetRecipeInfo = function(id) return { learned = id ~= 3275 } end }
	P1.fire("TRADE_SKILL_SHOW")
	step(2)
	local me = Craft.db.mine[Craft.me]
	eq(me.ids[7934], true, "a recipe learned is kept"); eq(me.ids[3275], nil, "one not learned is not"); eq(me.ids[2538], nil, "Cooking's are the Food tab's, not kept here")
	eq(me.lines[129], true, "the profession was read")
	view.Refresh()
	local known, missing
	for _, d in ipairs(view.list) do
		if d.spell == 7934 then known = d[6] elseif d.spell == 3275 then missing = d[6] end
	end
	eq(known, "|cff40ff40known|r", "known on its tab"); eq(missing, "|cffff4040missing|r", "what I lack, missing")
	P1.DT.UI:Show("craft171")
	eq(Craft.views[171].list[1][6], "|cff888888?|r", "another profession, never opened, still asks")
	check(Craft.views[129].list[1] and Craft.Makers(7934)[1] == "|cff40ff40You|r", "I am named among who can make it")
	-- the boxes beside the search box: what to list
	local function tick(key, on) view.ticks[key].checked = on; click(view.ticks[key]) end
	tick("known", true)
	eq(#view.list, 1, "Known: only what this character knows")
	tick("missing", true)
	check(#view.list > 1, "Missing: only what it lacks"); eq(view.ticks.known.checked, false, "and Known is unticked: both cannot be")
	for _, d in ipairs(view.list) do check(not d.known, "(none of them known)") break end
	tick("missing", false)
	tick("profit", true)
	eq(#view.list, 1, "Profitable: only what earns something"); eq(view.list[1].spell, 7934, "the one that does")
	tick("profit", false)
	tick("mats", true)
	eq(#view.list, 0, "Have mats: nothing while the bags hold none of the materials")
	local wasInv = P1.env.DawnInventory
	P1.env.DawnInventory = { API = { Count = function(id) return id == 1475 and 1 or 0, 0 end } }
	view.stale = true
	view.Refresh()
	eq(#view.list, 1, "with the materials in the bags: listed"); eq(view.list[1].spell, 7934, "the one I can make")
	P1.env.DawnInventory = wasInv
	tick("mats", false)
	-- sold to a vendor instead of on the auction house
	local pv = Craft.Profit(7934)
	eq(pv.vendorSells, nil, "(what a vendor pays is the game's figure: none known for this item here)"); check(Craft.ProfitText(pv, true):find("-|r", 1, true), "a dash where a vendor pays nothing")
	local wasInfo = P1.env.C_Item.GetItemInfo
	P1.env.C_Item.GetItemInfo = function(id) if id == 6452 then return "Anti-Venom", "[Anti-Venom]", 1, 1, 1, "", "", 20, "", 1, 50, 0, 0 end return wasInfo(id) end
	pv = Craft.Profit(7934)
	eq(pv.vendorSells, 150, "what a vendor pays for all that is made"); eq(pv.vendorProfit, 120, "less the materials: the profit at a vendor")
	check(Craft.ProfitText(pv, true):find("|cff40ff40+", 1, true), "shown in its own column's colours")
	P1.env.C_Item.GetItemInfo = wasInfo
	-- the Campsite: what every profession makes for the camp, together, each with its profession
	check(Craft.IsCamp(1229432) and Craft.IsCamp(1229737) and not Craft.IsCamp(7934), "a recipe for the camp is told from the rest (the tent, the campfire; not a potion)")
	P1.DT.UI:Show("craftcamp")
	local camp = Craft.views.camp
	check(#camp.list >= 30, "the Campsite lists them all: " .. #camp.list)
	local tent, fire
	for _, d in ipairs(camp.list) do
		if d.spell == 1229432 then tent = d elseif d.spell == 1229737 then fire = d end
	end
	eq(tent[2], "Leatherworking", "each with its profession, in a column of its own"); eq(fire[2], "Cooking", "Cooking's campfire among them")
	check(tent[3]:find("|cffffff0020|r", 1, true), "then its skill band, and the rest as on the other tabs")
	eq(tent[7], "|cff888888?|r", "a profession never opened on this character: a question")
	for _, d in ipairs(Craft.views[129].list) do check(not Craft.IsCamp(d.spell), "(none of them on its profession's own tab)") end
	local firstAidCamp = false
	for _, d in ipairs(camp.list) do firstAidCamp = firstAidCamp or (d.spell == 1230117 and d[7] ~= "|cff888888?|r") end
	eq(firstAidCamp, true, "one of a profession whose window was read says known or missing")
	camp.heads[2].scripts.OnClick(camp.heads[2])
	eq(camp.list[1][2], "Alchemy", "a click on Profession sorts by it")
	check(camp.sideButtons[2] and camp.sideButtons[2].label.text:find("Alchemy", 1, true), "and the list on the left is by profession too")
	-- a camp recipe of Cooking is read from the Cooking window by this module
	P1.env.C_TradeSkillUI = { GetAllRecipeIDs = function() return { 1229737, 2538 } end, GetRecipeInfo = function() return { learned = true } end }
	P1.fire("TRADE_SKILL_SHOW")
	step(2)
	eq(Craft.db.mine[Craft.me].ids[1229737], true, "Cooking's campfire, learned, is kept"); eq(Craft.db.mine[Craft.me].ids[2538], nil, "its food still is not")
	-- the guild: under Cooking's switch
	step(60)
	eq(crafts("KNOWN", "Pat"), 0, "Cooking's sharing not agreed to: nothing is sent"); eq(P1.DT.modules.crafts.hello(), nil, "nor said in the hello")
	P1.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
	P2.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
	check(P1.env.StaticPopupDialogs.DAWNTOOLS_SHARE.text:find("its other professions", 1, true), "the question says the other professions are part of it")
	step(5)
	check(crafts("KNOWN", "Pat") >= 1, "agreed to: what I know goes out")
	P1.DT.Comms:Hello(); P2.DT.Comms:Hello()
	step(60)
	local got = P2.DT.Craft.db.guild["Pat Smith"]
	check(got and got.ids[7934], "a guild member hears which recipes my character knows")
	eq(P2.DT.Craft.Makers(7934)[1], "Pat Smith", "and names it among who can make it")
	P2.DT.UI:Show("craft129")
	local theirs
	for _, d in ipairs(P2.DT.Craft.views[129].list) do if d.spell == 7934 then theirs = d[7] end end
	eq(theirs, "Pat Smith", "on the tab too")
	inject(P2, "Pat-Forever", (packed("KNOWN", "Pat Smith;rubbish", nil):gsub("^market", "crafts")))
	step(1)
	check(P2.DT.Craft.db.guild["Pat Smith"].ids[7934], "a list that is no list is not taken")
	-- Data Sync
	local bars = P2.DT.modules.crafts.progress()
	eq(bars[1][2], 2, "the bar: the recipes somebody can make (the potion and the campfire)"); check(bars[1][3] > 2000, "of all there are: " .. bars[1][3])
	-- Cooking has the profit too, and its Level header fits
	P1.DT.UI:Show("food")
	local head
	for _, w in ipairs(P1.widgets) do
		if w.kind == "Button" and w.text and type(w.text) == "table" and w.text.text and w.text.text:find("Profit", 1, true) and w.shown ~= false then head = w end
	end
	check(head, "Cooking has a Profit column")
	leave(P1); leave(P2)
end)()
V.vendorOnly = true
V:Refresh()
local sellers = {}
for _, w in ipairs(A.widgets) do
	if w.cells and w.shown then sellers[w.id] = w.cells.vbuy.text end
end
check(sellers[100] and sellers[110] and not sellers[821], "the vendor filter lists what a vendor sells")
check(sellers[100]:find("30c", 1, true), "with the vendor's price"); check(sellers[110]:find("*", 1, true), "and a star for limited stock")
V.vendorOnly = nil
V:Refresh()
A.env.GameTooltip.lines = {}
A.tooltipHook(A.env.GameTooltip, { id = 100 })
check(table.concat(A.env.GameTooltip.lines, "|"):find("30c at Kira, Booty Bay, Stranglethorn Vale", 1, true), "the item's tooltip says where a vendor sells it")

-- Auction houses: my faction's and the cross-faction one keep their own prices
local M = A.M
local Latest = A.env.DawnMarket.API.GetLatest
local function houseB(key)
	for _, w in ipairs(A.widgets) do if w.house == key then return w end end
end
eq(M.view, "H", "away from an auctioneer: my faction's house"); eq(houseB("H").text, "|cffffd100Horde|r", "its button is the lit one")
eq(houseB("X").text, "|cff999999X-Faction|r", "the other is not")
local hordePrice = M:House("H")[100].p
A.npc, A.npcFaction = "Creature-0-1-2-3-9999-00001B", "Neutral"
A.fire("AUCTION_HOUSE_SHOW")
step(1)
eq(M.at, "X", "an auctioneer of no faction is the cross-faction house"); eq(M.view, "X", "and its prices are shown")
eq(A.env.DawnMarket.API.GetHouse(), "X", "the other tabs can ask which house that is"); eq(select(2, A.env.DawnMarket.API.GetHouse()), "X-Faction", "and its name")
eq(A.items()[100], nil, "which are not my faction's"); eq(Latest(100), nil, "for the other tabs neither")
A.DT.db.settings.share = true
A.searched[100] = { { hordePrice + 7, 3 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(Latest(100), hordePrice + 7, "a price seen here is filed here"); eq(M:House("H")[100].p, hordePrice, "and my faction's stays what it was")
M.Sync:Flush()
check(sent[#sent].text:find("ZX|100,", 1, true), "it goes to the guild marked with its house")
step(1)
eq(houseB("X").text, "|cffffd100X-Faction|r", "at the cross-faction house its button is lit")
click(houseB("H"))
eq(M.view, "H", "a house's button shows that house"); eq(houseB("H").text, "|cffffd100Horde|r", "and lights up"); eq(Latest(100), hordePrice, "with its prices")
click(houseB("H"))
eq(M.view, "H", "clicking the lit one changes nothing")
A.searched[110] = { { 9, 1 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 110)
eq(M:House("X")[110].p, 9, "what is seen is still filed where I stand, whatever is shown")
-- from the guild
local function ob(id, p) return L.Encode({ { id = id, p = p, q = 1, t = A.DT.Now(), o = "=" } }) end
M.Sync:OnMessage("PUSH", "X|" .. ob(7001, 5), "Zed-Forever")
check(M:House("X")[7001] and M:House("X")[7001].p == 5 and not M:House("H")[7001], "a guild price goes to the house it names")
M.Sync:OnMessage("PUSH", ob(7002, 5), "Zed-Forever")
M.Sync:OnMessage("PUSH", "Q|" .. ob(7002, 5), "Zed-Forever")
check(not M:House("X")[7002] and not M:House("H")[7002], "one that names none, or an unknown one, is dropped")
A.DT.db.settings.share = nil
-- putting the house right by hand
step(1)
local hereB = find("Button", "Wrong house?")
check(hereB and hereB.shown and find("FontString", "You are at: |cffffd100X-Faction|r"), "at an auctioneer the tab says which house it takes it for")
click(hereB)
eq(M.at, "H", "a click puts that right"); eq(M.db.auctioneers["9999"], "H", "for this auctioneer")
A.fire("AUCTION_HOUSE_CLOSED")
step(1)
eq(M.at, nil, "away again"); eq(hereB.shown, false, "the button goes")
A.fire("AUCTION_HOUSE_SHOW")
eq(M.at, "H", "and it is remembered")
A.fire("AUCTION_HOUSE_CLOSED")
A.npc, A.npcFaction = "Creature-0-1-2-3-6666-00001C", "Alliance"
A.fire("AUCTION_HOUSE_SHOW")
eq(M.at, "X", "the other faction's auctioneer: cross-faction")
A.fire("AUCTION_HOUSE_CLOSED")
A.npc, A.npcFaction = "Creature-0-1-2-3-7777-00001D", nil
A.fire("AUCTION_HOUSE_SHOW")
eq(M.at, "X", "a faction the game does not tell, in a goblin town: cross-faction")
A.fire("AUCTION_HOUSE_CLOSED")
A.env.GetSubZoneText = function() return "Valley of Strength" end
A.fire("AUCTION_HOUSE_SHOW")
eq(M.at, "H", "a faction the game does not tell, elsewhere: my own house")
A.fire("AUCTION_HOUSE_CLOSED")
A.env.GetSubZoneText = function() return "Booty Bay" end
step(1)
-- saved data from before the houses
local old = NewClient("Olga", { db = { market = { items = { [100] = { p = 5, q = 1, t = Now(), o = "Olga", d = {} } }, settings = { share = false } } } })
eq(old.items()[100].p, 5, "prices saved before the houses were told apart are my faction's"); eq(old.M.db.items, nil, "moved, not copied")
leave(old)

-- Fish: what a cast is worth where, and what cooking adds
local Fish = A.DT.Fish
ITEMS[6359] = { "Firefin Snapper", 1, 20, 4, true, 7, 8 }
ITEMS[6362] = { "Raw Rockscale Cod", 1, 20, 3, true, 7, 8 }
ITEMS[4594] = { "Rockscale Cod", 1, 20, 6, true, 0, 5 }
ITEMS[13759] = { "Raw Nightfin Snapper", 1, 20, 5, true, 7, 8 }
ITEMS[13931] = { "Nightfin Soup", 1, 20, 10, true, 0, 5 }
ITEMS[9999] = { "Firefin Stew", 1, 20, 10, true, 0, 5 }
for id, price in pairs({ [6359] = 500, [6362] = 100, [4594] = 300, [13759] = 100, [13931] = 400, [9999] = 300 }) do A.M:Record(id, price, 5) end
A.slash("fish")
click(find("Button", "Spots")) -- (the window test left the other table up)
-- (and sorted some other way: put a table back to "biggest first" by one of its columns)
local function sortDesc(title)
	for _ = 1, 3 do
		for _, w in ipairs(A.widgets) do
			if w.kind == "Button" and w.shown ~= false and w.text and w.text.text and w.text.text:find(title, 1, true) then
				if w.text.text:find(title .. " v", 1, true) then return end
				click(w)
			end
		end
	end
end
sortDesc("Per cast")
local fishBox = Fish.search
fishBox:SetText("strangle") -- (the window test left the table sorted some other way: look it up)
step(1)
check(text("Stranglethorn Vale"), "the built-in waters are listed before anything was caught")
fishBox:SetText("")
step(1)
check(text("Prices: Horde auction house"), "and it says whose prices these are")
-- catches
local loot, fishing = { { 6359, 2 }, { 600, 1 } }, true
A.env.IsFishingLoot = function() return fishing end
A.env.GetRealZoneText = function() return "Testwater" end
A.env.GetSubZoneText = function() return "Pier" end
A.env.GetNumLootItems = function() return #loot end
A.env.GetLootSlotLink = function(i) return "|Hitem:" .. loot[i][1] .. "::|h[" .. ITEMS[loot[i][1]][1] .. "]|h" end
A.env.GetLootSlotInfo = function(i) return nil, "x", loot[i][2] end
A.env.GetProfessions = function() return nil, nil, nil, 7 end
A.env.GetProfessionInfo = function() return "Fishing", nil, 140 end
A.fire("LOOT_READY")
A.fire("LOOT_OPENED")
local function pier() return Fish.Catches()["Testwater, Pier"] end -- (the catches are rows of the store: added up from every origin)
eq(Fish.db.catches, nil, "(none are kept in the module's own saved table)")
eq(pier().casts, 1, "one loot window is one cast, however often it is announced"); eq(pier().items[6359], 2, "with what was in it"); eq(pier().mine, 1, "all of it mine")
eq(pier().skill, 140, "and the fishing skill it was caught at")
A.fire("LOOT_CLOSED")
A.fire("LOOT_OPENED")
eq(pier().casts, 2, "the next cast"); eq(pier().items[600], 2, "junk counts too")
-- a game with the older skill list instead of the profession list
do
	local professions, info = A.env.GetProfessions, A.env.GetProfessionInfo
	A.env.GetProfessions, A.env.GetProfessionInfo = nil, nil
	A.env.GetNumSkillLines = function() return 2 end
	A.env.GetSkillLineInfo = function(i)
		if i == 1 then return "Secondary Skills", true end
		return "Fishing", false, false, 90, 0, 25
	end
	A.env.GetRealZoneText, A.env.GetSubZoneText = function() return "Jetty Lake" end, function() return "" end
	local wasLoot = loot
	loot = { { 6362, 1 } } -- (not what the Pier gives: that spot's own numbers are looked at below)
	A.fire("LOOT_CLOSED")
	A.fire("LOOT_OPENED")
	loot = wasLoot
	eq(Fish.Catches()["Jetty Lake"].skill, 90, "the fishing skill is read from the skill list where that is what the game has")
	A.env.GetRealZoneText, A.env.GetSubZoneText = function() return "Testwater" end, function() return "Pier" end
	A.env.GetNumSkillLines, A.env.GetSkillLineInfo = nil, nil
	A.env.GetProfessions, A.env.GetProfessionInfo = professions, info
end
A.fire("LOOT_CLOSED")
fishing = false
A.fire("LOOT_OPENED")
eq(pier().casts, 2, "loot that is not fished is not a cast")
A.fire("LOOT_CLOSED")
Fish.Refresh()
check(text("Testwater, Pier"), "my own spot is listed")
local perCast = L.Money((4 * 500 + 2 * (Latest(600) or 100)) / 2) -- 4 snappers at 5s and 2 fangs at their price, over 2 casts
check(text("|cff888888~|r" .. perCast), "per cast: what was caught at today's prices over the casts, still marked a guess")
A.DT.DB.Put(Fish.Key("Testwater, Pier"), A.DT.DBLogic.Pack({ 20, { 600, 20, 6359, 40 }, 140, "Testwater, Pier" }, 4)) -- (twenty casts of mine, as the store holds them)
Fish.Refresh()
check(text("Firefin Snapper 200%"), "what bites, per cast"); check(not text("|cff888888~|r" .. perCast) and text(perCast), "believed from 20 casts on")
-- the Fish table
for _, w in ipairs(A.widgets) do
	if w.kind == "Button" and w.text == "Fish" and w.shown ~= false and w.scripts.OnClick and not w.id then click(w) end
end
sortDesc("Raw")
check(text("Raw Rockscale Cod"), "the Fish table lists the fish")
check(text("|cff40ff40+2s 0c|r"), "cooking adds the cooked price less the raw one")
for _, w in ipairs(A.widgets) do -- hovering the row shows the raw fish; hovering its cooked columns, the food
	if w.cols and w.shown and w.data and w.data.id == 6362 then
		A.env.GameTooltip.lines = {}
		w.scripts.OnEnter(w)
		eq(A.env.GameTooltip.lines[1], "item:6362", "the row's tooltip is the raw fish")
		A.env.GameTooltip.lines = {}
		w.over.scripts.OnEnter(w.over)
		eq(A.env.GameTooltip.lines[1], "item:4594", "over the cooked columns it is the food"); eq(w.over.shown, true, "where there is one")
	end
end
check(text("|cff40ff40+2s 75c|r"), "less the other mats, at the vendor's price where he sells them")
check(text("Testwater, Pier |cff40ff40200%|r"), "and where it bites")
Fish.db.recipes[9999] = { q = 2, r = { { 6359, 1 }, { 159, 1 } } }
Fish.Refresh()
check(text("Firefin Stew") and text("|cff40ff40+75c|r"), "a recipe from the Cooking window is used: 2 x 3s less 25c water less the 5s fish")
-- sorting and searching
local function fishRows()
	local out = {}
	for _, w in ipairs(A.widgets) do
		if w.cols and w.shown and w.data then out[#out + 1] = w.data end
	end
	return out
end
local function head(title)
	for _, w in ipairs(A.widgets) do
		if w.kind == "Button" and w.text and w.text.text and w.text.text:find(title, 1, true) and w.shown ~= false then return w end
	end
end
click(find("Button", "Spots"))
sortDesc("Per cast")
local rowsNow = fishRows()
check(rowsNow[1].sort[5] >= rowsNow[2].sort[5], "spots start with the best per cast"); check(head("Per cast").text.text:find(" v", 1, true), "and the header says so")
click(head("Per cast"))
rowsNow = fishRows()
check(rowsNow[1].sort[5] <= rowsNow[2].sort[5], "a click on the header turns it round")
click(head("Spot"))
rowsNow = fishRows()
check(rowsNow[1].sort[1] < rowsNow[2].sort[1], "another header sorts by that column, names from A")
click(head("Skill"))
check(fishRows()[1].sort[3] >= fishRows()[2].sort[3], "numbers from the biggest")
local fishSearch = Fish.search
fishSearch:SetText("testwater")
step(1)
rowsNow = fishRows()
check(#rowsNow == 1 and rowsNow[1][1] == "Testwater, Pier", "the search box finds a spot by name")
eq(rowsNow[1].sort[6] * 170, rowsNow[1].sort[5] * 170, "per hour goes by per cast"); check(rowsNow[1][6]:find(A.DT.Money(math.floor(rowsNow[1].sort[5] * 170 + 0.5)), 1, true), "170 casts of it")
check(rowsNow[1].sort[7] > 0 and rowsNow[1][7]:find("|cff40ff40", 1, true), "and the dearest single catch of the spot is named with its price: " .. rowsNow[1][7])
;(function() -- the hover of a spot: lines of what | value, with shares
	local tips, bites, own = rowsNow[1].tips, nil, nil
	for _, tip in ipairs(tips) do
		if type(tip) == "table" and tip[1]:sub(1, 2) == "  " and tip[2]:find("%%|r") then bites = tip end
		if type(tip) == "string" and tip:find("From your own", 1, true) then own = tip end
	end
	check(bites, "what bites: a line a fish, with its share of the casts and its price"); check(own, "and where the numbers are from")
	eq(tips[1][1], "Per cast", "a spot whose zone has no skill and no levels known begins with what a cast pays")
	local row
	for _, w in ipairs(A.widgets) do if w.cols and w.shown and w.data == rowsNow[1] then row = w end end
	local tip = A.env.GameTooltip
	local was = tip.lines
	tip.lines = {}
	row.scripts.OnEnter(row)
	check(#tip.lines > 4 and table.concat(tip.lines, "\n"):find("Per hour", 1, true), "hovering the row writes them into the tooltip")
	tip.lines = was
end)()
fishSearch:SetText("firefin")
step(1)
check(#fishRows() >= 1 and fishRows()[1].sort[8]:find("Firefin", 1, true), "or by what bites there")
fishSearch:SetText("")
step(1)
-- the skill column against my own skill (140 here)
local foundRow
local function skillOf(name)
	fishSearch:SetText(name) -- (it may be scrolled out of sight: look it up)
	Fish.Refresh()
	local found
	for _, d in ipairs(fishRows()) do
		if d[1] == name then found, foundRow = d[3], d end
	end
	fishSearch:SetText("")
	return found
end
eq(skillOf("Elwynn Forest"), "|cff40ff4025|r", "green: nothing gets away"); eq(skillOf("Stranglethorn Vale"), "|cffffd100225|r", "yellow: I can cast, some get away")
A.env.GetProfessionInfo = function() return "Fishing", nil, 140, 300, 0, 0, 356, 100 end
eq(skillOf("Stranglethorn Vale"), "|cff40ff40225|r", "a lure and gear count")
eq(skillOf("Eastern Plaguelands"), "|cffff4040425|r", "red: out of reach")
;(function() -- how many casts land, and the zone's levels
	eq(Fish.Chance(225, 225), 100, "at the zone's skill every cast lands"); eq(Fish.Chance(225, 130), 5, "at the least skill to cast: 5 in a hundred")
	eq(Fish.Chance(225, 129), 0, "below it: none"); eq(Fish.Chance(225, 180), 55, "between: a point a point"); eq(Fish.Chance(nil, 100), nil, "no skill known: nothing said")
	local function said(what)
		for _, tip in ipairs(foundRow.tips) do if type(tip) == "table" and tip[1]:find(what, 1, true) then return tip[2] end end
	end
	check(said("At your 240"):find("cannot cast here yet", 1, true), "the hover says I cannot cast there: " .. tostring(said("At your 240")))
	check(said("Fishing skill"):find("(cast from 330)", 1, true), "and from which skill I could")
	eq(foundRow[2], "", "no zone levels known: the column is blank"); eq(said("Zone levels"), nil, "and the hover leaves the line out")
	skillOf("Stranglethorn Vale")
	check(said("At your 240"):find("nothing gets away", 1, true), "where my skill is enough it says so")
	local Zone = A.DT.Zone
	local ensure, get = Zone.Ensure, Zone.Get
	Zone.Ensure = function() return true end
	Zone.Get = function(name) return name == "Stranglethorn Vale" and { lo = 30, hi = 45 } or nil end
	skillOf("Stranglethorn Vale")
	eq(foundRow[2], "|cffff404030-45|r", "the zone's levels, left of the skill, in a colour for my level (10: far too high)"); eq(foundRow.sort[2], 30, "sorted by the lowest")
	eq(said("Zone levels"), "|cffff404030-45|r", "and in the hover")
	Zone.Ensure, Zone.Get = ensure, get
	Fish.Refresh()
end)()
-- the gear table, and the link an item row gives
click(find("Button", "Gear"))
sortDesc("Fishing")
local gear = fishRows()
check(gear[1][2] == "+100" and gear[1].id == 6533, "gear starts with the biggest bonus")
local popups = #A.popups
for _, w in ipairs(A.widgets) do
	if w.cols and w.data == gear[1] then w.scripts.OnMouseUp(w) end
end
eq(A.popups[#A.popups], "DAWNTOOLS_LINK", "a click on an item row offers a link"); eq(#A.popups, popups + 1, "once")
eq(A.DT:ItemLink(6533), "https://www.wowhead.com/forever/item=6533", "to the item's page")
click(find("Button", "Spots"))
eq(A.DT.modules.fish.hello, nil, "the module has nothing to say to the guild")

-- Food: what the Cooking window lists, what this character lacks, and who in the guild can cook it
ITEMS[5001] = { "Stamina Stew", 1, 20, 10, true, 0, 5, lvl = 15 }
ITEMS[5002] = { "Spirit Soup", 1, 20, 10, true, 0, 5, lvl = 25 }
ITEMS[5003] = { "Plain Bread", 1, 20, 10, true, 0, 5 }
local TIPS = { [5001] = "Use: Restores health. Well fed: 6 Stamina and Spirit.", [5002] = "Use: Restores health. 8 Spirit.", [5003] = "Use: Restores 61 health." }
local function kitchen(c, learned) -- a Cooking window that lists recipes 1..3 for foods 5001..5003
	c.env.C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = ITEMS[id][1] }, { leftText = TIPS[id] } } } end }
	c.env.C_TradeSkillUI = {
		GetBaseProfessionInfo = function() return { profession = 5, professionName = "Cooking" } end,
		GetAllRecipeIDs = function() return { 1, 2, 3 } end,
		GetRecipeInfo = function(r) return { learned = learned[r] or false, categoryID = 9 } end,
		GetCategoryInfo = function() return { name = "Old Recipes" } end,
		GetRecipeSchematic = function(r) return { outputItemID = 5000 + r } end,
	}
	c.fire("TRADE_SKILL_SHOW")
	step(2)
end
local Fay, Gus = NewClient("Fay"), NewClient("Gus")
local FF, GF = Fay.DT.Food, Gus.DT.Food
Fay.slash("food")
eq(Fay.popups[#Fay.popups], nil, "the tab asks nothing itself: sharing is one question, a little after login")
local foodSent = count("KNOWN")
kitchen(Fay, { [1] = true, [3] = true })
eq(FF.db.mine["Player-Fay"].ids[5001], true, "what I can cook is recorded"); eq(FF.db.mine["Player-Fay"].ids[5002], nil, "what I cannot is not")
check(FF.db.foods[5002], "but the food is known of"); eq(FF.db.foods[5002].cat, "Old Recipes", "with the window's heading")
eq(count("KNOWN"), foodSent, "nothing is told to the guild before I agreed")
FF.Refresh()
local function foodText(c, part)
	for _, w in ipairs(c.widgets) do
		if w.kind == "FontString" and type(w.text) == "string" and w.text:find(part, 1, true) then return w.text end
	end
end
local function foodRows(c)
	local out = {}
	for _, w in ipairs(c.widgets) do
		if w.fcols and w.shown and w.data then out[#out + 1] = w.data end
	end
	return out
end
eq(#foodRows(Fay), 3, "all the food is listed"); eq(foodRows(Fay)[1].id, 5003, "lowest level first")
check(foodText(Fay, "3 foods, 2 of them known to this character"), "with a count")
check(foodText(Fay, "Stamina (1)") and foodText(Fay, "Spirit (1)") and foodText(Fay, "Health only (1)"), "grouped by what it gives, the first thing named")
eq(foodRows(Fay)[1][5], "|cff40ff40known|r", "a recipe I have"); eq(foodRows(Fay)[3][5], "|cffff4040missing|r", "one I lack")
eq(foodRows(Fay)[1][6], "|cff40ff40You|r", "I can cook it"); eq(foodRows(Fay)[3][6], "|cff888888nobody known|r", "nobody can cook the other")
FF.ticks.known.checked = true
click(FF.ticks.known)
eq(#foodRows(Fay), 2, "Known ticked: missing recipes are left out"); check(foodText(Fay, "All food (2)"), "from the counts too")
FF.ticks.missing.checked = true
click(FF.ticks.missing)
eq(#foodRows(Fay), 1, "Missing ticked: only what I lack"); eq(FF.ticks.known.checked, false, "which unticks Known: both cannot be")
FF.ticks.missing.checked = false
click(FF.ticks.missing)
FF.ticks.known.checked = true
click(FF.ticks.known)
FF.ticks.known.checked = false
click(FF.ticks.known)
-- a character without Cooking (its window was never read) knows nothing: hiding the missing hides all
local fay = FF.db.mine["Player-Fay"]
local hadIds, hadT = fay.ids, fay.t
fay.ids, fay.t = {}, nil
FF.Refresh()
eq(#foodRows(Fay), 3, "a character without Cooking: everything listed")
FF.ticks.known.checked = true
click(FF.ticks.known)
eq(#foodRows(Fay), 0, "and all of it hidden with the missing"); check(foodText(Fay, "Nothing known on this character"), "with a word why")
FF.ticks.known.checked = false
click(FF.ticks.known)
fay.ids, fay.t = hadIds, hadT
FF.Refresh()
for _, w in ipairs(Fay.widgets) do
	if w.section and w.section.kind == "Spirit" then w.scripts.OnClick(w) end
end
eq(#foodRows(Fay), 1, "a type picked on the left"); eq(foodRows(Fay)[1].id, 5002, "lists its food")
for _, w in ipairs(Fay.widgets) do
	if w.section and not w.section.kind then w.scripts.OnClick(w) end
end
eq(#foodRows(Fay), 3, "and all again")
local function foodHead(title)
	for _, w in ipairs(Fay.widgets) do
		if w.kind == "Button" and w.text and w.text.text and w.text.text:find(title, 1, true) then return w end
	end
end
check(foodHead("Level").text.text:find("Level ^", 1, true), "sorted by level to start with, and the header says so")
foodHead("Food").scripts.OnClick(foodHead("Food"))
eq(foodRows(Fay)[1].name, "Plain Bread", "a click on a header sorts by it: names from A")
foodHead("Food").scripts.OnClick(foodHead("Food"))
eq(foodRows(Fay)[1].name, "Stamina Stew", "again: the other way round")
foodHead("This character").scripts.OnClick(foodHead("This character"))
eq(foodRows(Fay)[3][5], "|cffff4040missing|r", "by what I know: the missing ones last")
foodHead("Level").scripts.OnClick(foodHead("Level"))
eq(foodRows(Fay)[1].id, 5003, "and back by level")
;(function() -- the skill band of a recipe
	local CS, Band = Fay.DT.CraftSkill, Fay.DT.CraftBand
	eq(CS[2679][2], 1, "the shipped list: Charred Wolf Meat from the start"); eq(CS[2679][1], 185, "of Cooking")
	eq(CS[20452][2], 0, "one whose learning skill the source does not know: 0, not 1")
	local band, profession = Band(7938)
	eq(band, "|cffff8040200|r |cffffff00220|r |cff40c040230|r |cff808080240|r", "the band in the colours of the Professions window"); eq(profession, "Blacksmithing", "and its profession")
	check(Band(20452):find("|cffff8040?|r |cffffff00325|r", 1, true), "not known: a question mark"); eq(Band(5002), nil, "nothing for what no profession makes")
	CS[5001], CS[5003] = { 185, 175, 200, 210, 220 }, { 185, 0, 50, 60, 70 }
	foodHead("Cooking skill").scripts.OnClick(foodHead("Cooking skill"))
	local rows = foodRows(Fay)
	eq(rows[1].id, 5002, "sorted by Cooking skill: none known first"); eq(rows[1][3], "", "and blank")
	eq(rows[2].id, 5003, "then the least (one not known where learned: by its yellow)"); eq(rows[3].id, 5001, "the most last")
	check(rows[3][3]:find("|cffff8040175|r |cffffff00200|r |cff40c040210|r |cff808080220|r", 1, true), "with its band: " .. rows[3][3])
	;(function() -- "Where to get it": a vendor of my side with the price, else a mob, else a quest; a click is a waypoint
		local e, FoodM = Fay.env, Fay.DT.Food
		eq(rows[3][8], "|cff888888Cooking trainer|r", "a recipe without an item: a trainer"); eq(rows[1][8], "", "nothing known of the recipe: blank")
		local wasLib, wasMap, wasWay = e.LibQuestieDB, e.C_Map, Fay.DT.Npc.Waypoint
		local NPCS = { [21] = { name = "Ally Al", zoneID = 12, friendlyToFaction = "A" }, [22] = { name = "Kira Cook", zoneID = 33, friendlyToFaction = "H" },
			[31] = { name = "Murloc Cook", zoneID = 40, minLevel = 20, maxLevel = 21 } }
		e.LibQuestieDB = {
			Item = { GetAllIds = function() return {} end, GetAll = function() end,
				Get = function(id, key) return (id == 7701 and key == "vendors" and { 21, 22 }) or (id == 7702 and key == "npcDrops" and { 31 }) or nil end },
			Npc = { Get = function(id, key) return NPCS[id] and NPCS[id][key] end },
		}
		e.C_Map = { GetAreaInfo = function(area) return ({ [12] = "Elwynn Forest", [33] = "Booty Bay", [40] = "Westfall" })[area] end }
		local buy = FoodM.Source(7701)
		eq(buy.kind, "buy", "a recipe vendors sell: to buy"); eq(buy.npc, 22, "from the vendor of my side, not the first listed"); eq(buy.more, 1, "and how many others sell it")
		local drop = FoodM.Source(7702)
		eq(drop.kind, "drop", "one that only drops: from a mob"); eq(drop.npc, 31, "which one")
		eq(FoodM.Source(7703), nil, "one with no source known: nothing")
		CS[5001][6], CS[5003][6] = 7701, 7702
		FoodM.Refresh()
		local by = {}
		for _, w in ipairs(Fay.widgets) do if w.fcols and w.shown and w.data then by[w.data.id] = w end end
		local cell = by[5001].data[8]
		check(cell:find("Buy|r |cff888888price ?|r  Kira Cook", 1, true) and cell:find("Booty Bay", 1, true) and cell:find("(+1)", 1, true), "the cell: buy, from whom, where; the price not seen yet: " .. cell)
		check(by[5003].data[8]:find("Drop|r  Murloc Cook", 1, true) and by[5003].data[8]:find("Westfall", 1, true), "a drop: the mob and its zone: " .. by[5003].data[8])
		eq(by[5001].where.shown, true, "the cell can be clicked"); eq(by[5002].where.shown, false, "one with nothing to go to cannot")
		Fay.DT.DB.Put("vendor:7701", Fay.DT.DB.VendorText(40, false, "Kira Cook", "Booty Bay"))
		FoodM.Refresh()
		check(by[5001].data[8]:find("Buy|r " .. Fay.DT.Money(40), 1, true), "with the price once it is known: " .. by[5001].data[8])
		local went
		Fay.DT.Npc.Waypoint = function(to) went = to end
		by[5001].where.scripts.OnMouseUp(by[5001].where)
		eq(went and went.id, 22, "a click: a waypoint to the vendor"); eq(went.name, "Kira Cook", "by name")
		by[5001].where.scripts.OnEnter(by[5001].where)
		local tip = table.concat(e.GameTooltip.lines or {}, "|")
		check(tip:find("Sold by (2)", 1, true) and tip:find("Ally Al", 1, true), "hovering lists every source: " .. tip)
		foodHead("Where to get it").scripts.OnClick(foodHead("Where to get it"))
		eq(foodRows(Fay)[1].id, 5001, "sorted by where: what is bought first")
		CS[5001][6], CS[5003][6] = nil, nil
		e.LibQuestieDB, e.C_Map, Fay.DT.Npc.Waypoint = wasLib, wasMap, wasWay
		foodHead("Cooking skill").scripts.OnClick(foodHead("Cooking skill"))
		FoodM.Refresh()
		rows = foodRows(Fay)
	end)()
	-- the Recipe column: the item that teaches it, with a hover and a link of its own
	check(CS[3220][6] == 3679 and CS[2679][6] == 0, "the shipped list says which scroll teaches a recipe (0: a trainer)")
	eq(rows[3][7], "|cff888888trainer|r", "no recipe item: a trainer teaches it"); eq(rows[1][7], "", "nothing known: blank")
	CS[5001][6] = 5002 -- (any item the fake client knows stands in for the scroll)
	Fay.DT.Food.Refresh()
	rows = foodRows(Fay)
	local row
	for _, w in ipairs(Fay.widgets) do if w.fcols and w.shown and w.data and w.data.id == 5001 then row = w end end
	check(row.data[7]:find("Spirit Soup", 1, true), "a recipe item is named: " .. row.data[7]); eq(row.over.shown, true, "and its cell has a hover of its own")
	local tip, popups = Fay.env.GameTooltip, #Fay.popups
	local linked
	local was = tip.SetHyperlink
	tip.SetHyperlink = function(_, link) linked = link end
	row.over.scripts.OnEnter(row.over)
	eq(linked, "item:5002", "which shows the recipe, not the food")
	tip.SetHyperlink = was
	row.over.scripts.OnMouseUp(row.over)
	eq(#Fay.popups, popups + 1, "a click on it gives the recipe's link")
	for _, w in ipairs(Fay.widgets) do if w.fcols and w.shown and w.data and w.data.id == 5002 then eq(w.over.shown, false, "a row without a recipe item has none") end end
	foodHead("Recipe").scripts.OnClick(foodHead("Recipe"))
	eq(foodRows(Fay)[1].id, 5001, "sorted by recipe: the named ones first")
	-- any item's tooltip says it
	local tip = A.env.GameTooltip
	local lines = tip.lines
	tip.lines = {}
	A.tooltipHook(tip, { id = 7938 })
	check(tostring(tip.lines[1]):find("Blacksmithing", 1, true) and tostring(tip.lines[1]):find("|cffffff00220|r", 1, true), "an item a profession makes: its tooltip names the profession and the band: " .. tostring(tip.lines[1]))
	-- what a vendor asks, for an item never seen at one
	local VT = A.M.View.VendorText
	eq(A.DT.VendorPrice[2678], 2, "the shipped list: Mild Spices, 2c each")
	local wasQ = A.env.LibQuestieDB
	A.env.LibQuestieDB = nil
	eq(VT(2678, 1), A.DT.Money(2), "a reagent on the shipped list: its price, QuestieDB or not"); eq(VT(2678, 5), A.DT.Money(10) .. " x5", "of a stack: all of it")
	eq(VT(7938, 1), nil, "an item neither knows of: nothing")
	A.env.LibQuestieDB = { Item = { Get = function(id, key) return key == "vendors" and (id == 4599 and { 11, 12, 13 } or id == 2692 and { 11 }) or nil end },
		Npc = { Get = function(id, key) return key == "name" and id == 11 and "Kira Cook" or nil end } }
	eq(VT(4599, 1), "Kira Cook +2 more |cff888888(price not seen yet)|r", "one QuestieDB says vendors sell: who, and that the price is not seen yet")
	eq(VT(2692, 1), A.DT.Money(40) .. " at Kira Cook", "both known: the price and who")
	tip.lines = {}
	A.tooltipHook(tip, { id = 4599 })
	check(tostring(tip.lines[1]):find("Vendor Kira Cook +2 more", 1, true), "and the tooltip says it: " .. tostring(tip.lines[1]))
	A.env.LibQuestieDB = wasQ
	tip.lines = lines
	CS[5001], CS[5003] = nil, nil
	foodHead("Level").scripts.OnClick(foodHead("Level"))
end)()
-- the guild
Fay.DT.db.settings.share, Gus.DT.db.settings.share = true, true
kitchen(Fay, { [1] = true, [2] = true, [3] = true })
step(2)
eq(count("KNOWN", "Fay"), 1, "learning a recipe tells the guild, once agreed")
check(GF.db.guild["Fay Smith"] and GF.db.guild["Fay Smith"].ids[5002], "a guild member takes it in, under the character's full name")
check(GF.db.foods[5001], "and so hears of the food itself")
Gus.slash("food")
kitchen(Gus, { [3] = true })
step(2)
local gusRows = foodRows(Gus)
eq(gusRows[1][6], "|cff40ff40You|r, Fay Smith", "who can cook it: me, then the guild"); eq(gusRows[2][6], "Fay Smith", "the guild alone")
eq(gusRows[2][5], "|cffff4040missing|r", "and that I lack it")
check(FF.db.guild["Gus Smith"] and FF.db.guild["Gus Smith"].ids[5003] and not FF.db.guild["Gus Smith"].ids[5001], "it goes both ways")
-- someone who comes later asks for the lists
local Hal = NewClient("Hal")
Hal.DT.db.settings.share = true
step(700)
check(Hal.DT.Food.db.guild["Fay Smith"] and Hal.DT.Food.db.guild["Gus Smith"], "a member who joins later asks, and is told")
local known = count("KNOWN")
step(1300)
eq(count("KNOWN"), known, "and nobody goes on repeating what is known")
-- not believed
Gus.DT.db.settings.share = false
kitchen(Fay, { [1] = true })
step(2)
check(GF.db.guild["Fay Smith"].ids[5002], "with sharing off nothing comes in")
Gus.DT.db.settings.share = true
local function foodMsg(payload) return table.concat({ "food", "KNOWN", 1, "z", LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(payload)) }, "\t") end
inject(Gus, "Mallory-Forever", foodMsg("Gus Smith;5001,5002"))
check(not GF.db.guild["Gus Smith"], "nobody else speaks for my own characters")
inject(Gus, "Mallory-Forever", foodMsg("no list here"))
inject(Gus, "Mallory-Forever", foodMsg(("x"):rep(50) .. ";5001"))
eq(GF.db.guild[("x"):rep(50)], nil, "and nonsense is dropped")
leave(Fay) leave(Gus) leave(Hal)

-- NPCs: read from QuestieDB as the tab is used, searched, filtered, and a waypoint set
do
	local Npc = A.DT.Npc
	A.slash("npc")
	check(text("Install the QuestieDB addon"), "without QuestieDB the tab says what it needs")
	eq(#Npc.Find("anything", {}), 0, "and lists nothing")
end
do
	local B2 = NewClient("Nell")
	B2.DT.db.settings.background = false -- (this client reads when its tabs are opened; the background reading is checked below)
	local Npc = B2.DT.Npc
	local function btext(part)
		for _, w in ipairs(B2.widgets) do
			if w.kind == "FontString" and w.shown ~= false and type(w.text) == "string" and w.text:find(part, 1, true) then return w.text end
		end
	end
	-- flags as in Classic: quest giver 2, vendor 4, trainer 16, innkeeper 128, repair 16384
	local NPCS = {
		[10] = { name = "Gorak", minLevel = 30, maxLevel = 30, rank = 0, zoneID = 1637, friendlyToFaction = "H", subName = "Fishing Supplies", npcFlags = 4 + 16384,
			spawns = { [1637] = { { 54.2, 68.1 }, { 20, 30 } } }, questStarts = { 5 } },
		[11] = { name = "Lumak", minLevel = 35, maxLevel = 35, rank = 0, zoneID = 1637, friendlyToFaction = "H", subName = "Fishing Trainer", npcFlags = 16 + 2,
			spawns = { [1637] = { { 69.8, 29.2 } } }, questStarts = { 7, 8 }, questEnds = { 7 } },
		[12] = { name = "Old Greyfin", minLevel = 22, maxLevel = 24, rank = 4, zoneID = 17, spawns = { [17] = { { 40, 40 } } }, waypoints = { [17] = { { { 1, 1 } } } } },
		[13] = { name = "Innkeeper Gryshka", minLevel = 35, maxLevel = 35, rank = 0, zoneID = 1637, friendlyToFaction = "H", subName = "Innkeeper", npcFlags = 128 + 4,
			spawns = { [1637] = { { 54, 68 } } } },
		[14] = { name = "Scripted Ghost", minLevel = 60, maxLevel = 60, rank = 3, zoneID = 0 },
		[15] = { name = "Marshal Gorakson", minLevel = 50, maxLevel = 50, rank = 1, zoneID = 12, friendlyToFaction = "A", spawns = { [12] = { { 10, 10 } }, [99] = { { 5, 5 } } } },
	}
	local reads = 0
	B2.env.LibQuestieDB = {
		RequireContract = function(n) return n == 4 end,
		Enum = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, INNKEEPER = 128, REPAIR = 16384 } },
		Npc = {
			GetAllIds = function() return { 10, 11, 12, 13, 14, 15 } end,
			GetAll = function(id, keys)
				reads = reads + 1
				local out = { n = #keys }
				for i, key in ipairs(keys) do out[i] = NPCS[id][key] end
				return out
			end,
			Get = function(id, key) return NPCS[id] and NPCS[id][key] end,
		},
	}
	local AREAS = { [1637] = "Orgrimmar", [17] = "The Barrens", [12] = "Elwynn Forest", [99] = "Nowhere" }
	local pin
	B2.env.C_Map = {
		GetAreaInfo = function(area) return AREAS[area] end,
		GetBestMapForUnit = function() return 1454 end,
		GetPlayerMapPosition = function() return { GetXY = function() return 0.21, 0.31 end } end,
		CanSetUserWaypointOnMap = function() return true end,
		SetUserWaypoint = function(point) pin = point end,
	}
	B2.env.UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map, x, y } end }
	B2.env.QuestieLoader = { ImportModule = function() return { GetUiMapIdByAreaId = function(_, area) return ({ [1637] = 1454, [17] = 1413, [12] = 1429 })[area] end } end }
	B2.env.GetRealZoneText = function() return "Orgrimmar" end
	Npc.BATCH = 2
	eq(reads, 0, "nothing is read at login")
	B2.slash("npc")
	check(btext("Reading NPCs..."), "the reading says how far it is")
	eq(#Npc.Find("", {}), 0, "nothing is listed half-read")
	step(1)
	eq(reads, 6, "every NPC is read once, over some frames")
	check(btext("6 of 6 NPCs"), "then they are all listed")
	local function names(text, f)
		local out = {}
		for i, r in ipairs(Npc.Find(text, f or {})) do out[i] = r.e.name end
		table.sort(out)
		return table.concat(out, ", ")
	end
	local function best(text) local r = Npc.Find(text, {}) table.sort(r, function(a, b) return a.score > b.score end) return r[1] and r[1].e.name end
	local function types(id) for _, r in ipairs(Npc.Find("", {})) do if r.e.id == id then return r.e.typeText end end end
	eq(types(10), "Vendor, Repairs, Fishing", "types come from the flags and the title: several at once")
	eq(types(11), "Trainer, Quest giver, Fishing", "a trainer who gives quests")
	eq(types(12), "Rare", "and from the rank"); eq(types(13), "Vendor, Innkeeper", "an innkeeper who sells"); eq(types(14), "Boss", "a boss")
	-- searching
	eq(names("fish"), "Gorak, Lumak", "a word may be in the title or the types")
	eq(names("fish train"), "Lumak", "every word has to match somewhere")
	eq(names("barrens"), "Old Greyfin", "or in the zone")
	eq(best("gorak"), "Gorak", "the exact name beats a name that starts with it")
	eq(names("gorak"), "Gorak, Marshal Gorakson", "both are found")
	eq(names("grysh"), "Innkeeper Gryshka", "part of a name")
	eq(names("grfn"), "Old Greyfin", "letters in order, when nothing plainer fits")
	eq(names("orgimmar"), "Gorak, Innkeeper Gryshka, Lumak", "a misspelt zone is forgiven")
	eq(names("lumek"), "Lumak", "and a misspelt name")
	eq(names("zzzz"), "", "nonsense finds nothing")
	-- filters
	eq(names("", { types = { Vendor = true } }), "Gorak, Innkeeper Gryshka", "a type")
	eq(names("", { types = { Vendor = true, Repairs = true } }), "Gorak", "two types have both to apply")
	eq(names("", { min = 31, max = 40 }), "Innkeeper Gryshka, Lumak", "levels")
	eq(names("", { side = "friendly" }), "Gorak, Innkeeper Gryshka, Lumak", "friendly to me (Horde)")
	eq(names("", { side = "hostile" }), "Marshal Gorakson, Old Greyfin, Scripted Ghost", "and not")
	eq(names("", { side = "noenemy" }), "Gorak, Innkeeper Gryshka, Lumak, Old Greyfin, Scripted Ghost", "the other faction's own left out, neutral ones kept")
	eq(names("", { zoneOnly = true }), "Gorak, Innkeeper Gryshka, Lumak", "this zone only")
	eq(names("", { zone = "The Barrens" }), "Old Greyfin", "a zone by name")
	eq(names("", { located = true }), "Gorak, Innkeeper Gryshka, Lumak, Marshal Gorakson, Old Greyfin", "with a known location")
	-- the rows
	local function nrows()
		local out = {}
		for _, w in ipairs(B2.widgets) do
			if w.ncols and w.shown and w.data then out[#out + 1] = w end
		end
		return out
	end
	eq(#nrows(), 6, "a row each")
	local function rowOf(name) for _, w in ipairs(nrows()) do if w.data.e.name == name then return w end end end
	eq(rowOf("Old Greyfin").data[2], "|cff80c0ffOld Greyfin|r", "a rare is coloured"); eq(rowOf("Old Greyfin").data[5], "22-24", "its levels")
	eq(rowOf("Gorak").data[7], "Orgrimmar", "the zone by name"); check(rowOf("Scripted Ghost").data[7]:find("no known location", 1, true), "or that there is none")
	-- favourites
	click(rowOf("Lumak").star)
	eq(Npc.db.favs[11], true, "a star makes a favourite, saved"); eq(nrows()[1].data.e.name, "Lumak", "which is listed first")
	eq(names("", { types = { Favourites = true } }), "Lumak", "and can be filtered on")
	local function typeButton(part)
		for _, w in ipairs(B2.widgets) do
			if w.kind == "Button" and w.shown and w.type and w.label.text:find(part, 1, true) then return w end
		end
	end
	check(typeButton("Vendor|r |cff8888882"), "the types on the left are counted: " .. tostring(typeButton("Vendor") and typeButton("Vendor").label.text))
	click(typeButton("Vendor"))
	eq(#nrows(), 2, "a click on one filters"); check(typeButton("Repairs|r |cff8888881"), "and the counts follow")
	click(typeButton("Vendor"))
	eq(#nrows(), 6, "and again to undo")
	Npc.search:SetText("fish")
	step(1)
	eq(#nrows(), 2, "typing searches, after a moment"); check(btext("2 of 6 NPCs, best match first"), "and says so")
	Npc.PickZone("@here")
	click(Npc.clear)
	step(1)
	eq(#nrows(), 6, "Clear undoes search and filters"); eq(Npc.db.zoneOnly, nil, "all of them")
	-- the zone list
	eq(Npc.zoneButton.label.text, "Zone: any", "the zone button says any zone")
	click(Npc.zoneButton)
	local zmenu = Npc.zoneButton.menu
	local zrows = zmenu.rows
	eq(zmenu.shown, true, "a click opens the list of zones")
	eq(zrows[1].label.text, "|cffffd100Any zone|r", "any zone first, lit while it is the pick"); eq(zrows[2].label.text, "|cffffffffWhere I am (Orgrimmar)|r |cff8888883|r", "then where I am, with its NPCs counted")
	local function zrow(zone)
		for _, b in ipairs(zrows) do if b.shown and b.entry and b.entry.value == zone then return b end end
	end
	check(zrow("The Barrens") and zrow("The Barrens").label.text:find("The Barrens|r |cff8888881", 1, true), "then the zones by name, counted")
	click(zrow("The Barrens"))
	eq(zmenu.shown, false, "a pick closes the list"); eq(Npc.zoneButton.label.text, "Zone: The Barrens", "and is named on the button")
	eq(#nrows(), 1, "only that zone's NPCs"); eq(nrows()[1].data.e.name, "Old Greyfin", "listed")
	click(Npc.zoneButton)
	click(zrows[2])
	eq(Npc.zoneButton.label.text, "Zone: here (Orgrimmar)", "where I am"); eq(#nrows(), 3, "its NPCs"); eq(Npc.db.zone, nil, "one or the other")
	-- typing in the list narrows it
	click(Npc.zoneButton)
	zmenu.box:SetText("elw")
	check(zrow("Elwynn Forest") and not zrow("The Barrens"), "typing leaves the zones that contain it"); check(zrows[1].shown and zrows[1].entry.text == "Any zone", "under the two that are always there")
	zmenu.box.scripts.OnEnterPressed(zmenu.box)
	eq(Npc.zoneButton.label.text, "Zone: Elwynn Forest", "Enter takes the first that fits"); eq(zmenu.shown, false, "and closes the list")
	click(Npc.zoneButton)
	eq(zmenu.box:GetText(), "", "opened again, the box is empty"); check(zrow("The Barrens"), "and every zone is back")
	click(zrows[1])
	eq(Npc.zoneButton.label.text, "Zone: any", "and any zone again"); eq(#nrows(), 6, "everything")
	-- the side, from a list too
	click(Npc.sideButton)
	local srows = Npc.sideButton.menu.rows
	eq(srows[2].label.text, "|cffffffffSide: hide other faction|r", "the sides to pick from"); eq(Npc.sideButton.menu.box, nil, "no box to type in for four entries")
	click(srows[2])
	eq(Npc.db.side, "noenemy", "a pick sets it"); eq(#nrows(), 5, "the other faction's NPC is out"); eq(Npc.sideButton.label.text, "Side: hide other faction", "named on the button")
	click(Npc.sideButton)
	click(srows[1])
	eq(Npc.db.side, nil, "and any side again")
	-- the waypoint: the game's own pin, the nearest spot on my map
	rowOf("Gorak").scripts.OnMouseUp(rowOf("Gorak"))
	eq(pin[1], 1454, "the pin is on the zone's map"); eq(pin[2], 0.2, "at the spot nearest to me"); eq(pin[3], 0.3, "of the two")
	check(B2.printed[#B2.printed]:find("Waypoint: Gorak, Orgrimmar 20.0, 30.0", 1, true), "and chat says where: " .. B2.printed[#B2.printed])
	-- with TomTom, that is used
	local tom
	B2.env.TomTom = { AddWaypoint = function(_, map, x, y, opts) tom = { map, x, y, opts.title } end }
	rowOf("Old Greyfin").scripts.OnMouseUp(rowOf("Old Greyfin"))
	eq(tom[1], 1413, "TomTom gets the map"); eq(tom[2], 0.4, "the place as a fraction"); eq(tom[4], "Old Greyfin", "and the name")
	tom = nil
	rowOf("Scripted Ghost").scripts.OnMouseUp(rowOf("Scripted Ghost"))
	eq(tom, nil, "no waypoint without a location"); check(B2.printed[#B2.printed]:find("Scripted Ghost: no known location", 1, true), "but a word about it")
	eq(Npc.Spot(rowOf("Marshal Gorakson").data.e).map, 1429, "of two zones, one that has a map is taken")
	-- the tooltip
	local function tip(name)
		B2.env.GameTooltip.lines = {}
		rowOf(name).scripts.OnEnter(rowOf(name))
		return table.concat(B2.env.GameTooltip.lines, " | ")
	end
	local t = tip("Gorak")
	check(t:find("<Fishing Supplies>", 1, true) and t:find("Level 30, Horde", 1, true) and t:find("Vendor, Repairs, Fishing", 1, true), "the tooltip says what it is: " .. t)
	check(t:find("Orgrimmar: 54.2, 68.1; 20.0, 30.0", 1, true) and t:find("Seen in 2 spots", 1, true) and t:find("Starts 1 quest, ends 0.", 1, true), "where, and its quests")
	t = tip("Old Greyfin")
	check(t:find("Rare", 1, true) and t:find("Only one known spot.", 1, true) and t:find("Patrols", 1, true), "a rare that patrols: " .. t)
	check(tip("Scripted Ghost"):find("No known location", 1, true), "and one that is nowhere")
	eq(B2.DT.modules.npc.hello, nil, "the module has nothing to say to the guild")

	-- Quests: read from QuestieDB the same way; what is open to me, and the chains
	local Quest = B2.DT.Quest
	local QUESTS = {
		[100] = { name = "Fish for Gorak", requiredLevel = 5, questLevel = 8, zoneOrSort = 1637, startedBy = { { 10 } } },
		[101] = { name = "More Fish", requiredLevel = 8, questLevel = 10, zoneOrSort = 1637, preQuestSingle = { 100 }, startedBy = { { 10 } } },
		[102] = { name = "The Big One", requiredLevel = 10, questLevel = 12, zoneOrSort = 17, preQuestSingle = { 101 }, requiredSkill = { 356, 50 }, startedBy = { { 11 } } },
		[103] = { name = "Side Catch", requiredLevel = 1, questLevel = 10, zoneOrSort = 17, preQuestGroup = { 100, 104 } },
		[104] = { name = "Alliance Errand", requiredLevel = 1, questLevel = 10, zoneOrSort = 12, requiredRaces = 1 },
		[105] = { name = "Deadmines Run", requiredLevel = 15, questLevel = 20, zoneOrSort = 12 },
		[106] = { name = "Mage Trial", requiredLevel = 1, questLevel = 10, zoneOrSort = -161, requiredClasses = 128 },
		[107] = { name = "Daily Bread", requiredLevel = 1, questLevel = 5, zoneOrSort = 1637, questFlags = 4096 },
	}
	local qreads = 0
	B2.env.LibQuestieDB.Quest = {
		GetAllIds = function() return { 100, 101, 102, 103, 104, 105, 106, 107 } end,
		GetAll = function(id, keys)
			qreads = qreads + 1
			local out = {}
			for i, key in ipairs(keys) do out[i] = QUESTS[id][key] end
			return out
		end,
	}
	local qdone, qon, fishing = {}, {}, 20
	B2.env.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return qdone[id] or false end, IsOnQuest = function(id) return qon[id] or false end }
	B2.env.GetQuestTagInfo = function(id) if id == 105 then return 81, "Dungeon" end end
	B2.env.UnitRace = function() return "Orc", "Orc", 2 end
	B2.env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	B2.env.GetNumSkillLines = function() return 1 end
	B2.env.GetSkillLineInfo = function() return "Fishing", false, false, fishing end
	Quest.BATCH = 3
	B2.slash("quest")
	eq(qreads, 0, "no quest is read before the tab is looked at... and then a few per frame")
	step(1)
	eq(qreads, 8, "every quest is read once")
	local function qrows()
		local out = {}
		for _, w in ipairs(B2.widgets) do
			if w.qcols and w.shown and w.data then out[#out + 1] = w end
		end
		return out
	end
	local function qnames()
		local out = {}
		for i, w in ipairs(qrows()) do out[i] = w.data.e.name end
		table.sort(out)
		return table.concat(out, ", ")
	end
	local function q(name) for _, w in ipairs(qrows()) do if w.data.e.name == name then return w.data end end end
	local function strip(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	eq(qnames(), "Daily Bread, Deadmines Run, Fish for Gorak, More Fish, Side Catch, The Big One", "the other side's and other classes' quests are left out to begin with")
	check(btext("6 of 8 quests"), "with a count")
	-- nested: each quest under the one that opens it
	local function nest()
		local out = {}
		for i, w in ipairs(qrows()) do out[i] = w.data.depth .. " " .. w.data.e.name end
		return table.concat(out, " / ")
	end
	eq(nest(), "0 Daily Bread / 0 Fish for Gorak / 1 More Fish / 2 The Big One / 1 Side Catch / 0 Deadmines Run",
		"the list is nested: each quest under the one that opens it, chains by the level of their first step")
	eq(strip(q("The Big One")[1]), "        > The Big One", "indented by how deep it stands"); eq(strip(q("Fish for Gorak")[1]), "Fish for Gorak", "a first step at the edge")
	eq(strip(q("Fish for Gorak")[5]), "open to you", "a quest I can take"); eq(strip(q("More Fish")[5]), "after: Fish for Gorak", "one that waits for another")
	eq(strip(q("Deadmines Run")[5]), "needs level 15", "one I am too low for"); eq(strip(q("Side Catch")[5]), "after: Fish for Gorak", "one that needs two others")
	eq(q("Fish for Gorak")[3], "Open world, Chain start", "labels: where a chain starts"); eq(q("More Fish")[3], "Open world, In chain", "and what is part of one")
	eq(q("Deadmines Run")[3], "Dungeon", "the game's own tag: a dungeon quest, and so not open world"); eq(q("Daily Bread")[3], "Open world, Daily", "a daily")
	;(function() -- what a quest asks: QuestieDB's sentence, in the window and on the tooltip
		local e
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == "Daily Bread" then e = r.e end end
		local lib = B2.env.LibQuestieDB
		local was = lib.Quest.Get
		lib.Quest.Get = function(id, key)
			if key == "objectivesText" and id == e.id then return { "Bring 5 loaves to the baker.", "" } end
			return was and was(id, key)
		end
		eq(Quest.Asks(e), "Bring 5 loaves to the baker.", "what a quest asks, in a sentence")
		Quest.ShowChain(e)
		local text = Quest.chain.rewards.text
		check(text:find("To do:|r  Bring 5 loaves to the baker.", 1, true), "the window says what to do")
		check(text:find("To do:", 1, true) < text:find("Rewards of", 1, true), "above what it gives")
		Quest.Tooltip(Quest.chain, e)
		local tip = table.concat(B2.env.GameTooltip.lines or {}, "|")
		check(tip:find("Bring 5 loaves to the baker.", 1, true), "and so does the tooltip: " .. tip)
		Quest.chain:Hide()
		lib.Quest.Get = was
	end)()
	;(function() -- a name is found without its apostrophes and hyphens
		local Match = B2.DT.Npc.Match
		local horn = { nameL = "horn of ve'han", hay = "horn of ve'han" }
		local zul = { nameL = "zul'farrak", hay = "zul'farrak tanaris" }
		local plain = { nameL = "plain horn", hay = "plain horn" }
		local pool = { horn, zul, plain }
		local function found(...)
			local out = {}
			for _, r in ipairs(Match(pool, { ... })) do out[#out + 1] = r.e.nameL end
			table.sort(out)
			return table.concat(out, ", ")
		end
		eq(found("horn", "of", "vehan"), "horn of ve'han", "\"vehan\" finds Ve'han, among several words too")
		eq(found("zulfarrak"), "zul'farrak", "\"zulfarrak\" finds Zul'Farrak"); eq(found("ve'han"), "horn of ve'han", "and written with it, as before")
		eq(found("horn"), "horn of ve'han, plain horn", "a name without any is found as ever")
		eq(found("vexhan"), "", "what is no part of it still is not found (three letters apart is no misspelling)")
	end)()
	;(function() -- a bag says how big it is
		local e, Item2 = B2.env, B2.DT.Item
		local was = e.C_TooltipInfo
		e.C_TooltipInfo = { GetItemByID = function(id)
			if id == 4496 then return { lines = { { leftText = "Small Brown Pouch" }, { leftText = "6 Slot Bag" } } } end
			if id == 4497 then return { lines = { { leftText = "Odd Box" }, { leftText = "Unique" } } } end
			if id == 4498 then return { lines = { { leftText = "Loading" } } } end
			return nil
		end }
		eq(Item2.BagSlots(4496), 6, "a bag's size is read from its tooltip"); eq(Item2.BagSlots(4497), nil, "a container that names none has none")
		eq(Item2.BagSlots(4498), nil, "one not loaded yet: not known")
		e.C_TooltipInfo = { GetItemByID = function() return { lines = { { leftText = "x" }, { leftText = "16 Slot Bag" } } } end }
		eq(Item2.BagSlots(4496), 6, "(kept for the session)"); eq(Item2.BagSlots(4498), 16, "and asked again where it was not known")
		e.C_TooltipInfo = was
	end)()
	;(function() -- Shift-click: the link into the chat; Shift-right-click: the page to read up on it
		local e, shown
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == "Daily Bread" then e = r.e end end
		Quest.ShowChain(e)
		local env = B2.env
		local wasShift, wasPopup = env.IsShiftKeyDown, env.StaticPopup_Show
		env.IsShiftKeyDown = function() return true end
		env.StaticPopup_Show = function(which, title, _, url) shown = { which, title, url } end
		local wasInsert, wasOpen = env.ChatEdit_InsertLink, env.ChatFrame_OpenChat
		local inserted, opened
		env.ChatEdit_InsertLink = function(link) inserted = link return true end
		env.ChatFrame_OpenChat = function(link) opened = link end
		local id = Quest.chain.rows[1].data.e.id
		click(Quest.chain.rows[1])
		eq(inserted, ("|cffffff00|Hquest:%d:%d|h[Daily Bread]|h|r"):format(id, e.level), "a Shift-click on a quest of the chain puts its link in the chat line"); eq(shown, nil, "not its page")
		eq(opened, nil, "(no new line where one is being written)")
		click(Quest.chain.rows[1], "RightButton")
		check(shown and shown[1] == "DAWNTOOLS_LINK" and shown[3] == "https://www.wowhead.com/forever/quest=" .. id, "a Shift-right-click shows its page")
		-- no chat line being written: one is opened with the link in it
		env.ChatEdit_InsertLink = function() return false end
		click(Quest.chain.rows[1])
		check(opened and opened:find("Hquest:" .. id, 1, true), "with no chat line open, one is opened with the link")
		-- the rows of the Quests and Items lists do the same
		inserted, shown = nil, nil
		env.ChatEdit_InsertLink = function(link) inserted = link return true end
		local qrow, irow
		for _, w in ipairs(B2.widgets) do
			if w.scripts and w.scripts.OnMouseUp and w.data and type(w.data) == "table" and w.data.e then
				if w.data.e.questLevel ~= nil or w.data.e.preAny then qrow = qrow or w elseif w.data.e.srcText then irow = irow or w end
			end
		end
		check(qrow, "(a quest row to click)")
		qrow.scripts.OnMouseUp(qrow, "LeftButton")
		check(inserted and inserted:find("Hquest:" .. qrow.data.e.id .. ":", 1, true), "a Shift-click on a row of the Quests list: its link in chat"); eq(shown, nil, "and no page")
		qrow.scripts.OnMouseUp(qrow, "RightButton")
		check(shown and shown[3]:find("quest=" .. qrow.data.e.id, 1, true), "a Shift-right-click: its page")
		eq(B2.DT:GameItemLink(4242, "Odd Thing"), "|cffffffff|Hitem:4242::::::::::::|h[Odd Thing]|h|r", "an item the game does not know yet gets a plain link")
		env.IsShiftKeyDown = wasShift
		eq(B2.DT:LinkClick("LeftButton", "x", "t", "u"), false, "without Shift a click is not a link click")
		env.ChatEdit_InsertLink, env.ChatFrame_OpenChat = wasInsert, wasOpen
		env.IsShiftKeyDown, env.StaticPopup_Show = wasShift, wasPopup
		Quest.chain:Hide()
	end)()
	;(function() -- an instance picked: a quest of it brings along the steps that lead up to it
		local by = {}
		for _, r in ipairs(Quest.Find("", {})) do by[r.e.name] = r.e end
		local step = by["More Fish"] -- (Fish for Gorak > More Fish > The Big One, and Side Catch beside)
		step.instance, step.types.Dungeon = "Krol'dok Stronghold", true -- (as the reading tags a quest of an instance)
		local function names(text, f)
			local got = {}
			for _, r in ipairs(Quest.Find(text, f)) do got[#got + 1] = r.e.name end
			table.sort(got)
			return table.concat(got, ", ")
		end
		eq(names("", { zone = "Krol'dok Stronghold" }), "Fish for Gorak, More Fish", "the step before it, given out in the world, is listed with it; what comes after it is not")
		eq(names("", { zone = "Krol'dok Stronghold", min = 99 }), "", "(the instance's own quest still has to pass the filters to bring anything)")
		eq(names("", { zone = "Krol'dok Stronghold", types = { Dungeon = true } }), "Fish for Gorak, More Fish", "the steps brought along need not be of the kind ticked")
		eq(names("", { types = { Dungeon = true }, sub = { Dungeon = "Krol'dok Stronghold" } }), "Fish for Gorak, More Fish", "the same for an instance picked on the left")
		eq(names("gorak", { zone = "Krol'dok Stronghold" }), "Fish for Gorak", "the search box narrows them like any other")
		-- a later step of the chain that is the instance's too: the steps between are steps up to it
		local last = by["The Big One"]
		step.instance, step.types.Dungeon = nil, nil
		last.instance, last.types.Dungeon = "Krol'dok Stronghold", true
		eq(names("", { zone = "Krol'dok Stronghold" }), "Fish for Gorak, More Fish, The Big One", "a quest of the instance further down the chain brings every step up to it, and still not the side step")
		last.instance, last.types.Dungeon = nil, nil
		step.instance, step.types.Dungeon = "Krol'dok Stronghold", true
		local zone = by["Fish for Gorak"].zoneName
		check(not names("", { zone = zone }):find("The Big One", 1, true) or by["The Big One"].zoneName == zone, "a plain zone brings nothing along")
		local was = Quest.Status
		Quest.Status = function(e) if e.name == "Fish for Gorak" then return "done", "done" end return was(e) end
		eq(names("", { zone = "Krol'dok Stronghold", hideDone = true }), "More Fish", "a step that is done is hidden with the done ones")
		Quest.Status = was
		step.instance, step.types.Dungeon = nil, nil
		eq(names("", { zone = "Krol'dok Stronghold" }), "", "(and back as it was)")
	end)()
	;(function() -- an instance quest given outside: found under its instance as under its zone
		local e
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == "Daily Bread" then e = r.e end end
		e.instance = "Krol'dok Stronghold" -- (as OneForAll's lists, or the quest's own words, would have it)
		local got = {}
		for _, r in ipairs(Quest.Find("", { zone = "Krol'dok Stronghold" })) do got[#got + 1] = r.e.name end
		eq(table.concat(got, ","), "Daily Bread", "a zone picked finds the quests of the instance of that name")
		got = {}
		for _, r in ipairs(Quest.Find("", { zone = "Orgrimmar" })) do got[r.e.name] = true end
		eq(got["Daily Bread"], true, "and it stays under the zone it is given in")
		click(Quest.zoneButton)
		local listed
		for _, b in ipairs(Quest.zoneButton.menu.rows) do if b.shown and b.entry and b.entry.value == "Krol'dok Stronghold" then listed = b end end
		check(listed, "the zone list names the instance too")
		click(Quest.zoneButton)
		e.instance = nil
	end)()
	;(function() -- a quest filed under no zone (Forever's new ones): placed by what it asks, else by where it is given
		local e = { zone = 0, zoneName = "", types = {} }
		Quest.Place(e, { "Recover the Tome of Twilight from Krol'dok Stronghold." }, 1637)
		eq(e.instance, "Krol'dok Stronghold", "one that names an instance is that instance's"); eq(e.zone, 1637, "and of the zone it is given in besides"); eq(e.zoneName, "Orgrimmar", "by its name")
		e = { zone = 0, zoneName = "", types = {} }
		Quest.Place(e, { "Bring 4 Thick Leather and 12 Iron Bar to Kreza Darkthorn." }, 1637)
		eq(e.zone, 1637, "one that names none is of the zone it is given in"); eq(e.zoneName, "Orgrimmar", "by its name"); eq(e.instance, nil, "and of no instance")
		e = { zone = 0, zoneName = "", types = {} }
		Quest.Place(e, { "Kill the boss in The Hall of Thanes." }, nil)
		eq(e.instance, "The Hall of Thanes", "the longest name that fits is taken")
		eq(Quest.Canon("Hall of Thanes"), "The Hall of Thanes", "an instance goes by one name, with its The"); eq(Quest.Canon("Dire Maul: East"), "Dire Maul", "a wing under its dungeon")
		eq(Quest.Canon("Upper Blackrock Spire"), "Blackrock Spire", "an upper half too"); eq(Quest.Canon("Some New Hold"), "Some New Hold", "an unknown name stays")
		e = { zone = 0, zoneName = "", types = {} }
		Quest.Place(e, nil, nil)
		eq(e.zoneName, "", "nothing known: it stays without a zone")
	end)()
	eq(q("Fish for Gorak")[4], "Orgrimmar", "the zone by name")
	-- filters
	Quest.ticks.mine.checked = false
	click(Quest.ticks.mine)
	eq(#qrows(), 8, "Mine only off: everything"); eq(strip(q("Alliance Errand")[5]), "other race or side", "and why it is not for me")
	eq(strip(q("Mage Trial")[5]), "other class", "a class quest of another class"); eq(q("Mage Trial")[3], "Class", "labelled"); eq(q("Mage Trial")[4], "Mage", "filed under its class")
	Quest.ticks.mine.checked = true
	click(Quest.ticks.mine)
	Quest.ticks.obtainable.checked = true
	click(Quest.ticks.obtainable)
	eq(qnames(), "Daily Bread, Fish for Gorak", "Can take now: only what is open to me")
	Quest.ticks.obtainable.checked = false
	click(Quest.ticks.obtainable)
	qdone[100] = true
	B2.fire("QUEST_TURNED_IN")
	step(1)
	eq(qnames(), "Daily Bread, Deadmines Run, More Fish, Side Catch, The Big One", "a quest handed in drops out")
	eq(strip(q("More Fish")[5]), "open to you", "and the next of its chain opens"); eq(strip(q("Side Catch")[5]), "after: Alliance Errand", "the other still waits for its second")
	eq(nest(), "0 Daily Bread / 0 More Fish / 1 The Big One / 0 Side Catch / 0 Deadmines Run", "the done step is squeezed out: the chain now begins at its first open step")
	click(Quest.heads[2])
	eq(nest(), "0 Daily Bread / 0 More Fish / 0 Side Catch / 0 The Big One / 0 Deadmines Run", "a click on a header sorts the list flat")
	check(btext("sorted flat"), "and says so")
	click(Quest.clear)
	step(1)
	eq(nest(), "0 Daily Bread / 0 More Fish / 1 The Big One / 0 Side Catch / 0 Deadmines Run", "Clear nests it again")
	Quest.ticks.nested.checked = false
	click(Quest.ticks.nested)
	eq(nest(), "0 Daily Bread / 0 More Fish / 0 Side Catch / 0 The Big One / 0 Deadmines Run", "Nested off: flat, by level")
	Quest.ticks.nested.checked = true
	click(Quest.ticks.nested)
	Quest.ticks.hideDone.checked = false
	click(Quest.ticks.hideDone)
	eq(strip(q("Fish for Gorak")[5]), "done", "Hide done off: it is listed as done")
	eq(nest(), "0 Daily Bread / 0 Fish for Gorak / 1 More Fish / 2 The Big One / 1 Side Catch / 0 Deadmines Run", "and has its place at the head of the chain again")
	qdone[101] = true
	B2.fire("QUEST_TURNED_IN")
	step(1)
	eq(strip(q("The Big One")[5]), "needs Fishing 50", "a profession not high enough")
	fishing = 60
	B2.fire("QUEST_ACCEPTED")
	step(1)
	eq(strip(q("The Big One")[5]), "open to you", "high enough")
	qon[102] = true
	B2.fire("QUEST_ACCEPTED")
	step(1)
	eq(strip(q("The Big One")[5]), "in your log", "a quest I have")
	Quest.ticks.notLog.checked = true
	click(Quest.ticks.notLog)
	check(not q("The Big One") and q("Side Catch"), "Not in log: what I already carry is left out")
	Quest.ticks.notLog.checked = false
	click(Quest.ticks.notLog)
	;(function() -- In log only: the quests I carry, each with the rest of its chain
		Quest.ticks.onlyLog.checked = true
		click(Quest.ticks.onlyLog)
		check(q("The Big One"), "In log only: a quest I carry is listed")
		check(not q("Daily Bread") and not q("Deadmines Run"), "what is neither in my log nor of such a quest's chain is not")
		check(q("More Fish") and q("Side Catch"), "the rest of its chain comes along: " .. qnames())
		Quest.ticks.notLog.checked = true
		click(Quest.ticks.notLog)
		eq(Quest.db.onlyLog, false, "ticking Not in log unticks it: both cannot be"); eq(Quest.ticks.onlyLog.checked, false, "and its box shows that")
		Quest.ticks.onlyLog.checked = true
		click(Quest.ticks.onlyLog)
		eq(Quest.db.notLog, false, "and the other way round")
		local was = qon[102]
		qon[102] = nil
		B2.fire("QUEST_REMOVED")
		step(1)
		eq(qnames(), "", "nothing in my log: nothing listed")
		qon[102] = was
		B2.fire("QUEST_ACCEPTED")
		step(1)
		Quest.ticks.onlyLog.checked = false
		click(Quest.ticks.onlyLog)
		check(q("Daily Bread"), "unticked: everything again")
	end)()
	;(function() -- for the Dungeons tab: quests in nested order, with where each stands
		local found = Quest.Find("", {})
		local nested = Quest.Nested(found)
		eq(#nested, #found, "every quest found is in it")
		local at = {}
		for i, r in ipairs(nested) do at[r.e.name] = { i, r.depth, r.status } end
		check(at["More Fish"] and at["The Big One"] and at["The Big One"][1] > at["More Fish"][1], "a quest stands after the one that opens it")
		check(at["The Big One"][2] > at["More Fish"][2], "one step deeper"); check(at["The Big One"][3] ~= nil, "with where it stands")
		eq(Quest.STATUS_COLOR.done, "|cff40a040", "done is green"); eq(Quest.STATUS_COLOR.log, "|cffffd100", "in the log is yellow")
	end)()
	;(function() -- which side a quest is for, and the filter by it (for the Dungeons tab)
		local alliance, both
		for _, r in ipairs(Quest.Find("", {})) do
			if r.e.name == "Alliance Errand" then alliance = r.e elseif r.e.name == "Daily Bread" then both = r.e end
		end
		eq(alliance and Quest.Side(alliance), "A", "a quest open to an Alliance race only is Alliance's"); eq(Quest.Side(both), "", "one open to all is nobody's alone")
		local function has(f, name) for _, r in ipairs(Quest.Find("", f)) do if r.e.name == name then return true end end return false end
		eq(has({ side = "H" }, "Alliance Errand"), false, "the Horde's quests: an Alliance one is left out"); eq(has({ side = "A" }, "Alliance Errand"), true, "the Alliance's: it is there")
		eq(has({ side = "H" }, "Daily Bread"), true, "one open to both is on either list")
	end)()
	;(function() -- a quest that can be repeated: done once is done, and says it can be done again
		local run
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == "Deadmines Run" then run = r.e end end
		run.types.Repeatable = true
		eq(Quest.Status(run) ~= "done", true, "(not done to begin with)")
		B2.fire("QUEST_TURNED_IN", run.id, 100, 0)
		step(1)
		local status, why = Quest.Status(run)
		eq(status, "done", "handed in once while the addon looked: done, though the game keeps no such quest among the completed")
		eq(why, "done once (can be repeated)", "and it says it can be done again")
		local listed = false
		for _, r in ipairs(Quest.Find("", { hideDone = true })) do listed = listed or r.e == run end
		eq(listed, false, "hidden with the done ones")
		local guid = B2.env.UnitGUID("player")
		eq(Quest.db.turned[guid][run.id], true, "kept for this character")
		Quest.db.turned[guid][run.id] = nil
		B2.fire("QUEST_ACCEPTED")
		step(1)
		qdone[run.id] = true
		B2.fire("QUEST_ACCEPTED")
		step(1)
		eq(select(2, Quest.Status(run)), "done once (can be repeated)", "the same where the game itself says it was done")
		run.types.Daily = true
		eq(Quest.Status(run) ~= "done", true, "a daily is never done for good")
		run.types.Daily, qdone[run.id] = nil, nil
		B2.fire("QUEST_ACCEPTED")
		step(1)
		-- the repeat of a quest done once, with a number of its own: done as well, where the same giver hands out both
		local fish, pre, starts = Quest.Entry(100), run.preAll, run.starts
		local theirs = fish.starts
		run.preAll, run.starts, fish.starts = { 100 }, { { 777 } }, { { 778 } }
		eq(Quest.Status(run) ~= "done", true, "a repeatable quest after a done one of another giver: not its repeat, still open")
		fish.starts = { { 777 } }
		eq(select(2, Quest.Status(run)), "done once as: Fish for Gorak (can be repeated)", "of the same giver: the repeat of it, done once")
		run.preAll, run.starts, fish.starts, run.types.Repeatable = pre, starts, theirs, nil
		local parent = run.parent
		run.parent = 100
		eq(select(2, Quest.Status(run)), "only during: Fish for Gorak (done)", "a quest only to be had during another is over once that one is done")
		run.parent = parent
	end)()
	;(function() -- a quest the game does not remember: marked as done by hand, with a right-click
		local run
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == "Deadmines Run" then run = r.e end end
		eq(Quest.Mark(run), true, "marked: done"); eq(Quest.Status(run), "done", "and it counts as done")
		eq(Quest.Mark(run), false, "marked again: not done after all"); eq(Quest.Status(run) ~= "done", true, "and it does not")
		qdone[run.id] = true
		B2.fire("QUEST_ACCEPTED")
		step(1)
		eq(Quest.Mark(run), nil, "one the game itself says is done is left as it is"); eq(Quest.Status(run), "done", "done")
		qdone[run.id] = nil
		B2.fire("QUEST_ACCEPTED")
		step(1)
	end)()
	;(function() -- quests that shut each other out: one done is all of them done
		local run
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == "Deadmines Run" then run = r.e end end
		local was = run.excl
		run.excl = { 100 } -- (Fish for Gorak, which I have done)
		local status, why = Quest.Status(run)
		eq(status, "done", "a quest whose twin I have done counts as done"); eq(why, "done as: Fish for Gorak", "and says as which")
		local listed = false
		for _, r in ipairs(Quest.Find("", { hideDone = true })) do listed = listed or r.e == run end
		eq(listed, false, "so it is hidden with the done ones")
		run.excl = { 102 } -- (The Big One, which is in my log)
		status, why = Quest.Status(run)
		eq(status, "never", "one whose twin I carry cannot be taken"); eq(why, "shut while you have: The Big One", "and says why")
		listed = false
		for _, r in ipairs(Quest.Find("", { mine = true })) do listed = listed or r.e == run end
		eq(listed, false, "\"mine only\" leaves it out: its twin is in the list")
		for _, r in ipairs(Quest.Find("", {})) do listed = listed or r.e == run end
		eq(listed, true, "without that switch it is listed")
		run.excl = was
	end)()
	-- the level, coloured by how hard the quest is for me (level 10)
	eq(q("The Big One")[2], "|cffffff0012|r", "about my level: yellow"); eq(q("Deadmines Run")[2], "|cffff202020|r", "far above: red")
	eq(q("Daily Bread")[2], "|cff40c0405|r", "below: green")
	B2.env.GetQuestDifficultyColor = function() return { r = 0.5, g = 0.5, b = 0.5 } end
	Quest.Refresh()
	eq(q("Daily Bread")[2], "|cff7f7f7f5|r", "the game's own colour where it gives one")
	B2.env.GetQuestDifficultyColor = nil
	Quest.Refresh()
	-- searching, as on the NPC tab
	Quest.search:SetText("barrens")
	step(1)
	eq(qnames(), "Side Catch, The Big One", "by zone")
	Quest.search:SetText("dungon")
	step(1)
	eq(qnames(), "Deadmines Run", "by a label, misspelt")
	click(Quest.clear)
	step(1)
	eq(#qrows(), 4, "Clear: the filters as they began (two are done by now)")
	-- under a ticked Dungeon: its instances by name, green when every quest of one is done
	local function qside(part)
		for _, w in ipairs(B2.widgets) do
			if w.kind == "Button" and w.shown and (w.qtype or w.sub) and w.label and w.label.text:find(part, 1, true) then return w end
		end
	end
	check(qside("Dungeon") and not qside("Elwynn Forest"), "no instances listed before Dungeon is ticked")
	click(qside("Dungeon"))
	eq(qnames(), "Deadmines Run", "Dungeon ticked: the dungeon quests")
	eq(qside("Elwynn Forest").label.text, "    |cffffffffElwynn Forest|r |cff8888880/1|r", "and under it each instance, with how many of its quests are done")
	click(qside("Elwynn Forest"))
	eq(Quest.db.sub.Dungeon, "Elwynn Forest", "a click picks one"); eq(qnames(), "Deadmines Run", "its quests"); eq(qside("Elwynn Forest").sel.shown, true, "and it is lit")
	qdone[105] = true
	B2.fire("QUEST_TURNED_IN")
	step(1)
	eq(qside("Elwynn Forest").label.text, "    |cff40ff40Elwynn Forest|r |cff40a0401/1|r", "all of its quests done: green"); eq(#qrows(), 0, "and nothing left to list there")
	click(qside("Elwynn Forest"))
	eq(Quest.db.sub.Dungeon, nil, "clicked again: every dungeon")
	click(qside("Elwynn Forest"))
	click(qside("Dungeon"))
	eq(Quest.db.sub.Dungeon, nil, "unticking Dungeon forgets the instance"); check(not qside("Elwynn Forest"), "and the instances are gone from the list")
	qdone[105] = nil
	B2.fire("QUEST_TURNED_IN")
	step(1)
	-- the zone list, as on the NPC tab
	click(Quest.zoneButton)
	local qz = Quest.zoneButton.menu
	qz.box:SetText("barr")
	qz.box.scripts.OnEnterPressed(qz.box)
	eq(Quest.zoneButton.label.text, "Zone: The Barrens", "a zone typed and taken"); eq(qnames(), "Side Catch, The Big One", "its quests")
	click(Quest.zoneButton)
	click(qz.rows[2])
	eq(Quest.zoneButton.label.text, "Zone: here (Orgrimmar)", "where I am"); eq(qnames(), "Daily Bread", "the quests of the zone I stand in")
	click(Quest.clear)
	step(1)
	eq(Quest.zoneButton.label.text, "Zone: any", "Clear: any zone")
	;(function() -- a zone whose quests are all done is green in the list
		local function barrens()
			click(Quest.zoneButton)
			local text
			for _, b in ipairs(qz.rows) do if b.shown and b.entry and b.entry.value == "The Barrens" then text = b.label.text end end
			click(Quest.zoneButton)
			return text or "?"
		end
		check(barrens():find("|cffffffffThe Barrens", 1, true), "a zone with quests left is white in the list")
		local ids = {}
		for _, r in ipairs(Quest.Find("", { zone = "The Barrens" })) do if not qdone[r.e.id] then ids[#ids + 1] = r.e.id end end
		for _, id in ipairs(ids) do qdone[id] = true end
		B2.fire("QUEST_TURNED_IN"); step(1)
		check(barrens():find("|cff40a040The Barrens", 1, true), "green once all of them are done: " .. barrens())
		for _, id in ipairs(ids) do qdone[id] = nil end
		B2.fire("QUEST_TURNED_IN"); step(1)
	end)()
	-- the chain
	local function chainText(name)
		local e
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == name then e = r.e end end
		local out = {}
		for i, d in ipairs(Quest.Chain(e)) do out[i] = ("%d %s%s"):format(d.depth, d.e.name, d.again and " again" or "") end
		return table.concat(out, " / "), e
	end
	eq(chainText("The Big One"), "0 Fish for Gorak / 1 More Fish / 2 The Big One / 1 Side Catch", "a chain from where it starts, each step under the one before")
	eq(chainText("Side Catch"), "0 Fish for Gorak / 1 More Fish / 2 The Big One / 1 Side Catch / 0 Alliance Errand / 1 Side Catch again",
		"a quest that needs two stands under both, named once")
	eq(chainText("Daily Bread"), "0 Daily Bread", "a quest on its own is its own chain")
	q("The Big One") -- (listed)
	for _, w in ipairs(qrows()) do if w.data.e.name == "The Big One" then w.scripts.OnMouseUp(w) end end
	local chain = Quest.chain
	eq(chain.shown, true, "a click on a quest opens its chain"); eq(chain.title.text, "Chain of: The Big One", "named")
	eq(strip(chain.rows[1].text.text), "[8] Fish for Gorak  Gorak", "the first step, with who gives it")
	eq(strip(chain.rows[3].text.text), "        > [12] The Big One  Lumak", "a later one indented under it")
	eq(chain.rows[3].here.shown, true, "the quest asked about is marked"); eq(chain.rows[1].here.shown, false, "the others not")
	eq(chain.rows[5].shown, false, "and no more rows than quests")
	tom = nil
	click(chain.rows[1])
	eq(tom[1], 1454, "a click on a step: a waypoint to who gives it"); eq(tom[4], "Gorak (Fish for Gorak)", "named after both")
	local printed = #B2.printed
	click(chain.rows[4])
	check(B2.printed[#B2.printed]:find("Side Catch: started by no NPC", 1, true) and #B2.printed > printed, "one that nobody gives says so")
	eq(B2.DT.modules.quest.hello, nil, "the module has nothing to say on the guild channel: its rows go with the store")
	;(function() -- a quest no NPC gives: an object, an item, or (nothing known) whom it is handed in to
		local lib = B2.env.LibQuestieDB
		local wasObject, wasItemGet, wasQuestGet, wasPin, wasInfo = lib.Object, lib.Item and lib.Item.Get, lib.Quest.Get, B2.DT.Npc.Pin, B2.DT.Item.ShowInfo
		lib.Object = { Get = function(id, key) return id == 77 and ({ name = "Wanted Poster", spawns = { [17] = { { 40.5, 60.1 } } } })[key] or nil end }
		lib.Item = lib.Item or {}
		lib.Item.Get = function(id, key) if id == 88 and key == "name" then return "Strange Letter" end return wasItemGet and wasItemGet(id, key) end
		lib.Quest.Get = function(id, key)
			if id == 9903 and key == "sourceItemId" then return 88 end
			if id == 9904 and key == "finishedBy" then return { { 10 } } end
			if id >= 9900 then return nil end
			return wasQuestGet(id, key)
		end
		local function quest(id, starts) return { id = id, name = "Q" .. id, level = 10, min = 1, zone = 17, zoneName = "The Barrens", starts = starts or {}, types = {}, typeText = "" } end
		local o = Quest.Origin(quest(9901, { nil, { 77 } }))
		eq(o.kind, "object", "a quest an object gives: an object"); eq(o.text, "object: Wanted Poster", "by its name")
		local pinned
		B2.DT.Npc.Pin = function(area, x, y, title) pinned = { area, x, y, title } end
		Quest.Waypoint(quest(9901, { nil, { 77 } }))
		eq(pinned and pinned[1], 17, "its waypoint: the object's place"); eq(pinned[2], 40.5, "where it stands"); eq(pinned[4], "Wanted Poster (Q9901)", "named after both")
		o = Quest.Origin(quest(9902, { nil, nil, { 88 } }))
		eq(o.kind, "item", "a quest an item starts: an item"); eq(o.say, "Begins from an item: Strange Letter", "said in a sentence")
		eq(Quest.Origin(quest(9903)).text, "item: Strange Letter", "no beginning listed, but an item it starts with: that item")
		local shown
		B2.DT.Item.ShowInfo = function(e) shown = e end
		Quest.Waypoint(quest(9902, { nil, nil, { 88 } }))
		eq(shown and shown.id, 88, "its click: the window of where that item comes from")
		o = Quest.Origin(quest(9904))
		eq(o.kind, "turnin", "nothing known of the beginning: whom it is handed in to"); check(o.say:find("Handed in to", 1, true), "and said so: " .. o.say)
		eq(Quest.Origin(quest(9905)), nil, "nothing known at all: nothing")
		lib.Object, lib.Item.Get, lib.Quest.Get, B2.DT.Npc.Pin, B2.DT.Item.ShowInfo = wasObject, wasItemGet, wasQuestGet, wasPin, wasInfo
	end)()

	-- Items: read from QuestieDB too; what only the game knows of an item is asked once and kept
	do
		local Item = B2.DT.Item
		;(function() -- in a fight the long lists are left alone: the game cuts off a script that takes long there
			local guarded = 0
			for _, w in ipairs(B2.widgets) do
				if w.scripts and w.scripts.OnUpdate and w.fcols == nil then
					local finds, was = 0, Item.Find
					Item.Find = function(...) finds = finds + 1 return was(...) end
					B2.combat = true
					local ok = pcall(w.scripts.OnUpdate, w, 0.1)
					B2.combat = false
					Item.Find = was
					if ok and finds == 0 then guarded = guarded + 1 end
				end
			end
			check(guarded > 0, "the tabs' per-frame work does nothing in combat")
		end)()
		local ITEMDB = {
			[400] = { name = "Sword", requiredLevel = 20, itemLevel = 25, class = 2, subClass = 7, npcDrops = { 12 }, questRewards = { 102 } },
			[500] = { name = "Bid Only Axe", requiredLevel = 1, itemLevel = 5, class = 2, subClass = 0, vendors = { 10 } },
			[100] = { name = "Copper Bar", requiredLevel = 0, itemLevel = 10, class = 7, subClass = 7, objectDrops = { 77 } },
			[820] = { name = "Minor Potion", requiredLevel = 5, itemLevel = 5, class = 0, subClass = 1, itemDrops = { 600 }, startQuest = 107 },
			[600] = { name = "Grey Fang", requiredLevel = 0, itemLevel = 1, class = 15, subClass = 0 },
			[830] = { name = "Plans: Iron Thing", requiredLevel = 0, itemLevel = 25, class = 9, subClass = 4, vendors = { 10 } },
		}
		local ireads = 0
		B2.env.LibQuestieDB.Item = {
			GetAllIds = function() return { 100, 400, 500, 600, 820, 830 } end,
			GetAll = function(id, keys)
				ireads = ireads + 1
				local out = {}
				for i, key in ipairs(keys) do out[i] = ITEMDB[id][key] end
				return out
			end,
			Get = function(id, key) return ITEMDB[id] and ITEMDB[id][key] end,
		}
		B2.env.LibQuestieDB.Object = { Get = function(id, key) return id == 77 and ({ name = "Copper Vein", zoneID = 17 })[key] or nil end }
		B2.env.LibQuestieDB.Quest.Get = function(id, key) return QUESTS[id] and QUESTS[id][key] end
		local recipeKnown = false
		local STATS = { [400] = { ITEM_MOD_STAMINA_SHORT = 11, ITEM_MOD_STRENGTH_SHORT = 4 }, [500] = { ITEM_MOD_STAMINA_SHORT = 3 } }
		B2.env.GetItemStats = function(link) return STATS[tonumber(link:match("item:(%d+)"))] or {} end
		B2.env.C_TooltipInfo = { GetItemByID = function(id)
			local lines = { { leftText = ITEMDB[id].name } }
			if id == 400 then lines[#lines + 1] = { leftText = "Equip: Improves your chance to hit by 1%." } end
			if id == 830 then lines[#lines + 1] = { leftText = "Requires Blacksmithing (125)" } end
			if id == 830 and recipeKnown then lines[#lines + 1] = { leftText = "Already known" } end
			return { lines = lines }
		end }
		B2.env.AtlasLoot = { Data = { Profession = { GetCraftSpellForCreatedItem = function(id) return id == 100 and 2657 or nil end } } }
		ITEMS[400].slot, ITEMS[500].slot = "INVTYPE_WEAPON", "INVTYPE_WEAPON"
		B2.uncached = { [400] = true }
		Item.BATCH = 2
		B2.slash("item")
		check(btext("Reading items..."), "the reading says how far it is")
		step(1)
		;(function() -- DT.DB: one way to ask, whatever knows the answer
			local D = B2.DT.DB
			for rel, def in pairs(D.RELS) do
				local kinds = {}
				for _, kind in ipairs(D.KINDS) do kinds[kind] = true end
				check(kinds[def[2]], "the model: " .. rel .. " points at a kind there is")
				for _, from in ipairs(def[1]) do check(kinds[from], "the model: " .. rel .. " starts from a kind there is") end
			end
			local sword = D.Get("item", 400)
			eq(sword.name, "Sword", "an item by its number"); eq(sword.level, 20, "with its level"); eq(sword.src, "questie", "and where that is from")
			eq(D.Get("item", 424242), nil, "one nobody knows: nothing"); eq(D.Name("npc", 424242), "npc 424242", "or its number for a name")
			local drops = D.RelTo("drops", "item", 400)
			eq(#drops, 1, "who drops an item"); eq(drops[1].kind .. drops[1].id, "npc12", "an NPC"); eq(drops[1].src, "questie", "says QuestieDB")
			eq(D.RelTo("drops", "item", 100)[1].kind, "object", "an object in the world"); eq(D.RelTo("drops", "item", 820)[1].kind, "item", "or another item it is inside")
			eq(D.RelTo("sells", "item", 500)[1].id, 10, "who sells it"); eq(D.RelTo("rewards", "item", 400)[1].id, 102, "which quest gives it")
			eq(D.Rel("starts", "item", 820)[1].id, 107, "which quest it starts"); eq(#D.Rel("starts", "item", 400), 0, "or none")
			eq(#D.RelTo("no such relation", "item", 400), 0, "a relation not answered yet: no facts, no error")
			eq(D.ChanceText({ chance = 12 }), "12%", "a chance a source states")
			eq(D.ChanceText({ chance = 12, n = 5, k = 1 }), "12%, seen 1 of 5 looted (20%)", "beside what we saw")
			eq(D.ChanceText({ chance = 12, n = 52, k = 7 }), "7 of 52 looted (13%), stated 12%", "ours first once enough was looted")
			eq(D.ChanceText({}), "", "nothing known: nothing said")
		end)()
		eq(ireads, 6, "every item is read once"); check(btext("6 of 6 items"), "then they are all listed")
		local function inames(text, f)
			local found, state = Item.Find(text, f or {})
			local out = {}
			for i, r in ipairs(found) do out[i] = r.e.name end
			table.sort(out)
			return table.concat(out, ", "), state
		end
		eq(inames("sword"), "Sword", "found by name"); eq(inames("swrd"), "Sword", "letters in order will do")
		eq(inames("vendor"), "Bid Only Axe, Plans: Iron Thing", "or by where it comes from")
		eq(inames("", { source = "Vendor" }), "Bid Only Axe, Plans: Iron Thing", "the source filter"); eq(inames("", { source = "Crafted" }), "Copper Bar", "crafted, where AtlasLoot says so")
		eq(inames("", { source = "Chest" }), "Copper Bar", "found in an object"); eq(inames("", { source = "Container" }), "Minor Potion", "or inside another item")
		eq(inames("", { min = 5, max = 20 }), "Minor Potion, Sword", "required level")
		eq(inames("", { class = 2 }), "Bid Only Axe, Sword", "a kind of item"); eq(inames("", { class = 2, group = "1h" }), "Bid Only Axe, Sword", "and its group")
		eq(inames("", { class = 2, group = "2h" }), "", "another group: none")
		-- the Stats box
		local want = Item.ParseStats("sta>11 Int>=5 hit armour<9")
		eq(#want, 4, "the Stats box takes several wishes"); eq(want[1].stat .. want[1].op .. want[1].n, "sta>11", "a stat, a sign, a number")
		eq(want[2].stat .. want[2].op, "int>=", "whatever the case"); eq(want[3].word, "hit", "a word alone"); eq(want[4].stat, "armor", "other spellings")
		-- what only the game knows: asked once, then kept
		Item.db.known[400], B2.uncached[400] = nil, true -- (the rows on screen had it learned already: as if never seen)
		local names, state = inames("", { stats = "sta>10" })
		eq(names, "", "the sword is not known to the game yet: not listed for now"); eq(state.unknown, 1, "it is being asked for"); eq(state.of, 6, "of the six candidates")
		eq(Item.db.known[500].s.sta, 3, "the others are known at once, with their stats")
		step(2)
		eq(inames("", { stats = "sta>10" }), "Sword", "it has come: stamina above 10")
		local known = Item.db.known[400]
		eq(known.q, 2, "kept for good: its quality"); eq(known.e, "INVTYPE_WEAPON", "where it is worn"); eq(known.s.sta, 11, "its stats"); eq(known.s.str, 4, "all of them")
		check(known.x:find("chance to hit by 1%%"), "and its Equip lines")
		eq(inames("", { stats = "hit" }), "Sword", "a word alone: has it, here in an Equip line"); eq(inames("", { stats = "hit>=1" }), "Sword", "with the number read from that line")
		eq(inames("", { stats = "hit>1" }), "", "which is no more than it is"); eq(inames("", { stats = "sta<5" }), "Bid Only Axe", "less than")
		eq(inames("", { stats = "sta str>3" }), "Sword", "several: all must hold"); eq(inames("", { stats = "int" }), "", "a stat nothing has")
		eq(inames("", { quality = 2 }), "Bid Only Axe, Sword", "quality, which only the game knows"); eq(inames("", { quality = 3 }), "", "nothing rare")
		eq(Item.StatText(known), "11 sta, 4 str", "its stats in a line")
		-- usable: also the skill an item asks for, and whether I know it already (recipes)
		local smithing = 100
		B2.env.GetNumSkillLines = function() return 1 end
		B2.env.GetSkillLineInfo = function() return "Blacksmithing", false, false, smithing end
		B2.env.C_Item.GetItemSubClassInfo = function() return "Blacksmithing" end
		eq(inames("plans", { usable = true }), "", "a recipe that asks for Blacksmithing 125, at 100: not usable")
		eq(Item.db.known[830].rs, "Blacksmithing", "what it asks for is kept with the item's facts"); eq(Item.db.known[830].rn, 125, "and how high")
		smithing = 125
		eq(inames("plans", { usable = true }), "Plans: Iron Thing", "at 125: usable")
		recipeKnown = true
		B2.fire("NEW_RECIPE_LEARNED")
		eq(inames("plans", { usable = true }), "", "once I know it, it is of no use to me: not listed")
		eq(inames("plans", {}), "Plans: Iron Thing", "without Usable it is listed all the same")
		recipeKnown = false
		B2.fire("NEW_RECIPE_LEARNED")
		B2.env.GetSkillLineInfo = function() return "Tailoring", false, false, 300 end
		eq(inames("plans", { usable = true }), "", "without the profession at all: not usable")
		B2.env.GetNumSkillLines, B2.env.GetSkillLineInfo, B2.env.C_Item.GetItemSubClassInfo = nil, nil, nil
		Item.db.known[500].v = 1
		eq(inames("", { quality = 2 }), "Bid Only Axe, Sword", "facts kept in an older shape are learned anew, not trusted"); eq(Item.db.known[500].v, 2, "and kept in the new one")
		-- an item the game never delivers is asked for three times and then left alone: no endless learning
		;(function() -- (a function of its own: the test file is at the limit of local variables)
			local asks, real = 0, B2.env.C_Item.RequestLoadItemDataByID
			B2.env.C_Item.RequestLoadItemDataByID = function(id) if id == 400 then asks = asks + 1 else real(id) end end
			Item.db.known[400], B2.uncached[400] = nil, true
			local st
			for _ = 1, 6 do
				_, st = inames("", { quality = 1 })
				step(9) -- (no answer comes: it is not waited for for ever)
			end
			check(asks <= 3, "asked for no more than three times: " .. asks); eq(st.unknown, 0, "then it is no longer counted as being learned")
			eq(inames("", { quality = 1 }):find("Sword"), nil, "and is simply not listed under a filter that needs it")
			B2.env.C_Item.RequestLoadItemDataByID, B2.uncached[400] = real, nil
		end)()
		-- nothing empty goes to the saved file, and it reads back the same
		B2.fire("PLAYER_LOGOUT")
		eq(Item.db.known[600].s, nil, "an item with nothing on it: no empty table written"); eq(Item.db.known[600].x, nil, "nor an empty text")
		eq(inames("", { stats = "sta<5" }), "Bid Only Axe", "and it all reads back as before")
		-- more unknown items than can be asked for without a word
		local had = Item.db.known
		Item.db.known = {}
		Item.CAP = 2
		names, state = inames("", { quality = 1 })
		eq(state.capped, true, "too many unknown items: none is asked for"); eq(names, "", "and none listed"); eq(next(Item.db.known), nil, "nothing learned")
		Item.force = true
		names, state = inames("", { quality = 1 })
		eq(state.capped, false, "'Learn them anyway': it goes ahead"); check(next(Item.db.known) ~= nil, "and learns")
		Item.force, Item.CAP, Item.db.known = nil, 3000, had
		-- the rows
		local function irows()
			local out = {}
			for _, w in ipairs(B2.widgets) do
				if w.icols and w.shown and w.data then out[#out + 1] = w end
			end
			return out
		end
		Item.Refresh()
		eq(#irows(), 6, "a row each")
		local function irow(name) for _, w in ipairs(irows()) do if w.data.e.name == name then return w end end end
		eq(irow("Sword").icols[1].text, "|cff1eff00Sword|r", "in its quality colour, once known"); eq(irow("Sword").icols[2].text, "20", "its level")
		eq(irow("Sword").icols[5].text, "INVTYPE_WEAPON", "where it is worn"); eq(irow("Sword").icols[6].text, "Drop, Quest reward", "and where it comes from")
		Item.statBox:SetText("sta>10")
		step(1)
		eq(#irows(), 1, "typing in the Stats box filters, after a moment"); eq(irows()[1].data.e.name, "Sword", "the sword")
		click(Item.clear)
		step(1)
		eq(#irows(), 6, "Clear: all of them again")
		-- where it comes from
		local function lines(name)
			local out = {}
			for i, d in ipairs(Item.Sources(irow(name).data.e)) do out[i] = d.head or d.text end
			return (table.concat(out, " / "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
		end
		eq(lines("Sword"), "Dropped by (1) / Old Greyfin level 22-24  The Barrens / Reward of the quest (1) / The Big One", "who drops it, and which quest gives it")
		eq(lines("Bid Only Axe"), "Sold by (1) / Gorak level 30  Orgrimmar", "who sells it")
		eq(lines("Copper Bar"), "Found in (1) / Copper Vein  The Barrens / Made with a profession (a recipe makes it)", "what it is found in, and that it is made")
		eq(lines("Minor Potion"), "Inside (1) / Grey Fang / Starts the quest (1) / Daily Bread", "what it is inside of, and the quest it starts")
		check(lines("Grey Fang"):find("No source known", 1, true), "or that nothing is known")
		irow("Sword").scripts.OnMouseUp(irow("Sword"))
		local info = Item.info
		eq(info.shown, true, "a click on an item opens where it comes from"); eq(info.title.text, "|cff1eff00Sword|r", "headed by the item")
		check(info.sub.text:find("11 sta, 4 str", 1, true), "with its stats")
		tom = nil
		click(info.rows[2])
		eq(tom[4], "Old Greyfin", "a click on who drops it: a waypoint to it")
		Quest.chain.shown = false
		click(info.rows[4])
		eq(Quest.chain.shown, true, "a click on the quest: its chain")
		-- what a quest gives: experience from QuestieDB's table, money from the game, items from the Items reading
		;(function() -- (a function of its own: the main chunk has no room for more locals)
		B2.env.LibQuestieDB.Support = { Get = function(name) return name == "QuestXP" and { db = { [102] = { 20, 390 } } } or nil end }
		B2.env.GetQuestLogRewardMoney = function(id) return id == 102 and 1200 or 0 end
		local r = Quest.Rewards({ id = 102, name = "Q102", level = 20 })
		eq(r.xp, 390, "a quest's experience"); eq(r.money, 1200, "its money, where the game tells it"); eq(#r.items, 1, "its item")
		eq(r.items[1].name, "Sword", "by name"); eq(r.items[1].sell, ITEMS[400][4], "with what a vendor pays for it")
		local text = table.concat(Quest.RewardLines({ id = 102, name = "Q102", level = 20 }), "|")
		check(text:find("390 XP", 1, true) and text:find("Sword", 1, true) and text:find("12s", 1, true), "all of it in the chain window's lines: " .. text)
		check(Quest.chain.rewards.text:find("Rewards of", 1, true), "which the window shows")
		local none = Quest.Rewards({ id = 999999, name = "Nothing", level = 1 })
		eq(none.xp, nil, "a quest nothing is known of: no experience"); eq(#none.items, 0, "no items"); eq(none.money, nil, "no money")
		B2.env.GetQuestLogRewardMoney = nil
		-- a quest giver shows quest 103: what the window says is kept, and believed from then on
		local e = B2.env
		e.GetQuestID = function() return 103 end
		e.GetRewardMoney = function() return 250 end
		e.GetRewardXP = function() return 880 end
		e.GetNumQuestRewards = function() return 1 end
		e.GetNumQuestChoices = function() return 2 end
		e.GetQuestItemInfo = function(kind, i) return "x", 1, kind == "reward" and 5 or 1, 1, true, kind == "reward" and 100 or (i == 1 and 400 or nil) end
		e.GetQuestItemLink = function(kind, i) return kind == "choice" and i == 2 and "|cffffffff|Hitem:500::::|h[Bid Only Axe]|h|r" or nil end
		B2.fire("QUEST_DETAIL")
		local seen = B2.DT.Quest.SeenAll()[103]
		eq(seen.m, 250, "the money a quest giver showed is kept"); eq(seen.x, 880, "the experience"); eq(seen.l, 10, "at my level")
		eq(seen.r[1][1], 100, "what is given"); eq(seen.r[1][2], 5, "how many"); eq(seen.c[1][1], 400, "what there is to choose from"); eq(seen.c[2][1], 500, "told by its link where the number is not given")
		local got = Quest.Rewards({ id = 103, name = "Q103", level = 10 })
		eq(got.seen, true, "a quest that was seen"); eq(got.money, 250, "its money without being in the log"); eq(#got.items, 3, "its items")
		eq(got.items[1].choose, false, "what is given first"); eq(got.items[1].count, 5, "with the count"); eq(got.items[2].choose, true, "then the choices")
		check(table.concat(Quest.RewardLines({ id = 103, name = "Q103", level = 10 }), "|"):find("(choose one)", 1, true), "marked as a choice in the window")
		-- in the window each item is a row of its own: icon, hover, link
		e.GetItemIcon = function(id) return "icon" .. id end
		Quest.ShowRewards({ id = 103, name = "Q103", level = 10 })
		local items = Quest.chain.items
		eq(#items, 3, "a row for each item"); eq(items[1].shown, true, "shown"); eq(items[1].item.id, got.items[1].id, "the first is what is given")
		items[1].icon.SetTexture = function(self, texture) self.texture = texture end -- (the fake keeps no texture: kept here)
		Quest.ShowRewards({ id = 103, name = "Q103", level = 10 })
		eq(items[1].icon.texture, "icon" .. got.items[1].id, "with its icon")
		check(items[1].text.text:find(" x5", 1, true), "its count: " .. items[1].text.text); check(items[2].text.text:find("(choose one)", 1, true), "a choice is marked")
		check(not Quest.chain.rewards.text:find("(choose one)", 1, true), "the items are no longer lines of the text above")
		local linked, wasLink = nil, e.GameTooltip.SetHyperlink
		e.GameTooltip.SetHyperlink = function(_, link) linked = link end
		items[2].scripts.OnEnter(items[2])
		eq(linked, "item:" .. items[2].item.id, "hovering a row shows the item's own tooltip")
		e.GameTooltip.SetHyperlink = wasLink
		local wasShift, wasInsert, wasPopup = e.IsShiftKeyDown, e.ChatEdit_InsertLink, e.StaticPopup_Show
		local inserted, page
		e.IsShiftKeyDown = function() return true end
		e.ChatEdit_InsertLink = function(link) inserted = link return true end
		e.StaticPopup_Show = function(_, _, _, url) page = url end
		click(items[2])
		eq(inserted, B2.DT:GameItemLink(items[2].item.id, items[2].item.name), "a Shift-click puts the game's link of it in the chat line")
		click(items[2], "RightButton")
		eq(page, "https://www.wowhead.com/forever/item=" .. items[2].item.id, "a Shift-right-click shows its page")
		e.IsShiftKeyDown, e.ChatEdit_InsertLink, e.StaticPopup_Show, e.GetItemIcon = wasShift, wasInsert, wasPopup, nil
		-- Shift held over an item row: the game's comparison with what I wear
		local compares, hides, owner = 0, 0, nil
		local wasOwned, wasShift2 = e.GameTooltip.IsOwned, e.IsShiftKeyDown
		e.GameTooltip.IsOwned = function(_, frame) return frame == owner end
		e.GameTooltip_ShowCompareItem = function() compares = compares + 1 end
		e.GameTooltip_HideShoppingTooltips = function() hides = hides + 1 end
		e.IsShiftKeyDown = function() return false end
		owner = items[2]
		items[2].scripts.OnEnter(items[2])
		eq(compares, 0, "hovering an item without Shift: no comparison")
		e.IsShiftKeyDown = function() return true end
		B2.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		eq(compares, 1, "Shift pressed while its tooltip is up: compared with what I wear")
		e.IsShiftKeyDown = function() return false end
		local hidden = hides
		B2.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
		eq(hides, hidden + 1, "let go: the comparison is put away")
		e.IsShiftKeyDown = function() return true end
		items[2].scripts.OnEnter(items[2])
		eq(compares, 2, "hovering with Shift already held: compared at once")
		owner = nil
		B2.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		eq(compares, 2, "the tooltip is somebody else's by now: left alone")
		e.GameTooltip.IsOwned, e.IsShiftKeyDown, e.GameTooltip_ShowCompareItem, e.GameTooltip_HideShoppingTooltips = wasOwned, wasShift2, nil, nil
		Quest.ShowRewards({ id = 999999, name = "Nothing", level = 1 })
		eq(items[1].shown, false, "a quest without items: the rows are put away")
		-- asked for while it is open: it comes in front of the main window again
		local raised = 0
		Quest.chain.Raise = function() raised = raised + 1 end
		Quest.ShowChain(Quest.Entry(101) or Quest.Find("", {})[1].e)
		eq(raised, 1, "another quest clicked while the window is open: it is brought to the front")
		Quest.chain.Raise = nil
		-- what a member saw counts the same, for a quest I never saw (a row of the store)
		B2.DT.DB.Put("qreward:104", B2.DT.DBLogic.Pack({ 0, 0, 5, { 600, 1 }, {} }, 5))
		local shipped = Quest.Rewards({ id = 104, name = "Q104", level = 5 })
		eq(shipped.seen, true, "a quest in the store is known"); eq(shipped.money, 0, "no money is an answer too"); eq(shipped.items[1].id, 600, "its item")
		e.GetQuestID = nil
		end)()
		eq(B2.DT.modules.item.hello, nil, "the module has nothing to say to the guild")
		ITEMS[400].slot, ITEMS[500].slot = nil, nil
	end

	-- reading in the background: a few seconds after login, a little per frame, not in combat
	do
		local Bea = NewClient("Bea")
		Bea.env.LibQuestieDB, Bea.env.C_Map, Bea.env.GetRealZoneText = B2.env.LibQuestieDB, B2.env.C_Map, B2.env.GetRealZoneText
		local BN, BQ = Bea.DT.Npc, Bea.DT.Quest
		BN.BATCH, BQ.BATCH = 2, 3
		reads, qreads = 0, 0
		eq(Bea.DT.db.settings.background, true, "background reading is on unless switched off")
		step(4)
		eq(reads + qreads, 0, "nothing is read at login itself")
		Bea.combat = true
		step(3)
		eq(reads + qreads, 0, "nor in combat")
		Bea.combat = false
		step(0.1)
		check(reads > 0 and reads < 6, "then a little per frame: " .. reads)
		step(3)
		eq(reads, 6, "the NPCs are read, with no tab opened"); eq(qreads, 8, "and the quests after them")
		eq(BN.Ready(), true, "ready before their tabs are looked at"); eq(BQ.Ready(), true, "both")
		eq(#BN.Find("gorak", {}), 2, "and searchable")
		Bea.slash("npc")
		eq(reads, 6, "opening the tab reads nothing a second time")
		leave(Bea)
		-- a tab opened before the background reading has come to it finishes at once, and is not read twice
		local Cy = NewClient("Cy")
		Cy.env.LibQuestieDB, Cy.env.C_Map, Cy.env.GetRealZoneText = B2.env.LibQuestieDB, B2.env.C_Map, B2.env.GetRealZoneText
		Cy.DT.Npc.BATCH, Cy.DT.Quest.BATCH = 2, 3
		reads, qreads = 0, 0
		Cy.slash("quest")
		step(1)
		eq(qreads, 8, "a tab opened early reads at its own pace")
		step(8)
		eq(qreads, 8, "and the background reading does not read it again"); eq(reads, 6, "but does the other list")
		leave(Cy)
		-- switched off: as before, only when a tab is opened
		local Dee = NewClient("Dee")
		Dee.env.LibQuestieDB, Dee.env.C_Map = B2.env.LibQuestieDB, B2.env.C_Map
		Dee.DT.db.settings.background = false
		reads, qreads = 0, 0
		step(10)
		eq(reads + qreads, 0, "background reading switched off: nothing is read until a tab is opened")
		leave(Dee)
	end
	leave(B2)
end

-- Tools: a tab of sub-tabs; Range is one. Range: how far target and focus are, as numbers on screen
do
	local Tools, Range = A.DT.Tools, A.DT.Range
	local target, focus = Range.units[1].f, Range.units[2].f
	Range.SetMark(0) -- (the sweep over every button above pressed + a few times)
	local there = {}
	A.env.UnitExists = function(unit) return there[unit] or false end
	A.env.UnitIsUnit = function(a, b) return there[a] == "me" and b == "player" end
	eq(Range.Text(8, 10), "|cff0edfd2≤10|r", "a band, coloured by its far end: near"); eq(Range.Text(0, 5), "|cffe6e6e6≤5|r", "melee")
	eq(Range.Text(25, 30), "|cff09dd00≤30|r", "medium"); eq(Range.Text(30, 35), "|cffffd100≤35|r", "further")
	eq(Range.Text(40), "|cffe60e13>40|r", "only the near end known, 40 and beyond"); eq(Range.Text(40, 45), "|cffe60e13≤45|r", "far")
	eq(Range.Text(), nil, "nothing when the game says nothing")
	-- "my range": the edges of a band are exact, so inside or beyond 30 is known for certain
	eq(Range.Text(25, 30, 30), "|cff40ff40≤30|r", "my range 30: a band wholly inside it is green"); eq(Range.Text(30, 35, 30), "|cffff4040≤35|r", "one wholly beyond is red")
	eq(Range.Text(28, 33, 30), "|cffffd100≤33|r", "one that straddles it cannot tell: gold"); eq(Range.Text(40, nil, 30), "|cffff4040>40|r", "far beyond: red")
	eq(Range.Text(27.4, 27.4, 30), "|cff40ff4027|r", "an exact distance is one number")
	-- my own spells narrow the library's band
	local function tight(...) local lo, hi = Range.Tighten(...) return tostring(lo) .. " " .. tostring(hi) end
	eq(tight(25, 40, 30, 36), "30 36", "spells narrow both ends"); eq(tight(25, 40, nil, nil), "25 40", "no spell answered: the library's band")
	eq(tight(25, 40, 30, nil), "30 40", "only a no: the near end moves"); eq(tight(25, 40, nil, 36), "25 36", "only a yes: the far end")
	eq(tight(nil, nil, 30, 36), "30 36", "the library silent: the spells alone"); eq(tight(40, nil, nil, 36), "0 36", "they disagree: the spells are believed")
	eq(tight(25, 28, 30, 36), "30 36", "likewise the other way"); eq(tight(30, nil, 36, nil), "36 nil", "beyond the furthest spell: no far end")
	-- off until asked for
	there.target, A.ranges = true, { target = { 8, 10 }, focus = { 30, 35 } }
	A.fire("PLAYER_TARGET_CHANGED")
	eq(Range.db.settings.on, false, "Range is off to begin with"); eq(target.shown, false, "so a target has no number"); eq(Range.driver.shown, false, "and nothing runs")
	A.slash("range")
	eq(Tools.buttons[1].text, "|cffffd100Range|r", "its sub-tab is yellow while it is off"); eq(Range.ticks.on.checked, false, "and its box unticked")
	Range.ticks.on.checked = true
	click(Range.ticks.on)
	eq(Tools.buttons[1].text, "|cff40ff40Range|r", "switched on: green"); eq(target.shown, true, "and the number shows at once")
	there.target = nil
	A.fire("PLAYER_TARGET_CHANGED")
	eq(target.shown, false, "no target: no number"); eq(Range.driver.shown, false, "and nothing runs")
	there.target = true
	A.fire("PLAYER_TARGET_CHANGED")
	eq(target.shown, true, "a target: its number shows"); eq(focus.shown, false, "the focus has none of its own yet"); eq(Range.driver.shown, true, "and the readout runs")
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cff0edfd2≤10|r", "the band, in its colour")
	eq(target.sign.text, "|cff0edfd2≤|r", "the sign is a text of its own (the game's font has none)"); eq(target.text.text, "|cff0edfd210|r", "before the number, in the same colour")
	local asked = A.rangeAsked
	A.ranges.target = { 25, 30 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.05)
	eq(A.rangeAsked, asked, "not asked more than ten times a second")
	Range.driver.scripts.OnUpdate(Range.driver, 0.06)
	eq(target.last, "|cff09dd00≤30|r", "and follows as the distance changes")
	eq(Range.markText.text, "off", "no range of mine set to begin with")
	check(Range.edgesText.text:find("Against enemies:|r  5, 28, 30\n", 1, true), "the sub-tab lists the distances that can be told apart, in order, each once: " .. Range.edgesText.text)
	check(Range.edgesText.text:find("On friends:|r  none", 1, true), "and says none where the library gives none")
	for _ = 1, 6 do click(Range.markMore) end
	eq(Range.db.mark, 30, "the + button sets my range, five yards a click"); eq(Range.markText.text, "30 yd", "shown")
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cff40ff40≤30|r", "inside it: green")
	A.ranges.target = { 30, 35 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤35|r", "a step beyond: red, at once")
	-- every ranged spell of my spellbook is a test of its own, at its real range now
	local BOOK = {
		{ spellID = 10, name = "Fire Blast", maxRange = 20 }, { spellID = 11, name = "Polymorph", maxRange = 30 },
		{ spellID = 12, name = "Wrath", maxRange = 30 }, { spellID = 13, name = "Leather", maxRange = 0, isPassive = true },
		{ spellID = 14, name = "Bash", maxRange = 0 }, { spellID = 15, name = "Heal", maxRange = 40 },
		{ spellID = 16, name = "Aimed Shot", maxRange = 35, minRange = 8 },
	}
	local oldSpell = A.env.C_Spell
	local distance = 33
	A.env.C_SpellBook = {
		GetNumSpellBookSkillLines = function() return 1 end,
		GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #BOOK } end,
		GetSpellBookItemInfo = function(slot) return BOOK[slot] end,
	}
	A.env.C_Spell = setmetatable({
		GetSpellInfo = function(id) for _, s in ipairs(BOOK) do if s.spellID == id then return s end end end,
		IsSpellInRange = function(id)
			for _, s in ipairs(BOOK) do
				if s.spellID == id then
					if s.name == "Heal" then return nil end -- (not on an enemy)
					return distance <= s.maxRange and distance >= (s.minRange or 0)
				end
			end
		end,
	}, { __index = oldSpell })
	A.fire("SPELLS_CHANGED")
	A.ranges.target = { 25, 40 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤35|r", "the library says 25 to 40; my 30-yard spells do not reach and the 35-yard one does: 30 to 35")
	eq(Range.SpellEdges(), "20 Fire Blast, 30 Polymorph, 35 Aimed Shot, 40 Heal", "each distance my spells can tell, a passive and a melee one left out")
	BOOK[3].maxRange = 36 -- (a talent stretches Wrath)
	A.fire("PLAYER_TALENT_UPDATE")
	distance = 36
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤36|r", "a talent moves the edge: read anew, and 36 is an edge now (a shot with a least range is no proof of being out of range)")
	distance = 5
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	check(target.last:find("20|r", 1, true), "close in: no further than my shortest spell; the shot that is too near to fire does not count as out of range: " .. target.last)
	Range.Refresh()
	check(Range.edgesText.text:find("36 Wrath", 1, true), "the sub-tab names the spells and their ranges")
	A.env.C_SpellBook, A.env.C_Spell = nil, oldSpell
	A.fire("SPELLS_CHANGED")
	A.ranges.target = { 30, 35 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤35|r", "no spellbook to read: the library's band as it is")
	-- a member of my group, outdoors: the game tells where they stand
	local spots = { player = { 100, 200, 0, 1 }, target = { 100, 220, 0, 1 } }
	A.env.UnitPosition = function(unit) local p = spots[unit] if p then return p[1], p[2], p[3], p[4] end end
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cff40ff4020|r", "the exact distance where the game gives positions")
	spots.target[4] = 2
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤35|r", "not across instances: the band again")
	A.env.UnitPosition = nil
	for _ = 1, 6 do click(Range.markLess) end
	click(Range.markLess)
	eq(Range.db.mark, 0, "and - takes it off again, never below nothing")
	A.ranges.target = { 25, 30 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	there.focus = true
	A.fire("PLAYER_FOCUS_CHANGED")
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(focus.shown, true, "a focus: a second number"); eq(focus.last, "|cffffd100≤35|r", "its own")
	there.target = "me"
	A.fire("PLAYER_TARGET_CHANGED")
	eq(target.shown, false, "targeting myself: no number")
	there.target = true
	A.fire("PLAYER_TARGET_CHANGED")
	-- where it stands
	eq(target.placed, "free", "without the game's target frame: at its free place")
	A.env._G.TargetFrame = { portrait = {} }
	Range.Apply()
	eq(target.placed, "portrait", "with it: above its portrait"); eq(focus.placed, "free", "the focus frame is not there: free")
	-- the Tools tab and the Range sub-tab
	A.slash("range")
	eq(Tools.buttons[1].text, "|cff40ff40Range|r", "/dt range opens the Tools tab on the Range sub-tab"); eq(Tools.buttons[1].shown, true, "its sub-tab button is there")
	eq(Range.ticks.locked.checked, true, "locked to begin with"); eq(Range.ticks.portrait.checked, true, "and above the portrait"); eq(Range.sizeText.text, "16", "the size")
	eq(target.box.shown, false, "locked: no box to drag")
	Range.ticks.locked.checked = false
	click(Range.ticks.locked)
	eq(target.box.shown, true, "unlocked: a box to drag it by")
	there.focus = nil
	A.fire("PLAYER_FOCUS_CHANGED")
	eq(focus.shown, true, "unlocked, a readout shows without its unit, to be placed")
	target.scripts.OnDragStop(target)
	eq(target.placed, "free", "dragged: it stays where it was put, though above-the-portrait is on"); eq(Range.db.pos.target[1], "CENTER", "and the place is saved")
	target.scripts.OnMouseWheel(target, 1)
	eq(Range.db.size, 17, "the wheel over one makes it bigger"); eq(Range.sizeText.text, "17", "and the sub-tab follows")
	click(Range.smaller)
	click(Range.smaller)
	eq(Range.db.size, 15, "the - button makes it smaller")
	Range.SetSize(99)
	eq(Range.db.size, 32, "no bigger than 32")
	Range.SetSize(1)
	eq(Range.db.size, 8, "no smaller than 8")
	click(Range.reset)
	eq(target.placed, "portrait", "Reset positions: back above the portrait"); eq(Range.db.pos.target, nil, "the dragged place forgotten")
	Range.ticks.portrait.checked = false
	click(Range.ticks.portrait)
	eq(target.placed, "free", "above-the-portrait off: free")
	Range.ticks.portrait.checked = true
	click(Range.ticks.portrait)
	Range.ticks.locked.checked = true
	click(Range.ticks.locked)
	eq(focus.shown, false, "locked again: no number without a unit"); eq(target.box.shown, false, "and no box")
	Range.ticks.target.checked = false
	click(Range.ticks.target)
	eq(target.shown, false, "Range to my target off: gone"); eq(Range.driver.shown, false, "nothing left to run")
	Range.ticks.target.checked = true
	click(Range.ticks.target)
	A.env._G.TargetFrame = nil
	there.target = nil
	A.fire("PLAYER_TARGET_CHANGED")
	eq(A.DT.modules.range.hello, nil, "the module has nothing to say to the guild"); eq(A.env.SLASH_DAWNTOOLS_RANGE1, "/dtrange", "its short command")
end

-- Tracker: a button that targets a name and marks it
do
	local Tools, Tracker = A.DT.Tools, A.DT.Tracker
	local b = Tracker.button
	Tracker.Set("on", false)
	Tracker.SetName("")
	Tracker.SetMark("ping")
	Tracker.SetGrow("CENTER")
	Tracker.Reset()
	eq(Tracker.Macro("Old Greyfin", "ping", true), "/cleartarget\n/tar Old Greyfin\n/ping [@target,exists,nodead]\n/targetlasttarget [noexists]\n/startattack [combat,harm,nodead]",
		"the click, as one macro: look afresh, ping it only if it is there and alive, else my old target back")
	eq(Tracker.Macro("Old Greyfin", "ping", false), "/cleartarget\n/tar Old Greyfin\n/ping [@target,exists,nodead]",
		"with no target to begin with there is none to put back (an old 'last target' is not dug up)")
	eq(Tracker.Macro("Rex", "icon", true), "/cleartarget\n/tar Rex\n/tm [@target,exists,nodead] 8\n/targetlasttarget [noexists]\n/startattack [combat,harm,nodead]", "or a raid icon")
	eq(Tracker.Macro("Rex", "none", true), "/cleartarget\n/tar Rex\n/targetlasttarget [noexists]\n/startattack [combat,harm,nodead]", "or nothing but the target")
	eq(Tracker.Macro("", "ping"), "", "no name: the click does nothing")
	eq(Tracker.Clean("  Old\nGreyfin  "), "Old Greyfin", "a name is one line, trimmed"); eq(#Tracker.Clean(("x"):rep(200)), 60, "and no longer than 60")
	eq(Tracker.Clean("Old;[Grey]fin"), "OldGreyfin", "macro signs are taken out of a name")
	eq(Tracker.Clean(("x"):rep(59) .. "\195\169"), ("x"):rep(59), "a letter cut in half at the limit goes whole")
	eq(b.shown, false, "the tracker is off to begin with")
	eq(b.attr.type1, "macro", "a left click runs a macro"); eq(b.attr["shift-type1"], "", "a shift-click does nothing: shift is for dragging")
	A.slash("tracker")
	local tab
	for _, w in ipairs(Tools.buttons) do if w.id == "tracker" then tab = w end end
	eq(tab.text, "|cffffd100Tracker|r", "its sub-tab, yellow while off")
	Tracker.onBox.checked = true
	click(Tracker.onBox)
	eq(b.shown, true, "switched on: the button shows"); eq(tab.text, "|cff40ff40Tracker|r", "and its sub-tab is green")
	eq(b.label.text, "|cff888888Right-click: set a name|r", "it says how to give it a name"); eq(b.width, 160, "as wide as that text")
	-- the name, by right click
	b.scripts.PostClick(b, "RightButton", true)
	eq(A.popups[#A.popups] == "DAWNTOOLS_TRACKER", false, "the right button on its way down asks nothing yet")
	b.scripts.PostClick(b, "RightButton", false)
	eq(A.popups[#A.popups], "DAWNTOOLS_TRACKER", "on its way up it asks for the name")
	b.scripts.PostClick(b, "LeftButton", false)
	local box = { text = "Rex", GetText = function(self) return self.text end }
	A.env.StaticPopupDialogs.DAWNTOOLS_TRACKER.OnAccept({ editBox = box })
	eq(Tracker.db.name, "Rex", "OK takes the name up"); eq(b.label.text, "|cffffd100Rex|r", "shown on the button")
	eq(b.attr["dt-keep"], "/cleartarget\n/tar Rex\n/ping [@target,exists,nodead]\n/targetlasttarget [noexists]\n/startattack [combat,harm,nodead]", "and in its macro for when I have a target")
	eq(b.attr["dt-plain"], "/cleartarget\n/tar Rex\n/ping [@target,exists,nodead]", "and in the one for when I have none")
	check(A.wrapBody and A.wrapBody:find("[@target,exists] dt-keep; dt-plain", 1, true), "which of the two a click runs is picked as it comes, by whether I have a target")
	-- the tooltip keeps out of the way of a shift-drag
	A.env.GameTooltip.shown = false
	b.scripts.OnEnter(b)
	eq(A.env.GameTooltip.shown, true, "hovering shows what the clicks do")
	A.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	eq(A.env.GameTooltip.shown, false, "Shift pressed over it: the tooltip goes")
	A.env.IsShiftKeyDown = function() return true end
	b.scripts.OnEnter(b)
	eq(A.env.GameTooltip.shown, false, "and does not come up while Shift is held")
	A.env.IsShiftKeyDown = nil
	b.scripts.OnLeave(b)
	Tracker.tipBox.checked = false
	click(Tracker.tipBox)
	b.scripts.OnEnter(b)
	eq(A.env.GameTooltip.shown, false, "the tooltip switched off on the sub-tab: hovering shows nothing")
	b.scripts.OnLeave(b)
	Tracker.tipBox.checked = true
	click(Tracker.tipBox)
	eq(b.width, 90, "a short name: no narrower than the least width")
	Tracker.SetName("A Very Long Name Of A Rare Mob Indeed")
	eq(b.width, 37 * 6 + 22, "a long one: as wide as it needs")
	-- what it grows from
	eq(b.hung, "CENTER", "hung by its centre to begin with")
	b.left, b.right, b.mid = 400, 644, 300
	b.moving = true
	b.scripts.OnDragStop(b)
	eq(Tracker.db.pos[1], 522, "dragged: the place of its centre is kept"); eq(Tracker.db.pos[2], 300, "and its height")
	click(Tracker.growButton)
	click(Tracker.growButton.menu.rows[1])
	eq(Tracker.db.grow, "LEFT", "Grow from left, picked from the list"); eq(Tracker.db.pos[1], 400, "it stays where it is: now its left edge is what is kept")
	eq(b.hung, "LEFT", "and what it hangs by"); eq(Tracker.growButton.label.text, "Grow from: Left (grows to the right)", "named on the button")
	Tracker.SetGrow("RIGHT")
	eq(Tracker.db.pos[1], 644, "from the right: its right edge")
	-- the mark
	click(Tracker.markButton)
	click(Tracker.markButton.menu.rows[2])
	eq(Tracker.db.mark, "icon", "the mark picked from the list"); check(b.attr["dt-keep"]:find("/tm [@target,exists,nodead] 8", 1, true), "is in the macro")
	-- in combat nothing of the button may be changed: it waits
	A.combat = true
	Tracker.SetName("Boar")
	eq(b.label.text, "|cffffd100A Very Long Name Of A Rare Mob Indeed|r", "a name set in combat is not taken up yet")
	check(A.printed[#A.printed]:find("taken up when the fight is over", 1, true), "and chat says so")
	check(Tracker.note.text:find("Waiting for the fight to end", 1, true), "so does the sub-tab")
	A.combat = false
	A.fire("PLAYER_REGEN_ENABLED")
	eq(b.label.text, "|cffffd100Boar|r", "the fight over: taken up"); check(b.attr["dt-plain"]:find("/tar Boar", 1, true), "in the macro too")
	-- the name from the sub-tab's own box
	Tracker.nameBox:SetText("Old Greyfin")
	Tracker.nameBox.scripts.OnEnterPressed(Tracker.nameBox)
	eq(Tracker.db.name, "Old Greyfin", "the box on the sub-tab sets it as well")
	click(Tracker.reset)
	eq(Tracker.db.pos, nil, "Reset position: back to where it began")
	-- a macro for a key: it clicks the button, so it needs no rewriting when the name changes
	local macros, picked = {}, nil
	A.env.GetMacroIndexByName = function(name) for i, m in ipairs(macros) do if m.name == name then return i end end return 0 end
	A.env.CreateMacro = function(name, icon, body) macros[#macros + 1] = { name = name, body = body, icon = icon } return #macros end
	A.env.EditMacro = function(i, name, _, body) macros[i].body = body end
	A.env.GetMacroBody = function(i) return macros[i] and macros[i].body end
	A.env.PickupMacro = function(i) picked = i end
	Tracker.macroDone = nil
	Tracker.Apply()
	eq(#macros, 1, "with the tracker switched on its macro is simply there, in the macro list"); eq(macros[1].name, "DT Tracker", "named")
	eq(macros[1].body, Tracker.Macro("Old Greyfin", Tracker.db.mark, true), "it holds the commands themselves, the name in them"); check(#macros[1].body <= 255, "and fits a macro"); eq(macros[1].icon, "Ability_Hunter_Pet_Wolf", "with a beast for an icon"); eq(picked, nil, "nothing is put on the cursor unasked")
	Tracker.Apply()
	eq(#macros, 1, "made once, not again and again")
	click(Tracker.macroButton)
	eq(picked, 1, "the button puts it on the cursor, to drop on a bar"); eq(#macros, 1, "the same one")
	macros[1].body = "/dance"
	click(Tracker.macroButton)
	eq(#macros, 1, "pressed again: no second one"); eq(macros[1].body, Tracker.Macro("Old Greyfin", Tracker.db.mark, true), "the one there is put right")
	Tracker.SetName("Rex")
	check(macros[1].body:find("/tar Rex", 1, true), "a new name is written into the macro"); eq(#macros, 1, "the same macro")
	Tracker.SetName("Old Greyfin")
	A.combat = true
	picked = nil
	click(Tracker.macroButton)
	eq(picked, nil, "not in combat"); check(A.printed[#A.printed]:find("cannot be made in combat", 1, true), "it says so")
	A.combat = false
	eq(A.DT.modules.tracker.hello, nil, "the module has nothing to say to the guild"); eq(A.env.SLASH_DAWNTOOLS_TRACKER1, "/dttracker", "its short command")
	Tracker.Set("on", false)
	;(function() -- Enemies: the enemy players in sight, who is on me first
		local En, e = A.DT.Enemies, A.env
		local was = { e.UnitExists, e.UnitIsPlayer, e.UnitCanAttack, e.UnitIsUnit, e.UnitName, e.UnitClass, e.UnitLevel, e.C_NamePlate, e.PlaySound }
		-- unit = { name, class, file, level, enemy player, on me }
		local units = { nameplate1 = { "Gank Alot", "Rogue", "ROGUE", 60, true, true }, nameplate2 = { "Zed Foe", "Mage", "MAGE", -1, true, false },
			nameplate3 = { "Friend Lee", "Priest", "PRIEST", 40, false, false }, target = { "Zed Foe", "Mage", "MAGE", -1, true, false } }
		e.UnitExists = function(u) return units[u] ~= nil end
		e.UnitIsPlayer = function(u) return units[u] ~= nil end
		e.UnitCanAttack = function(_, u) return units[u] and units[u][5] or false end
		e.UnitIsUnit = function(a, b) local u = a:match("^(.*)target$") return b == "player" and units[u] and units[u][6] or false end
		e.UnitName = function(u) return units[u] and units[u][1] end
		e.UnitClass = function(u) if units[u] then return units[u][2], units[u][3] end end
		e.UnitLevel = function(u) return units[u] and units[u][4] end
		e.C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" }, { namePlateUnitToken = "nameplate3" } } end }
		local sounds = 0
		e.PlaySound = function() sounds = sounds + 1 end
		local lib = En.lib
		En.lib = { GetRange = function(_, u) if u == "nameplate1" then return 8, 10 end if u == "target" or u == "nameplate2" then return 30, 35 end end }

		En.Scan()
		local list = En.List()
		eq(#list, 2, "the enemy players in sight, each once (a friend is not one)")
		eq(list[1].name, "Gank Alot", "who has me targeted first"); eq(list[1].onMe, true, "marked")
		check(En.LineText(list[1], 0):find("Gank Alot|r  60 Rogue  |cffcccccc8-10 yd|r  |cffff3030ON YOU|r", 1, true), "name, level, class, how far, and ON YOU: " .. En.LineText(list[1], 0))
		check(En.LineText(list[2], 0):find("Zed Foe|r  ?? Mage  |cffcccccc30-35 yd|r", 1, true) and not En.LineText(list[2], 0):find("ON YOU", 1, true),
			"one too far above me to be told shows ??, and is not on me")
		eq(En.alert, "onMe", "somebody on me is worth the louder sound")
		;(function() -- the game will not say whose target they have (as it may in combat): said, not passed off as "not on me"
			local wasUnit, wasSecret = e.UnitIsUnit, e.issecretvalue
			e.UnitIsUnit = function() return "hidden" end
			e.issecretvalue = function(v) return v == "hidden" end
			En.Scan()
			local l = En.List()
			eq(l[1].blind, true, "a target the game hides is not known"); eq(l[1].onMe, false, "and not counted as on me")
			check(En.LineText(l[1], 0):find("target hidden", 1, true), "the line says so: " .. En.LineText(l[1], 0))
			e.UnitIsUnit = function() error("not allowed") end
			En.Scan()
			eq(En.List()[1].blind, true, "nor is one the game refuses outright")
			e.UnitIsUnit, e.issecretvalue = wasUnit, wasSecret
			En.Scan()
			eq(En.List()[1].blind, false, "told again: known again")
			En.alert = "onMe"
		end)()
		-- the nearest first among those not on me
		units.nameplate1[6] = false
		units.nameplate4 = { "Far Away", "Hunter", "HUNTER", 50, true, false }
		e.C_NamePlate.GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" }, { namePlateUnitToken = "nameplate4" } } end
		En.Scan()
		list = En.List()
		eq(list[1].name, "Gank Alot", "nobody on me: the nearest first"); eq(list[3].name, "Far Away", "one whose distance is not known last")
		-- on screen, with its sound
		En.Set("on", true)
		En.alert = "onMe"
		En.Tick()
		eq(En.frame.shown, true, "switched on: the list shows"); eq(sounds, 1, "with a sound for the news")
		-- moved as the Tracker is: only with Shift held
		local f, moved = En.frame, 0
		local wasShift, wasMove = e.IsShiftKeyDown, f.StartMoving
		f.StartMoving = function() moved = moved + 1 end
		e.IsShiftKeyDown = function() return false end
		f.scripts.OnDragStart(f)
		eq(moved, 0, "a plain drag does not move it")
		f.scripts.OnEnter(f)
		check(table.concat(e.GameTooltip.lines or {}, "|"):find("Hold Shift and drag to move", 1, true), "its tooltip says how to move it")
		En.Set("tips", false)
		e.GameTooltip.lines = {}
		f.scripts.OnEnter(f)
		eq(#(e.GameTooltip.lines or {}), 0, "the tooltip can be switched off")
		En.Set("tips", true)
		-- (clicks are taken only while Shift is held: otherwise they go through to the world)
		local clicks
		f.SetMouseClickEnabled = function(_, on) clicks = on end
		e.IsShiftKeyDown = function() return true end
		A.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		eq(clicks, true, "Shift pressed: the list takes clicks, to be dragged")
		A.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
		eq(clicks, true, "another key changes nothing")
		f.scripts.OnDragStart(f)
		eq(moved, 1, "with Shift held it does")
		local wasCenter = f.GetCenter
		f.GetCenter = function() return 500, 400 end
		f.scripts.OnDragStop(f)
		check(En.db.pos and En.db.pos[1] == "CENTER" and En.db.pos[3] == 500, "and where it was put is kept")
		-- Shift let go in mid-drag: put down where it is, and click-through again
		f.scripts.OnDragStart(f)
		f.GetCenter = function() return 640, 300 end
		e.IsShiftKeyDown = function() return false end
		A.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
		eq(En.db.pos[3], 640, "Shift let go in mid-drag: it is put down where it is"); eq(clicks, false, "and clicks go through it again")
		-- locked: Shift or no Shift, it stays
		eq(En.db.settings.locked, false, "it is not locked to begin with")
		En.Set("locked", true)
		e.IsShiftKeyDown = function() return true end
		A.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		eq(clicks, false, "locked: Shift does not make it take clicks")
		f.scripts.OnDragStart(f)
		eq(moved, 2, "and a Shift-drag does not move it")
		e.IsShiftKeyDown = function() return false end -- (with Shift held the tooltip keeps out of the way)
		e.GameTooltip.lines = {}
		f.scripts.OnEnter(f)
		check(table.concat(e.GameTooltip.lines or {}, "|"):find("Locked in place", 1, true), "its tooltip says it is locked")
		e.IsShiftKeyDown = function() return true end
		En.Set("locked", false)
		eq(clicks, true, "unlocked with Shift held: it takes clicks again")
		check(En.boxes.locked, "a tick box for the lock")
		f.SetMouseClickEnabled = nil
		e.IsShiftKeyDown, f.StartMoving, f.GetCenter = wasShift, wasMove, wasCenter
		check(En.frame.title.text:find("Enemies: 3", 1, true), "its title counts them"); check(En.frame.lines[1].text:find("Gank Alot", 1, true), "a line each")
		-- out of sight: listed a while as lost, then forgotten
		e.C_NamePlate.GetNamePlates = function() return {} end
		units.target = nil
		step(4)
		En.Scan()
		list = En.List()
		eq(#list, 3, "out of sight they stay listed for a while"); check(En.LineText(list[1], e.GetTime()):find("lost %d+s ago"), "as lost, with how long ago")
		eq(list[1].onMe, false, "who they are on is not known any more")
		step(8)
		En.Scan()
		eq(#En.List(), 0, "and are forgotten after ten seconds")
		En.Tick()
		check(En.frame.title.text:find("none in sight", 1, true), "the list says there is nobody")
		En.Set("on", false)
		eq(En.frame.shown, false, "switched off: gone")
		En.lib = lib
		e.UnitExists, e.UnitIsPlayer, e.UnitCanAttack, e.UnitIsUnit, e.UnitName, e.UnitClass, e.UnitLevel, e.C_NamePlate, e.PlaySound = was[1], was[2], was[3], was[4], was[5], was[6], was[7], was[8], was[9]
	end)()
	;(function() -- Carrot: on when I mount, my trinket back when I dismount
		local Car, e = A.DT.Carrot, A.env
		local worn, mounted, taxi, asked = { [13] = 501, [14] = 502 }, false, false, 0
		local have = true
		e.GetInventoryItemID = function(_, slot) return worn[slot] end
		e.IsMounted = function() return mounted end
		e.UnitOnTaxi = function() return taxi end
		e.GetItemCount = function(id) return id == Car.ITEM and have and 1 or 0 end
		e.EquipItemByName = function(item, slot)
			asked = asked + 1
			if not A.combat then worn[slot] = item end -- (the game changes no trinket in combat)
		end
		local function mount(on) mounted = on; A.fire("PLAYER_MOUNT_DISPLAY_CHANGED"); step(1.1) end
		A.DT.Tools.Open("carrot")
		eq(Car.db.settings.on, false, "off to begin with"); eq(Car.db.settings.slot, 14, "the bottom trinket is the one to make room")
		mount(true)
		eq(worn[14], 502, "switched off: mounting changes nothing")
		mount(false)
		Car.boxes.on.checked = true
		click(Car.boxes.on)
		mount(true)
		eq(worn[14], Car.ITEM, "mounted: the carrot is on, in the slot picked"); eq(worn[13], 501, "the other trinket stays")
		eq(Car.db.back[1], 502, "what it replaced is kept")
		local n = asked
		A.fire("UNIT_AURA", "player"); step(1.1)
		eq(asked, n, "told again while mounted: nothing more is asked of the game")
		mount(false)
		eq(worn[14], 502, "dismounted: my trinket is back"); eq(Car.db.back, nil, "and nothing is owed")
		-- the other slot
		click(Car.boxes[13])
		eq(Car.db.settings.slot, 13, "the top trinket picked"); eq(Car.boxes[13].checked, true, "its box ticked"); eq(Car.boxes[14].checked, false, "the other not")
		mount(true)
		eq(worn[13], Car.ITEM, "the carrot takes the top slot now"); eq(worn[14], 502, "the bottom one stays")
		check(Car.boxes[13].label.text:find("501", 1, true), "while the carrot is on, the slot is named by what comes back: " .. tostring(Car.boxes[13].label.text))
		-- knocked off the mount in a fight: it waits for the fight's end
		A.combat = true
		mount(false)
		eq(worn[13], Car.ITEM, "dismounted in combat: the carrot stays on")
		A.combat = false
		A.fire("PLAYER_REGEN_ENABLED"); step(1.1)
		eq(worn[13], 501, "the fight over: my trinket is back")
		-- a flight path is no mount; no carrot, no swap
		taxi = true
		mount(true)
		eq(worn[13], 501, "on a flight path: nothing")
		taxi = false
		mount(false)
		have = false
		mount(true)
		eq(worn[13], 501, "without a carrot: nothing"); eq(Car.db.back, nil, "and nothing kept")
		mount(false)
		have = true
		-- switched off while it is on: what was taken off still comes back
		mount(true)
		Car.boxes.on.checked = false
		click(Car.boxes.on)
		mount(false)
		eq(worn[13], 501, "switched off on the mount: my trinket still comes back")
		e.GetInventoryItemID, e.IsMounted, e.UnitOnTaxi, e.GetItemCount, e.EquipItemByName = nil, nil, nil, nil, nil
	end)()
end

-- MP5: the five-second rule, counted from my own casts of spells that cost mana
do
	local Tools, Mp5 = A.DT.Tools, A.DT.Mp5
	local f, spark, driver = Mp5.f, Mp5.spark, Mp5.driver
	Mp5.Reset()
	Mp5.Set("locked", true)
	Mp5.Set("on", false) -- (the sweep over every button above may have pressed things)
	Mp5.SetLook("spark")
	local oldSpell, oldClass = A.env.C_Spell, A.env.UnitClass
	local COST = { [133] = { { type = 0, cost = 30 } }, [1] = { { type = 1, cost = 15 } }, [2] = { { type = 0, cost = 0 } }, [5143] = { { type = 0, cost = 85 } } }
	A.env.C_Spell = setmetatable({ GetSpellPowerCost = function(id) return COST[id] end }, { __index = oldSpell })
	A.env.UnitClass = function() return "Mage", "MAGE" end
	local function cast(id) A.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", id) end
	eq(Mp5.CostsMana(133), true, "a spell that costs mana"); eq(Mp5.CostsMana(1), false, "one that costs rage does not")
	eq(Mp5.CostsMana(2), false, "nor a free one"); eq(Mp5.CostsMana(999), false, "nor one the game knows nothing of")
	-- off until asked for
	cast(133)
	eq(driver.shown, false, "MP5 is off to begin with: a cast shows nothing")
	A.slash("mp5")
	local tab
	for _, b in ipairs(Tools.buttons) do if b.id == "mp5" then tab = b end end
	eq(tab.text, "|cffffd100MP5|r", "its sub-tab, yellow while off"); eq(Mp5.lookButton.label.text, "Look: Spark on my mana bar", "the spark is the look to begin with")
	Mp5.ticks.on.checked = true
	click(Mp5.ticks.on)
	eq(tab.text, "|cff40ff40MP5|r", "switched on: green"); eq(driver.shown, false, "idle: nothing runs")
	-- without the game's mana bar the spark has nowhere to run: the thin bar instead
	eq(Mp5.Look(), "bar", "no mana bar of the game's: the thin bar"); check(Mp5.note.text:find("thin bar is shown instead", 1, true), "and the sub-tab says so")
	cast(1)
	eq(driver.shown, false, "a spell that costs no mana starts nothing")
	cast(133)
	eq(driver.shown, true, "a mana spell starts the five seconds"); eq(f.shown, true, "the bar shows"); eq(f.part, 1, "full")
	eq(f.text.text, "5.0", "with the seconds beside it")
	step(2.5)
	check(math.abs(f.part - 0.5) < 0.02, "half way after two and a half seconds: " .. f.part); eq(f.text.text, "2.5", "the seconds follow")
	cast(133)
	eq(f.part, 1, "another mana spell starts it again")
	step(5.1)
	eq(f.shown, false, "five seconds on: gone"); eq(driver.shown, false, "and nothing runs any more")
	-- a channelled spell holds it
	A.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-2", 5143)
	step(8)
	eq(driver.shown, true, "a channelled mana spell holds the count"); eq(f.part, 1, "full, however long it lasts")
	A.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-2", 5143)
	step(2.5)
	check(math.abs(f.part - 0.5) < 0.02, "the five seconds run from its end")
	step(3)
	eq(f.shown, false, "and end")
	-- the spark, on the game's own mana bar
	A.env._G.PlayerFrameManaBar = { GetWidth = function() return 100 end, GetHeight = function() return 12 end, IsVisible = function() return true end }
	Mp5.Apply()
	Mp5.Refresh()
	eq(Mp5.Look(), "spark", "with the game's mana bar: the spark"); check(not Mp5.note.text:find("mana bar is not there", 1, true), "no word about falling back")
	cast(133)
	eq(spark.shown, true, "a cast: the spark is on the bar"); eq(spark.at, 1, "at its right end"); eq(f.shown, false, "the other looks are not shown")
	step(2.5)
	check(math.abs(spark.at - 0.5) < 0.02, "half way along after half the time")
	step(3)
	eq(spark.shown, false, "gone at the left end")
	-- the other looks, from the list
	click(Mp5.lookButton)
	click(Mp5.lookButton.menu.rows[4])
	eq(Mp5.db.look, "number", "a look picked from the list"); eq(Mp5.lookButton.label.text, "Look: Number", "named on the button")
	click(Mp5.test)
	eq(f.text.text, "5.0", "Test runs it once: the number"); eq(spark.shown, false, "and no spark")
	step(1)
	eq(f.text.text, "4.0", "counting down")
	Mp5.SetLook("clock")
	step(0.5)
	eq(f.text.text, "4", "the clock: whole seconds inside"); check(math.abs(f.part - 0.7) < 0.02, "and as much left of it")
	Mp5.ticks.seconds.checked = false
	click(Mp5.ticks.seconds)
	step(0.1)
	eq(f.text.text, "", "Show the seconds off: no number in the clock")
	Mp5.ticks.seconds.checked = true
	click(Mp5.ticks.seconds)
	step(6)
	-- placing it: unlocked it runs round and can be dragged and resized
	Mp5.SetLook("bar")
	eq(driver.shown, false, "locked and idle: nothing")
	Mp5.ticks.locked.checked = false
	click(Mp5.ticks.locked)
	eq(driver.shown, true, "unlocked: it is shown, to be placed"); eq(f.part, 1, "standing still and full, not counting"); eq(f.box.shown, true, "with a box to drag it by"); eq(f.grip.shown, true, "and a corner to size it by")
	f.scripts.OnDragStop(f)
	eq(Mp5.db.pos.bar[1], "CENTER", "where it was dragged is saved, per look"); eq(Mp5.db.pos.clock, nil, "another look keeps its own place")
	f.w, f.h = 200, 10
	f.grip.scripts.OnMouseUp(f.grip)
	eq(Mp5.db.size.bar[1], 200, "pulled by the corner: its new width is saved"); eq(Mp5.db.size.bar[2], 10, "and height"); eq(Mp5.sizeText.text, "200 x 10", "shown on the sub-tab")
	click(Mp5.bigger)
	eq(Mp5.db.size.bar[2], 11, "the + button makes the bar thicker")
	for _ = 1, 40 do click(Mp5.bigger) end
	eq(Mp5.db.size.bar[2], 30, "to a limit")
	Mp5.SetLook("spark")
	click(Mp5.bigger)
	eq(Mp5.db.size.spark, 3, "for the spark the size is how thick the line is"); eq(f.grip.shown, false, "and it has no corner: it lives on the mana bar")
	click(Mp5.reset)
	eq(Mp5.db.pos.bar, nil, "Reset: places forgotten"); eq(Mp5.db.size.spark, nil, "and sizes")
	Mp5.ticks.locked.checked = true
	click(Mp5.ticks.locked)
	eq(driver.shown, false, "locked again and idle: nothing runs"); eq(f.box.shown, false, "no box")
	-- only my own spells start it: a proc the game reports, with a mana cost on paper, does not
	A.env.IsPlayerSpell = function(id) return id == 133 end
	COST[777] = { { type = 0, cost = 10 } }
	cast(777)
	eq(driver.shown, false, "a spell that is not in my spellbook starts nothing")
	cast(133)
	eq(driver.shown, true, "one of mine does"); check(Mp5.last:find("(133)", 1, true), "and what started it is kept: " .. tostring(Mp5.last))
	A.env.IsPlayerSpell = nil
	step(6)
	-- a cost the game hides in combat still counts as a mana spell; a character without mana never runs
	A.env.issecretvalue = function(v) return v == "hidden" end
	COST[7] = { { type = 0, cost = "hidden" } }
	eq(Mp5.CostsMana(7), true, "a mana cost the game will not show still counts")
	A.env.issecretvalue = nil
	A.env.UnitClass = oldClass
	cast(133)
	eq(driver.shown, false, "a warrior has no mana: nothing ever runs")
	Mp5.Refresh()
	check(Mp5.note.text:find("has no mana", 1, true), "and the sub-tab says why")
	A.env.C_Spell, A.env._G.PlayerFrameManaBar = oldSpell, nil
	eq(A.DT.modules.mp5.hello, nil, "the module has nothing to say to the guild"); eq(A.env.SLASH_DAWNTOOLS_MP51, "/dtmp5", "its short command")
end

-- Combat: who killed me and who I killed, from the combat log
local Combat = A.DT.Combat
local ME_GUID = "Player-Alice"
local function log(event, sGUID, sName, dGUID, dName, ...)
	local extra = { ... }
	A.log = { 0, event, false, sGUID, sName, 0, 0, dGUID, dName, 0, 0, extra[1], extra[2], extra[3], extra[4], extra[5], extra[6], extra[7], extra[8], extra[9], extra[10] }
	A.fire("COMBAT_LOG_EVENT_UNFILTERED")
end
A.env.GetRealZoneText = function() return "Stranglethorn Vale" end
A.env.GetSubZoneText = function() return "Nesingwary's Expedition" end
A.env.C_Map = { GetBestMapForUnit = function() return 1434 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.3567, 0.1049 end } end }
log("SPELL_DAMAGE", "Player-Zed", "Zed", ME_GUID, "Alice", 133, "Fireball", 4, 300, 0, 4, 0, 0, 0, true) -- (a critical hit)
step(2)
log("SWING_DAMAGE", "Creature-0-1-2-3-99-0001", "Tiger", ME_GUID, "Alice", 40)
log("SWING_DAMAGE", "Pet-0-1-2-3-77-0001", "Fang", ME_GUID, "Alice", 25)
log("SPELL_DAMAGE", "Player-Zed", "Zed", "Player-Other", "Other", 133, "Fireball", 4, 999) -- not at me
log("SPELL_PERIODIC_DAMAGE", "Player-Zed", "Zed", ME_GUID, "Alice", 12, "Ignite", 4, 60)
log("UNIT_DIED", nil, nil, ME_GUID, "Alice")
A.fire("PLAYER_DEAD")
eq(#Combat.db.deaths, 1, "a death is recorded once, however it is told")
local death = Combat.db.deaths[1]
eq(death.killer, "Zed", "the last to hit me is the killer"); eq(death.player, true, "a player"); eq(death.with, "Ignite", "with what")
eq(death.amount, 60, "for how much"); eq(death.dmg, 360, "and all they did in those seconds")
eq(death.zone, "Stranglethorn Vale", "where"); eq(death.sub, "Nesingwary's Expedition", "exactly"); eq(death.x, 35.7, "on the map"); eq(death.level, 10, "at my level")
eq(#death.assists, 2, "the others who hit me helped"); eq(death.assists[1][1], "Tiger", "most damage first"); eq(death.assists[2][1], "Fang (pet)", "a pet is named as one")
check(not death.assists[1][3], "the tiger is no player")
-- the recap: every hit behind the death
eq(#death.hits, 4, "every hit I took is kept"); eq(death.hits[1][1], 2, "with how long before the death"); eq(death.hits[1][5], true, "and whether it was critical")
eq(death.hits[2][5], nil, "a plain swing is not")
-- where the combat log is closed to addons (WoW Forever): kills from PARTY_KILL, deaths from the game's recap
;(function()
	local kills, deaths, wasOpen = #Combat.db.kills, #Combat.db.deaths, Combat.open
	local oldGUID, oldName = A.env.UnitGUID, A.env.UnitName
	eq(wasOpen, true, "a client with an open combat log reads it")
	Combat.open = false
	A.env.UnitGUID = function(u) if u == "target" then return "Player-Enemy" end return oldGUID(u) end
	A.env.UnitName = function(u) if u == "target" then return "Gankalot" end return oldName and oldName(u) end
	A.fire("PLAYER_TARGET_CHANGED")
	A.fire("PARTY_KILL", ME_GUID, "Creature-0-1-2-3-55-0009")
	eq(#Combat.db.kills, kills, "a mob is no kill: this is for players")
	A.fire("PARTY_KILL", ME_GUID, "Player-Enemy")
	eq(#Combat.db.kills, kills + 1, "a killing blow of mine on a player is a kill, without the combat log")
	local k = Combat.db.kills[#Combat.db.kills]
	eq(k.name, "Gankalot", "named as I saw them"); eq(k.last, "Smith", "with their surname"); eq(k.guild, "Running Dawn", "with the guild I saw under the name"); eq(k.blow, true, "the blow was mine"); eq(k.player, true, "a player"); eq(k.zone, "Stranglethorn Vale", "where")
	A.fire("PARTY_KILL", ME_GUID, "Player-Enemy")
	A.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Gankalot dies, honorable kill Rank: Scout (12 Honor Points)")
	eq(#Combat.db.kills, kills + 1, "told three times: one kill")
	eq(k.class, "Warrior", "what was seen of them is kept: class"); eq(k.honor, 12, "the honour line adds its honour"); eq(k.rank, "Scout", "and their rank")
	check(Combat.About(k):find("Warrior, Scout, 12 honor", 1, true), "all of it in one line: " .. tostring(Combat.About(k)))
	check(Combat.Recap(k, false)[2].text:find("12 honor", 1, true), "shown in the kill's window")
	;(function() -- a name is in the colour of its class where that is known
		local was = RAID_CLASS_COLORS
		eq(Combat.Recap(k, false).title:find("|cffff4040Gankalot Smith|r", 1, true) ~= nil, true, "no class colours to be had: a player in red")
		RAID_CLASS_COLORS = { [k.cfile or "WARRIOR"] = { colorStr = "ffc79c6e" } }
		k.cfile = k.cfile or "WARRIOR"
		check(Combat.Recap(k, false).title:find("|cffc79c6eGankalot Smith|r", 1, true), "the class's colour: " .. Combat.Recap(k, false).title)
		RAID_CLASS_COLORS = was
	end)()
	A.fire("PARTY_KILL", "Player-Bob", "Player-Elsewhere")
	eq(#Combat.db.kills, kills + 1, "a group mate's kill of someone I was not on is not mine")
	step(6)
	A.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Sneakums dies, honorable kill Rank: Grunt (9 Honor Points)")
	eq(#Combat.db.kills, kills + 2, "the honour line tells of a kill I helped with")
	eq(Combat.db.kills[#Combat.db.kills].name, "Sneakums", "by name"); eq(Combat.db.kills[#Combat.db.kills].blow, nil, "not my blow")
	A.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 5 honor points.")
	eq(#Combat.db.kills, kills + 2, "other honour lines are not kills")
	table.remove(Combat.db.kills)
	local recapAt = 0 -- (each death's recap has its own times: one with the times of the last is that last one's)
	A.env.C_DeathRecap = { GetRecapEvents = function() return {
		{ timestamp = recapAt + 105, event = "SPELL_DAMAGE", sourceName = "Zed", spellName = "Pyroblast", spellId = 11366, amount = 500, overkill = 20 },
		{ timestamp = recapAt + 100, event = "SWING_DAMAGE", sourceName = "Tiger", amount = 40, overkill = -1 },
	} end }
	step(5)
	A.fire("PLAYER_DEAD")
	eq(#Combat.db.deaths, deaths, "a death no player I know of had a hand in is not kept")
	check(Combat.db.deathLog[#Combat.db.deathLog]:find("the death recap gave 2 events; struck by: Tiger, Zed; enemy players with me targeted: none; not kept", 1, true),
		"and what it was made of is noted: " .. Combat.db.deathLog[#Combat.db.deathLog])
	;(function() -- nobody known struck, but an enemy player had me targeted: the death is theirs, as a guess
		local e = A.env
		local was = { e.UnitExists, e.UnitIsPlayer, e.UnitCanAttack, e.UnitIsUnit, e.UnitGUID, e.UnitName }
		e.UnitExists = function(u) return u == "target" end
		e.UnitIsPlayer = function() return true end
		e.UnitCanAttack = function() return true end
		e.UnitIsUnit = function(a, b) return a == "targettarget" and b == "player" end
		e.UnitGUID = function(u) if u == "target" then return "Player-Gank" end return oldGUID(u) end
		e.UnitName = function(u) if u == "target" then return "Gank Stabber" end return oldName and oldName(u) end
		Combat.Watch()
		e.UnitExists, e.UnitIsPlayer, e.UnitCanAttack, e.UnitIsUnit, e.UnitGUID, e.UnitName = was[1], was[2], was[3], was[4], was[5], was[6]
		step(5)
		Combat.Watch = Combat.Watch -- (the recap is still that of the death before: it is asked again, then given up)
		local e2 = A.env
		local w = { e2.UnitExists, e2.UnitIsPlayer, e2.UnitCanAttack, e2.UnitIsUnit, e2.UnitGUID, e2.UnitName }
		A.fire("PLAYER_DEAD")
		eq(#Combat.db.deaths, deaths, "a recap that is still the last death's: the death waits for a new one")
		step(3)
		eq(#Combat.db.deaths, deaths + 1, "a death with an enemy player on me is kept, though nobody is known to have struck")
		check(Combat.db.deathLog[#Combat.db.deathLog]:find("still those of the death before (asked 4 times)", 1, true), "having asked the game four times: " .. Combat.db.deathLog[#Combat.db.deathLog])
		local g = Combat.db.deaths[#Combat.db.deaths]
		eq(g.killer, "Gank Stabber", "to whoever had me targeted"); eq(g.guess, true, "marked as a guess"); eq(g.player, true, "a player")
		check(Combat.Recap(g, true)[2].text:find("A guess", 1, true) or Combat.Recap(g, true)[3].text:find("A guess", 1, true), "and its window says so")
		check(Combat.db.deathLog[#Combat.db.deathLog]:find("enemy players with me targeted: Gank Stabber; kept, by who had me targeted", 1, true), "and the note")
		table.remove(Combat.db.deaths)
		local n = #A.printed
		A.slash("deathtest")
		check(#A.printed > n + 1 and A.printed[n + 1]:find("deathtest: the combat log is closed", 1, true), "/dt deathtest prints the notes")
	end)()
	A.env.UnitGUID = function(u) if u == "target" then return "Player-Zed" end return oldGUID(u) end
	A.env.UnitName = function(u) if u == "target" then return "Zed" end return oldName and oldName(u) end
	A.fire("PLAYER_TARGET_CHANGED")
	step(5)
	recapAt = 50
	A.fire("PLAYER_DEAD")
	eq(#Combat.db.deaths, deaths + 1, "a death by a player is recorded from the game's own recap")
	local d = Combat.db.deaths[#Combat.db.deaths]
	eq(d.killer, "Zed", "the last hit in it is the killer"); eq(d.with, "Pyroblast", "with what"); eq(d.amount, 500, "for how much")
	eq(d.assists[1] and d.assists[1][1], "Tiger", "the others in it helped"); eq(#d.hits, 2, "its hits are the recap"); eq(d.hits[1][3], "Melee", "a swing is melee")
	table.remove(Combat.db.deaths)
	;(function() -- a player I never saw: the hit's own GUID says it is one
		recapAt = 100
		local wasRecap = A.env.C_DeathRecap
		A.env.C_DeathRecap = { GetRecapEvents = function() return {
			{ timestamp = 300, event = "SWING_DAMAGE", sourceName = "Ghost Stalker", sourceGUID = "Player-9-ABCDEF", amount = 90 },
		} end }
		step(5)
		A.fire("PLAYER_DEAD")
		eq(#Combat.db.deaths, deaths + 1, "a death to a player never seen before is kept: the hit says who dealt it")
		local g = Combat.db.deaths[#Combat.db.deaths]
		eq(g.killer, "Ghost Stalker", "by name"); eq(g.player, true, "a player"); eq(g.guess, nil, "and no guess")
		table.remove(Combat.db.deaths)
		A.env.C_DeathRecap = wasRecap
	end)()
	table.remove(Combat.db.kills)
	A.env.UnitGUID, A.env.UnitName, A.env.C_DeathRecap, Combat.open = oldGUID, oldName, nil, wasOpen
	step(5)
end)()
-- (a recap's rows as text: "time ; who: what ; amount ; notes", colours taken out)
local function recapText(rec, isDeath)
	local out = {}
	for i, row in ipairs(Combat.Recap(rec, isDeath)) do
		out[i] = row.text or row.head or table.concat({ row.t, row.left, row.amount, row.note }, " ; ")
		check(row.left == nil or (type(row.icon) == "string" and row.icon ~= ""), "every table row has an icon")
	end
	return (table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local recapOf = recapText(death, true)
check(recapOf:find("425 damage taken in the last 10 seconds, from 3 attackers.", 1, true), "the recap totals the damage: " .. recapOf)
check(recapOf:find("1x ; Zed: Fireball ; 300 ; 71%, biggest 300, 1 critical", 1, true), "by ability, biggest first")
check(recapOf:find("-0.0 ; Zed: Ignite ; 60 ; killing blow", 1, true) and recapOf:find("-2.0 ; Zed: Fireball ; 300 ; critical", 1, true), "and hit by hit")
eq(Combat.Recap(death, true).title, "Killed by |cffff4040Zed|r", "headed by the killer"); eq(death.hits[1].i, 133, "the spell's number is kept for its icon")
check(recapText({ t = 0, zone = "Z", sub = "", killer = "Old", assists = {} }, true):find("from before the recap was kept", 1, true), "a death from before has none")
step(5)
log("ENVIRONMENTAL_DAMAGE", nil, nil, ME_GUID, "Alice", "Falling", 500)
log("UNIT_DIED", nil, nil, ME_GUID, "Alice")
eq(Combat.db.deaths[2].killer, "Falling", "a fall is its own killer"); eq(#Combat.db.deaths[2].assists, 0, "the earlier fight is not held against it")
do -- the recap also has heals, what was absorbed, resisted and blocked, overkill, attacks that did not land, debuffs, interrupts
	step(5)
	local TIGER = "Creature-0-1-2-3-99-0001"
	log("SPELL_AURA_APPLIED", "Player-Zed", "Zed", ME_GUID, "Alice", 118, "Polymorph", 64, "DEBUFF")
	log("SPELL_AURA_APPLIED", "Player-Bob", "Bob", ME_GUID, "Alice", 21562, "Fortitude", 2, "BUFF") -- (a buff is no part of it)
	log("SWING_MISSED", TIGER, "Tiger", ME_GUID, "Alice", "DODGE", false)
	log("SPELL_MISSED", "Player-Zed", "Zed", ME_GUID, "Alice", 133, "Fireball", 4, "ABSORB", false, 150)
	log("SPELL_HEAL", "Player-Bob", "Bob", ME_GUID, "Alice", 2061, "Flash Heal", 2, 250, 50, 0, true)
	log("SPELL_INTERRUPT", "Player-Zed", "Zed", ME_GUID, "Alice", 2139, "Counterspell", 64, 2061, "Flash Heal")
	log("SPELL_HEAL", ME_GUID, "Alice", "Player-Bob", "Bob", 2061, "Flash Heal", 2, 250, 0, 0, false)
	log("UNIT_DIED", nil, nil, "Player-Bob", "Bob") -- (a friend I healed is no kill of mine)
	log("SWING_DAMAGE", TIGER, "Tiger", ME_GUID, "Alice", 100, 40, 1, 20, 10, 30, false)
	log("UNIT_DIED", nil, nil, ME_GUID, "Alice")
	local rec = table.remove(Combat.db.deaths)
	eq(#Combat.db.kills, 0, "healing someone who then dies is no kill")
	eq(rec.killer, "Tiger", "only damage makes a killer: not the heal, not the spell that was absorbed"); eq(#rec.assists, 0, "nor a helper")
	eq(#rec.hits, 6, "all of it is kept, the buff aside")
	local all = recapText(rec, true)
	local function has(part, what) check(all:find(part, 1, true), what .. ": " .. all) end
	has("100 damage taken in the last 10 seconds, from 1 attacker.", "the damage is what landed")
	has("Healed for 200, and 50 more was overheal.", "heals, less the overheal")
	has("On top of that: 180 absorbed, 20 resisted, 10 blocked.", "what was soaked up")
	has("Not landed: 1 dodged.", "what I avoided")
	has("Tiger: Melee ; 100 ; 30 absorbed, 20 resisted, 10 blocked, overkill 40, killing blow", "the killing blow with its overkill")
	has("Bob: Flash Heal ; +200 ; critical, 50 overheal", "a heal")
	has("Zed: Polymorph ;  ; debuff put on me", "a debuff")
	has("Zed: Counterspell ;  ; interrupted my Flash Heal", "an interrupt")
	has("Zed: Fireball ; absorbed ; 150 damage", "a spell that was absorbed whole")
	has("Tiger: Melee ; dodged ; ", "a swing I dodged")
	has("Healing\n1x ; Bob: Flash Heal ; 200 ; 100%, biggest 200, 1 critical", "heals have their own totals")
	for _, row in ipairs(Combat.Recap(rec, true)) do
		if row.left and row.left:find("Bob", 1, true) then check(not row.left:find("ff4040", 1, true), "a healer is not in red") end
		if row.blow then eq(row.left, "|cffffffffTiger|r: Melee", "the killing blow is marked for its red line") end
	end
end
-- kills
log("SWING_DAMAGE", ME_GUID, "Alice", "Creature-0-1-2-3-55-0001", "Boar", 30)
log("PARTY_KILL", ME_GUID, "Alice", "Creature-0-1-2-3-55-0001", "Boar")
log("UNIT_DIED", nil, nil, "Creature-0-1-2-3-55-0001", "Boar")
log("SPELL_DAMAGE", ME_GUID, "Alice", "Player-Rex", "Rex", 116, "Frostbolt", 16, 200)
log("UNIT_DIED", nil, nil, "Player-Rex", "Rex")
log("UNIT_DIED", nil, nil, "Creature-0-1-2-3-56-0001", "Deer") -- nothing of mine
eq(#Combat.db.kills, 2, "what dies soon after I hit it is a kill of mine")
eq(Combat.db.kills[1].name, "Boar", "the boar"); eq(Combat.db.kills[1].blow, true, "by my own blow")
eq(Combat.db.kills[2].name, "Rex", "a player"); eq(Combat.db.kills[2].player, true, "marked as one"); eq(Combat.db.kills[2].blow, nil, "where I only helped")
eq(Combat.db.kills[2].with, "Frostbolt", "and what I last hit them with")
log("PARTY_KILL", ME_GUID, "Alice", "Player-Rex", "Rex")
eq(Combat.db.kills[2].blow, true, "a killing blow told after the death still counts")
check(recapText(Combat.db.kills[2]):find("200 damage from me in 1 hit, the killing blow among them.", 1, true), "a kill's recap is my own damage")
check(recapText(Combat.db.kills[2]):find("-0.0 ; Frostbolt ; 200 ; killing blow", 1, true), "hit by hit, without my name on every line")
log("SWING_DAMAGE", ME_GUID, "Alice", "Creature-0-1-2-3-57-0001", "Old Wolf", 5)
step(15)
log("UNIT_DIED", nil, nil, "Creature-0-1-2-3-57-0001", "Old Wolf")
eq(#Combat.db.kills, 2, "what dies long after is not mine")
-- the tab
A.slash("combat")
local function combatRows()
	local out = {}
	for _, w in ipairs(A.widgets) do
		if w.ccols and w.shown and w.data then out[#out + 1] = w.data end
	end
	return out
end
local function sideB(part)
	for _, w in ipairs(A.widgets) do
		if w.kind == "Button" and w.label and w.label.text and w.label.text:find(part, 1, true) then return w end
	end
end
click(sideB("Who killed me"))
Combat.search:SetText("")
Combat.Refresh()
check(sideB("Who killed me (2)") and sideB("Who did I kill (2)"), "both lists are offered as tabs, with their counts")
;(function() -- the third tab: everybody met, once each, with how often I killed them and they me
	local Combat = A.DT.Combat
	local kills, deaths = Combat.db.kills, Combat.db.deaths
	local now = os.time()
	kills[#kills + 1] = { t = now - 300, name = "Zed Foe", player = true, zone = "Ashenvale", sub = "", guild = "Bad Lot", blow = true }
	kills[#kills + 1] = { t = now - 200, name = "Zed Foe", player = true, zone = "Ashenvale", sub = "" }
	deaths[#deaths + 1] = { t = now - 100, killer = "Zed Foe", player = true, zone = "The Barrens", sub = "", assists = {} }
	local zed
	for _, p in ipairs(Combat.Players()) do if p.name == "Zed Foe" then zed = p end end
	eq(zed.kills, 2, "a player: how often I killed them"); eq(zed.deaths, 1, "and they me"); eq(zed.t, now - 100, "and when we last met")
	eq(zed.known.guild, "Bad Lot", "what was seen of them once is kept beside the last meeting")
	check(sideB("Players ("), "a third tab lists the players")
	click(sideB("Players ("))
	local row
	for _, w in ipairs(A.widgets) do
		if w.shown and w.data and w.data.player and w.data.player.name == "Zed Foe" then row = w end
	end
	check(row, "one row per player")
	check(row.data[1]:find("Zed Foe", 1, true) and row.data[1]:find("<Bad Lot>", 1, true), "with the guild"); eq(row.data[2], "|cff40ff402|r", "kills, green when ahead"); eq(row.data[3], "|cff40ff401|r", "deaths")
	check(row.data[5] == "The Barrens", "and where we last met")
	row.scripts.OnMouseUp(row)
	check(sideB("Who did I kill"), "a click goes to the fights"); eq(Combat.search:GetText(), "Zed Foe", "of that player")
	Combat.search:SetText("")
	table.remove(kills); table.remove(kills); table.remove(deaths)
	click(sideB("Who killed me"))
end)()
local shownDeaths = combatRows()
eq(#shownDeaths, 2, "my deaths are listed")
local zedRow
for _, d in ipairs(shownDeaths) do if d.rec == death then zedRow = d end end
eq(zedRow[2], "|cffff4040Zed|r", "a player in red"); eq(zedRow[3], "Ignite (60)", "what with"); eq(zedRow[4], "Nesingwary's Expedition, Stranglethorn Vale", "where")
eq(zedRow[5], "|cffffffffTiger|r 40, |cffffffffFang (pet)|r 25", "who helped")
check(text("2 deaths, 1 of them to players. Most often:"), "and a summary")
for _, w in ipairs(A.widgets) do
	if w.ccols and w.data == zedRow then
		A.env.GameTooltip.lines = {}
		w.scripts.OnEnter(w)
		local tip = table.concat(A.env.GameTooltip.lines, " | ")
		check(tip:find("(35.7, 10.5)", 1, true) and tip:find("Killed by Zed (a player), with Ignite for 60", 1, true) and tip:find("Helped: Tiger, 40 damage", 1, true), "the tooltip has the details: " .. tip)
	end
end
for _, w in ipairs(A.widgets) do
	if w.ccols and w.data == zedRow then w.scripts.OnMouseUp(w) end
end
check(text("Killed by |cffff4040Zed|r") and text("damage taken in the last 10 seconds") and text("|cffff4040Zed|r: Ignite"),"a click on a death opens its recap")
Combat.search:SetText("falling")
step(1)
eq(#combatRows(), 1, "the search box finds a death by its killer")
Combat.search:SetText("")
step(1)
click(sideB("Who did I kill"))
eq(#combatRows(), 2, "my kills"); check(text("2 kills, 1 of them of players."), "with their summary")
for _, w in ipairs(A.widgets) do
	if w.kind == "CheckButton" and w.scripts.OnClick and w.shown ~= false then
		for _, other in ipairs(A.widgets) do
			if other.kind == "FontString" and other.text == "Players only" then w.playersBox = true end
		end
	end
end
local onlyBox
for i, w in ipairs(A.widgets) do
	if w.kind == "FontString" and w.text == "Players only" then onlyBox = A.widgets[i - 1] end -- (its box was made just before its label)
end
onlyBox.checked = true
click(onlyBox)
eq(#combatRows(), 1, "players only"); eq(combatRows()[1].rec.name, "Rex", "leaves the boar out")
onlyBox.checked = false
click(onlyBox)
eq(A.DT.modules.combat.hello, nil, "the module has nothing to say to the guild")
-- the bar: Combat stands apart from the tabs before it
local tabX = {}
for _, w in ipairs(A.widgets) do
	if w.kind == "Button" and w.id and w.x and w.shown then tabX[w.id] = w.x end
end
eq(tabX.world - tabX.craft, 88, "tabs of one group stand side by side"); eq(tabX.combat - tabX.world, 102, "a new group stands apart"); eq(tabX.bis - tabX.combat, 88, "BiS beside it, in its group"); eq(tabX.tools - tabX.bis, 102, "and Tools behind a separator of its own")

-- places: Fish and Food are sub-tabs of Craft, NPC and Quests of World
do
	local UI = A.DT.UI
	local function place(id) for _, tab in ipairs(UI:TabList(true)) do if tab.id == id then return tab end end end
	local craft, world = place("craft"), place("world")
	check(craft and world and not place("fish") and not place("npc"), "Craft and World are on the bar; their sub-tabs are not")
	eq(craft.subs[1].id .. " " .. craft.subs[2].id, "fish food", "Craft holds Fish and Food"); eq(world.subs[1].id .. " " .. world.subs[2].id, "npc quest", "World holds NPC and Quests")
	A.slash("food")
	eq(A.DT.db.lastTab, "craft", "/dt food opens Craft"); eq(craft.current, "food", "on the Food sub-tab")
	eq(craft.buttons[1].text, "Fishing", "with a row of its sub-tabs"); eq(craft.buttons[2].text, "Cooking", "both")
	;(function() -- the professions: First Aid beside them, the rest behind a line
		local titles = {}
		for i, b in ipairs(craft.buttons) do titles[i] = b.text end
		eq(table.concat(titles, ", "), "Fishing, Cooking, First Aid, Mining, Campsite, Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring", "then First Aid, Mining and the Campsite, and the crafting professions, in order")
		eq(craft.buttons[3].row, 0, "First Aid stands with Fishing and Cooking, on the first row"); eq(craft.buttons[3].gap, 0, "with no line before it")
		eq(craft.buttons[4].row, 0, "Mining on the first row too"); eq(craft.buttons[4].gap, 1, "behind a line"); check(craft.lines[1].shown, "which is drawn")
		eq(craft.buttons[5].row, 0, "and the Campsite"); eq(craft.buttons[5].gap, 2, "behind another")
		eq(craft.buttons[6].row, 1, "the crafting professions begin a row of their own"); eq(craft.buttons[6].x, 2, "at its left edge"); eq(craft.buttons[11].row, 1, "Tailoring on it too")
		check(craft.buttons[7].x > craft.buttons[6].x, "each button after the last")
		local was = craft.panel.w
		craft.panel.w = 2000
		craft.panel.scripts.OnSizeChanged(craft.panel)
		eq(craft.buttons[6].row, 1, "however wide the window: still their own row"); eq(craft.buttons[11].row, 1, "and all of them on it"); eq(craft.buttons[5].row, 0, "the first row as it was")
		craft.panel.w = was
		craft.panel.scripts.OnSizeChanged(craft.panel)
	end)()
	click(craft.buttons[1])
	eq(craft.current, "fish", "a click on a sub-tab shows it"); eq(craft.panels.food.shown, false, "and hides the other"); eq(craft.panels.fish.shown, true, "its own panel")
	A.slash("market")
	A.slash("craft")
	eq(craft.current, "fish", "back at Craft: the sub-tab last used there"); eq(A.DT.db.tabs.sub.craft, "fish", "which is saved")
	A.env.SlashCmdList.DAWNTOOLS_QUEST()
	eq(A.DT.db.lastTab, "world", "a module's short command opens its place"); eq(world.current, "quest", "on its sub-tab")
	check(UI:HasTab("npc") and UI:HasTab("world") and not UI:HasTab("nothing"), "a sub-tab can be asked for by name like any tab")
end

-- Zones: levels and side worked out from the NPCs; what a zone has
do
	local Zed = NewClient("Zed")
	Zed.DT.db.settings.background = false
	local NPCS, QUESTS, ITEMDB = {}, {}, {}
	local function mob(id, level, zone, extra)
		NPCS[id] = { name = "Mob " .. id, minLevel = level, maxLevel = level, rank = 0, zoneID = zone, friendlyToFaction = "", npcFlags = 0, spawns = { [zone] = { { 50, 50 } } } }
		for k, v in pairs(extra or {}) do NPCS[id][k] = v end
	end
	for i, level in ipairs({ 3, 10, 11, 12, 13, 14, 15, 16, 17, 40 }) do mob(i, level, 17) end -- The Barrens: one stray low and one stray high
	mob(20, 30, 17, { name = "Innkeeper Wiley", friendlyToFaction = "H", npcFlags = 128 })
	mob(21, 30, 17, { name = "Devrak", friendlyToFaction = "H", npcFlags = 8 })
	mob(22, 30, 17, { name = "Wrahk", friendlyToFaction = "H", npcFlags = 4 })
	mob(23, 30, 17, { name = "Jahan", friendlyToFaction = "H", npcFlags = 4 + 16384 })
	mob(24, 30, 17, { name = "Captain Fairmount", friendlyToFaction = "A", npcFlags = 2 })
	mob(25, 24, 17, { name = "Old Greyfin", rank = 4 })
	mob(30, 55, 1519, { name = "Innkeeper Allison", friendlyToFaction = "A", npcFlags = 128 })
	mob(31, 55, 1519, { name = "Stormwind Vendor", friendlyToFaction = "A", npcFlags = 4 })
	for i, level in ipairs({ 30, 33, 35 }) do mob(40 + i, level, 33) end
	mob(45, 40, 33, { name = "Horde Trader", friendlyToFaction = "H", npcFlags = 4 })
	mob(46, 40, 33, { name = "Alliance Trader", friendlyToFaction = "A", npcFlags = 4 })
	for i, level in ipairs({ 17, 18, 20 }) do mob(50 + i, level, 718) end
	mob(54, 9999, 718, { name = "Boss Trigger" })                       -- (a "level" that is none)
	mob(55, 19, 718, { name = "Elite Guard", rank = 1, spawns = {} })   -- (an elite with no place on the map, as dungeon mobs are)
	mob(56, 19, 718, { name = "Deviate Faerie Dragon", rank = 4, spawns = { [718] = { { -1, -1 } } } }) -- (a rare inside: its "spot" is none)
	mob(57, 1, 17, { name = "Rabbit" })
	mob(58, 1, 17, { name = "Rat" })
	mob(60, 1, 9001, { name = "Lost Soul", spawns = {} })               -- (a place with one stray NPC and nothing else)
	for i = 1, 5 do QUESTS[10 + i] = { name = "Jungle Quest " .. i, requiredLevel = 30, questLevel = 30 + i * 2, zoneOrSort = 33 } end
	local ids = {}
	for id in pairs(NPCS) do ids[#ids + 1] = id end
	table.sort(ids)
	QUESTS[1] = { name = "Raptor Thieves", requiredLevel = 5, questLevel = 12, zoneOrSort = 17 }
	QUESTS[2] = { name = "Plainstrider Menace", requiredLevel = 5, questLevel = 11, zoneOrSort = 17 }
	QUESTS[3] = { name = "Too High Yet", requiredLevel = 30, questLevel = 30, zoneOrSort = 17 }
	ITEMDB[900] = { name = "Raptor Hide", npcDrops = { 2 } }
	ITEMDB[901] = { name = "Pearl", objectDrops = { 55 } }
	ITEMDB[902] = { name = "Elsewhere", npcDrops = { 41 } }
	local function entity(tbl, list)
		return {
			GetAllIds = function() return list end,
			GetAll = function(id, keys)
				local out = {}
				for i, key in ipairs(keys) do out[i] = tbl[id][key] end
				return out
			end,
			Get = function(id, key) return tbl[id] and tbl[id][key] end,
		}
	end
	Zed.env.LibQuestieDB = {
		RequireContract = function(v) return v == 4 end,
		Enum = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, INNKEEPER = 128, REPAIR = 16384 } },
		Npc = entity(NPCS, ids), Quest = entity(QUESTS, { 1, 2, 3, 11, 12, 13, 14, 15 }), Item = entity(ITEMDB, { 900, 901, 902 }),
		Object = { Get = function(id, key) return id == 55 and ({ name = "Giant Clam", zoneID = 17 })[key] or nil end },
	}
	local AREAS = { [17] = "The Barrens", [1519] = "Stormwind City", [33] = "Stranglethorn Vale", [718] = "Wailing Caverns", [9001] = "Nowhere Much" }
	Zed.env.C_Map = { GetAreaInfo = function(area) return AREAS[area] end, GetMapInfo = function(map) return map ~= 226 and { mapID = map } or nil end }
	Zed.env.QuestieLoader = { ImportModule = function() return {
		GetUiMapIdByAreaId = function(_, area) return ({ [17] = 1413, [33] = 1434, [718] = 226 })[area] end, -- (226: a map this game has not)
		IsDungeonZone = function(area) return area == 718 end, -- (as Questie has it: a plain function that takes the number alone)
		GetDungeons = function() return { [718] = { "Wailing Caverns", {}, 17, { { 17, 46.0, 36.3 } } } } end,
		GetDungeonLocation = function(_, area) return area == 718 and { { 17, 46.0, 36.3 } } or nil end,
		GetParentZoneId = function() return nil end,
	} end }
	local qdone = { [2] = true }
	Zed.env.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return qdone[id] or false end, IsOnQuest = function() return false end }
	local tom
	Zed.env.TomTom = { AddWaypoint = function(_, map, x, y, opts) tom = { map, x, y, opts.title } end }
	local gm = { gmdbs = { ["Herb Gathering"] = { [1413] = { [1] = 401, [2] = 401, [3] = 402 } }, Mining = {} },
		GetNameForNode = function(_, _, id) return ({ [401] = "Peacebloom", [402] = "Silverleaf" })[id] end }
	local stub = Zed.env.LibStub
	Zed.env.LibStub = setmetatable({}, { __call = function(_, name, silent)
		if name == "AceAddon-3.0" then return { GetAddon = function() return gm end } end
		return stub(name, silent)
	end })
	Zed.env.DawnMarket.API.Each = function(fn) fn(900, 5000, 1, 0) fn(901, 20000, 1, 0) fn(902, 99999, 1, 0) end
	local Zone = Zed.DT.Zone
	Zed.DT.Npc.BATCH, Zed.DT.Quest.BATCH, Zed.DT.Item.BATCH = 10, 10, 10
	local function ztext(part)
		for _, w in ipairs(Zed.widgets) do
			if w.kind == "FontString" and w.shown ~= false and type(w.text) == "string" and w.text:find(part, 1, true) then return w.text end
		end
	end
	Zed.slash("zone")
	check(ztext("Reading NPCs and quests"), "the Zones tab reads the NPCs and quests it is worked out from")
	step(2)
	check(ztext("3 of 4 zones"), "then lists the zones, dungeons left out to begin with")
	local barrens, sw, stv, wc = Zone.Get("The Barrens"), Zone.Get("Stormwind City"), Zone.Get("Stranglethorn Vale"), Zone.Get("Wailing Caverns")
	eq(barrens.lo, 10, "levels from the zone's ordinary mobs, the stray low one and the level-1 critters left out"); eq(barrens.hi, 17, "and the stray high one")
	eq(barrens.by, "mobs", "from its mobs, having few quests"); eq(stv.by, "quests", "a zone with quests enough: from the levels of its quests")
	eq(Zone.Get("Nowhere Much").junk, true, "a place with one stray NPC and no quest is not listed")
	eq(Zone.Levels(barrens), "10-17", "shown plainly (that they are estimates is said once, on the right)"); eq(barrens.side, "Horde", "four Horde service NPCs to one Alliance quest giver: Horde's")
	eq(sw.side, "Alliance", "only Alliance's people: Alliance's"); eq(Zone.Levels(sw), "", "no mobs: no levels")
	eq(stv.side, "Contested", "both sides' people, about even: contested"); eq(Zone.Levels(stv), "32-40", "its levels, by its quests")
	eq(wc.dungeon, true, "a dungeon is known as one"); eq(wc.hi, 20, "a 9999 that is no level does not stretch its levels"); eq(#wc.levels, 4, "and its elites count, placed or not"); eq(#barrens.rares, 1, "the zone's rares"); eq(barrens.services.Vendor, 2, "and its services, counted")
	local function zrows()
		local out = {}
		for _, w in ipairs(Zed.widgets) do
			if w.zcols and w.shown and w.data then out[#out + 1] = w end
		end
		return out
	end
	local function znames()
		local out = {}
		for i, w in ipairs(zrows()) do out[i] = w.data.z.name end
		return table.concat(out, ", ")
	end
	eq(znames(), "The Barrens, Stranglethorn Vale, Stormwind City", "lowest levels first, those without levels last")
	eq(zrows()[1].zcols[2].text, "|cffffff0010-17|r", "the levels coloured for my own level (10: about right)"); eq(zrows()[1].zcols[3].text, "|cffff5050Horde|r", "and whose it is")
	eq(zrows()[2].zcols[2].text, "|cffff404032-40|r", "far above me: red")
	Zone.dungeonBox.checked = true
	click(Zone.dungeonBox)
	eq(#zrows(), 4, "Show dungeons: the dungeon is listed"); check(ztext("Dungeon|r"), "marked as one")
	eq(znames(), "The Barrens, Wailing Caverns, Stranglethorn Vale, Stormwind City", "under the zone its door is in")
	eq(zrows()[2].zcols[1].text, "    |cff666666> |r|cffc080ffWailing Caverns|r", "indented beneath it"); eq(wc.parent, barrens, "its zone known")
	-- the side
	click(Zone.sideButton)
	click(Zone.sideButton.menu.rows[2])
	eq(Zone.db.side, "Horde", "a side picked from the list"); eq(znames(), "The Barrens, Wailing Caverns", "Horde's zones, with the dungeons in them")
	eq(Zone.sideButton.label.text, "Horde", "named on the button")
	click(Zone.sideButton)
	click(Zone.sideButton.menu.rows[4])
	eq(znames(), "Stranglethorn Vale", "the contested ones: a dungeon whose zone is filtered out is not shown")
	click(Zone.sideButton)
	click(Zone.sideButton.menu.rows[1])
	eq(#zrows(), 4, "any side again")
	Zone.search:SetText("wailing")
	step(1)
	eq(znames(), "Wailing Caverns", "a dungeon found on its own stands at the edge"); eq(zrows()[1].zcols[1].text, "|cffc080ffWailing Caverns|r", "not indented under a zone that is not listed")
	Zone.search:SetText("")
	step(1)
	Zone.mineBox.checked = true
	click(Zone.mineBox)
	eq(znames(), "The Barrens, Wailing Caverns", "For my level: only zones about my level, each with its dungeons")
	Zone.mineBox.checked = false
	click(Zone.mineBox)
	Zone.search:SetText("strangle")
	step(1)
	eq(znames(), "Stranglethorn Vale", "the search box finds a zone")
	Zone.search:SetText("")
	step(1)
	-- the zone picked
	local function zrow(name) for _, w in ipairs(zrows()) do if w.data.z.name == name then return w end end end
	click(zrow("The Barrens"))
	eq(Zone.right.title.text, "The Barrens", "a click shows the zone on the right"); check(Zone.right.sub.text:find("Levels 10-17", 1, true), "with its levels")
	local opened
	Zed.env.OpenWorldMap = function(map) opened = map end
	eq(Zone.right.map.shown, true, "a Map button stands top right of the zone")
	click(Zone.right.map)
	eq(opened, 1413, "it opens the game's map on that zone")
	opened = nil
	Zed.combat = true
	click(Zone.right.map)
	eq(opened, nil, "not in combat (the game forbids it)"); check(Zed.printed[#Zed.printed]:find("in combat", 1, true), "it says so")
	Zed.combat = false
	eq(Zone.MapOf(wc), 1413, "a dungeon without a map of its own: the map of the zone its door is in")
	click(zrow("Stormwind City"))
	eq(Zone.right.map.shown, false, "no button where no map is known")
	click(zrow("The Barrens"))
	local function zlines()
		local out = {}
		for i, d in ipairs(Zone.Lines(barrens)) do out[i] = (d.head and ("# " .. d.head) or d.text) end
		return (table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	local function zline(part)
		for _, d in ipairs(Zone.Lines(barrens)) do
			if (d.head or d.text):find(part, 1, true) then return d end
		end
	end
	local text = zlines()
	check(text:find("# Quests\n1 open to you, 1 not yet, 1 done, 3 in all", 1, true), "its quests, by where they stand for me: " .. text)
	check(text:find("# Dungeons\nWailing Caverns  17-20", 1, true), "the dungeon whose door is here, with its levels")
	check(text:find("# Rare mobs (1)\nOld Greyfin  level 24", 1, true), "its rares")
	check(text:find("3 in all  (show them)\n\n# Dungeons", 1, true), "the blocks set apart by a line of air")
	check(text:find("Flight master  1", 1, true) and text:find("Innkeeper  1", 1, true) and text:find("Vendor  2", 1, true) and text:find("Repairs  1", 1, true), "its services")
	check(text:find("# Fish  fishing skill 75", 1, true), "what bites, from the Fish tab")
	check(text:find("Herbs: Peacebloom 2, Silverleaf 1", 1, true), "its herbs, counted from GatherMate2's store, commonest first")
	check(text:find("Ore: none recorded", 1, true), "and a word where there are none")
	check(text:find("Leather: Light Leather, Medium Leather  (by the level of its mobs)", 1, true), "leather by the level of its mobs")
	check(text:find("Working it out", 1, true), "the dearest drops take a moment")
	step(1)
	text = zlines()
	check(text:find("Pearl  2g 0s 0c  Giant Clam\nRaptor Hide  50s 0c  Mob 2", 1, true), "then they are listed, dearest first, with what drops them: " .. text)
	check(not text:find("Elsewhere", 1, true), "what drops in another zone is not among them")
	eq(zline("Pearl").item, 901, "a drop's line knows its item")
	Zone.Refresh()
	Zone.right.scripts.OnMouseWheel(Zone.right, -10) -- (the drops are at the foot of the panel: scrolled to)
	local pearlRow
	for _, row in ipairs(Zone.right.rows) do if row.shown and row.data and row.data.item == 901 then pearlRow = row end end
	Zed.env.GameTooltip.lines = {}
	pearlRow.scripts.OnEnter(pearlRow)
	eq(Zed.env.GameTooltip.lines[1], "item:901", "hovering it shows the item's own tooltip")
	-- the clicks
	zline("show them").click()
	eq(Zed.DT.Quest.db.zone, "The Barrens", "a click on the quests: the Quests tab on this zone"); eq(Zed.DT.db.lastTab, "world", "opened")
	Zed.slash("zone")
	zline("Vendor").click()
	eq(Zed.DT.Npc.db.zone, "The Barrens", "a click on a service: the NPC tab on this zone"); eq(Zed.DT.Npc.db.types.Vendor, true, "and that kind")
	Zed.slash("zone")
	zline("Wailing Caverns").click()
	eq(tom[1], 1413, "a click on a dungeon: a waypoint to its door"); eq(tom[4], "Wailing Caverns", "named"); eq(tom[2], 0.46, "at the door")
	zline("Old Greyfin").click()
	eq(tom[4], "Old Greyfin", "a click on a rare: a waypoint to it")
	gm.gmdbs = nil
	check(zlines():find("Herbs and ore: needs the GatherMate2 addon", 1, true), "without GatherMate2 the block says what it needs, once")
	-- a mob inside a dungeon has no spot of its own, and the dungeon no map here: the waypoint goes to its door
	local dragon
	for _, r in ipairs(Zed.DT.Npc.Find("deviate", {})) do dragon = r.e end
	tom = nil
	Zed.DT.Npc.Waypoint(dragon)
	eq(tom[1], 1413, "a mob inside a dungeon: the waypoint goes to the dungeon's door, on the map outside"); eq(tom[2], 0.46, "at the door")
	check(Zed.printed[#Zed.printed]:find("the door of the dungeon it is in", 1, true), "and chat says that is what it is")
	;(function() -- QuestieDB without Questie: the map of a zone comes from QuestieDB's own table
		local loader = Zed.env.QuestieLoader
		Zed.env.QuestieLoader = nil
		Zed.env.loadstring = _G.load -- (the game has loadstring; "load" alone is a helper of this file)
		Zed.env.LibQuestieDB.Support = { Get = function(name) return name == "ZoneDB" and { private = { areaIdToUiMapId = "return { [4242] = 1453 }" } } or nil end }
		Zed.env.C_Map.GetMapInfo = function(map) return { mapID = map } end
		eq(Zed.DT.Npc.MapOf(4242), 1453, "without Questie, QuestieDB's own table gives a zone's map")
		Zed.env.QuestieLoader = loader
	end)()
	eq(Zed.DT.Npc.MapOf(718), nil, "a map this game does not have is no map")
	eq(Zed.DT.db.zone.last, "The Barrens", "the zone last looked at is remembered"); eq(Zed.DT.modules.zone.hello, nil, "the module has nothing to say to the guild")
	leave(Zed)
end

-- Settings in sections, and profiles
do
	local Pia = NewClient("Pia")
	local UI, P, db = Pia.DT.UI, Pia.DT.Profiles, Pia.DT.db
	local reloads = 0
	Pia.env.ReloadUI = function() reloads = reloads + 1 end
	Pia.env.GetRealmName = function() return "Forever" end
	-- sections
	Pia.slash("settings")
	local titles = {}
	for i, b in ipairs(UI.sectionButtons) do titles[i] = (b.label.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	eq(table.concat(titles, " / "), "General / Profiles / Tabs & Modules / Built-ins / Market / BiS / Data Sync", "the Settings tab lists its sections: the fixed ones, then one per module with switches, Data Sync at the bottom")
	eq(db.settingsSection, "general", "General to begin with"); eq(UI.sectionPanels.general.shown, true, "its panel shown"); eq(UI.sectionPanels.profiles.shown, false, "the others not")
	click(UI.sectionButtons[2])
	eq(db.settingsSection, "profiles", "a click shows a section"); eq(UI.sectionPanels.profiles.shown, true, "its panel"); eq(UI.sectionPanels.general.shown, false, "the last one hidden")
	Pia.slash("market")
	Pia.slash("settings")
	eq(db.settingsSection, "profiles", "the section last looked at is remembered")
	-- profiles: what is set up, never what was collected
	eq(P.Current(), "Default", "every character is on Default to begin with"); eq(table.concat(P.List(), ","), "Default", "the only profile")
	local range, market = db.range, db.market
	range.settings.on, range.size, range.mark = true, 22, 30
	db.tabs.hidden.combat = true
	market.favs[100] = true
	eq(P.New("Raid"), "Raid", "a new profile: a copy of how things are now"); eq(select(2, P.New("raid")), "There is a profile \"raid\" already.", "names are taken once, whatever the case")
	eq(P.New(""), nil, "a profile needs a name"); eq(P.New(("x"):rep(40)), nil, "not too long a one")
	eq(P.New("Bare", true), "Bare", "another, with everything at its default")
	eq(table.concat(P.List(), ","), "Default,Bare,Raid", "listed, Default first")
	eq(reloads, 0, "making profiles switches nothing")
	-- switch: the live values go to their profile, the other's come in, the interface reloads
	range.size = 12 -- (changed after Raid was copied: belongs to Default)
	P.Use("Raid")
	eq(reloads, 1, "using another profile reloads the interface"); eq(db.profile, "Raid", "it is the one held now"); eq(db.profileOf["Pia-Forever"], "Raid", "and this character's")
	eq(db.range.size, 22, "its values are in the live tables"); eq(db.range.settings.on, true, "settings too"); eq(db.tabs.hidden.combat, true, "and the tabs")
	eq(db.profiles.Default.mods.range.keys.size, 12, "what was live is kept under its own profile")
	eq(db.market.favs[100], true, "favourites and the like are not part of any profile"); check(db.market.houses, "nor is what was collected touched")
	P.Use("Bare")
	eq(db.range.size, nil, "an empty profile: nothing set (the modules fill in their defaults on load)"); eq(next(db.range.settings), nil, "no settings either")
	eq(db.tabs, nil, "nor tabs: the core sets them up anew"); eq(db.market.favs[100], true, "and still nothing collected is lost")
	P.Use("Default")
	eq(db.range.size, 12, "back on Default: as it was left"); eq(db.profileOf["Pia-Forever"], nil, "Default needs no entry")
	-- rename and delete
	eq(P.Rename("Default", "Main"), nil, "Default keeps its name"); eq(P.Rename("Raid", "Bare"), nil, "no renaming onto another")
	db.profileOf["Alt-Forever"] = "Raid"
	eq(P.Rename("Raid", "Raiding"), "Raiding", "a profile renamed"); eq(db.profileOf["Alt-Forever"], "Raiding", "characters on it follow")
	eq(P.Delete("Default"), nil, "Default cannot be deleted")
	P.Use("Raiding")
	eq(P.Delete("Raiding"), nil, "nor the one in use")
	P.Use("Default")
	eq(P.Delete("Raiding"), true, "another can"); eq(db.profileOf["Alt-Forever"], nil, "its characters are on Default again"); eq(db.profiles.Raiding, nil, "gone")
	-- export and import
	range.size, range.pos = 18, { target = { "CENTER", "CENTER", 10.5, -20 } }
	local text = P.Export("Default")
	check(type(text) == "string" and text:sub(1, 4) == "DT1:", "a profile exports as text")
	local name = P.Import(text)
	eq(name, "Imported", "and imports under a name of its own"); eq(P.Current(), "Default", "without being switched to")
	local got = db.profiles.Imported
	eq(got.mods.range.keys.size, 18, "with its values"); eq(got.mods.range.keys.pos.target[3], 10.5, "nested ones and fractions too"); eq(got.mods.range.settings.on, true, "and settings")
	eq(got.top.tabs.hidden.combat, true, "and the tabs")
	eq(P.Import(text), "Imported 2", "a second import gets the next name")
	eq(P.Import("hello"), nil, "something that is no profile is refused"); eq(select(2, P.Import("hello")):find("not a DawnTools profile") ~= nil, true, "with a word why")
	eq(P.Import("DT1:zz"), nil, "a damaged text is refused"); eq(P.Import("DT1:" .. ("ab"):rep(150000)), nil, "and one far too long")
	-- only what a profile may hold is taken in, and nothing in it is run
	local LD = Pia.env.LibStub("LibDeflate")
	local function pack(plain) return "DT1:" .. LD:EncodeForPrint(LD:CompressDeflate(plain)) end
	local evil = pack("{s1:vn1;s3:top{s8:settings{s10:backgroundF}s6:houses{n1;n2;}}s4:mods{s5:range{s8:settings{}s4:keys{s4:sizen9;s5:chars{}}}s7:nothing{}}}")
	local stored, whyNot = P.Import(evil, "Odd")
	if not stored then print("import: " .. tostring(whyNot)) end
	eq(stored, "Odd", "a hand-made text of the right shape is read")
	eq(db.profiles.Odd.top.settings.background, false, "what belongs in a profile is taken"); eq(db.profiles.Odd.top.houses, nil, "a key that does not is dropped")
	eq(db.profiles.Odd.mods.range.keys.size, 9, "a module's own keys are taken"); eq(db.profiles.Odd.mods.range.keys.chars, nil, "others not"); eq(db.profiles.Odd.mods.nothing, nil, "nor modules there are not")
	eq(P.Import(pack("{s1:vn1;s3:top{}s4:mods"), "Cut"), nil, "a text cut short is refused")
	eq(P.Import(pack(("{s1:a"):rep(20) .. ("}"):rep(20)), "Deep"), nil, "and one nested without end")
	eq(P.Import(pack("{s1:vn2;s3:top{}s4:mods{}}"), "Later"), nil, "and one of a version not known")
	-- what is of the wrong kind is left out (a number where a table belongs would break the next login), and
	-- nobody else's text answers for me on sharing
	local wrong = P.Import(pack("{s1:vn1;s3:top{s8:settingsn5;s4:tabss3:abcs3:posn1;s7:lastTab{}}s4:mods{s5:range{s8:settings{s2:onTs4:sizen3;}s4:keys{s3:posn7;s4:sizes3:big}}s6:market{s8:settings{s5:shareTs7:tooltipF}s4:keys{}}}}"), "Wrong")
	eq(wrong, "Wrong", "a text with values of the wrong kind is still read")
	local w = db.profiles.Wrong
	eq(w.top.settings, nil, "but a number where the settings belong is left out"); eq(w.top.tabs, nil, "a text where the tabs belong"); eq(w.top.pos, nil, "a number for a place"); eq(w.top.lastTab, nil, "a table for a name")
	eq(w.mods.range.settings.on, true, "a module's switches are taken"); eq(w.mods.range.settings.size, nil, "what is no switch is not")
	eq(w.mods.range.keys.pos, nil, "a module's own key of the wrong kind is left out"); eq(w.mods.range.keys.size, nil, "likewise")
	eq(w.mods.market.settings.share, nil, "sharing with the guild is never switched on by somebody's text"); eq(w.mods.market.settings.tooltip, false, "other switches are")
	eq(P.Import(pack("{s1:vn1;s3:top{s8:settings{s5:shareTs5:coinsF}}s4:mods{}}"), "Sharer"), "Sharer", "a text whose own settings say to share is read")
	eq(db.profiles.Sharer.top.settings.share, nil, "but the one switch of sharing is not taken from it"); eq(db.profiles.Sharer.top.settings.coins, false, "its other settings are")
	-- the section itself
	UI:ShowSection("profiles")
	local shown = {}
	for _, row in ipairs(P.rows) do if row.shown then shown[#shown + 1] = (row.label.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end end
	eq(table.concat(shown, ","), "> Default,   Bare,   Imported,   Imported 2,   Odd,   Sharer,   Wrong", "the section lists the profiles, the one in use marked")
	eq(P.rows[1].use.enabled, false, "the one in use cannot be 'used'"); eq(P.rows[1].delete.enabled, false, "nor Default deleted"); eq(P.rows[2].delete.enabled, true, "another can")
	click(P.rows[2].use)
	eq(Pia.popups[#Pia.popups], "DAWNTOOLS_PROFILE_USE", "Use asks first, as the interface reloads")
	click(P.rows[2].export)
	eq(Pia.popups[#Pia.popups], "DAWNTOOLS_COPY", "Export shows the text to copy")
	click(P.newCopy)
	eq(Pia.popups[#Pia.popups], "DAWNTOOLS_PROFILE_TEXT", "New asks for a name")
	Pia.env.StaticPopupDialogs.DAWNTOOLS_PROFILE_TEXT.OnAccept({ editBox = { GetText = function() return "Third" end } })
	check(db.profiles.Third, "and makes the profile"); check(P.message.text:find("Third", 1, true), "saying so")
	click(P.newCopy)
	Pia.env.StaticPopupDialogs.DAWNTOOLS_PROFILE_TEXT.OnAccept({ editBox = { GetText = function() return "third" end } })
	check(P.message.text:find("already", 1, true), "or why not")
	leave(Pia)
	-- another character, on another profile, gets its own values at login
	local saved = Pia.env.DawnToolsDB
	saved.profileOf["Quin-Forever"] = "Odd"
	local Quin = NewClient("Quin", { db = saved, globals = function(env) env.GetRealmName = function() return "Forever" end end })
	eq(Quin.DT.db.profile, "Odd", "a character with a profile of its own: its values are brought in at login")
	eq(Quin.DT.db.range.size, 9, "before the modules start"); eq(Quin.DT.db.settings.background, false, "the core's settings too")
	eq(Quin.DT.db.profiles.Default.mods.range.keys.size, 18, "the other character's are stored away under its profile")
	eq(Quin.DT.db.range.settings.on, false, "what the profile does not say is at its default"); eq(Quin.DT.db.market.favs[100], true, "and what was collected is everybody's")
	leave(Quin)
end

;(function() -- BiS: the tab right of Combat, the tooltip line, the roll line
	local GEAR = { -- name, where worn, the game's stats, a tooltip line
		[9001] = { "Old Helm", "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 10 } },
		[9002] = { "Warding Helm", "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 5 }, "Equip: Increased Defense +10." },
		[9003] = { "Helm of the List", "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 40 }, "Equip: Increased Defense +10." },
		[9004] = { "Band of Aim", "INVTYPE_FINGER", {}, "Equip: Improves your chance to hit by 1%." },
		[9005] = { "Listed Legs", "INVTYPE_LEGS", { ITEM_MOD_STAMINA_SHORT = 12 } },
		[9006] = { "Mage Hat", "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 99 }, "Classes: Mage" },
		[9007] = { "Worn Legs", "INVTYPE_LEGS", { ITEM_MOD_STAMINA_SHORT = 20 } },
		[9010] = { "Quest Helm", "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 25 } },
		[9011] = { "Crafted Helm", "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 18 } },
		[9012] = { "World Helm", "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 22 }, "Binds when equipped" },
		[9013] = { "Bound Helm", "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 50 } },
		[9014] = { "Dungeon Helm", "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 28 } },
	}
	for id, g in pairs(GEAR) do ITEMS[id] = { g[1], 2, 1, 100, false, 4, 0, slot = g[2] } end
	local worn = { [1] = 9001, [7] = 9007 }
	local X = NewClient("Bis", { globals = function(env)
		env.GetInventoryItemID = function(_, slot) return worn[slot] end
		env.GetItemStats = function(link)
			local g = GEAR[tonumber(link:match("item:(%d+)"))]
			return g and g[3] or {}
		end
		env.C_TooltipInfo = { GetItemByID = function(id)
			local g = GEAR[id]
			return { lines = { { leftText = ITEMS[id][1] }, g and g[4] and { leftText = g[4] } or nil } }
		end }
		-- the sheet: 60 defense without gear (level 10 gives 50), 2% hit from talents
		env.UnitDefense = function()
			local def = 60
			for _, id in pairs(worn) do if GEAR[id][4] and GEAR[id][4]:find("Defense") then def = def + 10 end end
			return 50, def - 50 -- (the skill, and what is added to it: level 10 gives 50)
		end
		env.GetHitModifier = function() return 2 end
		env.GetLootRollItemLink = function(roll) return roll == 1 and "|cff1eff00|Hitem:9003::::|h[Helm of the List]|h|r" or "|Hitem:100::::|h[Copper Bar]|h" end
	end })
	local B, e = X.DT.Bis, X.env
	local order = {}
	for i, tb in ipairs(X.DT.UI:TabList(true)) do order[tb.id] = i end
	eq(order.bis, order.combat + 1, "the BiS tab is right of Combat")
	eq(#X.DT.BisProfiles, 40, "a profile for every spec"); eq(#B.Mine(), 3, "three of them a warrior's")
	for _, p in ipairs(X.DT.BisProfiles) do
		check(#p.src > 0 and p.src[1]:find("^https://"), p.id .. " says where its values are from")
		for word in pairs(p.w) do check(B.LABEL[word], p.id .. ": a stat we have a word for (" .. word .. ")") end
		for word, cap in pairs(p.caps) do check(p.w[word] and cap.cap > 0, p.id .. ": a cap on a weighted stat") end
	end
	B.db.pick[B.me] = "warrior-protection"
	eq(B.Profile().caps.def.cap, 440 - 50 * 5, "below the last level the defense cap is lower, five a level"); eq(B.Profile().caps.def.hard, nil, "and not to be reached before all else")
	B.MAX_LEVEL = 10 -- (from here: a character of the last level)
	X.fire("PLAYER_LEVEL_UP")
	local prot = B.Profile()
	eq(prot.id, "warrior-protection", "the spec picked"); eq(prot.caps.def.cap, 440, "defense 440"); eq(prot.caps.def.hard, true, "before anything else")
	eq(prot.caps.hit.cap, 8, "hit 8%"); eq(prot.caps.exp.cap, 6.5, "expertise 6.5%")
	X.DT.BisLists["warrior-protection"] = { [9003] = "quest", [9005] = "crafted", [9006] = "quest" }
	X.bags = { 9002, 9004, 100 }
	X.fire("BAG_UPDATE_DELAYED")
	B.Edit("def", "cap", 70) -- (a cap within reach of level 10)
	eq(B.Profile().caps.def.cap, 70, "a cap changed by hand"); eq(B.Profile().caps.def.hard, true, "stays what it was otherwise")
	eq(B.Compute(), true, "worked out")
	local s = B.State()
	eq(s.cur[1], 9001, "what I wear"); eq(s.base.def, 60, "defense without gear: the sheet less the gear"); eq(s.base.hit, 2, "hit from talents")
	eq(s.curShort.def, 10, "ten short of the cap as I stand")
	eq(s.best.rows[1], 9002, "the best I own gives up stamina for the cap"); eq(s.best.short.def, nil, "which it reaches")
	eq(s.best.rows[11], 9004, "a ring from the bags is put on"); eq(s.best.rows[9], 9007, "what is best already stays")
	eq(s.bis.rows[1], 9003, "the best of the list"); eq(s.bis.rows[9], 9005, "slot by slot")
	-- what an item would gain
	local g = B.Gain(9003)
	eq(g.d, 35, "the listed helm: 35 stamina more than the best I own"); eq(table.concat(g.slots, ","), "Head", "and the slot it changes")
	eq(B.Gain(9002).best, true, "an item of my best set says so"); eq(B.Gain(9001).best, false, "one that is not, too")
	eq(B.Gain(9006).no, true, "another class's is not for me"); eq(B.Gain(100), nil, "what is not gear has nothing to say")
	local tip = e.GameTooltip
	tip.lines = {}
	X.tooltipHook(tip, { id = 9003 })
	local line
	for _, l in ipairs(tip.lines) do if l:find("BiS", 1, true) then line = l end end
	check(line and line:find("+35.0", 1, true) and line:find("Head", 1, true) and line:find("Protection", 1, true), "the tooltip says the gain and the slot: " .. tostring(line))
	tip.lines = {}
	X.tooltipHook(tip, { id = 100 })
	for _, l in ipairs(tip.lines) do check(not l:find("BiS", 1, true), "nothing on what is not gear") end
	B.db.settings.tooltip = false
	tip.lines = {}
	X.tooltipHook(tip, { id = 9003 })
	for _, l in ipairs(tip.lines) do check(not l:find("BiS", 1, true), "nor with the line switched off") end
	B.db.settings.tooltip = true
	-- the list's items I do not own, in order
	step(1)
	s = B.State()
	eq(#s.upg, 1, "the legs on the list are worse than mine: one upgrade"); eq(s.upg[1].id, 9003, "the helm"); eq(s.rank[9003], 1, "numbered")
	tip.lines = {}
	X.tooltipHook(tip, { id = 9003 })
	check(tip.lines[#tip.lines]:find("#1 upgrade", 1, true), "and the tooltip says which upgrade it is")
	-- rolled for
	local before = #X.printed
	X.fire("START_LOOT_ROLL", 1)
	check(#X.printed == before + 1 and X.printed[#X.printed]:find("+35.0", 1, true), "a roll: a line in the chat")
	X.fire("START_LOOT_ROLL", 2)
	eq(#X.printed, before + 1, "none for what is not gear")
	-- what there is to get: the item list (QuestieDB's as the Items tab reads it; here a stand-in), then the game's facts
	local Item = X.DT.Item
	Item.Start, Item.Ready = function() return false end, function() return true end
	Item.All = function() return {
		{ id = 9010, req = 1, c = 4, s = 0, src = { ["Quest reward"] = true } },
		{ id = 9011, req = 1, c = 4, s = 0, src = { Crafted = true } },
		{ id = 9012, req = 1, c = 4, s = 0, src = { Drop = true } },
		{ id = 9013, req = 1, c = 4, s = 0, src = { Drop = true } },
		{ id = 9014, req = 1, c = 4, s = 0, src = { Drop = true } },
		{ id = 9015, req = 40, c = 4, s = 0, src = { ["Quest reward"] = true } },
	} end
	X.DT.CraftSkill = {}
	local hall = X.DT.Dungeon.All()[1]
	hall.lo = 5
	hall.bosses[1].has[9014] = true
	B.Sift()
	local kinds = {}
	for _, c in ipairs(B.finder.got) do kinds[#kinds + 1] = c.id .. c.kind end
	table.sort(kinds)
	eq(table.concat(kinds, ","), "9010quest,9011crafted,9012boe,9014dungeon", "gear of my level, by where it is from: a drop that binds when picked up is no world drop, a level 40 helm not for level 10")
	local rank = B.Rank(1, 14, 4)
	local ids = {}
	for _, c in ipairs(rank.above) do ids[#ids + 1] = c.id .. c.kind end
	eq(table.concat(ids, ","), "9003quest,9002owned,9014dungeon,9010quest,9012boe,9011crafted", "one list for the head: all that beat the worn helm, the most worth first, each with where it is from")
	eq(rank.above[4].worth, 25, "its weight: what it would add in the worn helm's place"); eq(rank.above[4].pct, 150, "the gain as a part of the worn helm's weight"); eq(rank.worn.worth, 10, "the worn helm has its weight"); eq(rank.above[4].gain, 15, "and how much more that is")
	eq(rank.more, 0, "none left out"); eq(rank.worn.id, 9001, "the worn helm is the one to beat"); eq(#rank.below, 0, "nothing is worse than it here")
	eq(#B.Rank(9, 14, 4).above, 0, "none of them are legs")
	eq(B.Rank(1, 2, 4).more, 4, "a list cut short says how many more beat it")
	-- the tab: what I wear down the left, the stats along the top, what there is to get on the right
	X.DT.UI:Show("bis")
	local G = B.gear
	check(G.progress.text.text:find("%% of the best pre%-raid set"), "the bar says how far along: " .. G.progress.text.text)
	local capText = {}
	for _, bar in ipairs(G.caps) do if bar.shown then capText[#capText + 1] = bar.text.text .. " " .. bar.value.text end end
	eq(#capText, 3, "a bar for each cap"); check(capText[1]:find("Defense 60 / 70", 1, true) and capText[1]:find("owned: 70", 1, true), "defense: the total against the cap, and with the best I own: " .. capText[1])
	check(G.caps[1].sub.text:find("skill 50/50 +10 gear", 1, true) and G.caps[1].tip[1]:find("Defense skill 50 of 50", 1, true), "and under it the base skill over the most for the level and what gear adds, with the same on its tooltip: " .. G.caps[1].sub.text)
	check(capText[3]:find("Hit %% 2 / 8"), "hit: " .. capText[3])
	check(G.stats.text:find("Score 30", 1, true) and G.stats.text:find("Stamina |cffffffff30|r", 1, true), "the stats that count, along the top: " .. G.stats.text)
	local head = G.slots[1]
	eq(head.icon.texture, 1000 + 9001, "a slot shows the picture of what is worn"); check(head.name.text:find("Old Helm", 1, true), "and its name")
	check(head.name.text:find("|cff40ff40>|r", 1, true), "marked where I own something better"); check(not G.slots[9].name.text:find("|cff40ff40>|r", 1, true), "and not where I do not")
	check(head.score.text:find("^10 ") and head.score.text:find("5%%"), "its worth, and how that stands against the list's item: " .. head.score.text)
	check(G.slots[2].name.text:find("nothing worn", 1, true), "an empty slot says so"); eq(G.slots[2].icon.texture, "Interface\\PaperDoll\\UI-Backpack-EmptySlot", "with the empty picture")
	eq(#G.slots, 17, "every slot is on the left")
	head.scripts.OnEnter(head)
	eq(tip.lines[#tip.lines], "item:9001", "a slot shows its item's tooltip")
	-- the right side: at the last level (here level 10 is the last) the whole set to begin with, in versions to compare
	eq(G.head.text, "Whole set", "the last level opens on the whole set")
	local L = G.lines
	check(L[1].head.text:find("Score", 1, true) and L[1].head.text:find("the set you wear", 1, true), "its score, and that of the set worn")
	check(L[2].head.text:find("Defense 70", 1, true) and L[2].head.text:find("you: ", 1, true) and L[2].head.text:find("this set: ", 1, true) and L[3].head.text:find("Expertise", 1, true) and L[4].head.text:find("Hit", 1, true), "then each cap, as I stand and as the set would: " .. L[2].head.text)
	check(L[2].head.text:find("short by 10", 1, true) and L[2].head.text:find("reached", 1, true), "defense: ten short in what I wear, reached in the set")
	check(L[5].n.text:find("Head", 1, true) and L[5].item.id == 9003 and L[5].from.text:find("Quest", 1, true) and L[5].diff.text:find("%+") and L[5].pct.text:find("%%"), "a line for each slot: the item, what it alone would gain, where it is from")
	check(L[5].warn.text:find("#1", 1, true) and L[5].item.swap and L[5].item.swap[1]:find("Just this piece", 1, true), "where it comes in the order to buy in, and the detail on a hover")
	check(L[13].n.text:find("Legs", 1, true) and L[13].item.id == 9005 and L[13].diff.text:find("-8.0", 1, true) and L[13].warn.text:find("#", 1, true), "a listed piece that is worse than what I wear is shown too, with what it costs: " .. L[13].diff.text)
	eq(#X.DT.Bis.PERMS, 4, "the set worn and three more to compare"); eq(G.perms[1].shown, true, "a button each")
	click(G.perms[3]); eq(B.perm, 3, "the third"); check(L[1].head.text:find("Score", 1, true), "is shown"); check(B.Perm(3).short.def == nil, "the one that reaches every cap, as the gear there is allows: defense is")
	click(G.perms[4]); check(L[5].item.shown, "and the fourth"); click(G.perms[1]); check(L[5].item.id == 9001 and L[5].diff.text == "" and L[5].warn.text == "", "the set worn: its own items, no swaps")
	click(G.perms[2])
	eq(G.back.shown, false, "no way back from the whole set")
	click(G.slots[1])
	eq(G.head.text, "Head", "a click on a slot shows its list"); eq(G.back.shown, true, "with a way back to the set")
	local function Row(id) for _, l in ipairs(L) do if l.item.shown and l.item.id == id then return l end end end
	check(L[1].item.id == 9003 and L[1].from.text:find("Quest", 1, true), "the first line is the best item, with where it is from")
	check(L[2].item.id == 9002 and L[2].from.text:find("Owned", 1, true) and L[2].from.text:find("in your bags", 1, true), "one I own and do not wear says so, and where it is")
	check(Row(9010).diff.text:find("+15.0", 1, true) and Row(9010).pct.text:find("+150.0%", 1, true) and Row(9010).wt.text == "25", "each with its weight, its gain over the worn one, and that as a percent of the worn one's weight, in columns of their own")
	check(Row(9010).from.text:find("|cffffd100Quest|r", 1, true) and not Row(9010).from.text:find("Quest:", 1, true), "a quest reward is a Quest, in its own colour")
	check(L[7].item.id == 9001 and L[7].wt.text == "10" and L[7].diff.text == "" and L[7].from.text:find("Equipped", 1, true), "the worn helm stands in its place among them, with its weight and no difference, and its own source"); eq(L[8].item.shown, false, "nothing worse")
	-- (with the quests read: who gives the quest and where, first; a click on the line is a waypoint there)
	local way
	X.DT.Quest.Entry = function(id) return id == 77 and { id = 77, name = "A Helm for the Brave", zoneName = "Durotar" } or nil end
	X.DT.Quest.Origin = function() return { kind = "npc", id = 5, name = "Gar'Thok", text = "Gar'Thok" } end
	X.DT.Quest.Waypoint = function(e) way = e.id end
	e.LibQuestieDB = { Item = { Get = function(id, key) return id == 9010 and key == "questRewards" and { 77 } or nil end } }
	B.wheres = {}
	B.Refresh()
	check(Row(9010).from.text:find("Gar'Thok|r, Durotar", 1, true) and Row(9010).from.text:find("A Helm for the Brave", 1, true), "a quest reward says who gives the quest, and where: " .. Row(9010).from.text)
	click(Row(9010).item)
	eq(way, 77, "a click on it: a waypoint to where the quest is picked up")
	e.LibQuestieDB = nil; eq(Row(9010).icon.texture, 1000 + 9010, "and its picture")
	check(Row(9014).from.text:find("Dungeon", 1, true), "a dungeon drop: " .. Row(9014).from.text); check(Row(9011).from.text:find("Crafted", 1, true), "crafted"); check(Row(9012).from.text:find("World Drop", 1, true), "a world drop not seen on the auction house")
	Row(9014).item.scripts.OnEnter(Row(9014).item)
	eq(tip.lines[#tip.lines], "item:9014", "a line shows its item's tooltip")
	click(G.slots[9])
	eq(G.head.text, "Legs", "a click on a slot shows that slot"); eq(G.slots[9].sel.shown, true, "and marks it")
	check(L[1].head.text:find("Nothing found beats", 1, true), "a slot with nothing better says so")
	check(pcall(B.Refresh), "the slot list is drawn through Refresh for my own class, a worse item among them, without an error")
	check(L[2].item.id == 9007 and L[3].item.id == 9005 and L[3].diff.text:find("-8.0", 1, true), "a worse item stands under the worn one, with what it costs")
	check(select(2, pcall(B.Rank, 9)) ~= nil and #B.Rank(9).below == 4 or #B.Rank(9).below >= 1, "and a call without the counts does not fail")
	click(G.back); eq(G.head.text, "Whole set", "the way back")
	click(G.slots[1])
	step(3) -- (the set is worked out again as items come in; its gains take a moment)
	B.Show("up")
	check(B.up.rows[1].item.text.text:find("Helm of the List", 1, true) and B.up.rows[1].gain.text:find("+35.0", 1, true), "Upgrades lists what to get next")
	eq(B.up.rows[1].icon.texture, 1000 + 9003, "with its picture")
	B.Show("check")
	local text = B.check.text.text
	check(text:find("Old Helm", 1, true) and text:find("Stamina 10", 1, true), "Check shows what was read of each item worn")
	check(text:find("Defense 60", 1, true) and text:find("so 10 comes from talents", 1, true), "and what is left without gear")
	B.Show("weights")
	eq(B.weights.rows.def.cap.text, "70", "Weights shows the cap"); eq(B.weights.rows.sta.w.text, "1", "and what a point is worth")
	check(B.weights.note.text:find("mythicsim.com", 1, true) and B.weights.note.text:find("1.60.1", 1, true) and B.weights.note.text:find("changed by you", 1, true), "with where the values are from, for which client")
	local box = B.weights.rows.sta.w
	box.text = "0"
	box.scripts.OnEnterPressed(box)
	eq(B.Profile().w.sta, 0, "a weight typed in is taken"); eq(B.Gain(9003).up, false, "and counts at once: stamina worth nothing, the helm gains nothing")
	click(B.weights.reset)
	eq(B.Profile().w.sta, 1, "the profile's own values are put back"); eq(B.Profile().caps.def.cap, 440, "the cap too")
	-- the classes and their specs, as pictures
	local nClass = 0
	for _ in pairs(B.classButtons) do nClass = nClass + 1 end
	eq(nClass, 9, "a button for every class"); eq(B.classButtons.WARRIOR.sel.shown, true, "mine marked"); eq(B.classButtons.MAGE.sel.shown, false, "the others not")
	local specs = {}
	for _, b in ipairs(B.specButtons) do if b.shown then specs[#specs + 1] = b.label.text end end
	eq(table.concat(specs, ","), "Arms,Fury,Protection", "under them the specs of the class picked")
	eq(B.specButtons[3].sel.shown, true, "the one in use marked"); eq(B.specButtons[3].icon.texture, "Interface\\Icons\\Ability_Warrior_DefensiveStance", "each with its picture")
	click(B.specButtons[2])
	eq(B.Raw().id, "warrior-fury", "a click on a spec picks it"); eq(B.db.pick[B.me], "warrior-fury", "and it is kept")
	B.Show("gear")
	check(G.progress.text.text:find("no pre-raid list", 1, true), "a spec without a list says so")
	-- another class: its specs, its weights, none of my gear
	click(B.classButtons.MAGE)
	eq(B.Raw().class, "MAGE", "a click on a class goes to it"); eq(B.State().foreign, true, "which is not mine")
	specs = {}
	for _, b in ipairs(B.specButtons) do if b.shown then specs[#specs + 1] = b.label.text end end
	eq(table.concat(specs, ","), "Arcane,Arcane Fire,Fire,Frost,Frostfire", "with its specs")
	check(G.slots[1].name.text:find("nothing worn", 1, true), "my helm is not a mage's"); check(B.status.text:find("Not your class", 1, true), "and the tab says why")
	tip.lines = {}
	X.tooltipHook(tip, { id = 9003 })
	for _, l in ipairs(tip.lines) do check(not l:find("BiS", 1, true), "tooltips say nothing while another class is looked at") end
	click(B.specButtons[3])
	eq(B.Raw().id, "mage-fire", "its spec picked")
	click(B.classButtons.WARRIOR)
	eq(B.Raw().id, "warrior-fury", "back to my class: the spec looked at last")
	click(B.specButtons[3])
	eq(B.Raw().id, "warrior-protection", "and to Protection")
	-- in a fight nothing is worked out
	X.combat = true
	worn[1] = 9002
	X.fire("PLAYER_EQUIPMENT_CHANGED")
	eq(B.Compute(), false, "not in a fight"); eq(B.State().cur[1], 9001, "the state is as it was")
	X.combat = false
	eq(B.State().cur[1], 9002, "and worked out anew after"); eq(B.State().base.def, 60, "defense without gear did not move with the helm")
	leave(X)
	for id in pairs(GEAR) do ITEMS[id] = nil end
end)()

;(function() -- BiS, refined: the defaults, who may wear what, every spec has output, gear found for any class, the tooltip line
	local GEAR = { -- name, where worn, the game's stats, class, subclass, a tooltip line
		[9101] = { "Mage Cowl", "INVTYPE_HEAD", { ITEM_MOD_SPELL_POWER_SHORT = 20 }, 4, 1 },
		[9102] = { "Plate Helm of Power", "INVTYPE_HEAD", { ITEM_MOD_SPELL_POWER_SHORT = 50 }, 4, 4 },
		[9103] = { "Vendor Cowl", "INVTYPE_HEAD", { ITEM_MOD_SPELL_POWER_SHORT = 30 }, 4, 1 },
		[9110] = { "Mail Helm of Rage", "INVTYPE_HEAD", { ITEM_MOD_STRENGTH_SHORT = 30 }, 4, 3 },
		[9111] = { "Sold Mail Helm", "INVTYPE_HEAD", { ITEM_MOD_STRENGTH_SHORT = 20 }, 4, 3 },
		[9130] = { "Worn Ring", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 5 }, 4, 0 },
		[9131] = { "Better Ring", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 9 }, 4, 0 },
		[9140] = { "Worn Sword", "INVTYPE_WEAPON", { ITEM_MOD_STRENGTH_SHORT = 10 }, 2, 7 },
		[9141] = { "Offhand Sword", "INVTYPE_WEAPONOFFHAND", { ITEM_MOD_STRENGTH_SHORT = 12 }, 2, 7 },
		[9142] = { "Great Sword", "INVTYPE_2HWEAPON", { ITEM_MOD_STRENGTH_SHORT = 40 }, 2, 8 },
		[9150] = { "Mage Only Hat", "INVTYPE_HEAD", { ITEM_MOD_STRENGTH_SHORT = 99 }, 4, 3, "Classes: Mage" },
		[9160] = { "Unseen Helm", "INVTYPE_HEAD", { ITEM_MOD_STRENGTH_SHORT = 99 }, 4, 3 },
	}
	for i = 1, 8 do GEAR[9200 + i] = { "Cowl " .. i, "INVTYPE_HEAD", { ITEM_MOD_SPELL_POWER_SHORT = 20 + i }, 4, 1 } end
	for id, g in pairs(GEAR) do ITEMS[id] = { g[1], 2, 1, 100, false, g[4], g[5], slot = g[2] } end
	local worn = { [11] = 9130, [16] = 9140 }
	local X = NewClient("BisMore", { globals = function(env)
		env.GetInventoryItemID = function(_, slot) return worn[slot] end
		env.GetItemStats = function(link)
			local g = GEAR[tonumber(link:match("item:(%d+)"))]
			return g and g[3] or {}
		end
		env.C_TooltipInfo = { GetItemByID = function(id)
			local g = GEAR[id]
			return { lines = { { leftText = ITEMS[id][1] }, g and g[6] and { leftText = g[6] } or nil } }
		end }
		env.UnitDefense = function() return 60, 0 end
	end })
	local B, e, BL, V = X.DT.Bis, X.env, X.DT.BisLogic, X.DT.Market.View
	B.MAX_LEVEL = e.UnitLevel("player")
	-- what a fresh user gets is what is shipped, for every spec; a change is the profile's own, and is put back
	for _, raw in ipairs(X.DT.BisProfiles) do
		B.Pick(raw.id)
		local p = B.Profile()
		local same = true
		for word, n in pairs(raw.w) do same = same and p.w[word] == n end
		for word, n in pairs(p.w) do same = same and (raw.w[word] == n or (raw.caps[word] and n == 0)) end
		for word, cap in pairs(raw.caps) do
			local at = p.caps[word]
			same = same and at and at.cap == cap.cap and (at.over or 0) == (cap.over or 0) and at.hard == cap.hard
		end
		for word in pairs(p.caps) do same = same and raw.caps[word] ~= nil end
		check(same and B.db.edit[raw.id] == nil, raw.id .. ": with nothing changed, the weights and caps are the shipped ones")
		check(p.hands and #p.hands > 0, raw.id .. ": says what the hands may hold")
	end
	B.Pick("paladin-shockadin")
	local dw = false
	for _, h in ipairs(B.Profile().hands) do dw = dw or h == "dw" end
	eq(dw, false, "a paladin spec that does not say what the hands hold does not wield two weapons")
	B.Pick("hunter-beastmastery")
	B.Edit("crit", "w", 99); B.Edit("hit", "cap", 5); B.Edit("hit", "over", 2)
	eq(B.Profile().w.crit, 99, "a weight typed in"); eq(B.Profile().caps.hit.cap, 5, "a cap typed in"); check(B.db.edit["hunter-beastmastery"], "kept for that profile")
	B.Pick("hunter-marksmanship"); eq(B.Profile().w.crit, 11.76, "another spec is not touched by it")
	B.Pick("hunter-beastmastery")
	B.Edit("crit", "w", nil); B.Edit("hit", "cap", nil)
	eq(B.Profile().caps.hit.cap, 8, "a cap emptied is the default again"); eq(B.db.edit["hunter-beastmastery"], nil, "and with nothing else changed nothing is kept")
	B.ResetEdits()
	eq(B.Profile().w.crit, 12.74, "reset to default: the weight"); eq(B.Profile().caps.hit.cap, 8, "the cap"); eq(B.Profile().caps.hit.over, 0, "and past the cap")
	B.Edit("crit", "w", 99); B.Edit("crit", "w", nil)
	eq(B.db.edit["hunter-beastmastery"], nil, "a change put back by hand leaves nothing kept")
	B.Edit("sta", "over", 3)
	eq(B.db.edit["hunter-beastmastery"], nil, "a past-the-cap value for a stat with no cap changes nothing")
	-- the game's one spell power is healing for a healer too
	eq(BL.Stats({ ITEM_MOD_SPELL_POWER_SHORT = 30 }).heal, 30, "spell power counts as healing")
	eq(BL.Stats({ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 30 }).heal, nil, "damage alone does not")
	eq(BL.Stats({ ITEM_MOD_SPELL_POWER_SHORT = 30, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 40 }).heal, 40, "nor over what the game says of healing")
	-- who may wear and wield what at the last level, by class
	local ALL = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
	local MAY = { -- class, subclass, the classes that may
		{ 4, 1, "WARRIOR PALADIN HUNTER ROGUE PRIEST SHAMAN MAGE WARLOCK DRUID" }, { 4, 2, "WARRIOR PALADIN HUNTER ROGUE SHAMAN DRUID" },
		{ 4, 3, "WARRIOR PALADIN HUNTER SHAMAN" }, { 4, 4, "WARRIOR PALADIN" }, { 4, 6, "WARRIOR PALADIN SHAMAN" },
		{ 4, 7, "PALADIN" }, { 4, 8, "DRUID" }, { 4, 9, "SHAMAN" }, { 4, 0, "WARRIOR PALADIN HUNTER ROGUE PRIEST SHAMAN MAGE WARLOCK DRUID" },
		{ 2, 0, "WARRIOR PALADIN HUNTER SHAMAN" }, { 2, 1, "WARRIOR PALADIN HUNTER SHAMAN" }, { 2, 4, "WARRIOR PALADIN ROGUE PRIEST SHAMAN DRUID" },
		{ 2, 5, "WARRIOR PALADIN SHAMAN DRUID" }, { 2, 6, "WARRIOR PALADIN HUNTER DRUID" }, { 2, 7, "WARRIOR PALADIN HUNTER ROGUE MAGE WARLOCK" },
		{ 2, 8, "WARRIOR PALADIN HUNTER" }, { 2, 10, "WARRIOR HUNTER PRIEST SHAMAN MAGE WARLOCK DRUID" },
		{ 2, 13, "WARRIOR HUNTER ROGUE SHAMAN DRUID" }, { 2, 15, "WARRIOR HUNTER ROGUE PRIEST SHAMAN MAGE WARLOCK DRUID" },
		{ 2, 2, "WARRIOR HUNTER ROGUE" }, { 2, 3, "WARRIOR HUNTER ROGUE" }, { 2, 18, "WARRIOR HUNTER ROGUE" }, { 2, 16, "WARRIOR HUNTER ROGUE" },
		{ 2, 19, "PRIEST MAGE WARLOCK" },
	}
	for _, m in ipairs(MAY) do
		local want, got = {}, {}
		for class in m[3]:gmatch("%S+") do want[#want + 1] = class end
		for _, class in ipairs(ALL) do
			if V.MayUse(m[1], m[2], { me = class, level = 60, trained = false }) then got[#got + 1] = class end
		end
		table.sort(want); table.sort(got)
		eq(table.concat(got, " "), table.concat(want, " "), ("who may use item class %d, subclass %d"):format(m[1], m[2]))
	end
	eq(V.MayUse(4, 4, { me = "WARRIOR", level = 30, trained = false }), false, "plate is for level 40 and up"); eq(V.MayUse(4, 3, { me = "WARRIOR", level = 30, trained = false }), true, "mail before")
	-- every spec has output: a set to the last slot, scored, wearing only what the class may
	local cat, n = {}, 0
	local function Add(loc, class, sub, extra)
		n = n + 1
		local s = { sta = 5, str = 5, agi = 5, int = 5, spi = 5, sp = 5, heal = 5, mp5 = 2, ap = 10, rap = 10, fap = 10, dps = 20, crit = 1, scrit = 1, haste = 1 }
		for k, v in pairs(extra or {}) do s[k] = v end
		cat[n] = { id = n, loc = loc, class = class, sub = sub, s = s }
	end
	for _, loc in ipairs({ "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET" }) do
		for sub = 1, 4 do Add(loc, 4, sub) end
	end
	Add("INVTYPE_CLOAK", 4, 1, { def = 5, exp = 1 }); Add("INVTYPE_NECK", 4, 0, { hit = 1, shit = 1 })
	Add("INVTYPE_FINGER", 4, 0, { hit = 1 }); Add("INVTYPE_FINGER", 4, 0, { shit = 1 }); Add("INVTYPE_TRINKET", 4, 0); Add("INVTYPE_TRINKET", 4, 0)
	for _, sub in ipairs({ 0, 4, 7, 13, 15 }) do Add("INVTYPE_WEAPON", 2, sub); Add("INVTYPE_WEAPONOFFHAND", 2, sub) end
	for _, sub in ipairs({ 1, 5, 6, 8, 10 }) do Add("INVTYPE_2HWEAPON", 2, sub) end
	Add("INVTYPE_SHIELD", 4, 6, { def = 20, bv = 5 }); Add("INVTYPE_HOLDABLE", 4, 0)
	Add("INVTYPE_RANGED", 2, 2); Add("INVTYPE_RANGEDRIGHT", 2, 3); Add("INVTYPE_RANGEDRIGHT", 2, 18); Add("INVTYPE_RANGEDRIGHT", 2, 19); Add("INVTYPE_THROWN", 2, 16)
	for _, sub in ipairs({ 7, 8, 9 }) do Add("INVTYPE_RELIC", 4, sub) end
	local DUAL = { WARRIOR = true, ROGUE = true, HUNTER = true, SHAMAN = true }
	for _, raw in ipairs(X.DT.BisProfiles) do
		B.Pick(raw.id)
		local prof, who, list = B.Profile(), { me = raw.class, level = 60, trained = false }, {}
		for _, it in ipairs(cat) do
			if V.MayUse(it.class, it.sub, who) then list[#list + 1] = { id = it.id, loc = it.loc, s = it.s, n = 1 } end
		end
		local picks, _, score = BL.Solve(BL.Choices(list, prof), {}, prof)
		local empty = {}
		for i = 1, 10 do if #picks[i].ids ~= 1 then empty[#empty + 1] = BL.SLOTS[i][1] end end
		if #picks[11].ids ~= 2 then empty[#empty + 1] = "Rings" end
		if #picks[12].ids ~= 2 then empty[#empty + 1] = "Trinkets" end
		if #picks[13].ids < 1 then empty[#empty + 1] = "Weapons" end
		if #picks[14].ids < 1 then empty[#empty + 1] = "Ranged" end
		check(#empty == 0 and score > 0, raw.id .. ": every slot filled and a score (empty: " .. table.concat(empty, ",") .. "; score " .. tostring(score) .. ")")
		local rule = true
		for _, pick in ipairs(picks) do
			for _, id in ipairs(pick.ids) do rule = rule and V.MayUse(cat[id].class, cat[id].sub, who) end
		end
		local hands = picks[13].ids
		if #hands == 2 and (cat[hands[2]].loc == "INVTYPE_WEAPON" or cat[hands[2]].loc == "INVTYPE_WEAPONOFFHAND") then rule = rule and DUAL[raw.class] end
		check(rule, raw.id .. ": wears and wields only what its class may")
	end
	-- gear found for a class that is not mine, by what that class may wear; the best few of a place to wear go in its set
	local Item = X.DT.Item
	Item.Start, Item.Ready = function() return false end, function() return true end
	local ENTRIES = {}
	for id, g in pairs(GEAR) do if id ~= 9160 then ENTRIES[#ENTRIES + 1] = { id = id, req = 1, c = g[4], s = g[5], src = { [(id == 9103 or id == 9111) and "Vendor" or "Quest reward"] = true } } end end
	Item.All = function() return ENTRIES end
	X.DT.CraftSkill = {}
	local function Look() for _ = 1, 400 do B.Sift(); step(0.2) end end
	B.Pick("mage-fire")
	Look()
	step(3) -- (what was found goes into the set by itself, once all are looked at)
	local s = B.State()
	eq(s.foreign, true, "a mage's spec looked at")
	local got = {}
	for _, c in ipairs(B.finder.got) do got[c.id] = c.kind end
	eq(got[9102], nil, "plate is not found for a mage"); eq(got[9103], "vendor", "a vendor's cowl is"); eq(got[9110], nil, "nor a warrior's mail")
	local heads = 0
	for _, c in ipairs(s.all) do if c.loc == "INVTYPE_HEAD" then heads = heads + 1 end end
	eq(heads, 6, "of ten cowls the best six go into the set"); eq(s.bis.rows[1], 9103, "the best of them is its head")
	check(s.bis.score > 0, "a set for a class that has no list of its own")
	-- my own class: the same, and what I do not own is an upgrade
	B.Pick("warrior-fury")
	Look()
	step(5)
	s = B.State()
	eq(s.foreign, false, "my own class"); eq(s.bis.rows[1], 9110, "the best set found has the best helm"); eq(B.Where(9111, "vendor"), "sold by a vendor", "a vendor's item says so")
	local rank = B.Rank(1, 14, 4)
	eq(#rank.above, 2, "an empty slot: what is worth anything is above"); eq(rank.above[2].id, 9111, "the sold mail helm after the better one"); eq(B.Tag(9111, "vendor"), "Vendor", "and a vendor")
	eq(#rank.below, 4, "four of the rest are shown under it"); eq(rank.worn, nil, "nothing worn to show"); eq(rank.above[1].new, true, "an empty slot: the gain is all new"); eq(rank.above[1].pct, nil, "and no percent")
	eq(B.Rank(11, 14, 4).ref, 12, "two rings: the empty finger is the one to beat"); eq(B.Rank(11, 14, 4).above[1].id, 9131, "the better ring is above it")
	eq(s.upg[1] and s.upg[1].id, 9110, "upgrades without a list: the helm gains the most"); eq(s.rank[9110], 1, "numbered")
	-- the tooltip: where the item goes
	local tip = e.GameTooltip
	local function Line(id)
		tip.lines = {}
		X.tooltipHook(tip, { id = id })
		for _, l in ipairs(tip.lines) do if l:find("BiS", 1, true) then return l end end
	end
	check(Line(9110):find("+30.0", 1, true) and Line(9110):find("Head", 1, true), "an item I can use: what it gains, and where")
	check(Line(9131):find("Ring", 1, true) and not Line(9131):find("Rings", 1, true), "a ring takes one ring's place")
	check(Line(9141):find("Off hand", 1, true), "an off-hand weapon says so")
	eq(Line(9150), nil, "an item only a mage may wear: nothing is said")
	eq(B.Gain(9150).no, true, "though it is known not to be for me")
	B.Pick("warrior-arms")
	B.Compute()
	check(Line(9142):find("Two-hand", 1, true), "a two-hander says so")
	B.Pick("warrior-fury")
	B.Compute()
	-- in a fight: nothing is asked of the game, nothing said of an item not seen
	local asks = 0
	local real = e.C_Item.RequestLoadItemDataByID
	e.C_Item.RequestLoadItemDataByID = function() asks = asks + 1 end
	X.uncached[9160] = true
	X.combat = true
	eq(Line(9160), nil, "no line for an unseen item in a fight"); eq(asks, 0, "and the game is not asked about it")
	X.combat = false
	-- an item the game is slow to give: asked again and again, not on every look, and then left alone
	asks = 0
	B.Item(9160); B.Item(9160)
	eq(asks, 1, "asked once for two looks")
	for _ = 1, 8 do step(5); B.Item(9160) end
	eq(asks, 6, "asked again every few seconds, six times"); step(5); eq(B.Gone(9160), true, "and then known to be gone")
	e.C_Item.RequestLoadItemDataByID, X.uncached[9160] = real, nil
	leave(X)
	for id in pairs(GEAR) do ITEMS[id] = nil end
end)()
;(function() -- BiS, fast: how many items a spec asks the game for, the best first, shown as they come, and nothing asked twice
	local LOADED = {} -- the best of the list: loaded at once, as if kept from an earlier session
	local function Client(name)
		local X = NewClient(name, { globals = function(env)
			env.UnitLevel = function() return 60 end
			env.GetItemStats = function(link) return LOADED[tonumber(link:match("item:(%d+)"))] and { ITEM_MOD_STRENGTH_SHORT = 40 } or {} end
			env.C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = "x" } } } end }
		end })
		X.DT.Bis.MAX_LEVEL = 60
		return X
	end
	-- a stand-in item list the size of Classic's gear: 9000 pieces, a tenth of them needing no level
	local ENTRIES, byId = {}, {}
	for i = 1, 9000 do
		local req = i % 10 == 0 and 0 or 20 + (i * 7) % 41
		ENTRIES[i] = { id = 40000 + i, req = req, ilvl = req + (i * 3) % 17, c = i % 5 == 0 and 2 or 4, s = i % 5 == 0 and (i % 3) * 4 or i % 5,
			src = { [({ "Quest reward", "Drop", "Vendor", "Crafted" })[i % 4 + 1]] = true } }
	end
	for i = 1, 12 do -- (plate helms of the highest item level, a quest reward each)
		local id = 49000 + i
		ENTRIES[#ENTRIES + 1] = { id = id, req = 60, ilvl = 300 + i, c = 4, s = 4, src = { ["Quest reward"] = true } }
		ITEMS[id], LOADED[id] = { "Helm " .. i, 3, 1, 100, false, 4, 4, slot = "INVTYPE_HEAD", lvl = 60 }, true
	end
	local DG = Client("BisFast").DT.Dungeon -- (the item list knows what the bosses drop, as the real one does)
	for _, d in ipairs(DG.All()) do
		for _, boss in ipairs(d.bosses) do
			for id in pairs(boss.has) do ENTRIES[#ENTRIES + 1] = { id = id, req = 50, ilvl = 60 + id % 20, c = 4, s = id % 4 + 1, src = { Drop = true } } end
		end
	end
	for _, en in ipairs(ENTRIES) do byId[en.id] = en end
	local function Prepare(X)
		X.DT.Item.Start, X.DT.Item.Ready, X.DT.Item.All = function() return false end, function() return true end, function() return ENTRIES end
		X.DT.CraftSkill = {}
		local asked, order, total = {}, {}, { n = 0 }
		X.env.C_Item.RequestLoadItemDataByID = function(id)
			total.n = total.n + 1
			if not asked[id] then asked[id], order[#order + 1] = true, id end
		end
		return asked, order, total
	end
	local before = { ["warrior-fury"] = 5083 } -- (what the same list asked before the item level cut: measured with this block)
	local counts = {}
	for _, spec in ipairs({ "warrior-fury", "mage-fire", "priest-holy", "rogue-combat" }) do
		local X = Client("BisFast")
		local B = X.DT.Bis
		local asked, order = Prepare(X)
		B.Pick(spec)
		for _ = 1, 700 do B.Sift(); step(0.2) end
		local n = 0
		for _ in pairs(asked) do n = n + 1 end
		counts[#counts + 1] = spec .. " " .. n
		check(n <= 1500, spec .. ": asks the game for at most 1500 of 9000 items (asked " .. n .. ")")
		local first, last, k = 0, 0, math.min(40, #order)
		for i = 1, k do first, last = first + (byId[order[i]] and byId[order[i]].ilvl or 99), last + (byId[order[#order - i + 1]] and byId[order[#order - i + 1]].ilvl or 99) end
		check(k == 0 or first >= last, spec .. ": the best prospects are asked for first")
		leave(X)
	end
	-- a look at what there is: the best set stands after the first few, with the rest still to come
	local X = Client("BisFast")
	local B, e = X.DT.Bis, X.env
	local asked, _, total = Prepare(X)
	B.Pick("warrior-fury")
	for _ = 1, 20 do B.Sift(); step(0.2) end
	step(3)
	local s = B.State()
	check(#B.finder.todo > 100, "most items are still to come")
	check(s.bis and s.bis.rows[1] and s.bis.rows[1] > 49000 or error("DBG " .. tostring(B.Item(49001)) .. tostring(B.finder.kind[49001]) .. tostring(B.finder.gone) .. tostring(s.bis and s.bis.rows[1]) .. " got " .. #B.finder.got .. " todo " .. #B.finder.todo), "yet the best set is shown, with the best helm of those looked at")
	check(B.db.facts[49001] ~= nil, "what the game said of an item is kept for the next session")
	-- what is kept is not asked again, in a session after
	local seen = total.n
	B.db.facts[41234] = { id = 41234, loc = "INVTYPE_HEAD", name = "Kept Helm", q = 3, lvl = 50, s = { str = 30 } }
	check(B.Item(41234) and B.Item(41234).name == "Kept Helm", "an item kept from before is known without the game")
	eq(total.n, seen, "and is not asked for")
	-- another spec of the same class does not start over; items the game never gave are not asked for again
	for _ = 1, 700 do B.Sift(); step(0.2) end
	local done = total.n
	B.Pick("warrior-arms")
	for _ = 1, 100 do B.Sift(); step(0.2) end
	eq(total.n, done, "another spec of the class asks for nothing more")
	eq(#B.finder.todo, 0, "and everything asked is answered or given up on")
	-- not in a fight
	B.Pick("mage-fire")
	X.combat = true
	for _ = 1, 20 do B.Sift(); step(0.2) end
	eq(total.n, done, "nothing is asked in a fight")
	X.combat = false
	leave(X)
	for id in pairs(LOADED) do ITEMS[id] = nil end
end)()
;(function() -- BiS, spec and level: the tab opens on my class and spec, a level can be picked, the phase at the last level, defense as base plus gear
	local GEAR = { -- name, level, strength
		[9301] = { "Young Helm", 5, 3 }, [9302] = { "Mid Helm", 25, 10 }, [9303] = { "Late Helm", 38, 20 }, [9304] = { "High Helm", 55, 40 },
		[9305] = { "Top Helm", 60, 60 }, [9306] = { "Raid Helm", 60, 80 }, [9307] = { "Spire Helm", 55, 30 },
		[99401] = { "Hit Helm", 1, { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_HIT_RATING_SHORT = 80 } }, [99402] = { "Strong Helm", 1, 50 },
		[99403] = { "Hit Shoulders", 1, { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_HIT_RATING_SHORT = 80 }, "INVTYPE_SHOULDER" },
	}
	for id, g in pairs(GEAR) do ITEMS[id] = { g[1], 2, 1, 100, false, 4, 2, slot = g[4] or "INVTYPE_HEAD", lvl = g[2] } end
	local wornSlots = {}
	local points, spec = { 0, 0, 0 }, "tabs"
	local X = NewClient("BisSpec", { globals = function(env)
		env.UnitLevel = function() return 40 end
		env.GetItemStats = function(link)
			local g = GEAR[tonumber(link:match("item:(%d+)"))][3]
			return type(g) == "table" and g or { ITEM_MOD_STRENGTH_SHORT = g }
		end
		env.GetInventoryItemID = function(_, slot) return wornSlots[slot] end
		env.C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = ITEMS[id][1] } } } end }
		env.UnitDefense = function() return 195, 12 end
		env.GetNumTalentTabs = function() return 3 end
		env.GetTalentTabInfo = function(i)
			if spec == "tabs" then return "Tab " .. i, "icon", points[i], "background" end -- (Classic: name, icon, points)
			return 100 + i, "Tab " .. i, "text", "icon", points[i] -- (later: id, name, text, icon, points)
		end
	end })
	local B, e, BL = X.DT.Bis, X.env, X.DT.BisLogic
	-- the spec I am, from the talent trees
	eq(B.Default(), nil, "no points spent: nothing can be told"); eq(B.Raw().id, "warrior-arms", "and the first of the class is shown")
	points = { 5, 31, 15 }
	eq(B.Default(), "warrior-fury", "the tree with the most points"); eq(B.Raw().id, "warrior-fury", "is the spec the tab opens on")
	points = { 0, 5, 46 }; eq(B.Raw().id, "warrior-protection", "a tank's tree is its spec: the plain profile of it")
	points = { 10, 10, 0 }; eq(B.Raw().id, "warrior-arms", "equal trees: the first")
	spec = "later"; points = { 0, 0, 40 }; eq(B.Raw().id, "warrior-protection", "the later layout of the call is read too")
	spec, points = "tabs", { 5, 31, 15 }
	B.Pick("warrior-arms")
	eq(B.Raw().id, "warrior-arms", "a spec picked by hand wins"); eq(B.db.pick[B.me], "warrior-arms", "and is kept for the character")
	B.db.pick[B.me] = nil
	B.db.last = {}
	B.PickClass("MAGE"); B.PickClass("WARRIOR")
	eq(B.db.pick[B.me], "warrior-fury", "back to my class with nothing picked: my spec")
	B.db.pick[B.me] = nil
	e.GetTalentTabInfo, e.GetSpecialization = nil, function() return 2 end
	eq(B.Raw().id, "warrior-fury", "a client that names the active spec only: its place is the tree")
	e.GetSpecialization = nil
	eq(B.Raw().id, "warrior-arms", "no talent function at all: the first of the class")
	e.GetTalentTabInfo = function() error("not here") end
	eq(B.Raw().id, "warrior-arms", "a talent function that fails is no matter")
	local ALLP = X.DT.BisProfiles
	for class, names in pairs(BL.TREES) do
		for i, name in ipairs(names) do
			local id = BL.SpecId(class, { [i] = 9 }, ALLP)
			check(id and id:find("^" .. class:lower() .. "%-"), class .. " " .. name .. ": a profile of the class for the tree (" .. tostring(id) .. ")")
		end
	end
	eq(BL.SpecId("WARRIOR", { 0, 0, 0 }, ALLP), nil, "no points: no spec"); eq(BL.SpecId("DRUID", { 0, 9, 0 }, ALLP), "druid-feral", "Feral: the cat; the bear is a click")
	-- a level to look at: gear for that level, the lower bound with it, what was learned of items kept
	e.GetTalentTabInfo = function(i) return "Tab " .. i, "icon", points[i] end
	B.db.pick[B.me] = nil
	local Item, Dg = X.DT.Item, X.DT.Dungeon
	local spire, onyxia
	for _, d in ipairs(Dg.All()) do
		if d.name == "Upper Blackrock Spire" then spire = d end
		if d.name == "Onyxia's Lair" then onyxia = d end
	end
	spire.bosses[1].has[9307], onyxia.bosses[1].has[9306] = true, true
	Item.Start, Item.Ready = function() return false end, function() return true end
	Item.All = function() return {
		{ id = 9301, req = 5, c = 4, s = 2, src = { ["Quest reward"] = true } }, { id = 9302, req = 25, c = 4, s = 2, src = { ["Quest reward"] = true } },
		{ id = 9303, req = 38, c = 4, s = 2, src = { ["Quest reward"] = true } }, { id = 9304, req = 55, c = 4, s = 2, src = { ["Quest reward"] = true } },
		{ id = 9305, req = 60, c = 4, s = 2, src = { ["Quest reward"] = true } }, { id = 9306, req = 60, c = 4, s = 2, src = { Drop = true } },
		{ id = 9307, req = 55, c = 4, s = 2, src = { Drop = true } },
		{ id = 9308, req = 60, ilvl = 83, c = 4, s = 2, src = { Drop = true } }, { id = 9309, req = 38, c = 4, s = 2, src = { Drop = true } },
	} end
	-- (9308: dropped by a mob that stands in a raid the dungeon list does not have; 9309: by a boss of a dungeon for higher levels than mine)
	spire.bosses[1].has[9309] = true
	e.LibQuestieDB = { Item = { Get = function(id, key) return id == 9308 and key == "npcDrops" and { 15990 } or nil end },
		Npc = { Get = function(id, key) return id == 15990 and key == "zoneID" and 3456 or nil end } }
	e.C_Map = e.C_Map or {}
	e.C_Map.GetAreaInfo = function(area) return area == 3456 and "Naxxramas" or nil end
	X.DT.CraftSkill = {}
	local function Look() for _ = 1, 400 do B.Sift(); step(0.2) end step(3) end
	local function List()
		B.State()
		local rank, ids = B.Rank(1, 14, 4), {}
		for _, c in ipairs(rank.above) do ids[#ids + 1] = c.id end
		return table.concat(ids, ",")
	end
	eq(B.ViewLevel(), 40, "my own level to begin with"); Look()
	eq(List(), "9303,9302", "gear for my level, and not what is more than fifteen levels below it")
	eq(B.finder.kind[9309], "dungeon", "a boss's drop is a dungeon's drop also where the dungeon is for higher levels than the one looked at, not a world drop")
	local facts = B.db.facts
	B.SetLevel(20); Look()
	eq(B.ViewLevel(), 20, "a level picked"); eq(List(), "9301", "its own gear: the lower bound goes with the level")
	B.SetLevel(60); Look()
	eq(List(), "9305,9304,9307", "the last level: pre-raid gear, no raid's")
	eq(B.finder.kind[9308], nil, "nor the drop of a raid the dungeon list does not have: it is known for a raid's by where the mob that drops it stands")
	B.SetLevel(nil)
	eq(B.ViewLevel(), 40, "back to my level"); eq(B.db.level[B.me], nil, "nothing kept of it"); B.SetLevel(40); eq(B.db.level[B.me], nil, "my own level picked is nothing picked")
	B.SetLevel(99); eq(B.ViewLevel(), 60, "no more than the last level"); B.SetLevel(0); eq(B.ViewLevel(), 1, "no less than one"); B.SetLevel("x"); eq(B.ViewLevel(), 40, "a word is no level")
	Look()
	eq(List(), "9303,9302", "my level again"); check(rawequal(B.db.facts, facts) and facts[9304] ~= nil and facts[9302] ~= nil, "what was learned of items stays with a change of level")
	-- the phase, at the last level
	eq(B.Phase(), nil, "below the last level there is no phase")
	B.SetLevel(60); Look()
	eq(B.Phase()[2], "Pre-raid", "the last level: pre-raid to begin with")
	eq(Dg.IsRaid(onyxia), true, "Onyxia's Lair is a raid"); eq(Dg.IsRaid(spire), false, "Upper Blackrock Spire is not")
	eq(B.Tag(9307, "dungeon"), "Dungeon", "a dungeon's drop"); eq(B.Tag(9306, "dungeon"), "Raid", "a raid's"); eq(B.Tag(1, "owned"), "Owned", "an item I own")
	-- (the last level: the whole set, three versions of it, and the slot's list on a click)
	X.DT.UI:Show("bis")
	local G = B.gear
	eq(G.head.text, "Whole set", "the last level opens on the whole set"); eq(G.perms[4].shown, true, "with the set worn and three versions to compare")
	local set1, set2, set3 = B.Perm(2), B.Perm(3), B.Perm(4)
	eq(set1.rows[1], 9305, "the best set has the best helm there is before the raids"); eq(set2.rows[1], 9305, "the one that reaches every cap too, there being none"); eq(set3.rows[1], 9305, "and the one of what I own and the best finds")
	click(G.slots[1]); eq(G.head.text, "Head", "a slot clicked: its list"); click(G.back); eq(G.head.text, "Whole set", "and back")
	B.SetPhase("all"); Look()
	eq(B.Phase()[2], "Everything", "the other phase"); eq(List(), "9306,9305,9304,9307", "has the raid's drops too"); eq(B.finder.kind[9308], "boe", "that raid's as well"); eq(B.Perm(2).rows[1], 9306, "and the set the raid's helm")
	B.SetPhase("pre"); eq(B.Phase()[1], "pre", "and back")
	table.insert(B.PHASES, 2, { "one", "Tier 1", { "Onyxia's Lair" } }) -- (a tier is one more line: a name, and the raids out so far)
	B.SetPhase("one"); Look()
	eq(B.Phase()[2], "Tier 1", "a tier"); eq(List(), "9306,9305,9304,9307", "has the raids it names")
	table.remove(B.PHASES, 2)
	B.db.phase[B.me] = nil
	-- the controls: a box for the level, a way back, the phase button
	X.DT.UI:Show("bis")
	local C = B.level
	check(C.box.text == "60" and C.mine.shown and C.mine.label.text:find("40", 1, true) and C.phase.shown and C.phase.label.text == "Pre-raid", "the box says the level, with a way back to mine and the phase")
	-- the phase: a pick-list of every phase, shown at the last level only
	click(C.phase)
	check(C.phase.menu.shown, "the phase button opens its list")
	local named = {}
	for _, row in ipairs(C.phase.menu.rows) do if row.shown and row.entry then named[#named + 1] = row.entry.text end end
	eq(table.concat(named, ","), "Pre-raid,Everything", "the list has every phase")
	click(C.phase.menu.rows[2])
	eq(B.Phase()[1], "all", "one picked from it"); eq(C.phase.label.text, "Everything", "and shown on the button"); eq(C.phase.menu.shown, false, "the list closes")
	B.SetPhase("pre")
	-- the level: - and + step it, the number can be typed, the list is made anew once it has settled
	local calls, real = 0, B.SetLevel
	B.SetLevel = function(n) calls = calls + 1 return real(n) end
	click(C.minus); click(C.minus); click(C.minus)
	eq(C.box.text, "57", "a click on - steps down and the box shows it at once"); eq(calls, 0, "nothing is made anew yet"); eq(B.ViewLevel(), 60, "the level looked at waits")
	click(C.plus)
	eq(C.box.text, "58", "+ steps up")
	step(0.5)
	eq(calls, 1, "one rebuild after several quick clicks"); eq(B.ViewLevel(), 58, "and the level is the last one asked for"); check(not C.phase.shown, "no phase below the last level")
	for _ = 1, 3 do click(C.plus) end
	step(0.5)
	eq(B.ViewLevel(), 60, "no more than the last level"); check(C.phase.shown, "the phase is back")
	for _ = 1, 70 do click(C.minus) end
	step(0.5)
	eq(B.ViewLevel(), 1, "no less than 1")
	C.plus.scripts.OnMouseDown(C.plus); step(0.5); B.panel.scripts.OnUpdate(B.panel); C.plus.scripts.OnMouseUp(C.plus) -- (held: it goes on by itself; the game's frame is run by hand)
	click(C.plus)
	eq(B.pendingLevel, 2, "a button held down steps on, and the click that ends the hold steps no more"); step(0.5); eq(B.ViewLevel(), 2, "and settles")
	C.box.text = "40"; C.box.scripts.OnEnterPressed(C.box)
	check(B.ViewLevel() == 40 and not C.mine.shown and not C.phase.shown, "a level typed in is taken at once; my own needs no way back, and there is no phase")
	C.box.text = "30"; C.box.scripts.OnEnterPressed(C.box)
	eq(B.ViewLevel(), 30, "another"); check(C.mine.shown, "the way back shows"); click(C.mine); eq(B.ViewLevel(), 40, "the button goes back to mine")
	B.SetLevel = real
	eq(G.head.text, "Head", "below the last level the list of a slot is the main thing")
	-- one piece at a time: what it does to the set I wear, and to a cap I meet now
	e.UnitDefense = function() return 195, 12 end
	wornSlots[1] = 99401
	B.SetLevel(nil); B.Pick("warrior-fury"); B.Stale(); step(3)
	local st = B.State()
	local sw = B.Swaps(st, { rows = { [1] = 99402, [3] = 99403 } })
	eq(#sw[1].breaks, 1, "a helm that gives up the hit the worn one has: a swap that breaks a cap"); eq(sw[1].breaks[1], "hit", "the cap it breaks"); check(sw[1].d < 0 and sw[1].pct < 0, "and costs score")
	eq(#sw[3].breaks, 0, "shoulders that add hit break nothing"); check(sw[3].d > 0, "and gain"); eq(sw[3].order, 1, "they come first"); eq(sw[1].order, 2, "the helm after them")
	eq(sw[1].needs[1].by, 3, "the helm says which piece to get first: the shoulders"); eq(sw[3].caps.hit.after, 16, "hit as it would stand")
	wornSlots[1] = nil
	-- a list longer than the panel: the mouse wheel and the bar reach every row
	for i = 1, 40 do
		GEAR[99600 + i] = { "Many " .. i, 30, i }
		ITEMS[99600 + i] = { "Many " .. i, 2, 1, 100, false, 4, 2, slot = "INVTYPE_HEAD", lvl = 30 }
	end
	local more = Item.All
	Item.All = function()
		local list = more()
		for i = 1, 40 do list[#list + 1] = { id = 99600 + i, req = 30, c = 4, s = 2, src = { ["Quest reward"] = true } } end
		return list
	end
	B.Pick("warrior-fury"); B.SetLevel(41); Look()
	X.DT.UI:Show("bis"); click(G.slots[1]); B.Refresh()
	local first = G.lines[1].item.id
	check(G.bar.shown, "more rows than fit: a bar")
	B.panel.scripts.OnMouseWheel(B.panel, -1)
	check(G.lines[1].item.id ~= first and B.scroll == 3, "the wheel moves the list")
	for _ = 1, 30 do B.panel.scripts.OnMouseWheel(B.panel, -1) end
	local seen = {}
	for _, l in ipairs(G.lines) do if l.item.shown then seen[l.item.id] = true end end
	check(seen[99601], "the last of them is reached")
	B.panel.scripts.OnMouseWheel(B.panel, 100); eq(G.lines[1].item.id, first, "and back to the top")
	B.SetLevel(nil)
	-- another class's spec, at a level of its own
	B.PickClass("MAGE")
	eq(B.ViewLevel(), 60, "another class: the last level to begin with"); B.SetLevel(30); eq(B.State().who.level, 30, "and any level there is")
	B.SetLevel(nil); B.PickClass("WARRIOR")
	-- defense: base skill over the most for the level, then what gear adds, then the cap
	B.Pick("warrior-protection")
	local function Defense()
		X.DT.UI:Show("bis")
		B.Refresh()
		for _, bar in ipairs(B.gear.caps) do if bar.shown and bar.text.text:find("^Defense") then return bar.sub.text .. " | " .. bar.value.text end end
	end
	check(Defense():find("195/200 +12", 1, true) and Defense():find("207 / 340", 1, true), "defense at my level: " .. tostring(Defense()))
	B.SetLevel(60)
	check(Defense():find("295/300 +12", 1, true) and Defense():find("307 / 440", 1, true), "at another level the skill and the cap go with it: " .. tostring(Defense()))
	B.SetLevel(nil)
	e.UnitDefense = nil; B.db.base = {}; B.Stale(); step(3)
	check(Defense():find("200/200 +0", 1, true) and Defense():find("200 / 340", 1, true), "a client that does not say the skill: what the tab works out: " .. tostring(Defense()))
	leave(X)
	for id in pairs(GEAR) do ITEMS[id] = nil end
end)()
;(function() -- BiS, kept: a second login shows the lists before the item index is read; what it is built from changing throws it away; the keys are capped
	local GEAR = {}
	for i = 1, 6 do GEAR[99800 + i] = { "Kept Helm " .. i, 30 + i, 10 * i } end
	for id, g in pairs(GEAR) do ITEMS[id] = { g[1], 2, 1, 100, false, 4, 2, slot = "INVTYPE_HEAD", lvl = g[2] } end
	local function Globals(env)
		env.UnitLevel = function() return 40 end
		env.GetItemStats = function(link) return { ITEM_MOD_STRENGTH_SHORT = GEAR[tonumber(link:match("item:(%d+)"))][3] } end
		env.C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = ITEMS[id][1] } } } end }
		env.GetNumTalentTabs = function() return 3 end
		env.GetTalentTabInfo = function(i) return "Tab " .. i, "icon", i == 2 and 31 or 5 end
	end
	local walks, reads = 0, 0
	local function Index(X)
		local Item = X.DT.Item
		Item.Start, Item.Ready = function() reads = reads + 1 return false end, function() return true end
		Item.All = function()
			walks = walks + 1
			local list = {}
			for id in pairs(GEAR) do list[#list + 1] = { id = id, req = ITEMS[id].lvl, c = 4, s = 2, src = { ["Quest reward"] = true } } end
			return list
		end
		X.DT.CraftSkill = {}
	end
	local function Look(B) for _ = 1, 400 do B.Sift(); step(0.2) end step(3) end
	-- the first login: the item index is walked, and what was found is kept
	local X = NewClient("BisKept", { globals = Globals })
	local B = X.DT.Bis
	Index(X)
	X.DT.DB.Base("questie", "1.0/1")
	Look(B)
	check(walks > 0 and reads > 0, "the first time the item index is read")
	local kept = B.db.kept
	eq(#kept.order, 1, "what was found is kept under its key"); local entry = kept.keys[kept.order[1]]
	eq(#entry.got, 12, "six items and their kinds")
	check(kept.order[1]:find("^40:WARRIOR"), "by level and class (and phase): " .. kept.order[1])
	leave(X)
	-- the second login: nothing is read, and the slot list is there
	walks, reads = 0, 0
	local saved = X.env.DawnToolsDB
	local Y = NewClient("BisKept2", { globals = Globals, db = saved })
	local B2 = Y.DT.Bis
	Index(Y)
	local asks = 0
	local realAsk = Y.env.C_Item.RequestLoadItemDataByID
	Y.env.C_Item.RequestLoadItemDataByID = function(id) asks = asks + 1 return realAsk(id) end
	Y.DT.UI:Show("bis")
	Look(B2)
	click(B2.gear.slots[1])
	local top = B2.gear.lines[1]
	check(top.item.shown and top.item.id == 99806, "the slot list is shown from what was kept: the best helm first")
	eq(walks, 0, "the item index is not walked"); eq(reads, 0, "nor read"); eq(asks, 0, "and the game is asked for no item")
	check(B2.State().all and #B2.State().all > 0, "the sets have their candidates")
	-- an old list is shown while it is looked at again
	B2.db.kept.keys[B2.db.kept.order[1]].at = -1e9
	B2.Sift(); B2.Refresh()
	eq(B2.gear.lines[1].item.id, 99806, "an old list stays on show while it is looked at again")
	Look(B2); B2.Refresh()
	check(walks > 0, "older than its age: the index is walked again, quietly"); eq(B2.gear.lines[1].item.id, 99806, "and the list is the same after"); check(B2.db.kept.keys[B2.db.kept.order[1]].at ~= -1e9, "and is as new as the look")
	eq(#B2.db.kept.order, 1, "the same finds are the same entry")
	-- what it was built from changed: thrown away
	walks = 0
	Y.DT.DB.Base("questie", "2.0/1")
	B2.Sift()
	eq(next(B2.db.kept.keys), nil, "another QuestieDB: the kept list is gone"); eq(#B2.db.kept.order, 0, "and its keys")
	Look(B2)
	check(walks > 0 and #B2.db.kept.order == 1, "and is made anew from the index")
	B2.db.kept.stamp = "another shape"
	B2.Sift()
	eq(next(B2.db.kept.keys), nil, "another stamp (the shape of the facts, the dungeon list): gone too")
	-- the keys are capped
	for lvl = 1, 10 do
		B2.SetLevel(lvl)
		for _ = 1, 6 do B2.Sift(); step(0.2) end
	end
	local n = 0
	for _ in pairs(B2.db.kept.keys) do n = n + 1 end
	eq(#B2.db.kept.order, 6, "only the last six keys are kept"); eq(n, 6, "and no more entries than keys")
	check(B2.db.kept.order[1]:find("^10:"), "the one looked at last first")
	leave(Y)
	for id in pairs(GEAR) do ITEMS[id] = nil end
end)()
;(function() -- the store: two installs that each learned something end with the same database
	local P, R = NewClient("Pax"), NewClient("Rue")
	local a, b = P.DT.DB, R.DT.DB
	check(a.Origin():find("^%x%x%x%x%x%x$"), "an install has an origin of its own: no name"); eq(a.Origin(), P.env.DawnToolsDB.db.origin, "kept in the saved file")
	eq(a.Put("item:872", "Rockhide Strongfish;35"), true, "a row learned is kept"); eq(a.Put("item:872", "Rockhide Strongfish;35"), false, "the same again changes nothing")
	eq(a.Row("item:872").v, "Rockhide Strongfish;35", "and is found by its key"); eq(a.Row("item:872").src, "guild", "as what the guild learned"); eq(a.Row("item:1"), nil, "one not there: nothing")
	a.Put("npc:9000", "Gar'Thok;12;Durotar")
	a.Put("loot:9000:" .. a.Origin(), P.DT.DBLogic.Counter(4, { [872] = 1 }))
	b.Put("npc:9001", "Old Blanchy")
	b.Put("loot:9000:" .. b.Origin(), R.DT.DBLogic.Counter(6, { [872] = 2 }))
	-- loot: every corpse counted, once, where I see all of it
	local pe = P.env
	local corpses, drop = { "Creature-0-1-2-3-9100-00000A" }, { { 872, 2 }, { 100, 1 } }
	pe.GetNumLootItems = function() return #drop end
	pe.GetLootSourceInfo = function() -- (as the game answers: corpse, how many, corpse, how many, ...)
		local out = {}
		for _, guid in ipairs(corpses) do out[#out + 1], out[#out + 2] = guid, 1 end
		return table.unpack(out)
	end
	pe.GetLootSlotLink = function(slot) return "|cffffffff|Hitem:" .. drop[slot][1] .. "::::|h[x]|h|r" end
	pe.GetLootSlotInfo = function(slot) return "icon", "x", 1, nil, drop[slot][2] end
	P.fire("LOOT_OPENED")
	P.fire("LOOT_READY")
	local n, items = a.Looted("npc", 9100)
	eq(n, 1, "a corpse looted is counted once, however often its window is told of"); eq(items[872], 1, "with what of worth was in it"); eq(items[100], nil, "common things are not noted")
	corpses, drop = { "Creature-0-1-2-3-9100-00000B", "Creature-0-1-2-3-9100-00000C" }, { { 100, 1 } }
	P.fire("LOOT_OPENED")
	n, items = a.Looted("npc", 9100)
	eq(n, 3, "two corpses looted at once are two"); eq(items[872], 1, "with nothing of worth in them")
	corpses, drop = { "GameObject-0-1-2-3-555-00000D" }, { { 872, 3 } }
	P.fire("LOOT_OPENED")
	eq(select(1, a.Looted("object", 555)), 1, "a chest is an object, not a mob"); eq(select(1, a.Looted("npc", 555)), 0, "of the same number")
	pe.IsInGroup, pe.GetLootMethod = function() return true end, function() return "group" end
	corpses = { "Creature-0-1-2-3-9100-00000E" }
	P.fire("LOOT_OPENED")
	eq(select(1, a.Looted("npc", 9100)), 3, "in a group that rolls I do not see all of it: not counted")
	pe.GetLootMethod = function() return "freeforall" end
	P.fire("LOOT_OPENED")
	eq(select(1, a.Looted("npc", 9100)), 4, "with free-for-all loot I do")
	pe.IsInGroup = nil
	local of = a.Rel("drops", "npc", 9100)
	eq(#of, 1, "what a mob drops, as we counted it"); eq(of[1].kind .. of[1].id, "item872", "the item"); eq(of[1].n, 4, "of so many looted"); eq(of[1].k, 2, "seen so often"); eq(of[1].src, "guild", "our own knowledge")
	eq(a.ChanceText(of[1]), "2 of 4 looted (50%)", "said as a chance")
	local who = {}
	for _, fact in ipairs(a.RelTo("drops", "item", 872)) do who[#who + 1] = fact.kind .. fact.id .. ":" .. tostring(fact.n) end
	table.sort(who)
	eq(table.concat(who, ","), "npc644:nil,npc9000:4,npc9100:4,object555:1", "and who drops an item: the dungeon boss the shipped list names, and every mob and object it was seen in")
	check(a.Root() ~= b.Root(), "two installs that know different things: different hashes")
	local function Give(from, to) -- (what the sync will do: only the chunks whose hashes differ change hands)
		local sent = 0
		for _, chunk in ipairs(P.DT.DBLogic.Differ(to.Hashes(), from.Hashes())) do
			if from.Text(chunk) then
				to.Take(chunk, from.Text(chunk))
				sent = sent + 1
			end
		end
		return sent
	end
	check(Give(a, b) > 0 and Give(b, a) > 0, "each gives the other its chunks that differ")
	eq(a.Root(), b.Root(), "and both end with the same hash"); eq(Give(a, b), 0, "after which nothing more changes hands")
	eq(b.Row("npc:9000").v, "Gar'Thok;12;Durotar", "what one learned the other has"); eq(b.Row("npc:9000").src, "guild", "the very same row")
	check(a.Row("loot:9000:" .. b.Origin()) and b.Row("loot:9000:" .. a.Origin()), "counters of both origins are kept side by side: none is counted twice")
	-- my own counter never comes back in from the wire, however new it claims to be
	local forged = ("loot:9000:%s\t%d\town\t%s"):format(a.Origin(), P.DT.Now() + 100, "999;872:999")
	eq(a.Take("loot:35", forged), 0, "a counter of my own origin is not taken from another"); eq(a.Row("loot:9000:" .. a.Origin()).v, "4;872:1", "mine stands")
	eq(a.Take("npc:35", "item:5\t1\town\tfiled in the wrong chunk"), 0, "nor a row that does not belong in the chunk it came in")
	local stats = a.Stats()
	eq(stats.rows, 9, "the store says what it holds (the loot counted, and the item and the chest that were new, written down)"); check(stats.bytes > 0 and stats.chunks >= 3 and stats.root == a.Root(), "rows, chunks, size and hash")
	-- it is there again after a login
	leave(P)
	local P2 = NewClient("Pax", { db = P.env.DawnToolsDB })
	eq(P2.DT.DB.Row("npc:9001").v, "Old Blanchy", "the store is in the saved file"); eq(P2.DT.DB.Root(), b.Root(), "hash and all"); eq(P2.DT.DB.Origin(), a.Origin(), "under the same origin")
	leave(P2)
	leave(R)
end)()
;(function() -- the store's sync: installs that share become the same, by whisper, a chunk at a time
	local first = #sent + 1 -- (members of the checks above shared too: only what is said from here on is counted)
	local function whispers(from)
		local n = 0
		for i = first, #sent do
			local m = sent[i]
			if m.prefix == "DAWND" and (not from or m.from == from) then n = n + 1 end
		end
		return n
	end
	local A1, B1 = NewClient("Ada"), NewClient("Ben")
	local a, b = A1.DT.DB, B1.DT.DB
	a.Put("npc:9000", "Gar'Thok;12;Durotar")
	a.Put("loot:9000:" .. a.Origin(), "4;872:1")
	b.Put("npc:70000", "Old Blanchy")
	b.Put("loot:9000:" .. b.Origin(), "6;872:2")
	step(700)
	eq(whispers(), 0, "sharing not agreed to: not a whisper"); eq(b.Row("npc:9000"), nil, "and nothing taken in")
	check(not sent[#sent].text:find(a.Root(), 1, true), "nor is the store's hash said on the guild channel")
	A1.slash("db")
	eq(A1.popups[#A1.popups], "DAWNTOOLS_SHARE", "/dt db asks, once, whether to share")
	A1.env.StaticPopupDialogs.DAWNTOOLS_SHARE.OnAccept()
	eq(A1.DT.db.settings.share, true, "yes is kept")
	step(700)
	eq(whispers(), 0, "one member alone who shares: still nobody to talk to"); eq(b.Row("npc:9000"), nil, "the other, who does not, takes nothing")
	B1.DT.db.settings.share = true
	step(700)
	eq(a.Root(), b.Root(), "both share: after a round of hellos both hold the same")
	eq(b.Row("npc:9000").v, "Gar'Thok;12;Durotar", "what one found the other has"); eq(a.Row("npc:70000").v, "Old Blanchy", "both ways")
	check(a.Row("loot:9000:" .. b.Origin()) and b.Row("loot:9000:" .. a.Origin()), "counters of both, side by side")
	eq(select(1, a.Looted("npc", 9000)), 10, "which add up: looted ten times between us")
	check(whispers("Ada") > 0 and whispers("Ben") > 0, "by whisper, each to the other")
	for i = first, #sent do
		local m = sent[i]
		if m.prefix == "DAWND" then check(m.distribution == "WHISPER" and not m.text:find("Ada", 1, true) and not m.text:find("Ben", 1, true), "no name in any of it, and none of it on the guild channel") end
	end
	local before = whispers()
	step(1300)
	eq(whispers(), before, "two that hold the same have nothing more to say")
	-- a find reaches someone who was never online with its finder
	leave(A1)
	local C1 = NewClient("Cy")
	C1.DT.db.settings.share = true
	step(700)
	eq(C1.DT.DB.Row("npc:9000").v, "Gar'Thok;12;Durotar", "a newcomer gets from one member what another, now offline, found")
	eq(C1.DT.DB.Root(), b.Root(), "all of it")
	-- only what was asked for is taken
	local forged = "C=" .. LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate("npc:35\nnpc:9000\t" .. (Now() + 50) .. "\tguild\tA lie"))
	C1.hear("DAWND", forged, "WHISPER", "Ben-Forever")
	eq(C1.DT.DB.Row("npc:9000").v, "Gar'Thok;12;Durotar", "a chunk nobody asked for is not taken")
	C1.hear("DAWND", forged, "GUILD", "Ben-Forever")
	eq(C1.DT.DB.Row("npc:9000").v, "Gar'Thok;12;Durotar", "nor one that did not come as a whisper")
	-- in a fight nothing is asked; afterwards it goes on
	b.Put("npc:70001", "Mankrik")
	C1.combat = true
	step(700)
	eq(C1.DT.DB.Row("npc:70001"), nil, "in a fight nothing is asked for")
	C1.combat = false
	step(700)
	eq(C1.DT.DB.Row("npc:70001").v, "Mankrik", "after it, it goes on")
	leave(B1)
	leave(C1)
end)()
;(function() -- Finds: what the game shows is written down where it is not known, and listed under World
	local target, loot, at = nil, {}, { 0.452, 0.601 }
	local source = "Creature-0-1-2-3-5-00000A"
	local X = NewClient("Fay", { globals = function(env)
		env.LibQuestieDB = {
			Npc = { Get = function(id, key) return id == 5 and key == "name" and "Known Wolf" or nil end },
			Item = { Get = function(id, key) return id == 100 and key == "name" and "Copper Bar" or nil end },
			Quest = { Get = function() return nil end }, Object = { Get = function() return nil end },
		}
		local guid, name = env.UnitGUID, env.UnitName
		env.UnitExists = function(unit) return (unit == "target" and target ~= nil) or unit == "npc" end
		env.UnitGUID = function(unit) if unit == "target" then return target and target[1] end return guid(unit) end
		env.UnitName = function(unit) if unit == "target" then return target and target[2] end return name(unit) end
		env.UnitLevel = function(unit) return unit == "target" and 23 or 10 end
		env.GetRealZoneText = function() return "Stonetalon Mountains" end
		env.C_Map = { GetBestMapForUnit = function() return 1 end, GetPlayerMapPosition = function() return { GetXY = function() return at[1], at[2] end } end }
		env.GetNumLootItems = function() return #loot end
		env.GetLootSourceInfo = function() return source, 1 end
		env.GetLootSlotLink = function(slot) return "|cffffffff|Hitem:" .. loot[slot][1] .. "::::|h[" .. loot[slot][2] .. "]|h|r" end
		env.GetLootSlotInfo = function(slot) return "icon", loot[slot][2], 1, nil, 3 end
		env.GetQuestID, env.GetTitleText = function() return 60001 end, function() return "A Runesteel Matter" end
	end })
	local F, D = X.DT.Finds, X.DT.DB
	target = { "Creature-0-1-2-3-5-00000A", "Known Wolf" }
	X.fire("PLAYER_TARGET_CHANGED")
	eq(D.Row("npc:5"), nil, "an NPC QuestieDB knows is not written down")
	target = { "Creature-0-1-2-3-270001-00000B", "Runesteel Sentinel" }
	X.fire("PLAYER_TARGET_CHANGED")
	eq(D.Row("npc:270001").v, "Runesteel Sentinel;23;Stonetalon Mountains;45.2;60.1;m1", "one it does not know is: name, level, the zone, and where I stood")
	local t = D.Row("npc:270001").t
	step(5)
	X.fire("PLAYER_TARGET_CHANGED")
	eq(D.Row("npc:270001").t, t, "once: targeted again it is not written anew")
	target = { "Player-Someone", "Someone" }
	X.fire("PLAYER_TARGET_CHANGED")
	target = { "Pet-0-1-2-3-99-00000C", "Wolf" }
	X.fire("PLAYER_TARGET_CHANGED")
	eq(#F.All(), 1, "players and pets are not written down")
	-- talked to: now I stand at it, and its place is exact
	X.npc, X.npcName, at = "Creature-0-1-2-3-270001-00000B", "Runesteel Sentinel", { 0.47, 0.62 }
	X.fire("GOSSIP_SHOW")
	eq(D.Row("npc:270001").v, "Runesteel Sentinel;10;Stonetalon Mountains;47.0;62.0;1;m1", "talked to: its place is put right, and marked as where it stands")
	check(F.About(F.All()[1]):find("Stonetalon Mountains 47.0, 62.0", 1, true) and not F.About(F.All()[1]):find("afar", 1, true), "said so: " .. F.About(F.All()[1]))
	-- a quest it offers
	X.fire("QUEST_DETAIL")
	eq(D.Row("quest:60001").v, "A Runesteel Matter;270001;Stonetalon Mountains;47.0;62.0;m1", "a quest offered: its title, who gives it, where")
	-- loot: the items, and a chest
	loot = { { 100, "Copper Bar" }, { 275736, "Horn of Vehan" } }
	step(2)
	X.fire("LOOT_OPENED")
	eq(D.Row("item:100"), nil, "an item QuestieDB knows is not written down"); eq(D.Row("item:275736").v, "Horn of Vehan;3", "one it does not know is: name and quality")
	eq(D.Row("object:555"), nil, "a mob's corpse is no object")
	source = "GameObject-0-1-2-3-555-00000D"
	X.fire("LOOT_OPENED")
	eq(D.Row("object:555").v, ";;Stonetalon Mountains;47.0;62.0;1;m1", "a chest looted: its number and where it stands (the game gives no name)")
	-- what I carry, and what the auction house showed
	ITEMS[9300] = { "Odd Trinket", 3, 1, 100, false, 4, 0 }
	X.bags = { 9300, 100 }
	X.fire("BAG_UPDATE_DELAYED")
	X.items()[9301] = { p = 5, q = 1, t = Now(), o = "", d = {}, n = "Auctioned Oddity" }
	F.Sweep()
	check(D.Row("item:9300").v:find("^Odd Trinket;"), "an item in my bags that is not known"); check(D.Row("item:9301").v:find("^Auctioned Oddity;"), "and one seen on the auction house")
	local all = F.All(true)
	eq(#all, 6, "the finds: an NPC, a quest, three items, a chest")
	-- the tab, under World
	local tab
	for _, tb in ipairs(X.DT.UI:TabList(true)) do if tb.id == "world" then tab = tb end end
	local subs = {}
	for _, sub in ipairs(tab.subs) do subs[#subs + 1] = sub.id end
	check(table.concat(subs, ","):find("finds", 1, true), "Finds is a sub-tab of World: " .. table.concat(subs, ","))
	X.DT.UI:Show("finds")
	check(F.note.text:find("6 finds", 1, true), "it says how many: " .. F.note.text)
	local shown = {}
	for _, row in ipairs(F.rows) do if row.shown then shown[#shown + 1] = row.cells[3].text .. " | " .. row.cells[4].text end end
	local text = table.concat(shown, "\n")
	check(text:find("A Runesteel Matter | |cff888888from Runesteel Sentinel, Stonetalon Mountains 47.0, 62.0", 1, true), "a quest with its giver and place: " .. text)
	check(text:find("object 555", 1, true) and text:find("#270001", 1, true), "each with its number")
	-- without QuestieDB everything met is written down (nothing is known), and nothing is called a find
	X.env.LibQuestieDB = nil
	target = { "Creature-0-1-2-3-12-00000E", "Plain Boar" }
	X.fire("PLAYER_TARGET_CHANGED")
	check(D.Row("npc:12").v:find("^Plain Boar;23;"), "without QuestieDB what is met is still written down")
	eq(#F.All(true), 0, "but none of it is called a find"); eq(#F.All(), 7, "it is all in the store")
	F.Refresh()
	check(F.note.text:find("QuestieDB is not installed", 1, true), "and the tab says why")
	ITEMS[9300] = nil
	leave(X)
end)()
;(function() -- base rows: what an installed QuestieDB knows is written into the store, and passes to members without it
	local many, far = {}, {}
	for i = 1, 20 do many[i] = { 30 + i, 40 + i } end
	for i = 1, 60 do far[i] = 1000 + i end
	local NPC = {
		[5] = { name = "Known Wolf", minLevel = 11, maxLevel = 12, rank = 0, zoneID = 17, spawns = { [17] = { { 45.2, 60.14 }, { 1, 2 } } } },
		[300] = { name = "Far Trader", minLevel = 30, maxLevel = 30, rank = 0, zoneID = 0, friendlyToFaction = "AH", subName = "Trade Goods", npcFlags = 4 + 2,
			spawns = { [400] = { { 10, 20 } } }, questStarts = { 102 }, waypoints = { [400] = { { { 1, 1 } } } } },
		[6] = { name = "" },
		[7] = { name = "Roamer", minLevel = 19, maxLevel = 20, zoneID = 17, spawns = { [3] = { { 9, 9 } }, [17] = many } },
	}
	local ITEM = {
		[100] = { name = "Copper Bar", requiredLevel = 0, itemLevel = 10, class = 7, subClass = 7, vendors = { 300 } },
		[872] = { name = "Rockhide Strongfish", requiredLevel = 20, itemLevel = 25, class = 2, subClass = 7, npcDrops = far, questRewards = { 102 }, startQuest = 103 },
	}
	local QUEST = {
		[101] = { name = "First Steps", requiredLevel = 1, questLevel = 5, zoneOrSort = 17, startedBy = { { 5 } } },
		[102] = { name = "A Wolf; Problem", requiredLevel = 8, questLevel = 10, zoneOrSort = 17, startedBy = { { 300 } }, finishedBy = { nil, { 77 } }, preQuestSingle = { 101 },
			nextQuestInChain = 103, requiredSkill = { 185, 50 }, objectivesText = { "Kill 10 wolves, bring \"proof\": 100% of it." } },
		[103] = { name = "Unfiled", requiredLevel = 10, questLevel = 12, zoneOrSort = 0, startedBy = { nil, nil, { 872 } } },
		[104] = { name = "Wordy", requiredLevel = 3, questLevel = 4, zoneOrSort = 17, objectives = { { { 5, "Slay it" } } }, extraObjectives = { { nil, "icon", ("x"):rep(2500) } } },
	}
	QUEST[102].objectives, QUEST[102].reputationReward, QUEST[102].triggerEnd = { { { 5, "Wolf slain" } }, nil, { { 100 } } }, { { 76, 250 } }, { "Reach the cave", { [17] = { { 50, 50 } } } }
	local OBJECT = { [77] = { name = "Copper Vein", zoneID = 17, spawns = { [17] = { { 33.3, 44.4 } } }, questEnds = { 102 } } }
	local AREAS = { [3] = "Badlands", [17] = "The Barrens", [400] = "Thousand Needles" }
	local function questie(env)
		local function entity(data)
			local function Get(id, key) return data[id] and data[id][key] end
			return { GetAllIds = function() local ids = {} for id in pairs(data) do ids[#ids + 1] = id end return ids end, Get = Get,
				GetAll = function(id, keys) local out = {} for i, key in ipairs(keys) do out[i] = Get(id, key) end return data[id] and out end }
		end
		env.LibQuestieDB = { Npc = entity(NPC), Item = entity(ITEM), Quest = entity(QUEST), Object = entity(OBJECT),
			Enum = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4 }, raceMaskById = { [1] = 1, [2] = 2, [10] = 512 } },
			Support = { Get = function(name)
				return name == "QuestXP" and { db = { [102] = { 10, 850 } } } or name == "ZoneDB" and { private = { areaIdToUiMapId = { [17] = 1413, [400] = 1441 } } } or nil
			end } }
		env.C_Map = { GetAreaInfo = function(area) return AREAS[area] end }
		env.GetAddOnMetadata = function(addon, field) return addon == "QuestieDB" and field == "Version" and "1.1.3" or nil end
	end
	local Q1 = NewClient("Quill", { globals = questie })
	local d, DL = Q1.DT.DB, Q1.DT.DBLogic

	-- the values of a row, as one text and back
	local packed = DL.Pack({ 30, nil, "A \"quoted\" 100%, name", { 5, 6, [17] = { { 45.2, 60.1 } }, [-3] = true }, 0.25 }, 5)
	eq(packed, ',,"A %22quoted%22 100%25, name",{5,6,-3:T,17:{{45.2,60.1}}},0.25' and "30" .. packed:sub(3), "values as one text: " .. packed)
	local back = DL.Unpack(packed)
	eq(back[1], 30, "a number comes back"); eq(back[2], nil, "one that was not there is not"); eq(back[3], "A \"quoted\" 100%, name", "a text, whatever is in it")
	eq(back[4][2], 6, "a list in order"); eq(back[4][17][1][2], 60.1, "and what it holds under a number, lists within lists"); eq(back[4][-3], true, "true"); eq(back[5], 0.25, "a fraction")
	eq(DL.Pack(back, 5), packed, "the same values give the same text"); eq(DL.Pack({ 1, nil, nil }, 3), "1", "nothing is written for what is not there at the end")
	eq(DL.Unpack('1,{2,"open'), nil, "a text that is not one is not read"); eq(DL.Unpack("{1,2}}"), nil, "nor one with more in it than values")
	eq(#DL.Unpack(""), 0, "an empty one holds nothing")
	-- which of two rows under one key stands
	local base, sight = { t = 1, src = "questie", v = "a" }, { t = 5000, src = "guild", v = "b" }
	eq(DL.Wins(sight, base, 9999), false, "a sighting, however new, does not replace a source's row"); eq(DL.Wins(base, sight, 9999), true, "a source's row replaces a sighting")
	eq(DL.Wins({ t = 6000, src = "guild", v = "c" }, sight, 9999), true, "of two sightings the newer stands")

	d.Put("npc:5", "Known Wolf;13;The Barrens;50.0;50.0;1") -- (a sighting, from before the import)
	step(30)
	eq(d.Base("questie"), "1.1.3/6", "the import ran, and is marked with the QuestieDB it was of and the shape of its rows")
	eq(d.Row("npc:300").v, 'Far Trader;30,30,0,0,"AH","Trade Goods",6,{400:{{10,20}}},{102},,{400:{{{1,1}}}}', "an NPC: name, levels, rank, zone, side, title, flags, places, the quests it gives, and where it walks")
	eq(d.Row("npc:300").src, "questie", "as QuestieDB's"); eq(d.Row("npc:300").t, 710103060, "of a time that is its version, which every install writes alike")
	eq(d.Row("npc:5").src, "questie", "a sighting of what QuestieDB knows gives way to its row"); eq(d.Row("npc:6"), nil, "a record with no name is left out")
	eq(d.Row("item:100").v, "Copper Bar;0,10,7,7,,,,{300}", "an item with who sells it")
	eq(d.Row("quest:102").v:match("^[^;]*;"), "A Wolf, Problem;", "a name is kept clear of what ends it")
	eq(d.Row("object:77").v, "Copper Vein;17,{17:{{33.3,44.4}}},,{102}", "an object with its place and the quest that ends at it")
	check(#d.Row("quest:104").v <= DL.MAX_VALUE and d.Row("quest:104").v:find('{{{5,"Slay it"}}}', 1, true), "a row too long for the store loses its last fields, not its first: " .. #d.Row("quest:104").v)
	eq(d.Row("zone:17").v, "1413", "the map an area is drawn on"); check(d.Row("enum:npcFlags") and d.Row("enum:raceMaskById"), "and QuestieDB's own small tables")
	eq(#Q1.DT.Finds.All(true), 0, "none of it is a find"); eq(Q1.DT.Finds.Seen("npc", 300, "x"), false, "nor is what it knows written down again when met")
	check(d.Lib() == Q1.env.LibQuestieDB, "where QuestieDB is installed it is what the tabs read")
	local before = d.Root()
	Q1.DT.DBImport.Start()
	eq(Q1.DT.DBImport.Start(), false, "the same QuestieDB is not imported twice"); eq(d.Root(), before, "nothing changes")
	-- another install with the same QuestieDB writes the very same rows
	local Q2 = NewClient("Quinn", { globals = questie })
	step(30)
	eq(Q2.DT.DB.Row("npc:300").v, d.Row("npc:300").v, "a second install imports the same")
	eq(Q2.DT.DB.Hashes()["item:0"], d.Hashes()["item:0"], "to the letter: the same hash, so nothing of it needs passing between them")

	-- a member without QuestieDB: nothing to list, until a guildmate's rows come
	local tom
	local N1 = NewClient("Nell", { globals = function(env)
		env.C_Map = { GetAreaInfo = function(area) return AREAS[area] end }
		env.TomTom = { AddWaypoint = function(_, map, x, y, opts) tom = { map, x, y, opts.title } end }
	end })
	local n, Npc, Quest, Item = N1.DT.DB, N1.DT.Npc, N1.DT.Quest, N1.DT.Item
	N1.DT.db.settings.background = false
	eq(n.Lib(), nil, "without QuestieDB and with an empty store: nothing to read"); eq(n.Row("npc:300"), nil, "no base rows of one's own")
	eq(Npc.Start(), false, "the NPC tab has nothing to read")
	n.Put("npc:5", "Known Wolf;12;The Barrens;1.0;1.0") -- (met before anything was known: written down, as nothing says it is known)
	Q1.DT.db.settings.share, N1.DT.db.settings.share = true, true
	step(700)
	eq(n.Root(), d.Root(), "with the game database shared, a guildmate's rows come: both hold the same")
	eq(n.Row("npc:5").src, "questie", "what was written down of a thing QuestieDB knows gave way to its row")
	eq(d.Row("npc:5").v, Q2.DT.DB.Row("npc:5").v, "and did not write over it on the machine that has QuestieDB")
	eq(n.Take("npc:1", ("npc:300\t%d\tguild\tFar Trader;1;Nowhere"):format(Now())), 0, "nor does a sighting from the wire, however new")
	eq(#N1.DT.Finds.All(true), 0, "they are known there, not finds")
	N1.slash("db")
	check(N1.printed[#N1.printed - 3]:find("base rows", 1, true), "/dt db says where the base rows are from: " .. N1.printed[#N1.printed - 3])

	-- a member who has the source is a referee: a row of its own version that says something else is put right,
	-- and the right one then stands wherever the two meet
	local t0 = d.Row("npc:300").t
	local right = d.Row("npc:300").v
	local wrong = ("npc:300\t%d\tquestie\tZZ Wrong Trader;1"):format(t0)
	-- every chunk of a source has its fingerprint, written by the import and passed on first
	local print = d.Row("fp:questie:npc:1")
	check(print and print.src == "questie" and #print.v == 16, "the import wrote a fingerprint of the chunk's rows"); eq(n.Row("fp:questie:npc:1").v, print.v, "which the member without QuestieDB has too")
	eq(n.Take("npc:1", wrong), 0, "so a member without QuestieDB can tell: rows that do not add up to the fingerprint are not taken"); eq(n.Row("npc:300").v, right, "its own stand")
	check(n.refused == 1, "and it counts what it refused")
	eq(n.Take("npc:1", d.Text("npc:1")), 0, "the whole chunk as the source gives it adds up (nothing new in it here)")
	eq(d.Take("npc:1", wrong), 0, "the machine with QuestieDB refuses it the same way")
	-- where there is no fingerprint (rows of before there were any), the machine that has the source is the referee
	n.Put("fp:questie:npc:1", "lost", "guild", 5)
	d.Put("fp:questie:npc:1", "lost", "guild", 5)
	eq(d.Take("npc:1", wrong), 1, "without a fingerprint a row of the same version that says something else is taken (its text sorts later)")
	eq(d.Row("npc:300").v, right, "but the machine with QuestieDB puts it right by its own QuestieDB"); eq(d.Row("npc:300").t, t0 + 1, "a moment later than the wrong one")
	eq(n.Take("npc:1", wrong), 1, "a member without QuestieDB and without the fingerprint cannot tell, and takes the wrong one")
	step(700)
	eq(n.Row("npc:300").v, right, "until it next meets the referee: the right row is the later one, and stands")
	n.Put("fp:questie:npc:1", print.v, "questie", print.t)
	d.Put("fp:questie:npc:1", print.v, "questie", print.t)
	eq(n.Root(), d.Root(), "both hold the same again")
	eq(n.Take("npc:1", d.Text("npc:1")), 0, "and a row put right still adds up to the fingerprint: it is the values that count, not the moment")
	eq(d.Take("npc:1", ("npc:300\t%d\tquestie\tNewer Trader;1"):format(t0 + 1000)), 1, "a row of a later version is not this machine's to judge: taken as it is")
	check(d.Row("npc:300").v:find("^Newer Trader"), "it stands")
	d.Put("npc:300", right, "questie", t0 + 2000) -- (put back for the checks below)
	step(700)

	-- the store answers as QuestieDB would
	local lib = n.Lib()
	eq(lib.store, true, "the store is read in QuestieDB's place")
	eq(lib.Npc.Get(300, "subName"), "Trade Goods", "one field of an NPC"); eq(lib.Npc.Get(300, "name"), "Far Trader", "its name")
	local all = lib.Npc.GetAll(300, { "name", "maxLevel", "nothing", "npcFlags" })
	eq(all[1] .. all[2] .. tostring(all[3]) .. all[4], "Far Trader30nil6", "several at once, in the order asked"); eq(lib.Npc.GetAll(999, { "name" }), nil, "nothing of an NPC there is not")
	eq(table.concat(lib.Npc.GetAllIds(), ","), "5,7,300", "every NPC's number")
	local spots, others = lib.Npc.Get(7, "spawns"), 0
	for area in pairs(spots) do if area ~= 17 then others = others + 1 end end
	eq(#spots[17], 8, "of many places the first few are kept: those of its own zone first"); eq(others, 0, "and no more than those")
	eq(#lib.Item.Get(872, "npcDrops"), 40, "a long list is cut short"); eq(lib.Item.Get(872, "startQuest"), 103, "a number")
	eq(lib.Quest.Get(102, "startedBy")[1][1], 300, "who gives a quest"); eq(lib.Quest.Get(102, "finishedBy")[1], nil, "whom it goes back to: no NPC")
	eq(lib.Quest.Get(102, "finishedBy")[2][1], 77, "but an object"); eq(lib.Quest.Get(102, "objectivesText")[1], "Kill 10 wolves, bring \"proof\": 100% of it.", "what it asks, to the letter")
	eq(lib.Quest.Get(102, "objectives")[1][1][2], "Wolf slain", "what has to be killed for it"); eq(lib.Quest.Get(102, "objectives")[3][1][1], 100, "and brought, with nothing between left out of place")
	eq(lib.Quest.Get(102, "reputationReward")[1][2], 250, "the reputation it gives"); eq(lib.Quest.Get(102, "triggerEnd")[2][17][1][1], 50, "where it ends"); eq(lib.Object.Get(77, "questEnds")[1], 102, "what ends at an object")
	eq(lib.Npc.Get(300, "waypoints")[400][1][1][1], 1, "where an NPC walks")
	eq(lib.Quest.Get(102, "requiredSkill")[2], 50, "a skill it asks for"); eq(lib.Support.Get("QuestXP").db[102][2], 850, "the experience it gives")
	eq(lib.Enum.npcFlags.VENDOR, 4, "what QuestieDB's flags are called"); eq(lib.Enum.raceMaskById[10], 512, "and which bit a race is")
	eq(lib.Support.Get("ZoneDB").private.areaIdToUiMapId[400], 1441, "the map of an area")
	-- and so does DT.DB
	eq(n.Get("npc", 300).name, "Far Trader", "DT.DB knows the NPC"); eq(n.Name("quest", 101), "First Steps", "and a quest by name")
	local sells = n.RelTo("sells", "item", 100)
	eq(#sells, 1, "who sells an item"); eq(sells[1].id, 300, "the vendor")
	eq(#n.Only(n.RelTo("drops", "item", 872), "npc", "questie"), 40, "who drops one"); eq(n.RelTo("rewards", "item", 872)[1].id, 102, "which quest gives it"); eq(n.Rel("starts", "item", 872)[1].id, 103, "what it starts")

	-- the tabs list it: the NPC tab was told the store has more now, and reads it
	eq(Npc.Start(), true, "the NPC tab reads anew once rows have come")
	while not Npc.Step(8) do end
	local found = Npc.Find("far trader", {})
	eq(#found, 1, "an NPC is found by name, without QuestieDB installed")
	local e = found[1].e
	eq(e.sub, "Trade Goods", "with its title"); eq(e.typeText, "Vendor, Quest giver, Trade goods", "what it is, from its flags and its title"); eq(e.zoneName, "Thousand Needles", "and its zone")
	eq(#Npc.Find("", { types = { Vendor = true } }), 1, "the type filter works")
	Npc.Waypoint(e)
	eq(tom[1], 1441, "a waypoint to it: on the map of its zone"); eq(tom[2], 0.1, "at its place"); eq(tom[4], "Far Trader", "by name")
	-- quests and items too
	Quest.Start()
	while not Quest.Step(8) do end
	local q = Quest.Entry(102)
	eq(q.name, "A Wolf, Problem", "the Quests tab has the quest"); eq(q.zoneName, "The Barrens", "its zone"); eq(q.preAny[1], 101, "and what comes before it")
	check(q.types["In chain"] and q.types.Profession, "its kinds: " .. q.typeText)
	eq(Quest.Origin(q).name, "Far Trader", "who gives it"); eq(Quest.Asks(q), "Kill 10 wolves, bring \"proof\": 100% of it.", "what it asks")
	eq(Quest.Rewards(q).xp, 850, "what it gives")
	Item.Start()
	while not Item.Step(8) do end
	eq(#Item.All(), 2, "the Items tab has the items")
	local fish
	for _, it in ipairs(Item.All()) do if it.id == 872 then fish = it end end
	eq(fish.srcText, "Drop, Quest reward, Starts a quest", "with where each comes from"); eq(Item.rewards[102][1].id, 872, "and what a quest gives")

	-- the Zones tab follows: worked out before the quests' rows changed, it is worked out anew
	local Zone = N1.DT.Zone
	check(Zone.Ensure() and Zone.Get("The Barrens"), "the Zones tab has the zones of the store's NPCs")
	local was = Zone.Get("The Barrens")
	N1.DT:Fire("DT_DB_UPDATE", "npc:0")
	Npc.Start()
	while not Npc.Step(8) do end
	check(Zone.Ensure() and Zone.Get("The Barrens") ~= was, "and works them out anew when the NPCs were read anew")

	-- two members with different versions of QuestieDB: the later one's rows stand, on both machines
	local Q3 = NewClient("Quentin", { globals = function(env)
		questie(env)
		local get = env.LibQuestieDB.Npc.Get
		env.LibQuestieDB.Npc.Get = function(id, key) if id == 300 and key == "name" then return "Old Trader" end return get(id, key) end
		env.GetAddOnMetadata = function(addon, field) return addon == "QuestieDB" and field == "Version" and "1.1.2" or nil end
	end })
	step(30)
	check(Q3.DT.DB.Row("npc:300").v:find("^Old Trader;"), "an older QuestieDB says something else of an NPC"); check(Q3.DT.DB.Row("npc:300").t < d.Row("npc:300").t, "and its rows are marked as older")
	Q3.DT.db.settings.share = true
	step(700)
	check(Q3.DT.DB.Row("npc:300").v:find("^Far Trader;"), "shared: the member with the older QuestieDB has the later one's row"); check(d.Row("npc:300").v:find("^Far Trader;"), "and the later one's did not give way")
	Q3.DT.DB.Base("questie", "something else")
	Q3.DT.DBImport.Start()
	while not Q3.DT.DBImport.Step(50) do end
	check(Q3.DT.DB.Row("npc:300").v:find("^Far Trader;"), "nor does importing the older QuestieDB again write over it")
	leave(Q3)

	-- what the guild met itself stands beside it: an NPC written down in play is listed, and can be gone to
	n.Put("npc:270001", "Runesteel Sentinel;23;Stonetalon Mountains;45.2;60.1;1;m77")
	N1.DT:Fire("DT_DB_UPDATE")
	Npc.Start()
	while not Npc.Step(8) do end
	found = Npc.Find("runesteel", {})
	eq(#found, 1, "an NPC the guild met and QuestieDB does not know is in the NPC tab"); eq(found[1].e.zoneName, "Stonetalon Mountains", "with the zone it was met in"); eq(found[1].e.max, 23, "and its level")
	Npc.Waypoint(found[1].e)
	eq(tom[1], 77, "a waypoint to where it was met: the map noted with it"); eq(tom[2], 0.452, "and the place")
	-- a click on a find sets the waypoint too
	N1.DT.UI:Show("finds")
	local row
	for _, r in ipairs(N1.DT.Finds.rows) do if r.shown and r.find and r.find.id == 270001 then row = r end end
	check(row, "the find is listed under World > Finds")
	tom = nil
	row.scripts.OnClick(row, "LeftButton")
	eq(tom and tom[4], "Runesteel Sentinel", "and a click on it is a waypoint")
	leave(Q1) leave(Q2) leave(N1)
end)()
;(function() -- the seed: recipes, vendor prices and dungeons are not in the addon; they are rows of the store, written on a machine that has the seed and passed on by the guild
	local function seed(env)
		env.DawnToolsSeed = {
			SkillUpVersion = "v9", OneForAllVersion = "7.0",
			Recipes = { [7934] = { 129, 80, 80, 115, 150, 0, 6452, 3, { 1475, 1 } }, [7418] = { 333, 1, 70, 90, 110, 0, 0, 1, { 10940, 1, 10938, 2 } },
				[100001] = { 164, 50, 60, 70, 80, 9, 6452, 1.5, {} } },
			VendorPrice = { [2678] = 2 },
			Dungeons = { { "Hall of Tests", 13, 20, { { "First Boss", 9001, 0, { 872, 3.9, 873, 0 } }, { "Trash", 0, 0, { 874, 0 } } } },
				{ "Deep \"Quote\" Mine", 30, 35, { { "Rare One", 9002, 1, { 875, 12.5 } } } } },
		}
	end
	local S1 = NewClient("Sid", { globals = seed, noData = true })
	local d, T = S1.DT.DB, S1.DT
	eq(d.Row("recipe:7934").v, "129,80,80,115,150,0,6452,3,{1475,1}", "a recipe of the seed is a row of the store"); eq(d.Row("recipe:7934").src, "skillup", "of its source"); eq(d.Row("recipe:7934").t, 790000040, "as a base row, of a time that is its version")
	eq(d.Row("vprice:2678").v, "2", "what a vendor asks"); eq(d.Row("boss:2").v, '"Hall of Tests",13,20,"Trash",0,0,{874,0}', "a boss with its dungeon and what it drops")
	eq(d.Row("boss:3").src, "oneforall", "of its source"); eq(d.Base("skillup"), "v9/4", "marked with the version it was of"); eq(d.Row("base:oneforall").v, "7.0;3", "which the rows say too, and how many bosses there are")
	eq(T.DBSeed.Seed(), false, "the same seed is not written twice")
	-- the tables the tabs read are put together from the rows
	eq(T.Recipes[7934][9][1], 1475, "a recipe as the tabs read it, reagents and all"); eq(T.Recipes[100001][8], 1.5, "how many it makes")
	eq(table.concat(T.CraftSkill[6452], ","), "164,50,60,70,80,9", "for an item the band of the recipe that turns yellow soonest"); eq(T.CraftSkill[0], nil, "an enchantment makes no item")
	eq(T.VendorPrice[2678], 2, "a vendor's price"); eq(#T.Dungeons, 2, "the dungeons"); eq(T.Dungeons[1][1], "Hall of Tests", "in their order"); eq(#T.Dungeons[1][4], 2, "each with its bosses")
	eq(T.Dungeons[2][1], "Deep \"Quote\" Mine", "a name with anything in it"); eq(T.Dungeons[2][4][1][4][2], 12.5, "a drop chance"); eq(T.Dungeons[2][4][1][3], 1, "a rare")
	eq(T.Dungeon.DropOf(872).name, "First Boss", "the Dungeons tab knows who drops what"); eq(T.Craft.ByItem(6452), 100001, "and the profession tabs which recipe makes an item")
	S1.slash("db")
	check(S1.printed[#S1.printed - 2]:find("3 recipes and 1 vendor prices (SkillUp Forever v9), 3 bosses (OneForAll 7.0); this machine has the seed", 1, true), "/dt db says what is held: " .. S1.printed[#S1.printed - 2])
	-- a newcomer asks every member who holds it, and none of them for what another is sending or has sent
	;(function()
		local function big(env)
			seed(env)
			for i = 1, 60 do env.DawnToolsSeed.Recipes[1000 + i * 300] = { 129, 1, 2, 3, 4, 0, 5000 + i, 1, {} } end
		end
		local H1 = NewClient("Hal", { globals = big, noData = true })
		local H2 = NewClient("Hedda", { globals = big, noData = true })
		eq(H1.DT.DB.Root(), H2.DT.DB.Root(), "two machines with the same seed hold the same")
		local chunks = 0
		for _ in pairs(H1.DT.DB.Hashes()) do chunks = chunks + 1 end
		local N2 = NewClient("Nia", { noData = true })
		H1.DT.db.settings.share, H2.DT.db.settings.share, N2.DT.db.settings.share = true, true, true
		local before = #sent
		step(1400)
		eq(N2.DT.DB.Root(), H1.DT.DB.Root(), "the newcomer has it all")
		local asked = { Hal = 0, Hedda = 0 }
		for i = before + 1, #sent do
			local m = sent[i]
			if m.prefix == "DAWND" and m.from == "Nia" and m.text:sub(1, 2) == "C?" then
				for _, other in ipairs(clients) do if other.wire == m.to then asked[other.name] = asked[other.name] + 1 end end
			end
		end
		eq(asked.Hal + asked.Hedda, chunks, ("each chunk was asked for once, of one member or the other (%d of Hal, %d of Hedda)"):format(asked.Hal, asked.Hedda))
		check(asked.Hal > 0 and asked.Hedda > 0, ("and both were asked: %d of Hal, %d of Hedda"):format(asked.Hal, asked.Hedda))
		leave(H1) leave(H2) leave(N2)
	end)()
	-- a new member starts with none of it
	local M1 = NewClient("Mo", { noData = true })
	local m = M1.DT
	eq(m.Recipes, nil, "a member without the seed has no recipes"); eq(#m.Dungeon.All(), 0, "and no dungeons"); eq(m.Craft.ByItem(6452), nil, "nothing is made of anything")
	step(10)
	eq(M1.popups[#M1.popups], "DAWNTOOLS_SHARE", "and is asked, a little after login, whether to share the game database: that is how it comes")
	M1.DT.UI:Show("dungeon")
	local said
	for _, w in ipairs(M1.widgets) do if w.kind == "FontString" and type(w.text) == "string" and w.text:find("No dungeons known yet", 1, true) then said = w.text end end
	check(said and said:find("/dt db", 1, true), "the Dungeons tab says where they come from")
	-- with the game database shared it comes from the guild
	S1.DT.db.settings.share, M1.DT.db.settings.share = true, true
	step(700)
	eq(m.DB.Root(), d.Root(), "shared: both hold the same")
	eq(m.Recipes[7934][7], 6452, "the member has the recipes"); eq(m.VendorPrice[2678], 2, "the prices"); eq(m.Dungeons[2][4][1][1], "Rare One", "and the dungeons")
	eq(m.Dungeon.DropOf(875).name, "Rare One", "the Dungeons tab lists them at once"); eq(m.Craft.ByItem(6452), 100001, "the profession tabs too")
	m.DBSeed.Rebuild()
	eq(m.DBSeed.counts.boss, 3, "and can say how much it holds")
	-- a third member gets it from the second: the one with the seed need not be online
	leave(S1)
	local M2 = NewClient("Mia", { noData = true })
	M2.DT.db.settings.share = true
	step(700)
	eq(M2.DT.Recipes and M2.DT.Recipes[7418][1], 333, "a member passes on what came from the seed")
	-- rows that are not of the shape are not believed
	local bad = ("recipe:5\t1\tskillup\t1,2,\"x\"\nrecipe:6\t1\tskillup\t{{{\nrecipe:8\t%d\tguild\t129,80,80,115,150,0,6452,3,{1475,1}"):format(Now())
	check(M2.DT.DB.Take("recipe:0", bad) > 0, "rows of any shape may come over the wire")
	M2.DT.DBSeed.Rebuild()
	eq(M2.DT.Recipes[5], nil, "one that is no recipe is left out"); eq(M2.DT.Recipes[6], nil, "one that is no text of values too"); eq(M2.DT.Recipes[8], nil, "and one that is no base row")
	eq(M2.DT.Recipes[7934][3], 80, "the good ones stand")
	-- a newer seed replaces the rows
	leave(M1) leave(M2)
	local S2 = NewClient("Sid", { db = S1.env.DawnToolsDB, noData = true, globals = function(env)
		seed(env)
		env.DawnToolsSeed.SkillUpVersion, env.DawnToolsSeed.Recipes[7934][3] = "v10", 85
		env.DawnToolsSeed.OneForAllVersion, env.DawnToolsSeed.Dungeons[2] = "7.1", nil
	end })
	eq(S2.DT.Recipes[7934][3], 85, "a newer seed: its values replace the old"); eq(#S2.DT.Dungeons, 1, "and a shorter list of bosses leaves none of the old behind")
	leave(S2)
end)()
;(function() -- the stores of before move into the game database: once, from a saved file of today's shape, losing nothing and counting nothing twice
	local now = Now()
	local DL = assert(loadfile(DIR .. "Core/DBLogic.lua"))()
	local function allRows(DT)
		local out = {}
		for chunk in pairs(DT.DB.Hashes()) do
			for key, row in pairs(DL.Parse(DT.DB.Text(chunk))) do out[key] = row end
		end
		return out
	end
	local counted = "loot:644:1a2b3c\t" .. (now - 20) .. "\tguild\t5;872:1" -- (what DB.Loot counted of the first boss, since 0.44)
	local saved = {
		db = { v = 1, origin = "1a2b3c", chunks = { ["loot:2"] = counted }, hash = { ["loot:2"] = DL.Hash(counted) } },
		dungeon = { picked = "deadmines", seen = { [644] = { k = 4, t = now - 50, items = { [872] = 3, [7777] = 1 } }, [645] = { k = 0 },
				["ruinsoflordaeron/lordaeroncaptain"] = { k = 2, t = now - 5, items = { [6641] = 5 } } },
			guild = { Dana = { [644] = { k = 9, t = now, items = { [872] = 9 } } } }, peers = { Dana = now }, listPeers = { Dana = now },
			adds = { [644] = { t = now, line = "644;The Deadmines;17;26;Rhahk'Zor;644;0;888001:7.5" } }, more = { [888500] = { t = now, line = "x" } } },
		quest = { seen = { [501] = { m = 250, x = 900, l = 12, t = now - 100, r = { { 6001, 1 } }, c = { { 6002, 1 }, { 6003, 5 } } },
				[502] = { m = 0, x = 40, l = 12, t = now - 100, g = now, r = {}, c = {} }, [503] = { m = 1, x = 1, l = 200, r = {}, c = {} } }, rpeers = { Quinn = now } },
		market = { vendors = { [7001] = { p = 40, v = "Grimtak", z = "Razor Hill, Durotar", l = true, t = now - 1000 },
				[7002] = { p = 5, v = "Hon|cffff0000est Hal", z = "Here", t = now - 1000, r = now }, [7003] = { p = 0, v = "Nobody", z = "Nowhere" } }, vpeers = { Vera = now } },
		fish = { catches = { ["Testwater, Pier"] = { casts = 20, items = { [6359] = 40, [600] = 20 }, skill = 140 }, ["Elwynn Forest"] = { casts = 3, items = { [6291] = 3 } } } },
	}
	local X = NewClient("Mig", { db = saved })
	local T, d = X.DT, X.DT.DB
	-- dungeon loot: the larger of the tab's count and the store's, not the sum
	local n, items = d.Looted("npc", 644)
	eq(n, 5, "a boss the tab counted 4 times and DB.Loot 5: 5, not 9"); eq(items[872], 3, "an item: the larger of the two"); eq(items[7777], 1, "one only the tab saw")
	local n2, items2 = d.Looted("boss", "ruinsoflordaeron/lordaeroncaptain")
	eq(n2, 2, "a boss with no NPC number has a home of its own"); eq(items2[6641], 2, "an item is never seen more often than the boss was looted")
	eq(d.Row("loot:645:1a2b3c"), nil, "a boss never looted is not written"); eq(d.Row("loot:644:1a2b3c").src, "guild", "the rows are of what the guild learned, under this install's origin")
	for _, key in ipairs({ "seen", "guild", "peers", "listPeers", "adds", "more" }) do eq(saved.dungeon[key], nil, "the tab's saved " .. key .. " is gone") end
	eq(saved.dungeon.picked, "deadmines", "what is of the tab's set-up stays"); eq(saved.dungeon.moved, true, "and the move is marked")
	eq((T.Dungeon.Seen({ npc = 644, key = 644 })), 5, "the tab reads the store")
	-- quest rewards
	local q = T.Quest.SeenAll()
	eq(q[501].m, 250, "a quest's money"); eq(q[501].x, 900, "its experience"); eq(q[501].l, 12, "the level it was seen at"); eq(q[501].c[2][2], 5, "what there is to choose from, and how many"); eq(d.Row("qreward:501").t, now - 100, "of the time it was seen")
	eq(q[502].x, 40, "one that came from the guild is a row like the others"); eq(d.Row("qreward:503"), nil, "a level that cannot be is not written")
	eq(saved.quest.seen, nil, "the saved table is gone"); eq(saved.quest.rpeers, nil, "and its peers")
	-- vendor prices
	local v = d.Vendor(7001)
	eq(v.p, 40, "a vendor's price"); eq(v.v, "Grimtak", "the vendor"); eq(v.z, "Razor Hill, Durotar", "the place"); eq(v.l, true, "limited stock"); eq(v.t, now - 1000, "the time it was seen")
	eq(d.Vendor(7002).v, "Honcffff0000est Hal", "a name has no colour code in it"); eq(d.Row("vendor:7003"), nil, "a price of nothing is not written")
	eq(select(1, X.env.DawnMarket.API.GetVendor(7001)), 40, "the Market's API answers from the store"); eq(saved.market.vendors, nil, "the saved table is gone"); eq(saved.market.vpeers, nil, "and its peers")
	-- fishing catches
	local pier, elwynn = T.Fish.Catches()["Testwater, Pier"], T.Fish.Catches()["Elwynn Forest"]
	eq(pier.casts, 20, "twenty casts"); eq(pier.mine, 20, "all mine"); eq(pier.items[6359], 40, "what was caught"); eq(pier.skill, 140, "at what skill"); eq(elwynn.casts, 3, "a spot of few casts too")
	check(d.Row(T.Fish.Key("Testwater, Pier")), "a counter under this install's origin"); eq(saved.fish.catches, nil, "the saved table is gone")
	-- nothing of a player in any row
	for key, row in pairs(allRows(T)) do
		check(not (key .. row.v):find("Dana", 1, true) and not (key .. row.v):find("Quinn", 1, true) and not (key .. row.v):find("Vera", 1, true), "no player's name in " .. key)
	end
	-- run again on the same tables (a half-moved file): nothing is lost, nothing is counted twice
	local root = d.Root()
	T.Dungeon.Migrate({ seen = { [644] = { k = 4, items = { [872] = 3, [7777] = 1 } }, ["ruinsoflordaeron/lordaeroncaptain"] = { k = 2, items = { [6641] = 5 } } } })
	T.Quest.Migrate({ seen = { [501] = { m = 250, x = 900, l = 12, t = now - 100, r = { { 6001, 1 } }, c = { { 6002, 1 }, { 6003, 5 } } } } })
	T.Fish.Migrate({ catches = { ["Testwater, Pier"] = { casts = 20, items = { [6359] = 40, [600] = 20 }, skill = 140 } } })
	T.Market.MigrateVendors({ vendors = { [7001] = { p = 40, v = "Grimtak", z = "Razor Hill, Durotar", l = true, t = now - 1000 } } })
	eq(d.Root(), root, "the same again changes nothing")
	-- a newer row stands over an older one of the old table; a bigger count stands over a smaller
	d.Put("qreward:501", DL.Pack({ 300, 950, 14, {}, {} }, 5), "guild", now - 10)
	T.Quest.Migrate({ seen = { [501] = { m = 250, x = 900, l = 12, t = now - 100, r = {}, c = {} } } })
	eq(T.Quest.SeenAll()[501].m, 300, "a quest seen since stands over the old table's")
	T.Fish.Migrate({ catches = { ["Testwater, Pier"] = { casts = 25, items = { [6359] = 10 } } } })
	eq(T.Fish.Catches()["Testwater, Pier"].casts, 25, "a larger count of casts is taken"); eq(T.Fish.Catches()["Testwater, Pier"].items[6359], 40, "an item keeps the larger of its two")
	leave(X)
	-- fishing: the guild's counters are summed, and the tab says whose they are
	local function fisher(name)
		local c = NewClient(name, { globals = function(env)
			env.IsFishingLoot = function() return true end
			env.GetRealZoneText = function() return "Shared Cove" end
			env.GetSubZoneText = function() return "" end
			env.GetNumLootItems = function() return 1 end
			env.GetLootSlotLink = function() return "|Hitem:6359::|h[Firefin Snapper]|h" end
			env.GetLootSlotInfo = function() return nil, "x", 1 end
		end })
		c.DT.db.settings.share = true
		return c
	end
	local F1, F2 = fisher("Finn"), fisher("Fia")
	local function cast(c, times)
		for _ = 1, times do
			c.fire("LOOT_READY")
			c.fire("LOOT_CLOSED")
		end
	end
	cast(F1, 3)
	cast(F2, 2)
	local function cove(c)
		for _, s in ipairs(c.DT.Fish.Spots()) do if s.name == "Shared Cove" then return s end end
	end
	eq(cove(F1).casts, 3, "alone, a member's own casts"); eq(cove(F1).mine, 3, "all of them mine")
	step(700)
	eq(cove(F1).casts, 5, "shared: every member's casts are added up"); eq(cove(F1).mine, 3, "mine are still mine"); eq(cove(F2).casts, 5, "on both machines"); eq(cove(F2).mine, 2, "each with its own")
	eq(F2.DT.Fish.Catches()["Shared Cove"].items[6359], 5, "and what was caught"); eq(F1.DT.DB.Root(), F2.DT.DB.Root(), "both hold the same")
	for key, row in pairs(allRows(F1.DT)) do
		check(not (key .. row.v):find("Finn", 1, true) and not (key .. row.v):find("Fia", 1, true), "no player's name in " .. key)
	end
	cast(F2, 15)
	step(700)
	eq(cove(F1).casts, 20, "from twenty casts of the guild's the spot's own numbers stand over the guess")
	eq(F1.DT.modules.fish.hello, nil, "the module has nothing to say on the guild channel"); eq(F1.DT.Comms:Totals().mods.fish, nil, "and nothing counted of its own")
	leave(F1)
	leave(F2)
end)()
print(("ok: %d checks passed"):format(checks))
