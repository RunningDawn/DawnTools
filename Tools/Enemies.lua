-- DawnTools :: Enemies
-- A small list on screen of the enemy players the game is showing me: name, level, class, roughly how far,
-- and whether they have ME as their target. Local only: nothing is sent, nothing is saved but the settings.
--
-- What this can and cannot know. This server closes the combat log to addons, so an enemy is known only
-- while the game shows them: their nameplate is up, or I target or mouse over them. Somebody behind me, out
-- of nameplate range or in stealth is not in the list. There is no arrow: the game tells an addon where the
-- members of its own group stand, never an enemy. Distance is a band ("20-25 yd"), as on the Range tool.
-- "ON YOU" is their target being me: looked at three times a second, and no proof that they attack.
--
-- It moves as the Tracker does: hold Shift and drag; a tick box locks it against that too. Without Shift it takes no clicks at all: they go through
-- it to the world behind, so it is neither moved by accident nor in the way of targeting.
--
-- ponytail: the units looked at are my target, focus, mouseover and every nameplate. No click to target
-- (a targeting button cannot be set up in combat, when new enemies turn up). Add group mates' targets, or
-- a click outside combat, if that is ever asked for.

local _, DT = ...
local E = { seen = {} }
DT.Enemies = E

local KEEP, MAX_LINES, EVERY = 10, 10, 0.3 -- seconds a lost enemy stays listed; lines shown; seconds between looks
local WIDTH, LINE_H = 250, 14

local function Plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- "8-10 yd", "40+ yd", or "" where nothing can be told
local function RangeText(unit)
	local lib = E.lib
	if not lib then return "", nil end
	local ok, min, max = pcall(lib.GetRange, lib, unit)
	min, max = ok and tonumber(Plain(min)) or nil, ok and tonumber(Plain(max)) or nil
	if min and max then return ("%d-%d yd"):format(min, max), max end
	if min then return ("%d+ yd"):format(min), min + 100 end
	return "", nil
end

-- One look at a unit: an enemy player is written down (or brought up to date). Says whether it was one.
local function Look(unit, now)
	if type(unit) ~= "string" then return false end
	local ok, enemy = pcall(function()
		return UnitExists(unit) and UnitIsPlayer(unit) and UnitCanAttack("player", unit)
	end)
	if not (ok and Plain(enemy) == true) then return false end
	local name = Plain(UnitName(unit))
	if type(name) ~= "string" or name == "" then return false end
	local e = E.seen[name]
	local new = e == nil
	if new then
		e = { name = name }
		E.seen[name] = e
	end
	if UnitClass then
		local class, file = UnitClass(unit)
		class, file = Plain(class), Plain(file)
		e.class, e.cfile = type(class) == "string" and class or e.class, type(file) == "string" and file or e.cfile
	end
	e.level = tonumber(Plain(UnitLevel and UnitLevel(unit))) or e.level -- (-1: too far above me to be told)
	-- Whose target they have: the game may refuse to say (an error), or say it in a value addons may not read
	-- (a "secret", as it does with much in combat). Then it is not known, and the line says so (blind) rather
	-- than passing "not on me" off as a fact.
	local okOn, on = pcall(function() return UnitIsUnit(unit .. "target", "player") end)
	local was = e.onMe
	local told = okOn and type(Plain(on)) == "boolean"
	e.blind = not told
	e.onMe = told and on == true
	e.range, e.far = RangeText(unit)
	e.at, e.here = now, true
	-- (a new face, or one that has just turned on me: worth a sound)
	if new then E.alert = E.alert or "new" end
	if e.onMe and not was then E.alert = "onMe" end
	return true
end

-- Looks at everything the game shows me, and forgets who has been gone too long.
function E.Scan()
	local now = GetTime()
	for _, e in pairs(E.seen) do e.here = false end
	Look("target", now)
	Look("focus", now)
	Look("mouseover", now)
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, plates = pcall(C_NamePlate.GetNamePlates)
		for _, plate in ipairs(ok and type(plates) == "table" and plates or {}) do
			Look(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit), now)
		end
	end
	for name, e in pairs(E.seen) do
		if not e.here then
			e.onMe = false -- (out of sight: who they are on is not known any more)
			if now - e.at > KEEP then E.seen[name] = nil end
		end
	end
end

