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

  // ML Kit may merge the marker and numbers into a single text element.
  // Prefer its line grouping, then use geometric reconstruction as fallback.
  final sourceLines = <String>[];
  for (final block in recognized.blocks) {
    for (final line in block.lines) {
      sourceLines.add(line.text.toUpperCase());
    }
  }
  final parsed = _parseBetLines(sourceLines);
  if (parsed.isNotEmpty) {
    return ScannedReceipt(lines: parsed, code: code, amount: amount, expectedLines: expectedLines);
  }
  fragments.sort((a, b) => a.y.compareTo(b.y));
  final reconstructed = <String>[];
  final heights = fragments.map((f) => f.height).where((h) => h > 0).toList()..sort();
  final medianHeight = heights.isEmpty ? 12.0 : heights[heights.length ~/ 2];
  var row = <_Fragment>[];
  double center = 0;
  for (final fragment in fragments) {
    if (row.isNotEmpty && (fragment.y - center).abs() > medianHeight * 0.65) {
      row.sort((a, b) => a.box.left.compareTo(b.box.left));
      reconstructed.add(row.map((f) => f.text).join(' '));
      row = <_Fragment>[];
    }
    row.add(fragment);
    center = row.map((f) => f.y).reduce((a, b) => a + b) / row.length;
  }
  if (row.isNotEmpty) {
    row.sort((a, b) => a.box.left.compareTo(b.box.left));
    reconstructed.add(row.map((f) => f.text).join(' '));
  }
  return ScannedReceipt(
    lines: _parseBetLines(reconstructed), code: code, amount: amount, expectedLines: expectedLines,
  );
}

List<String> _parseBetLines(List<String> input) {
  final bets = <String>[];
  List<int>? numbers;
  bool inBetSection = false;
  for (final original in input) {
    final line = original.trim().toUpperCase();
    if (line.contains('EUROMILH') && line.contains('M1LH')) break;
    final nMatch = RegExp(r'^\s*(?:[1-9]\s*[.]\s*)?N\s*[:.]?\s*(.*)$').firstMatch(line);
    final eMatch = RegExp(r'^\s*E\s*[:.]?\s*(.*)$').firstMatch(line);
    if (nMatch != null) {
      inBetSection = true;
      final found = _parseNumericTokens(nMatch.group(1)!);
      numbers = _valid(found, 5, 50) ? found : null;
    } else if (eMatch != null && inBetSection) {
      final stars = _parseNumericTokens(eMatch.group(1)!);
      if (numbers != null && _valid(stars, 2, 12)) {
        bets.add("${numbers!.map((n) => n.toString().padLeft(2, '0')).join(' ')} + ${stars.map((n) => n.toString().padLeft(2, '0')).join(' ')}");
      }
      numbers = null;
    }
  }
  return bets;
}

List<int> _parseNumericTokens(String text) {
  final tokens = text.trim().split(RegExp(r'\s+'));
  final values = <int>[];
  for (final token in tokens) {
    final normalized = token.replaceAll(RegExp(r'[OQD]'), '0')
        .replaceAll(RegExp(r'[IL|]'), '1').replaceAll('S', '5').replaceAll('B', '8');
    if (!RegExp(r'^\d{1,2}$').hasMatch(normalized)) return const [];
    values.add(int.parse(normalized));
  }
  return values;
}

List<int> _numbers(List<_Fragment> elements) {
  final values = <int>[];
  for (final f in elements) {
    final normalized = f.text.replaceAll(RegExp(r'[OQD]'), '0')
        .replaceAll(RegExp(r'[IL|]'), '1')
        .replaceAll('S', '5').replaceAll('B', '8');
    for (final token in normalized.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      if (!RegExp(r'^\d{1,2}$').hasMatch(token)) return const [];
      values.add(int.parse(token));
    }
  }
  return values;
}

bool _valid(List<int> items, int count, int max) =>
    items.length == count &&
    items.every((n) => n >= 1 && n <= max) &&
    items.toSet().length == count;
