"""Offline API input boundaries; no network or production database access."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from wsgiref.util import setup_testing_defaults

import passenger_wsgi as api
from domain import validate_result
from store import Store


class SyncCursorBoundaryTests(unittest.TestCase):
    def test_sync_rejects_cursor_outside_sqlite_integer_range(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Store(Path(folder) / 'isolated.sqlite')
            store.migrate()
            for after in ('9223372036854775808', '9' * 100, '-1'):
                with self.subTest(after=after):
                    environ = {}
                    setup_testing_defaults(environ)
                    environ.update(PATH_INFO='/v1/sync', QUERY_STRING='after=' + after)
                    status = []
                    with patch.object(api, 'DATABASE_FILE', str(store.path)):
                        body = b''.join(api.application(environ, lambda code, headers: status.append(code)))
                    self.assertEqual(status, ['400 Bad Request'])
                    self.assertEqual(json.loads(body), {'error': 'invalid_pagination'})

    def test_sync_accepts_largest_sqlite_cursor_without_writes(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Store(Path(folder) / 'isolated.sqlite')
            store.migrate()
            before = store.path.read_bytes()
            environ = {}
            setup_testing_defaults(environ)
            environ.update(PATH_INFO='/v1/sync', QUERY_STRING='after=9223372036854775807')
            status = []
            with patch.object(api, 'DATABASE_FILE', str(store.path)):
                body = json.loads(b''.join(api.application(environ, lambda code, headers: status.append(code))))
            self.assertEqual(status, ['200 OK'])
            self.assertEqual(body['data'], [])
            self.assertEqual(body['nextCursor'], 9223372036854775807)
            self.assertFalse(body['hasMore'])
            self.assertEqual(store.path.read_bytes(), before)


class ResultIdentityBoundaryTests(unittest.TestCase):
    @staticmethod
    def result(identity):
        return {'game': 'milhao', 'drawId': identity, 'date': '2026-10-16',
                'status': 'numbers_confirmed', 'winningCode': 'PTM 09893',
                'sourceUrl': 'https://example.org/isolated-test-fixture',
                'retrievedAt': '2026-10-17T03:00:00Z', 'amountCents': None}

    def test_zero_draw_rejected_but_first_draw_remains_valid(self):
        validate_result(self.result('001/2026'))
        for identity in ('000/2026', 83, None):
            with self.subTest(identity=identity), self.assertRaises(ValueError):
                validate_result(self.result(identity))

    def test_invalid_identity_cannot_write_or_migrate_existing_database(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Store(Path(folder) / 'isolated.sqlite')
            store.import_rows([self.result('001/2026')])
            before = store.path.read_bytes()
            with self.assertRaises(ValueError):
                store.import_rows([self.result('000/2026')])
            self.assertEqual(store.path.read_bytes(), before)
            self.assertEqual(len(store.changes()), 1)


if __name__ == '__main__':
    unittest.main()
