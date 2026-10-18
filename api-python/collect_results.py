"""cPanel Cron collector: explicit RSS mode or the compatible JSON inbox mode."""
import argparse
from contextlib import closing
from datetime import date, datetime, timezone
import fcntl
import hashlib
import json
import logging
import os
from pathlib import Path
import sqlite3
from urllib.parse import urlsplit

from store import Store
import rss_import as rss
import official_cartaz
import official_statistics

log = logging.getLogger('luckyscan50.collect')


def run(database, inbox):
    """Compatible administrative inbox; never makes an HTTP request."""
    store = Store(database)
    store.path.parent.mkdir(parents=True, exist_ok=True)
    with store.path.with_suffix(store.path.suffix + '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log.info('Another import is active')
            return 0
        failures = 0
        for path in sorted(Path(inbox).glob('*.json')):
            try:
                payload = json.loads(path.read_text(encoding='utf-8'))
                result = store.import_rows(payload if isinstance(payload, list) else [payload], source='administrative-inbox')
                log.info('Import completed: changed=%d unchanged=%d', result['changed'], result['unchanged'])
            except (OSError, ValueError, sqlite3.Error):
                failures += 1
                log.error('Administrative import failed; input retained')
        return 1 if failures else 0


def verified_dates(path):
    """Operator-reviewed dates, never RSS publication dates or inferred schedules."""
    if path is None:
        return {}
    rows = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(rows, list):
        raise ValueError('Expected a list of reviewed draw dates')
    dates = {}
    for row in rows:
        if not isinstance(row, dict) or row.get('game') not in rss.GAMES.values():
            raise ValueError('Invalid reviewed date game')
        identity = rss.draw_id(row.get('drawId', ''))
        day = date.fromisoformat(row.get('date', ''))
        source = urlsplit(row.get('sourceUrl', ''))
        if (day.isoformat() != row['date'] or day.year != int(identity[-4:]) or
                source.scheme != 'https' or not source.hostname or source.username or source.password):
            raise ValueError('Reviewed dates require ISO date, matching year and HTTPS provenance')
        key = (row['game'], identity)
        if key in dates:
            raise ValueError('Duplicate reviewed draw date')
        dates[key] = day.isoformat()
    return dates


def announced_dates(store, manual):
    """Reuse the draw dates explicitly announced in earlier jackpot snapshots."""
    candidates, usable = {}, set()
    with closing(store.connect(readonly=True)) as connection:
        rows = connection.execute("SELECT payload,status FROM rss_observations WHERE kind='jackpots' AND status IN ('accepted','conflict')")
        for row in rows:
            record = json.loads(row[0])
            upcoming = record['upcoming']
            identity = (record['game'], upcoming['drawId'])
            candidates.setdefault(identity, set()).add(upcoming['date'])
            if row['status'] == 'accepted':
                usable.add(identity)
    for key, day in manual.items():
        candidates.setdefault(key, set()).add(day)
        usable.add(key)
    return ({key: next(iter(days)) for key, days in candidates.items() if len(days) == 1 and key in usable},
            {key: sorted(days) for key, days in candidates.items() if len(days) > 1})


def run_rss(database, *, fixtures=None, dates=None, cartaz=False):
    """One bounded collection cycle. Called remotely only by explicit --rss.

    All feeds are staged before promoting any new result, so same-cycle source
    conflicts cannot create a new historical draw. Never initializes an unknown
    or absent production database. Compatible pending results may become complete.
    """
    store = Store(database)
    if not store.path.is_absolute() or not store.path.is_file():
        raise ValueError('RSS requires an existing absolute SQLite database path; no automatic JSON migration')
    store.all()  # Read-only preflight validates existing results and schema.
    with store.path.with_suffix(store.path.suffix + '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log.info('RSS skipped: another import holds the database lock')
            return {'skipped': 'locked', 'exitCode': 0}
        rss.initialize(store)  # Only additive RSS tables on the known database.
        outcomes, payloads = {}, {}
        for kind, url in rss.FEEDS.items():
            try:
                if fixtures is None:
                    payload = rss.fetch(kind)
                else:
                    with (Path(fixtures) / (url.rsplit('/', 1)[1] + '.xml')).open('rb') as source:
                        payload = source.read(rss.MAX_BYTES + 1)
                outcomes[kind] = rss.ingest(store, payload, kind)
                payloads[kind] = payload
            except (OSError, ValueError, sqlite3.Error) as exc:
                outcomes[kind] = {'error': type(exc).__name__}
                try:
                    rss.record_failure(store, kind, exc)
                except (OSError, ValueError, sqlite3.Error):
                    outcomes[kind]['auditError'] = 'storage_unavailable'
                log.error('RSS %s failed: %s; existing results retained', kind, type(exc).__name__)
        known_dates, date_conflicts = announced_dates(store, dates or {})
        # Record conflicting announced dates without choosing either of them.
        if date_conflicts:
            with closing(store.connect()) as connection, connection:
                for game, identity in date_conflicts:
                    connection.execute("UPDATE rss_observations SET status='conflict',detail='announced_draw_date_conflict' "
                                       "WHERE game=? AND draw_id=? AND kind IN ('results','jackpots')", (game, identity))
                    for row in connection.execute("SELECT id,payload FROM rss_observations WHERE kind='jackpots' AND game=?", (game,)).fetchall():
                        if json.loads(row['payload'])['upcoming']['drawId'] == identity:
                            connection.execute("UPDATE rss_observations SET status='conflict',detail='announced_draw_date_conflict' WHERE id=?", (row['id'],))
                    now = datetime.now(timezone.utc).isoformat()
                    detail = json.dumps({'game': game, 'drawId': identity, 'dates': date_conflicts[(game, identity)]}, sort_keys=True)
                    fingerprint = 'date-conflict-' + hashlib.sha256(detail.encode()).hexdigest()
                    connection.execute('INSERT OR IGNORE INTO rss_imports(source_url,fingerprint,imported_at,status,detail) VALUES(?,?,?,?,?)',
                                       (rss.FEEDS['jackpots'], fingerprint, now, 'conflict', detail))
        if cartaz:
            try:
                if fixtures is None:
                    html = official_cartaz.fetch()
                else:
                    with (Path(fixtures).parent / 'official/euromilhoes.html').open('rb') as source:
                        html = source.read(official_cartaz.MAX_BYTES + 1)
                outcomes['cartaz'] = official_cartaz.reconcile(store, html, known_dates, date_conflicts)
            except (OSError, ValueError, sqlite3.Error) as exc:
                outcomes['cartaz'] = {'error': type(exc).__name__}
                try:
                    official_cartaz.initialize(store)
                    official_cartaz.record(store, str(type(exc).__name__).encode(), 'failed', [type(exc).__name__])
                except (OSError, ValueError, sqlite3.Error):
                    outcomes['cartaz']['auditError'] = 'storage_unavailable'
        if 'results' in payloads:
            # The results feed is complementary. Jackpots alone never inserts
            # a past result; its future announcement can supply the exact date.
            try:
                outcomes['results'] = rss.ingest(store, payloads['results'], 'results', known_dates)
            except (OSError, ValueError, sqlite3.Error) as exc:
                outcomes['results'] = {'error': type(exc).__name__, 'phase': 'promotion'}
                try:
                    rss.record_failure(store, 'results', exc)
                except (OSError, ValueError, sqlite3.Error):
                    outcomes['results']['auditError'] = 'storage_unavailable'
        failures = any('error' in outcome for outcome in outcomes.values())
        conflicts = bool(date_conflicts) or any(outcome.get('conflicts', 0) for outcome in outcomes.values())
        report = {'feeds': outcomes, 'dateConflicts': [{'game': g, 'drawId': d} for g, d in date_conflicts],
                  'offline': fixtures is not None, 'exitCode': 1 if failures else 2 if conflicts else 0}
        log.info('RSS cycle: %s', json.dumps(report, ensure_ascii=False, sort_keys=True))
        return report


def run_official_statistics(database, *, source_file=None, input_format='html'):
    """Explicit aggregate collection; shares the RSS/inbox execution lock."""
    store = Store(database)
    if not store.path.is_absolute() or not store.path.is_file():
        raise ValueError('Statistics require an existing absolute SQLite database path')
    store.all()  # Do not initialize or migrate an unknown production database.
    if input_format not in ('html', 'json') or (source_file is None and input_format != 'html'):
        raise ValueError('Remote statistics collection only accepts official HTML')
    with store.path.with_suffix(store.path.suffix + '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {'skipped': 'locked', 'exitCode': 0}
        try:
            if source_file is None:
                payload = official_statistics.fetch()
            else:
                with Path(source_file).open('rb') as source:
                    payload = source.read(official_statistics.MAX_BYTES + 1)
            result = store.import_official_statistics(payload, format=input_format)
            return {**result, 'offline': source_file is not None,
                    'exitCode': 2 if result['conflicts'] else 0}
        except (OSError, ValueError, sqlite3.Error) as exc:
            log.error('Official statistics collection failed: %s; previous snapshot retained', type(exc).__name__)
            return {'error': type(exc).__name__, 'exitCode': 1}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--inbox', type=Path)
    mode.add_argument('--rss', action='store_true', help='Explicitly request official HTTPS collection')
    mode.add_argument('--official-statistics', action='store_true', help='Explicit aggregate snapshot import; never changes draws')
    parser.add_argument('--statistics-file', type=Path, help='Reviewed local statistics capture; no HTTP')
    parser.add_argument('--statistics-format', choices=('html', 'json'), default='html')
    parser.add_argument('--database', default=os.environ.get('LUCKYSCAN_DATABASE'))
    parser.add_argument('--config', type=Path, help='Private JSON config for RSS Cron; paths must be absolute')
    parser.add_argument('--fixtures', type=Path, help='Offline XML directory; no HTTP')
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    try:
        config = json.loads(args.config.read_text(encoding='utf-8')) if args.config else {}
        if not isinstance(config, dict) or set(config) - {'database', 'enabled', 'datesFile', 'cartaz'}:
            raise ValueError('Invalid collector configuration')
        database = args.database or config.get('database')
        if not isinstance(database, str) or not Path(database).is_absolute():
            raise ValueError('An absolute database path is required')
        if args.inbox:
            if args.config or args.fixtures or args.statistics_file or args.statistics_format != 'html' or not args.inbox.is_dir():
                raise ValueError('Inbox mode requires an existing directory and no RSS options')
            return run(database, args.inbox)
        if args.official_statistics:
            if args.fixtures:
                raise ValueError('Statistics use --statistics-file, not RSS fixtures')
            if args.statistics_file is None and config.get('enabled') is not True:
                raise ValueError('Remote statistics collection disabled: enabled=true required')
            report = run_official_statistics(database, source_file=args.statistics_file, input_format=args.statistics_format)
            print(json.dumps(report, ensure_ascii=False))
            return report['exitCode']
        if args.statistics_file or args.statistics_format != 'html':
            raise ValueError('Statistics options require --official-statistics')
        if not args.fixtures and config.get('enabled') is not True:
            raise ValueError('Remote collection disabled: review config and set enabled=true explicitly')
        dates_path = config.get('datesFile')
        if dates_path is not None and (not isinstance(dates_path, str) or not Path(dates_path).is_absolute()):
            raise ValueError('datesFile must be an absolute path')
        if type(config.get('cartaz', True)) is not bool:
            raise ValueError('cartaz must be a boolean')
        report = run_rss(database, fixtures=args.fixtures, dates=verified_dates(dates_path),
                         cartaz=config.get('cartaz', True))
        print(json.dumps(report, ensure_ascii=False))
        return report['exitCode']
    except (OSError, ValueError, TypeError, sqlite3.Error) as exc:
        log.error('Collector stopped: %s', type(exc).__name__)
        parser.exit(1, str(exc) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
