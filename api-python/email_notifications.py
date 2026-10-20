"""Opt-in Gmail notifications. Separate private SQLite DB; no third-party packages.

No network access happens in request handlers. Only the explicit cron --send
command delivers mail, and only when all server settings are present.
"""
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from email.message import EmailMessage
from email.utils import formataddr, make_msgid
import hashlib
import hmac
import html
import json
import os
from pathlib import Path
import re
import secrets
import smtplib
import sqlite3
import ssl
import time
from urllib.parse import parse_qs, urlencode, urlsplit
from zoneinfo import ZoneInfo

from domain import TIERS, validate_result


class EmailError(Exception):
    def __init__(self, code, status=400):
        self.code, self.status = code, status


@dataclass(frozen=True)
class Config:
    database: str
    base_url: str
    secret: str
    username: str
    password: str
    enabled: bool = False
    daily_limit: int = 200
    batch_limit: int = 20

    @classmethod
    def environment(cls):
        return cls(
            os.environ.get('LUCKYSCAN_EMAIL_DATABASE', ''),
            os.environ.get('LUCKYSCAN_EMAIL_PUBLIC_URL', '').rstrip('/'),
            os.environ.get('LUCKYSCAN_EMAIL_SIGNING_KEY', ''),
            os.environ.get('LUCKYSCAN_GMAIL_USER', ''),
            os.environ.get('LUCKYSCAN_GMAIL_APP_PASSWORD', '').replace(' ', ''),
            os.environ.get('LUCKYSCAN_EMAIL_ENABLED') == '1',
            max(1, min(400, int(os.environ.get('LUCKYSCAN_EMAIL_DAILY_LIMIT', '200')))),
            max(1, min(50, int(os.environ.get('LUCKYSCAN_EMAIL_BATCH_LIMIT', '20')))),
        )

    @property
    def ready(self):
        url = urlsplit(self.base_url)
        return bool(self.enabled and self.database and Path(self.database).is_absolute()
                    and url.scheme == 'https' and url.hostname
                    and not (url.username or url.password or url.query or url.fragment)
                    and len(self.secret) >= 32
                    and re.fullmatch(r'[A-Za-z0-9._%+-]+@gmail\.com', self.username)
                    and re.fullmatch(r'[A-Za-z0-9]{16}', self.password))


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def email_address(value):
    if (not isinstance(value, str) or len(value) > 254 or
            not re.fullmatch(r'[A-Za-z0-9.!#$%&\x27*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', value)):
        raise EmailError('invalid_email')
    return value.lower()


def preferences(value):
    if not isinstance(value, dict):
        raise EmailError('invalid_preferences')
    result = {}
    for key in ('results', 'prizes', 'expiry'):
        if type(value.get(key)) is not bool:
            raise EmailError('invalid_preferences')
        result[key] = value[key]
    if type(value.get('leadDays')) is not int or value['leadDays'] not in (1, 3, 7, 14):
        raise EmailError('invalid_preferences')
    result['leadDays'] = value['leadDays']
    return result


