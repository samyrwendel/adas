#!/usr/bin/env python3
"""adas-jit-stats.py — métricas do ADAS-JIT a partir dos ledgers (F4/§5.5 da proposta; task 20261031-031).
Lido pelo governance-audit.sh (domingo) e pela revisão semanal (skill-review-dados.py). Só leitura, stdlib.

  regra-jit.log  disparos por superfície, silêncio, vetor degradado (≠ ok), cartões mais mostrados,
                 adesão do par (aplicou/ignorou/n/a — só cartão com `viola=` no Gatilho mede de verdade)
  juiz-reply.log chamadas, deny/aviso/guard/erro/teto, custo, p95
  gatilhos faltantes: DA normativa vigente NOVA (> --desde, padrão DA-474, a classificação em lote) sem
                 **Gatilho:** — é o que a revisão propõe gatilho (check 13 lista o resto).
Uso: adas-jit-stats.py [--dias 7] [--desde DA-474] [--home DIR]"""
import collections, datetime, json, os, re, subprocess, sys

a = sys.argv[1:]
opt = lambda n, d: a[a.index(n) + 1] if n in a else d
H = opt("--home", os.path.expanduser("~"))
DIAS = int(opt("--dias", "7"))
DESDE = int(re.sub(r"\D", "", opt("--desde", "DA-474")))
BUS = os.environ.get("ADAS_JIT_BUS") or os.path.join(H, ".claude", "bus")
corte = (datetime.datetime.now() - datetime.timedelta(days=DIAS)).strftime("%Y-%m-%dT%H:%M:%S")


def linhas(p):
    try:
        for l in open(p, encoding="utf-8"):
            try:
                d = json.loads(l)
            except ValueError:
                continue
            if d.get("ts", "") >= corte:
                yield d
    except OSError:
        return


def p95(xs):
    xs = sorted(xs)
    return xs[max(0, int(len(xs) * 0.95) - 1)] if xs else None


sup, dec, vet, cart, ades = (collections.Counter() for _ in range(5)); ms = []
for d in linhas(os.path.join(BUS, "regra-jit.log")):
    if d.get("superficie") == "par":
        for c, v in (d.get("adesao") or {}).items():
            ades[v] += 1
        continue
    sup[d.get("superficie")] += 1
    dec[d.get("decisao")] += 1
    if d.get("vetor") not in (None, "ok", "-"):
        vet[d["vetor"]] += 1
    for c in d.get("cartoes") or []:
        cart[c.get("id")] += 1
    if d.get("ms") is not None:
        ms.append(d["ms"])
print(f"## ADAS-JIT — últimos {DIAS} dias")
print(f"regra-jit: {sum(sup.values())} avaliações " + " · ".join(f"{k} {v}" for k, v in sup.most_common())
      + f" | decisão: " + " · ".join(f"{k} {v}" for k, v in dec.most_common()) + f" | p95 {p95(ms)} ms")
print("vetor degradado (embed falhou, caiu pra FTS): " + (" · ".join(f"{k} {v}" for k, v in vet.most_common()) or "nenhum"))
print("cartões mais mostrados: " + (", ".join(f"{k}×{v}" for k, v in cart.most_common(8)) or "nenhum"))
print("adesão (par cartão × ação seguinte): " + (" · ".join(f"{k} {v}" for k, v in ades.most_common()) or "sem par")
      + " — 'ignorou' só existe em cartão com viola=")

try:  # sinapses por espécie (GLOSSARIO.md): explícita · pertencimento · semântica · aprendida
    gr = json.load(open(os.path.join(os.path.expanduser("~"), ".adas", "jit", "grafo.json")))
    cl = collections.Counter(e.get("classe", "?") for e in gr)
    print(f"sinapses (grafo.json): {len(gr)} · " + " · ".join(f"{k} {v}" for k, v in cl.most_common()))
except (OSError, ValueError):
    print("sinapses: grafo.json indisponível")

jd, jms, custo = collections.Counter(), [], 0.0
for d in linhas(os.path.join(BUS, "juiz-reply.log")):
    jd[d.get("decisao", "?")] += 1
    custo += d.get("cost") or 0
    if d.get("ms") is not None:
        jms.append(d["ms"])
print(f"juiz-reply: {sum(jd.values())} replies · " + " · ".join(f"{k} {v}" for k, v in jd.most_common())
      + f" · custo US${custo:.4f} · p95 {p95(jms)} ms")

try:
    r = subprocess.run([sys.executable, os.path.join(H, "scripts", "check-da-gatilho.py"), "--list", H],
                       capture_output=True, text=True, timeout=60).stdout
    novas = [l for l in r.splitlines() if "degrau=doc" in l and int(re.search(r"DA-(\d+)", l).group(1)) > DESDE]
    print(f"gatilhos faltantes (DA normativa > DA-{DESDE:03d} sem **Gatilho:**): " + (len(novas) and "" or "nenhuma"))
    for l in novas:
        print("  " + l.replace("WARN ", ""))
    print("  " + (r.strip().splitlines() or ["check 13 indisponível"])[-1])
except Exception as e:
    print(f"gatilhos faltantes: check 13 falhou ({type(e).__name__})")
