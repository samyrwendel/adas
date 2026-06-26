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
