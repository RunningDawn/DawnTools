-- DawnTools :: Changelog
-- What changed, newest first. Shown on the Home tab. A new entry goes on top with every version.
-- Short lines, changes only: what a player would notice. Small fixes of one version share its entry.
-- { version, date, { lines } }

local _, DT = ...

DT.CHANGELOG = {
	{ "0.15.2", "2026-11-14", {
		"A click on the window brings it in front of other addon windows.",
	} },
	{ "0.15.1", "2026-11-14", {
		"DawnTools is now free software under the GPL (version 3 or later).",
	} },
	{ "0.15.0", "2026-11-14", {
		"Tools: Silencer. First box quiets your character's \"That ability isn't ready yet\" voice.",
	} },
	{ "0.14.0", "2026-11-14", {
		"Quests: a zone is green in the zone list once all its quests are done.",
	} },
	{ "0.13.1", "2026-11-14", {
		"World tabs need only QuestieDB now; Questie itself is optional (it adds dungeon entrances).",
	} },
	{ "0.13.0", "2026-11-14", {
		"Quests: money, items (given or choose one) and XP are learnt whenever a quest giver shows a quest.",
	} },
	{ "0.12.0", "2026-11-14", {
		"Quests: a click also shows the rewards: XP, money, and each item with what a vendor pays.",
	} },
	{ "0.11.1", "2026-11-14", {
		"/dt logtest: shows whether the Combat Log chat tab can be read (a test for kill recaps).",
	} },
	{ "0.11.0", "2026-11-14", {
		"Combat: level, race, class, rank and honor of the player, in the window and the row's tooltip.",
	} },
	{ "0.10.1", "2026-11-14", {
		"Combat: a kill's window says the server hides its hits, instead of \"nothing was recorded\".",
	} },
	{ "0.10.0", "2026-11-14", {
		"Combat: the guild of who killed you / who you killed, after the name. Search finds it too.",
	} },
	{ "0.9.3", "2026-11-14", {
		"Guild sharing starts even if something else fails at login.",
		"/dt sync also shows sends that failed with an error.",
	} },
	{ "0.9.1", "2026-11-14", {
		"Price columns widened for coin icons.",
	} },
	{ "0.9.0", "2026-11-14", {
		"Prices with coin icons (General: can be switched off).",
		"Tooltip: hold Shift over a stack for the price of all of it.",
		"Minimap button: our own, centred the same for everyone.",
		"MP5: only your own spells start the count; the sub-tab says what started it.",
		"/dt sync: shows what guild messages go out and come in.",
	} },
	{ "0.8.6", "2026-11-13", {
		"MP5: unlocked, it stands still for placing instead of counting round.",
	} },
	{ "0.8.5", "2026-11-13", {
		"Minimap button: icon centred whatever other addons are installed.",
	} },
	{ "0.8.4", "2026-11-13", {
		"Combat: PvP kills and deaths are now recorded on Forever. Players only; mobs are left out.",
	} },
	{ "0.8.1", "2026-11-13", {
		"Tracker: hotkey macro fixed; it follows the name.",
	} },
	{ "0.8.0", "2026-11-13", {
		"Windows close in combat.",
		"Zones: item tooltips on drops and fish.",
		"Quests: exclusive quests, passed steps and breadcrumbs shown right.",
		"Items: no endless \"learning\"; faster lists.",
		"Zones, NPCs: dungeon mobs no longer placed on the map.",
		"Profiles: import cannot switch on guild sharing.",
	} },
	{ "0.7.0", "2026-11-13", {
		"World: Zones. Levels, side, quests, dungeons, rares, fish, herbs, ore, best drops.",
		"Zones: side filter, Show dungeons, Map button.",
		"Waypoints: dungeon mobs point to the dungeon's door.",
		"Items: Usable checks skill needed and recipes already known.",
		"Tracker: \"DT Tracker\" macro in /macro, wolf icon.",
	} },
	{ "0.6.0", "2026-11-13", {
		"World: Items. Search by category, level, quality, source and stats (sta>11).",
	} },
	{ "0.5.0", "2026-11-13", {
		"Settings in sections.",
		"Profiles, with export and import.",
		"NPCs and quests read in the background after login.",
	} },
	{ "0.4.0", "2026-11-13", {
		"Home tab.",
		"Tracker: hotkey macro; tooltip can be switched off; attack goes on in a fight.",
	} },
	{ "0.3.0", "2026-11-13", {
		"Tools: Tracker. Targets a name and pings it.",
	} },
	{ "0.2.0", "2026-11-13", {
		"World tab: NPCs and Quests, with waypoints and quest chains.",
		"Craft tab: Fish and Food.",
		"Tools tab: Range and MP5.",
		"Market: full scan; gear recorded; better Usable filter.",
		"Inventory: character picker, totals over all characters.",
		"Fish: gold per hour, best catch per spot.",
	} },
	{ "0.1.0", "2026-11", {
		"First version: Market, Inventory, Fish, Food, Combat.",
	} },
}
