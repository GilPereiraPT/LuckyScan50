import 'receipt_geometry.dart';
import 'receipt_parser.dart';

class ValueEvidence {
  const ValueEvidence(
    this.kind,
    this.position,
    this.value,
    this.raw,
    this.pass, {
    this.correction,
    this.conflict = false,
    this.betIndex,
    this.bounds,
    this.validation = 'observed',
    this.requiresConfirmation = false,
  });
  final String kind, raw, pass;
  final int position, value;
  final String? correction;
  final bool conflict;
  final int? betIndex;
  final CropBox? bounds;
  final String validation;
  final bool requiresConfirmation;
  ValueEvidence validated(String state, {bool conflict = false}) =>
      ValueEvidence(
        kind,
        position,
        value,
        raw,
        pass,
        correction: correction,
        betIndex: betIndex,
        bounds: bounds,
        validation: state,
        requiresConfirmation: requiresConfirmation,
        conflict: conflict,
      );
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
    this.elapsedMs, {
    this.geometryMs = 0,
    this.cellMs = 0,
    this.skippedKnownCells = 0,
  });
  final int geometryMs, cellMs, skippedKnownCells;
  final ScannedReceipt initial, receipt;
  final CropPlan plan;
  final List<CropPass> passes;
  final List<BetEvidence> evidence;
  final int elapsedMs;
}

typedef RecognizeBetCrop =
    Future<OcrFrame> Function(BetCrop crop, double scale);
