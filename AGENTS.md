# AGENTS.md

Working rules for coding agents (and people) in this repository. `README.md` says what the addon is; `docs/SPEC-DawnTools.md` says how it was designed and what was built.

## What this is

A World of Warcraft addon in plain Lua for the server **WoW: Forever 1.60.1** (`## Interface: 16001`, Retail-style API). No framework, no build step: the game loads the files listed in `DawnTools.toc`, in that order.

## Layout

```
DawnTools.toc   load order; version
Core/           Logic (pure functions), Core (events, slash commands, minimap button, DT.VERSION),
                Comms (guild messages), UI (window, tabs, settings), Profiles, Changelog, Home
Market/         Capture (reading the auction house), Sync (guild sharing), UI
Modules/        Inventory, Fish, Food, Npc, Quest, Item, Zone, Combat: one file, one tab
Tools/          Tools (the tab), Range, Mp5, Tracker: small tools as sub-tabs
Libs/           third-party libraries, unchanged
tests/          run.js starts fengari; run.lua is a fake client plus every check
docs/           the spec
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

1. `## Version:` in `DawnTools.toc`
2. `DT.VERSION` in `Core/Core.lua`
3. a new entry on top of `DT.CHANGELOG` in `Core/Changelog.lua` (a test checks it begins with the current version)

Patch for fixes, minor for features. Changelog lines are short and say only what a player notices: no process notes.

## Principles that must hold

- **Opt-in and visible.** Nothing goes to the guild before the player agrees in a popup. Sharing off means nothing sent *and* nothing merged. An imported profile never switches sharing on.
- **Only four kinds of shared data:** Market observations (item, price, quantity, time, observer name), vendor prices (item, price, vendor's name, place; under Market's sharing switch), Food (character name, food item IDs) and quest rewards (quest, money, experience, items, the level it was seen at; no name). A fifth kind is a decision for the owner and goes in the spec first.
- **Everything else is local:** inventory, combat records, Auctionator's imported prices, anything about other players.
- **No automation of trade.** No buying, bidding, posting, cancelling. A scan starts from a click only; a full scan (`ReplicateItems`) at most once per 15 minutes.
- **Libraries** in `Libs/` stay unchanged and keep their licence files.

## Licence, and what may be copied in

DawnTools is **GPL-3.0-or-later** (`LICENSE`). New files are under it too.

- **May be copied in:** code or data whose licence is GPL-3.0-or-later compatible *and stated in the source itself* (a licence file, a `.toc` `X-License`, a file header): GPL-3.0, GPL-2.0-or-later, LGPL, MIT, BSD, zlib, public domain. Known so far: OneForAll (GPL-3.0-or-later), QuestieDB and Questie (GPL-3.0 for what their licence file covers; it warns that not every contributor may have agreed).
- **Every copy is recorded** in `THIRD_PARTY_LICENSES.txt` (create it with the first copy): what was taken, from which project and version, its author, its licence, and the licence text where that licence asks for it. Generated data files name their source in a header and are made by a script in `tools/`, not by hand.
- **May not be copied in:** anything "all rights reserved", without a licence, or with a contradictory one. Known: Auctionator (do not even read its source as a reference: its authors forbid it), TSM, aux, ForeverFishing, ForeverLevelingBiS, RareScanner, GatherMate2 (`.toc` and licence file disagree). Their data may still be *read at runtime* through their public functions on the player's own machine, never stored or shipped.
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
