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
-- A whisper carries two letters of kind and the rest packed. Measured on Forever 2026-11-19: about 700 bytes a
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
local S = { sent = 0, taken = 0 }
DT.DBSync = S

local PREFIX = "DAWND"
local RETRY, TIMEOUT = 600, 90
local MAX_HASHES, MAX_CHUNK = 20000, 400000 -- (lines of a hash list, bytes of a chunk: more is not believed)
local FIRST = { fp = 0, base = 1, enum = 2, boss = 3, recipe = 4, vprice = 5, zone = 6, loot = 7, oloot = 7 }
local LibDeflate = LibStub("LibDeflate")
local comm = {}
local peers = {} -- [member, as the game names them] = { asked = when, want = { chunk, ... }, hash = { [chunk] = theirs }, out = chunk asked for, at = when, idle = waits for another's chunk }
local flying = {} -- [chunk] = { who = the member it was asked of, at = when }
S.peers, S.flying = peers, flying

local function On() return S.db ~= nil and DT:Shares() end

-- On Forever the guild channel names a member "First Surname", a whisper "First-Surname" (and a whisper
-- addressed with the space does not arrive): one member is kept, and whispered to, under the second
local function Who(name) return (name:gsub(" ", "-")) end

local function Say(to, kind, body)
	if DT.Comms:Why() then return false end -- (not in a fight, nor where addon messages are not wanted)
	comm:SendCommMessage(PREFIX, kind .. LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(body or "")), "WHISPER", to, "BULK")
	S.sent = S.sent + 1
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
	local kind = text:sub(1, 2)
	if not (DT.Comms.peers[sender] or DT.Comms.peers[(sender:gsub("%-", " "))]) then
		if kind == "H?" and #text <= 300 then early[sender] = GetTime() end -- (their hello may be on its way)
		return
	end
	if #text > ((kind == "H?" or kind == "C?") and 300 or MAX_CHUNK) then return end
	if GAP[kind] then
		local now, key = GetTime(), sender .. kind
		if heard[key] and now - heard[key] < GAP[kind] then return end
		heard[key] = now
	end
	local packed = LibDeflate:DecodeForWoWAddonChannel(text:sub(3))
	local body = packed and LibDeflate:DecompressDeflate(packed)
	if type(body) ~= "string" then return end
	if kind == "H?" then
		Answer(sender)
	elseif kind == "H=" then
		local p = peers[sender]
		if not p or not p.asked or p.out then return end -- (not asked for, or a transfer is under way)
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
		if not (p and chunk and p.out == chunk) or #rows > MAX_CHUNK then return end -- (only what I asked for)
		local taken = DB.Take(chunk, rows)
		S.taken = S.taken + taken
		if taken > 0 then DT:Fire("DT_DB_UPDATE", chunk) end
		flying[chunk] = nil
		Next(sender)
		Wake()
	end
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
		comm:RegisterComm(PREFIX, "OnComm")
	end,
})

-- /dt db asks too, while the question of sharing has not been answered (Core.lua: DT:AskToShare): without it
-- the tabs that list recipes, dungeons, NPCs, quests and items have nothing to list
function S.Ask() DT:AskToShare() end
