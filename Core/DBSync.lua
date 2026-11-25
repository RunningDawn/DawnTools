-- DawnTools :: DB sync
-- The store of Core/DB.lua, passed between guild members: the sixth kind of shared data (docs/DATA.md, 4).
-- Off until the player says yes; with it off nothing is sent and nothing is taken in. No name is in any of it.
--
-- How two installs become the same:
--   1. Each says the one hash of its whole store with its hello on the guild channel (nothing else goes there).
--   2. Who hears a hash that is not their own asks the other, by whisper, for its chunks' hashes:   H?  ->  H=
--   3. and then, one at a time, for each chunk whose hash differs:                                  C?  ->  C=
--      A chunk received is laid into mine row by row, the newer row kept (DB.Take). The other side does the
--      same towards me when it hears my hello, so both end with what either knew.
-- A message is two letters of kind and the rest packed, in whispers of its pieces (below). Measured on Forever 2026-11-19: about 700 bytes a
-- second get through from one sender, none lost; a character is addressed by its name as the game gives it.
-- Chunks are asked for in the order of FIRST: what the tabs cannot do without (recipes, dungeons) before the
-- long lists of NPCs, items and quests.
-- Several members are asked at once, each for one chunk at a time, and never two for the same chunk: a chunk
-- on its way from one member is left to them (S.flying), and one that has come is not asked of another who
-- holds the very same (their hash of it is mine now). So a newcomer's fill is shared out over whoever is online.
-- ponytail: a chunk is always sent whole, however little of it differs; a member is asked again RETRY seconds
-- after the last time.

local _, DT = ...
local DB, L = DT.DB, DT.DBLogic
local S = { sent = 0, taken = 0, out = {}, inn = {}, turned = 0, unasked = 0, bytes = {}, pieces = 0, lost = 0, unread = 0 }
-- (out/inn: [kind] = messages this session; turned: from no guildmate; bytes: [kind] = sent, unpacked; pieces:
-- whispers of ours that came in; lost: messages begun and never finished; unread: whole, and could not be unpacked)
DT.DBSync = S

