-- DawnTools :: Finds
-- What the game shows me is noted in the store (Core/DB.lua) where it is not known yet, and World > Finds
-- lists what of it QuestieDB has no entry for: the guild's own finds. With the game database shared it all
-- passes to the guild with the rest of the store. No name of who found it.
--
--   npc:<number>     = name;level;zone;x;y[;1][;m<map>]   targeted or moused over; "1" once I talked to it,
--                                                  traded with it or looted it: then x, y are where it stands
--   item:<number>    = name;quality                in a loot window, my bags, a vendor's window, the auction data
--   quest:<number>   = title;giver's NPC number;zone;x;y[;m<map>]    as a quest giver offered it
--   object:<number>  = ;;zone;x;y;1[;m<map>]       a chest or node I looted (the game does not name it to an addon)
-- x, y: in percent of the map I was on, whose number is the last part (for a waypoint). DT.DB.Sighting reads
-- these rows; the NPC and Quests tabs list them beside what QuestieDB knows.
--
-- "Known" is asked of QuestieDB where it is installed: what it has an entry for is not written down at all.
-- Without QuestieDB everything met is written down (nothing is known yet), and nothing is called a find:
-- a member who has QuestieDB sees which of it is one.
-- ponytail: the game tells an addon where I am, never where another creature is. So an NPC's place is mine when
-- I met it: exact once I stood at it (talked, traded, looted), up to some forty yards off before.

local _, DT = ...
local DB = DT.DB
local F = {}
DT.Finds = F

local ROW_H, TOP_H = 18, 28
local panel, note
local rows, list, offset = {}, {}, 0
local dirty = true
local looked = {} -- ["npc:12"] = true: looked up this session (one look a number)
local KINDS = { npc = "|cffff8040NPC|r", item = "|cff40c0ffItem|r", quest = "|cffffd100Quest|r", object = "|cff80ff80Object|r" }

-- is QuestieDB there to say what is known
local function Judge()
	local lib = DB.Questie()
	return lib ~= nil and lib.Npc ~= nil and lib.Item ~= nil
end

-- known: QuestieDB has it, here or (its rows having come with the store) on a guildmate's machine
local function Known(kind, id)
	local row = DB.Row(kind .. ":" .. id)
	if row and DT.DBLogic.Base(row) then return true end
	if not Judge() then return false end
	local name = DB.Q(kind, id, "name")
	return type(name) == "string" and name ~= ""
end

