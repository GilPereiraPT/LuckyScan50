"""Cron-safe administrative inbox adapter. No remote source is authorized yet."""
import argparse
import fcntl
import json
import logging
import os
from pathlib import Path
import sqlite3
from store import Store

log=logging.getLogger('luckyscan50.collect')


def run(database, inbox):
    store=Store(database)
    store.path.parent.mkdir(parents=True,exist_ok=True)
    lock_path=store.path.with_suffix(store.path.suffix+'.lock')
    with lock_path.open('a') as lock:
        try:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            log.info('Another import is active')
            return 0
        failures=0
        for path in sorted(Path(inbox).glob('*.json')):
            try:
                payload=json.loads(path.read_text(encoding='utf-8'))
                result=store.import_rows(payload if isinstance(payload,list) else [payload],source='administrative-inbox')
                log.info('Import completed: changed=%d unchanged=%d',result['changed'],result['unchanged'])
            except (OSError,ValueError,sqlite3.Error):
                failures+=1
                log.error('Administrative import failed; input retained')
        return 1 if failures else 0


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database',default=os.environ.get('LUCKYSCAN_DATABASE'))
    parser.add_argument('--inbox',required=True,type=Path)
    args=parser.parse_args()
    if not args.database or not Path(args.database).is_absolute() or not args.inbox.is_dir():
        parser.error('An absolute database path and an existing inbox directory are required')
    logging.basicConfig(level=logging.INFO,format='%(asctime)s %(levelname)s %(message)s')
    return run(args.database,args.inbox)

if __name__=='__main__':
    raise SystemExit(main())
