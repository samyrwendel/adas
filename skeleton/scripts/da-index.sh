#!/usr/bin/env bash
# da-index.sh — índice + sagas do DECISIONS.md que NASCEM junto com a DA (DA-181/182).
#
# NÃO compacta, NÃO resume, NÃO altera uma linha do corpo das DAs — só DERIVA. O hook
# PostToolUse da-index-hook.sh roda `update` no ATO de qualquer edição do DECISIONS.md;
# o `check` (chamado pelo check-adas, check 10) ACUSA divergência — nunca passa batido.
#
# uso:
#   da-index.sh update [dir]                          # (re)gera todos os gerados
#   da-index.sh check  [dir]                           # regenera em tmp e compara; diverge = exit 1
#   da-index.sh sagas [--escopo a,b] [--projeto nome] [dir]   # camada 0
#   da-index.sh list  [--escopo a,b] [--saga slug] [--vigentes] [--desde AAAA-MM-DD] [dir]
#   da-index.sh show DA-NNN [dir] | show --saga slug [dir] | show --anexos DA-NNN [dir]
#   da-index.sh export-saga slug [dir]
# [dir] = onde vivem DECISIONS.md e os gerados (default: $HOME — NUNCA o cwd; DA-196).
#
# Determinístico: mesmo DECISIONS.md + membros.tsv ⇒ mesmos gerados byte a byte.
# Grandfather: checks de qualidade (c1/c2/c4/c5) só valem para DA-NNN > 180 — o corpo
# das DA-001..180 (a DA-127 inclusive) é intocável (DA-181/182) e nunca é re-julgado.
set -uo pipefail

SELFDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SEP=$'\037'
GRANDFATHER="${DA_INDEX_GRANDFATHER:-180}"   # DA-001..180 nunca são re-julgadas pelas checks de qualidade novas (override p/ harness de fixtures)
# [dir] ausente → $HOME, NUNCA o cwd (DA-196/DA-186: rodar de outro diretório não pode
# fazer "não achei o arquivo" virar "a decisão não existe"). [dir] explícito sempre vence.
DA_DIR_DEFAULT="${HOME:-.}"

