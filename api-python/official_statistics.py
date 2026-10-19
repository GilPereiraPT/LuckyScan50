"""Auditable aggregate snapshots, separate from individual draw history.

No third-party modules. The semantic HTML adapter is deliberately fail-closed;
its compatibility with the live SC page must be reviewed against a real capture.
A structurally valid import never claims that reference verification occurred.
"""
from contextlib import closing
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import hashlib
import json
import re
from urllib.request import Request, build_opener

from official_cartaz import Document, Node
from rss_import import FeedError, NoRedirect
from result_statistics import frequencies, star_limit

URL = 'https://www.jogossantacasa.pt/web/SCEstatisticas/'
COVERAGE_START = '2004-02-13'
MAX_BYTES = 2 * 1024 * 1024
SCHEMA = '''CREATE TABLE IF NOT EXISTS official_statistics_snapshots (
 id INTEGER PRIMARY KEY, source_url TEXT NOT NULL, updated_at TEXT NOT NULL,
 imported_at TEXT NOT NULL, fingerprint TEXT NOT NULL UNIQUE,
 source_sha256 TEXT NOT NULL, status TEXT NOT NULL,
 payload TEXT NOT NULL, UNIQUE(source_url,updated_at,fingerprint)
);
CREATE INDEX IF NOT EXISTS official_statistics_updated
 ON official_statistics_snapshots(updated_at);
CREATE TABLE IF NOT EXISTS official_statistics_imports (
 id INTEGER PRIMARY KEY, imported_at TEXT NOT NULL, source_url TEXT NOT NULL,
 source_sha256 TEXT NOT NULL, status TEXT NOT NULL, detail TEXT NOT NULL
);'''
HEADERS = ('Valor', 'Saídas', 'Percentagem', 'Último concurso', 'Data', 'Ausências')
OPTIONAL_HEADER = 'Concursos elegíveis'
INPUT_FIELDS = {'schemaVersion', 'game', 'sourceUrl', 'updatedAt', 'coverageStart', 'numbers', 'stars'}
ITEM_FIELDS = {'value', 'count', 'percentage', 'lastDrawId', 'lastDate', 'drawsSinceLast', 'eligibleDraws'}


def timestamp(value):
    if not isinstance(value, str):
        raise FeedError('Statistics timestamp must be a string')
    try:
        stamp = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if stamp.tzinfo is None or stamp.utcoffset() is None:
            raise ValueError()
    except ValueError as exc:
        raise FeedError('Statistics timestamps require an explicit timezone') from exc
    return stamp.astimezone(timezone.utc)


def integer(value, *, minimum=0, maximum=None):
    if type(value) is not int or value < minimum or (maximum is not None and value > maximum):
        raise FeedError('Invalid statistics integer')
    return value


def decimal_percentage(value):
    # Exact decimal source percentages are retained; no shared star denominator.
    if not isinstance(value, (str, int)) or isinstance(value, bool):
        raise FeedError('Percentage must be an exact decimal string or integer')
    if not re.fullmatch(r'(?:0|[1-9]\d{0,2})(?:\.\d{1,6})?', str(value)):
        raise FeedError('Invalid statistics percentage format')
    try:
        result = Decimal(str(value))
    except InvalidOperation as exc:
        raise FeedError('Invalid statistics percentage') from exc
    if not Decimal(0) <= result <= Decimal(100):
        raise FeedError('Statistics percentage outside 0..100')
    return result


