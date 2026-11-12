#!/usr/bin/env bash
# adas-jit-test.sh — roda TODAS as fixtures de gatilho pelos hooks (ADAS-JIT F2, DA-468; proposta do
# seniorbot §5.4). Uma fixture por regra: <FIXDIR>/DA-NNN.jsonl (ou DC-NNN.jsonl), uma linha por caso:
#   {"nome": "...", "espera": "deny|aviso|passa", "payload": {stdin do hook}, "env": {...}, "transcript": [linhas]}
# Placeholders em payload/env: {HOME} (HOME isolado do teste) · {REAL_HOME} · {TRANSCRIPT} (arquivo com
# as linhas de "transcript").
# O hook que roda é o que o DIÁRIO declara AGORA (`da-index.sh gatilhos` → da-cards.py num dir temporário):
#   gatilho com hook=<guard>  → o guard (~/.claude/hooks/<guard>)
#   gatilho com quando=/re/   → regra-jit.py (motor de evento)
#   sem gatilho               → regra-jit.py (só tema) — fixture de deny/aviso FALHA: é a prova de que
#                               remover o cartão quebra a regra (regra da DA-376).
# Também cobra: todo gatilho hook=/quando= TEM fixture (sem ela, FAIL) e o SessionStart não corta (prova 4).
# Task 20261031-031 (T1–T6): recompilação por shell até o regras.db, escopo por cwd, vetor morto no ledger,
# adesão por viola=, copiar-guard 1× por reply, regra-mãe no grafo. T7 (juiz, rede): --juiz.
# Uso: adas-jit-test.sh [--sem DA-NNN ...] [--fixtures DIR]   (--sem simula a remoção do cartão sem tocar o
#      diário append-only). Exit 0 = tudo verde.
set -uo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"; JD="$(dirname "$SELF")"
REAL_HOME="$HOME"
FIXDIR="${ADAS_FIXTURES:-$HOME/.adas/fixtures}"
SEM=(); JUIZ=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sem) SEM+=("$2"); shift ;;
    --fixtures) FIXDIR="$2"; shift ;;
    --juiz) JUIZ=1 ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac; shift
done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/jit" "$T/home/.claude/bus"
python3 "$JD/da-cards.py" --so-juiz --out "$T/jit" >/dev/null || { echo "✗ da-cards.py falhou"; exit 1; }
for f in regras.db regra-search da-cards.py grafo.json; do ln -s "$HOME/.adas/jit/$f" "$T/jit/$f" 2>/dev/null; done

JUIZ="$JUIZ" SEM_CSV="$(IFS=,; echo "${SEM[*]:-}")" T="$T" FIXDIR="$FIXDIR" JD="$JD" REAL_HOME="$REAL_HOME" python3 - <<'PY'
import glob, json, os, subprocess, sys
T, FIX, JD, RH = os.environ["T"], os.environ["FIXDIR"], os.environ["JD"], os.environ["REAL_HOME"]
sem = {s for s in os.environ.get("SEM_CSV", "").split(",") if s}
gp = os.path.join(T, "jit", "gatilhos.json")
todos = json.load(open(gp))
json.dump([g for g in todos if g["id"] not in sem], open(gp, "w"), ensure_ascii=False)  # --sem tira também o quando= que o regra-jit lê
gs = {g["id"]: g["gatilho"] for g in todos if g["id"] not in sem}
H = os.path.join(T, "home")
os.environ["ADAS_JIT_JUIZ"] = "off"  # filtro do juiz (rede) fora das fixtures; ele tem bloco próprio abaixo
ok = bad = 0
def chk(nome, cond, extra=""):
    global ok, bad
    print(("  ✓ " if cond else "  ✗ ") + nome + (f"  [{extra}]" if extra and not cond else ""))
    ok += bool(cond); bad += (not cond)
def sub(o, tr):
    s = json.dumps(o, ensure_ascii=False).replace("{HOME}", H).replace("{REAL_HOME}", RH).replace("{TRANSCRIPT}", tr)
    return json.loads(s)
def hook_cmd(g):
    if g and g.get("hook"):
        h = os.path.expanduser(g["hook"]); h = h if os.path.isabs(h) else os.path.join(RH, ".claude/hooks", h)
        return (["python3", h] if h.endswith(".py") else ["bash", h]), os.path.basename(h)
    return ["python3", os.path.join(JD, "regra-jit.py")], "regra-jit.py"
def veredito(out, rc, rid, via):
    if rc == 2: return "deny"
    o = {}
    for cand in (out.strip(), (out.strip().splitlines() or [""])[-1]):  # jq pretty (várias linhas) ou 1 linha no fim
        try:
            o = json.loads(cand); break
        except Exception:
            continue
    hs = o.get("hookSpecificOutput") or {}
    if hs.get("permissionDecision") == "deny" or o.get("decision") == "block": return "deny"
    ctx = hs.get("additionalContext") or ""
    vis = rid if ":" not in rid else "%s (%s)" % (rid.split(":", 1)[1], rid.split(":", 1)[0])  # D-C3: cartão da casa aparece como "DA-066 (nest-egg)"
    if ctx and (via != "regra-jit.py" or rid in ctx or vis in ctx): return "aviso"
    return "passa"

arqs = sorted(glob.glob(os.path.join(FIX, "D[AC]-*.jsonl")) + [x for x in glob.glob(os.path.join(FIX, "*:D[AC]-*.jsonl")) if not os.path.basename(x).startswith("juiz-")])  # D-C3: <casa>:DA-NNN.jsonl
print(f"── fixtures ({len(arqs)} regra(s) em {FIX}) ──")
for a in arqs:
    rid = os.path.basename(a)[:-6]
    g = gs.get(rid)
    cmd, via = hook_cmd(g)
    for n, l in enumerate(open(a, encoding="utf-8"), 1):
        if not l.strip(): continue
        c = json.loads(l)
        tr = os.path.join(T, f"tr-{rid}-{n}.jsonl")
        open(tr, "w").write("\n".join(json.dumps(x, ensure_ascii=False) for x in c.get("transcript", [])) + "\n")
        env = dict(os.environ, HOME=H, ADAS_JIT_DIR=os.path.join(T, "jit"), ADAS_JIT_BUS=os.path.join(H, ".claude/bus", f"{rid}-{n}"),
                   ADAS_JIT="inline", ADAS_JIT_OWNER="111", ADMIN_CHAT_ID="111")  # dono sintético; estado JIT por caso
        env.pop("AXON_HEADLESS", None)
        env.update(sub(c.get("env") or {}, tr))
        try:
            r = subprocess.run(cmd, input=json.dumps(sub(c["payload"], tr), ensure_ascii=False), capture_output=True,
                               text=True, env=env, timeout=20)
            v = veredito(r.stdout, r.returncode, rid, via)
        except Exception as e:
            v = f"erro {e.__class__.__name__}"
        chk(f"{rid} via {via}: {c.get('nome', n)} → {c['espera']}", v == c["espera"], f"veio {v}")

