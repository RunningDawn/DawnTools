-- DawnTools :: Dungeons
-- World > Dungeons: every dungeon with its level range; pick one and its bosses are listed in their order, each
-- with what it drops: the chance where known, how often the guild has seen it drop, and the auction price.
--
-- Where it comes from:
--   the dungeons, bosses and drops   DT.Dungeons: rows of the game database (Core/DBSeed.lua), of the seed addon or of an
--                                    installed OneForAll (GPL-3.0-or-later), whichever is the later version, whole
--   more of them                     the AtlasLootClassic addon where it is installed, read while the game runs
--                                    through its own tables: its raids and whatever the list above lacks, and
--                                    drop chances. Nothing of it is copied, kept or passed on (it is GPL version 2).
--   what was seen to drop            the loot counters of the game database (DB.Looted): every corpse, counted once,
--                                    mine and, once the game database is shared, every member's, added up
--
-- db: picked = the dungeon looked at; mine = only dungeons about my level; side = whose quests ("H", "A", "B")
--     closed[group] = true: a boss (or the quests of a dungeon) folded shut
-- A boss key is its NPC number, or "dungeon/boss" (letters only) where no number is known: such a boss is counted
-- under "bloot:<key>:<origin>" (D.Loot, below), the others by DB.Loot as every mob.

local _, DT = ...
local DB = DT.DB
local D = {}
DT.Dungeon = D

local MODULE = "AtlasLootClassic_DungeonsAndRaids"

