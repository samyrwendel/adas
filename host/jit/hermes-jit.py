#!/usr/bin/env python3
"""hermes-jit.py — ADAS-JIT para o Hermes Agent (shell hooks). Um script, dois eventos:

  pre_llm_call   regras PRÓPRIAS do host (DECISIONS.md, DH-NNN) inteiras + até K regras do PADRÃO (padrao.md)
                 escolhidas pela mensagem do usuário (busca por palavra, FTS5/bm25, com limiar; abaixo = silêncio)
                 + o aviso pendente do juiz sobre a resposta ANTERIOR desta sessão. Saída: {"context": "..."}.
  pre_llm_call   + motor de EVENTO: `**Gatilho:** evento · prompt · quando=/re/` do padrão casa a mensagem → o cartão entra
                 mesmo sem palavra em comum; cartão com `**Padrão sem ADAS:**` mostra a reação default que ele substitui.
  post_llm_call  (qualquer nível) a resposta casa o `resposta=/re/` de um Padrão sem ADAS e o diário não foi escrito
                 desde a mensagem → aviso pro próximo turno (determinístico, sem juiz). Task 20261101-007.
  post_llm_call  (nível 3) o juiz (Jev nativo, /systemone) lê a resposta que acabou de sair com as perguntas de
                 forma da rubrica (juiz-reply.json); violação vira linha no ledger e aviso para o próximo turno.
                 O Hermes não tem shell hook ANTES da entrega (transform_llm_output é só plugin Python e só troca
                 texto), então aqui o juiz é sempre AVISO: corrige a próxima mensagem, não segura esta.

Níveis (ADAS_JIT_NIVEL, DA-468): 1 = próprias + busca por palavra; 2 = idem (vetor não roda aqui: sem Ollama no
container; o nível 2 se comporta como 1); 3 = + juiz. Default 3. Fail-open em tudo: erro = sem saída, exit 0.
Arquivos em ADAS_GOV_DIR (default $HERMES_HOME/governanca): DECISIONS.md, padrao.md, juiz-reply.json, jit/ (ledger,
avisos). Juiz: provedores e chave do juiz_prov.py (mesmo módulo do Claude Code; o $HERMES_HOME/.env entra como
ADAS_JUIZ_ENVFILE, ponteiro, a chave não é copiada). Chave colada na conversa (DA-479): o pre_llm_call avisa o modelo
pra NÃO usar, mandar revogar e indicar o caminho seguro (`juiz_prov.py link`).
Env: ADAS_JIT_K (3), ADAS_JIT_BM25 (limiar, -5.0), ADAS_BUDGET_OWN (3500), ADAS_JIT_TETO (chamadas/dia, 300),
ADAS_JIT_TIMEOUT (s, 8)."""
import json, os, re, sqlite3, sys, time

HH = os.environ.get("HERMES_HOME", "/opt/data")
GOV = os.environ.get("ADAS_GOV_DIR", os.path.join(HH, "governanca"))
JD = os.path.join(GOV, "jit")
NIVEL = int(os.environ.get("ADAS_JIT_NIVEL", "3") or 3)
K = int(os.environ.get("ADAS_JIT_K", "3"))
BM25 = float(os.environ.get("ADAS_JIT_BM25", "-5.0"))  # calibrado em 31/10: ruído ≤ |4,1|, acerto ≥ |5,3|
BUDGET_OWN = int(os.environ.get("ADAS_BUDGET_OWN", "3500"))
TETO = int(os.environ.get("ADAS_JIT_TETO", "300"))
TIMEOUT = float(os.environ.get("ADAS_JIT_TIMEOUT", "8"))
os.environ.setdefault("ADAS_JUIZ_ENVFILE", os.path.join(HH, ".env"))
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import juiz_prov  # noqa: E402
# chave/token colado no chat (DA-479): formato de chave de API conhecido, nunca o texto comum
CHAVE_COLADA = re.compile(r"(?<![\w-])(sk-(?:or-v1-|ant-|proj-)?[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|github_pat_\w{30,}"
                          r"|AIza[0-9A-Za-z_-]{30,}|xox[abp]-[\w-]{20,}|AKIA[0-9A-Z]{16}|\d{8,10}:AA[\w-]{30,})")


