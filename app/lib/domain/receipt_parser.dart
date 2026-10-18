import 'dart:math' as math;

// Existing segmentation safety limit, shared with parsing and recovery.
const maxReceiptBets = 20;

/// Engine-independent OCR observations. Coordinates remain local to the device.
class ReceiptToken {
  const ReceiptToken(
    this.text,
    this.x,
    this.y,
    this.height, {
    this.angle = 0,
    this.width = 0,
  });
  final String text;
  final double x, y, height, angle, width;
}

class ParsedBet {
  const ParsedBet(this.index, this.numbers, this.stars, this.issues);
  final int index;
  final List<int> numbers, stars;
  final List<String> issues;
  bool get complete =>
      issues.isEmpty && numbers.length == 5 && stars.length == 2;
  String get formLine =>
      '${numbers.map(_two).join(' ')} + ${stars.map(_two).join(' ')}';
  static String _two(int n) => n.toString().padLeft(2, '0');
}

class ScannedReceipt {
  const ScannedReceipt({
    required this.bets,
    required this.rows,
    required this.warnings,
    this.code,
    this.amount,
    this.expectedLines,
    this.game,
    this.drawDate,
    this.drawId,
    this.hasMilhao = false,
    this.milhaoCodes = const [],
    this.tokenCount = 0,
    this.skewDegrees = 0,
    this.strategy = 'text',
    this.observations = const [],
  });
  final List<ParsedBet> bets;
  final List<ReceiptToken> observations;
  final List<String> rows, warnings, milhaoCodes;
  final String? code, amount, game, drawDate, drawId;
  final int? expectedLines;
  final bool hasMilhao;
  final int tokenCount;
  final double skewDegrees;
  final String strategy;
  List<String> get lines =>
      bets.where((b) => b.complete).map((b) => b.formLine).toList();

  /// Keep every detected position in the editable form. Question marks cannot
  /// be parsed as a valid key and therefore prevent saving an omitted bet.
  List<String> get formLines => bets.map((b) {
    if (b.complete) return b.formLine;
    final onlyMissing = b.issues.every(
      (s) => s.contains('em falta') || s.contains('não reconhecida'),
    );
    final n = onlyMissing && b.numbers.length == 5
        ? b.numbers.map(ParsedBet._two).join(' ')
        : '? ? ? ? ?';
    final e = onlyMissing && b.stars.length == 2
        ? b.stars.map(ParsedBet._two).join(' ')
        : '? ?';
    return '$n + $e';
  }).toList();
  bool get fullyParsed =>
      bets.isNotEmpty &&
      bets.every((b) => b.complete) &&
      (expectedLines == null || lines.length == expectedLines) &&
      warnings.isEmpty;
}

String _label(String text) => text
    .toUpperCase()
    .replaceAll('Õ', 'O')
    .replaceAll('Ã', 'A')
    .replaceAll('Ó', 'O')
    .replaceAll('Ú', 'U')
    .replaceAll('É', 'E')
    .replaceAll('Í', 'I');

double _median(List<double> values) {
  values.sort();
  final middle = values.length ~/ 2;
  return values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
}

/// Deskew coordinates only. Does not alter pixels or claim perspective recovery.
({List<String> rows, double skew}) reconstructRows(List<ReceiptToken> tokens) {
  final valid = tokens
      .where(
        (t) =>
            t.height > 0 &&
            t.height.isFinite &&
            t.x.isFinite &&
            t.y.isFinite &&
            (((t.angle % 180) + 180) % 180 - 90).abs() > 20,
      )
      .toList();
  if (valid.isEmpty) return (rows: <String>[], skew: 0.0);
  final angles = valid
      .map((t) => t.angle)
      .where((a) => a.isFinite && a.abs() <= 20)
      .toList();
  final skew = angles.isEmpty ? 0.0 : _median(angles);
  final radians = skew * math.pi / 180;
  double x(ReceiptToken t) => t.x * math.cos(radians) + t.y * math.sin(radians);
  double y(ReceiptToken t) =>
      -t.x * math.sin(radians) + t.y * math.cos(radians);
  final height = _median(valid.map((t) => t.height).toList());
  valid.sort((a, b) => y(a).compareTo(y(b)));
  final groups = <List<ReceiptToken>>[];
  for (final token in valid) {
    // A median baseline prevents chained merging of adjacent rows.
    if (groups.isEmpty ||
        (y(token) - _median(groups.last.map(y).toList())).abs() >
            height * 0.5) {
      groups.add([token]);
    } else {
      groups.last.add(token);
    }
  }
  return (
    rows: groups.map((group) {
      group.sort((a, b) => x(a).compareTo(x(b)));
      return group.map((t) => t.text).join(' ');
    }).toList(),
    skew: skew,
  );
}

