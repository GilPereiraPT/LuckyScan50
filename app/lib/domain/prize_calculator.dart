const _tiers = <String, int>{
  '5+2': 1, '5+1': 2, '5+0': 3, '4+2': 4, '4+1': 5, '3+2': 6, '4+0': 7,
  '2+2': 8, '3+1': 9, '3+0': 10, '1+2': 11, '2+1': 12, '2+0': 13,
};

int? tierFor(int mainMatches, int starMatches) {
  if (mainMatches < 0 || mainMatches > 5 ||
      starMatches < 0 || starMatches > 2) {
    throw RangeError('Contagem de acertos inválida');
  }
  return _tiers['$mainMatches+$starMatches'];
}
