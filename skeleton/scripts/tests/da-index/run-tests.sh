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
tem(){ local rc; grep -q "$@"; rc=$?; cat >/dev/null; return "$rc"; }   # grep -q que drena o resto: sob pipefail, produtor que escreve depois do match levava SIGPIPE (141)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -r "$HERE/fixture/." "$TMP/"

echo "== update =="
export DA_INDEX_GRANDFATHER=0
out="$(bash "$DAIDX" update "$TMP" 2>&1)"
echo "$out" | sed 's/^/  /'
[ -f "$TMP/DECISIONS-INDEX.md" ] && pass "DECISIONS-INDEX.md gerado" || fail "DECISIONS-INDEX.md NÃO gerado"
[ -f "$TMP/DECISIONS-SAGAS.md" ] && fail "DECISIONS-SAGAS.md ainda é gerado (maquinaria de saga desligada — task 20260906-028)" || pass "DECISIONS-SAGAS.md NÃO é mais gerado (task 028)"
grep -qE "WARN c(9|12):" <<< "$out" && fail "update ainda emite c9/c12 (desligados na task 028)" || pass "update não emite c9 nem c12"
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
grep -q 'FAIL c2: DA-004' <<< "$out" && pass "c2 acusa paste em DA-004 (FAIL — emenda DA-278)" || fail "c2 não acusou paste (FAIL) em DA-004"
showout="$(bash "$DAIDX" show DA-004 "$TMP")"
grep -q 'bloco de paste omitido' <<< "$showout" && pass "show DA-004 colapsa o paste" || fail "show DA-004 não colapsou o paste"
grep -qF 'commit aaaaaaaa' <<< "$showout" && fail "show DA-004 vazou linha de commit" || pass "show DA-004 não vaza linha de commit"
grep -q 'Depois do paste' <<< "$showout" && pass "show DA-004 preserva o texto depois do paste" || fail "show DA-004 perdeu o texto depois do paste"

echo "== fixture 5: tags compostas + consolida (cabeça) =="
grep -q 'saga-teste' "$TMP/DECISIONS-INDEX.md" && grep -q 'outra-saga' <<< "$(bash "$DAIDX" sagas "$TMP")" \
  && pass "saga composta (saga-teste, outra-saga) parseada" || fail "saga composta não parseada corretamente"
grep -q '^- DA-001 .*📚 em DA-005' "$TMP/DECISIONS-INDEX.md" && pass "DA-001 marcada 📚 consolidada em DA-005 (tag consolida:)" || fail "marca 📚 de consolida: não aplicada"
[ -z "$(ls "$TMP"/DECISIONS-VIGENTE-*.md 2>/dev/null)" ] && pass "nenhum DECISIONS-VIGENTE-*.md gerado (task 028)" || fail "DECISIONS-VIGENTE-*.md ainda é gerado (desligado na task 028)"

echo "== fixture 6: membro sem tag, pertencimento via membros.tsv =="
sagasout="$(bash "$DAIDX" sagas "$TMP")"
grep -q 'saga-tsv .*instância' <<< "$sagasout" && pass "saga-tsv (DA-006, via tsv) aparece com escopo instância" || fail "DA-006 não herdou saga/escopo do membros.tsv"

echo "== check: gerados sincronizados (idempotência) =="
bash "$DAIDX" check "$TMP" >"$TMP/check.out" 2>&1
# emenda DA-278: check agora sai !=0 quando um fixture "ruim" (paste/dup) vira FAIL de qualidade;
# a idempotência aqui é sobre SINCRONIA dos gerados — logo a asserção é a AUSÊNCIA de DIVERGE.
if grep -q 'DIVERGE' "$TMP/check.out"; then fail "check divergiu logo após update"; sed 's/^/    /' "$TMP/check.out"; else pass "gerados sincronizados (sem DIVERGE)"; fi

echo "== emenda DA-278: c1-c7 viram FAIL; c6 com grandfather (corte prospectivo) =="
grep -q 'FAIL c4: DA-003' <<< "$out" && pass "c4 (número duplicado) agora FAIL" || fail "c4 não virou FAIL"
CT="$(mktemp -d)"
cat > "$CT/DECISIONS.md" <<'FIX'
# fixture c6 grandfather

