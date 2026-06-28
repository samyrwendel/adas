#!/usr/bin/env bash
# check-adas — AUTO-AUDITORIA do próprio ADAS (PASSO 8). O ADAS governa o ADAS.
# Pega o modo de falha nº1 desses sistemas: a derivação .specs → faixas → ADAS.md
# rotar em SILÊNCIO (o doc descola da realidade). Genérico — roda em qualquer ADAS.
# Use no CI/pre-commit. WARN por padrão; frontmatter quebrado = BLOCK (faixa sem
# trigger não dispara). Não precisa de _template: já funciona out-of-the-box.
set -uo pipefail

SKILLS_DIR="${SKILLS_DIR:-.claude/skills}"
SPECS_DIR="${SPECS_DIR:-.specs}"
ADAS="${ADAS:-ADAS.md}"
DECISIONS="${DECISIONS:-DECISIONS.md}"
warn=0; block=0
note(){ echo "• $*"; }

# 1) PLACEHOLDER não preenchido → bootstrap incompleto (WARN)
# Conta só docs preenchíveis (.md das faixas/ADAS/DECISIONS + .css dos tokens da .specs): --include exclui o
# engine adas-check/*.js (que tem "check-<faixa>.js" no help, não é placeholder a preencher); --exclude-dir=_template
# exclui o template (placeholder POR DESIGN, clonado p/ faixas novas). Coerente com a varredura 4 (md+css, -not _template).
if grep -rqlE --include="*.md" --include="*.css" --exclude-dir=_template "<PLACEHOLDER>|<faixa>|<NNN>|<PROJETO>|<nome>" "$SPECS_DIR" "$SKILLS_DIR" "$ADAS" "$DECISIONS" 2>/dev/null; then
  note "PLACEHOLDER ainda presente — bootstrap incompleto (preencha)"; warn=1
fi

# 2) toda faixa tem frontmatter name+description (senão NÃO dispara) → BLOCK
while IFS= read -r f; do
  { head -10 "$f" | grep -q "^name:" && head -14 "$f" | grep -q "^description:"; } \
    || { note "FAIXA SEM frontmatter name/description: $f (não vai disparar)"; block=1; }
done < <(find "$SKILLS_DIR" -name SKILL.md -not -path "*/_template/*" 2>/dev/null)

# 3) faixa sem PROCEDÊNCIA (invariante sem origem = chute) → WARN
while IFS= read -r f; do
  grep -qiE "extra(í|i)do de|\.specs/|DA-[0-9]" "$f" \
    || { note "faixa sem procedência (cite .specs/ ou DA-NNN): $f"; warn=1; }
done < <(find "$SKILLS_DIR" -name SKILL.md -not -path "*/_template/*" 2>/dev/null)

# 4) DRIFT: faixa/.specs commitada DEPOIS do ADAS.md → regenere (WARN, precisa git)
if [ -d .git ] && command -v git >/dev/null 2>&1; then
  adas_t=$(git log -1 --format=%ct -- "$ADAS" 2>/dev/null || echo 0)
  while IFS= read -r f; do
    ft=$(git log -1 --format=%ct -- "$f" 2>/dev/null || echo 0)
    if [ "${ft:-0}" -gt "${adas_t:-0}" ]; then
      note "DRIFT: '$f' mudou depois do $ADAS — REGENERE o $ADAS"; warn=1; break
    fi
  done < <(find "$SKILLS_DIR" "$SPECS_DIR" \( -name "*.md" -o -name "*.css" \) -not -path "*/_template/*" 2>/dev/null)
fi

# 5) DA-NNN citada nas faixas/ADAS mas ausente do DECISIONS.md → WARN
for da in $(grep -rhoE "DA-[0-9]{3}" "$SKILLS_DIR" "$ADAS" 2>/dev/null | sort -u); do
  grep -q "$da" "$DECISIONS" 2>/dev/null || { note "$da citada mas ausente do $DECISIONS"; warn=1; }
done

# 6) ÂNCORA de onboarding existe e aponta pro ADAS.md → WARN
anchor=""
for a in AGENTS.md CLAUDE.md .cursorrules; do [ -f "$a" ] && anchor="$a" && break; done
if [ -z "$anchor" ]; then
  note "sem arquivo-âncora (AGENTS.md/CLAUDE.md) — a ferramenta não descobre o ADAS sozinha"; warn=1
elif ! grep -q "ADAS.md" "$anchor" 2>/dev/null; then
  note "âncora '$anchor' não aponta pro $ADAS — adicione 'leia ADAS.md'"; warn=1
fi

# veredito
if [ "$block" -ne 0 ]; then echo "✗ check-adas: faixa quebrada (frontmatter) — corrija antes de seguir"; exit 1; fi
if [ "$warn" -ne 0 ]; then echo "⚠ check-adas: avisos de higiene do ADAS (acima) — não bloqueia"; exit 0; fi
echo "✓ check-adas: ADAS íntegro (faixas com trigger+procedência, sem drift, DAs resolvidas)"
