"""Administrative CLI only. Never exposed over HTTP."""
import argparse
import fcntl
import hashlib
import tempfile
import json
import os
from pathlib import Path
from store import Store, read_json
from domain import validate_result


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path',type=Path)
    parser.add_argument('--database',default=os.environ.get('LUCKYSCAN_DATABASE'))
    parser.add_argument('--legacy',action='store_true',help='Back up and migrate a legacy JSON array')
    args=parser.parse_args(argv)
    if args.database and not Path(args.database).is_absolute():
        parser.error('Database path must be absolute')
    try:
        if not args.database:
            if args.legacy:
                parser.error('--legacy requires --database')
            payload=json.loads(args.path.read_text(encoding='utf-8'))
            path=Path(os.environ.get('LUCKYSCAN_RESULTS_FILE',str(Path(__file__).parent/'data'/'results.json')))
            print(json.dumps(import_json(path,payload if isinstance(payload,list) else [payload])))
            return
        store=Store(args.database)
        if args.legacy:
            result=store.import_legacy(args.path)
        else:
            payload=json.loads(args.path.read_text(encoding='utf-8'))
            result=store.import_rows(payload if isinstance(payload,list) else [payload])
        print(json.dumps(result))
    except (ValueError,OSError) as exc:
        parser.exit(1,f'Import failed: {exc}\n')


def import_json(path, incoming):
    """Compatibility writer: lock, validate, retain each previous JSON, atomic replace."""
    if not incoming:
        raise ValueError('Empty input')
    keys=set()
    for row in incoming:
        validate_result(row)
        key=(row['game'],row['drawId'])
        if key in keys:
            raise ValueError('Duplicate input')
        keys.add(key)
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.with_suffix(path.suffix+'.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        rows=read_json(path)
        indexed={(r['game'],r['drawId']):r for r in rows}
        changed=0
        for row in incoming:
            key=(row['game'],row['drawId'])
            old=indexed.get(key)
            if old==row:
                continue
            if old and old['status']=='complete' and row['status']!='complete':
                raise ValueError('Cannot downgrade a complete draw')
            indexed[key]=row
            changed+=1
        if changed:
            if path.exists():
                original=path.read_bytes()
                backup=path.with_name(path.name+'.'+hashlib.sha256(original).hexdigest()[:16]+'.bak')
                try:
                    with backup.open('xb') as output:
                        output.write(original)
                except FileExistsError:
                    if backup.read_bytes()!=original:
                        raise ValueError('Backup integrity mismatch')
            fd,tmp=tempfile.mkstemp(dir=path.parent,prefix='.luckyscan-',suffix='.tmp')
            try:
                with os.fdopen(fd,'w',encoding='utf-8') as output:
                    json.dump(sorted(indexed.values(),key=lambda r:(r['date'],r['game'],r['drawId'])),output,ensure_ascii=False,indent=2)
                    output.flush()
                    os.fsync(output.fileno())
                os.replace(tmp,path)
            finally:
                if os.path.exists(tmp):
                    os.unlink(tmp)
        return {'changed':changed,'unchanged':len(incoming)-changed}

if __name__=='__main__':
    main()
