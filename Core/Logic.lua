-- DawnTools :: Logic
-- Pure price-history maths and the wire format: no game API, so tests/run.lua can check it outside the game.
--
-- items[itemID] = {
--   p, q, t, o     latest: unit price (copper), quantity listed, observedAt (server time), observer
--   d = { [day] = one line of text (L.HISTORY_VERSION 2), as L.PackDay writes it:
--         a day of the last week:  "q|a|t:p,t:p,..."  q = most listed that day, a = that day's price from a local
--                                  source (Auctionator; empty: none), t = seconds into the day, p = the price seen
--         an older day:            "S|q|min|median|n"  only what the history graph shows of it }
--   n, c           item name and class: filled in by Market/Capture, not here
-- }
-- day = floor(observedAt / 86400). observedAt is also what tells a repeated observation from a new one.
-- A negative price is an outlier: kept so it is not taken twice, left out of every figure.
-- An observation is { id, p, q, t, o }.
-- (one line a day, not a table a price: some hundred thousand prices are as many tables less. The text is read and
-- written here only, by L.ReadDay and L.PackDay. A line that does not read is an empty day, never an error.)

local _, DT = ...
DT = DT or {}
local L = {}
DT.Logic = L

L.DAY = 86400
L.KEEP_DAYS = 14
L.FULL_DAYS = 7 -- days kept price by price; older ones as a summary (the 7-day median needs no more)
L.MAX_ITEMS = 20000
L.FUTURE = 300 -- seconds an observation may be ahead of our clock
L.HISTORY_VERSION = 2
-- ponytail: 16 observations a day per item. Later ones still move the latest price, but are not in the
-- history (so they can be merged twice, harmlessly). Keep the day's cheapest instead if minima go missing.
L.MAX_PER_DAY = 16

-- A day's line as a table: { q, a, o = { [observedAt] = price }, n } for a day kept price by price, or
-- { sum = true, q, min, median, n } for a summary; nil for a line that does not read.
function L.ReadDay(day, text)
	if type(text) ~= "string" then return nil end
	local sq, smin, smed, sn = text:match("^S|(%d+)|(%d+)|(%d+)|(%d+)$")
	if sq then return { sum = true, q = tonumber(sq), min = tonumber(smin), median = tonumber(smed), n = tonumber(sn) } end
	local q, a, rest = text:match("^(%d+)|(%d*)|(.*)$")
	if not q then return nil end
	local e = { q = tonumber(q), a = tonumber(a), o = {}, n = 0 }
	for t, p in rest:gmatch("(%d+):(%-?%d+)") do
		t, p = tonumber(t), tonumber(p)
		if t < L.DAY and p ~= 0 and not e.o[day * L.DAY + t] then
			e.o[day * L.DAY + t], e.n = p, e.n + 1
		end
	end
	return e
end

