#!/usr/bin/env bash
# da-herda.sh <DA-antiga> <DA-nova> — a cabeça v2 herda fixture e aprovação do juiz da DA que ela consolidou.
# Fixture e portão do juiz são por ID: sem isto a pergunta aprovada no replay volta a "pendente".
# Copia para o id novo e MOVE o original para fixtures/_herdadas/ (o runner só lê D[AC]-*.jsonl do topo, então a antiga,
# que já não tem cartão, não reprova; nada é apagado): fixtures/DA-antiga.jsonl e juiz-DA-antiga.jsonl; juiz-gate.json chaves
# DA-antiga e DA-antiga@prompt → id novo, com nota "herdado de DA-antiga em <data>".
# ADAS_DIR (default ~/.adas) permite testar numa cópia.
set -uo pipefail
[ $# -eq 2 ] || { echo "uso: da-herda.sh <DA-antiga> <DA-nova|casa:DA-nova>   (casa = repositório do app, ex.: nest-egg:DA-066)"; exit 2; }
OLD="$1"; NEW="$2"; A="${ADAS_DIR:-$HOME/.adas}"
for f in "$OLD" "$NEW"; do [[ "$f" =~ ^([a-z0-9][a-z0-9-]*:)?D[AC]-[0-9]+[a-z]?$ ]] || { echo "✗ id inválido: $f"; exit 2; }; done
fez=0
for pre in "" "juiz-"; do
  s="$A/fixtures/${pre}${OLD}.jsonl"; d="$A/fixtures/${pre}${NEW}.jsonl"
  [ -f "$s" ] || continue
  [ -e "$d" ] && { echo "= já existe: ${pre}${NEW}.jsonl (não sobrescrevo)"; continue; }
  cp "$s" "$d" && mkdir -p "$A/fixtures/_herdadas" && mv "$s" "$A/fixtures/_herdadas/" && { echo "✓ fixture ${pre}${OLD} → ${pre}${NEW} (original em _herdadas/)"; fez=1; }
done
python3 -I - "$A/jit/juiz-gate.json" "$OLD" "$NEW" <<'PY'
import json, sys, datetime, os
p, old, new = sys.argv[1:4]
if not os.path.exists(p): sys.exit(0)
g = json.load(open(p, encoding="utf-8"))
nota = f"herdado de {old} em {datetime.date.today().isoformat()}"
for suf in ("", "@prompt"):
    if old + suf in g and new + suf not in g:
        v = dict(g[old + suf]); v["nota_herdado"] = nota
        g[new + suf] = v
        print(f"✓ juiz-gate {old+suf} → {new+suf}")
tmp = p + ".tmp"
json.dump(g, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
os.replace(tmp, p)
PY
[ "$fez" = 1 ] || echo "(nada de fixture a copiar para $NEW)"
