# Novidades do ADAS

Cada versão diz o que muda para quem usa, não a lista de commits. A primeira linha `Resumo:` de cada
versão é a que aparece no aviso de versão nova da sessão.

## 1.0.1 — 2026-10-31

Resumo: o aviso de versão nova sai sempre na própria linha.

- Correção: quando o começo da sessão terminava sem quebra de linha, o aviso de versão grudava no texto anterior.

## 1.0.0 — 2026-10-31

Resumo: primeira versão numerada; a regra certa chega no instante da ação (ADAS-JIT), com aviso de versão nova e atualização segura.

- **Aviso de versão nova.** No começo da sessão, no máximo uma vez por dia, o ADAS confere se saiu versão nova e avisa numa linha, com o comando de atualizar. Sem rede, fica mudo. Para desligar: `ADAS_VERSION_CHECK=off`.
- **Atualização segura** (`bash host/update.sh`). Mostra o que muda e pede confirmação antes. Troca só o motor: o clone do ADAS e os hooks, com backup do `settings.json`. Nunca mexe no diário (`DECISIONS.md`, `CONDUCT.md`), na constituição (`.specs/`) nem nos repos governados.
- **ADAS-JIT: a regra chega no ato.** Antes de cada mensagem do dono, comando, edição ou delegação, aparecem até 3 cartões com a regra do diário que toca aquela ação. Abaixo do limiar fica em silêncio. Cada regra declara como acende na linha `**Gatilho:**`:
  - `evento`: predicado no comando ou no caminho;
  - `tema`: busca por palavra e por parecença;
  - `forma`: juiz ou guard que lê a mensagem antes de sair.
- **Três níveis de vigilância** (`ADAS_JIT_NIVEL`):
  - 1 = travas + gatilho + busca por palavra;
  - 2 = + busca por parecença (vetor);
  - 3 = + juiz de forma (modelo barato, teto diário, falha = passa).
  - O termostato que sobe e desce o nível sozinho ainda é manual.
- **Juiz da mensagem** (`host/jit/juiz-reply.py`). Faz as perguntas de forma do diário (texto pra copiar em bloco de código, "pronto" sem conferir, afirmar sem prova…) numa chamada só. A chave vem de `OPENROUTER_API_KEY` ou `EXPERIENTIALLABS_API_KEY`.
- **Rede de regras.** As regras ligadas entre si (citação, mesma saga, parecença) formam o `grafo.json`. Cada ligação tem a espécie no campo `classe`: explícita, pertencimento, semântica ou aprendida. A regra-mãe vem junto com o cartão do mecanismo dela.
- **Toda regra normativa tem gatilho e prova.** O `check-da-gatilho.py` cobra a linha `**Gatilho:**`. O `check-da-mecanismo.sh` cobra o `**Mecanismo:**` de toda regra que proíbe. Fixtures em `~/.adas/fixtures/` provam que o gatilho dispara.
- **Glossário** (`GLOSSARIO.md`). Um nome por conceito, em português simples. O carro (faixa, gate, drift) é o enforcement; o cérebro (sinapse, ativação, consolidação) é a memória.
- **`da-new.sh`** já cria a DA com as linhas `**Gatilho:**` e `**Exemplo:**`.
- Base que já existia e segue igual: faixas auto-disparadas, `ADAS.md` portátil, diário em camadas com sagas e cabeça, `check-adas`, `check-secrets`, runtime anti-decaimento (`host/install.sh`), plugins para OpenClaw e Hermes.
