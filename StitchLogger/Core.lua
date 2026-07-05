-- StitchLogger
-- Field-data logger for WoW Classic Hardcore.
-- Stores raw observations in SavedVariables: StitchLoggerDB

local ADDON_NAME = ...
local frame = CreateFrame("Frame")
local SL = {}
_G.StitchLogger = SL

local DEFAULT_SETTINGS = {
  autoStartSession = true,
  logQuestPanels = true,
  logMerchantInventory = true,
  logTrainerWindow = true,
  logBagDiffOnMerchantClose = true,
  logLootChat = true,
  logCombatDefeats = true,
  logMoneyChanges = true,
  printEvents = false,
}

local EVENTS = {
  "ADDON_LOADED",
  "PLAYER_LOGIN",
  "PLAYER_LOGOUT",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_TARGET_CHANGED",
  "PLAYER_MONEY",
  "PLAYER_XP_UPDATE",
  "PLAYER_LEVEL_UP",
  "QUEST_ACCEPTED",
  "QUEST_TURNED_IN",
  "QUEST_DETAIL",
  "QUEST_PROGRESS",
  "QUEST_COMPLETE",
  "QUEST_GREETING",
  "CHAT_MSG_LOOT",
  "COMBAT_LOG_EVENT_UNFILTERED",
  "MERCHANT_SHOW",
  "MERCHANT_UPDATE",
  "MERCHANT_CLOSED",
  "TRAINER_SHOW",
  "TRAINER_UPDATE",
  "TRAINER_CLOSED",
  "SKILL_LINES_CHANGED",
  "BAG_UPDATE_DELAYED",
}

local function cloneDefaults(target, defaults)
  target = target or {}
  for k, v in pairs(defaults) do
    if target[k] == nil then
      if type(v) == "table" then
        target[k] = cloneDefaults({}, v)
      else
        target[k] = v
      end
    elseif type(v) == "table" and type(target[k]) == "table" then
      cloneDefaults(target[k], v)
    end
  end
  return target
end

local function nowUtc()
  local t = (GetServerTime and GetServerTime()) or time()
  return date("!%Y-%m-%dT%H:%M:%SZ", t)
end

local function printMsg(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99StitchLogger|r: " .. tostring(msg))
end

local function round2(n)
  if not n then return nil end
  return math.floor(n * 100 + 0.5) / 100
end

local function getCoords()
  if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
    return nil
  end

  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return nil end

  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return { mapID = mapID } end

  return {
    mapID = mapID,
    x = round2(pos.x * 100),
    y = round2(pos.y * 100),
  }
end

local function unitSnapshot(unit)
  if not UnitExists(unit) then return nil end
  return {
    name = UnitName(unit),
    guid = UnitGUID(unit),
    level = UnitLevel(unit),
    creatureType = UnitCreatureType(unit),
    class = UnitClass(unit),
    reaction = UnitReaction(unit, "player"),
    classification = UnitClassification(unit),
  }
end

local function playerSnapshot()
  return {
    name = UnitName("player"),
    guid = UnitGUID("player"),
    realm = GetRealmName and GetRealmName() or nil,
    faction = UnitFactionGroup("player"),
    race = UnitRace("player"),
    class = UnitClass("player"),
    level = UnitLevel("player"),
    xp = UnitXP("player"),
    xpMax = UnitXPMax("player"),
    moneyCopper = GetMoney and GetMoney() or nil,
    zone = GetZoneText and GetZoneText() or nil,
    subZone = GetSubZoneText and GetSubZoneText() or nil,
    coords = getCoords(),
  }
end

local function ensureDB()
  StitchLoggerDB = StitchLoggerDB or {}
  StitchLoggerDB.version = StitchLoggerDB.version or 1
  StitchLoggerDB.addonVersion = "0.1.0"
  StitchLoggerDB.createdAt = StitchLoggerDB.createdAt or nowUtc()
  StitchLoggerDB.settings = cloneDefaults(StitchLoggerDB.settings or {}, DEFAULT_SETTINGS)
  StitchLoggerDB.sessions = StitchLoggerDB.sessions or {}
  StitchLoggerDB.counters = StitchLoggerDB.counters or { nextSession = 1, nextEvent = 1 }
  StitchLoggerDB.importNotes = StitchLoggerDB.importNotes or {}
  return StitchLoggerDB
end

local function currentSession()
  local db = ensureDB()
  if db.currentSessionId then
    for _, session in ipairs(db.sessions) do
      if session.sessionId == db.currentSessionId then
        return session
      end
    end
  end
  return nil
end

local function nextSessionId()
  local db = ensureDB()
  local n = db.counters.nextSession or 1
  db.counters.nextSession = n + 1
  return date("%Y-%m-%d") .. "-" .. string.format("%03d", n)
end

local function nextEventId()
  local db = ensureDB()
  local n = db.counters.nextEvent or 1
  db.counters.nextEvent = n + 1
  return "sl-" .. string.format("%06d", n)
end

local function startSession(reason)
  local db = ensureDB()
  local existing = currentSession()
  if existing then return existing end

  local session = {
    sessionId = nextSessionId(),
    startedAt = nowUtc(),
    endedAt = nil,
    reason = reason or "manual_or_auto_start",
    character = playerSnapshot(),
    events = {},
  }

  table.insert(db.sessions, session)
  db.currentSessionId = session.sessionId
  printMsg("session started: " .. session.sessionId)
  return session
end

local function stopSession(reason)
  local db = ensureDB()
  local session = currentSession()
  if not session then
    printMsg("no active session")
    return
  end
  session.endedAt = nowUtc()
  session.endReason = reason or "manual_or_logout"
  db.currentSessionId = nil
  printMsg("session stopped: " .. session.sessionId)
end

local function logEvent(eventType, payload)
  local db = ensureDB()
  local session = currentSession() or startSession("auto_event")
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
    confidence = payload.confidence or "high",
  }

  payload.confidence = nil
  for k, v in pairs(payload) do
    event[k] = v
  end

  table.insert(session.events, event)

  if db.settings and db.settings.printEvents then
    printMsg("logged " .. eventType .. " " .. event.eventId)
  end

  return event
