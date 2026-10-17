"""Official RSS ingestion. No deployment, scheduler, or Android dependencies.

The feeds omit previous draw dates and prize tiers. They cannot establish either.
"""
import argparse
from contextlib import closing
from datetime import date, datetime, timezone
from decimal import Decimal
from email.utils import parsedate_to_datetime
import hashlib
from html import unescape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sqlite3
from urllib.parse import urlsplit
from urllib.request import Request, HTTPRedirectHandler, build_opener
import xml.etree.ElementTree as ET

from domain import TIERS, validate_result
from store import Store

BASE = 'https://www.jogossantacasa.pt/web/SCRss/'
FEEDS = {kind: BASE + name for kind, name in (
    ('results', 'rssFeedCartRes'), ('jackpots', 'rssFeedJackpots'),
    ('portal', 'rssFeedPremiosPortal'))}
GAMES = {'Euromilhões': 'euromilhoes', 'M1lhão': 'milhao'}
MAX_BYTES = 1024 * 1024
DRAW = r'(\d{3}/\d{4})'
MONEY = r'(?:0|[1-9]\d{0,2}(?:\.\d{3})*|[1-9]\d*),\d{2}'
SCHEMA = '''
CREATE TABLE IF NOT EXISTS rss_imports (
 id INTEGER PRIMARY KEY, source_url TEXT NOT NULL, fingerprint TEXT NOT NULL,
 imported_at TEXT NOT NULL, status TEXT NOT NULL, detail TEXT NOT NULL,
 UNIQUE(source_url,fingerprint)
);
CREATE TABLE IF NOT EXISTS rss_observations (
 id INTEGER PRIMARY KEY, import_id INTEGER NOT NULL REFERENCES rss_imports(id),
 kind TEXT NOT NULL, game TEXT NOT NULL, draw_id TEXT NOT NULL,
 published_at TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL,
 detail TEXT NOT NULL, UNIQUE(import_id,game)
);
'''


class FeedError(ValueError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise FeedError('RSS redirect refused; configure a direct HTTPS endpoint')


def fetch(kind):
    # Fixed official URLs: neither item links nor user input can redirect this fetch.
    request = Request(FEEDS[kind], headers={'Accept': 'application/rss+xml, application/xml',
                                          'User-Agent': 'LuckyScan50-RSS/1.0'})
    with build_opener(NoRedirect()).open(request, timeout=20) as response:
        if response.status != 200 or response.url != FEEDS[kind]:
            raise FeedError('Unexpected RSS HTTP response')
        payload = response.read(MAX_BYTES + 1)
        if len(payload) > MAX_BYTES:
            raise FeedError('RSS exceeds size limit')
        return payload


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)

    def handle_starttag(self, tag, attrs):
        self.parts.append(' ')

    def handle_endtag(self, tag):
        self.parts.append(' ')


def plain(value):
    parser = PlainText()
    parser.feed(value)
    parser.close()
    return ' '.join(unescape(' '.join(parser.parts)).split())


def cents(value):
    value = value.replace('\u00a0', '').strip()
    if not re.fullmatch(MONEY, value):
        raise FeedError('Invalid Portuguese monetary value')
    return int(Decimal(value.replace('.', '').replace(',', '.')) * 100)


def draw_id(value):
    if not re.fullmatch(DRAW, value) or int(value[:3]) == 0 or not 1900 <= int(value[-4:]) <= 9999:
        raise FeedError('Invalid draw identity')
    return value


def timestamp(value):
    try:
        parsed = parsedate_to_datetime(value)
        if parsed.tzinfo is None:
            raise ValueError()
        return parsed.astimezone(timezone.utc).isoformat()
    except (ValueError, TypeError, OverflowError) as exc:
        raise FeedError('Invalid RSS publication date') from exc


