import 'dart:math' as math;
import 'receipt_ne_lines.dart';

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
  final horizontal = tokens
      .where(
        (t) =>
            t.height > 0 &&
            t.height.isFinite &&
            t.x.isFinite &&
            t.y.isFinite &&
            t.angle.isFinite &&
            (((t.angle % 180) + 180) % 180 - 90).abs() > 20,
      )
      .toList();
  if (horizontal.isEmpty) return [];
  final angles = horizontal
      .map((t) => t.angle)
      .where((a) => a.abs() <= 20)
      .toList();
  final radians = (angles.isEmpty ? 0.0 : _median(angles)) * math.pi / 180;
  double x(ReceiptToken t) => t.x * math.cos(radians) + t.y * math.sin(radians);
  double y(ReceiptToken t) =>
      -t.x * math.sin(radians) + t.y * math.cos(radians);
  final ns = <({ReceiptToken token, int? index})>[];
  for (final t in horizontal) {
    final m = RegExp(
      r'^\s*(?:(\d{1,2})\s*[.)]?\s*)?N\.?\s*$',
      caseSensitive: false,
    ).firstMatch(t.text);
    if (m == null) continue;
    int? index = int.tryParse(m[1] ?? '');
    if (index == null) {
      final ids = horizontal
          .where(
            (id) =>
                RegExp(r'^\d{1,2}[.)]?$').hasMatch(id.text.trim()) &&
                x(id) < x(t) &&
                x(t) - x(id) <= t.height * 2 &&
                (y(id) - y(t)).abs() <= t.height * .5,
          )
          .toList();
      if (ids.length == 1) {
        index = int.parse(
          ids.single.text.replaceAll(RegExp(r'[.)]'), '').trim(),
        );
      }
    }
    ns.add((token: t, index: index));
  }
  if (ns.isEmpty) return [];
  ns.sort((a, b) => y(a.token).compareTo(y(b.token)));
  final es = horizontal
      .where(
        (t) => RegExp(
          r'^E(?:\s+\d{1,2}){0,2}$',
          caseSensitive: false,
        ).hasMatch(t.text.trim()),
      )
      .toList();
  final pitches = <double>[
    for (var i = 1; i < ns.length; i++)
      if (ns[i].index != null &&
          ns[i - 1].index != null &&
          ns[i].index! > ns[i - 1].index!)
        (y(ns[i].token) - y(ns[i - 1].token)) /
            (ns[i].index! - ns[i - 1].index!),
  ];
  final pitch = pitches.isEmpty ? null : _median(pitches);
  final bets = <ParsedBet>[];
  for (var i = 0; i < ns.length && i < maxReceiptBets; i++) {
    final n = ns[i].token;
    final index = ns[i].index ?? (bets.isEmpty ? 1 : bets.last.index + 1);
    final next = i + 1 < ns.length ? y(ns[i + 1].token) : double.infinity;
    final end = math.min(
      next - n.height * .25,
      y(n) + (pitch ?? n.height * 3) * .85,
    );
    final candidates = es.where((e) {
      final dy = y(e) - y(n), dx = x(e) - x(n);
      final inline = dy.abs() <= n.height * .35 && dx > n.width / 2;
      final beneath =
          dy > n.height * .35 &&
          dx.abs() <= math.max(n.height * .8, n.width * .5);
      return y(e) < end && (inline || beneath);
    }).toList();
    final e = candidates.length == 1 ? candidates.single : null;
    final inline = e != null && (y(e) - y(n)).abs() <= n.height * .35;
    final issues = <String>[
      if (ns[i].index == null) 'Índice geométrico por confirmar',
      if (candidates.length > 1) 'Linha E ambígua; confirmar associação',
    ];
    List<int> values(ReceiptToken anchor, String kind) {
      final found = horizontal.where((t) {
        if (!RegExp(r'^\d{1,2}$').hasMatch(t.text.trim())) return false;
        if (x(t) - t.width / 2 <= x(anchor) + anchor.width / 2) return false;
        if (y(t) > end ||
            (y(t) - y(anchor)).abs() >
                math.min(t.height, anchor.height) * .55) {
          return false;
        }
        if (e != null) {
          if (inline) {
            if (kind == 'N' && x(t) >= x(e) - e.width / 2) return false;
          } else {
            final own = (y(t) - y(anchor)).abs();
            final other = (y(t) - y(kind == 'N' ? e : n)).abs();
            if (own >= other) {
              return false; // Equidistant values remain unassigned.
            }
          }
        }
        return true;
      }).toList()..sort((a, b) => x(a).compareTo(x(b)));
      return found.map((t) => int.parse(t.text.trim())).toList();
    }

    final numbers = values(n, 'N');
    final embedded = e == null
        ? <int>[]
        : e.text.trim().split(RegExp(r'\s+')).skip(1).map(int.parse).toList();
    final stars = e == null
        ? <int>[]
        : embedded.isEmpty
        ? values(e, 'E')
        : embedded;
    if (numbers.length != 5 ||
        numbers.toSet().length != 5 ||
        numbers.any((v) => v < 1 || v > 50)) {
      issues.add('Cinco números distintos entre 1 e 50 em falta');
    }
    if (stars.length != 2 ||
        stars.toSet().length != 2 ||
        stars.any((v) => v < 1 || v > 12)) {
      issues.add('Duas estrelas distintas entre 1 e 12 em falta');
    }
    bets.add(ParsedBet(index, numbers, stars, issues));
  }
  return bets
      .map(
        (b) => bets.where((other) => other.index == b.index).length > 1
            ? ParsedBet(b.index, b.numbers, b.stars, [
                ...b.issues,
                'Identificador de aposta repetido',
              ])
            : b,
      )
      .toList();
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
  // The official physical receipt separates TOTAL A PAGAR and the amount
  // onto different OCR lines, or prints them on the same line.
  // Never collect arbitrary monetary values outside this anchored label.
  final amounts = RegExp(
    r'\bTOTAL\s*(?:A\s+PAGAR\s*)?:?\s*(?:€\s*)?(\d{1,5}[,.]\d{2})(?:\s*€)?',
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
  // Euromilhões physical tickets often label the draw "AUT SORT 081",
  // rather than "CONCURSO 081". Only use an unequivocal anchored number.
  final contests = <({String number, String? year})>{
    ...RegExp(
      r'\b(?:CONCURSO|CONC\.)\s*(?:N[.º°]*\s*)?:?\s*(\d{3})(?:/(\d{4}))?\b',
    ).allMatches(raw).map((m) => (number: m[1]!, year: m[2])),
    ...RegExp(r'\bAUT\s+SORT\s+([0-9O]{3})\b')
        .allMatches(raw)
        .map((m) => (number: m[1]!.replaceAll('O', '0'), year: null)),
  };
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
        final code = '${recognized[1]!.toUpperCase()} ${recognized[2]!}';
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

  List<int> numeric(String value, {required bool starsLine}) {
    final exact = NeLineDigits.parse(value.trim(), stars: starsLine);
    if (exact != null) return exact;
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
        starsLine: false,
      );
      if (marker != null) {
        stars = numeric(tail.substring(marker.end), starsLine: true);
        hasStars = true;
      }
    } else if (e != null && index != null && !hasStars) {
      stars = numeric(e[1]!, starsLine: true);
      hasStars = true;
    } else if (index != null &&
        !hasStars &&
        RegExp(r'^[0-9\s]+$').hasMatch(row)) {
      numbers.addAll(numeric(row, starsLine: false));
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
