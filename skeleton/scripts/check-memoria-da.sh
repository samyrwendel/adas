#!/usr/bin/env bash
# check-memoria-da.sh — mecanização da DA-199 (governanca-adas / DA-205).
#
# Separa, POR CONTEÚDO, dois tipos de nota de memória de agente:
#   • REGRA DE TRABALHO (normativa, generalizável a outro agente) → pertence ao
#     diário de decisões (~/DECISIONS.md), NÃO à memória privada. Memória privada
#     não governa ninguém além de quem a escreveu (DA-198/199).
#   • PREFERÊNCIA / IDENTIDADE / CONTEXTO (como o dono é, como ele gosta de ser
#     respondido, formato, idioma, ponteiro pra DA) → pertence à memória. NÃO barrar.
#
# Sinal prático (DA-199): a nota manda alguém FAZER/DEIXAR DE FAZER algo no trabalho
# (eixo A, normativo) E é sobre o PROCESSO/ferramenta que outro agente compartilha
# (eixo W, trabalho)? Se sim nos dois e NÃO é sobre interação/identidade (eixo P) → RULE.
#
# ponytail: classificador heurístico por regex de 3 eixos (A normativo, W trabalho,
# P preferência). Teto conhecido: prosa livre engana regex; erra pra CLEAN quando P
# aparece (protege preferência — falso-positivo em preferência é falha grave, DA-199).
# Upgrade se o índice de acerto cair: mover pra classificador LLM chamado no scan de
# domingo (nunca no hook de escrita, que tem de ser instantâneo e offline).
#
# Uso:
#   check-memoria-da.sh classify            # lê conteúdo no stdin → "LABEL\treason"
#   check-memoria-da.sh scan <dir> [--only RULE|MAYBE] [--quiet]
#       # varre *.md do dir; lista flagged (RULE+MAYBE) com motivo; --quiet = só o path
# LABEL ∈ RULE (é DA disfarçada) | MAYBE (ambíguo, dono decide) | CLEAN (memória ok).
# Sempre sai 0 (fail-open) exceto erro de uso.
set -uo pipefail

# --- eixo A: linguagem normativa/imperativa (manda fazer / deixar de fazer) ---
RE_A='\bnunca\b|\bjamais\b|\bsempre\b|antes de |depois de |toda vez|sempre que|\bobrigat[oó]ri|\bprecisa\b|tem que |\bdeve\b|não pode|nao pode|\bproibid|\bevit(e|ar)\b|\bconferir\b|\bverificar\b|\bchecar\b|\bgarantir\b|não esque|nao esque|\bregistr(ar|e)\b|\bnão \b.*\bsem \b'

# --- eixo W: domínio de TRABALHO/processo (vale pra outro agente) ---
# NÃO inclui "DA-NNN"/"decisions"/"diário de decisões": citar uma DA é o comportamento
# CERTO da DA-199 (deixar o ponteiro) — não pode virar sinal de INFRAÇÃO. W mira AÇÃO
# de processo (task/commit/deploy/test/bus/…), não a meta-referência ao registro.
RE_W='\btask\b|\btarefa\b|injet|despach|delegar|\bcommit|\bpush\b|deploy|\bPR\b|\bmerge\b|\bbranch\b|rebase|\bbus\b|worker|\bagente\b|frota|pytest|\bteste?s?\b|su[ií]te|\brepo\b|reposit|\bscript\b|\bcron\b|\bhook\b|escopo|requeue|axon-|\bstash\b|git add|worktree|headless|timeout|\bmodelo\b|\bclaim\b|heartbeat|dispatch|\bmanifest\b|\bpre-commit\b|\bgate\b'

# --- eixo P: preferência / identidade / interação (memória é o lugar certo) ---
# NÃO inclui "samyr/dono/chefe": nesses arquivos eles são ATRIBUIÇÃO ("Samyr, 04/09:")
# — quem deu a ordem, não o ASSUNTO da nota. Regra ditada pelo dono ainda é regra de
# trabalho. P mira o TEMA (como responder, formato, idioma, identidade), não o autor.
RE_P='se chama|chamar de|\bprefere\b|\bgosta\b|responder|resposta|\bidioma\b|portugu[eê]s|\bpt-?br\b|\btom\b|\bformato\b|\bemoji\b|markdown|\bvoz\b|[aá]udio|timezone|\bfuso\b|carteira|\bwallet\b|apelido|identidade|persona|arqu[eé]tipo|estilo|humor|sarcas|saudaç|cumpriment'

# remove o frontmatter YAML (---...---) pra não classificar por description/metadata
strip_fm() {
  awk 'NR==1 && $0=="---"{fm=1;next} fm && $0=="---"{fm=0;next} !fm{print}'
}

classify_stream() {
  local body a="" w="" p=""
  body="$(strip_fm)"
  a="$(printf '%s' "$body" | grep -ioE "$RE_A" | sort -u | head -3 | paste -sd, -)"
  w="$(printf '%s' "$body" | grep -ioE "$RE_W" | sort -u | head -3 | paste -sd, -)"
  p="$(printf '%s' "$body" | grep -ioE "$RE_P" | sort -u | head -3 | paste -sd, -)"
  local label reason
  if [ -n "$a" ] && [ -n "$w" ] && [ -z "$p" ]; then
    label=RULE
  elif [ -n "$a" ] && [ -n "$w" ]; then
    label=MAYBE   # tem sinal de regra de trabalho MAS também de preferência → dono decide
  else
    label=CLEAN
  fi
  reason="normativo[${a:-—}] trabalho[${w:-—}]"
  [ -n "$p" ] && reason="$reason preferência[${p}]"
  printf '%s\t%s\n' "$label" "$reason"
}

cmd="${1:-}"
case "$cmd" in
  classify)
    classify_stream
    ;;
  scan)
    dir="${2:-}"; only=""; quiet=0
    shift 2 2>/dev/null || true
    while [ $# -gt 0 ]; do
      case "$1" in
        --only) only="${2:-}"; shift 2 ;;
        --quiet) quiet=1; shift ;;
        *) shift ;;
      esac
    done
    [ -d "$dir" ] || { echo "✗ check-memoria-da: dir inexistente: $dir" >&2; exit 2; }
    n_rule=0; n_maybe=0; n_clean=0
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in MEMORY.md) continue ;; esac   # índice, não é nota
      out="$(classify_stream < "$f")"
      label="${out%%$'\t'*}"; reason="${out#*$'\t'}"
      case "$label" in
        RULE)  n_rule=$((n_rule+1)) ;;
        MAYBE) n_maybe=$((n_maybe+1)) ;;
        CLEAN) n_clean=$((n_clean+1)); continue ;;
      esac
      [ -n "$only" ] && [ "$label" != "$only" ] && continue
      if [ "$quiet" = "1" ]; then printf '%s\n' "$f"
      else printf '%-6s %s\n    ↳ %s\n' "$label" "$f" "$reason"; fi
    done
    [ "$quiet" = "1" ] || printf '\n[resumo] RULE=%d MAYBE=%d CLEAN=%d (de %s)\n' \
      "$n_rule" "$n_maybe" "$n_clean" "$dir" >&2
    ;;
  *)
    echo "uso: check-memoria-da.sh classify   (stdin)" >&2
    echo "     check-memoria-da.sh scan <dir> [--only RULE|MAYBE] [--quiet]" >&2
    exit 2
    ;;
esac
exit 0
