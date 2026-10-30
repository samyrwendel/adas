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
| Bloqueio de comando proibido | `pre_tool_call` retornando `{"action": "block", "message": ...}` (shell tool do Hermes = **`terminal`**) | Sim — contrato copiado do plugin de referência real deste mesmo repo Hermes, `plugins/security-guidance/__init__.py`, que já bloqueia (modo opcional) por padrão de conteúdo |
| Faixa por-arquivo no instante da edição (JIT do PASSO 6) | — | **NÃO coberto.** Ficaria pra uma versão futura mapear os args de `write_file`/`patch` (mesmos nomes que `security-guidance` já usa) pra faixa certa por glob. |

## Instalação

Plugin de usuário vive em `$HERMES_HOME/plugins/` (default `~/.hermes/plugins/`; em container Hermes,
`HERMES_HOME` costuma ser `/opt/data`). **Não** copie pra `hermes-agent/plugins/` — esse é o diretório
dos plugins empacotados e some num update.

```bash
git clone https://github.com/samyrwendel/adas ~/adas          # ADAS_HOME default (HOME do processo Hermes!)
cp -r ~/adas/host/hermes-plugin "$HERMES_HOME/plugins/adas-hermes"
```

Depois, **três passos que o plugin sozinho não faz** (validados num Hermes real em container):

1. **Habilitar** — plugin é opt-in. Em `config.yaml`: `plugins: { enabled: [adas-hermes] }`
   (ou `hermes plugins enable adas-hermes`). Sem isso o Hermes encontra e ignora o plugin.
2. **Repo governado** — o núcleo só é injetado se o `cwd` da sessão cair dentro de um repo listado em
   `~/.claude/adas/repos.conf` (um caminho absoluto por linha; `ADAS_REPOS_CONF` sobrescreve) **e** esse
   repo tiver `ADAS.md` na raiz (copie `skeleton/ADAS.md`). Em container o `cwd` e o `HOME` são os do
   container (ex.: `/opt/data`), não os do host — o caminho no `repos.conf` tem que ser o de dentro.
3. **Reiniciar o gateway** — a seção de prompt é congelada por sessão; plugin novo só entra no próximo boot.

Config: `ADAS_HOME` (env) ou `~/adas` (default) precisa apontar pro clone do repo `adas`. `session_info`
traz `cwd` de verdade (chaves reais: `session_id, model, provider, platform, profile_name, cwd`).

> O plugin injeta **só o núcleo** do `ADAS.md`. O índice de decisões (`DECISIONS.md`) e a camada 0 de sagas
> do `adas-lib.sh` (`adas_da_layer0`) assumem o layout do host Claude Code (`~/DECISIONS.md`,
> `~/scripts/da-index.sh`) e **não chegam** ao Hermes por este plugin. Se o Hermes precisa de regras
> próprias da instância, mantenha um `DECISIONS.md` local e injete-o com um hook `pre_llm_call` à parte.

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

1. ~~`register()` rodando dentro do carregador REAL~~ — **provado** num Hermes 0.22 em container: o plugin
   é descoberto em `$HERMES_HOME/plugins/`, aparece em `Plugin discovery complete: N found, M enabled` e
   o `plugin.yaml` usa `provides_hooks:` (a chave dos plugins empacotados). Continua não provado: um turno
   real de LLM recebendo a seção de prompt e um `terminal` real sendo bloqueado.
2. Um subagente REAL recebendo o núcleo — se a `register_system_prompt_section` sozinha já basta,
   ou se o `subagent_start` registrado aqui é de fato necessário.
3. `pre_tool_call` bloqueando um `exec` disparado pelo modelo em produção (o teste chama o handler
   diretamente com kwargs sintéticos).

Se alguém tiver acesso de escrita ao Hermes (em `clawdgo` ou outra instância), o checklist acima é
o roteiro pra fechar a lacuna.