print("── todo gatilho de máquina tem fixture (DA-376) ──")
com = {os.path.basename(a)[:-6] for a in arqs}
for rid, g in sorted(gs.items()):
    if g.get("hook") or g.get("quando"):
        chk(f"{rid} ({g.get('tipo')}·{g.get('superficie')}·{'hook=' + g['hook'] if g.get('hook') else 'quando'}) tem fixture", rid in com)

print("── recompilação segue o diário (task 20261031-030) ──")
rj, rh = os.path.join(T, "rc", "jit"), os.path.join(T, "rc", "home")
os.makedirs(rj); os.makedirs(rh)
open(os.path.join(rj, "cards.json"), "w").write("[]"); os.utime(os.path.join(rj, "cards.json"), (1, 1))
open(os.path.join(rh, "DECISIONS.md"), "w").write("# x\n")
env = dict(os.environ, HOME=rh, ADAS_JIT_DIR=rj, ADAS_JIT_BUS=os.path.join(rh, "bus"), ADAS_JIT="inline"); env.pop("AXON_HEADLESS", None)
pl = json.dumps({"hook_event_name": "PreToolUse", "session_id": "rc", "tool_name": "Bash", "tool_input": {"command": "true"}})
subprocess.run(["python3", os.path.join(JD, "regra-jit.py")], input=pl, capture_output=True, text=True, env=env, timeout=20)
chk("diário mais novo que cards.json arma a recompilação (escrita por shell)", os.path.exists(os.path.join(rj, ".recompila")))
os.remove(os.path.join(rj, ".recompila")); os.utime(os.path.join(rj, "cards.json"))
subprocess.run(["python3", os.path.join(JD, "regra-jit.py")], input=pl, capture_output=True, text=True, env=env, timeout=20)
chk("compilado em dia não recompila", not os.path.exists(os.path.join(rj, ".recompila")))
import time
rcd = os.path.join(rh, "scripts"); os.makedirs(rcd)
for f in ("da-index.sh",): os.symlink(os.path.join(RH, "scripts", f), os.path.join(rcd, f))
os.symlink(os.path.join(JD, "da-cards.py"), os.path.join(rj, "da-cards.py"))  # o hook lança o compilador do próprio dir
open(os.path.join(rh, "DECISIONS.md"), "w").write("# x\n")
open(os.path.join(rh, "CONDUCT.md"), "w").write("# c\n")
with open(os.path.join(rh, "DECISIONS.md"), "a") as f:  # escrita por SHELL (heredoc/da-new), não por Edit
    f.write("\n## DA-999 — Teste de recompilação\n`escopo: instância` · `saga: teste` · `data: 2026-10-31` · `refs: —` · `consolida: —` · `supersede: —`\n"
            "**Regra:** Nunca rodar o teste de recompilação sem HOME isolado.\n**Motivo:** fixture.\n")
os.utime(os.path.join(rj, "cards.json"), (1, 1))
subprocess.run(["python3", os.path.join(JD, "regra-jit.py")], input=pl, capture_output=True, text=True, env=env, timeout=20)
for _ in range(60):
    try:
        if any(c["id"] == "DA-999" for c in json.load(open(os.path.join(rj, "cards.json")))): break
    except Exception: pass
    time.sleep(1)
ok999 = False
try:
    import sqlite3
    ok999 = sqlite3.connect(os.path.join(rj, "regras.db")).execute("select count(*) from docs where key='DA-999'").fetchone()[0] == 1
except Exception: pass
chk("T1 DA nova por shell → hook recompila: DA-999 no cards.json e no regras.db em ≤60 s", ok999)

print("── escopo, vetor, adesão, regra-mãe (task 20261031-031) ──")
def jit(payload, extra=None, tag="x"):
    bus = os.path.join(H, ".claude/bus", "t031-" + tag)
    e = dict(os.environ, HOME=RH, ADAS_JIT_DIR=os.path.join(RH, ".adas/jit"), ADAS_JIT_BUS=bus, ADAS_JIT="inline", ADAS_JIT_OWNER="111",
             ADAS_EMBED_TIMEOUT="20"); e.pop("AXON_HEADLESS", None); e.update(extra or {})
    r = subprocess.run(["python3", os.path.join(JD, "regra-jit.py")], input=json.dumps(payload, ensure_ascii=False),
                       capture_output=True, text=True, env=e, timeout=40)
    try: led = [json.loads(l) for l in open(os.path.join(bus, "regra-jit.log"))]
    except Exception: led = []
    return r.stdout, led
