-- DawnTools :: Gather
-- High-DPI 3D soft-target visual highlights for herbs, veins, treasure, barrels, fishing pools, and quest objects (~15 yd).
-- Defaulted to OFF. Guild node sharing is strictly opt-in (off = coded baseline + your own discoveries only).

local _, DT = ...
local G = { baseline = {}, index = {} }
DT.Gather = G

local DEFAULTS = {
	enabled = false,              -- defaulted to off
	share = false,                -- strictly opt-in: false = coded baseline + personal discoveries only
	herbs = true,
	ore = true,
	chests = true,                -- treasure chests, strongboxes, lockboxes, footlockers, caches
	barrels = true,               -- barrels, crates, casks, kegs, sacks, debris, urns, baskets
	fishing = true,               -- schools of fish, floating wreckage, pools, giant clams
	quests = true,                -- interactive objects for active quests in your log
	corpses = false,              -- lootable / skinnable corpses in soft-target cone
	interact = false,             -- books, scrolls, tablets, shrines, altars, braziers, levers
	allObjects = false,
	smartProf = false,            -- filter herbs/ore to your learned professions
	cultivation = true,           -- highlight when Tauren Cultivation is ready & eligible
	showPrice = true,             -- show live DawnMarket AH price beneath node name
	autoResScale = true,          -- scale 3D effects proportionally with monitor resolution & UI scale
	colorMode = "custom",         -- "custom" | "category" | "difficulty"
	color1 = { 0.30, 1.00, 0.55 },
	color2 = { 1.00, 0.88, 0.30 },
	fxSparkles = true,
	fxBeam = true,
	fxRing = true,
	fxOrbit = false,
	fxReticle = false,
	fxLabel = true,
	density = 12,                 -- 4 .. 18 sparkle particles
	scale = 1.0,                  -- 0.60 .. 2.00
	alpha = 0.92,                 -- 0.30 .. 1.00
	speed = 1.0,                  -- 0.50 .. 2.00
	offsetY = 10,                 -- -10 .. 40
	sound = "none",
}

local PRESETS = {
	{ name = "Emerald", c1 = { 0.30, 1.00, 0.55 }, c2 = { 1.00, 0.88, 0.30 } },
	{ name = "Gold",    c1 = { 1.00, 0.80, 0.18 }, c2 = { 1.00, 0.45, 0.10 } },
	{ name = "Violet",  c1 = { 0.72, 0.38, 1.00 }, c2 = { 0.55, 0.90, 1.00 } },
	{ name = "Cyan",    c1 = { 0.25, 0.88, 1.00 }, c2 = { 0.85, 0.97, 1.00 } },
	{ name = "Fel",     c1 = { 0.45, 1.00, 0.12 }, c2 = { 0.90, 1.00, 0.25 } },
	{ name = "Class",   class = true },
	{ name = "Theme",   theme = true },
}

local SOUNDS = {
	{ id = "none",  label = "None" },
	{ id = "chime", label = "Chime", kit = 12867 },
	{ id = "ping",  label = "Ping",  kit = 3175 },
	{ id = "bell",  label = "Bell",  kit = 5274 },
	{ id = "alert", label = "Alert", kit = 8959 },
}

local function IsSharing()
	return G.db ~= nil and G.db.settings ~= nil and G.db.settings.share == true
end

---------------------------------------------------------------------------
-- Resolution & Pixel-Density Scaling
---------------------------------------------------------------------------

local cachedResScale, cachedPixelSize, cachedResLabel = 1.0, 1.0, "1920x1080"

local function UpdateResolutionMetrics()
	local physW, physH
	if GetPhysicalScreenSize then
		physW, physH = GetPhysicalScreenSize()
	end
	local effScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1.0
	if not (physW and physH and physW > 0 and physH > 0) then
		physW = math.floor(((GetScreenWidth and GetScreenWidth()) or 1920) * effScale + 0.5)
		physH = math.floor(((GetScreenHeight and GetScreenHeight()) or 1080) * effScale + 0.5)
	end
	local rawScale = (physH / 1080) / math.max(effScale, 0.25)
	cachedResScale = math.max(0.75, math.min(3.50, rawScale))
	cachedPixelSize = (768 / math.max(physH, 1)) / math.max(effScale, 0.25)
	cachedResLabel = ("%dx%d (%.2fx)"):format(physW, physH, cachedResScale)
end

local function EffectiveScale(isPreview)
	local userScale = (G.db and G.db.settings and G.db.settings.scale) or 1.0
	if isPreview then
		return userScale
	end
	if G.db and G.db.settings and G.db.settings.autoResScale then
		return userScale * cachedResScale
	end
	return userScale
end

---------------------------------------------------------------------------
-- High-DPI Texture & Atlas Loader
---------------------------------------------------------------------------

local atlasCache = {}
local function HasAtlas(name)
	if atlasCache[name] ~= nil then return atlasCache[name] end
	local ok = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil) or false
	atlasCache[name] = ok
	return ok
end

local function SetSmoothFilter(tex, snapToGrid)
	if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(snapToGrid and true or false) end
	if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(snapToGrid and 0.5 or 0.0) end
end

local function ApplyHighResArt(tex, atlases, fallbackPath, l, r, t, b)
	SetSmoothFilter(tex, false)
	if atlases then
		for _, atlas in ipairs(atlases) do
			if HasAtlas(atlas) then
				tex:SetAtlas(atlas, false)
				return
			end
		end
	end
	tex:SetTexture(fallbackPath)
	if l then tex:SetTexCoord(l, r, t, b) end
end

---------------------------------------------------------------------------
-- Layer 1: Coded Baseline + Unified DT.DB / Market Index
---------------------------------------------------------------------------

local STARTER_NODES = {
	-- Herbs
	["peacebloom"] = { k = "herb", s = 1 }, ["silverleaf"] = { k = "herb", s = 1 },
	["earthroot"] = { k = "herb", s = 15 }, ["mageroyal"] = { k = "herb", s = 50 },
	["briarthorn"] = { k = "herb", s = 70 }, ["stranglekelp"] = { k = "herb", s = 85 },
	["bruiseweed"] = { k = "herb", s = 100 }, ["wild steelbloom"] = { k = "herb", s = 115 },
	["grave moss"] = { k = "herb", s = 120 }, ["kingsblood"] = { k = "herb", s = 125 },
	["liferoot"] = { k = "herb", s = 150 }, ["fadeleaf"] = { k = "herb", s = 160 },
	["goldthorn"] = { k = "herb", s = 170 }, ["khadgar's whisker"] = { k = "herb", s = 185 },
	["wintersbite"] = { k = "herb", s = 195 }, ["firebloom"] = { k = "herb", s = 205 },
	["purple lotus"] = { k = "herb", s = 210 }, ["arthas' tears"] = { k = "herb", s = 220 },
	["sungrass"] = { k = "herb", s = 230 }, ["blindweed"] = { k = "herb", s = 235 },
	["ghost mushroom"] = { k = "herb", s = 245 }, ["gromsblood"] = { k = "herb", s = 250 },
	["golden sansam"] = { k = "herb", s = 260 }, ["dreamfoil"] = { k = "herb", s = 270 },
	["mountain silversage"] = { k = "herb", s = 280 }, ["plaguebloom"] = { k = "herb", s = 285 },
	["icecap"] = { k = "herb", s = 290 }, ["black lotus"] = { k = "herb", s = 300 },
	["bloodvine"] = { k = "herb", s = 300 },
	-- Mining veins
	["copper vein"] = { k = "ore", s = 1 }, ["tin vein"] = { k = "ore", s = 65 },
	["silver vein"] = { k = "ore", s = 75 }, ["incindisite mineral vein"] = { k = "ore", s = 65 },
	["lesser bloodstone deposit"] = { k = "ore", s = 75 }, ["iron deposit"] = { k = "ore", s = 125 },
	["gold vein"] = { k = "ore", s = 155 }, ["mithril deposit"] = { k = "ore", s = 175 },
	["truesilver deposit"] = { k = "ore", s = 230 }, ["dark iron deposit"] = { k = "ore", s = 230 },
	["small thorium vein"] = { k = "ore", s = 245 }, ["rich thorium vein"] = { k = "ore", s = 275 },
	["small obsidian chunk"] = { k = "ore", s = 305 }, ["large obsidian chunk"] = { k = "ore", s = 305 },
	-- Treasure & chests
	["battered chest"] = { k = "chest", s = 1 }, ["solid chest"] = { k = "chest", s = 1 },
	["large battered chest"] = { k = "chest", s = 1 }, ["large solid chest"] = { k = "chest", s = 1 },
	["large iron bound chest"] = { k = "chest", s = 1 }, ["large mithril bound chest"] = { k = "chest", s = 1 },
	["bound adamantine chest"] = { k = "chest", s = 1 }, ["bound fel iron chest"] = { k = "chest", s = 1 },
	["waterlogged footlocker"] = { k = "chest", s = 1 }, ["battered footlocker"] = { k = "chest", s = 1 },
	["dented footlocker"] = { k = "chest", s = 1 }, ["mossy footlocker"] = { k = "chest", s = 1 },
	["scarlet footlocker"] = { k = "chest", s = 1 }, ["practice lockbox"] = { k = "chest", s = 1 },
	-- Barrels, crates & containers
	["dusty barrel"] = { k = "barrel", s = 1 }, ["wine barrel"] = { k = "barrel", s = 1 },
	["supply crate"] = { k = "barrel", s = 1 }, ["food crate"] = { k = "barrel", s = 1 },
	["water barrel"] = { k = "barrel", s = 1 }, ["loose dirt"] = { k = "barrel", s = 1 },
	["mound of dirt"] = { k = "barrel", s = 1 }, ["unclaimed baggage"] = { k = "barrel", s = 1 },
	-- Fishing & clams
	["floating wreckage"] = { k = "fishing", s = 1 }, ["giant clam"] = { k = "fishing", s = 1 },
}

