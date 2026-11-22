-- The enchants and consumables BiS weighs at the last level, by hand: item and spell numbers only. What each
-- gives is read from the game (its "Use:" line, its spell's text), so a server's own numbers count.
-- Only what may be bought or made: no raid or reputation enchants, no world buffs (Forever has none in raids).
-- items = { { item number, group: one of each group is taken } }
-- enchants = { { spell number, slot: Back, Chest, Wrist, Hands, Feet, Weapon (any), Weapon2h, Shield } }
local _, DT = ...
DT.BisExtras = {
	items = {
		{ 13510, "flask" }, { 13511, "flask" }, { 13512, "flask" }, -- Titans, Distilled Wisdom, Supreme Power
		{ 13452, "agility" }, { 9187, "agility" }, -- Elixir of the Mongoose, of Greater Agility
		{ 9206, "strength" }, { 12451, "strength" }, { 13453, "strength" }, -- Elixir of Giants, Juju Power, Elixir of Brute Force
		{ 12460, "attack" }, { 12820, "attack" }, -- Juju Might, Winterfall Firewater
		{ 13445, "armor" }, -- Elixir of Superior Defense
		{ 3825, "health" }, -- Elixir of Fortitude
		{ 13454, "spell" }, { 9264, "shadow" }, { 21546, "fire" }, { 17708, "frost" }, -- Greater Arcane, Shadow Power, Greater Firepower, Frost Power
		{ 9179, "intellect" }, { 13447, "intellect" }, -- Elixir of Greater Intellect, of the Sages
		{ 20007, "mana" }, -- Mageblood Potion
		{ 21151, "drink" }, -- Rumsey Rum Black Label
		{ 8410, "scroll" }, { 8412, "scroll" }, { 8411, "scroll" }, { 8423, "scroll" }, { 8424, "scroll" }, -- R.O.I.D.S., Ground Scorpok Assay, Lung Juice Cocktail, Cerebral Cortex Compound, Gizzard Gum
		{ 21023, "food" }, { 13928, "food" }, { 20452, "food" }, { 13931, "food" }, { 18254, "food" }, { 21217, "food" }, { 12218, "food" },
		-- (Dirge's Chimaerok Chops, Grilled Squid, Smoked Desert Dumplings, Nightfin Soup, Runn Tum Tuber Surprise, Sagefish Delight, Monster Omelet)
	},
	enchants = {
		{ 20015, "Back" }, { 13882, "Back" }, -- Superior Defense, Lesser Agility
		{ 20025, "Chest" }, { 20026, "Chest" }, -- Greater Stats, Major Health
		{ 20010, "Wrist" }, { 20011, "Wrist" }, { 23802, "Wrist" }, { 23801, "Wrist" }, { 20008, "Wrist" }, -- Superior Strength, Superior Stamina, Healing Power, Mana Regeneration, Greater Intellect
		{ 20013, "Hands" }, { 20012, "Hands" }, -- Greater Strength, Greater Agility
		{ 20020, "Feet" }, { 20023, "Feet" }, { 20024, "Feet" }, -- Greater Stamina, Greater Agility, Spirit
		{ 23799, "Weapon" }, { 23800, "Weapon" }, { 22749, "Weapon" }, { 22750, "Weapon" }, { 23804, "Weapon" }, { 23803, "Weapon" }, -- Strength, Agility, Spell Power, Healing Power, Mighty Intellect, Mighty Spirit
		{ 20035, "Weapon2h" }, { 20036, "Weapon2h" }, -- Major Spirit, Major Intellect
		{ 20017, "Shield" }, { 20016, "Shield" }, -- Greater Stamina, Superior Spirit
	},
}