end

local function itemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  local itemString = link:match("item:([%-?%d:]+)")
  if not itemString then return nil end
  local id = itemString:match("^(%-?%d+)")
  return tonumber(id)
end

local function itemSnapshot(linkOrName, count)
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

local function getBagSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag)
  end
  if GetContainerNumSlots then
    return GetContainerNumSlots(bag)
  end
  return 0
end

local function getBagItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    return {
      link = info.hyperlink,
      count = info.stackCount or 1,
      itemId = info.itemID,
      quality = info.quality,
      icon = info.iconFileID,
      bag = bag,
      slot = slot,
    }
  end

  if GetContainerItemInfo then
    local texture, count, locked, quality, readable, lootable, link, isFiltered, noValue, itemId = GetContainerItemInfo(bag, slot)
    if not texture and not link then return nil end
    return {
      link = link,
      count = count or 1,
      itemId = itemId or itemIDFromLink(link),
      quality = quality,
      icon = texture,
      bag = bag,
      slot = slot,
    }
  end

  return nil
end

local function bagSnapshot()
  local snapshot = {
    moneyCopper = GetMoney and GetMoney() or nil,
    items = {},
    slots = {},
  }

  local maxBag = NUM_BAG_SLOTS or 4
  for bag = 0, maxBag do
    local slots = getBagSlots(bag)
    for slot = 1, slots do
      local info = getBagItem(bag, slot)
      if info and info.link then
        local item = itemSnapshot(info.link, info.count)
        local key = tostring(item.itemId or item.link or item.name)
        snapshot.items[key] = snapshot.items[key] or {
          itemId = item.itemId,
          name = item.name,
          link = item.link,
          quality = item.quality or info.quality,
          itemType = item.itemType,
          itemSubType = item.itemSubType,
          equipLoc = item.equipLoc,
          vendorValueCopper = item.vendorValueCopper,
          count = 0,
        }
        snapshot.items[key].count = snapshot.items[key].count + (info.count or 1)
        table.insert(snapshot.slots, {
          bag = bag,
          slot = slot,
          key = key,
          count = info.count or 1,
          item = item,
        })
      end
    end
  end

  return snapshot
end

