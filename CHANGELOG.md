# Novidades do ADAS

Cada versão diz o que muda para quem usa, não a lista de commits. A primeira linha `Resumo:` de cada
versão é a que aparece no aviso de versão nova da sessão.

## 1.4.1 — 2026-11-12

Resumo: trava própria da casa ganha lugar fixo (`scripts/check-local.sh`) e o 1º `adas sync` reconhece cópia só atrasada — sem `--force` em massa.

- **`scripts/check-local.sh`** é da casa: fica fora do lock, o `adas sync` (nem com `--force`) nunca o toca, e o `check-adas.sh` das duas gerações o executa (rc≠0 = bloqueia, também no pre-commit e no CI). No modo mecanismo do v4, mecanismo chamado por ele conta como registrado. Trava de domínio (cor só no `tokens.css`, hosts da mesa) mora aqui, não numa cópia editada de script sincronizado.
- **1º sync sem lock**: cópia igual a alguma versão antiga do produto (blob alcançável do HEAD do repo adas) é "atrasada", não "editada" — sincroniza sem `--force`. Só o que nunca existiu no produto é recusado.
- **Sync atômico de verdade**: copia tudo para um estágio em `.adas/` antes de mexer na casa; falha no meio não deixa casa reprovando nem `lock.tmp` sobrando. O sync recusa o próprio produto; `--check` de casa que não existe reprova.
- **Diário sem `data:`**: o 1º sync grava `ultima: DA-NNN` no `.adas/ficha-desde`; DA anterior à âncora não ganha aviso de ficha (antes: 473 avisos no claude-tg-tmux).
- **`check-secrets.sh`** recebe dois consertos que viviam só nas casas: valor de `NOME_DA_CHAVE=` só reprova se parecer chave (prosa citada num diário não trava mais o gate, dramaker) e a allowlist é achada pelo repo varrido, não pelo diretório de quem chamou, com aviso quando nenhuma foi lida (claude-tg-tmux). O filtro de "valor fictício" do claude-tg-tmux não subiu: no produto, fixture com forma de chave sai só pela allowlist.
- `contrato.test.sh` sem `| grep -q` sob pipefail (falhava ~1 em 6 rodadas).

## 1.4.0 — 2026-11-12

Resumo: `adas sync` leva os scripts do produto às casas com carimbo sha256; cópia editada à mão reprova o check-adas.

- **`adas sync <casa>|--all`**: copia `skeleton/scripts/` (ou `skeleton-v4`) para `<casa>/scripts/` e grava `.adas/skeleton.lock` com geração, versão, commit e sha256 de cada arquivo. Cópia editada na casa não é sobrescrita sem `--force` (traga a mudança pro produto primeiro); a recusa é atômica por casa. A geração fica no lock e não troca sem `--force`. Scripts próprios da casa não entram no lock.
- **`check-adas.sh` confere o lock** (passo 8b; 7b no v4): arquivo fora do hash = FAIL, rc 1 ("edite no produto e rode adas sync"). Lock atrás do ADAS instalado = aviso. Casa sem lock: nada muda até o primeiro sync.
- **Corte do contrato por casa**: o primeiro sync grava `.adas/ficha-desde`; DA anterior ao sync não ganha aviso de ficha.
- **`adas test`** roda `tests/sync.test.sh` e confere o lock de cada casa do `repos.conf` (casa sem lock só é listada).
- **`update.sh`** avisa casa com `da-new.sh` sem `da-schema.tsv` e confere o lock das casas sincronizadas; copiar é o `adas sync`, nunca o update.
- Ressalvas da revisão da Fase 2: DA sem `data:` ISO não escapa mais do contrato (data fora de AAAA-MM-DD avisa); `--tipo 'regra|registro'` é recusado; `docs/ficha.md` sem tabela quebrada; o mapa de arestas do teste JIT conhece `parcial`. Cada uma com teste no `contrato.test.sh`.

## 1.3.0 — 2026-11-12

Resumo: a ficha da DA virou um arquivo só (`da-schema.tsv`); o molde, a instrução e o aviso de ficha fora do padrão saem dele.