-- The list, as it is shown: who is on me first, then the nearest, then those lost from sight (latest first).
function E.List()
	local list = {}
	for _, e in pairs(E.seen) do list[#list + 1] = e end
	table.sort(list, function(a, b)
		if a.here ~= b.here then return a.here end
		if a.onMe ~= b.onMe then return a.onMe end
		if a.here then
			local x, y = a.far or 1000, b.far or 1000
			if x ~= y then return x < y end
		elseif a.at ~= b.at then
			return a.at > b.at
		end
		return a.name < b.name
	end)
	return list
end

function E.LineText(e, now)
	local col = RAID_CLASS_COLORS and e.cfile and RAID_CLASS_COLORS[e.cfile]
	local name = (col and col.colorStr and ("|c" .. col.colorStr) or "|cffffffff") .. e.name .. "|r"
	local level = e.level and (e.level > 0 and tostring(e.level) or "??") or "?"
	local what = level .. (e.class and (" " .. e.class) or "")
	if not e.here then
		return ("%s  |cff888888%s  lost %ds ago|r"):format(name, what, math.floor(now - e.at + 0.5))
	end
	return ("%s  %s%s%s"):format(name, what, e.range ~= "" and ("  |cffcccccc" .. e.range .. "|r") or "",
		e.onMe and "  |cffff3030ON YOU|r" or (e.blind and "  |cff888888target hidden|r") or "")
end

---------------------------------------------------------------------------
-- On screen
---------------------------------------------------------------------------

local frame, lastSound = nil, 0

local function Draw()
	local now, list = GetTime(), E.List()
	local onMe, blind = 0, 0
	for _, e in ipairs(list) do onMe, blind = onMe + (e.onMe and 1 or 0), blind + (e.here and e.blind and 1 or 0) end
	frame.title:SetText(#list == 0 and "|cff888888Enemies: none in sight|r"
		or ("Enemies: %d%s%s"):format(#list, onMe > 0 and ("  |cffff3030%d on you|r"):format(onMe) or "",
			blind > 0 and "  |cff888888(game hides their targets now)|r" or ""))
	for i, line in ipairs(frame.lines) do
		local e = list[i]
		line:SetText(e and E.LineText(e, now) or "")
	end
	frame:SetHeight(20 + math.min(#list, MAX_LINES) * LINE_H + 4)
	frame.box:SetColorTexture(0, 0, 0, onMe > 0 and 0.55 or 0.35)
end

function E.Tick()
	E.Scan()
	if frame and frame:IsShown() then Draw() end
	local alert = E.alert
	E.alert = nil
	if alert and E.db.settings.sound and PlaySound and GetTime() - lastSound > 3 then
		lastSound = GetTime()
		-- (two sounds of the game's own: one for a new enemy, a louder one for someone turning on me)
		local kit = SOUNDKIT or {}
		pcall(PlaySound, alert == "onMe" and (kit.RAID_WARNING or 8959) or (kit.TELL_MESSAGE or 3081), "Master")
	end
end

function E.Apply()
	if not frame then return end
	local s = E.db.settings
	frame:SetShown(s.on)
	if E.Clicks then E.Clicks() end

	local pos = E.db.pos
	frame:ClearAllPoints()
	if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER", UIParent, "CENTER", 320, 120) end
	E.driver:SetShown(s.on)
	if s.on then Draw() end
end

function E.Set(key, on)
	E.db.settings[key] = on and true or false
	E.Apply()
	if E.Refresh then E.Refresh() end
	if key == "on" then DT.Tools.Show() end -- (its sub-tab changes colour)
end

local function MakeFrame()
	frame = CreateFrame("Frame", "DawnToolsEnemies", UIParent)
	frame:SetSize(WIDTH, 24)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame.box = frame:CreateTexture(nil, "BACKGROUND")
	frame.box:SetAllPoints()
	frame.box:SetColorTexture(0, 0, 0, 0.35)
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.title:SetPoint("TOPLEFT", 6, -5)
	-- It feels the mouse over it (for the tooltip) but takes clicks only while Shift is held (for the drag):
	-- without Shift a click goes straight through it to the world behind. (Passing clicks on while also
	-- taking them, as tried first, left the game dragging the camera instead of the list.)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	local function Clicks(on)
		on = on and not E.db.settings.locked -- (locked: never, Shift or no Shift)
		if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(on and true or false) end -- (a client without it: clicks always taken, as the Tracker)
	end
	E.Clicks = function() Clicks(IsShiftKeyDown and IsShiftKeyDown() or false) end
	local function Drop()
		if not frame.moving then return end
		frame.moving = nil
		frame:StopMovingOrSizing()
		local cx, cy = frame:GetCenter()
		if cx and cy then E.db.pos = { "CENTER", "BOTTOMLEFT", cx, cy } end
	end
	Clicks(IsShiftKeyDown and IsShiftKeyDown() or false)
	DT:On("MODIFIER_STATE_CHANGED", function(key, down)
		if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
		local held = down == 1 or (IsShiftKeyDown and IsShiftKeyDown()) or false
		if not held then Drop() end -- (Shift let go in mid-drag: it is put down where it is)
		Clicks(held)
	end)
	frame.lines = {}
	for i = 1, MAX_LINES do
		local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line:SetPoint("TOPLEFT", 6, -20 - (i - 1) * LINE_H)
		line:SetPoint("RIGHT", -4, 0)
		line:SetJustifyH("LEFT")
		line:SetWordWrap(false)
		frame.lines[i] = line
	end
	frame:SetScript("OnDragStart", function(self)
		-- (Shift, as on the Tracker: a plain drag across it moves nothing; locked, nothing does)
		if IsShiftKeyDown and IsShiftKeyDown() and not E.db.settings.locked then
			GameTooltip:Hide()
			self.moving = true
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", Drop)
	frame:SetScript("OnEnter", function(self)
		if not E.db.settings.tips then return end
		if IsShiftKeyDown and IsShiftKeyDown() then return end -- (about to be dragged: the tooltip would be in the way)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Enemies")
		GameTooltip:AddLine("Enemy players in sight. ON YOU: their target is you. \"target hidden\": the game would not say who their target is.", 1, 1, 1, true)
		GameTooltip:AddLine(E.db.settings.locked and "Locked in place (unlock it on the Tools tab to move it)." or "Hold Shift and drag to move.", 0.5, 0.8, 1)
		GameTooltip:AddLine("This tooltip can be switched off on the Tools tab.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
	E.frame = frame
	-- three looks a second, and only while the list is switched on
	E.driver = CreateFrame("Frame", nil, UIParent)
	E.driver:Hide()
	local since = 0
	DT.OnUpdate(E.driver, "tool: Enemies", function(_, elapsed)
		since = since + (elapsed or EVERY)
		if since < EVERY then return end
		since = 0
		pcall(E.Tick)
	end)
end

---------------------------------------------------------------------------
-- The tool's page
---------------------------------------------------------------------------

local boxes = {}
E.boxes = boxes

function E.Refresh()
	for key, box in pairs(boxes) do box:SetChecked(E.db.settings[key]) end
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
	Line("GameFontNormal", "Enemies", 20)
	Line("GameFontHighlightSmall", "A list on screen of the enemy players in sight: level, class, roughly how far, and |cffff3030ON YOU|r when "
		.. "one has you as their target. Sorted: on you first, then the nearest. One who leaves your sight stays listed for 10 seconds.\n"
		.. "Hold Shift and drag the list to move it.", 52)
	Line("GameFontDisableSmall", "Only who the game shows you: enemy nameplates must be on (or you target them). Nobody behind you, out of "
		.. "nameplate range or in stealth. No arrow: the game does not tell addons where an enemy stands. This server hides the combat log, "
		.. "so that is all there is to go by.", 46)
	local function Box(key, text)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("TOPLEFT", 4, y)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", box, "RIGHT", 2, 0)
		label:SetText(text)
		box:SetScript("OnClick", function(self) E.Set(key, self:GetChecked()) end)
		boxes[key] = box
		y = y - 24
	end
	Box("on", "Show the list of enemies")
	Box("locked", "Locked in place (Shift-drag moves it only while this is unticked)")
	Box("tips", "Show the tooltip when hovering the list (what it shows, how to move it)")
	Box("sound", "A sound for a new enemy, and a louder one when somebody turns on you")
end

DT:RegisterModule("enemies", {
	kind = "tool", -- (Settings > Tabs & Modules lists it under Tools)
	profile = { "pos" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "Enemies",
	version = 1,
	defaults = { on = false, locked = false, tips = true, sound = true },
	onEnable = function(mod)
		E.db = mod.db
		E.db.lockedOnce = nil -- (a leftover of its first day)
		E.lib = LibStub and LibStub("LibRangeCheck-3.0", true) or nil
		MakeFrame()
		DT:RegisterTool({ id = "enemies", title = "Enemies", order = 35, create = Build, onShow = E.Refresh,
			active = function() return E.db.settings.on end })
		if not SLASH_DAWNTOOLS_ENEMIES1 then
			SlashCmdList.DAWNTOOLS_ENEMIES = function() DT.Tools.Open("enemies") end
			SLASH_DAWNTOOLS_ENEMIES1 = "/dtenemies"
		end
		E.Apply()
	end,
	selfTest = function(_, Try)
		Try("enemies list", function()
			E.Scan()
			E.Apply()
		end)
	end,
})
