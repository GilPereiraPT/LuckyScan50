import 'dart:math' as math;
import 'receipt_evidence.dart';
import 'receipt_geometry.dart';
import 'receipt_ne_lines.dart';
import 'receipt_parser.dart';

final _numbered = RegExp(
  r'^\s*(\d{1,2})\s*[.)]?\s*N(?![A-Z])\s*[:.]?\s*(.*)$',
  caseSensitive: false,
);
final _marker = RegExp(
  r'^\s*(?:(\d{1,2})\s*[.)]?\s*)?([NE])(?![A-Z])\s*[:.]?\s*(.*)$',
  caseSensitive: false,
);

bool _horizontal(ReceiptToken t) =>
    t.height > 0 &&
    t.height.isFinite &&
    t.x.isFinite &&
    t.y.isFinite &&
    t.angle.isFinite &&
    horizontalReceiptAngle(t.angle).abs() <= 20 &&
    !verticalReceiptToken(t);

/// Split only an observed N/E prefix from its own observed numeric tail.
/// Relative character widths locate the prefix when ML Kit merges the line.
List<ReceiptToken> _markers(List<ReceiptToken> tokens) {
  final result = <ReceiptToken>[];
  for (final token in tokens) {
    final match = _horizontal(token) ? _marker.firstMatch(token.text) : null;
    if (match == null) {
      result.add(token);
      continue;
    }
    final tail = match[3]!.trim();
    final label = '${match[1] == null ? '' : '${match[1]}.'}${match[2]}'
        .toUpperCase();
    if (tail.isEmpty) {
      result.add(
        ReceiptToken(
          label,
          token.x,
          token.y,
          token.height,
          width: token.width,
          angle: token.angle,
        ),
      );
      continue;
    }
    final prefixLength = token.text.lastIndexOf(tail);
    final width = token.width > 0
        ? token.width
        : token.height * token.text.length * .55;
    final prefixWidth = width * prefixLength / token.text.length;
    final left = token.x - width / 2;
    final labelX = left + prefixWidth / 2;
    final tailX = left + (prefixWidth + width) / 2;
    final slope = math.tan(horizontalReceiptAngle(token.angle) * math.pi / 180);
    result.add(
      ReceiptToken(
        label,
        labelX,
        token.y + slope * (labelX - token.x),
        token.height,
        width: prefixWidth,
        angle: token.angle,
      ),
    );
    result.add(
      ReceiptToken(
        tail,
        tailX,
        token.y + slope * (tailX - token.x),
        token.height,
        width: width - prefixWidth,
        angle: token.angle,
      ),
    );
  }
  return result;
}

class NumberedBetReading {
  const NumberedBetReading(this.bet, this.evidence);
  final ParsedBet bet;
  final List<ValueEvidence> evidence;
}

NumberedBetReading _read(
  int index,
  ReceiptToken n,
  List<ReceiptToken> tokens,
  CropBox bounds,
  String pass,
) {
  final slope = math.tan(horizontalReceiptAngle(n.angle) * math.pi / 180);
  double baseline(ReceiptToken t) => t.y - slope * (t.x - n.x);
  final es = tokens
      .where(
        (t) =>
            t.text == 'E' &&
            _horizontal(t) &&
            baseline(t) > n.y + n.height * .35 &&
            baseline(t) < n.y + n.height * 3 &&
            baseline(t) < bounds.bottom &&
            ((t.x + t.width / 2) - (n.x + n.width / 2)).abs() <= n.height * 1.5,
      )
      .toList();
  final e = es.length == 1 ? es.single : null;
  String digits(ReceiptToken anchor) {
    final row =
        tokens
            .where(
              (t) =>
                  !identical(t, anchor) &&
                  _horizontal(t) &&
                  t.x - t.width / 2 >=
                      anchor.x + anchor.width / 2 - n.height * .05 &&
                  (baseline(t) - baseline(anchor)).abs() <=
                      math.min(t.height, anchor.height) * .45 &&
                  (e == null ||
                      (baseline(t) - baseline(anchor)).abs() <
                          (baseline(t) - baseline(identical(anchor, n) ? e : n))
                              .abs()),
            )
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));
    return row.map((t) => t.text).join(' ');
  }

  final rawN = digits(n), rawE = e == null ? '' : digits(e);
  return _reading(index, rawN, rawE, pass, bounds, [
    if (es.length > 1) 'Linha E ambígua; confirmar associação',
  ]);
}

