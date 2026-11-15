-- DawnTools self-check: the price maths, then whole addons (one per fake guild member) talking over a fake
-- guild channel. Run with:  cd tests && npm install && npm test   (needs Lua 5.2+ for loadfile's env; fengari is 5.3)

local DIR = ADDON_DIR or ""
local checks = 0
local function check(cond, what)
	checks = checks + 1
	if not cond then error("FAILED: " .. what, 2) end
end
local function eq(got, want, what)
	check(got == want, ("%s: got %s, want %s"):format(what, tostring(got), tostring(want)))
end

---------------------------------------------------------------------------
-- 1. Logic
---------------------------------------------------------------------------

local L = assert(loadfile(DIR .. "Core/Logic.lua"))()
local BASE = 1700000000 -- 80000 seconds into its day
local DAY = L.DAY

do
	local now, items = BASE, {}
	local function ob(id, p, q, t, o) return { id = id, p = p, q = q, t = t, o = o } end

	check(L.Observe(items, ob(1, 100, 5, now - 10, "A"), now), "an observation is taken")
	eq(items[1].p, 100, "latest price"); eq(items[1].q, 5, "latest quantity"); eq(items[1].o, "A", "latest observer")
	local ok, why = L.Observe(items, ob(1, 100, 5, now - 10, "B"), now)
	eq(ok, false, "the same observation twice"); eq(why, "dup", "is a duplicate")
	check(L.Observe(items, ob(1, 90, 9, now - 100, "C"), now), "an older observation is taken")
	eq(items[1].p, 100, "but the newest stays the latest"); eq(items[1].o, "A", "with its observer")
	eq(select(2, L.Observe(items, ob(1, 100, 1, now + 301, "A"), now)), "future", "from the future")
	check(L.Observe(items, ob(1, 110, 1, now + 50, "A"), now), "a clock a little ahead is fine")
	eq(select(2, L.Observe(items, ob(1, 100, 1, now - 14 * DAY - 1, "A"), now)), "old", "older than the history")
	eq(select(2, L.Observe(items, ob(1, 0, 1, now, "A"), now)), "bad", "no price")
	eq(select(2, L.Observe(items, ob(0, 5, 1, now, "A"), now)), "bad", "no item")
	eq(L.Observe({}, { id = 1, t = now }, now), false, "no price field")

	local med, n = L.Median(items[1], 7, now)
	eq(med, 100, "median of 90, 100, 110"); eq(n, 3, "over three observations")
	eq(L.Median({ d = {} }, 7, now), nil, "no median without data")

	-- outliers: kept, flagged, not believed; my own eyes are believed
	ok, why = L.Observe(items, ob(1, 600, 1, now + 100, "M"), now)
	eq(ok, true, "an outlier is kept"); eq(why, "outlier", "and flagged"); eq(items[1].p, 110, "but is not the latest")
	eq(select(2, L.Observe(items, ob(1, 19, 1, now + 101, "M"), now)), "outlier", "far too cheap is one too")
	eq(select(2, L.Observe(items, ob(1, 600, 1, now + 100, "M"), now)), "dup", "an outlier is not taken twice")
	eq(select(2, L.Median(items[1], 7, now)), 3, "outliers stay out of the median")
	ok, why = L.Observe(items, ob(1, 500, 1, now + 102, "M"), now)
	eq(why, nil, "five times the median is still believed")
	ok, why = L.Observe(items, ob(1, 3000, 2, now + 103, "me"), now, true)
	eq(why, nil, "what I saw myself is believed"); eq(items[1].p, 3000, "and is the latest")

	check(L.Observe(items, ob(1, 2900, 4, now + 103, "me"), now, true), "my second look in the same second")
	eq(items[1].p, 2900, "replaces the first"); eq(select(2, L.Median(items[1], 7, now)), 5, "without counting twice")

	-- history and trend
	local items2 = {}
	for i, p in ipairs({ 100, 120, 110 }) do L.Observe(items2, ob(2, p, i, now - 2 * DAY + i, "A"), now) end
	L.Observe(items2, ob(2, 200, 7, now - 5, "A"), now)
	local h = L.History(items2[2])
	eq(#h, 2, "two days of history"); eq(h[1].min, 100, "day min"); eq(h[1].median, 110, "day median")
	eq(h[1].n, 3, "day count"); eq(h[1].q, 3, "most listed that day"); eq(h[2].median, 200, "today")
	check(h[1].day < h[2].day, "oldest first")
	eq(L.Median(items2[2], 7, now), 115, "an even count takes the middle of the middle two")
	check(math.abs(L.Trend(items2[2], now) - (200 / 115 - 1)) < 1e-9, "trend against the 7-day median")
	eq(L.Median(items2[2], 1, now), 200, "median over one day")

	-- the cap per day
	local items3 = {}
	for i = 1, 20 do L.Observe(items3, ob(3, 100 + i, 1, now - 100 + i, "A"), now, true) end
	eq(L.History(items3[3])[1].n, L.MAX_PER_DAY, "a day keeps so many"); eq(items3[3].p, 120, "the latest still moves")

	-- a local fill-in: one price for its day, never passed on
	local items4 = {}
	check(L.Observe(items4, { id = 4, p = 77, q = 0, t = now - 50, o = "Auctionator", loc = true }, now, true), "a fill-in is taken")
	eq(items4[4].p, 77, "as the latest"); eq(L.History(items4[4])[1].min, 77, "and as that day's price")
	L.Observe(items4, { id = 4, p = 70, q = 0, t = now - 45, o = "Auctionator", loc = true }, now, true)
	eq(L.History(items4[4])[1].n, 1, "one a day, however often it is read"); eq(L.Median(items4[4], 7, now), 70, "counted in the median")
	eq(#L.Since(items4, 0, 100), 0, "so it is never passed on")
	L.Observe(items4, ob(4, 80, 3, now - 40, "A"), now)
	eq(items4[4].p, 80, "a real observation replaces it")

	-- since
	local since = L.Since(items, now - 50, 100)
	eq(since[1].t, now + 103, "newest first"); eq(since[2].o, "", "observer only known for the latest")
	for _, s in ipairs(since) do check(s.p ~= 600 and s.p ~= 19, "outliers are not passed on") end
	local found
	for _, s in ipairs(since) do if s.t == now + 103 then found = s end end
	eq(found and found.o, "me", "the latest carries its observer"); eq(found and found.q, 4, "and its quantity")
	eq(#L.Since(items, now - 50, 2), 2, "capped")
	eq(#L.Since(items, now + 1000, 100), 0, "nothing newer")

	-- wire format
	local text = L.Encode({ ob(1, 100, 5, now, "Al,i;ce"), ob(22, 3, 0, now + 1, "") })
	eq(text, ("1,100,5,%d,Alice;22,3,0,%d,"):format(now, now + 1), "encoded")
	local back = L.Decode(text .. ";garbage;1,2,3;9,9,9,9,x,y;-1,5,5,5,z")
	eq(#back, 2, "garbage is skipped"); eq(back[1].o, "Alice", "observer"); eq(back[2].id, 22, "second id"); eq(back[2].o, "", "no observer")
	eq(back[1].t, now, "time survives")
	eq(L.Encode({ ob(1, 1, 1, 1, "a"), ob(2, 2, 2, 2, "b"), ob(3, 3, 3, 3, "c") }, 2, 2), "2,2,2,2,b", "a slice")
	local many = {}
	for i = 1, L.MAX_DECODE + 50 do many[i] = ob(i, 1, 1, now, "") end
	eq(#L.Decode(L.Encode(many)), L.MAX_DECODE, "a message is read up to a limit")

	-- prune
	local items5 = {}
	L.Observe(items5, ob(5, 10, 1, now - 13 * DAY, "A"), now)
	L.Observe(items5, ob(6, 10, 1, now - 3 * DAY, "A"), now)
	L.Observe(items5, ob(6, 12, 1, now - 100, "A"), now)
	L.Observe(items5, ob(7, 10, 1, now - 50, "A"), now)
	eq(L.Prune(items5, now + 2 * DAY), 2, "an item not seen for 14 days goes"); eq(items5[5], nil, "gone")
	eq(L.Prune(items5, now + 12 * DAY), 2, "items stay while seen in time"); eq(#L.History(items5[6]), 1, "their old days go")
	local keep = L.MAX_ITEMS
	L.MAX_ITEMS = 1
	eq(L.Prune(items5, now), 1, "over the cap"); check(items5[7] and not items5[6], "the longest unseen goes first")
	L.MAX_ITEMS = keep

	eq(L.Money(12345), "1g 23s 45c", "money"); eq(L.Money(240), "2s 40c", "silver"); eq(L.Money(7), "7c", "copper")
	eq(L.Ago(30), "just now", "seconds"); eq(L.Ago(12 * 60), "12m ago", "minutes"); eq(L.Ago(3 * 3600 + 5), "3h ago", "hours")
	eq(L.Ago(2 * DAY + 5), "2d ago", "days")
	check(L.Newer("0.2.0", "0.1.9") and L.Newer("1.10", "1.9") and not L.Newer("0.1.0", "0.1.0") and not L.Newer("0.1", "0.2"), "versions")
end

---------------------------------------------------------------------------
-- 2. A fake game, one per guild member, on one clock and one guild channel
---------------------------------------------------------------------------

local now, timers, clients, sent = 0, {}, {}, {}
-- A stand-in for LibDeflate: the real one compresses correctly under fengari but does not inflate (not even a
-- stored block), so it cannot run here. It is checked in the game instead, by /dt selftest ("message packing").
local LibDeflate = {
	CompressDeflate = function(_, text) return "Z" .. text end,
	DecompressDeflate = function(_, text) return text:sub(1, 1) == "Z" and text:sub(2) or nil end,
	EncodeForWoWAddonChannel = function(_, text) return text end,
	DecodeForWoWAddonChannel = function(_, text) return text end,
	-- (for print: as hex here; the real one has its own alphabet)
	EncodeForPrint = function(_, text) return (text:gsub(".", function(ch) return ("%02x"):format(ch:byte()) end)) end,
	DecodeForPrint = function(_, text)
		if #text % 2 ~= 0 or text:find("[^0-9a-f]") then return nil end
		return (text:gsub("..", function(h) return string.char(tonumber(h, 16)) end))
	end,
}
local FILES = { "Core/Logic.lua", "Core/Core.lua", "Core/Comms.lua", "Core/UI.lua", "Core/Profiles.lua", "Market/Capture.lua", "Market/Sync.lua", "Market/UI.lua", "Data/QuestRewards.lua", "Modules/Inventory.lua", "Modules/Fish.lua", "Modules/Food.lua", "Modules/Npc.lua", "Modules/Quest.lua", "Modules/Item.lua", "Modules/Zone.lua", "Modules/Combat.lua", "Tools/Tools.lua", "Tools/Range.lua", "Tools/Mp5.lua", "Tools/Tracker.lua", "Tools/Silencer.lua", "Tools/Enemies.lua", "Core/Changelog.lua", "Core/Home.lua" }

local function after(delay, fn, owner) timers[#timers + 1] = { at = now + delay, fn = fn, owner = owner } end
local function Now() return BASE + math.floor(now) end

local function step(seconds)
	for _ = 1, math.floor(seconds / 0.05 + 0.5) do
		now = now + 0.05
		local due = {}
		for i = #timers, 1, -1 do
			if timers[i].at <= now then due[#due + 1] = table.remove(timers, i) end
		end
		table.sort(due, function(a, b) return a.at < b.at end)
		for _, t in ipairs(due) do
			local gone = t.owner and t.owner.gone -- a member who logged out: their timers died with their client
			if not gone then t.fn() end
			if t.every and not t.cancelled and not gone then
				t.at = now + t.every
				timers[#timers + 1] = t
			end
		end
		for _, c in ipairs(clients) do
			for _, w in ipairs(c.updaters) do
				if w.shown and w.scripts.OnUpdate then w.scripts.OnUpdate(w, 0.05) end
			end
		end
	end
end

-- items: name, quality, stack, vendor sell price, commodity, class, subclass
local ITEMS = {
	[100] = { "Copper Bar", 1, 20, 10, true, 7, 7 },
	[110] = { "Copper Ore", 1, 20, 5, true, 7, 7 },
	[300] = { "Linen Cloth", 1, 20, 30, true, 7, 5 },
	[400] = { "Sword", 2, 1, 1000, false, 2, lvl = 20, ilvl = 25 },
	[500] = { "Bid Only Axe", 2, 1, 1000, false, 2 },
	[600] = { "Grey Fang", 0, 20, 100, true, 15 },
	[820] = { "Minor Potion", 1, 5, 10, true, 0 },
	[821] = { "Herb", 1, 20, 2, true, 7, 9 },
	[830] = { "Coarse Thread", 1, 20, 2, true, 7, 5 },
}

-- Widgets only have the methods the real ones have for their type: a call to anything else is the same
-- "attempt to call a nil value" the game would raise.
local function Methods(base, names)
	local set = {}
	for name in pairs(base or {}) do set[name] = true end
	for name in names:gmatch("%S+") do set[name] = true end
	return set
end
local REGION = Methods(nil, "SetPoint ClearAllPoints SetAllPoints GetPoint GetLeft GetTop GetRight GetCenter SetSize SetWidth SetHeight GetWidth GetHeight Show Hide IsShown SetShown GetParent")
local FRAME = Methods(REGION, [[SetScript GetScript HookScript HasScript RegisterEvent UnregisterEvent UnregisterAllEvents
	CreateFontString CreateTexture SetAttribute GetAttribute SetBackdrop SetBackdropColor SetBackdropBorderColor SetFrameStrata SetFrameLevel GetEffectiveScale SetClampedToScreen
	SetMovable EnableMouse EnableMouseWheel RegisterForDrag StartMoving StopMovingOrSizing SetResizable SetResizeBounds
	StartSizing]])
local BUTTON = Methods(FRAME, [[SetText GetText RegisterForClicks SetEnabled Enable Disable LockHighlight UnlockHighlight SetNormalTexture
	SetHighlightTexture SetPushedTexture]])
local METHODS = {
	Frame = FRAME, Button = BUTTON,
	CheckButton = Methods(BUTTON, "SetChecked GetChecked"),
	EditBox = Methods(FRAME, "SetText GetText SetAutoFocus SetNumeric SetFocus ClearFocus HasFocus"),
	FontString = Methods(REGION, "SetText GetText SetJustifyH SetWordWrap SetTextColor SetSpacing SetFont SetShadowColor SetShadowOffset GetStringWidth"),
	Texture = Methods(REGION, "SetColorTexture SetTexture SetTexCoord SetAtlas"),
	GameTooltip = Methods(FRAME, "SetOwner AddLine AddDoubleLine GetItem SetHyperlink"),
	Slider = Methods(FRAME, "SetOrientation SetMinMaxValues SetValue GetValue SetValueStep SetObeyStepOnDrag SetThumbTexture"),
}

local function NewClient(name, opts)
	opts = opts or {}
	local c = {
		name = name, wire = name .. "-Forever", widgets = {}, updaters = {}, listeners = {}, printed = {}, popups = {}, queries = {},
		guild = true, combat = false, instance = false, searched = {}, browse = {}, replicate = {}, bags = {},
		browseQueries = {}, more = 0, pages = {}, bank = {},
		npc = "Creature-0-1-2-3-8719-00001A", npcFaction = "Horde", -- the auctioneer talked to: a Horde one
		uncached = { [400] = true }, -- the first GetItemInfo of these returns nothing, as for an item never seen
	}
	local env = setmetatable({}, { __index = _G })
	env._G = env
	c.env = env

	local Widget
	local BEHAVIOUR = {
		SetScript = function(self, script, fn)
			if script == "OnUpdate" and not self.updater then
				self.updater = true
				c.updaters[#c.updaters + 1] = self
			end
			self.scripts[script] = fn
		end,
		GetScript = function(self, script) return self.scripts[script] end,
		HookScript = function(self, script, fn)
			if script == "OnUpdate" and not self.updater then
				self.updater = true
				c.updaters[#c.updaters + 1] = self
			end
			local old = self.scripts[script]
			self.scripts[script] = old and function(...) old(...) fn(...) end or fn
		end,
		-- a panel is as big as the window's body, unless a test says otherwise
		GetWidth = function(self) return self.w or 764 end,
		GetHeight = function(self) return self.h or 426 end,
		HasScript = function() return false end,
		CreateFontString = function() return Widget("FontString") end,
		CreateTexture = function() return Widget("Texture") end,
		Show = function(self) self.shown = true end,
		Hide = function(self) self.shown = false end,
		SetShown = function(self, v) self.shown = v and true or false end,
		IsShown = function(self) return self.shown end,
		RegisterEvent = function(self, e) c.listeners[e] = c.listeners[e] or self end,
		SetText = function(self, v)
			self.text = v
			if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
		end,
		GetText = function(self) return self.text end,
		SetEnabled = function(self, v) self.enabled = v and true or false end,
		SetChecked = function(self, v) self.checked = v and true or false end,
		GetChecked = function(self) return self.checked end,
		SetMinMaxValues = function(self, min, max) self.min, self.max = min, max end,
		GetValue = function(self) return self.value end,
		SetValue = function(self, v) -- as the game does: kept within its range, and the script hears of a change
			v = math.max(self.min or v, math.min(self.max or v, v))
			if v == self.value then return end
			self.value = v
			if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
		end,
		HasFocus = function(self) return self.focus or false end,
		GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
		SetAttribute = function(self, key, value)
			self.attr = self.attr or {}
			self.attr[key] = value
		end,
		GetAttribute = function(self, key) return self.attr and self.attr[key] end,
		GetStringWidth = function(self) return #((self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 end,
		GetLeft = function(self) return self.left end,
		GetRight = function(self) return self.right end,
		GetCenter = function(self) if self.left then return (self.left + self.right) / 2, self.mid end end,
		AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
		SetHyperlink = function(self, link) self.lines[#self.lines + 1] = link end,
		AddDoubleLine = function(self, left, right) self.lines[#self.lines + 1] = left .. " " .. right end,
	}
	function Widget(kind)
		local methods = assert(METHODS[kind or "Frame"], "unknown widget type " .. tostring(kind))
		local w = { scripts = {}, shown = true, kind = kind or "Frame", lines = {} }
		c.widgets[#c.widgets + 1] = w
		return setmetatable(w, { __index = function(_, k)
			if not methods[k] then return nil end
			return BEHAVIOUR[k] or function() end
		end })
	end

	function c.fire(event, ...)
		local f = c.listeners[event]
		if f then f.scripts.OnEvent(f, event, ...) end
	end

	env.GetTime = function() return now end
	env.time, env.GetServerTime, env.date = Now, Now, os.date
	env.geterrorhandler = function() return function(err) error(err, 0) end end
	env.hooksecurefunc = function(tbl, fname, hook)
		if type(tbl) ~= "table" then tbl, fname, hook = env, tbl, fname end
		local orig = tbl[fname]
		tbl[fname] = function(...) orig(...) hook(...) end
	end
	env.print = function(...) c.printed[#c.printed + 1] = table.concat({ ... }, " ") end
	env.CreateFrame = function(kind) return Widget(kind) end
	env.SecureHandlerWrapScript = function(_, _, _, body) c.wrapBody = body end
	env.UIParent, env.UISpecialFrames = Widget(), {}
	env.GameTooltip, env.ItemRefTooltip = Widget("GameTooltip"), Widget("GameTooltip")
	env.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) c.tooltipHook = fn end }
	env.Enum = { TooltipDataType = { Item = 0 }, AuctionHouseSortOrder = { Price = 0 },
		AuctionHouseFilter = setmetatable({}, { __index = function(_, k) return k end }) }
	-- the auction house answers a list query, or a request for more, with its next page
	c.page = function()
		local rows = table.remove(c.pages, 1)
		local first = #c.browse == 0
		for _, row in ipairs(rows) do c.browse[#c.browse + 1] = row end
		if first then c.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") else c.fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", rows) end
	end
	env.ITEM_QUALITY_COLORS = { [0] = { hex = "|cff9d9d9d" }, [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" } }
	env.SlashCmdList = {}
	env.GetItemClassInfo = function(class) return ({ [0] = "Consumables", [2] = "Weapons", [4] = "Armor", [7] = "Trade Goods", [15] = "Miscellaneous" })[class] end
	env.GetItemSubClassInfo = function(_, sub) return "Sub " .. sub end
	env.StaticPopupDialogs = {}
	env.StaticPopup_Show = function(which) c.popups[#c.popups + 1] = which end
	env.ChatEdit_InsertLink = function() end
	env.UnitName = function(unit)
		if unit == "npc" then return c.npcName end
		return name
	end
	env.UnitGUID = function(unit) return unit == "npc" and c.npc or ("Player-" .. name) end
	env.UnitFactionGroup = function(unit)
		if unit == "npc" then return c.npcFaction end
		return "Horde"
	end
	env.UnitFullName = function() return name, "Smith" end -- on Forever: first name, surname
	env.UnitLevel = function() return 10 end
	-- the combat log: a test puts an event in c.log and fires COMBAT_LOG_EVENT_UNFILTERED
	env.CombatLogGetCurrentEventInfo = function() return table.unpack(c.log or {}, 1, 21) end
	env.UnitClass = function() return "Warrior", "WARRIOR" end
	env.GetGuildInfo = function() return "Running Dawn" end
	env.IsInGuild = function() return c.guild end
	env.InCombatLockdown = function() return c.combat end
	env.IsInInstance = function() return c.instance, c.instance and "party" or "none" end
	env.Ambiguate = function(full) return (full:match("^[^-]+")) end
	env.C_Timer = {
		After = function(delay, fn) after(delay, fn, c) end,
		NewTicker = function(every, fn)
			local t = { at = now + every, fn = fn, every = every, owner = c }
			t.Cancel = function(self) self.cancelled = true end
			timers[#timers + 1] = t
			return t
		end,
	}
	env.C_Item = {
		GetItemInfo = function(id)
			local i = ITEMS[id]
			if not i or c.uncached[id] then return nil end
			return i[1], "[" .. i[1] .. "]", i[2], i.ilvl or 1, i.lvl or 1, "", "", i[3], i.slot or "", 1000 + id, i[4], i[6], i[7] or 0
		end,
		RequestLoadItemDataByID = function(id)
			after(0.2, function()
				if c.gone then return end
				c.uncached[id] = nil
				c.fire("GET_ITEM_INFO_RECEIVED", id, ITEMS[id] ~= nil)
			end)
		end,
	}
	env.C_AuctionHouse = {
		GetNumCommoditySearchResults = function(id) return #(c.searched[id] or {}) end,
		GetCommoditySearchResultInfo = function(id, i)
			local l = c.searched[id][i]
			return { unitPrice = l[1], quantity = l[2] }
		end,
		GetNumItemSearchResults = function(key) return #(c.searched[key.itemID] or {}) end,
		GetItemSearchResultInfo = function(key, i)
			local l = c.searched[key.itemID][i]
			return { buyoutAmount = l[1], quantity = l[2] }
		end,
		GetBrowseResults = function() return c.browse end,
		SendBrowseQuery = function(query) c.browseQueries[#c.browseQueries + 1] = query end,
		RequestMoreBrowseResults = function() c.more = c.more + 1 end,
		HasFullBrowseResults = function() return #c.pages == 0 end,
		IsThrottledMessageSystemReady = function() return true end,
		GetItemKeyInfo = function(key) return { isCommodity = ITEMS[key.itemID][5] } end,
		GetNumReplicateItems = function() return #c.replicate end,
		ReplicateItems = function() c.replicated = (c.replicated or 0) + 1 end,
		GetReplicateItemInfo = function(i)
			local r = c.replicate[i + 1] -- the game counts these from 0
			return "", 0, r[2], 1, true, 1, "", 0, 0, r[3], 0, nil, nil, "", "", 0, r[1], true
		end,
		MakeItemKey = function(id) return { itemID = id } end,
		SendSearchQuery = function(key) c.queries[#c.queries + 1] = key.itemID end,
	}
	env.C_Container = {
		-- a slot is an item ID, or { item ID, stack size }; the bank (-1) only answers while it is open
		GetContainerNumSlots = function(bag) return bag == 0 and #c.bags or (bag == -1 and c.bankOpen) and #c.bank or 0 end,
		GetContainerItemInfo = function(bag, slot)
			local v = (bag == -1 and c.bank or c.bags)[slot]
			if type(v) == "table" then
				return { itemID = v[1], stackCount = v[2], hyperlink = "|Hitem:" .. v[1] .. "|h[" .. ITEMS[v[1]][1] .. "]|h" }
			end
			return v and { itemID = v } or nil
		end,
	}
	if opts.auctionator then
		env.Auctionator = { Constants = { SCAN_DAY_0 = opts.day0 }, Database = { db = opts.auctionator }, API = { v1 = {
			RegisterForDBUpdate = function(_, fn) c.auctionatorUpdate = fn end,
		} } }
	end

	-- the guild channel: everyone in the guild hears a message, its sender too
	local AceComm = { Embed = function(_, target)
		target.RegisterComm = function(t, _, method)
			c.hear = function(...) t[method](t, ...) end
		end
		target.SendCommMessage = function(_, prefix, text, distribution, _, prio, told)
			assert(#prefix <= 16 and not text:find("%z"), "a message the game would refuse")
			assert(not c.combat and not (c.instance and not c.DT.db.settings.instances), "sent where addon messages are restricted")
			sent[#sent + 1] = { from = name, text = text, prio = prio }
			if told then told(nil, #text, #text, c.refuse or 0) end -- (the game's answer: 0 is "taken")
			after(0.1, function()
				for _, other in ipairs(clients) do
					if other.guild and other.hear then other.hear(prefix, text, distribution, c.wire) end
				end
			end)
		end
	end }
	local icon = { Register = function() end, Show = function() c.minimap = true end, Hide = function() c.minimap = false end }
	local libs = { ["AceComm-3.0"] = AceComm, LibDeflate = LibDeflate, ["LibDBIcon-1.0"] = icon,
		["LibDataBroker-1.1"] = { NewDataObject = function(_, _, obj) c.launcher = obj return obj end },
		-- how far a unit is: c.ranges[unit] = { nearest, furthest } (as the range library answers)
		["LibRangeCheck-3.0"] = { GetHarmCheckers = function()
			local list, i = { 30, 5, 28, 30 }, 0
			return function() i = i + 1 return list[i] end
		end, GetRange = function(_, unit)
			c.rangeAsked = (c.rangeAsked or 0) + 1
			local r = c.ranges and c.ranges[unit]
			if r then return r[1], r[2] end
		end } }
	env.LibStub = setmetatable({}, { __call = function(_, lib) return libs[lib] end })

	if opts.globals then opts.globals(env) end
	env.DawnToolsDB = opts.db
	local DT = {}
	c.DT = DT
	for _, file in ipairs(FILES) do
		assert(loadfile(DIR .. file, "t", env))("DawnTools", DT)
	end
	if opts.before then opts.before(DT) end
	clients[#clients + 1] = c
	c.fire("ADDON_LOADED", "DawnTools")
	c.fire("PLAYER_LOGIN")
	DT.db.settings.coins = false -- (prices as plain text here: the coin pictures have their own checks)
	c.M = DT.Market
	c.items = function() return DT.Market.items end
	c.slash = function(text) env.SlashCmdList.DAWNTOOLS(text) end
	return c
end

local function leave(c)
	c.fire("PLAYER_LOGOUT")
	c.hear, c.gone = nil, true
	for i, other in ipairs(clients) do
		if other == c then table.remove(clients, i) end
	end
end

-- messages on the channel of one kind (and from one member, if given)
local function count(kind, from)
	local n = 0
	for _, m in ipairs(sent) do
		if m.text:find("\t" .. kind .. "\t", 1, true) and (not from or m.from == from) then n = n + 1 end
	end
	return n
end

local function packed(kind, payload, proto)
	if (kind == "PUSH" or kind == "DATA") and not payload:find("^%a|") then payload = "H|" .. payload end -- (the Horde house, unless the test says)
	return table.concat({ "market", kind, proto or 1, "z", LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(payload)) }, "\t")
end

local function wire(id, p, q, t, o) return ("%d,%d,%d,%d,%s"):format(id, p, q, t, o or "") end

---------------------------------------------------------------------------
-- 3. One member, not sharing: capture, tooltip, API
---------------------------------------------------------------------------

local A = NewClient("Alice")
local updates = 0
A.env.DawnMarket.API.RegisterForUpdate(function() updates = updates + 1 end)
eq(A.popups[1], nil, "the question waits a moment")
step(6)
eq(A.popups[1], "DAWNTOOLS_MARKET_SHARE", "first launch asks about sharing")
eq(A.M.db.settings.share, nil, "and nothing is decided for the player")

A.searched[100] = { { 50, 10 }, { 100, 10 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(A.items()[100].p, 50, "commodity: lowest unit price"); eq(A.items()[100].q, 20, "commodity: everything listed")
eq(A.items()[100].o, "Alice", "seen by me"); eq(A.items()[100].t, Now(), "at server time")

A.searched[400] = { { 900, 1 }, { 300, 9 }, { 0, 1 } }
A.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 400 })
eq(A.items()[400].p, 300, "item: lowest buyout, which is for one however many are sold at it"); eq(A.items()[400].q, 10, "item: auctions without a buyout are left out")

A.browse = { { itemKey = { itemID = 300 }, minPrice = 5, totalQuantity = 50 }, { itemKey = { itemID = 500 }, minPrice = 100, totalQuantity = 1 }, { itemKey = { itemID = 500, itemSuffix = 7 }, minPrice = 140, totalQuantity = 2 },
	{ itemKey = { itemID = 110 }, minPrice = 0, totalQuantity = 0 } }
A.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
eq(A.items()[300].p, 5, "browse row of a commodity"); eq(A.items()[300].q, 50, "with its quantity")
eq(A.items()[500].p, 100, "gear is taken from the list too: the cheapest of its rows"); eq(A.items()[110], nil, "an empty row is nothing")
A.items()[500] = nil -- (what follows was written without it)
A.fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { { itemKey = { itemID = 110 }, minPrice = 8, totalQuantity = 40 } })
eq(A.items()[110].p, 8, "rows added to a browse")

A.replicate = { { 600, 5, 100 }, { 600, 1, 15 }, { 600, 1, 0 }, { 821, 20, 400 } }
A.M.ahOpen = true -- (a full scan only comes at the auction house)
A.fire("REPLICATE_ITEM_LIST_UPDATE")
step(0.2)
A.M.ahOpen = false
eq(A.items()[600].p, 15, "full scan: lowest unit buyout"); eq(A.items()[600].q, 6, "full scan: units with a buyout")
eq(A.items()[821].p, 20, "full scan: a stack's price per unit")

-- the same price again is not a new observation, a new price is, and so is the same price much later
local seen = A.M.db.stats.n
step(60)
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(A.M.db.stats.n, seen, "an unchanged price is not recorded again at once")
A.searched[100][1][1] = 45
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(A.M.db.stats.n, seen + 1, "a changed price is"); eq(A.items()[100].p, 45, "and is the latest")
step(901)
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(A.M.db.stats.n, seen + 2, "and the same price after a quarter of an hour"); eq(A.items()[100].t, Now(), "so its age is honest")

eq(A.items()[100].n, "Copper Bar", "item name kept for the search"); eq(A.items()[100].c, 7, "and its class")
eq(A.items()[400].n, "Sword", "an item the client had to load is named once it has")
check(updates > 0, "API listeners hear about new prices")

local API = A.env.DawnMarket.API
local p, q, t, o = API.GetLatest(100)
eq(p, 45, "API price"); eq(q, 20, "API quantity"); eq(t, Now(), "API time"); eq(o, "Alice", "API observer")
local each = 0
API.Each(function(id, price, _, at) if id == 100 then each = price == p and at == t and 1 or -1 end end)
eq(each, 1, "API: every latest price can be walked")
eq(API.GetLatest(999), nil, "API: unknown item"); eq(API.GetMedian(100), 45, "API median")
eq(API.GetMedian(999), nil, "API: no median"); eq(#API.GetHistory(100), 1, "API history"); eq(#API.GetHistory(999), 0, "API: no history")

A.tooltipHook(A.env.GameTooltip, { id = 100 })
local line = A.env.GameTooltip.lines[#A.env.GameTooltip.lines]
check(line:find("Guild AH 45c (just now)", 1, true) and line:find("7d median 45c", 1, true), "tooltip line: " .. tostring(line))
A.tooltipHook(A.env.GameTooltip, { id = 999 })
eq(#A.env.GameTooltip.lines, 1, "no line for an item without a price")
A.M.db.settings.tooltip = false
A.tooltipHook(A.env.GameTooltip, { id = 100 })
eq(#A.env.GameTooltip.lines, 1, "and none when switched off")
A.M.db.settings.tooltip = true
do -- Shift over a stack: the price of all of it
	local tip = A.env.GameTooltip
	local lines, owner = tip.lines, tip.GetOwner
	tip.lines, tip.GetOwner = {}, function() return { count = 20 } end
	A.env.IsShiftKeyDown = function() return true end
	A.tooltipHook(tip, { id = 100 })
	check(tostring(tip.lines[1]):find("Guild AH 9s 0c x20", 1, true), "Shift over a stack of 20: twenty times the price: " .. tostring(tip.lines[1]))
	A.env.IsShiftKeyDown = nil
	tip.lines = {}
	A.tooltipHook(tip, { id = 100 })
	check(tostring(tip.lines[1]):find("Guild AH 45c (", 1, true), "without Shift: the price of one")
	tip.lines, tip.GetOwner = lines, owner
end

-- not sharing: the core says hello, the market says nothing
step(700)
check(count("HELLO", "Alice") >= 2, "the core says hello now and then")
for _, m in ipairs(sent) do check(not m.text:find("market", 1, true), "nothing about the market is sent before a yes") end
eq(A.DT.Comms.self, "Alice-Forever", "my own hello tells me my name on the wire")
eq(next(A.DT.Comms.peers), nil, "and I am not my own peer")
eq(A.M.Sync.queued, 0, "nothing is even queued")

---------------------------------------------------------------------------
-- 4. Two members sharing: HELLO, REQUEST, DATA, PUSH
---------------------------------------------------------------------------

A.env.StaticPopupDialogs.DAWNTOOLS_MARKET_SHARE.OnAccept()
eq(A.M.db.settings.share, true, "Alice says yes")

local B = NewClient("Bob")
B.env.StaticPopupDialogs.DAWNTOOLS_MARKET_SHARE.OnAccept()
step(30)
check(A.DT.Comms.peers["Bob-Forever"], "Alice heard Bob"); check(B.DT.Comms.peers["Alice-Forever"], "Bob heard Alice, who answered a newcomer")
eq(B.DT.Comms.peers["Alice-Forever"].version, A.DT.VERSION, "with her version")
eq(count("REQUEST", "Bob"), 1, "Bob asks for what he missed"); eq(count("REQUEST", "Alice"), 0, "Alice has nothing to ask an empty Bob")
eq(count("DATA", "Alice"), 1, "Alice answers")
eq(B.items()[100] and B.items()[100].p, 45, "Bob has Alice's price"); eq(B.items()[100].o, "Alice", "and who saw it")
eq(B.items()[400].p, 300, "and the others"); eq(B.M.Sync.done, true, "Bob is in step")
step(2)
eq(B.items()[100].n, "Copper Bar", "names are looked up for merged items too")
for _, m in ipairs(sent) do
	if m.text:find("\tDATA\t", 1, true) then eq(m.prio, "BULK", "data goes out at low priority") end
end
eq(#L.History(A.items()[100]), 1, "Alice does not merge her own messages back")
local aliceCount = A.M.db.stats.n

-- a new price is pushed
A.searched[100][1][1] = 40
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(B.items()[100].p, 45, "not at once")
step(50)
eq(count("PUSH", "Alice"), 1, "one push"); eq(B.items()[100].p, 40, "Bob has the new price"); eq(B.items()[100].o, "Alice", "from Alice")
eq(A.M.db.stats.n, aliceCount + 1, "Alice counted it once")
step(100)
eq(count("PUSH", "Alice"), 1, "nothing new, nothing sent")

-- without my name
A.M.db.settings.name = false
A.searched[110] = { { 9, 30 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 110)
step(50)
eq(B.items()[110].p, 9, "pushed without a name"); eq(B.items()[110].o, "", "Bob does not know who")
eq(A.items()[110].o, "Alice", "Alice still does")
A.M.db.settings.name = true

-- combat and instances: wait, then send
A.combat = true
A.searched[300] = { { 6, 10 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 300)
step(50)
eq(B.items()[300].p, 5, "nothing is sent in combat"); eq(A.M.Sync.queued, 1, "it waits")
A.combat, A.instance = false, true
step(50)
eq(B.items()[300].p, 5, "nor in an instance")
A.DT.db.settings.instances = true
step(50)
eq(B.items()[300].p, 6, "unless that is allowed")
A.DT.db.settings.instances, A.instance = false, false

-- both see things; Bob relays nothing of Alice's as his own
B.searched[820] = { { 200, 30 } }
B.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 820)
step(50)
eq(A.items()[820].p, 200, "Alice has Bob's price"); eq(A.items()[820].o, "Bob", "seen by Bob")

---------------------------------------------------------------------------
-- 5. What is not believed
---------------------------------------------------------------------------

local function inject(c, sender, text, distribution) c.hear("DAWN", text, distribution or "GUILD", sender) end
local T = Now()

inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T + 1000, "=")))
eq(B.items()[7000], nil, "a price from the future is dropped")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T - 15 * DAY, "=")))
eq(B.items()[7000], nil, "and one older than the history")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T, "="), 0))
eq(B.items()[7000], nil, "and a message in a protocol older than supported")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T, "="), 99))
eq(B.items()[7000], nil, "and one in a protocol not yet known")
check(B.printed[#B.printed]:find("update", 1, true), "which says an update is due")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T, "=")), "WHISPER")
eq(B.items()[7000], nil, "and anything not on the guild channel")
inject(B, "Mallory-Forever", "market\tPUSH\t1\tz\tnot deflate at all")
inject(B, "Mallory-Forever", "nonsense")
inject(B, "Mallory-Forever", packed("NOPE", "x"))
inject(B, "Mallory-Forever", packed("PUSH", "x;y;;;1,2"))
inject(B, "Mallory-Forever", packed("REQUEST", "nobody"))
eq(B.items()[7000], nil, "garbage does no harm")
inject(B, "Mallory-Forever", packed("PUSH", wire(7000, 5, 1, T, "=")))
eq(B.items()[7000].p, 5, "a sound one is taken"); eq(B.items()[7000].o, "Mallory", "under the sender's name")

-- an outlier against a known price
for i = 1, 3 do inject(B, "Carol-Forever", packed("PUSH", wire(100, 40 + i, 10, B.items()[100].t - 10 * i, "="))) end
eq(B.items()[100].p, 40, "older observations do not move the latest")
inject(B, "Mallory-Forever", packed("PUSH", wire(100, 4000, 10, T + 5, "=")))
eq(B.items()[100].p, 40, "a hundred times the median is not believed"); eq(B.items()[100].o, "Alice", "the latest stands")
inject(B, "Mallory-Forever", packed("PUSH", wire(100, 60, 10, T + 6, "=")))
eq(B.items()[100].p, 60, "a plausible change is")

-- one sender flooding
for i = 1, 60 do inject(B, "Spammer-Forever", packed("PUSH", wire(8000 + i, 5, 1, T, "="))) end
local flood = 0
for id in pairs(B.items()) do if id > 8000 and id < 9000 then flood = flood + 1 end end
eq(flood, 40, "a sender is heard so many times a minute")

---------------------------------------------------------------------------
-- 6. Logging out and in; sharing switched off; Auctionator
---------------------------------------------------------------------------

leave(B)
local saved = B.env.DawnToolsDB
eq(saved.market.synced, T + 6, "logging out in step is remembered, up to the newest price held")
step(120)
local requests = count("REQUEST", "Bob")
-- Auctionator's table: per item, the last price (m) and per day the highest low (h), lowest low (l), most listed (a).
-- Its day 500 is today, and started 80000 seconds before BASE.
local DAY0 = BASE - 80000 - 500 * DAY
local auctionator = {
	["830"] = { m = 21, h = { ["500"] = 22, ["499"] = 30 }, l = { ["499"] = 20 }, a = { ["500"] = 7 } },
	["820"] = { m = 150, h = { ["499"] = 150 }, l = {} },
	["300"] = { m = 99, h = { ["460"] = 99 }, l = {} },
	["g:400:20"] = { m = 5, h = { ["500"] = 5 }, l = {} },
	["110"] = "not a table", ["600"] = { m = 1 },
}
local B2 = NewClient("Bob", { db = saved, auctionator = auctionator, day0 = DAY0 })
eq(B2.items()[100].p, 60, "prices are saved"); eq(B2.items()[100].n, "Copper Bar", "with their names")
eq(B2.popups[1], nil, "the question is not asked twice")
step(40)
eq(B2.popups[1], nil, "really not")
eq(count("REQUEST", "Bob"), requests, "nothing happened meanwhile: nothing for Bob to ask for")
eq(count("REQUEST", "Alice"), 1, "Alice, who never caught up with anyone, asks Bob")
eq(A.items()[7000] and A.items()[7000].p, 5, "and gets what Bob heard from others"); eq(A.M.Sync.done, true, "so she is in step too")
check(B2.DT.Comms.peers["Alice-Forever"], "though Alice is heard")

-- Auctionator's history: every item and day it has, for me only
local thread = B2.items()[830]
eq(thread.p, 21, "an item only Auctionator knows: its last price"); eq(thread.o, "Auctionator", "which says where it is from")
eq(thread.q, 7, "with the most it saw listed"); eq(thread.n, "Coarse Thread", "and a name to search by")
check(thread.t < Now() - 3600 and thread.t > Now() - DAY, "placed within its day, not at this minute")
local th = L.History(thread)
eq(#th, 2, "one price per day Auctionator scanned"); eq(th[1].min, 20, "an older day: the lowest it saw"); eq(th[2].min, 21, "today")
eq(B2.items()[820].p, 200, "a newer price of our own stays the latest"); eq(B2.items()[820].o, "Bob", "under its observer")
eq(#L.History(B2.items()[820]), 2, "while Auctionator's earlier day joins its history")
eq(B2.items()[300].p, 6, "days older than the history are left out"); eq(B2.items()[400].p, 300, "gear by item level is skipped")
eq(B2.items()[110].p, 9, "and what is not a price record does no harm"); eq(B2.items()[600].p, 15, "nor one without days")
eq(B2.M.Sync.queued, 0, "Auctionator's prices are not shared")
for _, o in ipairs(L.Since(B2.items(), 0, 99999)) do check(o.id ~= 830 and o.p ~= 150, "not when asked for everything either") end
eq(count("PUSH", "Bob"), 1, "Bob pushed only what he saw himself")
check(B2.auctionatorUpdate, "registered for Auctionator's updates")
auctionator["830"].m = 19
B2.auctionatorUpdate()
step(5)
eq(B2.items()[830].p, 19, "a scan by Auctionator is taken over"); eq(#L.History(B2.items()[830]), 2, "into the same days")
B2.M.db.settings.auctionator = false
auctionator["830"].m = 18
B2.auctionatorUpdate()
step(5)
eq(B2.items()[830].p, 19, "unless that is switched off")

-- Alice saw something while Bob was away
leave(B2)
A.searched[830] = { { 25, 60 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 830)
step(120)
local B3 = NewClient("Bob", { db = B2.env.DawnToolsDB })
step(40)
eq(count("REQUEST", "Bob"), requests + 1, "Bob asks for what he missed"); eq(B3.items()[830].p, 25, "and gets it")
eq(B3.items()[830].o, "Alice", "a real observation replaces the fill-in")
local answered = count("DATA", "Alice")
inject(A, "Bob-Forever", "market\tREQUEST\t1\t-\tAlice-Forever;0")
step(5)
eq(count("DATA", "Alice"), answered, "asking again within a minute gets no second answer")
inject(A, "Dave-Forever", "market\tREQUEST\t1\t-\tSomeone-Else;0")
step(5)
eq(count("DATA", "Alice"), answered, "a request for someone else is not mine to answer")

-- sharing off: deaf and mute
B3.M.db.settings.share = false
local pushes, answers = count("PUSH", "Bob"), count("DATA", "Bob")
B3.searched[600] = { { 12, 5 } }
B3.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 600)
eq(B3.items()[600].p, 12, "prices are still recorded for me")
A.searched[100] = { { 33, 10 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
step(700)
eq(count("PUSH", "Bob"), pushes, "nothing is sent with sharing off"); eq(B3.items()[100].p, 60, "and nothing is taken in")
inject(B3, "Alice-Forever", "market\tREQUEST\t1\t-\tBob-Forever;0")
step(5)
eq(count("DATA", "Bob"), answers, "nor are requests answered")
check(not sent[#sent].text:find("market=", 1, true) or sent[#sent].from ~= "Bob", "Bob's hello no longer mentions the market")
check(B3.M.Sync:Status():find("Not sharing", 1, true), "the status says so")
check(A.M.Sync:Status():find("guild members seen", 1, true), "Alice's status counts peers")

---------------------------------------------------------------------------
-- 7. The window, the tabs, the commands
---------------------------------------------------------------------------

local C = NewClient("Carol", {
	globals = function(env) env.SLASH_OTHERADDON1 = "/dt" end,
	before = function(DT)
		DT:RegisterModule("demo", { title = "Demo", tab = { id = "demo", title = "Demo", defaultOrder = 20, create = function() end } })
		DT:RegisterModule("early", { title = "Early", tab = { id = "early", title = "Early", defaultOrder = 5, create = function() end } })
	end,
})
local function ids(list)
	local out = {}
	for i, tab in ipairs(list) do out[i] = tab.id end
	return table.concat(out, " ")
end
local UI = C.DT.UI
eq(C.env.SLASH_DAWNTOOLS1, "/dawntools", "the long command"); eq(C.env.SLASH_DAWNTOOLS2, nil, "/dt is left to the addon that has it")
eq(A.env.SLASH_DAWNTOOLS2, "/dt", "and taken when free"); eq(A.env.SLASH_DAWNTOOLS_MARKET1, "/dtmarket", "the module's short command")
eq(ids(UI:TabList()), "home early market demo inventory craft world combat tools", "tabs in their default order")
UI:MoveTab("demo", -1)
eq(ids(UI:TabList()), "home early demo market inventory craft world combat tools", "a tab moved up")
UI:MoveTab("home", -1)
eq(ids(UI:TabList()), "home early demo market inventory craft world combat tools", "the first cannot go higher")
UI:MoveTab("early", 1)
UI:MoveTab("early", 1)
eq(ids(UI:TabList()), "home demo market early inventory craft world combat tools", "moved down twice")
C.DT.db.tabs.hidden.market = true
eq(ids(UI:TabList()), "home demo early inventory craft world combat tools", "a hidden tab is off the bar"); eq(ids(UI:TabList(true)), "home demo market early inventory craft world combat tools", "but still there")
C.searched[100] = { { 50, 10 } }
C.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(C.items()[100].p, 50, "and its module keeps working")
C.slash("")
eq(C.DT.db.lastTab, "home", "the window opens on the first tab shown: Home, for someone new")
do
	local Home = C.DT.Home
	local homeB
	for _, w in ipairs(C.widgets) do if w.kind == "Button" and w.id == "home" and w.x then homeB = w end end
	eq(homeB.isIcon, true, "Home's button shows a picture"); eq(homeB.text, "", "not its name"); eq(homeB.tip, "Home", "which is said on hover")
	eq(homeB.x, 120, "it is the first on the bar")
	check(Home.forWhom.text:find("Running Dawn", 1, true), "built for Running Dawn"); check(Home.byWhom.text:find("Forgehaven", 1, true), "built by Forgehaven")
	check(Home.title.text:find(C.DT.VERSION, 1, true), "with the version")
	local lines = Home.Changelog()
	check(lines[1]:find(C.DT.VERSION, 1, true), "the changelog begins with this version: " .. lines[1]); check(lines[2]:find("^  %- "), "its lines beneath")
	eq(Home.log.rows[1].text, lines[1], "and is drawn, newest first")
	local guide = {}
	for _, b in ipairs(Home.guide) do if b.shown then guide[#guide + 1] = b.tab end end
	eq(table.concat(guide, " "), "demo early inventory craft world combat tools settings", "where things are: the tabs on the bar, in order (hidden ones left out)")
	local craftLine
	for _, b in ipairs(Home.guide) do if b.tab == "craft" then craftLine = b end end
	check(craftLine.label.text:find("(Fish, Food)", 1, true), "a place names what is under it: " .. craftLine.label.text)
	craftLine.scripts.OnClick(craftLine)
	eq(C.DT.db.lastTab, "craft", "a click on a line opens that tab")
	C.slash("")
	C.slash("")
	eq(C.DT.db.lastTab, "craft", "closed and opened again: the tab last looked at, not Home")
	C.DT.db.tabs.hidden.home = true
	eq(ids(UI:TabList()):find("home"), nil, "Home can be hidden like any tab")
	C.DT.db.tabs.hidden.home = nil
end
C.slash("market")
eq(C.DT.db.lastTab, "market", "/dt market opens a hidden tab all the same")
C.env.SlashCmdList.DAWNTOOLS_MARKET()
C.slash("settings")
eq(C.DT.db.lastTab, "settings", "/dt settings")
C.slash("debug market")
check(C.DT.db.debug.market, "debug on")
C.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
C.searched[100][1][1] = 51
C.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
check(C.printed[#C.printed]:find("saw item 100", 1, true), "debug logs a capture")
C.slash("debug market")
C.slash("probe")
check(C.printed[#C.printed]:find("Carol", 1, true), "the probe names me")
C.slash("help")
check(C.printed[#C.printed]:find("/dt market", 1, true), "help lists the tabs")
C.launcher.OnClick(nil, "RightButton")
C.launcher.OnClick(nil, "LeftButton")
C.launcher.OnTooltipShow(C.env.GameTooltip)
C.env.DawnTools_OnAddonCompartmentClick()
C.DT:ShowMinimap(false)
check(C.DT.db.minimap.hide, "minimap button off")
-- prices with coin pictures, or as letters
C.DT.db.settings.coins = true
check(C.DT.Money(12345):find("^1|T.-GoldIcon.-|t 23|T.-SilverIcon.-|t 45|T.-CopperIcon.-|t$"), "a price with the game's coins: " .. C.DT.Money(12345))
check(C.DT.Money(45):find("^45|T.-CopperIcon.-|t$") and C.DT.Money(-205):find("^%-2|T"), "only the coins there are, and a minus where it is one")
C.DT.db.settings.coins = false
eq(C.DT.Money(12345), "1g 23s 45c", "switched off: letters")
-- what goes out and comes in is counted, for /dt sync
do
	local st = C.DT.Comms.stats
	local okBefore, blockedBefore = st.ok, st.blocked
	C.printed = {}
	C.env.SlashCmdList.DAWNTOOLS("sync")
	check(st.ok > okBefore or st.blocked > blockedBefore, "/dt sync says HELLO (or notes why it could not)")
	local said = table.concat(C.printed, "\n")
	check(said:find("Sent: %d+ pieces") and said:find("My HELLO:") and said:find("Heard: %d+ messages"), "and prints the counts: " .. said)
	local n = st.ok + st.blocked
	C.env.SlashCmdList.DAWNTOOLS("sync")
	eq(st.ok + st.blocked, n, "asked again within the minute: no second HELLO")
	local report = table.concat(C.DT.Comms:Report(), "\n")
	if C.DT.Market.Sync:On() then check(C.DT.Market.Sync:Status():find("Sent: %d+ pieces"), "the Market status carries the same lines") end
	-- a send the game refuses is counted as that, with its answer
	local refused = st.refused
	C.refuse = 7
	C.DT.Comms:Send("core", "TEST", "x")
	C.refuse = nil
	eq(st.refused, refused + 1, "a refused send is counted"); check(C.DT.Comms:Report()[1]:find("last answer: 7", 1, true), "with the game's answer")
end
-- the minimap button is our own: no library draws it
do
	C.env.Minimap = C.env.CreateFrame("Frame")
	C.DT:ShowMinimap(true)
	local b = C.DT.minimapButton
	check(b and b.shown, "the minimap button is there without any library")
	check(b.icon ~= nil, "with the sun on it")
	C.DT.UI:Show("market")
	b.scripts.OnClick(b, "RightButton")
	eq(C.DT.db.lastTab, "settings", "a right click opens the settings")
	C.DT:ShowMinimap(false)
	eq(b.shown, false, "hidden when switched off"); check(C.DT.db.minimap.hide, "which is remembered")
	eq(#C.DT.Comms:Report(), 3, "the report is three lines")
	eq(C.DT.Comms.stats.started, true, "and says the guild messages were started")
end

-- a module switched off is not there at all
leave(C)
local off = C.env.DawnToolsDB.modules
off.market, off.inventory, off.fish, off.food, off.combat, off.npc, off.quest, off.tools, off.range, off.mp5, off.tracker, off.home, off.item, off.zone = false, false, false, false, false, false, false, false, false, false, false, false, false, false
local D = NewClient("Carol", { db = C.env.DawnToolsDB })
eq(ids(D.DT.UI:TabList(true)), "", "no tab for a module switched off")
D.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(D.env.DawnMarket.API.GetLatest(100), nil, "its API knows nothing"); eq(#D.env.DawnMarket.API.GetHistory(100), 0, "and breaks nothing")
eq(D.env.SLASH_DAWNTOOLS_MARKET1, nil, "no command either")
D.slash("market")
D.slash("")
eq(D.DT.db.lastTab, "settings", "only Settings is left")
step(700)
eq(D.DT.UI:SelfTest(), 0, "selftest passes without modules")
leave(D)

-- the Market tab on Alice, who has prices
local V = A.M.View
UI = A.DT.UI
A.slash("market")
local function find(kind, text)
	for _, w in ipairs(A.widgets) do
		if w.kind == kind and w.text == text then return w end
	end
end
local function shown()
	local n = 0
	for _, w in ipairs(A.widgets) do
		if w.cells and w.shown then n = n + 1 end
	end
	return n
end
local function click(w, button) w.scripts.OnClick(w, button or "LeftButton") end
local total = 0
for _ in pairs(A.items()) do total = total + 1 end
eq(shown(), 19, "a screenful of rows"); check(find("FontString", total .. " items  |cff888888click one for its history|r"), "and a count of all " .. total)
local search
for _, w in ipairs(A.widgets) do if w.kind == "EditBox" and not search then search = w end end -- (the level boxes come after it)
search:SetText("copper")
step(0.5)
eq(shown(), 2, "search by part of a name")
search:SetText("")
local function section(label)
	for _, w in ipairs(A.widgets) do
		if w.entry and w.shown and w.entry.label == label then return w end
	end
end
local function sectionNames()
	local names = {}
	for _, w in ipairs(A.widgets) do
		if w.entry and w.shown then names[#names + 1] = w.entry.label end
	end
	return table.concat(names, ", ")
end
eq(sectionNames(), "All items, Favourites, Weapons, Consumables, Trade Goods, Miscellaneous", "the categories there are prices for, in auction house order")
click(section("Trade Goods"))
eq(shown(), 5, "trade goods only")
eq(sectionNames(), "All items, Favourites, Weapons, Consumables, Trade Goods, Sub 5, Sub 7, Sub 9, Miscellaneous", "its sub-categories open under it")
click(section("Sub 7"))
eq(shown(), 2, "a sub-category"); eq(section("Sub 7").text.text, "    Sub 7", "shown indented")
click(section("Sub 7"))
eq(shown(), 5, "clicked again: back to the whole category")
click(section("Weapons"))
eq(shown(), 1, "another category"); check(not section("Sub 7"), "closes the first; one sub-category is no list")
click(section("All items"))
eq(shown(), 19, "everything again")

-- more categories than fit: they scroll instead of running out of the window
click(section("Trade Goods"))
V.panel.h = 110
V.panel.scripts.OnSizeChanged(V.panel)
eq(sectionNames(), "All items, Favourites, Weapons, Consumables, Trade Goods", "only as many categories as fit")
local sidebar
for _, w in ipairs(A.widgets) do if w.bar then sidebar = w end end
eq(sidebar.bar.shown, true, "with a scroll bar")
sidebar.scripts.OnMouseWheel(sidebar, -1)
eq(sectionNames(), "Weapons, Consumables, Trade Goods, Sub 5, Sub 7", "the wheel scrolls them")
for _ = 1, 5 do sidebar.scripts.OnMouseWheel(sidebar, -1) end
eq(sectionNames(), "Trade Goods, Sub 5, Sub 7, Sub 9, Miscellaneous", "to the end and no further")
eq(sidebar.bar.value, 4, "the bar follows the wheel")
sidebar.bar:SetValue(1)
eq(sectionNames(), "Favourites, Weapons, Consumables, Trade Goods, Sub 5", "dragging the bar scrolls them")
sidebar.bar:SetValue(99)
eq(sectionNames(), "Trade Goods, Sub 5, Sub 7, Sub 9, Miscellaneous", "as far as its end")
click(section("Sub 9"))
eq(V.group, 9, "a scrolled category is the one clicked")
V.panel.h = nil
V.panel.scripts.OnSizeChanged(V.panel)
eq(sidebar.bar.shown, false, "no scroll bar when everything fits"); check(section("All items"), "and back at the top")
click(section("All items"))

-- the table has the whole height until an item is picked; then the history box takes its share
V.selected = 100
V:Refresh()
eq(V.rows, 13, "fewer rows beside the history box")
V.selected = nil
V:Refresh()
eq(V.rows, 19, "all of them again without it")

-- the filters: required level, quality, usable by me (the fake player is level 10; the Sword needs 20)
local function rowsShown()
	local out, n = {}, 0
	for _, w in ipairs(A.widgets) do
		if w.cells and w.shown then out[w.id], n = true, n + 1 end
	end
	return out, n
end
local function tick(quality, on)
	for _, w in ipairs(A.widgets) do
		if w.kind == "CheckButton" and w.quality == quality then
			w.checked = on
			click(w)
		end
	end
end
eq(V.qualities, nil, "no quality ticked: all of them")
tick(2, true)
local got, n = rowsShown()
check(n > 0 and got[400], "uncommon ticked: the green sword passes")
for id in pairs(got) do eq(ITEMS[id][2], 2, "and only uncommon is listed") end
tick(1, true)
got = rowsShown()
check(got[400] and got[100], "a second box adds its quality")
tick(2, false)
check(not rowsShown()[400] and rowsShown()[100], "a box cleared takes its quality out")
tick(1, false)
eq(V.qualities, nil, "all boxes cleared: all of them again")
V.minLevel = 10
V:Refresh()
got, n = rowsShown()
check(got[400] and n == 1, "only what needs level 10 or more")
local lvlCell
for _, w in ipairs(A.widgets) do if w.cells and w.shown then lvlCell = w.cells end end
eq(lvlCell.lvl.text, "20", "its level column"); eq(lvlCell.ilvl.text, "25", "and item level")
V.minLevel, V.maxLevel = nil, 5
V:Refresh()
check(not rowsShown()[400], "a highest level leaves it out")
V.maxLevel, V.usable = nil, true
V:Refresh()
got, n = rowsShown()
check(not got[400] and n > 0, "usable by me: not what needs a higher level")
local sword = A.items()[400]
eq(sword.lv, 20, "what a filter needs is kept with the item"); eq(sword.ql, 2, "level and quality")
local function usable() V:Refresh() return rowsShown()[400] end
sword.lv = 5
check(usable(), "a weapon my class wields, at my level: usable")
-- where the game does not tell proficiencies: what the class can learn
A.env.UnitClass = function() return "Mage", "MAGE" end
sword.s = 0 -- an axe
V:Refresh()
got = rowsShown()
check(not got[400] and got[100], "not a weapon my class cannot wield; what is no gear stays")
sword.c, sword.s = 4, 1
check(usable(), "cloth on a mage: usable")
sword.s = 3
check(not usable(), "mail on a mage: not")
A.env.UnitClass = function() return "Warrior", "WARRIOR" end
check(usable(), "mail on a warrior: usable")
sword.s = 4
check(not usable(), "plate before level 40: not yet")
-- where it does (everyone knows Cloth): what the character has trained
local known = { [9078] = true, [227] = true }
A.env.IsPlayerSpell = function(spell) return known[spell] or false end
sword.c, sword.s = 2, 7
check(not usable(), "a sword without the sword skill: not usable, whatever the class could learn")
known[201] = true
check(usable(), "trained: usable")
sword.s = 10
check(usable(), "a staff, trained")
sword.c, sword.s = 4, 3
check(not usable(), "mail not trained: not")
sword.s = 0
check(usable(), "a ring or cloak: anyone")
A.env.IsPlayerSpell = nil
-- recipes: only of a profession I have
sword.c, sword.s = 9, 3
A.env.C_Item.GetItemSubClassInfo = function(class, sub) return class == 9 and sub == 3 and "Engineering" or "Other" end
check(usable(), "a recipe, where the game does not list professions: left in")
A.env.GetProfessions = function() return 1, nil, nil, nil, 5 end
A.env.GetProfessionInfo = function(i) return i == 1 and "Tailoring" or "Cooking" end
check(not usable(), "an engineering recipe without engineering: not usable")
A.env.GetProfessionInfo = function(i) return i == 1 and "Engineering" or "Cooking" end
check(usable(), "with it: usable")
sword.s = 0
check(usable(), "a book: anyone")
A.env.GetProfessions, A.env.GetProfessionInfo, A.env.C_Item.GetItemSubClassInfo = nil, nil, nil
-- a skill the item asks for, that high: goggles, recipes. Read once from the tooltip's text, then kept
sword.c, sword.s = 4, 0
local tips, reads = { [400] = { { leftText = "Goggles" }, { leftText = "Requires Engineering (150)" } } }, 0
A.env.C_TooltipInfo = { GetItemByID = function(id)
	reads = reads + 1
	return { lines = tips[id] or { { leftText = "Thing" }, { leftText = "Requires Level 1" } } }
end }
A.env.GetNumSkillLines = function() return 3 end
local skills = { { "Professions", true }, { "Tailoring", false, 200 }, { "Engineering", false, 100 } }
A.env.GetSkillLineInfo = function(i) return skills[i][1], skills[i][2], false, skills[i][3] end
check(not usable(), "goggles that ask for Engineering 150, at 100: not usable"); eq(sword.rq, "Engineering:150", "what it asks for is kept with the item")
skills[3][3] = 150
check(usable(), "at 150: usable")
skills[3][1] = "Mining"
check(not usable(), "without the profession at all: not")
skills[3][1] = "Engineering"
sword.c, sword.s = 9, 3
A.env.C_Item.GetItemSubClassInfo = function() return "Engineering" end
check(usable(), "a recipe goes by the same line")
tips[400][3] = { leftText = "Already known" }
check(not usable(), "a recipe I already know: not usable")
reads = 0
check(not usable(), "still not"); eq(reads, 0, "and not read again")
tips[400][3] = nil
A.fire("NEW_RECIPE_LEARNED")
check(usable(), "after a recipe is learned they are read anew")
skills[3][3] = 149
check(not usable(), "one point short: not")
skills[3][3] = 150
A.env.C_Item.GetItemSubClassInfo = nil
A.items()[100].rq = nil
V:Refresh()
eq(A.items()[100].rq, nil, "no skill line seen once is not yet believed (the tooltip may be half fetched)")
check(rowsShown()[100], "and the item is listed meanwhile")
step(3)
eq(A.items()[100].rq, "", "seen the same a pass later, by itself: settled as asking for nothing")
reads = 0
V:Refresh()
V:Refresh()
eq(reads, 0, "once known, no tooltip is read again")
tips[400] = { { leftText = "Retrieving item information" } }
A.env.RETRIEVING_ITEM_INFO = "Retrieving item information"
sword.c, sword.s = 4, 0
sword.rq = nil
check(usable(), "a tooltip still being fetched says nothing: listed meanwhile"); eq(sword.rq, nil, "and nothing is kept of it")
tips[400] = { { leftText = "Goggles" }, { leftText = "Requires Engineering (300)" } }
step(3)
check(not rowsShown()[400], "read again by itself once it is there"); eq(sword.rq, "Engineering:300", "and kept then")
A.env.C_TooltipInfo, A.env.GetNumSkillLines, A.env.GetSkillLineInfo = nil, nil, nil
sword.rq = nil
for _, item in pairs(A.items()) do item.rq = nil end
sword.c, sword.s = 2, 0
-- the same answer every time, and the game is not asked again
local calls, real = 0, A.env.C_Item.GetItemInfo
A.env.C_Item.GetItemInfo = function(id)
	calls = calls + 1
	return real(id)
end
V.minLevel = 1
V:Refresh()
local first = select(2, rowsShown())
A.env.C_Item.GetItemInfo = function(id) calls = calls + 1 end -- (as if the game had forgotten every item)
V:Refresh()
eq(select(2, rowsShown()), first, "ticked again: the same items, though the game no longer knows them")
V.minLevel = nil
A.env.C_Item.GetItemInfo = real
-- an item the game has not loaded yet
ITEMS[400].lvl = 5
sword.lv, sword.ql = nil, nil
A.uncached[400] = true
check(not usable(), "an item the game has not loaded yet is left out for now")
A.uncached[400] = nil
step(3)
check(rowsShown()[400], "but asked for, and listed by itself once it has come")
sword.lv, sword.ql = nil, nil
local loads, load = 0, A.env.C_Item.RequestLoadItemDataByID
A.env.C_Item.RequestLoadItemDataByID = function(id) if id == 400 then loads = loads + 1 end end
A.uncached[400] = true
for _ = 1, 5 do V:Refresh() step(1) end
check(loads <= 2, "an item the game never delivers is not asked for on every redraw") -- (asked, then waiting for an answer)
A.uncached[400], A.env.C_Item.RequestLoadItemDataByID = nil, load
V:Refresh()
ITEMS[400].lvl, sword.lv = 20, 20
V.usable = nil
V:Refresh()
eq(select(2, rowsShown()), 19, "filters off: everything again")

-- resizing: more rows, a wider Item column
V.panel.w, V.panel.h = 1000, 700
V.panel.scripts.OnSizeChanged(V.panel)
eq(V.rows, 34, "a taller window has more rows"); eq(shown(), 34, "all filled")
V.panel.w, V.panel.h = nil, nil
V.panel.scripts.OnSizeChanged(V.panel)
eq(shown(), 19, "and smaller again")
for _, w in ipairs(A.widgets) do
	if w.scripts.OnMouseDown then
		w.scripts.OnMouseDown(w)
		w.scripts.OnMouseUp(w)
	end
end
check(A.DT.db.size and A.DT.db.size[1] > 0, "the window's size is saved")

local firstRow
for _, w in ipairs(A.widgets) do if w.cells and not firstRow then firstRow = w end end
eq(firstRow.id, 100, "newest first by default")
local header
for _, w in ipairs(A.widgets) do if w.col and w.col.key == "p" then header = w end end
click(header)
check(firstRow.cells.p.text == "3s 0c" and firstRow.id == 400, "sorted by price, dearest first")
click(header)
eq(firstRow.id, 7000, "and cheapest first")
for _, w in ipairs(A.widgets) do
	if w.col then
		click(w)
		click(w)
	end
end

click(firstRow)
eq(V.selected, firstRow.id, "a row is selected")
local detail
for _, w in ipairs(A.widgets) do
	if w.kind == "FontString" and type(w.text) == "string" and w.text:find("observations on", 1, true) then detail = w end
end
check(detail and detail.text:find("7-day median", 1, true), "the detail shows its figures")
local id = V.selected
click(find("Button", "Favourite"))
check(A.M.db.favs[id], "starred")
click(section("Favourites"))
eq(shown(), 1, "favourites only")
click(section("All items"))
click(find("Button", "Unfavourite"))
eq(A.M.db.favs[id], nil, "unstarred")

local ah = find("Button", "Check price at AH")
eq(ah.enabled, false, "no price check away from the auction house")
A.fire("AUCTION_HOUSE_SHOW")
step(1)
eq(ah.enabled, true, "possible at the auction house")
click(ah)
eq(A.queries[1], id, "one search, for that item")
A.fire("AUCTION_HOUSE_CLOSED")

search.focus = true
A.env.ChatEdit_InsertLink("|cffffffff|Hitem:821::|h[Herb]|h|r")
eq(search.text, "Herb", "a shift-clicked link fills the search box")
search.focus = false
A.env.ChatEdit_InsertLink("|cffffffff|Hitem:100::|h[Copper Bar]|h|r")
eq(search.text, "Herb", "only while the box has the cursor")
search:SetText("")

-- Every script of every widget is run (hover, click with both buttons, wheel, drag, typing), on every tab.
-- Nothing may raise an error and no text may show a formatting accident.
local function UseEverything(label)
	for _, tab in ipairs({ "home", "market", "inventory", "fish", "food", "npc", "quest", "item", "zone", "combat", "tools", "settings" }) do
		A.slash(tab)
		for _, w in ipairs(A.widgets) do
			local s = w.scripts
			if s.OnEnter then s.OnEnter(w) end
			if s.OnLeave then s.OnLeave(w) end
			if s.OnMouseWheel then
				s.OnMouseWheel(w, -1)
				s.OnMouseWheel(w, 1)
			end
			if s.OnDragStart then
				s.OnDragStart(w)
				s.OnDragStop(w)
			end
			if s.OnEnterPressed then
				w:SetText("er")
				s.OnEnterPressed(w)
				s.OnEscapePressed(w)
			end
			if s.OnClick and w.enabled ~= false then
				click(w, "LeftButton")
				click(w, "RightButton")
				A.slash(tab) -- a tab button may have switched tabs
			end
		end
		step(0.5)
		for _, w in ipairs(A.widgets) do
			if type(w.text) == "string" then
				check(not w.text:find("nil", 1, true) and not w.text:find("%%[ds]"), label .. ", " .. tab .. ": bad text '" .. w.text .. "'")
			end
		end
	end
end
eq(A.DT.UI:SelfTest(), 0, "the in-game self test passes")
check(A.printed[#A.printed]:find("checks passed", 1, true), "and says so")
UseEverything("with prices")
V.qualities = nil
V.selected = next(A.items())
UseEverything("with a selection")
V.qualities, V.minLevel, V.maxLevel, V.usable = nil, nil, nil, nil
eq(#A.queries, 1, "no amount of clicking searches the auction house while it is closed")
A.slash("market")
A.slash("")

-- the scan button: only at the auction house, only on a click; one list read page by page
local scanB = find("Button", "Scan Auction House")
eq(scanB.enabled, false, "no scan away from the auction house"); eq(#A.browseQueries, 0, "and none was ever sent unasked")
A.fire("AUCTION_HOUSE_SHOW")
step(1)
eq(scanB.enabled, true, "possible at the auction house")
A.pages = { { { itemKey = { itemID = 821 }, minPrice = 3, totalQuantity = 40 } }, { { itemKey = { itemID = 830 }, minPrice = 8, totalQuantity = 9 } } }
A.browse = {}
local scanPopup = A.env.StaticPopupDialogs.DAWNTOOLS_SCAN
click(scanB)
eq(A.popups[#A.popups], "DAWNTOOLS_SCAN", "the button asks which kind of scan"); eq(#A.browseQueries, 0, "and sends nothing yet")
scanPopup.OnAccept()
eq(#A.browseQueries, 1, "quick: one list query"); eq(scanB.enabled, false, "and the button waits")
scanPopup.OnAccept()
eq(#A.browseQueries, 1, "a second one sends nothing more")
step(1)
eq(A.more, 0, "the next page is not asked for before the first has come")
A.page()
step(1)
eq(A.more, 1, "then it is")
A.page()
step(2)
eq(A.items()[821].p, 3, "prices from the first page"); eq(A.items()[830].p, 8, "and from the next")
check(A.M.scanStatus:find("Scan done: 2 items", 1, true), "the scan says when it is done"); eq(scanB.enabled, true, "and can be run again")
step(5)
eq(#A.browseQueries, 1, "it does not repeat itself"); eq(A.more, 1, "nor ask for pages there are not")
A.pages = { {}, {} }
scanPopup.OnAccept()
A.fire("AUCTION_HOUSE_CLOSED")
step(2)
check(A.M.scanStatus:find("closed", 1, true), "closing the auction house ends a scan"); eq(A.more, 1, "at once")
-- the full scan: every auction, real buyouts; once per 15 minutes
A.pages = {}
A.fire("AUCTION_HOUSE_SHOW")
step(1)
A.M.db.lastFull = nil
eq(A.M:FullWait(), 0, "a full scan is possible when none was run")
A.replicate = { { 821, 5, 500 }, { 821, 1, 90 }, { 830, 2, 60 } }
scanPopup.OnAlt()
eq(A.replicated, 1, "full: asks the game for every auction"); eq(scanB.enabled, false, "and the button waits")
check(A.M:FullWait() > 14 * 60, "the 15 minutes count from the asking")
A.fire("REPLICATE_ITEM_LIST_UPDATE")
step(2)
eq(A.items()[821].p, 90, "the lowest buyout for one"); eq(A.items()[830].p, 30, "a stack's buyout is shared out")
check(A.M.scanStatus:find("Full scan done: 3 auctions, 2 items", 1, true), "it says when it is done"); eq(scanB.enabled, true, "and the button is free again")
scanPopup.OnAlt()
local fullB = { SetEnabled = function(self, on) self.on = on end }
scanPopup.OnShow({ button3 = fullB })
eq(fullB.on, false, "the popup greys Full out while it is not possible")
eq(A.replicated, 1, "no second one inside 15 minutes"); check(A.M.scanStatus:find("possible again in 15 min", 1, true), "it says how long")
scanPopup.OnAccept()
eq(#A.browseQueries, 3, "a quick scan works meanwhile")
A.fire("AUCTION_HOUSE_CLOSED")
step(2)
-- cancelled: the auction house closes before the answer is read
A.fire("AUCTION_HOUSE_SHOW")
step(1)
A.M.db.lastFull = nil
A.replicate = { { 821, 1, 7 } }
scanPopup.OnShow({ button3 = fullB })
eq(fullB.on, true, "and offers it when it is")
scanPopup.OnAlt()
A.fire("AUCTION_HOUSE_CLOSED")
A.fire("REPLICATE_ITEM_LIST_UPDATE")
step(2)
check(A.M.scanStatus:find("cancelled: nothing recorded", 1, true), "closing the auction house cancels a full scan")
eq(A.items()[821].p, 90, "and nothing of it is recorded"); check(A.M:FullWait() > 14 * 60, "but the game's turn is used up"); eq(scanB.enabled, false, "the button is off away from the auction house")

-- Inventory: bags always, the bank while it is open; every character of the account; nothing to the guild
local Inv, me = A.DT.Inventory, "Player-Alice"
local Count = A.env.DawnInventory.API.Count
A.bags, A.bank = { { 110, 16 }, { 110, 4 }, 100 }, { { 100, 8 } }
A.fire("BAG_UPDATE_DELAYED")
eq(Count(110), 20, "stacks in the bags add up"); eq(Count(100), 1, "a slot without a stack size is one")
eq(select(2, Count(100)), 0, "the bank is not known before it was opened")
A.bankOpen = true
A.fire("BANKFRAME_OPENED")
eq(select(2, Count(100)), 8, "the bank is read when it opens")
A.bankOpen = false
A.fire("BANKFRAME_CLOSED")
A.bags = { { 110, 2 } }
A.fire("BAG_UPDATE_DELAYED")
eq(Count(110), 2, "the bags follow"); eq(select(2, Count(100)), 8, "the bank stays as last seen")
eq(Count(110, "Player-Nobody"), 0, "an unknown character has nothing")
Inv.db.chars["Player-Alt"] = { name = "Alice Alt", class = "DRUID", bags = { [110] = 5 }, bank = {} }
eq(Count(110, "Player-Alt"), 5, "another character's bags")
A.slash("inventory")
local function text(part)
	for _, w in ipairs(A.widgets) do
		if w.kind == "FontString" and w.shown ~= false and type(w.text) == "string" and w.text:find(part, 1, true) then return w.text end
	end
end
local function invRow(id)
	for _, w in ipairs(A.widgets) do
		if w.invRow and w.shown ~= false and w.id == id then
			local c = w.cols
			return c.bags.text .. " / " .. c.bank.text .. " / " .. c.total.text .. " / " .. c.all.text .. " / " .. c.who.text
		end
	end
end
local NONE = "|cff555555-|r"
Inv.Pick(nil) -- (the sweep over every button above picked something)
check(text("2 items"), "this character's items, to begin with"); eq(Inv.showButton.label.text, "|cffffffffAlice Smith|r", "the button says whose")
eq(invRow(110), "2 / " .. NONE .. " / 2 / |cffffd1007 / |cffffffffAlice Smith|r 2, |cffffffffAlice Alt|r 5",
	"bags, bank, total, then all characters together (gold: others have some), and who holds it, this character first")
eq(invRow(100), NONE .. " / 8 / 8 / 8 / |cffffffffAlice Smith|r 8", "what is in the bank; all characters = mine where nobody else has any")
check(not text("Bank not seen yet"), "and no word of another character's bank")
-- the list under the button
click(Inv.showButton)
local entries = Inv.menu.entries
eq(Inv.menu.shown, true, "a click on the button opens the list"); eq(#entries, 3, "this character, all, the other one")
eq(entries[1].label.text, "|cffffd100> |r|cffffffffAlice Smith|r", "the one shown is marked"); eq(entries[2].label.text, "   All characters", "all of them")
eq(entries[1].forget.shown, false, "this character cannot be forgotten"); eq(entries[3].forget.shown, true, "another can")
click(entries[2])
eq(Inv.menu.shown, false, "a pick closes the list"); eq(Inv.showButton.label.text, "All characters", "and is shown")
check(text("2 items"), "both items listed"); check(text("Bank not seen yet on: |cffffffffAlice Alt"), "and which bank was never opened")
eq(invRow(110), "7 / " .. NONE .. " / 7 / 7 / |cffffffffAlice Smith|r 2, |cffffffffAlice Alt|r 5", "everyone's bags added up")
Inv.db.chars[me].bags[100] = 3
Inv.Refresh()
eq(invRow(100), "3 / 8 / 11 / 11 / |cffffffffAlice Smith|r 11", "bags and bank side by side, with their sum")
click(Inv.showButton)
click(entries[3])
eq(Inv.showButton.label.text, "|cffffffffAlice Alt|r", "the other character"); check(text("1 items") and not invRow(100), "alone")
eq(invRow(110), "5 / " .. NONE .. " / 5 / |cffffd1007 / |cffffffffAlice Smith|r 2, |cffffffffAlice Alt|r 5", "its own figures")
-- a character that was deleted is forgotten from the list
Inv.db.chars["Player-Gone"] = { name = "Gone", class = "MAGE", bags = { [110] = 50 }, bank = {} }
click(Inv.showButton)
click(Inv.showButton)
click(Inv.showButton)
eq(#entries, 4, "a further character is in the list")
click(entries[4].forget)
eq(A.popups[#A.popups], "DAWNTOOLS_INV_FORGET", "the x asks first"); check(Inv.db.chars["Player-Gone"], "and forgets nothing yet")
Inv.Pick("Player-Gone")
A.env.StaticPopupDialogs.DAWNTOOLS_INV_FORGET.OnAccept(nil, "Player-Gone")
eq(Inv.db.chars["Player-Gone"], nil, "yes: its bags and bank are gone"); eq(Inv.showButton.label.text, "|cffffffffAlice Smith|r", "and the list is back on this character")
eq(invRow(110), "2 / " .. NONE .. " / 2 / |cffffd1007 / |cffffffffAlice Smith|r 2, |cffffffffAlice Alt|r 5", "its units no longer count")
Inv.Forget(me)
check(Inv.db.chars[me], "this character is never forgotten")
Inv.Pick("all")
for _, w in ipairs(A.widgets) do
	if w.kind == "EditBox" and w.shown ~= false and w ~= search then w:SetText("ore") end
end
step(0.5)
check(text("1 items"), "search by part of a name")
check(not A.DT.modules.inventory.hello and not A.DT.modules.inventory.onMessage, "the module has nothing to say to the guild")
eq(A.env.SLASH_DAWNTOOLS_INVENTORY1, "/dtinv", "its short command")

-- Settings sits apart from the working tabs
check(find("Button", "Settings") and find("Button", "Inventory"), "tab buttons")

-- Weapons in the categories: One-Handed and the like, the weapon types under the group picked
A.slash("market")
click(section("All items"))
click(section("Weapons"))
local oneHanded = section("One-Handed")
check(oneHanded, "weapons open into their groups"); eq(oneHanded.text.text, "    One-Handed", "indented once")
check(not section("Two-Handed"), "a group nothing was seen of is not listed"); check(not section("Sub 0"), "the types wait for their group")
click(oneHanded)
eq(V.group, "1h", "a group picked"); check(section("Sub 0"), "shows its weapon types")
eq(section("Sub 0").text.text, "        Sub 0", "indented twice")
for _, w in ipairs(A.widgets) do
	if w.cells and w.shown then eq(ITEMS[w.id][6], 2, "only weapons are listed") end
end
click(section("Sub 0"))
eq(V.leaf, 0, "a weapon type picked")
click(section("Sub 0"))
check(V.leaf == nil and V.group == "1h", "clicked again: back to its group")
click(section("One-Handed"))
check(V.group == nil and V.class == 2, "the group clicked again: back to all weapons")
click(section("All items"))
check(V.group == nil and V.class == nil, "and out again")

-- Armor: by type, then by where it is worn; a cloak is filed under Miscellaneous, as the auction house has it
ITEMS[900] = { "Plate Helm", 2, 1, 500, false, 4, 4, slot = "INVTYPE_HEAD" }
ITEMS[901] = { "Linen Cloak", 1, 1, 50, false, 4, 1, slot = "INVTYPE_CLOAK" }
ITEMS[902] = { "Plate Gloves", 2, 1, 400, false, 4, 4, slot = "INVTYPE_HAND" }
ITEMS[903] = { "Plate Robe", 2, 1, 400, false, 4, 4, slot = "INVTYPE_ROBE" }
for id = 900, 903 do
	A.searched[id] = { { 100 + id, 1 } }
	A.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = id })
end
step(3)
eq(A.items()[900].e, "INVTYPE_HEAD", "where an item is worn is kept with it")
local function listed()
	local ids = {}
	for _, w in ipairs(A.widgets) do
		if w.cells and w.shown then ids[#ids + 1] = w.id end
	end
	table.sort(ids)
	return table.concat(ids, " ")
end
local function labels()
	local out = {}
	for _, w in ipairs(A.widgets) do
		if w.entry and w.shown then out[#out + 1] = w.entry.label end
	end
	return table.concat(out, ",")
end
click(section("Armor"))
check(labels():find("Armor,Sub 4,Sub 0", 1, true), "armor opens into its types: plate, then miscellaneous for the cloak")
eq(listed(), "900 901 902 903", "all armor")
click(section("Sub 4"))
check(labels():find("Sub 4,INVTYPE_HEAD,INVTYPE_CHEST,INVTYPE_HAND,Sub 0", 1, true), "a type opens into its slots, in the auction house's order")
eq(listed(), "900 902 903", "plate only")
click(section("INVTYPE_HAND"))
eq(listed(), "902", "one slot")
click(section("INVTYPE_CHEST"))
eq(listed(), "903", "a robe is a chest piece")
click(section("Sub 0"))
check(labels():find("Sub 0,INVTYPE_CLOAK", 1, true), "miscellaneous has the cloak slot"); eq(listed(), "901", "and the cloak")
click(section("All items"))

-- Vendors: what a shop sells is recorded when it is opened, and shown beside the auction price
local shop = { { 100, 400, 20, -1 }, { 110, 9000, 1, 2 }, { 821, 50, 5, -1, true } } -- item, price, stack, left, other cost
A.env.GetMerchantNumItems = function() return #shop end
A.env.GetMerchantItemID = function(i) return shop[i][1] end
A.env.C_MerchantFrame = { GetItemInfo = function(i)
	return { price = shop[i][2], stackCount = shop[i][3], numAvailable = shop[i][4], hasExtendedCost = shop[i][5] or false }
end }
A.env.GetRealZoneText = function() return "Stranglethorn Vale" end
A.env.GetSubZoneText = function() return "Booty Bay" end
A.npcName = "Kira"
A.fire("MERCHANT_SHOW")
step(1)
local GetVendor = A.env.DawnMarket.API.GetVendor
local vp, vname, vzone, vlimited = GetVendor(100)
eq(vp, 20, "a vendor's price for one"); eq(vname, "Kira", "who sells it"); eq(vzone, "Booty Bay, Stranglethorn Vale", "where"); eq(vlimited, false, "stock not limited")
eq(select(4, GetVendor(110)), true, "limited stock is marked"); eq(GetVendor(821), nil, "what is not paid for in money is left out")
A.npcName, shop = "Dearer Dan", { { 100, 2000, 20, -1 } }
A.fire("MERCHANT_SHOW")
eq(select(2, GetVendor(100)), "Kira", "the cheapest seller is kept")
A.npcName, shop = "Kira", { { 100, 600, 20, -1 } }
A.fire("MERCHANT_SHOW")
eq(GetVendor(100), 30, "a seller's own price is brought up to date")
A.npcName = nil
click(section("All items"))
V.vendorOnly = true
V:Refresh()
local sellers = {}
for _, w in ipairs(A.widgets) do
	if w.cells and w.shown then sellers[w.id] = w.cells.vbuy.text end
end
check(sellers[100] and sellers[110] and not sellers[821], "the vendor filter lists what a vendor sells")
check(sellers[100]:find("30c", 1, true), "with the vendor's price"); check(sellers[110]:find("*", 1, true), "and a star for limited stock")
V.vendorOnly = nil
V:Refresh()
A.env.GameTooltip.lines = {}
A.tooltipHook(A.env.GameTooltip, { id = 100 })
check(table.concat(A.env.GameTooltip.lines, "|"):find("30c at Kira, Booty Bay, Stranglethorn Vale", 1, true), "the item's tooltip says where a vendor sells it")

-- Auction houses: my faction's and the cross-faction one keep their own prices
local M = A.M
local Latest = A.env.DawnMarket.API.GetLatest
local function houseB(key)
	for _, w in ipairs(A.widgets) do if w.house == key then return w end end
end
eq(M.view, "H", "away from an auctioneer: my faction's house"); eq(houseB("H").text, "|cffffd100Horde|r", "its button is the lit one")
eq(houseB("X").text, "|cff999999X-Faction|r", "the other is not")
local hordePrice = M:House("H")[100].p
A.npc, A.npcFaction = "Creature-0-1-2-3-9999-00001B", "Neutral"
A.fire("AUCTION_HOUSE_SHOW")
step(1)
eq(M.at, "X", "an auctioneer of no faction is the cross-faction house"); eq(M.view, "X", "and its prices are shown")
eq(A.env.DawnMarket.API.GetHouse(), "X", "the other tabs can ask which house that is"); eq(select(2, A.env.DawnMarket.API.GetHouse()), "X-Faction", "and its name")
eq(A.items()[100], nil, "which are not my faction's"); eq(Latest(100), nil, "for the other tabs neither")
M.db.settings.share = true
A.searched[100] = { { hordePrice + 7, 3 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 100)
eq(Latest(100), hordePrice + 7, "a price seen here is filed here"); eq(M:House("H")[100].p, hordePrice, "and my faction's stays what it was")
M.Sync:Flush()
check(sent[#sent].text:find("ZX|100,", 1, true), "it goes to the guild marked with its house")
step(1)
eq(houseB("X").text, "|cffffd100X-Faction|r", "at the cross-faction house its button is lit")
click(houseB("H"))
eq(M.view, "H", "a house's button shows that house"); eq(houseB("H").text, "|cffffd100Horde|r", "and lights up"); eq(Latest(100), hordePrice, "with its prices")
click(houseB("H"))
eq(M.view, "H", "clicking the lit one changes nothing")
A.searched[110] = { { 9, 1 } }
A.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 110)
eq(M:House("X")[110].p, 9, "what is seen is still filed where I stand, whatever is shown")
-- from the guild
local function ob(id, p) return L.Encode({ { id = id, p = p, q = 1, t = A.DT.Now(), o = "=" } }) end
M.Sync:OnMessage("PUSH", "X|" .. ob(7001, 5), "Zed-Forever")
check(M:House("X")[7001] and M:House("X")[7001].p == 5 and not M:House("H")[7001], "a guild price goes to the house it names")
M.Sync:OnMessage("PUSH", ob(7002, 5), "Zed-Forever")
M.Sync:OnMessage("PUSH", "Q|" .. ob(7002, 5), "Zed-Forever")
check(not M:House("X")[7002] and not M:House("H")[7002], "one that names none, or an unknown one, is dropped")
M.db.settings.share = nil
-- putting the house right by hand
step(1)
local hereB = find("Button", "Wrong house?")
check(hereB and hereB.shown and find("FontString", "You are at: |cffffd100X-Faction|r"), "at an auctioneer the tab says which house it takes it for")
click(hereB)
eq(M.at, "H", "a click puts that right"); eq(M.db.auctioneers["9999"], "H", "for this auctioneer")
A.fire("AUCTION_HOUSE_CLOSED")
step(1)
eq(M.at, nil, "away again"); eq(hereB.shown, false, "the button goes")
A.fire("AUCTION_HOUSE_SHOW")
eq(M.at, "H", "and it is remembered")
A.fire("AUCTION_HOUSE_CLOSED")
A.npc, A.npcFaction = "Creature-0-1-2-3-6666-00001C", "Alliance"
A.fire("AUCTION_HOUSE_SHOW")
eq(M.at, "X", "the other faction's auctioneer: cross-faction")
A.fire("AUCTION_HOUSE_CLOSED")
A.npc, A.npcFaction = "Creature-0-1-2-3-7777-00001D", nil
A.fire("AUCTION_HOUSE_SHOW")
eq(M.at, "X", "a faction the game does not tell, in a goblin town: cross-faction")
A.fire("AUCTION_HOUSE_CLOSED")
A.env.GetSubZoneText = function() return "Valley of Strength" end
A.fire("AUCTION_HOUSE_SHOW")
eq(M.at, "H", "a faction the game does not tell, elsewhere: my own house")
A.fire("AUCTION_HOUSE_CLOSED")
A.env.GetSubZoneText = function() return "Booty Bay" end
step(1)
-- saved data from before the houses
local old = NewClient("Olga", { db = { market = { items = { [100] = { p = 5, q = 1, t = Now(), o = "Olga", d = {} } }, settings = { share = false } } } })
eq(old.items()[100].p, 5, "prices saved before the houses were told apart are my faction's"); eq(old.M.db.items, nil, "moved, not copied")
leave(old)

-- Fish: what a cast is worth where, and what cooking adds
local Fish = A.DT.Fish
ITEMS[6359] = { "Firefin Snapper", 1, 20, 4, true, 7, 8 }
ITEMS[6362] = { "Raw Rockscale Cod", 1, 20, 3, true, 7, 8 }
ITEMS[4594] = { "Rockscale Cod", 1, 20, 6, true, 0, 5 }
ITEMS[13759] = { "Raw Nightfin Snapper", 1, 20, 5, true, 7, 8 }
ITEMS[13931] = { "Nightfin Soup", 1, 20, 10, true, 0, 5 }
ITEMS[9999] = { "Firefin Stew", 1, 20, 10, true, 0, 5 }
for id, price in pairs({ [6359] = 500, [6362] = 100, [4594] = 300, [13759] = 100, [13931] = 400, [9999] = 300 }) do A.M:Record(id, price, 5) end
A.slash("fish")
click(find("Button", "Spots")) -- (the window test left the other table up)
-- (and sorted some other way: put a table back to "biggest first" by one of its columns)
local function sortDesc(title)
	for _ = 1, 3 do
		for _, w in ipairs(A.widgets) do
			if w.kind == "Button" and w.shown ~= false and w.text and w.text.text and w.text.text:find(title, 1, true) then
				if w.text.text:find(title .. " v", 1, true) then return end
				click(w)
			end
		end
	end
end
sortDesc("Per cast")
local fishBox = Fish.search
fishBox:SetText("strangle") -- (the window test left the table sorted some other way: look it up)
step(1)
check(text("Stranglethorn Vale"), "the built-in waters are listed before anything was caught")
fishBox:SetText("")
step(1)
check(text("Prices: Horde auction house"), "and it says whose prices these are")
-- catches
local loot, fishing = { { 6359, 2 }, { 600, 1 } }, true
A.env.IsFishingLoot = function() return fishing end
A.env.GetRealZoneText = function() return "Testwater" end
A.env.GetSubZoneText = function() return "Pier" end
A.env.GetNumLootItems = function() return #loot end
A.env.GetLootSlotLink = function(i) return "|Hitem:" .. loot[i][1] .. "::|h[" .. ITEMS[loot[i][1]][1] .. "]|h" end
A.env.GetLootSlotInfo = function(i) return nil, "x", loot[i][2] end
A.env.GetProfessions = function() return nil, nil, nil, 7 end
A.env.GetProfessionInfo = function() return "Fishing", nil, 140 end
A.fire("LOOT_READY")
A.fire("LOOT_OPENED")
local pier = Fish.db.catches["Testwater, Pier"]
eq(pier.casts, 1, "one loot window is one cast, however often it is announced"); eq(pier.items[6359], 2, "with what was in it")
eq(pier.skill, 140, "and the fishing skill it was caught at")
A.fire("LOOT_CLOSED")
A.fire("LOOT_OPENED")
eq(pier.casts, 2, "the next cast"); eq(pier.items[600], 2, "junk counts too")
-- a game with the older skill list instead of the profession list
do
	local professions, info = A.env.GetProfessions, A.env.GetProfessionInfo
	A.env.GetProfessions, A.env.GetProfessionInfo = nil, nil
	A.env.GetNumSkillLines = function() return 2 end
	A.env.GetSkillLineInfo = function(i)
		if i == 1 then return "Secondary Skills", true end
		return "Fishing", false, false, 90, 0, 25
	end
	A.env.GetSubZoneText = function() return "Jetty" end
	A.fire("LOOT_CLOSED")
	A.fire("LOOT_OPENED")
	eq(Fish.db.catches["Testwater, Jetty"].skill, 90, "the fishing skill is read from the skill list where that is what the game has")
	Fish.db.catches["Testwater, Jetty"] = nil
	A.env.GetSubZoneText = function() return "Pier" end
	A.env.GetNumSkillLines, A.env.GetSkillLineInfo = nil, nil
	A.env.GetProfessions, A.env.GetProfessionInfo = professions, info
end
A.fire("LOOT_CLOSED")
fishing = false
A.fire("LOOT_OPENED")
eq(pier.casts, 2, "loot that is not fished is not a cast")
A.fire("LOOT_CLOSED")
Fish.Refresh()
check(text("Testwater, Pier"), "my own spot is listed")
local perCast = L.Money((4 * 500 + 2 * (Latest(600) or 100)) / 2) -- 4 snappers at 5s and 2 fangs at their price, over 2 casts
check(text("|cff888888~|r" .. perCast), "per cast: what was caught at today's prices over the casts, still marked a guess")
pier.casts, pier.items[6359], pier.items[600] = 20, 40, 20
Fish.Refresh()
check(text("Firefin Snapper 200%"), "what bites, per cast"); check(not text("|cff888888~|r" .. perCast) and text(perCast), "believed from 20 casts on")
-- the Fish table
for _, w in ipairs(A.widgets) do
	if w.kind == "Button" and w.text == "Fish" and w.shown ~= false and w.scripts.OnClick and not w.id then click(w) end
end
sortDesc("Raw")
check(text("Raw Rockscale Cod"), "the Fish table lists the fish")
check(text("|cff40ff40+2s 0c|r"), "cooking adds the cooked price less the raw one")
for _, w in ipairs(A.widgets) do -- hovering the row shows the raw fish; hovering its cooked columns, the food
	if w.cols and w.shown and w.data and w.data.id == 6362 then
		A.env.GameTooltip.lines = {}
		w.scripts.OnEnter(w)
		eq(A.env.GameTooltip.lines[1], "item:6362", "the row's tooltip is the raw fish")
		A.env.GameTooltip.lines = {}
		w.over.scripts.OnEnter(w.over)
		eq(A.env.GameTooltip.lines[1], "item:4594", "over the cooked columns it is the food"); eq(w.over.shown, true, "where there is one")
	end
end
check(text("|cff40ff40+2s 75c|r"), "less the other mats, at the vendor's price where he sells them")
check(text("Testwater, Pier |cff40ff40200%|r"), "and where it bites")
Fish.db.recipes[9999] = { q = 2, r = { { 6359, 1 }, { 159, 1 } } }
Fish.Refresh()
check(text("Firefin Stew") and text("|cff40ff40+75c|r"), "a recipe from the Cooking window is used: 2 x 3s less 25c water less the 5s fish")
-- sorting and searching
local function fishRows()
	local out = {}
	for _, w in ipairs(A.widgets) do
		if w.cols and w.shown and w.data then out[#out + 1] = w.data end
	end
	return out
end
local function head(title)
	for _, w in ipairs(A.widgets) do
		if w.kind == "Button" and w.text and w.text.text and w.text.text:find(title, 1, true) and w.shown ~= false then return w end
	end
end
click(find("Button", "Spots"))
sortDesc("Per cast")
local rowsNow = fishRows()
check(rowsNow[1].sort[4] >= rowsNow[2].sort[4], "spots start with the best per cast"); check(head("Per cast").text.text:find(" v", 1, true), "and the header says so")
click(head("Per cast"))
rowsNow = fishRows()
check(rowsNow[1].sort[4] <= rowsNow[2].sort[4], "a click on the header turns it round")
click(head("Spot"))
rowsNow = fishRows()
check(rowsNow[1].sort[1] < rowsNow[2].sort[1], "another header sorts by that column, names from A")
click(head("Skill"))
check(fishRows()[1].sort[2] >= fishRows()[2].sort[2], "numbers from the biggest")
local fishSearch = Fish.search
fishSearch:SetText("testwater")
step(1)
rowsNow = fishRows()
check(#rowsNow == 1 and rowsNow[1][1] == "Testwater, Pier", "the search box finds a spot by name")
eq(rowsNow[1].sort[5] * 170, rowsNow[1].sort[4] * 170, "per hour goes by per cast"); check(rowsNow[1][5]:find(A.DT.Money(math.floor(rowsNow[1].sort[4] * 170 + 0.5)), 1, true), "170 casts of it")
check(rowsNow[1].sort[6] > 0 and rowsNow[1][6]:find("|cff40ff40", 1, true), "and the dearest single catch of the spot is named with its price: " .. rowsNow[1][6])
fishSearch:SetText("firefin")
step(1)
check(#fishRows() >= 1 and fishRows()[1].sort[7]:find("Firefin", 1, true), "or by what bites there")
fishSearch:SetText("")
step(1)
-- the skill column against my own skill (140 here)
local function skillOf(name)
	fishSearch:SetText(name) -- (it may be scrolled out of sight: look it up)
	Fish.Refresh()
	local found
	for _, d in ipairs(fishRows()) do
		if d[1] == name then found = d[2] end
	end
	fishSearch:SetText("")
	return found
end
eq(skillOf("Elwynn Forest"), "|cff40ff4025|r", "green: nothing gets away"); eq(skillOf("Stranglethorn Vale"), "|cffffd100225|r", "yellow: I can cast, some get away")
A.env.GetProfessionInfo = function() return "Fishing", nil, 140, 300, 0, 0, 356, 100 end
eq(skillOf("Stranglethorn Vale"), "|cff40ff40225|r", "a lure and gear count")
eq(skillOf("Eastern Plaguelands"), "|cffff4040425|r", "red: out of reach")
-- the gear table, and the link an item row gives
click(find("Button", "Gear"))
sortDesc("Fishing")
local gear = fishRows()
check(gear[1][2] == "+100" and gear[1].id == 6533, "gear starts with the biggest bonus")
local popups = #A.popups
for _, w in ipairs(A.widgets) do
	if w.cols and w.data == gear[1] then w.scripts.OnMouseUp(w) end
end
eq(A.popups[#A.popups], "DAWNTOOLS_LINK", "a click on an item row offers a link"); eq(#A.popups, popups + 1, "once")
eq(A.DT:ItemLink(6533), "https://www.wowhead.com/forever/item=6533", "to the item's page")
click(find("Button", "Spots"))
eq(A.DT.modules.fish.hello, nil, "the module has nothing to say to the guild")

-- Food: what the Cooking window lists, what this character lacks, and who in the guild can cook it
ITEMS[5001] = { "Stamina Stew", 1, 20, 10, true, 0, 5, lvl = 15 }
ITEMS[5002] = { "Spirit Soup", 1, 20, 10, true, 0, 5, lvl = 25 }
ITEMS[5003] = { "Plain Bread", 1, 20, 10, true, 0, 5 }
local TIPS = { [5001] = "Use: Restores health. Well fed: 6 Stamina and Spirit.", [5002] = "Use: Restores health. 8 Spirit.", [5003] = "Use: Restores 61 health." }
local function kitchen(c, learned) -- a Cooking window that lists recipes 1..3 for foods 5001..5003
	c.env.C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = ITEMS[id][1] }, { leftText = TIPS[id] } } } end }
	c.env.C_TradeSkillUI = {
		GetBaseProfessionInfo = function() return { profession = 5, professionName = "Cooking" } end,
		GetAllRecipeIDs = function() return { 1, 2, 3 } end,
		GetRecipeInfo = function(r) return { learned = learned[r] or false, categoryID = 9 } end,
		GetCategoryInfo = function() return { name = "Old Recipes" } end,
		GetRecipeSchematic = function(r) return { outputItemID = 5000 + r } end,
	}
	c.fire("TRADE_SKILL_SHOW")
	step(2)
end
local Fay, Gus = NewClient("Fay"), NewClient("Gus")
local FF, GF = Fay.DT.Food, Gus.DT.Food
Fay.slash("food")
eq(Fay.popups[#Fay.popups], "DAWNTOOLS_FOOD_SHARE", "the first look at the tab asks about sharing")
local foodSent = count("KNOWN")
kitchen(Fay, { [1] = true, [3] = true })
eq(FF.db.mine["Player-Fay"].ids[5001], true, "what I can cook is recorded"); eq(FF.db.mine["Player-Fay"].ids[5002], nil, "what I cannot is not")
check(FF.db.foods[5002], "but the food is known of"); eq(FF.db.foods[5002].cat, "Old Recipes", "with the window's heading")
eq(count("KNOWN"), foodSent, "nothing is told to the guild before I agreed")
FF.Refresh()
local function foodText(c, part)
	for _, w in ipairs(c.widgets) do
		if w.kind == "FontString" and type(w.text) == "string" and w.text:find(part, 1, true) then return w.text end
	end
end
local function foodRows(c)
	local out = {}
	for _, w in ipairs(c.widgets) do
		if w.fcols and w.shown and w.data then out[#out + 1] = w.data end
	end
	return out
end
eq(#foodRows(Fay), 3, "all the food is listed"); eq(foodRows(Fay)[1].id, 5003, "lowest level first")
check(foodText(Fay, "3 foods, 2 of them known to this character"), "with a count")
check(foodText(Fay, "Stamina (1)") and foodText(Fay, "Spirit (1)") and foodText(Fay, "Health only (1)"), "grouped by what it gives, the first thing named")
eq(foodRows(Fay)[1][4], "|cff40ff40known|r", "a recipe I have"); eq(foodRows(Fay)[3][4], "|cffff4040missing|r", "one I lack")
eq(foodRows(Fay)[1][5], "|cff40ff40You|r", "I can cook it"); eq(foodRows(Fay)[3][5], "|cff888888nobody known|r", "nobody can cook the other")
for _, w in ipairs(Fay.widgets) do
	if w.kind == "Button" and w.text == "Hide missing" then w.scripts.OnClick(w) end
end
eq(#foodRows(Fay), 2, "missing recipes can be left out"); check(foodText(Fay, "All food (2)"), "from the counts too")
for _, w in ipairs(Fay.widgets) do
	if w.kind == "Button" and w.text == "Show missing" then w.scripts.OnClick(w) end
end
-- a character without Cooking (its window was never read) knows nothing: hiding the missing hides all
local fay = FF.db.mine["Player-Fay"]
local hadIds, hadT = fay.ids, fay.t
fay.ids, fay.t = {}, nil
FF.Refresh()
eq(#foodRows(Fay), 3, "a character without Cooking: everything listed")
for _, w in ipairs(Fay.widgets) do
	if w.kind == "Button" and w.text == "Hide missing" then w.scripts.OnClick(w) end
end
eq(#foodRows(Fay), 0, "and all of it hidden with the missing"); check(foodText(Fay, "Nothing known on this character"), "with a word why")
for _, w in ipairs(Fay.widgets) do
	if w.kind == "Button" and w.text == "Show missing" then w.scripts.OnClick(w) end
end
fay.ids, fay.t = hadIds, hadT
FF.Refresh()
for _, w in ipairs(Fay.widgets) do
	if w.section and w.section.kind == "Spirit" then w.scripts.OnClick(w) end
end
eq(#foodRows(Fay), 1, "a type picked on the left"); eq(foodRows(Fay)[1].id, 5002, "lists its food")
for _, w in ipairs(Fay.widgets) do
	if w.section and not w.section.kind then w.scripts.OnClick(w) end
end
eq(#foodRows(Fay), 3, "and all again")
local function foodHead(title)
	for _, w in ipairs(Fay.widgets) do
		if w.kind == "Button" and w.text and w.text.text and w.text.text:find(title, 1, true) then return w end
	end
end
check(foodHead("Level").text.text:find("Level ^", 1, true), "sorted by level to start with, and the header says so")
foodHead("Food").scripts.OnClick(foodHead("Food"))
eq(foodRows(Fay)[1].name, "Plain Bread", "a click on a header sorts by it: names from A")
foodHead("Food").scripts.OnClick(foodHead("Food"))
eq(foodRows(Fay)[1].name, "Stamina Stew", "again: the other way round")
foodHead("This character").scripts.OnClick(foodHead("This character"))
eq(foodRows(Fay)[3][4], "|cffff4040missing|r", "by what I know: the missing ones last")
foodHead("Level").scripts.OnClick(foodHead("Level"))
eq(foodRows(Fay)[1].id, 5003, "and back by level")
-- the guild
FF.db.settings.share, GF.db.settings.share = true, true
kitchen(Fay, { [1] = true, [2] = true, [3] = true })
step(2)
eq(count("KNOWN", "Fay"), 1, "learning a recipe tells the guild, once agreed")
check(GF.db.guild["Fay Smith"] and GF.db.guild["Fay Smith"].ids[5002], "a guild member takes it in, under the character's full name")
check(GF.db.foods[5001], "and so hears of the food itself")
Gus.slash("food")
kitchen(Gus, { [3] = true })
step(2)
local gusRows = foodRows(Gus)
eq(gusRows[1][5], "|cff40ff40You|r, Fay Smith", "who can cook it: me, then the guild"); eq(gusRows[2][5], "Fay Smith", "the guild alone")
eq(gusRows[2][4], "|cffff4040missing|r", "and that I lack it")
check(FF.db.guild["Gus Smith"] and FF.db.guild["Gus Smith"].ids[5003] and not FF.db.guild["Gus Smith"].ids[5001], "it goes both ways")
-- someone who comes later asks for the lists
local Hal = NewClient("Hal")
Hal.DT.Food.db.settings.share = true
step(700)
check(Hal.DT.Food.db.guild["Fay Smith"] and Hal.DT.Food.db.guild["Gus Smith"], "a member who joins later asks, and is told")
local known = count("KNOWN")
step(1300)
eq(count("KNOWN"), known, "and nobody goes on repeating what is known")
-- not believed
GF.db.settings.share = false
kitchen(Fay, { [1] = true })
step(2)
check(GF.db.guild["Fay Smith"].ids[5002], "with sharing off nothing comes in")
GF.db.settings.share = true
local function foodMsg(payload) return table.concat({ "food", "KNOWN", 1, "z", LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(payload)) }, "\t") end
inject(Gus, "Mallory-Forever", foodMsg("Gus Smith;5001,5002"))
check(not GF.db.guild["Gus Smith"], "nobody else speaks for my own characters")
inject(Gus, "Mallory-Forever", foodMsg("no list here"))
inject(Gus, "Mallory-Forever", foodMsg(("x"):rep(50) .. ";5001"))
eq(GF.db.guild[("x"):rep(50)], nil, "and nonsense is dropped")
leave(Fay) leave(Gus) leave(Hal)

-- NPCs: read from QuestieDB as the tab is used, searched, filtered, and a waypoint set
do
	local Npc = A.DT.Npc
	A.slash("npc")
	check(text("Needs the QuestieDB addon"), "without QuestieDB the tab says what it needs")
	eq(#Npc.Find("anything", {}), 0, "and lists nothing")
end
do
	local B2 = NewClient("Nell")
	B2.DT.db.settings.background = false -- (this client reads when its tabs are opened; the background reading is checked below)
	local Npc = B2.DT.Npc
	local function btext(part)
		for _, w in ipairs(B2.widgets) do
			if w.kind == "FontString" and w.shown ~= false and type(w.text) == "string" and w.text:find(part, 1, true) then return w.text end
		end
	end
	-- flags as in Classic: quest giver 2, vendor 4, trainer 16, innkeeper 128, repair 16384
	local NPCS = {
		[10] = { name = "Gorak", minLevel = 30, maxLevel = 30, rank = 0, zoneID = 1637, friendlyToFaction = "H", subName = "Fishing Supplies", npcFlags = 4 + 16384,
			spawns = { [1637] = { { 54.2, 68.1 }, { 20, 30 } } }, questStarts = { 5 } },
		[11] = { name = "Lumak", minLevel = 35, maxLevel = 35, rank = 0, zoneID = 1637, friendlyToFaction = "H", subName = "Fishing Trainer", npcFlags = 16 + 2,
			spawns = { [1637] = { { 69.8, 29.2 } } }, questStarts = { 7, 8 }, questEnds = { 7 } },
		[12] = { name = "Old Greyfin", minLevel = 22, maxLevel = 24, rank = 4, zoneID = 17, spawns = { [17] = { { 40, 40 } } }, waypoints = { [17] = { { { 1, 1 } } } } },
		[13] = { name = "Innkeeper Gryshka", minLevel = 35, maxLevel = 35, rank = 0, zoneID = 1637, friendlyToFaction = "H", subName = "Innkeeper", npcFlags = 128 + 4,
			spawns = { [1637] = { { 54, 68 } } } },
		[14] = { name = "Scripted Ghost", minLevel = 60, maxLevel = 60, rank = 3, zoneID = 0 },
		[15] = { name = "Marshal Gorakson", minLevel = 50, maxLevel = 50, rank = 1, zoneID = 12, friendlyToFaction = "A", spawns = { [12] = { { 10, 10 } }, [99] = { { 5, 5 } } } },
	}
	local reads = 0
	B2.env.LibQuestieDB = {
		RequireContract = function(n) return n == 4 end,
		Enum = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, INNKEEPER = 128, REPAIR = 16384 } },
		Npc = {
			GetAllIds = function() return { 10, 11, 12, 13, 14, 15 } end,
			GetAll = function(id, keys)
				reads = reads + 1
				local out = { n = #keys }
				for i, key in ipairs(keys) do out[i] = NPCS[id][key] end
				return out
			end,
			Get = function(id, key) return NPCS[id] and NPCS[id][key] end,
		},
	}
	local AREAS = { [1637] = "Orgrimmar", [17] = "The Barrens", [12] = "Elwynn Forest", [99] = "Nowhere" }
	local pin
	B2.env.C_Map = {
		GetAreaInfo = function(area) return AREAS[area] end,
		GetBestMapForUnit = function() return 1454 end,
		GetPlayerMapPosition = function() return { GetXY = function() return 0.21, 0.31 end } end,
		CanSetUserWaypointOnMap = function() return true end,
		SetUserWaypoint = function(point) pin = point end,
	}
	B2.env.UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map, x, y } end }
	B2.env.QuestieLoader = { ImportModule = function() return { GetUiMapIdByAreaId = function(_, area) return ({ [1637] = 1454, [17] = 1413, [12] = 1429 })[area] end } end }
	B2.env.GetRealZoneText = function() return "Orgrimmar" end
	Npc.BATCH = 2
	eq(reads, 0, "nothing is read at login")
	B2.slash("npc")
	check(btext("Reading NPCs..."), "the reading says how far it is")
	eq(#Npc.Find("", {}), 0, "nothing is listed half-read")
	step(1)
	eq(reads, 6, "every NPC is read once, over some frames")
	check(btext("6 of 6 NPCs"), "then they are all listed")
	local function names(text, f)
		local out = {}
		for i, r in ipairs(Npc.Find(text, f or {})) do out[i] = r.e.name end
		table.sort(out)
		return table.concat(out, ", ")
	end
	local function best(text) local r = Npc.Find(text, {}) table.sort(r, function(a, b) return a.score > b.score end) return r[1] and r[1].e.name end
	local function types(id) for _, r in ipairs(Npc.Find("", {})) do if r.e.id == id then return r.e.typeText end end end
	eq(types(10), "Vendor, Repairs, Fishing", "types come from the flags and the title: several at once")
	eq(types(11), "Trainer, Quest giver, Fishing", "a trainer who gives quests")
	eq(types(12), "Rare", "and from the rank"); eq(types(13), "Vendor, Innkeeper", "an innkeeper who sells"); eq(types(14), "Boss", "a boss")
	-- searching
	eq(names("fish"), "Gorak, Lumak", "a word may be in the title or the types")
	eq(names("fish train"), "Lumak", "every word has to match somewhere")
	eq(names("barrens"), "Old Greyfin", "or in the zone")
	eq(best("gorak"), "Gorak", "the exact name beats a name that starts with it")
	eq(names("gorak"), "Gorak, Marshal Gorakson", "both are found")
	eq(names("grysh"), "Innkeeper Gryshka", "part of a name")
	eq(names("grfn"), "Old Greyfin", "letters in order, when nothing plainer fits")
	eq(names("orgimmar"), "Gorak, Innkeeper Gryshka, Lumak", "a misspelt zone is forgiven")
	eq(names("lumek"), "Lumak", "and a misspelt name")
	eq(names("zzzz"), "", "nonsense finds nothing")
	-- filters
	eq(names("", { types = { Vendor = true } }), "Gorak, Innkeeper Gryshka", "a type")
	eq(names("", { types = { Vendor = true, Repairs = true } }), "Gorak", "two types have both to apply")
	eq(names("", { min = 31, max = 40 }), "Innkeeper Gryshka, Lumak", "levels")
	eq(names("", { side = "friendly" }), "Gorak, Innkeeper Gryshka, Lumak", "friendly to me (Horde)")
	eq(names("", { side = "hostile" }), "Marshal Gorakson, Old Greyfin, Scripted Ghost", "and not")
	eq(names("", { side = "noenemy" }), "Gorak, Innkeeper Gryshka, Lumak, Old Greyfin, Scripted Ghost", "the other faction's own left out, neutral ones kept")
	eq(names("", { zoneOnly = true }), "Gorak, Innkeeper Gryshka, Lumak", "this zone only")
	eq(names("", { zone = "The Barrens" }), "Old Greyfin", "a zone by name")
	eq(names("", { located = true }), "Gorak, Innkeeper Gryshka, Lumak, Marshal Gorakson, Old Greyfin", "with a known location")
	-- the rows
	local function nrows()
		local out = {}
		for _, w in ipairs(B2.widgets) do
			if w.ncols and w.shown and w.data then out[#out + 1] = w end
		end
		return out
	end
	eq(#nrows(), 6, "a row each")
	local function rowOf(name) for _, w in ipairs(nrows()) do if w.data.e.name == name then return w end end end
	eq(rowOf("Old Greyfin").data[2], "|cff80c0ffOld Greyfin|r", "a rare is coloured"); eq(rowOf("Old Greyfin").data[5], "22-24", "its levels")
	eq(rowOf("Gorak").data[7], "Orgrimmar", "the zone by name"); check(rowOf("Scripted Ghost").data[7]:find("no known location", 1, true), "or that there is none")
	-- favourites
	click(rowOf("Lumak").star)
	eq(Npc.db.favs[11], true, "a star makes a favourite, saved"); eq(nrows()[1].data.e.name, "Lumak", "which is listed first")
	eq(names("", { types = { Favourites = true } }), "Lumak", "and can be filtered on")
	local function typeButton(part)
		for _, w in ipairs(B2.widgets) do
			if w.kind == "Button" and w.shown and w.type and w.label.text:find(part, 1, true) then return w end
		end
	end
	check(typeButton("Vendor|r |cff8888882"), "the types on the left are counted: " .. tostring(typeButton("Vendor") and typeButton("Vendor").label.text))
	click(typeButton("Vendor"))
	eq(#nrows(), 2, "a click on one filters"); check(typeButton("Repairs|r |cff8888881"), "and the counts follow")
	click(typeButton("Vendor"))
	eq(#nrows(), 6, "and again to undo")
	Npc.search:SetText("fish")
	step(1)
	eq(#nrows(), 2, "typing searches, after a moment"); check(btext("2 of 6 NPCs, best match first"), "and says so")
	Npc.PickZone("@here")
	click(Npc.clear)
	step(1)
	eq(#nrows(), 6, "Clear undoes search and filters"); eq(Npc.db.zoneOnly, nil, "all of them")
	-- the zone list
	eq(Npc.zoneButton.label.text, "Zone: any", "the zone button says any zone")
	click(Npc.zoneButton)
	local zmenu = Npc.zoneButton.menu
	local zrows = zmenu.rows
	eq(zmenu.shown, true, "a click opens the list of zones")
	eq(zrows[1].label.text, "|cffffd100Any zone|r", "any zone first, lit while it is the pick"); eq(zrows[2].label.text, "|cffffffffWhere I am (Orgrimmar)|r |cff8888883|r", "then where I am, with its NPCs counted")
	local function zrow(zone)
		for _, b in ipairs(zrows) do if b.shown and b.entry and b.entry.value == zone then return b end end
	end
	check(zrow("The Barrens") and zrow("The Barrens").label.text:find("The Barrens|r |cff8888881", 1, true), "then the zones by name, counted")
	click(zrow("The Barrens"))
	eq(zmenu.shown, false, "a pick closes the list"); eq(Npc.zoneButton.label.text, "Zone: The Barrens", "and is named on the button")
	eq(#nrows(), 1, "only that zone's NPCs"); eq(nrows()[1].data.e.name, "Old Greyfin", "listed")
	click(Npc.zoneButton)
	click(zrows[2])
	eq(Npc.zoneButton.label.text, "Zone: here (Orgrimmar)", "where I am"); eq(#nrows(), 3, "its NPCs"); eq(Npc.db.zone, nil, "one or the other")
	-- typing in the list narrows it
	click(Npc.zoneButton)
	zmenu.box:SetText("elw")
	check(zrow("Elwynn Forest") and not zrow("The Barrens"), "typing leaves the zones that contain it"); check(zrows[1].shown and zrows[1].entry.text == "Any zone", "under the two that are always there")
	zmenu.box.scripts.OnEnterPressed(zmenu.box)
	eq(Npc.zoneButton.label.text, "Zone: Elwynn Forest", "Enter takes the first that fits"); eq(zmenu.shown, false, "and closes the list")
	click(Npc.zoneButton)
	eq(zmenu.box:GetText(), "", "opened again, the box is empty"); check(zrow("The Barrens"), "and every zone is back")
	click(zrows[1])
	eq(Npc.zoneButton.label.text, "Zone: any", "and any zone again"); eq(#nrows(), 6, "everything")
	-- the side, from a list too
	click(Npc.sideButton)
	local srows = Npc.sideButton.menu.rows
	eq(srows[2].label.text, "|cffffffffSide: hide other faction|r", "the sides to pick from"); eq(Npc.sideButton.menu.box, nil, "no box to type in for four entries")
	click(srows[2])
	eq(Npc.db.side, "noenemy", "a pick sets it"); eq(#nrows(), 5, "the other faction's NPC is out"); eq(Npc.sideButton.label.text, "Side: hide other faction", "named on the button")
	click(Npc.sideButton)
	click(srows[1])
	eq(Npc.db.side, nil, "and any side again")
	-- the waypoint: the game's own pin, the nearest spot on my map
	rowOf("Gorak").scripts.OnMouseUp(rowOf("Gorak"))
	eq(pin[1], 1454, "the pin is on the zone's map"); eq(pin[2], 0.2, "at the spot nearest to me"); eq(pin[3], 0.3, "of the two")
	check(B2.printed[#B2.printed]:find("Waypoint: Gorak, Orgrimmar 20.0, 30.0", 1, true), "and chat says where: " .. B2.printed[#B2.printed])
	-- with TomTom, that is used
	local tom
	B2.env.TomTom = { AddWaypoint = function(_, map, x, y, opts) tom = { map, x, y, opts.title } end }
	rowOf("Old Greyfin").scripts.OnMouseUp(rowOf("Old Greyfin"))
	eq(tom[1], 1413, "TomTom gets the map"); eq(tom[2], 0.4, "the place as a fraction"); eq(tom[4], "Old Greyfin", "and the name")
	tom = nil
	rowOf("Scripted Ghost").scripts.OnMouseUp(rowOf("Scripted Ghost"))
	eq(tom, nil, "no waypoint without a location"); check(B2.printed[#B2.printed]:find("Scripted Ghost: no known location", 1, true), "but a word about it")
	eq(Npc.Spot(rowOf("Marshal Gorakson").data.e).map, 1429, "of two zones, one that has a map is taken")
	-- the tooltip
	local function tip(name)
		B2.env.GameTooltip.lines = {}
		rowOf(name).scripts.OnEnter(rowOf(name))
		return table.concat(B2.env.GameTooltip.lines, " | ")
	end
	local t = tip("Gorak")
	check(t:find("<Fishing Supplies>", 1, true) and t:find("Level 30, Horde", 1, true) and t:find("Vendor, Repairs, Fishing", 1, true), "the tooltip says what it is: " .. t)
	check(t:find("Orgrimmar: 54.2, 68.1; 20.0, 30.0", 1, true) and t:find("Seen in 2 spots", 1, true) and t:find("Starts 1 quest, ends 0.", 1, true), "where, and its quests")
	t = tip("Old Greyfin")
	check(t:find("Rare", 1, true) and t:find("Only one known spot.", 1, true) and t:find("Patrols", 1, true), "a rare that patrols: " .. t)
	check(tip("Scripted Ghost"):find("No known location", 1, true), "and one that is nowhere")
	eq(B2.DT.modules.npc.hello, nil, "the module has nothing to say to the guild")

	-- Quests: read from QuestieDB the same way; what is open to me, and the chains
	local Quest = B2.DT.Quest
	local QUESTS = {
		[100] = { name = "Fish for Gorak", requiredLevel = 5, questLevel = 8, zoneOrSort = 1637, startedBy = { { 10 } } },
		[101] = { name = "More Fish", requiredLevel = 8, questLevel = 10, zoneOrSort = 1637, preQuestSingle = { 100 }, startedBy = { { 10 } } },
		[102] = { name = "The Big One", requiredLevel = 10, questLevel = 12, zoneOrSort = 17, preQuestSingle = { 101 }, requiredSkill = { 356, 50 }, startedBy = { { 11 } } },
		[103] = { name = "Side Catch", requiredLevel = 1, questLevel = 10, zoneOrSort = 17, preQuestGroup = { 100, 104 } },
		[104] = { name = "Alliance Errand", requiredLevel = 1, questLevel = 10, zoneOrSort = 12, requiredRaces = 1 },
		[105] = { name = "Deadmines Run", requiredLevel = 15, questLevel = 20, zoneOrSort = 12 },
		[106] = { name = "Mage Trial", requiredLevel = 1, questLevel = 10, zoneOrSort = -161, requiredClasses = 128 },
		[107] = { name = "Daily Bread", requiredLevel = 1, questLevel = 5, zoneOrSort = 1637, questFlags = 4096 },
	}
	local qreads = 0
	B2.env.LibQuestieDB.Quest = {
		GetAllIds = function() return { 100, 101, 102, 103, 104, 105, 106, 107 } end,
		GetAll = function(id, keys)
			qreads = qreads + 1
			local out = {}
			for i, key in ipairs(keys) do out[i] = QUESTS[id][key] end
			return out
		end,
	}
	local qdone, qon, fishing = {}, {}, 20
	B2.env.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return qdone[id] or false end, IsOnQuest = function(id) return qon[id] or false end }
	B2.env.GetQuestTagInfo = function(id) if id == 105 then return 81, "Dungeon" end end
	B2.env.UnitRace = function() return "Orc", "Orc", 2 end
	B2.env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	B2.env.GetNumSkillLines = function() return 1 end
	B2.env.GetSkillLineInfo = function() return "Fishing", false, false, fishing end
	Quest.BATCH = 3
	B2.slash("quest")
	eq(qreads, 0, "no quest is read before the tab is looked at... and then a few per frame")
	step(1)
	eq(qreads, 8, "every quest is read once")
	local function qrows()
		local out = {}
		for _, w in ipairs(B2.widgets) do
			if w.qcols and w.shown and w.data then out[#out + 1] = w end
		end
		return out
	end
	local function qnames()
		local out = {}
		for i, w in ipairs(qrows()) do out[i] = w.data.e.name end
		table.sort(out)
		return table.concat(out, ", ")
	end
	local function q(name) for _, w in ipairs(qrows()) do if w.data.e.name == name then return w.data end end end
	local function strip(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	eq(qnames(), "Daily Bread, Deadmines Run, Fish for Gorak, More Fish, Side Catch, The Big One", "the other side's and other classes' quests are left out to begin with")
	check(btext("6 of 8 quests"), "with a count")
	-- nested: each quest under the one that opens it
	local function nest()
		local out = {}
		for i, w in ipairs(qrows()) do out[i] = w.data.depth .. " " .. w.data.e.name end
		return table.concat(out, " / ")
	end
	eq(nest(), "0 Daily Bread / 0 Fish for Gorak / 1 More Fish / 2 The Big One / 1 Side Catch / 0 Deadmines Run",
		"the list is nested: each quest under the one that opens it, chains by the level of their first step")
	eq(strip(q("The Big One")[1]), "        > The Big One", "indented by how deep it stands"); eq(strip(q("Fish for Gorak")[1]), "Fish for Gorak", "a first step at the edge")
	eq(strip(q("Fish for Gorak")[5]), "open to you", "a quest I can take"); eq(strip(q("More Fish")[5]), "after: Fish for Gorak", "one that waits for another")
	eq(strip(q("Deadmines Run")[5]), "needs level 15", "one I am too low for"); eq(strip(q("Side Catch")[5]), "after: Fish for Gorak", "one that needs two others")
	eq(q("Fish for Gorak")[3], "Open world, Chain start", "labels: where a chain starts"); eq(q("More Fish")[3], "Open world, In chain", "and what is part of one")
	eq(q("Deadmines Run")[3], "Dungeon", "the game's own tag: a dungeon quest, and so not open world"); eq(q("Daily Bread")[3], "Open world, Daily", "a daily")
	;(function() -- what a quest asks: QuestieDB's sentence, in the window and on the tooltip
		local e
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == "Daily Bread" then e = r.e end end
		local lib = B2.env.LibQuestieDB
		local was = lib.Quest.Get
		lib.Quest.Get = function(id, key)
			if key == "objectivesText" and id == e.id then return { "Bring 5 loaves to the baker.", "" } end
			return was and was(id, key)
		end
		eq(Quest.Asks(e), "Bring 5 loaves to the baker.", "what a quest asks, in a sentence")
		Quest.ShowChain(e)
		local text = Quest.chain.rewards.text
		check(text:find("To do:|r  Bring 5 loaves to the baker.", 1, true), "the window says what to do")
		check(text:find("To do:", 1, true) < text:find("Rewards of", 1, true), "above what it gives")
		Quest.Tooltip(Quest.chain, e)
		local tip = table.concat(B2.env.GameTooltip.lines or {}, "|")
		check(tip:find("Bring 5 loaves to the baker.", 1, true), "and so does the tooltip: " .. tip)
		Quest.chain:Hide()
		lib.Quest.Get = was
	end)()
	;(function() -- shift-click in the quest window: the link to read up on that quest
		local e, shown
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == "Daily Bread" then e = r.e end end
		Quest.ShowChain(e)
		local env = B2.env
		local wasShift, wasPopup = env.IsShiftKeyDown, env.StaticPopup_Show
		env.IsShiftKeyDown = function() return true end
		env.StaticPopup_Show = function(which, title, _, url) shown = { which, title, url } end
		click(Quest.chain.rows[1])
		check(shown and shown[1] == "DAWNTOOLS_LINK" and shown[3] == "https://www.wowhead.com/forever/quest=" .. Quest.chain.rows[1].data.e.id,
			"a shift-click on a quest of the chain shows its link")
		env.IsShiftKeyDown, env.StaticPopup_Show = wasShift, wasPopup
		Quest.chain:Hide()
	end)()
	;(function() -- an instance quest given outside: found under its instance as under its zone
		local e
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == "Daily Bread" then e = r.e end end
		e.instance = "Krol'dok Stronghold" -- (as OneForAll's lists, or the quest's own words, would have it)
		local got = {}
		for _, r in ipairs(Quest.Find("", { zone = "Krol'dok Stronghold" })) do got[#got + 1] = r.e.name end
		eq(table.concat(got, ","), "Daily Bread", "a zone picked finds the quests of the instance of that name")
		got = {}
		for _, r in ipairs(Quest.Find("", { zone = "Orgrimmar" })) do got[r.e.name] = true end
		eq(got["Daily Bread"], true, "and it stays under the zone it is given in")
		click(Quest.zoneButton)
		local listed
		for _, b in ipairs(Quest.zoneButton.menu.rows) do if b.shown and b.entry and b.entry.value == "Krol'dok Stronghold" then listed = b end end
		check(listed, "the zone list names the instance too")
		click(Quest.zoneButton)
		e.instance = nil
	end)()
	;(function() -- a quest filed under no zone (Forever's new ones): placed by what it asks, else by where it is given
		local e = { zone = 0, zoneName = "", types = {} }
		Quest.Place(e, { "Recover the Tome of Twilight from Krol'dok Stronghold." }, 1637)
		eq(e.instance, "Krol'dok Stronghold", "one that names an instance is that instance's"); eq(e.zone, 1637, "and of the zone it is given in besides"); eq(e.zoneName, "Orgrimmar", "by its name")
		e = { zone = 0, zoneName = "", types = {} }
		Quest.Place(e, { "Bring 4 Thick Leather and 12 Iron Bar to Kreza Darkthorn." }, 1637)
		eq(e.zone, 1637, "one that names none is of the zone it is given in"); eq(e.zoneName, "Orgrimmar", "by its name"); eq(e.instance, nil, "and of no instance")
		e = { zone = 0, zoneName = "", types = {} }
		Quest.Place(e, { "Kill the boss in The Hall of Thanes." }, nil)
		eq(e.instance, "The Hall of Thanes", "the longest name that fits is taken")
		eq(Quest.Canon("Hall of Thanes"), "The Hall of Thanes", "an instance goes by one name, with its The"); eq(Quest.Canon("Dire Maul: East"), "Dire Maul", "a wing under its dungeon")
		eq(Quest.Canon("Upper Blackrock Spire"), "Blackrock Spire", "an upper half too"); eq(Quest.Canon("Some New Hold"), "Some New Hold", "an unknown name stays")
		e = { zone = 0, zoneName = "", types = {} }
		Quest.Place(e, nil, nil)
		eq(e.zoneName, "", "nothing known: it stays without a zone")
	end)()
	eq(q("Fish for Gorak")[4], "Orgrimmar", "the zone by name")
	-- filters
	Quest.ticks.mine.checked = false
	click(Quest.ticks.mine)
	eq(#qrows(), 8, "Mine only off: everything"); eq(strip(q("Alliance Errand")[5]), "other race or side", "and why it is not for me")
	eq(strip(q("Mage Trial")[5]), "other class", "a class quest of another class"); eq(q("Mage Trial")[3], "Class", "labelled"); eq(q("Mage Trial")[4], "Mage", "filed under its class")
	Quest.ticks.mine.checked = true
	click(Quest.ticks.mine)
	Quest.ticks.obtainable.checked = true
	click(Quest.ticks.obtainable)
	eq(qnames(), "Daily Bread, Fish for Gorak", "Can take now: only what is open to me")
	Quest.ticks.obtainable.checked = false
	click(Quest.ticks.obtainable)
	qdone[100] = true
	B2.fire("QUEST_TURNED_IN")
	step(1)
	eq(qnames(), "Daily Bread, Deadmines Run, More Fish, Side Catch, The Big One", "a quest handed in drops out")
	eq(strip(q("More Fish")[5]), "open to you", "and the next of its chain opens"); eq(strip(q("Side Catch")[5]), "after: Alliance Errand", "the other still waits for its second")
	eq(nest(), "0 Daily Bread / 0 More Fish / 1 The Big One / 0 Side Catch / 0 Deadmines Run", "the done step is squeezed out: the chain now begins at its first open step")
	click(Quest.heads[2])
	eq(nest(), "0 Daily Bread / 0 More Fish / 0 Side Catch / 0 The Big One / 0 Deadmines Run", "a click on a header sorts the list flat")
	check(btext("sorted flat"), "and says so")
	click(Quest.clear)
	step(1)
	eq(nest(), "0 Daily Bread / 0 More Fish / 1 The Big One / 0 Side Catch / 0 Deadmines Run", "Clear nests it again")
	Quest.ticks.nested.checked = false
	click(Quest.ticks.nested)
	eq(nest(), "0 Daily Bread / 0 More Fish / 0 Side Catch / 0 The Big One / 0 Deadmines Run", "Nested off: flat, by level")
	Quest.ticks.nested.checked = true
	click(Quest.ticks.nested)
	Quest.ticks.hideDone.checked = false
	click(Quest.ticks.hideDone)
	eq(strip(q("Fish for Gorak")[5]), "done", "Hide done off: it is listed as done")
	eq(nest(), "0 Daily Bread / 0 Fish for Gorak / 1 More Fish / 2 The Big One / 1 Side Catch / 0 Deadmines Run", "and has its place at the head of the chain again")
	qdone[101] = true
	B2.fire("QUEST_TURNED_IN")
	step(1)
	eq(strip(q("The Big One")[5]), "needs Fishing 50", "a profession not high enough")
	fishing = 60
	B2.fire("QUEST_ACCEPTED")
	step(1)
	eq(strip(q("The Big One")[5]), "open to you", "high enough")
	qon[102] = true
	B2.fire("QUEST_ACCEPTED")
	step(1)
	eq(strip(q("The Big One")[5]), "in your log", "a quest I have")
	Quest.ticks.notLog.checked = true
	click(Quest.ticks.notLog)
	check(not q("The Big One") and q("Side Catch"), "Not in log: what I already carry is left out")
	Quest.ticks.notLog.checked = false
	click(Quest.ticks.notLog)
	-- the level, coloured by how hard the quest is for me (level 10)
	eq(q("The Big One")[2], "|cffffff0012|r", "about my level: yellow"); eq(q("Deadmines Run")[2], "|cffff202020|r", "far above: red")
	eq(q("Daily Bread")[2], "|cff40c0405|r", "below: green")
	B2.env.GetQuestDifficultyColor = function() return { r = 0.5, g = 0.5, b = 0.5 } end
	Quest.Refresh()
	eq(q("Daily Bread")[2], "|cff7f7f7f5|r", "the game's own colour where it gives one")
	B2.env.GetQuestDifficultyColor = nil
	Quest.Refresh()
	-- searching, as on the NPC tab
	Quest.search:SetText("barrens")
	step(1)
	eq(qnames(), "Side Catch, The Big One", "by zone")
	Quest.search:SetText("dungon")
	step(1)
	eq(qnames(), "Deadmines Run", "by a label, misspelt")
	click(Quest.clear)
	step(1)
	eq(#qrows(), 4, "Clear: the filters as they began (two are done by now)")
	-- under a ticked Dungeon: its instances by name, green when every quest of one is done
	local function qside(part)
		for _, w in ipairs(B2.widgets) do
			if w.kind == "Button" and w.shown and (w.qtype or w.sub) and w.label and w.label.text:find(part, 1, true) then return w end
		end
	end
	check(qside("Dungeon") and not qside("Elwynn Forest"), "no instances listed before Dungeon is ticked")
	click(qside("Dungeon"))
	eq(qnames(), "Deadmines Run", "Dungeon ticked: the dungeon quests")
	eq(qside("Elwynn Forest").label.text, "    |cffffffffElwynn Forest|r |cff8888880/1|r", "and under it each instance, with how many of its quests are done")
	click(qside("Elwynn Forest"))
	eq(Quest.db.sub.Dungeon, "Elwynn Forest", "a click picks one"); eq(qnames(), "Deadmines Run", "its quests"); eq(qside("Elwynn Forest").sel.shown, true, "and it is lit")
	qdone[105] = true
	B2.fire("QUEST_TURNED_IN")
	step(1)
	eq(qside("Elwynn Forest").label.text, "    |cff40ff40Elwynn Forest|r |cff40a0401/1|r", "all of its quests done: green"); eq(#qrows(), 0, "and nothing left to list there")
	click(qside("Elwynn Forest"))
	eq(Quest.db.sub.Dungeon, nil, "clicked again: every dungeon")
	click(qside("Elwynn Forest"))
	click(qside("Dungeon"))
	eq(Quest.db.sub.Dungeon, nil, "unticking Dungeon forgets the instance"); check(not qside("Elwynn Forest"), "and the instances are gone from the list")
	qdone[105] = nil
	B2.fire("QUEST_TURNED_IN")
	step(1)
	-- the zone list, as on the NPC tab
	click(Quest.zoneButton)
	local qz = Quest.zoneButton.menu
	qz.box:SetText("barr")
	qz.box.scripts.OnEnterPressed(qz.box)
	eq(Quest.zoneButton.label.text, "Zone: The Barrens", "a zone typed and taken"); eq(qnames(), "Side Catch, The Big One", "its quests")
	click(Quest.zoneButton)
	click(qz.rows[2])
	eq(Quest.zoneButton.label.text, "Zone: here (Orgrimmar)", "where I am"); eq(qnames(), "Daily Bread", "the quests of the zone I stand in")
	click(Quest.clear)
	step(1)
	eq(Quest.zoneButton.label.text, "Zone: any", "Clear: any zone")
	;(function() -- a zone whose quests are all done is green in the list
		local function barrens()
			click(Quest.zoneButton)
			local text
			for _, b in ipairs(qz.rows) do if b.shown and b.entry and b.entry.value == "The Barrens" then text = b.label.text end end
			click(Quest.zoneButton)
			return text or "?"
		end
		check(barrens():find("|cffffffffThe Barrens", 1, true), "a zone with quests left is white in the list")
		local ids = {}
		for _, r in ipairs(Quest.Find("", { zone = "The Barrens" })) do if not qdone[r.e.id] then ids[#ids + 1] = r.e.id end end
		for _, id in ipairs(ids) do qdone[id] = true end
		B2.fire("QUEST_TURNED_IN"); step(1)
		check(barrens():find("|cff40a040The Barrens", 1, true), "green once all of them are done: " .. barrens())
		for _, id in ipairs(ids) do qdone[id] = nil end
		B2.fire("QUEST_TURNED_IN"); step(1)
	end)()
	-- the chain
	local function chainText(name)
		local e
		for _, r in ipairs(Quest.Find("", {})) do if r.e.name == name then e = r.e end end
		local out = {}
		for i, d in ipairs(Quest.Chain(e)) do out[i] = ("%d %s%s"):format(d.depth, d.e.name, d.again and " again" or "") end
		return table.concat(out, " / "), e
	end
	eq(chainText("The Big One"), "0 Fish for Gorak / 1 More Fish / 2 The Big One / 1 Side Catch", "a chain from where it starts, each step under the one before")
	eq(chainText("Side Catch"), "0 Fish for Gorak / 1 More Fish / 2 The Big One / 1 Side Catch / 0 Alliance Errand / 1 Side Catch again",
		"a quest that needs two stands under both, named once")
	eq(chainText("Daily Bread"), "0 Daily Bread", "a quest on its own is its own chain")
	q("The Big One") -- (listed)
	for _, w in ipairs(qrows()) do if w.data.e.name == "The Big One" then w.scripts.OnMouseUp(w) end end
	local chain = Quest.chain
	eq(chain.shown, true, "a click on a quest opens its chain"); eq(chain.title.text, "Chain of: The Big One", "named")
	eq(strip(chain.rows[1].text.text), "[8] Fish for Gorak  Gorak", "the first step, with who gives it")
	eq(strip(chain.rows[3].text.text), "        > [12] The Big One  Lumak", "a later one indented under it")
	eq(chain.rows[3].here.shown, true, "the quest asked about is marked"); eq(chain.rows[1].here.shown, false, "the others not")
	eq(chain.rows[5].shown, false, "and no more rows than quests")
	tom = nil
	click(chain.rows[1])
	eq(tom[1], 1454, "a click on a step: a waypoint to who gives it"); eq(tom[4], "Gorak (Fish for Gorak)", "named after both")
	local printed = #B2.printed
	click(chain.rows[4])
	check(B2.printed[#B2.printed]:find("Side Catch: started by no NPC", 1, true) and #B2.printed > printed, "one that nobody gives says so")
	eq(B2.DT.modules.quest.hello, nil, "the module has nothing to say to the guild")

	-- Items: read from QuestieDB too; what only the game knows of an item is asked once and kept
	do
		local Item = B2.DT.Item
		local ITEMDB = {
			[400] = { name = "Sword", requiredLevel = 20, itemLevel = 25, class = 2, subClass = 7, npcDrops = { 12 }, questRewards = { 102 } },
			[500] = { name = "Bid Only Axe", requiredLevel = 1, itemLevel = 5, class = 2, subClass = 0, vendors = { 10 } },
			[100] = { name = "Copper Bar", requiredLevel = 0, itemLevel = 10, class = 7, subClass = 7, objectDrops = { 77 } },
			[820] = { name = "Minor Potion", requiredLevel = 5, itemLevel = 5, class = 0, subClass = 1, itemDrops = { 600 }, startQuest = 107 },
			[600] = { name = "Grey Fang", requiredLevel = 0, itemLevel = 1, class = 15, subClass = 0 },
			[830] = { name = "Plans: Iron Thing", requiredLevel = 0, itemLevel = 25, class = 9, subClass = 4, vendors = { 10 } },
		}
		local ireads = 0
		B2.env.LibQuestieDB.Item = {
			GetAllIds = function() return { 100, 400, 500, 600, 820, 830 } end,
			GetAll = function(id, keys)
				ireads = ireads + 1
				local out = {}
				for i, key in ipairs(keys) do out[i] = ITEMDB[id][key] end
				return out
			end,
			Get = function(id, key) return ITEMDB[id] and ITEMDB[id][key] end,
		}
		B2.env.LibQuestieDB.Object = { Get = function(id, key) return id == 77 and ({ name = "Copper Vein", zoneID = 17 })[key] or nil end }
		B2.env.LibQuestieDB.Quest.Get = function(id, key) return QUESTS[id] and QUESTS[id][key] end
		local recipeKnown = false
		local STATS = { [400] = { ITEM_MOD_STAMINA_SHORT = 11, ITEM_MOD_STRENGTH_SHORT = 4 }, [500] = { ITEM_MOD_STAMINA_SHORT = 3 } }
		B2.env.GetItemStats = function(link) return STATS[tonumber(link:match("item:(%d+)"))] or {} end
		B2.env.C_TooltipInfo = { GetItemByID = function(id)
			local lines = { { leftText = ITEMDB[id].name } }
			if id == 400 then lines[#lines + 1] = { leftText = "Equip: Improves your chance to hit by 1%." } end
			if id == 830 then lines[#lines + 1] = { leftText = "Requires Blacksmithing (125)" } end
			if id == 830 and recipeKnown then lines[#lines + 1] = { leftText = "Already known" } end
			return { lines = lines }
		end }
		B2.env.AtlasLoot = { Data = { Profession = { GetCraftSpellForCreatedItem = function(id) return id == 100 and 2657 or nil end } } }
		ITEMS[400].slot, ITEMS[500].slot = "INVTYPE_WEAPON", "INVTYPE_WEAPON"
		B2.uncached = { [400] = true }
		Item.BATCH = 2
		B2.slash("item")
		check(btext("Reading items..."), "the reading says how far it is")
		step(1)
		eq(ireads, 6, "every item is read once"); check(btext("6 of 6 items"), "then they are all listed")
		local function inames(text, f)
			local found, state = Item.Find(text, f or {})
			local out = {}
			for i, r in ipairs(found) do out[i] = r.e.name end
			table.sort(out)
			return table.concat(out, ", "), state
		end
		eq(inames("sword"), "Sword", "found by name"); eq(inames("swrd"), "Sword", "letters in order will do")
		eq(inames("vendor"), "Bid Only Axe, Plans: Iron Thing", "or by where it comes from")
		eq(inames("", { source = "Vendor" }), "Bid Only Axe, Plans: Iron Thing", "the source filter"); eq(inames("", { source = "Crafted" }), "Copper Bar", "crafted, where AtlasLoot says so")
		eq(inames("", { source = "Chest" }), "Copper Bar", "found in an object"); eq(inames("", { source = "Container" }), "Minor Potion", "or inside another item")
		eq(inames("", { min = 5, max = 20 }), "Minor Potion, Sword", "required level")
		eq(inames("", { class = 2 }), "Bid Only Axe, Sword", "a kind of item"); eq(inames("", { class = 2, group = "1h" }), "Bid Only Axe, Sword", "and its group")
		eq(inames("", { class = 2, group = "2h" }), "", "another group: none")
		-- the Stats box
		local want = Item.ParseStats("sta>11 Int>=5 hit armour<9")
		eq(#want, 4, "the Stats box takes several wishes"); eq(want[1].stat .. want[1].op .. want[1].n, "sta>11", "a stat, a sign, a number")
		eq(want[2].stat .. want[2].op, "int>=", "whatever the case"); eq(want[3].word, "hit", "a word alone"); eq(want[4].stat, "armor", "other spellings")
		-- what only the game knows: asked once, then kept
		Item.db.known[400], B2.uncached[400] = nil, true -- (the rows on screen had it learned already: as if never seen)
		local names, state = inames("", { stats = "sta>10" })
		eq(names, "", "the sword is not known to the game yet: not listed for now"); eq(state.unknown, 1, "it is being asked for"); eq(state.of, 6, "of the six candidates")
		eq(Item.db.known[500].s.sta, 3, "the others are known at once, with their stats")
		step(2)
		eq(inames("", { stats = "sta>10" }), "Sword", "it has come: stamina above 10")
		local known = Item.db.known[400]
		eq(known.q, 2, "kept for good: its quality"); eq(known.e, "INVTYPE_WEAPON", "where it is worn"); eq(known.s.sta, 11, "its stats"); eq(known.s.str, 4, "all of them")
		check(known.x:find("chance to hit by 1%%"), "and its Equip lines")
		eq(inames("", { stats = "hit" }), "Sword", "a word alone: has it, here in an Equip line"); eq(inames("", { stats = "hit>=1" }), "Sword", "with the number read from that line")
		eq(inames("", { stats = "hit>1" }), "", "which is no more than it is"); eq(inames("", { stats = "sta<5" }), "Bid Only Axe", "less than")
		eq(inames("", { stats = "sta str>3" }), "Sword", "several: all must hold"); eq(inames("", { stats = "int" }), "", "a stat nothing has")
		eq(inames("", { quality = 2 }), "Bid Only Axe, Sword", "quality, which only the game knows"); eq(inames("", { quality = 3 }), "", "nothing rare")
		eq(Item.StatText(known), "11 sta, 4 str", "its stats in a line")
		-- usable: also the skill an item asks for, and whether I know it already (recipes)
		local smithing = 100
		B2.env.GetNumSkillLines = function() return 1 end
		B2.env.GetSkillLineInfo = function() return "Blacksmithing", false, false, smithing end
		B2.env.C_Item.GetItemSubClassInfo = function() return "Blacksmithing" end
		eq(inames("plans", { usable = true }), "", "a recipe that asks for Blacksmithing 125, at 100: not usable")
		eq(Item.db.known[830].rs, "Blacksmithing", "what it asks for is kept with the item's facts"); eq(Item.db.known[830].rn, 125, "and how high")
		smithing = 125
		eq(inames("plans", { usable = true }), "Plans: Iron Thing", "at 125: usable")
		recipeKnown = true
		B2.fire("NEW_RECIPE_LEARNED")
		eq(inames("plans", { usable = true }), "", "once I know it, it is of no use to me: not listed")
		eq(inames("plans", {}), "Plans: Iron Thing", "without Usable it is listed all the same")
		recipeKnown = false
		B2.fire("NEW_RECIPE_LEARNED")
		B2.env.GetSkillLineInfo = function() return "Tailoring", false, false, 300 end
		eq(inames("plans", { usable = true }), "", "without the profession at all: not usable")
		B2.env.GetNumSkillLines, B2.env.GetSkillLineInfo, B2.env.C_Item.GetItemSubClassInfo = nil, nil, nil
		Item.db.known[500].v = 1
		eq(inames("", { quality = 2 }), "Bid Only Axe, Sword", "facts kept in an older shape are learned anew, not trusted"); eq(Item.db.known[500].v, 2, "and kept in the new one")
		-- an item the game never delivers is asked for three times and then left alone: no endless learning
		;(function() -- (a function of its own: the test file is at the limit of local variables)
			local asks, real = 0, B2.env.C_Item.RequestLoadItemDataByID
			B2.env.C_Item.RequestLoadItemDataByID = function(id) if id == 400 then asks = asks + 1 else real(id) end end
			Item.db.known[400], B2.uncached[400] = nil, true
			local st
			for _ = 1, 6 do
				_, st = inames("", { quality = 1 })
				step(9) -- (no answer comes: it is not waited for for ever)
			end
			check(asks <= 3, "asked for no more than three times: " .. asks); eq(st.unknown, 0, "then it is no longer counted as being learned")
			eq(inames("", { quality = 1 }):find("Sword"), nil, "and is simply not listed under a filter that needs it")
			B2.env.C_Item.RequestLoadItemDataByID, B2.uncached[400] = real, nil
		end)()
		-- nothing empty goes to the saved file, and it reads back the same
		B2.fire("PLAYER_LOGOUT")
		eq(Item.db.known[600].s, nil, "an item with nothing on it: no empty table written"); eq(Item.db.known[600].x, nil, "nor an empty text")
		eq(inames("", { stats = "sta<5" }), "Bid Only Axe", "and it all reads back as before")
		-- more unknown items than can be asked for without a word
		local had = Item.db.known
		Item.db.known = {}
		Item.CAP = 2
		names, state = inames("", { quality = 1 })
		eq(state.capped, true, "too many unknown items: none is asked for"); eq(names, "", "and none listed"); eq(next(Item.db.known), nil, "nothing learned")
		Item.force = true
		names, state = inames("", { quality = 1 })
		eq(state.capped, false, "'Learn them anyway': it goes ahead"); check(next(Item.db.known) ~= nil, "and learns")
		Item.force, Item.CAP, Item.db.known = nil, 3000, had
		-- the rows
		local function irows()
			local out = {}
			for _, w in ipairs(B2.widgets) do
				if w.icols and w.shown and w.data then out[#out + 1] = w end
			end
			return out
		end
		Item.Refresh()
		eq(#irows(), 6, "a row each")
		local function irow(name) for _, w in ipairs(irows()) do if w.data.e.name == name then return w end end end
		eq(irow("Sword").icols[1].text, "|cff1eff00Sword|r", "in its quality colour, once known"); eq(irow("Sword").icols[2].text, "20", "its level")
		eq(irow("Sword").icols[5].text, "INVTYPE_WEAPON", "where it is worn"); eq(irow("Sword").icols[6].text, "Drop, Quest reward", "and where it comes from")
		Item.statBox:SetText("sta>10")
		step(1)
		eq(#irows(), 1, "typing in the Stats box filters, after a moment"); eq(irows()[1].data.e.name, "Sword", "the sword")
		click(Item.clear)
		step(1)
		eq(#irows(), 6, "Clear: all of them again")
		-- where it comes from
		local function lines(name)
			local out = {}
			for i, d in ipairs(Item.Sources(irow(name).data.e)) do out[i] = d.head or d.text end
			return (table.concat(out, " / "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
		end
		eq(lines("Sword"), "Dropped by (1) / Old Greyfin level 22-24  The Barrens / Reward of the quest (1) / The Big One", "who drops it, and which quest gives it")
		eq(lines("Bid Only Axe"), "Sold by (1) / Gorak level 30  Orgrimmar", "who sells it")
		eq(lines("Copper Bar"), "Found in (1) / Copper Vein  The Barrens / Made with a profession (a recipe makes it)", "what it is found in, and that it is made")
		eq(lines("Minor Potion"), "Inside (1) / Grey Fang / Starts the quest (1) / Daily Bread", "what it is inside of, and the quest it starts")
		check(lines("Grey Fang"):find("No source known", 1, true), "or that nothing is known")
		irow("Sword").scripts.OnMouseUp(irow("Sword"))
		local info = Item.info
		eq(info.shown, true, "a click on an item opens where it comes from"); eq(info.title.text, "|cff1eff00Sword|r", "headed by the item")
		check(info.sub.text:find("11 sta, 4 str", 1, true), "with its stats")
		tom = nil
		click(info.rows[2])
		eq(tom[4], "Old Greyfin", "a click on who drops it: a waypoint to it")
		Quest.chain.shown = false
		click(info.rows[4])
		eq(Quest.chain.shown, true, "a click on the quest: its chain")
		-- what a quest gives: experience from QuestieDB's table, money from the game, items from the Items reading
		;(function() -- (a function of its own: the main chunk has no room for more locals)
		B2.env.LibQuestieDB.Support = { Get = function(name) return name == "QuestXP" and { db = { [102] = { 20, 390 } } } or nil end }
		B2.env.GetQuestLogRewardMoney = function(id) return id == 102 and 1200 or 0 end
		local r = Quest.Rewards({ id = 102, name = "Q102", level = 20 })
		eq(r.xp, 390, "a quest's experience"); eq(r.money, 1200, "its money, where the game tells it"); eq(#r.items, 1, "its item")
		eq(r.items[1].name, "Sword", "by name"); eq(r.items[1].sell, ITEMS[400][4], "with what a vendor pays for it")
		local text = table.concat(Quest.RewardLines({ id = 102, name = "Q102", level = 20 }), "|")
		check(text:find("390 XP", 1, true) and text:find("Sword", 1, true) and text:find("12s", 1, true), "all of it in the chain window's lines: " .. text)
		check(Quest.chain.rewards.text:find("Rewards of", 1, true), "which the window shows")
		local none = Quest.Rewards({ id = 999999, name = "Nothing", level = 1 })
		eq(none.xp, nil, "a quest nothing is known of: no experience"); eq(#none.items, 0, "no items"); eq(none.money, nil, "no money")
		B2.env.GetQuestLogRewardMoney = nil
		-- a quest giver shows quest 103: what the window says is kept, and believed from then on
		local e = B2.env
		e.GetQuestID = function() return 103 end
		e.GetRewardMoney = function() return 250 end
		e.GetRewardXP = function() return 880 end
		e.GetNumQuestRewards = function() return 1 end
		e.GetNumQuestChoices = function() return 2 end
		e.GetQuestItemInfo = function(kind, i) return "x", 1, kind == "reward" and 5 or 1, 1, true, kind == "reward" and 100 or (i == 1 and 400 or nil) end
		e.GetQuestItemLink = function(kind, i) return kind == "choice" and i == 2 and "|cffffffff|Hitem:500::::|h[Bid Only Axe]|h|r" or nil end
		B2.fire("QUEST_DETAIL")
		local seen = B2.DT.modules.quest.db.seen[103]
		eq(seen.m, 250, "the money a quest giver showed is kept"); eq(seen.x, 880, "the experience"); eq(seen.l, 10, "at my level")
		eq(seen.r[1][1], 100, "what is given"); eq(seen.r[1][2], 5, "how many"); eq(seen.c[1][1], 400, "what there is to choose from"); eq(seen.c[2][1], 500, "told by its link where the number is not given")
		local got = Quest.Rewards({ id = 103, name = "Q103", level = 10 })
		eq(got.seen, true, "a quest that was seen"); eq(got.money, 250, "its money without being in the log"); eq(#got.items, 3, "its items")
		eq(got.items[1].choose, false, "what is given first"); eq(got.items[1].count, 5, "with the count"); eq(got.items[2].choose, true, "then the choices")
		check(table.concat(Quest.RewardLines({ id = 103, name = "Q103", level = 10 }), "|"):find("(choose one)", 1, true), "marked as a choice in the window")
		-- what ships with the addon counts the same, for a quest I never saw
		B2.DT.QuestRewards[104] = { m = 0, x = 0, l = 5, r = { { 600, 1 } }, c = {} }
		local shipped = Quest.Rewards({ id = 104, name = "Q104", level = 5 })
		eq(shipped.seen, true, "a quest in the shipped table is known"); eq(shipped.money, 0, "no money is an answer too"); eq(shipped.items[1].id, 600, "its item")
		B2.DT.QuestRewards[104] = nil
		e.GetQuestID = nil
		end)()
		eq(B2.DT.modules.item.hello, nil, "the module has nothing to say to the guild")
		ITEMS[400].slot, ITEMS[500].slot = nil, nil
	end

	-- reading in the background: a few seconds after login, a little per frame, not in combat
	do
		local Bea = NewClient("Bea")
		Bea.env.LibQuestieDB, Bea.env.C_Map, Bea.env.GetRealZoneText = B2.env.LibQuestieDB, B2.env.C_Map, B2.env.GetRealZoneText
		local BN, BQ = Bea.DT.Npc, Bea.DT.Quest
		BN.BATCH, BQ.BATCH = 2, 3
		reads, qreads = 0, 0
		eq(Bea.DT.db.settings.background, true, "background reading is on unless switched off")
		step(4)
		eq(reads + qreads, 0, "nothing is read at login itself")
		Bea.combat = true
		step(3)
		eq(reads + qreads, 0, "nor in combat")
		Bea.combat = false
		step(0.1)
		check(reads > 0 and reads < 6, "then a little per frame: " .. reads)
		step(3)
		eq(reads, 6, "the NPCs are read, with no tab opened"); eq(qreads, 8, "and the quests after them")
		eq(BN.Ready(), true, "ready before their tabs are looked at"); eq(BQ.Ready(), true, "both")
		eq(#BN.Find("gorak", {}), 2, "and searchable")
		Bea.slash("npc")
		eq(reads, 6, "opening the tab reads nothing a second time")
		leave(Bea)
		-- a tab opened before the background reading has come to it finishes at once, and is not read twice
		local Cy = NewClient("Cy")
		Cy.env.LibQuestieDB, Cy.env.C_Map, Cy.env.GetRealZoneText = B2.env.LibQuestieDB, B2.env.C_Map, B2.env.GetRealZoneText
		Cy.DT.Npc.BATCH, Cy.DT.Quest.BATCH = 2, 3
		reads, qreads = 0, 0
		Cy.slash("quest")
		step(1)
		eq(qreads, 8, "a tab opened early reads at its own pace")
		step(8)
		eq(qreads, 8, "and the background reading does not read it again"); eq(reads, 6, "but does the other list")
		leave(Cy)
		-- switched off: as before, only when a tab is opened
		local Dee = NewClient("Dee")
		Dee.env.LibQuestieDB, Dee.env.C_Map = B2.env.LibQuestieDB, B2.env.C_Map
		Dee.DT.db.settings.background = false
		reads, qreads = 0, 0
		step(10)
		eq(reads + qreads, 0, "background reading switched off: nothing is read until a tab is opened")
		leave(Dee)
	end
	leave(B2)
end

-- Tools: a tab of sub-tabs; Range is one. Range: how far target and focus are, as numbers on screen
do
	local Tools, Range = A.DT.Tools, A.DT.Range
	local target, focus = Range.units[1].f, Range.units[2].f
	Range.SetMark(0) -- (the sweep over every button above pressed + a few times)
	local there = {}
	A.env.UnitExists = function(unit) return there[unit] or false end
	A.env.UnitIsUnit = function(a, b) return there[a] == "me" and b == "player" end
	eq(Range.Text(8, 10), "|cff0edfd2≤10|r", "a band, coloured by its far end: near"); eq(Range.Text(0, 5), "|cffe6e6e6≤5|r", "melee")
	eq(Range.Text(25, 30), "|cff09dd00≤30|r", "medium"); eq(Range.Text(30, 35), "|cffffd100≤35|r", "further")
	eq(Range.Text(40), "|cffe60e13>40|r", "only the near end known, 40 and beyond"); eq(Range.Text(40, 45), "|cffe60e13≤45|r", "far")
	eq(Range.Text(), nil, "nothing when the game says nothing")
	-- "my range": the edges of a band are exact, so inside or beyond 30 is known for certain
	eq(Range.Text(25, 30, 30), "|cff40ff40≤30|r", "my range 30: a band wholly inside it is green"); eq(Range.Text(30, 35, 30), "|cffff4040≤35|r", "one wholly beyond is red")
	eq(Range.Text(28, 33, 30), "|cffffd100≤33|r", "one that straddles it cannot tell: gold"); eq(Range.Text(40, nil, 30), "|cffff4040>40|r", "far beyond: red")
	eq(Range.Text(27.4, 27.4, 30), "|cff40ff4027|r", "an exact distance is one number")
	-- my own spells narrow the library's band
	local function tight(...) local lo, hi = Range.Tighten(...) return tostring(lo) .. " " .. tostring(hi) end
	eq(tight(25, 40, 30, 36), "30 36", "spells narrow both ends"); eq(tight(25, 40, nil, nil), "25 40", "no spell answered: the library's band")
	eq(tight(25, 40, 30, nil), "30 40", "only a no: the near end moves"); eq(tight(25, 40, nil, 36), "25 36", "only a yes: the far end")
	eq(tight(nil, nil, 30, 36), "30 36", "the library silent: the spells alone"); eq(tight(40, nil, nil, 36), "0 36", "they disagree: the spells are believed")
	eq(tight(25, 28, 30, 36), "30 36", "likewise the other way"); eq(tight(30, nil, 36, nil), "36 nil", "beyond the furthest spell: no far end")
	-- off until asked for
	there.target, A.ranges = true, { target = { 8, 10 }, focus = { 30, 35 } }
	A.fire("PLAYER_TARGET_CHANGED")
	eq(Range.db.settings.on, false, "Range is off to begin with"); eq(target.shown, false, "so a target has no number"); eq(Range.driver.shown, false, "and nothing runs")
	A.slash("range")
	eq(Tools.buttons[1].text, "|cffffd100Range|r", "its sub-tab is yellow while it is off"); eq(Range.ticks.on.checked, false, "and its box unticked")
	Range.ticks.on.checked = true
	click(Range.ticks.on)
	eq(Tools.buttons[1].text, "|cff40ff40Range|r", "switched on: green"); eq(target.shown, true, "and the number shows at once")
	there.target = nil
	A.fire("PLAYER_TARGET_CHANGED")
	eq(target.shown, false, "no target: no number"); eq(Range.driver.shown, false, "and nothing runs")
	there.target = true
	A.fire("PLAYER_TARGET_CHANGED")
	eq(target.shown, true, "a target: its number shows"); eq(focus.shown, false, "the focus has none of its own yet"); eq(Range.driver.shown, true, "and the readout runs")
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cff0edfd2≤10|r", "the band, in its colour")
	eq(target.sign.text, "|cff0edfd2≤|r", "the sign is a text of its own (the game's font has none)"); eq(target.text.text, "|cff0edfd210|r", "before the number, in the same colour")
	local asked = A.rangeAsked
	A.ranges.target = { 25, 30 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.05)
	eq(A.rangeAsked, asked, "not asked more than ten times a second")
	Range.driver.scripts.OnUpdate(Range.driver, 0.06)
	eq(target.last, "|cff09dd00≤30|r", "and follows as the distance changes")
	eq(Range.markText.text, "off", "no range of mine set to begin with")
	check(Range.edgesText.text:find("Against enemies:|r  5, 28, 30\n", 1, true), "the sub-tab lists the distances that can be told apart, in order, each once: " .. Range.edgesText.text)
	check(Range.edgesText.text:find("On friends:|r  none", 1, true), "and says none where the library gives none")
	for _ = 1, 6 do click(Range.markMore) end
	eq(Range.db.mark, 30, "the + button sets my range, five yards a click"); eq(Range.markText.text, "30 yd", "shown")
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cff40ff40≤30|r", "inside it: green")
	A.ranges.target = { 30, 35 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤35|r", "a step beyond: red, at once")
	-- every ranged spell of my spellbook is a test of its own, at its real range now
	local BOOK = {
		{ spellID = 10, name = "Fire Blast", maxRange = 20 }, { spellID = 11, name = "Polymorph", maxRange = 30 },
		{ spellID = 12, name = "Wrath", maxRange = 30 }, { spellID = 13, name = "Leather", maxRange = 0, isPassive = true },
		{ spellID = 14, name = "Bash", maxRange = 0 }, { spellID = 15, name = "Heal", maxRange = 40 },
		{ spellID = 16, name = "Aimed Shot", maxRange = 35, minRange = 8 },
	}
	local oldSpell = A.env.C_Spell
	local distance = 33
	A.env.C_SpellBook = {
		GetNumSpellBookSkillLines = function() return 1 end,
		GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #BOOK } end,
		GetSpellBookItemInfo = function(slot) return BOOK[slot] end,
	}
	A.env.C_Spell = setmetatable({
		GetSpellInfo = function(id) for _, s in ipairs(BOOK) do if s.spellID == id then return s end end end,
		IsSpellInRange = function(id)
			for _, s in ipairs(BOOK) do
				if s.spellID == id then
					if s.name == "Heal" then return nil end -- (not on an enemy)
					return distance <= s.maxRange and distance >= (s.minRange or 0)
				end
			end
		end,
	}, { __index = oldSpell })
	A.fire("SPELLS_CHANGED")
	A.ranges.target = { 25, 40 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤35|r", "the library says 25 to 40; my 30-yard spells do not reach and the 35-yard one does: 30 to 35")
	eq(Range.SpellEdges(), "20 Fire Blast, 30 Polymorph, 35 Aimed Shot, 40 Heal", "each distance my spells can tell, a passive and a melee one left out")
	BOOK[3].maxRange = 36 -- (a talent stretches Wrath)
	A.fire("PLAYER_TALENT_UPDATE")
	distance = 36
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤36|r", "a talent moves the edge: read anew, and 36 is an edge now (a shot with a least range is no proof of being out of range)")
	distance = 5
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	check(target.last:find("20|r", 1, true), "close in: no further than my shortest spell; the shot that is too near to fire does not count as out of range: " .. target.last)
	Range.Refresh()
	check(Range.edgesText.text:find("36 Wrath", 1, true), "the sub-tab names the spells and their ranges")
	A.env.C_SpellBook, A.env.C_Spell = nil, oldSpell
	A.fire("SPELLS_CHANGED")
	A.ranges.target = { 30, 35 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤35|r", "no spellbook to read: the library's band as it is")
	-- a member of my group, outdoors: the game tells where they stand
	local spots = { player = { 100, 200, 0, 1 }, target = { 100, 220, 0, 1 } }
	A.env.UnitPosition = function(unit) local p = spots[unit] if p then return p[1], p[2], p[3], p[4] end end
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cff40ff4020|r", "the exact distance where the game gives positions")
	spots.target[4] = 2
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(target.last, "|cffff4040≤35|r", "not across instances: the band again")
	A.env.UnitPosition = nil
	for _ = 1, 6 do click(Range.markLess) end
	click(Range.markLess)
	eq(Range.db.mark, 0, "and - takes it off again, never below nothing")
	A.ranges.target = { 25, 30 }
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	there.focus = true
	A.fire("PLAYER_FOCUS_CHANGED")
	Range.driver.scripts.OnUpdate(Range.driver, 0.2)
	eq(focus.shown, true, "a focus: a second number"); eq(focus.last, "|cffffd100≤35|r", "its own")
	there.target = "me"
	A.fire("PLAYER_TARGET_CHANGED")
	eq(target.shown, false, "targeting myself: no number")
	there.target = true
	A.fire("PLAYER_TARGET_CHANGED")
	-- where it stands
	eq(target.placed, "free", "without the game's target frame: at its free place")
	A.env._G.TargetFrame = { portrait = {} }
	Range.Apply()
	eq(target.placed, "portrait", "with it: above its portrait"); eq(focus.placed, "free", "the focus frame is not there: free")
	-- the Tools tab and the Range sub-tab
	A.slash("range")
	eq(Tools.buttons[1].text, "|cff40ff40Range|r", "/dt range opens the Tools tab on the Range sub-tab"); eq(Tools.buttons[1].shown, true, "its sub-tab button is there")
	eq(Range.ticks.locked.checked, true, "locked to begin with"); eq(Range.ticks.portrait.checked, true, "and above the portrait"); eq(Range.sizeText.text, "16", "the size")
	eq(target.box.shown, false, "locked: no box to drag")
	Range.ticks.locked.checked = false
	click(Range.ticks.locked)
	eq(target.box.shown, true, "unlocked: a box to drag it by")
	there.focus = nil
	A.fire("PLAYER_FOCUS_CHANGED")
	eq(focus.shown, true, "unlocked, a readout shows without its unit, to be placed")
	target.scripts.OnDragStop(target)
	eq(target.placed, "free", "dragged: it stays where it was put, though above-the-portrait is on"); eq(Range.db.pos.target[1], "CENTER", "and the place is saved")
	target.scripts.OnMouseWheel(target, 1)
	eq(Range.db.size, 17, "the wheel over one makes it bigger"); eq(Range.sizeText.text, "17", "and the sub-tab follows")
	click(Range.smaller)
	click(Range.smaller)
	eq(Range.db.size, 15, "the - button makes it smaller")
	Range.SetSize(99)
	eq(Range.db.size, 32, "no bigger than 32")
	Range.SetSize(1)
	eq(Range.db.size, 8, "no smaller than 8")
	click(Range.reset)
	eq(target.placed, "portrait", "Reset positions: back above the portrait"); eq(Range.db.pos.target, nil, "the dragged place forgotten")
	Range.ticks.portrait.checked = false
	click(Range.ticks.portrait)
	eq(target.placed, "free", "above-the-portrait off: free")
	Range.ticks.portrait.checked = true
	click(Range.ticks.portrait)
	Range.ticks.locked.checked = true
	click(Range.ticks.locked)
	eq(focus.shown, false, "locked again: no number without a unit"); eq(target.box.shown, false, "and no box")
	Range.ticks.target.checked = false
	click(Range.ticks.target)
	eq(target.shown, false, "Range to my target off: gone"); eq(Range.driver.shown, false, "nothing left to run")
	Range.ticks.target.checked = true
	click(Range.ticks.target)
	A.env._G.TargetFrame = nil
	there.target = nil
	A.fire("PLAYER_TARGET_CHANGED")
	eq(A.DT.modules.range.hello, nil, "the module has nothing to say to the guild"); eq(A.env.SLASH_DAWNTOOLS_RANGE1, "/dtrange", "its short command")
end

-- Tracker: a button that targets a name and marks it
do
	local Tools, Tracker = A.DT.Tools, A.DT.Tracker
	local b = Tracker.button
	Tracker.Set("on", false)
	Tracker.SetName("")
	Tracker.SetMark("ping")
	Tracker.SetGrow("CENTER")
	Tracker.Reset()
	eq(Tracker.Macro("Old Greyfin", "ping", true), "/cleartarget\n/tar Old Greyfin\n/ping [@target,exists,nodead]\n/targetlasttarget [noexists]\n/startattack [combat,harm,nodead]",
		"the click, as one macro: look afresh, ping it only if it is there and alive, else my old target back")
	eq(Tracker.Macro("Old Greyfin", "ping", false), "/cleartarget\n/tar Old Greyfin\n/ping [@target,exists,nodead]",
		"with no target to begin with there is none to put back (an old 'last target' is not dug up)")
	eq(Tracker.Macro("Rex", "icon", true), "/cleartarget\n/tar Rex\n/tm [@target,exists,nodead] 8\n/targetlasttarget [noexists]\n/startattack [combat,harm,nodead]", "or a raid icon")
	eq(Tracker.Macro("Rex", "none", true), "/cleartarget\n/tar Rex\n/targetlasttarget [noexists]\n/startattack [combat,harm,nodead]", "or nothing but the target")
	eq(Tracker.Macro("", "ping"), "", "no name: the click does nothing")
	eq(Tracker.Clean("  Old\nGreyfin  "), "Old Greyfin", "a name is one line, trimmed"); eq(#Tracker.Clean(("x"):rep(200)), 60, "and no longer than 60")
	eq(Tracker.Clean("Old;[Grey]fin"), "OldGreyfin", "macro signs are taken out of a name")
	eq(Tracker.Clean(("x"):rep(59) .. "\195\169"), ("x"):rep(59), "a letter cut in half at the limit goes whole")
	eq(b.shown, false, "the tracker is off to begin with")
	eq(b.attr.type1, "macro", "a left click runs a macro"); eq(b.attr["shift-type1"], "", "a shift-click does nothing: shift is for dragging")
	A.slash("tracker")
	local tab
	for _, w in ipairs(Tools.buttons) do if w.id == "tracker" then tab = w end end
	eq(tab.text, "|cffffd100Tracker|r", "its sub-tab, yellow while off")
	Tracker.onBox.checked = true
	click(Tracker.onBox)
	eq(b.shown, true, "switched on: the button shows"); eq(tab.text, "|cff40ff40Tracker|r", "and its sub-tab is green")
	eq(b.label.text, "|cff888888Right-click: set a name|r", "it says how to give it a name"); eq(b.width, 160, "as wide as that text")
	-- the name, by right click
	b.scripts.PostClick(b, "RightButton", true)
	eq(A.popups[#A.popups] == "DAWNTOOLS_TRACKER", false, "the right button on its way down asks nothing yet")
	b.scripts.PostClick(b, "RightButton", false)
	eq(A.popups[#A.popups], "DAWNTOOLS_TRACKER", "on its way up it asks for the name")
	b.scripts.PostClick(b, "LeftButton", false)
	local box = { text = "Rex", GetText = function(self) return self.text end }
	A.env.StaticPopupDialogs.DAWNTOOLS_TRACKER.OnAccept({ editBox = box })
	eq(Tracker.db.name, "Rex", "OK takes the name up"); eq(b.label.text, "|cffffd100Rex|r", "shown on the button")
	eq(b.attr["dt-keep"], "/cleartarget\n/tar Rex\n/ping [@target,exists,nodead]\n/targetlasttarget [noexists]\n/startattack [combat,harm,nodead]", "and in its macro for when I have a target")
	eq(b.attr["dt-plain"], "/cleartarget\n/tar Rex\n/ping [@target,exists,nodead]", "and in the one for when I have none")
	check(A.wrapBody and A.wrapBody:find("[@target,exists] dt-keep; dt-plain", 1, true), "which of the two a click runs is picked as it comes, by whether I have a target")
	-- the tooltip keeps out of the way of a shift-drag
	A.env.GameTooltip.shown = false
	b.scripts.OnEnter(b)
	eq(A.env.GameTooltip.shown, true, "hovering shows what the clicks do")
	A.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	eq(A.env.GameTooltip.shown, false, "Shift pressed over it: the tooltip goes")
	A.env.IsShiftKeyDown = function() return true end
	b.scripts.OnEnter(b)
	eq(A.env.GameTooltip.shown, false, "and does not come up while Shift is held")
	A.env.IsShiftKeyDown = nil
	b.scripts.OnLeave(b)
	Tracker.tipBox.checked = false
	click(Tracker.tipBox)
	b.scripts.OnEnter(b)
	eq(A.env.GameTooltip.shown, false, "the tooltip switched off on the sub-tab: hovering shows nothing")
	b.scripts.OnLeave(b)
	Tracker.tipBox.checked = true
	click(Tracker.tipBox)
	eq(b.width, 90, "a short name: no narrower than the least width")
	Tracker.SetName("A Very Long Name Of A Rare Mob Indeed")
	eq(b.width, 37 * 6 + 22, "a long one: as wide as it needs")
	-- what it grows from
	eq(b.hung, "CENTER", "hung by its centre to begin with")
	b.left, b.right, b.mid = 400, 644, 300
	b.moving = true
	b.scripts.OnDragStop(b)
	eq(Tracker.db.pos[1], 522, "dragged: the place of its centre is kept"); eq(Tracker.db.pos[2], 300, "and its height")
	click(Tracker.growButton)
	click(Tracker.growButton.menu.rows[1])
	eq(Tracker.db.grow, "LEFT", "Grow from left, picked from the list"); eq(Tracker.db.pos[1], 400, "it stays where it is: now its left edge is what is kept")
	eq(b.hung, "LEFT", "and what it hangs by"); eq(Tracker.growButton.label.text, "Grow from: Left (grows to the right)", "named on the button")
	Tracker.SetGrow("RIGHT")
	eq(Tracker.db.pos[1], 644, "from the right: its right edge")
	-- the mark
	click(Tracker.markButton)
	click(Tracker.markButton.menu.rows[2])
	eq(Tracker.db.mark, "icon", "the mark picked from the list"); check(b.attr["dt-keep"]:find("/tm [@target,exists,nodead] 8", 1, true), "is in the macro")
	-- in combat nothing of the button may be changed: it waits
	A.combat = true
	Tracker.SetName("Boar")
	eq(b.label.text, "|cffffd100A Very Long Name Of A Rare Mob Indeed|r", "a name set in combat is not taken up yet")
	check(A.printed[#A.printed]:find("taken up when the fight is over", 1, true), "and chat says so")
	check(Tracker.note.text:find("Waiting for the fight to end", 1, true), "so does the sub-tab")
	A.combat = false
	A.fire("PLAYER_REGEN_ENABLED")
	eq(b.label.text, "|cffffd100Boar|r", "the fight over: taken up"); check(b.attr["dt-plain"]:find("/tar Boar", 1, true), "in the macro too")
	-- the name from the sub-tab's own box
	Tracker.nameBox:SetText("Old Greyfin")
	Tracker.nameBox.scripts.OnEnterPressed(Tracker.nameBox)
	eq(Tracker.db.name, "Old Greyfin", "the box on the sub-tab sets it as well")
	click(Tracker.reset)
	eq(Tracker.db.pos, nil, "Reset position: back to where it began")
	-- a macro for a key: it clicks the button, so it needs no rewriting when the name changes
	local macros, picked = {}, nil
	A.env.GetMacroIndexByName = function(name) for i, m in ipairs(macros) do if m.name == name then return i end end return 0 end
	A.env.CreateMacro = function(name, icon, body) macros[#macros + 1] = { name = name, body = body, icon = icon } return #macros end
	A.env.EditMacro = function(i, name, _, body) macros[i].body = body end
	A.env.GetMacroBody = function(i) return macros[i] and macros[i].body end
	A.env.PickupMacro = function(i) picked = i end
	Tracker.macroDone = nil
	Tracker.Apply()
	eq(#macros, 1, "with the tracker switched on its macro is simply there, in the macro list"); eq(macros[1].name, "DT Tracker", "named")
	eq(macros[1].body, Tracker.Macro("Old Greyfin", Tracker.db.mark, true), "it holds the commands themselves, the name in them"); check(#macros[1].body <= 255, "and fits a macro"); eq(macros[1].icon, "Ability_Hunter_Pet_Wolf", "with a beast for an icon"); eq(picked, nil, "nothing is put on the cursor unasked")
	Tracker.Apply()
	eq(#macros, 1, "made once, not again and again")
	click(Tracker.macroButton)
	eq(picked, 1, "the button puts it on the cursor, to drop on a bar"); eq(#macros, 1, "the same one")
	macros[1].body = "/dance"
	click(Tracker.macroButton)
	eq(#macros, 1, "pressed again: no second one"); eq(macros[1].body, Tracker.Macro("Old Greyfin", Tracker.db.mark, true), "the one there is put right")
	Tracker.SetName("Rex")
	check(macros[1].body:find("/tar Rex", 1, true), "a new name is written into the macro"); eq(#macros, 1, "the same macro")
	Tracker.SetName("Old Greyfin")
	A.combat = true
	picked = nil
	click(Tracker.macroButton)
	eq(picked, nil, "not in combat"); check(A.printed[#A.printed]:find("cannot be made in combat", 1, true), "it says so")
	A.combat = false
	eq(A.DT.modules.tracker.hello, nil, "the module has nothing to say to the guild"); eq(A.env.SLASH_DAWNTOOLS_TRACKER1, "/dttracker", "its short command")
	Tracker.Set("on", false)
	;(function() -- Enemies: the enemy players in sight, who is on me first
		local En, e = A.DT.Enemies, A.env
		local was = { e.UnitExists, e.UnitIsPlayer, e.UnitCanAttack, e.UnitIsUnit, e.UnitName, e.UnitClass, e.UnitLevel, e.C_NamePlate, e.PlaySound }
		-- unit = { name, class, file, level, enemy player, on me }
		local units = { nameplate1 = { "Gank Alot", "Rogue", "ROGUE", 60, true, true }, nameplate2 = { "Zed Foe", "Mage", "MAGE", -1, true, false },
			nameplate3 = { "Friend Lee", "Priest", "PRIEST", 40, false, false }, target = { "Zed Foe", "Mage", "MAGE", -1, true, false } }
		e.UnitExists = function(u) return units[u] ~= nil end
		e.UnitIsPlayer = function(u) return units[u] ~= nil end
		e.UnitCanAttack = function(_, u) return units[u] and units[u][5] or false end
		e.UnitIsUnit = function(a, b) local u = a:match("^(.*)target$") return b == "player" and units[u] and units[u][6] or false end
		e.UnitName = function(u) return units[u] and units[u][1] end
		e.UnitClass = function(u) if units[u] then return units[u][2], units[u][3] end end
		e.UnitLevel = function(u) return units[u] and units[u][4] end
		e.C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" }, { namePlateUnitToken = "nameplate3" } } end }
		local sounds = 0
		e.PlaySound = function() sounds = sounds + 1 end
		local lib = En.lib
		En.lib = { GetRange = function(_, u) if u == "nameplate1" then return 8, 10 end if u == "target" or u == "nameplate2" then return 30, 35 end end }

		En.Scan()
		local list = En.List()
		eq(#list, 2, "the enemy players in sight, each once (a friend is not one)")
		eq(list[1].name, "Gank Alot", "who has me targeted first"); eq(list[1].onMe, true, "marked")
		check(En.LineText(list[1], 0):find("Gank Alot|r  60 Rogue  |cffcccccc8-10 yd|r  |cffff3030ON YOU|r", 1, true), "name, level, class, how far, and ON YOU: " .. En.LineText(list[1], 0))
		check(En.LineText(list[2], 0):find("Zed Foe|r  ?? Mage  |cffcccccc30-35 yd|r", 1, true) and not En.LineText(list[2], 0):find("ON YOU", 1, true),
			"one too far above me to be told shows ??, and is not on me")
		eq(En.alert, "onMe", "somebody on me is worth the louder sound")
		;(function() -- the game will not say whose target they have (as it may in combat): said, not passed off as "not on me"
			local wasUnit, wasSecret = e.UnitIsUnit, e.issecretvalue
			e.UnitIsUnit = function() return "hidden" end
			e.issecretvalue = function(v) return v == "hidden" end
			En.Scan()
			local l = En.List()
			eq(l[1].blind, true, "a target the game hides is not known"); eq(l[1].onMe, false, "and not counted as on me")
			check(En.LineText(l[1], 0):find("target hidden", 1, true), "the line says so: " .. En.LineText(l[1], 0))
			e.UnitIsUnit = function() error("not allowed") end
			En.Scan()
			eq(En.List()[1].blind, true, "nor is one the game refuses outright")
			e.UnitIsUnit, e.issecretvalue = wasUnit, wasSecret
			En.Scan()
			eq(En.List()[1].blind, false, "told again: known again")
			En.alert = "onMe"
		end)()
		-- the nearest first among those not on me
		units.nameplate1[6] = false
		units.nameplate4 = { "Far Away", "Hunter", "HUNTER", 50, true, false }
		e.C_NamePlate.GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" }, { namePlateUnitToken = "nameplate4" } } end
		En.Scan()
		list = En.List()
		eq(list[1].name, "Gank Alot", "nobody on me: the nearest first"); eq(list[3].name, "Far Away", "one whose distance is not known last")
		-- on screen, with its sound
		En.Set("on", true)
		En.alert = "onMe"
		En.Tick()
		eq(En.frame.shown, true, "switched on: the list shows"); eq(sounds, 1, "with a sound for the news")
		-- moved as the Tracker is: only with Shift held
		local f, moved = En.frame, 0
		local wasShift, wasMove = e.IsShiftKeyDown, f.StartMoving
		f.StartMoving = function() moved = moved + 1 end
		e.IsShiftKeyDown = function() return false end
		f.scripts.OnDragStart(f)
		eq(moved, 0, "a plain drag does not move it")
		f.scripts.OnEnter(f)
		check(table.concat(e.GameTooltip.lines or {}, "|"):find("Hold Shift and drag to move", 1, true), "its tooltip says how to move it")
		En.Set("tips", false)
		e.GameTooltip.lines = {}
		f.scripts.OnEnter(f)
		eq(#(e.GameTooltip.lines or {}), 0, "the tooltip can be switched off")
		En.Set("tips", true)
		-- (clicks are taken only while Shift is held: otherwise they go through to the world)
		local clicks
		f.SetMouseClickEnabled = function(_, on) clicks = on end
		e.IsShiftKeyDown = function() return true end
		A.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		eq(clicks, true, "Shift pressed: the list takes clicks, to be dragged")
		A.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
		eq(clicks, true, "another key changes nothing")
		f.scripts.OnDragStart(f)
		eq(moved, 1, "with Shift held it does")
		local wasCenter = f.GetCenter
		f.GetCenter = function() return 500, 400 end
		f.scripts.OnDragStop(f)
		check(En.db.pos and En.db.pos[1] == "CENTER" and En.db.pos[3] == 500, "and where it was put is kept")
		-- Shift let go in mid-drag: put down where it is, and click-through again
		f.scripts.OnDragStart(f)
		f.GetCenter = function() return 640, 300 end
		e.IsShiftKeyDown = function() return false end
		A.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
		eq(En.db.pos[3], 640, "Shift let go in mid-drag: it is put down where it is"); eq(clicks, false, "and clicks go through it again")
		-- locked: Shift or no Shift, it stays
		eq(En.db.settings.locked, false, "it is not locked to begin with")
		En.Set("locked", true)
		e.IsShiftKeyDown = function() return true end
		A.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		eq(clicks, false, "locked: Shift does not make it take clicks")
		f.scripts.OnDragStart(f)
		eq(moved, 2, "and a Shift-drag does not move it")
		e.IsShiftKeyDown = function() return false end -- (with Shift held the tooltip keeps out of the way)
		e.GameTooltip.lines = {}
		f.scripts.OnEnter(f)
		check(table.concat(e.GameTooltip.lines or {}, "|"):find("Locked in place", 1, true), "its tooltip says it is locked")
		e.IsShiftKeyDown = function() return true end
		En.Set("locked", false)
		eq(clicks, true, "unlocked with Shift held: it takes clicks again")
		check(En.boxes.locked, "a tick box for the lock")
		f.SetMouseClickEnabled = nil
		e.IsShiftKeyDown, f.StartMoving, f.GetCenter = wasShift, wasMove, wasCenter
		check(En.frame.title.text:find("Enemies: 3", 1, true), "its title counts them"); check(En.frame.lines[1].text:find("Gank Alot", 1, true), "a line each")
		-- out of sight: listed a while as lost, then forgotten
		e.C_NamePlate.GetNamePlates = function() return {} end
		units.target = nil
		step(4)
		En.Scan()
		list = En.List()
		eq(#list, 3, "out of sight they stay listed for a while"); check(En.LineText(list[1], e.GetTime()):find("lost %d+s ago"), "as lost, with how long ago")
		eq(list[1].onMe, false, "who they are on is not known any more")
		step(8)
		En.Scan()
		eq(#En.List(), 0, "and are forgotten after ten seconds")
		En.Tick()
		check(En.frame.title.text:find("none in sight", 1, true), "the list says there is nobody")
		En.Set("on", false)
		eq(En.frame.shown, false, "switched off: gone")
		En.lib = lib
		e.UnitExists, e.UnitIsPlayer, e.UnitCanAttack, e.UnitIsUnit, e.UnitName, e.UnitClass, e.UnitLevel, e.C_NamePlate, e.PlaySound = was[1], was[2], was[3], was[4], was[5], was[6], was[7], was[8], was[9]
	end)()
	;(function() -- Silencer: a box per noise, each the game's own setting
		local Sil, e, cvars = A.DT.Silencer, A.env, { Sound_EnableErrorSpeech = "1" }
		local tab
		A.DT.Tools.Open("silencer")
		for _, w in ipairs(Tools.buttons) do if w.id == "silencer" then tab = w end end
		eq(Sil.boxes[1].enabled, false, "a client without the setting: the box cannot be ticked")
		e.GetCVar = function(name) return cvars[name] end
		e.SetCVar = function(name, value) cvars[name] = tostring(value) end
		A.DT.Tools.Show("silencer")
		eq(Sil.boxes[1].checked, false, "unticked to begin with"); eq(Sil.boxes[1].enabled, true, "and can be ticked"); eq(tab.text, "|cffffd100Silencer|r", "its sub-tab yellow")
		Sil.boxes[1].checked = true
		click(Sil.boxes[1])
		eq(cvars.Sound_EnableErrorSpeech, "0", "ticked: the game's error speech is switched off"); eq(tab.text, "|cff40ff40Silencer|r", "and the sub-tab is green")
		Sil.boxes[1].checked = false
		click(Sil.boxes[1])
		eq(cvars.Sound_EnableErrorSpeech, "1", "unticked: on again")
		e.GetCVar, e.SetCVar = nil, nil
	end)()
end

-- MP5: the five-second rule, counted from my own casts of spells that cost mana
do
	local Tools, Mp5 = A.DT.Tools, A.DT.Mp5
	local f, spark, driver = Mp5.f, Mp5.spark, Mp5.driver
	Mp5.Reset()
	Mp5.Set("locked", true)
	Mp5.Set("on", false) -- (the sweep over every button above may have pressed things)
	Mp5.SetLook("spark")
	local oldSpell, oldClass = A.env.C_Spell, A.env.UnitClass
	local COST = { [133] = { { type = 0, cost = 30 } }, [1] = { { type = 1, cost = 15 } }, [2] = { { type = 0, cost = 0 } }, [5143] = { { type = 0, cost = 85 } } }
	A.env.C_Spell = setmetatable({ GetSpellPowerCost = function(id) return COST[id] end }, { __index = oldSpell })
	A.env.UnitClass = function() return "Mage", "MAGE" end
	local function cast(id) A.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", id) end
	eq(Mp5.CostsMana(133), true, "a spell that costs mana"); eq(Mp5.CostsMana(1), false, "one that costs rage does not")
	eq(Mp5.CostsMana(2), false, "nor a free one"); eq(Mp5.CostsMana(999), false, "nor one the game knows nothing of")
	-- off until asked for
	cast(133)
	eq(driver.shown, false, "MP5 is off to begin with: a cast shows nothing")
	A.slash("mp5")
	local tab
	for _, b in ipairs(Tools.buttons) do if b.id == "mp5" then tab = b end end
	eq(tab.text, "|cffffd100MP5|r", "its sub-tab, yellow while off"); eq(Mp5.lookButton.label.text, "Look: Spark on my mana bar", "the spark is the look to begin with")
	Mp5.ticks.on.checked = true
	click(Mp5.ticks.on)
	eq(tab.text, "|cff40ff40MP5|r", "switched on: green"); eq(driver.shown, false, "idle: nothing runs")
	-- without the game's mana bar the spark has nowhere to run: the thin bar instead
	eq(Mp5.Look(), "bar", "no mana bar of the game's: the thin bar"); check(Mp5.note.text:find("thin bar is shown instead", 1, true), "and the sub-tab says so")
	cast(1)
	eq(driver.shown, false, "a spell that costs no mana starts nothing")
	cast(133)
	eq(driver.shown, true, "a mana spell starts the five seconds"); eq(f.shown, true, "the bar shows"); eq(f.part, 1, "full")
	eq(f.text.text, "5.0", "with the seconds beside it")
	step(2.5)
	check(math.abs(f.part - 0.5) < 0.02, "half way after two and a half seconds: " .. f.part); eq(f.text.text, "2.5", "the seconds follow")
	cast(133)
	eq(f.part, 1, "another mana spell starts it again")
	step(5.1)
	eq(f.shown, false, "five seconds on: gone"); eq(driver.shown, false, "and nothing runs any more")
	-- a channelled spell holds it
	A.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-2", 5143)
	step(8)
	eq(driver.shown, true, "a channelled mana spell holds the count"); eq(f.part, 1, "full, however long it lasts")
	A.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-2", 5143)
	step(2.5)
	check(math.abs(f.part - 0.5) < 0.02, "the five seconds run from its end")
	step(3)
	eq(f.shown, false, "and end")
	-- the spark, on the game's own mana bar
	A.env._G.PlayerFrameManaBar = { GetWidth = function() return 100 end, GetHeight = function() return 12 end, IsVisible = function() return true end }
	Mp5.Apply()
	Mp5.Refresh()
	eq(Mp5.Look(), "spark", "with the game's mana bar: the spark"); check(not Mp5.note.text:find("mana bar is not there", 1, true), "no word about falling back")
	cast(133)
	eq(spark.shown, true, "a cast: the spark is on the bar"); eq(spark.at, 1, "at its right end"); eq(f.shown, false, "the other looks are not shown")
	step(2.5)
	check(math.abs(spark.at - 0.5) < 0.02, "half way along after half the time")
	step(3)
	eq(spark.shown, false, "gone at the left end")
	-- the other looks, from the list
	click(Mp5.lookButton)
	click(Mp5.lookButton.menu.rows[4])
	eq(Mp5.db.look, "number", "a look picked from the list"); eq(Mp5.lookButton.label.text, "Look: Number", "named on the button")
	click(Mp5.test)
	eq(f.text.text, "5.0", "Test runs it once: the number"); eq(spark.shown, false, "and no spark")
	step(1)
	eq(f.text.text, "4.0", "counting down")
	Mp5.SetLook("clock")
	step(0.5)
	eq(f.text.text, "4", "the clock: whole seconds inside"); check(math.abs(f.part - 0.7) < 0.02, "and as much left of it")
	Mp5.ticks.seconds.checked = false
	click(Mp5.ticks.seconds)
	step(0.1)
	eq(f.text.text, "", "Show the seconds off: no number in the clock")
	Mp5.ticks.seconds.checked = true
	click(Mp5.ticks.seconds)
	step(6)
	-- placing it: unlocked it runs round and can be dragged and resized
	Mp5.SetLook("bar")
	eq(driver.shown, false, "locked and idle: nothing")
	Mp5.ticks.locked.checked = false
	click(Mp5.ticks.locked)
	eq(driver.shown, true, "unlocked: it is shown, to be placed"); eq(f.part, 1, "standing still and full, not counting"); eq(f.box.shown, true, "with a box to drag it by"); eq(f.grip.shown, true, "and a corner to size it by")
	f.scripts.OnDragStop(f)
	eq(Mp5.db.pos.bar[1], "CENTER", "where it was dragged is saved, per look"); eq(Mp5.db.pos.clock, nil, "another look keeps its own place")
	f.w, f.h = 200, 10
	f.grip.scripts.OnMouseUp(f.grip)
	eq(Mp5.db.size.bar[1], 200, "pulled by the corner: its new width is saved"); eq(Mp5.db.size.bar[2], 10, "and height"); eq(Mp5.sizeText.text, "200 x 10", "shown on the sub-tab")
	click(Mp5.bigger)
	eq(Mp5.db.size.bar[2], 11, "the + button makes the bar thicker")
	for _ = 1, 40 do click(Mp5.bigger) end
	eq(Mp5.db.size.bar[2], 30, "to a limit")
	Mp5.SetLook("spark")
	click(Mp5.bigger)
	eq(Mp5.db.size.spark, 3, "for the spark the size is how thick the line is"); eq(f.grip.shown, false, "and it has no corner: it lives on the mana bar")
	click(Mp5.reset)
	eq(Mp5.db.pos.bar, nil, "Reset: places forgotten"); eq(Mp5.db.size.spark, nil, "and sizes")
	Mp5.ticks.locked.checked = true
	click(Mp5.ticks.locked)
	eq(driver.shown, false, "locked again and idle: nothing runs"); eq(f.box.shown, false, "no box")
	-- only my own spells start it: a proc the game reports, with a mana cost on paper, does not
	A.env.IsPlayerSpell = function(id) return id == 133 end
	COST[777] = { { type = 0, cost = 10 } }
	cast(777)
	eq(driver.shown, false, "a spell that is not in my spellbook starts nothing")
	cast(133)
	eq(driver.shown, true, "one of mine does"); check(Mp5.last:find("(133)", 1, true), "and what started it is kept: " .. tostring(Mp5.last))
	A.env.IsPlayerSpell = nil
	step(6)
	-- a cost the game hides in combat still counts as a mana spell; a character without mana never runs
	A.env.issecretvalue = function(v) return v == "hidden" end
	COST[7] = { { type = 0, cost = "hidden" } }
	eq(Mp5.CostsMana(7), true, "a mana cost the game will not show still counts")
	A.env.issecretvalue = nil
	A.env.UnitClass = oldClass
	cast(133)
	eq(driver.shown, false, "a warrior has no mana: nothing ever runs")
	Mp5.Refresh()
	check(Mp5.note.text:find("has no mana", 1, true), "and the sub-tab says why")
	A.env.C_Spell, A.env._G.PlayerFrameManaBar = oldSpell, nil
	eq(A.DT.modules.mp5.hello, nil, "the module has nothing to say to the guild"); eq(A.env.SLASH_DAWNTOOLS_MP51, "/dtmp5", "its short command")
end

-- Combat: who killed me and who I killed, from the combat log
local Combat = A.DT.Combat
local ME_GUID = "Player-Alice"
local function log(event, sGUID, sName, dGUID, dName, ...)
	local extra = { ... }
	A.log = { 0, event, false, sGUID, sName, 0, 0, dGUID, dName, 0, 0, extra[1], extra[2], extra[3], extra[4], extra[5], extra[6], extra[7], extra[8], extra[9], extra[10] }
	A.fire("COMBAT_LOG_EVENT_UNFILTERED")
end
A.env.GetRealZoneText = function() return "Stranglethorn Vale" end
A.env.GetSubZoneText = function() return "Nesingwary's Expedition" end
A.env.C_Map = { GetBestMapForUnit = function() return 1434 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.3567, 0.1049 end } end }
log("SPELL_DAMAGE", "Player-Zed", "Zed", ME_GUID, "Alice", 133, "Fireball", 4, 300, 0, 4, 0, 0, 0, true) -- (a critical hit)
step(2)
log("SWING_DAMAGE", "Creature-0-1-2-3-99-0001", "Tiger", ME_GUID, "Alice", 40)
log("SWING_DAMAGE", "Pet-0-1-2-3-77-0001", "Fang", ME_GUID, "Alice", 25)
log("SPELL_DAMAGE", "Player-Zed", "Zed", "Player-Other", "Other", 133, "Fireball", 4, 999) -- not at me
log("SPELL_PERIODIC_DAMAGE", "Player-Zed", "Zed", ME_GUID, "Alice", 12, "Ignite", 4, 60)
log("UNIT_DIED", nil, nil, ME_GUID, "Alice")
A.fire("PLAYER_DEAD")
eq(#Combat.db.deaths, 1, "a death is recorded once, however it is told")
local death = Combat.db.deaths[1]
eq(death.killer, "Zed", "the last to hit me is the killer"); eq(death.player, true, "a player"); eq(death.with, "Ignite", "with what")
eq(death.amount, 60, "for how much"); eq(death.dmg, 360, "and all they did in those seconds")
eq(death.zone, "Stranglethorn Vale", "where"); eq(death.sub, "Nesingwary's Expedition", "exactly"); eq(death.x, 35.7, "on the map"); eq(death.level, 10, "at my level")
eq(#death.assists, 2, "the others who hit me helped"); eq(death.assists[1][1], "Tiger", "most damage first"); eq(death.assists[2][1], "Fang (pet)", "a pet is named as one")
check(not death.assists[1][3], "the tiger is no player")
-- the recap: every hit behind the death
eq(#death.hits, 4, "every hit I took is kept"); eq(death.hits[1][1], 2, "with how long before the death"); eq(death.hits[1][5], true, "and whether it was critical")
eq(death.hits[2][5], nil, "a plain swing is not")
-- where the combat log is closed to addons (WoW Forever): kills from PARTY_KILL, deaths from the game's recap
;(function()
	local kills, deaths, wasOpen = #Combat.db.kills, #Combat.db.deaths, Combat.open
	local oldGUID, oldName = A.env.UnitGUID, A.env.UnitName
	eq(wasOpen, true, "a client with an open combat log reads it")
	Combat.open = false
	A.env.UnitGUID = function(u) if u == "target" then return "Player-Enemy" end return oldGUID(u) end
	A.env.UnitName = function(u) if u == "target" then return "Gankalot" end return oldName and oldName(u) end
	A.fire("PLAYER_TARGET_CHANGED")
	A.fire("PARTY_KILL", ME_GUID, "Creature-0-1-2-3-55-0009")
	eq(#Combat.db.kills, kills, "a mob is no kill: this is for players")
	A.fire("PARTY_KILL", ME_GUID, "Player-Enemy")
	eq(#Combat.db.kills, kills + 1, "a killing blow of mine on a player is a kill, without the combat log")
	local k = Combat.db.kills[#Combat.db.kills]
	eq(k.name, "Gankalot", "named as I saw them"); eq(k.guild, "Running Dawn", "with the guild I saw under the name"); eq(k.blow, true, "the blow was mine"); eq(k.player, true, "a player"); eq(k.zone, "Stranglethorn Vale", "where")
	A.fire("PARTY_KILL", ME_GUID, "Player-Enemy")
	A.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Gankalot dies, honorable kill Rank: Scout (12 Honor Points)")
	eq(#Combat.db.kills, kills + 1, "told three times: one kill")
	eq(k.class, "Warrior", "what was seen of them is kept: class"); eq(k.honor, 12, "the honour line adds its honour"); eq(k.rank, "Scout", "and their rank")
	check(Combat.About(k):find("Warrior, Scout, 12 honor", 1, true), "all of it in one line: " .. tostring(Combat.About(k)))
	check(Combat.Recap(k, false)[2].text:find("12 honor", 1, true), "shown in the kill's window")
	A.fire("PARTY_KILL", "Player-Bob", "Player-Elsewhere")
	eq(#Combat.db.kills, kills + 1, "a group mate's kill of someone I was not on is not mine")
	step(6)
	A.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Sneakums dies, honorable kill Rank: Grunt (9 Honor Points)")
	eq(#Combat.db.kills, kills + 2, "the honour line tells of a kill I helped with")
	eq(Combat.db.kills[#Combat.db.kills].name, "Sneakums", "by name"); eq(Combat.db.kills[#Combat.db.kills].blow, nil, "not my blow")
	A.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 5 honor points.")
	eq(#Combat.db.kills, kills + 2, "other honour lines are not kills")
	table.remove(Combat.db.kills)
	local recapAt = 0 -- (each death's recap has its own times: one with the times of the last is that last one's)
	A.env.C_DeathRecap = { GetRecapEvents = function() return {
		{ timestamp = recapAt + 105, event = "SPELL_DAMAGE", sourceName = "Zed", spellName = "Pyroblast", spellId = 11366, amount = 500, overkill = 20 },
		{ timestamp = recapAt + 100, event = "SWING_DAMAGE", sourceName = "Tiger", amount = 40, overkill = -1 },
	} end }
	step(5)
	A.fire("PLAYER_DEAD")
	eq(#Combat.db.deaths, deaths, "a death no player I know of had a hand in is not kept")
	check(Combat.db.deathLog[#Combat.db.deathLog]:find("the death recap gave 2 events; struck by: Tiger, Zed; enemy players with me targeted: none; not kept", 1, true),
		"and what it was made of is noted: " .. Combat.db.deathLog[#Combat.db.deathLog])
	;(function() -- nobody known struck, but an enemy player had me targeted: the death is theirs, as a guess
		local e = A.env
		local was = { e.UnitExists, e.UnitIsPlayer, e.UnitCanAttack, e.UnitIsUnit, e.UnitGUID, e.UnitName }
		e.UnitExists = function(u) return u == "target" end
		e.UnitIsPlayer = function() return true end
		e.UnitCanAttack = function() return true end
		e.UnitIsUnit = function(a, b) return a == "targettarget" and b == "player" end
		e.UnitGUID = function(u) if u == "target" then return "Player-Gank" end return oldGUID(u) end
		e.UnitName = function(u) if u == "target" then return "Gank Stabber" end return oldName and oldName(u) end
		Combat.Watch()
		e.UnitExists, e.UnitIsPlayer, e.UnitCanAttack, e.UnitIsUnit, e.UnitGUID, e.UnitName = was[1], was[2], was[3], was[4], was[5], was[6]
		step(5)
		Combat.Watch = Combat.Watch -- (the recap is still that of the death before: it is asked again, then given up)
		local e2 = A.env
		local w = { e2.UnitExists, e2.UnitIsPlayer, e2.UnitCanAttack, e2.UnitIsUnit, e2.UnitGUID, e2.UnitName }
		A.fire("PLAYER_DEAD")
		eq(#Combat.db.deaths, deaths, "a recap that is still the last death's: the death waits for a new one")
		step(3)
		eq(#Combat.db.deaths, deaths + 1, "a death with an enemy player on me is kept, though nobody is known to have struck")
		check(Combat.db.deathLog[#Combat.db.deathLog]:find("still those of the death before (asked 4 times)", 1, true), "having asked the game four times: " .. Combat.db.deathLog[#Combat.db.deathLog])
		local g = Combat.db.deaths[#Combat.db.deaths]
		eq(g.killer, "Gank Stabber", "to whoever had me targeted"); eq(g.guess, true, "marked as a guess"); eq(g.player, true, "a player")
		check(Combat.Recap(g, true)[2].text:find("A guess", 1, true) or Combat.Recap(g, true)[3].text:find("A guess", 1, true), "and its window says so")
		check(Combat.db.deathLog[#Combat.db.deathLog]:find("enemy players with me targeted: Gank Stabber; kept, by who had me targeted", 1, true), "and the note")
		table.remove(Combat.db.deaths)
		local n = #A.printed
		A.slash("deathtest")
		check(#A.printed > n + 1 and A.printed[n + 1]:find("deathtest: the combat log is closed", 1, true), "/dt deathtest prints the notes")
	end)()
	A.env.UnitGUID = function(u) if u == "target" then return "Player-Zed" end return oldGUID(u) end
	A.env.UnitName = function(u) if u == "target" then return "Zed" end return oldName and oldName(u) end
	A.fire("PLAYER_TARGET_CHANGED")
	step(5)
	recapAt = 50
	A.fire("PLAYER_DEAD")
	eq(#Combat.db.deaths, deaths + 1, "a death by a player is recorded from the game's own recap")
	local d = Combat.db.deaths[#Combat.db.deaths]
	eq(d.killer, "Zed", "the last hit in it is the killer"); eq(d.with, "Pyroblast", "with what"); eq(d.amount, 500, "for how much")
	eq(d.assists[1] and d.assists[1][1], "Tiger", "the others in it helped"); eq(#d.hits, 2, "its hits are the recap"); eq(d.hits[1][3], "Melee", "a swing is melee")
	table.remove(Combat.db.deaths)
	;(function() -- a player I never saw: the hit's own GUID says it is one
		recapAt = 100
		local wasRecap = A.env.C_DeathRecap
		A.env.C_DeathRecap = { GetRecapEvents = function() return {
			{ timestamp = 300, event = "SWING_DAMAGE", sourceName = "Ghost Stalker", sourceGUID = "Player-9-ABCDEF", amount = 90 },
		} end }
		step(5)
		A.fire("PLAYER_DEAD")
		eq(#Combat.db.deaths, deaths + 1, "a death to a player never seen before is kept: the hit says who dealt it")
		local g = Combat.db.deaths[#Combat.db.deaths]
		eq(g.killer, "Ghost Stalker", "by name"); eq(g.player, true, "a player"); eq(g.guess, nil, "and no guess")
		table.remove(Combat.db.deaths)
		A.env.C_DeathRecap = wasRecap
	end)()
	table.remove(Combat.db.kills)
	A.env.UnitGUID, A.env.UnitName, A.env.C_DeathRecap, Combat.open = oldGUID, oldName, nil, wasOpen
	step(5)
end)()
-- (a recap's rows as text: "time ; who: what ; amount ; notes", colours taken out)
local function recapText(rec, isDeath)
	local out = {}
	for i, row in ipairs(Combat.Recap(rec, isDeath)) do
		out[i] = row.text or row.head or table.concat({ row.t, row.left, row.amount, row.note }, " ; ")
		check(row.left == nil or (type(row.icon) == "string" and row.icon ~= ""), "every table row has an icon")
	end
	return (table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local recapOf = recapText(death, true)
check(recapOf:find("425 damage taken in the last 10 seconds, from 3 attackers.", 1, true), "the recap totals the damage: " .. recapOf)
check(recapOf:find("1x ; Zed: Fireball ; 300 ; 71%, biggest 300, 1 critical", 1, true), "by ability, biggest first")
check(recapOf:find("-0.0 ; Zed: Ignite ; 60 ; killing blow", 1, true) and recapOf:find("-2.0 ; Zed: Fireball ; 300 ; critical", 1, true), "and hit by hit")
eq(Combat.Recap(death, true).title, "Killed by |cffff4040Zed|r", "headed by the killer"); eq(death.hits[1].i, 133, "the spell's number is kept for its icon")
check(recapText({ t = 0, zone = "Z", sub = "", killer = "Old", assists = {} }, true):find("from before the recap was kept", 1, true), "a death from before has none")
step(5)
log("ENVIRONMENTAL_DAMAGE", nil, nil, ME_GUID, "Alice", "Falling", 500)
log("UNIT_DIED", nil, nil, ME_GUID, "Alice")
eq(Combat.db.deaths[2].killer, "Falling", "a fall is its own killer"); eq(#Combat.db.deaths[2].assists, 0, "the earlier fight is not held against it")
do -- the recap also has heals, what was absorbed, resisted and blocked, overkill, attacks that did not land, debuffs, interrupts
	step(5)
	local TIGER = "Creature-0-1-2-3-99-0001"
	log("SPELL_AURA_APPLIED", "Player-Zed", "Zed", ME_GUID, "Alice", 118, "Polymorph", 64, "DEBUFF")
	log("SPELL_AURA_APPLIED", "Player-Bob", "Bob", ME_GUID, "Alice", 21562, "Fortitude", 2, "BUFF") -- (a buff is no part of it)
	log("SWING_MISSED", TIGER, "Tiger", ME_GUID, "Alice", "DODGE", false)
	log("SPELL_MISSED", "Player-Zed", "Zed", ME_GUID, "Alice", 133, "Fireball", 4, "ABSORB", false, 150)
	log("SPELL_HEAL", "Player-Bob", "Bob", ME_GUID, "Alice", 2061, "Flash Heal", 2, 250, 50, 0, true)
	log("SPELL_INTERRUPT", "Player-Zed", "Zed", ME_GUID, "Alice", 2139, "Counterspell", 64, 2061, "Flash Heal")
	log("SPELL_HEAL", ME_GUID, "Alice", "Player-Bob", "Bob", 2061, "Flash Heal", 2, 250, 0, 0, false)
	log("UNIT_DIED", nil, nil, "Player-Bob", "Bob") -- (a friend I healed is no kill of mine)
	log("SWING_DAMAGE", TIGER, "Tiger", ME_GUID, "Alice", 100, 40, 1, 20, 10, 30, false)
	log("UNIT_DIED", nil, nil, ME_GUID, "Alice")
	local rec = table.remove(Combat.db.deaths)
	eq(#Combat.db.kills, 0, "healing someone who then dies is no kill")
	eq(rec.killer, "Tiger", "only damage makes a killer: not the heal, not the spell that was absorbed"); eq(#rec.assists, 0, "nor a helper")
	eq(#rec.hits, 6, "all of it is kept, the buff aside")
	local all = recapText(rec, true)
	local function has(part, what) check(all:find(part, 1, true), what .. ": " .. all) end
	has("100 damage taken in the last 10 seconds, from 1 attacker.", "the damage is what landed")
	has("Healed for 200, and 50 more was overheal.", "heals, less the overheal")
	has("On top of that: 180 absorbed, 20 resisted, 10 blocked.", "what was soaked up")
	has("Not landed: 1 dodged.", "what I avoided")
	has("Tiger: Melee ; 100 ; 30 absorbed, 20 resisted, 10 blocked, overkill 40, killing blow", "the killing blow with its overkill")
	has("Bob: Flash Heal ; +200 ; critical, 50 overheal", "a heal")
	has("Zed: Polymorph ;  ; debuff put on me", "a debuff")
	has("Zed: Counterspell ;  ; interrupted my Flash Heal", "an interrupt")
	has("Zed: Fireball ; absorbed ; 150 damage", "a spell that was absorbed whole")
	has("Tiger: Melee ; dodged ; ", "a swing I dodged")
	has("Healing\n1x ; Bob: Flash Heal ; 200 ; 100%, biggest 200, 1 critical", "heals have their own totals")
	for _, row in ipairs(Combat.Recap(rec, true)) do
		if row.left and row.left:find("Bob", 1, true) then check(not row.left:find("ff4040", 1, true), "a healer is not in red") end
		if row.blow then eq(row.left, "|cffffffffTiger|r: Melee", "the killing blow is marked for its red line") end
	end
end
-- kills
log("SWING_DAMAGE", ME_GUID, "Alice", "Creature-0-1-2-3-55-0001", "Boar", 30)
log("PARTY_KILL", ME_GUID, "Alice", "Creature-0-1-2-3-55-0001", "Boar")
log("UNIT_DIED", nil, nil, "Creature-0-1-2-3-55-0001", "Boar")
log("SPELL_DAMAGE", ME_GUID, "Alice", "Player-Rex", "Rex", 116, "Frostbolt", 16, 200)
log("UNIT_DIED", nil, nil, "Player-Rex", "Rex")
log("UNIT_DIED", nil, nil, "Creature-0-1-2-3-56-0001", "Deer") -- nothing of mine
eq(#Combat.db.kills, 2, "what dies soon after I hit it is a kill of mine")
eq(Combat.db.kills[1].name, "Boar", "the boar"); eq(Combat.db.kills[1].blow, true, "by my own blow")
eq(Combat.db.kills[2].name, "Rex", "a player"); eq(Combat.db.kills[2].player, true, "marked as one"); eq(Combat.db.kills[2].blow, nil, "where I only helped")
eq(Combat.db.kills[2].with, "Frostbolt", "and what I last hit them with")
log("PARTY_KILL", ME_GUID, "Alice", "Player-Rex", "Rex")
eq(Combat.db.kills[2].blow, true, "a killing blow told after the death still counts")
check(recapText(Combat.db.kills[2]):find("200 damage from me in 1 hit, the killing blow among them.", 1, true), "a kill's recap is my own damage")
check(recapText(Combat.db.kills[2]):find("-0.0 ; Frostbolt ; 200 ; killing blow", 1, true), "hit by hit, without my name on every line")
log("SWING_DAMAGE", ME_GUID, "Alice", "Creature-0-1-2-3-57-0001", "Old Wolf", 5)
step(15)
log("UNIT_DIED", nil, nil, "Creature-0-1-2-3-57-0001", "Old Wolf")
eq(#Combat.db.kills, 2, "what dies long after is not mine")
-- the tab
A.slash("combat")
local function combatRows()
	local out = {}
	for _, w in ipairs(A.widgets) do
		if w.ccols and w.shown and w.data then out[#out + 1] = w.data end
	end
	return out
end
local function sideB(part)
	for _, w in ipairs(A.widgets) do
		if w.kind == "Button" and w.label and w.label.text and w.label.text:find(part, 1, true) then return w end
	end
end
click(sideB("Who killed me"))
Combat.search:SetText("")
Combat.Refresh()
check(sideB("Who killed me (2)") and sideB("Who did I kill (2)"), "both lists are offered as tabs, with their counts")
;(function() -- the third tab: everybody met, once each, with how often I killed them and they me
	local Combat = A.DT.Combat
	local kills, deaths = Combat.db.kills, Combat.db.deaths
	local now = os.time()
	kills[#kills + 1] = { t = now - 300, name = "Zed Foe", player = true, zone = "Ashenvale", sub = "", guild = "Bad Lot", blow = true }
	kills[#kills + 1] = { t = now - 200, name = "Zed Foe", player = true, zone = "Ashenvale", sub = "" }
	deaths[#deaths + 1] = { t = now - 100, killer = "Zed Foe", player = true, zone = "The Barrens", sub = "", assists = {} }
	local zed
	for _, p in ipairs(Combat.Players()) do if p.name == "Zed Foe" then zed = p end end
	eq(zed.kills, 2, "a player: how often I killed them"); eq(zed.deaths, 1, "and they me"); eq(zed.t, now - 100, "and when we last met")
	eq(zed.known.guild, "Bad Lot", "what was seen of them once is kept beside the last meeting")
	check(sideB("Players ("), "a third tab lists the players")
	click(sideB("Players ("))
	local row
	for _, w in ipairs(A.widgets) do
		if w.shown and w.data and w.data.player and w.data.player.name == "Zed Foe" then row = w end
	end
	check(row, "one row per player")
	check(row.data[1]:find("Zed Foe", 1, true) and row.data[1]:find("<Bad Lot>", 1, true), "with the guild"); eq(row.data[2], "|cff40ff402|r", "kills, green when ahead"); eq(row.data[3], "|cff40ff401|r", "deaths")
	check(row.data[5] == "The Barrens", "and where we last met")
	row.scripts.OnMouseUp(row)
	check(sideB("Who did I kill"), "a click goes to the fights"); eq(Combat.search:GetText(), "Zed Foe", "of that player")
	Combat.search:SetText("")
	table.remove(kills); table.remove(kills); table.remove(deaths)
	click(sideB("Who killed me"))
end)()
local shownDeaths = combatRows()
eq(#shownDeaths, 2, "my deaths are listed")
local zedRow
for _, d in ipairs(shownDeaths) do if d.rec == death then zedRow = d end end
eq(zedRow[2], "|cffff4040Zed|r", "a player in red"); eq(zedRow[3], "Ignite (60)", "what with"); eq(zedRow[4], "Nesingwary's Expedition, Stranglethorn Vale", "where")
eq(zedRow[5], "|cffffffffTiger|r 40, |cffffffffFang (pet)|r 25", "who helped")
check(text("2 deaths, 1 of them to players. Most often:"), "and a summary")
for _, w in ipairs(A.widgets) do
	if w.ccols and w.data == zedRow then
		A.env.GameTooltip.lines = {}
		w.scripts.OnEnter(w)
		local tip = table.concat(A.env.GameTooltip.lines, " | ")
		check(tip:find("(35.7, 10.5)", 1, true) and tip:find("Killed by Zed (a player), with Ignite for 60", 1, true) and tip:find("Helped: Tiger, 40 damage", 1, true), "the tooltip has the details: " .. tip)
	end
end
for _, w in ipairs(A.widgets) do
	if w.ccols and w.data == zedRow then w.scripts.OnMouseUp(w) end
end
check(text("Killed by |cffff4040Zed|r") and text("damage taken in the last 10 seconds") and text("|cffff4040Zed|r: Ignite"),"a click on a death opens its recap")
Combat.search:SetText("falling")
step(1)
eq(#combatRows(), 1, "the search box finds a death by its killer")
Combat.search:SetText("")
step(1)
click(sideB("Who did I kill"))
eq(#combatRows(), 2, "my kills"); check(text("2 kills, 1 of them of players."), "with their summary")
for _, w in ipairs(A.widgets) do
	if w.kind == "CheckButton" and w.scripts.OnClick and w.shown ~= false then
		for _, other in ipairs(A.widgets) do
			if other.kind == "FontString" and other.text == "Players only" then w.playersBox = true end
		end
	end
end
local onlyBox
for i, w in ipairs(A.widgets) do
	if w.kind == "FontString" and w.text == "Players only" then onlyBox = A.widgets[i - 1] end -- (its box was made just before its label)
end
onlyBox.checked = true
click(onlyBox)
eq(#combatRows(), 1, "players only"); eq(combatRows()[1].rec.name, "Rex", "leaves the boar out")
onlyBox.checked = false
click(onlyBox)
eq(A.DT.modules.combat.hello, nil, "the module has nothing to say to the guild")
-- the bar: Combat stands apart from the tabs before it
local tabX = {}
for _, w in ipairs(A.widgets) do
	if w.kind == "Button" and w.id and w.x and w.shown then tabX[w.id] = w.x end
end
eq(tabX.world - tabX.craft, 88, "tabs of one group stand side by side"); eq(tabX.combat - tabX.world, 102, "a new group stands apart"); eq(tabX.tools - tabX.combat, 102, "and Tools behind a separator of its own")

-- places: Fish and Food are sub-tabs of Craft, NPC and Quests of World
do
	local UI = A.DT.UI
	local function place(id) for _, tab in ipairs(UI:TabList(true)) do if tab.id == id then return tab end end end
	local craft, world = place("craft"), place("world")
	check(craft and world and not place("fish") and not place("npc"), "Craft and World are on the bar; their sub-tabs are not")
	eq(craft.subs[1].id .. " " .. craft.subs[2].id, "fish food", "Craft holds Fish and Food"); eq(world.subs[1].id .. " " .. world.subs[2].id, "npc quest", "World holds NPC and Quests")
	A.slash("food")
	eq(A.DT.db.lastTab, "craft", "/dt food opens Craft"); eq(craft.current, "food", "on the Food sub-tab")
	eq(craft.buttons[1].text, "Fish", "with a row of its sub-tabs"); eq(craft.buttons[2].text, "Food", "both")
	click(craft.buttons[1])
	eq(craft.current, "fish", "a click on a sub-tab shows it"); eq(craft.panels.food.shown, false, "and hides the other"); eq(craft.panels.fish.shown, true, "its own panel")
	A.slash("market")
	A.slash("craft")
	eq(craft.current, "fish", "back at Craft: the sub-tab last used there"); eq(A.DT.db.tabs.sub.craft, "fish", "which is saved")
	A.env.SlashCmdList.DAWNTOOLS_QUEST()
	eq(A.DT.db.lastTab, "world", "a module's short command opens its place"); eq(world.current, "quest", "on its sub-tab")
	check(UI:HasTab("npc") and UI:HasTab("world") and not UI:HasTab("nothing"), "a sub-tab can be asked for by name like any tab")
end

-- Zones: levels and side worked out from the NPCs; what a zone has
do
	local Zed = NewClient("Zed")
	Zed.DT.db.settings.background = false
	local NPCS, QUESTS, ITEMDB = {}, {}, {}
	local function mob(id, level, zone, extra)
		NPCS[id] = { name = "Mob " .. id, minLevel = level, maxLevel = level, rank = 0, zoneID = zone, friendlyToFaction = "", npcFlags = 0, spawns = { [zone] = { { 50, 50 } } } }
		for k, v in pairs(extra or {}) do NPCS[id][k] = v end
	end
	for i, level in ipairs({ 3, 10, 11, 12, 13, 14, 15, 16, 17, 40 }) do mob(i, level, 17) end -- The Barrens: one stray low and one stray high
	mob(20, 30, 17, { name = "Innkeeper Wiley", friendlyToFaction = "H", npcFlags = 128 })
	mob(21, 30, 17, { name = "Devrak", friendlyToFaction = "H", npcFlags = 8 })
	mob(22, 30, 17, { name = "Wrahk", friendlyToFaction = "H", npcFlags = 4 })
	mob(23, 30, 17, { name = "Jahan", friendlyToFaction = "H", npcFlags = 4 + 16384 })
	mob(24, 30, 17, { name = "Captain Fairmount", friendlyToFaction = "A", npcFlags = 2 })
	mob(25, 24, 17, { name = "Old Greyfin", rank = 4 })
	mob(30, 55, 1519, { name = "Innkeeper Allison", friendlyToFaction = "A", npcFlags = 128 })
	mob(31, 55, 1519, { name = "Stormwind Vendor", friendlyToFaction = "A", npcFlags = 4 })
	for i, level in ipairs({ 30, 33, 35 }) do mob(40 + i, level, 33) end
	mob(45, 40, 33, { name = "Horde Trader", friendlyToFaction = "H", npcFlags = 4 })
	mob(46, 40, 33, { name = "Alliance Trader", friendlyToFaction = "A", npcFlags = 4 })
	for i, level in ipairs({ 17, 18, 20 }) do mob(50 + i, level, 718) end
	mob(54, 9999, 718, { name = "Boss Trigger" })                       -- (a "level" that is none)
	mob(55, 19, 718, { name = "Elite Guard", rank = 1, spawns = {} })   -- (an elite with no place on the map, as dungeon mobs are)
	mob(56, 19, 718, { name = "Deviate Faerie Dragon", rank = 4, spawns = { [718] = { { -1, -1 } } } }) -- (a rare inside: its "spot" is none)
	mob(57, 1, 17, { name = "Rabbit" })
	mob(58, 1, 17, { name = "Rat" })
	mob(60, 1, 9001, { name = "Lost Soul", spawns = {} })               -- (a place with one stray NPC and nothing else)
	for i = 1, 5 do QUESTS[10 + i] = { name = "Jungle Quest " .. i, requiredLevel = 30, questLevel = 30 + i * 2, zoneOrSort = 33 } end
	local ids = {}
	for id in pairs(NPCS) do ids[#ids + 1] = id end
	table.sort(ids)
	QUESTS[1] = { name = "Raptor Thieves", requiredLevel = 5, questLevel = 12, zoneOrSort = 17 }
	QUESTS[2] = { name = "Plainstrider Menace", requiredLevel = 5, questLevel = 11, zoneOrSort = 17 }
	QUESTS[3] = { name = "Too High Yet", requiredLevel = 30, questLevel = 30, zoneOrSort = 17 }
	ITEMDB[900] = { name = "Raptor Hide", npcDrops = { 2 } }
	ITEMDB[901] = { name = "Pearl", objectDrops = { 55 } }
	ITEMDB[902] = { name = "Elsewhere", npcDrops = { 41 } }
	local function entity(tbl, list)
		return {
			GetAllIds = function() return list end,
			GetAll = function(id, keys)
				local out = {}
				for i, key in ipairs(keys) do out[i] = tbl[id][key] end
				return out
			end,
			Get = function(id, key) return tbl[id] and tbl[id][key] end,
		}
	end
	Zed.env.LibQuestieDB = {
		RequireContract = function(v) return v == 4 end,
		Enum = { npcFlags = { QUEST_GIVER = 2, VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, INNKEEPER = 128, REPAIR = 16384 } },
		Npc = entity(NPCS, ids), Quest = entity(QUESTS, { 1, 2, 3, 11, 12, 13, 14, 15 }), Item = entity(ITEMDB, { 900, 901, 902 }),
		Object = { Get = function(id, key) return id == 55 and ({ name = "Giant Clam", zoneID = 17 })[key] or nil end },
	}
	local AREAS = { [17] = "The Barrens", [1519] = "Stormwind City", [33] = "Stranglethorn Vale", [718] = "Wailing Caverns", [9001] = "Nowhere Much" }
	Zed.env.C_Map = { GetAreaInfo = function(area) return AREAS[area] end, GetMapInfo = function(map) return map ~= 226 and { mapID = map } or nil end }
	Zed.env.QuestieLoader = { ImportModule = function() return {
		GetUiMapIdByAreaId = function(_, area) return ({ [17] = 1413, [33] = 1434, [718] = 226 })[area] end, -- (226: a map this game has not)
		IsDungeonZone = function(area) return area == 718 end, -- (as Questie has it: a plain function that takes the number alone)
		GetDungeons = function() return { [718] = { "Wailing Caverns", {}, 17, { { 17, 46.0, 36.3 } } } } end,
		GetDungeonLocation = function(_, area) return area == 718 and { { 17, 46.0, 36.3 } } or nil end,
		GetParentZoneId = function() return nil end,
	} end }
	local qdone = { [2] = true }
	Zed.env.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return qdone[id] or false end, IsOnQuest = function() return false end }
	local tom
	Zed.env.TomTom = { AddWaypoint = function(_, map, x, y, opts) tom = { map, x, y, opts.title } end }
	local gm = { gmdbs = { ["Herb Gathering"] = { [1413] = { [1] = 401, [2] = 401, [3] = 402 } }, Mining = {} },
		GetNameForNode = function(_, _, id) return ({ [401] = "Peacebloom", [402] = "Silverleaf" })[id] end }
	local stub = Zed.env.LibStub
	Zed.env.LibStub = setmetatable({}, { __call = function(_, name, silent)
		if name == "AceAddon-3.0" then return { GetAddon = function() return gm end } end
		return stub(name, silent)
	end })
	Zed.env.DawnMarket.API.Each = function(fn) fn(900, 5000, 1, 0) fn(901, 20000, 1, 0) fn(902, 99999, 1, 0) end
	local Zone = Zed.DT.Zone
	Zed.DT.Npc.BATCH, Zed.DT.Quest.BATCH, Zed.DT.Item.BATCH = 10, 10, 10
	local function ztext(part)
		for _, w in ipairs(Zed.widgets) do
			if w.kind == "FontString" and w.shown ~= false and type(w.text) == "string" and w.text:find(part, 1, true) then return w.text end
		end
	end
	Zed.slash("zone")
	check(ztext("Reading NPCs and quests"), "the Zones tab reads the NPCs and quests it is worked out from")
	step(2)
	check(ztext("3 of 4 zones"), "then lists the zones, dungeons left out to begin with")
	local barrens, sw, stv, wc = Zone.Get("The Barrens"), Zone.Get("Stormwind City"), Zone.Get("Stranglethorn Vale"), Zone.Get("Wailing Caverns")
	eq(barrens.lo, 10, "levels from the zone's ordinary mobs, the stray low one and the level-1 critters left out"); eq(barrens.hi, 17, "and the stray high one")
	eq(barrens.by, "mobs", "from its mobs, having few quests"); eq(stv.by, "quests", "a zone with quests enough: from the levels of its quests")
	eq(Zone.Get("Nowhere Much").junk, true, "a place with one stray NPC and no quest is not listed")
	eq(Zone.Levels(barrens), "10-17", "shown plainly (that they are estimates is said once, on the right)"); eq(barrens.side, "Horde", "four Horde service NPCs to one Alliance quest giver: Horde's")
	eq(sw.side, "Alliance", "only Alliance's people: Alliance's"); eq(Zone.Levels(sw), "", "no mobs: no levels")
	eq(stv.side, "Contested", "both sides' people, about even: contested"); eq(Zone.Levels(stv), "32-40", "its levels, by its quests")
	eq(wc.dungeon, true, "a dungeon is known as one"); eq(wc.hi, 20, "a 9999 that is no level does not stretch its levels"); eq(#wc.levels, 4, "and its elites count, placed or not"); eq(#barrens.rares, 1, "the zone's rares"); eq(barrens.services.Vendor, 2, "and its services, counted")
	local function zrows()
		local out = {}
		for _, w in ipairs(Zed.widgets) do
			if w.zcols and w.shown and w.data then out[#out + 1] = w end
		end
		return out
	end
	local function znames()
		local out = {}
		for i, w in ipairs(zrows()) do out[i] = w.data.z.name end
		return table.concat(out, ", ")
	end
	eq(znames(), "The Barrens, Stranglethorn Vale, Stormwind City", "lowest levels first, those without levels last")
	eq(zrows()[1].zcols[2].text, "|cffffff0010-17|r", "the levels coloured for my own level (10: about right)"); eq(zrows()[1].zcols[3].text, "|cffff5050Horde|r", "and whose it is")
	eq(zrows()[2].zcols[2].text, "|cffff404032-40|r", "far above me: red")
	Zone.dungeonBox.checked = true
	click(Zone.dungeonBox)
	eq(#zrows(), 4, "Show dungeons: the dungeon is listed"); check(ztext("Dungeon|r"), "marked as one")
	eq(znames(), "The Barrens, Wailing Caverns, Stranglethorn Vale, Stormwind City", "under the zone its door is in")
	eq(zrows()[2].zcols[1].text, "    |cff666666> |r|cffc080ffWailing Caverns|r", "indented beneath it"); eq(wc.parent, barrens, "its zone known")
	-- the side
	click(Zone.sideButton)
	click(Zone.sideButton.menu.rows[2])
	eq(Zone.db.side, "Horde", "a side picked from the list"); eq(znames(), "The Barrens, Wailing Caverns", "Horde's zones, with the dungeons in them")
	eq(Zone.sideButton.label.text, "Horde", "named on the button")
	click(Zone.sideButton)
	click(Zone.sideButton.menu.rows[4])
	eq(znames(), "Stranglethorn Vale", "the contested ones: a dungeon whose zone is filtered out is not shown")
	click(Zone.sideButton)
	click(Zone.sideButton.menu.rows[1])
	eq(#zrows(), 4, "any side again")
	Zone.search:SetText("wailing")
	step(1)
	eq(znames(), "Wailing Caverns", "a dungeon found on its own stands at the edge"); eq(zrows()[1].zcols[1].text, "|cffc080ffWailing Caverns|r", "not indented under a zone that is not listed")
	Zone.search:SetText("")
	step(1)
	Zone.mineBox.checked = true
	click(Zone.mineBox)
	eq(znames(), "The Barrens, Wailing Caverns", "For my level: only zones about my level, each with its dungeons")
	Zone.mineBox.checked = false
	click(Zone.mineBox)
	Zone.search:SetText("strangle")
	step(1)
	eq(znames(), "Stranglethorn Vale", "the search box finds a zone")
	Zone.search:SetText("")
	step(1)
	-- the zone picked
	local function zrow(name) for _, w in ipairs(zrows()) do if w.data.z.name == name then return w end end end
	click(zrow("The Barrens"))
	eq(Zone.right.title.text, "The Barrens", "a click shows the zone on the right"); check(Zone.right.sub.text:find("Levels 10-17", 1, true), "with its levels")
	local opened
	Zed.env.OpenWorldMap = function(map) opened = map end
	eq(Zone.right.map.shown, true, "a Map button stands top right of the zone")
	click(Zone.right.map)
	eq(opened, 1413, "it opens the game's map on that zone")
	opened = nil
	Zed.combat = true
	click(Zone.right.map)
	eq(opened, nil, "not in combat (the game forbids it)"); check(Zed.printed[#Zed.printed]:find("in combat", 1, true), "it says so")
	Zed.combat = false
	eq(Zone.MapOf(wc), 1413, "a dungeon without a map of its own: the map of the zone its door is in")
	click(zrow("Stormwind City"))
	eq(Zone.right.map.shown, false, "no button where no map is known")
	click(zrow("The Barrens"))
	local function zlines()
		local out = {}
		for i, d in ipairs(Zone.Lines(barrens)) do out[i] = (d.head and ("# " .. d.head) or d.text) end
		return (table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	local function zline(part)
		for _, d in ipairs(Zone.Lines(barrens)) do
			if (d.head or d.text):find(part, 1, true) then return d end
		end
	end
	local text = zlines()
	check(text:find("# Quests\n1 open to you, 1 not yet, 1 done, 3 in all", 1, true), "its quests, by where they stand for me: " .. text)
	check(text:find("# Dungeons\nWailing Caverns  17-20", 1, true), "the dungeon whose door is here, with its levels")
	check(text:find("# Rare mobs (1)\nOld Greyfin  level 24", 1, true), "its rares")
	check(text:find("3 in all  (show them)\n\n# Dungeons", 1, true), "the blocks set apart by a line of air")
	check(text:find("Flight master  1", 1, true) and text:find("Innkeeper  1", 1, true) and text:find("Vendor  2", 1, true) and text:find("Repairs  1", 1, true), "its services")
	check(text:find("# Fish  fishing skill 75", 1, true), "what bites, from the Fish tab")
	check(text:find("Herbs: Peacebloom 2, Silverleaf 1", 1, true), "its herbs, counted from GatherMate2's store, commonest first")
	check(text:find("Ore: none recorded", 1, true), "and a word where there are none")
	check(text:find("Leather: Light Leather, Medium Leather  (by the level of its mobs)", 1, true), "leather by the level of its mobs")
	check(text:find("Working it out", 1, true), "the dearest drops take a moment")
	step(1)
	text = zlines()
	check(text:find("Pearl  2g 0s 0c  Giant Clam\nRaptor Hide  50s 0c  Mob 2", 1, true), "then they are listed, dearest first, with what drops them: " .. text)
	check(not text:find("Elsewhere", 1, true), "what drops in another zone is not among them")
	eq(zline("Pearl").item, 901, "a drop's line knows its item")
	Zone.Refresh()
	Zone.right.scripts.OnMouseWheel(Zone.right, -10) -- (the drops are at the foot of the panel: scrolled to)
	local pearlRow
	for _, row in ipairs(Zone.right.rows) do if row.shown and row.data and row.data.item == 901 then pearlRow = row end end
	Zed.env.GameTooltip.lines = {}
	pearlRow.scripts.OnEnter(pearlRow)
	eq(Zed.env.GameTooltip.lines[1], "item:901", "hovering it shows the item's own tooltip")
	-- the clicks
	zline("show them").click()
	eq(Zed.DT.Quest.db.zone, "The Barrens", "a click on the quests: the Quests tab on this zone"); eq(Zed.DT.db.lastTab, "world", "opened")
	Zed.slash("zone")
	zline("Vendor").click()
	eq(Zed.DT.Npc.db.zone, "The Barrens", "a click on a service: the NPC tab on this zone"); eq(Zed.DT.Npc.db.types.Vendor, true, "and that kind")
	Zed.slash("zone")
	zline("Wailing Caverns").click()
	eq(tom[1], 1413, "a click on a dungeon: a waypoint to its door"); eq(tom[4], "Wailing Caverns", "named"); eq(tom[2], 0.46, "at the door")
	zline("Old Greyfin").click()
	eq(tom[4], "Old Greyfin", "a click on a rare: a waypoint to it")
	gm.gmdbs = nil
	check(zlines():find("Herbs and ore: needs the GatherMate2 addon", 1, true), "without GatherMate2 the block says what it needs, once")
	-- a mob inside a dungeon has no spot of its own, and the dungeon no map here: the waypoint goes to its door
	local dragon
	for _, r in ipairs(Zed.DT.Npc.Find("deviate", {})) do dragon = r.e end
	tom = nil
	Zed.DT.Npc.Waypoint(dragon)
	eq(tom[1], 1413, "a mob inside a dungeon: the waypoint goes to the dungeon's door, on the map outside"); eq(tom[2], 0.46, "at the door")
	check(Zed.printed[#Zed.printed]:find("the door of the dungeon it is in", 1, true), "and chat says that is what it is")
	;(function() -- QuestieDB without Questie: the map of a zone comes from QuestieDB's own table
		local loader = Zed.env.QuestieLoader
		Zed.env.QuestieLoader = nil
		Zed.env.loadstring = _G.load -- (the game has loadstring; "load" alone is a helper of this file)
		Zed.env.LibQuestieDB.Support = { Get = function(name) return name == "ZoneDB" and { private = { areaIdToUiMapId = "return { [4242] = 1453 }" } } or nil end }
		Zed.env.C_Map.GetMapInfo = function(map) return { mapID = map } end
		eq(Zed.DT.Npc.MapOf(4242), 1453, "without Questie, QuestieDB's own table gives a zone's map")
		Zed.env.QuestieLoader = loader
	end)()
	eq(Zed.DT.Npc.MapOf(718), nil, "a map this game does not have is no map")
	eq(Zed.DT.db.zone.last, "The Barrens", "the zone last looked at is remembered"); eq(Zed.DT.modules.zone.hello, nil, "the module has nothing to say to the guild")
	leave(Zed)
end

-- Settings in sections, and profiles
do
	local Pia = NewClient("Pia")
	local UI, P, db = Pia.DT.UI, Pia.DT.Profiles, Pia.DT.db
	local reloads = 0
	Pia.env.ReloadUI = function() reloads = reloads + 1 end
	Pia.env.GetRealmName = function() return "Forever" end
	-- sections
	Pia.slash("settings")
	local titles = {}
	for i, b in ipairs(UI.sectionButtons) do titles[i] = (b.label.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	eq(table.concat(titles, " / "), "General / Profiles / Tabs & Modules / Market / Food", "the Settings tab lists its sections: the fixed ones, then one per module with switches")
	eq(db.settingsSection, "general", "General to begin with"); eq(UI.sectionPanels.general.shown, true, "its panel shown"); eq(UI.sectionPanels.profiles.shown, false, "the others not")
	click(UI.sectionButtons[2])
	eq(db.settingsSection, "profiles", "a click shows a section"); eq(UI.sectionPanels.profiles.shown, true, "its panel"); eq(UI.sectionPanels.general.shown, false, "the last one hidden")
	Pia.slash("market")
	Pia.slash("settings")
	eq(db.settingsSection, "profiles", "the section last looked at is remembered")
	-- profiles: what is set up, never what was collected
	eq(P.Current(), "Default", "every character is on Default to begin with"); eq(table.concat(P.List(), ","), "Default", "the only profile")
	local range, market = db.range, db.market
	range.settings.on, range.size, range.mark = true, 22, 30
	db.tabs.hidden.combat = true
	market.favs[100] = true
	eq(P.New("Raid"), "Raid", "a new profile: a copy of how things are now"); eq(select(2, P.New("raid")), "There is a profile \"raid\" already.", "names are taken once, whatever the case")
	eq(P.New(""), nil, "a profile needs a name"); eq(P.New(("x"):rep(40)), nil, "not too long a one")
	eq(P.New("Bare", true), "Bare", "another, with everything at its default")
	eq(table.concat(P.List(), ","), "Default,Bare,Raid", "listed, Default first")
	eq(reloads, 0, "making profiles switches nothing")
	-- switch: the live values go to their profile, the other's come in, the interface reloads
	range.size = 12 -- (changed after Raid was copied: belongs to Default)
	P.Use("Raid")
	eq(reloads, 1, "using another profile reloads the interface"); eq(db.profile, "Raid", "it is the one held now"); eq(db.profileOf["Pia-Forever"], "Raid", "and this character's")
	eq(db.range.size, 22, "its values are in the live tables"); eq(db.range.settings.on, true, "settings too"); eq(db.tabs.hidden.combat, true, "and the tabs")
	eq(db.profiles.Default.mods.range.keys.size, 12, "what was live is kept under its own profile")
	eq(db.market.favs[100], true, "favourites and the like are not part of any profile"); check(db.market.houses, "nor is what was collected touched")
	P.Use("Bare")
	eq(db.range.size, nil, "an empty profile: nothing set (the modules fill in their defaults on load)"); eq(next(db.range.settings), nil, "no settings either")
	eq(db.tabs, nil, "nor tabs: the core sets them up anew"); eq(db.market.favs[100], true, "and still nothing collected is lost")
	P.Use("Default")
	eq(db.range.size, 12, "back on Default: as it was left"); eq(db.profileOf["Pia-Forever"], nil, "Default needs no entry")
	-- rename and delete
	eq(P.Rename("Default", "Main"), nil, "Default keeps its name"); eq(P.Rename("Raid", "Bare"), nil, "no renaming onto another")
	db.profileOf["Alt-Forever"] = "Raid"
	eq(P.Rename("Raid", "Raiding"), "Raiding", "a profile renamed"); eq(db.profileOf["Alt-Forever"], "Raiding", "characters on it follow")
	eq(P.Delete("Default"), nil, "Default cannot be deleted")
	P.Use("Raiding")
	eq(P.Delete("Raiding"), nil, "nor the one in use")
	P.Use("Default")
	eq(P.Delete("Raiding"), true, "another can"); eq(db.profileOf["Alt-Forever"], nil, "its characters are on Default again"); eq(db.profiles.Raiding, nil, "gone")
	-- export and import
	range.size, range.pos = 18, { target = { "CENTER", "CENTER", 10.5, -20 } }
	local text = P.Export("Default")
	check(type(text) == "string" and text:sub(1, 4) == "DT1:", "a profile exports as text")
	local name = P.Import(text)
	eq(name, "Imported", "and imports under a name of its own"); eq(P.Current(), "Default", "without being switched to")
	local got = db.profiles.Imported
	eq(got.mods.range.keys.size, 18, "with its values"); eq(got.mods.range.keys.pos.target[3], 10.5, "nested ones and fractions too"); eq(got.mods.range.settings.on, true, "and settings")
	eq(got.top.tabs.hidden.combat, true, "and the tabs")
	eq(P.Import(text), "Imported 2", "a second import gets the next name")
	eq(P.Import("hello"), nil, "something that is no profile is refused"); eq(select(2, P.Import("hello")):find("not a DawnTools profile") ~= nil, true, "with a word why")
	eq(P.Import("DT1:zz"), nil, "a damaged text is refused"); eq(P.Import("DT1:" .. ("ab"):rep(150000)), nil, "and one far too long")
	-- only what a profile may hold is taken in, and nothing in it is run
	local LD = Pia.env.LibStub("LibDeflate")
	local function pack(plain) return "DT1:" .. LD:EncodeForPrint(LD:CompressDeflate(plain)) end
	local evil = pack("{s1:vn1;s3:top{s8:settings{s10:backgroundF}s6:houses{n1;n2;}}s4:mods{s5:range{s8:settings{}s4:keys{s4:sizen9;s5:chars{}}}s7:nothing{}}}")
	local stored, whyNot = P.Import(evil, "Odd")
	if not stored then print("import: " .. tostring(whyNot)) end
	eq(stored, "Odd", "a hand-made text of the right shape is read")
	eq(db.profiles.Odd.top.settings.background, false, "what belongs in a profile is taken"); eq(db.profiles.Odd.top.houses, nil, "a key that does not is dropped")
	eq(db.profiles.Odd.mods.range.keys.size, 9, "a module's own keys are taken"); eq(db.profiles.Odd.mods.range.keys.chars, nil, "others not"); eq(db.profiles.Odd.mods.nothing, nil, "nor modules there are not")
	eq(P.Import(pack("{s1:vn1;s3:top{}s4:mods"), "Cut"), nil, "a text cut short is refused")
	eq(P.Import(pack(("{s1:a"):rep(20) .. ("}"):rep(20)), "Deep"), nil, "and one nested without end")
	eq(P.Import(pack("{s1:vn2;s3:top{}s4:mods{}}"), "Later"), nil, "and one of a version not known")
	-- what is of the wrong kind is left out (a number where a table belongs would break the next login), and
	-- nobody else's text answers for me on sharing
	local wrong = P.Import(pack("{s1:vn1;s3:top{s8:settingsn5;s4:tabss3:abcs3:posn1;s7:lastTab{}}s4:mods{s5:range{s8:settings{s2:onTs4:sizen3;}s4:keys{s3:posn7;s4:sizes3:big}}s6:market{s8:settings{s5:shareTs7:tooltipF}s4:keys{}}}}"), "Wrong")
	eq(wrong, "Wrong", "a text with values of the wrong kind is still read")
	local w = db.profiles.Wrong
	eq(w.top.settings, nil, "but a number where the settings belong is left out"); eq(w.top.tabs, nil, "a text where the tabs belong"); eq(w.top.pos, nil, "a number for a place"); eq(w.top.lastTab, nil, "a table for a name")
	eq(w.mods.range.settings.on, true, "a module's switches are taken"); eq(w.mods.range.settings.size, nil, "what is no switch is not")
	eq(w.mods.range.keys.pos, nil, "a module's own key of the wrong kind is left out"); eq(w.mods.range.keys.size, nil, "likewise")
	eq(w.mods.market.settings.share, nil, "sharing with the guild is never switched on by somebody's text"); eq(w.mods.market.settings.tooltip, false, "other switches are")
	-- the section itself
	UI:ShowSection("profiles")
	local shown = {}
	for _, row in ipairs(P.rows) do if row.shown then shown[#shown + 1] = (row.label.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end end
	eq(table.concat(shown, ","), "> Default,   Bare,   Imported,   Imported 2,   Odd,   Wrong", "the section lists the profiles, the one in use marked")
	eq(P.rows[1].use.enabled, false, "the one in use cannot be 'used'"); eq(P.rows[1].delete.enabled, false, "nor Default deleted"); eq(P.rows[2].delete.enabled, true, "another can")
	click(P.rows[2].use)
	eq(Pia.popups[#Pia.popups], "DAWNTOOLS_PROFILE_USE", "Use asks first, as the interface reloads")
	click(P.rows[2].export)
	eq(Pia.popups[#Pia.popups], "DAWNTOOLS_COPY", "Export shows the text to copy")
	click(P.newCopy)
	eq(Pia.popups[#Pia.popups], "DAWNTOOLS_PROFILE_TEXT", "New asks for a name")
	Pia.env.StaticPopupDialogs.DAWNTOOLS_PROFILE_TEXT.OnAccept({ editBox = { GetText = function() return "Third" end } })
	check(db.profiles.Third, "and makes the profile"); check(P.message.text:find("Third", 1, true), "saying so")
	click(P.newCopy)
	Pia.env.StaticPopupDialogs.DAWNTOOLS_PROFILE_TEXT.OnAccept({ editBox = { GetText = function() return "third" end } })
	check(P.message.text:find("already", 1, true), "or why not")
	leave(Pia)
	-- another character, on another profile, gets its own values at login
	local saved = Pia.env.DawnToolsDB
	saved.profileOf["Quin-Forever"] = "Odd"
	local Quin = NewClient("Quin", { db = saved, globals = function(env) env.GetRealmName = function() return "Forever" end end })
	eq(Quin.DT.db.profile, "Odd", "a character with a profile of its own: its values are brought in at login")
	eq(Quin.DT.db.range.size, 9, "before the modules start"); eq(Quin.DT.db.settings.background, false, "the core's settings too")
	eq(Quin.DT.db.profiles.Default.mods.range.keys.size, 18, "the other character's are stored away under its profile")
	eq(Quin.DT.db.range.settings.on, false, "what the profile does not say is at its default"); eq(Quin.DT.db.market.favs[100], true, "and what was collected is everybody's")
	leave(Quin)
end

print(("ok: %d checks passed"):format(checks))
