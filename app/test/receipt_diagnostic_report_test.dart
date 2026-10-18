import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/data/receipt_diagnostic_report.dart';
import 'package:luckyscan50/data/receipt_scanner.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

void main() {
  test(
    'export preserves crop results, uncertainty, provenance and timing without images',
    () {
      const initial = ScannedReceipt(
        bets: [],
        rows: ['vertical word'],
        warnings: [],
        observations: [ReceiptToken('O000DNOOO0', 10, 100, 698, angle: 90)],
      );
      const finalReceipt = ScannedReceipt(
        bets: [
          ParsedBet(1, [1, 2, 3, 4, 5], [1, 2], []),
          ParsedBet(2, [6], [], ['Missing stars']),
        ],
        rows: [],
        warnings: ['Conflict'],
      );
      const crop = BetCrop(2, CropBox(0, 20, 600, 80));
      const candidate = ValueEvidence(
        'N',
        0,
        6,
        'O6',
        'row-2',
        betIndex: 2,
        bounds: CropBox(0, 20, 600, 80),
        validation: 'conflict',
        correction: 'O→0',
        conflict: true,
      );
      const result = MultiPassResult(
        initial,
        finalReceipt,
        CropPlan([], [], ['Review']),
        [
          CropPass('row-2', crop, 1, OcrFrame('N O6 E', [], elapsedMs: 7), 12),
          CropPass('row-2-retry', crop, 2, null, 4, error: 'PlatformException'),
        ],
        [
          BetEvidence(
            2,
            [candidate],
            ['Conflict'],
            acceptedValues: [candidate],
          ),
        ],
        20,
      );
      const scan = ReceiptScan(
        finalReceipt,
        'FIRST PASS',
        imagePath: '/private/user/photo.jpg',
        initialReceipt: initial,
        multiPass: result,
        ocrMs: 10,
        parseMs: 30,
        phaseTimings: {'cleanup': 2, 'total': 44},
      );
      final report = receiptDiagnosticReport(
        scan,
        build: 'test',
        version: 'test',
      );
      final encoded = jsonEncode(report);
      expect(encoded, isNot(contains('/private/user')));
      expect(encoded, isNot(contains('photo.jpg')));
      expect(report['photographsIncluded'], false);
      expect(report['schemaVersion'], 3);
      final analysis = report['analysis'] as Map;
      expect(analysis['status'], 'review_required');
      expect(analysis['completeBets'], 1);
      expect(analysis['incompleteBets'], 1);
      expect(analysis['failedCropPasses'], 1);
      expect(encoded, contains('"validation":"conflict"'));
      expect(encoded, contains('"betIndex":2'));
      expect((report['timingsMs'] as Map)['phases'], {
        'cleanup': 2,
        'total': 44,
      });
      expect((report['initialPass'] as Map)['rawText'], 'FIRST PASS');
      expect((report['timingsMs'] as Map)['totalProcessing'], 44);
      final passes = report['cropPasses'] as List;
      expect((passes.first['result'] as Map)['rawText'], 'N O6 E');
      expect(passes.last['error'], 'PlatformException');
      final bets = (report['finalResult'] as Map)['bets'] as List;
      expect(bets.first['complete'], true);
      expect(bets.last['stars'], isEmpty);
      expect(bets.last['complete'], false);
      expect(encoded, contains('"conflict":true'));
      expect(encoded, contains('O→0'));
    },
  );
  test('recovery failure still exports initial OCR and failure', () {
    const first = ScannedReceipt(bets: [], rows: [], warnings: ['Uncertain']);
    const scan = ReceiptScan(
      first,
      'observed',
      initialReceipt: first,
      recoveryError: 'crop: PlatformException',
    );
    final report = receiptDiagnosticReport(
      scan,
      build: 'test',
      version: 'test',
    );
    expect(report['errors'], ['crop: PlatformException']);
    expect(
      (report['analysis'] as Map)['flags'],
      contains('recovery_exception'),
    );
    expect(report['cropPasses'], isEmpty);
    expect((report['initialPass'] as Map)['parsed'], isNotNull);
  });
}
