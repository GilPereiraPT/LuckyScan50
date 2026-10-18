import 'receipt_parser.dart';

/// Recognises the Jogos Santa Casa online print layout from OCR text.
/// Uses *observed reading order*, never fixed image coordinates or known bets.
ScannedReceipt parseOnlinePdfReceipt(
  String rawText,
  List<ReceiptToken> tokens, {
  List<String> textRows = const [],
}) {
  final normalized = _normal(rawText);
  final reconstructed = reconstructRows(tokens).rows;
  final candidates = <List<String>>[
    reconstructed,
    textRows,
    rawText.split('\n'),
  ];
  List<ParsedBet> bets = [];
  for (final rows in candidates) {
    final found = _readBetRows(rows);
    if (found.length > bets.length) bets = found;
  }
  final warnings = <String>[];
  if (!normalized.contains('EUROMILHOES')) {
    warnings.add('Identificação do Euromilhões por confirmar.');
  }
  final countMatches = RegExp(
    r'\b(\d{1,2})\s+APOSTA(?:S|\(S\))',
  ).allMatches(normalized).map((m) => int.parse(m[1]!)).toSet();
  final printed = countMatches.length == 1 ? countMatches.single : null;
  final expected = printed != null && printed > 0 && printed <= maxReceiptBets
      ? printed
      : null;
  if (countMatches.length > 1 || countMatches.any((n) => n > maxReceiptBets)) {
    warnings.add('Quantidade de apostas no PDF ambígua.');
  }
  if (expected == null) {
    warnings.add('Não foi possível confirmar o número de apostas impresso.');
  } else if (bets.length != expected) {
    warnings.add(
      'PDF: identificadas ${bets.length} de $expected apostas; rever as restantes.',
    );
    if (bets.length < expected) {
      bets = [
        ...bets,
        for (var i = bets.length + 1; i <= expected; i++)
          ParsedBet(i, const [], const [], const ['Aposta não reconhecida']),
      ];
    }
  }
  final milhao = normalized.contains('M1LHAO');
  final codes = <String>[];
  if (milhao) {
    for (final match in RegExp(
      r'\b([A-Z]{3})\s*(\d{5})\b',
    ).allMatches(normalized)) {
      final code = '${match[1]} ${match[2]}';
      if (!codes.contains(code)) codes.add(code);
    }
    final expectedCodes = RegExp(
      r'\b(\d{1,2})\s+CODIGO(?:\(S\)|S)',
    ).firstMatch(normalized);
    if (expectedCodes != null && codes.length != int.parse(expectedCodes[1]!)) {
      warnings.add('Códigos M1lhão incompletos; confirmar manualmente.');
    }
  }
  final euroAmount = _printedTotal(normalized, 'EUROMILHOES');
  final milhaoAmount = _printedTotal(normalized, 'M1LHAO');
  final amount = euroAmount == null || (milhao && milhaoAmount == null)
      ? null
      : _money(euroAmount + (milhaoAmount ?? 0));
  final euroDraw = RegExp(
    r'EUROMILHOES\s+(\d{3}/\d{4})\s+(\d{2}/\d{2}/\d{4})',
  ).firstMatch(normalized);
  final milhaoDraw = RegExp(
    r'M1LHAO\s+(\d{3}/\d{4})\s+(\d{2}/\d{2}/\d{4})',
  ).firstMatch(normalized);
  final ids = RegExp(r'\b\d{12}\b')
      .allMatches(normalized)
      .map((m) => m[0]!)
      .toSet();
  return ScannedReceipt(
    bets: bets,
    rows: reconstructed.isNotEmpty ? reconstructed : textRows,
    warnings: warnings,
    code: ids.length == 1 ? ids.single : null,
    amount: amount,
    expectedLines: expected,
    game: 'euromilhoes',
    drawDate: _date(euroDraw?.group(2)),
    drawId: euroDraw?.group(1),
    milhaoDrawId: milhaoDraw?.group(1),
    hasMilhao: milhao,
    milhaoCodes: codes,
    tokenCount: tokens.length,
    strategy: 'online-pdf-table',
    observations: tokens,
  );
}

bool looksLikeOnlinePdf(String text) {
  final normalized = _normal(text);
  return normalized.contains('APOSTAS EM JOGO') ||
      (normalized.contains('CANAL JOGO') &&
          normalized.contains('EUROMILHOES')) ||
      normalized.contains('CONTAAPOSTAS');
}

List<ParsedBet> _readBetRows(List<String> rows) {
  // A bet is a run of five ordered numbers and two ordered stars.
  // There is no fallback based on expected winning values.
  final betPattern = RegExp(
    r'(?<![0-9/])([0-9]{1,2})\s+([0-9]{1,2})\s+'
    r'([0-9]{1,2})\s+([0-9]{1,2})\s+([0-9]{1,2})'
    r'\s*(?:\+\s*|\s+)([0-9]{1,2})\s+([0-9]{1,2})(?![0-9/])',
  );
  final result = <ParsedBet>[];
  for (final row in rows) {
    for (final m in betPattern.allMatches(row.replaceAll('\u00a0', ' '))) {
      final values = [
        for (var i = 1; i <= 7; i++) int.parse(m[i]!),
      ];
      final numbers = values.sublist(0, 5);
      final stars = values.sublist(5);
      if (numbers.any((n) => n < 1 || n > 50) ||
          stars.any((n) => n < 1 || n > 12) ||
          !_orderedDistinct(numbers) ||
          !_orderedDistinct(stars)) {
        continue;
      }
      if (result.length == maxReceiptBets) return result;
      result.add(ParsedBet(result.length + 1, numbers, stars, const []));
    }
  }
  return result;
}

bool _orderedDistinct(List<int> values) {
  for (var i = 1; i < values.length; i++) {
    if (values[i] <= values[i - 1]) return false;
  }
  return true;
}

String _normal(String text) => text
    .toUpperCase()
    .replaceAll('Õ', 'O')
    .replaceAll('Ã', 'A')
    .replaceAll('É', 'E')
    .replaceAll('Ó', 'O')
    .replaceAll('Í', 'I');

int? _printedTotal(String text, String game) {
  final match = RegExp(
    'TOTAL\\s+$game\\s*:?\\s*€?\\s*([0-9]{1,5})[,.]([0-9]{2})',
  ).firstMatch(text);
  if (match == null) return null;
  return int.parse(match[1]!) * 100 + int.parse(match[2]!);
}

String _money(int cents) =>
    '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

String? _date(String? value) {
  if (value == null) return null;
  final parts = value.split('/');
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  final test = DateTime(year, month, day);
  if (test.day != day || test.month != month || test.year != year) return null;
  return '${parts[2]}-${parts[1]}-${parts[0]}';
}
