-- DawnTools :: Carrot
-- Carrot on a Stick (a trinket: mount speed +3%) put on when I mount and the trinket it replaced put back when
-- I dismount. The player picks which of the two trinket slots it takes. Local only: nothing is sent.
-- The game lets no trinket be changed in combat: knocked off the mount by a hit, the carrot stays on until the
-- fight is over, and is swapped back then.
-- ponytail: the carrot only. Mithril Spurs (boots) and the riding enchant on gloves are the same swap in other
-- slots: make ITEM / slot a list when somebody has them. An empty slot gets the carrot and keeps it (there is
-- nothing to put back). A trinket with a "use" starts its 30 seconds of cooldown when put back: the game's rule.

local _, DT = ...
local C = {}
DT.Carrot = C

C.ITEM = 11122 -- Carrot on a Stick
C.SLOTS = { { 13, "Top trinket" }, { 14, "Bottom trinket" } }

local function Worn(slot)
	return GetInventoryItemID and GetInventoryItemID("player", slot) or nil
end

-- do I own one (worn or in the bags)? The carrot, or the item named.
function C.Have(item)
	local count = (C_Item and C_Item.GetItemCount) or GetItemCount
	local ok, n = pcall(function() return count(item or C.ITEM) end)
	return ok and (tonumber(n) or 0) > 0
end

local function Riding()
	return IsMounted and IsMounted() and not (UnitOnTaxi and UnitOnTaxi("player")) or false
end

-- One swap at a time: the game takes a moment over it, and asking again meanwhile only gets "item is locked".
-- A second later it is looked at again, which is also the second try where the first did nothing.
local busy, tries = false, 0 -- (tries: how often in a row the old trinket did not go back on)
local function Equip(item, slot)
	local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
	if not equip then return end
	busy = true
	pcall(equip, item, slot)
	C_Timer.After(1, function()
		busy = false
		C.Check(true)
	end)
end

-- Called whenever mounting, combat or what I wear may have changed. db.back = { item, slot }: the trinket the
-- carrot replaced and where (saved: a /reload on the mount does not lose it).
function C.Check(again)
	if busy or not C.db or (InCombatLockdown and InCombatLockdown()) then return end
	local s, back = C.db.settings, C.db.back
	-- (what each slot held last that was no carrot: what goes back where the note of it was lost)
	local last = C.db.last or {}
	C.db.last = last
	for _, slot in ipairs(C.SLOTS) do
		local id = Worn(slot[1])
		if id and id ~= C.ITEM then last[slot[1]] = id end
	end
	-- A carrot on, on foot, and no note of what it replaced (lost over a loading screen, say): left behind. The
	-- trinket that slot held last goes back, if I still have it and it is not in the other slot now.
	if not back and s.on and not Riding() then
		for _, slot in ipairs(C.SLOTS) do
			local at = slot[1]
			if not back and Worn(at) == C.ITEM and last[at] and Worn(27 - at) ~= last[at] and C.Have(last[at]) then
				back = { last[at], at }
				C.db.back = back
			end
		end
	end
	if Riding() then
		local slot = s.slot == 13 and 13 or 14
		-- (a carrot I put in either slot by hand is left where it is)
		if s.on and not back and Worn(13) ~= C.ITEM and Worn(14) ~= C.ITEM and C.Have() then
			local was = Worn(slot)
			if was then C.db.back = { was, slot } end
			Equip(C.ITEM, slot)
		end
	elseif back then
		-- (also when the tool was switched off meanwhile: what it took off, it puts back)
		-- (it will not go on: dead, or the trinket is gone. Five tries a second apart, then not until something changes)
		tries = again and tries + 1 or 0
		if Worn(back[2]) ~= C.ITEM then C.db.back = nil elseif tries < 5 then Equip(back[1], back[2]) end
	end
	if C.Refresh then C.Refresh() end
end

---------------------------------------------------------------------------
-- The tool's page
---------------------------------------------------------------------------

