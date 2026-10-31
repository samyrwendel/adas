#!/usr/bin/env python3
"""hermes-jit.py — ADAS-JIT para o Hermes Agent (shell hooks). Um script, dois eventos:

  pre_llm_call   regras PRÓPRIAS do host (DECISIONS.md, DH-NNN) inteiras + até K regras do PADRÃO (padrao.md)
                 escolhidas pela mensagem do usuário (busca por palavra, FTS5/bm25, com limiar; abaixo = silêncio)
                 + o aviso pendente do juiz sobre a resposta ANTERIOR desta sessão. Saída: {"context": "..."}.
  post_llm_call  (nível 3) o juiz (Jev nativo, /systemone) lê a resposta que acabou de sair com as perguntas de
                 forma da rubrica (juiz-reply.json); violação vira linha no ledger e aviso para o próximo turno.
                 O Hermes não tem shell hook ANTES da entrega (transform_llm_output é só plugin Python e só troca
                 texto), então aqui o juiz é sempre AVISO: corrige a próxima mensagem, não segura esta.

Níveis (ADAS_JIT_NIVEL, DA-468): 1 = próprias + busca por palavra; 2 = idem (vetor não roda aqui: sem Ollama no
container; o nível 2 se comporta como 1); 3 = + juiz. Default 3. Fail-open em tudo: erro = sem saída, exit 0.
Arquivos em ADAS_GOV_DIR (default $HERMES_HOME/governanca): DECISIONS.md, padrao.md, juiz-reply.json, jit/ (ledger,
avisos). Chave do juiz: env OPENROUTER_API_KEY / EXPERIENTIALLABS_API_KEY, senão a linha do $HERMES_HOME/.env.
Env: ADAS_JIT_K (3), ADAS_JIT_BM25 (limiar, -5.0), ADAS_BUDGET_OWN (3500), ADAS_JIT_TETO (chamadas/dia, 300),
ADAS_JIT_TIMEOUT (s, 8)."""
import json, os, re, sqlite3, sys, time, urllib.request

HH = os.environ.get("HERMES_HOME", "/opt/data")
GOV = os.environ.get("ADAS_GOV_DIR", os.path.join(HH, "governanca"))
JD = os.path.join(GOV, "jit")
NIVEL = int(os.environ.get("ADAS_JIT_NIVEL", "3") or 3)
K = int(os.environ.get("ADAS_JIT_K", "3"))
BM25 = float(os.environ.get("ADAS_JIT_BM25", "-5.0"))  # calibrado em 31/10: ruído ≤ |4,1|, acerto ≥ |5,3|
BUDGET_OWN = int(os.environ.get("ADAS_BUDGET_OWN", "3500"))
TETO = int(os.environ.get("ADAS_JIT_TETO", "300"))
TIMEOUT = float(os.environ.get("ADAS_JIT_TIMEOUT", "8"))
PROV = [("OPENROUTER_API_KEY", "https://openrouter.ai/api/v1/systemone"),
        ("EXPERIENTIALLABS_API_KEY", "https://api.experientiallabs.ai/v1/systemone")]


def regras(arq, pref):
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
    return out


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


def pre(p):
    ex = p.get("extra") or {}
    msg = ex.get("user_message") or ""
    if isinstance(msg, (list, dict)):
        msg = json.dumps(msg, ensure_ascii=False)
    own = regras("DECISIONS.md", "DH")
    pad = regras("padrao.md", "DA")
    linhas, usado = [], 0
    for i, t, r in own:
        l = f"• {i} {t}: {r}"
        if usado + len(l) > BUDGET_OWN:
            break
        linhas.append(l); usado += len(l) + 1
    hits = busca(pad, msg)
    idx = {i: (t, r) for i, t, r in pad}
    sel = [f"• {i} {idx[i][0]}: {idx[i][1][:400]}" for i, _ in hits if i in idx]
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


def chave(nome):
    if os.environ.get(nome):
        return os.environ[nome]
    try:
        for l in open(os.path.join(HH, ".env"), encoding="utf-8"):
            if l.startswith(nome + "="):
                return l.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return ""


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
    if NIVEL < 3:
        return
    ex = p.get("extra") or {}
    texto = (ex.get("assistant_response") or "").strip()
    if not texto:
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
    q = {c["id"]: {"type": "noul", "instructions": c["pergunta"]} for c in cartoes}
    corpo = json.dumps({"model": "jev-latest", "state": {"mensagem": texto[:4000], "formato": "markdown"},
                        "questions": q}).encode()
    t0 = time.time(); resp = None
    for nome, url in PROV:
        k = chave(nome)
        if not k:
            continue
        try:
            rec["chamou"] = True
            req = urllib.request.Request(url, data=corpo, headers={"Authorization": "Bearer " + k, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=max(0.5, TIMEOUT - (time.time() - t0))) as r:
                d = json.loads(r.read())
            resp = {a: float(v.get("noul")) for a, v in (d.get("answers") or {}).items() if v.get("noul") is not None}
            rec.update(prov=nome.split("_")[0].lower(), model=d.get("model"), cost=(d.get("usage") or {}).get("cost"))
            if resp:
                break
        except Exception as e:
            rec["erro"] = f"{type(e).__name__}: {str(e)[:80]}"
    rec["ms"] = round((time.time() - t0) * 1000)
    if not resp:
        rec["decisao"] = "erro" if rec.get("chamou") else "sem_chave"; return ledger(rec)
    viol = [c for c in cartoes if resp.get(c["id"], 0.0) >= min(c.get("limiar", 0.8), c.get("limiar_aviso") or 9)]
    rec.update(resp={a: round(b, 3) for a, b in resp.items()}, decisao="aviso" if viol else "ok", cartoes=[c["id"] for c in viol])
    ledger(rec)
    if viol:
        txt = ("Sua resposta anterior quebrou regra de forma do ADAS (o juiz leu depois de sair): "
               + " | ".join(f'{c["id"]}: {c["regra_curta"][:200]} Conserto: {c.get("conserto") or "-"}' for c in viol)
               + " — se fizer sentido, corrija ou complemente nesta resposta e não repita.")
        try:
            os.makedirs(JD, exist_ok=True)
            json.dump({"texto": txt, "ts": rec["ts"]}, open(aviso_path(p.get("session_id")), "w"), ensure_ascii=False)
        except OSError:
            pass


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