def winning(game, value):
    if game == 'milhao':
        match = re.fullmatch(r'([A-Z]{3})\s*(\d{5})', value)
        if not match:
            raise FeedError('Invalid or incomplete Milhao code')
        return {'winningCode': match[1] + ' ' + match[2]}
    match = re.fullmatch(r'(\d+(?:\s+\d+){4})\s*\+\s*(\d+\s+\d+)', value)
    if not match:
        raise FeedError('Invalid or incomplete Euromilhoes key')
    numbers, stars = [list(map(int, part.split())) for part in match.groups()]
    for values, maximum in ((numbers, 50), (stars, 12)):
        if len(set(values)) != len(values) or any(not 1 <= n <= maximum for n in values):
            raise FeedError('Duplicate or out-of-range key value')
    return {'numbers': sorted(numbers), 'stars': sorted(stars)}


def portal_section(text):
    match = re.fullmatch(r'Total Prémios €\s*(' + MONEY + r') Maior Prémio €\s*(' + MONEY +
                         r') Maior Categoria (SEM DADOS|[1-9]\d?\.?º Prémio)', text)
    if not match:
        raise FeedError('Incomplete Portal indicators')
    total, largest = cents(match[1]), cents(match[2])
    if largest > total:
        raise FeedError('Largest Portal prize exceeds total')
    category = None if match[3] == 'SEM DADOS' else int(re.match(r'\d+', match[3])[0])
    if category is not None and not 1 <= category <= 13:
        raise FeedError('Invalid Portal category')
    return {'totalCents': total, 'largestCents': largest, 'largestCategory': category,
            'categoryLabel': match[3]}


