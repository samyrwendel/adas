#!/usr/bin/env bash
# da-new.sh — porta única de escrita do DECISIONS.md (DA-181 §2.2).
#
# flock em ~/.adas/da.lock, snapshot do diário em ~/.adas/snapshots/ ANTES de
# anexar, número = max(DA-NNN existente)+1, esqueleto anexado no FIM do arquivo
# (nunca no meio — é aqui que se evita o vetor da DA-127/DA-012: dois escritores
# ou um Edit por old_string/new_string num arquivo de 1 MB). O agente preenche o
# esqueleto por Edit DEPOIS, dentro da DA recém-criada — nunca em DA anterior.
#
# O esqueleto, a instrução e a ficha SAEM de da-schema.tsv (ao lado deste script), o contrato
# único da DA: este script não conhece nome de campo nenhum (Fase 2, task 20261112-017).
#
# uso: da-new.sh --tipo <tipo> <escopo> <saga> "<título>" [dir]
#      da-new.sh --ajuda        instrução de preenchimento (campos, obrigatoriedade, tetos)
#      da-new.sh --ficha        a ficha em markdown (docs/ficha.md do produto é esta saída)
#   tipo:   um dos valores da etiqueta tipo no esquema (regra · registro · princípio)
#   escopo: produto | instância | projeto/<nome> (composto: "produto,instância")
#   saga:   slug existente em ~/.adas/sagas.conf, ou "nova/<slug>" se for nova
#   dir:    onde vive DECISIONS.md (default: $HOME)
set -uo pipefail

SCHEMA="${ADAS_DA_SCHEMA:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/da-schema.tsv}"
[ -f "$SCHEMA" ] || { echo "✗ da-new: contrato da DA não encontrado: $SCHEMA" >&2; exit 2; }
linhas() { awk -F'\t' '!/^#/ && NF>=9' "$SCHEMA"; }   # onde chave rotulo obrigatorio teto molde default valores ajuda
valores_de() { linhas | awk -F'\t' -v k="$1" '$2==k{print $8; exit}'; }

ajuda() {
  linhas | awk -F'\t' '{ t = ($5 == "-") ? "" : "teto " $5 " · "
    printf "  %s [%s]%s %s%s\n", $3, $4, ($6 == "n" ? " (fora do molde)" : ""), t, $9 }'
}
ficha() {
  echo "# Ficha da DA"
  echo
  echo "Gerada de \`skeleton/scripts/da-schema.tsv\` por \`bash skeleton/scripts/da-new.sh --ficha\` — não edite à mão."
  echo "A ordem das linhas é a ordem da ficha. Teto \`alvo/corte\`: o check avisa só acima do corte."
  echo
  echo "| Campo | Onde | Obrigatório | Teto | No molde | Valores | Como escrever |"
  echo "|---|---|---|---|---|---|---|"
  linhas | awk -F'\t' 'function esc(x,   n, p, i, o) { n = split(x, p, "|"); o = p[1]; for (i = 2; i <= n; i++) o = o "\\|" p[i]; return o }   # barra na célula quebra a tabela
  { $8 = esc($8); $9 = esc($9)
    printf "| %s | %s | %s | %s | %s | %s | %s |\n", ($1=="cab" ? "`" $3 ":`" : "**" $3 ":**"), $1, $4, $5, ($6=="s" ? "sim" : "não"), $8, $9 }'
}
usage() { echo 'uso: da-new.sh --tipo <'"$(valores_de tipo)"'> <escopo> <saga> "<título>" [dir]   ·   da-new.sh --ajuda | --ficha' >&2; exit 2; }

TIPO=""; POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ajuda) ajuda; exit 0 ;;
    --ficha) ficha; exit 0 ;;
    --tipo) TIPO="${2:-}"; shift 2 || usage ;;
    --tipo=*) TIPO="${1#--tipo=}"; shift ;;
    *) POS+=("$1"); shift ;;
  esac
done
[ "${#POS[@]}" -ge 3 ] || usage
if [ -z "$TIPO" ] || [[ "$TIPO" == *"|"* ]] || [[ "|$(valores_de tipo)|" != *"|$TIPO|"* ]]; then
  echo "✗ da-new: --tipo é obrigatório e vale $(valores_de tipo) (veio '${TIPO}')." >&2
  echo "  regra manda ou proíbe; registro é fato (o que foi feito, onde roda) e não vira cartão." >&2
  usage
fi
ESCOPO="${POS[0]}"; SAGA="${POS[1]}"; TITULO="${POS[2]}"; DIR="${POS[3]:-$HOME}"
DEC="$DIR/DECISIONS.md"
[ -f "$DEC" ] || { echo "✗ da-new: $DEC não existe"; exit 2; }

