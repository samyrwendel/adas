#!/usr/bin/env python3
"""ADAS 1.1.1 — juiz sem chave avisa, provedores do juiz, chave sem chat, termostato, chave colada no Hermes,
gatilho com superfície em lista. Sem rede: provedores falsos num servidor HTTP local. Rodado pelo smoke.sh."""
import datetime, http.server, json, os, subprocess, sys, tempfile, threading, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
J = os.path.join(ROOT, "host", "jit")
T = tempfile.mkdtemp(prefix="adas111-")
ok = bad = 0


def chk(nome, cond, extra=""):
    global ok, bad
    print(("  ✓ " if cond else "  ✗ ") + nome + (f"  [{str(extra)[:200]}]" if extra and not cond else ""))
    ok += bool(cond); bad += (not cond)


# ── provedores falsos: /bom/systemone responde, /ruim/systemone dá 500, /v1/chat/completions (OpenAI) responde JSON
CHAMADAS = []
class Fake(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"models":[]}')
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0); corpo = json.loads(self.rfile.read(n) or b"{}")
        CHAMADAS.append((self.path, self.headers.get("Authorization"), corpo))
        if self.path.startswith("/ruim"):
            self.send_response(500); self.end_headers(); return
        if self.path.endswith("/chat/completions"):
            u = corpo["messages"][-1]["content"]
            msg = u.split("<<<", 1)[-1].split(">>>", 1)[0]
            ids = __import__("re").findall(r'- "([^"]+)":', u)
            r = {"choices": [{"message": {"content": json.dumps({**{i: 0.95 if "Stormer" in msg else 0.05 for i in ids}, "estranho": 1})}}]}
        else:
            r = {"model": "jev-fake", "answers": {k: {"noul": 0.9} for k in corpo["questions"]}}
        b = json.dumps(r).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(b)

srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_address[1]}"

LIMPO = {k: v for k, v in os.environ.items() if not any(s in k for s in ("API_KEY", "JUIZ", "ADAS_JIT_NIVEL", "HERMES_HOME"))}


def run(args, env=None, inp=None, timeout=30):
    e = dict(LIMPO, HOME=T, **(env or {}))
    return subprocess.run(args, input=inp, capture_output=True, text=True, env=e, timeout=timeout)


sys.path.insert(0, J)
os.environ.clear(); os.environ.update(LIMPO, HOME=T)
import juiz_prov as jp  # noqa: E402
jp.H = T; jp.CONF = os.path.join(T, ".adas", "juiz.env")
# HOME falso não tem o redator da instância (claude-tg-tmux); desde a e753230 o juiz é fail-closed sem ele.
# Redator falso: identidade, só pra exercitar provedores. O fail-closed é provado logo abaixo.
STUB = os.path.join(T, "redator-falso.py")
open(STUB, "w").write("def carregar_segredos():\n    return []\ndef redigir(t, s):\n    return t, 0\n")
jp.REDATOR = os.path.join(T, "nao-existe.py")
try:
    jp.perguntar("x", [{"id": "DA-1", "pergunta": "p"}], time.time() + 5, provs=[]); _fc = False
except RuntimeError as e:
    _fc = "redator indisponível" in str(e)
jp.REDATOR = STUB; LIMPO["ADAS_REDATOR"] = STUB  # subprocessos (juiz-reply, configurar) também

print("== juiz: provedores e chave sem chat (task 20261101-001, DA-479)")
chk("sem redator o texto não sai: RuntimeError antes de qualquer provedor (e753230)", _fc)
CART = [{"id": "DA-1", "pergunta": "chama o setup de Stormer?"}]
ps = [{"nome": "typesafe", "tipo": "systemone", "url": BASE + "/ruim/systemone", "model": "jev-latest", "key": "k1"},
      {"nome": "openrouter", "tipo": "systemone", "url": BASE + "/bom/systemone", "model": "jev-latest", "key": "k2"}]
r, m = jp.perguntar("o 123 Stormer", CART, time.time() + 5, provs=ps)
chk("systemone: 1º provedor falha (500) → cai no 2º, mesma pergunta tipada noul", m["prov"] == "openrouter" and r == {"DA-1": 0.9}
    and CHAMADAS[-1][2]["questions"]["DA-1"]["type"] == "noul", (m, r))
