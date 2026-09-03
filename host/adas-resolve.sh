#!/usr/bin/env bash
# ADAS host — resolução de repo governado, CALLÁVEL por qualquer harness (não
# só Claude Code). Fina camada de CLI sobre adas_resolve()/adas_is_hub() de
# adas-lib.sh — a fonte de config (~/.claude/adas/repos.conf) e a lógica de
# match continuam num lugar só; isto só expõe pra fora do bash.
#
# Uso:
#   adas-resolve.sh <path>            → imprime a raiz do repo governado (ou nada), rc 0/1
#   adas-resolve.sh --is-hub <path>   → rc 0 se <path> é ancestral de algum repo governado
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/adas-lib.sh"

if [ "${1:-}" = "--is-hub" ]; then
  adas_is_hub "${2:-}"
  exit $?
fi

repo="$(adas_resolve "${1:-}")"
if [ -n "$repo" ]; then
  printf '%s\n' "$repo"
  exit 0
fi
exit 1
