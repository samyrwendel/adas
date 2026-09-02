#!/usr/bin/env bash
# smoke — SPEC EXECUTÁVEL do repo adas (CI + local: `bash tests/smoke.sh`).
# Testa COMPORTAMENTO, não só sintaxe: cada modo de falha pego nas auditorias de 16/07
# (check morto por self-match, no-op verde do check-secrets, sobrescrita do SETUP,
# hooks do host) vira um assert permanente de regressão.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ echo "  ✓ $1"; pass=$((pass+1)); }
bad(){ echo "  ✗ $1"; fail=$((fail+1)); }
expect_exit(){ # expect_exit <esperado> <descrição> <cmd...>
  local want="$1" desc="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  [ "$got" = "$want" ] && ok "$desc" || bad "$desc (exit $got, esperado $want)"
}

echo "== 0) sintaxe de todos os .sh"
synbad=0
while IFS= read -r f; do bash -n "$f" 2>/dev/null || { bad "sintaxe: $f"; synbad=1; }; done \
  < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*')
[ "$synbad" = 0 ] && ok "bash -n em todos os .sh"

echo "== 1) check-secrets — o gate não pode aprovar sem examinar"
mkdir -p "$T/s1"; (cd "$T/s1" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir scripts && cp "$ROOT/skeleton/scripts/check-secrets.sh" scripts/ \
  && echo "tk='ghp_000000000000000000000000000000000000'" > c.js && git add -A && git commit -qm x)
expect_exit 1 "staged vazio + segredo commitado → BLOCK (fallback --all)" \
  bash -c "cd '$T/s1' && bash scripts/check-secrets.sh"
(cd "$T/s1" && echo "k2='ghp_111111111111111111111111111111111111'" > n.js && git add n.js)
expect_exit 1 "segredo STAGED → BLOCK" bash -c "cd '$T/s1' && bash scripts/check-secrets.sh"
mkdir -p "$T/s2"; (cd "$T/s2" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir scripts && cp "$ROOT/skeleton/scripts/check-secrets.sh" scripts/ \
  && echo ok > a.txt && git add -A && git commit -qm x)
expect_exit 0 "repo limpo, staged vazio → verde (sem falso positivo)" \
  bash -c "cd '$T/s2' && bash scripts/check-secrets.sh"

echo "== 2) check-_template — o exemplo não pode ser um check morto"
mkdir -p "$T/t/src"; cp "$ROOT/skeleton/scripts/check-_template.sh" "$T/t/check.sh"
echo "kb = [{ callback_data: 'orfao' }]" > "$T/t/src/bot.js"
expect_exit 1 "botão órfão → ACUSA (self-match corrigido)" bash -c "cd '$T/t' && SRC=src bash check.sh"
echo "bot.action('orfao', h)" >> "$T/t/src/bot.js"
expect_exit 0 "botão com handler → passa" bash -c "cd '$T/t' && SRC=src bash check.sh"

echo "== 3) SETUP — cadeia REAL do doc, com colisão (cp -Rn nunca sobrescreve + versão sempre gravada)"
mkdir -p "$T/p1/scripts" && cd "$T/p1" \
  && echo "MEU LOG" > DECISIONS.md && echo "MEU ADAS" > ADAS.md && echo "meu readme" > README.md \
  && echo "MEU CHECK" > scripts/check-secrets.sh   # colisão FORA da checklist do passo 1
d="$T/clone" && git clone -q "$ROOT" "$d"
rm -rf "$d/skeleton" && cp -R "$ROOT/skeleton" "$d/skeleton"   # testa o WORKING TREE, não o último commit
rm "$d/skeleton/README.md" && { cp -Rn "$d/skeleton/." . || true; } \
  && mkdir -p .adas && git -C "$d" rev-parse HEAD | cut -c1-7 > .adas/skeleton-version
[ "$(cat DECISIONS.md)" = "MEU LOG" ] && ok "DECISIONS.md preenchido intacto" || bad "cp SOBRESCREVEU DECISIONS.md"
[ "$(cat README.md)" = "meu readme" ] && ok "README do projeto intacto" || bad "README sobrescrito"
[ "$(cat scripts/check-secrets.sh)" = "MEU CHECK" ] && ok "colisão fora da checklist preservada" || bad "colisão sobrescrita"
[ -s .adas/skeleton-version ] && ok "skeleton-version gravado MESMO com cp pulando arquivos" || bad "versão não gravada (cadeia engoliu)"
[ -f scripts/check-adas.sh ] && ok "arquivos novos vieram" || bad "cópia incompleta"

