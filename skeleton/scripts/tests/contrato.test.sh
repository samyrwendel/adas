#!/usr/bin/env bash
# contrato.test.sh — teste de CONTRATO da DA por mutação (Fase 2 do plano estrutural, task 20261112-017).
#
# O esquema (../da-schema.tsv) é a fonte única da ficha. Este teste prova três coisas:
#   1. o molde do da-new.sh é o esquema (mesmos campos, mesma ordem) e o script não escreve nome de campo à mão;
#   2. cada campo que um LEITOR consome existe no esquema — a tabela LEITORES abaixo é o lado do consumidor do
#      contrato: apagar do esquema um campo que alguém lê derruba este teste;
#   3. o leitor reage ao campo: monta uma DA de fixture A PARTIR do esquema, muda só aquele campo e exige que a
#      saída do leitor mude (mutação por efeito; grep de rótulo nos leitores não serve — parecer 006 §3).
# Trocar a ordem de linhas do esquema muda o molde e mantém este teste verde (a ordem esperada sai do esquema).
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)"; SCHEMA="${ADAS_DA_SCHEMA:-$S/da-schema.tsv}"
IDX="$S/da-index.sh"; NEW="$S/da-new.sh"; MEC="$S/check-da-mecanismo.sh"
CARDS="$(cd "$S/../.." 2>/dev/null && pwd)/host/jit/da-cards.py"   # só existe no repo do produto
export ADAS_DA_SCHEMA="$SCHEMA" LC_ALL=C.UTF-8
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ok=0; ko=0; pass(){ echo "  ✓ $1"; ok=$((ok+1)); }; fail(){ echo "  ✗ $1"; ko=$((ko+1)); }
linhas(){ awk -F'\t' '!/^#/ && NF>=9' "$SCHEMA"; }
tem_campo(){ linhas | awk -F'\t' -v k="$1" '$2==k{f=1} END{exit !f}'; }

# ---- 1. molde = esquema ----------------------------------------------------------------------------
mkdir -p "$T/m"; printf '# d\n' > "$T/m/DECISIONS.md"
ADAS_HOME_DIR="$T/m/.adas" bash "$NEW" --tipo regra produto nova/t "molde" "$T/m" >/dev/null 2>&1 || fail "da-new.sh falhou"
got_cab="$(sed -n '4p' "$T/m/DECISIONS.md" | grep -oE '`[^`:]+:' | tr -d '`:' | paste -sd' ')"
exp_cab="$(linhas | awk -F'\t' '$1=="cab" && $6=="s"{print $3}' | paste -sd' ')"
got_corpo="$(sed -n '5,$p' "$T/m/DECISIONS.md" | sed -nE 's/^\*\*([^*]+):\*\*.*/\1/p' | paste -sd'|')"
exp_corpo="$(linhas | awk -F'\t' '$1=="corpo" && $6=="s"{print $3}' | paste -sd'|')"
[ -n "$exp_cab" ] && [ "$got_cab" = "$exp_cab" ] && pass "cabeçalho do molde na ordem do esquema ($got_cab)" || fail "cabeçalho: veio '$got_cab', esquema '$exp_cab'"
[ -n "$exp_corpo" ] && [ "$got_corpo" = "$exp_corpo" ] && pass "corpo do molde na ordem do esquema" || fail "corpo: veio '$got_corpo', esquema '$exp_corpo'"
bash "$NEW" produto nova/t "x" "$T/m" >/dev/null 2>&1; [ $? = 2 ] && pass "sem --tipo recusa (rc=2)" || fail "da-new.sh aceitou DA sem --tipo"
bash "$NEW" --tipo norma produto nova/t "x" "$T/m" >/dev/null 2>&1; [ $? = 2 ] && pass "--tipo fora do esquema recusa" || fail "--tipo inválido aceito"
achados=""
while IFS=$'\t' read -r onde _ rot _; do
  pat="\\*\\*$rot:"; [ "$onde" = cab ] && pat="\`$rot:"
  grep -nE '^[[:space:]]*(echo|printf)' "$NEW" | grep -F -- "${pat//\\/}" >/dev/null && achados+="$rot "