---

## DA-400 — acima do corte (deve FAIL)
`escopo: instância` · `saga: nova/t` · `data: 2026-09-13`
**Regra:** regra
**Lição:** sempre rodar scripts/foo antes de agir

## DA-200 — abaixo do corte (deve WARN)
`escopo: instância` · `saga: nova/t` · `data: 2026-09-13`
**Regra:** regra
**Lição:** sempre rodar scripts/foo antes de agir
FIX
DA_INDEX_C6_GRANDFATHER=300 bash "$DAIDX" update "$CT" >/dev/null 2>&1
c6out="$(DA_INDEX_C6_GRANDFATHER=300 bash "$DAIDX" check "$CT" 2>&1)"; c6rc=$?
grep -q 'FAIL c6: DA-400' <<< "$c6out" && pass "c6 DA-400 (>300) → FAIL" || fail "c6 DA-400 devia FAIL"
grep -q 'WARN c6: DA-200' <<< "$c6out" && pass "c6 DA-200 (<=300) → WARN (grandfather)" || fail "c6 DA-200 devia WARN"
[ "$c6rc" -ne 0 ] && pass "check com c6 FAIL → exit != 0 (pre-commit bloqueia)" || fail "check devia falhar com c6 FAIL"
rm -rf "$CT"

echo "== show --saga =="
bash "$DAIDX" show --saga saga-teste "$TMP" | tem '## NA-saga-teste' && pass "show --saga imprime a seção certa" || fail "show --saga não achou NA-saga-teste"

echo "== export-saga (sem números DA-N, sem espaço duplo, faixa vira [decisões internas]) =="
exp="$(bash "$DAIDX" export-saga saga-teste "$TMP")"
grep -qE 'DA-[0-9]' <<< "$exp" && fail "export-saga vazou número DA-N" || pass "export-saga não vaza número DA-N"
grep -qE '  ' <<< "$exp" && fail "export-saga deixou espaço duplo (buraco de substituição)" || pass "export-saga sem espaço duplo"
grep -qF '[decisões internas]' <<< "$exp" && pass "export-saga vira faixa DA-N–DA-M em [decisões internas]" || fail "export-saga não converteu a faixa DA-001–DA-002"
grep -qF '[decisão interna]' <<< "$exp" && pass "export-saga vira DA-N solta em [decisão interna]" || fail "export-saga não converteu a DA-003 solta"

echo "== fixture 7: parágrafo de metadado quebrado em 2 linhas não vaza continuação =="
grep -q '^- DA-007 .*— Isto é o parágrafo de conteúdo real, que deve virar a Regra no índice\.' "$TMP/DECISIONS-INDEX.md" \
  && pass "DA-007 pula o parágrafo **Data:**/Implementado-por/Escopo inteiro" || fail "DA-007 vazou fragmento do parágrafo de metadado"
sagasout="$(bash "$DAIDX" sagas "$TMP")"
grep -qE '^- regra-fallback-swallow .*Regra: (por:|-|\*\*|"|fragmento)' <<< "$sagasout" \
  && fail "saga regra-fallback-swallow ainda mostra fragmento" || pass "saga regra-fallback-swallow sem fragmento"

# A linha de saga não traz mais "membros: DA-…" desde o item 2a (da88a74, 05/09): asserção atualizada, código intacto.
echo "== fixture 8: rótulo curto ('**O problema.**') não vira Regra — cai em ver DA-NNN =="
grep -qF -- <<< "$sagasout" '- regra-fallback-curto · produto · cabeça: — · 1 DA · Regra: ver DA-008' \
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
grep -qF -- <<< "$sagasout" '- regra-fallback-longa · produto · cabeça: — · 1 DA · Regra: ver DA-012' \
  && pass "DA-012 (frase longa demais) cai em 'ver DA-012'" || fail "DA-012 não caiu no fallback por tamanho"

