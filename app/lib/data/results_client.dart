import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/wallet.dart';

class ResultsClient {
  ResultsClient({
    http.Client? client,
    this.base = 'https://luckyscan50-api.policlinicosdesantoandre.com',
  }) : client = client ?? http.Client();
  final http.Client client;
  final String base;
  Future<List<Map<String, dynamic>>> fetch() async {
    final rows = <Map<String, dynamic>>[];
    for (final game in ['euromilhoes', 'milhao']) {
      var offset = 0;
      while (true) {
        final response = await client
            .get(
              Uri.parse('$base/v1/draws?game=$game&limit=100&offset=$offset'),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw const FormatException('A API de resultados está indisponível');
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final page = (body['data'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        for (final row in page) {
          validateDraw(row);
        }
        rows.addAll(page);
        // The deployed 0.1.1 API has no pagination metadata. Do not loop the same page.
        if (body['pagination'] is! Map ||
            body['pagination']['hasMore'] != true) {
          break;
        }
        if (page.isEmpty || offset >= 100000) {
          throw const FormatException('Paginação inválida');
        }
        offset += page.length;
      }
    }
    return rows;
  }

  Future<Map<String, dynamic>> fetchRssOverview() async {
    final response = await client
        .get(Uri.parse('$base/v1/rss/overview'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const FormatException('Informação RSS indisponível');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      throw const FormatException('Resposta RSS inválida');
    }
    return decoded;
  }

  void close() => client.close();
}

void validateDraw(Map<String, dynamic> row) {
  final drawId = row['drawId'];
  if (!['euromilhoes', 'milhao'].contains(row['game']) ||
      !['complete', 'numbers_confirmed'].contains(row['status']) ||
      drawId is! String ||
      !RegExp(r'^\d{3}/\d{4}$').hasMatch(drawId) ||
      int.parse(drawId.substring(0, 3)) == 0) {
    throw const FormatException('Resultado inválido');
  }

  DateTime? exactDate(dynamic value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    return parsed != null &&
            parsed.year > 0 &&
            parsed.toIso8601String().substring(0, 10) == value
        ? parsed
        : null;
  }

  final day = exactDate(row['date']);
  final retrievedText = row['retrievedAt'];
  final timestamp = retrievedText is String
      ? RegExp(
          r'^(\d{4}-\d{2}-\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(?:[.,]\d+)?(?:[Zz]|[+-](\d{2}):?(\d{2}))$',
        ).firstMatch(retrievedText)
      : null;
  final retrieved = retrievedText is String
      ? DateTime.tryParse(retrievedText)
      : null;
  final sourceText = row['sourceUrl'];
  final source = sourceText is String ? Uri.tryParse(sourceText) : null;
  if (day == null ||
      day.year != int.parse(drawId.substring(4)) ||
      timestamp == null ||
      exactDate(timestamp[1]) == null ||
      int.parse(timestamp[2]!) > 23 ||
      int.parse(timestamp[3]!) > 59 ||
      int.parse(timestamp[4]!) > 59 ||
      (timestamp[5] != null && int.parse(timestamp[5]!) > 23) ||
      (timestamp[6] != null && int.parse(timestamp[6]!) > 59) ||
      retrieved == null ||
      !retrieved.isUtc ||
      source == null ||
      source.scheme != 'https' ||
      source.host.isEmpty ||
      source.userInfo.isNotEmpty) {
    throw const FormatException('Origem ou datas inválidas');
  }
  if (row['game'] == 'milhao') {
    final winningCode = row['winningCode'];
    if (winningCode is! String ||
        !RegExp(r'^[A-Z]{3} ?\d{5}$').hasMatch(winningCode)) {
      throw const FormatException('Código inválido');
    }
    if (row['amountCents'] != null &&
        (row['amountCents'] is! int || (row['amountCents'] as int) < 0)) {
      throw const FormatException('Prémio inválido');
    }
    return;
  }
  for (final field in ['numbers', 'stars']) {
    final values = row[field];
    if (values is! List || values.any((value) => value is! int)) {
      throw const FormatException('Chave inválida');
    }
  }
  BetLine(List<int>.from(row['numbers']), List<int>.from(row['stars']));
  final tiers = row['tiers'];
  const combinations = [
    [5, 2],
    [5, 1],
    [5, 0],
    [4, 2],
    [4, 1],
    [3, 2],
    [4, 0],
    [2, 2],
    [3, 1],
    [3, 0],
    [1, 2],
    [2, 1],
    [2, 0],
  ];
  if (tiers is! List || tiers.length != 13) {
    throw const FormatException('Escalões incompletos');
  }
  for (var i = 0; i < 13; i++) {
    final tier = tiers[i];
    if (tier is! Map || !tier.containsKey('amountCents')) {
      throw const FormatException('Escalão inválido');
    }
    for (final field in ['winnersPortugal', 'winnersTotal']) {
      final value = tier[field];
      if (!tier.containsKey(field) ||
          (value != null && (value is! int || value < 0)) ||
          (row['status'] == 'complete' && value == null)) {
        throw const FormatException('Contagem de vencedores inválida');
      }
    }
    final portugal = tier['winnersPortugal'];
    final total = tier['winnersTotal'];
    if (portugal != null && total != null && portugal > total) {
      throw const FormatException('Contagem de vencedores inválida');
    }
    if (row['status'] == 'complete' &&
        (tier['winnersTotal'] as int) > 0 &&
        (tier['amountCents'] == null || tier['amountCents'] == 0)) {
      throw const FormatException('Prémio oficial em falta');
    }
    if (row['status'] == 'complete' && total == 0 && tier['amountCents'] == 0) {
      throw const FormatException('Prémio não atribuído deve ser nulo');
    }

    if (tier['tier'] != i + 1 ||
        tier['main'] != combinations[i][0] ||
        tier['stars'] != combinations[i][1] ||
        (tier['amountCents'] != null &&
            (tier['amountCents'] is! int ||
                (tier['amountCents'] as int) < 0))) {
      throw const FormatException('Escalão inválido');
    }
  }
}
