"""Run with Python + lupa (Lua 5.1), no game process interaction."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
frames = {}; hooks = {}; SlashCmdList = {}; UIParent = {}
function CreateFrame(kind, name)
 local f = {events={}, scripts={}}
 function f:RegisterEvent(e) self.events[e]=true end
 function f:SetScript(k,v) self.scripts[k]=v end
 setmetatable(f, {__index=function() return function() return 0 end end})
 frames[#frames+1]=f
 if name then _G[name]=f end
 return f
end
function emit(e, ...)
 for _,f in ipairs(frames) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f,e,...) end end
end
function hooksecurefunc(name,fn) hooks[name]=fn end
DEFAULT_CHAT_FRAME={AddMessage=function() end}
time=function() return 1790150000 end; GetServerTime=time; date=os.date
GetBuildInfo=function() return '1.15.9','69722','date',11509 end
GetLocale=function() return 'enUS' end
UnitName=function(u) return u=='player' and 'Tester' or 'Kodo' end
UnitGUID=function(u) return u=='player' and 'Player-1-123' or 'Creature-0-1-1-1-3234-0001' end
UnitExists=function() return true end
UnitLevel=function() return 15 end
UnitCreatureType=function() return 'Beast' end
UnitClass=function() return 'Hunter' end
UnitReaction=function() return 3 end
UnitClassification=function() return 'normal' end
UnitFactionGroup=function() return 'Horde' end
UnitRace=function() return 'Tauren' end
UnitXP=function() return 100 end; UnitXPMax=function() return 1000 end
GetMoney=function() return 10000 end
GetRealmName=function() return 'Stitches' end
GetZoneText=function() return 'The Barrens' end; GetSubZoneText=GetZoneText
GetNumSkillLines=function() return 0 end
GetItemInfo=function(link) return 'Leather',link,1,1,1,'Trade Goods','Leather',20,'',1,10 end
GetSpellInfo=function() return 'Unknown' end
BuyMerchantItem=function() end
GetMerchantItemInfo=function() return 'Thread',1,100,5,-1,true,false end
GetMerchantItemLink=function() return 'item:2320' end
C_Timer={After=function(_,fn) fn() end}
GetNumTradeSkills=function() return 1 end
GetTradeSkillLine=function() return 'Leatherworking',25,75 end
GetTradeSkillInfo=function() return 'Light Leather','optimal',4 end
GetTradeSkillItemLink=function() return 'item:2318' end
GetTradeSkillNumReagents=function() return 1 end
GetTradeSkillReagentInfo=function() return 'Ruined Leather Scraps',1,3,12 end
GetTradeSkillReagentItemLink=function() return 'item:2934' end
GetTradeSkillNumMade=function() return 1,1 end
GetNumLootItems=function() return 1 end
GetLootSlotLink=function() return 'item:2318' end
GetLootSlotInfo=function() return 1,'Light Leather',2 end
GetLootSourceInfo=function() return 'Creature-0-1-1-1-3234-0001',2 end
''')
for filename in (root/'StitchLogger/StitchLogger.toc').read_text().splitlines():
    if filename.endswith('.lua'):
        lua.execute((root/'StitchLogger'/filename).read_text(), 'StitchLogger')
lua.execute('''
emit('ADDON_LOADED','StitchLogger'); emit('PLAYER_LOGIN')
assert(#StitchLoggerDB.sessions==1)
emit('TRADE_SKILL_SHOW')
local events=StitchLoggerDB.sessions[1].events
local recipe=events[#events].recipes[1]
assert(recipe.reagents[1].required==3 and recipe.minMade==1)
emit('LOOT_OPENED'); local loot=events[#events]
assert(loot.item.quantity==2 and loot.lootSources[1].npcId==3234)
local n=#events; emit('LOOT_OPENED'); assert(#events==n)
hooks.BuyMerchantItem(1,10)
assert(events[#events].item.quantity==10 and events[#events].estimatedTotalPriceCopper==200)
SlashCmdList.STITCHLOGGER('stop'); local sessions=#StitchLoggerDB.sessions
emit('PLAYER_TARGET_CHANGED'); emit('CHAT_MSG_LOOT','nothing'); emit('TRADE_SKILL_SHOW')
assert(#StitchLoggerDB.sessions==sessions and StitchLoggerDB.currentSessionId==nil)
emit('PLAYER_LOGIN'); assert(StitchLoggerDB.currentSessionId==nil)
SlashCmdList.STITCHLOGGER('start'); assert(#StitchLoggerDB.sessions==2)
emit('PLAYER_LOGOUT'); assert(StitchLoggerDB.currentSessionId==nil)
emit('PLAYER_LOGIN'); assert(#StitchLoggerDB.sessions==3)
SlashCmdList.STITCHFIND('leather')
''')
print('PASS: all modules load under Lua 5.1; recipes, loot quantities/source IDs, merchant cost, pause/resume, logout/login and search')
