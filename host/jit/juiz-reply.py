#!/usr/bin/env python3
"""juiz-reply.py — PreToolUse (matcher: mcp__plugin_telegram_telegram__reply). ADAS-JIT F3, nível 3 do
mainbot (DA-468). Juiz de FORMA: a rubrica NÃO mora aqui, é compilada pelo da-cards.py a partir dos
cartões com `**Gatilho:** forma · reply · juiz` (~/.adas/jit/juiz-reply.json). DA nova com esse gatilho =
pergunta nova, sem tocar neste arquivo.

Ordem: 1) os guards determinísticos dos cartões `forma · reply · hook=` (copiar-guard…) rodam ANTES, com o
mesmo payload; se algum nega, o juiz REPASSA a negação e para (sem custo de LLM). É o único lugar onde o
guard roda no reply (task 20261031-031: registro standalone removido do settings). 2) cache por
hash (texto + rubrica). 3) provedores do juiz_prov.py, na ordem configurada: Jev (systemone, perguntas `noul`)
direto na TypeSafe, pela OpenRouter, pela ExperientialLabs ou pelo Vercel Gateway, ou qualquer endpoint OpenAI-compatível
(Ollama local). Pergunta com probabilidade ≥ limiar do cartão = violação.
Saída: cartão em modo `deny` → permissionDecision deny citando DA-NNN + Regra + conserto; modo `aviso`
(rótulo ainda não aprovado, ou reprovado no replay) → additionalContext (a mensagem sai).

FAIL-OPEN: erro, timeout (4 s no total), teto diário, rubrica ausente → exit 0 sem saída. Bot mudo é pior
que bot errado. Ledger: ~/.claude/bus/juiz-reply.log (uma linha JSON por chamada).
Chave: juiz_prov.py (env → ~/.adas/juiz.env → ADAS_JUIZ_ENVFILE → cofre ADAS_JUIZ_CRED); sem chave = juiz desligado,
e o SessionStart avisa. Nível: ADAS_JIT_NIVEL (fixo) → ~/.adas/jit/nivel.fixo → ~/.adas/jit/nivel (termostato) → 3;
abaixo de 3 o hook não faz nada. Env: JUIZ_REPLY_RUBRICA, JUIZ_REPLY_TETO (chamadas/dia, default 600), JUIZ_REPLY_TIMEOUT (s, default 4),
JUIZ_REPLY_LEDGER, JUIZ_REPLY_CACHE (testes apontam pra /tmp).
"""
import hashlib, json, os, re, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))  # juiz_prov.py mora ao lado (hook instalado = symlink)
import juiz_prov  # noqa: E402

H = os.path.expanduser("~")
RUBRICA = os.environ.get("JUIZ_REPLY_RUBRICA", f"{H}/.adas/jit/juiz-reply.json")
LEDGER = os.environ.get("JUIZ_REPLY_LEDGER", f"{H}/.claude/bus/juiz-reply.log")
CACHE = os.environ.get("JUIZ_REPLY_CACHE", f"{H}/.adas/jit/juiz-cache.json")
TETO = int(os.environ.get("JUIZ_REPLY_TETO", "600"))
TIMEOUT = float(os.environ.get("JUIZ_REPLY_TIMEOUT", "4"))
MAX_TEXTO = 4000


def perguntar(texto, cartoes, prazo, fmt=None):
    """Uma chamada, todas as perguntas, pelos provedores do juiz_prov (ordem configurada, fail-over)."""
    return juiz_prov.perguntar(texto[:MAX_TEXTO], cartoes, prazo, fmt)


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


def padrao_default(texto):
    """Determinístico, qualquer nível (DA-482, task 20261101-007): o reply casa a reação DEFAULT que uma regra substitui
    (`resposta=/re/` do campo Padrão sem ADAS, no cards.json) e o diário não foi escrito nos últimos 15 min → aviso.
    ponytail: janela fixa de 15 min no lugar da marca de turno do Hermes; o reply do Telegram fecha o turno do dono."""
    try:
        cards = json.load(open(os.path.join(os.environ.get("ADAS_JIT_DIR") or f"{H}/.adas/jit", "cards.json")))
        dmt = max(os.path.getmtime(f"{H}/{f}") for f in ("DECISIONS.md", "CONDUCT.md") if os.path.exists(f"{H}/{f}"))
    except Exception:
        return None
    if time.time() - dmt < 900:
        return None
    hits, RESP = [], r"resposta=/(.*?)/(?=\s|$)"
    for c in cards:
        m = re.search(RESP, c.get("padrao_sem_adas") or "")
        try:
            if m and re.search(m.group(1), texto, re.I):
                hits.append(c)
        except re.error:
            continue
    if not hits:
        return None
    return ("Este reply faz o que o modelo faz SEM ADAS: " + " | ".join(
        c["id"] + ": " + re.sub(RESP, "", c["padrao_sem_adas"]).strip()[:160] for c in hits)
        + " — o diário (DECISIONS.md/CONDUCT.md) NÃO foi escrito: registre a DA/DC (da-new.sh) antes de mandar e cite o ID.")


