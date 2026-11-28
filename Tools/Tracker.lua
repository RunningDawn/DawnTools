-- DawnTracker
-- A small button on screen that holds a name. A click does what "/tar <name>" does and, if that found
-- something, marks it for the group (a ping, or a raid icon). For hunting a rare, or keeping an eye on one mob.
-- Local only. Its options are the Tracker sub-tab of the Tools tab.
--
-- Targeting is a protected action: only a secure button may do it, and only through a macro. So the whole
-- click is one macro:
--     /cleartarget
--     /tar <name>
--     /ping [@target,exists,nodead]     (only when the /tar found something, and it is alive)
--     /targetlasttarget [noexists]      (it found nothing: the target I had is put back)
--     /startattack [combat,harm,nodead] (in a fight: my attack, which clearing the target stopped, goes on)
-- The last two lines are is only there when I had a target as the click began. Without one, "last target" is some
-- old one (often myself), and a miss would bring that up from nowhere. A macro cannot remember whether there
-- was a target, so the button looks, in the game's own restricted code that runs before a secure click
-- (SecureHandlerWrapScript), and takes the macro with the line or the one without.
-- The target is cleared first on every click, so a dead one I still have targeted does not stand in the way:
-- /tar looks afresh and takes a living one of that name where there is one (the game prefers the living).
-- A macro cannot compare names, and addon code can neither target nor (in combat) read names; this gets
-- "ping it if it is what I asked for, and leave my target alone otherwise" without either.
-- The game also forbids changing a secure button in combat: a new name, size or place waits for its end.
-- ponytail: one name. A list of trackers if one is not enough.

local _, DT = ...
local K = {}
DT.Tracker = K

-- db.settings: on (off until asked for), tips (the tooltip on hovering the button)
-- db.name: what to target; db.mark: "ping" | "icon" | "none"; db.grow: "LEFT" | "CENTER" | "RIGHT" (the side
-- that stays put while the button is as wide as its text); db.pos = { x, y } of that point on the screen

local MIN_W, PAD, HEIGHT, MAX_NAME = 90, 22, 22, 60
local MARKS = { { "ping", "Ping it" }, { "icon", "Raid icon (skull)" }, { "none", "Just target it" } }
local GROWS = { { "LEFT", "Left (grows to the right)" }, { "CENTER", "Centre (grows both ways)" }, { "RIGHT", "Right (grows to the left)" } }

local button, pending

