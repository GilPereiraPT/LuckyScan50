import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../domain/wallet.dart';

class WalletStore {
  WalletStore(this.db);
  final Database db;
  static Future<WalletStore> open(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final database = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE receipts (id TEXT PRIMARY KEY, code TEXT NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute('CREATE INDEX receipt_code ON receipts(code)');
          await db.execute(
            'CREATE TABLE results (game TEXT, draw_id TEXT, payload TEXT NOT NULL, PRIMARY KEY(game,draw_id))',
          );
          await db.execute(
            'CREATE TABLE history (sequence INTEGER PRIMARY KEY AUTOINCREMENT, receipt_id TEXT, changed_at TEXT, payload TEXT)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY,value TEXT NOT NULL)',
          );
        },
      ),
    );
    return WalletStore(database);
  }

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Receipt>> receipts() async =>
      (await db.query('receipts', orderBy: 'rowid DESC'))
          .map(
            (r) => Receipt.fromJson(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();
  Future<List<Map<String, dynamic>>> results() async =>
      (await db.query('results'))
          .map(
            (r) => jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          )
          .toList();
  Future<bool> duplicateCode(String code, String id) async =>
      code.isNotEmpty &&
      (await db.query(
        'receipts',
        where: 'code=? AND id<>?',
        whereArgs: [code, id],
      )).isNotEmpty;
  Future<void> save(Receipt receipt) async => db.transaction((txn) async {
    final payload = jsonEncode(receipt.toJson());
    await txn.insert('receipts', {
      'id': receipt.id,
      'code': receipt.code,
      'payload': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert('history', {
      'receipt_id': receipt.id,
      'changed_at': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    });
  });
  Future<void> saveResults(List<Map<String, dynamic>> rows) async =>
      db.transaction((txn) async {
        for (final row in rows) {
          await txn.insert('results', {
            'game': row['game'],
            'draw_id': row['drawId'],
            'payload': jsonEncode(row),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await txn.insert('settings', {
          'key': 'lastSync',
          'value': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
  Future<void> delete(String id) async => db.transaction((txn) async {
    await txn.delete('receipts', where: 'id=?', whereArgs: [id]);
    await txn.delete('history', where: 'receipt_id=?', whereArgs: [id]);
  });
  Future<void> erase() async => db.transaction((txn) async {
    for (final table in ['receipts', 'results', 'history', 'settings']) {
      await txn.delete(table);
    }
  });
  Future<void> restore(List<Receipt> receipts) async => db.transaction((
    txn,
  ) async {
    // Merge by stable receipt ID; never erase existing receipts during restore.
    for (final r in receipts) {
      await txn.insert('receipts', {
        'id': r.id,
        'code': r.code,
        'payload': jsonEncode(r.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  });
}
