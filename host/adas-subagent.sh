#!/usr/bin/env bash
# ADAS host — SubagentStart. Subagents nascem com contexto isolado (o SessionStart do pai NUNCA
# chega neles) — é onde a invenção nasce. Este hook injeta o núcleo em todo subagent.
# O envelope JSON hookSpecificOutput é OBRIGATÓRIO neste evento (stdout cru é descartado).
# NÃO lê stdin (evita stall por spawn) — resolve via CLAUDE_PROJECT_DIR/cwd. Fail-open.
DIR="$(dirname "$0")"
. "$DIR/adas-lib.sh" 2>/dev/null || exit 0

base="${CLAUDE_PROJECT_DIR:-$PWD}"
repo="$(adas_resolve "$base")"
if [ -n "$repo" ]; then
  ctx="$(bash "$DIR/adas-core.sh" "$repo" 2>/dev/null || true)"
elif adas_is_hub "$base"; then
  ctx="$(adas_hub_header)"
else
  exit 0
fi
[ -n "$ctx" ] || exit 0
printf '%s' "$ctx" | jq -Rs '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:.}}' 2>/dev/null || true
exit 0
