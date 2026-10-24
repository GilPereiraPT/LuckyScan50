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

// This parser is used only for a crop to the right of a known N/E marker.
// O/o has no alphabetic meaning in that numeric-only region.
({List<int>? values, List<ValueEvidence> evidence}) _lineReading(
  OcrFrame frame,
  BetCrop crop,
  String pass,
) {
  var raw = frame.text.trim();
  final marker = _marker.firstMatch(raw);
  if (marker != null) {
    if (marker[2]!.toUpperCase() != crop.kind ||
        (marker[1] != null && int.parse(marker[1]!) != crop.index)) {
      return (values: null, evidence: <ValueEvidence>[]);
    }
    raw = marker[3]!;
  }
  final normalized = raw.replaceAll(RegExp('[Oo]'), '0');
  final values = NeLineDigits.parse(normalized, stars: crop.kind == 'E');
  if (values == null) return (values: null, evidence: <ValueEvidence>[]);
  final digits = raw.replaceAll(RegExp(r'\s+'), '');
  return (
    values: values,
    evidence: [
      for (var i = 0; i < values.length; i++)
        ValueEvidence(
          crop.kind!,
          i,
          values[i],
          digits.substring(i * 2, i * 2 + 2),
          pass,
          correction:
              RegExp('[Oo]').hasMatch(digits.substring(i * 2, i * 2 + 2))
              ? 'O→0 em linha numérica'
              : null,
          betIndex: crop.index,
          bounds: crop.box,
        ),
    ],
  );
}

