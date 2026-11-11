-- The window and the button. Flat dark panel, 1px border, gold accents and the GameFont* set, so a
-- UI skin (DragonUI) carries its fonts and colours into it.

local _, TL = ...
local floor, max, min = math.floor, math.max, math.min
local LOOT = TL.LOOT
local DB = TL.DB

local PANEL_WIDTH, PANEL_HEIGHT = 346, 404
local ROW_HEIGHT = 34
local HEADER_HEIGHT = 22
-- The window resizes from its bottom-right corner, but never narrower than the creature's name
-- (FitToContent below) and never wider or taller than this.
local MIN_WIDTH, MIN_HEIGHT = 260, 180
local MAX_WIDTH, MAX_HEIGHT = 640, 620
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local GOLD = { 0.84, 0.69, 0.36 }
local DIM = { 0.55, 0.55, 0.55 }

local button, panel
local currentEntry
local rowPool, headerPool = {}, {}

-- The list is the panel less its side padding, so a resize only has to re-point it.
local function ContentWidth()
	return max(60, (panel and panel:GetWidth() or PANEL_WIDTH) - 44)
end

-----------------------------------------
-- helpers

local function Skin(frame, alpha)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(0.02, 0.02, 0.02, alpha or 0.95)
	frame:SetBackdropBorderColor(0.28, 0.25, 0.18, 1)
end

local function Flat(parent, layer)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	tex:SetTexture(WHITE)
	return tex
end

local function ChanceText(hundredths)
	local pct = (tonumber(hundredths) or 0) / 100
	if pct >= 99.95 then return "100%" end
	if pct >= 10 then return string.format("%d%%", floor(pct + 0.5)) end
	if pct >= 1 then return (string.format("%.1f", pct):gsub("%.0$", "")) .. "%" end
	if pct >= 0.01 then return (string.format("%.2f", pct):gsub("0$", "")) .. "%" end
	return "<0.01%"
end

local ARMOR = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shield",
	[7] = "Libram", [8] = "Idol", [9] = "Totem", [10] = "Sigil" }
