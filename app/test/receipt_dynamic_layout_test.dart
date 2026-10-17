import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_autofill.dart';
import 'package:luckyscan50/domain/receipt_cells.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';
import 'package:luckyscan50/domain/receipt_rules.dart';

// Controlled geometry/raster fixtures, not claims of OCR over real photographs.
List<ReceiptToken> ticket(
  int count, {
  Set<int> missing = const {},
  bool onlyFirstValues = false,
  bool footer = true,
}) => [
  for (var i = 1; i <= count; i++)
    if (!missing.contains(i)) ...[
      ReceiptToken('$i.N', 40, 100 + (i - 1) * 70, 16, width: 32),
      ReceiptToken('E', 40, 125 + (i - 1) * 70, 16, width: 12),
      if (!onlyFirstValues || i == 1) ...[
        for (var j = 0; j < 5; j++)
          ReceiptToken(
            '${j + 1}'.padLeft(2, '0'),
            110 + j * 75.0,
            100 + (i - 1) * 70,
            16,
            width: 24,
          ),
        for (var j = 0; j < 2; j++)
          ReceiptToken(
            '${j + 8}'.padLeft(2, '0'),
            110 + j * 75.0,
            125 + (i - 1) * 70,
            16,
            width: 24,
          ),
      ],
    ],
  if (footer) ...[
    ReceiptToken('TOTAL', 40, 100 + (count - 1) * 70 + 85, 16, width: 50),
    ReceiptToken(
      '782-00837480-199',
      350,
      100 + (count - 1) * 70 + 115,
      16,
      width: 200,
    ),
    ReceiptToken(
      '${count + 1}.N',
      40,
      100 + (count - 1) * 70 + 145,
      16,
      width: 32,
    ),
    const ReceiptToken('12', 500, 45, 16, width: 24),
  ],
];
List<CropBox> rules(int count) => [
  const CropBox(20, 70, 540, 72),
  CropBox(20, 100 + (count - 1) * 70 + 55, 540, 100 + (count - 1) * 70 + 57),
];
double height(int count) => count * 70.0 + 280;

