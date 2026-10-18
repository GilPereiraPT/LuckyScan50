import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luckyscan50/main.dart';
import 'package:luckyscan50/domain/wallet.dart';

void main() {
  testWidgets('wallet shows empty state and opens the manual selector', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receiptsProvider.overrideWith((ref) async => <Receipt>[]),
          resultsProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
        ],
        child: const LuckyScanApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A sua carteira'), findsOneWidget);
    expect(find.textContaining('0 recibos'), findsOneWidget);
    await tester.tap(find.text('Bilhetes'));
    await tester.pumpAndSettle();
    expect(find.text('Sem bilhetes para esta pesquisa.'), findsOneWidget);
    await tester.tap(find.text('Criar aposta manual'));
    await tester.pumpAndSettle();
    expect(find.text('Introdução manual'), findsOneWidget);
    expect(find.text('As suas chaves, à sua maneira'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });
}
