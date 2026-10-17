import { describe, expect, it } from "vitest";
import { checkLine, validateResult, type EuroDraw, type MilhaoDraw } from "../src/domain/results.js";
const combinations: Array<[number, number]> = [[5,2],[5,1],[5,0],[4,2],[4,1],[3,2],[4,0],[2,2],[3,1],[3,0],[1,2],[2,1],[2,0]];
const draw: EuroDraw = {
  game:"euromilhoes",drawId:"083/2026",date:"2026-10-16",
  numbers:[7,15,16,22,35],stars:[4,6],status:"complete",
  sourceUrl:"https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes",
  retrievedAt:"2026-10-17T09:00:00Z",
  tiers:combinations.map(([main,stars],i)=>({tier:i+1,main,stars,
    amountCents:i===0?null:i===1?null:1000,winnersPortugal:0,winnersTotal:i<2?0:1})),
};
describe("validação e cálculo",()=>{
  it("aceita resultado completo com escalões sem vencedores",()=>expect(()=>validateResult(draw)).not.toThrow());
  it("calcula o escalão 3",()=>expect(checkLine(draw,[7,15,16,22,35],[1,2]).tier).toBe(3));
  it("não inventa valor sem vencedor no primeiro escalão",()=>{
    expect(checkLine(draw,[7,15,16,22,35],[4,6]).amountCents).toBeNull();
  });
  it("rejeita chave repetida",()=>expect(()=>checkLine(draw,[7,7,16,22,35],[4,6])).toThrow());
  it("rejeita escalões em falta",()=>expect(()=>validateResult({...draw,tiers:draw.tiers.slice(0,12)})).toThrow());
  it("rejeita prémio em falta com vencedores",()=>expect(()=>validateResult({
    ...draw,tiers:draw.tiers.map((v,i)=>i===2?{...v,amountCents:null}:v),
  })).toThrow());
  it("valida formato do M1lhão",()=>{
    const milhao:MilhaoDraw={game:"milhao",drawId:"009/2026",date:"2026-09-25",
      winningCode:"PTM 09893",status:"complete",
      sourceUrl:"https://www.jogossantacasa.pt/web/SCCartazResult/m1lhao",
      retrievedAt:"2026-10-17T09:00:00Z"};
    expect(()=>validateResult(milhao)).not.toThrow();
  });
});
