#!/usr/bin/env bash
# update.sh — atualiza o MOTOR do ADAS a partir do repo público.
#   bash host/update.sh            # mostra o que muda e pede confirmação
#   bash host/update.sh --yes      # sem pergunta (automação)
#   bash host/update.sh --check    # só mostra; não muda nada
#
# O que troca: o clone deste repo (git merge --ff-only) e os hooks do host (re-roda install.sh, que
# faz backup do settings.json em .bak-adas antes do merge). O que NUNCA toca: DECISIONS.md, CONDUCT.md,
# .specs/, fixtures locais (~/.adas/fixtures), cards/grafo compilados, repos governados.
# Para os repos governados (repos.conf), só LISTA quais têm scripts/ diferentes do skeleton novo;
# copiar é decisão de quem cuida do repo (o skeleton pode ter sido adaptado lá).
# Clone com mudança local ou fora do fast-forward → aborta sem mexer em nada.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="ask"; case "${1:-}" in --yes) MODE="yes";; --check) MODE="check";; "") ;; *) echo "uso: update.sh [--yes|--check]"; exit 2;; esac
cd "$DIR" || exit 1
git rev-parse --git-dir >/dev/null 2>&1 || { echo "✗ $DIR não é um clone git do adas"; exit 1; }
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "✗ o clone tem mudança local não commitada — resolva antes (nada foi alterado):"; git status --short --untracked-files=no; exit 1
fi
br="$(git rev-parse --abbrev-ref HEAD)"
git fetch -q origin "$br" 2>/dev/null || { echo "✗ sem acesso ao remoto (nada foi alterado)"; exit 1; }
up="origin/$br"
if [ "$(git rev-parse HEAD)" = "$(git rev-parse "$up")" ]; then
  echo "✓ ADAS já está na última versão ($(cat VERSION 2>/dev/null || echo '?'))"; exit 0
fi
git merge-base --is-ancestor HEAD "$up" || { echo "✗ o clone divergiu de $up (commit local) — não dá fast-forward; nada foi alterado"; exit 1; }

echo "ADAS $(cat VERSION 2>/dev/null || echo '?') → $(git show "$up:VERSION" 2>/dev/null || echo '?')"
echo "── novidades (CHANGELOG):"
git diff HEAD "$up" -- CHANGELOG.md | sed -n 's/^+\([^+]\)/\1/p' | head -40
echo "── arquivos do motor que mudam:"
git diff --stat HEAD "$up" -- host skeleton skeleton-v4 VERSION | tail -40
[ "$MODE" = "check" ] && { echo "(--check: nada alterado)"; exit 0; }
if [ "$MODE" = "ask" ]; then
  printf 'Aplicar? [s/N] '; read -r r || r=""
  case "$r" in s|S|sim|y|Y|yes) ;; *) echo "cancelado — nada alterado"; exit 0;; esac
fi
git merge -q --ff-only "$up" || { echo "✗ merge falhou — clone intacto"; exit 1; }
bash "$DIR/host/install.sh" || { echo "✗ install.sh falhou — o settings.json tem backup em ~/.claude/settings.json.bak-adas"; exit 1; }
echo "✓ ADAS $(cat VERSION) instalado"

conf="$HOME/.claude/adas/repos.conf"
if [ -f "$conf" ]; then
  while IFS= read -r repo; do
    case "$repo" in ''|\#*) continue;; esac
    [ -d "$repo/scripts" ] || continue
    dif=""
    for f in "$DIR"/skeleton/scripts/*; do
      b="$(basename "$f")"; [ -f "$repo/scripts/$b" ] && ! cmp -s "$f" "$repo/scripts/$b" && dif="$dif $b"
    done
    [ -n "$dif" ] && echo "• $repo: scripts/ diferente do skeleton novo:$dif (copiar é decisão do repo)"
  done < "$conf"
fi
exit 0
