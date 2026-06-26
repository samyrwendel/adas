# <PROJETO> — Registro de Decisões (DA-NNN)

> Log **append-only**. Toda decisão (escolha entre alternativas, trade-off aceito, config com efeito
> permanente, reversão) vira uma entrada numerada. **Numerar sequencial, nunca reusar.** Mudar uma
> decisão = marcar a antiga `🔄 Supersedida por DA-MMM` (nunca apagar). Atualizar o índice + a faixa
> afetada + regenerar o `ADAS.md` **no mesmo commit**.

## Índice
- **DA-001** — <título curto>

---

## Protocolo operacional (o loop de auto-aprimoramento)
1. **Quando registrar:** escolha técnica/produto, fee/config permanente, trade-off consciente, reversão.
2. **No mesmo commit:** entrada DA-NNN aqui + índice + a(s) faixa(s) `.claude/skills/*/SKILL.md` afetada(s) + regenerar `ADAS.md`.
3. **Supersede, não delete.** Número nunca reusado; a antiga vira `🔄 Supersedida por DA-MMM`.
4. **Análise de impacto antes de "feito":** ao tocar uma função, mapear o raio (callers, schemas, docs,
   testes, espelhos de token/i18n) e atualizar no mesmo commit; **flagar** o que ficou de fora de propósito.
5. **Mudou `.specs/`** → propagar pros espelhos → atualizar a faixa → regenerar `ADAS.md`.

---

## Decisão Arquitetural DA-001 — <Título curto>

**Status:** ✅ Aceita · **Data:** <YYYY-MM-DD>

### Contexto
<1 parágrafo: que problema/escolha existia.>

### Decisão
<o que foi decidido — tabela se houver múltiplos contextos.>

### Consequências (números reais quando der)
- **+** <ganho medido>
- **−** <custo/limitação>

### Implementação
<arquivos/envs tocados, com `arquivo:linha`.>
