import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_cells.dart';
import 'package:luckyscan50/domain/receipt_geometry.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

void main() {
  test(
    'real report geometry yields five numbered rows and paired-digit columns',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/receipt_1792267583612_geometry.json',
                ).readAsStringSync(),
              )
              as Map;
      final tokens = [
        for (final t in fixture['tokens'])
          ReceiptToken(
            t['text'],
            (t['x'] as num).toDouble(),
            (t['y'] as num).toDouble(),
            (t['height'] as num).toDouble(),
            width: (t['width'] as num).toDouble(),
            angle: (t['angleDegrees'] as num).toDouble(),
          ),
      ];
      final rows = planBetCrops(tokens, 2160, 3000);
      final grid = planBetCells(tokens, rows, 2160, 3000);
      expect(rows.rows.map((r) => r.index), [1, 2, 3, 4, 5]);
      expect(grid.cells.length, 25);
      expect(grid.markers.length, 5);
      expect(grid.cells.where((c) => c.kind == 'E'), isEmpty);
    },
  );
  test(
    'one indexed N and explicit E row need no printed five-bet assumption',
    () {
      final tokens = [
        const ReceiptToken('1.N', 50, 100, 20, width: 30),
        const ReceiptToken('E', 50, 135, 20, width: 15),
        for (var i = 0; i < 5; i++)
          ReceiptToken('${i + 1}', 120 + i * 60.0, 100, 20, width: 25),
        for (var i = 0; i < 2; i++)
          ReceiptToken('${i + 7}', 120 + i * 60.0, 135, 20, width: 25),
      ];
      final grid = planBetCells(
        tokens,
        planBetCrops(tokens, 600, 400),
        600,
        400,
      );
      expect(grid.cells.length, 7);
      expect(grid.markers, isEmpty);
    },
  );
  test(
    'upside-down anchors cannot win orientation selection, including unreliable zero angles',
    () {
      final tokens = [
        const ReceiptToken('1.N', 50, 100, 20, width: 30),
        const ReceiptToken('29', 240, 100, 20, width: 25),
        const ReceiptToken('32', 300, 100, 20, width: 25),
      ];
      expect(uprightBetRowCount(tokens, 600, 400), 1);
      for (final angle in [0.0, 180.0]) {
        final rotated = [
          for (final t in tokens)
            ReceiptToken(
              t.text,
              600 - t.x,
              400 - t.y,
              t.height,
              width: t.width,
              angle: angle,
            ),
        ];
        expect(uprightBetRowCount(rotated, 600, 400), 0);
      }
    },
  );
  test(
    'N anchor angles prioritize the corrective rotation instead of three blind full-frame passes',
    () {
      expect(
        preferredReceiptTurns([
          const ReceiptToken('1.N', 50, 100, 20, angle: 90),
        ]).first,
        3,
      );
      expect(
        preferredReceiptTurns([
          const ReceiptToken('1.N', 50, 100, 20, angle: 180),
        ]).first,
        2,
      );
      expect(
        preferredReceiptTurns([
          const ReceiptToken('1.N', 50, 100, 20, angle: 270),
        ]).first,
        1,
      );
    },
  );
  test('E belongs below N, not to a distant text column', () {
    final tokens = <ReceiptToken>[
      const ReceiptToken('1.N', 50, 100, 20, width: 30),
      const ReceiptToken('E', 250, 135, 20, width: 15),
      for (var i = 0; i < 5; i++)
        ReceiptToken('${i + 1}', 120 + i * 60.0, 100, 20, width: 25),
    ];
    final grid = planBetCells(
      tokens,
      planBetCrops(tokens, 600, 400),
      600,
      400,
    );
    expect(grid.markers.length, 1);
    expect(grid.cells.where((c) => c.kind == 'E'), isEmpty);
  });

}