OLIVUM = "calcular o custo in-house do duto de exaustão peça a peça com a dobradeira de 2 m da serralheria"
pr = lambda cwd, q, sid: {"hook_event_name": "UserPromptSubmit", "session_id": sid, "cwd": cwd, "prompt": q}
out, led = jit(pr(RH, OLIVUM, "e1"), tag="esc1")
chk("T2 cwd=home: DA-611 (projeto/olivum) NÃO aparece", "DA-611" not in out and led and led[-1].get("escopo") == "instância,produto", out[:120])
RAMPA = "qual a margem do rampa na compra de USDT pela Bras Pay e o que o cliente paga a mais que o mercado"
out, led = jit(pr(os.path.join(RH, "rampa-pix"), RAMPA, "e1c"), tag="esc1c")
chk("D-C3 cwd=rampa-pix: cartão da casa aparece como 'DA-0NN (rampa-pix)' com show apontando pro repositório", "(rampa-pix)" in out and "da-index.sh show DA-" in out and "rampa-pix" in out.split("show", 1)[-1], out[:200])
RAMPA_SEM_NOME = "qual a margem da compra de USDT com o provedor de pix e o que o cliente paga a mais que o mercado"
out, led = jit(pr(RH, RAMPA_SEM_NOME, "e1d"), tag="esc1d")
chk("D-C3/D-C9 cwd=home, ação SEM nome de casa: cartão do rampa-pix NÃO aparece (casa fechada)", "(rampa-pix)" not in out, out[:200])
out, led = jit(pr(RH, "qual a margem da venda do rampa?", "e1e"), tag="esc1e")
chk("D-C9 porteiro por nome: 'rampa' em cwd=home abre a casa (DA-006 e DA-004 do rampa-pix)", "DA-006 (rampa-pix)" in out and "DA-004 (rampa-pix)" in out, out[:240])
out, led = jit(pr(RH, "qual o risco por trade e a alavancagem máxima do robô da Lighter no perfil agressivo do nest egg?", "e1f"), tag="esc1f")
chk("D-C9 porteiro por nome: 'nest egg'/'lighter' em cwd=home abre o nest-egg", "(nest-egg)" in out, out[:240])
out, led = jit(pr(RH, "como se calcula o custo de fabricação do duto no orçamento do Olivum?", "e1g"), tag="esc1g")
chk("D-C9 porteiro por nome: 'olivum' em cwd=home abre o orcamento-estudio", "(orcamento-estudio)" in out, out[:240])
out, led = jit(pr(RH, "como se mede a célula de setup no track record do tradingdegens, pelo replay?", "e1h"), tag="esc1h")
chk("D-C9 porteiro por nome: 'tradingdegens' em cwd=home abre o tradingagents", "(tradingagents)" in out, out[:240])
out, led = jit(pr(os.path.join(RH, "tradingagents"), "cada eixo da tela do TradingDegens tem um produtor e um nome: setup, frame, fase, veredito", "e2"), tag="esc2")
chk("T2 cwd=tradingagents: cartão do TradingDegens aparece (DA-003 da casa tradingagents; a DA-193 do servidor virou 📚 em 07/11)", "DA-003 (tradingagents)" in out, out[:160])
out, led = jit(pr(RH, "cada eixo da tela tem um produtor e um nome: setup, frame, fase, veredito", "e2b"), tag="esc2b")
chk("T2 cwd=home: cartão do TradingDegens NÃO aparece", "(tradingagents)" not in out, out[:160])
out, led = jit(pr(RH, "qual o custo do duto da cozinha", "e3"), {"ADAS_EMBED_TIMEOUT": "0.001"}, tag="vec")
chk("T3 vetor morto → ledger vetor=<exceção> e nivel 1", led and led[-1].get("vetor") not in ("ok", None, "-") and led[-1].get("nivel") == 1, str(led[-1:])[:160])
bash = lambda sid, c: {"hook_event_name": "PreToolUse", "session_id": sid, "cwd": RH, "tool_name": "Bash", "tool_input": {"command": c}}
lote = lambda sid, c: {"hook_event_name": "PostToolBatch", "session_id": sid, "tool_uses": [{"tool_name": "Bash", "tool_input": {"command": c}}]}
for sid, acao, esp in (("a1", "ssh root@nanogo 'restic backup /home/degen/comcripto/data/comcripto.db'", "ignorou"),
                       ("a2", "ssh root@nanogo 'restic snapshots --latest 1'", "aplicou")):
    jit(bash(sid, "ssh root@nanogo 'ls /home/degen/comcripto/data/backups'"), tag="ad" + sid)  # mostra DA-547/548 (ex-DA-444/464)
    jit(lote(sid, "ssh root@nanogo 'ls /home/degen/comcripto/data/backups'"), tag="ad" + sid)  # fecha o lote que mostrou
    _, led = jit(lote(sid, acao), tag="ad" + sid)
    ad = (led[-1].get("adesao") or {}) if led else {}
    chk(f"T4 DA-548 (ex-DA-464) mostrado + '{acao[16:60]}…' → {esp}", ad.get("DA-548") == esp and ad.get("DA-547") == "n/a", str(ad))
import importlib.util as _iu
_sp = _iu.spec_from_file_location("rj519", os.path.join(JD, "regra-jit.py")); _rj = _iu.module_from_spec(_sp); _sp.loader.exec_module(_rj)
_ids = lambda sup, t: [c["id"] for c in _rj.motor_evento(sup, t)]
chk("T-DC013 prompt do bot financeiro dedicado NÃO acende DC-046", "DC-046" not in _ids("prompt", "Você é um assistente financeiro autônomo de Samyr. A conta de luz vence amanhã, pagar hoje"))
chk("T-DC013 conta vencendo no mainbot continua acendendo", "DC-046" in _ids("prompt", "a conta de luz vence amanhã"))
chk("T-DA464 ssh/ls no ComCripto sem backup NÃO acende (DA-548)", "DA-548" not in _ids("bash", "ssh nanogo-ts 'ls -d ~/ComCripto /home/degen/*omcripto*'"))
chk("T-DA464 ComCripto + restic/.db acende (DA-548)", "DA-548" in _ids("bash", "ssh nanogo-ts 'restic backup ~/ComCripto/data/comcripto.db'"))
g = json.load(open(os.path.join(RH, ".adas/jit/grafo.json")))
# T6: fixture própria (DA-524, lote 05): par vivo do diário some quando as DAs são consolidadas; aqui a aresta nasce de um adendo sintético
import importlib.machinery as _im
_dc = _im.SourceFileLoader("dcg", os.path.join(JD, "da-cards.py")).load_module()
_gt = os.path.join(T, "gfix"); os.makedirs(_gt, exist_ok=True)
_dc.compila_grafo([{"id": "DA-901", "hash": "h1"}, {"id": "DA-902", "hash": "h2", "filhos": ["DA-901"]}], _gt, {})
gfix = json.load(open(os.path.join(_gt, "grafo.json")))
chk("T6 grafo (fixture): adendo que mecaniza DA-901 gera aresta mecanismo-de", any(e["a"] == "DA-902" and e["b"] == "DA-901" and e["tipo"] == "mecanismo-de" for e in gfix), str(gfix))
CL = {"refs": "explícita", "consolida": "explícita", "supersede": "explícita", "mecanismo-de": "explícita", "saga": "pertencimento", "semântica": "semântica", "adesao": "aprendida", "entidade": "entidade"}
chk("T6 grafo.json: toda aresta tem classe ∈ {explícita, pertencimento, semântica, aprendida, entidade} e casa com o tipo (GLOSSARIO.md)",
    all(e.get("classe") == CL.get(e["tipo"]) for e in g), str([e for e in g if e.get("classe") != CL.get(e["tipo"])][:2]))
