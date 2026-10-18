import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/receipt_multipass.dart';
import 'package:luckyscan50/domain/receipt_parser.dart';

// The strings/angles/heights are reported by the user. X/Y coordinates below
// are CONTROLLED TEST GEOMETRY, not an export from the missing real photos.
const verticalWords = [
  'ZWZWZWZwZu',
  'O000DNOOO0',
  'OTOLONMONUM',
  'UOrNOrOr',
  'OONTODO000',
];
List<ReceiptToken> diagnosticTokens({bool anchors = true}) => [
  for (var i = 0; i < 5; i++)
    ReceiptToken(
      verticalWords[i],
      150 + i * 55,
      400,
      685 + i * 3.0,
      angle: 90,
      width: 26,
    ),
  if (anchors)
    for (var i = 0; i < 5; i++) ...[
      ReceiptToken('${i + 1}.N', 40, 130 + i * 120, 24, width: 45),
      ReceiptToken('32', 600, 130 + i * 120, 24, width: 28),
      ReceiptToken('48', 650, 130 + i * 120, 24, width: 28),
    ],
];
OcrFrame fullFrame() =>
    OcrFrame('EUROMILHÕES COM M1LHÃO\n5 AP SIMPLES', diagnosticTokens());
OcrFrame cropFrame(String text) => OcrFrame(text, const []);
void main() {
  test('tall 90-degree words identify columns but never become numbers', () {
    final plan = planBetCrops(diagnosticTokens(), 1000, 1000);
    expect(plan.verticalElements.length, 5);
    expect(plan.rows.length, 5);
    expect(plan.rows.map((r) => r.index), [1, 2, 3, 4, 5]);
    for (final row in plan.rows) {
      expect(row.box.right, 1000); // Keep unrecognized stars within the crop.
      expect(row.box.height, greaterThan(24));
      expect(row.box.left, greaterThanOrEqualTo(0));
    }
  });
  test(
    'a printed expected count does not invent crop rows without anchors',
    () async {
      final initial = OcrFrame(
        'EUROMILHÕES\n5 AP SIMPLES',
        diagnosticTokens(anchors: false),
      );
      var calls = 0;
      final result = await recoverReceiptRows(
        initial: initial,
        width: 1000,
        height: 1000,
        recognizeCrop: (row, scale) async {
          calls++;
          return cropFrame('');
        },
      );
      expect(result.plan.rows, isEmpty);
      expect(calls, 0);
      expect(result.receipt.lines, isEmpty);
    },
  );
  test(
    'controlled row recognitions recover five complete bets and ten observed stars',
    () async {
      final calls = <int>[];
      final result = await recoverReceiptRows(
        initial: fullFrame(),
        width: 1000,
        height: 1000,
        recognizeCrop: (row, scale) async {
          calls.add(row.index);
          return cropFrame('${row.index}.N 01 02 03 32 48 E 04 06');
        },
      );
      expect(calls, [1, 2, 3, 4, 5]);
      expect(result.receipt.lines.length, 5);
      expect(result.receipt.bets.fold(0, (n, b) => n + b.stars.length), 10);
      expect(
        result.evidence.every(
          (b) =>
              b.candidates.any((v) => v.kind == 'E' && v.pass.contains('row-')),
        ),
        isTrue,
      );
      expect(result.initial.lines, isEmpty);
      expect(result.passes.length, 5);
    },
  );
  test(
    'empty recrops cannot be filled with reference ticket numbers',
    () async {
      final result = await recoverReceiptRows(
        initial: fullFrame(),
        width: 1000,
        height: 1000,
        recognizeCrop: (row, scale) async => cropFrame(verticalWords.join(' ')),
      );
      expect(result.receipt.lines, isEmpty);
      expect(result.passes.length, 10);
      expect(result.receipt.bets.every((b) => !b.complete), isTrue);
    },
  );
  test('second scale is attempted only for unresolved crops', () async {
    final scales = <double>[];
    final result = await recoverReceiptRows(
      initial: fullFrame(),
      width: 1000,
      height: 1000,
      recognizeCrop: (row, scale) async {
        scales.add(scale);
        return cropFrame(
          scale == 1
              ? '${row.index}.N 01 02 03 32 48'
              : '${row.index}.N 01 02 03 32 48 E 04 06',
        );
      },
    );
    expect(scales, [1, 2, 1, 2, 1, 2, 1, 2, 1, 2]);
    expect(result.receipt.lines.length, 5);
  });
  test(
    'O/0 correction is restricted to anchored numeric fields and attributed per value',
    () async {
      final result = await recoverReceiptRows(
        initial: fullFrame(),
        width: 1000,
        height: 1000,
        recognizeCrop: (row, scale) async =>
            cropFrame('${row.index}.N O1 02 03 32 48 E O4 06'),
      );
      expect(result.receipt.lines.length, 5);
      final values = result.evidence.first.candidates
          .where((e) => e.pass.startsWith('row-'))
          .toList();
      expect(values.where((e) => e.correction != null).map((e) => e.raw), [
        'O1',
        'O4',
      ]);
      expect(result.receipt.warnings.join(' '), contains('O→0'));
    },
  );
  test(
    'compatible complete number and star groups can come from separate passes',
    () async {
      final result = await recoverReceiptRows(
        initial: fullFrame(),
        width: 1000,
        height: 1000,
        recognizeCrop: (row, scale) async => cropFrame(
          scale == 1
              ? '${row.index}.N 01 02 03 32 48'
              : '${row.index}.N\nE 04 06',
        ),
      );
      expect(result.receipt.lines.length, 5);
      final values = result.evidence.first.candidates;
      expect(values.any((v) => v.kind == 'N' && v.pass == 'row-1@1x'), isTrue);
      expect(values.any((v) => v.kind == 'E' && v.pass == 'row-1@2x'), isTrue);
    },
  );
  test(
    'a neighbouring explicitly numbered row cannot fill this crop',
    () async {
      final result = await recoverReceiptRows(
        initial: fullFrame(),
        width: 1000,
        height: 1000,
        recognizeCrop: (row, scale) async =>
            cropFrame('9.N 01 02 03 32 48 E 04 06'),
      );
      expect(result.receipt.lines, isEmpty);
    },
  );
  test('crop failures preserve initial text and partial bets', () async {
    final initial = fullFrame();
    final result = await recoverReceiptRows(
      initial: initial,
      width: 1000,
      height: 1000,
      recognizeCrop: (row, scale) async =>
          throw StateError('simulated failure'),
    );
    expect(result.initial.observations.length, initial.tokens.length);
    expect(result.passes.every((p) => p.error == 'StateError'), isTrue);
    expect(result.receipt.lines, isEmpty);
  });
  test(
    'vertical administrative elements outside the betting zone do not trigger recovery',
    () {
      final tokens = [
        const ReceiptToken('1.N', 100, 100, 20, width: 30),
        const ReceiptToken('TOTAL', 100, 800, 690, angle: 90, width: 25),
      ];
      expect(planBetCrops(tokens, 1000, 1500).verticalElements, isEmpty);
    },
  );
  test(
    'conflicting complete full-frame and crop reads require manual confirmation',
    () async {
      final tokens = [
        for (var i = 0; i < 5; i++)
          ReceiptToken(
            '${i + 1}.N 01 02 03 32 48 E 04 06',
            450,
            130 + i * 120,
            24,
            width: 900,
          ),
        ...diagnosticTokens(anchors: false),
      ];
      final result = await recoverReceiptRows(
        initial: OcrFrame('EUROMILHÕES', tokens),
        width: 1000,
        height: 1000,
        recognizeCrop: (row, scale) async =>
            cropFrame('${row.index}.N 07 08 09 32 48 E 04 06'),
      );
      expect(result.initial.lines.length, 5);
      expect(result.receipt.lines, isEmpty);
      expect(result.evidence.every((e) => e.acceptedValues.isEmpty), isTrue);
      expect(
        result.evidence.every((e) => e.issues.join(' ').contains('Conflito')),
        isTrue,
      );
    },
  );
  test(
    'geometric row association without a printed index remains uncertain',
    () async {
      final tokens = [
        const ReceiptToken('N', 40, 130, 24, width: 30),
        const ReceiptToken('32', 600, 130, 24, width: 28),
        const ReceiptToken('48', 650, 130, 24, width: 28),
        const ReceiptToken('O000DNOOO0', 200, 150, 200, angle: 90, width: 20),
      ];
      final result = await recoverReceiptRows(
        initial: OcrFrame('EUROMILHÕES', tokens),
        width: 1000,
        height: 1000,
        recognizeCrop: (row, scale) async =>
            cropFrame('N 01 02 03 32 48 E 04 06'),
      );
      expect(result.receipt.lines, isEmpty);
      expect(
        result.receipt.bets.single.issues.join(' '),
        contains('Índice geométrico'),
      );
    },
  );
  test(
    'original full-frame metadata survives an orientation pass with missing metadata',
    () async {
      final metadata = parseReceiptObservations(
        text:
            'EUROMILHÕES COM M1LHÃO\nTOTAL 11,00 €\nCONCURSO 081/2026\n782-00837480-199',
      );
      final result = await recoverReceiptRows(
        initial: fullFrame(),
        width: 1000,
        height: 1000,
        metadata: metadata,
        recognizeCrop: (row, scale) async =>
            cropFrame('${row.index}.N 01 02 03 32 48 E 04 06'),
      );
      expect(result.receipt.code, '782-00837480-199');
      expect(result.receipt.amount, '11,00');
      expect(result.receipt.drawId, '081/2026');
      expect(result.receipt.hasMilhao, isTrue);
    },
  );
}
