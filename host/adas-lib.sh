#!/usr/bin/env bash
# ADAS host — resolução de repos governados. Fonte: ~/.claude/adas/repos.conf
# (um caminho absoluto por linha; '#' comenta). Override: env ADAS_REPOS_CONF.
ADAS_CONF="${ADAS_REPOS_CONF:-$HOME/.claude/adas/repos.conf}"
ADAS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || dirname "${BASH_SOURCE[0]}")"

# ORÇAMENTO de bytes da emissão do SessionStart. O harness do Claude Code PERSISTE
# (guarda em tool-results/ e entrega ao modelo só um preview de 2 KiB) o stdout de um
# hook acima de 10 KiB (10.240 bytes). Medido nos transcripts desta máquina (05/09,
# tests/smoke.sh secção 17): maior stdout ENTREGUE inline = 10.215 B; menor stdout
# PERSISTIDO = 10.822 B → a fronteira é 10*1024. Preview = primeiros 2.048 B. Orçamos
# 9.600 B: 640 B (6%) abaixo do teto e abaixo dos 10.215 B que JÁ chegaram inteiros,
# logo toda emissão que cabe no orçamento é entrega garantida. Emissão > teto some em
# silêncio; é o defeito que este orçamento fecha. Override: env ADAS_EMIT_BUDGET.
ADAS_EMIT_BUDGET="${ADAS_EMIT_BUDGET:-9600}"

# adas_blen <str> → nº de BYTES (não chars) — o teto do harness é em bytes.
adas_blen() { LC_ALL=C printf '%s' "${1:-}" | wc -c; }

# ITEM 2b (DA-230 §6.2): ~/.claude/CLAUDE.md é a ÚNICA prosa que entra em 100% das
# sessões desta máquina, mesmo quando o cwd é o repo git de OUTRO projeto (o CLAUDE.md
# do próprio repo, se houver, não sobe até a home nesse caso — só o global sobe sempre).
# Por isso o núcleo passa a chegar por lá via @import, fora do teto de 10 KiB do hook —
# medido: @import não corta até 160 KB (47x o núcleo), ver commit. Override: testes.
ADAS_CORE_IMPORT_FILE="${ADAS_CORE_IMPORT_FILE:-$HOME/.claude/adas-core-import.md}"
ADAS_CORE_IMPORT_LINE='@adas-core-import.md'

# adas_core_import_synced <core> → 0 SÓ com PROVA de que o CLAUDE.md global já importa
# ESTE núcleo exato (linha de import presente E cache bate byte a byte). Qualquer
# divergência — linha removida, cache ausente, núcleo mudou — AUTOCURA o cache pra
# próxima sessão e retorna 1: é o FALLBACK (DA-230 nunca pode repetir o buraco de
# 03/09 — regra sumida sem chegar por nenhum canal). Fail-open: erro de I/O também é 1,
# e nesse caso o chamador emite o núcleo inline como sempre fez.
adas_core_import_synced() {
  local core="$1" claude_md="$HOME/.claude/CLAUDE.md" cached
  if [ -f "$claude_md" ] && grep -qF "$ADAS_CORE_IMPORT_LINE" "$claude_md" 2>/dev/null; then
    cached="$(cat "$ADAS_CORE_IMPORT_FILE" 2>/dev/null || true)"
    [ "$cached" = "$core" ] && return 0
  fi
  mkdir -p "$(dirname "$ADAS_CORE_IMPORT_FILE")" 2>/dev/null || true
  printf '%s\n' "$core" > "$ADAS_CORE_IMPORT_FILE" 2>/dev/null || true
  return 1
}

