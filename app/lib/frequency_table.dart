import 'package:flutter/material.dart';
import 'domain/wallet.dart';
import 'data/official_frequency_snapshot.dart';

class FrequencyTable extends StatefulWidget {
  const FrequencyTable({
    super.key,
    required this.draws,
    required this.receipts,
  });
  final List<Map<String, dynamic>> draws;
  final List<Receipt> receipts;
  @override
  State<FrequencyTable> createState() => _FrequencyTableState();
}

class _FrequencyTableState extends State<FrequencyTable> {
  bool stars = false;
  bool official = true;
  int column = 0;
  bool ascending = true;
  @override
  Widget build(BuildContext context) {
    final field = stars ? 'stars' : 'numbers';
    final confirmed = <String, Map<String, dynamic>>{};
    for (final draw in widget.draws) {
      if (draw['game'] == 'euromilhoes' &&
          ['complete', 'numbers_confirmed'].contains(draw['status'])) {
        confirmed['${draw['drawId']}'] = draw;
      }
    }
    final rows = List.generate(stars ? 12 : 50, (i) {
      final value = i + 1;
      final occurrences = official
          ? (stars ? officialStarCounts : officialNumberCounts)[i]
          : confirmed.values
                .where((d) => (d[field] as List? ?? []).contains(value))
                .length;
      final played = widget.receipts.fold<int>(
        0,
        (sum, receipt) =>
            sum +
            receipt.lines
                    .where(
                      (line) =>
                          (stars ? line.stars : line.numbers).contains(value),
                    )
                    .length *
                receipt.drawIds.length,
      );
      return [value, occurrences, played];
    });
    rows.sort((a, b) {
      final result = a[column].compareTo(b[column]);
      return result == 0
          ? a[0].compareTo(b[0])
          : (ascending ? result : -result);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Números')),
            ButtonSegment(value: true, label: Text('Estrelas')),
          ],
          selected: {stars},
          onSelectionChanged: (values) => setState(() => stars = values.first),
        ),
        SwitchListTile(
          title: const Text('Estatísticas oficiais'),
          subtitle: const Text('Jogos Santa Casa · 17/10/2026 às 03:00'),
          value: official,
          onChanged: (value) => setState(() => official = value),
        ),
        const SizedBox(height: 12),
        Text(
          official
              ? 'Jogos Santa Casa · 17/10/2026 · Toque num cabeçalho para ordenar.'
              : '${confirmed.length} concursos · Toque num cabeçalho para ordenar.',
        ),
        const Text('As minhas apostas: combinações jogadas por concurso.'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            sortColumnIndex: column,
            sortAscending: ascending,
            columns: [
              for (final label in [
                stars ? 'Estrela' : 'Número',
                'Saídas',
                'As minhas apostas',
              ])
                DataColumn(
                  label: Text(label),
                  numeric: true,
                  onSort: (index, direction) => setState(() {
                    column = index;
                    ascending = direction;
                  }),
                ),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [for (final value in row) DataCell(Text('$value'))],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
