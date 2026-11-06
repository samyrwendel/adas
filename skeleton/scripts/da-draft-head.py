#!/usr/bin/env python3
"""da-draft-head.py — rascunho DETERMINÍSTICO de cabeça v2 (spec: metodo-e-lotes.md §5 D1).
Só lê e imprime. Sem LLM. Uso (via da-index.sh): draft-head <saga> [--ids DA-a,DA-b] [dir]
AVISA termo distintivo (path/arquivo/identificador) das consolidadas ausente da cabeça (DA-546); --confere DA-a,DA-b confere cabeças já escritas (só termos em frase com nunca/só/não; --tudo lista todos).
Recusa grupo com mais de um gatilho vivo (evento/forma): divida com --ids."""
import os, re, subprocess, sys

def termos(corpo):
    """termos distintivos: identificador em crase (path/arquivo/nome com . / _ - ou CamelCase), arquivo solto, CamelCase."""
    corpo = re.sub(r"(?m)^### Histórico.*", "", corpo, flags=re.S)
    corpo = re.sub(r"(?m)^`escopo:.*$", "", corpo)
    t = set()
    for c in re.findall(r"`([^`\n]{3,60})`", corpo):
        c = c.strip().rstrip(".,;:)")
        if re.fullmatch(r"DA-\d+[a-z]?|DC-\d+", c) or " " in c or c.startswith(("escopo:", "saga:")):
            continue
        if re.search(r"[./_-]|[a-z][A-Z]", c):
            t.add(c)
    t |= set(re.findall(r"\b[\w-]+\.(?:sh|py|json|md|conf|service|timer|jsonl)\b", corpo))
    t |= set(re.findall(r"\b[A-Z][a-z]+[A-Z][A-Za-z]+\b", corpo))
    return t

GENERICOS = {"DECISIONS.md", "CLAUDE.md", "ADAS.md", "CONDUCT.md", "MEMORY.md", "OpenClaw", "GitHub", "OpenAI", "ChatGPT", "OpenRouter", "DeFi", "~/DECISIONS.md", "~/ADAS.md"}
NEG = re.compile(r"\b(nunca|só|jamais|proibid\w*|NUNCA|SÓ|não|nem)\b")

def criticos(w, corpo):
    """termo numa frase que proíbe/restringe (nunca/só/não): perdê-lo desarma a regra (caso settings.json, DA-546)."""
    return any(w in fr and NEG.search(fr) for fr in re.split(r"(?<=[.;:])\s+|\n", corpo))

def perdidos(cabeca, membros, das, todos=False):
    """termos das DAs consolidadas que não aparecem em lugar nenhum da cabeça."""
    h = cabeca.lower()
    out = {}
    for x in membros:
        for w in sorted(termos(das[x][1])):
            base = os.path.basename(w.rstrip("/")) or w
            if w in GENERICOS or re.search(r"[<$\"\\]", w):
                continue
            if w.lower() not in h and base.lower() not in h and (todos or criticos(w, das[x][1])):
                out.setdefault(w, []).append(x)
    # caminho completo + basename = o mesmo termo: fica o mais curto
    for w in list(out):
        if any(o != w and o in w for o in out):
            del out[w]
    return out

args = sys.argv[1:]
ids_arg, pos, confere, tudo = None, [], None, False
i = 0
while i < len(args):
    if args[i] == "--tudo":
        tudo = True; i += 1
    elif args[i] == "--confere":
        confere = args[i + 1]; i += 2
    elif args[i] == "--ids":
        ids_arg = args[i + 1]; i += 2
    else:
        pos.append(args[i]); i += 1
if not pos and not confere:
    sys.exit("uso: da-index.sh draft-head <saga> [--ids DA-a,DA-b,…] [dir]")
saga = pos[0] if pos and not confere else ""
_dp = pos[0 if confere else 1:][:1]
d = _dp[0] if _dp else os.path.expanduser("~")
dai = os.path.join(os.path.dirname(os.path.abspath(__file__)), "da-index.sh")

def run(*a):
    return subprocess.run(["bash", dai, *a], capture_output=True, text=True).stdout

txt = open(f"{d}/DECISIONS.md", encoding="utf-8").read()
das = {}
for m in re.finditer(r"(?ms)^## (DA-\d+[a-z]?) — ([^\n]*)\n(.*?)(?=^## D[AC]-\d+|\Z)", txt):
    das[m.group(1)] = (m.group(2), m.group(3))

def campo(corpo, nome):
    r = re.findall(rf"(?m)^\*\*{nome}:\*\*[ \t]*(.*)$", corpo)
    return r[-1].strip() if r else ""

