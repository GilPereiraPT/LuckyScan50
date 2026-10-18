import 'receipt_parser.dart';

/// Only replaces empty fields or values previously supplied by OCR, and never
/// replaces edits made while the image picker/recognizer was running.
Map<String, String> receiptAutofill(
  ScannedReceipt scan, {
  required Map<String, String> current,
  required Map<String, String> atStart,
  required Map<String, String> previousOcr,
}) {
  final candidates = <String, String?>{
    'code': scan.code,
    'cost': scan.amount,
    'draws': scan.drawId,
    'date': scan.drawDate,
    'expected': scan.expectedLines?.toString(),
    'lines': scan.bets.isEmpty ? null : scan.formLines.join('\n'),
    'milhaoDraws': scan.milhaoDrawId,
    'milhaoCodes': scan.milhaoCodes.isEmpty
        ? null
        : scan.milhaoCodes.join('\n'),
  };
  final updates = <String, String>{};
  for (final entry in candidates.entries) {
    final value = current[entry.key] ?? '';
    if (entry.value != null &&
        value == (atStart[entry.key] ?? '') &&
        (value.trim().isEmpty || value == previousOcr[entry.key])) {
      updates[entry.key] = entry.value!;
    }
  }
  return updates;
}
