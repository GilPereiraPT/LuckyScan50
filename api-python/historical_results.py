"""Bounded official Euromilhoes history import; public form only, stdlib only."""
from contextlib import closing
from datetime import datetime, timedelta
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import tempfile
import time
from urllib.parse import urlencode
from urllib.request import Request, build_opener, HTTPCookieProcessor
from http.cookiejar import CookieJar
from zoneinfo import ZoneInfo

import official_cartaz as official
import rss_import as rss
from store import Store


def catalogue(payload):
    match = re.search(br'charset\s*=\s*[\'"]?([A-Za-z0-9_-]+)', payload[:8192], re.I)
    text = payload.decode(match[1].decode() if match else 'utf-8-sig')
    document = official.Document()
    document.feed(text)
    document.close()
    forms = [n for n in document.root.find('form')
             if n.attrs.get('id') == 'frmContestSelection']
    if len(forms) != 1 or forms[0].attrs.get('method', '').lower() != 'post':
        raise ValueError('Official history form unavailable')
    if forms[0].attrs.get('action') not in (official.URL, '/web/SCCartazResult/euroMilhoes'):
        raise ValueError('Unexpected official form destination')
    selects = [n for n in forms[0].find('select') if n.attrs.get('name') == 'selectContest']
    if len(selects) != 1:
        raise ValueError('Official history selector unavailable')
    result = []
    for option in selects[0].find('option'):
        identity = re.fullmatch(r'(\d{3}/\d{4})\s*-\s*.+', option.text())
        value = option.attrs.get('value', '')
        if not identity or not re.fullmatch(r'\d+(?:\.0)?', value):
            raise ValueError('Invalid official history option')
        result.append((identity[1], value))
    if not result or len(result) > 60 or len({i for i, _ in result}) != len(result):
        raise ValueError('Empty, duplicate or excessive official history catalogue')
    return result


class OfficialSession:
    def __init__(self):
        self.opener = build_opener(rss.NoRedirect(), HTTPCookieProcessor(CookieJar()))

    def fetch(self, selection=None):
        body = None if selection is None else urlencode({'selectContest': selection}).encode()
        request = Request(official.URL, data=body, headers={
            'User-Agent': 'LuckyScan50-history/1.0', 'Accept': 'text/html',
            'Content-Type': 'application/x-www-form-urlencoded'})
        with self.opener.open(request, timeout=20) as response:
            if response.status != 200 or response.url != official.URL:
                raise ValueError('Unexpected official history HTTP response')
            payload = response.read(official.MAX_BYTES + 1)
            if len(payload) > official.MAX_BYTES:
                raise ValueError('Official history response too large')
            return payload


def collect(today, fetch, pause=time.sleep):
    """No database writes; reject a server that ignores the selected contest."""
    landing = fetch()
    entries = catalogue(landing)
    latest, _ = official.parse(landing)
    cutoff = today - timedelta(days=89)
    selected, all_dates, seen = [], [], set()
    for identity, selection in entries:
        if identity == latest['drawId']:
            payload, row = landing, latest
        else:
            pause(1)
            payload = fetch(selection)
            row, _ = official.parse(payload)
        if row['drawId'] != identity:
            raise ValueError('Official server did not return requested draw ' + identity)
        day = datetime.strptime(row['date'], '%Y-%m-%d').date()
        if day > today or row['date'] in seen:
            raise ValueError('Duplicate or future official history date')
        seen.add(row['date'])
        all_dates.append(day)
        if cutoff <= day <= today:
            selected.append((row, payload))
    if not selected:
        raise ValueError('No official draws available in the requested 90-day window')
    return {
        'from': cutoff.isoformat(), 'to': today.isoformat(),
        'catalogueCount': len(entries), 'selectedCount': len(selected),
        'oldestAvailable': min(all_dates).isoformat(),
        'latestAvailable': max(all_dates).isoformat(),
        'startBoundaryCovered': min(all_dates) <= cutoff,
        'completeHistoryAudited': False,
    }, sorted(selected, key=lambda item: item[0]['date'])


def apply_batch(store, items, report, apply=False):
    """Validate against a SQLite copy, refuse all conflicts, then commit one batch."""
    store.all()
    with store.path.with_suffix(store.path.suffix + '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with tempfile.TemporaryDirectory(prefix='.history-', dir=store.path.parent) as directory:
            stage = Store(Path(directory) / 'staging.sqlite3')
            with closing(store.connect(readonly=True)) as original, closing(stage.connect()) as target:
                original.backup(target)
            before = stage.all()
            rss.initialize(stage)
            changes, conflicts, partial = [], [], []
            for row, payload in items:
                result = official.reconcile(stage, payload)
                if result['conflicts']:
                    conflicts.append(row['drawId'])
                if result['changed']:
                    changes.append(row)
                if row['status'] != 'complete':
                    partial.append(row['drawId'])
            output = {**report, 'game': 'euromilhoes', 'dryRun': not apply,
                      'changed': 0, 'wouldChange': len(changes),
                      'conflicts': conflicts, 'partialDraws': partial}
            if conflicts:
                output['status'] = 'conflicts_no_import'
                return output
            if not apply:
                output['status'] = 'preview'
                return output
            # Preserve raw public responses and their hashes for provenance.
            audit = store.path.parent / 'history-imports'
            audit.mkdir(exist_ok=True, mode=0o700)
            stamp = datetime.now(ZoneInfo('Europe/Lisbon')).strftime('%Y%m%d-%H%M%S-%f')
            folder = audit / stamp
            folder.mkdir(mode=0o700)
            for row, payload in items:
                name = row['drawId'].replace('/', '-') + '.html'
                target = folder / name
                target.write_bytes(payload)
                target.chmod(0o600)
            backup = folder / 'before.sqlite3'
            with closing(store.connect(readonly=True)) as original, closing(sqlite3.connect(backup)) as target:
                original.backup(target)
            backup.chmod(0o600)
            official.initialize(store)
            with closing(store.connect()) as db, db:
                db.execute('BEGIN IMMEDIATE')
                current = [json.loads(r[0]) for r in db.execute(
                    'SELECT payload FROM draws ORDER BY draw_date,game,draw_id')]
                if current != before:
                    raise ValueError('Database changed during preview; nothing imported, retry later')
                if changes:
                    store.import_rows(changes, source='official-history-90-days', _connection=db)
                for row, payload in items:
                    official.record(store, payload, 'accepted' if row['status'] == 'complete' else 'pending',
                                    ['history_90_days'], row, connection=db)
            output.update(status='imported', changed=len(changes),
                          unchanged=len(items) - len(changes), backup=str(backup))
            manifest = {**output, 'sourceUrl': official.URL,
                        'snapshots': {row['drawId']: hashlib.sha256(payload).hexdigest()
                                      for row, payload in items}}
            target = folder / 'manifest.json'
            target.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
            target.chmod(0o600)
            return output


def run(apply=False, today=None, fetch=None):
    path = os.environ.get('LUCKYSCAN_DATABASE', '')
    if not path or not Path(path).is_absolute() or not Path(path).is_file():
        raise ValueError('LUCKYSCAN_DATABASE must point to the existing results SQLite database')
    today = today or datetime.now(ZoneInfo('Europe/Lisbon')).date()
    report, items = collect(today, fetch or OfficialSession().fetch)
    return apply_batch(Store(path), items, report, apply)
