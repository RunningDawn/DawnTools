# DawnTools / DawnMarket — guild addon suite (v1 spec)

**DawnTools** is a suite of guild addons for Running Dawn on WoW: Forever. **DawnMarket** is its first module: members share recent AH prices and get a market viewer that works anywhere in the world.

**No money-making logic.** No vendor-flip, craft→vendor or other trading logic ships in DawnTools.

## As built (v0.1.0) — where the code differs from this spec

- **One addon folder.** Everything lives in `DawnTools/`; modules are subfolders (`Market/`) registered with `DawnTools:RegisterModule` and switched on/off on the Settings tab. No `DawnTools_Market/` folder, no `## Group` TOC fields.
- **No Ace framework.** Plain Lua. Bundled libs are only what guild messages need: LibStub, CallbackHandler, ChatThrottleLib, AceComm (splitting + throttling), LibDeflate (compression). Observations are encoded as `id,price,qty,time,observer;`, so no serializer.
- **Module settings** are a plain list of checkboxes (`{ key, label }`), not an AceConfig table.
- **Tabs:** reorder with arrows (no drag handles); one account-wide layout. The window resizes from its bottom right corner.
- **Market tab** is laid out like the auction house: categories (and the open category's sub-categories) down the left, search box on top, table in the middle, the selected item underneath.
- **Capture also reads browse results** (every listed item, as Auctionator does; for gear the lowest price may be a bid, put right when its auctions are opened). An unchanged price is recorded again only after 15 minutes.
- **Sync:** all messages go to GUILD, none by whisper. A REQUEST names the member who should answer; the DATA answer is heard and merged by everyone. `since` is "when I was last in step with the guild", not "my newest observation". An answer holds at most the 2000 newest observations.
- **Sharing off** means nothing is sent *and* nothing is taken in.
- **Outlier filter** applies to prices from other members only; what the player saw themselves is always believed.
- **Auctionator:** its whole price history (every item, every day it scanned, within 14 days) is read from its price table, since its public API cannot list items or days. It knows the day of a price, not the time, so each day becomes one price placed mid-day, shown as seen by "Auctionator", and never shared with the guild. Gear it tracks by item level is skipped.
- **Trend** is a percentage against the 7-day median, not an arrow. **"Search at AH"** is "Check price at AH": one search for exactly that item, which refreshes its price in the viewer.
- **History** keeps at most 16 observations per item per day; length is fixed at 14 days.
- **A scan, on request.** Principle 2 ("never trigger scans") now reads: never on its own. The Market tab has a "Scan auction house" button, for members without Auctionator: one click reads the auction house's item list once, page by page (the list an empty search shows; no ReplicateItems, no cooldown used up). It records every listed item at the list row's lowest price; for items that can be bid on that may be a bid, put right when their auctions are opened. **Full scan (added later):** the button now asks Quick or Full. Full calls ReplicateItems once (every auction, exact buyouts), only from that click, and no more than once per 15 minutes (db.lastFull, also set when another addon runs one). Closing the auction house before it is read cancels it: nothing is recorded and the 15 minutes still count.
- **Inventory module** (`Inventory.lua`, tab "Inventory", `/dtinv`): bags and bank of every character on the account, one searchable list. Local only: it sends and receives nothing. The bank is read while it is open, so each character has to open it once. Characters are keyed by GUID and shown as class icon + "First Surname" in the class colour (the surname is UnitFullName's second value on Forever). `DawnInventory.API.Count(itemID, guid)` → in bags, in bank.
- **Market table:** fills the tab's height, with a scroll bar; the history box takes its place at the bottom only while an item is picked. Columns Lvl (required level) and iLvl. Filter line: required level from-to, a tick box per quality (none ticked = all), "Usable" (level, and the game's own CanUseItem where the client has it).
- **Auction houses:** prices are kept per house, "H"/"A" (a faction's own) and "X" (cross-faction). The house is worked out when the auction window opens (auctioneer of the other faction or of none = cross-faction; a choice made by hand with the "Here:" button is remembered per auctioneer NPC). The Market tab, the tooltip line and the API show one house: the one the player is at, or the one picked with the house button. PUSH and DATA payloads start with the house ("H|…"); a payload without it is dropped. Auctionator's history, which does not tell houses apart, is filed under the player's own faction.
- **Categories** are a tree like the auction house's own: weapons by One-Handed / Two-Handed / Ranged / Miscellaneous, then weapon type; armor by Plate / Mail / Leather / Cloth, then slot (head … hands), with Miscellaneous holding neck, back, finger, trinket, off-hand and shirt. An item's slot (`e`) is stored with its name and class.
- **House picker:** one button per house on the Market tab, the lit one is shown; at an auctioneer a line says which house it is taken for, with "Wrong house?" beside it.
- **Fish module** (`Fish.lua`, tab "Fish", `/dtfish`), local only. Two tables. *Spots*: what a cast is worth in each fishing spot at the shown house's prices. *Fish*: each fish's price raw and cooked, what cooking adds after the other mats, and where it bites. A third table, *Gear*, lists the lures, poles and clothes that raise fishing skill, how many the account has, and where they come from in the old world. A click on any item row shows a link to its Wowhead Classic page in a box to copy (an addon cannot open a browser). All tables sort by any column (click its header) and have a search box. A spot's skill is the level at which nothing gets away, coloured by the player's fishing skill with gear and lure: green enough, yellow can cast (from 95 below), red cannot. Sources: a built-in list of old-world fish, recipes and waters (recipes checked against game data; waters and their equal shares are a rough guess, marked "~"); the account's own Cooking recipes, read when that window opens; and the player's own catches, counted per zone and sub-zone, which replace the guess for a zone from 20 casts on.
- **Food module** (`Food.lua`, tab "Food", `/dtfood`): every food the Cooking window lists (read when it is opened, recipes not learned included), grouped on the left by what it gives (read from the item's English tooltip: Stamina, Spirit, … or "Health only"; the Cooking window's own heading where that fails). Each row says whether this character knows the recipe and who can cook it: the account's other characters and guild members. "Hide missing" leaves out what this character lacks. The table sorts by any column (click its header). **Shared with the guild, opt-in** (asked once when the tab is first opened, `settings.share`): a character's name and the item IDs of the food it can cook (KNOWN), and a REQUEST for a member's list when their HELLO count differs from what is held. This is a second kind of shared data beside Market prices (principle 3).
- **Vendors:** whenever a vendor's shop is opened, what it sells for money is recorded (unit price, vendor, place, limited stock), local only. The Market table has "Vendor sells" beside "Vendor pays" (gold where the auction price is higher, * for limited stock), a "Vendor sells" filter box, the vendor and place on the row's tooltip, in the history box and on item tooltips, and a "Link" button to the item's page. `DawnMarket.API.GetVendor(itemID)` → price, vendor, place, limited. `DawnMarket.API.GetHouse()` → key, name of the house the prices are of.
- **NPC module** (`Npc.lua`, tab "NPC", `/dtnpc`), local only. Every NPC of the game, to search and to set a waypoint to. **The data is not DawnTools' own:** it is read at runtime from the QuestieDB addon through its public API (`LibQuestieDB.Npc`: `GetAllIds`, `GetAll`, `Get`); nothing of it is copied into DawnTools or saved, and nothing goes to the guild. Without Questie + QuestieDB the tab says so and stays empty. Read the first time the tab is opened, a few milliseconds per frame, with a progress line. *Types:* each NPC has a set (Vendor, Repairs, Trainer, Class trainer, Quest giver, Flight master, Innkeeper, Banker, Auctioneer, Stable master, Spirit healer, Battlemaster, Guild services; Rare, Elite, Boss; the professions; Food & drink, Trade goods, Reagents, Weapons, Armour, General goods, Ammo, Mounts) from QuestieDB's NPC flags, the rank, and keywords in the NPC's title. *Search:* one box over name, title, zone and types; every word must match; ranked exact name > start of name > word in name > elsewhere > letters in order > a misspelling (one letter, two in long words; only when the plain search finds less than a screenful). *Filters:* the types on the left (those the listed NPCs have, with counts; several ticked must all apply), Favourites, level from-to, side (any / friendly to me / not), this zone only, with a known location, Clear. *Favourites:* a star per row, saved (`favs`), with the ticked filters the only thing saved. *Click:* a waypoint to the nearest spot on the map I am on, else the first: TomTom if installed, else the game's own map pin; Shift-click the NPC's page; hover: title, level, rank, side, types, spots per zone, whether it patrols, quests started/ended, what DawnTools saw it sell.
- **Quests module (`Quest.lua`).** Every quest, read at runtime from QuestieDB (`LibQuestieDB.Quest`) like the NPC tab: nothing copied, nothing saved but the filters, nothing sent to the guild. Shows what is open to this character (done / in the log / open / not yet and why / not for it), labels (dungeon, raid, group, class, profession, daily, chain start...), and a chain window that lists a quest's whole chain from its first quest, indented, with a waypoint to each quest giver.
- **Items module (`Item.lua`, World > Items).** Every item, read at runtime from QuestieDB (`LibQuestieDB.Item`): name, levels, kind and sources (dropped by, sold by, found in, reward of, starts a quest; "crafted" from AtlasLoot's public lookup when installed). Laid out as the Market tab (its category tree and usable rules are shared). Quality, slot, stats and Equip/Use lines come from the game per item, are asked for once and kept in `DawnToolsDB.item.known` (item facts never change). A Stats box filters on them (`sta>11 int>=5 hit`). Filters that need those facts work on what the cheap filters left, learn the rest a batch at a time, and refuse more than 3,000 unknown items without a click. Local only.
- **Zones module (`Zone.lua`, World > Zones).** A list of zones (levels, side) and, for the one picked, what is there. Levels and side are worked out from the NPC list (ordinary hostile mobs' levels without the extremes; whose service NPCs stand there), marked "~" as estimates, since nothing installed gives them to read. The panel: quests (open / not yet / done, a jump to the Quests tab), dungeons whose door is there (Questie's `ZoneDB:GetDungeons`, waypoint), rares, services (a jump to the NPC tab), fish (the Fish tab's data), herbs and ore (counted from the player's own GatherMate2 store, read at runtime), leather (by mob level, the old-world rule), and the ten dearest drops by the guild's auction prices (worked out a few milliseconds a frame). Local only; nothing copied.
- **Home tab (`Home.lua`, `Changelog.lua`).** The first tab, a house on its button instead of a word (`tab.icon`): "Built for Running Dawn", "Built by Forgehaven", what each tab is for (click = open it), and the changelog (`DT.CHANGELOG`, a new entry with every version). A new user's first look at the window lands here; afterwards the window reopens on the tab last used, as before. Hideable like any tab.
- **Settings in sections (`UI.lua`).** The Settings tab lists sections down the left: General, Profiles, Tabs & Modules, and one for every module with switches of its own (`UI:Section(id, title, order, build)`).
- **Profiles (`Profiles.lua`).** A profile holds how the addon is set up (settings, tabs and modules, the window, and per module what it names in `profile = { ... }`: positions, sizes, filters) and nothing that was collected. Every character uses "Default" until one is picked for it; switching reloads the interface. Export and import as text: an own writer and reader (text, numbers, yes/no, tables) packed with LibDeflate; reading runs no code, checks shape, size and depth, and keeps only keys a profile may hold. Local only.
- **Background reading (`Core.lua`, `DT:Background`).** NPCs and quests (items later) are read from QuestieDB a few seconds after login, about 2 ms a frame, not in combat, so their tabs open at once. General setting, on by default.
- **Places on the tab bar.** Some tabs stand together under one: Fish and Food under **Craft**, NPC and Quests under **World**. A module puts its tab under a place with `tab.under = "world"`; the place is the button on the bar and shows a row of its sub-tabs (`UI.lua`, PLACES). `/dt npc` and the like open the place on that sub-tab; the last sub-tab used is remembered. Hiding and ordering on the Settings tab go by what is on the bar.
- **Tools tab (`Tools.lua`).** A top tab in a group of its own (behind a second separator, after Combat) holding sub-tabs: small tools that are not worth a whole tab. A module adds one with `DT:RegisterTool({ id, title, order, create, onShow })` from its `onEnable`. `/dt <tool id>` opens it.
- **Range module (`Range.lua`), the first tool.** The estimated distance to target and focus as numbers on screen (a band, "8 - 10" or "40+": the game gives no exact distance), coloured by band, above the unit frames' portraits or dragged anywhere, lockable, font size 8-32. Local only. The range checks are the library **LibRangeCheck-3.0** (MIT, The WoWUIDev Community), embedded unchanged in `Libs/` with its licence file, as the Ace libraries are: an MIT library used as a library, not code copied from an all-rights-reserved addon, so the "copy no code" principle is untouched. On top of the library, every ranged spell in the character's own spellbook is asked "in range?" too (its real range now, talents counted), which narrows the bands and keeps them narrow in combat; "My range" colours the number green inside a chosen distance and red beyond; members of the own group outdoors get the exact distance from their positions. The band limits and colours follow RangeDisplay's defaults (that addon declares itself public domain).
- **MP5 module (`Mp5.lua`), a tool.** The five-second rule as a small indicator: after a spell that costs mana, a five-second countdown (held while such a spell is channelled), then nothing. Counted from the player's own casts: Forever has no two-second mana ticks and hides mana from addons in combat, so nothing is measured. Four looks from a dropdown (a spark over the game's own mana bar, falling back to the bar where that is not there; a thin bar; a small clock; a number), movable, resizable, lockable. Off until switched on. Local only.
- **Tracker module (`Tracker.lua`), a tool.** A small secure button holding a name: a click runs one macro (clear target, `/tar <name>`, ping or raid-icon it if it is there and alive, else put the old target back). Right-click sets the name, Shift-drag moves it, it is as wide as its text and grows from the left, the centre or the right. Changes made in combat wait for its end (the game's rule for secure buttons). Off until switched on. Local only.
- **Vendor prices are shared** (decided by the owner, 0.25.0): a third kind of shared data, under Market's sharing switch and its question. On the wire (module `vendors`, the shared way `Comms:Gossip`): `HAVE` lines of item, copper, limited, seen, vendor's name, place; `WANT` asks one member for what they saw since a time. Only what a member saw themselves is sent; what came from the guild is marked and never passed on. No player's name is in it.
- **Quest rewards are shared** (decided by the owner, 0.28.0): a fourth kind of shared data, with its own question (asked when the Quests tab is first opened) and its own switch. The same way on the wire (module `quest`): lines of quest, copper, experience, the level it was seen at, seen, items given, items to choose from. No player's name. What a member sees themselves replaces what the guild said.
- **Data Sync** (Settings, last section): messages and bytes sent and received per module, kept across sessions (`DT.db.sync`), what each module holds, and the session's counters. A button starts the counting anew.
- **Quests, an instance picked** (as the zone, or on the left under Dungeon / Raid): a quest of that instance brings the steps that lead up to it into the list, those given out in the world too (not what follows it, unless that leads on to another quest of the instance); they skip the zone, kind and level filters but not the status switches or the search. A plain zone brings nothing along.
- **Profession tabs** (`Craft.lua`, module `crafts`, 0.33.0): under Craft, after Fishing and Cooking (the Fish and Food modules, renamed on screen): First Aid, then behind a line Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Mining, Tailoring. Each lists every recipe of the shipped list (`DT.Recipes`: materials, yield, skill band, scroll), with the cost of its materials (the cheaper of auction and vendor), its profit (auction price of what is made, times the yield, less 5%, less the materials; unknown while a price is missing; none for an enchantment), whether this character knows it (read when the profession's window is opened), who can make it, and where the recipe comes from. Cooking has the profit column too. **Shared with the guild under Cooking's switch** (owner's decision): character name and the recipe IDs it knows, `KNOWN` / `REQUEST` as the Food module's; the question and the setting say so.
- **A module may have several tabs** (`tabs = { ... }`); sub-tab buttons are as wide as their titles, and a change of `group` along the row puts a line between them.
- **Dungeons module** (`Dungeon.lua`, tab World > Dungeons, `/dtdungeon`), local only: the dungeons and raids with their level range on the left; the picked one's bosses in order, each with its drops (slot, type, drop chance, auction price). The list ships with the addon (`Data/Dungeons.lua`, generated by `Tools/dungeons.js` from the OneForAll addon, GPL-3.0-or-later). The AtlasLootClassic addon, where installed, is read at runtime through its own tables for what the shipped list lacks (raids) and for drop chances; nothing of it is copied (GPL version 2). **Boss loot seen is shared** (decided by the owner, 0.38.0): a fifth kind of shared data, with its own question and switch. The loot window of a boss in a dungeon or raid is counted once a corpse (`db.seen[boss] = { k, t, items }`); on the wire (module `dungeon`, `Comms:Gossip`) a line a boss: key, times looted, when, items with their counts. No names. Each member's count is kept by member and the sums are added when shown. **The list keeps itself up to date** (0.39.0): the OneForAll addon, where installed, is read at runtime, and bosses and drops it has beyond the shipped list are added; those additions are told to the guild under the same switch (module `dungeonlist`: a line a boss with dungeon, levels, boss name, NPC, and the new items with their chances), so a member without OneForAll gets them from one with a newer. What came from the guild is not passed on. A release refreshes the shipped list with `node Tools/dungeons.js`.
- **Favourites module** (`Favs.lua`, the tab with the star beside Market, `/dtfav`), local only. One list of favourite items for the whole addon (`DT.Favs` in `Core.lua`, kept in `db.market.favs` where the Market tab always kept its own). An Alt-click makes an item a favourite or no longer one: on an item row of DawnTools (`DT:LinkClick` with the item's number), and on any item in the game that takes a modified click (`hooksecurefunc` on the game's `HandleModifiedItemClick`: listened to, not changed). The tab lists them: level, slot, kind, where it comes from (dungeon boss, profession, vendor, mob, quest), auction price, vendor price, how many I have.
- **Chat History module** (`ChatHistory.lua`), a tool, local only. The game's own chat history is used, not a new one: the tool switches each chat edit box to plain arrow keys (`SetAltArrowKeyMode(false)`; off: back to Alt), listens to the lines the game adds to its history (`hooksecurefunc` on each box's `AddHistoryLine`), keeps the last 50 (`db.lines`, plain text, this computer only) and hands them back to every box at login. Off by default.
- **Carrot module (`Carrot.lua`), a tool.** Carrot on a Stick (item 11122) is equipped on mounting (not on a flight path) into the trinket slot the player picked, and the trinket it replaced is equipped again on dismounting; in combat the game changes no trinket, so that waits for the fight's end. What was replaced is saved (`db.back`) so a reload while mounted loses nothing. Off by default. Local only.
- **Tab groups:** a tab may name a `group`; where the group changes along the bar there is a gap with a thin line. Market, Inventory, Fish, Food and NPC are group 1, Combat group 2.
- **Combat module** (`Combat.lua`, tab "Combat", `/dtcombat`), local only. Reads the combat log. *Who killed me*: for each death the time, place (zone, sub-zone, map coordinates), the killer (source of the last hit in the 10 seconds before; players in red), what with and for how much, and who else hit me in that time with their damage. *Who did I kill*: whatever died within 10 seconds of my hitting it, with whether the killing blow was mine. Sortable, searchable, "Players only" box. 500 entries per list. *Recap*: a click on a row opens a small window with the damage behind it, totalled by ability (hits, criticals, biggest, share) and listed hit by hit with the seconds before the death; for a death every hit taken in those 10 seconds, for a kill my own last 30 attacks on it (what others did to it is not kept). Also in it: heals received (with overheal), what was absorbed, resisted and blocked, overkill, attacks that did not land (dodged, parried, missed, immune, ...), debuffs put on me and spells of mine that were interrupted. Only damage decides who the killer is. Laid out as a table: time (or number of hits) | spell icon | who: ability | amount | notes; damage red, heals green, absorbed/resisted/blocked blue, criticals yellow, debuffs and interrupts purple, a share bar behind each total and a red line behind the killing blow.
- **Settings tab** sits on the right of the tab bar, apart from the working tabs.
- **Not built:** officer/admin (§6), load-on-demand modules.
- **Still to verify in game (Phase 0):** `/dt probe` lists which APIs and events exist on Forever; the replicate events and addon messages in instances are the unknowns. Real sync needs a second guild member.

Tests: `cd tests && npm install && npm test`. In game: `/dt selftest`.

## Suite structure

Each module is its own addon folder that depends on the core, grouped together in the AddOns list.

```
Interface/AddOns/
  DawnTools/            -- core (required)
  DawnTools_Market/     -- DawnMarket module
  DawnTools_<Next>/     -- future modules
```

**DawnTools (core):**
- Bundles the shared libraries (Ace3: AceAddon, AceComm, AceSerializer/LibSerialize, LibDeflate, ChatThrottleLib, AceDB, AceConfig).
- **Guild comms layer:** one prefix `DAWN`. Each message carries `module, type, protocolVersion`. The core does HELLO/version check once for all modules, and each module registers handlers for its own message types.
- **One main window** with a tab per module (see "Main window and tabs"). One minimap / addon compartment button. Slash commands: `/dt` (alias `/dawntools`) toggles the main window; modules are subcommands (`/dt market`) and may register a short alias (`/dtmarket`). Check at load that no other addon already owns a command; fall back to the long form if so.
- **Module registry:** modules call `DawnTools:RegisterModule(name, {version, onEnable, onMessage, settings, tab})`.

### Main window and tabs

**Opening it:** the DawnTools button (minimap + addon compartment) or `/dt` toggles one main window. Every module lives inside it as a tab, so there are no separate module windows.

**Tabs register themselves.** A module's `tab` field is:
```lua
tab = {
  id = "market",
  title = "Market",
  icon = <texture>,
  defaultOrder = 10,
  create = function(parentFrame) ... end,  -- called the first time the tab is opened (lazy)
  onShow = function() ... end,
  onHide = function() ... end,
}
```
- The core builds the tab bar from every registered module that has a `tab`.
- Installing a new `DawnTools_*` child addon adds its tab automatically; removing the folder removes it.
- The core never hardcodes module names.

**Settings tab:**
- Always present, always last, can't be hidden.
- Contains:
  - **General** (core options)
  - **Tabs:** a list of every registered tab with a visibility checkbox and drag handles (plus up/down arrows as a fallback) to reorder.
  - **One section per module**, built from each module's `settings` table (AceConfig), so modules add their options without touching core code.

**Per-user layout:**
- Tab order and visibility are saved per character in the AceDB profile, with an option to use one account-wide layout.
- New modules appear at their `defaultOrder` the first time they're seen.
- **Hiding a tab only hides the UI.** The module keeps running in the background (e.g. DawnMarket still captures and syncs prices). To fully turn a module off, disable its addon in the AddOns list.

**Window behaviour:**
- Remembers its size, position and last open tab.
- Movable and resizable, closes with Esc.
- `/dt <tabId>` opens straight to that tab (e.g. `/dt market`).
- Module aliases like `/dtmarket` just call `DawnTools:OpenTab("market")`.
- **Shared helpers:** item name index, money formatting, time-ago formatting, debug logging (`/dt debug <module>`).

**Module TOC:**
```
## Title: DawnMarket
## Dependencies: DawnTools
## Group: DawnTools        -- verify Forever supports Group/Category TOC fields
## Category: Auction House
```

- **Grouping in the AddOns list:** the `## Group` and `## Category` TOC fields came with a recent Retail patch. If Forever doesn't support them, fall back to the naming convention (`DawnTools_*`) and a common colour prefix in `## Title`.
- **Load-on-demand later:** heavy modules can be marked LoadOnDemand and loaded by the core when first opened.

**Future module ideas (not v1):** guild recipe directory ("who can craft X"), raid soft-reserve (SR+) tracker, guild bank viewer.

## Environment

- **Game:** WoW: Forever 1.60.1, interface 16001, Mainline (Retail) API, modern AH.
- **API status:** Every API below must be verified on Forever (Phase 0).
- **Optional dependency:** Auctionator.
- **Libraries:** AceComm-3.0, ChatThrottleLib, AceSerializer (or LibSerialize) + LibDeflate.
- **Distribution:** guild only (git repo / zip).
- **Licence:** GPL-3.0-or-later (changed from MIT on 2026-11-14, version 0.15.1, so that GPL data such as QuestieDB's or OneForAll's may be shipped inside the addon). Code or data under a GPL-compatible licence may be copied in, each copy recorded in `THIRD_PARTY_LICENSES.txt`. Copy no code or data from ARR addons (aux, TSM, Auctionator, ForeverFishing, RareScanner); their data may only be read at runtime on the player's machine. Auctionator's source is not read at all. (Rules in full: `AGENTS.md`.)

## Principles

1. **Opt-in and visible.** First launch shows what is shared and asks. A settings toggle turns sharing off at any time. Sharing never runs while it's off.
2. **Never trigger scans.** The addon only records prices from what the player already sees: their own searches, their own full scans, and their local Auctionator data. No hidden ReplicateItems calls, no extra freezes, no stolen scan cooldowns.
3. **Shared data only.** What's shared is item prices, quantities and timestamps, plus the observing character's name, which can be anonymised in settings.
4. **Cheap on bandwidth.** Sync deltas, not databases.

## 1. Price capture (local)

**Sources, in priority order:**
1. **AH search results the player opens:**
   - `COMMODITY_SEARCH_RESULTS_UPDATED`, read with `C_AuctionHouse.GetCommoditySearchResultInfo`
   - `ITEM_SEARCH_RESULTS_UPDATED`, read with `GetItemSearchResultInfo`
   - Record the lowest unit buyout and the total quantity listed.
2. **Full scans the player runs**, through any addon: `REPLICATE_ITEM_LIST_UPDATE`, then `GetReplicateItemInfo`. Record min buyout per item and quantity.
3. **Auctionator, if installed:**
   - `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)` and `GetAuctionAgeByItemID`.
   - Item IDs to query: the watchlist + items in bags + items already in our DB.
   - If Auctionator exposes a DB-update callback (`RegisterForDBUpdate`, to be verified), import after each of its scans.
   - **Fallback:** read Auctionator's saved price table directly. Internal and fragile, so flag it in code and fail quietly if the format changes.

**Per observation:** `itemID, minUnitPrice, quantity, observedAt (server time), observer`.

## 2. Data model

Per item:
- **latest:** minUnitPrice, quantity, observedAt, observer
- **daily:** history for the last 14 days, one entry per day: min, median of observations, max quantity, observation count
- **derived (not stored):** 7-day median, trend (today vs 7-day median), staleness

Storage: account-wide SavedVariables, pruned to 14 days. Cap at ~20k items, dropping the oldest unseen items first.

## 3. Guild sync

- **Transport:** Through the DawnTools core comms layer (AceComm over GUILD, prefix `DAWN`, module `market`). Every message carries the protocol version.
- **HELLO:** sent on login and every 10 minutes. Contains addon version, item count, and newest observedAt.
- **REQUEST since:** I ask the peer with the newest data for observations since my newest timestamp.
- **DATA:** batches of observations, serialised + compressed. Bulk priority through ChatThrottleLib.
- **PUSH:** after a capture event, broadcast only the new observations, batched every 30–60 seconds.
- **Merge:**
  - Per item, the newest `latest` wins.
  - Daily history merges observation counts and recomputes the median.
  - Dedupe on (itemID, observedAt, observer).

**Safety:**
- Reject observations with future timestamps (more than 5 minutes ahead) or older than 14 days.
- **Outlier filter:** with ≥3 data points, ignore an incoming price above 5× or below 0.2× the 7-day median for `latest`. Still count it in history, flagged.
- Per-sender rate limit; drop messages from versions below the minimum supported.
- Pause sync in combat and in instances. Forever runs the Midnight-era addon restrictions, so verify what addon comms are allowed there.

## 4. Market viewer

**Opening:** the "Market" tab in the DawnTools window (`/dt market`, `/dtmarket`, or the DawnTools button). Works anywhere, not only at the AH.

**Search:**
- By name, with prefix match and suggestions as you type.
- Shift-click an item link into the search box.
- Name index built from items seen (cached `GetItemInfo` names), stored locally.
- Category filter: trade goods subtypes, consumables, recipes, gear.

**Results table columns:**
- Item (icon, name, quality colour)
- Last price
- Age ("12m ago", "3h ago"), coloured green < 1h, yellow < 24h, red older
- Qty last seen
- 7-day median
- Trend arrow
- Vendor sell price
- Seen by (or "guild" if anonymised)

Sortable by any column.

**Item detail panel:**
- Price history sparkline for 14 days (texture bars, no external libs)
- Daily min/median table
- Observation count
- "Search at AH" button, active only when the AH is open

**Favourites:** star items. The favourites tab shows them with last price and age.

**Tooltip line on any item:** `Guild AH: 2s 40c (3h ago) · 7d median 2s 10c`.

## 5. Settings

| Setting | Default |
|---|---|
| Share prices with guild | ask on first launch |
| Import from Auctionator | on if installed |
| Show my name as observer | on |
| Tooltip line | on |
| Sync in instances | off |
| History length | 14 days |

**Debug:** `/dt debug market` logs captures and sync traffic.

**Stats panel:** items tracked, observations today, peers seen, last sync.

## 6. Officer/admin (later, optional)

- Minimum version broadcast, to nag outdated users.
- "Who has the addon" list from HELLOs.

## Build phases

0. **Proof of concept:**
   - Verify the search-result events, the replicate APIs and the Auctionator API on Forever.
   - Send/receive a test AceComm message between two guildies.
   - Measure throughput.
   - Check whether Forever honours `## Group` / `## Category` in the TOC.
0.5. DawnTools core skeleton: module registry, comms layer with HELLO/version check, main window with auto-registered tabs, Settings tab with tab visibility + reordering, `/dt`, minimap button.
1. DawnMarket: local capture + data model + tooltip line (solo, no sync).
2. Market viewer (solo data).
3. Guild sync: HELLO / REQUEST / DATA / PUSH, merge, safety filters.
4. Auctionator import.
5. Opt-in flow, settings, stats panel, anonymisation.
6. Small beta with 3–5 guildies for a week, then the whole guild.

## Data layer (from v0.44.0)

The model, sources, licences, stores, what is sent, and the phases are in `docs/DATA.md`. Built so far: `DT.DB`
(`Core/DB.lua`), read-only, answering a first set of relations; `/dt db bench` for the measurements the store
and its sync are sized by. Built from v0.44.0: one local store of rows in chunks (`Core/DBLogic.lua`), loot of every mob and object
counted into it, and the sixth kind of shared data ("what I discover about the game world", anonymous, own
switch, `Core/DBSync.lua`): hashes compared, differing chunks passed by whisper. Decided, not built: the older
stores moved in; base rows imported from installed sources and passed between members; new NPCs and items noted;
a Finds tab.

From v0.45.0 the download holds no recipes and no dungeons: they are rows of the store, written on the machine
that keeps the seed addon (`DawnTools_Seed`, beside the addon, in no repository; `Core/DBSeed.lua`) and passed
on by the guild; `DT.Recipes`, `DT.CraftSkill`, `DT.VendorPrice` and `DT.Dungeons` are put together from the
rows. The import of QuestieDB takes what the tabs use of a thing, not its name alone, and the NPC, Quests,
Items and Zones tabs read QuestieDB or the store through one reader (`DB.Lib()`), so a member without QuestieDB
has them from a guildmate. Where the earlier sections of this page say "read at runtime from QuestieDB, nothing
copied" or "the shipped list", this is what holds now. The work left is in `docs/PLAN-DATA.md`.

## BiS (v0.43.0)

A tab right of Combat, local only (nothing sent).

- **Item stats** are read from the game per item number (`GetItemStats`, then the tooltip's lines for what it leaves out); "Use" and "Chance on hit" lines are not stats. Rating is kept as what it buys (hit, crit, haste, expertise in percent; 10, 14, 10, 10 rating a percent on client 1.60.1).
- **Without gear** = character sheet less the worn gear's stats, for the capped stats. Talents, racials and enchants are in it unnamed. Never read in a fight; kept per character.
- **Profiles** are data, private to the keeper (from the seed addon, never in the repository): weights and caps per spec, with source and client build. Spell hit cap 17%. Weights and caps can be changed per profile on the Weights view.
- **Score**: weight x stat; a capped stat counts its weight up to the cap (from where the character stands without gear) and its "over" value past it. A hard cap (defense 440 for shield tanks) is reached before anything else counts.
- **Solver** (`Core/BisLogic.lua`): exact, slot after slot, keeping the best worth for every amount of the capped stats reached. Two rings, two trinkets and the two hands are one choice each. Checked against trying every combination.
- **Lists** (`Data/BisLists.lua`): item numbers and a source word, by hand. Protection warrior only so far.
- **Gear found**: for every spec, the list or not, the tab looks through the item index (quest rewards, crafted, bind-on-equip drops, vendors) and the dungeon list for gear its class may wear at its level (the last level for another class's spec, by Classic's rules), asks the game for the most promising of them (without loading anything the index gives class, subclass, level and item level: of each armor or weapon type only the best 100 by item level, 60 for weapons, 150 for the rings, necks, trinkets and cloaks that share a type, best of every type first; a plain piece for a slot with few high ones can be missed), 40 a pass at most, again every few seconds, six times, and puts the best six of each place to wear into the best set, beside the list's items. What the game said is kept for good (`db.facts`, as the Items tab keeps its own), so an item is slow once per account. The set and the upgrades are worked out again every few seconds as items come in, and once more when all are looked at; the views say how many are left. A spec that names no hands may not wield two weapons unless its class can.
- **Defaults**: a profile's own weights and caps (the defense cap five lower for each level below the last) are what is used until something is typed on the Weights view; those changes are kept per profile, an empty box or Reset to default puts the shipped values back.
- **Tooltip line**: said for gear the class may wear; names the place it changes (Ring, Trinket, Main hand, Off hand, Two-hand); nothing for what another class wears; nothing asked of the game, and nothing worked out, in a fight.
- **Shown**: Gear (progress bar, cap bars, slot grid), Upgrades (ordered), Weights (editable), Check (what was read, to hold against the game); a tooltip line; a chat line on a roll.
- **Spec**: on first open (nothing picked for this character) the tab shows the class and spec the character is: the talent tree with the most points (`GetTalentTabInfo`, both layouts; else `GetSpecialization`; all guarded) by its place in the class's trees (`BL.TREES`), as the profile named for the tree (`BL.SpecId`); a variant of a tree (threat only, melee weave, the bear) is a click away. Nothing told: the class's first profile. A pick by hand is kept per character and wins.
- **Level**: a stepper on the second row of the header, on the right: `-` level `+` (the number is a box that can be typed in; Enter takes it; clicks and a held button change it, and the candidate list is made anew only once the level has rested a third of a second), 1 to 60, and "My level (N)" beside it where the level looked at is not mine. Default the character's own level. The level drives which items are usable (required level not above it), the lower bound (15 levels below it), the defense cap (five a level) and the defense skill without gear. Items learned stay (`db.facts`). At another level than mine, "trained" armor and weapon skills are not counted (Classic's rules). Another class's spec defaults to the last level.
- **Phase** (only at the last level): a pick-list (`DT:Dropdown`) on the right of the header, one entry for each of `B.PHASES` = `{ id, name, raids }`, raids = `true` or a list of raid names as the dungeon list says them (`Dungeon.IsRaid`). Pre-raid (default; no raid's drops) and Everything. A later tier is one more entry: its name and every raid out by then.
- **Slot list**: one ranked list per slot (`B.Rank`): usable items better than the worn one, best first (as many as fit; "and N more" otherwise), the worn item in its place, about four worse below. Each row: level, **weight**, difference against the worn item in score and in percent of the worn item's weight, and "Source: where exactly" (`B.SourceText`: Owned: bags or bank, Quest: giver and quest, World Drop, Dungeon or Raid: boss, Crafted: profession and skill, Vendor). Weight = what the item adds to the set worn with that slot emptied (a capped stat counts up to the cap and its "over" value past it); difference = the real change to the set's score were it swapped in (a two-hander in the main hand takes the off hand out too), so a row's weight less the worn row's weight is its difference. An empty slot: the difference is all "new", no percent. Two rings or trinkets: compared with the weaker one, and the list says so. No off hand is compared while a two-hander is wielded. Upgrades and the tooltip line count against the best set I own, not the worn one.
- **Whole set** (last level, opens there; a click on a slot shows its list, "Whole set" goes back): the caps first, each as I stand and as the chosen set would (reached, over by how much, short by how much), then every slot with the set's item, what that piece alone would do to the set I wear, where it is from, and its place in the order to buy in: swaps that break no cap I meet now first, the biggest gain first, then those that would take me under a cap (marked, with the piece to get first); the hover says each cap's before and after. Sets (`B.Perm`): What I wear, Best set, Every cap reached (the solver with every cap hard), Owned + 3 best finds (what I own and the three biggest upgrades). One swap at a time is looked at (`B.Swaps`).
- **Look** (Gear): a header band (classes and views; specs on the left, level and phase on the right; the specs shrink to pictures where their names would run into the controls); a fixed column grid for the right side (icon, item, then right-aligned weight, difference and percent, then the source as a coloured kind and the where in grey, in a set a warning column); rows of one height with the alternate tint and hover of the other tabs, the worn item on a quiet gold band between two thin rules; a scroll list (mouse wheel and the thin bar of the NPC tab) wherever it is longer than the panel; cap bars of one height with the label left and the value right, amber short, green reached, blue well over (10% or more), the defense breakdown on a line under its bar and its tooltip.
- **Defense**: shown as base skill / most for the level, plus what gear adds, then the total against the profile's cap: `Defense 298/300 +44 = 342/440` (`UnitDefense`; without it, the skill without gear).
- Open: nothing of it has been seen on Forever. Which sheet functions the client answers, and how its items word their stats, is what the Check view is for.

## Out of scope for v1

- Any buying, posting, sniping or deal-finding.
- Cross-guild or cross-realm sharing; external server or desktop app.
- Guild recipe directory ("who can craft X"). Good v2 candidate; it reuses the same sync layer.
