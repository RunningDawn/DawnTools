# AGENTS.md

Working rules for coding agents (and people) in this repository. `README.md` says what the addon is; `docs/SPEC-DawnTools.md` says how it was designed and what was built.

## What this is

A World of Warcraft addon in plain Lua for the server **WoW: Forever 1.60.1** (`## Interface: 16001`, Retail-style API). No framework, no build step: the game loads the files listed in `DawnTools.toc`, in that order.

## Layout

```
DawnTools.toc   load order; version
Core/           Logic (pure functions), Core (events, slash commands, minimap button, DT.VERSION),
                DB (DT.DB: the one way to ask about items, NPCs, quests and how they hang together, and the store of
                what we learned; DB.Lib: the lists of NPCs, items, quests as QuestieDB or the store gives them;
                DBLogic: its rows, chunks, hashes, merge, pure; DBImport: an installed QuestieDB into the store;
                DBSeed: the seed addon's recipes and dungeons into the store, and DT.Recipes / DT.Dungeons out of it;
                DBSync: passing it between members),
                Comms (guild messages), UI (window, tabs, settings), Profiles, Changelog, Home
Market/         Capture (reading the auction house), Sync (guild sharing), UI
Modules/        Inventory, Fish, Food, Npc, Quest, Item, Zone, Combat, Bis: one file, one tab; Craft: a tab for each profession
                (Bis: its maths is Core/BisLogic.lua, pure; its stat-weight profiles are private to the keeper, in the
                seed folder, never in this repository; its item lists Data/BisLists.lua, by hand)
Tools/          Tools (the tab), Range, Mp5, Tracker: small tools as sub-tabs
Data/           BisLists (by hand). No other game data is in the addon: it is in the store
../DawnTools_Seed/   beside the addon, in no repository and no download: CraftSkill.lua and Dungeons.lua as
                tools/craftskill.js and tools/dungeons.js write them, and the BiS profiles (private, not passed to
                the guild either). The tests read them too
Libs/           third-party libraries, unchanged
tests/          run.js starts fengari; run.lua is a fake client plus every check
docs/           the spec; DATA.md: the data model, every source and its licence, what is stored and what is sent;
                PLAN-DATA.md: the work left on the game database, in order (keep its state up to date)
```

A new file goes in the `.toc` **and** in `FILES` near the top of `tests/run.lua`.

## Tests

```
cd tests && npm install && npm test      # or: node run.js   (about 35 seconds)
```

Passing ends with `ok: N checks passed`. A change in behaviour gets a check in `tests/run.lua`. Green tests do not mean it works in game: say plainly what nobody has seen on Forever yet.

## Git

**Do not commit or push.** Leave changes in the working tree and give the owner the commands.

## Versions

With each batch of changes, in step:

1. `## Version:` in `DawnTools.toc`, and the green `v…` at the end of its `## Title:` (the addon list shows it)
2. `DT.VERSION` in `Core/Core.lua`
3. a new entry on top of `DT.CHANGELOG` in `Core/Changelog.lua` (a test checks it begins with the current version)

Patch for fixes, minor for features. Changelog lines are short and say only what a player notices: no process notes.

## Principles that must hold

- **Opt-in and visible.** Nothing goes to the guild before the player agrees in a popup. One question and one switch for all of it (`DT:Shares()`, `DT.db.settings.share`; a module asks nothing itself and has no switch of its own for it). Sharing off means nothing sent *and* nothing merged. An imported profile never switches sharing on.
- **Only three kinds of shared data** (the table of what each carries is in `docs/DATA.md`): the game database (rows of `DawnToolsDB.db`: the game's data as imported from QuestieDB and OneForAll and seeded from the seed addon, things met in play, loot counted per mob, chest, node or boss under a random origin number, vendor prices, quest rewards, fishing catches; by whisper, no name; a member passes on all of it, whoever it came from), Market observations (item, price, quantity, time, observer name) and recipes known (character name, and the food item IDs and profession recipe IDs it knows). New data about the game goes into the store as rows, not into a store and a sync of its own. A new kind is a decision for the owner and goes in the spec first. New code that asks where a thing comes from or what it gives goes through `DT.DB` (`DB.Lib()` for the long lists), not to QuestieDB directly: `LibQuestieDB` is named in `Core/DB.lua` and `Core/DBImport.lua` only.
- **No game data in the download.** Data from another project goes into the store on a machine that has the source (an import at runtime, or the seed addon), not into a file of this repository. What reaches the store reaches other members: only sources whose licence allows passing it on (below) go in.
- **Everything else is local:** inventory, combat records, Auctionator's imported prices, anything about other players.
- **No automation of trade.** No buying, bidding, posting, cancelling. A scan starts from a click only; a full scan (`ReplicateItems`) at most once per 15 minutes.
- **Libraries** in `Libs/` stay unchanged and keep their licence files.

## Licence, and what may be copied in

DawnTools is **GPL-3.0-or-later** (`LICENSE`). New files are under it too.

- **May be copied in:** code or data whose licence is GPL-3.0-or-later compatible *and stated in the source itself* (a licence file, a `.toc` `X-License`, a file header): GPL-3.0, GPL-2.0-or-later, LGPL, MIT, BSD, zlib, public domain. Known so far: OneForAll (GPL-3.0-or-later), QuestieDB and Questie (GPL-3.0 for what their licence file covers; it warns that not every contributor may have agreed).
- **Every copy is recorded** in `THIRD_PARTY_LICENSES.txt` (create it with the first copy): what was taken, from which project and version, its author, its licence, and the licence text where that licence asks for it. That holds for rows of the store as for files: keeping data out of the download does not change what its licence allows, since a row passed to a guildmate is a copy handed on. Generated data files name their source in a header and are made by a script in `tools/`, not by hand.
- **May not be copied in:** anything "all rights reserved", without a licence, or with a contradictory one. Known: Auctionator (do not even read its source as a reference: its authors forbid it), TSM, aux, ForeverFishing, ForeverLevelingBiS, RareScanner, GatherMate2 (`.toc` and licence file disagree), AtlasLootClassic (GPL version 2: not one this licence may take in). Their data may still be *read at runtime* through their public functions on the player's own machine, never stored or shipped.
- **Not from websites.** No scraping of Wowhead or other sites: their terms forbid it, whatever the licence of DawnTools.
- When in doubt about a licence: do not copy, ask the owner.

## Things this server does differently

- Registering `COMBAT_LOG_EVENT*` gets an addon blocked. `Modules/Combat.lua` uses `PARTY_KILL`, `PLAYER_DEAD`, the honor chat line and `C_DeathRecap` instead. Do not use `C_CombatLogInternal`.
- Values may be "secret" in combat: test with `issecretvalue` before comparing or storing (see `Plain()` in `Combat.lua`).
- Guild addon messages are rate-limited and a heavy sender may be dropped by the server. Everything goes through `Core/Comms.lua` (AceComm + ChatThrottleLib); nothing is sent in combat, nor in instances unless the player allows it. `/dt sync` shows the counters.
- Character names have two words ("First Surname").
- Secure buttons and macros cannot change in combat (`Tools/Tracker.lua` waits for its end).

## Style

- The least code that works; reuse what is in `Core/` before writing new helpers.
- A deliberate shortcut gets a `-- ponytail:` comment naming its limit and what would replace it.
- Guard every game function that may be missing (`X and X(...)`); `/dt probe` lists what Forever has.
- Player-facing text is plain English, short.
