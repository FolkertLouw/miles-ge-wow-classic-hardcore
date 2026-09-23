import importlib.util
from contextlib import closing
import sqlite3
import tempfile
from pathlib import Path
import luadata

spec = importlib.util.spec_from_file_location('archive', Path(__file__).resolve().parents[1]/'tools/archive.py')
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)
with tempfile.TemporaryDirectory() as temp:
    folder=Path(temp); source=folder/'StitchLogger.lua'
    data={'sessions':[{'sessionId':'s1','character':{'guid':'Player-A','realm':'Stitches'},'events':[
        {'eventId':'sl-1','eventType':'manual_note','timestamp':'2026-09-23','character':'Tester','text':'Kodo leather'}]}]}
    source.write_text('StitchLoggerDB = '+luadata.serialize(data),encoding='utf-8')
    archive.import_file(source,folder/'out'); archive.import_file(source,folder/'out')
    with closing(sqlite3.connect(folder/'out/archive.sqlite3')) as db:
        assert db.execute('select count(*) from events').fetchone()[0]==1
    data['sessions'][0]['character']['guid']='Player-B'
    source.write_text('StitchLoggerDB = '+luadata.serialize(data),encoding='utf-8')
    archive.import_file(source,folder/'out')
    with closing(sqlite3.connect(folder/'out/archive.sqlite3')) as db:
        assert db.execute('select count(*) from events').fetchone()[0]==2
    source.write_text("StitchLoggerDB = os.execute('do not execute')",encoding='utf-8')
    try: archive.import_file(source,folder/'out')
    except Exception: pass
    else: raise AssertionError('Executable Lua should be rejected')
print('PASS: archive round-trip, repeat-import deduplication, character isolation, executable input rejection')
