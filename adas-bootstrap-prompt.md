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

PASSO 0 — CAMADA .specs/ (CONSTITUIÇÃO): identifique os 1–3 invariantes MAIS estáveis
e compartilhados entre repos/superfícies (tipicamente: identidade visual + tokens
crus; talvez contratos/endereços; talvez vocabulário de marca). Materialize-os como
arquivos-fonte LITERAIS (ex.: .specs/tokens.css, .specs/SKILL.md) num lugar
COMPARTILHADO, fora das skills de um repo só. As faixas (PASSO 2) são GERADAS daqui
e DEVEM citar a procedência ("extraído de .specs/…"). Liste os ESPELHOS (onde cada
valor canônico é copiado) pra a propagação ser explícita.

PASSO 1 — IDENTIFIQUE AS FAIXAS (só as que se aplicam; faixa = domínio onde o drift
causa retrabalho). Candidatas: Visual/Design · Arquitetura/Padrões de código
(módulos canônicos + lista "reusar-não-recriar" + anti-padrões) · Produto/Escopo ·
Nomenclatura/Termos · Caminho crítico (dinheiro/segurança — regras + testes) ·
Idioma/Copy/i18n · <faixa específica do projeto>.

PASSO 2 — Para CADA faixa, crie uma pasta .claude/skills/<nome>/SKILL.md com:
  FRONTMATTER yaml { name, description, when_to_use }:
    - description = lista EXAUSTIVA de gatilhos E SINTOMAS (como o usuário fala
      torto). É o que dispara a faixa — gatilho magro = faixa que nunca acorda.
    - when_to_use = cenários + globs de arquivo onde a faixa vale.
  CORPO com:
    - QUANDO SE APLICA (resumo dos gatilhos)
    - FONTE DA VERDADE (onde vivem os valores/componentes/configs canônicos —
      caminhos exatos; "nunca hardcodar, sempre reusar via X") + PROCEDÊNCIA
      ("extraído de .specs/…")
    - FAÇA / NÃO FAÇA (numerado, incluindo a lista de LEGADOS PROIBIDOS)
    - INVENTÁRIO REUSE-FIRST (o que JÁ existe e DEVE ser reusado antes de criar novo)

PASSO 3 — Crie o LOG DE DECISÕES DECISIONS.md (estilo ADR). Cada entrada:
  "## DA-NNN — Título" + "Status ✅ Aceita | 🔄 Supersedida por DA-MMM · Data" +
  Contexto / Decisão / Consequências (números reais quando der) / Implementação
  (arquivos:linha). Numerar sequencial, NUNCA reusar. Mudar decisão = marcar a
  antiga como Supersedida (nunca apagar). Índice rápido no topo.

PASSO 4 — Consolide num doc PORTÁTIL ADAS.md: autocontido (funciona colado em
QUALQUER LLM, sem acesso ao repo). Cabeçalho: procedência + data + quais decisões
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

PASSO 6 (só Claude Code) — fie um hook PreToolUse em .claude/settings.json que, ao
Edit|Write de arquivos que casem com os globs de uma faixa, injete a spec destilada
daquela faixa como additionalContext (enforcement JIT no momento da edição).

SAÍDA: crie os arquivos (.specs/, .claude/skills/*/SKILL.md, DECISIONS.md, ADAS.md,
o hook) e me mostre o índice. Antes de finalizar, me peça pra confirmar os
invariantes que você reverse-engineerou.
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

## Esqueleto vazio
Há um esqueleto copiável em `~/projects/adas-template/skeleton/` (.specs/ + skills/_template/SKILL.md +
DECISIONS.md + ADAS.md + .claude/settings.json). Copie pra um projeto novo e preencha os `<PLACEHOLDER>`.
