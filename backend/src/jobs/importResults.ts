import { readFile } from "node:fs/promises";
import { importResult } from "../data/store.js";
import { validateResult, type DrawResult } from "../domain/results.js";

const path = process.argv[2];
if (!path) {
  console.error("Uso: npm run import:result -- caminho/resultado.json");
  process.exitCode = 2;
} else {
  try {
    const data = JSON.parse(await readFile(path,"utf8")) as DrawResult;
    validateResult(data);
    await importResult(data);
    console.log("Concurso validado e importado:", data.game, data.drawId);
  } catch (error) {
    console.error("Falha na importação:", (error as Error).message);
    process.exitCode = 1;
  }
}
