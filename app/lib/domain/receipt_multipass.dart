import 'dart:math' as math;
import 'receipt_parser.dart';

class CropBox {
  const CropBox(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
  double get width => right - left;
  double get height => bottom - top;
  bool intersects(CropBox other) =>
      left < other.right &&
      right > other.left &&
      top < other.bottom &&
      bottom > other.top;
  Map<String, double> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
}

class BetCrop {
  const BetCrop(this.index, this.box, {this.printedIndex = false});
  final int index;
  final CropBox box;
  final bool printedIndex;
}

class CropPlan {
  const CropPlan(this.rows, this.verticalElements, this.warnings, {this.zone});
  final List<BetCrop> rows;
  final List<ReceiptToken> verticalElements;
  final List<String> warnings;
  final CropBox? zone;
}

bool verticalReceiptToken(ReceiptToken token) {
  final angle = ((token.angle % 180) + 180) % 180;
  return (angle - 90).abs() <= 20 &&
      token.height > math.max(40, token.width * 3);
}

CropBox _box(ReceiptToken t) => CropBox(
  t.x - t.width / 2,
  t.y - t.height / 2,
  t.x + t.width / 2,
  t.y + t.height / 2,
);
double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

/// Uses observed row anchors and tall intersecting elements, NEVER expected bet
/// counts, known winning numbers or reference-ticket values to create crops.
CropPlan planBetCrops(List<ReceiptToken> tokens, double width, double height) {
  final horizontal = tokens
      .where(
        (t) =>
            !verticalReceiptToken(t) &&
            t.height > 0 &&
            t.height < height / 8 &&
            t.angle.abs() % 180 <= 20 &&
            t.x >= 0 &&
            t.x <= width &&
            t.y >= 0 &&
            t.y <= height,
      )
      .toList();
  final vertical = tokens.where(verticalReceiptToken).toList();
  if (horizontal.isEmpty) {
    return CropPlan([], vertical, [
      'Sem âncoras horizontais; não foram inventadas linhas.',
    ]);
  }
  final h = _median(horizontal.map((t) => t.height));
  final sorted = [...horizontal]..sort((a, b) => a.y.compareTo(b.y));
  final groups = <List<ReceiptToken>>[];
  for (final token in sorted) {
    if (groups.isEmpty ||
        (token.y - _median(groups.last.map((t) => t.y))).abs() > h * .55) {
      groups.add([token]);
    } else {
      groups.last.add(token);
    }
  }
  final anchors = <({List<ReceiptToken> tokens, int? index})>[];
  for (final group in groups) {
    group.sort((a, b) => a.x.compareTo(b.x));
    final text = group.map((t) => t.text.toUpperCase()).join(' ');
    final marker = RegExp(r'^\s*(?:(\d{1,2})\s*[.)]?\s*)?N\b').firstMatch(text);
    if (marker != null) {
      anchors.add((tokens: group, index: int.tryParse(marker[1] ?? '')));
    }
  }
  if (anchors.isEmpty) {
    return CropPlan([], vertical, [
      'Zona das apostas não localizada com evidência suficiente.',
    ]);
  }
  final anchorTop = anchors.first.tokens.map((t) => t.y).reduce(math.min);
  final anchorBottom = anchors.last.tokens.map((t) => t.y).reduce(math.max);
  final left = math.max(
    0.0,
    anchors
            .expand((a) => a.tokens)
            .map((t) => t.x - t.width / 2)
            .reduce(math.min) -
        h * 2,
  );
  // Full receipt width preserves stars even if none survived the initial OCR.
  final seed = CropBox(
    left,
    math.max(0, anchorTop - h * 2),
    width,
    math.min(height, anchorBottom + h * 2),
  );
  final relevant = vertical.where((t) => _box(t).intersects(seed)).toList();
  final top = relevant.isEmpty
      ? seed.top
      : math.max(
          0.0,
          math.min(seed.top, relevant.map((t) => _box(t).top).reduce(math.min)),
        );
  final bottom = relevant.isEmpty
      ? seed.bottom
      : math.min(
          height,
          math.max(
            seed.bottom,
            relevant.map((t) => _box(t).bottom).reduce(math.max),
          ),
        );
  final zone = CropBox(left, top, width, bottom);
  // Recover other OBSERVED suffix rows within the same column span, not rows
  // interpolated from a printed count or from a vertical word's character count.
  final candidateGroups = groups.where((group) {
    final y = _median(group.map((t) => t.y));
    if (y < top || y > bottom) return false;
    if (anchors.any((a) => identical(a.tokens, group))) return true;
    if (relevant.isEmpty) return false;
    final text = group.map((t) => t.text.toUpperCase()).join(' ');
    if (RegExp(r'\b(?:TOTAL|CONCURSO|CONC|EURO|M1LH)\b|^E\b').hasMatch(text)) {
      return false;
    }
    final numeric = group
        .where(
          (t) =>
              RegExp(r'^\d{1,2}$').hasMatch(t.text) &&
              int.parse(t.text) >= 1 &&
              int.parse(t.text) <= 50,
        )
        .length;
    return numeric >= 2 &&
        group.every((t) => RegExp(r'^[\d\s.,]+$').hasMatch(t.text));
  }).toList();
  final warnings = <String>[];
  final rows = <BetCrop>[];
  final used = <int>{};
  for (
    var position = 0;
    position < candidateGroups.length && position < 20;
    position++
  ) {
    final group = candidateGroups[position];
    final center = _median(group.map((t) => t.y));
    final anchored = anchors.where((a) => identical(a.tokens, group));
    final printed = anchored.isEmpty ? null : anchored.first.index;
    final index = printed ?? position + 1;
    if (index < 1 || !used.add(index)) {
      warnings.add('Índice geométrico ambíguo; linha não associada.');
      continue;
    }
    final previous = position == 0
        ? top
        : _median(candidateGroups[position - 1].map((t) => t.y));
    final next = position + 1 == candidateGroups.length
        ? bottom
        : _median(candidateGroups[position + 1].map((t) => t.y));
    final cropTop = position == 0
        ? math.max(top, center - h * 1.5)
        : math.max(top, (previous + center) / 2);
    // Extend below the N row to retain a separate E/stars line; stop before
    // the next observed numeric/N row and leave a small, explicit margin.
    final cropBottom = position + 1 == candidateGroups.length
        ? bottom
        : math.min(bottom, next - h * .65);
    if (cropBottom - cropTop < h || next <= center) {
      warnings.add('Margens insuficientes; linha não recortada.');
      continue;
    }
    rows.add(
      BetCrop(
        index,
        CropBox(left, cropTop, width, cropBottom),
        printedIndex: printed != null,
      ),
    );
  }
  if (candidateGroups.length > 20) {
    warnings.add('Limite de 20 linhas observado; leitura parcial.');
  }
  return CropPlan(rows, relevant, warnings, zone: zone);
}

class OcrFrame {
  const OcrFrame(
    this.text,
    this.tokens, {
    this.rows = const [],
    this.elapsedMs = 0,
  });
  final String text;
  final List<ReceiptToken> tokens;
  final List<String> rows;
  final int elapsedMs;
  ScannedReceipt parse() =>
      parseReceiptObservations(text: text, tokens: tokens, textRows: rows);
}

class ValueEvidence {
  const ValueEvidence(
    this.kind,
    this.position,
    this.value,
    this.raw,
    this.pass, {
    this.correction,
    this.conflict = false,
  });
  final String kind, raw, pass;
  final int position, value;
  final String? correction;
  final bool conflict;
  String get description =>
      '$kind[$position]=$value ← $raw ($pass)${correction == null ? '' : ' [$correction; confirmar]'}${conflict ? ' [conflito]' : ''}';
}

class BetEvidence {
  const BetEvidence(
    this.index,
    this.candidates,
    this.issues, {
    this.acceptedValues = const [],
  });
  final int index;
  final List<ValueEvidence> candidates, acceptedValues;
  final List<String> issues;
}

class CropPass {
  const CropPass(
    this.id,
    this.crop,
    this.scale,
    this.frame,
    this.elapsedMs, {
    this.error,
  });
  final String id;
  final BetCrop crop;
  final double scale;
  final OcrFrame? frame;
  final int elapsedMs;
  final String? error;
}

class MultiPassResult {
  const MultiPassResult(
    this.initial,
    this.receipt,
    this.plan,
    this.passes,
    this.evidence,
    this.elapsedMs,
  );
  final ScannedReceipt initial, receipt;
  final CropPlan plan;
  final List<CropPass> passes;
  final List<BetEvidence> evidence;
  final int elapsedMs;
}

typedef RecognizeBetCrop =
    Future<OcrFrame> Function(BetCrop crop, double scale);

({ParsedBet? bet, List<ValueEvidence> values}) _cropCandidate(
  OcrFrame frame,
  int index,
  String pass, {
  required bool indexedAnchor,
}) {
  // Corrections are permitted ONLY between explicit N/E anchors, in a cropped
  // bet row. Arbitrary vertical words and numeric-looking administrative IDs
  // never enter this branch.
  final rows = frame.rows.isEmpty ? frame.text.split('\n') : frame.rows;
  final rawGroups = <String, List<String>>{};
  final corrected = <String>[];
  bool numeric = false;
  for (final row in rows) {
    var value = row.toUpperCase();
    final n = RegExp(
      r'^\s*(?:\d{1,2}\s*[.)]?\s*)?N\s*[:.]?\s*(.*)$',
    ).firstMatch(value);
    final e = RegExp(r'^\s*E\s*[:.]?\s*(.*)$').firstMatch(value);
    if (n != null) {
      final tail = n[1]!;
      final separator = RegExp(r'E\s*[:.]?\s*(?=[0-9O])').firstMatch(tail);
      rawGroups['N'] =
          (separator == null ? tail : tail.substring(0, separator.start))
              .trim()
              .split(RegExp(r'\s+'));
      if (separator != null) {
        rawGroups['E'] = tail
            .substring(separator.end)
            .trim()
            .split(RegExp(r'\s+'));
      }
    } else if (e != null) {
      rawGroups['E'] = e[1]!.trim().split(RegExp(r'\s+'));
    }
    if (RegExp(r'^\s*(?:\d{1,2}\s*[.)]?\s*)?N\b').hasMatch(value)) {
      numeric = true;
    }
    if (numeric &&
        (RegExp(r'^\s*E\b').hasMatch(value) ||
            RegExp(r'^\s*(?:\d{1,2}\s*[.)]?\s*)?N\b').hasMatch(value))) {
      value = value.replaceAllMapped(RegExp(r'\b[0-9O]{1,2}\b'), (m) {
        final raw = m[0]!;
        final normal = raw.replaceAll('O', '0');
        return normal;
      });
    } else if (value.trim().isNotEmpty) {
      numeric = false;
    }
    corrected.add(value);
  }
  final parsed = parseReceiptObservations(text: corrected.join('\n'));
  final observed = parsed.bets
      .where((b) => b.numbers.isNotEmpty || b.stars.isNotEmpty)
      .toList();
  if (observed.length != 1) return (bet: null, values: <ValueEvidence>[]);
  final b = observed.single;
  // If a crop actually contains another explicitly indexed bet, don't attach
  // those values to its neighbour merely because this was the requested crop.
  final printed = RegExp(
    r'^\s*(\d{1,2})\s*[.)]?\s*N\b',
    multiLine: true,
  ).firstMatch(frame.text.toUpperCase());
  if (printed != null && int.parse(printed[1]!) != index) {
    return (bet: null, values: <ValueEvidence>[]);
  }
  final associationIssue = printed == null && !indexedAnchor
      ? 'Índice geométrico por confirmar'
      : null;
  final values = <ValueEvidence>[];
  for (final pair in [
    (kind: 'N', values: b.numbers),
    (kind: 'E', values: b.stars),
  ]) {
    for (var i = 0; i < pair.values.length; i++) {
      final n = pair.values[i];
      final normal = n.toString().padLeft(2, '0');
      final rawValues = rawGroups[pair.kind] ?? [];
      final raw = rawValues.length == pair.values.length
          ? rawValues[i]
          : normal;
      values.add(
        ValueEvidence(
          pair.kind,
          i,
          n,
          raw,
          pass,
          correction: raw.contains('O') ? 'O→0' : null,
        ),
      );
    }
  }
  return (
    bet: ParsedBet(index, b.numbers, b.stars, [
      ...b.issues,
      if (associationIssue != null) associationIssue,
    ]),
    values: values,
  );
}

Future<MultiPassResult> recoverReceiptRows({
  required OcrFrame initial,
  required double width,
  required double height,
  required RecognizeBetCrop recognizeCrop,
  ScannedReceipt? metadata,
}) async {
  final clock = Stopwatch()..start();
  final first = initial.parse();
  final meta = metadata ?? first;
  final plan = planBetCrops(initial.tokens, width, height);
  final bets = {for (final b in first.bets) b.index: b};
  final evidence = <int, List<ValueEvidence>>{};
  final issues = <int, List<String>>{};
  for (final b in first.bets) {
    evidence[b.index] = [
      for (var i = 0; i < b.numbers.length; i++)
        ValueEvidence(
          'N',
          i,
          b.numbers[i],
          b.numbers[i].toString(),
          b.numbers.length == 5
              ? 'full-frame'
              : 'full-frame (posição parcial por confirmar)',
        ),
      for (var i = 0; i < b.stars.length; i++)
        ValueEvidence(
          'E',
          i,
          b.stars[i],
          b.stars[i].toString(),
          b.stars.length == 2
              ? 'full-frame'
              : 'full-frame (posição parcial por confirmar)',
        ),
    ];
  }
  final passes = <CropPass>[];
  for (final crop in plan.rows) {
    // Re-read affected lines even if syntactically complete: vertical column
    // segmentation can coexist with plausible but wrong-looking complete rows.
    if ((bets[crop.index]?.complete ?? false) &&
        !plan.verticalElements.any((v) => _box(v).intersects(crop.box))) {
      continue;
    }
    for (final scale in [1.0, 2.0]) {
      final passId = 'row-${crop.index}@${scale.toInt()}x';
      final timer = Stopwatch()..start();
      try {
        final frame = await recognizeCrop(crop, scale);
        passes.add(
          CropPass(passId, crop, scale, frame, timer.elapsedMilliseconds),
        );
        final candidate = _cropCandidate(
          frame,
          crop.index,
          passId,
          indexedAnchor: crop.printedIndex,
        );
        if (candidate.bet == null) {
          issues
              .putIfAbsent(crop.index, () => [])
              .add('$passId: âncoras/linha ambíguas');
          continue;
        }
        evidence.putIfAbsent(crop.index, () => []).addAll(candidate.values);
        final old = bets[crop.index];
        final next = candidate.bet!;
        if (old != null &&
            old.complete &&
            next.complete &&
            old.formLine != next.formLine) {
          bets[crop.index] = ParsedBet(crop.index, old.numbers, old.stars, [
            'Passagens OCR contraditórias',
          ]);
          issues
              .putIfAbsent(crop.index, () => [])
              .add('Conflito entre passagens; confirmar manualmente.');
          break;
        }
        final countIssuesOnly =
            next.issues.every(
              (v) =>
                  v.startsWith('Cinco números') ||
                  v.startsWith('Duas estrelas'),
            ) &&
            (old == null ||
                old.issues.every(
                  (v) =>
                      v.startsWith('Cinco números') ||
                      v.startsWith('Duas estrelas') ||
                      v == 'Aposta não reconhecida',
                ));
        if (old != null && countIssuesOnly) {
          bool valid(List<int> v, int count, int maximum) =>
              v.length == count &&
              v.toSet().length == count &&
              v.every((n) => n >= 1 && n <= maximum);
          final oldN = valid(old.numbers, 5, 50),
              oldE = valid(old.stars, 2, 12);
          final nextN = valid(next.numbers, 5, 50),
              nextE = valid(next.stars, 2, 12);
          final conflict =
              (oldN &&
                  nextN &&
                  old.numbers.join(',') != next.numbers.join(',')) ||
              (oldE && nextE && old.stars.join(',') != next.stars.join(','));
          if (conflict) {
            bets[crop.index] = ParsedBet(crop.index, old.numbers, old.stars, [
              'Grupos numéricos contraditórios entre passagens',
            ]);
            issues
                .putIfAbsent(crop.index, () => [])
                .add('Conflito entre grupos observados.');
            break;
          }
          if ((oldN || nextN) && (oldE || nextE)) {
            bets[crop.index] = ParsedBet(
              crop.index,
              nextN ? next.numbers : old.numbers,
              nextE ? next.stars : old.stars,
              [],
            );
            break;
          }
        }
        if (next.complete) {
          bets[crop.index] = next;
          break;
        }
        // Retain partial observations in evidence; never append fragments from
        // different unanchored positions to manufacture a complete bet.
        if (old == null ||
            (next.numbers.length + next.stars.length >
                old.numbers.length + old.stars.length)) {
          bets[crop.index] = next;
        }
      } catch (error) {
        passes.add(
          CropPass(
            passId,
            crop,
            scale,
            null,
            timer.elapsedMilliseconds,
            error: error.runtimeType.toString(),
          ),
        );
        issues
            .putIfAbsent(crop.index, () => [])
            .add('$passId falhou: ${error.runtimeType}');
      }
    }
  }
  final ordered = bets.values.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  final warnings = [
    ...meta.warnings.where((w) => !w.startsWith('Leitura incompleta:')),
    ...plan.warnings,
  ];
  if (meta.expectedLines != null &&
      ordered.where((b) => b.complete).length != meta.expectedLines) {
    warnings.add(
      'Leitura incompleta: confirmar todas as ${meta.expectedLines} apostas.',
    );
  }
  if (evidence.values.expand((e) => e).any((v) => v.correction != null)) {
    warnings.add(
      'O→0 aplicado apenas em campo numérico ancorado; confirmar os valores assinalados.',
    );
  }
  T? keepMetadata<T>(T? before, T? after, String label) {
    if (before != null && after != null && before != after) {
      warnings.add(
        'Metadado $label contraditório entre orientações; confirmar.',
      );
      return null;
    }
    return before ?? after;
  }

  final receipt = ScannedReceipt(
    bets: ordered,
    rows: first.rows,
    warnings: warnings,
    code: keepMetadata(meta.code, first.code, 'code'),
    amount: keepMetadata(meta.amount, first.amount, 'amount'),
    expectedLines: meta.expectedLines,
    game: keepMetadata(meta.game, first.game, 'game'),
    drawDate: keepMetadata(meta.drawDate, first.drawDate, 'drawDate'),
    drawId: keepMetadata(meta.drawId, first.drawId, 'drawId'),
    hasMilhao: meta.hasMilhao || first.hasMilhao,
    milhaoCodes: {...meta.milhaoCodes, ...first.milhaoCodes}.toList(),
    tokenCount: first.tokenCount,
    skewDegrees: first.skewDegrees,
    strategy: passes.isEmpty ? first.strategy : 'multi-pass',
    observations: first.observations,
  );
  final provenance = <BetEvidence>[];
  for (final b in ordered) {
    final observed = evidence[b.index] ?? [];
    final selected = <ValueEvidence>[];
    if (b.complete) {
      for (final group in [
        (kind: 'N', values: b.numbers),
        (kind: 'E', values: b.stars),
      ]) {
        for (var i = 0; i < group.values.length; i++) {
          final matches = observed.where(
            (e) =>
                e.kind == group.kind &&
                e.position == i &&
                e.value == group.values[i] &&
                !e.pass.contains('parcial'),
          );
          if (matches.isNotEmpty) selected.add(matches.last);
        }
      }
    }
    provenance.add(
      BetEvidence(b.index, observed, [
        ...b.issues,
        ...?issues[b.index],
      ], acceptedValues: selected),
    );
  }
  return MultiPassResult(
    first,
    receipt,
    plan,
    passes,
    provenance,
    clock.elapsedMilliseconds,
  );
}
