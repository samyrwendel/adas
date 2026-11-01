#!/usr/bin/env python3
"""juiz_prov.py — provedores do juiz de forma do ADAS-JIT (nível 3) e a configuração da chave sem passar pelo chat.

Provedores, na ordem de ADAS_JUIZ_ORDEM (default typesafe,openrouter,experientiallabs,gateway,openai):
  typesafe          Jev direto (TYPESAFE_API_KEY)           https://api.typesafe.ai/v1/systemone
  openrouter        Jev pela OpenRouter (OPENROUTER_API_KEY) https://openrouter.ai/api/v1/systemone
  experientiallabs  Jev pela EL (EXPERIENTIALLABS_API_KEY)   https://api.experientiallabs.ai/v1/systemone
  gateway           Jev pelo Vercel AI Gateway (AI_GATEWAY_API_KEY)
  openai            qualquer endpoint OpenAI-compatível, inclusive Ollama local: ADAS_JUIZ_OPENAI_URL
                    (ex. http://127.0.0.1:11434/v1) + ADAS_JUIZ_OPENAI_MODEL [+ ADAS_JUIZ_OPENAI_KEY]. As MESMAS
                    perguntas sim/não, pedidas como JSON {id: probabilidade de SIM}; o limiar continua por cartão.
Os quatro primeiros falam /systemone (perguntas tipadas `noul`). Falhou um, tenta o próximo; acabou o prazo → exceção
→ quem chama passa (fail-open).

De onde vem a chave (primeiro que tiver): env do processo → ~/.adas/juiz.env (KEY=VALUE, chmod 600) → os arquivos
de ADAS_JUIZ_ENVFILE (ex. o .env do Hermes; ponteiro, a chave não é copiada) → o script ADAS_JUIZ_CRED
(`<script> <provedor> value`, o cofre da instância). Sem nenhuma: juiz DESLIGADO e o nível efetivo é 2.

Chave colada no chat NUNCA é usada (DA-479): o caminho é este comando, no terminal ou pelo link de uso único.
CLI:
  juiz_prov.py status [--aviso]       sem rede; --aviso só imprime a linha de juiz desligado (SessionStart)
  juiz_prov.py testar                  uma pergunta de verdade em cada provedor configurado
  juiz_prov.py configurar [--auto]     --auto: acha as chaves que o agente já tem e grava a 1ª que FUNCIONA;
                                       sem --auto: pergunta o provedor e lê a chave escondida (getpass)
  juiz_prov.py link [--host H] [--ttl 300]   formulário local de uso único (5 min) pra quem só tem o chat"""
import getpass, json, os, re, secrets, socket, subprocess, sys, time, urllib.request

H = os.path.expanduser("~")
CONF = os.environ.get("ADAS_JUIZ_CONF") or os.path.join(H, ".adas", "juiz.env")
SYSTEMONE = {  # nome: (variável da chave, url, modelo)
    "typesafe": ("TYPESAFE_API_KEY", "https://api.typesafe.ai/v1/systemone", "jev-latest"),
    "openrouter": ("OPENROUTER_API_KEY", "https://openrouter.ai/api/v1/systemone", "jev-latest"),
    "experientiallabs": ("EXPERIENTIALLABS_API_KEY", "https://api.experientiallabs.ai/v1/systemone", "jev-latest"),
    "gateway": ("AI_GATEWAY_API_KEY", "https://ai-gateway.vercel.sh/typesafe/v1/systemone", "typesafe-ai/jev"),
}
ORDEM = "typesafe,openrouter,experientiallabs,gateway,openai"
VARS = [v[0] for v in SYSTEMONE.values()] + ["ADAS_JUIZ_OPENAI_URL", "ADAS_JUIZ_OPENAI_MODEL", "ADAS_JUIZ_OPENAI_KEY"]
CMD = "adas juiz" if __import__("shutil").which("adas") else "python3 " + os.path.realpath(__file__)


def ler_env(p):
    out = {}
    try:
        for l in open(os.path.expanduser(p), encoding="utf-8"):
            l = l.strip()
            if l and not l.startswith("#") and "=" in l:
                k, v = l.split("=", 1)
                out[k.strip().removeprefix("export ").strip()] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return out


