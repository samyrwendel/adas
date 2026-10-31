#!/usr/bin/env python3
"""da-cards.py — compila os ledgers (DECISIONS.md vigentes + CONDUCT.md) em CARTÕES DE REGRA e indexa
(ADAS-JIT F0, task 20261031-018). Saída em ~/.adas/jit/: cards.json, regras.db (FTS5 + vec0), emb-cache.json.

Níveis (compatível com os 3 do produto):
  1 básico: cartões + FTS5/bm25 — stdlib pura, sem Ollama.
  2 + vetor: embedding nomic-embed-text via Ollama (opcional). Ollama fora → cartão sem vetor, FTS segue.
  3 + juiz (F3, task 20261031-027): cartão com `**Gatilho:** forma · reply · juiz` vira UMA pergunta tipada
    da rubrica juiz-reply.json (derivada da Regra, ou `pergunta="…"` do próprio Gatilho). DA nova com esse
    Gatilho = pergunta nova, sem código. `forma · reply · hook=<guard>` entra na lista de guards que o juiz
    roda ANTES. Modo `deny` só com `modo=deny` no Gatilho E aprovado no replay (juiz-gate.json); o resto é aviso.
Gatilho vem de `da-index.sh gatilhos` (última linha de cada id vale; ausência = tema).
Incremental por hash do texto indexado: DA nova = 1 embedding. Semente opcional: /tmp/senior-013/emb.json.
Uso: da-cards.py [--home DIR] [--out DIR] [--no-vec] [--so-juiz] [--seed emb.json]"""
import hashlib, json, os, re, sqlite3, struct, subprocess, sys, urllib.request

HOME = os.path.expanduser("~")
OUT = os.path.join(HOME, ".adas", "jit")
LIMIAR_PADRAO = 0.8
OLL = os.environ.get("ADAS_OLLAMA", "http://127.0.0.1:11434/api/embed")
MODEL = os.environ.get("ADAS_EMBED_MODEL", "nomic-embed-text")
EMBED_MAX = 2000

def load_vec(db):
    try:
        import sqlite_vec
    except ImportError:  # venv do cérebro (instância); no produto: pip install sqlite-vec
        import glob
        for p in glob.glob(os.path.join(HOME, "brain/.venv/lib/python3*/site-packages")):
            sys.path.append(p)
        try:
            import sqlite_vec
        except ImportError:
            return False
    try:
        db.enable_load_extension(True); sqlite_vec.load(db); db.enable_load_extension(False)
        return True
    except Exception:
        return False

