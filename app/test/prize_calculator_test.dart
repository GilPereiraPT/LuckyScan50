import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/prize_calculator.dart';

void main() {
  test('escalões e ausência de prémio', () {
    expect(tierFor(5, 2), 1);
    expect(tierFor(2, 0), 13);
    expect(tierFor(1, 0), isNull);
  });
}
