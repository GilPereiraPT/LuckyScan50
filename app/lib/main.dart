import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'data/backup.dart';
import 'data/receipt_scanner.dart';
import 'data/receipt_crop_backend.dart';
import 'data/receipt_corners.dart';
import 'data/receipt_diagnostic_report.dart';
import 'domain/receipt_autofill.dart';
import 'data/results_client.dart';
import 'data/api_overview_page.dart';
import 'data/wallet_store.dart';
import 'domain/wallet.dart';
import 'manual_bets_page.dart';

const buildSha = String.fromEnvironment(
  'LUCKYSCAN_BUILD_SHA',
  defaultValue: 'local',
);
const appVersion = '0.2.4+6';

final receiptScannerProvider = Provider<ReceiptScanner>(
  (ref) => scanReceiptImage,
);

final storeProvider = Provider<WalletStore>(
  (ref) => throw UnimplementedError(),
);
final receiptsProvider = FutureProvider(
  (ref) => ref.watch(storeProvider).receipts(),
);
final resultsProvider = FutureProvider(
  (ref) => ref.watch(storeProvider).results(),
);
final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final money = NumberFormat.currency(locale: 'pt_PT', symbol: '€');
String euro(int value) => money.format(value / 100);

/// Keep the real LuckyScan50 identity visible on secondary pages.
Widget brandedPageTitle(String title) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Image.asset(
      'assets/branding/luckyscan50-logo.webp',
      width: 32,
      height: 32,
      fit: BoxFit.contain,
    ),
    const SizedBox(width: 10),
    Flexible(child: Text(title)),
  ],
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationDocumentsDirectory();
  final store = await WalletStore.open(
    p.join(directory.path, 'wallet.sqlite3'),
  );
  final savedTheme = await store.setting('theme');
  final initialTheme = ThemeMode.values.firstWhere(
    (mode) => mode.name == savedTheme,
    orElse: () => ThemeMode.system,
  );
  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        themeProvider.overrideWith((ref) => initialTheme),
      ],
      child: const LuckyScanApp(),
    ),
  );
}

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const Home()),
    GoRoute(path: '/add', builder: (_, __) => const AddReceipt()),
    GoRoute(path: '/manual', builder: (_, __) => const ManualBetPage()),
    GoRoute(path: '/about', builder: (_, __) => const AboutPage()),
    GoRoute(path: '/api', builder: (_, __) => const ApiOverviewPage()),
    GoRoute(
      path: '/receipt/:id',
      builder: (_, state) => ReceiptPage(state.pathParameters['id']!),
    ),
  ],
);

class LuckyScanApp extends ConsumerWidget {
  const LuckyScanApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ThemeData theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffc5a45d),
        brightness: brightness,
        primary: brightness == Brightness.dark
            ? const Color(0xffe7c77f)
            : const Color(0xff172841),
      ),
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xff0c1523)
          : const Color(0xfff5f6f9),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
    return MaterialApp.router(
      title: 'LuckyScan50',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'PT'),
      supportedLocales: const [Locale('pt', 'PT')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ref.watch(themeProvider),
      routerConfig: router,
    );
  }
}