def regras(arq, pref, extra=None):
    """→ [(id, título, regra)]. extra (dict) recebe, por id, o Gatilho de evento do prompt e o Padrão sem ADAS
    que o sync exporta (task 20261101-007): {"quando": re, "conserto": str, "padrao": str, "resposta": re}."""
    try:
        t = open(os.path.join(GOV, arq), encoding="utf-8").read()
    except OSError:
        return []
    out = []
    for s in re.split(r"(?m)^(?=## " + pref + r"-\d)", t)[1:]:
        h = re.match(r"## (" + pref + r"-\d+[a-z]?) — (.*)", s)
        r = re.search(r"\*\*Regra:\*\*(.*?)(?=\n\*\*|\n`origem|\Z)", s, re.S)
        if h and r:
            out.append((h.group(1), h.group(2).strip(), " ".join(r.group(1).split())))
            if extra is not None:
                e = {}
                g = re.search(r"(?m)^\*\*Gatilho:\*\*\s*evento\s*·\s*([\w,\s]+?)\s*·\s*(.*)$", s)
                if g and "prompt" in g.group(1).replace(" ", "").split(","):
                    e["quando"] = rx(campo_g(g.group(2), "quando"))
                    e["conserto"] = (re.search(r'conserto="([^"]*)"', g.group(2)) or [None, ""])[1]
                ps = re.search(r"(?m)^\*\*Padrão sem ADAS:\*\*(.*)$", s)
                if ps:
                    e["resposta"] = rx(campo_g(ps.group(1), "resposta"))
                    e["padrao"] = re.sub(r"resposta=/.*?/(?=\s|$)", "", ps.group(1)).strip()
                if e:
                    extra[h.group(1)] = e
    return out


def campo_g(spec, k):
    """`k=/re/` de uma linha de Gatilho/Padrão → 're' (sem as barras); '' se não tem."""
    m = re.search(k + r"=/(.*?)/(?=\s·|\s|$)", spec)
    return m.group(1) if m else ""


def rx(v):
    try:
        return re.compile(v, re.I) if v else None
    except re.error:
        return None


def diario_mtime():
    try:
        return os.path.getmtime(os.path.join(GOV, "DECISIONS.md"))
    except OSError:
        return 0.0


def proxima_dh():
    try:
        ns = [int(n) for n in re.findall(r"(?m)^## DH-(\d+)", open(os.path.join(GOV, "DECISIONS.md"), encoding="utf-8").read())]
    except OSError:
        ns = []
    return "DH-%03d" % (max(ns or [0]) + 1)


# palavra comum de conversa não é assunto: sem isto "bom dia, tudo bem?" casava "tudo commitado"
VAZIAS = set("tudo isso essa esse esta este isto aqui agora hoje ontem amanhã como para pela pelo mais menos muito "
             "você voce vocês então entao quando onde qual quais quanto obrigado valeu beleza certo sobre também "
             "tambem depois antes ainda mesmo cada outra outro coisa fazer feito pode poderia seria está estou "
             "estão tenho temos favor".split())


def busca(rs, q):
    """top-K por bm25 (FTS5 em memória) com limiar; bm25 mais NEGATIVO = mais relevante."""
    termos = [t for t in dict.fromkeys(t.lower() for t in re.findall(r"\w{4,}", q or "")) if t not in VAZIAS][:40]
    if not termos or not rs:
        return []
    db = sqlite3.connect(":memory:")
    db.execute("create virtual table d using fts5(id unindexed, txt, tokenize='unicode61 remove_diacritics 2')")
    db.executemany("insert into d values (?, ?)", [(i, f"{t} {r}") for i, t, r in rs])
    fq = " OR ".join('"%s"' % t.replace('"', "") for t in termos)
    try:
        hits = db.execute("select id, bm25(d) from d where d match ? order by bm25(d) limit ?", (fq, K)).fetchall()
    except sqlite3.Error:
        return []
    return [(i, round(b, 2)) for i, b in hits if b <= BM25]


def ledger(rec):
    try:
        os.makedirs(JD, exist_ok=True)
        with open(os.path.join(JD, "jit.log"), "a") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError:
        pass


def aviso_path(sid):
    return os.path.join(JD, "aviso-" + re.sub(r"[^\w-]", "_", sid or "nosid") + ".json")


def turno_path(sid):
    return os.path.join(JD, "turno-" + re.sub(r"[^\w-]", "_", sid or "nosid") + ".json")


