-- DawnTools :: Core
-- Saved data, events, chat output, the module registry, slash commands, the minimap button.

local ADDON, DT = ...
_G.DawnTools = DT

DT.VERSION = "0.36.1" -- keep in step with the .toc
DT.LOGO = "Interface\\AddOns\\DawnTools\\logo"

local DEFAULTS = {
	instances = false, -- send guild messages inside instances too
	background = true, -- read NPCs, quests and items a little at a time after login, so their tabs open at once
	coins = true,      -- prices with the game's coin pictures (off: "1g 20s 5c")
}

---------------------------------------------------------------------------
-- Events: game events and our own share one table. DT:On("EVENT", fn), DT:Fire("EVENT", ...)
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function DT:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		-- our own events are not game events: RegisterEvent raises an error for those
		-- (pcall: a game event this client does not know must not stop the addon from loading)
		if not event:find("^DT_") then pcall(frame.RegisterEvent, frame, event) end
	end
	table.insert(handlers[event], fn)
end

-- (each handler on its own: one that fails is reported and the rest still run)
function DT:Fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then geterrorhandler()(err) end
	end
end

frame:SetScript("OnEvent", function(_, event, ...) DT:Fire(event, ...) end)

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

function DT:Print(msg, ...)
	if select("#", ...) > 0 then msg = msg:format(...) end
	print("|cffc6ad5eDawnTools|r: " .. msg)
end

-- /dt debug <module>
function DT:Debug(module, msg, ...)
	if self.db and self.db.debug[module] then self:Print("|cff888888[" .. module .. "] " .. msg .. "|r", ...) end
end

