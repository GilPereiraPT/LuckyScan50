import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'domain/wallet.dart';
import 'main.dart' show storeProvider, receiptsProvider, brandedPageTitle, euro;

/// A selected multiple is stored as its distinct five-number/two-star
/// combinations, so the existing verification and wallet remain compatible.
class ManualSelection {
  ManualSelection({this.multiple = false});
  bool multiple;
  final Set<int> numbers = {};
  final Set<int> stars = {};
  int get combinations => choose(numbers.length, 5) * choose(stars.length, 2);
  bool get valid => multiple
      ? numbers.length >= 5 && numbers.length <= 10 &&
          stars.length >= 2 && stars.length <= 12
      : numbers.length == 5 && stars.length == 2;
}

int choose(int n, int k) {
  if (n < k) { return 0; }
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
  final result = <BetLine>[];
  for (final selection in selections) {
    if (!selection.valid) {
      throw const FormatException('Complete os números e estrelas de todas as apostas.');
    }
    final numbers = selection.numbers.toList()..sort();
    final stars = selection.stars.toList()..sort();
    for (final ns in combinations(numbers, 5)) {
      for (final ss in combinations(stars, 2)) {
        result.add(BetLine(ns, ss));
        if (result.length > 500) {
          throw const FormatException('Máximo de 500 combinações simples por registo. Divida a aposta.');
        }
      }
    }
  }
  return result;
}

class ManualBetPage extends ConsumerStatefulWidget {
  const ManualBetPage({super.key});
  @override
  ConsumerState<ManualBetPage> createState() => _ManualBetPageState();
}

class _ManualBetPageState extends ConsumerState<ManualBetPage> {
  final selections = <ManualSelection>[ManualSelection()];
  final draw = TextEditingController();
  final cost = TextEditingController();
  final date = TextEditingController();
  int active = 0;
  bool saving = false;

  @override
  void dispose() {
    draw.dispose();
    cost.dispose();
    date.dispose();
    super.dispose();
  }

  int get total => selections.fold(0, (sum, s) => sum + s.combinations);
  bool get ready => selections.every((s) => s.valid) && total > 0 && total <= 500;
  ManualSelection get selection => selections[active];

  void setCount(int count) => setState(() {
    if (count > selections.length) {
      selections.addAll(List.generate(count - selections.length, (_) => ManualSelection()));
    } else {
      selections.removeRange(count, selections.length);
    }
    active = math.min(active, selections.length - 1);
  });

  void toggle(int value, bool star) {
    final set = star ? selection.stars : selection.numbers;
    final limit = star ? (selection.multiple ? 12 : 2) : (selection.multiple ? 10 : 5);
    setState(() {
      if (!set.remove(value) && set.length < limit) { set.add(value); }
    });
  }

