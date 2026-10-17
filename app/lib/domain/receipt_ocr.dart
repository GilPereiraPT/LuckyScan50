import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ScannedReceipt {
  const ScannedReceipt({required this.lines, this.code, this.amount, this.expectedLines});
  final List<String> lines;
  final String? code;
  final String? amount;
  final int? expectedLines;
}

class _Fragment {
  _Fragment(this.text, this.box);
  final String text;
  final Rect box;
  double get y => box.center.dy;
  double get height => box.height;
}

/// Reconstructs ticket rows by geometry, not global ML Kit reading order.
ScannedReceipt parseScannedReceipt(RecognizedText recognized) {
  final fragments = <_Fragment>[];
  for (final block in recognized.blocks) {
    for (final line in block.lines) {
      for (final element in line.elements) {
        fragments.add(_Fragment(element.text.toUpperCase(), element.boundingBox));
      }
    }
  }
  final raw = recognized.text.toUpperCase();
  final code = RegExp(r'\b\d{3}-\d{8}-[A-Z0-9]{2,4}\b').firstMatch(raw)?.group(0);
  final amount = RegExp(r'€\s*(\d{1,4}[,.]\d{2})')
      .firstMatch(raw)?.group(1)?.replaceAll('.', ',');
  final expected = RegExp(r'\b(\d{1,2})\s+AP\s+SIMPLES\b').firstMatch(raw);
  final expectedLines = expected == null ? null : int.tryParse(expected.group(1)!);

  fragments.sort((a, b) => a.y.compareTo(b.y));
  final labels = fragments.where((f) => RegExp(r'^[1-9][.]?N$').hasMatch(f.text)).toList();
  if (labels.isEmpty) {
    return ScannedReceipt(lines: const [], code: code, amount: amount, expectedLines: expectedLines);
  }
  final rows = <String>[];
  for (final n in labels) {
    final later = labels.where((f) => f.y > n.y).toList();
    final boundary = later.isNotEmpty ? later.first.y : double.infinity;
    final stars = fragments.where((f) =>
      f.y > n.y + n.height * 0.4 &&
      f.y < math.min(boundary, n.y + n.height * 3.3) &&
      f.text == 'E'
    ).toList();
    if (stars.isEmpty) continue;
    final e = stars.first;
    final tolerance = math.max(n.height, e.height) * 0.65;
    final numberElements = fragments.where((f) =>
      (f.y - n.y).abs() <= tolerance && f.box.center.dx > n.box.right
    ).toList()..sort((a,b) => a.box.left.compareTo(b.box.left));
    final starElements = fragments.where((f) =>
      (f.y - e.y).abs() <= tolerance && f.box.center.dx > e.box.right
    ).toList()..sort((a,b) => a.box.left.compareTo(b.box.left));
    final numbers = _numbers(numberElements);
    final starNumbers = _numbers(starElements);
    if (_valid(numbers, 5, 50) && _valid(starNumbers, 2, 12)) {
      rows.add("${numbers.join(' ')} + ${starNumbers.join(' ')}");
    }
  }
  return ScannedReceipt(lines: rows, code: code, amount: amount, expectedLines: expectedLines);
}

List<int> _numbers(List<_Fragment> elements) {
  final values = <int>[];
  for (final f in elements) {
    if (!RegExp(r'^\d{1,2}$').hasMatch(f.text)) return const [];
    values.add(int.parse(f.text));
  }
  return values;
}

bool _valid(List<int> items, int count, int max) =>
    items.length == count &&
    items.every((n) => n >= 1 && n <= max) &&
    items.toSet().length == count;