# ============================================================================
# 1) PARSER — awk extrai um registro por DA (ver cabeçalho de campos abaixo)
# ============================================================================
_parse_awk() {
cat <<'AWKEOF'
BEGIN { SEP = sprintf("%c", 31); n = 0; inbody = 0 }
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function refs_in(s,    out) {
  out = ""
  while (match(s, /DA-[0-9]+[a-z]?/)) { out = out (out=="" ? "" : ",") substr(s, RSTART, RLENGTH); s = substr(s, RSTART+RLENGTH) }
  return out
}
function refs_in_plain(s,    out) {
  out = ""
  while (match(s, /DA-[0-9]+/)) { out = out (out=="" ? "" : ",") substr(s, RSTART, RLENGTH); s = substr(s, RSTART+RLENGTH) }
  return out
}
function csv_add(list, item) { if (item == "") return list; if (list == "") return item; return list "," item }
function mark_targets(map_name, targets, by,    k, a, i, key) {
  k = split(targets, a, ",")
  for (i=1; i<=k; i++) {
    key = trim(a[i]); if (key == "") continue
    sub(/^DA-/, "", key)
    if (key == by) continue
    if (map_name == "sup") { if (!(key in supby)) supby[key] = by }
    else if (map_name == "par") { if (!(key in parby)) parby[key] = by }
    else if (map_name == "con") { if (!(key in conby)) conby[key] = by }
  }
}

# ---- Regra fallback (b), consciente de PARÁGRAFO (DA-181 fix pós-teste 03/09) --------------
# Um parágrafo pode vir hard-wrapped em várias linhas físicas. A linha ORIGINAL só olhava a
# 1a linha física pra decidir "é metadado?" — uma continuação como "por:** devbot. **Escopo:**"
# (2a linha de um `**Data:** ... **Implementado\npor:** devbot...` quebrado) passava batida e
# virava a Regra. Agora classifica o PARÁGRAFO inteiro (até linha em branco/heading/---) pela
# 1a linha, e só then extrai a 1a FRASE (até .!?) do parágrafo de conteúdo real.
function is_metadata_start(l) {
  if (l ~ /^\*\*(Data|Status|Autor|Decidido por|Implementado por|Gatilho|Pedido do|Escopo)[:]?\*\*?/) return 1
  if (l ~ /^Relacionadas:/) return 1
  if (l ~ /^`/) return 1
  if (l ~ /^>/) return 1
  if (l ~ /^---/) return 1
  if (l ~ /^[([]/) return 1
  if (l ~ /^\*?"/) return 1
  return 0
}
function strip_prefix_markup(s,    r) {
  r = s
  sub(/^[ \t]*([-*][ \t]+|[0-9]+\.[ \t]+)/, "", r)
  gsub(/\*\*/, "", r)
  return trim(r)
}
function first_sentence(s,    n2, i, ch, nx) {
  n2 = length(s)
  for (i = 1; i <= n2; i++) {
    ch = substr(s, i, 1)
    if (ch == "." || ch == "!" || ch == "?") {
      nx = (i < n2) ? substr(s, i+1, 1) : ""
      if (nx == "" || nx == " " || nx == "\t") return substr(s, 1, i)
    }
  }
  return ""
}
function valid_sentence(s,    c) {
  if (s == "") return 0
  if (length(s) < 30 || length(s) > 240) return 0
  c = substr(s, 1, 1)
  if (c ~ /^[]["'`(){}*_.,;:!?#>—–-]/) return 0
  return 1
}
# para_line: alimenta uma linha do corpo no acumulador do canal ch ("f"=1o parágrafo do
# corpo inteiro, "d"=1o parágrafo dentro de uma seção ### Decisão). Fecha o parágrafo em
# linha branca/heading/---; se o parágrafo fechado NÃO era metadado, tenta commitá-lo
# (uma tentativa só — falhar validação não passa pro parágrafo seguinte, vira "none").
function para_line(ch, line) {
  if (ptried[ch]) return
  if (!pactive[ch]) return
  if (line ~ /^[[:space:]]*$/ || line ~ /^#/ || line ~ /^---[ \t]*$/) {
    if (pbufopen[ch]) {
      if (!pbufmeta[ch]) para_commit(ch)
      pbufopen[ch] = 0; pbuf[ch] = ""; pbufmeta[ch] = 0
    }
    return
  }
  if (!pbufopen[ch]) { pbufopen[ch] = 1; pbufmeta[ch] = is_metadata_start(line); pbuf[ch] = trim(line) }
  else pbuf[ch] = pbuf[ch] " " trim(line)
}
function para_commit(ch,    cleaned, sent) {
  cleaned = strip_prefix_markup(pbuf[ch])
  sent = first_sentence(cleaned)
  if (valid_sentence(sent)) presult[ch] = sent
  ptried[ch] = 1
}
function para_finalize(ch) {
  if (!ptried[ch] && pbufopen[ch] && !pbufmeta[ch]) para_commit(ch)
}
function iso_from_br(d,    a) { split(d, a, "/"); return a[3] "-" a[2] "-" a[1] }

function flush(   ) {
  para_finalize("f"); para_finalize("d")
  if (cur != "") {
    d0 = presult["d"]; f0 = presult["f"]
    if (regra == "") { if (d0 != "") { regra = d0; regrasrc = "decisao" } else if (f0 != "") { regra = f0; regrasrc = "paragrafo" } else regrasrc = "none" }
    bodydata = (bodydata_label != "") ? bodydata_label : bodydateline
    n++
    ord[n] = cur; rawnum[n] = curraw; lineno[n] = curline; title_a[n] = t
    escopo_a[n] = e_escopo; saga_a[n] = e_saga; data_a[n] = e_data; refs_a[n] = e_refs
    consolida_a[n] = e_consolida; supersede_a[n] = e_supersede; medido_a[n] = e_medido
    regra_a[n] = regra; regrasrc_a[n] = regrasrc
    motivo_a[n] = motivo; tradeoff_a[n] = tradeoff; licao_a[n] = licao
    bodydata_a[n] = bodydata; corpolines_a[n] = bl
    haspaste_a[n] = (commitcount >= 3 || efficiency_seen == 1 || tablelines >= 2) ? 1 : 0
    historico_a[n] = historico_list
    if (e_supersede != "") mark_targets("sup", e_supersede, curraw)
    if (e_consolida != "") mark_targets("con", e_consolida, curraw)
  }
  cur=""; curraw=""; curline=0; t=""
  e_escopo=""; e_saga=""; e_data=""; e_refs=""; e_consolida=""; e_supersede=""; e_medido=""
  regra=""; regrasrc="none"; motivo=""; tradeoff=""; licao=""; bodydata=""; bodydata_label=""; bodydateline=""; d0=""; f0=""
  bl=0; commitcount=0; efficiency_seen=0; tablelines=0
  inhist=0; historico_list=""; tagline_seen=0
  ptried["f"]=0; ptried["d"]=0; pactive["f"]=1; pactive["d"]=0
  pbufopen["f"]=0; pbufopen["d"]=0; pbuf["f"]=""; pbuf["d"]=""; pbufmeta["f"]=0; pbufmeta["d"]=0
  presult["f"]=""; presult["d"]=""
}
/^## DA-[0-9]+/ { inbody = 1 }
!inbody && /^- \*\*DA-[0-9]+\*\*/ && /[Ss]upersed[a-z]* (pela|por) DA-[0-9]+/ {
  match($0, /DA-[0-9]+/); self = substr($0, RSTART+3, RLENGTH-3)
  rest = substr($0, RSTART+RLENGTH)
  if (match(rest, /[Ss]upersed[a-z]* (pela|por) DA-[0-9]+/)) {
    seg = substr(rest, RSTART, RLENGTH); match(seg, /DA-[0-9]+/)
    tgt = substr(seg, RSTART+3, RLENGTH-3)
    if (!(self in supby)) supby[self] = tgt
  }
}
/^## DA-[0-9]+ — / {
  flush()
  match($0, /DA-[0-9]+/); curraw = substr($0, RSTART+3, RLENGTH-3)
  cur = "DA-" curraw; curline = NR
  t = $0; sub(/^## DA-[0-9]+ — /, "", t)
  bl = 0
  next
}
cur == "" { next }
{
  line = $0; bl++
  if (bl <= 3 && !tagline_seen && (index(line, "`escopo:") > 0 || index(line, "`saga:") > 0)) {
    tagline_seen = 1
    s = line
    while (match(s, /`[^`]+`/)) {
      tag = substr(s, RSTART+1, RLENGTH-2); s = substr(s, RSTART+RLENGTH)
      ci = index(tag, ":")
      if (ci > 0) {
        key = trim(substr(tag, 1, ci-1)); val = trim(substr(tag, ci+1))
        if (val == "—" || val == "-") val = ""
        if (key == "escopo") e_escopo = csv_add(e_escopo, val)
        else if (key == "saga") { k2 = split(val, sa, ","); for (j2=1;j2<=k2;j2++) e_saga = csv_add(e_saga, trim(sa[j2])) }
        else if (key == "data") e_data = val
        else if (key == "refs") e_refs = csv_add(e_refs, val)
        else if (key == "consolida") e_consolida = csv_add(e_consolida, val)
        else if (key == "supersede") e_supersede = csv_add(e_supersede, val)
        else if (key == "medido") e_medido = val
      }
    }
    next
  }
  if (regrasrc != "regra" && regra == "" && match(line, /^\*\*Regra:?\*\*[:]?[ \t]*/)) { regra = substr(line, RLENGTH+1); regrasrc = "regra" }
  if (motivo == "" && match(line, /^\*\*Motivo:?\*\*[:]?[ \t]*/)) motivo = substr(line, RLENGTH+1)
  if (tradeoff == "" && match(line, /^\*\*Trade-off:?\*\*[:]?[ \t]*/)) tradeoff = substr(line, RLENGTH+1)
  if (licao == "" && match(line, /^\*\*Li(ção|cao):?\*\*[:]?[ \t]*/)) licao = substr(line, RLENGTH+1)
  # data do corpo: (2) linha "**Data:** YYYY-MM-DD" rotulada — pega o PREFIXO ISO (o resto da
  # linha pode ter hora "20:07", parêntese "(noite autônoma)" etc.; só a data importa aqui)
  if (bodydata_label == "" && match(line, /\*\*Data:?\*\*[:]?[ \t]*/)) {
    bl_cand = substr(line, RSTART+RLENGTH)
    if (match(bl_cand, /^[0-9]{4}-[0-9]{2}-[0-9]{2}/)) bodydata_label = substr(bl_cand, RSTART, RLENGTH)
  }
  # data do corpo: (3) 1a data (BR DD/MM/YYYY ou ISO) que abre a linha isolada — convenção comum
  # quando não há rótulo "Data:" (ex.: "**23/08/2026** · refs ..."). NÃO pega data em prosa
  # solta no meio da frase (ex.: "[Samyr, 22/07/2026, msg 1051]") — só a que abre a linha.
  if (bodydateline == "" && match(line, /^\*{0,2}[0-9]{2}\/[0-9]{2}\/[0-9]{4}\*{0,2}/)) {
    rawdt = substr(line, RSTART, RLENGTH); gsub(/\*/, "", rawdt); bodydateline = iso_from_br(rawdt)
  } else if (bodydateline == "" && match(line, /^\*{0,2}[0-9]{4}-[0-9]{2}-[0-9]{2}\*{0,2}/)) {
    rawdt = substr(line, RSTART, RLENGTH); gsub(/\*/, "", rawdt); bodydateline = rawdt
  }
  if (!ptried["d"] && !pactive["d"]) {
    if (line ~ /^### Decis/ || line ~ /^\*\*Decis[^*]*\*\*[[:space:]]*$/) {
      pactive["d"] = 1
    } else if (match(line, /^\*\*Decis[^*]*\*\*[[:space:]]*:?[[:space:]]*/) && length(line) > RLENGTH) {
      pactive["d"] = 1
      para_line("d", substr(line, RLENGTH+1))
    }
  } else if (!ptried["d"]) {
    para_line("d", line)
    if (line ~ /^#/) pactive["d"] = 0
  }
  if (!ptried["f"]) para_line("f", line)
  if (line ~ /^### Hist(ó|o)rico/) inhist = 1
  else if (inhist && line ~ /^(##|---)/) inhist = 0
  else if (inhist && line ~ /^- DA-[0-9]/) historico_list = historico_list (historico_list=="" ? "" : ";") refs_in(line)
  if (line ~ /^commit [0-9a-f]{40}$/) commitcount++
  if (index(line, "Efficiency meter") > 0) efficiency_seen = 1
  if (index(line,"────")>0 || index(line,"━━━━")>0 || index(line,"════")>0 || index(line,"░░░░")>0 || index(line,"▓▓▓▓")>0 || index(line,"█████")>0) tablelines++
  if (line ~ /(NÃO|não|nao|Não) supersede/) next
  if (match(line, /[Ss]upersed(ida|ed)[a-z]* (pela|por) DA-[0-9]+/)) {
    seg = substr(line, RSTART, RLENGTH); match(seg, /DA-[0-9]+/)
    tgt = substr(seg, RSTART+3, RLENGTH-3)
    if (!(curraw in supby)) supby[curraw] = tgt
    next
  }
  if (match(line, /[Ss]upersede[a-z]*/)) {
    seg = substr(line, RSTART)
    if (match(seg, /[;.]/)) seg = substr(seg, 1, RSTART-1)
    r = refs_in_plain(seg)
    if (r != "") {
      if (seg ~ /(PARCIAL|parcial|a linha|o escopo|a regra|o crit(é|e)rio|no campo)/) mark_targets("par", r, curraw)
      else mark_targets("sup", r, curraw)
    }
    next
  }
  if (match(line, /corrige o escopo[a-z ]* d[aeo][a-z]* DA-[0-9]+/) || (line ~ /passam? a `?escopo:/ && line ~ /DA-[0-9]+/)) {
    mark_targets("par", refs_in_plain(line), curraw)
  }
}
END {
  flush()
  for (i=1;i<=n;i++) totalcnt[rawnum[i]]++
  for (i=1;i<=n;i++) {
    if (totalcnt[rawnum[i]] > 1) { seen[rawnum[i]]++; suf = sprintf("%c", 96+seen[rawnum[i]]); key_a[i] = "DA-" rawnum[i] suf }
    else key_a[i] = "DA-" rawnum[i]
  }
  for (i=1; i<=n; i++) {
    ksuf = key_a[i]; sub(/^DA-/, "", ksuf)
    ms = (ksuf in supby) ? supby[ksuf] : ((rawnum[i] in supby) ? supby[rawnum[i]] : "")
    mp = (ksuf in parby) ? parby[ksuf] : ((rawnum[i] in parby) ? parby[rawnum[i]] : "")
    mc = (ksuf in conby) ? conby[ksuf] : ((rawnum[i] in conby) ? conby[rawnum[i]] : "")
    out = key_a[i] SEP rawnum[i] SEP lineno[i] SEP title_a[i] SEP \
          escopo_a[i] SEP saga_a[i] SEP data_a[i] SEP refs_a[i] SEP \
          consolida_a[i] SEP supersede_a[i] SEP medido_a[i] SEP \
          regra_a[i] SEP regrasrc_a[i] SEP motivo_a[i] SEP tradeoff_a[i] SEP \
          licao_a[i] SEP bodydata_a[i] SEP corpolines_a[i] SEP haspaste_a[i] SEP \
          historico_a[i] SEP ms SEP mp SEP mc
    print out
  }
}
AWKEOF
}

# ============================================================================
# 2) CARREGAMENTO — popula arrays globais a partir do DECISIONS.md + membros.tsv
#    Campos (0-based, array KEY/RAWNUM/.../MCON), N = total de registros.
# ============================================================================
declare -a KEY RAWNUM LINE TITLE ESCOPO SAGA DATATAG REFS CONSOLIDA SUPERSEDE MEDIDO
declare -a REGRA REGRASRC MOTIVO TRADEOFF LICAO BODYDATA CORPOLINES HASPASTE HISTORICO MSUP MPAR MCON
declare -A MTSV_SAGA MTSV_ESCOPO
declare -a EFF_SAGA EFF_ESCOPO   # indexado 0..N-1 (NÃO associativo — subscrito é aritmético)
N=0

# DA-024: fantasma conhecido (DA-182) — anunciada, nunca escrita; substância alhures.
declare -A FANTASMA_REF=( ["DA-024"]="029" )

load_records() {
  local dir="$1"; local dec="$dir/DECISIONS.md"
  if [ ! -f "$dec" ]; then
    echo "✗ da-index: não consegui ler $dec (arquivo não existe) — dir='$dir'" >&2
    exit 1
  fi
  if [ ! -r "$dec" ]; then
    echo "✗ da-index: não consegui ler $dec (sem permissão de leitura)" >&2
    exit 1
  fi
  KEY=(); RAWNUM=(); LINE=(); TITLE=(); ESCOPO=(); SAGA=(); DATATAG=(); REFS=(); CONSOLIDA=(); SUPERSEDE=(); MEDIDO=()
  REGRA=(); REGRASRC=(); MOTIVO=(); TRADEOFF=(); LICAO=(); BODYDATA=(); CORPOLINES=(); HASPASTE=(); HISTORICO=(); MSUP=(); MPAR=(); MCON=()
  local i=0
  while IFS="$SEP" read -r f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 f13 f14 f15 f16 f17 f18 f19 f20 f21 f22 f23; do
    KEY[i]="$f1"; RAWNUM[i]="$f2"; LINE[i]="$f3"; TITLE[i]="$f4"; ESCOPO[i]="$f5"; SAGA[i]="$f6"; DATATAG[i]="$f7"
    REFS[i]="$f8"; CONSOLIDA[i]="$f9"; SUPERSEDE[i]="$f10"; MEDIDO[i]="$f11"; REGRA[i]="$f12"; REGRASRC[i]="$f13"
    MOTIVO[i]="$f14"; TRADEOFF[i]="$f15"; LICAO[i]="$f16"; BODYDATA[i]="$f17"; CORPOLINES[i]="$f18"; HASPASTE[i]="$f19"
    HISTORICO[i]="$f20"; MSUP[i]="$f21"; MPAR[i]="$f22"; MCON[i]="$f23"
    i=$((i+1))
  done < <(awk "$(_parse_awk)" "$dec")
  N=$i

  MTSV_SAGA=(); MTSV_ESCOPO=()
  local mtsv="$dir/DECISIONS-anexos/DA-182/membros.tsv"
  if [ -f "$mtsv" ]; then
    local da s e f first=1
    while IFS=$'\t' read -r da s e f; do
      [ "$first" = 1 ] && { first=0; continue; }
      [ -z "$da" ] && continue
      MTSV_SAGA["$da"]="$s"; MTSV_ESCOPO["$da"]="$e"
    done < "$mtsv"
  fi

  EFF_SAGA=(); EFF_ESCOPO=()
  local idx
  for ((idx=0; idx<N; idx++)); do
    local es="${SAGA[idx]}"; [ -z "$es" ] && es="${MTSV_SAGA[${KEY[idx]}]:-}"
    local ee="${ESCOPO[idx]}"; [ -z "$ee" ] && ee="${MTSV_ESCOPO[${KEY[idx]}]:-}"
    EFF_SAGA[idx]="$es"; EFF_ESCOPO[idx]="$ee"
  done
}

# marca final de uma DA (índice i): "" (vigente) | "sup:<alvo>" | "par:<alvo>" | "con:<alvo>"
mark_of() {
  local i="$1"
  [ -n "${MSUP[i]}" ] && { echo "sup:${MSUP[i]}"; return; }
  [ -n "${MPAR[i]}" ] && { echo "par:${MPAR[i]}"; return; }
  [ -n "${MCON[i]}" ] && { echo "con:${MCON[i]}"; return; }
  echo ""
}
mark_render() {   # "🔄 por DA-x" | "½ por DA-y" | "📚 em DA-z" | ""
  local m; m="$(mark_of "$1")"
  [ -z "$m" ] && { echo ""; return; }
  local kind="${m%%:*}" tgt="${m#*:}"
  case "$kind" in
    sup) echo "🔄 por DA-$tgt" ;;
    par) echo "½ por DA-$tgt" ;;
    con) echo "📚 em DA-$tgt" ;;
  esac
}

