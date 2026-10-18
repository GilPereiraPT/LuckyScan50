import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/results_client.dart';

Map<String, dynamic> officialDraw() {
  const signatures = [
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
  return {
    'game': 'euromilhoes',
    'drawId': '083/2026',
    'date': '2026-10-16',
    'retrievedAt': '2026-10-17T03:00:19Z',
    'sourceUrl': 'https://www.jogossantacasa.pt/official-test-fixture',
    'status': 'complete',
    'numbers': [7, 15, 16, 22, 35],
    'stars': [4, 6],
    'tiers': [
      for (var i = 0; i < signatures.length; i++)
        <String, dynamic>{
          'tier': i + 1,
          'main': signatures[i][0],
          'stars': signatures[i][1],
          'amountCents': 100,
          'winnersPortugal': 0,
          'winnersTotal': 1,
        },
    ],
  };
}

Map<String, dynamic> copyDraw(Map<String, dynamic> draw) =>
    jsonDecode(jsonEncode(draw)) as Map<String, dynamic>;

void main() {
  test(
    'accepts official-shaped complete draw and explicit timezone offsets',
    () {
      for (final timestamp in [
        '2026-10-17T03:00:19Z',
        '2026-10-17T04:00:19+01:00',
        '2026-10-17T04:00:19.123456+0100',
      ]) {
        expect(
          () => validateDraw({...officialDraw(), 'retrievedAt': timestamp}),
          returnsNormally,
        );
      }
    },
  );

  test(
    'rejects impossible or noncanonical draw dates and mismatched years',
    () {
      for (final date in ['2026-02-30', '2026-10-16T00:00:00', '2025-10-16']) {
        expect(
          () => validateDraw({...officialDraw(), 'date': date}),
          throwsFormatException,
          reason: date,
        );
      }
      expect(
        () => validateDraw({...officialDraw(), 'drawId': '000/2026'}),
        throwsFormatException,
      );
    },
  );

  test(
    'rejects retrieval timestamps without timezone or normalized overflow',
    () {
      for (final timestamp in [
        '2026-10-17T03:00:19',
        '2026-02-30T03:00:19Z',
        '2026-10-17T25:00:19Z',
        '2026-10-17T03:60:19Z',
        '2026-10-17T03:00:60Z',
        '2026-10-17T03:00:19+24:00',
        '2026-10-17T03:00:19+01:60',
      ]) {
        expect(
          () => validateDraw({...officialDraw(), 'retrievedAt': timestamp}),
          throwsFormatException,
          reason: timestamp,
        );
      }
    },
  );

  test('rejects source credentials, missing host and insecure transport', () {
    for (final source in [
      'https://user:secret@example.org/results',
      'https:///results',
      'http://www.jogossantacasa.pt/results',
    ]) {
      expect(
        () => validateDraw({...officialDraw(), 'sourceUrl': source}),
        throwsFormatException,
      );
    }
  });

  test('rejects Portugal winners exceeding all winners', () {
    final row = officialDraw();
    (row['tiers'] as List).first['winnersPortugal'] = 2;
    expect(() => validateDraw(row), throwsFormatException);
  });

  test(
    'preserves explicit nulls for pending prizes but rejects missing fields',
    () {
      final pending = {...officialDraw(), 'status': 'numbers_confirmed'};
      for (final tier in pending['tiers'] as List) {
        tier['amountCents'] = null;
        tier['winnersPortugal'] = null;
        tier['winnersTotal'] = null;
      }
      expect(() => validateDraw(pending), returnsNormally);
      for (final field in ['amountCents', 'winnersPortugal', 'winnersTotal']) {
        final missing = copyDraw(pending);
        (missing['tiers'] as List).first.remove(field);
        expect(
          () => validateDraw(missing),
          throwsFormatException,
          reason: field,
        );
      }
    },
  );

  test('keeps unawarded prize null and rejects fabricated zero prize', () {
    final row = officialDraw();
    final first = (row['tiers'] as List).first;
    first['winnersTotal'] = 0;
    first['amountCents'] = null;
    expect(() => validateDraw(row), returnsNormally);
    first['amountCents'] = 0;
    expect(() => validateDraw(row), throwsFormatException);
  });

  test('malformed payload types produce controlled validation failures', () {
    for (final update in <Map<String, dynamic>>[
      {'drawId': 83},
      {'date': 20261016},
      {'retrievedAt': null},
      {'sourceUrl': []},
      {
        'numbers': [7, 15, 16, 22, '35'],
      },
      {'stars': null},
      {'tiers': []},
      {'tiers': List.filled(13, null)},
    ]) {
      expect(
        () => validateDraw({...officialDraw(), ...update}),
        throwsFormatException,
        reason: '$update',
      );
    }
  });

  test(
    'validates Milhao separately and preserves legacy missing prize amount',
    () {
      final row = {
        ...officialDraw(),
        'game': 'milhao',
        'drawId': '009/2026',
        'winningCode': 'PTM 09893',
      };
      row.remove('numbers');
      row.remove('stars');
      row.remove('tiers');
      expect(() => validateDraw(row), returnsNormally);
      expect(
        () => validateDraw({...row, 'winningCode': 9893}),
        throwsFormatException,
      );
      expect(
        () => validateDraw({...row, 'amountCents': -1}),
        throwsFormatException,
      );
    },
  );
}
