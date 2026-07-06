-- StitchLogger Debug UI
-- Movable in-game window that displays a live rolling feed of logged events.

local DEBUG_FRAME_NAME = "StitchLoggerDebugFrame"
local POLL_INTERVAL_SECONDS = 0.25
local MAX_LINES = 200

local state = {
  elapsed = 0,
  lastSessionId = nil,
  lastEventCount = 0,
  enabled = false,
  lines = {},
}

local function ensureDB()
  StitchLoggerDB = StitchLoggerDB or {}
  StitchLoggerDB.settings = StitchLoggerDB.settings or {}
  StitchLoggerDB.settings.debugUI = StitchLoggerDB.settings.debugUI or {
    shown = false,
    maxLines = MAX_LINES,
  }
  return StitchLoggerDB
end

local function safeText(value)
  if value == nil then return "" end
  return tostring(value)
end

local function currentSession()
  local db = ensureDB()
  if not db.currentSessionId or not db.sessions then return nil end
  for _, session in ipairs(db.sessions) do
    if session.sessionId == db.currentSessionId then return session end
  end
  return nil
end

local function shortCoords(coords)
  if not coords then return "" end
  if coords.x and coords.y then
    return string.format(" %.2f,%.2f", tonumber(coords.x) or 0, tonumber(coords.y) or 0)
  end
  if coords.mapID then return " map:" .. tostring(coords.mapID) end
  return ""
end

local function firstItemName(items)
  if type(items) ~= "table" then return nil end
  local first = items[1]
  if type(first) == "table" then return first.name or first.raw or first.link end
  return nil
end

local function summarizeEvent(event)
  if type(event) ~= "table" then return "unknown event" end

  local eventType = safeText(event.eventType or "unknown")
  local id = safeText(event.eventId or "?")
  local loc = shortCoords(event.coords)
  local suffix = ""

  if eventType == "mob_defeat" and event.mob then
    suffix = " " .. safeText(event.mob.name) .. " lvl " .. safeText(event.mob.level)
  elseif eventType == "xp_gained" then
    suffix = " +" .. safeText(event.xpGained) .. " XP"
  elseif eventType == "loot_message" then
    local item = firstItemName(event.items)
    suffix = item and (" " .. safeText(item)) or (" " .. safeText(event.rawMessage))
  elseif eventType == "skinning_completed" then
    local mob = event.skinnedMob and event.skinnedMob.name or "unknown mob"
    local item = firstItemName(event.skinningLoot)
    local skill = event.skinningSkillBefore and event.skinningSkillBefore.effectiveSkill or nil
    local req = event.skinningRequirementBefore and event.skinningRequirementBefore.requiredSkill or nil
    suffix = " " .. safeText(mob)
    if item then suffix = suffix .. " -> " .. safeText(item) end
    if skill or req then suffix = suffix .. " skill " .. safeText(skill) .. "/req " .. safeText(req) end
  elseif eventType == "skinning_started" then
    local mob = event.targetContext and event.targetContext.mob and event.targetContext.mob.name or "unknown mob"
    local req = event.skinningRequirementBefore and event.skinningRequirementBefore.requiredSkill or nil
    local skill = event.skinningSkillBefore and event.skinningSkillBefore.effectiveSkill or nil
    suffix = " " .. safeText(mob)
    if skill or req then suffix = suffix .. " skill " .. safeText(skill) .. "/req " .. safeText(req) end
  elseif eventType == "skinning_loot_received" then
    local mob = event.skinnedMob and event.skinnedMob.name or "unknown mob"
    local item = firstItemName(event.items)
    suffix = " " .. safeText(mob)
    if item then suffix = suffix .. " -> " .. safeText(item) end
  elseif eventType == "item_tooltips_from_loot" then
    local item = firstItemName(event.items)
    suffix = item and (" " .. safeText(item) .. " tooltip") or " tooltip"
  elseif eventType == "merchant_opened" or eventType == "merchant_inventory_tooltips" then
    local vendor = event.vendor and event.vendor.name or "unknown vendor"
    suffix = " " .. safeText(vendor)
  elseif eventType == "merchant_item_bought" then
    local vendor = event.vendor and event.vendor.name or "unknown vendor"
    local item = event.item and event.item.name or "unknown item"
    suffix = " " .. safeText(item) .. " from " .. safeText(vendor)
  elseif eventType == "merchant_closed" then
    suffix = " delta " .. safeText(event.moneyDeltaCopper) .. "c"
  elseif eventType == "trainer_opened" or eventType == "trainer_closed" then
    local trainer = event.trainer and event.trainer.name or "unknown trainer"
    suffix = " " .. safeText(trainer)
  elseif eventType == "trainer_service_bought" then
    local service = event.service and event.service.name or "unknown service"
    suffix = " " .. safeText(service)
  elseif eventType == "quest_accepted" or eventType == "quest_turned_in" then
    suffix = " " .. safeText(event.questTitle or event.questID)
  elseif eventType == "quest_detail_panel" or eventType == "quest_complete_panel" or eventType == "quest_item_tooltips" then
    local title = event.questTitle or (event.quest and event.quest.title) or "quest panel"
    suffix = " " .. safeText(title)
  elseif eventType == "money_changed" then
    suffix = " " .. safeText(event.deltaCopper) .. "c"
  elseif eventType == "manual_note" then
    suffix = " " .. safeText(event.text)
  elseif eventType == "manual_snapshot" then
    suffix = " snapshot"
  elseif eventType == "skills_changed" then
    suffix = " skills changed"
  end

  return string.format("[%s] %s%s%s", id, eventType, suffix, loc)
