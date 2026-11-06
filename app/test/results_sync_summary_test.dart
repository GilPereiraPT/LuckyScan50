import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/results_sync_summary.dart';
import 'package:luckyscan50/domain/wallet.dart';

Map<String, dynamic> euroDraw(String id, {String? retrievedAt}) => {
  'game': 'euromilhoes',
  'drawId': id,
  'status': 'complete',
  'numbers': [10, 11, 12, 13, 14],
  'stars': [3, 4],
  'tiers': <dynamic>[],
  'retrievedAt': retrievedAt ?? '2026-11-06T00:00:00Z',
};

Map<String, dynamic> milhaoDraw(String id) => {
  'game': 'milhao',
  'drawId': id,
  'status': 'complete',
  'winningCode': 'ABC 12346',
  'amountCents': 100000000,
};

Receipt receipt(
  String id,
  List<String> euro, {
  List<String> milhao = const [],
}) => Receipt(
  id: id,
  createdAt: '2026-11-06T00:00:00Z',
  source: 'manual',
  code: '',
  costCents: 250,
  lines: [BetLine([1, 2, 3, 4, 5], [1, 2])],
  drawIds: euro,
  milhaoDrawIds: milhao,
  milhaoCodes: milhao.isEmpty ? [] : ['ABC 12345'],
);

void main() {
  test('a successful request does not claim missing results were updated', () {
    final receipts = [
      receipt('first', ['086/2026', '088/2026']),
      receipt('second', ['081/2026'], milhao: ['010/2026']),
    ];
    final stored = [euroDraw('081/2026')];
    final summary = summarizeResultsSync(
      previous: stored,
      current: stored,
      receipts: receipts,
    );
    expect(summary.changedDraws, 0);
    expect(summary.pendingDraws, [
      'Euromilhões 086/2026',
      'Euromilhões 088/2026',
      'M1lhão 010/2026',
    ]);
    expect(summary.message, contains('faltam resultados'));
    expect(summary.message, isNot(contains('Resultados atualizados')));
  });

  test('counts actual new draws and keeps remaining pending visible', () {
    final summary = summarizeResultsSync(
      previous: [euroDraw('081/2026')],
      current: [euroDraw('081/2026'), euroDraw('086/2026')],
      receipts: [receipt('first', ['086/2026', '088/2026'])],
    );
    expect(summary.changedDraws, 1);
    expect(summary.pendingDraws, ['Euromilhões 088/2026']);
    expect(summary.message, contains('1 resultado(s) novo(s)'));
    expect(summary.message, contains('088/2026'));
  });

  test('ignores retrieval metadata changes with no draw changes', () {
    final summary = summarizeResultsSync(
      previous: [euroDraw('086/2026', retrievedAt: '2026-11-05T00:00:00Z')],
      current: [euroDraw('086/2026', retrievedAt: '2026-11-06T00:00:00Z')],
      receipts: [receipt('first', ['086/2026'])],
    );
    expect(summary.changedDraws, 0);
    expect(summary.pendingDraws, isEmpty);
    expect(summary.message, contains('Não foram encontrados resultados novos'));
  });

  test('a separately confirmed M1lhão draw resolves the pending status', () {
    final results = [
      euroDraw('081/2026'),
      milhaoDraw('010/2026'),
    ];
    final summary = summarizeResultsSync(
      previous: results,
      current: results,
      receipts: [receipt('second', ['081/2026'], milhao: ['010/2026'])],
    );
    expect(summary.pendingDraws, isEmpty);
    expect(summary.unconfirmedPrizes, 0);
  });
}