local function diffBags(before, after)
  local removed, added = {}, {}
  before = before or { items = {} }
  after = after or { items = {} }

  for key, b in pairs(before.items or {}) do
    local a = (after.items or {})[key]
    local delta = (b.count or 0) - (a and a.count or 0)
    if delta > 0 then
      table.insert(removed, {
        key = key,
        itemId = b.itemId,
        name = b.name,
        link = b.link,
        quality = b.quality,
        itemType = b.itemType,
        itemSubType = b.itemSubType,
        equipLoc = b.equipLoc,
        vendorValueCopper = b.vendorValueCopper,
        quantity = delta,
      })
    end
  end

  for key, a in pairs(after.items or {}) do
    local b = (before.items or {})[key]
    local delta = (a.count or 0) - (b and b.count or 0)
    if delta > 0 then
      table.insert(added, {
        key = key,
        itemId = a.itemId,
        name = a.name,
        link = a.link,
        quality = a.quality,
        itemType = a.itemType,
        itemSubType = a.itemSubType,
        equipLoc = a.equipLoc,
        vendorValueCopper = a.vendorValueCopper,
        quantity = delta,
      })
    end
  end

  return added, removed
end

local function professionSnapshot()
  local result = {}
  if not GetNumSkillLines or not GetSkillLineInfo then return result end

  for i = 1, GetNumSkillLines() do
    local skillName, isHeader, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank = GetSkillLineInfo(i)
    if skillName and not isHeader then
      table.insert(result, {
        name = skillName,
        rank = skillRank,
        maxRank = skillMaxRank,
        modifier = skillModifier,
      })
    end
  end

  return result
end

local function merchantInventorySnapshot()
  local result = {}
  if not GetMerchantNumItems or not GetMerchantItemInfo then return result end

  for i = 1, GetMerchantNumItems() do
    local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
    local link = GetMerchantItemLink and GetMerchantItemLink(i) or nil
    table.insert(result, {
      index = i,
      name = name,
      link = link,
      item = link and itemSnapshot(link, quantity) or { name = name, quantity = quantity },
      priceCopper = price,
      quantity = quantity,
      numAvailable = numAvailable,
      isUsable = isUsable,
      extendedCost = extendedCost,
    })
  end

  return result
end

local function trainerServicesSnapshot()
  local result = {}
  if not GetNumTrainerServices or not GetTrainerServiceInfo then return result end

  for i = 1, GetNumTrainerServices() do
    local name, rank, category, expanded = GetTrainerServiceInfo(i)
    local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil
    table.insert(result, {
      index = i,
      name = name,
      rank = rank,
      category = category,
      expanded = expanded,
      costCopper = cost,
    })
  end

  return result
end

local function questRewardSnapshot()
  local reward = {
    title = GetTitleText and GetTitleText() or nil,
    objectiveText = GetObjectiveText and GetObjectiveText() or nil,
    questText = GetQuestText and GetQuestText() or nil,
    choices = {},
    rewards = {},
  }

  if GetNumQuestChoices and GetQuestItemInfo then
    for i = 1, GetNumQuestChoices() do
      local name, texture, numItems, quality, isUsable = GetQuestItemInfo("choice", i)
      local link = GetQuestItemLink and GetQuestItemLink("choice", i) or nil
      table.insert(reward.choices, {
        index = i,
        name = name,
        quantity = numItems,
        quality = quality,
        isUsable = isUsable,
        link = link,
        item = link and itemSnapshot(link, numItems) or nil,
      })
    end
  end

  if GetNumQuestRewards and GetQuestItemInfo then
    for i = 1, GetNumQuestRewards() do
      local name, texture, numItems, quality, isUsable = GetQuestItemInfo("reward", i)
      local link = GetQuestItemLink and GetQuestItemLink("reward", i) or nil
      table.insert(reward.rewards, {
        index = i,
        name = name,
        quantity = numItems,
        quality = quality,
        isUsable = isUsable,
        link = link,
        item = link and itemSnapshot(link, numItems) or nil,
      })
    end
  end

  if GetRewardMoney then reward.moneyCopper = GetRewardMoney() end
  if GetRewardXP then reward.xp = GetRewardXP() end

  return reward
end

local lastTarget = nil
local lastDefeat = nil
local lastXP = nil
local lastMoney = nil
local merchantSession = nil
local trainerSession = nil

