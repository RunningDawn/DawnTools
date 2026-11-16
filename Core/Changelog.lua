-- DawnTools :: Changelog
-- What changed, newest first. Shown on the Home tab. A new entry goes on top with every version.
-- Short lines, changes only: what a player would notice. Small fixes of one version share its entry.
-- { version, date, { lines } }

local _, DT = ...

DT.CHANGELOG = {
	{ "0.32.0", "2026-11-16", {
		"Food: a \"Where to get it\" column for the recipe: the vendor (with the price where known), the mob that drops it, or the quest. Click it for a waypoint; Shift-click for all its sources.",
	} },
	{ "0.31.1", "2026-11-16", {
		"Quests: a quest \"shut by\" its twin that you already did now counts as done (\"done as: ...\"), so its chain no longer looks blocked. One shut while you carry its twin is left out by \"Mine only\".",
	} },
	{ "0.31.0", "2026-11-16", {
		"Quests: \"In log only\" shows just the quests in your log, each with the rest of its chain.",
	} },
	{ "0.30.0", "2026-11-16", {
		"Items, and reward items in the quest window: hold Shift over one to compare it with what you wear.",
	} },
	{ "0.29.3", "2026-11-16", {
		"Quests: reward items in the quest window have their icon, show their tooltip on hover, and link with Shift-click (Shift-right-click: web page).",
		"Fixed: a quest clicked while the quest window was open opened it behind the main window.",
	} },
	{ "0.29.2", "2026-11-16", {
		"Items and Quests: Shift-click a row to put its link in chat; Shift-right-click for its web page.",
	} },
	{ "0.29.1", "2026-11-16", {
		"Quests: a dungeon's chain is shown up to its dungeon quests only; what comes after them is left out.",
	} },
	{ "0.29.0", "2026-11-16", {
		"Quests: with a dungeon picked as the zone, a dungeon quest that is part of a chain shows its whole chain, the steps out in the world too.",
	} },
	{ "0.28.3", "2026-11-15", {
		"Built-ins: the raid-style party frames box is gone: it is set in Edit Mode (click the party frames there).",
	} },
	{ "0.28.2", "2026-11-15", {
		"Built-ins: the error speech box is \"Silence error speech\": ticked means the voice is off.",
	} },
	{ "0.28.1", "2026-11-15", {
		"Fixed \"script ran too long\" with the Items tab open in combat: the NPC, Quests, Items and Zones lists now wait for the fight to end before they are gone through again.",
	} },
	{ "0.28.0", "2026-11-15", {
		"Quests: what a quest gives can be shared with the guild (asked once, on the Quests tab): one member's look at a quest giver fills it in for everybody.",
	} },
	{ "0.27.0", "2026-11-15", {
		"Settings: Built-ins. The game's own switches in one place: auto loot, cooldown numbers, all action bars, error speech, status text, target of target, raid frame options, scrolling combat text, in-game navigation.",
		"The Silencer tool is gone: its switch (error speech) is on the Built-ins page.",
		"Data Sync: lists the other addons DawnTools can read, and whether you have them.",
	} },
	{ "0.26.1", "2026-11-15", {
		"Data Sync: the auction bar is every item ever priced, out of all items; a thin blue bar on it shows those seen in the last day.",
	} },
	{ "0.26.0", "2026-11-15", {
		"Settings, Data Sync: bars that show how complete each kind of data is: auction prices, vendor prices, cooking recipes, quest rewards.",
		"Settings: a line parts Data Sync from the settings above it.",
	} },
	{ "0.25.0", "2026-11-15", {
		"Vendor prices are shared with the guild (if you share prices): one member's visit to a vendor fills the price in for everybody.",
		"Settings: Data Sync. How much has been sent to and received from the guild, by module, and what is held.",
	} },
	{ "0.24.0", "2026-11-15", {
		"Item tooltips: a Vendor line for anything vendors sell, also before you have seen it at one: who sells it, and the price where known.",
	} },
	{ "0.23.0", "2026-11-15", {
		"Food: a Recipe column on the right with the recipe item that teaches it (or \"trainer\"). Hover it for the recipe's own tooltip.",
	} },
	{ "0.22.0", "2026-11-15", {
		"Fish, Spots: a Levels column with the zone's mob levels, coloured for your level.",
		"Fish, Spots: the hover is a tidy list: skill, how many of your casts land, pay per cast and hour, and every fish with its share and price.",
	} },
	{ "0.21.0", "2026-11-15", {
		"Food: the Cooking column shows the whole band: learned at, yellow, green, grey.",
		"Item tooltips: anything a profession makes says which profession and its skill band.",
	} },
	{ "0.20.0", "2026-11-15", {
		"Food: a Cooking column with the skill at which each recipe can be learned. Click its header to sort by it.",
	} },
	{ "0.19.0", "2026-11-15", {
		"Tools: Carrot. Puts your Carrot on a Stick on when you mount and your trinket back when you dismount. You pick which trinket makes room.",
	} },
	{ "0.18.6", "2026-11-15", {
		"Combat: player names are in the colour of their class, where the class was seen.",
	} },
	{ "0.18.5", "2026-11-15", {
		"Enemies: says \"target hidden\" when the game will not tell who an enemy is targeting, instead of showing nothing.",
	} },
	{ "0.18.4", "2026-11-15", {
		"Enemies: a Locked box, so that not even Shift-drag moves the list.",
	} },
	{ "0.18.3", "2026-11-15", {
		"Enemies: Shift-drag moves the list now; without Shift, clicks go through it.",
	} },
	{ "0.18.2", "2026-11-15", {
		"Enemies: moved like the Tracker, with Shift held; its hover tooltip can be switched off.",
	} },
	{ "0.18.0", "2026-11-15", {
		"Tools: Enemies. A list on screen of the enemy players in sight, with level, class, distance, and ON YOU when one targets you.",
	} },
	{ "0.17.2", "2026-11-15", {
		"Combat: who killed you is read from the game's death recap a moment after the death, when it is ready.",
	} },
	{ "0.17.1", "2026-11-15", {
		"Combat: a death is now also recorded when the server does not say who struck: by the enemy players who had you targeted.",
		"/dt deathtest shows what the last deaths were made of.",
	} },
	{ "0.17.0", "2026-11-15", {
		"Combat: the lists are tabs across the top, and a new one, Players: everyone you fought, with kills against deaths.",
	} },
	{ "0.16.1", "2026-11-15", {
		"Quests: shift-click shows the link again (it opened behind the quest window), also inside the quest window.",
	} },
	{ "0.16.0", "2026-11-15", {
		"Quests: what a quest asks you to do is shown when you click it, and on its tooltip.",
		"Quests: text in the quest window stays inside the window.",
	} },
	{ "0.15.6", "2026-11-15", {
		"Quests: the list on the left is wider, and long dungeon names no longer run over the quest list.",
	} },
	{ "0.15.5", "2026-11-15", {
		"Quests: dungeons are in the zone list again, and a dungeon quest shows its dungeon in the Zone column.",
	} },
	{ "0.15.4", "2026-11-15", {
		"Quests: with the OneForAll addon installed, every dungeon quest is listed under its dungeon, also those given outside it.",
	} },
	{ "0.15.3", "2026-11-15", {
		"Quests: Forever's new quests (Krol'dok Stronghold and other new dungeons) now have a zone and show under Dungeon.",
	} },
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
