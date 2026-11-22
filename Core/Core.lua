-- DawnTools :: Core
-- Saved data, events, chat output, the module registry, slash commands, the minimap button.

local ADDON, DT = ...
_G.DawnTools = DT

DT.VERSION = "0.54.5" -- keep in step with the .toc
DT.LOGO = "Interface\\AddOns\\DawnTools\\logo"

local DEFAULTS = {
	instances = false,  -- send guild messages inside instances too
	background = true,  -- read NPCs, quests and items a little at a time after login, so their tabs open at once
	coins = true,       -- prices with the game's coin pictures (off: "1g 20s 5c")
	theme = "original", -- "original", "modern", "ellesmere", or "classic"
}

---------------------------------------------------------------------------
-- Events: game events and our own share one table. DT:On("EVENT", fn), DT:Fire("EVENT", ...)
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers, where = {}, {} -- (where: [handler] = the file and line that asked for it, for /dt perf)

function DT:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		-- our own events are not game events: RegisterEvent raises an error for those
		-- (pcall: a game event this client does not know must not stop the addon from loading)
		if not event:find("^DT_") then pcall(frame.RegisterEvent, frame, event) end
	end
	table.insert(handlers[event], fn)
	local stack = debugstack and debugstack(2, 1, 0) or ""
	where[fn] = stack:match("DawnTools[/\\](.-:%d+)") or "?"
end

-- (each handler on its own: one that fails is reported and the rest still run)
-- How long what runs takes, and how much memory it makes, for /dt perf:
-- [name] = { n = times, ms = in all, max = the longest once, kb = memory made in all, kbmax = the most once }
-- (memory made: what Lua holds after less before; a clean-up of the garbage in between shows as none)
DT.perf = {}
local clock = debugprofilestop
local function heap() local ok, kb = pcall(collectgarbage, "count") return ok and kb or 0 end
-- (what ran since t0, m0 = DT.Mark(), noted under a name)
function DT.Mark() return clock and clock(), heap() end
function DT.Note(name, t0, m0)
	if not t0 then return end
	local ms, kb, p = clock() - t0, math.max(0, heap() - m0), DT.perf[name]
	if not p then p = { n = 0, ms = 0, max = 0, kb = 0, kbmax = 0 } DT.perf[name] = p end
	p.n, p.ms, p.max, p.kb, p.kbmax = p.n + 1, p.ms + ms, math.max(p.max, ms), p.kb + kb, math.max(p.kbmax, kb)
end
function DT.Timed(name, fn, ...)
	local t0, m0 = DT.Mark()
	local ok, err = pcall(fn, ...)
	DT.Note(name, t0, m0)
	if not ok then geterrorhandler()(err) end
end
-- a frame's OnUpdate, timed under a name
function DT.OnUpdate(f, name, fn)
	f:SetScript("OnUpdate", function(...) DT.Timed(name, fn, ...) end)
end

function DT:Fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do DT.Timed(event .. " " .. (where[fn] or "?"), fn, ...) end
end

-- /dt perf: the slowest since the /reload, by the longest single run. "/dt perf all": by the time in all (what
-- runs often), "/dt perf mem": by the memory made (churn), "/dt perf gc": memory before and after a clean-up
-- (a short freeze), "/dt perf reset": start again.
local function AddonKB()
	if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
	local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
	return get and get("DawnTools") or 0
