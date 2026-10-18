import 'dart:math' as math;
import 'dart:typed_data';
import 'receipt_geometry.dart';
import 'receipt_parser.dart';

/// Low resolution luminance stays on-device and is never added to diagnostics.
class ReceiptRaster {
  const ReceiptRaster(this.width, this.height, this.pixels);
  final int width, height;
  final Uint8List pixels;
}

/// Search for long solid/dashed rules across the observed betting columns.
/// A rule needs dark pixels in nearly every horizontal bin and white paper on
/// both sides. Text, isolated digits and dense barcodes cannot create rows.
List<CropBox> detectReceiptRules(
  ReceiptRaster raster,
  List<ReceiptToken> tokens,
  double width,
  double height,
) {
  if (raster.width < 20 ||
      raster.height < 20 ||
      raster.pixels.length != raster.width * raster.height) {
    return [];
  }
  final labels = tokens
      .where(
        (t) =>
            !verticalReceiptToken(t) &&
            RegExp(
              r'^\s*(?:\d{1,2}\s*[.)]?\s*)?N\b',
              caseSensitive: false,
            ).hasMatch(t.text),
      )
      .toList();
  if (labels.isEmpty) return [];
  final hs = labels.map((t) => t.height).toList()..sort();
  final h = hs[hs.length ~/ 2];
  final angles =
      labels
          .map((t) => horizontalReceiptAngle(t.angle))
          .where((a) => a.abs() <= 15)
          .toList()
        ..sort();
  final slope = angles.isEmpty
      ? 0.0
      : math.tan(angles[angles.length ~/ 2] * math.pi / 180);
  final top = labels.map((t) => t.y).reduce(math.min) - h;
  final bottom = labels.map((t) => t.y).reduce(math.max) + h;
  final numeric = tokens
      .where(
        (t) =>
            t.y >= top &&
            t.y <= bottom &&
            !verticalReceiptToken(t) &&
            RegExp(r'^\d{1,2}$').hasMatch(t.text),
      )
      .toList();
  if (numeric.isEmpty) return [];
  final left = math.max(
    0.0,
    labels.map((t) => t.x - t.width / 2).reduce(math.min) - h * .4,
  );
  final right = math.min(
    width,
    numeric.map((t) => t.x + t.width / 2).reduce(math.max) + h,
  );
  if (right - left < width * .25) return [];
  final sx = raster.width / width, sy = raster.height / height;
  final x0 = (left * sx).ceil(), x1 = (right * sx).floor();
  final offset = math.max(3, (h * sy * .8).round());
  int pixel(int x, int y) => raster.pixels[y * raster.width + x];
  final ys = <int>[];
  for (var y = offset; y < raster.height - offset; y++) {
    var dark = 0, light = 0, total = 0;
    final bins = List<int>.filled(12, 0), binSizes = List<int>.filled(12, 0);
    for (var x = x0; x < x1; x++) {
      final yy = y + (slope * (x - x0) * sy / sx).round();
      if (yy - offset < 0 || yy + offset >= raster.height) continue;
      final bin = ((x - x0) * 12 / (x1 - x0)).floor().clamp(0, 11);
      binSizes[bin]++;
      if (pixel(x, yy) < 145) {
        dark++;
        bins[bin]++;
      }
      if (pixel(x, yy - offset) > 185 && pixel(x, yy + offset) > 185) light++;
      total++;
    }
    if (total > 0 &&
        dark / total >= .45 &&
        light / total >= .65 &&
        List.generate(
              12,
              (i) => binSizes[i] > 0 && bins[i] / binSizes[i] >= .25,
            ).where((v) => v).length >=
            10) {
      ys.add(y);
    }
  }
  final runs = <List<int>>[];
  for (final y in ys) {
    if (runs.isEmpty || y > runs.last.last + 1) {
      runs.add([y]);
    } else {
      runs.last.add(y);
    }
  }
  return [
    for (final run in runs)
      if (run.length <= math.max(3, h * sy * .55))
        CropBox(
          left,
          math.max(0, run.first / sy + math.min(0, slope * (right - left))),
          right,
          math.min(
            height,
            (run.last + 1) / sy + math.max(0, slope * (right - left)),
          ),
        ),
  ];
}
