#!/usr/bin/env bash
# check-secrets (porta 1/2): NOME_DA_CHAVE=valor só casa quando o valor PARECE chave (task 13-018). Prosa
# ("OPENAI_API_KEY: exibindo …") não reprova; chave falsa de qualquer forma plausível continua reprovando.
# Chaves FALSAS montadas em runtime (o próprio pre-commit reprovaria o literal neste arquivo).
set -uo pipefail
CHK="${CHK:-$(cd "$(dirname "$0")/.." && pwd)/check-secrets.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
caso() { # <esperado 0|1> <rótulo> <conteúdo do arquivo servido>
  local d="$T/c$RANDOM"; mkdir -p "$d/static"; printf '%s\n' "$3" > "$d/static/x.txt"
  (cd "$d" && git init -q . && git add -A && bash "$CHK" --all >/dev/null 2>&1); local rc=$?
  if [ "$rc" = "$1" ]; then echo "✓ $2 (exit $rc)"; else echo "✗ $2: esperava exit $1, veio $rc"; fail=1; fi
}
N="OPENAI""_API_KEY"
caso 0 "prosa depois do nome não reprova"            "$N: exibindo o exemplo do envelope."
caso 0 "palavra longa só de letras (<20) não reprova" "$N=placeholder"
caso 1 "chave com dígitos (16) reprova"              "$N=abcd1234efgh5678"
caso 1 "chave curta com dígito (8) reprova"          "$N=ab12cd34"
caso 1 "dígito só no fim reprova"                    "$N=abcdefghijk9"
caso 1 "20+ letras sem dígito reprova"               "$N = abcdefghijklmnopqrstuvwx"
caso 1 "ELEVENLABS com hex de 32 reprova"            "ELEVENLABS""_API_KEY=0123456789abcdef0123456789abcdef"
caso 0 "valor curto de 3 caracteres não reprova"     "$N=abc"
[ "$fail" = 0 ] && echo "TODOS OK" || echo "FALHOU"
exit "$fail"
