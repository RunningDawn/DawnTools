-- DawnMarket :: Sync
-- Shares observations with the guild. Does nothing at all unless the player said yes (settings.share).
--   PUSH     what I just saw, in batches
--   REQUEST  "<member>;<since>": that member, send me what you have newer than `since`
--   DATA     the answer, to the whole guild (everyone merges it)
-- PUSH and DATA start with the auction house they are about: "H|", "A|" or "X|", then the observations.
-- The HELLO summary is "<items>,<newest observedAt>".
-- An observer "=" on the wire means "whoever sent this message"; "" means not told.

local _, DT = ...
local M, L = DT.Market, DT.Logic
local Sync = { queue = {}, queued = 0 }
M.Sync = Sync

local PUSH_EVERY = 45
local BATCH = 200          -- observations per message
local PUSH_BATCHES = 5     -- messages per push round; the rest wait for the next
-- ponytail: an answer holds the 2000 newest observations, so a member away for long (or new) gets the
-- recent picture, not all 14 days. Page through older ones if the history graph matters to people.
local REPLY_CAP = 2000
local replied = {}         -- [requester] = GetTime() of my last answer

function Sync:On()
	return M.db.settings.share == true
end

function Sync:Queue(ob)
	if not self:On() then return end
	local key = ob.h .. ob.id
	if not self.queue[key] then self.queued = self.queued + 1 end
	self.queue[key] = ob -- the newest per item and house is enough
end

local function Short(sender)
	return Ambiguate and Ambiguate(sender, "guild") or sender
end

-- my own observations go out as "=" (or nameless, if I prefer that)
local function Wire(list)
	local mine, out = M.db.settings.name and "=" or "", {}
	for i, ob in ipairs(list) do
		out[i] = { id = ob.id, p = ob.p, q = ob.q, t = ob.t, o = ob.o == DT.me and mine or ob.o }
	end
	return out
end

local function SendAll(kind, list, house)
	list = Wire(list)
	for from = 1, #list, BATCH do
		DT.Comms:Send("market", kind, house .. "|" .. L.Encode(list, from, from + BATCH - 1), true)
	end
end

function Sync:Flush()
	if self.queued == 0 then return end
	if not self:On() then
		self.queue, self.queued = {}, 0
		return
	end
	if not DT.Comms:CanSend() then return end
	local byHouse, n = {}, 0
	for key, ob in pairs(self.queue) do
		byHouse[ob.h] = byHouse[ob.h] or {}
		table.insert(byHouse[ob.h], ob)
		self.queue[key] = nil
		n = n + 1
		if n >= BATCH * PUSH_BATCHES then break end
	end
	self.queued = self.queued - n
	for house, list in pairs(byHouse) do SendAll("PUSH", list, house) end
end

local function Tracked()
	local count = 0
	for _, items in pairs(M.db.houses) do
		for _ in pairs(items) do count = count + 1 end
	end
	return count
end

-- what I may be missing: everything since I was last in step with the guild
local function Since()
	return M.db.synced or (DT.Now() - L.KEEP_DAYS * L.DAY)
end

function Sync:Hello()
	if not self:On() then return nil end
	return ("%d,%d"):format(Tracked(), M.db.newest or 0)
end

-- once per session: ask the first member who has something newer than my last visit
function Sync:OnHello(sender, summary)
	if not self:On() or self.done or self.pending or not summary then return end
	local newest = tonumber(summary:match("^%d+,(%d+)$"))
	local since = Since()
	if not newest or newest <= since then return end
	self.pending = sender
	C_Timer.After(math.random() * 3, function()
		DT.Comms:Send("market", "REQUEST", ("%s;%d"):format(sender, since))
	end)
	C_Timer.After(90, function()
		if self.pending == sender and not self.done then self.pending = nil end -- no answer: try the next HELLO
	end)
end

local function Merge(payload, sender)
	local now, who, taken, doubted = DT.Now(), Short(sender), 0, 0
	local house, body = payload:match("^(%a)|(.*)$")
	if not M.HOUSE_NAMES[house or ""] then return end -- (a message that does not say which house is not guessed at)
	local items = M:House(house)
	for _, ob in ipairs(L.Decode(body)) do
		if ob.o == "=" then ob.o = who end
		-- (a name from the guild is shown as it is: nothing in it that the game would read as colour or a link, and no novel)
		ob.o = tostring(ob.o or ""):gsub("[|%c]", ""):sub(1, 40)
		ob.h = house
		local ok, why = L.Observe(items, ob, now)
		if ok then
			taken = taken + 1
			if why then doubted = doubted + 1 end
			M:Accepted(ob)
		end
	end
	Sync.last = now
	DT:Debug("market", "merged %d observations from %s (%d doubted as outliers)", taken, sender, doubted)
end

function Sync:OnMessage(kind, payload, sender)
	if not self:On() then return end
	if kind == "PUSH" then
		Merge(payload, sender)
	elseif kind == "DATA" then
		Merge(payload, sender)
		if sender == self.pending then self.done = true end
	elseif kind == "REQUEST" then
		local target, since = payload:match("^(.-);(%d+)$")
		if not target or target ~= DT.Comms.self then return end
		if replied[sender] and GetTime() - replied[sender] < 60 then return end
		replied[sender] = GetTime()
		for house, items in pairs(M.db.houses) do
			SendAll("DATA", L.Since(items, tonumber(since), REPLY_CAP), house)
		end
	end
