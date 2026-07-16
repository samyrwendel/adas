#!/usr/bin/env bash
# ADAS host — INSTALADOR idempotente do runtime anti-decaimento (PASSO 11).
#   bash host/install.sh                       # instala/atualiza hooks + repos.conf existente
#   bash host/install.sh /path/repo1 [...]     # idem + adiciona repos governados ao repos.conf
# Faz: 1) copia os hooks pro user-level  2) garante ~/.claude/adas/repos.conf
#      3) MERGE dos hooks no ~/.claude/settings.json — preserva o que já existe, remove entradas
#         adas-*.sh antigas e re-adiciona as do snippet (rodar 2x = mesmo resultado). Backup .bak-adas.
# Instalação é FAIL-CLOSED (meia-instalação é pior que nenhuma): qualquer erro aborta.
# Os hooks instalados continuam fail-open em runtime (nunca travam sessão/edição).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "✗ jq é obrigatório (apt/brew install jq)"; exit 1; }

H="$HOME/.claude/hooks"; A="$HOME/.claude/adas"; S="$HOME/.claude/settings.json"
mkdir -p "$H" "$A"

# 1) hooks — fonte única é o repo adas; instalar = copiar
cp "$DIR/adas-lib.sh" "$DIR/adas-core.sh" "$DIR/adas-activate.sh" \
   "$DIR/adas-subagent.sh" "$DIR/adas-route.sh" "$H/"
chmod +x "$H"/adas-*.sh
echo "✓ hooks copiados para $H"

# 2) repos.conf — um caminho ABSOLUTO por linha
if [ "$#" -gt 0 ]; then
  for r in "$@"; do
    rr="$(cd "$r" 2>/dev/null && pwd)" || { echo "✗ repo inexistente: $r"; exit 1; }
    [ -f "$rr/ADAS.md" ] || echo "• aviso: $rr sem ADAS.md na raiz (o núcleo reinjetado cai no fallback genérico)"
    grep -qxF "$rr" "$A/repos.conf" 2>/dev/null || echo "$rr" >> "$A/repos.conf"
  done
elif [ ! -f "$A/repos.conf" ]; then
  cp "$DIR/repos.conf.example" "$A/repos.conf"
  echo "• criado $A/repos.conf a partir do exemplo — EDITE com seus repos"
fi
echo "✓ repos.conf: $(grep -vE '^[[:space:]]*(#|$)' "$A/repos.conf" 2>/dev/null | wc -l | tr -d ' ') repo(s) governado(s)"

# 3) merge idempotente no settings.json (preserva hooks alheios; substitui só os adas-*.sh)
[ -f "$S" ] || echo '{}' > "$S"
jq -e . "$S" >/dev/null || { echo "✗ $S não é JSON válido — corrija antes de instalar"; exit 1; }
cp "$S" "$S.bak-adas"
trap 'rm -f "$S.tmp"' EXIT
jq --slurpfile snip "$DIR/settings-snippet.json" '
  def strip_adas:
    map(.hooks = ((.hooks // []) | map(select(((.command // "") | test("adas-(activate|subagent|route)\\.sh")) | not))))
    | map(select((.hooks | length) > 0));
  .hooks //= {}
  | .hooks.SessionStart  = (((.hooks.SessionStart  // []) | strip_adas) + $snip[0].hooks.SessionStart)
  | .hooks.SubagentStart = (((.hooks.SubagentStart // []) | strip_adas) + $snip[0].hooks.SubagentStart)
  | .hooks.PreToolUse    = (((.hooks.PreToolUse    // []) | strip_adas) + $snip[0].hooks.PreToolUse)
' "$S" > "$S.tmp"
jq -e '.hooks.SessionStart and .hooks.SubagentStart and .hooks.PreToolUse' "$S.tmp" >/dev/null \
  || { echo "✗ merge falhou — settings intacto (backup em $S.bak-adas)"; rm -f "$S.tmp"; exit 1; }
mv "$S.tmp" "$S"
echo "✓ hooks registrados em $S (backup: $S.bak-adas)"
echo "OK — vale a partir da PRÓXIMA sessão. Teste sem abrir sessão: host/README.md §Teste rápido"
