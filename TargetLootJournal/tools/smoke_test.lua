-- Smoke test for Target Loot (Journal) outside the game: stubs enough of the 3.3.5a API to load
-- Core.lua and Panel.lua in .toc order, then plays a target and a mod-forever-journal server.
--
--   lua5.1 tools/smoke_test.lua
--
-- It fails on: a Lua error, an API method the client does not actually have (anything the stub had
-- to invent is reported), a wrong request, a row that does not parse, and filters that do not
-- filter.

local dir = arg[1] or "."

local checks, failures = 0, 0
local function check(name, ok, detail)
	checks = checks + 1
	if ok then
		print("  ok   " .. name)
	else
		failures = failures + 1
		print("  FAIL " .. name .. (detail and ("  -> " .. tostring(detail)) or ""))
	end
end

local function eq(name, got, want)
	check(name, got == want, string.format("got %s, want %s", tostring(got), tostring(want)))
end

-----------------------------------------
-- 3.3.5a stubs

local now = 100
function GetTime() return now end

function strsplit(sep, text)
	local out = {}
	for field in (tostring(text) .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do
		out[#out + 1] = field
	end
	return unpack(out)
end

bit = {}
function bit.band(a, b)
	local result, bitValue = 0, 1
	a, b = math.floor(a), math.floor(b)
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then result = result + bitValue end
		a, b, bitValue = math.floor(a / 2), math.floor(b / 2), bitValue * 2
	end
	return result
end

local playerName, targetGUID, targetName = "Tester", nil, nil
function UnitName(unit)
	if unit == "player" then return playerName end
	if unit == "target" then return targetName end
end
function UnitGUID(unit) if unit == "target" then return targetGUID end end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function RegisterAddonMessagePrefix() return true end

DEFAULT_CHAT_FRAME = { AddMessage = function (_, message) print("      [chat] " .. tostring(message)) end }
UISpecialFrames = {}
SlashCmdList = {}
ITEM_QUALITY_COLORS = {
	[0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 },
	[2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
	[4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 },
}

local items = {
	[100] = { "Epic Helm", "|cffa335ee|Hitem:100|h[Epic Helm]|h|r", 4, 200, 80, 4, 1, 1, "INVTYPE_HEAD", "Interface\\Icons\\inv_helm" },
	[200] = { "Quest Trinket", "|cff1eff00|Hitem:200|h[Quest Trinket]|h|r", 2, 1, 1, 12, 0, 0, "", "Interface\\Icons\\inv_trinket" },
	[300] = { "Shared Drop", "|cff1eff00|Hitem:300|h[Shared Drop]|h|r", 2, 1, 1, 15, 0, 0, "", "Interface\\Icons\\inv_misc" },
}
function GetItemInfo(item)
	-- The client takes both a number and an "item:<n>" key.
	if type(item) == "string" then
		item = tonumber(item:match("^item:(%d+)$")) or item
	end
	local row = items[item]
	if not row then return nil end
	return row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10]
end

local objects = {}
local invented = {}

local newObject
local methods = {}
methods.SetScript = function (self, event, fn) self.__scripts[event] = fn end
methods.CreateTexture = function (self, name, layer) return newObject("Texture", name, self) end
methods.CreateFontString = function (self, name, layer, template) return newObject("FontString", name, self) end
methods.GetScript = function (self, event) return self.__scripts[event] end
methods.HookScript = function (self, event, fn)
	local old = self.__scripts[event]
	self.__scripts[event] = function (...) if old then old(...) end fn(...) end
end
methods.Show = function (self)
	local was = self.__shown
	self.__shown = true
	if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
methods.Hide = function (self)
	local was = self.__shown
	self.__shown = false
	if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
methods.IsShown = function (self) return self.__shown end
methods.SetPoint = function (self) self.__points = (self.__points or 0) + 1 end
methods.ClearAllPoints = function (self) self.__points = 0 end
methods.SetAllPoints = function () end
methods.SetSize = function (self, w, h) self.__width, self.__height = w, h end
methods.SetWidth = function (self, w) self.__width = w end
methods.SetHeight = function (self, h) self.__height = h end
methods.GetWidth = function (self) return self.__width or 100 end
methods.GetHeight = function (self) return self.__height or 20 end
methods.GetCenter = function (self) return 640, 360 end
methods.SetText = function (self, text) self.__text = text and tostring(text) or "" end
methods.GetText = function (self) return self.__text end
methods.SetBackdrop = function (self, backdrop) self.__backdrop = backdrop end
methods.GetName = function (self) return self.__name end
methods.IsOwned = function (self, owner) return self.__owner == owner end
methods.SetOwner = function (self, owner) self.__owner = owner self.__lines = {} end
methods.ClearLines = function (self) self.__lines = {} end
methods.AddLine = function (self, text) table.insert(self.__lines, tostring(text)) end
methods.AddDoubleLine = function (self, left, right)
	table.insert(self.__lines, tostring(left) .. ": " .. tostring(right))
end
methods.SetHyperlink = function (self, link) self.__link = link end
methods.GetFrameLevel = function (self) return rawget(self, "__level") or 1 end
methods.SetFrameLevel = function (self, level) rawset(self, "__level", level) end
methods.StartMoving = function () end
methods.StopMovingOrSizing = function () end
methods.SetScrollChild = function (self, child) self.__child = child end
methods.EnableMouseWheel = function () end
methods.SetVerticalScroll = function (self, value) self.__scroll = value end
methods.GetVerticalScroll = function (self) return self.__scroll or 0 end
methods.RegisterEvent = function (self, event)
	local events = rawget(self, "__events") or {}
	events[event] = true
	rawset(self, "__events", events)
end

-- Everything else the addon uses that has no visible effect outside the game.
methods.SetTexture = function (self, texture) rawset(self, "__texture", texture) end

for _, name in ipairs({
	"SetTexCoord", "SetVertexColor", "SetBlendMode", "SetDesaturated", "SetTextColor",
	"SetJustifyH", "SetWordWrap", "SetBackdropColor", "SetBackdropBorderColor", "RegisterForClicks",
	"EnableMouse", "SetFrameStrata", "SetToplevel", "SetClampedToScreen", "SetMovable", "SetScrollChild",
}) do
	methods[name] = methods[name] or function () end
end

newObject = function (kind, name, parent)
	local object = {
		__kind = kind, __name = name, __parent = parent, __scripts = {}, __shown = true,
		__width = 100, __height = 20, __text = "",
	}
	setmetatable(object, {
		__index = function (self, key)
			if methods[key] then return methods[key] end
			-- Fields (__shown, __points, ...) are nil until set, even when unset: never a method.
			if key:sub(1, 2) == "__" then return nil end
			invented[key] = kind
			return function () end
		end,
	})
	if name then _G[name] = object end
	table.insert(objects, object)
	return object
end

function CreateFrame(kind, name, parent)
	return newObject(kind, name, parent)
end

UIParent = newObject("Frame", "UIParent")
WorldFrame = newObject("Frame", "WorldFrame")
TargetFrame = newObject("Frame", "TargetFrame")
GameTooltip = newObject("GameTooltip", "GameTooltip")

-----------------------------------------
-- the addon message channel

local sent = {}
function SendAddonMessage(prefix, message, channel, target)
	table.insert(sent, { prefix = prefix, message = message, channel = channel, target = target })
end

local frames = {}
local realCreateFrame = CreateFrame
CreateFrame = function (kind, name, parent, template)
	local frame = realCreateFrame(kind, name, parent, template)
	frame.__template = template
	if kind == "Frame" and not name then table.insert(frames, frame) end
	if kind == "Frame" and name == "TargetLootJournalFrame" then table.insert(frames, frame) end
	return frame
end

local function fire(event, ...)
	for _, frame in ipairs(frames) do
		local script = frame.__scripts and frame.__scripts.OnEvent
		if script and frame.__events and frame.__events[event] then script(frame, event, ...) end
	end
end

-----------------------------------------
-- load the addon

print("loading " .. dir)
local addon = {}
local function load(name)
	local chunk, err = loadfile(dir .. "/" .. name)
	if not chunk then error(name .. ": " .. err) end
	-- The client hands every file of one addon (addon name, its private table).
	chunk("TargetLootJournal", addon)
end
load("Core.lua")
load("Panel.lua")
TL = addon

print("first run")
fire("ADDON_LOADED", "TargetLootJournal")

-----------------------------------------
-- play a target

print("targeting creature 12345")
targetGUID, targetName = "0xF130003039000001", "Test Mob"   -- a 3.3.5a creature GUID, entry 12345
fire("PLAYER_TARGET_CHANGED")

local last = sent[#sent]
check("a request went out", last ~= nil, "nothing was sent")
eq("request prefix", last and last.prefix, "JNL")
eq("request", last and last.message, "TL:tl1:12345")
eq("whispered to yourself", last and last.target, playerName)

do
	local saved = targetGUID
	targetGUID = "0x0000000000000007"            -- a player: no entry in the GUID
	check("a player GUID is not a creature", TL.TargetEntry() == nil)
	targetGUID = "Creature-0-0-0-0-12345-0000123456"   -- the 4.x+ form, for a patched core
	eq("4.x-style GUID still parses", TL.TargetEntry(), 12345)
	targetGUID = saved
end

local hello = false
for _, message in ipairs(sent) do
	if message.message:match("^HELLO") then hello = true end
end
check("no HELLO (it would wipe the Journal addon's features)", not hello)

print("answering with three rows")
local function reply(code)
	local message = code
	local prefix, rest = message:match("^(%u+):(.*)$")
	fire("CHAT_MSG_ADDON", "JNL", message, "WHISPER", playerName)
end

reply("TLR:tl1:12345:12345:3")
reply("TLD:tl1:100,1500,0,1,1,4,4,1,1,200,80,Epic%20Helm,0,12345;"
	.. "200,500,1,1,1,2,12,0,0,1,1,Quest%20Trinket,0,12345;"
	.. "300,200,32,1,2,2,15,0,0,1,1,Shared%20Drop,0,12345")
reply("TLE:tl1")

local loot = TL and TL.Loot(12345)
check("answer cached for the entry", loot ~= nil)
eq("row count", loot and #loot.rows, 3)
eq("loot id read from TLR", loot and loot.lootId, 12345)
eq("first item", loot and loot.rows[1].item, 100)
eq("chance x100 parsed", loot and loot.rows[1].chance, 1500)
eq("flags parsed (quest row)", loot and loot.rows[2].flags, 1)
eq("shared flag parsed", loot and loot.rows[3].flags, 32)
eq("escaped name unescaped", loot and loot.rows[1].name, "Epic Helm")
eq("min/max count", loot and loot.rows[3].max, 2)

local button = _G.TargetLootJournalButton
check("button shows for the target", button and button:IsShown())
eq("button badge", button and button.count:GetText(), "3")

-----------------------------------------
-- the window

local panel = _G.TargetLootJournalFrame
check("window was created", panel ~= nil)

TL.Toggle()
check("window opens", panel:IsShown())

local function visibleRows()
	local count = 0
	for _, object in ipairs(objects) do
		if object.__kind == "Button" and object.__parent == panel.content and object:IsShown() then
			count = count + 1
		end
	end
	return count
end

local function headers()
	local out = {}
	for _, object in ipairs(objects) do
		if object.__kind == "FontString" and object.__parent == panel.content and object:IsShown() and object:GetText() ~= "" then
			table.insert(out, object:GetText())
		end
	end
	return out
end

eq("rows drawn", visibleRows(), 3)
local drawn = headers()
check("two sections", #drawn == 2, table.concat(drawn, " | "))
check("first section names the creature", drawn[1] and drawn[1]:find("Test Mob") ~= nil, drawn[1])
eq("second section", drawn[2], "Shared world drops")

print("filters")
panel.toggles[2]:GetScript("OnClick")()      -- quest
eq("quest rows hidden", visibleRows(), 2)
panel.toggles[1]:GetScript("OnClick")()      -- world
eq("shared rows hidden", visibleRows(), 1)
panel.toggles[1]:GetScript("OnClick")()
panel.toggles[2]:GetScript("OnClick")()
eq("all rows back", visibleRows(), 3)

print("tooltip on a row")
local row
for _, object in ipairs(objects) do
	if object.__kind == "Button" and object.__parent == panel.content and object.data then row = row or object end
end
check("a row holds its drop", row and row.data and row.data.item == 100)
row:GetScript("OnEnter")(row)
local tooltip = table.concat(GameTooltip.__lines or {}, " / ")
check("tooltip has the drop chance", tooltip:find("15%%") ~= nil, tooltip)
row:GetScript("OnLeave")(row)

-----------------------------------------
-- bad answers, other addons' traffic, and a lost request

print("noise and failures")
reply("TLD:tl1:1,2,3")                       -- a stray row, no request
reply("DR:1:2")                              -- the Journal addon's own answer
reply("TLR:tl9:1:1:1")                       -- an answer to a request we never made
check("stray traffic is ignored", TL.Loot(12345) and #TL.Loot(12345).rows == 3)

fire("PLAYER_TARGET_CHANGED")                -- same target: no new request
local requests = 0
for _, message in ipairs(sent) do
	if message.message:match("^TL:") then requests = requests + 1 end
end
eq("cached target is not asked again", requests, 1)

targetGUID, targetName = "0xF130000063000001", "Lootless Mob"   -- entry 99
fire("PLAYER_TARGET_CHANGED")
last = sent[#sent]
eq("new target asks for its entry", last.message, "TL:tl2:99")
reply("TLR:tl2:99:99:0")
reply("TLE:tl2")
TL.Toggle()
eq("empty answer says so", visibleRows(), 0)
check("empty text shown", panel.empty:IsShown())

print("a request the server refuses")
targetGUID, targetName = "0xF130000037000001", "Test Mob"   -- entry 55
fire("PLAYER_TARGET_CHANGED")
TL.Toggle()
last = sent[#sent]
eq("refused request goes out", last.message, "TL:tl3:55")
reply("ERR:tl3:bad")
check("refusal is shown", panel.empty:IsShown())
check("refusal says to rebuild", panel.empty:GetText():find("rebuild") ~= nil, panel.empty:GetText())

targetGUID, targetName = nil, nil
fire("PLAYER_TARGET_CHANGED")
check("button hides without a target", not _G.TargetLootJournalButton:IsShown())
check("window hides without a target", not panel:IsShown())

-----------------------------------------
-- regression: an answer whose items the client has never seen (the first open)
--
-- The first open showed the server's English names and "?" icons and never refreshed when the
-- client cached the items; and the quest row had to come back when its filter was turned off
-- and on again.

print("31 rows, none of the items cached yet")
items = {}
targetGUID, targetName = "0xF1300007C0000001", "Test Boar"   -- entry 1984
fire("PLAYER_TARGET_CHANGED")

local many = "100,4700,0,1,1,1,15,0,0,1,1,Server%20Name%20One,0,1984;"
	.. "101,4700,0,1,1,2,15,0,0,1,1,Server%20Name%20Two,0,1984;"
	.. "117,2500,1,1,1,1,15,0,0,1,1,Tough%20Jerky,0,1984"
for i = 1, 28 do
	many = many .. ";" .. string.format("%d,87,32,1,1,2,4,2,5,20,10,Shared%%20%d,0,1984", 200 + i, i)
end
last = sent[#sent]
eq("request for the new target", last.message, "TL:tl4:1984")
reply("TLR:tl4:1984:1984:31")
reply("TLD:tl4:" .. many)
reply("TLE:tl4")

TL.Toggle()
eq("all 31 rows drawn", visibleRows(), 31)

local function rowFor(item)
	for _, object in ipairs(objects) do
		if object.__kind == "Button" and object.__parent == panel.content and object:IsShown()
			and object.data and object.data.item == item then
			return object
		end
	end
end

check("the quest row is drawn", rowFor(117) ~= nil)
eq("server name shown while the item is uncached", rowFor(100) and rowFor(100).name:GetText(), "Server Name One")
eq("fallback icon while the item is uncached", rowFor(100) and rowFor(100).icon.__texture,
	"Interface\\Icons\\INV_Misc_QuestionMark")

print("the client caches two of them")
items[100] = { "Verdorbener Pelz", "|cffa335ee|Hitem:100|h[Verdorbener Pelz]|h|r", 4, 200, 80, 4, 1, 1, "INVTYPE_HEAD", "Interface\\Icons\\local_helm" }
items[117] = { "Zähes Stockfleisch", "|cff1eff00|Hitem:117|h[Zähes Stockfleisch]|h|r", 2, 1, 1, 12, 0, 0, "", "Interface\\Icons\\local_jerky" }
now = now + 1
for _, object in ipairs(objects) do
	if object.__scripts.OnUpdate then object.__scripts.OnUpdate(object, 0.25) end
end
eq("localized name replaces the server one", rowFor(100).name:GetText(), "Verdorbener Pelz")
eq("icon follows the cache", rowFor(100).icon.__texture, "Interface\\Icons\\local_helm")

print("filters again")
panel.toggles[2]:GetScript("OnClick")()
eq("quest row hidden", visibleRows(), 30)
panel.toggles[2]:GetScript("OnClick")()
eq("quest row comes back", visibleRows(), 31)
check("the quest row is really there", rowFor(117) ~= nil)

-----------------------------------------
-- API usage

local names = {}
for name, kind in pairs(invented) do names[#names + 1] = name .. " (" .. kind .. ")" end
table.sort(names)
check("no invented 3.3.5a methods were needed", #names == 0, #names > 0 and table.concat(names, ", ") or nil)

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
