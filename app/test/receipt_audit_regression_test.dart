import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/receipt_scanner.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

void main() {
  const complete = '1.N 06 20 29 32 48\nE 04 06';

  test('partial geometry cannot reduce a printed five-bet layout to one', () {
    final first = parseReceiptObservations(text: '5 AP SIMPLES\n$complete');
    final bounded = withBetLayout(first, 1);
    expect(bounded.expectedLines, 5);
    expect(bounded.bets.map((b) => b.index), [1, 2, 3, 4, 5]);
    expect(bounded.bets.first.complete, isTrue);
    expect(bounded.bets.skip(1).every((b) => !b.complete), isTrue);
    expect(
      bounded.formLines.skip(1).every((line) => line.contains('?')),
      isTrue,
    );
    expect(bounded.warnings.join(' '), contains('Contagem visual 1'));
  });

  test('layout cannot discard a later observed numbered bet', () {
    final first = parseReceiptObservations(
      text: '$complete\n3.N 05 17 36 47 49\nE 05 11',
    );
    final bounded = withBetLayout(first, 1);
    expect(bounded.expectedLines, 3);
    expect(bounded.bets.last.index, 3);
    expect(bounded.bets.last.numbers, [5, 17, 36, 47, 49]);
    expect(bounded.bets[1].complete, isFalse);
  });

  test(
    'a confirmed footer can bound geometry but never erases its warning',
    () {
      final first = parseReceiptObservations(text: '5 AP SIMPLES\n$complete');
      final bounded = withBetLayout(first, 1, closedBettingZone: true);
      expect(bounded.expectedLines, 1);
      expect(bounded.warnings.join(' '), contains('Contagem visual 1'));
    },
  );

  test('geometric N-looking footer text cannot create a later bet', () {
    final parsed = parseReceiptObservations(
      text: '',
      tokens: [
        const ReceiptToken('1.N', 20, 100, 16, width: 25),
        const ReceiptToken('TOTAL', 30, 170, 16, width: 40),
        const ReceiptToken('2.N', 20, 205, 16, width: 25),
      ],
    );
    expect(parsed.expectedLines, 1);
    expect(parsed.bets.map((b) => b.index), [1]);
  });

  test('unnumbered text and grouped tokens require index confirmation', () {
    for (final tokens in [
      <ReceiptToken>[],
      [
        const ReceiptToken('N 06 20 29 32 48', 170, 100, 20, width: 250),
        const ReceiptToken('E 04 06', 80, 125, 20, width: 70),
      ],
    ]) {
      final result = parseReceiptObservations(
        text: 'N 06 20 29 32 48\nE 04 06',
        tokens: tokens,
      );
      expect(result.bets.first.numbers, [6, 20, 29, 32, 48]);
      expect(result.bets.first.stars, [4, 6]);
      expect(result.bets.first.complete, isFalse);
      expect(
        result.bets.first.issues,
        contains('Índice da aposta por confirmar'),
      );
      expect(result.formLines.first, contains('?'));
    }
  });

  test('an isolated E reads its following numeric row only', () {
    final result = parseReceiptObservations(
      text:
          '1.N 06 20 29 32 48\nE\n04 06\n'
          '2.N 05 17 36 47 49\nE\n05 11\nTOTAL 11,00',
    );
    expect(result.lines, ['06 20 29 32 48 + 04 06', '05 17 36 47 49 + 05 11']);
    final missing = parseReceiptObservations(
      text:
          '1.N 06 20 29 32 48\nE\n'
          '2.N 05 17 36 47 49\nE\n05 11\nTOTAL\n04 06',
    );
    expect(missing.bets.first.stars, isEmpty);
    expect(missing.bets[1].stars, [5, 11]);
    expect(missing.bets.first.complete, isFalse);
  });

  test(
    'upside-down N anchor triggers orientation search without vertical words',
    () {
      const upsideDown = [
        ReceiptToken('1.N', 20, 100, 20, width: 25, angle: 180),
      ];
      expect(upsideDown.any(verticalReceiptToken), isFalse);
      expect(receiptNeedsOrientationSearch(upsideDown, 300, 300), isTrue);
      expect(preferredReceiptTurns(upsideDown).first, 2);
      expect(
        receiptNeedsOrientationSearch(
          [const ReceiptToken('1.N', 20, 100, 20, width: 25)],
          300,
          300,
        ),
        isFalse,
      );
      // An empty OCR frame can itself be caused by a sideways photograph.
      expect(receiptNeedsOrientationSearch([], 300, 300), isTrue);
    },
  );
}
