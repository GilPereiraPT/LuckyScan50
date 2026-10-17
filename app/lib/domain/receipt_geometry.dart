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
  const BetCrop(
    this.index,
    this.box, {
    this.printedIndex = false,
    this.kind,
    this.position,
    this.deskewDegrees = 0,
    this.contrast = false,
  });
  final int index;
  final CropBox box;
  final bool printedIndex;
  final String? kind;
  final int? position;
  final double deskewDegrees;
  final bool contrast;
  bool get isCell => kind != null;
}

class CropPlan {
  const CropPlan(
    this.rows,
    this.verticalElements,
    this.warnings, {
    this.zone,
    this.expectedLines,
    this.missingIndices = const [],
    this.headerRule,
    this.footerRule,
  });
  final List<BetCrop> rows;
  final List<ReceiptToken> verticalElements;
  final List<String> warnings;
  final CropBox? zone, headerRule, footerRule;
  final int? expectedLines;
  final List<int> missingIndices;
}

double horizontalReceiptAngle(double angle) =>
    ((angle + 90) % 180 + 180) % 180 - 90;

bool verticalReceiptToken(ReceiptToken token) {
  final angle = ((token.angle % 180) + 180) % 180;
  return (angle - 90).abs() <= 20 &&
      token.height > math.max(40, token.width * 3);
}