import importlib.machinery, importlib.util
ld = importlib.machinery.SourceFileLoader("rs", os.path.join(JD, "regra-search")); rs = importlib.util.module_from_spec(importlib.util.spec_from_loader("rs", ld)); ld.exec_module(rs)
chk("T6 cartão mecanismo mostrado → regra-mãe (fixture)", rs.regra_mae({"DA-901"}, gfix).get("DA-901") == ["DA-902"])
chk("T6 adendo em lote (DA-376) não vira regra-mãe", "DA-376" not in rs.regra_mae({"DA-376"}, g))

print("── copiar-guard 1× por reply (task 20261031-031) ──")
st = json.load(open(os.path.join(RH, ".claude/settings.json")))
regs = [h["command"] for e in st.get("hooks", {}).get("PreToolUse", []) if e.get("matcher") == "mcp__plugin_telegram_telegram__reply" for h in e.get("hooks", [])]
chk("T5 settings: copiar-guard NÃO registrado standalone no reply (roda dentro do juiz)", not any("copiar-guard" in c for c in regs), str(regs))
chk("T5 settings: juiz-reply registrado no reply", any("juiz-reply" in c for c in regs))
gh = os.path.join(T, "g5"); os.makedirs(os.path.join(gh, ".claude/bus"))
rp = json.dumps({"hook_event_name": "PreToolUse", "tool_name": "mcp__plugin_telegram_telegram__reply",
                 "tool_input": {"chat_id": "1", "format": "text", "text": "Cola: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOabcdefghijklmnopqrstuvwxyz0123 x"}})
e5 = dict(os.environ, HOME=gh, JUIZ_REPLY_RUBRICA=os.path.join(RH, ".adas/jit/juiz-reply.json"),
          JUIZ_REPLY_LEDGER=os.path.join(gh, "j.log"), JUIZ_REPLY_CACHE=os.path.join(gh, "c.json"))
for c in regs:  # os hooks do matcher reply, como o Claude Code roda
    r5 = subprocess.run(["bash", "-c", c], input=rp, capture_output=True, text=True, env=e5, timeout=20)
    if "juiz-reply" in c: out5 = r5.stdout
n5 = sum(1 for _ in open(os.path.join(gh, ".claude/bus/copiar-guard.log"))) if os.path.exists(os.path.join(gh, ".claude/bus/copiar-guard.log")) else 0
chk(f"T5 reply com chave SSH: guard roda 1× ({n5}) e o juiz repassa o deny", n5 == 1 and '"deny"' in out5, out5[:120])

if os.environ.get("JUIZ") == "1":
    # T7: paráfrase no juiz (rede, ~US$0,0003). <FIXDIR>/juiz-<ID>.jsonl: {"nome","espera":[...],"text","format"}.
    # espera: deny | aviso (do próprio ID) | passa | "aviso:outro" (aviso de OUTRO cartão, não deste). "gap": medido e
    # registrado — mostrado, não conta.
    print("── juiz: fixtures de paráfrase (T7, --juiz) ──")
    for a in sorted(glob.glob(os.path.join(FIX, "juiz-D[AC]-*.jsonl")) + glob.glob(os.path.join(FIX, "juiz-*:D[AC]-*.jsonl"))):  # D-C3: juiz-<casa>:DA-NNN
        rid = os.path.basename(a)[5:-6]
        for l in open(a, encoding="utf-8"):
            if not l.strip(): continue
            c = json.loads(l); jd = os.path.join(T, "j7"); os.makedirs(jd, exist_ok=True)
            r7 = os.path.join(jd, "rub.json")  # rubrica real SEM os guards: o guard grava no log real (HOME real é
            if not os.path.exists(r7):        # preciso pra credencial do juiz) e não é o assunto do T7
                rb = json.load(open(os.path.join(RH, ".adas/jit/juiz-reply.json"))); rb["hooks"] = []; json.dump(rb, open(r7, "w"))
            e7 = dict(os.environ, JUIZ_REPLY_RUBRICA=r7, JUIZ_REPLY_LEDGER=os.path.join(jd, "l.log"), JUIZ_REPLY_CACHE=os.path.join(jd, "c.json"))
            pl7 = json.dumps({"hook_event_name": "PreToolUse", "tool_name": "mcp__plugin_telegram_telegram__reply",
                              "tool_input": {"chat_id": "1", "text": c["text"], "format": c.get("format", "text")}}, ensure_ascii=False)
            o = subprocess.run(["python3", os.path.join(RH, ".claude/hooks/juiz-reply.py")], input=pl7, capture_output=True, text=True, env=e7, timeout=30).stdout
            v = "deny" if '"deny"' in o and rid in o else ("aviso" if rid in o else ("aviso:outro" if o.strip() else "passa"))
            if c.get("gap"):  # gap MEDIDO e registrado (DA-475): mostra, não reprova
                print(f"  ⚠ T7 {rid}: {c['nome']} → gap conhecido ({c['gap'][:60]}…), veio {v}")
                continue
            chk(f"T7 {rid}: {c['nome']} → {'|'.join(c['espera'])}", v in c["espera"], f"veio {v}")

print("── juiz como filtro do motor de evento + heredoc + dedupe (task 20261103-001) ──")
import importlib.util
sp_ = importlib.util.spec_from_file_location("rj", os.path.join(JD, "regra-jit.py")); rj = importlib.util.module_from_spec(sp_); sp_.loader.exec_module(rj)
sb = rj.comando_sem_corpo
chk("T8 heredoc: palavra do gatilho só no corpo não casa", "nanogo" not in sb("python3 - <<'EOF'\nx = 'nanogo restic'\nEOF\nls"))
chk("T8 argumento de bus-inject/echo/sed não casa", all("nanogo" not in sb(c) for c in (
    "bash ~/s/bus-inject.sh devbot 'backup do nanogo restic' 'c'", "echo \"nanogo restic\"", "sed -i 's/nanogo/x/' f")))