echo "== fixture 13/14: fallback de data do Histórico (tag → **Data:** → data isolada no corpo → —) =="
sagasmd="$(bash "$DAIDX" show --saga regra-fallback-datas "$TMP")"   # NA só em memória (task 028)
grep -qF -- <<< "$sagasmd" '- 2026-03-15 · DA-013 ·' && pass "DA-013: data BR isolada '**15/03/2026**' virou 2026-03-15 no Histórico" || fail "DA-013 não converteu a data isolada do corpo"
grep -qF -- <<< "$sagasmd" '- — · DA-014 ·' && pass "DA-014 (sem nenhuma data no corpo) mantém — no Histórico" || fail "DA-014 não deveria ter data nenhuma"

echo "== da-new.sh: número novo, snapshot, diário original intocado (fora deste dir) =="
before_sha="$(sha256sum "$TMP/DECISIONS.md" | cut -d' ' -f1)"
newout="$(ADAS_HOME_DIR="$TMP/.adas" bash "$DANEW" --tipo regra instância "nova/teste-harness" "DA de teste do harness" "$TMP")"
grep -q '^DA-015$' <<< "$newout" && pass "da-new.sh calculou DA-015 (max+1)" || fail "da-new.sh não calculou o número certo: $newout"
[ -d "$TMP/.adas/snapshots" ] && [ -n "$(ls -A "$TMP/.adas/snapshots" 2>/dev/null)" ] && pass "snapshot criado antes de anexar" || fail "snapshot ausente"
after_sha_realhome="$(sha256sum "$HOME/DECISIONS.md" 2>/dev/null | cut -d' ' -f1)"
echo "  (nota: da-new.sh rodou só contra $TMP; diário real não foi tocado por construção do teste)"

echo "== da-new.sh: saga inexistente sem prefixo nova/ é RECUSADA (exit 2), sem anexar =="
SAGACONF_TMP="$TMP/.adas-slugtest"; mkdir -p "$SAGACONF_TMP"
printf 'saga-existente|produto|\n' > "$SAGACONF_TMP/sagas.conf"
before2="$(sha256sum "$TMP/DECISIONS.md" | cut -d' ' -f1)"
rc=0
out2="$(ADAS_HOME_DIR="$TMP/.adas" ADAS_SAGAS_CONF="$SAGACONF_TMP/sagas.conf" bash "$DANEW" --tipo regra instância "saga-que-nao-existe" "titulo x" "$TMP" 2>&1)" || rc=$?
after2="$(sha256sum "$TMP/DECISIONS.md" | cut -d' ' -f1)"
[ "$rc" = 2 ] && pass "da-new.sh recusa slug inexistente com exit 2" || fail "da-new.sh não recusou slug inexistente (rc=$rc)"
[ "$before2" = "$after2" ] && pass "DECISIONS.md intocado após recusa" || fail "DECISIONS.md foi alterado mesmo com slug recusado"
grep -q 'saga-existente' <<< "$out2" && pass "mensagem de recusa lista os slugs válidos" || fail "mensagem de recusa não lista slugs válidos"
rc3=0
out3="$(ADAS_HOME_DIR="$TMP/.adas" ADAS_SAGAS_CONF="$SAGACONF_TMP/sagas.conf" bash "$DANEW" --tipo regra instância "nova/saga-x" "titulo x" "$TMP" 2>&1)" || rc3=$?
[ "$rc3" = 0 ] && grep -q '^DA-016$' <<< "$out3" && pass "'nova/saga-x' anexa normalmente (DA-016)" || fail "'nova/saga-x' deveria ter anexado: rc=$rc3 out=$out3"

