#!/usr/bin/env bash
# da-index.sh — índice do DECISIONS.md que NASCE junto com a DA.
#
# O problema que resolve: DECISIONS.md é append-only e cresce sem teto (no caso real que
# gerou isto: 163 DAs, ~244k tokens). Consultar "isso já foi decidido?" exigiria ler tudo —
# então ninguém lê, e decisões são violadas por desconhecimento. O índice é a versão que
# CABE no contexto (1 linha por DA); o integral permanece intocado — o índice APONTA,
# nunca substitui. NÃO compacta, NÃO resume, NÃO altera uma linha do corpo das DAs.
#
# Mecanismo (a entrada nasce COM a DA, não depois): o hook PostToolUse
# .claude/hooks/da-index-hook.sh roda `update` no ATO de qualquer edição do DECISIONS.md —
# não depende de boa vontade de quem anexa. Anexou por fora do hook (echo >>, sed)?
# O `check` (chamado pelo check-adas, check 10) ACUSA a divergência — nunca passa batido.
#
# uso: da-index.sh update [dir]   # (re)gera DECISIONS-INDEX.md a partir de DECISIONS.md
#      da-index.sh check  [dir]   # regenera em tmp e compara; divergência = exit 1 barulhento
# [dir] = onde vivem DECISIONS.md e DECISIONS-INDEX.md (default: cwd).
#
# Determinístico: mesmo DECISIONS.md ⇒ mesmo índice byte a byte (update é idempotente e
# serve de regeneração em lote/backfill). Supersede é detectado por TEXTO, conservador —
# relação que o texto não afirma NÃO é marcada:
#   · "Supersedida/superseded por/pela DA-NNN" (na própria DA ou no índice embutido) → 🔄
#   · "supersede ... DA-NNN" sem qualificador e sem negação ("NÃO supersede") → 🔄
#   · com qualificador (PARCIAL, "a linha", "o escopo", "a regra", "o critério", "no campo")
#     ou "corrige o escopo", ou "DA-X ... passa(m) a `escopo:" → ½ alterada por (parcial)
set -uo pipefail

MODE="${1:-}"; DIR="${2:-.}"
DEC="$DIR/DECISIONS.md"; IDX="$DIR/DECISIONS-INDEX.md"
[ "$MODE" = update ] || [ "$MODE" = check ] || { echo "uso: da-index.sh update|check [dir]"; exit 2; }
[ -f "$DEC" ] || { echo "✗ da-index: $DEC não existe"; exit 2; }

