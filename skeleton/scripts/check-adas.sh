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
# Conta só docs preenchíveis (.md das faixas/ADAS/DECISIONS/AGENTS + .css dos tokens da .specs): --include exclui o
# engine adas-check/*.js (que tem "check-<faixa>.js" no help, não é placeholder a preencher); --exclude-dir=_template
# exclui o template (placeholder POR DESIGN — modelo p/ faixas novas vindo do repo canônico; o local é removido no
# fim do bootstrap, ver AGENTS.md item 7). Coerente com a varredura 4 (md+css, -not _template).
if grep -rqlE --include="*.md" --include="*.css" --exclude-dir=_template "<PLACEHOLDER>|<faixa>|<NNN>|<PROJETO>|<nome>" "$SPECS_DIR" "$SKILLS_DIR" "$ADAS" "$DECISIONS" AGENTS.md 2>/dev/null; then
  note "PLACEHOLDER ainda presente — bootstrap incompleto (preencha)"; warn=1
fi

# 2) toda faixa tem frontmatter name+description (senão NÃO dispara) → BLOCK
# (extrai o bloco entre os dois primeiros '---' — head fixo dava falso BLOCK em description longa)
while IFS= read -r f; do
  fm="$(awk '/^---[[:space:]]*$/{c++; next} c==1{print} c>=2{exit}' "$f" 2>/dev/null)"
  { printf '%s\n' "$fm" | grep -q "^name:" && printf '%s\n' "$fm" | grep -q "^description:"; } \
    || { note "FAIXA SEM frontmatter name/description: $f (não vai disparar)"; block=1; }
done < <(find "$SKILLS_DIR" -name SKILL.md -not -path "*/_template/*" 2>/dev/null)

# 2b) TRIGGER MAGRO → WARN. O description é o ROTEADOR: magro = faixa que nunca
# acorda (modo de falha nº2, depois do drift silencioso). Exortação no prompt não
# basta — piso MECÂNICO: ≥400 chars, ≥12 gatilhos (separados por ,/;), a cláusula
# pushy "SEMPRE" + a negação "MESMO", e ≥2 sintomas citados ('...' — como o
# usuário REALMENTE fala). Heurística, não censo: passar no piso ≠ trigger bom,
# mas reprovar = certeza de magro.
while IFS= read -r f; do
  fm="$(awk '/^---[[:space:]]*$/{c++; next} c==1{print} c>=2{exit}' "$f" 2>/dev/null)"
  desc="$(printf '%s\n' "$fm" | awk '/^description:/{flag=1} flag && /^[a-z_]+:/ && !/^description:/{flag=0} flag{print}' | tr -d '\n')"
  [ -z "$desc" ] && continue  # ausência total já é BLOCK no check 2
  thin=""
  [ "${#desc}" -lt 400 ] && thin="${thin}<400 chars; "
  n_trig=$(printf '%s' "$desc" | tr ',;' '\n' | grep -c .)
  [ "$n_trig" -lt 12 ] && thin="${thin}só ${n_trig} gatilhos (<12); "
  printf '%s' "$desc" | grep -qi "SEMPRE" || thin="${thin}sem cláusula 'use SEMPRE que'; "
  printf '%s' "$desc" | grep -qi "MESMO" || thin="${thin}sem negação 'MESMO que não peça'; "
  n_symp=$(printf '%s' "$desc" | grep -o "'" | wc -l)
  [ "$n_symp" -lt 4 ] && thin="${thin}<2 sintomas citados ('...'); "
  [ -n "$thin" ] && { note "TRIGGER MAGRO em $f: ${thin}— engordar (sinônimos+sintomas+vocabulário real do usuário)"; warn=1; }
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
  # 4b) working tree SUJO nas faixas/.specs — a janela onde o drift mais importa (antes do
  # commit) é invisível pro check por timestamp acima; acusa explicitamente (WARN)
  if git status --porcelain -- "$SKILLS_DIR" "$SPECS_DIR" 2>/dev/null | grep -q .; then
    note "faixa/.specs com mudança NÃO COMMITADA — commite junto com o $ADAS regenerado (mesmo commit)"; warn=1
  fi
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

# 7) NÚCLEO do runtime (PASSO 11): marcadores adas-core no ADAS.md → WARN
# Sem marcadores o adas-core.sh cai num fallback silencioso (topo do arquivo); núcleo gordo
# encarece cada reinjeção (SessionStart/SubagentStart).
if [ -f "$ADAS" ]; then
  if ! grep -q "adas-core-start" "$ADAS" 2>/dev/null; then
    note "sem marcadores <!-- adas-core-start/end --> no $ADAS — runtime host/ cai no fallback (topo do arquivo)"; warn=1
  elif ! grep -q "adas-core-end" "$ADAS" 2>/dev/null; then
    note "marcador adas-core-start SEM adas-core-end no $ADAS — núcleo vira o arquivo inteiro"; warn=1
  else
    core_n=$(sed -n '/<!-- adas-core-start -->/,/<!-- adas-core-end -->/p' "$ADAS" 2>/dev/null | wc -l | tr -d ' ')
    core_n=$((core_n>2 ? core_n-2 : 0))   # sem contar as 2 linhas de marcador
    [ "${core_n:-0}" -gt 60 ] && { note "núcleo adas-core com ${core_n} linhas (>60) — enxugue: é reinjetado a cada fronteira de contexto"; warn=1; }
  fi
fi

# 8) VERSÃO do esqueleto instalado → WARN (a cadeia canônico→installs também apodrece)
# O SETUP do bootstrap grava .adas/skeleton-version (commit curto do clone). Sem ele, não dá
# pra saber se este install está atrasado. Com ADAS_CHECK_REMOTE=1 compara com o GitHub.
if [ ! -f .adas/skeleton-version ]; then
  note "sem .adas/skeleton-version — backfill seguro (NÃO re-copie o esqueleto): sincronize os scripts com o canônico e rode: mkdir -p .adas && git ls-remote https://github.com/samyrwendel/adas HEAD | cut -c1-7 > .adas/skeleton-version"; warn=1
elif [ "${ADAS_CHECK_REMOTE:-0}" = "1" ] && command -v git >/dev/null 2>&1; then
  local_v="$(cut -c1-7 .adas/skeleton-version 2>/dev/null | head -1 | tr -d '[:space:]')"
  remote_v="$(timeout 5 git ls-remote https://github.com/samyrwendel/adas HEAD 2>/dev/null | cut -c1-7)"
  if [ -n "$remote_v" ] && [ -n "$local_v" ] && [ "$local_v" != "$remote_v" ]; then
    note "esqueleto instalado ($local_v) ≠ canônico remoto ($remote_v) — veja o que mudou no repo adas"; warn=1
  fi
fi

# veredito
if [ "$block" -ne 0 ]; then echo "✗ check-adas: faixa quebrada (frontmatter) — corrija antes de seguir"; exit 1; fi
if [ "$warn" -ne 0 ]; then echo "⚠ check-adas: avisos de higiene do ADAS (acima) — não bloqueia"; exit 0; fi
echo "✓ check-adas: ADAS íntegro (faixas com trigger+procedência, sem drift, DAs resolvidas)"
