#!/usr/bin/env python3
"""jit-replay.py — F0: reproduz a tabela do §3 (queries.json) e repete o limiar sobre os replies REAIS do
transcript do mainbot. Só leitura; nada de hook. Saída: ~/.adas/jit/replay.json.
Uso: jit-replay.py queries <queries.json> | replies <transcript.jsonl> [--lim N] [--skip N]"""
import glob, importlib.util, json, os, statistics, sys, time, urllib.request

D = os.path.dirname(os.path.abspath(__file__))
from importlib.machinery import SourceFileLoader
spec = importlib.util.spec_from_file_location("rs", os.path.join(D, "regra-search"), loader=SourceFileLoader("rs", os.path.join(D, "regra-search")))
rs = importlib.util.module_from_spec(spec); spec.loader.exec_module(rs)

idx = rs.Index()
def _embed(q):
    req = urllib.request.Request(rs.OLL, data=json.dumps({"model": rs.MODEL, "input": [q[:int(os.environ.get("ADAS_EMBED_Q","2000"))]]}).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r: return json.loads(r.read())["embeddings"][0]
idx.embed = _embed
print("nível:", 2 if idx.vec else 1)

def run(q):
    t0 = time.time(); res = idx.search(q); ms = (time.time() - t0) * 1000
    for r in res: r["acima"] = rs.acima(r)
    return res, ms

def queries(path):
    out = []
    for label, q, exp in json.load(open(path)):
        res, ms = run(q)
        ids = [r["id"] for r in res]
        ranks = {e: (ids.index(e) + 1 if e in ids else ">15") for e in exp}
        l2s = [r for r in res if r["l2"] is not None]; bms = [r for r in res if r["bm25"] is not None]
        t1 = min(l2s, key=lambda r: r["l2"]) if l2s else None; b1 = min(bms, key=lambda r: r["bm25"]) if bms else None
        ac = [r["id"] for r in res if r["acima"]][:3]
        out.append({"label": label, "esperado": exp, "rank_hibrido": ranks, "l2_top1": [t1["id"], t1["l2"]] if t1 else None,
                    "bm25_top1": [b1["id"], b1["bm25"]] if b1 else None, "acima_do_limiar": ac, "ms": round(ms)})
        print(f'- {label[:46]:46s} rank {ranks} | l2 {out[-1]["l2_top1"]} | bm25 {out[-1]["bm25_top1"]} | acima {ac}')
    return out

def replies(path, lim, skip):
    items = []
    for l in open(path):
        try: d = json.loads(l)
        except Exception: continue
        c = (d.get("message") or {}).get("content")
        if isinstance(c, list):
            for b in c:
                if b.get("type") == "tool_use" and b.get("name", "").endswith("telegram__reply"):
                    t = (b.get("input") or {}).get("text") or ""
                    if t.strip(): items.append({"ts": d.get("timestamp"), "text": t})
    items = items[skip:skip + lim]
    out = []
    for i, it in enumerate(items):
        res, ms = run(it["text"])
        out.append({"ts": it["ts"], "len": len(it["text"]), "ms": round(ms), "ini": it["text"][:80].replace("\n", " "),
                    "cartoes": [{k: r[k] for k in ("id", "rank", "l2", "bm25", "acima")} for r in res[:8]]})
    return out

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "queries":
        json.dump(queries(a[1]), open(os.path.join(D, "replay-queries.json"), "w"), ensure_ascii=False, indent=1)
    else:
        lim = int(a[a.index("--lim") + 1]) if "--lim" in a else 10**6
        skip = int(a[a.index("--skip") + 1]) if "--skip" in a else 0
        r = replies(a[1], lim, skip)
        p = os.path.join(D, f"replay-replies-{os.environ.get("ADAS_EMBED_Q","2000")}-{skip}.json"); json.dump(r, open(p, "w"), ensure_ascii=False)
        print(len(r), "replies →", p, "| p95 ms", sorted(x["ms"] for x in r)[int(len(r) * .95) - 1])
