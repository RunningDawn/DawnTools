-- DawnTools :: Mitigation
-- A small column on screen, read again twice a second: how much of a physical hit my armor takes off; how often
-- a swing misses, is dodged, parried or blocked, each on its own line, and all four together; what a block
-- takes off; and (if ticked) what my resistances take off a spell of each school on average. Beside it a bar,
-- 100% high, that fills from the top in the order the game asks: miss, dodge, parry, block. What does not
-- fit under 100% is cut off the last ones: a block the swing never gets to is no block.
-- Against my target's level where I have an enemy targeted (a skull: three above mine), else my own.
-- Local only. Its options are the Mitigation sub-tab of the Tools tab.
-- ponytail: the old game's rules, not seen on Forever: armor / (armor + 400 + 85 * level), at most 75% (the
-- game's own function is used where the client has one); miss 5% and 0.04% a point of defense over the
-- attacker's weapon skill; resistance / (5 * level) * 75%, at most 75%; one roll for a swing, in that order;
-- my own swing misses an enemy of my level 5%, one level up 5.5%, two 6%, three and more 1% a level and 5% (8% at
-- three), less my hit. Not in "Hit": two weapons (19% more misses), the enemy's dodge and parry, spells.
-- The character pane's armor tooltip says the armor number against my own level, to hold it against.
-- ponytail: no size setting (FPS has one): add when somebody wants it bigger.
--
-- Since 0.59.0 it is the Stats pane (the module keeps its name, "mitigation", for what is saved). What it shows
-- is what my spec cares about (G.Recommended): the spec is the talent tree with the most points, as the BiS tab
-- reads it, and the lines are the stats its BiS profile weighs (Data/BisProfiles.lua): the above for a tank
-- only, then my hit, attack or ranged attack, spells, attributes; a stat the profile has a cap for is shown
-- against it ("425 / 440"). Where the spec cannot be told (no talents yet, BiS off): the above, and the groups
-- the class uses. With "choose myself" ticked (kept for each character: db.chars[me] = { override, show })
-- the groups ticked are shown in full instead. A number the client does not give is left out, line and all.
-- ponytail: the game's own numbers as the character pane has them; not seen on Forever which of these functions
-- it has (each is guarded). Spell power is the best school's; spell hit is what gear and talents add, as the
-- game says it. Haste, expertise and armor penetration have no line: no function known to ask. A tree with two
-- roles (Feral) is the one BiS takes it for.

local _, DT = ...
local G = {}
DT.Mitigation = G

