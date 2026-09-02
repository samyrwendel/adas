# host/ — Runtime anti-decaimento do ADAS (PASSO 11, opcional — só Claude Code)

> O JIT por faixa (PASSO 6) injeta a regra **no instante da edição** — é a parte mais forte do ADAS.
> Mas sozinho ele deixa **quatro buracos** por onde a aderência decai numa sessão longa. Esta camada
> fecha os quatro. Mecanismos absorvidos do [ponytail](https://github.com/DietrichGebert/ponytail)
> (MIT), adaptados: aqui o estado é **por repo** (não global) e o texto injetado vem do **ADAS.md do
> repo** (fonte canônica), nunca hardcoded no hook.

## Os 4 vetores de decaimento (e o que fecha cada um)

| # | Vetor | Sintoma | Fecha com |
|---|---|---|---|
| 1 | **Sessão nasce fora do repo** (hub multi-repo): o `.claude/settings.json` do repo **não carrega** — o Claude Code só carrega project-root da sessão + user settings | O JIT nunca dispara; ADAS inteiro inerte | `adas-route.sh` (PreToolUse user-level, roteia pelo path do arquivo e delega ao `adas-inject.sh` do repo) |
| 2 | **Compactação/resume**: o "leia o ADAS.md" do turno 1 evapora quando o contexto compacta | Sessão longa "esquece" a governança | `adas-activate.sh` (SessionStart `startup\|resume\|clear\|compact` reinjeta o NÚCLEO do ADAS.md) |
| 3 | **Subagents órfãos**: subagent nasce com contexto isolado — o SessionStart do pai **nunca chega** nele | Decisões de abordagem (onde a invenção nasce) sem governança | `adas-subagent.sh` (SubagentStart com envelope `additionalContext` — obrigatório: stdout cru é descartado neste evento) |
| 4 | **Injeção dupla**: user + project settings são **mesclados**; sessão aberta dentro do repo dispararia a mesma regra 2× | Ruído/custo | guard no `adas-route.sh`: se `CLAUDE_PROJECT_DIR` é o próprio repo, exit 0 (o hook do projeto cobre) |

Tudo **fail-open**: erro em qualquer script nunca trava a sessão nem bloqueia a edição — na dúvida,
não injeta (a direção segura para injeção de contexto; gates de dinheiro são o oposto, ver PASSO 7).

## Instalação

```bash
# TUDO EM UM (idempotente — rodar de novo atualiza; preserva hooks alheios no settings):
bash host/install.sh /caminho/repo1 /caminho/repo2   # repos governados como argumentos
# Sem argumentos: só instala/atualiza hooks e mantém o repos.conf existente.
```

O instalador faz os 3 passos (scripts → `repos.conf` → merge jq do `settings-snippet.json` no
`~/.claude/settings.json`, com backup `.bak-adas`) e ABORTA em erro (instalação é fail-closed;
os hooks instalados continuam fail-open em runtime). O `scripts/check-adas.sh` do repo governado
audita o resultado (check 9 — ENFORCEMENT): runtime ausente, hooks copiados sem registro no
settings, ou repo fora do `repos.conf` viram WARN explícito — instalação-fantasma não cala.
Manual, se preferir:

```bash
# 1. Scripts no user-level
mkdir -p ~/.claude/hooks ~/.claude/adas
cp host/adas-lib.sh host/adas-core.sh host/adas-activate.sh host/adas-subagent.sh host/adas-route.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/adas-*.sh

# 2. Repos governados (um caminho absoluto por linha)
cp host/repos.conf.example ~/.claude/adas/repos.conf && $EDITOR ~/.claude/adas/repos.conf

# 3. Hooks no user settings — merge de host/settings-snippet.json no ~/.claude/settings.json
#    (preserve o que você já tem; vale a partir da PRÓXIMA sessão)
```

Requisitos: `jq` e `bash` no PATH. Cada repo governado precisa de `ADAS.md` na raiz (o núcleo
reinjetado é a seção entre `<!-- adas-core-start -->` e `<!-- adas-core-end -->`; sem marcadores,
cai no topo do arquivo) e, para o JIT via roteador, `.claude/hooks/adas-inject.sh` (PASSO 6).

## Teste rápido (sem abrir sessão)

```bash
echo '{"cwd":"/caminho/do/repo","session_id":"t"}' | bash ~/.claude/hooks/adas-activate.sh            # núcleo
CLAUDE_PROJECT_DIR=/caminho/do/hub bash ~/.claude/hooks/adas-subagent.sh | jq .                        # envelope
echo '{"tool_input":{"file_path":"/caminho/do/repo/arquivo-de-faixa"}}' | bash ~/.claude/hooks/adas-route.sh | jq .  # faixa
CLAUDE_PROJECT_DIR=/caminho/do/repo bash -c 'echo "{\"tool_input\":{\"file_path\":\"$CLAUDE_PROJECT_DIR/x\"}}" | bash ~/.claude/hooks/adas-route.sh'  # guard: vazio
```

## O que o runtime NÃO cobre (limitações conhecidas)
- **Escrita via shell**: o matcher `Edit|Write|MultiEdit` NÃO pega `sed -i`, `tee`, redirects
  (`>`/`>>`) nem `NotebookEdit` — uma edição por Bash passa sem a faixa injetada. Cobrir isso com
  parsing de comando seria frágil; a outra ponta (gates `check-*.sh` no commit/deploy, PASSO 7) é
  quem pega o que escapou aqui.
- **Subagent em hub**: o `adas-subagent.sh` resolve o repo pelo `CLAUDE_PROJECT_DIR`/cwd — subagent
  nascido no HUB recebe o header multi-repo genérico, não o núcleo do repo que ele vai tocar
  (o roteador PreToolUse compensa no instante da edição).

## O que NÃO absorver do ponytail (decidido por verificação adversarial)
- **Reinjeção do ruleset completo por turno** (~1,3k tokens/turno acelera a própria compactação que se
  quer evitar) — reinjete só nas FRONTEIRAS (SessionStart) e nos nascimentos (SubagentStart).
- **Fail-open em gate de dinheiro** — injeção de contexto é fail-open; gate de caminho crítico é
  **fail-closed** (PASSO 7).
- **Flag/modo global único** — o ADAS é por repo; estado por repo (`~/.claude/adas/<repo>.active`).
- **LOC como métrica** — menos linhas num handler de webhook pode ser check deletado.
- **Substituir o JIT por injeção genérica** — a regra específica no instante da edição é a parte mais
  forte do ADAS; o ponytail nem tem equivalente.
