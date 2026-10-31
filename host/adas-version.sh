#!/usr/bin/env bash
# adas-version.sh — aviso de versão nova do ADAS (SessionStart, via adas-activate.sh).
#
# No máximo 1 consulta por dia (cache em ~/.adas/version-check), timeout curto, mudo sem rede.
# Compara a versão INSTALADA (~/.claude/adas/VERSION, gravada pelo install.sh) com a última
# publicada (primeiro "## X.Y.Z" do CHANGELOG.md da main, pela URL pública, sem token). Se houver
# nova, imprime UMA linha:
#   ADAS 1.1.0 disponível (instalado 1.0.0): <Resumo: do changelog>. Atualizar: bash <clone>/host/update.sh
# Env: ADAS_VERSION_CHECK=off (desliga) · ADAS_VERSION_URL (fonte do changelog; aceita file://)
#      ADAS_VERSION_CACHE · ADAS_VERSION_INSTALLED (arquivo com a versão instalada) · ADAS_VERSION_TTL (s, 86400)
[ "${ADAS_VERSION_CHECK:-on}" = "off" ] && exit 0
URL="${ADAS_VERSION_URL:-https://raw.githubusercontent.com/samyrwendel/adas/main/CHANGELOG.md}"
CACHE="${ADAS_VERSION_CACHE:-$HOME/.adas/version-check}"
INST_F="${ADAS_VERSION_INSTALLED:-$HOME/.claude/adas/VERSION}"
TTL="${ADAS_VERSION_TTL:-86400}"
SRC="$(cat "$HOME/.claude/adas/source" 2>/dev/null || echo "$HOME/adas")"

inst="$(tr -d '[:space:]' < "$INST_F" 2>/dev/null)"
[ -n "$inst" ] || exit 0

now=$(date +%s)
latest=""; resumo=""
if [ -f "$CACHE" ]; then
  IFS=$'\t' read -r ts latest resumo < "$CACHE" 2>/dev/null || true
  [ -n "${ts:-}" ] && [ $((now - ts)) -lt "$TTL" ] || latest=""
fi
if [ -z "$latest" ]; then
  body="$(curl -fsS -m 3 "$URL" 2>/dev/null | head -c 20000)" || exit 0
  latest="$(printf '%s\n' "$body" | sed -n 's/^## \([0-9][0-9.]*\).*/\1/p' | head -1)"
  [ -n "$latest" ] || exit 0
  resumo="$(printf '%s\n' "$body" | awk -v v="$latest" '
    $0 ~ "^## "v { on=1; next } on && /^## / { exit } on && /^Resumo:/ { sub(/^Resumo:[ ]*/, ""); print; exit }')"
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null
  printf '%s\t%s\t%s\n' "$now" "$latest" "$resumo" > "$CACHE" 2>/dev/null || true
fi

resumo="${resumo%.}"
# nova só se latest > inst (sort -V); igual ou mais velha = silêncio
[ "$latest" = "$inst" ] && exit 0
[ "$(printf '%s\n%s\n' "$inst" "$latest" | sort -V | tail -1)" = "$latest" ] || exit 0
echo "ADAS $latest disponível (instalado $inst)${resumo:+: $resumo}. Atualizar: bash $SRC/host/update.sh"
exit 0
