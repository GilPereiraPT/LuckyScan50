import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/receipt_scanner.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

void main() {
  test('unreadable initial frame triggers bounded orientation recovery', () {
    expect(receiptNeedsOrientationSearch(const [], 1200, 1900), isTrue);
    expect(
      receiptNeedsOrientationSearch(
        [const ReceiptToken('EUROMILHÕES', 100, 50, 22, width: 190)],
        1200,
        1900,
      ),
      isTrue,
    );
  });

  test('an upright numbered bet does not trigger unnecessary rotation', () {
    const tokens = [
      ReceiptToken('1.N', 50, 100, 24, width: 44),
      ReceiptToken('06', 130, 100, 24, width: 32),
      ReceiptToken('20', 210, 100, 24, width: 32),
    ];
    expect(receiptNeedsOrientationSearch(tokens, 1200, 1900), isFalse);
  });

  test('sideways N anchors trigger rotation recovery', () {
    const tokens = [ReceiptToken('1.N', 100, 500, 160, width: 25, angle: 90)];
    expect(receiptNeedsOrientationSearch(tokens, 1200, 1900), isTrue);
  });

  test('better orientation wins, equal quality never overwrites first', () {
    expect(prefersReceiptOrientation(5, 1), isTrue);
    expect(prefersReceiptOrientation(1, 5), isFalse);
    expect(prefersReceiptOrientation(5, 5), isFalse);
    expect(prefersReceiptOrientation(0, 0), isFalse);
  });
}
