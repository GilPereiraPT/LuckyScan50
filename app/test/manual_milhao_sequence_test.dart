import 'package:flutter_test/flutter_test.dart';
import '../lib/manual_bets_page.dart';

void main() {
  test('preserves letters and leading zeroes across a carry', () {
    expect(manualMilhaoSequence('abc 00009', 3), [
      'ABC 00009',
      'ABC 00010',
      'ABC 00011',
    ]);
  });

  test('rejects malformed codes and invalid quantities', () {
    for (final code in ['AB 00001', 'ABC 1234', 'ABC 123456']) {
      expect(() => manualMilhaoSequence(code, 1), throwsFormatException);
    }
    for (final count in [0, -1, 501]) {
      expect(
        () => manualMilhaoSequence('ABC 00001', count),
        throwsFormatException,
      );
    }
  });

  test('does not wrap or change letters at the numeric limit', () {
    expect(manualMilhaoSequence('ABC99999', 1), ['ABC 99999']);
    expect(
      () => manualMilhaoSequence('ABC 99999', 2),
      throwsFormatException,
    );
  });
}