-- A price for showing: with the game's coin pictures, or as "1g 20s 5c" where the player prefers letters.
-- (Logic.Money is the plain text, for anything a picture cannot go into.)
local COIN = {
	"|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	"|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	"|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
-- The skill band of the recipe that makes an item (Data/CraftSkill.lua), as the Professions window colours it:
-- learned at (orange), yellow, green, grey. Returns the band as text and the profession's name; nothing for an
-- item no profession makes. "?" where the skill it is learned at is not known.
local PROFESSION = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
	[185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }
function DT.CraftBand(item)
	local b = DT.CraftSkill and DT.CraftSkill[item]
	if not b then return nil end
	return ("|cffff8040%s|r |cffffff00%d|r |cff40c040%d|r |cff808080%d|r"):format(b[2] > 0 and b[2] or "?", b[3], b[4], b[5]),
		PROFESSION[b[1]] or "Profession"
end

function DT.Money(copper)
	if not (DT.db and DT.db.settings.coins) then return DT.Logic.Money(copper) end
	local c = math.floor(math.abs(copper) + 0.5)
	local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
	c = c % 100
	local text = g > 0 and ("%d%s %d%s %d%s"):format(g, COIN[1], s, COIN[2], c, COIN[3])
		or s > 0 and ("%d%s %d%s"):format(s, COIN[2], c, COIN[3]) or ("%d%s"):format(c, COIN[3])
	return copper < 0 and "-" .. text or text
end

-- server time: the same clock for every guild member
function DT.Now()
	return GetServerTime and GetServerTime() or time()
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
-- DT:RegisterModule("market", {
--   title    = "Market",
--   version  = 1,
--   defaults = { key = value },                    the module's settings
--   settings = { { key = "x", label = "..." } },   checkboxes on the Settings tab
--   status   = function(mod) return "one line" end shown under them
--   tab      = { id, title, defaultOrder, create = function(parent) end, onShow = fn, onHide = fn,
--                group = 2,                        tabs of another group stand apart on the bar (default 1)
--                under = "world" },                not on the bar itself: a sub-tab of that place (see UI.lua)
--   slash    = "/dtmarket",                         opens the tab, if nobody else owns the command
--   onEnable = function(mod) end,                  at login, unless the module is switched off
--   hello    = function(mod) return "summary" end, sent along with the core's HELLO
--   onHello  = function(mod, sender, summary) end,
--   onMessage = function(mod, kind, payload, sender) end,
-- })
-- The core sets mod.name, mod.db (its saved table, with .settings) and mod.enabled.

DT.modules, DT.order = {}, {}

function DT:RegisterModule(name, mod)
	mod.name = name
	self.modules[name] = mod
	self.order[#self.order + 1] = name
end

-- for _, mod in DT:Enabled() do
function DT:Enabled()
	local list = {}
	for _, name in ipairs(self.order) do
		if self.modules[name].enabled then list[#list + 1] = self.modules[name] end
	end
	return ipairs(list)
end

---------------------------------------------------------------------------
-- Reading in the background
---------------------------------------------------------------------------
-- The long lists (NPCs, quests, items) are read from QuestieDB the first time their tab is looked at, which
-- takes a second or two. With DT.db.settings.background they are read a few seconds after login instead, one
-- after the other, about 2 ms a frame, not in combat: the tabs then open at once.
--   DT:Background({ Start = function() return true when there is something to read end,
--                   Step  = function(ms) read on for about ms; return true when done end })
local readers = {}
local reader = CreateFrame("Frame")
reader:Hide()
reader:SetScript("OnUpdate", function(self)
	if InCombatLockdown and InCombatLockdown() then return end
	local r = readers[1]
	if not r then return self:Hide() end
	-- (a list that fails to read is reported once and dropped: the others still get their turn)
	local ok, done
	if not r.begun then
		r.begun = true
		ok, done = pcall(r.Start)
		done = ok and not done
	else
		ok, done = pcall(r.Step, 2)
	end
	if not ok then
		table.remove(readers, 1)
		geterrorhandler()(done)
	elseif done then
		table.remove(readers, 1)
	end
end)

-- the setting switched on in mid-session: begin now (off: what is being read stops at once)
function DT:ReadInBackground(on)
	reader:SetShown(on and #readers > 0 or false)
end

function DT:Background(r)
	readers[#readers + 1] = r
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
-- DawnToolsDB (account-wide):
--   settings   see DEFAULTS
--   modules    [name] = false       switched off on the Settings tab
--   debug      [name] = true
--   tabs       { rank = { [id] = n }, hidden = { [id] = true } }
--   pos, size  window position, { width, height }
--   lastTab    id
--   minimap    { hide, minimapPos = degrees round the minimap } (the shape LibDBIcon kept, which drew the button once)
--   [name]     each module's own table; .settings holds its settings

local function Init()
	DawnToolsDB = DawnToolsDB or {}
	local db = DawnToolsDB
	-- this character's profile, before anything reads the tables (Profiles.lua)
	if DT.Profiles then DT.Profiles.Login(db) end
	-- (whatever has got into the saved data, these are tables when anything reads them)
	for _, key in ipairs({ "settings", "modules", "debug", "minimap" }) do
		if type(db[key]) ~= "table" then db[key] = {} end
	end
	if type(db.tabs) ~= "table" then db.tabs = {} end
	if type(db.tabs.rank) ~= "table" then db.tabs.rank = {} end
	if type(db.tabs.hidden) ~= "table" then db.tabs.hidden = {} end
	if type(db.tabs.sub) ~= "table" then db.tabs.sub = nil end
	if type(db.pos) ~= "table" or type(db.pos[1]) ~= "string" or type(db.pos[2]) ~= "string" or type(db.pos[3]) ~= "number" or type(db.pos[4]) ~= "number" then db.pos = nil end
	if type(db.size) ~= "table" or type(db.size[1]) ~= "number" or type(db.size[2]) ~= "number" then db.size = nil end
	if type(db.lastTab) ~= "string" then db.lastTab = nil end
	if type(db.settingsSection) ~= "string" then db.settingsSection = nil end
	for key, value in pairs(DEFAULTS) do
		if db.settings[key] == nil then db.settings[key] = value end
	end
	for _, name in ipairs(DT.order) do
		local mod = DT.modules[name]
		if type(db[name]) ~= "table" then db[name] = {} end
		if type(db[name].settings) ~= "table" then db[name].settings = {} end
		for key, value in pairs(mod.defaults or {}) do
			if db[name].settings[key] == nil then db[name].settings[key] = value end
		end
		mod.db = db[name]
		mod.enabled = db.modules[name] ~= false
	end
	DT.db = db
end

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------

local function Probe()
	-- SPEC phase 0: which of the things we rely on exist on this client
	local names = {
		"C_AuctionHouse.GetNumCommoditySearchResults", "C_AuctionHouse.GetCommoditySearchResultInfo",
		"C_AuctionHouse.GetNumItemSearchResults", "C_AuctionHouse.GetItemSearchResultInfo", "C_AuctionHouse.GetBrowseResults",
		"C_AuctionHouse.GetItemKeyInfo", "C_AuctionHouse.SendBrowseQuery", "C_AuctionHouse.RequestMoreBrowseResults",
		"C_AuctionHouse.HasFullBrowseResults", "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems", "C_AuctionHouse.GetReplicateItemInfo",
		"C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage", "C_Item.GetItemInfo",
		"C_Item.RequestLoadItemDataByID", "C_Container.GetContainerItemInfo", "UnitGUID", "CombatLogGetCurrentEventInfo", "GetServerTime", "IsInGuild", "IsInInstance",
		"InCombatLockdown", "Ambiguate", "TooltipDataProcessor.AddTooltipPostCall", "StaticPopup_Show",
		"Auctionator.API.v1.GetAuctionPriceByItemID", "Auctionator.API.v1.GetAuctionAgeByItemID",
		"Auctionator.API.v1.RegisterForDBUpdate",
		"LibQuestieDB.Npc.GetAllIds", "LibStub", "TargetFrame", "FocusFrame", "OpenWorldMap", "WorldMapFrame.SetMapID", "SLASH_PING1", "C_Ping", "SLASH_TARGET_MARKER1", "C_Spell.GetSpellPowerCost", "GetSpellPowerCost", "PlayerFrame", "PlayerFrameManaBar", "issecretvalue", "UnitCanAttack", "C_SpellBook.GetSpellBookItemInfo", "C_Spell.IsSpellInRange", "C_Spell.GetSpellInfo", "IsSpellInRange", "GetSpellTabInfo", "UnitPosition", "LibQuestieDB.Quest.GetAllIds", "LibQuestieDB.Item.GetAllIds", "LibQuestieDB.Object.Get", "GetItemStats", "C_Item.GetItemStats", "AtlasLoot.Data.Profession.GetCraftSpellForCreatedItem", "C_QuestLog.GetAllCompletedQuestIDs", "C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.IsOnQuest", "C_QuestLog.GetQuestTagInfo", "GetQuestTagInfo", "GetQuestsCompleted", "QuestieLoader.ImportModule", "TomTom.AddWaypoint", "C_Map.GetAreaInfo", "C_Map.SetUserWaypoint",
		"UiMapPoint.CreateFromCoordinates", "C_SuperTrack.SetSuperTrackedUserWaypoint", "debugprofilestop",
	}
	local missing = {}
	for _, name in ipairs(names) do
		local value = _G
		for part in name:gmatch("[^.]+") do value = type(value) == "table" and value[part] or nil end
		if type(value) ~= "function" then missing[#missing + 1] = name end
	end
	DT:Print("probe: %d of %d functions exist.%s", #names - #missing, #names,
		#missing > 0 and (" Missing: " .. table.concat(missing, ", ")) or "")

	local events = { "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
		"AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "REPLICATE_ITEM_LIST_UPDATE", "GET_ITEM_INFO_RECEIVED", "CHAT_MSG_ADDON", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "COMBAT_LOG_EVENT_UNFILTERED", "MERCHANT_SHOW", "LOOT_READY", "TRADE_SKILL_SHOW" }
	local unknown, tester = {}, CreateFrame("Frame")
	for _, event in ipairs(events) do
		local ok
		if C_EventUtils and C_EventUtils.IsEventValid then
			ok = C_EventUtils.IsEventValid(event)
		else
			ok = pcall(tester.RegisterEvent, tester, event)
		end
		if not ok then unknown[#unknown + 1] = event end
	end
	tester:UnregisterAllEvents()
	DT:Print("probe: %d of %d events exist.%s", #events - #unknown, #events,
		#unknown > 0 and (" Unknown: " .. table.concat(unknown, ", ")) or "")

	-- Which auction house is this? Run at each kind of auctioneer and compare the lines: whatever differs
	-- (the auctioneer's id, its faction, the zone) is what can tell the houses apart.
	local npc = UnitGUID and UnitGUID("npc")
	if npc then
		DT:Print("probe: auctioneer '%s', id %s, faction %s, zone '%s' / '%s', map %s, my faction %s.",
			tostring(UnitName("npc")), tostring(npc:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)") or npc),
			tostring(UnitFactionGroup and UnitFactionGroup("npc") or "?"),
			tostring(GetZoneText and GetZoneText() or "?"), tostring(GetSubZoneText and GetSubZoneText() or "?"),
			tostring(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or "?"),
			tostring(UnitFactionGroup and UnitFactionGroup("player") or "?"))
	else
		DT:Print("probe: no auctioneer open. Run this with the auction house window open to see which house it is.")
	end

	local peers = 0
	for _ in pairs(DT.Comms.peers) do peers = peers + 1 end
	DT:Print("probe: I am '%s', guild '%s', on the wire '%s'. %d guild members with DawnTools heard this session.",
		tostring(DT.me), tostring(GetGuildInfo and GetGuildInfo("player") or nil), tostring(DT.Comms.self or "not heard yet"), peers)
end

-- true when no addon has claimed the command (SLASH_FOO1 = "/dt")
local function SlashFree(cmd)
	for key, value in pairs(_G) do
		if type(value) == "string" and type(key) == "string" and value:lower() == cmd and key:find("^SLASH_") then return false end
	end
	return true
end

local function Slash(input)
	local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		DT.UI:Toggle()
	elseif DT.UI:HasTab(cmd) then
		DT.UI:Show(cmd)
	elseif DT.Tools and DT.Tools.Has(cmd) and DT.UI:HasTab("tools") then -- (a tool of the Tools tab, by name)
		DT.Tools.Open(cmd)
	elseif cmd == "debug" and DT.modules[rest:lower()] then
		local name = rest:lower()
		DT.db.debug[name] = not DT.db.debug[name] or nil
		DT:Print("debug %s %s", name, DT.db.debug[name] and "on" or "off")
	elseif cmd == "reset" then
		DT.UI:ResetWindow()
		DT:Print("window back to its first size and place.")
	elseif cmd == "probe" then
		Probe()
	elseif cmd == "sync" then
		DT.Comms:Diagnose()
	elseif cmd == "deathtest" then
		if DT.Combat and DT.Combat.DeathReport then DT.Combat.DeathReport() else DT:Print("deathtest: the Combat module is switched off.") end
	elseif cmd == "logtest" then
		-- An experiment: can the lines the game printed in the Combat Log chat tab be read? Reads, changes nothing.
		local frame = COMBATLOG
		for i = 1, NUM_CHAT_WINDOWS or 10 do
			local f = _G["ChatFrame" .. i]
			if not frame and f and IsCombatLog and IsCombatLog(f) then frame = f end
		end
		frame = frame or ChatFrame2
		if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then
			DT:Print("logtest: no Combat Log chat tab that can be read was found.")
			return
		end
		local n = frame:GetNumMessages()
		DT:Print(("logtest: %s holds %d lines. The last %d, as written:"):format(frame:GetName() or "the tab", n, math.min(n, 6)))
		for i = math.max(1, n - 5), n do
			local ok, text = pcall(frame.GetMessageInfo, frame, i)
			if not ok then
				DT:Print(("  %d: reading failed: %s"):format(i, tostring(text)))
			elseif issecretvalue and issecretvalue(text) then
				DT:Print(("  %d: HIDDEN by the game (a secret value)"):format(i))
			else
				DT:Print(("  %d: %s"):format(i, tostring(text):gsub("|", "||"):sub(1, 400)))
			end
		end
	elseif cmd == "selftest" then
		DT.UI:SelfTest()
	else
		local tabs = {}
		for _, mod in DT:Enabled() do
			for _, tab in ipairs(mod.tabs or { mod.tab }) do tabs[#tabs + 1] = tab.id end
		end
		tabs[#tabs + 1] = "settings"
		DT:Print("/dt (window) | /dt %s | /dt debug <%s> | /dt probe | /dt sync (guild messages: what goes out and comes in) | /dt selftest | /dt reset (window size and place)",
			table.concat(tabs, " | /dt "), table.concat(DT.order, "|"))
	end
end

-- An addon cannot open a browser: the link is shown in a box, ready to copy.
StaticPopupDialogs.DAWNTOOLS_LINK = {
	text = "%s\n\nCopy the link with Ctrl+C and paste it into your browser.",
	button1 = CLOSE or "Close", hasEditBox = true, editBoxWidth = 320, maxLetters = 0, -- (0: as long as it likes)
	OnShow = function(self, url)
		local box = self.editBox or self.EditBox
		if not box then return end
		box:SetText(url)
		box:HighlightText()
		box:SetFocus()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- any text to copy (a profile, say), with words that fit
StaticPopupDialogs.DAWNTOOLS_COPY = {
	text = "%s\n\nCtrl+C copies it.",
	button1 = CLOSE or "Close", hasEditBox = true, editBoxWidth = 320, maxLetters = 0, -- (0: as long as it likes)
	OnShow = StaticPopupDialogs.DAWNTOOLS_LINK.OnShow,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function DT:ShowCopy(title, text)
	StaticPopup_Show("DAWNTOOLS_COPY", title, nil, text)
end

function DT:ShowLink(title, url)
	StaticPopup_Show("DAWNTOOLS_LINK", title, nil, url)
end

-- A click on a row with Shift held, as on anything in the game: the left button puts its link into the chat
-- line being written (a line is opened if none is); the right button shows its web page, to copy.
-- Returns true when Shift was held (the click is dealt with).
function DT:LinkClick(button, link, title, url)
	if not (IsShiftKeyDown and IsShiftKeyDown()) then return false end
	if button == "RightButton" then
		self:ShowLink(title, url)
	elseif link then
		local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
		local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
		if not (insert and insert(link)) and open then open(link) end
	end
	return true
end

-- Shift held over one of our item rows: the game's own comparison with what I wear, beside the tooltip, as over
-- an item in the bags (also where the game is set to compare always). DT:CompareTip(owner) after the row's
-- tooltip is shown; pressing or letting go of Shift while it is up shows or hides the comparison.
local compared
local function Compare()
	if not (compared and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(compared)) then return end
	local always = GetCVarBool and GetCVarBool("alwaysCompareItems")
	if (IsShiftKeyDown and IsShiftKeyDown()) or always then
		if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
	elseif GameTooltip_HideShoppingTooltips then
		pcall(GameTooltip_HideShoppingTooltips, GameTooltip)
	end
end
function DT:CompareTip(owner)
	compared = owner
	Compare()
end
DT:On("MODIFIER_STATE_CHANGED", function(key)
	if key == "LSHIFT" or key == "RSHIFT" then Compare() end
end)

-- the game's own link of an item (as the game writes it once it knows the item; else a plain one)
function DT:GameItemLink(id, name)
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, _, link = pcall(function() return get(id) end)
	return ok and link or ("|cffffffff|Hitem:%d::::::::::::|h[%s]|h|r"):format(id, name or ("item " .. id))
end

-- where to read up on an item
-- ponytail: Wowhead's Classic pages. Forever has items and sources of its own that are not there.
function DT:ItemLink(id)
	return "https://www.wowhead.com/forever/item=" .. id
end

function DT:OpenTab(id)
	self.UI:Show(id)
end

function DawnTools_OnAddonCompartmentClick()
	DT.UI:Toggle()
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

DT:On("ADDON_LOADED", function(name)
	if name == ADDON then Init() end
end)

-- Minimap button: our own. It was drawn through whichever LibDBIcon another addon had loaded, and that library
-- lays a button out differently from version to version, so the round sun sat off-centre for whoever had
-- another copy than mine. Now it is the same button for everybody.
-- ponytail: a round minimap is assumed; on a square one the button rides the circle. Corners if someone has one.
local mini
local function MiniClick(_, button)
	if button == "RightButton" then DT.UI:Show("settings") else DT.UI:Toggle() end
end
local function MiniTip(tip)
	tip:AddLine("DawnTools")
	tip:AddLine("Click: window. Right-click: settings.", 1, 1, 1)
end
local function PlaceMini()
	local angle = math.rad(tonumber(DT.db.minimap.minimapPos) or 225)
	local r = (Minimap:GetWidth() or 140) / 2 + 5
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end
local function MakeMini()
	if mini or not Minimap then return end
	mini = CreateFrame("Button", "DawnToolsMinimapButton", Minimap)
	mini:SetSize(31, 31)
	mini:SetFrameStrata("MEDIUM")
	mini:SetFrameLevel(8)
	mini:RegisterForClicks("AnyUp")
	mini:RegisterForDrag("LeftButton")
	mini:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
	-- The ring and the dark disc in it, as the game's own minimap buttons have them. Two sets of numbers: the
	-- game with the addon compartment draws the ring a little smaller. (Measured on a screenshot there: the
	-- ring's middle is one up and half right of the disc's; the hole is 22 across, the sun 20.)
	local modern = AddonCompartmentFrame ~= nil
	local ring = mini:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
	ring:SetSize(modern and 50 or 53, modern and 50 or 53)
	ring:SetPoint("TOPLEFT", 0, 0)
	local disc = mini:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
	if modern then
		disc:SetSize(24, 24)
		disc:SetPoint("CENTER", 0, 0)
	else
		disc:SetSize(20, 20)
		disc:SetPoint("TOPLEFT", 7, -5)
	end
	local sun = mini:CreateTexture(nil, "ARTWORK")
	sun:SetTexture(DT.LOGO)
	sun:SetSize(20, 20)
	sun:SetPoint("CENTER", disc, "CENTER", 0.5, 1)
	mini.icon = sun
	mini:SetScript("OnClick", MiniClick)
	mini:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		MiniTip(GameTooltip)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- dragged: it follows the mouse round the minimap
	mini:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale() or 1
			if not (mx and my and px and py) then return end
			DT.db.minimap.minimapPos = math.deg((math.atan2 or math.atan)(py / scale - my, px / scale - mx)) % 360
			PlaceMini()
		end)
	end)
	mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	DT.minimapButton = mini
end

function DT:ShowMinimap(on)
	self.db.minimap.hide = not on
	MakeMini()
	if not mini then return end
	PlaceMini()
	mini:SetShown(on and true or false)
end

DT:On("PLAYER_LOGIN", function()
	DT.me = UnitName("player")

	for _, mod in DT:Enabled() do
		-- a module that fails must not take the others with it; the error still reaches BugSack
		local ok, err = pcall(mod.onEnable or function() end, mod)
		if not ok then geterrorhandler()(err) end
	end

	C_Timer.After(5, function()
		if DT.db.settings.background then reader:Show() end
	end)

	SlashCmdList.DAWNTOOLS = Slash
	SLASH_DAWNTOOLS1 = "/dawntools"
	if SlashFree("/dt") then SLASH_DAWNTOOLS2 = "/dt" end
	for _, mod in DT:Enabled() do
		if mod.slash and mod.tab and SlashFree(mod.slash) then
			local key = "DAWNTOOLS_" .. mod.name:upper()
			SlashCmdList[key] = function() DT.UI:Show(mod.tab.id) end
			_G["SLASH_" .. key .. "1"] = mod.slash
		end
	end

	DT:ShowMinimap(not DT.db.minimap.hide)
	-- (for broker bars, where that library is there: the same clicks)
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if ldb then
		pcall(ldb.NewDataObject, ldb, "DawnTools", { type = "launcher", icon = DT.LOGO, OnClick = MiniClick, OnTooltipShow = MiniTip })
	end
end)

-- Guild messages start in a handler of their own. They used to start at the end of the one above, after the
-- minimap button: whatever failed there (another player's copy of a library, say) left this client deaf and
-- mute to the guild, without a word.
DT:On("PLAYER_LOGIN", function() DT.Comms:Start() end)