function K.Clean(name)
	-- (one line; and none of ; [ ], which a macro reads as its own signs)
	name = tostring(name or ""):gsub("[\r\n]", " "):gsub("[;%[%]]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	name = name:sub(1, MAX_NAME)
	-- (cut in the middle of a letter of several bytes: that half letter goes too)
	name = name:gsub("[\192-\255][\128-\191]*$", function(tail)
		local lead = tail:byte(1)
		local need = lead >= 240 and 4 or lead >= 224 and 3 or 2
		return #tail < need and "" or tail
	end)
	return name
end

-- the macro a click runs; "" while there is no name. keep: I have a target now, to be put back on a miss
function K.Macro(name, mark, keep)
	name = K.Clean(name)
	if name == "" then return "" end
	local lines = { "/cleartarget", "/tar " .. name }
	-- (a corpse is not marked: nobody needs calling to a dead mob. It stays targeted, which says it is dead.)
	if mark == "ping" then
		lines[#lines + 1] = (SLASH_PING1 or "/ping") .. " [@target,exists,nodead]"
	elseif mark == "icon" then
		lines[#lines + 1] = "/tm [@target,exists,nodead] 8"
	end
	if keep then
		lines[#lines + 1] = "/targetlasttarget [noexists]"
		-- Clearing the target stops my attack; in a fight it is taken up again on whatever I now have
		-- targeted (the old target put back, or the one found), so a click does not end my fighting.
		lines[#lines + 1] = "/startattack [combat,harm,nodead]"
	end
	return table.concat(lines, "\n")
end

local function Busy()
	return InCombatLockdown and InCombatLockdown() or false
end

-- Everything as the settings now are. In combat nothing of a secure button may be touched: it is done when
-- the fight is over.
function K.Apply()
	if not button then return end
	if Busy() then
		pending = true
		return
	end
	pending = false
	local db = K.db
	local name = K.Clean(db.name)
	button.label:SetText(name ~= "" and ("|cffffd100" .. name .. "|r") or "|cff888888Right-click: set a name|r")
	-- both macros are laid ready; which one a click runs is picked as it comes (see MakeButton)
	button:SetAttribute("dt-keep", K.Macro(name, db.mark, true))
	button:SetAttribute("dt-plain", K.Macro(name, db.mark, false))
	button:SetAttribute("macrotext1", K.Macro(name, db.mark, false))
	local width = math.max(MIN_W, math.floor((button.label:GetStringWidth() or 0) + PAD + 0.5))
	button:SetSize(width, HEIGHT)
	button.width = width
	-- hung by the side that is to stay put: the button then grows away from it by itself
	button:ClearAllPoints()
	if db.pos then
		button:SetPoint(db.grow, UIParent, "BOTTOMLEFT", db.pos[1], db.pos[2])
	else
		button:SetPoint(db.grow, UIParent, "CENTER", 0, -200)
	end
	button.hung = db.grow
	button:SetShown(db.settings.on and true or false)
	K.KeepMacro()
end

-- where the point the button hangs by is on the screen now (nil before it was ever drawn)
local function Anchor(grow)
	local left, right = button:GetLeft(), button:GetRight()
	local _, y = button:GetCenter()
	if not (left and right and y) then return nil end
	return { grow == "LEFT" and left or grow == "RIGHT" and right or (left + right) / 2, y }
end

local function Changed()
	K.Apply()
	if K.Refresh then K.Refresh() end
end

function K.SetName(name)
	K.db.name = K.Clean(name)
	if Busy() then DT:Print("Tracker: \"%s\" is taken up when the fight is over (the game allows no change in combat).", K.db.name) end
	Changed()
end

function K.SetMark(mark)
	K.db.mark = mark
	Changed()
end

-- the side it grows from: it stays where it is on the screen, only what holds it changes
function K.SetGrow(grow)
	if button and not Busy() and K.db.pos then K.db.pos = Anchor(grow) or K.db.pos end
	K.db.grow = grow
	Changed()
end

function K.Set(key, on)
	K.db.settings[key] = on and true or false
	Changed()
	if key == "on" then DT.Tools.Show() end -- (its sub-tab changes colour)
end

function K.Reset()
	K.db.pos = nil
	Changed()
end

-- A macro of the player's own, for an action bar or a key. It holds the commands themselves (the name and
-- all), and is rewritten whenever the name or the mark changes; in combat the game allows no rewriting, so
-- that waits for the fight's end like the button does. (A macro that clicked the button, "/click ...", did
-- not work on Forever.) It works with the tracker's window hidden too.
-- ponytail: a macro cannot look whether I have a target, so it always has the "put my target back" lines:
-- on a miss with no target, an old last target may come up. The button itself does not have this.
local MACRO = "DT Tracker"
local function Body()
	local body = K.Macro(K.db.name, K.db.mark, true)
	return body ~= "" and body or "/dttracker" -- (no name yet: it opens the tracker's settings)
end
local MACRO_ICON = "Ability_Hunter_Pet_Wolf" -- (a beast: what one is mostly after)
-- the macro is there (made if it was not, put right if it was changed); its place in the list, or nil and why not
local function Ensure()
	if Busy() then return nil, "Tracker: macros cannot be made in combat." end
	if not (CreateMacro and GetMacroIndexByName) then return nil, "Tracker: this game version has no macros to make." end
	local index = GetMacroIndexByName(MACRO)
	if not index or index == 0 then
		local ok, made = pcall(CreateMacro, MACRO, MACRO_ICON, Body())
		if not ok or not made then return nil, "Tracker: the macro could not be made (is your macro list full?)." end
		index = made
	elseif EditMacro then
		-- (put right where it is not what it should be; one that is, is left as it is)
		local body = GetMacroBody and GetMacroBody(index)
		if body ~= Body() then pcall(EditMacro, index, MACRO, MACRO_ICON, Body()) end
	end
	return index
end

-- With the tracker switched on, the macro is simply there in the macro list (/macro, the general ones), as
-- other addons' are: made a moment after login or when the tracker is switched on, and kept as the name is.
function K.KeepMacro()
	-- (not in the first moments after login: the macro list is not loaded then, and the macro would be made twice)
	if not K.loaded or not K.db.settings.on then return end
	Ensure()
end

function K.MakeMacro()
	local index, why = Ensure()
	if not index then return DT:Print(why) end
	if PickupMacro then pcall(PickupMacro, index) end
	DT:Print("Tracker: the macro \"%s\" is on your cursor: drop it on an action bar, and give that button a key. It is in /macro too.", MACRO)
	return index
end

local function EditBox(popup)
	return popup and (popup.editBox or popup.EditBox or (popup.GetEditBox and popup:GetEditBox()))
end

local function MakeButton()
	button = CreateFrame("Button", "DawnToolsTrackerButton", UIParent, "SecureActionButtonTemplate")
	button:SetFrameStrata("MEDIUM")
	button:SetClampedToScreen(true)
	button:SetMovable(true)
	-- (both: which of the two the game acts on is the player's own setting)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:RegisterForDrag("LeftButton")
	button:SetAttribute("type1", "macro")
	button:SetAttribute("shift-type1", "") -- (shift is for dragging: a shift-click does nothing)
	-- Before each click, in the game's restricted code: have I a target? Then the macro that puts it back on
	-- a miss, else the plain one. (Where this cannot be set up, the plain one: a miss leaves no target.)
	if SecureHandlerWrapScript then
		local ok = pcall(function()
			local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
			SecureHandlerWrapScript(button, "OnClick", header, [[
				local which = SecureCmdOptionParse("[@target,exists] dt-keep; dt-plain")
				self:SetAttribute("macrotext1", self:GetAttribute(which) or "")
			]])
		end)
		K.wrapped = ok
	end
	local edge = button:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.78, 0.68, 0.37, 0.9)
	local back = button:CreateTexture(nil, "BORDER")
	back:SetPoint("TOPLEFT", 1, -1)
	back:SetPoint("BOTTOMRIGHT", -1, 1)
	back:SetColorTexture(0.06, 0.06, 0.07, 0.92)
	local glow = button:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 1, 1, 0.1)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.label:SetPoint("CENTER")
	-- the right button asks for the name (once: on the way up)
	button:SetScript("PostClick", function(_, which, down)
		if which == "RightButton" and not down then StaticPopup_Show("DAWNTOOLS_TRACKER") end
	end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		if IsShiftKeyDown and IsShiftKeyDown() and not Busy() then
			self:StartMoving()
			self.moving = true
		end
	end)
	button:SetScript("OnDragStop", function(self)
		if not self.moving then return end
		self.moving = false
		self:StopMovingOrSizing()
		K.db.pos = Anchor(K.db.grow) or K.db.pos
		K.Apply()
	end)
	button:SetScript("OnEnter", function(self)
		self.over = true
		if not K.db.settings.tips then return end
		if IsShiftKeyDown and IsShiftKeyDown() then return end -- (about to be dragged: the tooltip would be in the way)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Tracker")
		GameTooltip:AddLine("Left-click: target it, and mark it if it is there.", 1, 1, 1)
		GameTooltip:AddLine("Right-click: change the name.", 1, 1, 1)
		GameTooltip:AddLine("Shift-drag: move.", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self.over = false
		GameTooltip:Hide()
	end)
	-- Shift pressed while the mouse is over it: the tooltip goes, to be out of the way of the drag
	DT:On("MODIFIER_STATE_CHANGED", function(key, down)
		if button.over and down == 1 and type(key) == "string" and key:find("SHIFT", 1, true) then GameTooltip:Hide() end
	end)
	button:Hide()
	K.button = button

	StaticPopupDialogs.DAWNTOOLS_TRACKER = {
		text = "Track what?\n(a name, or the start of one, as after /tar)",
		button1 = OKAY or "Okay", button2 = CANCEL or "Cancel",
		hasEditBox = true, maxLetters = MAX_NAME,
		OnShow = function(self)
			local box = EditBox(self)
			if box then
				box:SetText(K.db.name or "")
				if box.HighlightText then box:HighlightText() end
			end
		end,
		OnAccept = function(self)
			local box = EditBox(self)
			if box then K.SetName(box:GetText()) end
		end,
		EditBoxOnEnterPressed = function(box)
			K.SetName(box:GetText())
			local popup = box:GetParent()
			if popup and popup.Hide then popup:Hide() end
		end,
		EditBoxOnEscapePressed = function(box)
			local popup = box:GetParent()
			if popup and popup.Hide then popup:Hide() end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
end

---------------------------------------------------------------------------
-- The Tracker sub-tab
---------------------------------------------------------------------------

local onBox, tipBox, nameBox, markButton, growButton, note

function K.Refresh()
	if not onBox then return end
	onBox:SetChecked(K.db.settings.on and true or false)
	tipBox:SetChecked(K.db.settings.tips and true or false)
	if not nameBox:HasFocus() then nameBox:SetText(K.db.name or "") end
	for _, m in ipairs(MARKS) do
		if m[1] == K.db.mark then markButton.label:SetText("When found: " .. m[2]) end
	end
	for _, g in ipairs(GROWS) do
		if g[1] == K.db.grow then growButton.label:SetText("Grow from: " .. g[2]) end
	end
	note:SetText((pending and "|cffffd100Waiting for the fight to end to take up the change.|r\n" or "")
		.. ((K.db.mark == "ping" and not SLASH_PING1) and "|cffffd100This game version seems to have no ping command: if nothing is pinged, pick the raid icon.|r" or ""))
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
	Line("GameFontNormal", "Tracker")
	y = y - 20
	Line("GameFontHighlightSmall", "A small button that holds a name. Left-click it: it targets that name as /tar would and, if it was there, "
		.. "marks it for your group. If it was not there, your target stays what it was.\n"
		.. "Right-click the button to change the name; hold Shift and drag to move it.")
	y = y - 48
	onBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	onBox:SetSize(22, 22)
	onBox:SetPoint("TOPLEFT", 4, y)
	local onLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	onLabel:SetPoint("LEFT", onBox, "RIGHT", 2, 0)
	onLabel:SetText("Show the tracker")
	onBox:SetScript("OnClick", function(self) K.Set("on", self:GetChecked()) end)
	y = y - 24
	tipBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	tipBox:SetSize(22, 22)
	tipBox:SetPoint("TOPLEFT", 4, y)
	local tipLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tipLabel:SetPoint("LEFT", tipBox, "RIGHT", 2, 0)
	tipLabel:SetText("Show the tooltip when hovering the tracker (what the clicks do)")
	tipBox:SetScript("OnClick", function(self) K.Set("tips", self:GetChecked()) end)
	K.tipBox = tipBox
	y = y - 30
	local nameLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameLabel:SetPoint("TOPLEFT", 8, y - 4)
	nameLabel:SetText("Name")
	nameBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	nameBox:SetSize(220, 20)
	nameBox:SetPoint("TOPLEFT", 52, y)
	nameBox:SetAutoFocus(false)
	nameBox:SetScript("OnEnterPressed", function(self)
		K.SetName(self:GetText())
		self:ClearFocus()
	end)
	nameBox:SetScript("OnEscapePressed", function(self)
		self:SetText(K.db.name or "")
		self:ClearFocus()
	end)
	local nameHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	nameHint:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
	nameHint:SetText("Enter to take it up. The start of a name is enough.")
	y = y - 30
	local function Pick(list, current, pick, width)
		local b = DT:Dropdown(panel, width, {
			entries = function()
				local out = {}
				for i, e in ipairs(list) do out[i] = { value = e[1], text = e[2] } end
				return out
			end,
			picked = current, pick = pick,
		})
		b:SetPoint("TOPLEFT", 8, y)
		y = y - 26
		return b
	end
	markButton = Pick(MARKS, function() return K.db.mark end, K.SetMark, 230)
	growButton = Pick(GROWS, function() return K.db.grow end, K.SetGrow, 260)
	y = y - 4
	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(130, 20)
	reset:SetPoint("TOPLEFT", 8, y)
	reset:SetText("Reset position")
	reset:SetScript("OnClick", K.Reset)
	local macro = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	macro:SetSize(190, 20)
	macro:SetPoint("LEFT", reset, "RIGHT", 10, 0)
	macro:SetText("Pick up the hotkey macro")
	macro:SetScript("OnClick", K.MakeMacro)
	macro:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("A macro that does what a click on the tracker does")
		GameTooltip:AddLine("The macro \"" .. MACRO .. "\" is in your macro list (/macro, general) while the tracker is switched on. This puts it on "
			.. "your cursor: drop it on an action bar and bind a key to that button. It targets the name the tracker holds (a name changed in a fight is taken up after it).", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	macro:SetScript("OnLeave", function() GameTooltip:Hide() end)
	K.macroButton = macro
	y = y - 30
	note = Line("GameFontHighlightSmall", "")
	y = y - 34
	Line("GameFontHighlightSmall", "|cff888888The game lets no addon change a targeting button during a fight: a new name, mark or place set in "
		.. "combat is taken up when it ends. Clicking the tracker works in combat.|r")
	K.onBox, K.nameBox, K.markButton, K.growButton, K.reset, K.note = onBox, nameBox, markButton, growButton, reset, note
end

DT:RegisterModule("tracker", {
	kind = "tool", -- (Settings > Tabs & Modules lists it under Tools)
	profile = { "name", "mark", "grow", "pos" }, -- (what of its saved table is how it is set up: goes with a profile)
	title = "Tracker",
	version = 1,
	defaults = { on = false, tips = true },
	onEnable = function(mod)
		K.db = mod.db
		local db = K.db
		db.name, db.mark, db.grow = db.name or "", db.mark or "ping", db.grow or "CENTER"
		MakeButton()
		DT:On("PLAYER_REGEN_ENABLED", function()
			if pending then Changed() end
		end)
		DT:On("PLAYER_ENTERING_WORLD", K.Apply)
		C_Timer.After(4, function()
			K.loaded = true
			K.KeepMacro()
		end)
		DT:RegisterTool({ id = "tracker", title = "Tracker", order = 30, create = Build, onShow = K.Refresh,
			active = function() return K.db.settings.on end })
		if not SLASH_DAWNTOOLS_TRACKER1 then
			SlashCmdList.DAWNTOOLS_TRACKER = function() DT.Tools.Open("tracker") end
			SLASH_DAWNTOOLS_TRACKER1 = "/dttracker"
		end
		K.Apply()
	end,
	selfTest = function(_, Try)
		Try("tracker button", K.Apply)
		Try("tracker macro", function() assert(K.Macro("Rex", "ping"):find("/tar Rex", 1, true)) end)
	end,
})
