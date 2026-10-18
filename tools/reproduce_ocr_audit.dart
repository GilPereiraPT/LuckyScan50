import '../app/lib/domain/receipt_parser.dart';
import '../app/lib/domain/receipt_geometry.dart';
import '../app/lib/domain/receipt_cell_consensus.dart';
import '../app/lib/domain/receipt_evidence.dart';

void main() {
  final first = parseReceiptObservations(
    text: '5 AP SIMPLES\n1.N 06 20 29 32 48\nE 04 06',
  );
  final bounded = withBetLayout(first, 1);
  print(
    'COUNT before=${first.expectedLines}/${first.bets.length} after=${bounded.expectedLines}/${bounded.bets.length} forms=${bounded.formLines}',
  );
  final unnamed = parseReceiptObservations(text: 'N 06 20 29 32 48\nE 04 06');
  print(
    'UNINDEXED complete=${unnamed.bets.first.complete} issues=${unnamed.bets.first.issues}',
  );
  final standalone = parseReceiptObservations(
    text: '1.N 06 20 29 32 48\nE\n04 06',
  );
  print(
    'E_ISOLATED stars=${standalone.bets.first.stars} complete=${standalone.bets.first.complete}',
  );
  const box = CropBox(0, 0, 40, 40);
  final consensus = consolidateCellEvidence(
    [const BetCrop(1, box, kind: 'N', position: 0)],
    [
      for (final pass in ['cell@1x', 'cell@2x-contrast'])
        ValueEvidence(
          'N',
          0,
          6,
          'O6',
          pass,
          betIndex: 1,
          bounds: box,
          correction: 'O6→06',
          requiresConfirmation: true,
        ),
    ],
  );
  print('CORRELATED corrected accepted=${consensus.bets.first.numbers}');
  final upside = [
    const ReceiptToken('1.N', 20, 100, 20, width: 25, angle: 180),
  ];
  print(
    'UPSIDE rows=${uprightBetRowCount(upside, 300, 300)} vertical=${upside.any(verticalReceiptToken)} turns=${preferredReceiptTurns(upside)}',
  );
}
