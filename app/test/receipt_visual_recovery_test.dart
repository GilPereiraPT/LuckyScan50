import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_cells.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

void main() {
  final numbers = <List<int>>[
    [6, 20, 29, 32, 48],
    [5, 17, 36, 47, 49],
    [22, 26, 43, 45, 47],
    [6, 10, 13, 35, 44],
    [2, 6, 13, 20, 32],
  ];
  final stars = <List<int>>[
    [4, 6],
    [5, 11],
    [3, 9],
    [2, 10],
    [3, 10],
  ];

  List<ReceiptToken> realGeometryTokens() {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/receipt_1792267583612_geometry.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    return [
      for (final entry in fixture['tokens'] as List)
        ReceiptToken(
          entry['text'] as String,
          (entry['x'] as num).toDouble(),
          (entry['y'] as num).toDouble(),
          (entry['height'] as num).toDouble(),
          width: (entry['width'] as num).toDouble(),
          angle: (entry['angleDegrees'] as num).toDouble(),
        ),
    ];
  }

  test(
    'visual crops create 35 independent N/E cells from real vertical OCR',
    () {
      final tokens = realGeometryTokens();
      final plan = planBetCrops(tokens, 2160, 3000);
      final grid = planVisualBetCells(tokens, plan, 2160, 3000);
      expect(plan.rows.map((r) => r.index), [1, 2, 3, 4, 5]);
      expect(grid.cells.length, 35);
      for (var index = 1; index <= 5; index++) {
        expect(
          grid.cells.where((c) => c.index == index && c.kind == 'N').length,
          5,
        );
        expect(
          grid.cells.where((c) => c.index == index && c.kind == 'E').length,
          2,
        );
      }
      // The first two columns are not legible in the whole-frame fixture.
      // Their coordinates, not their values, must be reconstructed.
      final first = grid.cells.firstWhere(
        (c) => c.index == 1 && c.kind == 'N' && c.position == 0,
      );
      expect(first.box.left, greaterThan(350));
      expect(first.box.right, lessThan(900));
    },
  );

  Future<MultiPassResult> simulatedScan({
    bool unreadableStar = false,
    bool emptyAt1x = false,
    bool unreadableMissingE = false,
  }) async {
    final tokens = realGeometryTokens();
    final receipt = const ScannedReceipt(
      bets: [],
      rows: [],
      warnings: [],
      expectedLines: 5,
      game: 'euromilhoes',
      amount: '11,00',
      drawDate: '2026-10-09',
    );
    final scan = await recoverReceiptRows(
      visualCells: true,
      initial: OcrFrame('', tokens),
      metadata: receipt,
      width: 2160,
      height: 3000,
      recognizeCrop: (crop, scale) async {
        if (crop.kind == 'marker') {
          if (unreadableMissingE) return const OcrFrame('', []);
          return OcrFrame('E', [
            ReceiptToken(
              'E', crop.box.width / 2, crop.box.height / 2, 30,
              width: 20,
            ),
          ], rows: const ['E']);
        }
        // Full-line probes lack a cell position in this simulated OCR backend.
        if (crop.position == null) return const OcrFrame('', []);
        if (emptyAt1x && scale == 1.0) return const OcrFrame('', []);
        if (crop.kind == 'E' &&
            crop.index == 3 &&
            crop.position == 1 &&
            unreadableStar) {
          return const OcrFrame('?', []);
        }
        final value = crop.kind == 'E'
            ? stars[crop.index - 1][crop.position!]
            : numbers[crop.index - 1][crop.position!];
        final printed = value.toString().padLeft(2, '0');
        return OcrFrame(
          printed,
          [
            ReceiptToken(
              printed,
              crop.box.width / 2,
              crop.box.height / 2,
              30,
              width: 50,
            ),
          ],
          rows: [printed],
        );
      },
    );
    return scan;
  }

  test(
    'scan pipeline uses visual OCR and recovers five complete bets',
    () async {
      final scan = await simulatedScan();
      expect(scan.receipt.strategy, 'visual-grid-cells');
      expect(scan.receipt.bets.length, 5);
      for (var i = 0; i < 5; i++) {
        final bet = scan.receipt.bets[i];
        expect(bet.complete, isTrue);
        expect(bet.numbers, numbers[i]);
        expect(bet.stars, stars[i]);
      }
      expect(scan.passes.where((p) => p.id.startsWith('cell-')).length, 35);
    },
  );

  test('blank 1x visual cells recover through 2x contrast crop', () async {
    final scan = await simulatedScan(emptyAt1x: true);
    expect(scan.receipt.lines, hasLength(5));
    final blankFirstPasses = scan.passes.where(
      (p) => p.id.startsWith('cell-') && p.id.contains('@1x'),
    ).length;
    final enlargedRetries = scan.passes.where(
      (p) => p.id.startsWith('cell-') && p.id.contains('@2x-contrast'),
    ).length;
    // Cells with trustworthy full-frame evidence need not be reprocessed.
    expect(blankFirstPasses, greaterThan(0));
    // First-pass crops already corroborated by the full frame need no retry.
    expect(enlargedRetries, greaterThan(0));
    expect(enlargedRetries, lessThanOrEqualTo(blankFirstPasses));
    for (var i = 0; i < 5; i++) {
      expect(scan.receipt.bets[i].numbers, numbers[i]);
      expect(scan.receipt.bets[i].stars, stars[i]);
    }
  });

  test('missing standalone E cannot borrow stars from a guessed row', () async {
    final scan = await simulatedScan(unreadableMissingE: true);
    final missing = scan.passes
        .where((p) => p.id.startsWith('marker-'))
        .map((p) => p.crop.index)
        .toSet();
    expect(missing, isNotEmpty);
    for (final index in missing) {
      expect(scan.receipt.bets.singleWhere((b) => b.index == index).complete, isFalse);
      expect(scan.receipt.warnings.join(' '), contains('E não confirmado'));
    }
  });

  test('unreadable star stays pending and cannot be manufactured', () async {
    final scan = await simulatedScan(unreadableStar: true);
    final third = scan.receipt.bets[2];
    expect(third.complete, isFalse);
    expect(third.stars, isNot(equals(stars[2])));
    expect(scan.receipt.fullyParsed, isFalse);
  });
}
