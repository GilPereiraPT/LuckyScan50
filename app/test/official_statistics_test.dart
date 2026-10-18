import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luckyscan50/data/official_statistics.dart';
import 'package:luckyscan50/data/official_statistics_page.dart';
import 'package:luckyscan50/data/results_client.dart';
import 'package:luckyscan50/data/wallet_store.dart';

// Synthetic contract fixture; never represented as the real official snapshot.
Map<String, dynamic> syntheticSnapshot() => {
  'schemaVersion': 1,
  'game': 'euromilhoes',
  'sourceUrl': 'https://www.jogossantacasa.pt/web/SCEstatisticas/',
  'sourceSha256': List.filled(64, 'a').join(),
  'updatedAt': '2026-10-17T03:00:00+01:00',
  'coverageStart': '2004-02-13',
  'snapshotReferenceVerified': false,
  for (final name in ['numbers', 'stars'])
    name: List.generate(
      name == 'numbers' ? 50 : 12,
      (i) => <String, dynamic>{
        'value': i + 1,
        'count': 100,
        'percentage': '10.00',
        'lastDrawId': '083/2026',
        'lastDate': '2026-10-16',
        'drawsSinceLast': 0,
        'eligibleDraws': 1000,
      },
    ),
};

class MemoryStore implements WalletStore {
  String? cache;
  @override
  Future<String?> setting(String key) async => cache;
  @override
  Future<void> setSetting(String key, String value) async {
    cache = value;
  }

  @override
  Future<List<Map<String, dynamic>>> results() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('snapshot preserves 50 numbers, 12 stars and published percentages', () {
    final data = syntheticSnapshot();
    (data['stars'] as List)[11]['percentage'] = '18.00';
    (data['stars'] as List)[11]['eligibleDraws'] = null;
    final result = OfficialStatistics.parse(data);
    expect(result.numbers, hasLength(50));
    expect(result.stars, hasLength(12));
    expect(result.stars.last.percentage, 18);
    expect(result.stars.last.eligibleDraws, isNull);
    expect(result.referenceVerified, isFalse);
  });
  test(
    'published decimal rounding is compared using exact rational arithmetic',
    () {
      final data = syntheticSnapshot();
      final row = (data['stars'] as List)[0];
      row['count'] = 107;
      row['eligibleDraws'] = 4000;
      row['percentage'] = '2.68';
      expect(OfficialStatistics.parse(data).stars.first.percentage, 2.68);
    },
  );
  test(
    'incomplete, duplicate, invalid percent and impossible date rejected',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (d) => (d['numbers'] as List).removeLast(),
        (d) => (d['stars'] as List)[11]['value'] = 1,
        (d) => (d['stars'] as List)[0]['percentage'] = 'NaN',
        (d) => (d['numbers'] as List)[0]['lastDate'] = '2026-02-30',
        (d) => d['updatedAt'] = '2026-10-17T03:00:00',
        (d) => d['updatedAt'] = '2026-02-30T03:00:00Z',
        (d) => (d['numbers'] as List)[0]['lastDrawId'] = '000/2026',
        (d) => (d['numbers'] as List)[0]['lastDrawId'] = '083/2025',
        (d) => (d['numbers'] as List)[0]['lastDate'] = '2026-10-18',
        (d) => (d['numbers'] as List)[0]['lastDate'] = null,
        (d) => (d['numbers'] as List)[0]['drawsSinceLast'] = null,
        (d) => (d['numbers'] as List)[0]['percentage'] = '11.00',
      ]) {
        final data = syntheticSnapshot();
        mutate(data);
        expect(() => OfficialStatistics.parse(data), throwsFormatException);
      }
    },
  );
  test(
    'rollback, conflicting same date and incomplete fetch preserve cache',
    () async {
      String? value;
      final cache = OfficialStatisticsCache(
        read: () async => value,
        write: (v) async => value = v,
      );
      await cache.accept({'available': true, 'data': syntheticSnapshot()});
      final before = value;
      final forged = syntheticSnapshot();
      (forged['numbers'] as List)[0]['count'] = 101;
      (forged['numbers'] as List)[0]['percentage'] = '10.10';
      (forged['numbers'] as List)[1]['count'] = 99;
      (forged['numbers'] as List)[1]['percentage'] = '9.90';
      await expectLater(
        cache.accept({'available': true, 'data': forged}),
        throwsFormatException,
      );
      expect(value, before);

      final older = syntheticSnapshot()
        ..['updatedAt'] = '2026-10-16T03:00:00+01:00';
      final conflict = syntheticSnapshot()
        ..['sourceSha256'] = List.filled(64, 'b').join();
      for (final response in [
        {'available': true, 'data': older},
        {'available': true, 'data': conflict},
        {'available': false, 'data': null},
      ]) {
        await expectLater(cache.accept(response), throwsFormatException);
        expect(value, before);
      }
    },
  );
  testWidgets(
    'offline screen preserves cached provenance after network failure on small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryStore()..cache = jsonEncode(syntheticSnapshot());
      final before = store.cache;
      final client = ResultsClient(
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: OfficialStatisticsPage(store: store, client: client),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-10-17T03:00:00+01:00'), findsOneWidget);
      expect(
        find.textContaining('confronto com a captura oficial'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Atualizar estatísticas'));
      await tester.pumpAndSettle();
      expect(store.cache, before);
      expect(
        find.textContaining('última cache continua disponível'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
