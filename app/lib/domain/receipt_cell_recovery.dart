import 'receipt_geometry.dart';
import 'receipt_cells.dart';
import 'receipt_evidence.dart';
import 'receipt_cell_consensus.dart';
import 'receipt_parser.dart';
import 'receipt_ne_lines.dart';

Future<MultiPassResult> recoverReceiptCells({
  required OcrFrame initial,
  required ScannedReceipt metadata,
  required CropPlan plan,
  required double width,
  required double height,
  required RecognizeBetCrop recognizeCrop,
  int? maxPasses,
  CellGrid? initialGrid,
  String strategy = 'geometric-cells',
}) async {
  // Each observed bet has seven fields and may need a marker probe and retries.
  // Scale the budget with the actual layout instead of starving bets after #5.
  final passBudget =
      maxPasses ?? (plan.rows.length * 20).clamp(20, maxReceiptBets * 20);
  final total = Stopwatch()..start(), geometry = Stopwatch()..start();
  var grid = initialGrid ?? planBetCells(initial.tokens, plan, width, height);
  var geometryMs = geometry.elapsedMilliseconds;
  final first = withBetLayout(
        initial.parse(),
        plan.expectedLines,
        closedBettingZone: plan.footerRule != null,
      ),
      passes = <CropPass>[],
      errors = <String>[];
  final observations = <ValueEvidence>[], augmented = [...initial.tokens];
  var budgetExhausted = false;
  Future<OcrFrame?> read(BetCrop crop, double scale, String id) async {
    if (passes.length >= passBudget) {
      budgetExhausted = true;
      return null;
    }
    final watch = Stopwatch()..start();
    try {
      final frame = await recognizeCrop(crop, scale);
      passes.add(CropPass(id, crop, scale, frame, watch.elapsedMilliseconds));
      return frame;
    } catch (error) {
      passes.add(
        CropPass(
          id,
          crop,
          scale,
          null,
          watch.elapsedMilliseconds,
          error: error.runtimeType.toString(),
        ),
      );
      errors.add('$id: ${error.runtimeType}');
      return null;
    }
  }

  // Probe only label pixels. A predicted between-row location is not evidence
  // of an E row until the recognizer actually reads E there.
  final missingE = grid.markers.map((m) => m.index).toSet();
  final verifiedMissingE = <int>{};
  for (final marker in grid.markers) {
    final frame = await read(marker, 1, 'marker-${marker.index}');
    if (frame == null || frame.text.trim().toUpperCase() != 'E') continue;
    final observed = frame.tokens
        .where((t) => t.text.trim().toUpperCase() == 'E')
        .toList();
    if (observed.length != 1) continue;
    final t = observed.single;
    if (t.x < 0 ||
        t.y < 0 ||
        t.x > marker.box.width ||
        t.y > marker.box.height) {
      continue;
    }
    verifiedMissingE.add(marker.index);
    augmented.add(
      ReceiptToken(
        'E',
        marker.box.left + t.x,
        marker.box.top + t.y,
        t.height,
        width: t.width,
        angle: t.angle,
      ),
    );
  }
  geometry.reset();
  if (augmented.length != initial.tokens.length &&
      strategy != 'visual-grid-cells') {
    grid = planBetCells(augmented, plan, width, height);
  }
  // The visual-grid E position comes from a standalone observed E or a
  // predicted position. Only verified marker probes permit predicted stars.
  final activeCells = strategy == 'visual-grid-cells'
      ? grid.cells
            .where(
              (c) =>
                  c.kind != 'E' ||
                  !missingE.contains(c.index) ||
                  verifiedMissingE.contains(c.index),
            )
            .toList()
      : grid.cells;
  geometryMs += geometry.elapsedMilliseconds;
  void observe(BetCrop cell, String raw, String pass) {
    final value = parseNumericCell(raw, cell.kind!);
    final rejected =
        value.value == null && RegExp(r'^\d{1,2}$').hasMatch(value.raw);
    if (value.value == null && !rejected) return;
    observations.add(
      ValueEvidence(
        cell.kind!,
        cell.position!,
        value.value ?? int.parse(value.raw),
        value.raw,
        pass,
        betIndex: cell.index,
        bounds: cell.box,
        correction: value.correction,
        validation: rejected ? 'rejected-range' : 'observed',
        requiresConfirmation: value.raw.length == 1 || value.correction != null,
      ),
    );
  }

  observations.addAll(
    projectCellObservations(initial, activeCells, 'full-frame'),
  );
  // First read each complete numeric line with ML Kit. Crop bounds come from
  // the current image's observed/validated grid, never fixed image pixels.
  // Individual cells remain the fallback and detect contradictory readings.
  for (final index in plan.rows.map((r) => r.index)) {
    for (final kind in ['N', 'E']) {
      final parts =
          activeCells.where((c) => c.index == index && c.kind == kind).toList()
            ..sort((a, b) => a.position!.compareTo(b.position!));
      final count = kind == 'N' ? 5 : 2;
      if (parts.length != count ||
          List.generate(count, (i) => i).any((i) => parts[i].position != i)) {
        continue;
      }
      final left = parts.map((c) => c.box.left).reduce((a, b) => a < b ? a : b);
      final right = parts
          .map((c) => c.box.right)
          .reduce((a, b) => a > b ? a : b);
      final top = parts.map((c) => c.box.top).reduce((a, b) => a < b ? a : b);
      final bottom = parts
          .map((c) => c.box.bottom)
          .reduce((a, b) => a > b ? a : b);
      final entire = BetCrop(
        index,
        CropBox(left, top, right, bottom),
        kind: kind,
        printedIndex: true,
      );
      final frame = await read(entire, 1, 'line-$index-$kind@1x');
      if (frame == null) continue;
      final values = NeLineDigits.parse(frame.text.trim(), stars: kind == 'E');
      if (values == null) continue;
      for (var i = 0; i < values.length; i++) {
        observations.add(
          ValueEvidence(
            kind,
            i,
            values[i],
            values[i].toString().padLeft(2, '0'),
            'line-$index-$kind@1x',
            betIndex: index,
            bounds: parts[i].box,
            // Full-line reading remains one ML Kit observation, not two votes.
            requiresConfirmation: true,
          ),
        );
      }
    }
  }

  var skipped = 0;
  // Vertical whole-frame tokens require re-reading the original image cells.
  final contaminatedFullFrame =
      strategy == 'visual-grid-cells' && plan.verticalElements.isNotEmpty;
  for (final cell in activeCells) {
    final known = observations.where(
      (v) =>
          v.betIndex == cell.index &&
          v.kind == cell.kind &&
          v.position == cell.position &&
          v.validation != 'rejected-range',
    );
    if (!contaminatedFullFrame &&
        known.isNotEmpty &&
        known.map((v) => v.value).toSet().length == 1 &&
        known.any((v) => v.correction == null && !v.requiresConfirmation)) {
      skipped++;
      continue;
    }
    final id = 'cell-${cell.index}-${cell.kind}-${cell.position}';
    final frame = await read(cell, 1, '$id@1x');
    if (frame != null) observe(cell, frame.text, '$id@1x');
    final after = observations
        .where(
          (v) =>
              v.betIndex == cell.index &&
              v.kind == cell.kind &&
              v.position == cell.position &&
              v.validation != 'rejected-range',
        )
        .toList();
    // No blind 2x retry on already high-resolution receipt pixels. A correction
    // needs corroboration; small unresolved glyphs justify one 2x attempt.
    final needsConfirmation =
        after.isNotEmpty &&
        after.map((v) => v.value).toSet().length == 1 &&
        after.map((v) => v.pass).toSet().length < 2 &&
        after.every((v) => v.correction != null || v.requiresConfirmation);
    if (needsConfirmation ||
        (strategy == 'visual-grid-cells' && after.isEmpty) ||
        (strategy != 'visual-grid-cells' &&
            after.isEmpty &&
            cell.box.height < 48)) {
      final retry = BetCrop(
        cell.index,
        cell.box,
        printedIndex: true,
        kind: cell.kind,
        position: cell.position,
        deskewDegrees: cell.deskewDegrees,
        contrast:
            needsConfirmation ||
            (strategy == 'visual-grid-cells' && after.isEmpty),
      );
      // Real Android diagnostics show many blank 50-60 px crops. Repeating
      // those cells at 1x contrast leaves the text too small for ML Kit.
      // Retry unreadable visual cells at 2x without inventing any digits.
      final scale =
          (strategy == 'visual-grid-cells' &&
                  (after.isEmpty || needsConfirmation)) ||
              cell.box.height < 48
          ? 2.0
          : 1.0;
      final retryId =
          '$id@${scale.toInt()}x${retry.contrast ? '-contrast' : ''}';
      final frame = await read(retry, scale, retryId);
      if (frame != null) observe(cell, frame.text, retryId);
    }
  }
  final consensus = consolidateCellEvidence(activeCells, observations);
  final bets = {
    for (final b in first.bets) b.index: b,
    for (final b in consensus.bets) b.index: b,
  }.values.toList()..sort((a, b) => a.index.compareTo(b.index));
  final warnings = [
    ...metadata.warnings.where((w) => !w.startsWith('Leitura incompleta:')),
    ...plan.warnings,
    ...grid.warnings,
    if (strategy == 'visual-grid-cells')
      for (final index in missingE.difference(verifiedMissingE))
        'Aposta $index: E não confirmado por OCR; estrelas pendentes.',
    ...errors,
    if (budgetExhausted)
      'Limite de $passBudget passagens atingido; leitura parcial.',
  ];
  if (bets.any((b) => !b.complete) ||
      (metadata.expectedLines != null &&
          bets.where((b) => b.complete).length != metadata.expectedLines)) {
    warnings.add('Leitura incompleta: confirmar todas as apostas.');
  }
  if (observations.any((v) => v.correction != null)) {
    warnings.add(
      'Correções O/0, I/1 ou S/5 apenas em células N/E; confirmar valores assinalados.',
    );
  }
  T? keep<T>(T? before, T? after, String label) {
    if (before != null && after != null && before != after) {
      warnings.add('Metadado $label contraditório; confirmar.');
      return null;
    }
    return before ?? after;
  }

  final result = ScannedReceipt(
    bets: bets,
    rows: first.rows,
    warnings: warnings,
    code: keep(metadata.code, first.code, 'code'),
    amount: keep(metadata.amount, first.amount, 'amount'),
    expectedLines: keep(
      metadata.expectedLines,
      first.expectedLines,
      'expectedLines',
    ),
    game: keep(metadata.game, first.game, 'game'),
    drawDate: keep(metadata.drawDate, first.drawDate, 'drawDate'),
    drawId: keep(metadata.drawId, first.drawId, 'drawId'),
    hasMilhao: metadata.hasMilhao || first.hasMilhao,
    milhaoCodes: {...metadata.milhaoCodes, ...first.milhaoCodes}.toList(),
    observations: initial.tokens,
    tokenCount: first.tokenCount,
    skewDegrees: first.skewDegrees,
    strategy: strategy,
  );
  return MultiPassResult(
    first,
    result,
    plan,
    passes,
    consensus.evidence,
    total.elapsedMilliseconds,
    geometryMs: geometryMs,
    cellMs: passes.fold(0, (a, p) => a + p.elapsedMs),
    skippedKnownCells: skipped,
  );
}
