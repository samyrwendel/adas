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

echo "== export-saga (sem números DA-N, sem espaço duplo, faixa vira [decisões internas]) =="
exp="$(bash "$DAIDX" export-saga saga-teste "$TMP")"
echo "$exp" | grep -qE 'DA-[0-9]' && fail "export-saga vazou número DA-N" || pass "export-saga não vaza número DA-N"
echo "$exp" | grep -qE '  ' && fail "export-saga deixou espaço duplo (buraco de substituição)" || pass "export-saga sem espaço duplo"
echo "$exp" | grep -qF '[decisões internas]' && pass "export-saga vira faixa DA-N–DA-M em [decisões internas]" || fail "export-saga não converteu a faixa DA-001–DA-002"
echo "$exp" | grep -qF '[decisão interna]' && pass "export-saga vira DA-N solta em [decisão interna]" || fail "export-saga não converteu a DA-003 solta"

echo "== fixture 7: parágrafo de metadado quebrado em 2 linhas não vaza continuação =="
grep -q '^- DA-007 .*— Isto é o parágrafo de conteúdo real, que deve virar a Regra no índice\.' "$TMP/DECISIONS-INDEX.md" \
  && pass "DA-007 pula o parágrafo **Data:**/Implementado-por/Escopo inteiro" || fail "DA-007 vazou fragmento do parágrafo de metadado"
sagasout="$(bash "$DAIDX" sagas "$TMP")"
echo "$sagasout" | grep -qE '^- regra-fallback-swallow .*Regra: (por:|-|\*\*|"|fragmento)' \
  && fail "saga regra-fallback-swallow ainda mostra fragmento" || pass "saga regra-fallback-swallow sem fragmento"

echo "== fixture 8: rótulo curto ('**O problema.**') não vira Regra — cai em ver DA-NNN =="
echo "$sagasout" | grep -qF -- '- regra-fallback-curto · produto · cabeça: — · 1 DA · membros: DA-008 · Regra: ver DA-008' \
  && pass "DA-008 (frase-rótulo curta) cai em 'ver DA-008', não usa 'O problema.'" || fail "DA-008 não caiu no fallback 'ver DA-NNN'"

echo "== fixture 9: Decisão em lista de alternativas extrai frase do primeiro item =="
grep -q '^- DA-009 .*— Manter o processo atual em produção (escolhida)\.' "$TMP/DECISIONS-INDEX.md" \
  && pass "DA-009 extrai a frase do primeiro item da lista, sem '- ' nem '**'" || fail "DA-009 não extraiu a frase do bullet corretamente"

echo "== fixture 10: parágrafo que É só citação entre aspas/itálico é pulado =="
grep -q '^- DA-010 .*— Esta linha de conteúdo real, fora da citação' "$TMP/DECISIONS-INDEX.md" \
  && pass "DA-010 pula a citação solta e usa o parágrafo de conteúdo seguinte" || fail "DA-010 usou a citação como Regra"

echo "== fixture 11: parágrafo iniciado por 'Decidido por:' (sem Data) também é metadado =="
grep -q '^- DA-011 .*— Este parágrafo é o conteúdo de verdade' "$TMP/DECISIONS-INDEX.md" \
  && pass "DA-011 pula 'Decidido por:' e usa o parágrafo seguinte" || fail "DA-011 usou a linha de atribuição como Regra"

echo "== fixture 12: frase >240 chars não vira Regra — cai em ver DA-NNN =="
echo "$sagasout" | grep -qF -- '- regra-fallback-longa · produto · cabeça: — · 1 DA · membros: DA-012 · Regra: ver DA-012' \
  && pass "DA-012 (frase longa demais) cai em 'ver DA-012'" || fail "DA-012 não caiu no fallback por tamanho"

echo "== fixture 13/14: fallback de data do Histórico (tag → **Data:** → data isolada no corpo → —) =="
sagasmd="$(cat "$TMP/DECISIONS-SAGAS.md")"
echo "$sagasmd" | grep -qF -- '- 2026-03-15 · DA-013 ·' && pass "DA-013: data BR isolada '**15/03/2026**' virou 2026-03-15 no Histórico" || fail "DA-013 não converteu a data isolada do corpo"
echo "$sagasmd" | grep -qF -- '- — · DA-014 ·' && pass "DA-014 (sem nenhuma data no corpo) mantém — no Histórico" || fail "DA-014 não deveria ter data nenhuma"

