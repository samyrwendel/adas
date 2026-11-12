#!/usr/bin/env bash
# adas sync — leva os scripts do produto (skeleton*/scripts/) às casas e carimba a cópia (Fase 3a, parecer 006).
#   adas sync <casa>... [--force] [--geracao skeleton|skeleton-v4]   copia e grava <casa>/.adas/skeleton.lock
#   adas sync --all [--force]                                          todas as casas do repos.conf
#   adas sync --check [<casa>...|--all]                                só confere o lock; rc 1 se cópia fora do hash
# O lock guarda geração, versão, commit e o sha256 de cada arquivo; o check-adas.sh da casa reprova arquivo fora
# do hash (cópia editada à mão = FAIL, decisão do dono msg 13512). Mesmo desenho do sync-hooks.sh da frota: cópia
# editada na casa (hash ≠ lock, ou sem lock e ≠ toda versão que o produto já teve) NÃO é sobrescrita sem --force —
# traga a mudança pro produto primeiro; trava própria da casa vai em scripts/check-local.sh, que o sync nunca toca.
# Recusa é por casa e atômica: nada muda nela. Na 1ª vez grava .adas/ficha-desde (corte do contrato da DA, R5 da
# revisão 018, e a âncora `ultima: DA-NNN`): DA anterior ao sync não ganha aviso. A geração (skeleton/skeleton-v4) fica no lock e não muda
# sem --force. repos.conf: $ADAS_REPOS_CONF ou ~/.claude/adas/repos.conf.
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CONF="${ADAS_REPOS_CONF:-$HOME/.claude/adas/repos.conf}"
FICHA_PADRAO=2026-11-13   # o mesmo padrão do da-index.sh (ficha_check): corte nunca antes dele
MODE=sync; FORCE=0; ALL=0; GER=""; CASAS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --force) FORCE=1 ;;
    --all) ALL=1 ;;
    --geracao) shift; GER="${1:-}" ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "adas sync: flag desconhecida: $1" >&2; exit 2 ;;
    *) CASAS+=("$1") ;;
  esac; shift
done
case "$GER" in ''|skeleton|skeleton-v4) ;; *) echo "adas sync: --geracao é skeleton ou skeleton-v4" >&2; exit 2 ;; esac
if [ "$ALL" = 1 ]; then
  [ -f "$CONF" ] || { echo "adas sync: sem $CONF (uma casa por linha)" >&2; exit 2; }
  while IFS= read -r l; do case "$l" in ''|\#*) ;; *) CASAS+=("$l") ;; esac; done < "$CONF"
fi
[ "${#CASAS[@]}" -gt 0 ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

VER="$(cat "$ROOT/VERSION")"
COMMIT="$(git -C "$ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo nao-registrada)"
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
# historico <arquivo> — rc 0 se o conteúdo é um blob do histórico do produto (alcançável do HEAD; stash e objeto solto
# não contam). Sem lock, é isso que separa cópia ATRASADA (nunca editada, só velha) de cópia EDITADA na casa.
BLOBS=""
historico() {
  if [ -z "$BLOBS" ]; then
    BLOBS="$(mktemp)"; trap 'rm -f "$BLOBS"' EXIT
    git -C "$ROOT" rev-list --objects HEAD 2>/dev/null | cut -d' ' -f1 | sort -u > "$BLOBS"
  fi
  grep -qxF "$(git hash-object "$1" 2>/dev/null)" "$BLOBS"
}
lock_sha() { awk -F'\t' -v a="$2" '!/^#/ && $2==a {print $1; exit}' "$1" 2>/dev/null; }

confere() {  # confere <casa> — rc 1 se algum arquivo do lock está fora do hash
  local c="$1" L="$1/.adas/skeleton.lock" s a ruins=0 velhos=0 ger
  [ -d "$c" ] || { echo "✗ $c: não existe (tire do repos.conf)"; return 1; }
  if [ -d "$c/skeleton/scripts" ] && [ -f "$c/host/adas-sync.sh" ]; then echo "• $c: é o produto ADAS — não recebe sync"; return 0; fi
  [ -f "$L" ] || { echo "• $c: sem lock (ainda não sincronizada) — rode: adas sync $c"; return 0; }
  ger="$(sed -n 's/^# geracao: //p' "$L" | head -1)"
  while IFS=$'\t' read -r s a; do
    case "$s" in ''|\#*) continue;; esac
    if [ "$(sha "$c/scripts/$a")" != "$s" ]; then echo "  ✗ $c/scripts/$a fora do hash (editado à mão)"; ruins=$((ruins+1))
    elif [ "$(sha "$ROOT/${ger:-skeleton}/scripts/$a")" != "$s" ]; then velhos=$((velhos+1)); fi
  done < "$L"
  if [ "$ruins" -gt 0 ]; then echo "✗ $c: $ruins arquivo(s) fora do hash — edite no produto e rode adas sync"; return 1; fi
  echo "✓ $c: lock $(sed -n 's/^# versao: //p' "$L" | head -1) (${ger:-skeleton}), 0 arquivo fora do hash$([ "$velhos" -gt 0 ] && echo " · $velhos atrás do produto — rode: adas sync $c")"
}

