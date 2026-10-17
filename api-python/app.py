"""LuckyScan50: API de resultados validada, apenas de leitura."""
import json
import os
import re
from datetime import datetime, date
from pathlib import Path
from flask import Flask, jsonify, request

application = Flask(__name__)
ROOT = Path(__file__).resolve().parent
DATA_FILE = Path(os.environ.get("LUCKYSCAN_RESULTS_FILE", str(ROOT / "data" / "results.json"))).resolve()
VALID_GAMES = frozenset(("euromilhoes", "milhao"))
EXPECTED_TIERS = (
    (5,2),(5,1),(5,0),(4,2),(4,1),(3,2),(4,0),
    (2,2),(3,1),(3,0),(1,2),(2,1),(2,0),
)

def validate_result(result):
    if not isinstance(result, dict) or result.get("game") not in VALID_GAMES:
        raise ValueError("Jogo inválido")
    if not re.fullmatch(r"\d{3}/\d{4}", str(result.get("drawId", ""))):
        raise ValueError("Concurso inválido")
    try:
        date.fromisoformat(result["date"])
        datetime.fromisoformat(result["retrievedAt"].replace("Z", "+00:00"))
    except (ValueError, TypeError, KeyError) as exc:
        raise ValueError("Datas inválidas") from exc
    if not str(result.get("sourceUrl", "")).startswith("https://"):
        raise ValueError("Origem inválida")
    if result["game"] == "milhao":
        if not re.fullmatch(r"[A-Z]{3} ?\d{5}", str(result.get("winningCode", ""))):
            raise ValueError("Código M1lhão inválido")
        return
    for key, size, maximum in (("numbers", 5, 50), ("stars", 2, 12)):
        values = result.get(key)
        if (not isinstance(values, list) or len(values) != size
                or any(type(n) is not int or n < 1 or n > maximum for n in values)
                or len(set(values)) != size):
            raise ValueError(f"Campo inválido: {key}")
    tiers = result.get("tiers")
    if not isinstance(tiers, list) or len(tiers) != 13:
        raise ValueError("Necessários 13 escalões")
    for i, tier in enumerate(tiers):
        if (not isinstance(tier, dict)
                or tier.get("tier") != i + 1
                or (tier.get("main"), tier.get("stars")) != EXPECTED_TIERS[i]):
            raise ValueError("Escalão inválido")
        for field in ("amountCents", "winnersPortugal", "winnersTotal"):
            value = tier.get(field)
            if value is not None and (type(value) is not int or value < 0):
                raise ValueError(f"Valor inválido: {field}")
        if (result.get("status") == "complete"
                and tier.get("amountCents") is None
                and (tier.get("winnersTotal") or 0) > 0):
            raise ValueError("Prémio desconhecido com vencedores")
    if result.get("status") not in ("complete", "numbers_confirmed"):
        raise ValueError("Estado inválido")

def load_results():
    try:
        with DATA_FILE.open(encoding="utf-8") as fp:
            data = json.load(fp)
    except FileNotFoundError:
        return []
    if not isinstance(data, list):
        raise ValueError("Base de dados inválida")
    for item in data:
        validate_result(item)
    return sorted(data, key=lambda x: (x["date"], x["game"], x["drawId"]))

def response(payload, status=200):
    res = jsonify(payload)
    res.status_code = status
    res.headers["Cache-Control"] = "public, max-age=120" if status == 200 else "no-store"
    res.headers["X-Content-Type-Options"] = "nosniff"
    return res

@application.get("/health")
def health():
    return response({"ok": True, "service": "luckyscan50-results", "version": "0.1.0"})

@application.get("/v1/draws/latest")
def latest():
    game = request.args.get("game", "euromilhoes")
    if game not in VALID_GAMES:
        return response({"error": "invalid_game"}, 400)
    try:
        items = [item for item in load_results() if item["game"] == game]
    except (ValueError, OSError, json.JSONDecodeError):
        return response({"error": "results_unavailable"}, 503)
    return response(items[-1]) if items else response({"error": "no_validated_results"}, 404)

@application.get("/v1/draws")
def list_draws():
    game = request.args.get("game", "euromilhoes")
    if game not in VALID_GAMES:
        return response({"error": "invalid_game"}, 400)
    try:
        limit = int(request.args.get("limit", "30"))
    except ValueError:
        return response({"error": "invalid_limit"}, 400)
    if not 1 <= limit <= 100:
        return response({"error": "invalid_limit"}, 400)
    try:
        items = [item for item in load_results() if item["game"] == game]
    except (ValueError, OSError, json.JSONDecodeError):
        return response({"error": "results_unavailable"}, 503)
    return response({"data": list(reversed(items))[:limit]})

@application.get("/v1/draws/<game>/<draw_id>/<year>")
def draw_by_id(game, draw_id, year):
    if game not in VALID_GAMES or not re.fullmatch(r"\d{3}", draw_id) or not re.fullmatch(r"\d{4}", year):
        return response({"error": "invalid_draw"}, 400)
    try:
        items = load_results()
    except (ValueError, OSError, json.JSONDecodeError):
        return response({"error": "results_unavailable"}, 503)
    match = next((r for r in items if r["game"] == game and r["drawId"] == draw_id + "/" + year), None)
    return response(match) if match else response({"error": "draw_not_found"}, 404)

@application.get("/v1/milhao/latest")
def milhao_latest():
    with application.test_request_context("/v1/draws/latest?game=milhao"):
        return latest()

if __name__ == "__main__":
    application.run(host="127.0.0.1", port=int(os.environ.get("PORT", "3000")))