-- the table back into its line (prices in the order of their time, so the same day is the same text)
function L.PackDay(day, e)
	if e.sum then return ("S|%.0f|%.0f|%.0f|%.0f"):format(e.q or 0, e.min, e.median, e.n) end
	local ts, parts = {}, {}
	for t in pairs(e.o) do ts[#ts + 1] = t end
	table.sort(ts)
	for i, t in ipairs(ts) do parts[i] = ("%.0f:%.0f"):format(t - day * L.DAY, e.o[t]) end
	return ("%.0f|%s|%s"):format(e.q or 0, e.a and ("%.0f"):format(e.a) or "", table.concat(parts, ","))
end

-- the prices of a day that count (outliers left out), from its line, into list; false for a summary or a bad line
local function DayPrices(text, list)
	local a, rest = text:match("^%d+|(%d*)|(.*)$")
	if not a then return false end
	for p in rest:gmatch(":(%d+)") do list[#list + 1] = tonumber(p) end -- (":-": an outlier, not taken)
	if a ~= "" then list[#list + 1] = tonumber(a) end
	return true
end

local function Middle(list)
	local n = #list
	if n == 0 then return nil end
	table.sort(list)
	if n % 2 == 1 then return list[(n + 1) / 2] end
	return math.floor((list[n / 2] + list[n / 2 + 1]) / 2)
end

-- The 7-day median of every item, kept in memory (never saved): worked out once a day, or once something was
-- taken in or pruned. (weak keys: an item pruned takes its entry with it)
local cache = setmetatable({}, { __mode = "k" })

-- median price over the last `days` days, and how many observations it rests on.
-- ponytail: past L.FULL_DAYS a day is its summary, counted as its median as many times as it had prices (close, not
-- exact). Nothing in DawnTools asks for more than 7 days; DawnMarket.API.GetMedian may.
function L.Median(item, days, now)
	local today = math.floor(now / L.DAY)
	local c = days == 7 and cache[item]
	if c and c.day == today then return c.med, c.n end
	local list = {}
	for day, text in pairs(item.d) do
		if day > today - days and type(text) == "string" and not DayPrices(text, list) then
			local e = L.ReadDay(day, text)
			if e and e.sum then
				for _ = 1, math.min(e.n, L.MAX_PER_DAY + 1) do list[#list + 1] = e.median end
			end
		end
	end
	local n = #list
	local med = Middle(list)
	if days == 7 then cache[item] = { day = today, med = med, n = n } end
	return med, n
end

-- latest price against the 7-day median: 0.1 = 10% dearer. nil without both.
function L.Trend(item, now)
	local med = L.Median(item, 7, now)
	if not (med and item.p) then return nil end
	return item.p / med - 1
end

-- a day's figures: { day, min, median, n, q }, nil where it has no usable price
local function Figures(day, text)
	local e = L.ReadDay(day, text)
	if not e then return nil end
	if e.sum then return { day = day, min = e.min, median = e.median, n = e.n, q = e.q } end
	local list = {}
	for _, p in pairs(e.o) do
		if p > 0 then list[#list + 1] = p end
	end
	if e.a then list[#list + 1] = e.a end
	if not list[1] then return nil end
	local median = Middle(list)
	return { day = day, min = list[1], median = median, n = #list, q = e.q }
end

-- { { day, min, median, n, q }, ... } oldest first, days without a usable price left out
function L.History(item)
	local out = {}
	for day, text in pairs(item.d) do out[#out + 1] = Figures(day, text) end
	table.sort(out, function(a, b) return a.day < b.day end)
	return out
end

-- Takes one observation. `trusted` is a price this player saw themselves: it skips the outlier check
-- (otherwise a real fivefold jump could never be recorded by anyone). `ob.loc` is a local fill-in
-- (Auctionator, which knows the day of a price but not the time): one price per day, never passed on.
-- Returns true (and "outlier" when it was kept but not believed), or false and why.
function L.Observe(items, ob, now, trusted)
	local id, p, q, t = ob.id, ob.p, ob.q or 0, ob.t
	if not (id and p and t) or id <= 0 or p <= 0 or q < 0 then return false, "bad" end
	if t > now + L.FUTURE then return false, "future" end
	if t < now - L.KEEP_DAYS * L.DAY then return false, "old" end
	local item = items[id]
	if not item then
		item = { d = {} }
		items[id] = item
	end
	local outlier = false
	local day = math.floor(t / L.DAY)
	local e = L.ReadDay(day, item.d[day])
	-- (a day already summed up takes nothing more: what it had cannot be told from what comes)
	if e and e.sum then return false, "summed" end
	e = e or { q = 0, n = 0, o = {} }
	if ob.loc then
		e.a = p
		if q > e.q then e.q = q end
	else
		-- (my own second look within the same second replaces the first: results arrive in parts)
		if e.o[t] and not trusted then return false, "dup" end
		if not trusted then
			local med, n = L.Median(item, 7, now)
			outlier = n >= 3 and (p > 5 * med or p < 0.2 * med)
		end
		if e.o[t] then
			e.o[t] = p
		elseif e.n < L.MAX_PER_DAY then
			e.o[t] = outlier and -p or p
			e.n = e.n + 1
		end
		if q > e.q then e.q = q end
	end
	item.d[day] = L.PackDay(day, e)
	cache[item] = nil
	if not outlier and (t > (item.t or 0) or (trusted and t == item.t)) then
		item.p, item.q, item.t, item.o = p, q, t, ob.o
	end
	return true, outlier and "outlier" or nil
end

-- Drops what is older than KEEP_DAYS, sums up the days older than FULL_DAYS, drops a line that does not read, then
-- the longest-unseen items above MAX_ITEMS. Returns how many are left.
-- pause: called every 100 items, where it may yield (a coroutine spreads a big house over frames); the items are
-- gone over as they were at the start, so one taken in meanwhile is safe.
function L.Prune(items, now, pause)
	local cutoff, today, count = now - L.KEEP_DAYS * L.DAY, math.floor(now / L.DAY), 0
	local cutDay, sumDay = today - L.KEEP_DAYS, today - L.FULL_DAYS
	local ids = {}
	for id in pairs(items) do ids[#ids + 1] = id end
	for i, id in ipairs(ids) do
		if pause and i % 100 == 0 then pause() end
		local item = items[id]
		if not item then -- (gone meanwhile)
		elseif not item.t or item.t < cutoff or type(item.d) ~= "table" then
			items[id] = nil
		else
			count = count + 1
			for day, text in pairs(item.d) do
				local e = L.ReadDay(day, text)
				if day < cutDay or not e then
					item.d[day] = nil
				elseif day <= sumDay and not e.sum then
					local f = Figures(day, text)
					item.d[day] = f and L.PackDay(day, { sum = true, q = f.q, min = f.min, median = f.median, n = f.n }) or nil
				end
			end
			cache[item] = nil
		end
	end
	if count > L.MAX_ITEMS then
		local list = {}
		for id, item in pairs(items) do list[#list + 1] = { id, item.t } end
		table.sort(list, function(a, b) return a[2] < b[2] end)
		for i = 1, count - L.MAX_ITEMS do items[list[i][1]] = nil end
		count = L.MAX_ITEMS
	end
	return count
end

-- From the history as it was kept before 0.52 (a table a day, a table of prices in it) to one line a day. What
-- does not read is left out. Returns how many days were turned.
function L.Upgrade(items)
	local n = 0
	for _, item in pairs(items) do
		if type(item) == "table" and type(item.d) == "table" then
			for day, e in pairs(item.d) do
				if type(e) == "table" and type(day) == "number" then
					local o, kept = {}, 0
					for t, p in pairs(type(e.o) == "table" and e.o or {}) do
						if type(t) == "number" and type(p) == "number" and p ~= 0 and math.floor(t / L.DAY) == day then o[t], kept = p, kept + 1 end
					end
					item.d[day] = L.PackDay(day, { q = tonumber(e.q) or 0, a = tonumber(e.a), o = o, n = kept })
					n = n + 1
				elseif type(e) ~= "string" then
					item.d[day] = nil
				end
			end
		end
	end
	return n
end

-- The observations newer than `since`, newest first, at most `cap`. Only real observations of the days kept price
-- by price: local fill-ins and the summed-up days are left out. The observer is only known for an item's latest.
function L.Since(items, since, cap)
	local list = {}
	local first = math.floor(since / L.DAY)
	for id, item in pairs(items) do
		for day, text in pairs(item.d) do
			local e = day >= first and L.ReadDay(day, text)
			for t, p in pairs(e and not e.sum and e.o or {}) do
				if t > since and p > 0 then
					local latest = t == item.t
					list[#list + 1] = { id = id, p = p, q = latest and item.q or e.q, t = t, o = latest and item.o or "" }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		return a.id < b.id
	end)
	for i = #list, cap + 1, -1 do list[i] = nil end
	return list
end

---------------------------------------------------------------------------
-- Wire format: "id,price,qty,observedAt,observer;" per observation
---------------------------------------------------------------------------

L.MAX_DECODE = 500 -- observations read from one message; a longer message is cut off

function L.Encode(list, from, to)
	local parts = {}
	for i = from or 1, math.min(to or #list, #list) do
		local ob = list[i]
		parts[#parts + 1] = ("%.0f,%.0f,%.0f,%.0f,%s"):format(ob.id, ob.p, ob.q or 0, ob.t, (tostring(ob.o or ""):gsub("[,;%c]", "")))
	end
	return table.concat(parts, ";")
end

function L.Decode(text)
	local list = {}
	for rec in text:gmatch("[^;]+") do
		local id, p, q, t, o = rec:match("^(%d+),(%d+),(%d+),(%d+),([^,]*)$")
		-- (an item id has 7 digits at most: a guild message does not make an entry for any number)
		if id and #id < 8 and #p < 15 and #q < 10 and #t < 12 then
			list[#list + 1] = { id = tonumber(id), p = tonumber(p), q = tonumber(q), t = tonumber(t), o = o }
			if #list >= L.MAX_DECODE then break end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

function L.Money(copper)
	local c = math.floor(math.abs(copper) + 0.5)
	local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
	c = c % 100
	local text = g > 0 and ("%dg %ds %dc"):format(g, s, c) or s > 0 and ("%ds %dc"):format(s, c) or ("%dc"):format(c)
	return copper < 0 and "-" .. text or text
end

function L.Ago(seconds)
	if seconds < 60 then return "just now" end
	if seconds < 3600 then return ("%dm ago"):format(math.floor(seconds / 60)) end
	if seconds < 86400 then return ("%dh ago"):format(math.floor(seconds / 3600)) end
	return ("%dd ago"):format(math.floor(seconds / 86400))
end

-- "1.10.2" against "1.9": true when a is the newer
function L.Newer(a, b)
	local x, y = {}, {}
	for n in tostring(a):gmatch("%d+") do x[#x + 1] = tonumber(n) end
	for n in tostring(b):gmatch("%d+") do y[#y + 1] = tonumber(n) end
	for i = 1, math.max(#x, #y) do
		if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) > (y[i] or 0) end
	end
	return false
end

return L
