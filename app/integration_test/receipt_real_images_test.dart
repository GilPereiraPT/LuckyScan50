import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:luckyscan50/data/receipt_scanner.dart';
import 'package:luckyscan50/main.dart';

// Ground truth is used ONLY to score the real outputs, never as OCR input.
const expected = [
  '06 20 29 32 48 + 04 06',
  '05 17 36 47 49 + 05 11',
  '22 26 43 45 47 + 03 09',
  '06 10 13 35 44 + 02 10',
  '02 06 13 20 32 + 03 10',
];
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Android ML Kit and real form: both original orientations', (
    tester,
  ) async {
    if (!Platform.isAndroid) {
      fail('This acceptance test requires an Android device.');
    }
    final evidence = <Map<String, dynamic>>[];
    for (final name in ['vertical.jpg', 'rotated.jpg']) {
      // Missing photographs FAIL this explicit acceptance run; never skip it green.
      final bytes = await rootBundle.load('assets/private_receipts/$name');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/ocr-acceptance-$name');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final scan = await tester.runAsync(() => scanReceiptFile(file.path));
      expect(scan, isNotNull);
      final actual = scan!.receipt.lines;
      final perBet = <Map<String, dynamic>>[];
      for (var i = 0; i < 5; i++) {
        final bet = scan.receipt.bets.where((b) => b.index == i + 1);
        final wanted = expected[i].split(' + ');
        final numbers = wanted[0].split(' ').map(int.parse).toList();
        final stars = wanted[1].split(' ').map(int.parse).toList();
        final got = bet.isEmpty ? null : bet.single;
        final n = List.generate(
          5,
          (j) =>
              got != null &&
                  got.numbers.length > j &&
                  got.numbers[j] == numbers[j]
              ? 1
              : 0,
        ).fold(0, (a, b) => a + b);
        final e = List.generate(
          2,
          (j) => got != null && got.stars.length > j && got.stars[j] == stars[j]
              ? 1
              : 0,
        ).fold(0, (a, b) => a + b);
        perBet.add({
          'index': i + 1,
          'correctNumbers': n,
          'correctStars': e,
          'completeCorrect': n == 5 && e == 2,
        });
      }
      evidence.add({
        'orientation': name,
        'android': true,
        'build': buildSha,
        'beforeComplete': scan.initialReceipt?.lines.length,
        'afterComplete': actual.length,
        'initialOcrMs': scan.ocrMs,
        'totalProcessingMs': scan.ocrMs + scan.parseMs,
        'recoveryMs': scan.multiPass?.elapsedMs,
        'passes': scan.multiPass?.passes.length,
        'perBet': perBet,
      });
      binding.reportData = {'receiptOcr': evidence};
      expect(
        actual,
        expected,
        reason: 'Real OCR acceptance failed: ${jsonEncode(evidence.last)}',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            receiptScannerProvider.overrideWithValue((_) async => scan),
          ],
          child: const MaterialApp(home: AddReceipt()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importar imagem'));
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Chaves — uma por linha',
      );
      await tester.scrollUntilVisible(
        field,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        expected.join('\n'),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await file.delete();
    }
    binding.reportData = {'receiptOcr': evidence, 'accepted': true};
  });
}
