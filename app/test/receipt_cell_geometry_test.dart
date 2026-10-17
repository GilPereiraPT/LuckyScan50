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
}
