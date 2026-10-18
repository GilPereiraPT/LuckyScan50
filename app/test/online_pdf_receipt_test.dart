import 'package:flutter_test/flutter_test.dart';
import 'package:luckyscan50/domain/online_pdf_receipt.dart';

void main() {
  test('online three-bet PDF with M1lhão is read without coordinates', () {
    // Sanitised, synthetic OCR text matching the observed ONLINE table format.
    const text = '''
APOSTAS EM JOGO
EUROMILHÕES
CODIGO APOSTA  DATA APOSTA  SORTEIO  DETALHE APOSTAS
000000000000 17/10/2026 Euromilhões 084/2026 20/10/2026
3 aposta(s)
7 16 37 45 46 + 1 9
16 20 22 26 28 + 7 12
2 8 16 28 35 + 4 9
Total Euromilhões: € 6,60
M1LHÃO
M1lhão 010/2026 30/10/2026
3 código(s)
QRL 34251
QRL 34252
QRL 34253
Total M1lhão: € 0,90
''';
    final scan = parseOnlinePdfReceipt(text, const []);
    expect(scan.bets.length, 3);
    expect(scan.fullyParsed, isTrue);
    expect(scan.lines, [
      '07 16 37 45 46 + 01 09',
      '16 20 22 26 28 + 07 12',
      '02 08 16 28 35 + 04 09',
    ]);
    expect(scan.amount, '7,50');
    expect(scan.expectedLines, 3);
    expect(scan.milhaoCodes, ['QRL 34251', 'QRL 34252', 'QRL 34253']);
    expect(scan.drawId, '084/2026');
    expect(scan.milhaoDrawId, '010/2026');
    expect(scan.drawDate, '2026-10-20');
    expect(looksLikeOnlinePdf(text), isTrue);
  });

  test('missing bet never becomes a guessed valid bet', () {
    const text = '''
Apostas em Jogo
Euromilhões
3 aposta(s)
7 16 37 45 46 + 1 9
2 8 16 28 35 + 4 9
Total Euromilhões: € 6,60
''';
    final scan = parseOnlinePdfReceipt(text, const []);
    expect(scan.bets.length, 3);
    expect(scan.bets.last.complete, isFalse);
    expect(scan.formLines.last, contains('?'));
    expect(scan.fullyParsed, isFalse);
  });

  test('invalid order or range is rejected rather than normalised', () {
    const text = '''
APOSTAS EM JOGO Euromilhões 2 aposta(s)
7 16 37 45 46 + 1 9
7 16 16 45 51 + 1 15
''';
    final scan = parseOnlinePdfReceipt(text, const []);
    expect(scan.lines.length, 1);
    expect(scan.bets.length, 2);
    expect(scan.fullyParsed, isFalse);
  });

  test('ordinary physical ticket is not wrongly recognised as online PDF', () {
    expect(looksLikeOnlinePdf('EUROMILHÕES 5 AP SIMPLES 1.N 06 20'), isFalse);
  });
}
