-- StitchLogger Tooltip module
-- Captures visible tooltip text for item links when available.
-- This is the closest addon-side source to "what the player sees" on item tooltips.

local frame = CreateFrame("Frame")
local tooltipName = "StitchLoggerHiddenTooltip"
local tooltip = CreateFrame("GameTooltip", tooltipName, UIParent, "GameTooltipTemplate")
tooltip:SetOwner(UIParent, "ANCHOR_NONE")

local function nowUtc()
  local t = (GetServerTime and GetServerTime()) or time()
  return date("!%Y-%m-%dT%H:%M:%SZ", t)
end

local function round2(n)
  if not n then return nil end
  return math.floor(n * 100 + 0.5) / 100
end

local function getCoords()
  if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return nil end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return nil end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return { mapID = mapID } end
  return { mapID = mapID, x = round2(pos.x * 100), y = round2(pos.y * 100) }
end

local function unitSnapshot(unit)
  if not UnitExists(unit) then return nil end
  return {
    name = UnitName(unit),
    guid = UnitGUID(unit),
    level = UnitLevel(unit),
    creatureType = UnitCreatureType(unit),
    classification = UnitClassification(unit),
  }
end

local function ensureDB()
  StitchLoggerDB = StitchLoggerDB or {}
  StitchLoggerDB.version = StitchLoggerDB.version or 1
  StitchLoggerDB.addonVersion = StitchLoggerDB.addonVersion or "0.1.0"
  StitchLoggerDB.sessions = StitchLoggerDB.sessions or {}
  StitchLoggerDB.counters = StitchLoggerDB.counters or { nextSession = 1, nextEvent = 1 }
  return StitchLoggerDB
end

local function currentSession()
  local db = ensureDB()
  if db.currentSessionId then
    for _, session in ipairs(db.sessions) do
      if session.sessionId == db.currentSessionId then return session end
    end
  end

  local n = db.counters.nextSession or 1
  db.counters.nextSession = n + 1
  local session = {
    sessionId = date("%Y-%m-%d") .. "-" .. string.format("%03d", n),
    startedAt = nowUtc(),
    reason = "auto_tooltip_event",
    character = { name = UnitName("player"), level = UnitLevel("player"), realm = GetRealmName and GetRealmName() or nil },
    events = {},
  }
  table.insert(db.sessions, session)
  db.currentSessionId = session.sessionId
  return session
end

local function nextEventId()
  local db = ensureDB()
  local n = db.counters.nextEvent or 1
  db.counters.nextEvent = n + 1
  return "sl-" .. string.format("%06d", n)
end

local function logTooltipEvent(eventType, payload)
  local session = currentSession()
  payload = payload or {}
  local event = {
    eventId = nextEventId(),
    eventType = eventType,
    timestamp = nowUtc(),
    timeSeconds = time(),
    character = UnitName("player"),
    characterLevel = UnitLevel("player"),
    zone = GetZoneText and GetZoneText() or nil,
    subZone = GetSubZoneText and GetSubZoneText() or nil,
    coords = getCoords(),
    source = "addon",
    module = "Tooltip.lua",
    confidence = payload.confidence or "high",
  }
  payload.confidence = nil
  for k, v in pairs(payload) do event[k] = v end
  table.insert(session.events, event)
  return event
end

local function itemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  local itemString = link:match("item:([%-?%d:]+)")
  if not itemString then return nil end
  local id = itemString:match("^(%-?%d+)")
  return tonumber(id)
end

local function basicItemSnapshot(linkOrName, count)
  local item = {
    raw = linkOrName,
    quantity = count or 1,
  }

  if type(linkOrName) == "string" then
    item.link = linkOrName:find("|Hitem:") and linkOrName or nil
    item.itemId = itemIDFromLink(linkOrName)
  end

  local name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, icon, sellPrice, classID, subclassID, bindType = GetItemInfo(linkOrName)
  item.name = name or linkOrName
  item.link = link or item.link
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

local function readTooltipLines()
  local lines = {}
  local numLines = tooltip:NumLines() or 0
  for i = 1, numLines do
    local left = _G[tooltipName .. "TextLeft" .. i]
    local right = _G[tooltipName .. "TextRight" .. i]
    local leftText = left and left:GetText() or nil
    local rightText = right and right:GetText() or nil
    local leftColor = nil
    local rightColor = nil

    if left then
      local r, g, b = left:GetTextColor()
      leftColor = { r = round2(r), g = round2(g), b = round2(b) }
    end
    if right then
      local r, g, b = right:GetTextColor()
      rightColor = { r = round2(r), g = round2(g), b = round2(b) }
    end

    if leftText or rightText then
      table.insert(lines, {
        index = i,
        left = leftText,
        right = rightText,
        leftColor = leftColor,
        rightColor = rightColor,
      })
    end
  end
  return lines
