import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/wallet_store.dart';
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
}