end
function DT.PerfReport(how)
	if how == "reset" then DT.perf = {} DT:Print("perf: counting anew.") return end
	if how == "gc" then
		local before = AddonKB()
		pcall(collectgarbage, "collect")
		DT:Print("perf: DawnTools holds %.1f MB; %.1f MB after a clean-up (the rest was garbage, made and let go).", before / 1024, AddonKB() / 1024)
		return
	end
	local by = how == "all" and "ms" or how == "mem" and "kb" or "max"
	local list = {}
	for name, p in pairs(DT.perf) do list[#list + 1] = { name = name, p = p } end
	table.sort(list, function(a, b) return a.p[by] > b.p[by] end)
	DT:Print("perf since the /reload, %s. DawnTools holds %.1f MB now. (/dt perf all | mem | gc | reset)",
		by == "ms" and "by time in all" or by == "kb" and "by memory made" or "by the longest once", AddonKB() / 1024)
	for i = 1, math.min(12, #list) do
		local p = list[i].p
		print(("  %s  %.1f ms once, %.0f ms in all, x%d  |cff888888%.0f KB made (%.0f once)|r"):format(list[i].name, p.max, p.ms, p.n, p.kb, p.kbmax))
	end
end

frame:SetScript("OnEvent", function(_, event, ...) DT:Fire(event, ...) end)

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

function DT:Print(msg, ...)
	if select("#", ...) > 0 then msg = msg:format(...) end
	print("|cffc6ad5eDawnTools|r: " .. msg)
end

-- /dt debug <module>
function DT:Debug(module, msg, ...)
	if self.db and self.db.debug[module] then self:Print("|cff888888[" .. module .. "] " .. msg .. "|r", ...) end
end

-- A price for showing: with the game's coin pictures, or as "1g 20s 5c" where the player prefers letters.
-- (Logic.Money is the plain text, for anything a picture cannot go into.)
local COIN = {
	"|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	"|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	"|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
-- The skill band of the recipe that makes an item (DT.CraftSkill: from the store, Core/DBSeed.lua), as the Professions window colours it:
-- learned at (orange), yellow, green, grey. Returns the band as text and the profession's name; nothing for an
-- item no profession makes. "?" where the skill it is learned at is not known.
local PROFESSION = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
	[185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }
function DT.CraftBand(item)
	local b = DT.CraftSkill and DT.CraftSkill[item]
	if not b then return nil end
	return ("|cffff8040%s|r |cffffff00%d|r |cff40c040%d|r |cff808080%d|r"):format(b[2] > 0 and b[2] or "?", b[3], b[4], b[5]),
		PROFESSION[b[1]] or "Profession"
end

function DT.ProfessionName(id) return PROFESSION[id] end

-- The recipes an item goes into as a material: { { spell =, r = the recipe's row }, ... }, or nil for none.
-- (DT.Recipes: r[9] = { reagent, count, ... }. Put together on the first ask, and again once the recipes are.)
local usedIn, usedFrom = {}, nil -- (empty, not nil: a new member has no recipes yet, and DT.Recipes nil == usedFrom)
function DT.UsedIn(item)
	if usedFrom ~= DT.Recipes then
		usedIn, usedFrom = {}, DT.Recipes
		for spell, r in pairs(DT.Recipes or {}) do
			local mats = type(r) == "table" and type(r[9]) == "table" and r[9] or {}
			for i = 1, #mats, 2 do
				local id = mats[i]
				if type(id) == "number" then
					usedIn[id] = usedIn[id] or {}
					table.insert(usedIn[id], { spell = spell, r = r })
				end
			end
		end
	end
	return usedIn[item]
end

-- a recipe's name: the game's name of its spell, else the item it makes
function DT.RecipeName(spell, r)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell) or (GetSpellInfo and GetSpellInfo(spell))
	if not name and r and r[7] and C_Item and C_Item.GetItemInfo then name = C_Item.GetItemInfo(r[7]) end
	return name or ("recipe " .. tostring(spell))
end

function DT.Money(copper)
	if not (DT.db and DT.db.settings.coins) then return DT.Logic.Money(copper) end
	local c = math.floor(math.abs(copper) + 0.5)
	local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
	c = c % 100
	local text = g > 0 and ("%d%s %d%s %d%s"):format(g, COIN[1], s, COIN[2], c, COIN[3])
		or s > 0 and ("%d%s %d%s"):format(s, COIN[2], c, COIN[3]) or ("%d%s"):format(c, COIN[3])
	return copper < 0 and "-" .. text or text
end

-- A character as shown: "First Surname". On Forever the surname is what other clients give as the realm, so a
-- sender "First-Surname" is written with a space; one without a surname stays as it is.
function DT.Name(sender)
	return (tostring(sender or ""):gsub("%-", " ", 1))
end

-- what begins every line DawnTools puts on an item's tooltip, in gold: "DT: Auction", "DT: Vendor"
DT.TIP = "|cffffd100DT:|r "

-- server time: the same clock for every guild member
function DT.Now()
	return GetServerTime and GetServerTime() or time()
end

---------------------------------------------------------------------------
-- Themes & Widget Skinning ("original", "modern", "ellesmere", "classic")
---------------------------------------------------------------------------

local function ClassOrEllesmereAccent()
	local eui = _G.EllesmereUI
	if type(eui) == "table" and type(eui.GetAccentColor) == "function" then
		local ok, r, g, b = pcall(eui.GetAccentColor, eui)
		if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
			return r, g, b
		end
	end
	local _, class = UnitClass and UnitClass("player")
	local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
	local c = class and colors and colors[class]
	if c then return c.r, c.g, c.b end
	return 0.40, 0.78, 1.00
end

DT.THEME_ORDER = { "original", "modern", "ellesmere", "classic" }
DT.THEMES = {
	original = {
		id = "original",
		name = "Original",
		native = true,
		bg = { 0.06, 0.06, 0.07, 0.95 },
		popupBg = { 0.06, 0.06, 0.07, 0.97 },
		subBg = { 1, 1, 1, 0.04 },
		border = { 0.0, 0.0, 0.0, 1.0 },
		popupBorder = { 0.78, 0.68, 0.37, 1.0 },
		hover = { 1, 1, 1, 0.08 },
		accent = function() return 1.0, 0.82, 0.0 end,
	},
	modern = {
		id = "modern",
		name = "Modern",
		bg = { 0.08, 0.09, 0.11, 0.95 },
		popupBg = { 0.07, 0.08, 0.10, 0.98 },
		subBg = { 0.11, 0.12, 0.15, 0.85 },
		border = { 0.24, 0.27, 0.33, 1.0 },
		popupBorder = { 0.30, 0.35, 0.44, 1.0 },
		btnBg = { 0.14, 0.16, 0.20, 0.95 },
		btnBorder = { 0.26, 0.30, 0.37, 1.0 },
		inputBg = { 0.05, 0.06, 0.08, 0.95 },
		hover = { 1, 1, 1, 0.08 },
		sep = { 1, 1, 1, 0.14 },
		title = { 0.92, 0.80, 0.45 },
		accent = function() return 0.35, 0.72, 0.95 end,
	},
	ellesmere = {
		id = "ellesmere",
		name = "EllesmereUI",
		bg = { 0.045, 0.045, 0.05, 0.97 },
		popupBg = { 0.04, 0.04, 0.045, 0.98 },
		subBg = { 0.07, 0.07, 0.08, 0.95 },
		border = { 0.0, 0.0, 0.0, 1.0 },
		popupBorder = { 0.0, 0.0, 0.0, 1.0 },
		btnBg = { 0.085, 0.085, 0.095, 0.95 },
		btnBorder = { 0.0, 0.0, 0.0, 1.0 },
		inputBg = { 0.03, 0.03, 0.035, 0.98 },
		hover = { 1, 1, 1, 0.06 },
		sep = { 1, 1, 1, 0.10 },
		title = { 0.95, 0.95, 0.95 },
		accent = ClassOrEllesmereAccent,
	},
	classic = {
		id = "classic",
		name = "Classic WoW",
		native = true,
		classic = true,
		bg = { 1, 1, 1, 0.96 },
		popupBg = { 1, 1, 1, 0.96 },
		subBg = { 0.08, 0.06, 0.04, 0.55 },
		border = { 1, 1, 1, 1 },
		popupBorder = { 1, 1, 1, 1 },
		btnBg = { 0.12, 0.09, 0.06, 0.9 },
		btnBorder = { 0.55, 0.45, 0.25, 1 },
		inputBg = { 0.05, 0.04, 0.03, 0.9 },
		hover = { 1, 0.82, 0, 0.12 },
		sep = { 0.85, 0.70, 0.30, 0.28 },
		title = { 1.0, 0.82, 0.0 },
		accent = function() return 1.0, 0.82, 0.0 end,
	},
}

function DT:Theme()
	local id = self.db and self.db.settings and self.db.settings.theme or "original"
	local t = DT.THEMES[id] or DT.THEMES.original
	local r, g, b = t.accent()
	local hex = ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
	return t, r, g, b, hex
end

local weak = { __mode = "k" }
local skinnedFrames = setmetatable({}, weak)
local skinnedButtons = setmetatable({}, weak)
local skinnedChecks = setmetatable({}, weak)
local skinnedEdits = setmetatable({}, weak)
local skinnedCloses = setmetatable({}, weak)
local skinnedBars = setmetatable({}, weak)
local skinnedHighlights = setmetatable({}, weak)
local skinnedSelections = setmetatable({}, weak)

local function EnsureBackdrop(f)
	if not f.SetBackdrop and BackdropTemplateMixin then
		Mixin(f, BackdropTemplateMixin)
	end
end

-- kind: "window" | "popup" | "menu" | "inset" | "panel" | "sidebar"
function DT:SkinFrame(f, kind)
	if not f then return f end
	EnsureBackdrop(f)
	skinnedFrames[f] = kind or "panel"
	local t = self:Theme()
	if not f.SetBackdrop then return f end
	if t.classic then
		if kind == "window" then
			f:SetBackdrop({
				bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 256, edgeSize = 24,
				insets = { left = 6, right = 6, top = 6, bottom = 6 },
			})
			f:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], t.bg[4])
			f:SetBackdropBorderColor(1, 1, 1, 1)
		elseif kind == "popup" then
			f:SetBackdrop({
				bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 256, edgeSize = 16,
				insets = { left = 4, right = 4, top = 4, bottom = 4 },
			})
			f:SetBackdropColor(t.popupBg[1], t.popupBg[2], t.popupBg[3], t.popupBg[4])
			f:SetBackdropBorderColor(1, 1, 1, 1)
		elseif kind == "menu" then
			f:SetBackdrop({
				bgFile = "Interface\\FrameGeneral\\UI-Background-Marble",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 256, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			f:SetBackdropColor(0.65, 0.60, 0.54, 0.98)
			f:SetBackdropBorderColor(0.95, 0.80, 0.35, 1)
		elseif kind == "inset" or kind == "sidebar" then
			f:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8x8",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			f:SetBackdropColor(0.06, 0.05, 0.04, kind == "sidebar" and 0.72 or 0.62)
			f:SetBackdropBorderColor(0.85, 0.70, 0.32, 0.95)
		else
			f:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8x8",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 10,
				insets = { left = 2, right = 2, top = 2, bottom = 2 },
			})
			f:SetBackdropColor(0.14, 0.11, 0.08, 0.85)
			f:SetBackdropBorderColor(0.85, 0.70, 0.32, 0.9)
		end
	elseif t.native then
		if kind == "popup" or kind == "menu" then
			f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
			f:SetBackdropColor(t.popupBg[1], t.popupBg[2], t.popupBg[3], t.popupBg[4])
			f:SetBackdropBorderColor(t.popupBorder[1], t.popupBorder[2], t.popupBorder[3], t.popupBorder[4])
		elseif kind == "sidebar" or kind == "panel" then
			f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
			f:SetBackdropColor(1, 1, 1, kind == "sidebar" and 0.04 or 0.08)
		else
			f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
			f:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], t.bg[4])
			f:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], t.border[4])
		end
	else
		local bg = (kind == "popup" or kind == "menu") and t.popupBg or (kind == "sidebar" or kind == "panel") and t.subBg or t.bg
		local bd = (kind == "popup" or kind == "menu") and t.popupBorder or t.border
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
		f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
	end
	return f