def conf():
    return ler_env(CONF)


def valor(nome, c=None, cofre=True):
    """Variável de chave/config: env → juiz.env → ADAS_JUIZ_ENVFILE (lista com ':') → cofre (ADAS_JUIZ_CRED)."""
    c = conf() if c is None else c
    if os.environ.get(nome):
        return os.environ[nome]
    if c.get(nome):
        return c[nome]
    for f in filter(None, (os.environ.get("ADAS_JUIZ_ENVFILE") or c.get("ADAS_JUIZ_ENVFILE") or "").split(":")):
        v = ler_env(f).get(nome)
        if v:
            return v
    cred = os.environ.get("ADAS_JUIZ_CRED") or os.environ.get("JUIZ_REPLY_CRED") or c.get("ADAS_JUIZ_CRED")
    prov = {v[0]: k for k, v in SYSTEMONE.items()}.get(nome)
    if cofre and cred and prov and os.path.exists(os.path.expanduser(cred)):
        try:
            r = subprocess.run(["bash", os.path.expanduser(cred), prov, "value"], capture_output=True, text=True, timeout=2)
            return r.stdout.strip()
        except Exception:
            return ""
    return ""


def tem_cofre(c):
    cred = os.environ.get("ADAS_JUIZ_CRED") or os.environ.get("JUIZ_REPLY_CRED") or c.get("ADAS_JUIZ_CRED")
    return bool(cred and os.path.exists(os.path.expanduser(cred)))


def provedores(c=None, rede=True):
    """Lista na ordem configurada, só os que têm chave (ou URL, no openai). rede=False: não chama o cofre (rápido)."""
    c = conf() if c is None else c
    out = []
    for nome in (os.environ.get("ADAS_JUIZ_ORDEM") or c.get("ADAS_JUIZ_ORDEM") or ORDEM).replace(" ", "").split(","):
        if nome in SYSTEMONE:
            var, url, model = SYSTEMONE[nome]
            k = valor(var, c, cofre=rede) or ("cofre" if not rede and tem_cofre(c) else "")
            if k:
                out.append({"nome": nome, "tipo": "systemone", "url": url, "model": model, "key": k})
        elif nome == "openai":
            url, model = valor("ADAS_JUIZ_OPENAI_URL", c), valor("ADAS_JUIZ_OPENAI_MODEL", c)
            if url and model:
                out.append({"nome": "openai", "tipo": "openai", "url": url.rstrip("/"), "model": model,
                            "key": valor("ADAS_JUIZ_OPENAI_KEY", c)})
    return out


def _post(url, corpo, key, prazo):
    h = {"Content-Type": "application/json"}
    if key:
        h["Authorization"] = "Bearer " + key
    req = urllib.request.Request(url, data=json.dumps(corpo).encode(), headers=h)
    with urllib.request.urlopen(req, timeout=max(0.3, prazo - time.time())) as r:
        return json.loads(r.read())


def _openai(p, texto, cartoes, prazo, fmt):
    perg = "\n".join(f'- "{c["id"]}": {c["pergunta"]}' for c in cartoes)
    sis = ("Você é um juiz de FORMA de mensagens. Para cada pergunta, dê a probabilidade (0 a 1) de a resposta ser SIM "
           "para a mensagem dada. Responda SÓ um objeto JSON {\"<id>\": <número>}, sem texto fora dele.")
    d = _post(p["url"] + "/chat/completions", {
        "model": p["model"], "temperature": 0, "response_format": {"type": "json_object"},
        "messages": [{"role": "system", "content": sis},
                     {"role": "user", "content": f"Formato: {fmt or 'text'}\nMensagem:\n<<<\n{texto}\n>>>\nPerguntas:\n{perg}"}]},
        p["key"], prazo)
    t = (d.get("choices") or [{}])[0].get("message", {}).get("content") or ""
    j = json.loads(t[t.find("{"):t.rfind("}") + 1])
    ids = {c["id"] for c in cartoes}
    resp = {}
    for k, v in j.items():
        if k in ids:
            v = 1.0 if v is True else 0.0 if v is False else float(v)
            resp[k] = max(0.0, min(1.0, v))
    return resp, {"cost": (d.get("usage") or {}).get("cost"), "model": d.get("model") or p["model"]}


