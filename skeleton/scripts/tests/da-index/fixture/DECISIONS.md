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
**Motivo:** motivo fundador de teste, resolve de vez a faixa DA-001–DA-002 e também cita DA-003 solta.
**Trade-off:** trade-off da cabeça de teste.
**Lição:** lição transferível de teste.
### Histórico
- DA-001 (2026-01-01) · absorvida pela cabeça · medido: — · sobreviveu: tudo · caiu: nada

## DA-006 — DA sem nenhuma tag, pertencimento vem só do membros.tsv
Texto qualquer de decisão em parágrafo solto, sem cabeçalho de tags e sem ### Decisão —
este é o fallback de primeiro parágrafo. O escopo e a saga desta DA vêm inteiramente de
DECISIONS-anexos/DA-182/membros.tsv (fixture), nunca de uma tag local.

## DA-007 — Parágrafo de metadado quebrado em duas linhas não pode vazar a continuação (Regra-Fallback)
`escopo: produto` · `saga: regra-fallback-swallow`

**Data:** 2026-02-01 · **Pedido do Samyr, via mainbot** (task 20260201-001) · **Implementado
por:** devbot. **Escopo:** `arquivo/qualquer.sh`, `outro/arquivo.py`.

### O buraco
Isto é o parágrafo de conteúdo real, que deve virar a Regra no índice. Nada disso é metadado.

## DA-008 — Rótulo curto tipo "**O problema.**" não é frase de conteúdo válida (Regra-Fallback)
`escopo: produto` · `saga: regra-fallback-curto`

**Data:** 2026-02-02 · **Autor:** devbot. **Escopo:** `arquivo/qualquer.sh`.

**O problema.** Isso é só a segunda frase deste parágrafo, que não deveria ser usada aqui.

## DA-009 — Decisão em lista de alternativas extrai a frase do primeiro item (Regra-Fallback)
`escopo: produto` · `saga: regra-fallback-lista`

**Decisão, com a alternativa descartada e o porquê:**
- **Manter o processo atual em produção** (escolhida). Complemento que continua
  na linha seguinte do mesmo item.
- **Trocar de tecnologia** (descartada). Não serve porque falha em produção.

## DA-010 — Parágrafo que é só citação entre aspas/itálico não pode virar a Regra (Regra-Fallback)
`escopo: produto` · `saga: regra-fallback-citacao`

*"Isso é uma citação solta que não deveria nunca virar a Regra no índice de decisões."*

Esta linha de conteúdo real, fora da citação, é que deve aparecer como Regra no índice gerado.

## DA-011 — Parágrafo iniciado por atribuição sem tag Data também é metadado (Regra-Fallback)
`escopo: produto` · `saga: regra-fallback-atribuicao`

**Decidido por:** Samyr, numa conversa qualquer, sem tag de Data nesta linha específica.

Este parágrafo é o conteúdo de verdade que deve virar a Regra mostrada no índice gerado.

## DA-012 — Frase de conteúdo longa demais não vira Regra, cai no fallback ver DA-NNN (Regra-Fallback)
`escopo: produto` · `saga: regra-fallback-longa`

Esta é uma frase de conteúdo propositalmente muito longa para ultrapassar de propósito o teto de
duzentos e quarenta caracteres estabelecido pela regra de extração determinística da Regra,
continuando ainda um bom pedaço mais adiante até finalmente passar do limite com folga suficiente
para o teste do harness não deixar dúvida nenhuma sobre a validação de tamanho máximo aceito.

## DA-013 — Data vem de linha em negrito isolada no corpo, sem tag e sem rótulo Data (Regra-Fallback)
`escopo: produto` · `saga: regra-fallback-datas`

**15/03/2026** · alguma referência qualquer, sem rótulo "Data:" explícito nesta linha.

Conteúdo qualquer desta DA, só para ter um corpo mínimo de teste no harness.

## DA-014 — DA genuinamente sem nenhuma data em lugar nenhum do corpo (Regra-Fallback)
`escopo: produto` · `saga: regra-fallback-datas`

Este corpo não menciona nenhuma data em formato reconhecível, em lugar nenhum do texto.
