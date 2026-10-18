import 'dart:io';
import '../app/lib/data/backup.dart';
import '../app/lib/domain/wallet.dart';

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp(
    'luckyscan-backup-isolated-',
  );
  try {
    final image = File('${temp.path}/synthetic-only.jpg');
    await image.writeAsString('Synthetic bytes; no user photograph.');
    final receipt = Receipt(
      id: 'isolated-audit',
      createdAt: '2026-10-18T12:00:00Z',
      source: 'physical',
      code: '',
      costCents: 250,
      lines: [
        BetLine([1, 2, 3, 4, 5], [1, 2]),
      ],
      drawIds: ['001/2026'],
      imagePath: image.path,
    );
    final encrypted = await WalletBackup.encrypt([
      receipt,
    ], 'synthetic-audit-password');
    final output = '${temp.path}/restored';
    final first = await WalletBackup.decrypt(
      encrypted,
      'synthetic-audit-password',
      imageDirectory: output,
    );
    final second = await WalletBackup.decrypt(
      encrypted,
      'synthetic-audit-password',
      imageDirectory: output,
    );
    print('Restore receipt IDs equal: ${first.single.id == second.single.id}');
    print(
      'Restored image paths equal: ${first.single.imagePath == second.single.imagePath}',
    );
    print(
      'Images written for one repeated receipt: ${await Directory(output).list().length}',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}
