#!/usr/bin/env python3
"""da-draft-head.py — rascunho DETERMINÍSTICO de cabeça v2 (spec: metodo-e-lotes.md §5 D1).
Só lê e imprime. Sem LLM. Uso (via da-index.sh): draft-head <saga> [--ids DA-a,DA-b] [dir]
Recusa grupo com mais de um gatilho vivo (evento/forma): divida com --ids."""
import os, re, subprocess, sys

args = sys.argv[1:]
ids_arg, pos = None, []
i = 0
while i < len(args):
    if args[i] == "--ids":
        ids_arg = args[i + 1]; i += 2
    else:
        pos.append(args[i]); i += 1
if not pos:
    sys.exit("uso: da-index.sh draft-head <saga> [--ids DA-a,DA-b,…] [dir]")
saga = pos[0]
d = pos[1] if len(pos) > 1 else os.path.expanduser("~")
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
print("\n--- fora do bloco ---")
print("Regra de cada membro (140 caracteres):")
for x in grupo:
    print(f"  {x}: {campo(das[x][1], 'Regra')[:140]}")
fx = [x for x in grupo if os.path.exists(os.path.expanduser(f"~/.adas/fixtures/{x}.jsonl")) or os.path.exists(os.path.expanduser(f"~/.adas/fixtures/juiz-{x}.jsonl"))]
print("Fixtures a migrar (da-herda.sh <antiga> <nova>): " + (", ".join(fx) or "—"))
print("Gatilhos vivos no grupo: " + (", ".join(vivos) or "—"))
