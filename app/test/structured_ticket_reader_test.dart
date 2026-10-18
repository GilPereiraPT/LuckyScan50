import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/structured_ticket_reader.dart';

void main() {
  test('five standard bets are read by anchored cells, not footer text', () {
    const numbers = [
      [6, 20, 29, 32, 48],
      [5, 17, 36, 47, 49],
      [22, 26, 43, 45, 47],
      [6, 10, 13, 35, 44],
      [2, 6, 13, 20, 32],
    ];
    const stars = [
      [4, 6],
      [5, 11],
      [3, 9],
      [2, 10],
      [3, 10],
    ];
    final tokens = <TicketGlyph>[
      const TicketGlyph('081', 500, 40, 20, 30),
      const TicketGlyph('782', 200, 900, 20, 30),
    ];
    for (var i = 0; i < 5; i++) {
      final y = 100.0 + i * 90;
      tokens.add(TicketGlyph('${i + 1}.N', 100, y, 30, 40));
      tokens.add(TicketGlyph('E', 100, y + 38, 30, 20));
      for (var j = 0; j < 5; j++) {
        tokens.add(TicketGlyph('${numbers[i][j]}', 170.0 + 60 * j, y, 30, 28));
      }
      for (var j = 0; j < 2; j++) {
        tokens.add(
          TicketGlyph('${stars[i][j]}', 170.0 + 60 * j, y + 38, 30, 28),
        );
      }
    }
    final result = readStructuredTicket(tokens.reversed.toList());
    expect(result.complete, isTrue);
    expect(result.rows.length, 5);
    for (var i = 0; i < 5; i++) {
      expect(result.rows[i].index, i + 1);
      expect(result.rows[i].numbers, numbers[i]);
      expect(result.rows[i].stars, stars[i]);
    }
  });

  test('missing star stays pending, never borrows the following row', () {
    final tokens = [
      const TicketGlyph('1.N', 100, 100, 30, 40),
      for (var i = 0; i < 5; i++)
        TicketGlyph('${i + 1}', 170.0 + i * 60, 100, 30, 28),
      const TicketGlyph('2.N', 100, 200, 30, 40),
      const TicketGlyph('E', 100, 238, 30, 20),
      for (var i = 0; i < 5; i++)
        TicketGlyph('${i + 10}', 170.0 + i * 60, 200, 30, 28),
      const TicketGlyph('03', 170, 238, 30, 28),
      const TicketGlyph('10', 230, 238, 30, 28),
    ];
    final result = readStructuredTicket(tokens);
    expect(result.rows.first.stars, isEmpty);
    expect(result.rows.first.complete, isFalse);
    expect(result.rows.last.stars, [3, 10]);
    expect(result.rows.last.complete, isTrue);
  });
}
