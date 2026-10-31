#!/usr/bin/env python3
"""jit-replay.py — F0: reproduz a tabela do §3 (queries.json) e repete o limiar sobre os replies REAIS do
transcript do mainbot. Só leitura; nada de hook. Saída: ~/.adas/jit/replay.json.
Uso: jit-replay.py queries <queries.json> | replies <transcript.jsonl> [--lim N] [--skip N]
     jit-replay.py espalha <queries.json> [--cwd DIR]   (sinapses: rank antes/depois do espalhamento → replay-espalha.json)"""
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

def espalha(path, cwd):
    """Sinapses B0 (task 20261031-031): rank do esperado ANTES (a0, recuperação híbrida) e DEPOIS (a1, espalhamento
    no grafo.json), com o filtro de escopo do cwd. Negativo (esperado vazio): máx a1 = teto de ruído."""
    esc, g, out = rs.escopos(cwd), rs.grafo(), []
    def rank(a, e):
        o = [k for k, _ in sorted(a.items(), key=lambda x: -x[1])]
        return o.index(e) + 1 if e in o else f">{len(o)}"
    for label, q, exp in json.load(open(path)):
        res = [r for r in idx.search(q, n=40) if rs.no_escopo(r.get("escopo"), esc)]
        a0 = {r["id"]: rs.ativacao(r) for r in res}
        a1 = rs.espalha(a0, g)
        a1 = {k: v for k, v in a1.items() if k in a0 or rs.no_escopo(escopo_de.get(k), esc)}
        row = {"label": label, "esperado": exp, "antes": {e: rank(a0, e) for e in exp}, "depois": {e: rank(a1, e) for e in exp},
               "max_a0": round(max(a0.values(), default=0), 3), "max_a1": round(max(a1.values(), default=0), 3),
               "top3_depois": [k for k, _ in sorted(a1.items(), key=lambda x: -x[1])[:3]]}
        out.append(row)
        print(f'- {label[:46]:46s} {row["antes"]} → {row["depois"]}  máx a1 {row["max_a1"]}  top3 {row["top3_depois"]}')
    neg = [r["max_a1"] for r in out if not r["esperado"]]
    print("teto de ruído (máx a1 nos negativos):", max(neg, default=None))
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
    if a[0] == "espalha":
        cwd = a[a.index("--cwd") + 1] if "--cwd" in a else os.path.expanduser("~")
        escopo_de = {k: e for k, e in idx.db.execute("select key, %s from docs" % ("escopo" if idx.tem_escopo else "''"))}
        json.dump(espalha(a[1], cwd), open(os.path.join(rs.D, "replay-espalha.json"), "w"), ensure_ascii=False, indent=1)
    elif a[0] == "queries":
        json.dump(queries(a[1]), open(os.path.join(D, "replay-queries.json"), "w"), ensure_ascii=False, indent=1)
    else:
        lim = int(a[a.index("--lim") + 1]) if "--lim" in a else 10**6
        skip = int(a[a.index("--skip") + 1]) if "--skip" in a else 0
        r = replies(a[1], lim, skip)
        p = os.path.join(D, f"replay-replies-{os.environ.get("ADAS_EMBED_Q","2000")}-{skip}.json"); json.dump(r, open(p, "w"), ensure_ascii=False)
        print(len(r), "replies →", p, "| p95 ms", sorted(x["ms"] for x in r)[int(len(r) * .95) - 1])
