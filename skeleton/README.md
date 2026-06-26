# ADAS skeleton — esqueleto copiável

Estrutura mínima de um **ADAS** (Anti-Drift Adherence System) pra colar num projeto novo.
Conceito completo + o prompt de bootstrap: `../../adas-bootstrap-prompt.md`.

## Como usar
1. Copie esta pasta pra raiz do projeto novo:
   ```bash
   cp -r ~/projects/adas-template/skeleton/. /caminho/do/projeto/
   ```
2. Preencha os `<PLACEHOLDER>` em cada arquivo (de cima pra baixo na cadeia):
   - `.specs/` — a **constituição** (invariantes mais estáveis + valores crus). Comece por aqui.
   - `.claude/skills/<faixa>/SKILL.md` — duplique `_template/` por faixa; engorde o `description`.
   - `DECISIONS.md` — registre a 1ª decisão como `DA-001`.
   - `ADAS.md` — destile as faixas num doc portátil.
   - `.claude/settings.json` — ajuste os globs e a spec injetada por faixa.
3. Ou: aponte uma LLM pro projeto + cole o prompt de bootstrap (ele preenche tudo a partir do código real).

## A cadeia (cada camada cita a de cima)
```
.specs/ → .claude/skills/*/SKILL.md → ADAS.md → hook (settings.json)
                      +  DECISIONS.md (log append-only)
```
Princípio-mestre: **ADESÃO > INVENÇÃO**. Loop: decisão → DA-NNN + atualiza a faixa + regenera o
ADAS.md, **no mesmo commit**; **supersede, não delete**.
