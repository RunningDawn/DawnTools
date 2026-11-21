-- DawnTools :: FPS
-- The game's own frame rate (GetFramerate), as a small number on screen: placed where it suits, locked there,
-- made bigger or smaller. Local only. Its options are the FPS sub-tab of the Tools tab.

local _, DT = ...
local F = {}
DT.Fps = F

-- db.settings: on (off until asked for), locked; db.pos = { point, relative point, x, y }; db.size = the font size
local SIZE, MIN, MAX = 14, 8, 48
local EVERY = 0.5 -- (seconds between redraws: the game's own number is an average over about a second)

local f, ticks, sizeText

local function Size() return math.max(MIN, math.min(MAX, tonumber(F.db.size) or SIZE)) end

-- green at 50 and up, gold from 30, red below
local function Color(fps)
	if fps >= 50 then return 0.25, 0.9, 0.35 elseif fps >= 30 then return 1, 0.82, 0 end
	return 1, 0.3, 0.3
end

local function Draw()
	local fps = GetFramerate and GetFramerate() or 0
	f.text:SetText(("%d fps"):format(math.floor(fps + 0.5)))
	f.text:SetTextColor(Color(fps))
	f.fps = fps
end

-- everything as the settings now are: shown or not, where, how big, whether it can be moved
function F.Apply()
	local s, size = F.db.settings, Size()
	local unlocked = not s.locked
	f:ClearAllPoints()
	local pos = F.db.pos or { "TOP", "TOP", 0, -20 }
	f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	f:SetSize(size * 4.2, size * 1.5)
	f.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
	f.box:SetShown(unlocked)
	f.name:SetShown(unlocked)
	f.grip:SetShown(unlocked)
	f:EnableMouse(unlocked)
	f:EnableMouseWheel(unlocked)
	f:SetShown(s.on and true or false)
	if s.on then Draw() end
	if sizeText then sizeText:SetText(tostring(size)) end
	for key, box in pairs(ticks or {}) do box:SetChecked(s[key] and true or false) end
end

function F.Set(key, on)
	F.db.settings[key] = on and true or false
	F.Apply()
	if key == "on" then DT.Tools.Show() end -- (its sub-tab changes colour)
end

function F.Resize(by)
	F.db.size = math.max(MIN, math.min(MAX, Size() + by))
	F.Apply()
end

function F.Reset()
	F.db.pos, F.db.size = nil, nil
	F.Apply()
end

local function Keep()
	local point, _, relative, x, y = f:GetPoint(1)
	F.db.pos = { point, relative, x, y }
end

local function MakeFrame()
	f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(MIN * 4.2, MIN * 1.5, MAX * 4.2, MAX * 1.5) end
	f:RegisterForDrag("LeftButton")
	f.box = f:CreateTexture(nil, "BACKGROUND")
	f.box:SetAllPoints()
	f.box:SetColorTexture(0.2, 0.6, 1, 0.25)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.text:SetPoint("CENTER")
	f.text:SetShadowColor(0, 0, 0, 0.9)
	f.text:SetShadowOffset(1, -1)
	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.name:SetPoint("BOTTOM", f, "TOP", 0, 4)
	f.name:SetText("FPS (drag; corner or wheel: size)")
	f:SetScript("OnDragStart", function(self) if not F.db.settings.locked then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Keep()
	end)
	f:SetScript("OnMouseWheel", function(_, delta) F.Resize(delta) end)
	-- the corner to pull it bigger by: the font follows the height
	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(10, 10)
	f.grip:SetPoint("BOTTOMRIGHT", 4, -4)
	local corner = f.grip:CreateTexture(nil, "OVERLAY")
	corner:SetAllPoints()
	corner:SetColorTexture(1, 1, 1, 0.7)
	f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	f.grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		F.db.size = math.max(MIN, math.min(MAX, math.floor(f:GetHeight() / 1.5 + 0.5)))
		Keep()
		F.Apply()
	end)
	local idle = 0
	f:SetScript("OnUpdate", function(_, dt) -- (runs only while it is shown)
		idle = idle + (dt or 0)
		if idle < EVERY then return end
		idle = 0
		Draw()
	end)
	f:Hide()
	F.f = f
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
	Line("GameFontNormal", "FPS: frames a second")
	y = y - 20
	Line("GameFontHighlightSmall", "The game's own frame rate, as a small number on screen: green at 50 and up, gold from 30, red below.")
	y = y - 24
	ticks = {}
	local function Tick(key, text)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("TOPLEFT", 4, y)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", box, "RIGHT", 2, 0)
		label:SetText(text)
		box:SetScript("OnClick", function(self) F.Set(key, self:GetChecked()) end)
		ticks[key] = box
		y = y - 24
	end
	Tick("on", "Show FPS")
	Tick("locked", "Locked (unticked: drag it, pull its corner, or turn the mouse wheel over it)")
	y = y - 6
	local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", 8, y - 4)
	label:SetText("Size")
	local function Button(text, x, width, click)
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(width, 20)
		b:SetPoint("TOPLEFT", x, y)
		b:SetText(text)
		b:SetScript("OnClick", click)
		return b
	end
	F.smaller = Button("-", 44, 22, function() F.Resize(-1) end)
	sizeText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sizeText:SetPoint("TOPLEFT", 70, y - 4)
	sizeText:SetWidth(40)
	sizeText:SetJustifyH("CENTER")
	F.bigger = Button("+", 114, 22, function() F.Resize(1) end)
	F.reset = Button("Reset place and size", 152, 150, F.Reset)
	F.ticks = ticks
	F.Apply()
end

DT:RegisterModule("fps", {
	profile = { "pos", "size" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "FPS",
	version = 1,
	defaults = { on = false, locked = false },
	onEnable = function(mod)
		F.db = mod.db
		MakeFrame()
		DT:RegisterTool({ id = "fps", title = "FPS", order = 25, create = Build, onShow = F.Apply,
			active = function() return F.db.settings.on end })
		F.Apply()
	end,
	selfTest = function(_, Try)
		Try("fps display", F.Apply)
	end,
})
