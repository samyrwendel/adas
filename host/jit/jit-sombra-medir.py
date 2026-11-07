#!/usr/bin/env python3
"""jit-sombra-medir.py — mede a SOMBRA do Jev (task 20261107-016) sobre queries.json + o caso 'quero fazer trade'.
  jit-sombra-medir.py [queries.json] [-n 45] [--vec] [--catalogo] [--limiar 0.5] [--out FILE]
Por consulta: ids que o Jev acendeu (p ≥ limiar), se os esperados vieram, ms dos candidatos (bm25+vetor+grafo) e do Jev, custo.
Resumo: acerto dos esperados, ids médios nos NEGATIVOS (inundação), p95 de latência, custo por prompt. Só leitura."""
import importlib.util, json, os, statistics, sys, time

D = os.path.dirname(os.path.abspath(__file__))
a = sys.argv[1:]
def opt(n, d, t=str): return t(a[a.index(n) + 1]) if n in a else d
N, LIM = opt("-n", 45, int), opt("--limiar", 0.5, float)
if "--vec" in a: os.environ["ADAS_JIT_SOMBRA_VEC"] = "1"  # padrão da sombra é bm25+grafo, sem vetor
os.environ["ADAS_JIT_SOMBRA_EMBED"] = os.environ.get("ADAS_JIT_SOMBRA_EMBED", "30")
sp = importlib.util.spec_from_file_location("rj", os.path.join(D, "regra-jit.py")); rj = importlib.util.module_from_spec(sp); sp.loader.exec_module(rj)
sys.path.insert(0, D); import juiz_prov

pos = [x for i, x in enumerate(a) if x.endswith(".json") and (i == 0 or a[i-1] != "--out")]
qs = json.load(open(pos[0] if pos else os.path.expanduser("~/.adas/jit/queries.json")))
qs.append(["caso: quero fazer trade", "quero fazer um trade de BTC agora, long com alavancagem 10x", ["DA-629", "DA-390", "DA-392"]])
esc = {"produto", "instância"}
import sqlite3
NOIDX = {r[0] for r in sqlite3.connect(os.path.join(os.path.expanduser("~/.adas/jit"), "regras.db")).execute("select key from docs")}
qs = [[l, q, [e for e in ex if e in NOIDX]] for l, q, ex in qs]  # esperado que não está no índice vivo não é falha do Jev (consolidado/ausente)
CARDS = json.load(open(os.path.expanduser("~/.adas/jit/cards.json"))) if "--catalogo" in a else []
out = []
for label, q, exp in qs:
    t0 = time.time()
    if "--catalogo" in a:  # todos os cartões do escopo, só título (sem vetor): o Jev lê o catálogo inteiro
        cand, vetor = [{"id": c["id"], "titulo": c["titulo"][:110], "regra_curta": ""} for c in CARDS if rj.rs().no_escopo(c.get("escopo"), esc)], "-"
    else:
        cand, vetor = rj.candidatos_largos(q, esc, N)
    t1 = time.time()
    perg = [{"id": c["id"], "pergunta": f'{c["titulo"]}'} for c in cand] if "--catalogo" in a else [{"id": c["id"], "pergunta": (f'O dono está pedindo/prestes a fazer algo cujo assunto a regra {c["id"]} — "{c.get("titulo") or ""}" — governa, '
            f'ou que ela COMPLEMENTA, de modo que lembrá-la agora evitaria erro? Regra: {c["regra_curta"]} Responda NÃO se o assunto só aparece por acaso.')} for c in cand]
    txt = ("MENSAGEM DO DONO (decida o que vale lembrar ANTES de agir). Para cada item abaixo, que é o título de uma regra do diário: "
           "responda SIM só se a regra GOVERNA o que o dono pede, ou COMPLEMENTA/limita uma regra que governa (teto de risco, quem executa, onde pode operar).\n" + q[:1500]) if "--catalogo" in a else q[:1500]
    try:
        resp, m = juiz_prov.perguntar(txt, perg, t1 + 25)
    except Exception as e:
        out.append({"label": label, "erro": str(e)[:80]}); continue
    ids = [i for i, v in sorted(resp.items(), key=lambda kv: -kv[1]) if v >= LIM]
    em_cand = [e for e in exp if e in {c["id"] for c in cand}]
    out.append({"label": label, "esperado": exp, "nos_candidatos": em_cand, "acendeu": [e for e in exp if e in ids], "ids": ids,
                "vetor": vetor, "ms_cand": round((t1 - t0) * 1000), "ms_jev": round((time.time() - t1) * 1000), "cost": m.get("cost") or 0})
    print(f'- {label[:44]:44s} esp {exp} cand {em_cand} acendeu {out[-1]["acendeu"]} | {len(ids)} ids | vetor {vetor} | cand {out[-1]["ms_cand"]}ms jev {out[-1]["ms_jev"]}ms')
ok = [o for o in out if "erro" not in o]
com = [o for o in ok if o["esperado"]]; neg = [o for o in ok if not o["esperado"]]
p95 = lambda xs: sorted(xs)[min(len(xs) - 1, int(len(xs) * 0.95))] if xs else None
res = {"n": N, "limiar": LIM, "sem_vetor": "--vec" not in a, "catalogo": "--catalogo" in a, "consultas": len(ok), "erros": len(out) - len(ok),
       "esperados_acendeu": f'{sum(len(o["acendeu"]) for o in com)}/{sum(len(o["esperado"]) for o in com)}',
       "esperados_nos_candidatos": f'{sum(len(o["nos_candidatos"]) for o in com)}/{sum(len(o["esperado"]) for o in com)}',
       "ids_medios_com_esperado": round(statistics.mean(len(o["ids"]) for o in com), 1) if com else None,
       "ids_medios_negativos": round(statistics.mean(len(o["ids"]) for o in neg), 1) if neg else None,
       "p95_ms_jev": p95([o["ms_jev"] for o in ok]), "p95_ms_total": p95([o["ms_cand"] + o["ms_jev"] for o in ok]),
       "custo_medio_usd": round(statistics.mean(o["cost"] for o in ok), 6) if ok else None}
print(json.dumps(res, ensure_ascii=False, indent=1))
o = opt("--out", os.path.expanduser("~/.adas/jit/sombra-medicao.json"))
json.dump({"resumo": res, "consultas": out}, open(o, "w"), ensure_ascii=False, indent=1)