for low, info in pairs(STARTER_NODES) do
	G.baseline[low] = { k = info.k, s = info.s }
end
for low, info in pairs(DT.GatherNodes or {}) do
	G.baseline[low] = { k = info.k, s = info.s or 1, id = (info.id and info.id > 0) and info.id or nil }
	if info.id and info.id > 0 then G.index[low] = info.id end
end

local function IndexTradeItem(id, name, class, sub)
	if not (id and name and class == 7) then return end
	local low = name:lower()
	if sub == 9 then
		G.baseline[low] = G.baseline[low] or { k = "herb", s = 1, id = id }
		G.baseline[low].id = G.baseline[low].id or id
		G.index[low] = id
	elseif sub == 7 then
		G.index[low] = id
		local stem = low:gsub("%s+ore$", ""):gsub("%s+stone$", "")
		if stem ~= "" and stem ~= low then
			G.index[stem] = G.index[stem] or id
			for _, pat in ipairs({ "%s vein", "rich %s vein", "%s deposit", "rich %s deposit", "%s lode", "small %s vein" }) do
				local nodeName = pat:format(stem)
				G.baseline[nodeName] = G.baseline[nodeName] or { k = "ore", s = 1, id = id }
				G.baseline[nodeName].id = G.baseline[nodeName].id or id
			end
		end
	end
end

local lastDBStamp = -1

function G.RebuildIndex()
	-- 1. Pull Trade Goods (Herbs & Ores) already observed in DawnMarket
	local M = DT.Market
	if M and M.db and M.db.houses then
		for _, house in pairs(M.db.houses) do
			for id, item in pairs(house) do
				if item.n and item.c == 7 then
					IndexTradeItem(id, item.n, item.c, item.s)
				end
			end
		end
	end

	-- 2. Pull Trade Goods & Object Node Names from DT.DB (QuestieDB or guild-synced DB store)
	local DB = DT.DB
	local stamp = DB and DB.Stamp and DB.Stamp() or 0
	if DB and DB.Lib and stamp ~= lastDBStamp then
		local lib = DB.Lib()
		if lib and lib.Item and lib.Item.GetAllIds then
			lastDBStamp = stamp
			local ok, ids = pcall(lib.Item.GetAllIds)
			for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do
				local class = lib.Item.Get(id, "class")
				local sub = lib.Item.Get(id, "subClass")
				if class == 7 and (sub == 9 or sub == 7) then
					local name = lib.Item.Get(id, "name")
					if type(name) == "string" and name ~= "" then
						IndexTradeItem(id, name, class, sub)
						-- Index exact world object names that drop this herb/ore (catches custom Forever nodes)
						if lib.Object and lib.Object.Get then
							local objs = lib.Item.Get(id, "objectDrops")
							if type(objs) == "table" then
								local kind = (sub == 9) and "herb" or "ore"
								for _, objID in ipairs(objs) do
									local objName = lib.Object.Get(objID, "name")
									if type(objName) == "string" and objName ~= "" then
										local oLow = objName:lower()
										G.baseline[oLow] = G.baseline[oLow] or { k = kind, s = 1, id = id }
										G.baseline[oLow].id = G.baseline[oLow].id or id
										G.index[oLow] = G.index[oLow] or id
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Layer 2 & 3: Live Tooltip Scanner, Keyword Classifier & Personal DB
---------------------------------------------------------------------------

local SKILL_PAT = (ITEM_MIN_SKILL or "Requires %s (%d)"):gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
SKILL_PAT = "^" .. SKILL_PAT:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"

local HERB_PROF = (GetSpellInfo and GetSpellInfo(2366)) or "Herbalism"
local MINE_PROF = (GetSpellInfo and GetSpellInfo(2575)) or "Mining"
local LOCK_PROF = (GetSpellInfo and GetSpellInfo(1804)) or "Lockpicking"
local SKIN_PROF = (GetSpellInfo and GetSpellInfo(8613)) or "Skinning"

local function ProfToKind(prof)
	if not prof then return nil end
	local low = prof:lower()
	if low:find("herb", 1, true) or low == HERB_PROF:lower() then return "herb" end
	if low:find("min", 1, true) or low == MINE_PROF:lower() then return "ore" end
	if low:find("lock", 1, true) or low == LOCK_PROF:lower() then return "chest" end
	if low:find("fish", 1, true) then return "fishing" end
	if low:find("skin", 1, true) or low == SKIN_PROF:lower() then return "corpse" end
	return nil
end

local KEYWORD_RULES = {
	{ kind = "fishing",  words = { "school of", "floating wreckage", "wreckage", "oil spill", "swarm", "pool", "giant clam", "clam", "lobster", "shellfish" } },
	{ kind = "chest",    words = { "chest", "strongbox", "coffer", "lockbox", "footlocker", "reliquary", "cache", "stash", "treasure", "safebox" } },
	{ kind = "barrel",   words = { "barrel", "crate", "cask", "keg", "sack", "supplies", "driftwood", "debris", "rubble", "urn", "vase", "basket", "bundle", "baggage", "box", "mound of dirt", "loose dirt" } },
	{ kind = "interact", words = { "book", "tome", "scroll", "tablet", "plaque", "shrine", "altar", "brazier", "lever", "monument", "obelisk", "pedestal", "lectern", "journal", "letter", "note", "mailbox", "portal", "crystal pylon" } },
}

local function ClassifyByKeywords(low)
	for _, group in ipairs(KEYWORD_RULES) do
		for _, w in ipairs(group.words) do
			if low:find(w, 1, true) then
				return group.kind
			end
		end
	end
	return nil
end

