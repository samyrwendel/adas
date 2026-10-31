# Glossário do ADAS

Um nome por conceito, em português simples. A ordem de cada linha é a regra: **o termo simples vem primeiro**.
A analogia do cérebro entra só como sinônimo, para explicar a dinâmica. Ela nunca vira nome de campo, flag ou arquivo.
Nenhum nome de código ou de arquivo mudou por causa deste glossário: ele amarra os nomes que já existem.

## Duas metáforas, duas camadas

O ADAS usa duas imagens, e cada termo pertence a UMA delas:

- **Carro: camada de ENFORCEMENT.** É o que mantém o agente na pista NO ATO.
  - Termos: faixa, gate, check, drift, pista.
  - "Faixa" nunca descreve ligação entre regras.
- **Cérebro: camada de MEMÓRIA.** É o que o agente lembra e como lembra.
  - Termos: diário, nota, sinapse, ativação, consolidação.
  - "Sinapse" nunca descreve bloqueio.

O ADAS-JIT é a ponte entre as duas: a memória acende (ativação) e o enforcement age (aviso, gate, deny).

## Termos canônicos

| Termo | O que é | Onde vive |
|---|---|---|
| **DA** (Decisão Arquitetural) | decisão registrada, `DA-NNN`, append-only: nunca some, é superada ou consolidada | `DECISIONS.md`; `scripts/da-new.sh`; `scripts/da-index.sh show DA-NNN` |
| **DC** (Decisão de Conduta) | regra de comportamento do agente, `DC-NNN` | `CONDUCT.md` (instância) |
| **saga** | a história de uma regra: as DAs que tratam do mesmo assunto ao longo do tempo. É o eixo do TEMPO | campo `saga:` da DA (única grafia); `~/.adas/sagas.conf` |
| **cabeça** (da saga) | a DA que diz o que vale HOJE naquela saga; consolida as anteriores | campo `consolida:` da DA; `cabeça:` no índice |
| **rodada** | uma atualização datada dentro da saga | DA nova na mesma saga |
| **escopo** | onde a regra vale: `produto`, `instância` ou `projeto/<nome>` | campo `escopo:` da DA; `rotas.conf` |
| **faixa** | regra de trabalho de um projeto, auto-disparada pela descrição (camada de enforcement) | `.claude/skills/*/SKILL.md` |
| **cartão** | a DA compilada em forma curta (regra, conserto, gatilho), pronta para ser mostrada | `cards.json` / `regras.db` (`host/jit/da-cards.py`) |
| **gatilho** | a condição que faz uma regra aparecer: `evento` (predicado no comando/caminho), `forma` (juiz ou guard), `tema` (busca) | linha `**Gatilho:**` da DA; `gatilhos.json` |
| **juiz** | modelo que lê a mensagem antes de sair e responde as perguntas de forma | `juiz-reply.json` + `juiz-reply.py` (instância) |
| **regra-mãe** | a regra que um cartão-mecanismo serve; aparece junto com ele | `regra_mae()` em `regra-search` |
| **adesão** | a regra foi mostrada e a ação seguinte cumpriu (`aplicou`) ou não (`ignorou`). É o "A" de ADAS | campo `adesao` do ledger `regra-jit.log` |
| **nota** | conceito estável do cérebro (pessoa, projeto, ferramenta, ideia), editada no lugar | `~/brain/<domínio>/<slug>.md` (instância) |
| **mapa de conteúdo** (MOC) | a página que agrupa as notas de um assunto. É o eixo do ESPAÇO | `_moc.md` |
| **destilação** | conversa vira nota, em lote periódico (o "sonho" da instância) | `brain-distill` (instância) |
| **grafo** (código) / **rede** (prosa) | o conjunto das ligações entre regras ou entre notas | `grafo.json` (regras); `brain-graph` (notas) |

## Analogias do cérebro (sinônimos documentados)

| Termo simples | Sinônimo do cérebro | O que significa aqui | Onde vive |
|---|---|---|---|
| ligação | **sinapse** | qualquer ligação entre duas unidades. Tem origem, destino, peso e uma de 4 espécies (abaixo) | `grafo.json` (`classe`); seções `## Sinapses` e `## Relacionadas` das notas |
| disparo (o evento) | **ativação** (o processo) | a regra acende numa ação | `decisao`/`cartoes` no `regra-jit.log` |
| espalhar | **ativação por espalhamento** | vizinhos acendem com força decrescente (β 0,7, 2 saltos). Só reordena e anexa, nunca cria disparo | `espalha()` em `regra-search` |
| limiar | **limiar de disparo** | abaixo dele, silêncio | `LIMIAR` em `regra-jit.py`; `limiar`/`limiar_aviso` do juiz |
| consolidar | **consolidação** | rodadas viram cabeça; o episódio (o Motivo da DA) vira regra limpa. É o PROCESSO; a DA que resulta dele é a cabeça | `consolida:` |
| trecho de conversa | **episódio** | o que aconteceu: a mensagem que motivou a regra | `kind='conversation'` no índice do cérebro |
| reforço e enfraquecimento | **plasticidade** / **poda** | o peso da sinapse aprendida sobe com `aplicou` e desce com `ignorou`; a aresta fraca sai na recompilação. Poda vale só para aresta aprendida, nunca para DA. **(pendente: B1)** | campo `w` do `grafo.json` (quando existir) |

### As 4 espécies de sinapse

O campo `classe` de cada aresta do `grafo.json` diz a espécie. O campo `tipo` continua dizendo a origem.

| `classe` | `tipo` de origem | Peso | Quem escreve |
|---|---|---|---|
| **explícita** | `refs`, `consolida`, `supersede`, `mecanismo-de` | 1,0 | autor da DA; no cérebro, `## Sinapses` |
| **pertencimento** | `saga` (mesmo grupo) | 0,3 | compilador |
| **semântica** | `semântica` (cosseno ≥ 0,80, top-5) | o cosseno | compilador; no cérebro, `## Relacionadas` (≥ 0,60) |
| **aprendida** | `adesao` | w ∈ [0,1] | ledger de adesão. **Pendente (B1): o nome está reservado e o campo nasce com o dado** |

## Aposentado da prosa

- **narrativa**: o conceito é "cabeça da saga". `NA-<saga>` fica só como identificador da vista gerada da saga, hoje desligada; o id continua reservado caso a vista volte.

## Rejeitados (não usar)

- **neurônio** (para nota ou DA): no cérebro a memória está no padrão, não na célula; chamar uma DA de neurônio confunde quem chega.
- **engrama**: substrato físico de uma memória; aqui ninguém precisa desse nome.
- **córtex / área** (para MOC): região anatômica, não agrupamento por assunto. Use "mapa de conteúdo".
- **potencial de ação**: físico e longo; "disparo" já diz.
- **conectoma**: jargão; "rede" diz o mesmo.
- **hebbiano**: só como nota explicativa da plasticidade ("o que dispara junto e foi útil se liga"), nunca como nome.
- **esquecimento**: falso aqui. O diário é append-only; use supersede, consolida ou poda, cada um no seu lugar.
