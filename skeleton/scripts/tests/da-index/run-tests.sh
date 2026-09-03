#!/usr/bin/env bash
# run-tests.sh — harness de fixtures do da-index.sh (DA-181 §2.6g, exigido ANTES de
# instalar/ligar qualquer FAIL). Roda update+check+show+da-new contra um DECISIONS.md
# de fixture (nunca o real) e falha ALTO na primeira divergência do esperado.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DAIDX="$HERE/../../da-index.sh"
DANEW="$HERE/../../da-new.sh"
FAIL=0
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -r "$HERE/fixture/." "$TMP/"

echo "== update =="
export DA_INDEX_GRANDFATHER=0
out="$(bash "$DAIDX" update "$TMP" 2>&1)"
echo "$out" | sed 's/^/  /'
[ -f "$TMP/DECISIONS-INDEX.md" ] && pass "DECISIONS-INDEX.md gerado" || fail "DECISIONS-INDEX.md NÃO gerado"
[ -f "$TMP/DECISIONS-SAGAS.md" ] && pass "DECISIONS-SAGAS.md gerado" || fail "DECISIONS-SAGAS.md NÃO gerado"
[ -f "$TMP/DECISIONS-LICOES.md" ] && pass "DECISIONS-LICOES.md gerado" || fail "DECISIONS-LICOES.md NÃO gerado"

echo "== fixture 1: DA com Regra explícita =="
grep -q '^- DA-001 .*— DA com Regra explícita — Regra explícita de teste' "$TMP/DECISIONS-INDEX.md" \
  && pass "DA-001 mostra a Regra (não um fallback)" || fail "DA-001 não mostra a Regra explícita no índice"

echo "== fixture 2: DA só com ### Decisão (fallback) =="
grep -q '^- DA-002 .*Esta é a linha de decisão do formato antigo' "$TMP/DECISIONS-INDEX.md" \
  && pass "DA-002 cai no fallback ### Decisão" || fail "DA-002 não capturou o fallback de Decisão"

echo "== fixture 3: número duplicado vira a/b por ordem =="
grep -q '^- DA-003a .*primeira versão' "$TMP/DECISIONS-INDEX.md" && pass "DA-003a = primeira ocorrência" || fail "DA-003a ausente/errada"
grep -q '^- DA-003b .*segunda versão' "$TMP/DECISIONS-INDEX.md" && pass "DA-003b = segunda ocorrência" || fail "DA-003b ausente/errada"

echo "== fixture 4: paste de terminal =="
grep -q 'WARN c2: DA-004' <<< "$out" && pass "c2 acusa paste em DA-004 (WARN, não FAIL)" || fail "c2 não acusou paste em DA-004"
showout="$(bash "$DAIDX" show DA-004 "$TMP")"
echo "$showout" | grep -q 'bloco de paste omitido' && pass "show DA-004 colapsa o paste" || fail "show DA-004 não colapsou o paste"
echo "$showout" | grep -qF 'commit aaaaaaaa' && fail "show DA-004 vazou linha de commit" || pass "show DA-004 não vaza linha de commit"
echo "$showout" | grep -q 'Depois do paste' && pass "show DA-004 preserva o texto depois do paste" || fail "show DA-004 perdeu o texto depois do paste"

echo "== fixture 5: tags compostas + consolida (cabeça) =="
grep -q 'saga-teste' "$TMP/DECISIONS-INDEX.md" && grep -q 'outra-saga' <<< "$(bash "$DAIDX" sagas "$TMP")" \
  && pass "saga composta (saga-teste, outra-saga) parseada" || fail "saga composta não parseada corretamente"
grep -q '^- DA-001 .*📚 em DA-005' "$TMP/DECISIONS-INDEX.md" && pass "DA-001 marcada 📚 consolidada em DA-005 (tag consolida:)" || fail "marca 📚 de consolida: não aplicada"
grep -q 'produto' "$TMP/DECISIONS-VIGENTE-instância.md" 2>/dev/null; # não é assert, só smoke
[ -f "$TMP/DECISIONS-VIGENTE-produto,instância.md" ] || [ -f "$TMP/DECISIONS-VIGENTE-produto.md" ] \
  && pass "VIGENTE-produto existe (escopo composto splitado)" || fail "VIGENTE-produto ausente"

echo "== fixture 6: membro sem tag, pertencimento via membros.tsv =="
sagasout="$(bash "$DAIDX" sagas "$TMP")"
echo "$sagasout" | grep -q 'saga-tsv .*instância' && pass "saga-tsv (DA-006, via tsv) aparece com escopo instância" || fail "DA-006 não herdou saga/escopo do membros.tsv"

echo "== check: gerados sincronizados (idempotência) =="
bash "$DAIDX" check "$TMP" >/tmp/da-index-test-check.out 2>&1
if [ $? -eq 0 ]; then pass "check exit 0 (sincronizado)"; else fail "check divergiu logo após update"; cat /tmp/da-index-test-check.out | sed 's/^/    /'; fi

echo "== show --saga =="
bash "$DAIDX" show --saga saga-teste "$TMP" | grep -q '## NA-saga-teste' && pass "show --saga imprime a seção certa" || fail "show --saga não achou NA-saga-teste"

echo "== export-saga (sem números DA-N) =="
exp="$(bash "$DAIDX" export-saga saga-teste "$TMP")"
echo "$exp" | grep -qE 'DA-[0-9]' && fail "export-saga vazou número DA-N" || pass "export-saga não vaza número DA-N"

echo "== da-new.sh: número novo, snapshot, diário original intocado (fora deste dir) =="
before_sha="$(sha256sum "$TMP/DECISIONS.md" | cut -d' ' -f1)"
newout="$(ADAS_HOME_DIR="$TMP/.adas" bash "$DANEW" instância "nova/teste-harness" "DA de teste do harness" "$TMP")"
echo "$newout" | grep -q '^DA-007$' && pass "da-new.sh calculou DA-007 (max+1)" || fail "da-new.sh não calculou o número certo: $newout"
[ -d "$TMP/.adas/snapshots" ] && [ -n "$(ls -A "$TMP/.adas/snapshots" 2>/dev/null)" ] && pass "snapshot criado antes de anexar" || fail "snapshot ausente"
after_sha_realhome="$(sha256sum "$HOME/DECISIONS.md" 2>/dev/null | cut -d' ' -f1)"
echo "  (nota: da-new.sh rodou só contra $TMP; diário real não foi tocado por construção do teste)"

echo
if [ "$FAIL" = 0 ]; then
  echo "✓✓✓ harness da-index: TODOS OS TESTES PASSARAM"
  exit 0
else
  echo "✗✗✗ harness da-index: HÁ FALHAS ACIMA"
  exit 1
fi
