#!/usr/bin/env python3
"""juiz-reply.py — PreToolUse (matcher: mcp__plugin_telegram_telegram__reply). ADAS-JIT F3, nível 3 do
mainbot (DA-468). Juiz de FORMA: a rubrica NÃO mora aqui, é compilada pelo da-cards.py a partir dos
cartões com `**Gatilho:** forma · reply · juiz` (~/.adas/jit/juiz-reply.json). DA nova com esse gatilho =
pergunta nova, sem tocar neste arquivo.

Ordem: 1) os guards determinísticos dos cartões `forma · reply · hook=` (copiar-guard…) rodam ANTES, com o
mesmo payload; se algum nega, o juiz REPASSA a negação e para (sem custo de LLM). É o único lugar onde o
guard roda no reply (task 20261031-031: registro standalone removido do settings). 2) cache por
hash (texto + rubrica). 3) Jev nativo (systemone, perguntas `noul`) pela OpenRouter; reserva
ExperientialLabs. Pergunta com probabilidade ≥ limiar do cartão = violação.
Saída: cartão em modo `deny` → permissionDecision deny citando DA-NNN + Regra + conserto; modo `aviso`
(rótulo ainda não aprovado, ou reprovado no replay) → additionalContext (a mensagem sai).

FAIL-OPEN: erro, timeout (4 s no total), teto diário, rubrica ausente → exit 0 sem saída. Bot mudo é pior
que bot errado. Ledger: ~/.claude/bus/juiz-reply.log (uma linha JSON por chamada).
Chave: env OPENROUTER_API_KEY / EXPERIENTIALLABS_API_KEY, senão o script JUIZ_REPLY_CRED (`<script> <provedor> value`).
Env: ADAS_JIT_NIVEL (<3 = juiz desligado), JUIZ_REPLY_RUBRICA, JUIZ_REPLY_TETO (chamadas/dia, default 600), JUIZ_REPLY_TIMEOUT (s, default 4),
JUIZ_REPLY_LEDGER, JUIZ_REPLY_CACHE (testes apontam pra /tmp).
"""
import hashlib, json, os, subprocess, sys, time, urllib.request

H = os.path.expanduser("~")
RUBRICA = os.environ.get("JUIZ_REPLY_RUBRICA", f"{H}/.adas/jit/juiz-reply.json")
LEDGER = os.environ.get("JUIZ_REPLY_LEDGER", f"{H}/.claude/bus/juiz-reply.log")
CACHE = os.environ.get("JUIZ_REPLY_CACHE", f"{H}/.adas/jit/juiz-cache.json")
TETO = int(os.environ.get("JUIZ_REPLY_TETO", "600"))
TIMEOUT = float(os.environ.get("JUIZ_REPLY_TIMEOUT", "4"))
CRED = os.environ.get("JUIZ_REPLY_CRED", f"{H}/claude-tg-tmux/scripts/get-credential.sh")
NIVEL = os.environ.get("ADAS_JIT_NIVEL", "3")  # DA-468: o juiz é o nível 3; abaixo dele o hook não faz nada
PROVEDORES = [("openrouter", "https://openrouter.ai/api/v1/systemone"),
              ("experientiallabs", "https://api.experientiallabs.ai/v1/systemone")]
MAX_TEXTO = 4000


ENV_CHAVE = {"openrouter": "OPENROUTER_API_KEY", "experientiallabs": "EXPERIENTIALLABS_API_KEY"}


def chave(prov):
    """Chave do provedor: env (OPENROUTER_API_KEY / EXPERIENTIALLABS_API_KEY) ou o cofre da instância
    (JUIZ_REPLY_CRED: script `<cred> <provedor> value`). Sem chave → exceção → fail-open."""
    if os.environ.get(ENV_CHAVE.get(prov, "")):
        return os.environ[ENV_CHAVE[prov]]
    if not os.path.exists(CRED):
        raise RuntimeError(f"sem chave para {prov}")
    r = subprocess.run(["bash", CRED, prov, "value"], capture_output=True, text=True, timeout=2)
    return r.stdout.strip()


