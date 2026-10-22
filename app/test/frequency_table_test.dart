import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/frequency_table.dart';
import 'package:luckyscan50/domain/wallet.dart';

void main() {
  testWidgets('sort frequencies and count participation in every contest', (
    tester,
  ) async {
    final receipt = Receipt(
      id: 'test',
      createdAt: '2026-10-19',
      source: 'manual',
      code: '',
      costCents: 500,
      lines: [
        BetLine([1, 2, 3, 4, 5], [1, 2]),
      ],
      drawIds: ['082/2026', '083/2026'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FrequencyTable(
              receipts: [receipt],
              draws: [
                {
                  'game': 'euromilhoes',
                  'drawId': '083/2026',
                  'status': 'numbers_confirmed',
                  'numbers': [7, 15, 16, 22, 35],
                  'stars': [4, 6],
                },
                {
                  'game': 'euromilhoes',
                  'drawId': '083/2026',
                  'status': 'complete',
                  'numbers': [7, 15, 16, 22, 35],
                  'stars': [4, 6],
                },
              ],
            ),
          ),
        ),
      ),
    );
    var officialTable = tester.widget<DataTable>(find.byType(DataTable));
    expect((officialTable.rows.first.cells[1].child as Text).data, '187');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(find.textContaining('1 concursos'), findsOneWidget);
    var table = tester.widget<DataTable>(find.byType(DataTable));
    expect((table.rows.first.cells[2].child as Text).data, '2');
    await tester.tap(find.text('Saídas'));
    await tester.pump();
    await tester.tap(find.text('Saídas'));
    await tester.pump();
    table = tester.widget<DataTable>(find.byType(DataTable));
    expect((table.rows.first.cells[0].child as Text).data, '7');
    await tester.tap(find.text('Estrelas'));
    await tester.pump();
    table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.rows.length, 12);
    expect((table.rows.first.cells[0].child as Text).data, '4');
    expect(tester.takeException(), isNull);
  });
}
