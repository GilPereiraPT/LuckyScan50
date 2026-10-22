import 'receipt_multipass.dart';
import 'receipt_parser.dart';

/// One enlarged image containing all N/E lines. Never split bets or cells.
Future<MultiPassResult> readReceiptWholeZone({
  required OcrFrame initial,
  required ScannedReceipt metadata,
  required double width,
  required double height,
  required RecognizeBetCrop recognizeCrop,
  List<CropBox> rules = const [],
}) async {
  final clock = Stopwatch()..start();
  final layout = planBetCrops(initial.tokens, width, height, rules: rules);
  final header = layout.headerRule;
  final footer = layout.footerRule;
  final bounded =
      header != null &&
      footer != null &&
      footer.top > header.bottom &&
      layout.rows.every(
        (r) => r.box.top >= header.bottom && r.box.bottom <= footer.top,
      );
  // If separators are uncertain, preserve the whole image instead of guessing.
  final box = bounded
      ? CropBox(0, header.bottom, width, footer.top)
      : CropBox(0, 0, width, height);
  final crop = BetCrop(0, box);
  final passId = bounded ? 'whole-bet-zone@2x' : 'whole-image@2x';
  final frame = await recognizeCrop(crop, 2.0);
  final parsed = withBetLayout(frame.parse(), metadata.expectedLines);
  final receipt = ScannedReceipt(
    bets: parsed.bets,
    rows: parsed.rows,
    warnings: parsed.warnings,
    code: metadata.code,
    amount: metadata.amount,
    expectedLines: metadata.expectedLines,
    game: metadata.game,
    drawDate: metadata.drawDate,
    drawId: metadata.drawId,
    hasMilhao: metadata.hasMilhao,
    milhaoCodes: metadata.milhaoCodes,
    tokenCount: parsed.tokenCount,
    skewDegrees: parsed.skewDegrees,
    strategy: passId,
    observations: parsed.observations,
  );
  return MultiPassResult(
    initial.parse(),
    receipt,
    CropPlan(
      [crop],
      const [],
      const [],
      zone: box,
      expectedLines: metadata.expectedLines,
      headerRule: header,
      footerRule: footer,
    ),
    [CropPass(passId, crop, 2.0, frame, clock.elapsedMilliseconds)],
    const [],
    clock.elapsedMilliseconds,
  );
}