class Home extends ConsumerStatefulWidget {
  const Home({super.key});
  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !syncing) {
      sync();
    }
  }

  int index = 0;
  bool syncing = false;
  String search = '', filter = 'Todos';
  Future<void> sync() async {
    setState(() => syncing = true);
    final client = ResultsClient();
    try {
      final rows = await client.fetch();
      await ref.read(storeProvider).saveResults(rows);
      ref.invalidate(resultsProvider);
      if (mounted) {
        message(
          context,
          'Resultados atualizados. ${rows.length} concursos disponíveis offline.',
        );
      }
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Não foi possível sincronizar. Os dados guardados continuam disponíveis.',
        );
      }
    } finally {
      client.close();
      if (mounted) setState(() => syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptsProvider);
    final results = ref.watch(resultsProvider);
    const titles = [
      'A sua carteira',
      'Bilhetes',
      'Sorteios',
      'Estatísticas',
      'Definições',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/branding/luckyscan50-logo.webp',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(titles[index])),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar resultados',
            onPressed: syncing ? null : sync,
            icon: syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: receipts.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) =>
                const Empty('Não foi possível abrir a carteira local.'),
            data: (tickets) => results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => const Empty(
                'Não foi possível abrir os resultados guardados.',
              ),
              data: (draws) => ListView(
                padding: const EdgeInsets.all(20),
                children: content(tickets, draws),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: index < 2
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/manual'),
              icon: const Icon(Icons.grid_view_rounded),
              label: const Text('Criar aposta manual'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            label: 'Bilhetes',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Sorteios',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart),
            label: 'Estatísticas',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Definições',
          ),
        ],
      ),
    );
  }

  List<Widget> content(
    List<Receipt> tickets,
    List<Map<String, dynamic>> draws,
  ) {
    final totals = finances(tickets, draws);
    if (index == 0) {
      return [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset(
            'assets/branding/luckyscan50-banner.webp',
            width: double.infinity,
            fit: BoxFit.contain,
            semanticLabel: 'LuckyScan50 — Bilhetes, Prémios e Estatísticas',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${tickets.length} recibos · ${draws.length} concursos guardados',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Nova aposta manual'),
            subtitle: const Text(
              'Selecionar números e estrelas sem fotografia',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/manual'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Fotografar ou importar talão'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/add'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_done_outlined),
            title: const Text('Resultados e fonte de dados'),
            subtitle: const Text(
              'Consultar a API LuckyScan50 e o estado dos feeds',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/api'),
          ),
        ),
        const SizedBox(height: 16),
        metric('Total apostado', totals['spent']!),
        metric('Prémios identificados', totals['identified']!),
        metric('Efetivamente recebido', totals['received']!),
        metric('Saldo de caixa', totals['cashBalance']!),
        const Text(
          'Os prémios desconhecidos não entram nos totais. A despesa é registada uma vez por recibo.',
        ),
        const SizedBox(height: 20),
        const Text(
          'Atividade recente',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (tickets.isEmpty)
          const Empty(
            'Comece por registar uma aposta manual ou importar uma imagem.',
          ),
        ...tickets.take(3).map((r) => ticketTile(r, draws)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Projeto não oficial, independente dos Jogos Santa Casa. Confirme sempre os prémios pelo operador autorizado.',
          ),
        ),
      ];
    }
    if (index == 1) {
      final filtered = tickets
          .where(
            (r) =>
                (r.code.toLowerCase().contains(search.toLowerCase()) ||
                    r.drawIds.join(' ').contains(search)) &&
                (filter == 'Todos' ||
                    receiptStatus(r, verify(r, draws)) == filter),
          )
          .toList();
      return [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Pesquisar recibo ou concurso',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (s) => setState(() => search = s),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children:
              [
                    'Todos',
                    'A aguardar',
                    'Premiado',
                    'Sem prémio',
                    'Prémio por confirmar',
                    'Recebido',
                  ]
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s),
                      selected: filter == s,
                      onSelected: (_) => setState(() => filter = s),
                    ),
                  )
                  .toList(),
        ),
        if (filtered.isEmpty) const Empty('Sem bilhetes para esta pesquisa.'),
        ...filtered.map((r) => ticketTile(r, draws)),
      ];
    }
    if (index == 2) {
      return [
        const Text(
          'Resultados guardados',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Atualize para descarregar os concursos disponíveis. Os resultados ficam acessíveis offline.',
        ),
        if (draws.isEmpty)
          const Empty('Sem resultados. Toque no botão de sincronização.'),
        ...([
          ...draws,
        ]..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String))).map(
          (d) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d['game'] == 'milhao' ? 'M1lhão' : 'Euromilhões'} · ${d['drawId']}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${d['date']} · ${d['status'] == 'complete' ? 'Completo' : 'Parcial — valores por confirmar'}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    d['game'] == 'milhao'
                        ? '${d['winningCode']}'
                        : '${(d['numbers'] as List).join('  ')}   ★ ${(d['stars'] as List).join('  ')}',
                    style: const TextStyle(fontSize: 22),
                  ),
                  if (d['game'] == 'euromilhoes')
                    ExpansionTile(
                      title: const Text('13 escalões'),
                      children: (d['tiers'] as List)
                          .map<Widget>(
                            (t) => ListTile(
                              title: Text(
                                '${t['tier']}.º · ${t['main']} + ${t['stars']}',
                              ),
                              trailing: Text(
                                t['amountCents'] == null
                                    ? 'Não atribuído / desconhecido'
                                    : euro(t['amountCents'] as int),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  Text(
                    'Fonte: ${d['sourceUrl']}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }
    if (index == 3) {
      final complete = draws
          .where((d) => d['game'] == 'euromilhoes' && d['status'] == 'complete')
          .toList();
      return [
        const Text(
          'Finanças e frequências',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        metric('Saldo teórico', totals['theoreticalBalance']!),
        metric('Saldo de caixa', totals['cashBalance']!),
        ListTile(
          title: const Text('Retorno identificado'),
          trailing: Text(
            totals['spent'] == 0
                ? '—'
                : '${(totals['identified']! * 100 / totals['spent']!).toStringAsFixed(1)} %',
          ),
        ),
        Text(
          '${complete.length} concursos completos em cache. Estas frequências não são previsões.',
        ),
        const SizedBox(height: 16),
        ...List.generate(50, (i) {
          final n = i + 1;
          final official = complete
              .where((d) => (d['numbers'] as List).contains(n))
              .length;
          final personal = tickets.fold(
            0,
            (sum, r) =>
                sum + r.lines.where((l) => l.numbers.contains(n)).length,
          );
          return ListTile(
            dense: true,
            leading: CircleAvatar(child: Text('$n')),
            title: Text('$official ocorrências nos sorteios guardados'),
            subtitle: Text('$personal chaves pessoais'),
          );
        }),
      ];
    }
    return [
      const Text(
        'Privacidade e preferências',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      DropdownButtonFormField<ThemeMode>(
        initialValue: ref.watch(themeProvider),
        decoration: const InputDecoration(labelText: 'Tema'),
        items: const [
          DropdownMenuItem(value: ThemeMode.system, child: Text('Sistema')),
          DropdownMenuItem(value: ThemeMode.light, child: Text('Claro')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Escuro')),
        ],
        onChanged: (v) async {
          if (v == null) return;
          ref.read(themeProvider.notifier).state = v;
          await ref.read(storeProvider).setSetting('theme', v.name);
        },
      ),
      const SizedBox(height: 16),
      ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: const Text('API e fontes oficiais'),
        subtitle: const Text('Estado dos resultados, RSS e sincronização'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/api'),
      ),
      const SizedBox(height: 16),
      const Text(
        'Os recibos e imagens ficam no armazenamento privado da aplicação. Não são enviados à API. Não introduza palavras-passe dos Jogos Santa Casa.',
      ),
      ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('Criar cópia encriptada'),
        subtitle: const Text('Inclui recibos e imagens no dispositivo'),
        onTap: () => backup(tickets),
      ),
      ListTile(
        leading: const Icon(Icons.restore),
        title: const Text('Restaurar cópia'),
        onTap: restore,
      ),
      ListTile(
        leading: const Icon(Icons.table_chart_outlined),
        title: const Text('Exportar recibos CSV'),
        onTap: () => exportCsv(tickets, draws),
      ),
      ListTile(
        leading: const Icon(Icons.delete_forever),
        title: const Text('Eliminar todos os dados locais'),
        onTap: erase,
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('Sobre o LuckyScan50'),
        subtitle: const Text('Conheça a aplicação, privacidade e limitações'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/about'),
      ),
      const Divider(),
      const Text(
        'Disponível: carteira manual, OCR com confirmação, resultados offline, verificação e exportação. Alertas automáticos, prazos regulamentares e bloqueio biométrico ainda não estão disponíveis.',
      ),
      const SizedBox(height: 20),
      const Text(
        'LuckyScan50 · Gil Pereira · versão $appVersion · $buildSha\nAplicação não oficial. Nunca utilize estatísticas como previsão de prémios.',
      ),
    ];
  }

  Widget ticketTile(Receipt receipt, List<Map<String, dynamic>> draws) {
    final check = verify(receipt, draws);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const Icon(Icons.confirmation_number_outlined),
        title: Text(
          receipt.code.isEmpty
              ? 'Recibo ${receipt.id.substring(0, receipt.id.length < 6 ? receipt.id.length : 6)}'
              : receipt.code,
        ),
        subtitle: Text(
          '${receipt.drawIds.join(', ')}\n${receiptStatus(receipt, check)} · ${euro(receipt.costCents)}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/receipt/${receipt.id}'),
      ),
    );
  }

  Future<void> backup(List<Receipt> tickets) async {
    final password = await askPassword(context);
    if (password == null) return;
    try {
      final encrypted = await WalletBackup.encrypt(tickets, password);
      final file = File(
        p.join((await getTemporaryDirectory()).path, 'luckyscan50.backup'),
      );
      await file.writeAsString(encrypted, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Cópia encriptada LuckyScan50',
        ),
      );
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Não foi possível criar a cópia. Use uma palavra-passe com pelo menos 12 caracteres.',
        );
      }
    }
  }

  Future<void> restore() async {
    final selected = await FilePicker.platform.pickFiles();
    if (selected == null || selected.files.single.path == null || !mounted) {
      return;
    }
    final password = await askPassword(context);
    if (password == null) return;
    try {
      final text = await File(selected.files.single.path!).readAsString();
      final imageDirectory = p.join(
        (await getApplicationDocumentsDirectory()).path,
        'receipts',
      );
      final receipts = await WalletBackup.decrypt(
        text,
        password,
        imageDirectory: imageDirectory,
      );
      await ref.read(storeProvider).restore(receipts);
      ref.invalidate(receiptsProvider);
      if (mounted) {
        message(
          context,
          'Cópia restaurada. Recibos já existentes foram preservados.',
        );
      }
    } catch (_) {
      if (mounted) {
        message(context, 'Cópia inválida ou palavra-passe incorreta.');
      }
    }
  }

  Future<void> exportCsv(
    List<Receipt> tickets,
    List<Map<String, dynamic>> draws,
  ) async {
    String cell(String s) {
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final rows = [
      'recibo;origem;concursos;apostado_centimos;identificado_centimos;recebido_centimos',
      ...tickets.map(
        (r) => [
          cell(r.code),
          cell(r.source),
          cell(r.drawIds.join(',')),
          r.costCents,
          verify(r, draws).knownCents,
          r.receivedCents,
        ].join(';'),
      ),
    ];
    try {
      final file = File(
        p.join((await getTemporaryDirectory()).path, 'luckyscan50.csv'),
      );
      await file.writeAsString('\uFEFF${rows.join('\r\n')}');
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      if (mounted) message(context, 'Não foi possível exportar.');
    }
  }

  Future<void> erase() async {
    if (!await confirm(
      context,
      'Eliminar todos os recibos, histórico, imagens e resultados deste dispositivo?',
    )) {
      return;
    }
    await ref.read(storeProvider).erase();
    final images = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'receipts'),
    );
    if (await images.exists()) await images.delete(recursive: true);
    for (final name in ['luckyscan50.backup', 'luckyscan50.csv']) {
      final file = File(p.join((await getTemporaryDirectory()).path, name));
      if (await file.exists()) await file.delete();
    }
    ref.invalidate(receiptsProvider);
    ref.invalidate(resultsProvider);
  }
}

