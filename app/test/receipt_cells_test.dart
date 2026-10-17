import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_cells.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';
import 'package:luckyscan50/domain/receipt_cell_consensus.dart';

// Actual JSON geometry, redacted administrative identifiers. Recognize callbacks
// below are controlled substitutes, never evidence of real Android/visual OCR.
List<ReceiptToken> reportedTokens({double scale = 1, double tilt = 0}) {
  final json =
      jsonDecode(
            File(
              'test/fixtures/receipt_1792267583612_geometry.json',
            ).readAsStringSync(),
          )
          as Map;
  return [
    for (final t in json['tokens'])
      ReceiptToken(
        t['text'],
        t['x'] * scale,
        (t['y'] + tilt * t['x']) * scale,
        t['height'] * scale,
        width: t['width'] * scale,
        angle:
            ((t['angleDegrees'] as num).abs() > 70
                    ? t['angleDegrees']
                    : tilt == 0
                    ? t['angleDegrees']
                    : 4.0)
                .toDouble(),
      ),
  ];
}

OcrFrame initialFrame() =>
    OcrFrame('EUROMILHÕES COM M1LHÃO\n5 AP SIMPLES', reportedTokens());
OcrFrame markerFrame(BetCrop crop) => OcrFrame('E', [
  ReceiptToken('E', crop.box.width * .65, crop.box.height / 2, 60, width: 30),
]);
void main() {
  test(
    'real report splits four vertical digit columns into two number columns',
    () {
      final tokens = reportedTokens();
      final grid = planBetCells(
        tokens,
        planBetCrops(tokens, 2160, 3000),
        2160,
        3000,
      );
      expect(grid.cells.length, 25);
      expect(grid.markers.length, 5);
      expect(grid.cells.where((c) => c.kind == 'E'), isEmpty);
      expect(
        (grid.cells.first.box.left + grid.cells.first.box.right) / 2,
        closeTo(580, 20),
      );
      expect(grid.cells.first.position, 0);
    },
  );
  test(
    'verified E probes establish separate star rows, empty OCR never fabricates values',
    () async {
      final result = await recoverReceiptRows(
        initial: initialFrame(),
        width: 2160,
        height: 3000,
        recognizeCrop: (c, s) async =>
            c.kind == 'marker' ? markerFrame(c) : const OcrFrame('', []),
      );
      expect(result.receipt.lines, isEmpty);
      expect(result.receipt.bets.every((b) => b.stars.isEmpty), true);
      expect(result.passes.where((p) => p.crop.kind == 'E').length, 10);
      expect(result.skippedKnownCells, 14);
      expect(result.passes.where((p) => p.scale == 2), isEmpty);
      expect(
        result.evidence.first.acceptedValues.first.position,
        2,
      ); // 29 is third, not first.
      expect(result.receipt.hasMilhao, true);
    },
  );
  test(
    'controlled cell readings fill observed slots without N/E text anchors',
    () async {
      // Arbitrary controlled values; not the known ticket prefix values.
      const n = [1, 2, 3, 4, 5], e = [7, 8];
      final result = await recoverReceiptRows(
        initial: initialFrame(),
        width: 2160,
        height: 3000,
        recognizeCrop: (c, s) async => c.kind == 'marker'
            ? markerFrame(c)
            : OcrFrame(
                '${(c.kind == 'N' ? n : e)[c.position!]}'.padLeft(2, '0'),
                const [],
              ),
      );
      expect(result.receipt.lines.length, 5);
      expect(
        result.receipt.bets.every((b) => b.stars.join(',') == '7,8'),
        true,
      );
      expect(result.receipt.bets.first.numbers, [1, 2, 29, 32, 48]);
      expect(result.receipt.bets.last.numbers, [1, 2, 13, 4, 32]);
      expect(
        result.passes.length,
        26,
      ); // 5 label probes + 21 missing cells; no row OCR/2x.
      expect(
        result.evidence
            .expand((e) => e.acceptedValues)
            .every((v) => v.bounds != null && v.betIndex != null),
        true,
      );
    },
  );
  test(
    'unverified E probes never turn an assumed between-row location into stars',
    () async {
      final result = await recoverReceiptRows(
        initial: initialFrame(),
        width: 2160,
        height: 3000,
        recognizeCrop: (c, s) async => const OcrFrame('', []),
      );
      expect(result.passes.where((p) => p.crop.kind == 'E'), isEmpty);
      expect(result.receipt.lines, isEmpty);
    },
  );
  test(
    'relative column geometry survives resolution scaling and mild inclination',
    () {
      for (final scale in [.5, 1.0, 2.0]) {
        final tokens = reportedTokens(scale: scale);
        final grid = planBetCells(
          tokens,
          planBetCrops(tokens, 2160 * scale, 3000 * scale),
          2160 * scale,
          3000 * scale,
        );
        expect(grid.cells.length, 25, reason: 'scale $scale');
      }
      final tokens = reportedTokens(tilt: .07);
      final grid = planBetCells(
        tokens,
        planBetCrops(tokens, 2160, 3200),
        2160,
        3200,
      );
      expect(grid.cells.length, 25);
    },
  );
  test(
    'O/I/S corrections apply to numeric cells only, bounded and single-valued',
    () {
      expect(parseNumericCell('O6', 'N').value, 6);
      expect(parseNumericCell('I2', 'E').value, 12);
      expect(parseNumericCell('S', 'N').value, 5);
      for (final text in [
        'TOTAL',
        'M1LHÃO',
        'O00NOO0O0',
        '06 20',
        '0',
        '51',
        '20O',
      ]) {
        expect(parseNumericCell(text, 'N').value, isNull);
      }
      expect(parseNumericCell('13', 'E').value, isNull);
      expect(parseNumericCell('06', 'M1').value, isNull);
    },
  );
  test(
    'consensus is per bet and slot; conflicting or uncorroborated corrections stay pending',
    () {
      const box = CropBox(0, 0, 40, 40);
      const cells = [
        BetCrop(1, box, kind: 'N', position: 0),
        BetCrop(2, box, kind: 'N', position: 0),
      ];
      ValueEvidence v(int bet, int value, String pass, {String? correction}) =>
          ValueEvidence(
            'N',
            0,
            value,
            '$value',
            pass,
            betIndex: bet,
            bounds: box,
            correction: correction,
          );
      var result = consolidateCellEvidence(cells, [
        v(1, 6, 'a'),
        v(1, 6, 'b'),
        v(2, 6, 'a'),
      ]);
      expect(result.bets.map((b) => b.numbers.single), [6, 6]);
      result = consolidateCellEvidence(cells, [
        v(1, 6, 'a'),
        v(1, 7, 'b'),
        v(2, 6, 'a', correction: 'O→0'),
      ]);
      expect(result.bets.every((b) => b.numbers.isEmpty), true);
      expect(result.evidence.first.candidates.every((v) => v.conflict), true);
      result = consolidateCellEvidence(cells, [
        v(1, 6, 'a', correction: 'O→0'),
        v(1, 6, 'contrast', correction: 'O→0'),
      ]);
      expect(result.bets.first.numbers, [6]);
      expect(result.bets.first.complete, false);
    },
  );
  test(
    'actual recorded row results recover the observed 20 in bet five without filling unseen values',
    () {
      final data =
          jsonDecode(
                File(
                  'test/fixtures/receipt_1792267583612_geometry.json',
                ).readAsStringSync(),
              )
              as Map;
      final tokens = reportedTokens();
      final grid = planBetCells(
        tokens,
        planBetCrops(tokens, 2160, 3000),
        2160,
        3000,
      );
      final observed = projectCellObservations(
        initialFrame(),
        grid.cells,
        'full-frame',
      );
      expect(
        consolidateCellEvidence(
          grid.cells,
          observed,
        ).bets.fold(0, (int a, b) => a + b.numbers.length),
        14,
      );
      for (final pass in data['cropPasses']) {
        if (!(pass['id'] as String).endsWith('@1x')) continue;
        final b = pass['bounds'];
        final frame = OcrFrame(pass['rawText'], [
          for (final t in pass['tokens'])
            ReceiptToken(
              t['text'],
              (t['x'] as num).toDouble(),
              (t['y'] as num).toDouble(),
              (t['height'] as num).toDouble(),
              width: (t['width'] as num).toDouble(),
              angle: (t['angleDegrees'] as num).toDouble(),
            ),
        ]);
        observed.addAll(
          projectCellObservations(
            frame,
            grid.cells,
            pass['id'],
            sourceBox: CropBox(
              (b['left'] as num).toDouble(),
              (b['top'] as num).toDouble(),
              (b['right'] as num).toDouble(),
              (b['bottom'] as num).toDouble(),
            ),
          ),
        );
      }
      final result = consolidateCellEvidence(grid.cells, observed);
      expect(result.bets.fold(0, (int a, b) => a + b.numbers.length), 15);
      expect(result.bets.last.numbers, [13, 20, 32]);
      expect(
        result.evidence.last.acceptedValues
            .singleWhere((v) => v.value == 20)
            .position,
        3,
      );
      expect(result.bets.every((b) => !b.complete && b.stars.isEmpty), true);
      expect(
        result.evidence.every(
          (b) => b.acceptedValues.every((v) => v.position >= 2),
        ),
        true,
      );
    },
  );
  test(
    'an E group already read without separable cells is preserved by the row fallback',
    () async {
      final initial = OcrFrame('EUROMILHÕES COM M1LHÃO\n5 AP SIMPLES', [
        ...reportedTokens(),
        const ReceiptToken('E 07', 375, 1170, 80, width: 150),
      ]);
      expect(initial.parse().bets.first.stars, [7]);
      final result = await recoverReceiptRows(
        initial: initial,
        width: 2160,
        height: 3000,
        recognizeCrop: (c, s) async => const OcrFrame('', []),
      );
      expect(result.receipt.bets.first.stars, [7]);
      expect(result.passes.every((p) => p.crop.kind == null), true);
    },
  );
  test(
    'ambiguous number columns do not erase old numbers when only E cells can be found',
    () async {
      final initial = OcrFrame('EUROMILHÕES COM M1LHÃO\n5 AP SIMPLES', [
        ...reportedTokens(),
        const ReceiptToken('40', 1900, 1090, 80, width: 100),
        for (var i = 0; i < 5; i++)
          ReceiptToken('E', 375, 1170 + i * 174.0, 80, width: 35),
      ]);
      final before = initial.parse().bets.first.numbers;
      final result = await recoverReceiptRows(
        initial: initial,
        width: 2160,
        height: 3000,
        recognizeCrop: (c, s) async => const OcrFrame('', []),
      );
      expect(result.receipt.bets.first.numbers, before);
    },
  );
}
