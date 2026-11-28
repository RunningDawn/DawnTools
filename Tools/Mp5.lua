-- DawnMp5
-- The five-second rule, shown: after a spell that costs mana, regeneration from spirit stops for five seconds.
-- A small indicator counts those seconds down and is gone when regeneration is back. Local only.
--
-- On Forever there are no two-second mana ticks (mana comes back evenly) and addons cannot read mana in
-- combat, so nothing is measured: the five seconds are counted from my own casts of spells that cost mana,
-- and held while such a spell is channelled.
-- ponytail: casts only. Mana lost to something that is no cast of mine (a drain) is not seen, and a cast
-- made free by an effect may still start the count.
-- Its options are the MP5 sub-tab of the Tools tab.

local _, DT = ...
local M = {}
DT.Mp5 = M

-- db.settings: on (off until asked for), locked, seconds (the number beside the bar / in the clock)
-- db.look: "spark" | "bar" | "clock" | "number"
-- db.pos[look] = { point, relative point, x, y }; db.size[look] = { width, height } (bar, clock) or a number
-- (number: font size; spark: how thick the line is)

local RULE = 5
local LOOKS = { { "spark", "Spark on my mana bar" }, { "bar", "Thin bar" }, { "clock", "Small clock" }, { "number", "Number" } }
local DEFAULT = { spark = 2, bar = { 120, 6 }, clock = { 24, 24 }, number = 16 }
local LIMIT = { spark = { 1, 8 }, number = { 8, 40 }, bar = { 2, 30 }, clock = { 12, 64 } } -- (bar: its height; clock: its side)
local GOLD = { 1, 0.82, 0 }
local NO_MANA = { WARRIOR = true, ROGUE = true }

local f, spark, driver -- the indicator (bar, clock, number), the line over the mana bar, the clock that runs them
local endsAt, held, channelling

---------------------------------------------------------------------------
-- What starts the count
---------------------------------------------------------------------------

-- whether a spell costs mana. A cost the game will not show (in combat) on a mana entry counts as one.
local function CostsMana(id)
	local get = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
	if not (get and id) then return false end
	local ok, yes = pcall(function()
		for _, c in ipairs(get(id) or {}) do
			if c.type == 0 or c.name == "MANA" then
				if issecretvalue and issecretvalue(c.cost) then return true end
				if (tonumber(c.cost) or 0) > 0 or (tonumber(c.costPercent) or 0) > 0 then return true end
			end
		end
		return false
	end)
	return ok and yes or false
end
M.CostsMana = CostsMana

