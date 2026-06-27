#!/usr/bin/env bash
# check-secrets — GATE de segurança (ADAS · faixa seguranca-acesso). BLOQUEIA segredo entrando no repo.
# O hook avisa na EDIÇÃO; este BLOQUEIA no COMMIT/DEPLOY. Pré-commit por padrão (conteúdo STAGED).
#   bash scripts/check-secrets.sh            # staged (pré-commit)
#   bash scripts/check-secrets.sh --all      # toda a árvore tracked
#   bash scripts/check-secrets.sh --dir src  # um diretório
# Gate: "precommit": "bash scripts/check-secrets.sh"  ·  no deploy junto dos outros check-*.
set -uo pipefail

mode="staged"; dir="."
while [ $# -gt 0 ]; do
  case "$1" in
    --all) mode="all" ;;
    --dir) mode="dir"; dir="${2:-.}"; shift ;;
  esac; shift
done

# alta confiança → BLOCK (token GitHub, chave privada, AWS, Slack, Google API)
HI='ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|gh[osu]_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}|AIza[0-9A-Za-z_-]{35}'
# heurística key=value → WARN (pode ser falso-positivo)
LO='(api[_-]?key|secret|passwd|password|access[_-]?token|auth[_-]?token)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9/_+.-]{16,}'

block=0; warn=0
env_tracked(){ grep -E '(^|/)\.env($|\.[^/]*)$' | grep -vE '\.env\.(example|sample|template)$'; }

if [ "$mode" = "staged" ] && [ -d .git ]; then
  if git diff --cached --name-only 2>/dev/null | env_tracked >/dev/null; then
    echo "✗ [BLOCK] .env sendo commitado — ponha no .gitignore (use .env.example SEM valores)"; block=1
  fi
  added=$(git diff --cached -U0 2>/dev/null | grep '^+' | grep -v '^+++' || true)
  hits=$(printf '%s\n' "$added" | grep -nEi "$HI" || true)
  [ -n "$hits" ] && { echo "✗ [BLOCK] possível SEGREDO no conteúdo staged:"; printf '%s\n' "$hits" | sed 's/^/    /' | head -8; block=1; }
  warns=$(printf '%s\n' "$added" | grep -Ei "$LO" || true)
  [ -n "$warns" ] && { echo "• [warn] credencial key=value no staged — confirme se não é segredo"; warn=1; }
else
  base="$dir"; [ "$mode" = "all" ] && base="."
  list=$(git -C "$base" ls-files 2>/dev/null)
  [ -z "$list" ] && list=$(cd "$base" 2>/dev/null && find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)
  printf '%s\n' "$list" | env_tracked >/dev/null && { echo "✗ [BLOCK] .env tracked no repo (use .env.example)"; block=1; }
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    p="$base/$f"; [ -f "$p" ] || continue
    case "$f" in *node_modules/*|*.min.*|*.lock|*/.git/*) continue ;; esac
    h=$(grep -nEi "$HI" "$p" 2>/dev/null || true)
    [ -n "$h" ] && { echo "✗ [BLOCK] possível SEGREDO em $f:"; printf '%s\n' "$h" | sed 's/^/    /' | head -4; block=1; }
  done <<EOF
$list
EOF
fi

if [ "$block" -ne 0 ]; then echo; echo "✗ check-secrets: segredo detectado — NÃO commitar. Se já vazou, ROTACIONE o segredo."; exit 1; fi
if [ "$warn" -ne 0 ]; then echo; echo "⚠ check-secrets: avisos (acima) — revise"; exit 0; fi
echo "✓ check-secrets: nenhum segredo de alta confiança detectado"
