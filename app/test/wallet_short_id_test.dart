import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/main.dart';
import 'package:luckyscan50/domain/wallet.dart';

void main() {
  testWidgets('a restored receipt with a short ID renders safely', (
    tester,
  ) async {
    final receipt = Receipt(
      id: 'one',
      createdAt: '2026-10-18',
      source: 'manual',
      code: '',
      costCents: 250,
      lines: [
        BetLine([1, 2, 3, 4, 5], [1, 2]),
      ],
      drawIds: ['083/2026'],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receiptsProvider.overrideWith((ref) async => [receipt]),
          resultsProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
        ],
        child: const LuckyScanApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bilhetes'));
    await tester.pumpAndSettle();
    expect(find.text('Recibo one'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