done < <(linhas)
[ -z "$achados" ] && pass "nenhum nome de campo em echo/printf no da-new.sh" || fail "da-new.sh escreve campo à mão: $achados"
ajuda="$(bash "$NEW" --ajuda)"; faltam=""
while IFS=$'\t' read -r _ _ rot _; do grep -qF -- "$rot" <<< "$ajuda" || faltam+="$rot "; done < <(linhas)
[ -z "$faltam" ] && pass "--ajuda cita todos os campos do esquema" || fail "--ajuda sem: $faltam"
FICHA="$S/../../docs/ficha.md"
if [ -f "$FICHA" ]; then   # só no repo do produto; ordem livre (trocar linha do esquema não reprova), conteúdo não
  diff <(grep '^| ' "$FICHA" | sort) <(bash "$NEW" --ficha | grep '^| ' | sort) >/dev/null \
    && pass "docs/ficha.md = da-new.sh --ficha" || fail "docs/ficha.md desatualizada — rode: bash skeleton/scripts/da-new.sh --ficha > docs/ficha.md"
fi

# ---- 2+3. leitores: o campo existe no esquema e o leitor reage à mudança dele ------------------------
W="$T/w"; mkdir -p "$W/scripts" "$W/.adas"; ln -s "$IDX" "$W/scripts/da-index.sh"; : > "$W/CONDUCT.md"
base() {  # valor de base do campo (a DA de fixture tem que ser válida o bastante para cada leitor a ler)
  case "$1" in
    escopo) echo produto ;; saga) echo nova/t ;; data) echo 2026-11-20 ;; tipo) echo regra ;; gravidade) echo norma ;;
    refs|consolida|supersede|parcial) echo — ;;
    regra) echo "Nunca faça v-regra sem conferir." ;; gatilho) echo tema ;; exemplo) echo "✗ errado-a → ✓ certo-a" ;;
    mecanismo) echo "$W/DECISIONS.md" ;; *) echo "v-$1" ;;
  esac
}
muta() {
  case "$1" in
    escopo) echo instância ;; saga) echo nova/u ;; data) echo 2026-11-01 ;; tipo) echo registro ;; gravidade) echo piso ;;
    refs|consolida|supersede|parcial) echo DA-001 ;; gatilho) echo "forma · reply · juiz" ;; exemplo) echo "✗ errado-b → ✓ certo-b" ;;
    mecanismo) echo /nao/existe/trava.sh ;; *) echo "m-$1 nunca" ;;
  esac
}
gera() {  # gera <chave mutada|-> → $W/DECISIONS.md com DA-001 (alvo) e DA-002 montada do esquema
  local mut="$1"
  { printf '# D\n\n## DA-001 — alvo\n`escopo: produto` · `saga: nova/t` · `data: 2026-11-20` · `refs: —` · `consolida: —` · `supersede: —`\n**Regra:** Regra da DA-001 que serve de alvo.\n\n'
    printf '## DA-002 — fixture do contrato\n'
    local onde ch rot cab="" corpo="" v
    while IFS=$'\t' read -r onde ch rot _; do
      if [ "$ch" = "$mut" ]; then v="$(muta "$ch")"; else v="$(base "$ch")"; fi
      if [ "$onde" = cab ]; then cab+="${cab:+ · }\`$rot: $v\`"; else corpo+="**$rot:** $v"$'\n'; fi
    done < <(linhas)
    printf '%s\n%s' "$cab" "$corpo"
    [ "$mut" = consolida ] && printf '\n### Histórico\n- DA-001 — alvo — Regra\n'
  } > "$W/DECISIONS.md"
}
le() {  # le <leitor> → saída do leitor sobre o $W atual
  case "$1" in
    list)        bash "$IDX" list "$W" ;;
    vigentes)    bash "$IDX" list --vigentes "$W" ;;
    escopo)      bash "$IDX" list --escopo produto "$W" ;;
    saga)        bash "$IDX" list --saga nova/t "$W" ;;
    desde)       bash "$IDX" list --desde 2026-11-15 "$W" ;;
    gatilhos)    bash "$IDX" gatilhos "$W" ;;
    licoes)      bash "$IDX" update "$W" >/dev/null 2>&1; cat "$W/DECISIONS-LICOES.md" ;;
    show)        bash "$IDX" show DA-002 "$W" ;;
    dump)        bash "$IDX" dump "$W" ;;
    mecanismo)   bash "$MEC" --list "$W/DECISIONS.md" "$W" ;;
    cards)       python3 -I - "$CARDS" "$W" <<'PY'
