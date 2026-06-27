# ADAS — Bootstrap Prompt (template reutilizável)

> **ADAS = Anti-Drift Adherence System.** Como o ADAS de carro mantém você na **faixa**, este
> mantém qualquer LLM na **faixa da spec** — em vez de inventar cor, estrutura, escopo, nomenclatura
> ou texto novos. Princípio-mestre: **ADESÃO > INVENÇÃO** (consolidar > reescrever · padronizar >
> inventar · medir antes de substituir · nunca regredir o que funciona).

## A arquitetura (4 camadas + 1 loop)

```
.specs/  (CONSTITUIÇÃO: invariantes mais estáveis + valores crus; compartilhada entre repos)
   │  extraída/adaptada →
.claude/skills/*/SKILL.md  (FAIXAS: escopo do projeto, AUTO-DISPARADAS via frontmatter)
   │  destiladas →
ADAS.md  (PORTÁTIL: cola em qualquer LLM, sem hook/sem repo)
   │  injetada JIT →
.claude/settings.json hook  (REFORÇO no instante da edição — só Claude Code)
   +
DECISIONS.md  (LOG append-only de decisões DA-NNN, com cadeia de supersede)
```

Cada camada **cita a de cima**. Mudou o canônico → propaga pra baixo → regenera. O **loop de
auto-aprimoramento** não é "lembrar de atualizar": é uma **hierarquia de derivação** (o de baixo é
sempre gerado do de cima) + 3 disciplinas:
1. **Mesmo commit** — decisão + faixa + doc andam juntos.
2. **Supersede, não delete** — número nunca reusado; history vira trilha de auditoria.
3. **Regenerar do canônico** — `ADAS.md` é derivado das faixas; faixa é derivada de `.specs/`. Divergiu, regenera.

Os dois pontos finos: **(a)** o `frontmatter.description` é o roteador — gatilho magro = faixa que
nunca dispara; liste todo sinônimo E sintoma ("tá feio", "quebrado", "desalinhado"). **(b)** `.specs/`
separado das faixas não é redundância — é **nível de estabilidade** (constituição rara/compartilhada
≠ faixa que evolui com o projeto).

---

## O PROMPT (cole numa LLM capaz, apontando pro projeto)

