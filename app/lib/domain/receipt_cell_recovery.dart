import 'receipt_geometry.dart';
import 'receipt_cells.dart';
import 'receipt_evidence.dart';
import 'receipt_cell_consensus.dart';
import 'receipt_parser.dart';

Future<MultiPassResult> recoverReceiptCells({
  required OcrFrame initial,
  required ScannedReceipt metadata,
  required CropPlan plan,
  required double width,
  required double height,
  required RecognizeBetCrop recognizeCrop,
  int maxPasses = 40,
  CellGrid? initialGrid,
}) async {
  final total = Stopwatch()..start(), geometry = Stopwatch()..start();
  var grid = initialGrid ?? planBetCells(initial.tokens, plan, width, height);
  var geometryMs = geometry.elapsedMilliseconds;
  final first = initial.parse(), passes = <CropPass>[], errors = <String>[];
  final observations = <ValueEvidence>[], augmented = [...initial.tokens];
  Future<OcrFrame?> read(BetCrop crop, double scale, String id) async {
    if (passes.length >= maxPasses) return null;
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
  if (augmented.length != initial.tokens.length) {
    grid = planBetCells(augmented, plan, width, height);
  }
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
      ),
    );
  }

  for (final cell in grid.cells) {
    for (final token in initial.tokens) {
      if (verticalReceiptToken(token)) continue;
      if (token.x >= cell.box.left &&
          token.x <= cell.box.right &&
          token.y >= cell.box.top &&
          token.y <= cell.box.bottom &&
          token.width <= cell.box.width * 1.2) {
        observe(cell, token.text, 'full-frame');
      }
    }
  }
  var skipped = 0;
  for (final cell in grid.cells) {
    final known = observations.where(
      (v) =>
          v.betIndex == cell.index &&
          v.kind == cell.kind &&
          v.position == cell.position &&
          v.validation != 'rejected-range',
    );
    if (known.isNotEmpty &&
        known.map((v) => v.value).toSet().length == 1 &&
        known.any((v) => v.correction == null)) {
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
    final correctionOnly =
        after.isNotEmpty && after.every((v) => v.correction != null);
    if (correctionOnly || (after.isEmpty && cell.box.height < 48)) {
      final retry = BetCrop(
        cell.index,
        cell.box,
        printedIndex: true,
        kind: cell.kind,
        position: cell.position,
        deskewDegrees: cell.deskewDegrees,
        contrast: correctionOnly,
      );
      final scale = cell.box.height < 48 ? 2.0 : 1.0;
      final retryId =
          '$id@${scale.toInt()}x${retry.contrast ? '-contrast' : ''}';
      final frame = await read(retry, scale, retryId);
      if (frame != null) observe(cell, frame.text, retryId);
    }
  }
  final consensus = consolidateCellEvidence(grid.cells, observations);
  final bets = {
    for (final b in first.bets) b.index: b,
    for (final b in consensus.bets) b.index: b,
  }.values.toList()..sort((a, b) => a.index.compareTo(b.index));
  final warnings = [
    ...metadata.warnings.where((w) => !w.startsWith('Leitura incompleta:')),
    ...plan.warnings,
    ...grid.warnings,
    ...errors,
    if (passes.length >= maxPasses)
      'Limite de $maxPasses passagens atingido; leitura parcial.',
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
    strategy: 'geometric-cells',
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
