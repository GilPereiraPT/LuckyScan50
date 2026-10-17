import { describe, expect, it } from "vitest";
import { tierFor } from "../src/domain/prizeTier.js";

describe("tierFor", () => {
  it("classifica todos os escalões", () => {
    const samples: Array<[number, number]> = [
      [5,2],[5,1],[5,0],[4,2],[4,1],[3,2],[4,0],
      [2,2],[3,1],[3,0],[1,2],[2,1],[2,0],
    ];
    samples.forEach(([n,s],i) => expect(tierFor(n,s)).toBe(i+1));
  });
  it("devolve null sem prémio", () => {
    expect(tierFor(1,0)).toBeNull();
    expect(tierFor(0,2)).toBeNull();
  });
  it("rejeita contagens inválidas", () => {
    expect(() => tierFor(6,0)).toThrow(RangeError);
  });
});
