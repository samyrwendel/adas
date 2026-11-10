"""juiz-conformal.py — P1 (task 20261110-006, DA-700): limiar do juiz-reply por regra, calibrado nos rótulos cegos (DA-699).
Calibração conformal split (só os NEGATIVOS rotulados): limiar_conformal = quantil ⌈(n+1)(1-α)⌉ dos scores das mensagens
que NÃO ferem a regra → P(alarme numa mensagem limpa) ≤ α em dado novo. Score ≤ limiar_conformal = ABSTENÇÃO (o juiz
grava no ledger como `silencioso`, não avisa nem nega). Regra com menos de MIN_NEG negativos = "sem dado" → limiar global
(todos os negativos rotulados das regras que o juiz ainda pergunta — `modo: fora` não entra).
  calibrar [--ligar]  grava em ~/.adas/jit/juiz-gate.json: `_conformal` {ligado, alvo, global} + `limiar_conformal`/`conformal` por regra
            (backup .bak-p1 antes); depois rode `da-cards.py --so-juiz`.
  replay    132 casos: original × DA-699 × DA-699+P1 (in-sample e leave-one-out), tabela em stdout.
  --teste   autoteste do quantil.
Reverter: `"ligado": false` em `_conformal` + `da-cards.py --so-juiz`. Saída só tem número: nenhum trecho de conversa."""
import json, math, os, shutil, sys, importlib.util
H = os.path.expanduser("~"); GATE = f"{H}/.adas/jit/juiz-gate.json"
ALVO = float(os.environ.get("JUIZ_CONFORMAL_ALVO", "0.10")); MIN_NEG = math.ceil((1 - ALVO) / ALVO)  # α=0,10 → 9: menos que isso o quantil não existe

def quantil(neg, a=ALVO):
    k = math.ceil((len(neg) + 1) * (1 - a))
    return None if k > len(neg) else round(sorted(neg)[k - 1], 3)

def dados():
    spec = importlib.util.spec_from_file_location("rm", os.path.join(os.path.dirname(os.path.realpath(__file__)), "juiz-rotulo-modelos.py"))
    rm = importlib.util.module_from_spec(spec); spec.loader.exec_module(rm)
    gab = json.load(open(f"{rm.D}/gabarito-juiz.json"))["casos"]; rot = json.load(open(f"{rm.D}/rotulos.json"))
    ok, _ = rm.consenso(rot, [c["n"] for c in gab])
    return [dict(n=c["n"], regra=c["regra"], score=c["score"], fere=ok[c["n"]], viola=c["veredito_juiz"] == "viola") for c in gab if c["n"] in ok]

def limiares(casos, gate, fora_n=None):
    """→ (global, {regra: q}) sem o caso fora_n (leave-one-out)."""
    neg = [c for c in casos if not c["fere"] and c["n"] != fora_n]
    glob = quantil([c["score"] for c in neg if (gate.get(c["regra"]) or {}).get("modo") != "fora"])
    por = {}
    for r in {c["regra"] for c in neg}:
        s = [c["score"] for c in neg if c["regra"] == r]
        if len(s) >= MIN_NEG: por[r] = quantil(s)
    return glob, por

def calibrar():
    casos = dados(); gate = json.load(open(GATE))
    glob, por = limiares(casos, gate)
    shutil.copy2(GATE, GATE + ".bak-p1")
    gate["_conformal"] = {"ligado": "--ligar" in sys.argv, "alvo": ALVO, "global": glob, "min_neg": MIN_NEG, "n_rotulos": len(casos),
        "doc": "P1 task 20261110-006 (DA-700): score ≤ limiar_conformal (da regra, senão global) = abstenção → só ledger (silencioso). "
               "Quantil conformal dos negativos rotulados (alvo de alarme falso ≤ alvo). Reverter: ligado=false + da-cards.py --so-juiz."}
    for r in {c["regra"] for c in casos}:
        neg = sum(1 for c in casos if c["regra"] == r and not c["fere"])
        g = gate.setdefault(r, {}) if r in por or r in gate else None
        if g is None: continue
        g["limiar_conformal"] = por.get(r, glob)
        g["conformal"] = f"rótulo (n_neg={neg})" if r in por else f"sem dado (n_neg={neg} < {MIN_NEG}) → global"
    tmp = GATE + ".tmp"; json.dump(gate, open(tmp, "w"), ensure_ascii=False, indent=1); os.replace(tmp, GATE)
    print(f"global {glob} · por regra {por} · gate gravado (backup {GATE}.bak-p1)")

