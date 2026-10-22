"""Run once from cPanel's Execute Python Script; no terminal arguments needed."""
import json
from historical_results import run

try:
    print(json.dumps(run(apply=True), ensure_ascii=False))
except Exception as exc:
    print(json.dumps({'status': 'stopped', 'error': type(exc).__name__, 'detail': str(exc)},
                     ensure_ascii=False))
    raise SystemExit(1)
