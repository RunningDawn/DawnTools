-- DawnTools :: Favourites
-- The tab with the star, beside Market: the items marked as favourites, each with what there is to say about
-- it: level, slot and kind, where it comes from, what it costs on the auction house and at a vendor, how many
-- I have. Local only: nothing is sent.
--
-- An item is made a favourite, or no longer one, with an Alt-click:
--   on an item row of these tabs (Items, the Craft tabs, Dungeons, a quest's rewards), and on a row here;
--   on an item anywhere in the game that takes a modified click: the bags, a vendor, the loot window, the
--     auction house (the game's own HandleModifiedItemClick, which this only listens to);
--   or with the Favourite button of the Market tab.
-- They are kept where the Market tab always kept its own (db.market.favs), so both show the same ones: DT.Favs
-- (Core.lua) is the one way in.

local _, DT = ...
local F = {}
DT.FavTab = F

local ROW_H, TOP_H = 18, 28
-- (a column of width 0 takes what is left; those of a width below 0 sit at the right edge, that wide, side by side)
local COLS = { { "Item", 230 }, { "Lvl", 36, true }, { "Slot", 92 }, { "Kind", 100 }, { "Where it comes from", 0 },
	{ "Auction", -92, true }, { "Vendor", -84, true }, { "Have", -52, true } }
local function RightOf(c)
	local w = 0
	for i = c + 1, #COLS do
		if COLS[i][2] < 0 then w = w - COLS[i][2] end
	end
	return w
end
local RIGHT_W = RightOf(0)

local panel, search, note, bar
local rows, heads, list, offset = {}, {}, {}, 0
local sortBy = { col = 1, desc = false }
local dirty = true
local asked = {} -- [item] = true: its facts were asked of the game this session

-- Where an item comes from, in a few words: a dungeon boss that drops it, the profession that makes it, a vendor,
-- a mob or a quest. Up to two of them. "" where nothing is known.
function F.Where(id)
	local parts = {}
	local Dg = DT.Dungeon
	local boss = Dg and Dg.DropOf and Dg.DropOf(id)
	if boss then
		local chance = Dg.Chance(boss, id)
		parts[#parts + 1] = ("|cffff8040Drop|r  %s, %s%s"):format(boss.name, boss.dungeon.name, chance and (" |cff888888(%s%%)|r"):format(("%g"):format(chance)) or "")
	end
	local band, profession
	if DT.CraftBand then band, profession = DT.CraftBand(id) end
	if band then parts[#parts + 1] = ("|cff40c0ffMade|r  %s %s"):format(profession, band) end
	if #parts < 2 then
		local Food = DT.Food
		local src = Food and Food.Source and Food.Source(id)
		-- (a drop named already by its dungeon boss is not said twice)
		if src and not (boss and src.kind == "drop") then parts[#parts + 1] = Food.WhereText(id, src) end
	end
	return table.concat(parts, "  |cff666666·|r  ")
end

local function Rebuild()
	local q = (search:GetText() or ""):lower()
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local api, count = DawnMarket and DawnMarket.API, DawnInventory and DawnInventory.API and DawnInventory.API.Count
	list = {}
	local budget = 60
	for id in pairs(DT.Favs.All()) do
		local name, _, quality, _, level, kind, sub, _, slot, icon = info(id)
		-- (one the game has not told us about yet: asked for once a session, a batch a pass)
		if not name and budget > 0 and not asked[id] and C_Item and C_Item.RequestLoadItemDataByID then
			budget, asked[id] = budget - 1, true
			pcall(C_Item.RequestLoadItemDataByID, id)
		end
		local shown = name or ("item " .. id)
		local where = F.Where(id)
		if q == "" or (shown .. " " .. where):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower():find(q, 1, true) then
			local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
			local ah = api and api.GetLatest and (api.GetLatest(id)) or nil
			local vendor = (api and api.GetVendor and (api.GetVendor(id))) or (DT.VendorPrice and DT.VendorPrice[id]) or nil
			local bags, bank = 0, 0
			if count then bags, bank = count(id) end
			local have = (bags or 0) + (bank or 0)
			list[#list + 1] = { id = id, name = shown,
				(icon and ("|T%s:14|t "):format(icon) or "") .. color .. shown .. "|r",
				level and level > 1 and tostring(level) or "", slot and slot ~= "" and (_G[slot] or slot) or "", sub or kind or "", where,
				ah and DT.Money(ah) or "|cff888888-|r", vendor and DT.Money(vendor) or "|cff888888-|r", have > 0 and tostring(have) or "|cff888888-|r",
				sort = { shown, level or 0, slot or "", sub or kind or "", where, ah or 0, vendor or 0, have } }
		end
	end
	table.sort(list, function(a, b)
		local x, y = a.sort[sortBy.col], b.sort[sortBy.col]
		if x ~= y then
			if sortBy.desc then return x > y end
			return x < y
		end
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 8, -TOP_H - ROW_H - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -12, 0)
	local shade = row:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
	row.vcols = {}
	local x = 0
	for c, col in ipairs(COLS) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if col[2] > 0 then
			fs:SetPoint("LEFT", x, 0)
			fs:SetWidth(col[2] - 6)
		elseif col[2] == 0 then
			fs:SetPoint("LEFT", x, 0)
			fs:SetPoint("RIGHT", -RIGHT_W - 6, 0)
		else
			fs:SetPoint("RIGHT", -RightOf(c) - 6, 0)
			fs:SetWidth(-col[2] - 6)
		end
		fs:SetJustifyH(col[3] and "RIGHT" or "LEFT")
		fs:SetWordWrap(false)
		row.vcols[c] = fs
		x = x + math.max(0, col[2])
	end
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. d.id)
		GameTooltip:AddLine("Click: everywhere it comes from. Alt-click: no longer a favourite.", 0.5, 0.8, 1)
		GameTooltip:AddLine("Shift-click: link in chat. Shift-right-click: its web page. Hold Shift: compare.", 0.5, 0.8, 1)
		GameTooltip:Show()
		DT:CompareTip(self)
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self, button)
		local d = self.data
		if not d then return end
		if DT:LinkClick(button, DT:GameItemLink(d.id, d.name), d.name, DT:ItemLink(d.id), d.id) or button == "RightButton" then return end
		if DT.Food and DT.Food.OpenItem then DT.Food.OpenItem(d.id, d.name) end
	end)
	rows[i] = row
	return row
end

function F.Refresh()
	if not panel then return end
	dirty = false
	Rebuild()
	local fit = math.max(1, math.floor((panel:GetHeight() - TOP_H - ROW_H) / ROW_H))
	local max = math.max(0, #list - fit)
	offset = math.max(0, math.min(offset, max))
	bar:SetMinMaxValues(0, max)
	bar:SetValue(offset)
	bar:SetShown(max > 0)
	bar.thumb:SetSize(8, math.max(16, fit * ROW_H * fit / math.max(fit, #list)))
	for i = 1, math.max(fit, #rows) do
		local d = i <= fit and list[offset + i]
		local row = rows[i] or (d and MakeRow(i))
		if row then
			row.data = d or nil
			row:SetShown(d and true or false)
			for c, cell in ipairs(row.vcols) do cell:SetText(d and d[c] or "") end
		end
	end
	for c, h in ipairs(heads) do
		h.text:SetText("|cffffd100" .. COLS[c][1] .. (sortBy.col == c and (sortBy.desc and " v" or " ^") or "") .. "|r")
	end
	local n = 0
	for _ in pairs(DT.Favs.All()) do n = n + 1 end
	note:SetText(n == 0 and "|cff888888No favourites yet. Alt-click an item to make it one: on an item row of these tabs, in your bags, at a vendor, in the loot window.|r"
		or ("%d favourite%s  |cff888888Alt-click an item anywhere to add or remove one.|r"):format(n, n == 1 and "" or "s"))
end

local function Build(parent)
	panel = parent
	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("TOPLEFT", 12, -3)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function() -- (hooked: the template's own handler shows the "Search" hint)
		offset, dirty = 0, true
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	F.search = search
	note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("LEFT", search, "RIGHT", 12, 0)
	note:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	note:SetJustifyH("LEFT")
	note:SetWordWrap(false)
	F.note = note

	local x = 8
	for c, col in ipairs(COLS) do
		-- click to sort, again to turn it round
		local h = CreateFrame("Button", nil, panel)
		if col[2] < 0 then h:SetPoint("TOPRIGHT", -12 - RightOf(c) - 6, -TOP_H) else h:SetPoint("TOPLEFT", x, -TOP_H) end
		h:SetSize(col[2] > 0 and col[2] - 6 or col[2] < 0 and -col[2] - 6 or 200, ROW_H)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetJustifyH(col[3] and "RIGHT" or "LEFT")
		h.text:SetWordWrap(false)
		h:SetScript("OnClick", function()
			if sortBy.col == c then
				sortBy.desc = not sortBy.desc
			else
				sortBy.col, sortBy.desc = c, c >= 6 -- (prices and how many from the most; the rest from A)
			end
			F.Refresh()
		end)
		heads[c] = h
		x = x + math.max(0, col[2])
	end
	F.heads = heads

	bar = CreateFrame("Slider", nil, panel)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(8)
	bar:SetPoint("TOPRIGHT", -1, -TOP_H - ROW_H)
	bar:SetPoint("BOTTOMRIGHT", -1, 2)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.3)
	bar.thumb = bar:CreateTexture(nil, "OVERLAY")
	bar.thumb:SetColorTexture(0.78, 0.68, 0.37, 0.9)
	bar:SetThumbTexture(bar.thumb)
	bar:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value + 0.5)
		if value == offset then return end -- (Refresh sets the bar too)
		offset = value
		F.Refresh()
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		F.Refresh()
	end)
	panel:SetScript("OnSizeChanged", F.Refresh)
	local nextUpdate = 0
	DT.OnUpdate(panel, "tab: Favourites", function()
		if not dirty or GetTime() < nextUpdate then return end
		if InCombatLockdown and InCombatLockdown() then return end -- (in a fight the lists wait)
		nextUpdate = GetTime() + 0.5
		F.Refresh()
	end)
end

-- An Alt-click on an item anywhere in the game (the game's own handler of modified clicks is listened to, not
-- changed): a favourite, or no longer one.
function F.OnModifiedClick(link)
	if not (IsAltKeyDown and IsAltKeyDown()) or (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then return end
	local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
	if id then DT.Favs.Toggle(id, link:match("%[(.-)%]")) end
end

DT:RegisterModule("favs", {
	title = "Favourites",
	version = 1,
	slash = "/dtfav",
	-- (the button on the bar shows a star instead of the title, as Home shows a house)
	tab = { id = "favs", title = "Favourites", defaultOrder = 11, create = Build, onShow = F.Refresh,
		icon = { atlas = "auctionhouse-icon-favorite", texture = "Interface\\Common\\ReputationStar" } },
	onEnable = function()
		DT:On("DT_FAVS", function() dirty = true end)
		DT:On("DT_MARKET_UPDATE", function() dirty = true end)
		DT:On("GET_ITEM_INFO_RECEIVED", function(item) if asked[item] then dirty = true end end)
		if hooksecurefunc and HandleModifiedItemClick then pcall(hooksecurefunc, "HandleModifiedItemClick", function(link) F.OnModifiedClick(link) end) end
	end,
})