import importlib.util, json, sys
sp = importlib.util.spec_from_file_location("dc", sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
print(json.dumps(m.das_de(sys.argv[2], sys.argv[2]), ensure_ascii=False, sort_keys=True))
PY
    ;;
    grafo)       mkdir -p "$T/g"; python3 -I - "$CARDS" "$W" "$T/g" <<'PY'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("dc", sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
cards = m.das_de(sys.argv[2], sys.argv[2])
for c in cards: c["hash"] = c["id"]          # sem vetor: só as arestas explícitas
m.compila_grafo(cards, sys.argv[3], {}, home=sys.argv[2]); print(open(sys.argv[3] + "/grafo.json").read())
PY
    ;;
  esac
}
# LEITORES: chave do esquema → quem a consome. É o contrato visto do consumidor (ficha v2 §2.2, coluna "Quem lê").
LEITORES="regra:list gatilho:gatilhos exemplo:cards fonte:show motivo:cards tradeoff:show licao:licoes
mecanismo:mecanismo padrao:cards detalhe:cards escopo:escopo saga:saga data:desde tipo:cards gravidade:cards
refs:cards consolida:vigentes supersede:vigentes parcial:list parcial:grafo"
[ -f "$CARDS" ] || echo "  · da-cards.py fora deste repo: leitor 'cards' pulado"
for par in $LEITORES; do
  ch="${par%%:*}" lt="${par#*:}"
  tem_campo "$ch" || { fail "campo '$ch' lido por '$lt' sumiu do esquema"; continue; }
  case "$lt" in cards|grafo) [ -f "$CARDS" ] || continue ;; esac
  gera -;   a="$(le "$lt" 2>&1)"
  gera "$ch"; b="$(le "$lt" 2>&1)"
  [ "$a" != "$b" ] && pass "$ch → $lt reage" || fail "$ch → $lt NÃO reage à mudança do campo"
done
# dump: cada campo do esquema é uma coluna e reage (o acesso único segue o esquema sozinho)
while IFS=$'\t' read -r _ ch _; do
  gera -; a="$(le dump)"; gera "$ch"; b="$(le dump)"
  [ "$a" != "$b" ] || fail "dump não reage a '$ch'"
done < <(linhas)
[ "$(le dump | head -1 | cut -f3- | tr '\t' ' ')" = "$(linhas | cut -f2 | paste -sd' ')" ] \
  && pass "dump: colunas = chaves do esquema, na ordem" || fail "dump: cabeçalho difere do esquema"
gera -; ck="$(DA_FICHA_DESDE=2026-11-13 bash "$IDX" check "$W" 2>&1)"
grep -q 'WARN ficha: DA-002' <<< "$ck" && fail "a fixture montada do esquema não passa na ficha: $(grep 'ficha: DA-002' <<< "$ck" | head -2)" \
  || pass "DA montada do esquema passa no check da ficha"
echo "contrato: $ok ok, $ko falha(s)"; [ "$ko" = 0 ]
