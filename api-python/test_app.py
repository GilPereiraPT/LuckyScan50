import copy
from contextlib import closing
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from wsgiref.util import setup_testing_defaults
import passenger_wsgi as api
from domain import TIERS, validate_result, check_line
from store import Store, read_json
from collect_results import run
from import_result import import_json


def result(game='euromilhoes'):
    row={'game':game,'drawId':'001/2026','date':'2026-01-02','status':'complete',
         'sourceUrl':'https://example.org/authorized-test-fixture','retrievedAt':'2026-01-03T09:00:00Z'}
    if game=='milhao':
        return {**row,'winningCode':'ABC 12345','amountCents':100000000}
    return {**row,'numbers':[1,2,3,4,5],'stars':[1,2],
            'tiers':[{'tier':i+1,'main':n,'stars':s,'amountCents':None if i==0 else 1000,
                      'winnersPortugal':0,'winnersTotal':0 if i==0 else 1} for i,(n,s) in enumerate(TIERS)]}


class APITests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.store=Store(self.root/'results.db')
        self.store.migrate()
        patcher=patch.object(api,'DATABASE_FILE',str(self.store.path))
        patcher.start()
        self.addCleanup(patcher.stop)

    def request(self,path,method='GET'):
        environ={}
        setup_testing_defaults(environ)
        environ.update(REQUEST_METHOD=method,PATH_INFO=path.split('?')[0],
                       QUERY_STRING=path.partition('?')[2],**{'wsgi.input':io.BytesIO()})
        captured={}
        def start(status,headers):
            captured.update(code=int(status[:3]),headers=dict(headers))
        body=json.loads(b''.join(api.application(environ,start)))
        return captured['code'],body,captured['headers']

    def test_health_empty_and_method(self):
        code,body,headers=self.request('/health')
        self.assertEqual((code,body['runtime']),(200,'native_wsgi'))
        self.assertEqual(self.request('/v1/draws/latest')[:2],(404,{'error':'no_validated_results'}))
        self.assertEqual(self.request('/v1/draws')[1]['data'],[])
        self.assertEqual(self.request('/v1/draws','POST')[0],405)
        self.assertEqual(self.request('/unknown')[0],404)

    def test_details_aliases_and_pagination(self):
        self.store.import_rows([result(),result('milhao')])
        newer={**result(),'drawId':'002/2026','date':'2026-01-06'}
        self.store.import_rows([newer])
        self.assertEqual(self.request('/v1/draws/latest')[1]['drawId'],'002/2026')
        self.assertEqual(self.request('/v1/milhao/001/2026')[1]['winningCode'],'ABC 12345')
        self.assertEqual(self.request('/v1/milhao/latest')[1],self.request('/v1/draws/latest?game=milhao')[1])
        self.assertEqual(self.request('/v1/draws/euromilhoes/001/2026')[1],result())
        body=self.request('/v1/draws?limit=1&offset=1')[1]
        self.assertEqual(body['data'][0]['drawId'],'001/2026')
        self.assertEqual(body['pagination']['total'],2)
        self.assertEqual(len(self.request('/v1/draws?from=2026-01-06')[1]['data']),1)

    def test_invalid_queries(self):
        for query in ('game=x','limit=0','limit=101','offset=-1','after=-1','from=2026-02-30',
                      'from=2026-02-01&to=2026-01-01','limit=2&limit=3'):
            with self.subTest(query=query):
                self.assertEqual(self.request('/v1/draws?'+query)[0],400)

    def test_storage_failure_closed(self):
        self.store.path.unlink()
        self.assertEqual(self.request('/v1/draws/latest')[0],503)
        self.assertFalse(self.store.path.exists())

    def test_sync_corrections_and_cursor(self):
        self.store.import_rows([result()])
        changed=result()
        changed['tiers'][1]['amountCents']=2000
        self.store.import_rows([changed])
        first=self.request('/v1/sync?limit=1')[1]
        self.assertTrue(first['hasMore'])
        second=self.request('/v1/sync?after='+str(first['nextCursor']))[1]
        self.assertEqual(second['data'][0]['revision'],2)
        self.assertEqual(second['data'][0]['result'],changed)
        self.assertFalse(second['hasMore'])

    def test_statistics_confirmed_keys_independent_of_prize_tiers(self):
        self.store.import_rows([result()])
        partial={**result(),'drawId':'002/2026','date':'2026-01-06','status':'numbers_confirmed'}
        self.store.import_rows([partial])
        numbers=self.request('/v1/statistics/numbers')[1]
        self.assertEqual(len(numbers['data']),50)
        self.assertEqual(numbers['drawCount'],2)
        self.assertEqual(numbers['scope'],'stored_confirmed_keys')
        self.assertFalse(numbers['coverage']['isCompleteHistory'])
        self.assertEqual(numbers['coverage']['storedDrawCount'],2)
        self.assertEqual(numbers['data'][0]['count'],2)
        self.assertEqual(numbers['data'][-1]['lastDate'],None)
        self.assertEqual(len(self.request('/v1/statistics/stars')[1]['data']),12)
        self.assertEqual(self.request('/v1/statistics/summary')[1]['drawCount'],2)

    def test_json_fallback_and_duplicate_detection(self):
        path=self.root/'results.json'
        path.write_text(json.dumps([result()]))
        with patch.object(api,'DATABASE_FILE',None),patch.object(api,'DATA_FILE',path):
            self.assertEqual(self.request('/v1/draws/latest')[1],result())
            self.assertEqual(self.request('/v1/sync')[1]['mode'],'snapshot')
        path.write_text(json.dumps([result(),result()]))
        with self.assertRaises(ValueError):
            read_json(path)

    def test_legacy_backup_repeatability_and_history(self):
        path=self.root/'legacy.json'
        path.write_text(json.dumps([result()]))
        original=path.read_bytes()
        self.assertEqual(self.store.import_legacy(path)['changed'],1)
        self.assertEqual(self.store.import_legacy(path)['unchanged'],1)
        self.assertEqual(path.read_bytes(),original)
        backups=list(self.root.glob('*.bak'))
        self.assertEqual(len(backups),1)
        self.assertEqual(backups[0].read_bytes(),original)
        timestamp_only={**result(),'retrievedAt':'2026-01-04T09:00:00Z'}
        self.assertEqual(self.store.import_rows([timestamp_only])['unchanged'],1)
        self.assertEqual(len(self.store.changes()),1)

    def test_legacy_cli_writer_preserves_previous_versions(self):
        path=self.root/'old.json'
        self.assertEqual(import_json(path,[result()])['changed'],1)
        self.assertEqual(import_json(path,[result()])['unchanged'],1)
        corrected=result()
        corrected['tiers'][1]['amountCents']=1500
        import_json(path,[corrected])
        self.assertEqual(read_json(path),[corrected])
        self.assertEqual(json.loads(next(self.root.glob('old.json.*.bak')).read_text()),[result()])


    def test_atomic_rollback_on_downgrade(self):
        self.store.import_rows([result()])
        new={**result('milhao')}
        partial={**result(),'status':'numbers_confirmed'}
        with self.assertRaises(ValueError):
            self.store.import_rows([new,partial])
        self.assertEqual(self.store.all(),[result()])
        self.assertEqual(len(self.store.changes()),1)

    def test_inbox_is_idempotent_and_retains_failed_inputs(self):
        inbox=self.root/'inbox'
        inbox.mkdir()
        (inbox/'one.json').write_text(json.dumps(result()))
        self.assertEqual(run(self.store.path,inbox),0)
        self.assertEqual(run(self.store.path,inbox),0)
        self.assertEqual(len(self.store.changes()),1)
        (inbox/'bad.json').write_text('{}')
        self.assertEqual(run(self.store.path,inbox),1)
        self.assertTrue((inbox/'bad.json').exists())


