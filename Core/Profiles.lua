-- DawnTools :: Profiles
-- A profile is how the addon is set up: every setting and preference, and nothing that was collected.
--   in a profile:  settings, which modules and tabs are on and in what order, the window's place and size,
--                  and per module its settings plus the preferences it names (mod.profile = { "key", ... }:
--                  positions, sizes, filters)
--   never in one:  prices, inventories, catches, recipes, the combat log, favourites
-- Every character uses "Default" until another profile is picked for it.
--
-- DawnToolsDB.profiles[name]  = a stored profile (see Snapshot)
-- DawnToolsDB.profileOf[who]  = the profile of a character ("Name-Realm"); none = "Default"
-- DawnToolsDB.profile         = the profile whose values the live tables hold right now
--
-- The modules know nothing of this: they read the same tables as ever. At login, before they start, a
-- character whose profile is not the one held live has the live values stored away and its own copied in
-- (P.Login). Switching in the window does the same and then reloads the interface, so every module starts
-- afresh on the new values.

local _, DT = ...
local P = {}
DT.Profiles = P

local DEFAULT = "Default"
local TOP = { "settings", "modules", "tabs", "pos", "size", "minimap", "lastTab", "settingsSection" }
local MAX_NAME, MAX_TEXT, MAX_NODES, MAX_DEPTH = 30, 200000, 20000, 8
local PREFIX = "DT1:"

local function Copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = Copy(x) end
	return out
end

function P.Who()
	return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
end

-- the live values of a saved-variables table, as a profile: { v = 1, top = { key = value }, mods = { [module] =
-- { settings = {...}, keys = { key = value } } } }
function P.Snapshot(db)
	local snap = { v = 1, top = {}, mods = {} }
	for _, key in ipairs(TOP) do snap.top[key] = Copy(db[key]) end
	for _, name in ipairs(DT.order) do
		local mdb = db[name]
		if type(mdb) == "table" then
			local m = { settings = Copy(mdb.settings) or {}, keys = {} }
			for _, key in ipairs(DT.modules[name].profile or {}) do m.keys[key] = Copy(mdb[key]) end
			snap.mods[name] = m
		end
	end
	return snap
end

-- a profile's values into the live tables. What the profile does not say goes back to nothing, which the
-- core and the modules then fill with their defaults (so this runs before they start, or before a reload).
function P.Apply(db, snap)
	for _, key in ipairs(TOP) do db[key] = Copy(snap.top and snap.top[key]) end
	for _, name in ipairs(DT.order) do
		db[name] = db[name] or {}
		local mdb, m = db[name], snap.mods and snap.mods[name] or {}
		mdb.settings = Copy(m.settings) or {}
		for _, key in ipairs(DT.modules[name].profile or {}) do mdb[key] = Copy(m.keys and m.keys[key]) end
	end
end

local function Tables(db)
	db.profiles, db.profileOf = db.profiles or {}, db.profileOf or {}
	db.profile = db.profile or DEFAULT
end

-- the live values are stored under the profile they belong to, and another profile's are copied in.
-- A profile that was never stored (a first use of "Default", say) starts as what is live now.
function P.Swap(db, to)
	Tables(db)
	if to == db.profile then return false end
	db.profiles[db.profile] = P.Snapshot(db)
	if db.profiles[to] then P.Apply(db, db.profiles[to]) end
	db.profile = to
	return true
end

-- at login, before anything else reads the tables
function P.Login(db)
	Tables(db)
	P.Swap(db, db.profileOf[P.Who()] or DEFAULT)
end

function P.Current()
	return DT.db.profile or DEFAULT
end