end

function DT:SkinHighlight(tex, alpha)
	if not tex then return tex end
	skinnedHighlights[tex] = alpha or false
	local t, ar, ag, ab = self:Theme()
	if t.native then
		tex:SetColorTexture(t.hover[1], t.hover[2], t.hover[3], alpha or t.hover[4])
	else
		tex:SetColorTexture(ar, ag, ab, alpha or 0.14)
	end
	return tex
end

function DT:SkinSelection(tex, alpha)
	if not tex then return tex end
	skinnedSelections[tex] = alpha or false
	local _, ar, ag, ab = self:Theme()
	tex:SetColorTexture(ar, ag, ab, alpha or 0.18)
	return tex
end

local function SetBlizButtonAlpha(b, alpha)
	for _, key in ipairs({ "Left", "Middle", "Right" }) do
		if b[key] and b[key].SetAlpha then b[key]:SetAlpha(alpha) end
	end
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
		local tex = b[getter] and b[getter](b)
		if tex and tex.SetAlpha then tex:SetAlpha(alpha) end
	end
end

function DT:SkinButton(b)
	if not b then return b end
	EnsureBackdrop(b)
	if not skinnedButtons[b] then
		skinnedButtons[b] = true
		b._dtHover = b:CreateTexture(nil, "HIGHLIGHT")
		b._dtHover:SetAllPoints()
		b._dtActiveBar = b:CreateTexture(nil, "OVERLAY")
		b._dtActiveBar:SetHeight(2)
		b._dtActiveBar:SetPoint("BOTTOMLEFT", 1, 1)
		b._dtActiveBar:SetPoint("BOTTOMRIGHT", -1, 1)
		b._dtActiveBar:Hide()

		local origLock, origUnlock = b.LockHighlight, b.UnlockHighlight
		b.LockHighlight = function(self)
			self._dtActive = true
			if origLock then origLock(self) end
			DT:SkinButton(self)
		end
		b.UnlockHighlight = function(self)
			self._dtActive = false
			if origUnlock then origUnlock(self) end
			DT:SkinButton(self)
		end
	end
	local t, ar, ag, ab = self:Theme()
	if t.native then
		SetBlizButtonAlpha(b, 1)
		if b.SetBackdrop then b:SetBackdrop(nil) end
		b._dtHover:SetColorTexture(0, 0, 0, 0)
		b._dtActiveBar:Hide()
	else
		SetBlizButtonAlpha(b, 0)
		if b.SetBackdrop then
			b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
			if b._dtActive then
				b:SetBackdropColor(ar * 0.25 + t.btnBg[1], ag * 0.25 + t.btnBg[2], ab * 0.25 + t.btnBg[3], 0.98)
				b:SetBackdropBorderColor(ar, ag, ab, 0.9)
			else
				b:SetBackdropColor(t.btnBg[1], t.btnBg[2], t.btnBg[3], t.btnBg[4])
				b:SetBackdropBorderColor(t.btnBorder[1], t.btnBorder[2], t.btnBorder[3], t.btnBorder[4])
			end
		end
		b._dtHover:SetColorTexture(ar, ag, ab, 0.16)
		b._dtActiveBar:SetColorTexture(ar, ag, ab, 1)
		b._dtActiveBar:SetShown(b._dtActive and true or false)
	end
	return b
end

