# adas — Registro de Decisões (DA-NNN)

> Log **append-only**. Toda decisão (escolha entre alternativas, trade-off aceito, config com efeito
> permanente, reversão) vira uma entrada numerada. **Numerar sequencial, nunca reusar.** Mudar uma
> decisão = marcar a antiga `🔄 Supersedida por DA-MMM` (nunca apagar).
>
> O ADAS governa o ADAS (README, "Auto-auditoria — PASSO 8") — este arquivo é o próprio repo
> praticando o que prega.

---

## Decisão Arquitetural DA-001 — ADAS é multi-harness: documento portátil, mecanismo por plugin

**Status:** ✅ Aceita · **Data:** 2026-09-03

### Contexto
O README documentava só a instalação Claude Code — "Claude Code" aparecia 3×, `openclaw`/`hermes`/
`plugin` 0×, e o PASSO 11 (runtime anti-decaimento) dizia explicitamente "só Claude Code". O Samyr
perguntou se havia documentação pra instalar noutro harness: não havia. A CAMADA DE DOCUMENTO
(`.specs/` → faixas → `ADAS.md`) já era portátil por natureza — cola em qualquer LLM, sem hook e sem
repo, como o próprio README já dizia da camada `ADAS.md`. Só a CAMADA DE MECANISMO (os 3 ganchos do
`host/`) estava presa a uma API específica (hooks do Claude Code: SessionStart/PreToolUse/
SubagentStart).

### Decisão
1. **Uma regra, N ganchos — nunca reimplementar a regra por harness.** Os scripts do `host/` que já
   existiam (`adas-core.sh` — extrai o núcleo do `ADAS.md`; e o `adas-inject.sh` por-repo — faixa por
   glob) ganharam duas fatias novas e reusáveis por CLI: `adas-resolve.sh` (resolve repo governado,
   fina camada sobre `adas-lib.sh`) e `adas-secret-guard.sh` (detector mecânico: comando de shell lê
   `.env` real fora do lugar? — faixa `seguranca-acesso`, regra 2). Plugins de harness NUNCA duplicam
   texto de regra em TypeScript/Python — chamam esses scripts via subprocess.
2. **Cada harness usa o gancho que resolve melhor o MESMO problema**, sem forçar equivalência 1:1 com
   o Claude Code:
   - **OpenClaw** (`host/openclaw-plugin/`, TypeScript/`definePluginEntry`): `before_prompt_build`
     (roda TODO turno — cobre sozinho os "4 buracos de decaimento" que o Claude Code precisa de 3
     hooks pra fechar, porque não há fronteira de contexto que sobreviva a uma injeção por-turno) +
     `before_tool_call` com `block: true` (bloqueio real — mais forte que o Claude Code, que hoje só
     injeta contexto no PreToolUse).
   - **Hermes** (`host/hermes-plugin/`, Python/`register(ctx)`): `ctx.register_system_prompt_section`
     (contrato documentado como "congelado em CADA sessão nova" — resolve reinjeção pós-compactação
     por desenho) + `subagent_start` (existe de verdade, confirmado lendo
     `plugins/observability/langfuse/__init__.py` do próprio Hermes, que já o usa — não assumido) +
     `pre_tool_call` com `{"action": "block", ...}` (mesmo contrato do plugin de referência real
     `plugins/security-guidance/__init__.py`, copiado do Hermes, não inventado).
3. **O que NÃO existe em cada harness fica escrito, não presumido equivalente.** Nenhum dos dois
   plugins novos cobre o JIT por-arquivo-e-glob (PASSO 6, `Edit|Write|MultiEdit` → faixa específica) —
   ficou fora de propósito, documentado como próximo passo, não fingido como coberto. Tabela
   comparativa completa: README raiz, seção "Instalação por harness".

### Consequências (números reais)
- **+** 64/64 checks verdes em `tests/smoke.sh` (10 novos: `adas-resolve.sh`/`adas-secret-guard.sh`
  isolados + `npm test`/`pytest` reais dos dois plugins novos, sem mock da lógica de produção).
- **+** `adas-openclaw`: 6/6 testes vitest, TypeScript compilando limpo contra
  `openclaw/plugin-sdk/plugin-entry` real (não um stub).
- **+** `adas-hermes`: 6/6 testes pytest, contra os scripts REAIS do `host/` (não mockados) e um
  mock mínimo de `ctx` (só a superfície documentada em `hermes_cli/plugins.py`, lida via SSH
  read-only em clawdgo — nunca escrita).
- **−** Nenhum dos dois plugins foi provado contra uma instância REAL do harness (Gateway OpenClaw
  vivo processando um turno de verdade; Hermes rodando em clawdgo). Ver "Não provado" abaixo.
- **−** Achado de segurança durante o trabalho, sem relação com o ADAS em si: `openclaw --profile
  <nome> plugins install` disparou uma migração de estado que RENOMEOU
  `~/.openclaw/exec-approvals.json` (config real do `clawdbot-gw` em produção) pra `.json.migrated`,
  mesmo com o perfil isolado ativo. Restaurado na hora, sem dano permanente confirmado (logs do
  `openclaw-gateway` sem erro, PM2 sem restart). Achado registrado em memória do agente que
  implementou — não é um problema do ADAS, é um problema da isolação `--profile`/`--dev` da própria
  OpenClaw nesta instalação; documentado aqui porque mudou COMO o plugin OpenClaw pôde ser testado
  (só via `tsc`+`vitest` locais, nunca via CLI `openclaw` contra um perfil neste servidor).

### O que NÃO foi provado (declarado, não escondido)
- Um subagente REAL do OpenClaw ou do Hermes recebendo o núcleo injetado (os testes provam que o
  HANDLER injeta certo quando chamado com um evento sintético — não que o runtime de cada harness
  chama esse handler pra turnos de subagente do mesmo jeito que chama pra turnos normais).
- `before_tool_call`/`pre_tool_call` bloqueando um comando disparado pelo MODELO de verdade em
  produção (os testes chamam o handler diretamente — não passaram pela política real de
  aprovação/exec de nenhum dos dois harnesses).
- O loader real do OpenClaw aceitando o plugin (`openclaw plugins inspect --runtime`) — não tentado
  de novo depois do achado de segurança acima, pelo motivo já explicado.
- Qualquer coisa que dependa de escrita numa instância real do Hermes — acesso era só leitura
  (SSH em clawdgo), por instrução explícita da task.

### Implementação
`host/adas-resolve.sh` (novo), `host/adas-secret-guard.sh` (novo), `host/openclaw-plugin/` (novo:
`package.json`, `openclaw.plugin.json`, `src/index.ts`, `src/index.test.ts`, `tsconfig.json`,
`vitest.config.ts`, `README.md`), `host/hermes-plugin/` (novo: `plugin.yaml`, `__init__.py`,
`test_adas_hermes.py`, `README.md`), `tests/smoke.sh` (+2 seções, 10 checks), `README.md` (PASSO 11
+ seção "Instalação por harness"), `host/README.md` (título + pointer), `.gitignore` (novo —
`node_modules/`, `dist/`, `__pycache__/`).