def validate_watches(value):
    if not isinstance(value, list) or len(value) > 500:
        raise EmailError('invalid_watches')
    clean, ids, total = [], set(), 0
    for row in value:
        if not isinstance(row, dict):
            raise EmailError('invalid_watches')
        receipt = row.get('id')
        if not isinstance(receipt, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', receipt) or receipt in ids:
            raise EmailError('invalid_watches')
        ids.add(receipt)
        item = {'id': receipt}
        for field in ('drawIds', 'milhaoDrawIds'):
            values = row.get(field, [])
            if (not isinstance(values, list) or len(values) > 208 or len(set(map(str, values))) != len(values)
                    or any(not isinstance(v, str) or not re.fullmatch(r'\d{3}/\d{4}', v)
                           or int(v[:3]) == 0 for v in values)):
                raise EmailError('invalid_watches')
            item[field] = values
        lines = row.get('lines', [])
        if not isinstance(lines, list) or len(lines) > 500:
            raise EmailError('invalid_watches')
        item['lines'] = []
        for line in lines:
            if not isinstance(line, dict):
                raise EmailError('invalid_watches')
            bet = {}
            for key, count, maximum in (('numbers', 5, 50), ('stars', 2, 12)):
                nums = line.get(key)
                if (not isinstance(nums, list) or len(nums) != count
                        or any(type(n) is not int or not 1 <= n <= maximum for n in nums)
                        or len(set(nums)) != count):
                    raise EmailError('invalid_watches')
                bet[key] = nums
            item['lines'].append(bet)
        codes = row.get('milhaoCodes', [])
        if (not isinstance(codes, list) or len(codes) > 500
                or any(not isinstance(c, str) or not re.fullmatch(r'[A-Z]{3} ?\d{5}', c) for c in codes)):
            raise EmailError('invalid_watches')
        item['milhaoCodes'] = [c.replace(' ', '') for c in codes]
        received = row.get('receivedCents', 0)
        if type(received) is not int or not 0 <= received <= 10**14:
            raise EmailError('invalid_watches')
        item['receivedCents'] = received
        total += len(lines) + len(codes)
        if total > 10000:
            raise EmailError('too_many_watches')
        clean.append(item)
    return clean


class EmailStore:
    def __init__(self, config, clock=None):
        self.config, self.clock = config, clock or time.time

    @contextmanager
    def connect(self):
        path = Path(self.config.database)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Pre-create exclusively so the first database contents are never world-readable.
        fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(fd)
        os.chmod(path, 0o600)
        db = sqlite3.connect(path, timeout=15)
        db.row_factory = sqlite3.Row
        try:
            db.executescript('''
              CREATE TABLE IF NOT EXISTS subscribers (
                id TEXT PRIMARY KEY, email TEXT NOT NULL, status TEXT NOT NULL,
                version TEXT NOT NULL, prefs TEXT NOT NULL, watches TEXT NOT NULL DEFAULT '[]',
                consent_at REAL NOT NULL, confirmed_at REAL, updated_at REAL NOT NULL,
                confirm_until REAL NOT NULL, last_confirmation REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS outbox (
                id INTEGER PRIMARY KEY, subscriber TEXT NOT NULL, event TEXT NOT NULL,
                category TEXT NOT NULL, version TEXT NOT NULL, subject TEXT NOT NULL,
                body TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'queued',
                created_at REAL NOT NULL, next_attempt REAL NOT NULL DEFAULT 0,
                attempts INTEGER NOT NULL DEFAULT 0, attempted_at REAL,
                UNIQUE(subscriber,event));
              CREATE TABLE IF NOT EXISTS rate_limits (
                key TEXT NOT NULL, bucket INTEGER NOT NULL, count INTEGER NOT NULL,
                PRIMARY KEY(key,bucket));
              CREATE INDEX IF NOT EXISTS outbox_state ON outbox(state,next_attempt);
              CREATE TABLE IF NOT EXISTS send_attempts (attempted_at REAL NOT NULL);
            ''')
            with db:
                db.execute('BEGIN IMMEDIATE')
                yield db
        finally:
            db.close()

    def authenticate(self, environ):
        header = environ.get('HTTP_AUTHORIZATION', '')
        if not re.fullmatch(r'Bearer [0-9a-f]{64}', header):
            raise EmailError('unauthorized', 401)
        return digest(header[7:])

    def rate(self, db, key, maximum, seconds=3600):
        bucket = int(self.clock()) // seconds
        key = hmac.new(self.config.secret.encode(), key.encode(), hashlib.sha256).hexdigest()
        row = db.execute('SELECT count FROM rate_limits WHERE key=? AND bucket=?', (key, bucket)).fetchone()
        if row and row[0] >= maximum:
            raise EmailError('rate_limited', 429)
        db.execute('INSERT INTO rate_limits VALUES(?,?,1) ON CONFLICT(key,bucket) DO UPDATE SET count=count+1', (key, bucket))
        db.execute('DELETE FROM rate_limits WHERE bucket<?', (bucket - 48,))

    def link(self, row, purpose):
        token = hmac.new(self.config.secret.encode(),
                         f'{purpose}:{row["id"]}:{row["version"]}'.encode(), hashlib.sha256).hexdigest()
        return self.config.base_url + '/v1/email/' + purpose + '?' + urlencode({'id': row['id'], 'token': token})

    def valid_link(self, row, purpose, token):
        expected = parse_qs(urlsplit(self.link(row, purpose)).query)['token'][0]
        return isinstance(token, str) and hmac.compare_digest(expected, token)

    def enqueue(self, db, row, event, category, subject, body):
        db.execute('INSERT OR IGNORE INTO outbox(subscriber,event,category,version,subject,body,created_at) VALUES(?,?,?,?,?,?,?)',
                   (row['id'], event, category, row['version'], subject, body, self.clock()))

    def subscribe(self, identity, payload, remote):
        if not isinstance(payload, dict) or payload.get('consent') is not True:
            raise EmailError('consent_required')
        address, prefs = email_address(payload.get('email')), preferences(payload.get('preferences'))
        now = self.clock()
        with self.connect() as db:
            self.rate(db, 'ip:' + remote, 30)
            self.rate(db, 'email:' + address, 6)
            old = db.execute('SELECT * FROM subscribers WHERE id=?', (identity,)).fetchone()
            same = old and old['email'] == address and old['status'] != 'revoked'
            active = same and old['status'] == 'active'
            version = old['version'] if same else secrets.token_hex(16)
            if not same:
                db.execute('DELETE FROM outbox WHERE subscriber=?', (identity,))
            watches = old['watches'] if active else '[]'
            db.execute('''INSERT INTO subscribers(id,email,status,version,prefs,watches,consent_at,
                confirmed_at,updated_at,confirm_until,last_confirmation) VALUES(?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET email=excluded.email,status=excluded.status,
                version=excluded.version,prefs=excluded.prefs,watches=excluded.watches,
                consent_at=excluded.consent_at,confirmed_at=excluded.confirmed_at,
                updated_at=excluded.updated_at,confirm_until=excluded.confirm_until,
                last_confirmation=excluded.last_confirmation''',
                (identity, address, 'active' if active else 'pending', version, json.dumps(prefs), watches,
                 old['consent_at'] if same else now,
                 old['confirmed_at'] if active else None, now,
                 old['confirm_until'] if same else now + 86400,
                 old['last_confirmation'] if same else now))
            row = db.execute('SELECT * FROM subscribers WHERE id=?', (identity,)).fetchone()
            if not active and (not same or now - old['last_confirmation'] >= 900):
                # Rotate the link for an explicit resend, invalidating stale queued copies.
                if same:
                    db.execute('UPDATE subscribers SET version=?,confirm_until=?,last_confirmation=? WHERE id=?',
                               (secrets.token_hex(16), now + 86400, now, identity))
                    db.execute("UPDATE outbox SET state='cancelled' WHERE subscriber=? AND state='queued'", (identity,))
                    row = db.execute('SELECT * FROM subscribers WHERE id=?', (identity,)).fetchone()
                self.enqueue(db, row, 'confirm:' + row['version'], 'confirm',
                             'Confirme os avisos do LuckyScan50',
                             'Foi pedida uma subscrição de avisos do LuckyScan50 para este endereço.\n\n'
                             'Para confirmar, abra a ligação e escolha Confirmar:\n' + self.link(row, 'confirm') +
                             '\n\nA ligação é válida por 24 horas. Se não fez este pedido, ignore a mensagem.\n')
            return {'status': row['status'], 'email': address}

    def status(self, identity):
        with self.connect() as db:
            row = db.execute('SELECT status,email,updated_at FROM subscribers WHERE id=?', (identity,)).fetchone()
            return dict(row) if row else {'status': 'not_subscribed'}

    def revoke(self, identity):
        with self.connect() as db:
            db.execute("UPDATE subscribers SET status='revoked',email='',watches='[]',version=? WHERE id=?",
                       (secrets.token_hex(16), identity))
            db.execute('DELETE FROM outbox WHERE subscriber=?', (identity,))
        return {'status': 'revoked'}

    def watches(self, identity, value):
        clean = validate_watches(value)
        with self.connect() as db:
            row = db.execute('SELECT status FROM subscribers WHERE id=?', (identity,)).fetchone()
            if not row or row['status'] != 'active':
                raise EmailError('confirmation_required', 409)
            db.execute('UPDATE subscribers SET watches=?,updated_at=? WHERE id=?',
                       (json.dumps(clean), self.clock(), identity))
            # Discard queued personal reminders; the next cron recomputes from fresh data.
            db.execute("DELETE FROM outbox WHERE subscriber=? AND category IN ('prizes','expiry') AND state='queued'", (identity,))
        return {'status': 'active', 'receipts': len(clean)}

    def act_on_link(self, identity, token, purpose, apply=False):
        with self.connect() as db:
            row = db.execute('SELECT * FROM subscribers WHERE id=?', (identity,)).fetchone()
            if not row or row['status'] == 'revoked' or not self.valid_link(row, purpose, token):
                raise EmailError('invalid_link')
            if purpose == 'confirm' and self.clock() > row['confirm_until']:
                raise EmailError('expired_link')
            if apply:
                if purpose == 'confirm':
                    db.execute("UPDATE subscribers SET status='active',confirmed_at=COALESCE(confirmed_at,?) WHERE id=?",
                               (self.clock(), identity))
                    db.execute("UPDATE outbox SET state='cancelled' WHERE subscriber=? AND category='confirm' AND state='queued'", (identity,))
                else:
                    db.execute("UPDATE subscribers SET status='revoked',email='',watches='[]',version=? WHERE id=?",
                               (secrets.token_hex(16), identity))
                    db.execute('DELETE FROM outbox WHERE subscriber=?', (identity,))
        return {'status': 'active' if purpose == 'confirm' else 'revoked'}


def deadline_map(path):
    """Only explicitly reviewed, source-attributed deadlines; never infer legal dates."""
    if not path:
        return {}
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        raise ValueError('Invalid deadlines file')
    for key, value in data.items():
        if not re.fullmatch(r'(euromilhoes|milhao):\d{3}/\d{4}', key) or not isinstance(value, dict):
            raise ValueError('Invalid deadline')
        day = date.fromisoformat(value['deadline'])
        checked = date.fromisoformat(value['verifiedAt'])
        url = urlsplit(value['sourceUrl'])
        if (day.isoformat() != value['deadline'] or checked.isoformat() != value['verifiedAt']
                or url.scheme != 'https' or url.hostname not in ('www.jogossantacasa.pt', 'jogossantacasa.pt')
                or url.username or url.password):
            raise ValueError('Deadline requires reviewed official provenance')
    return data


def awards(watch, results):
    found = []
    for game, ids in (('euromilhoes', watch['drawIds']), ('milhao', watch['milhaoDrawIds'])):
        for identity in ids:
            row = results.get(game + ':' + identity)
            if not row or row['status'] != 'complete':
                continue
            amount = 0
            if game == 'euromilhoes':
                ns, ss = set(row['numbers']), set(row['stars'])
                for line in watch['lines']:
                    matches = (len(ns.intersection(line['numbers'])), len(ss.intersection(line['stars'])))
                    if matches in TIERS:
                        amount += row['tiers'][TIERS.index(matches)]['amountCents'] or 0
            elif row['winningCode'].replace(' ', '') in watch['milhaoCodes']:
                amount = row.get('amountCents') or 0
            if amount > 0:
                found.append((game + ':' + identity, amount))
    return found


def plan_messages(store, rows, deadlines=None, apply=False):
    for row in rows:
        validate_result(row)
    index = {r['game'] + ':' + r['drawId']: r for r in rows}
    today = datetime.fromtimestamp(store.clock(), timezone.utc).astimezone(ZoneInfo('Europe/Lisbon')).date()
    counts = {'results': 0, 'prizes': 0, 'expiry': 0}
    with store.connect() as db:
        for subscriber in db.execute("SELECT * FROM subscribers WHERE status='active'").fetchall():
            prefs = json.loads(subscriber['prefs'])
            since = datetime.fromtimestamp(subscriber['consent_at'], timezone.utc).astimezone(ZoneInfo('Europe/Lisbon')).date()
            events = []
            if prefs['results']:
                for key, row in index.items():
                    if row['status'] != 'complete' or not since.isoformat() <= row['date'] <= today.isoformat():
                        continue
                    content = {k: v for k, v in row.items() if k != 'retrievedAt'}
                    fingerprint = digest(json.dumps(content, sort_keys=True))[:20]
                    label = ('M1lhão' if row['game'] == 'milhao' else 'Euromilhões') + ' ' + row['drawId']
                    numbers = (row['winningCode'] if row['game'] == 'milhao' else
                               ' '.join(f'{n:02}' for n in row['numbers']) + ' · Estrelas: ' + ' '.join(f'{n:02}' for n in row['stars']))
                    events.append(('result:' + key + ':' + fingerprint, 'results',
                                   'LuckyScan50 — resultado ' + label,
                                   f'{label}\nData: {row["date"]}\nChave: {numbers}\n\nFonte: {row["sourceUrl"]}\n'))
            for watch in json.loads(subscriber['watches']):
                prizes = [(key, amount) for key, amount in awards(watch, index)
                          if key not in (deadlines or {})
                          or date.fromisoformat(deadlines[key]['deadline']) >= today]
                if sum(amount for _, amount in prizes) <= watch['receivedCents']:
                    continue
                stamp = 'Dados da carteira sincronizados em ' + datetime.fromtimestamp(subscriber['updated_at'], timezone.utc).isoformat() + '.\n'
                outstanding = sum(amount for _, amount in prizes) - watch['receivedCents']
                if prefs['prizes']:
                    # A weekly reminder per receipt; a changed receipt is evaluated again next week.
                    event = f'prize:{watch["id"]}:{today.isocalendar().year}:{today.isocalendar().week}'
                    events.append((event, 'prizes', 'LuckyScan50 — prémio por levantar',
                                   f'Um recibo tem {outstanding / 100:.2f} € em prémios identificados ainda não registados como recebidos.\n'
                                   'Abra a app, confirme o recibo e atualize o recebimento se já levantou o prémio.\n' + stamp))
                if prefs['expiry']:
                    for key, _ in prizes:
                        deadline = (deadlines or {}).get(key)
                        if not deadline:
                            continue
                        remaining = (date.fromisoformat(deadline['deadline']) - today).days
                        if 0 <= remaining <= prefs['leadDays']:
                            # One advance warning and one final-day warning, never a daily flood.
                            phase = 'last' if remaining == 0 else 'advance'
                            event = f'expiry:{watch["id"]}:{key}:{deadline["deadline"]}:{phase}'
                            events.append((event, 'expiry', 'LuckyScan50 — prazo de levantamento próximo',
                                           f'Concurso: {key}\nData-limite validada: {deadline["deadline"]}\n'
                                           f'Faltam {remaining} dia(s). Confirme se já levantou o prémio.\n'
                                           f'Fonte: {deadline["sourceUrl"]}\n' + stamp))
            for event, category, subject, body in events:
                if db.execute('SELECT 1 FROM outbox WHERE subscriber=? AND event=?', (subscriber['id'], event)).fetchone():
                    continue
                counts[category] += 1
                if apply:
                    store.enqueue(db, subscriber, event, category, subject, body)
    return counts


def gmail_send(config, message):
    context = ssl.create_default_context()
    smtp = smtplib.SMTP('smtp.gmail.com', 587, timeout=30)
    try:
        smtp.ehlo()
        smtp.starttls(context=context)
        smtp.ehlo()
        smtp.login(config.username, config.password)
        smtp.send_message(message)
    finally:
        # Do not turn a QUIT failure after DATA acceptance into a resend.
        smtp.close()


def deliver(store, sender=gmail_send):
    """Reserve before SMTP. Ambiguous transport failures are NOT automatically retried."""
    if not store.config.ready:
        raise EmailError('email_not_configured', 503)
    sent = failed = uncertain = 0
    for _ in range(store.config.batch_limit):
        with store.connect() as db:
            if db.execute('SELECT COUNT(*) FROM send_attempts WHERE attempted_at>?', (store.clock() - 86400,)).fetchone()[0] >= store.config.daily_limit:
                break
            # A previous killed process may have submitted its email already.
            db.execute("UPDATE outbox SET state='uncertain' WHERE state='sending' AND attempted_at<?", (store.clock() - 600,))
            queued = db.execute("SELECT * FROM outbox WHERE state='queued' AND next_attempt<=? ORDER BY category='confirm' DESC,id LIMIT 1", (store.clock(),)).fetchone()
            if not queued:
                break
            subscriber = db.execute('SELECT * FROM subscribers WHERE id=?', (queued['subscriber'],)).fetchone()
            if (not subscriber or subscriber['version'] != queued['version'] or subscriber['status'] == 'revoked'
                    or (queued['category'] == 'confirm' and
                        (subscriber['status'] != 'pending' or store.clock() > subscriber['confirm_until']))
                    or (queued['category'] != 'confirm' and (subscriber['status'] != 'active'
                        or not json.loads(subscriber['prefs']).get(queued['category'])))):
                db.execute("UPDATE outbox SET state='cancelled' WHERE id=?", (queued['id'],))
                continue
            db.execute("UPDATE outbox SET state='sending',attempts=attempts+1,attempted_at=? WHERE id=?", (store.clock(), queued['id']))
            db.execute('INSERT INTO send_attempts VALUES(?)', (store.clock(),))
        message = EmailMessage()
        message['From'] = formataddr(('LuckyScan50', store.config.username))
        message['To'] = subscriber['email']
        message['Subject'] = queued['subject']
        message['Message-ID'] = make_msgid(idstring=f'luckyscan50-{queued["id"]}', domain='gmail.com')
        unsubscribe = store.link(subscriber, 'unsubscribe')
        message['List-Unsubscribe'] = '<' + unsubscribe + '>'
        message['List-Unsubscribe-Post'] = 'List-Unsubscribe=One-Click'
        body = queued['body'] + '\nCancelar todos os avisos:\n' + unsubscribe + '\n\nLuckyScan50 — aplicação independente dos Jogos Santa Casa.\n'
        message.set_content(body)
        confirm = ('<p><a href="' + html.escape(store.link(subscriber, 'confirm'), quote=True) +
                   '">Confirmar o meu email</a></p>') if queued['category'] == 'confirm' else ''
        message.add_alternative('<!doctype html><html lang="pt-PT"><body><h2>LuckyScan50</h2>' + confirm + '<p>' +
                                html.escape(queued['body']).replace('\n', '<br>') +
                                '</p><p><a href="' + html.escape(unsubscribe, quote=True) +
                                '">Cancelar os avisos</a></p><p>Aplicação independente dos Jogos Santa Casa.</p></body></html>', subtype='html')
        state, next_attempt, stop = 'sent', 0, False
        try:
            sender(store.config, message)
            sent += 1
        except smtplib.SMTPAuthenticationError:
            state, failed, stop = 'failed', failed + 1, True
        except smtplib.SMTPRecipientsRefused:
            state, failed = 'failed', failed + 1
        except smtplib.SMTPResponseException as exc:
            # An explicit 4xx rejection means SMTP did not accept this message.
            retry = 400 <= exc.smtp_code < 500 and queued['attempts'] < 2
            state = 'queued' if retry else 'failed'
            next_attempt = store.clock() + 900 * (queued['attempts'] + 1)
            failed += 1
        except (OSError, smtplib.SMTPException):
            state, uncertain = 'uncertain', uncertain + 1
        with store.connect() as db:
            db.execute('UPDATE outbox SET state=?,next_attempt=? WHERE id=?', (state, next_attempt, queued['id']))
        if stop:
            break
    return {'sent': sent, 'failed': failed, 'uncertain': uncertain}


def maintenance(store):
    with store.connect() as db:
        stale = [r[0] for r in db.execute("SELECT id FROM subscribers WHERE status='pending' AND confirm_until<?", (store.clock() - 7 * 86400,))]
        for identity in stale:
            db.execute('DELETE FROM outbox WHERE subscriber=?', (identity,))
            db.execute('DELETE FROM subscribers WHERE id=?', (identity,))
        db.execute("UPDATE outbox SET body='' WHERE created_at<? AND state IN ('sent','cancelled','failed','uncertain')", (store.clock() - 30 * 86400,))
        db.execute('DELETE FROM send_attempts WHERE attempted_at<?', (store.clock() - 2 * 86400,))


def handle_request(environ, start_response, config=None):
    """Return None for unrelated routes, preserving the public read-only API."""
    path = environ.get('PATH_INFO', '')
    if not path.startswith('/v1/email/'):
        return None
    def reply(status, data, html_page=False):
        body = data.encode() if html_page else json.dumps(data, ensure_ascii=False).encode()
        reason = {200: 'OK', 202: 'Accepted', 400: 'Bad Request', 401: 'Unauthorized', 404: 'Not Found',
                  405: 'Method Not Allowed', 409: 'Conflict', 413: 'Payload Too Large', 429: 'Too Many Requests', 503: 'Service Unavailable'}[status]
        start_response(f'{status} {reason}', [('Content-Type', 'text/html; charset=utf-8' if html_page else 'application/json; charset=utf-8'),
            ('Content-Length', str(len(body))), ('Cache-Control', 'no-store'), ('Referrer-Policy', 'no-referrer'),
            ('X-Content-Type-Options', 'nosniff'), ('Content-Security-Policy', "default-src 'none'; form-action 'self'; frame-ancestors 'none'")])
        return [body]
    try:
        config = config or Config.environment()
        if path == '/v1/email/status' and environ.get('REQUEST_METHOD') == 'GET':
            return reply(200, {'available': config.ready, 'provider': 'gmail', 'requiresConfirmation': True})
        if not config.ready:
            return reply(503, {'error': 'email_not_configured'})
        store = EmailStore(config)
        method = environ.get('REQUEST_METHOD')
        if path in ('/v1/email/confirm', '/v1/email/unsubscribe'):
            if method not in ('GET', 'POST'):
                raise EmailError('method_not_allowed', 405)
            params = parse_qs(environ.get('QUERY_STRING', ''), keep_blank_values=True)
            if set(params) != {'id', 'token'} or any(len(v) != 1 for v in params.values()):
                raise EmailError('invalid_link')
            identity, token = params['id'][0], params['token'][0]
            purpose = path.rsplit('/', 1)[1]
            result = store.act_on_link(identity, token, purpose, apply=method == 'POST')
            text = ('Email confirmado. Pode voltar à app e sincronizar a carteira.' if purpose == 'confirm'
                    else 'Subscrição cancelada. Não receberá mais avisos.') if method == 'POST' else (
                    'Confirmar os avisos do LuckyScan50' if purpose == 'confirm' else 'Cancelar todos os avisos do LuckyScan50')
            form = '' if method == 'POST' else '<form method="post"><button type="submit">' + text + '</button></form>'
            return reply(200, '<!doctype html><html lang="pt-PT"><meta name="viewport" content="width=device-width"><title>LuckyScan50</title><h1>LuckyScan50</h1><p>' + text + '</p>' + form + '</html>', True)
        if path not in ('/v1/email/subscription', '/v1/email/watches'):
            raise EmailError('not_found', 404)
        identity = store.authenticate(environ)
        if path.endswith('/subscription') and method == 'GET':
            return reply(200, store.status(identity))
        if path.endswith('/subscription') and method == 'DELETE':
            return reply(200, store.revoke(identity))
        if method not in ('POST', 'PUT'):
            raise EmailError('method_not_allowed', 405)
        length = int(environ.get('CONTENT_LENGTH') or '0')
        if not 0 < length <= 1048576:
            raise EmailError('invalid_body_size', 413)
        if environ.get('CONTENT_TYPE', '').split(';')[0].strip() != 'application/json':
            raise EmailError('json_required')
        raw = environ['wsgi.input'].read(length)
        if len(raw) != length:
            raise EmailError('invalid_body')
        payload = json.loads(raw)
        if path.endswith('/subscription'):
            return reply(202, store.subscribe(identity, payload, environ.get('REMOTE_ADDR', 'unknown')))
        return reply(200, store.watches(identity, payload))
    except EmailError as exc:
        return reply(exc.status, {'error': exc.code})
    except (ValueError, TypeError, KeyError, UnicodeError, RecursionError):
        return reply(400, {'error': 'invalid_request'})
    except (sqlite3.Error, OSError):
        return reply(503, {'error': 'email_storage_unavailable'})
