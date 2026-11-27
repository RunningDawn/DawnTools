-- DawnTools :: Chat Saver
-- The chat set up once, kept by name, and put back on any character: every chat window (its name, font size,
-- colour, how see-through, shown, locked, docked where or placed where and how big), what each shows (the kinds
-- of message and the channels), the channels joined, and the colour of every kind of message. One layout may be
-- ticked to be put back at every login and /reload: a new character gets it by itself.
-- Local only: nothing is sent. Written from the game's own chat functions (FCF_*, ChatFrame_*), not from another
-- addon's code.
-- ponytail: the channels are joined by name, not put back in their numbers' order; a window that is closed now and
-- shown in the layout is opened at its own number, which the game may draw at the end of the tabs.

local _, DT = ...
local C = {}
DT.ChatSaver = C

-- db.layouts[name] = { at, by, windows = { [i] = { name, size, color = { r, g, b, a }, shown, locked, docked (place),
-- unint, groups = { ... }, chans = { ... }, pos = { point, relative, x, y }, w, h } }, colors = { [chat type] = { r, g, b } },
-- channels = { names } }; db.auto = the name of the one to put back at login, or nil

local function Windows() return NUM_CHAT_WINDOWS or 10 end
local function Frame(i) return _G["ChatFrame" .. i] end
local function Combat(f) return IsCombatLog and IsCombatLog(f) or false end