chk("T8 ssh host 'restic …' e python3 -c continuam casando", "restic" in sb("ssh root@nanogo 'restic snapshots'") and "x" in sb("python3 -c 'x'"))
sys.path.insert(0, JD); import juiz_prov as jp_
rj.STATE = os.path.join(T, "j8"); card = {"id": "DA-444", "regra_curta": "r", "titulo": "t", "motor": "evento"}
os.environ.pop("ADAS_JIT_JUIZ", None); jp_.nivel = lambda: 3; jp_.provedores = lambda c=None, rede=True: [{"nome": "stub"}]
jp_.perguntar = lambda texto, cartoes, prazo, fmt=None, provs=None: ({"DA-444": 0.1}, {"prov": "stub", "cost": 1e-5})
k, p, m = rj.juiz_filtra("bash", "ls", [dict(card)])
chk("T8 juiz p<limiar derruba o cartão e grava p/prov/custo", k == [] and p == {"DA-444": 0.1} and m.get("prov") == "stub" and m.get("cost") == 1e-5, str((k, p, m)))
jp_.perguntar = lambda *a, **kw: ({"DA-444": 0.9}, {"prov": "stub"})
chk("T8 juiz p≥limiar mantém", len(rj.juiz_filtra("bash", "ls", [dict(card)])[0]) == 1)
def _boom(*a, **kw): raise RuntimeError("timeout")
jp_.perguntar = _boom
k, p, m = rj.juiz_filtra("bash", "ls", [dict(card)])
chk("T8 falha do juiz = passa (cartão mostrado, erro no ledger)", len(k) == 1 and "erro" in m, str(m))
rj.JUIZ_TETO = 0
chk("T8 teto/dia estourado = passa sem chamar", len(rj.juiz_filtra("bash", "ls", [dict(card)])[0]) == 1 and not rj.juiz_filtra("bash", "ls", [dict(card)])[2]["chamou"])
rj.JUIZ_TETO = 400
ev_ = {"hook_event_name": "PreToolUse", "session_id": "dd", "cwd": RH, "tool_name": "Bash", "tool_input": {"command": "ssh root@nanogo 'restic snapshots'"}}
o1, _ = jit(ev_, tag="dd"); o2, _ = jit(ev_, tag="dd")
chk("T8 dedupe: mesmo cartão na mesma sessão não repete (TTL 30 min)", "DA-547" in o1 and "DA-547" not in o2 and rj.TTL_VISTO == 1800, o2[:100])

print("── sombra do Jev (task 20261107-016): grava só no log, fail-silent, sem vetor por padrão ──")
rj.LOG = os.path.join(T, "sombra.log"); rj.STATE = os.path.join(T, "j16"); rj.D = RH + "/.adas/jit" if os.path.isdir(RH + "/.adas/jit") else rj.D
rj.candidatos_largos = lambda texto, esc, n=45: ([{"id": "DA-1", "titulo": "t", "regra_curta": "r"}, {"id": "DA-2", "titulo": "u", "regra_curta": "s"}], "off")
jp_.perguntar = lambda texto, cartoes, prazo, fmt=None, provs=None: ({"DA-1": 0.9, "DA-2": 0.1}, {"prov": "stub", "cost": 2e-4})
rj.sombra_jev("quero fazer trade", {"produto"}, "s16", "r")
lin = [json.loads(l) for l in open(rj.LOG)]
chk("S16 grava sombra_jev {ids,p,ms,cost} e só os p≥limiar entram em ids", lin[-1]["superficie"] == "sombra" and lin[-1]["sombra_jev"]["ids"] == ["DA-1"]
    and lin[-1]["sombra_jev"]["cost"] == 2e-4 and "ms" in lin[-1]["sombra_jev"], str(lin[-1]))
jp_.perguntar = _boom
rj.sombra_jev("quero fazer trade", {"produto"}, "s16", "r")
chk("S16 Jev caído = linha com erro, sem exceção (fail-silent)", "erro" in json.loads(open(rj.LOG).read().splitlines()[-1])["sombra_jev"])
rj.SOMBRA_TETO = 0; n_ = len(open(rj.LOG).read().splitlines()); rj.sombra_jev("x", {"produto"}, "s16", "r")
chk("S16 teto/dia estourado não chama nem grava", len(open(rj.LOG).read().splitlines()) == n_); rj.SOMBRA_TETO = 300
import tempfile as _tf
_cd = _tf.mkdtemp(dir=T); rj.D = _cd
json.dump([{"id": "DA-1", "titulo": "t1", "regra_curta": "r1", "saga": "sa", "escopo": "instância"}, {"id": "DA-2", "titulo": "t2", "regra_curta": "r2", "saga": "sb", "escopo": "instância"},
           {"id": "DA-3", "titulo": "t3", "regra_curta": "r3", "saga": "sb", "escopo": "instância"}], open(_cd + "/cards.json", "w"))
json.dump({"arestas": [{"a": "DA-1", "b": "DA-3", "w": 0.9, "tipo": "complementa"}]}, open(_cd + "/grafo-jev.json", "w"))
def _jv(texto, cartoes, prazo, **kw):
    ids = {c["id"] for c in cartoes}
    return ({i: (0.9 if i in ("sa", "DA-1", "DA-3") else 0.1) for i in ids}, {"cost": 1e-4})
rc = rj.sombra_cascata("x", {"instância"}, juiz=_jv)
chk("S16 cascata: saga acende → DA acende → vizinha (grafo-jev) entra; saga apagada fica fora", rc["ids"] == ["DA-1", "DA-3"] and rc["sagas"] == ["sa"] and rc["ids_n2"] == ["DA-1"] and rc["cost"] == 3e-4, str(rc))
os.environ["ADAS_JIT_JUIZ"] = "off"
chk("S16 ADAS_JIT_JUIZ=off ou superfície != prompt não dispara processo", rj.dispara_sombra("prompt", "x", {"produto"}, "s", "r") is None and rj.dispara_sombra("bash", "x", {"produto"}, "s", "r") is None)

