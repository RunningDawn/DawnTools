-- DawnTools :: Chat History
-- In the chat line, Up and Down walk through what was sent before, as in a shell.
-- The game has this already, half hidden: every chat edit box keeps the lines sent from it, but the arrows
-- reach it only with Alt held (plain arrows move the character), and it is forgotten at logout. So this builds
-- no history of its own. It
--   lets the plain arrow keys reach the chat line while it is open (the game's own switch, SetAltArrowKeyMode);
--   keeps the sent lines across sessions and hands them back to the game's history at login.
-- Local only: nothing is sent. The lines kept (chat only, no whispers or other commands) are in the saved file
-- of this computer, in plain text.
-- ponytail: one history for all chat windows, as lines only (not which channel each went to). While playing,
-- the game's own depth applies (about 32 lines); the last KEEP are kept for the next login.

local _, DT = ...
local H = {}
DT.ChatHistory = H

local KEEP = 50
local hooked, restoring = {}, false

-- the chat edit boxes there are now
local function Boxes()
	local out = {}
	for i = 1, tonumber(NUM_CHAT_WINDOWS) or 10 do
		local box = _G["ChatFrame" .. i .. "EditBox"]
		if type(box) == "table" then out[#out + 1] = box end
	end
	return out
end

-- Only chat is kept across sessions: plain text and the say/yell/guild/party/raid/emote/channel commands. Whispers
-- and every other slash command (/console, /run, a pasted password after /w...) stay in the game's history for
-- this session only.
-- ponytail: an allow-list of command names, not of content; plain text goes to whatever channel the window is on.
local CHAT = { s = 1, say = 1, y = 1, yell = 1, g = 1, guild = 1, o = 1, officer = 1, p = 1, party = 1, raid = 1,
	ra = 1, rw = 1, i = 1, instance = 1, bg = 1, battleground = 1, e = 1, em = 1, emote = 1 }
local function Keepable(text)
	if text:sub(1, 1) ~= "/" then return true end
	local cmd = (text:match("^/(%S+)") or ""):lower()
	return CHAT[cmd] or cmd:match("^%d+$") ~= nil
end

-- a line the game added to its history: kept for the next login (the same line twice running, once)
local function Record(text)
	local s = H.db.settings
	if restoring or not s.keep or type(text) ~= "string" or text == "" or not Keepable(text) then return end
	local lines = H.db.lines
	if lines[#lines] == text then return end
	lines[#lines + 1] = text
	while #lines > KEEP do table.remove(lines, 1) end
end

-- Every chat edit box is set as the switch says, and looked after: its history is listened to, and the lines
-- kept from before are handed to it once.
function H.Apply()
	if not H.db then return end
	local s = H.db.settings
	for _, box in ipairs(Boxes()) do
		-- (off: as the game has it, the arrows only with Alt)
		if box.SetAltArrowKeyMode then pcall(box.SetAltArrowKeyMode, box, not s.on) end
		if not hooked[box] and box.AddHistoryLine then
			hooked[box] = true
			if hooksecurefunc then pcall(hooksecurefunc, box, "AddHistoryLine", function(_, text) Record(text) end) end
			if s.keep then
				restoring = true
				for _, line in ipairs(H.db.lines) do pcall(box.AddHistoryLine, box, line) end
				restoring = false
			end
		end
	end
end

function H.Set(key, on)
	H.db.settings[key] = on and true or false
	H.Apply()
	if H.Refresh then H.Refresh() end
	if key == "on" then DT.Tools.Show() end -- (its sub-tab changes colour)
end

function H.Forget()
	for i = #H.db.lines, 1, -1 do H.db.lines[i] = nil end
	if H.Refresh then H.Refresh() end
end

---------------------------------------------------------------------------
-- The tool's page
---------------------------------------------------------------------------

local boxes, count = {}, nil
H.boxes = boxes

function H.Refresh()
	for key, box in pairs(boxes) do box:SetChecked(H.db.settings[key]) end
	if count then count:SetText(("%d line%s kept for the next login."):format(#H.db.lines, #H.db.lines == 1 and "" or "s")) end
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
		return fs
	end
	local function Box(key, text)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("TOPLEFT", 4, y)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", box, "RIGHT", 2, 0)
		label:SetText(text)
		box:SetScript("OnClick", function(self) H.Set(key, self:GetChecked()) end)
		boxes[key] = box
		y = y - 24
	end
	Line("GameFontNormal", "Chat History", 20)
	Line("GameFontHighlightSmall", "In the chat line, Up and Down bring back what you sent before, the last line first, as in a shell.", 20)
	Box("on", "Up and Down walk through what you sent (no Alt needed)")
	Box("keep", ("Remember it across sessions (the last %d lines)"):format(KEEP))
	y = y - 4
	count = Line("GameFontHighlightSmall", "", 18)
	H.forget = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	H.forget:SetSize(170, 20)
	H.forget:SetPoint("TOPLEFT", 6, y)
	H.forget:SetText("Forget everything kept")
	H.forget:SetScript("OnClick", H.Forget)
	y = y - 30
	Line("GameFontDisableSmall", "While the chat line is open the arrow keys belong to it: Left and Right move the cursor in the text, they do not turn "
		.. "your character. Without this tool the game does the same with Alt held. The lines kept (whispers and commands among them) are in "
		.. "the saved file of this computer, in plain text; \"Forget\" empties that, not what the game itself still holds until you log out.", 60)
end

DT:RegisterModule("chathistory", {
	kind = "tool", -- (Settings > Tabs & Modules lists it under Tools)
	title = "Chat History",
	version = 1,
	defaults = { on = false, keep = true },
	onEnable = function(mod)
		H.db = mod.db
		H.db.lines = type(H.db.lines) == "table" and H.db.lines or {}
		DT:RegisterTool({ id = "chathistory", title = "Chat History", order = 39, create = Build, onShow = H.Refresh,
			active = function() return H.db.settings.on end })
		-- (chat windows made later, and those the game sets up after login, are looked after too)
		for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_CHAT_WINDOWS" }) do
			DT:On(event, function() H.Apply() end)
		end
		if not SLASH_DAWNTOOLS_CHATHISTORY1 then
			SlashCmdList.DAWNTOOLS_CHATHISTORY = function() DT.Tools.Open("chathistory") end
			SLASH_DAWNTOOLS_CHATHISTORY1 = "/dtchat"
		end
		H.Apply()
	end,
	selfTest = function(_, Try)
		Try("chat history", H.Apply)
	end,
})