adas_repos() {
  [ -f "$ADAS_CONF" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$ADAS_CONF" 2>/dev/null
}

# adas_resolve <path> → imprime a raiz do repo governado que contém <path> (ou nada)
adas_resolve() {
  local p="$1" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$p" in "$r"|"$r"/*) printf '%s' "$r"; return 0 ;; esac
  done <<EOF
$(adas_repos)
EOF
  return 0
}

# adas_is_hub <dir> → 0 se <dir> é ancestral de pelo menos um repo governado
adas_is_hub() {
  local d="$1" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$r" in "$d"/*) return 0 ;; esac
  done <<EOF
$(adas_repos)
EOF
  return 1
}

# adas_da_rotas <cwd> → imprime o csv de escopos do ~/.adas/rotas.conf cujo prefixo
# bate com <cwd> (prefixo MAIS LONGO vence); vazio se nenhuma rota casar.
adas_da_rotas() {
  local cwd="$1" conf="${ADAS_ROTAS_CONF:-$HOME/.adas/rotas.conf}"
  [ -f "$conf" ] || return 0
  local best="" bestlen=-1 prefixo escopos
  while IFS='|' read -r prefixo escopos; do
    case "$prefixo" in ""|"#"*) continue ;; esac
    case "$cwd" in
      "$prefixo"|"$prefixo"/*)
        if [ "${#prefixo}" -gt "$bestlen" ]; then best="$escopos"; bestlen="${#prefixo}"; fi
        ;;
    esac
  done < "$conf"
  printf '%s' "$best"
}

# adas_da_layer0 <cwd> [budget_bytes] → camada 0 do diário (DA-181): 'sagas --escopo
# <conjunto>' + DECISIONS-LICOES.md inteiro. Cabe em [budget_bytes] (default: sem teto,
# p/ o caminho SubagentStart que usa additionalContext). PRIORIDADE DE CORTE DECLARADA:
# vigente (sagas) ANTES de histórico (lições) — as lições cedem primeiro. O que não
# couber NÃO some em silêncio: vira uma linha-ponteiro [ADAS-CORTE] com o tamanho e o
# comando pra ler o resto (DA-036 — ausência de dado tem que estar escrita). DA_LOAD=off
# desliga (0 tokens, cron mecânico). Fail-open: qualquer ausência = string vazia.
adas_da_layer0() {
  [ "${DA_LOAD:-index}" = "off" ] && return 0
  local cwd="$1" budget="${2:-1000000000}"
  local dec="$HOME/DECISIONS.md" idx="$HOME/scripts/da-index.sh"
  [ -f "$dec" ] && [ -f "$idx" ] || return 0

  local escopo=""
  if [ -n "${ADAS_PROJETO:-}" ]; then
    escopo="produto,projeto/${ADAS_PROJETO}"
    case "$ADAS_PROJETO" in claude-tg-tmux|axon|adas|"") escopo="$escopo,instância" ;; esac
  else
    escopo="$(adas_da_rotas "$cwd")"
  fi
  [ -z "$escopo" ] && escopo="produto,instância"

  local sagas licoes
  sagas="$(bash "$idx" sagas --escopo "$escopo" "$HOME" 2>/dev/null)"
  [ -f "$HOME/DECISIONS-LICOES.md" ] && licoes="$(cat "$HOME/DECISIONS-LICOES.md" 2>/dev/null)"
  [ -z "$sagas" ] && [ -z "${licoes:-}" ] && return 0

  local out used part plen ptr
  out="$(printf '\n[DECISIONS camada 0 — escopo %s] sagas do diário de decisões (~/DECISIONS.md). "quem decidiu?" = DA-NNN, nunca a NA. Rodadas pendentes avisadas abaixo devem ser lidas (show DA-NNN) antes de decidir na saga.\n' "$escopo")"
  used="$(adas_blen "$out")"

  # 1) sagas (VIGENTES) — prioridade máxima
  if [ -n "$sagas" ]; then
    part="$(printf '%s\n' "$sagas")"; plen="$(adas_blen "$part")"
    if [ $((used + plen)) -le "$budget" ]; then
      out="${out}${part}"; used=$((used + plen))
      # a linha da saga não traz mais "membros: DA-…" (item 2a, cabe mais saga
      # no orçamento) — este rodapé é COMO recuperar a lista completa; sem ele
      # o corte vira o defeito que a DA-230 proíbe (dado sumido sem dizer onde)
      local hint hlen
      hint="$(printf '\nmembros completos de uma saga: bash ~/scripts/da-index.sh list --saga <slug> ~\n')"
      hlen="$(adas_blen "$hint")"
      [ $((used + hlen)) -le "$budget" ] && { out="${out}${hint}"; used=$((used + hlen)); }
    else
      ptr="$(printf '\n[ADAS-CORTE] sagas vigentes (%d bytes) nao couberam no orcamento de %d bytes — leia com: bash ~/scripts/da-index.sh sagas --escopo %s ~\n' "$plen" "$budget" "$escopo")"
      [ $((used + $(adas_blen "$ptr"))) -le "$budget" ] && { out="${out}${ptr}"; used=$((used + $(adas_blen "$ptr"))); }
    fi
  fi
  # 2) lições (HISTÓRICO) — entra por último, cede primeiro
  if [ -n "${licoes:-}" ]; then
    part="$(printf '\n%s\n' "$licoes")"; plen="$(adas_blen "$part")"
    if [ $((used + plen)) -le "$budget" ]; then
      out="${out}${part}"; used=$((used + plen))
    else
      ptr="$(printf '\n[ADAS-CORTE] licoes/historico (~/DECISIONS-LICOES.md, %d bytes) nao couberam no orcamento de %d bytes — leia com: cat ~/DECISIONS-LICOES.md\n' "$plen" "$budget")"
      [ $((used + $(adas_blen "$ptr"))) -le "$budget" ] && { out="${out}${ptr}"; used=$((used + $(adas_blen "$ptr"))); }
    fi
  fi
  printf '%s' "$out"
}

# adas_hub_header → cabeçalho multi-repo genérico (lista os repos governados)
adas_hub_header() {
  local names
  names="$(adas_repos | while IFS= read -r r; do basename "$r"; done | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  printf '[ADAS] Governanca ativa nesta maquina. Repos governados: %s — cada um tem um ADAS.md na raiz. Principio-mestre: ADESAO > INVENCAO (reusar > inventar; consolidar > reescrever; nunca regredir o que funciona). Caminho de dinheiro = seguranca: nada mockado, nunca executa irreversivel sem confirmacao. Ao trabalhar em arquivos de um desses repos, LEIA o ADAS.md daquele repo antes de produzir qualquer coisa; a regra da faixa tambem sera injetada automaticamente no instante da edicao (hook PreToolUse). Esta regra permanece ATIVA em toda a sessao, inclusive apos compactacao de contexto.\n' "$names"
}

# adas_session_emit <cwd> → emissão COMPLETA do SessionStart cabendo em ADAS_EMIT_BUDGET
# bytes: núcleo do repo (sempre, é a REGRA) + camada 0 no orçamento restante. É o único
# lugar que monta a saída — o hook só decide o efeito colateral (.active). Sem efeito
# colateral aqui, então o teste chama esta função direto contra dados reais.
adas_session_emit() {
  local cwd="$1" repo core budget suprimido=0
  repo="$(adas_resolve "$cwd")"
  if [ -n "$repo" ]; then
    core="$(bash "$ADAS_LIB_DIR/adas-core.sh" "$repo" 2>/dev/null || true)"
    [ -n "${core:-}" ] && adas_core_import_synced "$core" && suprimido=1
  elif adas_is_hub "$cwd"; then
    core="$(adas_hub_header)"
  fi
  if [ -n "${core:-}" ] && [ "$suprimido" != 1 ]; then
    printf '%s\n' "$core"
    budget=$(( ${ADAS_EMIT_BUDGET:-9216} - $(adas_blen "$core") - 1 ))
  else
    budget=$(( ${ADAS_EMIT_BUDGET:-9216} ))
  fi
  [ "$budget" -lt 0 ] && budget=0
  adas_da_layer0 "$cwd" "$budget" 2>/dev/null || true
}
