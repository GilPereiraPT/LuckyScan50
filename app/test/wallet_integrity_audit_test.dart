import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/wallet.dart';
import 'package:luckyscan50/manual_bets_page.dart';

Receipt walletReceipt({
  required List<BetLine> lines,
  required List<String> draws,
  List<String>? codes,
  List<String>? milhaoDraws,
}) => Receipt(
  id: 'audit-receipt',
  createdAt: '2026-10-18T00:00:00Z',
  source: 'manual',
  code: '',
  costCents: 660,
  lines: lines,
  drawIds: draws,
  milhaoCodes: codes ?? [],
  milhaoDrawIds: milhaoDraws ?? [],
);

void main() {
  test('validated bet values cannot change through retained input lists', () {
    final numbers = [1, 2, 3, 4, 5];
    final stars = [1, 2];
    final line = BetLine(numbers, stars);
    numbers[0] = 50;
    stars.add(3);
    expect(line.numbers, [1, 2, 3, 4, 5]);
    expect(line.stars, [1, 2]);
    expect(() => line.numbers.add(6), throwsUnsupportedError);
    expect(() => line.stars[0] = 12, throwsUnsupportedError);
  });

  test('receipt inputs cannot duplicate a draw or code after validation', () {
    final lines = [
      BetLine([1, 2, 3, 4, 5], [1, 2]),
    ];
    final draws = ['083/2026'];
    final milhaoDraws = ['009/2026'];
    final codes = ['PTM 09893'];
    final receipt = walletReceipt(
      lines: lines,
      draws: draws,
      milhaoDraws: milhaoDraws,
      codes: codes,
    );
    draws.add('083/2026');
    milhaoDraws.add('009/2026');
    codes.add('PTM 09893');
    lines.clear();
    expect(receipt.lines, hasLength(1));
    expect(receipt.drawIds, ['083/2026']);
    expect(receipt.milhaoDrawIds, ['009/2026']);
    expect(receipt.milhaoCodes, ['PTM 09893']);
    expect(() => receipt.drawIds.add('083/2026'), throwsUnsupportedError);
    expect(() => receipt.lines.clear(), throwsUnsupportedError);
    final verification = verify(receipt, [
      {
        'game': 'milhao',
        'drawId': '009/2026',
        'status': 'complete',
        'winningCode': 'PTM09893',
        'amountCents': 100000000,
      },
    ]);
    expect(verification.knownCents, 100000000);
    expect(verification.winningLines, 1);
  });

  test('multiple prizes count each combination and the receipt cost once', () {
    final selection = ManualSelection(multiple: true)
      ..numbers.addAll([1, 2, 3, 4, 5, 6])
      ..stars.addAll([1, 2, 3]);
    final receipt = walletReceipt(
      lines: expandManualSelections([selection]),
      draws: ['083/2026'],
    );
    // 6 main selections x 3 star pairs = 18 distinct paid combinations.
    // Versus this draw: 1x5+2, 2x5+1, 5x4+2 and 10x4+1.
    final draw = <String, dynamic>{
      'game': 'euromilhoes',
      'drawId': '083/2026',
      'status': 'complete',
      'numbers': [1, 2, 3, 4, 5],
      'stars': [1, 2],
      'tiers': List.generate(
        13,
        (i) => {
          'amountCents': [10000, 1000, 500, 200, 100][i < 5 ? i : 4],
        },
      ),
    };
    final verification = verify(receipt, [draw, draw]);
    expect(receipt.lines, hasLength(18));
    expect(verification.winningLines, 18);
    expect(verification.knownCents, 14000);
    expect(finances([receipt], [draw])['spent'], 660);
    expect(finances([receipt], [draw])['theoreticalBalance'], 13340);
  });

  test('manual expansion enforces ranges before creating any combination', () {
    for (final bad in [0, 51]) {
      final selection = ManualSelection()
        ..numbers.addAll([bad, 2, 3, 4, 5])
        ..stars.addAll([1, 2]);
      expect(selection.valid, isFalse);
      expect(() => expandManualSelections([selection]), throwsFormatException);
    }
    final invalidStars = ManualSelection(multiple: true)
      ..numbers.addAll([1, 2, 3, 4, 5, 6])
      ..stars.addAll([1, 13]);
    expect(invalidStars.valid, isFalse);
    expect(() => expandManualSelections([invalidStars]), throwsFormatException);
    expect(() => expandManualSelections([]), throwsFormatException);
  });

  test(
    '500 combinations are allowed and 501 are rejected without deduplication',
    () {
      final simple = ManualSelection()
        ..numbers.addAll([1, 2, 3, 4, 5])
        ..stars.addAll([1, 2]);
      // Repeated selections may represent genuine paid lines: preserve them.
      expect(expandManualSelections(List.filled(500, simple)), hasLength(500));
      expect(
        () => expandManualSelections(List.filled(501, simple)),
        throwsFormatException,
      );
    },
  );

  test(
    'all 13 prize tiers are paid per line and unknown amount stays pending',
    () {
      const matches = [
        [5, 2],
        [5, 1],
        [5, 0],
        [4, 2],
        [4, 1],
        [3, 2],
        [4, 0],
        [2, 2],
        [3, 1],
        [3, 0],
        [1, 2],
        [2, 1],
        [2, 0],
      ];
      final lines = matches
          .map(
            (match) => BetLine(
              [
                ...List.generate(match[0], (i) => i + 1),
                ...List.generate(5 - match[0], (i) => i + 10),
              ],
              [
                ...List.generate(match[1], (i) => i + 1),
                ...List.generate(2 - match[1], (i) => i + 7),
              ],
            ),
          )
          .toList();
      final receipt = walletReceipt(lines: lines, draws: ['083/2026']);
      final tiers = List.generate(
        13,
        (i) => <String, dynamic>{'amountCents': (i + 1) * 100},
      );
      final draw = <String, dynamic>{
        'game': 'euromilhoes',
        'drawId': '083/2026',
        'status': 'complete',
        'numbers': [1, 2, 3, 4, 5],
        'stars': [1, 2],
        'tiers': tiers,
      };
      final complete = verify(receipt, [draw]);
      expect(complete.winningLines, 13);
      expect(complete.knownCents, 9100);
      expect(complete.complete, isTrue);
      tiers[4]['amountCents'] = null;
      final pending = verify(receipt, [draw]);
      expect(pending.knownCents, 8600);
      expect(pending.winningLines, 13);
      expect(pending.unknownPrizes, 1);
      expect(pending.complete, isFalse);
    },
  );

  test('same contest text in different games never aliases the result', () {
    final receipt = walletReceipt(
      lines: [
        BetLine([1, 2, 3, 4, 5], [1, 2]),
      ],
      draws: ['009/2026'],
      milhaoDraws: ['009/2026'],
      codes: ['PTM 09893'],
    );
    final verification = verify(receipt, [
      {
        'game': 'milhao',
        'drawId': '009/2026',
        'status': 'complete',
        'winningCode': 'PTM09893',
        'amountCents': null,
      },
    ]);
    expect(verification.pendingDraws, 1);
    expect(verification.unknownPrizes, 1);
    expect(verification.knownCents, 0);
    expect(verification.complete, isFalse);
  });
}