-- Whether a spell is one of mine, from the spellbook. The game also reports spells nobody cast on purpose
-- (procs, passive effects, the server's own helpers); one of those with a mana cost on paper, coming every
-- few seconds, kept the count running for ever. Where the game has no way to ask, every spell counts.
local function Mine(id)
	local ok, yes = pcall(function()
		if IsPlayerSpell then return IsPlayerSpell(id) end
		if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
		if IsSpellKnown then return IsSpellKnown(id) end
		return true
	end)
	return not ok or yes ~= false
end
M.Mine = Mine

local function HasMana()
	local _, class = UnitClass("player")
	return not NO_MANA[class or ""]
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- the game's own mana bar of the player frame, whatever this client calls it; nil when it is not there
local function ManaBar()
	local bar
	pcall(function() bar = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar end)
	bar = bar or _G.PlayerFrameManaBar
	if type(bar) ~= "table" or not bar.GetWidth then return nil end
	if bar.IsVisible and not bar:IsVisible() then return nil end
	return bar
end

-- the look in use: the one picked, or the thin bar where the spark has no mana bar to run on
function M.Look()
	local look = M.db.look
	if look == "spark" and not ManaBar() then return "bar", true end
	return look, false
end

local function Size(look)
	local size = M.db.size[look]
	if type(DEFAULT[look]) == "table" then
		return type(size) == "table" and size or { DEFAULT[look][1], DEFAULT[look][2] }
	end
	return type(size) == "number" and size or DEFAULT[look]
end

local function Active()
	return M.db.settings.on and HasMana()
end

-- seconds left to show now, or nil when there is nothing to show. Unlocked and idle: it stands still and
-- full, so the indicator can be seen while it is put in place. (It used to run round as a demonstration,
-- which looked like a count that never stopped.)
local function Left(now)
	if held then return RULE end
	if endsAt and endsAt > now then return endsAt - now end
	if not M.db.settings.locked then return RULE end
end

local function Draw(now)
	local left = Active() and Left(now)
	local look = M.Look()
	-- (the game's mana bar came or went: laid out anew for the look that is now the one)
	if M.laid and look ~= M.laid then return M.Apply() end
	if not left then
		endsAt = nil
		f:Hide()
		spark:Hide()
		driver:Hide()
		return
	end
	local part = left / RULE
	local seconds = ("%.1f"):format(left)
	if look == "spark" then
		local bar = ManaBar()
		spark.line:ClearAllPoints()
		spark.line:SetPoint("CENTER", spark, "LEFT", (bar and bar:GetWidth() or 0) * part, 0)
		spark.at = part
		spark:Show()
		f:Hide()
		return
	end
	spark:Hide()
	f:Show()
	local size = Size(look)
	if look == "bar" then
		f.fill:SetWidth(math.max(1, size[1] * part))
		f.text:SetText(M.db.settings.seconds and seconds or "")
	elseif look == "clock" then
		f.fill:SetHeight(math.max(1, size[2] * part))
		f.text:SetText(M.db.settings.seconds and ("%d"):format(math.ceil(left)) or "")
	else
		f.text:SetText(seconds)
	end
	f.part = part
end

-- everything as the settings now are: which parts there are, how big, where, whether it can be dragged
function M.Apply()
	local s, look, fell = M.db.settings, M.Look()
	M.fell, M.laid = fell, look
	local unlocked = not s.locked
	local size = Size(look)
	f:ClearAllPoints()
	local pos = M.db.pos[look] or { "CENTER", "CENTER", 0, -160 }
	f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	f.fill:ClearAllPoints()
	f.text:ClearAllPoints()
	local font = 12
	if look == "bar" then
		f:SetSize(size[1], size[2])
		f.fill:SetPoint("LEFT", 0, 0)
		f.fill:SetHeight(size[2])
		f.text:SetPoint("LEFT", f, "RIGHT", 4, 0)
		font = math.max(9, math.min(18, size[2] + 6))
	elseif look == "clock" then
		f:SetSize(size[1], size[2])
		f.fill:SetPoint("BOTTOM", 0, 0)
		f.fill:SetWidth(size[1])
		f.text:SetPoint("CENTER")
		font = math.max(8, math.floor(size[2] * 0.55))
	elseif look == "number" then
		f:SetSize(size * 3.2, size * 1.5)
		f.text:SetPoint("CENTER")
		font = size
	end
	f.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", font, "") -- (no black outline: a soft shadow, as the Range number)
	f.fill:SetShown(look == "bar" or look == "clock")
	f.back:SetShown(look == "bar" or look == "clock")
	f.box:SetShown(unlocked)
	f.name:SetShown(unlocked)
	f.grip:SetShown(unlocked and (look == "bar" or look == "clock"))
	f:EnableMouse(unlocked)
	f:EnableMouseWheel(unlocked)
	-- the spark: a line over the game's mana bar, as thick as asked
	local bar = ManaBar()
	if bar then
		spark:ClearAllPoints()
		spark:SetAllPoints(bar)
		spark.line:SetSize(Size("spark"), (bar.GetHeight and bar:GetHeight() or 10) + 4)
	end
	driver:SetShown(Active() and (endsAt ~= nil or held or unlocked) or false)
	Draw(GetTime())
end

function M.Start(now)
	if not Active() then return end
	endsAt, held = (now or GetTime()) + RULE, false
	driver:Show()
	Draw(now or GetTime())
end

local function Changed()
	M.Apply()
	if M.Refresh then M.Refresh() end
end

function M.Set(key, on)
	M.db.settings[key] = on and true or false
	Changed()
	if key == "on" then DT.Tools.Show() end -- (its sub-tab changes colour)
end

function M.SetLook(look)
	M.db.look = look
	Changed()
end

-- bigger or smaller, whatever that is for the look in use: the number's size, the spark's thickness, the
-- bar's height, the clock's side
function M.Resize(by)
	local look = M.db.look == "spark" and "spark" or M.Look()
	local limit, size = LIMIT[look], Size(look)
	local function Clamp(n) return math.max(limit[1], math.min(limit[2], math.floor(n + 0.5))) end
	if look == "bar" then
		M.db.size.bar = { size[1], Clamp(size[2] + by) }
	elseif look == "clock" then
		local side = Clamp(size[2] + by * 2)
		M.db.size.clock = { side, side }
	else
		M.db.size[look] = Clamp(size + by)
	end
	Changed()
end

function M.Reset()
	M.db.pos, M.db.size = {}, {}
	Changed()
end

local function MakeFrames()
	f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(12, 2, 400, 64) end
	f:RegisterForDrag("LeftButton")
	f.box = f:CreateTexture(nil, "BACKGROUND")
	f.box:SetPoint("TOPLEFT", -3, 3)
	f.box:SetPoint("BOTTOMRIGHT", 3, -3)
	f.box:SetColorTexture(0.2, 0.6, 1, 0.25)
	f.back = f:CreateTexture(nil, "BORDER")
	f.back:SetAllPoints()
	f.back:SetColorTexture(0, 0, 0, 0.45)
	f.fill = f:CreateTexture(nil, "ARTWORK")
	f.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	f.text:SetShadowColor(0, 0, 0, 0.9)
	f.text:SetShadowOffset(1, -1)
	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.name:SetPoint("BOTTOM", f, "TOP", 0, 4)
	f.name:SetText("MP5 (drag; corner: size)")
	f:SetScript("OnDragStart", function(self)
		if not M.db.settings.locked then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relative, x, y = self:GetPoint(1)
		M.db.pos[(M.Look())] = { point, relative, x, y }
	end)
	f:SetScript("OnMouseWheel", function(_, delta) M.Resize(delta) end)
	-- the corner to pull the bar or the clock bigger by
	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(10, 10)
	f.grip:SetPoint("BOTTOMRIGHT", 4, -4)
	local corner = f.grip:CreateTexture(nil, "OVERLAY")
	corner:SetAllPoints()
	corner:SetColorTexture(1, 1, 1, 0.7)
	f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	f.grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		local look = M.Look()
		local limit = LIMIT[look]
		local w, h = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
		if look == "clock" then
			local side = math.max(limit[1], math.min(limit[2], math.max(w, h)))
			M.db.size.clock = { side, side }
		elseif look == "bar" then
			M.db.size.bar = { math.max(20, math.min(400, w)), math.max(limit[1], math.min(limit[2], h)) }
		end
		local point, _, relative, x, y = f:GetPoint(1)
		M.db.pos[look] = { point, relative, x, y }
		Changed()
	end)
	f:Hide()

	spark = CreateFrame("Frame", nil, UIParent)
	spark:SetFrameStrata("HIGH")
	spark.line = spark:CreateTexture(nil, "OVERLAY")
	spark.line:SetColorTexture(1, 0.95, 0.6, 0.95)
	spark:Hide()

	driver = CreateFrame("Frame", nil, UIParent)
	driver:Hide()
	-- (about 30 redraws a second look smooth for a five-second count and spare the per-frame SetPoint/SetText)
	local idle = 0
	DT.OnUpdate(driver, "tool: Mp5", function(_, dt)
		idle = idle + (dt or 0)
		if idle < 0.03 then return end
		idle = 0
		Draw(GetTime())
	end)
	M.f, M.spark, M.driver = f, spark, driver
end

---------------------------------------------------------------------------
-- The MP5 sub-tab
---------------------------------------------------------------------------

local ticks, lookButton, sizeText, note = {}, nil, nil, nil

function M.Refresh()
	if not lookButton then return end
	for key, box in pairs(ticks) do box:SetChecked(M.db.settings[key] and true or false) end
	for _, l in ipairs(LOOKS) do
		if l[1] == M.db.look then lookButton.label:SetText("Look: " .. l[2]) end
	end
	local look = M.db.look == "spark" and "spark" or M.Look()
	local size = Size(look)
	sizeText:SetText(type(size) == "table" and (size[1] .. " x " .. size[2]) or tostring(size))
	note:SetText(not HasMana() and "|cffff8080This character has no mana: there is nothing to show.|r"
		or ((M.fell and "|cffffd100The game's own mana bar is not there (replaced unit frames?): the thin bar is shown instead of the spark.|r\n" or "")
			.. (M.last and ("|cff888888Last started by: " .. M.last .. "|r") or "")))
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
	Line("GameFontNormal", "MP5: the five-second rule")
	y = y - 20
	Line("GameFontHighlightSmall", "After a spell that costs mana, the mana you get back from spirit stops for five seconds. "
		.. "This counts those five seconds down and is gone when it is back. Channelled spells hold it until they end.")
	y = y - 34
	local function Tick(key, text)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("TOPLEFT", 4, y)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", box, "RIGHT", 2, 0)
		label:SetText(text)
		box:SetScript("OnClick", function(self) M.Set(key, self:GetChecked()) end)
		ticks[key] = box
		y = y - 24
	end
	Tick("on", "Show MP5 (off: nothing of this tool runs)")
	y = y - 6
	lookButton = DT:Dropdown(panel, 220, {
		entries = function()
			local out = {}
			for i, l in ipairs(LOOKS) do out[i] = { value = l[1], text = l[2] } end
			return out
		end,
		picked = function() return M.db.look end,
		pick = M.SetLook,
	})
	lookButton:SetPoint("TOPLEFT", 8, y)
	M.lookButton = lookButton
	y = y - 28
	Tick("locked", "Locked (unticked: it stays on screen to be placed; drag it, pull its corner, or turn the mouse wheel over it)")
	Tick("seconds", "Show the seconds (beside the bar, inside the clock)")
	y = y - 6
	local sizeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sizeLabel:SetPoint("TOPLEFT", 8, y - 4)
	sizeLabel:SetText("Size")
	local function Button(text, x, width, click)
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(width, 20)
		b:SetPoint("TOPLEFT", x, y)
		b:SetText(text)
		b:SetScript("OnClick", click)
		return b
	end
	M.smaller = Button("-", 44, 22, function() M.Resize(-1) end)
	sizeText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sizeText:SetPoint("TOPLEFT", 70, y - 4)
	sizeText:SetWidth(64)
	sizeText:SetJustifyH("CENTER")
	M.bigger = Button("+", 138, 22, function() M.Resize(1) end)
	M.reset = Button("Reset place and size", 176, 150, M.Reset)
	M.test = Button("Test", 334, 60, function() M.Start() end)
	M.sizeText = sizeText
	y = y - 32
	note = Line("GameFontHighlightSmall", "")
	M.note = note
	y = y - 30
	Line("GameFontHighlightSmall", "|cff888888Why only this: on Forever mana comes back evenly (there are no two-second ticks to time), and the game "
		.. "hides your mana from addons in combat. So the five seconds are counted from your own casts; nothing is measured. "
		.. "\"Test\" runs it once (it must be switched on).|r")
	M.ticks = ticks
end

DT:RegisterModule("mp5", {
	kind = "tool", -- (Settings > Tabs & Modules lists it under Tools)
	profile = { "look", "pos", "size" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "MP5",
	version = 1,
	defaults = { on = false, locked = true, seconds = true },
	onEnable = function(mod)
		M.db = mod.db
		local db = M.db
		db.look, db.pos, db.size = db.look or "spark", db.pos or {}, db.size or {}
		MakeFrames()
		DT:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spell)
			if unit == "player" and CostsMana(spell) and Mine(spell) and not channelling then
				-- (kept, to be read on the sub-tab: should the count run when it ought not, this says what set it off)
				local name
				pcall(function() name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)) or (GetSpellInfo and GetSpellInfo(spell)) end)
				M.last = ("%s (%s)"):format(type(name) == "string" and name or "spell", tostring(spell))
				M.Start()
				if M.Refresh then M.Refresh() end
			end
		end)
		-- a channelled mana spell: the count waits, full, until it ends
		DT:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spell)
			if unit ~= "player" or not CostsMana(spell) or not Active() then return end
			channelling, held = true, true
			driver:Show()
		end)
		DT:On("UNIT_SPELLCAST_CHANNEL_STOP", function(unit)
			if unit ~= "player" or not channelling then return end
			channelling, held = false, false
			M.Start()
		end)
		-- (a channel whose end was never told, through a loading screen or a death, is not held for ever)
		for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD" }) do
			DT:On(event, function()
				channelling, held = false, false
				M.Apply()
			end)
		end
		DT:RegisterTool({ id = "mp5", title = "MP5", order = 20, create = Build, onShow = Changed,
			active = function() return M.db.settings.on end })
		if not SLASH_DAWNTOOLS_MP51 then
			SlashCmdList.DAWNTOOLS_MP5 = function() DT.Tools.Open("mp5") end
			SLASH_DAWNTOOLS_MP51 = "/dtmp5"
		end
		M.Apply()
	end,
	selfTest = function(_, Try)
		Try("mp5 indicator", M.Apply)
		Try("mp5 cost", function() CostsMana(133) end)
	end,
})