def embed(texts):
    req = urllib.request.Request(OLL, data=json.dumps({"model": MODEL, "input": [t[:EMBED_MAX] for t in texts]}).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(r.read())["embeddings"]

def f32(v): return struct.pack("%df" % len(v), *v)
def sha(t): return hashlib.sha1(t.encode()).hexdigest()[:16]

def extract(home):
    vig = set(re.findall(r"^- (DA-\d+[a-z]?)", subprocess.run(
        ["bash", os.path.join(home, "scripts/da-index.sh"), "list", "--vigentes", home],
        capture_output=True, text=True).stdout, re.M))
    cards = []
    txt = open(os.path.join(home, "DECISIONS.md"), encoding="utf-8").read()
    for b in re.split(r"(?m)^(?=## DA-\d)", txt)[1:]:
        h = re.match(r"## (DA-\d+[a-z]?) — (.*)", b)
        if not h or h.group(1) not in vig: continue
        def campo(n):
            m = re.search(r"\*\*" + n + r":\*\*(.*?)(?=\n\*\*|\n###|\n---|\Z)", b, re.S)
            return " ".join(m.group(1).split()) if m else ""
        regra = campo("Regra")
        if regra: cards.append({"id": h.group(1), "titulo": h.group(2).strip(), "regra": regra, "motivo": campo("Motivo")})
    ctxt = open(os.path.join(home, "CONDUCT.md"), encoding="utf-8").read()
    for b in re.split(r"(?m)^(?=## DC-\d)", ctxt)[1:]:
        h = re.match(r"## (DC-\d+) — (.*)", b); r = re.search(r"\*\*Regra:\*\*(.*?)\n", b)
        if not h or not r: continue
        why = re.search(r"\*\*Why:\*\*(.*?)(?=\n\*\*|\n##|\Z)", b, re.S)
        cards.append({"id": h.group(1), "titulo": h.group(2).strip(), "regra": " ".join(r.group(1).split()),
                      "motivo": " ".join(why.group(1).split()) if why else ""})
    gat = gatilhos(home)
    for c in cards:
        c["gatilho"] = gat.get(c["id"], {"tipo": "tema"})
        c["regra_curta"] = c["regra"] if len(c["regra"]) <= 240 else c["regra"][:237].rstrip() + "…"
        c["texto"] = f'{c["id"]} {c["titulo"]}\nRegra: {c["regra"][:700]}\nMotivo: {c["motivo"][:500]}'
        c["hash"] = sha(c["texto"])
    return cards

def parse_gatilho(spec):
    """'forma · reply · juiz · modo=deny · pergunta="…"' → dict. Tolerante: token desconhecido é ignorado."""
    partes = [p.strip() for p in re.split(r"\s+·\s+", spec.strip()) if p.strip()]
    g = {"tipo": partes[0].lower() if partes else "tema"}
    if len(partes) > 1 and "=" not in partes[1]:
        g["superficie"] = partes[1].lower()
    for p in partes[1:]:
        if p.lower() == "juiz":
            g["juiz"] = True
        elif "=" in p:
            k, v = p.split("=", 1)
            g[k.strip().lower()] = v.strip().strip('"').strip("'")
    return g

def gatilhos(home):
    r = subprocess.run(["bash", os.path.join(home, "scripts/da-index.sh"), "gatilhos", home], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():  # da-index local sem o subcomando → o do servidor
        r = subprocess.run(["bash", os.path.join(HOME, "scripts/da-index.sh"), "gatilhos", home], capture_output=True, text=True)
    out = {}
    for l in r.stdout.splitlines():
        f = l.split("\t")
        if len(f) >= 2:
            g = parse_gatilho(f[1]); g["fonte"] = f[2] if len(f) > 2 else f[0]; out[f[0]] = g
    return out

def hook_path(h):
    h = os.path.expanduser(h)
    return h if os.path.isabs(h) else os.path.join(HOME, ".claude/hooks", h)

def compila_juiz(cards, out):
    """Rubrica do juiz da superfície reply: SÓ cartões forma·reply·juiz; guards forma·reply·hook= à parte."""
    gp = os.path.join(out, "juiz-gate.json")
    gate = json.load(open(gp)) if os.path.exists(gp) else {}
    rub, hooks = [], []
    for c in cards:
        g = c.get("gatilho") or {}
        if g.get("tipo") != "forma" or g.get("superficie") != "reply":
            continue
        if g.get("hook") and g.get("antes") != "nao":  # antes=nao: guard com estado próprio (deny-once) não roda 2x
            hp = hook_path(g["hook"])
            if hp not in hooks: hooks.append(hp)
        if not g.get("juiz"):
            continue
        gt = gate.get(c["id"]) or {}
        aprovado = gt.get("aprovado") is True
        rub.append({"id": c["id"], "titulo": c["titulo"],
                    "pergunta": g.get("pergunta") or f'A mensagem desrespeita esta regra? Regra: {c["regra"][:500]}',
                    "regra_curta": c["regra_curta"],
                    "conserto": g.get("conserto") or "reescreva cumprindo a Regra (ou diga explicitamente o que não conferiu).",
                    "limiar": float(gt.get("limiar", LIMIAR_PADRAO)),
                    "modo": "deny" if g.get("modo") == "deny" and aprovado else "aviso",
                    "modo_pedido": g.get("modo", "aviso"), "replay": "aprovado" if aprovado else ("reprovado" if gt else "pendente"),
                    "fonte": g.get("fonte")})
    corpo = {"cartoes": rub, "hooks": hooks}
    corpo["hash"] = sha(json.dumps(corpo, sort_keys=True, ensure_ascii=False))
    tmp = os.path.join(out, "juiz-reply.json.tmp")
    json.dump(corpo, open(tmp, "w"), ensure_ascii=False, indent=1); os.replace(tmp, os.path.join(out, "juiz-reply.json"))
    print(f"juiz-reply: {len(rub)} pergunta(s) ({sum(r['modo']=='deny' for r in rub)} deny), {len(hooks)} guard(s) antes")

def compila_gatilhos(cards, out):
    """gatilhos.json: só cartões com gatilho declarado (≠ tema puro) — o que o regra-jit avalia por predicado
    (evento · <superfície> · quando=/re/ [salvo=/re/]) e o que o adas-jit-test.sh roda por hook= (fixtures)."""
    gs = [{"id": c["id"], "titulo": c["titulo"], "regra_curta": c["regra_curta"], "gatilho": c["gatilho"]}
          for c in cards if (c.get("gatilho") or {}).get("tipo", "tema") != "tema"]
    tmp = os.path.join(out, "gatilhos.json.tmp")
    json.dump(gs, open(tmp, "w"), ensure_ascii=False, indent=1); os.replace(tmp, os.path.join(out, "gatilhos.json"))
    print(f"gatilhos: {len(gs)} declarado(s) ({sum(1 for g in gs if g['gatilho'].get('quando'))} predicado, "
          f"{sum(1 for g in gs if g['gatilho'].get('hook'))} hook=)")

def main():
    a = sys.argv[1:]
    home = a[a.index("--home") + 1] if "--home" in a else HOME
    novec = "--no-vec" in a
    seed = a[a.index("--seed") + 1] if "--seed" in a else None
    global OUT
    OUT = a[a.index("--out") + 1] if "--out" in a else OUT
    os.makedirs(OUT, exist_ok=True)
    cards = extract(home)
    compila_juiz(cards, OUT)
    compila_gatilhos(cards, OUT)
    if "--so-juiz" in a:
        return
    cache_p = os.path.join(OUT, "emb-cache.json")
    cache = json.load(open(cache_p)) if os.path.exists(cache_p) else {}
    if seed and os.path.exists(seed):  # semente: chave "ID|RM" → vetor do mesmo texto
        s = json.load(open(seed)); n = 0
        for c in cards:
            v = s.get(c["id"] + "|RM")
            if v and c["hash"] not in cache and len(v) == 768:
                # só vale se o texto indexado não mudou desde a semente
                try:
                    old = {x["id"]: x for x in json.load(open(os.path.join(os.path.dirname(seed), "cards.json")))}[c["id"]]
                    otxt = f'{old["id"]} {old["title"]}\nRegra: {old["regra"][:700]}\nMotivo: {old["motivo"][:500]}'
                    if sha(otxt) == c["hash"]: cache[c["hash"]] = v; n += 1
                except Exception: pass
        print(f"semente: {n} vetores reaproveitados")
    vec_ok = not novec
    if vec_ok:
        todo = [c for c in cards if c["hash"] not in cache]
        try:
            for i in range(0, len(todo), 8):
                for c, v in zip(todo[i:i+8], embed([c["texto"] for c in todo[i:i+8]])): cache[c["hash"]] = v
                json.dump(cache, open(cache_p, "w"))
            print(f"embeddings novos: {len(todo)}")
        except Exception as e:
            print(f"Ollama indisponível ({e.__class__.__name__}) — índice só FTS (nível 1)"); vec_ok = False
    db_p = os.path.join(OUT, "regras.db.tmp")
    if os.path.exists(db_p): os.remove(db_p)
    db = sqlite3.connect(db_p)
    has_vec = vec_ok and load_vec(db)
    db.execute("create table docs(id integer primary key, key text, titulo text, regra_curta text, texto text)")
    db.execute("create virtual table docs_fts using fts5(texto, content='docs', content_rowid='id')")
    if has_vec: db.execute("create virtual table docs_vec using vec0(embedding float[768])")
    db.execute("create table meta(k text primary key, v text)")
    for i, c in enumerate(cards, 1):
        db.execute("insert into docs values(?,?,?,?,?)", (i, c["id"], c["titulo"], c["regra_curta"], c["texto"]))
        db.execute("insert into docs_fts(rowid,texto) values(?,?)", (i, c["texto"]))
        if has_vec and c["hash"] in cache: db.execute("insert into docs_vec(rowid,embedding) values(?,?)", (i, f32(cache[c["hash"]])))
    db.executemany("insert into meta values(?,?)", [("n", str(len(cards))), ("vec", "1" if has_vec else "0"), ("modelo", MODEL)])
    db.commit(); db.close()
    os.replace(db_p, os.path.join(OUT, "regras.db"))
    json.dump(cards, open(os.path.join(OUT, "cards.json"), "w"), ensure_ascii=False, indent=0)
    print(f"cartões {len(cards)} (DA {sum(c['id'].startswith('DA') for c in cards)}, DC {sum(c['id'].startswith('DC') for c in cards)}) | nível {'2 (FTS+vetor)' if has_vec else '1 (FTS)'}")

if __name__ == "__main__":
    main()
