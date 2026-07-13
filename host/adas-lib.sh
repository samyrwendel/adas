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

# adas_hub_header → cabeçalho multi-repo genérico (lista os repos governados)
adas_hub_header() {
  local names
  names="$(adas_repos | while IFS= read -r r; do basename "$r"; done | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  printf '[ADAS] Governanca ativa nesta maquina. Repos governados: %s — cada um tem um ADAS.md na raiz. Principio-mestre: ADESAO > INVENCAO (reusar > inventar; consolidar > reescrever; nunca regredir o que funciona). Caminho de dinheiro = seguranca: nada mockado, nunca executa irreversivel sem confirmacao. Ao trabalhar em arquivos de um desses repos, LEIA o ADAS.md daquele repo antes de produzir qualquer coisa; a regra da faixa tambem sera injetada automaticamente no instante da edicao (hook PreToolUse). Esta regra permanece ATIVA em toda a sessao, inclusive apos compactacao de contexto.\n' "$names"
}
