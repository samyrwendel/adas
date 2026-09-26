#!/usr/bin/env bash
# check-secrets — GATE de segurança (ADAS · faixa seguranca-acesso). BLOQUEIA segredo entrando no repo.
# O hook avisa na EDIÇÃO; este BLOQUEIA no COMMIT/DEPLOY. Pré-commit por padrão (conteúdo STAGED).
#   bash scripts/check-secrets.sh            # staged (pré-commit)
#   bash scripts/check-secrets.sh --all      # toda a árvore tracked + porta 2 (histórico do git)
#   bash scripts/check-secrets.sh --dir src  # um diretório
#   bash scripts/check-secrets.sh --dominio  # credencial fora do domínio dono (regras em ~/.adas/credencial-dominio.conf)
# Gate: "precommit": "bash scripts/check-secrets.sh"  ·  no deploy junto dos outros check-*.
#
# PORTAS 1 e 2 das "seis portas do app" (DA-189, faixa seguranca-acesso — ver SKILL.md
# seção "Seis portas do app"): são as duas MECÂNICAS (grep puro, sem prova humana — as
# outras quatro exigem evidência e vivem em scripts/check-app-security.sh). Linhas
# marcadas "[porta 1" / "[porta 2" são o contrato que check-adas.sh lê pra montar o
# resumo das seis portas — não mude o prefixo sem atualizar os dois lados.
set -uo pipefail

mode="staged"; dir="."
while [ $# -gt 0 ]; do
  case "$1" in
    --all) mode="all" ;;
    --dominio) mode="dominio" ;;
    --dir) mode="dir"; dir="${2:-.}"; shift ;;
  esac; shift
done