end

local function tooltipSnapshot(linkOrName)
  local snapshot = {
    source = "hidden_game_tooltip",
    captured = false,
    lines = {},
  }

  if not linkOrName then
    snapshot.reason = "no_link_or_name"
    return snapshot
  end

  tooltip:ClearLines()
  local ok = false

  if type(linkOrName) == "string" and linkOrName:find("|Hitem:") then
    ok = pcall(function() tooltip:SetHyperlink(linkOrName) end)
  elseif type(linkOrName) == "number" then
    ok = pcall(function() tooltip:SetHyperlink("item:" .. tostring(linkOrName)) end)
  else
    snapshot.reason = "not_an_item_link"
    return snapshot
  end

  if not ok then
    snapshot.reason = "set_hyperlink_failed"
    tooltip:ClearLines()
    return snapshot
  end

  snapshot.lines = readTooltipLines()
  snapshot.captured = #snapshot.lines > 0
  if not snapshot.captured then
    snapshot.reason = "no_tooltip_lines_returned"
  end
  tooltip:ClearLines()
  return snapshot
end

_G.StitchLoggerTooltipSnapshot = tooltipSnapshot
_G.StitchLoggerItemSnapshotWithTooltip = function(linkOrName, count)
  local item = basicItemSnapshot(linkOrName, count)
  item.tooltip = tooltipSnapshot(item.link or linkOrName)
  return item
end

local function extractItemLinks(message)
  local links = {}
  for link in tostring(message):gmatch("|c%x+|Hitem:.-|h%[.-%]|h|r") do
    table.insert(links, link)
  end
  return links
end

local function merchantInventoryWithTooltips()
  local result = {}
  if not GetMerchantNumItems or not GetMerchantItemInfo then return result end

  for i = 1, GetMerchantNumItems() do
    local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
    local link = GetMerchantItemLink and GetMerchantItemLink(i) or nil
    table.insert(result, {
      index = i,
      name = name,
      link = link,
      priceCopper = price,
      quantity = quantity,
      numAvailable = numAvailable,
      isUsable = isUsable,
      extendedCost = extendedCost,
      item = link and _G.StitchLoggerItemSnapshotWithTooltip(link, quantity) or { name = name, quantity = quantity },
    })
  end

  return result
end

local function questPanelItemsWithTooltips()
  local result = { choices = {}, rewards = {} }

  if GetNumQuestChoices and GetQuestItemInfo then
    for i = 1, GetNumQuestChoices() do
      local name, texture, numItems, quality, isUsable = GetQuestItemInfo("choice", i)
      local link = GetQuestItemLink and GetQuestItemLink("choice", i) or nil
      table.insert(result.choices, {
        index = i,
        name = name,
        quantity = numItems,
        quality = quality,
        isUsable = isUsable,
        link = link,
        item = link and _G.StitchLoggerItemSnapshotWithTooltip(link, numItems) or nil,
      })
    end
  end

  if GetNumQuestRewards and GetQuestItemInfo then
    for i = 1, GetNumQuestRewards() do
      local name, texture, numItems, quality, isUsable = GetQuestItemInfo("reward", i)
      local link = GetQuestItemLink and GetQuestItemLink("reward", i) or nil
      table.insert(result.rewards, {
        index = i,
        name = name,
        quantity = numItems,
        quality = quality,
        isUsable = isUsable,
        link = link,
        item = link and _G.StitchLoggerItemSnapshotWithTooltip(link, numItems) or nil,
      })
    end
  end

  return result
end

frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_DETAIL")

frame:SetScript("OnEvent", function(self, event, ...)
  if event == "CHAT_MSG_LOOT" then
    local message = ...
    local links = extractItemLinks(message)
    if #links == 0 then return end

    local items = {}
    for _, link in ipairs(links) do
      table.insert(items, _G.StitchLoggerItemSnapshotWithTooltip(link, 1))
    end

    logTooltipEvent("item_tooltips_from_loot", {
      rawMessage = message,
      items = items,
      target = unitSnapshot("target"),
    })
    return
  end

  if event == "MERCHANT_SHOW" then
    logTooltipEvent("merchant_inventory_tooltips", {
      vendor = unitSnapshot("target"),
      merchantInventory = merchantInventoryWithTooltips(),
    })
    return
  end

  if event == "QUEST_COMPLETE" or event == "QUEST_DETAIL" then
    logTooltipEvent("quest_item_tooltips", {
      npc = unitSnapshot("target"),
      questTitle = GetTitleText and GetTitleText() or nil,
      questItems = questPanelItemsWithTooltips(),
      panelEvent = event,
    })
    return
  end
end)
