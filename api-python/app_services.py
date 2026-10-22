"""Owner entitlements and opt-in, content-free app metrics. Stdlib only.

Separate private database; disabled unless a path and secret are configured.
No purchase claims are accepted here: paid entitlements require store verification.
"""
from contextlib import contextmanager
from datetime import datetime, timezone
from http.cookies import SimpleCookie
import hashlib
import base64
import hmac
import html
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time
from urllib.parse import parse_qs

EVENTS = frozenset(('app_open', 'scan_camera', 'scan_import', 'scan_error',
                   'receipt_saved_manual', 'receipt_saved_import'))
RETENTION_DAYS = 90
PANEL_STYLE = """body{font:16px system-ui,sans-serif;background:#0c1523;color:#e6edf7;margin:0;padding:clamp(16px,4vw,48px)}main{max-width:1100px;margin:auto}h1{color:#e7c77f}p{line-height:1.6}table{width:100%;border-collapse:collapse;background:#132238}th,td{text-align:left;padding:12px;border-bottom:1px solid #304058}th{color:#e7c77f}a{color:#e7c77f}input,button{font:inherit;padding:12px;margin:8px;border-radius:8px}button{background:#e7c77f;color:#0c1523;border:0;cursor:pointer}.scroll{overflow:auto}.cards{display:flex;gap:16px;flex-wrap:wrap}.card{background:#132238;padding:24px;border-radius:12px;flex:1}.card strong{display:block;font-size:36px;color:#e7c77f}"""
STYLE_HASH = base64.b64encode(hashlib.sha256(PANEL_STYLE.encode()).digest()).decode()

def panel(title, content):
    return f'<!doctype html><html lang="pt"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>{title}</title><style>{PANEL_STYLE}</style></head><body><main>{content}</main></body></html>'

SCHEMA = '''
CREATE TABLE IF NOT EXISTS licenses (
 id INTEGER PRIMARY KEY, key_hash TEXT UNIQUE NOT NULL, bound_install TEXT,
 revoked INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS owner_sessions (
 token_hash TEXT PRIMARY KEY, license_id INTEGER NOT NULL, install TEXT NOT NULL,
 expires INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS metric_installs (
 token_hash TEXT PRIMARY KEY, created_at INTEGER NOT NULL, last_seen INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS metric_events (
 id TEXT PRIMARY KEY, install TEXT NOT NULL, day TEXT NOT NULL,
 name TEXT NOT NULL, version TEXT NOT NULL, platform TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS metric_event_day ON metric_events(day);
CREATE INDEX IF NOT EXISTS metric_event_install ON metric_events(install,day);
CREATE TABLE IF NOT EXISTS rate_limits (
 bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL);
'''


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


