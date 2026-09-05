#!/usr/bin/env bash
# check-adas — AUTO-AUDITORIA do próprio ADAS (PASSO 8). O ADAS governa o ADAS.
# Pega o modo de falha nº1 desses sistemas: a derivação .specs → faixas → ADAS.md
# rotar em SILÊNCIO (o doc descola da realidade). Genérico — roda em qualquer ADAS.
# Use no CI/pre-commit. WARN por padrão; frontmatter quebrado = BLOCK (faixa sem
# trigger não dispara). Não precisa de _template: já funciona out-of-the-box.
set -uo pipefail

# --seal (DA-165): roda a auditoria E grava a PROVA de que ela rodou —
# .adas/install-check (timestamp UTC · skeleton-version · veredito · contagem).
# O selo é versionado (é prova, não cache). Sem ele, o check 11 acusa.
SEAL=0; [ "${1:-}" = "--seal" ] && SEAL=1

SKILLS_DIR="${SKILLS_DIR:-.claude/skills}"
SPECS_DIR="${SPECS_DIR:-.specs}"
ADAS="${ADAS:-ADAS.md}"
DECISIONS="${DECISIONS:-DECISIONS.md}"
warn=0; block=0; notes=0
note(){ echo "• $*"; notes=$((notes+1)); }

# 1) PLACEHOLDER não preenchido → bootstrap incompleto (WARN)
# Conta só docs preenchíveis (.md das faixas/ADAS/DECISIONS/AGENTS + .css dos tokens da .specs): --include exclui o
# engine adas-check/*.js (que tem "check-<faixa>.js" no help, não é placeholder a preencher); --exclude-dir=_template
# exclui o template (placeholder POR DESIGN — modelo p/ faixas novas vindo do repo canônico; o local é removido no
# fim do bootstrap, ver AGENTS.md item 7). Coerente com a varredura 4 (md+css, -not _template).
if grep -rqlE --include="*.md" --include="*.css" --exclude-dir=_template "<PLACEHOLDER>|<faixa>|<NNN>|<PROJETO>|<nome>" "$SPECS_DIR" "$SKILLS_DIR" "$ADAS" "$DECISIONS" AGENTS.md 2>/dev/null; then
  note "PLACEHOLDER ainda presente — bootstrap incompleto (preencha)"; warn=1
fi

# 2-pré) PROPRIEDADE: governado × dependência — por SINAL DETECTÁVEL, nunca por lista
# mantida à mão (lista morre na primeira skill nova; regra que depende de alguém lembrar
# é a que falha). Caso real: 491 avisos contra skills de TERCEIRO (gstack, gsd-*) que não
# podemos consertar — verificador que grita sobre o inconsertável ensina a ser ignorado.
# Cadeia (1º sinal decide; CONFLITO → governado = audita, o lado seguro):
#   a) root é repo git e a skill está TRACKED → GOVERNADO (commitar = adotar; fork commitado audita)
#   b) skill tem .git próprio/ancestral dentro de SKILLS_DIR → DEPENDÊNCIA (o dono é o outro repo;
#      sobrevive a update do pacote sem ação humana)
#   c) SKILL.md cita procedência nossa (.specs/, DA-NNN, "extraído de") → GOVERNADO (auto-declarada
#      por construção do template — check 3 cobra exatamente isso)
#   d) 1º componente do caminho citado no ADAS.md → GOVERNADO (adotada; o ADAS.md já é regenerado
#      por obrigação do protocolo — não é cadastro novo)
#   e) sem NENHUMA evidência de posse → DEPENDÊNCIA — contada e DECLARADA no veredito (nunca
#      silenciosa; ADAS_CHECK_DEPS=1 exibe os achados delas como informação, sem warn/block)
GOV=(); DEP=()
_git_root=0; [ -d .git ] && command -v git >/dev/null 2>&1 && _git_root=1
while IFS= read -r f; do
  sd="$(dirname "$f")"; own=""
  if [ "$_git_root" = 1 ] && [ -n "$(git ls-files -- "$sd" 2>/dev/null | head -1)" ]; then
    own=g
  else
    p="$sd"
    while [ -n "$p" ] && [ "$p" != "$SKILLS_DIR" ] && [ "$p" != "." ] && [ "$p" != "/" ]; do
      [ -e "$p/.git" ] && { own=d; break; }
      p="$(dirname "$p")"
    done
  fi
  if [ -z "$own" ]; then
    if grep -qiE "extra(í|i)do de|\.specs/|DA-[0-9]" "$f" 2>/dev/null; then
      own=g
    else
      top="${sd#"$SKILLS_DIR"/}"; top="${top%%/*}"
      { [ -n "$top" ] && grep -qw -- "$top" "$ADAS" 2>/dev/null; } && own=g || own=d
    fi
  fi
  if [ "$own" = g ]; then GOV+=("$f"); else DEP+=("$f"); fi
