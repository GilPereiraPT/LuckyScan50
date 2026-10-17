import 'dart:ui';
import 'dart:math' as math;
import 'package:luckyscan50/domain/receipt_autofill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:luckyscan50/domain/receipt_ocr.dart';

// Transcription supplied in the task, NOT OCR output from the missing photos.
const referenceBets = [
  '06 20 29 32 48 + 04 06',
  '05 17 36 47 49 + 05 11',
  '22 26 43 45 47 + 03 09',
  '06 10 13 35 44 + 02 10',
  '02 06 13 20 32 + 03 10',
];
RecognizedText transcription(String text) => RecognizedText(
  text: text,
  blocks: [
    TextBlock(
      text: text,
      boundingBox: Rect.zero,
      recognizedLanguages: [],
      cornerPoints: [],
      lines: text
          .split('\n')
          .map(
            (line) => TextLine(
              text: line,
              elements: [],
              boundingBox: Rect.zero,
              recognizedLanguages: [],
              cornerPoints: [],
              confidence: null,
              angle: null,
            ),
          )
          .toList(),
    ),
  ],
);
void main() {
  test('game header must not terminate the betting section', () {
    final parsed = parseScannedReceipt(
      transcription('EUROMILHÕES COM M1LHÃO\n1.N 06 20 29 32 48\nE 04 06'),
    );
    expect(parsed.lines, [referenceBets[0]]);
  });
  test('N and E on the same physical row remain one bet', () {
    final parsed = parseScannedReceipt(
      transcription('1.N 06 20 29 32 48 E 04 06'),
    );
    expect(parsed.lines, [referenceBets[0]]);
  });
  test('explicit TOTAL permits trailing euro sign', () {
    final parsed = parseScannedReceipt(transcription('TOTAL 11,00 €'));
    expect(parsed.amount, '11,00');
  });
  test(
    'five user-transcribed bets and explicit metadata (not real image OCR)',
    () {
      final rows = List.generate(
        5,
        (i) => '${i + 1}.N ${referenceBets[i].replaceAll(' + ', ' E ')}',
      ).join('\n');
      final parsed = parseScannedReceipt(
        transcription(
          'EUROMILHÕES COM M1LHÃO\nCONCURSO 081\n09/10/2026\n5 AP SIMPLES\n$rows\nTOTAL 11,00 €\n782-00837480-199\n782-02213749-M1L',
        ),
      );
      expect(parsed.lines, referenceBets);
      expect(parsed.drawId, '081/2026');
      expect(parsed.drawDate, '2026-10-09');
      expect(parsed.expectedLines, 5);
      expect(parsed.amount, '11,00');
      expect(parsed.hasMilhao, isTrue);
      expect(parsed.code, '782-00837480-199');
      expect(parsed.milhaoCodes, isEmpty);
      expect(parsed.fullyParsed, isTrue);
    },
  );
  test('three of five preserve two missing slots', () {
    final rows = List.generate(
      3,
      (i) => '${i + 1}.N ${referenceBets[i].replaceAll(' + ', ' E ')}',
    ).join('\n');
    final parsed = parseReceiptObservations(text: '5 APOSTAS\n$rows');
    expect(parsed.lines, referenceBets.take(3));
    expect(parsed.bets.length, 5);
    expect(parsed.bets.where((b) => !b.complete).map((b) => b.index), [4, 5]);
    expect(parsed.fullyParsed, isFalse);
  });
  test('uncertain letters never silently become numbers', () {
    final p = parseReceiptObservations(text: '1.N O6 20 29 32 48 E 04 06');
    expect(p.lines, isEmpty);
    expect(p.bets.single.issues.join(' '), contains('O6'));
    expect(p.bets.single.stars, [4, 6]);
  });
  test('administrative text terminates a partial bet', () {
    final p = parseReceiptObservations(
      text:
          '1.N 06 20 29 32 48\nTOTAL 11,00 €\nE 04 06\n2.N 05 17 36 47 49 E 05 11',
    );
    expect(p.lines, [referenceBets[1]]);
    expect(p.bets.first.complete, isFalse);
  });
  test('same numbers on different bets allowed, repeated index uncertain', () {
    expect(
      parseReceiptObservations(
        text: '1.N 06 20 29 32 48 E 04 06\n2.N 06 20 29 32 48 E 04 06',
      ).lines.length,
      2,
    );
    expect(
      parseReceiptObservations(
        text: '1.N 06 20 29 32 48 E 04 06\n1.N 06 20 29 32 48 E 04 06',
      ).lines,
      isEmpty,
    );
  });
  test('out of range and duplicate values rejected', () {
    for (final row in [
      '1.N 06 06 29 32 48 E 04 06',
      '1.N 06 20 29 32 51 E 04 06',
      '1.N 06 20 29 32 48 E 04 13',
    ]) {
      expect(parseReceiptObservations(text: row).lines, isEmpty);
    }
  });
  test(
    'administrative numbers and M1L identifier are not participation codes',
    () {
      final p = parseReceiptObservations(
        text: '782-02213749-M1L\n06 20 29 32 48 04 06\nTOTAL 11,00 €',
      );
      expect(p.lines, isEmpty);
      expect(p.milhaoCodes, isEmpty);
      expect(p.code, isNull);
      expect(p.hasMilhao, isFalse);
    },
  );
  test('strict dates, ambiguous dates and missing contest year', () {
    final p = parseReceiptObservations(text: 'CONCURSO 081\n31/02/2026');
    expect(p.drawId, isNull);
    expect(p.drawDate, isNull);
    expect(p.warnings, isNotEmpty);
    final a = parseReceiptObservations(
      text: 'CONCURSO 081\n09/10/2026\n10/10/2026',
    );
    expect(a.drawId, isNull);
    expect(a.drawDate, isNull);
  });
  test('conflicting totals are uncertain and codes need an explicit label', () {
    final p = parseReceiptObservations(
      text: 'TOTAL 11,00 €\nTOTAL 22,00 €\nABC 12345',
    );
    expect(p.amount, isNull);
    expect(p.milhaoCodes, isEmpty);
    expect(
      parseReceiptObservations(text: 'CÓDIGO M1LHÃO: ABC 12345').milhaoCodes,
      ['ABC 12345'],
    );
  });
  test('shuffled geometric tokens reconstruct physical rows', () {
    final words = '1.N 06 20 29 32 48 E 04 06'.split(' ');
    final tokens = List.generate(
      words.length,
      (i) => ReceiptToken(words[i], 10 + i * 25.0, 20, 12),
    )..shuffle(math.Random(42));
    final p = parseReceiptObservations(
      text: 'unreliable block order',
      tokens: tokens,
    );
    expect(p.lines, [referenceBets[0]]);
    expect(p.strategy, 'geometry');
  });
  test('deskew handles observed ten-degree token baselines', () {
    final words = '1.N 06 20 29 32 48 E 04 06'.split(' '),
        a = 10 * math.pi / 180;
    final tokens = List.generate(words.length, (i) {
      final x = 10 + i * 25.0, y = 20.0;
      return ReceiptToken(
        words[i],
        x * math.cos(a) - y * math.sin(a),
        x * math.sin(a) + y * math.cos(a),
        12,
        angle: 10,
      );
    });
    final p = parseReceiptObservations(text: '', tokens: tokens);
    expect(p.lines, [referenceBets[0]]);
    expect(p.skewDegrees, 10);
  });
  test('contradictory geometry and native text require confirmation', () {
    final p = parseReceiptObservations(
      text: '1.N 05 17 36 47 49 E 05 11',
      tokens: [const ReceiptToken('1.N 06 20 29 32 48 E 04 06', 20, 20, 12)],
    );
    expect(p.lines, isEmpty);
    expect(p.warnings.join(' '), contains('discordam'));
  });
  test('autofill protects manual and in-flight edits, permits OCR refresh', () {
    final p = parseReceiptObservations(
      text: '1.N 06 20 29 32 48 E 04 06\nTOTAL 11,00 €',
    );
    final first = receiptAutofill(p, current: {}, atStart: {}, previousOcr: {});
    expect(first['lines'], referenceBets[0]);
    expect(first['cost'], '11,00');
    expect(
      receiptAutofill(
        p,
        current: {'lines': 'manual'},
        atStart: {'lines': 'manual'},
        previousOcr: {},
      ).containsKey('lines'),
      isFalse,
    );
    expect(
      receiptAutofill(
        p,
        current: {'lines': 'new edit'},
        atStart: {},
        previousOcr: {},
      ).containsKey('lines'),
      isFalse,
    );
    expect(
      receiptAutofill(
        p,
        current: first,
        atStart: first,
        previousOcr: first,
      )['lines'],
      referenceBets[0],
    );
  });
}
