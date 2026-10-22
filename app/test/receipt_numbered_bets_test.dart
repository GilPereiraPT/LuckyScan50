import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_numbered_bets.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

ReceiptToken t(
  String text,
  double x,
  double y, {
  double width = 16,
  double h = 14,
  double angle = 0,
}) => ReceiptToken(text, x, y, h, width: width, angle: angle);
List<ReceiptToken> row(int i, double y, {bool e = true, bool split = false}) =>
    [
      if (split) ...[
        t('$i.', 25, y, width: 8),
        t('N', 38, y, width: 8),
      ] else
        t('$i.N', 30, y, width: 24),
      // Global numeric values deliberately disagree with the new line reads.
      t('0112233445', 130, y, width: 160),
      if (e) t('E', 38, y + 20, width: 8),
      t('0102', 82, y + 20, width: 64),
    ];
ScannedReceipt metadata(int count) => ScannedReceipt(
  bets: const [],
  rows: const ['original'],
  warnings: const [],
  expectedLines: count,
  game: 'euromilhoes',
  code: '782-00837480-199',
  drawDate: '2026-10-09',
  drawId: '081/2026',
  amount: '11,00',
  hasMilhao: true,
  milhaoCodes: const ['ABC 00001'],
);
Future<MultiPassResult> read(
  List<ReceiptToken> tokens, {
  int count = 1,
  RecognizeBetCrop? crop,
  double width = 400,
  double height = 2000,
}) async => (await recoverNumberedBets(
  initial: OcrFrame('', tokens),
  metadata: metadata(count),
  width: width,
  height: height,
  recognizeCrop:
      crop ??
      (c, s) async =>
          OcrFrame(c.kind == 'N' ? '07 15 16 22 35' : '04 06', const []),
))!;
void main() {
  test(
    'reads every N and E independently and in printed order, never global values',
    () async {
      final calls = <String>[];
      final r = await read(
        [...row(1, 70), ...row(2, 140)],
        count: 2,
        crop: (c, s) async {
          calls.add('${c.index}.${c.kind}@$s');
          expect(c.box.left, greaterThan(40));
          expect(c.box.right, 400);
          expect(c.box.height, lessThan(35));
          return OcrFrame(c.kind == 'N' ? '07 15 16 22 35' : '04 06', const []);
        },
      );
      expect(calls, ['1.N@1.0', '1.E@1.0', '2.N@1.0', '2.E@1.0']);
      expect(r.receipt.lines, [
        '07 15 16 22 35 + 04 06',
        '07 15 16 22 35 + 04 06',
      ]);
      expect(r.receipt.strategy, 'numbered-n-e-lines');
      expect(r.evidence.first.acceptedValues, hasLength(7));
      expect(r.receipt.code, metadata(2).code);
      expect(r.receipt.amount, '11,00');
      expect(r.receipt.drawId, '081/2026');
      expect(r.receipt.drawDate, '2026-10-09');
      expect(r.receipt.milhaoCodes, ['ABC 00001']);
    },
  );
  test(
    'O and o are zero only inside the numeric N/E crop, with provenance',
    () async {
      final r = await read(
        row(1, 70),
        crop: (c, s) async =>
            OcrFrame(c.kind == 'N' ? 'O6 13 2O 32 48' : 'o4 O6', const []),
      );
      expect(r.receipt.lines, ['06 13 20 32 48 + 04 06']);
      expect(r.evidence.first.acceptedValues.first.raw, 'O6');
      expect(r.evidence.first.acceptedValues.first.correction, contains('O→0'));
      expect(r.receipt.code, '782-00837480-199');
    },
  );
  test('does not synthesize missing digits or replace other letters', () async {
    final r = await read(
      row(1, 70),
      crop: (c, s) async =>
          OcrFrame(c.kind == 'N' ? 'O6 13 X 32 48' : '04 06', const []),
    );
    expect(r.receipt.lines, isEmpty);
    expect(r.receipt.bets.first.stars, [4, 6]);
    expect(r.passes.where((p) => p.crop.kind == 'N'), hasLength(2));
  });
  test('only the failed line is retried, at 2x', () async {
    final calls = <String>[];
    final r = await read(
      row(1, 70),
      crop: (c, s) async {
        calls.add('${c.kind}@$s');
        return OcrFrame(
          c.kind == 'N' ? (s == 1 ? '07 15' : '07 15 16 22 35') : '04 06',
          const [],
        );
      },
    );
    expect(calls, ['N@1.0', 'N@2.0', 'E@1.0']);
    expect(r.receipt.lines, hasLength(1));
  });
  test('explicit foreign index in a crop is rejected', () async {
    final r = await read(
      row(1, 70),
      crop: (c, s) async =>
          OcrFrame(c.kind == 'N' ? '2.N 07 15 16 22 35' : '04 06', const []),
    );
    expect(r.receipt.lines, isEmpty);
  });
  test(
    'wrong marker type is rejected instead of swapping stars and numbers',
    () async {
      final r = await read(
        row(1, 70),
        crop: (c, s) async =>
            OcrFrame(c.kind == 'N' ? 'E 07 15 16 22 35' : '04 06', const []),
      );
      expect(r.receipt.lines, isEmpty);
    },
  );
  test(
    'missing index stays pending; subsequent bets keep their printed index',
    () async {
      final r = await read([...row(1, 70), ...row(3, 210)], count: 3);
      expect(r.receipt.bets.map((b) => b.index), [1, 2, 3]);
      expect(r.receipt.bets[1].complete, isFalse);
      expect(r.receipt.bets.last.complete, isTrue);
    },
  );
  test('duplicate printed indices are never accepted', () async {
    final r = await read([...row(1, 70), ...row(1, 140)]);
    expect(r.receipt.lines, isEmpty);
    expect(r.receipt.bets.first.issues.join(' '), contains('repetido'));
  });
  test('split index and N still locate their own line', () async {
    final r = await read(row(1, 70, split: true));
    expect(r.receipt.lines, hasLength(1));
  });
  test(
    'separator bounds exclude footer lookalikes from numeric reads',
    () async {
      final calls = <int>[];
      final r = await read(
        [
          t('================', 180, 45, width: 350),
          ...row(1, 70),
          t('================', 180, 115, width: 350),
          ...row(2, 160),
        ],
        crop: (c, s) async {
          calls.add(c.index);
          expect(c.box.bottom, lessThanOrEqualTo(115));
          return OcrFrame(c.kind == 'N' ? '07 15 16 22 35' : '04 06', const []);
        },
      );
      expect(calls, [1, 1]);
      expect(r.receipt.lines, hasLength(1));
    },
  );
  test(
    'user diagnostic: five N markers, only two E markers, vertical global garbage',
    () async {
      final tokens = <ReceiptToken>[
        for (final v in [
          (1, 245.0, 1327.0, 92.0),
          (2, 243.5, 1499.5, 87.0),
          (3, 246.5, 1667.0, 80.0),
          (4, 252.5, 1836.5, 79.0),
          (5, 255.5, 2011.0, 84.0),
        ])
          t('${v.$1}.N', v.$2, v.$3, width: 120, h: v.$4),
        t('E', 288.5, 1754.5, width: 45, h: 71),
        t('E', 293, 1921.5, width: 45, h: 75),
        t('O000NOO000', 433, 1697.5, width: 90, h: 833, angle: 88.8),
        t('|OLOLOUM0NONO', 510, 1687.5, width: 90, h: 901, angle: 89.4),
        t('UOrNOrOr', 683, 1693, width: 90, h: 824, angle: 89.3),
        t('OON0000OO', 759.5, 1697, width: 90, h: 830, angle: 90),
      ];
      final crops = <BetCrop>[];
      final r = await read(
        tokens,
        count: 5,
        width: 2200,
        height: 3300,
        crop: (c, s) async {
          crops.add(c);
          // Each actual crop is a horizontal strip; vertical words are not parsed.
          expect(c.box.width, greaterThan(c.box.height * 8));
          return OcrFrame(c.kind == 'N' ? 'O6 13 2O 32 48' : 'O4 O6', const []);
        },
      );
      expect(r.receipt.lines, hasLength(5));
      expect(crops, hasLength(10));
      for (var i = 0; i < 5; i++) {
        final n = crops[i * 2], e = crops[i * 2 + 1];
        expect(n.kind, 'N');
        expect(e.kind, 'E');
        expect(n.index, i + 1);
        expect(e.index, i + 1);
        expect(n.box.top, lessThan(e.box.top));
        if (i < 4) {
          expect(e.box.bottom, lessThan(crops[(i + 1) * 2].box.bottom));
        }
      }
    },
  );
  test('line crops support translated and skewed ticket markers', () async {
    final slope = math.tan(8 * math.pi / 180);
    final tokens = [...row(1, 70), ...row(2, 140)]
        .map(
          (v) => ReceiptToken(
            v.text,
            35 + v.x * 1.5,
            80 + (v.y + slope * v.x) * 1.5,
            v.height * 1.5,
            width: v.width * 1.5,
            angle: 8,
          ),
        )
        .toList();
    final r = await read(tokens, count: 2);
    expect(r.receipt.lines, hasLength(2));
  });
  test(
    'crop errors leave affected values pending and continue subsequent bets',
    () async {
      final r = await read(
        [...row(1, 70), ...row(2, 140)],
        count: 2,
        crop: (c, s) async {
          if (c.index == 1 && c.kind == 'N') throw StateError('OCR');
          return OcrFrame(c.kind == 'N' ? '07 15 16 22 35' : '04 06', const []);
        },
      );
      expect(r.receipt.bets.first.complete, isFalse);
      expect(r.receipt.bets.last.complete, isTrue);
    },
  );
  test('photo pipeline enables separate line recognition', () async {
    final r = await recoverReceiptRows(
      initial: OcrFrame('', row(1, 70)),
      metadata: metadata(1),
      width: 400,
      height: 2000,
      visualCells: true,
      numberedBetsFirst: true,
      recognizeCrop: (c, s) async =>
          OcrFrame(c.kind == 'N' ? '07 15 16 22 35' : '04 06', const []),
    );
    expect(r.receipt.strategy, 'numbered-n-e-lines');
    expect(r.passes, hasLength(2));
  });
  test('without numbered anchors keep the existing fallback', () async {
    expect(
      await recoverNumberedBets(
        initial: const OcrFrame('TOTAL 11,00', []),
        width: 400,
        height: 1000,
        recognizeCrop: (c, s) async => const OcrFrame('', []),
      ),
      isNull,
    );
  });
}
