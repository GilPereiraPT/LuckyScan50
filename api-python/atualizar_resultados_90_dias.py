"""Daily, bounded, official 90-day backfill for Euromilhões and M1lhão.

Run using the same private SQLite results database as Passenger. Safe to rerun:
official pages are validated, incompatible changes are quarantined, and unchanged
draws do not generate new revisions or backups. No APK changes are required.
"""
from contextlib import closing
from datetime import datetime
import fcntl
import json
import os
from pathlib import Path
import sqlite3
from zoneinfo import ZoneInfo

import historical_results
import official_cartaz
import official_milhao
from store import Store

ROOT = Path(__file__).resolve().parent


def configured_database():
    """Use the API database; on cPanel Cron may not inherit Passenger env."""
    path = os.environ.get('LUCKYSCAN_DATABASE')
    if not path:
        config_path = ROOT / 'rss-collector.json'
        if not config_path.is_file():
            raise ValueError('LUCKYSCAN_DATABASE or an active rss-collector.json is required')
        config = json.loads(config_path.read_text(encoding='utf-8'))
        if not isinstance(config, dict) or config.get('enabled') is not True:
            raise ValueError('Results collection must be explicitly enabled')
        path = config.get('database')
    if not isinstance(path, str) or not Path(path).is_absolute() or not Path(path).is_file():
        raise ValueError('An existing absolute SQLite results database is required')
    return Path(path)


def run(database=None, *, today=None, fetchers=None):
    """Return an auditable per-game report without suppressing failures."""
    database = Path(database) if database is not None else configured_database()
    if not database.is_absolute() or not database.is_file():
        raise ValueError('An existing absolute SQLite results database is required')
    Store(database).all()  # Validate the database before any network request.
    today = today or datetime.now(ZoneInfo('Europe/Lisbon')).date()
    outputs = {}
    failures = False
    # Separate lock prevents duplicate daily sweeps before the per-import lock.
    with database.with_suffix(database.suffix + '.recent.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {'status': 'already_running', 'exitCode': 0, 'games': {}}
        for game, adapter in (('euromilhoes', official_cartaz), ('milhao', official_milhao)):
            try:
                fetch = fetchers[game] if fetchers is not None else historical_results.OfficialSession(adapter.URL).fetch
                report, items = historical_results.collect(today, fetch, adapter=adapter)
                outcome = historical_results.apply_batch(
                    Store(database), items, report, apply=True, adapter=adapter,
                )
                # A partial or conflicting result must not be announced as complete.
                if outcome['status'] == 'conflicts_no_import' or outcome.get('partialDraws'):
                    failures = True
                outputs[game] = {
                    'status': outcome['status'],
                    'changed': outcome['changed'],
                    'selectedCount': outcome['selectedCount'],
                    'latestAvailable': outcome['latestAvailable'],
                    'conflicts': outcome.get('conflicts', []),
                    'partialDraws': outcome.get('partialDraws', []),
                    'startBoundaryCovered': outcome['startBoundaryCovered'],
                }
            except (OSError, ValueError, TypeError, sqlite3.Error) as exc:
                failures = True
                outputs[game] = {'status': 'failed', 'error': type(exc).__name__}
    return {'status': 'incomplete' if failures else 'ok',
            'exitCode': 1 if failures else 0, 'games': outputs}


if __name__ == '__main__':
    try:
        report = run()
    except (OSError, ValueError, TypeError, sqlite3.Error) as exc:
        report = {'status': 'failed', 'exitCode': 1, 'error': type(exc).__name__}
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    raise SystemExit(report['exitCode'])