def parse(payload, kind):
    if kind not in FEEDS or not isinstance(payload, bytes) or len(payload) > MAX_BYTES:
        raise FeedError('Invalid RSS input')
    # Decode using the XML declaration/BOM, never the HTTP charset or a fixed
    # UTF-8 assumption. Scan the decoded text before XML entity processing.
    try:
        if payload.startswith((b'\xff\xfe\x00\x00', b'\x00\x00\xfe\xff')):
            encoding = 'utf-32'
        elif payload.startswith((b'\xff\xfe', b'\xfe\xff')):
            encoding = 'utf-16'
        elif payload.startswith(b'\x00\x00\x00<'):
            encoding = 'utf-32-be'
        elif payload.startswith(b'<\x00\x00\x00'):
            encoding = 'utf-32-le'
        elif payload.startswith(b'\x00<\x00?'):
            encoding = 'utf-16-be'
        elif payload.startswith(b'<\x00?\x00'):
            encoding = 'utf-16-le'
        else:
            declaration = re.match(br'''<\?xml\s[^>]*encoding\s*=\s*['"]([A-Za-z][A-Za-z0-9._-]*)['"]''', payload)
            encoding = declaration[1].decode('ascii') if declaration else 'utf-8-sig'
        decoded = payload.decode(encoding)
    except (ValueError, LookupError) as exc:
        raise FeedError('Invalid XML encoding') from exc
    scan = decoded.upper()
    if '<!DOCTYPE' in scan or '<!ENTITY' in scan:
        raise FeedError('DTD and entity declarations are prohibited')
    try:
        root = ET.fromstring(decoded)
    except (ET.ParseError, ValueError, LookupError) as exc:
        raise FeedError('Invalid XML') from exc
    if root.tag != 'rss' or root.get('version') != '2.0' or len(root.findall('channel')) != 1:
        raise FeedError('Expected RSS 2.0 with one channel')
    channel = root.find('channel')
    records = []
    seen = set()
    for item in channel.findall('item'):
        title = item.findtext('title', '')
        if title not in GAMES:
            continue
        game = GAMES[title]
        if game in seen:
            raise FeedError('Duplicate game item')
        seen.add(game)
        if any(len(item.findall(field)) != 1 for field in ('title', 'description')):
            raise FeedError('Ambiguous RSS item')
        if len(item.findall('pubDate')) > 1:
            raise FeedError('Ambiguous publication date')
        published = timestamp(item.findtext('pubDate') or channel.findtext('pubDate'))
        text = plain(item.findtext('description', ''))
        record = {'game': game, 'publishedAt': published}
        if kind == 'results':
            match = re.fullmatch(r'Sorteio nº ' + DRAW + r'\s*:\s*(.+)', text)
            if not match:
                raise FeedError('Invalid results description')
            record.update(drawId=draw_id(match[1]), **winning(game, match[2]))
        elif kind == 'jackpots':
            match = re.fullmatch(r'Próximo Sorteio nº ' + DRAW + r', [^,]+? dia (\d{2}/\d{2}/\d{4})'
                                 r' - (?:Jackpot - )?1º prémio €\s*(' + MONEY + r') '
                                 r'(?:Chave do )?Sorteio nº ' + DRAW + r'\s*[-:]\s*(.+)', text)
            if not match:
                raise FeedError('Invalid jackpot description')
            try:
                next_date = datetime.strptime(match[2], '%d/%m/%Y').date()
                if next_date.strftime('%d/%m/%Y') != match[2]:
                    raise ValueError()
            except ValueError as exc:
                raise FeedError('Invalid next draw date') from exc
            upcoming, previous = draw_id(match[1]), draw_id(match[4])
            if int(upcoming[-4:]) != next_date.year or (int(upcoming[-4:]), int(upcoming[:3])) <= (int(previous[-4:]), int(previous[:3])):
                raise FeedError('Invalid next draw identity')
            same_year = upcoming[-4:] == previous[-4:]
            if ((same_year and int(upcoming[:3]) != int(previous[:3]) + 1) or
                    (not same_year and (int(upcoming[-4:]) != int(previous[-4:]) + 1 or int(upcoming[:3]) != 1))):
                raise FeedError('Next draw is not the successor of the previous draw')
            if next_date < datetime.fromisoformat(published).date():
                raise FeedError('Upcoming draw precedes RSS publication')
            amount = cents(match[3])
            if amount <= 0:
                raise FeedError('Invalid announced prize')
            record.update(drawId=previous, **winning(game, match[5]),
                          upcoming={'drawId': upcoming, 'date': next_date.isoformat(),
                                    'amountCents': amount,
                                    'kind': 'forecast_jackpot' if game == 'euromilhoes' else 'advertised_prize'})
        else:
            match = re.fullmatch(r'Último Sorteio ' + DRAW + r' (.+) Desde Sempre (.+)', text)
            if not match:
                raise FeedError('Invalid Portal description')
            record.update(drawId=draw_id(match[1]), scope='portal_only',
                          lastDraw=portal_section(match[2]), allTime=portal_section(match[3]))
            if (record['lastDraw']['totalCents'] > record['allTime']['totalCents'] or
                    record['lastDraw']['largestCents'] > record['allTime']['largestCents']):
                raise FeedError('Portal last draw exceeds historical indicators')
            if game == 'milhao' and any(record[scope]['largestCategory'] not in (None, 1) for scope in ('lastDraw','allTime')):
                raise FeedError('Invalid Milhao Portal category')
        if int(record['drawId'][-4:]) > datetime.fromisoformat(published).year:
            raise FeedError('Previous draw year is after RSS publication')
        records.append(record)
    if not records:
        raise FeedError('No supported game items')
    return records


def key(record):
    if record['game'] == 'milhao':
        return record['winningCode'].replace(' ', '')
    return (tuple(sorted(record['numbers'])), tuple(sorted(record['stars'])))


def initialize(store):
    store.migrate()
    with closing(store.connect()) as connection:
        connection.executescript(SCHEMA)


