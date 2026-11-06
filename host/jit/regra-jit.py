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
        prompt: L2 ≤ 0,65, ou bm25 ≤ -25 só se o corpo < 300 chars (bm25 é absoluto e infla com o tamanho),
                ou LÍDER: os dois motores concordam (ver lider(); task 20261101-001)
        bash:   DESLIGADO por padrão (ADAS_JIT_BASH_VEC=1 liga: L2 ≤ 0,65 e comando > 8 palavras). Medido em
                135 comandos reais: léxico dispara em 60–90% (ruído); vetor custa ~1 s/comando em CPU e
                disparou 3/135, todos autorreferentes; o positivo real (backup de um servidor) ficou em L2 0,74. Bash = evento.
        edit:   L2 ≤ 0,60; ledgers (DECISIONS*/CONDUCT) ficam só com o motor de evento
Saída: additionalContext (nunca bloqueia; deny é papel dos guards `hook=`). Cartão cujo id já está no
payload é omitido (o agente já está nele); cartão já mostrado na sessão nos últimos 30 min também.
Escopo: no motor de TEMA, cartão `projeto/*` só aparece no cwd do projeto (rotas.conf, contrato do
adas_da_rotas); o motor de EVENTO não filtra (o predicado de caminho/comando já é o escopo).
Regra-mãe: cartão-mecanismo mostrado traz a regra que ele mecaniza (grafo.json, aresta mecanismo-de).
Ledger: ~/.claude/bus/regra-jit.log (JSONL: ts, sid, superfície, nível, vetor ok|off|<erro>, escopo, cartões
com l2/bm25, decisão, ms). Par (PostToolBatch): leu_da + adesao {id: aplicou|ignorou|n/a} pelo `viola=/re/`.
Env: ADAS_JIT=off (desliga) | log (sombra: grava o ledger, não injeta). Nível (ADAS_JIT_NIVEL → ~/.adas/jit/nivel.fixo →
~/.adas/jit/nivel, do termostato.py → 3): 1 tira o vetor (só evento + léxico); 2/3 usa o vetor; o juiz (nível 3) é o
hook juiz-reply.py. Fail-open em tudo."""
import hashlib, json, os, re, subprocess, sys, time

HOME = os.path.expanduser("~")
D = os.environ.get("ADAS_JIT_DIR") or os.path.join(HOME, ".adas", "jit")
BUS = os.environ.get("ADAS_JIT_BUS") or os.path.join(HOME, ".claude", "bus")
LOG = os.path.join(BUS, "regra-jit.log")
STATE = os.path.join(BUS, "regra-jit")
K = 3
TTL_VISTO = 1800  # dedupe: o mesmo cartão não repete na sessão em <30 min (medição 20261102-024: 3 cartões = 34 de 48 disparos)
JUIZ_LIMIAR = float(os.environ.get("ADAS_JIT_JUIZ_LIMIAR", "0.3"))  # prob. mínima de "a regra se aplica a ESTA ação" (calibrado no replay de 30)
JUIZ_TETO = int(os.environ.get("ADAS_JIT_JUIZ_TETO", "400"))          # chamadas/dia do filtro (custo ~5e-5 USD cada)
JUIZ_TIMEOUT = float(os.environ.get("ADAS_JIT_JUIZ_TIMEOUT", "2.5"))
LIMIAR = {"prompt": {"l2": 0.65, "bm25": -25.0, "bm25_max_chars": 300, "lider_l2": 0.82, "lider_bm25": -12.0, "lider_razao": 1.6},
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


_RS = None
def rs():
    """regra-search como módulo (Index, escopos, grafo, regra_mae) — carregado uma vez por hook."""
    global _RS
    if _RS is None:
        import importlib.machinery, importlib.util
        ld = importlib.machinery.SourceFileLoader("regra_search", os.path.join(D, "regra-search"))
        _RS = importlib.util.module_from_spec(importlib.util.spec_from_loader("regra_search", ld))
        ld.exec_module(_RS)
    return _RS



TEXTO = {"bus-inject.sh", "da-new.sh", "alert-mainbot.sh", "echo", "printf", "sed", "grep", "rg", "awk", "git", "gh"}
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?(?:\n\s*\2\s*(?=\n|$)|$)", re.S)

def comando_sem_corpo(cmd):
    """Bash: o `quando` do gatilho casa no COMANDO, não no texto que ele carrega (task 20261103-001, N=8 de 10 na
    amostra). Tira (1) corpo de heredoc e (2) argumentos entre aspas de programas de texto (TEXTO: bus-inject, da-new,
    echo, sed, grep, git commit…). `ssh host 'restic …'` e `python3 -c '…'` ficam: lá o argumento É o comando.
    ponytail: split por ; | & \\n sem aspas aninhadas; subshell $(...) com texto passa inteiro (fail-open = cartão a mais)."""
    cmd = HEREDOC.sub(lambda m: m.group(0).split("\n", 1)[0], cmd)
    out = []
    segs = re.split(r"(?<!\\)([;&|\n]+)", cmd)  # separadores ficam nas posições ímpares
    # junta de volta segmentos cortados dentro de aspas
    juntos, buf = [], ""
    for k, part in enumerate(segs):
        buf += part
        if k % 2 == 0 and buf.count("'") % 2 == 0 and buf.count('"') % 2 == 0:
            juntos.append(buf); buf = ""
    if buf:
        juntos.append(buf)
    for seg in juntos:
        w = re.sub(r"^\s*(?:\w+=\S*\s+)*", "", seg).split(None, 1)
        prog = os.path.basename(w[0]) if w else ""
        if prog in ("bash", "sh", "python3") and len(w) > 1:  # `bash …/bus-inject.sh "<texto>"`
            prog = os.path.basename(w[1].split()[0])
        out.append(re.sub(r"'[^']*'|\"[^\"]*\"", "''", seg) if prog in TEXTO else seg)
    return "".join(out)

def motor_evento(sup, alvo):
    try:
        gs = json.load(open(os.path.join(D, "gatilhos.json")))
    except Exception:
        return []
    out = []
    cru = alvo
    if sup == "bash":
        alvo = comando_sem_corpo(alvo)  # só o `quando` lê o comando limpo; o `salvo` lê o texto inteiro (ex.: "passada de uso" no critério)
    for g in gs:
        gt = g.get("gatilho") or {}
        # sem filtro de escopo aqui: o predicado (caminho/comando) JÁ é o escopo — a DA-401 (projeto) governa a edição
        # de ~/claude-tg-tmux/skills/quantfury feita do cwd da instância. O filtro vale pro motor de TEMA.
        # superfície pode ser lista ("bash,edit,prompt"): a CLASSE da ação (atualizar o pacote X, escrever no caminho Y)
        # acende em qualquer superfície que a carrega — task 20261101-001, medição 033 (sed -i no cache, npm update -g)
        if sup not in (gt.get("superficie") or "").replace(" ", "").split(",") or not gt.get("quando") or gt.get("hook"):
            continue
        try:
            q, s = rx(gt["quando"]), rx(gt.get("salvo"))
            if q and q.search(alvo) and not (s and s.search(cru)):
                out.append({"id": g["id"], "regra_curta": g["regra_curta"], "titulo": g.get("titulo"), "motor": "evento",
                            "conserto": gt.get("conserto")})
        except re.error:
            continue
    return out


def juiz_filtra(sup, alvo, cards):
    """Filtro do motor de EVENTO (task 20261103-001, Samyr msg 12171): o regex acha a palavra; o juiz Jev responde "a
    regra se aplica a ESTA ação?" (uma chamada, todas as perguntas, juiz_prov: OpenRouter titular, EL reserva). Cartão
    com p < JUIZ_LIMIAR cai. FALHA = PASSA (DA-468): sem chave, nível < 3, teto/dia, timeout ou erro mostram o cartão.
    → (cartões que ficam, {id: p}, meta). Contador diário em STATE/juiz-AAAAMMDD.n (a barra é o teto, não o ledger)."""
    ev = [c for c in cards if c.get("motor") == "evento"]
    meta = {"chamou": False}
    if not ev or os.environ.get("ADAS_JIT_JUIZ", "on") == "off":
        return cards, {}, meta
    try:
        sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
        import juiz_prov
        if juiz_prov.nivel() < 3 or not juiz_prov.provedores(rede=False):
            return cards, {}, dict(meta, motivo="sem_juiz")
        cn = os.path.join(STATE, "juiz-" + time.strftime("%Y%m%d") + ".n")
        try:
            n = int(open(cn).read() or 0)
        except (OSError, ValueError):
            n = 0
        if n >= JUIZ_TETO:
            return cards, {}, dict(meta, motivo="teto")
        os.makedirs(STATE, exist_ok=True)
        open(cn, "w").write(str(n + 1))
        perg = [{"id": c["id"], "pergunta": (
            f'A AÇÃO acima (superfície {sup}) trabalha no assunto da regra {c["id"]} — "{c.get("titulo") or ""}" — de modo que '
            f'lembrar essa regra agora ajudaria quem a executa? Regra: {c["regra_curta"]} '
            "Responda NÃO só quando o assunto aparece por acaso: texto de fixture/teste de hook, comentário de código, "
            "mensagem ou task de outro assunto, ou outro projeto.")} for c in ev]
        t0 = time.time()
        meta["chamou"] = True
        resp, m = juiz_prov.perguntar(alvo[:1500], perg, t0 + JUIZ_TIMEOUT)
        meta.update(ms=round((time.time() - t0) * 1000), prov=m.get("prov"), cost=m.get("cost"))
    except Exception as e:
        return cards, {}, dict(meta, erro=type(e).__name__ + ": " + str(e)[:80])
    return [c for c in cards if c.get("motor") != "evento" or resp.get(c["id"], 1.0) >= JUIZ_LIMIAR], \
        {k: round(v, 2) for k, v in resp.items()}, meta

def juiz_prompt(texto, ja):
    """Juiz na superfície PROMPT: toda mensagem do dono passa pelas perguntas tipadas de juiz-prompt.json (ex.: "isto é
    decisão permanente?"). Regex na frente (motor_evento), juiz atrás: a regra que o regex JÁ acendeu (`ja`) não é
    perguntada de novo. sombra = só ledger; aviso = vira cartão. FALHA = SILÊNCIO (o regex continua na frente).
    Divide o teto diário com o filtro de evento (STATE/juiz-AAAAMMDD.n). → (cartões, meta)"""
    meta = {"chamou": False}
    try:
        rub = [r for r in (json.load(open(os.path.join(D, "juiz-prompt.json"))).get("cartoes") or []) if r["id"] not in ja]
    except Exception:
        return [], meta
    if not rub or os.environ.get("ADAS_JIT_JUIZ", "on") == "off" or len(texto.strip()) < 12:
        return [], meta
    try:
        sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
        import juiz_prov
        if juiz_prov.nivel() < 3 or not juiz_prov.provedores(rede=False):
            return [], dict(meta, motivo="sem_juiz")
        cn = os.path.join(STATE, "juiz-" + time.strftime("%Y%m%d") + ".n")
        try:
            n = int(open(cn).read() or 0)
        except (OSError, ValueError):
            n = 0
        if n >= JUIZ_TETO:
            return [], dict(meta, motivo="teto")
        os.makedirs(STATE, exist_ok=True)
        open(cn, "w").write(str(n + 1))
        t0 = time.time()
        meta["chamou"] = True
        resp, m = juiz_prov.perguntar(texto[:1500], [{"id": r["id"], "pergunta": r["pergunta"]} for r in rub], t0 + JUIZ_TIMEOUT)
        meta.update(ms=round((time.time() - t0) * 1000), prov=m.get("prov"), cost=m.get("cost"),
                    p={k: round(v, 2) for k, v in resp.items()})
    except Exception as e:
        return [], dict(meta, erro=type(e).__name__ + ": " + str(e)[:80])
    hit = [r for r in rub if resp.get(r["id"], 0.0) >= r["limiar"]]
    meta["sombra"] = [r["id"] for r in hit if r["modo"] != "aviso"]
    return [{"id": r["id"], "regra_curta": r["regra_curta"], "titulo": r.get("titulo"), "motor": "juiz",
             "conserto": r.get("conserto")} for r in hit if r["modo"] == "aviso"], meta


def linha_cartao(c, par=None, mae=None):
    """Uma linha do cartão. Com Exemplo em par (pares.json): regra em ≤120 chars + ✗ errado → ✓ certo (exemplo > regra);
    sem par: a regra_curta de sempre."""
    if par:
        r = c["regra_curta"]
        l = f'• {c["id"]} — {r[:120].rstrip()}{"…" if len(r) > 120 else ""}  ✗ {par["errado"][:140]} → ✓ {par["certo"][:140]}'
    else:
        l = f'• {c["id"]} — {c["regra_curta"]}'
    if mae:
        l += f'  (regra-mãe: {", ".join(mae)})'
    if c.get("conserto"):
        l += f'  ⇒ {c["conserto"]}'
    return l + f'  → bash ~/scripts/da-index.sh show {c["id"]} ~'


def nivel():
    """Nível do JIT (DA-468): env → nivel.fixo → nivel (termostato) → 3. Mesmo contrato do juiz_prov.nivel()."""
    try:
        sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
        import juiz_prov
        return juiz_prov.nivel()
    except Exception:
        v = os.environ.get("ADAS_JIT_NIVEL", "3")
        return int(v) if v.isdigit() else 3


def motor_tema(sup, texto, alvo, esc):
    """→ (cartões, nível, vetor). vetor = ok | off | <Exceção> — o embed que morreu sob carga fica no ledger."""
    lim = LIMIAR[sup]
    if sup == "edit" and LEDGERS.search(alvo):
        return [], 0, "-"
    if sup == "bash" and (os.environ.get("ADAS_JIT_BASH_VEC") != "1" or len(texto.split()) <= lim.get("min_palavras", 0)):
        return [], 0, "-"
    os.environ.setdefault("ADAS_EMBED_TIMEOUT", "1.5")
    # DA-468: nível 1 = travas + gatilho + busca por palavra (sem vetor); 2 = + vetor; 3 = + juiz (hook à parte)
    idx = rs().Index(path=os.path.join(D, "regras.db"), vec=nivel() >= 2)
    res = [r for r in idx.search(texto, n=12) if rs().no_escopo(r.get("escopo"), esc)][:8]
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
    lid = lider(res, lim)
    if lid and lid["id"] not in {c["id"] for c in out}:
        out.append({"id": lid["id"], "regra_curta": lid["regra_curta"], "motor": "lider", "l2": lid["l2"], "bm25": lid["bm25"]})
    erro = getattr(idx, "vec_erro", None)
    return out, (2 if idx.vec and not erro else 1), (erro or ("ok" if idx.vec else "off"))


def lider(res, lim):
    """Os dois motores CONCORDAM num líder (task 20261101-001, medição 033): 1º no léxico com folga (bm25 ≥ razão × o
    2º — normaliza o bm25 pela própria consulta, que infla com o tamanho), entre os 2 primeiros no vetor, e passando
    um piso frouxo em cada lado. Banco de 68 casos: regra-alvo no prompt 12 → 23; nas 300 mensagens reais do dono,
    disparo 7 → 13 (5 dos 6 novos relevantes). O espalhamento pelo grafo foi medido aqui e não achou alvo novo (0/68):
    fica só reordenando."""
    if "lider_razao" not in lim:
        return None
    bms = sorted((r for r in res if r.get("bm25") is not None), key=lambda r: r["bm25"])
    l2s = sorted((r for r in res if r.get("l2") is not None), key=lambda r: r["l2"])
    if not bms or not l2s:
        return None
    t, seg = bms[0], (bms[1]["bm25"] if len(bms) > 1 else -0.1)
    if (t["l2"] is not None and t["l2"] <= lim["lider_l2"] and t["bm25"] <= lim["lider_bm25"]
            and t["bm25"] / min(seg, -0.1) >= lim["lider_razao"] and t["id"] in {r["id"] for r in l2s[:2]}):
        return t
    return None


def corta_k(vivos):
    """Corta em K respeitando a gravidade (DA-522, D4): piso nunca é cortado (pode passar de K), preferência é a primeira a sair.
    Sem gravidade.json (ou tudo norma) = vivos[:K] de sempre. Ordem original preservada dentro de cada nível."""
    try:
        g = json.load(open(os.path.join(D, "gravidade.json")))
    except Exception:
        return vivos[:K]
    peso = {"piso": 0, "preferência": 2}
    ordem = sorted(range(len(vivos)), key=lambda i: (peso.get(g.get(vivos[i]["id"]), 1), i))
    pisos = [i for i in ordem if g.get(vivos[i]["id"]) == "piso"]
    keep = set(pisos) | set(ordem[:max(K, len(pisos))])
    return [c for i, c in enumerate(vivos) if i in keep]


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
    # adesão por PREDICADO (task 029 §A.2 #4): cartão com `viola=/re/` no Gatilho → a ação seguinte casa? ignorou : aplicou.
    # Sem viola= → n/a (menção do id não prova cumprimento). Ações = tool_input dos tool_uses do lote.
    try:
        gs = {g["id"]: g.get("gatilho") or {} for g in json.load(open(os.path.join(D, "gatilhos.json")))}
    except Exception:
        gs = {}
    acoes = "\n".join(json.dumps(t.get("tool_input") or {}, ensure_ascii=False) for t in p.get("tool_uses") or [])
    adesao = {}
    for c in mostrado["cartoes"]:
        try:
            v = rx((gs.get(c) or {}).get("viola"))
        except re.error:
            v = None
        adesao[c] = ("ignorou" if v.search(acoes) else "aplicou") if v else "n/a"
    ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "sid": sid, "superficie": "par",
            "mostrado_em": mostrado.get("superficie"), "cartoes": mostrado["cartoes"], "leu_da": leu, "adesao": adesao,
            "ferramentas": ferr[:6], "atraso_s": round(time.time() - mostrado.get("t", time.time()), 1)})


def recompila_se_velho():
    """Ledger mais novo que o compilado → da-cards.py desacoplado. Pega escrita por shell (da-new.sh, heredoc),
    que o PostToolUse do Edit não vê, e hook morto no teto antes de lançar (task 20261031-030).
    Trava de 120 s por arquivo-marcador; o da-cards.py tem flock próprio contra corrida."""
    try:
        alvo = os.path.getmtime(os.path.join(D, "cards.json"))
        led = max(os.path.getmtime(os.path.join(HOME, f)) for f in ("DECISIONS.md", "CONDUCT.md")
                  if os.path.exists(os.path.join(HOME, f)))
    except (OSError, ValueError):
        return
    marca = os.path.join(D, ".recompila")
    if led <= alvo or (os.path.exists(marca) and time.time() - os.path.getmtime(marca) < 120):
        return
    try:
        open(marca, "w").close()
        subprocess.Popen(["timeout", "300", sys.executable, os.path.join(D, "da-cards.py"), "--out", D],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError:
        pass


def main():
    if os.environ.get("ADAS_JIT", "inline") == "off":
        return
    recompila_se_velho()
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
    esc = rs().escopos(p.get("cwd") or os.getcwd(), HOME)
    cards = motor_evento(sup, alvo)
    jpm = {}
    if sup == "prompt":  # regex na frente, juiz atrás: o que o regex não previu, o juiz pega pelo sentido
        jpc, jpm = juiz_prompt(texto, {c["id"] for c in cards})
        cards += jpc
    nivel, vetor = 0, "-"
    if len(cards) < K:
        try:
            tema, nivel, vetor = motor_tema(sup, texto, alvo, esc)
        except Exception as e:
            tema, vetor = [], "erro:" + type(e).__name__
        cards += [c for c in tema if c["id"] not in {x["id"] for x in cards}]
    vp, vd = vistos(sid)
    now = time.time()
    cand, omitidos = [], []
    for c in cards:  # dedupe ANTES do juiz: cartão já visto não custa chamada
        if re.search(r"\b%s\b" % re.escape(c["id"]), texto):
            omitidos.append((c["id"], "no_payload")); continue
        if c["id"] in vd:
            omitidos.append((c["id"], "visto")); continue
        cand.append(c)
    vivos, pj, jmeta = juiz_filtra(sup, alvo, cand)
    omitidos += [(c["id"], "juiz") for c in cand if c not in vivos]
    mostrar = corta_k(vivos)
    modo = os.environ.get("ADAS_JIT", "inline")
    decisao = ("inline" if modo != "log" else "sombra") if mostrar else "silencio"
    ms = round((time.time() - t0) * 1000)
    if cards or sup == "prompt":
        ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "sid": sid, "superficie": sup, "nivel": nivel, "vetor": vetor,
                "escopo": ",".join(sorted(esc)), "decisao": decisao, "ms": ms, "payload": red(texto),
                "cartoes": [{k: c.get(k) for k in ("id", "motor", "l2", "bm25")} for c in mostrar],
                "omitidos": omitidos, **({"juiz": dict(jmeta, p=pj)} if jmeta.get("chamou") or jmeta.get("erro") or jmeta.get("motivo") else {}),
                **({"juiz_prompt": jpm} if jpm.get("chamou") or jpm.get("erro") or jpm.get("motivo") else {})})
    elif ms > 300:
        ledger({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "sid": sid, "superficie": sup, "nivel": nivel, "vetor": vetor,
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
    mae = rs().regra_mae({c["id"] for c in mostrar}, rs().grafo(D))
    try:
        pares = json.load(open(os.path.join(D, "pares.json")))
    except Exception:
        pares = {}
    for c in mostrar:  # cartão-mecanismo → a regra que ele mecaniza (DA-465 → DA-412), sinapse determinística
        linhas.append(linha_cartao(c, pares.get(c["id"]), mae.get(c["id"])))
    ev = "UserPromptSubmit" if sup == "prompt" else "PreToolUse"
    print(json.dumps({"hookSpecificOutput": {"hookEventName": ev, "additionalContext": "\n".join(linhas)}},
                     ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
