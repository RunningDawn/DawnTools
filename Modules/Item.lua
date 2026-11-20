-- DawnItem
-- Every item of the game: to search through as in the auction house, to see where one comes from, and to
-- filter gear by what is on it.
-- As with NPCs and quests the list is read at runtime from the QuestieDB addon where that is installed, without
-- it from DawnTools' own game database (DT.DB.Lib): name, levels, kind, and the sources (who drops it, who
-- sells it, which quest gives it).
--
-- What QuestieDB does not have (quality, where it is worn, its stats, its Equip / Use lines) only the game
-- knows, and only once it has loaded the item. Those facts never change, so each item is asked for once and
-- what comes back is kept for good (db.known): the second look at anything is instant.

local _, DT = ...
local I = {}
DT.Item = I

-- db.known[itemID] = { v = 2, q = quality, e = where it is worn ("INVTYPE_HEAD", "" for not worn), s = { sta = 11, ... },
--                      x = its Equip / Use / Chance-on-hit lines, lower case,
--                      rs, rn = the skill it asks for and how high ("Blacksmithing", 125), nil for none }
--                      (shared by all profiles; v: an entry of an older shape is learned anew)
-- db: min, max (required level), quality (at least), usable, source, stats (the text of the box), class, group, leaf

I.BATCH = 200
local FIELDS = { "name", "requiredLevel", "itemLevel", "class", "subClass", "npcDrops", "objectDrops", "itemDrops", "vendors",
	"questRewards", "startQuest", "teachesSpell" }
local SOURCES = { "Drop", "Chest", "Container", "Vendor", "Quest reward", "Starts a quest", "Crafted" }
local QUALITIES = { { nil, "Any quality" }, { 1, "Common and better" }, { 2, "Uncommon and better" }, { 3, "Rare and better" }, { 4, "Epic and better" } }
I.CAP = 3000      -- more unknown items than this are not asked for without a word
local ASK = 150    -- items asked of the game per pass

-- the game's names for what is on gear -> the short words of the Stats box
local STAT_KEYS = {
	ITEM_MOD_STAMINA_SHORT = "sta", ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STRENGTH_SHORT = "str",
	ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor", ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_SPELL_POWER_SHORT = "sp",
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal", ITEM_MOD_HIT_RATING_SHORT = "hit",
	ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_DODGE_RATING_SHORT = "dodge", ITEM_MOD_PARRY_RATING_SHORT = "parry",
	ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
	ITEM_MOD_HEALTH_REGEN_SHORT = "hp5", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", RESISTANCE2_NAME = "fire", RESISTANCE3_NAME = "nature",
	RESISTANCE4_NAME = "frost", RESISTANCE5_NAME = "shadow", RESISTANCE6_NAME = "arcane",
}
-- other ways to write them
local ALIAS = { stam = "sta", stamina = "sta", intellect = "int", agility = "agi", strength = "str", spirit = "spi", armour = "armor",
	attackpower = "ap", spellpower = "sp", spelldamage = "sp", healing = "heal", critical = "crit", defense = "def", defence = "def" }
-- where a stat is not among the game's numbers (on old-world gear "hit" is an Equip line): the words to find
-- it by in those lines, and the number beside them is its value
local IN_TEXT = { hit = "to hit", crit = "critical", dodge = "dodge", parry = "parry", block = "block", def = "defense", mp5 = "mana per 5",
	hp5 = "health per 5", sp = "spells", heal = "healing", ap = "attack power" }

local index = {}
I.rewards = {} -- [quest] = { item entry, ... }: what a quest gives, turned round from each item's "reward of"
local reading
local ready, missing = false, false
local fromStore, stale = false, false -- read from DawnTools' own database; which has changed since
local dirty = true
local catalog -- the kinds of item there are, their groups, and the items of each group

---------------------------------------------------------------------------
-- Reading QuestieDB (or the store, which answers the same way)
---------------------------------------------------------------------------

local function Lib()
	local lib = DT.DB.Lib()
	if not (lib and lib.Item and lib.Item.GetAllIds and lib.Item.GetAll) then return end
	return lib
end

local function Any(list)
	return type(list) == "table" and next(list) ~= nil
end

-- "made by a recipe", where AtlasLoot is there to say so
local function Crafted(id)
	local fn = AtlasLoot and AtlasLoot.Data and AtlasLoot.Data.Profession and AtlasLoot.Data.Profession.GetCraftSpellForCreatedItem
	if not fn then return false end
	local ok, spell = pcall(fn, id)
	return ok and spell and true or false
end

