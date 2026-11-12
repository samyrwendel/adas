#!/usr/bin/env bash
# da-new-casa.sh — trava D-C6 (DA-670): DA só de projeto nasce no repositório do app. HOME falso; nenhum diário real é tocado.
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.adas" "$T/app/scripts"; printf '# d\n' > "$T/home/DECISIONS.md"; printf '# d\n' > "$T/app/DECISIONS.md"; : > "$T/app/scripts/da-new.sh"
printf '%s|produto,projeto/app\n' "$T/app" > "$T/home/.adas/rotas.conf"
ok=0; bad=0
t() { local esp="$1"; shift; HOME="$T/home" bash "$S/da-new.sh" --tipo regra "$@" >/dev/null 2>&1; local rc=$?
      if [ "$rc" = "$esp" ]; then ok=$((ok+1)); else bad=$((bad+1)); echo "✗ esperava rc=$esp, veio $rc: $*"; fi; }
t 2 projeto/app nova/x "t"                       # só projeto, casa existe → recusa
t 0 projeto/app nova/casa-app "t"                # ponteiro 📦
t 0 produto,projeto/app nova/x "t"               # transversal fica
t 0 instância nova/x "t"                         # outro escopo
t 0 projeto/sem-casa nova/x "t"                  # projeto sem repositório próprio segue no servidor
t 0 projeto/app nova/x "t" "$T/app"              # pela porta do repositório (dir ≠ HOME)
echo "da-new-casa: $ok ok, $bad falha(s)"; [ "$bad" = 0 ]