done < <(find "$SKILLS_DIR" -name SKILL.md -not -path "*/_template/*" 2>/dev/null)

# Os checks por-faixa (2, 2b, 3) como funções: mesmo exame, dois destinos —
# governada acusa (warn/block), dependência só INFORMA quando pedido.
fm_issue() {  # frontmatter name+description (senão NÃO dispara)
  local fm; fm="$(awk '/^---[[:space:]]*$/{c++; next} c==1{print} c>=2{exit}' "$1" 2>/dev/null)"
  { printf '%s\n' "$fm" | grep -q "^name:" && printf '%s\n' "$fm" | grep -q "^description:"; } \
    || echo "SEM frontmatter name/description (não vai disparar)"
}
thin_issue() {  # trigger magro (piso mecânico do description)
  local fm desc thin n_trig n_symp
  fm="$(awk '/^---[[:space:]]*$/{c++; next} c==1{print} c>=2{exit}' "$1" 2>/dev/null)"
  desc="$(printf '%s\n' "$fm" | awk '/^description:/{flag=1} flag && /^[a-z_]+:/ && !/^description:/{flag=0} flag{print}' | tr -d '\n')"
  [ -z "$desc" ] && return 0  # ausência total já é caso do fm_issue
  thin=""
  [ "${#desc}" -lt 400 ] && thin="${thin}<400 chars; "
  n_trig=$(printf '%s' "$desc" | tr ',;' '\n' | grep -c .)
  [ "$n_trig" -lt 12 ] && thin="${thin}só ${n_trig} gatilhos (<12); "
  printf '%s' "$desc" | grep -qi "SEMPRE" || thin="${thin}sem cláusula 'use SEMPRE que'; "
  printf '%s' "$desc" | grep -qi "MESMO" || thin="${thin}sem negação 'MESMO que não peça'; "
  n_symp=$(printf '%s' "$desc" | grep -o "'" | wc -l)
  [ "$n_symp" -lt 4 ] && thin="${thin}<2 sintomas citados ('...'); "
  # COBERTURA DE ATOR (task 20260905-008, achado pós-DA-229): gatilho entre aspas
  # é convenção deste ADAS pra fala do DONO — mas o dono não é o único que
  # estabelece regra. Faixa com vários gatilhos-fala-do-dono e ZERO menção a um
  # ato do AGENTE por conta própria é cega pro caso em que o agente decide
  # sozinho: a regra nasce e nada dispara (DA-198/199/205).
  if [ "$n_symp" -ge 4 ] && ! printf '%s' "$desc" | grep -qiE \
    "\bagente (decide|estabelece|institui|cria|adota)\b|\bpor conta pr[oó]pria\b|\bsozinho\b|\beu vou\b|\bsem (o )?(dono|usu[aá]rio) (pedir|falar|mandar)\b"; then
    thin="${thin}COBERTURA DE ATOR: só fala do dono, nenhum ato do agente citado; "
  fi
  [ -n "$thin" ] && echo "TRIGGER MAGRO: ${thin}— engordar (sinônimos+sintomas+vocabulário real do usuário)"
  return 0
}
prov_issue() {  # procedência (invariante sem origem = chute)
  grep -qiE "extra(í|i)do de|\.specs/|DA-[0-9]" "$1" \
    || echo "sem procedência (cite .specs/ ou DA-NNN)"
}