# D-C6 (DA-670, mudança de casa): DA só de projeto nasce no DECISIONS.md do repositório do app, não no do servidor.
# Só trava quando há casa de fato (rota do ~/.adas/rotas.conf com o projeto, DECISIONS.md e scripts/da-new.sh);
# projeto sem repositório próprio segue aqui. Ponteiro 📦 (saga nova/casa-*) é a exceção. Escopo composto (produto/instância + projeto) fica.
if [ "$(readlink -f "$DIR")" = "$(readlink -f "$HOME")" ] && [[ "$SAGA" != nova/casa-* ]]; then
  _so_proj=1; _casa=""
  IFS=',' read -ra _esc <<< "$ESCOPO"
  for _e in "${_esc[@]}"; do
    _e="${_e// /}"
    [[ "$_e" == projeto/* ]] || { _so_proj=0; break; }
    [ -n "$_casa" ] && continue
    while IFS='|' read -r _pre _escs _; do
      [[ "$_pre" == \#* || -z "$_pre" ]] && continue
      [[ ",$_escs," == *",$_e,"* && -f "$_pre/DECISIONS.md" && -f "$_pre/scripts/da-new.sh" ]] && { _casa="$_pre"; break; }
    done < "${ADAS_ROTAS_CONF:-$HOME/.adas/rotas.conf}" 2>/dev/null
  done
  if [ "$_so_proj" = 1 ] && [ -n "$_casa" ]; then
    echo "✗ da-new: DA só de projeto nasce no repositório do app (DA-670). Use: bash $_casa/scripts/da-new.sh $ESCOPO $SAGA '<título>' $_casa" >&2
    echo "  no servidor só o ponteiro 📦 (saga nova/casa-<repo>, tipo registro); DA transversal leva as duas etiquetas (ex.: produto,projeto/x)." >&2
    exit 2
  fi
fi

# ADAS_DIR default segue o [dir] alvo (nunca $HOME) — senão um da-new.sh contra uma cópia de
# teste ainda grava snapshot/lock no ~/.adas/ do servidor real. Produção usa dir=$HOME por
# default, então o comportamento real não muda; só o caso [dir] ≠ $HOME passa a se isolar.
ADAS_DIR="${ADAS_HOME_DIR:-$DIR/.adas}"
mkdir -p "$ADAS_DIR/snapshots" 2>/dev/null || true
LOCK="$ADAS_DIR/da.lock"

# saga tem que existir em sagas.conf (ou vir como nova/<slug>) — slug desconhecido sem esse
# prefixo RECUSA (exit 2) em vez de anexar uma DA com saga fantasma no diário.
SAGAS_CONF="${ADAS_SAGAS_CONF:-$ADAS_DIR/sagas.conf}"
if [ -f "$SAGAS_CONF" ]; then
  IFS=',' read -ra _sg <<< "$SAGA"
  invalid=()
  for sgv in "${_sg[@]}"; do
    [[ "$sgv" == nova/* ]] && continue
    grep -qE "^${sgv}\||[|,]${sgv}(,|\$)" "$SAGAS_CONF" 2>/dev/null || invalid+=("$sgv")
  done
  if [ "${#invalid[@]}" -gt 0 ]; then
    echo "✗ da-new: saga(s) inexistente(s) em $SAGAS_CONF: ${invalid[*]} — use 'nova/<slug>' se for saga nova." >&2
    echo "  slugs válidos:" >&2
    cut -d'|' -f1 "$SAGAS_CONF" 2>/dev/null | grep -vE '^(#|$)' | sed 's/^/    /' >&2
    exit 2
  fi
fi

exec 9>"$LOCK"
flock -w 10 9 || { echo "✗ da-new: não consegui o lock $LOCK em 10s (outro processo escrevendo?)"; exit 1; }

# snapshot ANTES de anexar (achado dos pré-mortems: ~/ não é git — só o snapshot protege)
ts="$(date -u +%Y%m%dT%H%M%SZ)"
cp "$DEC" "$ADAS_DIR/snapshots/DECISIONS.md.$ts" 2>/dev/null || { echo "✗ da-new: snapshot falhou — abortando sem tocar no diário"; exit 1; }
# rotação: mantém só os 30 snapshots mais recentes (nome = timestamp UTC, ordena cronológico)
ls -1 "$ADAS_DIR/snapshots"/DECISIONS.md.* 2>/dev/null | sort | head -n -30 | xargs -r rm -f --

# número = max(DA-NNN)+1, sobre o DIÁRIO REAL (não sobre um cache)
max=0
while read -r n; do
  n="$((10#$n))"
  [ "$n" -gt "$max" ] && max="$n"
done < <(grep -oE '^## DA-[0-9]+' "$DEC" | grep -oE '[0-9]+')
novo=$((max+1))
novokey="DA-$(printf '%03d' "$novo")"

data_hoje="$(date +%F)"
{
  echo ""
  echo "## $novokey — $TITULO"
  linhas | awk -F'\t' -v e="$ESCOPO" -v s="$SAGA" -v h="$data_hoje" -v t="$TIPO" '
    $6 != "s" { next }
    $1 == "cab"   { v = $7; if (v == "$ESCOPO") v = e; else if (v == "$SAGA") v = s; else if (v == "$HOJE") v = h; else if (v == "$TIPO") v = t
                    cab = cab (cab == "" ? "" : " · ") "`" $3 ": " v "`"; next }
    $1 == "corpo" { corpo = corpo "**" $3 ":** " $7 "\n" }
    END { print cab; printf "%s", corpo }'
} >> "$DEC"

echo "✓ da-new: $novokey anexada no fim de $DEC (snapshot: $ADAS_DIR/snapshots/DECISIONS.md.$ts)"
echo "  Preencha por Edit dentro de $novokey — nunca em DA anterior. Linha que não se aplica: apague. Contrato: $SCHEMA"
ajuda
echo "$novokey"
