-- Target Loot (Journal): what the creature you have targeted drops, from the realm's own loot
-- tables. The data comes from the mod-forever-journal server module over the JNL addon-whisper
-- protocol its Journal addon already uses:
--
--   client:  TL:<request>:<creature entry>
--   server:  TLR:<request>:<entry>:<loot id>:<rows>, TLD:<request>:<rows...>, TLE:<request>
--   row:     item,chance x100,flags,min,max,quality,class,subclass,inv type,item level,
--            required level,name,classes,loot id
--
-- Request ids start with "tl" and the answers are three-letter codes, so a Journal addon running
-- beside this one can never mistake them for its own requests (its ids are bare numbers and its
-- list codes are two letters). No HELLO is sent: that would replace the Journal addon's feature
-- flags, and the module answers without one.
--
-- 3.3.5a only: no Settings API, no C_Timer, no BackdropTemplate, no craftable colour textures.

local addonName, TL = ...
TL.name = addonName or "TargetLootJournal"
TL.PREFIX = "JNL"

TargetLootJournalDB = TargetLootJournalDB or {}
local DB = TargetLootJournalDB
for key, value in pairs({ showShared = true, showQuest = true }) do
	if DB[key] == nil then DB[key] = value end
end
TL.DB = DB

local floor = math.floor

-- Loot flags, as src/Journal.h sends them.
TL.LOOT = { QUEST = 1, HARD_MODE = 2, CONDITION = 4, CHEST = 8, BOP = 16, SHARED = 32, TOKEN = 64 }

-- Loot tables change only with a restart, and the button hides the wait either way.
local CACHE_SECONDS = 900
TL.cache = {}

-----------------------------------------
-- event bus

local listeners = {}

