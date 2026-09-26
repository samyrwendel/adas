#!/usr/bin/env bash
# check-secrets --dominio (DA-005 do repo adas): arquivo/job de um domínio que lê a credencial
# de OUTRO domínio reprova; comentário e `unset` passam; sem regra declarada, passa. HOME falso,
# crontab falso no PATH — nada toca a máquina real.
set -uo pipefail
CHK="${CHK:-$(cd "$(dirname "$0")/.." && pwd)/check-secrets.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; mkdir -p "$H/fin" "$H/.adas" "$H/.config/systemd/user" "$T/bin"
ENVP='channels/telegram/\.env|BOT_TOKEN_PRINCIPAL'
printf '~/fin/** | %s | fixture: financeiro sem o token principal\n' "$ENVP" > "$H/.adas/credencial-dominio.conf"
printf '#!/bin/sh\necho ""\n' > "$T/bin/crontab"; chmod +x "$T/bin/crontab"
fail=0
run() { HOME="$H" PATH="$T/bin:$PATH" bash "$CHK" --dominio 2>&1; }
caso() { # <esperado 0|1> <rótulo>
  local out rc; out="$(run)"; rc=$?
  if [ "$rc" = "$1" ]; then echo "✓ $2 (exit $rc)"; else echo "✗ $2: esperava exit $1, veio $rc"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1; fi
}

printf '#!/bin/sh\n# antes: source ~/.claude/channels/telegram/.env\nunset BOT_TOKEN_PRINCIPAL\necho ok\n' > "$H/fin/runner.sh"
caso 0 "comentário + unset (o runner já contido) passa"

printf '#!/bin/sh\nset -a; . ~/.claude/channels/telegram/.env\n' > "$H/fin/alerta.sh"
caso 1 "source do .env principal num caminho financeiro reprova"
rm "$H/fin/alerta.sh"

printf '[Service]\nEnvironmentFile=%%h/.claude/channels/telegram/.env\nExecStart=/bin/sh %s/fin/runner.sh\n' "$H" > "$H/.config/systemd/user/fin.service"
caso 1 "unit que executa arquivo de domínio com EnvironmentFile do token principal reprova"
printf '[Service]\nExecStart=/bin/sh %s/fin/runner.sh\n' "$H" > "$H/.config/systemd/user/fin.service"
caso 0 "a mesma unit sem a credencial no ambiente passa"

printf '#!/bin/sh\necho "0 9 * * * . ~/.claude/channels/telegram/.env && %s/fin/runner.sh"\n' "$H" > "$T/bin/crontab"
caso 1 "cron que carrega o .env principal antes do arquivo de domínio reprova"
printf '#!/bin/sh\necho "0 9 * * * %s/fin/runner.sh"\n' "$H" > "$T/bin/crontab"
caso 0 "cron limpo passa"

rm "$H/.adas/credencial-dominio.conf"
printf '#!/bin/sh\n. ~/.claude/channels/telegram/.env\n' > "$H/fin/alerta.sh"
caso 0 "sem regra declarada, o modo não inventa proibição"

[ "$fail" = 0 ] && echo "TODOS OK" || echo "FALHOU"
exit $fail
