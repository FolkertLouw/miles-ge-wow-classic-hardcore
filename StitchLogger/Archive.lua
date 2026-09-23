-- Extra raw evidence; loot-window observations are NOT receipts or drop rates.
local SL = StitchLogger
local frame = CreateFrame("Frame")
local function npcID(guid)
  return tonumber((guid or ""):match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

local lootSeen, skinningUntil = {}, 0
local function captureLoot()
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    if link then
      local _, name, quantity = GetLootSlotInfo(slot)
      local raw = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
      local sources = {}
      for i = 1, #raw, 2 do
        sources[#sources + 1] = { guid = raw[i], npcId = npcID(raw[i]), quantity = raw[i + 1] }
      end
      local key = tostring(slot) .. ":" .. link
      if not lootSeen[key] then
        lootSeen[key] = true
        SL.LogEvent("loot_window_item", {
          item = SL.ItemSnapshot(link, quantity), lootSources = sources,
          lootKind = time() <= skinningUntil and "skinning_candidate" or "unclassified",
          confidence = #sources > 0 and "high" or "low",
          notes = "Observed in loot window; source GUID is evidence. Not proof of receipt. Reopening can repeat observations. Skinning classification is temporal context only.",
        })
      end
    end
  end
end

local function captureRecipes(craft)
  local count = craft and GetNumCrafts or GetNumTradeSkills
  if not count then return end
  local profession, rank, maxRank
  if craft then
    if GetCraftDisplaySkillLine then profession, rank, maxRank = GetCraftDisplaySkillLine() end
    profession = profession or (GetCraftName and GetCraftName())
  elseif GetTradeSkillLine then profession, rank, maxRank = GetTradeSkillLine() end
  local recipes = {}
  for i = 1, count() do
    local name, difficulty, available, subName, trainingPoints, requiredLevel
    if craft then
      local expanded
      name, subName, difficulty, available, expanded, trainingPoints, requiredLevel = GetCraftInfo(i)
    else name, difficulty, available = GetTradeSkillInfo(i) end
    if name and difficulty ~= "header" then
      local linkFn = craft and GetCraftItemLink or GetTradeSkillItemLink
      local reagentCountFn = craft and GetCraftNumReagents or GetTradeSkillNumReagents
      local reagentFn = craft and GetCraftReagentInfo or GetTradeSkillReagentInfo
      local reagentLinkFn = craft and GetCraftReagentItemLink or GetTradeSkillReagentItemLink
      local recipe = { name = name, rank = subName, difficulty = difficulty,
        craftableCount = available, trainingPointCost = trainingPoints, requiredLevel = requiredLevel,
        outputLink = linkFn and linkFn(i), reagents = {} }
      if not craft and GetTradeSkillRecipeLink then recipe.recipeLink = GetTradeSkillRecipeLink(i) end
      if not craft and GetTradeSkillNumMade then recipe.minMade, recipe.maxMade = GetTradeSkillNumMade(i) end
      for j = 1, (reagentCountFn and reagentCountFn(i) or 0) do
        local reagentName, _, required, owned = reagentFn(i, j)
        recipe.reagents[#recipe.reagents + 1] = { name = reagentName,
          link = reagentLinkFn and reagentLinkFn(i, j), required = required, owned = owned }
      end
      recipes[#recipes + 1] = recipe
    end
  end
  SL.LogEvent("recipes_snapshot", { profession = profession, skillRank = rank, maxRank = maxRank,
    recipes = recipes, scope = "currently_visible_entries; expand categories and clear filters to capture more" })
end

local pending = {}
local function scheduleRecipes(craft)
  local key = craft and "craft" or "trade"
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(0.5, function()
    pending[key] = nil
    if not (StitchLoggerDB and StitchLoggerDB.paused) then captureRecipes(craft) end
  end)
end

for _, event in ipairs({"LOOT_OPENED", "LOOT_CLOSED", "UNIT_SPELLCAST_SUCCEEDED",
  "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "LOOT_CLOSED" then lootSeen = {}; skinningUntil = 0; return end
  if StitchLoggerDB and StitchLoggerDB.paused then return end
  if event == "LOOT_OPENED" then captureLoot()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    if unit == "player" and spellID == 8613 then skinningUntil = time() + 5 end
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then scheduleRecipes(false)
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then scheduleRecipes(true) end
end)

-- Search raw evidence in-game without modifying it. Most recent 15 matches.
SLASH_STITCHFIND1 = "/stitchfind"
SlashCmdList.STITCHFIND = function(query)
  query = (query or ""):lower()
  if query == "" then DEFAULT_CHAT_FRAME:AddMessage("Usage: /stitchfind kodo"); return end
  local function contains(value)
    if type(value) == "string" then return value:lower():find(query, 1, true) ~= nil end
    if type(value) == "number" then return tostring(value) == query end
    if type(value) == "table" then for _, v in pairs(value) do if contains(v) then return true end end end
    return false
  end
  local count = 0
  local sessions = StitchLoggerDB and StitchLoggerDB.sessions or {}
  for i = #sessions, 1, -1 do
    local events = sessions[i].events or {}
    for j = #events, 1, -1 do
      local e = events[j]
      if contains(e) then
        local subject = e.mob or e.item or e.target or e.vendor or e.trainer or {}
        DEFAULT_CHAT_FRAME:AddMessage((e.timestamp or "") .. " " .. (e.eventType or "") .. " " ..
          (subject.name or e.profession or e.text or e.rawMessage or "") .. " [" .. (e.eventId or "") .. "] " .. (e.zone or ""))
        count = count + 1
        if count == 15 then return end
      end
    end
  end
  DEFAULT_CHAT_FRAME:AddMessage("StitchLogger: " .. count .. " matching events.")
end