trunc() {  # trunc "$texto" N
  local s="$1" n="$2"
  if [ "${#s}" -le "$n" ]; then printf '%s' "$s"; return; fi
  printf '%s...' "${s:0:$((n-3))}"
}

# ============================================================================
# 3) AGRUPAMENTO POR SAGA
# ============================================================================
declare -A SAGA_MEMBERS SAGA_ESCOPO SAGA_HEAD_IDX
SAGA_SLUGS=()

group_sagas() {
  SAGA_MEMBERS=(); SAGA_ESCOPO=(); SAGA_HEAD_IDX=(); SAGA_SLUGS=()
  local idx slug
  for ((idx=0; idx<N; idx++)); do
    [ -z "${EFF_SAGA[idx]}" ] && continue
    IFS=',' read -ra _slugs <<< "${EFF_SAGA[idx]}"
    for slug in "${_slugs[@]}"; do
      slug="$(printf '%s' "$slug" | sed 's/^[ \t]*//;s/[ \t]*$//')"
      [ -z "$slug" ] && continue
      [ "$slug" = "fantasma" ] && continue
      if [ -z "${SAGA_MEMBERS[$slug]:-}" ]; then SAGA_SLUGS+=("$slug"); fi
      SAGA_MEMBERS[$slug]+="$idx "
      if [ -z "${SAGA_ESCOPO[$slug]:-}" ] && [ -n "${EFF_ESCOPO[idx]}" ]; then SAGA_ESCOPO[$slug]="${EFF_ESCOPO[idx]}"; fi
      if [ -n "${CONSOLIDA[idx]}" ]; then SAGA_HEAD_IDX[$slug]="$idx"; fi
    done
  done
  IFS=$'\n' SAGA_SLUGS=($(sort <<<"${SAGA_SLUGS[*]}")); unset IFS
}