local WEAPON = { [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace",
	[6] = "Polearm", [7] = "Sword", [8] = "Sword", [10] = "Staff", [13] = "Fist Weapon",
	[14] = "Miscellaneous", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow", [19] = "Wand", [20] = "Fishing Pole" }
local SLOT = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs",
	[8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Trinket", [13] = "Weapon",
	[14] = "Off hand", [15] = "Ranged", [16] = "Back", [17] = "Two-hand", [20] = "Robe",
	[21] = "Main hand", [22] = "Off hand", [23] = "Held", [25] = "Thrown", [26] = "Ranged", [28] = "Relic" }

local function TypeText(d)
	local slot = SLOT[d.invType]
	if d["class"] == 4 then
		local kind = ARMOR[d.subclass]
		if not kind then return slot or "" end
		return (slot and (slot .. ", ") or "") .. kind
	elseif d["class"] == 2 then
		local kind = WEAPON[d.subclass]
		return (slot and (slot .. ", ") or "") .. (kind or "")
	end
	return slot or ""
end

-- Item data lives in Core: it asks the client and refreshes the window when it lands.
local QueryItem = TL.QueryItem

local function ItemInfo(d)
	local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(d.item)
	return name or d.name or ("Item #" .. d.item), link, quality or d.quality or 1, texture
end

local function ItemLink(d, link)
	return link or select(2, GetItemInfo(d.item)) or ("item:" .. d.item)
end

-----------------------------------------
-- the button on the target frame

local function ButtonCount(entry)
	local loot = TL.Loot(entry)
	return loot and #loot.rows or 0
end

local function UpdateButton()
	if not button then return end
	if not currentEntry or (TargetFrame and not TargetFrame:IsShown()) then
		button:Hide()
		return
	end
	local count = ButtonCount(currentEntry)
	local loot = TL.Loot(currentEntry)
	button.icon:SetDesaturated(not loot)
	if loot then
		button:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
		button.icon:SetVertexColor(1, 1, 1)
	else
		button:SetBackdropBorderColor(0.28, 0.25, 0.18, 1)
		button.icon:SetVertexColor(0.7, 0.7, 0.7)
	end
	button.count:SetText(loot and count > 0 and tostring(count) or "")
	button:Show()
end

local function CreateButton()
	button = CreateFrame("Button", "TargetLootJournalButton", UIParent)
	button:SetSize(22, 22)
	button:SetFrameStrata("MEDIUM")
	button:SetClampedToScreen(true)
	Skin(button, 0.92)
	button:RegisterForClicks("LeftButtonUp")

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 3, -3)
	button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	button.icon:SetTexture(BAG_ICON)
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	button.count = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.count:SetPoint("BOTTOMRIGHT", 1, -1)
	button.count:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	local glow = Flat(button, "HIGHLIGHT")
	glow:SetAllPoints(button.icon)
	glow:SetVertexColor(1, 1, 1, 0.18)

	button:SetScript("OnClick", function () TL.Toggle() end)
	button:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine(UnitName("target") or "Target loot", 1, 1, 1)
		local loot = currentEntry and TL.Loot(currentEntry)
		if loot then
			local shared = 0
			for i = 1, #loot.rows do
				if bit.band(loot.rows[i].flags, LOOT.SHARED) ~= 0 then shared = shared + 1 end
			end
			GameTooltip:AddLine(string.format("%d drop%s, %d of them shared world drops",
				#loot.rows, #loot.rows == 1 and "" or "s", shared), 0.72, 0.72, 0.72)
		else
			GameTooltip:AddLine("Asking the journal server...", DIM[1], DIM[2], DIM[3])
		end
		GameTooltip:AddLine("Click to open; Ctrl-click the window to preview, Shift-click to link.",
			0.5, 0.5, 0.5, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function () GameTooltip:Hide() end)

	if TargetFrame then
		-- Above the target frame and its art, or the portrait and bars draw over it.
		button:SetFrameStrata("HIGH")
		button:SetFrameLevel((TargetFrame.GetFrameLevel and TargetFrame:GetFrameLevel() or 1) + 5)
		button:SetPoint("TOPRIGHT", TargetFrame, "TOPRIGHT", 4, 4)
		TargetFrame:HookScript("OnHide", function ()
			button:Hide()
			if panel then panel:Hide() end
		end)
		TargetFrame:HookScript("OnShow", function () UpdateButton() end)
	else
		button:SetPoint("CENTER", UIParent, "CENTER", -200, 120)
	end
	button:Hide()
end

-----------------------------------------
-- the window

local function SetupRow(row, d)
	local name, link, quality, texture = ItemInfo(d)
	if not GetItemInfo(d.item) then QueryItem(d.item) end

	row.data = d
	row.link = link
	row.itemID = d.item
	row.icon:SetTexture(texture or FALLBACK_ICON)
	row.name:SetText(name)
	local color = ITEM_QUALITY_COLORS[quality] or ITEM_QUALITY_COLORS[1]
	row.name:SetTextColor(color.r, color.g, color.b)
	row.chance:SetText(ChanceText(d.chance))

	local bits = {}
	if d.max and d.max > 1 then
		bits[#bits + 1] = d.min == d.max and ("x" .. d.max) or ("x" .. d.min .. "-" .. d.max)
	end
	local kind = TypeText(d)
	if kind ~= "" then bits[#bits + 1] = kind end
	if bit.band(d.flags, LOOT.QUEST) ~= 0 then bits[#bits + 1] = "|cff80c0ffquest only|r" end
	if bit.band(d.flags, LOOT.CONDITION) ~= 0 then bits[#bits + 1] = "|cffc0a060conditional|r" end
	if bit.band(d.flags, LOOT.HARD_MODE) ~= 0 then bits[#bits + 1] = "|cffff8020hard mode|r" end
	if bit.band(d.flags, LOOT.BOP) ~= 0 then bits[#bits + 1] = "|cff9d9d9dbinds|r" end
	row.meta:SetText(table.concat(bits, "  "))
end

local function NewRow()
	local row = CreateFrame("Button", nil, panel.content)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(26, 26)
	row.icon:SetPoint("LEFT", 2, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
	row.name:SetPoint("RIGHT", row, "RIGHT", -62, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.meta:SetPoint("RIGHT", row, "RIGHT", -62, 0)
	row.meta:SetJustifyH("LEFT")
	row.meta:SetTextColor(DIM[1], DIM[2], DIM[3])

	row.chance = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.chance:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.chance:SetJustifyH("RIGHT")
	row.chance:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	local glow = row:CreateTexture(nil, "HIGHLIGHT")
	glow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 1, 1, 0.22)
	glow:SetAllPoints(row)

	row:SetScript("OnEnter", function (self)
		if not self.data then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:ClearLines()
		GameTooltip:SetHyperlink(ItemLink(self.data, self.link))
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Drop chance", ChanceText(self.data.chance), 1, 0.82, 0, 1, 1, 1)
		local d = self.data
		if d.max and d.max > 1 then
			GameTooltip:AddDoubleLine("Amount", d.min == d.max and tostring(d.max) or (d.min .. "-" .. d.max),
				1, 0.82, 0, 1, 1, 1)
		end
		if bit.band(d.flags, LOOT.QUEST) ~= 0 then
			GameTooltip:AddLine("Only drops while you are on the quest that needs it.", 0.6, 0.8, 1, true)
		end
		if bit.band(d.flags, LOOT.CONDITION) ~= 0 then
			GameTooltip:AddLine("Has extra drop conditions (a quest, a class, reputation or an event).", 0.8, 0.8, 0.8, true)
		end
		if bit.band(d.flags, LOOT.HARD_MODE) ~= 0 then
			GameTooltip:AddLine("Hard mode only.", 1, 0.5, 0.2)
		end
		if bit.band(d.flags, LOOT.SHARED) ~= 0 then
			GameTooltip:AddLine("A shared world drop: many creatures can drop it.", 0.8, 0.8, 0.8, true)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function () GameTooltip:Hide() end)
	row:SetScript("OnClick", function (self)
		if not self.data then return end
		local link = ItemLink(self.data, self.link)
		if IsControlKeyDown() then
			if DressUpItemLink then DressUpItemLink(link) end
		elseif IsShiftKeyDown() and ChatEdit_InsertLink then
			ChatEdit_InsertLink(link)
		end
	end)
	return row
end

local function UpdateToggles()
	if not panel then return end
	for _, toggle in ipairs(panel.toggles) do
		local on = DB[toggle.key]
		toggle.text:SetTextColor(on and GOLD[1] or DIM[1], on and GOLD[2] or DIM[2], on and GOLD[3] or DIM[3])
		toggle:SetBackdropBorderColor(on and GOLD[1] or 0.22, on and GOLD[2] or 0.22, on and GOLD[3] or 0.22, 1)
	end
end

local Render

local function RenderRows()
	if not panel then return end
	local entry = panel.entry
	local loot = TL.Loot(entry)

	for i = 1, #rowPool do rowPool[i]:Hide() end
	for i = 1, #headerPool do headerPool[i]:Hide() end
	panel.empty:Hide()

	local rowUsed, headerUsed, y = 0, 0, 0

	local function header(text)
		headerUsed = headerUsed + 1
		local fs = headerPool[headerUsed]
		if not fs then
			fs = panel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			fs:SetJustifyH("LEFT")
			headerPool[headerUsed] = fs
		end
		fs:SetText(text)
		fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 2, -y)
		fs:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", -2, -y)
		fs:Show()
		y = y + HEADER_HEIGHT
	end

	local function row(data)
		rowUsed = rowUsed + 1
		local r = rowPool[rowUsed]
		if not r then
			r = NewRow()
			rowPool[rowUsed] = r
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
		r:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", 0, -y)
		SetupRow(r, data)
		r:Show()
		y = y + ROW_HEIGHT
	end

	if not loot then
		panel.empty:SetText(entry and "Asking the journal server..." or "Target a creature.")
		panel.empty:Show()
		panel.subtitle:SetText("mod-forever-journal")
	else
		local direct, shared = {}, {}
		for i = 1, #loot.rows do
			local d = loot.rows[i]
			if bit.band(d.flags, LOOT.SHARED) ~= 0 then
				shared[#shared + 1] = d
			elseif DB.showQuest or bit.band(d.flags, LOOT.QUEST) == 0 then
				direct[#direct + 1] = d
			end
		end

		if #direct > 0 then
			header("Drops from " .. (UnitName("target") or "this creature"))
			for i = 1, #direct do row(direct[i]) end
		end
		if DB.showShared and #shared > 0 then
			header("Shared world drops")
			for i = 1, #shared do row(shared[i]) end
		end

		if not DB.showShared then shared = {} end

		if rowUsed == 0 then
			panel.empty:SetText("This creature drops nothing the journal lists.")
			panel.empty:Show()
		end

		local total = #direct + #shared
		panel.subtitle:SetText(loot.lootId > 0
			and string.format("%d drop%s, %d shared  -  loot table %d", total, total == 1 and "" or "s", #shared, loot.lootId)
			or "no loot table")
	end

	panel.content:SetHeight(max(y, 1))
end

-- The window is never narrower than the creature's name: the title and the line under it are one
-- line each, so a narrower window would clip the name the window is about.
local function FitToContent()
	if not panel then return end
	local widest = max(panel.title:GetStringWidth() or 0, panel.subtitle:GetStringWidth() or 0)
	local wanted = min(MAX_WIDTH, max(MIN_WIDTH, widest + 52))
	panel:SetMinResize(wanted, MIN_HEIGHT)
	if panel:GetWidth() < wanted then panel:SetWidth(wanted) end
end

function Render()
	-- The title follows the target, not the moment the window opened.
	panel.title:SetText(UnitName("target") or "Target loot")
	RenderRows()
	UpdateToggles()
	FitToContent()
end

local function ToggleButton(parent, label, x, key, tip)
	local toggle = CreateFrame("Button", nil, parent)
	toggle:SetSize(66, 18)
	toggle:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -46)
	Skin(toggle, 0.9)
	toggle.key = key
	toggle.text = toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	toggle.text:SetPoint("CENTER")
	toggle.text:SetText(label)
	toggle:SetScript("OnClick", function ()
		DB[key] = not DB[key]
		Render()
		-- A row a filter brings back has to be in view, not above the old scroll offset.
		panel.scroll:SetVerticalScroll(0)
	end)
	toggle:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine(label, 1, 1, 1)
		GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function () GameTooltip:Hide() end)
	return toggle
end

local function CreatePanel()
	panel = CreateFrame("Frame", "TargetLootJournalFrame", UIParent)
	panel:SetSize(DB.width and max(DB.width, MIN_WIDTH) or PANEL_WIDTH,
		DB.height and max(DB.height, MIN_HEIGHT) or PANEL_HEIGHT)
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:SetResizable(true)
	panel:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
	panel:EnableMouse(true)
	Skin(panel, 0.96)
	panel:Hide()

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("TOPLEFT", 14, -12)
	panel.title:SetPoint("RIGHT", panel, "RIGHT", -34, 0)
	panel.title:SetJustifyH("LEFT")
	panel.title:SetTextColor(0.95, 0.95, 0.95)

	panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.subtitle:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3)
	panel.subtitle:SetPoint("RIGHT", panel, "RIGHT", -34, 0)
	panel.subtitle:SetJustifyH("LEFT")
	panel.subtitle:SetTextColor(DIM[1], DIM[2], DIM[3])

	-- The header (the creature's name and the line under it) is the drag handle, so it has to be a
	-- frame of its own: a font string takes no mouse, and the panel is covered by the scroll frame.
	panel.header = CreateFrame("Frame", nil, panel)
	panel.header:SetPoint("TOPLEFT")
	panel.header:SetPoint("TOPRIGHT")
	panel.header:SetHeight(44)
	panel.header:EnableMouse(true)
	panel.header:RegisterForDrag("LeftButton")
	panel.header:SetScript("OnDragStart", function () panel:StartMoving() end)
	panel.header:SetScript("OnDragStop", function ()
		panel:StopMovingOrSizing()
		local x, y = panel:GetCenter()
		if x and y then
			DB.point = { x = floor(x + 0.5), y = floor(y + 0.5) }
		end
	end)

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetFrameLevel(panel.header:GetFrameLevel() + 1)

	panel.toggles = {
		ToggleButton(panel, "World", 14, "showShared", "List the shared world drop tables this creature can also roll."),
		ToggleButton(panel, "Quest", 86, "showQuest", "List drops that only happen while you are on their quest."),
	}

	panel.divider = Flat(panel)
	panel.divider:SetHeight(1)
	panel.divider:SetVertexColor(0.26, 0.23, 0.17, 1)
	panel.divider:SetPoint("TOPLEFT", 12, -70)
	panel.divider:SetPoint("TOPRIGHT", -12, -70)

	panel.scroll = CreateFrame("ScrollFrame", "TargetLootJournalScroll", panel, "UIPanelScrollFrameTemplate")
	panel.scroll:SetPoint("TOPLEFT", 12, -76)
	panel.scroll:SetPoint("BOTTOMRIGHT", -28, 30)

	panel.content = CreateFrame("Frame", nil, panel.scroll)
	panel.content:SetWidth(ContentWidth())
	panel.content:SetHeight(1)
	panel.scroll:SetScrollChild(panel.content)
	panel.scroll:EnableMouseWheel(true)
	panel.scroll:SetScript("OnMouseWheel", function (self, delta)
		local limit = max(0, panel.content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(max(0, math.min((self:GetVerticalScroll() or 0) - delta * ROW_HEIGHT * 2, limit)))
	end)

	-- A resize re-points the list; the rows and the section headers are anchored to it, so they follow.
	panel:SetScript("OnSizeChanged", function (self)
		self.content:SetWidth(ContentWidth())
		-- The scroll offset can now be past the end of a taller window.
		local limit = max(0, self.content:GetHeight() - self.scroll:GetHeight())
		if (self.scroll:GetVerticalScroll() or 0) > limit then self.scroll:SetVerticalScroll(limit) end
	end)

	panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	panel.empty:SetPoint("TOPLEFT", panel.scroll, "TOPLEFT", 8, -16)
	panel.empty:SetPoint("TOPRIGHT", panel.scroll, "TOPRIGHT", -8, -16)
	panel.empty:SetJustifyH("CENTER")
	panel.empty:Hide()

	panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.footer:SetPoint("BOTTOMLEFT", 14, 10)
	panel.footer:SetText("Shift-click link  -  Ctrl-click preview  -  drag the header to move")

	-- The bottom-right corner resizes it, with the same grip the chat frame uses.
	panel.grip = CreateFrame("Button", nil, panel)
	panel.grip:SetSize(16, 16)
	panel.grip:SetPoint("BOTTOMRIGHT", -3, 3)
	panel.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	panel.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	panel.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	panel.grip:SetScript("OnMouseDown", function () panel:StartSizing("BOTTOMRIGHT") end)
	panel.grip:SetScript("OnMouseUp", function ()
		panel:StopMovingOrSizing()
		DB.width = floor(panel:GetWidth() + 0.5)
		DB.height = floor(panel:GetHeight() + 0.5)
	end)

	if DB.point then
		panel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", DB.point.x, DB.point.y)
	else
		panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -280, -180)
	end

	table.insert(UISpecialFrames, "TargetLootJournalFrame")
end

-----------------------------------------
-- showing it

function TL.Show(entry)
	if not panel then return end
	panel.entry = entry or currentEntry
	panel.title:SetText(UnitName("target") or "Target loot")
	panel:Show()
	if panel.entry then TL.Ensure(panel.entry) end
	Render()
end

function TL.Toggle()
	if not panel then return end
	if panel:IsShown() and panel.entry == currentEntry then
		panel:Hide()
	else
		TL.Show(currentEntry)
	end
end

function TL.ResetPosition()
	DB.point, DB.width, DB.height = nil, nil, nil
	if panel then
		panel:ClearAllPoints()
		panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -280, -180)
		panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
		FitToContent()
	end
end

local function UpdateTarget()
	currentEntry = TL.TargetEntry()
	if not currentEntry then
		if button then button:Hide() end
		if panel then panel:Hide() end
		return
	end
	TL.Ensure(currentEntry)
	UpdateButton()
	if panel and panel:IsShown() then
		panel.entry = currentEntry
		Render()
	end
end

-----------------------------------------
-- wiring

TL.On("LOADED", function ()
	CreateButton()
	CreatePanel()
	UpdateTarget()
end)

TL.On("TARGET", UpdateTarget)

TL.On("LOOT", function (entry)
	if entry == currentEntry then UpdateButton() end
	if panel and panel:IsShown() and panel.entry == entry then Render() end
end)

TL.On("ITEMS", function ()
	if panel and panel:IsShown() then Render() end
end)

TL.On("FAILED", function (entry, why)
	if panel and panel:IsShown() and panel.entry == entry then
		panel.empty:SetText("The journal server did not answer" .. (why and (" (" .. why .. ")") or "")
			.. ". If the journal module was only just patched, rebuild the server and it will.")
		panel.empty:Show()
	end
end)

TL.On("TOGGLE", function () TL.Toggle() end)
TL.On("RESET", function ()
	TL.ResetPosition()
	TL.Print("window position reset.")
end)
