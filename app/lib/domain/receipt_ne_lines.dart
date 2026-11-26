/// Leitura conservadora das linhas N/E dos talões físicos do Euromilhões.
///
/// Recebe texto *já localizado* à direita de uma âncora N ou E. Nunca procura
/// algarismos em cabeçalhos, identificadores, datas ou no talão integral.
/// O comprimento é uma condição necessária, não uma prova de correção OCR.
class NeLineDigits {
  const NeLineDigits._();

  static List<int>? parse(String source, {required bool stars}) {
    // Apenas dígitos e espaços: nunca eliminar letras desconhecidas (p.ex. 儿4).
    if (!RegExp(r'^[0-9\s]+$').hasMatch(source)) return null;
    final digits = source.replaceAll(RegExp(r'\s+'), '');
    if (digits.length != (stars ? 4 : 10)) return null;
    final values = <int>[
      for (var i = 0; i < digits.length; i += 2)
        int.parse(digits.substring(i, i + 2)),
    ];
    if (values.any((n) => n < 1 || n > (stars ? 12 : 50))) return null;
    if (values.toSet().length != values.length) return null;
    if (!stars) {
      for (var i = 1; i < values.length; i++) {
        if (values[i] <= values[i - 1]) return null;
      }
    }
    return values;
  }

  // Only for crops anchored to N/E, never metadata or ticket codes.
  static const lookAlikes = <String, String>{
    'O': '0',
    'o': '0',
    'I': '1',
    'i': '1',
    'l': '1',
    'L': '1',
    '|': '1',
    'Z': '2',
    'z': '2',
    'S': '5',
    's': '5',
    'G': '6',
    'B': '8',
  };
  static const _noise = {'.', ',', ':', ';', "'", '`', '"', '-', '_', '~'};
  static bool needsConfirmation(String raw) =>
      RegExp(r'[|ZzGBL]').hasMatch(raw);

  static ({String digits, List<String> observed, List<String?> notes})?
  normalize(String source) {
    final digits = StringBuffer();
    final observed = <String>[];
    final notes = <String?>[];
    for (final rune in source.runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'^\s$').hasMatch(char) || _noise.contains(char)) continue;
      if (RegExp(r'^[0-9]$').hasMatch(char)) {
        digits.write(char);
        observed.add(char);
        notes.add(null);
        continue;
      }
      final mapped = lookAlikes[char];
      if (mapped == null) return null;
      digits.write(mapped);
      observed.add(char);
      notes.add('$char→$mapped em linha numérica');
    }
    return (digits: digits.toString(), observed: observed, notes: notes);
  }
}
