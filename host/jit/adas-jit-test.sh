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
    if ctx and (via != "regra-jit.py" or rid in ctx): return "aviso"
    return "passa"

arqs = sorted(glob.glob(os.path.join(FIX, "D[AC]-*.jsonl")))
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
chk("T2 cwd=home: DA-433 (projeto/olivum) NÃO aparece", "DA-433" not in out and led and led[-1].get("escopo") == "instância,produto", out[:120])
out, led = jit(pr(os.path.join(RH, "tradingagents"), "no card do TradingDegens o eixo temporal da tela mostra a hora de Manaus ou da bolsa de NY?", "e2"), tag="esc2")
chk("T2 cwd=tradingagents: cartão projeto/tradingdegens aparece (DA-193)", "DA-193" in out, out[:160])
out, led = jit(pr(RH, "qual o custo do duto da cozinha", "e3"), {"ADAS_EMBED_TIMEOUT": "0.001"}, tag="vec")
chk("T3 vetor morto → ledger vetor=<exceção> e nivel 1", led and led[-1].get("vetor") not in ("ok", None, "-") and led[-1].get("nivel") == 1, str(led[-1:])[:160])
bash = lambda sid, c: {"hook_event_name": "PreToolUse", "session_id": sid, "cwd": RH, "tool_name": "Bash", "tool_input": {"command": c}}
lote = lambda sid, c: {"hook_event_name": "PostToolBatch", "session_id": sid, "tool_uses": [{"tool_name": "Bash", "tool_input": {"command": c}}]}
for sid, acao, esp in (("a1", "ssh root@nanogo 'restic backup /home/degen/comcripto/data/comcripto.db'", "ignorou"),
                       ("a2", "ssh root@nanogo 'restic snapshots --latest 1'", "aplicou")):
    jit(bash(sid, "ssh root@nanogo 'cat /usr/local/sbin/nanogo-backup.sh'"), tag="ad" + sid)  # mostra DA-444/464
    jit(lote(sid, "ssh root@nanogo 'cat /usr/local/sbin/nanogo-backup.sh'"), tag="ad" + sid)  # fecha o lote que mostrou
    _, led = jit(lote(sid, acao), tag="ad" + sid)
    ad = (led[-1].get("adesao") or {}) if led else {}
    chk(f"T4 DA-464 mostrado + '{acao[16:60]}…' → {esp}", ad.get("DA-464") == esp and ad.get("DA-444") == "n/a", str(ad))
g = json.load(open(os.path.join(RH, ".adas/jit/grafo.json")))
chk("T6 grafo.json: DA-412 é regra-mãe da DA-465 (mecanismo-de)", any(e["a"] == "DA-412" and e["b"] == "DA-465" and e["tipo"] == "mecanismo-de" for e in g))
CL = {"refs": "explícita", "consolida": "explícita", "supersede": "explícita", "mecanismo-de": "explícita", "saga": "pertencimento", "semântica": "semântica", "adesao": "aprendida"}
chk("T6 grafo.json: toda aresta tem classe ∈ {explícita, pertencimento, semântica, aprendida} e casa com o tipo (GLOSSARIO.md)",
    all(e.get("classe") == CL.get(e["tipo"]) for e in g), str([e for e in g if e.get("classe") != CL.get(e["tipo"])][:2]))
import importlib.machinery, importlib.util
ld = importlib.machinery.SourceFileLoader("rs", os.path.join(JD, "regra-search")); rs = importlib.util.module_from_spec(importlib.util.spec_from_loader("rs", ld)); ld.exec_module(rs)
chk("T6 cartão DA-465 mostrado → regra-mãe DA-412", rs.regra_mae({"DA-465"}, g).get("DA-465") == ["DA-412"])
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
    for a in sorted(glob.glob(os.path.join(FIX, "juiz-D[AC]-*.jsonl"))):
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

print("── SessionStart sem corte (ADAS-JIT) ──")
# adas_session_emit direto (o hook adas-activate.sh grava o .active da sessão — efeito colateral que o teste não pode ter)
r = subprocess.run(["bash", "-c", f'. "{RH}/.claude/hooks/adas-lib.sh" && adas_session_emit "{RH}"'], capture_output=True, text=True, timeout=30)
chk("SessionStart sem [ADAS-CORTE]", "[ADAS-CORTE]" not in r.stdout, r.stdout[:120])
chk("SessionStart anuncia [ADAS-JIT ativo]", "[ADAS-JIT ativo]" in r.stdout)
chk(f"SessionStart ≤ 9600 B ({len(r.stdout.encode())} B)", len(r.stdout.encode()) <= 9600)
print(f"RESULTADO: {ok} ok, {bad} falha(s)")
sys.exit(1 if bad else 0)
PY