local EVERY = 0.5 -- (seconds between readings)
local LINE, BAR, PAD, GAP = 11, 8, 7, 4 -- (a line's height, the bar's width, the room inside the border, between groups of lines)
-- the order a swing is decided in; and each one's colour, on the bar and for its line
local ORDER = {
	{ "miss", "Miss", 0.65, 0.65, 0.65 },
	{ "dodge", "Dodge", 0.3, 0.9, 0.4 },
	{ "parry", "Parry", 1, 0.82, 0 },
	{ "block", "Block", 0.35, 0.6, 1 },
}
G.ORDER = ORDER
local SCHOOLS = { { 2, "Fire" }, { 3, "Nature" }, { 4, "Frost" }, { 5, "Shadow" }, { 6, "Arcane" } } -- (UnitResistance's numbers)
local ATTR = { { "str", "Strength" }, { "agi", "Agility" }, { "sta", "Stamina" }, { "int", "Intellect" }, { "spi", "Spirit" } } -- (in UnitStat's order)
-- the groups of lines, as they are ticked, and the lines of each; "mit" is everything above them, with the bar
local LINES = { melee = { "hit", "ap", "crit" }, ranged = { "rap", "rcrit" }, spell = { "sp", "heal", "scrit", "shit", "mp5" }, attr = { "str", "agi", "sta", "int", "spi" } }
local GROUPS = { "mit", "melee", "ranged", "spell", "attr" }
-- the groups a class uses, where its spec cannot be told (m melee, r ranged, s spell)
local AUTO = { WARRIOR = "m", ROGUE = "m", HUNTER = "mr", PALADIN = "ms", SHAMAN = "ms", DRUID = "ms", MAGE = "s", WARLOCK = "s", PRIEST = "s" }
local LETTER = { melee = "m", ranged = "r", spell = "s" }
local f, ticks

local function Num(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok or (issecretvalue and issecretvalue(a)) or type(a) ~= "number" then return nil end
	return a, not (issecretvalue and issecretvalue(b)) and type(b) == "number" and b or nil
end

-- In a fight this client tells an addon none of the character's numbers. What was read last before it is kept
-- and shown on (held: something of what is shown is from before the fight); a buff or a proc in the fight is
-- not in it. What depends on the enemy's level is still worked out anew from the kept numbers.
local kept, held = {}, false
local function Kept(key, a, b)
	if a == nil and b == nil and kept[key] and InCombatLockdown and InCombatLockdown() then
		held = true
		return kept[key][1], kept[key][2]
	end
	kept[key] = { a, b }
	return a, b
end

-- the sum of the first three numbers a function gives (attack power: its base, what is added, what is taken off)
local function Sum(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b) or issecretvalue(c))) or type(a) ~= "number" then return nil end
	return a + (tonumber(b) or 0) + (tonumber(c) or 0)
end
-- the most a function gives over the schools of magic (2 holy to 7 arcane)
local function Best(fn)
	local best
	for school = 2, 7 do
		local n = Num(fn, school)
		if n and (not best or n > best) then best = n end
	end
	return best
end

-- what is kept for this character: { override = I choose myself, show = { [group] = true } }
local function Mine()
	local ok, guid = pcall(function() return UnitGUID and UnitGUID("player") or UnitName("player") end)
	local key = ok and guid or "?"
	G.db.chars = G.db.chars or {}
	G.db.chars[key] = G.db.chars[key] or {}
	return G.db.chars[key]
end

-- my spec's BiS profile (the tree with the most points), or nil where it cannot be told
local function Spec()
	local B = DT.Bis
	local ok, id = pcall(function() return B and B.Default and B.Default() end)
	for _, p in ipairs(ok and id and DT.BisProfiles or {}) do
		if p.id == id then return p end
	end
end

-- What my spec cares about: { mit = the mitigation lines and the bar, lines = { [line] = true }, caps = { [stat] = its cap }, spec = the profile }
function G.Recommended()
	local p, lines, caps, mit = Spec(), {}, {}, true
	if p then
		local w = p.w or {}
		local ranged = w.rap or w.rdps
		mit = p.role == "tank"
		lines.hit = w.hit and true
		lines[ranged and "rap" or "ap"] = (w.ap or w.rap or w.fap) and true
		lines[ranged and "rcrit" or "crit"] = w.crit and true
		lines.sp = w.sp and true
		for key in pairs(w) do
			if key:find("^sp_") then lines.sp = true end -- (one school's)
		end
		lines.heal, lines.scrit, lines.shit, lines.mp5 = w.heal and true, w.scrit and true, w.shit and true, w.mp5 and true
		for _, key in ipairs(LINES.attr) do lines[key] = w[key] and true end
		for key, c in pairs(p.caps or {}) do caps[key] = type(c) == "table" and c.cap or nil end
	else
		local ok, _, class = pcall(function() return UnitClass("player") end)
		lines.hit = true
		for group, letter in pairs(LETTER) do
			if (AUTO[ok and class or ""] or ""):find(letter, 1, true) then
				for _, key in ipairs(LINES[group]) do lines[key] = true end
			end
		end
	end
	return { mit = mit, lines = lines, caps = caps, spec = p }
end

-- What is shown: what my spec cares about, or with "choose myself" the groups ticked, in full.
function G.Plan()
	local plan, me = G.Recommended(), Mine()
	if me.override then
		local show = me.show or {}
		plan.mit, plan.lines = show.mit and true or false, {}
		for group, list in pairs(LINES) do
			for _, key in ipairs(show[group] and list or {}) do plan.lines[key] = true end
		end
	end
	plan.override = me.override and true or false
	return plan
end

-- is something of a group shown under a plan
function G.Shows(plan, group)
	if group == "mit" then return plan.mit end
	for _, key in ipairs(LINES[group] or {}) do
		if plan.lines[key] then return true end
	end
	return false
end

-- Defense as the Skills pane lists it: the skill, what is on it for a while, and what gear and talents add.
-- nil on a client without the pane's functions, or with the line folded away under its heading.
local function SkillDefense()
	if type(GetSkillLineInfo) ~= "function" then return nil end
	for i = 1, Num(GetNumSkillLines) or 0 do
		local ok, name, header, _, rank, temp, bonus = pcall(GetSkillLineInfo, i)
		if ok and not header and name == (DEFENSE or "Defense") and type(rank) == "number" and not (issecretvalue and issecretvalue(rank)) then
			return rank + (tonumber(temp) or 0) + (tonumber(bonus) or 0)
		end
	end
end

-- the old game's share of a physical hit that armor takes off, in percent
function G.Armor(armor, level)
	return math.max(0, math.min(75, 100 * armor / (armor + 400 + 85 * level)))
end

-- how often my own swing misses an enemy so many levels above me (below: 0 or less), before my hit, in percent
function G.Miss(above)
	local skill = above * 5 -- (its defense over my weapon skill)
	return math.max(0, 5 + skill * (skill > 10 and 0.2 or 0.1))
end

-- The swing's one roll: each of ORDER gets its share while there is room under 100, the later ones what is left.
-- Returns the shares (in ORDER's order) and their sum.
function G.Table(r)
	local out, left = {}, 100
	for i, o in ipairs(ORDER) do
		out[i] = math.max(0, math.min(left, r[o[1]] or 0))
		left = left - out[i]
	end
	return out, 100 - left
end

-- Returns { vs = the attacker's level, armor = % off a hit, miss, dodge, parry, block = % each as the sheet says,
-- def = my defense, gear's share in it; hit = % of my own swings at it that do not miss, bv = what a block takes off, shares = each as it fits on the roll, all = their sum,
-- res = { { school, % } } where asked for }. A number the client will not give (or hides in a fight) is left out.
function G.Read(resist, want)
	held = false
	want = want or {}
	local mine = Kept("mine", Num(UnitLevel, "player")) or 1
	local vs = mine
	if UnitExists and UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") then
		local level = Kept("vs", Num(UnitLevel, "target"))
		vs = level and level > 0 and level or mine + 3
	end
	local r = { vs = vs }
	local _, armor = Kept("armor", Num(UnitArmor, "player"))
	if armor then
		local share = C_PaperDollInfo and Num(C_PaperDollInfo.GetArmorEffectiveness, armor, vs)
		r.armor = Num(PaperDollFrame_GetArmorReduction, armor, vs) or (share and share * 100) or G.Armor(armor, vs)
	end
	local skill, bonus = Num(UnitDefense, "player")
	r.def = Kept("def", skill and skill + (bonus or 0) or SkillDefense()) -- (the skill and what gear adds to it)
	-- (a client that says it neither way: five a level and the defense on what I wear now, as BiS reads
	-- the gear. Talents, enchants and buffs are not in it. Not there while BiS is off)
	if not r.def and DT.Bis and DT.Bis.WornDefense then
		local ok, def = pcall(DT.Bis.WornDefense)
		r.def = ok and type(def) == "number" and def or nil
	end
	r.miss = math.max(0, 5 + ((r.def or mine * 5) - vs * 5) * 0.04)
	r.dodge, r.parry, r.block = Kept("dodge", Num(GetDodgeChance)) or 0, Kept("parry", Num(GetParryChance)) or 0, Kept("block", Num(GetBlockChance)) or 0
	r.bv = Kept("bv", Num(GetShieldBlock))
	local hit = (Kept("hit", Num(GetHitModifier)) or 0) + (Kept("hitRating", Num(GetCombatRatingBonus, CR_HIT_MELEE or 6)) or 0)
	r.hit, r.hitBonus = math.min(100, 100 - math.max(0, G.Miss(vs - mine) - hit)), hit
	r.shares, r.all = G.Table(r)
	if resist then
		r.res = {}
		for _, school in ipairs(SCHOOLS) do
			local _, total = Kept(school[2], Num(UnitResistance, "player", school[1]))
			if total then r.res[#r.res + 1] = { school[2], math.max(0, math.min(75, total / (vs * 5) * 75)) } end
		end
	end
	-- my own numbers, the groups asked for
	if want.melee then r.ap, r.crit = Kept("ap", Sum(UnitAttackPower, "player")), Kept("crit", Num(GetCritChance)) end
	if want.ranged then r.rap, r.rcrit = Kept("rap", Sum(UnitRangedAttackPower, "player")), Kept("rcrit", Num(GetRangedCritChance)) end
	if want.spell then
		r.sp, r.heal = Kept("sp", Best(GetSpellBonusDamage)), Kept("heal", Num(GetSpellBonusHealing))
		r.scrit, r.shit = Kept("scrit", Best(GetSpellCritChance)), Kept("shit", Num(GetSpellHitModifier))
		local idle, casting = Kept("regen", Num(GetManaRegen)) -- (a second: as it stands, and while casting)
		r.mp5, r.mp5c = idle and idle * 5, casting and casting * 5
	end
	if want.attr then
		r.attr = {}
		for i, a in ipairs(ATTR) do
			local _, total = Kept("attr" .. i, Num(UnitStat, "player", i))
			r.attr[a[1]] = total
		end
	end
	r.held = held
	return r
end

local function Pct(n) return n and ("%.1f%%"):format(n) or "?" end

local function Draw()
	local plan = G.Plan()
	local L, caps = plan.lines, plan.caps
	local r = G.Read(G.db.settings.resist, { melee = L.ap or L.crit, ranged = L.rap or L.rcrit,
		spell = L.sp or L.heal or L.scrit or L.shit or L.mp5, attr = G.Shows(plan, "attr") })
	-- Groups of lines, a small gap between them. For a tank: all of the roll and its parts in their order; armor,
	-- what a block takes off and defense. Then my own hit; the resistances; my attack, ranged attack, spells and
	-- attributes, the lines the plan has. Only a line with a number is drawn. Under them the level it is all against.
	local groups = { { {}, {} } }
	local function Group(rows)
		local any = false
		for _, row in ipairs(rows) do
			if row[2] then
				if not any and groups[#groups][1][1] then groups[#groups + 1] = { {}, {} } end
				any = true
				local g = groups[#groups]
				g[1][#g[1] + 1], g[2][#g[2] + 1] = row[1], row[2]
			end
		end
	end
	local function Int(n) return n and ("%d"):format(n) or nil end
	local function Of(text, cap) return text and cap and (text .. " / " .. ("%g"):format(cap)) or text end -- (against its cap)
	if plan.mit then
		local roll = { { "All", Pct(r.all) } }
		for _, o in ipairs(ORDER) do
			roll[#roll + 1] = { ("|cff%02x%02x%02x%s|r"):format(math.floor(o[3] * 255), math.floor(o[4] * 255), math.floor(o[5] * 255), o[2]), Pct(r[o[1]]) }
		end
		Group(roll)
		Group({ { "Armor", Pct(r.armor) }, { "Block value", r.bv and r.bv > 0 and Int(r.bv) or nil }, { "Defense", Of(Int(r.def), caps.def) } })
	end
	Group({ { "Hit", L.hit and Pct(r.hit) }, { "Hit bonus", L.hit and caps.hit and r.hitBonus and Of(("+%.1f"):format(r.hitBonus), caps.hit) or nil } })
	local res = {}
	for i, school in ipairs(r.res or {}) do res[i] = { "|cffb48cff" .. school[1] .. "|r", ("-%.1f%%"):format(school[2]) } end
	Group(res)
	Group({ { "Attack power", L.ap and Int(r.ap) }, { "Crit", L.crit and r.crit and Pct(r.crit) } })
	Group({ { "Ranged AP", L.rap and Int(r.rap) }, { "Ranged crit", L.rcrit and r.rcrit and Pct(r.rcrit) } })
	Group({ { "Spell power", L.sp and Int(r.sp) }, { "Healing", L.heal and r.heal and (r.heal ~= r.sp or not L.sp) and Int(r.heal) or nil },
		{ "Spell crit", L.scrit and r.scrit and Pct(r.scrit) },
		{ "Spell hit", L.shit and r.shit and (caps.shit or r.shit > 0) and Of(("+%.1f"):format(r.shit), caps.shit) or nil },
		{ "Mana / 5s", L.mp5 and r.mp5 and (r.mp5c and r.mp5c ~= r.mp5 and ("%d (%d)"):format(r.mp5, r.mp5c) or Int(r.mp5)) or nil } })
	local attrs = {}
	for _, a in ipairs(ATTR) do attrs[#attrs + 1] = { a[2], L[a[1]] and Int((r.attr or {})[a[1]]) } end
	Group(attrs)
	local height = 0
	for i = 1, math.max(#groups, #f.groups) do
		local g, at = groups[i], f.groups[i] or f.Group()
		f.groups[i] = at
		for k = 1, 2 do
			at[k]:ClearAllPoints()
			at[k]:SetPoint(k == 1 and "TOPLEFT" or "TOPRIGHT", f, k == 1 and "TOPLEFT" or "TOPRIGHT", k == 1 and PAD + BAR + 6 or -PAD, -PAD - height)
			at[k]:SetText(g and table.concat(g[k], "\n") or "")
			at[k]:SetShown(g ~= nil)
		end
		if g then height = height + #g[1] * LINE + GAP end
	end
	height = height - GAP
	f.vs:SetText("vs level " .. r.vs .. (r.held and "\n|cff888888as before the fight|r" or ""))
	f:SetSize(BAR + 130, height + GAP + (r.held and 28 or 14) + 2 * PAD) -- (a gap and the level's line under the rows)
	f.ground:SetHeight(math.max(height, 1))
	f.ground:SetShown(plan.mit)
	-- the bar: from the top, in the order of the roll
	local y = 0
	for i, seg in ipairs(f.segs) do
		local h = r.shares[i] / 100 * height
		seg:ClearAllPoints()
		seg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD - y)
		seg:SetSize(BAR, math.max(h, 0.01))
		seg:SetShown(plan.mit and h > 0)
		seg.share = r.shares[i]
		y = y + h
	end
end

function G.Apply()
	local s = G.db.settings
	local unlocked = not s.locked
	f:ClearAllPoints()
	local pos = G.db.pos or { "TOP", "TOP", 0, -60 }
	f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	-- (to be dragged: blue; locked: a dark ground to read it on)
	f.blue = unlocked
	if unlocked then f:SetBackdropColor(0.2, 0.6, 1, 0.3) else f:SetBackdropColor(0, 0, 0, 0.55) end
	f:SetBackdropBorderColor(0, 0, 0, unlocked and 0.9 or 0.55)
	f.name:SetShown(unlocked)
	f:EnableMouse(unlocked)
	f:SetShown(s.on and true or false)
	if s.on then Draw() end
	-- (the groups' ticks say what is shown; they are mine to change only with "choose myself")
	local plan = G.Plan()
	for key, box in pairs(ticks or {}) do
		if LINES[key] or key == "mit" then
			box:SetChecked(G.Shows(plan, key) and true or false)
			box:SetEnabled(plan.override)
		elseif key == "override" then
			box:SetChecked(plan.override)
		else
			box:SetChecked(s[key] and true or false)
		end
	end
	if G.specLine then
		G.specLine:SetText(plan.override and "Shown now: your own choice, kept for this character."
			or plan.spec and ("Shown now: what is recommended for |cffffffff%s|r (your talents)."):format(plan.spec.title or plan.spec.id)
			or "Shown now: by your class. Your spec could not be told (no talent points yet, or the BiS module is off).")
	end
end

function G.Set(key, on)
	if key == "override" then
		local me = Mine()
		-- (the first time: my own choice begins as what was recommended)
		if on and not me.show then
			local plan = G.Recommended()
			me.show = {}
			for _, group in ipairs(GROUPS) do me.show[group] = G.Shows(plan, group) or nil end
		end
		me.override = on and true or nil
	elseif LINES[key] or key == "mit" then
		local me = Mine()
		me.show = me.show or {}
		me.show[key] = on and true or nil
	else
		G.db.settings[key] = on and true or false
	end
	G.Apply()
	if key == "on" then DT.Tools.Show() end -- (its sub-tab changes colour)
end

local function MakeFrame()
	f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetSize(BAR + 126, 100)
	f:RegisterForDrag("LeftButton")
	-- (the tooltip's ground and border: its corners are round)
	f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	-- the bar's ground: what is left of it under the rest is a swing that lands
	f.ground = f:CreateTexture(nil, "BORDER")
	f.ground:SetPoint("TOPLEFT", PAD, -PAD)
	f.ground:SetSize(BAR, 100)
	f.ground:SetColorTexture(0.45, 0.1, 0.1, 0.8)
	f.segs = {}
	for i, o in ipairs(ORDER) do
		f.segs[i] = f:CreateTexture(nil, "ARTWORK")
		f.segs[i]:SetColorTexture(o[3], o[4], o[5], 1)
	end
	-- a group of lines: its names on the left, its numbers on the right (placed when drawn)
	f.groups = {}
	function f.Group()
		local pair = {}
		for k = 1, 2 do
			pair[k] = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			pair[k]:SetJustifyH(k == 1 and "LEFT" or "RIGHT")
			pair[k]:SetShadowColor(0, 0, 0, 0.9)
			pair[k]:SetShadowOffset(1, -1)
		end
		return pair
	end
	f.vs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- (the game's yellow)
	f.vs:SetPoint("BOTTOM", 0, PAD)
	f.vs:SetShadowColor(0, 0, 0, 0.9)
	f.vs:SetShadowOffset(1, -1)
	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.name:SetPoint("BOTTOM", f, "TOP", 0, 4)
	f.name:SetText("Stats (drag)")
	f:SetScript("OnDragStart", function(self) if not G.db.settings.locked then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relative, x, y = self:GetPoint(1)
		G.db.pos = { point, relative, x, y }
	end)
	local idle = 0
	DT.OnUpdate(f, "tool: Mitigation", function(_, dt) -- (runs only while it is shown)
		idle = idle + (dt or 0)
		if idle < EVERY then return end
		idle = 0
		Draw()
	end)
	f:Hide()
	G.f = f
end

local function Build(panel)
	local y = -6
	local function Line(font, text, height)
		local fs = panel:CreateFontString(nil, "OVERLAY", font)
		fs:SetPoint("TOPLEFT", 6, y)
		fs:SetPoint("RIGHT", -6, 0)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		fs:SetText(text)
		y = y - height
	end
	Line("GameFontNormal", "Stats", 20)
	Line("GameFontHighlightSmall", "On screen, as it changes: what your armor takes off a physical hit; how often a swing misses, is dodged, "
		.. "parried or blocked, and all four together; what a block takes off; your defense. "
		.. "\"Hit\" is how often your own swing at an enemy of that level does not miss (one weapon; its dodge and parry not counted). Against your target's level if it is an enemy "
		.. "(a skull counts as three above you), else your own.", 68)
	Line("GameFontHighlightSmall", "The bar is one swing, 100% high. It fills from the top in the order the game decides a swing: "
		.. "miss, dodge, parry, block. Red under them is a swing that lands. Past 100% the last in the order are cut short: "
		.. "the line still says what your sheet says, the bar what you get.", 44)
	ticks = {}
	local function Tick(key, text)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("TOPLEFT", 4, y)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", box, "RIGHT", 2, 0)
		label:SetText(text)
		box:SetScript("OnClick", function(self) G.Set(key, self:GetChecked()) end)
		ticks[key] = box
		y = y - 24
	end
	Tick("on", "Show the stats pane")
	Tick("locked", "Locked (unticked: drag it)")
	Tick("resist", "Resistances too: what each takes off a spell of its school, on average")
	y = y - 4
	local spec = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	spec:SetPoint("TOPLEFT", 6, y)
	spec:SetPoint("RIGHT", -6, 0)
	spec:SetJustifyH("LEFT")
	G.specLine = spec
	y = y - 16
	Tick("override", "Choose myself what is shown (kept for this character); unticked: what is recommended for my spec")
	local top = y
	Tick("mit", "Mitigation: the bar, miss, dodge, parry, block, armor, defense")
	Tick("melee", "Attack: hit, attack power, crit")
	Tick("ranged", "Ranged attack: attack power, crit")
	-- (the last two beside the first three: the page is not tall)
	local x, low = 330, y
	y = top
	local function Beside(key, text)
		Tick(key, text)
		ticks[key]:ClearAllPoints()
		ticks[key]:SetPoint("TOPLEFT", x, y + 24)
	end
	Beside("spell", "Spells: power, healing, crit, hit, mana / 5s")
	Beside("attr", "Attributes: the ones my spec uses")
	y = low - 6
	Line("GameFontDisableSmall", "A stat your spec has a cap for is shown against it (425 / 440). The numbers are the game's own, as your character pane has them; one this game does not give is left out.", 26)
	Line("GameFontDisableSmall", "Spells go past armor, dodge, parry and block. In a fight the game tells an addon none of your numbers: they stay as they were before it (the widget says so), "
		.. "and only what depends on the enemy's level moves. Defense is read from your Skills pane; where the game does not give that to an addon, it is your level's and your gear's, without talents, enchants and buffs.", 44)
	G.ticks = ticks
	G.Apply()
end

DT:RegisterModule("mitigation", {
	kind = "tool", -- (Settings > Tabs & Modules lists it under Tools)
	profile = { "pos" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "Stats",
	version = 1,
	defaults = { on = false, locked = false, resist = false },
	onEnable = function(mod)
		G.db = mod.db
		MakeFrame()
		DT:RegisterTool({ id = "mitigation", title = "Stats", order = 26, create = Build, onShow = G.Apply,
			active = function() return G.db.settings.on end })
		G.Apply()
	end,
	selfTest = function(_, Try)
		Try("mitigation display", G.Apply)
	end,
})
