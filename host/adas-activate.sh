#!/usr/bin/env bash
# ADAS host — SessionStart (matcher: startup|resume|clear|compact). Reinjeta o núcleo do repo na
# FRONTEIRA de contexto (pós-compaction/clear/resume — onde o "leia o ADAS.md" do turno 1 evapora).
# Neste evento, stdout cru vira contexto — MAS o harness persiste (não entrega) stdout > 10 KiB,
# então a emissão respeita ADAS_EMIT_BUDGET (ver adas-lib.sh). Fail-open: qualquer erro sai 0 em silêncio.
DIR="$(dirname "$0")"
. "$DIR/adas-lib.sh" 2>/dev/null || exit 0

payload="$(timeout 1 cat 2>/dev/null || true)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"

# efeito colateral: marca a sessão ativa quando o cwd cai num repo governado
repo="$(adas_resolve "$cwd")"
if [ -n "$repo" ]; then
  mkdir -p "$HOME/.claude/adas" 2>/dev/null || true
  printf '{"mode":"full","session_id":"%s","ts":"%s","repo":"%s"}\n' "$sid" "$(date -Is 2>/dev/null)" "$repo" \
    > "$HOME/.claude/adas/$(basename "$repo").active" 2>/dev/null || true
fi

# emissão (núcleo + camada 0) dentro do orçamento de bytes — o que não couber vira ponteiro [ADAS-CORTE]
adas_session_emit "$cwd" 2>/dev/null || true
exit 0