def main():
    raw = sys.stdin.read()
    p = json.loads(raw)
    ti = p.get("tool_input") or {}
    texto = (ti.get("text") or "").strip()
    if not texto:
        return
    pd = padrao_default(texto)
    def avisa_padrao():
        ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "decisao": "padrao", "len": len(texto), "aviso": pd[:200]})
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": pd}}, ensure_ascii=False))
    if juiz_prov.nivel() < 3:
        return avisa_padrao() if pd else None
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
    if pd:  # depois dos guards (deny vence); o juiz roda de novo no reply corrigido
        return avisa_padrao()
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


# Afirmação de AUSÊNCIA sem prova (DA-544, task 20261109-011): o Jev deu 0,45 a "eu não tenho acesso de leitura lá"
# (msg 13135, sem ter tentado sudo) e baixar o limiar pra 0,45 marcaria 47% dos replies (48/102 em 48h). Regex por
# FRASE: ausência no presente sem comando, caminho, código HTTP ou ressalva ("não conferi") na mesma frase → aviso.
# Medido em 1039 replies (28/10–09/11): 18 hits (1,7%), ~1 conceitual. "conferi agora" sozinho NÃO é prova (msg 13122).
AUS = re.compile(r"\bn[ãa]o\s+(?:tenho|temos|h[áa])\s+(?:\w+\s+){0,2}?(?:acesso|chave|conta|permiss[ãa]o|credencial|token|senha|login|sudo|cadastr\w*)"
                 r"|\bn[ãa]o\s+tem\s+(?:\w+\s+){0,2}?(?:acesso|chave|credencial|token|senha|login|sudo|permiss[ãa]o)"
                 r"|(?<!ainda )\bn[ãa]o\s+exist(?:e|em)\s+(?:mais|(?:no|na|nos|nas)\s+(?:servidor|cofre|repo|c[óo]digo|disco|sistema|pasta|banco|container)"
                 r"|(?:o\s+|a\s+|um\s+|uma\s+)?(?:repo|arquivo|pasta|chave|token|endpoint|servi[çc]o|unit|timer|cron|tabela|conta|credencial|script|hook)\b)"
                 r"|\bsem\s+acesso|\bn[ãa]o\s+consigo\s+(?:acessar|ler|entrar|logar)|\bn[ãa]o\s+est[áa]\s+(?:no\s+cofre|cadastrad\w*|instalad\w*)", re.I)
PROVA = re.compile(r"`|\b(?:ssh|sudo|ls|grep|find|cat|curl|systemctl|journalctl|get-credential\S*|bw|git|ps|pgrep|stat|which|docker|pm2)\b"
                   r"|(?:^|\s)[~/][\w.@-]+/|\.env\b|\b[1-5]\d\d\b|permission denied|n[ãa]o\s+(?:conferi|testei|verifiquei|chequei|olhei|vi)\b", re.I)
RELATO = re.compile(r"\b(?:disse|dizer|dizia|dizendo|falei|afirmar|afirmei|escrevi|achava)\s+que\b|\berrei\b|[\"“«]", re.I)


def ausencia_sem_prova(texto):
    hits = []
    for f in re.split(r"(?<=[.!?;])\s+|\n+", texto):
        m = AUS.search(f)
        if m and not PROVA.search(f) and not RELATO.search(f[:m.start()]):
            hits.append(f.strip()[:140])
    return hits


def com_ausencia(out, texto):
    """Junta o aviso de ausência à saída do main: deny fica como está (o reply reescrito passa de novo aqui)."""
    try:
        hits = ausencia_sem_prova(texto)
    except Exception:
        return out
    if not hits or '"deny"' in out:
        return out
    ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "decisao": "ausencia", "len": len(texto), "frases": hits})
    av = ("DA-544 (afirmação de ausência sem prova): " + " | ".join(f"«{h}»" for h in hits)
          + " — Regra: afirmar que algo não existe ou que não há acesso exige o comando que mostrou isso agora"
          " (ssh direto, sudo -n, aliases do ~/.ssh/config, cofre E .env do projeto). Conserto: cite o comando"
          " e a saída, ou escreva 'não conferi'; se errou, corrija na próxima mensagem.")
    try:
        o = json.loads(out) if out.strip() else None
    except ValueError:
        return out
    if o and "additionalContext" in (o.get("hookSpecificOutput") or {}):
        o["hookSpecificOutput"]["additionalContext"] += " | ⚠️ " + av
    elif o:
        return out
    else:
        o = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "⚠️ JUIZ-REPLY (aviso, a mensagem JÁ SAIU): " + av}}
    return json.dumps(o, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    import io
    raw_in = sys.stdin.read()
    sys.stdin, real_out, sys.stdout = io.StringIO(raw_in), sys.stdout, io.StringIO()
    try:
        main()
    except Exception:
        pass
    out, sys.stdout = sys.stdout.getvalue(), real_out
    try:
        out = com_ausencia(out, ((json.loads(raw_in).get("tool_input") or {}).get("text") or "").strip())
    except Exception:
        pass
    sys.stdout.write(out)
    sys.exit(0)
