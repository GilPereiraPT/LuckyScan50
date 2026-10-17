"""Public, read-only native WSGI API. No external Python dependencies."""
from datetime import date
import json
import logging
import os
from pathlib import Path
import re
import sqlite3
from urllib.parse import parse_qs
from domain import validate_result
from store import Store, read_json
from result_statistics import frequencies, summary

ROOT=Path(__file__).resolve().parent
DATA_FILE=Path(os.environ.get('LUCKYSCAN_RESULTS_FILE',str(ROOT/'data'/'results.json')))
DATABASE_FILE=os.environ.get('LUCKYSCAN_DATABASE')
log=logging.getLogger('luckyscan50')


def load_results():
    return Store(DATABASE_FILE).all() if DATABASE_FILE else read_json(DATA_FILE)


def application(environ,start_response):
    def reply(code,data):
        body=json.dumps(data,ensure_ascii=False,separators=(',',':')).encode('utf-8')
        statuses={200:'OK',400:'Bad Request',404:'Not Found',405:'Method Not Allowed',503:'Service Unavailable'}
        headers=[('Content-Type','application/json; charset=utf-8'),('Content-Length',str(len(body))),
                 ('Cache-Control','public, max-age=120' if code==200 else 'no-store'),
                 ('X-Content-Type-Options','nosniff')]
        if code==405:
            headers.append(('Allow','GET'))
        start_response(f'{code} {statuses[code]}',headers)
        return [body]
    if environ.get('REQUEST_METHOD')!='GET':
        return reply(405,{'error':'method_not_allowed'})
    path=environ.get('PATH_INFO','/')
    query=parse_qs(environ.get('QUERY_STRING',''),keep_blank_values=True)
    if any(len(values)!=1 for values in query.values()):
        return reply(400,{'error':'duplicate_parameter'})
    params={k:v[0] for k,v in query.items()}
    if path in ('/','/health'):
        return reply(200,{'ok':True,'service':'luckyscan50-results','version':'0.2.0','runtime':'native_wsgi'})
    detail=re.fullmatch(r'/v1/draws/(euromilhoes|milhao)/(\d{3})/(\d{4})',path)
    milhao=re.fullmatch(r'/v1/milhao/(\d{3})/(\d{4})',path)
    allowed=('/v1/draws','/v1/draws/latest','/v1/milhao/latest','/v1/statistics/numbers',
             '/v1/statistics/stars','/v1/statistics/summary','/v1/sync')
    if path not in allowed and not detail and not milhao:
        return reply(404,{'error':'not_found'})
    game='milhao' if path.startswith('/v1/milhao/') else params.get('game','euromilhoes')
    if game not in ('euromilhoes','milhao'):
        return reply(400,{'error':'invalid_game'})
    try:
        limit=int(params.get('limit','30'))
        offset=int(params.get('offset','0'))
        after=int(params.get('after','0'))
        if not 1<=limit<=100 or offset<0 or after<0:
            raise ValueError()
    except ValueError:
        return reply(400,{'error':'invalid_pagination'})
    for key in ('from','to'):
        if key in params:
            try:
                if date.fromisoformat(params[key]).isoformat()!=params[key]:
                    raise ValueError()
            except ValueError:
                return reply(400,{'error':'invalid_date'})
    if params.get('from','')>params.get('to','9999-12-31'):
        return reply(400,{'error':'invalid_date_range'})
    try:
        if path=='/v1/sync' and DATABASE_FILE:
            changes=Store(DATABASE_FILE).changes(after,limit+1)
            more=len(changes)>limit
            changes=changes[:limit]
            for item in changes:
                item['result']=json.loads(item.pop('payload'))
            return reply(200,{'data':changes,'nextCursor':changes[-1]['sequence'] if changes else after,'hasMore':more,'mode':'revisions'})
        rows=load_results()
        rows=[r for r in rows if params.get('from','')<=r['date']<=params.get('to','9999-12-31')]
    except (ValueError,OSError,TypeError,KeyError,sqlite3.Error):
        log.error('Result storage unavailable')
        return reply(503,{'error':'results_unavailable'})
    if path=='/v1/sync':
        # A JSON file has no revision cursor. Explicitly request a full replacement.
        return reply(200,{'data':rows,'mode':'snapshot','nextCursor':None,'hasMore':False})
    if path.startswith('/v1/statistics/'):
        if path.endswith('/summary'):
            return reply(200,summary(rows))
        return reply(200,frequencies(rows,path.rsplit('/',1)[1]))
    if detail or milhao:
        target_game=detail[1] if detail else 'milhao'
        target_id=detail[2]+'/'+detail[3] if detail else milhao[1]+'/'+milhao[2]
        found=next((r for r in rows if r['game']==target_game and r['drawId']==target_id),None)
        return reply(200,found) if found else reply(404,{'error':'draw_not_found'})
    rows=[r for r in rows if r['game']==game]
    if path.endswith('/latest'):
        return reply(200,rows[-1]) if rows else reply(404,{'error':'no_validated_results'})
    rows=list(reversed(rows))
    return reply(200,{'data':rows[offset:offset+limit],'pagination':{'limit':limit,'offset':offset,
                     'total':len(rows),'hasMore':offset+limit<len(rows)}})