function DT:SkinCheckBox(cb)
	if not cb then return cb end
	if not skinnedChecks[cb] then
		skinnedChecks[cb] = true
		local box = CreateFrame("Frame", nil, cb, "BackdropTemplate")
		box:SetSize(14, 14)
		box:SetPoint("CENTER", 0, 0)
		box:EnableMouse(false)
		local fill = box:CreateTexture(nil, "OVERLAY")
		fill:SetPoint("TOPLEFT", 3, -3)
		fill:SetPoint("BOTTOMRIGHT", -3, 3)
		box.fill = fill
		cb._dtBox = box

		local function SyncCheck(self)
			if self._dtBox then self._dtBox.fill:SetShown(self:GetChecked() and true or false) end
		end
		cb:HookScript("OnClick", SyncCheck)
		hooksecurefunc(cb, "SetChecked", SyncCheck)
		cb:HookScript("OnEnter", function(self)
			local t, ar, ag, ab = DT:Theme()
			if not t.native and self._dtBox and self._dtBox.SetBackdropBorderColor then
				self._dtBox:SetBackdropBorderColor(ar, ag, ab, 1)
			end
		end)
		cb:HookScript("OnLeave", function(self)
			local t = DT:Theme()
			if not t.native and self._dtBox and self._dtBox.SetBackdropBorderColor then
				self._dtBox:SetBackdropBorderColor(t.btnBorder[1], t.btnBorder[2], t.btnBorder[3], t.btnBorder[4])
			end
		end)
	end
	local t, ar, ag, ab = self:Theme()
	local alpha = t.native and 1 or 0
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
		local tex = cb[getter] and cb[getter](cb)
		if tex and tex.SetAlpha then tex:SetAlpha(alpha) end
	end
	cb._dtBox:SetShown(not t.native)
	if not t.native then
		EnsureBackdrop(cb._dtBox)
		cb._dtBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		cb._dtBox:SetBackdropColor(t.inputBg[1], t.inputBg[2], t.inputBg[3], t.inputBg[4])
		cb._dtBox:SetBackdropBorderColor(t.btnBorder[1], t.btnBorder[2], t.btnBorder[3], t.btnBorder[4])
		cb._dtBox.fill:SetColorTexture(ar, ag, ab, 1)
		cb._dtBox.fill:SetShown(cb:GetChecked() and true or false)
	end
	return cb
end

function DT:SkinEditBox(eb)
	if not eb then return eb end
	EnsureBackdrop(eb)
	if not skinnedEdits[eb] then
		skinnedEdits[eb] = true
		eb:HookScript("OnEditFocusGained", function(self)
			local t, ar, ag, ab = DT:Theme()
			if not t.native and self.SetBackdropBorderColor then self:SetBackdropBorderColor(ar, ag, ab, 1) end
		end)
		eb:HookScript("OnEditFocusLost", function(self)
			local t = DT:Theme()
			if not t.native and self.SetBackdropBorderColor then
				self:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], t.border[4])
			end
		end)
	end
	local t = self:Theme()
	local alpha = t.native and 1 or 0
	for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do
		if eb[key] and eb[key].SetAlpha then eb[key]:SetAlpha(alpha) end
	end
	if eb.SetBackdrop then
		if t.native then
			eb:SetBackdrop(nil)
		else
			eb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
			eb:SetBackdropColor(t.inputBg[1], t.inputBg[2], t.inputBg[3], t.inputBg[4])
			eb:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], t.border[4])
		end
	end
	return eb
end

function DT:SkinCloseButton(btn)
	if not btn then return btn end
	if not skinnedCloses[btn] then
		skinnedCloses[btn] = true
		local hover = btn:CreateTexture(nil, "HIGHLIGHT")
		hover:SetPoint("TOPLEFT", 5, -5)
		hover:SetPoint("BOTTOMRIGHT", -5, 5)
		btn._dtHover = hover
		local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("CENTER", 0, 1)
		label:SetText("x")
		btn._dtLabel = label
		btn:HookScript("OnEnter", function(self)
			if self._dtLabel and self._dtLabel:IsShown() then self._dtLabel:SetTextColor(1, 0.35, 0.35) end
		end)
		btn:HookScript("OnLeave", function(self)
			if self._dtLabel and self._dtLabel:IsShown() then self._dtLabel:SetTextColor(0.85, 0.85, 0.85) end
		end)
	end
	local t = self:Theme()
	local alpha = t.native and 1 or 0
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
		local tex = btn[getter] and btn[getter](btn)
		if tex and tex.SetAlpha then tex:SetAlpha(alpha) end
	end
	btn._dtHover:SetColorTexture(1, 0.25, 0.25, t.native and 0 or 0.22)
	btn._dtLabel:SetShown(not t.native)
	btn._dtLabel:SetTextColor(0.85, 0.85, 0.85)
	return btn
end

function DT:SkinScrollBar(bar, track)
	if not bar then return bar end
	skinnedBars[bar] = track or bar._dtTrack or false
	if track then bar._dtTrack = track end
	local t, ar, ag, ab = self:Theme()
	if bar._dtTrack then
		bar._dtTrack:SetColorTexture(0, 0, 0, t.native and 0.3 or 0.45)
	end
	if bar.thumb then
		if t.native then
			bar.thumb:SetColorTexture(0.78, 0.68, 0.37, 0.9)
		else
			bar.thumb:SetColorTexture(ar, ag, ab, 0.85)
		end
	end
	return bar
end

function DT:ApplyTheme()
	for f, kind in pairs(skinnedFrames) do self:SkinFrame(f, kind) end
	for b in pairs(skinnedButtons) do self:SkinButton(b) end
	for cb in pairs(skinnedChecks) do self:SkinCheckBox(cb) end
	for eb in pairs(skinnedEdits) do self:SkinEditBox(eb) end
	for btn in pairs(skinnedCloses) do self:SkinCloseButton(btn) end
	for bar, track in pairs(skinnedBars) do self:SkinScrollBar(bar, track or nil) end
	for tex, alpha in pairs(skinnedHighlights) do self:SkinHighlight(tex, alpha or nil) end
	for tex, alpha in pairs(skinnedSelections) do self:SkinSelection(tex, alpha or nil) end
	self:Fire("DT_THEME", self:Theme().id)
end

function DT:SetTheme(id)
	id = tostring(id or ""):lower()
	if not DT.THEMES[id] then return false end
	if self.db and self.db.settings then self.db.settings.theme = id end
	self:ApplyTheme()
	if self.UI and self.UI.Refresh then self.UI:Refresh() end
	return true
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
-- DT:RegisterModule("market", {
--   title    = "Market",
--   version  = 1,
--   defaults = { key = value },                    the module's settings
--   settings = { { key = "x", label = "..." } },   checkboxes on the Settings tab
--   status   = function(mod) return "one line" end shown under them
--   tab      = { id, title, defaultOrder, create = function(parent) end, onShow = fn, onHide = fn,
--                group = 2,                        tabs of another group stand apart on the bar (default 1)
--                under = "world" },                not on the bar itself: a sub-tab of that place (see UI.lua)
--   slash    = "/dtmarket",                         opens the tab, if nobody else owns the command
--   onEnable = function(mod) end,                  at login, unless the module is switched off
--   hello    = function(mod) return "summary" end, sent along with the core's HELLO
--   onHello  = function(mod, sender, summary) end,
--   onMessage = function(mod, kind, payload, sender) end,
-- })
-- The core sets mod.name, mod.db (its saved table, with .settings) and mod.enabled.

