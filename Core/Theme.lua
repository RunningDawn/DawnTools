-- DawnTools :: Themes
-- The look of the window and its widgets, picked on Settings > Themes: "original" (the look DawnTools always
-- had), "modern", "ellesmere" (dark, with EllesmereUI's accent colour where that addon is installed, else the
-- class colour) and "classic" (the game's own stone and gold).
-- A widget is skinned once where it is made (DT:SkinFrame, SkinButton, SkinCheckBox, SkinEditBox,
-- SkinCloseButton, SkinScrollBar, SkinHighlight, SkinSelection) and is remembered: DT:SetTheme paints all of
-- them anew and fires DT_THEME (the theme's id) for whatever lays itself out by the theme.
-- Kept in DT.db.settings.theme. Loaded before Core/UI.lua, which skins as it builds.

local _, DT = ...

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
		-- (the original theme: each kind exactly as it was before there were themes)
		if kind == "menu" then
			f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
			f:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
		elseif kind == "popup" then
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

-- plain: how strong it is under the original theme, where that differs (what the widget had before there were
-- themes; 0 where it had none)
function DT:SkinHighlight(tex, alpha, plain)
	if not tex then return tex end
	skinnedHighlights[tex] = { alpha or false, plain }
	local t, ar, ag, ab = self:Theme()
	if t.native then
		tex:SetColorTexture(t.hover[1], t.hover[2], t.hover[3], t.id == "original" and plain or alpha or t.hover[4])
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
	for tex, a in pairs(skinnedHighlights) do self:SkinHighlight(tex, a[1] or nil, a[2]) end
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

-- the saved theme, once the saved settings are there
DT:On("PLAYER_LOGIN", function() DT:ApplyTheme() end)
