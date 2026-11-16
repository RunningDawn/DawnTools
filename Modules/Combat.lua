-- DawnCombat
-- Who killed me, and who I killed: read from the combat log as it happens, kept on this computer.
-- A death is told from the damage I took in the seconds before it: the last hit is the killer, everyone else
-- who hit me helped. A kill is anything that died within seconds of my hitting it; the killing blow is marked.
--
-- WoW Forever closes the combat log to addons (registering for it gets an addon blocked), so there (C.open
-- false) it is not touched at all. What the game does hand out is used instead:
--   a kill   of a player only (this is for PvP): the PARTY_KILL event (who struck the blow, who died: GUIDs
--            only), mine if the blow was mine or it was my target; and the "X dies, honorable kill" chat line,
--            which also tells of the kills I only helped with.
--   a death  PLAYER_DEAD, with the game's own death recap (C_DeathRecap: the last few hits) for who and what.
-- ponytail: no hit-by-hit recap of my kills without the log, and a death's recap is the game's last few hits.

local _, DT = ...
local C = {}
DT.Combat = C

-- db: deaths = { { t, zone, sub, x, y, level, killer, player, with, amount, dmg, assists = { { name, dmg, player } } }, ... }
--     kills  = { { t, zone, sub, x, y, name, player, with, blow = true when the killing blow was mine }, ... }
-- newest last; x, y are map coordinates in percent, where the game gives them
-- both may have hits = { { seconds before the death, name, spell, amount, crit, player, k, a, r, b, o, m, i }, ... }, oldest
-- first (the named fields: see OnLog): on a death all that was done to me in the window, heals and attacks that did
-- not land included (hp = my full health); on a kill my own attacks on it. That is the recap.

local WINDOW = 10 -- seconds of damage before a death that count towards it
local KEEP = 500  -- entries kept per list; the oldest go first
local HITS = 30   -- of my hits on one target, the last so many are kept for its recap
local LISTED = 30 -- lines a recap lists one by one (the totals by ability cover all of them)
local dirty = true

local me
local taken = {}  -- damage I took lately: { t, name, player, spell, amount }
local dealt = {}  -- [guid] = { t, name, player, spell, blow }: what I hit lately
local lastDeath, lastKill = -100, nil

local function IsPlayer(guid)
	return type(guid) == "string" and guid:find("^Player%-") ~= nil
end

-- a pet is named with what it is: its owner is not in the log
local function Named(guid, name)
	name = name or "Unknown"
	return type(guid) == "string" and guid:find("^Pet%-") and (name .. " (pet)") or name
end

-- where and when this happened
local function Here(rec)
	rec.t = time()
	rec.zone = GetRealZoneText and GetRealZoneText() or "?"
	rec.sub = GetSubZoneText and GetSubZoneText() or ""
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
	if pos and pos.GetXY then
		local x, y = pos:GetXY()
		if x and y then rec.x, rec.y = math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10 end
	end
	return rec
end

local function Keep(list, rec)
	list[#list + 1] = rec
	while #list > KEEP do table.remove(list, 1) end
	dirty = true
end

-- what is kept of a hit, with its time turned into seconds before the death
local function Stored(hit, now)
	return { math.floor((now - hit.t) * 10 + 0.5) / 10, hit.name, hit.spell, hit.amount or 0, hit.crit, hit.player,
		k = hit.k, a = hit.a, r = hit.r, b = hit.b, o = hit.o, m = hit.m, i = hit.i }
end

local function Plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- names of what I have targeted, moused over or seen a nameplate of: the kill event names nobody
local seen, seenN, players, about = {}, 0, {}, {}
local function See(unit)
	local guid, name = Plain(UnitGUID and UnitGUID(unit)), Plain(UnitName and UnitName(unit))
	if type(guid) ~= "string" or type(name) ~= "string" then return end
	if not seen[guid] then
		seenN = seenN + 1
		if seenN > 400 then seen, seenN = {}, 1 end -- (ponytail: emptied when full; whatever is near is seen again)
	end
	seen[guid] = name
	if IsPlayer(guid) then
		players[name] = true
		-- what the game shows of them: guild, class, race, level (kept with the kill or death, on this machine only)
		local function Text(v)
			v = Plain(v)
			return type(v) == "string" and v ~= "" and v or nil
		end
		local a = about[name] or {}
		about[name] = a
		a.guild = Text(GetGuildInfo and GetGuildInfo(unit)) or a.guild
		if UnitClass then
			local class, file = UnitClass(unit)
			a.class, a.cfile = Text(class) or a.class, Text(file) or a.cfile
		end
		a.race = Text(UnitRace and UnitRace(unit)) or a.race
		a.lvl = tonumber(Plain(UnitLevel and UnitLevel(unit))) or a.lvl -- (-1: too high to be told)
	end
end

-- a record, with what was seen of the player it is about
local function Known(rec, name)
	for k, v in pairs(about[name] or {}) do rec[k] = v end
	return rec
end

local function NameOf(guid)
	if seen[guid] then return seen[guid] end
	if IsPlayer(guid) and GetPlayerInfoByGUID then
		local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, guid)
		name = ok and Plain(name)
		if type(name) == "string" and name ~= "" then return name end
	end
	return "Unknown"
end

