#!/usr/bin/env bash
# Teeth on BOTH sides (DA-199 criterion 1): preferência passa SEM aviso; regra de
# trabalho dispara. Falso-positivo em preferência = falha tão grave quanto vazar regra.
set -uo pipefail
CHK="$(dirname "$0")/../check-memoria-da.sh"
fail=0
check() { # <esperado RULE|MAYBE|CLEAN> <descrição> <conteúdo>
  local exp="$1" desc="$2" content="$3" got
  got="$(printf '%s' "$content" | bash "$CHK" classify | cut -f1)"
  if [ "$got" = "$exp" ]; then echo "✓ $desc → $got"
  else echo "✗ $desc: esperado $exp, veio $got"; fail=1; fi
}

# --- lado PREFERÊNCIA/IDENTIDADE (deve passar = CLEAN) ---
check CLEAN "responder sempre em pt-BR"        "Responder sempre em português do Brasil, especialmente no Telegram."
check CLEAN "o dono se chama X"                 "O dono se chama Samyr e prefere ser chamado de Samyr."
check CLEAN "nunca usar emoji em excesso"       "Nunca usar emoji em excesso na resposta; tom sóbrio."
check CLEAN "sem markdown no telegram"          "Não usar tabela markdown no Telegram, que não renderiza."
check CLEAN "ponteiro pra DA"                   "Contexto do projeto X. Regra vive na DA-183, aqui só o ponteiro."

# --- lado REGRA DE TRABALHO (deve disparar = RULE) ---
check RULE  "antes de injetar task, conferir"  "Antes de injetar task pro agente, conferir a fila aberta dele."
check RULE  "nunca use axon-requeue vivo"       "Nunca use axon-requeue.sh com o worker vivo; faça refund e encerre."
check RULE  "commit por path, nunca add -A"     "Sempre commitar por path explícito no repo; nunca git add -A entre agentes."
check RULE  "sempre conferir antes de despachar" "Sempre verificar o modelo do worker antes de despachar a task no bus."

# --- lado AMBÍGUO (regra de trabalho + interação → MAYBE, dono decide) ---
check MAYBE "regra de trabalho com termo de interação" "Sempre responder a task do bus confirmando o escopo antes de commitar."

[ "$fail" = 0 ] && echo "TODOS OK" || echo "FALHOU"
exit $fail
