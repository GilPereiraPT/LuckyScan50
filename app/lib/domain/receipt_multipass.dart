import 'receipt_parser.dart';
import 'receipt_evidence.dart';
import 'receipt_cells.dart';
import 'receipt_cell_recovery.dart';
import 'receipt_cell_consensus.dart';
import 'receipt_numbered_bets.dart';
export 'receipt_evidence.dart';
import 'receipt_geometry.dart';
export 'receipt_geometry.dart';

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
          pair.values.length == (pair.kind == 'N' ? 5 : 2) ? i : -1,
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
      ...b.issues.where(
        (issue) => issue != 'Índice da aposta por confirmar' || !indexedAnchor,
      ),
      if (associationIssue != null) associationIssue,
    ]),
    values: values,
  );
}

ScannedReceipt _boundedInitial(OcrFrame frame, CropPlan plan) {
  final scan = withBetLayout(
    frame.parse(),
    plan.expectedLines,
    closedBettingZone: plan.footerRule != null,
    unconfirmed: plan.rows
        .where((r) => !r.printedIndex)
        .map((r) => r.index)
        .toSet(),
  );
  final checked = <ParsedBet>[];
  for (final bet in scan.bets) {
    final rows = plan.rows.where((r) => r.index == bet.index);
    if (rows.isEmpty) {
      checked.add(bet);
      continue;
    }
    final row = rows.single;
    bool inside(ReceiptToken t) => t.y >= row.box.top && t.y <= row.box.bottom;
    final es = frame.tokens.where((t) => t.text.trim().toUpperCase() == 'E');
    final foreignStars =
        bet.stars.isNotEmpty && es.isNotEmpty && !es.any(inside);
    final local = parseReceiptObservations(
      text: '',
      tokens: frame.tokens.where(inside).toList(),
    );
    final same = local.bets.where((b) => b.index == bet.index);
    final numbers = bet.numbers.length > 5 && same.length == 1
        ? same.single.numbers
        : bet.numbers;
    checked.add(
      ParsedBet(bet.index, numbers, foreignStars ? const [] : bet.stars, [
        ...bet.issues,
        if (foreignStars) 'Linha E fora da aposta; estrelas pendentes',
      ]),
    );
  }
  return ScannedReceipt(
    bets: checked,
    rows: scan.rows,
    warnings: scan.warnings,
    code: scan.code,
    amount: scan.amount,
    expectedLines: scan.expectedLines,
    game: scan.game,
    drawDate: scan.drawDate,
    drawId: scan.drawId,
    hasMilhao: scan.hasMilhao,
    milhaoCodes: scan.milhaoCodes,
    tokenCount: scan.tokenCount,
    skewDegrees: scan.skewDegrees,
    strategy: scan.strategy,
    observations: scan.observations,
  );
}

Future<MultiPassResult> recoverReceiptRows({
  required OcrFrame initial,
  required double width,
  required double height,
  required RecognizeBetCrop recognizeCrop,
  ScannedReceipt? metadata,
  List<CropBox> rules = const [],
  bool visualCells = false,
  bool numberedBetsFirst = false,
}) async {
  final clock = Stopwatch()..start();
  if (numberedBetsFirst) {
    final numbered = await recoverNumberedBets(
      initial: initial,
      metadata: metadata,
      rules: rules,
      width: width,
      height: height,
      recognizeCrop: recognizeCrop,
    );
    if (numbered != null) return numbered;
  }
  final geometryClock = Stopwatch()..start();
  final plan = planBetCrops(initial.tokens, width, height, rules: rules);
  final first = _boundedInitial(initial, plan);
  final meta = withBetLayout(
    metadata ?? first,
    plan.expectedLines,
    closedBettingZone: plan.footerRule != null,
  );

  // Whole-frame ML Kit can collapse the first two N/E columns into long
  // vertical words. Recover values from original-image numeric cell crops,
  // with spatial anchors, BEFORE attempting legacy row/text recovery.
  if (visualCells &&
      meta.game == 'euromilhoes' &&
      plan.verticalElements.isNotEmpty) {
    final visual = planVisualBetCells(initial.tokens, plan, width, height);
    if (visual.cells.length == plan.rows.length * 7 && plan.rows.isNotEmpty) {
      final result = await recoverReceiptCells(
        initialGrid: visual,
        strategy: 'visual-grid-cells',
        initial: initial,
        metadata: meta,
        plan: plan,
        width: width,
        height: height,
        recognizeCrop: recognizeCrop,
      );
      return MultiPassResult(
        result.initial,
        result.receipt,
        result.plan,
        result.passes,
        result.evidence,
        clock.elapsedMilliseconds,
        geometryMs: geometryClock.elapsedMilliseconds + result.geometryMs,
        cellMs: result.cellMs,
        skippedKnownCells: result.skippedKnownCells,
      );
    }
  }
  final grid = planBetCells(initial.tokens, plan, width, height);
  final projected = projectCellObservations(initial, grid.cells, 'full-frame');
  bool covered(ParsedBet bet, String kind, List<int> values) => values.every(
    (value) => projected.any(
      (v) => v.betIndex == bet.index && v.kind == kind && v.value == value,
    ),
  );
  final preservesInitial = first.bets.every(
    (b) => covered(b, 'N', b.numbers) && covered(b, 'E', b.stars),
  );
  if (meta.game == 'euromilhoes' &&
      grid.cells.any((c) => c.kind == 'N') &&
      preservesInitial) {
    final initialGeometryMs = geometryClock.elapsedMilliseconds;
    final result = await recoverReceiptCells(
      initialGrid: grid,
      initial: initial,
      metadata: meta,
      plan: plan,
      width: width,
      height: height,
      recognizeCrop: recognizeCrop,
    );
    return MultiPassResult(
      result.initial,
      result.receipt,
      result.plan,
      result.passes,
      result.evidence,
      clock.elapsedMilliseconds,
      geometryMs: initialGeometryMs + result.geometryMs,
      cellMs: result.cellMs,
      skippedKnownCells: result.skippedKnownCells,
    );
  }
  final bets = {for (final b in first.bets) b.index: b};
  final evidence = <int, List<ValueEvidence>>{};
  final issues = <int, List<String>>{};
  for (final b in first.bets) {
    evidence[b.index] = [
      for (var i = 0; i < b.numbers.length; i++)
        ValueEvidence(
          'N',
          b.numbers.length == 5 ? i : -1,
          b.numbers[i],
          b.numbers[i].toString(),
          b.numbers.length == 5
              ? 'full-frame'
              : 'full-frame (posição parcial por confirmar)',
        ),
      for (var i = 0; i < b.stars.length; i++)
        ValueEvidence(
          'E',
          b.stars.length == 2 ? i : -1,
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
        !plan.verticalElements.any(
          (v) => receiptTokenBox(v).intersects(crop.box),
        )) {
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