echo "== da-new.sh: snapshot isolado do [dir] (não vaza pro ~/.adas real) + rotação a 30 =="
DIRTEST="$TMP/copia-isolada"; mkdir -p "$DIRTEST/.adas/snapshots"
cp "$TMP/DECISIONS.md" "$DIRTEST/DECISIONS.md"
for i in $(seq -w 1 32); do : > "$DIRTEST/.adas/snapshots/DECISIONS.md.202601${i}T000000Z"; done
realhome_before="$(ls -1 "$HOME/.adas/snapshots" 2>/dev/null | wc -l)"
bash "$DANEW" --tipo regra instância "nova/rotacao-teste" "titulo rotacao" "$DIRTEST" >/dev/null
realhome_after="$(ls -1 "$HOME/.adas/snapshots" 2>/dev/null | wc -l)"
[ "$realhome_before" = "$realhome_after" ] && pass "snapshot NÃO vazou pro ~/.adas/snapshots real (sem ADAS_HOME_DIR, dir≠\$HOME)" || fail "snapshot vazou pro servidor real!"
count_dirtest="$(ls -1 "$DIRTEST/.adas/snapshots" | wc -l)"
[ "$count_dirtest" = 30 ] && pass "rotação mantém exatamente os 30 snapshots mais recentes" || fail "rotação não manteve 30 (tem $count_dirtest)"

echo "== DA-196: [dir] ausente resolve por \$HOME, nunca pelo cwd =="
mkdir -p "$TMP/elsewhere"
show_home="$(cd "$TMP" && HOME="$TMP" bash "$DAIDX" show DA-001)"
show_elsewhere="$(cd "$TMP/elsewhere" && HOME="$TMP" bash "$DAIDX" show DA-001)"
[ "$show_home" = "$show_elsewhere" ] && [ -n "$show_home" ] && pass "show DA-001 sem [dir]: mesmo resultado de \$HOME e de outro cwd" || fail "show DA-001 sem [dir] diverge por cwd"

list_home="$(cd "$TMP" && HOME="$TMP" bash "$DAIDX" list)"
list_elsewhere="$(cd "$TMP/elsewhere" && HOME="$TMP" bash "$DAIDX" list)"
[ "$list_home" = "$list_elsewhere" ] && [ -n "$list_home" ] && pass "list sem [dir]: mesmo resultado de \$HOME e de outro cwd" || fail "list sem [dir] diverge por cwd"

# normaliza primeiro (da-new.sh dos testes anteriores anexou DA-015/016 sem passar pelo
# hook PostToolUse que regeneraria os gerados — não é o que este teste mede)
bash "$DAIDX" update "$TMP" >/dev/null 2>&1
before_upd_sha="$(sha256sum "$TMP/DECISIONS-INDEX.md" "$TMP/DECISIONS-LICOES.md")"
( cd "$TMP/elsewhere" && HOME="$TMP" bash "$DAIDX" update >/dev/null 2>&1 )
after_upd_sha="$(sha256sum "$TMP/DECISIONS-INDEX.md" "$TMP/DECISIONS-LICOES.md")"
[ "$before_upd_sha" = "$after_upd_sha" ] && pass "update sem [dir] rodado de outro cwd: gerados byte-idênticos aos de \$HOME" || fail "update sem [dir] rodado de outro cwd mudou os gerados"
[ -z "$(ls -A "$TMP/elsewhere" 2>/dev/null)" ] && pass "update sem [dir] escreveu em \$HOME, não vazou pro cwd (elsewhere continua vazio)" || fail "update sem [dir] escreveu no cwd errado"

echo "== DA-196: diário ausente/ilegível nunca vira 'não encontrada' (arquivo ausente ≠ decisão ausente) =="
EMPTYDIR="$TMP/sem-diario"; mkdir -p "$EMPTYDIR"
out_missing="$(bash "$DAIDX" show DA-001 "$EMPTYDIR" 2>&1)"; rc_missing=$?
[ "$rc_missing" -ne 0 ] && pass "show com diário ausente: exit != 0" || fail "show com diário ausente: exit 0 (deveria falhar)"
grep -qF "$EMPTYDIR/DECISIONS.md" <<< "$out_missing" && pass "erro de ausente cita o caminho tentado" || fail "erro de ausente não cita o caminho tentado"
grep -qi "não encontrada" <<< "$out_missing" && fail "erro de arquivo ausente usa 'não encontrada' (mascara ausência de dado como ausência de decisão)" || pass "erro de arquivo ausente NÃO usa 'não encontrada'"