# 2) toda faixa GOVERNADA tem frontmatter name+description → BLOCK
for f in ${GOV[@]+"${GOV[@]}"}; do
  m="$(fm_issue "$f")"; [ -n "$m" ] && { note "FAIXA $m: $f"; block=1; }
done

# 2b) TRIGGER MAGRO (só GOVERNADAS) → WARN. O description é o ROTEADOR: magro = faixa
# que nunca acorda (modo de falha nº2, depois do drift silencioso). Piso MECÂNICO:
# ≥400 chars, ≥12 gatilhos, cláusula "SEMPRE", negação "MESMO", ≥2 sintomas citados.
# Heurística, não censo: passar no piso ≠ trigger bom, mas reprovar = certeza de magro.
for f in ${GOV[@]+"${GOV[@]}"}; do
  m="$(thin_issue "$f")"; [ -n "$m" ] && { note "$m em $f"; warn=1; }
done

# 3) faixa GOVERNADA sem PROCEDÊNCIA (invariante sem origem = chute) → WARN
for f in ${GOV[@]+"${GOV[@]}"}; do
  m="$(prov_issue "$f")"; [ -n "$m" ] && { note "faixa $m: $f"; warn=1; }
done

# 2-dep) DEPENDÊNCIAS: fora da auditoria, mas NUNCA em silêncio — o que não se audita
# se DECLARA (trocar ruído por ponto cego seria repetir o defeito original). Trigger
# magro de terceiro não é inofensivo (capacidade paga que nunca acorda) — é problema
# de AÇÃO alheia: dependência INFORMA quando perguntado, governada GRITA sempre.
if [ "${#DEP[@]}" -gt 0 ]; then
  dep_probs=0
  # procedência é convenção NOSSA — cobrá-la de terceiro seria achado falso; só
  # frontmatter quebrado e trigger magro valem como achado de dependência.
  for f in ${DEP[@]+"${DEP[@]}"}; do
    m="$(fm_issue "$f")$(thin_issue "$f")"
    [ -n "$m" ] && dep_probs=$((dep_probs+1))
    if [ "${ADAS_CHECK_DEPS:-0}" = "1" ]; then
      m="$(fm_issue "$f")";   [ -n "$m" ] && echo "  · dep: $m — $f"
      m="$(thin_issue "$f")"; [ -n "$m" ] && echo "  · dep: $m — $f"
    fi
  done
  note "ℹ ${#DEP[@]} skill(s) de DEPENDÊNCIA (terceiros) fora da auditoria, ${dep_probs} com achados — reporte upstream; ADAS_CHECK_DEPS=1 exibe (classificação por sinal: git/procedência/ADAS.md, sem lista)"
fi

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

# 9) ENFORCEMENT LIGADO? → WARN. O modo de falha nº0, antes de todos os outros: o sistema
# inteiro DESLIGADO. Este check auditava higiene de doc e nunca perguntava "eu estou ATIVO?" —
# uma instalação-fantasma (ADAS.md copiado à mão, zero hooks) passava com warns cosméticos.
# Verificador que aprova sistema desligado é pior que não ter verificador: dá confiança falsa.
# Tudo WARN (runtime host é opcional; doc-only pode ser escolha consciente) — mas dito ALTO.
# 9a) JIT do repo (PASSO 6 — a parte mais forte do ADAS). Só se o repo usa Claude Code (.claude/).
if [ -d .claude ]; then
  if [ ! -f .claude/hooks/adas-inject.sh ]; then
    note "ENFORCEMENT: sem .claude/hooks/adas-inject.sh — o JIT (PASSO 6) não existe; a governança é só documento"; warn=1
  elif ! grep -q "adas-inject" .claude/settings.json 2>/dev/null; then
    note "ENFORCEMENT: adas-inject.sh existe mas não está registrado em .claude/settings.json — o hook nunca dispara"; warn=1
  fi
