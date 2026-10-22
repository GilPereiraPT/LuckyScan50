import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'milhao_draw_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'domain/wallet.dart';
import 'main.dart'
    show
        storeProvider,
        recordAppEvent,
        receiptsProvider,
        resultsProvider,
        brandedPageTitle,
        euro;

/// A selected multiple is stored as its distinct five-number/two-star
/// combinations, so the existing verification and wallet remain compatible.
class ManualSelection {
  ManualSelection({this.multiple = false});
  bool multiple;
  final Set<int> numbers = {};
  final Set<int> stars = {};
  int get combinations => choose(numbers.length, 5) * choose(stars.length, 2);
  bool get valid =>
      numbers.every((n) => n >= 1 && n <= 50) &&
      stars.every((n) => n >= 1 && n <= 12) &&
      (multiple
          ? numbers.length >= 5 &&
                numbers.length <= 10 &&
                stars.length >= 2 &&
                stars.length <= 12
          : numbers.length == 5 && stars.length == 2);
}

int choose(int n, int k) {
  if (n < k) {
    return 0;
  }
  var result = 1;
  for (var i = 1; i <= k; i++) {
    result = result * (n - k + i) ~/ i;
  }
  return result;
}

Iterable<List<int>> combinations(List<int> items, int count) sync* {
  if (count == 0) {
    yield <int>[];
    return;
  }
  for (var i = 0; i <= items.length - count; i++) {
    for (final rest in combinations(items.sublist(i + 1), count - 1)) {
      yield [items[i], ...rest];
    }
  }
}

List<BetLine> expandManualSelections(List<ManualSelection> selections) {
  if (selections.isEmpty || selections.any((selection) => !selection.valid)) {
    throw const FormatException(
      'Complete os números e estrelas de todas as apostas.',
    );
  }
  final count = selections.fold(
    0,
    (total, selection) => total + selection.combinations,
  );
  if (count > 500) {
    throw const FormatException(
      'Máximo de 500 combinações simples por registo. Divida a aposta.',
    );
  }
  final result = <BetLine>[];
  for (final selection in selections) {
    final numbers = selection.numbers.toList()..sort();
    final stars = selection.stars.toList()..sort();
    for (final ns in combinations(numbers, 5)) {
      for (final ss in combinations(stars, 2)) {
        result.add(BetLine(ns, ss));
      }
    }
  }
  return result;
}

/// Calendar suggestions for the current and preceding year; cached dates override.
Map<String, String> manualDrawOptions(
  DateTime now,
  List<Map<String, dynamic>> results,
) {
  final options = <String, String>{};
  for (final year in [now.year - 1, now.year]) {
    var sequence = 0;
    for (
      var day = DateTime.utc(year);
      day.year == year;
      day = day.add(const Duration(days: 1))
    ) {
      if (day.weekday != DateTime.tuesday && day.weekday != DateTime.friday) {
        continue;
      }
      sequence++;
      options['${sequence.toString().padLeft(3, '0')}/$year'] = day
          .toIso8601String()
          .substring(0, 10);
    }
  }
  for (final result in results) {
    if (result['game'] == 'euromilhoes' &&
        result['drawId'] is String &&
        result['date'] is String) {
      options[result['drawId'] as String] = result['date'] as String;
    }
  }
  return options;
}

int manualCostCents(int combinations, {int drawCount = 1}) =>
    combinations * 250 * drawCount;

List<String> manualMilhaoSequence(String firstCode, int count) {
  final match = RegExp(
    r'^([A-Z]{3})\s*(\d{5})$',
  ).firstMatch(firstCode.trim().toUpperCase());
  if (match == null || count < 1 || count > 500) {
    throw const FormatException(
      'Indique o primeiro código (ABC 00001) e uma quantidade entre 1 e 500.',
    );
  }
  final first = int.parse(match[2]!);
  if (first + count - 1 > 99999) {
    throw const FormatException(
      'A sequência ultrapassa 99999. Confirme os códigos no comprovativo.',
    );
  }
  return List.generate(
    count,
    (i) => '${match[1]} ${(first + i).toString().padLeft(5, '0')}',
  );
}

