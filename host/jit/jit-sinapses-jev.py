#!/usr/bin/env python3
"""jit-sinapses-jev.py — OFFLINE (task 20261107-016, A): o Jev propõe as arestas 'depende-de' / 'complementa' entre DAs.
Grava num grafo-jev.json SEPARADO (nunca toca o grafo.json). Custo medido e com TETO.
  jit-sinapses-jev.py [--fonte servidor|rampa-pix|nest-egg|tradingagents|orcamento-estudio|todas] [--limit N]
                      [--teto-usd 0.30] [--limiar 0.6] [--vizinhos 8] [--out ~/.adas/jit/grafo-jev.json]
Candidatos por DA = vizinhos de PALAVRA (soma de idf dos termos que dividem), dentro da mesma fonte; sem vetor/Ollama.
Uma chamada ao Jev por DA (2 perguntas por vizinho). Retoma do que já está no --out (não repete DA já julgada)."""
import json, math, os, re, sys, time, collections

D = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, D)
import juiz_prov

HOME = os.path.expanduser("~")
FONTES = {"rampa-pix": f"{HOME}/rampa-pix/DECISIONS.md", "nest-egg": "/opt/projects/nest-egg/DECISIONS.md",
          "tradingagents": f"{HOME}/tradingagents/DECISIONS.md", "orcamento-estudio": f"{HOME}/orcamento-estudio/DECISIONS.md"}
a = sys.argv[1:]
def opt(n, d, t=str): return t(a[a.index(n) + 1]) if n in a else d
fonte, LIMIT, TETO, LIM, VIZ = opt("--fonte", "todas"), opt("--limit", 0, int), opt("--teto-usd", 0.30, float), opt("--limiar", 0.6, float), opt("--vizinhos", 8, int)
OUT = opt("--out", os.path.expanduser("~/.adas/jit/grafo-jev.json"))


def nos_servidor():
    cs = json.load(open(os.path.expanduser("~/.adas/jit/cards.json")))
    return [{"id": c["id"], "titulo": c["titulo"], "curta": c.get("regra_curta") or ""} for c in cs]


def nos_projeto(nome):
    """'## DA-NNN — título' + 400 chars do corpo. Id vira 'nome:DA-NNN' (os diários repetem a numeração do servidor)."""
    txt = open(FONTES[nome], encoding="utf-8").read()
    out = []
    for m in re.finditer(r"^## (D[AS]-\d+) — (.+?)\n(.*?)(?=^## |\Z)", txt, re.S | re.M):
        if "<Título" in m.group(2): continue
        out.append({"id": f"{nome}:{m.group(1)}", "titulo": m.group(2).strip(), "curta": re.sub(r"\s+", " ", m.group(3)).strip()[:400]})
    return out


def vizinhos(nos, k):
    tok = lambda n: set(re.findall(r"\w{4,}", (n["titulo"] + " " + n["curta"]).lower()))
    T = {n["id"]: tok(n) for n in nos}
    df = collections.Counter(t for s in T.values() for t in s)
    idf = {t: math.log(len(nos) / c) for t, c in df.items()}
    inv = collections.defaultdict(list)
    for i, s in T.items():
        for t in s: inv[t].append(i)
    out = {}
    for i, s in T.items():
        sc = collections.Counter()
        for t in s:
            if len(inv[t]) > len(nos) * 0.25: continue  # termo de hub não liga nada
            for j in inv[t]:
                if j != i: sc[j] += idf[t]
        out[i] = [j for j, _ in sc.most_common(k)]
    return out


def main():
    fontes = ["servidor"] + list(FONTES) if fonte == "todas" else [fonte]
    try: sal = json.load(open(OUT))
    except Exception: sal = {"feitos": [], "arestas": [], "custo_usd": 0.0, "chamadas": 0, "ms": []}
    feitos = set(sal["feitos"])
    if not juiz_prov.provedores(rede=False): sys.exit("sem provedor do Jev")
    for f in fontes:
        nos = nos_servidor() if f == "servidor" else nos_projeto(f)
        por = {n["id"]: n for n in nos}
        viz = vizinhos(nos, VIZ)
        n_f = 0
        for n in nos:
            if n["id"] in feitos or not viz[n["id"]]: continue
            if LIMIT and n_f >= LIMIT: break
            if sal["custo_usd"] >= TETO: print("TETO atingido", sal["custo_usd"]); break
            perg = []
            for j in viz[n["id"]]:
                v = por[j]
                perg.append({"id": j + "|depende", "pergunta": f'A regra {n["id"]} DEPENDE da regra {j} ("{v["titulo"][:110]}"): sem {j} ela não se aplica direito ou perde o sentido?'})
                perg.append({"id": j + "|complementa", "pergunta": f'A regra {j} ("{v["titulo"][:110]}") COMPLEMENTA {n["id"]}: quem aplica {n["id"]} deveria lembrar também de {j} (limite, exceção, quem executa)? NÃO se só tratam de assunto parecido.'})
            t0 = time.time()
            try:
                resp, m = juiz_prov.perguntar(f'{n["id"]} — {n["titulo"]}. {n["curta"][:500]}', perg, time.time() + 30)
            except Exception as e:
                print("erro", n["id"], str(e)[:60]); continue
            for k, p in resp.items():
                j, tipo = k.split("|")
                if p >= LIM: sal["arestas"].append({"a": n["id"], "b": j, "w": round(p, 2), "tipo": "depende-de" if tipo == "depende" else "complementa", "classe": "jev"})
            sal["feitos"].append(n["id"]); sal["chamadas"] += 1; sal["custo_usd"] = round(sal["custo_usd"] + (m.get("cost") or 0), 6)
            sal["ms"].append(round((time.time() - t0) * 1000)); n_f += 1
            if n_f % 20 == 0: json.dump(sal, open(OUT, "w"), ensure_ascii=False)
        print(f, n_f, "DAs julgadas")
    ms = sorted(sal["ms"])
    sal["resumo"] = {"chamadas": sal["chamadas"], "arestas": len(sal["arestas"]), "custo_usd": sal["custo_usd"], "custo_por_da": round(sal["custo_usd"] / max(1, sal["chamadas"]), 6),
                     "p95_ms": ms[int(len(ms) * 0.95)] if ms else None, "limiar": LIM, "teto_usd": TETO}
    json.dump(sal, open(OUT, "w"), ensure_ascii=False)
    print(json.dumps(sal["resumo"], ensure_ascii=False))


if __name__ == "__main__":
    main()