local function Clean(text) -- (a name without colour codes or pictures: AtlasLoot puts a badge on some)
	return (tostring(text):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- a name as a key, to tell the same dungeon or boss in two lists: its letters, lower case, without a leading "the"
local function Key(name)
	return (Clean(name):lower():gsub("^the ", ""):gsub("[^%a]", ""))
end
D.Key = Key

-- the raids: the old world's, and Forever's own (AtlasLoot's Forever list): a dungeon of the list, by its key, is one of them or not
local RAIDS = {}
for _, name in ipairs({ "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub", "Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj", "Ahn'Qiraj", "Naxxramas", "Mount Hyjal", "Barrow Deeps Raid", "Barrow Deeps" }) do RAIDS[Key(name)] = true end
function D.IsRaid(d) return d and RAIDS[d.key or Key(d.name or "")] or false end
-- the old world's raids by the number of their zone (the name the game gives a zone is not always the raid's)
D.RAID_AREA = { [2717] = "Molten Core", [2159] = "Onyxia's Lair", [2677] = "Blackwing Lair", [1977] = "Zul'Gurub",
	[3429] = "Ruins of Ahn'Qiraj", [3428] = "Temple of Ahn'Qiraj", [3456] = "Naxxramas" }

-- AtlasLoot's names for a place the list calls otherwise
local ALIAS = { [Key("Sunken Temple")] = "The Temple of Atal'Hakkar" }

-- AtlasLoot's table of dungeons and raids, its module loaded if it is not yet; nil where AtlasLoot is not there
local function Atlas()
	local AL = AtlasLoot
	if not (type(AL) == "table" and AL.ItemDB and AL.ItemDB.Get) then return nil end
	local ok, data = pcall(AL.ItemDB.Get, AL.ItemDB, MODULE)
	if not (ok and type(data) == "table") then
		local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
		if load then pcall(load, MODULE) end
		ok, data = pcall(AL.ItemDB.Get, AL.ItemDB, MODULE)
	end
	return ok and type(data) == "table" and data or nil
end

-- Every dungeon and raid, the lowest first:
--   { key, name, lo, hi, bosses = { { key, name, npc, rare, items = { id, ... }, chance = { [id] = in a hundred } } } }
-- Put together, in this order, from
--   1. the list in the game database (DT.Dungeons, Core/DBSeed.lua);
--   2. the OneForAll addon where it is installed, read while the game runs: a newer one knows bosses and drops
--      the shipped list does not have yet. What it adds is noted (db.adds) to be told to the guild;
--   3. what guild members told of theirs (db.more), where sharing was agreed to;
--   4. the AtlasLootClassic addon where installed, for dungeons and raids none of the above has.
-- Read once a session, and again when the guild tells of more.
local list, byNpc, byKey

-- One boss, or more drops of one, into the list. items = { { id, chance (0: not known) }, ... }.
-- Returns the boss, and those of the items that were news.
local function Put(dname, lo, hi, bname, npc, rare, items)
	local dk = Key(dname)
	if dk == "" then return nil, {} end
	local d = byKey[dk]
	if not d then
		d = { key = dk, name = dname, lo = lo and lo > 0 and lo or nil, hi = hi and hi > 0 and hi or nil, bosses = {} }
		byKey[dk], list[#list + 1] = d, d
	end
	local bk, boss = Key(bname), nil
	for _, b in ipairs(d.bosses) do
		if (npc and b.npc == npc) or Key(b.name) == bk then boss = b break end
	end
	if not boss then
		boss = { name = bname, npc = npc, rare = rare or false, items = {}, chance = {}, has = {}, dungeon = d, key = npc or (dk .. "/" .. bk) }
		-- ("Trash", what the other mobs drop, stays the last of a dungeon)
		local n = #d.bosses
		if n > 0 and d.bosses[n].name == "Trash" and bname ~= "Trash" then table.insert(d.bosses, n, boss) else d.bosses[n + 1] = boss end
		if npc then byNpc[npc] = boss end
	end
	local news = {}
	for _, it in ipairs(items) do
		local id, chance = it[1], it[2] or 0
		if not boss.has[id] then
			boss.has[id], boss.items[#boss.items + 1], news[#news + 1] = true, id, it
		end
		if chance > 0 and not boss.chance[id] then boss.chance[id] = chance end
	end
	return boss, news
end

function D.All()
	if list then return list end
	list, byNpc, byKey = {}, {}, {}
	-- 1. the shipped list
	for _, e in ipairs(DT.Dungeons or {}) do
		for _, b in ipairs(e[4]) do
			local items = {}
			for i = 1, #b[4], 2 do items[#items + 1] = { b[4][i], b[4][i + 1] } end
			Put(e[1], e[2], e[3], b[1], b[2] > 0 and b[2] or nil, b[3] == 1, items)
		end
	end
	-- 2. AtlasLoot, where installed: the dungeons and raids nothing above has
	for key, content in pairs(Atlas() or {}) do
		if type(key) == "string" and key:sub(1, 2) ~= "__" and type(content) == "table" and type(content.items) == "table" then
			local range = type(content.LevelRange) == "table" and content.LevelRange or {}
			-- (AtlasLoot names some only by their zone's number: AQ40 is "TheTempleofAhnQiraj", which no raid's name matches)
			local area = tonumber(content.MapID)
			local ok, areaName = pcall(function() return area and C_Map.GetAreaInfo(area) end)
			areaName = ok and areaName
			local name = area and D.RAID_AREA[area] or type(content.name) == "string" and Clean(content.name)
				or type(areaName) == "string" and areaName ~= "" and areaName or key
			name = ALIAS[Key(name)] or name -- (one place under its other name)
			-- (the same place under another name, "Scarlet Monastery" for its four wings, "Onyxias Lair" twice: known
			-- by a boss that is in the list already)
			local known = false
			for _, boss in ipairs(content.items) do
				local npc = type(boss) == "table" and (type(boss.npcID) == "table" and boss.npcID[1] or boss.npcID)
				known = known or (npc ~= nil and byNpc[npc] ~= nil)
			end
			if not byKey[Key(name)] and not known then
				for _, boss in ipairs(content.items) do
					-- (not its lists of keys, tier sets and the like, which are no boss's drops)
					if type(boss) == "table" and not boss.ExtraList and not boss.IgnoreAsSource then
						-- what it drops: every list it has (the difficulties, the two sides), each item once, in their order
						local items, seen, keys = {}, {}, {}
						for k, v in pairs(boss) do
							if type(k) == "number" and type(v) == "table" then keys[#keys + 1] = k end
						end
						table.sort(keys)
						for _, k in ipairs(keys) do
							for _, entry in ipairs(boss[k]) do
								local id = type(entry) == "table" and entry[2]
								if type(id) == "number" and id > 0 and not seen[id] then seen[id], items[#items + 1] = true, { id, 0 } end
							end
						end
						if items[1] then
							local npc = type(boss.npcID) == "table" and boss.npcID[1] or boss.npcID
							Put(name, tonumber(range[2]), tonumber(range[3]), type(boss.name) == "string" and Clean(boss.name) or "?", type(npc) == "number" and npc or nil, false, items)
						end
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		local x, y = a.lo or 999, b.lo or 999
		if x ~= y then return x < y end
		return a.name < b.name
	end)
	return list
end

-- the boss that drops an item (the first in the list that does; the trash last); nil for none
function D.DropOf(item)
	local trash
	for _, d in ipairs(D.All()) do
		for _, boss in ipairs(d.bosses) do
			if boss.has[item] then
				if boss.name ~= "Trash" then return boss end
				trash = trash or boss
			end
		end
	end
	return trash
end

-- the chance that a boss drops an item, in a hundred: the shipped list's, else AtlasLoot's; nil where neither has one
function D.Chance(boss, item)
	if boss.chance and boss.chance[item] then return boss.chance[item] end
	local rates = boss.npc and AtlasLoot and AtlasLoot.Data and AtlasLoot.Data.Droprate
	if not (rates and rates.GetData) then return nil end
	local ok, chance = pcall(rates.GetData, rates, boss.npc, item)
	return ok and tonumber(chance) or nil
end

---------------------------------------------------------------------------
-- What was seen to drop, and the guild
---------------------------------------------------------------------------

-- How often a boss was looted and each item seen, by me and the guild together (the game database's counters):
--   kills, { [item] = times }
function D.Seen(boss)
	if boss.npc then return DB.Looted("npc", boss.npc) end
	return DB.Looted("boss", boss.key)
end

-- the boss a corpse is: by its NPC number, else (no number known for it) by its name
function D.BossOf(npc, name)
	D.All()
	if npc and byNpc[npc] then return byNpc[npc] end
	if not name then return nil end
	local want = Key(name)
	for _, d in ipairs(list) do
		for _, boss in ipairs(d.bosses) do
			if not boss.npc and boss.name ~= "Trash" and Key(boss.name) == want then return boss end
		end
	end
end

-- Every corpse is counted by DB.Loot (Core/DB.lua): a boss with an NPC number in the list is read back from that
-- count by D.Seen. Left to count here: a boss the list gives no NPC number, told by its name from the target, in a
-- dungeon or raid. Poor and common things (cloth, potions) are not noted: they are no boss's own loot.
-- ponytail: what the window shows me. In a group that rolls, that is all of it; a boss I never open is not counted.
local looted = {} -- [corpse] = true: counted this session
function D.Loot()
	if not (D.db and GetNumLootItems and GetLootSourceInfo) then return end
	local inside, kind = false, nil
	if IsInInstance then inside, kind = IsInInstance() end
	if not inside or (kind ~= "party" and kind ~= "raid") then return end
	local by = {} -- [corpse] = { [item] = true }
	for slot = 1, GetNumLootItems() do
		local guid = GetLootSourceInfo(slot)
		if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
			by[guid] = by[guid] or {}
			local link = GetLootSlotLink and GetLootSlotLink(slot)
			local item = link and tonumber(tostring(link):match("item:(%d+)"))
			local _, _, _, _, quality = GetLootSlotInfo(slot)
			if item and (tonumber(quality) or 0) >= 2 then by[guid][item] = true end
		end
	end
	for guid, items in pairs(by) do
		local npc = tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
		local name = UnitGUID and UnitGUID("target") == guid and UnitName and UnitName("target") or nil
		local boss = D.BossOf(npc, name)
		if boss and not boss.npc and not looted[guid] then
			looted[guid] = true
			DB.Count("bloot", boss.key, items)
			D.Stale()
		end
	end
end

---------------------------------------------------------------------------
-- The tab: the dungeons on the left, the picked one's bosses and their drops on the right
---------------------------------------------------------------------------

local ROW_H, SIDE_W, TOP_H, SIDE_H = 18, 230, 28, 18
-- { title, width (0: to the right edge), right-justified, the line's field: its place, or a key }
local COLS = { { "Boss / item", 290, false, 1 }, { "Slot", 96, false, 2 }, { "Upg", 34, false, "upg" }, { "Type", 104, false, 3 },
	{ "Chance", 64, true, 4 }, { "Seen by the guild", 132, true, 5 }, { "Auction", 0, true, 6 } }
-- a green arrow: an upgrade over my best set, by the BiS tab's reckoning
local UPG = "|TInterface\\Buttons\\Arrow-Up-Up:14:14:0:0:32:32:0:32:0:32:64:255:64|t"
local panel, side, search, note, bar
local rows, sideButtons, heads, lines, offset, sideOffset = {}, {}, {}, {}, 0, 0
local dirty = true
local asked = {} -- [item] = true: its facts were asked of the game this session

function D.Stale()
	dirty = true
end
-- (the list of dungeons was put together anew from the store: Core/DBSeed.lua)
DT:On("DT_DATA_UPDATE", function()
	list = nil
	D.Stale()
end)

-- a dungeon's levels in a colour for my own level (as the Zones tab colours a zone)
local function Levels(d)
	if not d.lo then return "" end
	local text = d.lo == d.hi and tostring(d.lo) or (d.lo .. "-" .. (d.hi or d.lo))
	local Z = DT.Zone
	local color = Z and Z.LevelColor and Z.LevelColor({ lo = d.lo, hi = d.hi or d.lo }, UnitLevel and UnitLevel("player") or 0) or "|cffffffff"
	return color .. text .. "|r"
end

-- the dungeons listed on the left: all of them, or (db.mine) those about my level: not far above me, not long outgrown
local function Listed()
	local all = D.All()
	if not D.db.mine then return all end
	local mine, out = UnitLevel and UnitLevel("player") or 0, {}
	for _, d in ipairs(all) do
		if not d.lo or (mine >= d.lo - 3 and mine <= (d.hi or d.lo) + 5) then out[#out + 1] = d end
	end
	return out
end

local function Picked()
	local all = Listed()
	for _, d in ipairs(all) do
		if d.key == D.db.picked then return d end
	end
	return all[1]
end

local SIDES = { H = "Horde", A = "Alliance", B = "both sides" }

-- The rows of the picked dungeon, group by group: first its quests (of the side picked), then each boss with
-- what it drops, and last, apart, the trash. A group's heading ({ group = key }) folds it shut or open with a
-- click, and that is remembered (db.closed). Under it a line a quest ({ quest = }) or an item ({ item = }).
-- The search box leaves only the items whose name it finds (and the bosses that still have one), folded or not.
local GOLD, BLUE, GREYBAR = { 1, 0.82, 0, 0.10 }, { 0.3, 0.6, 1, 0.12 }, { 1, 1, 1, 0.06 }
local function Rebuild()
	local d, q = Picked(), (search:GetText() or ""):lower()
	lines = {}
	if not d then return end
	local closed = D.db.closed
	local function Fold(key) return (closed[key] and q == "") and "|cffaaaaaa[+]|r " or "|cffaaaaaa[-]|r " end
	-- its quests
	local Q = DT.Quest
	if q == "" and Q and Q.Find then
		local key = "quests:" .. d.key
		if Q.Ready and Q.Ready() then
			-- (the dungeon's quests, and with each the steps that lead up to it; the done ones left out unless asked for)
			local ok, found = pcall(Q.Find, "", { zone = Q.Canon and Q.Canon(d.name) or d.name, side = D.db.side ~= "B" and D.db.side or nil,
				hideDone = D.db.hideDone })
			found = ok and found or {}
			-- (with the done ones go those of another class: neither is anything for this character to do)
			if D.db.hideDone then
				local kept = {}
				for _, r in ipairs(found) do
					if not (r.status == "never" and r.why == "other class") then kept[#kept + 1] = r end
				end
				found = kept
			end
			-- each under the quest that opens it, so a chain reads from its first step down to the dungeon's
			local nested = Q.Nested and Q.Nested(found) or found
			local colors = Q.STATUS_COLOR or {}
			lines[#lines + 1] = { group = key, shade = BLUE, Fold(key) .. ("|cff80c0ffQuests|r  |cff888888%d, for %s%s|r"):format(#found, SIDES[D.db.side] or "both sides",
				D.db.hideDone and "; done ones and other classes' hidden" or ""), "", "", "", "", "" }
			if not closed[key] then
				for _, r in ipairs(nested) do
					-- (in the colour of where it stands: done green, in my log yellow, open white, not yet grey)
					local color, depth = colors[r.status] or "|cffffffff", r.depth or 0
					lines[#lines + 1] = { quest = r.e, depth = depth, status = r.status,
						"    " .. ("    "):rep(math.min(depth, 6)) .. (depth > 0 and "|cff666666> |r" or "") .. ("|cff888888[%d]|r %s%s|r"):format(r.e.level, color, r.e.name),
						color .. (r.why or "") .. "|r", "", "", "", "" }
				end
			end
		else
			lines[#lines + 1] = { "|cff888888Quests: open World, Quests once and they are listed here.|r", "", "", "", "", "" }
		end
	end
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local budget = 60
	for _, boss in ipairs(d.bosses) do
		local kills, seen = D.Seen(boss)
		local trash = boss.name == "Trash"
		-- (the trash stands apart: a line of room, and a heading of another colour)
		if trash and lines[1] then lines[#lines + 1] = { "", "", "", "", "", "" } end
		local at = #lines + 1
		local key = tostring(boss.key)
		lines[at] = { boss = boss, group = key, shade = trash and GREYBAR or GOLD,
			Fold(key) .. (trash and "|cffbbbbbbTrash|r  |cff888888what the other mobs here drop|r" or ("|cffffd100%s|r%s"):format(boss.name, boss.rare and "  |cff80c0ffrare|r" or "")),
			"", "", "", kills > 0 and ("|cffaaaaaalooted %d time%s|r"):format(kills, kills == 1 and "" or "s") or "", "" }
		-- (what was seen to drop and is not in the list is listed after it)
		local ids, listed = {}, {}
		for _, id in ipairs(boss.items) do ids[#ids + 1], listed[id] = id, true end
		local extra = {}
		for id in pairs(seen) do
			if not listed[id] then extra[#extra + 1] = id end
		end
		table.sort(extra)
		for _, id in ipairs(extra) do ids[#ids + 1] = id end
		local kept = 0
		for _, id in ipairs((closed[key] and q == "") and {} or ids) do
			local name, _, quality, _, _, kind, sub, _, slot, icon = info(id)
			-- (one the game has not told us about yet: asked for once a session, a batch a pass)
			if not name and budget > 0 and not asked[id] and C_Item and C_Item.RequestLoadItemDataByID then
				budget, asked[id] = budget - 1, true
				pcall(C_Item.RequestLoadItemDataByID, id)
			end
			local shown = name or ("item " .. id)
			if q == "" or shown:lower():find(q, 1, true) then
				kept = kept + 1
				local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
				local chance = D.Chance(boss, id)
				local price = DawnMarket and DawnMarket.API.GetLatest and DawnMarket.API.GetLatest(id)
				local times = seen[id] or 0
				lines[#lines + 1] = { item = id, name = shown, upg = DT.Bis and DT.Bis.IsUpgrade and DT.Bis.IsUpgrade(id) and UPG or nil,
					"    " .. (icon and ("|T%s:14|t "):format(icon) or "") .. color .. shown .. "|r" .. (not listed[id] and "  |cff66ccffseen by the guild|r" or ""),
					slot and slot ~= "" and (_G[slot] or slot) or "", sub or kind or "",
					chance and ("%s%%"):format(chance % 1 == 0 and ("%d"):format(chance) or ("%.1f"):format(chance)) or "|cff888888-|r",
					kills > 0 and ("%d of %d  |cff888888(%d%%)|r"):format(times, kills, math.floor(times / kills * 100 + 0.5)) or "|cff888888-|r",
					price and DT.Money(price) or "" }
			end
		end
		if kept == 0 and q ~= "" then
			lines[at] = nil
			if trash and lines[at - 1] and lines[at - 1][1] == "" then lines[at - 1] = nil end
		end
	end
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", SIDE_W + 8, -TOP_H - ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -12, 0)
	row.shade = row:CreateTexture(nil, "BACKGROUND")
	row.shade:SetAllPoints()
	row.shade:SetColorTexture(1, 0.82, 0, 0.10)
	row.dcols = {}
	local x = 0
	for c, col in ipairs(COLS) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", x, 0)
		if col[2] > 0 then fs:SetWidth(col[2] - 6) else fs:SetPoint("RIGHT", 0, 0) end
		fs:SetJustifyH(col[3] and "RIGHT" or "LEFT")
		fs:SetWordWrap(false)
		row.dcols[c] = fs
		x = x + col[2]
	end
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if d.item then
			GameTooltip:SetHyperlink("item:" .. d.item)
			GameTooltip:AddLine("Shift-click: link in chat. Shift-right-click: its web page. Hold Shift: compare.", 0.5, 0.8, 1)
			DT.Favs.Hint(GameTooltip, d.item)
			GameTooltip:Show()
			DT:CompareTip(self)
		elseif d.quest then
			if DT.Quest and DT.Quest.Tooltip then DT.Quest.Tooltip(self, d.quest) end
		elseif d.group then
			GameTooltip:AddLine(d.boss and d.boss.name or "Quests")
			GameTooltip:AddLine("Click: fold it shut, or open again.", 0.5, 0.8, 1)
			if d.boss and d.boss.name ~= "Trash" then
				GameTooltip:AddLine(d.boss.npc and "Right-click: a waypoint to it (the door of its dungeon)." or "Where it stands is not known.", 0.5, 0.8, 1)
			end
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self, button)
		local d = self.data
		if not d then return end
		if d.item then
			DT:LinkClick(button, DT:GameItemLink(d.item, d.name), d.name, DT:ItemLink(d.item), d.item)
		elseif d.quest then
			if DT.Quest and DT.Quest.ShowChain then DT.Quest.ShowChain(d.quest) end
		elseif d.group then
			-- (a heading: a right-click on a boss is a waypoint to it; any other click folds the group)
			if button == "RightButton" and d.boss and d.boss.npc and DT.Npc and DT.Npc.Waypoint then
				DT.Npc.Waypoint({ id = d.boss.npc, name = d.boss.name, zone = 0 })
			else
				D.db.closed[d.group] = not D.db.closed[d.group] or nil
				D.Refresh()
			end
		end
	end)
	rows[i] = row
	return row
end

local function SideButton(i)
	local b = CreateFrame("Button", nil, side)
	b:SetHeight(SIDE_H)
	b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * SIDE_H)
	b:SetPoint("RIGHT", -2, 0)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(1, 0.82, 0, 0.18)
	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", 6, 0)
	b.label:SetPoint("RIGHT", -46, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetWordWrap(false)
	b.levels = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.levels:SetPoint("RIGHT", -4, 0)
	b:SetScript("OnClick", function(self)
		if not self.dungeon then return end
		D.db.picked, offset = self.dungeon.key, 0
		D.Refresh()
	end)
	sideButtons[i] = b
	return b
end

-- scrolled = only the window moved: the lines are not worked out again (they ask the quest list and every item)
function D.Refresh(scrolled)
	if not panel then return end
	local all = Listed()
	if scrolled ~= true then
		dirty = false
		Rebuild()
	end
	local picked = Picked()
	-- the dungeons
	local sfit = math.max(1, math.floor((panel:GetHeight() - 6) / SIDE_H))
	sideOffset = math.max(0, math.min(sideOffset, #all - sfit))
	for i = 1, math.max(sfit, #sideButtons) do
		local d = i <= sfit and all[i + sideOffset] or nil
		local b = sideButtons[i] or (d and SideButton(i))
		if b then
			b.dungeon = d
			b:SetShown(d ~= nil)
			if d then
				b.label:SetText(d.name)
				b.levels:SetText(Levels(d))
				b.sel:SetShown(d == picked)
			end
		end
	end
	-- its bosses and what they drop
	local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H - ROW_H) / ROW_H))
	local max = math.max(0, #lines - fit)
	offset = math.max(0, math.min(offset, max))
	bar:SetMinMaxValues(0, max)
	bar:SetValue(offset)
	bar:SetShown(max > 0)
	bar.thumb:SetSize(8, math.max(16, fit * ROW_H * fit / math.max(fit, #lines)))
	for i = 1, math.max(fit, #rows) do
		local d = i <= fit and lines[offset + i]
		local row = rows[i] or (d and MakeRow(i))
		if row then
			row.data = d or nil
			row:SetShown(d and true or false)
			row.shade:SetShown(d and d.shade and true or false)
			if d and d.shade then row.shade:SetColorTexture(d.shade[1], d.shade[2], d.shade[3], d.shade[4]) end
			for c, cell in ipairs(row.dcols) do cell:SetText(d and d[COLS[c][4]] or "") end
		end
	end
	D.mineBox:SetChecked(D.db.mine and true or false)
	D.doneBox:SetChecked(D.db.hideDone and true or false)
	D.sideButton:SetText("Quests: " .. (SIDES[D.db.side] or "both sides"))
	local items = 0
	for _, d in ipairs(lines) do items = items + (d.item and 1 or 0) end
	note:SetText(picked and ("%s%s: %d bosses, %d drops listed"):format(picked.name, picked.lo and ("  |cff888888levels|r %s"):format(Levels(picked)) or "", #picked.bosses, items)
		or "|cff888888No dungeons known yet. DawnTools does not come with them: they reach you from guild members, with the game database shared (/dt db).|r")
end

local function Show()
	D.Refresh()
end

local function Build(parent)
	panel = parent
	side = CreateFrame("Frame", nil, panel)
	side:SetPoint("TOPLEFT", 0, -2)
	side:SetPoint("BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDE_W)
	local shade = side:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, 0.04)
	side:EnableMouseWheel(true)
	side:SetScript("OnMouseWheel", function(_, delta)
		sideOffset = sideOffset - delta * 3
		D.Refresh(true)
	end)

	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("TOPLEFT", SIDE_W + 16, -3)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function() -- (hooked: the template's own handler shows the "Search" hint)
		offset, dirty = 0, true
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	D.search = search
	note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("LEFT", search, "RIGHT", 12, 0)
	note:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	note:SetJustifyH("LEFT")
	note:SetWordWrap(false)
	D.note = note
	-- what to list: only the dungeons about my level; the quests of which side
	D.mineBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	D.mineBox:SetSize(22, 22)
	D.mineBox:SetPoint("LEFT", search, "RIGHT", 8, 0)
	D.mineBox.label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	D.mineBox.label:SetPoint("LEFT", D.mineBox, "RIGHT", 0, 0)
	D.mineBox.label:SetText("My level range")
	D.mineBox:SetScript("OnClick", function(self)
		D.db.mine, sideOffset, offset = self:GetChecked() and true or false, 0, 0
		D.Refresh()
	end)
	D.mineBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Only the dungeons about your level: none far above you, none long outgrown.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	D.mineBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	D.sideButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	D.sideButton:SetSize(150, 22)
	D.sideButton:SetPoint("LEFT", D.mineBox.label, "RIGHT", 10, 0)
	D.sideButton:SetScript("OnClick", function()
		D.db.side = D.db.side == "H" and "A" or D.db.side == "A" and "B" or "H"
		offset = 0
		D.Refresh()
	end)
	D.sideButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Which side's quests a dungeon lists: Horde, Alliance, or both. A click goes to the next.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	D.sideButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	D.doneBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	D.doneBox:SetSize(22, 22)
	D.doneBox:SetPoint("LEFT", D.sideButton, "RIGHT", 8, 0)
	D.doneBox.label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	D.doneBox.label:SetPoint("LEFT", D.doneBox, "RIGHT", 0, 0)
	D.doneBox.label:SetText("Hide done quests")
	D.doneBox:SetScript("OnClick", function(self)
		D.db.hideDone, offset = self:GetChecked() and true or false, 0
		D.Refresh()
	end)
	D.doneBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Leaves out the quests you have done, and those of another class. Unticked, done ones are listed in green; one in your log is yellow.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	D.doneBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	note:ClearAllPoints()
	note:SetPoint("LEFT", D.doneBox.label, "RIGHT", 12, 0)
	note:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

	local x = SIDE_W + 8
	for c, col in ipairs(COLS) do
		local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", x, -TOP_H - 2)
		if col[2] > 0 then h:SetWidth(col[2] - 6) else h:SetPoint("RIGHT", panel, "RIGHT", -12, 0) end
		h:SetJustifyH(col[3] and "RIGHT" or "LEFT")
		h:SetText("|cffffd100" .. col[1] .. "|r")
		heads[c] = h
		x = x + col[2]
	end

	bar = CreateFrame("Slider", nil, panel)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(8)
	bar:SetPoint("TOPRIGHT", -1, -TOP_H - ROW_H)
	bar:SetPoint("BOTTOMRIGHT", -1, 2)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.3)
	bar.thumb = bar:CreateTexture(nil, "OVERLAY")
	bar.thumb:SetColorTexture(0.78, 0.68, 0.37, 0.9)
	bar:SetThumbTexture(bar.thumb)
	bar:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value + 0.5)
		if value == offset then return end -- (Refresh sets the bar too)
		offset = value
		D.Refresh(true)
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		D.Refresh(true)
	end)
	panel:SetScript("OnSizeChanged", D.Refresh)
	local nextUpdate = 0
	DT.OnUpdate(panel, "tab: Dungeons", function()
		if not dirty or GetTime() < nextUpdate then return end
		if InCombatLockdown and InCombatLockdown() then return end -- (in a fight the lists wait)
		nextUpdate = GetTime() + 0.5
		D.Refresh()
	end)
end

-- The tab's own saved counts moved into the game database (once; the saved file of before has db.seen[boss key] =
-- { k = times looted, t, items = { [item] = times } } and db.guild[member name][boss key] = the same).
-- db.seen becomes this install's counters: the larger of it and what DB.Loot counted of the same boss (which has
-- counted every corpse as well since 0.44), per item too: nothing is counted twice, and a second run changes
-- nothing. A boss with no NPC number goes to "bloot:<dungeon/boss>". db.guild is keyed by names, which the store
-- never holds: it is dropped, and comes back by sync. The list sharing's leavings (db.adds, db.more, db.peers,
-- db.listPeers) go too: an installed OneForAll is a source of the store now (Core/DBSeed.lua).
function D.Migrate(db)
	for key, s in pairs(type(db.seen) == "table" and db.seen or {}) do
		local n = type(s) == "table" and tonumber(s.k) or 0
		if n >= 1 and n < 1e6 then
			local items = {}
			for item, k in pairs(type(s.items) == "table" and s.items or {}) do
				item, k = tonumber(item), tonumber(k)
				if item and item > 0 and k and k >= 1 then items[item] = math.min(k, n) end
			end
			local npc = tonumber(key)
			if npc and npc > 0 and npc == math.floor(npc) then
				DB.Raise("loot", ("%d"):format(npc), n, items)
			elseif type(key) == "string" and key:find("^%a+/%a+$") then
				DB.Raise("bloot", key, n, items)
			end
		end
	end
	db.seen, db.guild, db.adds, db.more, db.peers, db.listPeers = nil, nil, nil, nil, nil, nil
	db.moved = true
end

-- how many bosses (not the trash) were looted, as counted by me and the guild, of all there are
local function Looted()
	local all, looted = 0, 0
	for _, d in ipairs(D.All()) do
		for _, boss in ipairs(d.bosses) do
			if boss.name ~= "Trash" then
				all = all + 1
				if D.Seen(boss) > 0 then looted = looted + 1 end
			end
		end
	end
	return looted, all
end

DT:RegisterModule("dungeon", {
	profile = { "picked", "mine", "side", "closed", "hideDone" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "Dungeons",
	version = 1,
	slash = "/dtdungeon",
	tab = { id = "dungeon", title = "Dungeons", defaultOrder = 59.5, under = "world", create = Build, onShow = Show },
	onEnable = function(mod)
		local db = mod.db
		if db.seen or db.guild or db.adds or db.more or db.peers or db.listPeers then
			local ok, err = pcall(D.Migrate, db)
			if not ok then geterrorhandler()(err) end -- (what was not moved is still there for the next login)
		end
		db.closed = db.closed or {}
		if db.hideDone == nil then db.hideDone = true end -- (done quests are left out, to begin with)
		-- (the quests of my own side, to begin with)
		if db.side ~= "H" and db.side ~= "A" and db.side ~= "B" then db.side = UnitFactionGroup and UnitFactionGroup("player") == "Alliance" and "A" or "H" end
		D.db = db
		for _, event in ipairs({ "LOOT_READY", "LOOT_OPENED" }) do
			DT:On(event, function() pcall(D.Loot) end)
		end
		-- (an item's name and facts arrived: only for one this tab asked about)
		DT:On("GET_ITEM_INFO_RECEIVED", function(item) if asked[item] then dirty = true end end)
	end,
	held = function()
		local looted = Looted()
		return ("the loot of %d bosses, counted by you and the guild (in the game database)"):format(looted)
	end,
	progress = function()
		local looted, all = Looted()
		return { { "Dungeon bosses whose loot was seen", looted, all, "by you or the guild" } }
	end,
	selfTest = function(_, Try)
		Try("dungeon list", function() return D.All() end)
	end,
})
