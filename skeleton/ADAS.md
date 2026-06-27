# <PROJETO> ADAS — Governança do Projeto (pacote para LLMs)

> **O que é isto.** "ADAS" (Anti-Drift Adherence System) é o conjunto de **faixas/guard-rails** que
> mantêm qualquer assistente de IA dentro das specs do projeto — em vez de inventar cor, estrutura,
> escopo, nomenclatura ou texto novos. Este arquivo é a destilação **autocontida** (cola em qualquer LLM).
>
> **Procedência.** Gerado em **<data>** a partir de `.specs/` + `.claude/skills/*/SKILL.md` +
> `.claude/settings.json`. Reflete **DA-001…DA-NNN** (ver `DECISIONS.md`).
> **Fonte da verdade = `.specs/` e as faixas; se este doc divergir, regenere.**

---

## Como usar (qualquer LLM)
1. **Leia ANTES de produzir qualquer coisa** — código, UI, texto, decisão, feature.
2. **Adesão > invenção.** Se já existe token/componente/padrão/decisão, **use o que existe**.
3. **Consolidar > reescrever · padronizar > inventar · medir antes de substituir · nunca regredir o que funciona.**
4. Lógica pode vir de referências; **a identidade visual/de marca NUNCA**. Nada mockado/hardcoded — fonte real.

### Escada de decisão — pare no 1º degrau que resolve *(padrão do [ponytail](https://github.com/DietrichGebert/ponytail), MIT)*
ANTES de escrever código novo, desça a escada e **pare no primeiro degrau que já resolve** — "o melhor
código é o que você não escreve". É o operacional do "adesão > invenção":
1. **Precisa existir?** (YAGNI — o pedido pede isso mesmo, agora?)
2. **Já existe no projeto?** Reusa o helper/componente/padrão que está lá.
3. **A stdlib resolve?** Usa a biblioteca-padrão.
4. **A plataforma faz nativo?** Prefere o recurso nativo.
5. **Uma dependência já instalada resolve?** Usa o que já tem.
6. **Dá uma linha?** Faz em uma.
7. **Só então:** o mínimo que funciona — menor diff, menos arquivos, deletar > adicionar.
> **Os não-negociáveis NÃO são "preguiça":** comprehensão do problema, validação no limite de confiança,
> erro que evita perda de dado, segurança/acessibilidade e o **caminho do dinheiro testado** ficam SEMPRE
> (faixa `seguranca-acesso` + os `check-*.sh`). "Fazer menos" nunca erode a rede.

### Atalho consciente = marcador `adas:` no lugar exato *(débito honesto)*
Tomou um atalho de propósito? Deixe uma migalha **na linha** nomeando o teto + o caminho de upgrade:
```
// adas: gateado só neste card; varrer telas irmãs — ver DA-NNN
```
`node .claude/skills/adas-check/scripts/adas-debt.js .` junta todos num relatório `arquivo:linha`. É o
débito **localizado e real** (o que VOCÊ deferiu) — diferente do `DECISIONS.md` (pesado/deliberado) e do
ratchet por contagem. Quite antes de fechar a faixa. **Estado geral:** `scripts/adas-report.sh` conta
faixas/DAs/débito/saúde e **se recusa a inventar "% de aderência"** (só mostra o medível — anti-chute).

### Mapa rápido — qual faixa para qual tarefa
| Sua tarefa toca… | Faixa |
|---|---|
| <qualquer coisa visível: tela, cor, CSS, layout, ícone> | **1. <Design>** |
| <texto / tradução / idioma> | **2. <Idioma>** |
| <escopo, prioridade, monetização> | **3. <Produto>** |
| <padrões de código / arquitetura / módulos canônicos> | **4. <App/Arquitetura>** |
| <tomar/mudar/questionar uma decisão> | **5. <Decisões>** |

---

## 0. Reforço automático (hook ADAS — só Claude Code)
Um hook `PreToolUse` (`.claude/settings.json`) injeta a faixa relevante a cada `Edit|Write` de arquivo
que casa com o glob da faixa. **Não funciona em outra LLM** — por isso este documento existe.

## 1. FAIXA: <Design> — DA-<NNN>
**Quando aplicar:** <gatilhos>. **Fonte da verdade:** `.specs/tokens.css` + `<espelhos>`.
<resumo: identidade, tokens, componentes canônicos, FAÇA/NÃO FAÇA, legados PROIBIDOS.>

## 2. FAIXA: <Idioma> — DA-<NNN>
<resumo da faixa.>

## 3. FAIXA: <Produto> — DA-<NNN>
<resumo da faixa.>

## 4. FAIXA: <App/Arquitetura> — DA-<NNN>
<superfícies, componentes/módulos canônicos a REUSAR, débito técnico a não piorar, caminho crítico + testes.>

## 5. FAIXA: Decisões — DA-NNN no `DECISIONS.md`
**Quando aplicar:** SEMPRE que uma decisão for tomada/mudada/questionada.
Loop: decisão → DA-NNN + atualiza a faixa + regenera este doc, **no mesmo commit**; **supersede, não delete**;
análise de impacto (callers/schemas/docs/testes/espelhos) antes de "feito".

### Índice de decisões (texto completo em `DECISIONS.md`)
- **DA-001** — <título>