if confere:  # DA-546: cabeça já escrita vs. suas consolidadas — aviso, não bloqueio
    n = 0
    for h in [x.strip() for x in confere.split(",") if x.strip()]:
        m = re.search(r"consolida: ([^`]*)`", das[h][1]) if h in das else None
        mem = [x.strip() for x in m.group(1).split(",") if x.strip().startswith("DA-")] if m else []
        mem = [x for x in mem if x in das]
        perd = perdidos(f"{das[h][0]}\n{das[h][1]}", mem, das, tudo)
        for w, de in sorted(perd.items()):
            print(f"⚠ {h}: termo `{w}` de {', '.join(de)} não aparece na cabeça"); n += 1
    print(f"{n} termo(s) perdido(s) em {confere}")
    sys.exit(0)

if ids_arg:
    grupo = [x.strip() for x in ids_arg.split(",") if x.strip()]
else:
    grupo = [l.split()[1] for l in run("list", "--vigentes", "--saga", saga, d).splitlines() if l.startswith("- DA-")]
faltam = [x for x in grupo if x not in das]
if not grupo or faltam:
    sys.exit(f"✗ draft-head: sem DA para {faltam or saga}")
grupo.sort(key=lambda x: int(re.sub(r"\D", "", x)))

gat = {}
for l in run("gatilhos", d).splitlines():
    f = l.split("\t")
    if len(f) >= 2:
        gat[f[0]] = f[1]
vivos = [x for x in grupo if x in gat and not gat[x].strip().startswith("tema")]
if len(vivos) > 1:
    sys.exit(f"✗ draft-head: {len(vivos)} gatilhos vivos ({', '.join(vivos)}) — divida com --ids")

esc = []
for x in grupo:
    e = re.search(r"`escopo: ([^`]*)`", das[x][1])
    for p in (e.group(1).split(",") if e else []):
        p = p.strip()
        if p and p not in esc:
            esc.append(p)
ultima = grupo[-1]
regra = campo(das[ultima][1], "Regra")
mec = []
for x in grupo:
    for l in re.findall(r"(?m)^\*\*Mecanismo(?: da DA-\d+)?:\*\*[ \t]*(.*)$", das[x][1]):
        mec.append(l)
caminhos = []
for l in mec:
    for c in re.findall(r"`([~/][^`\s]+)`", l):
        if c not in caminhos:
            caminhos.append(c)
par = ""
for x in reversed(grupo):
    e = campo(das[x][1], "Exemplo")
    if "✗" in e and "✓" in e:
        par = e; break
padrao = next((campo(das[x][1], "Padrão sem ADAS") for x in reversed(grupo) if campo(das[x][1], "Padrão sem ADAS")), "")

print(f"## DA-NOVA — <título com as palavras de busca>")
print(f"`escopo: {','.join(esc)}` · `saga: {saga}` · `data: AAAA-MM-DD` · `tipo: regra` · `gravidade: norma` · `refs: —` · `consolida: {', '.join(grupo)}` · `supersede: —`")
print(f"**Regra:** {regra}   <!-- {len(regra)} caracteres; reescrever em até 120 -->")
print(f"**Gatilho:** {gat[vivos[0]] if vivos else 'tema'}")
print(f"**Exemplo:** {par or '✗ … → ✓ …'}")
if not par:
    srcs = sorted({m for x in grupo for m in re.findall(r"msgs? \d{4,6}", das[x][1])})
    print(f"<!-- sem par no grupo; procurar: {', '.join(srcs) or '—'}; copiar-guard.log, reportar-guard.log, juiz-reply.log -->")
print("**Fonte do exemplo:** ")
print("**Motivo:** ")
print("**Trade-off:** ")
print("**Lição:** ")
if mec:
    print("**Mecanismo:** " + " ".join(f"`{c}` ({'existe' if os.path.exists(os.path.expanduser(c)) else 'não existe'})" for c in caminhos))
if padrao:
    print(f"**Padrão sem ADAS:** {padrao}")
print("### Histórico")
for x in grupo:
    print(f"- {x} — {das[x][0]}")
_rasc = "\n".join([regra, par, padrao] + mec)
_perd = perdidos(_rasc, grupo, das)
if _perd:
    print("\n⚠ termos distintivos das consolidadas ausentes do rascunho (cobrir no Detalhe/Mecanismo ou descartar com motivo):")
    for w, de in sorted(_perd.items()):
        print(f"  `{w}` ← {', '.join(de)}")
print("\n--- fora do bloco ---")
print("Regra de cada membro (140 caracteres):")
for x in grupo:
    print(f"  {x}: {campo(das[x][1], 'Regra')[:140]}")
fx = [x for x in grupo if os.path.exists(os.path.expanduser(f"~/.adas/fixtures/{x}.jsonl")) or os.path.exists(os.path.expanduser(f"~/.adas/fixtures/juiz-{x}.jsonl"))]
print("Fixtures a migrar (da-herda.sh <antiga> <nova>): " + (", ".join(fx) or "—"))
print("Gatilhos vivos no grupo: " + (", ".join(vivos) or "—"))