def validate_snapshot(snapshot, *, now=None):
    """Validate all 62 entries atomically; do not reconstruct source denominators."""
    if not isinstance(snapshot, dict) or set(snapshot) != INPUT_FIELDS:
        raise FeedError('Unexpected statistics structure')
    if type(snapshot['schemaVersion']) is not int or snapshot['schemaVersion'] != 1:
        raise FeedError('Unsupported statistics schema')
    if snapshot['game'] != 'euromilhoes' or snapshot['sourceUrl'] != URL:
        raise FeedError('Statistics require the configured official HTTPS source')
    updated = timestamp(snapshot['updatedAt'])
    now = now or datetime.now(timezone.utc)
    if updated > now or updated.date().isoformat() < COVERAGE_START or snapshot['coverageStart'] != COVERAGE_START:
        raise FeedError('Invalid statistics date or historical coverage')
    coverage = date.fromisoformat(COVERAGE_START)
    canonical = {k: snapshot[k] for k in INPUT_FIELDS - {'numbers', 'stars', 'updatedAt'}}
    canonical['updatedAt'] = updated.isoformat()
    for field, maximum in (('numbers', 50), ('stars', 12)):
        rows = snapshot[field]
        if not isinstance(rows, list) or len(rows) != maximum:
            raise FeedError('Statistics require exactly 50 numbers and 12 stars')
        accepted = {}
        for row in rows:
            if not isinstance(row, dict) or set(row) != ITEM_FIELDS:
                raise FeedError('Unexpected statistics row structure')
            value = integer(row['value'], minimum=1, maximum=maximum)
            if value in accepted:
                raise FeedError('Duplicate statistics entry')
            count = integer(row['count'])
            percent = decimal_percentage(row['percentage'])
            eligible = row['eligibleDraws']
            if eligible is not None:
                integer(eligible, minimum=1)
                if count > eligible:
                    raise FeedError('Occurrences exceed explicitly supplied eligible draws')
                # Compare only to the explicitly provided denominator and the
                # source precision. Stars 10/11/12 may have different values.
                quantum = Decimal(1).scaleb(percent.as_tuple().exponent)
                computed = (Decimal(count) * 100 / eligible).quantize(quantum, rounding=ROUND_HALF_UP)
                if computed != percent:
                    raise FeedError('Percentage disagrees with its source denominator')
            if (count == 0 and percent != 0) or (count > 0 and percent == 0):
                raise FeedError('Occurrences and percentage disagree')
            absent = row['drawsSinceLast']
            if absent is not None:
                integer(absent)
                if eligible is not None and absent > eligible - count:
                    raise FeedError('Absences and occurrences exceed eligible draws')
            identity, day = row['lastDrawId'], row['lastDate']
            if count == 0:
                if identity is not None or day is not None:
                    raise FeedError('A never-drawn value cannot have a last draw')
            else:
                if not isinstance(identity, str) or not re.fullmatch(r'(?!000)\d{3}/\d{4}', identity):
                    raise FeedError('Invalid last Portuguese draw identifier')
                try:
                    last = date.fromisoformat(day)
                    if (last.isoformat() != day or not coverage <= last <= updated.date()
                            or last.year != int(identity[-4:]) or absent is None):
                        raise ValueError()
                except (TypeError, ValueError) as exc:
                    raise FeedError('Invalid last statistics draw date or absence') from exc
                if field == 'stars' and value > star_limit(last.isoformat()):
                    raise FeedError('Star did not exist at its reported last draw date')
            accepted[value] = {**row, 'percentage': format(percent, 'f')}
        if set(accepted) != set(range(1, maximum + 1)):
            raise FeedError('Missing statistics values')
        canonical[field] = [accepted[value] for value in range(1, maximum + 1)]
    denominators = {row['eligibleDraws'] for row in canonical['numbers']}
    if len(denominators - {None}) > 1:
        raise FeedError('All main numbers require the same explicit eligible draw total')
    if len(denominators) == 1 and None not in denominators:
        if sum(row['count'] for row in canonical['numbers']) != 5 * next(iter(denominators)):
            raise FeedError('Number frequencies disagree with the explicit draw total')
    # Never impose a common denominator on stars introduced in different periods.
    return canonical


