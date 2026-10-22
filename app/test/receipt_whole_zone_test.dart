import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_whole_zone.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

void main() {
  test(
    'one whole image pass preserves five bets and original metadata',
    () async {
      var calls = 0;
      final result = await readReceiptWholeZone(
        initial: const OcrFrame('', []),
        metadata: const ScannedReceipt(
          bets: [],
          rows: [],
          warnings: [],
          expectedLines: 5,
          game: 'euromilhoes',
          drawId: '081/2026',
          amount: '11.00',
        ),
        width: 1440,
        height: 1920,
        recognizeCrop: (crop, scale) async {
          calls++;
          expect(scale, 2);
          expect(crop.box.toJson(), {
            'left': 0.0,
            'top': 0.0,
            'right': 1440.0,
            'bottom': 1920.0,
          });
          return const OcrFrame(
            '1.N 06 20 29 32 48\nE 04 06\n'
            '2.N 05 17 36 47 49\nE 05 11\n'
            '3.N 22 26 43 45 47\nE 03 09\n'
            '4.N 06 10 13 35 44\nE 02 10\n'
            '5.N 02 06 13 20 32\nE 03 10',
            [],
          );
        },
      );
      expect(calls, 1);
      expect(result.receipt.bets.where((b) => b.complete).length, 5);
      expect(result.receipt.bets[2].numbers, [22, 26, 43, 45, 47]);
      expect(result.receipt.bets[2].stars, [3, 9]);
      expect(result.receipt.drawId, '081/2026');
      expect(result.passes.single.id, 'whole-image@2x');
    },
  );
}
