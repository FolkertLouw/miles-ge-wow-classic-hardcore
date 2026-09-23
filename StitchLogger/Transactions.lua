-- Reconcile observable outcomes. Failed clicks are never counted as purchases.
local SL=StitchLogger
local frame=CreateFrame("Frame")
local cachedBags, cachedSkills, batch, craftCasts, recipes, spellbook = nil,nil,nil,{}, {},{}
local timerVersion=0
local merchantOpen=false
local cachedRepairCost=0
local hooksInstalled=false
local recipeUse=nil
local function snapshotSpells()
  local result={}
  if not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellBookItemInfo then return result end
  for tab=1,GetNumSpellTabs() do
    local _,_,offset,num=GetSpellTabInfo(tab)
    for i=(offset or 0)+1,(offset or 0)+(num or 0) do
      local kind,id=GetSpellBookItemInfo(i,BOOKTYPE_SPELL or "spell")
      if id and kind=="SPELL" then result[id]=true end
    end
  end
  return result
end
local function refresh()
  cachedBags=SL.BagSnapshot();cachedSkills=SL.SkillsSnapshot()
  if merchantOpen and GetRepairAllCost then cachedRepairCost=GetRepairAllCost() end
end
local function begin(kind)
  if batch and batch.kind~=kind then SL.FinishTransaction("different_activity") end
  if not batch then
    local start=SL.LogEvent("transaction_started",{kind=kind})
    batch={transactionId=start.eventId,kind=kind,startedAt=time(),before=SL.Copy(cachedBags or SL.BagSnapshot()),
      skillsBefore=SL.Copy(cachedSkills or SL.SkillsSnapshot()),attempts={},casts={},learnedSpells={},
      moneyEvidence="net_change_over_batch; individual_costs_only_if_reconciled"}
  end
  return batch
end
local function deltaMap(items)
  local out={};for _,i in ipairs(items) do if i.itemId then out[i.itemId]=(out[i.itemId] or 0)+i.quantity end end;return out
end
local function sameAmounts(a,b)
  for id,n in pairs(a) do if b[id]~=n then return false end end
  for id,n in pairs(b) do if a[id]~=n then return false end end
  return true
end
function SL.RememberRecipes(list,profession)
  StitchLoggerDB.recipeKnowledge=StitchLoggerDB.recipeKnowledge or {}
  local observer=(GetRealmName() or "")..":"..(UnitGUID("player") or "")
  StitchLoggerDB.recipeKnowledge[observer]=StitchLoggerDB.recipeKnowledge[observer] or {}
  local known=StitchLoggerDB.recipeKnowledge[observer]
  for _,r in ipairs(list) do
    local id=r.recipeLink and tonumber(r.recipeLink:match("enchant:(%d+)") or r.recipeLink:match("spell:(%d+)"))
    local k=id and ("id:"..id) or (profession or "")..":"..r.name..":"..(r.rank or "")
    recipes[k]=SL.Copy(r);recipes[k].spellID=id;recipes[k].profession=profession
    if not known[k] then
      known[k]={firstObserved=time(),name=r.name,spellID=id,profession=profession}
      SL.LogEvent("recipe_first_observed",{recipe=r,profession=profession,
        evidence="first_visible_observation; not_proof_of_learning_at_this_time"})
    end
  end
end
local function recipeFor(id)
  if recipes["id:"..id] then return recipes["id:"..id] end
  local name=SL.SpellName(id);local found=nil
  for _,r in pairs(recipes) do
    if name and r.name==name then if found then return nil end;found=r end
  end
  return found
