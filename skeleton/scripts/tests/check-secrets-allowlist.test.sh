#!/usr/bin/env bash
# check-secrets-allowlist.test.sh — porta 2 (histórico): allowlist achada a partir do REPO varrido, não do CWD; vale
# pro histórico; sem allowlist o bloqueio diz que não leu nenhuma. Veio do claude-tg-tmux (task 20260921-018); o
# filtro de 'valor fictício' de lá NÃO subiu: no produto a fixture só sai com caminho declarado (invariante v4).
#!/usr/bin/env bash
# test-check-secrets.sh — as duas peneiras da porta 2 (task 20260921-018).
#
# Prova os DOIS lados no mesmo repo descartável (/tmp, nunca este):
#   fictício  → não bloqueia   ·   segredo com formato real → continua bloqueando
# Nenhum segredo de verdade é usado: os valores "reais" são inventados e montados em
# TEMPO DE EXECUÇÃO (concatenação) — os DOIS, o forte e o fraco: senão o literal no fonte
# faria o próprio gate do
# repo acusar este arquivo de teste. O único literal que fica é o FICTÍCIO, de propósito:
# ele prova, no próprio repo, que a peneira de valor o deixa passar.
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GATE="${CHK:-$AQUI/../check-secrets.sh}"
ok=0; fail=0
t() { if eval "$2"; then echo "  ✓ $1"; ok=$((ok+1)); else echo "  ✗ $1"; fail=$((fail+1)); fi; }

TMP="$(mktemp -d /tmp/test-check-secrets-XXXX)"
trap 'rm -rf "$TMP"' EXIT

# valores inventados, montados aqui — nenhum deles existe em lugar nenhum
FICTICIO='Bearer test-secret-token'                       # fixture: forma de Bearer, valor de teste
P=gh; REAL_FORTE="${P}p_0123456789abcdef0123456789abcdef0123"   # 36 chars depois do prefixo
B=Bea; REAL_FRACO="${B}rer zK7qPmRv4Xn2Ld9wTbH6"          # forma fraca, valor SEM marca de fixture

repo_novo() {                                             # $1 = arquivo, $2 = conteúdo
  rm -rf "$TMP/r"; mkdir -p "$TMP/r/$(dirname "$1")"
  printf '%s\n' "$2" > "$TMP/r/$1"
  git -C "$TMP/r" init -q 2>/dev/null
  git -C "$TMP/r" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$TMP/r" -c user.email=t@t -c user.name=t commit -qm x >/dev/null 2>&1
  rm -f "$TMP/r/$1"                                       # some da ÁRVORE, fica no HISTÓRICO
  git -C "$TMP/r" -c user.email=t@t -c user.name=t commit -qam rm >/dev/null 2>&1
}
roda() { ( cd "$TMP/r" && bash "$GATE" --all 2>&1 ); }

echo "== 1. fixture com forma de chave e SEM allowlist bloqueia (política do produto: isenção é por caminho declarado) =="
repo_novo "test/fixture.test.ts" "  headers: { Authorization: '$FICTICIO' },"
saida="$(roda)"; rc=$?
t "sai 1" "[ $rc -eq 1 ]"
t "porta 2 acusa a fixture" "printf '%s' \"\$saida\" | grep -q 'fixture.test.ts'"

echo "== 2. histórico com formato FORTE continua bloqueando =="
repo_novo "static/app.js" "const t = '$REAL_FORTE';"
saida="$(roda)"; rc=$?
t "sai 1" "[ $rc -eq 1 ]"
t "porta 2 acusa" "printf '%s' \"\$saida\" | grep -q '\[porta 2'"
t "aponta o caminho" "printf '%s' \"\$saida\" | grep -q 'static/app.js'"
t "NÃO imprime o valor" "! printf '%s' \"\$saida\" | grep -q '$REAL_FORTE'"

echo "== 3. formato FRACO com valor sem cara de fixture continua bloqueando =="
repo_novo "static/x.js" "fetch(u,{headers:{Authorization:'$REAL_FRACO'}});"
saida="$(roda)"; rc=$?
t "sai 1" "[ $rc -eq 1 ]"
t "porta 2 acusa" "printf '%s' \"\$saida\" | grep -q '\[porta 2'"
t "NÃO imprime o valor" "! printf '%s' \"\$saida\" | grep -q '$REAL_FRACO'"

echo "== 4. marca de fixture NÃO isenta formato forte (o teto declarado) =="
repo_novo "static/y.js" "// example/dummy fixture\nconst t='$REAL_FORTE';"
saida="$(roda)"; rc=$?
t "sai 1 mesmo com 'example' na linha" "[ $rc -eq 1 ]"

echo "== 5. allowlist vale pro HISTÓRICO, não só pra árvore =="
repo_novo "vendor/bin.js" "const t = '$REAL_FRACO';"
mkdir -p "$TMP/r/.adas"
printf 'vendor/bin.js | fixture do teste, valor inventado | 2026-09-21\n' > "$TMP/r/.adas/secrets-allowlist"
git -C "$TMP/r" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$TMP/r" -c user.email=t@t -c user.name=t commit -qm al >/dev/null 2>&1
saida="$(roda)"; rc=$?
t "caminho isento sai da porta 2" "[ $rc -eq 0 ]"

echo "== 6. allowlist é achada a partir do REPO, não do CWD de quem chamou =="
saida="$( cd /tmp && bash "$GATE" --dir "$TMP/r" 2>&1 )"; rc=$?
t "de outro diretório, ainda sai 0" "[ $rc -eq 0 ]"
t "leu a allowlist do diretório varrido" "printf '%s' \"\$saida\" | grep -q 'ℹ allowlist'"

echo "== 7. sem allowlist alguma, o bloqueio DIZ que não leu allowlist =="
rm -f "$TMP/r/.adas/secrets-allowlist"
git -C "$TMP/r" -c user.email=t@t -c user.name=t commit -qam noal >/dev/null 2>&1
saida="$(roda)"; rc=$?
t "volta a bloquear" "[ $rc -eq 1 ]"
t "avisa que nenhuma allowlist foi lida" "printf '%s' \"\$saida\" | grep -q 'nenhuma allowlist foi lida'"

echo
echo "check-secrets (allowlist): $ok ok, $fail falha(s)"
[ "$fail" -eq 0 ]