oa = [{"nome": "openai", "tipo": "openai", "url": BASE + "/v1", "model": "qualquer", "key": ""}]
r1, _ = jp.perguntar("o 123 Stormer no BTC", CART, time.time() + 5, provs=oa)
r2, _ = jp.perguntar("bom dia", CART, time.time() + 5, provs=oa)
chk("OpenAI-compatível (Ollama/qualquer): JSON {id: p}, id desconhecido descartado, sem chave = sem Authorization",
    r1 == {"DA-1": 0.95} and r2 == {"DA-1": 0.05} and CHAMADAS[-1][1] is None, (r1, r2))
try:
    jp.perguntar("x", CART, time.time() + 5, provs=[ps[0]]); falhou = False
except RuntimeError:
    falhou = True
chk("todos falham → RuntimeError (quem chama faz fail-open)", falhou)

# ordem e origem da chave
cf = os.path.join(T, ".adas", "juiz.env"); os.makedirs(os.path.dirname(cf), exist_ok=True)
herm = os.path.join(T, "hermes.env"); open(herm, "w").write("OPENROUTER_API_KEY=da-hermes\n")
open(cf, "w").write(f"ADAS_JUIZ_ORDEM=openai,openrouter\nADAS_JUIZ_ENVFILE={herm}\nADAS_JUIZ_OPENAI_URL={BASE}/v1\nADAS_JUIZ_OPENAI_MODEL=m\n")
pv = jp.provedores()
chk("ordem configurável (ADAS_JUIZ_ORDEM) e chave por ponteiro pro .env do Hermes (não copiada)",
    [p["nome"] for p in pv] == ["openai", "openrouter"] and pv[1]["key"] == "da-hermes" and "da-hermes" not in open(cf).read(), pv)
os.remove(cf)
chk("produto sem default de caminho da instância (claude-tg-tmux)", "claude-tg-tmux" not in open(os.path.join(J, "juiz_prov.py")).read()
    and "claude-tg-tmux" not in open(os.path.join(J, "juiz-reply.py")).read())

# aviso de juiz desligado
o = run(["python3", os.path.join(J, "juiz_prov.py"), "status", "--aviso"]).stdout
chk("sem chave + nível 3 → 'Juiz DESLIGADO: sem chave — nível 2' com o comando de ligar", "Juiz DESLIGADO: sem chave — nível 2" in o and "configurar" in o, o)
o = run(["python3", os.path.join(J, "juiz_prov.py"), "status", "--aviso"], {"ADAS_JIT_NIVEL": "2"}).stdout
chk("nível 2 fixado → sem aviso (o juiz não foi pedido)", o.strip() == "", o)
o = run(["python3", os.path.join(J, "juiz_prov.py"), "status", "--aviso"], {"OPENROUTER_API_KEY": "x"}).stdout
chk("com chave → silêncio", o.strip() == "", o)
os.makedirs(os.path.join(T, ".claude", "adas"), exist_ok=True)
open(os.path.join(T, ".claude", "adas", "source"), "w").write(ROOT)
o = run(["bash", os.path.join(ROOT, "host", "adas-activate.sh")], {"ADAS_VERSION_CHECK": "off", "ADAS_JIT_NIVEL": "3"}, inp="{}").stdout
chk("SessionStart (adas-activate.sh) mostra o aviso em linha própria", "\nJuiz DESLIGADO" in o, o[-300:])

