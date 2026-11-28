-- DawnTools :: Changelog
-- What changed, newest first. Shown on the Home tab. A new entry goes on top with every version.
-- Short lines, changes only: what a player would notice. Small fixes of one version share its entry.
-- { version, date, { lines } }

local _, DT = ...

DT.CHANGELOG = {
	{ "0.58.1", "2026-11-28", {
		"Settings > Tabs & Modules, tidied: the pages under a tab are listed beneath its name and no longer run into the modules. The modules are sorted into Tabs and pages, Tools and Behind the scenes, in columns that end inside the window. Hover Game database to read what it is.",
	} },
	{ "0.58.0", "2026-11-27", {
		"Themes (Settings > Themes): Original (the look as it was, and still the one you get), Modern, EllesmereUI and Classic WoW. Switches at once.",
		"Tools > Gather: a highlight on the herb, vein, chest, barrel, fishing pool or quest object you are about to interact with, with its name, the skill it asks for and its auction price. Off until you switch it on. By Mushroompunch.",
		"Tools: the tool buttons wrap to a second row when the window is narrow.",
	} },
	{ "0.57.2", "2026-11-27", {
		"Chat Saver: General, Trade and the other numbered channels are no longer unticked when a layout is put back at login. If yours were unticked, tick them again and save once more.",
		"Chat Saver: Save with no name typed writes over the layout picked.",
		"Fishing: whether you can cast in a water counts your fishing pole and your best lure even while they are in the bags, and follows at once when you equip one.",
	} },
	{ "0.57.1", "2026-11-26", {
		"Cooking: foods that give crit, hit or another bonus are grouped by it, no longer under Health only.",
		"Fishing: waters that ask for more skill than the zone around them have a row of their own on Spots: Bay of Storms, Hetaera's Clutch and Scalebeard's Cave in Azshara and Jademir Lake in Feralas (425), Jaguero Isle off Stranglethorn (300). A spot you fished there shows that skill, not the zone's.",
		"Craft: a \"Profit (DE)\" column after Profit (vendor) on the profession tabs: what an armour piece or weapon earns made and disenchanted, the dust, essences and shards sold on the auction house. Hover the row for what it gives. By the old world's disenchanting rates.",
		"Fishing: a History table beside Spots, Fish and Gear: where you fished, how many casts, what bit and what it was worth. Spots is the list of waters only now, the same for everybody.",
		"Fishing: Spots shows the fishing skill of a water as a range: from the skill you can first cast there to the skill at which nothing gets away (330-425). The column of the zone's mob levels is headed Mob lvl.",
		"Fishing: Moonglade, Burning Steppes, Deadwind Pass, Zephras Isle, Riverglades and Hyjal are listed.",
	} },
	{ "0.57.0", "2026-11-24", {
		"Market: a \"Bag/Bank/Alt\" column, after Qty: how many of the item you have in your bags, in your bank, and on your other characters (as the Inventory tab knows them; empty where you have none). The row's tooltip says who has how many and where. Click the header to sort by it.",
		"Market: Ctrl-click a row to try the item on in the dressing room, Shift-click to link it in chat, Alt-click to make it a favourite, as on the other tabs. Hold Shift over a row to compare it with what you wear.",
		"Market: under Containers the item level column shows the bag's slots instead; click its header to sort by size.",
		"Tools: Mitigation. A small column on screen, as it changes: miss, dodge, parry and block together and each on a line; what your armor takes off a physical hit; your block value and defense; how often your own swing hits. Resistances too, if ticked. Beside it a bar of one swing: it fills from the top in the order the game decides (miss, dodge, parry, block), and past 100% the last ones are cut short. Against your target's level, or your own. In a fight the game hides your numbers from addons: they stay as they were before it. Off until ticked.",
		"Guild sync: when a member logs off in the middle of an exchange, the chat no longer fills with \"No player named ... is currently playing\". Nothing more is whispered to them until they are back, and that line is kept out of the chat.",
		"Carrot: a carrot left on after a fight or a loading screen is noticed and swapped for the trinket that slot held before, whenever you are on foot and out of combat.",
	} },
	{ "0.56.3", "2026-11-23", {
		"BiS: hit and crit on gear count for spells too, as Forever has one of each. Casters and healers now see hit and crit gear for what it is worth.",
		"BiS: the recommended set no longer gives up everything else for a cap no gear of the phase can reach (17% spell hit, a tank's hit): such a cap counts by its weight. A cap that can be reached still comes first.",
		"BiS: the recommended set also looks at the best pieces without the capped stats: a tank at the defense cap is offered the best stamina and armor, not only the most defense.",
		"BiS: a weapon in the off hand counts half its damage everywhere, as in the recommended set; the set lists it in the off hand.",
		"BiS below level 60: a quest reward shows only from five levels under its quest (the item itself often asks for no level), and no raid's gear or raid quest reward is offered.",
		"BiS: the sets are worked out a few milliseconds a frame: the game no longer stands still for a second when they are (the tab says \"Working out the sets...\").",
		"BiS Gear: Ring 1 and Ring 2, Trinket 1 and Trinket 2 each list upgrades against what is worn in that very slot; what the other holds is not offered.",
		"BiS: Recalculate now works the sets out anew at once (it only did after a /reload), and sets kept by an older version are not shown for the new one.",
		"BiS: where part of the working out fails, the tab says so in red instead of showing an empty list.",
		"BiS: an item dropped in a dungeon and in a raid counts as the dungeon's; a raid listed as \"Barrow Deeps\" is the one ticked as \"Barrow Deeps Raid\".",
		"BiS Weights: small weights (armor 0.01) show as they are; Enter in an unchanged box no longer rounds them to 0.",
		"BiS: a cap typed between two steps (hit 2.45) no longer picks a worse set; an item the game reports one stat of twice is not counted double; \"spell damage\" and \"damage done by magical spells\" lines are read as spell power.",
		"BiS: a guildmate's shared item with numbers no item has is not believed.",
		"Guild sync: Forever's own recipes (numbers over a million) now reach members; they were left out.",
		"Market: the Usable filter keeps checking skill and known recipes on a long list.",
		"Quests: what you have done is read again once the quest list is in.",
		"Shift-, Alt- and Ctrl-click on an item work on the Inventory, Food, Fish and Zones tabs as on the others.",
		"Carrot: no more endless tries to put the old trinket back while dead or when it is gone.",
		"/dawn opens the window too; where another addon has /dt (Details!), the login line says which command is yours.",
	} },
	{ "0.56.2", "2026-11-23", {
		"Ctrl-click on an item in any DawnTools list tries it on in the dressing room.",
	} },
	{ "0.56.1", "2026-11-23", {
		"BiS: items the game never answers for are not asked again for a week (or until a new game build); Recalculate no longer asks for them.",
		"BiS: items the item list has no type for (some of Forever's own) are found by the type the game gives them.",
		"BiS: armor is read from the tooltip where the game gives no number; armor pieces stored without armor are read again once.",
		"BiS weights: hunters count attack power on gear for the bow too.",
		"BiS weights: every spec counts armor a little (0.01 a point; tanks as before), so of two like pieces the one with more armor ranks higher.",
		"BiS: a ranged weapon's DPS counts for nothing except to hunters.",
		"/dt bis load also counts the items the game never answered.",
		"/dt bis <item> says why an item is not in the BiS item list.",
		"Settings: the in-game navigation switch is gone (it did nothing on Forever).",
	} },
	{ "0.56.0", "2026-11-23", {
		"BiS: item stats are shared with the guild (where sharing is on): a member who has them asks the game for none of those items. Where the game says otherwise of an item after a patch, the newer stats reach everyone.",
		"BiS: items are asked of the game more gently, twenty a second at most, and items it already holds are read at once.",
		"BiS: working out the best set makes far less garbage, for less stutter.",
		"BiS: a dungeon drop says the dungeon, the boss and the drop chance where known, as \"Dungeon, Boss (12%)\".",
		"Dungeons: items AtlasLoot lists for a dungeon the list already has (Forever's own, like Gutcutter Hatchet in Zul'Farrak) count as that dungeon's drops, no longer as world drops.",
		"BiS: when the sets cannot be worked out, the tab says why instead of staying empty.",
		"BiS: dodge, parry and block rating count as the character sheet does (12, 15 and 5 a percent): dodge gear no longer looks twelve times better than it is. Only gear with those ratings, and weapons, is read anew once; the rest stays as stored.",
		"BiS: items load much faster and none are given up on wrongly: each is taken as the game answers, and the count of items to load goes down as they come. Less stutter while they load with the tab open.",
		"Market: prices from the guild no longer stop with \"script ran too long\" on a big price history: it is tidied a little each frame.",
		"BiS: weapon DPS now counts for every warrior and paladin spec, Enhancement, Combat daggers and melee Survival (as much as Feral tanks and rogues weigh it): low-damage weapons stop winning on stats alone.",
		"Market: no error at a vendor whose name the game keeps hidden; its prices are not taken then.",
		"BiS: /dt bis <item> says in chat where an item stands: found or not, its stats, whether you can use it, and what it does against what you wear. /dt bis load says how far the item loader is and what it still waits for.",
	} },
	{ "0.55.3", "2026-11-22", {
		"Data Sync: whispers from a guildmate are no longer turned away when the guild channel gives their name in another form.",
	} },
	{ "0.55.2", "2026-11-22", {
		"BiS: the item tooltip shows only the gain against what you wear, +score (+%), and says when an item would drop you below a cap.",
	} },
	{ "0.55.1", "2026-11-22", {
		"BiS: no whole-set view at level 60: every level shows the list of the slot clicked, the recommended piece marked [R], and the slot marked where the recommended set has another piece.",
		"BiS: the recommended set counts what you own, so it never gives up a piece you have for a worse one.",
		"BiS: tanks are only shown their heaviest armor (plate for warriors and paladins from level 40, leather for bears).",
		"BiS: the tooltip and Upgrades compare with what you wear, the same numbers as the slot list.",
		"BiS: Recalculate asks first.",
	} },
	{ "0.55.0", "2026-11-22", {
		"BiS rebuilt: every item there is is loaded once, in the background, and kept. No item is left out for its level or type any more (Avenguard Helm), and nothing is looked through again after a /reload.",
		"BiS: the Gear view sets what you wear beside one recommended set, which keeps your locked items and reaches the defense cap, then hit, first.",
		"BiS: upgrades and the tooltip line are worked out at once, by swapping the item into your best set; a piece that takes you under a hard cap is no upgrade.",
	} },
	{ "0.54.5", "2026-11-21", {
		"BiS: gear of the other faction is left out: its reputations (cities, battlegrounds), and what only its quests (by their races, or else by who gives them) or vendors give. Where both sides have a quest for it, yours is the one named.",
		"BiS: before a raid is in the phase, rewards for its bosses' drops are left out too (the Head of Nefarian's, handed in in a city).",
		"BiS: the tank weights (Protection warrior and paladin, bear) count armor, dodge, parry and block, and hit for more: they measured threat only. Warriors and paladins reach the defense cap first.",
		"BiS, Extras: at level 60 the best enchants and consumables for the spec (as the game words them), counted toward the hit and defense caps.",
		"Less lag: looting no longer makes the next tooltip read the whole store again; a BiS tooltip never works the sets out itself (it shows from the next look); market history is pruned once a day, not at every login.",
		"Sunken Temple and The Temple of Atal'Hakkar are one place in Dungeons, Quests and NPCs. Zones the game has no name for (Forever's own numbers, \"Zone 10074\") take their map's name.",
		"/dt perf: what took longest since the /reload, and what made the most memory (/dt perf all | mem | gc | reset).",
		"Cooking: foods that raise Fishing skill have a category of their own.",
		"BiS at level 60: every spec reaches its hit cap first (8% melee, 17% spell); legendaries (Atiesh) are left out; the sets are worked out much faster where several caps count.",
		"Faster login: the slash commands are looked up once, not once a module.",
		"Less memory: an NPC keeps no search text or table of kinds (made when searched); a tab reads its list twice as fast while it is open.",
		"BiS: gear of any level is looked at, not only the last 15 (Avenguard Helm); tanks reach the defense cap before hit; less work after a bag change or a gear swap.",
		"BiS: right-click an item in a slot's list to lock it there; the sets to compare keep it (per character and spec). Right-click the slot to unlock.",
	} },
	{ "0.54.4", "2026-11-21", {
		"Guild sharing: the game database goes in short whispers of plain letters and digits, as Forever lets through; the long ones of 0.54.3 never arrived whole. Everyone needs this version to share it.",
		"Settings, Data Sync: counts the whisper pieces that came in, messages lost part-way or unreadable, and the bytes sent; Sync now asks every member who shares.",
	} },
	{ "0.54.3", "2026-11-21", {
		"Guild sharing: the game database now really passes between members (0.54.2 still dropped the answers: the game names a whisper's sender First Surname, and only First-Surname can be whispered to).",
		"Settings: Data Sync now shows the game database's requests each way (lists and chunks asked for, answered, rows taken in, whispers turned away) and, for each member, whether their database matches yours and what is being fetched.",
		"Settings: a new Data Storage page has the bars of how complete each kind of data is, what is held on this computer, and the other addons DawnTools reads.",
		"Settings, Data Sync: a Sync now button (or /dt db sync) asks every member whose game database differs for theirs at once, instead of waiting up to ten minutes.",
	} },
	{ "0.54.2", "2026-11-21", {
		"Guild sharing: recipes, dungeons and the rest of the game database now reach other members (they never arrived: a whisper names a member First-Surname, the guild channel First Surname).",
		"Chat Saver: loading a layout no longer closes docked tabs (the Combat Log among them); they stay docked where they were.",
	} },
	{ "0.54.1", "2026-11-21", {
		"Fixed an error on item tooltips for a new player whose guild had not yet passed on any recipes.",
	} },
	{ "0.54.0", "2026-11-21", {
		"BiS comes with the addon: default stat weights and caps for every class and spec. Change any of them on the Weights view; Reset to default brings them back.",
	} },
	{ "0.53.1", "2026-11-21", {
		"Licences: the Ace3 licence now comes with AceComm and CallbackHandler (Libs/Ace3-LICENSE.txt).",
		"No other addon is named in the load order beyond the public ones DawnTools reads from.",
		"BiS: Realistic (on by default; the last entry of the phase list, and in Settings): gear that needs a reputation standing you do not have yet is left out. Untick it to see everything.",
		"BiS: Temple of Ahn'Qiraj gear (from AtlasLoot's list) no longer shows as a dungeon drop in pre-raid; that raid now has its own name and counts only when ticked.",
	} },
	{ "0.53.0", "2026-11-21", {
		"Tools: an FPS sub-tab: the game's frame rate as a small number on screen, to drag where it suits, lock and size.",
		"Tools: a Chat Saver sub-tab: save your chat windows, tabs, sizes, places, what each shows, channels and colours by name, load them on any character; one can be put back at every login and /reload.",
		"Tooltips: DT: Vendor (buy) names the vendor on the left and has the price on the right, in line with the other prices.",
		"Quests: the safe-to-delete line on quest items works before the Quests tab is opened: the first such tooltip reads the quests in the background.",
		"Quests: the line also shows on quest papers the game does not file as Quest items (Bath'rah's Parchment): what no vendor buys and no recipe uses.",
		"BiS: selling junk at a vendor no longer starts the sets and upgrades over from the beginning on every sale (memory spiked while selling).",
		"Quests: a quest only to be had during another (Gregan's The Videre Elixir in Feralas) now says whom to take that one from and what stands before it, and shows in its chain.",
		"BiS: every boss drop of a dungeon for your level is looked at. Sunken Temple's gear at 60 (Warrior's Embrace, Eater of the Dead) was left out behind higher-level pieces of the same armor or weapon type.",
		"BiS: Upgrades lists every find that beats what you wear, not only the best few of each slot.",
		"BiS: gear worn with a random suffix (of the Bandit, of the Bear) counts with the suffix's stats.",
		"BiS: Upgrades has an \"Only with upgrades\" box next to the source list: dungeons and raids with none are left out of it.",
		"BiS: the gear found is looked through once more after this update.",
		"BiS: Upgrades' source column gives a dungeon drop's dungeon, then its boss and drop chance lined up after it.",
		"BiS: % says \"new\" only for a slot you wear nothing in; a dash where what you wear there counts for nothing for this spec.",
		"Dungeons: an Upg column between Slot and Type: a green arrow on each drop that would improve your best set.",
		"Settings: a Data Debug section below Data Sync: buttons for memory, time per addon and opening the map timed, with the lines in a box to copy (and kept in the saved file until the next press).",
		"/dt map: opens the world map and says how long it took, the slowest frame after it and, with script profiling on, each addon's share.",
	} },
	{ "0.52.0", "2026-11-20", {
		"BiS: the Upgrades view has a filter: by source (quest, crafted, vendor, world drop, any dungeon) or one dungeon or raid, with its levels and how many upgrades it drops.",
		"BiS: Upgrades has column titles, and weight, vs worn, %, the slot and the full source, as Gear has.",
		"BiS: the sets and upgrades are saved: a /reload shows them at once instead of working them out again. Recalculate (Gear and Upgrades) looks again.",
		"BiS: at level 60, raids are ticked one by one (Forever's own first) instead of \"Everything\".",
		"BiS: the whole-set view shows your score and caps beside the set's in a small table of their own, above the items.",
		"Dungeon lists: no more doubles or odd entries from AtlasLoot (the same place under another name, lists of keys and tier sets).",
		"Quests: a quest item's tooltip says DT: Safe to delete (its quests done, or never yours) or NOT safe to delete, and for which quest.",
		"Tooltips: every DawnTools line begins with a gold DT:, in this order: Vendor (sell), Vendor (buy), Auction (when seen), Auction (7d median), the recipes an item goes into (Shift: their names). Prices line up on the right.",
		"Settings: a Tooltips section with a switch for each line, all on to begin with.",
		"BiS: the tooltip of gear you own but do not wear, or that does not better your best set, says what it does against what you wear.",
		"BiS: the best set and Upgrades only take gear you can wear at the level looked at.",
		"Fixed: an error at login with an auction price above about 214,000 gold.",
		"Quests: quests Questie itself hides as not in the game (like the second The Videre Elixir) are no longer listed.",
		"Market, Cooking, professions: characters are named with their surname, yours too.",
		"Market: price history takes far less memory and a smaller saved file. Days older than a week keep their low, median and count. Your saved prices are turned over once, at the first login.",
	} },
	{ "0.51.0", "2026-11-20", {
		"BiS: the Weights view has a Buffs column: what consumables and buffs give a capped stat (hit, defense...) at level 60, counted in when the best set is worked out.",
		"BiS: a ranged weapon's DPS is scored on its own, and an off-hand weapon counts half.",
		"BiS: attack power that only works against some foes (\"when fighting Undead\") no longer counts.",
		"BiS: gear that was slow to load is read again instead of being scored on part of its stats.",
		"BiS: dual wield is offered only when your character can dual wield; unique rings and trinkets are never paired.",
		"BiS: items your race cannot wear are left out, and new armour or weapon skills count at once.",
		"BiS: a respec switches the tab to your new spec; hit and defense pieces needed for a cap are always weighed.",
		"BiS: no more stutter while upgrades are worked out, and nothing is worked out on gear changes while the tab is closed.",
		"Guild: nothing, not even a hello, is sent before you agree to share; database sync talks only to guildmates, less often.",
		"Market: large answers from guildmates no longer lose their end; junk items from guild messages no longer pile up.",
		"Market: Check price at AH waits for a running scan; no doubled vendor line on tooltips; the last scan result clears when the AH closes.",
		"Quests: a quest after a repeatable you handed in shows as open; the chain window updates on hand-in, accept or abandon.",
		"Waypoints no longer say \"that map takes no waypoint\" until /reload when Questie was still loading.",
		"Cooking: names, icons and profits fill in as the game loads them; someone else's linked Cooking window no longer counts as yours.",
		"Professions: opening a profession window no longer scans its recipes over and over.",
		"Finds: an item is noted only once the game has loaded it, so its quality is right; no more rescans of unloaded items.",
		"Items: the category list follows new data. Favourites: search no longer matches hidden colour codes.",
		"NPC tab hovers and Dungeons tab scrolling are faster. The MP5 bar redraws 30 times a second, not every frame.",
		"Combat: the combat log is never touched; older deaths and kills (past the newest 100) drop their hit-by-hit recap.",
		"Chat History no longer keeps whispers or non-chat commands across sessions.",
		"Bad numbers in a saved or imported profile no longer break the window; a guildmate's version text is shown safely.",
	} },
	{ "0.50.5", "2026-11-20", {
		"Enchanting: an enchantment's row shows the game's tooltip for it, and Shift-click links it in chat.",
	} },
	{ "0.50.4", "2026-11-20", {
		"BiS: Pre-raid leaves out the gear of both Ahn'Qiraj raids too.",
	} },
	{ "0.50.3", "2026-11-20", {
		"Quests: \"Hide done\" also hides a quest that can only be had during another, once that one is done (the second The Videre Elixir).",
	} },
	{ "0.50.2", "2026-11-20", {
		"Quests: \"Hide done\" also hides the repeat of a quest you did once (Again With the Zapped Giants, after Zapped Giants).",
	} },
	{ "0.50.1", "2026-11-20", {
		"BiS: Pre-raid no longer lists gear from raids (Naxxramas and the rest), and a dungeon boss's drop is called that at every level, not a world drop.",
	} },
	{ "0.50.0", "2026-11-19", {
		"BiS: a level stepper (- and +, or type a level) and, at the last level, a list to pick the phase from.",
		"BiS: the slot list scrolls, with weight, difference and percent in columns and the source in colour; the item you wear is set apart.",
		"BiS opens at once after a reload: what it found is remembered.",
		"BiS: Defense shows its skill and gear on a line under its bar.",
	} },
	{ "0.49.0", "2026-11-19", {
		"BiS opens on your own class and spec, at your own level. Pick another level to see the best gear for it.",
		"BiS: one ranked list per slot, best on top, what you wear in its place and a few worse below. Each row says what the item weighs, how much better or worse it is than yours, and where to get it.",
		"BiS at the last level: choose Pre-raid or Everything. The tab opens on your whole set against a best set, shows each cap reached or short, and which piece to get next without dropping below a cap you meet now.",
		"BiS: Defense shows as skill/maximum + gear.",
	} },
	{ "0.48.0", "2026-11-19", {
		"Vendor prices, what quests give, dungeon loot counts and fishing catches now live in the game database and are shared with it. Dungeon loot is counted once. What you had is carried over at login.",
		"Fishing: the Spots tab uses the guild's casts too, and says whose numbers they are.",
		"An installed OneForAll fills your dungeon list when it is newer than what the guild has, and passes it on.",
		"A member without QuestieDB can now tell a broken copy of the game's data from a whole one, and does not take or pass on the broken one.",
		"BiS: looks at far fewer items, the most promising first, so the best set shows within seconds and fills in as items arrive. What it learns is kept, so the next login is quick.",
		"Members on an older DawnTools stop exchanging vendor prices, quest rewards and dungeon loot with updated members until they update.",
	} },
	{ "0.47.1", "2026-11-19", {
		"The game database is read anew once more, so that every member's copy is marked the same way.",
	} },
	{ "0.47.0", "2026-11-19", {
		"One question, one switch: sharing with the guild is asked once, a little after login, and switched on or off in one place (Settings > General). The separate questions and switches of Market, Cooking, Quests, Dungeons and the game database are gone. Everyone is asked once more.",
		"A guild member who has QuestieDB (or the seed) now checks what comes from the guild against it and puts wrong entries right, for everyone.",
		"BiS: every spec now gets a best set and upgrades, found from quests, crafting, drops, dungeons and vendors, not only from the hand list. Another class's spec shows what that class could find.",
		"BiS: items the game is slow to send are asked for again, and the tab says how many are left.",
		"BiS: the tooltip names the place an item changes (Ring, Trinket, Main hand, Off hand, Two-hand) and says nothing about gear your class cannot wear. \"Reset to default\" puts a spec's weights and caps back.",
	} },
	{ "0.46.0", "2026-11-19", {
		"Filling the game database is shared out over the guild members who are online: each is asked for different pieces, none for a piece another is already sending.",
		"Where guild members have different versions of QuestieDB (or of the recipes and dungeons), the newest one's data now stands for everyone.",
		"World > Zones follows the game database as it fills.",
	} },
	{ "0.45.1", "2026-11-19", {
		"The game database now keeps everything QuestieDB knows of an NPC, item, quest or object (what a quest wants killed or brought, reputation it gives, where an NPC walks), for the guild members who do not have QuestieDB. It is read anew once, in the background.",
		"The addon list shows the version beside the name.",
	} },
	{ "0.45.0", "2026-11-19", {
		"The game's data is no longer part of DawnTools' download: recipes, vendor prices and dungeons now live in the game database on your computer and come from guild members who have them. Share the game database (/dt db, or the question after login) to get them; until then the profession and Dungeons tabs say so.",
		"World tabs without QuestieDB: with the game database shared, NPCs, quests and items (who sells or drops what, quest chains, waypoints) come from a guildmate who has QuestieDB.",
		"What the guild met that QuestieDB does not know is now listed in the NPC and Quests tabs too. World > Finds: a click on an NPC, quest or chest sets a waypoint to where it was met.",
		"/dt db says how many recipes and bosses the database holds and of which version.",
	} },
	{ "0.44.0", "2026-11-19", {
		"Items: where an item comes from now names the dungeon boss that drops it, with the drop chance stated and what you and the guild have seen.",
		"Loot of every mob, chest and node is now counted on this computer (once a corpse, uncommon and better, where you see all of the loot): the start of our own drop chances. ",
		"New, off until you agree (/dt db): share that game database with the guild, without your name. Members' addons compare what they hold and pass each other only the pieces that differ, so you also get what members who are offline found.",
		"With QuestieDB installed, DawnTools copies what it uses of it (names, levels, where NPCs and objects stand) into its own database in the background. Shared with the guild, a member without QuestieDB gets it from the others.",
		"New under World: Finds. An NPC you target or an item you loot that QuestieDB does not know is noted and listed there; with the game database shared, the guild's finds too.",
		"/dt db bench: measures what a large saved database costs and how fast guild whispers get through, for the shared game database to come.",
	} },
	{ "0.43.0", "2026-11-18", {
		"New tab, BiS (right of Combat): the best gear for a spec. Pick any class and spec by its picture. Along the top how far along you are, the caps and your stats; down the left every slot with what you wear and what it is worth; on the right, for the slot you click, the best you own, the pre-raid list's pick, and the five best quest rewards, dungeon drops, crafted and world-drop items of your level.",
		"Stat weights and caps for 40 specs of all classes (client 1.60.1). All of them can be changed on the tab's Weights view. (From 0.48.0 they are not in the download.)",
		"Item tooltips say what the item would gain over your best set and which slots it changes; so does a chat line when an item is rolled for.",
		"The pre-raid list is for Protection warriors so far.",
		"Combat: players are shown with their surname, where it was seen.",
		"The version is said in the chat when the interface loads.",
	} },
	{ "0.42.3", "2026-11-18", {
		"Fixed: pulling the window's corner could make it leap to nearly the whole screen. The corner now follows the mouse exactly.",
	} },
	{ "0.42.2", "2026-11-18", {
		"Search (NPCs, quests, items, zones): a name is found without its apostrophes and hyphens: \"vehan\" finds Horn of Ve'han, \"zulfarrak\" finds Zul'Farrak.",
	} },
	{ "0.42.1", "2026-11-18", {
		"Items: a bag shows how many slots it has, and bags sort by size (click \"Slot / size\").",
		"Data Sync: the list of other addons says which one matters (QuestieDB) and what the rest add.",
	} },
	{ "0.42.0", "2026-11-17", {
		"Tools: Chat History. In the chat line, Up and Down bring back what you sent before (no Alt needed), and the last 50 lines are remembered across sessions.",
	} },
	{ "0.41.3", "2026-11-17", {
		"Dungeons: \"Hide done quests\" also hides the quests of another class.",
	} },
	{ "0.41.2", "2026-11-16", {
		"Dungeons: a dungeon's quests are coloured by where they stand (in your log yellow, done green), each under the steps that lead up to it. Done ones are hidden unless you untick \"Hide done quests\".",
	} },
	{ "0.41.1", "2026-11-16", {
		"Item tooltips in DawnTools say what an Alt-click does: make it a favourite, or no longer one.",
	} },
	{ "0.41.0", "2026-11-16", {
		"Favourites: a tab with a star, beside Market. Alt-click an item to make it a favourite: on an item row of DawnTools, in your bags, at a vendor, in the loot window. The tab lists them with level, slot, kind, where they come from, auction and vendor price, and how many you have.",
	} },
	{ "0.40.0", "2026-11-16", {
		"Dungeons: a box for only the dungeons about your level; each dungeon lists its quests, for Horde, Alliance or both (your side to begin with).",
		"Dungeons: click a boss to fold its drops shut or open (remembered); the trash stands apart at the end. Right-click a boss for its waypoint.",
	} },
	{ "0.39.0", "2026-11-16", {
		"Dungeons: if you have the OneForAll addon, bosses and drops it knows beyond DawnTools' own list are added, and (if you share) passed to the guild: one member with a newer OneForAll keeps everybody's list up to date.",
	} },
	{ "0.38.0", "2026-11-16", {
		"Dungeons: the list of dungeons, bosses and drops now comes with DawnTools: no other addon needed. AtlasLootClassic, where installed, adds raids and drop chances.",
		"Dungeons: what you see bosses drop is counted, and can be shared with the guild (asked once): real drop rates build up in the \"Seen by the guild\" column.",
	} },
	{ "0.37.0", "2026-11-16", {
		"World: Dungeons. Every dungeon and raid with its levels; pick one for its bosses and what each drops, with the chance and the auction price. Needs the AtlasLootClassic addon.",
	} },
	{ "0.36.1", "2026-11-16", {
		"Craft: Mining and Campsite stand on the first row, after First Aid; the crafting professions have the second row.",
	} },
	{ "0.36.0", "2026-11-16", {
		"Craft: a Campsite tab with everything the professions make for the camp (tent, chair, campfires, workbenches), each with its profession. They are no longer in the professions' own tabs.",
		"Craft: the crafting professions have a row of their own, under Fishing, Cooking and First Aid.",
	} },
	{ "0.35.0", "2026-11-16", {
		"Craft: the gathering professions stand apart at the end: Mining, and new tabs for what Herbalism, Skinning and Fishing make.",
		"Quests: right-click a quest to mark it done (or not done) by hand, for one the game does not remember, such as a quest that can be repeated.",
	} },
	{ "0.34.0", "2026-11-16", {
		"Craft tabs: tick boxes beside the search box: Known, Missing, Profitable, Have mats.",
		"Craft tabs: two profit columns, Profit (AH) and Profit (vendor): made and sold on the auction house, or to a vendor.",
	} },
	{ "0.33.1", "2026-11-16", {
		"Quests: a repeatable quest you have done once counts as done (\"done once (can be repeated)\") and is hidden with the done ones.",
	} },
	{ "0.33.0", "2026-11-16", {
		"Craft: a tab for each profession: First Aid, Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Mining, Tailoring. Every recipe with its skill, what its materials cost, what it earns, who can make it and where the recipe comes from.",
		"Craft: Fish is now Fishing, Food is now Cooking. Cooking has a Profit column too.",
		"Sharing which recipes you know now covers all professions, under Cooking's switch.",
		"Cooking: the Level header is no longer cut off.",
	} },
	{ "0.32.1", "2026-11-16", {
		"Quests: a quest that no NPC gives now says where it begins: an object in the world, an item, or (where nothing is known) whom it is handed in to. A click takes you there.",
	} },
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
