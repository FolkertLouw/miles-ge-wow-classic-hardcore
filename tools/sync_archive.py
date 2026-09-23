"""Import a WoW save and publish only gameplay observations to the current Git branch.
Raw saves, SQLite, account paths and unit GUIDs remain local. No force pushes or merges.
Requires Python and luadata (pip install luadata==1.0.5).
"""
from contextlib import closing
import argparse
import hashlib
import json
import sqlite3
import subprocess
from pathlib import Path
from archive import import_file

FIELDS = {
 'trainer_closed': ('trainer','services'),
 'merchant_opened': ('vendor','merchantInventory'),
 'recipes_snapshot': ('profession','skillRank','maxRank','recipes','scope'),
 'encounter_updated': ('encounter',),
 'quest_detail_panel': ('quest','npc'),
 'quest_accepted': ('questID',),
 'quest_turned_in': ('questID','xpReward','moneyReward'),
 'route_observation': ('reason',),
 'service_discovered': ('npc','serviceType'),
 'trainer_purchase_attempt': ('trainer','service'),
 'spellbook_added': ('spellID','name','sourceContext'),
}
PRIVATE = {'guid','observerGUID','playerGUID','sourceGUID','targetGUID','rawMessage','archiveCharacter','character','player','raw','castGUID'}
def clean(value):
    if isinstance(value,dict):
        return {clean(k):clean(v) for k,v in value.items() if k not in PRIVATE and 'guid' not in k.lower()}
    if isinstance(value,list):return [clean(v) for v in value]
    if isinstance(value,str) and ('Player-' in value or 'Creature-' in value):return 'unit-ref-'+hashlib.sha256(value.encode()).hexdigest()
    return value

def export(archive, destination):
    destination.mkdir(parents=True,exist_ok=True)
    records=[]; trainers=[]
    with closing(sqlite3.connect(archive/'archive.sqlite3')) as db:
        for identity,raw in db.execute('SELECT identity,payload FROM events ORDER BY timestamp,identity'):
            e=json.loads(raw);kind=e.get('eventType')
            if kind not in FIELDS:continue
            record={k:e[k] for k in ('eventType','timestamp','zone','subZone','coords','coordinateBasis')+FIELDS[kind] if k in e}
            record['observationID']=hashlib.sha256(identity.encode()).hexdigest()
            record['client']=e.get('archiveClient')
            record=clean(record)
            if kind=='trainer_closed':
                record['services']=[s for s in record.get('services',[]) if s.get('category')!='header']
                for service in record['services']:
                    trainers.append(dict(service,trainer=(record.get('trainer') or {}).get('name'),zone=e.get('zone'),coords=e.get('coords'),observedAt=e.get('timestamp'),observationID=record['observationID']))
            records.append(record)
    for name,rows in [('observations.jsonl',records),('trainer-services.jsonl',trainers)]:
        path=destination/name;temp=path.with_suffix('.tmp')
        temp.write_text(''.join(json.dumps(row,ensure_ascii=False,sort_keys=True)+'\n' for row in rows),encoding='utf-8')
        temp.replace(path)
    return len(records),len(trainers)

def git(repo,*args):
    return subprocess.check_output(['git','-C',str(repo),*args],text=True,stderr=subprocess.STDOUT).strip()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--push',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    # Serialize scheduled/manual runs, released by OS on exit including failures.
    args.archive.mkdir(parents=True,exist_ok=True)
    with (args.archive/'sync.lock').open('a+b') as lock:
        if __import__('os').name=='nt':
            import msvcrt
            lock.seek(0);lock.write(b'0');lock.flush();lock.seek(0)
            msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if git(repo,'diff','--cached','--name-only'):
            raise RuntimeError('Staged changes exist; refusing to include unrelated work.')
        branch=git(repo,'branch','--show-current')
        if branch!='codex/restore-stitchlogger-era-11509':
            raise RuntimeError('Unexpected branch; sync stopped without switching branches.')
        if git(repo,'remote','get-url','origin')!='https://github.com/FolkertLouw/miles-ge-wow-classic-hardcore.git':
            raise RuntimeError('Unexpected remote; sync stopped.')
        # Parse a stable byte snapshot; a save changing during the read is retried next run.
        before=args.source.stat()
        raw=args.source.read_bytes()
        after=args.source.stat()
        if (before.st_mtime_ns,before.st_size)!=(after.st_mtime_ns,after.st_size):
            raise RuntimeError('WoW is writing the save; retry on the next run.')
        snapshot=args.archive/'pending-save.lua'
        snapshot.write_bytes(raw)
        digest=hashlib.sha256(raw).hexdigest()
        marker=args.archive/'last-export.sha256'
        if not marker.exists() or marker.read_text()!=digest:
            import_file(snapshot,args.archive)
            print('Exported observations and trainer rows:',export(args.archive,repo/'shared-data'))
            marker.write_text(digest)
        git(repo,'add','--','shared-data/observations.jsonl','shared-data/trainer-services.jsonl')
        if git(repo,'diff','--cached','--name-only'):
            git(repo,'-c','user.name=StitchLogger Archive','-c','user.email=stitchlogger@localhost','commit','-m','Archive newly observed Classic gameplay data')
            print('Committed gameplay observations.')
        if args.push:
            print(git(repo,'push','--set-upstream','origin',branch))
        print('Sync complete:',git(repo,'rev-parse','--short','HEAD'))

if __name__=='__main__':main()
