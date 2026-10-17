import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_cell_consensus.dart';
import 'package:luckyscan50/domain/receipt_evidence.dart';
import 'package:luckyscan50/domain/receipt_geometry.dart';

void main() {
  const box = CropBox(0, 0, 40, 40);
  final cells = [
    for (var i = 0; i < 5; i++) BetCrop(1, box, kind: 'N', position: i),
    for (var i = 0; i < 2; i++) BetCrop(1, box, kind: 'E', position: i),
  ];
  ValueEvidence v(
    String kind,
    int slot,
    int value, {
    String pass = 'a',
    String? correction,
    CropBox bounds = box,
  }) => ValueEvidence(
    kind,
    slot,
    value,
    '$value',
    pass,
    betIndex: 1,
    bounds: bounds,
    correction: correction,
  );
  test(
    'only five distinct bounded numbers and two distinct bounded stars complete a bet',
    () {
      final readings = [
        for (var i = 0; i < 5; i++) v('N', i, i + 1),
        v('E', 0, 7),
        v('E', 1, 8),
      ];
      expect(
        consolidateCellEvidence(cells, readings).bets.single.complete,
        true,
      );
      expect(
        consolidateCellEvidence(cells, [
          ...readings,
          v('N', 0, 2, pass: 'b'),
        ]).bets.single.complete,
        false,
      );
      expect(
        consolidateCellEvidence(cells, [
          ...readings.where((v) => v.kind != 'E'),
          v('E', 0, 13),
        ]).bets.single.complete,
        false,
      );
    },
  );
  test('range and geometry rejection remain in provenance', () {
    final result = consolidateCellEvidence(cells, [
      v('N', 0, 51),
      v('N', 1, 7, bounds: const CropBox(100, 100, 120, 120)),
    ]);
    expect(result.bets.single.numbers, isEmpty);
    expect(
      result.evidence.single.candidates.map((v) => v.validation),
      containsAll(['rejected-range', 'rejected-association']),
    );
  });
  test('a partial text list is not evidence of a column position', () {
    expect(
      consolidateCellEvidence(cells, [v('N', -1, 29)]).bets.single.numbers,
      isEmpty,
    );
  });
  test('a correction needs corroboration from a different pass', () {
    final corrected = v('N', 0, 6, correction: 'O→0');
    expect(
      consolidateCellEvidence(cells, [
        corrected,
        corrected,
      ]).bets.single.numbers,
      isEmpty,
    );
    expect(
      consolidateCellEvidence(cells, [
        corrected,
        v('N', 0, 6, pass: 'contrast'),
      ]).bets.single.numbers,
      [6],
    );
  });
}