def perguntar(texto, cartoes, prazo, fmt=None, provs=None):
    """Uma chamada, todas as perguntas. → (respostas {id: p}, meta {prov, model, cost}) ou RuntimeError."""
    erro = None
    for p in (provs if provs is not None else provedores()):
        if prazo - time.time() < 0.3:
            break
        try:
            if p["tipo"] == "openai":
                resp, meta = _openai(p, texto, cartoes, prazo, fmt)
            else:
                q = {c["id"]: {"type": "noul", "instructions": c["pergunta"]} for c in cartoes}
                d = _post(p["url"], {"model": p["model"], "state": {"mensagem": texto, "formato": fmt or "text"},
                                     "questions": q}, p["key"], prazo)
                resp = {k: float(v.get("noul")) for k, v in (d.get("answers") or {}).items() if v.get("noul") is not None}
                meta = {"model": d.get("model"), "cost": (d.get("usage") or {}).get("cost")}
            if not resp:
                raise ValueError("sem respostas")
            return resp, dict(meta, prov=p["nome"])
        except Exception as e:
            erro = f'{p["nome"]}: {type(e).__name__}: {str(e)[:80]}'
    raise RuntimeError(erro or "sem provedor configurado")


# ───────────────────────── status / aviso ─────────────────────────
def nivel():
    """Nível do ADAS-JIT (DA-468): env ADAS_JIT_NIVEL (fixo) → nivel.fixo (fixação manual) → nivel (termostato) → 3."""
    v = os.environ.get("ADAS_JIT_NIVEL")
    for f in ("nivel.fixo", "nivel"):
        if v:
            break
        try:
            v = open(os.path.join(os.environ.get("ADAS_JIT_DIR") or os.path.join(H, ".adas", "jit"), f)).read().strip()
        except OSError:
            v = None
    return int(v) if v and v.isdigit() else 3


def aviso():
    """Linha do SessionStart quando o nível pede juiz (3) e não há chave. Sem rede, sem cofre."""
    if nivel() < 3 or provedores(rede=False):
        return ""
    return ("Juiz DESLIGADO: sem chave — nível 2 (regras chegam, mas ninguém lê a resposta antes de sair). "
            f"Pra ligar: {CMD} configurar --auto (acha a chave que você já tem) · {CMD} configurar (cola escondido no "
            f"terminal) · {CMD} link (formulário de uso único). Chave colada no chat não é usada.")


# ───────────────────────── configurar ─────────────────────────
TESTE = [{"id": "t", "pergunta": "A mensagem é um cumprimento?"}]


def funciona(p):
    try:
        perguntar("bom dia!", TESTE, time.time() + 12, provs=[p])
        return True
    except Exception as e:
        print(f"  · {p['nome']} não respondeu: {str(e)[:100]}")
        return False


