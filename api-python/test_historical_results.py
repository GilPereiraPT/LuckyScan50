"""History collector: offline official fixture, no production or remote writes."""
from datetime import date
import json
from pathlib import Path
import re
import tempfile
import unittest

import historical_results as history
import official_cartaz as official
from store import Store

HTML = Path(__file__).parent / 'fixtures/official/euromilhoes.html'


def landing():
    payload = HTML.read_bytes()
    return re.sub(
        br'<select name="selectContest">.*?</select>',
        b'<select name="selectContest"><option value="15233.0">083/2026 - sexta-feira</option>'
        b'<option value="14999.0">053/2026 - sexta-feira</option></select>',
        payload, flags=re.S)


def older():
    return landing().replace(b'Sorteio: 083/2026', b'Sorteio: 053/2026').replace(
        b'Data do Sorteio - 16/10/2026', b'Data do Sorteio - 15/07/2026')


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = Store(Path(self.temp.name) / 'results.sqlite3')
        self.store.migrate()

    def test_real_catalogue_uses_explicit_ids(self):
        entries = history.catalogue(HTML.read_bytes())
        self.assertIn(('083/2026', '15233.0'), entries)
        self.assertIn(('078/2026', '15067.0'), entries)

    def test_collect_filters_exact_window_and_uses_post_selection(self):
        requested = []
        def fetch(selection=None):
            requested.append(selection)
            return landing() if selection is None else older()
        report, rows = history.collect(date(2026, 10, 20), fetch, pause=lambda _: None)
        self.assertEqual(requested, [None, '14999.0'])
        self.assertEqual(report['from'], '2026-07-23')
        self.assertEqual(report['selectedCount'], 1)
        self.assertTrue(report['startBoundaryCovered'])
        self.assertEqual(rows[0][0]['drawId'], '083/2026')

    def test_server_ignoring_selection_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'requested draw'):
            history.collect(date(2026, 10, 20), lambda selection=None: landing(), pause=lambda _: None)
        self.assertEqual(self.store.all(), [])

    def test_preview_no_write_then_import_backup_and_repeat(self):
        row, _ = official.parse(landing())
        items = [(row, landing())]
        report = {'selectedCount': 1}
        preview = history.apply_batch(self.store, items, report)
        self.assertEqual(preview['wouldChange'], 1)
        self.assertEqual(self.store.all(), [])
        result = history.apply_batch(self.store, items, report, apply=True)
        self.assertEqual(result['changed'], 1)
        self.assertTrue(Path(result['backup']).is_file())
        self.assertEqual(Store(result['backup']).all(), [])
        self.assertEqual(self.store.all()[0]['numbers'], [7, 15, 16, 22, 35])
        repeat = history.apply_batch(self.store, items, report, apply=True)
        self.assertEqual(repeat['changed'], 0)
        self.assertEqual(len(self.store.changes()), 1)
        manifest = json.loads(Path(result['backup']).with_name('manifest.json').read_text())
        self.assertEqual(len(manifest['snapshots']['083/2026']), 64)

    def test_conflict_prevents_entire_batch(self):
        row, _ = official.parse(landing())
        row['numbers'] = [1, 2, 3, 4, 5]
        self.store.import_rows([row])
        old, _ = official.parse(older())
        result = history.apply_batch(self.store, [(old, older()),
            (official.parse(landing())[0], landing())], {}, apply=True)
        self.assertEqual(result['status'], 'conflicts_no_import')
        self.assertEqual(len(self.store.all()), 1)
        self.assertEqual(self.store.all()[0]['numbers'], [1, 2, 3, 4, 5])

    def test_official_catalogue_destination_not_arbitrary(self):
        with self.assertRaises(ValueError):
            history.catalogue(landing().replace(
                b'action="/web/SCCartazResult/euroMilhoes"', b'action="https://example.test"'))
