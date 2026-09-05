#!/usr/bin/env bash
# memoria-da-guard.sh — hook PostToolUse (Write|Edit|MultiEdit), mecanização da DA-199.
#
# JIT no ATO da escrita (DA-205): quando alguém grava uma REGRA DE TRABALHO na memória
# privada de um agente em vez de registrar DA, AVISA — não bloqueia. PostToolUse roda
# DEPOIS da escrita, então por construção não trava agente headless (a escrita já
# aconteceu). Só emite additionalContext quando o veredito é RULE (estrito: exige eixo
# normativo + trabalho e AUSÊNCIA de sinal de preferência — protege preferência de
# falso-positivo, que a DA-199 diz ser falha tão grave quanto vazar regra).
# Fail-open em tudo. O cérebro é check-memoria-da.sh; a rede de domingo é governance-audit.sh.
payload="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0

f="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -n "$f" ] || exit 0
# só dentro da memória privada de um agente
case "$f" in
  */.claude/projects/*/memory/*.md) ;;
  *) exit 0 ;;
esac
case "$f" in */memory/MEMORY.md) exit 0 ;; esac   # índice, não é nota

# conteúdo escrito: Write=.content · Edit=.new_string · MultiEdit=join(.edits[].new_string)
content="$(printf '%s' "$payload" | jq -r '
  .tool_input.content
  // .tool_input.new_string
  // ([.tool_input.edits[]?.new_string] | join("\n"))
  // empty' 2>/dev/null || true)"
[ -n "$content" ] || exit 0

CHK="${MEMORIA_DA_CHK:-$HOME/scripts/check-memoria-da.sh}"
[ -x "$CHK" ] || exit 0
out="$(printf '%s' "$content" | bash "$CHK" classify 2>/dev/null)" || exit 0
case "$out" in
  RULE*) ;;                # só avisa no veredito estrito
  *) exit 0 ;;
esac
reason="$(printf '%s' "$out" | cut -f2)"

msg="⚠️ ADAS/DA-199 — isto parece REGRA DE TRABALHO em memória privada (${reason}). Memória privada não governa outro agente: quem executa a task não lê a memória de quem a escreveu (caso medido, DA-198). AÇÃO: registre no diário de decisões — ~/scripts/da-new.sh <escopo> <saga> \"<título>\" — e deixe AQUI só o ponteiro (\"regra vive na DA-NNN\"). Se for só PREFERÊNCIA de interação/identidade (idioma, tom, formato, quem é o dono), ignore este aviso: memória é o lugar certo."
jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