UNREADABLE="$TMP/sem-permissao"; mkdir -p "$UNREADABLE"
cp "$TMP/DECISIONS.md" "$UNREADABLE/DECISIONS.md"
chmod 000 "$UNREADABLE/DECISIONS.md"
out_unreadable="$(bash "$DAIDX" list "$UNREADABLE" 2>&1)"; rc_unreadable=$?
chmod 644 "$UNREADABLE/DECISIONS.md"
[ "$rc_unreadable" -ne 0 ] && pass "list com diário ilegível (chmod 000): exit != 0" || fail "list com diário ilegível: exit 0 (deveria falhar)"
grep -qF "$UNREADABLE/DECISIONS.md" <<< "$out_unreadable" && pass "erro de ilegível cita o caminho tentado" || fail "erro de ilegível não cita o caminho tentado"
grep -qi "não encontrada" <<< "$out_unreadable" && fail "erro de diário ilegível usa 'não encontrada'" || pass "erro de diário ilegível NÃO usa 'não encontrada'"

echo "== D-C1/D-C4 (mudança de casa, DA-670): ponteiro 📦, show com a casa, c11 e Histórico sem ruído =="
CASA="$TMP/casa"; mkdir -p "$CASA"
cat > "$CASA/DECISIONS.md" <<'MD'
# diário de teste

## DA-001 — Regra antiga do app (será ponteiro)
`escopo: projeto/app` · `saga: nova/x` · `data: 2026-11-01` · `refs: —` · `consolida: —` · `supersede: —`
**Regra:** Margem de 3% nos dois sentidos.
**Motivo:** teste.

## DA-002 — Outra regra, esta supersede em prosa de verdade? não
`escopo: produto` · `saga: nova/y` · `data: 2026-11-02` · `refs: —` · `consolida: —` · `supersede: —`
**Regra:** Regra independente que deve continuar vigente.
**Motivo:** teste.

## DA-003 — 📦 Mudança de casa: o app vive em /tmp/app
`escopo: projeto/app` · `saga: nova/casa-app` · `data: 2026-11-03` · `tipo: registro` · `refs: —` · `consolida: DA-001` · `supersede: —` · `passa-a-limpo: DAS-777`
**Regra:** Decisão do app nasce no repositório dele.
**Detalhe operacional:** 📦 casa: /tmp/app/DECISIONS.md · ler: `bash ~/scripts/da-index.sh show DA-NNN /tmp/app`
### Histórico
- DA-001 — Margem de 3%, supersede parcial da DA-002 (título copiado) → 📦 app DA-009
MD
bash "$DAIDX" update "$CASA" >/dev/null 2>&1
sh1="$(bash "$DAIDX" show DA-001 "$CASA" 2>&1 | head -1)"; vg="$(bash "$DAIDX" list --vigentes "$CASA" 2>&1)"; ck="$(bash "$DAIDX" check "$CASA" 2>&1)"
[ "$sh1" = "📦 mudou de casa: app DA-009 (bash ~/scripts/da-index.sh show DA-009 /tmp/app) — ponteiro DA-003" ] \
  && pass "D-C1: show de DA 📚 em ponteiro imprime a casa" || fail "D-C1: show da DA 📚 não imprime a linha 📦 ($sh1)"
grep -q '^- DA-002' <<< "$vg" \
  && pass "D-C4: título copiado no Histórico ('supersede') não marca a DA-002" || fail "D-C4: Histórico marcou a DA-002 como superada"
grep -E 'c11' <<< "$ck" | grep -qE 'DA-(777|009)' \
  && fail "D-C4: c11 acusa id de passa-a-limpo/📦" || pass "D-C4: c11 ignora passa-a-limpo e '📦 <repo> DA-NNN'"

