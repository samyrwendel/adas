#!/usr/bin/env python3
"""jit-filtro-replay.py — calibra JUIZ_LIMIAR do filtro de evento (regra-jit.py juiz_filtra) no replay das linhas
julgadas à mão (relatório da task 20261102-024: idx = posição entre as linhas `inline` do regra-jit.log).
Uso: jit-filtro-replay.py <julgamentos.txt> [--ledger regra-jit.log]. Só leitura; chama o juiz de verdade (~5e-5 USD/linha)."""
import importlib.util, json, os, re, sys, tempfile
os.environ["ADAS_JIT_BUS"] = tempfile.mkdtemp()  # contador de teto isolado
D = os.path.dirname(os.path.realpath(__file__))
sp = importlib.util.spec_from_file_location("rj", os.path.join(D, "regra-jit.py")); rj = importlib.util.module_from_spec(sp); sp.loader.exec_module(rj)
rel = sys.argv[1]
led = os.path.expanduser(sys.argv[sys.argv.index("--ledger") + 1]) if "--ledger" in sys.argv else os.path.expanduser("~/.claude/bus/regra-jit.log")
inline = [j for j in (json.loads(l) for l in open(led)) if j.get("decisao") == "inline"]
G = {g["id"]: g for g in json.load(open(os.path.join(rj.D, "gatilhos.json")))}
rows = []  # (idx, cartão, S|N)
for l in open(rel):
    m = re.match(r"(\d+) \| (\w+) \| ([^|]+) \| ([SNP]) \| (.*)", l)
    if not m: continue
    i, v, mot = int(m[1]), m[4], m[5]
    for cid in re.findall(r"(D[AC]-\d+)\(", m[3]):
        s = "S" if v == "S" else "N" if v == "N" else ("S" if re.search(cid + r" sim|" + cid + r" \(.*?\) pertinente", mot) else "N")
        rows.append((i, cid, s))
res = []
for i, cid, lab in rows:
    j = inline[i]
    c = {"id": cid, "regra_curta": G[cid]["regra_curta"], "motor": "evento"}
    _, p, meta = rj.juiz_filtra(j["superficie"], j["payload"], [c])
    res.append((i, cid, lab, p.get(cid), meta.get("ms"), meta.get("erro")))
    print(i, cid, lab, p.get(cid), meta.get("ms"), meta.get("erro") or "")
json.dump(res, open("/tmp/jit-filtro-replay.json", "w"))
ms = sorted(r[4] for r in res if r[4])
print("p95 ms:", ms[int(len(ms) * .95) - 1] if ms else None, "n:", len(res))
for lim in (.3, .4, .5, .6, .7, .8):
    k = [r for r in res if r[3] is not None and r[3] >= lim]; d = [r for r in res if r[3] is not None and r[3] < lim]
    S = sum(r[2] == "S" for r in k); FN = sum(r[2] == "S" for r in d)
    print(f"lim {lim}: fica {len(k)} (S {S}, N {len(k)-S}) precisão {S/max(1,len(k)):.0%} | derruba {len(d)} (S perdidos {FN}, N cortados {len(d)-FN})")
