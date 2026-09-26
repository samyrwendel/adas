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

---

## Decisão Arquitetural DA-002 — check-adas ganha TETO de gatilho (trigger-coringa), par do piso (trigger-magro)

**Status:** ✅ Aceita · **Data:** 2026-09-13

### Contexto
O `check-adas.sh` já tinha `thin_issue` — o PISO do gatilho: faixa com description curta / poucos
gatilhos = WARN "engorde". Faltava o TETO. Uma auditoria da instância clawd (aplicando o prompt
público de auditoria de agentes da OpenAI) achou o modo de falha oposto: descriptions com gatilhos
CORINGA — tokens semanticamente vazios (`'????'`, `'ok'`, `'aprovado'`, `'pode fazer'`, `'posso
apagar?'`) que casam QUALQUER mensagem. O roteador acorda a faixa no ruído: contexto queimado,
governança injetada em "ok". (Origem na instância: DA-276 do diário do servidor.)

### Decisão
Adicionar `coringa_issue` — o TETO, par de `thin_issue`. Reprova, como WARN, duas classes MECÂNICAS
e portáveis de token entre aspas: (1) só pontuação (`'????'`, `'!!!'`); (2) ack vazio por match
EXATO do token (`ok`, `aprovado`, `pode fazer`, …) — exato pra NÃO colidir com sigla de domínio
(`DA`, `HF`, `OI`). Sem blocklist de frase (não generalizaria). A classe "pergunta genérica sem
substantivo de domínio" (`'tá seguro?'`) fica fora do escopo mecânico — exigiria NLP; vai pra
revisão humana. Piso engorda, teto poda: juntos definem o gatilho equilibrado.

### Consequências
- `check-adas.sh` (skeleton) +31 linhas: função `coringa_issue` + loop 2c (WARN, só GOVERNADAS).
- Teste `scripts/tests/check-coringa.test.sh` (6 casos, dois lados): dispara em coringa; limpo em
  gatilho de domínio, sigla curta e pergunta-genérica. Zero falso-positivo (a regra crua "token
  <=2 chars" foi descartada por colidir com `DA`).
- Retroativo na instância: as 3 faixas do clawd foram podadas antes (DA-276) e passam limpas.

### Implementação
`skeleton/scripts/check-adas.sh` (função + loop 2c), `skeleton/scripts/tests/check-coringa.test.sh`
(novo). Espelhado na cópia de instância `~/scripts/check-adas.sh` (fora deste repo).

---

## Decisão Arquitetural DA-003 — checks de qualidade do da-index sobem de WARN→FAIL (gate real), com grandfather prospectivo no c6

**Status:** ✅ Aceita · **Data:** 2026-09-13

### Contexto
O `da-index.sh` tinha c1..c7 como checks de qualidade WARN (advisório puro: imprimiam, mas `run_quality_checks` sempre fazia `return 0` e `cmd_check` ignorava o retorno). O comentário do c1 já previa o flip ("300 seria FAIL — ainda não ligado"). A DA-181 §2.6g exige o harness de fixtures passando ANTES de ligar qualquer FAIL.

### Decisão
c1-c5 e c7 passam a FAIL (setam `fail=1`; `run_quality_checks` faz `return $fail`; `cmd_check` faz `|| rc=1`) → bloqueiam commit pelo pre-commit. O c6 (lição cita nome próprio/caminho) vira FAIL só para DA > `DA_INDEX_C6_GRANDFATHER` (default 276), porque o corpo das DA antigas é imutável (append-only) e não se rasura — abaixo do corte segue WARN. c10/c11 seguem WARN.

### Consequências
- `skeleton/scripts/da-index.sh`: `fail` + const c6gf + flip c1-c5,c7 + severidade por número no c6 + `return $fail` + `cmd_check … || rc=1`.
- `skeleton/scripts/tests/da-index/run-tests.sh`: c2/c4 do fixture agora asseridos como FAIL; a idempotência passa a checar AUSÊNCIA de DIVERGE (o exit passou a refletir FAIL de qualidade); nova seção prova o c6 grandfather (>corte FAIL, ≤corte WARN, check exit≠0). 52 asserções verdes; as 2 falhas restantes (DA-008/DA-012, geração de índice) são ANTERIORES a esta mudança e ficam para correção separada.
- Origem/autorização: emenda constitucional autorizada pelo dono (protocolo de decisão + supersede/grandfather).

### Implementação
`skeleton/scripts/da-index.sh`, `skeleton/scripts/tests/da-index/run-tests.sh`. Espelhado nas cópias de instância `~/scripts/da-index.sh` e `claude-tg-tmux/scripts/da-index.sh` (fora deste repo).

## Decisão Arquitetural DA-004 — DA que proíbe só vale com MECANISMO que reprova a violação (check-da-mecanismo)

**Status:** ✅ Aceita · **Data:** 2026-09-25

**Regra:** DA cuja linha Regra contenha proibição ou exclusividade (nunca, proibido, não pode, jamais, somente, só) só entra com uma linha `**Mecanismo:**` citando caminho de arquivo/unit que EXISTE; DA nova sem isso reprova o `check-adas.sh` (BLOCK) e o pre-commit; DA anterior ao corte vira fila (WARN com contagem).
**Mecanismo:** `skeleton/scripts/check-da-mecanismo.sh` (e o espelho `skeleton-v4/scripts/check-da-mecanismo.sh`), chamado pelo `skeleton/scripts/check-adas.sh` (check 10b) e pelo pre-commit gerado por `skeleton/scripts/install-hooks.sh` (gate 2b); teste `skeleton/scripts/tests/check-da-mecanismo.test.sh`.

### Contexto
Na instância de origem, em 21–25/09, o dono pegou 2–3 furos do mesmo tipo: a DA dizia "nunca X" e nada barrava X (testes escrevendo no estado real de um robô; aviso de conta saindo pelo bot proibido). Uma DA anterior já pedia "regra + mecanismo" na formalização, mas nada checava. A checagem tinha que ser do mesmo tipo que ela exige: automática.

### Decisão
- Proibição detectada só no PARÁGRAFO da Regra (não no corpo da DA: "só" descritivo no Motivo não dispara). Falso positivo dentro da Regra se resolve reescrevendo a Regra, não isentando.
- Mecanismo vale se pelo menos um caminho citado existe: `~/…`, absoluto, relativo à raiz, nome solto em `scripts/`, ou unit systemd (`systemctl [--user] cat`).
- DA nova = `data:` ≥ `DA_MECANISMO_DESDE` (padrão 2026-09-26). Diário sem data usa corte por NÚMERO em `.adas/da-mecanismo-corte` (a maior DA na adoção); sem esse arquivo, DA sem data fica na fila.
- O template do skeleton-v4 (DA-001, "nunca é apagada") ganhou o próprio `**Mecanismo:**` — senão todo projeto novo nasceria reprovado.

### Consequências
- Registrar decisão com proibição fica mais lento (a trava tem que existir ou nascer junto). DA de preferência (sem proibição) não muda.
- Existência do caminho não prova que ele reprova — o check fecha a porta de DA sem trava nenhuma; a qualidade da trava continua sendo revisão.
- Complementa o `check-mecanismo.sh` do skeleton-v4 (que cobra os invariantes do núcleo do ADAS.md): aquele governa o ADAS.md, este governa o diário.