local scanTip
local function ReadSoftInteractLines()
	if C_TooltipInfo and C_TooltipInfo.GetUnit then
		local ok, data = pcall(C_TooltipInfo.GetUnit, "softinteract")
		if ok and data and data.lines then
			local out = {}
			for _, line in ipairs(data.lines) do
				if line.leftText and line.leftText ~= "" then out[#out + 1] = line.leftText end
			end
			return out
		end
	end
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "DawnToolsGatherScanTip", nil, "GameTooltipTemplate")
		scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	end
	scanTip:ClearLines()
	scanTip:SetUnit("softinteract")
	local out = {}
	for i = 1, scanTip:NumLines() do
		local fs = _G["DawnToolsGatherScanTipTextLeft" .. i]
		local txt = fs and fs:GetText()
		if txt and txt ~= "" then out[#out + 1] = txt end
	end
	return out
end

local function ActiveQuestTitles()
	local set = {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.title then set[info.title] = true end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, GetNumQuestLogEntries() do
			local title, _, _, isHeader = GetQuestLogTitle(i)
			if title and not isHeader then set[title] = true end
		end
	end
	return set
end

local function ProbeItemCache(name)
	if not (C_Item and C_Item.GetItemInfo) then return nil end
	local low = name:lower()
	local stripped = low
		:gsub("^rich%s+", ""):gsub("^small%s+", ""):gsub("^ooze covered%s+", ""):gsub("^large%s+", "")
		:gsub("%s+vein$", ""):gsub("%s+deposit$", ""):gsub("%s+lode$", ""):gsub("%s+node$", "")
		:gsub("%s+bush$", ""):gsub("%s+patch$", ""):gsub("%s+cluster$", "")
	for _, cand in ipairs({ name, stripped, stripped .. " ore" }) do
		local itemName, link, _, _, _, _, _, _, _, _, _, class, sub = C_Item.GetItemInfo(cand)
		if itemName and class == 7 then
			local id = link and tonumber(link:match("item:(%d+)"))
			if sub == 9 then return "herb", id end
			if sub == 7 then return "ore", id end
		end
	end
	return nil
end

local LEARNABLE_KINDS = { herb = true, ore = true, chest = true, barrel = true, fishing = true, interact = true }

local function Clean(txt)
	return (tostring(txt or ""):gsub("[|;%c]", ""):sub(1, 60))
end

local function WriteToUnifiedDB(low, rec)
	if not (IsSharing() and DT.DB and DT.DB.Put and rec) then return end
	local packed = ("%s;%s;%d;%d"):format(Clean(rec.n), rec.k, rec.s or 1, rec.id or 0)
	pcall(DT.DB.Put, "gnode:" .. low, packed, "guild", rec.t or DT.Now())
end

function G.LearnNode(name, kind, skill, itemID, fromGuild)
	if not (G.db and name and name ~= "" and LEARNABLE_KINDS[kind]) then return false end
	if fromGuild and not IsSharing() then return false end
	local low = name:lower()
	local base = G.baseline[low]
	if base and base.k == kind and (base.s or 1) >= (skill or 1) and (base.id or not itemID) then
		return false
	end
	local cur = G.db.nodes[low]
	local now = DT.Now()
	local changed = false
	if not cur then
		cur = { n = name, k = kind, s = skill or 1, id = itemID or G.index[low], t = now, r = fromGuild and now or nil }
		G.db.nodes[low] = cur
		changed = true
	else
		if skill and skill > (cur.s or 1) then cur.s, changed = skill, true end
		if itemID and not cur.id then cur.id, changed = itemID, true end
		if not fromGuild and cur.r then cur.r, changed = nil, true end
	end
	if changed and not fromGuild and IsSharing() then
		WriteToUnifiedDB(low, cur)
		if G.gossip then G.gossip:Queue(low) end
	end
	return changed
end

function G.SyncUnifiedDB()
	if not (IsSharing() and DT.DB and DT.DB.Each) then return end
	-- 1. Push any personal nodes into DT.DB so DBSync replicates them across the guild
	for low, n in pairs(G.db.nodes) do
		if not n.r then
			WriteToUnifiedDB(low, n)
		end
	end
	-- 2. Pull any guild-discovered gnode:* rows that arrived via DBSync
	pcall(DT.DB.Each, "gnode", function(key, row)
		local low = key:match("^gnode:(.+)$")
		if low and row and row.v then
			local name, kind, skill, itemID = row.v:match("^([^;]+);(%a+);(%d+);(%d+)$")
			if name and LEARNABLE_KINDS[kind] then
				skill, itemID = tonumber(skill) or 1, tonumber(itemID) or 0
				G.LearnNode(Clean(name), kind, skill, itemID > 0 and itemID or nil, true)
			end
		end
	end)
end

local seenThisSession = {}

local function InspectSoftInteract(name)
	if UnitIsDead and UnitIsDead("softinteract") then
		return { k = "corpse", s = 1, corpse = true }
	end

	local low = name:lower()
	local cached = seenThisSession[low]
	if cached then return cached end

	local learned = G.db and G.db.nodes[low]
	if learned and learned.r and not IsSharing() then
		learned = nil
	end
	local base = G.baseline[low]
	local kind = (learned and learned.k) or (base and base.k)
	local skill = (learned and learned.s) or (base and base.s)
	local itemID = (learned and learned.id) or (base and base.id) or G.index[low]
	local isQuest = false

	local lines = ReadSoftInteractLines()
	local quests = G.db and G.db.settings and G.db.settings.quests and ActiveQuestTitles() or nil
	for _, text in ipairs(lines) do
		local prof, req = text:match(SKILL_PAT)
		if prof then
			kind = ProfToKind(prof) or kind
			skill = tonumber(req) or skill
		else
			local pOnly = text:match("^Requires%s+(.+)$")
			if pOnly then kind = ProfToKind(pOnly) or kind end
		end
		if quests and (quests[text] or text:match("^%s*%-?%s*.+:%s*%d+/%d+%s*$")) then
			isQuest = true
		end
	end

	if not kind then
		local probedKind, probedID = ProbeItemCache(name)
		if probedKind then
			kind, itemID = probedKind, itemID or probedID
		end
	end

	if not kind then
		kind = ClassifyByKeywords(low)
	end

	if kind then
		G.LearnNode(name, kind, skill or 1, itemID, false)
	end

	local res = { k = kind or (isQuest and "quest" or nil), s = skill or 1, id = itemID, quest = isQuest }
	seenThisSession[low] = res
	return res
end

---------------------------------------------------------------------------
-- Layer 4: Opt-In Guild Dictionary Gossip (DT.Comms:Gossip)
---------------------------------------------------------------------------

local function InitGossip()
	if not (DT.Comms and DT.Comms.Gossip) then return end
	G.gossip = DT.Comms:Gossip("gather", {
		on = IsSharing,
		peers = function()
			G.db.peers = G.db.peers or {}
			return G.db.peers
		end,
		own = function()
			if not IsSharing() then return {} end
			local out = {}
			for low, n in pairs(G.db.nodes) do
				if not n.r then out[low] = n.t or 1 end
			end
			return out
		end,
		line = function(low)
			if not IsSharing() then return nil end
			local n = G.db.nodes[low]
			return (n and not n.r) and ("%s;%s;%d;%d;%d"):format(Clean(n.n), n.k, n.s or 1, n.id or 0, n.t or 0) or nil
		end,
		take = function(line)
			if not IsSharing() then return false end
			local name, kind, skill, itemID, t = line:match("^([^;]+);(%a+);(%d+);(%d+);(%d+)$")
			if not (name and LEARNABLE_KINDS[kind]) then return false end
			skill, itemID, t = tonumber(skill) or 1, tonumber(itemID) or 0, tonumber(t) or DT.Now()
			return G.LearnNode(Clean(name), kind, skill, itemID > 0 and itemID or nil, true)
		end,
	})
end

DT:RegisterModule("gather_sync", {
	title = "Gather node dictionary sync",
	version = 1,
	defaultOff = true,
	hidden = true,
	hello = function() return IsSharing() and G.gossip and G.gossip:Hello() or nil end,
	onHello = function(_, sender, summary) if IsSharing() and G.gossip then G.gossip:OnHello(sender, summary) end end,
	onMessage = function(_, kind, payload, sender) if IsSharing() and G.gossip then G.gossip:OnMessage(kind, payload, sender) end end,
})

---------------------------------------------------------------------------
-- Profession Ranks, Difficulty Colors & Tauren Cultivation Check
---------------------------------------------------------------------------

local function GetSkillRanks()
	local ranks = {}
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank = GetSkillLineInfo(i)
			if name and not header then ranks[name:lower()] = rank or 0 end
		end
	elseif GetProfessions and GetProfessionInfo then
		local slots = { GetProfessions() }
		for i = 1, 6 do
			if slots[i] then
				local name, _, rank = GetProfessionInfo(slots[i])
				if name then ranks[name:lower()] = rank or 0 end
			end
		end
	end
	return ranks
end

local function PlayerRankFor(kind)
	local ranks = GetSkillRanks()
	if kind == "herb" then return ranks[HERB_PROF:lower()] or ranks["herbalism"] end
	if kind == "ore" then return ranks[MINE_PROF:lower()] or ranks["mining"] end
	if kind == "chest" then return ranks[LOCK_PROF:lower()] or ranks["lockpicking"] end
	if kind == "corpse" then return ranks[SKIN_PROF:lower()] or ranks["skinning"] end
	return nil
end

local function IsCultivationReady(nodeSkill)
	local s = G.db and G.db.settings
	if not (s and s.cultivation and GetSpellInfo and GetSpellCooldown) then return false end
	local name = GetSpellInfo("Cultivation")
	if not name then return false end
	local start, dur = GetSpellCooldown("Cultivation")
	if start and dur and dur > 1.5 and (start + dur - GetTime()) > 0 then return false end
	local reqLvl = math.floor((nodeSkill or 1) / 5)
	return (UnitLevel and UnitLevel("player") or 0) >= reqLvl
end

local DIFF_COLORS = {
	red    = { { 1.00, 0.22, 0.22 }, { 1.00, 0.55, 0.25 } },
	orange = { { 1.00, 0.55, 0.15 }, { 1.00, 0.85, 0.30 } },
	yellow = { { 1.00, 0.90, 0.20 }, { 1.00, 1.00, 0.65 } },
	green  = { { 0.28, 1.00, 0.45 }, { 0.80, 1.00, 0.50 } },
	grey   = { { 0.68, 0.72, 0.78 }, { 0.90, 0.92, 0.96 } },
}

local CATEGORY_COLORS = {
	herb     = { { 0.25, 1.00, 0.48 }, { 0.85, 1.00, 0.45 } },
	ore      = { { 1.00, 0.78, 0.18 }, { 1.00, 0.95, 0.55 } },
	chest    = { { 0.25, 0.85, 1.00 }, { 0.95, 0.85, 0.35 } },
	barrel   = { { 0.95, 0.62, 0.28 }, { 1.00, 0.86, 0.55 } },
	fishing  = { { 0.20, 0.68, 1.00 }, { 0.70, 0.95, 1.00 } },
	corpse   = { { 1.00, 0.42, 0.38 }, { 1.00, 0.78, 0.45 } },
	interact = { { 0.68, 0.82, 1.00 }, { 1.00, 1.00, 1.00 } },
	quest    = { { 0.82, 0.42, 1.00 }, { 1.00, 0.82, 0.35 } },
	other    = { { 0.90, 0.90, 1.00 }, { 0.65, 0.80, 1.00 } },
}

local function DifficultyBand(kind, reqSkill)
	local rank = PlayerRankFor(kind)
	if not (rank and reqSkill) then return nil end
	if rank < reqSkill then return "red" end
	if rank < reqSkill + 25 then return "orange" end
	if rank < reqSkill + 50 then return "yellow" end
	if rank < reqSkill + 100 then return "green" end
	return "grey"
end

local function ActiveColors(kind, reqSkill)
	local s = G.db.settings
	if s.colorMode == "difficulty" then
		local band = DifficultyBand(kind, reqSkill)
		if band and DIFF_COLORS[band] then
			local p = DIFF_COLORS[band]
			return p[1][1], p[1][2], p[1][3], p[2][1], p[2][2], p[2][3]
		end
	elseif s.colorMode == "category" and kind and CATEGORY_COLORS[kind] then
		local p = CATEGORY_COLORS[kind]
		return p[1][1], p[1][2], p[1][3], p[2][1], p[2][2], p[2][3]
	end
	local c1, c2 = s.color1 or DEFAULTS.color1, s.color2 or DEFAULTS.color2
	return c1[1], c1[2], c1[3], c2[1], c2[2], c2[3]
end

local function PassesFilters(info)
	local s = G.db and G.db.settings
	if not (s and info) then return false end
	local k = info.k
	if info.quest and s.quests then return true end
	if k == "herb" and not s.herbs then return false end
	if k == "ore" and not s.ore then return false end
	if k == "chest" and not s.chests then return false end
	if k == "barrel" and not s.barrels then return false end
	if k == "fishing" and not s.fishing then return false end
	if k == "corpse" and not s.corpses then return false end
	if k == "interact" and not s.interact then return false end
	if not k then return s.allObjects and true or false end
	if s.smartProf and (k == "herb" or k == "ore") then
		local hasHerb = PlayerRankFor("herb") ~= nil
		local hasMine = PlayerRankFor("ore") ~= nil
		if hasHerb or hasMine then
			if k == "herb" and not hasHerb then return false end
			if k == "ore" and not hasMine then return false end
		end
	end
	return true
end

---------------------------------------------------------------------------
-- High-DPI Multi-Layer Visual Rig (3D World Overlay + Live Preview)
---------------------------------------------------------------------------

local MAX_SPARKLES, NUM_ORBITS = 18, 4

local function CreateVisualRig(parent)
	local rig = CreateFrame("Frame", nil, parent)
	rig:SetSize(120, 120)

	rig.beamAura = rig:CreateTexture(nil, "BACKGROUND")
	ApplyHighResArt(rig.beamAura, nil, "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	rig.beamAura:SetBlendMode("ADD")
	rig.beamAura:SetPoint("BOTTOM", rig, "CENTER", 0, -14)

	rig.beamOuter = rig:CreateTexture(nil, "BORDER")
	ApplyHighResArt(rig.beamOuter, { "GarrMission_EncounterBar-Spark" }, "Interface\\CastingBar\\UI-CastingBar-Spark")
	rig.beamOuter:SetBlendMode("ADD")
	rig.beamOuter:SetPoint("BOTTOM", rig, "CENTER", 0, -10)

	rig.beamCore = rig:CreateTexture(nil, "ARTWORK")
	ApplyHighResArt(rig.beamCore, { "GarrMission_EncounterBar-Spark" }, "Interface\\CastingBar\\UI-CastingBar-Spark")
	rig.beamCore:SetBlendMode("ADD")
	rig.beamCore:SetPoint("BOTTOM", rig, "CENTER", 0, -8)

	rig.ring1 = rig:CreateTexture(nil, "ARTWORK")
	ApplyHighResArt(rig.ring1, { "Artifacts-PerkRing-White" }, "Interface\\SpellActivationOverlay\\IconAlert", 0.08, 0.92, 0.08, 0.92)
	rig.ring1:SetBlendMode("ADD")
	rig.ring1:SetPoint("CENTER")

	rig.ring2 = rig:CreateTexture(nil, "ARTWORK")
	ApplyHighResArt(rig.ring2, { "Artifacts-PerkRing-White" }, "Interface\\Cooldown\\ping4")
	rig.ring2:SetBlendMode("ADD")
	rig.ring2:SetPoint("CENTER")

	rig.corners = {}
	for i = 1, 4 do
		local c = rig:CreateTexture(nil, "OVERLAY")
		c:SetTexture("Interface\\Buttons\\WHITE8x8")
		c:SetBlendMode("ADD")
		SetSmoothFilter(c, true)
		local d = rig:CreateTexture(nil, "OVERLAY")
		d:SetTexture("Interface\\Buttons\\WHITE8x8")
		d:SetBlendMode("ADD")
		SetSmoothFilter(d, true)
		rig.corners[i] = { h = c, v = d }
	end

	rig.orbits = {}
	for i = 1, NUM_ORBITS do
		local o = rig:CreateTexture(nil, "OVERLAY")
		ApplyHighResArt(o, { "CovenantSanctum-Renown-Sparkle", "Legion-Sparkle" }, "Interface\\GLUES\\MODELS\\UI_MainMenu_Legion\\UI_Legion_Sparkle")
		o:SetBlendMode("ADD")
		rig.orbits[i] = o
	end

	rig.sparkles = {}
	for i = 1, MAX_SPARKLES do
		local bloom = rig:CreateTexture(nil, "ARTWORK")
		ApplyHighResArt(bloom, nil, "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
		bloom:SetBlendMode("ADD")

		local flare = rig:CreateTexture(nil, "OVERLAY")
		ApplyHighResArt(flare, { "CovenantSanctum-Renown-Sparkle", "Legion-Sparkle" }, "Interface\\GLUES\\MODELS\\UI_MainMenu_Legion\\UI_Legion_Sparkle")
		flare:SetBlendMode("ADD")

		rig.sparkles[i] = { bloom = bloom, flare = flare }
	end

	rig.label = rig:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rig.label:SetPoint("BOTTOM", rig, "CENTER", 0, 28)
	rig.label:SetShadowOffset(1, -1)
	rig.label:SetShadowColor(0, 0, 0, 1)

	rig.sub = rig:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rig.sub:SetPoint("TOP", rig.label, "BOTTOM", 0, -1)
	rig.sub:SetShadowOffset(1, -1)
	rig.sub:SetShadowColor(0, 0, 0, 1)

	return rig
end

local function FormatSubtitle(info, nodeName)
	local s = G.db and G.db.settings
	if not (s and info) then return nil end
	local parts = {}
	local id = info.id or (nodeName and G.index[nodeName:lower()])
	local fav = id and DT.Market and DT.Market.db and DT.Market.db.favs and DT.Market.db.favs[id]
	if fav then parts[#parts + 1] = "|cffffd100* Fav|r" end
	if s.showPrice and id and DawnMarket and DawnMarket.API and DT.Money then
		local p = DawnMarket.API.GetLatest(id) or DawnMarket.API.GetMedian(id, 7)
		if p and p > 0 then parts[#parts + 1] = DT.Money(p) end
	end
	if info.k == "herb" and IsCultivationReady(info.s) then
		parts[#parts + 1] = "|cff40ff80[Cultivate Ready]|r"
	end
	return #parts > 0 and table.concat(parts, "  ") or nil
end

local function UpdateVisualRig(rig, now, info, nodeName, isPreview)
	local s = G.db and G.db.settings
	if not s then return end
	local kind = info and info.k or "other"
	local r1, g1, b1, r2, g2, b2 = ActiveColors(kind, info and info.s)
	local sc = EffectiveScale(isPreview)
	local baseAlpha = s.alpha or 0.92
	local spd = s.speed or 1.0
	local t = now * spd

	local showBeam = s.fxBeam and true or false
	rig.beamAura:SetShown(showBeam)
	rig.beamOuter:SetShown(showBeam)
	rig.beamCore:SetShown(showBeam)
	if showBeam then
		local pulse = 0.88 + 0.12 * math.sin(t * 2.6)
		rig.beamAura:SetSize(56 * sc * pulse, 136 * sc)
		rig.beamAura:SetVertexColor(r1, g1, b1, baseAlpha * 0.28)
		rig.beamOuter:SetSize(30 * sc * pulse, 130 * sc)
		rig.beamOuter:SetVertexColor(r1, g1, b1, baseAlpha * 0.50)
		rig.beamCore:SetSize(11 * sc, 112 * sc * pulse)
		rig.beamCore:SetVertexColor(math.min(1, r2 + 0.25), math.min(1, g2 + 0.25), math.min(1, b2 + 0.25), baseAlpha * 0.85)
	end

	local showRing = s.fxRing and true or false
	rig.ring1:SetShown(showRing)
	rig.ring2:SetShown(showRing)
	if showRing then
		local p1, p2 = (t * 0.72) % 1, (t * 0.72 + 0.5) % 1
		rig.ring1:SetSize((20 + p1 * 58) * sc, (20 + p1 * 58) * sc)
		rig.ring1:SetVertexColor(r1, g1, b1, (1 - p1) * baseAlpha * 0.85)
		if rig.ring1.SetRotation then rig.ring1:SetRotation(t * 0.55) end

		rig.ring2:SetSize((20 + p2 * 58) * sc, (20 + p2 * 58) * sc)
		rig.ring2:SetVertexColor(r2, g2, b2, (1 - p2) * baseAlpha * 0.72)
		if rig.ring2.SetRotation then rig.ring2:SetRotation(-t * 0.55) end
	end

	local showRet = s.fxReticle and true or false
	local spread = (20 + 2.5 * math.sin(t * 3.2)) * sc
	local arm = 10 * sc
	local thick = math.max(cachedPixelSize * 2, math.floor((2 * sc) / cachedPixelSize + 0.5) * cachedPixelSize)
	local OFF = { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }
	for i, c in ipairs(rig.corners) do
		c.h:SetShown(showRet)
		c.v:SetShown(showRet)
		if showRet then
			local sx, sy = OFF[i][1], OFF[i][2]
			c.h:ClearAllPoints()
			c.h:SetSize(arm, thick)
			c.h:SetPoint("CENTER", rig, "CENTER", sx * spread - sx * arm * 0.5, sy * spread)
			c.h:SetVertexColor(r1, g1, b1, baseAlpha)
			c.v:ClearAllPoints()
			c.v:SetSize(thick, arm)
			c.v:SetPoint("CENTER", rig, "CENTER", sx * spread, sy * spread - sy * arm * 0.5)
			c.v:SetVertexColor(r2, g2, b2, baseAlpha)
		end
	end

	local showOrbit = s.fxOrbit and true or false
	for i, o in ipairs(rig.orbits) do
		o:SetShown(showOrbit)
		if showOrbit then
			local ang = t * 2.4 + (i - 1) * (math.pi * 2 / NUM_ORBITS)
			local depth = 0.75 + 0.25 * math.sin(ang)
			o:ClearAllPoints()
			o:SetPoint("CENTER", rig, "CENTER", math.cos(ang) * 28 * sc, math.sin(ang) * 12 * sc)
			o:SetSize(22 * sc * depth, 22 * sc * depth)
			if o.SetRotation then o:SetRotation(ang * 1.5) end
			if i % 2 == 1 then o:SetVertexColor(r1, g1, b1, baseAlpha * depth)
			else o:SetVertexColor(r2, g2, b2, baseAlpha * depth) end
		end
	end

	local showSpark = s.fxSparkles and true or false
	local count = math.max(4, math.min(MAX_SPARKLES, math.floor(s.density or 12)))
	for i = 1, MAX_SPARKLES do
		local sp = rig.sparkles[i]
		local active = showSpark and (i <= count)
		sp.bloom:SetShown(active)
		sp.flare:SetShown(active)
		if active then
			local p = (t * 1.10 + i * (1 / count) * 3.17) % 1
			local a = math.sin(p * math.pi)
			local sz = (14 + a * 20) * sc
			local x = math.cos(i * 2.399 + t * 0.55) * (25 * sc)
			local y = (-12 + p * 58) * sc
			local cr, cg, cb = r1, g1, b1
			if i % 2 == 0 then cr, cg, cb = r2, g2, b2 end

			sp.bloom:ClearAllPoints()
			sp.bloom:SetPoint("CENTER", rig, "CENTER", x, y)
			sp.bloom:SetSize(sz * 1.35, sz * 1.35)
			sp.bloom:SetVertexColor(cr, cg, cb, a * baseAlpha * 0.45)

			sp.flare:ClearAllPoints()
			sp.flare:SetPoint("CENTER", rig, "CENTER", x, y)
			sp.flare:SetSize(sz, sz)
			if sp.flare.SetRotation then sp.flare:SetRotation((i % 2 == 0 and 1 or -1) * t * 0.9 + i) end
			sp.flare:SetVertexColor(math.min(1, cr + 0.15), math.min(1, cg + 0.15), math.min(1, cb + 0.15), a * baseAlpha)
		end
	end

	local showLabel = s.fxLabel and nodeName and nodeName ~= ""
	rig.label:SetShown(showLabel and true or false)
	if showLabel then
		rig.label:ClearAllPoints()
		rig.label:SetPoint("BOTTOM", rig, "CENTER", 0, 28 * sc)
		rig.label:SetText(nodeName)
		rig.label:SetTextColor(r1, g1, b1, baseAlpha)
		local subText = FormatSubtitle(info, nodeName)
		rig.sub:SetShown(subText ~= nil)
		if subText then rig.sub:SetText(subText) end
	else
		rig.sub:Hide()
	end
end

---------------------------------------------------------------------------
-- 3D World Overlay & Safe CVar Management
---------------------------------------------------------------------------

local TARGET_CVARS = {
	SoftTargetInteract = "3",
	SoftTargetIconGameObject = "1",
	SoftTargetIconInteract = "1",
	SoftTargetLoot = "1",
	SoftTargetNameplateInteract = "1",
	SoftTargetInteractArc = "2",
	SoftTargetInteractRange = "15",
	SoftTargetInteractOnlyInRange = "0",
}

local function ApplyCVars(on)
	if not (GetCVar and SetCVar) then return end
	G.db.savedCVars = G.db.savedCVars or {}
	if on then
		for k, val in pairs(TARGET_CVARS) do
			if G.db.savedCVars[k] == nil then
				local ok, cur = pcall(GetCVar, k)
				if ok and cur ~= nil then G.db.savedCVars[k] = tostring(cur) end
			end
			pcall(SetCVar, k, val)
		end
	else
		for k, prev in pairs(G.db.savedCVars) do
			pcall(SetCVar, k, prev)
		end
		G.db.savedCVars = {}
	end
end

local worldFrame, worldRig
local activePlate, activeInfo, activeName, lastKnownName
local lastChimeAt, lastChimeName = 0, nil

local function PlayChime(forceId)
	local id = forceId or (G.db and G.db.settings and G.db.settings.sound) or "none"
	if id == "none" then return end
	for _, s in ipairs(SOUNDS) do
		if s.id == id and s.kit and PlaySound then
			pcall(PlaySound, s.kit, "SFX")
			return
		end
	end
end

local function SyncWorldTarget()
	if not (worldFrame and G.db and G.db.settings and G.db.settings.enabled) then
		if worldFrame then worldFrame:Hide() end
		activePlate, activeInfo, activeName = nil, nil, nil
		return
	end
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("softinteract")
	local name = UnitName and UnitName("softinteract")
	if name and name ~= "" then lastKnownName = name end
	local info = plate and name and InspectSoftInteract(name)
	if plate and info and PassesFilters(info) then
		local changed = (plate ~= activePlate or name ~= activeName)
		activePlate, activeInfo, activeName = plate, info, name
		local yOff = (G.db.settings.offsetY or 10) * (G.db.settings.autoResScale and cachedResScale or 1.0)
		worldRig:ClearAllPoints()
		worldRig:SetPoint("CENTER", plate, "CENTER", 0, yOff)
		worldFrame:Show()
		if changed then
			local now = GetTime()
			if name ~= lastChimeName or (now - lastChimeAt) > 4 then
				lastChimeAt, lastChimeName = now, name
				PlayChime()
			end
		end
	else
		activePlate, activeInfo, activeName = nil, nil, nil
		worldFrame:Hide()
	end
end

local function EnsureWorldOverlay()
	if worldFrame then return end
	worldFrame = CreateFrame("Frame", "DawnToolsGatherOverlay", UIParent)
	worldFrame:SetAllPoints(UIParent)
	worldFrame:SetFrameStrata("BACKGROUND")
	worldFrame:Hide()
	worldRig = CreateVisualRig(worldFrame)
	worldFrame:SetScript("OnUpdate", function()
		if not (activePlate and activePlate:IsShown()) then
			SyncWorldTarget()
			return
		end
		UpdateVisualRig(worldRig, GetTime(), activeInfo, activeName, false)
	end)
end

function G.SetEnabled(on)
	on = on and true or false
	G.db.settings.enabled = on
	if on then
		UpdateResolutionMetrics()
		G.SyncUnifiedDB()
		G.RebuildIndex()
		EnsureWorldOverlay()
		ApplyCVars(true)
		SyncWorldTarget()
	else
		if worldFrame then worldFrame:Hide() end
		activePlate, activeInfo, activeName = nil, nil, nil
		ApplyCVars(false)
	end
	if DT.Tools and DT.Tools.Show and DT.Tools.Has("gather") then
		DT.Tools.Show()
	end
end

local GATHER_SPELLS = {
	[2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb", [28695] = "herb",
	[2575] = "ore",  [2576] = "ore",  [3564] = "ore",  [10248] = "ore",  [29354] = "ore",
	[3365] = "chest", [1804] = "chest", [6477] = "chest", [6478] = "chest",
}

DT:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if unit ~= "player" or not (G.db and spellID) then return end
	local sName = GetSpellInfo and GetSpellInfo(spellID)
	local kind = GATHER_SPELLS[spellID]
		or (sName and sName:lower():find("herb", 1, true) and "herb")
		or (sName and sName:lower():find("cultivat", 1, true) and "herb")
		or (sName and sName:lower():find("min", 1, true) and "ore")
		or (sName and sName:lower():find("open", 1, true) and "chest")
	local targetName = (UnitName and UnitName("softinteract")) or activeName or lastKnownName
	if kind and targetName and targetName ~= "" then
		seenThisSession[targetName:lower()] = nil
		G.LearnNode(targetName, kind, 1, G.index[targetName:lower()], false)
	end
end)

for _, ev in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
	DT:On(ev, function()
		if ev == "DISPLAY_SIZE_CHANGED" or ev == "UI_SCALE_CHANGED" then
			UpdateResolutionMetrics()
		elseif ev == "QUEST_LOG_UPDATE" then
			for k, v in pairs(seenThisSession) do
				if v.quest then seenThisSession[k] = nil end
			end
		end
		if G.db and G.db.settings and G.db.settings.enabled then SyncWorldTarget() end
	end)
end

DT:On("DT_MARKET_UPDATE", function()
	if G.db then G.RebuildIndex() end
end)

DT:On("PLAYER_LOGOUT", function()
	if G.db and G.db.savedCVars and next(G.db.savedCVars) then
		ApplyCVars(false)
	end
end)

---------------------------------------------------------------------------
-- Color Picker Helper
---------------------------------------------------------------------------

local function OpenColorPicker(colorTable, onChanged)
	if not ColorPickerFrame then return end
	local r, g, b = colorTable[1] or 1, colorTable[2] or 1, colorTable[3] or 1
	local function Apply(nr, ng, nb)
		colorTable[1], colorTable[2], colorTable[3] = nr, ng, nb
		if onChanged then onChanged() end
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, hasOpacity = false,
			swatchFunc = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				Apply(nr, ng, nb)
			end,
			cancelFunc = function(prev)
				if prev then Apply(prev.r, prev.g, prev.b) end
			end,
		})
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.previousValues = { r, g, b }
		ColorPickerFrame.func = function()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			Apply(nr, ng, nb)
		end
		ColorPickerFrame.cancelFunc = function(prev)
			if prev then Apply(prev[1], prev[2], prev[3]) end
		end
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame:Show()
	end
end

---------------------------------------------------------------------------
-- Tools Sub-Tab UI
---------------------------------------------------------------------------

local function SkinCheck(cb) return DT.SkinCheckBox and DT:SkinCheckBox(cb) or cb end
local function SkinBtn(b) return DT.SkinButton and DT:SkinButton(b) or b end
local function SkinBox(f, kind) return DT.SkinFrame and DT:SkinFrame(f, kind) or f end

local function NodeCounts()
	local base, mine, guild = 0, 0, 0
	for _ in pairs(G.baseline) do base = base + 1 end
	for _, n in pairs(G.db and G.db.nodes or {}) do
		if n.r then
			if IsSharing() then guild = guild + 1 end
		else
			mine = mine + 1
		end
	end
	return base, mine, guild
end

local function Build(panel)
	UpdateResolutionMetrics()
	G.SyncUnifiedDB()
	local s = G.db.settings
	local refreshers = {}
	local function RefreshControls()
		for _, fn in ipairs(refreshers) do fn() end
		if DT.UI and DT.UI.Refresh then DT.UI:Refresh() end
	end

	local function Label(parent, font, x, y, text)
		local fs = parent:CreateFontString(nil, "OVERLAY", font)
		fs:SetPoint("TOPLEFT", x, y)
		fs:SetJustifyH("LEFT")
		fs:SetText(text or "")
		return fs
	end

	local function Check(parent, x, y, text, key, onChange)
		local cb = SkinCheck(CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"))
		cb:SetSize(22, 22)
		cb:SetPoint("TOPLEFT", x, y)
		cb.label = Label(cb, "GameFontHighlightSmall", 24, -5, text)
		cb:SetScript("OnClick", function(self)
			local val = self:GetChecked() and true or false
			if onChange then onChange(val) else s[key] = val end
			RefreshControls()
		end)
		refreshers[#refreshers + 1] = function() cb:SetChecked(s[key] and true or false) end
		return cb
	end

	local function Btn(parent, x, y, w, text, click)
		local b = SkinBtn(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
		b:SetSize(w, 20)
		b:SetPoint("TOPLEFT", x, y)
		b:SetText(text)
		b:SetScript("OnClick", function()
			click()
			RefreshControls()
		end)
		return b
	end

	local function StepControl(parent, x, y, labelText, key, minV, maxV, step, fmt)
		Label(parent, "GameFontHighlightSmall", x, y - 3, labelText)
		local readout = Label(parent, "GameFontHighlightSmall", x + 118, y - 3, "")
		readout:SetWidth(46)
		readout:SetJustifyH("CENTER")
		Btn(parent, x + 92, y, 22, "-", function()
			s[key] = math.max(minV, math.floor(((s[key] or minV) - step) * 100 + 0.5) / 100)
		end)
		Btn(parent, x + 168, y, 22, "+", function()
			s[key] = math.min(maxV, math.floor(((s[key] or minV) + step) * 100 + 0.5) / 100)
		end)
		refreshers[#refreshers + 1] = function() readout:SetText(fmt(s[key] or minV)) end
	end

	local y = -4
	Check(panel, 4, y, "|cffffd100Enable Gathering Highlights|r  |cff888888(15-yard soft-target cone; off by default)|r", "enabled", function(on)
		G.SetEnabled(on)
	end)

	y = y - 20
	Check(panel, 4, y, "Share & receive discovered nodes with guild  |cff888888(off = coded + personal finds only)|r", "share", function(on)
		s.share = on
		seenThisSession = {}
		if on then G.SyncUnifiedDB() end
		if s.enabled then SyncWorldTarget() end
	end)

	y = y - 24
	Label(panel, "GameFontNormal", 6, y, "Sparkle Filters & Smart Rules")
	local dbStat = Label(panel, "GameFontDisableSmall", 214, y - 1, "")
	refreshers[#refreshers + 1] = function()
		local b, m, g = NodeCounts()
		if IsSharing() then
			dbStat:SetText(("DB: %d indexed, %d mine, %d guild"):format(b, m, g))
		else
			dbStat:SetText(("DB: %d indexed, %d mine (solo mode)"):format(b, m))
		end
	end

	y = y - 18
	Check(panel, 6, y, "Herbs", "herbs")
	Check(panel, 108, y, "Mining Veins", "ore")
	Check(panel, 224, y, "Treasure & Chests", "chests")
	Check(panel, 356, y, "Barrels & Crates", "barrels")

	y = y - 20
	Check(panel, 6, y, "Fishing & Pools", "fishing")
	Check(panel, 108, y, "Quest Objects", "quests")
	Check(panel, 224, y, "Skinning / Loot", "corpses")
	Check(panel, 356, y, "Lore & Shrines", "interact")

	y = y - 20
	Check(panel, 6, y, "All Objects", "allObjects")
	Check(panel, 108, y, "Smart Profession Filter", "smartProf")
	Check(panel, 268, y, "Tauren Cultivation Prompt", "cultivation")

	y = y - 26
	Label(panel, "GameFontNormal", 6, y, "High-Res Visual Layers")
	y = y - 18
	Check(panel, 6, y, "HD Sparkles", "fxSparkles")
	Check(panel, 160, y, "Light Pillar", "fxBeam")
	Check(panel, 318, y, "Beacon Halo Ring", "fxRing")
	y = y - 20
	Check(panel, 6, y, "Orbiting Motes", "fxOrbit")
	Check(panel, 134, y, "Pixel Reticle", "fxReticle")
	Check(panel, 258, y, "Node Name", "fxLabel")
	Check(panel, 376, y, "AH Price", "showPrice")

	y = y - 26
	Label(panel, "GameFontNormal", 6, y, "Color Mode & Palette")
	local modes = {
		{ id = "custom",     label = "Custom" },
		{ id = "category",   label = "By Node Type" },
		{ id = "difficulty", label = "By Skill Difficulty" },
	}
	local mx = 152
	for _, m in ipairs(modes) do
		local b = Btn(panel, mx, y + 2, m.id == "difficulty" and 118 or 92, m.label, function()
			s.colorMode = m.id
		end)
		refreshers[#refreshers + 1] = function()
			if (s.colorMode or "custom") == m.id then b:LockHighlight() else b:UnlockHighlight() end
		end
		mx = mx + (m.id == "difficulty" and 122 or 96)
	end

	y = y - 22
	local function ColorSwatch(x, title, key)
		local sw = SkinBox(CreateFrame("Button", nil, panel, "BackdropTemplate"), "panel")
		sw:SetSize(22, 18)
		sw:SetPoint("TOPLEFT", x, y)
		local fill = sw:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", 2, -2)
		fill:SetPoint("BOTTOMRIGHT", -2, 2)
		Label(sw, "GameFontHighlightSmall", 28, -3, title)
		sw:SetScript("OnClick", function()
			s.colorMode = "custom"
			OpenColorPicker(s[key], RefreshControls)
		end)
		refreshers[#refreshers + 1] = function()
			local c = s[key] or DEFAULTS[key]
			fill:SetColorTexture(c[1], c[2], c[3], 1)
		end
	end
	ColorSwatch(8, "Primary Color", "color1")
	ColorSwatch(136, "Shimmer Color", "color2")
	Btn(panel, 270, y + 1, 108, "Refresh DB Index", function()
		G.SyncUnifiedDB()
		G.RebuildIndex()
	end)

	y = y - 22
	local px = 8
	for _, p in ipairs(PRESETS) do
		Btn(panel, px, y, 58, p.name, function()
			s.colorMode = "custom"
			if p.class then
				local _, cls = UnitClass and UnitClass("player")
				local tbl = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
				local c = cls and tbl and tbl[cls]
				if c then
					s.color1 = { c.r, c.g, c.b }
					s.color2 = { math.min(1, c.r + 0.25), math.min(1, c.g + 0.25), math.min(1, c.b + 0.25) }
				end
			elseif p.theme and DT.Theme then
				local _, r, g, b = DT:Theme()
				s.color1 = { r, g, b }
				s.color2 = { 1, 0.92, 0.55 }
			else
				s.color1 = { p.c1[1], p.c1[2], p.c1[3] }
				s.color2 = { p.c2[1], p.c2[2], p.c2[3] }
			end
		end)
		px = px + 62
	end

	y = y - 26
	Label(panel, "GameFontNormal", 6, y, "Resolution Scaling, Tuning & Audio")
	local resStat = Label(panel, "GameFontDisableSmall", 248, y - 1, "")
	refreshers[#refreshers + 1] = function()
		UpdateResolutionMetrics()
		resStat:SetText("Display: " .. cachedResLabel)
	end

	y = y - 18
	Check(panel, 6, y, "Auto-scale with screen resolution", "autoResScale")
	StepControl(panel, 232, y - 2, "Height Offset:", "offsetY", -10, 40, 2, function(v) return ("%d px"):format(v) end)

	y = y - 22
	StepControl(panel, 8, y, "Effect Size:", "scale", 0.60, 2.00, 0.10, function(v) return ("%d%%"):format(v * 100) end)
	StepControl(panel, 232, y, "Brightness:", "alpha", 0.30, 1.00, 0.10, function(v) return ("%d%%"):format(v * 100) end)

	y = y - 22
	StepControl(panel, 8, y, "Anim Speed:", "speed", 0.50, 2.00, 0.10, function(v) return ("%.1fx"):format(v) end)
	StepControl(panel, 232, y, "Sparkle Count:", "density", 4, MAX_SPARKLES, 2, function(v) return ("%d"):format(v) end)

	y = y - 24
	Label(panel, "GameFontHighlightSmall", 8, y - 3, "Detection Chime:")
	local sx = 108
	for _, snd in ipairs(SOUNDS) do
		local b = Btn(panel, sx, y, 52, snd.label, function()
			s.sound = snd.id
			if snd.id ~= "none" then PlayChime(snd.id) end
		end)
		refreshers[#refreshers + 1] = function()
			if (s.sound or "none") == snd.id then b:LockHighlight() else b:UnlockHighlight() end
		end
		sx = sx + 56
	end

	-- Right Column: Live Animated Node Preview
	local preview = SkinBox(CreateFrame("Frame", nil, panel, "BackdropTemplate"), "sidebar")
	preview:SetPoint("TOPRIGHT", -6, -6)
	preview:SetPoint("BOTTOMRIGHT", -6, 6)
	preview:SetWidth(264)

	local previewKinds = {
		{ k = "herb",     s = 230, name = "Sungrass",             sub = "Herb Node (Skill 230)",    icon = "Interface\\Icons\\INV_Misc_Herb_11" },
		{ k = "ore",      s = 275, name = "Rich Thorium Vein",    sub = "Mining Vein (Skill 275)",  icon = "Interface\\Icons\\INV_Ore_Thorium_02" },
		{ k = "chest",    s = 1,   name = "Solid Chest",          sub = "Treasure & Chests",        icon = "Interface\\Icons\\INV_Box_01" },
		{ k = "barrel",   s = 1,   name = "Dusty Supply Barrel",  sub = "Barrels & Crates",         icon = "Interface\\Icons\\INV_Misc_Drum_01" },
		{ k = "fishing",  s = 1,   name = "Floating Wreckage",    sub = "Fishing & Pools",          icon = "Interface\\Icons\\INV_Misc_Fish_02" },
		{ k = "quest",    s = 1,   name = "Stolen Supply Crate",  sub = "Active Quest Objective",   icon = "Interface\\Icons\\INV_Crate_01", quest = true },
		{ k = "interact", s = 1,   name = "Ancient Stone Tablet", sub = "Lore & Shrines",           icon = "Interface\\Icons\\INV_Misc_Note_01" },
	}
	local previewIdx = 1

	Label(preview, "GameFontNormal", 10, -10, "Live Effect Preview")
	local pSub = Label(preview, "GameFontDisableSmall", 10, -26, previewKinds[1].sub)

	local cycleBtn = Btn(preview, 10, -10, 114, "Switch Node", function()
		previewIdx = (previewIdx % #previewKinds) + 1
		pSub:SetText(previewKinds[previewIdx].sub)
	end)
	cycleBtn:ClearAllPoints()
	cycleBtn:SetPoint("TOPRIGHT", -10, -10)

	local ground = preview:CreateTexture(nil, "BACKGROUND")
	ground:SetPoint("CENTER", 0, -24)
	ground:SetSize(150, 46)
	ApplyHighResArt(ground, nil, "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	ground:SetVertexColor(0.22, 0.35, 0.20, 0.55)

	local nodeIcon = preview:CreateTexture(nil, "ARTWORK")
	nodeIcon:SetSize(28, 28)
	nodeIcon:SetPoint("CENTER", 0, -20)

	local previewRig = CreateVisualRig(preview)
	previewRig:SetPoint("CENTER", nodeIcon, "CENTER", 0, 6)

	local hint = Label(preview, "GameFontDisableSmall", 10, 0, "High-DPI sparkles auto-scale with screen resolution and sync via DT.DB when enabled.")
	hint:ClearAllPoints()
	hint:SetPoint("BOTTOMLEFT", 10, 10)
	hint:SetPoint("BOTTOMRIGHT", -10, 10)
	hint:SetWordWrap(true)

	preview:SetScript("OnUpdate", function()
		local cur = previewKinds[previewIdx]
		nodeIcon:SetTexture(cur.icon)
		UpdateVisualRig(previewRig, GetTime(), cur, cur.name, true)
	end)

	RefreshControls()
end

---------------------------------------------------------------------------
-- Module & Tool Registration
---------------------------------------------------------------------------

DT:RegisterModule("gather", {
	profile = { "settings" },
	title = "Gather",
	version = 3,
	defaultOff = true,
	defaults = DEFAULTS,
	settings = {
		{ key = "enabled", label = "Enable 3D gathering highlights (15-yard soft-target cone)" },
		{ key = "share",   label = "Share discovered gathering nodes with the guild (and receive theirs)" },
	},
	status = function(mod)
		local b, m, g = NodeCounts()
		local state = mod.db.settings.enabled and "|cff40ff40Active|r" or "|cff888888Off (default)|r"
		if IsSharing() then
			return ("%s — %d indexed, %d mine, %d from guild"):format(state, b, m, g)
		end
		return ("%s — %d indexed, %d mine (solo mode; not sharing)"):format(state, b, m)
	end,
	onEnable = function(mod)
		if DT.modules.gather_sync then
			DT.modules.gather_sync.enabled = true
		end
		mod.db.nodes = mod.db.nodes or {}
		mod.db.peers = mod.db.peers or {}
		G.db = mod.db
		UpdateResolutionMetrics()
		G.SyncUnifiedDB()
		G.RebuildIndex()
		InitGossip()
		DT:On("DT_SETTINGS", function(name, key)
			if name == "gather" then
				if key == "enabled" then
					G.SetEnabled(mod.db.settings.enabled)
				elseif key == "share" then
					seenThisSession = {}
					if mod.db.settings.share then G.SyncUnifiedDB() end
					if mod.db.settings.enabled then SyncWorldTarget() end
				end
			end
		end)
		if mod.db.settings.enabled then
			G.SetEnabled(true)
		end
		DT:RegisterTool({
			id = "gather",
			title = "Gather",
			order = 45,
			create = Build,
			active = function() return mod.db.settings.enabled and true or false end,
		})
	end,
})