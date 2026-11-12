#!/usr/bin/env bash
# taxa.test.sh — Fase 4 (taxa): `da-index.sh taxa` avisa acima de 5 DAs/dia ou 20% de adendo em 7 dias, sem reprovar;
# `da-new.sh` avisa quando a saga já ganhou 2 DAs em 48 h e cria mesmo assim. Diários em /tmp; nenhum real é tocado.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
IDX="$S/da-index.sh"; NEW="$S/da-new.sh"; ok=0; ko=0
pass() { ok=$((ok+1)); echo "  ✓ $1"; }; fail() { ko=$((ko+1)); echo "  ✗ $1"; }
gen() {  # gen <n> <n-adendo> <data> — diário com n DAs na data, as primeiras n-adendo com título de adendo
  local i t; printf '# d\n'
  for ((i=1; i<=$1; i++)); do t="t$i"; [ "$i" -le "$2" ] && t="Adendo de Mecanismo"
    printf '\n## DA-%03d — %s\n`escopo: produto` · `saga: nova/x` · `data: %s` · `tipo: regra`\n**Regra:** r\n' "$i" "$t" "$3"; done
}
taxa() { mkdir -p "$T/d"; gen "$1" "$2" "$3" > "$T/d/DECISIONS.md"; DA_TAXA_DESDE=2026-01-01 DA_TAXA_HOJE=2026-11-21 bash "$IDX" taxa "$T/d"; }
caso() {  # caso <esperado: alto|ok> <descrição> <n> <n-adendo> <data>
  local out; out="$(taxa "$3" "$4" "$5")"; local rc=$?
  case "$out" in "⚠"*) v=alto ;; *) v=ok ;; esac
  [ "$rc" = 0 ] && [ "$v" = "$1" ] && pass "$2" || fail "$2 (rc=$rc): $out"
}
echo "== 1) limites"
caso alto "36 DAs em 7 dias (5,1/dia) avisa"                 36 0 2026-11-20
caso ok   "35 DAs em 7 dias (5,0/dia) não avisa"             35 0 2026-11-20
caso alto "3 adendos em 10 (30%) avisa"                      10 3 2026-11-20
caso ok   "2 adendos em 10 (20%) não avisa"                  10 2 2026-11-20
caso ok   "2 adendos em 4: amostra abaixo de 5 não avisa"     4 2 2026-11-20
caso ok   "40 DAs fora da janela não contam"                 40 0 2026-11-07
echo "== 2) adendo pela linha de Mecanismo; DA sem data fica fora e é declarada; corte da casa"
printf '# d\n\n## DA-001 — a\n**Regra:** r\n\n## DA-002 — b\n`data: 2026-11-21`\n**Mecanismo da DA-001:** `x`\n' > "$T/d/DECISIONS.md"
out="$(DA_TAXA_DESDE=2026-01-01 DA_TAXA_HOJE=2026-11-21 DA_TAXA_MIN=1 bash "$IDX" taxa "$T/d")"
grep -q 'adendo 1/1' <<< "$out" && grep -q '1 sem data, fora da conta' <<< "$out" && pass "linha **Mecanismo da DA-NNN:** conta como adendo; DA sem data declarada" || fail "adendo/sem data: $out"
gen 40 0 2026-11-20 > "$T/d/DECISIONS.md"; mkdir -p "$T/d/.adas"; echo 2026-11-21 > "$T/d/.adas/taxa-desde"
out="$(DA_TAXA_HOJE=2026-11-21 bash "$IDX" taxa "$T/d")"; case "$out" in "⚠"*) fail "corte da casa ignorado: $out" ;; *) pass ".adas/taxa-desde: DA anterior ao corte não conta" ;; esac
rm -rf "$T/d/.adas"
echo "== 3) da-new.sh: aviso de saga recente, sem bloquear"
mkdir -p "$T/n"; printf '# d\n' > "$T/n/DECISIONS.md"
novo() { bash "$NEW" --tipo regra produto "$1" "$2" "$T/n" 2>&1 >/dev/null; }
e1="$(novo nova/ponte a)"; e2="$(novo nova/ponte b)"; e3="$(novo ponte c)"; e4="$(novo nova/outra d)"
[ -z "$(grep '⚠ da-new' <<< "$e1$e2")" ] && pass "1ª e 2ª DA da saga: sem aviso" || fail "avisou cedo demais: $e1 $e2"
grep -q "⚠ da-new: a saga 'ponte' já ganhou 2 DA" <<< "$e3" && grep -q 'Quando é DA' <<< "$e3" \
  && pass "3ª DA da saga em 48 h: aviso com a lista e o critério (nova/<slug> = <slug>)" || fail "3ª DA sem aviso: $e3"
[ -z "$(grep '⚠ da-new' <<< "$e4")" ] && pass "outra saga: sem aviso" || fail "avisou em outra saga: $e4"
[ "$(grep -c '^## DA-' "$T/n/DECISIONS.md")" = 4 ] && pass "o aviso não bloqueia: as 4 DAs foram criadas" || fail "aviso bloqueou a criação"
e5="$(DA_NEW_HOJE="$(date -d '+3 days' +%F 2>/dev/null || date -v+3d +%F)" novo ponte e)"
[ -z "$(grep '⚠ da-new' <<< "$e5")" ] && pass "3 dias depois: fora da janela, sem aviso" || fail "avisou fora da janela: $e5"
bash "$NEW" --quando | grep -q 'texto para calar um check' && pass "--quando imprime o critério" || fail "--quando"
echo "taxa: $ok ok, $ko falha(s)"; [ "$ko" = 0 ]