- **Contrato único da DA** (`scripts/da-schema.tsv`): campos, ordem da ficha v2, obrigatoriedade, tetos e valores, uma linha por campo. A ordem das linhas é a ordem da ficha. A tabela legível está em `docs/ficha.md`, gerada por `da-new.sh --ficha`.
- **`da-new.sh` exige `--tipo`** (`regra` · `registro` · `princípio`): `da-new.sh --tipo regra <escopo> <saga> "<título>" [dir]`. O esqueleto e a instrução saem do esquema; o script não escreve nome de campo. O molde ganhou `tipo`, `gravidade`, a ordem v2 (Regra · Gatilho · Exemplo · Motivo · Trade-off · Lição · Mecanismo · Detalhe operacional) e o Gatilho nasce vazio. `--ajuda` imprime a instrução.
- **`da-index.sh check` confere a DA nova contra o esquema** (só aviso): campo obrigatório ausente ou vazio, linha deixada vazia, Regra acima de 240 (alvo 120), Lição acima de 300, lado do Exemplo acima de 140, `tipo`/`gravidade` fora dos valores, `consolida`/`supersede` que não são lista de ids, e `parcial`/`supersede` apontando DA que já não é vigente ("aponte para a cabeça"). Vale para DA com `data:` a partir de 2026-11-13 (`DA_FICHA_DESDE`); DA existente não ganha aviso. O corte é por data e não por número porque cada diário tem a sua numeração.
- **`parcial: DA-NNN`** no cabeçalho marca ½ (mesmo efeito de `supersede: DA-NNN (só …)`, que segue valendo); a DA alvo continua vigente. O cartão e o grafo do JIT leem a etiqueta (aresta `parcial`, classe explícita).
- **`da-index.sh dump [dir]`**: TSV com id, marca de vigência e cada campo do esquema (`∅` = linha ausente). É o acesso único aos campos para os outros leitores.
- **Teste de contrato** (`skeleton/scripts/tests/contrato.test.sh`, dentro do `adas test`): o molde segue o esquema, cada campo que um leitor consome existe no esquema e o leitor reage quando o campo muda. Apagar do esquema um campo lido derruba o teste; trocar a ordem de duas linhas muda o molde e o teste segue verde.
- **`adas test` espera a trava por no máximo 480 s**: trava presa vira rodada vermelha (com `--selftest`, grava o status e alerta) em vez de esperar para sempre (O1 da revisão 016). Lock que não abre diz que segue sem trava (O2). O smoke grava o log do openclaw e do hermes num arquivo por rodada (O4).

## 1.2.2 — 2026-11-12

Resumo: o relógio não dá mais vermelho falso por horário nem por duas rodadas ao mesmo tempo.

- **Commit no último minuto do dia conta como agente** no termostato do JIT (`--until` fechava em 23:59:00; agora 23:59:59). Teste de regressão com commit às 23:59:30 (R1 da revisão 013).
- **`adas test` roda uma vez por árvore** (`flock`): a segunda rodada espera a primeira. Rodadas simultâneas na mesma árvore davam vermelho falso (2 de 9 em 12/11; 0 de 6 com a trava).
- Testes com `pipefail` não reprovam mais por SIGPIPE quando o `grep -q` fecha antes do produtor (`tem` drena a saída); o harness do da-index não usa mais arquivo fixo em `/tmp`.

## 1.2.1 — 2026-11-12

Resumo: o juiz liga em qualquer máquina com o redator mínimo do ADAS; trocar a chave não apaga mais o redator configurado.

- **Redator mínimo no produto** (`host/jit/redator_min.py`): sem `ADAS_REDATOR`, o texto que vai pro juiz passa por ele (chaves `sk-`, GitHub, Google, AWS, Slack, bot do Telegram, Bearer, PEM, `api_key=…` e o valor de variável de ambiente com nome de segredo). Antes, fora de uma instância com redator próprio, o juiz nunca ligava. Quem tem cofre continua apontando `ADAS_REDATOR` pro dele.
- **`adas juiz configurar`, `--auto` e `link` preservam a linha `ADAS_REDATOR`** do `juiz.env`. Antes a reescrita apagava a linha e o juiz desligava respondendo "LIGADO".
- `ADAS_REDATOR=~/…` funciona no status igual ao uso (antes o status dizia DESLIGADO com o juiz funcionando).
- Redator configurado que não existe: `configurar` diz "sem redator" e não culpa a chave (que nem foi testada).

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
