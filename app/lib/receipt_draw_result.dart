import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'domain/wallet.dart';
import 'ticket_numbers.dart';

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
    if (draw == null ||
        !['complete', 'numbers_confirmed'].contains(draw['status'])) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: Text('Concurso $drawId · Resultado indisponível'),
          subtitle: const Text('A atualizar resultado.'),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            TicketNumbers(
              numbers: List<int>.from(draw['numbers'] as List),
              stars: List<int>.from(draw['stars'] as List),
            ),
            const SizedBox(height: 10),
            Text(
              check.winningLines == 0
                  ? 'Sem apostas premiadas'
                  : '${check.winningLines} apostas premiadas · ${check.unknownPrizes > 0 ? 'Valor por publicar' : amount}',
            ),
            Text('Jogos Santa Casa · ${draw['date']}'),
          ],
        ),
      ),
    );
  }
}
