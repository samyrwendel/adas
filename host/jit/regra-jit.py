#!/usr/bin/env python3
"""regra-jit.py — ADAS-JIT F1: a regra certa chega no INSTANTE da ação (DA-468; proposta do seniorbot,
task 20261031-013 §5.3). Um hook, adaptadores por superfície, detectada pelo payload:

  UserPromptSubmit            → prompt  (só mensagem do dono via <channel> do Telegram, ou prompt de sessão
                                         interativa; worker headless e alerta de bot "[...]" ficam de fora)
  PreToolUse Bash             → bash    (comando)
  PreToolUse Edit|Write|Multi → edit    (file_path + 2k do conteúdo)
  PostToolBatch               → par     (adesão: cartão mostrado × ação seguinte, só ledger)

Motores, nesta ordem (k≤3 no total, silêncio é o default):
  1. EVENTO — cartões com `**Gatilho:** evento · <superfície> · quando=/re/ [salvo=/re/] [conserto="…"]`
     (compilados em ~/.adas/jit/gatilhos.json pelo da-cards.py). Regex no comando (bash), no caminho
     (edit) ou no corpo (prompt). ms, 0 token.
  2. TEMA — busca híbrida no índice de cartões (regra-search), com limiar POR SUPERFÍCIE (medido na F0 e
     na calibração desta task sobre 400 Bash + 79 Edit reais):
        prompt: L2 ≤ 0,65, ou bm25 ≤ -25 só se o corpo < 300 chars (bm25 é absoluto e infla com o tamanho)
        bash:   DESLIGADO por padrão (ADAS_JIT_BASH_VEC=1 liga: L2 ≤ 0,65 e comando > 8 palavras). Medido em
                135 comandos reais: léxico dispara em 60–90% (ruído); vetor custa ~1 s/comando em CPU e
                disparou 3/135, todos autorreferentes; o positivo do nanogo ficou em L2 0,74. Bash = evento.
        edit:   L2 ≤ 0,60; ledgers (DECISIONS*/CONDUCT) ficam só com o motor de evento
Saída: additionalContext (nunca bloqueia; deny é papel dos guards `hook=`). Cartão cujo id já está no
payload é omitido (o agente já está nele); cartão já mostrado na sessão nos últimos 60 min também.
Ledger: ~/.claude/bus/regra-jit.log (JSONL: ts, sid, superfície, motor, cartões com l2/bm25, decisão, ms).
Env: ADAS_JIT=off (desliga) | log (sombra: grava o ledger, não injeta). Fail-open em tudo."""
import hashlib, json, os, re, subprocess, sys, time

HOME = os.path.expanduser("~")
D = os.environ.get("ADAS_JIT_DIR") or os.path.join(HOME, ".adas", "jit")
BUS = os.environ.get("ADAS_JIT_BUS") or os.path.join(HOME, ".claude", "bus")
LOG = os.path.join(BUS, "regra-jit.log")
STATE = os.path.join(BUS, "regra-jit")
K = 3
TTL_VISTO = 3600
LIMIAR = {"prompt": {"l2": 0.65, "bm25": -25.0, "bm25_max_chars": 300},
          "bash": {"l2": 0.65, "min_palavras": 8},
          "edit": {"l2": 0.60}}
LEDGERS = re.compile(r"(^|/)(DECISIONS[^/]*|CONDUCT[^/]*|DECISIONS-INDEX)\.md$")
SEGREDO = re.compile(r"[A-Za-z0-9_\-+/=]{28,}")


def red(s, n=160):
    return SEGREDO.sub("«…»", (s or "").replace("\n", " "))[:n]


def ledger(rec):
    try:
        os.makedirs(BUS, exist_ok=True)
        with open(LOG, "a") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError:
        pass


def dono():
    """chat_id do dono pela lib-tg-env.sh (sem literal). None = não dá pra filtrar."""
    if os.environ.get("ADAS_JIT_OWNER"):
        return os.environ["ADAS_JIT_OWNER"]
    lib = os.path.join(HOME, ".claude", "hooks", "lib-tg-env.sh")
    if not os.path.exists(lib):
        return None
    try:
        r = subprocess.run(["bash", "-c", f'. "{lib}"; tg_owner_chat_id'], capture_output=True, text=True, timeout=2)
        return r.stdout.strip() or None
    except Exception:
        return None


