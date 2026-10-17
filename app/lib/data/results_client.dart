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

  void close() => client.close();
}

void validateDraw(Map<String, dynamic> row) {
  if (!['euromilhoes', 'milhao'].contains(row['game']) ||
      !['complete', 'numbers_confirmed'].contains(row['status']) ||
      !RegExp(r'^\d{3}/\d{4}$').hasMatch(row['drawId'] as String? ?? '')) {
    throw const FormatException('Resultado inválido');
  }
  final day = DateTime.tryParse(row['date'] as String? ?? '');
  final retrieved = DateTime.tryParse(row['retrievedAt'] as String? ?? '');
  final source = Uri.tryParse(row['sourceUrl'] as String? ?? '');
  if (day == null ||
      retrieved == null ||
      source == null ||
      source.scheme != 'https' ||
      source.host.isEmpty) {
    throw const FormatException('Origem ou datas inválidas');
  }
  if (row['game'] == 'milhao') {
    if (!RegExp(
      r'^[A-Z]{3} ?\d{5}$',
    ).hasMatch(row['winningCode'] as String? ?? '')) {
      throw const FormatException('Código inválido');
    }
    if (row['amountCents'] != null &&
        (row['amountCents'] is! int || (row['amountCents'] as int) < 0)) {
      throw const FormatException('Prémio inválido');
    }
    return;
  }
  BetLine(
    List<int>.from(row['numbers'] as List),
    List<int>.from(row['stars'] as List),
  );
  final tiers = row['tiers'] as List;
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
  if (tiers.length != 13) throw const FormatException('Escalões incompletos');
  for (var i = 0; i < 13; i++) {
    final tier = tiers[i] as Map;
    for (final field in ['winnersPortugal', 'winnersTotal']) {
      final value = tier[field];
      if ((value != null && (value is! int || value < 0)) ||
          (row['status'] == 'complete' && value == null)) {
        throw const FormatException('Contagem de vencedores inválida');
      }
    }
    if (row['status'] == 'complete' &&
        (tier['winnersTotal'] as int) > 0 &&
        (tier['amountCents'] == null || tier['amountCents'] == 0)) {
      throw const FormatException('Prémio oficial em falta');
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
