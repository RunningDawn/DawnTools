# Plan: the game database

Where the game database of DawnTools is going, what is built, and the work left, in the order to do it.
The model, the sources and their licences, and what is stored and sent are in `docs/DATA.md`; this page is the
work plan. Written 2026-11-19 at version 0.44.0; brought up to date the same day at 0.45.0. Update the state of
a step here when it changes.

## The vision

One database of the game, kept on each player's own machine, that the guild fills and shares.

1. **One model.** Items, NPCs, objects, quests, zones, recipes, dungeons, with the relations between them
   (who drops what and how often, who sells it, which quest gives it, where it stands).
2. **Every tab reads it.** No tab asks QuestieDB or another addon directly; they ask `DT.DB`.
3. **Fed from several places.** Other addons installed on the machine, the seed addon on its keeper's machine,
   and what members see in play. Every fact says where it is from.
4. **Not in the download.** It is written on each player's machine and acquired from guildmates: the more
   members online, the faster a new member's database fills.
5. **The guild's own finds stand out.** What no source knew before a member met it is listed as a find.
6. **Anonymous.** No name is stored, sent as a field, or shown.
7. **One store, one sync, one switch.** The older per-module stores and their separate sync kinds are gone.
8. **Not taxing.** Nothing polled; a look at one thing reads one chunk; nothing sent in a fight.

## Where it stands

**Nothing below has been seen in the game since 0.44.0.** All of it passes the checks of `tests/run.lua`, which
run the addon against a fake client and a fake guild. Step 1 is the first thing to do.

| Part of the vision | State |
|---|---|
| Documentation | Done: `docs/DATA.md`. |
| The model | Written down (22 relations in `DB.RELS`). `DT.DB` answers 6 as relations; the tabs read the rest of what they need through `DB.Lib()`. |
| The store | Done: rows in chunks, hashed (`Core/DBLogic.lua`, `Core/DB.lua`). Measured: 60,000 rows are 2.5 MB of memory, 58 ms to read through. |
| Base rows | Done in 0.45.0: QuestieDB's NPCs, items, quests and objects with what the tabs use of them (flags, places, who drops and sells, quest chains); recipes, vendor prices and dungeons from the seed addon. Not seen in game; size and import time not measured. |
| Not in the download | Done in 0.45.0 for recipes, vendor prices and dungeons: they live in `DawnTools_Seed/` on the keeper's machine. `Data/QuestRewards.lua` went in 0.48.0. Still a file of the addon: `Data/BisLists.lua`. `Data/BisProfiles.lua` holds the BiS default weights (decision E). |
| Learned in play | Loot of every mob, chest and node counted (seen working in game at 0.44.0). New NPCs, items, quests, chests written down, now with the map they were met on (not seen in game). |
| Finds | World → Finds lists them; a click is a waypoint. They are in the NPC and Quests tabs too. |
| Sync | Built; passes in the fake guild: a newcomer gets recipes, dungeons and a guildmate's QuestieDB rows, also from a member who only received them. Never run between two real players. Measured alone: about 700 bytes a second per sender by whisper, none lost. |
| Every tab reads it | Done in 0.45.0 for NPC, Quests, Items, Zones, Food, the Market tooltip: all through `DB.Lib()` / `DT.DB`, so they work from the store without QuestieDB. `LibQuestieDB` is named in `Core/DB.lua` and `Core/DBImport.lua` only. Left: `Q.Origin`, `Food.Source`, `F.Where`, `D.DropOf` still put their own answers together (from the same reader) instead of asking `DB.Rel`. |
| One store, one sync | Done in 0.48.0 for boss loot, quest rewards, vendor prices, fishing catches and the dungeon list: rows of the store, each with a migration, their own sync kinds removed. Boss loot is counted once. Left beside the store on purpose: Market observations (a price history with observers) and recipes known (they name characters). Not seen in game. |

## The work, in order

Each step ships alone: its checks in `tests/run.lua`, a version bump, a changelog line, `docs/DATA.md` brought
up to date, and a check in the game by the owner. No commit by an agent.

### Step 1. See it hold up (owner, in game)

**Seen 2026-11-19 at 0.47.1, on the machine with QuestieDB and the seed:** the import of every field ran to its
end (`…/5`); the store holds 56,563 rows in 1,693 chunks, 6,340 KB; 2,482 recipes, 50 vendor prices and 321
bosses came from the seed; loot is counted (2 windows, 2 corpses counted). Not noted yet: how long the import
took and whether the game stuttered. Not seen yet: anything between two players; the tabs on a machine
without QuestieDB; the one question of sharing.

Nothing to build. On the machine with QuestieDB and the seed addon: `/reload`, wait a few minutes out of a
fight, `/dt db`.

- The base-rows line goes from "being imported, n of m" to "of QuestieDB …/6". Note how long it took and
  whether the game stuttered: the import now reads some twenty fields a thing, at about 2 ms a frame. What
  QuestieDB's own decoding costs is not known. It only runs with "Read … in the background" switched on.
- The line after it: "N recipes and M vendor prices (SkillUp Forever …), K bosses (OneForAll …); this machine
  has the seed". The profession tabs and World → Dungeons look as they did at 0.44.0.
