"""Strict reader of the official Euromilhoes result cartaz; standard library only."""
from contextlib import closing
from datetime import date, datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
import re
import sqlite3
from urllib.request import Request, build_opener

from domain import TIERS, validate_result
from rss_import import FeedError, NoRedirect, cents, draw_id, key, winning

URL = 'https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes'
MAX_BYTES = 1024 * 1024
SCHEMA = '''CREATE TABLE IF NOT EXISTS official_observations (
 id INTEGER PRIMARY KEY, source_url TEXT NOT NULL, fingerprint TEXT NOT NULL,
 game TEXT, draw_id TEXT, imported_at TEXT NOT NULL, published_at TEXT,
 status TEXT NOT NULL, payload TEXT, detail TEXT NOT NULL,
 UNIQUE(source_url,fingerprint)
);'''


class Node:
    def __init__(self, tag='', attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def text(self):
        return ' '.join(' '.join(c.text() if isinstance(c, Node) else c for c in self.children).split())

    def find(self, tag, classes=()):
        found = []
        if self.tag == tag and set(classes).issubset(self.attrs.get('class', '').split()):
            found.append(self)
        for child in self.children:
            if isinstance(child, Node):
                found.extend(child.find(tag, classes))
        return found


class Document(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node()
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        if len(self.stack) > 128:
            raise FeedError('Official HTML nesting exceeds limit')
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in ('area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'):
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                break

    def handle_data(self, data):
        if self.stack[-1].tag not in ('script', 'style'):
            self.stack[-1].children.append(data)


def fetch():
    request = Request(URL, headers={'User-Agent': 'LuckyScan50-official/1.0', 'Accept': 'text/html'})
    with build_opener(NoRedirect()).open(request, timeout=20) as response:
        if response.status != 200 or response.url != URL:
            raise FeedError('Unexpected official cartaz HTTP response')
        payload = response.read(MAX_BYTES + 1)
        if len(payload) > MAX_BYTES:
            raise FeedError('Official cartaz exceeds size limit')
        return payload


def count(value):
    if value in ('', '-', '—', 'SEM DADOS'):
        return None
    if not re.fullmatch(r'(?:0|[1-9]\d{0,2}(?:\.\d{3})*|[1-9]\d*)', value):
        raise FeedError('Invalid official winner count')
    return int(value.replace('.', ''))


def parse(payload):
    if not isinstance(payload, bytes) or len(payload) > MAX_BYTES:
        raise FeedError('Invalid official cartaz input')
    encoding = re.search(br'charset\s*=\s*[\'\"]?([A-Za-z0-9_-]+)', payload[:8192], re.I)
    try:
        text = payload.decode('utf-8-sig' if payload.startswith(b'\xef\xbb\xbf') else encoding[1].decode() if encoding else 'utf-8')
        document = Document()
        document.feed(text)
        document.close()
    except (ValueError, LookupError) as exc:
        raise FeedError('Invalid official HTML encoding') from exc
    headers = document.root.find('span', ['dataInfo'])
    if len(headers) != 1:
        raise FeedError('Missing or ambiguous official draw header')
    header = headers[0].text()
    identities = re.findall(r'\bSorteio:\s*(\d{3}/\d{4})\b', header)
    days = re.findall(r'\bData do Sorteio\s*[-:]\s*(\d{2}/\d{2}/\d{4})\b', header)
    if len(identities) != 1 or len(days) != 1:
        raise FeedError('Missing or ambiguous official draw date')
    identity = draw_id(identities[0])
    try:
        day = datetime.strptime(days[0], '%d/%m/%Y').date()
        if day.strftime('%d/%m/%Y') != days[0] or day.year != int(identity[-4:]):
            raise ValueError()
    except ValueError as exc:
        raise FeedError('Invalid official draw date') from exc
    keys = document.root.find('div', ['betMiddle', 'twocol', 'regPad'])
    if len(keys) != 1:
        raise FeedError('Missing or ambiguous official key')
    rows = keys[0].find('ul', ['colums'])
    if len(rows) != 1:
        raise FeedError('Ambiguous official key rows')
    fields = [n.text() for n in rows[0].children if isinstance(n, Node) and n.tag == 'li']
    if not fields:
        raise FeedError('Missing official key')
    values = winning('euromilhoes', fields[0])
    if len(fields) != 2 or winning('euromilhoes', fields[1]) != values:
        raise FeedError('Official key and extraction order disagree')
    if day > datetime.now(timezone.utc).date():
        raise FeedError('Official result draw date is in the future')
    prize_tables = document.root.find('div', ['betMiddle', 'customfiveCol'])
    if len(prize_tables) > 1:
        raise FeedError('Ambiguous official prize table')
    tiers = {}
    for row in prize_tables[0].find('ul', ['colums']) if prize_tables else []:
        cells = [n.text() for n in row.children if isinstance(n, Node) and n.tag == 'li']
        if len(cells) != 5:
            raise FeedError('Invalid official prize row')
        label = re.fullmatch(r'(\d{1,2})\.?º Prémio', cells[0])
        matches = re.fullmatch(r'(\d) Números? \+ (\d) Estrelas?', cells[1])
        if not label or not matches:
            raise FeedError('Invalid official prize identity')
        tier = int(label[1])
        if tier not in range(1, 14) or tier in tiers or tuple(map(int, matches.groups())) != TIERS[tier-1]:
            raise FeedError('Duplicate or inconsistent official tier')
        portugal, total = count(cells[2]), count(cells[3])
        money = cells[4]
        if money in ('', '-', '—', 'SEM DADOS') or re.fullmatch(r'\(\d+\)', money):
            amount = None  # Never follow footnote (1) to the forecast jackpot.
        elif money.startswith('€'):
            amount = cents(money[1:].strip())
            if total == 0:
                if amount != 0:
                    raise FeedError('Amount reported for an unawarded official tier')
                amount = None
        else:
            raise FeedError('Invalid official unit prize')
        tiers[tier] = {'tier': tier, 'main': TIERS[tier-1][0], 'stars': TIERS[tier-1][1],
                       'amountCents': amount, 'winnersPortugal': portugal, 'winnersTotal': total}
    missing = [i for i in range(1, 14) if i not in tiers]
    row = {'game': 'euromilhoes', 'drawId': identity, 'date': day.isoformat(), **values,
           'sourceUrl': URL, 'retrievedAt': datetime.now(timezone.utc).isoformat(),
           'status': 'numbers_confirmed', 'tiers': [tiers.get(i, {'tier': i, 'main': TIERS[i-1][0],
           'stars': TIERS[i-1][1], 'amountCents': None, 'winnersPortugal': None,
           'winnersTotal': None}) for i in range(1,14)]}
    validate_result(row)
    issues = ['Missing official tiers: ' + ','.join(map(str, missing))] if missing else []
    if not missing:
        try:
            validate_result({**row, 'status': 'complete'})
            row['status'] = 'complete'
        except ValueError:
            issues.append('Official prizes pending')
    return row, issues


def record(store, payload, status, detail, row=None, connection=None):
    now = datetime.now(timezone.utc).isoformat()
    fingerprint = hashlib.sha256(payload + (now.encode() if status == 'failed' else b'')).hexdigest()
    values = (URL, fingerprint, row['game'] if row else None, row['drawId'] if row else None,
              now, status, json.dumps(row, ensure_ascii=False) if row else None, json.dumps(detail, ensure_ascii=False))
    sql = ('INSERT INTO official_observations(source_url,fingerprint,game,draw_id,imported_at,status,payload,detail) '
           'VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(source_url,fingerprint) DO UPDATE SET '
           'status=excluded.status,detail=excluded.detail')
    if connection is not None:
        connection.execute(sql, values)
    else:
        with closing(store.connect()) as db, db:
            db.execute(sql, values)


def initialize(store):
    with closing(store.connect()) as db:
        db.executescript(SCHEMA)


def reconcile(store, payload, known_dates=None, conflicting_dates=()):
    """Never replace confirmed content; only compatible partial->complete upgrades."""
    initialize(store)
    try:
        row, issues = parse(payload)
    except ValueError as exc:
        record(store, payload, 'invalid', [str(exc)])
        raise
    identity = (row['game'], row['drawId'])
    conflicts = []
    with closing(store.connect()) as db, db:
        db.execute('BEGIN IMMEDIATE')
        old_row = db.execute('SELECT payload FROM draws WHERE game=? AND draw_id=?', identity).fetchone()
        old = json.loads(old_row[0]) if old_row else None
        if identity in conflicting_dates or (known_dates or {}).get(identity, row['date']) != row['date']:
            conflicts.append('official_date_conflict')
        for observed in db.execute("SELECT payload,status,detail FROM rss_observations WHERE game=? AND draw_id=? AND kind IN ('results','jackpots')", identity):
            if key(json.loads(observed['payload'])) != key(row) or observed['status'] == 'conflict':
                conflicts.append('official_rss_conflict')
        if old:
            if old['date'] != row['date'] or key(old) != key(row):
                conflicts.append('official_existing_key_or_date_conflict')
            for previous, candidate in zip(old['tiers'], row['tiers']):
                for field in ('amountCents', 'winnersPortugal', 'winnersTotal'):
                    before, after = previous[field], candidate[field]
                    if (before is not None and after is not None and before != after) or (
                            old['status'] == 'complete' and field == 'amountCents' and before is None and after is not None) or (
                            field == 'amountCents' and before is not None and after is None and candidate['winnersTotal'] == 0):
                        conflicts.append('official_prize_conflict')
        if conflicts:
            status, imported = 'conflict', {'changed': 0, 'unchanged': 0}
            db.execute("UPDATE rss_observations SET status='conflict',detail='official_cartaz_conflict' WHERE game=? AND draw_id=? AND kind IN ('results','jackpots')", identity)
        elif old and (old['status'] == 'complete' or row['status'] != 'complete'):
            status, imported = 'matched' if old['status'] == 'complete' else 'pending', {'changed': 0, 'unchanged': 1}
        else:
            status = 'accepted' if row['status'] == 'complete' else 'pending'
            imported = store.import_rows([row], source=URL, _connection=db)
        record(store, payload, status, sorted(set(conflicts)) + issues, row, db)
    return {'drawId': row['drawId'], 'date': row['date'], 'status': status,
            'resultStatus': row['status'], 'conflicts': len(set(conflicts)), 'issues': issues, **imported}
