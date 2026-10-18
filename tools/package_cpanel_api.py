"""Build a cPanel ZIP with modules at its root; exclude data and private config."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def build(destination):
    files = {}
    api = ROOT / 'api-python'
    for path in sorted(api.glob('*.py')):
        if not path.name.startswith('test_'):
            files[path.name] = path.read_bytes()
    for name in ('requirements.txt', 'rss-collector.example.json', 'verified-draw-dates.example.json'):
        files[name] = (api / name).read_bytes()
    files['README.md'] = (api / 'README.md').read_text().replace('../docs/', 'documentacao/').encode()
    for path in sorted((api / 'migrations').glob('*.sql')):
        files['migrations/' + path.name] = path.read_bytes()
    for path in sorted(api.glob('test_*.py')):
        files['validacao/api-python/' + path.name] = path.read_bytes()
    for path in sorted((api / 'fixtures').rglob('*')):
        if path.is_file():
            files['validacao/api-python/fixtures/' + path.relative_to(api / 'fixtures').as_posix()] = path.read_bytes()
    fixture = 'euromilhoes-083-2026.json'
    files['validacao/backend/fixtures/' + fixture] = (ROOT / 'backend/fixtures' / fixture).read_bytes()
    for name in ('rss-cron-cpanel.md', 'rss-integration.md', 'historical-results-sources.md',
                 'results-api.md', 'official-results-cpanel.md', 'validation/rss-source-audit-20261017.json'):
        files['documentacao/' + name] = (ROOT / 'docs' / name).read_bytes()
    files['INSTALAR_RSS.md'] = (ROOT / 'docs/rss-cron-cpanel.md').read_text().replace(
        '(historical-results-sources.md)', '(documentacao/historical-results-sources.md)').replace(
        '(official-results-cpanel.md)', '(documentacao/official-results-cpanel.md)').encode()
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    files['build-info.json'] = (json.dumps({'commit': commit, 'createdAt': datetime.now(timezone.utc).isoformat(),
        'python': '3.12', 'remoteCollectionEnabledByDefault': False,
        'containsProductionData': False}, indent=2) + '\n').encode()
    manifest = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}
    files['SHA256.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'x', zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError('ZIP CRC validation failed')
        for name, digest in manifest.items():
            if hashlib.sha256(archive.read(name)).hexdigest() != digest:
                raise ValueError('ZIP content checksum mismatch')
    return {'path': str(destination), 'bytes': destination.stat().st_size,
            'sha256': hashlib.sha256(destination.read_bytes()).hexdigest(), 'files': len(files), 'commit': commit}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    print(json.dumps(build(parser.parse_args().output), indent=2))