- The first line: rows, chunks and **KB**. This is the number nobody has: the size of everything.
- `DawnTools_Seed` shows in the addon list and is switched on.
- World → Finds after targeting some of Forever's own mobs, talking to one, opening a chest; click one.

Then, on a second account or with QuestieDB and the seed switched off and the saved file moved away: the tabs
say "Nothing to list yet"; after agreeing to share, with the first character online, they fill. Time it.

If the import stutters: a smaller `I.BATCH`, fewer fields, or the lists in a second pass. If the store is too
big to pass at 700 bytes a second: `I.LIST` and `I.SPOTS` down (`Core/DBImport.lua`), or step 5's work first.

### Step 2. The tabs fall back to the store — done (0.45.0, Zones in 0.46.0)

`DB.Lib()` gives the tabs QuestieDB or the store, in one shape. A tab that read from the store reads anew when
rows have come (`DT_DB_UPDATE`). A waypoint without Questie: the map from the `zone:` rows, else by the zone's
name. A
dungeon's door needs Questie as before.

### Step 3. Relations into the store — done as lists (0.45.0), not as relations

A thing's row carries its lists (who drops, sells, rewards an item; the quests an NPC gives and takes; a quest's
chain, giver and taker), cut at 40 entries and 8 places. `DT.DB`'s six relations answer from them.

Left, when something needs it:

- `DB.Rel` / `DB.RelTo` answers for ends, requires, objective, spawns, teaches; and the four callers above
  moved onto them, each with a check that its answers are unchanged.
- An item dropped by more than 40 mobs names 40. If that matters: the rest in a second row.

### Step 4. The old stores move in — done (0.48.0)

Built as listed below, with these differences: the old sync kinds were dropped outright, not answered for a
few versions (a member on an older DawnTools stops exchanging those four kinds until they update); a boss the
list gives no NPC number is counted under `bloot:<dungeon/boss>:<origin>`; inside a dungeon or raid every loot
window is counted whatever the loot method; an installed OneForAll is a source of `boss:` rows (the later of it
and the seed is written, whole); `tools/harvest.js` is obsolete. Not seen in game: every migration, and
whether dungeon counts read right after a real group kill.

One store. The switch is one already (decision A, 0.47.0); what is left is moving the data.

In this order, each a step of its own with a migration that runs once and a check on a saved file of today's
shape:

1. **Dungeon loot** (`dungeon.seen`, `dungeon.guild`). Same shape as the loot counters. `dungeon.seen`
   becomes this install's counters; `dungeon.guild` (keyed by member name) is dropped and comes back by sync.
   `D.Loot` goes; `D.Seen` reads `DB.Looted`. Ends the double count.
2. **Dungeon list additions** (`dungeon.more`): what an installed OneForAll has beyond the seeded list, as
   `boss:` rows of source `oneforall` written by whoever has it. Then OneForAll is a source like QuestieDB, the
   seed's `Dungeons.lua` is not needed, and the "list additions" sync kind goes.
3. **Quest rewards** (`quest.seen`) as `rewards` rows; `Q.Rewards` reads them. `Data/QuestRewards.lua` and
   `tools/harvest.js` go.
4. **Vendor prices** (`market.vendors`) as `sells` rows with price, vendor, place.
5. **Fishing catches** (`fish.catches`) as counters per zone and origin: the guild then shares catch rates.

For a few versions the old sync kinds are still answered, so members on an older DawnTools are not cut off;
then they are removed from `Core/Comms.lua` users and from `docs/DATA.md`.

- Done when: `DawnToolsDB` holds no game data outside `db`, and `README.md` lists the shared kinds that are left.

### Step 5. The sync between real players

Needs a second player on this build.

- Two accounts, both sharing: loot different mobs, wait for a hello round (up to ten minutes), compare
  `/dt db` hashes.
- A fresh install beside a filled one: time until the hashes agree.
- Then build what the measurements ask for:
  - (done in 0.46.0, in the fake guild: one transfer served by several members at once, no chunk asked for
    twice)
  - a hash per kind between the root and the chunks, so that the hash list of a large store is not sent whole;
  - **Bad data** (the owner, 2026-11-19: reconciling it matters more than removing rows). What is in place:
    a later version of a source stands over an earlier one; a source's row over a sighting; a row of the wrong
    shape is left out. What is not: two members who hold different rows of the same source and version (one
    of them broken, or changed by hand) settle on whichever text sorts later, right or wrong, and it then
    spreads. Built in 0.47.0: a member who has the source installed checks a row that came against its own
    source and puts it right, a moment later, so that its row stands everywhere (`DB.Referee`). Still open,
    the stronger half: a fingerprint of each source's rows said with the version, so that a member WITHOUT the
    source can tell a store that differs from what the version should give (today such a member takes a wrong
    row and holds it until it next meets a referee); and for counters, bounds per origin and a way to leave an
    origin out;
  - a hello sooner after a transfer ends, so the next member does not wait ten minutes.
- Done when: a new member's store fills from the guild without anyone doing anything, and `/dt sync` shows what
  it cost.

