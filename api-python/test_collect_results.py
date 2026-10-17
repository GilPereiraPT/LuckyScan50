"""Offline Cron integration. Network calls are mocked or prohibited."""
from contextlib import closing, redirect_stderr
from datetime import datetime
import fcntl
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import URLError
import xml.etree.ElementTree as ET

from backup_results import backup
from collect_results import main, run, run_rss, verified_dates
from result_statistics import frequencies
import rss_import as rss
from store import Store
from test_rss import sample, changed, FIXTURES


class CollectorTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.store = Store(self.root / 'validation.sqlite3')
        self.store.migrate()
        blocker = patch('rss_import.build_opener', side_effect=AssertionError('Remote collection is not authorized in tests'))
        blocker.start()
        self.addCleanup(blocker.stop)

    def test_three_real_feeds_are_idempotent_and_dates_pending(self):
        one = run_rss(self.store.path, fixtures=FIXTURES)
        two = run_rss(self.store.path, fixtures=FIXTURES)
        self.assertEqual(one, two)
        self.assertEqual(one['exitCode'], 0)
        self.assertEqual(one['feeds']['results']['pendingDate'], 2)
        self.assertEqual(self.store.all(), [])
        self.assertEqual(len(rss.overview(self.store)['data']), 6)
        with closing(self.store.connect(readonly=True)) as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM rss_imports').fetchone()[0], 3)
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM rss_observations').fetchone()[0], 6)

    def test_http_mode_dispatches_all_three_fixed_feeds_with_mock_transport(self):
        with patch('rss_import.fetch', side_effect=sample) as transport:
            report = run_rss(self.store.path)
        self.assertEqual([call.args[0] for call in transport.call_args_list], ['results', 'jackpots', 'portal'])
        self.assertEqual(report['exitCode'], 0)
        self.assertFalse(report['offline'])

    def test_lock_prevents_all_fetches_and_inbox_uses_same_lock(self):
        inbox = self.root / 'inbox'
        inbox.mkdir()
        with self.store.path.with_suffix('.sqlite3.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch('rss_import.fetch') as transport:
                self.assertEqual(run_rss(self.store.path)['skipped'], 'locked')
                self.assertEqual(run(self.store.path, inbox), 0)
                transport.assert_not_called()

    def test_missing_database_is_not_created(self):
        path = self.root / 'missing.sqlite3'
        with self.assertRaises(ValueError):
            run_rss(path, fixtures=FIXTURES)
        self.assertFalse(path.exists())

    def test_existing_confirmed_result_is_unchanged(self):
        fixture = Path(__file__).parent.parent / 'backend/fixtures/euromilhoes-083-2026.json'
        original = json.loads(fixture.read_text())
        self.store.import_rows([original])
        report = run_rss(self.store.path, fixtures=FIXTURES)
        self.assertEqual(report['exitCode'], 0)
        self.assertEqual(self.store.all(), [original])
        self.assertEqual(len(self.store.changes()), 1)

    def test_same_cycle_conflict_is_staged_before_any_promotion(self):
        def upstream(kind):
            return changed(description='Sorteio nº 083/2026: 8 15 16 22 35 + 4 6') if kind == 'results' else sample(kind)
        with patch('rss_import.fetch', side_effect=upstream):
            report = run_rss(self.store.path, dates={('euromilhoes', '083/2026'): '2026-10-16'})
        self.assertEqual(report['exitCode'], 2)
        self.assertEqual(self.store.all(), [])
        self.assertGreater(rss.overview(self.store)['conflicts'], 0)

    def test_one_failed_feed_keeps_others_and_existing_snapshots(self):
        run_rss(self.store.path, fixtures=FIXTURES)
        def upstream(kind):
            if kind == 'jackpots':
                raise URLError('simulated unavailable')
            return sample(kind)
        with patch('rss_import.fetch', side_effect=upstream):
            report = run_rss(self.store.path)
        self.assertEqual(report['exitCode'], 1)
        self.assertIn('error', report['feeds']['jackpots'])
        self.assertEqual(len(rss.overview(self.store)['data']), 6)

    def test_bad_xml_does_not_stop_other_feeds(self):
        with patch('rss_import.fetch', side_effect=lambda kind: b'<bad' if kind == 'results' else sample(kind)):
            report = run_rss(self.store.path)
        self.assertEqual(report['exitCode'], 1)
        self.assertEqual(report['feeds']['portal']['accepted'], 2)
        self.assertEqual(report['feeds']['jackpots']['accepted'], 2)
        self.assertEqual(self.store.all(), [])

    def test_failure_audit_error_does_not_stop_other_feeds(self):
        with patch('rss_import.fetch', side_effect=lambda kind: b'<bad' if kind == 'results' else sample(kind)), \
                patch('rss_import.record_failure', side_effect=sqlite3.OperationalError('simulated audit failure')):
            report = run_rss(self.store.path)
        self.assertEqual(report['exitCode'], 1)
        self.assertEqual(report['feeds']['results']['auditError'], 'storage_unavailable')
        self.assertEqual(report['feeds']['portal']['accepted'], 2)

    def test_reviewed_date_after_publication_cannot_create_future_draw(self):
        with self.assertRaises(ValueError):
            rss.ingest(self.store, sample(), 'results', {('euromilhoes', '083/2026'): '2026-10-17'})
        self.assertEqual(self.store.all(), [])
        report = run_rss(self.store.path, fixtures=FIXTURES,
                         dates={('euromilhoes', '083/2026'): '2026-10-17'})
        self.assertEqual(report['exitCode'], 1)
        self.assertEqual(report['feeds']['results']['phase'], 'promotion')
        self.assertEqual(self.store.all(), [])

    def test_previously_announced_date_promotes_future_result_without_using_publication(self):
        run_rss(self.store.path, fixtures=FIXTURES)
        root = ET.fromstring(sample())
        for item in root.findall('./channel/item'):
            if item.findtext('title') == 'Euromilhões':
                item.find('description').text = '<b>Sorteio nº 084/2026</b>: 7 15 16 22 35 + 4 6'
                # Later publication day deliberately differs from draw day.
                item.find('pubDate').text = 'Wed, 21 Oct 2026 01:00:00 GMT'
        future = ET.tostring(root, encoding='utf-8')
        with patch('rss_import.fetch', side_effect=lambda kind: future if kind == 'results' else sample(kind)):
            report = run_rss(self.store.path)
            again = run_rss(self.store.path)
        self.assertEqual(report['feeds']['results']['inserted'], 1)
        self.assertEqual(again['feeds']['results']['inserted'], 0)
        row = self.store.all()[0]
        self.assertEqual((row['game'], row['drawId'], row['date'], row['status']),
                         ('euromilhoes', '084/2026', '2026-10-20', 'numbers_confirmed'))
        self.assertEqual(len(self.store.changes()), 1)

    def test_conflicting_announced_dates_are_quarantined_and_audited(self):
        run_rss(self.store.path, fixtures=FIXTURES)
        root = ET.fromstring(sample('jackpots'))
        item = next(i for i in root.findall('./channel/item') if i.findtext('title') == 'Euromilhões')
        item.find('description').text = item.findtext('description').replace('20/10/2026', '21/10/2026')
        variant = ET.tostring(root, encoding='utf-8')
        with patch('rss_import.fetch', side_effect=lambda kind: variant if kind == 'jackpots' else sample(kind)):
            one = run_rss(self.store.path)
            two = run_rss(self.store.path)
        self.assertEqual(one['exitCode'], 2)
        self.assertEqual(two['exitCode'], 2)
        self.assertEqual(one['dateConflicts'], [{'game': 'euromilhoes', 'drawId': '084/2026'}])
        self.assertFalse(any(r['feed'] == 'jackpots' and r['game'] == 'euromilhoes' for r in rss.overview(self.store)['data']))
        with closing(self.store.connect(readonly=True)) as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM rss_imports WHERE status='conflict'").fetchone()[0], 1)

    def test_remote_cli_requires_explicit_enabled_config(self):
        config = self.root / 'config.json'
        config.write_text(json.dumps({'database': str(self.store.path), 'enabled': False}))
        with patch('sys.argv', ['collect_results.py', '--rss', '--config', str(config)]), redirect_stderr(io.StringIO()), patch('rss_import.fetch') as transport:
            with self.assertRaises(SystemExit) as caught:
                main()
            self.assertEqual(caught.exception.code, 1)
            transport.assert_not_called()

    def test_offline_cli_and_config_dates_are_independent_by_game(self):
        dates = self.root / 'dates.json'
        dates.write_text(json.dumps([{'game': 'euromilhoes', 'drawId': '083/2026', 'date': '2026-10-16',
                                     'sourceUrl': 'https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes'}]))
        config = self.root / 'config.json'
        config.write_text(json.dumps({'database': str(self.store.path), 'enabled': False, 'datesFile': str(dates)}))
        with patch('sys.argv', ['collect_results.py', '--rss', '--config', str(config), '--fixtures', str(FIXTURES)]):
            self.assertEqual(main(), 0)
        self.assertEqual(len(self.store.all()), 1)
        self.assertEqual(self.store.all()[0]['game'], 'euromilhoes')
        self.assertEqual(len(rss.overview(self.store)['data']), 6)

    def test_invalid_reviewed_dates_rejected(self):
        path = self.root / 'dates.json'
        for values in ({}, [{'game': 'euromilhoes', 'drawId': '083/2026', 'date': '2025-10-16', 'sourceUrl': 'https://example.org'}],
                       [{'game': 'milhao', 'drawId': '009/2026', 'date': '2026-02-30', 'sourceUrl': 'https://example.org'}]):
            path.write_text(json.dumps(values))
            with self.assertRaises(ValueError):
                verified_dates(path)

    def test_backup_is_consistent_and_never_overwrites_existing_backup(self):
        run_rss(self.store.path, fixtures=FIXTURES)
        path = self.root / 'backup.sqlite3'
        backup(self.store.path, path)
        self.assertEqual(Store(path).all(), self.store.all())
        self.assertEqual(rss.overview(Store(path)), rss.overview(self.store))
        with self.assertRaises(FileExistsError):
            backup(self.store.path, path)

    def test_single_draw_statistics_never_claim_full_history(self):
        run_rss(self.store.path, fixtures=FIXTURES, dates={('euromilhoes', '083/2026'): '2026-10-16'})
        values = frequencies(self.store.all(), 'numbers')
        self.assertEqual(values['drawCount'], 1)
        self.assertFalse(values['coverage']['isCompleteHistory'])
        self.assertEqual(values['coverage']['historyStart'], '2004-02-13')
        self.assertIn('Amostra', values['coverage']['notice'])


if __name__ == '__main__':
    unittest.main()
