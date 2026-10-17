"""LuckyScan50 WSGI puro, compatível com Passenger, sem bibliotecas externas."""
import json
import os
import re
from pathlib import Path
from datetime import date, datetime
from urllib.parse import parse_qs

ROOT = Path(__file__).resolve().parent
DATA_FILE = Path(os.environ.get("LUCKYSCAN_RESULTS_FILE", str(ROOT / "data" / "results.json")))
TIERS = ((5,2),(5,1),(5,0),(4,2),(4,1),(3,2),(4,0),(2,2),(3,1),(3,0),(1,2),(2,1),(2,0))

def validate_result(row):
    if not isinstance(row, dict) or row.get("game") not in ("euromilhoes", "milhao"):
        raise ValueError("Invalid game")
    if not re.fullmatch(r"\d{3}/\d{4}", str(row.get("drawId", ""))):
        raise ValueError("Invalid draw")
    try:
        date.fromisoformat(row["date"])
        datetime.fromisoformat(row["retrievedAt"].replace("Z", "+00:00"))
    except (KeyError, TypeError, ValueError, AttributeError):
        raise ValueError("Invalid dates") from None
    if not str(row.get("sourceUrl", "")).startswith("https://"):
        raise ValueError("Invalid source")
    if row["game"] == "milhao":
        if not re.fullmatch(r"[A-Z]{3} ?\d{5}", str(row.get("winningCode", ""))):
            raise ValueError("Invalid Milhao")
        return
    for field,count,maximum in (("numbers",5,50),("stars",2,12)):
        nums = row.get(field)
        if not isinstance(nums,list) or len(nums)!=count or len(set(nums))!=count or any(type(v)!=int or v<1 or v>maximum for v in nums):
            raise ValueError("Invalid "+field)
    tiers = row.get("tiers")
    if not isinstance(tiers,list) or len(tiers)!=13:
        raise ValueError("Invalid tiers")
    for i,t in enumerate(tiers):
        if not isinstance(t,dict) or (t.get("tier"),t.get("main"),t.get("stars")) != (i+1,*TIERS[i]):
            raise ValueError("Invalid tier")
        for name in ("amountCents","winnersPortugal","winnersTotal"):
            v=t.get(name)
            if v is not None and (type(v)!=int or v<0):
                raise ValueError("Invalid "+name)
        if row.get("status")=="complete" and t.get("amountCents") is None and (t.get("winnersTotal") or 0)>0:
            raise ValueError("Missing prize amount")
    if row.get("status") not in ("complete","numbers_confirmed"):
        raise ValueError("Invalid status")

def load_results():
    try:
        rows=json.loads(DATA_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return []
    if not isinstance(rows,list):
        raise ValueError("Invalid storage")
    for row in rows:
        validate_result(row)
    return sorted(rows,key=lambda x:(x["date"],x["game"],x["drawId"]))

def application(environ,start_response):
    path=environ.get("PATH_INFO","/")
    query=parse_qs(environ.get("QUERY_STRING",""))
    def reply(code,data):
        body=json.dumps(data,ensure_ascii=False).encode("utf-8")
        status={200:"OK",400:"Bad Request",404:"Not Found",405:"Method Not Allowed",503:"Service Unavailable"}
        start_response(str(code)+" "+status[code],[("Content-Type","application/json; charset=utf-8"),("Content-Length",str(len(body))),("Cache-Control","public, max-age=120" if code==200 else "no-store"),("X-Content-Type-Options","nosniff")])
        return [body]
    if environ.get("REQUEST_METHOD")!="GET":
        return reply(405,{"error":"method_not_allowed"})
    if path in ("/","/health"):
        return reply(200,{"ok":True,"service":"luckyscan50-results","version":"0.1.1","runtime":"native_wsgi"})
    if not (path in ("/v1/draws","/v1/draws/latest","/v1/milhao/latest") or path.startswith("/v1/draws/")):
        return reply(404,{"error":"not_found"})
    game="milhao" if path=="/v1/milhao/latest" else query.get("game",["euromilhoes"])[0]
    if game not in ("euromilhoes","milhao"):
        return reply(400,{"error":"invalid_game"})
    try:
        rows=load_results()
    except (ValueError,OSError,TypeError,KeyError,json.JSONDecodeError):
        return reply(503,{"error":"results_unavailable"})
    if path=="/v1/draws":
        try:
            limit=int(query.get("limit",["30"])[0])
        except (ValueError,TypeError):
            return reply(400,{"error":"invalid_limit"})
        if not 1<=limit<=100:
            return reply(400,{"error":"invalid_limit"})
        return reply(200,{"data":list(reversed([r for r in rows if r["game"]==game]))[:limit]})
    if path in ("/v1/draws/latest","/v1/milhao/latest"):
        subset=[r for r in rows if r["game"]==game]
        return reply(200,subset[-1]) if subset else reply(404,{"error":"no_validated_results"})
    match=re.fullmatch(r"/v1/draws/(euromilhoes|milhao)/(\d{3})/(\d{4})",path)
    if not match:
        return reply(404,{"error":"not_found"})
    found=next((r for r in rows if r["game"]==match[1] and r["drawId"]==match[2]+"/"+match[3]),None)
    return reply(200,found) if found else reply(404,{"error":"draw_not_found"})
