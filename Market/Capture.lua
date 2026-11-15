-- DawnMarket :: Capture
-- Records auction prices from what the player already sees: it listens to the results of searches and scans
-- that the player, or any addon they run, started. On its own it never asks the auction house for anything;
-- the one scan it can run is started by the player's click (M:Scan).
-- Also the price lookups the other tabs use (DawnMarket.API).

local _, DT = ...
local L = DT.Logic
local M = { items = {}, callbacks = {} }
DT.Market = M

local REFRESH = 900         -- an unchanged price is recorded again after this long, so its age stays honest
local AUCTIONATOR = "Auctionator"
local AH = C_AuctionHouse

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local touched = false
-- tells the window and the API's listeners, once for a burst of changes
function M:Touch()
	if touched then return end
	touched = true
	C_Timer.After(0.5, function()
		touched = false
		DT:Fire("DT_MARKET_UPDATE")
		for _, fn in ipairs(M.callbacks) do
			local ok, err = pcall(fn)
			if not ok then geterrorhandler()(err) end
		end
	end)
end

---------------------------------------------------------------------------
-- Houses
---------------------------------------------------------------------------
-- Prices are kept per auction house: "H" / "A" (a faction's own) and "X" (the cross-faction one); db.houses[key]
-- is that house's item table. M.at: the house the player stands at (nil away from one). M.view: the house
-- shown in the window, on tooltips and to the other tabs; M.items is its table.

M.HOUSE_NAMES = { H = "Horde", A = "Alliance", X = "X-Faction" }

function M:House(key)
	local houses = self.db.houses
	houses[key] = houses[key] or {}
	return houses[key]
end

function M:SetView(key)
	self.view, self.db.view = key, key
	self.items = self:House(key)
	self:Touch()
end

-- which auctioneer this is: its NPC id, or the place where the game gives none
local function Auctioneer()
	local guid = UnitGUID and UnitGUID("npc")
	local sub, zone = GetSubZoneText and GetSubZoneText(), GetZoneText and GetZoneText()
	return guid and guid:match("%-(%d+)%-%x+$") or (sub and sub ~= "" and sub) or zone or "?"
end

-- The house the player named for this auctioneer wins. Otherwise an auctioneer of the other faction, or of
-- none, is the cross-faction house.
-- ponytail: rests on the auctioneer's faction as the game reports it (not reported = my own house). If Forever
-- reports it otherwise, the "Here:" button on the Market tab sets it right, once per auctioneer.
local function Detect()
	local known = M.db.auctioneers[Auctioneer()]
	if known then return known end
	local theirs = UnitFactionGroup and UnitFactionGroup("npc")
	if theirs and theirs ~= UnitFactionGroup("player") then return "X" end
	-- the goblin towns' auctioneers report no faction at all: known by the place
	-- ponytail: English place names; another language's client uses the "Here:" button
	local sub, zone = GetSubZoneText and GetSubZoneText() or "", GetZoneText and GetZoneText() or ""
	for _, town in ipairs({ "Booty Bay", "Gadgetzan", "Everlook" }) do
		if sub:find(town, 1, true) or zone:find(town, 1, true) then return "X" end
	end
	return M.faction
end

-- the player says which house this auctioneer is: remembered for it
-- ponytail: prices recorded here under the wrong house before that stay where they are until they age out
function M:SetAt(key)
	if not self.at then return end
	self.db.auctioneers[Auctioneer()] = key
	self.at = key
	self:SetView(key)
end

-- where what the player sees right now belongs
local function Here()
	return M.at or M.view
end

-- Item names and classes, for the search box. The game may not know an item yet: those are asked for a few
-- at a time and filled in when GET_ITEM_INFO_RECEIVED says so (or when a row showing them is drawn).
local queue, queued = {}, {}

local function Info(id)
	for _, items in pairs(M.db.houses) do
		local item = items[id]
		if item and not (item.n and item.s and item.e) then
			local name, _, _, _, _, _, _, _, slot, _, _, class, sub = C_Item.GetItemInfo(id)
			if not name then return false end
			-- name, class, subclass, and where it is worn ("INVTYPE_HEAD"; "" for what is not worn)
			item.n, item.c, item.s, item.e = name, class, sub or 0, slot or ""
		end
	end
	return true
end

local function Pump()
	for _ = 1, 25 do
		local id = table.remove(queue)
		if not id then return end
		if Info(id) then queued[id] = nil else C_Item.RequestLoadItemDataByID(id) end
	end
	C_Timer.After(1, Pump)
end

function M:Resolve(id)
	if Info(id) or queued[id] then return end
	queued[id] = true
	queue[#queue + 1] = id
	if #queue == 1 then C_Timer.After(1, Pump) end
end

-- an observation that was taken: `mine` = seen by this player just now (as against merged from the guild)
function M:Accepted(ob, mine)
	local stats, today = self.db.stats, math.floor(DT.Now() / L.DAY)
	if stats.day ~= today then stats.day, stats.n = today, 0 end
	stats.n = stats.n + 1
	if not ob.loc and ob.t > (self.db.newest or 0) then self.db.newest = ob.t end
	self:Resolve(ob.id)
	if mine and not ob.loc then self.Sync:Queue(ob) end
	self:Touch()
end

local function Fresh(id, price, now)
	local item = M:House(Here())[id]
	return item and item.p == price and item.t and now - item.t < REFRESH
end

-- A price this player sees right now.
function M:Record(id, price, qty)
	local now = DT.Now()
	if Fresh(id, price, now) then return end
	local ob = { id = id, p = price, q = qty, t = now, o = DT.me, h = Here() }
	if L.Observe(self:House(ob.h), ob, now, true) then
		DT:Debug("market", "saw item %d at %dc, %d listed", id, price, qty) -- (no money text: built for every price of a scan, shown or not)
		self:Accepted(ob, true)
	end
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------

local function Commodity(id)
	local min, qty = nil, 0
	for i = 1, AH.GetNumCommoditySearchResults(id) do
		local r = AH.GetCommoditySearchResultInfo(id, i)
		if r then
			qty = qty + r.quantity
			if not min or r.unitPrice < min then min = r.unitPrice end
		end
	end
	if min then M:Record(id, min, qty) end
end

-- ponytail: one price per item ID. Gear that comes in several variants (suffix, item level) shares it;
-- key by the whole item key if that turns out to mislead.
local function Items(key)
	if type(key) ~= "table" or not key.itemID then return end
	local min, qty = nil, 0
	for i = 1, AH.GetNumItemSearchResults(key) do
		local r = AH.GetItemSearchResultInfo(key, i)
		if r and r.buyoutAmount and r.buyoutAmount > 0 then
			local count = math.max(r.quantity or 1, 1)
			local unit = r.buyoutAmount -- (already for one; quantity = how many are sold at that price)
			qty = qty + count
			if not min or unit < min then min = unit end
		end
	end
	if min then M:Record(key.itemID, min, qty) end
end

-- Browse rows give the lowest price per item: taken for everything listed, as Auctionator does.
-- ponytail: for things that can be bid on, that lowest price may be a bid under the buyout. Opening the
-- item's auctions records its real buyout; search each such item instead if bids mislead too often.
-- One item may come in several rows (suffixes, item levels): the cheapest of one list counts.
local low = {} -- [itemID] = lowest price in the list being read
local function Browse(rows)
	if not rows then low = {} end -- a new list
	local now = DT.Now()
	for _, row in ipairs(rows or AH.GetBrowseResults()) do
		local key, price = row.itemKey, row.minPrice
		local id = key and key.itemID
		if id and price and price > 0 and (row.totalQuantity or 0) > 0 and not (low[id] and low[id] <= price) then
			low[id] = price
			if not Fresh(id, price, now) then M:Record(id, price, row.totalQuantity) end
		end
	end
end

-- A full scan (the replicate list): every auction, so real buyouts. Ours (the button) or one another addon
-- ran. Read a slice per frame: it can be tens of thousands long.
-- The game takes one about every 15 minutes, whoever asked: db.lastFull is when the last one was.
local FULL_EVERY = 15 * 60
local FULL_CANCELLED = "Full scan cancelled: nothing recorded. The game allows the next in 15 minutes; a quick scan works meanwhile."
local scan -- { paging, waiting, t, ticker, full } while one the player asked for runs
local StopScan

-- seconds until the game takes another full scan (0: now)
function M:FullWait()
	return math.max(0, FULL_EVERY - (DT.Now() - (self.db.lastFull or 0)))
end

local replicating, lastRead = false, nil
local function Replicate()
	if replicating or not AH.GetNumReplicateItems then return end
	-- (the event comes again as the items of a list load: a list just read is not read again, unless it is
	-- the answer to a scan of our own that is waiting)
	if not (scan and scan.full) and lastRead and GetTime() - lastRead < 30 then return end
	local n, i, min, qty = AH.GetNumReplicateItems(), 0, {}, {}
	if n == 0 then return end -- (not there yet: the event comes again when it is)
	replicating = true
	if not (scan and scan.full) then M.db.lastFull = DT.Now() end -- (another addon's: the wait is the same)
	local function Slice()
		-- The auction house closed half way: what was read is thrown away. The lowest of half the auctions
		-- is not the lowest price, and where it belongs is no longer known.
		if not M.ahOpen then
			replicating = false
			return
		end
		if scan and scan.full then
			M.scanStatus = ("Full scan: reading %d of %d auctions..."):format(i, n)
			M:Touch()
		end
		for _ = 1, 2000 do
			if i >= n then
				local items = 0
				for id, price in pairs(min) do
					items = items + 1
					M:Record(id, price, qty[id])
				end
				replicating, lastRead = false, GetTime()
				if scan and scan.full then StopScan(("Full scan done: %d auctions, %d items."):format(n, items)) end
				return
			end
			local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = AH.GetReplicateItemInfo(i)
			i = i + 1
			if id and buyout and buyout > 0 then
				count = math.max(count or 1, 1)
				local unit = math.floor(buyout / count)
				qty[id] = (qty[id] or 0) + count
				if not min[id] or unit < min[id] then min[id] = unit end
			end
		end
		C_Timer.After(0, Slice)
	end
	Slice()
end

---------------------------------------------------------------------------
-- A scan the player asks for (the button on the Market tab)
---------------------------------------------------------------------------
-- Quick: one read of the auction house's item list, page by page: what an empty search shows. The pages
-- arrive through the browse events and are recorded by Browse above.
-- Full: ReplicateItems, read by Replicate above.

function StopScan(text)
	scan.ticker:Cancel()
	scan, M.scanning, M.scanStatus = nil, false, text
	M:Touch()
end

local function ScanTick()
	if not scan then return end -- (a tick already on its way when the scan ended)
	if not M.ahOpen then return StopScan(scan.full and FULL_CANCELLED or "Scan stopped: the auction house closed.") end
	if scan.full then
		-- (the game does not say when it refuses one: its own 15 minutes may not be over)
		if not replicating and GetTime() - scan.t > 90 then
			StopScan("Full scan: no answer. The game allows one every 15 minutes, counting other addons' scans.")
		end
	elseif scan.waiting then
		if GetTime() - scan.t > 15 then StopScan("Scan stopped: no answer from the auction house.") end
	elseif scan.paging and AH.HasFullBrowseResults() then
		StopScan(("Scan done: %d items listed."):format(#AH.GetBrowseResults()))
	elseif not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady() then
		if scan.paging then
			M.scanStatus = ("Scanning: %d items so far..."):format(#AH.GetBrowseResults())
			AH.RequestMoreBrowseResults()
		else
			local filters = {}
			for _, name in ipairs({ "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality", "EpicQuality", "LegendaryQuality" }) do
				filters[#filters + 1] = Enum.AuctionHouseFilter[name]
			end
			AH.SendBrowseQuery({ searchString = "", minLevel = 0, maxLevel = 0, filters = filters, itemClassFilters = {},
				sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } })
		end
		scan.paging, scan.waiting, scan.t = true, true, GetTime()
		M:Touch()
	end
end

-- Only ever called from the button's click.
function M:Scan(full)
	if scan or not self.ahOpen then return end
	if full then
		local wait = self:FullWait()
		if not (AH.ReplicateItems and AH.GetNumReplicateItems) then
			self.scanStatus = "This game version has no full scan."
		elseif wait > 0 then
			self.scanStatus = ("Full scan: possible again in %d min."):format(math.ceil(wait / 60))
		else
			self.db.lastFull = DT.Now() -- (counted from the asking: a cancelled one uses the game's turn up too)
			scan = { full = true, t = GetTime(), ticker = C_Timer.NewTicker(0.5, ScanTick) }
			self.scanning, self.scanStatus = true, "Full scan: waiting for the auction house (up to a minute)..."
			AH.ReplicateItems()
		end
		return self:Touch()
	end
	if not (AH.SendBrowseQuery and AH.RequestMoreBrowseResults and AH.HasFullBrowseResults) then return end
	scan = { ticker = C_Timer.NewTicker(0.5, ScanTick) }
	self.scanning, self.scanStatus = true, "Scanning..."
	ScanTick()
end

local function ScanAnswer()
	if scan then scan.waiting = false end
end

-- Auctionator's own price history, for this player alone. It keeps, per item and day, the lowest price it saw
-- (and the most listed), but not the time of day. So each of its days becomes one price in our history,
-- placed in the middle of that day, shown as seen by "Auctionator", and never sent to the guild.
-- This reads Auctionator's price table directly (its API cannot list items or days): the layout is
--   Auctionator.Database.db["<itemID>"] = { m = last price, h = { ["<day>"] = high }, l = { low }, a = { listed } }
-- with day = days since Auctionator.Constants.SCAN_DAY_0. Anything unexpected and the import quietly stops.
local importing = false
local function Import()
	local A = Auctionator
	local source = A and A.Database and A.Database.db
	local day0 = A and A.Constants and A.Constants.SCAN_DAY_0
	if importing or not M.db.settings.auctionator or type(source) ~= "table" or type(day0) ~= "number" then return end
	importing = true
	-- ponytail: Auctionator keeps one price per item for the whole realm, whichever house it scanned; its
	-- history is filed under my faction's house.
	local own = M:House(M.faction)
	local key, taken = nil, 0
	local function One(id, data, now)
		-- a latest price that came from Auctionator is worked out afresh (its time of day is our guess)
		local item = own[id]
		if item and item.o == AUCTIONATOR then item.t = nil end
		local newest = -1
		for day in pairs(data.h) do newest = math.max(newest, tonumber(day) or -1) end
		for day, high in pairs(data.h) do
			local d = tonumber(day)
			-- the newest day's price is the last one seen; an older day's is its lowest
			local price = d == newest and data.m or (type(data.l) == "table" and data.l[day]) or high
			if d and type(price) == "number" and price > 0 then
				local start = day0 + d * L.DAY
				local t = math.floor(start + math.max(0, math.min(now - start, L.DAY)) / 2)
				local qty = type(data.a) == "table" and tonumber(data.a[day]) or 0
				if L.Observe(own, { id = id, p = price, q = qty, t = t, o = AUCTIONATOR, loc = true }, now, true) then
					taken = taken + 1
				end
			end
		end
		M:Resolve(id)
	end
	local Slice
	local function Step()
		local now = DT.Now()
		for _ = 1, 500 do
			local data
			key, data = next(source, key)
			if key == nil then
				importing = false
				DT:Debug("market", "took %d daily prices from Auctionator", taken)
				if taken > 0 then M:Touch() end
				return
			end
			local id = tonumber(key) -- gear by item level ("g:...") and pets ("p:...") are skipped
			if id and type(data) == "table" and type(data.h) == "table" then One(id, data, now) end
		end
		C_Timer.After(0, Slice)
	end
	Slice = function()
		-- (Auctionator may add to its table between two slices, which next() does not forgive; the next
		-- update from Auctionator starts the import again)
		local ok, err = pcall(Step)
		if not ok then
			importing = false
			DT:Debug("market", "Auctionator import stopped: %s", tostring(err))
		end
	end
	Slice()
end

---------------------------------------------------------------------------
-- Start (from the module's onEnable, in Market/UI.lua)
---------------------------------------------------------------------------

function M:Enable(mod)
	local db = mod.db
	db.favs, db.stats, db.houses, db.auctioneers = db.favs or {}, db.stats or {}, db.houses or {}, db.auctioneers or {}
	db.vendors = db.vendors or {}
	self.db = db
	self.faction = (UnitFactionGroup and UnitFactionGroup("player")) == "Alliance" and "A" or "H"
	if db.items then -- from before the houses were told apart: all of it counts as my faction's
		db.houses[self.faction], db.items = db.houses[self.faction] or db.items, nil
	end
	self.view = db.view == "X" and "X" or self.faction
	self.items = self:House(self.view)
	for _, items in pairs(db.houses) do
		L.Prune(items, DT.Now())
		for id, item in pairs(items) do
			if not (item.n and item.s and item.e) then self:Resolve(id) end
		end
	end

	DT:On("COMMODITY_SEARCH_RESULTS_UPDATED", Commodity)
	DT:On("ITEM_SEARCH_RESULTS_UPDATED", Items)
	DT:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
		Browse()
		ScanAnswer()
	end)
	DT:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(rows)
		Browse(rows)
		ScanAnswer()
	end)
	DT:On("AUCTION_HOUSE_BROWSE_FAILURE", function()
		if scan then StopScan("Scan stopped: the auction house refused.") end
	end)
	DT:On("REPLICATE_ITEM_LIST_UPDATE", Replicate)
	DT:On("AUCTION_HOUSE_SHOW", function()
		M.ahOpen = true
		M.at = Detect()
		M:SetView(M.at) -- (touches)
	end)
	DT:On("AUCTION_HOUSE_CLOSED", function()
		M.ahOpen, M.at = false, nil
		M:Touch()
	end)
	DT:On("GET_ITEM_INFO_RECEIVED", function(id, ok)
		if not queued[id] then return end
		queued[id] = nil
		if ok and Info(id) then M:Touch() end
	end)

	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api then
		local pending = false
		local function Later()
			if pending then return end
			pending = true
			C_Timer.After(3, function()
				pending = false
				Import()
			end)
		end
		if api.RegisterForDBUpdate then pcall(api.RegisterForDBUpdate, "DawnTools", Later) end
		C_Timer.After(10, Later)
	end
end

---------------------------------------------------------------------------
-- Vendors: what they sell, read whenever the player opens one
---------------------------------------------------------------------------
-- db.vendors[itemID] = { p = copper for one, v = the vendor's name, z = where, l = true for limited stock, t = seen }
-- Kept on this computer. Items paid for in anything but money are left out.

local function Merchant()
	local npc = UnitName("npc")
	if not (npc and GetMerchantNumItems and GetMerchantItemID) then return end
	local zone, sub = GetRealZoneText and GetRealZoneText() or "?", GetSubZoneText and GetSubZoneText() or ""
	local where = sub ~= "" and sub ~= zone and (sub .. ", " .. zone) or zone
	for i = 1, GetMerchantNumItems() do
		local id, price, stack, left, extended = GetMerchantItemID(i), nil, nil, nil, nil
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local info = C_MerchantFrame.GetItemInfo(i)
			if info then price, stack, left, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
		elseif GetMerchantItemInfo then
			local _
			_, _, price, stack, left, _, _, extended = GetMerchantItemInfo(i)
		end
		if id and price and price > 0 and not extended then
			local unit, old = math.ceil(price / math.max(1, stack or 1)), M.db.vendors[id]
			-- the cheapest seller is kept; a seller's own price is brought up to date
			if not old or unit <= old.p or old.v == npc then
				M.db.vendors[id] = { p = unit, v = npc, z = where, l = (left or -1) >= 0 or nil, t = DT.Now() }
			end
		end
	end
	M:Touch()
end
-- (not while the module is switched off: it has no saved data then)
DT:On("MERCHANT_SHOW", function() if M.db then Merchant() end end)
DT:On("MERCHANT_UPDATE", function() if M.db then Merchant() end end)

---------------------------------------------------------------------------
-- Price lookups for the other tabs (read-only). Work with the module switched off: they then know no prices.
---------------------------------------------------------------------------

local API = {}
DawnMarket = { API = API }

-- unit price in copper, quantity listed, observedAt (server time), observer; nothing when unknown
function API.GetLatest(itemID)
	local item = M.items[itemID]
	if item and item.t then return item.p, item.q, item.t, item.o end
end

-- median unit price over the last `days` days (default 7), or nil
function API.GetMedian(itemID, days)
	local item = M.items[itemID]
	if item then return (L.Median(item, days or 7, DT.Now())) end
end

-- { { day, min, median, n, q }, ... } oldest first; day = days since the epoch
function API.GetHistory(itemID)
	local item = M.items[itemID]
	return item and L.History(item) or {}
end

-- fn(itemID, unit price, quantity, observedAt, observer) for every item with a latest price
function API.Each(fn)
	for id, item in pairs(M.items) do
		if item.t then fn(id, item.p, item.q, item.t, item.o) end
	end
end

-- what a vendor asks for one, the vendor's name, where, whether the stock is limited; nothing when none is known
function API.GetVendor(itemID)
	local v = M.db and M.db.vendors[itemID]
	if v then return v.p, v.v, v.z, v.l or false end
end

-- the auction house the prices given here are of: its key ("H", "A", "X") and its name. At an auctioneer
-- that is the house the player stands at.
function API.GetHouse()
	local key = M.at or M.view
	if key then return key, M.HOUSE_NAMES[key] end
end

-- callback() after new prices were recorded or merged
function API.RegisterForUpdate(callback)
	M.callbacks[#M.callbacks + 1] = callback
end