fi
# 9b) runtime host (PASSO 11) — a escada da meia-instalação, do fantasma ao ativo.
# Só onde há Claude Code na máquina (~/.claude); em CI não existe e o bloco cala.
if [ -d "$HOME/.claude" ]; then
  _rconf="${ADAS_REPOS_CONF:-$HOME/.claude/adas/repos.conf}"
  if [ ! -f "$HOME/.claude/hooks/adas-activate.sh" ]; then
    note "ENFORCEMENT: runtime host NÃO instalado nesta máquina — sem reinjeção (compaction/subagent/hub), sessão longa esquece a governança. Opcional, mas pule CONSCIENTE. Instalar: bash host/install.sh $PWD (repo canônico samyrwendel/adas)"; warn=1
  elif ! grep -q "adas-activate\|adas-route" "$HOME/.claude/settings.json" 2>/dev/null; then
    note "ENFORCEMENT: MEIA-INSTALAÇÃO — hooks adas-*.sh copiados mas ausentes de ~/.claude/settings.json (nunca disparam); rode host/install.sh de novo"; warn=1
  elif ! grep -qxF "$PWD" "$_rconf" 2>/dev/null; then
    note "ENFORCEMENT: runtime instalado mas este repo está FORA do repos.conf ($_rconf) — reinjeção não cobre este repo; rode: bash host/install.sh $PWD"; warn=1
  fi
fi

# 10) ÍNDICE DE DECISÕES sincronizado → WARN. O índice nasce COM a DA (hook PostToolUse
# da-index-hook.sh roda o update no ato da edição); se divergiu, alguém anexou por fora
# do hook (echo >>, sed) ou editou o índice à mão — tem que ACUSAR, nunca passar batido.
# O DECISIONS.md integral é append-only e intocado; o índice é derivado e regenerável.
if [ -f "$DECISIONS" ] && [ -f scripts/da-index.sh ]; then
  if [ ! -f DECISIONS-INDEX.md ]; then
    note "sem DECISIONS-INDEX.md — o índice não nasceu; rode: bash scripts/da-index.sh update"; warn=1
  elif ! bash scripts/da-index.sh check . >/dev/null 2>&1; then
    note "DECISIONS-INDEX.md DIVERGE do $DECISIONS (DA anexada por fora do hook?) — rode: bash scripts/da-index.sh update"; warn=1
  fi
fi

# 11) SELO DE INSTALAÇÃO (DA-165): o check tem que ter RODADO alguma vez e deixado prova.
# "Rode o check e finalize limpo" era exortação em prompt — classe que a DA-017 já julgou.
# Custo: ler UM arquivo; nada re-executa por sessão. Selo obsoleto (esqueleto atualizou
# depois da prova) também acusa — a prova envelhece junto com o que ela provou.
if [ "$SEAL" != "1" ]; then
  if [ ! -f .adas/install-check ]; then
    note "sem .adas/install-check — a instalação nunca foi PROVADA; rode: bash scripts/check-adas.sh --seal (DA-165)"; warn=1
  else
    sealed_v="$(awk -F': ' '/^skeleton-version:/{print $2}' .adas/install-check 2>/dev/null | tr -d '[:space:]')"
    cur_v="$(cut -c1-7 .adas/skeleton-version 2>/dev/null | head -1 | tr -d '[:space:]')"
    if [ -n "$cur_v" ] && [ "$sealed_v" != "$cur_v" ]; then
      note "selo OBSOLETO (provado em '${sealed_v:-?}', esqueleto agora '$cur_v') — re-sele: bash scripts/check-adas.sh --seal"; warn=1
    fi
  fi
fi

