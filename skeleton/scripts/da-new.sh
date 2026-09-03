#!/usr/bin/env bash
# da-new.sh — porta única de escrita do DECISIONS.md (DA-181 §2.2).
#
# flock em ~/.adas/da.lock, snapshot do diário em ~/.adas/snapshots/ ANTES de
# anexar, número = max(DA-NNN existente)+1, esqueleto do cabeçalho anexado no
# FIM do arquivo (nunca no meio — é aqui que se evita o vetor da DA-127/DA-012:
# dois escritores ou um Edit por old_string/new_string num arquivo de 1 MB).
# O agente preenche o esqueleto (Regra/Motivo/Trade-off/Lição) por Edit DEPOIS,
# dentro da DA recém-criada — nunca editando DAs anteriores.
#
# uso: da-new.sh <escopo> <saga> "<título>" [dir]
#   escopo: produto | instância | projeto/<nome> (composto: "produto,instância")
#   saga:   slug existente em ~/.adas/sagas.conf, ou "nova/<slug>" se for nova
#   dir:    onde vive DECISIONS.md (default: $HOME)
set -uo pipefail

usage() { echo 'uso: da-new.sh <escopo> <saga> "<título>" [dir]'; exit 2; }
[ $# -ge 3 ] || usage
ESCOPO="$1"; SAGA="$2"; TITULO="$3"; DIR="${4:-$HOME}"
DEC="$DIR/DECISIONS.md"
[ -f "$DEC" ] || { echo "✗ da-new: $DEC não existe"; exit 2; }

# ADAS_DIR default segue o [dir] alvo (nunca $HOME) — senão um da-new.sh contra uma cópia de
# teste ainda grava snapshot/lock no ~/.adas/ do servidor real. Produção usa dir=$HOME por
# default, então o comportamento real não muda; só o caso [dir] ≠ $HOME passa a se isolar.
ADAS_DIR="${ADAS_HOME_DIR:-$DIR/.adas}"
mkdir -p "$ADAS_DIR/snapshots" 2>/dev/null || true
LOCK="$ADAS_DIR/da.lock"

# saga tem que existir em sagas.conf (ou vir como nova/<slug>) — slug desconhecido sem esse
# prefixo RECUSA (exit 2) em vez de anexar uma DA com saga fantasma no diário.
SAGAS_CONF="${ADAS_SAGAS_CONF:-$ADAS_DIR/sagas.conf}"
if [ -f "$SAGAS_CONF" ]; then
  IFS=',' read -ra _sg <<< "$SAGA"
  invalid=()
  for sgv in "${_sg[@]}"; do
    [[ "$sgv" == nova/* ]] && continue
    grep -qE "^${sgv}\||[|,]${sgv}(,|\$)" "$SAGAS_CONF" 2>/dev/null || invalid+=("$sgv")
  done
  if [ "${#invalid[@]}" -gt 0 ]; then
    echo "✗ da-new: saga(s) inexistente(s) em $SAGAS_CONF: ${invalid[*]} — use 'nova/<slug>' se for saga nova." >&2
    echo "  slugs válidos:" >&2
    cut -d'|' -f1 "$SAGAS_CONF" 2>/dev/null | grep -vE '^(#|$)' | sed 's/^/    /' >&2
    exit 2
  fi
fi

exec 9>"$LOCK"
flock -w 10 9 || { echo "✗ da-new: não consegui o lock $LOCK em 10s (outro processo escrevendo?)"; exit 1; }

# snapshot ANTES de anexar (achado dos pré-mortems: ~/ não é git — só o snapshot protege)
ts="$(date -u +%Y%m%dT%H%M%SZ)"
cp "$DEC" "$ADAS_DIR/snapshots/DECISIONS.md.$ts" 2>/dev/null || { echo "✗ da-new: snapshot falhou — abortando sem tocar no diário"; exit 1; }
# rotação: mantém só os 30 snapshots mais recentes (nome = timestamp UTC, ordena cronológico)
ls -1 "$ADAS_DIR/snapshots"/DECISIONS.md.* 2>/dev/null | sort | head -n -30 | xargs -r rm -f --

# número = max(DA-NNN)+1, sobre o DIÁRIO REAL (não sobre um cache)
max=0
while read -r n; do
  n="$((10#$n))"
  [ "$n" -gt "$max" ] && max="$n"
done < <(grep -oE '^## DA-[0-9]+' "$DEC" | grep -oE '[0-9]+')
novo=$((max+1))
novokey="DA-$(printf '%03d' "$novo")"

data_hoje="$(date +%F)"
{
  echo ""
  echo "## $novokey — $TITULO"
  echo "\`escopo: $ESCOPO\` · \`saga: $SAGA\` · \`data: $data_hoje\` · \`refs: —\` · \`consolida: —\` · \`supersede: —\`"
  echo "**Regra:** "
  echo "**Motivo:** "
  echo "**Trade-off:** "
  echo "**Lição:** "
} >> "$DEC"

echo "✓ da-new: $novokey anexada no fim de $DEC (snapshot: $ADAS_DIR/snapshots/DECISIONS.md.$ts)"
echo "  Preencha Regra/Motivo/Trade-off/Lição por Edit dentro de $novokey — nunca em DA anterior."
echo "$novokey"
