#!/usr/bin/env bash
# smoke-v4 — o teste de ADOÇÃO do skeleton-v4: o que um adotante vê no dia 0, nos dois modos.
# Roda com HOME isolada (adotante sem runtime host) — o que a home do autor tem não conta aqui.
set -u   # sem pipefail: os pipelines aqui são "produtor | grep -q", e grep -q fecha cedo (SIGPIPE no produtor não é falha)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SK="$ROOT/skeleton-v4"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home"; export HOME="$T/home"
pass=0; fail=0
ok(){ echo "  ✓ $1"; pass=$((pass+1)); }
bad(){ echo "  ✗ $1"; fail=$((fail+1)); }
adopt(){ # adopt <dir> — git init vazio + tar do esqueleto (sem o README dele)
  mkdir -p "$1" && (cd "$1" && git init -q && git config user.email t@t && git config user.name t) \
    && (cd "$SK" && tar cf - --exclude=./README.md .) | tar xkf - -C "$1"
}

echo "== 0) sintaxe + o índice que vem no tar bate com o DECISIONS.md que vem junto"
for f in "$SK"/scripts/*.sh "$SK"/mecanismo/tests/*.sh "$SK"/.claude/hooks/*.sh; do bash -n "$f" || bad "sintaxe: $f"; done
bash "$SK/scripts/da-index.sh" check "$SK" >/dev/null 2>&1 && ok "DECISIONS-INDEX.md do esqueleto sincronizado" || bad "índice do esqueleto nasce divergente"
find "$SK" \( -name '*.js' -o -name '*.ts' -o -name '*.py' \) | grep -q . && bad "há .js/.ts/.py no esqueleto" || ok "esqueleto só bash+md+json"

echo "== 1) VAZAMENTO ZERO: nada da instância do autor no esqueleto"
leak="$(grep -rniE '012a|012b|DA-024|DA-029|fantasma|GRANDFATHER|clawd|samyr|mainbot|cronbot|degenbot|devbot|claude-tg-tmux|tradingagents|holdge|peptideo|radar-eleitor' "$SK" | grep -v 'github.com/samyrwendel/adas' || true)"
[ -z "$leak" ] && ok "grep de instância vazio" || { bad "instância do autor no esqueleto:"; echo "$leak" | sed 's/^/      /'; }
nums="$(grep -rnoE 'DA-[0-9]{3}' "$SK/scripts" "$SK/.claude" "$SK/.adas" "$SK/mecanismo" | grep -v 'DA-001' || true)"
[ -z "$nums" ] && ok "scripts/hooks não citam número de diário do autor" || { bad "número de diário em script:"; echo "$nums" | sed 's/^/      /'; }

echo "== 2) MODO DOC — dia 0 = exatamente 1 aviso (placeholders), zero stderr, selo/versão/modo gravados"
adopt "$T/doc"; cd "$T/doc"
bash scripts/adas-init.sh --modo doc --fonte "$ROOT" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "adas-init --modo doc exit 0" || bad "adas-init --modo doc exit $rc"
out="$(bash scripts/check-adas.sh 2>"$T/doc.err")"; rc=$?
n="$(printf '%s\n' "$out" | grep -c '^•')"
[ "$rc" = 0 ] && ok "check-adas exit 0" || bad "check-adas exit $rc"
[ "$n" = 1 ] && ok "exatamente 1 linha • (era 8 no esqueleto anterior)" || { bad "$n linhas • (esperado 1):"; printf '%s\n' "$out" | grep '^•' | sed 's/^/      /'; }
printf '%s\n' "$out" | grep -q '^• PLACEHOLDER ainda presente — preencha: .*DECISIONS.md' && ok "o 1 aviso é o PLACEHOLDER, com a lista de arquivos" || bad "o aviso não é o PLACEHOLDER com lista"
[ -s "$T/doc.err" ] && { bad "stderr não vazio:"; sed 's/^/      /' "$T/doc.err"; } || ok "stderr vazio"
for f in .adas/profile.json .adas/skeleton-version .adas/install-check; do [ -s "$f" ] && ok "$f gravado" || bad "$f ausente"; done
grep -q '"modo": *"doc"' .adas/profile.json && ok "profile.json declara modo doc" || bad "modo não gravado no profile"
grep -q '^modo: doc' .adas/install-check && ok "selo registra o modo" || bad "selo sem modo"
[ -x .git/hooks/pre-commit ] && ok "pre-commit instalado pelo init" || bad "pre-commit não instalado"
grep -q "$(date +%F)" DECISIONS.md && ok "DA-001 recebeu a data de adoção" || bad "data não carimbada na DA-001"
printf '%s\n' "$out" | grep -q 'impede' && printf '%s\n' "$out" | grep -qv 'não impede' && bad "modo doc afirma que impede" || ok "modo doc não afirma impedir nada"

echo "== 3) UM FORMATO SÓ — a DA-001 do template é lida pelo índice; da-new cria a DA-002 e o índice a vê"
grep -q '^- DA-001 · produto · — — Este projeto adota o ADAS — ' DECISIONS-INDEX.md && ok "índice enxerga a DA-001 do template (título + Regra)" || bad "DA-001 do template invisível ao índice"
bash scripts/da-index.sh update . 2>&1 | grep -q 'WARN c11' && bad "c11 acusa DA inexistente no dia 0" || ok "sem c11 no dia 0"
newout="$(bash scripts/da-new.sh produto - "Segunda decisão de teste" . 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$newout" | grep -q '^DA-002$' && ok "da-new.sh gerou DA-002 (max+1)" || bad "da-new.sh não gerou DA-002: $newout"
bash scripts/da-index.sh check . >/dev/null 2>&1 && bad "check não acusou índice velho após da-new" || ok "índice velho após da-new é acusado (divergência nunca passa)"
bash scripts/da-index.sh update . >/dev/null 2>&1
bash scripts/da-index.sh list . | grep -q '^- DA-002 · produto · — — Segunda decisão de teste' && ok "list enxerga a DA-002 criada pelo caminho oficial" || bad "DA-002 não aparece no list"
bash scripts/da-index.sh show DA-002 . | grep -q '^## DA-002 — Segunda decisão de teste' && ok "show DA-002 devolve o corpo" || bad "show DA-002 falhou"
bash scripts/da-index.sh sagas . >/dev/null 2>&1; [ $? = 2 ] && ok "'sagas' saiu e diz isso (exit 2), não quebra" || bad "'sagas' não responde exit 2"

echo "== 4) NÃO SUJA A HOME — de /tmp, sem [dir], da-new/da-index/check-adas agem no repo do script"
cd "$T"
n0="$(ls -A "$HOME" | wc -l)"
o="$(bash "$T/doc/scripts/da-new.sh" produto - "Terceira, rodada de fora" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$o" | grep -q "$T/doc/DECISIONS.md" && ok "da-new sem [dir] escreveu em $T/doc" || bad "da-new sem [dir] não escreveu no repo: $o"
grep -q '^## DA-003 — Terceira' "$T/doc/DECISIONS.md" && ok "DA-003 está no diário do repo" || bad "DA-003 não foi para o repo"
bash "$T/doc/scripts/da-index.sh" update 2>&1 | grep -q '3 DAs' && ok "da-index sem [dir] atualizou o repo do script" || bad "da-index sem [dir] não agiu no repo do script"
[ ! -e "$HOME/DECISIONS.md" ] && [ ! -e "$HOME/.adas" ] && [ "$(ls -A "$HOME" | wc -l)" = "$n0" ] && ok "\$HOME intocada" || { bad "\$HOME foi tocada:"; ls -la "$HOME" | sed 's/^/      /'; }
mkdir -p "$T/x"; cd "$T/x"; [ ! -e DECISIONS.md ] && ok "cwd (sem DECISIONS.md) também intocado" || bad "cwd foi tocado"

echo "== 5) check-adas [dir] — de fora, audita o alvo e não o cwd; git rev-parse (não [ -d .git ])"
adopt "$T/b"; (cd "$T/b" && bash scripts/adas-init.sh --modo doc --fonte "$ROOT" >/dev/null 2>&1)
cd "$T"; outb="$(bash "$T/doc/scripts/check-adas.sh" "$T/b" 2>&1)"
printf '%s\n' "$outb" | grep -q 'PLACEHOLDER' && ok "check-adas <dir> audita o alvo (placeholder de B)" || bad "check-adas <dir> não auditou B"
(cd "$T/doc" && git add -A >/dev/null 2>&1 && git commit -qm "adota" >/dev/null 2>&1 && git worktree add -q "$T/wt" -b wt >/dev/null 2>&1)
if [ -d "$T/wt" ]; then
  outw="$(bash "$T/wt/scripts/check-adas.sh" "$T/wt" 2>&1)"
  printf '%s\n' "$outw" | grep -q 'sem git' && bad "worktree tratado como 'sem git'" || ok "worktree (.git é arquivo) reconhecido como git"
else bad "não consegui criar worktree para o teste"; fi

echo "== 6) MODO MECANISMO — mesmo esqueleto virgem: 1 aviso + check-mecanismo FALHA (invariante sem gatilho não entra)"
adopt "$T/mec"; cd "$T/mec"
bash scripts/adas-init.sh --modo mecanismo --fonte "$ROOT" >/dev/null 2>&1
grep -q 'adas-modo: mecanismo' ADAS.md && [ ! -f mecanismo/ADAS.mecanismo.md ] && ok "init trocou o ADAS.md pelo template do modo mecanismo" || bad "ADAS.md não é o template do modo mecanismo"
grep -q '"modo": *"mecanismo"' .adas/profile.json && ok "profile.json declara modo mecanismo" || bad "modo mecanismo não gravado"
outm="$(bash scripts/check-adas.sh 2>&1)"; rcm=$?
[ "$rcm" = 1 ] && ok "check-adas exit 1 em modo mecanismo virgem (o contrato do modo)" || bad "check-adas exit $rcm (esperado 1)"
[ "$(printf '%s\n' "$outm" | grep -c '^•')" = 1 ] && ok "ainda só 1 linha • (placeholder) — o FAIL é do mecanismo, não ruído" || bad "linhas • em mecanismo ≠ 1"
printf '%s\n' "$outm" | grep -q '✓ \[mecanismo\] invariante 1 «Segredo nunca entra no repo»' && ok "invariante de referência (check-secrets + teste) PASSA" || bad "invariante de referência não passou"
printf '%s\n' "$outm" | grep -q '✗ \[mecanismo\] invariante 2 .*não existe' && printf '%s\n' "$outm" | grep -q '✗ \[mecanismo\] invariante 3' && ok "invariantes-modelo sem gatilho são LISTADOS como FAIL" || bad "invariantes sem gatilho não listados"
[ "$out" != "$outm" ] && ok "saída do modo doc ≠ saída do modo mecanismo (o modo não é decorativo)" || bad "saídas iguais nos dois modos"
git add -A >/dev/null 2>&1; git commit -qm "tenta" >/dev/null 2>&1 && bad "pre-commit deixou passar invariante sem gatilho" || ok "pre-commit BLOQUEIA o commit em modo mecanismo com invariante sem gatilho"

echo "== 7) check-mecanismo — fixture preenchida passa; tirar o teste: falha nomeando o invariante; frase solta é rejeitada"
sed -i '/^2\. /d; /^3\. /d' ADAS.md
bash scripts/check-mecanismo.sh . >/dev/null 2>&1 && ok "só invariantes com gatilho+teste → PASSA" || bad "fixture preenchida não passou"
printf '2. **Nunca editar settings.json à mão** — mecanismo: scripts/check-adas.sh\n' > "$T/inv"; sed -i "/^1\. /r $T/inv" ADAS.md
o2="$(bash scripts/check-mecanismo.sh . 2>&1)"; [ $? = 1 ] && printf '%s\n' "$o2" | grep -q 'invariante 2 .*sem teste:' && ok "sem teste: → FAIL nomeando o invariante 2" || bad "sem teste: não falhou como esperado: $o2"
sed -i '2,$ s/^2\. .*$/2. **Nunca editar settings.json à mão** — sem gatilho nenhum, só a frase/' ADAS.md
o3="$(bash scripts/check-mecanismo.sh . 2>&1)"; [ $? = 1 ] && printf '%s\n' "$o3" | grep -q 'invariante sem gatilho não entra' && ok "frase sem mecanismo: é REJEITADA com a mensagem do modo" || bad "frase solta não rejeitada: $o3"
sed -i '/^2\. /d' ADAS.md; mkdir -p hooks; printf '#!/usr/bin/env bash\nexit 0\n' > hooks/x.sh; printf '#!/usr/bin/env bash\nexit 0\n' > hooks/x.test.sh
printf '2. **Regra com hook não registrado** — mecanismo: hooks/x.sh · teste: hooks/x.test.sh\n' > "$T/inv"; sed -i "/^1\. /r $T/inv" ADAS.md
o4="$(bash scripts/check-mecanismo.sh . 2>&1)"; [ $? = 1 ] && printf '%s\n' "$o4" | grep -q 'NADA o executa' && ok "mecanismo existente mas não registrado → FAIL (gate que ninguém chama não é gate)" || bad "hook não registrado passou: $o4"
jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"bash hooks/x.sh"}]}]' .claude/settings.json > "$T/s.json" && mv "$T/s.json" .claude/settings.json
bash scripts/check-mecanismo.sh . >/dev/null 2>&1 && ok "registrado em settings.json → PASSA" || bad "hook registrado não passou"

echo "== 8) adas-init sem --modo: exit 2 com a pergunta certa; idempotente em repo preenchido"
o5="$(bash "$T/doc/scripts/adas-init.sh" "$T/doc" 2>&1)"; [ $? = 2 ] && printf '%s\n' "$o5" | grep -qi 'quem está no ato' && ok "sem --modo → exit 2 + 'quem está no ato?'" || bad "sem --modo não perguntou: $o5"
cd "$T/doc"; sed -i 's/<PLACEHOLDER: quem decidiu, e a frase literal se houver>/Fulana, "vamos adotar"/' DECISIONS.md; bash scripts/da-index.sh update . >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm "preenche" >/dev/null 2>&1
bash scripts/adas-init.sh --modo doc --fonte "$ROOT" >/dev/null 2>&1
[ -z "$(git status --porcelain -- . ':!.adas' 2>/dev/null)" ] && ok "re-init não altera nada fora de .adas/ (git diff vazio)" || { bad "re-init alterou:"; git status --porcelain | sed 's/^/      /'; }

echo "== 9) detector de ator (modo doc): 20 commits de agente avisam; 1 humano no meio não"
adopt "$T/ag"; cd "$T/ag"; bash scripts/adas-init.sh --modo doc --fonte "$ROOT" >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm "adota" -m "Co-Authored-By: Claude <noreply@anthropic.com>" >/dev/null 2>&1
for i in $(seq 1 19); do echo "$i" >> log.txt; git add log.txt; git commit -qm "c$i" -m "Co-Authored-By: Claude <noreply@anthropic.com>" >/dev/null 2>&1; done
bash scripts/check-adas.sh 2>&1 | grep -q '^• ATOR: 20 dos últimos 20 commits são de agente' && ok "20/20 de agente → ATOR avisa com o sinal e sugere --modo mecanismo" || bad "detector de ator não avisou"
echo h >> log.txt; git add log.txt; git -c user.name=Humana -c user.email=h@h commit -qm "revisão humana" >/dev/null 2>&1
bash scripts/check-adas.sh 2>&1 | grep -q '^• ATOR' && bad "1 commit humano no meio ainda acusa" || ok "1 commit humano nos últimos 20 → não acusa"

echo "== 10) o teste do gatilho de referência roda sozinho"
bash "$SK/mecanismo/tests/check-secrets.test.sh" >/dev/null 2>&1 && ok "mecanismo/tests/check-secrets.test.sh exit 0" || bad "teste de referência falhou"

echo; echo "RESULTADO smoke-v4: $pass ok, $fail falha(s)"
[ "$fail" = 0 ]
