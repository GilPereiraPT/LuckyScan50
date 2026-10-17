import 'dart:math' as math;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'receipt_parser.dart';
export 'receipt_parser.dart';

/// Adapt ML Kit observations without mixing recognition, parsing and form state.
ScannedReceipt parseScannedReceipt(RecognizedText recognized) {
  final tokens = <ReceiptToken>[];
  final rows = <String>[];
  for (final block in recognized.blocks) {
    for (final line in block.lines) {
      rows.add(line.text);
      for (final element in line.elements) {
        final corners = element.cornerPoints;
        final angle = corners.length >= 2
            ? math.atan2(
                    corners[1].y - corners[0].y,
                    corners[1].x - corners[0].x,
                  ) *
                  180 /
                  math.pi
            : element.angle ?? line.angle ?? 0;
        tokens.add(
          ReceiptToken(
            element.text,
            element.boundingBox.center.dx,
            element.boundingBox.center.dy,
            element.boundingBox.height,
            angle: angle,
          ),
        );
      }
    }
  }
  return parseReceiptObservations(
    text: recognized.text,
    textRows: rows,
    tokens: tokens,
  );
}
