import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { validateResult, type DrawResult } from "../domain/results.js";

const filePath = resolve(process.env.RESULTS_PATH ?? "./data/results.json");
export async function allResults(): Promise<DrawResult[]> {
  try {
    const data: unknown = JSON.parse(await readFile(filePath, "utf8"));
    if (!Array.isArray(data)) throw new Error("Formato da base inválido");
    data.forEach(x => validateResult(x as DrawResult));
    return data as DrawResult[];
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw err;
  }
}
export async function importResult(result: DrawResult): Promise<void> {
  validateResult(result);
  const rows = await allResults();
  const i = rows.findIndex(r => r.game === result.game && r.drawId === result.drawId);
  if (i >= 0) rows[i] = result; else rows.push(result);
  rows.sort((a,b) => a.date.localeCompare(b.date) || a.game.localeCompare(b.game));
  await mkdir(dirname(filePath), { recursive: true });
  const temp = filePath + "." + randomUUID() + ".tmp";
  await writeFile(temp, JSON.stringify(rows, null, 2) + "\n", { flag: "wx", mode: 0o600 });
  await rename(temp, filePath);
}