echo "== Fase 2: parcial: (alias do ½) e ficha contra o da-schema.tsv =="
F2="$TMP/fase2"; mkdir -p "$F2"
R300="$(printf 'abcdefghij%.0s' $(seq 1 30))"   # 300 caracteres
{
cat <<'MD'
# DECISIONS

## DA-900 — alvo parcial
`escopo: produto` · `saga: nova/t` · `data: 2026-11-01` · `refs: —` · `consolida: —` · `supersede: —`
**Regra:** Regra da DA-900 que segue vigente depois do parcial.

## DA-901 — antiga absorvida
`escopo: produto` · `saga: nova/t` · `data: 2026-11-01` · `refs: —` · `consolida: —` · `supersede: —`
**Regra:** Regra antiga que a cabeça DA-902 absorveu inteira.

## DA-902 — cabeça
`escopo: produto` · `saga: nova/t` · `data: 2026-11-01` · `refs: —` · `consolida: DA-901` · `supersede: —`
**Regra:** Cabeça que consolida a DA-901 e segue vigente.

### Histórico
- DA-901 — antiga — Regra

MD
printf '## DA-903 — antiga com Regra de 300\n`escopo: produto` · `saga: nova/t` · `data: 2026-11-01` · `refs: —` · `consolida: —` · `supersede: —`\n**Regra:** %s\n\n' "$R300"
printf '## DA-904 — nova com Regra de 300\n`escopo: produto` · `saga: nova/t` · `data: 2026-11-20` · `tipo: regra` · `gravidade: norma` · `refs: —` · `consolida: —` · `supersede: —` · `parcial: DA-900 (só o teto)`\n**Regra:** %s\n**Gatilho:** tema\n**Exemplo:** ✗ a → ✓ b\n**Motivo:** m\n**Trade-off:** t\n**Lição:** l\n\n' "$R300"
cat <<'MD'
## DA-905 — nova que aponta a absorvida
`escopo: produto` · `saga: nova/t` · `data: 2026-11-20` · `tipo: regra` · `gravidade: norma` · `refs: —` · `consolida: —` · `supersede: —` · `parcial: DA-901`
**Regra:** Regra curta e completa da DA-905.
**Gatilho:** tema
**Exemplo:** ✗ a → ✓ b
**Motivo:** m
**Trade-off:** t
**Lição:** l
**Detalhe operacional:** 
MD
} > "$F2/DECISIONS.md"
bash "$DAIDX" update "$F2" >/dev/null 2>&1
vg2="$(bash "$DAIDX" list --vigentes "$F2" 2>&1)"; ck2="$(DA_FICHA_DESDE=2026-11-13 bash "$DAIDX" check "$F2" 2>&1)"
tem -E '^- DA-900 .*½ por DA-904' <<< "$vg2" && pass "parcial: DA-900 marca ½ e ela segue em list --vigentes" || fail "parcial: não marcou ½ / tirou dos vigentes: $(grep DA-900 <<< "$vg2")"
tem 'WARN ficha: DA-904 Regra com 300 caracteres' <<< "$ck2" && pass "ficha: DA nova (acima do corte) com Regra de 300 → WARN" || fail "ficha: Regra de 300 acima do corte sem WARN"
tem 'DA-903' <<< "$(grep 'ficha' <<< "$ck2")" && fail "ficha: DA abaixo do corte foi julgada" || pass "ficha: DA abaixo do corte (Regra de 300) → silêncio"
tem 'WARN ficha: DA-905 parcial aponta DA-901, que não é vigente (📚 em DA-902) — aponte para a cabeça DA-902' <<< "$ck2" \
  && pass "ficha: parcial com alvo 📚 → WARN apontando a cabeça" || fail "ficha: alvo 📚 sem WARN: $(grep 905 <<< "$ck2")"
tem 'WARN ficha: DA-905 Detalhe operacional vazio — preencha ou apague a linha' <<< "$ck2" && pass "ficha: linha deixada vazia → WARN" || fail "ficha: linha vazia sem WARN"
tem -E 'WARN ficha: DA-905 (sem|.*caracteres)' <<< "$ck2" && fail "ficha: DA-905 completa ganhou aviso indevido" || pass "ficha: DA completa sem aviso de campo"

echo
if [ "$FAIL" = 0 ]; then
  echo "✓✓✓ harness da-index: TODOS OS TESTES PASSARAM"
  exit 0
else
  echo "✗✗✗ harness da-index: HÁ FALHAS ACIMA"
  exit 1
fi
