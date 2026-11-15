# DawnTools

Guild tools for **Running Dawn** on **WoW: Forever 1.60.1**.

One window (`/dt`, or the minimap button) with a tab per tool. Most of it works for anyone; the shared parts need guild mates who run it too.

## What is in it

| Tab | What it does | Shared with the guild? |
|---|---|---|
| **Market** | Auction prices you have seen, viewable anywhere. 14 days of history, vendor prices, a price line on item tooltips (hold Shift over a stack for the whole stack). Can scan the auction house on a button click and import Auctionator's prices. | Prices, opt-in |
| **Inventory** | Bags and bank of every character on the account, one searchable list. | No |
| **Craft → Fish** | What a cast is worth in each fishing spot, fish raw and cooked, fishing gear. | No |
| **Craft → Food** | Every cooked food, by what it gives, and who can cook it. | Recipes known, opt-in |
| **World → NPC / Quests / Items / Zones** | Search every NPC, quest, item and zone; waypoints (TomTom or the map pin). Needs the QuestieDB addon (Questie itself is not needed), read at runtime. | No |
| **Combat** | PvP only: who killed me and who I killed, with place, time, guild, class and level. A recap of the hits taken before a death. | No |
| **Tools → Range** | Estimated distance to target and focus. | No |
| **Tools → MP5** | Five-second-rule indicator. | No |
| **Tools → Tracker** | A button that targets a name and pings or marks it. | No |
| **Tools → Silencer** | Tick boxes that switch off game noises (first: the "ability isn't ready" voice). | No |
| **Settings** | Per-module switches, tab order, profiles with export / import. | No |

## What is sent to the guild

Nothing, until you say yes. Two things can be shared, each asked about once:

- **Market:** item prices, quantities and times, plus the name of the character that saw them (can be made anonymous).
- **Food:** your character's name and which foods it can cook.

Both travel as addon messages on the guild channel and reach only guild members running DawnTools. With sharing off, nothing is sent and nothing is taken in. Everything else stays on your machine. No messages are sent in combat, nor in instances unless you switch that on.

## What it does not do

It does not buy, bid, post, cancel or undercut. It never scans the auction house by itself: only when you click the button.

## Install

Copy the `DawnTools` folder into `Interface/AddOns/` and restart the game. The folder must be named `DawnTools`.

Optional addons it works with: QuestieDB (World tabs; Questie adds dungeon entrances), Auctionator (price import), TomTom (waypoints), GatherMate2 (herbs and ore per zone), AtlasLootClassic ("crafted" as an item source).

## Commands

| Command | Does |
|---|---|
| `/dt` | Open or close the window |
| `/dt <tab>` | Open a tab: `market`, `npc`, `combat`, `range`, ... |
| `/dt sync` | Show whether guild messages get out and come in |
| `/dt reset` | Put the window back to its first size and place |
| `/dt selftest` | Check the window in game |
| `/dt probe` | List which game functions this server has |

## Known limits on WoW: Forever

- The server closes the combat log to addons. Kills are known by who, where and when, not by the hits; deaths have the game's own recap.
- The World tabs are empty without QuestieDB.
- Distances are bands ("8 - 10"), not exact numbers: the game gives no exact distance.

## Development

```
cd tests
npm install
npm test
```

The tests run the addon's Lua against a fake game client. `docs/SPEC-DawnTools.md` holds the design and what was built; `AGENTS.md` holds the working rules for this repository.

## Bundled libraries

In `Libs/`, unchanged: LibStub, CallbackHandler-1.0, ChatThrottleLib, AceComm-3.0, LibDeflate, LibRangeCheck-3.0. Each stays under its own licence.

## Licence

Copyright (C) 2026 Running Dawn

DawnTools is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY; see `LICENSE` for details.
