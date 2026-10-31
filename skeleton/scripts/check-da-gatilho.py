#!/usr/bin/env python3
"""check-da-gatilho — DA normativa sem **Gatilho:** é regra que só existe no papel (ADAS-JIT F2, check 13).

Normativa = a linha **Regra:** manda ou proíbe (nunca · sempre · só/somente · obrigat* · proibid* · jamais ·
não pode · exige). Para cada DA vigente normativa, o DEGRAU de eficácia (medido em 06/09: doc na janela 0%,
ponteiro 43%, trava no ato com conserto 71%):
  gate      Gatilho com hook=<guard> ou quando=/re/ (evento/forma com predicado), ou juiz com modo=deny
  ponteiro  Gatilho declarado sem trava (tema, juiz em aviso) — a regra chega por recuperação/aviso
  doc       sem **Gatilho:** nenhum (nem adendo "**Gatilho da DA-NNN:**") — só no diário → WARN
Gatilho com hook=/quando= sem fixture em <raiz>/.adas/fixtures/DA-NNN.jsonl → WARN (DA-376: trava sem teste
que falha quando ela some não é trava). Nunca FAIL: é fila de levantamento (a revisão semanal propõe os gatilhos).

Uso: check-da-gatilho.py [--list] [raiz]   (raiz com DECISIONS.md e scripts/da-index.sh; padrão: cwd)
Saída: "WARN DA-NNN degrau=doc — título" (com --list) e uma linha de resumo "gatilho: …". Exit 0 sempre."""
import os, re, subprocess, sys

NORMA = re.compile(r"(^|[^\w])(nunca|sempre|s[óo]|somente|obrigat\w*|proibid\w*|jamais|n[ãa]o pode|exige\w*)([^\w]|$)", re.I)

def main():
    a = [x for x in sys.argv[1:] if x != "--list"]
    lista = "--list" in sys.argv
    raiz = os.path.abspath(a[0] if a else ".")
    dec = os.path.join(raiz, "DECISIONS.md")
    idx = os.path.join(raiz, "scripts", "da-index.sh")
    if not os.path.exists(idx):
        idx = os.path.join(os.path.dirname(os.path.abspath(__file__)), "da-index.sh")
    if not (os.path.exists(dec) and os.path.exists(idx)):
        print("gatilho: sem DECISIONS.md/da-index.sh — pulado"); return 0
    run = lambda *c: subprocess.run(["bash", idx, *c, raiz], capture_output=True, text=True).stdout
    vig = set(re.findall(r"^- (DA-\d+[a-z]?)", run("list", "--vigentes"), re.M))
    gat = {}
    for l in run("gatilhos").splitlines():
        f = l.split("\t")
        if len(f) >= 2: gat[f[0]] = f[1]
    fixdir = os.path.join(raiz, ".adas", "fixtures")
    txt = open(dec, encoding="utf-8").read()
    cont = {"gate": 0, "ponteiro": 0, "doc": 0}; avisos = []
    for b in re.split(r"(?m)^(?=## DA-\d)", txt)[1:]:
        h = re.match(r"## (DA-\d+[a-z]?) — (.*)", b)
        if not h or h.group(1) not in vig: continue
        m = re.search(r"\*\*Regra:\*\*(.*?)(?=\n\*\*|\n###|\n---|\Z)", b, re.S)
        if not m or not NORMA.search(m.group(1)): continue
        da, g = h.group(1), gat.get(h.group(1))
        if g is None:
            d = "doc"
        elif re.search(r"(^|·)\s*(hook|quando)=", g) or ("juiz" in g and "modo=deny" in g):
            d = "gate"
        else:
            d = "ponteiro"
        cont[d] += 1
        if d == "doc":
            avisos.append(f"WARN {da} degrau=doc — {h.group(2)[:90]}")
        if g and re.search(r"(^|·)\s*(hook|quando)=", g) and not os.path.exists(os.path.join(fixdir, da + ".jsonl")):
            avisos.append(f"WARN {da} gatilho de máquina sem fixture ({fixdir}/{da}.jsonl)")
    if lista:
        print("\n".join(avisos))
    sem_fix = sum(1 for x in avisos if "sem fixture" in x)
    print(f"gatilho: {sum(cont.values())} DA normativa(s) vigente(s) — gate {cont['gate']} · ponteiro {cont['ponteiro']} · "
          f"doc {cont['doc']} (sem Gatilho){f' · {sem_fix} sem fixture' if sem_fix else ''}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
