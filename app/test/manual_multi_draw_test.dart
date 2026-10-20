import 'package:flutter_test/flutter_test.dart';
import '../lib/manual_bets_page.dart';
import '../lib/domain/wallet.dart';

void main() {
  test('counts combinations for each selected draw', () {
    expect(manualCostCents(2, drawCount: 3), 1500);
    expect(manualCostCents(2), 500);
  });

  test('multiple draws survive persistence without optional M1lhao', () {
    final receipt = Receipt(
      id: 'manual-test',
      createdAt: '2026-10-20T10:00:00Z',
      source: 'manual',
      code: '',
      costCents: 500,
      lines: [BetLine([1, 2, 3, 4, 5], [1, 2])],
      drawIds: ['081/2026', '082/2026'],
    );
    final restored = Receipt.fromJson(receipt.toJson());
    expect(restored.drawIds, ['081/2026', '082/2026']);
    expect(restored.costCents, 500);
    expect(restored.milhaoCodes, isEmpty);
    expect(restored.milhaoDrawIds, isEmpty);
    expect(verify(restored, []).pendingDraws, 2);
  });
}