@contextmanager
def database(path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    # Create with restrictive permissions before SQLite opens it.
    fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
    os.close(fd)
    os.chmod(path, 0o600)
    db = sqlite3.connect(path, timeout=5)
    try:
        db.executescript(SCHEMA)
        with db:
            yield db
    finally:
        db.close()


class RequestError(Exception):
    def __init__(self, code, status=400):
        self.code, self.status = code, status


def read_body(env, form=False):
    expected = 'application/x-www-form-urlencoded' if form else 'application/json'
    if env.get('CONTENT_TYPE', '').split(';')[0] != expected:
        raise RequestError('invalid_content_type')
    try:
        size = int(env.get('CONTENT_LENGTH', '0'))
        if not 0 < size <= 2048:
            raise RequestError('invalid_size', 413)
        raw = env['wsgi.input'].read(size)
        data = parse_qs(raw.decode(), strict_parsing=True) if form else json.loads(raw)
        if not isinstance(data, dict):
            raise ValueError()
        return data
    except (ValueError, UnicodeError, KeyError):
        raise RequestError('invalid_body') from None


def token(env):
    value = env.get('HTTP_AUTHORIZATION', '')
    if not value.startswith('Bearer ') or not re.fullmatch(r'[A-Za-z0-9_-]{40,100}', value[7:]):
        raise RequestError('unauthorized', 401)
    return value[7:]


def limited(db, bucket, maximum, now, window=86400):
    bucket = f'{bucket}:{now // window}'
    db.execute('INSERT OR IGNORE INTO rate_limits VALUES(?,0,?)', (bucket, now + window))
    db.execute('UPDATE rate_limits SET count=count+1 WHERE bucket=?', (bucket,))
    return db.execute('SELECT count FROM rate_limits WHERE bucket=?', (bucket,)).fetchone()[0] <= maximum


def clean(db, now):
    cutoff = datetime.fromtimestamp(now - RETENTION_DAYS * 86400, timezone.utc).date().isoformat()
    db.execute('DELETE FROM metric_events WHERE day<=?', (cutoff,))
    db.execute('DELETE FROM metric_installs WHERE last_seen<?', (now - RETENTION_DAYS * 86400,))
    db.execute('DELETE FROM owner_sessions WHERE expires<?', (now,))
    db.execute('DELETE FROM rate_limits WHERE expires<?', (now,))


def report(db, now):
    since = datetime.fromtimestamp(now - 6 * 86400, timezone.utc).date().isoformat()
    return {
        'retentionDays': RETENTION_DAYS,
        'metric': 'consenting_installations_not_people',
        'installations': db.execute('SELECT count(*) FROM metric_installs').fetchone()[0],
        'active7Days': db.execute("SELECT count(DISTINCT install) FROM metric_events WHERE day>=? AND name='app_open'", (since,)).fetchone()[0],
        'daily': [dict(zip(('day', 'event', 'version', 'platform', 'count'), row)) for row in db.execute(
            'SELECT day,name,version,platform,count(*) FROM metric_events GROUP BY day,name,version,platform ORDER BY day DESC')],
    }


def admin_cookie(secret, value=None, now=None):
    now = int(time.time()) if now is None else now
    if value is None:
        payload = f'{now + 3600}.{secrets.token_hex(16)}'
        return payload + '.' + hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
    try:
        expiry, nonce, signature = value.split('.')
        payload = f'{expiry}.{nonce}'
        return now < int(expiry) <= now + 3600 and hmac.compare_digest(
            signature, hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest())
    except (ValueError, TypeError):
        return False


def handle_request(env, start):
    path = env.get('PATH_INFO', '')
    if not (path.startswith('/v1/app/') or path.startswith('/admin/app')):
        return None
    status_names = {200: 'OK', 201: 'Created', 400: 'Bad Request', 401: 'Unauthorized',
                    403: 'Forbidden', 404: 'Not Found', 405: 'Method Not Allowed',
                    413: 'Payload Too Large', 429: 'Too Many Requests', 503: 'Service Unavailable'}

    def reply(status, data, markup=False, extra=()):
        body = data.encode() if markup else json.dumps(data, separators=(',', ':')).encode()
        headers = [('Content-Type', 'text/html; charset=utf-8' if markup else 'application/json'),
                   ('Content-Length', str(len(body))), ('Cache-Control', 'no-store'),
                   ('X-Content-Type-Options', 'nosniff'), ('Referrer-Policy', 'no-referrer'),
                   ('Content-Security-Policy', f"default-src 'none'; style-src 'sha256-{STYLE_HASH}'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"), *extra]
        start(f'{status} {status_names[status]}', headers)
        return [body]

    db_path = os.environ.get('LUCKYSCAN_APP_DATABASE', '')
    secret = os.environ.get('LUCKYSCAN_APP_SECRET', '')
    admin = os.environ.get('LUCKYSCAN_ADMIN_TOKEN', '')
    if not db_path or len(secret) < 32:
        return reply(503, {'error': 'app_services_not_configured'})
    method = env.get('REQUEST_METHOD', 'GET')
    now = int(time.time())
    day = datetime.fromtimestamp(now, timezone.utc).date().isoformat()
    # Do not trust caller-supplied forwarding headers.
    ip_key = hmac.new(secret.encode(), f"{day}:{env.get('REMOTE_ADDR', 'unknown')}".encode(), hashlib.sha256).hexdigest()
    try:
        with database(db_path) as db:
            clean(db, now)
            if path.startswith('/admin/app'):
                if len(admin) < 32 or hmac.compare_digest(admin, secret):
                    return reply(503, {'error': 'admin_not_configured'})
                if path == '/admin/app/login' and method == 'POST':
                    if not limited(db, 'admin:' + ip_key, 10, now, 3600):
                        return reply(429, {'error': 'rate_limited'})
                    supplied = read_body(env, form=True).get('token', [])
                    if len(supplied) != 1 or not hmac.compare_digest(digest(supplied[0]), digest(admin)):
                        return reply(401, {'error': 'unauthorized'})
                    cookie = admin_cookie(secret + admin, now=now)
                    return reply(200, '<p>Sessão iniciada. <a href="/admin/app">Abrir painel</a></p>', True,
                                 [('Set-Cookie', f'ls_admin={cookie}; Path=/admin/app; HttpOnly; Secure; SameSite=Strict; Max-Age=3600')])
                if path == '/admin/app/licenses':
                    # Mutations accept a server-to-server Bearer token only, never
                    # browser cookies. WordPress also checks capability and nonce.
                    authorization = env.get('HTTP_AUTHORIZATION', '')
                    if not hmac.compare_digest(digest(authorization), digest('Bearer ' + admin)):
                        return reply(401, {'error': 'unauthorized'})
                    if method == 'GET':
                        rows = db.execute('SELECT id,bound_install IS NOT NULL,revoked,created_at FROM licenses ORDER BY id DESC LIMIT 100').fetchall()
                        return reply(200, {'licenses': [dict(zip(('id', 'bound', 'revoked', 'createdAt'), row)) for row in rows]})
                    if method != 'POST':
                        return reply(405, {'error': 'method_not_allowed'})
                    if not limited(db, 'licenses:' + digest(admin), 30, now, 3600):
                        return reply(429, {'error': 'rate_limited'})
                    data = read_body(env)
                    if data == {'action': 'create'}:
                        key = secrets.token_urlsafe(32)
                        cursor = db.execute('INSERT INTO licenses(key_hash,created_at) VALUES(?,?)', (digest(key), now))
                        return reply(201, {'id': cursor.lastrowid, 'activationKey': key})
                    if set(data) == {'action', 'id'} and data['action'] == 'revoke' and type(data['id']) is int and data['id'] > 0:
                        if not db.execute('UPDATE licenses SET revoked=1 WHERE id=?', (data['id'],)).rowcount:
                            return reply(404, {'error': 'license_not_found'})
                        db.execute('DELETE FROM owner_sessions WHERE license_id=?', (data['id'],))
                        return reply(200, {'revoked': True, 'id': data['id']})
                    raise RequestError('invalid_license_action')
                if method != 'GET':
                    return reply(405, {'error': 'method_not_allowed'})
                cookies = SimpleCookie()
                try:
                    cookies.load(env.get('HTTP_COOKIE', ''))
                except Exception:
                    raise RequestError('unauthorized', 401) from None
                session = cookies.get('ls_admin')
                authenticated = bool(session and admin_cookie(secret + admin, session.value, now))
                authorization = env.get('HTTP_AUTHORIZATION', '')
                authenticated = authenticated or hmac.compare_digest(digest(authorization), digest('Bearer ' + admin))
                if not authenticated:
                    if path == '/admin/app':
                        return reply(200, panel('LuckyScan50 — acesso privado', '<h1>LuckyScan50</h1><form method="post" action="/admin/app/login"><label>Chave de administrador <input type="password" name="token" required autocomplete="current-password"></label><button>Entrar</button></form>'), True)
                    return reply(401, {'error': 'unauthorized'})
                data = report(db, now)
                if path == '/admin/app/logout':
                    return reply(200, panel('Sessão terminada', '<h1>Sessão terminada</h1><a href="/admin/app">Entrar novamente</a>'), True, [('Set-Cookie', 'ls_admin=; Path=/admin/app; HttpOnly; Secure; SameSite=Strict; Max-Age=0')])
                if path == '/admin/app/statistics':
                    return reply(200, data)
                if path != '/admin/app':
                    return reply(404, {'error': 'not_found'})
                rows = ''.join('<tr>' + ''.join(f'<td>{html.escape(str(row[k]))}</td>' for k in ('day', 'event', 'version', 'platform', 'count')) + '</tr>' for row in data['daily'])
                return reply(200, panel('LuckyScan50 — estatísticas', f'<h1>LuckyScan50 — estatísticas privadas</h1><div class="cards"><div class="card">Instalações com consentimento<strong>{data["installations"]}</strong></div><div class="card">Ativas nos últimos 7 dias<strong>{data["active7Days"]}</strong></div></div><p>Retenção: 90 dias. Instalações, não pessoas. Apenas utilizações com partilha ativada.</p><div class="scroll"><table><thead><tr><th>Dia UTC</th><th>Evento</th><th>Versão</th><th>Plataforma</th><th>Contagem</th></tr></thead><tbody>{rows}</tbody></table></div><p><a href="/admin/app/statistics">Consultar JSON</a> · <a href="/admin/app/logout">Terminar sessão</a></p>'), True)
            if path == '/v1/app/metrics/register' and method == 'POST':
                consent = read_body(env)
                if consent != {'consentVersion': 1} or type(consent.get('consentVersion')) is not int:
                    raise RequestError('invalid_consent')
                if not limited(db, 'register:' + ip_key, 20, now) or not limited(db, 'register:global', 10000, now):
                    return reply(429, {'error': 'rate_limited'})
                raw = secrets.token_urlsafe(32)
                db.execute('INSERT INTO metric_installs VALUES(?,?,?)', (digest(raw), now, now))
                return reply(201, {'token': raw})
            if path == '/v1/app/metrics' and method in ('POST', 'DELETE'):
                identity = digest(token(env))
                if not db.execute('SELECT 1 FROM metric_installs WHERE token_hash=?', (identity,)).fetchone():
                    return reply(401, {'error': 'unauthorized'})
                if method == 'DELETE':
                    db.execute('DELETE FROM metric_events WHERE install=?', (identity,))
                    db.execute('DELETE FROM metric_installs WHERE token_hash=?', (identity,))
                    return reply(200, {'deleted': True})
                data = read_body(env)
                if set(data) != {'eventId', 'event', 'version', 'platform'} or not all(isinstance(value, str) for value in data.values()) or data['event'] not in EVENTS:
                    raise RequestError('invalid_event')
                if not isinstance(data['eventId'], str) or not re.fullmatch(r'[a-f0-9]{32}', data['eventId']):
                    raise RequestError('invalid_event_id')
                if not isinstance(data['version'], str) or not re.fullmatch(r'\d{1,3}\.\d{1,3}\.\d{1,3}\+\d{1,8}', data['version']):
                    raise RequestError('invalid_version')
                if data['platform'] not in ('android', 'ios', 'other'):
                    raise RequestError('invalid_platform')
                if not limited(db, 'events:' + identity, 200, now):
                    return reply(429, {'error': 'rate_limited'})
                db.execute('INSERT OR IGNORE INTO metric_events VALUES(?,?,?,?,?,?)',
                           (data['eventId'], identity, day, data['event'], data['version'], data['platform']))
                db.execute('UPDATE metric_installs SET last_seen=? WHERE token_hash=?', (now, identity))
                return reply(200, {'accepted': True})
            if path == '/v1/app/owner/activate' and method == 'POST':
                if not limited(db, 'activate:' + ip_key, 20, now, 3600):
                    return reply(429, {'error': 'rate_limited'})
                data = read_body(env)
                if set(data) != {'key', 'installation'} or not isinstance(data['key'], str) or not isinstance(data['installation'], str) or not re.fullmatch(r'[a-f0-9]{32}', data['installation']):
                    raise RequestError('invalid_activation')
                license_row = db.execute('SELECT id,bound_install FROM licenses WHERE key_hash=? AND revoked=0', (digest(data['key']),)).fetchone()
                if not license_row or license_row[1] not in (None, data['installation']):
                    return reply(403, {'error': 'activation_denied'})
                # Immediate transaction serialization prevents two concurrent bindings.
                changed = db.execute('UPDATE licenses SET bound_install=? WHERE id=? AND (bound_install IS NULL OR bound_install=?) AND revoked=0', (data['installation'], license_row[0], data['installation'])).rowcount
                if not changed:
                    return reply(403, {'error': 'activation_denied'})
                db.execute('DELETE FROM owner_sessions WHERE license_id=?', (license_row[0],))
                raw = secrets.token_urlsafe(32)
                expiry = now + 30 * 86400
                db.execute('INSERT INTO owner_sessions VALUES(?,?,?,?)', (digest(raw), license_row[0], data['installation'], expiry))
                return reply(200, {'token': raw, 'tier': 'owner', 'ads': False, 'expiresAt': expiry})
            if path == '/v1/app/entitlement' and method == 'GET':
                row = db.execute('SELECT s.expires FROM owner_sessions s JOIN licenses l ON l.id=s.license_id WHERE s.token_hash=? AND s.expires>? AND l.revoked=0', (digest(token(env)), now)).fetchone()
                if not row:
                    return reply(401, {'error': 'owner_session_invalid'})
                expiry = now + 30 * 86400
                db.execute('UPDATE owner_sessions SET expires=? WHERE token_hash=?', (expiry, digest(token(env))))
                return reply(200, {'tier': 'owner', 'ads': False, 'expiresAt': expiry})
            return reply(405 if path in ('/v1/app/metrics/register', '/v1/app/metrics', '/v1/app/owner/activate', '/v1/app/entitlement') else 404, {'error': 'method_or_route_not_allowed'})
    except RequestError as error:
        return reply(error.status, {'error': error.code})
    except (OSError, sqlite3.Error):
        return reply(503, {'error': 'app_services_unavailable'})


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Provision/revoke owner licenses on the server; never put keys in APKs.')
    parser.add_argument('action', choices=('create-owner', 'revoke-owner', 'purge'))
    parser.add_argument('--id', type=int)
    args = parser.parse_args()
    configured_path = os.environ.get('LUCKYSCAN_APP_DATABASE')
    if not configured_path:
        parser.error('Set LUCKYSCAN_APP_DATABASE outside the public web directory')
    with database(configured_path) as connection:
        if args.action == 'create-owner':
            key = secrets.token_urlsafe(32)
            cursor = connection.execute('INSERT INTO licenses(key_hash,created_at) VALUES(?,?)', (digest(key), int(time.time())))
            print(f'License ID: {cursor.lastrowid}\nActivation key (shown once): {key}')
        elif args.action == 'revoke-owner':
            if not args.id:
                parser.error('--id is required')
            connection.execute('UPDATE licenses SET revoked=1 WHERE id=?', (args.id,))
            connection.execute('DELETE FROM owner_sessions WHERE license_id=?', (args.id,))
        else:
            clean(connection, int(time.time()))
