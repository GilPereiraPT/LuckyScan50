"""Regression tests over original official HTTPS XML snapshots."""
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import URLError
import xml.etree.ElementTree as ET

from domain import check_line
from result_statistics import frequencies
from rss_import import FEEDS, FeedError, NoRedirect, cents, fetch, ingest, overview, parse, run_remote
from store import Store
import test_app

FIXTURES = Path(__file__).parent / 'fixtures/rss'
NAMES = {'results': 'rssFeedCartRes', 'jackpots': 'rssFeedJackpots', 'portal': 'rssFeedPremiosPortal'}


def sample(kind='results'):
    return (FIXTURES / (NAMES[kind] + '.xml')).read_bytes()


def changed(kind='results', game='Euromilhões', description=None, title=None):
    root = ET.fromstring(sample(kind))
    item = next(i for i in root.findall('./channel/item') if i.findtext('title') == game)
    if description is not None:
        item.find('description').text = description
    if title is not None:
        item.find('title').text = title
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


class ParseTests(unittest.TestCase):
    def test_real_cartres(self):
        euro, milhao = parse(sample(), 'results')
        self.assertEqual((euro['drawId'], euro['numbers'], euro['stars']), ('083/2026', [7,15,16,22,35], [4,6]))
        self.assertEqual((milhao['drawId'], milhao['winningCode']), ('009/2026', 'PTM 09893'))
        self.assertEqual(euro['publishedAt'], '2026-10-16T19:51:19+00:00')
        self.assertNotIn('date', euro)

    def test_real_jackpots(self):
        euro, milhao = parse(sample('jackpots'), 'jackpots')
        self.assertEqual(euro['upcoming'], {'drawId': '084/2026', 'date': '2026-10-20', 'amountCents': 5900000000, 'kind': 'forecast_jackpot'})
        self.assertEqual(milhao['upcoming'], {'drawId': '010/2026', 'date': '2026-10-30', 'amountCents': 100000000, 'kind': 'advertised_prize'})
        self.assertEqual(euro['numbers'], [7,15,16,22,35])
        self.assertEqual(euro['stars'], [4,6])
        self.assertEqual(milhao['winningCode'], 'PTM 09893')
        self.assertEqual(euro['publishedAt'], '2026-10-16T20:01:29+00:00')

    def test_real_portal_not_individual_prizes(self):
        euro, milhao = parse(sample('portal'), 'portal')
        self.assertEqual(euro['lastDraw'], {'totalCents': 10155509, 'largestCents': 22464, 'largestCategory': 5, 'categoryLabel': '5.º Prémio'})
        self.assertEqual(euro['allTime']['totalCents'], 33232462001)
        self.assertEqual(euro['allTime']['largestCents'], 733182700)
        self.assertEqual(euro['allTime']['largestCategory'], 1)
        self.assertEqual(milhao['lastDraw'], {'totalCents': 0, 'largestCents': 0, 'largestCategory': None, 'categoryLabel': 'SEM DADOS'})
        self.assertEqual(milhao['allTime']['totalCents'], 4300000000)
        self.assertEqual(milhao['allTime']['largestCents'], 100000000)
        self.assertEqual(euro['scope'], 'portal_only')
        self.assertEqual(euro['publishedAt'], '2026-10-17T03:00:19+00:00')
        self.assertNotIn('tiers', euro)

    def test_encodings_order_and_exact_titles(self):
        root = ET.fromstring(sample())
        channel = root.find('channel')
        items = channel.findall('item')
        for item in items:
            channel.remove(item)
        for item in reversed(items):
            channel.append(item)
        for encoding in ('iso-8859-1','utf-8','utf-16','utf-32','utf-16-be','windows-1252'):
            with self.subTest(encoding=encoding):
                rows = parse(ET.tostring(root, encoding=encoding, xml_declaration=True), 'results')
                self.assertEqual({r['game']: r['drawId'] for r in rows}, {'milhao': '009/2026', 'euromilhoes': '083/2026'})
        self.assertEqual([r['game'] for r in parse(changed(title='Euromilhões Extra'), 'results')], ['milhao'])

    def test_original_fixture_checksums(self):
        manifest=json.loads((FIXTURES/'manifest.json').read_text())
        for entry in manifest:
            raw=sample(entry['feed'])
            self.assertEqual(hashlib.sha256(raw).hexdigest(),entry['sha256'])
            self.assertEqual(len(raw),entry['bytes'])

    def test_html_and_xml_entities(self):
        payload = changed(description='<b>Sorteio n&#186; 083/2026</b>: 7&nbsp;15 16 22 35 + 4 6')
        self.assertEqual(parse(payload, 'results')[0]['numbers'], [7,15,16,22,35])

    def test_invalid_xml_dtd_and_duplicates(self):
        bad = [b'not xml', b'<rss>', b'<rss version="1.0"><channel/></rss>', b'<!DOCTYPE rss [<!ENTITY x "abc">]><rss version="2.0"><channel/></rss>', '<?xml version="1.0" encoding="UTF-16"?><!DOCTYPE rss><rss/>'.encode('utf-16')]
        root = ET.fromstring(sample())
        channel = root.find('channel')
        channel.append(copy.deepcopy(next(i for i in channel.findall('item') if i.findtext('title') == 'Euromilhões')))
        bad.append(ET.tostring(root))
        for data in bad:
            with self.subTest(data=data[:60]), self.assertRaises(ValueError):
                parse(data, 'results')

    def test_invalid_keys_and_draws(self):
        for identity, value in [('000/2026','7 15 16 22 35 + 4 6'), ('83/2026','7 15 16 22 35 + 4 6'), ('083/2026','7 15 16 22 51 + 4 6'), ('083/2026','7 15 16 22 35 + 4 13'), ('083/2026','7 7 16 22 35 + 4 6'), ('083/2026','7 15 16 22 + 4 6'), ('083/2026','7 15 16 22 35 + 4')]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse(changed(description='Sorteio nº '+identity+': '+value), 'results')
        with self.assertRaises(ValueError):
            parse(changed(game='M1lhão', description='Sorteio nº 009/2026: PTM 9893'), 'results')

    def test_invalid_jackpots_and_money(self):
        root = ET.fromstring(sample('jackpots'))
        desc = next(i.findtext('description') for i in root.findall('./channel/item') if i.findtext('title') == 'Euromilhões')
        for old, new in [('20/10/2026','31/02/2026'),('084/2026','084/2025'),('084/2026','082/2026'),('084/2026','090/2026'),('59.000.000,00','59.000,0'),('59.000.000,00','0,00')]:
            with self.subTest(new=new), self.assertRaises(ValueError):
                parse(changed('jackpots', description=desc.replace(old,new)), 'jackpots')
        for value in ['1,001','-1,00','1.00,00','NaN','1e3','59,000,000.00']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                cents(value)
        self.assertEqual(cents('59.000.000,00'), 5900000000)
        self.assertEqual(cents('0,00'), 0)

    def test_incomplete_portal(self):
        with self.assertRaises(ValueError):
            parse(changed('portal', description='Último Sorteio 083/2026 Total Prémios € 101.555,09'), 'portal')

    def test_fixed_https_no_redirect_and_size_limit(self):
        self.assertTrue(all(url.startswith('https://www.jogossantacasa.pt/web/SCRss/') for url in FEEDS.values()))
        for url in ('http://example.org/rss','https://example.org/rss'):
            with self.assertRaises(FeedError):
                NoRedirect().redirect_request(None,None,302,'',{},url)
        with patch('rss_import.build_opener') as opener:
            response = opener.return_value.open.return_value.__enter__.return_value
            response.status, response.url = 200, FEEDS['results']
            response.read.return_value = b'x' * (1024 * 1024 + 1)
            with self.assertRaises(FeedError):
                fetch('results')

    def test_publication_validation_and_channel_fallback(self):
        root = ET.fromstring(sample())
        item = next(i for i in root.findall('./channel/item') if i.findtext('title')=='Euromilhões')
        item.remove(item.find('pubDate'))
        self.assertEqual(parse(ET.tostring(root,encoding='utf-8'),'results')[0]['publishedAt'], '2026-10-16T19:51:19+00:00')
        root.find('channel/pubDate').text = 'invalid'
        with self.assertRaises(ValueError):
            parse(ET.tostring(root,encoding='utf-8'),'results')

    def test_incomplete_portal_money_and_future_draw_id(self):
        root = ET.fromstring(sample('portal'))
        desc = next(i.findtext('description') for i in root.findall('./channel/item') if i.findtext('title')=='Euromilhões')
        for old,new in [('224,64','999.999,99'), ('5.º Prémio','14.º Prémio'), ('101.555,09','101.555,0')]:
            with self.subTest(new=new), self.assertRaises(ValueError):
                parse(changed('portal',description=desc.replace(old,new)),'portal')
        with self.assertRaises(ValueError):
            parse(changed(description='Sorteio nº 083/2027: 7 15 16 22 35 + 4 6'),'results')


class ImportTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.store = Store(Path(directory.name) / 'validation.sqlite3')
        self.dates = {('euromilhoes','083/2026'): '2026-10-16', ('milhao','009/2026'): '2026-10-16'}

    def test_idempotent_pending_date_then_promotion(self):
        self.assertEqual(ingest(self.store,sample(),'results')['pendingDate'], 2)
        self.assertEqual(self.store.all(), [])
        self.assertEqual(ingest(self.store,sample(),'results',self.dates)['inserted'], 2)
        self.assertEqual(ingest(self.store,sample(),'results',self.dates)['inserted'], 0)
        self.assertEqual(ingest(self.store,sample('jackpots'),'jackpots')['conflicts'], 0)
        self.assertEqual(len(self.store.changes()), 2)
        self.assertEqual(len(overview(self.store)['data']), 4)
        self.assertTrue(all(row['status']=='numbers_confirmed' for row in self.store.all()))
        self.assertEqual(frequencies(self.store.all(),'numbers')['drawCount'], 1)
        self.assertEqual(len(frequencies(self.store.all(),'stars')['data']), 12)

    def test_preserve_confirmed_tiers_on_portal_and_key_conflict(self):
        official = json.loads((Path(__file__).parent.parent/'backend/fixtures/euromilhoes-083-2026.json').read_text())
        self.store.import_rows([official])
        ingest(self.store,sample(),'results',self.dates)
        ingest(self.store,sample('portal'),'portal')
        divergent = changed(description='Sorteio nº 083/2026: 8 15 16 22 35 + 4 6')
        self.assertEqual(ingest(self.store,divergent,'results')['conflicts'], 1)
        self.assertEqual(next(r for r in self.store.all() if r['game']=='euromilhoes'), official)
        self.assertEqual(check_line(official,[7,15,16,22,40],[4,10])['amountCents'],10106)
        self.assertEqual(len(self.store.changes()), 2)
        self.assertEqual([r['feed'] for r in overview(self.store)['data'] if r['game']=='euromilhoes'], ['portal'])

    def test_crossfeed_conflict_before_draw_insert(self):
        ingest(self.store,sample(),'results')
        root = ET.fromstring(sample('jackpots'))
        item = next(i for i in root.findall('./channel/item') if i.findtext('title')=='Euromilhões')
        item.find('description').text = item.findtext('description').replace('7 15 16 22 35','8 15 16 22 35')
        report = ingest(self.store,ET.tostring(root,encoding='utf-8'),'jackpots',self.dates)
        self.assertEqual(report['conflicts'], 1)
        self.assertFalse(any(r['game']=='euromilhoes' for r in self.store.all()))
        self.assertFalse(any(r['game']=='euromilhoes' for r in overview(self.store)['data']))

    def test_failure_preserves_data_and_audits(self):
        ingest(self.store,sample(),'results',self.dates)
        before = self.store.all()
        with patch('rss_import.fetch',side_effect=URLError('unavailable')):
            outcomes = run_remote(self.store,['results','jackpots','portal'])
        self.assertTrue(all('error' in row for row in outcomes.values()))
        self.assertEqual(self.store.all(), before)
        self.assertEqual(len(overview(self.store)['data']), 2)
        with self.assertRaises(ValueError):
            ingest(self.store,b'<broken','results')
        self.assertEqual(self.store.all(), before)
        with closing(self.store.connect(readonly=True)) as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM rss_imports WHERE status='failed'").fetchone()[0], 3)
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM rss_imports WHERE status='invalid'").fetchone()[0], 1)

    def test_atomic_rollback_invalid_explicit_date(self):
        with self.assertRaises(ValueError):
            ingest(self.store,sample(),'results',{**self.dates,('milhao','009/2026'):'2025-10-16'})
        self.assertEqual(self.store.all(), [])
        self.assertEqual(overview(self.store)['data'], [])

    def test_portal_never_creates_results(self):
        ingest(self.store,sample('portal'),'portal',self.dates)
        self.assertEqual(self.store.all(), [])
        self.assertEqual(len(overview(self.store)['data']), 2)

    def test_parallel_replays_create_one_revision_per_game(self):
        with ThreadPoolExecutor(max_workers=4) as pool:
            reports=list(pool.map(lambda _: ingest(self.store,sample(),'results',self.dates), range(4)))
        self.assertEqual(sum(r['inserted'] for r in reports),2)
        self.assertEqual(len(self.store.changes()),2)

    def test_one_feed_failure_does_not_stop_others(self):
        def upstream(kind):
            if kind=='results':
                raise URLError('unavailable')
            return sample(kind)
        with patch('rss_import.fetch',side_effect=upstream):
            outcome=run_remote(self.store,['results','jackpots','portal'])
        self.assertIn('error',outcome['results'])
        self.assertEqual(outcome['jackpots']['accepted'],2)
        self.assertEqual(outcome['portal']['accepted'],2)
        self.assertEqual(len(overview(self.store)['data']),4)

    def test_statistics_full_history_and_no_inferred_prize(self):
        self.store.import_rows([test_app.result()])
        ingest(self.store,sample(),'results',self.dates)
        counts=frequencies(self.store.all(),'numbers')
        self.assertEqual(counts['drawCount'],2)
        self.assertEqual(counts['data'][0]['count'],1)
        self.assertEqual(counts['data'][6]['count'],1)
        euro=next(r for r in self.store.all() if r['drawId']=='083/2026')
        self.assertTrue(all(t['amountCents'] is None for t in euro['tiers']))
        milhao=next(r for r in self.store.all() if r['game']=='milhao')
        self.assertIsNone(milhao['amountCents'])

    def test_later_administrative_correction_hides_observation(self):
        ingest(self.store,sample(),'results',self.dates)
        euro=next(r for r in self.store.all() if r['game']=='euromilhoes')
        euro['numbers']=[8,15,16,22,35]
        self.store.import_rows([euro])
        self.assertFalse(any(r['game']=='euromilhoes' for r in overview(self.store)['data']))
        self.assertEqual(overview(self.store)['conflicts'],1)

    def test_existing_draw_date_cannot_be_changed(self):
        ingest(self.store,sample(),'results',self.dates)
        report=ingest(self.store,sample(),'results',{('euromilhoes','083/2026'):'2026-10-15'})
        self.assertEqual(report['conflicts'],1)
        self.assertEqual(next(r for r in self.store.all() if r['game']=='euromilhoes')['date'],'2026-10-16')


class RSSAPITests(unittest.TestCase):
    setUp = test_app.APITests.setUp
    request = test_app.APITests.request
    def test_json_endpoint_cache_and_methods(self):
        self.assertEqual(self.request('/v1/rss/overview')[1], {'data': [], 'conflicts': 0})
        ingest(self.store,sample('jackpots'),'jackpots')
        code, body, headers = self.request('/v1/rss/overview')
        self.assertEqual(code, 200)
        self.assertEqual(headers['Cache-Control'], 'no-cache')
        euro = next(row for row in body['data'] if row['game']=='euromilhoes')
        self.assertEqual(euro['upcoming']['amountCents'], 5900000000)
        self.assertEqual(self.request('/v1/rss/overview','POST')[0], 405)
        self.assertEqual(self.request('/v1/statistics/numbers')[2]['Cache-Control'], 'no-cache')


if __name__=='__main__':
    unittest.main()
