import io
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from urllib.parse import urlencode

import app_services as services
import passenger_wsgi as api


class AppServicesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = str(Path(self.temp.name) / 'private.db')
        self.admin = 'a' * 43
        env = patch.dict(os.environ, {'LUCKYSCAN_APP_DATABASE': self.path,
            'LUCKYSCAN_APP_SECRET': 's' * 43, 'LUCKYSCAN_ADMIN_TOKEN': self.admin})
        env.start()
        self.addCleanup(env.stop)

    def request(self, path, method='GET', body=None, token=None, cookie=None, raw=None):
        data = json.dumps(body).encode() if body is not None else b''
        if raw is not None:
            data = raw
        env = {'PATH_INFO': path, 'REQUEST_METHOD': method,
               'CONTENT_TYPE': 'application/json' if raw is None else 'application/x-www-form-urlencoded',
               'CONTENT_LENGTH': str(len(data)), 'wsgi.input': io.BytesIO(data),
               'REMOTE_ADDR': '127.0.0.1'}
        if token:
            env['HTTP_AUTHORIZATION'] = 'Bearer ' + token
        if cookie:
            env['HTTP_COOKIE'] = cookie
        captured = {}
        def start(status, headers):
            captured.update(code=int(status[:3]), headers=dict(headers))
        value = b''.join(api.application(env, start))
        content = value.decode() if captured['headers']['Content-Type'].startswith('text/html') else json.loads(value)
        return captured['code'], content, captured['headers']

    def register(self):
        status, data, _ = self.request('/v1/app/metrics/register', 'POST', {'consentVersion': 1})
        self.assertEqual(status, 201)
        return data['token']

    def event(self, token, **changes):
        return self.request('/v1/app/metrics', 'POST', {
            'eventId': '1' * 32, 'event': 'app_open', 'version': '0.2.14+16',
            'platform': 'android', **changes}, token)

    def owner_key(self):
        key = 'k' * 43
        with services.database(self.path) as db:
            db.execute('INSERT INTO licenses(key_hash,created_at) VALUES(?,?)', (services.digest(key), int(time.time())))
        return key

    def test_disabled_without_configuration(self):
        with patch.dict(os.environ, {'LUCKYSCAN_APP_SECRET': ''}):
            self.assertEqual(self.request('/v1/app/metrics/register', 'POST', {})[0], 503)

    def test_no_telemetry_without_consent_or_registration(self):
        self.assertEqual(self.request('/v1/app/metrics/register', 'POST', {'consentVersion': 0})[0], 400)
        self.assertEqual(self.event('x' * 43)[0], 401)
        self.assertEqual(self.request('/v1/app/metrics/register', 'GET')[0], 405)

    def test_event_idempotency_counts_versions_and_private_panel(self):
        token = self.register()
        for _ in range(2):
            self.assertEqual(self.event(token)[0], 200)
        self.assertEqual(self.request('/admin/app/statistics')[0], 401)
        status, data, headers = self.request('/admin/app/statistics', token=self.admin)
        self.assertEqual(status, 200)
        self.assertEqual(data['active7Days'], 1)
        self.assertEqual(data['daily'][0]['count'], 1)
        self.assertEqual(headers['Cache-Control'], 'no-store')
        self.assertNotIn('install', data['daily'][0])
        self.assertEqual(self.request('/admin/app', token=self.admin)[0], 200)

    def test_forbids_receipt_payloads_arbitrary_fields_and_malformed_events(self):
        token = self.register()
        for changes in ({'email': 'private@example.com'}, {'numbers': [1, 2, 3]},
                        {'event': 'purchase'}, {'event': {}}, {'event': []},
                        {'version': '<script>'}, {'platform': 'browser'}, {'eventId': '123'}):
            with self.subTest(changes=changes):
                self.assertEqual(self.event(token, **changes)[0], 400)
        with services.database(self.path) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM metric_events').fetchone()[0], 0)

    def test_deletion_erases_only_own_events_and_revokes_metrics_token(self):
        first, second = self.register(), self.register()
        self.event(first)
        self.event(second, eventId='2' * 32)
        self.assertEqual(self.request('/v1/app/metrics', 'DELETE', token=first)[0], 200)
        self.assertEqual(self.event(first)[0], 401)
        data = self.request('/admin/app/statistics', token=self.admin)[1]
        self.assertEqual(data['installations'], 1)
        self.assertEqual(sum(row['count'] for row in data['daily']), 1)

    def test_owner_binding_renewal_and_revocation(self):
        key = self.owner_key()
        body = {'key': key, 'installation': '1' * 32}
        status, grant, _ = self.request('/v1/app/owner/activate', 'POST', body)
        self.assertEqual(status, 200)
        self.assertFalse(grant['ads'])
        self.assertEqual(self.request('/v1/app/owner/activate', 'POST', {**body, 'installation': '2' * 32})[0], 403)
        self.assertEqual(self.request('/v1/app/entitlement', token=grant['token'])[1]['tier'], 'owner')
        # A new activation rotates the session; no permanent APK-local owner flag.
        new_grant = self.request('/v1/app/owner/activate', 'POST', body)[1]
        self.assertEqual(self.request('/v1/app/entitlement', token=grant['token'])[0], 401)
        with services.database(self.path) as db:
            db.execute('UPDATE licenses SET revoked=1')
        self.assertEqual(self.request('/v1/app/entitlement', token=new_grant['token'])[0], 401)
        self.assertEqual(self.request('/v1/app/owner/activate', 'POST', body)[0], 403)

    def test_hashes_only_stored_for_owner_and_metrics(self):
        key = self.owner_key()
        grant = self.request('/v1/app/owner/activate', 'POST', {'key': key, 'installation': '1' * 32})[1]
        metrics = self.register()
        with services.database(self.path) as db:
            dump = '\n'.join(db.iterdump())
        for raw_secret in (key, grant['token'], metrics, self.admin, '127.0.0.1'):
            self.assertNotIn(raw_secret, dump)
        self.assertEqual(Path(self.path).stat().st_mode & 0o777, 0o600)

    def test_expired_owner_sessions_are_denied(self):
        key = self.owner_key()
        grant = self.request('/v1/app/owner/activate', 'POST', {'key': key, 'installation': '1' * 32})[1]
        with services.database(self.path) as db:
            db.execute('UPDATE owner_sessions SET expires=0')
        self.assertEqual(self.request('/v1/app/entitlement', token=grant['token'])[0], 401)

    def test_retention_and_rate_limits(self):
        token = self.register()
        self.event(token)
        with services.database(self.path) as db:
            db.execute("UPDATE metric_events SET day='2000-01-01'")
            db.execute('UPDATE metric_installs SET last_seen=0')
        data = self.request('/admin/app/statistics', token=self.admin)[1]
        self.assertEqual(data['daily'], [])
        self.assertEqual(data['installations'], 0)
        for _ in range(19):
            self.register()
        self.assertEqual(self.request('/v1/app/metrics/register', 'POST', {'consentVersion': 1})[0], 429)

    def test_admin_cookie_secure_and_expiring(self):
        login = self.request('/admin/app/login', 'POST', raw=urlencode({'token': self.admin}).encode())
        self.assertEqual(login[0], 200)
        cookie = login[2]['Set-Cookie']
        for protection in ('HttpOnly', 'Secure', 'SameSite=Strict'):
            self.assertIn(protection, cookie)
        self.assertEqual(self.request('/admin/app/statistics', cookie=cookie.split(';')[0])[0], 200)
        expired = services.admin_cookie('s' * 43 + self.admin, now=int(time.time()) - 7200)
        self.assertEqual(self.request('/admin/app/statistics', cookie='ls_admin=' + expired)[0], 401)
        self.assertEqual(self.request('/admin/app/statistics', cookie='ls_admin=forged')[0], 401)

    def test_admin_login_is_limited(self):
        for _ in range(10):
            self.assertEqual(self.request('/admin/app/login', 'POST', raw=b'token=bad')[0], 401)
        self.assertEqual(self.request('/admin/app/login', 'POST', raw=b'token=bad')[0], 429)

    def test_body_limits_bad_json_and_invalid_activation(self):
        self.assertEqual(self.request('/v1/app/owner/activate', 'POST', {'key': [], 'installation': '1' * 32})[0], 400)
        self.assertEqual(self.request('/v1/app/owner/activate', 'POST', {'key': 'bad', 'installation': '1' * 32})[0], 403)
        self.assertEqual(self.request('/v1/app/metrics/register', 'POST', {'x': 'y' * 3000})[0], 413)


    def test_admin_can_issue_and_revoke_owner_keys_without_exposing_stored_hashes(self):
        self.assertEqual(self.request('/admin/app/licenses', 'POST', {'action': 'create'})[0], 401)
        created = self.request('/admin/app/licenses', 'POST', {'action': 'create'}, token=self.admin)
        self.assertEqual(created[0], 201)
        license_id = created[1]['id']
        key = created[1]['activationKey']
        listing = self.request('/admin/app/licenses', token=self.admin)
        self.assertEqual(listing[1]['licenses'][0]['id'], license_id)
        self.assertNotIn(key, json.dumps(listing[1]))
        self.assertNotIn('key_hash', json.dumps(listing[1]))
        self.assertEqual(self.request('/v1/app/owner/activate', 'POST', {'key': key, 'installation': '3' * 32})[0], 200)
        self.assertEqual(self.request('/admin/app/licenses', 'POST', {'action': 'revoke', 'id': license_id}, token=self.admin)[0], 200)
        self.assertEqual(self.request('/v1/app/owner/activate', 'POST', {'key': key, 'installation': '3' * 32})[0], 403)
        self.assertEqual(self.request('/admin/app/licenses', 'POST', {'action': 'revoke', 'id': True}, token=self.admin)[0], 400)

    def test_browser_cookie_cannot_issue_owner_license(self):
        login = self.request('/admin/app/login', 'POST', raw=urlencode({'token': self.admin}).encode())
        cookie = login[2]['Set-Cookie'].split(';')[0]
        self.assertEqual(self.request('/admin/app/licenses', 'POST', {'action': 'create'}, cookie=cookie)[0], 401)
