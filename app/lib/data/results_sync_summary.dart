import 'dart:convert';

import '../domain/wallet.dart';

/// Distinguishes an HTTP sync from actually receiving new draw results.
/// The comparison ignores source metadata that does not change verification.
class ResultsSyncSummary {
  const ResultsSyncSummary({
    required this.changedDraws,
    required this.pendingDraws,
    required this.unconfirmedPrizes,
  });

  final int changedDraws;
  final List<String> pendingDraws;
  final int unconfirmedPrizes;

  String get message {
    if (pendingDraws.isNotEmpty) {
      final example = pendingDraws.take(3).join(', ');
      final suffix = pendingDraws.length > 3 ? ', …' : '';
      final imported = changedDraws > 0
          ? '$changedDraws resultado(s) novo(s) ou corrigido(s). '
          : '';
      return imported +
          'Consulta concluída, mas faltam resultados para '
              '${pendingDraws.length} concurso(s) dos seus bilhetes: '
              '$example$suffix.';
    }
    if (unconfirmedPrizes > 0) {
      return 'Consulta concluída, mas há '
          '$unconfirmedPrizes prémio(s) com valor por confirmar.';
    }
    if (changedDraws > 0) {
      return 'Resultados atualizados: '
          '$changedDraws concurso(s) novo(s) ou corrigido(s).';
    }
    return 'Consulta concluída. Não foram encontrados resultados novos.';
  }
}

String _key(Map<String, dynamic> draw) => "${draw['game']}/${draw['drawId']}";

String _verificationContent(Map<String, dynamic> draw) => jsonEncode([
  draw['status'],
  draw['numbers'],
  draw['stars'],
  draw['tiers'],
  draw['winningCode'],
  draw['amountCents'],
]);

ResultsSyncSummary summarizeResultsSync({
  required List<Map<String, dynamic>> previous,
  required List<Map<String, dynamic>> current,
  required List<Receipt> receipts,
}) {
  final previousByKey = {for (final draw in previous) _key(draw): draw};
  final currentByKey = {for (final draw in current) _key(draw): draw};
  var changed = 0;
  for (final entry in currentByKey.entries) {
    final old = previousByKey[entry.key];
    if (old == null ||
        _verificationContent(old) != _verificationContent(entry.value)) {
      changed++;
    }
  }

  final pending = <String>{};
  var unconfirmed = 0;
  for (final receipt in receipts) {
    for (final id in receipt.drawIds) {
      final draw = currentByKey['euromilhoes/$id'];
      if (draw == null ||
          !['complete', 'numbers_confirmed'].contains(draw['status'])) {
        pending.add('Euromilhões $id');
      }
    }
    for (final id in receipt.milhaoDrawIds) {
      final draw = currentByKey['milhao/$id'];
      if (draw == null || draw['status'] != 'complete') {
        pending.add('M1lhão $id');
      }
    }
    unconfirmed += verify(receipt, current).unknownPrizes;
  }

  return ResultsSyncSummary(
    changedDraws: changed,
    pendingDraws: pending.toList()..sort(),
    unconfirmedPrizes: unconfirmed,
  );
}