```text
PAPEL: Você é o arquiteto de governança deste projeto. Construa um "ADAS"
(Anti-Drift Adherence System): um conjunto de FAIXAS (guard-rails) que mantêm
qualquer assistente de IA dentro das specs do projeto, em vez de inventar cor,
estrutura, escopo, nomenclatura ou texto novos. Princípio-mestre: ADESÃO > INVENÇÃO
(consolidar>reescrever, padronizar>inventar, medir antes de substituir, nunca
regredir o que funciona).

MODO DE CONTEXTO:
- PROJETO EM ANDAMENTO (já tem código): primeiro AUDITE o repo. Faça o inventário
  dos invariantes REAIS — tokens de design, componentes canônicos, convenções de
  pasta/arquivo, nomenclatura/termos, config/.env, caminhos críticos (dinheiro,
  auth, ações irreversíveis), integrações externas. Derive o ADAS do que EXISTE
  (engenharia reversa); aponte inconsistências; NÃO imponha convenção nova.
- PROJETO NOVO: me entreviste com as perguntas fundadoras (identidade visual?
  stack/arquitetura? escopo in/out? termos canônicos e proibidos? caminho crítico
  e suas regras? idiomas?). Derive das respostas + defaults sensatos; marque toda
  suposição.

SETUP — COPIE O ESQUELETO CANÔNICO (NÃO recrie a estrutura do zero). Rode na RAIZ do
projeto destino:
  git clone --depth 1 https://github.com/samyrwendel/adas /tmp/adas \
    && cp -r /tmp/adas/skeleton/. . && rm -rf /tmp/adas
Isso traz a estrutura PRONTA (com <PLACEHOLDER>): .specs/SKILL.md + .specs/tokens.css,
.claude/skills/_template/SKILL.md, .claude/settings.json (hook), DECISIONS.md, ADAS.md.
Os PASSOS abaixo PREENCHEM esses arquivos — não recriam a estrutura. Confirme que os
arquivos foram copiados antes de seguir (se o projeto já tiver .claude/, faça merge,
não sobrescreva).

PASSO 0 — CAMADA .specs/ (CONSTITUIÇÃO): identifique os 1–3 invariantes MAIS estáveis
e compartilhados entre repos/superfícies (tipicamente: identidade visual + tokens
crus; talvez contratos/endereços; talvez vocabulário de marca). PREENCHA os arquivos
JÁ COPIADOS `.specs/SKILL.md` e `.specs/tokens.css` (deixe-os num lugar COMPARTILHADO,
fora das skills de um repo só). As faixas (PASSO 2) são GERADAS daqui e DEVEM citar a
procedência ("extraído de .specs/…"). Liste os ESPELHOS (onde cada valor canônico é
copiado) pra a propagação ser explícita.

PASSO 1 — IDENTIFIQUE AS FAIXAS (só as que se aplicam; faixa = domínio onde o drift
causa retrabalho). Candidatas: Visual/Design · Arquitetura/Padrões de código
(módulos canônicos + lista "reusar-não-recriar" + anti-padrões) · Produto/Escopo ·
Nomenclatura/Termos · Caminho crítico (dinheiro/segurança — regras + testes) ·
Idioma/Copy/i18n · **Segredos & Acesso** (token/.env/chave/repo) · <faixa específica do projeto>.
A faixa **Segredos & Acesso** (`.claude/skills/seguranca-acesso/`) já vem PREENCHIDA no esqueleto
(regras universais: nunca commitar segredo, token least-privilege, não caçar credencial, confirmar
op de repo irreversível) + o gate `scripts/check-secrets.sh` — MANTENHA, não recrie; só ajuste o específico do projeto.

PASSO 2 — Para CADA faixa, DUPLIQUE a pasta-modelo `.claude/skills/_template/` →
`.claude/skills/<nome>/` e preencha o `SKILL.md` (apague `_template/` no fim):
  FRONTMATTER no PADRÃO OFICIAL Anthropic Skills (name + description; when_to_use é OPCIONAL/extra):
    - NÃO reinvente o formato da skill — siga `anthropics/skills` (`spec/` + `template/`) + `skill-creator`;
      o ADAS só soma a governança no corpo. (Faixa do ADAS = Anthropic Skill.)
    - description = TODO o triggering e "PUSHY" (guidance oficial p/ combater UNDERtriggering): lista
      exaustiva de gatilhos + SINTOMAS + "use SEMPRE que …, MESMO sem pedir explícito". É o roteador.
    - Otimize o trigger com o `skill-creator` (description-improver). when_to_use = extra (oficial = tudo no description).
  CORPO com:
    - QUANDO SE APLICA (resumo dos gatilhos)
    - FONTE DA VERDADE (onde vivem os valores/componentes/configs canônicos —
      caminhos exatos; "nunca hardcodar, sempre reusar via X") + PROCEDÊNCIA
      ("extraído de .specs/…")
    - FAÇA / NÃO FAÇA (numerado, incluindo a lista de LEGADOS PROIBIDOS)
    - INVENTÁRIO REUSE-FIRST (o que JÁ existe e DEVE ser reusado antes de criar novo)
    - LEITURAS OBRIGATÓRIAS + TRAVA (padrão do spec-skills, cura da reinvenção):
      preencha `references/mandatory-readings.md` (os arquivos REAIS a ler antes de
      editar nesta faixa) + `references/few-shots/` (exemplos canônicos preenchidos) +
      a seção "Trava obrigatória" (pare na ambiguidade; leia o código real antes de agir).

PASSO 3 — PREENCHA o LOG DE DECISÕES `DECISIONS.md` (já no esqueleto, estilo ADR). Cada entrada:
  "## DA-NNN — Título" + "Status ✅ Aceita | 🔄 Supersedida por DA-MMM · Data" +
  Contexto / Decisão / Consequências (números reais quando der) / Implementação
  (arquivos:linha). Numerar sequencial, NUNCA reusar. Mudar decisão = marcar a
  antiga como Supersedida (nunca apagar). Índice rápido no topo.

PASSO 4 — PREENCHA o doc PORTÁTIL `ADAS.md` (já no esqueleto): autocontido (funciona
colado em QUALQUER LLM, sem acesso ao repo). Cabeçalho: procedência + data + quais decisões
reflete + "fonte da verdade = .specs/ e as faixas; se divergirem, regenere".
Preâmbulo "Como usar": ler ANTES de produzir qualquer coisa; adesão > invenção.
Tabela de roteamento "tarefa → faixa".

PASSO 5 — Escreva o PROTOCOLO OPERACIONAL (loop de auto-aprimoramento) dentro da
faixa de Decisões:
  - TODA decisão / novo entendimento (escolha entre alternativas, trade-off aceito,
    config com efeito permanente, reversão) → uma entrada DA-NNN, E dobrar de volta
    na(s) faixa(s) afetada(s), NO MESMO COMMIT.
  - Mudou .specs/ → propaga pros espelhos → atualiza a faixa → REGENERA o ADAS.md.
  - Supersede, não delete. O log é append-only + trilha de auditoria.
  - Análise de impacto antes de "feito": ao tocar uma função, mapear o raio
    (callers, schemas, docs, testes, espelhos) e atualizar no mesmo commit; flagar
    explicitamente o que ficou de fora de propósito.

PASSO 6 (só Claude Code) — AJUSTE o hook PreToolUse (stub já em `.claude/settings.json`):
para cada faixa, no `Edit|Write` de arquivos que casem com os globs dela, injete a spec
destilada como additionalContext (enforcement JIT no momento da edição). Duplique o item
do array por faixa.

PASSO 7 (opcional, mas FORTEMENTE recomendado p/ caminho crítico) — FAIXAS EXECUTÁVEIS
+ GATE: transforme cada NÃO-FAÇA crítico (sobretudo do caminho do dinheiro/segurança)
num check RODÁVEL em scripts/check-<nome>.sh (duplique scripts/check-_template.sh; sai
!= 0 quando VIOLA, com mensagem ACIONÁVEL). Wire um gate de pré-deploy/CI:
  - MONEY-PATH e SEGURANÇA bloqueiam (SEVERITY=block, build falha): ex. callback de
    pagamento sem handler, vazamento de RLS, mistura de unidade/moeda.
  - Limpeza/estilo só AVISAM (SEVERITY=warn): ex. botões/handlers órfãos, TODO.
  - Gate no package.json: "deploy": "SEVERITY=block bash scripts/check-*.sh && build && <restart>".
  Registre o gate como DA-NNN e cite o check na faixa ("enforcement: scripts/check-<nome>.sh").
  O hook pega no momento da EDIÇÃO; o check pega no COMMIT/DEPLOY — as duas pontas.
  ENGINE PRONTO p/ faixas de UI (design/i18n): o esqueleto já traz checadores Node
  profile-driven em `.claude/skills/adas-check/scripts/` — `adas-check.js` (runner/compare),
  `check-design.js` (cor fora do token), `check-i18n.js` (paridade de locale + hardcoded),
  `align-design.js` (auto-fix de cor, dry-run). Defina a "pista" em `.adas/profile.json`
  (ou `check-design.js <dir> --detect-tokens` gera das CSS vars). É o espelho de máquina da `.specs/`.

PASSO 8 (opcional) — AUTO-AUDITORIA DO ADAS (o ADAS governa o ADAS): use o
scripts/check-adas.sh (já vem pronto e genérico) no gate. Pega o modo de falha nº1
desses sistemas — a derivação .specs → faixas → ADAS.md rotar em SILÊNCIO. Checa:
PLACEHOLDER não preenchido; faixa sem frontmatter name/description = BLOCK (não
dispara); faixa sem PROCEDÊNCIA (invariante sem origem = chute); DRIFT (faixa/.specs
commitada DEPOIS do ADAS.md → regenere); DA-NNN citada mas ausente do DECISIONS.md.
WARN por padrão, exceto frontmatter quebrado.

PASSO 9 (opcional) — ONBOARDING / ÂNCORA: preencha `AGENTS.md` (já copiado) — o arquivo
que qualquer LLM/ferramenta lê no PRIMEIRO contato e que aponta pro `ADAS.md` ("leia o
ADAS antes de produzir qualquer coisa"). Espelhe (cp) ou symlink pro nome que cada
ferramenta lê no boot: `CLAUDE.md` (Claude Code), `.cursorrules` (Cursor), etc. Sem
âncora, a governança existe mas a ferramenta não a descobre sozinha.

SAÍDA: PREENCHA os arquivos COPIADOS (.specs/, .claude/skills/<faixa>/SKILL.md,
DECISIONS.md, ADAS.md, AGENTS.md, o hook, scripts/check-*), remova `_template/` e me mostre o índice. Antes de
finalizar, me peça pra confirmar os invariantes que você reverse-engineerou.
```

---

## O hook (Claude Code — o que faz "colar")

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_input.file_path // empty' | { read -r f; case \"$f\" in *\"/src/\"*) printf '%s' '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"ADAS <faixa>: <spec destilada em 1 parágrafo, com proibidos>. Spec: <caminho/da/faixa>\"}}' ;; esac; } 2>/dev/null || true",
        "timeout": 10,
        "statusMessage": "ADAS <faixa>"
      }]
    }]
  }
}
```

Em LLM **sem** hook (ChatGPT/Gemini/etc.), o substituto é colar o **`ADAS.md` portátil** como
system/primeiro turno — por isso ele existe separado das faixas.

## Esqueleto canônico (o prompt já manda copiar — ver SETUP)
O esqueleto vive em **github.com/samyrwendel/adas** (`skeleton/`): `.specs/` + `skills/_template/SKILL.md`
+ `DECISIONS.md` + `ADAS.md` + `.claude/settings.json`. O SETUP do prompt já faz o `git clone … && cp`
pra dentro do projeto; os PASSOS preenchem os `<PLACEHOLDER>`. Manual:
```bash
git clone --depth 1 https://github.com/samyrwendel/adas /tmp/adas && cp -r /tmp/adas/skeleton/. . && rm -rf /tmp/adas
```
