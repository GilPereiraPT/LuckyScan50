"""Administrative CLI only. Never exposed over HTTP."""
import argparse
import json
import os
from pathlib import Path
from store import Store


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path',type=Path)
    parser.add_argument('--database',default=os.environ.get('LUCKYSCAN_DATABASE'))
    parser.add_argument('--legacy',action='store_true',help='Back up and migrate a legacy JSON array')
    args=parser.parse_args(argv)
    if not args.database:
        parser.error('Set LUCKYSCAN_DATABASE or --database to an absolute private path')
    if not Path(args.database).is_absolute():
        parser.error('Database path must be absolute')
    store=Store(args.database)
    try:
        if args.legacy:
            result=store.import_legacy(args.path)
        else:
            payload=json.loads(args.path.read_text(encoding='utf-8'))
            result=store.import_rows(payload if isinstance(payload,list) else [payload])
        print(json.dumps(result))
    except (ValueError,OSError) as exc:
        parser.exit(1,f'Import failed: {exc}\n')

if __name__=='__main__':
    main()