def superficie_e_texto(p):
    """→ (superficie, texto_para_busca, alvo_do_predicado) ou (None, …) = inerte."""
    ev = p.get("hook_event_name", "")
    if ev == "UserPromptSubmit":
        pr = p.get("prompt") or ""
        if '<channel source="plugin:telegram' in pr:
            uid = re.search(r'user_id="(-?\d+)"', pr)
            own = dono()
            if own and uid and uid.group(1) != own:
                return None, "", ""
            m = re.search(r"<channel[^>]*>(.*?)(</channel>|$)", pr, re.S)
            body = (m.group(1) if m else pr).strip()
        elif os.environ.get("AXON_HEADLESS") or pr.lstrip().startswith(("[", "<")):
            return None, "", ""
        else:
            body = pr.strip()
        return "prompt", body[:2000], body[:2000]
    if ev == "PreToolUse":
        tn, ti = p.get("tool_name", ""), p.get("tool_input") or {}
        if tn == "Bash":
            c = ti.get("command") or ""
            return "bash", c[:2000], c
        if tn in ("Edit", "Write", "MultiEdit"):
            fp = ti.get("file_path") or ""
            body = ti.get("new_string") or ti.get("content") or "\n".join(
                e.get("new_string", "") for e in ti.get("edits") or [])
            return "edit", (fp + "\n" + body)[:2000], fp
    if ev == "PostToolBatch":
        return "par", "", ""
    return None, "", ""


def rx(v):
    v = (v or "").strip()
    if len(v) >= 2 and v[0] == "/" and v.rfind("/") > 0:
        v = v[1:v.rfind("/")]
    return re.compile(v, re.I) if v else None


def motor_evento(sup, alvo):
    try:
        gs = json.load(open(os.path.join(D, "gatilhos.json")))
    except Exception:
        return []
    out = []
    for g in gs:
        gt = g.get("gatilho") or {}
        if gt.get("superficie") != sup or not gt.get("quando") or gt.get("hook"):
            continue
        try:
            q, s = rx(gt["quando"]), rx(gt.get("salvo"))
            if q and q.search(alvo) and not (s and s.search(alvo)):
                out.append({"id": g["id"], "regra_curta": g["regra_curta"], "motor": "evento",
                            "conserto": gt.get("conserto")})
        except re.error:
            continue
    return out


def motor_tema(sup, texto, alvo):
    lim = LIMIAR[sup]
    if sup == "edit" and LEDGERS.search(alvo):
        return [], 0
    if sup == "bash" and (os.environ.get("ADAS_JIT_BASH_VEC") != "1" or len(texto.split()) <= lim.get("min_palavras", 0)):
        return [], 0
    os.environ.setdefault("ADAS_EMBED_TIMEOUT", "1.5")
    import importlib.machinery, importlib.util
    ld = importlib.machinery.SourceFileLoader("regra_search", os.path.join(D, "regra-search"))
    m = importlib.util.module_from_spec(importlib.util.spec_from_loader("regra_search", ld))
    ld.exec_module(m)
    idx = m.Index(vec=True)
    res = idx.search(texto, n=8)
    bm_ok = "bm25" in lim and len(texto) < lim.get("bm25_max_chars", 0)
    out = []
    for r in res:
        via = None
        if r["l2"] is not None and r["l2"] <= lim["l2"]:
            via = "vetor"
        elif bm_ok and r["bm25"] is not None and r["bm25"] <= lim["bm25"]:
            via = "lexical"
        if via:
            out.append({"id": r["id"], "regra_curta": r["regra_curta"], "motor": via, "l2": r["l2"], "bm25": r["bm25"]})
    return out, (2 if idx.vec else 1)


def vistos(sid):
    p = os.path.join(STATE, re.sub(r"[^\w-]", "_", sid or "nosid") + ".seen")
    now = time.time()
    try:
        d = {k: v for k, v in json.load(open(p)).items() if now - v < TTL_VISTO}
    except Exception:
        d = {}
    return p, d


def salvar(p, d):
    try:
        os.makedirs(STATE, exist_ok=True)
        tmp = p + ".tmp"
        json.dump(d, open(tmp, "w")); os.replace(tmp, p)
    except OSError:
        pass


