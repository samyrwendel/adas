# Novidades do ADAS

Cada versão diz o que muda para quem usa, não a lista de commits. A primeira linha `Resumo:` de cada
versão é a que aparece no aviso de versão nova da sessão.

## 1.2.0 — 2026-11-12

Resumo: `adas test` roda todas as suítes do ADAS; um timer diário roda o mesmo e avisa quando fica vermelho.

- **`adas test`**: um comando para as suítes do esqueleto, o harness do `da-index`, o smoke e o smoke-v4, com o tempo de cada uma. Sai ≠0 se qualquer uma falhar. O pre-commit do repositório `adas` e o CI rodam o mesmo comando, então teste vermelho não entra mais por cima.
- **Relógio diário (`adas-selftest.timer`)**, instalado pelo `host/install.sh` onde houver `systemd --user`. Grava `~/.adas/selftest.status` (e `~/.adas/selftest.log` com a saída do que falhou) e avisa **só na troca** verde↔vermelho. O canal do aviso é `ADAS_ALERT_CMD` em `~/.claude/adas/selftest.env`; sem ele o aviso vai pro journal. Sem LLM.
- **SessionStart**: enquanto o relógio estiver vermelho, ou sem rodar há mais de 3 dias, a sessão abre com uma linha dizendo isso.
- **Projeto ADAS fora de git é procurado**, não só barrado quando alguém roda o check: o `adas test` varre toda pasta com `.adas/` sob a home e `/opt/projects` (menos a home) e reprova a que não é repositório git (DA-530).

## 1.1.5 — 2026-11-11

Resumo: o juiz exige redator de segredos configurado (ADAS_REDATOR) e avisa quando falta; check de mecanismo cobra só DA em vigor.

- **Redator do juiz por configuração.** Saiu o caminho padrão de instância. Defina `ADAS_REDATOR` (env ou `~/.adas/juiz.env`). Sem ele nenhum texto vai pro juiz, e agora `adas juiz status` e o SessionStart dizem "Juiz DESLIGADO: sem redator" em vez de listar provedores como se estivesse ligado.
- **Check de mecanismo cobra a regra em vigor.** DA superada ou consolidada sai da fila; a vigência só vale pro `DECISIONS.md` da raiz, outro diário é auditado inteiro.
- **BLOCK novo:** projeto ADAS (com `.adas/profile.json`) fora de repo git reprova no `check-adas.sh`.

## 1.1.4 — 2026-11-01

Resumo: quando o dono diz "a partir de agora…", o agente registra a decisão no diário e não só na memória dele.

- **Frase de decisão acende a regra na hora.** "A partir de agora", "não pode mais", "nunca mais", "fica assim", "regra nova", "from now on"… trazem a regra de registrar no diário, mesmo quando a mensagem não tem nenhuma palavra da regra. Antes, no Hermes, nada aparecia e o agente guardava a ordem só na memória própria.
- **No Hermes o aviso já diz onde escrever:** o caminho do `DECISIONS.md` e o número da próxima DH.
- **Resposta "anotado, regra permanente na memória" sem o diário escrito leva aviso.** No Hermes, no turno seguinte; no Claude Code, antes do reply sair no Telegram. Não precisa de juiz nem de chave: é uma comparação de texto.
- **Campo novo nas decisões: `**Padrão sem ADAS:**`.** Diz o que o modelo faria sem o ADAS e que a regra troca. Esse texto também serve pra achar a regra. Com `resposta=/…/`, a resposta que saiu é conferida contra ele.
- Pra chegar no Hermes, o sync que gera o `padrao.md` agora leva junto essas duas linhas (Gatilho de evento e Padrão sem ADAS).

## 1.1.3 — 2026-10-31

Resumo: atualizar um clone usado por outro agente (Hermes) não mexe mais no Claude Code da máquina.

- `host/update.sh` só reinstala os hooks do Claude Code quando o clone é o que ele usa (`~/.claude/adas/source`). Num clone do Hermes ou de outro agente, atualiza só o motor e avisa.
- No Hermes, a configuração do juiz fica em `$HERMES_HOME/governanca/juiz.env`, no volume do app, e sobrevive à troca do container.
- **Atenção, quem sai de 1.1.0–1.1.2 num clone do Hermes:** o `update.sh` que roda é o antigo, que ainda reinstala os hooks do Claude Code. Nesse caso use `git -C <clone> pull --ff-only` uma vez. Daí em diante o `update.sh` já é o novo.