local function cacheTarget()
  lastTarget = unitSnapshot("target")
  if lastTarget then
    lastTarget.coords = getCoords()
    lastTarget.cachedAt = nowUtc()
  end
end

local function recentDefeatContext()
  if lastDefeat and (time() - (lastDefeat.timeSeconds or 0)) <= 20 then
    return lastDefeat
  end
  return nil
end

local function onCombatLog()
  local db = ensureDB()
  if not db.settings.logCombatDefeats then return end
  if not CombatLogGetCurrentEventInfo then return end

  local timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

  if subevent ~= "PARTY_KILL" then return end

  local playerGUID = UnitGUID("player")
  local petGUID = UnitGUID("pet")
  if sourceGUID ~= playerGUID and sourceGUID ~= petGUID then return end

  local cached = nil
  if lastTarget and lastTarget.guid == destGUID then cached = lastTarget end

  local event = logEvent("mob_defeat", {
    mob = {
      name = destName,
      guid = destGUID,
      level = cached and cached.level or nil,
      creatureType = cached and cached.creatureType or nil,
      classification = cached and cached.classification or nil,
    },
    creditedSource = {
      guid = sourceGUID,
      name = sourceName,
      sourceType = sourceGUID == petGUID and "pet" or "player",
    },
    confidence = cached and "high" or "medium",
  })

  lastDefeat = {
    eventId = event.eventId,
    mobName = destName,
    mobGuid = destGUID,
    mobLevel = cached and cached.level or nil,
    timeSeconds = time(),
    coords = event.coords,
  }
end

