"""Consistent SQLite backup, without modifying the source or overwriting a file."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
from store import Store


def backup(source, destination):
    source, destination = Path(source), Path(destination)
    if not source.is_absolute() or not destination.is_absolute() or source.resolve() == destination.resolve():
        raise ValueError('Use distinct absolute database and backup paths')
    store = Store(source)
    store.all()  # Read-only; refuses a missing or malformed source.
    fd = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(fd)
    try:
        with closing(store.connect(readonly=True)) as original, closing(sqlite3.connect(destination)) as output:
            original.backup(output)
            if output.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise ValueError('Backup integrity check failed')
    except BaseException:
        destination.unlink(missing_ok=True)
        raise
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text(encoding='utf-8'))
        print(backup(config['database'], args.output))
    except (OSError, ValueError, TypeError, KeyError, sqlite3.Error) as exc:
        parser.exit(1, 'Backup failed: ' + str(exc) + '\n')


if __name__ == '__main__':
    main()
