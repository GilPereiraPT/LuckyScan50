import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/wallet_store.dart';
import 'package:luckyscan50/domain/wallet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'wallet_test.dart' show receipt, draw;

void main() {
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

  test(
    'receipt and revision insert roll back together on history failure',
    () async {
      sqfliteFfiInit();
      final store = await WalletStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.db.close);
      await store.db.execute(
        "CREATE TRIGGER fail_history BEFORE INSERT ON history BEGIN SELECT RAISE(ABORT, 'simulated full disk'); END",
      );
      await expectLater(
        store.save(receipt()),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.receipts(), isEmpty);
      expect(await store.db.query('history'), isEmpty);
    },
  );

  test(
    'restore is transactional and preserves receipts on insertion failure',
    () async {
      sqfliteFfiInit();
      final store = await WalletStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.db.close);
      await store.save(receipt());
      await store.db.execute(
        "CREATE TRIGGER fail_restore BEFORE INSERT ON receipts WHEN NEW.id = 'blocked' BEGIN SELECT RAISE(ABORT, 'simulated insert failure'); END",
      );
      await expectLater(
        store.restore([receipt(id: 'new'), receipt(id: 'blocked')]),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.receipts()).map((r) => r.id), ['one']);
      expect(await store.db.query('history'), hasLength(1));
    },
  );

  test(
    'repeated restore keeps amounts, original attachments and history',
    () async {
      sqfliteFfiInit();
      final store = await WalletStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.db.close);
      final existing = Receipt.fromJson({
        ...receipt().toJson(),
        'receivedCents': 12345,
        'imagePath': '/private/existing-image.jpg',
      });
      await store.save(existing);
      final restored = Receipt.fromJson({
        ...receipt().toJson(),
        'costCents': 999,
        'receivedCents': 0,
        'imagePath': '/private/restored-image.jpg',
      });
      await store.restore([restored, receipt(id: 'new')]);
      await store.restore([restored, receipt(id: 'new')]);
      final rows = await store.receipts();
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((r) => r.id == 'one').toJson(),
        existing.toJson(),
      );
      expect(finances(rows, [])['spent'], 1000);
      expect(finances(rows, [])['received'], 12345);
      expect(await store.db.query('history'), hasLength(1));
    },
  );

  test(
    'results replay does not duplicate draws or change receipt spending',
    () async {
      sqfliteFfiInit();
      final store = await WalletStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.db.close);
      final ticket = Receipt.fromJson({
        ...receipt().toJson(),
        'drawIds': ['001/2026'],
      });
      await store.save(ticket);
      await store.saveResults([draw(), draw()]);
      await store.saveResults([draw()]);
      expect(await store.results(), hasLength(1));
      final totals = finances(await store.receipts(), await store.results());
      expect(totals['spent'], 500);
      expect(totals['identified'], 10000);
      expect(await store.db.query('history'), hasLength(1));
    },
  );

  test(
    'results and sync marker roll back together after invalid payload',
    () async {
      sqfliteFfiInit();
      final store = await WalletStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.db.close);
      await store.saveResults([draw()]);
      await store.setSetting('lastSync', 'known-successful-sync');
      await expectLater(
        store.saveResults([
          {...draw(), 'drawId': '002/2026'},
          {...draw(), 'drawId': '003/2026', 'unserializable': Object()},
        ]),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect((await store.results()).single['drawId'], '001/2026');
      expect(await store.setting('lastSync'), 'known-successful-sync');
    },
  );

  test(
    'statistics cache setting leaves wallet, revisions and results intact',
    () async {
      sqfliteFfiInit();
      final store = await WalletStore.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(store.db.close);
      await store.save(receipt());
      await store.saveResults([draw()]);
      await store.setSetting(
        'officialStatisticsCacheV1',
        '{"data":{"drawCount":100}}',
      );
      expect((await store.receipts()).single.toJson(), receipt().toJson());
      expect((await store.results()).single, draw());
      expect(await store.db.query('history'), hasLength(1));
      expect(await store.setting('officialStatisticsCacheV1'), contains('100'));
    },
  );
}