# membros de uma saga, ORDENADOS por LINE (ordem no diário). Ecoa índices separados por espaço.
saga_members_sorted() {
  local slug="$1" idx
  local -a idxs=(${SAGA_MEMBERS[$slug]:-})
  local -a withline=()
  for idx in "${idxs[@]}"; do withline+=("${LINE[idx]}:$idx"); done
  printf '%s\n' "${withline[@]}" | sort -t: -k1,1n | cut -d: -f2
}

# fonte da "Regra atual" de uma saga: última DA vigente por ordem no diário
# (a da cabeça quando não há rodada depois; a própria cabeça se regra não parseia => "ver DA-NNN")
saga_regra_source_idx() {
  local slug="$1"
  local -a members=($(saga_members_sorted "$slug"))
  local head="${SAGA_HEAD_IDX[$slug]:-}"
  if [ -z "$head" ]; then
    echo "${members[-1]}"
    return
  fi
  local headline="${LINE[$head]}"
  local last="$head" idx
  for idx in "${members[@]}"; do
    [ "${LINE[$idx]}" -gt "$headline" ] && last="$idx"
  done
  echo "$last"
}

saga_rodadas_depois_da_cabeca() {  # conta membros com LINE > cabeça
  local slug="$1"
  local head="${SAGA_HEAD_IDX[$slug]:-}"
  [ -z "$head" ] && { echo 0; return; }
  local headline="${LINE[$head]}" idx c=0
  for idx in $(saga_members_sorted "$slug"); do
    [ "${LINE[$idx]}" -gt "$headline" ] && c=$((c+1))
  done
  echo "$c"
}

saga_estado() {  # viva|encerrada — heurística: título/regra da última DA menciona "encerr"
  local slug="$1"
  local -a members=($(saga_members_sorted "$slug"))
  local last="${members[-1]}"
  if printf '%s %s' "${TITLE[$last]}" "${REGRA[$last]}" | grep -qiE 'encerr(ada|amento)'; then
    echo "encerrada"
  else
    echo "viva"
  fi
}

# ============================================================================
# 4) GERAÇÃO — DECISIONS-INDEX.md / DECISIONS-SAGAS.md / DECISIONS-LICOES.md /
#    DECISIONS-VIGENTE-<escopo>.md
# ============================================================================
saga_summary_line() {
  local slug="$1"
  local -a members=($(saga_members_sorted "$slug"))
  local escopo="${SAGA_ESCOPO[$slug]:-—}"
  local head="${SAGA_HEAD_IDX[$slug]:-}"
  local cabeca="—"; [ -n "$head" ] && cabeca="${KEY[$head]}"
  local n_das="${#members[@]}"
  local memlist=""; local idx
  for idx in "${members[@]}"; do memlist+="${memlist:+, }${KEY[$idx]}"; done
  local src; src="$(saga_regra_source_idx "$slug")"
  local regra="ver ${KEY[$src]}"
  [ "${REGRASRC[$src]}" != "none" ] && regra="$(trunc "${REGRA[$src]}" 200)"
  local rodadas; rodadas="$(saga_rodadas_depois_da_cabeca "$slug")"
  local aviso=""
  if [ -n "$head" ] && [ "$rodadas" -ge 1 ]; then
    local extras=""
    local hl="${LINE[$head]}"
    for idx in "${members[@]}"; do [ "${LINE[$idx]}" -gt "$hl" ] && extras+="${extras:+, }${KEY[$idx]}"; done
    aviso=" · ⚠ $rodadas rodada(s) depois da cabeça $cabeca — ler $extras"
    [ "$rodadas" -ge 3 ] && aviso+=" (hora de nova cabeça)"
  fi
  printf -- "- %s · %s · cabeça: %s · %s DA%s · membros: %s · Regra: %s%s\n" \
    "$slug" "$escopo" "$cabeca" "$n_das" "$([ "$n_das" = 1 ] && echo "" || echo "s")" "$memlist" "$regra" "$aviso"
}

build_sagas_block() {   # usado tanto por 'sagas' quanto pelo bloco embutido do INDEX
  local filtro_escopo="$1"   # csv ou vazio
  local slug
  for slug in "${SAGA_SLUGS[@]}"; do
    if [ -n "$filtro_escopo" ]; then
      local match=0 fe se
      IFS=',' read -ra _fe <<< "$filtro_escopo"
      for fe in "${_fe[@]}"; do
        IFS=',' read -ra _se <<< "${SAGA_ESCOPO[$slug]:-}"
        for se in "${_se[@]}"; do [ "$se" = "$fe" ] && match=1; done
      done
      [ "$match" = 0 ] && continue
    fi
    saga_summary_line "$slug"
  done
}

index_line_for() {
  local i="$1"
  local escopo="${EFF_ESCOPO[i]:-—}"; local saga="${EFF_SAGA[i]:-—}"
  local marca; marca="$(mark_render "$i")"
  local regra="${REGRA[$i]}"; [ "${REGRASRC[$i]}" = "none" ] && regra=""
  local sufixo=""; [ -n "$marca" ] && sufixo=" · $marca"
  printf -- "- %s · %s · %s%s — %s%s\n" \
    "${KEY[$i]}" "$escopo" "$saga" "$sufixo" "${TITLE[$i]}" "$([ -n "$regra" ] && echo " — $(trunc "$regra" 140)" || echo "")"
}

build_index() {
  local dir="$1"; local dec="$dir/DECISIONS.md"
  local nheaders sha; nheaders="$(grep -c '^## DA-[0-9]' "$dec")"; sha="$(sha256sum "$dec" | cut -c1-16)"
  echo "# Índice de Decisões — GERADO de DECISIONS.md (NÃO EDITE À MÃO)"
  echo "# Regenerar: bash scripts/da-index.sh update · Conferir: bash scripts/da-index.sh check"
  echo "# Sem marca = vigente · 🔄 por DA-x = SUPERSEDIDA (íntegra) · ½ por DA-y = alterada (parcial) · 📚 em DA-z = consolidada na cabeça da saga"
  echo "# fonte: $nheaders cabeçalhos (182 chaves com DA-012a/012b; DA-024 é fantasma) · sha256(DECISIONS.md)=$sha"
  echo
  echo "<!-- da-sagas-start -->"
  echo "## Sagas"
  build_sagas_block ""
  echo "<!-- da-sagas-end -->"
  echo
  local i inserted024=0
  for ((i=0; i<N; i++)); do
    if [ "$inserted024" = 0 ] && [ "$(nv "${RAWNUM[i]}")" -gt 24 ]; then
      printf -- "- DA-024 · fantasma → ver DA-%s (anunciada no índice congelado, nunca escrita)\n" "${FANTASMA_REF[DA-024]:-029}"
      inserted024=1
    fi
    index_line_for "$i"
  done
  if [ "$inserted024" = 0 ]; then
    printf -- "- DA-024 · fantasma → ver DA-%s (anunciada no índice congelado, nunca escrita)\n" "${FANTASMA_REF[DA-024]:-029}"
  fi
  return 0
}

