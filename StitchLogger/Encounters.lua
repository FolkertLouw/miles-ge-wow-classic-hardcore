-- Encounters are keyed by creature GUID + observer, never by most-recent kill.
local SL=StitchLogger
local frame=CreateFrame("Frame")
local window, recentWindows, cast, spellTarget = nil, {}, nil, nil
local touched, deadSeen = {}, {}
local function records()
  StitchLoggerDB.encounters = StitchLoggerDB.encounters or {}
  return StitchLoggerDB.encounters
end
local function key(guid) return (GetRealmName() or "")..":"..(UnitGUID("player") or "")..":"..guid end
local function encounter(guid, name)
  if not SL.NPCID(guid) then return nil end
  local all=records(); local k=key(guid); local e=all[k]
  if not e then
    local seed=SL.LogEvent("encounter_started",{mob={guid=guid,npcId=SL.NPCID(guid),name=name}})
    if not seed then return nil end
    e={encounterId=k..":"..seed.eventId, guid=guid, npcId=SL.NPCID(guid), name=name,
      firstSeen=time(), lastSeen=time(), revision=0, observations={}, phases={}, lootState="not_inspected"}
    all[k]=e
  end
  if name then e.name=name end
  e.lastSeen=time(); return e
end
local function publish(e, reason)
  if not e then return end
  e.revision=e.revision+1; e.lastSeen=time()
  SL.LogEvent("encounter_updated",{encounterId=e.encounterId, reason=reason, encounter=e})
end
local function observe(unit)
  local actor=SL.Actor(unit)
  if not actor or not actor.npcId then return end
  local e=encounter(actor.guid,actor.name)
  e.level=actor.level; e.creatureType=actor.creatureType; e.classification=actor.classification
  if not e.lastObservation or time()-e.lastObservation>=30 then
    e.lastObservation=time()
    e.observations[#e.observations+1]={at=time(),coords=SL.Coords(),zone=GetZoneText(),subZone=GetSubZoneText(),
      coordinateBasis="observer_position",unit=unit, tapDenied=UnitIsTapDenied and UnitIsTapDenied(unit) or nil}
    if #e.observations>20 then table.remove(e.observations,1) end
    publish(e,"observed")
  end
end
local function groupActor(guid)
  if not guid then return nil end
  if guid==UnitGUID("player") then return "player" end
  if guid==UnitGUID("pet") then return "pet" end
  for i=1,4 do
    if guid==UnitGUID("party"..i) then return "party" end
    if guid==UnitGUID("partypet"..i) then return "party_pet" end
  end
  for i=1,40 do
    if guid==UnitGUID("raid"..i) then return "raid" end
    if guid==UnitGUID("raidpet"..i) then return "raid_pet" end
  end
end
local damageEvents={SWING_DAMAGE=true,RANGE_DAMAGE=true,SPELL_DAMAGE=true,SPELL_PERIODIC_DAMAGE=true,DAMAGE_SHIELD=true,DAMAGE_SPLIT=true}
local function combat()
  if StitchLoggerDB.settings and not StitchLoggerDB.settings.logCombatDefeats then return end
  local _,event,_,sg,sn,_,_,dg,dn = CombatLogGetCurrentEventInfo()
  if not SL.NPCID(dg) then return end
  local source=groupActor(sg)
  if damageEvents[event] and source then
    local t=touched[dg] or {};t.at=time();t.sourceType=source
    t.player=t.player or source=="player" or source=="pet";t.group=true;touched[dg]=t;return
  end
  local participation=touched[dg]
  if not ((event=="PARTY_KILL" and source) or (event=="UNIT_DIED" and participation and time()-participation.at<120)) then return end
  local e=encounter(dg,dn)
  if event=="PARTY_KILL" then
    if e.kill and e.kill.creditEvent=="PARTY_KILL" then return end
    e.kill={at=time(),creditEvent=event,creditedSourceGUID=sg,creditedSourceName=sn,sourceType=source,
      playerParticipated=participation and participation.player or false,groupParticipated=participation~=nil,lootEligibility="unknown"}
  elseif not e.kill then
    e.kill={at=time(),creditEvent=event,sourceType="observed_death_after_group_damage",lootEligibility="unknown"}
  else return end
  e.kill.observerCoords=SL.Coords();e.kill.zone=GetZoneText()
  local actor=SL.Actor("target")
  if actor and actor.guid==dg then e.level=actor.level;e.creatureType=actor.creatureType;e.classification=actor.classification end
  publish(e,"defeated")