class ManualBetPage extends ConsumerStatefulWidget {
  const ManualBetPage({super.key});
  @override
  ConsumerState<ManualBetPage> createState() => _ManualBetPageState();
}

class _ManualBetPageState extends ConsumerState<ManualBetPage> {
  final selections = <ManualSelection>[ManualSelection()];
  final milhaoDraw = TextEditingController();
  final paidAmount = TextEditingController();
  bool includeMilhao = false;
  final selectedDraws = <String>{};
  final milhaoFirst = TextEditingController();
  final milhaoCount = TextEditingController(text: '1');
  final milhaoCodes = TextEditingController();

  @override
  void dispose() {
    milhaoDraw.dispose();
    paidAmount.dispose();
    milhaoFirst.dispose();
    milhaoCount.dispose();
    milhaoCodes.dispose();
    super.dispose();
  }

  void generateMilhao() {
    try {
      final codes = manualMilhaoSequence(
        milhaoFirst.text,
        int.tryParse(milhaoCount.text) ?? 0,
      );
      setState(() => milhaoCodes.text = codes.join('\n'));
    } on FormatException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String? selectedDraw;
  int active = 0;
  bool saving = false;

  int get total => selections.fold(0, (sum, s) => sum + s.combinations);
  bool get ready =>
      selections.every((s) => s.valid) && total > 0 && total <= 500;
  ManualSelection get selection => selections[active];

  void setCount(int count) => setState(() {
    if (count > selections.length) {
      selections.addAll(
        List.generate(count - selections.length, (_) => ManualSelection()),
      );
    } else {
      selections.removeRange(count, selections.length);
    }
    active = math.min(active, selections.length - 1);
  });

  void toggle(int value, bool star) {
    final set = star ? selection.stars : selection.numbers;
    final limit = star
        ? (selection.multiple ? 12 : 2)
        : (selection.multiple ? 10 : 5);
    setState(() {
      if (!set.remove(value) && set.length < limit) {
        set.add(value);
      }
    });
  }

  Future<void> save() async {
    if (saving) {
      return;
    }
    // Guard the confirmation as well as persistence: repeated callbacks must
    // never open two confirmations and create two receipts for one submission.
    setState(() => saving = true);
    try {
      final lines = expandManualSelections(selections);
      final options = manualDrawOptions(
        DateTime.now(),
        ref.read(resultsProvider).valueOrNull ?? [],
      );
      final drawIds = selectedDraws.toList()
        ..sort((a, b) => options[a]!.compareTo(options[b]!));
      if (drawIds.isEmpty || drawIds.any((id) => !options.containsKey(id))) {
        throw const FormatException('Selecione pelo menos um concurso.');
      }
      final codes = (includeMilhao ? milhaoCodes.text : '')
          .split(RegExp(r'[\n,;]+'))
          .map((c) => c.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ''))
          .where((c) => c.isNotEmpty)
          .toList();
      final milhaoIds = includeMilhao
          ? milhaoDraw.text
                .split(RegExp(r'[,;\s]+'))
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList()
          : <String>[];
      if (includeMilhao && codes.isEmpty) {
        throw const FormatException(
          'Gere a sequência M1lhão e reveja os códigos antes de guardar.',
        );
      }
      if (includeMilhao &&
          (milhaoIds.isEmpty ||
              milhaoIds.any((id) => !RegExp(r'^\d{3}/\d{4}$').hasMatch(id)) ||
              codes.any((c) => !RegExp(r'^[A-Z]{3}\d{5}$').hasMatch(c)) ||
              codes.toSet().length != codes.length)) {
        throw const FormatException(
          'Confirme o concurso M1lhão (000/2026) e os códigos, sem duplicados.',
        );
      }
      final price = paidAmount.text.trim().isEmpty
          ? manualCostCents(lines.length, drawCount: drawIds.length)
          : cents(paidAmount.text);
      final drawDate = options[drawIds.first]!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar registo'),
          content: Text(
            '${selections.length} aposta(s), ${lines.length} combinação(ões) simples.\n'
            'Concursos: ${drawIds.join(', ')}\nValor pago: ${euro(price)}\n'
            'M1lhão: ${codes.isEmpty ? 'sem códigos registados' : '${milhaoIds.join(', ')} · ${codes.length} códigos'}\n\n'
            'Reveja as seleções antes de guardar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Rever'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
      final now = DateTime.now();
      final receipt = Receipt(
        id: now.microsecondsSinceEpoch.toRadixString(36),
        createdAt: now.toUtc().toIso8601String(),
        source: 'manual',
        code: '',
        costCents: price,
        drawDate: drawDate,
        lines: lines,
        drawIds: drawIds,
        milhaoDrawIds: milhaoIds,
        milhaoCodes: codes,
      );
      await ref.read(storeProvider).save(receipt);
      recordAppEvent(ref, 'receipt_saved_manual');
      ref.invalidate(receiptsProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível guardar as apostas.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget numbersGrid({required bool star}) {
    final max = star ? 12 : 50;
    final set = star ? selection.stars : selection.numbers;
    return LayoutBuilder(
      builder: (context, box) {
        // Preserve the Android 48dp touch target on small displays instead of
        // forcing six stars or ten numbers into a narrower card.
        final columns = math.min(
          star ? 6 : 10,
          math.max(1, ((box.maxWidth + 7) / 55).floor()),
        );
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: max,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final value = index + 1;
            final selected = set.contains(value);
            return Semantics(
              button: true,
              selected: selected,
              label: '${star ? 'Estrela' : 'Número'} $value',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: saving ? null : () => toggle(value, star),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? (star
                              ? const Color(0xffd59f37)
                              : const Color(0xff19785f))
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? Colors.transparent
                          : Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Text(
                    value.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = manualDrawOptions(
      DateTime.now(),
      ref.watch(resultsProvider).valueOrNull ?? [],
    );
    final entries = options.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    selectedDraw ??= entries
        .firstWhere(
          (e) =>
              e.value.compareTo(
                DateTime.now().toIso8601String().substring(0, 10),
              ) >=
              0,
          orElse: () => entries.last,
        )
        .key;
    if (selectedDraws.isEmpty && selectedDraw != null) {
      selectedDraws.add(selectedDraw!);
    }
    final s = selection;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: brandedPageTitle('Introdução manual')),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: ready && !saving ? save : null,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(
            ready
                ? 'Confirmar e guardar · $total combinações'
                : 'Complete as apostas para guardar',
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'As suas chaves, à sua maneira',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text('Escolha os números e o concurso.'),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quantidade de apostas',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filledTonal(
                                onPressed: selections.length > 1 && !saving
                                    ? () => setCount(selections.length - 1)
                                    : null,
                                icon: const Icon(Icons.remove),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Text(
                                  '${selections.length}',
                                  style: theme.textTheme.headlineMedium,
                                ),
                              ),
                              IconButton.filledTonal(
                                onPressed: selections.length < 20 && !saving
                                    ? () => setCount(selections.length + 1)
                                    : null,
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                          Text(
                            '$total combinações',
                            style: theme.textTheme.labelLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(
                            selections.length,
                            (i) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  '${i + 1} ${selections[i].valid ? '✓' : '·'}',
                                ),
                                selected: i == active,
                                onSelected: saving
                                    ? null
                                    : (_) => setState(() => active = i),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, box) => Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Aposta ${active + 1}',
                              style: theme.textTheme.titleLarge,
                            ),
                            SegmentedButton<bool>(
                              direction:
                                  box.maxWidth <
                                      300 *
                                          MediaQuery.textScalerOf(
                                            context,
                                          ).scale(1)
                                  ? Axis.vertical
                                  : Axis.horizontal,
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  label: Text('Simples'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('Múltipla'),
                                ),
                              ],
                              selected: {s.multiple},
                              onSelectionChanged: saving
                                  ? null
                                  : (values) => setState(() {
                                      s.multiple = values.first;
                                      if (!s.multiple) {
                                        s.numbers.removeAll(
                                          (s.numbers.toList()..sort()).skip(5),
                                        );
                                        s.stars.removeAll(
                                          (s.stars.toList()..sort()).skip(2),
                                        );
                                      }
                                    }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Números · ${s.numbers.length}/${s.multiple ? '5–10' : '5'}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      numbersGrid(star: false),
                      const SizedBox(height: 18),
                      Text(
                        'Estrelas · ${s.stars.length}/${s.multiple ? '2–12' : '2'}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      numbersGrid(star: true),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.valid
                                  ? '${s.combinations} combinação(ões) simples'
                                  : 'Escolha ${s.multiple ? '5 a 10 números e 2 a 12 estrelas' : '5 números e 2 estrelas'}',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: saving
                                ? null
                                : () => setState(() {
                                    s.numbers.clear();
                                    s.stars.clear();
                                  }),
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Limpar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Registar M1lhão (opcional)'),
                        value: includeMilhao,
                        onChanged: saving
                            ? null
                            : (value) => setState(() => includeMilhao = value),
                      ),
                      if (includeMilhao) ...[
                        const Text(
                          'Introduza as letras uma vez e o primeiro número. A sequência mantém as letras e os zeros iniciais.',
                        ),
                        const SizedBox(height: 12),
                        MilhaoDrawPicker(
                          controller: milhaoDraw,
                          enabled: !saving,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: milhaoFirst,
                          enabled: !saving,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Primeiro código',
                            hintText: 'ABC 00001',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: milhaoCount,
                          enabled: !saving,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Quantidade de códigos no comprovativo',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: saving ? null : generateMilhao,
                          icon: const Icon(Icons.format_list_numbered),
                          label: const Text('Gerar sequência'),
                        ),
                        TextField(
                          controller: milhaoCodes,
                          enabled: !saving,
                          minLines: 2,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Códigos M1lhão — rever ou editar',
                            hintText: 'Um código por linha',
                          ),
                        ),
                        const Text(
                          'Estes códigos serão verificados em todos os concursos M1lhão indicados. '
                          'Confirme no comprovativo; se os códigos forem diferentes, crie registos separados.',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedDraw,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Adicionar concurso Euromilhões',
                        ),
                        items: entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text('${e.key} · ${e.value}'),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (value) => setState(() {
                                selectedDraw = value;
                                if (value != null) selectedDraws.add(value);
                              }),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: selectedDraws
                            .map(
                              (id) => InputChip(
                                label: Text('$id · ${options[id]}'),
                                onDeleted: saving || selectedDraws.length == 1
                                    ? null
                                    : () => setState(
                                        () => selectedDraws.remove(id),
                                      ),
                              ),
                            )
                            .toList(),
                      ),
                      const Text(
                        'As mesmas chaves aplicam-se a todos os concursos selecionados.',
                      ),
                      ListTile(
                        leading: const Icon(Icons.calendar_month),
                        title: const Text('Concursos selecionados'),
                        subtitle: Text('${selectedDraws.length} concurso(s)'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.euro),
                        title: const Text('Valor pago calculado'),
                        subtitle: Text(
                          '${euro(manualCostCents(total, drawCount: selectedDraws.length))} · $total combinações × ${selectedDraws.length} concursos × 2,50 €',
                        ),
                      ),
                      TextField(
                        controller: paidAmount,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        enabled: !saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Total pago no comprovativo (€)',
                          helperText: 'Opcional: substitui o total calculado.',
                        ),
                      ),
                      const Text(
                        'Registe o total do recibo uma única vez. O registo dos códigos '
                        'M1lhão é opcional e não altera o valor pago. As datas dos '
                        'resultados guardados têm prioridade. Máximo: 500 combinações.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
