export type PrizeTier = { tier: number; main: number; stars: number; amountCents: number | null; winnersPortugal: number | null; winnersTotal: number | null };
export type EuroDraw = {
  game: "euromilhoes"; drawId: string; date: string; numbers: number[]; stars: number[];
  tiers: PrizeTier[]; status: "numbers_confirmed" | "complete";
  sourceUrl: string; retrievedAt: string;
};
export type MilhaoDraw = {
  game: "milhao"; drawId: string; date: string; winningCode: string;
  status: "complete"; sourceUrl: string; retrievedAt: string;
};
export type DrawResult = EuroDraw | MilhaoDraw;
const signatures: ReadonlyArray<readonly [number,number]> = [
  [5,2],[5,1],[5,0],[4,2],[4,1],[3,2],[4,0],
  [2,2],[3,1],[3,0],[1,2],[2,1],[2,0],
];
const validDate = (date: string) => /^\d{4}-\d{2}-\d{2}$/.test(date) &&
  !Number.isNaN(Date.parse(date)) && new Date(date + "T00:00:00Z").toISOString().slice(0,10) === date;
export function validateResult(draw: DrawResult): void {
  if (!/^\d{3}\/\d{4}$/.test(draw.drawId) || !validDate(draw.date) ||
      !/^https:\/\//.test(draw.sourceUrl) || Number.isNaN(Date.parse(draw.retrievedAt))) {
    throw new Error("Identificador, data ou fonte inválidos");
  }
  if (draw.game === "milhao") {
    if (!/^[A-Z]{3} ?\d{5}$/.test(draw.winningCode)) throw new Error("Código M1lhão inválido");
    return;
  }
  for (const [values, expectedLength, upper] of [[draw.numbers, 5, 50], [draw.stars, 2, 12]] as const) {
    if (values.length !== expectedLength || new Set(values).size !== expectedLength ||
        values.some(x => !Number.isInteger(x) || x < 1 || x > upper)) {
      throw new Error("Números/estrelas inválidos");
    }
  }
  if (draw.tiers.length !== 13 ||
      draw.tiers.some((p,i) => p.tier !== i+1 ||
        p.main !== signatures[i][0] || p.stars !== signatures[i][1] ||
        (p.amountCents !== null && (!Number.isInteger(p.amountCents) || p.amountCents < 0)) ||
        (p.winnersPortugal !== null && (!Number.isInteger(p.winnersPortugal) || p.winnersPortugal < 0)) ||
        (p.winnersTotal !== null && (!Number.isInteger(p.winnersTotal) || p.winnersTotal < 0)))) {
    throw new Error("Escalões incompletos ou incorretos");
  }
  if (draw.status === "complete" && draw.tiers.some(t => t.amountCents === null && (t.winnersTotal ?? 0) > 0)) {
    throw new Error("Valor em falta num escalão com vencedores");
  }
}
export function checkLine(draw: EuroDraw, numbers: number[], stars: number[]) {
  validateResult(draw);
  if (numbers.length !== 5 || stars.length !== 2 ||
      new Set(numbers).size !== 5 || new Set(stars).size !== 2 ||
      numbers.some(n => !Number.isInteger(n) || n < 1 || n > 50) ||
      stars.some(n => !Number.isInteger(n) || n < 1 || n > 12)) {
    throw new Error("Chave inválida");
  }
  const main = numbers.filter(n => draw.numbers.includes(n)).length;
  const starCount = stars.filter(n => draw.stars.includes(n)).length;
  const tier = draw.tiers.find(p => p.main === main && p.stars === starCount);
  return { main, stars: starCount, tier: tier?.tier ?? null,
    amountCents: draw.status === "complete" ? (tier?.amountCents ?? null) : null,
    amountConfirmed: draw.status === "complete" && (!tier || tier.amountCents !== null) };
}