def par(p, sid):
    """PostToolBatch: fecha o par 'cartão mostrado' × 'ação seguinte' (adesão no ledger)."""
    pend = os.path.join(STATE, re.sub(r"[^\w-]", "_", sid or "nosid") + ".pend")
    try:
        mostrado = json.load(open(pend))
    except Exception:
        return
    if not mostrado.get("armado"):  # o lote que MOSTROU o cartão fecha agora; o par é com o PRÓXIMO lote
        mostrado["armado"] = True
        try:
            json.dump(mostrado, open(pend, "w"))
        except OSError:
            pass
        return
    try:
        os.remove(pend)
    except OSError:
        pass
    lote = re.sub(r"📌 ADAS-JIT[^\"]*", "", json.dumps(p, ensure_ascii=False))  # o texto injetado não conta como leitura
    leu = [c for c in mostrado["cartoes"] if re.search(r"\b%s\b" % re.escape(c), lote)]
    ferr = sorted(set(re.findall(r'"tool_name":\s*"([^"]+)"', lote)))
    ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "sid": sid, "superficie": "par",
            "mostrado_em": mostrado.get("superficie"), "cartoes": mostrado["cartoes"], "leu_da": leu,
            "ferramentas": ferr[:6], "atraso_s": round(time.time() - mostrado.get("t", time.time()), 1)})


def main():
    if os.environ.get("ADAS_JIT", "inline") == "off":
        return
    t0 = time.time()
    try:
        p = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    sid = p.get("session_id") or ""
    sup, texto, alvo = superficie_e_texto(p)
    if sup == "par":
        return par(p, sid)
    if not sup or not texto.strip() or not os.path.exists(os.path.join(D, "regras.db")):
        return
    cards = motor_evento(sup, alvo)
    nivel = 0
    if len(cards) < K:
        try:
            tema, nivel = motor_tema(sup, texto, alvo)
        except Exception:
            tema = []
        cards += [c for c in tema if c["id"] not in {x["id"] for x in cards}]
    vp, vd = vistos(sid)
    now = time.time()
    mostrar, omitidos = [], []
    for c in cards:
        if re.search(r"\b%s\b" % re.escape(c["id"]), texto):
            omitidos.append((c["id"], "no_payload")); continue
        if c["id"] in vd:
            omitidos.append((c["id"], "visto")); continue
        mostrar.append(c)
        if len(mostrar) == K:
            break
    modo = os.environ.get("ADAS_JIT", "inline")
    decisao = ("inline" if modo != "log" else "sombra") if mostrar else "silencio"
    ms = round((time.time() - t0) * 1000)
    if cards or sup == "prompt":
        ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "sid": sid, "superficie": sup, "nivel": nivel,
                "decisao": decisao, "ms": ms, "payload": red(texto),
                "cartoes": [{k: c.get(k) for k in ("id", "motor", "l2", "bm25")} for c in mostrar],
                "omitidos": omitidos})
    elif ms > 300:
        ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "sid": sid, "superficie": sup, "nivel": nivel,
                "decisao": "silencio", "ms": ms})
    if not mostrar or modo == "log":
        return
    for c in mostrar:
        vd[c["id"]] = now
    salvar(vp, vd)
    try:  # acumula até o próximo PostToolBatch (mais de uma ação pode mostrar cartão no mesmo lote)
        pp = os.path.join(STATE, re.sub(r"[^\w-]", "_", sid or "nosid") + ".pend")
        try:
            prev = json.load(open(pp))
        except Exception:
            prev = {"cartoes": [], "superficie": sup, "t": now}
        prev["cartoes"] += [c["id"] for c in mostrar if c["id"] not in prev["cartoes"]]
        prev["armado"] = False  # cartão novo neste lote: o par espera o próximo
        json.dump(prev, open(pp, "w"))
    except OSError:
        pass
    linhas = ["📌 ADAS-JIT — regra(s) do diário que tocam ESTA ação (não bloqueia; confira antes de seguir):"]
    for c in mostrar:
        l = f'• {c["id"]} — {c["regra_curta"]}'
        if c.get("conserto"):
            l += f'  ⇒ {c["conserto"]}'
        linhas.append(l + f'  → bash ~/scripts/da-index.sh show {c["id"]} ~')
    ev = "UserPromptSubmit" if sup == "prompt" else "PreToolUse"
    print(json.dumps({"hookSpecificOutput": {"hookEventName": ev, "additionalContext": "\n".join(linhas)}},
                     ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
