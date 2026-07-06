-- StitchLogger Skinning post-processor
-- Patches a timing edge case where WoW can fire LOOT_CLOSED before CHAT_MSG_LOOT.
-- If a skinning loot message arrives just after an empty skinning_completed event,
-- this module attaches the loot to that completed event and logs a small correction event.

local frame = CreateFrame("Frame")
local ATTACH_WINDOW_SECONDS = 3

local function nowUtc()
  local t = (GetServerTime and GetServerTime()) or time()
  return date("!%Y-%m-%dT%H:%M:%SZ", t)
end

local function ensureDB()
  StitchLoggerDB = StitchLoggerDB or {}
  StitchLoggerDB.sessions = StitchLoggerDB.sessions or {}
  StitchLoggerDB.counters = StitchLoggerDB.counters or { nextSession = 1, nextEvent = 1 }
  return StitchLoggerDB
end

local function currentSession()
  local db = ensureDB()
  if not db.currentSessionId then return nil end
  for _, session in ipairs(db.sessions) do
    if session.sessionId == db.currentSessionId then return session end
  end
  return nil
end

local function nextEventId()
  local db = ensureDB()
  local n = db.counters.nextEvent or 1
  db.counters.nextEvent = n + 1
  return "sl-" .. string.format("%06d", n)
end

local function itemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  local itemString = link:match("item:([%-?%d:]+)")
  if not itemString then return nil end
  local id = itemString:match("^(%-?%d+)")
  return tonumber(id)
end

local function itemSnapshot(link, count)
  local item = { raw = link, quantity = count or 1, link = link, itemId = itemIDFromLink(link) }
  local name, itemLink, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, icon, sellPrice, classID, subclassID, bindType = GetItemInfo(link)
  item.name = name or link
  item.link = itemLink or link
  item.quality = quality
  item.itemLevel = itemLevel
  item.minLevel = minLevel
  item.itemType = itemType
  item.itemSubType = itemSubType
  item.stackCount = stackCount
  item.equipLoc = equipLoc
  item.icon = icon
  item.vendorValueCopper = sellPrice
  item.classID = classID
  item.subclassID = subclassID
  item.bindType = bindType
  return item
end

local function extractLootItems(message)
  local items = {}
  for link in tostring(message):gmatch("|c%x+|Hitem:.-|h%[.-%]|h|r") do
    table.insert(items, itemSnapshot(link, 1))
  end
  return items
end

local function findRecentEmptySkinningCompleted(session)
  if not session or not session.events then return nil end
  local now = time()
  for i = #session.events, 1, -1 do
    local event = session.events[i]
    if type(event) == "table" then
      local age = now - (event.timeSeconds or 0)
      if age > ATTACH_WINDOW_SECONDS then return nil end
      if event.eventType == "skinning_completed" then
        local loot = event.skinningLoot or {}
        if #loot == 0 then return event end
      end
    end
  end
  return nil
end

local function logCorrection(session, completedEvent, items, rawMessage)
  if not session then return end
  local event = {
    eventId = nextEventId(),
    eventType = "skinning_loot_attached_after_close",
    timestamp = nowUtc(),
    timeSeconds = time(),
    character = UnitName("player"),
    characterLevel = UnitLevel("player"),
    source = "addon",
    module = "SkinningPostProcessor.lua",
    confidence = "medium",
    rawMessage = rawMessage,
    attachedToEventId = completedEvent and completedEvent.eventId or nil,
    items = items,
    notes = "Attached loot to a recent empty skinning_completed event because CHAT_MSG_LOOT arrived after LOOT_CLOSED."
  }
  table.insert(session.events, event)
end

frame:RegisterEvent("CHAT_MSG_LOOT")
frame:SetScript("OnEvent", function(self, event, ...)
  if event ~= "CHAT_MSG_LOOT" then return end
  local message = ...
  local items = extractLootItems(message)
  if #items == 0 then return end

  local session = currentSession()
  local completed = findRecentEmptySkinningCompleted(session)
  if not completed then return end

  completed.skinningLoot = items
  completed.skinningLootAttachedAfterClose = true
  completed.skinningLootAttachReason = "CHAT_MSG_LOOT arrived after LOOT_CLOSED"
  completed.skinningLootAttachTimestamp = nowUtc()

  logCorrection(session, completed, items, message)
end)