# ── MODO --dominio — credencial fora do DOMÍNIO dono (DA-005 do repo adas) ─────────────────
# Arquivo de um domínio (ex.: scripts financeiros) que cita/lê a credencial de OUTRO domínio
# (ex.: o token do bot principal) é violação, esteja ou não num repo git — o gate de commit
# não vê script solto na home, por isso este modo roda no audit. As regras são da INSTÂNCIA:
#   ${CREDENCIAL_DOMINIO_CONF:-$HOME/.adas/credencial-dominio.conf}, uma linha por regra:
#   <caminho ou glob; ~ e /** aceitos> | <regex ERE proibida> | <motivo/DA>   (separador " | ")
# Não contam: linha de comentário (# no início) e `unset <VAR>` — tirar a credencial do
# ambiente é justamente o conserto. Saída aponta arquivo:linha, nunca valor.
if [ "$mode" = "dominio" ]; then
  CONF="${CREDENCIAL_DOMINIO_CONF:-$HOME/.adas/credencial-dominio.conf}"
  [ -f "$CONF" ] || { echo "✓ [domínio] sem $CONF — nenhuma regra de domínio declarada"; exit 0; }
  dblock=0; nreg=0; narq=0; declare -A _re_de=()
  while IFS= read -r _l; do
    case "$_l" in ''|'#'*) continue ;; esac
    # separador é " | " (com espaços): a regex pode ter alternância a|b sem espaço
    case "$_l" in *' | '*' | '*) ;; *) echo "• [domínio] regra inválida ignorada (formato: caminho | regex | motivo): $_l"; continue ;; esac
    _g="${_l%% | *}"; _rest="${_l#* | }"; _re="${_rest%% | *}"; _mo="${_rest#* | }"
    _g="$(printf '%s' "$_g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    nreg=$((nreg + 1))
    case "$_g" in "~/"*) _g="$HOME/${_g#\~/}" ;; esac
    if [[ "$_g" == *'/**' ]]; then
      mapfile -t _fs < <(find "${_g%'/**'}" -type f 2>/dev/null)
    else
      mapfile -t _fs < <(compgen -G "$_g" 2>/dev/null)
    fi
    for _f in "${_fs[@]}"; do
      [ -f "$_f" ] || continue
      case "$_f" in *.log|*.bak*|*.md|*.json|*.pyc) continue ;; esac  # dado/log/backup não executa
      narq=$((narq + 1)); _re_de["$_f"]="$_re"
      _h=$(grep -nE -- "$_re" "$_f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(#|unset[[:space:]])' || true)
      if [ -n "$_h" ]; then
        echo "✗ [BLOCK] [domínio] ${_f/#$HOME/\~} cita credencial fora do domínio ($_mo):"
        printf '%s\n' "$_h" | cut -d: -f1 | sed 's/^/    linha /' | head -5
        dblock=1
      fi
    done
  done < "$CONF"
  # Jobs agendados (unit systemd --user e crontab) que EXECUTAM um arquivo de domínio: a
  # credencial também entra pelo AMBIENTE do job (Environment=/EnvironmentFile=/source no
  # cron), que o script não mostra — e /proc/<pid>/environ não pega cron de vida curta.
  njob=0; _jobs=""
  _job() {  # $1 = nome do job, $2 = texto do job (unit inteira ou linha do cron)
    local f; for f in "${!_re_de[@]}"; do
      printf '%s\n' "$2" | grep -qF -- "$f" || continue
      njob=$((njob + 1)); _jobs="${_jobs} $1"
      if printf '%s\n' "$2" | grep -vE '^[[:space:]]*(#|unset[[:space:]])' | grep -qE -- "${_re_de[$f]}"; then
        echo "✗ [BLOCK] [domínio] job $1 executa ${f/#$HOME/\~} com a credencial proibida no ambiente/comando"; dblock=1
      fi
      return
    done
  }
  for _u in "$HOME"/.config/systemd/user/*.service; do
    [ -f "$_u" ] || continue
    _t="$(cat "$_u" 2>/dev/null)"
    _ef="$(printf '%s\n' "$_t" | sed -n 's/^EnvironmentFile=-\{0,1\}//p' | sed "s|%h|$HOME|g")"
    _job "$(basename "$_u")" "$_t
EnvironmentFile-aponta:$_ef"
  done
  if _ct="$(crontab -l 2>&1)"; then
    while IFS= read -r _c; do
      case "$_c" in ''|'#'*) continue ;; esac
      _job "cron:$(printf '%s' "$_c" | cut -c1-40)…" "$_c"
    done <<< "$_ct"
  elif ! printf '%s' "$_ct" | grep -qi "no crontab"; then
    echo "• [domínio] crontab ILEGÍVEL aqui ($(printf '%s' "$_ct" | head -1)) — jobs de cron NÃO verificados"
  fi
  echo "• [domínio] $njob job(s) agendado(s) executam arquivo de domínio:${_jobs:- nenhum}"
  if [ "$dblock" -ne 0 ]; then echo "✗ check-secrets --dominio: credencial fora do domínio dono — tire a leitura/citação (unset é permitido)"; exit 1; fi
  echo "✓ [domínio] $nreg regra(s), $narq arquivo(s) examinado(s): nenhuma credencial fora do domínio"
  exit 0
fi

# Deploy/pós-commit: nada staged → o modo staged seria um no-op VERDE (falsa garantia
# na última barreira). Cai pra varredura completa em vez de aprovar sem examinar nada.
# (Efeito aceito BY DESIGN: amend-só-mensagem/commit vazio com segredo histórico na
#  árvore passam a bloquear — "se já vazou, ROTACIONE"; use --dir pra escopo menor.)
if [ "$mode" = "staged" ] && [ -z "$(git diff --cached --name-only 2>/dev/null)" ]; then
  echo "• staged vazio — nada a examinar aí; caindo para varredura completa (--all)"
  mode="all"
fi

# alta confiança → BLOCK (token GitHub, chave privada, AWS, Slack, Google API, bot Telegram).
# Bot Telegram = <id 8-10 dígitos>:AA<33 base64url>. Caso real: o token VIVO do bot de produção
# ficou literal num .py solto e num .bak e o gate passou VERDE em --dir — não havia padrão
# pra ele, e o LO só casa o NOME da variável (TELEGRAM_BOT_TOKEN=), não o formato.
HI='ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|gh[osu]_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}|AIza[0-9A-Za-z_-]{35}|[0-9]{8,10}:AA[A-Za-z0-9_-]{33}'
# heurística key=value → WARN (pode ser falso-positivo)
LO='(api[_-]?key|secret|passwd|password|access[_-]?token|auth[_-]?token)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9/_+.-]{16,}'

# ── PORTA 1 (DA-189) — chave/token no que é servido ao NAVEGADOR ─────────────────────
# Padrões pedidos pela DA: sk- (OpenAI/Anthropic), AIza (Google), ghp_ (GitHub), AKIA
# (AWS), xox[abp]- (Slack), "Bearer <token literal>", e KEY=valor dos quatro provedores
# citados por nome. Reusa o HI de cima (mesma classe) mais o que falta pra cobrir a
# lista exata da DA.
FRONT_KEY='sk-[A-Za-z0-9]{16,}|AIza[0-9A-Za-z_-]{35}|ghp_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|xox[abp]-[0-9A-Za-z-]{10,}|[Bb]earer +[A-Za-z0-9._-]{16,}|(ELEVENLABS_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|TELEGRAM_BOT_TOKEN) *[:=] *[A-Za-z0-9]{8,}|[0-9]{8,10}:AA[A-Za-z0-9_-]{33}'
# NEXT_PUBLIC_/VITE_/REACT_APP_ resolvem em BUILD TIME — o valor vai pro bundle público
# mesmo que o código "pareça" server-side. Proibido quando o NOME da variável contém
# KEY/SECRET/TOKEN/PASS (case-insensitive): a intenção do nome já denuncia segredo.
FRONT_PREFIX='(NEXT_PUBLIC_|VITE_|REACT_APP_)[A-Z0-9_]*(KEY|SECRET|TOKEN|PASS)[A-Z0-9_]*[[:space:]]*[:=]'
# Diretórios convencionalmente SERVIDOS ao navegador (build output / templates
# renderizados). Heurística por NOME de componente do caminho — sem stack conhecida
# não dá pra fazer melhor que convenção.
SERVED_DIR_RE='(^|/)(static|build|dist|public|templates)(/|$)'

block=0; warn=0
base="$dir"; [ "$mode" = "all" ] && base="."

# ── ALLOWLIST DECLARADA — fixture conhecida, não segredo ─────────────────────────────────
# .adas/secrets-allowlist (versionado): uma linha por CAMINHO isento, no formato
#   <caminho relativo à raiz> | <motivo> | <AAAA-MM-DD>
# Só o caminho listado é isento (árvore e histórico — porta 2). Linha sem motivo ou sem data
# NÃO vale (avisa e ignora): isenção sem porquê é o gate desligado com outro nome. Caso real:
# token de teste ("Bearer test-…") numa fixture commitada acusava porta 2 em todo commit e só
# reescrever a história "resolveria". Teto declarado: um segredo REAL que entrar num arquivo já
# listado passa — por isso a lista é de caminhos de teste, curta e revisada; arquivo novo nunca
# está nela. Exceção no CÓDIGO (regex solta) é proibida: a isenção mora no arquivo, com motivo.
ALLOWLIST_FILE="${SECRETS_ALLOWLIST:-.adas/secrets-allowlist}"
allow_paths=""
if [ -f "$ALLOWLIST_FILE" ]; then
  while IFS= read -r _al; do
    case "$_al" in ''|'#'*) continue ;; esac
    _ap=$(printf '%s' "$_al" | cut -d'|' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    _am=$(printf '%s' "$_al" | cut -d'|' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    _ad=$(printf '%s' "$_al" | cut -d'|' -f3 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$_ap" ] || [ -z "$_am" ] || ! printf '%s' "$_ad" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
      echo "• allowlist: entrada INVÁLIDA ignorada (precisa de: caminho | motivo | AAAA-MM-DD): $_al"; warn=1; continue
    fi
    allow_paths="${allow_paths}${_ap}
"
  done < "$ALLOWLIST_FILE"
  [ -n "$allow_paths" ] && echo "ℹ allowlist ($ALLOWLIST_FILE): $(printf '%s' "$allow_paths" | grep -c .) caminho(s) isento(s) por motivo declarado: $(printf '%s' "$allow_paths" | tr '\n' ' ')"
fi
is_allowed() { [ -n "$allow_paths" ] && printf '%s\n' "$allow_paths" | grep -qxF -- "${1#./}"; }
# Exclusão por SUFIXO (.example/.sample/.template), não por "logo depois de .env":
# ".env.enterprise.example" (achado real ao rodar isto contra um projeto de verdade,
# task 20260904-005) tem SEGMENTO A MAIS entre ".env" e ".example" e escapava da
# exclusão antiga (\.env\.(example|...)$ exige os dois lado a lado) — virava falso
# "BLOCK .env tracked" sobre um arquivo que É o contrato (chave sem valor), não o
# segredo. Qualquer coisa que já passou pelo filtro ".env" e termina em
# example/sample/template é template, não importa quantos segmentos tem no meio.
env_tracked(){ grep -E '(^|/)\.env($|\.[^/]*)$' | grep -vE '\.(example|sample|template)$'; }
# Conteúdo de um arquivo rastreado, no modo certo: STAGED (índice, `git show :path`)
# quando ainda não commitado, ou o que está NO DISCO/tracked quando já é all/dir —
# um helper só, pra portas 1/2 não duplicarem a lógica staged×all três vezes.
_conteudo() {
  if [ "$mode" = "staged" ] && [ -d .git ]; then git show ":$1" 2>/dev/null
  else cat "$base/$1" 2>/dev/null; fi
}

if [ "$mode" = "staged" ] && [ -d .git ]; then
  if git diff --cached --name-only 2>/dev/null | env_tracked >/dev/null; then
    echo "✗ [BLOCK] .env sendo commitado — ponha no .gitignore (use .env.example SEM valores)"; block=1
  fi
  _staged_files=$(git diff --cached --name-only 2>/dev/null || true)
  _staged_chk=""; while IFS= read -r _sf; do [ -z "$_sf" ] && continue; is_allowed "$_sf" || _staged_chk="${_staged_chk}${_sf}
"; done <<EOF
$_staged_files
EOF
  added=$(printf '%s' "$_staged_chk" | xargs -d '\n' -r git diff --cached -U0 -- 2>/dev/null | grep '^+' | grep -v '^+++' || true)
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
    is_allowed "$f" && continue
    h=$(grep -nEi "$HI" "$p" 2>/dev/null || true)
    [ -n "$h" ] && { echo "✗ [BLOCK] possível SEGREDO em $f:"; printf '%s\n' "$h" | sed 's/^/    /' | head -4; block=1; }
  done <<EOF
$list
EOF
fi

# ── PORTA 1 (DA-189) — chave/token no que é servido ao navegador. Roda em QUALQUER
# modo (staged ou all/dir): o nome do arquivo já basta pra saber se ele é "servido"
# (SERVED_DIR_RE), então não precisa esperar --all pra pegar um segredo novo indo
# pra dentro de static/build/dist/public/templates.
porta1_files=""
if [ "$mode" = "staged" ] && [ -d .git ]; then
  porta1_files=$(git diff --cached --name-only 2>/dev/null || true)
else
  porta1_files=$(git -C "$base" ls-files 2>/dev/null)
  [ -z "$porta1_files" ] && porta1_files=$(cd "$base" 2>/dev/null && find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sed 's#^\./##')
fi
p1_hit=0
served=$(printf '%s\n' "$porta1_files" | grep -E "$SERVED_DIR_RE" || true)
if [ -n "$served" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    is_allowed "$f" && continue
    h=$(_conteudo "$f" | grep -nEi "$FRONT_KEY" || true)
    [ -n "$h" ] && { echo "✗ [BLOCK] [porta 1 — chave no front] $f serve chave/token ao navegador:"; printf '%s\n' "$h" | sed 's/^/    /' | head -4; block=1; p1_hit=1; }
  done <<EOF
$served
EOF
fi
# NEXT_PUBLIC_/VITE_/REACT_APP_ com nome de KEY/SECRET/TOKEN/PASS — checa QUALQUER
# arquivo rastreado (não só os diretórios servidos): é ONDE A VARIÁVEL NASCE
# (.env.example, config do bundler) que decide se ela vai pro bundle público.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in *node_modules/*|*.min.*|*.lock|*/.git/*) continue ;; esac
  h=$(_conteudo "$f" | grep -nE "$FRONT_PREFIX" || true)
  [ -n "$h" ] && { echo "✗ [BLOCK] [porta 1 — chave no front] $f declara variável NEXT_PUBLIC_/VITE_/REACT_APP_ com nome de segredo:"; printf '%s\n' "$h" | sed 's/^/    /' | head -4; block=1; p1_hit=1; }
done <<EOF
$porta1_files
EOF
[ "$p1_hit" = 0 ] && echo "✓ [porta 1 — chave no front] nada em static/build/dist/public/templates, nenhum NEXT_PUBLIC_/VITE_/REACT_APP_ com nome de segredo"

# ── PORTA 2 (DA-189) — segredo no HISTÓRICO do git. Só em all/dir: reescrever a
# história não é frequente, e a varredura é sobre commits PASSADOS — não muda entre
# um commit novo e outro, então não vale pagar rev-list+grep em CADA pré-commit.
if [ "$mode" != "staged" ] && [ -d .git ]; then
  # .env.example/.sample/.template são o CONTRATO (chaves sem valor) — sempre
  # permitidos, mesma exclusão de env_tracked() acima. `git log -- pathspec` não
  # filtra por sufixo sozinho, então pega o nome de arquivo por commit (--name-only)
  # e só mantém o commit se SOBRAR pelo menos um arquivo que não é exemplo.
  hist_names=$(git log --all --full-history --format='@@%H %s' --name-only \
    -- '*.env' '.env.*' 'auth.json' 2>/dev/null | awk '
    /^@@/ { if (commit != "" && keep) print commit; commit=$0; keep=0; next }
    NF && $0 !~ /\.(example|sample|template)$/ { keep=1 }
    END { if (commit != "" && keep) print commit }
  ')
  hist_content=""
  revs=$(git rev-list --all 2>/dev/null || true)
  if [ -n "$revs" ]; then
    hist_content=$(printf '%s\n' "$revs" | xargs git grep -lE "$FRONT_KEY" 2>/dev/null || true)
    # allowlist: "rev:caminho" cujo caminho está isento sai da acusação (o resto fica)
    if [ -n "$allow_paths" ] && [ -n "$hist_content" ]; then
      hist_content=$(printf '%s\n' "$hist_content" | while IFS= read -r _hc; do is_allowed "${_hc#*:}" || printf '%s\n' "$_hc"; done)
    fi
  fi
  if [ -n "$hist_names" ] || [ -n "$hist_content" ]; then
    echo "✗ [BLOCK] [porta 2 — .env no histórico] segredo/arquivo sensível JÁ ESTEVE no git:"
    [ -n "$hist_names" ] && { echo "  arquivos (.env/.env.*/auth.json, exceto .example/.sample/.template):"; printf '%s\n' "$hist_names" | sed 's/^@@/    /' | head -6; }
    [ -n "$hist_content" ] && { echo "  commits com padrão de chave:"; printf '%s\n' "$hist_content" | sed 's/^/    /' | head -6; }
    echo "  rotacione ANTES de limpar o histórico — apagar o arquivo no HEAD não apaga o commit antigo"
    block=1
  else
    echo "✓ [porta 2 — .env no histórico] nenhum .env/.env.*/auth.json nem padrão de chave em nenhum commit"
  fi
fi

if [ "$block" -ne 0 ]; then echo; echo "✗ check-secrets: segredo detectado — NÃO commitar. Se já vazou, ROTACIONE o segredo."; exit 1; fi
if [ "$warn" -ne 0 ]; then echo; echo "⚠ check-secrets: avisos (acima) — revise"; exit 0; fi
echo "✓ check-secrets: nenhum segredo de alta confiança detectado"
