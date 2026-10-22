import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/milhao_draw_picker.dart';

void main() {
  test('Does not invent future contests when no dates were published', () {
    expect(milhaoDrawOptions([], []), isEmpty);
  });
  test(
    'Uses announced dates, rejects invalid dates and preserves corrections',
    () {
      final options = milhaoDrawOptions(
        [
          {'game': 'milhao', 'drawId': '009/2026', 'date': '2026-09-25'},
          {'game': 'euromilhoes', 'drawId': '083/2026', 'date': '2026-10-16'},
        ],
        [
          {
            'game': 'milhao',
            'validation': 'accepted',
            'upcoming': {'drawId': '010/2026', 'date': '2026-10-30'},
          },
          {
            'game': 'milhao',
            'validation': 'accepted',
            'upcoming': {'drawId': '009/2026', 'date': '2026-09-26'},
          },
          {
            'game': 'milhao',
            'validation': 'accepted',
            'upcoming': {'drawId': '011/2026', 'date': '2026-02-30'},
          },
          {
            'game': 'milhao',
            'validation': 'conflict',
            'upcoming': {'drawId': '012/2026', 'date': '2026-12-25'},
          },
        ],
      );
      expect(options, {'009/2026': '2026-09-25', '010/2026': '2026-10-30'});
    },
  );
}