List<ParsedBet> _parseAnchoredTokens(List<ReceiptToken> tokens) {
  final nAnchors =
      tokens
          .where(
            (t) =>
                t.height > 0 &&
                t.x.isFinite &&
                t.y.isFinite &&
                RegExp(
                  r'^[0-9]{1,2}[.]?N$',
                  caseSensitive: false,
                ).hasMatch(t.text.trim()),
          )
          .toList()
        ..sort((a, b) => a.y.compareTo(b.y));
  final eAnchors = tokens
      .where(
        (t) =>
            t.height > 0 &&
            t.x.isFinite &&
            t.y.isFinite &&
            t.text.trim().toUpperCase() == 'E',
      )
      .toList();
  final bets = <ParsedBet>[];
  for (var i = 0; i < nAnchors.length && i < maxReceiptBets; i++) {
    final n = nAnchors[i];
    final nextY = i + 1 < nAnchors.length ? nAnchors[i + 1].y : double.infinity;
    final es = eAnchors.where((t) => t.y > n.y && t.y < nextY).toList()
      ..sort((a, b) => a.y.compareTo(b.y));
    final e = es.isEmpty ? null : es.first;
    List<int> values(ReceiptToken anchor, int maxValue) {
      final matches =
          tokens
              .where(
                (t) =>
                    t.x - t.width / 2 > anchor.x + anchor.width / 2 &&
                    (t.y - anchor.y).abs() < anchor.height * 0.6 &&
                    RegExp(r'^[0-9]{1,2}$').hasMatch(t.text.trim()),
              )
              .toList()
            ..sort((a, b) => a.x.compareTo(b.x));
      return matches
          .map((t) => int.parse(t.text.trim()))
          .where((v) => v >= 1 && v <= maxValue)
          .toList();
    }

    final ns = values(n, 50);
    final ss = e == null ? <int>[] : values(e, 12);
    final issues = <String>[];
    if (ns.length != 5 || ns.toSet().length != 5) {
      issues.add('N: quantidade ou duplicados por confirmar');
    }
    if (ss.length != 2 || ss.toSet().length != 2) {
      issues.add('E: quantidade ou duplicados por confirmar');
    }
    bets.add(ParsedBet(i + 1, ns, ss, issues));
  }
  return bets;
}