function TL.On(event, fn)
	listeners[event] = listeners[event] or {}
	local list = listeners[event]
	list[#list + 1] = fn
end

function TL.Fire(event, ...)
	local list = listeners[event]
	if not list then return end
	for i = 1, #list do list[i](...) end
end

function TL.Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cffd7b15bTarget Loot:|r " .. tostring(message))
end

-----------------------------------------
-- timers (3.3.5a has no C_Timer)

local timers = {}
local timerFrame = CreateFrame("Frame")

timerFrame:SetScript("OnUpdate", function (self)
	local now = GetTime()
	for i = #timers, 1, -1 do
		if timers[i].at <= now then
			local entry = table.remove(timers, i)
			entry.fn()
		end
	end
	if #timers == 0 then self:Hide() end
end)

function TL.After(delay, fn)
	timers[#timers + 1] = { at = GetTime() + delay, fn = fn }
	timerFrame:Show()
end

-----------------------------------------
-- the target

function TL.TargetEntry()
	local guid = UnitGUID("target")
	if not guid then return nil end
	-- 3.3.5a sends a plain hex GUID ("0xF130003039000001"), not the "Creature-0-0-..." form that
	-- arrived with 4.0. The core reads the entry as (guid >> 24) & 0xFFFFFF, which is the 6 hex
	-- digits before the last six: "F130" is a creature, the entry sits in the middle. A player or
	-- item GUID has no entry there, so it comes out as 0 and is not a creature.
	local kind, _, _, _, _, entry = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then return tonumber(entry) end
	if not guid:find("^0x%x+$") then return nil end
	entry = tonumber(guid:sub(-12, -7), 16)
	if not entry or entry == 0 then return nil end
	return entry
end

-----------------------------------------
-- asking the server

local serial = 0
local pending = {}

local function send(payload)
	SendAddonMessage(TL.PREFIX, payload, "WHISPER", UnitName("player"))
end

function TL.Request(entry)
	for req, p in pairs(pending) do
		if p.entry == entry then return req end
	end
	serial = serial + 1
	local req = "tl" .. serial
	pending[req] = { entry = entry, at = GetTime(), tries = 0 }
	send("TL:" .. req .. ":" .. tostring(entry))
	return req
end

-- A request the server never answered (a reload, a lost whisper) is asked again twice, then
-- given up on.
local sweep = CreateFrame("Frame")
local sweepElapsed = 0

sweep:SetScript("OnUpdate", function (self, elapsed)
	if not next(pending) then return end
	sweepElapsed = sweepElapsed + elapsed
	if sweepElapsed < 1 then return end
	sweepElapsed = 0
	local now = GetTime()
	for req, p in pairs(pending) do
		if now - p.at > 4 then
			if p.tries < 2 then
				p.tries = p.tries + 1
				p.at = now
				send("TL:" .. req .. ":" .. tostring(p.entry))
			else
				pending[req] = nil
				TL.Fire("FAILED", p.entry)
			end
		end
	end
end)

-----------------------------------------
-- reading the answers

local function splitFields(text)
	local out = {}
	if not text or text == "" then return out end
	for field in (text .. ":"):gmatch("([^:]*):") do out[#out + 1] = field end
	return out
end

function TL.Unescape(text)
	if type(text) ~= "string" then return text end
	if text == "-" then return "" end
	return (text:gsub("%%(%x%x)", function (hex) return string.char(tonumber(hex, 16)) end))
end

local function parseRow(text)
	local f = {}
	for value in text:gmatch("[^,]+") do f[#f + 1] = value end
	return {
		item = tonumber(f[1]) or 0,
		chance = tonumber(f[2]) or 0,
		flags = tonumber(f[3]) or 0,
		min = tonumber(f[4]) or 1,
		max = tonumber(f[5]) or 1,
		quality = tonumber(f[6]) or 1,
		class = tonumber(f[7]) or 0,
		subclass = tonumber(f[8]) or 0,
		invType = tonumber(f[9]) or 0,
		ilvl = tonumber(f[10]) or 0,
		reqLevel = tonumber(f[11]) or 0,
		name = TL.Unescape(f[12] or ""),
		classes = tonumber(f[13]) or 0,
		lootId = tonumber(f[14]) or 0,
	}
end

local function onMessage(message)
	local code, req, rest = message:match("^(%u+):([^:]*):?(.*)$")
	if not code then return end

	local p = pending[req]

	if code == "TLR" then
		if not p then return end
		local fields = splitFields(rest)
		p.at = GetTime()
		-- rest is "<entry>:<loot id>:<rows>": the request id was split off with the code.
		p.part = { lootId = tonumber(fields[2]) or 0, rows = {} }
	elseif code == "TLD" then
		if not p or not p.part then return end
		for row in rest:gmatch("[^;]+") do
			p.part.rows[#p.part.rows + 1] = parseRow(row)
		end
	elseif code == "TLE" then
		if not p or not p.part then return end
		pending[req] = nil
		TL.cache[p.entry] = { rows = p.part.rows, lootId = p.part.lootId, at = GetTime() }
		TL.Fire("LOOT", p.entry, TL.cache[p.entry])
	elseif code == "ERR" then
		-- The module's own refusals (busy, bad). Without it, this waits for the sweep.
		if not p then return end
		pending[req] = nil
		TL.Fire("FAILED", p.entry, rest)
	end
end

-----------------------------------------
-- the cache the window reads

function TL.Loot(entry)
	local cached = entry and TL.cache[entry]
	if not cached then return nil end
	if GetTime() - cached.at > CACHE_SECONDS then
		TL.cache[entry] = nil
		return nil
	end
	return cached
end

-- The cached answer, asking the server when there is none yet. nil means "not here yet".
function TL.Ensure(entry)
	if not entry then return nil end
	local cached = TL.Loot(entry)
	if cached then return cached end
	TL.Request(entry)
	return nil
end

function TL.Forget(entry)
	if entry then
		TL.cache[entry] = nil
	else
		TL.cache = {}
	end
end

-----------------------------------------
-- client item data: names, icons and links

-- The server sends the name out of item_template, which is English on a German client, and the
-- icon only comes from the client's own cache. An item the character has never seen is not in
-- that cache, so the row shows the server name and a "?" until the client is asked for the item
-- and answers. 3.3.5a does not reliably fire GET_ITEM_INFO_RECEIVED for items asked for through
-- a hidden tooltip, so this polls the cache the way the Journal addon does.
local scan = CreateFrame("GameTooltip", "TargetLootJournalScan", nil, "GameTooltipTemplate")
scan:SetOwner(WorldFrame, "ANCHOR_NONE")

local waiting, waitingCount = {}, 0

function TL.QueryItem(item)
	if not item or item == 0 or GetItemInfo(item) then return end
	if waiting[item] then return end
	waiting[item] = GetTime()
	waitingCount = waitingCount + 1
	scan:ClearLines()
	scan:SetHyperlink("item:" .. item)
end

local pollFrame = CreateFrame("Frame")
local pollElapsed = 0
pollFrame:SetScript("OnUpdate", function (self, elapsed)
	if waitingCount == 0 then return end
	pollElapsed = pollElapsed + elapsed
	if pollElapsed < 0.2 then return end
	pollElapsed = 0
	local now, arrived = GetTime(), false
	for item, since in pairs(waiting) do
		if GetItemInfo(item) then
			waiting[item] = nil
			waitingCount = waitingCount - 1
			arrived = true
		elseif now - since > 20 then
			-- An item the realm does not have: stop asking, keep the server name.
			waiting[item] = nil
			waitingCount = waitingCount - 1
		end
	end
	if arrived then TL.Fire("ITEMS") end
end)

-----------------------------------------
-- events and commands

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")

events:SetScript("OnEvent", function (self, event, ...)
	if event == "ADDON_LOADED" then
		if ... == TL.name then
			-- 3.3.5 has it; a client that doesn't keeps working, the module just may not answer.
			if RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, TL.PREFIX) end
			TL.Fire("LOADED")
		end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, message, _, sender = ...
		if prefix == TL.PREFIX and sender == UnitName("player") then onMessage(message) end
	elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		TL.Fire("TARGET")
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		TL.Fire("ITEMS")
	end
end)

SLASH_TARGETLOOTJOURNAL1 = "/tloot"
SLASH_TARGETLOOTJOURNAL2 = "/tjloot"
SlashCmdList.TARGETLOOTJOURNAL = function (msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "id" then
		local entry = TL.TargetEntry()
		TL.Print(entry and ("target creature is " .. entry) or "no creature targeted.")
	elseif msg == "refresh" then
		TL.Forget(nil)
		TL.Print("loot will be asked for again.")
		TL.Fire("TARGET")
	elseif msg == "reset" then
		TL.Fire("RESET")
	else
		TL.Fire("TOGGLE")
	end
end
