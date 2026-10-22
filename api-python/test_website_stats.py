"""Counter tests: temporary SQLite, origins, malformed input and persistence."""
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import website_stats as stats


class CounterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'stats.sqlite3'
        env = patch.dict(os.environ, {'LUCKYSCAN_WEBSITE_STATS_DATABASE': str(self.path)})
        env.start()
        self.addCleanup(env.stop)

    def request(self, method='GET', origin=stats.ORIGIN, raw=b'{"event":"pageview"}', **extra):
        environ = {'PATH_INFO': stats.ROUTE, 'REQUEST_METHOD': method, 'HTTP_ORIGIN': origin,
                   'CONTENT_TYPE': 'application/json', 'CONTENT_LENGTH': str(len(raw)),
                   'wsgi.input': io.BytesIO(raw), **extra}
        response = {}
        def start(status, headers):
            response.update(status=int(status.split()[0]), headers=dict(headers))
        body = stats.handle_request(environ, start)
        return response, json.loads(b''.join(body))

    def test_read_does_not_increment_and_post_persists(self):
        self.assertEqual(self.request()[1]['total'], 0)
        one, body = self.request('POST')
        self.assertEqual(body['total'], 1)
        self.assertEqual(body['metric'], 'pageviews')
        self.assertEqual(self.request()[1]['total'], 1)
        self.assertEqual(self.request('POST')[1]['total'], 2)
        self.assertEqual(one['headers']['Access-Control-Allow-Origin'], stats.ORIGIN)
        self.assertEqual(one['headers']['Cache-Control'], 'no-store')
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_preflight_does_not_create_a_counter(self):
        response, _ = self.request('OPTIONS')
        self.assertEqual(response['status'], 200)
        self.assertIn('POST', response['headers']['Access-Control-Allow-Methods'])
        self.assertFalse(self.path.exists())

    def test_other_origins_cannot_increment(self):
        for origin in ('https://example.test', '', 'null'):
            with self.subTest(origin=origin):
                response, _ = self.request('POST', origin=origin)
                self.assertEqual(response['status'], 403)
                self.assertNotIn('Access-Control-Allow-Origin', response['headers'])
        self.assertFalse(self.path.exists())

    def test_invalid_input_does_not_increment(self):
        for body in (b'{}', b'{"event":"other"}', b'not json', b'[]', b''):
            with self.subTest(body=body):
                self.assertEqual(self.request('POST', raw=body)[0]['status'], 400)
        self.assertEqual(self.request('POST', raw=b'x'*129)[0]['status'], 413)
        self.assertEqual(self.request('DELETE')[0]['status'], 405)
        self.assertFalse(self.path.exists())

    def test_separate_database_and_storage_failure(self):
        with patch.dict(os.environ, {'LUCKYSCAN_DATABASE': str(self.path)}):
            self.assertEqual(self.request()[0]['status'], 503)
        with patch.object(stats, 'visit_total', side_effect=OSError()):
            self.assertEqual(self.request('POST')[0]['status'], 503)
        self.assertIsNone(stats.handle_request({'PATH_INFO': '/v1/draws'}, lambda *_: None))

    def test_concurrent_requests_do_not_lose_counts(self):
        stats.visit_total(self.path)
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda _: stats.visit_total(self.path, increment=True), range(24)))
        self.assertEqual(stats.visit_total(self.path)['total'], 24)
