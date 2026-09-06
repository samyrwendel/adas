#!/usr/bin/env bash
# smoke — SPEC EXECUTÁVEL do repo adas (CI + local: `bash tests/smoke.sh`).
# Testa COMPORTAMENTO, não só sintaxe: cada modo de falha pego nas auditorias de 16/07
# (check morto por self-match, no-op verde do check-secrets, sobrescrita do SETUP,
# hooks do host) vira um assert permanente de regressão.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIG_HOME="$HOME"
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

echo "== 11) selo de instalação (DA-165) — a prova de que o check RODOU"
S1="$T/selo"; mkdir -p "$S1/scripts" "$S1/.adas"
cp "$ROOT/skeleton/scripts/check-adas.sh" "$S1/scripts/"
printf '# X\n<!-- adas-core-start -->\nn\n<!-- adas-core-end -->\n' > "$S1/ADAS.md"
echo "leia ADAS.md" > "$S1/AGENTS.md"; touch "$S1/DECISIONS.md"; echo "abc1234" > "$S1/.adas/skeleton-version"
out=$(cd "$S1" && bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "nunca foi PROVADA" && ok "sem selo → acusa instalação nunca provada" || bad "selo ausente passou calado"
out=$(cd "$S1" && bash scripts/check-adas.sh --seal 2>/dev/null)
[ -f "$S1/.adas/install-check" ] && grep -q "^veredito:" "$S1/.adas/install-check" \
  && ok "--seal grava .adas/install-check com veredito" || bad "--seal não gravou o selo"
out=$(cd "$S1" && bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "nunca foi PROVADA\|OBSOLETO" && bad "selado mas ainda acusa" || ok "selado + esqueleto igual → silêncio"
echo "def5678" > "$S1/.adas/skeleton-version"
out=$(cd "$S1" && bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "selo OBSOLETO" && ok "esqueleto atualizado → selo obsoleto acusa" || bad "selo obsoleto passou calado"

echo "== 12) install-hooks (DA-166) — o pre-commit BLOQUEIA de verdade"
G="$T/gated"; mkdir -p "$G/scripts"
(cd "$G" && git init -q && git config user.email t@t && git config user.name t)
cp "$ROOT/skeleton/scripts/check-secrets.sh" "$ROOT/skeleton/scripts/da-index.sh" "$G/scripts/"
printf '#!/bin/bash\ntouch hook-local-rodou\n' > "$G/.git/hooks/pre-commit"; chmod +x "$G/.git/hooks/pre-commit"
(cd "$G" && bash "$ROOT/skeleton/scripts/install-hooks.sh" >/dev/null 2>&1) && ok "install-hooks instala" || bad "install-hooks falhou"
h1="$(md5sum "$G/.git/hooks/pre-commit")"
(cd "$G" && bash "$ROOT/skeleton/scripts/install-hooks.sh" >/dev/null 2>&1)
[ "$h1" = "$(md5sum "$G/.git/hooks/pre-commit")" ] && ok "idempotente (2ª execução = mesmo hook)" || bad "2ª execução mudou o hook"
[ -f "$G/.git/hooks/pre-commit.local" ] && ok "hook alheio preservado em pre-commit.local" || bad "hook alheio PERDIDO"
# segredo montado em RUNTIME (prefixo+zeros separados): o arquivo de teste contém o
# padrão completo, mas ESTE fonte não — senão o próprio pre-commit da DA-166 bloqueia
# o commit do teste (aconteceu no commit de nascimento do gate; classe do portão que
# lê o fonte — mesma lição do gate de pictograma)
printf "tk='%s%s'\n" "ghp_" "$(printf '0%.0s' $(seq 36))" > "$G/vazou.js"
(cd "$G" && git add vazou.js)
expect_exit 1 "commit com segredo staged → BLOQUEADO (exercitado)" \
  bash -c "cd '$G' && git commit -qm x"
(cd "$G" && git rm -q --cached vazou.js && rm vazou.js && echo ok > limpo.txt && git add limpo.txt)
expect_exit 0 "commit limpo → passa (e chama o hook local)" \
  bash -c "cd '$G' && git commit -qm ok"
[ -f "$G/hook-local-rodou" ] && ok "hook alheio ainda roda (encadeado)" || bad "hook alheio não foi chamado"

echo "== 13) adas-resolve.sh / adas-secret-guard.sh — a fonte que os plugins multi-harness chamam"
export HOME="$ORIG_HOME"   # seções 6-12 rodaram com HOME de fixture; da aqui em diante é ambiente real
export ADAS_REPOS_CONF="$T/repos.conf"
echo "$R" > "$T/repos.conf"
out=$(bash "$ROOT/host/adas-resolve.sh" "$R/sub/dir")
[ "$out" = "$R" ] && ok "adas-resolve.sh acha a raiz de um path dentro do repo" || bad "adas-resolve.sh não resolveu (out=$out)"
bash "$ROOT/host/adas-resolve.sh" "/nao/e/governado" >/dev/null 2>&1
expect_exit 1 "adas-resolve.sh: path fora de repo governado → rc=1" bash "$ROOT/host/adas-resolve.sh" "/nao/e/governado"
out=$(bash "$ROOT/host/adas-secret-guard.sh" "cat .env")
echo "$out" | grep -q '^block:seguranca-acesso' && ok "secret-guard BLOQUEIA cat .env" || bad "secret-guard não bloqueou cat .env (out=$out)"
out=$(bash "$ROOT/host/adas-secret-guard.sh" "cat .env.example")
[ "$out" = "allow" ] && ok "secret-guard PERMITE .env.example" || bad "secret-guard bloqueou .env.example por engano (out=$out)"
out=$(bash "$ROOT/host/adas-secret-guard.sh" "ls -la")
[ "$out" = "allow" ] && ok "secret-guard PERMITE comando inofensivo" || bad "secret-guard bloqueou comando inofensivo (out=$out)"
out=$(bash "$ROOT/host/adas-secret-guard.sh" "cat .env && rm -rf /")
echo "$out" | grep -q '^block:' && ok "secret-guard bloqueia mesmo com comando encadeado (&&)" || bad "secret-guard vazou comando encadeado (out=$out)"
unset ADAS_REPOS_CONF

echo "== 14) plugins multi-harness — build/testes reais rodam (não só existem)"
if command -v npm >/dev/null 2>&1 && [ -d "$ROOT/host/openclaw-plugin/node_modules/openclaw" ]; then
  ( cd "$ROOT/host/openclaw-plugin" && npm test >/tmp/adas-openclaw-smoke.log 2>&1 )
  oc_rc=$?
  [ "$oc_rc" = 0 ] && ok "adas-openclaw: build+vitest verdes" || bad "adas-openclaw: npm test falhou (rc=$oc_rc, ver /tmp/adas-openclaw-smoke.log)"
else
  echo "  (pulado — sem npm/openclaw linkado neste ambiente; rode 'npm test' manualmente em host/openclaw-plugin/)"
fi
if command -v python3 >/dev/null 2>&1 && python3 -c "import pytest" >/dev/null 2>&1; then
  ( cd "$ROOT/host/hermes-plugin" && python3 -m pytest test_adas_hermes.py -q >/tmp/adas-hermes-smoke.log 2>&1 )
  hm_rc=$?
  [ "$hm_rc" = 0 ] && ok "adas-hermes: pytest verde" || bad "adas-hermes: pytest falhou (rc=$hm_rc, ver /tmp/adas-hermes-smoke.log)"
else
  echo "  (pulado — sem pytest neste ambiente)"
fi

echo "== 15) seis portas de segurança do app (DA-189) — 6 fixtures"
# Portas 1/2 (mecânicas, check-secrets.sh) e 3-6 (com prova, check-app-security.sh).
mkdir -p "$T/sp1/static" && (cd "$T/sp1" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir -p scripts && cp "$ROOT/skeleton/scripts/check-secrets.sh" scripts/ \
  && echo ok > README.md && git add -A && git commit -qm x)
(cd "$T/sp1" && echo 'const k = "sk-ABCDEFGHIJKLMNOPQRSTUVWX";' > static/app.js && git add static/app.js)
out=$(cd "$T/sp1" && bash scripts/check-secrets.sh 2>&1); rc=$?
[ "$rc" = 1 ] && ok "porta 1 — chave sk- em static/ → FALHA" || bad "porta 1 (chave em static) não bloqueou (rc=$rc)"
echo "$out" | grep -q "porta 1" || bad "porta 1: mensagem não identifica a porta"

mkdir -p "$T/sp2" && (cd "$T/sp2" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir -p scripts && cp "$ROOT/skeleton/scripts/check-secrets.sh" scripts/ \
  && echo ok > README.md && git add -A && git commit -qm x)
(cd "$T/sp2" && echo 'NEXT_PUBLIC_STRIPE_SECRET'"_KEY=abc" > .env.example && git add .env.example)
# ^ literal quebrada em duas strings de propósito: concatenada em runtime pro
#   fixture ficar íntegra, mas SEM aparecer contígua na fonte deste arquivo —
#   senão o check-secrets.sh REAL (rodando no pre-commit deste repo) bloqueava
#   o commit da própria suite por causa do padrão que ela mesma testa.
out=$(cd "$T/sp2" && bash scripts/check-secrets.sh 2>&1); rc=$?
[ "$rc" = 1 ] && ok "porta 1 — NEXT_PUBLIC_*_SECRET_KEY → FALHA" || bad "porta 1 (prefixo público) não bloqueou (rc=$rc)"

mkdir -p "$T/sp3" && (cd "$T/sp3" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir -p scripts && cp "$ROOT/skeleton/scripts/check-secrets.sh" scripts/ \
  && echo ok > README.md && git add -A && git commit -qm x \
  && echo "TELEGRAM_BOT_TOKEN=123456:AAfake" > .env && git add -f .env && git commit -qm "oops" \
  && git rm -q .env && git commit -qm "remove env")
out=$(cd "$T/sp3" && bash scripts/check-secrets.sh --all 2>&1); rc=$?
[ "$rc" = 1 ] && ok "porta 2 — .env removido mas vivo no histórico → FALHA" || bad "porta 2 (.env no histórico) não bloqueou (rc=$rc)"
echo "$out" | grep -qi "rotacione ANTES de limpar" || bad "porta 2: sem a instrução de rotacionar antes de limpar"

mkdir -p "$T/sp3b" && (cd "$T/sp3b" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir -p scripts && cp "$ROOT/skeleton/scripts/check-secrets.sh" scripts/ \
  && printf 'OPENAI_API_KEY=\nANTHROPIC_API_KEY=\n' > .env.example && git add -A && git commit -qm "add .env.example")
out=$(cd "$T/sp3b" && bash scripts/check-secrets.sh --all 2>&1); rc=$?
[ "$rc" = 0 ] && ok "porta 2 — .env.example (SEM valor) no histórico → não é falha (falso positivo corrigido)" \
  || bad "porta 2 confundiu .env.example com .env real (rc=$rc): $out"

mkdir -p "$T/sp3c" && (cd "$T/sp3c" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir -p scripts && cp "$ROOT/skeleton/scripts/check-secrets.sh" scripts/ \
  && printf 'OPENAI_API_KEY=\n' > .env.enterprise.example && git add -A && git commit -qm x)
out=$(cd "$T/sp3c" && bash scripts/check-secrets.sh --all 2>&1); rc=$?
[ "$rc" = 0 ] && ok ".env.<algo>.example (segmento extra) tracked → não é falso BLOCK (achado real da task 20260904-005)" \
  || bad ".env.enterprise.example ainda bloqueia por engano (rc=$rc): $out"

mkdir -p "$T/sp4/scripts" && cp "$ROOT/skeleton/scripts/check-app-security.sh" "$T/sp4/scripts/"
out=$(cd "$T/sp4" && bash scripts/check-app-security.sh 2>&1); rc=$?
[ "$rc" = 0 ] && ok "sem .adas/seguranca-app.json → WARN, não bloqueia" || bad "sem json bloqueou (esperado warn, rc=$rc)"
[ "$(echo "$out" | grep -c "adas: débito")" = 4 ] && ok "sem json — as 4 portas com prova viram débito adas:" \
  || bad "sem json — não listou as 4 portas como débito"

mkdir -p "$T/sp5/scripts" "$T/sp5/.adas" && cp "$ROOT/skeleton/scripts/check-app-security.sh" "$T/sp5/scripts/"
cat > "$T/sp5/.adas/seguranca-app.json" <<'EOS'
{
  "validacao_servidor": {"estado": "passa", "evidencia": "", "data": "2026-09-04"},
  "arquivo_publico": {"estado": "debito"},
  "erro_fala_demais": {"estado": "debito"},
  "rate_limit": {"estado": "debito"}
}
EOS
out=$(cd "$T/sp5" && bash scripts/check-app-security.sh 2>&1); rc=$?
[ "$rc" = 1 ] && ok "porta 3 'passa' SEM evidência → FAIL (DA-174)" || bad "'passa' sem evidência não falhou (rc=$rc)"
echo "$out" | grep -qi "DA-174" || bad "FAIL sem evidência não cita DA-174"

mkdir -p "$T/sp6/scripts" "$T/sp6/.adas" && cp "$ROOT/skeleton/scripts/check-app-security.sh" "$T/sp6/scripts/"
cat > "$T/sp6/.adas/seguranca-app.json" <<'EOS'
{
  "validacao_servidor": {"estado": "na", "evidencia": "site estático, nenhuma rota de escrita", "data": "2026-09-04"},
  "arquivo_publico": {"estado": "debito"},
  "erro_fala_demais": {"estado": "debito"},
  "rate_limit": {"estado": "debito"}
}
EOS
out=$(cd "$T/sp6" && bash scripts/check-app-security.sh 2>&1); rc=$?
[ "$rc" = 0 ] && ok "porta 3 'na' JUSTIFICADO → PASSA (não bloqueia)" || bad "'na' justificado bloqueou (rc=$rc)"
echo "$out" | grep -q "N/A (justificado)" || bad "'na' justificado não imprimiu o veredito PASSA"

mkdir -p "$T/sp7/scripts" "$T/sp7/.adas" && (cd "$T/sp7" && git init -q && git config user.email t@t && git config user.name t)
cp "$ROOT/skeleton/scripts/check-secrets.sh" "$T/sp7/scripts/"
cp "$ROOT/skeleton/scripts/check-app-security.sh" "$T/sp7/scripts/"
cp "$ROOT/skeleton/scripts/check-adas.sh" "$T/sp7/scripts/"
cp "$T/sp6/.adas/seguranca-app.json" "$T/sp7/.adas/"
(cd "$T/sp7" && echo "leia ADAS.md" > AGENTS.md \
  && printf '# X\n<!-- adas-core-start -->\nN\n<!-- adas-core-end -->\n' > ADAS.md \
  && touch DECISIONS.md && git add -A && git commit -qm init)
out=$(cd "$T/sp7" && bash scripts/check-adas.sh 2>&1)
echo "$out" | grep -q "SEIS PORTAS (DA-189):" && ok "check-adas.sh mostra o resumo das 6 portas" || bad "check-adas.sh não mostrou as 6 portas"
echo "$out" | grep -q "1 chave-no-front=PASSA · 2 env-historico=PASSA" && ok "check-adas.sh: portas mecânicas (1/2) refletem o check-secrets.sh live" \
  || bad "check-adas.sh não rodou/leu as portas mecânicas"
echo "$out" | grep -q "3 validacao-servidor=N/A (justificado)" && ok "check-adas.sh: porta 3 lê .adas/seguranca-app.json" \
  || bad "check-adas.sh não leu o estado da porta 3"
echo "$out" | grep -q "5 erro-fala-demais=débito" && ok "check-adas.sh: porta sem prova aparece como débito" \
  || bad "check-adas.sh não marcou a porta sem prova como débito"

echo "== 16) COBERTURA DE ATOR (task 20260905-008) — gatilho só-fala-do-dono acusa; com ato do agente, passa"
AT="$T/ator"; mkdir -p "$AT/scripts" "$AT/.claude/skills/so-dono"
cp "$ROOT/skeleton/scripts/check-adas.sh" "$AT/scripts/"
# filler NEUTRO (sem citar as próprias palavras-gatilho do check, senão auto-combina
# e falseia o RED — a mesma classe de self-match que o check-_template.sh (seção 2) já corrige)
FILLER='lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat duis aute irure dolor.'
printf -- '---\nname: so-dono\ndescription: "use SEMPRE que o dono disser: '"'"'vamos fazer assim'"'"', '"'"'fica assim'"'"', '"'"'a partir de agora'"'"', '"'"'sempre que'"'"', '"'"'nunca mais'"'"', '"'"'toda vez que'"'"', '"'"'regra nova'"'"', '"'"'padrão novo'"'"', '"'"'vamos adotar'"'"', '"'"'muda pra X'"'"', '"'"'reverte'"'"', '"'"'pode fazer'"'"', '"'"'aprovado'"'"', '"'"'ok'"'"', MESMO que o usuário não peça — '"$FILLER"'"\n---\nextraído de .specs/x — regra nossa.\n' > "$AT/.claude/skills/so-dono/SKILL.md"
printf '# ADAS teste\nfaixa so-dono adotada\n' > "$AT/ADAS.md"; touch "$AT/DECISIONS.md"
out=$(cd "$AT" && bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "COBERTURA DE ATOR.*so-dono" && ok "faixa só-fala-do-dono → acusa COBERTURA DE ATOR" || bad "não acusou cobertura de ator (RED esperado)"
printf -- '---\nname: so-dono\ndescription: "use SEMPRE que o dono disser: '"'"'vamos fazer assim'"'"', '"'"'fica assim'"'"', '"'"'a partir de agora'"'"', '"'"'sempre que'"'"', '"'"'nunca mais'"'"', '"'"'toda vez que'"'"', '"'"'regra nova'"'"', '"'"'padrão novo'"'"', '"'"'vamos adotar'"'"', '"'"'muda pra X'"'"', '"'"'reverte'"'"', '"'"'pode fazer'"'"', '"'"'aprovado'"'"', '"'"'ok'"'"', MESMO que o usuário não peça; dispara IGUAL quando o agente decide sozinho, por conta própria, tipo '"'"'a partir de agora eu vou sempre conferir X antes de Y'"'"' — mais texto de enchimento pra passar o piso de tamanho, garantindo mais de quatrocentos caracteres no total desta description longa o bastante."\n---\nextraído de .specs/x — regra nossa.\n' > "$AT/.claude/skills/so-dono/SKILL.md"
out=$(cd "$AT" && bash scripts/check-adas.sh 2>/dev/null)
echo "$out" | grep -q "COBERTURA DE ATOR" && bad "com ato do agente citado, ainda acusa (GREEN esperado)" || ok "com ato do agente citado → passa (sem COBERTURA DE ATOR)"

echo "== 17) ORÇAMENTO da emissão do SessionStart (adas_session_emit) — teto de 10 KiB do harness"
# CONTEXTO: o Claude Code PERSISTE stdout de hook > 10 KiB e entrega ao modelo só um
# preview de 2 KiB. Medido nos transcripts (05/09): maior inline 10.215 B, menor
# persistido 10.822 B → fronteira 10*1024. adas_session_emit orça 9.600 B e o que não
# cabe vira PONTEIRO auditável [ADAS-CORTE]; prioridade DECLARADA: vigente (sagas) antes
# de histórico (lições). Este assert FALHA se a emissão passar do orçamento — regressão
# impossível de passar despercebida quando o diário crescer de novo.
BR="$T/bud"; mkdir -p "$BR/scripts" "$BR/.claude/adas"
echo "$BR" > "$BR/.claude/adas/repos.conf"
printf '# ADAS teste\n<!-- adas-core-start -->\nNUCLEO-TESTE regra vigente do repo.\n<!-- adas-core-end -->\n' > "$BR/ADAS.md"
touch "$BR/DECISIONS.md"
cat > "$BR/scripts/da-index.sh" <<'STUB'
#!/usr/bin/env bash
head -c "${SAGAS_BYTES:-20000}" </dev/zero | tr '\0' 'S'
STUB
head -c 20000 </dev/zero | tr '\0' 'L' > "$BR/DECISIONS-LICOES.md"
emit(){ HOME="$BR" ADAS_EMIT_BUDGET="$1" SAGAS_BYTES="$2" bash -c 'source "'"$ROOT"'/host/adas-lib.sh"; adas_session_emit "'"$BR"'"'; }
blen(){ LC_ALL=C wc -c; }

# A) sagas(20k)+lições(20k) NÃO cabem: emissão <= orçamento, < teto, com os dois ponteiros
o="$(emit 9600 20000)"; b="$(printf '%s' "$o" | blen)"
[ "$b" -le 9600 ] && ok "emissão ($b B) <= orçamento 9600" || bad "emissão ($b B) ESTOUROU o orçamento 9600"
[ "$b" -lt 10240 ] && ok "emissão ($b B) < teto 10240 (entrega inline, não persiste)" || bad "emissão ($b B) >= teto 10240 (seria cortada a 2 KiB)"
printf '%s' "$o" | grep -q "NUCLEO-TESTE" && ok "núcleo (a REGRA) chega inteiro" || bad "núcleo não chegou"
printf '%s' "$o" | grep -q "\[ADAS-CORTE\] sagas" && ok "sagas que não coube → ponteiro [ADAS-CORTE]" || bad "sagas cortada em SILÊNCIO"
printf '%s' "$o" | grep -q "\[ADAS-CORTE\] licoes" && ok "lições que não coube → ponteiro [ADAS-CORTE]" || bad "lições cortada em SILÊNCIO"
printf '%s' "$o" | grep -q "leia com: cat ~/DECISIONS-LICOES.md" && ok "ponteiro DIZ como ler o resto" || bad "ponteiro sem comando de leitura"

# B) DENTE: sem orçamento (teto gigante) a MESMA emissão estoura o teto — o defeito que o orçamento fecha
o2="$(emit 99999999 20000)"; b2="$(printf '%s' "$o2" | blen)"
[ "$b2" -gt 10240 ] && ok "sem orçamento a emissão ($b2 B) estoura o teto (RED que o orçamento evita)" || bad "fixture pequena: sem orçamento deu $b2 B, o teste não tem dente"

# C) PRIORIDADE: sagas pequena (1k) CABE → vigente inline; histórico (lições) cede primeiro
o3="$(emit 9600 1000)"; b3="$(printf '%s' "$o3" | blen)"
[ "$b3" -le 9600 ] && ok "com sagas pequena, emissão ($b3 B) <= orçamento" || bad "emissão ($b3 B) estourou"
printf '%s' "$o3" | grep -q "\[ADAS-CORTE\] sagas" && bad "sagas pequena foi cortada (deveria caber inline)" || ok "sagas vigente cabe → INLINE"
printf '%s' "$o3" | grep -q "\[ADAS-CORTE\] licoes" && ok "histórico cede primeiro → ponteiro" || bad "lições não cedeu (prioridade invertida)"

echo "== 18) da-index c9/c12 DESLIGADOS (task 20260906-028) — fixtures que ANTES acusavam agora ficam em silêncio; SAGAS/VIGENTE não nascem"
# HISTÓRICO: esta seção era o dente do c12 (DA-234: acusar 3ª rodada de saga em aberto, calar em saga
# resolvida). Em 06/09/2026 o Samyr mandou desligar a maquinaria de saga/cabeça/NA (task 20260906-028):
# saem a geração de DECISIONS-SAGAS.md/DECISIONS-VIGENTE-*.md e os checks c9/c12; fica o conteúdo do
# diário e a camada 0. As 3 asserções antigas testavam a maquinaria removida — foram substituídas pelo
# dente inverso (não acusa mais) + a prova de que nada de conteúdo se perde. fixture-c12-mau ganhou
# DA-106..108 (3 rodadas DEPOIS da cabeça DA-105) — antes disparava c9.
C12="$T/c12"; mkdir -p "$C12/scripts"
cp "$ROOT/skeleton/scripts/da-index.sh" "$C12/scripts/"
cat > "$C12/DECISIONS.md" <<'EOS'
# T — Registro de Decisões

## DA-101 — Fixture mau padrão, tentativa 1
`escopo: produto` · `saga: fixture-c12-mau` · `data: 2026-01-01`
**Regra:** tentativa 1, remenda um emissor.

## DA-102 — Fixture mau padrão, tentativa 2
`escopo: produto` · `saga: fixture-c12-mau` · `data: 2026-01-02`
**Regra:** tentativa 2, remenda outro emissor.

## DA-103 — Fixture mau padrão, tentativa 3 (aqui o aviso já deveria ter soado, na hora)
`escopo: produto` · `saga: fixture-c12-mau` · `data: 2026-01-02`
**Regra:** tentativa 3, ainda não foi na raiz.

## DA-104 — Fixture mau padrão, tentativa 4
`escopo: produto` · `saga: fixture-c12-mau` · `data: 2026-01-03`
**Regra:** tentativa 4, o padrão persiste.

## DA-105 — Fixture mau padrão, cabeça tardia
`escopo: produto` · `saga: fixture-c12-mau` · `data: 2026-01-10` · `consolida: DA-101, DA-102, DA-103, DA-104`
**Regra:** achou a raiz na 5ª, tarde demais — mas achou. É história agora.

## DA-106 — Fixture mau padrão, rodada 1 depois da cabeça
`escopo: produto` · `saga: fixture-c12-mau` · `data: 2026-01-11`
**Regra:** remendo depois da cabeça, 1.

## DA-107 — Fixture mau padrão, rodada 2 depois da cabeça
`escopo: produto` · `saga: fixture-c12-mau` · `data: 2026-01-12`
**Regra:** remendo depois da cabeça, 2.

## DA-108 — Fixture mau padrão, rodada 3 depois da cabeça (antes: c9 "hora de nova cabeça")
`escopo: produto` · `saga: fixture-c12-mau` · `data: 2026-01-13`
**Regra:** remendo depois da cabeça, 3.

## DA-201 — Fixture bom padrão, parte 1
`escopo: produto` · `saga: fixture-c12-bom` · `data: 2026-02-01`
**Regra:** parte 1 do desenho.

## DA-202 — Fixture bom padrão, parte 2
`escopo: produto` · `saga: fixture-c12-bom` · `data: 2026-02-01`
**Regra:** parte 2 do desenho.

## DA-203 — Fixture bom padrão, parte 3
`escopo: produto` · `saga: fixture-c12-bom` · `data: 2026-02-01`
**Regra:** parte 3, fecha o desenho.

## DA-204 — Fixture bom padrão, cabeça no tempo certo
`escopo: produto` · `saga: fixture-c12-bom` · `data: 2026-02-05` · `consolida: DA-201, DA-202, DA-203`
**Regra:** cabeça natural — resolveu exatamente na 3ª, sem 4ª rodada.

## DA-301 — Fixture aberta, tentativa 1
`escopo: produto` · `saga: fixture-c12-aberto` · `data: 2026-03-01`
**Regra:** tentativa 1, remenda um emissor.

## DA-302 — Fixture aberta, tentativa 2
`escopo: produto` · `saga: fixture-c12-aberto` · `data: 2026-03-01`
**Regra:** tentativa 2, remenda outro emissor.

## DA-303 — Fixture aberta, tentativa 3 (aqui o aviso deve soar e o diário acaba sem resolver)
`escopo: produto` · `saga: fixture-c12-aberto` · `data: 2026-03-02`
**Regra:** tentativa 3, ainda não foi na raiz — e nunca mais aparece consolida:/supersede: desta saga.
EOS
sha_before="$(sha256sum "$C12/DECISIONS.md" | cut -d" " -f1)"
out=$(bash "$C12/scripts/da-index.sh" update "$C12" 2>&1)
echo "$out" | grep -q "^WARN c12:" && bad "c12 ainda acusa (deveria estar DESLIGADO — task 028)" || ok "c12 desligado: fixture-c12-aberto (3ª rodada em aberto) não acusa mais"
echo "$out" | grep -q "^WARN c9:" && bad "c9 ainda acusa (deveria estar DESLIGADO — task 028)" || ok "c9 desligado: fixture-c12-mau com 3 rodadas depois da cabeça não acusa mais"
[ -f "$C12/DECISIONS-SAGAS.md" ] && bad "update ainda gera DECISIONS-SAGAS.md" || ok "update não gera DECISIONS-SAGAS.md"
[ -z "$(ls "$C12"/DECISIONS-VIGENTE-*.md 2>/dev/null)" ] && ok "update não gera DECISIONS-VIGENTE-*.md" || bad "update ainda gera DECISIONS-VIGENTE-*.md"
[ -f "$C12/DECISIONS-INDEX.md" ] && [ -f "$C12/DECISIONS-LICOES.md" ] && ok "INDEX e LICOES continuam sendo gerados" || bad "INDEX/LICOES sumiram junto (desligou demais)"
[ "$sha_before" = "$(sha256sum "$C12/DECISIONS.md" | cut -d" " -f1)" ] && ok "DECISIONS.md byte a byte intocado pelo update" || bad "update alterou o DECISIONS.md"
bash "$C12/scripts/da-index.sh" show DA-105 "$C12" | grep -q "cabeça tardia" && ok "cabeça DA-105 continua legível por show" || bad "show DA-105 falhou"
printf 'x\n' > "$C12/DECISIONS-SAGAS.md"   # arquivo velho/estranho deixado no lugar NÃO faz o check falhar
bash "$C12/scripts/da-index.sh" check "$C12" >/dev/null 2>&1 && ok "check ignora DECISIONS-SAGAS.md legado (não é mais conferido)" || bad "check ainda exige/confere DECISIONS-SAGAS.md"

echo "== 19) item 2b — núcleo via @import do CLAUDE.md GLOBAL, com fallback e autocura"
# CONTEXTO: ~/.claude/CLAUDE.md carrega inteiro em toda sessão desta máquina (medido:
# @import não corta até 160 KB). O núcleo passa a chegar por lá; o hook só o reemite
# inline (consumindo orçamento) quando NÃO há prova de que o import está entregando —
# linha ausente, cache ausente, ou núcleo mudou e o cache ainda é o antigo.
IM="$T/imp"; mkdir -p "$IM/scripts" "$IM/.claude/adas"
echo "$IM" > "$IM/.claude/adas/repos.conf"
printf '# ADAS teste import\n<!-- adas-core-start -->\nNUCLEO-TESTE-2B regra vigente v1.\n<!-- adas-core-end -->\n' > "$IM/ADAS.md"
emit2(){ HOME="$IM" bash -c 'source "'"$ROOT"'/host/adas-lib.sh"; adas_session_emit "'"$IM"'"'; }

# A) sem ~/.claude/CLAUDE.md nenhum → fallback: núcleo inline + cache autocurado
rm -f "$IM/.claude/CLAUDE.md" "$IM/.claude/adas-core-import.md"
o="$(emit2)"
echo "$o" | grep -q "NUCLEO-TESTE-2B" && ok "sem CLAUDE.md → fallback emite o núcleo inline" \
  || bad "sem CLAUDE.md: núcleo NÃO chegou por nenhum canal (o buraco que a DA-230 proíbe)"
grep -q "NUCLEO-TESTE-2B" "$IM/.claude/adas-core-import.md" 2>/dev/null \
  && ok "autocura: cache criado com o núcleo atual mesmo no fallback" || bad "cache não foi autocurado"

# B) CLAUDE.md existe mas SEM a linha de import → ainda fallback
printf 'algum CLAUDE.md sem a linha magica\n' > "$IM/.claude/CLAUDE.md"
o="$(emit2)"
echo "$o" | grep -q "NUCLEO-TESTE-2B" && ok "CLAUDE.md sem linha de import → fallback emite núcleo inline" \
  || bad "CLAUDE.md sem linha de import: núcleo sumiu"

# C) CLAUDE.md COM a linha + cache já sincronizado (item A/B deixaram o cache = v1) → SUPRIME
printf '@adas-core-import.md\n' > "$IM/.claude/CLAUDE.md"
o="$(emit2)"
echo "$o" | grep -q "NUCLEO-TESTE-2B" && bad "sincronizado mas emitiu inline mesmo assim (orçamento não foi liberado)" \
  || ok "import sincronizado → emissão inline SUPRIMIDA (orçamento inteiro livre pra camada 0)"

# D) núcleo MUDA (edição real do ADAS.md) → cache antigo diverge → fallback reemite a versão NOVA
printf '# ADAS teste import\n<!-- adas-core-start -->\nNUCLEO-TESTE-2B regra vigente v2 (mudou).\n<!-- adas-core-end -->\n' > "$IM/ADAS.md"
o="$(emit2)"
echo "$o" | grep -q "v2 (mudou)" && ok "núcleo mudou → cache desatualizado detectado, fallback reemite a versão NOVA" \
  || bad "núcleo mudou e a versão nova não chegou (cache velho mascarou a mudança)"
# self-heal: a chamada seguinte já deve vir suprimida com o cache atualizado pra v2
o2="$(emit2)"
echo "$o2" | grep -q "v2 (mudou)" && bad "cache autocurado mas 2ª chamada ainda emitiu inline" \
  || ok "cache autocurado pra v2 → 2ª chamada já vem suprimida"

echo "== 20) fronteira de bloco (adas_emit_block) — DENTE genérico, não só do cabeçalho (task 20260906-009)"
# CONTEXTO: 3 colapsos de fronteira JÁ vistos aqui, um de cada vez — rodapé colado na
# última saga (9c17511), cabeçalho colado na primeira saga (a viva quando esta task foi
# aberta). Causa raiz: command substitution engole o \n final de QUALQUER "$(...)", e cada
# ponto que montava um bloco à mão tratava (ou esquecia de tratar) isso sozinho. O fix
# unifica em adas_emit_block; este teste usa fixtures REALISTAS multi-linha (a fixture do
# teste 17 é um blob de 1 char sem \n interno — não pegaria NENHUM dos 3 colapsos) e
# confere a fronteira de TODO bloco de uma vez, pra pegar a 4ª superfície antes dela existir.
FRT="$T/frt"; mkdir -p "$FRT/scripts"
touch "$FRT/DECISIONS.md"
N_SAGAS=4
cat > "$FRT/scripts/da-index.sh" <<'STUB'
#!/usr/bin/env bash
for i in 1 2 3 4; do
  printf -- '- fixture-saga-%d · produto · cabeça: DA-10%d · 1 DA · Regra: linha de teste realista numero %d, prova que cada saga fica na sua propria linha, nunca colada na vizinha.\n' "$i" "$i" "$i"
done
STUB
M_LICOES=3
{
  for i in 1 2 3; do
    printf -- '- LICAO-%d — bullet de licao numero %d, texto suficiente pra simular o historico real e servir de ancora de fronteira.\n' "$i" "$i"
  done
} > "$FRT/DECISIONS-LICOES.md"
frt_emit(){ local budget="$1"; HOME="$FRT" bash -c 'source "'"$ROOT"'/host/adas-lib.sh"; adas_da_layer0 "'"$FRT"'" "'"$budget"'"'; }

# A) tudo cabe: cabeçalho, as 4 sagas, o rodapé e as 3 lições — cada um na SUA linha
o="$(frt_emit 999999)"; printf '%s\n' "$o" > "$T/frt_full.txt"
n_sagas=$(grep -c '^- fixture-saga-' "$T/frt_full.txt")
n_licoes=$(grep -c '^- LICAO-' "$T/frt_full.txt")
[ "$n_sagas" = "$N_SAGAS" ] && ok "as $N_SAGAS sagas chegam como $N_SAGAS itens de lista (não $((N_SAGAS-1)))" \
  || bad "sagas: esperado $N_SAGAS itens, chegaram $n_sagas — alguma fronteira colou"
[ "$n_licoes" = "$M_LICOES" ] && ok "as $M_LICOES lições chegam como $M_LICOES itens de lista" \
  || bad "lições: esperado $M_LICOES itens, chegaram $n_licoes — alguma fronteira colou"
# DENTE forte: total de linhas = 1 (branco líder) + 1 (cabeçalho) + sagas + 1 (rodapé) + lições.
# QUALQUER colagem em QUALQUER fronteira reduz esta soma — pega a 4ª superfície sem saber
# de antemão qual vai ser.
esperado=$((1 + 1 + N_SAGAS + 1 + M_LICOES))
total=$(wc -l < "$T/frt_full.txt")
[ "$total" = "$esperado" ] && ok "total de linhas ($total) bate com a soma dos blocos — nenhuma fronteira colou" \
  || bad "total de linhas ($total) != esperado ($esperado) — duas coisas grudaram numa linha só"
grep -q '^\[DECISIONS camada 0.*fixture-saga' "$T/frt_full.txt" \
  && bad "cabeçalho colado na 1ª saga" || ok "cabeçalho termina na própria linha (não gruda na 1ª saga)"
grep -q '^- fixture-saga.*membros completos' "$T/frt_full.txt" \
  && bad "última saga colada no rodapé" || ok "rodapé começa na própria linha (não gruda na última saga)"
grep -q '^membros completos.*LICAO' "$T/frt_full.txt" \
  && bad "rodapé colado na 1ª lição" || ok "1ª lição começa na própria linha (não gruda no rodapé)"

# B) orçamento força corte das SAGAS → [ADAS-CORTE] próprio, sem colar no cabeçalho
# (400: cabe o cabeçalho + o ponteiro; abaixo disso nem o ponteiro cabe e some em
# silêncio — mesmo comportamento de antes do fix, não é regressão desta task)
o="$(frt_emit 400)"; printf '%s\n' "$o" > "$T/frt_cut_sagas.txt"
grep -q '^\[ADAS-CORTE\] sagas' "$T/frt_cut_sagas.txt" \
  && ok "sagas cortadas (orçamento 400) → [ADAS-CORTE] na própria linha" || bad "corte de sagas não gerou ponteiro isolado"
grep -q '^\[DECISIONS camada 0.*ADAS-CORTE' "$T/frt_cut_sagas.txt" \
  && bad "cabeçalho colado no ponteiro [ADAS-CORTE] de sagas" || ok "cabeçalho não cola no ponteiro de corte de sagas"

# C) orçamento cabe cabeçalho+sagas+rodapé mas força corte das LIÇÕES
o="$(frt_emit 1150)"; printf '%s\n' "$o" > "$T/frt_cut_licoes.txt"
n_sagas_c=$(grep -c '^- fixture-saga-' "$T/frt_cut_licoes.txt")
[ "$n_sagas_c" = "$N_SAGAS" ] && ok "com orçamento 1150, as $N_SAGAS sagas ainda cabem inteiras" \
  || bad "fixture do teste C não isola lições (sagas=$n_sagas_c, esperado $N_SAGAS) — ajustar orçamento"
grep -q '^\[ADAS-CORTE\] licoes' "$T/frt_cut_licoes.txt" \
  && ok "lições cortadas (orçamento 1150) → [ADAS-CORTE] na própria linha" || bad "corte de lições não gerou ponteiro isolado"
grep -q 'membros completos.*ADAS-CORTE' "$T/frt_cut_licoes.txt" \
  && bad "rodapé colado no ponteiro [ADAS-CORTE] de lições" || ok "rodapé não cola no ponteiro de corte de lições"

echo
echo "RESULTADO: $pass ok, $fail falha(s)"
[ "$fail" = 0 ]
