#!/usr/bin/env bash
# adas test — o RELÓGIO do ADAS (Fase 1 do plano estrutural): um comando roda todas as suítes do produto.
#
#   adas test                    suítes do skeleton + harness do da-index + smoke + smoke-v4 + varredura DA-530
#   adas test --sem-varredura    só as suítes do repo (pre-commit e CI: a varredura olha a MÁQUINA, não o repo)
#   adas test --selftest         idem `adas test` + grava ~/.adas/selftest.status e alerta na TRANSIÇÃO
#                                verde↔vermelho (adas-selftest.timer, cron mecânico sem LLM — DA-009)
#   adas test --linha            uma linha para o SessionStart se o relógio está vermelho ou parado; senão nada
#
# Sai ≠0 se qualquer suíte falhar. Mede o tempo de cada uma (a "medição" do relógio).
# Env: ADAS_SELFTEST_STATUS (arquivo de status) · ADAS_ALERT_CMD (comando que recebe a mensagem como $1;
#      sem ele o alerta vai pro stderr/journal) · ADAS_VARREDURA_RAIZES (raízes da varredura, separadas por ':')
#      ADAS_SELFTEST_VELHO (s sem rodar até a linha do SessionStart acusar relógio parado; default 3 dias)
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ST="${ADAS_SELFTEST_STATUS:-$HOME/.adas/selftest.status}"

campo() { sed -n "s/^$1=//p" "$ST" 2>/dev/null | head -1; }

if [ "${1:-}" = "--linha" ]; then
  [ -f "$ST" ] || exit 0
  now=$(date +%s); rodou="$(campo rodou)"; desde="$(campo desde)"
  if [ "$(campo estado)" = vermelho ]; then
    echo "ADAS selftest VERMELHO há $(( (now - ${desde:-$now}) / 86400 )) dia(s): $(campo falhas). Rode: adas test"
  elif [ -n "$rodou" ] && [ $((now - rodou)) -gt "${ADAS_SELFTEST_VELHO:-259200}" ]; then
    echo "ADAS selftest sem rodar há $(( (now - rodou) / 86400 )) dia(s) — timer parado? systemctl --user status adas-selftest.timer"
  fi
  exit 0
fi

SELF=0; VARRE=1
for a in "$@"; do
  case "$a" in
    --selftest) SELF=1 ;;
    --sem-varredura) VARRE=0 ;;
    *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done

# Isolamento: dentro do pre-commit o git exporta GIT_DIR/GIT_INDEX_FILE e um teste que faz `git init`
# em /tmp escreveria no repo real. AXON_HEADLESS do worker muda o comportamento de hooks sob teste.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars 2>/dev/null) AXON_HEADLESS

falhas=(); log=""; t0=$(date +%s)
roda() {  # roda <nome> <cmd...>
  local nome="$1" s rc out; shift; s=$(date +%s)
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then
    printf '  ✓ %-38s %3ss\n' "$nome" "$(( $(date +%s) - s ))"
  else
    printf '  ✗ %-38s %3ss  (rc=%s)\n' "$nome" "$(( $(date +%s) - s ))" "$rc"
    { printf '%s\n' "$out" | grep -E '^[[:space:]]*(✗|FAIL)' || printf '%s\n' "$out" | tail -3; } | head -5 | sed 's/^/      /'
    falhas+=("$nome"); log+="=== $nome (rc=$rc)"$'\n'"$out"$'\n'
  fi
}

# Varredura DA-530 (ressalva R2 da revisão 008): ADAS-Projeto só em repo git. Sem git não há pre-commit nem CI
# que dispare o check-adas da pasta, então quem dispara é o relógio. Marca = a pasta `.adas/` (não só o
# profile.json: axon e claude-tg-tmux têm ADAS sem ele). A home é a raiz de governança e fica de fora.
varredura_da530() {
  local raiz d dir home ruins=0
  home="$(cd "$HOME" && pwd -P)"
  IFS=: read -ra raizes <<< "${ADAS_VARREDURA_RAIZES:-$HOME:/opt/projects}"
  for raiz in "${raizes[@]}"; do
    [ -d "$raiz" ] || continue
    while IFS= read -r d; do
      dir="$(cd "$(dirname "$d")" && pwd -P)"
      [ "$dir" = "$home" ] && continue
      if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "✗ ADAS-Projeto só entra em repo git (DA-530) — $dir tem .adas/ e não é repo git; git init ou tire o ADAS daqui"
        ruins=$((ruins + 1))
      fi
    done < <(find "$raiz" -maxdepth 3 -type d -name .adas \
               -not -path '*/node_modules/*' -not -path '*/_graveyard_*' -not -path '*/.cache/*' 2>/dev/null)
  done
  [ "$ruins" = 0 ]
}

echo "adas test — $ROOT"
for f in "$ROOT"/skeleton/scripts/tests/*.sh; do roda "skeleton/$(basename "$f")" bash "$f"; done
roda "skeleton/da-index/run-tests.sh" bash "$ROOT/skeleton/scripts/tests/da-index/run-tests.sh"
roda "tests/smoke.sh"    bash "$ROOT/tests/smoke.sh"
roda "tests/smoke-v4.sh" bash "$ROOT/tests/smoke-v4.sh"
[ "$VARRE" = 1 ] && roda "varredura DA-530 (pasta .adas sem git)" varredura_da530

total=$(( $(date +%s) - t0 ))
if [ "${#falhas[@]}" = 0 ]; then estado=verde; echo "VERDE — todas as suítes passaram (${total}s)"
else estado=vermelho; echo "VERMELHO — ${#falhas[@]} suíte(s) falharam: ${falhas[*]} (${total}s)"; fi

if [ "$SELF" = 1 ]; then
  now=$(date +%s); antes="$(campo estado)"; desde="$(campo desde)"
  [ "$antes" = "$estado" ] && [ -n "$desde" ] || desde=$now
  mkdir -p "$(dirname "$ST")"
  printf 'estado=%s\ndesde=%s\nrodou=%s\nsegundos=%s\nfalhas=%s\n' "$estado" "$desde" "$now" "$total" "${falhas[*]}" > "$ST.tmp" \
    && mv "$ST.tmp" "$ST"
  printf '%s' "$log" > "${ST%.status}.log"   # saída inteira das suítes vermelhas da última rodada (vazio se verde)
  # alerta SÓ na transição; sem status anterior conta como verde (nasce mudo se nasce verde)
  if [ "${antes:-verde}" != "$estado" ]; then
    if [ "$estado" = vermelho ]; then msg="🔴 ADAS selftest VERMELHO em $(hostname): ${falhas[*]}. Saída: ${ST%.status}.log · rode: adas test"
    else msg="🟢 ADAS selftest voltou ao verde em $(hostname)."; fi
    if [ -n "${ADAS_ALERT_CMD:-}" ]; then $ADAS_ALERT_CMD "$msg" || echo "alerta falhou: $msg" >&2
    else echo "ALERTA: $msg" >&2; fi
    echo "selftest: transição ${antes:-verde}→$estado alertada"
  else
    echo "selftest: sem transição ($estado) — sem alerta"
  fi
fi
[ "$estado" = verde ]