end

local function createFrame()
  if _G[DEBUG_FRAME_NAME] then return _G[DEBUG_FRAME_NAME] end

  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", DEBUG_FRAME_NAME, UIParent, template)
  f:SetSize(560, 320)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()

  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true,
      tileSize = 32,
      edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetBackdropColor(0, 0, 0, 0.88)
  end

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -12)
  title:SetText("StitchLogger Debug")
  f.title = title

  local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  subtitle:SetText("Live event feed. Drag to move. /stitchdebug hide to close.")
  f.subtitle = subtitle

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() StitchLoggerDebugHide() end)
  f.close = close

  local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  clear:SetSize(72, 22)
  clear:SetPoint("TOPRIGHT", close, "BOTTOMRIGHT", -8, -4)
  clear:SetText("Clear")
  clear:SetScript("OnClick", function() StitchLoggerDebugClear() end)
  f.clear = clear

  local scroll = CreateFrame("ScrollingMessageFrame", nil, f)
  scroll:SetPoint("TOPLEFT", 16, -58)
  scroll:SetPoint("BOTTOMRIGHT", -16, 16)
  scroll:SetFontObject(ChatFontNormal)
  scroll:SetJustifyH("LEFT")
  scroll:SetFading(false)
  scroll:SetMaxLines(MAX_LINES)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  f.log = scroll

  return f
end

local function addLine(text, r, g, b)
  local f = createFrame()
  local maxLines = (StitchLoggerDB and StitchLoggerDB.settings and StitchLoggerDB.settings.debugUI and StitchLoggerDB.settings.debugUI.maxLines) or MAX_LINES
  table.insert(state.lines, text)
  while #state.lines > maxLines do table.remove(state.lines, 1) end
  f.log:AddMessage(text, r or 0.65, g or 1, b or 0.65)
end

local function replayLines()
  local f = createFrame()
  f.log:Clear()
  for _, line in ipairs(state.lines) do
    f.log:AddMessage(line, 0.65, 1, 0.65)
  end
end

local function show()
  ensureDB().settings.debugUI.shown = true
  state.enabled = true
  local f = createFrame()
  replayLines()
  f:Show()
end

local function hide()
  ensureDB().settings.debugUI.shown = false
  state.enabled = false
  createFrame():Hide()
end

local function toggle()
  local f = createFrame()
  if f:IsShown() then hide() else show() end
end

local function clear()
  state.lines = {}
  local f = createFrame()
  f.log:Clear()
end

local function poll()
  local session = currentSession()
  if not session then return end

  if state.lastSessionId ~= session.sessionId then
    state.lastSessionId = session.sessionId
    state.lastEventCount = 0
    addLine("--- session " .. tostring(session.sessionId) .. " ---", 1, 0.82, 0)
  end

  local events = session.events or {}
  for i = state.lastEventCount + 1, #events do
    local event = events[i]
    addLine(summarizeEvent(event))
  end
  state.lastEventCount = #events
end

_G.StitchLoggerDebugShow = show
_G.StitchLoggerDebugHide = hide
_G.StitchLoggerDebugToggle = toggle
_G.StitchLoggerDebugClear = clear
_G.StitchLoggerDebugAddEvent = function(event)
  addLine(summarizeEvent(event))
end

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, elapsed)
  state.elapsed = state.elapsed + elapsed
  if state.elapsed < POLL_INTERVAL_SECONDS then return end
  state.elapsed = 0
  local db = ensureDB()
  if state.enabled or (db.settings.debugUI and db.settings.debugUI.shown) then
    state.enabled = true
    createFrame():Show()
    poll()
  end
end)

SLASH_STITCHLOGGERDEBUG1 = "/stitchdebug"
SLASH_STITCHLOGGERDEBUG2 = "/sldebug"
SlashCmdList.STITCHLOGGERDEBUG = function(msg)
  msg = string.lower(msg or "")
  if msg == "show" or msg == "on" then
    show()
  elseif msg == "hide" or msg == "off" then
    hide()
  elseif msg == "toggle" or msg == "" then
    toggle()
  elseif msg == "clear" then
    clear()
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99StitchLogger|r debug commands: /stitchdebug show, hide, toggle, clear")
  end
end
