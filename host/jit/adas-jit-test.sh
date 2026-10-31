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
# Uso: adas-jit-test.sh [--sem DA-NNN ...] [--fixtures DIR]   (--sem simula a remoção do cartão sem tocar o
#      diário append-only). Exit 0 = tudo verde.
set -uo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"; JD="$(dirname "$SELF")"
REAL_HOME="$HOME"
FIXDIR="${ADAS_FIXTURES:-$HOME/.adas/fixtures}"
SEM=()
while [ $# -gt 0 ]; do
  case "$1" in
    --sem) SEM+=("$2"); shift ;;
    --fixtures) FIXDIR="$2"; shift ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac; shift
done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/jit" "$T/home/.claude/bus"
python3 "$JD/da-cards.py" --so-juiz --out "$T/jit" >/dev/null || { echo "✗ da-cards.py falhou"; exit 1; }
for f in regras.db regra-search da-cards.py; do ln -s "$HOME/.adas/jit/$f" "$T/jit/$f" 2>/dev/null; done

SEM_CSV="$(IFS=,; echo "${SEM[*]:-}")" T="$T" FIXDIR="$FIXDIR" JD="$JD" REAL_HOME="$REAL_HOME" python3 - <<'PY'
import glob, json, os, subprocess, sys
T, FIX, JD, RH = os.environ["T"], os.environ["FIXDIR"], os.environ["JD"], os.environ["REAL_HOME"]
sem = {s for s in os.environ.get("SEM_CSV", "").split(",") if s}
gs = {g["id"]: g["gatilho"] for g in json.load(open(os.path.join(T, "jit", "gatilhos.json"))) if g["id"] not in sem}
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

print("── SessionStart sem corte (ADAS-JIT) ──")
# adas_session_emit direto (o hook adas-activate.sh grava o .active da sessão — efeito colateral que o teste não pode ter)
r = subprocess.run(["bash", "-c", f'. "{RH}/.claude/hooks/adas-lib.sh" && adas_session_emit "{RH}"'], capture_output=True, text=True, timeout=30)
chk("SessionStart sem [ADAS-CORTE]", "[ADAS-CORTE]" not in r.stdout, r.stdout[:120])
chk("SessionStart anuncia [ADAS-JIT ativo]", "[ADAS-JIT ativo]" in r.stdout)
chk(f"SessionStart ≤ 9600 B ({len(r.stdout.encode())} B)", len(r.stdout.encode()) <= 9600)
print(f"RESULTADO: {ok} ok, {bad} falha(s)")
sys.exit(1 if bad else 0)
PY