# juiz-reply sem chave: fail-open; com provedor falso: aviso
rub = os.path.join(T, "rub.json")
json.dump({"cartoes": [{"id": "DA-1", "pergunta": "x?", "regra_curta": "y", "conserto": "z", "limiar": 0.8, "modo": "aviso"}], "hooks": []}, open(rub, "w"))
pl = json.dumps({"hook_event_name": "PreToolUse", "tool_name": "mcp__plugin_telegram_telegram__reply", "tool_input": {"chat_id": "1", "text": "o 123 Stormer", "format": "text"}})
e = {"JUIZ_REPLY_RUBRICA": rub, "JUIZ_REPLY_LEDGER": os.path.join(T, "j.log"), "JUIZ_REPLY_CACHE": os.path.join(T, "c.json")}
r = run(["python3", os.path.join(J, "juiz-reply.py")], e, inp=pl)
chk("juiz-reply sem chave: sai 0 sem saída (mensagem passa)", r.returncode == 0 and not r.stdout.strip(), r.stdout)
open(cf, "w").write(f"ADAS_JUIZ_ORDEM=openai\nADAS_JUIZ_OPENAI_URL={BASE}/v1\nADAS_JUIZ_OPENAI_MODEL=m\n")
r = run(["python3", os.path.join(J, "juiz-reply.py")], dict(e, JUIZ_REPLY_CACHE=os.path.join(T, "c2.json")), inp=pl)
chk("juiz-reply com provedor OpenAI-compatível → aviso do cartão, limiar do cartão", "DA-1" in r.stdout and "aviso" in r.stdout, r.stdout)
os.remove(cf)

# configurar por função (o mesmo que o terminal e o link chamam): testa antes de gravar, 600
okk, msg = jp.salvar_chave("openai", "segredo-x", BASE + "/v1", "m")
st = os.stat(cf).st_mode & 0o777 if os.path.exists(cf) else None
chk("salvar_chave: testa, grava ~/.adas/juiz.env com permissão 600", okk and st == 0o600, (msg, oct(st or 0)))
os.remove(cf)
jp.SYSTEMONE["falso"] = ("FALSO_API_KEY", BASE + "/ruim/systemone", "jev")
okk, msg = jp.salvar_chave("falso", "k-ruim")
chk("chave que não responde → nada é gravado", okk is False and not os.path.exists(cf), msg)
del jp.SYSTEMONE["falso"]

# autodetecção: .env do Hermes e Ollama local
os.makedirs(os.path.join(T, ".hermes"), exist_ok=True)
open(os.path.join(T, ".hermes", ".env"), "w").write("OPENROUTER_API_KEY=chave-do-hermes\n")
r = run(["python3", "-c", f"""
import sys; sys.path.insert(0, {J!r}); import juiz_prov as jp
jp.SYSTEMONE = {{"openrouter": ("OPENROUTER_API_KEY", {BASE!r} + "/bom/systemone", "jev-latest")}}
sys.exit(jp.configurar_auto())"""], {"ADAS_OLLAMA_BASE": BASE + "/nada"})
c = open(cf).read() if os.path.exists(cf) else ""
chk("configurar --auto acha a chave no .env do Hermes, testa e grava só o PONTEIRO", r.returncode == 0
    and f"ADAS_JUIZ_ENVFILE={T}/.hermes/.env" in c and "chave-do-hermes" not in c, r.stdout + c)
os.remove(cf); os.remove(os.path.join(T, ".hermes", ".env"))

# provedores que o AGENTE já tem (Hermes/OpenClaw/Codex), lidos na hora — nada copiado
hh = os.path.join(T, "hh"); os.makedirs(hh, exist_ok=True)
open(os.path.join(hh, ".env"), "w").write("ROUTER_KEY=chave-do-router\n")
open(os.path.join(hh, "config.yaml"), "w").write(f"""model:
  default: "modelo-barato"   # comentário
  provider: "custom"
  base_url: "{BASE}/v1"
custom_providers:
  - name: roteador
    base_url: "{BASE}/v1"
    key_env: ROUTER_KEY
    model: "modelo-barato"
    models:
      - modelo-barato
""")
pv = jp.provs_de_fonte("hermes:" + os.path.join(hh, "config.yaml"))
chk("Hermes config.yaml: custom_providers + key_env do .env → provedor OpenAI-compatível com a chave lida na hora",
    any(p["via"] == "hermes roteador" and p["key"] == "chave-do-router" and p["model"] == "modelo-barato" for p in pv), pv)
r = run(["python3", os.path.join(J, "juiz_prov.py"), "configurar", "--auto"], {"HERMES_HOME": hh, "ADAS_OLLAMA_BASE": BASE + "/nada"})
c = open(cf).read() if os.path.exists(cf) else ""
chk("configurar --auto reusa o provedor do Hermes: grava FONTE (ponteiro), nunca a chave", r.returncode == 0
    and "ADAS_JUIZ_FONTE=hermes:" in c and "chave-do-router" not in c, r.stdout + c)
