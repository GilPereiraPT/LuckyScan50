import 'dart:convert';
import 'dart:io';
import '../app/lib/domain/wallet.dart';

void main() {
  final lines = List.generate(500, (_) => BetLine([1, 2, 3, 4, 5], [1, 2]));
  final receipts = List.generate(
    20,
    (i) => Receipt(
      id: 'benchmark-$i',
      createdAt: '2026-10-18',
      source: 'manual',
      code: '',
      costCents: 100000,
      lines: lines,
      drawIds: ['083/2026'],
    ),
  );
  final results = <Map<String, dynamic>>[
    {
      'game': 'euromilhoes',
      'drawId': '083/2026',
      'status': 'complete',
      'numbers': [1, 2, 3, 4, 5],
      'stars': [1, 2],
      'tiers': List.generate(13, (_) => {'amountCents': 100}),
    },
  ];
  for (var i = 0; i < 10; i++) {
    finances(receipts, results);
  }
  final samples = <int>[];
  for (var sample = 0; sample < 7; sample++) {
    final clock = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      finances(receipts, results);
    }
    clock.stop();
    samples.add(clock.elapsedMicroseconds);
  }
  samples.sort();
  final payload = jsonEncode(receipts.map((r) => r.toJson()).toList());
  stdout.writeln(
    jsonEncode({
      'syntheticReceipts': 20,
      'linesEach': 500,
      'verificationLinesPerSample': 200000,
      'medianMicroseconds': samples[3],
      'samplesMicroseconds': samples,
      'jsonUtf8Bytes': utf8.encode(payload).length,
      'rssBytesAtEnd': ProcessInfo.currentRss,
      'totals': finances(receipts, results),
    }),
  );
}
