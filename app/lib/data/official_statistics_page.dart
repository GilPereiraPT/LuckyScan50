import 'package:flutter/material.dart';
import 'official_statistics.dart';
import 'results_client.dart';
import 'wallet_store.dart';

class OfficialStatisticsPage extends StatefulWidget {
  const OfficialStatisticsPage({super.key, required this.store, this.client});
  final WalletStore store;
  final ResultsClient? client;
  @override
  State<OfficialStatisticsPage> createState() => _OfficialStatisticsPageState();
}

class _OfficialStatisticsPageState extends State<OfficialStatisticsPage> {
  late final ResultsClient client = widget.client ?? ResultsClient();
  late final cache = OfficialStatisticsCache(
    read: () => widget.store.setting('officialStatisticsCacheV1'),
    write: (value) =>
        widget.store.setSetting('officialStatisticsCacheV1', value),
  );
  OfficialStatistics? snapshot;
  List<Map<String, dynamic>> draws = [];
  bool loading = true, updating = false, stars = false;
  String query = '', order = 'Número', notice = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    OfficialStatistics? stored;
    var localDraws = <Map<String, dynamic>>[];
    var warning = '';
    try {
      stored = await cache.load();
    } catch (_) {
      warning =
          'Cache estatística inválida. Pode atualizar; a carteira foi preservada.';
    }
    try {
      localDraws = await widget.store.results();
    } catch (_) {
      warning =
          'Não foi possível carregar a amostra local. A cache oficial foi preservada.';
    }
    if (mounted) {
      setState(() {
        snapshot = stored;
        draws = localDraws;
        notice = warning;
        loading = false;
      });
    }
  }

  Future<void> refresh() async {
    if (updating) return;
    setState(() => updating = true);
    try {
      final accepted = await cache.accept(
        await client.fetchOfficialStatistics(),
      );
      if (mounted) {
        setState(() {
          snapshot = accepted;
          notice = 'Snapshot descarregado. Confirme abaixo a data da fonte.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => notice =
              'Estatísticas oficiais indisponíveis ou inválidas. A última cache continua disponível; a carteira não foi alterada.',
        );
      }
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  @override
  void dispose() {
    if (widget.client == null) client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cutoff = snapshot?.updatedAt.toUtc().toIso8601String().substring(
      0,
      10,
    );
    final local = draws
        .where(
          (d) =>
              d['game'] == 'euromilhoes' &&
              ['complete', 'numbers_confirmed'].contains(d['status']) &&
              (cutoff == null || (d['date'] as String).compareTo(cutoff) <= 0),
        )
        .toList();
    final localCounts = <int, int>{};
    for (final draw in local) {
      for (final value in draw[stars ? 'stars' : 'numbers'] as List) {
        if (value is int) {
          localCounts.update(value, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    }
    final rows =
        [
          ...(stars ? snapshot?.stars : snapshot?.numbers) ??
              <OfficialStatistic>[],
        ]..removeWhere(
          (r) => query.isNotEmpty && r.value.toString() != query.trim(),
        );
    rows.sort(
      (a, b) => switch (order) {
        'Saídas' => b.count.compareTo(a.count),
        'Percentagem' => b.percentage.compareTo(a.percentage),
        'Ausências' => (b.absences ?? -1).compareTo(a.absences ?? -1),
        _ => a.value.compareTo(b.value),
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estatísticas oficiais'),
        actions: [
          IconButton(
            tooltip: 'Atualizar estatísticas',
            onPressed: updating ? null : refresh,
            icon: updating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Frequências descritivas; não preveem números vencedores.',
                ),
                if (notice.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(notice, key: const Key('statistics-notice')),
                  ),
                if (snapshot == null)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Sem snapshot oficial em cache. Atualize quando a API disponibilizar dados validados.',
                    ),
                  ),
                if (snapshot != null) ...[
                  Text('Atualização da fonte: ${snapshot!.json['updatedAt']}'),
                  const Text(
                    'Cobertura declarada da fonte: desde 13/02/2004. Esta data não comprova a completude do histórico local.',
                  ),
                  Text('Fonte: ${snapshot!.json['sourceUrl']}'),
                  if (!snapshot!.referenceVerified)
                    const Text(
                      'Estrutura validada; confronto com a captura oficial de referência pendente.',
                    ),
                  const Text(
                    'Dados guardados offline. A data da fonte deve ser verificada antes de os considerar atuais.',
                  ),
                  const Text(
                    'As estrelas 10, 11 e 12 têm períodos de disponibilidade distintos. As percentagens publicadas não são recalculadas com um denominador comum.',
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Comparação: ${local.length} concursos com chave confirmada no dispositivo. Histórico completo não verificado. Data limite: ${cutoff ?? 'sem snapshot'}.',
                ),
                const Text(
                  'As saídas locais abaixo representam apenas essa amostra, não a frequência oficial.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Números'),
                      selected: !stars,
                      onSelected: (_) => setState(() => stars = false),
                    ),
                    ChoiceChip(
                      label: const Text('Estrelas'),
                      selected: stars,
                      onSelected: (_) => setState(() => stars = true),
                    ),
                  ],
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Pesquisar número ou estrela',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => query = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: order,
                  decoration: const InputDecoration(labelText: 'Ordenar por'),
                  items: ['Número', 'Saídas', 'Percentagem', 'Ausências']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => order = v);
                  },
                ),
                for (final row in rows)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${stars ? 'Estrela' : 'Número'} ${row.value} · ${row.count} saídas · ${row.percentage.toStringAsFixed(2)} %',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Semantics(
                            label:
                                '${row.percentage.toStringAsFixed(2)} por cento de saídas na fonte',
                            child: LinearProgressIndicator(
                              value: row.percentage / 100,
                            ),
                          ),
                          Text(
                            'Último concurso: ${row.lastDrawId ?? 'não indicado'} · ${row.lastDate ?? 'data não indicada'}',
                          ),
                          Text(
                            'Ausências: ${row.absences ?? 'não indicadas'} · Sorteios elegíveis: ${row.eligibleDraws ?? 'não indicados'}',
                          ),
                          Text(
                            'Saídas na amostra local: ${localCounts[row.value] ?? 0}',
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
