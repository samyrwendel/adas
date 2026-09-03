# adas-hermes — plugin ADAS pro Hermes agent

Injeta a governança ADAS (núcleo do `ADAS.md` do repo) em cada sessão/subagente e bloqueia comandos
de shell que violam a faixa `seguranca-acesso` (ex.: `cat .env` fora do lugar). Não reimplementa
nenhuma regra — chama os scripts do `host/` deste repo (`adas-resolve.sh`, `adas-core.sh`,
`adas-secret-guard.sh`) via subprocess, a MESMA fonte que os hooks do Claude Code usam.

## O que este plugin cobre — e o que NÃO cobre

| Gancho ADAS | Mecanismo Hermes usado | Cobre? |
|---|---|---|
| Núcleo injetado na sessão (equivalente ao SessionStart) | `ctx.register_system_prompt_section("adas-core", content=<callable>)` — "bounded context que é CONGELADO em cada NOVO prompt de sessão" (contrato documentado no próprio `hermes_cli/plugins.py`) | Sim, por desenho — resolve sozinho o problema de "reinjetar após compactação/resume" que o Claude Code precisa do `adas-activate.sh` pra fechar, porque o texto já nasce dentro do prompt da sessão |
| Faixa por subagente | `subagent_start` (hook — **existe de verdade**, confirmado lendo `plugins/observability/langfuse/__init__.py`, que já o usa) | Registrado como reforço best-effort. **NÃO PROVADO** se é necessário — a `register_system_prompt_section` pode já cobrir subagente automaticamente se ele nasce como sessão nova (plausível, não confirmado sem um Hermes rodando de verdade) |
| Bloqueio de comando proibido | `pre_tool_call` retornando `{"action": "block", "message": ...}` | Sim — contrato copiado do plugin de referência real deste mesmo repo Hermes, `plugins/security-guidance/__init__.py`, que já bloqueia (modo opcional) por padrão de conteúdo |
| Faixa por-arquivo no instante da edição (JIT do PASSO 6) | — | **NÃO coberto.** Ficaria pra uma versão futura mapear os args de `write_file`/`patch` (mesmos nomes que `security-guidance` já usa) pra faixa certa por glob. |

## Instalação

```bash
cp -r host/hermes-plugin ~/.hermes/hermes-agent/plugins/adas-hermes
# ou, se o Hermes suportar plugin externo por path (confira `hermes plugins --help`
# na instância real — não verificado aqui, sem acesso de escrita ao Hermes):
hermes plugins install /caminho/pro/adas/host/hermes-plugin
```

Config: `ADAS_HOME` (env) ou `~/adas` (default) precisa apontar pro clone do repo `adas` — mesma
convenção do plugin OpenClaw. Repos governados: mesmo `~/.claude/adas/repos.conf` do host do Claude
Code (`ADAS_REPOS_CONF` como override) — compartilhado entre harnesses, não duplicado por plugin.

## Testar que os ganchos disparam

**Provado neste repo**, sem precisar de uma instância Hermes real (o `ctx` é um mock mínimo que só
implementa `register_hook`/`register_system_prompt_section` — a partir daí é o `register()` e os
handlers REAIS do plugin sendo exercitados, contra os scripts do `host/` reais, não mockados):

```bash
cd host/hermes-plugin
python3 -m pytest test_adas_hermes.py -v
```

**NÃO provado aqui** — este servidor não tem o Hermes instalado (ele roda em `clawdgo`, acesso só
leitura por SSH pra pesquisar a API; ver `agent/agent_runtime_helpers.py:3097` e
`hermes_cli/plugins.py:3114` pro contrato real do dispatcher):

1. `register()` rodando dentro do carregador REAL de plugins do Hermes (o mock aqui não valida o
   `plugin.yaml` nem o processo de descoberta/carregamento).
2. Um subagente REAL recebendo o núcleo — se a `register_system_prompt_section` sozinha já basta,
   ou se o `subagent_start` registrado aqui é de fato necessário.
3. `pre_tool_call` bloqueando um `exec` disparado pelo modelo em produção (o teste chama o handler
   diretamente com kwargs sintéticos).

Se alguém tiver acesso de escrita ao Hermes (em `clawdgo` ou outra instância), o checklist acima é
o roteiro pra fechar a lacuna.