DT.modules, DT.order = {}, {}

-- a module's saved part and whether it is on (at load; or at once for a module registered after it, before login)
function DT.SetupModule(db, mod)
	local name = mod.name
	if type(db[name]) ~= "table" then db[name] = {} end
	if type(db[name].settings) ~= "table" then db[name].settings = {} end
	for key, value in pairs(mod.defaults or {}) do
		if db[name].settings[key] == nil then db[name].settings[key] = value end
	end
	mod.db = db[name]
	if mod.defaultOff then
		mod.enabled = db.modules[name] == true
	else
		mod.enabled = db.modules[name] ~= false
	end
end

function DT:RegisterModule(name, mod)
	mod.name = name
	self.modules[name] = mod
	self.order[#self.order + 1] = name
	if self.db then DT.SetupModule(self.db, mod) end
end

-- for _, mod in DT:Enabled() do
function DT:Enabled()
	local list = {}
	for _, name in ipairs(self.order) do
		if self.modules[name].enabled then list[#list + 1] = self.modules[name] end
	end
	return ipairs(list)
end

---------------------------------------------------------------------------
-- Reading in the background
---------------------------------------------------------------------------
-- The long lists (NPCs, quests, items) are read from QuestieDB the first time their tab is looked at, which
-- takes a second or two. With DT.db.settings.background they are read a few seconds after login instead, one
-- after the other, about 2 ms a frame, not in combat: the tabs then open at once.
--   DT:Background({ Start = function() return true when there is something to read end,
--                   Step  = function(ms) read on for about ms; return true when done end })
local readers = {}
local reader = CreateFrame("Frame")
reader:Hide()
reader:SetScript("OnUpdate", function(self)
	if InCombatLockdown and InCombatLockdown() then return end
	local r = readers[1]
	if not r then return self:Hide() end
	-- (a list that fails to read is reported once and dropped: the others still get their turn)
	local ok, done
	local t0, m0 = DT.Mark()
	if not r.begun then
		r.begun = true
		ok, done = pcall(r.Start)
		done = ok and not done
	else
		ok, done = pcall(r.Step, 2)
	end
	DT.Note("background: " .. (r.name or "?"), t0, m0)
	if not ok then
		table.remove(readers, 1)
		geterrorhandler()(done)
	elseif done then
		table.remove(readers, 1)
	end
end)

-- the setting switched on in mid-session: begin now (off: what is being read stops at once)
function DT:ReadInBackground(on)
	reader:SetShown(on and #readers > 0 or false)
end

function DT:Background(r)
	readers[#readers + 1] = r
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
-- DawnToolsDB (account-wide):
--   settings   see DEFAULTS
--   modules    [name] = false       switched off on the Settings tab
--   debug      [name] = true
--   tabs       { rank = { [id] = n }, hidden = { [id] = true } }
--   pos, size  window position, { width, height }
--   lastTab    id
--   minimap    { hide, minimapPos = degrees round the minimap } (the shape LibDBIcon kept, which drew the button once)
--   [name]     each module's own table; .settings holds its settings

local function Init()
	DawnToolsDB = DawnToolsDB or {}
	local db = DawnToolsDB
	-- this character's profile, before anything reads the tables (Profiles.lua)
	if DT.Profiles then DT.Profiles.Login(db) end
	-- (whatever has got into the saved data, these are tables when anything reads them)
	for _, key in ipairs({ "settings", "modules", "debug", "minimap" }) do
		if type(db[key]) ~= "table" then db[key] = {} end
	end
	if type(db.tabs) ~= "table" then db.tabs = {} end
	if type(db.tabs.rank) ~= "table" then db.tabs.rank = {} end
	if type(db.tabs.hidden) ~= "table" then db.tabs.hidden = {} end
	if type(db.tabs.sub) ~= "table" then db.tabs.sub = nil end
	-- (nested too: a rank is compared as a number, a position or size is a finite one)
	local function Num(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end
	for id, n in pairs(db.tabs.rank) do if not Num(n) then db.tabs.rank[id] = nil end end
	if type(db.pos) ~= "table" or type(db.pos[1]) ~= "string" or type(db.pos[2]) ~= "string" or not Num(db.pos[3]) or not Num(db.pos[4]) then db.pos = nil end
	if type(db.size) ~= "table" or not Num(db.size[1]) or not Num(db.size[2]) then db.size = nil end
	if type(db.lastTab) ~= "string" then db.lastTab = nil end
	if type(db.settingsSection) ~= "string" then db.settingsSection = nil end
	for key, value in pairs(DEFAULTS) do
		if db.settings[key] == nil then db.settings[key] = value end
	end
	for _, name in ipairs(DT.order) do DT.SetupModule(db, DT.modules[name]) end
	DT.db = db
end

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------

local function Probe()
	-- SPEC phase 0: which of the things we rely on exist on this client
	local names = {
		"C_AuctionHouse.GetNumCommoditySearchResults", "C_AuctionHouse.GetCommoditySearchResultInfo",
		"C_AuctionHouse.GetNumItemSearchResults", "C_AuctionHouse.GetItemSearchResultInfo", "C_AuctionHouse.GetBrowseResults",
		"C_AuctionHouse.GetItemKeyInfo", "C_AuctionHouse.SendBrowseQuery", "C_AuctionHouse.RequestMoreBrowseResults",
		"C_AuctionHouse.HasFullBrowseResults", "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems", "C_AuctionHouse.GetReplicateItemInfo",
		"C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage", "C_Item.GetItemInfo",
		"C_Item.RequestLoadItemDataByID", "C_Container.GetContainerItemInfo", "UnitGUID", "CombatLogGetCurrentEventInfo", "GetServerTime", "IsInGuild", "IsInInstance",
		"InCombatLockdown", "Ambiguate", "TooltipDataProcessor.AddTooltipPostCall", "StaticPopup_Show",
		"Auctionator.API.v1.GetAuctionPriceByItemID", "Auctionator.API.v1.GetAuctionAgeByItemID",
		"Auctionator.API.v1.RegisterForDBUpdate",
		"LibQuestieDB.Npc.GetAllIds", "LibStub", "TargetFrame", "FocusFrame", "OpenWorldMap", "WorldMapFrame.SetMapID", "SLASH_PING1", "C_Ping", "SLASH_TARGET_MARKER1", "C_Spell.GetSpellPowerCost", "GetSpellPowerCost", "PlayerFrame", "PlayerFrameManaBar", "issecretvalue", "UnitCanAttack", "C_SpellBook.GetSpellBookItemInfo", "C_Spell.IsSpellInRange", "C_Spell.GetSpellInfo", "IsSpellInRange", "GetSpellTabInfo", "UnitPosition", "LibQuestieDB.Quest.GetAllIds", "LibQuestieDB.Item.GetAllIds", "LibQuestieDB.Object.Get", "GetItemStats", "C_Item.GetItemStats", "UnitDefense", "GetTalentTabInfo", "GetNumTalentTabs", "GetSpecialization", "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetTalentTabInfo", "AtlasLoot.Data.Profession.GetCraftSpellForCreatedItem", "C_QuestLog.GetAllCompletedQuestIDs", "C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.IsOnQuest", "C_QuestLog.GetQuestTagInfo", "GetQuestTagInfo", "GetQuestsCompleted", "QuestieLoader.ImportModule", "TomTom.AddWaypoint", "C_Map.GetAreaInfo", "C_Map.SetUserWaypoint",
		"UiMapPoint.CreateFromCoordinates", "C_SuperTrack.SetSuperTrackedUserWaypoint", "debugprofilestop",
	}
	local missing = {}
	for _, name in ipairs(names) do
		local value = _G
		for part in name:gmatch("[^.]+") do value = type(value) == "table" and value[part] or nil end
		if type(value) ~= "function" then missing[#missing + 1] = name end
	end
	DT:Print("probe: %d of %d functions exist.%s", #names - #missing, #names,
		#missing > 0 and (" Missing: " .. table.concat(missing, ", ")) or "")

	-- (not COMBAT_LOG_EVENT*: registering it gets the addon blocked here)
	local events = { "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
		"AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "REPLICATE_ITEM_LIST_UPDATE", "GET_ITEM_INFO_RECEIVED", "CHAT_MSG_ADDON", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MERCHANT_SHOW", "LOOT_READY", "TRADE_SKILL_SHOW" }
	local unknown, tester = {}, CreateFrame("Frame")
	for _, event in ipairs(events) do
		local ok
		if C_EventUtils and C_EventUtils.IsEventValid then
			ok = C_EventUtils.IsEventValid(event)
		else
			ok = pcall(tester.RegisterEvent, tester, event)
		end
		if not ok then unknown[#unknown + 1] = event end
	end
	tester:UnregisterAllEvents()
	DT:Print("probe: %d of %d events exist.%s", #events - #unknown, #events,
		#unknown > 0 and (" Unknown: " .. table.concat(unknown, ", ")) or "")

	-- Which auction house is this? Run at each kind of auctioneer and compare the lines: whatever differs
	-- (the auctioneer's id, its faction, the zone) is what can tell the houses apart.
	local npc = UnitGUID and UnitGUID("npc")
	if npc then
		DT:Print("probe: auctioneer '%s', id %s, faction %s, zone '%s' / '%s', map %s, my faction %s.",
			tostring(UnitName("npc")), tostring(npc:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)") or npc),
			tostring(UnitFactionGroup and UnitFactionGroup("npc") or "?"),
			tostring(GetZoneText and GetZoneText() or "?"), tostring(GetSubZoneText and GetSubZoneText() or "?"),
			tostring(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or "?"),
			tostring(UnitFactionGroup and UnitFactionGroup("player") or "?"))
	else
		DT:Print("probe: no auctioneer open. Run this with the auction house window open to see which house it is.")
	end

	local peers = 0
	for _ in pairs(DT.Comms.peers) do peers = peers + 1 end
	DT:Print("probe: I am '%s', guild '%s', on the wire '%s'. %d guild members with DawnTools heard this session.",
		tostring(DT.me), tostring(GetGuildInfo and GetGuildInfo("player") or nil), tostring(DT.Comms.self or "not heard yet"), peers)
end

-- true when no addon has claimed the command (SLASH_FOO1 = "/dt")
-- (the slash commands taken, read off _G once at login: a walk of every global is a tenth of a second or more)
local taken
local function SlashFree(cmd)
	if not taken then
		taken = {}
		for key, value in pairs(_G) do
			if type(key) == "string" and type(value) == "string" and key:sub(1, 6) == "SLASH_" then taken[value:lower()] = true end
		end
	end
	return not taken[cmd]
end

local function Slash(input)
	local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		DT.UI:Toggle()
	elseif DT.UI:HasTab(cmd) then
		DT.UI:Show(cmd)
	elseif DT.Tools and DT.Tools.Has(cmd) and DT.UI:HasTab("tools") then -- (a tool of the Tools tab, by name)
		DT.Tools.Open(cmd)
	elseif cmd == "debug" and DT.modules[rest:lower()] then
		local name = rest:lower()
		DT.db.debug[name] = not DT.db.debug[name] or nil
		DT:Print("debug %s %s", name, DT.db.debug[name] and "on" or "off")
	elseif cmd == "reset" then
		DT.UI:ResetWindow()
		DT:Print("window back to its first size and place.")
	elseif cmd == "probe" then
		Probe()
	elseif cmd == "perf" then
		DT.PerfReport(rest:lower())
	elseif cmd == "map" then
		DT.MapTime()
	elseif cmd == "db" then
		DT.DB.Slash(rest)
	elseif cmd == "sync" then
		DT.Comms:Diagnose()
	elseif cmd == "deathtest" then
		if DT.Combat and DT.Combat.DeathReport then DT.Combat.DeathReport() else DT:Print("deathtest: the Combat module is switched off.") end
	elseif cmd == "logtest" then
		-- An experiment: can the lines the game printed in the Combat Log chat tab be read? Reads, changes nothing.
		local frame = COMBATLOG
		for i = 1, NUM_CHAT_WINDOWS or 10 do
			local f = _G["ChatFrame" .. i]
			if not frame and f and IsCombatLog and IsCombatLog(f) then frame = f end
		end
		frame = frame or ChatFrame2
		if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then
			DT:Print("logtest: no Combat Log chat tab that can be read was found.")
			return
		end
		local n = frame:GetNumMessages()
		DT:Print(("logtest: %s holds %d lines. The last %d, as written:"):format(frame:GetName() or "the tab", n, math.min(n, 6)))
		for i = math.max(1, n - 5), n do
			local ok, text = pcall(frame.GetMessageInfo, frame, i)
			if not ok then
				DT:Print(("  %d: reading failed: %s"):format(i, tostring(text)))
			elseif issecretvalue and issecretvalue(text) then
				DT:Print(("  %d: HIDDEN by the game (a secret value)"):format(i))
			else
				DT:Print(("  %d: %s"):format(i, tostring(text):gsub("|", "||"):sub(1, 400)))
			end
		end
	elseif cmd == "theme" then
		local pick = rest:lower()
		if DT:SetTheme(pick) then
			DT:Print("theme set to %s.", DT:Theme().name)
		else
			DT:Print("themes: %s (current: %s)", table.concat(DT.THEME_ORDER, ", "), DT:Theme().id)
		end
	elseif cmd == "selftest" then
		DT.UI:SelfTest()
	else
		local tabs = {}
		for _, mod in DT:Enabled() do
			for _, tab in ipairs(mod.tabs or { mod.tab }) do tabs[#tabs + 1] = tab.id end
		end
		tabs[#tabs + 1] = "settings"
        		DT:Print("/dt (window) | /dt %s | /dt theme <%s> | /dt debug <%s> | /dt probe | /dt perf (what is slow) | /dt sync (guild messages: what goes out and comes in) | /dt selftest | /dt reset (window size and place)",
        			table.concat(tabs, " | /dt "), table.concat(DT.THEME_ORDER, "|"), table.concat(DT.order, "|"))
        	end
end

-- An addon cannot open a browser: the link is shown in a box, ready to copy.
StaticPopupDialogs.DAWNTOOLS_LINK = {
	text = "%s\n\nCopy the link with Ctrl+C and paste it into your browser.",
	button1 = CLOSE or "Close", hasEditBox = true, editBoxWidth = 320, maxLetters = 0, -- (0: as long as it likes)
	OnShow = function(self, url)
		local box = self.editBox or self.EditBox
		if not box then return end
		box:SetText(url)
		box:HighlightText()
		box:SetFocus()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- any text to copy (a profile, say), with words that fit
StaticPopupDialogs.DAWNTOOLS_COPY = {
	text = "%s\n\nCtrl+C copies it.",
	button1 = CLOSE or "Close", hasEditBox = true, editBoxWidth = 320, maxLetters = 0, -- (0: as long as it likes)
	OnShow = StaticPopupDialogs.DAWNTOOLS_LINK.OnShow,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function DT:ShowCopy(title, text)
	StaticPopup_Show("DAWNTOOLS_COPY", title, nil, text)
end

function DT:ShowLink(title, url)
	StaticPopup_Show("DAWNTOOLS_LINK", title, nil, url)
end

-- Favourites: items marked to be kept an eye on. One list for the whole addon (the tab with the star shows it,
-- the Market tab marks them with a star), kept where the Market tab always kept its own: db.market.favs.
DT.Favs = {}
function DT.Favs.All()
	local market = DT.db.market
	if type(market) ~= "table" then
		market = {}
		DT.db.market = market
	end
	market.favs = market.favs or {}
	return market.favs
end
function DT.Favs.Is(item)
	return DT.Favs.All()[item] and true or false
end
-- makes an item a favourite, or no longer one; says so (name: for the saying); returns what it is now
function DT.Favs.Toggle(item, name)
	local favs = DT.Favs.All()
	favs[item] = not favs[item] or nil
	DT:Print(favs[item] and "%s: a favourite now (the tab with the star lists them)." or "%s: no longer a favourite.", name or ("item " .. item))
	DT:Fire("DT_FAVS", item)
	return favs[item] or false
end

-- the line for an item row's tooltip that says what an Alt-click does (by whether it is a favourite already)
function DT.Favs.Hint(tip, item)
	tip:AddLine(DT.Favs.Is(item) and "Alt-click: no longer a favourite." or "Alt-click: make it a favourite (the tab with the star lists them).", 0.5, 0.8, 1)
end

-- A click on a row with Shift held, as on anything in the game: the left button puts its link into the chat
-- line being written (a line is opened if none is); the right button shows its web page, to copy.
-- Returns true when Shift was held (the click is dealt with).
-- (item: its number where the row is an item's. With Alt held instead, the item is made a favourite, or no
-- longer one: see DT.Favs.)
function DT:LinkClick(button, link, title, url, item)
	if item and IsAltKeyDown and IsAltKeyDown() then
		DT.Favs.Toggle(item, title)
		return true
	end
	if not (IsShiftKeyDown and IsShiftKeyDown()) then return false end
	if button == "RightButton" then
		self:ShowLink(title, url)
	elseif link then
		local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
		local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
		if not (insert and insert(link)) and open then open(link) end
	end
	return true
end

-- Shift held over one of our item rows: the game's own comparison with what I wear, beside the tooltip, as over
-- an item in the bags (also where the game is set to compare always). DT:CompareTip(owner) after the row's
-- tooltip is shown; pressing or letting go of Shift while it is up shows or hides the comparison.
local compared
local function Compare()
	if not (compared and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(compared)) then return end
	local always = GetCVarBool and GetCVarBool("alwaysCompareItems")
	if (IsShiftKeyDown and IsShiftKeyDown()) or always then
		if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
	elseif GameTooltip_HideShoppingTooltips then
		pcall(GameTooltip_HideShoppingTooltips, GameTooltip)
	end
end
function DT:CompareTip(owner)
	compared = owner
	Compare()
end
DT:On("MODIFIER_STATE_CHANGED", function(key)
	if key == "LSHIFT" or key == "RSHIFT" then Compare() end
end)

-- the game's own link of an item (as the game writes it once it knows the item; else a plain one)
function DT:GameItemLink(id, name)
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, _, link = pcall(function() return get(id) end)
	return ok and link or ("|cffffffff|Hitem:%d::::::::::::|h[%s]|h|r"):format(id, name or ("item " .. id))
end

-- where to read up on an item
-- ponytail: Wowhead's Classic pages. Forever has items and sources of its own that are not there.
function DT:ItemLink(id)
	return "https://www.wowhead.com/forever/item=" .. id
end

function DT:OpenTab(id)
	self.UI:Show(id)
end

function DawnTools_OnAddonCompartmentClick()
	DT.UI:Toggle()
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

DT:On("ADDON_LOADED", function(name)
	if name == ADDON then Init() end
end)

-- Minimap button: our own. It was drawn through whichever LibDBIcon another addon had loaded, and that library
-- lays a button out differently from version to version, so the round sun sat off-centre for whoever had
-- another copy than mine. Now it is the same button for everybody.
-- ponytail: a round minimap is assumed; on a square one the button rides the circle. Corners if someone has one.
local mini
local function MiniClick(_, button)
	if button == "RightButton" then DT.UI:Show("settings") else DT.UI:Toggle() end
end
local function MiniTip(tip)
	tip:AddLine("DawnTools")
	tip:AddLine("Click: window. Right-click: settings.", 1, 1, 1)
end
local function PlaceMini()
	local angle = math.rad(tonumber(DT.db.minimap.minimapPos) or 225)
	local r = (Minimap:GetWidth() or 140) / 2 + 5
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end
local function MakeMini()
	if mini or not Minimap then return end
	mini = CreateFrame("Button", "DawnToolsMinimapButton", Minimap)
	mini:SetSize(31, 31)
	mini:SetFrameStrata("MEDIUM")
	mini:SetFrameLevel(8)
	mini:RegisterForClicks("AnyUp")
	mini:RegisterForDrag("LeftButton")
	mini:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
	-- The ring and the dark disc in it, as the game's own minimap buttons have them. Two sets of numbers: the
	-- game with the addon compartment draws the ring a little smaller. (Measured on a screenshot there: the
	-- ring's middle is one up and half right of the disc's; the hole is 22 across, the sun 20.)
	local modern = AddonCompartmentFrame ~= nil
	local ring = mini:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
	ring:SetSize(modern and 50 or 53, modern and 50 or 53)
	ring:SetPoint("TOPLEFT", 0, 0)
	local disc = mini:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
	if modern then
		disc:SetSize(24, 24)
		disc:SetPoint("CENTER", 0, 0)
	else
		disc:SetSize(20, 20)
		disc:SetPoint("TOPLEFT", 7, -5)
	end
	local sun = mini:CreateTexture(nil, "ARTWORK")
	sun:SetTexture(DT.LOGO)
	sun:SetSize(20, 20)
	sun:SetPoint("CENTER", disc, "CENTER", 0.5, 1)
	mini.icon = sun
	mini:SetScript("OnClick", MiniClick)
	mini:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		MiniTip(GameTooltip)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- dragged: it follows the mouse round the minimap
	mini:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale() or 1
			if not (mx and my and px and py) then return end
			DT.db.minimap.minimapPos = math.deg((math.atan2 or math.atan)(py / scale - my, px / scale - mx)) % 360
			PlaceMini()
		end)
	end)
	mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	DT.minimapButton = mini
end

function DT:ShowMinimap(on)
	self.db.minimap.hide = not on
	MakeMini()
	if not mini then return end
	PlaceMini()
	mini:SetShown(on and true or false)
end

---------------------------------------------------------------------------
-- Sharing with the guild: one switch for all of it
---------------------------------------------------------------------------
-- DT.db.settings.share: nil until the player has answered, then true or false. Every kind of shared data goes
-- by it (docs/DATA.md, 4): with it off nothing is sent and nothing is taken in.
function DT:Shares()
	return self.db ~= nil and self.db.settings.share == true
end

-- yes or no, said by the player (the popup, or the switch on the Settings tab)
function DT:SetSharing(on)
	self.db.settings.share = on and true or false
	-- (the modules that send what they hold when sharing begins hear it as a change of their setting)
	if on then
		-- (the first hello: none went out before the yes)
		if DT.Comms then DT.Comms:Hello() end
		for _, mod in DT:Enabled() do DT:Fire("DT_SETTINGS", mod.name, "share") end
	end
end

-- asked a little after login and by /dt db, while it has not been answered
function DT:AskToShare()
	if self.db.settings.share == nil and IsInGuild() then StaticPopup_Show("DAWNTOOLS_SHARE") end
end

StaticPopupDialogs.DAWNTOOLS_SHARE = {
	text = "DawnTools: share with the guild?\n\n"
		.. "DawnTools does not come with the game's data: recipes, dungeons, NPCs, quests and items reach you from guild "
		.. "members who use it, and you pass on what you hold.\n\n"
		.. "Also sent to them as you play: the auction prices you see, with your character's name (it can be left out in "
		.. "the settings), and what vendors ask; each of your characters' names and the recipes it knows, of cooking and "
		.. "its other professions; what a quest gave you and the level you were; what a boss dropped and how often you "
		.. "looted it; what you catch fishing, and where; and what you loot or meet that nobody knew, under a random number.\n\n"
		.. "Nothing else is sent, and you can switch it off at any time: /dt settings.",
	button1 = "Share", button2 = "Not now",
	OnAccept = function() DT:SetSharing(true) end,
	-- (only a real no: a popup pushed aside by another one asks again next time)
	OnCancel = function(_, _, reason)
		if reason == "clicked" then DT:SetSharing(false) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

DT:On("PLAYER_LOGIN", function()
	-- (me with my surname, as the guild sees me; first = the name alone, as observations before 0.52 have it)
	DT.first = UnitName("player")
	local first, last = DT.first, nil
	if UnitFullName then first, last = UnitFullName("player") end
	DT.me = (first or DT.first or "?") .. (type(last) == "string" and last ~= "" and (" " .. last) or "")
	DT:Print("version %s loaded. /dt opens the window.", DT.VERSION)
	DT:ApplyTheme()
	C_Timer.After(5, function() DT:AskToShare() end)

	for _, mod in DT:Enabled() do
		-- a module that fails must not take the others with it; the error still reaches BugSack
		DT.Timed("start: " .. tostring(mod.name), mod.onEnable or function() end, mod) -- (Timed: in a pcall, errors still reported)
	end

	C_Timer.After(5, function()
		if DT.db.settings.background then reader:Show() end
	end)

	SlashCmdList.DAWNTOOLS = Slash
	SLASH_DAWNTOOLS1 = "/dawntools"
	if SlashFree("/dt") then SLASH_DAWNTOOLS2 = "/dt" end
	for _, mod in DT:Enabled() do
		if mod.slash and mod.tab and SlashFree(mod.slash) then
			local key = "DAWNTOOLS_" .. mod.name:upper()
			SlashCmdList[key] = function() DT.UI:Show(mod.tab.id) end
			_G["SLASH_" .. key .. "1"] = mod.slash
		end
	end

	DT:ShowMinimap(not DT.db.minimap.hide)
	-- (for broker bars, where that library is there: the same clicks)
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if ldb then
		pcall(ldb.NewDataObject, ldb, "DawnTools", { type = "launcher", icon = DT.LOGO, OnClick = MiniClick, OnTooltipShow = MiniTip })
	end
end)

-- Guild messages start in a handler of their own. They used to start at the end of the one above, after the
-- minimap button: whatever failed there (another player's copy of a library, say) left this client deaf and
-- mute to the guild, without a word.
DT:On("PLAYER_LOGIN", function() DT.Comms:Start() end)