r = run(["python3", os.path.join(J, "juiz-reply.py")], dict(e, JUIZ_REPLY_CACHE=os.path.join(T, "c3.json")), inp=pl)
chk("juiz-reply usa o provedor do Hermes → aviso", "DA-1" in r.stdout, r.stdout)
os.remove(cf)
oc = os.path.join(T, "openclaw.json")
json.dump({"env": {"MINHA_CHAVE": "do-openclaw"}, "models": {"providers": {"meu": {"baseUrl": BASE + "/v1", "apiKey": "${MINHA_CHAVE}",
           "models": [{"id": "glm-barato"}]}, "or": {"baseUrl": "https://openrouter.ai/api/v1", "apiKey": "k-or", "models": [{"id": "x"}]}}}}, open(oc, "w"))
pv = jp.provs_de_fonte("openclaw:" + oc)
chk("OpenClaw openclaw.json: models.providers (apiKey ${VAR} do bloco env) + OpenRouter vira Jev primeiro",
    any(p["via"] == "openclaw meu" and p["key"] == "do-openclaw" and p["model"] == "glm-barato" for p in pv)
    and any(p["nome"] == "openrouter" and p["tipo"] == "systemone" and p["key"] == "k-or" for p in pv), pv)
cx = os.path.join(T, "config.toml")
open(cx, "w").write(f'model = "m"\n[model_providers.oauth]\nbase_url = "{BASE}/v1"\n[model_providers.chave]\nbase_url = "{BASE}/v1"\nenv_key = "CX_KEY"\n')
os.environ["CX_KEY"] = "do-codex"
pv = jp.provs_de_fonte("codex:" + cx)
chk("Codex config.toml: provedor com env_key entra; login OAuth (sem chave) fica de fora (DA-006)",
    [p["via"] for p in pv] == ["codex chave"] and pv[0]["key"] == "do-codex", pv)
del os.environ["CX_KEY"]

hg = os.path.join(T, "hg"); os.makedirs(os.path.join(hg, "governanca"))
r = run(["python3", "-c", f"import sys; sys.path.insert(0, {J!r}); import juiz_prov; print(juiz_prov.CONF)"], {"HERMES_HOME": hg})
chk("no Hermes a config do juiz mora em $HERMES_HOME/governanca/juiz.env (volume persistente)",
    r.stdout.strip() == os.path.join(hg, "governanca", "juiz.env"), r.stdout + r.stderr)

# link de uso único
r = run(["python3", os.path.join(J, "juiz_prov.py"), "link", "--ttl", "20"])
url = r.stdout.strip()
time.sleep(1.2)
def get(u, data=None):
    try:
        with urllib.request.urlopen(urllib.request.Request(u, data=data), timeout=10) as x:
            return x.status, x.read().decode()
    except urllib.error.HTTPError as x:
        return x.code, ""
    except urllib.error.URLError:
        return 0, ""  # servidor já saiu: link queimado
s1, b1 = get(url.rsplit("/", 1)[0] + "/token-errado")
s2, b2 = get(url)
chk("link: escuta em 127.0.0.1, token errado = 410, token certo = formulário", url.startswith("http://127.0.0.1:") and s1 == 410
    and s2 == 200 and "type=password" in b2, (url, s1, s2))
import urllib.parse
s3, b3 = get(url, urllib.parse.urlencode({"prov": "openai", "chave": "", "url": BASE + "/v1", "model": "m"}).encode())
s4, _ = get(url)
chk("link: envio testa e grava a chave; o link queima (2º acesso = recusado)", s3 == 200 and "LIGADO" in b3 and s4 in (0, 410)
    and "ADAS_JUIZ_OPENAI_URL" in (open(cf).read() if os.path.exists(cf) else ""), (s3, b3, s4))
if os.path.exists(cf): os.remove(cf)

