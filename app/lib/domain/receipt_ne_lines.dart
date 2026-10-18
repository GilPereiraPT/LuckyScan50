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
}