NumberedBetReading _reading(
  int index,
  String rawN,
  String rawE,
  String pass,
  CropBox bounds,
  List<String> issues,
) {
  final numbers = NeLineDigits.parse(rawN, stars: false);
  final stars = NeLineDigits.parse(rawE, stars: true);
  final evidence = <ValueEvidence>[];
  for (final group in [
    (kind: 'N', raw: rawN, values: numbers),
    (kind: 'E', raw: rawE, values: stars),
  ]) {
    if (group.values == null) continue;
    final digits = group.raw.replaceAll(RegExp(r'\s+'), '');
    for (var i = 0; i < group.values!.length; i++) {
      evidence.add(
        ValueEvidence(
          group.kind,
          i,
          group.values![i],
          digits.substring(i * 2, i * 2 + 2),
          pass,
          betIndex: index,
          bounds: bounds,
        ),
      );
    }
  }
  return NumberedBetReading(
    ParsedBet(index, numbers ?? [], stars ?? [], [
      ...issues,
      if (numbers == null) 'Cinco números distintos entre 1 e 50 em falta',
      if (stars == null) 'Duas estrelas distintas entre 1 e 12 em falta',
    ]),
    evidence,
  );
}

/// Read a bounded crop independently. An explicit different index is rejected.
/// An isolated N is allowed only because the original crop has a printed index.
NumberedBetReading? _cropReading(OcrFrame frame, BetCrop crop, String pass) {
  final tokens = _markers(frame.tokens);
  final ns = tokens
      .where(
        (t) => _horizontal(t) && RegExp(r'^(?:\d{1,2}\.)?N$').hasMatch(t.text),
      )
      .toList();
  if (ns.isNotEmpty) {
    if (ns.length != 1) return null;
    final match = _numbered.firstMatch(ns.single.text);
    if (match != null && int.parse(match[1]!) != crop.index) return null;
    final right = tokens.map((t) => t.x + t.width / 2).reduce(math.max);
    final bottom = tokens.map((t) => t.y + t.height).reduce(math.max);
    return _read(
      crop.index,
      ns.single,
      tokens,
      CropBox(0, 0, right, bottom),
      pass,
    );
  }
  final rows = frame.rows.isEmpty ? frame.text.split('\n') : frame.rows;
  String? n, e;
  bool nextN = false, nextE = false;
  for (final raw in rows) {
    final text = raw.trim().toUpperCase();
    if (text.isEmpty || RegExp(r'^={4,}$').hasMatch(text)) continue;
    final match = _marker.firstMatch(text);
    if (match != null) {
      if (match[1] != null && int.parse(match[1]!) != crop.index) return null;
      if (match[2] == 'N') {
        if (n != null) return null;
        n = match[3]!;
        nextN = n.trim().isEmpty;
      } else {
        if (n == null || e != null) return null;
        e = match[3]!;
        nextN = false;
        nextE = e.trim().isEmpty;
      }
    } else if (nextN) {
      n = text;
      nextN = false;
    } else if (nextE) {
      e = text;
      nextE = false;
    } else {
      return null;
    }
  }
  if (n == null) return null;
  return _reading(crop.index, n, e ?? '', pass, crop.box, []);
}

