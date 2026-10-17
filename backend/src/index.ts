import { createServer } from "node:http";
import { allResults } from "./data/store.js";

const port = Number(process.env.PORT ?? 3000);
const send = (res: import("node:http").ServerResponse, status: number, body: unknown) => {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": status === 200 ? "public, max-age=120" : "no-store",
    "access-control-allow-origin": "*",
    "x-content-type-options": "nosniff",
  });
  res.end(JSON.stringify(body));
};
createServer(async (req,res) => {
  if (req.method !== "GET") return send(res,405,{error:"method_not_allowed"});
  const url = new URL(req.url ?? "/", "http://localhost");
  if (url.pathname === "/health") return send(res,200,{ok:true,service:"luckyscan50-results"});
  try {
    const rows = await allResults();
    if (url.pathname === "/v1/draws/latest") {
      const game = url.searchParams.get("game") ?? "euromilhoes";
      if (!["euromilhoes","milhao"].includes(game)) return send(res,400,{error:"invalid_game"});
      const match = rows.filter(r=>r.game===game).at(-1);
      return match ? send(res,200,match) : send(res,404,{error:"no_validated_results"});
    }
    if (url.pathname === "/v1/draws") {
      const game = url.searchParams.get("game") ?? "euromilhoes";
      if (!["euromilhoes","milhao"].includes(game)) return send(res,400,{error:"invalid_game"});
      const limit = Number(url.searchParams.get("limit") ?? 30);
      if (!Number.isInteger(limit) || limit < 1 || limit > 100) return send(res,400,{error:"invalid_limit"});
      return send(res,200,{data:rows.filter(r=>r.game===game).reverse().slice(0,limit)});
    }
    const match = /^\/v1\/draws\/(euromilhoes|milhao)\/(\d{3})\/(\d{4})$/.exec(url.pathname);
    if (match) {
      const result = rows.find(r=>r.game===match[1] && r.drawId===match[2]+"/"+match[3]);
      return result ? send(res,200,result) : send(res,404,{error:"draw_not_found"});
    }
    return send(res,404,{error:"not_found"});
  } catch {
    return send(res,503,{error:"results_unavailable"});
  }
}).listen(port, () => console.log(`LuckyScan50 results API on port ${port}`));
