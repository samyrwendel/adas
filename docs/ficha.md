# Ficha da DA

Gerada de `skeleton/scripts/da-schema.tsv` por `bash skeleton/scripts/da-new.sh --ficha` — não edite à mão.
A ordem das linhas é a ordem da ficha. Teto `alvo/corte`: o check avisa só acima do corte.

| Campo | Onde | Obrigatório | Teto | No molde | Valores | Como escrever |
|---|---|---|---|---|---|---|
| `escopo:` | cab | sim | - | sim | - | produto · instância · projeto/<nome> (pode compor) |
| `saga:` | cab | sim | - | sim | - | slug do sagas.conf ou nova/<slug> |
| `data:` | cab | sim | - | sim | - | data do registro |
| `tipo:` | cab | sim | - | sim | regra|registro|princípio | regra manda ou proíbe · registro é fato (não vira cartão) · princípio |
| `gravidade:` | cab | sim | - | sim | piso|norma|preferência | quem promove a piso ou rebaixa a preferência é o dono |
| `refs:` | cab | sim | - | sim | - | ids citados |
| `consolida:` | cab | sim | - | sim | ids | ids que esta cabeça absorve, lista pura |
| `supersede:` | cab | sim | - | sim | ids() | ids que esta DA revoga; parcial = DA-NNN (só …), sempre apontando a cabeça vigente |
| `parcial:` | cab | opcional | - | não | ids() | mudança parcial de outra DA (marca ½); acrescente a etiqueta só quando houver |
| **Regra:** | corpo | sim | 120/240 | sim | - | uma frase no imperativo; alvo 120, o cartão corta em 240; o resto vai no Detalhe operacional |
| **Gatilho:** | corpo | regra | - | sim | - | evento · <superfície> · … | forma · reply · … | tema (normativa sem gatilho de máquina); registro apaga a linha |
| **Exemplo:** | corpo | regra | 140+140 | sim | - | par ✗ <o que saiu> → ✓ <como devia sair>, caso real |
| **Fonte do exemplo:** | corpo | opcional | - | não | - | onde o caso está (msg, log com data, DA); fica fora do cartão |
| **Motivo:** | corpo | sim | - | sim | - | abre pelo incidente e pela ordem do dono, com data; termine com Decidido por |
| **Trade-off:** | corpo | sim | - | sim | - | + o que ganha · − o que perde · o que foi rejeitado |
| **Lição:** | corpo | sim | 300 | sim | - | geral e portátil, sem caminho de arquivo nem nome próprio |
| **Mecanismo:** | corpo | proibe | - | sim | - | caminho REAL da trava/teste que reprova a violação (DA-527); Regra que não proíbe apaga a linha |
| **Padrão sem ADAS:** | corpo | opcional | - | não | - | a reação default do modelo que a regra troca |
| **Detalhe operacional:** | corpo | opcional | - | sim | - | valores, limiares, exceções, passos; não se aplica = apague a linha |
