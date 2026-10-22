"""Controlled M1lhao structure and isolated SQLite; no remote access."""
from datetime import date
from pathlib import Path
import tempfile
import unittest

import historical_results as history
import official_milhao as official
from store import Store

FIXTURE = Path(__file__).parent / 'fixtures/official/milhao-structure-example.html'


def html():
    return FIXTURE.read_bytes()


def older():
    return html().replace(b'Sorteio: 009/2026', b'Sorteio: 008/2026').replace(
        b'25/09/2026', b'18/07/2026').replace(b'PTM09893', b'XYZ00001')


class MilhaoHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = Store(Path(self.temp.name) / 'results.sqlite3')
        self.store.migrate()

    def test_code_date_and_actual_prize(self):
        row, issues = official.parse(html())
        self.assertEqual(row['winningCode'], 'PTM09893')
        self.assertEqual(row['drawId'], '009/2026')
        self.assertEqual(row['date'], '2026-09-25')
        self.assertEqual(row['amountCents'], 100000000)
        self.assertEqual(row['sourceUrl'], official.URL)
        self.assertEqual(row['status'], 'complete')
        self.assertEqual(issues, [])

    def test_missing_prize_is_partial_not_inferred(self):
        row, issues = official.parse(html().replace('€ 1.000.000,00'.encode(), b'-'))
        self.assertEqual(row['status'], 'numbers_confirmed')
        self.assertIsNone(row['amountCents'])
        self.assertTrue(issues)

    def test_invalid_ambiguous_codes_dates_and_counts(self):
        for payload in (
                html().replace(b'PTM09893', b'PTM0989'),
                html().replace(b'PTM09893', b'PTM09893 XYZ00001'),
                html().replace(b'25/09/2026', b'31/02/2026'),
                html().replace(b'25/09/2026', b'25/09/2025'),
                html().replace(b'<li>1</li>', b'<li>2</li>'),
                html().replace(b'/web/SCCartazResult/m1lhao', b'/web/SCCartazResult/euroMilhoes')):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                official.parse(payload)

    def test_collect_uses_milhao_selection_and_window(self):
        calls = []
        def fetch(selection=None):
            calls.append(selection)
            return html() if selection is None else older()
        report, items = history.collect(date(2026, 10, 20), fetch,
                                        pause=lambda _: None, adapter=official)
        self.assertEqual(calls, [None, '15069.0'])
        self.assertEqual(report['selectedCount'], 1)
        self.assertEqual(report['latestAvailable'], '2026-09-25')
        self.assertTrue(report['startBoundaryCovered'])
        self.assertEqual(items[0][0]['game'], 'milhao')
        with self.assertRaises(ValueError):
            history.collect(date(2026, 10, 20), lambda selection=None: html(),
                            pause=lambda _: None, adapter=official)

    def test_backup_import_repeat_and_correct_audit_source(self):
        row, _ = official.parse(html())
        items = [(row, html())]
        preview = history.apply_batch(self.store, items, {}, adapter=official)
        self.assertEqual(preview['wouldChange'], 1)
        self.assertEqual(self.store.all(), [])
        result = history.apply_batch(self.store, items, {}, apply=True, adapter=official)
        self.assertEqual(result['game'], 'milhao')
        self.assertEqual(result['changed'], 1)
        self.assertEqual(Store(result['backup']).all(), [])
        again = history.apply_batch(self.store, items, {}, apply=True, adapter=official)
        self.assertEqual(again['changed'], 0)
        self.assertEqual(len(self.store.changes()), 1)
        with self.store.connect(readonly=True) as db:
            urls = [r[0] for r in db.execute('SELECT source_url FROM official_observations')]
        self.assertEqual(urls, [official.URL])

    def test_prize_conflict_stops_all_imports(self):
        row, _ = official.parse(html())
        row['amountCents'] = 123
        self.store.import_rows([row])
        result = history.apply_batch(self.store, [
            (official.parse(html())[0], html())], {}, apply=True, adapter=official)
        self.assertEqual(result['status'], 'conflicts_no_import')
        self.assertEqual(self.store.all()[0]['amountCents'], 123)

    def test_legacy_missing_amount_can_be_completed_without_code_changes(self):
        row, _ = official.parse(html())
        row.pop('amountCents')
        self.store.import_rows([row], source='legacy-json')
        result = history.apply_batch(self.store, [
            (official.parse(html())[0], html())], {}, apply=True, adapter=official)
        self.assertEqual(result['changed'], 1)
        self.assertEqual(self.store.all()[0]['amountCents'], 100000000)