# 12) SEIS PORTAS DE SEGURANÇA DO APP (DA-189) → WARN. Todo projeto que nasce com
# ADAS nasce com estas seis obrigações: chave no front, .env no histórico (mecânicas,
# scripts/check-secrets.sh), validação-só-na-tela, arquivo-público, erro-fala-demais,
# rate-limit (com prova, scripts/check-app-security.sh + .adas/seguranca-app.json).
# Este check não REPETE a lógica dos dois scripts — RODA os dois (quando existem) e
# resume o veredito de cada porta numa linha só, pro relatório do projeto nunca
# esconder "faltam seis verificações" atrás de dois comandos que ninguém lembra de rodar.
_porta_mec() {  # $1 = "porta 1" ou "porta 2" (rótulo que check-secrets.sh imprime)
  local marca="$1" out="$2"
  if printf '%s\n' "$out" | grep -q "✗ \[BLOCK\] \[$marca"; then echo "FALHA"
  elif printf '%s\n' "$out" | grep -q "✓ \[$marca"; then echo "PASSA"
  else echo "?"; fi
}
if [ ! -d .git ]; then
  # Sem .git, `check-secrets.sh --all` cai no fallback `find .` da árvore INTEIRA
  # (git ls-files vazio) — em ~/ (raiz de governança, não repo) isso varre TUDO
  # embaixo (clones de projeto, node_modules, .venv…) e travou minutos na task
  # 20260904-005. Sem controle de versão não há "árvore do projeto" bem definida
  # pra escopar; reporta honesto em vez de arriscar o check inteiro pendurado.
  p1="sem .git (não verificável com segurança aqui)"; p2="$p1"
elif [ -f scripts/check-secrets.sh ]; then
  sec_out="$(bash scripts/check-secrets.sh --all 2>/dev/null)"
  p1="$(_porta_mec "porta 1" "$sec_out")"; p2="$(_porta_mec "porta 2" "$sec_out")"
else
  p1="sem check-secrets.sh"; p2="sem check-secrets.sh"
fi
if [ -f scripts/check-app-security.sh ]; then
  asec_out="$(bash scripts/check-app-security.sh 2>/dev/null)"
else
  asec_out=""
fi
_porta_prova() {  # $1 = rótulo que check-app-security.sh usa (ex.: "porta 3")
  local marca="$1"
  if [ ! -f scripts/check-app-security.sh ]; then echo "sem check-app-security.sh"; return; fi
  if printf '%s\n' "$asec_out" | grep -q "✗ \[seis portas\].*($marca)"; then echo "FALHA (sem prova válida)"
  elif printf '%s\n' "$asec_out" | grep -q "adas: débito.*($marca)"; then echo "débito"
  elif printf '%s\n' "$asec_out" | grep -q "✓ \[seis portas\].*($marca): N/A"; then echo "N/A (justificado)"
  elif printf '%s\n' "$asec_out" | grep -q "✓ \[seis portas\].*($marca)"; then echo "PASSA"
  else echo "débito"
  fi
}
p3="$(_porta_prova "porta 3")"; p4="$(_porta_prova "porta 4")"
p5="$(_porta_prova "porta 5")"; p6="$(_porta_prova "porta 6")"
note "SEIS PORTAS (DA-189): 1 chave-no-front=$p1 · 2 env-historico=$p2 · 3 validacao-servidor=$p3 · 4 arquivo-publico=$p4 · 5 erro-fala-demais=$p5 · 6 rate-limit=$p6"
for pv in "$p1" "$p2" "$p3" "$p4" "$p5" "$p6"; do
  case "$pv" in PASSA|*"justificado"*) ;; *) warn=1 ;; esac
done

# veredito
v="ok"; [ "$warn" -ne 0 ] && v="warn"; [ "$block" -ne 0 ] && v="block"
if [ "$SEAL" = "1" ]; then
  mkdir -p .adas
  { echo "selado: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "skeleton-version: $(cut -c1-7 .adas/skeleton-version 2>/dev/null | head -1 | tr -d '[:space:]')"
    echo "veredito: $v"
    echo "avisos: $notes"
  } > .adas/install-check
  echo "🔏 selo gravado em .adas/install-check (veredito: $v, $notes aviso(s)) — versione-o: é a prova, não cache"
fi
if [ "$block" -ne 0 ]; then echo "✗ check-adas: faixa quebrada (frontmatter) — corrija antes de seguir"; exit 1; fi
if [ "$warn" -ne 0 ]; then echo "⚠ check-adas: avisos de higiene do ADAS (acima) — não bloqueia"; exit 0; fi
echo "✓ check-adas: ADAS íntegro (faixas com trigger+procedência, sem drift, DAs resolvidas)"