def gravar(linhas):
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    tmp = CONF + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("# juiz do ADAS-JIT — gerado por juiz_prov.py configurar. Nunca commitar.\n" + "\n".join(linhas) + "\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, CONF)


def candidatos():
    """Chaves que o agente JÁ tem: env do processo (Claude Code), .env do Hermes, cofre da instância, Ollama local."""
    hermes = [f for f in (os.path.join(os.environ.get("HERMES_HOME", "/opt/data"), ".env"), os.path.join(H, ".hermes", ".env"))
              if os.path.exists(f)]
    out = []
    for nome, (var, url, model) in SYSTEMONE.items():
        if os.environ.get(var):
            out.append(({"nome": nome, "tipo": "systemone", "url": url, "model": model, "key": os.environ[var]},
                        [f"ADAS_JUIZ_ORDEM={nome}"], f"{var} do ambiente"))
        for f in hermes:
            if ler_env(f).get(var):
                out.append(({"nome": nome, "tipo": "systemone", "url": url, "model": model, "key": ler_env(f)[var]},
                            [f"ADAS_JUIZ_ORDEM={nome}", f"ADAS_JUIZ_ENVFILE={f}"], f"{var} em {f}"))
    cred = os.environ.get("ADAS_JUIZ_CRED") or os.environ.get("JUIZ_REPLY_CRED")
    if cred and os.path.exists(cred):
        for nome, (var, url, model) in SYSTEMONE.items():
            k = valor(var, {"ADAS_JUIZ_CRED": cred})
            if k:
                out.append(({"nome": nome, "tipo": "systemone", "url": url, "model": model, "key": k},
                            [f"ADAS_JUIZ_ORDEM={nome}", f"ADAS_JUIZ_CRED={cred}"], f"cofre {cred}"))
    oll = os.environ.get("ADAS_OLLAMA_BASE", "http://127.0.0.1:11434")
    try:
        with urllib.request.urlopen(oll + "/api/tags", timeout=1.5) as r:
            ms = [m["name"] for m in json.loads(r.read()).get("models", []) if "embed" not in m["name"]]
        if ms:
            out.append(({"nome": "openai", "tipo": "openai", "url": oll + "/v1", "model": ms[0], "key": ""},
                        ["ADAS_JUIZ_ORDEM=openai", f"ADAS_JUIZ_OPENAI_URL={oll}/v1", f"ADAS_JUIZ_OPENAI_MODEL={ms[0]}"],
                        f"Ollama local ({ms[0]})"))
    except Exception:
        pass
    return out


def configurar_auto():
    cs = candidatos()
    if not cs:
        print("Nenhuma chave encontrada (env, .env do Hermes, cofre, Ollama). Use: configurar (sem --auto) ou link.")
        return 1
    for p, linhas, origem in cs:
        print(f"• testando {p['nome']} ({origem})…")
        if funciona(p):
            gravar(linhas)
            print(f"✓ juiz LIGADO: {p['nome']} ({origem}). Gravado em {CONF} (600, só o ponteiro quando a chave mora em outro lugar).")
            return 0
    print("Nenhuma das chaves encontradas respondeu. Use: configurar (sem --auto) ou link.")
    return 1


def salvar_chave(prov, chave, url="", model=""):
    """Grava, testa e devolve (ok, msg). Chave só em ~/.adas/juiz.env (600); nunca em log nem na saída."""
    if prov in SYSTEMONE:
        var, u, m = SYSTEMONE[prov]
        p = {"nome": prov, "tipo": "systemone", "url": u, "model": m, "key": chave.strip()}
        linhas = [f"ADAS_JUIZ_ORDEM={prov}", f"{var}={chave.strip()}"]
    elif prov == "openai" and url and model:
        p = {"nome": "openai", "tipo": "openai", "url": url.rstrip("/"), "model": model, "key": chave.strip()}
        linhas = ["ADAS_JUIZ_ORDEM=openai", f"ADAS_JUIZ_OPENAI_URL={url.rstrip('/')}", f"ADAS_JUIZ_OPENAI_MODEL={model}"]
        if chave.strip():
            linhas.append(f"ADAS_JUIZ_OPENAI_KEY={chave.strip()}")
    else:
        return False, "provedor desconhecido (ou openai sem URL/modelo)"
    if not funciona(p):
        return False, f"a chave de {prov} não respondeu — nada foi gravado"
    gravar(linhas)
    return True, f"juiz LIGADO ({prov}), gravado em {CONF}"


def configurar_tty():
    nomes = list(SYSTEMONE) + ["openai"]
    print("Provedor do juiz:\n" + "\n".join(f"  {i}) {n}" for i, n in enumerate(nomes, 1)))
    try:
        prov = nomes[int(input("número: ").strip()) - 1]
    except (ValueError, IndexError, EOFError):
        print("cancelado"); return 1
    url = model = ""
    if prov == "openai":
        url = input("URL base (ex. http://127.0.0.1:11434/v1): ").strip()
        model = input("modelo: ").strip()
    chave = getpass.getpass("chave (não aparece; vazio se o endpoint não pede): ")
    ok, msg = salvar_chave(prov, chave, url, model)
    print(("✓ " if ok else "✗ ") + msg)
    return 0 if ok else 1


# ───────────────────────── link de uso único ─────────────────────────
FORM = """<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width"><title>ADAS · juiz</title>
<body style="font:16px system-ui;max-width:28em;margin:2em auto;padding:0 1em">
<h3>Chave do juiz do ADAS</h3><p>Uso único, vale 5 min. A chave vai direto pro arquivo local
(<code>~/.adas/juiz.env</code>, permissão 600) e é testada. Não passa pelo chat.</p>
<form method=post><label>Provedor<br><select name=prov>%s</select></label><br><br>
<label>Chave<br><input name=chave type=password autocomplete=off style="width:100%%"></label><br><br>
<details><summary>OpenAI-compatível / Ollama</summary><input name=url placeholder="http://127.0.0.1:11434/v1" style="width:100%%">
<input name=model placeholder="modelo" style="width:100%%"></details><br><button>Salvar e testar</button></form>"""


def servir(bind, porta, token, ttl):
    import http.server, urllib.parse
    fim = time.time() + ttl
    estado = {"usado": False}

    class Hd(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _ok(self, corpo, cod=200):
            b = corpo.encode()
            self.send_response(cod); self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(b)))
            self.end_headers(); self.wfile.write(b)

        def _valido(self):
            return not estado["usado"] and time.time() < fim and secrets.compare_digest(self.path.split("?")[0], "/" + token)

        def do_GET(self):
            if not self._valido():
                return self._ok("link vencido ou já usado", 410)
            self._ok(FORM % "".join(f"<option>{n}</option>" for n in list(SYSTEMONE) + ["openai"]))

        def do_POST(self):
            if not self._valido():
                return self._ok("link vencido ou já usado", 410)
            estado["usado"] = True  # uso único: a 1ª tentativa queima o link, deu certo ou não
            n = int(self.headers.get("Content-Length") or 0)
            f = {k: v[0] for k, v in urllib.parse.parse_qs(self.rfile.read(min(n, 20000)).decode()).items()}
            ok, msg = salvar_chave(f.get("prov", ""), f.get("chave", ""), f.get("url", ""), f.get("model", ""))
            self._ok(("✓ " if ok else "✗ ") + msg + ("" if ok else ". Gere outro link."))

    srv = http.server.HTTPServer((bind, porta), Hd)  # síncrono: a resposta sai ANTES do loop ver o link queimado
    srv.timeout = 1
    while time.time() < fim and not estado["usado"]:
        srv.handle_request()