end

local activityBases={[8613]="skinning",[2366]="herbalism",[2575]="mining",[7620]="fishing",[3365]="opening"}
local function activityFor(id)
  if activityBases[id] then return activityBases[id] end
  local name=SL.SpellName(id)
  if not name then return nil end
  for base,kind in pairs(activityBases) do if name==SL.SpellName(base) then return kind end end
end
local function castStart(target, guid, id)
  local kind=activityFor(id)
  if not kind then cast=nil; return end
  local actor=SL.Actor("mouseover") or SL.Actor("target")
  -- A target is only a candidate; actual attribution requires matching loot-source GUIDs.
  cast={castGUID=guid,spellID=id,kind=kind,targetName=target,targetCandidate=actor,
    startedAt=time(),skillsBefore=SL.SkillsSnapshot(),coords=SL.Coords()}
  local ev=SL.LogEvent("gathering_attempt",cast);cast.attemptId=ev and ev.eventId
end
local function sourceList(slot)
  if not GetLootSourceInfo then return {} end
  local raw={GetLootSourceInfo(slot)};local result={}
  for i=1,#raw,2 do
    if type(raw[i])=="string" then result[#result+1]={guid=raw[i],quantity=raw[i+1],npcId=SL.NPCID(raw[i])} end
  end
  return result
end
local function phaseFor(guid)
  if window.activity then
    local a=window.activity
    if a.kind=="skinning" then
      if a.targetCandidate and a.targetCandidate.guid==guid and a.succeededAt then return "skinning" end
      return "unclassified"
    end
    return a.kind.."_candidate"
  end
  -- A previously skinned source reopened after its cast must not become ordinary corpse loot.
  local e=records()[key(guid)]
  if e and e.phases.skinning then return "unclassified" end
  return "corpse"
end
local function capture()
  if not window then
    local ev=SL.LogEvent("loot_inspection_started",{targetCandidate=SL.Actor("target"),evidence="loot_window"})
    window={inspectionId=ev.eventId,openedAt=time(),slots={},sources={},sourceItems={},receipts={}}
    if cast and cast.succeededAt and time()-cast.succeededAt<=8 then window.activity=SL.Copy(cast)
    elseif cast and cast.kind=="skinning" and time()-cast.startedAt<=20 then window.activity=SL.Copy(cast)
    elseif cast and cast.kind=="fishing" and time()-cast.startedAt<=35 then window.activity=SL.Copy(cast) end
  end
  local n=GetNumLootItems()
  for slot=1,n do
    local link=GetLootSlotLink(slot)
    local _,name,qty=GetLootSlotInfo(slot)
    local sources=sourceList(slot)
    -- Preserve the initial slot snapshot even after auto-loot clears it.
    if not window.slots[slot] or (not window.slots[slot].link and link) then
      window.slots[slot]={slot=slot,link=link,itemId=SL.ItemID(link),name=name,quantity=qty,sources=sources}
    end
    for _,src in ipairs(sources) do window.sources[src.guid]=true end
  end
  local sums={}
  for _,s in pairs(window.slots) do
    for _,src in ipairs(s.sources) do
      sums[src.guid]=sums[src.guid] or {}
      if s.itemId and type(src.quantity)=="number" then
        local k=tostring(s.itemId)
        local a=sums[src.guid][k] or {quantity=0,link=s.link,itemId=s.itemId}
        a.quantity=a.quantity+src.quantity; sums[src.guid][k]=a
      end
    end
  end
  for guid in pairs(window.sources) do
    local e=encounter(guid)
    if e then
      local phase=phaseFor(guid)
      local p=e.phases[phase] or {observedItems={},receivedCorrelated={},inspectionCount=0,inspectionIds={}}
      e.phases[phase]=p
      if not p.inspectionIds[window.inspectionId] then
        p.inspectionIds[window.inspectionId]=true;p.inspectionCount=p.inspectionCount+1
        if p.inspectionCount>1 then p.reopened=true end
      end
      for id,item in pairs(sums[guid] or {}) do
        local old=p.observedItems[id]
        if not old or item.quantity>old.quantity then p.observedItems[id]=SL.Copy(item) end
      end
      p.state=next(p.observedItems) and "items_observed" or "inspected_no_item_slots"
      p.quantityBasis="maximum_seen_per_source_and_phase; not_sum_of_reopens"
      e.lootState="inspected"
      if window.activity then p.activity=SL.Copy(window.activity) end
      local fp=SL.Fingerprint(p)
      window.sourceItems[guid]=window.sourceItems[guid] or {}
      if window.sourceItems[guid].fingerprint~=fp then
        window.sourceItems[guid]={phase=phase,fingerprint=fp};publish(e,"loot_observed")
      end
    end
  end
  window.slotCount=n
end
local function closeWindow(reason)
  if not window then return end
  window.closedAt=time();window.closeReason=reason
  local allCleared=true;local num=0
  for _,s in pairs(window.slots) do num=num+1;if not s.cleared then allCleared=false end end
  window.allObservedSlotsCleared=num>0 and allCleared
  window.emptyWindow=num==0
  window.emptyAttribution=window.emptyWindow and "source_unknown; not_proof_of_no_drop" or nil
  SL.LogEvent("loot_inspection",window)
  if cast and window.activity and cast.castGUID==window.activity.castGUID then cast=nil end
  recentWindows[#recentWindows+1]=window
  while #recentWindows>8 do table.remove(recentWindows,1) end
  window=nil
end
SL.Subscribe(function(event)
  if event.eventType~="item_received" or event.receiptKind~="loot" then return end
  local candidates={}
  local function match(w)
    if not w or (w.closedAt and time()-w.closedAt>2) then return end
    local remaining=0;local sources={}
    for _,slot in pairs(w.slots) do
      if slot.itemId==event.item.itemId then
        remaining=remaining+(slot.quantity or 0)
        for _,src in ipairs(slot.sources) do sources[src.guid]=true end
      end
    end
    remaining=remaining-(w.receipts[tostring(event.item.itemId)] or 0)
    if remaining>=event.item.quantity then candidates[#candidates+1]={window=w,sources=sources} end
  end
  match(window);for _,w in ipairs(recentWindows) do match(w) end
  if #candidates~=1 then
    SL.LogEvent("receipt_link",{receiptId=event.eventId,status="unresolved",candidateWindows=#candidates,confidence="low"});return
  end
  local c=candidates[1];local id=tostring(event.item.itemId)
  c.window.receipts[id]=(c.window.receipts[id] or 0)+event.item.quantity
  local guid,n=nil,0;for g in pairs(c.sources) do guid=g;n=n+1 end
  local e=n==1 and encounter(guid) or nil
  local phase=e and c.window.sourceItems[guid] and c.window.sourceItems[guid].phase
  SL.LogEvent("receipt_link",{receiptId=event.eventId,inspectionId=c.window.inspectionId,
    encounterId=e and e.encounterId,sourceGUID=n==1 and guid or nil,
    phase=phase,status=n==1 and "correlated_single_source" or "ambiguous_multi_source",confidence="medium"})
  if e and phase then
    local p=e.phases[phase];p.receivedCorrelated[id]=(p.receivedCorrelated[id] or 0)+event.item.quantity
    publish(e,"receipt_correlated")
  end
end)
SL.OnReset(function() window=nil;recentWindows={};cast=nil;spellTarget=nil;touched={} end)
SL.OnFlush(function(reason) closeWindow(reason) end)
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","COMBAT_LOG_EVENT_UNFILTERED",
  "UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED",
  "LOOT_READY","LOOT_OPENED","LOOT_SLOT_CHANGED","LOOT_SLOT_CLEARED","LOOT_CLOSED"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(_,event,...)
  if not SL.Active() then return end
  if event=="PLAYER_LOGIN" then
    for k,e in pairs(records()) do if time()-(e.lastSeen or 0)>86400 then records()[k]=nil end end
  elseif event=="PLAYER_TARGET_CHANGED" then observe("target")
  elseif event=="UPDATE_MOUSEOVER_UNIT" then observe("mouseover")
  elseif event=="COMBAT_LOG_EVENT_UNFILTERED" then combat()
  elseif event=="UNIT_SPELLCAST_SENT" then
    local unit,target,guid,id=...;if unit=="player" then castStart(target,guid,id) end
  elseif event=="UNIT_SPELLCAST_START" then
    local unit,guid,id=...;if unit=="player" and (not cast or cast.castGUID~=guid) then castStart(nil,guid,id) end
  elseif event=="UNIT_SPELLCAST_SUCCEEDED" then
    local unit,guid,id=...
    if unit=="player" and activityFor(id) then
      if not cast or cast.castGUID~=guid then castStart(nil,guid,id) end
      cast.succeededAt=time()
      if window and window.activity and window.activity.castGUID==guid then window.activity=SL.Copy(cast);capture() end
      SL.LogEvent("gathering_cast_succeeded",{attemptId=cast.attemptId,activity=cast,skillsAfter=SL.SkillsSnapshot()})
    end
  elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then
    local unit,guid=...;if unit=="player" and cast and cast.castGUID==guid then
      SL.LogEvent("gathering_failed",{attemptId=cast.attemptId,reason=event});cast=nil
    end
  elseif event=="LOOT_READY" or event=="LOOT_OPENED" or event=="LOOT_SLOT_CHANGED" then capture()
  elseif event=="LOOT_SLOT_CLEARED" then
    local slot=...;if window and window.slots[slot] then window.slots[slot].cleared=true end
  elseif event=="LOOT_CLOSED" then closeWindow("closed") end
end)

-- Compact combined encounter query; raw events remain available via /stitchfind.
SLASH_STITCHMOB1="/stitchmob"
SlashCmdList.STITCHMOB=function(query)
  query=(query or ""):lower()
  if query=="" then DEFAULT_CHAT_FRAME:AddMessage("Usage: /stitchmob kodo (or NPC ID)");return end
  local list={}
  for _,e in pairs(StitchLoggerDB and StitchLoggerDB.encounters or {}) do
    if (e.name or ""):lower():find(query,1,true) or tostring(e.npcId)==query then list[#list+1]=e end
  end
  table.sort(list,function(a,b) return a.lastSeen>b.lastSeen end)
  for i=1,math.min(5,#list) do
    local e=list[i]
    DEFAULT_CHAT_FRAME:AddMessage((e.name or tostring(e.npcId)).." ["..e.npcId.."] "..
      (e.kill and ("defeated / "..e.kill.sourceType) or "observed").." / "..e.lootState)
    local observations=e.observations or {};local loc=observations[#observations]
    local coords=loc and loc.coords or (e.kill and e.kill.observerCoords)
    if coords and coords.x then
      DEFAULT_CHAT_FRAME:AddMessage(string.format("  Observer location: %s %.1f, %.1f",loc and loc.zone or (e.kill and e.kill.zone) or "",coords.x,coords.y))
    end
    for phase,p in pairs(e.phases) do
      local parts={}
      for id,item in pairs(p.observedItems) do
        parts[#parts+1]=(item.link or id).." x"..item.quantity.." observed; "..(p.receivedCorrelated[id] or 0).." received (correlated)"
      end
      DEFAULT_CHAT_FRAME:AddMessage("  "..phase..": "..(#parts>0 and table.concat(parts,", ") or p.state))
    end
  end
  if #list==0 then DEFAULT_CHAT_FRAME:AddMessage("No matching recent encounters. Older records remain in /stitchfind and the external archive.") end
end
