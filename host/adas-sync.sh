#!/usr/bin/env bash
# adas sync — leva os scripts do produto (skeleton*/scripts/) às casas e carimba a cópia (Fase 3a, parecer 006).
#   adas sync <casa>... [--force] [--geracao skeleton|skeleton-v4] [--diario skeleton]   copia e grava <casa>/.adas/skeleton.lock
#   adas sync --all [--force]                                          todas as casas do repos.conf
#   adas sync --check [<casa>...|--all]                                só confere o lock; rc 1 se cópia fora do hash
# O lock guarda geração, versão, commit e o sha256 de cada arquivo; o check-adas.sh da casa reprova arquivo fora
# do hash (cópia editada à mão = FAIL, decisão do dono msg 13512). Mesmo desenho do sync-hooks.sh da frota: cópia
# editada na casa (hash ≠ lock, ou sem lock e ≠ toda versão que o produto já teve) NÃO é sobrescrita sem --force —
# traga a mudança pro produto primeiro; trava própria da casa vai em scripts/check-local.sh, que o sync nunca toca.
# Recusa é por casa e atômica: nada muda nela. Na 1ª vez grava .adas/ficha-desde (corte do contrato da DA, R5 da
# revisão 018, e a âncora `ultima: DA-NNN`): DA anterior ao sync não ganha aviso. A geração (skeleton/skeleton-v4) fica no lock e não muda
# sem --force. repos.conf: $ADAS_REPOS_CONF ou ~/.claude/adas/repos.conf.
# Teste que o produto escreve para um script que ele leva viaja junto (revisão 025): em casa que tem mecanismo/tests/,
# os arquivos de <geração>/mecanismo/tests/ entram no sync e no lock como `../mecanismo/tests/<nome>` (o nome do lock é
# relativo a scripts/, então o check-adas.sh da casa confere o hash sem mudar). Teste próprio da casa, ali, fica intocado.
# Casa híbrida (parecer 028): `--geracao skeleton-v4 --diario skeleton` traz o diário (da-index.sh, da-new.sh,
# da-draft-head.py, da-schema.tsv) de skeleton/scripts e o resto de skeleton-v4; o lock grava `# diario: skeleton`.
# 1º sync de casa v4 cujo da-index.sh é versão do skeleton é recusado até dizer --diario. Quando o check-da-mecanismo.sh
# chega a uma casa que não o tinha, o sync grava .adas/da-mecanismo-desde (hoje) e .adas/da-mecanismo-corte (maior DA):
# o diário de antes vira fila (WARN), não FAIL. host/sync-triados.tsv: cópia editada na casa que o produto já triou
# (trecho subiu ou foi descartado com motivo) conta como versão antiga — sem --force. Linha não commitada nesse
# arquivo carimba '+sujo' (revisão 030). --diario em casa JÁ carimbada sem diário (v4 puro) exige --force.
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CONF="${ADAS_REPOS_CONF:-$HOME/.claude/adas/repos.conf}"
FICHA_PADRAO=2026-11-13   # o mesmo padrão do da-index.sh (ficha_check): corte nunca antes dele
MODE=sync; FORCE=0; ALL=0; GER=""; DIARIO=""; CASAS=()
DIARIO_ARQS=" da-index.sh da-new.sh da-draft-head.py da-schema.tsv "
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --force) FORCE=1 ;;
    --all) ALL=1 ;;
    --geracao) shift; GER="${1:-}" ;;
    --diario) shift; DIARIO="${1:-}" ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "adas sync: flag desconhecida: $1" >&2; exit 2 ;;
    *) CASAS+=("$1") ;;
  esac; shift
done
case "$GER" in ''|skeleton|skeleton-v4) ;; *) echo "adas sync: --geracao é skeleton ou skeleton-v4" >&2; exit 2 ;; esac
case "$DIARIO" in ''|skeleton) ;; *) echo "adas sync: --diario só aceita skeleton" >&2; exit 2 ;; esac
if [ "$ALL" = 1 ]; then
  [ -f "$CONF" ] || { echo "adas sync: sem $CONF (uma casa por linha)" >&2; exit 2; }
  while IFS= read -r l; do case "$l" in ''|\#*) ;; *) CASAS+=("$l") ;; esac; done < "$CONF"
