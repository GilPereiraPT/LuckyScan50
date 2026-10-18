"""Entirely synthetic structural fixtures; NOT the official 17/10/2026 snapshot."""
from contextlib import closing, redirect_stdout, redirect_stderr
from datetime import datetime, timezone
import fcntl
from html import escape
import io
import json
from pathlib import Path
import tempfile
import sqlite3
from concurrent.futures import ThreadPoolExecutor
import unittest
from unittest.mock import patch, MagicMock
from urllib.error import URLError
from wsgiref.util import setup_testing_defaults

import official_statistics as stats
import passenger_wsgi as api
from collect_results import main, run_official_statistics
from store import Store
from test_app import result

NOW = datetime(2026, 10, 18, 10, 0, tzinfo=timezone.utc)


def synthetic_snapshot():
    def rows(maximum):
        return [{'value': value, 'count': 10, 'percentage': '10.00',
                 'lastDrawId': '083/2026', 'lastDate': '2026-10-16',
                 'drawsSinceLast': 0, 'eligibleDraws': 100}
                for value in range(1, maximum + 1)]
    snapshot = {'schemaVersion': 1, 'game': 'euromilhoes', 'sourceUrl': stats.URL,
                'updatedAt': '2026-10-17T03:00:00+01:00', 'coverageStart': '2004-02-13',
                'numbers': rows(50), 'stars': rows(12)}
    # The three late-added stars deliberately have different denominators.
    for value, denominator in ((10, 50), (11, 40), (12, 25)):
        snapshot['stars'][value - 1].update(eligibleDraws=denominator,
                                           percentage=f'{10 * 100 / denominator:.2f}')
    return snapshot


def encoded(snapshot=None):
    return json.dumps(snapshot or synthetic_snapshot(), ensure_ascii=False).encode()


def synthetic_html(snapshot=None, encoding='utf-8'):
    snapshot = snapshot or synthetic_snapshot()
    fragments = [f'<html><head><meta charset="{encoding}"></head><body>',
                 '<!-- SYNTHETIC STRUCTURAL FIXTURE, NOT AN OFFICIAL CAPTURE -->',
                 '<p>Desde 13/02/2004</p>', f'<time datetime="{snapshot["updatedAt"]}">Atualização</time>']
    for field, caption in (('numbers', 'Números'), ('stars', 'Estrelas')):
        fragments.append(f'<table><caption>{caption}</caption><tr>')
        fragments.extend(f'<th>{header}</th>' for header in stats.HEADERS + (stats.OPTIONAL_HEADER,))
        fragments.append('</tr>')
        for row in snapshot[field]:
            cells = [str(row['value']), str(row['count']), row['percentage'].replace('.', ',') + ' %',
                     row['lastDrawId'] or '—', datetime.fromisoformat(row['lastDate']).strftime('%d/%m/%Y') if row['lastDate'] else '—',
                     str(row['drawsSinceLast']) if row['drawsSinceLast'] is not None else '—',
                     str(row['eligibleDraws'])]
            fragments.append('<tr>' + ''.join(f'<td>{escape(cell)}</td>' for cell in cells) + '</tr>')
        fragments.append('</table>')
    fragments.append('</body></html>')
    return ''.join(fragments).encode(encoding)