print("── LISTA de títulos (task 20261109-017): Jev e grafo intercalados, Jev caído = ordem do grafo ──")
rj.candidatos_largos = lambda texto, esc, n=45: ([{"id": f"DA-{i}", "titulo": f"t{i}", "regra_curta": ""} for i in (1, 2, 3, 4)], "off")
l_, m_ = rj.lista_fill("x", {"produto"}, 3)
chk("LISTA sem juiz = ordem do grafo", [c["id"] for c in l_] == ["DA-1", "DA-2", "DA-3"] and m_["jev"] == "off", str(m_))
os.environ["ADAS_JIT_JUIZ"] = "on"; _nv, _pv = jp_.nivel, jp_.provedores
jp_.nivel = lambda: 3; jp_.provedores = lambda rede=True: [{"nome": "stub"}]
jp_.perguntar = lambda texto, cartoes, prazo, fmt=None, provs=None: ({"DA-1": .1, "DA-2": .2, "DA-3": .3, "DA-4": .9}, {"cost": 0})
l_, m_ = rj.lista_fill("x", {"produto"}, 3)
chk("LISTA intercala Jev 1º, grafo 1º, Jev 2º…", [c["id"] for c in l_] == ["DA-4", "DA-1", "DA-3"] and m_["jev"] == "ok", str([c["id"] for c in l_]))
jp_.perguntar = _boom
chk("LISTA Jev caído = só grafo, sem exceção", [c["id"] for c in rj.lista_fill("x", {"produto"}, 2)[0]] == ["DA-1", "DA-2"])
jp_.nivel, jp_.provedores = _nv, _pv; os.environ["ADAS_JIT_JUIZ"] = "off"

print("── PONTE diário→casa (task 20261110-009): sinapse e entidade atravessam o escopo; quem julga é o agente ──")
import sqlite3 as _sq
_pd = os.path.join(T, "ponte"); os.makedirs(_pd); _D0 = rj.D; rj.D = _pd
_db = _sq.connect(os.path.join(_pd, "regras.db")); _db.execute("create table docs(key text, titulo text)")
_db.executemany("insert into docs values(?,?)", [(f"ne:DA-0{i}", f"t{i}") for i in range(1, 9)]); _db.commit(); _db.close()
_E = lambda a, b, w, c: {"a": a, "b": b, "w": w, "classe": c}
json.dump([_E("ne:DA-04", "ne:DA-05", 1.0, "explícita"), _E("ne:DA-05", "ne:DA-06", 0.9, "semântica"),
           _E("ne:DA-04", "ne:DA-07", 0.3, "pertencimento"), _E("DA-1", "ne:DA-01", 0.83, "semântica"),
           _E("DA-1", "ne:DA-08", 0.88, "entidade"), _E("ne:DA-04", "ne:DA-08", 0.85, "semântica")],
          open(os.path.join(_pd, "grafo.json"), "w"))
json.dump({"bot:sendtrades": {"rx": r"(?<![\w@])(?:@sendtrades(?:_?bot)?|sendtrades_?bot|s[\s_-]?e[\s_-]?n[\s_-]?d[\s_-]?t[\s_-]?r[\s_-]?a[\s_-]?d[\s_-]?e[\s_-]?s?(?:[\s_-]?bot)?)\b", "das": ["ne:DA-04"]}},
          open(os.path.join(_pd, "entidades.json"), "w"))
_ms = [{"id": "DA-1"}, {"id": "DA-2"}]
chk("PONTE (DA-703): DA da lista sem eco na mensagem + sinapse semântica fraca não passa do piso", rj.pontes(_ms, "texto qualquer", {}) == [])
_p = rj.pontes(_ms, "o print do Send Trade", {}, n=4)
chk("PONTE 2 saltos a partir da entidade, convergência soma (DA-08: lista+entidade), pertencimento sozinho (DA-07) fora, semente só completa",
    [c["id"] for c in _p] == ["ne:DA-05", "ne:DA-08", "ne:DA-06", "ne:DA-04"] and _p[0]["motor"] == "ponte", str([(c["id"], c["ativ"]) for c in _p]))
chk("PONTE caminho visível com casa só na troca", _p[2]["caminho"] == "@sendtrades_bot → ne DA-04 → DA-05 → DA-06"
    and _p[2]["via"] == "@sendtrades_bot → ne DA-04 → DA-05", str(_p[2]))
chk("PONTE teto e já-visto na sessão", len(rj.pontes(_ms, "Send Trade", {}, n=1)) == 1
    and "ne:DA-05" not in [c["id"] for c in rj.pontes(_ms, "Send Trade", {"lista:ne:DA-05": 1})])
_ej = os.path.join(_pd, "entidades.json"); _en = json.load(open(_ej))
_en["tema:x"] = {"rx": r"contra[\s-]+tend[eê]ncia", "das": ["ne:DA-06"]}
json.dump(_en, open(_ej, "w"))
_t = rj.pontes([], "compra contra tendencia", {}, n=3)
chk("PONTE tema curado (task 20261110-014): a DA do tema aparece ELA mesma, na frente; mensagem sem a frase não a traz",
    _t and _t[0]["id"] == "ne:DA-06" and not [c for c in rj.pontes([], "reinicia o mainbot", {}, n=3) if c["id"] == "ne:DA-06"], str(_t))
chk("PONTE sem grafo/entidades = nada, sem exceção", rj.pontes([{"id": "DA-7"}], "x", {}) == [])

print("── PLASTICIDADE e PODA (DA-704): peso aprendido fora do grafo.json, medido junto ──")
import contextlib, io
_pp = os.path.join(_pd, "pesos-aprendidos.json")
chk("PLAST sem pesos-aprendidos.json = sem influência (fator 1, posição igual)", all(c["fator"] == 1.0 and c["aprend"] == "igual"
    for c in rj.pontes(_ms, "o print do Send Trade", {}, n=4)))
with contextlib.redirect_stdout(io.StringIO()): rj.liga_pesos(True)
_c6 = [["ne:DA-04", "ne:DA-05"], ["ne:DA-05", "ne:DA-06"]]
_m = rj.aprende({"ne:DA-06": {"arestas": _c6}, "ne:DA-08": {"arestas": [["DA-1", "ne:DA-08"]]}}, {"ne:DA-06"})
chk("PLAST aberto ganha +0,15 em cada aresta do caminho; mostrado e não aberto perde 0,05", _m == {"ne:DA-04|ne:DA-05": 1.15,
    "ne:DA-05|ne:DA-06": 1.15, "DA-1|ne:DA-08": 0.95}, str(_m))
