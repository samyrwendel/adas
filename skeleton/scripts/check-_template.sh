#!/usr/bin/env bash
# check-<nome> — FAIXA EXECUTÁVEL (ADAS PASSO 7). Padrão nascido no GroupPay.
# Transforma um NÃO-FAÇA crítico de uma faixa num teste rodável: sai != 0 quando VIOLA.
# O hook injeta a regra no MOMENTO da edição; este check pega no COMMIT/DEPLOY (as duas pontas).
#
#   Procedência: DA-<NNN> · faixa .claude/skills/<faixa>/SKILL.md
#   Severidade:  SEVERITY=block → falha o build (caminho do dinheiro/segurança)
#                SEVERITY=warn  → só avisa, não bloqueia (limpeza/estilo)
#   Uso:         SEVERITY=block bash scripts/check-<nome>.sh
#   Gate:        no package.json → "deploy": "SEVERITY=block bash scripts/check-*.sh && npm run build && <restart>"
set -euo pipefail

SEVERITY="${SEVERITY:-block}"
SRC="${SRC:-src}"
fail=0

# ── EXEMPLO (estilo GroupPay check:dead-buttons): botão/callback sem handler ──────────
# Ajuste os 2 greps pra sua stack (Telegraf/grammY/node-telegram-bot-api, regex de action, etc.).
botoes=$(grep -rhoE "callback_data: *['\"][A-Za-z0-9_:-]+" "$SRC" 2>/dev/null | sed -E "s/.*['\"]//" | sort -u || true)
for b in $botoes; do
  if ! grep -rqE "action\(['\"/]?${b}|case ['\"]${b}['\"]|'${b}'|\"${b}\"" "$SRC" 2>/dev/null; then
    echo "✗ callback '${b}' sem handler — adicione o handler ou remova o botão"
    fail=1
  fi
done

# ── OUTRO EXEMPLO (caminho do dinheiro): nunca misturar unidade/moeda ─────────────────
# if grep -rqE "price_brl_cents.*plano *USD|usd.*brl_cents" "$SRC" 2>/dev/null; then
#   echo "✗ mistura de moeda (BRL cents em contexto USD) — normalize a unidade antes"
#   fail=1
# fi

# ── Veredito ─────────────────────────────────────────────────────────────────────────
if [ "$fail" -ne 0 ]; then
  if [ "$SEVERITY" = "block" ]; then echo "GATE bloqueado (money-path/segurança) — corrija antes do deploy"; exit 1; fi
  echo "GATE: aviso (não bloqueia)"; exit 0
fi
echo "✓ check-<nome> ok"
