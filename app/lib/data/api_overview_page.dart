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
      title: const Text('Atualização dos resultados'),
      actions: [
        IconButton(
          tooltip: 'Atualizar',
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
                title: Text('Serviço temporariamente indisponível'),
                subtitle: Text('Tente novamente mais tarde.'),
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
              'Resultados dos Jogos Santa Casa',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('API: luckyscan50-api.policlinicosdesantoandre.com'),
            const SizedBox(height: 12),
            const Text('Consulte o estado das atualizações.'),
            const SizedBox(height: 12),
            Text('Observações RSS: ${rows.length}'),
            Text('Conflitos comunicados: ${data['conflicts'] ?? '—'}'),
            const Divider(),
            for (final item in rows)
              Card(
                child: ListTile(
                  title: Text(
                    item['game'] == 'milhao' ? 'M1lhão' : 'Euromilhões',
                  ),
                  subtitle: Text(
                    'Concurso: ${item['drawId'] ?? '—'}\n'
                    'Validação: ${item['validation'] ?? '—'}\n'
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
            const Text('Os resultados são atualizados ao abrir a app.'),
          ],
        );
      },
    ),
  );
}