ScannedReceipt parseReceiptObservations({
  required String text,
  List<String>? textRows,
  List<ReceiptToken> tokens = const [],
}) {
  final geometric = reconstructRows(tokens);
  final textual = textRows == null || textRows.every((s) => s.trim().isEmpty)
      ? text.split('\n')
      : textRows;
  final anchoredBets = _parseAnchoredTokens(tokens);
  final geometryBets = anchoredBets.isNotEmpty
      ? anchoredBets
      : _parseBets(geometric.rows);
  final textBets = _parseBets(textual);
  final warnings = <String>[];
  // Geometry is primary when anchored rows exist. Conflicts are never resolved by count alone.
  final useGeometry = geometryBets.isNotEmpty;
  var bets = useGeometry ? geometryBets : textBets;
  if (useGeometry && textBets.isNotEmpty) {
    final conflicts = <int>{};
    for (final a in geometryBets.where((b) => b.complete)) {
      for (final b in textBets.where((b) => b.complete && b.index == a.index)) {
        if (a.formLine != b.formLine) conflicts.add(a.index);
      }
    }
    if (conflicts.isNotEmpty) {
      warnings.add(
        'Geometria e texto discordam nas apostas ${conflicts.join(', ')}.',
      );
      bets = bets
          .map(
            (b) => conflicts.contains(b.index)
                ? ParsedBet(b.index, b.numbers, b.stars, [
                    ...b.issues,
                    'Leituras OCR contraditórias',
                  ])
                : b,
          )
          .toList();
    }
  }
  final rows = useGeometry ? geometric.rows : textual;
  // Metadata can use reconstructed rows but only explicit, unambiguous labels.
  final raw = _label('$text\n${rows.join('\n')}');
  final identifiers = RegExp(
    r'\b\d{3}-\d{8}-(?:\d{3}|M1L)\b',
  ).allMatches(raw).map((m) => m[0]!).toSet();
  final codes = identifiers
      .where((s) => RegExp(r'-\d{3}$').hasMatch(s))
      .toList();
  final amounts = RegExp(
    r'\bTOTAL\s*:?\s*(?:€\s*)?(\d{1,5}[,.]\d{2})(?:\s*€)?',
  ).allMatches(raw).map((m) => m[1]!.replaceAll('.', ',')).toSet();
  if (amounts.length > 1) {
    warnings.add('Mais de um valor TOTAL; confirme o valor pago.');
  }
  final counts = RegExp(
    r'\b(\d{1,2})\s+(?:AP\.?\s+SIMPLES|APOSTAS?)\b',
  ).allMatches(raw).map((m) => int.parse(m[1]!)).where((n) => n > 0).toSet();
  final validBets = bets
      .where((b) => b.index >= 1 && b.index <= maxReceiptBets)
      .toList();
  if (validBets.length != bets.length ||
      counts.any((n) => n > maxReceiptBets)) {
    warnings.add(
      'Limite de $maxReceiptBets apostas; confirmar o formato do talão.',
    );
  }
  bets = validBets;
  final observed = bets.isEmpty
      ? null
      : bets.map((b) => b.index).reduce(math.max);
  final printed = counts.length == 1 && counts.single <= maxReceiptBets
      ? counts.single
      : null;
  final isMilhaoOnly = raw.contains('M1LHAO') && !raw.contains('EUROMILH');
  final expected = isMilhaoOnly
      ? null
      : observed == null
      ? printed
      : math.max(observed, printed ?? observed);
  if (counts.length > 1) warnings.add('Número de apostas ambíguo.');
  final dates = <String>{};
  for (final m in RegExp(r'\b(\d{2})/(\d{2})/(\d{4})\b').allMatches(raw)) {
    final d = int.parse(m[1]!),
        month = int.parse(m[2]!),
        year = int.parse(m[3]!);
    final date = DateTime(year, month, d);
    if (date.year == year && date.month == month && date.day == d) {
      dates.add('${m[3]}-${m[2]}-${m[1]}');
    }
  }
  final day = dates.length == 1 ? dates.single : null;
  if (dates.length > 1) {
    warnings.add('Várias datas reconhecidas; confirmar a data do sorteio.');
  }
  final contests = RegExp(
    r'\b(?:CONCURSO|CONC\.)\s*(?:N[.º°]*\s*)?:?\s*(\d{3})(?:/(\d{4}))?\b',
  ).allMatches(raw).map((m) => (number: m[1]!, year: m[2])).toSet();
  String? drawId;
  if (contests.length == 1) {
    final contest = contests.single;
    final year = contest.year ?? day?.substring(0, 4);
    if (year != null && (day == null || year == day.substring(0, 4))) {
      drawId = '${contest.number}/$year';
    } else {
      warnings.add('Concurso sem ano inequívoco; completar manualmente.');
    }
  } else if (contests.length > 1) {
    warnings.add('Vários concursos reconhecidos; confirmar a associação.');
  }
  if (expected != null && bets.length < expected) {
    final indices = bets.map((b) => b.index).toSet();
    bets = [
      ...bets,
      for (var i = 1; i <= expected; i++)
        if (!indices.contains(i))
          ParsedBet(i, const [], const [], const ['Aposta não reconhecida']),
    ]..sort((a, b) => a.index.compareTo(b.index));
  }
  if (expected != null && bets.where((b) => b.complete).length != expected) {
    warnings.add('Leitura incompleta: confirmar todas as $expected apostas.');
  }
  final hasMilhao = raw.contains('M1LHAO');
  final milhaoCodes = <String>[];
  if (hasMilhao) {
    final seen = <String>{};
    for (final line in rows) {
      final match = RegExp(
        r'^\s*([A-Z]{3})\s+(\d{5})\s*$',
        caseSensitive: false,
      ).firstMatch(_label(line));
      final labeled = RegExp(
        r'^\s*CODIGO\s+M1LHAO\s*:\s*([A-Z]{3})\s+(\d{5})\s*$',
        caseSensitive: false,
      ).firstMatch(_label(line));
      final recognized = match ?? labeled;
      if (recognized != null) {
        final code = recognized[1]!.toUpperCase() + ' ' + recognized[2]!;
        if (seen.add(code)) milhaoCodes.add(code);
      }
    }
    final printedCodes = RegExp(r'\b(\d{1,2})\s+CODIGO\(S\)').firstMatch(raw);
    if (printedCodes != null) {
      final count = int.parse(printedCodes[1]!);
      if (count != milhaoCodes.length) {
        warnings.add(
          'M1lhão: $count códigos impressos, ${milhaoCodes.length} completos reconhecidos; confirmar manualmente.',
        );
      }
    }
  }
  return ScannedReceipt(
    bets: bets,
    rows: rows,
    warnings: warnings,
    code: codes.length == 1 ? codes.single : null,
    amount: amounts.length == 1 ? amounts.single : null,
    expectedLines: expected,
    game: raw.contains('EUROMILH')
        ? 'euromilhoes'
        : hasMilhao
        ? 'milhao'
        : null,
    drawDate: day,
    drawId: drawId,
    hasMilhao: hasMilhao,
    milhaoCodes: milhaoCodes,
    tokenCount: tokens.length,
    skewDegrees: geometric.skew,
    strategy: useGeometry ? 'geometry' : 'text',
    observations: List.unmodifiable(tokens),
  );
}

