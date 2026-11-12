#!/usr/bin/env bash
# sync.test.sh — aceite da Fase 3a (distribuição): `adas sync` carimba, o check-adas.sh da casa reprova cópia editada
# à mão, `--all` leva uma mudança do produto a todas as casas, a geração fica no lock. Tudo em /tmp, contra uma CÓPIA
# do produto (o teste muda um script do skeleton) — nunca toca uma casa real nem o repos.conf da máquina.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ok=0; ko=0; pass(){ echo "  ✓ $1"; ok=$((ok+1)); }; fail(){ echo "  ✗ $1"; ko=$((ko+1)); }
export HOME="$T/home" ADAS_REPOS_CONF="$T/repos.conf"; mkdir -p "$HOME"; unset AXON_HEADLESS
P="$T/produto"; mkdir -p "$P/host"   # só o necessário: host/jit pesa ~1 GB (vetores, caches)
cp -r "$ROOT/skeleton" "$ROOT/skeleton-v4" "$ROOT/VERSION" "$ROOT/CHANGELOG.md" "$P/"; cp "$ROOT"/host/*.sh "$ROOT/host/adas" "$P/host/"
SYNC="$P/host/adas-sync.sh"
casa() {  # casa <dir> — repo git com o esqueleto de docs (sem scripts: quem traz é o sync)
  mkdir -p "$1"; cp "$ROOT"/skeleton/*.md "$1/"; git -C "$1" init -q
}
identicas() {  # identicas <casa> <geração> — toda cópia = produto e = lock
  local f a s
  for f in "$P/$2/scripts"/*; do [ -f "$f" ] || continue; a="$(basename "$f")"
    cmp -s "$f" "$1/scripts/$a" || return 1
    s="$(awk -F'\t' -v a="$a" '!/^#/ && $2==a{print $1}' "$1/.adas/skeleton.lock")"
    [ "$s" = "$(sha256sum "$f" | cut -d' ' -f1)" ] || return 1
  done
}

echo "== 1) sync numa casa nova: lock + cópias idênticas + ficha-desde"
A="$T/casaA"; casa "$A"
bash "$SYNC" "$A" >/dev/null && [ -f "$A/.adas/skeleton.lock" ] && pass "lock gravado" || fail "sync não gravou lock"
identicas "$A" skeleton && pass "cópias idênticas ao produto e ao lock" || fail "cópia ≠ produto/lock"
grep -q '^# geracao: skeleton$' "$A/.adas/skeleton.lock" && grep -q "^# versao: $(cat "$P/VERSION")$" "$A/.adas/skeleton.lock" \
  && pass "lock traz geração e versão" || fail "lock sem geração/versão"
d="$(cat "$A/.adas/ficha-desde" 2>/dev/null)"
[[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ ! "$d" < 2026-11-13 ]] && pass "R5: ficha-desde gravado ($d)" || fail "R5: ficha-desde ausente/ruim: '$d'"
echo 2026-12-31 > "$A/.adas/ficha-desde"; bash "$SYNC" "$A" >/dev/null
[ "$(cat "$A/.adas/ficha-desde")" = 2026-12-31 ] && pass "R5: 2º sync não mexe no ficha-desde" || fail "R5: 2º sync reescreveu o ficha-desde"
out="$(bash "$A/scripts/check-adas.sh" "$A" 2>&1)"; rc=$?
[ "$rc" = 0 ] && pass "check-adas da casa limpa sai 0" || fail "check-adas da casa limpa saiu $rc: $(tail -2 <<< "$out")"
bash "$SYNC" --check "$A" >/dev/null && pass "--check: casa limpa rc 0" || fail "--check reprovou casa limpa"

echo "== 2) cópia editada à mão = FAIL"
echo "# remendo local" >> "$A/scripts/da-index.sh"
out="$(bash "$A/scripts/check-adas.sh" "$A" 2>&1)"; rc=$?
[ "$rc" != 0 ] && grep -q 'scripts/da-index.sh difere do carimbo' <<< "$out" && pass "check-adas sai $rc e aponta o arquivo" || fail "check-adas não reprovou a cópia editada (rc=$rc)"
bash "$SYNC" --check "$A" >/dev/null; [ $? = 1 ] && pass "--check: rc 1 com cópia editada" || fail "--check não acusou cópia editada"
antes="$(sha256sum "$A/scripts/da-index.sh")"
out="$(bash "$SYNC" "$A" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(sha256sum "$A/scripts/da-index.sh")" = "$antes" ] && grep -q 'da-index.sh' <<< "$out" \
  && pass "sync recusa sobrescrever cópia editada sem --force (nada mudou)" || fail "sync sobrescreveu cópia editada sem --force (rc=$rc)"
bash "$SYNC" --force "$A" >/dev/null && identicas "$A" skeleton && pass "--force restaura a cópia" || fail "--force não restaurou"

echo "== 3) casa com cópia divergente e SEM lock: recusa; script próprio da casa fica intocado"
B="$T/casaB"; casa "$B"; mkdir -p "$B/scripts"
cp "$P/skeleton/scripts/check-secrets.sh" "$B/scripts/"; echo "# melhoria só no servidor" >> "$B/scripts/check-secrets.sh"
echo 'echo meu' > "$B/scripts/check-meu.sh"
bash "$SYNC" "$B" >/dev/null 2>&1; [ $? = 1 ] && [ ! -f "$B/.adas/skeleton.lock" ] && pass "1º sync com cópia divergente recusa e não grava lock" || fail "1º sync passou por cima de cópia divergente"
bash "$SYNC" --force "$B" >/dev/null && [ "$(cat "$B/scripts/check-meu.sh")" = "echo meu" ] && ! grep -q 'check-meu' "$B/.adas/skeleton.lock" \
  && pass "script próprio da casa não entra no lock nem muda" || fail "sync mexeu no script próprio da casa"

echo "== 4) mudança no skeleton + sync --all leva a todas as casas"
C="$T/casaC"; casa "$C"; bash "$SYNC" "$C" >/dev/null
printf '%s\n%s\n%s\n' "# conf de teste" "$A" "$B/" > "$ADAS_REPOS_CONF"; echo "$C" >> "$ADAS_REPOS_CONF"
echo "# mudança do produto $$" >> "$P/skeleton/scripts/adas-report.sh"
out="$(bash "$SYNC" --check --all)"; grep -q 'atrás do produto' <<< "$out" && pass "--check aponta casa atrás do produto" || fail "--check não viu casa atrás"
bash "$SYNC" --all >/dev/null; rc=$?
[ "$rc" = 0 ] && identicas "$A" skeleton && identicas "$B" skeleton && identicas "$C" skeleton \
  && grep -q "mudança do produto $$" "$C/scripts/adas-report.sh" && pass "sync --all levou a mudança às 3 casas (sem --force: cópias intactas)" || fail "sync --all não propagou (rc=$rc)"
for c in "$A" "$B" "$C"; do bash "$c/scripts/check-adas.sh" "$c" >/dev/null 2>&1 || fail "check-adas de $c reprovou depois do sync"; done

echo "== 5) geração fica no lock"
V="$T/casaV"; mkdir -p "$V"; git -C "$V" init -q
bash "$SYNC" --geracao skeleton-v4 "$V" >/dev/null && identicas "$V" skeleton-v4 && grep -q '^# geracao: skeleton-v4$' "$V/.adas/skeleton.lock" \
  && pass "--geracao skeleton-v4 carimba v4" || fail "sync v4 falhou"
bash "$SYNC" "$V" >/dev/null && grep -q '^# geracao: skeleton-v4$' "$V/.adas/skeleton.lock" && pass "sync sem --geracao mantém a do lock" || fail "sync trocou a geração sozinho"
bash "$SYNC" --geracao skeleton "$V" >/dev/null 2>&1; [ $? = 1 ] && grep -q '^# geracao: skeleton-v4$' "$V/.adas/skeleton.lock" \
  && pass "trocar de geração sem --force recusa" || fail "geração trocada sem --force"
echo "# remendo" >> "$V/scripts/check-secrets.sh"
bash "$V/scripts/check-adas.sh" "$V" >/dev/null 2>&1; [ $? != 0 ] && pass "check-adas v4 reprova cópia editada" || fail "check-adas v4 não reprovou cópia editada"

echo "== 6) update.sh: casa sem da-schema.tsv avisa; casa com lock é conferida (update de verdade, remoto local)"
D="$T/casaD"; mkdir -p "$D/scripts"; cp "$P/skeleton/scripts/da-new.sh" "$D/scripts/"
G=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
"${G[@]}" -C "$P" init -q && "${G[@]}" -C "$P" add -A && "${G[@]}" -C "$P" commit -qm base
"${G[@]}" clone -q --bare "$P" "$T/bare.git" && git -C "$P" remote add origin "$T/bare.git"
"${G[@]}" clone -q "$T/bare.git" "$T/w2" && echo x >> "$T/w2/CHANGELOG.md" && "${G[@]}" -C "$T/w2" add -A \
  && "${G[@]}" -C "$T/w2" commit -qm novo && git -C "$T/w2" push -q origin HEAD 2>/dev/null
mkdir -p "$HOME/.claude/adas"; printf '%s\n%s\n' "$D" "$A" > "$HOME/.claude/adas/repos.conf"
out="$(bash "$P/host/update.sh" --yes 2>&1)"
grep -q "$D: falta scripts/da-schema.tsv" <<< "$out" && pass "update.sh avisa casa sem da-schema.tsv" || fail "update.sh calado sem da-schema.tsv: $(tail -3 <<< "$out")"
grep -q "✓ $A: lock" <<< "$out" && pass "update.sh confere a casa com lock (adas sync --check)" || fail "update.sh não conferiu o lock: $(tail -3 <<< "$out")"

echo "== 7) revisão 020: falha no meio não deixa estado parcial; produto não é casa; casa que sumiu reprova; âncora do corte"
E="$T/casaE"; casa "$E"; bash "$SYNC" "$E" >/dev/null
echo "# v2 $$" >> "$P/skeleton/scripts/adas-report.sh"; chmod 000 "$P/skeleton/scripts/da-index.sh"
bash "$SYNC" "$E" >/dev/null 2>&1; rc=$?; chmod 755 "$P/skeleton/scripts/da-index.sh"
[ "$rc" = 1 ] && ! grep -q "v2 $$" "$E/scripts/adas-report.sh" && [ -z "$(find "$E/.adas" "$E/scripts" -name '*tmp*' -o -name 'sync-estagio*')" ] \
  && bash "$E/scripts/check-adas.sh" "$E" >/dev/null 2>&1 && pass "falha no meio da cópia: nada mudou, sem resto, check-adas segue 0" || fail "falha no meio deixou estado parcial (rc=$rc)"
bash "$SYNC" "$E" >/dev/null && identicas "$E" skeleton && pass "sync seguinte conclui" || fail "sync depois da falha não concluiu"
bash "$SYNC" "$P" >/dev/null 2>&1; [ $? = 1 ] && [ ! -e "$P/scripts" ] && [ ! -e "$P/.adas/skeleton.lock" ] && pass "sync recusa o próprio produto" || fail "sync criou scripts/ no produto"
bash "$SYNC" --check "$T/nao-existe" >/dev/null 2>&1; [ $? = 1 ] && pass "--check: casa que não existe reprova" || fail "--check passou casa inexistente"
F="$T/casaF"; casa "$F"; printf '# D\n\n## DA-001 — antiga sem data\n\n**Regra:** x.\n\n## DA-002 — antiga sem data\n\n**Regra:** y.\n' > "$F/DECISIONS.md"
bash "$SYNC" "$F" >/dev/null; grep -q '^ultima: DA-002$' "$F/.adas/ficha-desde" && pass "1º sync grava a âncora (ultima: DA-002)" || fail "ficha-desde sem âncora: $(cat "$F/.adas/ficha-desde" | tr '\n' ' ')"
bash "$F/scripts/da-index.sh" update "$F" >/dev/null 2>&1; o="$(bash "$F/scripts/da-index.sh" check "$F" 2>&1)"
grep -q 'WARN ficha' <<< "$o" && fail "diário sem data: DA anterior ao sync ganhou aviso: $(grep -m1 'WARN ficha' <<< "$o")" || pass "diário sem data: DA anterior ao sync não ganha aviso"
printf '\n## DA-003 — nova sem data\n\n**Regra:** z.\n' >> "$F/DECISIONS.md"; bash "$F/scripts/da-index.sh" update "$F" >/dev/null 2>&1; o="$(bash "$F/scripts/da-index.sh" check "$F" 2>&1)"
grep -q 'WARN ficha: DA-003' <<< "$o" && ! grep -q 'WARN ficha: DA-00[12]' <<< "$o" && pass "DA nova sem data, depois da âncora, não escapa" || fail "âncora: DA-003 nova não avisou (ou antiga avisou)"

echo "== 8) B4: mecanismo da casa em scripts/check-local.sh — fora do lock, o --force não apaga, o check-adas executa"
ls "$ROOT"/skeleton*/scripts/check-local.sh >/dev/null 2>&1 && fail "o produto traz scripts/check-local.sh (é da casa)" || pass "produto não traz check-local.sh"
for g in skeleton skeleton-v4; do
  K="$T/casaK-$g"; casa "$K"; bash "$SYNC" --geracao "$g" "$K" >/dev/null
  printf 'echo "✗ trava da casa: cor fora do token"; exit 1\n' > "$K/scripts/check-local.sh"
  out="$(bash "$K/scripts/check-adas.sh" "$K" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && grep -q 'trava da casa: cor fora do token' <<< "$out" && grep -q 'check-local.sh' <<< "$out" \
    && pass "$g: check-local.sh rc 1 → check-adas rc 1 com a saída da trava" || fail "$g: check-adas ignorou a trava da casa (rc=$rc)"
  echo "# remendo" >> "$K/scripts/adas-report.sh"; bash "$SYNC" --force "$K" >/dev/null
  grep -q 'trava da casa' "$K/scripts/check-local.sh" && ! grep -q 'check-local' "$K/.adas/skeleton.lock" \
    && pass "$g: sync --force não toca check-local.sh nem o carimba" || fail "$g: --force mexeu no check-local.sh"
  printf 'echo "✓ trava da casa ok"\n' > "$K/scripts/check-local.sh"
  out="$(bash "$K/scripts/check-adas.sh" "$K" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && grep -q 'check-local: ✓ trava da casa ok' <<< "$out" && pass "$g: trava verde → check-adas rc 0 e diz que rodou" || fail "$g: trava verde e check-adas rc=$rc"
