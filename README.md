# DawnTools

Guild tools for **Running Dawn** on **WoW: Forever 1.60.1**.

One window (`/dt`, or the minimap button) with a tab per tool. Most of it works for anyone; the shared parts need guild mates who run it too.

**DawnTools does not come with the game's data.** Recipes, dungeons, and the lists of NPCs, quests and items live in a database on your own computer, and reach it from guild members who have them once you agree to share the game database (asked a little after login, or `/dt db`). Until then the profession, Dungeons and World tabs say they have nothing to list. With the QuestieDB addon installed, the World tabs work at once, and you become a source of its lists for the guild.

## What is in it

| Tab | What it does | Shared with the guild? |
|---|---|---|
| **Market** | Auction prices you have seen, viewable anywhere. 14 days of history, vendor prices, a price line on item tooltips (hold Shift over a stack for the whole stack). Can scan the auction house on a button click and import Auctionator's prices. | Prices, opt-in |
| **Favourites** (the star) | Items you marked with an Alt-click, anywhere: level, slot, kind, where each comes from, auction and vendor price, how many you have. | No |
| **Inventory** | Bags and bank of every character on the account, one searchable list. | No |
| **Craft → Fishing** | What a cast is worth in each fishing spot, fish raw and cooked, fishing gear. | No |
| **Craft → Cooking** | Every cooked food, by what it gives, who can cook it, where its recipe comes from, and what cooking it earns. | Recipes known, opt-in |
| **Craft → First Aid, Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Mining, Tailoring** | Every recipe: skill band, cost of materials, profit at today's prices, who can make it, where the recipe comes from. | Recipes known, opt-in |
| **World → NPC / Quests / Items / Zones** | Search every NPC, quest, item and zone; waypoints (TomTom or the map pin). Read from the QuestieDB addon where installed (Questie itself is not needed), else from the game database as guild members filled it. | With the game database |
| **World → Dungeons** | Every dungeon with its levels; the bosses of one and what each drops, with drop chance, how often the guild saw it drop, and auction price. AtlasLootClassic, if installed, adds raids and chances. | Boss loot seen, opt-in |
| **World → Finds** | What the guild met that QuestieDB does not know: NPCs targeted, items looted, quests offered, chests opened. A click is a waypoint to where it was met. Noted on this computer; passed on only with the game database shared. | With the game database |
| **Combat** | PvP only: who killed me and who I killed, with place, time, guild, class and level. A recap of the hits taken before a death. | No |
| **BiS** | The best gear for a spec. Any class and spec can be picked, by its picture; your own gear (worn, bags, bank as last seen) is rated for a spec of your class. Along the top: how far along you are, the caps (defense, hit, expertise) and your stats. Down the left: every slot with what is worn and what it is worth. On the right, for the slot clicked: the best you own, the pre-raid list's pick, and the five best quest rewards, dungeon drops, crafted and world-drop items of your level, each with its gain over what you wear and where it is from (the item list is read from QuestieDB at runtime, the dungeon list and recipes are DawnTools' own). Also the next upgrades in order, and a line on item tooltips with what an item would gain. Stat weights and caps for 40 specs, all changeable; below level 60 the defense cap goes with the level. The pre-raid list is for Protection warriors so far. | No |
| **Tools → Range** | Estimated distance to target and focus. | No |
| **Tools → MP5** | Five-second-rule indicator. | No |
| **Tools → Tracker** | A button that targets a name and pings or marks it. | No |
| **Tools → Enemies** | A list on screen of enemy players in sight: level, class, distance, and who has you targeted. | No |
| **Tools → Chat History** | Up and Down in the chat line bring back what you sent, as in a shell; remembered across sessions. | No |
| **Tools → Carrot** | Carrot on a Stick on when you mount, your trinket back when you dismount. | No |
| **Settings → Built-ins** | The game's own switches that are hard to find, in one place (auto loot, cooldown numbers, action bars, error speech, raid frames, combat text…). | No |
| **Settings → Data Sync** | How complete each kind of data is, what went to and came from the guild, and which optional addons are installed. | No |
| **Settings** | Per-module switches, tab order, profiles with export / import. | No |

## What is sent to the guild

