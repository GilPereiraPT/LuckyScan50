"""Run once from cPanel Execute Python Script, using the existing results database."""
import json
import official_milhao
from historical_results import run

try:
    print(json.dumps(run(apply=True, adapter=official_milhao), ensure_ascii=False))
except Exception as exc:
    print(json.dumps({'status': 'stopped', 'error': type(exc).__name__, 'detail': str(exc)},
                     ensure_ascii=False))
    raise SystemExit(1)
