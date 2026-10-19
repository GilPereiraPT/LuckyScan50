import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'domain/wallet.dart';

class ReceiptDrawResult extends StatelessWidget {
  const ReceiptDrawResult({
    super.key,
    required this.receipt,
    required this.drawId,
    required this.results,
  });
  final Receipt receipt;
  final String drawId;
  final List<Map<String, dynamic>> results;

  @override
  Widget build(BuildContext context) {
    final matches = results.where(
      (row) => row['game'] == 'euromilhoes' && row['drawId'] == drawId,
    );
    final draw = matches.isEmpty ? null : matches.first;
    if (draw == null || draw['status'] != 'complete') {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: Text('Concurso $drawId · Resultado indisponível'),
          subtitle: const Text(
            'Ainda não é possível concluir se tem prémio. '
            'Atualize os resultados no ecrã principal. '
            'A lista de concursos não garante que exista resultado guardado.',
          ),
        ),
      );
    }
    final check = verify(
      Receipt.fromJson({
        ...receipt.toJson(),
        'drawIds': [drawId],
        'milhaoDrawIds': <String>[],
        'milhaoCodes': <String>[],
      }),
      [draw],
    );
    final amount = NumberFormat.currency(
      locale: 'pt_PT',
      symbol: '€',
    ).format(check.knownCents / 100);
    return Card(
      child: ListTile(
        leading: Icon(
          check.winningLines > 0 ? Icons.emoji_events : Icons.check_circle,
        ),
        title: Text('Concurso $drawId · ${check.label}'),
        subtitle: Text(
          'Chave sorteada: ${(draw['numbers'] as List).join(' ')} '
          '· ★ ${(draw['stars'] as List).join(' ')}\n'
          '${check.winningLines} apostas premiadas · $amount\n'
          'Fonte: Jogos Santa Casa · ${draw['date']}',
        ),
      ),
    );
  }
}
