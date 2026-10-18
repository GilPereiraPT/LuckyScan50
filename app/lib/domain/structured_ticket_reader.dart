/// Independent, deterministic Euromilhões receipt structure reader.
/// Format and validate this module through the automated GitHub workflow.
///
/// This module does not parse full-frame text or depend on legacy OCR passes.
/// It receives OCR tokens with image coordinates and returns only unambiguous
/// values. Image rectification and token recognition belong to the caller.
class TicketGlyph {
  const TicketGlyph(this.text, this.x, this.y, this.height, this.width);
  final String text;
  final double x;
  final double y;
  final double height;
  final double width;
}

class TicketRow {
  const TicketRow(this.index, this.numbers, this.stars, this.issues);
  final int index;
  final List<int> numbers;
  final List<int> stars;
  final List<String> issues;
  bool get complete => issues.isEmpty;
}

class StructuredTicket {
  const StructuredTicket(this.rows, this.issues);
  final List<TicketRow> rows;
  final List<String> issues;
  bool get complete => rows.isNotEmpty &&
      issues.isEmpty &&
      rows.every((row) => row.complete);
}

StructuredTicket readStructuredTicket(List<TicketGlyph> glyphs) {
  final valid = glyphs.where((g) =>
      g.x.isFinite && g.y.isFinite &&
      g.height.isFinite && g.height > 0 &&
      g.width.isFinite && g.width >= 0).toList();
  final anchors = <({TicketGlyph glyph, int index})>[];
  final label = RegExp(r'^(\d{1,2})\s*[.)]?\s*N$', caseSensitive: false);
  for (final glyph in valid) {
    final match = label.firstMatch(glyph.text.trim());
    if (match == null) continue;
    final index = int.parse(match[1]!);
    if (index >= 1 && index <= 20) {
      anchors.add((glyph: glyph, index: index));
    }
  }
  anchors.sort((a, b) => a.glyph.y.compareTo(b.glyph.y));
  if (anchors.isEmpty) {
    return const StructuredTicket([], ['Sem âncoras de aposta inequívocas']);
  }
  final result = <TicketRow>[];
  for (var i = 0; i < anchors.length; i++) {
    final anchor = anchors[i];
    final nextY = i + 1 < anchors.length
        ? anchors[i + 1].glyph.y
        : double.infinity;
    final eCandidates = valid.where((g) =>
        g.text.trim().toUpperCase() == 'E' &&
        g.y > anchor.glyph.y + anchor.glyph.height * 0.3 &&
        g.y < nextY &&
        (g.x - anchor.glyph.x).abs() <= anchor.glyph.height * 2).toList();
    eCandidates.sort((a, b) => a.y.compareTo(b.y));
    final e = eCandidates.length == 1 ? eCandidates.single : null;
    List<int> cells(TicketGlyph row) {
      final candidates = valid.where((g) =>
          g.x - g.width / 2 > row.x + row.width / 2 &&
          (g.y - row.y).abs() <= row.height * 0.45 &&
          RegExp(r'^\d{1,2}$').hasMatch(g.text.trim())).toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      return candidates.map((g) => int.parse(g.text.trim())).toList();
    }
    final numbers = cells(anchor.glyph);
    final stars = e == null ? <int>[] : cells(e);
    final issues = <String>[];
    if (eCandidates.length != 1) {
      issues.add('Âncora E ausente ou ambígua');
    }
    if (numbers.length != 5 ||
        numbers.toSet().length != 5 ||
        numbers.any((n) => n < 1 || n > 50)) {
      issues.add('Números por confirmar');
    }
    if (stars.length != 2 ||
        stars.toSet().length != 2 ||
        stars.any((n) => n < 1 || n > 12)) {
      issues.add('Estrelas por confirmar');
    }
    result.add(TicketRow(anchor.index, numbers, stars, issues));
  }
  final issues = <String>[];
  final indices = result.map((r) => r.index).toList();
  if (indices.toSet().length != indices.length) {
    issues.add('Índices de aposta duplicados');
  }
  for (var i = 1; i < indices.length; i++) {
    if (indices[i] <= indices[i - 1]) {
      issues.add('Ordem das apostas ambígua');
      break;
    }
  }
  return StructuredTicket(result, issues);
}