-- can anything be told apart here: QuestieDB installed, or its rows in the store (mine, or a guildmate's)
local function CanTell()
	return Judge() or DB.Base("questie") ~= nil or DB.Row("base:questie") ~= nil
end

-- where I stand: "zone;x;y" (x, y in percent of the map, one decimal), or the zone alone; and, to end the row
-- with, ";m<the map's number>" (or "")
local function Here()
	local zone = (GetRealZoneText and GetRealZoneText() or ""):gsub(";", ",")
	local ok, x, y, map = pcall(function()
		local map = C_Map.GetBestMapForUnit("player")
		local pos = C_Map.GetPlayerMapPosition(map, "player")
		local x, y = pos:GetXY()
		return x, y, map
	end)
	if ok and type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) and not (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then
		return ("%s;%.1f;%.1f"):format(zone, x * 100, y * 100), type(map) == "number" and (";m%d"):format(map) or ""
	end
	return zone, ""
end

-- A thing the game showed: written down unless it is known. Returns true where it was.
function F.Seen(kind, id, value)
	local key = kind .. ":" .. tostring(id)
	if type(id) ~= "number" or id <= 0 or looked[key] then return false end
	looked[key] = true
	if Known(kind, id) or DB.Row(key) then return false end
	DB.Put(key, value)
	dirty = true
	return true
end

-- the NPC number of a unit, where it is one
local function NpcOf(unit)
	if not (UnitGUID and UnitExists and UnitExists(unit)) then return end
	local guid = UnitGUID(unit)
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- near: I stand at it (I talk to it, trade with it), so where I am is where it is
local function Unit(unit, near)
	local id = NpcOf(unit)
	if not id then return end
	local key = "npc:" .. id
	if looked[key] and not near then return end
	local name, level = UnitName(unit), UnitLevel and UnitLevel(unit) or 0
	if type(name) ~= "string" or (issecretvalue and (issecretvalue(name) or issecretvalue(level))) then return end
	local here, map = Here()
	local value = ("%s;%d;%s"):format(name:gsub(";", ","), tonumber(level) or 0, here) .. (near and ";1" or "") .. map
	if F.Seen("npc", id, value) then return end
	-- (written down from afar before: now that I stand at it, its place is put right)
	local row = near and DB.Row(key)
	if row and not DB.Sighting("npc", row.v).near and DB.Sighting("npc", value).near and not Known("npc", id) then
		DB.Put(key, value)
		dirty = true
	end
end

-- the loot window that is open: its items, and the chest or node it is the loot of
local function Loot()
	if not (GetNumLootItems and GetLootSlotLink) then return end
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then
			local _, name, _, _, quality = GetLootSlotInfo(slot)
			F.Seen("item", id, ("%s;%d"):format(type(name) == "string" and name or link:match("%[(.-)%]") or "", tonumber(quality) or 0))
		end
		for _, guid in ipairs({ GetLootSourceInfo and GetLootSourceInfo(slot) }) do
			if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
				local kind, source = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
				-- (a chest or node: I stand at it, and the game gives an addon no name for it)
				if kind == "GameObject" then
					local here, map = Here()
					F.Seen("object", tonumber(source), (";;%s;1%s"):format(here, map))
				end
			end
		end
	end
end

-- an item by its number: written down with what the game says of it, where the game knows it
-- (one the game does not know yet is asked once, not at every sweep: GET_ITEM_INFO_RECEIVED lifts the wait)
local pending = {}
local function Item(id)
	if looked["item:" .. id] or pending[id] then return end
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, name, _, quality = pcall(function() return info(id) end)
	if ok and name then F.Seen("item", id, ("%s;%d"):format(name, tonumber(quality) or 0)) else pending[id] = true end
end

-- what I carry and bank (Inventory's count), what a vendor shows, what the auction house showed (Market's)
function F.Sweep()
	local Inv = DT.Inventory
	local mine = Inv and Inv.db and Inv.db.chars and Inv.db.chars[Inv.me]
	for _, bag in ipairs({ mine and mine.bags or {}, mine and mine.bank or {} }) do
		for id in pairs(bag) do Item(id) end
	end
	for id, item in pairs(DT.Market and DT.Market.items or {}) do
		if type(item) == "table" and item.n then Item(id) end
	end
end

local function Merchant()
	Unit("npc", true)
	for i = 1, GetMerchantNumItems and GetMerchantNumItems() or 0 do
		local link = GetMerchantItemLink and GetMerchantItemLink(i)
		local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then Item(id) end
	end
end

-- a quest giver offers a quest
local function Quest()
	Unit("npc", true)
	local id = GetQuestID and GetQuestID()
	local title = GetTitleText and GetTitleText()
	if type(id) ~= "number" or type(title) ~= "string" or title == "" then return end
	local here, map = Here()
	F.Seen("quest", id, ("%s;%s;%s%s"):format(title:gsub(";", ","), tostring(NpcOf("npc") or ""), here, map))
end

-- Everything written down, the newest first: { kind, id, name, more, t }. finds: only what QuestieDB does not
-- know (with QuestieDB not installed: nothing, as nothing can be told apart).
function F.All(finds)
	local out = {}
	if finds and not CanTell() then return out end
	for chunk in pairs(DB.Hashes()) do
		local kind = chunk:match("^(%a+):")
		if KINDS[kind] then
			for line in (DB.Text(chunk) or ""):gmatch("[^\n]+") do
				local id, t, src, v = line:match("^%a+:(%d+)\t(%d+)\t([^\t]*)\t(.*)$")
				id = tonumber(id)
				if id and not (finds and (src ~= "guild" or Known(kind, id))) then
					local name = v:match("^([^;]*)")
					out[#out + 1] = { kind = kind, id = id, name = name ~= "" and name or (kind .. " " .. id), t = tonumber(t),
						seen = src == "guild" and DB.Sighting(kind, v) or {} }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		if a.kind ~= b.kind then return a.kind < b.kind end
		return a.id < b.id
	end)
	return out
end

-- "level 23, Stonetalon Mountains 45.2, 60.1 (seen from afar)"
local function Place(s)
	if not s.zone then return "" end
	if not (s.x and s.y) then return s.zone end
	return ("%s %.1f, %.1f%s"):format(s.zone, s.x, s.y, s.near and "" or " |cff666666(seen from afar)|r")
end

local function About(f)
	local s = f.seen
	if f.kind == "npc" then
		local at = Place(s)
		return (s.level and s.level > 0 and ("level " .. s.level .. (at ~= "" and ", " or "")) or "") .. at
	elseif f.kind == "quest" then
		local who = s.giver and DB.Name("npc", s.giver) or nil
		return (who and ("from " .. who .. ", ") or "") .. Place(s)
	elseif f.kind == "object" then
		return Place(s)
	end
	return ""