def link(host=None, ttl=300):
    """Escuta SÓ no endereço do link (127.0.0.1 por padrão; IP da tailnet com --host): nunca em 0.0.0.0."""
    host = host or os.environ.get("ADAS_JUIZ_LINK_HOST") or "127.0.0.1"
    s = socket.socket(); s.bind((host, 0)); porta = s.getsockname()[1]; s.close()
    token = secrets.token_urlsafe(18)
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "_servir", host, str(porta), token, str(ttl)],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    url = f"http://{host}:{porta}/{token}"
    print(url)
    return url


def main(a):
    cmd = a[0] if a else "status"
    if cmd == "status":
        if "--aviso" in a:
            av = aviso()
            if av:
                print(av)
            return 0
        ps = provedores(rede=False)
        print(("juiz: " + ", ".join(p["nome"] for p in ps)) if ps else aviso())
        return 0
    if cmd == "testar":
        ps = provedores()
        if not ps:
            print(aviso()); return 1
        ok = [p["nome"] for p in ps if funciona(p)]
        print("✓ responderam: " + ", ".join(ok) if ok else "✗ nenhum provedor respondeu")
        return 0 if ok else 1
    if cmd == "configurar":
        return configurar_auto() if "--auto" in a else configurar_tty()
    if cmd == "link":
        link(a[a.index("--host") + 1] if "--host" in a else None, int(a[a.index("--ttl") + 1]) if "--ttl" in a else 300)
        return 0
    if cmd == "_servir":
        servir(a[1], int(a[2]), a[3], int(a[4]))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
