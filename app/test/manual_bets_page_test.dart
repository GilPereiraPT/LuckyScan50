import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/manual_bets_page.dart';

void main() {
  test('draw calendar and combination price', () {
    final options = manualDrawOptions(DateTime(2026, 10, 19), []);
    expect(options['081/2026'], '2026-10-09');
    expect(options['082/2026'], '2026-10-13');
    expect(options['083/2026'], '2026-10-16');
    expect(manualCostCents(18), 4500);
    expect(manualCostCents(0), 0);
    final overridden = manualDrawOptions(DateTime(2026), [
      {'game': 'euromilhoes', 'drawId': '083/2026', 'date': '2026-10-17'},
    ]);
    expect(overridden['083/2026'], '2026-10-17');
  });
  test('single selection produces exactly one valid line', () {
    final s = ManualSelection();
    s.numbers.addAll([48, 6, 29, 32, 20]);
    s.stars.addAll([6, 4]);
    expect(s.valid, isTrue);
    expect(s.combinations, 1);
    final lines = expandManualSelections([s]);
    expect(lines, hasLength(1));
    expect(lines.single.numbers, [6, 20, 29, 32, 48]);
    expect(lines.single.stars, [4, 6]);
  });

  test('multiple expands to all distinct simple combinations', () {
    final s = ManualSelection(multiple: true);
    s.numbers.addAll([1, 2, 3, 4, 5, 6]);
    s.stars.addAll([1, 2, 3]);
    expect(s.valid, isTrue);
    expect(s.combinations, 18);
    final lines = expandManualSelections([s]);
    expect(lines, hasLength(18));
    expect(
      lines.map((l) => '${l.numbers.join(',')}+${l.stars.join(',')}').toSet(),
      hasLength(18),
    );
  });

  test('incomplete entries cannot be saved', () {
    expect(
      () => expandManualSelections([ManualSelection()]),
      throwsFormatException,
    );
  });

  test('large multiple is rejected to protect local wallet', () {
    final s = ManualSelection(multiple: true);
    s.numbers.addAll(List.generate(10, (i) => i + 1));
    s.stars.addAll(List.generate(12, (i) => i + 1));
    expect(s.valid, isTrue);
    expect(s.combinations, 16632);
    expect(() => expandManualSelections([s]), throwsFormatException);
  });
}
