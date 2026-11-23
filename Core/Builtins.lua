-- DawnTools :: Built-ins
-- A page of the Settings tab with switches of the game's own that are hard to find in its menus. Each is one or
-- more of the game's settings (CVars): the game keeps them, nothing is saved here, and a box shows what the
-- game is set to now. A setting this client does not have greys its box.
-- ponytail: CVars only. "Raid-style party frames" is not here: on this client it is an Edit Mode setting (click
-- the party frames in Edit Mode), kept in the layout, not a CVar. It would mean rewriting the player's layout.

local _, DT = ...
local B = {}
DT.Builtins = B

-- cvars: { name, value when on, value when off }; on = every one of them the client has is at its "on" value
-- after: run when it was switched (out of combat)
B.LIST = {
	{ id = "autoLoot", label = "Auto loot", cvars = { { "autoLootDefault", "1", "0" } } },
	{ id = "cooldownNumbers", label = "Show numbers for cooldowns", cvars = { { "countdownForCooldowns", "1", "0" } } },
	{ id = "actionBars", label = "All action bars shown (bars 2 to 8)", cvars = { { "enableMultiActionBars", "127", "0" } },
		tip = "Per character. If the bars do not appear at once: /reload.",
		after = function() if MultiActionBar_Update then pcall(MultiActionBar_Update) end end },
	-- (ticked = the voice is off: the box is the wish, "silence it", so its "on" value is the setting's 0)
	{ id = "errorSpeech", label = "Silence error speech: my character saying \"That ability isn't ready yet\", \"Not enough mana\"",
		cvars = { { "Sound_EnableErrorSpeech", "0", "1" } }, tip = "The red text in the middle of the screen stays; only the voice goes." },
	{ id = "statusText", label = "Status text on health and mana bars: both the number and the percent",
		cvars = { { "statusText", "1", "0" }, { "statusTextDisplay", "BOTH", "NONE" } } },
	{ id = "targetOfTarget", label = "Target of target", cvars = { { "showTargetOfTarget", "1", "0" } } },
	{ id = "raidPower", label = "Raid frames: show power bars (mana, rage, energy)", cvars = { { "raidFramesDisplayPowerBars", "1", "0" } }, tip = "Per character." },
	{ id = "raidClass", label = "Raid frames: class colours", cvars = { { "raidFramesDisplayClassColor", "1", "0" } }, tip = "Per character." },
	{ id = "combatText", label = "Scrolling combat text: on me, and my damage on enemies",
		cvars = { { "enableFloatingCombatText", "1", "0" }, { "floatingCombatTextCombatDamage", "1", "0" } } },
}

local function Get(cvar)
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local ok, value = pcall(function() return get(cvar) end)
	return ok and value ~= nil and tostring(value) or nil -- nil: this client has no such setting
end

function B.Entry(id)
	for _, entry in ipairs(B.LIST) do
		if entry.id == id then return entry end
	end
end

-- has the client any of its settings?
function B.Has(entry)
	for _, c in ipairs(entry.cvars) do
		if Get(c[1]) then return true end
	end
	return false
end

function B.On(entry)
	local any = false
	for _, c in ipairs(entry.cvars) do
		local value = Get(c[1])
		if value then
			any = true
			if value:upper() ~= c[2] then return false end
		end
	end
	return any
end

function B.Set(entry, on)
	-- (the game changes some of these in a fight only with a complaint: asked for again afterwards)
	if InCombatLockdown and InCombatLockdown() then
		DT:Print("Not in combat: switch \"%s\" again after the fight.", entry.label)
		return false
	end
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	for _, c in ipairs(entry.cvars) do
		if set and Get(c[1]) then pcall(set, c[1], on and c[2] or c[3]) end
	end
	if entry.after then entry.after(on) end
	return true
end

local boxes = {}
B.boxes = boxes

DT.UI:Section("builtins", "Built-ins", 40, function(panel, kit)
	local y = -2
	kit.Text(panel, "GameFontNormal", 4, y, "Built-ins")
	local note = kit.Text(panel, "GameFontDisableSmall", 4, y - 20, "The game's own settings, gathered here because they are hard to find in its menus. They are the game's: they stay as set without DawnTools.")
	note:SetWidth(560)
	note:SetWordWrap(true)
	y = y - 50
	for _, entry in ipairs(B.LIST) do
		local box = kit.Toggle(panel, 4, y, entry.label,
			function(self)
				local has = B.Has(entry)
				self:SetEnabled(has)
				self.label:SetText((has and "" or "|cff888888") .. entry.label .. (has and "" or "  (not a setting of this client)|r"))
				return has and B.On(entry)
			end,
			function(on) B.Set(entry, on) end)
		if entry.tip then
			box:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(entry.tip, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			box:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		boxes[entry.id] = box
		y = y - 22
	end
end)