end
F.About = About

local function Refresh()
	if not panel then return end
	dirty = false
	if not (InCombatLockdown and InCombatLockdown()) then F.Sweep() end
	list = F.All(true)
	local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H) / ROW_H))
	offset = math.max(0, math.min(offset, math.max(0, #list - fit)))
	note:SetText(not CanTell() and "|cff888888QuestieDB is not installed. What you meet is still written down and (if you share) passed on; which of it is a find only shows where QuestieDB is there to say what is known.|r"
		or #list == 0 and "|cff888888Nothing yet. NPCs you target, items you loot or carry, quests you are offered and chests you open are listed here where QuestieDB does not know them.|r"
		or ("%d find%s: what the guild met that QuestieDB does not know, the newest first."):format(#list, #list == 1 and "" or "s"))
	for i = 1, math.max(fit, #rows) do
		local f = i <= fit and list[offset + i]
		local row = rows[i]
		if f and not row then
			row = CreateFrame("Button", nil, panel)
			row:SetHeight(ROW_H)
			row:SetPoint("TOPLEFT", 6, -TOP_H - (i - 1) * ROW_H)
			row:SetPoint("TOPRIGHT", -6, -TOP_H - (i - 1) * ROW_H)
			local highlight = row:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.06)
			row.cells = {}
			for c, x in ipairs({ 4, 130, 190, 430 }) do
				local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				fs:SetPoint("LEFT", x, 0)
				fs:SetWidth(({ 122, 56, 236, 420 })[c])
				fs:SetJustifyH("LEFT")
				fs:SetWordWrap(false)
				row.cells[c] = fs
			end
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row:SetScript("OnEnter", function(self)
				local f2 = self.find
				if not f2 then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if f2.kind == "item" then
					GameTooltip:SetHyperlink("item:" .. f2.id)
				else
					GameTooltip:AddLine(f2.name)
					GameTooltip:AddLine(f2.seen.x and "Click: waypoint to where it was met." or "No place was noted for it.", 0.5, 0.8, 1)
				end
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
			row:SetScript("OnClick", function(self, button)
				local f2 = self.find
				if not f2 then return end
				if f2.kind == "item" then
					DT:LinkClick(button, DT:GameItemLink(f2.id, f2.name), f2.name, DT:ItemLink(f2.id), f2.id)
				elseif DT.Npc and DT.Npc.PinSeen then
					DT.Npc.PinSeen(f2.seen, f2.name)
				end
			end)
			rows[i] = row
		end
		if row then
			row.find = f or nil
			row:SetShown(f and true or false)
			if f then
				row.cells[1]:SetText(date("%a %d %b %H:%M", f.t))
				row.cells[2]:SetText(KINDS[f.kind])
				row.cells[3]:SetText(f.name)
				row.cells[4]:SetText(("|cff888888%s  #%d|r"):format(About(f), f.id))
			end
		end
	end
end
F.Refresh = Refresh
F.rows = rows

local function Build(parent)
	panel = parent
	note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 10, -8)
	note:SetPoint("TOPRIGHT", -10, -8)
	note:SetJustifyH("LEFT")
	note:SetWordWrap(false)
	F.note = note
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Refresh()
	end)
	panel:SetScript("OnSizeChanged", Refresh)
	local nextUpdate = 0
	panel:SetScript("OnUpdate", function()
		if not dirty or GetTime() < nextUpdate then return end
		if InCombatLockdown and InCombatLockdown() then return end
		nextUpdate = GetTime() + 0.5
		Refresh()
	end)
end

DT:RegisterModule("finds", {
	title = "Finds",
	version = 1,
	slash = "/dtfinds",
	tab = { id = "finds", title = "Finds", defaultOrder = 59.8, under = "world", create = Build, onShow = Refresh },
	onEnable = function()
		DT:On("PLAYER_TARGET_CHANGED", function() Unit("target") end)
		DT:On("UPDATE_MOUSEOVER_UNIT", function() Unit("mouseover") end)
		DT:On("GOSSIP_SHOW", function() Unit("npc", true) end)
		DT:On("MERCHANT_SHOW", Merchant)
		DT:On("QUEST_DETAIL", Quest)
		DT:On("LOOT_OPENED", Loot)
		DT:On("DT_DB_UPDATE", function() dirty = true end) -- (a member's finds came in)
		DT:On("GET_ITEM_INFO_RECEIVED", function(id, success)
			if pending[id] and success ~= false then pending[id], dirty = nil, true end
		end)
	end,
})