local function onLootMessage(message)
  local db = ensureDB()
  if not db.settings.logLootChat then return end

  local items = {}
  for link in tostring(message):gmatch("|c%x+|Hitem:.-|h%[.-%]|h|r") do
    table.insert(items, itemSnapshot(link, 1))
  end

  logEvent("loot_message", {
    rawMessage = message,
    items = items,
    recentDefeat = recentDefeatContext(),
    confidence = (#items > 0 and recentDefeatContext()) and "medium" or "low",
  })
end

local function onMoneyChanged()
  local db = ensureDB()
  if not db.settings.logMoneyChanges then return end

  local money = GetMoney and GetMoney() or nil
  if not money then return end

  if lastMoney == nil then
    lastMoney = money
    return
  end

  local delta = money - lastMoney
  if delta ~= 0 then
    logEvent("money_changed", {
      moneyBeforeCopper = lastMoney,
      moneyAfterCopper = money,
      deltaCopper = delta,
    })
  end
  lastMoney = money
end

local function onXPChanged()
  local xp = UnitXP("player")
  if lastXP == nil then
    lastXP = xp
    return
  end

  local delta = xp - lastXP
  if delta < 0 then
    delta = nil -- likely level-up reset; PLAYER_LEVEL_UP will log separately
  end

  if delta and delta > 0 then
    logEvent("xp_gained", {
      xpBefore = lastXP,
      xpAfter = xp,
      xpGained = delta,
      recentDefeat = recentDefeatContext(),
    })
  end

  lastXP = xp
end

local function onMerchantShow()
  local db = ensureDB()
  local vendor = unitSnapshot("target")
  merchantSession = {
    openedAt = nowUtc(),
    vendor = vendor,
    coords = getCoords(),
    moneyBeforeCopper = GetMoney and GetMoney() or nil,
    bagBefore = bagSnapshot(),
    inventory = db.settings.logMerchantInventory and merchantInventorySnapshot() or nil,
  }

  logEvent("merchant_opened", {
    vendor = vendor,
    merchantInventory = merchantSession.inventory,
  })
end

local function onMerchantClosed()
  if not merchantSession then return end

  local after = bagSnapshot()
  local added, removed = diffBags(merchantSession.bagBefore, after)

  logEvent("merchant_closed", {
    vendor = merchantSession.vendor,
    openedAt = merchantSession.openedAt,
    moneyBeforeCopper = merchantSession.moneyBeforeCopper,
    moneyAfterCopper = after.moneyCopper,
    moneyDeltaCopper = after.moneyCopper and merchantSession.moneyBeforeCopper and (after.moneyCopper - merchantSession.moneyBeforeCopper) or nil,
    itemsAdded = added,
    itemsRemoved = removed,
    notes = "Inventory diff across the merchant session. This is raw evidence; importer should reconcile purchases/sales carefully.",
  })

  merchantSession = nil
end

local function onTrainerShow()
  trainerSession = {
    openedAt = nowUtc(),
    trainer = unitSnapshot("target"),
    coords = getCoords(),
    moneyBeforeCopper = GetMoney and GetMoney() or nil,
    services = trainerServicesSnapshot(),
  }

  logEvent("trainer_opened", {
    trainer = trainerSession.trainer,
    services = trainerSession.services,
  })
end

local function onTrainerClosed()
  if not trainerSession then return end
  logEvent("trainer_closed", {
    trainer = trainerSession.trainer,
    openedAt = trainerSession.openedAt,
    moneyBeforeCopper = trainerSession.moneyBeforeCopper,
    moneyAfterCopper = GetMoney and GetMoney() or nil,
  })
  trainerSession = nil
end

local function hookFunctions()
  if SL.hooksInstalled then return end
  SL.hooksInstalled = true

  if BuyTrainerService then
    hooksecurefunc("BuyTrainerService", function(index)
      local name, rank, category = GetTrainerServiceInfo and GetTrainerServiceInfo(index)
      local cost = GetTrainerServiceCost and GetTrainerServiceCost(index) or nil
      logEvent("trainer_service_bought", {
        trainer = unitSnapshot("target"),
        service = {
          index = index,
          name = name,
          rank = rank,
          category = category,
          costCopper = cost,
        },
      })
    end)
  end

  if BuyMerchantItem then
    hooksecurefunc("BuyMerchantItem", function(index, quantity)
      local name, texture, price, stackQuantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(index)
      local link = GetMerchantItemLink and GetMerchantItemLink(index) or nil
      local qty = quantity or 1
      logEvent("merchant_item_bought", {
        vendor = unitSnapshot("target"),
        item = link and itemSnapshot(link, qty * (stackQuantity or 1)) or { name = name, quantity = qty * (stackQuantity or 1) },
        index = index,
        requestedStacks = qty,
        stackQuantity = stackQuantity,
        unitStackPriceCopper = price,
        estimatedTotalPriceCopper = price and (price * qty) or nil,
        extendedCost = extendedCost,
      })
    end)
  end
end

local function questTitleFromAcceptedArgs(arg1, arg2)
  local questID = arg2 or arg1
  if C_QuestLog and C_QuestLog.GetTitleForQuestID and questID then
    local title = C_QuestLog.GetTitleForQuestID(questID)
    if title then return title, questID end
  end
  return nil, questID
end

local function onEvent(self, event, ...)
  if event == "ADDON_LOADED" then
    local loaded = ...
    if loaded ~= ADDON_NAME then return end
    ensureDB()
    hookFunctions()
    return
  end

  if event == "PLAYER_LOGIN" then
    ensureDB()
    lastXP = UnitXP("player")
    lastMoney = GetMoney and GetMoney() or nil
    if StitchLoggerDB.settings.autoStartSession then
      startSession("player_login")
    end
    logEvent("player_login", { player = playerSnapshot(), professions = professionSnapshot() })
    return
  end

  if event == "PLAYER_LOGOUT" then
    logEvent("player_logout", { player = playerSnapshot(), professions = professionSnapshot() })
    local session = currentSession()
    if session then
      session.endedAt = nowUtc()
      session.endReason = "player_logout"
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    logEvent("world_entered", { player = playerSnapshot(), professions = professionSnapshot() })
    return
  end

  if event == "PLAYER_TARGET_CHANGED" then
    cacheTarget()
    if lastTarget then
      logEvent("target_changed", { target = lastTarget, confidence = "medium" })
    end
    return
  end

  if event == "PLAYER_MONEY" then onMoneyChanged(); return end
  if event == "PLAYER_XP_UPDATE" then onXPChanged(); return end

  if event == "PLAYER_LEVEL_UP" then
    local newLevel = ...
    logEvent("level_up", { newLevel = newLevel })
    return
  end

  if event == "COMBAT_LOG_EVENT_UNFILTERED" then onCombatLog(); return end

  if event == "CHAT_MSG_LOOT" then
    local message = ...
    onLootMessage(message)
    return
  end

  if event == "MERCHANT_SHOW" then onMerchantShow(); return end
  if event == "MERCHANT_UPDATE" and merchantSession then merchantSession.inventory = merchantInventorySnapshot(); return end
  if event == "MERCHANT_CLOSED" then onMerchantClosed(); return end

  if event == "TRAINER_SHOW" then onTrainerShow(); return end
  if event == "TRAINER_UPDATE" and trainerSession then trainerSession.services = trainerServicesSnapshot(); return end
  if event == "TRAINER_CLOSED" then onTrainerClosed(); return end

  if event == "QUEST_ACCEPTED" then
    local arg1, arg2 = ...
    local title, questID = questTitleFromAcceptedArgs(arg1, arg2)
    logEvent("quest_accepted", { questID = questID, questTitle = title, npc = unitSnapshot("target") })
    return
  end

  if event == "QUEST_TURNED_IN" then
    local questID, xpReward, moneyReward = ...
    local title = nil
    if C_QuestLog and C_QuestLog.GetTitleForQuestID and questID then title = C_QuestLog.GetTitleForQuestID(questID) end
    logEvent("quest_turned_in", {
      questID = questID,
      questTitle = title,
      xpReward = xpReward,
      moneyRewardCopper = moneyReward,
      npc = unitSnapshot("target"),
    })
    return
  end

  if event == "QUEST_DETAIL" then
    logEvent("quest_detail_panel", { npc = unitSnapshot("target"), quest = questRewardSnapshot() })
    return
  end

  if event == "QUEST_PROGRESS" then
    logEvent("quest_progress_panel", { npc = unitSnapshot("target"), quest = questRewardSnapshot() })
    return
  end

  if event == "QUEST_COMPLETE" then
    logEvent("quest_complete_panel", { npc = unitSnapshot("target"), quest = questRewardSnapshot() })
    return
  end

  if event == "QUEST_GREETING" then
    logEvent("quest_greeting", { npc = unitSnapshot("target") })
    return
  end

  if event == "SKILL_LINES_CHANGED" then
    logEvent("skills_changed", { professions = professionSnapshot() })
    return
  end

  if event == "BAG_UPDATE_DELAYED" then
    -- Reserved for later precise inventory stream. Merchant close currently records bag diffs.
    return
  end
end

for _, ev in ipairs(EVENTS) do frame:RegisterEvent(ev) end
frame:SetScript("OnEvent", onEvent)

local function slashHelp()
  printMsg("commands:")
  printMsg("/stitch start - start session")
  printMsg("/stitch stop - stop session")
  printMsg("/stitch note <text> - add manual note")
  printMsg("/stitch snapshot - log player/bag/profession snapshot")
  printMsg("/stitch status - show status")
  printMsg("/stitch export - show SavedVariables path reminder")
  printMsg("/stitch print on|off - toggle chat event prints")
end

SLASH_STITCHLOGGER1 = "/stitch"
SLASH_STITCHLOGGER2 = "/stitchlogger"
SlashCmdList.STITCHLOGGER = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = string.lower(cmd or "")

  if cmd == "start" then
    startSession("manual")
  elseif cmd == "stop" then
    stopSession("manual")
  elseif cmd == "note" then
    if rest == "" then
      printMsg("usage: /stitch note <text>")
      return
    end
    logEvent("manual_note", { text = rest, target = unitSnapshot("target") })
    printMsg("note logged")
  elseif cmd == "snapshot" then
    logEvent("manual_snapshot", {
      player = playerSnapshot(),
      target = unitSnapshot("target"),
      professions = professionSnapshot(),
      bags = bagSnapshot(),
    })
    printMsg("snapshot logged")
  elseif cmd == "status" then
    local session = currentSession()
    if session then
      printMsg("active session: " .. session.sessionId .. " events: " .. tostring(#session.events))
    else
      printMsg("no active session")
    end
  elseif cmd == "export" then
    printMsg("logout or /reload, then upload WTF/Account/<ACCOUNT>/SavedVariables/StitchLogger.lua")
  elseif cmd == "print" then
    local db = ensureDB()
    if rest == "on" then db.settings.printEvents = true; printMsg("event prints on")
    elseif rest == "off" then db.settings.printEvents = false; printMsg("event prints off")
    else printMsg("usage: /stitch print on|off") end
  else
    slashHelp()
  end
end
