class TicketLine {
  const TicketLine({required this.numbers, required this.stars});
  final List<int> numbers;
  final List<int> stars;
}

class ParsedTicket {
  const ParsedTicket({
    required this.sourceType,
    required this.lines,
    this.receiptCode,
    this.drawDate,
    this.confidence = 0,
  });
  final String sourceType; // physical | online | manual
  final String? receiptCode;
  final DateTime? drawDate;
  final List<TicketLine> lines;
  final double confidence;
}

abstract class TicketReader {
  Future<ParsedTicket> read(String imagePath);
}
