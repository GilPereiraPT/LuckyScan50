import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_numbered_bets.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

ReceiptToken t(String text, double x, double y, {double width = 16}) =>
    ReceiptToken(text, x, y, 14, width: width);

List<ReceiptToken> row(
  int index,
  double y, {
  String numbers = '0715162235',
  String stars = '0406',
  bool split = false,
  bool embedded = false,
}) {
  if (embedded) {
    return [
      t(
        '$index.N$numbers',
        20 + (index.toString().length + 2 + numbers.length) * 4,
        y,
        width: (index.toString().length + 2 + numbers.length) * 8,
      ),
      t(
        'E$stars',
        36 + (1 + stars.length) * 4,
        y + 20,
        width: (1 + stars.length) * 8,
      ),
    ];
  }
  return [
    if (split) ...[
      t('$index.', 25, y, width: 8),
      t('N', 38, y, width: 8),
    ] else
      t('$index.N', 30, y, width: 24),
    t(numbers, 130, y, width: 160),
    t('E', 38, y + 20, width: 8),
    t(stars, 82, y + 20, width: 64),
  ];
}

ScannedReceipt metadata(int count) => ScannedReceipt(
  bets: const [],
  rows: const ['metadados originais'],
  warnings: const [],
  expectedLines: count,
  game: 'euromilhoes',
  code: '782-00837480-199',
  drawDate: '2026-10-16',
  drawId: '083/2026',
  amount: '12,50',
  hasMilhao: true,
  milhaoCodes: const ['ABC 00001'],
);

Future<MultiPassResult> read(
  List<ReceiptToken> tokens, {
  int count = 1,
  List<CropBox> rules = const [],
  RecognizeBetCrop? crop,
}) async => (await recoverNumberedBets(
  initial: OcrFrame('texto global fora de ordem', tokens),
  metadata: metadata(count),
  width: 400,
  height: 2000,
  rules: rules,
  recognizeCrop: crop ?? (_, _) async => const OcrFrame('', []),
))!;