def ingest(store, payload, kind, draw_dates=None):
    """Validate/quarantine observations and optionally insert new, dated draws.

    Never update an existing draw. Audit, candidate and draw insert are atomic.
    Replaying identical bytes rechecks candidates when a date is later supplied.
    """
    if kind not in FEEDS:
        raise FeedError('Unknown feed')
    initialize(store)
    digest = hashlib.sha256(payload).hexdigest()
    now = datetime.now(timezone.utc).isoformat()
    try:
        records = parse(payload, kind)
    except ValueError as exc:
        with closing(store.connect()) as connection, connection:
            connection.execute('INSERT OR IGNORE INTO rss_imports(source_url,fingerprint,imported_at,status,detail) VALUES(?,?,?,?,?)',
                               (FEEDS[kind], digest, now, 'invalid', str(exc)))
        raise
    report = {'accepted': 0, 'conflicts': 0, 'inserted': 0, 'pendingDate': 0}
    with closing(store.connect()) as connection, connection:
        connection.execute('BEGIN IMMEDIATE')
        connection.execute('INSERT OR IGNORE INTO rss_imports(source_url,fingerprint,imported_at,status,detail) VALUES(?,?,?,?,?)',
                           (FEEDS[kind], digest, now, 'valid', ''))
        import_id = connection.execute('SELECT id FROM rss_imports WHERE source_url=? AND fingerprint=?',
                                       (FEEDS[kind], digest)).fetchone()[0]
        for record in records:
            game, identity = record['game'], record['drawId']
            old = connection.execute('SELECT payload FROM draws WHERE game=? AND draw_id=?', (game, identity)).fetchone()
            conflicts = []
            if kind != 'portal':
                if connection.execute("SELECT 1 FROM rss_observations WHERE game=? AND draw_id=? "
                                      "AND status='conflict' AND detail LIKE '%announced_draw_date%' LIMIT 1",
                                      (game, identity)).fetchone():
                    conflicts.append('announced_draw_date_conflict')
                if old and key(json.loads(old[0])) != key(record):
                    conflicts.append('existing_draw')
                if old and (draw_dates or {}).get((game, identity), json.loads(old[0])['date']) != json.loads(old[0])['date']:
                    conflicts.append('existing_draw_date')
                for other in connection.execute("SELECT payload FROM rss_observations WHERE game=? AND draw_id=? AND kind IN ('results','jackpots') AND import_id<>?", (game, identity, import_id)):
                    if key(json.loads(other[0])) != key(record):
                        conflicts.append('rss_observation')
            status = 'conflict' if conflicts else 'accepted'
            if conflicts:
                report['conflicts'] += 1
                # Quarantine previously accepted conflicting candidates, including
                # forecasts, so the public overview cannot advertise either key.
                connection.execute("UPDATE rss_observations SET status='conflict',detail='cross_feed_conflict' WHERE game=? AND draw_id=? AND kind IN ('results','jackpots')", (game, identity))
            else:
                report['accepted'] += 1
            connection.execute('INSERT INTO rss_observations(import_id,kind,game,draw_id,published_at,payload,status,detail) VALUES(?,?,?,?,?,?,?,?) '
                               'ON CONFLICT(import_id,game) DO UPDATE SET status=excluded.status,detail=excluded.detail',
                               (import_id, kind, game, identity, record['publishedAt'], json.dumps(record, ensure_ascii=False), status, ','.join(sorted(set(conflicts)))))
            if conflicts or kind == 'portal' or old:
                continue
            day = (draw_dates or {}).get((game, identity))
            if day is None:
                report['pendingDate'] += 1
                continue
            # Explicit date only: RSS publication dates are not draw dates.
            if date.fromisoformat(day) > datetime.fromisoformat(record['publishedAt']).date():
                raise FeedError('Draw date is after result publication')
            row = {'game': game, 'drawId': identity, 'date': day, 'status': 'numbers_confirmed',
                   'sourceUrl': FEEDS[kind], 'retrievedAt': now}
            if game == 'milhao':
                row.update(winningCode=record['winningCode'], amountCents=None)
            else:
                row.update(numbers=record['numbers'], stars=record['stars'], tiers=[
                    {'tier': index + 1, 'main': n, 'stars': s, 'amountCents': None,
                     'winnersPortugal': None, 'winnersTotal': None} for index, (n, s) in enumerate(TIERS)])
            validate_result(row)
            report['inserted'] += store.import_rows([row], source=FEEDS[kind], _connection=connection)['changed']
    return report


