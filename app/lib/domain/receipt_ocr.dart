import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Conservative extraction: never invent missing numbers or stars.
class ScannedReceipt {
  const ScannedReceipt({required this.lines, this.code, this.amount});
  final List<String> lines;
  final String? code;
  final String? amount;
}

ScannedReceipt parseScannedReceipt(RecognizedText recognized) {
  final raw = recognized.text;
  final code = RegExp(r'\b\d{3}-\d{8}-[A-Z0-9]{2,4}\b')
      .firstMatch(raw.toUpperCase())?.group(0);
  final amountMatch = RegExp(
    r'(?:TOTAL\s+A\s+PAGAR[\s\S]{0,70}?)?€\s*(\d{1,4}[,.]\d{2})',
    caseSensitive: false,
  ).firstMatch(raw);
  final amount = amountMatch?.group(1)?.replaceAll('.', ',');

  // ML Kit may return whole columns in an unexpected reading order.
  // Group OCR elements by their visual vertical centres, not by text.text.
  final elements = recognized.blocks.expand((b) => b.lines)
      .expand((line) => line.elements).toList();
  elements.sort((a, b) => a.boundingBox.center.dy
      .compareTo(b.boundingBox.center.dy));
  final rows = <List<TextElement>>[];
  for (final element in elements) {
    final y = element.boundingBox.center.dy;
    if (rows.isEmpty ||
        (y - rows.last.first.boundingBox.center.dy).abs() >
            element.boundingBox.height * 0.45) {
      rows.add([element]);
    } else {
      rows.last.add(element);
    }
  }
  for (final row in rows) {
    row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
  }
  final result = <String>[];
  final seen = <String>{};
  // Only identify explicitly marked N/E pairs. Do not shift values
  // from adjacent tickets or rows to force five numbers.
  for (var i = 0; i + 1 < rows.length; i++) {
    final numberRow = rows[i].map((e) => e.text).join(' ').toUpperCase();
    final starRow = rows[i + 1].map((e) => e.text).join(' ').toUpperCase();
    if (!RegExp(r'(?:^|\s)[1-9][.\s]*N\b').hasMatch(numberRow)) continue;
    if (!RegExp(r'(?:^|\s)E\b').hasMatch(starRow)) continue;
    final numbers = _values(numberRow.replaceFirst(
      RegExp(r'\b[1-9][.\s]*N\b'), ''));
    final stars = _values(starRow.replaceFirst(RegExp(r'\bE\b'), ''));
    if (_valid(numbers, 5, 50) && _valid(stars, 2, 12)) {
      final value = '${numbers.join(' ')} + ${stars.join(' ')}';
      if (seen.add(value)) result.add(value);
    }
  }
  return ScannedReceipt(lines: result, code: code, amount: amount);
}

List<int> _values(String s) => RegExp(r'\b\d{1,2}\b')
    .allMatches(s).map((m) => int.parse(m.group(0)!)).toList();

bool _valid(List<int> items, int count, int max) =>
    items.length == count &&
    items.every((n) => n >= 1 && n <= max) &&
    items.toSet().length == count;
