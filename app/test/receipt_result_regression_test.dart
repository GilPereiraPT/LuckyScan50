import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/recent_results.dart';
import 'package:luckyscan50/data/wallet_store.dart';
import 'package:luckyscan50/domain/wallet.dart';
import 'package:luckyscan50/main.dart';

Receipt photographedReceipt({String contest = '081/2026'}) => Receipt(
  id: 'receipt-081',
  createdAt: '2026-10-19T12:00:00Z',
  source: 'manual',
  code: '',
  costCents: 1250,
  drawIds: [contest],
  lines: [
    BetLine([6, 20, 29, 32, 48], [4, 6]),
    BetLine([5, 17, 36, 47, 49], [5, 11]),
    BetLine([22, 26, 43, 45, 47], [3, 9]),
    BetLine([6, 10, 13, 35, 44], [2, 10]),
    BetLine([2, 6, 13, 20, 32], [3, 10]),
  ],
);

class _EmptyResultsStore implements WalletStore {
  @override
  Future<List<Map<String, dynamic>>> results() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'official 081 settles photographed receipt offline without a prize',
    () async {
      final results = await withRecentResults([]);
      expect(
        results.map((r) => r['drawId']),
        containsAll(['081/2026', '082/2026', '083/2026']),
      );
      final check = verify(photographedReceipt(), results);
      expect(check.complete, isTrue);
      expect(check.label, 'Sem prémio');
      expect(check.winningLines, 0);
      expect(check.knownCents, 0);

      final winning = Receipt.fromJson({
        ...photographedReceipt().toJson(),
        'lines': [
          BetLine([5, 20, 24, 31, 45], [1, 2]).toJson(),
        ],
      });
      expect(verify(winning, results).knownCents, 2389813);
      expect(verify(winning, results).label, 'Premiado');
    },
  );

  test(
    'stored corrections win and partial sync cannot downgrade complete seed',
    () async {
      final recent = await withRecentResults([]);
      final draw = recent.firstWhere((r) => r['drawId'] == '081/2026');
      final corrected = {...draw, 'retrievedAt': '2026-10-19T13:30:00Z'};
      final combined = mergeRecentResults([corrected], recent);
      expect(combined.where((r) => r['drawId'] == '081/2026'), hasLength(1));
      expect(
        combined.firstWhere((r) => r['drawId'] == '081/2026'),
        same(corrected),
      );
      final partial = {...draw, 'status': 'numbers_confirmed'};
      expect(
        mergeRecentResults([
          partial,
        ], recent).firstWhere((r) => r['drawId'] == '081/2026')['status'],
        'complete',
      );
      expect(
        verify(photographedReceipt(contest: '001/2025'), recent).complete,
        isFalse,
      );
    },
  );

  for (final contest in ['081/2026', '001/2025']) {
    testWidgets('receipt $contest keeps deletion above Android navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(_EmptyResultsStore()),
            receiptsProvider.overrideWith(
              (ref) async => [photographedReceipt(contest: contest)],
            ),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 640),
                padding: EdgeInsets.only(bottom: 34),
                viewPadding: EdgeInsets.only(bottom: 34),
              ),
              child: const ReceiptPage('receipt-081'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (contest == '081/2026') {
        expect(find.text('Sem prémio · manual'), findsOneWidget);
      } else {
        expect(find.text('Prémios identificados'), findsNothing);
        expect(
          find.textContaining('Não significa ausência de prémio'),
          findsOneWidget,
        );
      }
      final delete = find.widgetWithText(OutlinedButton, 'Eliminar recibo');
      expect(tester.getRect(delete).bottom, lessThanOrEqualTo(606));
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(
        find.text('Eliminar este recibo e a respetiva imagem?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