Nothing, until you say yes. It is asked once, a little after login, for all of it together, and switched on or off in one place (Settings > General). What is shared then (the full table, with what each line carries, is in `docs/DATA.md`):

- **Market:** item prices, quantities and times, plus the name of the character that saw them (can be made anonymous).
- **Cooking and professions:** your character's name and which recipes it knows (one switch for cooking and the other professions).
- **Game database:** the game's data as your computer holds it (recipes, vendor prices, dungeons; NPCs, quests and items where you or a guildmate have QuestieDB), and what DawnTools noted as you played: how often you looted a mob, chest or node and which items of worth were in it, counted under a random number (dungeon bosses too); NPCs, items and quests you met that nobody knew; what vendors ask for their goods (the item, the price, the vendor and the place); what a quest gave you and the level you were; what you catch fishing, and where; and, with OneForAll installed, its list of dungeons. No names. Sent by whisper between members' addons, a piece at a time, each passing on all it holds; you also receive what members who are offline found.

Both travel as addon messages on the guild channel and reach only guild members running DawnTools. With sharing off, nothing is sent and nothing is taken in. Everything else stays on your machine. No messages are sent in combat, nor in instances unless you switch that on.

## What it does not do

It does not buy, bid, post, cancel or undercut. It never scans the auction house by itself: only when you click the button.

## Install

Copy the `DawnTools` folder into `Interface/AddOns/` and restart the game. The folder must be named `DawnTools`.

Optional addons it works with: QuestieDB (World tabs; Questie adds dungeon entrances), OneForAll (which dungeon a quest is for), Auctionator (price import), TomTom (waypoints), GatherMate2 (herbs and ore per zone), AtlasLootClassic ("crafted" as an item source).

## Commands

| Command | Does |
|---|---|
| `/dt` | Open or close the window |
| `/dt <tab>` | Open a tab: `market`, `npc`, `combat`, `range`, ... |
| `/dt sync` | Show whether guild messages get out and come in |
| `/dt db` | What the game database holds: rows, size, where its lists are from, how many recipes and bosses |
| `/dt db bench` | Measure what a large saved database costs and how fast guild whispers get through (see `docs/DATA.md`) |
| `/dt reset` | Put the window back to its first size and place |
| `/dt selftest` | Check the window in game |
| `/dt probe` | List which game functions this server has |

## Known limits on WoW: Forever

- The server closes the combat log to addons. Kills are known by who, where and when, not by the hits; deaths have the game's own recap.
- A new install has no recipes, dungeons or lists of NPCs, quests and items until the game database is shared and a guild member who holds them is online. The first fill takes a while: whispers get through at about 700 bytes a second.
- Without QuestieDB the World tabs show what guild members' QuestieDB knew, cut short where it is long (40 sources an item, 8 places an NPC), and a dungeon's entrance still needs Questie.
- Distances are bands ("8 - 10"), not exact numbers: the game gives no exact distance.

## Development

```
cd tests
npm install
npm test
```

The tests run the addon's Lua against a fake game client. They need the two data files of the seed addon beside the addon (below). `docs/SPEC-DawnTools.md` holds the design and what was built; `docs/DATA.md` the data, where it is from and what is sent; `AGENTS.md` the working rules for this repository.

### The seed

The recipes (every recipe's skill band and reagents, vendor prices of reagents) and the dungeons (bosses, drops) are not in this repository or in the download. They are generated into a folder beside the addon, `Interface/AddOns/DawnTools_Seed/`, from two installed addons:

```
node tools/craftskill.js     # from SkillUp Forever
node tools/dungeons.js       # from OneForAll
```

Where that folder is installed (with a `Seed.lua` and a `.toc`: see `docs/DATA.md`), DawnTools writes its tables into the game database at login, and from there they pass to the guild. One member who keeps it is enough.

## Bundled libraries

In `Libs/`, unchanged: LibStub, CallbackHandler-1.0, ChatThrottleLib, AceComm-3.0, LibDeflate, LibRangeCheck-3.0. Each stays under its own licence.

The game data that passes between members comes from the SkillUp Forever and OneForAll addons (both GPL-3.0-or-later) and from QuestieDB: see `THIRD_PARTY_LICENSES.txt`.

## Licence

Copyright (C) 2026 Running Dawn

DawnTools is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY; see `LICENSE` for details.
