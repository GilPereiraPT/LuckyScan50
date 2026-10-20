"""Official M1lhao parser: independent draw IDs, dates, winning code and prize."""
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
import re

from domain import validate_result
import official_cartaz as official
import rss_import as rss

URL = 'https://www.jogossantacasa.pt/web/SCCartazResult/m1lhao'
initialize = official.initialize


def parse(payload):
    if not isinstance(payload, bytes) or len(payload) > official.MAX_BYTES:
        raise ValueError('Invalid M1lhao HTML input')
    encoding = re.search(br'charset\s*=\s*[\x27"]?([A-Za-z0-9_-]+)', payload[:8192], re.I)
    document = official.Document()
    document.feed(payload.decode(encoding[1].decode() if encoding else 'utf-8-sig'))
    document.close()
    forms = [n for n in document.root.find('form')
             if n.attrs.get('id') == 'frmContestSelection']
    if len(forms) != 1 or forms[0].attrs.get('action') not in (
            URL, '/web/SCCartazResult/m1lhao'):
        raise ValueError('Missing or ambiguous M1lhao result form')
    form = forms[0]
    headers = form.find('span', ['dataInfo'])
    if len(headers) != 1:
        raise ValueError('Missing or ambiguous M1lhao header')
    header = headers[0].text()
    identities = re.findall(r'\bSorteio:\s*(\d{3}/\d{4})\b', header)
    dates = re.findall(r'\bData do Sorteio\s*[-:]\s*(\d{2}/\d{2}/\d{4})\b', header)
    if len(identities) != 1 or len(dates) != 1:
        raise ValueError('Missing or ambiguous M1lhao identity/date')
    identity = rss.draw_id(identities[0])
    day = datetime.strptime(dates[0], '%d/%m/%Y').date()
    if day.strftime('%d/%m/%Y') != dates[0] or day.year != int(identity[-4:]):
        raise ValueError('Invalid M1lhao date')
    if day > datetime.now(timezone.utc).date():
        raise ValueError('Future M1lhao result')
    # Scope to the result form, not navigation, scripts or another game's page.
    codes = re.findall(r'(?<![A-Za-z0-9])([A-Z]{3}\s?\d{5})(?![A-Za-z0-9])', form.text())
    if len(codes) != 1:
        raise ValueError('Expected exactly one official M1lhao winning code; multiple codes require review')
    code = re.sub(r'\s', '', codes[0])
    prizes = []
    for ul in form.find('ul', ['colums']):
        cells = [x.text() for x in ul.children if isinstance(x, official.Node) and x.tag == 'li']
        if len(cells) == 3 and re.fullmatch(r'1\.?º Prémio', cells[0]):
            # A key table row may also have three cells; it is not a prize amount.
            if re.fullmatch(r'[A-Z]{3}\s?\d{5}', cells[1]):
                continue
            prizes.append(cells)
    if len(prizes) > 1:
        raise ValueError('Ambiguous M1lhao prize table')
    amount, issues = None, []
    if prizes:
        _, winners, value = prizes[0]
        count = official.count(winners)
        if count not in (None, 1):
            raise ValueError('Winner count does not match a single winning M1lhao code')
        if value.startswith('€'):
            amount = rss.cents(value[1:].strip())
            if amount <= 0:
                raise ValueError('Invalid M1lhao prize amount')
        elif value not in ('', '-', '—', 'SEM DADOS'):
            raise ValueError('Invalid M1lhao prize value')
        if count is None:
            amount = None
    if amount is None:
        issues.append('Official M1lhao prize pending')
    row = {'game': 'milhao', 'drawId': identity, 'date': day.isoformat(),
           'winningCode': code, 'amountCents': amount, 'sourceUrl': URL,
           'retrievedAt': datetime.now(timezone.utc).isoformat(),
           'status': 'complete' if amount is not None else 'numbers_confirmed'}
    validate_result(row)
    return row, issues


def record(store, payload, status, detail, row=None, connection=None):
    now = datetime.now(timezone.utc).isoformat()
    fingerprint = hashlib.sha256(payload).hexdigest()
    values = (URL, fingerprint, row['game'] if row else None,
              row['drawId'] if row else None, now, status,
              json.dumps(row, ensure_ascii=False) if row else None,
              json.dumps(detail, ensure_ascii=False))
    sql = ('INSERT INTO official_observations(source_url,fingerprint,game,draw_id,imported_at,status,payload,detail) '
           'VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(source_url,fingerprint) DO UPDATE SET '
           'status=excluded.status,detail=excluded.detail')
    if connection is not None:
        connection.execute(sql, values)
    else:
        with closing(store.connect()) as db, db:
            db.execute(sql, values)


def reconcile(store, payload):
    initialize(store)
    row, issues = parse(payload)
    identity = ('milhao', row['drawId'])
    conflicts = []
    with closing(store.connect()) as db, db:
        db.execute('BEGIN IMMEDIATE')
        previous = db.execute('SELECT payload FROM draws WHERE game=? AND draw_id=?', identity).fetchone()
        old = json.loads(previous[0]) if previous else None
        if old:
            if old['date'] != row['date'] or rss.key(old) != rss.key(row):
                conflicts.append('official_existing_code_or_date_conflict')
            if old.get('amountCents') is not None and row['amountCents'] is not None and old['amountCents'] != row['amountCents']:
                conflicts.append('official_prize_conflict')
        for observed in db.execute(
                "SELECT payload,status FROM rss_observations WHERE game=? AND draw_id=? AND kind IN ('results','jackpots')",
                identity):
            if rss.key(json.loads(observed['payload'])) != rss.key(row) or observed['status'] == 'conflict':
                conflicts.append('official_rss_conflict')
        if conflicts:
            status, imported = 'conflict', {'changed': 0, 'unchanged': 0}
        elif old and (row['status'] != 'complete' or (
                old['status'] == 'complete' and old.get('amountCents') is not None)):
            status, imported = 'matched', {'changed': 0, 'unchanged': 1}
        else:
            status = 'accepted' if row['status'] == 'complete' else 'pending'
            imported = store.import_rows([row], source=URL, _connection=db)
        record(store, payload, status, sorted(set(conflicts)) + issues, row, db)
    return {'drawId': row['drawId'], 'date': row['date'], 'status': status,
            'resultStatus': row['status'], 'conflicts': len(set(conflicts)), **imported}
