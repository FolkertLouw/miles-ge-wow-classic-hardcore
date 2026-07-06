-- StitchLogger Skinning module
-- Adds explicit skinning-attempt/result events on top of Core.lua's generic loot logging.
-- Skinning success is based on Skinning profession skill, not player level.

local frame = CreateFrame("Frame")
local lastSkinning = nil
local recentCorpses = {}

local SKINNING_SPELL_NAME = "Skinning"
local SKINNING_WINDOW_SECONDS = 20
local CORPSE_WINDOW_SECONDS = 90

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
    reason = "auto_skinning_event",
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

local function logSkinningEvent(eventType, payload)
  local session = currentSession()
  payload = payload or {}
  local event = {
    eventId = nextEventId(),
    eventType = eventType,
    timestamp = nowUtc(),
    timeSeconds = time(),
    character = UnitName("player"),
    characterLevel = UnitLevel("player"), -- context only; not used for skinning success
    zone = GetZoneText and GetZoneText() or nil,
    subZone = GetSubZoneText and GetSubZoneText() or nil,
    coords = getCoords(),
    source = "addon",
    module = "Skinning.lua",
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

local function itemSnapshot(linkOrName, count)
  local item = { raw = linkOrName, quantity = count or 1 }
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

local function getSkinningSkill()
  local result = {
    profession = "Skinning",
    known = false,
    baseSkill = nil,
    modifier = 0,
    effectiveSkill = nil,
    maxSkill = nil,
    source = "skill_lines",
  }

  if not GetNumSkillLines or not GetSkillLineInfo then
    result.source = "skill_lines_api_unavailable"
    return result
  end

  for i = 1, GetNumSkillLines() do
    local skillName, isHeader, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank = GetSkillLineInfo(i)
    if skillName == SKINNING_SPELL_NAME and not isHeader then
      local base = tonumber(skillRank) or 0
      local modifier = tonumber(skillModifier) or 0
      result.known = true
      result.index = i
      result.baseSkill = base
      result.modifier = modifier
      result.effectiveSkill = base + modifier
      result.maxSkill = tonumber(skillMaxRank)
      return result
    end
  end

  result.source = "skinning_not_found_in_skill_lines"
  return result
end

local function requiredSkinningForMobLevel(mobLevel)
  mobLevel = tonumber(mobLevel)
  if not mobLevel or mobLevel <= 0 then return nil end
  if mobLevel <= 10 then return 1 end
  if mobLevel <= 20 then return (mobLevel * 10) - 100 end
  return mobLevel * 5
end

local function skinningDifficultySnapshot(mob, skinningSkill)
  local mobLevel = mob and tonumber(mob.level) or nil
  local required = requiredSkinningForMobLevel(mobLevel)
  local effective = skinningSkill and skinningSkill.effectiveSkill or nil
  local canSkin = nil
  local delta = nil

  if required and effective then
    canSkin = effective >= required
    delta = effective - required
  end

  return {
    mobLevel = mobLevel,
    requiredSkill = required,
    skinningSkill = skinningSkill or getSkinningSkill(),
    canSkin = canSkin,
    skillDeltaToRequired = delta,
    requirementFormula = "Classic: level <= 10 requires 1; level 11-20 requires level*10-100; level >= 21 requires level*5.",
    difficultyColor = nil,
    difficultyColorSource = "not_captured_yet",
    notes = "Skinning success is checked against Skinning profession skill, not character level. Difficulty color from the corpse tooltip is not yet captured reliably by the addon.",
  }
end

local function pruneRecentCorpses()
  local now = time()
  local kept = {}
  for _, corpse in ipairs(recentCorpses) do
    if now - (corpse.timeSeconds or 0) <= CORPSE_WINDOW_SECONDS then
      table.insert(kept, corpse)
    end
  end
  recentCorpses = kept
end

local function rememberCorpse(mob)
  if not mob or not mob.name then return end
  pruneRecentCorpses()
  table.insert(recentCorpses, {
    mob = mob,
    timeSeconds = time(),
    timestamp = nowUtc(),
    coords = getCoords(),
    playerLevel = UnitLevel("player"),
    skinningSkillAtDefeat = getSkinningSkill(),
    skinningRequirementAtDefeat = skinningDifficultySnapshot(mob, getSkinningSkill()),
  })
end

local function closestRecentCorpse()
  pruneRecentCorpses()
  return recentCorpses[#recentCorpses]
end

local function currentOrRecentSkinTarget()
  local target = unitSnapshot("target")
  if target and target.name then
    local skill = getSkinningSkill()
    return {
      mob = target,
      source = "current_target",
      confidence = "medium",
      skinning = skinningDifficultySnapshot(target, skill),
    }
  end

  local corpse = closestRecentCorpse()
  if corpse then
    local skill = getSkinningSkill()
    return {
      mob = corpse.mob,
      source = "recent_defeat",
      corpse = corpse,
      confidence = "medium",
      skinning = skinningDifficultySnapshot(corpse.mob, skill),
    }
  end

  return {
    mob = nil,
    source = "unknown",
    confidence = "low",
    skinning = skinningDifficultySnapshot(nil, getSkinningSkill()),
  }
end

local function extractLootItems(message)
  local items = {}
  for link in tostring(message):gmatch("|c%x+|Hitem:.-|h%[.-%]|h|r") do
    table.insert(items, itemSnapshot(link, 1))
  end
  return items
end

local function isSkinningSpell(spellName)
  return spellName == SKINNING_SPELL_NAME
end

local function refreshLastSkinningSkillAfter(reason)
  if not lastSkinning then return end
  lastSkinning.skinningSkillAfter = getSkinningSkill()
  lastSkinning.skinningAfterReason = reason
  if lastSkinning.targetContext and lastSkinning.targetContext.mob then
    lastSkinning.skinningRequirementAfter = skinningDifficultySnapshot(lastSkinning.targetContext.mob, lastSkinning.skinningSkillAfter)
  end
end

frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("CHAT_MSG_SKILL")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_CLOSED")

frame:SetScript("OnEvent", function(self, event, ...)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    if not CombatLogGetCurrentEventInfo then return end
    local timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
    if subevent ~= "PARTY_KILL" then return end
    local playerGUID = UnitGUID("player")
    local petGUID = UnitGUID("pet")
    if sourceGUID ~= playerGUID and sourceGUID ~= petGUID then return end
    local target = unitSnapshot("target")
    local mob = {
      name = destName,
      guid = destGUID,
      level = target and target.guid == destGUID and target.level or nil,
      creatureType = target and target.guid == destGUID and target.creatureType or nil,
      classification = target and target.guid == destGUID and target.classification or nil,
    }
    rememberCorpse(mob)
    return
  end

  if event == "UNIT_SPELLCAST_START" then
    local unit, castGUID, spellID = ...
    if unit ~= "player" then return end
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or GetSpellInfo(spellID)
    if not isSkinningSpell(spellName) then return end
    local targetContext = currentOrRecentSkinTarget()
    local skillBefore = getSkinningSkill()
    local requirementBefore = skinningDifficultySnapshot(targetContext.mob, skillBefore)
    targetContext.skinning = requirementBefore
    lastSkinning = {
      castGUID = castGUID,
      spellID = spellID,
      spellName = spellName,
      startedAt = nowUtc(),
      timeSeconds = time(),
      targetContext = targetContext,
      skinningSkillBefore = skillBefore,
      skinningRequirementBefore = requirementBefore,
      loot = {},
    }
    logSkinningEvent("skinning_started", {
      castGUID = castGUID,
      spellID = spellID,
      spellName = spellName,
      targetContext = targetContext,
      skinningSkillBefore = skillBefore,
      skinningRequirementBefore = requirementBefore,
      confidence = targetContext.confidence,
    })
    return
  end

  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, castGUID, spellID = ...
    if unit ~= "player" then return end
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or GetSpellInfo(spellID)
    if not isSkinningSpell(spellName) then return end
    if lastSkinning then
      lastSkinning.succeededAt = nowUtc()
      lastSkinning.succeededTimeSeconds = time()
      refreshLastSkinningSkillAfter("spellcast_succeeded")
    end
    local context = lastSkinning and lastSkinning.targetContext or currentOrRecentSkinTarget()
    logSkinningEvent("skinning_succeeded", {
      castGUID = castGUID,
      spellID = spellID,
      spellName = spellName,
      targetContext = context,
      skinningSkillBefore = lastSkinning and lastSkinning.skinningSkillBefore or nil,
      skinningSkillAfter = lastSkinning and lastSkinning.skinningSkillAfter or getSkinningSkill(),
      skinningRequirementBefore = lastSkinning and lastSkinning.skinningRequirementBefore or (context and context.skinning),
      skinningRequirementAfter = lastSkinning and lastSkinning.skinningRequirementAfter or nil,
      confidence = context and context.confidence or "medium",
    })
    return
  end

  if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    local unit, castGUID, spellID = ...
    if unit ~= "player" then return end
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or GetSpellInfo(spellID)
    if not isSkinningSpell(spellName) then return end
    local context = lastSkinning and lastSkinning.targetContext or currentOrRecentSkinTarget()
    logSkinningEvent("skinning_failed", {
      castGUID = castGUID,
      spellID = spellID,
      spellName = spellName,
      reasonEvent = event,
      targetContext = context,
      skinningSkillBefore = lastSkinning and lastSkinning.skinningSkillBefore or getSkinningSkill(),
      skinningRequirementBefore = lastSkinning and lastSkinning.skinningRequirementBefore or (context and context.skinning),
      confidence = "medium",
    })
    lastSkinning = nil
    return
  end

  if event == "CHAT_MSG_SKILL" then
    local message = ...
    if lastSkinning and time() - (lastSkinning.timeSeconds or 0) <= SKINNING_WINDOW_SECONDS then
      refreshLastSkinningSkillAfter("chat_msg_skill")
      logSkinningEvent("skinning_skill_message", {
        rawMessage = message,
        skinningCast = lastSkinning,
        skinningSkillBefore = lastSkinning.skinningSkillBefore,
        skinningSkillAfter = lastSkinning.skinningSkillAfter,
        confidence = "medium",
      })
    end
    return
  end

  if event == "SKILL_LINES_CHANGED" then
    if lastSkinning and time() - (lastSkinning.timeSeconds or 0) <= SKINNING_WINDOW_SECONDS then
      refreshLastSkinningSkillAfter("skill_lines_changed")
    end
    return
  end

  if event == "LOOT_OPENED" then
    if lastSkinning and time() - (lastSkinning.timeSeconds or 0) <= SKINNING_WINDOW_SECONDS then
      refreshLastSkinningSkillAfter("loot_opened")
      logSkinningEvent("skinning_loot_opened", {
        skinningCast = lastSkinning,
        skinningSkillBefore = lastSkinning.skinningSkillBefore,
        skinningSkillAfter = lastSkinning.skinningSkillAfter,
        skinningRequirementBefore = lastSkinning.skinningRequirementBefore,
        skinningRequirementAfter = lastSkinning.skinningRequirementAfter,
        confidence = lastSkinning.targetContext and lastSkinning.targetContext.confidence or "medium",
      })
    end
    return
  end

  if event == "CHAT_MSG_LOOT" then
    local message = ...
    if not lastSkinning or time() - (lastSkinning.timeSeconds or 0) > SKINNING_WINDOW_SECONDS then return end
    local items = extractLootItems(message)
    if #items == 0 then return end
    for _, item in ipairs(items) do table.insert(lastSkinning.loot, item) end
    refreshLastSkinningSkillAfter("loot_received")
    logSkinningEvent("skinning_loot_received", {
      rawMessage = message,
      items = items,
      skinningCast = lastSkinning,
      skinnedMob = lastSkinning.targetContext and lastSkinning.targetContext.mob or nil,
      skinningSkillBefore = lastSkinning.skinningSkillBefore,
      skinningSkillAfter = lastSkinning.skinningSkillAfter,
      skinningRequirementBefore = lastSkinning.skinningRequirementBefore,
      skinningRequirementAfter = lastSkinning.skinningRequirementAfter,
      confidence = lastSkinning.targetContext and lastSkinning.targetContext.confidence or "medium",
    })
    return
  end

  if event == "LOOT_CLOSED" then
    if lastSkinning and time() - (lastSkinning.timeSeconds or 0) <= SKINNING_WINDOW_SECONDS then
      refreshLastSkinningSkillAfter("loot_closed")
      logSkinningEvent("skinning_completed", {
        skinningCast = lastSkinning,
        skinnedMob = lastSkinning.targetContext and lastSkinning.targetContext.mob or nil,
        skinningLoot = lastSkinning.loot or {},
        skinningSkillBefore = lastSkinning.skinningSkillBefore,
        skinningSkillAfter = lastSkinning.skinningSkillAfter,
        skinningRequirementBefore = lastSkinning.skinningRequirementBefore,
        skinningRequirementAfter = lastSkinning.skinningRequirementAfter,
        confidence = lastSkinning.targetContext and lastSkinning.targetContext.confidence or "medium",
      })
      lastSkinning = nil
    end
    return
  end
end)
