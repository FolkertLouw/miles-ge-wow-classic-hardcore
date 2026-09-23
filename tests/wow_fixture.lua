-- Controllable Classic API fixture: timers, bags, money, loot and casts.
frames={};hooks={};SlashCmdList={};UIParent={};clock=1790150000;timers={};messages={}
function CreateFrame(kind,name)
 local f={events={},scripts={}}
 function f:RegisterEvent(e) self.events[e]=true end
 function f:SetScript(k,v) self.scripts[k]=v end
 setmetatable(f,{__index=function() return function() return 0 end end})
 frames[#frames+1]=f;if name then _G[name]=f end;return f
end
function emit(e,...)
 for _,f in ipairs(frames) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f,e,...) end end
end
function hooksecurefunc(a,b,c)
 local name=type(a)=="table" and b or a;local fn=c or b
 hooks[name]=hooks[name] or {};table.insert(hooks[name],fn)
end
function click(name,...) for _,fn in ipairs(hooks[name] or {}) do fn(...) end end
function advance(n)
 local finish=clock+n
 while true do
  local idx=nil;for i,t in ipairs(timers) do if t.at<=finish and (not idx or t.at<timers[idx].at) then idx=i end end
  if not idx then break end
  local t=table.remove(timers,idx);clock=t.at;t.fn()
 end
 clock=finish
end
C_Timer={After=function(n,fn) timers[#timers+1]={at=clock+n,fn=fn} end}
DEFAULT_CHAT_FRAME={AddMessage=function(_,m) messages[#messages+1]=m end}
time=function() return math.floor(clock) end;GetServerTime=time;date=os.date
GetBuildInfo=function() return '1.15.9','69722','date',11509 end
GetLocale=function() return 'enUS' end
units={player={name='Tester',guid='Player-1-123'},pet={name='Pet',guid='Pet-0-1-1-1-1-0001'},
 target={name='Kodo',guid='Creature-0-1-1-1-3234-0001'},party1={name='Friend',guid='Player-1-456'}}
UnitName=function(u) return units[u] and units[u].name end
UnitGUID=function(u) return units[u] and units[u].guid end
UnitExists=function(u) return units[u]~=nil end
UnitLevel=function() return 15 end;UnitCreatureType=function() return 'Beast' end
UnitClass=function() return 'Hunter' end;UnitReaction=function() return 3 end
UnitClassification=function() return 'normal' end;UnitFactionGroup=function() return 'Horde' end
UnitRace=function() return 'Tauren' end;UnitXP=function() return 100 end;UnitXPMax=function() return 1000 end
money=10000;GetMoney=function() return money end
GetRealmName=function() return 'Stitches' end;GetZoneText=function() return 'The Barrens' end;GetSubZoneText=GetZoneText
pos={x=.5,y=.5};C_Map={GetBestMapForUnit=function() return 1413 end,GetPlayerMapPosition=function() return pos end}
skill=25;GetNumSkillLines=function() return 1 end
GetSkillLineInfo=function() return 'Leatherworking',false,true,skill,0,0,75 end
function link(id) return '|cffffffff|Hitem:'..id..':0|h[Item '..id..']|h|r' end
GetItemInfo=function(l) return 'Item',l,1,1,1,'Trade Goods','Leather',20,'',1,10 end
spellNames={[8613]='Skinning',[8617]='Skinning',[2366]='Herb Gathering',[2575]='Mining',[7620]='Fishing',[3365]='Opening',[2881]='Light Leather',[100]='Training'}
GetSpellInfo=function(id) return spellNames[id] end
C_Spell={GetSpellName=GetSpellInfo}
bags={};C_Container={}
C_Container.GetContainerNumSlots=function(b) return b==0 and #bags or 0 end
C_Container.GetContainerItemInfo=function(b,s)
 local i=bags[s];if i then return {hyperlink=link(i.id),stackCount=i.count,itemID=i.id} end
end
BuyMerchantItem=function() end;BuyTrainerService=function() end
C_Container.UseContainerItem=function() end
repairCost=0;GetRepairAllCost=function() return repairCost,repairCost>0 end
RepairAllItems=function() end
GetMerchantItemInfo=function() return 'Thread',1,100,5,-1,true,false end
GetMerchantItemLink=function() return link(2320) end
GetMerchantNumItems=function() return 1 end
serviceCategory='available';GetNumTrainerServices=function() return 1 end
GetTrainerServiceInfo=function() return 'Training','Rank 1',serviceCategory,true end
GetTrainerServiceCost=function() return 200 end
GetTrainerServiceLevelReq=function() return 10 end
GetTrainerServiceSkillReq=function() return 'Leatherworking',25,true end
GetTrainerServiceNumAbilityReq=function() return 0 end
GetTradeSkillLine=function() return 'Leatherworking',skill,75 end
GetNumTradeSkills=function() return 1 end
GetTradeSkillInfo=function() return 'Light Leather','optimal',4 end
GetTradeSkillItemLink=function() return link(2318) end
GetTradeSkillRecipeLink=function() return '|Henchant:2881|h[Light Leather]|h' end
GetTradeSkillNumReagents=function() return 1 end
GetTradeSkillReagentInfo=function() return 'Ruined Leather Scraps',1,3,12 end
GetTradeSkillReagentItemLink=function() return link(2934) end
GetTradeSkillNumMade=function() return 1,1 end
loot={}
GetNumLootItems=function() return #loot end
GetLootSlotLink=function(i) return loot[i] and loot[i].link end
GetLootSlotInfo=function(i) local s=loot[i];if s then return 1,'Item',s.quantity end end
GetLootSourceInfo=function(i) local s=loot[i];return unpack(s and s.sources or {}) end
cleu={};CombatLogGetCurrentEventInfo=function() return unpack(cleu,1,11) end
function kill(source,guid)
 cleu={clock,'PARTY_KILL',false,source,'Killer',0,0,guid,'Kodo',0,0};emit('COMBAT_LOG_EVENT_UNFILTERED')
end
LOOT_ITEM_SELF='You receive loot: %s.';LOOT_ITEM_SELF_MULTIPLE='You receive loot: %sx%d.'
LOOT_ITEM_CREATED_SELF='You create: %s.';LOOT_ITEM_CREATED_SELF_MULTIPLE='You create: %sx%d.'
LOOT_ITEM_PUSHED_SELF='You receive item: %s.';LOOT_ITEM_PUSHED_SELF_MULTIPLE='You receive item: %sx%d.'
function receive(id,n) emit('CHAT_MSG_LOOT',string.format(LOOT_ITEM_SELF_MULTIPLE,link(id),n)) end
function latest(kind)
 for i=#StitchLoggerDB.sessions,1,-1 do
  local events=StitchLoggerDB.sessions[i].events
  for j=#events,1,-1 do if events[j].eventType==kind then return events[j] end end
 end
end
function count(kind)
 local n=0;for _,s in ipairs(StitchLoggerDB.sessions) do for _,e in ipairs(s.events) do if e.eventType==kind then n=n+1 end end end;return n
end
function encounter() for _,e in pairs(StitchLoggerDB.encounters or {}) do return e end end
