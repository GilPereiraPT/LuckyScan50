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
  const CropPlan(this.rows, this.verticalElements, this.warnings, {this.zone});
  final List<BetCrop> rows;
  final List<ReceiptToken> verticalElements;
  final List<String> warnings;
  final CropBox? zone;
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
CropPlan planBetCrops(List<ReceiptToken> tokens, double width, double height) {
  final horizontal = tokens
      .where(
        (t) =>
            !verticalReceiptToken(t) &&
            t.height > 0 &&
            t.height < height / 8 &&
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
  final sorted = [...horizontal]..sort((a, b) => rowY(a).compareTo(rowY(b)));
  final groups = <List<ReceiptToken>>[];
  for (final token in sorted) {
    if (groups.isEmpty ||
        (rowY(token) - _median(groups.last.map(rowY))).abs() > h * .55) {
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
  final relevant = vertical
      .where((t) => receiptTokenBox(t).intersects(seed))
      .toList();
  final top = relevant.isEmpty
      ? seed.top
      : math.max(
          0.0,
          math.min(
            seed.top,
            relevant.map((t) => receiptTokenBox(t).top).reduce(math.min),
          ),
        );
  final bottom = relevant.isEmpty
      ? seed.bottom
      : math.min(
          height,
          math.max(
            seed.bottom,
            relevant.map((t) => receiptTokenBox(t).bottom).reduce(math.max),
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
        CropBox(
          left,
          math.max(
            0,
            math.min(
              cropTop,
              group.map((t) => t.y - t.height / 2).reduce(math.min) - h * .5,
            ),
          ),
          width,
          math.min(
            height,
            math.max(
              cropBottom,
              group.map((t) => t.y + t.height / 2).reduce(math.max) + h * .5,
            ),
          ),
        ),
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