-- the chat as it is now, as a layout
function C.Capture()
	local L = { windows = {}, colors = {}, channels = {}, at = time and time() or 0, by = DT.Name and DT.Name(DT.me or "") or "" }
	for i = 1, Windows() do
		local f = Frame(i)
		local name, size, r, g, b, a, shown, locked, docked, unint
		if GetChatWindowInfo then name, size, r, g, b, a, shown, locked, docked, unint = GetChatWindowInfo(i) end -- (not X and X(i): that keeps the first value only)
		if f and name then
			local w = { name = name, size = size, color = { r, g, b, a }, shown = shown and true or false, locked = locked and true or false,
				docked = tonumber(docked), unint = unint and true or false, groups = {}, chans = {} }
			if GetChatWindowMessages then w.groups = { GetChatWindowMessages(i) } end
			local list = GetChatWindowChannels and { GetChatWindowChannels(i) } or {}
			for k = 1, #list, 2 do w.chans[#w.chans + 1] = list[k] end
			-- (where it stands: the first window always, any other that is not docked)
			if (i == 1 or not w.docked) and f.GetPoint then
				local point, _, relative, x, y = f:GetPoint(1)
				w.pos, w.w, w.h = { point, relative, x, y }, f:GetWidth(), f:GetHeight()
			end
			L.windows[i] = w
		end
	end
	for chatType, c in pairs(ChatTypeInfo or {}) do
		if type(c) == "table" and c.r then L.colors[chatType] = { c.r, c.g, c.b } end
	end
	local list = GetChannelList and { GetChannelList() } or {}
	for k = 1, #list, 3 do
		if type(list[k + 1]) == "string" then L.channels[#L.channels + 1] = list[k + 1] end
	end
	return L
end

local function Call(fn, ...) if fn then pcall(fn, ...) end end

-- The channels of a layout: those not joined are joined, and each window is made to show its own. Only what
-- differs is touched: a window that shows the right channels already is left alone (taking all off and adding
-- them again loses every channel the game has not joined yet, as at login: General, Trade and the rest).
function C.Channels(L)
	if type(L) ~= "table" or type(L.windows) ~= "table" then return end
	local joined = {}
	local list = GetChannelList and { GetChannelList() } or {}
	for k = 1, #list, 3 do if type(list[k + 1]) == "string" then joined[list[k + 1]:lower()] = true end end
	for _, name in ipairs(L.channels or {}) do
		if not joined[name:lower()] then Call(JoinPermanentChannel, name, nil, 1) end
	end
	for i = 1, Windows() do
		local f, w = Frame(i), L.windows[i]
		if f and w and not Combat(f) then
			local have, want = {}, {}
			local now = GetChatWindowChannels and { GetChatWindowChannels(i) } or {}
			for k = 1, #now, 2 do have[now[k]] = true end
			for _, chan in ipairs(w.chans or {}) do want[chan] = true end
			for chan in pairs(have) do if not want[chan] then Call(ChatFrame_RemoveChannel, f, chan) end end
			for _, chan in ipairs(w.chans or {}) do if not have[chan] then Call(ChatFrame_AddChannel, f, chan) end end
		end
	end
end

-- a layout put back. Says how many windows it set. later: without the channels (C.Channels, called apart)
function C.Apply(L, later)
	if type(L) ~= "table" or type(L.windows) ~= "table" then return 0 end
	if not later then C.Channels(L) end
	local n = 0
	for i = 1, Windows() do
		local f, w = Frame(i), L.windows[i]
		if f and w then
			n = n + 1
			Call(FCF_SetWindowName, f, w.name)
			if w.size then Call(FCF_SetChatWindowFontSize, nil, f, w.size) end
			if w.color and w.color[1] then
				Call(FCF_SetWindowColor, f, w.color[1], w.color[2], w.color[3])
				if w.color[4] then Call(FCF_SetWindowAlpha, f, w.color[4]) end
			end
			-- (the combat log keeps its own filters: what it shows is not message kinds)
			if not Combat(f) then
				Call(ChatFrame_RemoveAllMessageGroups, f)
				for _, group in ipairs(w.groups or {}) do Call(ChatFrame_AddMessageGroup, f, group) end
			end
			-- (docked comes first, as the game itself reads it: a docked tab that is not the one picked says
			-- "not shown", and is a tab all the same. Only a window neither docked nor shown is closed.)
			if w.docked and i > 1 then
				Call(FCF_DockFrame, f, w.docked)
			elseif i == 1 or w.shown then
				Call(SetChatWindowShown, i, true)
				if i > 1 then Call(FCF_UnDockFrame, f) end
				if w.pos and f.ClearAllPoints then
					f:ClearAllPoints()
					f:SetPoint(w.pos[1], UIParent, w.pos[2], w.pos[3], w.pos[4])
					if w.w and w.h then f:SetSize(w.w, w.h) end
					Call(FCF_SavePositionAndDimensions, f)
				end
				if f.Show then f:Show() end
			else
				Call(FCF_Close, f)
			end
			Call(FCF_SetLocked, f, w.locked)
			Call(FCF_SetUninteractable, f, w.unint)
		end
	end
	for chatType, c in pairs(L.colors or {}) do Call(ChangeChatColor, chatType, c[1], c[2], c[3]) end
	Call(FCF_DockUpdate)
	return n
end

function C.Save(name)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then name = C.picked or "" end -- (no name typed: saved over the one picked)
	if name == "" then return false end
	C.db.layouts[name] = C.Capture()
	C.picked = name
	DT:Print("Chat Saver: saved as \"%s\".", name)
	if C.Refresh then C.Refresh() end
	return true
end

function C.Load(name)
	local L = C.db.layouts[name or ""]
	if not L then return 0 end
	if InCombatLockdown and InCombatLockdown() then
		DT:Print("Chat Saver: not in a fight; try again after it.")
		return 0
	end
	local n = C.Apply(L)
	DT:Print("Chat Saver: \"%s\" put back (%d windows).", name, n)
	return n
end

function C.Delete(name)
	if not C.db.layouts[name or ""] then return end
	C.db.layouts[name] = nil
	if C.db.auto == name then C.db.auto = nil end
	if C.picked == name then C.picked = nil end
	if C.Refresh then C.Refresh() end
end

-- the one picked is put back at every login and /reload, or not
function C.SetAuto(on)
	C.db.auto = on and C.picked or nil
	if C.Refresh then C.Refresh() end
end

---------------------------------------------------------------------------
-- The Chat Saver sub-tab
---------------------------------------------------------------------------

local nameBox, pick, autoBox, info

local function Names()
	local out = {}
	for name in pairs(C.db.layouts) do out[#out + 1] = name end
	table.sort(out)
	return out
end

function C.Refresh()
	if not pick then return end
	if C.picked and not C.db.layouts[C.picked] then C.picked = nil end
	C.picked = C.picked or C.db.auto or Names()[1]
	pick.label:SetText(C.picked or "|cff888888no layout saved yet|r")
	autoBox:SetChecked(C.picked ~= nil and C.db.auto == C.picked)
	local L = C.picked and C.db.layouts[C.picked]
	local shown = 0
	for _, w in pairs(L and L.windows or {}) do if w.shown or w.docked then shown = shown + 1 end end
	info:SetText(L and ("|cff888888Saved %s by %s: %d windows shown, %d channels.%s|r"):format(date and date("%Y-%m-%d %H:%M", L.at) or "", L.by ~= "" and L.by or "?",
		shown, #(L.channels or {}), C.db.auto and ("  Put back at login: " .. C.db.auto .. ".") or "") or "")
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
	local function Button(text, x, width, click)
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(width, 20)
		b:SetPoint("TOPLEFT", x, y)
		b:SetText(text)
		b:SetScript("OnClick", click)
		return b
	end
	Line("GameFontNormal", "Chat Saver", 20)
	Line("GameFontHighlightSmall", "Your chat set up once, kept by name, and put back on any character: the windows and tabs, their sizes and places, "
		.. "what each shows, the channels and the colours.", 34)
	-- save the chat as it is now
	nameBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	nameBox:SetSize(180, 20)
	nameBox:SetPoint("TOPLEFT", 12, y)
	nameBox:SetAutoFocus(false)
	nameBox:SetScript("OnEnterPressed", function(self) if C.Save(self:GetText()) then self:SetText("") self:ClearFocus() end end)
	nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	C.nameBox = nameBox
	C.save = Button("Save the chat as it is now", 200, 190, function() if C.Save(nameBox:GetText()) then nameBox:SetText("") nameBox:ClearFocus() end end)
	y = y - 30
	-- the saved ones
	pick = DT:Dropdown(panel, 180, {
		entries = function()
			local out = {}
			for _, name in ipairs(Names()) do out[#out + 1] = { value = name, text = name .. (C.db.auto == name and "  |cff40ff40at login|r" or "") } end
			return out
		end,
		picked = function() return C.picked end,
		pick = function(v) C.picked = v C.Refresh() end,
	})
	pick:SetPoint("TOPLEFT", 8, y - 1)
	C.pick = pick
	C.load = Button("Load", 200, 70, function() C.Load(C.picked) end)
	C.delete = Button("Delete", 276, 70, function() C.Delete(C.picked) end)
	y = y - 28
	autoBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	autoBox:SetSize(22, 22)
	autoBox:SetPoint("TOPLEFT", 4, y)
	local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", autoBox, "RIGHT", 2, 0)
	label:SetText("Put this layout back at every login and /reload, on every character")
	autoBox:SetScript("OnClick", function(self) C.SetAuto(self:GetChecked()) end)
	C.autoBox = autoBox
	y = y - 26
	info = Line("GameFontHighlightSmall", "", 30)
	C.info = info
	Line("GameFontDisableSmall", "No name typed: Save writes over the layout picked below. Kept in the saved file of this computer, for all your characters. The combat log keeps its own filters.", 20)
	C.Refresh()
end

DT:RegisterModule("chatsaver", {
	title = "Chat Saver",
	version = 1,
	onEnable = function(mod)
		C.db = mod.db
		C.db.layouts = type(C.db.layouts) == "table" and C.db.layouts or {}
		DT:RegisterTool({ id = "chatsaver", title = "Chat Saver", order = 40, create = Build, onShow = C.Refresh,
			active = function() return C.db.auto ~= nil end })
		-- the layout ticked: put back a moment after the chat windows are made (the game sets them up itself first)
		DT:On("PLAYER_ENTERING_WORLD", function(login, reload)
			if not (login or reload) or not (C.db.auto and C.db.layouts[C.db.auto]) then return end
			local function Put() if not (InCombatLockdown and InCombatLockdown()) then C.Apply(C.db.layouts[C.db.auto], true) end end
			-- ponytail: the channels 10 seconds in, when the game has joined its own (General, Trade); a slower
			-- login leaves a channel new to this character unticked: Load puts it right
			local function Chans() if C.db.auto then C.Channels(C.db.layouts[C.db.auto]) end end
			if C_Timer and C_Timer.After then C_Timer.After(1, Put) C_Timer.After(10, Chans) else Put() Chans() end
		end)
	end,
	selfTest = function(_, Try)
		Try("chat saver", C.Capture)
	end,
})