void main() {
  test(
    'split two-digit identifier and N keep their row and upright orientation',
    () {
      final tokens = <ReceiptToken>[];
      for (final t in ticket(12, footer: false)) {
        if (t.text == '10.N') {
          tokens.add(ReceiptToken('10.', t.x - 13, t.y, t.height, width: 18));
          tokens.add(ReceiptToken('N', t.x + 8, t.y, t.height, width: 10));
        } else {
          tokens.add(t);
        }
      }
      final plan = planBetCrops(tokens, 600, height(12), rules: rules(12));
      expect(plan.expectedLines, 12);
      expect(plan.rows.map((r) => r.index), List.generate(12, (i) => i + 1));
      expect(uprightBetRowCount(tokens, 600, height(12)), 12);
    },
  );
  for (final count in [1, 2, 5, 12, 20]) {
    test(
      '$count bets have dynamic rows and exactly seven fields per bet',
      () async {
        final tokens = ticket(count);
        final plan = planBetCrops(
          tokens,
          600,
          height(count),
          rules: rules(count),
        );
        expect(plan.expectedLines, count);
        expect(
          plan.rows.map((r) => r.index),
          List.generate(count, (i) => i + 1),
        );
        expect(plan.missingIndices, isEmpty);
        expect(plan.headerRule, isNotNull);
        expect(plan.footerRule, isNotNull);
        expect(
          plan.rows.last.box.bottom,
          lessThanOrEqualTo(rules(count).last.top),
        );
        final grid = planBetCells(tokens, plan, 600, height(count));
        expect(grid.cells.length, count * 7);
        final result = await recoverReceiptRows(
          initial: OcrFrame('EUROMILHÕES', tokens),
          width: 600,
          height: height(count),
          rules: rules(count),
          recognizeCrop: (crop, scale) async => const OcrFrame('', []),
        );
        expect(result.receipt.expectedLines, count);
        expect(result.receipt.bets.length, count);
        expect(result.receipt.lines.length, count);
      },
    );
  }
  test('omitted indices 2 and 10 keep slots and later values', () async {
    final tokens = ticket(12, missing: {2, 10});
    final plan = planBetCrops(tokens, 600, height(12), rules: rules(12));
    expect(plan.expectedLines, 12);
    expect(plan.missingIndices, [2, 10]);
    final result = await recoverReceiptRows(
      initial: OcrFrame('EUROMILHÕES', tokens),
      width: 600,
      height: height(12),
      rules: rules(12),
      recognizeCrop: (crop, scale) async => const OcrFrame('', []),
    );
    expect(
      result.receipt.bets.map((b) => b.index),
      List.generate(12, (i) => i + 1),
    );
    expect(result.receipt.bets[1].complete, isFalse);
    expect(result.receipt.bets[9].complete, isFalse);
    expect(result.receipt.bets[10].complete, isTrue);
    final updates = receiptAutofill(
      result.receipt,
      current: {},
      atStart: {},
      previousOcr: {},
    );
    final lines = updates['lines']!.split('\n');
    expect(lines.length, 12);
    expect(lines[1], contains('?'));
    expect(lines[9], contains('?'));
    expect(lines[10], '01 02 03 04 05 + 08 09');
  });
  test('N and E remain paired across an illegible identifier', () {
    final tokens = ticket(3)
        .map(
          (t) => t.text == '2.N'
              ? ReceiptToken('N', t.x, t.y, t.height, width: t.width)
              : t,
        )
        .toList();
    final plan = planBetCrops(tokens, 600, height(3), rules: rules(3));
    expect(plan.rows.map((r) => r.index), [1, 2, 3]);
    expect(plan.rows[1].printedIndex, isFalse);
    expect(plan.rows[2].printedIndex, isTrue);
  });
  test('a misread sequence identifier cannot discard later printed bets', () {
    final tokens = ticket(4)
        .map(
          (t) => t.text == '2.N'
              ? ReceiptToken('7.N', t.x, t.y, t.height, width: t.width)
              : t,
        )
        .toList();
    final plan = planBetCrops(tokens, 600, height(4), rules: rules(4));
    expect(plan.expectedLines, 4);
    expect(plan.rows.map((r) => r.index), [1, 3, 4]);
    expect(plan.missingIndices, [2]);
    expect(plan.warnings.join(' '), contains('Sequência'));
  });
  test('a missing E line cannot borrow stars from the following bet', () async {
    final tokens = ticket(
      3,
    ).where((t) => t.y != 125 && !(t.y == 170 && t.text == '2.N')).toList();
    final result = await recoverReceiptRows(
      initial: OcrFrame('EUROMILHÕES', tokens),
      width: 600,
      height: height(3),
      rules: rules(3),
      recognizeCrop: (crop, scale) async => const OcrFrame('', []),
    );
    expect(result.receipt.bets[0].stars, isEmpty);
    expect(result.receipt.bets[0].complete, isFalse);
    expect(result.receipt.bets[2].stars, [8, 9]);
    expect(result.receipt.bets[2].index, 3);
  });
  test(
    'an unnumbered complete row stays pending instead of silently binding values',
    () async {
      final tokens = ticket(3)
          .map(
            (t) => t.text == '2.N'
                ? ReceiptToken('N', t.x, t.y, t.height, width: t.width)
                : t,
          )
          .toList();
      final result = await recoverReceiptRows(
        initial: OcrFrame('EUROMILHÕES', tokens),
        width: 600,
        height: height(3),
        rules: rules(3),
        recognizeCrop: (crop, scale) async => const OcrFrame('', []),
      );
      expect(result.receipt.bets[1].complete, isFalse);
      expect(
        result.receipt.bets[1].issues.join(' '),
        contains('Índice geométrico'),
      );
      expect(result.receipt.bets[2].complete, isTrue);
    },
  );
  test('footer digits and even N-looking footer text never extend bets', () {
    final tokens = ticket(2);
    expect(planBetCrops(tokens, 600, height(2)).rows.map((r) => r.index), [
      1,
      2,
    ]);
    final parsed = parseReceiptObservations(
      text:
          'EUROMILHÕES\n1.N 01 02 03 04 05 E 08 09\nTOTAL 2,20 €\n2.N 10 11 12 13 14 E 01 02',
    );
    expect(parsed.bets.length, 1);
    expect(parsed.expectedLines, 1);
  });
  test(
    'image layout wins over a contradictory printed five-bet OCR count',
    () async {
      final result = await recoverReceiptRows(
        initial: OcrFrame('EUROMILHÕES\n5 AP SIMPLES', ticket(2)),
        width: 600,
        height: height(2),
        rules: rules(2),
        recognizeCrop: (crop, scale) async => const OcrFrame('', []),
      );
      expect(result.receipt.expectedLines, 2);
      expect(result.receipt.bets.length, 2);
      expect(result.receipt.warnings.join(' '), contains('Contagem visual'));
    },
  );
  test(
    'twelve bets receive enough cell passes beyond the previous fixed budget',
    () async {
      final result = await recoverReceiptRows(
        initial: OcrFrame('EUROMILHÕES', ticket(12, onlyFirstValues: true)),
        width: 600,
        height: height(12),
        rules: rules(12),
        recognizeCrop: (crop, scale) async => OcrFrame(
          '${crop.kind == 'N' ? crop.position! + 1 : crop.position! + 8}'
              .padLeft(2, '0'),
          const [],
        ),
      );
      expect(result.passes.length, greaterThan(40));
      expect(result.receipt.lines.length, 12);
      expect(result.receipt.bets.last.index, 12);
      expect(
        result.receipt.warnings.join(' '),
        isNot(contains('passagens atingido')),
      );
    },
  );
  test(
    'out-of-limit identifiers are warned instead of allocating arbitrary slots',
    () {
      final tokens = [
        ...ticket(2),
        const ReceiptToken('99.N', 40, 600, 16, width: 32),
      ];
      final plan = planBetCrops(tokens, 600, 900, rules: rules(2));
      expect(plan.expectedLines, 2);
      expect(plan.warnings.join(' '), contains('fora do limite'));
    },
  );
  for (final skew in [0.0, 0.06]) {
    test(
      'pixels detect dashed header/footer rules with slope $skew and reject digits/barcode',
      () {
        const w = 600, h = 600;
        final pixels = Uint8List(w * h)..fillRange(0, w * h, 235);
        for (final y in [70, 225]) {
          for (var x = 20; x < 540; x++) {
            if (x % 12 < 9) {
              final yy = y + (skew * (x - 20)).round();
              pixels[yy * w + x] = 20;
            }
          }
        }
        // A footer barcode is dark across many rows: it lacks white margins.
        for (var y = 350; y < 410; y++) {
          for (var x = 20; x < 540; x++) {
            if (x % 5 < 3) pixels[y * w + x] = 20;
          }
        }
        final angle = skew == 0 ? 0.0 : 3.4336;
        final tokens = ticket(2, footer: false)
            .map(
              (t) => ReceiptToken(
                t.text,
                t.x,
                t.y + skew * (t.x - 20),
                t.height,
                width: t.width,
                angle: angle,
              ),
            )
            .toList();
        final found = detectReceiptRules(
          ReceiptRaster(w, h, pixels),
          tokens,
          600,
          600,
        );
        expect(found.length, 2);
        final plan = planBetCrops(tokens, 600, 600, rules: found);
        expect(plan.expectedLines, 2);
        expect(plan.headerRule, isNotNull);
        expect(plan.footerRule, isNotNull);
      },
    );
  }
}
