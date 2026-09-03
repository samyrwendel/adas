#!/usr/bin/env bash
# ADAS host — resolução de repos governados. Fonte: ~/.claude/adas/repos.conf
# (um caminho absoluto por linha; '#' comenta). Override: env ADAS_REPOS_CONF.
ADAS_CONF="${ADAS_REPOS_CONF:-$HOME/.claude/adas/repos.conf}"

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

# adas_da_layer0 <cwd> → camada 0 do diário de decisões (DA-181): 'sagas --escopo
# <conjunto>' + DECISIONS-LICOES.md inteiro. DA_LOAD=off desliga (0 tokens, cron
# mecânico); default é injetar. Fail-open: qualquer ausência = string vazia.
adas_da_layer0() {
  [ "${DA_LOAD:-index}" = "off" ] && return 0
  local cwd="$1"
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
  printf '\n[DECISIONS camada 0 — escopo %s] sagas do diário de decisões (~/DECISIONS.md). "quem decidiu?" = DA-NNN, nunca a NA. Rodadas pendentes avisadas abaixo devem ser lidas (show DA-NNN) antes de decidir na saga.\n%s\n\n%s\n' "$escopo" "$sagas" "${licoes:-}"
}

# adas_hub_header → cabeçalho multi-repo genérico (lista os repos governados)
adas_hub_header() {
  local names
  names="$(adas_repos | while IFS= read -r r; do basename "$r"; done | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  printf '[ADAS] Governanca ativa nesta maquina. Repos governados: %s — cada um tem um ADAS.md na raiz. Principio-mestre: ADESAO > INVENCAO (reusar > inventar; consolidar > reescrever; nunca regredir o que funciona). Caminho de dinheiro = seguranca: nada mockado, nunca executa irreversivel sem confirmacao. Ao trabalhar em arquivos de um desses repos, LEIA o ADAS.md daquele repo antes de produzir qualquer coisa; a regra da faixa tambem sera injetada automaticamente no instante da edicao (hook PreToolUse). Esta regra permanece ATIVA em toda a sessao, inclusive apos compactacao de contexto.\n' "$names"
}
