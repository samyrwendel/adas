#!/usr/bin/env bash
# ADAS host — PreToolUse (matcher: Edit|Write|MultiEdit). Roteia a injeção JIT por faixa para
# sessões que NÃO nascem dentro do repo (ex.: hub multi-repo), onde os .claude/settings.json
# aninhados dos repos NÃO carregam (Claude Code só carrega project-root da sessão + user settings).
# Guard anti-injeção-dupla: se CLAUDE_PROJECT_DIR é o próprio repo, o hook de projeto já cobre
# (settings de user+projeto são MESCLADOS). Delega ao script canônico do repo — o texto da faixa
# continua versionado com o código dele. Fail-open.
DIR="$(dirname "$0")"
. "$DIR/adas-lib.sh" 2>/dev/null || exit 0

# stdin do PreToolUse é confiável (payload fechado pelo host) — cat direto; um timeout
# curto podia TRUNCAR payload grande e falhar aberto sem injetar (o receio de stall é
# só do SubagentStart, que por isso nem lê stdin).
payload="$(cat 2>/dev/null || true)"
f="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -n "$f" ] || exit 0

repo="$(adas_resolve "$f")"
[ -n "$repo" ] || exit 0

case "${CLAUDE_PROJECT_DIR:-}" in
  "$repo"|"$repo"/*) exit 0 ;;
esac

inj="$repo/.claude/hooks/adas-inject.sh"
[ -f "$inj" ] || exit 0
printf '%s' "$payload" | bash "$inj" 2>/dev/null || true
exit 0