build_sagas_md() {
  echo "# DECISIONS-SAGAS.md — NA-<slug>, GERADO de DECISIONS.md (NÃO EDITE À MÃO)"
  echo "# Regenerar: bash scripts/da-index.sh update · uma seção por saga com 2+ DAs. Ninguém escreve aqui — é awk."
  echo
  local slug
  for slug in "${SAGA_SLUGS[@]}"; do
    local -a members=($(saga_members_sorted "$slug"))
    [ "${#members[@]}" -lt 2 ] && continue
    local escopo="${SAGA_ESCOPO[$slug]:-—}"
    local head="${SAGA_HEAD_IDX[$slug]:-}"
    local cabeca="—"; [ -n "$head" ] && cabeca="${KEY[$head]}"
    local memlist=""; local idx
    for idx in "${members[@]}"; do memlist+="${memlist:+, }${KEY[$idx]}"; done
    local src; src="$(saga_regra_source_idx "$slug")"
    local regra="ver ${KEY[$src]}"
    [ "${REGRASRC[$src]}" != "none" ] && regra="${REGRA[$src]}"
    local msrc="$head"; [ -z "$msrc" ] && msrc="${members[-1]}"
    local motivo="${MOTIVO[$msrc]:-—}"; local tradeoff="${TRADEOFF[$msrc]:-—}"; local licao="${LICAO[$msrc]:-—}"
    local rodadas; rodadas="$(saga_rodadas_depois_da_cabeca "$slug")"
    local estado; estado="$(saga_estado "$slug")"

    echo "## NA-$slug"
    echo "- escopo: $escopo"
    echo "- cabeça: $cabeca"
    echo "- membros: $memlist"
    echo "- **Regra atual:** $regra"
    echo "- Motivo: $motivo"
    echo "- Trade-off: $tradeoff"
    echo "- Lição: $licao"
    echo "### Histórico"
    for idx in "${members[@]}"; do
      local data="${DATATAG[$idx]:-${BODYDATA[$idx]:-—}}"
      local mr; mr="$(mark_render "$idx")"; [ -z "$mr" ] && mr="vigente"
      local medido="${MEDIDO[$idx]:-—}"
      local rline="${REGRA[$idx]}"; [ "${REGRASRC[$idx]}" = "none" ] && rline="—"
      printf -- "- %s · %s · %s · %s · %s · medido: %s\n" "$data" "${KEY[$idx]}" "${TITLE[$idx]}" "$(trunc "$rline" 120)" "$mr" "$medido"
    done
    if [ -n "$head" ] && [ "$rodadas" -ge 1 ]; then
      local extras="" hl="${LINE[$head]}"
      for idx in "${members[@]}"; do [ "${LINE[$idx]}" -gt "$hl" ] && extras+="${extras:+, }${KEY[$idx]}"; done
      echo "> ⚠ $rodadas rodada(s) depois da cabeça $cabeca — ler $extras$([ "$rodadas" -ge 3 ] && echo ' — hora de nova cabeça')"
    fi
    echo "- estado: $estado"
    echo
  done
}

build_licoes() {
  echo "# DECISIONS-LICOES.md — GERADO de DECISIONS.md (NÃO EDITE À MÃO). Injetado inteiro na sessão."
  echo
  declare -A appliedby
  local i
  for ((i=0; i<N; i++)); do
    local l="${LICAO[i]}"
    [ -z "$l" ] && continue
    if [[ "$l" =~ ^[Aa]plica[[:space:]]+DA-([0-9]+[a-z]?) ]]; then
      appliedby["${BASH_REMATCH[1]}"]+="${appliedby[${BASH_REMATCH[1]}]:+, }${KEY[i]}"
    fi
  done
  for ((i=0; i<N; i++)); do
    local l="${LICAO[i]}"
    [ -z "$l" ] && continue
    [[ "$l" =~ ^[Nn]enhuma ]] && continue
    [[ "$l" =~ ^[Aa]plica[[:space:]]+DA- ]] && continue
    local raw="${RAWNUM[i]}"; local apl="${appliedby[$raw]:-}"
    printf -- "- %s · %s · %s · %s%s\n" "${KEY[i]}" "${EFF_ESCOPO[i]:-—}" "${EFF_SAGA[i]:-—}" "$l" "$([ -n "$apl" ] && echo " · aplicada por: $apl" || echo "")"
  done
}

build_vigente_for_escopo() {
  local alvo="$1" i
  echo "# DECISIONS-VIGENTE-$alvo.md — GERADO de DECISIONS.md (NÃO EDITE À MÃO). Cabeçalhos de DAs vigentes do escopo $alvo."
  echo
  for ((i=0; i<N; i++)); do
    local match=0 ee
    IFS=',' read -ra _ee <<< "${EFF_ESCOPO[i]}"
    for ee in "${_ee[@]}"; do [ "$ee" = "$alvo" ] && match=1; done
    [ "$match" = 0 ] && continue
    local m; m="$(mark_of "$i")"
    [ -n "$m" ] && [ "${m%%:*}" != "par" ] && continue   # 🔄 e 📚 não são vigentes; ½ continua valendo no que não foi alterado
    echo "## ${KEY[i]} — ${TITLE[i]}"
    [ -n "${REGRA[i]}" ] && [ "${REGRASRC[i]}" != "none" ] && echo "**Regra:** ${REGRA[i]}"
    echo
  done
}

all_escopos() {
  local i ee
  declare -A seen
  for ((i=0; i<N; i++)); do
    IFS=',' read -ra _ee <<< "${EFF_ESCOPO[i]}"
    for ee in "${_ee[@]}"; do [ -n "$ee" ] && seen["$ee"]=1; done
  done
  printf '%s\n' "${!seen[@]}" | sort
}

vigente_filename() { echo "DECISIONS-VIGENTE-$(printf '%s' "$1" | tr '/' '-').md"; }