def avisar(sid, txt, ts):
    try:
        os.makedirs(JD, exist_ok=True)
        ap = aviso_path(sid)
        try:
            txt = json.load(open(ap)).get("texto", "") + " " + txt
        except (OSError, ValueError):
            pass
        json.dump({"texto": txt.strip(), "ts": ts}, open(ap, "w"), ensure_ascii=False)
    except OSError:
        pass


def padrao_default(p, texto):
    """Determinístico, sem juiz e em qualquer nível (task 20261101-007): a resposta casa a reação DEFAULT que uma regra
    substitui (`resposta=/re/` do Padrão sem ADAS) e o diário NÃO foi escrito desde a mensagem → aviso pro próximo turno.
    ponytail: a isenção é sempre "escreveu no diário" (a única regra com resposta= hoje é a de decisão do dono);
    regra com outro destino ganha `salvo=` próprio quando existir."""
    ext = {}
    regras("padrao.md", "DA", ext)
    viol = [(i, e) for i, e in ext.items() if e.get("resposta") and e["resposta"].search(texto)]
    if not viol:
        return
    try:
        t0 = json.load(open(turno_path(p.get("session_id")))).get("t", 0)
    except (OSError, ValueError):
        t0 = time.time() - 600
    if diario_mtime() >= t0:
        return ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "ev": "padrao", "sid": p.get("session_id"),
                       "decisao": "ok_diario", "cartoes": [i for i, _ in viol]})
    ts = time.strftime("%Y-%m-%dT%H:%M:%S")
    ledger({"ts": ts, "ev": "padrao", "sid": p.get("session_id"), "decisao": "aviso", "cartoes": [i for i, _ in viol]})
    avisar(p.get("session_id"), "Sua resposta anterior fez o que o modelo faz SEM ADAS: " + " | ".join(
        f"{i}: {e.get('padrao', '')[:160]} ⇒ {e.get('conserto') or 'siga a regra'}" for i, e in viol)
        + f" O diário ({GOV}/DECISIONS.md) NÃO foi escrito: registre agora a {proxima_dh()} e diga ao dono onde ficou.", ts)


def pre(p):
    ex = p.get("extra") or {}
    msg = ex.get("user_message") or ""
    if isinstance(msg, (list, dict)):
        msg = json.dumps(msg, ensure_ascii=False)
    own = regras("DECISIONS.md", "DH")
    ext = {}
    pad = regras("padrao.md", "DA", ext)
    linhas, usado = [], 0
    for i, t, r in own:
        l = f"• {i} {t}: {r}"
        if usado + len(l) > BUDGET_OWN:
            break
        linhas.append(l); usado += len(l) + 1
    # motor de EVENTO (task 20261101-007): Gatilho `evento · prompt · quando=/re/` do padrão casa a mensagem e o cartão
    # entra MESMO sem palavra em comum com a regra (a frase de decisão do dono não fala "DA", "diário" nem "decisão")
    evento = [i for i, e in ext.items() if e.get("quando") and e["quando"].search(msg)]
    # a reação default que a regra substitui (Padrão sem ADAS) também é texto de busca: o padrão casa por ela
    pad_busca = [(i, t, r + " " + ext.get(i, {}).get("padrao", "")) for i, t, r in pad]
    hits = [(i, "evento") for i in evento] + [h for h in busca(pad_busca, msg) if h[0] not in evento]
    hits = hits[:max(K, len(evento))]
    idx = {i: (t, r) for i, t, r in pad}
    sel = []
    for i, _ in hits:
        if i not in idx:
            continue
        l = f"• {i} {idx[i][0]}: {idx[i][1][:400]}"
        e = ext.get(i) or {}
        if e.get("padrao"):
            l += f" ⚠️ Sem ADAS você faria: {e['padrao'][:200]} — NÃO faça isso."
        if e.get("conserto"):
            l += f" ⇒ {e['conserto']}"
        sel.append(l)
    if evento:
        sel.append(f"Diário deste host: {GOV}/DECISIONS.md — a próxima é {proxima_dh()} (`## DH-NNN — título`, linha "
                   "`escopo · origem · data · status`, `**Regra:**`); append no fim, nunca editar DH anterior.")
    try:  # marca do turno pro post saber se o diário foi escrito DEPOIS desta mensagem
        os.makedirs(JD, exist_ok=True)
        json.dump({"t": time.time(), "evento": evento}, open(turno_path(p.get("session_id")), "w"))
    except OSError:
        pass
    aviso = None
    ap = aviso_path(p.get("session_id"))
    if os.path.exists(ap):
        try:
            aviso = json.load(open(ap)).get("texto")
            os.remove(ap)
        except (OSError, ValueError):
            aviso = None
    ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "ev": "pre", "sid": p.get("session_id"), "nivel": NIVEL,
            "cartoes": hits, "aviso": bool(aviso)})
    if CHAVE_COLADA.search(msg):
        aviso = ((aviso + " ") if aviso else "") + (
            "A mensagem do usuário traz uma CHAVE/TOKEN colada (DA-479): NÃO use, não repita e não guarde. Diga que ela "
            "ficou exposta no histórico do chat e precisa ser REVOGADA no painel do provedor; a nova entra sem passar pelo "
            "chat, pelo link de uso único (o dono pede o link) ou por `juiz_prov.py configurar` no terminal.")
    if not linhas and not sel and not aviso:
        return
    out = "GOVERNANÇA (ADAS do Hermes — vale nesta resposta; regra PRÓPRIA vence a padrão):\n"
    if aviso:
        out += f"⚠️ {aviso}\n"
    if linhas:
        out += "PRÓPRIAS:\n" + "\n".join(linhas) + "\n"
    if sel:
        out += "PADRÃO que toca ESTA mensagem (ADAS-JIT):\n" + "\n".join(sel) + "\n"
    if pad:
        out += f"(padrão completo: {len(pad)} regras em {GOV}/padrao.md — leia se o assunto pedir)"
    print(json.dumps({"context": out.strip()}, ensure_ascii=False))