print("== termostato do nível (DA-468)")
H2 = os.path.join(T, "h2"); os.makedirs(os.path.join(H2, ".claude", "bus"))
repo = os.path.join(H2, "repo"); os.makedirs(repo)
def g(*c, autor="a"):
    subprocess.run(["git", "-C", repo, *c], capture_output=True, env=dict(LIMPO, GIT_AUTHOR_NAME=autor, GIT_COMMITTER_NAME=autor,
                   GIT_AUTHOR_EMAIL="a@x", GIT_COMMITTER_EMAIL="a@x"))
g("init", "-q")
open(os.path.join(repo, "a.py"), "w").write("print(1)\n"); g("add", "."); g("commit", "-qm", "x")
def diario(n):
    open(os.path.join(H2, "DECISIONS.md"), "w").write("".join(f"## DA-{i:03d} — x\n**Regra:** y\n" for i in range(1, n + 1)))
def termo(*extra, env=None):
    r = run(["python3", os.path.join(J, "termostato.py"), "--home", H2, "--repos", repo, "--json", *extra],
            dict(env or {}, ADAS_JIT_BUS=os.path.join(H2, ".claude", "bus")))
    return json.loads(r.stdout or "{}")
diario(10); chk("10 DAs, 1 autor, sem risco → nível 1", termo().get("nivel") == 1)
diario(60); chk(">50 DAs → nível 2", termo().get("nivel") == 2)
diario(210); chk(">200 DAs → nível 3", termo().get("nivel") == 3)
diario(10)
open(os.path.join(repo, "pag.py"), "w").write("def cobrar(): pix()\n"); g("add", "."); g("commit", "-qm", "y", autor="b")
chk("código toca dinheiro + 2º agente no repo → nível 3", termo().get("nivel") == 3)
g("rm", "-q", "pag.py"); g("commit", "-qm", "z")
hoje = datetime.date.today()
open(os.path.join(H2, ".claude", "bus", "juiz-reply.log"), "w").write(json.dumps({"ts": f"{hoje}T10:00:00", "decisao": "aviso"}) + "\n")
chk("achado do juiz há < 30 dias → nível 3", termo().get("nivel") == 3)
depois = (hoje + datetime.timedelta(days=31)).isoformat()
r = termo("--agora", depois)
chk("31 dias sem achado (e sem 2º agente na janela) → DESCE", r.get("nivel") == 1, r)
open(os.path.join(H2, ".adas", "jit", "nivel.fixo"), "w").write("3")
r = termo("--agora", depois)
chk("fixação manual (nivel.fixo) vence o automático", r.get("nivel") == 3 and r.get("automatico") == 1 and r.get("fixo") == "nivel.fixo", r)
st = json.load(open(os.path.join(H2, ".adas", "jit", "termostato.json")))
mud = run(["python3", os.path.join(J, "termostato.py"), "mudancas", "--dias", "400", "--home", H2, "--agora", depois]).stdout
chk("toda mudança vai pro histórico e sai no relatório da semana", len(st["historico"]) >= 4 and "→" in mud, mud)
chk("nível automático gravado em ~/.adas/jit/nivel (o fixo não sobrescreve)", open(os.path.join(H2, ".adas", "jit", "nivel")).read().strip() == "1")

print("== chave colada no Hermes (DA-479)")
HJ = os.path.join(T, "hj"); os.makedirs(os.path.join(HJ, "governanca"))
open(os.path.join(HJ, "governanca", "padrao.md"), "w").write("## DA-900 — x\n**Regra:** y.\n")
pre = lambda msg: run(["python3", os.path.join(J, "hermes-jit.py")], {"HERMES_HOME": HJ, "ADAS_JUIZ_CONF": os.path.join(T, "nada.env")},
                      inp=json.dumps({"hook_event_name": "pre_llm_call", "session_id": "s", "extra": {"user_message": msg}})).stdout
o = pre("toma minha chave: sk-or-v1-" + "a1b2c3d4" * 5)
chk("mensagem com chave colada → aviso: não usar, revogar, link de uso único", "REVOGADA" in o and "uso único" in o, o)
chk("conversa comum → sem aviso de chave", "REVOGADA" not in pre("bom dia, tudo certo?"))

print(f"RESULTADO 1.1.1: {ok} ok, {bad} falha(s)")
srv.shutdown()
sys.exit(1 if bad else 0)
