import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_numbered_bets.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';
import 'package:luckyscan50/domain/receipt_cells.dart';

ReceiptToken t(String text, double x, double y, {double width = 16}) =>
    ReceiptToken(text, x, y, 14, width: width);

Future<MultiPassResult> read(RecognizeBetCrop crop) async =>
    (await recoverNumberedBets(
      initial: OcrFrame('', [
        t('1.N', 30, 70, width: 24),
        t('0112233445', 130, 70, width: 160),
        t('E', 38, 90, width: 8),
        t('0102', 82, 90, width: 64),
      ]),
      metadata: const ScannedReceipt(
        bets: [],
        rows: [],
        warnings: [],
        expectedLines: 1,
        game: 'euromilhoes',
        drawId: '081/2026',
      ),
      width: 400,
      height: 2000,
      recognizeCrop: crop,
    ))!;

void main() {
  test('line normalization retains evidence and metadata', () async {
    final r = await read(
      (c, s) async =>
          OcrFrame(c.kind == 'N' ? 'O7 l5 16 22 3S .' : '04 .06', const []),
    );
    expect(r.receipt.lines, ['07 15 16 22 35 + 04 06']);
    expect(r.receipt.drawId, '081/2026');
    expect(
      r.evidence.first.acceptedValues
          .where((v) => v.correction != null)
          .map((v) => v.raw),
      ['O7', 'l5', '3S'],
    );
  });
  test('ambiguous pipe needs matching second pass', () async {
    final r = await read(
      (c, s) async => OcrFrame(
        c.kind == 'E'
            ? '04 06'
            : s == 1
            ? '07 15 16 22 3|'
            : '07 15 16 22 32',
        const [],
      ),
    );
    expect(r.receipt.lines, isEmpty);
  });
  test('ambiguous pipe can be corroborated', () async {
    final r = await read(
      (c, s) async => OcrFrame(
        c.kind == 'E'
            ? '04 06'
            : s == 1
            ? '07 15 16 22 3|'
            : '07 15 16 22 31',
        const [],
      ),
    );
    expect(r.receipt.lines, ['07 15 16 22 31 + 04 06']);
  });
  test('cell normalization retains range and raw evidence', () {
    expect(parseNumericCell('l5', 'N').value, 15);
    expect(parseNumericCell('3|', 'N').correction, '3|→31');
    expect(parseNumericCell('l5', 'E').value, isNull);
    expect(parseNumericCell('X5', 'N').value, isNull);
    expect(parseNumericCell('l5', 'metadata').value, isNull);
  });
}
