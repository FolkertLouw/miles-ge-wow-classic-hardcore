from contextlib import closing
from pathlib import Path
import sys, tempfile, unittest, sqlite3, json
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from sync_archive import export

class SyncTests(unittest.TestCase):
    def test_export_is_stable_and_preserves_unknown_ranks(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            event={'eventType':'trainer_closed','timestamp':'2026-09-23','character':'Private', 'trainer':{'name':'Urek','guid':'Creature-private'},'services':[{'category':'header','name':'Hunter','costCopper':9999999},{'index':2,'name':'Mend Pet','category':'available','costCopper':1200}],'rawMessage':'Private chat','coords':{'nested-key-Player-123':'encounter-Player-123'}}
            with closing(sqlite3.connect(root/'archive.sqlite3')) as db:
                db.execute('CREATE TABLE events (identity TEXT, payload TEXT, timestamp TEXT)')
                db.execute('INSERT INTO events VALUES (?,?,?)',('one',json.dumps(event),'2026-09-23'))
                db.commit()
            self.assertEqual(export(root,root/'shared'),(1,1))
            p=root/'shared/observations.jsonl';first=p.read_bytes()
            export(root,root/'shared');self.assertEqual(first,p.read_bytes())
            data=json.loads(first);self.assertNotIn('guid',data['trainer'])
            self.assertNotIn('Player-',first.decode());self.assertNotIn('Private',first.decode());self.assertEqual(len(data['services']),1)
            self.assertNotIn('rank',data['services'][0])
