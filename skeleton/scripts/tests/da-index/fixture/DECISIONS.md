# DECISIONS.md — FIXTURE de teste do harness de da-index.sh (skeleton/scripts/tests/da-index/)
# Não é o diário real. Cobre: DA com Regra, DA só com ### Decisão, número duplicado,
# DA com paste de terminal, DA com tags compostas (cabeça + consolida), membro sem tag (via tsv).

## DA-001 — DA com Regra explícita
`escopo: produto` · `saga: saga-teste` · `data: 2026-01-01`
**Regra:** Regra explícita de teste, deve aparecer verbatim no índice e na NA.
**Motivo:** motivo de teste, uma linha.
**Trade-off:** trade-off de teste, uma linha.
**Lição:** nenhuma (específica)

## DA-002 — DA só com Decisão, formato antigo
**Status:** ✅ Aceita · **Data:** 2026-01-02

### Contexto
Contexto qualquer do formato antigo, sem tags novas.

### Decisão
Esta é a linha de decisão do formato antigo, sem Regra explícita.

### Consequências
- **+** ganho qualquer

## DA-003 — Primeira ocorrência do número duplicado
`escopo: instância`
**Regra:** primeira versão do texto duplicado (deve virar DA-003a).

## DA-003 — Segunda ocorrência do número duplicado
`escopo: instância`
**Regra:** segunda versão do texto duplicado (deve virar DA-003b).

## DA-004 — DA com paste de terminal colado sem querer
`escopo: produto` · `saga: saga-teste`
**Regra:** Regra antes do paste, deve aparecer no índice normalmente.

commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Author: Teste <teste@example.com>
Date:   Thu Jan 1 00:00:00 2026 -0400

    mensagem de commit de teste 1

commit bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
Author: Teste <teste@example.com>
Date:   Thu Jan 1 00:00:01 2026 -0400

    mensagem de commit de teste 2

commit cccccccccccccccccccccccccccccccccccccccc
Author: Teste <teste@example.com>
Date:   Thu Jan 1 00:00:02 2026 -0400

    mensagem de commit de teste 3

**Depois do paste:** o show tem que pular o bloco acima e mostrar isto.

## DA-005 — DA-cabeça com tags compostas, consolidando DA-001
`escopo: produto,instância` · `saga: saga-teste, outra-saga` · `data: 2026-01-05` · `refs: DA-001` · `consolida: DA-001` · `supersede: —`
**Regra:** Regra vigente da cabeça, consolidando a saga-teste.
**Motivo:** motivo fundador de teste.
**Trade-off:** trade-off da cabeça de teste.
**Lição:** lição transferível de teste.
### Histórico
- DA-001 (2026-01-01) · absorvida pela cabeça · medido: — · sobreviveu: tudo · caiu: nada

## DA-006 — DA sem nenhuma tag, pertencimento vem só do membros.tsv
Texto qualquer de decisão em parágrafo solto, sem cabeçalho de tags e sem ### Decisão —
este é o fallback de primeiro parágrafo. O escopo e a saga desta DA vêm inteiramente de
DECISIONS-anexos/DA-182/membros.tsv (fixture), nunca de uma tag local.