fi
[ "${#CASAS[@]}" -gt 0 ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

VER="$(cat "$ROOT/VERSION")"
COMMIT="$(git -C "$ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo nao-registrada)"
if [ "$MODE" = sync ] && [ -n "$(git -C "$ROOT" status --porcelain -- skeleton/scripts skeleton-v4/scripts skeleton-v4/mecanismo/tests host/sync-triados.tsv 2>/dev/null)" ]; then
  COMMIT="$COMMIT+sujo"; echo "⚠ adas sync: o produto tem mudança NÃO commitada em skeleton*/scripts, mecanismo/tests ou host/sync-triados.tsv — o carimbo sai '$COMMIT'; commite antes de levar às casas" >&2
fi
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
# historico <geração> <nome> <arquivo> — rc 0 se o conteúdo é uma versão que ESSE arquivo já teve no produto: blob de
# <geração>/scripts/<nome> em commit alcançável do HEAD (stash e objeto solto não contam; blob de OUTRO caminho ou da
# outra geração também não — revisão 022). Sem lock, é isso que separa cópia ATRASADA (só velha) de cópia EDITADA.
BLOBS=""
historico() {
  if [ -z "$BLOBS" ]; then
    BLOBS="$(mktemp)"; trap 'rm -f "$BLOBS"' EXIT
    git -C "$ROOT" log --format= --raw --no-abbrev --no-renames -m HEAD -- skeleton/scripts skeleton-v4/scripts skeleton-v4/mecanismo/tests 2>/dev/null \
      | awk -F'\t' '/^:/ {split($1, m, " "); print m[4] " " $2}' | sort -u > "$BLOBS"
    awk -F'\t' '!/^#/ && NF >= 2 {print $1 " " $2}' "$ROOT/host/sync-triados.tsv" >> "$BLOBS" 2>/dev/null
  fi
  grep -qxF "$(git hash-object --no-filters "$3" 2>/dev/null) $1/$(na_casa "$2")" "$BLOBS"
}
na_casa() { case "$1" in ../*) echo "${1#../}" ;; *) echo "scripts/$1" ;; esac; }   # nome do lock → caminho na casa (e, sob a geração, no produto)
e_diario() { [[ "$DIARIO_ARQS" == *" $1 "* ]]; }
origem() { if [ -n "$dia" ] && e_diario "$1"; then echo "$dia"; else echo "$g"; fi; }   # geração de onde vem o item (lê $g/$dia do chamador)
itens() {  # itens <geração> <casa> [<diário>] — nomes do lock (relativos a scripts/): os scripts e, em casa com mecanismo/tests/, os testes do produto
  local f
  for f in "$ROOT/$1/scripts"/*; do [ -f "$f" ] && { [ -n "${3:-}" ] && e_diario "$(basename "$f")" || basename "$f"; }; done
  [ -n "${3:-}" ] && for f in $DIARIO_ARQS; do [ -f "$ROOT/$3/scripts/$f" ] && echo "$f"; done
  [ -d "$2/mecanismo/tests" ] || return 0
  for f in "$ROOT/$1/mecanismo/tests"/*; do [ -f "$f" ] && echo "../mecanismo/tests/$(basename "$f")"; done
  return 0
}
lock_sha() { awk -F'\t' -v a="$2" '!/^#/ && $2==a {print $1; exit}' "$1" 2>/dev/null; }

confere() {  # confere <casa> — rc 1 se algum arquivo do lock está fora do hash
  local c="$1" L="$1/.adas/skeleton.lock" s a ruins=0 velhos=0 g dia
  [ -d "$c" ] || { echo "✗ $c: não existe (tire do repos.conf)"; return 1; }
  if [ -d "$c/skeleton/scripts" ] && [ -f "$c/host/adas-sync.sh" ]; then echo "• $c: é o produto ADAS — não recebe sync"; return 0; fi
  [ -f "$L" ] || { echo "• $c: sem lock (ainda não sincronizada) — rode: adas sync $c"; return 0; }
  g="$(sed -n 's/^# geracao: //p' "$L" | head -1)"; g="${g:-skeleton}"; dia="$(sed -n 's/^# diario: //p' "$L" | head -1)"
  while IFS=$'\t' read -r s a; do
    case "$s" in ''|\#*) continue;; esac
    if [ "$(sha "$c/scripts/$a")" != "$s" ]; then echo "  ✗ $c/scripts/$a fora do hash (editado à mão)"; ruins=$((ruins+1))
    elif [ "$(sha "$ROOT/$(origem "$a")/scripts/$a")" != "$s" ]; then velhos=$((velhos+1)); fi
  done < "$L"
  if [ "$ruins" -gt 0 ]; then echo "✗ $c: $ruins arquivo(s) fora do hash — edite no produto e rode adas sync"; return 1; fi
  echo "✓ $c: lock $(sed -n 's/^# versao: //p' "$L" | head -1) ($g${dia:+ + diário $dia}), 0 arquivo fora do hash$([ "$velhos" -gt 0 ] && echo " · $velhos atrás do produto — rode: adas sync $c")"
}

sincroniza() {  # sincroniza <casa>
  local c="$1" L="$1/.adas/skeleton.lock" g dia f a cur novo old ruins=() lockger lockdia its=() i tinha_mec=0
  [ -d "$c" ] || { echo "✗ $c: não existe"; return 1; }
  if [ -d "$c/skeleton/scripts" ] && [ -f "$c/host/adas-sync.sh" ]; then echo "✗ $c: é o produto ADAS (fonte dos scripts) — não é casa; nada mudou"; return 1; fi
  lockger="$(sed -n 's/^# geracao: //p' "$L" 2>/dev/null | head -1)"
  if [ -z "$lockger" ] && [ -z "$GER" ] && { [ -f "$c/scripts/check-mecanismo.sh" ] || [ -f "$c/scripts/adas-init.sh" ]; }; then
    echo "✗ $c: sem lock e com cara de skeleton-v4 (tem scripts/check-mecanismo.sh ou adas-init.sh) — diga a geração: adas sync --geracao skeleton-v4 $c (nada mudou)"; return 1
  fi
  g="${GER:-${lockger:-skeleton}}"
  if [ -n "$lockger" ] && [ "$g" != "$lockger" ] && [ "$FORCE" = 0 ]; then
    echo "✗ $c: lock é da geração $lockger, pedido $g — trocar de geração exige --force (nada mudou)"; return 1
  fi
  lockdia="$(sed -n 's/^# diario: //p' "$L" 2>/dev/null | head -1)"; dia="${DIARIO:-$lockdia}"
  if [ -n "$dia" ] && [ "$g" != skeleton-v4 ]; then echo "✗ $c: --diario só vale com a geração skeleton-v4 (pedido $g) — nada mudou"; return 1; fi
  if [ -n "$lockger" ] && [ "$dia" != "$lockdia" ] && [ "$FORCE" = 0 ]; then   # revisão 030: mesmo desenho da troca de geração
    echo "✗ $c: lock é de diário ${lockdia:-$lockger (sem --diario)}, pedido $dia — trocar o diário de casa já carimbada exige --force (nada mudou)"; return 1
  fi
  if [ -z "$lockger" ] && [ "$g" = skeleton-v4 ] && [ -z "$dia" ] && [ -f "$c/scripts/da-index.sh" ] && historico skeleton da-index.sh "$c/scripts/da-index.sh"; then
    echo "✗ $c: casa v4 com o da-index.sh do skeleton (diário híbrido) — o v4 puro quebraria o diário; diga: adas sync --geracao skeleton-v4 --diario skeleton $c (nada mudou)"; return 1
  fi
  [ -f "$c/scripts/check-da-mecanismo.sh" ] && tinha_mec=1
  mapfile -t its < <(itens "$g" "$c" "$dia")
  for a in "${its[@]}"; do
    f="$ROOT/$(origem "$a")/scripts/$a"
    [ -f "$c/scripts/$a" ] || continue
    cur="$(sha "$c/scripts/$a")"; novo="$(sha "$f")"
    [ "$cur" = "$novo" ] && continue
    old="$(lock_sha "$L" "$a")"
    [ -n "$old" ] && [ "$cur" = "$old" ] && continue   # cópia intacta, só atrás do produto
    [ -z "$old" ] && historico "$(origem "$a")" "$a" "$c/scripts/$a" && continue   # 1º sync: cópia = versão antiga do produto (B5, revisão 020)
    ruins+=("$a")
  done
  if [ "${#ruins[@]}" -gt 0 ] && [ "$FORCE" = 0 ]; then
    echo "✗ $c: cópia editada na casa (↑ casa à frente do carimbo) — traga a mudança pro produto ($g/scripts${dia:+, diário de $dia/scripts}) ou use --force. Nada mudou:"
    for a in "${ruins[@]}"; do echo "    $a  ($(diff "$ROOT/$(origem "$a")/scripts/$a" "$c/scripts/$a" | grep -c '^[<>]') linha(s) diferentes)"; done
    return 1
  fi
  if [ "${#ruins[@]}" -gt 0 ]; then   # --force sobre edição NÃO commitada não tem volta (o git da casa não guarda) — revisão 022
    local sujos=()
    for a in "${ruins[@]}"; do
      git -C "$c" ls-files --error-unmatch "$(na_casa "$a")" >/dev/null 2>&1 && ! git -C "$c" diff --quiet HEAD -- "$(na_casa "$a")" 2>/dev/null && sujos+=("$a")
    done
    if [ "${#sujos[@]}" -gt 0 ]; then
      echo "✗ $c: --force apagaria edição NÃO commitada, sem volta: ${sujos[*]} — commite, ou descarte de propósito (git -C $c checkout -- scripts/<arquivo>) e rode de novo. Nada mudou"; return 1
    fi
  fi
  mkdir -p "$c/scripts" "$c/.adas" || return 1
  local st="$c/.adas/sync-estagio.$$"; rm -rf "$st"; mkdir "$st" || return 1
  i=0
  for a in "${its[@]}"; do   # 1º tempo: tudo para o estágio (arquivo N = item N); falha aqui = nada mudou na casa
    [ -d "$c/scripts/$a" ] && { echo "✗ $c: scripts/$a é diretório — nada mudou" >&2; rm -rf "$st"; return 1; }
    cp -p "$ROOT/$(origem "$a")/scripts/$a" "$st/$i" || { echo "✗ $c: falhou copiando $a — nada mudou" >&2; rm -rf "$st"; return 1; }
    i=$((i+1))
  done
  { echo "# adas skeleton.lock — gerado por 'adas sync'; NÃO edite (nem os scripts listados: edite no produto)"
    echo "# geracao: $g"; [ -n "$dia" ] && echo "# diario: $dia"; echo "# versao: $VER"; echo "# commit: $COMMIT"
    i=0; for a in "${its[@]}"; do printf '%s\t%s\n' "$(sha "$st/$i")" "$a"; i=$((i+1)); done
  } > "$L.tmp" || { rm -rf "$st" "$L.tmp"; return 1; }
  i=0; for a in "${its[@]}"; do mv "$st/$i" "$c/scripts/$a" || { echo "✗ $c: falhou movendo $a — rode de novo" >&2; rm -rf "$st" "$L.tmp"; return 1; }; i=$((i+1)); done
  rmdir "$st"; mv "$L.tmp" "$L" || return 1
  echo "$COMMIT" > "$c/.adas/skeleton-version"
  if [ ! -s "$c/.adas/ficha-desde" ]; then
    local d; d="$(date +%F)"; [[ "$d" < "$FICHA_PADRAO" ]] && d="$FICHA_PADRAO"
    { echo "$d"; u="$(grep -oE '^## DA-[0-9]+[a-z]?' "$c/DECISIONS.md" 2>/dev/null | tail -1)"; [ -n "$u" ] && echo "ultima: ${u#\#\# }"; } > "$c/.adas/ficha-desde"
  fi
  if [ "$tinha_mec" = 0 ] && [ -f "$c/scripts/check-da-mecanismo.sh" ] && [ ! -s "$c/.adas/da-mecanismo-desde" ]; then
    date +%F > "$c/.adas/da-mecanismo-desde"
    u="$(grep -oE '^## (Decisão Arquitetural )?DA-[0-9]+' "$c/DECISIONS.md" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1)"
    [ -n "$u" ] && [ ! -s "$c/.adas/da-mecanismo-corte" ] && echo "$((10#$u))" > "$c/.adas/da-mecanismo-corte"
  fi
  echo "✓ $c: $(grep -vc '^#' "$L") arquivo(s) de $g${dia:+ + diário $dia} $VER ($COMMIT)$([ "${#ruins[@]}" -gt 0 ] && echo " — --force sobrescreveu: ${ruins[*]}")"
}

rc=0
for c in "${CASAS[@]}"; do
  c="${c%/}"
  if [ "$MODE" = check ]; then confere "$c" || rc=1; else sincroniza "$c" || rc=1; fi
done
exit "$rc"