CropBox receiptTokenBox(ReceiptToken t) => CropBox(
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
CropPlan planBetCrops(
  List<ReceiptToken> tokens,
  double width,
  double height, {
  List<CropBox> rules = const [],
}) {
  final horizontal = tokens
      .where(
        (t) =>
            !verticalReceiptToken(t) &&
            t.height > 0 &&
            t.height < height / 8 &&
            t.x.isFinite &&
            t.y.isFinite &&
            horizontalReceiptAngle(t.angle).abs() <= 20 &&
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
  final angles = horizontal
      .map((t) => horizontalReceiptAngle(t.angle))
      .where((a) => a.abs() <= 15)
      .toList();
  final slope = angles.isEmpty
      ? 0.0
      : math.tan(_median(angles) * math.pi / 180);
  double rowY(ReceiptToken t) => t.y - slope * t.x;
  double ruleY(CropBox r) =>
      (r.top + r.bottom) / 2 - slope * (r.left + r.right) / 2;
  final sorted = [...horizontal]..sort((a, b) => rowY(a).compareTo(rowY(b)));
  final groups = <List<ReceiptToken>>[];
  for (final t in sorted) {
    if (groups.isEmpty ||
        (rowY(t) - _median(groups.last.map(rowY))).abs() > h * .55) {
      groups.add([t]);
    } else {
      groups.last.add(t);
    }
  }
  String text(List<ReceiptToken> g) {
    g.sort((a, b) => a.x.compareTo(b.x));
    return g.map((t) => t.text.toUpperCase()).join(' ');
  }

  final anchors = <({List<ReceiptToken> group, int? index, double x})>[];
  final warnings = <String>[];
  for (final g in groups) {
    final m = RegExp(r'^\s*(?:(\d{1,2})\s*[.)]?\s*)?N\b').firstMatch(text(g));
    if (m == null) continue;
    final index = int.tryParse(m[1] ?? '');
    if (index != null && (index < 1 || index > maxReceiptBets)) {
      warnings.add(
        'Identificador $index fora do limite de $maxReceiptBets apostas; confirmar formato.',
      );
      continue;
    }
    anchors.add((group: g, index: index, x: g.first.x - g.first.width / 2));
  }
  if (anchors.isEmpty) {
    return CropPlan([], vertical, [
      ...warnings,
      'Zona das apostas não localizada com evidência suficiente.',
    ]);
  }
  // Select the repeated identifier column. A two-digit label may be wider;
  // allow glyph-sized variation, never an unrelated numeric footer column.
  final clusters = <List<int>>[];
  for (var i = 0; i < anchors.length; i++) {
    final matching = clusters.where(
      (c) =>
          (anchors[i].x - _median(c.map((j) => anchors[j].x))).abs() <= h * 2,
    );
    if (matching.isEmpty) {
      clusters.add([i]);
    } else {
      matching.first.add(i);
    }
  }
  clusters.sort((a, b) => b.length.compareTo(a.length));
  final chosen = clusters.first.map((i) => anchors[i]).toList();
  final firstY = _median(chosen.first.group.map(rowY));
  final above = rules.where((r) => ruleY(r) < firstY - h * .4).toList()
    ..sort((a, b) => ruleY(a).compareTo(ruleY(b)));
  final header = above.isEmpty ? null : above.last;
  final below = rules.where((r) => ruleY(r) > firstY + h).toList()
    ..sort((a, b) => ruleY(a).compareTo(ruleY(b)));
  final footer = below.isEmpty ? null : below.first;
  final footerText = groups
      .where(
        (g) =>
            _median(g.map(rowY)) > firstY + h &&
            RegExp(
              r'^(?:TOTAL\b|EUROMILH[ÕO]ES\s+COM\b|EM TODO\b|VIRN\b|CODIGO\b)',
            ).hasMatch(text(g)),
      )
      .toList();
  final end = math.min(
    footer == null ? height : ruleY(footer),
    footerText.isEmpty ? height : _median(footerText.first.map(rowY)) - h,
  );
  final selected = chosen
      .where((a) => _median(a.group.map(rowY)) < end)
      .toList();
  if (selected.isEmpty) return CropPlan([], [], ['Zona das apostas ambígua.']);
  final lastY = _median(selected.last.group.map(rowY));
  final es = groups
      .where(
        (g) =>
            RegExp(r'^E\b').hasMatch(text(g)) &&
            _median(g.map(rowY)) > lastY &&
            _median(g.map(rowY)) < math.min(end, lastY + h * 3),
      )
      .toList();
  final bottomY = math.min(
    end,
    es.isEmpty ? lastY + h * 2 : _median(es.last.map(rowY)) + h,
  );
  final topY = header == null ? firstY - h * 1.5 : ruleY(header) + h * .2;
  final left = math.max(0.0, selected.map((a) => a.x).reduce(math.min) - h * 2);
  final zone = CropBox(
    left,
    math.max(0, topY + math.min(0, slope * width)),
    width,
    math.min(height, bottomY + math.max(0, slope * width)),
  );
  final relevant = vertical
      .where((t) => receiptTokenBox(t).intersects(zone))
      .toList();
  final pitches = <double>[
    for (var i = 1; i < selected.length; i++)
      if (selected[i].index != null &&
          selected[i - 1].index != null &&
          selected[i].index! > selected[i - 1].index!)
        (_median(selected[i].group.map(rowY)) -
                _median(selected[i - 1].group.map(rowY))) /
            (selected[i].index! - selected[i - 1].index!),
  ];
  final pitch = pitches.isEmpty ? null : _median(pitches);
  final rows = <BetCrop>[], used = <int>{};
  var previousIndex = 0;
  for (var pos = 0; pos < selected.length && pos < maxReceiptBets; pos++) {
    final a = selected[pos];
    // Unreadable identifiers keep a provisional slot. A later explicit number
    // is never renumbered to close a gap in the sequence.
    final index = a.index ?? previousIndex + 1;
    final laterSmaller =
        a.index != null &&
        selected
            .skip(pos + 1)
            .any(
              (next) =>
                  next.index != null &&
                  next.index! > previousIndex &&
                  next.index! < index,
            );
    if (used.contains(index) ||
        index <= previousIndex ||
        index > maxReceiptBets ||
        laterSmaller) {
      warnings.add(
        'Sequência de identificadores ambígua junto da aposta $index.',
      );
      continue;
    }
    used.add(index);
    previousIndex = index;
    final center = _median(a.group.map(rowY));
    final next = pos + 1 < selected.length
        ? _median(selected[pos + 1].group.map(rowY))
        : bottomY;
    final cropTop = math.max(topY, center - h * .85);
    final cropBottom = math.min(
      bottomY,
      math.min(next, center + (pitch ?? (next - center))) - h * .5,
    );
    if (cropBottom <= cropTop) continue;
    rows.add(
      BetCrop(
        index,
        CropBox(
          left,
          math.max(0, cropTop + math.min(0, slope * width)),
          width,
          math.min(height, cropBottom + math.max(0, slope * width)),
        ),
        printedIndex: a.index != null,
      ),
    );
  }
  final count = used.isEmpty ? null : used.reduce(math.max);
  final missing = [
    if (count != null)
      for (var i = 1; i <= count; i++)
        if (!used.contains(i)) i,
  ];
  if (missing.isNotEmpty) {
    warnings.add(
      'Identificadores não reconhecidos: ${missing.join(', ')}; posições preservadas.',
    );
  }
  return CropPlan(
    rows,
    relevant,
    warnings,
    zone: zone,
    expectedLines: count,
    missingIndices: missing,
    headerRule: header,
    footerRule: footer,
  );
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

/// A rotated photograph can expose readable N labels while still being upside
/// down. Do not select that frame merely because it contains numbered anchors.
int uprightBetRowCount(List<ReceiptToken> tokens, double width, double height) {
  final plan = planBetCrops(tokens, width, height);
  var count = 0;
  for (final row in plan.rows) {
    final labels = tokens
        .where(
          (t) =>
              RegExp(
                '^\\s*${row.index}\\s*[.)]?\\s*N\\b',
                caseSensitive: false,
              ).hasMatch(t.text) &&
              t.y >= row.box.top &&
              t.y <= row.box.bottom,
        )
        .toList();
    if (labels.isEmpty) {
      // ML Kit may split the printed identifier and N into separate elements,
      // especially for two-digit labels. Require a nearby identifier on the
      // left of N; numeric fields to its right cannot satisfy this association.
      for (final n in tokens.where(
        (t) =>
            RegExp(r'^N\.?$', caseSensitive: false).hasMatch(t.text.trim()) &&
            t.y >= row.box.top &&
            t.y <= row.box.bottom,
      )) {
        final ids = tokens.where(
          (t) =>
              t.text.replaceAll(RegExp(r'[.)]'), '').trim() ==
                  row.index.toString() &&
              t.x < n.x &&
              n.x - t.x <= n.height * 2 &&
              (t.y - n.y).abs() <= n.height * .5,
        );
        if (ids.length == 1) labels.add(n);
      }
    }
    if (labels.length != 1) continue;
    final n = labels.single;
    final angle = (n.angle % 360 + 360) % 360;
    if (angle > 45 && angle < 315) continue;
    final sameRow = tokens.where(
      (t) =>
          !verticalReceiptToken(t) &&
          (t.y - n.y).abs() <= n.height * .75 &&
          RegExp(r'^\d{1,2}$').hasMatch(t.text),
    );
    if (sameRow.where((t) => t.x < n.x - n.width / 2).length >= 2 &&
        !sameRow.any((t) => t.x > n.x + n.width / 2)) {
      continue;
    }
    count++;
  }
  return count;
}

List<int> preferredReceiptTurns(List<ReceiptToken> tokens) {
  final counts = <int, int>{};
  for (final token in tokens) {
    if (!token.angle.isFinite ||
        !RegExp(
          r'^\s*\d{1,2}\s*[.)]?\s*N\b',
          caseSensitive: false,
        ).hasMatch(token.text)) {
      continue;
    }
    final quadrant = (((token.angle % 360 + 360) % 360) / 90).round() % 4;
    counts[quadrant] = (counts[quadrant] ?? 0) + 1;
  }
  if (counts.isEmpty) return [1, 3, 2];
  final ordered = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  final first = ordered.first == 0 ? 2 : (4 - ordered.first) % 4;
  return {first, 1, 3, 2}.toList();
}
