import 'receipt_evidence.dart';
import 'receipt_cells.dart';
import 'receipt_geometry.dart';
import 'receipt_parser.dart';

class CellConsensus {
  const CellConsensus(this.bets, this.evidence);
  final List<ParsedBet> bets;
  final List<BetEvidence> evidence;
}

/// Slots are geometrical identities, never the position in a partial text list.
CellConsensus consolidateCellEvidence(
  List<BetCrop> cells,
  List<ValueEvidence> observations,
) {
  final bets = <ParsedBet>[], provenance = <BetEvidence>[];
  final indices = cells.map((c) => c.index).toSet().toList()..sort();
  for (final index in indices) {
    final candidates = <ValueEvidence>[],
        accepted = <ValueEvidence>[],
        issues = <String>[];
    final numbers = <int>[], stars = <int>[];
    for (final group in [
      (kind: 'N', count: 5, maximum: 50, values: numbers),
      (kind: 'E', count: 2, maximum: 12, values: stars),
    ]) {
      for (var slot = 0; slot < group.count; slot++) {
        final all = observations
            .where(
              (v) =>
                  v.betIndex == index &&
                  v.kind == group.kind &&
                  v.position == slot,
            )
            .toList();
        final expected = cells
            .where(
              (c) =>
                  c.index == index &&
                  c.kind == group.kind &&
                  c.position == slot,
            )
            .toList();
        bool associated(ValueEvidence v) {
          if (expected.length != 1 || v.bounds == null) return false;
          final box = expected.single.box, got = v.bounds!;
          final x = (got.left + got.right) / 2, y = (got.top + got.bottom) / 2;
          return x >= box.left &&
              x <= box.right &&
              y >= box.top &&
              y <= box.bottom;
        }

        final values = all
            .where(
              (v) => associated(v) && v.value >= 1 && v.value <= group.maximum,
            )
            .toList();
        candidates.addAll(
          all
              .where((v) => !values.contains(v))
              .map(
                (v) => v.validated(
                  associated(v) ? 'rejected-range' : 'rejected-association',
                ),
              ),
        );
        final distinct = values.map((v) => v.value).toSet();
        final conflict = distinct.length > 1;
        final confirmed =
            distinct.length == 1 &&
            (values.any(
                  (v) => v.correction == null && !v.requiresConfirmation,
                ) ||
                values.map((v) => v.pass).toSet().length >= 2);
        final state = conflict
            ? 'conflict'
            : confirmed
            ? 'accepted'
            : 'pending';
        candidates.addAll(
          values.map((v) => v.validated(state, conflict: conflict)),
        );
        if (confirmed && !conflict) {
          final v = values
              .firstWhere(
                (v) => v.correction == null,
                orElse: () => values.first,
              )
              .validated('accepted');
          accepted.add(v);
          group.values.add(v.value);
        } else {
          issues.add(
            '${group.kind}[${slot + 1}]: ${conflict ? 'conflito entre leituras' : 'sem confirmação suficiente'}',
          );
        }
      }
      if (group.values.toSet().length != group.values.length) {
        issues.add('${group.kind}: valores repetidos na mesma aposta');
      }
    }
    bets.add(ParsedBet(index, numbers, stars, issues));
    provenance.add(
      BetEvidence(index, candidates, issues, acceptedValues: accepted),
    );
  }
  return CellConsensus(bets, provenance);
}

/// Projects observed element centres from an axis-aligned crop into the working
/// image. This also accepts captured old row results; text order is irrelevant.
List<ValueEvidence> projectCellObservations(
  OcrFrame frame,
  List<BetCrop> cells,
  String pass, {
  CropBox? sourceBox,
  double scale = 1,
}) {
  if (scale <= 0 || !scale.isFinite) return [];
  final observations = <ValueEvidence>[];
  for (final cell in cells.where((c) => c.isCell && c.kind != 'marker')) {
    for (final token in frame.tokens) {
      if (verticalReceiptToken(token)) continue;
      final x = (sourceBox?.left ?? 0) + token.x / scale;
      final y = (sourceBox?.top ?? 0) + token.y / scale;
      if (x < cell.box.left ||
          x > cell.box.right ||
          y < cell.box.top ||
          y > cell.box.bottom ||
          token.width / scale > cell.box.width * 1.2) {
        continue;
      }
      final parsed = parseNumericCell(token.text, cell.kind!);
      final rejected =
          parsed.value == null && RegExp(r'^\d{1,2}$').hasMatch(parsed.raw);
      if (parsed.value == null && !rejected) continue;
      observations.add(
        ValueEvidence(
          cell.kind!,
          cell.position!,
          parsed.value ?? int.parse(parsed.raw),
          parsed.raw,
          pass,
          betIndex: cell.index,
          bounds: cell.box,
          correction: parsed.correction,
          requiresConfirmation:
              parsed.raw.length == 1 || parsed.correction != null,
          validation: rejected ? 'rejected-range' : 'observed',
        ),
      );
    }
  }
  return observations;
}
