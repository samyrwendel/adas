#!/usr/bin/env bash
# install-selftest.sh — instala o adas-selftest.timer (systemd --user): roda `adas test --selftest` 1×/dia,
# grava ~/.adas/selftest.status e alerta só na transição verde↔vermelho. Cron mecânico, sem LLM (DA-009).
# Chamado pelo install.sh; roda sozinho também (idempotente). Sem systemd --user (macOS etc.): avisa e sai 0.
# Canal do alerta: ADAS_ALERT_CMD em ~/.claude/adas/selftest.env (opcional; sem ele o alerta vai pro journal).
# Desligar: systemctl --user disable --now adas-selftest.timer
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
U="$HOME/.config/systemd/user"
systemctl --user show-environment >/dev/null 2>&1 || { echo "• sem systemd --user — adas-selftest.timer não instalado (rode adas test --selftest no seu agendador)"; exit 0; }
# o systemd --user lê as units da home REAL; com HOME de fixture (smoke) a unit escrita aqui nunca seria vista
real_home="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)"
if [ -n "$real_home" ] && [ "$(cd "$HOME" && pwd -P)" != "$(cd "$real_home" 2>/dev/null && pwd -P)" ]; then
  echo "• HOME ($HOME) não é a home do usuário — adas-selftest.timer não instalado"; exit 0
fi
mkdir -p "$U"
cat > "$U/adas-selftest.service" <<EOF
[Unit]
Description=ADAS selftest — roda todas as suítes do ADAS e alerta na transição verde↔vermelho

[Service]
Type=oneshot
ExecStart=/bin/bash $DIR/adas-test.sh --selftest
EnvironmentFile=-%h/.claude/adas/selftest.env
TimeoutStartSec=600
Nice=10
NoNewPrivileges=yes
EOF
cat > "$U/adas-selftest.timer" <<'EOF'
[Unit]
Description=ADAS selftest diário (relógio do ADAS)

[Timer]
OnCalendar=*-*-* 06:40:00
Persistent=true
AccuracySec=5min

[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now adas-selftest.timer >/dev/null
echo "✓ adas-selftest.timer ativo (diário 06:40; status em ~/.adas/selftest.status)"