gen() {
  awk '
    function flush() {
      if (cur != "") { title[cur]=t; esc[cur]=e; dec[cur]=d; fp[cur]=f0; ord[++n]=cur }
      t=""; e=""; d=""; f0=""; wantdec=0
    }
    function refs_in(s, seg,  m, out) {  # todos os DA-NNN de s, separados por espaço
      out=""
      while (match(s, /DA-[0-9]+/)) { out=out " " substr(s, RSTART, RLENGTH); s=substr(s, RSTART+RLENGTH) }
      return out
    }
    function mark(kind, targets, by,  k, a, i) {
      k=split(targets, a, " ")
      for (i=1; i<=k; i++) if (a[i] != "" && a[i] != "DA-" by) {
        if (kind=="sup") sup[a[i]]=by; else if (!(a[i] in sup)) par[a[i]]=by
      }
    }
    # ---- índice embutido/preâmbulo (antes da 1ª DA): só auto-marcadores explícitos
    /^## DA-[0-9]+/ { inbody=1 }
    !inbody && /^- \*\*DA-[0-9]+\*\*/ && /[Ss]upersed[a-z]* (pela|por) DA-[0-9]+/ {
      match($0, /DA-[0-9]+/); self=substr($0, RSTART, RLENGTH)
      rest=substr($0, RSTART+RLENGTH)
      if (match(rest, /[Ss]upersed[a-z]* (pela|por) DA-[0-9]+/)) {
        seg=substr(rest, RSTART, RLENGTH); match(seg, /DA-[0-9]+/)
        sup[self]=substr(seg, RSTART+3, RLENGTH-3)
      }
    }
    # ---- cabeçalho de DA
    /^## DA-[0-9]+ — / {
      flush()
      match($0, /DA-[0-9]+/); cur=substr($0, RSTART, RLENGTH)
      t=$0; sub(/^## DA-[0-9]+ — /, "", t)   # sub() e não offset: o em-dash é multibyte
      bl=0
      next
    }
    cur == "" { next }
    # ---- corpo da DA corrente
    {
      line=$0; bl++
      # escopo declarado (DA-131 do caso real: `escopo: produto` LOGO SOB o título —
      # só nas 3 primeiras linhas; menção a escopo no meio do corpo não é declaração)
      if (e=="" && bl <= 3 && match(line, /`?escopo: ?[^` ]+/)) {
        e=substr(line, RSTART, RLENGTH); sub(/^`?escopo: ?/, "", e)
      }
      # uma linha do que decide: 1ª linha após o rótulo Decisão; fallback = 1ª linha "de prosa"
      if (wantdec && line !~ /^[[:space:]]*$/ && length(line) >= 15 && line !~ /^[([]/) { d=line; wantdec=0 }
      if (d=="" && (line ~ /^### Decis/ || line ~ /^\*\*Decis[^*]*\*\*[[:space:]]*$/)) wantdec=1
      if (d=="" && !wantdec && match(line, /^\*\*Decis[^*]*\*\*[[:space:]]*:?[[:space:]]*/) && length(line) > RLENGTH) d=substr(line, RLENGTH+1)
      if (f0=="" && line !~ /^[[:space:]]*$/ && line !~ /^(\*\*Status|\*\*Data|`?escopo:|>|#|---)/) f0=line
      # supersede/alteração — por TEXTO, mesma linha, conservador
      if (line ~ /(NÃO|não|nao|Não) supersede/) next
      if (match(line, /[Ss]upersed(ida|ed)[a-z]* (pela|por) DA-[0-9]+/)) {
        seg=substr(line, RSTART, RLENGTH); match(seg, /DA-[0-9]+/)
        sup[cur]=substr(seg, RSTART+3, RLENGTH-3)
        next
      }
      if (match(line, /[Ss]upersede[a-z]*/)) {
        seg=substr(line, RSTART)
        if (match(seg, /[;.]/)) seg=substr(seg, 1, RSTART-1)   # só até o fim da oração
        r=refs_in(seg)
        if (r != "") {
          if (seg ~ /(PARCIAL|parcial|a linha|o escopo|a regra|o crit[eé]rio|no campo)/) mark("par", r, substr(cur,4))
          else mark("sup", r, substr(cur,4))
        }
        next
      }
      if (match(line, /corrige o escopo[a-z ]* d[aeo][a-z]* DA-[0-9]+/) || (line ~ /passam? a `?escopo:/ && line ~ /DA-[0-9]+/)) {
        mark("par", refs_in(line), substr(cur,4))
      }
    }
    END {
      flush()
      for (i=1; i<=n; i++) {
        c=ord[i]
        st=""
        if (c in sup)      st=" · 🔄 SUPERSEDIDA por DA-" sup[c]
        else if (c in par) st=" · ½ alterada por DA-" par[c]
        sc=""; if (esc[c] != "") sc=" · escopo: " esc[c]
        dl=dec[c]; if (dl=="") dl=fp[c]
        gsub(/^[[:space:]*>-]+|[[:space:]]+$/, "", dl); gsub(/\*\*/, "", dl)
        if (length(dl) > 140) { dl=substr(dl, 1, 137); sub(/[^ ]*$/, "", dl); dl=dl "..." }
        printf "- %s%s%s — %s%s\n", c, sc, st, title[c], (dl=="" ? "" : " — " dl)
      }
    }
  ' "$DEC"
}

build() {
  local n sha
  n="$(grep -c '^## DA-[0-9]' "$DEC")"
  sha="$(sha256sum "$DEC" | cut -c1-16)"
  {
    echo "# Índice de Decisões — GERADO de DECISIONS.md (NÃO EDITE À MÃO)"
    echo "# Regenerar: bash scripts/da-index.sh update · Conferir: bash scripts/da-index.sh check"
    echo "# Sem tag = vigente · 🔄 SUPERSEDIDA (íntegra) · ½ alterada (parcial — o resto vale) · o texto INTEGRAL das DAs segue no DECISIONS.md"
    echo "# fonte: $n DAs · sha256(DECISIONS.md)=$sha"
    echo
    gen
  }
}

case "$MODE" in
  update)
    tmp="$(mktemp)"; build > "$tmp" || { rm -f "$tmp"; echo "✗ da-index: geração falhou"; exit 1; }
    mv "$tmp" "$IDX"
    echo "✓ da-index: $IDX ($(grep -c '^- DA-' "$IDX") entradas)"
    ;;
  check)
    [ -f "$IDX" ] || { echo "✗ da-index: $IDX NÃO EXISTE — o índice não nasceu; rode: bash scripts/da-index.sh update"; exit 1; }
    tmp="$(mktemp)"; build > "$tmp"
    if cmp -s "$tmp" "$IDX"; then rm -f "$tmp"; echo "✓ da-index: índice sincronizado com DECISIONS.md"; exit 0; fi
    echo "✗ da-index: DECISIONS-INDEX.md DIVERGE do DECISIONS.md — DA anexada por fora do hook, ou índice editado à mão."
    echo "  Conserto: bash scripts/da-index.sh update   (diferença abaixo)"
    diff "$IDX" "$tmp" | head -10
    rm -f "$tmp"; exit 1
    ;;
esac