echo "== 4) check-adas no esqueleto recém-copiado (working tree) — warn, nunca block"
mkdir -p "$T/p2" && cd "$T/p2" && cp -Rn "$d/skeleton/." . 2>/dev/null
mkdir -p .adas && git -C "$d" rev-parse HEAD | cut -c1-7 > .adas/skeleton-version
out=$(bash scripts/check-adas.sh); rc=$?
[ "$rc" = 0 ] && ok "exit 0 (placeholder é warn, não block)" || bad "bloqueou o esqueleto (exit $rc)"
echo "$out" | grep -q PLACEHOLDER && ok "acusa PLACEHOLDER pendente" || bad "não acusou placeholder"

echo "== 5) check-adas — núcleo adas-core e skeleton-version"
mkdir -p "$T/p3/scripts" && cd "$T/p3" && cp "$ROOT/skeleton/scripts/check-adas.sh" scripts/
printf '# X\nsem marcadores\n' > ADAS.md; echo "leia ADAS.md" > AGENTS.md; touch DECISIONS.md
out=$(bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "adas-core" && ok "acusa ADAS.md sem marcadores de núcleo" || bad "não acusou núcleo ausente"
echo "$out" | grep -q "skeleton-version" && ok "acusa install sem skeleton-version" || bad "não acusou versão ausente"

echo "== 6) hooks do host — reinjeção, envelope, roteador e guard"
R="$T/repo"; mkdir -p "$R/.claude/hooks"
printf '%s\n' '# Repo teste' '<!-- adas-core-start -->' 'NUCLEO-SENTINELA' '<!-- adas-core-end -->' > "$R/ADAS.md"
cat > "$R/.claude/hooks/adas-inject.sh" <<'EOS'
#!/usr/bin/env bash
f="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)"; [ -z "$f" ] && exit 0
printf 'FAIXA-SENTINELA' | jq -Rs '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:.}}'
EOS
echo "$R" > "$T/repos.conf"
export ADAS_REPOS_CONF="$T/repos.conf"
export HOME="$T/home"; mkdir -p "$HOME"
out=$(echo "{\"cwd\":\"$R\",\"session_id\":\"t\"}" | bash "$ROOT/host/adas-activate.sh")
echo "$out" | grep -q NUCLEO-SENTINELA && ok "SessionStart reinjeta o núcleo do repo" || bad "activate não emitiu o núcleo"
[ -f "$HOME/.claude/adas/repo.active" ] && ok "flag .active gravado (consumido pelo adas-report)" || bad "sem flag .active"
out=$(CLAUDE_PROJECT_DIR="$R" bash "$ROOT/host/adas-subagent.sh")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && ok "SubagentStart: envelope JSON válido" || bad "envelope inválido/ausente"
out=$(echo "{\"tool_input\":{\"file_path\":\"$R/x.ts\"}}" | bash "$ROOT/host/adas-route.sh")
echo "$out" | grep -q FAIXA-SENTINELA && ok "roteador delega ao adas-inject.sh do repo" || bad "roteador não delegou"
out=$(echo "{\"tool_input\":{\"file_path\":\"$R/x.ts\"}}" | CLAUDE_PROJECT_DIR="$R" bash "$ROOT/host/adas-route.sh")
[ -z "$out" ] && ok "guard anti-dupla: project==repo → silêncio" || bad "guard falhou (injeção dupla)"

echo "== 7) install.sh — merge idempotente sem destruir hooks alheios"
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<'EOS'
{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo MEU-HOOK-ALHEIO"}]}]}}
EOS
bash "$ROOT/host/install.sh" "$R" >/dev/null 2>&1 && ok "install.sh rodou" || bad "install.sh falhou"
S="$HOME/.claude/settings.json"
jq -e '.hooks.SessionStart | map(.hooks[].command) | any(test("MEU-HOOK-ALHEIO"))' "$S" >/dev/null \
  && ok "hook alheio preservado" || bad "hook alheio PERDIDO no merge"
jq -e '.hooks.PreToolUse | map(.hooks[].command) | any(test("adas-route"))' "$S" >/dev/null \
  && ok "hooks adas registrados" || bad "hooks adas ausentes"
n1=$(jq '.hooks.SessionStart | length' "$S")
bash "$ROOT/host/install.sh" "$R" >/dev/null 2>&1
n2=$(jq '.hooks.SessionStart | length' "$S")
[ "$n1" = "$n2" ] && ok "idempotente (2ª execução não duplica)" || bad "2ª execução DUPLICOU hooks ($n1→$n2)"
grep -qxF "$R" "$HOME/.claude/adas/repos.conf" && ok "repos.conf com o repo governado" || bad "repos.conf sem o repo"

echo "== 8) check-adas — ENFORCEMENT: instalação-fantasma NUNCA passa em silêncio"
# estado do teste 7: HOME=$T/home com runtime completo e $R no repos.conf → NENHUM warn
mkdir -p "$R/scripts"; cp "$ROOT/skeleton/scripts/check-adas.sh" "$R/scripts/"
cp "$ROOT/skeleton/.claude/settings.json" "$R/.claude/settings.json"
out=$(cd "$R" && bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "ENFORCEMENT" \
  && bad "falso positivo: tudo instalado mas acusou enforcement" || ok "instalado → sem warn de enforcement"
# fantasma (o caso clawd): máquina com ~/.claude mas ZERO runtime → ACUSA
H2="$T/home2"; mkdir -p "$H2/.claude"
out=$(cd "$R" && HOME="$H2" bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "runtime host NÃO instalado" \
  && ok "fantasma → acusa runtime ausente" || bad "instalação-fantasma passou em silêncio"
# meia-instalação: hooks copiados, settings sem registro → ACUSA
mkdir -p "$H2/.claude/hooks"; cp "$ROOT"/host/adas-*.sh "$H2/.claude/hooks/"; echo '{}' > "$H2/.claude/settings.json"
out=$(cd "$R" && HOME="$H2" bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "MEIA-INSTALA" \
  && ok "meia-instalação → acusa hooks sem registro" || bad "meia-instalação passou em silêncio"
# instalado mas o repo FORA do repos.conf → ACUSA
echo '{"hooks":"adas-activate adas-route"}' > "$H2/.claude/settings.json"
echo "/outro/repo" > "$H2/rc"
out=$(cd "$R" && HOME="$H2" ADAS_REPOS_CONF="$H2/rc" bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "FORA do repos.conf" \
  && ok "repo fora do repos.conf → acusa" || bad "repo não governado passou em silêncio"
# JIT do repo desligado (sem adas-inject.sh) → ACUSA
R2="$T/repo2"; mkdir -p "$R2/.claude" "$R2/scripts"; cp "$ROOT/skeleton/scripts/check-adas.sh" "$R2/scripts/"
printf '# X\n' > "$R2/ADAS.md"; touch "$R2/DECISIONS.md"
out=$(cd "$R2" && HOME="$H2" bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "JIT (PASSO 6) não existe" \
  && ok "repo sem adas-inject.sh → acusa JIT desligado" || bad "JIT desligado passou em silêncio"

echo "== 9) da-index — o índice nasce COM a DA e divergência NUNCA passa batido"
D="$T/dadir"; mkdir -p "$D/scripts" "$D/.claude/hooks"
cp "$ROOT/skeleton/scripts/da-index.sh" "$D/scripts/"
cp "$ROOT/skeleton/.claude/hooks/da-index-hook.sh" "$D/.claude/hooks/"
cat > "$D/DECISIONS.md" <<'EOS'
# T — Registro de Decisões

## DA-001 — Primeira decisão
**Status:** ok
### Decisão
Fazemos X sempre, sem exceção.

## DA-002 — Segunda decisão
`escopo: produto`
Este texto supersede a DA-001.

## DA-003 — Terceira decisão
DA-002 passa a `escopo: instância`.
EOS
bash "$D/scripts/da-index.sh" update "$D" >/dev/null 2>&1
grep -q '^- DA-001 · 🔄 SUPERSEDIDA por DA-002' "$D/DECISIONS-INDEX.md" \
  && ok "supersede pleno detectado por texto" || bad "supersede pleno não marcado"
grep -q '^- DA-002 · escopo: produto · ½ alterada por DA-003' "$D/DECISIONS-INDEX.md" \
  && ok "escopo + alteração parcial (passa a escopo)" || bad "escopo/parcial errado"
grep -q 'Fazemos X sempre' "$D/DECISIONS-INDEX.md" \
  && ok "linha 'o que decide' extraída do campo Decisão" || bad "decisão não extraída"
expect_exit 0 "check: sincronizado → verde" bash "$D/scripts/da-index.sh" check "$D"
printf '\n## DA-004 — Anexada por fora do hook\ncorpo\n' >> "$D/DECISIONS.md"
expect_exit 1 "check: DA anexada por echo >> → ACUSA divergência" bash "$D/scripts/da-index.sh" check "$D"
printf '{"tool_input":{"file_path":"%s/DECISIONS.md"}}' "$D" | bash "$D/.claude/hooks/da-index-hook.sh" >/dev/null 2>&1
grep -q '^- DA-004' "$D/DECISIONS-INDEX.md" \
  && ok "hook PostToolUse regenera no ato (a entrada nasceu com a DA)" || bad "hook não regenerou"
expect_exit 0 "check volta a verde após o hook" bash "$D/scripts/da-index.sh" check "$D"
sed -i 's/DA-004 — Anexada/DA-004 — EDITADA/' "$D/DECISIONS-INDEX.md"
expect_exit 1 "índice editado à mão → ACUSA" bash "$D/scripts/da-index.sh" check "$D"

echo "== 10) propriedade governado × dependência — por SINAL, sem lista"
X="$T/own"; mkdir -p "$X/scripts" "$X/.claude/skills/nossa-faixa" "$X/.claude/skills/vendor-plano" "$X/.claude/skills/vendor-git/sub"
cp "$ROOT/skeleton/scripts/check-adas.sh" "$X/scripts/"
printf -- '---\nname: nossa-faixa\ndescription: curta demais\n---\nextraído de .specs/x — regra nossa.\n' > "$X/.claude/skills/nossa-faixa/SKILL.md"
printf 'sem frontmatter nenhum\n' > "$X/.claude/skills/vendor-plano/SKILL.md"
mkdir -p "$X/.claude/skills/vendor-git/.git"
printf 'quebrado tambem\n' > "$X/.claude/skills/vendor-git/sub/SKILL.md"
printf '# ADAS de teste\n' > "$X/ADAS.md"; touch "$X/DECISIONS.md"
out=$(cd "$X" && bash scripts/check-adas.sh 2>/dev/null); rc=$?
[ "$rc" = 0 ] && ok "skill de terceiro quebrada NÃO bloqueia (exit 0)" || bad "dependência causou BLOCK (rc=$rc)"
echo "$out" | grep -q "TRIGGER MAGRO.*nossa-faixa" && ok "governada (procedência) segue auditada" || bad "governada escapou da auditoria"
echo "$out" | grep -q "2 skill(s) de DEPENDÊNCIA" && ok "dependências CONTADAS e declaradas (2)" || bad "contagem de dependência ausente/errada"
echo "$out" | grep -q "vendor-plano\|vendor-git" && bad "achado de dependência vazou sem flag" || ok "sem flag → dependência não polui"
out=$(cd "$X" && ADAS_CHECK_DEPS=1 bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "dep:.*vendor-plano" && ok "ADAS_CHECK_DEPS=1 exibe achados de dependência" || bad "flag não exibiu dependências"
# skill nova de terceiro chega AMANHÃ: classificada certo SEM tocar em config
mkdir -p "$X/.claude/skills/vendor-novo"; printf 'chegou hoje, sem frontmatter\n' > "$X/.claude/skills/vendor-novo/SKILL.md"
out=$(cd "$X" && bash scripts/check-adas.sh 2>/dev/null); rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q "3 skill(s) de DEPENDÊNCIA" \
  && ok "skill de terceiro NOVA classificada certo no 1º dia, zero config" || bad "skill nova classificada errado"
# adoção: citar no ADAS.md → vira governada (e o frontmatter quebrado agora BLOQUEIA)
echo "faixa vendor-novo adotada" >> "$X/ADAS.md"
out=$(cd "$X" && bash scripts/check-adas.sh 2>/dev/null); rc=$?
[ "$rc" = 1 ] && ok "adotada (citada no ADAS.md) → auditada, quebrada BLOQUEIA" || bad "adoção não puxou pra auditoria (rc=$rc)"
# conflito (fork commitado): tracked no git do root → GOVERNADA mesmo com sinais de terceiro
(cd "$X" && git init -q && git config user.email t@t && git config user.name t \
  && git add .claude/skills/vendor-plano/SKILL.md && git commit -qm x)
out=$(cd "$X" && bash scripts/check-adas.sh 2>/dev/null); rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q "vendor-plano" \
  && ok "fork COMMITADO = adotado → audita (conflito cai no lado seguro)" || bad "tracked não virou governada"

echo
echo "RESULTADO: $pass ok, $fail falha(s)"
[ "$fail" = 0 ]