## 1.1.2 — 2026-10-31

Resumo: o juiz reusa o provedor que o agente já tem configurado (Hermes, OpenClaw, Codex, Claude Code), sem copiar a chave.

- `adas juiz configurar --auto` agora lê a configuração de provedores do próprio agente:
  - Hermes: `config.yaml` (modelo e `custom_providers`) + `.env`;
  - OpenClaw: `openclaw.json` (`models.providers`);
  - Codex: `config.toml` (provedor com chave; login OAuth fica de fora);
  - Claude Code: bloco `env` do `settings.json`.
- Quando o provedor é OpenRouter, ExperientialLabs, TypeSafe ou Vercel Gateway, o juiz usa o Jev por ele. Senão, usa o modelo barato do próprio agente.
- Grava só o ponteiro pro arquivo do agente. A chave é lida na hora e nunca é copiada.
- Provado num Hermes real (5 de 6 provedores da config responderam) e numa config real de OpenClaw (2 de 2).

## 1.1.1 — 2026-10-31

Resumo: o juiz sem chave avisa e se liga sem passar pelo chat; o nível de vigilância se ajusta sozinho; a regra certa chega em 90% das violações medidas (antes 58%).

- **Juiz sem chave avisa.** No nível 3 sem chave, o começo da sessão mostra "Juiz DESLIGADO: sem chave — nível 2" e o comando de ligar. O produto não aponta mais pra caminho de instância nenhuma.
- **Ligar o juiz sem colar a chave no chat** (comando novo `adas`):
  - `adas juiz configurar --auto` acha a chave que o agente já tem (ambiente, `.env` do Hermes, cofre, Ollama local), testa e grava a primeira que responde;
  - `adas juiz configurar` pede a chave escondida no terminal e grava `~/.adas/juiz.env` (permissão 600);
  - `adas juiz link` abre um formulário de uso único que vale 5 minutos.
- **Chave colada na conversa não é usada.** O agente manda revogar e indica um dos caminhos acima. O juiz ganhou uma pergunta pra isso, e o Hermes avisa o modelo quando a mensagem traz uma chave.
- **Mais provedores pro juiz:** Jev direto na TypeSafe, OpenRouter, ExperientialLabs, Vercel Gateway, ou qualquer endpoint compatível com OpenAI (inclusive Ollama local). As perguntas e o limiar são os mesmos; a ordem é configurável; se todos falham, a mensagem sai.
- **Termostato do nível** (`adas nivel`). Sobe por tamanho do diário, por 2º agente no repo, por código que mexe com dinheiro, cliente ou mensagem a pessoas, e por achado do juiz. Desce depois de 30 dias sem achado. A fixação manual vence. Toda mudança sai na revisão semanal.
- **A regra certa chega mais vezes.** Medido no banco de 68 casos reais:
  - regra entregue nas violações: **74 → 114 de 127**;
  - no pedido do dono: 13 → 25 de 68;
  - cartões fora do alvo quase iguais (9 → 11 no pedido, 16 → 18 nas ações).

  O que mudou:
  - o gatilho de evento descreve a classe da ação, não o comando de um exemplo, e pode valer em várias superfícies (`bash,edit,prompt`);
  - a busca dispara quando a busca por palavra e a por parecença apontam a mesma regra em 1º lugar;
  - a trava de copiar e colar pega também texto anunciado pra colar (prompt, reclamação, comando curto).

## 1.1.0 — 2026-10-31

Resumo: ADAS-JIT chega ao Hermes; a cada mensagem entram só as regras que tocam o assunto, e um juiz avisa quando a resposta quebra regra de forma.

- **ADAS-JIT no Hermes** (`host/jit/hermes-jit.py`, shell hooks `pre_llm_call` e `post_llm_call`):
  - as regras próprias do host entram inteiras;
  - do padrão entram só as que tocam a mensagem (busca por palavra com limiar). Conversa comum não puxa regra.
- **Juiz no Hermes** (nível 3). Lê a resposta depois que ela sai, porque o Hermes não tem gancho de shell antes da entrega. A violação fica no ledger e vira aviso no próximo turno. Chave: a do OpenRouter que o próprio Hermes já usa.

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
