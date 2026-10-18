"""Real saved official HTML and controlled mutations; no production writes."""
from contextlib import closing
import fcntl
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import URLError

import official_cartaz as official
import rss_import as rss
from collect_results import run_rss
from store import Store
import test_app
from test_rss import FIXTURES, changed, sample

HTML = Path(__file__).parent / 'fixtures/official/euromilhoes.html'


def html():
    return HTML.read_bytes()


def modify_tier(number, old=None, new=None, remove=False):
    text = html().decode('iso-8859-1')
    pattern = r'<ul class="colums">\s*<li>' + str(number) + r'\.º Prémio</li>.*?</ul>'
    match = re.search(pattern, text, re.S)
    assert match
    replacement = '' if remove else match[0].replace(old, new)
    return (text[:match.start()] + replacement + text[match.end():]).encode('iso-8859-1')


class OfficialTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.store = Store(Path(temp.name) / 'offline.sqlite3')
        self.store.migrate()
        rss.initialize(self.store)
        for target in ('rss_import.build_opener', 'official_cartaz.build_opener'):
            blocker = patch(target, side_effect=AssertionError('No remote collection in unit tests'))
            blocker.start()
            self.addCleanup(blocker.stop)

    def test_original_cartaz_all_13_tiers_and_explicit_date(self):
        manifest = json.loads(HTML.with_name('manifest.json').read_text())
        self.assertEqual(hashlib.sha256(html()).hexdigest(), manifest['sha256'])
        row, issues = official.parse(html())
        reference = json.loads((Path(__file__).parent.parent / 'backend/fixtures/euromilhoes-083-2026.json').read_text())
        self.assertEqual(row['tiers'], reference['tiers'])
        self.assertEqual(row['date'], '2026-10-16')
        self.assertEqual(row['drawId'], '083/2026')
        self.assertEqual(row['numbers'], [7, 15, 16, 22, 35])
        self.assertEqual(row['stars'], [4, 6])
        self.assertEqual(row['status'], 'complete')
        self.assertEqual(issues, [])
        self.assertIsNone(row['tiers'][0]['amountCents'])
        self.assertEqual(row['tiers'][0]['winnersTotal'], 0)
        self.assertEqual(row['tiers'][4]['amountCents'], 10106)
        self.assertNotEqual(row['tiers'][0]['amountCents'], 5900000000)

    def test_missing_tier_is_pending_with_nulls(self):
        payload = modify_tier(13, remove=True)
        row, issues = official.parse(payload)
        self.assertEqual(row['status'], 'numbers_confirmed')
        self.assertEqual(len(row['tiers']), 13)
        self.assertIsNone(row['tiers'][12]['amountCents'])
        self.assertIsNone(row['tiers'][12]['winnersTotal'])
        self.assertTrue(issues)
        report = official.reconcile(self.store, payload)
        self.assertEqual(report['status'], 'pending')
        self.assertEqual(self.store.all()[0]['status'], 'numbers_confirmed')

    def test_missing_required_amount_does_not_complete_draw(self):
        payload = modify_tier(5, '&euro; 101,06&nbsp;', '-')
        row, _ = official.parse(payload)
        self.assertEqual(row['status'], 'numbers_confirmed')
        self.assertIsNone(row['tiers'][4]['amountCents'])
        self.assertEqual(row['tiers'][4]['winnersTotal'], 831)

    def test_absent_prize_table_preserves_verified_date_as_pending(self):
        payload = html().replace(b'customfiveCol', b'unknown-layout')
        row, issues = official.parse(payload)
        self.assertEqual(row['date'], '2026-10-16')
        self.assertEqual(row['status'], 'numbers_confirmed')
        self.assertTrue(all(t['amountCents'] is None for t in row['tiers']))
        self.assertTrue(issues)

    def test_missing_winner_count_is_pending(self):
        payload = modify_tier(5, '<li class="litleCol">61</li>', '<li class="litleCol">SEM DADOS</li>')
        row, _ = official.parse(payload)
        self.assertEqual(row['status'], 'numbers_confirmed')
        self.assertIsNone(row['tiers'][4]['winnersPortugal'])

    def test_missing_invalid_or_wrong_year_date_is_rejected(self):
        for old, new in (('Data do Sorteio - 16/10/2026', 'Sem data'),
                         ('16/10/2026', '31/02/2026'), ('16/10/2026', '16/10/2025')):
            with self.subTest(new=new), self.assertRaises(ValueError):
                official.reconcile(self.store, html().replace(old.encode(), new.encode()))
        self.assertEqual(self.store.all(), [])

    def test_tier_identity_and_bad_monetary_values_are_rejected(self):
        for payload in (modify_tier(5, '4 Números + 1 Estrela', '5 Números + 1 Estrela'),
                        modify_tier(5, '101,06', '-101,06'),
                        modify_tier(1, '(1)', '&euro; 59.000.000,00')):
            with self.subTest(payload=hashlib.sha256(payload).hexdigest()), self.assertRaises(ValueError):
                official.parse(payload)

    def test_repeated_result_does_not_add_revision(self):
        one = official.reconcile(self.store, html())
        two = official.reconcile(self.store, html())
        self.assertEqual(one['changed'], 1)
        self.assertEqual(two['changed'], 0)
        self.assertEqual(len(self.store.changes()), 1)
        with closing(self.store.connect(readonly=True)) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM official_observations').fetchone()[0], 1)
            self.assertIsNone(db.execute('SELECT published_at FROM official_observations').fetchone()[0])

    def test_compatible_pending_to_complete_preserves_two_revisions(self):
        rss.ingest(self.store, sample(), 'results', {('euromilhoes', '083/2026'): '2026-10-16'})
        self.assertEqual(self.store.all()[0]['status'], 'numbers_confirmed')
        report = official.reconcile(self.store, html())
        self.assertEqual(report['changed'], 1)
        self.assertEqual(self.store.all()[0]['status'], 'complete')
        self.assertEqual([r['revision'] for r in self.store.changes()], [1, 2])

    def test_new_draw_can_use_official_cartaz_even_without_rss(self):
        report = official.reconcile(self.store, html())
        self.assertEqual(report['changed'], 1)
        self.assertEqual(self.store.all()[0]['sourceUrl'], official.URL)

    def test_complete_money_conflict_never_overwrites_confirmed_result(self):
        official.reconcile(self.store, html())
        before = self.store.all()
        report = official.reconcile(self.store, modify_tier(5, '101,06', '102,06'))
        self.assertEqual(report['status'], 'conflict')
        self.assertEqual(self.store.all(), before)
        self.assertEqual(len(self.store.changes()), 1)

    def test_incomplete_cartaz_never_downgrades_complete_draw(self):
        official.reconcile(self.store, html())
        before = self.store.all()
        official.reconcile(self.store, modify_tier(13, remove=True))
        self.assertEqual(self.store.all(), before)
        self.assertEqual(len(self.store.changes()), 1)

    def test_known_partial_prize_cannot_be_silently_replaced_by_unawarded(self):
        row, _ = official.parse(html())
        row['status'] = 'numbers_confirmed'
        row['tiers'][0]['amountCents'] = 100
        row['tiers'][0]['winnersTotal'] = None
        self.store.import_rows([row])
        before = self.store.all()
        self.assertEqual(official.reconcile(self.store, html())['status'], 'conflict')
        self.assertEqual(self.store.all(), before)

    def test_key_disagreement_is_quarantined_before_any_insert(self):
        rss.ingest(self.store, changed(description='Sorteio nº 083/2026: 8 15 16 22 35 + 4 6'), 'results')
        report = official.reconcile(self.store, html())
        self.assertEqual(report['status'], 'conflict')
        rss.ingest(self.store, sample(), 'results', {('euromilhoes', '083/2026'): '2026-10-16'})
        self.assertEqual(self.store.all(), [])

    def test_verified_date_disagreement_stays_pending(self):
        report = official.reconcile(self.store, html(), {('euromilhoes', '083/2026'): '2026-10-15'})
        self.assertEqual(report['status'], 'conflict')
        self.assertEqual(self.store.all(), [])

    def test_real_offline_cycle_completes_euro_keeps_milhao_date_pending(self):
        report = run_rss(self.store.path, fixtures=FIXTURES, cartaz=True)
        self.assertEqual(report['exitCode'], 0)
        self.assertEqual(report['feeds']['cartaz']['status'], 'accepted')
        rows = self.store.all()
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]['game'], rows[0]['drawId'], rows[0]['status']), ('euromilhoes', '083/2026', 'complete'))
        self.assertEqual(report['feeds']['results']['pendingDate'], 1)
        self.assertEqual(len(rss.overview(self.store)['data']), 6)

    def test_milhao_uses_its_own_reviewed_date_and_never_euro_prizes(self):
        # Controlled reviewed date demonstrates independent association; not a
        # claim that the real 009/2026 draw happened on this synthetic test date.
        run_rss(self.store.path, fixtures=FIXTURES, cartaz=True,
                dates={('milhao', '009/2026'): '2026-10-09'})
        rows = {row['game']: row for row in self.store.all()}
        self.assertEqual(rows['euromilhoes']['date'], '2026-10-16')
        self.assertEqual(rows['milhao']['date'], '2026-10-09')
        self.assertEqual(rows['milhao']['winningCode'], 'PTM 09893')
        self.assertEqual(rows['milhao']['status'], 'numbers_confirmed')
        self.assertIsNone(rows['milhao']['amountCents'])

    def test_cartaz_failure_does_not_stop_rss_or_infer_prizes(self):
        with patch('rss_import.fetch', side_effect=sample), patch('official_cartaz.fetch', side_effect=URLError('offline')):
            report = run_rss(self.store.path, cartaz=True,
                             dates={('euromilhoes', '083/2026'): '2026-10-16'})
        self.assertEqual(report['exitCode'], 1)
        self.assertEqual(report['feeds']['portal']['accepted'], 2)
        self.assertEqual(self.store.all()[0]['status'], 'numbers_confirmed')
        self.assertTrue(all(t['amountCents'] is None for t in self.store.all()[0]['tiers']))

    def test_existing_collector_lock_prevents_cartaz_http_too(self):
        with self.store.path.with_suffix('.sqlite3.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch('official_cartaz.fetch') as request:
                report = run_rss(self.store.path, cartaz=True)
                request.assert_not_called()
        self.assertEqual(report['skipped'], 'locked')

    def test_cartaz_wrong_contest_never_fills_another_draw_prizes(self):
        def previous(kind):
            return changed(description='Sorteio nº 082/2026: 7 15 16 22 35 + 4 6') if kind == 'results' else sample(kind)
        with patch('rss_import.fetch', side_effect=previous), patch('official_cartaz.fetch', return_value=html()):
            run_rss(self.store.path, cartaz=True, dates={('euromilhoes', '082/2026'): '2026-10-13'})
        rows = {r['drawId']: r for r in self.store.all()}
        self.assertEqual(rows['083/2026']['status'], 'complete')
        self.assertEqual(rows['082/2026']['status'], 'numbers_confirmed')
        self.assertTrue(all(t['amountCents'] is None for t in rows['082/2026']['tiers']))


class CompatibilityTests(unittest.TestCase):
    setUp = test_app.APITests.setUp
    request = test_app.APITests.request

    def test_latest_sync_and_overview_keep_contracts(self):
        rss.ingest(self.store, sample(), 'results', {('euromilhoes', '083/2026'): '2026-10-16'})
        official.reconcile(self.store, html())
        code, latest, _ = self.request('/v1/draws/latest')
        self.assertEqual((code, latest['status'], len(latest['tiers'])), (200, 'complete', 13))
        changes = self.request('/v1/sync')[1]
        self.assertEqual(changes['mode'], 'revisions')
        self.assertEqual(len(changes['data']), 2)
        overview = self.request('/v1/rss/overview')[1]
        self.assertEqual(set(overview), {'data', 'conflicts'})
        euro = next(r for r in overview['data'] if r['game']=='euromilhoes')
        self.assertEqual(euro['historyStatus'], 'stored')
