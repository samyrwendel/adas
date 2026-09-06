# <PROJETO> ADAS — Governança do Projeto (pacote para LLMs)
<!-- adas-modo: doc -->

> **O que é isto.** "ADAS" (Anti-Drift Adherence System) é o conjunto de **faixas/guard-rails** que
> descrevem o que este projeto já decidiu — token, estrutura, escopo, nomenclatura, texto — para o
> assistente de IA usar o que existe em vez de inventar. Este arquivo é a destilação **autocontida**.
>
> **Modo doc: quem aplica a regra é o dono, presente na sessão.** Este documento lembra; ele não
> impede nada. O que a máquina cobra de verdade está em `scripts/check-*.sh` e no pre-commit.
>
> **Procedência.** Gerado em **<data>** a partir de `.specs/` + `.claude/skills/*/SKILL.md`.
> Reflete **DA-001…DA-NNN** (ver `DECISIONS.md`). **Fonte da verdade = `.specs/` e as faixas; se
> este doc divergir, regenere.**

---

<!-- adas-core-start -->
<!-- NÚCLEO: o que o runtime host (opcional) reinjeta em SessionStart/SubagentStart.
     Mantenha ~30-45 linhas: como usar + escada + mapa de faixas. Fora dos marcadores NÃO é reinjetado. -->
## Como usar (qualquer LLM)
1. **Leia ANTES de produzir qualquer coisa** — código, UI, texto, decisão, feature.
2. **Adesão > invenção.** Se já existe token/componente/padrão/decisão, **use o que existe**.
3. **Consolidar > reescrever · padronizar > inventar · medir antes de substituir · nunca regredir o que funciona.**
4. Lógica pode vir de referências; **a identidade visual/de marca NUNCA**. Nada mockado/hardcoded — fonte real.

### Escada de decisão — pare no 1º degrau que resolve *(padrão do [ponytail](https://github.com/DietrichGebert/ponytail), MIT)*
1. **Precisa existir?** (o pedido pede isso mesmo, agora?)
2. **Já existe no projeto?** Reusa o helper/componente/padrão que está lá.
3. **A stdlib resolve?** 4. **A plataforma faz nativo?** 5. **Uma dependência já instalada resolve?**
6. **Dá uma linha?** 7. **Só então:** o mínimo que funciona — menor diff, menos arquivos, deletar > adicionar.
> **Os não-negociáveis NÃO são "preguiça":** compreensão do problema, validação no limite de confiança,
> erro que evita perda de dado, segurança/acessibilidade e o **caminho do dinheiro testado** ficam SEMPRE
> (faixa `seguranca-acesso` + os `check-*.sh`).

### Atalho consciente = marcador `adas:` na linha exata *(débito honesto)*
```
// adas: gateado só neste card; varrer telas irmãs — ver DA-NNN
```
`scripts/adas-report.sh` conta faixas/DAs/débito/saúde e **se recusa a inventar "% de aderência"**.

### Mapa rápido — qual faixa para qual tarefa
| Sua tarefa toca… | Faixa |
|---|---|
| <qualquer coisa visível: tela, cor, CSS, layout, ícone> | **1. <Design>** |
| <texto / tradução / idioma> | **2. <Idioma>** |
| <padrões de código / arquitetura / módulos canônicos> | **3. <App/Arquitetura>** |
| segredo, token, `.env`, credencial, operação de repo | **`seguranca-acesso`** |
| tomar/mudar/questionar uma decisão | **Decisões** (`DECISIONS.md`) |
<!-- adas-core-end -->

---

## 0. Reforço automático (hooks — só Claude Code)
1. **JIT por faixa** — `PreToolUse` (`.claude/settings.json` → `.claude/hooks/adas-inject.sh`) injeta a
   faixa relevante a cada `Edit|Write|MultiEdit` de arquivo que casa com o glob da faixa.
2. **Runtime anti-decaimento** (opcional, `host/` do repo adas): reinjeta o NÚCLEO acima após
   compaction/resume e em todo subagente.

**Não funciona em outra LLM** — por isso este documento existe.

## 1. FAIXA: <Design> — DA-<NNN>
**Quando aplicar:** <gatilhos>. **Fonte da verdade:** `.specs/tokens.css` + `<espelhos>`.
<resumo: identidade, tokens, componentes canônicos, FAÇA/NÃO FAÇA, legados PROIBIDOS.>

## 2. FAIXA: <Idioma> — DA-<NNN>
<resumo da faixa.>

## 3. FAIXA: <App/Arquitetura> — DA-<NNN>
<superfícies, componentes/módulos canônicos a REUSAR, débito técnico a não piorar, caminho crítico + testes.>

## 4. FAIXA: Decisões — DA-NNN no `DECISIONS.md`
**Quando aplicar:** SEMPRE que uma decisão for tomada/mudada/questionada — **e em todo fix aprovado**.
Loop: decisão → `scripts/da-new.sh` → preenche a DA + atualiza a faixa + regenera este doc, **no mesmo
commit**; **supersede, não delete**. Fix aprovado que representa uma **CLASSE** de erro → a regra dobra na
**faixa sensível** que dispara no momento certo (`description`/hook/check) — aprendizado só em chat/doc
morto NÃO conta como registrado.

### Índice de decisões (texto completo em `DECISIONS.md`, índice gerado em `DECISIONS-INDEX.md`)
- **DA-001** — Este projeto adota o ADAS
