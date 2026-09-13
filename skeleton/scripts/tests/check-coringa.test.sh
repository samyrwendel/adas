#!/usr/bin/env bash
# Teeth on BOTH sides (espelha check-memoria-da.test.sh): coringa DISPARA, mas gatilho
# de domínio e sigla curta (DA/HF) passam SEM aviso. Falso-positivo numa sigla é falha
# tão grave quanto deixar passar um '????'. Testa a função isolada (sem rodar o audit).
set -uo pipefail
CHK="$(dirname "$0")/../check-adas.sh"
# extrai SÓ a função coringa_issue do check canônico e a carrega
eval "$(awk '/^coringa_issue\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$CHK")"
fail=0
check() { # <FIRE|CLEAN> <rótulo> <conteúdo da description>
  local exp="$1" label="$2" desc="$3" tmp got
  tmp="$(mktemp)"
  printf -- '---\nname: fixture\ndescription: "%s"\n---\n# fixture · DA-001 procedência\n' "$desc" > "$tmp"
  got="$(coringa_issue "$tmp")"; rm -f "$tmp"
  if [ "$exp" = FIRE ]; then
    [ -n "$got" ] && echo "✓ $label → disparou" || { echo "✗ $label: esperava disparar, veio limpo"; fail=1; }
  else
    [ -z "$got" ] && echo "✓ $label → limpo" || { echo "✗ $label: esperava limpo, veio: $got"; fail=1; }
  fi
}

# --- lado CORINGA (deve DISPARAR) ---
check FIRE  "só pontuação '????'"      "criar arquivo; deletar; 'servidor lento'; '????'; disco cheio"
check FIRE  "ack vazio 'ok'"           "muda pra X; 'ok'; reverte decisão"
check FIRE  "ack 'pode fazer'"         "aprova a mudança na mesa; 'pode fazer'; 'aprovado'"

# --- lado LEGÍTIMO (deve passar = CLEAN) ---
check CLEAN "sigla de domínio 'DA'"    "vira 'DA' aqui; registrar; 'muda pra X'; 'reverte'"
check CLEAN "só gatilho de domínio"    "criar/deletar arquivo; 'disco cheio'; RAM alta; systemd"
check CLEAN "pergunta genérica (fora do escopo mecânico)" "credencial; token; '.env'; 'tá seguro?'"

[ "$fail" = 0 ] && echo "TODOS OK" || echo "FALHOU"
exit $fail