local boxes, status = {}, nil
C.boxes = boxes

local function NameOf(item)
	if not item then return "|cff888888empty|r" end
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, name = pcall(function() return info(item) end)
	return ok and name or ("item " .. item)
end

function C.Refresh()
	if not boxes.on then return end
	local s, back = C.db.settings, C.db.back
	boxes.on:SetChecked(s.on)
	for _, slot in ipairs(C.SLOTS) do
		local id = slot[1]
		boxes[id]:SetChecked((s.slot == 13 and 13 or 14) == id)
		-- (while the carrot is on, the slot is named by the trinket that comes back)
		local worn = back and back[2] == id and back[1] or Worn(id)
		boxes[id].label:SetText(slot[2] .. ": " .. NameOf(worn))
	end
	status:SetText(not C.Have() and "|cffff6060You have no Carrot on a Stick.|r It is the reward of the quest \"Gahz'rilla\" in Zul'Farrak."
		or back and ("|cff40ff40Carrot on.|r " .. NameOf(back[1]) .. " comes back when you dismount (after the fight, if you are in one).")
		or "|cff40ff40Carrot found.|r")
end

function C.Set(key, value)
	C.db.settings[key] = value
	C.Check()
	C.Refresh()
	if key == "on" then DT.Tools.Show() end -- (its sub-tab changes colour)
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
	local function Box(key, text, click)
		local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		box:SetSize(22, 22)
		box:SetPoint("TOPLEFT", 4, y)
		box.label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
		box.label:SetText(text)
		box:SetScript("OnClick", click)
		boxes[key] = box
		y = y - 24
	end
	Line("GameFontNormal", "Carrot", 20)
	Line("GameFontHighlightSmall", "Puts your Carrot on a Stick on when you mount, and the trinket it replaced back on when you dismount. "
		.. "Not on a flight path. A carrot found on you on foot is taken for left behind, and swapped for the trinket that slot held before.", 30)
	Box("on", "Swap the carrot in while mounted", function(self) C.Set("on", self:GetChecked() and true or false) end)
	y = y - 6
	Line("GameFontNormalSmall", "The trinket that makes room for it:", 16)
	for _, slot in ipairs(C.SLOTS) do
		Box(slot[1], slot[2], function() C.Set("slot", slot[1]) end)
	end
	y = y - 6
	status = Line("GameFontHighlightSmall", "", 30)
	Line("GameFontDisableSmall", "The game changes no trinket in combat: knocked off your mount by a hit, you keep the carrot until the fight is over. "
		.. "A trinket with a \"use\" has 30 seconds of cooldown after it is put back on.", 40)
end

DT:RegisterModule("carrot", {
	kind = "tool", -- (Settings > Tabs & Modules lists it under Tools)
	title = "Carrot",
	version = 1,
	defaults = { on = false, slot = 14 },
	onEnable = function(mod)
		C.db = mod.db
		DT:RegisterTool({ id = "carrot", title = "Carrot", order = 38, create = Build, onShow = C.Refresh,
			active = function() return C.db.settings.on end })
		for _, event in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_UNGHOST", "PLAYER_ALIVE" }) do
			DT:On(event, function() C.Check() end)
		end
		-- (the trinkets changed by hand: the page names them anew; and a client without the mount event still
		-- gets told of the mount through its aura)
		DT:On("UNIT_INVENTORY_CHANGED", function(unit) if unit == "player" then C.Check() end end)
		DT:On("UNIT_AURA", function(unit) if unit == "player" then C.Check() end end)
		if not SLASH_DAWNTOOLS_CARROT1 then
			SlashCmdList.DAWNTOOLS_CARROT = function() DT.Tools.Open("carrot") end
			SLASH_DAWNTOOLS_CARROT1 = "/dtcarrot"
		end
	end,
	selfTest = function(_, Try)
		Try("carrot check", C.Check)
	end,
})
