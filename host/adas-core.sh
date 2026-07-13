#!/usr/bin/env bash
# ADAS host — builder do núcleo. Extrai a seção <!-- adas-core-start/end --> do ADAS.md do repo;
# fallback = topo do arquivo (até a 1ª faixa/invariantes ou 45 linhas). Fail-open: nunca quebra a sessão.
# Uso: adas-core.sh <repo-root>
repo="$1"
f="$repo/ADAS.md"
if [ ! -f "$f" ]; then
  printf 'ADAS ativo em %s: ADESAO > INVENCAO — reuse componente/rota/padrao que ja existe; nao invente estrutura, escopo, nomenclatura ou texto novos.\n' "$repo"
  exit 0
fi
core="$(sed -n '/<!-- adas-core-start -->/,/<!-- adas-core-end -->/p' "$f" 2>/dev/null | sed '1d;$d')"
if [ -z "$core" ]; then
  core="$(awk 'NR>45{exit} /^## (Invariantes|[0-9]+\. FAIXA)/{exit} {print}' "$f" 2>/dev/null)"
fi
[ -n "$core" ] || { printf 'ADAS ativo: leia %s antes de produzir qualquer coisa. ADESAO > INVENCAO.\n' "$f"; exit 0; }
printf '%s\n\n[ADAS %s] ATIVO EM TODA RESPOSTA nesta sessao — nao decai com o tamanho do contexto; em duvida, a regra da faixa vale. Antes de editar um dominio, leia a faixa em .claude/skills/*/SKILL.md do repo. Fonte completa: %s\n' "$core" "$(basename "$repo")" "$f"
exit 0