void main() {
  test(
    'numbered N/E pairs are primary, preserve all metadata and need no crop',
    () async {
      final result = await read(
        [...row(1, 70), ...row(2, 140, numbers: '0112233445', stars: '0209')],
        count: 2,
        crop: (_, _) => throw StateError('Complete rows must not be re-read'),
      );
      expect(result.receipt.lines, [
        '07 15 16 22 35 + 04 06',
        '01 12 23 34 45 + 02 09',
      ]);
      expect(result.receipt.strategy, 'numbered-n-e');
      expect(result.passes, isEmpty);
      expect(result.receipt.code, metadata(2).code);
      expect(result.receipt.amount, '12,50');
      expect(result.receipt.drawDate, '2026-10-16');
      expect(result.receipt.drawId, '083/2026');
      expect(result.receipt.milhaoCodes, ['ABC 00001']);
      expect(result.evidence.first.acceptedValues, hasLength(7));
      expect(result.evidence.first.acceptedValues.first.raw, '07');
    },
  );

  test(
    'merged markers and ten/four digits are split without guessing values',
    () async {
      final result = await read(row(1, 70, embedded: true));
      expect(result.receipt.lines, ['07 15 16 22 35 + 04 06']);
    },
  );

  test('split index and N are associated geometrically', () async {
    final result = await read(row(1, 70, split: true));
    expect(result.receipt.lines, ['07 15 16 22 35 + 04 06']);
  });

  test(
    'separators bound the betting block and exclude footer lookalikes',
    () async {
      final result = await read([
        t('================', 180, 45, width: 350),
        ...row(1, 70),
        t('================', 180, 115, width: 350),
        ...row(2, 160),
        t('TOTAL A PAGAR 12,50', 160, 220, width: 250),
      ]);
      expect(result.receipt.bets, hasLength(1));
      expect(result.receipt.lines, ['07 15 16 22 35 + 04 06']);
    },
  );

  test(
    'missing index leaves its slot pending instead of renumbering',
    () async {
      final result = await read([...row(1, 70), ...row(3, 210)], count: 3);
      expect(result.receipt.bets.map((b) => b.index), [1, 2, 3]);
      expect(result.receipt.bets[1].complete, isFalse);
      expect(result.receipt.bets.last.index, 3);
    },
  );

  test('duplicate indices are not accepted as a complete bet', () async {
    final result = await read([...row(1, 70), ...row(1, 140)]);
    expect(result.receipt.lines, isEmpty);
    expect(result.receipt.bets.first.issues.join(' '), contains('repetido'));
  });

  test(
    'uncertain digits affect only their own bet, not neighbouring stars',
    () async {
      final result = await read([
        ...row(1, 70, numbers: 'O715162235'),
        ...row(2, 140),
      ], count: 2);
      expect(result.receipt.bets.first.complete, isFalse);
      expect(result.receipt.bets.first.numbers, isEmpty);
      expect(result.receipt.bets.first.stars, [4, 6]);
      expect(result.receipt.bets.last.complete, isTrue);
    },
  );

  test(
    'only an incomplete numbered row is cropped and can be completed',
    () async {
      final calls = <int>[];
      final result = await read(
        [...row(1, 70), ...row(2, 140, stars: '04')],
        count: 2,
        crop: (crop, scale) async {
          calls.add(crop.index);
          return const OcrFrame('2.N 07 15 16 22 35\nE 04 06', []);
        },
      );
      expect(calls, [2]);
      expect(result.receipt.lines, hasLength(2));
    },
  );

  test(
    'a crop returning another printed index cannot fill the requested row',
    () async {
      final result = await read(
        row(1, 70, numbers: '071516223'),
        crop: (_, _) async => const OcrFrame('2.N 07 15 16 22 35\nE 04 06', []),
      );
      expect(result.receipt.lines, isEmpty);
    },
  );

  test('contradictory complete numeric groups stay unconfirmed', () async {
    final result = await read(
      row(1, 70, stars: '04'),
      crop: (_, _) async => const OcrFrame('1.N 01 12 23 34 45\nE 04 06', []),
    );
    expect(result.receipt.lines, isEmpty);
    expect(result.receipt.bets.first.numbers, [7, 15, 16, 22, 35]);
    expect(
      result.receipt.bets.first.issues.join(' '),
      contains('contraditórias'),
    );
  });

  test(
    'row position is relative to N/E anchors, including skew and scaling',
    () async {
      final source = [...row(1, 70), ...row(2, 140)];
      final angle = 8.0, slope = math.tan(8 * math.pi / 180);
      final moved = source
          .map(
            (v) => ReceiptToken(
              v.text,
              35 + v.x * 1.5,
              80 + (v.y + slope * v.x) * 1.5,
              v.height * 1.5,
              width: v.width * 1.5,
              angle: angle,
            ),
          )
          .toList();
      final result = await read(moved, count: 2);
      expect(result.receipt.lines, hasLength(2));
    },
  );

  test(
    'recovery pipeline explicitly enables numbered-first photo reading',
    () async {
      final result = await recoverReceiptRows(
        initial: OcrFrame('', row(1, 70)),
        metadata: metadata(1),
        width: 400,
        height: 2000,
        visualCells: true,
        numberedBetsFirst: true,
        recognizeCrop: (_, _) async => const OcrFrame('', []),
      );
      expect(result.receipt.strategy, 'numbered-n-e');
      expect(result.receipt.lines, ['07 15 16 22 35 + 04 06']);
    },
  );

  test(
    'a photo without numbered anchors remains on the existing fallback',
    () async {
      final result = await recoverNumberedBets(
        initial: const OcrFrame('TOTAL 12,50', []),
        width: 400,
        height: 1000,
        recognizeCrop: (_, _) async => const OcrFrame('', []),
      );
      expect(result, isNull);
    },
  );
}
