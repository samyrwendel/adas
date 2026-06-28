#!/usr/bin/env bash
# adas-report — RELATÓRIO do estado do ADAS, com GUARDA DE HONESTIDADE (PASSO 10).
#
# Padrão importado do ponytail (github.com/DietrichGebert/ponytail, MIT): o `/ponytail-gain`
# mostra impacto medido MAS se RECUSA a imprimir número por-repo inventado (não existe baseline
# do "código que você não escreveu") — redireciona pro débito REAL. Aqui é a mesma disciplina:
# o ADAS NÃO inventa "% de aderência". Mostra só o que dá pra CONTAR de verdade (faixas, decisões,
# débito marcado, drift) e diz onde está o que NÃO é medível sem benchmark. Reforça os princípios
# "medir antes de substituir" e "nunca mascarar o não-sabido como número".
#
# Uso: scripts/adas-report.sh        (roda na raiz do projeto governado pelo ADAS)
set -uo pipefail

SKILLS_DIR="${SKILLS_DIR:-.claude/skills}"
SPECS_DIR="${SPECS_DIR:-.specs}"
ADAS="${ADAS:-ADAS.md}"
DECISIONS="${DECISIONS:-DECISIONS.md}"
SCAN_DIR="${1:-.}"
DEBT_JS="$SKILLS_DIR/adas-check/scripts/adas-debt.js"

count_or_zero(){ local n; n=$(eval "$1" 2>/dev/null); echo "${n:-0}"; }

# --- MEDÍVEL (contável de verdade) ---
faixas=$(count_or_zero "find '$SKILLS_DIR' -name SKILL.md -not -path '*/_template/*' 2>/dev/null | wc -l | tr -d ' '")
das=$(count_or_zero "grep -rhoE 'DA-[0-9]{3}' '$DECISIONS' 2>/dev/null | sort -u | wc -l | tr -d ' '")
placeholders=$(count_or_zero "grep -rlE --include='*.md' --include='*.css' --exclude-dir=_template '<PLACEHOLDER>|<faixa>|<NNN>|<PROJETO>|<nome>' '$SPECS_DIR' '$SKILLS_DIR' '$ADAS' '$DECISIONS' 2>/dev/null | wc -l | tr -d ' '")

debt="—"
if command -v node >/dev/null 2>&1 && [ -f "$DEBT_JS" ]; then
  debt=$(node "$DEBT_JS" "$SCAN_DIR" --count-only 2>/dev/null || echo "—")
fi

# saúde da governança (PASSO 8) — reusa o check-adas, não reimplementa
health="(check-adas ausente)"
if [ -f scripts/check-adas.sh ]; then
  if out=$(bash scripts/check-adas.sh 2>/dev/null); then health="$(echo "$out" | tail -1)"; else health="$(echo "$out" | tail -1)"; fi
fi

echo "┌─ ADAS · relatório ────────────────────────────────"
echo "│ MEDÍVEL (contado, não estimado):"
printf "│   faixas ativas .......... %s\n" "$faixas"
printf "│   decisões (DA-NNN) ...... %s\n" "$das"
printf "│   débito marcado (adas:) . %s\n" "$debt"
printf "│   placeholders pendentes . %s%s\n" "$placeholders" "$([ "$placeholders" != 0 ] && echo '  ⚠ bootstrap incompleto')"
echo "│   saúde (check-adas) ..... $health"
echo "│"
echo "│ NÃO MEDÍVEL aqui (e o ADAS NÃO inventa número):"
echo "│   • \"% de aderência\" / \"% de drift evitado\" — não há baseline do que a LLM"
echo "│     TERIA inventado sem as faixas. Reportar % seria chute (= mascarar o não-sabido)."
echo "│   • Pra impacto REAL, rode um benchmark A/B: mesma tarefa COM × SEM as faixas"
echo "│     e meça (LoC, custo, retrabalho). Veja o método do ponytail em benchmarks/."
echo "│   • Débito por-repo HONESTO = a contagem 'adas:' acima (o que VOCÊ deferiu),"
echo "│     não uma comparação fabricada. Liste com: node $DEBT_JS ."
echo "└───────────────────────────────────────────────────"

# exit sempre 0 — é relatório (informativo), não gate. O gate é o check-adas/check-*.sh.
exit 0
