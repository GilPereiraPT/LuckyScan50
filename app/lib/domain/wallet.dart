import 'prize_calculator.dart';

int cents(String text) {
  final match = RegExp(
    r'^\s*(\d+)(?:[,.](\d{1,2}))?\s*€?\s*$',
  ).firstMatch(text);
  if (match == null) throw const FormatException('Valor monetário inválido');
  return int.parse(match[1]!) * 100 +
      int.parse((match[2] ?? '').padRight(2, '0'));
}

List<int> parseNumbers(String value, int count, int maximum) {
  final values = value.trim().split(RegExp(r'[ ,;]+')).map(int.parse).toList();
  if (values.length != count ||
      values.toSet().length != count ||
      values.any((n) => n < 1 || n > maximum)) {
    throw FormatException(
      'Introduza $count valores distintos entre 1 e $maximum',
    );
  }
  return values;
}

class BetLine {
  BetLine(this.numbers, this.stars) {
    parseNumbers(numbers.join(' '), 5, 50);
    parseNumbers(stars.join(' '), 2, 12);
  }
  final List<int> numbers;
  final List<int> stars;
  Map<String, dynamic> toJson() => {'numbers': numbers, 'stars': stars};
  factory BetLine.fromJson(Map<String, dynamic> j) => BetLine(
    List<int>.from(j['numbers'] as List),
    List<int>.from(j['stars'] as List),
  );
}

class Receipt {
  Receipt({
    required this.id,
    required this.createdAt,
    required this.source,
    required this.code,
    required this.costCents,
    required this.lines,
    required this.drawIds,
    this.milhaoDrawIds = const [],
    this.milhaoCodes = const [],
    this.receivedCents = 0,
    this.imagePath,
    this.drawDate,
  }) {
    if (drawDate != null) {
      final day = DateTime.tryParse(drawDate!);
      if (day == null || day.toIso8601String().substring(0, 10) != drawDate) {
        throw const FormatException('Data de sorteio inválida');
      }
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id) ||
        !['manual', 'physical', 'online'].contains(source) ||
        costCents < 0 ||
        receivedCents < 0 ||
        lines.isEmpty ||
        drawIds.isEmpty ||
        [
          ...drawIds,
          ...milhaoDrawIds,
        ].any((id) => !RegExp(r'^\d{3}/\d{4}$').hasMatch(id)) ||
        drawIds.toSet().length != drawIds.length ||
        milhaoDrawIds.toSet().length != milhaoDrawIds.length ||
        milhaoCodes.map((c) => c.replaceAll(' ', '')).toSet().length !=
            milhaoCodes.length ||
        milhaoCodes.isEmpty != milhaoDrawIds.isEmpty ||
        milhaoCodes.any(
          (code) => !RegExp(r'^[A-Z]{3} ?\d{5}$').hasMatch(code),
        )) {
      throw const FormatException('Recibo inválido');
    }
  }
  final String id, createdAt, source, code;
  final int costCents, receivedCents;
  final List<BetLine> lines;
  final List<String> drawIds, milhaoDrawIds, milhaoCodes;
  final String? imagePath, drawDate;
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt,
    'source': source,
    'code': code,
    'costCents': costCents,
    'receivedCents': receivedCents,
    'lines': lines.map((l) => l.toJson()).toList(),
    'drawIds': drawIds,
    'milhaoDrawIds': milhaoDrawIds,
    'milhaoCodes': milhaoCodes,
    'imagePath': imagePath,
    'drawDate': drawDate,
  };
  factory Receipt.fromJson(Map<String, dynamic> j) => Receipt(
    id: j['id'] as String,
    createdAt: j['createdAt'] as String,
    source: j['source'] as String,
    code: j['code'] as String,
    costCents: j['costCents'] as int,
    receivedCents: j['receivedCents'] as int? ?? 0,
    lines: (j['lines'] as List)
        .map((l) => BetLine.fromJson(Map<String, dynamic>.from(l as Map)))
        .toList(),
    drawIds: List<String>.from(j['drawIds'] as List),
    milhaoDrawIds: List<String>.from(j['milhaoDrawIds'] as List? ?? []),
    milhaoCodes: List<String>.from(j['milhaoCodes'] as List? ?? []),
    imagePath: j['imagePath'] as String?,
    drawDate: j['drawDate'] as String?,
  );
}

class Verification {
  const Verification(
    this.knownCents,
    this.pendingDraws,
    this.unknownPrizes,
    this.winningLines,
  );
  final int knownCents, pendingDraws, unknownPrizes, winningLines;
  bool get complete => pendingDraws == 0 && unknownPrizes == 0;
  String get label => pendingDraws > 0
      ? 'A aguardar'
      : unknownPrizes > 0
      ? 'Prémio por confirmar'
      : winningLines > 0
      ? 'Premiado'
      : 'Sem prémio';
}

Verification verify(Receipt receipt, List<Map<String, dynamic>> results) {
  int total = 0, pending = 0, unknown = 0, winners = 0;
  for (final id in receipt.drawIds) {
    final rows = results.where(
      (r) => r['game'] == 'euromilhoes' && r['drawId'] == id,
    );
    if (rows.isEmpty || rows.first['status'] != 'complete') {
      pending++;
      continue;
    }
    final draw = rows.first;
    for (final line in receipt.lines) {
      final main = line.numbers
          .toSet()
          .intersection(Set<int>.from(draw['numbers'] as List))
          .length;
      final stars = line.stars
          .toSet()
          .intersection(Set<int>.from(draw['stars'] as List))
          .length;
      final tier = tierFor(main, stars);
      if (tier == null) continue;
      winners++;
      final amount = (draw['tiers'] as List)[tier - 1]['amountCents'];
      if (amount == null) {
        unknown++;
      } else {
        total += amount as int;
      }
    }
  }
  for (final id in receipt.milhaoDrawIds) {
    final rows = results.where(
      (r) => r['game'] == 'milhao' && r['drawId'] == id,
    );
    if (rows.isEmpty || rows.first['status'] != 'complete') {
      pending++;
      continue;
    }
    final draw = rows.first;
    for (final code in receipt.milhaoCodes) {
      if (code.replaceAll(' ', '') ==
          (draw['winningCode'] as String).replaceAll(' ', '')) {
        winners++;
        if (draw['amountCents'] == null) {
          unknown++;
        } else {
          total += draw['amountCents'] as int;
        }
      }
    }
  }
  return Verification(total, pending, unknown, winners);
}

Map<String, int> finances(
  List<Receipt> receipts,
  List<Map<String, dynamic>> results,
) {
  final spent = receipts.fold(0, (sum, r) => sum + r.costCents);
  final identified = receipts.fold(
    0,
    (sum, r) => sum + verify(r, results).knownCents,
  );
  final received = receipts.fold(0, (sum, r) => sum + r.receivedCents);
  return {
    'spent': spent,
    'identified': identified,
    'received': received,
    'theoreticalBalance': identified - spent,
    'cashBalance': received - spent,
  };
}

String receiptStatus(Receipt receipt, Verification verification) {
  if (verification.complete &&
      verification.knownCents > 0 &&
      receipt.receivedCents >= verification.knownCents) {
    return 'Recebido';
  }
  return verification.label;
}
