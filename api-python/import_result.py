"""Importar resultados previamente verificados por um operador; CLI não pública."""
import json
import os
import sys
import tempfile
from pathlib import Path
from app import DATA_FILE, validate_result, load_results

def main(path):
    result = json.loads(Path(path).read_text(encoding="utf-8"))
    validate_result(result)
    current = [item for item in load_results()
               if (item["game"], item["drawId"]) != (result["game"], result["drawId"])]
    current.append(result)
    current.sort(key=lambda x: (x["date"], x["game"], x["drawId"]))
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".luckyscan-", suffix=".tmp", dir=DATA_FILE.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(current, out, ensure_ascii=False, indent=2)
            out.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, DATA_FILE)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    print(f"Importado: {result['game']} {result['drawId']}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Uso: python import_result.py ficheiro.json")
    main(sys.argv[1])
