-- DawnTools :: Comms
-- Guild messages for every module, under one prefix. A message is
--   module \t kind \t protocol version \t flag \t payload        flag "z" = payload deflated, "-" = plain
-- The core's own HELLO says who has the addon; modules add a summary to it and get the others' summaries.
-- Everything goes to GUILD, never a whisper: a message meant for one member names them in its payload.

local _, DT = ...
local Comms = { peers = {}, PROTO = 1 }
DT.Comms = Comms

local PREFIX = "DAWN"
local MIN_PROTO = 1                  -- older messages are dropped
local HELLO_EVERY = 600
local RATE_N, RATE_WINDOW = 40, 60   -- messages taken from one sender per window

local AceComm = LibStub("AceComm-3.0")
local LibDeflate = LibStub("LibDeflate")
AceComm:Embed(Comms)

-- tells my own HELLO from the others' when it comes back, which is how I learn my name on the wire
local nonce = tostring(math.random(1, 999999999))
local lastHello, rate, nagged = -1000, {}, false

-- What went out and came in this session, counted: /dt sync and the Market status show it. Nothing here
-- changes what is sent; it is for finding out why two members do not hear each other.
--   ok, refused  pieces the game took / refused (code: its last answer when it refused)
--   blocked      sends not tried, and why the last one was not
--   heard, bad   messages of ours that came in / of those, the ones that could not be read
--   helloAt, echo  when my last HELLO went out / when one of mine came back from the server
local stats = { ok = 0, refused = 0, blocked = 0, heard = 0, bad = 0 }
Comms.stats = stats

-- why nothing can be sent now; nil when it can. Not in combat, and not in instances unless asked: the game
-- restricts addon messages there.
function Comms:Why()
	if not IsInGuild() then return "not in a guild" end
	if InCombatLockdown() then return "in combat" end
	if not DT.db.settings.instances and IsInInstance() then return "in an instance" end
end

function Comms:CanSend()
	return self:Why() == nil
end

