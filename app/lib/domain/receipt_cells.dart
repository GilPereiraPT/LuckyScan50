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
      (ordered[i].value.y - ordered[i - 1].value.y) /
          (ordered[i].key - ordered[i - 1].key),
  ];
  final pitch = pitches.isEmpty ? null : _median(pitches);
  final eAnchors = <int, ReceiptToken>{};
  final markers = <BetCrop>[], warnings = <String>[];
  double slope(ReceiptToken n) => math.tan(
    (horizontalReceiptAngle(n.angle).abs() <= 15
            ? horizontalReceiptAngle(n.angle)
            : 0) *
        math.pi /
        180,
  );
  for (var i = 0; i < ordered.length; i++) {
    final index = ordered[i].key, n = ordered[i].value;
    final next = i + 1 < ordered.length
        ? ordered[i + 1].value.y
        : n.y + (pitch ?? h * 3);
    final row = plan.rows.firstWhere((r) => r.index == index);
    final end = math.min(
      next,
      math.min(row.box.bottom, n.y + (pitch ?? h * 3)),
    );
    final found = tokens
        .where(
          (t) =>
              t.text.trim().toUpperCase() == 'E' &&
              !verticalReceiptToken(t) &&
              t.y - slope(n) * (t.x - n.x) >= n.y - h * .5 &&
              t.y < end - h * .3 &&
              // E must sit underneath the N of the numbered anchor,
              // never in an unrelated column to its right.
              (t.x - (n.x + n.width * .25)).abs() <=
                  math.max(h * .65, n.width * .65),
        )
        .toList();
    if (found.length == 1) {
      eAnchors[index] = found.single;
    } else if (found.isEmpty && end - n.y > h * 1.5) {
      final box = CropBox(
        math.max(0, n.x - n.width / 2 - h * .25),
        n.y + n.height / 2,
        math.min(width, n.x + n.width / 2 + h * .65),
        math.min(height, end),
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
  if (kind != 'N' && kind != 'E') {
    return (value: null, raw: raw, correction: null);
  }
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

/// Prefer spatial cell recognition when whole-frame OCR collapses the first
/// columns of several bets into tall, 90-degree text elements.
///
/// Geometry is inferred from printed N anchors and at least three numeric
/// columns actually observed on those N rows. NO lottery values are inferred.
/// An E row is positioned between adjacent N rows; its stars must still be
/// independently recognized in the original image by the crop callback.
CellGrid planVisualBetCells(
  List<ReceiptToken> tokens,
  CropPlan plan,
  double width,
  double height,
) {
  final labels = <int, ReceiptToken>{};
  final warnings = <String>[];
  final label = RegExp(
    r'^\s*(\d{1,2})\s*[.)]?\s*N\s*\.?\s*$',
    caseSensitive: false,
  );
  for (final t in tokens.where((t) => !verticalReceiptToken(t))) {
    final match = label.firstMatch(t.text);
    if (match == null) continue;
    final index = int.parse(match[1]!);
    if (!plan.rows.any((row) => row.index == index && row.printedIndex)) {
      continue;
    }
    if (labels.containsKey(index)) {
      return const CellGrid([], [], ['Âncoras N duplicadas.']);
    }
    labels[index] = t;
  }
  if (labels.length < 2) return const CellGrid([], [], []);
  final ordered = labels.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final h = _median(ordered.map((e) => e.value.height).toList());
  final pitches = <double>[];
  for (var i = 1; i < ordered.length; i++) {
    final previous = ordered[i - 1], current = ordered[i];
    if (current.value.y <= previous.value.y) {
      return const CellGrid([], [], ['Ordem geométrica N ambígua.']);
    }
    pitches.add(
      (current.value.y - previous.value.y) / (current.key - previous.key),
    );
  }
  final pitch = _median(pitches);
  if (pitch <= h * 1.1 || pitch > height / 2) {
    return const CellGrid([], [], ['Espaçamento N não fiável.']);
  }
  final numeric = RegExp(r'^[0-9OIS]{1,2}$', caseSensitive: false);
  final angles = tokens
      .where(
        (t) =>
            !verticalReceiptToken(t) &&
            numeric.hasMatch(t.text.trim()) &&
            horizontalReceiptAngle(t.angle).abs() <= 10,
      )
      .map((t) => horizontalReceiptAngle(t.angle))
      .toList();
  final slope = math.tan(
    (angles.isEmpty ? 0.0 : _median(angles)) * math.pi / 180,
  );

  // Work from the printed horizontal numbers, not the erroneous vertical
  // digit strings. Three rightmost columns suffice to locate the other two.
  final samples = <double>[];
  for (final t in tokens) {
    if (verticalReceiptToken(t) ||
        !numeric.hasMatch(t.text.trim()) ||
        t.width <= 0) {
      continue;
    }
    for (final entry in ordered) {
      final n = entry.value;
      if (t.x <= n.x + h ||
          t.x >= width * .95 ||
          (t.y - n.y - slope * (t.x - n.x)).abs() > h * .65) {
        continue;
      }
      samples.add(t.x);
      break;
    }
  }
  samples.sort();
  final clusters = <List<double>>[];
  for (final x in samples) {
    if (clusters.isEmpty || x - _median(clusters.last) > h * 1.2) {
      clusters.add([x]);
    } else {
      clusters.last.add(x);
    }
  }
  if (clusters.length < 3 || clusters.length > 5) {
    return const CellGrid([], [], ['Colunas N insuficientes ou ambíguas.']);
  }
  final observed = clusters.map(_median).toList();
  final distances = <double>[
    for (var i = 1; i < observed.length; i++) observed[i] - observed[i - 1],
  ];
  final step = _median(distances);
  if (step <= h * 1.1 ||
      step >= width / 4 ||
      distances.any((d) => d < step * .55 || d > step * 1.65)) {
    return const CellGrid([], [], ['Grelha de colunas inconsistente.']);
  }
  final last = observed.last;
  final first = last - 4 * step;
  final nX = _median(ordered.map((e) => e.value.x).toList());
  if (first <= nX + h * .6 ||
      first >= nX + h * 6 ||
      last + step * .46 >= width) {
    return const CellGrid([], [], ['Primeira coluna N sem posição segura.']);
  }
  final xs = [for (var i = 0; i < 5; i++) first + i * step];
  if (observed.any(
    (x) => xs.map((v) => (x - v).abs()).reduce(math.min) > step * .31,
  )) {
    return const CellGrid([], [], ['Alinhamento das colunas incerto.']);
  }
  // E is an isolated printed marker beneath each N (not an inline number).
  // Match the ACTUAL isolated E before the next N; never read the N row
  // twice or use a constant fraction of the pitch as a verified E position.
  final eAnchors = <int, ReceiptToken>{};
  final eOffsets = <double>[];
  for (var j = 0; j < ordered.length; j++) {
    final entry = ordered[j], n = entry.value;
    final nextY = j + 1 < ordered.length ? ordered[j + 1].value.y : n.y + pitch;
    final found = tokens
        .where(
          (t) =>
              !verticalReceiptToken(t) &&
              t.text.trim().toUpperCase() == 'E' &&
              (t.x - n.x).abs() <= h * 1.25 &&
              t.y > n.y + h * .35 &&
              t.y < nextY - h * .25,
        )
        .toList();
    if (found.length == 1) {
      eAnchors[entry.key] = found.single;
      eOffsets.add(found.single.y - n.y);
    } else if (found.length > 1) {
      warnings.add(
        'Aposta ${entry.key}: várias âncoras E; estrelas por confirmar.',
      );
    }
  }
  final eOffset = eOffsets.isEmpty ? null : _median(eOffsets);
  final cells = <BetCrop>[], markers = <BetCrop>[];
  for (final entry in ordered) {
    final n = entry.value, e = eAnchors[entry.key];
    // With no E visible in the first pass, use the observed N-to-N pitch
    // solely to place an E-label OCR probe. Never treat that estimate as
    // verification or accept nearby stars until the probe actually reads E.
    final eY = e?.y ?? n.y + (eOffset ?? pitch * .45);
    if (e == null) {
      final marker = CropBox(
        math.max(0, n.x - h * .5),
        math.max(0, eY - h * .55),
        math.min(width, n.x + h * 1.4),
        math.min(height, eY + h * .55),
      );
      markers.add(
        BetCrop(entry.key, marker, kind: 'marker', printedIndex: true),
      );
    }
    for (final kind in ['N', 'E']) {
      for (var i = 0; i < (kind == 'N' ? 5 : 2); i++) {
        final x = xs[i];
        final y = kind == 'E'
            ? eY + slope * (x - (e?.x ?? n.x))
            : n.y + slope * (x - n.x);
        final halfHeight = math.min(pitch * .33, h * (kind == 'N' ? .58 : .50));
        final box = CropBox(
          math.max(0, x - step * .46),
          math.max(0, y - halfHeight),
          math.min(width, x + step * .46),
          math.min(height, y + halfHeight),
        );
        if (box.width < h || box.height < h * .75) continue;
        cells.add(
          BetCrop(entry.key, box, kind: kind, position: i, printedIndex: true),
        );
      }
    }
  }
  if (plan.expectedLines != null && labels.length != plan.expectedLines) {
    warnings.add(
      'Índices N incompletos: verificação manual das apostas não localizadas.',
    );
  }
  return CellGrid(cells, markers, warnings);
}
