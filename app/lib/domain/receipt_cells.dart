import 'dart:math' as math;
import 'receipt_geometry.dart';
import 'receipt_parser.dart';

class CellGrid {
  const CellGrid(this.cells, this.markers, this.warnings);
  final List<BetCrop> cells, markers;
  final List<String> warnings;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Uses indexed N anchors, observed column bounds and VERIFIED E labels.
/// Missing E labels generate label-only probes, never assumed star values.
CellGrid planBetCells(
  List<ReceiptToken> tokens,
  CropPlan plan,
  double width,
  double height,
) {
  final anchors = <int, ReceiptToken>{};
  for (final t in tokens.where((t) => !verticalReceiptToken(t))) {
    final m = RegExp(
      r'^\s*(\d{1,2})\s*[.)]?\s*N\s*\.?\s*$',
      caseSensitive: false,
    ).firstMatch(t.text);
    if (m != null &&
        plan.rows.any((r) => r.index == int.parse(m[1]!) && r.printedIndex)) {
      final index = int.parse(m[1]!);
      if (anchors.containsKey(index)) {
        return const CellGrid([], [], ['Índices N repetidos; grelha ambígua.']);
      }
      anchors[index] = t;
    }
  }
  if (anchors.isEmpty) {
    return const CellGrid([], [], ['Sem âncoras N numeradas para células.']);
  }
  final ordered = anchors.entries.toList()
    ..sort((a, b) => a.value.y.compareTo(b.value.y));
  final h = _median(anchors.values.map((t) => t.height).toList());
  final pitches = [
    for (var i = 1; i < ordered.length; i++)
      ordered[i].value.y - ordered[i - 1].value.y,
  ];
  final pitch = pitches.isEmpty ? null : _median(pitches);
  final eAnchors = <int, ReceiptToken>{};
  final markers = <BetCrop>[], warnings = <String>[];
  double slope(ReceiptToken n) =>
      math.tan((n.angle.abs() <= 15 ? n.angle : 0) * math.pi / 180);
  for (var i = 0; i < ordered.length; i++) {
    final index = ordered[i].key, n = ordered[i].value;
    final next = i + 1 < ordered.length
        ? ordered[i + 1].value.y
        : n.y + (pitch ?? h * 3);
    final found = tokens
        .where(
          (t) =>
              t.text.trim().toUpperCase() == 'E' &&
              !verticalReceiptToken(t) &&
              t.y - slope(n) * (t.x - n.x) >= n.y - h * .5 &&
              t.y < next - h * .3 &&
              t.x >= n.x - n.width / 2,
        )
        .toList();
    if (found.length == 1) {
      eAnchors[index] = found.single;
    } else if (found.isEmpty && pitch != null && pitch > h * 1.5) {
      final box = CropBox(
        math.max(0, n.x - n.width / 2 - h * .15),
        n.y + h * .35,
        math.min(width, n.x + n.width / 2 + h * .3),
        math.min(height, next - h * .35),
      );
      if (box.height >= h * .7) {
        markers.add(BetCrop(index, box, printedIndex: true, kind: 'marker'));
      }
    } else {
      warnings.add('Aposta $index: linha E não identificada com segurança.');
    }
  }
  final nSamples = <({double left, double right})>[],
      eSamples = <({double left, double right})>[];
  for (final entry in ordered) {
    final n = entry.value, e = eAnchors[entry.key];
    final span = width - n.x;
    if (span <= 0) continue;
    final inline =
        e != null && (e.y - n.y - slope(n) * (e.x - n.x)).abs() < h * .8;
    for (final t in tokens) {
      final v = verticalReceiptToken(t);
      final numeric = RegExp(
        r'^[0-9OIS]{1,2}$',
        caseSensitive: false,
      ).hasMatch(t.text.trim());
      if (!v && !numeric) continue;
      if (t.x - t.width / 2 <= n.x + n.width / 2 || t.width <= 0) continue;
      bool crosses(double y) => v
          ? t.y - t.height / 2 <= y && t.y + t.height / 2 >= y
          : (t.y - y).abs() <= h * .55;
      final sample = (
        left: (t.x - t.width / 2 - n.x) / span,
        right: (t.x + t.width / 2 - n.x) / span,
      );
      if (crosses(n.y + slope(n) * (t.x - n.x)) &&
          (!inline || t.x < e.x - e.width / 2)) {
        nSamples.add(sample);
      }
      if (e != null &&
          crosses(e.y + slope(n) * (t.x - e.x)) &&
          t.x - t.width / 2 > e.x + e.width / 2) {
        eSamples.add(sample);
      }
    }
  }
  // Touching digit bounds merge into one TWO-DIGIT column. The real report
  // contains four vertical digit words, not four separate number fields.
  List<double> columns(
    List<({double left, double right})> samples,
    int count,
    String kind,
  ) {
    samples.sort((a, b) => a.left.compareTo(b.left));
    final groups = <({double left, double right})>[];
    for (final s in samples) {
      if (groups.isEmpty || s.left > groups.last.right + .004) {
        groups.add(s);
      } else {
        final old = groups.removeLast();
        groups.add((left: old.left, right: math.max(old.right, s.right)));
      }
    }
    if (groups.length != count) {
      warnings.add(
        '$kind: ${groups.length} colunas observadas; $count necessárias.',
      );
      return [];
    }
    return groups.map((g) => (g.left + g.right) / 2).toList();
  }

  final ns = columns(nSamples, 5, 'N'),
      es = eAnchors.isEmpty ? <double>[] : columns(eSamples, 2, 'E');
  final cells = <BetCrop>[];
  for (final entry in ordered) {
    final n = entry.value, e = eAnchors[entry.key], span = width - n.x;
    for (final group in [
      (kind: 'N', xs: ns, anchor: n),
      (kind: 'E', xs: es, anchor: e),
    ]) {
      if (group.anchor == null || group.xs.isEmpty) continue;
      final a = group.anchor!;
      final xs = group.xs.map((v) => n.x + v * span).toList();
      for (var j = 0; j < xs.length; j++) {
        final x = xs[j], y = a.y + slope(n) * (x - a.x);
        final gap = [
          for (final other in xs)
            if (other != x) (other - x).abs(),
        ].reduce(math.min);
        final halfWidth = math.min(h * 1.15, gap * .44);
        // E and N are frequently separated by only one glyph height.
        final separation = e == null
            ? h * 2
            : (e.y - n.y - slope(n) * (e.x - n.x)).abs();
        final halfHeight = math.min(
          h * .65,
          separation > h * .6 ? separation * .49 : h * .65,
        );
        final box = CropBox(
          math.max(0, x - halfWidth),
          math.max(0, y - halfHeight),
          math.min(width, x + halfWidth),
          math.min(height, y + halfHeight),
        );
        if (box.width < h || box.height < h * .7) continue;
        cells.add(
          BetCrop(
            entry.key,
            box,
            printedIndex: true,
            kind: group.kind,
            position: j,
            deskewDegrees: math.atan(slope(n)) * 180 / math.pi,
          ),
        );
      }
    }
  }
  return CellGrid(cells, markers, warnings);
}

({int? value, String raw, String? correction}) parseNumericCell(
  String text,
  String kind,
) {
  final raw = text.trim().toUpperCase();
  if (!RegExp(r'^[0-9OIS]{1,2}$').hasMatch(raw)) {
    return (value: null, raw: raw, correction: null);
  }
  final normal = raw
      .replaceAll('O', '0')
      .replaceAll('I', '1')
      .replaceAll('S', '5');
  final v = int.tryParse(normal);
  return (
    value: v != null && v >= 1 && v <= (kind == 'E' ? 12 : 50) ? v : null,
    raw: raw,
    correction: normal == raw ? null : '$raw→$normal',
  );
}