end

---------------------------------------------------------------------------
-- Vendor prices: what a vendor asks is the same for everybody, so one member's visit fills it in for the guild.
-- Under the same switch as the auction prices (settings.share). No player's name is in it. Passed on the
-- shared way (Comms:Gossip, module "vendors"); a record is "item;copper;limited (0/1);seen;vendor;where".
-- What came from the guild is marked (r = when it came): it is not my sighting, and is not sent on.
-- ponytail: a price seen with a reputation discount goes out as seen, and the cheapest is kept: it may read a
-- little under what another member pays until they visit that vendor.
---------------------------------------------------------------------------
local function Clean(text)
	return (tostring(text or ""):gsub("[|;%c]", ""):sub(1, 60))
end

local vendors = DT.Comms:Gossip("vendors", {
	on = function() return M.db ~= nil and Sync:On() end,
	peers = function()
		M.db.vpeers = M.db.vpeers or {}
		return M.db.vpeers
	end,
	own = function()
		local out = {}
		for id, v in pairs(M.db.vendors) do
			if not v.r then out[id] = v.t or 1 end
		end
		return out
	end,
	line = function(id)
		local v = M.db.vendors[id]
		return v and ("%d;%d;%d;%d;%s;%s"):format(id, v.p, v.l and 1 or 0, v.t or 0, Clean(v.v), Clean(v.z))
	end,
	take = function(line, now)
		local id, p, l, t, v, z = line:match("^(%d+);(%d+);([01]);(%d+);([^;]*);([^;]*)$")
		id, p, t = tonumber(id), tonumber(p), math.min(tonumber(t) or 0, now)
		if not (id and id > 0 and p and p > 0 and p < 1e10 and v ~= "") then return false end
		v, z = Clean(v), Clean(z)
		local old = M.db.vendors[id]
		-- as with my own visits: the cheapest seller is kept, and a seller's own price is brought up to
		-- date by a newer sighting. What I saw myself at that vendor is not replaced by another's.
		local mine = old and not old.r and old.v == v
		if old and (mine or not (p < old.p or (old.v == v and t > (old.t or 0)))) then return false end
		M.db.vendors[id] = { p = p, v = v, z = z, l = l == "1" or nil, t = t, r = now }
		return true
	end,
	taken = function()
		M:Touch()
		Sync.last = DT.Now()
	end,
})

function Sync:QueueVendor(id) vendors:Queue(id) end
function Sync:VendorHello() return vendors:Hello() end

-- how many vendor prices are held, and how many of them came from the guild
function Sync:VendorCounts()
	local n, guild = 0, 0
	for _, v in pairs(M.db and M.db.vendors or {}) do n, guild = n + 1, guild + (v.r and 1 or 0) end
	return n, guild
end

DT:RegisterModule("vendors", {
	title = "Vendor price sharing",
	version = 1,
	hello = function() return vendors:Hello() end,
	onHello = function(_, sender, summary) vendors:OnHello(sender, summary) end,
	onMessage = function(_, kind, payload, sender) vendors:OnMessage(kind, payload, sender) end,
})

function Sync:Status()
	local items, peers = Tracked(), 0
	for _ in pairs(DT.Comms.peers) do peers = peers + 1 end
	local now, stats = DT.Now(), M.db.stats
	return ("%d items tracked, %d observations today.\n%s"):format(items,
		stats.day == math.floor(now / L.DAY) and stats.n or 0,
		self:On() and ("Sharing: %d guild members seen this session, last data %s.\n%s"):format(peers,
			self.last and L.Ago(now - self.last) or "not yet", table.concat(DT.Comms:Report(), "\n"))
		or "Not sharing: prices stay on this computer and none come in.")
end

function Sync:Enable()
	StaticPopupDialogs.DAWNTOOLS_MARKET_SHARE = {
		text = "DawnTools Market: share prices with the guild?\n\n"
			.. "Sent to guild members who use DawnTools: the prices and quantities you see at the auction house, when you "
			.. "saw them, and your character's name (you can leave the name out in the settings). Also what vendors "
			.. "ask for their goods (the item, the price, the vendor and the place).\n\n"
			.. "Nothing else is sent, and you can switch it off at any time: /dt settings.",
		button1 = "Share", button2 = "Not now",
		OnAccept = function() M.db.settings.share = true end,
		-- (only a real no: a popup pushed aside by another one asks again next time)
		OnCancel = function(_, _, reason)
			if reason == "clicked" then M.db.settings.share = false end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	if M.db.settings.share == nil and IsInGuild() then
		C_Timer.After(5, function() StaticPopup_Show("DAWNTOOLS_MARKET_SHARE") end)
	end
	C_Timer.NewTicker(PUSH_EVERY, function() Sync:Flush() end)
	-- in step with the guild as of now, if this session heard what it had missed
	DT:On("PLAYER_LOGOUT", function()
		-- (or as of the newest thing I hold: a clock running a little ahead somewhere must not make me ask again)
		if Sync:On() and Sync.done then M.db.synced = math.max(DT.Now(), M.db.newest or 0) end
	end)
end
