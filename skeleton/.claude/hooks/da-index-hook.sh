#!/usr/bin/env bash
# da-index-hook.sh — PostToolUse (Edit|Write|MultiEdit): quando o arquivo editado é um
# DECISIONS.md, regenera o DECISIONS-INDEX.md NO ATO — a entrada do índice NASCE com a DA,
# sem depender de boa vontade de quem anexa (o agente não tem como pular este caminho ao
# editar pela ferramenta; anexos por shell são pegos pelo check 10 do check-adas).
# Fail-open: erro aqui nunca bloqueia a edição nem trava a sessão.
payload="$(cat 2>/dev/null || true)"
f="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
case "$f" in */DECISIONS.md) ;; *) exit 0 ;; esac
d="$(dirname "$f")"
for s in "$d/scripts/da-index.sh" "$HOME/scripts/da-index.sh"; do
  [ -f "$s" ] && { bash "$s" update "$d" >/dev/null 2>&1 || true; break; }
done
exit 0
