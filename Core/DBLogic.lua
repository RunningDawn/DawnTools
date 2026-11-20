-- DawnTools :: DB logic
-- Pure: the rows of the game database DawnTools keeps itself, how they lie in chunks, how a chunk is hashed and
-- how two copies of one are merged. No game API, so tests/run.lua can check it outside the game. The model is
-- in docs/DATA.md; the store that uses this is in Core/DB.lua.
--
-- A row is { t = when it was learned (server time), src = where from ("guild": learned by us; "questie", ...),
-- v = its values as one text } under a key. A key is "what:number[:more]": "item:872", "drops:644:872",
-- "loot:644:1f3a9c" (a counter: the last part is the origin that counted). No tab or line break in any of it.
-- Rows live in chunks by what they are and their number, SPAN numbers to a chunk; a chunk is one text, a row a
-- line, the lines in the order of their keys: two copies holding the same rows are the same text, and so hash
-- the same.

local _, DT = ...
DT = DT or {}
local L = {}
DT.DBLogic = L

L.SPAN = 256        -- numbers to a chunk
L.FUTURE = 300      -- seconds a row may be ahead of our clock
L.MAX_VALUE = 2000  -- bytes a row's values may be

-- the chunk a key lies in: "drops:2" for "drops:644:872"; a key without a number lies by its letters
function L.ChunkOf(key)
	local what, id = key:match("^(%a+):(%d+)")
	if id then return what .. ":" .. math.floor(tonumber(id) / L.SPAN) end
	local sum = 0
	for i = 1, #key do sum = (sum * 31 + key:byte(i)) % 64 end
	return (key:match("^(%a+)") or "x") .. ":s" .. sum
end

-- (what goes into a row must not break a line of it)
function L.Clean(text)
	return (tostring(text):gsub("[\t\n\r]", " "))
end

-- a chunk's text -> { [key] = { t, src, v } }
function L.Parse(text)
	local rows = {}
	for line in (text or ""):gmatch("[^\n]+") do
		local key, t, src, v = line:match("^([^\t]+)\t(%d+)\t([^\t]*)\t(.*)$")
		if key then rows[key] = { t = tonumber(t), src = src, v = v } end
	end
	return rows
end

