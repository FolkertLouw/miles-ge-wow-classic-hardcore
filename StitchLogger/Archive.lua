local SL = StitchLogger
local frame = CreateFrame("Frame")
local lastSnapshots = {}
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
      if craft and GetCraftRecipeLink then recipe.recipeLink = GetCraftRecipeLink(i) end
      if not craft and GetTradeSkillNumMade then recipe.minMade, recipe.maxMade = GetTradeSkillNumMade(i) end
      for j = 1, (reagentCountFn and reagentCountFn(i) or 0) do
        local reagentName, _, required, owned = reagentFn(i, j)
        recipe.reagents[#recipe.reagents + 1] = { name = reagentName,
          link = reagentLinkFn and reagentLinkFn(i, j), required = required, owned = owned }
      end
      recipes[#recipes + 1] = recipe
    end
  end
  if SL.RememberRecipes then SL.RememberRecipes(recipes, profession) end
  local fingerprint = SL.Fingerprint({profession, rank, maxRank, recipes})
  local key = craft and "craft" or "trade"
  if lastSnapshots[key] == fingerprint then return end
  lastSnapshots[key] = fingerprint
  SL.LogEvent("recipes_snapshot", { profession = profession, skillRank = rank, maxRank = maxRank,
    recipes = recipes, scope = "currently_visible_entries; expand categories and clear filters to capture more" })
end

SL.OnReset(function() lastSnapshots = {} end)
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

for _, event in ipairs({"TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event)
  if StitchLoggerDB and StitchLoggerDB.paused then return end
  scheduleRecipes(event == "CRAFT_SHOW" or event == "CRAFT_UPDATE")
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
        local subject = e.encounter or e.mob or e.item or e.target or e.vendor or e.trainer or {}
        DEFAULT_CHAT_FRAME:AddMessage((e.timestamp or "") .. " " .. (e.eventType or "") .. " " ..
          (subject.name or e.profession or e.text or e.rawMessage or e.kind or "") .. " " .. (e.status or e.reason or "") .. " [" .. (e.eventId or "") .. "] " .. (e.zone or ""))
        count = count + 1
        if count == 15 then return end
      end
    end
  end
  DEFAULT_CHAT_FRAME:AddMessage("StitchLogger: " .. count .. " matching events.")
end