end
function SL.FinishTransaction(reason)
  if not batch then return end
  local b=batch;batch=nil;timerVersion=timerVersion+1
  b.reason=reason;b.after=SL.BagSnapshot();b.skillsAfter=SL.SkillsSnapshot()
  b.moneyDeltaCopper=(b.after.moneyCopper or 0)-(b.before.moneyCopper or 0)
  b.itemsAdded,b.itemsRemoved=SL.DiffBags(b.before,b.after)
  b.status="unconfirmed";b.confidence="low"
  local added,removed=deltaMap(b.itemsAdded),deltaMap(b.itemsRemoved)
  if b.kind=="merchant_purchase" then
    local expected,cost,complete={},0,true
    for _,a in ipairs(b.attempts) do
      if not a.item or not a.item.itemId or not a.estimatedTotalPriceCopper or a.extendedCost then complete=false
      else
        expected[a.item.itemId]=(expected[a.item.itemId] or 0)+a.requestedQuantity
        cost=cost+a.estimatedTotalPriceCopper
      end
    end
    b.expectedCostCopper=cost
    if complete and sameAmounts(added,expected) and next(removed)==nil and b.moneyDeltaCopper==-cost then
      b.status="confirmed_batch";b.confidence="high";b.actualCostCopper=cost
    else b.status="unreconciled_batch" end
  elseif b.kind=="merchant_sale" then
    local expected,cost,complete={},0,true
    for _,a in ipairs(b.attempts) do
      if not a.itemId or not a.unitValueCopper then complete=false
      else expected[a.itemId]=(expected[a.itemId] or 0)+a.quantity;cost=cost+a.unitValueCopper*a.quantity end
    end
    b.expectedProceedsCopper=cost
    if complete and sameAmounts(removed,expected) and next(added)==nil and b.moneyDeltaCopper==cost then
      b.status="confirmed_batch";b.confidence="high";b.actualProceedsCopper=cost
    else b.status="unreconciled_batch" end
  elseif b.kind=="repair" then
    local cost=0;local guild=false
    for _,a in ipairs(b.attempts) do cost=cost+(a.quotedCostCopper or 0);guild=guild or a.guildBank end
    b.remainingRepairCostCopper=GetRepairAllCost and GetRepairAllCost() or nil
    if #b.attempts==1 and cost>0 and b.remainingRepairCostCopper==0 and next(added)==nil and next(removed)==nil then
      if not guild and b.moneyDeltaCopper==-cost then
        b.status="confirmed_batch";b.actualCostCopper=cost;b.confidence="high"
      elseif guild and b.moneyDeltaCopper==0 then b.status="repair_confirmed_guild_cost_unverified";b.confidence="medium" end
    end
  elseif b.kind=="training" then
    local services=SL.TrainerSnapshot();local confirmed,cost=0,0
    for _,a in ipairs(b.attempts) do
      local s=a.service;local learned=false
      for _,after in ipairs(services) do
        if after.name==s.name and after.rank==s.rank and after.category=="used" and s.category~="used" then learned=true end
      end
      for _,id in ipairs(b.learnedSpells) do
        local rank=C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
        if SL.SpellName(id)==s.name and ((s.rank or "")=="" or rank==s.rank) then learned=true end
      end
      a.learningConfirmed=learned
      if learned then confirmed=confirmed+1 end
      if type(s.costCopper)=="number" then cost=cost+s.costCopper else b.costUnknown=true end
    end
    b.servicesAfter=services;b.expectedCostCopper=cost
    if confirmed==#b.attempts and confirmed>0 then
      b.status="learning_confirmed_cost_unresolved";b.confidence="medium"
      if not b.costUnknown and b.moneyDeltaCopper==-cost and next(added)==nil and next(removed)==nil then
        b.status="confirmed_batch";b.actualCostCopper=cost;b.confidence="high"
      end
    end
  elseif b.kind=="crafting" then
    local required,outputs={},{};local successes,complete=0,true
    for _,c in ipairs(b.casts) do
      if c.succeeded then
        successes=successes+1
        local r=c.recipe
        for _,reagent in ipairs(r.reagents or {}) do
          local id=SL.ItemID(reagent.link)
          if not id or not reagent.required then complete=false
          else required[id]=(required[id] or 0)+reagent.required end
        end
        local id=SL.ItemID(r.outputLink)
        if not id or not r.minMade or not r.maxMade then complete=false
        else
          outputs[id]=outputs[id] or {min=0,max=0}
          outputs[id].min=outputs[id].min+r.minMade;outputs[id].max=outputs[id].max+r.maxMade
        end
      end
    end
    b.successfulCasts=successes
    local valid=complete and successes>0 and sameAmounts(removed,required) and b.moneyDeltaCopper==0
    for id,range in pairs(outputs) do if not added[id] or added[id]<range.min or added[id]>range.max then valid=false end end
    for id in pairs(added) do if not outputs[id] then valid=false end end
    if valid then b.status="confirmed_batch";b.confidence="high"
    elseif successes>0 then b.status="cast_success_inventory_unresolved";b.confidence="medium" end
    b.materialCostCopper=nil -- no invented market or acquisition value
  end
  for _,c in ipairs(b.casts) do craftCasts[c.castGUID]=nil end
  b.finishedAt=time();SL.LogEvent("transaction_result",b);refresh()
end
local function schedule()
  if not batch then return end
  timerVersion=timerVersion+1;local version=timerVersion
  C_Timer.After(1,function()
    if version==timerVersion and SL.Active() then
      -- A subsequent cast in a crafting batch may still be in flight.
      for _,c in pairs(craftCasts) do if not c.finished then return end end
      SL.FinishTransaction("settled")
    end
  end)