def unique_json(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise FeedError('Duplicate JSON field')
        result[key] = value
    return result


def parse_json(payload, *, now=None):
    if not isinstance(payload, bytes) or not payload or len(payload) > MAX_BYTES:
        raise FeedError('Invalid statistics input size')
    try:
        snapshot = json.loads(payload.decode('utf-8-sig'), object_pairs_hook=unique_json)
    except (ValueError, UnicodeError) as exc:
        raise FeedError('Invalid statistics JSON') from exc
    return validate_snapshot(snapshot, now=now)


def text_integer(value):
    if not re.fullmatch(r'(?:0|[1-9]\d{0,2}(?:\.\d{3})*|[1-9]\d*)', value):
        raise FeedError('Invalid Portuguese statistics count')
    return int(value.replace('.', ''))


def parse_html(payload, *, now=None):
    """Strict semantic-table profile, not yet validated against a live capture.

    Required source semantics: one timezone-qualified time element, an explicit
    coverage statement, and exactly one captioned table for each field. We do
    not guess dates/timezones or accept page-wide loose numeric token matches.
    """
    if not isinstance(payload, bytes) or not payload or len(payload) > MAX_BYTES:
        raise FeedError('Invalid statistics input size')
    charset = re.search(br'charset\s*=\s*[\'"]?([A-Za-z0-9_-]+)', payload[:8192], re.I)
    try:
        text = payload.decode('utf-8-sig' if payload.startswith(b'\xef\xbb\xbf') else charset[1].decode() if charset else 'utf-8')
        document = Document()
        document.feed(text)
        document.close()
    except (LookupError, ValueError) as exc:
        raise FeedError('Invalid statistics HTML encoding') from exc
    times = document.root.find('time')
    coverage = re.findall(r'\bDesde\s+(\d{2}/\d{2}/\d{4})\b', document.root.text())
    if len(times) != 1 or 'datetime' not in times[0].attrs or coverage != ['13/02/2004']:
        raise FeedError('Missing or ambiguous official update/coverage metadata')
    snapshot = {'schemaVersion': 1, 'game': 'euromilhoes', 'sourceUrl': URL,
                'updatedAt': times[0].attrs['datetime'], 'coverageStart': COVERAGE_START}
    tables = document.root.find('table')
    selected = {}
    for table in tables:
        captions = table.find('caption')
        if len(captions) != 1 or captions[0].text() not in ('Números', 'Estrelas'):
            raise FeedError('Unexpected statistics table or caption')
        field = 'numbers' if captions[0].text() == 'Números' else 'stars'
        if field in selected:
            raise FeedError('Duplicate statistics table')
        rows = table.find('tr')
        if not rows:
            raise FeedError('Missing statistics table rows')
        headers = tuple(node.text() for node in rows[0].find('th'))
        if headers not in (HEADERS, HEADERS + (OPTIONAL_HEADER,)):
            raise FeedError('Unexpected official statistics columns')
        values = []
        for row in rows[1:]:
            cells = [node.text() for node in row.children if isinstance(node, Node) and node.tag == 'td']
            if len(cells) != len(headers) or row.find('th'):
                raise FeedError('Unexpected official statistics row')
            percent = re.fullmatch(r'((?:0|[1-9]\d{0,2})(?:,\d{1,6})?)\s*%', cells[2])
            if not percent:
                raise FeedError('Invalid official percentage cell')
            last_day = None
            if cells[4] != '—':
                try:
                    last_day = datetime.strptime(cells[4], '%d/%m/%Y').date()
                    if last_day.strftime('%d/%m/%Y') != cells[4]:
                        raise ValueError()
                except ValueError as exc:
                    raise FeedError('Invalid official last draw date') from exc
            values.append({'value': text_integer(cells[0]), 'count': text_integer(cells[1]),
                           'percentage': percent[1].replace(',', '.'),
                           'lastDrawId': None if cells[3] == '—' else cells[3],
                           'lastDate': last_day.isoformat() if last_day else None,
                           'drawsSinceLast': None if cells[5] == '—' else text_integer(cells[5]),
                           'eligibleDraws': text_integer(cells[6]) if len(cells) == 7 else None})
        selected[field] = values
    if set(selected) != {'numbers', 'stars'}:
        raise FeedError('Missing official statistics table')
    return validate_snapshot({**snapshot, **selected}, now=now)


def fetch():
    request = Request(URL, headers={'User-Agent': 'LuckyScan50-statistics/1.0', 'Accept': 'text/html'})
    with build_opener(NoRedirect()).open(request, timeout=20) as response:
        if response.status != 200 or response.url != URL:
            raise FeedError('Unexpected official statistics HTTP response')
        if 'text/html' not in response.headers.get('Content-Type', '').lower():
            raise FeedError('Unexpected official statistics content type')
        payload = response.read(MAX_BYTES + 1)
        if len(payload) > MAX_BYTES:
            raise FeedError('Official statistics exceed size limit')
        return payload


def initialize(store):
    with closing(store.connect()) as connection:
        connection.executescript(SCHEMA)


def ingest(store, payload, *, format='html', now=None):
    """Atomic snapshots with idempotency and same-update conflicts quarantined."""
    if format not in ('html', 'json'):
        raise FeedError('Unknown statistics input format')
    # Validate before creating tables or making any database writes.
    snapshot = (parse_html if format == 'html' else parse_json)(payload, now=now)
    store.all()  # Read-only preflight: never create or migrate an unknown database.
    imported = (now or datetime.now(timezone.utc)).astimezone(timezone.utc).isoformat()
    raw_digest = hashlib.sha256(payload).hexdigest()
    serialized = json.dumps(snapshot, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
    fingerprint = hashlib.sha256(serialized.encode()).hexdigest()
    initialize(store)
    with closing(store.connect()) as connection, connection:
        connection.execute('BEGIN IMMEDIATE')
        previous = connection.execute('SELECT id,status FROM official_statistics_snapshots WHERE fingerprint=?', (fingerprint,)).fetchone()
        if previous:
            return {'changed': 0, 'unchanged': 1, 'conflicts': int(previous['status'] == 'conflict')}
        same_time = connection.execute('SELECT id FROM official_statistics_snapshots WHERE source_url=? AND updated_at=?',
                                       (URL, snapshot['updatedAt'])).fetchall()
        status = 'conflict' if same_time else 'accepted'
        # Retain the earlier accepted payload: a divergent source observation
        # never changes the last usable cache at that timestamp.
        connection.execute('INSERT INTO official_statistics_snapshots(source_url,updated_at,imported_at,fingerprint,source_sha256,status,payload) '
                           'VALUES(?,?,?,?,?,?,?)', (URL, snapshot['updatedAt'], imported, fingerprint, raw_digest, status, serialized))
        connection.execute('INSERT INTO official_statistics_imports(imported_at,source_url,source_sha256,status,detail) VALUES(?,?,?,?,?)',
                           (imported, URL, raw_digest, status, 'same_update_different_content' if same_time else 'structure_validated_reference_pending'))
    return {'changed': int(not same_time), 'unchanged': 0, 'conflicts': int(bool(same_time))}


def compare_history(snapshot, draws):
    """A frequency comparison cannot establish complete individual draw coverage."""
    cutoff = timestamp(snapshot['updatedAt']).date().isoformat()
    rows = [row for row in draws if row['date'] <= cutoff]
    result = {'cutoffDate': cutoff, 'verification': 'not_audited',
              'notice': 'Diferenças são esperadas numa amostra incompleta e não provam concursos em falta.'}
    matches = True
    for field in ('numbers', 'stars'):
        calculated = frequencies(rows, field)
        result['coverage'] = calculated['coverage']
        by_value = {row['value']: row for row in calculated['data']}
        result[field] = []
        for row in snapshot[field]:
            stored = by_value[row['value']]
            difference = row['count'] - stored['count']
            matches = matches and difference == 0
            result[field].append({'value': row['value'], 'officialCount': row['count'],
                                  'storedCount': stored['count'], 'countDifference': difference,
                                  'officialEligibleDraws': row['eligibleDraws'],
                                  'storedEligibleDraws': stored['eligibleDraws']})
    result['countsMatch'] = matches
    return result


def overview(store=None):
    empty = {'available': False, 'data': None, 'prediction': False,
             'notice': 'Sem snapshot importado. Confronto com a captura oficial de 17/10/2026 às 03:00 pendente.'}
    if store is None:
        return empty
    with closing(store.connect(readonly=True)) as connection:
        exists = connection.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='official_statistics_snapshots'").fetchone()
        if not exists:
            return empty
        row = connection.execute("SELECT payload,imported_at,source_sha256 FROM official_statistics_snapshots WHERE status='accepted' "
                                 'ORDER BY updated_at DESC,id DESC LIMIT 1').fetchone()
        conflicts = connection.execute("SELECT COUNT(*) FROM official_statistics_snapshots WHERE status='conflict'").fetchone()[0]
    if not row:
        return {**empty, 'conflicts': conflicts}
    snapshot = json.loads(row['payload'])
    # Revalidate persisted payloads; a corrupted local cache must fail closed.
    validate_snapshot(snapshot)
    return {'available': True, 'data': {**snapshot, 'importedAt': row['imported_at'],
            'sourceSha256': row['source_sha256'], 'validation': 'structure_validated',
            'snapshotReferenceVerified': False}, 'prediction': False, 'conflicts': conflicts,
            'comparison': compare_history(snapshot, store.all()),
            'notice': 'Estatísticas descritivas da fonte declarada; confronto com captura oficial pendente. '
                      'A cobertura dos concursos individuais guardados é independente.'}