sincroniza() {  # sincroniza <casa>
  local c="$1" L="$1/.adas/skeleton.lock" g src f a cur novo old ruins=() lockger
  [ -d "$c" ] || { echo "✗ $c: não existe"; return 1; }
  if [ -d "$c/skeleton/scripts" ] && [ -f "$c/host/adas-sync.sh" ]; then echo "✗ $c: é o produto ADAS (fonte dos scripts) — não é casa; nada mudou"; return 1; fi
  lockger="$(sed -n 's/^# geracao: //p' "$L" 2>/dev/null | head -1)"
  g="${GER:-${lockger:-skeleton}}"
  if [ -n "$lockger" ] && [ "$g" != "$lockger" ] && [ "$FORCE" = 0 ]; then
    echo "✗ $c: lock é da geração $lockger, pedido $g — trocar de geração exige --force (nada mudou)"; return 1
  fi
  src="$ROOT/$g/scripts"
  for f in "$src"/*; do
    [ -f "$f" ] || continue; a="$(basename "$f")"
    [ -f "$c/scripts/$a" ] || continue
    cur="$(sha "$c/scripts/$a")"; novo="$(sha "$f")"
    [ "$cur" = "$novo" ] && continue
    old="$(lock_sha "$L" "$a")"
    [ -n "$old" ] && [ "$cur" = "$old" ] && continue   # cópia intacta, só atrás do produto
    [ -z "$old" ] && historico "$c/scripts/$a" && continue   # 1º sync: cópia = versão antiga do produto (B5, revisão 020)
    ruins+=("$a")
  done
  if [ "${#ruins[@]}" -gt 0 ] && [ "$FORCE" = 0 ]; then
    echo "✗ $c: cópia editada na casa (↑ casa à frente do carimbo) — traga a mudança pro produto ($g/scripts) ou use --force. Nada mudou:"
    for a in "${ruins[@]}"; do echo "    $a  ($(diff "$src/$a" "$c/scripts/$a" | grep -c '^[<>]') linha(s) diferentes)"; done
    return 1
  fi
  mkdir -p "$c/scripts" "$c/.adas" || return 1
  local st="$c/.adas/sync-estagio.$$"; rm -rf "$st"; mkdir "$st" || return 1
  for f in "$src"/*; do   # 1º tempo: tudo para o estágio; falha aqui = nada mudou na casa
    [ -f "$f" ] || continue; a="$(basename "$f")"
    [ -d "$c/scripts/$a" ] && { echo "✗ $c: scripts/$a é diretório — nada mudou" >&2; rm -rf "$st"; return 1; }
    cp -p "$f" "$st/$a" || { echo "✗ $c: falhou copiando $a — nada mudou" >&2; rm -rf "$st"; return 1; }
  done
  { echo "# adas skeleton.lock — gerado por 'adas sync'; NÃO edite (nem os scripts listados: edite no produto)"
    echo "# geracao: $g"; echo "# versao: $VER"; echo "# commit: $COMMIT"
    for f in "$st"/*; do a="$(basename "$f")"; printf '%s\t%s\n' "$(sha "$f")" "$a"; done
  } > "$L.tmp" || { rm -rf "$st" "$L.tmp"; return 1; }
  for f in "$st"/*; do mv "$f" "$c/scripts/$(basename "$f")" || { echo "✗ $c: falhou movendo $(basename "$f") — rode de novo" >&2; rm -rf "$st" "$L.tmp"; return 1; }; done
  rmdir "$st"; mv "$L.tmp" "$L" || return 1
  echo "$COMMIT" > "$c/.adas/skeleton-version"
  if [ ! -s "$c/.adas/ficha-desde" ]; then
    local d; d="$(date +%F)"; [[ "$d" < "$FICHA_PADRAO" ]] && d="$FICHA_PADRAO"
    { echo "$d"; u="$(grep -oE '^## DA-[0-9]+[a-z]?' "$c/DECISIONS.md" 2>/dev/null | tail -1)"; [ -n "$u" ] && echo "ultima: ${u#\#\# }"; } > "$c/.adas/ficha-desde"
  fi
  echo "✓ $c: $(grep -vc '^#' "$L") arquivo(s) de $g $VER ($COMMIT)$([ "${#ruins[@]}" -gt 0 ] && echo " — --force sobrescreveu: ${ruins[*]}")"
}

rc=0
for c in "${CASAS[@]}"; do
  c="${c%/}"
  if [ "$MODE" = check ]; then confere "$c" || rc=1; else sincroniza "$c" || rc=1; fi
done
exit "$rc"