/// Priority path for physical tickets: numbered N anchors, then N/E rows.
/// It never uses the date, amount or arbitrary footer digits as bet values.
Future<MultiPassResult?> recoverNumberedBets({
  required OcrFrame initial,
  required double width,
  required double height,
  required RecognizeBetCrop recognizeCrop,
  ScannedReceipt? metadata,
  List<CropBox> rules = const [],
}) async {
  final clock = Stopwatch()..start();
  final tokens = _markers(initial.tokens);
  final printed = tokens
      .where((t) => _horizontal(t) && _numbered.hasMatch(t.text))
      .toList();
  // Split OCR elements such as "1." + "N" are assembled by the crop planner.
  final separators = tokens.where(
    (t) => _horizontal(t) && RegExp(r'^[=\s]{4,}$').hasMatch(t.text),
  );
  final plan = planBetCrops(
    tokens,
    width,
    height,
    rules: [...rules, ...separators.map(receiptTokenBox)],
  );
  if (printed.isEmpty && !plan.rows.any((r) => r.printedIndex)) return null;
  if (plan.rows.isEmpty) return null;
  final geometryMs = clock.elapsedMilliseconds;
  final meta = metadata ?? initial.parse();
  final expected = math
      .max(plan.expectedLines ?? 0, meta.expectedLines ?? 0)
      .clamp(1, maxReceiptBets)
      .toInt();
  final bets = <int, ParsedBet>{};
  final observations = <int, List<ValueEvidence>>{};
  final passes = <CropPass>[];
  for (final crop in plan.rows.where((r) => r.printedIndex)) {
    final local = tokens
        .where((t) => t.y >= crop.box.top && t.y <= crop.box.bottom)
        .toList();
    final ns = local.where((t) {
      if (!_horizontal(t)) return false;
      final match = _numbered.firstMatch(t.text);
      return match != null && int.parse(match[1]!) == crop.index;
    }).toList();
    final split = local.where((t) => _horizontal(t) && t.text == 'N').toList();
    final n = ns.length == 1
        ? ns.single
        : ns.isEmpty && split.length == 1
        ? split.single
        : null;
    final reading = n == null
        ? null
        : _read(crop.index, n, local, crop.box, 'numbered-full-frame');
    final candidates = <ValueEvidence>[...?reading?.evidence];
    var bet =
        reading?.bet ??
        ParsedBet(crop.index, const [], const [], const [
          'Aposta não reconhecida',
        ]);
    final duplicate =
        printed.where((t) {
          final match = _numbered.firstMatch(t.text)!;
          return int.parse(match[1]!) == crop.index &&
              (plan.zone == null || t.y < plan.zone!.bottom);
        }).length >
        1;
    if (duplicate) {
      bet = ParsedBet(crop.index, bet.numbers, bet.stars, [
        ...bet.issues,
        'Identificador de aposta repetido',
      ]);
    }
    if (!duplicate &&
        !bet.complete &&
        !bet.issues.any((issue) => issue.contains('ambígua'))) {
      for (final scale in [1.0, 2.0]) {
        final pass = 'numbered-row-${crop.index}@${scale.toInt()}x';
        final timer = Stopwatch()..start();
        try {
          final frame = await recognizeCrop(crop, scale);
          passes.add(
            CropPass(pass, crop, scale, frame, timer.elapsedMilliseconds),
          );
          final next = _cropReading(frame, crop, pass);
          if (next == null) continue;
          candidates.addAll(next.evidence);
          final conflict =
              (bet.numbers.length == 5 &&
                  next.bet.numbers.length == 5 &&
                  bet.numbers.join(',') != next.bet.numbers.join(',')) ||
              (bet.stars.length == 2 &&
                  next.bet.stars.length == 2 &&
                  bet.stars.join(',') != next.bet.stars.join(','));
          if (conflict) {
            bet = ParsedBet(crop.index, bet.numbers, bet.stars, [
              'Leituras OCR contraditórias',
            ]);
            break;
          }
          final numbers = next.bet.numbers.isNotEmpty
              ? next.bet.numbers
              : bet.numbers;
          final stars = next.bet.stars.isNotEmpty ? next.bet.stars : bet.stars;
          bet = ParsedBet(crop.index, numbers, stars, [
            ...next.bet.issues.where((issue) => issue.contains('ambígua')),
            if (numbers.length != 5)
              'Cinco números distintos entre 1 e 50 em falta',
            if (stars.length != 2)
              'Duas estrelas distintas entre 1 e 12 em falta',
          ]);
          if (bet.complete) break;
        } catch (error) {
          passes.add(
            CropPass(
              pass,
              crop,
              scale,
              null,
              timer.elapsedMilliseconds,
              error: error.runtimeType.toString(),
            ),
          );
        }
      }
    }
    bets[crop.index] = bet;
    observations[crop.index] = candidates;
  }
  final ordered = [
    for (var index = 1; index <= expected; index++)
      bets[index] ??
          ParsedBet(index, const [], const [], const [
            'Aposta não reconhecida',
          ]),
  ];
  final warnings = [
    ...meta.warnings.where((w) => !w.startsWith('Leitura incompleta:')),
    ...plan.warnings,
    if (ordered.any((b) => !b.complete))
      'Leitura incompleta: confirmar todas as $expected apostas.',
  ];
  final receipt = ScannedReceipt(
    bets: ordered,
    rows: meta.rows,
    warnings: warnings,
    code: meta.code,
    amount: meta.amount,
    expectedLines: expected,
    game: meta.game,
    drawDate: meta.drawDate,
    drawId: meta.drawId,
    hasMilhao: meta.hasMilhao,
    milhaoCodes: meta.milhaoCodes,
    tokenCount: initial.tokens.length,
    skewDegrees: meta.skewDegrees,
    strategy: 'numbered-n-e',
    observations: initial.tokens,
  );
  return MultiPassResult(
    meta,
    receipt,
    plan,
    passes,
    [
      for (final bet in ordered)
        BetEvidence(
          bet.index,
          observations[bet.index] ?? [],
          bet.issues,
          acceptedValues: bet.complete
              ? [
                  for (final kind in ['N', 'E'])
                    for (
                      var position = 0;
                      position < (kind == 'N' ? 5 : 2);
                      position++
                    )
                      (observations[bet.index] ?? []).lastWhere(
                        (v) =>
                            v.kind == kind &&
                            v.position == position &&
                            v.value ==
                                (kind == 'N'
                                    ? bet.numbers
                                    : bet.stars)[position],
                      ),
                ]
              : [],
        ),
    ],
    clock.elapsedMilliseconds,
    geometryMs: geometryMs,
  );
}
