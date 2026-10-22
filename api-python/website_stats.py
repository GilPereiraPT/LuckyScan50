"""Aggregate page views for the public product page; no visitor identifiers."""
from contextlib import closing
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3

ORIGIN = 'https://gilpereirapt.github.io'
ROUTE = '/v1/website/visits'


def database_path():
    configured = os.environ.get('LUCKYSCAN_WEBSITE_STATS_DATABASE')
    if configured:
        path = Path(configured)
    else:
        results = os.environ.get('LUCKYSCAN_DATABASE')
        parent = Path(results).parent if results else Path(__file__).resolve().parent / 'data'
        path = parent / 'website-stats.sqlite3'
    if not path.is_absolute():
        raise ValueError('Expected an absolute website stats database path')
    results = os.environ.get('LUCKYSCAN_DATABASE')
    if results and path.resolve() == Path(results).resolve():
        raise ValueError('Website counter must use a separate database')
    return path


def visit_total(path, increment=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(descriptor)
    except FileExistsError:
        pass
    with closing(sqlite3.connect(path, timeout=5)) as db, db:
        db.execute('CREATE TABLE IF NOT EXISTS website_visits '
                   '(id INTEGER PRIMARY KEY CHECK(id=1), total INTEGER NOT NULL, started_at TEXT NOT NULL)')
        db.execute('INSERT OR IGNORE INTO website_visits VALUES(1,0,?)',
                   (datetime.now(timezone.utc).isoformat(),))
        if increment:
            db.execute('UPDATE website_visits SET total=total+1 WHERE id=1')
        total, started_at = db.execute(
            'SELECT total,started_at FROM website_visits WHERE id=1').fetchone()
    return {'total': total, 'startedAt': started_at, 'metric': 'pageviews'}


def handle_request(environ, start_response):
    if environ.get('PATH_INFO') != ROUTE:
        return None
    origin = environ.get('HTTP_ORIGIN')
    method = environ.get('REQUEST_METHOD', 'GET')

    def reply(status, data):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        headers = [('Content-Type', 'application/json; charset=utf-8'),
                   ('Content-Length', str(len(body))), ('Cache-Control', 'no-store'),
                   ('Vary', 'Origin'), ('X-Content-Type-Options', 'nosniff')]
        if origin == ORIGIN:
            headers.extend([('Access-Control-Allow-Origin', ORIGIN),
                            ('Access-Control-Allow-Methods', 'GET, POST, OPTIONS'),
                            ('Access-Control-Allow-Headers', 'Content-Type')])
        if status == 405:
            headers.append(('Allow', 'GET, POST, OPTIONS'))
        reasons = {200: 'OK', 400: 'Bad Request', 403: 'Forbidden',
                   405: 'Method Not Allowed', 413: 'Payload Too Large',
                   503: 'Service Unavailable'}
        start_response(f'{status} {reasons[status]}', headers)
        return [body]

    if method not in ('GET', 'POST', 'OPTIONS'):
        return reply(405, {'error': 'method_not_allowed'})
    if method in ('POST', 'OPTIONS') and origin != ORIGIN:
        return reply(403, {'error': 'origin_not_allowed'})
    if method == 'OPTIONS':
        return reply(200, {'ok': True})
    if method == 'POST':
        if environ.get('CONTENT_TYPE', '').split(';')[0].strip().lower() != 'application/json':
            return reply(400, {'error': 'expected_json'})
        try:
            size = int(environ.get('CONTENT_LENGTH', ''))
            if size > 128:
                return reply(413, {'error': 'payload_too_large'})
            if size <= 0:
                raise ValueError()
            raw = environ['wsgi.input'].read(size)
            if len(raw) != size or json.loads(raw) != {'event': 'pageview'}:
                raise ValueError()
        except (ValueError, KeyError, UnicodeError, TypeError):
            return reply(400, {'error': 'invalid_event'})
    try:
        return reply(200, visit_total(database_path(), increment=method == 'POST'))
    except (ValueError, OSError, sqlite3.Error):
        return reply(503, {'error': 'counter_unavailable'})