def overview(store):
    """Read-only backend utility: freshness, forecasts, Portal-only indicators.

    No cache: observations are selected on every request. HTTP clients must
    revalidate; old snapshots remain available if the next fetch fails.
    """
    with closing(store.connect(readonly=True)) as connection:
        exists = connection.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='rss_observations'").fetchone()
        if not exists:
            return {'data': [], 'conflicts': 0}
        observations = connection.execute("SELECT o.*, i.source_url, i.imported_at FROM rss_observations o JOIN rss_imports i ON i.id=o.import_id ORDER BY o.published_at DESC,o.id DESC").fetchall()
        data, seen, conflict_count = [], set(), 0
        for row in observations:
            group = (row['kind'], row['game'])
            if group in seen:
                continue
            seen.add(group)
            item = json.loads(row['payload'])
            # Recheck against administrative corrections made after ingestion.
            current = connection.execute('SELECT payload FROM draws WHERE game=? AND draw_id=?', (row['game'], row['draw_id'])).fetchone()
            conflict = row['status'] == 'conflict' or (row['kind'] != 'portal' and current and key(json.loads(current[0])) != key(item))
            if conflict:
                conflict_count += 1
                continue
            data.append({**item, 'feed': row['kind'], 'sourceUrl': row['source_url'],
                         'importedAt': row['imported_at'], 'validation': 'accepted',
                         'historyStatus': 'not_applicable' if row['kind']=='portal' else 'stored' if current else 'pending_draw_date'})
        return {'data': data, 'conflicts': conflict_count}


def record_failure(store, kind, exc):
    initialize(store)
    now = datetime.now(timezone.utc).isoformat()
    with closing(store.connect()) as connection, connection:
        connection.execute('INSERT INTO rss_imports(source_url,fingerprint,imported_at,status,detail) VALUES(?,?,?,?,?)',
                           (FEEDS[kind], 'failure-' + now, now, 'failed', type(exc).__name__))


def run_remote(store, kinds):
    outcomes = {}
    for kind in kinds:
        try:
            outcomes[kind] = ingest(store, fetch(kind), kind)
        except (OSError, ValueError, sqlite3.Error) as exc:
            # Network failures also leave an audit record; no result deletion.
            outcomes[kind] = {'error': type(exc).__name__}
            try:
                record_failure(store, kind, exc)
            except (OSError, ValueError, sqlite3.Error):
                outcomes[kind]['auditError'] = 'storage_unavailable'
    return outcomes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True, type=Path)
    parser.add_argument('--feed', required=True, choices=FEEDS)
    parser.add_argument('--file', type=Path, help='Import original XML bytes instead of fetching HTTPS')
    parser.add_argument('--draw-date', action='append', default=[], metavar='GAME:NNN/YYYY=YYYY-MM-DD',
                        help='Separately verified draw date; never inferred from RSS publication')
    args = parser.parse_args()
    if not args.database.is_absolute():
        parser.error('Use an absolute path to a local validation database')
    dates = {}
    for entry in args.draw_date:
        try:
            game_id, day = entry.split('=')
            game, identity = game_id.split(':')
            if game not in GAMES.values() or date.fromisoformat(day).isoformat() != day:
                raise ValueError()
            draw_id(identity)
            if int(identity[-4:]) != date.fromisoformat(day).year:
                raise ValueError()
            dates[(game, identity)] = day
        except ValueError:
            parser.error('Invalid explicit draw date')
    try:
        if args.file:
            with args.file.open('rb') as source:
                payload = source.read(MAX_BYTES + 1)
        else:
            payload = fetch(args.feed)
        print(json.dumps(ingest(Store(args.database), payload, args.feed, dates), ensure_ascii=False))
    except (OSError, ValueError, sqlite3.Error) as exc:
        try:
            record_failure(Store(args.database), args.feed, exc)
        except (OSError, ValueError, sqlite3.Error):
            pass  # A storage failure cannot be recorded in the failed store.
        parser.exit(1, 'RSS import failed: ' + str(exc) + '\n')


if __name__ == '__main__':
    main()
