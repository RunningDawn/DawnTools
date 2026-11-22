-- DawnRange
-- How far the target and the focus are, as a small number on screen. Local only.
-- The game gives no exact distance: the library LibRangeCheck-3.0 (MIT, embedded in Libs) tries spell, item and
-- interact ranges and answers with a band, 8 to 10 yards, or "40 and more". Shown is the end that matters:
-- "<=10" (with the real sign) for "no further than 10", ">40" where no far end is known.
-- Its options are the Range sub-tab of the Tools tab.

local _, DT = ...
local R = {}
DT.Range = R

-- db.settings: on (the whole tool; off until asked for), target, focus (which numbers), locked,
--              portrait (above the unit frame's portrait)
-- db.mark: "my range" in yards (0 = none): the number is green inside it, red beyond it
-- db.size: font size; db.pos[unit] = { point, relative point, x, y } where it was dragged to;
-- db.free[unit] = true: dragged, so it stays there though "portrait" is on

local SIZE_MIN, SIZE_MAX = 8, 32
local UNITS = {
	{ unit = "target", title = "Target", frame = "TargetFrame", x = 0 },
	{ unit = "focus", title = "Focus", frame = "FocusFrame", x = -120 },
}
-- The colour says how near: by the far end of the band (as RangeDisplay's defaults).
local BANDS = { { 5, "ffe6e6e6" }, { 20, "ff0edfd2" }, { 30, "ff09dd00" } } -- melee, short, medium
local FAR, PLAIN = "ffe60e13", "ffffd100"                                    -- 40 and beyond; anything else
local FAR_FROM = 40

-- "<=10" (the sign as one character) in its colour: no further than 10; ">40" when only the near end is
-- known; "27" when the exact distance is (min = max);
-- nil when the game says nothing.
-- mark (yards): "my range". The edges of a band are exact (they are the ranges of spells and items), so
-- whether the unit is inside 30 yards is known for certain even when the distance is not: green when the
-- whole band is inside the mark, red when it is all beyond, gold only where the band straddles it.
local IN, OUT = "ff40ff40", "ffff4040"
local LE = "\226\137\164" -- the less-than-or-equal sign (UTF-8)
function R.Text(min, max, mark)
	if not min then return nil end
	local color = min >= FAR_FROM and FAR or PLAIN
	if mark and mark > 0 then
		color = (max and max <= mark) and IN or min >= mark and OUT or PLAIN
	elseif max then
		for _, band in ipairs(BANDS) do
			if max <= band[1] then color = band[2] break end
		end
	end
	if max == min then return ("|c%s%d|r"):format(color, math.floor(min + 0.5)) end
	if max then return ("|c%s" .. LE .. "%d|r"):format(color, max) end
	return ("|c%s>%d|r"):format(color, min)
end

-- The exact distance, where the game tells where a unit stands: only members of my group, and not inside
-- instances. For everything else (every enemy) there are only the bands.
local function Exact(unit)
	if not UnitPosition then return nil end
	local y, x, _, where = UnitPosition("player")
	local uy, ux, _, uwhere = UnitPosition(unit)
	if not (x and ux) or where ~= uwhere then return nil end
	return math.sqrt((x - ux) ^ 2 + (y - uy) ^ 2)
end

---------------------------------------------------------------------------
-- My own spells as range tests
---------------------------------------------------------------------------
-- The library tests a short list of spells per class. Every spell this character knows that has a range is
-- one more exact edge, at the spell's real range now (talents and ranks counted), and spell tests go on
-- working in combat, when the library's item tests are barred. So the spellbook is read, and each of its
-- ranged spells asked "in range?" along with the library.
--   spells = { { id, name, range, min = its least range (a hunter's shots), 0 for none }, ... } nearest first

local spells, stale = {}, true

local function Collect()
	stale, spells = false, {}
	local seen = {}
	local function Add(id)
		if type(id) ~= "number" or seen[id] then return end
		seen[id] = true
		local name, least, range
		if C_Spell and C_Spell.GetSpellInfo then
			local info = C_Spell.GetSpellInfo(id)
			if info then name, least, range = info.name, info.minRange, info.maxRange end
		elseif GetSpellInfo then
			local _
			name, _, _, _, least, range = GetSpellInfo(id)
		end
		-- (no range: melee or on myself; the library's own melee test covers that)
		if name and range and range > 0 then
			spells[#spells + 1] = { id = id, name = name, range = math.floor(range + 0.5), min = math.floor((least or 0) + 0.5) }
		end
	end
	local B = C_SpellBook
	if B and B.GetNumSpellBookSkillLines and B.GetSpellBookSkillLineInfo and B.GetSpellBookItemInfo then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		for line = 1, B.GetNumSpellBookSkillLines() or 0 do
			local info = B.GetSpellBookSkillLineInfo(line)
			if info then
				for slot = (info.itemIndexOffset or 0) + 1, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0) do
					local item = B.GetSpellBookItemInfo(slot, bank)
					if item and not item.isPassive and not item.isOffSpec then Add(item.spellID) end -- (spells only: a flyout's number is none)
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then -- (the older spellbook)
		for tab = 1, GetNumSpellTabs() or 0 do
			local _, _, offset, count = GetSpellTabInfo(tab)
			for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do
				local kind, id = GetSpellBookItemInfo(slot, "spell")
				if kind == "SPELL" and not (IsPassiveSpell and IsPassiveSpell(slot, "spell")) then Add(id) end
			end
		end
	end
	table.sort(spells, function(a, b)
		if a.range ~= b.range then return a.range < b.range end
		return a.name < b.name
	end)
end

-- true / false, or nil where the spell cannot be cast on that unit at all (a heal on an enemy)
local function Reaches(s, unit)
	local r
	if C_Spell and C_Spell.IsSpellInRange then
		r = C_Spell.IsSpellInRange(s.id, unit)
	elseif IsSpellInRange then
		r = IsSpellInRange(s.name, unit)
	end
	if r == true or r == 1 then return true end
	if r == false or r == 0 then return false end
end

-- what my spells say of a unit: it is further than "near", and no further than "far" (either may be nil)
local function Spells(unit)
	if stale then pcall(Collect) end
	local near, far
	for _, s in ipairs(spells) do
		local ok, reaches = pcall(Reaches, s, unit)
		if ok and reaches == true then
			if not far or s.range < far then far = s.range end
			if s.min > 0 and (not near or s.min > near) then near = s.min end
		elseif ok and reaches == false and s.min == 0 then -- (one with a least range may also fail for being too near)
			if not near or s.range > near then near = s.range end
		end
	end
	return near, far
end

-- The library's band, narrowed by what the spells say. Where the two disagree (they round differently) the
-- spells are believed: theirs are the ranges that count when casting.
function R.Tighten(min, max, near, far)
	if not (near or far) then return min, max end
	local lo, hi = math.max(min or 0, near or 0), max
	if far and (not hi or far < hi) then hi = far end
	if hi and lo > hi then lo, hi = near or 0, far end
	if hi and lo > hi then lo = hi end
	return lo, hi
end

-- "20 Fire Blast, 30 Polymorph, 36 Wrath": each distance my spells can tell, with one spell that does
function R.SpellEdges()
	if stale then pcall(Collect) end
	local out, seen = {}, {}
	for _, s in ipairs(spells) do
		if not seen[s.range] then
			seen[s.range] = true
			out[#out + 1] = s.range .. " " .. s.name
		end
	end
	return out[1] and table.concat(out, ", ") or nil
end

local function Valid(unit)
	return UnitExists and UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) or false
end

-- the portrait of the game's own unit frame, whatever this client calls it; nil when the frame is not there
local function Portrait(u)
	local frame = _G[u.frame]
	if type(frame) ~= "table" then return nil end
	return (frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait) or frame.portrait or _G[u.frame .. "Portrait"] or frame
end

local driver
local function Place(u)
	local f, db = u.f, R.db
	f:ClearAllPoints()
	local portrait = db.settings.portrait and not db.free[u.unit] and Portrait(u)
	if portrait then
		f.placed = "portrait"
		f:SetPoint("BOTTOM", portrait, "TOP", 0, 4)
	else
		local pos = db.pos[u.unit] or { "CENTER", "CENTER", u.x, -120 }
		f.placed = "free"
		f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	end
end

-- everything as the settings and the units now are: which readouts show, where, how big, whether they can be dragged
function R.Apply()
	local s, any = R.db.settings, false
	for _, u in ipairs(UNITS) do
		local f = u.f
		local on = R.lib ~= nil and s.on and s[u.unit] and (Valid(u.unit) or not s.locked)
		f:SetShown(on and true or false)
		if on then
			any = true
			Place(u)
			-- the game's own font, without the black outline (a soft shadow instead): easier on the eye. It
			-- has no less-than-or-equal sign, so the sign is a text of its own in Arial, before the number.
			f.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", R.db.size, "")
			f.sign:SetFont("Fonts\\ARIALN.TTF", R.db.size, "")
			f.box:SetShown(not s.locked)
			f.name:SetShown(not s.locked)
			f:EnableMouse(not s.locked)
			f:EnableMouseWheel(not s.locked)
			f.last = nil -- (drawn anew)
		end
	end
	driver:SetShown(any)
end

local function Draw(u)
	local text = ""
	if Valid(u.unit) then
		local okExact, exact = pcall(Exact, u.unit) -- (positions may be hidden from addons in a fight)
		if okExact and type(exact) == "number" and exact == exact then
			text = R.Text(exact, exact, R.db.mark)
		else
			local ok, min, max = pcall(R.lib.GetRange, R.lib, u.unit)
			if not ok then min, max = nil, nil end
			min, max = R.Tighten(min, max, Spells(u.unit))
			text = R.Text(min, max, R.db.mark) or ""
		end
	end
	if text ~= u.f.last then
		u.f.last = text
		-- "|cffrrggbb<=30|r": the sign goes to its own text, in the same colour
		local color, body = text:match("^(|c%x%x%x%x%x%x%x%x)" .. LE .. "(.*)$")
		u.f.sign:SetText(color and (color .. LE .. "|r") or "")
		u.f.text:SetText(color and (color .. body) or text)
	end
end

function R.SetMark(yards)
	R.db.mark = math.max(0, math.min(100, math.floor(yards + 0.5)))
	R.Apply()
	if R.Refresh then R.Refresh() end
end

function R.SetSize(size)
	R.db.size = math.max(SIZE_MIN, math.min(SIZE_MAX, math.floor(size + 0.5)))
	R.Apply()
	if R.Refresh then R.Refresh() end
end

function R.Set(key, on)
	R.db.settings[key] = on and true or false
	if key == "portrait" and on then R.db.free = {} end -- (asked for anew: the dragged ones go back too)
	R.Apply()
	if R.Refresh then R.Refresh() end
	if key == "on" then DT.Tools.Show() end -- (its sub-tab changes colour)
end

function R.Reset()
	R.db.pos, R.db.free = {}, {}
	R.db.settings.portrait = true
	R.Apply()
	if R.Refresh then R.Refresh() end
end

local function MakeReadout(u)
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(96, 26)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f.box = f:CreateTexture(nil, "BACKGROUND")
	f.box:SetAllPoints()
	f.box:SetColorTexture(0.2, 0.6, 1, 0.25)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.text:SetPoint("CENTER", 4, 0)
	f.sign = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.sign:SetPoint("RIGHT", f.text, "LEFT", 0, 0)
	for _, fs in ipairs({ f.text, f.sign }) do
		fs:SetShadowColor(0, 0, 0, 0.9)
		fs:SetShadowOffset(1, -1)
	end
	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.name:SetPoint("BOTTOM", f, "TOP", 0, 1)
	f.name:SetText(u.title .. " range (drag; wheel: size)")
	f:SetScript("OnDragStart", function(self)
		if not R.db.settings.locked then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- (its place on the screen itself: it may have hung by a unit frame's portrait until now, and what
		-- the game then names as its point is measured from there)
		local cx, cy = self:GetCenter()
		if cx and cy then
			R.db.pos[u.unit] = { "CENTER", "BOTTOMLEFT", cx, cy }
		else
			local point, _, relative, x, y = self:GetPoint(1)
			R.db.pos[u.unit] = { point, relative, x, y }
		end
		R.db.free[u.unit] = true
		R.Apply()
	end)
	f:SetScript("OnMouseWheel", function(_, delta)
		R.SetSize(R.db.size + delta)
	end)
	f:Hide()
	u.f = f
	return f
end

---------------------------------------------------------------------------
-- The Range sub-tab
---------------------------------------------------------------------------

local ticks, sizeText, markText, libNote, edgesText = {}, nil, nil, nil, nil

-- The distances this character can tell apart right now: each is the range of a spell it knows, of an item
-- the game can test, or of an interaction (duel, follow). A band runs from one to the next.
local function Edges(getter)
	if not (R.lib and R.lib[getter]) then return nil end
	local out, seen = {}, {}
	local ok = pcall(function()
		for range in R.lib[getter](R.lib) do
			if type(range) == "number" and not seen[range] then seen[range], out[#out + 1] = true, range end
		end
	end)
	if not ok or not out[1] then return nil end
	table.sort(out)
	return table.concat(out, ", ")
end
R.Edges = Edges

function R.Refresh()
	if not sizeText then return end
	for key, box in pairs(ticks) do box:SetChecked(R.db.settings[key] and true or false) end
	sizeText:SetText(tostring(R.db.size))
	markText:SetText(R.db.mark > 0 and (R.db.mark .. " yd") or "off")
	edgesText:SetText(("|cffffd100The distances this character can tell apart now|r |cff888888(yards)|r\n\n"
		.. "|cff888888Against enemies:|r  %s\n\n"
		.. "|cff888888On friends:|r  %s\n\n"
		.. "|cff888888Your own spells|r |cff888888(their real range now, talents counted):|r  %s\n\n"
		.. "|cff888888Each is the range of a spell you know, of an item the game can test, or of an interaction.\n"
		.. "A band runs from one to the next: more spells with other ranges make finer bands.|r"):format(
		Edges("GetHarmCheckers") or "none", Edges("GetFriendCheckers") or "none", R.SpellEdges() or "none found"))
	libNote:SetShown(R.lib == nil)
end

local function Build(panel)
	local y = -6
	local function Line(font, text)
		local fs = panel:CreateFontString(nil, "OVERLAY", font)
		fs:SetPoint("TOPLEFT", 6, y)
		fs:SetPoint("RIGHT", -6, 0)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		fs:SetText(text)
		return fs
	end
	Line("GameFontNormal", "Range")
	y = y - 20
	Line("GameFontHighlightSmall", "How far your target and your focus are, as a small number on screen. The game only tells a band, "
		.. "not an exact distance: \"" .. LE .. "30\" is 30 yards or nearer (and further than the next smaller step), \">40\" is further than 40.")
	y = y - 34
	local function Tick(key, text)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("TOPLEFT", 4, y)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", box, "RIGHT", 2, 0)
		label:SetText(text)
		box:SetScript("OnClick", function(self) R.Set(key, self:GetChecked()) end)
		ticks[key] = box
		y = y - 24
	end
	Tick("on", "Show range (off: nothing of this tool runs)")
	y = y - 6
	Tick("target", "Range to my target")
	Tick("focus", "Range to my focus")
	Tick("locked", "Locked (unticked: drag the numbers where you want them; the mouse wheel over one changes the size)")
	Tick("portrait", "Above the portrait: each number sits just above its unit frame's portrait (a dragged one stays where it was put)")
	y = y - 6
	local sizeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sizeLabel:SetPoint("TOPLEFT", 8, y - 4)
	sizeLabel:SetText("Size")
	local function Step(text, x, by)
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(22, 20)
		b:SetPoint("TOPLEFT", x, y)
		b:SetText(text)
		b:SetScript("OnClick", function() R.SetSize(R.db.size + by) end)
		return b
	end
	R.smaller = Step("-", 44, -1)
	sizeText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sizeText:SetPoint("TOPLEFT", 72, y - 4)
	sizeText:SetWidth(24)
	sizeText:SetJustifyH("CENTER")
	R.bigger = Step("+", 100, 1)
	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(130, 20)
	reset:SetPoint("TOPLEFT", 150, y)
	reset:SetText("Reset positions")
	reset:SetScript("OnClick", R.Reset)
	R.reset = reset
	y = y - 28
	-- "my range": the number goes green inside it, red beyond
	local markLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	markLabel:SetPoint("TOPLEFT", 8, y - 4)
	markLabel:SetText("My range")
	local function MarkStep(text, x, by)
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(22, 20)
		b:SetPoint("TOPLEFT", x, y)
		b:SetText(text)
		b:SetScript("OnClick", function() R.SetMark(R.db.mark + by) end)
		return b
	end
	R.markLess = MarkStep("-", 66, -5)
	markText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	markText:SetPoint("TOPLEFT", 92, y - 4)
	markText:SetWidth(40)
	markText:SetJustifyH("CENTER")
	R.markMore = MarkStep("+", 136, 5)
	local markHelp = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	markHelp:SetPoint("TOPLEFT", 168, y - 4)
	markHelp:SetText("|cff40ff40green|r = inside it for certain, |cffff4040red|r = beyond it, |cffffd100gold|r = cannot tell. Off: colours by distance.")
	R.markText = markText
	y = y - 34
	Line("GameFontHighlightSmall", "Colours: |cffe6e6e6melee (to 5)|r   |cff0edfd2near (to 20)|r   |cff09dd00medium (to 30)|r   "
		.. "|cffffd100further|r   |cffe60e1340 and beyond|r")
	y = y - 30
	edgesText = Line("GameFontHighlightSmall", "")
	R.edgesText = edgesText
	y = y - 130
	libNote = Line("GameFontHighlightSmall", "|cffff8080The range library did not load: nothing can be shown.|r")
	R.ticks, R.sizeText = ticks, sizeText
end

DT:RegisterModule("range", {
	profile = { "size", "pos", "free", "mark" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "Range",
	version = 1,
	defaults = { on = false, target = true, focus = true, locked = true, portrait = true },
	onEnable = function(mod)
		R.db = mod.db
		local db = R.db
		db.size, db.pos, db.free, db.mark = db.size or 16, db.pos or {}, db.free or {}, db.mark or 0
		R.lib = LibStub and LibStub("LibRangeCheck-3.0", true) or nil
		for _, u in ipairs(UNITS) do MakeReadout(u) end
		R.units = UNITS
		-- ten times a second, and only while a number is on screen
		driver = CreateFrame("Frame", nil, UIParent)
		driver:Hide()
		local since = 0
		DT.OnUpdate(driver, "tool: Range", function(_, elapsed)
			since = since + (elapsed or 0.1)
			if since < 0.1 then return end
			since = 0
			for _, u in ipairs(UNITS) do
				if u.f:IsShown() then Draw(u) end
			end
		end)
		R.driver = driver
		for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
			DT:On(event, R.Apply)
		end
		-- (spells learned, talents moved: the spellbook is read anew at the next look)
		for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_ENTERING_WORLD" }) do
			DT:On(event, function() stale = true end)
		end
		DT:RegisterTool({ id = "range", title = "Range", order = 10, create = Build, onShow = R.Refresh,
			active = function() return R.db.settings.on end })
		if not SLASH_DAWNTOOLS_RANGE1 then
			SlashCmdList.DAWNTOOLS_RANGE = function() DT.Tools.Open("range") end
			SLASH_DAWNTOOLS_RANGE1 = "/dtrange"
		end
		R.Apply()
	end,
	selfTest = function(_, Try)
		Try("range readouts", R.Apply)
		Try("range text", function() assert(R.Text(8, 10) and R.Text(40) and R.Text() == nil) end)
		Try("range spells", function() R.SpellEdges() end)
	end,
})
