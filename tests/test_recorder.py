"""Behavior regression tests run all enabled modules under Lua 5.1."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

def runtime():
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT/'tests/wow_fixture.lua').read_text(encoding='utf-8-sig'))
    for name in (ROOT/'StitchLogger/StitchLogger.toc').read_text().splitlines():
        if name.endswith('.lua'):
            lua.execute((ROOT/'StitchLogger'/name).read_text(encoding='utf-8-sig'),'StitchLogger')
    lua.execute("emit('ADDON_LOADED','StitchLogger');emit('PLAYER_LOGIN')")
    return lua

class RecorderTests(unittest.TestCase):
    def check(self, code):
        runtime().execute(code)

    def test_localized_receipts_and_other_players(self):
        self.check('''
        receive(2318,4);assert(latest('item_received').item.quantity==4)
        emit('CHAT_MSG_LOOT','Friend receives loot: '..link(2318)..'x8.')
        assert(count('item_received')==1)
        LOOT_ITEM_SELF_MULTIPLE='%2$dx Gegenstand %1$s erhalten.'
        local p=StitchLogger.ParseLoot('6x Gegenstand '..link(2318)..' erhalten.')
        assert(p.item.quantity==6)
        ''')

    def test_corpse_reopening_and_delayed_receipt(self):
        self.check('''
        local g=UnitGUID('target');emit('PLAYER_TARGET_CHANGED');kill(UnitGUID('player'),g)
        loot={{link=link(2318),quantity=2,sources={g,2}}}
        emit('LOOT_READY');emit('LOOT_OPENED');emit('LOOT_SLOT_CLEARED',1);emit('LOOT_CLOSED')
        receive(2318,2)
        local e=encounter();assert(e.phases.corpse.observedItems['2318'].quantity==2)
        assert(e.phases.corpse.receivedCorrelated['2318']==2)
        advance(3);emit('LOOT_READY');emit('LOOT_OPENED');emit('LOOT_CLOSED')
        assert(e.phases.corpse.observedItems['2318'].quantity==2 and e.phases.corpse.inspectionCount==2)
        assert(e.kill and e.lootState=='inspected')
        ''')

    def test_empty_window_does_not_invent_empty_corpse(self):
        self.check('''
        emit('PLAYER_TARGET_CHANGED');kill(UnitGUID('player'),UnitGUID('target'))
        loot={};emit('LOOT_OPENED');emit('LOOT_CLOSED')
        assert(encounter().lootState=='not_inspected')
        assert(latest('loot_inspection').emptyAttribution)
        ''')

    def test_same_item_multiple_sources_is_ambiguous(self):
        self.check('''
        loot={{link=link(2318),quantity=2,sources={UnitGUID('target'),1,'Creature-0-1-1-1-3234-0002',1}}}
        emit('LOOT_OPENED');receive(2318,2)
        assert(latest('receipt_link').status=='ambiguous_multi_source')
        assert(latest('receipt_link').encounterId==nil)
        ''')

    def test_skinning_and_corpse_are_separate(self):
        self.check('''
        local g=UnitGUID('target');loot={{link=link(2318),quantity=1,sources={g,1}}}
        emit('LOOT_OPENED');emit('LOOT_CLOSED');advance(3)
        emit('UNIT_SPELLCAST_SENT','player','Kodo','cast-1',8617)
        emit('UNIT_SPELLCAST_SUCCEEDED','player','cast-1',8617)
        loot={{link=link(2318),quantity=3,sources={g,3}}};emit('LOOT_OPENED')
        assert(encounter().phases.skinning.observedItems['2318'].quantity==3)
        assert(encounter().phases.corpse.observedItems['2318'].quantity==1)
        ''')

    def test_skinning_target_mismatch_and_failure(self):
        self.check('''
        emit('UNIT_SPELLCAST_SENT','player','Kodo','cast-1',8613)
        emit('UNIT_SPELLCAST_SUCCEEDED','player','cast-1',8613)
        loot={{link=link(2318),quantity=1,sources={'Creature-0-1-1-1-999-0009',1}}};emit('LOOT_OPENED')
        assert(encounter().phases.skinning==nil and encounter().phases.unclassified)
        emit('LOOT_CLOSED');advance(3)
        emit('UNIT_SPELLCAST_SENT','player','Kodo','cast-2',8613)
        emit('UNIT_SPELLCAST_FAILED','player','cast-2',8613)
        assert(latest('gathering_failed'))
        ''')

    def test_group_kill_dedup_and_unrelated_death(self):
        self.check('''
        local g=UnitGUID('target');kill(UnitGUID('party1'),g);kill(UnitGUID('party1'),g)
        assert(encounter().kill.sourceType=='party')
        assert(count('encounter_updated')==1)
        cleu={clock,'UNIT_DIED',false,nil,nil,0,0,'Creature-0-1-1-1-99-999','Other',0,0}
        emit('COMBAT_LOG_EVENT_UNFILTERED');assert(count('encounter_started')==1)
        ''')

    def test_seen_kill_without_loot_stays_unknown(self):
        self.check("kill(UnitGUID('player'),UnitGUID('target'));assert(encounter().lootState=='not_inspected')")

    def test_merchant_success_and_failed_click(self):
        self.check('''
        emit('MERCHANT_SHOW');click('BuyMerchantItem',1,10)
        money=9800;bags={{id=2320,count=10}};emit('BAG_UPDATE_DELAYED');emit('PLAYER_MONEY');advance(2)
        local t=latest('transaction_result');assert(t.status=='confirmed_batch' and t.actualCostCopper==200)
        click('BuyMerchantItem',1,5);advance(2)
        assert(latest('transaction_result').status=='unreconciled_batch')
        ''')

    def test_training_requires_learning_and_money(self):
        self.check('''
        emit('TRAINER_SHOW');click('BuyTrainerService',1);money=9800;serviceCategory='used'
        emit('LEARNED_SPELL_IN_TAB',100);emit('TRAINER_UPDATE');emit('PLAYER_MONEY');advance(2)
        assert(latest('transaction_result').status=='confirmed_batch')
        ''')

    def test_training_money_alone_is_not_learning(self):
        self.check('''
        emit('TRAINER_SHOW');click('BuyTrainerService',1);money=9800;emit('PLAYER_MONEY');advance(2)
        assert(latest('transaction_result').status=='unconfirmed')
        ''')

    def test_craft_output_and_reagents(self):
        self.check('''
        bags={{id=2934,count=6}};emit('BAG_UPDATE_DELAYED');emit('TRADE_SKILL_SHOW');advance(1)
        emit('UNIT_SPELLCAST_SENT','player','','craft-1',2881)
        emit('UNIT_SPELLCAST_SUCCEEDED','player','craft-1',2881)
        bags={{id=2934,count=3},{id=2318,count=1}};emit('BAG_UPDATE_DELAYED');advance(2)
        local t=latest('transaction_result');assert(t.status=='confirmed_batch' and t.successfulCasts==1)
        assert(t.itemsRemoved[1].quantity==3 and t.itemsAdded[1].quantity==1)
        ''')

    def test_failed_craft_and_concurrent_inventory_change(self):
        self.check('''
        bags={{id=2934,count=6}};emit('BAG_UPDATE_DELAYED');emit('TRADE_SKILL_SHOW');advance(1)
        emit('UNIT_SPELLCAST_SENT','player','','craft-1',2881)
        emit('UNIT_SPELLCAST_INTERRUPTED','player','craft-1',2881);advance(2)
        assert(latest('transaction_result').status=='unconfirmed')
        emit('UNIT_SPELLCAST_SENT','player','','craft-2',2881)
        emit('UNIT_SPELLCAST_SUCCEEDED','player','craft-2',2881)
        bags={{id=2934,count=3},{id=2318,count=1},{id=999,count=1}};emit('BAG_UPDATE_DELAYED');advance(2)
        assert(latest('transaction_result').status=='cast_success_inventory_unresolved')
        ''')

    def test_immutable_snapshots(self):
        self.check('''
        emit('PLAYER_TARGET_CHANGED');local old=latest('encounter_updated')
        kill(UnitGUID('player'),UnitGUID('target'))
        assert(old.encounter.kill==nil and latest('encounter_updated').encounter.kill)
        ''')

    def test_pause_resume_and_logout(self):
        self.check('''
        SlashCmdList.STITCHLOGGER('stop');local n=#StitchLoggerDB.sessions
        emit('PLAYER_TARGET_CHANGED');receive(2318,1);emit('TRADE_SKILL_SHOW');advance(3);emit('PLAYER_LOGIN')
        assert(#StitchLoggerDB.sessions==n and StitchLoggerDB.currentSessionId==nil)
        SlashCmdList.STITCHLOGGER('start');assert(#StitchLoggerDB.sessions==n+1)
        emit('PLAYER_LOGOUT');assert(StitchLoggerDB.currentSessionId==nil)
        emit('PLAYER_LOGIN');assert(#StitchLoggerDB.sessions==n+2)
        ''')

    def test_recipe_snapshots_dedup_and_route_movement(self):
        self.check('''
        emit('TRADE_SKILL_SHOW');advance(1);emit('TRADE_SKILL_UPDATE');advance(1)
        assert(count('recipes_snapshot')==1)
        emit('ZONE_CHANGED');local n=count('route_observation')
        for _,f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,30) end end
        assert(count('route_observation')==n)
        pos={x=.7,y=.7}
        for _,f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,30) end end
        assert(count('route_observation')==n+1)
        ''')

    def test_receipt_without_window_is_unassigned(self):
        self.check("receive(2318,2);assert(latest('receipt_link').status=='unresolved')")

    def test_skinning_loot_ready_before_cast_success(self):
        self.check("""
        local g=UnitGUID('target')
        emit('UNIT_SPELLCAST_SENT','player','Kodo','skin-early',8613)
        loot={{link=link(2318),quantity=2,sources={g,2}}};emit('LOOT_READY')
        assert(encounter().phases.corpse==nil)
        emit('UNIT_SPELLCAST_SUCCEEDED','player','skin-early',8613)
        assert(encounter().phases.skinning.observedItems['2318'].quantity==2)
        """)

    def test_sales_and_repairs(self):
        self.check("""
        bags={{id=2318,count=3}};emit('BAG_UPDATE_DELAYED');emit('MERCHANT_SHOW')
        click('UseContainerItem',0,1);bags={};money=10030;emit('BAG_UPDATE_DELAYED');emit('PLAYER_MONEY');advance(2)
        assert(latest('transaction_result').kind=='merchant_sale' and latest('transaction_result').actualProceedsCopper==30)
        repairCost=50;emit('MERCHANT_SHOW');click('RepairAllItems',false)
        money=9980;repairCost=0;emit('PLAYER_MONEY');advance(2)
        assert(latest('transaction_result').kind=='repair' and latest('transaction_result').actualCostCopper==50)
        """)

    def test_failed_repair_is_unconfirmed(self):
        self.check("""
        repairCost=50;emit('MERCHANT_SHOW');click('RepairAllItems',false);advance(2)
        assert(latest('transaction_result').status=='unconfirmed')
        """)

    def test_crafting_batch_two_casts(self):
        self.check("""
        bags={{id=2934,count=6}};emit('BAG_UPDATE_DELAYED');emit('TRADE_SKILL_SHOW');advance(1)
        emit('UNIT_SPELLCAST_SENT','player','','craft-1',2881)
        emit('UNIT_SPELLCAST_SUCCEEDED','player','craft-1',2881)
        bags={{id=2934,count=3},{id=2318,count=1}};emit('BAG_UPDATE_DELAYED')
        emit('UNIT_SPELLCAST_SENT','player','','craft-2',2881);advance(2)
        assert(count('transaction_result')==0)
        emit('UNIT_SPELLCAST_SUCCEEDED','player','craft-2',2881)
        bags={{id=2318,count=2}};emit('BAG_UPDATE_DELAYED');advance(2)
        local t=latest('transaction_result');assert(t.status=='confirmed_batch' and t.successfulCasts==2)
        """)

    def test_gathering_candidates_and_services(self):
        self.check("""
        emit('UNIT_SPELLCAST_SENT','player','Copper Vein','mine-1',2575)
        emit('UNIT_SPELLCAST_SUCCEEDED','player','mine-1',2575)
        loot={{link=link(2770),quantity=2,sources={'GameObject-0-1-1-1-1731-0001',2}}}
        emit('LOOT_OPENED');emit('LOOT_CLOSED')
        assert(latest('loot_inspection').activity.kind=='mining')
        assert(latest('loot_inspection').activity.targetName=='Copper Vein')
        emit('BANKFRAME_OPENED');assert(latest('service_discovered').service=='bank')
        """)

    def test_stale_receipt_and_paused_cast_do_not_link(self):
        self.check("""
        loot={{link=link(2318),quantity=2,sources={UnitGUID('target'),2}}}
        emit('LOOT_OPENED');emit('LOOT_CLOSED');advance(3);receive(2318,2)
        assert(latest('receipt_link').status=='unresolved')
        emit('UNIT_SPELLCAST_SENT','player','Kodo','skin-1',8613)
        SlashCmdList.STITCHLOGGER('stop');SlashCmdList.STITCHLOGGER('start')
        emit('LOOT_OPENED');assert(encounter().phases.skinning==nil)
        """)

    def test_reload_preserves_corpse_deduplication(self):
        lua=runtime()
        lua.execute("""
        loot={{link=link(2318),quantity=2,sources={UnitGUID('target'),2}}}
        emit('LOOT_OPENED');emit('LOOT_CLOSED');emit('PLAYER_LOGOUT')
        function serialize(v)
          if type(v)=='table' then
            local p={'{'};for k,x in pairs(v) do p[#p+1]='['..serialize(k)..']='..serialize(x)..',' end
            p[#p+1]='}';return table.concat(p)
          elseif type(v)=='string' then return string.format('%q',v)
          else return tostring(v) end
        end
        """)
        saved=lua.eval('serialize(StitchLoggerDB)')
        fresh=runtime()
        fresh.execute('StitchLoggerDB='+saved)
        fresh.execute("""
        emit('PLAYER_LOGIN');loot={{link=link(2318),quantity=2,sources={UnitGUID('target'),2}}}
        emit('LOOT_OPENED');emit('LOOT_CLOSED')
        local p=encounter().phases.corpse
        assert(p.observedItems['2318'].quantity==2 and p.inspectionCount==2)
        """)

    def test_existing_start_does_not_drop_pending_purchase(self):
        self.check("""
        emit('MERCHANT_SHOW');click('BuyMerchantItem',1,5)
        SlashCmdList.STITCHLOGGER('start')
        money=9900;bags={{id=2320,count=5}};emit('BAG_UPDATE_DELAYED');advance(2)
        assert(latest('transaction_result').status=='confirmed_batch')
        """)

    def test_recipe_learning_and_first_observation(self):
        self.check("""
        emit('TRADE_SKILL_SHOW');advance(1)
        assert(count('recipe_first_observed')==1)
        emit('TRADE_SKILL_UPDATE');advance(1);assert(count('recipe_first_observed')==1)
        local old=GetItemInfo
        GetItemInfo=function(l) return 'Pattern',l,1,1,1,'Recipe','Leatherworking',1,'',1,10,9 end
        bags={{id=9999,count=1}};emit('BAG_UPDATE_DELAYED');click('UseContainerItem',0,1)
        bags={};emit('LEARNED_SPELL_IN_TAB',2881);emit('BAG_UPDATE_DELAYED');advance(1)
        assert(latest('learning_source_link').status=='correlated_recipe_item')
        """)

    def test_in_game_encounter_query(self):
        self.check("""
        emit('PLAYER_TARGET_CHANGED');kill(UnitGUID('player'),UnitGUID('target'))
        local n=#messages;SlashCmdList.STITCHMOB('kodo')
        assert(#messages>n and messages[n+1]:find('Kodo',1,true))
        SlashCmdList.STITCHFIND('kodo')
        """)

if __name__=='__main__': unittest.main(verbosity=2)
