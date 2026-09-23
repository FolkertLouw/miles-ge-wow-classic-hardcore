"""SavedVariables -> raw backup -> SQLite/JSONL end-to-end verification."""
from pathlib import Path
from contextlib import closing, redirect_stdout
import copy
import importlib.util
import io
import json
import sqlite3
import tempfile
import unittest
import luadata
from test_recorder import runtime
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('archive',ROOT/'tools/archive.py')
archive=importlib.util.module_from_spec(spec);spec.loader.exec_module(archive)

class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name);self.source=self.root/'StitchLogger.lua';self.out=self.root/'archive'
    def tearDown(self): self.temp.cleanup()
    def write(self,data):
        self.source.write_text('StitchLoggerDB = '+luadata.serialize(data),encoding='utf-8')
    def ingest(self):
        with redirect_stdout(io.StringIO()): archive.import_file(self.source,self.out)
    def rows(self,table):
        with closing(sqlite3.connect(self.out/'archive.sqlite3')) as db:
            return db.execute(f'SELECT payload FROM {table}').fetchall()
    def test_legacy_dedup_and_character_isolation(self):
        data={'sessions':[{'sessionId':'s1','character':{'guid':'Player-A','realm':'Stitches'},'events':[
          {'eventId':'sl-1','eventType':'manual_note','timestamp':'2026-09-23','character':'Tester','text':'Kodo leather'}]}]}
        self.write(data);self.ingest();self.ingest();self.assertEqual(len(self.rows('events')),1)
        data['sessions'][0]['character']['guid']='Player-B'
        self.write(data);self.ingest();self.assertEqual(len(self.rows('events')),2)
    def test_executable_input_rejected(self):
        self.source.write_text("StitchLoggerDB = os.execute('do not execute')",encoding='utf-8')
        with self.assertRaises(Exception): self.ingest()
        self.assertFalse(self.out.exists())
    def test_actual_recorder_save_and_indexes(self):
        lua=runtime()
        lua.execute('''
          emit('PLAYER_TARGET_CHANGED');kill(UnitGUID('player'),UnitGUID('target'))
          loot={{link=link(2318),quantity=2,sources={UnitGUID('target'),2}}}
          emit('LOOT_READY');emit('LOOT_OPENED');receive(2318,2);emit('LOOT_CLOSED')
          emit('MERCHANT_SHOW');click('BuyMerchantItem',1,5)
          bags={{id=2320,count=5}};money=9900;emit('BAG_UPDATE_DELAYED');emit('PLAYER_MONEY');advance(2)
          emit('PLAYER_LOGOUT')
          function serialize(v)
            if type(v)=='table' then local t={'{'};for k,x in pairs(v) do t[#t+1]='['..serialize(k)..']='..serialize(x)..',' end;t[#t+1]='}';return table.concat(t)
            elseif type(v)=='string' then return string.format('%q',v)
            else return tostring(v) end
          end
        ''')
        self.source.write_text('StitchLoggerDB = '+lua.eval('serialize(StitchLoggerDB)'),encoding='utf-8')
        self.ingest();n=len(self.rows('events'));self.ingest();self.assertEqual(len(self.rows('events')),n)
        self.assertEqual(len(self.rows('encounters')),1)
        encounter=json.loads(self.rows('encounters')[0][0])
        self.assertEqual(encounter['phases']['corpse']['observedItems']['2318']['quantity'],2)
        self.assertEqual(encounter['kill']['sourceType'],'player')
        transaction=json.loads(self.rows('transactions')[0][0])
        self.assertEqual(transaction['actualCostCopper'],100)
        self.assertEqual(transaction['status'],'confirmed_batch')
        self.assertEqual(len((self.out/'encounters.jsonl').read_text().splitlines()),1)
        self.assertEqual(next((self.out/'raw').glob('*.lua')).read_bytes(),self.source.read_bytes())
        # Reimport an older save with only the first encounter observation.
        data=luadata.unserialize(self.source.read_text().split('=',1)[1])
        for session in data['sessions']:
            session['events']=[e for e in session['events'] if e.get('eventType')!='encounter_updated' or e['encounter']['revision']==1]
        self.write(data);self.ingest()
        self.assertEqual(json.loads(self.rows('encounters')[0][0])['revision'],encounter['revision'])

if __name__=='__main__': unittest.main(verbosity=2)