def perguntar(texto, cartoes, prazo, fmt=None):
    """Uma chamada, todas as perguntas. Devolve (respostas{id: p}, meta) ou levanta exceção."""
    q = {c["id"]: {"type": "noul", "instructions": c["pergunta"]} for c in cartoes}
    corpo = json.dumps({"model": "jev-latest", "state": {"mensagem": texto[:MAX_TEXTO], "formato": (fmt or "text")}, "questions": q}).encode()
    erro = None
    for prov, url in PROVEDORES:
        resta = prazo - time.time()
        if resta < 0.3:
            break
        try:
            req = urllib.request.Request(url, data=corpo, headers={
                "Authorization": "Bearer " + chave(prov), "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=resta) as r:
                d = json.loads(r.read())
            resp = {k: float(v.get("noul")) for k, v in (d.get("answers") or {}).items() if v.get("noul") is not None}
            if not resp:
                raise ValueError("sem answers")
            return resp, {"prov": prov, "model": d.get("model"), "cost": (d.get("usage") or {}).get("cost")}
        except Exception as e:  # tenta a reserva
            erro = f"{prov}: {type(e).__name__}: {str(e)[:80]}"
    raise RuntimeError(erro or "sem tempo")


def ledger(reg):
    try:
        with open(LEDGER, "a") as f:
            f.write(json.dumps(reg, ensure_ascii=False) + "\n")
    except Exception:
        pass


def chamadas_hoje():
    hoje = time.strftime("%Y-%m-%d")
    n = 0
    try:
        with open(LEDGER) as f:
            for l in f:
                if l.startswith('{"ts": "' + hoje) and '"chamou": true' in l:
                    n += 1
    except FileNotFoundError:
        pass
    return n


def guard_nega(hook, payload):
    """→ stdout do guard se ele NEGOU (o juiz repassa a negação), senão None. O guard roda SÓ aqui: o registro
    standalone no settings saiu (rodava 2× por reply, task 20261031-029 §A.2 #5)."""
    try:
        cmd = ["python3", hook] if hook.endswith(".py") else ["bash", hook]
        r = subprocess.run(cmd, input=payload, capture_output=True, text=True, timeout=3)
        return r.stdout if '"deny"' in r.stdout else None
    except Exception:
        return None


def veredito(resp, cartoes):
    """Cartões violados: probabilidade ≥ limiar do cartão, OU na faixa de aviso [limiar_aviso, limiar) — cartão
    deny com faixa de aviso (DC-037: paráfrase cai em 0,88–0,93; task 20261031-031) avisa sem negar."""
    return [c for c in cartoes if resp.get(c["id"], 0.0) >= min(c.get("limiar", 0.8), c.get("limiar_aviso") or 9)]


def nega_(c, resp):
    return c.get("modo") == "deny" and resp.get(c["id"], 0.0) >= c.get("limiar", 0.8)


def saida(violados, resp):
    nega = [c for c in violados if nega_(c, resp)]
    if nega:
        partes = [f'{c["id"]} (p={resp[c["id"]]:.2f}) — Regra: {c["regra_curta"]} Conserto: {c["conserto"]}' for c in nega]
        return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": "JUIZ-REPLY (ADAS-JIT, DA-468): " + " | ".join(partes)
                + " — reescreva e reenvie."}}
    partes = [f'{c["id"]} (p={resp[c["id"]]:.2f}): {c["regra_curta"]} Conserto: {c["conserto"]}' for c in violados]
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext":
            "⚠️ JUIZ-REPLY (aviso, a mensagem JÁ SAIU): " + " | ".join(partes)}}


def main():
    if NIVEL.isdigit() and int(NIVEL) < 3:
        return
    raw = sys.stdin.read()
    p = json.loads(raw)
    ti = p.get("tool_input") or {}
    texto = (ti.get("text") or "").strip()
    if not texto:
        return
    try:
        rub = json.load(open(RUBRICA))
    except Exception:  # rubrica ausente/corrompida: o juiz cala, mas o guard da DA-412 (deny) não pode calar junto
        rub = {"hooks": [f"{H}/.claude/hooks/copiar-guard.py"]}
    cartoes = rub.get("cartoes") or []
    t0 = time.time()
    h = hashlib.sha256((rub.get("hash", "") + "\0" + str(ti.get("format")) + "\0" + texto).encode()).hexdigest()[:20]
    reg = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "hash": h, "len": len(texto), "chamou": False}
    for g in rub.get("hooks") or []:
        neg = guard_nega(g, raw)
        if neg:
            reg.update(decisao="guard", guard=os.path.basename(g), ms=round((time.time() - t0) * 1000))
            ledger(reg)
            sys.stdout.write(neg if neg.endswith("\n") else neg + "\n")
            return
    if not cartoes:
        return
    try:
        cache = json.load(open(CACHE))
    except Exception:
        cache = {}
    resp = cache.get(h)
    if resp is None:
        if chamadas_hoje() >= TETO:
            reg.update(decisao="teto", ms=round((time.time() - t0) * 1000))
            return ledger(reg)
        reg["chamou"] = True
        try:
            resp, meta = perguntar(texto, cartoes, t0 + TIMEOUT, ti.get("format"))
            reg.update(meta)
        except Exception as e:
            reg.update(decisao="erro", erro=str(e)[:160], ms=round((time.time() - t0) * 1000))
            return ledger(reg)
        cache[h] = resp
        if len(cache) > 3000:
            cache = dict(list(cache.items())[-2000:])
        try:
            tmp = CACHE + ".tmp"
            json.dump(cache, open(tmp, "w"))
            os.replace(tmp, CACHE)
        except Exception:
            pass
    else:
        reg["cache"] = True
    violados = veredito(resp, cartoes)
    reg.update(resp={k: round(v, 3) for k, v in resp.items()}, ms=round((time.time() - t0) * 1000),
               decisao=("deny" if any(nega_(c, resp) for c in violados) else "aviso" if violados else "ok"),
               cartoes=[c["id"] for c in violados])
    ledger(reg)
    if violados:
        print(json.dumps(saida(violados, resp), ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
