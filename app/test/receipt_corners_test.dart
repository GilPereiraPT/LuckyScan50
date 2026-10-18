import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/receipt_corners.dart';

void main() {
  test('default four-corner frame is a convex quadrilateral', () {
    expect(validReceiptQuadrilateral(initialReceiptCorners), isTrue);
  });

  test('adjustable corner frame accepts angled photographs', () {
    const corners = [
      ReceiptCorner(.15, .06),
      ReceiptCorner(.92, .12),
      ReceiptCorner(.83, .91),
      ReceiptCorner(.07, .84),
    ];
    expect(validReceiptQuadrilateral(corners), isTrue);
  });

  test('crossed corners, tiny areas and off-image points are rejected', () {
    expect(
      validReceiptQuadrilateral(const [
        ReceiptCorner(.1, .1),
        ReceiptCorner(.9, .9),
        ReceiptCorner(.9, .1),
        ReceiptCorner(.1, .9),
      ]),
      isFalse,
    );
    expect(
      validReceiptQuadrilateral(const [
        ReceiptCorner(.45, .45),
        ReceiptCorner(.55, .45),
        ReceiptCorner(.55, .55),
        ReceiptCorner(.45, .55),
      ]),
      isFalse,
    );
    expect(
      validReceiptQuadrilateral(const [
        ReceiptCorner(-.1, .1),
        ReceiptCorner(.9, .1),
        ReceiptCorner(.9, .9),
        ReceiptCorner(.1, .9),
      ]),
      isFalse,
    );
  });

  test('corner dragging clamps positions to the image boundaries', () {
    const corner = ReceiptCorner(.1, .1);
    final shifted = corner.shifted(-3, 5);
    expect(shifted.x, 0);
    expect(shifted.y, 1);
  });
}