class Empty extends StatelessWidget {
  const Empty(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Text(text, textAlign: TextAlign.center),
  );
}

Widget metric(String title, int value) => Card(
  child: ListTile(
    title: Text(title),
    trailing: Text(
      euro(value),
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    ),
  ),
);
void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
Future<bool> confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ) ??
    false;
Future<String?> askPassword(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Palavra-passe da cópia'),
      content: TextField(
        controller: controller,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Pelo menos 12 caracteres',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
  // Dialog animations may still use its controller at this point.
  return result;
}

class AddReceipt extends ConsumerStatefulWidget {
  const AddReceipt({super.key});
  @override
  ConsumerState<AddReceipt> createState() => _AddReceiptState();
}

class _AddReceiptState extends ConsumerState<AddReceipt> {
  final code = TextEditingController(),
      cost = TextEditingController(),
      draws = TextEditingController(),
      milhaoDraws = TextEditingController(),
      milhaoCodes = TextEditingController(),
      lines = TextEditingController(),
      receiptDate = TextEditingController(),
      expectedCount = TextEditingController();
  String source = 'manual', ocrText = '';
  File? image;
  final _temporaryRectified = <String>{};
  bool busy = false;
  bool saving = false;
  bool milhaoDetected = false;
  int? expectedBets;
  bool milhaoDeferred = false;
  ReceiptScan? lastScan;
  final previousOcr = <String, String>{};
  Map<String, TextEditingController> get scanFields => {
    'code': code,
    'cost': cost,
    'draws': draws,
    'lines': lines,
    'date': receiptDate,
    'expected': expectedCount,
    'milhaoCodes': milhaoCodes,
  };
  @override
  void dispose() {
    for (final c in [
      code,
      cost,
      draws,
      milhaoDraws,
      milhaoCodes,
      lines,
      receiptDate,
      expectedCount,
    ]) {
      c.dispose();
    }
    // Corrected images are temporary until explicitly copied into the wallet.
    // Never delete the original camera/gallery image.
    for (final path in _temporaryRectified) {
      File(path).delete().catchError((Object _) => File(path));
    }
    super.dispose();
  }

  Future<ReceiptScan?> _guidedScan(ImageSource selected) async {
    final picked = await ImagePicker().pickImage(source: selected);
    if (picked == null || !mounted) return null;
    const backend = ReceiptCropBackend();
    final preview = await backend.prepare(picked.path, preview: true);
    try {
      if (!mounted) return null;
      final corners = await Navigator.of(context).push<List<ReceiptCorner>>(
        MaterialPageRoute(
          builder: (_) => ReceiptCornersPage(
            path: preview.path,
            width: preview.width,
            height: preview.height,
          ),
        ),
      );
      if (corners == null || !mounted) return null;
      if (corners.isEmpty) return scanReceiptFile(picked.path);
      final corrected = await backend.rectify(preview, [
        for (final corner in corners) ...[corner.x, corner.y],
      ]);
      try {
        final scan = await scanReceiptFile(corrected);
        _temporaryRectified.add(corrected);
        return scan;
      } catch (_) {
        try {
          await File(corrected).delete();
        } catch (_) {
          // Temporary cache cleanup will also occur on next app start.
        }
        rethrow;
      }
    } finally {
      await backend.dispose(preview);
    }
  }

  Future<void> scan(
    ImageSource selected, {
    bool additionalMilhao = false,
    bool guided = false,
  }) async {
    if (busy || saving) return;
    final atStart = {
      for (final entry in scanFields.entries) entry.key: entry.value.text,
    };
    setState(() => busy = true);
    try {
      final result = guided
          ? await _guidedScan(selected)
          : await ref.read(receiptScannerProvider)(selected);
      if (result == null || !mounted) return;
      final fields = scanFields;
      final updates = receiptAutofill(
        result.receipt,
        current: {
          for (final entry in fields.entries) entry.key: entry.value.text,
        },
        atStart: atStart,
        previousOcr: previousOcr,
      );
      if (additionalMilhao) {
        updates.removeWhere((key, _) => key != 'milhaoCodes');
      }
      setState(() {
        if (!additionalMilhao) {
          if (result.imagePath != null) image = File(result.imagePath!);
          ocrText = result.rawText;
          source = source == 'manual' ? 'physical' : source;
          milhaoDetected = result.receipt.hasMilhao;
          milhaoDeferred = false;
          expectedBets = result.receipt.expectedLines;
        } else {
          ocrText = '$ocrText\n--- M1LHÃO ---\n${result.rawText}';
        }
        if (!additionalMilhao) lastScan = result;
        for (final entry in updates.entries) {
          fields[entry.key]!.text = entry.value;
          previousOcr[entry.key] = entry.value;
        }
      });
      message(
        context,
        additionalMilhao
            ? 'Boletim M1lhão lido. Confirme o código e o concurso; identificadores do recibo não são códigos de participação.'
            : '${result.receipt.lines.length} aposta(s) completa(s) reconhecida(s). Confirme todos os campos. Edições manuais foram preservadas.',
      );
    } on ReceiptScanFailure catch (error) {
      if (mounted) {
        message(
          context,
          'Falha em ${error.stage} (${error.errorType}). Pode continuar manualmente.',
        );
      }
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Falha ao preencher o formulário. Os campos anteriores foram preservados.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> scanMilhao(ImageSource selected) =>
      scan(selected, additionalMilhao: true);
  Future<void> save() async {
    if (saving || busy) return;
    setState(() => saving = true);
    try {
      if (lines.text.contains('?')) {
        throw const FormatException(
          'Há apostas pendentes: complete ou corrija o formulário antes de guardar.',
        );
      }
      final parsed = lines.text
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) {
            final parts = l.split('+');
            if (parts.length != 2) {
              throw const FormatException(
                'Cada chave deve ter números + estrelas',
              );
            }
            return BetLine(
              parseNumbers(parts[0], 5, 50),
              parseNumbers(parts[1], 2, 12),
            );
          })
          .toList();
      final expected = expectedCount.text.trim().isEmpty
          ? null
          : int.tryParse(expectedCount.text);
      if (expectedCount.text.trim().isNotEmpty &&
          (expected == null || expected < 1)) {
        throw const FormatException('Número esperado de apostas inválido');
      }
      if (expected != null && parsed.length != expected) {
        throw FormatException(
          'Reconhecidas $expected apostas esperadas: complete ou corrija o formulário antes de guardar.',
        );
      }
      List<String> ids(String text) =>
          text.split(RegExp(r'[,;\s]+')).where((s) => s.isNotEmpty).toList();
      final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final receipt = Receipt(
        id: id,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        source: source,
        code: code.text.trim(),
        costCents: cents(cost.text),
        drawDate: receiptDate.text.trim().isEmpty
            ? null
            : receiptDate.text.trim(),
        lines: parsed,
        drawIds: ids(draws.text),
        milhaoDrawIds: ids(milhaoDraws.text),
        milhaoCodes: milhaoCodes.text
            .split(RegExp(r'[,;\n]+'))
            .map((s) => s.trim().toUpperCase())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
      if (receipt.milhaoDrawIds.isNotEmpty && receipt.milhaoCodes.isEmpty) {
        throw const FormatException('Introduza os códigos M1lhão');
      }
      if (await ref
          .read(storeProvider)
          .duplicateCode(receipt.code, receipt.id)) {
        if (!mounted ||
            !await confirm(
              context,
              'Já existe um recibo com este identificador. Guardar uma aposta distinta?',
            )) {
          return;
        }
      }
      if (!mounted ||
          !await confirm(
            context,
            'Confirmou todas as chaves, concursos e o valor total de ${euro(receipt.costCents)}?',
          )) {
        return;
      }
      if (image != null) {
        final dir = Directory(
          p.join((await getApplicationDocumentsDirectory()).path, 'receipts'),
        );
        await dir.create(recursive: true);
        final copied = await image!.copy(p.join(dir.path, '$id.jpg'));
        await ref
            .read(storeProvider)
            .save(
              Receipt.fromJson({...receipt.toJson(), 'imagePath': copied.path}),
            );
      } else {
        await ref.read(storeProvider).save(receipt);
      }
      ref.invalidate(receiptsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        message(
          context,
          e is FormatException
              ? e.message
              : 'Não foi possível guardar o recibo.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: brandedPageTitle('Confirmar aposta')),
    bottomNavigationBar: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: busy || saving ? null : save,
          icon: const Icon(Icons.check),
          label: const Text('Confirmar e guardar'),
        ),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            const Text(
              'Uma despesa por recibo',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Agrupe as secções Euromilhões e M1lhão do mesmo comprovativo. Confirme os campos antes de guardar.',
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              initiallyExpanded: true,
              title: const Text('OCR direto, sem corrigir perspetiva'),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy || saving
                          ? null
                          : () => scan(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Fotografar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy || saving
                          ? null
                          : () => scan(ImageSource.gallery),
                      icon: const Icon(Icons.image),
                      label: const Text('Importar imagem'),
                    ),
                  ],
                ),
              ],
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Captura com moldura de quatro cantos',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Fotografe o talão completo e ajuste os cantos '
                      'do papel antes de iniciar o OCR. A correção é opcional '
                      'e pode ser dispensada para usar a fotografia original.',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: busy || saving
                              ? null
                              : () => scan(ImageSource.camera, guided: true),
                          icon: const Icon(Icons.crop_free),
                          label: const Text('Fotografar com moldura'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy || saving
                              ? null
                              : () => scan(ImageSource.gallery, guided: true),
                          icon: const Icon(Icons.photo_size_select_large),
                          label: const Text('Importar com moldura'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (busy) const LinearProgressIndicator(),
            if (image != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Image.file(image!, height: 180),
              ),
            if (expectedBets != null && ocrText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Apostas completas: ${lastScan?.receipt.lines.length ?? 0} / $expectedBets',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (milhaoDetected && !milhaoDeferred)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fotografe o boletim do M1lhão',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'O código M1lhão não é o identificador do recibo. Confirme o código antes de guardar.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: busy || saving
                                ? null
                                : () => scanMilhao(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Fotografar M1lhão'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy || saving
                                ? null
                                : () => scanMilhao(ImageSource.gallery),
                            icon: const Icon(Icons.image),
                            label: const Text('Importar M1lhão'),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => milhaoDeferred = true),
                            child: const Text('Adiar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (lastScan != null) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.ios_share),
                label: const Text('Exportar relatório OCR'),
                onPressed: busy || saving
                    ? null
                    : () async {
                        try {
                          final report = receiptDiagnosticReport(
                            lastScan!,
                            build: buildSha,
                            version: appVersion,
                          );
                          final directory = await getTemporaryDirectory();
                          final file = File(
                            p.join(
                              directory.path,
                              'LuckyScan50-OCR-${DateTime.now().millisecondsSinceEpoch}.json',
                            ),
                          );
                          await file.writeAsString(
                            const JsonEncoder.withIndent('  ').convert(report),
                          );
                          await SharePlus.instance.share(
                            ShareParams(
                              files: [
                                XFile(file.path, mimeType: 'application/json'),
                              ],
                              subject: 'LuckyScan50 — diagnóstico OCR',
                            ),
                          );
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Não foi possível exportar o relatório OCR.',
                              ),
                            ),
                          );
                        }
                      },
              ),
              const Text(
                'Inclui texto reconhecido do recibo; sem fotografias. '
                'As edições manuais do formulário não entram no relatório.',
              ),
            ],
            if (lastScan?.recoveryError != null)
              Text(
                'Recuperação indisponível; leitura inicial preservada: ${lastScan!.recoveryError}',
              ),
            if (lastScan?.multiPass != null)
              ExpansionTile(
                title: const Text(
                  'Passagens de recuperação e origem dos valores',
                ),
                children: [
                  SelectableText(
                    'Antes: ${(lastScan!.initialReceipt ?? lastScan!.multiPass!.initial).lines.length} apostas completas; '
                    'depois: ${lastScan!.receipt.lines.length}. OCR inicial ${lastScan!.ocrMs} ms; recuperação ${lastScan!.multiPass!.elapsedMs} ms.\n'
                    'Zona das apostas: ${lastScan!.multiPass!.plan.zone?.toJson()}\n'
                    'Elementos verticais intersectantes: ${lastScan!.multiPass!.plan.verticalElements.map((v) => '${v.text} (${v.height.toStringAsFixed(1)} px, ${v.angle.toStringAsFixed(1)}°)').join('; ')}',
                  ),
                  if (lastScan!.initialReceipt != null)
                    ExpansionTile(
                      title: const Text(
                        'Primeira passagem preservada — coordenadas e texto',
                      ),
                      children: [
                        SelectableText(
                          '${lastScan!.rawText}\n'
                          '${lastScan!.initialReceipt!.observations.map((t) => '${t.text} @ x=${t.x}, y=${t.y}, w=${t.width}, h=${t.height}, a=${t.angle}').join('\n')}',
                        ),
                      ],
                    ),
                  for (final pass in lastScan!.orientationPasses)
                    SelectableText(
                      'Orientação ${pass.turns * 90}°: ${pass.rows} linhas observadas, ${pass.elapsedMs} ms\n${pass.frame.text}',
                    ),
                  for (final pass in lastScan!.multiPass!.passes)
                    SelectableText(
                      '${pass.id}: recorte ${pass.crop.box.toJson()}, ${pass.elapsedMs} ms totais; '
                      'motor ${pass.frame?.elapsedMs ?? 0} ms; erro ${pass.error ?? 'nenhum'}\n${pass.frame?.text ?? ''}',
                    ),
                  for (final bet in lastScan!.multiPass!.evidence)
                    ListTile(
                      title: Text('Aposta ${bet.index} — proveniência'),
                      subtitle: SelectableText(
                        'Valores aceites: ${bet.acceptedValues.map((v) => v.description).join('; ')}\n'
                        'Observações de todas as passagens: ${bet.candidates.map((v) => v.description).join('; ')}\n'
                        'Incertezas: ${bet.issues.join('; ')}',
                      ),
                    ),
                ],
              ),
            if (lastScan != null) ...[
              Text(
                'Jogo: ${lastScan!.receipt.game ?? 'não identificado'} · ${lastScan!.receipt.lines.length} apostas completas',
              ),
              for (final bet in lastScan!.receipt.bets.where(
                (b) => !b.complete,
              ))
                ListTile(
                  title: Text('Aposta ${bet.index} incompleta — confirmar'),
                  subtitle: Text('${bet.formLine}\n${bet.issues.join('; ')}'),
                ),
              for (final warning in lastScan!.receipt.warnings) Text(warning),
              ExpansionTile(
                title: const Text('Diagnóstico local da leitura'),
                children: [
                  SelectableText(
                    'Imagem → ML Kit local; retificação de perspetiva quando selecionada\n'
                    'ML Kit: ${lastScan!.rawText.length} caracteres, ${lastScan!.receipt.tokenCount} elementos, ${lastScan!.ocrMs} ms\n'
                    'Reconstrução: ${lastScan!.receipt.strategy}, inclinação ${lastScan!.receipt.skewDegrees.toStringAsFixed(1)}°\n'
                    'Interpretação e recuperação: ${lastScan!.receipt.lines.length} apostas completas, ${lastScan!.parseMs} ms\n'
                    'Elementos (x,y,altura,ângulo):\n${lastScan!.receipt.observations.map((t) => '${t.text} @ ${t.x.toStringAsFixed(1)},${t.y.toStringAsFixed(1)},${t.height.toStringAsFixed(1)},${t.angle.toStringAsFixed(1)}').join('\n')}\n'
                    'Linhas reconstruídas:\n${lastScan!.receipt.rows.join('\n')}',
                  ),
                ],
              ),
            ],
            if (ocrText.isNotEmpty)
              ExpansionTile(
                title: const Text('Texto OCR local — consultar transcrição'),
                children: [SelectableText(ocrText)],
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: source,
              decoration: const InputDecoration(labelText: 'Origem'),
              items: const [
                DropdownMenuItem(value: 'manual', child: Text('Manual')),
                DropdownMenuItem(
                  value: 'physical',
                  child: Text('Bilhete físico'),
                ),
                DropdownMenuItem(value: 'online', child: Text('Aposta online')),
              ],
              onChanged: (v) => setState(() => source = v!),
            ),
            field(code, 'Identificador do recibo (opcional)'),
            field(cost, 'Valor total pago (€)', hint: '2,50'),
            field(draws, 'Concursos Euromilhões', hint: '083/2026, 084/2026'),
            field(receiptDate, 'Data do sorteio (AAAA-MM-DD)'),
            field(expectedCount, 'Número esperado de apostas (confirmar)'),
            field(
              lines,
              'Chaves — uma por linha',
              hint: '1 2 3 4 5 + 1 2',
              minLines: 5,
              maxLines: null,
            ),
            field(milhaoDraws, 'Concursos M1lhão (opcional)', hint: '009/2026'),
            field(
              milhaoCodes,
              'Códigos M1lhão (um por linha)',
              hint: 'ABC 12345',
              maxLines: 3,
            ),
            const Text(
              'O OCR tenta importar apenas chaves completas e válidas. Confirme sempre todas as chaves, estrelas e valores antes de guardar. Imagens não são enviadas ao servidor.',
            ),
          ],
        ),
      ),
    ),
  );
  Widget field(
    TextEditingController c,
    String label, {
    String? hint,
    int? maxLines = 1,
    int? minLines,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(
      controller: c,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}

/// Página informativa. Os ficheiros de identidade visual originais
/// serão incluídos como assets apenas após confirmação dos binários.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: brandedPageTitle('Sobre o LuckyScan50')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Semantics(
                label: 'Identidade LuckyScan50',
                child: Container(
                  height: 200,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xff172841),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/branding/luckyscan50-logo.webp',
                        width: 68,
                        height: 68,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'LUCKYSCAN50',
                        style: TextStyle(
                          fontSize: 25,
                          letterSpacing: 2.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xffe7c77f),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'As suas apostas, organizadas.',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'O LuckyScan50 permite guardar recibos e apostas do '
                'Euromilhões e M1lhão no dispositivo, consultar resultados '
                'disponíveis e acompanhar os valores apostados e recebidos.',
              ),
              const SizedBox(height: 16),
              const Text(
                'As fotografias e apostas são guardadas localmente. '
                'O reconhecimento de texto exige confirmação antes '
                'de guardar os dados.',
              ),
              const SizedBox(height: 24),
              Text('Projeto independente', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Aplicação não oficial, sem ligação ou associação aos '
                'Jogos Santa Casa. A verificação e atribuição oficial '
                'de prémios competem exclusivamente ao operador autorizado.',
              ),
              const SizedBox(height: 24),
              const Text('Gil Pereira · LuckyScan50'),
              const SizedBox(height: 8),
              Text(
                'Versão de auditoria $appVersion · $buildSha',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceiptPage extends ConsumerWidget {
  const ReceiptPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(receiptsProvider).valueOrNull ?? [];
    final matching = tickets.where((r) => r.id == id);
    if (matching.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Empty('Recibo não encontrado.'),
      );
    }
    final r = matching.first;
    final verification = verify(
      r,
      ref.watch(resultsProvider).valueOrNull ?? [],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe do recibo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            r.code.isEmpty ? 'Recibo local' : r.code,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          Text('${receiptStatus(r, verification)} · ${r.source}'),
          const SizedBox(height: 16),
          metric('Valor pago', r.costCents),
          metric('Prémios identificados', verification.knownCents),
          metric('Recebido', r.receivedCents),
          if (!verification.complete)
            Text(
              '${verification.pendingDraws} concursos pendentes · ${verification.unknownPrizes} prémios por confirmar',
            ),
          const Text('Euromilhões'),
          Text(r.drawIds.join(', ')),
          ...r.lines.map(
            (l) => Card(
              child: ListTile(
                title: Text(l.numbers.join('  ')),
                subtitle: Text('★ ${l.stars.join('  ')}'),
              ),
            ),
          ),
          if (r.milhaoCodes.isNotEmpty)
            Text(
              'M1lhão ${r.milhaoDrawIds.join(', ')}\n${r.milhaoCodes.join('\n')}',
            ),
          if (r.imagePath != null && File(r.imagePath!).existsSync())
            Image.file(File(r.imagePath!), height: 300),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              final controller = TextEditingController(
                text: (r.receivedCents / 100).toStringAsFixed(2),
              );
              final value = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Total efetivamente recebido'),
                  content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Euros'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              );
              if (value == null) return;
              try {
                await ref
                    .read(storeProvider)
                    .save(
                      Receipt.fromJson({
                        ...r.toJson(),
                        'receivedCents': cents(value),
                      }),
                    );
                ref.invalidate(receiptsProvider);
              } catch (_) {
                if (context.mounted) message(context, 'Valor inválido.');
              }
            },
            child: const Text('Registar recebimento'),
          ),
          TextButton(
            onPressed: () async {
              if (!await confirm(
                context,
                'Eliminar este recibo e a respetiva imagem?',
              )) {
                return;
              }
              await ref.read(storeProvider).delete(r.id);
              if (r.imagePath != null) {
                final file = File(r.imagePath!);
                if (await file.exists()) await file.delete();
              }
              ref.invalidate(receiptsProvider);
              if (context.mounted) context.pop();
            },
            child: const Text('Eliminar recibo'),
          ),
        ],
      ),
    );
  }
}