-- every profile there is, by name, "Default" first
function P.List()
	local db, seen, out = DT.db, {}, {}
	local function Add(name)
		if name and not seen[name] then seen[name], out[#out + 1] = true, name end
	end
	Add(DEFAULT)
	Add(db.profile)
	for name in pairs(db.profiles) do Add(name) end
	table.sort(out, function(a, b)
		if (a == DEFAULT) ~= (b == DEFAULT) then return a == DEFAULT end
		return a:lower() < b:lower()
	end)
	return out
end

local function Exists(name)
	for _, n in ipairs(P.List()) do
		if n:lower() == name:lower() then return true end
	end
	return false
end

-- a name fit for a profile, or nil and why not
function P.Name(name)
	name = tostring(name or ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return nil, "A profile needs a name." end
	if #name > MAX_NAME then return nil, ("A profile's name is %d letters at most."):format(MAX_NAME) end
	if Exists(name) then return nil, ("There is a profile \"%s\" already."):format(name) end
	return name
end

-- a new profile: a copy of what is set up now, or an empty one (everything at its default). Not switched to.
function P.New(name, empty)
	local ok, why = P.Name(name)
	if not ok then return nil, why end
	DT.db.profiles[ok] = empty and { v = 1, top = {}, mods = {} } or P.Snapshot(DT.db)
	return ok
end

function P.Rename(old, new)
	local db = DT.db
	if old == DEFAULT then return nil, "\"Default\" keeps its name." end
	local ok, why = P.Name(new)
	if not ok then return nil, why end
	db.profiles[ok], db.profiles[old] = db.profiles[old], nil
	if db.profile == old then db.profile = ok end
	for who, name in pairs(db.profileOf) do
		if name == old then db.profileOf[who] = ok end
	end
	return ok
end

function P.Delete(name)
	local db = DT.db
	if name == DEFAULT then return nil, "\"Default\" cannot be deleted." end
	if name == db.profile then return nil, "The profile in use cannot be deleted: switch to another first." end
	db.profiles[name] = nil
	for who, n in pairs(db.profileOf) do
		if n == name then db.profileOf[who] = nil end -- (those characters are on "Default" again)
	end
	return true
end

-- this character uses that profile from now on. The interface is reloaded: every module starts on its values.
function P.Use(name)
	local db = DT.db
	db.profileOf[P.Who()] = name ~= DEFAULT and name or nil
	if P.Swap(db, name) and ReloadUI then ReloadUI() end
end

-- the profile in use back to how everything is at first
function P.Reset()
	P.Apply(DT.db, { v = 1, top = {}, mods = {} })
	if ReloadUI then ReloadUI() end
end

---------------------------------------------------------------------------
-- Export and import: a profile as a piece of text
---------------------------------------------------------------------------
-- Written and read by a small writer and reader of our own: text, numbers, yes/no and tables, and nothing
-- else. Reading it runs no code, so a text from a stranger can at worst give odd settings.
--   table  {k v k v ...}     text  s<length>:<bytes>     number  n<number>;     yes / no  T / F

local function Write(v, out)
	local t = type(v)
	if t == "table" then
		out[#out + 1] = "{"
		for k, x in pairs(v) do
			if (type(k) == "string" or type(k) == "number") and (type(x) == "table" or type(x) == "string" or type(x) == "number" or type(x) == "boolean") then
				Write(k, out)
				Write(x, out)
			end
		end
		out[#out + 1] = "}"
	elseif t == "string" then
		out[#out + 1] = "s" .. #v .. ":" .. v
	elseif t == "number" then
		if v == v and v ~= math.huge and v ~= -math.huge then out[#out + 1] = "n" .. tostring(v) .. ";" else out[#out + 1] = "n0;" end -- (no infinities)
	elseif t == "boolean" then
		out[#out + 1] = v and "T" or "F"
	end
end

-- reads one value at `at`; returns it and where the next begins. Raises an error on anything unexpected.
local function Read(text, at, depth, count)
	count.n = count.n + 1
	if count.n > MAX_NODES then error("too much in it") end
	local c = text:sub(at, at)
	if c == "{" then
		if depth > MAX_DEPTH then error("too deep") end
		local out = {}
		at = at + 1
		while text:sub(at, at) ~= "}" do
			if at > #text then error("cut off") end
			local k, v
			k, at = Read(text, at, depth + 1, count)
			v, at = Read(text, at, depth + 1, count)
			if type(k) ~= "string" and type(k) ~= "number" then error("odd key") end
			out[k] = v
		end
		return out, at + 1
	elseif c == "s" then
		local len, colon = text:match("^(%d+)():", at + 1)
		len = tonumber(len)
		if not len or colon + len > #text then error("odd text") end
		return text:sub(colon + 1, colon + len), colon + len + 1
	elseif c == "n" then
		local num, after = text:match("^([%d%.%-%+eE]+);()", at + 1)
		num = tonumber(num)
		if not num or num ~= num or num == math.huge or num == -math.huge then error("odd number") end
		return num, after
	elseif c == "T" then
		return true, at + 1
	elseif c == "F" then
		return false, at + 1
	end
	error("not understood")
end

-- what each of the core's own keys has to be
local TOP_KIND = { settings = "table", modules = "table", tabs = "table", pos = "table", size = "table", minimap = "table",
	lastTab = "string", settingsSection = "string" }
-- Settings that are the player's own word on sharing with the guild: a text from somebody else never
-- answers those. They come in unset, so the addon asks as it does the first time.
local CONSENT = { share = true }

-- Only what a profile may hold is taken from what was read, and only where it is of the kind it should be:
-- a number where a table belongs would break whatever reads it at the next login.
local function Sane(v)
	if type(v) ~= "table" or v.v ~= 1 or type(v.top) ~= "table" or type(v.mods) ~= "table" then return nil end
	local out = { v = 1, top = {}, mods = {} }
	for _, key in ipairs(TOP) do
		if type(v.top[key]) == TOP_KIND[key] then out.top[key] = Copy(v.top[key]) end
	end
	-- (the one switch of sharing is among the core's settings: it too comes in unset)
	if out.top.settings then
		for key in pairs(CONSENT) do out.top.settings[key] = nil end
	end
	for name, m in pairs(v.mods) do
		local mod = DT.modules[name]
		if mod and type(m) == "table" then
			local keep = { settings = {}, keys = {} }
			for key, value in pairs(type(m.settings) == "table" and m.settings or {}) do
				-- (a module's settings are switches: yes or no)
				if type(key) == "string" and type(value) == "boolean" and not CONSENT[key] then keep.settings[key] = value end
			end
			local live = DT.db[name]
			for _, key in ipairs(mod.profile or {}) do
				local value = type(m.keys) == "table" and m.keys[key]
				-- (of the kind the module holds there now, where it holds anything)
				if value ~= nil and (type(live) ~= "table" or live[key] == nil or type(live[key]) == type(value)) then keep.keys[key] = Copy(value) end
			end
			out.mods[name] = keep
		end
	end
	return out
end

local function Deflate()
	return LibStub and LibStub("LibDeflate", true)
end

-- a profile as text to copy
function P.Export(name)
	local db = DT.db
	local snap = name == db.profile and P.Snapshot(db) or db.profiles[name]
	local LD = Deflate()
	if not (snap and LD) then return nil end
	local out = {}
	Write(snap, out)
	return PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(table.concat(out)))
end

-- a profile from such a text, stored under a new name (never switched to by itself). Returns the name, or
-- nil and why not.
function P.Import(text, name)
	text = tostring(text or ""):gsub("%s+", "")
	if #text > MAX_TEXT then return nil, "That text is too long to be a profile." end
	if text:sub(1, #PREFIX) ~= PREFIX then return nil, "That is not a DawnTools profile (it should begin with " .. PREFIX .. ")." end
	local LD = Deflate()
	local packed = LD and LD:DecodeForPrint(text:sub(#PREFIX + 1))
	local plain = packed and LD:DecompressDeflate(packed)
	if not plain then return nil, "That text is damaged: it could not be unpacked." end
	if #plain > MAX_TEXT * 10 then return nil, "That text unpacks to far more than a profile holds." end
	local ok, value = pcall(function() return (Read(plain, 1, 1, { n = 0 })) end)
	local snap = ok and Sane(value)
	if not snap then return nil, "That text is not a profile this version understands." end
	if not name or name == "" then
		name = "Imported"
		local n = 1
		while Exists(name) do
			n = n + 1
			name = "Imported " .. n
		end
	end
	local good, why = P.Name(name)
	if not good then return nil, why end
	DT.db.profiles[good] = snap
	return good
end

---------------------------------------------------------------------------
-- The Profiles section of the Settings tab
---------------------------------------------------------------------------

local rows, head, message = {}, nil, nil
local asking -- what the name popup is for: function(text)

local function Say(text, bad)
	if message then message:SetText(text and ((bad and "|cffff8080" or "|cff80ff80") .. text .. "|r") or "") end
end

local function Ask(title, start, fn)
	asking = fn
	P.askStart = start or ""
	StaticPopup_Show("DAWNTOOLS_PROFILE_TEXT", title)
end

local function Draw(panel)
	local list, current = P.List(), P.Current()
	head:SetText(("This character (|cffffd100%s|r) uses the profile |cffffd100%s|r. Characters that have picked none use Default."):format(P.Who(), current))
	for i = 1, math.max(#list, #rows) do
		local name, row = list[i], rows[i]
		if name and not row then
			row = CreateFrame("Frame", nil, panel)
			row:SetHeight(22)
			row:SetPoint("TOPLEFT", 4, -96 - (i - 1) * 24)
			row:SetPoint("RIGHT", -4, 0)
			row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.label:SetPoint("LEFT", 4, 0)
			row.label:SetWidth(190)
			row.label:SetJustifyH("LEFT")
			row.label:SetWordWrap(false)
			local x = 200
			local function Button(text, width, click)
				local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
				b:SetSize(width, 20)
				b:SetPoint("LEFT", x, 0)
				b:SetText(text)
				b:SetScript("OnClick", function() click(row.name) end)
				x = x + width + 4
				return b
			end
			row.use = Button("Use", 50, function(n) StaticPopup_Show("DAWNTOOLS_PROFILE_USE", n, nil, n) end)
			row.rename = Button("Rename", 66, function(n)
				Ask(("A new name for the profile \"%s\":"):format(n), n, function(text)
					local ok, why = P.Rename(n, text)
					Say(ok and ("Renamed to \"" .. ok .. "\".") or why, not ok)
				end)
			end)
			row.export = Button("Export", 60, function(n)
				local text = P.Export(n)
				if text then DT:ShowCopy(("Profile \"%s\" as text (%d letters)."):format(n, #text), text) else Say("That profile could not be exported.", true) end
			end)
			row.delete = Button("Delete", 60, function(n) StaticPopup_Show("DAWNTOOLS_PROFILE_DELETE", n, nil, n) end)
			rows[i] = row
		end
		if row then
			row:SetShown(name ~= nil)
			if name then
				row.name = name
				row.label:SetText((name == current and "|cffffd100> " or "   ") .. name .. (name == current and "|r" or ""))
				row.use:SetEnabled(name ~= current)
				row.rename:SetEnabled(name ~= DEFAULT)
				row.delete:SetEnabled(name ~= DEFAULT and name ~= current)
			end
		end
	end
end

local function Build(panel, kit)
	kit.Text(panel, "GameFontNormal", 4, -2, "Profiles")
	local about = kit.Text(panel, "GameFontHighlightSmall", 4, -22, "|cff888888A profile is how the addon is set up: settings, tabs, window, positions and filters. What was collected "
		.. "(prices, inventories, the combat log, favourites) is the same in every profile.\nSwitching reloads the interface.|r")
	about:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
	about:SetWordWrap(true)
	head = kit.Text(panel, "GameFontHighlightSmall", 4, -62, "")
	message = kit.Text(panel, "GameFontHighlightSmall", 4, -78, "")
	head.Load = function() Draw(panel) end
	kit.controls[#kit.controls + 1] = head
	-- along the bottom: what makes new ones
	local x = 4
	local function Button(text, width, click)
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(width, 22)
		b:SetPoint("BOTTOMLEFT", x, 6)
		b:SetText(text)
		b:SetScript("OnClick", function()
			click()
			DT.UI:Refresh()
		end)
		x = x + width + 6
		return b
	end
	P.newCopy = Button("New: copy of this", 130, function()
		Ask("A name for the new profile (a copy of how things are set up now):", "", function(text)
			local ok, why = P.New(text)
			Say(ok and ("Profile \"" .. ok .. "\" made. \"Use\" switches to it.") or why, not ok)
		end)
	end)
	P.newEmpty = Button("New: defaults", 110, function()
		Ask("A name for the new profile (everything as it is at first):", "", function(text)
			local ok, why = P.New(text, true)
			Say(ok and ("Profile \"" .. ok .. "\" made. \"Use\" switches to it.") or why, not ok)
		end)
	end)
	P.importButton = Button("Import", 70, function()
		Ask("Paste a profile's text (it begins with " .. PREFIX .. "):", "", function(text)
			local ok, why = P.Import(text)
			Say(ok and ("Imported as \"" .. ok .. "\". \"Use\" switches to it.") or why, not ok)
		end)
	end)
	P.resetButton = Button("Reset this profile", 130, function() StaticPopup_Show("DAWNTOOLS_PROFILE_RESET", P.Current()) end)
	P.rows, P.message = rows, message

	local function Box(popup)
		return popup and (popup.editBox or popup.EditBox or (popup.GetEditBox and popup:GetEditBox()))
	end
	local function Answer(popup)
		local box = Box(popup)
		if asking and box then asking(box:GetText()) end
		asking = nil
		DT.UI:Refresh()
	end
	StaticPopupDialogs.DAWNTOOLS_PROFILE_TEXT = {
		text = "%s", button1 = OKAY or "Okay", button2 = CANCEL or "Cancel", hasEditBox = true, editBoxWidth = 320, maxLetters = 0,
		OnShow = function(self)
			local box = Box(self)
			if box then
				box:SetText(P.askStart or "")
				if box.HighlightText then box:HighlightText() end
			end
		end,
		OnAccept = Answer,
		EditBoxOnEnterPressed = function(box)
			local popup = box:GetParent()
			Answer(popup)
			if popup and popup.Hide then popup:Hide() end
		end,
		EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs.DAWNTOOLS_PROFILE_USE = {
		text = "Use the profile \"%s\" on this character?\n\nThe interface reloads.",
		button1 = YES or "Yes", button2 = NO or "No",
		OnAccept = function(_, name) P.Use(name) end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs.DAWNTOOLS_PROFILE_DELETE = {
		text = "Delete the profile \"%s\"?\n\nCharacters that use it go back to Default.",
		button1 = YES or "Yes", button2 = NO or "No",
		OnAccept = function(_, name)
			local ok, why = P.Delete(name)
			Say(ok and ("Profile \"" .. name .. "\" deleted.") or why, not ok)
			DT.UI:Refresh()
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopupDialogs.DAWNTOOLS_PROFILE_RESET = {
		text = "Put the profile \"%s\" back to how everything is at first?\n\nSettings, tabs, window and positions; nothing that was collected. The interface reloads.",
		button1 = YES or "Yes", button2 = NO or "No",
		OnAccept = function() P.Reset() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
end

DT.UI:Section("profiles", "Profiles", 20, Build)