-- A message goes as whispers of its own pieces, each a single whisper of letters, digits and brackets:
--   kind id:i:n;piece      (kind "H?", "H=", "C?", "C="; id numbers the messages of one sender; piece i of n)
-- Measured on Forever 2026-11-21: such whispers arrive, 200 of 200, where a long message the library cuts up
-- itself (a control byte before each piece, any byte in it) never came whole. Its prefix is not 0.54's ("DAWND").
local PREFIX, PIECE = "DAWNW", 230
local seq = 0
local RETRY, TIMEOUT = 600, 90
local MAX_HASHES, MAX_CHUNK = 20000, 400000 -- (lines of a hash list, bytes of a chunk: more is not believed)
local MAX_PIECES = math.ceil(MAX_CHUNK / PIECE) -- (packed, a chunk is far smaller than that)
local parts = {} -- [member .. ":" .. id] = a message of theirs coming in: { kind, n, got, at, [i] = piece }
local STALE = 60 -- (seconds a message may lie unfinished: then it is counted lost)
local FIRST = { fp = 0, base = 1, enum = 2, boss = 3, recipe = 4, vprice = 5, zone = 6, loot = 7, oloot = 7 }
local LibDeflate = LibStub("LibDeflate")
local comm = {}
local peers = {} -- [member, as the game names them] = { asked = when, want = { chunk, ... }, hash = { [chunk] = theirs }, out = chunk asked for, at = when, idle = waits for another's chunk }
local flying = {} -- [chunk] = { who = the member it was asked of, at = when }
S.peers, S.flying = peers, flying

local function On() return S.db ~= nil and DT:Shares() end

-- On Forever a member is named "First Surname" by the guild channel and as the sender of a whisper, but a whisper
-- arrives only addressed "First-Surname": one member is kept, and whispered to, under that form, whichever
-- way the game wrote the name that came in
local function Who(name) return (name:gsub(" ", "-")) end

-- A member who logged off: the game answers every whisper to them with a line in the chat ("No player named ...").
-- gone[member] = true from the first such line, or from the game saying they went offline, until their next hello:
-- nothing more is whispered to them, and what was being fetched from them is left to others. A message's pieces
-- are handed to the game one after the other (the next when the one before has gone out), so that nothing of it
-- lies queued for somebody who has left. whispered[member] = when a piece last went to them: the game's line
-- about a whisper of ours is kept out of the chat (S.Hide).
local gone, whispered = {}, {}
S.gone = gone

local function Say(to, kind, body)
	if DT.Comms:Why() then return false end -- (not in a fight, nor where addon messages are not wanted)
	to = Who(to)
	if gone[to] then return false end
	local data = LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(body or ""))
	local n = math.max(1, math.ceil(#data / PIECE))
	seq = seq % 9999 + 1
	local id, i = seq, 0
	local function Piece()
		i = i + 1
		if i > n or gone[to] then return end
		whispered[to] = GetTime()
		comm:SendCommMessage(PREFIX, ("%s%d:%d:%d;%s"):format(kind, id, i, n, data:sub((i - 1) * PIECE + 1, i * PIECE)), "WHISPER", to, "BULK", Piece)
	end
	Piece()
	S.sent, S.out[kind] = S.sent + 1, (S.out[kind] or 0) + 1
	S.bytes[kind] = (S.bytes[kind] or 0) + #(body or "")
	return true
end

-- The next chunk wanted of a member is asked for; none left: done with them. Passed over: a chunk that is mine
-- already as they have it (it came from another member meanwhile), and one that is on its way from another
-- (then this member waits, p.idle, and is asked again when that one has come or failed to).
local function Next(sender)
	local p = peers[sender]
	if not p then return end
	p.out, p.idle = nil, nil
	local mine, now, at = DB.Hashes(), GetTime(), 1
	while p.want[at] do
		local chunk = p.want[at]
		local fly = flying[chunk]
		if fly and (now - fly.at > TIMEOUT or fly.who == sender) then flying[chunk], fly = nil, nil end
		if p.hash and mine[chunk] == p.hash[chunk] then
			table.remove(p.want, at)
		elseif fly then
			at, p.idle = at + 1, true
		else
			table.remove(p.want, at)
			if Say(sender, "C?", chunk) then
				p.out, p.at, p.idle = chunk, now, nil
				flying[chunk] = { who = sender, at = now }
			else
				-- (cannot ask now: the rest waits for their next hello)
				p.want, p.asked, p.idle = {}, nil, nil
			end
			return
		end
	end
end

-- a chunk came, or will not: whoever waited for it looks again
local function Wake()
	for name, p in pairs(peers) do
		if p.idle and not p.out then Next(name) end
	end
end

-- The game's line in the chat: is it about a member being gone? ("No player named 'X' is currently playing.",
-- "X has gone offline.") Returns the member, as whispered to.
local function Pattern(text) return text and "^" .. text:gsub("%p", "%%%0"):gsub("%%%%s", "(.+)") .. "$" end
local function Gone(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	local name = text:match(Pattern(ERR_CHAT_PLAYER_NOT_FOUND_S) or "^No player named '(.+)' is currently playing%.$")
		or text:match(Pattern(ERR_FRIEND_OFFLINE_S) or "^(.+) has gone offline%.$")
	-- (the name may come as a link to the player)
	name = name and name:gsub("|H.-|h", ""):gsub("|h", ""):gsub("[%[%]]", "")
	return name and Who(name)
end

function S.Left(text)
	local who = Gone(text)
	if not who or not (peers[who] or whispered[who]) then return end
	gone[who] = true
	local p = peers[who]
	peers[who] = nil
	if p and p.out then flying[p.out] = nil end
	Wake()
end

-- (a chat filter: true keeps the line out of the chat. Only "no player named", and only within seconds of a
-- whisper of ours to that name: a whisper the player typed themselves still gets its answer shown)
function S.Hide(_, _, text)
	local who = Gone(text)
	if who and whispered[who] and GetTime() - whispered[who] < 30 and not text:find("offline", 1, true) then return true end
	return false
end

-- my hashes, to a member who asked for them
local function Answer(to)
	local lines = {}
	for chunk, hash in pairs(DB.Hashes()) do lines[#lines + 1] = chunk .. "=" .. hash end
	Say(to, "H=", table.concat(lines, "\n"))
end
-- ponytail: [name] = when they asked before I heard their hello; an entry per name that whispers, dropped at its hello
local early = {}

-- a member said the hash of their store
function S.Heard(sender, root)
	if not On() then return end
	sender = Who(sender)
	gone[sender] = nil -- (here again)
	-- (they asked before their hello reached me: answered now, if that was not long ago)
	if early[sender] then
		if GetTime() - early[sender] < 120 then Answer(sender) end
		early[sender] = nil
	end
	if type(root) ~= "string" or root == "" or root == DB.Root() then return end
	local p = peers[sender] or { want = {} }
	peers[sender] = p
	local now = GetTime()
	if p.out and now - (p.at or 0) > TIMEOUT then -- (no answer came: begun anew, and others may ask for what they kept)
		flying[p.out], p.out, p.want = nil, nil, {}
		Wake()
	end
	if p.idle then Next(sender) end
	p.root = root
	if p.empty == root then return end -- (nothing of theirs I lacked, and they hold nothing new since: they ask me)
	if p.out or p.idle or (p.asked and now - p.asked < RETRY) then return end
	if Say(sender, "H?", "") then p.asked = now end
end

local heard = {} -- [sender .. kind] = when a request of theirs was last answered
-- (a chunk is asked for only once the one before has come, so "C?" needs no gap: one would stall a fast transfer)
local GAP = { ["H?"] = 60 }

function comm:OnComm(prefix, text, distribution, sender)
	if prefix ~= PREFIX or distribution ~= "WHISPER" or not On() or type(text) ~= "string" or type(sender) ~= "string" then return end
	-- only guildmates (who have said hello on the guild channel), and no more than is worth unpacking
	local kind, id, i, n, piece = text:match("^(%u[%?=])(%d+):(%d+):(%d+);([%w%(%)]*)$")
	i, n = tonumber(i), tonumber(n)
	-- (the guild channel may name them "First Surname", "First-Surname" or only "First")
	local guild, first, rest = DT.Comms.peers, sender:match("^([^%- ]+)[%- ](.+)$")
	local member = guild[sender] or first and (guild[first .. " " .. rest] or guild[first .. "-" .. rest] or guild[first])
	sender = Who(sender)
	if not member then
		if kind == "H?" then early[sender] = GetTime() end -- (their hello may be on its way)
		S.turned, S.turnedWho = S.turned + 1, sender
		return
	end
	-- (a request is one piece; an answer no more pieces than a chunk of the most that is believed)
	if not kind or i < 1 or i > n or n > ((kind == "H?" or kind == "C?") and 1 or MAX_PIECES) then S.unread = S.unread + 1 return end
	S.pieces = S.pieces + 1
	local key, now = sender .. ":" .. id, GetTime()
	local part = parts[key]
	if not part then
		for k, old in pairs(parts) do
			if now - old.at > STALE then parts[k], S.lost = nil, S.lost + 1 end
		end
		part = { kind = kind, n = n, got = 0, at = now }
		parts[key] = part
	end
	if part.kind ~= kind or part.n ~= n or part[i] then return end
	part[i], part.got, part.at = piece, part.got + 1, now
	if part.got < n then return end
	parts[key] = nil
	if GAP[kind] then
		local now, key = GetTime(), sender .. kind
		if heard[key] and now - heard[key] < GAP[kind] then return end
		heard[key] = now
	end
	local packed = LibDeflate:DecodeForPrint(table.concat(part, "", 1, n))
	local body = packed and LibDeflate:DecompressDeflate(packed)
	if type(body) ~= "string" then S.unread = S.unread + 1 return end
	S.inn[kind] = (S.inn[kind] or 0) + 1
	if kind == "H?" then
		Answer(sender)
	elseif kind == "H=" then
		local p = peers[sender]
		if not p or not p.asked or p.out then S.unasked = S.unasked + 1 return end -- (not asked for, or a transfer is under way)
		local mine, want, n = DB.Hashes(), {}, 0
		p.hash = {}
		for chunk, hash in body:gmatch("([^=\n]+)=(%x+)") do
			n = n + 1
			if n > MAX_HASHES then break end
			if mine[chunk] ~= hash then want[#want + 1], p.hash[chunk] = chunk, hash end
		end
		table.sort(want, function(a, b)
			local x, y = FIRST[a:match("^%a+")] or 9, FIRST[b:match("^%a+")] or 9
			if x ~= y then return x < y end
			return a < b
		end)
		p.want = want
		-- (spread the next ask so that all members do not ask all at once; nothing of theirs to take: not again until
		-- what they hold changes)
		p.asked, p.empty = GetTime() - math.random() * RETRY / 4, #want == 0 and p.root or nil
		Next(sender)
	elseif kind == "C?" then
		local chunk = DB.Text(body)
		if chunk then Say(sender, "C=", body .. "\n" .. chunk) end
	elseif kind == "C=" then
		local p = peers[sender]
		local chunk, rows = body:match("^([^\n]+)\n(.*)$")
		if not (p and chunk and p.out == chunk) or #rows > MAX_CHUNK then S.unasked = S.unasked + 1 return end -- (only what I asked for)
		local taken = DB.Take(chunk, rows)
		S.taken = S.taken + taken
		if taken > 0 then DT:Fire("DT_DB_UPDATE", chunk) end
		flying[chunk] = nil
		Next(sender)
		Wake()
	end
end

-- Sync now (the Data Sync page, /dt db sync): every wait dropped, a hello sent, and every member who shares
-- asked for their list at once, whatever their last hello said (they may have learned something since). A pull,
-- not a push: what comes in is still only what I asked for. A transfer under way goes on as it was.
-- Returns how many were asked, or nil with sharing off.
function S.Now()
	if not On() then return nil end
	for _, p in pairs(peers) do p.asked, p.empty = nil, nil end
	DT.Comms:Hello()
	local n, now = 0, GetTime()
	for name, peer in pairs(DT.Comms.peers) do
		local who = Who(name)
		local p = peers[who] or { want = {} }
		peers[who] = p
		if peer.sum.gamedb and not (p.out or p.idle) and Say(who, "H?", "") then p.asked, n = now, n + 1 end
	end
	return n
end

-- What the whispers did this session, as lines for the Data Sync page: requests and answers each way, and each
-- member heard: whether their store is the same as mine, and what is being fetched from them.
function S.Report()
	local o, i = S.out, S.inn
	local lines = {
		("Asked of others: %d lists of chunks, %d chunks. Came back: %d lists, %d chunks (%d rows taken in)."):format(o["H?"] or 0, o["C?"] or 0, i["H="] or 0, i["C="] or 0, S.taken),
		("Asked of me: %d lists, %d chunks. Sent back: %d lists, %d chunks."):format(i["H?"] or 0, i["C?"] or 0, o["H="] or 0, o["C="] or 0),
	}
	lines[#lines + 1] = ("Whispers in: %d pieces; %d messages lost part-way, %d that could not be read. Bytes sent: lists %d, chunks %d."):format(S.pieces, S.lost, S.unread, S.bytes["H="] or 0, S.bytes["C="] or 0)
	if S.unasked > 0 then lines[#lines + 1] = ("%d answers not taken: not asked for, or another under way."):format(S.unasked) end
	if S.turned > 0 then lines[#lines + 1] = ("%d whispers turned away: not from a member heard on the guild channel (last from %s)."):format(S.turned, tostring(S.turnedWho)) end
	if not On() then lines[#lines + 1] = "Sharing is off: nothing is asked or answered." end
	local mine, now, names = DB.Root(), GetTime(), {}
	for name in pairs(DT.Comms.peers) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local root, p = DT.Comms.peers[name].sum.gamedb, peers[Who(name)]
		local what
		if not root then what = "says no hash (sharing off, or an older version)"
		elseif root == mine then what = "the same as mine"
		elseif not p then what = "differs; not asked yet (at their next hello)"
		elseif p.out then what = ("differs; fetching %s, %d more to fetch"):format(p.out, #p.want)
		elseif p.idle then what = ("differs; waiting on a chunk another member is sending, %d to fetch"):format(#p.want)
		elseif p.empty == root then what = "differs; nothing of theirs I lack (they fetch from me)"
		elseif p.hash then what = "differs; fetched what their list showed, asked again within 10 minutes"
		elseif p.asked then what = ("differs; their list asked for %ds ago, no answer yet"):format(math.floor(now - p.asked))
		else what = "differs" end
		lines[#lines + 1] = ("%s: %s"):format(name, what)
	end
	return lines
end

DT:RegisterModule("gamedb", { -- (not "db": that key of the saved file is the store itself)
	title = "Game database",
	version = 1,
	status = function()
		local s = DB.Stats()
		return ("%d rows in %d chunks, %.0f KB. This session: %d whispers sent, %d rows taken in."):format(s.rows, s.chunks, s.bytes / 1024, S.sent, S.taken)
	end,
	-- (the one thing that goes on the guild channel: the hash of the whole store)
	hello = function() return On() and DB.Root() or nil end,
	onHello = function(_, sender, summary) S.Heard(sender, summary) end,
	onEnable = function(mod)
		S.db = mod.db
		LibStub("AceComm-3.0"):Embed(comm)
		local raw = comm.OnComm -- (timed, for /dt perf)
		comm.OnComm = function(self, ...) DT.Timed("guild: game database whisper in", raw, self, ...) end
		comm:RegisterComm(PREFIX, "OnComm")
		DT:On("CHAT_MSG_SYSTEM", S.Left)
		if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", S.Hide) end
	end,
})

-- /dt db asks too, while the question of sharing has not been answered (Core.lua: DT:AskToShare): without it
-- the tabs that list recipes, dungeons, NPCs, quests and items have nothing to list
function S.Ask() DT:AskToShare() end