local function Entry(id, v)
	local e = { id = id, name = v[1], nameL = v[1]:lower(), req = v[2] or 0, ilvl = v[3] or 0, c = v[4] or 15, s = v[5] or 0, src = {} }
	if Any(v[6]) then e.src.Drop = true end
	if Any(v[7]) then e.src.Chest = true end
	if Any(v[8]) then e.src.Container = true end
	if Any(v[9]) then e.src.Vendor = true end
	if Any(v[10]) then
		e.src["Quest reward"] = true
		for _, quest in pairs(v[10]) do
			if type(quest) == "number" then
				I.rewards[quest] = I.rewards[quest] or {}
				table.insert(I.rewards[quest], e)
			end
		end
	end
	if (v[11] or 0) > 0 then e.src["Starts a quest"] = true end
	if Crafted(id) then e.src.Crafted = true end
	e.teaches = (v[12] or 0) > 0 and v[12] or nil
	local names = {}
	for _, s in ipairs(SOURCES) do
		if e.src[s] then names[#names + 1] = s end
	end
	e.srcText = table.concat(names, ", ")
	e.hay = (e.name .. " " .. e.srcText):lower()
	return e
end

local function ReadAll(lib)
	local ids = lib.Item.GetAllIds()
	local stop = debugprofilestop and debugprofilestop() + (I.budget or 8)
	fromStore = lib.store == true
	for i, id in ipairs(ids) do
		local ok, v = pcall(lib.Item.GetAll, id, FIELDS)
		if ok and v and type(v[1]) == "string" and v[1] ~= "" then
			local made, e = pcall(Entry, id, v) -- (one odd record is left out, not the end of the reading)
			if made then index[#index + 1] = e end
		end
		I.progress = i / #ids
		if (stop and debugprofilestop() > stop) or (not stop and i % I.BATCH == 0) then
			coroutine.yield()
			stop = debugprofilestop and debugprofilestop() + (I.budget or 8)
		end
	end
	ready = true
end

function I.Start()
	-- (read from the store, which has more now, or was empty: read anew)
	if stale and not reading then
		index, I.rewards, catalog = {}, {}, nil
		ready, missing, stale, dirty = false, false, false, true
	end
	if not ready and not reading and not missing then
		local lib = Lib()
		if lib then
			reading = coroutine.create(function() ReadAll(lib) end)
		else
			missing = true
		end
	end
	return reading ~= nil
end

function I.Step(ms)
	if not reading then return true end
	I.budget = ms
	local ok, err = coroutine.resume(reading)
	if not ok then
		DT:Debug("item", "reading stopped: %s", tostring(err))
		ready = true -- (what was read is what there is: not begun again on top of itself)
	end
	if coroutine.status(reading) == "dead" then reading = nil end
	return reading == nil
end

function I.Ready()
	return ready
end

function I.All()
	return index
end

---------------------------------------------------------------------------
-- What only the game knows of an item: asked once, kept for good
---------------------------------------------------------------------------

local asked, waiting = {}, {} -- [itemID] = times asked; = when the last asking was, while its answer is due
local partial = {}            -- [itemID] = facts of an item whose tooltip never came whole: good for this session only
-- an item the game never delivers (QuestieDB knows some the game does not): asked three times, then left alone
local function GaveUp(id)
	return (asked[id] or 0) >= 3 and not waiting[id]
end
-- what is kept of an item, if it is of the shape in use
local function Kept(id)
	local k = I.db.known[id]
	if k and k.v == 2 then
		k.s, k.x = k.s or {}, k.x or "" -- (empty ones are not written to the saved file)
		return k
	end
	return partial[id]
end
local redraw = false
local function Later()
	if redraw then return end
	redraw = true
	C_Timer.After(1.5, function() redraw, dirty = false, true end)
end

-- "Requires Blacksmithing (125)", in the game's own words
local SKILL_LINE = (ITEM_MIN_SKILL or "Requires %s (%d)"):gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
SKILL_LINE = "^" .. SKILL_LINE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
local FACTS = 2 -- (the shape of a kept entry: see db.known)

-- What an item's tooltip says: { x = its Equip / Use / Chance-on-hit lines (lower case, one per line),
-- skill, rank = what it asks for, learned = "Already known" stands on it }; nil while the tooltip is not all there
local function Tooltip(id)
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return { x = "" } end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
	local lines = ok and data and data.lines
	if not lines or #lines < 1 then return nil end
	local out, tip = {}, {}
	local starts = { ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:", ITEM_SPELL_TRIGGER_ONUSE or "Use:", ITEM_SPELL_TRIGGER_ONPROC or "Chance on hit:" }
	for _, line in ipairs(lines) do
		local text = line.leftText
		if type(text) == "string" then
			if RETRIEVING_ITEM_INFO and text == RETRIEVING_ITEM_INFO then return nil end
			for _, s in ipairs(starts) do
				if text:sub(1, #s) == s then out[#out + 1] = text:lower() end
			end
			local skill, rank = text:match(SKILL_LINE)
			if skill then tip.skill, tip.rank = skill, tonumber(rank) end
			if text == (ITEM_SPELL_KNOWN or "Already known") then tip.learned = true end
		end
	end
	tip.x = table.concat(out, "\n")
	return tip
end

-- Whether this character already knows what an item teaches (a recipe, a pet). That is about the character,
-- so it is not kept with the item: found out once a session, and anew after a recipe is learned.
local learned = {}
local function Learned(id)
	if learned[id] ~= nil then return learned[id] end
	local tip = Tooltip(id)
	if not tip then return nil end
	learned[id] = tip.learned or false
	return learned[id]
end

-- the facts of an item, or nil while the game has not loaded it (it is then asked for, three times at most)
function I.Know(id)
	local k = Kept(id)
	if k then return k end
	local name, _, quality, _, _, _, _, _, slot = C_Item.GetItemInfo(id)
	local tip = name and Tooltip(id)
	if not name or (tip == nil and (asked[id] or 0) < 3) then
		if waiting[id] and GetTime() - waiting[id] > 8 then waiting[id] = nil end -- (no answer came: not waited for for ever)
		if not waiting[id] and (asked[id] or 0) < 3 then
			asked[id], waiting[id] = (asked[id] or 0) + 1, GetTime()
			C_Item.RequestLoadItemDataByID(id)
		end
		return nil
	end
	local whole = tip ~= nil
	tip = tip or { x = "" }
	k = { v = FACTS, q = quality or 1, e = slot or "", s = {}, x = (tip.x or ""):sub(1, 400), rs = tip.skill, rn = tip.rank }
	if tip.learned ~= nil or tip.x then learned[id] = tip.learned or false end
	local get = (C_Item and C_Item.GetItemStats) or GetItemStats
	local ok, stats = pcall(function() return get and get("item:" .. id) end)
	for key, value in pairs(ok and type(stats) == "table" and stats or {}) do
		local short = STAT_KEYS[key]
		if short and type(value) == "number" then
			k.s[short] = (k.s[short] or 0) + value
		elseif type(value) == "number" and type(_G[key]) == "string" then
			k.x = k.x .. "\n" .. _G[key]:lower() -- (one of the game's we have no short word for: findable by its name)
		end
	end
	-- (kept for good only when its tooltip was all there: half a tooltip would be believed for ever)
	if whole then I.db.known[id] = k else partial[id] = k end
	return k
end

-- how much of a stat an item has: among the game's numbers, else read from its Equip lines; nil for none
function I.Stat(k, stat)
	if k.s[stat] then return k.s[stat] end
	local words = IN_TEXT[stat]
	if not words then return nil end
	for line in k.x:gmatch("[^\n]+") do
		if line:find(words, 1, true) then return tonumber(line:match("(%d+%.?%d*)")) or 0 end
	end
end

-- "sta>11 int>=5 hit" -> { { stat = "sta", op = ">", n = 11 }, ..., { word = "hit", stat = "hit" } }
function I.ParseStats(text)
	local out = {}
	for token in tostring(text or ""):lower():gmatch("%S+") do
		local name, op, n = token:match("^([%a%d]+)([<>=]+)(%d+%.?%d*)$")
		if name and (op == ">" or op == "<" or op == ">=" or op == "<=" or op == "=") then
			out[#out + 1] = { stat = ALIAS[name] or name, op = op, n = tonumber(n) }
		else
			local word = token:gsub("[<>=].*$", "")
			if word ~= "" then out[#out + 1] = { word = word, stat = ALIAS[word] or word } end
		end
	end
	return out
end

local function Holds(k, wants)
	for _, w in ipairs(wants) do
		local have = I.Stat(k, w.stat)
		if w.op then
			if not have then return false end
			local ok = (w.op == ">" and have > w.n) or (w.op == "<" and have < w.n) or (w.op == ">=" and have >= w.n)
				or (w.op == "<=" and have <= w.n) or (w.op == "=" and have == w.n)
			if not ok then return false end
		elseif not (have and have > 0) and not k.x:find(w.word, 1, true) then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Finding
---------------------------------------------------------------------------

local function Cat()
	return DT.Market.View.cat
end

-- The items that fit, best first: { e = entry, score = }, and how the learning stands:
-- { unknown = items the game has not told us about yet, of = candidates, capped = too many to ask for }
function I.Find(text, f)
	local words = {}
	for word in text:lower():gmatch("%S+") do words[#words + 1] = word end
	local cat = Cat()
	local level = UnitLevel and UnitLevel("player") or 0
	local who = f.usable and DT.Market.View.Character(level) or nil
	local pool = {}
	for _, e in ipairs(index) do
		local ok = (not f.min or e.req >= f.min) and (not f.max or e.req <= f.max) and (not f.source or e.src[f.source])
			and (not f.class or e.c == f.class)
		if ok and f.class and f.group ~= nil then ok = (cat.Place({ c = e.c, s = e.s, e = "" })) == f.group end
		if ok and who then ok = e.req <= level and DT.Market.View.MayUse(e.c, e.s, who) end
		if ok then pool[#pool + 1] = e end
	end
	local found = DT.Npc.Match(pool, words)
	-- What needs the game's own facts: quality, where it is worn, stats. And "usable" beyond level and kind:
	-- the skill an item asks for ("Requires Blacksmithing (125)") against mine, and whether I already know
	-- what it teaches.
	local wants = I.ParseStats(f.stats)
	local state = { unknown = 0, of = #found }
	if not (f.quality or f.leaf ~= nil or wants[1] or who) then return found, state end
	local known = setmetatable({}, { __index = function(_, id) return Kept(id) end })
	for _, r in ipairs(found) do
		if not known[r.e.id] and not GaveUp(r.e.id) then state.unknown = state.unknown + 1 end
	end
	state.capped = state.unknown > I.CAP and not I.force
	local out, budget, pendingLearned = {}, ASK, 0
	for _, r in ipairs(found) do
		local k = known[r.e.id]
		if not k and not state.capped and budget > 0 and not GaveUp(r.e.id) then
			budget = budget - 1
			k = I.Know(r.e.id)
		end
		if k then
			local fits = (not f.quality or k.q >= f.quality) and (f.leaf == nil or select(2, cat.Place({ c = r.e.c, s = r.e.s, e = k.e })) == f.leaf)
				and (not wants[1] or Holds(k, wants))
			if fits and who then
				-- the skill it asks for, that high (where the game lists my skills)
				if k.rs and who.profs and (who.profs[k.rs] or -1) < (k.rn or 0) then fits = false end
				-- a recipe (or the like) I already know is of no use to me
				if fits and (r.e.c == 9 or r.e.c == 15) then
					-- (a tooltip each, the first time in a session: a batch per pass, like the rest)
					local mine = learned[r.e.id]
					if mine == nil and budget > 0 then
						budget = budget - 1
						mine = Learned(r.e.id)
					end
					if mine == nil then pendingLearned = pendingLearned + 1 end
					if mine ~= false then fits = false end
				end
			end
			if fits then out[#out + 1] = r end
		end
	end
	state.unknown = pendingLearned
	for _, r in ipairs(found) do
		if not known[r.e.id] and not GaveUp(r.e.id) then state.unknown = state.unknown + 1 end
	end
	return out, state
end

---------------------------------------------------------------------------
-- Where an item comes from
---------------------------------------------------------------------------

local LISTED = 12
-- lines for the detail window: { text =, npc = id / quest = id (what a click does) }, headed by kind
function I.Sources(e)
	local DBx, out = DT.DB, {}
	if not Lib() then return out end
	local function Zone(area)
		return area and area > 0 and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area) or nil
	end
	-- (facts: what DT.DB says, see Core/DB.lua; line: a fact as a line of the window)
	local function Block(title, facts, line)
		if not facts[1] then return end
		out[#out + 1] = { head = ("%s (%d)"):format(title, #facts) }
		for i = 1, math.min(LISTED, #facts) do out[#out + 1] = line(facts[i]) end
		if #facts > LISTED then out[#out + 1] = { text = ("|cff888888and %d more|r"):format(#facts - LISTED) } end
	end
	local function Npc(fact)
		local npc = DBx.Get("npc", fact.id) or {}
		local zone, min, max = Zone(npc.zone), npc.min, npc.max
		local level = max and max > 0 and (min == max and (" |cff888888level " .. max .. "|r") or (" |cff888888level " .. (min or max) .. "-" .. max .. "|r")) or ""
		local name = npc.name or ("NPC " .. fact.id)
		return { text = name .. level .. (zone and ("  |cff6699cc" .. zone .. "|r") or ""), npc = fact.id, name = name }
	end
	local drops = DBx.RelTo("drops", "item", e.id)
	-- (a dungeon boss: with its chance, the stated one and what was seen)
	Block("Dungeon bosses", DBx.Only(drops, "npc", "shipped"), function(fact)
		local chance = DBx.ChanceText(fact)
		return { text = ("%s  |cff6699cc%s|r%s"):format(fact.boss, fact.dungeon, chance ~= "" and ("  |cffffd100" .. chance .. "|r") or ""), npc = fact.id, name = fact.boss }
	end)
	Block("Dropped by", DBx.Only(drops, "npc", "questie"), Npc)
	Block("Sold by", DBx.Only(DBx.RelTo("sells", "item", e.id), "npc", "questie"), Npc)
	Block("Found in", DBx.Only(drops, "object", "questie"), function(fact)
		local object = DBx.Get("object", fact.id) or {}
		local zone = Zone(object.zone)
		return { text = (object.name or ("object " .. fact.id)) .. (zone and ("  |cff6699cc" .. zone .. "|r") or "") }
	end)
	Block("Inside", DBx.Only(drops, "item", "questie"), function(fact)
		return { text = DBx.Q("item", fact.id, "name") or ("item " .. fact.id) }
	end)
	local function Quest(fact)
		return { text = DBx.Q("quest", fact.id, "name") or ("quest " .. fact.id), quest = fact.id }
	end
	Block("Reward of the quest", DBx.RelTo("rewards", "item", e.id), Quest)
	Block("Starts the quest", DBx.Rel("starts", "item", e.id), Quest)
	if e.src.Crafted then out[#out + 1] = { head = "Made with a profession (a recipe makes it)" } end
	if e.teaches then out[#out + 1] = { head = "Teaches a recipe or spell" } end
	if not out[1] then out[1] = { text = "|cff888888No source known: perhaps a quest item handed over, or not in the game any more.|r" } end
	return out
end

local STAT_ORDER = { "armor", "dps", "sta", "str", "agi", "int", "spi", "ap", "sp", "heal", "hit", "crit", "dodge", "parry", "block", "def", "mp5", "hp5",
	"fire", "nature", "frost", "shadow", "arcane" }
local function StatText(k)
	local parts = {}
	for _, s in ipairs(STAT_ORDER) do
		if k.s[s] then parts[#parts + 1] = ("%s %s"):format(k.s[s] % 1 == 0 and ("%d"):format(k.s[s]) or ("%.1f"):format(k.s[s]), s) end
	end
	return table.concat(parts, ", ")
end
I.StatText = StatText

local function Colored(e)
	local k = Kept(e.id)
	local color = k and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[k.q] and ITEM_QUALITY_COLORS[k.q].hex or "|cffffffff"
	return color .. e.name .. "|r"
end

-- the window that says where an item comes from
local info
local IW, IH, IROWS = 520, 16, 30
local infoLines, infoOffset = {}, 0
local function DrawInfo()
	infoOffset = math.max(0, math.min(infoOffset, #infoLines - IROWS))
	for i = 1, IROWS do
		local d, row = infoLines[i + infoOffset], info.rows[i]
		row.data = d
		row:SetShown(d ~= nil)
		if d then
			row.text:SetText(d.head and ("|cffffd100" .. d.head .. "|r") or ("    " .. d.text))
			row:EnableMouse((d.npc or d.quest) and true or false)
		end
	end
	info.more:SetText(#infoLines > IROWS and ("|cff888888mouse wheel: %d above, %d below|r"):format(infoOffset, math.max(0, #infoLines - IROWS - infoOffset)) or "")
end

function I.ShowInfo(e)
	if not info then
		info = CreateFrame("Frame", "DawnToolsItemInfo", UIParent, "BackdropTemplate")
		info:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		info:SetBackdropColor(0.06, 0.06, 0.07, 0.97)
		info:SetBackdropBorderColor(0.78, 0.68, 0.37, 1)
		info:SetFrameStrata("DIALOG")
		info:SetClampedToScreen(true)
		info:SetMovable(true)
		info:EnableMouse(true)
		info:RegisterForDrag("LeftButton")
		info:SetScript("OnDragStart", info.StartMoving)
		info:SetScript("OnDragStop", info.StopMovingOrSizing)
		info:SetPoint("CENTER", 0, 40)
		if UISpecialFrames then table.insert(UISpecialFrames, "DawnToolsItemInfo") end -- Esc closes it
		local shut = CreateFrame("Button", nil, info, "UIPanelCloseButton")
		shut:SetPoint("TOPRIGHT", 2, 2)
		shut:SetScript("OnClick", function() info:Hide() end) -- (the template's own closing goes through the game's panel code, which is barred to addons in combat: a plain Hide is not)
		info.title = info:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		info.title:SetPoint("TOPLEFT", 10, -8)
		info.sub = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		info.sub:SetPoint("TOPLEFT", 10, -28)
		info.sub:SetPoint("RIGHT", -10, 0)
		info.sub:SetJustifyH("LEFT")
		info.sub:SetWordWrap(false)
		info.more = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		info.more:SetPoint("BOTTOMLEFT", 10, 6)
		info.rows = {}
		for i = 1, IROWS do
			local row = CreateFrame("Button", nil, info)
			row:SetHeight(IH)
			row:SetPoint("TOPLEFT", 8, -46 - (i - 1) * IH)
			row:SetPoint("RIGHT", -8, 0)
			local glow = row:CreateTexture(nil, "HIGHLIGHT")
			glow:SetAllPoints()
			glow:SetColorTexture(1, 1, 1, 0.08)
			row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.text:SetPoint("LEFT", 4, 0)
			row.text:SetPoint("RIGHT", -4, 0)
			row.text:SetJustifyH("LEFT")
			row.text:SetWordWrap(false)
			-- a click: a waypoint to the NPC, or the quest's chain
			row:SetScript("OnClick", function(self)
				local d = self.data
				if not d then return end
				if d.npc then
					DT.Npc.Waypoint({ id = d.npc, name = d.name, zone = 0 })
				elseif d.quest then
					local quest = DT.Quest.Entry and DT.Quest.Entry(d.quest)
					if quest then
						DT.Quest.ShowChain(quest)
					else
						DT:Print("Open the Quests tab once (World > Quests): then a click here shows the quest's chain.")
					end
				end
			end)
			info.rows[i] = row
		end
		info:EnableMouseWheel(true)
		info:SetScript("OnMouseWheel", function(_, delta)
			infoOffset = infoOffset - delta * 3
			DrawInfo()
		end)
		I.info = info
	end
	local k = I.Know(e.id)
	infoLines, infoOffset = I.Sources(e), 0
	info.title:SetText(Colored(e))
	info.sub:SetText(("|cff888888Level %d, item level %d.|r %s%s"):format(e.req, e.ilvl, k and StatText(k) or "",
		"   |cff888888Click a name: waypoint. Click a quest: its chain.|r"))
	info:SetSize(IW, 46 + math.max(1, math.min(#infoLines, IROWS)) * IH + 24)
	info:Show()
	DrawInfo()
	return infoLines
end

---------------------------------------------------------------------------
-- The tab: laid out as the Market tab is
---------------------------------------------------------------------------

local ROW_H, SIDE_W, TOP_H, SIDE_H = 18, 150, 50, 17
local COLS = { { "Item", 230 }, { "Lvl", 34 }, { "iLvl", 38 }, { "Type", 110 }, { "Slot / size", 80 }, { "Source", 150 }, { "Auction", 0 } }
local panel, side, search, countText, bar, minBox, maxBox, statBox, qualityButton, sourceButton, usableBox, learnButton
local rows, heads, sideButtons, list, sections, offset, sideOffset = {}, {}, {}, {}, {}, 0, 0
local sortCol, sortDesc
local searchAt, state = nil, { unknown = 0, of = 0 }

local function SlotName(k)
	if not k or k.e == "" then return "" end
	return _G[k.e] or k.e
end

-- How many slots a bag has: its tooltip's own line ("16 Slot Bag"). nil while the game has not loaded it, or for
-- a container that says none. Kept for the session.
local CONTAINER = 1 -- (the item class of bags, quivers and the like)
local SLOTS_LINE = "^" .. ((CONTAINER_SLOTS or "%d Slot %s"):gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%d", "(%%d+)"):gsub("%%s", ".+")) .. "$"
local bagSlots = {}
function I.BagSlots(id)
	if bagSlots[id] ~= nil then return bagSlots[id] or nil end
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
	local lines = ok and data and data.lines
	if not lines or #lines < 2 then return nil end -- (not all there yet: asked again at the next look)
	for _, line in ipairs(lines) do
		local n = type(line.leftText) == "string" and tonumber(line.leftText:match(SLOTS_LINE))
		if n then
			bagSlots[id] = n
			return n
		end
	end
	bagSlots[id] = false
end

local function Rebuild()
	local db, cat = I.db, Cat()
	local found
	if ready then found, state = I.Find(search:GetText() or "", db) else found, state = {}, { unknown = 0, of = 0 } end
	list = {}
	for i, r in ipairs(found) do
		local e = r.e
		list[i] = { e = e, score = r.score, sort = { e.nameL, e.req, e.ilvl, e.s,
			-- (bags by how big they are: as text, so it sorts beside the empty cells of everything else)
			e.c == CONTAINER and ("%03d"):format(I.BagSlots(e.id) or 0) or "", e.srcText, 0 } }
	end
	table.sort(list, function(a, b)
		if sortCol then
			local x, y = a.sort[sortCol], b.sort[sortCol]
			if x ~= y then
				if sortDesc then return x > y end
				return x < y
			end
		elseif a.score ~= b.score then
			return a.score > b.score
		end
		if a.e.req ~= b.e.req then return a.e.req < b.e.req end
		if a.e.nameL ~= b.e.nameL then return a.e.nameL < b.e.nameL end
		return a.e.id < b.e.id
	end)
	-- the categories: every kind of item there is; under the one picked its groups; under an armour group
	-- the places it is worn (as far as the game has told us)
	sections = { { label = "All items" } }
	local classes, groups, leaves = {}, {}, {}
	if ready then
		-- (which kinds and groups there are does not change once the items are read: worked out once)
		if not catalog then
			catalog = { classes = {}, groups = {}, byGroup = {} }
			local scratch = { e = "" }
			for _, e in ipairs(index) do
				scratch.c, scratch.s = e.c, e.s
				local group = cat.Place(scratch)
				local key = e.c .. ":" .. tostring(group)
				catalog.classes[e.c] = true
				catalog.groups[e.c] = catalog.groups[e.c] or {}
				catalog.groups[e.c][group] = true
				catalog.byGroup[key] = catalog.byGroup[key] or {}
				table.insert(catalog.byGroup[key], e)
			end
		end
		for class in pairs(catalog.classes) do classes[class] = true end
		groups = catalog.groups[db.class or -1] or {}
		-- where the armour of the group picked is worn: as far as the game has told us
		if db.class == cat.ARMOR and db.group ~= nil then
			for _, e in ipairs(catalog.byGroup[db.class .. ":" .. tostring(db.group)] or {}) do
				local k = Kept(e.id)
				if k and k.e ~= "" then
					local _, leaf = cat.Place({ c = e.c, s = e.s, e = k.e })
					if leaf then leaves[leaf] = true end
				end
			end
		end
	end
	local function Add(class)
		if not classes[class] then return end
		classes[class] = nil
		sections[#sections + 1] = { label = cat.ClassName(class), class = class }
		if class ~= db.class then return end
		for _, group in ipairs(cat.Ordered(groups, class == cat.WEAPON and cat.WEAPON_GROUPS or class == cat.ARMOR and cat.ARMOR_GROUPS or nil)) do
			sections[#sections + 1] = { label = cat.GroupLabel(class, group), class = class, group = group, depth = 1 }
			if group == db.group and class == cat.ARMOR then
				for _, leaf in ipairs(cat.Ordered(leaves, nil, cat.SLOT_RANK)) do
					sections[#sections + 1] = { label = cat.LeafLabel(class, leaf), class = class, group = group, leaf = leaf, depth = 2 }
				end
			end
		end
	end
	for _, class in ipairs(cat.CLASS_ORDER) do Add(class) end
	local rest = {}
	for class in pairs(classes) do rest[#rest + 1] = class end
	table.sort(rest)
	for _, class in ipairs(rest) do Add(class) end
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", SIDE_W + 8, -TOP_H - ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -12, 0)
	local shade = row:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
	row.icols = {}
	for c = 1, #COLS do
		row.icols[c] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.icols[c]:SetJustifyH("LEFT")
		row.icols[c]:SetWordWrap(false)
	end
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if not self.data then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. self.data.e.id)
		GameTooltip:AddLine("Click: where it comes from. Shift-click: link in chat. Shift-right-click: its web page.", 0.5, 0.8, 1)
		GameTooltip:AddLine("Hold Shift: compare with what you wear.", 0.5, 0.8, 1)
		DT.Favs.Hint(GameTooltip, self.data.e.id)
		GameTooltip:Show()
		DT:CompareTip(self)
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self, button)
		local d = self.data
		if not d then return end
		if DT:LinkClick(button, DT:GameItemLink(d.e.id, d.e.name), d.e.name, DT:ItemLink(d.e.id), d.e.id) or button == "RightButton" then return end
		I.ShowInfo(d.e)
	end)
	rows[i] = row
	return row
end

local function Label(list, value)
	for _, e in ipairs(list) do
		if e[1] == value then return e[2] end
	end
	return list[1][2]
end

-- scrolled = only the window moved: the items are not gone through again
function I.Refresh(scrolled)
	if not panel then return end
	local db, cat = I.db, Cat()
	if scrolled ~= true then
		dirty = false
		Rebuild()
	end
	local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H - ROW_H) / ROW_H))
	local max = math.max(0, #list - fit)
	offset = math.max(0, math.min(offset, max))
	bar:SetMinMaxValues(0, max)
	bar:SetValue(offset)
	bar:SetShown(max > 0)
	bar.thumb:SetSize(8, math.max(16, fit * ROW_H * fit / math.max(fit, #list)))
	local x, xs, widths = 0, {}, {}
	for c, col in ipairs(COLS) do
		xs[c], widths[c] = x, col[2] > 0 and col[2] - 6 or math.max(60, panel:GetWidth() - SIDE_W - 8 - x - 16)
		x = x + col[2]
		heads[c]:ClearAllPoints()
		heads[c]:SetPoint("TOPLEFT", SIDE_W + 8 + xs[c], -TOP_H)
		heads[c]:SetSize(widths[c], ROW_H)
		heads[c].text:SetText("|cffffd100" .. col[1] .. (sortCol == c and (sortDesc and " v" or " ^") or "") .. "|r")
	end
	local pending = false
	for i = 1, math.max(fit, #rows) do
		local d = i <= fit and list[offset + i]
		local row = rows[i] or (d and MakeRow(i))
		if row then
			row.data = d or nil
			row:SetShown(d and true or false)
			if d then
				-- (the rows on screen are learned as they come into view: their colour and slot fill in)
				local e = d.e
				local k = I.Know(e.id)
				if not k and not GaveUp(e.id) then pending = true end
				local price = DawnMarket and DawnMarket.API.GetLatest and DawnMarket.API.GetLatest(e.id)
				local cells = { Colored(e), e.req > 0 and tostring(e.req) or "", e.ilvl > 0 and tostring(e.ilvl) or "",
					cat.GroupLabel(e.c, (cat.Place({ c = e.c, s = e.s, e = "" }))) or "",
					-- (a bag says how big it is where other things say where they are worn)
					e.c == CONTAINER and I.BagSlots(e.id) and (I.BagSlots(e.id) .. " slots") or SlotName(k),
					e.srcText, price and DT.Money(price) or "" }
				for c, cell in ipairs(row.icols) do
					cell:SetText(cells[c])
					cell:ClearAllPoints()
					cell:SetPoint("LEFT", xs[c], 0)
					cell:SetWidth(widths[c])
				end
			end
		end
	end
	if pending or state.unknown > 0 then Later() end
	if scrolled == true then return end
	-- the categories
	local sfit = math.max(1, math.floor((panel:GetHeight() - 6) / SIDE_H))
	sideOffset = math.max(0, math.min(sideOffset, #sections - sfit))
	for i = 1, math.max(sfit, #sideButtons) do
		local e = i <= sfit and sections[i + sideOffset] or nil
		local b = sideButtons[i]
		if e and not b then
			b = CreateFrame("Button", nil, side)
			b:SetHeight(SIDE_H)
			b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * SIDE_H)
			b:SetPoint("RIGHT", -2, 0)
			b.sel = b:CreateTexture(nil, "BACKGROUND")
			b.sel:SetAllPoints()
			b.sel:SetColorTexture(1, 0.82, 0, 0.18)
			local glow = b:CreateTexture(nil, "HIGHLIGHT")
			glow:SetAllPoints()
			glow:SetColorTexture(1, 1, 1, 0.08)
			b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.label:SetPoint("LEFT", 6, 0)
			b.label:SetPoint("RIGHT", -4, 0)
			b.label:SetJustifyH("LEFT")
			b.label:SetWordWrap(false)
			b:SetScript("OnClick", function(self)
				local s = self.entry
				if not s then return end
				-- what is picked, clicked again, goes back up one step
				if s.leaf ~= nil and db.group == s.group and db.leaf == s.leaf then
					db.leaf = nil
				elseif s.group ~= nil and s.leaf == nil and db.class == s.class and db.group == s.group and db.leaf == nil then
					db.group = nil
				else
					db.class, db.group, db.leaf = s.class, s.group, s.leaf
				end
				offset = 0
				I.Refresh()
			end)
			sideButtons[i] = b
		end
		if b then
			b.entry = e
			b:SetShown(e ~= nil)
			if e then
				b.label:SetText(("    "):rep(e.depth or 0) .. e.label)
				local on
				if e.leaf ~= nil then
					on = db.class == e.class and db.group == e.group and db.leaf == e.leaf
				elseif e.group ~= nil then
					on = db.class == e.class and db.group == e.group and db.leaf == nil
				else
					on = db.class == e.class and db.group == nil
				end
				b.sel:SetShown(on and true or false)
			end
		end
	end
	usableBox:SetChecked(db.usable and true or false)
	qualityButton.label:SetText(Label(QUALITIES, db.quality))
	sourceButton.label:SetText(db.source and ("From: " .. db.source) or "From: anywhere")
	learnButton:SetShown(state.capped and true or false)
	if missing then
		countText:SetText("|cffff8080" .. DT.DB.NEEDS .. "|r")
	elseif not ready then
		countText:SetText(("|cff888888Reading items... %d%%|r"):format(math.floor((I.progress or 0) * 100)))
	elseif state.capped then
		countText:SetText(("|cffffd100%d of these %d items are not known to the game yet. Narrow it down (a category, a level, a word), or:|r"):format(state.unknown, state.of))
	elseif state.unknown > 0 then
		countText:SetText(("%d items so far  |cffffd100learning %d of %d...|r"):format(#list, state.unknown, state.of))
	else
		countText:SetText(("%d of %d items%s"):format(#list, #index, sortCol and "" or (search:GetText() or "") ~= "" and ", best match first" or ""))
	end
end

local function Build(parent)
	panel = parent
	local db = I.db
	side = CreateFrame("Frame", nil, panel)
	side:SetPoint("TOPLEFT", 0, -2)
	side:SetPoint("BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDE_W)
	local shade = side:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, 0.04)
	side:EnableMouseWheel(true)
	side:SetScript("OnMouseWheel", function(_, delta)
		sideOffset = sideOffset - delta * 2
		I.Refresh()
	end)

	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("TOPLEFT", SIDE_W + 16, -3)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function()
		sortCol, offset, searchAt, I.force = nil, 0, GetTime() + 0.15, nil
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	I.search = search
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", search, "RIGHT", 12, 0)
	countText:SetJustifyH("LEFT")
	countText:SetWordWrap(false)
	learnButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	learnButton:SetSize(130, 20)
	learnButton:SetPoint("LEFT", countText, "RIGHT", 8, 0)
	learnButton:SetText("Learn them anyway")
	learnButton:SetScript("OnClick", function()
		I.force = true
		I.Refresh()
	end)
	learnButton:Hide()
	I.learnButton, I.countText = learnButton, countText

	-- the second line: level, quality, usable, source, stats
	local function Text(text, after, gap)
		local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if after then fs:SetPoint("LEFT", after, "RIGHT", gap or 6, 0) else fs:SetPoint("TOPLEFT", SIDE_W + 12, -30) end
		fs:SetText(text)
		return fs
	end
	local function LevelBox(key, after)
		local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
		box:SetSize(28, 18)
		box:SetPoint("LEFT", after, "RIGHT", 8, 0)
		box:SetAutoFocus(false)
		box:SetNumeric(true)
		box:SetText(db[key] and tostring(db[key]) or "")
		box:SetScript("OnTextChanged", function(self)
			db[key] = tonumber(self:GetText())
			offset, dirty, I.force = 0, true, nil
		end)
		box:SetScript("OnEnterPressed", box.ClearFocus)
		box:SetScript("OnEscapePressed", box.ClearFocus)
		return box
	end
	minBox = LevelBox("min", Text("Level"))
	maxBox = LevelBox("max", Text("to", minBox, 4))
	local function Pick(width, entries, picked, pick, after, gap)
		local b = DT:Dropdown(panel, width, { entries = entries, picked = picked, pick = function(value)
			pick(value)
			offset, I.force = 0, nil
			I.Refresh()
		end })
		b:SetPoint("LEFT", after, "RIGHT", gap or 10, 0)
		return b
	end
	qualityButton = Pick(140, function()
		local out = {}
		for i, q in ipairs(QUALITIES) do out[i] = { value = q[1], text = q[2] } end
		return out
	end, function() return db.quality end, function(v) db.quality = v end, maxBox)
	sourceButton = Pick(130, function()
		local out = { { text = "From: anywhere" } }
		for _, s in ipairs(SOURCES) do out[#out + 1] = { value = s, text = s } end
		return out
	end, function() return db.source end, function(v) db.source = v end, qualityButton)
	usableBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	usableBox:SetSize(22, 22)
	usableBox:SetPoint("LEFT", sourceButton, "RIGHT", 8, 0)
	local usableText = Text("Usable", usableBox, 0)
	usableBox:SetScript("OnClick", function(self)
		db.usable = self:GetChecked() and true or nil
		offset = 0
		I.Refresh()
	end)
	local statLabel = Text("Stats", usableText, 12)
	statBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	statBox:SetSize(140, 18)
	statBox:SetPoint("LEFT", statLabel, "RIGHT", 8, 0)
	statBox:SetAutoFocus(false)
	statBox:SetText(db.stats or "")
	statBox:SetScript("OnTextChanged", function(self)
		db.stats = self:GetText()
		offset, searchAt, I.force = 0, GetTime() + 0.4, nil
	end)
	statBox:SetScript("OnEnterPressed", statBox.ClearFocus)
	statBox:SetScript("OnEscapePressed", statBox.ClearFocus)
	statBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("What is on the item")
		GameTooltip:AddLine("Words with a space between; all must hold.", 1, 1, 1, true)
		GameTooltip:AddLine("sta>11   int>=5   armor>100   dps>20", 0.6, 0.9, 1)
		GameTooltip:AddLine("hit   crit   mp5   fire     (a word alone: the item has it)", 0.6, 0.9, 1)
		GameTooltip:AddLine("sta str agi int spi armor dps ap sp heal hit crit dodge parry block def mp5 hp5 fire nature frost shadow arcane", 0.7, 0.7, 0.7, true)
		GameTooltip:AddLine("Any other word is looked for in the item's Equip and Use lines.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	statBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	I.statBox, I.qualityButton, I.sourceButton, I.usableBox, I.minBox, I.maxBox = statBox, qualityButton, sourceButton, usableBox, minBox, maxBox
	local clear = CreateFrame("Button", nil, panel)
	clear:SetSize(40, 18)
	clear:SetPoint("LEFT", statBox, "RIGHT", 10, 0)
	clear.label = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	clear.label:SetPoint("LEFT")
	clear.label:SetText("|cff80c0ffClear|r")
	clear:SetScript("OnClick", function()
		db.min, db.max, db.quality, db.source, db.usable, db.stats, db.class, db.group, db.leaf = nil, nil, nil, nil, nil, nil, nil, nil, nil
		minBox:SetText("")
		maxBox:SetText("")
		statBox:SetText("")
		search:SetText("")
		sortCol, offset, I.force = nil, 0, nil
		I.Refresh()
	end)
	I.clear = clear

	for c = 1, #COLS do
		local h = CreateFrame("Button", nil, panel)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetJustifyH("LEFT")
		h.text:SetWordWrap(false)
		h:SetScript("OnClick", function()
			if sortCol == c then sortDesc = not sortDesc else sortCol, sortDesc = c, false end
			I.Refresh()
		end)
		heads[c] = h
	end
	I.heads = heads

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
		if value == offset then return end
		offset = value
		I.Refresh(true)
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		I.Refresh(true)
	end)
	panel:SetScript("OnSizeChanged", function() I.Refresh(true) end) -- (the same items, laid out anew)
	panel:SetScript("OnUpdate", function()
		-- (in a fight the game cuts off a script that takes long: reading and searching the list wait for its end)
		if InCombatLockdown and InCombatLockdown() then return end
		if reading then
			I.Step(8)
			I.Refresh()
			return
		end
		if searchAt and GetTime() >= searchAt then searchAt, dirty = nil, true end
		if dirty then I.Refresh() end
	end)
end

local function Show()
	I.Start()
	I.Refresh()
end

DT:RegisterModule("item", {
	title = "Items",
	version = 1,
	slash = "/dtitem",
	profile = { "min", "max", "quality", "usable", "source", "stats", "class", "group", "leaf" }, -- (how it is set up: goes with a profile)
	tab = { id = "item", title = "Items", defaultOrder = 58, under = "world", create = Build, onShow = Show },
	onEnable = function(mod)
		I.db = mod.db
		I.db.known = I.db.known or {}
		DT:On("DT_DB_UPDATE", function() stale = fromStore or missing end)
		DT:Background({ Start = I.Start, Step = I.Step })
		DT:On("GET_ITEM_INFO_RECEIVED", function(id)
			if not waiting[id] then return end
			waiting[id] = nil
			Later()
		end)
		DT:On("NEW_RECIPE_LEARNED", function()
			learned = {}
			Later()
		end)
		-- (the saved file holds a few thousand of these in time: empty parts are left out of it)
		DT:On("PLAYER_LOGOUT", function()
			for _, k in pairs(I.db.known) do
				if type(k) == "table" then
					if k.s and not next(k.s) then k.s = nil end
					if k.x == "" then k.x = nil end
				end
			end
		end)
	end,
	selfTest = function(_, Try)
		Try("item tab", function() I.Refresh() end)
		Try("item stats box", function() assert(#I.ParseStats("sta>11 hit") == 2) end)
		Try("item search", function()
			if ready then I.Find("sword", {}) end
		end)
	end,
})
