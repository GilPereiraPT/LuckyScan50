import 'dart:convert';
import 'package:flutter/services.dart';
import 'results_client.dart';

/// Audited recent draws supplement the incomplete remote history offline.
/// Stored complete results take precedence, including later corrections.
Future<List<Map<String, dynamic>>> withRecentResults(
  List<Map<String, dynamic>> stored,
) async {
  final text = await rootBundle.loadString(
    'assets/results/recent_official.json',
  );
  final bundled = (jsonDecode(text) as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  for (final row in bundled) {
    validateDraw(row);
  }
  return mergeRecentResults(stored, bundled);
}

List<Map<String, dynamic>> mergeRecentResults(
  List<Map<String, dynamic>> stored,
  List<Map<String, dynamic>> bundled,
) {
  final results = <String, Map<String, dynamic>>{};
  for (final row in [...bundled, ...stored]) {
    final identity = '${row['game']}/${row['drawId']}';
    if (row['status'] != 'complete' &&
        results[identity]?['status'] == 'complete') {
      continue;
    }
    results[identity] = row;
  }
  return results.values.toList();
}