### Step 6. Our numbers shown everywhere

- Drop chance, stated and ours ("7 of 52 looted"), in World → Dungeons, in BiS's "where it is from", and on
  the item tooltip. One function already says it: `DB.ChanceText`.
- World → NPC: what a mob was seen to drop.
- A group that rolls for loot: record that the mob drops the item, without a count (today: nothing).
- Skinning and pickpocketing kept apart from the kill's loot (today: a corpse's second window is skipped).
- Needs seeing in game first: what Forever reports as the loot method in a group.

### Step 7. More sources

- OneForAll (GPL-3-or-later): vendor prices, quest drops, reagent sources, trainers, item sets, disenchant
  tables, flight paths. As base rows of source `oneforall`, imported at runtime as QuestieDB is (it is a global
  table, `OneForAll`), in place of the seed file.
- SkillUp Forever (GPL-3-or-later): its public API gives recipes, reagents and what a recipe is learned at, but
  not the skill bands (yellow, green, grey), so it cannot take the seed file's place yet. Ask its author, or
  keep the seed.
- AtlasLoot drop rates: shown while installed, never stored (GPL-2).
- CMaNGOS classic-db: drop chances of old-world mobs. Only after its `LICENSE` and `COPYRIGHT` files in the
  official repository are read (decision C). A `tools/` script, the result recorded in
  `THIRD_PARTY_LICENSES.txt`.
- The relations still unanswered: pickpocket, skinning, gathering, disenchants, part of, quest of, key of,
  catch, within, belongs, flight.

## Decisions for the owner

| | Question | Needed for |
|---|---|---|
| A | Decided 2026-11-19 and built in 0.47.0: one switch for all sharing (`DT:Shares()`), everyone asked once more. The data of the old kinds still sits in its own stores: step 4. | Done |
| B | Market answers a request with everything it holds, other members' observations and their names included. Say so in the popup, or strip the names from what is passed on? | Any time; it is how it works today |
| C | CMaNGOS classic-db: read its licence files and, if they allow it, take its drop chances? | Step 7 |
| D | The base rows rest on the Questie team's statement that reuse under GPL-3 is fine with them, not on every contributor's consent. Accepted 2026-11-19; to be looked at again before the addon goes on CurseForge. From 0.45.1 every field QuestieDB has of a thing is in those rows, bar translations. | Publishing |
| E | The BiS stat weights ship in the download as defaults (`Data/BisProfiles.lua`, owner's decision, 0.54.0): every player can change them and reset them. Not in the store, not sent. | Done |
| F | The one question of sharing is asked a little after login, since without it a member has no recipes, dungeons or lists. (Accepted with A.) | Done |
| G | Who keeps the seed. One machine is enough for the guild to have the data, but only while members who got it are online to pass it on. A second keeper (the folder copied by hand) makes it sturdier. | Now |

## Risks

- **The import may stutter or take long.** Not seen in game. It reads far more a thing than at 0.44.0. Step 1
  finds out; the pacing is one number.
- **Size and the first fill.** Not measured. A whole QuestieDB with its lists may be several MB; at 700 bytes a
  second from one sender (packed, so perhaps a third of the text) a new member's first fill may take the better
  part of an hour. Recipes and dungeons come first and are small. Step 1 measures; step 5 is the cure.
- **A new member starts empty.** Until they agree to share and a member who holds the data is online, the
  profession, Dungeons and World tabs have nothing to list, and say so. That is the price of "not in the
  download".
- **The server's limit on addon whispers is not known.** 700 bytes a second is the sending library's own pace;
  what happens with twenty members whispering one newcomer is not measured.
- **A bad or broken member.** A hash proves a chunk arrived whole, not that it is true. A member can pass on
  wrong recipes or dungeons as easily as right ones: the newer or later-sorting row stands. Bounds are in place
  (seen never above looted, only chunks asked for, never my own counters from the wire, rows of the wrong shape
  left out); forgetting an origin is step 5, and base rows have no origin to forget.
- **Old versions in the guild.** The base rows of 0.44.0 were of another shape. Its sync never ran between two
  players and its files were never committed, so only the owner's install should hold such rows; it imports
  anew at the first login (the import is marked with the shape, `/6`). While the old sync kinds are answered (step 4) nothing breaks; once they are
  removed, a member on an old DawnTools shares nothing until they update.
- **QuestieDB changes its shape.** `Core/DBImport.lua` and `DB.FIELDS` are the places that would need changing.
- **Version numbers decide.** The later version of a source stands for everyone, by its version number alone:
  a release that is worse than the one before it still wins, and two builds with one number are not told apart.
- **Rows are never taken out.** A recipe or NPC a later version of a source drops stays in every store.

## How a step is checked

- `cd tests && node run.js` ends with `ok: N checks passed` (about four minutes). It needs the seed addon's
  two data files beside the addon. A step adds checks for what it changes; a migration is checked on a saved
  table of the old shape.
- Then in the game, by the owner. Green tests do not mean it works on Forever: every step says plainly what
  nobody has seen in game yet.
- `/dt db` says what the store holds: rows, chunks, size, hash, origin, base version, recipes and bosses, the
  last loot window.
