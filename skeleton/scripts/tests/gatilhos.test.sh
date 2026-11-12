#!/usr/bin/env bash
# gatilhos.test.sh — `da-index.sh gatilhos` (ADAS-JIT, DA-468): linha na própria DA/DC, adendo
# "Gatilho da DX-NNN" vindo de DA posterior, ausência = sem saída, e da-new.sh nasce com a linha.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; IDX="$HERE/../da-index.sh"; NEW="$HERE/../da-new.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; ok=0; ko=0
pass(){ echo "  ✓ $1"; ok=$((ok+1)); }; fail(){ echo "  ✗ $1"; ko=$((ko+1)); }
cat > "$T/DECISIONS.md" <<'D'
## DA-001 — sem gatilho
**Regra:** x
## DA-002 — com gatilho
**Regra:** y
**Gatilho:** forma · reply · juiz · modo=aviso
## DA-003 — rodada de rótulos
**Regra:** z
**Gatilho da DC-007:** forma · reply · juiz
**Gatilho da DA-002:** forma · reply · juiz · modo=deny
D
printf '## DC-007 — c\n**Regra:** w\n' > "$T/CONDUCT.md"
out="$(bash "$IDX" gatilhos "$T")"
[ "$(echo "$out" | grep -c .)" = 3 ] && pass "3 linhas (DA-001 sem gatilho não sai)" || fail "esperava 3 linhas: $out"
grep -qP '^DA-002\tforma · reply · juiz · modo=aviso\tDA-002$' <<< "$out" && pass "linha na própria DA" || fail "própria DA"
grep -qP '^DC-007\tforma · reply · juiz\tDA-003$' <<< "$out" && pass "adendo de DC numa DA posterior" || fail "adendo DC"
[ "$(echo "$out" | grep '^DA-002' | tail -1 | cut -f2)" = "forma · reply · juiz · modo=deny" ] && pass "última linha do id vence (adendo)" || fail "ordem"
mkdir -p "$T/.adas"; printf 'saga-x|\n' > "$T/.adas/sagas.conf"
ADAS_HOME_DIR="$T/.adas" bash "$NEW" --tipo regra produto saga-x "nova" "$T" >/dev/null 2>&1
# Procura no BLOCO da DA criada (a última), não na última linha: o molde ganhou linhas depois do Gatilho.
blk="$(awk '/^## DA-/{b=""} {b=b $0 "\n"} END{printf "%s", b}' "$T/DECISIONS.md")"
[ "$(printf '%b' "$blk" | grep -c '^\*\*Gatilho:\*\*')" = 1 ] && <<<"$(printf '%b' "$blk")" grep -qxE '\*\*Gatilho:\*\* ?' \
  && pass "da-new.sh emite uma linha **Gatilho:** vazia no bloco (Gatilho nasce vazio)" || fail "template sem Gatilho vazio"
echo "gatilhos: $ok ok, $ko falha(s)"; [ "$ko" = 0 ]
