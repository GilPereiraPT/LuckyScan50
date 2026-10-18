import '../domain/receipt_multipass.dart';
import '../domain/receipt_parser.dart';
import 'receipt_scanner.dart';

/// Deliberate allowlist: no source paths, photographs, crops or binary payloads.
/// The recognized receipt text can contain personal identifiers.
Map<String, Object?> receiptDiagnosticReport(
  ReceiptScan scan, {
  required String build,
  required String version,
}) {
  final recovery = scan.multiPass;
  Map<String, Object?> token(ReceiptToken t) => {
    'text': t.text,
    'x': t.x,
    'y': t.y,
    'width': t.width,
    'height': t.height,
    'angleDegrees': t.angle,
  };
  Map<String, Object?> parsed(ScannedReceipt r) => {
    'expectedBets': r.expectedLines,
    'completeBets': r.bets.where((b) => b.complete).length,
    'bets': [
      for (final b in r.bets)
        {
          'index': b.index,
          'numbers': b.numbers,
          'stars': b.stars,
          'complete': b.complete,
          'issues': b.issues,
        },
    ],
    'warnings': r.warnings,
    'rows': r.rows,
    'strategy': r.strategy,
  };
  Map<String, Object?> frame(OcrFrame f) => {
    'rawText': f.text,
    'rows': f.rows,
    'tokens': f.tokens.map(token).toList(),
    'parsed': parsed(f.parse()),
  };
  Map<String, Object?> value(ValueEvidence v) => {
    'betIndex': v.betIndex,
    'bounds': v.bounds?.toJson(),
    'coordinateFrame': v.bounds == null ? 'unknown' : 'working-image',
    'validation': v.validation,
    'requiresConfirmation': v.requiresConfirmation,
    'kind': v.kind,
    'position': v.position,
    'value': v.value,
    'raw': v.raw,
    'pass': v.pass,
    'correction': v.correction,
    'conflict': v.conflict,
  };
  final first = scan.initialReceipt;
  final finalBets = scan.receipt.bets;
  final complete = finalBets.where((b) => b.complete).length;
  final incomplete = finalBets.where((b) => !b.complete).length;
  final passes = recovery?.passes ?? <CropPass>[];
  final failedPasses = passes.where((p) => p.error != null).length;
  final emptyPasses = passes.where((p) => p.frame == null ||
      (p.frame!.text.trim().isEmpty && p.frame!.tokens.isEmpty)).length;
  final unresolved = <String>[];
  if (scan.recoveryError != null) unresolved.add('recovery_exception');
  if (recovery == null) unresolved.add('no_recovery_result');
  if (recovery?.plan.zone == null) unresolved.add('betting_zone_not_detected');
  if (recovery != null && recovery.plan.rows.isEmpty) {
    unresolved.add('no_bet_rows_detected');
  }
  if (failedPasses > 0) unresolved.add('crop_recognition_errors');
  if (emptyPasses > 0) unresolved.add('empty_crop_observations');
  if (incomplete > 0) unresolved.add('incomplete_bets');
  if (scan.receipt.expectedLines != null &&
      complete < scan.receipt.expectedLines!) {
    unresolved.add('expected_bets_not_complete');
  }
  return {
    'schemaVersion': 3,
    'analysis': {
      'status': unresolved.isEmpty ? 'no_detected_blockers' : 'review_required',
      'flags': unresolved,
      'expectedBets': scan.receipt.expectedLines,
      'detectedBets': finalBets.length,
      'completeBets': complete,
      'incompleteBets': incomplete,
      'plannedRows': recovery?.plan.rows.length,
      'cropPasses': passes.length,
      'failedCropPasses': failedPasses,
      'emptyCropPasses': emptyPasses,
      'orientationAttempts': scan.orientationPasses.length,
      'manualConfirmationRequired': incomplete > 0 ||
          scan.receipt.warnings.isNotEmpty || unresolved.isNotEmpty,
      'note': 'Heuristic diagnostic only; not proof of correct photo OCR.',
    },
    'build': build,
    'appVersion': version,
    'engine': 'Google ML Kit Latin',
    'imageGeometry': scan.imageGeometry,
    'workingFramePass': (scan.imageGeometry['workingQuarterTurns'] ?? 0) == 0
        ? 'initialPass'
        : 'orientation:${scan.imageGeometry['workingQuarterTurns']}',
    'purpose': 'diagnostic',
    'realPhotoOcrValidated': false,
    'photographsIncluded': false,
    'privacy':
        'Contains recognized receipt text; no photographs or file paths.',
    'timingsMs': {
      'phases': scan.phaseTimings,
      'geometry': recovery?.geometryMs,
      'cellPasses': recovery?.cellMs,
      'initialOcr': scan.ocrMs,
      'interpretationAndRecovery': scan.parseMs,
      'rowRecovery': recovery?.elapsedMs,
      'initialParse': scan.initialParseMs,
      'totalProcessing': scan.totalProcessingMs,
    },
    'initialPass': {
      'rawText': scan.rawText,
      'ocrMs': scan.ocrMs,
      'tokens': (first?.observations ?? scan.receipt.observations)
          .map(token)
          .toList(),
      'parsed': first == null ? null : parsed(first),
    },
    'orientationPasses': [
      for (final p in scan.orientationPasses)
        {
          'quarterTurns': p.turns,
          'elapsedMs': p.elapsedMs,
          'observedRows': p.rows,
          'result': frame(p.frame),
        },
    ],
    'cropPlan': recovery == null
        ? null
        : {
            'zone': recovery.plan.zone?.toJson(),
            'detectedBetCount': recovery.plan.expectedLines,
            'missingIdentifiers': recovery.plan.missingIndices,
            'headerRule': recovery.plan.headerRule?.toJson(),
            'footerRule': recovery.plan.footerRule?.toJson(),
            'rows': [
              for (final row in recovery.plan.rows)
                {
                  'index': row.index,
                  'printedIndex': row.printedIndex,
                  'bounds': row.box.toJson(),
                },
            ],
            'warnings': recovery.plan.warnings,
            'verticalElements': recovery.plan.verticalElements
                .map(token)
                .toList(),
          },
    'skippedKnownCells': recovery?.skippedKnownCells,
    'cropPasses': [
      for (final p in recovery?.passes ?? <CropPass>[])
        {
          'id': p.id,
          'kind': p.crop.kind ?? 'row',
          'position': p.crop.position,
          'deskewDegrees': p.crop.deskewDegrees,
          'contrast': p.crop.contrast,
          'betIndex': p.crop.index,
          'bounds': p.crop.box.toJson(),
          'printedIndex': p.crop.printedIndex,
          'scale': p.scale,
          'elapsedMs': p.elapsedMs,
          'recognitionMs': p.frame?.elapsedMs,
          'error': p.error,
          'result': p.frame == null ? null : frame(p.frame!),
        },
    ],
    'finalResult': parsed(scan.receipt),
    'provenance': [
      for (final b in recovery?.evidence ?? <BetEvidence>[])
        {
          'betIndex': b.index,
          'issues': b.issues,
          'acceptedValues': b.acceptedValues.map(value).toList(),
          'candidates': b.candidates.map(value).toList(),
        },
    ],
    'errors': [
      if (scan.recoveryError != null) scan.recoveryError,
      for (final p in recovery?.passes ?? <CropPass>[])
        if (p.error != null) {'pass': p.id, 'error': p.error},
    ],
    'warnings': scan.receipt.warnings,
    'scope':
        'OCR observations only; manually edited form values are not overwritten or exported.',
  };
}
