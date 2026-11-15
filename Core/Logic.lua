-- DawnTools :: Logic
-- Pure price-history maths and the wire format: no game API, so tests/run.lua can check it outside the game.
--
-- items[itemID] = {
--   p, q, t, o     latest: unit price (copper), quantity listed, observedAt (server time), observer
--   d = { [day] = { q = most listed that day, n = observations kept, o = { [observedAt] = price },
--                   a = that day's price from a local source (Auctionator): counted, never passed on } }
--   n, c           item name and class: filled in by Market/Capture, not here
-- }
-- day = floor(observedAt / 86400). observedAt is also what tells a repeated observation from a new one.
-- A negative price in d[day].o is an outlier: kept so it is not taken twice, left out of every figure.
-- An observation is { id, p, q, t, o }.

local _, DT = ...
DT = DT or {}
local L = {}
DT.Logic = L

L.DAY = 86400
L.KEEP_DAYS = 14
L.MAX_ITEMS = 20000
L.FUTURE = 300 -- seconds an observation may be ahead of our clock
-- ponytail: 16 observations a day per item. Later ones still move the latest price, but are not in the
-- history (so they can be merged twice, harmlessly). Keep the day's cheapest instead if minima go missing.
L.MAX_PER_DAY = 16

local function Prices(item, days, now)
	local list, today = {}, math.floor(now / L.DAY)
	for day, e in pairs(item.d) do
		if day > today - days then
			for _, p in pairs(e.o) do
				if p > 0 then list[#list + 1] = p end
			end
			if e.a then list[#list + 1] = e.a end
		end
	end
	table.sort(list)
	return list
end

local function Middle(list)
	local n = #list
	if n == 0 then return nil end
	if n % 2 == 1 then return list[(n + 1) / 2] end
	return math.floor((list[n / 2] + list[n / 2 + 1]) / 2)
end

-- median price over the last `days` days, and how many observations it rests on
function L.Median(item, days, now)
	local list = Prices(item, days, now)
	return Middle(list), #list
end

-- latest price against the 7-day median: 0.1 = 10% dearer. nil without both.
function L.Trend(item, now)
	local med = L.Median(item, 7, now)
	if not (med and item.p) then return nil end
	return item.p / med - 1
end

-- { { day, min, median, n, q }, ... } oldest first, days without a usable price left out
function L.History(item)
	local out = {}
	for day, e in pairs(item.d) do
		local list = {}
		for _, p in pairs(e.o) do
			if p > 0 then list[#list + 1] = p end
		end
		if e.a then list[#list + 1] = e.a end
		if list[1] then
			table.sort(list)
			out[#out + 1] = { day = day, min = list[1], median = Middle(list), n = #list, q = e.q }
		end
	end
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
	local e = item.d[day]
	if ob.loc then
		if not e then
			e = { q = 0, n = 0, o = {} }
			item.d[day] = e
		end
		e.a = p
		if q > e.q then e.q = q end
	else
		-- (my own second look within the same second replaces the first: results arrive in parts)
		if e and e.o[t] and not trusted then return false, "dup" end
		if not trusted then
			local med, n = L.Median(item, 7, now)
			outlier = n >= 3 and (p > 5 * med or p < 0.2 * med)
		end
		if not e then
			e = { q = 0, n = 0, o = {} }
			item.d[day] = e
		end
		if e.o[t] then
			e.o[t] = p
		elseif e.n < L.MAX_PER_DAY then
			e.o[t] = outlier and -p or p
			e.n = e.n + 1
		end
		if q > e.q then e.q = q end
	end
	if not outlier and (t > (item.t or 0) or (trusted and t == item.t)) then
		item.p, item.q, item.t, item.o = p, q, t, ob.o
	end
	return true, outlier and "outlier" or nil
end

-- Drops what is older than KEEP_DAYS, then the longest-unseen items above MAX_ITEMS. Returns how many are left.
function L.Prune(items, now)
	local cutoff, cutDay, count = now - L.KEEP_DAYS * L.DAY, math.floor(now / L.DAY) - L.KEEP_DAYS, 0
	for id, item in pairs(items) do
		if not item.t or item.t < cutoff then
			items[id] = nil
		else
			count = count + 1
			for day in pairs(item.d) do
				if day < cutDay then item.d[day] = nil end
			end
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

-- The observations newer than `since`, newest first, at most `cap`. Only real observations: local
-- fill-ins (d[day].a) are left out. The observer is only known for an item's latest observation.
function L.Since(items, since, cap)
	local list = {}
	for id, item in pairs(items) do
		for _, e in pairs(item.d) do
			for t, p in pairs(e.o) do
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
		parts[#parts + 1] = ("%d,%d,%d,%d,%s"):format(ob.id, ob.p, ob.q or 0, ob.t, (tostring(ob.o or ""):gsub("[,;%c]", "")))
	end
	return table.concat(parts, ";")
end

function L.Decode(text)
	local list = {}
	for rec in text:gmatch("[^;]+") do
		local id, p, q, t, o = rec:match("^(%d+),(%d+),(%d+),(%d+),([^,]*)$")
		if id and #id < 10 and #p < 15 and #q < 10 and #t < 12 then
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
