#!/usr/bin/env bash
# Teste do gatilho "segredo nunca entra no repo": check-secrets.sh tem de BLOQUEAR um token
# commitado/staged e passar num repo limpo. O token falso é montado em runtime para este
# arquivo não acionar o próprio gate.
set -uo pipefail
# Roda dentro do pre-commit, que exporta GIT_DIR/GIT_INDEX_FILE — numa worktree o GIT_DIR aponta pro repo
# REAL, e sem limpar, o `git init` daqui reinicializa o repo do projeto (core.bare=true, user=t; aconteceu
# em 25/09/2026, task 20260926-001).
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CS="$HERE/../../scripts/check-secrets.sh"
[ -f "$CS" ] || { echo "✗ sem scripts/check-secrets.sh"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
tk="ghp_$(printf '0%.0s' $(seq 36))"
# Bearer sem marca de fixture, também montado em runtime: literal aqui, este arquivo acusaria a porta 2 (histórico)
# de toda casa que o commitasse — e do próprio produto (revisão 025; aconteceu no 1e7171a).
bz="Bearer zK7qPmRv$(printf '4Xn2Ld9wTbH6')"

mkdir -p "$T/sujo/scripts" && cd "$T/sujo" && git init -q && git config user.email t@t && git config user.name t \
  && cp "$CS" scripts/ && echo "tk='$tk'" > c.js && git add -A && git commit -qm x
bash scripts/check-secrets.sh >/dev/null 2>&1 && { echo "✗ token commitado passou"; exit 1; }
# token de bot Telegram (<id>:AA<33 base64url>), montado em runtime. Caso real 07/09: token VIVO do bot
# ficou literal em .py solto e o gate passou VERDE em --dir (sem git) — o modo que varre a home.
tg="$(printf '1%.0s' $(seq 10)):AA$(printf 'a%.0s' $(seq 33))"
mkdir -p "$T/tg/scripts" && cd "$T/tg" && cp "$CS" scripts/ && echo "TELEGRAM_TOKEN = \"$tg\"" > bot.py
bash scripts/check-secrets.sh --dir . >/dev/null 2>&1 && { echo "✗ token de bot Telegram em dir sem git (--dir) passou"; exit 1; }
git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm x
bash scripts/check-secrets.sh >/dev/null 2>&1 && { echo "✗ token de bot Telegram commitado passou"; exit 1; }

mkdir -p "$T/limpo/scripts" && cd "$T/limpo" && git init -q && git config user.email t@t && git config user.name t \
  && cp "$CS" scripts/ && echo ok > a.txt && git add -A && git commit -qm x
bash scripts/check-secrets.sh >/dev/null 2>&1 || { echo "✗ repo limpo foi bloqueado"; exit 1; }
# allowlist declarada (caminho | motivo | data): fixture com padrão de chave no histórico passa SÓ com o
# arquivo versionado; fixture nova com segredo real continua bloqueada (o gate é calibrado, não desligado).
mkdir -p "$T/fx/scripts" "$T/fx/tests" "$T/fx/.adas" && cd "$T/fx" && git init -q && git config user.email t@t && git config user.name t \
  && cp "$CS" scripts/ && echo "hdr = '$bz'" > tests/fixture.test.js && git add -A && git commit -qm fixture
bash scripts/check-secrets.sh >/dev/null 2>&1 && { echo "✗ Bearer sem marca de fixture e sem allowlist passou (porta 2)"; exit 1; }
printf 'tests/fixture.test.js | token de teste, sem valor real | 2026-09-06\n' > .adas/secrets-allowlist
bash scripts/check-secrets.sh >/dev/null 2>&1 || { echo "✗ allowlist declarada não isentou a fixture"; exit 1; }
echo "hdr = 'Bearer test-secret-token'" > tests/fict.test.js && git add -A && git commit -qm fict
bash scripts/check-secrets.sh >/dev/null 2>&1 || { echo "✗ valor que se declara fixture ('Bearer test-secret-token') bloqueou (peneira de valor)"; exit 1; }
echo "tk='$tk'" > tests/nova.test.js && git add -A && git commit -qm nova
bash scripts/check-secrets.sh >/dev/null 2>&1 && { echo "✗ segredo em fixture NOVA passou com allowlist (gate desligado)"; exit 1; }
# porta 2 por NOME (*.env no histórico): a allowlist isenta o caminho declarado, e SÓ ele (task 20260925-031:
# systemd/sombra.env, EnvironmentFile sem segredo, bloqueava o histórico todo sem a isenção valer ali).
mkdir -p "$T/ev/scripts" "$T/ev/.adas" && cd "$T/ev" && git init -q && git config user.email t@t && git config user.name t \
  && cp "$CS" scripts/ && echo "X_BASE=/tmp" > unit.env && git add -A && git commit -qm env
bash scripts/check-secrets.sh >/dev/null 2>&1 && { echo "✗ *.env no histórico sem allowlist passou (porta 2)"; exit 1; }
printf 'unit.env | EnvironmentFile só com caminho | 2026-09-25\n' > .adas/secrets-allowlist
bash scripts/check-secrets.sh >/dev/null 2>&1 || { echo "✗ allowlist declarada não isentou o *.env no histórico"; exit 1; }
echo "X=1" > outro.env && git add -A && git commit -qm outro
bash scripts/check-secrets.sh >/dev/null 2>&1 && { echo "✗ *.env NOVO no histórico passou com allowlist de outro caminho"; exit 1; }
echo "✓ check-secrets bloqueia token (GitHub e bot Telegram, com e sem git), passa repo limpo, e a allowlist isenta só o caminho declarado"
