"""Offline tests of the dual-game 90-day refresh and latest M1lhão."""
from datetime import date
import fcntl
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import URLError

from atualizar_resultados_90_dias import run
from collect_results import run_rss
from store import Store
from test_historical_results import landing as euro_landing, older as euro_older
from test_milhao_history import html as milhao_landing, older as milhao_older
from test_rss import FIXTURES


class RecentAutomaticResultsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'results.sqlite3'
        self.store = Store(self.path)
        self.store.migrate()
        self.today = date(2026, 11, 6)
        self.calls = {'euromilhoes': [], 'milhao': []}

    def euro_fetch(self, selection=None):
        self.calls['euromilhoes'].append(selection)
        if selection is None:
            return euro_landing()
        if selection == '14999.0':
            return euro_older()
        raise AssertionError('Unexpected Euromilhões contest selection')

    def milhao_fetch(self, selection=None):
        self.calls['milhao'].append(selection)
        if selection is None:
            return milhao_landing()
        if selection == '15069.0':
            return milhao_older()
        raise AssertionError('Unexpected M1lhão contest selection')

    def test_daily_backfills_both_games_then_is_idempotent(self):
        fetchers = {'euromilhoes': self.euro_fetch, 'milhao': self.milhao_fetch}
        first = run(self.path, today=self.today, fetchers=fetchers)
        self.assertEqual(first['exitCode'], 0, first)
        self.assertEqual(first['games']['euromilhoes']['changed'], 1)
        self.assertEqual(first['games']['milhao']['changed'], 1)
        self.assertEqual({r['game'] for r in self.store.all()}, {'euromilhoes', 'milhao'})
        self.assertEqual(len(self.store.changes()), 2)
        backups = list(self.path.parent.glob('history-imports/*/before.sqlite3'))
        self.assertEqual(len(backups), 2)
        again = run(self.path, today=self.today, fetchers=fetchers)
        self.assertEqual(again['exitCode'], 0, again)
        self.assertEqual(again['games']['euromilhoes']['status'], 'up_to_date')
        self.assertEqual(again['games']['milhao']['status'], 'up_to_date')
        self.assertEqual(len(self.store.changes()), 2)
        self.assertEqual(len(list(self.path.parent.glob('history-imports/*/before.sqlite3'))), 2)

    def test_failure_of_one_game_does_not_erase_other_result(self):
        def fail(_=None):
            raise URLError('Official M1lhão unavailable')
        result = run(self.path, today=self.today,
                     fetchers={'euromilhoes': self.euro_fetch, 'milhao': fail})
        self.assertEqual(result['exitCode'], 1)
        self.assertEqual(result['games']['euromilhoes']['changed'], 1)
        self.assertEqual(result['games']['milhao']['status'], 'failed')
        self.assertEqual([r['game'] for r in self.store.all()], ['euromilhoes'])

    def test_preexisting_daily_lock_skips_before_fetching(self):
        with self.path.with_suffix('.sqlite3.recent.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch('historical_results.OfficialSession') as transport:
                result = run(self.path, today=self.today)
                transport.assert_not_called()
        self.assertEqual(result['status'], 'already_running')
        self.assertEqual(self.store.all(), [])

    def test_absent_database_is_never_created(self):
        missing = self.path.parent / 'missing.sqlite3'
        with self.assertRaises(ValueError):
            run(missing, today=self.today)
        self.assertFalse(missing.exists())

    def test_latest_milhao_and_euromilhoes_from_same_offline_cron(self):
        report = run_rss(self.path, fixtures=FIXTURES, cartaz=True, milhao=True)
        self.assertEqual(report['exitCode'], 0, report)
        self.assertIn('milhao_cartaz', report['feeds'])
        self.assertEqual(report['feeds']['milhao_cartaz']['drawId'], '009/2026')
        stored = {r['game']: r for r in self.store.all()}
        self.assertEqual(set(stored), {'euromilhoes', 'milhao'})
        self.assertEqual(stored['milhao']['status'], 'complete')
        self.assertEqual(stored['milhao']['winningCode'], 'PTM09893')

    def test_unavailable_milhao_cartaz_does_not_block_euro(self):
        with patch('rss_import.fetch', side_effect=lambda kind: (FIXTURES / {
            'results': 'rssFeedCartRes.xml', 'jackpots': 'rssFeedJackpots.xml',
            'portal': 'rssFeedPremiosPortal.xml'}[kind]).read_bytes()), \
             patch('official_cartaz.fetch', return_value=euro_landing()), \
             patch('official_milhao.fetch', side_effect=URLError('offline')):
            report = run_rss(self.path, cartaz=True, milhao=True)
        self.assertEqual(report['exitCode'], 1, report)
        self.assertEqual(report['feeds']['cartaz']['drawId'], '083/2026')
        self.assertEqual(report['feeds']['milhao_cartaz']['error'], 'URLError')
        self.assertEqual([r['game'] for r in self.store.all()], ['euromilhoes'])


if __name__ == '__main__':
    unittest.main()
