import 'package:flutter/material.dart';

import 'results_client.dart';

class ApiOverviewPage extends StatefulWidget {
  const ApiOverviewPage({super.key});

  @override
  State<ApiOverviewPage> createState() => _ApiOverviewPageState();
}

class _ApiOverviewPageState extends State<ApiOverviewPage> {
  late Future<Map<String, dynamic>> overview;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    overview = load();
  }

  Future<Map<String, dynamic>> load() async {
    final client = ResultsClient();
    try {
      return await client.fetchRssOverview();
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('API e fontes de dados'),
      actions: [
        IconButton(
          tooltip: 'Atualizar estado da API',
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: overview,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('API temporariamente indisponível'),
                subtitle: Text('Os resultados guardados no dispositivo continuam acessíveis offline.'),
              ),
            ],
          );
        }
        final data = snapshot.data!;
        final rows = (data['data'] as List).whereType<Map>().toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'LuckyScan50 · Fonte de resultados',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('API: luckyscan50-api.policlinicosdesantoandre.com'),
            const SizedBox(height: 12),
            const Text(
              'Os feeds RSS são observações da fonte. A data de publicação não comprova a data do sorteio. Apenas concursos validados devem ser usados na verificação de prémios.',
            ),
            const SizedBox(height: 12),
            Text('Observações RSS: ${rows.length}'),
            Text('Conflitos comunicados: ${data['conflicts'] ?? '—'}'),
            const Divider(),
            for (final item in rows)
              Card(
                child: ListTile(
                  title: Text(item['game'] == 'milhao' ? 'M1lhão' : 'Euromilhões'),
                  subtitle: Text(
                    'Concurso: ${item['drawId'] ?? '—'}\\n'
                    'Validação: ${item['validation'] ?? '—'}\\n'
                    'Histórico: ${item['historyStatus'] ?? '—'}',
                  ),
                  isThreeLine: true,
                  trailing: Icon(
                    item['historyStatus'] == 'stored'
                        ? Icons.check_circle_outline
                        : Icons.pending_outlined,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'A sincronização dos concursos confirmados é efetuada pelo botão de sincronização no ecrã principal. Os bilhetes e imagens não são enviados à API.',
            ),
          ],
        );
      },
    ),
  );
}
