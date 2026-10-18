import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

ReceiptToken token(String text, double x, double y, {double width = 60}) =>
    ReceiptToken(text, x, y, 55, width: width);

void main() {
  test('N/E proximity associates five bets and stars', () {
    const numbers = [
      [6, 20, 29, 32, 48],
      [5, 17, 36, 47, 49],
      [22, 26, 43, 45, 47],
      [6, 10, 13, 35, 44],
      [2, 6, 13, 20, 32],
    ];
    const stars = [
      [4, 6],
      [5, 11],
      [3, 9],
      [2, 10],
      [3, 10],
    ];
    final tokens = <ReceiptToken>[token('081', 650, 920)];
    for (var i = 0; i < 5; i++) {
      final y = 1025.0 + i * 105;
      tokens.add(token('${i + 1}.N', 175, y));
      tokens.add(token('E', 195, y + 50, width: 30));
      for (var j = 0; j < 5; j++) {
        tokens.add(token('${numbers[i][j]}', 315.0 + 150 * j, y));
      }
      for (var j = 0; j < 2; j++) {
        tokens.add(token('${stars[i][j]}', 315.0 + 150 * j, y + 50));
      }
    }
    final result = parseReceiptObservations(
      text: 'EUROMILHOES 5 AP SIMPLES AUT SORT 081 2026/10/09',
      tokens: tokens,
    );
    expect(result.bets.length, 5);
    expect(result.bets.first.numbers, numbers.first);
    expect(result.bets.first.stars, stars.first);
    expect(result.bets.last.numbers, numbers.last);
    expect(result.bets.last.stars, stars.last);
  });
}