  Future<void> save() async {
    if (saving) { return; }
    try {
      final lines = expandManualSelections(selections);
      final drawId = draw.text.trim();
      if (!RegExp(r'^\d{3}/\d{4}$').hasMatch(drawId)) {
        throw const FormatException('Indique o concurso no formato 081/2026.');
      }
      final price = cents(cost.text);
      final drawDate = date.text.trim();
      if (drawDate.isNotEmpty) {
        final parsed = DateTime.tryParse(drawDate);
        if (parsed == null || parsed.toIso8601String().substring(0, 10) != drawDate) {
          throw const FormatException('Data inválida: utilize AAAA-MM-DD.');
        }
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar registo'),
          content: Text(
            '${selections.length} aposta(s), ${lines.length} combinação(ões) simples.\n'
            'Concurso: $drawId\nValor pago: ${euro(price)}\n\n'
            'Confirme as seleções com o comprovativo. Esta app não faz apostas oficiais.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rever')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      );
      if (confirmed != true || !mounted) { return; }
      setState(() => saving = true);
      final now = DateTime.now();
      final receipt = Receipt(
        id: now.microsecondsSinceEpoch.toRadixString(36),
        createdAt: now.toUtc().toIso8601String(),
        source: 'manual',
        code: '',
        costCents: price,
        drawDate: drawDate.isEmpty ? null : drawDate,
        lines: lines,
        drawIds: [drawId],
      );
      await ref.read(storeProvider).save(receipt);
      ref.invalidate(receiptsProvider);
      if (mounted) { Navigator.of(context).pop(); }
    } on FormatException catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); }
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível guardar as apostas.')),
      ); }
    } finally {
      if (mounted) { setState(() => saving = false); }
    }
  }

  Widget numbersGrid({required bool star}) {
    final max = star ? 12 : 50;
    final set = star ? selection.stars : selection.numbers;
    return LayoutBuilder(builder: (context, box) {
      final columns = star ? 6 : (box.maxWidth < 370 ? 5 : 10);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: max,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns, mainAxisSpacing: 7, crossAxisSpacing: 7,
          childAspectRatio: 1.05,
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
                  color: selected ? (star ? const Color(0xffd59f37) : const Color(0xff19785f))
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? Colors.transparent : Theme.of(context).dividerColor,
                  ),
                ),
                child: Text(value.toString().padLeft(2, '0'), style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                )),
              ),
            ),
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = selection;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: brandedPageTitle('Introdução manual')),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: ready && !saving ? save : null,
          icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(ready ? 'Confirmar e guardar · $total combinações' : 'Complete as apostas para guardar'),
        ),
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('As suas chaves, à sua maneira', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Sem fotografia e sem OCR. Escolha os números, confirme o concurso e guarde na carteira.'),
            const SizedBox(height: 18),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Quantidade de apostas', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(children: [
                  IconButton.filledTonal(onPressed: selections.length > 1 && !saving ? () => setCount(selections.length - 1) : null,
                      icon: const Icon(Icons.remove)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('${selections.length}',
                      style: theme.textTheme.headlineMedium)),
                  IconButton.filledTonal(onPressed: selections.length < 20 && !saving ? () => setCount(selections.length + 1) : null,
                      icon: const Icon(Icons.add)),
                  const Spacer(),
                  Text('$total combinações', style: theme.textTheme.labelLarge),
                ]),
                const SizedBox(height: 12),
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(
                  children: List.generate(selections.length, (i) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${i+1} ${selections[i].valid ? '✓' : '·'}'),
                      selected: i == active,
                      onSelected: (_) => setState(() => active = i),
                    ),
                  )),
                )),
              ]),
            )),
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Aposta ${active + 1}', style: theme.textTheme.titleLarge)),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Simples')),
                      ButtonSegment(value: true, label: Text('Múltipla')),
                    ],
                    selected: {s.multiple},
                    onSelectionChanged: (values) => setState(() {
                      s.multiple = values.first;
                      if (!s.multiple) {
                        s.numbers.removeAll((s.numbers.toList()..sort()).skip(5));
                        s.stars.removeAll((s.stars.toList()..sort()).skip(2));
                      }
                    }),
                  ),
                ]),
                const SizedBox(height: 12),
                Text('Números · ${s.numbers.length}/${s.multiple ? '5–10' : '5'}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                numbersGrid(star: false),
                const SizedBox(height: 18),
                Text('Estrelas · ${s.stars.length}/${s.multiple ? '2–12' : '2'}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                numbersGrid(star: true),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text(s.valid
                      ? '${s.combinations} combinação(ões) simples'
                      : 'Escolha ${s.multiple ? '5 a 10 números e 2 a 12 estrelas' : '5 números e 2 estrelas'}')),
                  TextButton.icon(onPressed: () => setState(() {s.numbers.clear(); s.stars.clear();}),
                    icon: const Icon(Icons.restart_alt), label: const Text('Limpar')),
                ]),
              ],
            ))),
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              TextField(controller: draw, decoration: const InputDecoration(
                labelText: 'Concurso Euromilhões', hintText: '081/2026',
                prefixIcon: Icon(Icons.event_available),
              )),
              const SizedBox(height: 12),
              TextField(controller: date, decoration: const InputDecoration(
                labelText: 'Data do sorteio (opcional)', hintText: '2026-10-09',
                prefixIcon: Icon(Icons.calendar_month),
              )),
              const SizedBox(height: 12),
              TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Valor total pago (€)', hintText: '11,00',
                  prefixIcon: Icon(Icons.euro),
                )),
              const SizedBox(height: 8),
              const Text('Introduza o valor real do comprovativo. As múltiplas são guardadas como combinações simples para verificação de resultados. Máximo: 500 combinações.'),
            ]))),
          ],
        ),
      )),
    );
  }
}