def metr(casos, vis):
    tp = sum(1 for c in casos if vis(c) and c["fere"]); fp = sum(1 for c in casos if vis(c) and not c["fere"])
    pos = sum(c["fere"] for c in casos)
    return dict(av=tp + fp, tp=tp, fp=fp, prec=tp / (tp + fp) if tp + fp else None, rec=tp / pos if pos else None)

def replay(saida=True):
    casos = dados(); gate = json.load(open(GATE))
    modo = lambda r: (gate.get(r) or {}).get("modo")
    q = lambda c, loo: (lambda g, p: p.get(c["regra"], g))(*limiares(casos, gate, c["n"] if loo else None))
    colunas = {"original (antes da DA-699)": lambda c: c["viola"],
               "DA-699 (produção hoje)": lambda c: c["viola"] and modo(c["regra"]) not in ("fora", "silencioso"),
               "DA-699 + P1 in-sample": lambda c: c["viola"] and modo(c["regra"]) not in ("fora", "silencioso") and c["score"] > q(c, False),
               "DA-699 + P1 leave-one-out": lambda c: c["viola"] and modo(c["regra"]) not in ("fora", "silencioso") and c["score"] > q(c, True)}
    res = {k: metr(casos, f) for k, f in colunas.items()}
    if saida:
        f = lambda x: "n/d" if x is None else f"{100 * x:.0f}%"
        print(f"{len(casos)} casos rotulados, {sum(c['fere'] for c in casos)} ferem · alvo α={ALVO} · global={limiares(casos, gate)[0]} · por regra={limiares(casos, gate)[1]}")
        for k, m in res.items():
            print(f"  {k:<28} avisos visíveis {m['av']:>3} · VP {m['tp']:>2} FP {m['fp']:>2} · precisão {f(m['prec']):>4} · recall {f(m['rec']):>4}")
        ref = res["DA-699 (produção hoje)"]["av"]
        print(f"  avisos a menos com P1 (vs DA-699): {ref - res['DA-699 + P1 in-sample']['av']} in-sample, {ref - res['DA-699 + P1 leave-one-out']['av']} LOO")
        print("  por regra (DA-699 → P1 LOO): " + " · ".join(
            f"{r} {metr(cs, colunas['DA-699 (produção hoje)'])['tp']}/{metr(cs, colunas['DA-699 (produção hoje)'])['av']}→"
            f"{metr(cs, colunas['DA-699 + P1 leave-one-out'])['tp']}/{metr(cs, colunas['DA-699 + P1 leave-one-out'])['av']}"
            for r in sorted({c['regra'] for c in casos}) for cs in [[c for c in casos if c['regra'] == r]]
            if metr(cs, colunas['original (antes da DA-699)'])['av']) + "  (VP/avisos)")
    return res

def _teste():
    assert MIN_NEG == 9 or ALVO != 0.10
    assert quantil([0.1] * 8) is None                      # n=8 < 9: não existe quantil 90% conformal
    assert quantil([i / 10 for i in range(1, 10)]) == 0.9  # n=9 → k=9 → o maior
    assert quantil([i / 100 for i in range(1, 20)]) == 0.18  # n=19 → k=18
    print("teste ok")

if __name__ == "__main__":
    {"calibrar": calibrar, "replay": replay, "--teste": _teste}[sys.argv[1]]()