class StatisticsValidationTests(unittest.TestCase):
    def test_full_50_and_12_exact_decimals_and_distinct_star_denominators(self):
        parsed = stats.parse_json(encoded(), now=NOW)
        self.assertEqual((len(parsed['numbers']), len(parsed['stars'])), (50, 12))
        self.assertEqual(parsed['updatedAt'], '2026-10-17T02:00:00+00:00')
        self.assertEqual([row['eligibleDraws'] for row in parsed['stars'][9:]], [50, 40, 25])
        self.assertEqual([row['percentage'] for row in parsed['stars'][9:]], ['20.00', '25.00', '40.00'])

    def test_missing_source_denominators_are_never_inferred(self):
        snapshot = synthetic_snapshot()
        for row in snapshot['stars']:
            row['eligibleDraws'] = None
        parsed = stats.parse_json(encoded(snapshot), now=NOW)
        self.assertTrue(all(row['eligibleDraws'] is None for row in parsed['stars']))
        self.assertEqual(parsed['stars'][11]['percentage'], '40.00')

    def test_missing_duplicate_out_of_range_and_bad_counts_are_rejected(self):
        mutations = [lambda s: s['numbers'].pop(), lambda s: s['stars'].pop(),
                     lambda s: s['numbers'][1].update(value=1), lambda s: s['stars'][0].update(value=13),
                     lambda s: s['numbers'][0].update(count=True), lambda s: s['numbers'][0].update(count=-1),
                     lambda s: s['numbers'][0].update(drawsSinceLast=-1),
                     lambda s: s['numbers'][0].update(eligibleDraws=0),
                     lambda s: s['numbers'][0].update(eligibleDraws=50, percentage='20.00'),
                     lambda s: s['numbers'][0].update(count=101)]
        for mutation in mutations:
            snapshot = synthetic_snapshot()
            mutation(snapshot)
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                stats.parse_json(encoded(snapshot), now=NOW)

    def test_bad_percentages_and_denominator_disagreement_are_rejected(self):
        for value in ('-1', '101', 'NaN', 'Infinity', '10,5', '0.25%', 25.0, True, '1e2', '9.99'):
            snapshot = synthetic_snapshot()
            snapshot['numbers'][0]['percentage'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                stats.parse_json(encoded(snapshot), now=NOW)

    def test_unknown_structure_and_duplicate_json_keys_fail_closed(self):
        snapshot = synthetic_snapshot()
        snapshot['unreviewedColumn'] = 1
        with self.assertRaises(ValueError):
            stats.parse_json(encoded(snapshot), now=NOW)
        with self.assertRaises(ValueError):
            stats.parse_json(encoded().replace(b'"schemaVersion": 1', b'"schemaVersion": 1, "schemaVersion": 1'), now=NOW)
        snapshot = synthetic_snapshot()
        snapshot['numbers'][0]['extra'] = 'unexpected'
        with self.assertRaises(ValueError):
            stats.parse_json(encoded(snapshot), now=NOW)

    def test_metadata_and_last_draw_are_required_and_not_guessed(self):
        mutations = [{'coverageStart': '2016-09-27'}, {'sourceUrl': 'http://www.jogossantacasa.pt/web/SCEstatisticas/'},
                     {'updatedAt': '2026-10-17T03:00:00'}, {'updatedAt': '2027-10-17T03:00:00Z'},
                     {'game': 'milhao'}]
        for change in mutations:
            with self.subTest(change=change), self.assertRaises(ValueError):
                stats.parse_json(encoded({**synthetic_snapshot(), **change}), now=NOW)
        for change in ({'lastDrawId': '000/2026'}, {'lastDrawId': '083/2025'},
                       {'lastDate': '2026-10-18'}, {'lastDate': '2026-02-30'},
                       {'lastDate': None}, {'lastDrawId': None}, {'drawsSinceLast': None}):
            snapshot = synthetic_snapshot()
            snapshot['numbers'][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                stats.parse_json(encoded(snapshot), now=NOW)

    def test_zero_occurrence_requires_no_fabricated_last_draw(self):
        snapshot = synthetic_snapshot()
        snapshot['numbers'][0].update(count=0, percentage='0.00', lastDrawId=None, lastDate=None, drawsSinceLast=None)
        for row in snapshot['numbers']:
            row['eligibleDraws'] = None
        self.assertIsNone(stats.parse_json(encoded(snapshot), now=NOW)['numbers'][0]['lastDate'])
        snapshot['numbers'][0]['lastDrawId'] = '083/2026'
        with self.assertRaises(ValueError):
            stats.parse_json(encoded(snapshot), now=NOW)

    def test_sum_of_number_counts_is_checked_when_total_is_explicit(self):
        snapshot = synthetic_snapshot()
        snapshot['numbers'][0].update(count=11, percentage='11.00')
        with self.assertRaises(ValueError):
            stats.parse_json(encoded(snapshot), now=NOW)

    def test_late_added_stars_cannot_claim_a_draw_before_availability(self):
        for star, day, identity in ((10, '2011-05-06', '036/2011'), (11, '2004-02-13', '001/2004'),
                                    (12, '2016-09-23', '076/2016')):
            snapshot = synthetic_snapshot()
            snapshot['stars'][star - 1].update(lastDate=day, lastDrawId=identity)
            with self.subTest(star=star), self.assertRaises(ValueError):
                stats.parse_json(encoded(snapshot), now=NOW)

    def test_html_tables_entity_and_portuguese_decimal_support(self):
        parsed = stats.parse_html(synthetic_html().replace('Números'.encode(), b'N&#250;meros'), now=NOW)
        self.assertEqual(parsed, stats.parse_json(encoded(), now=NOW))
        self.assertEqual(stats.parse_html(synthetic_html(encoding='iso-8859-1'), now=NOW), parsed)

    def test_fixed_https_timeout_redirect_content_type_and_size_boundary(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status, response.url = 200, stats.URL
        response.headers = {'Content-Type': 'text/html; charset=utf-8'}
        response.read.return_value = synthetic_html()
        opener = MagicMock()
        opener.open.return_value = response
        with patch('official_statistics.build_opener', return_value=opener):
            self.assertEqual(stats.fetch(), synthetic_html())
            request = opener.open.call_args.args[0]
            self.assertEqual(request.full_url, stats.URL)
            self.assertEqual(opener.open.call_args.kwargs['timeout'], 20)
            response.read.assert_called_with(stats.MAX_BYTES + 1)
            for change in ('url', 'status', 'headers', 'payload'):
                response.url, response.status = stats.URL, 200
                response.headers, response.read.return_value = {'Content-Type': 'text/html'}, b'<html/>'
                if change == 'url':
                    response.url = 'http://www.jogossantacasa.pt/web/SCEstatisticas/'
                elif change == 'status':
                    response.status = 302
                elif change == 'headers':
                    response.headers = {'Content-Type': 'application/json'}
                else:
                    response.read.return_value = b'x' * (stats.MAX_BYTES + 1)
                with self.subTest(change=change), self.assertRaises(ValueError):
                    stats.fetch()
        with self.assertRaises(ValueError):
            stats.NoRedirect().redirect_request(None, None, 302, 'redirect', {}, 'http://example.org')

    def test_changed_html_structure_or_metadata_is_rejected(self):
        payload = synthetic_html()
        variants = [payload.replace(b'<th>Valor</th>', b'<th>Outro</th>', 1),
                    payload.replace(b'<table>', b'<table><tr><td>99</td></tr>', 1),
                    payload.replace(b'Desde 13/02/2004', b'Desde 01/01/2026'),
                    payload.replace(b'+01:00', b''), payload.replace(b'</body>', b'<table></table></body>')]
        for variant in variants:
            with self.subTest(variant=variant[:50]), self.assertRaises(ValueError):
                stats.parse_html(variant, now=NOW)
        with self.assertRaises(ValueError):
            stats.parse_html(b'<html>12 34 56</html>', now=NOW)
        with self.assertRaises(ValueError):
            stats.parse_json(b'x' * (stats.MAX_BYTES + 1), now=NOW)


class StatisticsStorageTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.store = Store(self.root / 'test.sqlite3')
        self.store.migrate()

    def test_empty_overview_is_read_only_and_has_no_invented_numbers(self):
        before = self.store.path.read_bytes()
        self.assertEqual(stats.overview(self.store)['data'], None)
        self.assertFalse(stats.overview(self.store)['available'])
        self.assertEqual(self.store.path.read_bytes(), before)

    def test_snapshots_idempotent_and_separate_from_draws_and_revisions(self):
        self.store.import_rows([result()])
        before = self.store.all()
        one = self.store.import_official_statistics(encoded(), format='json', now=NOW)
        two = self.store.import_official_statistics(encoded(), format='json', now=NOW)
        self.assertEqual(one, {'changed': 1, 'unchanged': 0, 'conflicts': 0})
        self.assertEqual(two, {'changed': 0, 'unchanged': 1, 'conflicts': 0})
        self.assertEqual(self.store.all(), before)
        self.assertEqual(len(self.store.changes()), 1)
        body = stats.overview(self.store)
        self.assertTrue(body['available'])
        self.assertFalse(body['prediction'])
        self.assertFalse(body['data']['snapshotReferenceVerified'])
        self.assertEqual(body['data']['validation'], 'structure_validated')
        self.assertRegex(body['data']['sourceSha256'], r'^[a-f0-9]{64}$')

    def test_older_snapshot_never_replaces_latest_and_history_retained(self):
        self.store.import_official_statistics(encoded(), format='json', now=NOW)
        old = synthetic_snapshot()
        old['updatedAt'] = '2026-10-16T23:00:00Z'
        self.store.import_official_statistics(encoded(old), format='json', now=NOW)
        self.assertEqual(stats.overview(self.store)['data']['updatedAt'], '2026-10-17T02:00:00+00:00')
        with closing(self.store.connect(readonly=True)) as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM official_statistics_snapshots').fetchone()[0], 2)

    def test_same_update_divergence_preserves_accepted_cache_and_is_idempotent(self):
        self.store.import_official_statistics(encoded(), format='json', now=NOW)
        divergent = synthetic_snapshot()
        divergent['numbers'][0].update(count=11, percentage='11.00')
        divergent['numbers'][1].update(count=9, percentage='9.00')
        one = self.store.import_official_statistics(encoded(divergent), format='json', now=NOW)
        two = self.store.import_official_statistics(encoded(divergent), format='json', now=NOW)
        self.assertEqual(one['conflicts'], 1)
        self.assertEqual(two['unchanged'], 1)
        self.assertEqual(stats.overview(self.store)['data']['numbers'][0]['count'], 10)
        self.assertEqual(stats.overview(self.store)['conflicts'], 1)

    def test_invalid_import_writes_nothing_and_does_not_erase_cached_snapshot(self):
        self.store.import_official_statistics(encoded(), format='json', now=NOW)
        before = stats.overview(self.store)
        with self.assertRaises(ValueError):
            self.store.import_official_statistics(b'{}', format='json', now=NOW)
        self.assertEqual(stats.overview(self.store), before)

    def test_snapshot_and_import_audit_commit_atomically(self):
        stats.initialize(self.store)
        with closing(self.store.connect()) as connection, connection:
            connection.execute("CREATE TRIGGER reject_audit BEFORE INSERT ON official_statistics_imports BEGIN SELECT RAISE(ABORT,'synthetic audit failure'); END")
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.import_official_statistics(encoded(), format='json', now=NOW)
        with closing(self.store.connect(readonly=True)) as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM official_statistics_snapshots').fetchone()[0], 0)
        self.assertEqual(self.store.changes(), [])

    def test_parallel_snapshot_replays_create_one_snapshot(self):
        def replay(_):
            return self.store.import_official_statistics(encoded(), format='json', now=NOW)
        with ThreadPoolExecutor(max_workers=4) as executor:
            results = list(executor.map(replay, range(6)))
        self.assertEqual(sum(row['changed'] for row in results), 1)
        self.assertEqual(sum(row['unchanged'] for row in results), 5)
        with closing(self.store.connect(readonly=True)) as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM official_statistics_snapshots').fetchone()[0], 1)

    def test_corrupted_persisted_snapshot_fails_closed(self):
        self.store.import_official_statistics(encoded(), format='json', now=NOW)
        with closing(self.store.connect()) as connection, connection:
            connection.execute("UPDATE official_statistics_snapshots SET payload='{}'")
        with self.assertRaises(ValueError):
            stats.overview(self.store)

    def request(self):
        environment = {}
        setup_testing_defaults(environment)
        environment.update(REQUEST_METHOD='GET', PATH_INFO='/v1/statistics/official')
        captured = {}
        def start_response(status, headers):
            captured.update(status=status, headers=dict(headers))
        with patch.object(api, 'DATABASE_FILE', str(self.store.path)):
            payload = json.loads(b''.join(api.application(environment, start_response)))
        return captured, payload

    def test_additive_wsgi_endpoint_does_not_need_a_draw(self):
        self.assertFalse(self.request()[1]['available'])
        self.store.import_official_statistics(encoded(), format='json', now=NOW)
        response, payload = self.request()
        self.assertEqual(response['status'], '200 OK')
        self.assertEqual(response['headers']['Cache-Control'], 'no-cache')
        self.assertEqual(len(payload['data']['numbers']), 50)
        self.assertEqual(len(payload['data']['stars']), 12)
        self.assertEqual(self.store.all(), [])

    def test_comparison_uses_only_confirmed_history_before_snapshot_cutoff(self):
        self.store.import_rows([result()])
        later = {**result(), 'drawId': '084/2026', 'date': '2026-10-20'}
        self.store.import_rows([later])
        self.store.import_official_statistics(encoded(), format='json', now=NOW)
        comparison = stats.overview(self.store)['comparison']
        self.assertEqual(comparison['coverage']['storedDrawCount'], 1)
        self.assertFalse(comparison['coverage']['isCompleteHistory'])
        self.assertEqual(comparison['cutoffDate'], '2026-10-17')
        self.assertEqual(comparison['numbers'][0]['countDifference'], 9)
        self.assertFalse(comparison['countsMatch'])

    def test_cli_offline_replay_uses_shared_execution_lock(self):
        path = self.root / 'statistics.json'
        path.write_bytes(encoded())
        with patch('official_statistics.fetch', side_effect=AssertionError('No HTTP in offline import')):
            self.assertEqual(run_official_statistics(self.store.path, source_file=path, input_format='json')['changed'], 1)
            with self.store.path.with_suffix('.sqlite3.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.assertEqual(run_official_statistics(self.store.path, source_file=path, input_format='json')['skipped'], 'locked')

    def test_missing_database_is_not_created_and_remote_failure_keeps_cache(self):
        with self.assertRaises(ValueError):
            run_official_statistics(self.root / 'absent.sqlite3')
        self.assertFalse((self.root / 'absent.sqlite3').exists())
        with self.assertRaises(sqlite3.OperationalError):
            Store(self.root / 'absent.sqlite3').import_official_statistics(encoded(), format='json', now=NOW)
        self.assertFalse((self.root / 'absent.sqlite3').exists())
        self.store.import_official_statistics(encoded(), format='json', now=NOW)
        before = stats.overview(self.store)
        with patch('official_statistics.fetch', side_effect=URLError('synthetic offline failure')):
            self.assertEqual(run_official_statistics(self.store.path)['exitCode'], 1)
        self.assertEqual(stats.overview(self.store), before)

    def test_cli_remote_requires_explicit_enabled_config(self):
        with patch('sys.argv', ['collect_results.py', '--official-statistics', '--database', str(self.store.path)]), \
                patch('official_statistics.fetch') as fetch, redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                main()
            self.assertEqual(caught.exception.code, 1)
            fetch.assert_not_called()
        path = self.root / 'statistics.json'
        path.write_bytes(encoded())
        with patch('sys.argv', ['collect_results.py', '--official-statistics', '--database', str(self.store.path),
                                '--statistics-file', str(path), '--statistics-format', 'json']), redirect_stdout(io.StringIO()):
            self.assertEqual(main(), 0)


if __name__ == '__main__':
    unittest.main()