double _middle(Iterable<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

/// The full-image pass locates markers only. Every numeric N/E line is then
/// recognized separately, in order, even if full-image OCR looked complete.
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
  final separators = tokens.where(
    (t) => _horizontal(t) && RegExp(r'^[=\s]{4,}$').hasMatch(t.text),
  );
  final plan = planBetCrops(
    tokens,
    width,
    height,
    rules: [...rules, ...separators.map(receiptTokenBox)],
  );
  final rows = plan.rows.where((r) => r.printedIndex).toList();
  if (rows.isEmpty) return null;
  final geometryMs = clock.elapsedMilliseconds;
  final meta = metadata ?? initial.parse();
  final expected = math
      .max(plan.expectedLines ?? 0, meta.expectedLines ?? 0)
      .clamp(1, maxReceiptBets)
      .toInt();
  final anchors = <int, ReceiptToken>{};
  final duplicates = <int>{};
  for (final row in rows) {
    final ns = tokens.where((t) {
      if (!_horizontal(t) || t.y < row.box.top || t.y > row.box.bottom) {
        return false;
      }
      final m = _numbered.firstMatch(t.text);
      return m != null && int.parse(m[1]!) == row.index;
    }).toList();
    if (ns.length == 1) {
      anchors[row.index] = ns.single;
    } else if (ns.length > 1) {
      duplicates.add(row.index);
    } else {
      final split = tokens
          .where(
            (t) =>
                _horizontal(t) &&
                t.text == 'N' &&
                t.y >= row.box.top &&
                t.y <= row.box.bottom,
          )
          .toList();
      if (split.length == 1) anchors[row.index] = split.single;
    }
  }
  // Repeated printed identifiers are never silently reassigned.
  for (final index in anchors.keys) {
    final matches = tokens.where((t) {
      final m = _horizontal(t) ? _numbered.firstMatch(t.text) : null;
      return m != null &&
          int.parse(m[1]!) == index &&
          (plan.zone == null ||
              (t.y >= plan.zone!.top && t.y <= plan.zone!.bottom));
    });
    if (matches.length > 1) duplicates.add(index);
  }
  final orderedAnchors = anchors.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final pitches = <double>[
    for (var i = 1; i < orderedAnchors.length; i++)
      if (orderedAnchors[i].value.y > orderedAnchors[i - 1].value.y)
        (orderedAnchors[i].value.y - orderedAnchors[i - 1].value.y) /
            (orderedAnchors[i].key - orderedAnchors[i - 1].key),
  ];
  final bets = <int, ParsedBet>{};
  final observations = <int, List<ValueEvidence>>{};
  final passes = <CropPass>[];
  for (final row in rows) {
    final n = anchors[row.index];
    if (n == null || duplicates.contains(row.index)) {
      bets[row.index] = ParsedBet(row.index, const [], const [], [
        duplicates.contains(row.index)
            ? 'Identificador de aposta repetido'
            : 'Marcador N em falta',
      ]);
      continue;
    }
    final slope = math.tan(horizontalReceiptAngle(n.angle) * math.pi / 180);
    double alignedY(ReceiptToken t) => t.y - slope * (t.x - n.x);
    final pitch = pitches.isNotEmpty ? _middle(pitches) : n.height * 2.5;
    final es = tokens
        .where(
          (t) =>
              _horizontal(t) &&
              t.text == 'E' &&
              alignedY(t) > n.y + n.height * .35 &&
              alignedY(t) < n.y + pitch * .8 &&
              ((t.x + t.width / 2) - (n.x + n.width / 2)).abs() <
                  n.height * 1.5,
        )
        .toList();
    if (es.length > 1) {
      bets[row.index] = ParsedBet(row.index, const [], const [], const [
        'Linha E ambígua; confirmar associação',
      ]);
      continue;
    }
    // If global OCR missed E, search its own lower half-line, never the next bet.
    final e = es.isEmpty ? null : es.single;
    final eY = e == null ? n.y + pitch / 2 : alignedY(e);
    final spacing = eY - n.y;
    final numbers = <int>[], stars = <int>[];
    final evidence = <ValueEvidence>[];
    for (final kind in ['N', 'E']) {
      final marker = kind == 'N' ? n : e;
      final y = kind == 'N' ? n.y : eY;
      final left = math.max(
        0.0,
        (marker?.x ?? n.x) + (marker?.width ?? n.width) / 2 + n.height * .12,
      );
      final right = math.min(width, plan.zone?.right ?? width);
      final top = math.max(
        0.0,
        math.max(
          plan.zone?.top ?? 0,
          y - spacing * .55 + math.min(0, slope * (right - n.x)),
        ),
      );
      final bottom = math.min(
        height,
        math.min(
          plan.zone?.bottom ?? height,
          y + spacing * .55 + math.max(0, slope * (right - n.x)),
        ),
      );
      if (right <= left || bottom <= top) continue;
      final crop = BetCrop(
        row.index,
        CropBox(left, top, right, bottom),
        printedIndex: true,
        kind: kind,
        deskewDegrees: horizontalReceiptAngle(n.angle),
      );
      // Try the original pixels first. Increase contrast only when normal
      // N/E line OCR at both scales cannot produce a complete valid group.
      for (final attempt in [
        (scale: 1.0, contrast: false),
        (scale: 2.0, contrast: false),
        (scale: 2.0, contrast: true),
      ]) {
        final scale = attempt.scale;
        final candidate = attempt.contrast
            ? BetCrop(
                crop.index,
                crop.box,
                printedIndex: crop.printedIndex,
                kind: crop.kind,
                position: crop.position,
                deskewDegrees: crop.deskewDegrees,
                contrast: true,
              )
            : crop;
        final suffix = attempt.contrast ? '-contrast' : '';
        final pass = 'numbered-line-${row.index}-$kind@${scale.toInt()}x$suffix';
        final timer = Stopwatch()..start();
        try {
          final frame = await recognizeCrop(candidate, scale);
          passes.add(
            CropPass(pass, candidate, scale, frame, timer.elapsedMilliseconds),
          );
          final reading = _lineReading(frame, candidate, pass);
          if (reading.values == null) continue;
          (kind == 'N' ? numbers : stars).addAll(reading.values!);
          evidence.addAll(reading.evidence);
          break;
        } catch (error) {
          passes.add(
            CropPass(
              pass,
              candidate,
              scale,
              null,
              timer.elapsedMilliseconds,
              error: error.runtimeType.toString(),
            ),
          );
        }
      }
    }
    bets[row.index] = ParsedBet(row.index, numbers, stars, [
      if (numbers.length != 5) 'Cinco números distintos entre 1 e 50 em falta',
      if (stars.length != 2) 'Duas estrelas distintas entre 1 e 12 em falta',
    ]);
    observations[row.index] = evidence;
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
    strategy: 'numbered-n-e-lines',
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
