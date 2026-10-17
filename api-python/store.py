"""Transactional SQLite imports and immutable revision history; JSON fallback."""
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sqlite3
from domain import validate_result


def read_json(path):
    try:
        rows = json.loads(Path(path).read_text(encoding='utf-8'))
    except FileNotFoundError:
        return []
    if not isinstance(rows, list):
        raise ValueError('Expected a JSON array')
    seen = set()
    for row in rows:
        validate_result(row)
        key = (row['game'],row['drawId'])
        if key in seen:
            raise ValueError('Duplicate draw in input')
        seen.add(key)
    return sorted(rows, key=lambda r:(r['date'],r['game'],r['drawId']))


class Store:
    def __init__(self, path):
        self.path = Path(path)

    def connect(self, readonly=False):
        if readonly:
            connection = sqlite3.connect(self.path.resolve().as_uri()+'?mode=ro', uri=True, timeout=10)
        else:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute('PRAGMA foreign_keys=ON')
        return connection

    def migrate(self):
        with closing(self.connect()) as connection:
            version = connection.execute('PRAGMA user_version').fetchone()[0]
            if version > 1:
                raise ValueError('Unsupported database version')
            if version == 0:
                sql = (Path(__file__).parent/'migrations'/'001_initial.sql').read_text()
                connection.executescript('BEGIN IMMEDIATE;\n'+sql+'\nCOMMIT;')

    def all(self):
        with closing(self.connect(readonly=True)) as connection:
            rows = [json.loads(row[0]) for row in connection.execute(
                'SELECT payload FROM draws ORDER BY draw_date,game,draw_id')]
        for row in rows:
            validate_result(row)
        return rows

    def changes(self, after=0, limit=100):
        with closing(self.connect(readonly=True)) as connection:
            return [dict(row) for row in connection.execute(
                'SELECT r.sequence,r.revision,r.imported_at AS updatedAt,d.game,d.draw_id AS drawId,'
                'r.payload FROM revisions r JOIN draws d ON d.id=r.draw_id '
                'WHERE sequence>? ORDER BY sequence LIMIT ?', (after,limit))]

    def import_rows(self, rows, source='manual'):
        if not isinstance(rows,list) or not rows:
            raise ValueError('Expected a non-empty array')
        seen = set()
        for row in rows:
            validate_result(row)
            key=(row['game'],row['drawId'])
            if key in seen:
                raise ValueError('Duplicate draw in batch')
            seen.add(key)
        self.migrate()
        now=datetime.now(timezone.utc).isoformat()
        changed=unchanged=0
        with closing(self.connect()) as connection, connection:
            connection.execute('BEGIN IMMEDIATE')
            for row in rows:
                payload=json.dumps(row,sort_keys=True,ensure_ascii=False,separators=(',',':'))
                # Polling timestamps alone must not create a new revision.
                content={k:v for k,v in row.items() if k!='retrievedAt'}
                fingerprint=hashlib.sha256(json.dumps(content,sort_keys=True,separators=(',',':')).encode()).hexdigest()
                old=connection.execute('SELECT id,revision,fingerprint,payload FROM draws WHERE game=? AND draw_id=?',
                                       (row['game'],row['drawId'])).fetchone()
                if old and old['fingerprint']==fingerprint:
                    unchanged+=1
                    continue
                if old and json.loads(old['payload'])['status']=='complete' and row['status']!='complete':
                    raise ValueError('Cannot downgrade a complete draw')
                revision=old['revision']+1 if old else 1
                connection.execute('INSERT INTO draws(game,draw_id,draw_date,status,source_url,retrieved_at,updated_at,revision,payload,fingerprint) '
                    'VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(game,draw_id) DO UPDATE SET '
                    'draw_date=excluded.draw_date,status=excluded.status,source_url=excluded.source_url,'
                    'retrieved_at=excluded.retrieved_at,updated_at=excluded.updated_at,revision=excluded.revision,'
                    'payload=excluded.payload,fingerprint=excluded.fingerprint',
                    (row['game'],row['drawId'],row['date'],row['status'],row['sourceUrl'],row['retrievedAt'],now,revision,payload,fingerprint))
                draw_id=connection.execute('SELECT id FROM draws WHERE game=? AND draw_id=?',(row['game'],row['drawId'])).fetchone()[0]
                connection.execute('INSERT INTO revisions(draw_id,revision,payload,fingerprint,imported_at) VALUES(?,?,?,?,?)',
                                   (draw_id,revision,payload,fingerprint,now))
                for table in ('draw_numbers','prize_tiers','milhao_results'):
                    connection.execute('DELETE FROM '+table+' WHERE draw_id=?',(draw_id,))
                if row['game']=='euromilhoes':
                    for kind in ('numbers','stars'):
                        connection.executemany('INSERT INTO draw_numbers VALUES(?,?,?,?)',
                            [(draw_id,kind,i,n) for i,n in enumerate(row[kind])])
                    connection.executemany('INSERT INTO prize_tiers VALUES(?,?,?,?,?,?,?)',
                        [(draw_id,t['tier'],t['main'],t['stars'],t['amountCents'],t['winnersPortugal'],t['winnersTotal']) for t in row['tiers']])
                else:
                    connection.execute('INSERT INTO milhao_results VALUES(?,?,?)',
                                       (draw_id,row['winningCode'],row.get('amountCents')))
                changed+=1
            connection.execute('INSERT INTO import_log(imported_at,source,changed,unchanged) VALUES(?,?,?,?)',
                               (now,source,changed,unchanged))
        return {'changed':changed,'unchanged':unchanged}

    def import_legacy(self, path):
        path=Path(path)
        rows=read_json(path)
        # Preserve the exact bytes before the first database write. Never overwrite a backup.
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        backup=path.with_name(path.name+'.'+digest[:16]+'.bak')
        try:
            with backup.open('xb') as output:
                output.write(path.read_bytes())
        except FileExistsError:
            if hashlib.sha256(backup.read_bytes()).hexdigest()!=digest:
                raise ValueError('Backup integrity mismatch')
        return self.import_rows(rows,source='legacy-json') if rows else {'changed':0,'unchanged':0}
