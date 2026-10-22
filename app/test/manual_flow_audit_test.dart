import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luckyscan50/data/wallet_store.dart';
import 'package:luckyscan50/domain/wallet.dart';
import 'package:luckyscan50/main.dart' show storeProvider, AddReceipt;
import 'package:luckyscan50/manual_bets_page.dart';

class _RecordingWallet implements WalletStore {
  final saved = <Receipt>[];
  @override
  Future<List<Map<String, dynamic>>> results() async => [];
  @override
  Future<void> save(Receipt receipt) async => saved.add(receipt);
  @override
  Future<bool> duplicateCode(String code, String id) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, _RecordingWallet store) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: const MaterialApp(home: ManualBetPage()),
      ),
    );

void main() {
  testWidgets('manual confirmation excludes concurrent saves', (tester) async {
    final store = _RecordingWallet();
    await _open(tester, store);
    final dynamic state = tester.state(find.byType(ManualBetPage));
    for (final number in [1, 2, 3, 4, 5]) {
      state.toggle(number, false);
    }
    for (final star in [1, 2]) {
      state.toggle(star, true);
    }
    state.selectedDraw = '083/2026';
    await tester.pump();
    final first = state.save() as Future<void>;
    final second = state.save() as Future<void>;
    // The in-flight operation intentionally animates its busy indicator.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Confirmar registo', skipOffstage: false), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    expect(store.saved, hasLength(1));
    expect(store.saved.single.costCents, 250);
  });

  testWidgets('imported receipt confirmation excludes concurrent saves', (
    tester,
  ) async {
    final store = _RecordingWallet();
    final routes = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Wallet')),
          routes: [
            GoRoute(path: 'add', builder: (_, __) => const AddReceipt()),
          ],
        ),
      ],
    );
    addTearDown(routes.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: MaterialApp.router(routerConfig: routes),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(AddReceipt));
    state.lines.text = '1 2 3 4 5 + 1 2';
    state.draws.text = '083/2026';
    state.cost.text = '2,20';
    final first = state.save() as Future<void>;
    final second = state.save() as Future<void>;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    expect(store.saved, hasLength(1));
    expect(store.saved.single.costCents, 220);
    expect(find.text('Wallet'), findsOneWidget);
  });

  testWidgets('number and star targets remain at least 48dp on 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, _RecordingWallet());
    await tester.pumpAndSettle();
    for (final label in ['Número 1', 'Estrela 1']) {
      final target = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      );
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
    }
  });

  testWidgets('manual page fits a 320px Android display', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, _RecordingWallet());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual page supports dark theme and large text on 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(_RecordingWallet())],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const ManualBetPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving between selections preserves each unpaid draft', (
    tester,
  ) async {
    await _open(tester, _RecordingWallet());
    final dynamic state = tester.state(find.byType(ManualBetPage));
    state.toggle(7, false);
    state.toggle(4, true);
    state.setCount(2);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '2 ·'));
    await tester.pumpAndSettle();
    state.toggle(35, false);
    state.toggle(9, true);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '1 ·'));
    await tester.pumpAndSettle();
    expect(state.selection.numbers, {7});
    expect(state.selection.stars, {4});
    await tester.tap(find.widgetWithText(ChoiceChip, '2 ·'));
    await tester.pumpAndSettle();
    expect(state.selection.numbers, {35});
    expect(state.selection.stars, {9});
  });
}
