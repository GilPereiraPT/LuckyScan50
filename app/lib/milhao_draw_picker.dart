import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/results_client.dart';
import 'main.dart' show resultsProvider;

/// Only dated results and officially advertised future draws are selectable.
Map<String, String> milhaoDrawOptions(
  List<Map<String, dynamic>> results,
  List<dynamic> overview,
) {
  final options = <String, String>{};
  void add(dynamic id, dynamic date) {
    if (id is! String ||
        date is! String ||
        !RegExp(r'^\d{3}/\d{4}$').hasMatch(id) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      return;
    }
    final day = DateTime.tryParse(date);
    if (day == null ||
        day.toIso8601String().substring(0, 10) != date ||
        day.year.toString() != id.substring(4)) {
      return;
    }
    options[id] = date;
  }

  for (final row in overview.whereType<Map>()) {
    if (row['game'] != 'milhao' || row['validation'] != 'accepted') continue;
    final upcoming = row['upcoming'];
    if (upcoming is Map) add(upcoming['drawId'], upcoming['date']);
  }
  // Stored results take precedence over forecasts.
  for (final row in results) {
    if (row['game'] == 'milhao') add(row['drawId'], row['date']);
  }
  return options;
}

final milhaoOverviewProvider = FutureProvider<List<dynamic>>((ref) async {
  final client = ResultsClient();
  try {
    final overview = await client.fetchRssOverview();
    return overview['data'] as List<dynamic>;
  } finally {
    client.close();
  }
});

class MilhaoDrawPicker extends ConsumerWidget {
  const MilhaoDrawPicker({
    super.key,
    required this.controller,
    this.enabled = true,
  });
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(resultsProvider);
    final overview = ref.watch(milhaoOverviewProvider);
    final options = milhaoDrawOptions(
      results.asData?.value ?? [],
      overview.asData?.value ?? [],
    );
    final entries = options.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final selected = value.text
              .split(',')
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet();
          return InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Concursos M1lhão (opcional)',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final id in selected)
                  InputChip(
                    label: Text(
                      options[id] == null
                          ? id
                          : '$id — ${displayDate(options[id]!)}',
                    ),
                    onDeleted: !enabled
                        ? null
                        : () {
                            selected.remove(id);
                            controller.text = selected.join(', ');
                          },
                  ),
                DropdownButton<String>(
                  isExpanded: true,
                  hint: Text(
                    results.isLoading || overview.isLoading
                        ? 'A carregar concursos…'
                        : 'Escolher concurso e data',
                  ),
                  items: [
                    for (final entry in entries.where(
                      (entry) => !selected.contains(entry.key),
                    ))
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          '${entry.key} — ${displayDate(entry.value)}',
                        ),
                      ),
                  ],
                  onChanged: !enabled
                      ? null
                      : (id) {
                          if (id == null) return;
                          selected.add(id);
                          controller.text = selected.join(', ');
                        },
                ),
                if (entries.isEmpty &&
                    !results.isLoading &&
                    !overview.isLoading)
                  const Text('Ainda não há concursos com data disponível.'),
                if (overview.hasError)
                  TextButton.icon(
                    onPressed: !enabled
                        ? null
                        : () {
                            ref.invalidate(milhaoOverviewProvider);
                            ref.invalidate(resultsProvider);
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Atualizar concursos'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String displayDate(String iso) =>
      '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';
}
