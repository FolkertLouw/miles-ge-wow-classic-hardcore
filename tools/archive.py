"""Back up and index StitchLogger SavedVariables without executing Lua."""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import luadata


def import_file(source, destination):
    raw = source.read_bytes()
    text = raw.decode('utf-8-sig')
    match = re.match(r'\s*StitchLoggerDB\s*=\s*', text)
    if not match:
        raise ValueError('Expected StitchLoggerDB SavedVariables assignment')
    data = luadata.unserialize(text[match.end():])
    if not isinstance(data, dict):
        raise ValueError('Expected a SavedVariables table')
    digest = hashlib.sha256(raw).hexdigest()
    destination.mkdir(parents=True, exist_ok=True)
    backups = destination / 'raw'
    backups.mkdir(exist_ok=True)
    (backups / (digest + '.lua')).write_bytes(raw)
    with closing(sqlite3.connect(destination / 'archive.sqlite3')) as db:
        db.execute('CREATE TABLE IF NOT EXISTS events (identity TEXT PRIMARY KEY, event_type TEXT, timestamp TEXT, character TEXT, realm TEXT, zone TEXT, payload TEXT)')
        before = db.total_changes
        for session in data.get('sessions', []):
            char = session.get('character') or {}
            for event in session.get('events', []):
                payload = dict(event, archiveSessionId=session.get('sessionId'), archiveClient=session.get('client'), archiveCharacter=char)
                # Timestamp and character GUID protect against event-counter resets across machines.
                identity = json.dumps([char.get('guid'), char.get('realm'), event.get('character'), session.get('sessionId'), event.get('eventId'), event.get('timestamp')])
                db.execute('INSERT INTO events VALUES (?,?,?,?,?,?,?) ON CONFLICT(identity) DO UPDATE SET payload=excluded.payload',
                           (identity, event.get('eventType'), event.get('timestamp'), event.get('character'), char.get('realm'), event.get('zone'), json.dumps(payload, ensure_ascii=False)))
        count = db.execute('SELECT count(*) FROM events').fetchone()[0]
        print(f'Archive contains {count} unique events; {db.total_changes-before} inserted/refreshed. Raw backup: {digest}.lua')
        rows = db.execute('SELECT payload FROM events ORDER BY timestamp, identity').fetchall()
        db.commit()
    output = destination / 'events.jsonl'
    temporary = output.with_suffix('.jsonl.tmp')
    temporary.write_text(''.join(row[0]+'\n' for row in rows), encoding='utf-8')
    temporary.replace(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=Path('local-archive'))
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('import').add_argument('source', type=Path)
    sub.add_parser('find').add_argument('query')
    args = parser.parse_args()
    if args.command == 'import':
        import_file(args.source, args.archive)
    else:
        if not (args.archive/'archive.sqlite3').exists():
            parser.error('Import a SavedVariables file first')
        with closing(sqlite3.connect(args.archive/'archive.sqlite3')) as db:
            for row in db.execute('SELECT payload FROM events WHERE instr(lower(payload),lower(?))>0 ORDER BY timestamp DESC LIMIT 50', (args.query,)):
                print(row[0])


if __name__ == '__main__':
    main()