for _ in range(8): rj.aprende({"ne:DA-06": {"arestas": _c6}}, {"ne:DA-06"})
_p = {c["id"]: c for c in rj.pontes(_ms, "o print do Send Trade", {}, n=4)}
chk("PLAST teto 2,0 e o aprendizado sobe o item (DA-06 passa a DA-08) e o ledger sabe", _p["ne:DA-06"]["aprend"] == "subiu"
    and _p["ne:DA-08"]["aprend"] == "desceu" and _p["ne:DA-06"]["fator"] == 4.0, str({k: (v["aprend"], v["fator"]) for k, v in _p.items()}))
_P = json.load(open(_pp)); _vel = time.time() - 61 * 86400
chk("PODA: >60 dias sem abrir cai pro piso (explícita 0,8, demais 0,3), sem apagar; abrir de novo volta",
    rj.fator("k", "semântica", {"arestas": {"k": {"f": 1.5, "visto": _vel}}}) == 0.3
    and rj.fator("k", "explícita", {"arestas": {"k": {"f": 1.5, "visto": _vel}}}) == 0.8
    and rj.fator("k", "semântica", {"arestas": {"k": {"f": 1.5, "visto": _vel, "util": time.time()}}}) == 1.5)
rj.STATE = os.path.join(T, "plast"); os.makedirs(rj.STATE, exist_ok=True); rj.LOG = os.path.join(T, "plast.log")
for _cmd, _esp in (("bash ~/scripts/da-index.sh show DA-06 /opt/projects/ne", ["ne:DA-06"]), ("citei ne DA-06 no reply", [])):
    json.dump({"cartoes": [], "pontes": ["ne:DA-06"], "pontes_info": {"ne:DA-06": {"arestas": _c6, "aprend": "subiu"}},
               "armado": True, "superficie": "prompt", "t": time.time()}, open(os.path.join(rj.STATE, "sp.pend"), "w"))
    rj.par({"session_id": "sp", "tool_uses": [{"tool_name": "Bash", "tool_input": {"command": _cmd}}]}, "sp")
    _l = json.loads(open(rj.LOG).read().splitlines()[-1])
    chk(f"PLAST par: só `da-index.sh show` com a casa ensina ({_cmd[:24]}…)", _l["abriu_ponte"] == _esp and _l["pontes_aprend"] == {"ne:DA-06": "subiu"}, str(_l))
with contextlib.redirect_stdout(io.StringIO()): rj.liga_pesos(False)
chk("PLAST --zera-pesos: backup + desligado = sem influência", rj.pesos() == {} and any(f.startswith("pesos-aprendidos.json.bak-") for f in os.listdir(_pd))
    and all(c["fator"] == 1.0 for c in rj.pontes(_ms, "o print do Send Trade", {}, n=4)))
rj.D = _D0

print("── juiz externo (task 20261109-022): segredo não sai, texto é DADO, saída só probabilidade ──")
import importlib.util as _iuj
_spj = _iuj.spec_from_file_location("jp_limpo", os.path.join(JD, "juiz_prov.py")); jpl = _iuj.module_from_spec(_spj); _spj.loader.exec_module(jpl)
_RH_RED = os.environ.get("ADAS_REDATOR") or jpl.conf().get("ADAS_REDATOR") or ""  # redator da instância, pela config (R4)
if os.path.isfile(_RH_RED):
    jpl.REDATOR = _RH_RED; os.environ["REDACT_FONTES"] = os.path.join(T, "nada")  # só a metade de padrões; cofre real fora do teste
    _a = "abcdefghij0123456789ABCDEFGHIJ0123456789"  # chaves falsas montadas em runtime (o pre-commit reprova literal)
    _falsas = ["sk-" + "proj" + _a[:30], "gh" + "p_" + _a[:36], "AI" + "za" + _a[:35], "AK" + "IA" + "ABCDEFGHIJ012345",
               "xox" + "b-" + _a[:20], "1234567890:" + "AA" + _a[:33], "ro:" + "1:abc:2:" + "ab12" * 8,
               "-----BEGIN " + "PRIVATE KEY-----\n" + _a + "\n-----END " + "PRIVATE KEY-----"]
    _corpo = []
    jpl._post = lambda url, corpo, key, prazo: (_corpo.append(corpo), {"answers": {"DA-1": {"noul": 0.9}, "DA-X": {"noul": 1}, "DA-2": {"noul": "lixo"}}})[1]
    _txt = "faz o deploy. " + " ".join(_falsas) + " Bearer " + _a + " api_key=" + _a
    r_, m_ = jpl.perguntar(_txt, [{"id": "DA-1", "pergunta": "p1"}, {"id": "DA-2", "pergunta": "p2"}], time.time() + 5,
                           provs=[{"nome": "stub", "tipo": "systemone", "url": "x", "model": "m", "key": "k"}])
    _env = json.dumps(_corpo[-1], ensure_ascii=False)
    chk("JUIZ nenhuma chave falsa (8 formatos + Bearer + api_key=) sai no payload", not any(f[:24] in _env for f in _falsas) and _a not in _env, _env[:300])
    chk("JUIZ texto vai como DADO: toda pergunta leva a instrução de ignorar ordem dentro da mensagem",
        all("DADO" in q["instructions"] for q in _corpo[-1]["questions"].values()))
    chk("JUIZ saída: só id perguntado e só probabilidade (DA-X e 'lixo' descartados)", r_ == {"DA-1": 0.9}, str(r_))
    jpl._RED = None; jpl.REDATOR = os.path.join(T, "nao-existe.py"); _corpo.clear()
    try:
        jpl.perguntar("x", [{"id": "DA-1", "pergunta": "p"}], time.time() + 5, provs=[{"nome": "stub", "tipo": "systemone", "url": "x", "model": "m", "key": "k"}]); _ok = False
    except RuntimeError as e:
        _ok = "redator" in str(e)
    chk("JUIZ redator ausente = RuntimeError e nada sai (quem chama pula o juiz)", _ok and not _corpo)
    os.environ.pop("REDACT_FONTES", None)