done
M="$T/casaM"; mkdir -p "$M/scripts" "$M/tests"; git -C "$M" init -q
printf '# M\n<!-- adas-core-start -->\n1. **hosts da lista** — mecanismo: scripts/check-casa.sh · teste: tests/casa.test.sh\n<!-- adas-core-end -->\n' > "$M/ADAS.md"
echo 'exit 0' > "$M/scripts/check-casa.sh"; echo 'exit 0' > "$M/tests/casa.test.sh"; cp "$P/skeleton-v4/scripts/check-mecanismo.sh" "$M/scripts/"
bash "$M/scripts/check-mecanismo.sh" "$M" >/dev/null 2>&1; [ $? = 1 ] && pass "v4: mecanismo que nada executa reprova (controle)" || fail "v4: check-mecanismo passou mecanismo solto"
echo 'bash scripts/check-casa.sh' > "$M/scripts/check-local.sh"
bash "$M/scripts/check-mecanismo.sh" "$M" >/dev/null 2>&1 && pass "v4: mecanismo chamado pelo check-local.sh conta como registrado" || fail "v4: check-mecanismo não aceita check-local.sh como registro"

echo "== 9) B5: 1º sync (sem lock) separa cópia ATRASADA (blob do histórico do produto) de cópia EDITADA"
"${G[@]}" -C "$P" add -A && "${G[@]}" -C "$P" commit -qm 'v-velha'
velha="$(cat "$P/skeleton/scripts/adas-report.sh")"
echo "# release nova $$" >> "$P/skeleton/scripts/adas-report.sh"; "${G[@]}" -C "$P" commit -qam 'v-nova'
R="$T/casaR"; casa "$R"; mkdir -p "$R/scripts"; printf '%s\n' "$velha" > "$R/scripts/adas-report.sh"
out="$(bash "$SYNC" "$R" 2>&1)"; rc=$?
[ "$rc" = 0 ] && identicas "$R" skeleton && pass "cópia atrasada (versão antiga do produto) sincroniza sem --force" || fail "cópia atrasada recusada (rc=$rc): $(tail -2 <<< "$out")"
S="$T/casaS"; casa "$S"; mkdir -p "$S/scripts"; printf '%s\n# edição da casa\n' "$velha" > "$S/scripts/adas-report.sh"
bash "$SYNC" "$S" >/dev/null 2>&1; [ $? = 1 ] && [ ! -f "$S/.adas/skeleton.lock" ] && grep -q 'edição da casa' "$S/scripts/adas-report.sh" \
  && pass "cópia editada (fora do histórico) segue recusada" || fail "cópia editada passou sem --force"
echo "# rascunho no stash $$" >> "$P/skeleton/scripts/adas-report.sh"; cp "$P/skeleton/scripts/adas-report.sh" "$T/stash.sh"; git -C "$P" stash -q
U="$T/casaU"; casa "$U"; mkdir -p "$U/scripts"; cp "$T/stash.sh" "$U/scripts/adas-report.sh"
bash "$SYNC" "$U" >/dev/null 2>&1; [ $? = 1 ] && pass "blob só do stash (não alcançável do HEAD) não conta como histórico" || fail "blob do stash virou 'versão antiga'"

echo "sync: $ok ok, $ko falha(s)"; [ "$ko" = 0 ]