# ============================================================================
# 5) CHECKS DE QUALIDADE c1..c12 (WARN — nenhum FAIL nesta fase; ver GRANDFATHER)
# ============================================================================
nv() { echo $((10#${1:-0})); }   # valor numérico seguro (evita "008" ser lido como octal)

# dias entre duas datas ISO YYYY-MM-DD, SEM fork (nem `date`, nem subshell) — chamado em loop
# de hook síncrono (c10 já registra que grep -r em ~1GB foi gargalo; aqui o gargalo seria
# processo por saga). Resultado em $_DA234_DIAS; "" se alguma data não parsear.
_da234_epoch_dias() {  # Howard Hinnant days_from_civil
  local y=${1:0:4} m=${1:5:2} d=${1:8:2}
  y=$((10#$y)); m=$((10#$m)); d=$((10#$d))
  [ "$m" -le 2 ] && y=$((y-1))
  local era=$(( (y >= 0 ? y : y-399) / 400 ))
  local yoe=$((y - era*400)) mp=$(( (m + 9) % 12 ))
  local doy=$(( (153*mp + 2)/5 + d - 1 ))
  local doe=$(( yoe*365 + yoe/4 - yoe/100 + doy ))
  _DA234_EPOCH=$(( era*146097 + doe ))
}
_da234_dias_entre() {
  _DA234_DIAS=""
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return
  [[ "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return
  _da234_epoch_dias "$1"; local e1="$_DA234_EPOCH"
  _da234_epoch_dias "$2"; local e2="$_DA234_EPOCH"
  _DA234_DIAS=$((e2 - e1))
}

run_quality_checks() {
  local dir="$1" warn=0
  local sagas_conf="${ADAS_SAGAS_CONF:-$HOME/.adas/sagas.conf}"
  local i
  # c1: teto de corpo (120 WARN / 300 seria FAIL — ainda não ligado)
  for ((i=0; i<N; i++)); do
    [ "$(nv "${RAWNUM[i]}")" -le "$GRANDFATHER" ] && continue
    [ "${CORPOLINES[i]}" -gt 120 ] && { echo "WARN c1: ${KEY[i]} corpo com ${CORPOLINES[i]} linhas (teto 120)"; warn=1; }
  done
  # c2: paste de terminal
  for ((i=0; i<N; i++)); do
    [ "$(nv "${RAWNUM[i]}")" -le "$GRANDFATHER" ] && continue
    [ "${HASPASTE[i]}" = "1" ] && { echo "WARN c2: ${KEY[i]} parece ter paste de terminal — evidência vai pro anexo"; warn=1; }
  done
  # c3: slug fora do sagas.conf sem prefixo nova/
  if [ -f "$sagas_conf" ]; then
    for ((i=0; i<N; i++)); do
      [ -z "${SAGA[i]}" ] && continue
      IFS=',' read -ra _sg <<< "${SAGA[i]}"
      local sgv
      for sgv in "${_sg[@]}"; do
        [[ "$sgv" == nova/* ]] && continue
        grep -qE "^${sgv}\||[|,]${sgv}(,|\$)" "$sagas_conf" 2>/dev/null || { echo "WARN c3: ${KEY[i]} usa saga '$sgv' fora do sagas.conf (use 'nova/$sgv' se for nova)"; warn=1; }
      done
    done
  fi
  # c4: número duplicado NOVO (ambos > grandfather)
  declare -A cnt
  for ((i=0; i<N; i++)); do cnt["${RAWNUM[i]}"]=$(( ${cnt["${RAWNUM[i]}"]:-0} + 1 )); done
  local k
  for k in "${!cnt[@]}"; do
    [ "${cnt[$k]}" -gt 1 ] && [ "$(nv "$k")" -gt "$GRANDFATHER" ] && { echo "WARN c4: DA-$k duplicada (número novo, não é o caso grandfathered DA-012)"; warn=1; }
  done
  # c5: tags obrigatórias (escopo, saga, Regra) — só DA nova
  for ((i=0; i<N; i++)); do
    [ "$(nv "${RAWNUM[i]}")" -le "$GRANDFATHER" ] && continue
    local falt=""
    [ -z "${ESCOPO[i]}" ] && falt+="escopo "
    [ -z "${SAGA[i]}" ] && falt+="saga "
    [ "${REGRASRC[i]}" != "regra" ] && falt+="Regra "
    [ -n "$falt" ] && { echo "WARN c5: ${KEY[i]} sem tag(s) obrigatória(s): $falt"; warn=1; }
  done
  # c6: lição com caminho ou nome próprio
  local nomes="$HOME/.adas/nomes-proprios.txt"
  for ((i=0; i<N; i++)); do
    local l="${LICAO[i]}"; [ -z "$l" ] && continue
    if [[ "$l" == *"~/"* || "$l" == *"/home/"* || "$l" == *".sh"* || "$l" == *".py"* || "$l" == *"scripts/"* ]]; then
      echo "WARN c6: ${KEY[i]} Lição parece regra disfarçada (caminho/extensão): ${l:0:80}"; warn=1
    elif [ -f "$nomes" ] && grep -qFf "$nomes" <<< "$l" 2>/dev/null; then
      echo "WARN c6: ${KEY[i]} Lição cita nome próprio: ${l:0:80}"; warn=1
    fi
  done
  # c7: cabeça com Histórico incompleto vs consolida:
  for ((i=0; i<N; i++)); do
    [ -z "${CONSOLIDA[i]}" ] && continue
    IFS=',' read -ra _cons <<< "${CONSOLIDA[i]}"
    local miss="" c
    for c in "${_cons[@]}"; do
      c="$(printf '%s' "$c" | sed 's/^[ \t]*//;s/[ \t]*$//;s/^DA-//')"
      [[ ",${HISTORICO[i]}," == *",DA-$c,"* ]] || miss+="DA-$c "
    done
    [ -n "$miss" ] && { echo "WARN c7: ${KEY[i]} (cabeça) tem consolida: sem linha correspondente no Histórico: $miss"; warn=1; }
  done
  # c9: saga com >=3 rodadas após a cabeça
  local slug
  for slug in "${SAGA_SLUGS[@]}"; do
    [ -z "${SAGA_HEAD_IDX[$slug]:-}" ] && continue
    local r; r="$(saga_rodadas_depois_da_cabeca "$slug")"
    [ "$r" -ge 3 ] && { echo "WARN c9: saga $slug tem $r rodadas depois da cabeça — hora de nova cabeça"; warn=1; }
  done
  # c10: NA-/slug citado fora do lugar (scripts, claude-tg-tmux, skills, axon) — UMA
  # passada só (alternação de todos os slugs) em vez de N greps recursivos (era o
  # gargalo: 37 sagas × grep -r em ~1GB deixava o hook (síncrono) lento demais).
  if [ "${#SAGA_SLUGS[@]}" -gt 0 ]; then
    local paths=()
    for p in "$HOME/scripts" "$HOME/claude-tg-tmux" "$HOME/.claude/skills" "$HOME/axon"; do [ -d "$p" ] && paths+=("$p"); done
    if [ "${#paths[@]}" -gt 0 ]; then
      local altpat; altpat="$(printf '%s\n' "${SAGA_SLUGS[@]}" | paste -sd'|')"
      local hits
      hits="$(grep -rloE --include='*.sh' --include='*.md' --include='*.js' --include='*.py' \
        --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist \
        "NA-(${altpat})" "${paths[@]}" 2>/dev/null)"
      if [ -n "$hits" ]; then
        local f slugshit
        while IFS= read -r f; do
          slugshit="$(grep -ohE "NA-(${altpat})" "$f" 2>/dev/null | sort -u | tr '\n' ' ')"
          echo "WARN c10: $f cita ${slugshit}— NA não tem identidade fora de DECISIONS-SAGAS.md"; warn=1
        done <<< "$hits"
      fi
    fi
  fi
  # c11: número citado que não existe no diário (exceto DA-024, fantasma conhecida)
  local dec="$dir/DECISIONS.md"
  declare -A exists
  for ((i=0; i<N; i++)); do exists["$(nv "${RAWNUM[i]}")"]=1; done
  local cited unknown=""
  for cited in $(grep -oE 'DA-[0-9]+' "$dec" 2>/dev/null | sort -u); do
    [ "$cited" = "DA-024" ] && continue
    local num; num="$(nv "${cited#DA-}")"
    [ -z "${exists[$num]:-}" ] && unknown+="$cited "
  done
  [ -n "$unknown" ] && { echo "WARN c11: citações a número inexistente no diário: $unknown"; warn=1; }
  # c12: 3ª rodada da mesma saga sem `supersede:`/`consolida:` PRÓPRIA em <=7 dias — aviso
  # PREVENTIVO (DA-234). Irmão do c9, mesma matéria-prima (saga_members_sorted), mede OUTRA
  # coisa: c9 vê a consolidação atrasada DEPOIS que a cabeça já existe; este vê o padrão ANTES
  # dela existir. "3 rodadas e a 4ª já resolve (consolida/supersede)" é ritmo saudável — não
  # avisa. SÓ avisa saga AINDA EM ABERTO (sem consolida:/supersede: própria até o fim do
  # diário) — assim que a cabeça aparece, mesmo tarde, o run vira história e cala (o aviso
  # preventivo não tem mais o que prevenir; sinalizar retroativamente é alarme sem ação
  # possível, treina o operador a ignorar). Não mexe em saga_rodadas_depois_da_cabeca nem no c9.
  for slug in "${SAGA_SLUGS[@]}"; do
    # atalho barato ANTES do sort (fork de sort/cut): saga com <3 membros nunca chega em tally=3.
    local -a _c12_raw=(${SAGA_MEMBERS[$slug]:-})
    [ "${#_c12_raw[@]}" -lt 3 ] && continue
    local -a _c12_membros=($(saga_members_sorted "$slug"))
    local tally=0 run_start="" trig="" trig_dias="" idx
    for idx in "${_c12_membros[@]}"; do
      if [ -n "${CONSOLIDA[idx]}" ] || [ -n "${SUPERSEDE[idx]}" ]; then
        # resolvida (mesmo que tardia) = história, não alarme — silencia e reseta o run.
        tally=0; run_start=""; trig=""; trig_dias=""
        continue
      fi
      [ "$tally" = 0 ] && run_start="$idx"
      tally=$((tally+1))
      if [ "$tally" = 3 ]; then
        local dstart dend
        dstart="${DATATAG[run_start]:-${BODYDATA[run_start]:-}}"
        dend="${DATATAG[idx]:-${BODYDATA[idx]:-}}"
        # ponytail: janela ancorada só no 1º membro do run; se ele cair fora de 7d mas um
        # sub-trio mais recente dentro do mesmo run coubesse, não detecta — sem caso real hoje.
        _da234_dias_entre "$dstart" "$dend"
        if [ -n "$_DA234_DIAS" ] && [ "$_DA234_DIAS" -le 7 ]; then trig="$idx"; trig_dias="$_DA234_DIAS"; else trig=""; trig_dias=""; fi
      fi
    done
    if [ -n "$trig" ]; then
      echo "WARN c12: saga $slug — ${KEY[trig]} foi a 3ª rodada sem supersede:/consolida: em ${trig_dias}d (ainda sem resolver, $tally rodada(s)) — vá na raiz antes da 4ª"
      warn=1
    fi
  done
  return 0
}

# ============================================================================
# 6) COMANDOS
# ============================================================================
usage() {
  echo "uso: da-index.sh update|check [dir]"
  echo "     da-index.sh sagas [--escopo a,b] [--projeto nome] [dir]"
  echo "     da-index.sh list [--escopo a,b] [--saga slug] [--vigentes] [--desde AAAA-MM-DD] [dir]"
  echo "     da-index.sh show DA-NNN|--saga slug|--anexos DA-NNN [dir]"
  echo "     da-index.sh export-saga slug [dir]"
  exit 2
}

# regenera o conteúdo entre <!-- da-sagas-start/end --> de um arquivo (ADAS.md);
# no-op se o arquivo não existe ou não tem os marcadores (nada a fazer, sem erro).
splice_sagas_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -qF '<!-- da-sagas-start -->' "$file" 2>/dev/null || return 0
  local tmp; tmp="$(mktemp)"
  awk '
    /<!-- da-sagas-start -->/ { print; f=1; next }
    /<!-- da-sagas-end -->/ { f=0; print; next }
    !f { print }
  ' "$file" > "$tmp"
  # injeta o bloco logo após a linha de start (dentro do arquivo temporário)
  local tmp2; tmp2="$(mktemp)"
  awk -v blockfile="$2" '
    { print }
    /<!-- da-sagas-start -->/ { while ((getline line < blockfile) > 0) print line }
  ' "$tmp" > "$tmp2"
  rm -f "$tmp"
  printf '%s' "$tmp2"
}

cmd_update() {
  local dir="${1:-$DA_DIR_DEFAULT}"
  [ -f "$dir/DECISIONS.md" ] || { echo "✗ da-index: $dir/DECISIONS.md não existe"; exit 2; }
  load_records "$dir"; group_sagas
  local tmp; tmp="$(mktemp)"; build_index "$dir" > "$tmp" || { rm -f "$tmp"; echo "✗ da-index: geração do índice falhou"; exit 1; }
  mv "$tmp" "$dir/DECISIONS-INDEX.md"
  tmp="$(mktemp)"; build_sagas_md > "$tmp"; mv "$tmp" "$dir/DECISIONS-SAGAS.md"
  tmp="$(mktemp)"; build_licoes > "$tmp"; mv "$tmp" "$dir/DECISIONS-LICOES.md"
  local esc
  for esc in $(all_escopos); do
    tmp="$(mktemp)"; build_vigente_for_escopo "$esc" > "$tmp"; mv "$tmp" "$dir/$(vigente_filename "$esc")"
  done
  if [ -f "$dir/ADAS.md" ] && grep -qF '<!-- da-sagas-start -->' "$dir/ADAS.md" 2>/dev/null; then
    local blk; blk="$(mktemp)"; build_sagas_block "" > "$blk"
    local spliced; spliced="$(splice_sagas_block "$dir/ADAS.md" "$blk")"
    if [ -n "$spliced" ] && [ -f "$spliced" ]; then mv "$spliced" "$dir/ADAS.md"; fi
    rm -f "$blk"
  fi
  echo "✓ da-index: INDEX ($N DAs) · SAGAS (${#SAGA_SLUGS[@]} sagas, $(printf '%s\n' "${SAGA_SLUGS[@]}" | while read -r s; do [ "$(saga_members_sorted "$s" | wc -l)" -ge 2 ] && echo x; done | wc -l) com 2+ DAs) · LICOES · VIGENTE-*"
  run_quality_checks "$dir"
}

cmd_check() {
  local dir="${1:-$DA_DIR_DEFAULT}"
  [ -f "$dir/DECISIONS-INDEX.md" ] || { echo "✗ da-index: $dir/DECISIONS-INDEX.md NÃO EXISTE — rode: bash scripts/da-index.sh update"; exit 1; }
  load_records "$dir"; group_sagas
  local tmpdir; tmpdir="$(mktemp -d)"
  build_index "$dir" > "$tmpdir/INDEX"
  build_sagas_md > "$tmpdir/SAGAS"
  build_licoes > "$tmpdir/LICOES"
  local esc rc=0
  for esc in $(all_escopos); do build_vigente_for_escopo "$esc" > "$tmpdir/VIGENTE-$(printf '%s' "$esc" | tr '/' '-')"; done

  if ! cmp -s "$tmpdir/INDEX" "$dir/DECISIONS-INDEX.md"; then
    echo "✗ da-index: DECISIONS-INDEX.md DIVERGE do DECISIONS.md"; diff "$dir/DECISIONS-INDEX.md" "$tmpdir/INDEX" 2>/dev/null | head -10; rc=1
  fi
  if [ -f "$dir/DECISIONS-SAGAS.md" ] && ! cmp -s "$tmpdir/SAGAS" "$dir/DECISIONS-SAGAS.md"; then
    echo "✗ da-index: DECISIONS-SAGAS.md DIVERGE"; diff "$dir/DECISIONS-SAGAS.md" "$tmpdir/SAGAS" 2>/dev/null | head -10; rc=1
  elif [ ! -f "$dir/DECISIONS-SAGAS.md" ]; then echo "✗ da-index: DECISIONS-SAGAS.md NÃO EXISTE"; rc=1; fi
  if [ -f "$dir/DECISIONS-LICOES.md" ] && ! cmp -s "$tmpdir/LICOES" "$dir/DECISIONS-LICOES.md"; then
    echo "✗ da-index: DECISIONS-LICOES.md DIVERGE"; rc=1
  elif [ ! -f "$dir/DECISIONS-LICOES.md" ]; then echo "✗ da-index: DECISIONS-LICOES.md NÃO EXISTE"; rc=1; fi
  for esc in $(all_escopos); do
    local fn; fn="$(vigente_filename "$esc")"
    if [ -f "$dir/$fn" ] && ! cmp -s "$tmpdir/VIGENTE-$(printf '%s' "$esc" | tr '/' '-')" "$dir/$fn"; then
      echo "✗ da-index: $fn DIVERGE"; rc=1
    elif [ ! -f "$dir/$fn" ]; then echo "✗ da-index: $fn NÃO EXISTE"; rc=1; fi
  done
  if [ -f "$dir/ADAS.md" ] && grep -qF '<!-- da-sagas-start -->' "$dir/ADAS.md" 2>/dev/null; then
    build_sagas_block "" > "$tmpdir/ADASBLK"
    local spliced; spliced="$(splice_sagas_block "$dir/ADAS.md" "$tmpdir/ADASBLK")"
    if [ -n "$spliced" ] && [ -f "$spliced" ] && ! cmp -s "$spliced" "$dir/ADAS.md"; then
      echo "✗ da-index: ADAS.md (bloco de sagas) DIVERGE"; rc=1
    fi
    rm -f "$spliced"
  fi
  rm -rf "$tmpdir"

  run_quality_checks "$dir"
  if [ "$rc" = 0 ]; then echo "✓ da-index: todos os gerados sincronizados com DECISIONS.md"; fi
  exit "$rc"
}

cmd_sagas() {
  local escopo="" projeto="" dir="$DA_DIR_DEFAULT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --escopo) escopo="$2"; shift 2 ;;
      --projeto) projeto="$2"; escopo="${escopo:+$escopo,}projeto/$2"; shift 2 ;;
      *) dir="$1"; shift ;;
    esac
  done
  load_records "$dir"; group_sagas
  build_sagas_block "$escopo"
}

cmd_list() {
  local escopo="" saga_f="" vigentes=0 desde="" dir="$DA_DIR_DEFAULT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --escopo) escopo="$2"; shift 2 ;;
      --saga) saga_f="$2"; shift 2 ;;
      --vigentes) vigentes=1; shift ;;
      --desde) desde="$2"; shift 2 ;;
      *) dir="$1"; shift ;;
    esac
  done
  load_records "$dir"; group_sagas
  local i
  for ((i=0; i<N; i++)); do
    if [ -n "$escopo" ]; then
      local match=0 fe se
      IFS=',' read -ra _fe <<< "$escopo"; IFS=',' read -ra _se <<< "${EFF_ESCOPO[i]}"
      for fe in "${_fe[@]}"; do for se in "${_se[@]}"; do [ "$se" = "$fe" ] && match=1; done; done
      [ "$match" = 0 ] && continue
    fi
    if [ -n "$saga_f" ]; then
      [[ ",${EFF_SAGA[i]}," == *",$saga_f,"* ]] || continue
    fi
    if [ "$vigentes" = 1 ]; then
      [ -n "$(mark_of "$i")" ] && continue
    fi
    if [ -n "$desde" ]; then
      local d="${DATATAG[i]:-${BODYDATA[i]}}"
      [[ "$d" < "$desde" ]] && continue
    fi
    index_line_for "$i"
  done
}

collapse_paste() {
  awk '
    function is_paste_start(l) {
      return (l ~ /^commit [0-9a-f]{40}$/) || (index(l,"Efficiency meter")>0) || \
             (index(l,"────")>0) || (index(l,"━━━━")>0) || (index(l,"════")>0) || (index(l,"░░░░")>0) || \
             (index(l,"▓▓▓▓")>0) || (index(l,"█████")>0)
    }
    function is_prose(l) { return (l ~ /^\*\*[^*]+:?\*\*/) || (l ~ /^### /) }
    {
      if (!inpaste && is_paste_start($0)) { inpaste=1; skipped=0 }
      if (inpaste) {
        if (is_prose($0)) {
          if (skipped>0) print "  [... bloco de paste omitido (" skipped " linhas) ...]"
          inpaste=0; print; next
        }
        skipped++; next
      }
      print
    }
    END { if (inpaste && skipped>0) print "  [... bloco de paste omitido (" skipped " linhas) ...]" }
  '
}

cmd_show() {
  local dir="$DA_DIR_DEFAULT" mode="da" arg=""
  case "${1:-}" in
    --saga) mode="saga"; arg="$2"; dir="${3:-$DA_DIR_DEFAULT}" ;;
    --anexos) mode="anexos"; arg="$2"; dir="${3:-$DA_DIR_DEFAULT}" ;;
    *) mode="da"; arg="$1"; dir="${2:-$DA_DIR_DEFAULT}" ;;
  esac
  [ -z "$arg" ] && usage
  load_records "$dir"
  case "$mode" in
    da)
      local i found=-1
      for ((i=0; i<N; i++)); do [ "${KEY[i]}" = "$arg" ] && { found=$i; break; }; done
      [ "$found" = -1 ] && { echo "✗ da-index show: $arg não encontrada"; exit 1; }
      local start="${LINE[found]}" end
      if [ $((found+1)) -lt "$N" ]; then end=$(( ${LINE[$((found+1))]} - 1 )); else end='$'; fi
      sed -n "${start},${end}p" "$dir/DECISIONS.md" | collapse_paste
      ;;
    saga)
      group_sagas
      build_sagas_md | awk -v s="## NA-$arg" 'index($0,s)==1{f=1} f{print; if($0=="" && started)exit; if(f)started=1} f && /^## NA-/ && $0!=s && started{exit}'
      ;;
    anexos)
      local d2="$dir/DECISIONS-anexos/$arg"
      [ -d "$d2" ] && ls -la "$d2" || echo "(sem anexos para $arg)"
      ;;
  esac
}

