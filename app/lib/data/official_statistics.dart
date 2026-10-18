import 'dart:convert';

class OfficialStatistic {
  const OfficialStatistic(
    this.value,
    this.count,
    this.percentage,
    this.lastDrawId,
    this.lastDate,
    this.absences,
    this.eligibleDraws,
  );
  final int value, count;
  final double percentage;
  final String? lastDrawId, lastDate;
  final int? absences, eligibleDraws;
}

/// A validated aggregate snapshot. It never creates individual draws or prizes.
class OfficialStatistics {
  OfficialStatistics._(this.json, this.numbers, this.stars, this.updatedAt);
  final Map<String, dynamic> json;
  final List<OfficialStatistic> numbers, stars;
  final DateTime updatedAt;
  String get fingerprint => jsonEncode([
    json['sourceUrl'],
    json['sourceSha256'],
    json['coverageStart'],
    updatedAt.toUtc().toIso8601String(),
    for (final rows in [numbers, stars])
      [
        for (final row in rows)
          [
            row.value,
            row.count,
            row.percentage,
            row.lastDrawId,
            row.lastDate,
            row.absences,
            row.eligibleDraws,
          ],
      ],
  ]);
  bool get referenceVerified => json['snapshotReferenceVerified'] == true;

  factory OfficialStatistics.parse(Map<String, dynamic> input) {
    final data = jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
    final source = Uri.tryParse(data['sourceUrl']?.toString() ?? '');
    final updated = data['updatedAt'];
    final time = updated is String ? DateTime.tryParse(updated) : null;
    final calendar = updated is String && updated.length >= 10
        ? updated.substring(0, 10)
        : '';
    final calendarDate = DateTime.tryParse(calendar);
    if (calendarDate == null ||
        calendarDate.toIso8601String().substring(0, 10) != calendar ||
        data['schemaVersion'] != 1 ||
        data['game'] != 'euromilhoes' ||
        data['coverageStart'] != '2004-02-13' ||
        source?.scheme != 'https' ||
        source?.host != 'www.jogossantacasa.pt' ||
        source?.path != '/web/SCEstatisticas/' ||
        time == null ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(updated as String) ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(data['sourceSha256']?.toString() ?? '')) {
      throw const FormatException('Origem ou cobertura estatística inválida');
    }
    List<OfficialStatistic> read(String field, int size) {
      final rows = data[field];
      if (rows is! List || rows.length != size) {
        throw const FormatException('Estatísticas incompletas');
      }
      final seen = <int>{};
      final result = <OfficialStatistic>[];
      for (final item in rows) {
        if (item is! Map) throw const FormatException('Indicador inválido');
        final value = item['value'], count = item['count'];
        final percent = double.tryParse(item['percentage'].toString());
        final last = item['lastDate'], draw = item['lastDrawId'];
        final absence = item['drawsSinceLast'],
            eligible = item['eligibleDraws'];
        final date = last is String ? DateTime.tryParse(last) : null;
        final percentText = item['percentage'].toString();
        final precision = percentText.contains('.')
            ? percentText.split('.').last.length
            : 0;
        final availabilityStart =
            field == 'stars' && value is int && value >= 10
            ? (value == 12 ? '2016-09-27' : '2011-05-10')
            : '2004-02-13';
        if (value is! int ||
            value < 1 ||
            value > size ||
            !seen.add(value) ||
            count is! int ||
            count < 0 ||
            percent == null ||
            !percent.isFinite ||
            percent < 0 ||
            percent > 100 ||
            !RegExp(
              r'^(?:0|[1-9]\d{0,2})(?:\.\d{1,6})?$',
            ).hasMatch(percentText) ||
            (count == 0 && (percent != 0 || last != null || draw != null)) ||
            (count > 0 &&
                (percent == 0 ||
                    last == null ||
                    draw == null ||
                    absence == null)) ||
            (absence != null && (absence is! int || absence < 0)) ||
            (eligible != null &&
                (eligible is! int ||
                    eligible < 1 ||
                    eligible < count ||
                    (absence is int && absence > eligible) ||
                    !_percentageAgrees(
                      count,
                      eligible,
                      percentText,
                      precision,
                    ))) ||
            ((last == null) != (draw == null)) ||
            (last != null &&
                (date == null ||
                    date.toIso8601String().substring(0, 10) != last ||
                    !RegExp(
                      r'^(?!000)\d{3}/\d{4}$',
                    ).hasMatch(draw.toString()) ||
                    date.year.toString() != draw.toString().substring(4) ||
                    last.toString().compareTo(availabilityStart) < 0 ||
                    date.toUtc().isAfter(time)))) {
          throw const FormatException('Indicador estatístico inválido');
        }
        result.add(
          OfficialStatistic(
            value,
            count,
            percent,
            draw as String?,
            last as String?,
            absence as int?,
            eligible as int?,
          ),
        );
      }
      result.sort((a, b) => a.value.compareTo(b.value));
      return List.unmodifiable(result);
    }

    return OfficialStatistics._(
      data,
      read('numbers', 50),
      read('stars', 12),
      time,
    );
  }
}

class OfficialStatisticsCache {
  OfficialStatisticsCache({required this.read, required this.write});
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  Future<OfficialStatistics?> load() async {
    final raw = await read();
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Cache inválida');
    }
    return OfficialStatistics.parse(decoded);
  }

  Future<OfficialStatistics> accept(Map<String, dynamic> response) async {
    if (response['available'] != true ||
        response['data'] is! Map<String, dynamic>) {
      throw const FormatException('Snapshot oficial ainda indisponível');
    }
    final next = OfficialStatistics.parse(
      response['data'] as Map<String, dynamic>,
    );
    OfficialStatistics? previous;
    try {
      previous = await load();
    } on FormatException {
      /* A corrupt cache can be replaced by valid data. */
    }
    if (previous != null &&
        (next.updatedAt.isBefore(previous.updatedAt) ||
            (next.updatedAt == previous.updatedAt &&
                next.fingerprint != previous.fingerprint))) {
      throw const FormatException(
        'Snapshot anterior ou divergente; cache preservada',
      );
    }
    await write(jsonEncode(next.json));
    return next;
  }
}

bool _percentageAgrees(
  int count,
  int eligible,
  String published,
  int precision,
) {
  final scale = BigInt.from(10).pow(precision);
  final numerator = BigInt.from(count) * BigInt.from(100) * scale;
  final denominator = BigInt.from(eligible);
  final rounded =
      (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
  return rounded == BigInt.parse(published.replaceAll('.', ''));
}
