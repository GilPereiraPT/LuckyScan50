import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/wallet.dart';
import 'package:luckyscan50/data/backup.dart';
import 'package:luckyscan50/data/results_client.dart';
import 'package:luckyscan50/data/wallet_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Receipt receipt({String id = 'one'}) => Receipt(
  id: id,
  createdAt: '2026-01-01',
  source: 'manual',
  code: 'ABC',
  costCents: 500,
  lines: [
    BetLine([1, 2, 3, 4, 5], [1, 2]),
  ],
  drawIds: ['001/2026', '002/2026'],
);
Map<String, dynamic> draw() => {
  'game': 'euromilhoes',
  'drawId': '001/2026',
  'status': 'complete',
  'numbers': [1, 2, 3, 4, 5],
  'stars': [1, 2],
  'tiers': List.generate(
    13,
    (i) => <String, dynamic>{'amountCents': i == 0 ? 10000 : 100},
  ),
};

void main() {
  test('exact cents, no floating point parsing', () {
    expect(cents('2,50'), 250);
    expect(cents('0.01'), 1);
    expect(cents('12'), 1200);
    for (final s in ['1.001', '-1', 'NaN', '2e3']) {
      expect(() => cents(s), throwsFormatException);
    }
  });
  test('multi-draw receipt remains pending and costs only once', () {
    final r = receipt();
    final v = verify(r, [draw()]);
    expect(v.knownCents, 10000);
    expect(v.pendingDraws, 1);
    expect(v.complete, isFalse);
    expect(finances([r], [draw()])['spent'], 500);
  });
  test('unknown prizes are never zero or marked definitive', () {
    final d = draw();
    (d['tiers'] as List)[0]['amountCents'] = null;
    final v = verify(receipt(), [d]);
    expect(v.unknownPrizes, 1);
    expect(v.knownCents, 0);
    expect(v.complete, isFalse);
  });
  test('partial results do not settle a bet', () {
    final v = verify(receipt(), [
      {...draw(), 'status': 'numbers_confirmed'},
    ]);
    expect(v.pendingDraws, 2);
    expect(v.knownCents, 0);
  });
  test('same numbers on genuine separate receipts are allowed', () {
    expect(finances([receipt(), receipt(id: 'two')], [])['spent'], 1000);
  });
  test('encrypted backup round trip and corruption detection', () async {
    final text = await WalletBackup.encrypt([
      receipt(),
    ], 'a long test password');
    expect(text.contains('ABC'), isFalse);
    final restored = await WalletBackup.decrypt(text, 'a long test password');
    expect(restored.single.toJson(), receipt().toJson());
    await expectLater(
      WalletBackup.decrypt(text, 'wrong password'),
      throwsFormatException,
    );
    await expectLater(
      WalletBackup.decrypt('$text!', 'a long test password'),
      throwsFormatException,
    );
  });
  test('legacy API sync stops after one page per game', () async {
    int calls = 0;
    final client = ResultsClient(
      client: MockClient((request) async {
        calls++;
        return http.Response('{"data":[]}', 200);
      }),
    );
    expect(await client.fetch(), isEmpty);
    expect(calls, 2);
    client.close();
  });
  test(
    'SQLite persists receipts and merge restores without duplicates',
    () async {
      sqfliteFfiInit();
      final store = await WalletStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.db.close);
      await store.save(receipt());
      expect((await store.receipts()).single.costCents, 500);
      expect(await store.duplicateCode('ABC', 'new'), isTrue);
      await store.restore([receipt(), receipt(id: 'two')]);
      expect((await store.receipts()).length, 2);
      await store.saveResults([draw()]);
      expect((await store.results()).length, 1);
      await store.erase();
      expect(await store.receipts(), isEmpty);
      expect(await store.results(), isEmpty);
    },
  );
  test('backup restores photographs to a new private directory', () async {
    final temp = await Directory.systemTemp.createTemp('luckyscan-backup-');
    addTearDown(() => temp.delete(recursive: true));
    final image = File('${temp.path}/original.jpg');
    await image.writeAsBytes([1, 2, 3, 4]);
    final r = Receipt.fromJson({
      ...receipt().toJson(),
      'imagePath': image.path,
    });
    final text = await WalletBackup.encrypt([r], 'a long test password');
    final restored = await WalletBackup.decrypt(
      text,
      'a long test password',
      imageDirectory: '${temp.path}/new-device',
    );
    expect(await File(restored.single.imagePath!).readAsBytes(), [1, 2, 3, 4]);
    expect(restored.single.imagePath, isNot(image.path));
  });
  test('duplicate Milhao codes cannot double-count a prize', () {
    expect(
      () => Receipt.fromJson({
        ...receipt().toJson(),
        'milhaoDrawIds': ['001/2026'],
        'milhaoCodes': ['ABC 12345', 'ABC12345'],
      }),
      throwsFormatException,
    );
  });
}
