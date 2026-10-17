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
    'ocrMs': f.elapsedMs,
    'tokens': f.tokens.map(token).toList(),
    'parsed': parsed(f.parse()),
  };
  Map<String, Object?> value(ValueEvidence v) => {
    'kind': v.kind,
    'position': v.position,
    'value': v.value,
    'raw': v.raw,
    'pass': v.pass,
    'correction': v.correction,
    'conflict': v.conflict,
  };
  final first = scan.initialReceipt;
  return {
    'schemaVersion': 1,
    'build': build,
    'appVersion': version,
    'engine': 'Google ML Kit Latin',
    'purpose': 'diagnostic',
    'realPhotoOcrValidated': false,
    'photographsIncluded': false,
    'privacy':
        'Contains recognized receipt text; no photographs or file paths.',
    'timingsMs': {
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
            'warnings': recovery.plan.warnings,
            'verticalElements': recovery.plan.verticalElements
                .map(token)
                .toList(),
          },
    'cropPasses': [
      for (final p in recovery?.passes ?? <CropPass>[])
        {
          'id': p.id,
          'betIndex': p.crop.index,
          'bounds': p.crop.box.toJson(),
          'printedIndex': p.crop.printedIndex,
          'scale': p.scale,
          'elapsedMs': p.elapsedMs,
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
