import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_ne_lines.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

void main() {
  test('linha N: dez algarismos divididos em cinco pares', () {
    expect(NeLineDigits.parse('0620293248', stars: false), [6, 20, 29, 32, 48]);
    expect(NeLineDigits.parse('06 20 29 32 48', stars: false), [6, 20, 29, 32, 48]);
  });
  test('linha E: quatro algarismos divididos em dois pares', () {
    expect(NeLineDigits.parse('0406', stars: true), [4, 6]);
    expect(NeLineDigits.parse('05 11', stars: true), [5, 11]);
  });
  test('nunca inventar digitos em falta ou corrigir simbolos', () {
    expect(NeLineDigits.parse('儿4 06', stars: true), isNull);
    expect(NeLineDigits.parse('0577', stars: true), isNull);
    expect(NeLineDigits.parse('06', stars: true), isNull);
    expect(NeLineDigits.parse('062029324', stars: false), isNull);
  });
  test('rejeitar repetidos, valores invalidos e ordem N errada', () {
    expect(NeLineDigits.parse('0006293248', stars: false), isNull);
    expect(NeLineDigits.parse('0620292948', stars: false), isNull);
    expect(NeLineDigits.parse('2029063248', stars: false), isNull);
    expect(NeLineDigits.parse('0012', stars: true), isNull);
  });
  test('talão físico: N seguido de E isolado e metadados explícitos', () {
    const data = 'EUROMILHÕES\n'
        '5 AP SIMPLES AUT SORT 081\n'
        '1.N 06 20 29 32 48\nE\n04 06\n'
        '2.N 05 17 36 47 49\nE\n05 11\n'
        'TOTAL A PAGAR € 11,00\n2026/10/09';
    final result = parseReceiptObservations(text: data);
    expect(result.amount, '11,00');
    expect(result.drawDate, '2026-10-09');
    expect(result.drawId, '081/2026');
    expect(result.expectedLines, 5);
    // An isolated E never authorizes borrowing a number from the next N row.
    expect(result.bets.first.numbers, [6, 20, 29, 32, 48]);
    expect(result.bets.first.stars.length, lessThanOrEqualTo(2));
  });
  test('parser principal associa N e E de cinco apostas', () {
    const data = '5 AP SIMPLES AUT SORT 081\n'
        '1.N 0620293248\nE 0406\n'
        '2.N 0517364749\nE 0511\n'
        '3.N 2226434547\nE 0309\n'
        '4.N 0610133544\nE 0210\n'
        '5.N 0206132032\nE 0310\n'
        'TOTAL A PAGAR 11,00';
    final result = parseReceiptObservations(text: data);
    expect(result.bets, hasLength(5));
    expect(result.bets.every((b) => b.complete), isTrue);
    expect(result.expectedLines, 5);
    expect(result.bets.first.numbers, [6, 20, 29, 32, 48]);
    expect(result.bets.last.stars, [3, 10]);
  });
}
