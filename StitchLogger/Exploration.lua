-- Field observations: never infer hidden prerequisites or exact object coordinates.
local SL=StitchLogger
local frame=CreateFrame("Frame")
local lastPosition, elapsed, lastServices = nil,0,{}
local serviceEvents={GOSSIP_SHOW="gossip",BANKFRAME_OPENED="bank",MAIL_SHOW="mailbox",
  AUCTION_HOUSE_SHOW="auction_house",TAXIMAP_OPENED="flight_master",TRAINER_SHOW="trainer",MERCHANT_SHOW="merchant"}
local function route(reason)
  local pos=SL.Coords();if not pos or not pos.x or not pos.y then return end
  if reason=="movement" and lastPosition and lastPosition.mapID==pos.mapID then
    local dx,dy=pos.x-lastPosition.x,pos.y-lastPosition.y
    if dx*dx+dy*dy<1 then return end
  end
  lastPosition=SL.Copy(pos)
  SL.LogEvent("route_observation",{reason=reason,player=SL.PlayerSnapshot(),coordinateBasis="player_position"})
end
for event in pairs(serviceEvents) do frame:RegisterEvent(event) end
for _,event in ipairs({"ZONE_CHANGED","ZONE_CHANGED_NEW_AREA","ZONE_CHANGED_INDOORS","PLAYER_ENTERING_WORLD",
  "QUEST_DETAIL","QUEST_ACCEPTED","QUEST_TURNED_IN","CHAT_MSG_SKILL","UNIT_SPELLCAST_SENT"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(_,event,...)
  if not SL.Active() then return end
  if serviceEvents[event] then
    local npc=SL.Actor("npc") or SL.Actor("target")
    local options=event=="GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or nil
    local active=event=="GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or nil
    local available=event=="GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or nil
    SL.LogEvent("service_discovered",{service=serviceEvents[event],npc=npc,gossipOptions=options,
      activeQuests=active,availableQuests=available,identityEvidence=npc and "interacting_unit_or_target_candidate" or "unknown"})
  elseif event=="CHAT_MSG_SKILL" then
    SL.LogEvent("skill_message",{rawMessage=(...),skills=SL.SkillsSnapshot()})
  elseif event=="UNIT_SPELLCAST_SENT" then
    local unit,target,guid,id=...
    if unit=="player" then
      -- Tooltip text is context only; it may be stale or belong to another object.
      local text=GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
      if text and GameTooltip and GameTooltip:IsShown() then
        SL.LogEvent("interaction_context",{castGUID=guid,spellID=id,targetName=target,tooltipNameCandidate=text,
          confidence="low",coordinateBasis="observer_position"})
      end
    end
  elseif event=="QUEST_DETAIL" or event=="QUEST_ACCEPTED" or event=="QUEST_TURNED_IN" then
    local id=event=="QUEST_DETAIL" and GetQuestID and GetQuestID() or (...)
    SL.LogEvent("quest_availability_context",{questID=id,trigger=event,player=SL.PlayerSnapshot(),skills=SL.SkillsSnapshot(),
      prerequisiteStatus="not_exposed; player_state_is_observed_context_not_a_requirement"})
  else route(event) end
end)
frame:SetScript("OnUpdate",function(_,dt)
  elapsed=elapsed+dt;if elapsed<30 then return end;elapsed=0
  if SL.Active() then route("movement") end
end)
SL.OnReset(function() lastPosition=nil;elapsed=0 end)