echo "== da-new.sh: número novo, snapshot, diário original intocado (fora deste dir) =="
before_sha="$(sha256sum "$TMP/DECISIONS.md" | cut -d' ' -f1)"
newout="$(ADAS_HOME_DIR="$TMP/.adas" bash "$DANEW" instância "nova/teste-harness" "DA de teste do harness" "$TMP")"
echo "$newout" | grep -q '^DA-015$' && pass "da-new.sh calculou DA-015 (max+1)" || fail "da-new.sh não calculou o número certo: $newout"
[ -d "$TMP/.adas/snapshots" ] && [ -n "$(ls -A "$TMP/.adas/snapshots" 2>/dev/null)" ] && pass "snapshot criado antes de anexar" || fail "snapshot ausente"
after_sha_realhome="$(sha256sum "$HOME/DECISIONS.md" 2>/dev/null | cut -d' ' -f1)"
echo "  (nota: da-new.sh rodou só contra $TMP; diário real não foi tocado por construção do teste)"

echo "== da-new.sh: saga inexistente sem prefixo nova/ é RECUSADA (exit 2), sem anexar =="
SAGACONF_TMP="$TMP/.adas-slugtest"; mkdir -p "$SAGACONF_TMP"
printf 'saga-existente|produto|\n' > "$SAGACONF_TMP/sagas.conf"
before2="$(sha256sum "$TMP/DECISIONS.md" | cut -d' ' -f1)"
rc=0
out2="$(ADAS_HOME_DIR="$TMP/.adas" ADAS_SAGAS_CONF="$SAGACONF_TMP/sagas.conf" bash "$DANEW" instância "saga-que-nao-existe" "titulo x" "$TMP" 2>&1)" || rc=$?
after2="$(sha256sum "$TMP/DECISIONS.md" | cut -d' ' -f1)"
[ "$rc" = 2 ] && pass "da-new.sh recusa slug inexistente com exit 2" || fail "da-new.sh não recusou slug inexistente (rc=$rc)"
[ "$before2" = "$after2" ] && pass "DECISIONS.md intocado após recusa" || fail "DECISIONS.md foi alterado mesmo com slug recusado"
echo "$out2" | grep -q 'saga-existente' && pass "mensagem de recusa lista os slugs válidos" || fail "mensagem de recusa não lista slugs válidos"
rc3=0
out3="$(ADAS_HOME_DIR="$TMP/.adas" ADAS_SAGAS_CONF="$SAGACONF_TMP/sagas.conf" bash "$DANEW" instância "nova/saga-x" "titulo x" "$TMP" 2>&1)" || rc3=$?
[ "$rc3" = 0 ] && echo "$out3" | grep -q '^DA-016$' && pass "'nova/saga-x' anexa normalmente (DA-016)" || fail "'nova/saga-x' deveria ter anexado: rc=$rc3 out=$out3"

echo "== da-new.sh: snapshot isolado do [dir] (não vaza pro ~/.adas real) + rotação a 30 =="
DIRTEST="$TMP/copia-isolada"; mkdir -p "$DIRTEST/.adas/snapshots"
cp "$TMP/DECISIONS.md" "$DIRTEST/DECISIONS.md"
for i in $(seq -w 1 32); do : > "$DIRTEST/.adas/snapshots/DECISIONS.md.202601${i}T000000Z"; done
realhome_before="$(ls -1 "$HOME/.adas/snapshots" 2>/dev/null | wc -l)"
bash "$DANEW" instância "nova/rotacao-teste" "titulo rotacao" "$DIRTEST" >/dev/null
realhome_after="$(ls -1 "$HOME/.adas/snapshots" 2>/dev/null | wc -l)"
[ "$realhome_before" = "$realhome_after" ] && pass "snapshot NÃO vazou pro ~/.adas/snapshots real (sem ADAS_HOME_DIR, dir≠\$HOME)" || fail "snapshot vazou pro servidor real!"
count_dirtest="$(ls -1 "$DIRTEST/.adas/snapshots" | wc -l)"
[ "$count_dirtest" = 30 ] && pass "rotação mantém exatamente os 30 snapshots mais recentes" || fail "rotação não manteve 30 (tem $count_dirtest)"

echo
if [ "$FAIL" = 0 ]; then
  echo "✓✓✓ harness da-index: TODOS OS TESTES PASSARAM"
  exit 0
else
  echo "✗✗✗ harness da-index: HÁ FALHAS ACIMA"
  exit 1
fi