List<ParsedBet> _parseBets(List<String> rows) {
  final bets = <ParsedBet>[];
  int? index;
  List<int> numbers = [], stars = [];
  final issues = <String>[];
  bool hasStars = false;
  void flush() {
    if (index == null) return;
    final found = <String>[...issues];
    if (numbers.length != 5 ||
        numbers.toSet().length != 5 ||
        numbers.any((n) => n < 1 || n > 50)) {
      found.add('Cinco números distintos entre 1 e 50 em falta');
    }
    if (stars.length != 2 ||
        stars.toSet().length != 2 ||
        stars.any((n) => n < 1 || n > 12)) {
      found.add('Duas estrelas distintas entre 1 e 12 em falta');
    }
    bets.add(ParsedBet(index!, List.of(numbers), List.of(stars), found));
    index = null;
    numbers = [];
    stars = [];
    issues.clear();
    hasStars = false;
  }

  List<int> numeric(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final values = <int>[];
    for (final token in parts) {
      if (RegExp(r'^\d{1,2}$').hasMatch(token)) {
        values.add(int.parse(token));
      } else {
        issues.add('Token numérico incerto: $token');
      }
    }
    return values;
  }

  for (final original in rows) {
    final row = _label(original.trim());
    if (bets.isNotEmpty || index != null) {
      if (RegExp(
        r'^(?:TOTAL\b|EUROMILHOES\s+COM\b|EM TODO\b|VIRN\b|CODIGO\b)',
      ).hasMatch(row)) {
        flush();
        break;
      }
    }
    // Require N/E anchors, never mine phone numbers, totals or receipt IDs.
    final n = RegExp(
      r'^\s*(?:(\d{1,2})\s*[.)]?\s*)?N\b\s*[:.]?\s*(.*)$',
    ).firstMatch(row);
    final e = RegExp(r'^\s*E\s*[:.]?\s*(.*)$').firstMatch(row);
    if (n != null) {
      flush();
      index = n[1] == null
          ? (bets.isEmpty ? 1 : bets.last.index + 1)
          : int.parse(n[1]!);
      final tail = n[2]!;
      final marker = RegExp(r'E\s*[:.]?\s*(?=[0-9])').firstMatch(tail);
      numbers = numeric(
        marker == null ? tail : tail.substring(0, marker.start),
      );
      if (marker != null) {
        stars = numeric(tail.substring(marker.end));
        hasStars = true;
      }
    } else if (e != null && index != null && !hasStars) {
      stars = numeric(e[1]!);
      hasStars = true;
    } else if (index != null &&
        !hasStars &&
        RegExp(r'^[0-9\s]+$').hasMatch(row)) {
      numbers.addAll(numeric(row));
    } else if (index != null && row.isNotEmpty) {
      flush();
    }
  }
  flush();
  final counts = <int, int>{};
  for (final b in bets) {
    counts.update(b.index, (n) => n + 1, ifAbsent: () => 1);
  }
  return bets
      .map(
        (b) => counts[b.index]! > 1
            ? ParsedBet(b.index, b.numbers, b.stars, [
                ...b.issues,
                'Identificador de aposta repetido',
              ])
            : b,
      )
      .toList();
}

/// Apply the observed image layout without changing metadata or manual edits.
ScannedReceipt withBetLayout(
  ScannedReceipt scan,
  int? count, {
  List<String> warnings = const [],
  Set<int> unconfirmed = const {},
}) {
  if (count == null) return scan;
  final indexed = {
    for (final b in scan.bets.where((b) => b.index <= count)) b.index: b,
  };
  return ScannedReceipt(
    bets: [
      for (var i = 1; i <= count; i++)
        unconfirmed.contains(i) && indexed.containsKey(i)
            ? ParsedBet(i, indexed[i]!.numbers, indexed[i]!.stars, [
                ...indexed[i]!.issues,
                'Índice geométrico por confirmar',
              ])
            : indexed[i] ??
                  ParsedBet(i, const [], const [], const [
                    'Aposta não reconhecida',
                  ]),
    ],
    rows: scan.rows,
    warnings: [
      ...scan.warnings.where((w) => !w.startsWith('Leitura incompleta:')),
      ...warnings,
      if (scan.expectedLines != null && scan.expectedLines != count)
        'Contagem visual $count difere da leitura textual ${scan.expectedLines}; confirmar.',
    ],
    code: scan.code,
    amount: scan.amount,
    expectedLines: count,
    game: scan.game,
    drawDate: scan.drawDate,
    drawId: scan.drawId,
    hasMilhao: scan.hasMilhao,
    milhaoCodes: scan.milhaoCodes,
    tokenCount: scan.tokenCount,
    skewDegrees: scan.skewDegrees,
    strategy: scan.strategy,
    observations: scan.observations,
  );
}
