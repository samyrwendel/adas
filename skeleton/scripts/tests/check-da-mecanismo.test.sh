#!/usr/bin/env bash
# Dentes dos dois lados (DA-004 deste repo): DA nova que proíbe sem trava REPROVA; com trava
# real passa; "só" fora da Regra não dispara; caminho inventado não conta como trava; DA antiga
# vira WARN (fila), não FAIL.
set -uo pipefail
CHK="$(cd "$(dirname "$0")/.." && pwd)/check-da-mecanismo.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts"; : > "$T/scripts/trava-real.sh"
fail=0

caso() { # <esperado: FAIL|OK|WARN> <rótulo> <corpo da DA (sem cabeçalho)>
  local exp="$1" label="$2" body="$3" out rc got
  printf '# diário\n\n## DA-900 — fixture\n%s\n' "$body" > "$T/DECISIONS.md"
  out="$(bash "$CHK" --list "$T/DECISIONS.md" "$T")"; rc=$?
  if printf '%s\n' "$out" | grep -q '^FAIL DA-900'; then got=FAIL
  elif printf '%s\n' "$out" | grep -q '^WARN DA-900'; then got=WARN
  else got=OK; fi
  if [ "$got" = "$exp" ] && { [ "$exp" != FAIL ] || [ "$rc" -ne 0 ]; } && { [ "$exp" = FAIL ] || [ "$rc" -eq 0 ]; }; then
    echo "✓ $label → $got (exit $rc)"
  else
    echo "✗ $label: esperava $exp, veio $got (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
}

META_NOVA='`escopo: produto` · `saga: x` · `data: 2026-10-01` · `refs: —`'
META_VELHA='`escopo: produto` · `saga: x` · `data: 2026-09-01` · `refs: —`'

caso FAIL "DA nova proíbe (nunca) sem Mecanismo" "$META_NOVA
**Regra:** O robô nunca escreve no estado real durante teste.
**Motivo:** incidente."

caso FAIL "DA nova com 'só' na Regra multi-linha, sem Mecanismo" "$META_NOVA
**Regra:** Aviso de conta sai
só pelo bot dedicado.
**Motivo:** x."

caso OK "DA nova proíbe COM Mecanismo e caminho real" "$META_NOVA
**Regra:** O robô nunca escreve no estado real durante teste.
**Mecanismo:** \`scripts/trava-real.sh\` reprova a suíte que toque o estado real.
**Motivo:** x."

caso OK "Mecanismo com rótulo estendido e nome solto em scripts/" "$META_NOVA
**Regra:** Proibido usar o token do mainbot.
**Mecanismo (o que reprova a violação):** trava-real.sh no pre-commit.
**Motivo:** x."

caso FAIL "Mecanismo cita caminho que NÃO existe" "$META_NOVA
**Regra:** Jamais apagar o diário.
**Mecanismo:** \`scripts/trava-inventada.sh\` (ainda não existe).
**Motivo:** x."

caso OK "'só' fora da Regra (no Motivo) não dispara" "$META_NOVA
**Regra:** Commit leva a mensagem no padrão convencional.
**Motivo:** só assim o changelog sai sozinho; nunca foi diferente.
**Lição:** somente registro."

caso OK "palavra que CONTÉM 'só' (sócio, sólido) não dispara" "$META_NOVA
**Regra:** O sócio aprova a arquitetura sólida antes do deploy."

caso WARN "DA antiga (antes do corte) sem Mecanismo vira fila" "$META_VELHA
**Regra:** Nunca rodar dry-run sem ler o script inteiro."

caso WARN "DA antiga no formato **Data:** inline" "**Status:** ✅ Aceita · **Data:** 2026-09-03
**Regra:** Somente o dono aprova."

caso WARN "DA sem data e sem corte gravado vira fila" "**Regra:** Nunca publicar sem o gate."

mkdir -p "$T/.adas"; echo 899 > "$T/.adas/da-mecanismo-corte"
caso FAIL "DA sem data ACIMA do corte por número (.adas/da-mecanismo-corte)" "**Regra:** Nunca publicar sem o gate."
echo 900 > "$T/.adas/da-mecanismo-corte"
caso WARN "DA sem data no corte (<=) segue fila" "**Regra:** Nunca publicar sem o gate."
rm -rf "$T/.adas"

# adendo (append-only): uma DA POSTERIOR dá o mecanismo à antiga com "**Mecanismo da DA-NNN:**"
adendo() { # <OK|WARN> <rótulo> <linha de adendo>
  printf '# diário\n\n## DA-900 — antiga\n%s\n**Regra:** Nunca publicar sem o gate.\n\n## DA-901 — adendo\n%s\n**Regra:** Declara mecanismos.\n%s\n' \
    "$META_VELHA" "$META_VELHA" "$3" > "$T/DECISIONS.md"
  local out got; out="$(bash "$CHK" --list "$T/DECISIONS.md" "$T")"
  printf '%s\n' "$out" | grep -q '^WARN DA-900' && got=WARN || got=OK
  [ "$got" = "$1" ] && echo "✓ $2 → $got" || { echo "✗ $2: esperava $1, veio $got"; fail=1; }
}
adendo OK   "adendo com caminho real tira a DA antiga da fila" '**Mecanismo da DA-900:** `scripts/trava-real.sh` reprova a publicação sem gate.'
adendo WARN "adendo com caminho inventado não conta"            '**Mecanismo da DA-900:** `scripts/trava-inventada.sh`.'
adendo WARN "adendo pra OUTRA DA não vale pra esta"             '**Mecanismo da DA-899:** `scripts/trava-real.sh`.'

# ponta a ponta: o check-adas.sh (ao lado) BLOQUEIA (exit 1) com a mesma DA nova sem trava
ADAS_CHK="$(dirname "$CHK")/check-adas.sh"
if [ -f "$ADAS_CHK" ]; then
  printf '# diário\n\n## DA-900 — fixture\n%s\n**Regra:** Nunca X.\n' "$META_NOVA" > "$T/DECISIONS.md"
  out="$(cd "$T" && DECISIONS="$T/DECISIONS.md" bash "$ADAS_CHK" "$T" 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF "sem **Mecanismo:** que exista"; then echo "✓ check-adas.sh bloqueia (exit 1)"
  else echo "✗ check-adas.sh não bloqueou (exit $rc)"; fail=1; fi
fi

[ "$fail" = 0 ] && echo "TODOS OK" || echo "FALHOU"
exit $fail