def chamadas_hoje():
    hoje = time.strftime("%Y-%m-%d"); n = 0
    try:
        for l in open(os.path.join(JD, "jit.log")):
            if l.startswith('{"ts": "' + hoje) and '"chamou": true' in l:
                n += 1
    except OSError:
        pass
    return n


def post(p):
    ex = p.get("extra") or {}
    texto = (ex.get("assistant_response") or "").strip()
    if not texto:
        return
    padrao_default(p, texto)
    if NIVEL < 3:
        return
    try:
        rub = json.load(open(os.path.join(GOV, "juiz-reply.json")))
    except (OSError, ValueError):
        return
    cartoes = rub.get("cartoes") or []
    if not cartoes:
        return
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "ev": "juiz", "sid": p.get("session_id"),
           "plataforma": ex.get("platform"), "len": len(texto), "chamou": False}
    if chamadas_hoje() >= TETO:
        rec["decisao"] = "teto"; return ledger(rec)
    t0 = time.time()
    rec["chamou"] = bool(juiz_prov.provedores(rede=False))
    try:
        resp, meta = juiz_prov.perguntar(texto[:4000], cartoes, t0 + TIMEOUT, "markdown")
        rec.update(meta)
    except Exception as e:
        resp = None
        rec["erro"] = str(e)[:120]
    rec["ms"] = round((time.time() - t0) * 1000)
    if not resp:
        rec["decisao"] = "erro" if rec["chamou"] else "sem_chave"; return ledger(rec)
    viol = [c for c in cartoes if resp.get(c["id"], 0.0) >= min(c.get("limiar", 0.8), c.get("limiar_aviso") or 9)]
    cala = lambda c: c.get("modo") == "silencioso" or resp.get(c["id"], 0.0) <= (c.get("limiar_abstem") or 0)  # DA-699 + P1 (abstenção conformal)
    if any(cala(c) for c in viol):  # grava, não avisa
        rec["silencioso"] = [c["id"] for c in viol if cala(c)]
        viol = [c for c in viol if not cala(c)]
    rec.update(resp={a: round(b, 3) for a, b in resp.items()}, decisao="aviso" if viol else "ok", cartoes=[c["id"] for c in viol])
    ledger(rec)
    if viol:
        txt = ("Sua resposta anterior quebrou regra de forma do ADAS (o juiz leu depois de sair): "
               + " | ".join(f'{c["id"]}: {c["regra_curta"][:200]} Conserto: {c.get("conserto") or "-"}' for c in viol)
               + " — se fizer sentido, corrija ou complemente nesta resposta e não repita.")
        avisar(p.get("session_id"), txt, rec["ts"])


def main():
    try:
        p = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return
    ev = p.get("hook_event_name") or (sys.argv[1] if len(sys.argv) > 1 else "")
    if ev == "pre_llm_call":
        pre(p)
    elif ev == "post_llm_call":
        post(p)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