else:
    print("  (pulado: redator da instância ausente)")

print("── D4: cartão lê tipo/gravidade/status da DC, par ❌/✅, Detalhe (task 20261106-010) ──")
import importlib.util as _iu4
_sp4 = _iu4.spec_from_file_location("dc4", os.path.join(JD, "da-cards.py")); dc4 = _iu4.module_from_spec(_sp4); _sp4.loader.exec_module(dc4)
chk("D4 par aceita ❌/✅", dc4.par_exemplo(["❌ disse fiz sem fazer → ✅ conferiu e citou o comando"]) == {"errado": "disse fiz sem fazer", "certo": "conferiu e citou o comando"})
chk("D4 par ✗/✓ segue valendo", dc4.par_exemplo(["✗ a → ✓ b"]) == {"errado": "a", "certo": "b"})
import re as _re4
_br = _re4.compile(dc4.bot_rx("sendtrades"), _re4.I); _bn = _re4.compile(dc4.bot_rx("nanogo"), _re4.I)
chk("ENTIDADE bot: @x_bot, x_bot e nome de exibição ('Send Trade'); nome curto solto não (nanogo é host)",
    all(_br.search(t) for t in ("@sendtrades_bot", "o Send Trade", "sendtrades")) and _bn.search("@nanogo_bot")
    and not _bn.search("ssh nanogo") and not _br.search("mysendtrades"))
m4 = dc4.meta_da("## DA-1 — t\n`tipo: registro` · `gravidade: piso`\n")
chk("D4 meta lê tipo e gravidade", m4["tipo"] == "registro" and m4["gravidade"] == "piso")
m4 = dc4.meta_da("## DA-1 — t\n`escopo: produto`\n")
chk("D4 padrão: tipo regra, gravidade norma", m4["tipo"] == "regra" and m4["gravidade"] == "norma")
h4 = os.path.join(T, "d4home"); os.makedirs(os.path.join(h4, "scripts"))
os.symlink(os.path.join(RH, "scripts/da-index.sh"), os.path.join(h4, "scripts/da-index.sh"))
open(os.path.join(h4, "DECISIONS.md"), "w").write(
    "## DA-901 — Regra viva\n`escopo: instância` · `tipo: regra` · `gravidade: piso`\n**Regra:** r viva.\n**Detalhe operacional:** palavraunicadodetalhe aqui.\n\n"
    "## DA-902 — Registro\n`escopo: instância` · `tipo: registro`\n**Regra:** fato.\n")
open(os.path.join(h4, "CONDUCT.md"), "w").write(
    "## DC-901 — Viva\n`escopo: comportamento` · `status: vigente`\n**Regra:** c viva.\n\n"
    "## DC-902 — Aposentada\n`escopo: comportamento` · `status: aposentada`\n**Regra:** c morta.\n")
try:
    cs4 = {c["id"]: c for c in dc4.extract(h4)}
    vivos4 = "DA-901" in cs4
    chk("D4 tipo: registro não vira cartão", vivos4 and "DA-902" not in cs4, sorted(cs4))
    chk("D4 DC com status ≠ vigente não vira cartão", "DC-901" in cs4 and "DC-902" not in cs4, sorted(cs4))
    chk("D4 Detalhe entra no texto indexado", vivos4 and "palavraunicadodetalhe" in cs4["DA-901"]["texto"])
    chk("D4 gravidade chega ao cartão", vivos4 and cs4["DA-901"]["gravidade"] == "piso")
except Exception as e:  # da-index.sh do home de teste não lista vigentes → o teste acusa em vez de quebrar
    chk("D4 extract em home mínimo", False, repr(e))
jd4 = os.path.join(T, "d4jit"); os.makedirs(jd4)
json.dump({"P": "piso", "F": "preferência"}, open(os.path.join(jd4, "gravidade.json"), "w"))
_sp5 = _iu4.spec_from_file_location("rj4", os.path.join(JD, "regra-jit.py")); rj4 = _iu4.module_from_spec(_sp5); _sp5.loader.exec_module(rj4)
rj4.D = jd4
ids4 = lambda l: [c["id"] for c in rj4.corta_k([{"id": i} for i in l])]
chk("D4 corta_k: preferência sai primeiro", ids4(["F", "a", "b", "c"]) == ["a", "b", "c"], ids4(["F", "a", "b", "c"]))
chk("D4 corta_k: piso do fim não é cortado", ids4(["a", "b", "c", "P"]) == ["a", "b", "c", "P"] or "P" in ids4(["a", "b", "c", "P"]), ids4(["a", "b", "c", "P"]))
chk("D4 corta_k: piso passa de K", len(ids4(["P", "P", "P", "P", "a"])) == 4 and "a" not in ids4(["P", "P", "P", "P", "a"]))
os.remove(os.path.join(jd4, "gravidade.json"))
chk("D4 corta_k sem gravidade.json = vivos[:K]", ids4(["a", "b", "c", "d"]) == ["a", "b", "c"])

print("── SessionStart sem corte (ADAS-JIT) ──")
# adas_session_emit direto (o hook adas-activate.sh grava o .active da sessão — efeito colateral que o teste não pode ter)
r = subprocess.run(["bash", "-c", f'. "{RH}/.claude/hooks/adas-lib.sh" && adas_session_emit "{RH}"'], capture_output=True, text=True, timeout=30)
chk("SessionStart sem [ADAS-CORTE]", "[ADAS-CORTE]" not in r.stdout, r.stdout[:120])
chk("SessionStart anuncia [ADAS-JIT ativo]", "[ADAS-JIT ativo]" in r.stdout)
chk("D-C9 SessionStart traz o mapa das casas (uma linha 📦 por rota com DECISIONS.md)", r.stdout.count("📦 ") >= 4 and "--casa rampa-pix" in r.stdout and "--casa nest-egg" in r.stdout, r.stdout[-300:])
chk(f"SessionStart ≤ 9600 B ({len(r.stdout.encode())} B)", len(r.stdout.encode()) <= 9600)
print(f"RESULTADO: {ok} ok, {bad} falha(s)")
sys.exit(1 if bad else 0)
PY