-- (called by the library for every piece of a message as it goes out, with the game's answer where it tells)
local function Sent(_, _, _, result)
	if result == nil or result == true or result == 0 then
		stats.ok = stats.ok + 1
	else
		stats.refused, stats.code = stats.refused + 1, result
	end
end

-- bulk: deflated and sent at low priority. Returns whether it went out.
function Comms:Send(module, kind, payload, bulk)
	local why = self:Why()
	if why then
		stats.blocked, stats.why = stats.blocked + 1, why
		return false
	end
	local flag = "-"
	if bulk then
		payload, flag = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(payload)), "z"
	end
	local text = table.concat({ module, kind, self.PROTO, flag, payload }, "\t")
	local ok, err = pcall(self.SendCommMessage, self, PREFIX, text, "GUILD", nil, bulk and "BULK" or "NORMAL", Sent)
	DT:Debug(module, ok and "sent %s, %d bytes" or "send %s failed: %s", kind, ok and #text or tostring(err))
	-- (a send that raised an error, in the library or the game: counted, with what it said)
	if not ok then stats.failed, stats.err = (stats.failed or 0) + 1, tostring(err):sub(1, 160) end
	return ok
end

function Comms:Hello()
	local parts = { nonce, DT.VERSION }
	for _, mod in DT:Enabled() do
		local summary = mod.hello and mod:hello()
		if summary then parts[#parts + 1] = mod.name .. "=" .. summary end
	end
	if self:Send("core", "HELLO", table.concat(parts, ";")) then
		lastHello = GetTime()
		stats.helloAt = lastHello
	end
end

-- the counts, as lines to read out
function Comms:Report()
	local now = GetTime()
	local function Ago(t)
		local s = math.floor(now - t)
		return s < 90 and (s .. "s ago") or (math.floor(s / 60) .. "m ago")
	end
	local members = {}
	for name, peer in pairs(self.peers) do members[#members + 1] = ("%s %s (%s)"):format(name, peer.version, Ago(peer.t)) end
	table.sort(members)
	if not stats.started then return { "Guild messages were never started on this client: something failed at login. /reload, and look for an error." } end
	return {
		("Sent: %d pieces, %d refused%s; %d sends not tried%s."):format(stats.ok, stats.refused,
			stats.code ~= nil and (" (the game's last answer: %s)"):format(tostring(stats.code)) or "",
			stats.blocked, stats.why and (" (last: " .. stats.why .. ")") or "")
			.. (stats.failed and (" %d sends FAILED with an error: %s"):format(stats.failed, stats.err) or ""),
		stats.helloAt and ("My HELLO: sent %s, %s."):format(Ago(stats.helloAt),
			stats.echo and stats.echo >= stats.helloAt and "came back from the server" or "has NOT come back from the server")
			or ("My HELLO: not sent yet" .. (self:Why() and (" (" .. self:Why() .. ")") or "") .. "."),
		("Heard: %d messages, %d unreadable. Members: %s."):format(stats.heard, stats.bad, members[1] and table.concat(members, ", ") or "none"),
	}
end

-- /dt sync: says HELLO (once a minute at most), and prints the counts now and a few seconds on
local lastAsked = -1000
function Comms:Diagnose()
	if GetTime() - lastAsked >= 60 then
		lastAsked = GetTime()
		self:Hello()
	end
	for _, line in ipairs(self:Report()) do DT:Print(line) end
	C_Timer.After(5, function()
		DT:Print("...and five seconds on:")
		for _, line in ipairs(Comms:Report()) do DT:Print(line) end
	end)
end

local function OnHello(sender, payload)
	local fields = {}
	for field in payload:gmatch("[^;]+") do fields[#fields + 1] = field end
	if fields[1] == nonce then
		Comms.self, stats.echo = sender, GetTime()
		return
	end
	-- known = heard before in this session of theirs (a new nonce means they logged in again)
	local known = Comms.peers[sender] and Comms.peers[sender].nonce == fields[1]
	local peer = { nonce = fields[1], version = fields[2] or "?", t = GetTime(), sum = {} }
	for i = 3, #fields do
		local name, summary = fields[i]:match("^(%w+)=(.*)$")
		if name then peer.sum[name] = summary end
	end
	Comms.peers[sender] = peer
	if not nagged and DT.Logic.Newer(peer.version, DT.VERSION) then
		nagged = true
		DT:Print("%s has DawnTools %s, yours is %s. Time to update.", sender, peer.version, DT.VERSION)
	end
	-- someone new: answer once, so they need not wait for my next round
	-- ponytail: every member answers a newcomer. Past a few hundred users, stay quiet when another answer was heard.
	if not known and GetTime() - lastHello > 60 then
		C_Timer.After(1 + math.random() * 9, function()
			if GetTime() - lastHello > 60 then Comms:Hello() end
		end)
	end
	for _, mod in DT:Enabled() do
		if mod.onHello then mod:onHello(sender, peer.sum[mod.name]) end
	end
end

function Comms:OnComm(_, text, distribution, sender)
	if distribution ~= "GUILD" then return end
	stats.heard = stats.heard + 1
	local module, kind, proto, flag, payload = text:match("^([^\t]*)\t([^\t]*)\t(%d+)\t([^\t])\t(.*)$")
	proto = tonumber(proto)
	if not module then stats.bad = stats.bad + 1 end
	if not module or proto < MIN_PROTO then return end
	if proto > self.PROTO then
		if not nagged then
			nagged = true
			DT:Print("%s uses a newer DawnTools that this version cannot read. Time to update.", sender)
		end
		return
	end
	local hello = module == "core" and kind == "HELLO"
	if sender == self.self and not hello then return end

	local now = GetTime()
	local r = rate[sender]
	if not r or now - r.t > RATE_WINDOW then
		r = { t = now, n = 0 }
		rate[sender] = r
	end
	r.n = r.n + 1
	if r.n > RATE_N then return end

	if flag == "z" then
		local packed = LibDeflate:DecodeForWoWAddonChannel(payload)
		payload = packed and LibDeflate:DecompressDeflate(packed)
		if not payload then
			stats.bad = stats.bad + 1
			return
		end
	end
	if hello then return OnHello(sender, payload) end
	local mod = DT.modules[module]
	if mod and mod.enabled and mod.onMessage then
		DT:Debug(module, "%s from %s, %d bytes", kind, sender, #payload)
		mod:onMessage(kind, payload, sender)
	end
end

function Comms:Start()
	self:RegisterComm(PREFIX, "OnComm")
	stats.started = true
	C_Timer.After(8, function() Comms:Hello() end)
	C_Timer.NewTicker(HELLO_EVERY, function() Comms:Hello() end)
end