-- Enemy players that have me as their target: [name] = when last seen so. Where the server tells nothing of
-- who struck me, whoever had me targeted when I died is the best there is to go by.
-- ponytail: looked at twice a second, on my target, focus, mouseover and every nameplate in view. Someone
-- out of sight, or with another target while their damage ticks, is missed; a healer's target counts.
local onMe = {}
local function Watch()
	local function Look(unit)
		if type(unit) ~= "string" then return end
		local ok, hit = pcall(function()
			return UnitExists(unit) and UnitIsPlayer(unit) and UnitCanAttack(unit, "player") and UnitIsUnit(unit .. "target", "player")
		end)
		if ok and Plain(hit) == true then
			See(unit)
			local name = Plain(UnitName(unit))
			if type(name) == "string" then onMe[name] = GetTime() end
		end
	end
	Look("target")
	Look("focus")
	Look("mouseover")
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, plates = pcall(C_NamePlate.GetNamePlates)
		for _, plate in ipairs(ok and type(plates) == "table" and plates or {}) do
			Look(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
		end
	end
end
C.Watch = Watch

-- What each of the last deaths was made of, for /dt deathtest: why one was kept or not.
local recapSaid = "not asked"
local lastRecap -- the time of the newest hit in the recap last used
local function Note(text)
	C.db.deathLog = C.db.deathLog or {}
	local log = C.db.deathLog
	log[#log + 1] = date("%d %b %H:%M:%S") .. "  " .. text
	while #log > 10 do table.remove(log, 1) end
end

function C.DeathReport()
	local log = C.db.deathLog or {}
	DT:Print("deathtest: the combat log is %s to addons here. The last %d deaths:", C.open and "open" or "closed", #log)
	for _, line in ipairs(log) do DT:Print("  " .. line) end
	if not log[1] then DT:Print("  none since this was added. Die once (to anything), then type this again.") end
end

-- the game's own death recap, as hits I took (see OnLog for what a hit is); nothing where there is none
local function FromRecap()
	if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then recapSaid = "the game has no death recap here" return end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents)
	if not ok then recapSaid = "the death recap raised an error: " .. tostring(events) return end
	events = Plain(events)
	if type(events) ~= "table" then recapSaid = "the death recap gave " .. (events == nil and "nothing (or kept it secret)" or type(events)) return end
	recapSaid = "the death recap gave " .. #events .. " events"
	local now, newest, out = GetTime(), nil, {}
	for _, e in ipairs(events) do
		local at = type(e) == "table" and tonumber(Plain(e.timestamp))
		if at then
			newest = math.max(newest or at, at)
			local kind, name, spell = Plain(e.event), Plain(e.sourceName), Plain(e.spellName)
			if kind == "SWING_DAMAGE" then spell = "Melee" end
			if kind == "ENVIRONMENTAL_DAMAGE" then
				spell = tostring(Plain(e.environmentalType) or "Environment")
				name = spell
			end
			-- (a hit names who dealt it by GUID too: a player's begins with "Player-", seen before or not)
			local guid = Plain(e.sourceGUID)
			if (type(name) ~= "string" or name == "") and type(guid) == "string" then name = NameOf(guid) end
			name = type(name) == "string" and name ~= "" and name or "Unknown"
			local byPlayer = IsPlayer(guid) or players[name] or false
			if byPlayer and name ~= "Unknown" then players[name] = true end
			local function N(v)
				v = tonumber(Plain(v))
				return v and v > 0 and v or nil
			end
			out[#out + 1] = { at = at, name = name, player = byPlayer, spell = type(spell) == "string" and spell or "Spell",
				amount = N(e.amount) or 0, o = N(e.overkill), a = N(e.absorbed), r = N(e.resisted), b = N(e.blocked),
				crit = Plain(e.critical) and true or nil, i = spell ~= "Melee" and tonumber(Plain(e.spellId)) or nil }
		end
	end
	if not out[1] then recapSaid = recapSaid .. ", none of them readable" return end
	-- (asked too soon, the game still holds the recap of the death before: that one is not this death's)
	if newest == lastRecap then recapSaid = recapSaid .. ", still those of the death before" return end
	lastRecap = newest
	table.sort(out, function(a, b) return a.at < b.at end)
	for _, hit in ipairs(out) do
		-- (the recap may reach further back than the window: such a hit still counts, at the window's edge)
		hit.t, hit.at = now - math.min(newest - hit.at, WINDOW - 0.1), nil
	end
	taken = out
	return true
end

-- PARTY_KILL as an event of its own (the closed combat log's stand-in for a kill)
local function OnPartyKill(attacker, target)
	if C.open then return end -- (the combat log tells it, and better)
	attacker, target = Plain(attacker), Plain(target)
	if type(target) ~= "string" then return end -- (inside dungeons the game hides who died)
	if not IsPlayer(target) then return end -- (mobs are not what this is for)
	local mine = attacker == me
	if not mine and Plain(UnitGUID and UnitGUID("target")) ~= target then return end -- (a group mate's kill of something else)
	local now, name = GetTime(), NameOf(target)
	-- (told already, by this event or by the honour line: the same kill)
	if lastKill and (lastKill.guid == target or lastKill.rec.name == name) and now - (lastKill.at or 0) < 5 then
		if mine then lastKill.rec.blow, dirty = true, true end
		return
	end
	local rec = Known(Here({ name = name, player = true, blow = mine or nil, hits = {} }), name)
	lastKill = { guid = target, rec = rec, at = now }
	Keep(C.db.kills, rec)
end

-- "Zed dies, honorable kill ...": a player I killed or helped to kill, by name (the game's own wording)
local honorPattern
local function OnHonor(text)
	if C.open then return end
	text = Plain(text)
	if type(text) ~= "string" then return end
	if not honorPattern then
		local form = type(COMBATLOG_HONORGAIN) == "string" and COMBATLOG_HONORGAIN or "%s dies, honorable kill Rank: %s (%d Honor Points)"
		honorPattern = "^" .. form:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%d?%$?s", "(.-)"):gsub("%%%d?%$?d", "(%%d+)")
	end
	-- ponytail: name, rank, honour in the English order; another language's order would swap rank and name
	local name, rank, honor = text:match(honorPattern)
	rank, honor = type(rank) == "string" and rank ~= "" and #rank < 40 and rank or nil, tonumber(honor)
	if type(name) ~= "string" or name == "" or #name > 60 then return end
	local now = GetTime()
	if lastKill and lastKill.rec.name == name and now - (lastKill.at or 0) < 5 then -- (PARTY_KILL told it first)
		lastKill.rec.rank, lastKill.rec.honor, dirty = rank, honor, true
		return
	end
	local rec = Known(Here({ name = name, player = true, rank = rank, honor = honor, hits = {} }), name)
	lastKill = { rec = rec, at = now }
	Keep(C.db.kills, rec)
end

local function Death()
	local now = GetTime()
	if now - lastDeath < 2 then return end -- (the game tells of a death in more than one way)
	lastDeath = now
	local by, order, last, hits, pvp = {}, {}, nil, {}, false
	for _, hit in ipairs(taken) do
		if now - hit.t <= WINDOW then
			hits[#hits + 1] = Stored(hit, now)
			if not hit.k then -- (damage: heals and the rest are in the recap, but kill nobody)
				pvp = pvp or hit.player or false
				local a = by[hit.name]
				if not a then
					a = { hit.name, 0, hit.player }
					by[hit.name], order[#order + 1] = a, a
				end
				a[2] = a[2] + (hit.amount or 0)
				last = hit
			end
		end
	end
	-- what there was to go by, for /dt deathtest
	local sources, watchers = {}, {}
	for _, a in ipairs(order) do sources[#sources + 1] = a[1] .. (a[3] and " (player)" or "") end
	for name, at in pairs(onMe) do
		if now - at <= WINDOW then watchers[#watchers + 1] = { name, at } end
	end
	table.sort(watchers, function(a, b) return a[2] > b[2] end)
	local names = {}
	for i, w in ipairs(watchers) do names[i] = w[1] end
	local function Said(kept)
		Note(("%s; struck by: %s; enemy players with me targeted: %s; %s"):format(C.open and "combat log open" or recapSaid,
			sources[1] and table.concat(sources, ", ") or "nobody known", names[1] and table.concat(names, ", ") or "none", kept))
		recapSaid = "not asked"
	end
	-- (this is for PvP: a death no player had a hand in, to a mob or a fall, is not kept)
	-- ponytail: players only where the log is closed (Forever, the only place this runs); the open-log path
	-- still keeps mobs, as its tests expect. Filter there too if this ever runs on such a client.
	if not pvp and not C.open then
		taken = {}
		if not watchers[1] then return Said("not kept: no player had a hand in it that I know of") end
		-- Nobody known to be a player struck (or nothing was told of who struck), but enemy players had me
		-- targeted: the death is theirs, as a guess (guess = true), the latest of them first.
		local rec = Here({ killer = watchers[1][1], player = true, guess = true, level = UnitLevel and UnitLevel("player") or nil, assists = {},
			hits = hits, hp = UnitHealthMax and UnitHealthMax("player") or nil })
		for i = 2, #watchers do rec.assists[#rec.assists + 1] = { watchers[i][1], 0, true } end
		Known(rec, rec.killer)
		onMe = {}
		Keep(C.db.deaths, rec)
		return Said("kept, by who had me targeted")
	end
	local rec = Here({ killer = last and last.name or "Unknown", player = last and last.player or false, with = last and last.spell,
		amount = last and last.amount, dmg = last and by[last.name][2], level = UnitLevel and UnitLevel("player") or nil, assists = {},
		hits = hits, hp = UnitHealthMax and UnitHealthMax("player") or nil })
	for _, a in ipairs(order) do
		if a[1] ~= rec.killer then rec.assists[#rec.assists + 1] = a end
	end
	table.sort(rec.assists, function(a, b) return a[2] > b[2] end)
	Known(rec, rec.killer)
	taken = {}
	onMe = {}
	Keep(C.db.deaths, rec)
	Said("kept")
end

local DAMAGE = { SPELL_DAMAGE = true, RANGE_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true }
local MISS = { SPELL_MISSED = true, RANGE_MISSED = true, SPELL_PERIODIC_MISSED = true, DAMAGE_SHIELD_MISSED = true }
local MISSED = { ABSORB = "absorbed", RESIST = "resisted", BLOCK = "blocked", DODGE = "dodged", PARRY = "parried", MISS = "missed",
	IMMUNE = "immune", DEFLECT = "deflected", EVADE = "evaded", REFLECT = "reflected" }

local function Plus(n)
	n = tonumber(n)
	return n and n > 0 and n or nil
end

-- A hit is: t, name, player, spell, amount, crit, and where they apply
--   k  what it was, if not damage: "heal", "miss" (an attack that did not land), "debuff", "interrupt"
--   a, r, b  how much was absorbed, resisted, blocked
--   o  overkill (of a heal: overheal)
--   m  how an attack missed ("dodged"); of an interrupt, the spell that was cut short
--   i  the spell's number (for its icon)
local function OnLog()
	local _, event, _, sGUID, sName, _, _, dGUID, dName = CombatLogGetCurrentEventInfo()
	if not event then return end
	-- (where the game hides the combat log from addons, nothing of it can be read: left alone)
	if issecretvalue and (issecretvalue(event) or issecretvalue(sGUID) or issecretvalue(dGUID)) then return end
	if event == "PARTY_KILL" then
		if sGUID == me then
			local d = dealt[dGUID] or { t = GetTime(), name = Named(dGUID, dName), player = IsPlayer(dGUID) }
			dealt[dGUID], d.blow = d, true
			-- (the death may have been told first)
			if lastKill and lastKill.guid == dGUID then lastKill.rec.blow, dirty = true, true end
		end
		return
	elseif event == "UNIT_DIED" then
		if dGUID == me then
			Death()
		elseif dealt[dGUID] and GetTime() - dealt[dGUID].t <= WINDOW then
			local d = dealt[dGUID]
			local rec = Here({ name = d.name, player = d.player, with = d.spell, blow = d.blow or nil, hits = {} })
			for i, hit in ipairs(d.hits or {}) do rec.hits[i] = Stored(hit, GetTime()) end
			dealt[dGUID], lastKill = nil, { guid = dGUID, rec = rec }
			Keep(C.db.kills, rec)
		end
		return
	end
	if dGUID ~= me and sGUID ~= me then return end
	local a = { select(12, CombatLogGetCurrentEventInfo()) } -- (what follows differs by event)
	local hit = { t = GetTime() }
	if event == "SWING_DAMAGE" then
		hit.spell, hit.amount, hit.o, hit.r, hit.b, hit.a, hit.crit = "Melee", a[1], Plus(a[2]), Plus(a[4]), Plus(a[5]), Plus(a[6]), a[7] and true or nil
	elseif event == "ENVIRONMENTAL_DAMAGE" then
		-- (falling, drowning, lava: nobody did it)
		sName = tostring(a[1] or "Environment")
		hit.spell, hit.amount, hit.o, hit.r, hit.b, hit.a = sName, a[2], Plus(a[3]), Plus(a[5]), Plus(a[6]), Plus(a[7])
	elseif DAMAGE[event] then
		hit.spell, hit.amount, hit.o, hit.r, hit.b, hit.a, hit.crit = a[2], a[4], Plus(a[5]), Plus(a[7]), Plus(a[8]), Plus(a[9]), a[10] and true or nil
	elseif event == "SWING_MISSED" or MISS[event] then
		local how, missed = a[1], a[3]
		hit.spell = "Melee"
		if event ~= "SWING_MISSED" then hit.spell, how, missed = a[2], a[4], a[6] end
		hit.k, hit.m, hit.amount = "miss", MISSED[how] or tostring(how or "missed"):lower(), missed
		if how == "ABSORB" then hit.a = Plus(missed) elseif how == "RESIST" then hit.r = Plus(missed) elseif how == "BLOCK" then hit.b = Plus(missed) end
	elseif dGUID == me and (event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL") then
		-- (what it healed me for: the overheal is told apart)
		hit.k, hit.spell, hit.amount, hit.o, hit.crit = "heal", a[2], (tonumber(a[4]) or 0) - (tonumber(a[5]) or 0), Plus(a[5]), a[7] and true or nil
	elseif dGUID == me and event == "SPELL_AURA_APPLIED" and a[4] == "DEBUFF" then
		hit.k, hit.spell = "debuff", a[2]
	elseif dGUID == me and event == "SPELL_INTERRUPT" then
		hit.k, hit.spell, hit.m = "interrupt", a[2], a[5]
	else
		return
	end
	hit.spell, hit.amount = hit.spell or "Spell", tonumber(hit.amount) or 0
	-- (the spell's number, for its icon; a swing and a fall have none)
	if hit.spell ~= "Melee" and event ~= "ENVIRONMENTAL_DAMAGE" then hit.i = tonumber(a[1]) end
	if dGUID == me then
		hit.name, hit.player = Named(sGUID, sName), IsPlayer(sGUID)
		taken[#taken + 1] = hit
		if #taken > 120 then table.remove(taken, 1) end
	elseif dGUID then
		-- (only damage makes it a target of mine: an attack that never landed does not)
		if hit.k and not dealt[dGUID] then return end
		local d = dealt[dGUID] or { hits = {} }
		d.name, d.player = Named(dGUID, dName), IsPlayer(dGUID)
		if not hit.k then d.t, d.spell = hit.t, hit.spell end
		hit.name = "Me"
		d.hits = d.hits or {}
		d.hits[#d.hits + 1] = hit
		if #d.hits > HITS then table.remove(d.hits, 1) end
		dealt[dGUID] = d
		-- ponytail: swept only on a hit; it stays small because what dies is taken out
		local n = 0
		for _ in pairs(dealt) do n = n + 1 end
		if n > 80 then
			for guid, old in pairs(dealt) do
				if hit.t - old.t > WINDOW then dealt[guid] = nil end
			end
		end
	end
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

-- The lists are tabs across the top (SIDE_W: nothing stands at the side any more), the search under them.
local ROW_H, SIDE_W, TOP_H, SIDE_H, TAB_W = 18, 0, 54, 20, 160
local VIEWS = {
	deaths = { label = "Who killed me", { "When", 124 }, { "Killed by", 170 }, { "With", 170 }, { "Where", 200 }, { "Helped by", 0 } },
	kills = { label = "Who did I kill", { "When", 124 }, { "Killed", 170 }, { "With", 170 }, { "Killing blow", 90 }, { "Where", 0 } },
	-- everybody met, once each: how often I killed them and they me
	players = { label = "Players", { "Player", 250 }, { "I killed", 70 }, { "Killed me", 80 }, { "Last met", 124 }, { "Where", 0 } },
}
local VIEW_ORDER = { "deaths", "kills", "players" }
local view = "deaths"
local sortBy = { deaths = { col = 1, desc = true }, kills = { col = 1, desc = true }, players = { col = 2, desc = true } }
local panel, side, search, countText, playersOnly, bar
local rows, heads, sideButtons, list, offset = {}, {}, {}, {}, 0
local onlyPlayers = false

-- A name in the colour of its class, where the class is known: from the record (cfile), else from what was
-- seen of them this session. Unknown: a player in red, anything else white.
local function Who(name, player, cfile)
	cfile = cfile or (about[name] and about[name].cfile)
	local col = cfile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cfile]
	if col and col.colorStr then return "|c" .. col.colorStr .. name .. "|r" end
	return (player and "|cffff4040" or "|cffffffff") .. name .. "|r"
end

-- the name with the guild after it, where one was seen
local function Tag(name, rec)
	return Who(name, rec.player, rec.cfile) .. (rec.guild and (" |cff888888<" .. rec.guild .. ">|r") or "")
end

local function Where(rec)
	return rec.sub ~= "" and rec.sub ~= rec.zone and (rec.sub .. ", " .. rec.zone) or rec.zone
end

-- Everybody I killed or was killed by, once each: { name, kills, deaths, t (the last meeting), rec (of it) }.
function C.Players(only)
	local by, all = {}, {}
	local function Add(name, rec, kill)
		if not name or (only and not rec.player) then return end
		local p = by[name]
		if not p then
			p = { name = name, kills = 0, deaths = 0, t = 0 }
			by[name], all[#all + 1] = p, p
		end
		if kill then p.kills = p.kills + 1 else p.deaths = p.deaths + 1 end
		-- (the newest record of them is the one shown; one that knows their guild or class is kept beside it)
		if (rec.t or 0) >= p.t then p.t, p.rec = rec.t or 0, rec end
		if rec.guild or rec.class then p.known = (not p.known or (rec.t or 0) >= (p.known.t or 0)) and rec or p.known end
	end
	for _, rec in ipairs(C.db.kills) do Add(rec.name, rec, true) end
	for _, rec in ipairs(C.db.deaths) do Add(rec.killer, rec, false) end
	return all
end

local function Rebuild()
	local q = (search:GetText() or ""):lower()
	list = {}
	if view == "players" then
		for _, p in ipairs(C.Players(onlyPlayers)) do
			local about, where = p.known or p.rec, Where(p.rec)
			local won = p.kills > p.deaths and "|cff40ff40" or p.kills < p.deaths and "|cffff6060" or "|cffffffff"
			if q == "" or (p.name .. " " .. (about.guild or "") .. " " .. where):lower():find(q, 1, true) then
				list[#list + 1] = { rec = about, player = p, Tag(p.name, about), won .. p.kills .. "|r", won .. p.deaths .. "|r",
					date("%a %d %b %H:%M", p.t), where, sort = { p.name, p.kills, p.deaths, p.t, where } }
			end
		end
	end
	for _, rec in ipairs(view ~= "players" and C.db[view] or {}) do
		local name = view == "deaths" and rec.killer or rec.name
		local when, where = date("%a %d %b %H:%M", rec.t), Where(rec)
		local with = rec.with and (rec.with .. (rec.amount and rec.amount > 0 and (" (%d)"):format(rec.amount) or ""))
			or (rec.guess and "|cff888888had me targeted|r") or ""
		local helpers = {}
		for _, a in ipairs(rec.assists or {}) do helpers[#helpers + 1] = Who(a[1], a[3]) .. (a[2] > 0 and (" " .. a[2]) or "") end
		local row
		if view == "deaths" then
			row = { rec = rec, when, Tag(name, rec), with, where, helpers[1] and table.concat(helpers, ", ") or "|cff888888nobody|r",
				sort = { rec.t, name, with, where, #helpers } }
		else
			row = { rec = rec, when, Tag(name, rec), rec.with or "", rec.blow and "|cff40ff40yes|r" or "|cff888888helped|r", where,
				sort = { rec.t, name, rec.with or "", rec.blow and 1 or 0, where } }
		end
		if (not onlyPlayers or rec.player) and (q == "" or (name .. " " .. (rec.guild or "") .. " " .. where .. " " .. with):lower():find(q, 1, true)) then
			list[#list + 1] = row
		end
	end
	local by = sortBy[view]
	table.sort(list, function(a, b)
		local x, y = a.sort[by.col], b.sort[by.col]
		if x ~= y then
			if by.desc then return x > y end
			return x < y
		end
		if view == "players" then return a.sort[1] < b.sort[1] end -- (by name)
		return a.sort[1] > b.sort[1]
	end)
end

---------------------------------------------------------------------------
-- The recap: what the damage was, by ability and hit by hit
---------------------------------------------------------------------------

local RED, GREEN, BLUE, PURPLE, YELLOW, GREY = "|cffff6060", "|cff40ff40", "|cff80c0ff", "|cffc080ff", "|cffffff00", "|cffaaaaaa"

-- the icon of a spell; a sword for a swing
local function Icon(id, spell)
	local get = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
	return id and get and get(id) or (spell == "Melee" and "Interface\\Icons\\INV_Sword_04") or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- what there is to say about a hit beside its amount: "critical, 30 absorbed, overkill 40"
local function Notes(hit, blow)
	local parts = {}
	if hit[5] then parts[#parts + 1] = YELLOW .. "critical|r" end
	if hit.a then parts[#parts + 1] = BLUE .. hit.a .. " absorbed|r" end
	if hit.r then parts[#parts + 1] = BLUE .. hit.r .. " resisted|r" end
	if hit.b then parts[#parts + 1] = BLUE .. hit.b .. " blocked|r" end
	if hit.o then parts[#parts + 1] = hit.k == "heal" and (GREY .. hit.o .. " overheal|r") or ("overkill " .. hit.o) end
	if blow then parts[#parts + 1] = "|cffff4040killing blow|r" end
	return table.concat(parts, ", ")
end

-- hits totalled by who and what
local function Tally(by, order, hit)
	local key = hit[2] .. "\0" .. hit[3]
	local a = by[key]
	if not a then
		a = { name = hit[2], spell = hit[3], player = hit[6], i = hit.i, n = 0, sum = 0, crits = 0, max = 0 }
		by[key], order[#order + 1] = a, a
	end
	a.n, a.sum, a.crits, a.max = a.n + 1, a.sum + hit[4], a.crits + (hit[5] and 1 or 0), math.max(a.max, hit[4])
end

-- "Level 60 Orc Warrior, Scout, 12 honour": what was seen of the player a record is about, or nil
function C.About(rec)
	local parts = {}
	if rec.lvl then parts[#parts + 1] = "Level " .. (rec.lvl > 0 and rec.lvl or "??") end
	if rec.race then parts[#parts + 1] = rec.race end
	if rec.class then
		local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.cfile]
		parts[#parts + 1] = col and col.colorStr and ("|c" .. col.colorStr .. rec.class .. "|r") or rec.class
	end
	local more = { parts[1] and table.concat(parts, " ") or nil }
	if rec.rank then more[#more + 1] = rec.rank end
	if rec.honor then more[#more + 1] = rec.honor .. " honor" end
	return more[1] and table.concat(more, ", ") or nil
end

-- The recap as rows for its window, with .title. A row is one of
--   { text = }   a line across
--   { head = }   a heading
--   { t, icon, left, amount, note, bar, heal, blow }   a table row: t is the time or the number of hits, bar the
--                share (0..1) drawn behind it, heal makes that green, blow marks the killing blow
function C.Recap(rec, death)
	local rows = { title = death and ("Killed by " .. Tag(rec.killer, rec)) or ("Killed " .. Tag(rec.name, rec)) }
	local function Line(text) rows[#rows + 1] = { text = text } end
	Line(date("%A %d %B %Y, %H:%M", rec.t) .. "  " .. GREY .. Where(rec) .. "|r")
	if C.About(rec) then Line(C.About(rec)) end
	if rec.guess then Line("|cffff9944A guess: the server did not say who struck. This is who had me targeted when I died.|r") end
	local hits = rec.hits
	if not hits or not hits[1] then
		-- (a kill where the combat log is closed: the game tells who died, never what I hit them with)
		Line("|cff888888" .. (not death and not C.open and "This server hides the hits of a kill from addons: only who, where and when are known."
			or ("Nothing was recorded for this one" .. (hits and "." or ": it is from before the recap was kept."))) .. "|r")
		return rows
	end
	local total, by, order, from, attackers, landed, lastDamage = 0, {}, {}, {}, 0, 0, nil
	local healed, over, heals, healOrder = 0, 0, {}, {}
	local absorbed, resisted, blocked, avoided, avoidedOrder = 0, 0, 0, {}, {}
	for i, hit in ipairs(hits) do
		if hit.k ~= "heal" then absorbed, resisted, blocked = absorbed + (hit.a or 0), resisted + (hit.r or 0), blocked + (hit.b or 0) end
		if not hit.k then
			Tally(by, order, hit)
			total, landed, lastDamage = total + hit[4], landed + 1, i
			if not from[hit[2]] then from[hit[2]], attackers = true, attackers + 1 end
		elseif hit.k == "heal" then
			Tally(heals, healOrder, hit)
			healed, over = healed + hit[4], over + (hit.o or 0)
		elseif hit.k == "miss" and not (hit.a or hit.r or hit.b) then
			local how = hit.m or "missed"
			if not avoided[how] then avoided[how], avoidedOrder[#avoidedOrder + 1] = 0, how end
			avoided[how] = avoided[how] + 1
		end
	end
	if death then
		Line((RED .. "%d|r damage taken in the last %d seconds, from %d attacker%s.%s"):format(total, WINDOW, attackers, attackers == 1 and "" or "s",
			rec.hp and rec.hp > 0 and (" My full health was %d."):format(rec.hp) or ""))
	else
		Line((RED .. "%d|r damage from me in %d hit%s%s."):format(total, landed, landed == 1 and "" or "s", rec.blow and ", the killing blow among them" or "; someone else struck the last blow"))
	end
	if healed > 0 or over > 0 then
		Line(("Healed for " .. GREEN .. "%d|r%s."):format(healed, over > 0 and (", and %d more was overheal"):format(over) or ""))
	end
	local soaked = {}
	if absorbed > 0 then soaked[#soaked + 1] = absorbed .. " absorbed" end
	if resisted > 0 then soaked[#soaked + 1] = resisted .. " resisted" end
	if blocked > 0 then soaked[#soaked + 1] = blocked .. " blocked" end
	if soaked[1] then Line("On top of that: " .. BLUE .. table.concat(soaked, ", ") .. "|r.") end
	if avoidedOrder[1] then
		for i, how in ipairs(avoidedOrder) do avoidedOrder[i] = avoided[how] .. " " .. how end
		Line("Not landed: " .. GREY .. table.concat(avoidedOrder, ", ") .. "|r.")
	end
	local function Section(title, by, order, sum, colour, named)
		if not order[1] then return end
		rows[#rows + 1] = { head = title }
		table.sort(order, function(a, b) return a.sum > b.sum end)
		for _, a in ipairs(order) do
			local share = a.sum / math.max(1, sum)
			rows[#rows + 1] = { t = a.n .. "x", icon = Icon(a.i, a.spell), left = (named and (named(a) .. ": ") or "") .. a.spell,
				amount = colour .. a.sum .. "|r", bar = share, heal = colour == GREEN,
				note = ("%d%%, biggest %d%s"):format(math.floor(share * 100 + 0.5), a.max, a.crits > 0 and (", %s%d critical|r"):format(YELLOW, a.crits) or "") }
		end
	end
	Section("Damage by ability", by, order, total, RED, death and function(a) return Who(a.name, a.player) end)
	Section("Healing", heals, healOrder, healed, GREEN, function(a) return Who(a.name) end)
	rows[#rows + 1] = { head = "As it happened  " .. GREY .. "(seconds before the death)|r" }
	local first = math.max(1, #hits - LISTED + 1)
	if first > 1 then Line(("|cff888888%d earlier lines not listed|r"):format(first - 1)) end
	for i = first, #hits do
		local hit = hits[i]
		local blow = i == lastDamage and (death or rec.blow) and true or false
		-- (a healer is no enemy: not in red)
		local row = { t = ("-%.1f"):format(hit[1]), icon = Icon(hit.i, hit[3]), left = (death and (Who(hit[2], hit.k ~= "heal" and hit[6]) .. ": ") or "") .. hit[3],
			note = Notes(hit, blow), blow = blow }
		if hit.k == "heal" then
			row.amount = GREEN .. "+" .. hit[4] .. "|r"
		elseif hit.k == "miss" then
			row.amount, row.note = GREY .. (hit.m or "missed") .. "|r", hit[4] > 0 and (GREY .. hit[4] .. " damage|r") or ""
		elseif hit.k == "debuff" then
			row.amount, row.note = "", PURPLE .. "debuff put on me|r"
		elseif hit.k == "interrupt" then
			row.amount, row.note = "", PURPLE .. "interrupted my " .. (hit.m or "spell") .. "|r"
		else
			row.amount = RED .. hit[4] .. "|r"
		end
		rows[#rows + 1] = row
	end
	return rows
end

-- columns of the recap window: time or count | icon | who: what | amount | notes
local RW, RH, X_ICON, X_LEFT, X_AMOUNT, X_NOTE = 580, 17, 40, 60, 268, 338
local recap

local function RecapRow(i)
	local row = CreateFrame("Frame", nil, recap)
	row:SetSize(RW - 20, RH)
	row:SetPoint("TOPLEFT", 10, -34 - (i - 1) * RH)
	row.bar = row:CreateTexture(nil, "BACKGROUND")
	row.bar:SetPoint("LEFT", X_ICON - 2, 0)
	row.bar:SetHeight(RH - 2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.icon:SetPoint("LEFT", X_ICON, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- (without the icon's own border)
	local function Text(x, width, justify, font)
		local fs = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
		fs:SetPoint("LEFT", x, 0)
		fs:SetWidth(width)
		fs:SetJustifyH(justify)
		fs:SetWordWrap(false)
		return fs
	end
	row.t = Text(0, X_ICON - 8, "RIGHT")
	row.left = Text(X_LEFT, X_AMOUNT - X_LEFT - 4, "LEFT")
	row.amount = Text(X_AMOUNT, X_NOTE - X_AMOUNT - 10, "RIGHT")
	row.note = Text(X_NOTE, RW - 20 - X_NOTE, "LEFT")
	row.text = Text(0, RW - 20, "LEFT")
	row.head = Text(0, RW - 20, "LEFT", "GameFontNormalSmall")
	recap.rows[i] = row
	return row
end

function C.ShowRecap(rec, death)
	if not recap then
		recap = CreateFrame("Frame", "DawnToolsRecap", UIParent, "BackdropTemplate")
		recap:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		recap:SetBackdropColor(0.06, 0.06, 0.07, 0.97)
		recap:SetBackdropBorderColor(0.78, 0.68, 0.37, 1)
		recap:SetFrameStrata("DIALOG")
		recap:SetClampedToScreen(true)
		recap:SetMovable(true)
		recap:EnableMouse(true)
		recap:RegisterForDrag("LeftButton")
		recap:SetScript("OnDragStart", recap.StartMoving)
		recap:SetScript("OnDragStop", recap.StopMovingOrSizing)
		recap:SetPoint("CENTER", 0, 40)
		table.insert(UISpecialFrames, "DawnToolsRecap") -- Esc closes it
		local shut = CreateFrame("Button", nil, recap, "UIPanelCloseButton")
		shut:SetPoint("TOPRIGHT", 2, 2)
		shut:SetScript("OnClick", function() recap:Hide() end) -- (the template's own closing goes through the game's panel code, which is barred to addons in combat: a plain Hide is not)
		recap.skull = recap:CreateTexture(nil, "ARTWORK")
		recap.skull:SetSize(18, 18)
		recap.skull:SetPoint("TOPLEFT", 10, -8)
		recap.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
		recap.title = recap:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		recap.title:SetPoint("LEFT", recap.skull, "RIGHT", 6, 0)
		recap.rows = {}
	end
	local rows = C.Recap(rec, death)
	recap.title:SetText(rows.title)
	for i = 1, math.max(#rows, #recap.rows) do
		local d = rows[i]
		local row = recap.rows[i] or (d and RecapRow(i))
		if row then
			row:SetShown(d and true or false)
			d = d or {}
			local cells = d.left ~= nil
			row.text:SetText(d.text or "")
			row.head:SetText(d.head or "")
			row.t:SetText(cells and (GREY .. d.t .. "|r") or "")
			row.left:SetText(d.left or "")
			row.amount:SetText(d.amount or "")
			row.note:SetText(d.note or "")
			row.icon:SetShown(cells)
			row.icon:SetTexture(d.icon)
			-- behind a total its share; behind the killing blow a red line across
			row.bar:SetShown((d.bar or d.blow) and true or false)
			row.bar:SetWidth(math.max(1, (d.blow and 1 or d.bar or 0) * (RW - 20 - X_ICON)))
			if d.heal then row.bar:SetColorTexture(0.2, 0.8, 0.2, 0.22) else row.bar:SetColorTexture(0.9, 0.2, 0.2, d.blow and 0.3 or 0.22) end
		end
	end
	recap:SetSize(RW, 44 + #rows * RH)
	recap:Show()
end

-- "12 deaths, 5 of them to players. Most often: Gorak (4)."
local function Summary()
	if view == "players" then
		local kills, deaths = 0, 0
		for _, row in ipairs(list) do kills, deaths = kills + row.player.kills, deaths + row.player.deaths end
		if #list == 0 then return "|cff888888Nobody met yet.|r" end
		return ("%d players: I killed them %d times, they killed me %d times. Click one for the fights."):format(#list, kills, deaths)
	end
	local n, players, count, top = 0, 0, {}, nil
	for _, row in ipairs(list) do
		local name = view == "deaths" and row.rec.killer or row.rec.name
		n, players = n + 1, players + (row.rec.player and 1 or 0)
		count[name] = (count[name] or 0) + 1
		if not top or count[name] > count[top] then top = name end
	end
	if n == 0 then
		return view == "deaths" and "|cff888888No deaths recorded yet.|r" or "|cff888888No kills recorded yet.|r"
	end
	return ("%d %s, %d of them %s players. Most often: %s (%d)."):format(n, view == "deaths" and "deaths" or "kills", players,
		view == "deaths" and "to" or "of", top, count[top])
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", SIDE_W + 8, -TOP_H - ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -12, 0)
	row.ccols = {}
	for c = 1, 5 do
		row.ccols[c] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.ccols[c]:SetJustifyH("LEFT")
		row.ccols[c]:SetWordWrap(false)
	end
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		local rec = d.rec
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if d.player then
			local p = d.player
			GameTooltip:AddLine(p.name)
			if C.About(rec) then GameTooltip:AddLine((rec.guild and ("<" .. rec.guild .. "> ") or "") .. C.About(rec), 1, 0.82, 0) end
			GameTooltip:AddLine(("I killed them %d times, they killed me %d times."):format(p.kills, p.deaths), 1, 1, 1)
			GameTooltip:AddLine("Last met " .. date("%A %d %B %Y, %H:%M", p.t) .. ", " .. Where(p.rec), 0.8, 0.8, 0.8, true)
			GameTooltip:AddLine("Click for the fights with them", 0.5, 0.8, 1)
			return GameTooltip:Show()
		end
		GameTooltip:AddLine(date("%A %d %B %Y, %H:%M", rec.t))
		GameTooltip:AddLine(Where(rec) .. (rec.x and (" (%.1f, %.1f)"):format(rec.x, rec.y) or ""), 1, 1, 1)
		if C.About(rec) then GameTooltip:AddLine((rec.guild and ("<" .. rec.guild .. "> ") or "") .. C.About(rec), 1, 0.82, 0) end
		if view == "deaths" then
			GameTooltip:AddLine(("Killed by %s%s%s"):format(rec.killer, rec.player and " (a player)" or "",
				rec.with and (", with " .. rec.with .. (rec.amount and rec.amount > 0 and (" for %d"):format(rec.amount) or "")) or ""), 1, 1, 1, true)
			if rec.dmg and rec.dmg > 0 then
				GameTooltip:AddLine(("%d damage from them in the last %d seconds"):format(rec.dmg, WINDOW), 0.8, 0.8, 0.8)
			end
			if rec.level then GameTooltip:AddLine("I was level " .. rec.level, 0.8, 0.8, 0.8) end
			for _, a in ipairs(rec.assists) do
				GameTooltip:AddLine(("Helped: %s%s, %s"):format(a[1], a[3] and " (a player)" or "", a[2] > 0 and (a[2] .. " damage") or "had me targeted"), 0.8, 0.8, 0.8)
			end
			if rec.guess then
				GameTooltip:AddLine("A guess: the server did not say who struck. These are the enemy players who had me targeted.", 1, 0.6, 0.3, true)
			end
		else
			GameTooltip:AddLine(("%s%s%s"):format(rec.name, rec.player and " (a player)" or "",
				rec.blow and ": the killing blow was mine" or ": I helped"), 1, 1, 1, true)
			if rec.with then GameTooltip:AddLine("My last hit: " .. rec.with, 0.8, 0.8, 0.8) end
		end
		if rec.hits and rec.hits[1] then GameTooltip:AddLine("Click for the recap: every hit and heal", 0.5, 0.8, 1) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self)
		local d = self.data
		if not d then return end
		if d.player then -- (a player: over to the list of the fights with them)
			view, offset = d.player.kills > 0 and "kills" or "deaths", 0
			search:SetText(d.player.name)
			return C.Refresh()
		end
		C.ShowRecap(d.rec, view == "deaths")
	end)
	rows[i] = row
	return row
end

local function Refresh()
	if not panel then return end
	dirty = false
	Rebuild()
	local cols, by = VIEWS[view], sortBy[view]
	local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H - ROW_H) / ROW_H))
	local max = math.max(0, #list - fit)
	offset = math.max(0, math.min(offset, max))
	bar:SetMinMaxValues(0, max)
	bar:SetValue(offset)
	bar:SetShown(max > 0)
	bar.thumb:SetSize(8, math.max(16, fit * ROW_H * fit / math.max(fit, #list)))
	-- the last column takes the width that is left
	local x, xs, widths = 0, {}, {}
	for c, col in ipairs(cols) do
		xs[c], widths[c] = x, col[2] > 0 and col[2] - 6 or math.max(60, panel:GetWidth() - SIDE_W - 8 - x - 16)
		x = x + col[2]
		heads[c]:ClearAllPoints()
		heads[c]:SetPoint("TOPLEFT", SIDE_W + 8 + xs[c], -TOP_H)
		heads[c]:SetSize(widths[c], ROW_H)
		heads[c].text:SetText("|cffffd100" .. col[1] .. (by.col == c and (by.desc and " v" or " ^") or "") .. "|r")
	end
	for i = 1, math.max(fit, #rows) do
		local d = i <= fit and list[offset + i]
		local row = rows[i] or (d and MakeRow(i))
		if row then
			row.data = d or nil
			row:SetShown(d and true or false)
			for c, cell in ipairs(row.ccols) do
				cell:SetText(d and d[c] or "")
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", xs[c], 0)
				cell:SetWidth(widths[c])
			end
		end
	end
	for key, b in pairs(sideButtons) do
		local n = key == "players" and #C.Players(onlyPlayers) or 0
		for _, rec in ipairs(key ~= "players" and C.db[key] or {}) do
			if not onlyPlayers or rec.player then n = n + 1 end
		end
		b.label:SetText(("%s (%d)"):format(VIEWS[key].label, n))
		b.sel:SetShown(key == view)
	end
	countText:SetText(Summary())
end
C.Refresh = Refresh

local function Build(parent)
	panel = parent
	-- the lists, as tabs across the top
	side = CreateFrame("Frame", nil, panel)
	side:SetPoint("TOPLEFT", 0, -2)
	side:SetPoint("TOPRIGHT", 0, -2)
	side:SetHeight(SIDE_H + 4)
	local shade = side:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, 0.04)
	for i, key in ipairs(VIEW_ORDER) do
		local b = CreateFrame("Button", nil, side)
		b:SetSize(TAB_W, SIDE_H)
		b:SetPoint("TOPLEFT", 2 + (i - 1) * (TAB_W + 4), -2)
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetAllPoints()
		b.sel:SetColorTexture(1, 0.82, 0, 0.18)
		local highlight = b:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)
		b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.label:SetPoint("LEFT", 6, 0)
		b.label:SetJustifyH("LEFT")
		b:SetScript("OnClick", function()
			view, offset = key, 0
			Refresh()
		end)
		sideButtons[key] = b
	end
	-- leave out wolves and the like
	playersOnly = CreateFrame("CheckButton", nil, side, "UICheckButtonTemplate")
	playersOnly:SetSize(22, 22)
	playersOnly:SetPoint("TOPLEFT", 2 + #VIEW_ORDER * (TAB_W + 4) + 8, -1)
	local playersText = playersOnly:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	playersText:SetPoint("LEFT", playersOnly, "RIGHT", 2, 0)
	playersText:SetText("Players only")
	playersOnly:SetScript("OnClick", function(self)
		onlyPlayers, offset = self:GetChecked() and true or false, 0
		Refresh()
	end)

	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("TOPLEFT", 10, -SIDE_H - 9)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function() -- (hooked: the template's own handler shows the "Search" hint)
		offset, dirty = 0, true
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	C.search = search
	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", search, "RIGHT", 12, 0)
	countText:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
	countText:SetJustifyH("LEFT")
	countText:SetWordWrap(false)

	-- column headers: click to sort, again to turn it round
	for c = 1, 5 do
		local h = CreateFrame("Button", nil, panel)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetJustifyH("LEFT")
		h.text:SetWordWrap(false)
		h:SetScript("OnClick", function()
			local by = sortBy[view]
			if by.col == c then
				by.desc = not by.desc
			else
				by.col, by.desc = c, c == 1 -- (time: newest first; names from A)
			end
			Refresh()
		end)
		heads[c] = h
	end

	bar = CreateFrame("Slider", nil, panel)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(8)
	bar:SetPoint("TOPRIGHT", -1, -TOP_H - ROW_H)
	bar:SetPoint("BOTTOMRIGHT", -1, 2)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.3)
	bar.thumb = bar:CreateTexture(nil, "OVERLAY")
	bar.thumb:SetColorTexture(0.78, 0.68, 0.37, 0.9)
	bar:SetThumbTexture(bar.thumb)
	bar:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value + 0.5)
		if value == offset then return end -- (Refresh sets the bar too)
		offset = value
		Refresh()
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Refresh()
	end)
	panel:SetScript("OnSizeChanged", Refresh)
	local nextUpdate = 0
	panel:SetScript("OnUpdate", function()
		if GetTime() < nextUpdate then return end
		nextUpdate = GetTime() + 0.5
		if dirty then Refresh() end
	end)
end

---------------------------------------------------------------------------
-- The module
---------------------------------------------------------------------------

DT:RegisterModule("combat", {
	title = "Combat",
	version = 1,
	slash = "/dtcombat",
	-- group: tabs of another group stand apart on the bar, behind a separator
	tab = { id = "combat", title = "Combat", defaultOrder = 60, group = 2, create = Build, onShow = Refresh },
	onEnable = function(mod)
		C.db = mod.db
		C.db.deaths, C.db.kills = C.db.deaths or {}, C.db.kills or {}
		me = UnitGUID("player")
		-- Is the combat log open to addons? Not on a client that hides values from them (WoW Forever, and the
		-- game from 12.0): there it is not even registered for, which would get the addon blocked.
		C.open = CombatLogGetCurrentEventInfo ~= nil
			and not (issecretvalue or C_CombatLogInternal or (C_CombatLog and C_CombatLog.IsCombatLogRestricted))
		if C.open then
			-- (this runs hundreds of times a second in a fight: should the game refuse us what is in it, that is
			-- noted a few times and then left be, not reported for every single event)
			local refused = 0
			DT:On("COMBAT_LOG_EVENT_UNFILTERED", function()
				if refused > 20 then return end
				local ok, err = pcall(OnLog)
				if not ok then
					refused = refused + 1
					DT:Debug("combat", "the combat log could not be read: %s", tostring(err))
				end
			end)
		end
		DT:On("PARTY_KILL", OnPartyKill)
		DT:On("CHAT_MSG_COMBAT_HONOR_GAIN", OnHonor)
		DT:On("PLAYER_TARGET_CHANGED", function() See("target") end)
		DT:On("UPDATE_MOUSEOVER_UNIT", function() See("mouseover") end)
		DT:On("NAME_PLATE_UNIT_ADDED", function(unit)
			if type(Plain(unit)) == "string" then See(unit) end
		end)
		-- The game's recap of a death is not ready the moment the death is told: it is asked for at once and,
		-- while it has nothing new, again after 0.3, 1 and 2 seconds. Only then is the death written down.
		local waiting = false
		DT:On("PLAYER_DEAD", function()
			pcall(Watch) -- (one last look at who is on me)
			if C.open then return Death() end
			if waiting then return end
			local waits, tries = { 0.3, 0.7, 1 }, 0
			local function Try()
				local ok, fresh = pcall(FromRecap)
				tries = tries + 1
				if (ok and fresh) or tries > #waits or not (C_Timer and C_Timer.After) then
					waiting = false
					recapSaid = recapSaid .. (tries > 1 and (" (asked %d times)"):format(tries) or "")
					return Death()
				end
				waiting = true
				C_Timer.After(waits[tries], Try)
			end
			Try()
		end)
		if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.5, function() pcall(Watch) end) end
	end,
	selfTest = function(_, Try)
		for _, v in ipairs({ "deaths", "kills" }) do
			Try("combat tab, " .. v, function()
				local was = view
				view = v
				Refresh()
				view = was
				Refresh()
			end)
		end
	end,
})