end
SL.Subscribe(function(e)
  if not SL.Active() then return end
  if e.eventType=="merchant_opened" then merchantOpen=true end
  if e.eventType=="merchant_opened" or e.eventType=="trainer_opened" or e.eventType=="player_login" then
    if batch then SL.FinishTransaction("new_interaction") end;refresh();spellbook=snapshotSpells()
  elseif e.eventType=="merchant_purchase_attempt" or e.eventType=="trainer_purchase_attempt" then
    local b=begin(e.eventType=="merchant_purchase_attempt" and "merchant_purchase" or "training")
    b.attempts[#b.attempts+1]=SL.Copy(e);schedule()
  end
end)
SL.OnReset(function() merchantOpen=false;recipeUse=nil;batch=nil;craftCasts={};timerVersion=timerVersion+1;refresh() end)
SL.OnFlush(function(reason) SL.FinishTransaction(reason) end)
local function installHooks()
  if hooksInstalled then return end;hooksInstalled=true
  local function useItem(bag,slot)
    if not SL.Active() then return end
    local found
    for _,i in ipairs(cachedBags and cachedBags.slots or {}) do if i.bag==bag and i.slot==slot then found=i end end
    if not found then return end
    if merchantOpen then
      local b=begin("merchant_sale")
      b.attempts[#b.attempts+1]={itemId=found.item.itemId,quantity=found.count,unitValueCopper=found.item.vendorValueCopper,
        evidence="right_click_at_merchant; outcome_must_be_reconciled"}
      schedule()
    elseif found.item.classID==9 then
      local ev=SL.LogEvent("recipe_item_use_attempt",{item=found.item,bag=bag,slot=slot,
        notes="Recipe item use is an attempt, not proof of learning."})
      recipeUse={attemptId=ev.eventId,itemId=found.item.itemId,at=time(),before=SL.Copy(cachedBags)}
    end
  end
  if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container,"UseContainerItem",useItem)
  elseif UseContainerItem then hooksecurefunc("UseContainerItem",useItem) end
  if RepairAllItems then hooksecurefunc("RepairAllItems",function(guild)
    if not SL.Active() or not merchantOpen then return end
    local b=begin("repair");b.attempts[#b.attempts+1]={quotedCostCopper=cachedRepairCost,guildBank=guild or false};schedule()
  end) end
end
for _,e in ipairs({"ADDON_LOADED","PLAYER_LOGIN","UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED","BAG_UPDATE_DELAYED","PLAYER_MONEY","SKILL_LINES_CHANGED","SPELLS_CHANGED",
  "LEARNED_SPELL_IN_TAB","TRAINER_UPDATE","TRAINER_CLOSED","MERCHANT_CLOSED"}) do frame:RegisterEvent(e) end
frame:SetScript("OnEvent",function(_,event,...)
  if event=="ADDON_LOADED" then installHooks();return end
  if not SL.Active() then return end
  if event=="MERCHANT_CLOSED" then merchantOpen=false end
  if event=="PLAYER_LOGIN" then refresh();spellbook=snapshotSpells();return end
  if event=="UNIT_SPELLCAST_SENT" then
    local unit,target,guid,id=...;if unit~="player" then return end
    local recipe=recipeFor(id);if not recipe then return end
    if not batch or batch.kind~="crafting" then refresh() end
    local b=begin("crafting")
    local c={castGUID=guid,spellID=id,targetName=target,recipe=SL.Copy(recipe)}
    craftCasts[guid]=c;b.casts[#b.casts+1]=c
    SL.LogEvent("craft_attempt",{transactionId=b.transactionId,cast=c});return
  elseif event=="UNIT_SPELLCAST_SUCCEEDED" or event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then
    local unit,guid=...;local c=craftCasts[guid]
    if unit=="player" and c then
      c.finished=true;c.succeeded=event=="UNIT_SPELLCAST_SUCCEEDED";c.resultEvent=event
      SL.LogEvent("craft_cast_result",{transactionId=batch and batch.transactionId,cast=c});schedule()
    end
    return
  elseif event=="LEARNED_SPELL_IN_TAB" then
    local id=...
    SL.LogEvent("spell_learned",{spellID=id,name=SL.SpellName(id),sourceContext=batch and batch.kind or "unknown"})
    if batch and batch.kind=="training" then batch.learnedSpells[#batch.learnedSpells+1]=id end
    if recipeUse and time()-recipeUse.at<=10 then
      local use=SL.Copy(recipeUse);recipeUse=nil
      C_Timer.After(0.5,function()
        if not SL.Active() then return end
        local _,removed=SL.DiffBags(use.before,SL.BagSnapshot())
        local consumed=false
        for _,item in ipairs(removed) do if item.itemId==use.itemId and item.quantity==1 then consumed=true end end
        SL.LogEvent("learning_source_link",{attemptId=use.attemptId,spellID=id,recipeItemId=use.itemId,
          itemConsumed=consumed,status=consumed and "correlated_recipe_item" or "unresolved",confidence="medium"})
      end)
    end
  elseif event=="SPELLS_CHANGED" then
    local after=snapshotSpells()
    for id in pairs(after) do if not spellbook[id] then
      SL.LogEvent("spellbook_added",{spellID=id,name=SL.SpellName(id),sourceContext=batch and batch.kind or "unknown"})
      if batch and batch.kind=="training" then batch.learnedSpells[#batch.learnedSpells+1]=id end
    end end
    spellbook=after
  end
  if batch then schedule() else refresh() end
end)
