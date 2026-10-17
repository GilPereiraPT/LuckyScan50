#!/usr/bin/env python3
"""Run test-only Flutter dependencies in a disposable app copy, never the APK source.

host: the real SQLite FFI persistence regression.
android: real ML Kit + form acceptance; requires Android and both private photos.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['host', 'android'])
    parser.add_argument('--resolve-only', action='store_true', help='Resolve the QA lockfile without running tests')
    parser.add_argument('--device')
    parser.add_argument('--photos', type=Path)
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    if args.mode == 'android' and not args.resolve_only:
        if not args.device or not args.photos:
            parser.error('android requires --device and --photos')
        for name in ['vertical.jpg', 'rotated.jpg']:
            if not (args.photos / name).is_file():
                parser.error(f'Missing private photograph: {name}')
    with tempfile.TemporaryDirectory(prefix='luckyscan-qa-', dir=os.environ.get('TMPDIR', '/tmp')) as directory:
        app = Path(directory) / 'app'
        shutil.copytree(ROOT / 'app', app, ignore=shutil.ignore_patterns(
            'build', '.dart_tool', '.gradle', '.kotlin', '.cxx',
            '.flutter-plugins-dependencies', 'assets', '*.log'))
        spec = (app / 'pubspec.yaml').read_text()
        extra = '  sqflite_common_ffi: ^2.3.6\n'
        if args.mode == 'android':
            extra = '  integration_test:\n    sdk: flutter\n'
            spec += '  assets:\n    - assets/private_receipts/\n'
            shutil.copytree(ROOT / 'qa/android/integration_test', app / 'integration_test', dirs_exist_ok=True)
            shutil.copytree(ROOT / 'qa/android/test_driver', app / 'test_driver', dirs_exist_ok=True)
            target = app / 'assets/private_receipts'
            target.mkdir(parents=True)
            if not args.resolve_only:
                for name in ['vertical.jpg', 'rotated.jpg']:
                    shutil.copy2(args.photos / name, target / name)
        else:
            shutil.copy2(ROOT / 'qa/host/wallet_database_test.dart', app / 'test/wallet_database_test.dart')
        (app / 'pubspec.yaml').write_text(spec.replace('dev_dependencies:\n', 'dev_dependencies:\n' + extra))
        lock = ROOT / f'qa/{args.mode}/pubspec.lock'
        if lock.exists():
            shutil.copy2(lock, app / 'pubspec.lock')
        subprocess.run(['flutter', 'pub', 'get'] + (['--enforce-lockfile'] if lock.exists() else []), cwd=app, check=True)
        if not lock.exists():
            shutil.copy2(app / 'pubspec.lock', lock)
        if args.resolve_only:
            print('QA dependencies resolved; no tests executed.')
            return
        command = ['flutter', 'test', 'test/wallet_database_test.dart', '--reporter', 'expanded']
        if args.mode == 'android':
            command = ['flutter', 'drive', '--driver=test_driver/receipt_driver.dart',
                       '--target=integration_test/receipt_real_images_test.dart', '-d', args.device]
        try:
            subprocess.run(command, cwd=app, check=True)
        finally:
            evidence = app / 'build/receipt-real-evidence.json'
            if args.evidence and evidence.exists():
                args.evidence.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(evidence, args.evidence)


if __name__ == '__main__':
    main()