-- and back: the rows as one text, in the order of their keys
function L.Build(rows)
	local keys = {}
	for key in pairs(rows) do keys[#keys + 1] = key end
	table.sort(keys)
	for i, key in ipairs(keys) do
		local r = rows[key]
		keys[i] = ("%s\t%d\t%s\t%s"):format(key, r.t, r.src or "", r.v or "")
	end
	return table.concat(keys, "\n")
end

-- A text's hash, as 16 hex digits. Four sums, each a different mix of the bytes and where they stand.
-- ponytail: tells two texts apart for comparing copies; it is no protection against someone who means harm.
function L.Hash(text)
	local a, b, c, d = 1, 0, 7, 0
	for i = 1, #text do
		local x = text:byte(i)
		a = (a + x) % 65521
		b = (b + a) % 65521
		c = (c * 31 + x) % 65497
		d = (d + c * (i % 251 + 1)) % 65479
	end
	return ("%04x%04x%04x%04x"):format(a, b, c, d)
end

-- the one hash of many: { [name] = hash } rolled into one, the names in order
function L.Roll(hashes)
	local names = {}
	for name in pairs(hashes) do names[#names + 1] = name end
	table.sort(names)
	for i, name in ipairs(names) do names[i] = name .. "=" .. hashes[name] end
	return L.Hash(table.concat(names, ";"))
end

-- Is a row one to take in over the one held (nil: none held)? A base row (a source's: "questie", ...) wins over
-- one we wrote down in play ("guild") under the same key: what a member without the source met, and could not
-- know for known, must not write over the source's fuller row on every other machine. Between two of a kind the
-- newer wins; of two of the same second, the one whose text sorts later, so that both sides end with the same
-- row. Never one from the future, nor one too long.
function L.Base(row) return row.src ~= nil and row.src ~= "" and row.src ~= "guild" end
function L.Wins(theirs, mine, now)
	if type(theirs) ~= "table" or type(theirs.t) ~= "number" or type(theirs.v) ~= "string" then return false end
	if theirs.t > now + L.FUTURE or #theirs.v > L.MAX_VALUE then return false end
	if not mine then return true end
	if L.Base(theirs) ~= L.Base(mine) then return L.Base(theirs) end
	if theirs.t ~= mine.t then return theirs.t > mine.t end
	return theirs.v > mine.v
end

-- The time a source's rows carry: its version as a number that grows with it ("1.10.3" before "1.11.0"), and
-- after it the shape the rows are written in. So of two members who imported different versions of a source
-- the newer one's rows stand everywhere (L.Wins: the newer row), and every install of the same version and
-- shape writes the same time, and so the same text.
-- Its last digit is left free: a member who has the source and finds a row of its own version wrong puts it
-- right one later (DB.Take), up to L.REPAIRS times, and that row then stands over the wrong one everywhere.
-- ponytail: three numbers of up to 99 each (the whole stays below any real time, which a row may not be ahead
-- of); two builds of one version number are told apart by nothing.
L.REPAIRS = 9
function L.VersionTime(version, shape)
	local a, b, c = tostring(version or ""):match("(%d+)%.?(%d*)%.?(%d*)")
	a, b, c = math.min(tonumber(a) or 0, 99), math.min(tonumber(b) or 0, 99), math.min(tonumber(c) or 0, 99)
	-- (from 700 million up: above every time base rows carried before 0.47.0, so that those are written over)
	return 700000000 + ((a * 100 + b) * 100 + c) * 1000 + math.min(shape or 0, 99) * 10
end

-- The fingerprint of a source's rows of one chunk: { [key] = values } as one hash, whatever time they carry.
-- Whoever writes a source's rows into the store writes this beside them (DB.Prints); whoever is handed such
-- rows by another member checks them against it before taking any (DB.Take).
function L.PrintOf(values)
	local keys = {}
	for key in pairs(values) do keys[#keys + 1] = key end
	table.sort(keys)
	for i, key in ipairs(keys) do keys[i] = key .. "\t" .. values[key] end
	return L.Hash(table.concat(keys, "\n"))
end

-- Another copy's rows laid into mine: those of theirs that win are taken. skip(key, row) may refuse one (my own
-- counters from the wire, a blocked origin). Returns how many were taken.
function L.Merge(mine, theirs, now, skip)
	local taken = 0
	for key, row in pairs(theirs) do
		if not (skip and skip(key, row)) and L.Wins(row, mine[key], now) then
			mine[key], taken = { t = row.t, src = row.src, v = row.v }, taken + 1
		end
	end
	return taken
end

-- what two copies must exchange: the chunks whose hashes differ, or that only one has
function L.Differ(mine, theirs)
	local out = {}
	for id, hash in pairs(theirs) do
		if mine[id] ~= hash then out[#out + 1] = id end
	end
	for id in pairs(mine) do
		if theirs[id] == nil then out[#out + 1] = id end
	end
	table.sort(out)
	return out
end

-- A counter's values: "n;item:k,item:k" <-> n, { [item] = k }. What is seen never outnumbers what was looted.
function L.Counter(n, items)
	local ids = {}
	for id in pairs(items) do ids[#ids + 1] = id end
	table.sort(ids)
	for i, id in ipairs(ids) do ids[i] = id .. ":" .. math.min(items[id], n) end
	return n .. ";" .. table.concat(ids, ",")
end

function L.Counted(v)
	local n, list = (v or ""):match("^(%d+);(.*)$")
	n = tonumber(n) or 0
	local items = {}
	for id, k in (list or ""):gmatch("(%d+):(%d+)") do items[tonumber(id)] = math.min(tonumber(k), n) end
	return n, items
end

-- Values as one text and back, for a base row: numbers, texts, true / false, and lists of those (a list's
-- entries in order, then what it holds under other numbers, lowest first: { 5, 6, [17] = { 1 } } is
-- "{5,6,17:{1}}"). Values are set apart by commas; one that is not there is empty. The same values always give
-- the same text. n: how many values there are (some may be nil).
local function Enc(v)
	local kind = type(v)
	if kind == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "0" end
		-- ("%.0f", not "%d": the game's Lua writes a whole number past two thousand million wrong with "%d")
		if v == math.floor(v) and math.abs(v) < 1e15 then return ("%.0f"):format(v) end
		return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
	elseif kind == "string" then
		return '"' .. v:gsub('[%%"]', function(ch) return ("%%%02x"):format(ch:byte()) end) .. '"'
	elseif kind == "boolean" then
		return v and "T" or "F"
	elseif kind == "table" then
		local out, n, keys = {}, 0, {}
		while v[n + 1] ~= nil do
			n = n + 1
			out[n] = Enc(v[n])
		end
		for key in pairs(v) do
			if type(key) == "number" and key == math.floor(key) and (key < 1 or key > n) then keys[#keys + 1] = key end
		end
		table.sort(keys)
		for _, key in ipairs(keys) do out[#out + 1] = ("%.0f:%s"):format(key, Enc(v[key])) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return ""
end

function L.Pack(values, n)
	local out = {}
	n = n or #values
	for i = 1, n do out[i] = values[i] ~= nil and Enc(values[i]) or "" end
	while n > 0 and out[n] == "" do
		out[n] = nil
		n = n - 1
	end
	return table.concat(out, ",")
end

local function Dec(s, i)
	local ch = s:sub(i, i)
	if ch == '"' then
		local to = s:find('"', i + 1, true)
		if not to then error("open text") end
		return (s:sub(i + 1, to - 1):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)), to + 1
	elseif ch == "{" then
		local list, n = {}, 0
		i = i + 1
		if s:sub(i, i) == "}" then return list, i + 1 end
		while true do
			local key, after = s:match("^(%-?%d+):()", i)
			local value
			if key then
				value, i = Dec(s, after)
				list[tonumber(key)] = value
			else
				value, i = Dec(s, i)
				n = n + 1
				list[n] = value
			end
			ch = s:sub(i, i)
			if ch == "}" then return list, i + 1 end
			if ch ~= "," then error("open list") end
			i = i + 1
		end
	elseif ch == "T" or ch == "F" then
		return ch == "T", i + 1
	end
	local number, after = s:match("^(%-?%d+%.?%d*)()", i)
	if number then return tonumber(number), after end
	return nil, i
end

-- the values of a text L.Pack made, by their place: { [1] = , [2] = , ... }; nil where the text is not one
function L.Unpack(text)
	local ok, values = pcall(function()
		local out, n, i = {}, 0, 1
		while i <= #text do
			n = n + 1
			out[n], i = Dec(text, i)
			if i <= #text and text:sub(i, i) ~= "," then error("not a list of values") end
			i = i + 1
		end
		return out
	end)
	return ok and values or nil
end

return L