class DomainTests(unittest.TestCase):
    def test_all_tiers_and_unknown_prize(self):
        row=result()
        for i,(main,stars) in enumerate(TIERS):
            numbers=row['numbers'][:main]+list(range(40,40+5-main))
            star_numbers=row['stars'][:stars]+list(range(10,10+2-stars))
            self.assertEqual(check_line(row,numbers,star_numbers)['tier'],i+1)
        self.assertIsNone(check_line(row,row['numbers'],row['stars'])['amountCents'])
        self.assertEqual(check_line(row,[10,11,12,13,14],[10,11])['amountCents'],0)

    def test_invalid_records_are_value_errors(self):
        mutations=[{'numbers':[[],2,3,4,5]},{'numbers':[True,2,3,4,5]},
                   {'numbers':[1,1,2,3,4]},{'stars':[1,13]}, {'status':'unknown'},
                   {'sourceUrl':'https://'},{'drawId':'001/2025'}, {'retrievedAt':'2026-01-01T00:00:00'}]
        for change in mutations:
            with self.subTest(change=change),self.assertRaises(ValueError):
                validate_result({**result(),**change})
        for field,value in [('amountCents',1.5),('amountCents',-1),('winnersPortugal',2),('winnersTotal',None)]:
            row=result()
            row['tiers'][1][field]=value
            with self.subTest(field=field,value=value),self.assertRaises(ValueError):
                validate_result(row)

if __name__=='__main__':
    unittest.main()
