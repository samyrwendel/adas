#!/usr/bin/env bash
# ADAS host — guarda mecânica de "não vasculhar credencial fora do local
# apontado" (faixa seguranca-acesso, regra 2: skeleton/.claude/skills/
# seguranca-acesso/SKILL.md). Detecta se um COMANDO DE SHELL lê/imprime um
# .env real (não .env.example/.sample/.template) — o caso concreto do
# critério de teste desta faixa ("cat .env fora do lugar").
#
# Complementa, não substitui, scripts/check-secrets.sh (que bloqueia SEGREDO
# entrando no COMMIT via padrão de conteúdo — chave AWS, token GitHub etc.).
# Este guarda o INSTANTE do TOOL CALL, antes do comando rodar — é o que os
# harnesses com pre_tool_call/before_tool_call bloqueante (OpenClaw, Hermes)
# conseguem fazer que o Claude Code hoje não faz (ADAS nele só injeta
# contexto no PreToolUse, nunca bloqueia — ver README, seção Claude Code).
#
# Uso: adas-secret-guard.sh "<comando de shell>"
# Saída (stdout): "allow" ou "block:<motivo>". Sempre rc 0 — quem chama decide
# o que fazer com o texto (fail-open na AUSÊNCIA de comando, nunca na
# presença de um padrão proibido).
cmd="${1:-}"
[ -z "$cmd" ] && { echo "allow"; exit 0; }

if printf '%s' "$cmd" | grep -qE '\b(cat|less|more|head|tail|type|bat)\b[^;&|]*\.env\b' \
  && ! printf '%s' "$cmd" | grep -qE '\.env\.(example|sample|template)\b'; then
  printf 'block:seguranca-acesso regra 2 — NUNCA vasculhar/imprimir .env fora do local explicitamente apontado pelo usuário (SKILL.md). Comando recusado: %s\n' "$cmd"
  exit 0
fi
echo "allow"
