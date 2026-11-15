-- DawnTools :: Silencer
-- Tick boxes that quiet noises of the game. Each is one of the game's own settings (a CVar), so the game keeps
-- it by itself: nothing is saved here, and a box shows what the game is set to now. All are unticked on a
-- client nobody has changed.
-- ponytail: one setting per box, and only what the game can switch off by itself. A noise with no setting of
-- its own (one sound file among many) would need MuteSoundFile and a saved list: add when one is asked for.

local _, DT = ...
local S = {}
DT.Silencer = S

-- cvar: the game's setting; quiet: its value while the noise is off; loud: its value otherwise
S.LIST = {
	{ id = "errorSpeech", cvar = "Sound_EnableErrorSpeech", quiet = "0", loud = "1",
		label = "Error speech: my character saying \"That ability isn't ready yet\", \"Not enough mana\", \"Out of range\"",
		tip = "The red text in the middle of the screen stays; only the voice goes." },
}

local function Get(cvar)
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local ok, value = pcall(function() return get(cvar) end)
	return ok and value ~= nil and tostring(value) or nil -- nil: this client has no such setting
end

function S.Quiet(entry)
	return Get(entry.cvar) == entry.quiet
end

function S.Set(entry, quiet)
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if set and Get(entry.cvar) then pcall(set, entry.cvar, quiet and entry.quiet or entry.loud) end
	DT.Tools.Show() -- (the sub-tab's colour, and through it the boxes)
end

local boxes = {}
S.boxes = boxes

function S.Refresh()
	for i, entry in ipairs(S.LIST) do
		local box = boxes[i]
		if box then
			local has = Get(entry.cvar) ~= nil
			box:SetChecked(has and S.Quiet(entry))
			box:SetEnabled(has)
			box.label:SetText((has and "" or "|cff888888") .. entry.label .. (has and "" or "  (this server has no such setting)|r"))
		end
	end
end

local function Build(panel)
	local head = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	head:SetPoint("TOPLEFT", 6, -6)
	head:SetText("Silencer")
	local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 6, -26)
	note:SetText("Tick a noise to switch it off. These are the game's own sound settings: they stay as set without DawnTools.")
	for i, entry in ipairs(S.LIST) do
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("TOPLEFT", 4, -24 - i * 24)
		box.label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
		box:SetScript("OnClick", function(self) S.Set(entry, self:GetChecked() and true or false) end)
		box:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(entry.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		box:SetScript("OnLeave", function() GameTooltip:Hide() end)
		boxes[i] = box
	end
end

DT:RegisterModule("silencer", {
	title = "Silencer",
	version = 1,
	onEnable = function()
		DT:RegisterTool({ id = "silencer", title = "Silencer", order = 40, create = Build, onShow = S.Refresh,
			active = function()
				for _, entry in ipairs(S.LIST) do
					if S.Quiet(entry) then return true end
				end
				return false
			end })
		if not SLASH_DAWNTOOLS_SILENCER1 then
			SlashCmdList.DAWNTOOLS_SILENCER = function() DT.Tools.Open("silencer") end
			SLASH_DAWNTOOLS_SILENCER1 = "/dtsilencer"
		end
	end,
	selfTest = function(_, Try)
		Try("silencer boxes", S.Refresh) -- (a client without a setting greys its box: not a failure)
	end,
})
