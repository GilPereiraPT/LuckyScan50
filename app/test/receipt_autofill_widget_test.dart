import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/main.dart';
import 'package:luckyscan50/data/receipt_scanner.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';
import 'receipt_ocr_test.dart' show referenceBets;

String sample(int count) =>
    'EUROMILHÕES COM M1LHÃO\nCONCURSO 081\n09/10/2026\n5 AP SIMPLES\n'
    '${List.generate(count, (i) => '${i + 1}.N ${referenceBets[i].replaceAll(' + ', ' E ')}').join('\n')}'
    '\nTOTAL 11,00 €\n782-00837480-199\n782-02213749-M1L';
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
String value(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label)).controller!.text;
Future<void> open(WidgetTester tester, ReceiptScanner scanner) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [receiptScannerProvider.overrideWithValue(scanner)],
      child: const MaterialApp(home: AddReceipt()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('parser output reaches the real confirmation form', (
    tester,
  ) async {
    final text = sample(5);
    await open(
      tester,
      (_) async => ReceiptScan(parseReceiptObservations(text: text), text),
    );
    await tester.tap(find.text('Importar imagem'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      field('Chaves — uma por linha'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(value(tester, 'Chaves — uma por linha'), referenceBets.join('\n'));
    expect(value(tester, 'Concursos Euromilhões'), '081/2026');
    expect(value(tester, 'Data do sorteio (AAAA-MM-DD)'), '2026-10-09');
    expect(value(tester, 'Valor total pago (€)'), '11,00');
    await tester.scrollUntilVisible(
      find.text('Fotografe o boletim do M1lhão'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Adiar'), findsOneWidget);
    await tester.tap(find.text('Adiar'));
    await tester.pumpAndSettle();
    expect(find.text('Fotografe o boletim do M1lhão'), findsNothing);
  });
  testWidgets('three of five fill three keys but cannot be silently saved', (
    tester,
  ) async {
    final text = sample(3);
    await open(
      tester,
      (_) async => ReceiptScan(parseReceiptObservations(text: text), text),
    );
    await tester.tap(find.text('Importar imagem'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Aposta 4 incompleta — confirmar'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Aposta 4 incompleta — confirmar'), findsOneWidget);
    // The action is now outside the scrollable form, in its own safe area.
    expect(find.text('Confirmar e guardar'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e guardar'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('complete ou corrija o formulário'),
      findsOneWidget,
    );
  });
  testWidgets('confirmation button remains in the safe bottom action bar', (
    tester,
  ) async {
    await open(tester, (_) async => null);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.bottomNavigationBar, isA<SafeArea>());
    final safeArea = scaffold.bottomNavigationBar! as SafeArea;
    expect(safeArea.top, isFalse);
    expect(safeArea.minimum.bottom, greaterThanOrEqualTo(12));
    expect(find.text('Confirmar e guardar'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is FilledButton), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Image && w.image is AssetImage),
        findsOneWidget);
    await tester.scrollUntilVisible(
      field('Chaves — uma por linha'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final lines = tester.widget<TextField>(field('Chaves — uma por linha'));
    expect(lines.minLines, 5);
    expect(lines.maxLines, isNull);
  });

  testWidgets('manual edit during recognition is not overwritten', (
    tester,
  ) async {
    final pending = Completer<ReceiptScan?>();
    await open(tester, (_) => pending.future);
    await tester.tap(find.text('Importar imagem'));
    await tester.pump();
    await tester.scrollUntilVisible(
      field('Chaves — uma por linha'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      field('Chaves — uma por linha'),
      '10 11 12 13 14 + 1 2',
    );
    final text = sample(5);
    pending.complete(ReceiptScan(parseReceiptObservations(text: text), text));
    await tester.pumpAndSettle();
    expect(value(tester, 'Chaves — uma por linha'), '10 11 12 13 14 + 1 2');
  });
}
