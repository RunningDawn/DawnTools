-- Pre-raid gear worth looking at, by profile (see Data/BisProfiles.lua): item numbers and where each is from.
-- Nothing else is kept of an item: its name and stats are asked of the game, and which of these make the best
-- set is worked out from those (Modules/Bis.lua), so a number here that is not the best is harmless.
-- Written by hand for DawnTools. Where a dungeon boss of the dungeon list (DT.Dungeons) drops the item, the tab names that
-- boss; the word here is what is shown otherwise.
-- ponytail: Protection warrior only, level 60 dungeons, crafting and quests. Another spec: a list under its id.
local _, DT = ...
local D, C, Q, W = "dungeon drop", "crafted", "quest", "world drop"
DT.BisLists = {
	["warrior-protection"] = {
		-- head
		[12952] = D, [11746] = D, [16731] = D, [12620] = C, [13073] = W,
		-- neck
		[13091] = W, [15411] = Q, [13177] = D, [11933] = D,
		-- shoulder
		[14552] = W, [16733] = D, [12557] = D,
		-- back
		[13397] = D, [18413] = C,
		-- chest
		[14624] = D, [16730] = D, [12618] = C, [11926] = D, [18503] = D,
		-- wrist
		[16735] = D, [12936] = D, [12550] = D, [18754] = D,
		-- hands
		[14622] = D, [13072] = W, [16737] = D,
		-- waist
		[14620] = D, [16736] = D, [13142] = D, [13502] = D,
		-- legs
		[14623] = D, [16732] = D, [11927] = D, [13498] = D,
		-- feet
		[14621] = D, [16734] = D, [13381] = D, [18521] = D,
		-- rings
		[11669] = D, [18522] = D, [2246] = W, [12548] = Q, [13098] = D, [17713] = D, [10795] = D,
		-- trinkets
		[17774] = Q, [11810] = D, [11811] = C, [18370] = D, [13966] = Q, [13965] = Q, [11815] = D,
		-- one-hand weapons
		[18348] = Q, [15806] = Q, [12940] = D, [11684] = D, [13361] = D, [12798] = C, [11784] = D, [12621] = D,
		-- shields
		[12602] = D, [22336] = Q, [18499] = D, [13243] = D,
		-- ranged
		[18323] = D, [12651] = D, [13380] = D,
	},
}