cmd_export_saga() {
  local slug="$1" dir="${2:-$DA_DIR_DEFAULT}"
  load_records "$dir"; group_sagas
  [ -z "${SAGA_MEMBERS[$slug]:-}" ] && { echo "✗ export-saga: saga '$slug' não existe ou tem 0 membros"; exit 1; }
  local estado; estado="$(saga_estado "$slug")"
  [ "$estado" = "encerrada" ] && { echo "✗ export-saga: saga '$slug' está encerrada — não exporta"; exit 1; }
  local head="${SAGA_HEAD_IDX[$slug]:-}"; local src="$head"
  [ -z "$src" ] && src="$(saga_regra_source_idx "$slug")"
  {
    echo "## ${TITLE[$src]}"
    [ -n "${REGRA[$src]}" ] && [ "${REGRASRC[$src]}" != "none" ] && echo "**Regra:** ${REGRA[$src]}"
    [ -n "${MOTIVO[$src]}" ] && echo "**Motivo:** ${MOTIVO[$src]}"
    [ -n "${TRADEOFF[$src]}" ] && echo "**Trade-off:** ${TRADEOFF[$src]}"
  } | sed -E 's/DA-[0-9]+[a-z]?[–-]DA-[0-9]+[a-z]?/[decisões internas]/g; s/DA-[0-9]+[a-z]?/[decisão interna]/g; s/  +/ /g'
}

MODE="${1:-}"; shift || true
case "$MODE" in
  update) cmd_update "$@" ;;
  check) cmd_check "$@" ;;
  sagas) cmd_sagas "$@" ;;
  list) cmd_list "$@" ;;
  show) cmd_show "$@" ;;
  export-saga) cmd_export_saga "$@" ;;
  *) usage ;;
esac
