# ADAS — Anti-Drift Adherence System

> Faixas de governança que mantêm **qualquer LLM dentro da spec do projeto** — em vez de inventar
> cor, estrutura, escopo, nomenclatura ou texto novos. Como o ADAS de carro te mantém na **faixa**.
> Princípio-mestre: **ADESÃO > INVENÇÃO** — consolidar > reescrever · padronizar > inventar ·
> medir antes de substituir · nunca regredir o que funciona.

Nasceu no projeto **Holdge** (suíte DeFi self-custodial) e foi extraído como método reutilizável.

## Por que existe
LLMs reinventam: recriam um componente que já existe, mudam uma cor canônica, fogem do escopo,
repetem um bug já decidido. O ADAS troca "confiar que a LLM lembra" por uma **hierarquia de
derivação + enforcement no momento da ação**.

## Para quem é — e para quem NÃO é (ainda)

**Serve:** um repo git, um produto, um dono presente numa sessão interativa (Claude Code, Cursor,
Codex). Foi assim que nasceu (Holdge, jun/2026) e é assim que o autor usa nos projetos dele. Você lê
o `ADAS.md` junto com a LLM no começo da sessão, ela fica na faixa enquanto você olha, e o
`DECISIONS.md` guarda o que **você** decidiu.

**Não serve, como está:** frota de agentes headless, hub multi-repo sem git na raiz, servidor/home,
ou qualquer lugar onde não há humano no instante do ato. Nesses ambientes a regra escrita não é lida
(medido: 5% das sessões invocaram uma decisão como veto; 0 de 28 sínteses foram aprovadas pelo dono)
e o check de drift é cego sem git. O que funcionou nesses casos foi outra coisa: **gate que falha e
frase no prompt no instante da ação**.

**Os números deste README** foram medidos em UMA instalação, no servidor do autor, em setembro de
2026, sem usuário externo. Trate como relato, não como propriedade do método.

## Arquitetura (4 camadas + 1 loop)
```
.specs/  (CONSTITUIÇÃO: invariantes mais estáveis + valores crus; compartilhada entre repos)
   │  extraída/adaptada →
.claude/skills/*/SKILL.md  (FAIXAS: escopo do projeto, AUTO-DISPARADAS via frontmatter)
   │  destiladas →
ADAS.md  (PORTÁTIL: cola em qualquer LLM, sem hook/sem repo)
   │  injetada JIT →
.claude/settings.json hook  (REFORÇO no instante da edição — só Claude Code)
   +
DECISIONS.md  (DIÁRIO EM CAMADAS — o loop de volta):
   ├─ DA-NNN         append-only, nunca some — o que foi DECIDIDO e por quê
   ├─ NA-<saga>      DA-CABEÇA por saga — o que VALE HOJE (consolida a linhagem)
   └─ views geradas  índice · sagas · lições · vigentes-por-escopo (regeneradas)
```
Cada camada **cita e é gerada da de cima**. Por isso "auto-aprimorar" é mecânico: decisão entra como
`DA-NNN`, dobra na faixa que afeta, regenera o portátil — **no mesmo commit**. São **três papéis
distintos**, não um: **constituição/faixa = COMO se trabalha**; **`DA-NNN` = O QUE foi decidido e por quê**
(histórico imutável); **`NA-<saga>` = O QUE vale hoje** — a cabeça da saga, que se lê sem varrer o histórico.

**Aposentar decisão são DOIS mecanismos, não um.** *Supersede* é substituição **pontual e declarada** de
uma decisão específica — raro por natureza (medido nesta instalação: 11 de 235 decisões aposentadas por supersede — 4 íntegras, 7 parciais). O que resolve **acúmulo** é a
**consolidação na cabeça da saga**: a `NA-<saga>` reescreve o que vale e absorve a linhagem **sem apagar
nenhuma** decisão — medido, **28 cabeças cobrindo ~150 decisões**, e a **leitura obrigatória caiu de ~200
para ~78**. Nada some; muda só o que você **precisa** ler pra saber a regra atual.

O mesmo vale pro **aprendizado de fix**: fix aprovado que representa uma **classe** de erro (mesmo padrão
possível em superfície irmã — ex.: errou igual no spot E no colateral) dobra na **faixa sensível** que
dispara no momento certo (description/hook/check), **não em doc morto** — doc morto não dispara.

### Faixas executáveis + gate (opcional — padrão nascido no GroupPay)
O hook injeta a regra no **momento da edição**. Pra fechar a outra ponta, um NÃO-FAÇA crítico vira um
**check rodável** (`scripts/check-<nome>.sh`, ver `skeleton/scripts/check-_template.sh`) + um **gate de
deploy/CI**: **money-path/segurança bloqueiam** (`SEVERITY=block`), **limpeza só avisa** (`SEVERITY=warn`).
Assim a faixa pega no **commit/deploy**, não só na edição. É o PASSO 7 do prompt.

### Auto-auditoria — o ADAS governa o ADAS (PASSO 8)
`scripts/check-adas.sh` (genérico, pronto) audita o **próprio ADAS** e pega o modo de falha nº1:
a derivação `.specs → faixas → ADAS.md` **rotar em silêncio**. Detecta **DRIFT** (faixa/`.specs`
commitada depois do `ADAS.md` → regenere), `<PLACEHOLDER>` não preenchido, **faixa sem frontmatter**
(não dispara) e **sem procedência** (invariante = chute), e `DA-NNN` órfã. Roda no CI/pre-commit.

### O verificador tem que ser honesto sobre o próprio limite
Governança **vive de check** — mas um check que transforma a **própria limitação** em acusação treina todo
mundo a **ignorar o alarme**, e alarme ignorado é pior que alarme nenhum. Quatro modos de falha, a **mesma
raiz**: **ausência de DADO reportada como ausência de FATO**.
- **timeout curto lendo silêncio como mentira** — sem resposta a tempo é **INCONCLUSIVO**, não reprovação;
- **procurar no escopo errado** e ler a ausência ali como inatividade real;
- **comparar com o separador errado** — um checador que reprovaria 100% do formato canônico e **nunca
  disparou porque nunca foi exercitado** (check sem teste é fé, não gate);
- **resolver o caminho pelo diretório atual** e responder "não encontrado" quando na verdade **não conseguiu LER**.

A regra, e vale pra qualquer check: **distinga "confirmei que está errado" de "não consegui verificar"**, e
**diga ONDE procurou quando reprova** — veredito sem escopo não é verificável, e um NÃO que era só um silêncio
apodrece a confiança no alarme inteiro.

### Âncora de onboarding (PASSO 9)
`AGENTS.md` é o arquivo que **qualquer LLM/ferramenta lê no primeiro contato** e aponta pro `ADAS.md`
("leia o ADAS antes de produzir qualquer coisa"). Espelhe/symlink pro nome que cada ferramenta lê no
boot — `CLAUDE.md` (Claude Code), `.cursorrules` (Cursor) — todos apontando pro mesmo `ADAS.md`. Sem
âncora, a governança existe mas a ferramenta não a descobre sozinha. (O `check-adas` valida que ela existe.)

### Leituras obrigatórias + few-shots + trava (cura da reinvenção — do spec-skills)
Cada faixa traz `references/mandatory-readings.md` (os arquivos REAIS a ler ANTES de editar) +
`references/few-shots/` (exemplos canônicos preenchidos) + uma **Trava obrigatória** (pare na
ambiguidade; leia o código real antes de agir). Reuso-por-construção: você só reinventa o que não leu.
Padrão importado do [spec-skills](https://github.com/samyrwendel/spec-skills).

### Segredos & Acesso — faixa pré-preenchida (universal) + gate
O esqueleto traz a faixa [`seguranca-acesso`](skeleton/.claude/skills/seguranca-acesso/SKILL.md) **já preenchida**
(as regras são iguais em todo projeto) + o gate `scripts/check-secrets.sh`:
- **nunca commitar segredo** — `.env`/token/chave fora do repo; só `.env.example` SEM valores;
- **token least-privilege** — fine-grained por repo, não admin-PAT amplo (`admin:org`/`delete_repo`);
- **não caçar credencial** fora do local apontado; nunca imprimir valor (só mascarado);
- **op de repo irreversível** (apagar/force-push/visibilidade/merge/criar) só com confirmação explícita.

`check-secrets.sh` **bloqueia** (BLOCK) token/chave/`.env` no staged/deploy — o hook avisa na edição, o gate trava no commit.

### Escada de decisão + débito localizado + relatório honesto (PASSO 10 — do ponytail)
Três ideias absorvidas do [ponytail](https://github.com/DietrichGebert/ponytail) (MIT; "o melhor código é o que
você não escreve") — encaixadas no frame existente, **sem braço novo** (o próprio "adesão > invenção" do ADAS):
- **Escada de decisão** (`ADAS.md`/`AGENTS.md`): antes de escrever código novo — precisa existir? → já existe? →
  stdlib? → nativo? → dep instalada? → uma linha? → só então o mínimo. **Pare no 1º degrau.** Operacionaliza o
  anti-invenção. Os **não-negociáveis** (validação/erro/segurança/**money-path testado**) ficam SEMPRE — "fazer
  menos" não erode a rede (lição do braço `caveman` do ponytail, que regrediu correção e precisou de gate).
- **Marcador `adas:` + coletor** (`skeleton/.claude/skills/adas-check/scripts/adas-debt.js`): atalho consciente vira
  migalha **na linha exata** (`// adas: <teto>. <upgrade>.`); o coletor junta tudo em `arquivo:linha`. Débito
  **localizado e REAL** (o que você deferiu) — complementa o `DECISIONS.md` (pesado) e o ratchet por contagem.
  `--max N` ratcheia. *(Pega o padrão "consertei num card, reabriu noutro": a migalha marca a tela irmã não-varrida.)*
- **Relatório com guarda de honestidade** (`skeleton/scripts/adas-report.sh`): conta faixas/DAs/débito/saúde e
  **se RECUSA a inventar "% de aderência"** — não há baseline do que a LLM teria inventado, então % seria chute.
  Espelha o `/ponytail-gain` (que nunca imprime número por-repo) e a regra "medir antes de substituir".

### Runtime anti-decaimento (PASSO 11 — do ponytail, multi-harness)
O JIT (PASSO 6) injeta a regra no instante da edição — mas a aderência ainda decai por **4 buracos**:
sessão que nasce **fora do repo** (num hub multi-repo o `.claude/settings.json` do repo **nem carrega**
— o ADAS fica inerte sem ninguém perceber), **compactação/resume** (o "leia o ADAS.md" do turno 1
evapora), **subagents órfãos** (nascem sem o contexto do pai — e é onde a invenção nasce) e **injeção
dupla** (user+project settings se mesclam). No **Claude Code**, a camada [`host/`](host/) fecha os
quatro: `SessionStart (startup|resume|clear|compact)` reinjeta o **núcleo** do `ADAS.md` (seção
`<!-- adas-core-start/end -->`) nas fronteiras de contexto; `SubagentStart` injeta em todo subagent
(envelope obrigatório); `adas-route.sh` (PreToolUse user-level) roteia pelo path e delega ao
`adas-inject.sh` **do repo** (texto versionado com o código), com guard anti-dupla. Estado por repo,
tudo fail-open — e o que **não** absorver do ponytail está documentado em [`host/README.md`](host/README.md).
Instalação: `bash host/install.sh /caminho/repo1 …` (idempotente; faz scripts → `repos.conf` → merge do
`settings-snippet.json` preservando o que existe).

**OpenClaw e Hermes também têm runtime** ([`host/openclaw-plugin/`](host/openclaw-plugin/),
[`host/hermes-plugin/`](host/hermes-plugin/)) — cada um chama os MESMOS scripts do `host/`
(`adas-resolve.sh`/`adas-core.sh`/`adas-secret-guard.sh`) via subprocess, nunca reimplementa a
regra. A forma muda por harness (ver a tabela abaixo) — nos dois, um plugin nativo consegue
**bloquear** um comando proibido pela faixa, não só injetar contexto (mais forte que o Claude Code
hoje). Detalhe completo, o que cada harness cobre e o que NÃO cobre, e como testar: ver
[`Instalação por harness`](#instalação-por-harness) mais abaixo.

## Instalação por harness

| | **Claude Code** (referência) | **OpenClaw** | **Hermes** |
|---|---|---|---|
| **O que copiar** (documento) | `skeleton/` inteiro (`.specs/`, faixas, `ADAS.md`, `DECISIONS.md`) — igual pra qualquer harness/LLM, nada específico aqui | mesmo `skeleton/` — o documento não muda | mesmo `skeleton/` — o documento não muda |
| **O que instalar** (mecanismo) | `.claude/settings.json` do repo (JIT por faixa) + opcional `host/install.sh` (runtime anti-decaimento) | [`host/openclaw-plugin/`](host/openclaw-plugin/) (`npm install && npm run build && openclaw plugins install . --link`) | [`host/hermes-plugin/`](host/hermes-plugin/) (copiar pra `plugins/adas-hermes/` ou `hermes plugins install`) |
| **Onde liga** | `.claude/settings.json` do repo (JIT) + `~/.claude/settings.json` (runtime, via `host/settings-snippet.json`) | config do plugin (`adasHome`) + `~/.claude/adas/repos.conf` (compartilhado) | `ADAS_HOME` (env) ou `~/adas` + mesmo `~/.claude/adas/repos.conf` |
| **Núcleo do ADAS.md por turno/sessão** | `SessionStart` (reinjeta nas fronteiras: startup/resume/clear/compact) | `before_prompt_build` (roda TODO turno — sem "buraco" de compactação, por desenho) | `register_system_prompt_section` (congelado em CADA sessão nova) |
| **Subagente** | `SubagentStart` (envelope `additionalContext` obrigatório) | mesmo `before_prompt_build` (cobre turnos de subagente) — **não provado contra subagente real** | `subagent_start` (existe, confirmado) — **não provado se é redundante com a seção de prompt** |
| **Faixa por-arquivo no instante da edição** (JIT, PASSO 6) | `PreToolUse` (`Edit\|Write\|MultiEdit`) → `adas-inject.sh` do repo, injeta a faixa que casa o glob | **não coberto** por este plugin ainda | **não coberto** por este plugin ainda |
| **Bloqueio de comando proibido** | **não existe** — o ADAS no Claude Code hoje só injeta contexto no PreToolUse, nunca recusa a ferramenta | `before_tool_call` com `block: true` (mais forte que o Claude Code) | `pre_tool_call` com `{"action":"block", ...}` (mesmo contrato do plugin real `security-guidance` deste repo Hermes) |
| **Testar que os ganchos disparam** | `host/README.md#teste-rápido` (comandos prontos, sem abrir sessão) | `cd host/openclaw-plugin && npm test` (real, sem Gateway) — ver `host/openclaw-plugin/README.md` pro que falta pra loader-backed | `cd host/hermes-plugin && python3 -m pytest -v` (real, sem Hermes rodando) — ver `host/hermes-plugin/README.md` pro que falta em produção |
| **Custo/política** | assinatura Claude (`claude` CLI) | roda o binário `claude-cli` — caminho permitido pela conta usada nesta instância | **API key** — o OAuth de assinatura foi cortado pra harnesses de terceiro, e o Hermes é nomeado explicitamente nessa restrição; sem key própria, não roda |

Cada seção do README de cada plugin (`host/openclaw-plugin/README.md`, `host/hermes-plugin/README.md`)
lista, sem inventar equivalência, exatamente o que foi PROVADO e o que ficou marcado como não-provado
por falta de acesso a uma instância real desses dois harnesses (ver DA correspondente em
`DECISIONS.md`).

### Faixa = Anthropic Skill (formato oficial, não reinventado)
Uma faixa do ADAS **é** uma [Anthropic Skill](https://github.com/anthropics/skills) (mesmo `SKILL.md` + frontmatter).
Então o **formato** segue o padrão oficial — [`spec/`](https://github.com/anthropics/skills/tree/main/spec),
[`template/`](https://github.com/anthropics/skills/tree/main/template) e o `skill-creator` — e o ADAS **só soma a
semântica de governança** (procedência, trava, DA-NNN). Divisão: **`skill-creator`/`anthropics/skills` = como AUTORAR
uma skill** (formato, packaging, eval, otimizar trigger) · **ADAS = como GOVERNAR com skills** (faixas + constituição +
decisões + drift + gates).
- **`description` é o roteador e deve ser "PUSHY"** — a guidance oficial pede combater o *undertriggering* ("use SEMPRE
  que … mesmo sem pedir explícito"); é a fonte de autoridade da regra "gatilho gordo + sintomas". Todo o triggering vai
  no `description` (o `when_to_use` é extra/não-canônico).
- **Otimize o trigger de cada faixa com o `skill-creator`** (tem um *description-improver* dedicado — é literalmente o roteador do ADAS).

## Os 3 modos & relação com o spec-skills
O ADAS opera em 3 modos (frame nascido no [spec-skills](https://github.com/samyrwendel/spec-skills)):
- **install** — projeto novo **nasce na pista** via scaffolding generativo. É **específico de stack** → fica num consumidor (ex.: `spec-skills` p/ Turbo+Next+Nest+Prisma); o `adas` não traz scaffolding de stack.
- **compare** — detecta **saída de faixa** (drift). **Engine pronto neste repo** (`skeleton/.claude/skills/adas-check/`): `adas-check.js` (runner), `check-design.js`, `check-i18n.js`. Determinístico; LLM pro nuance.
- **align** — **traz pra pista** (`align-design.js`: auto-fix de cor, dry-run, **retém o ambíguo** Δ>max p/ decisão humana).

Dois sabores de checagem, **não confundir** (nomes quase iguais, direções opostas):
- **`check-adas.sh`** (bash, universal) — audita a **governança** (o trilho apodreceu? drift/placeholder/procedência/DA órfã).
- **`adas-check.js` / `check-design.js` / `align-design.js`** (Node) — auditam/alinham o **código** contra as faixas (design/i18n…). Engine importado do [`spec-skills`](https://github.com/samyrwendel/spec-skills).

Contrato compartilhado: `.specs/` (humano/LLM) ↔ `.adas/profile.json` (máquina, p/ os checadores) — **gerados da mesma fonte de tokens** (`check-design.js --detect-tokens` bootstrapa o profile das CSS vars). Divisão: **`adas` = método + governança + engine compare/align (universal)**; **`spec-skills` = skill-pack TS-fullstack que adiciona o `install` (scaffolding) e consome a governança do `adas`**.

## Conteúdo do repo
| Arquivo | Pra quê |
|---|---|
| [`adas-bootstrap-prompt.md`](adas-bootstrap-prompt.md) | O **prompt** que cria um ADAS num projeto novo ou em andamento (engenharia reversa do código real). |
| [`skeleton/`](skeleton/) | **Esqueleto vazio** copiável (`.specs/` + `skills/_template/` + `DECISIONS.md` + `ADAS.md` + hook fonte-única). |
| [`host/`](host/) | **Runtime anti-decaimento** (PASSO 11, opcional): hooks user-level de reinjeção (SessionStart/SubagentStart) + roteador multi-repo. |

## Como chamar o ADAS em qualquer projeto

**1) Via prompt (qualquer LLM) — recomendado** — aponte a LLM pro seu projeto e cole o conteúdo de
[`adas-bootstrap-prompt.md`](adas-bootstrap-prompt.md). O próprio prompt manda **copiar o esqueleto**
(`git clone … && cp`) pra dentro do projeto, audita o repo e **preenche** as camadas (`.specs/` →
faixas → `ADAS.md` → hook).

**2) Via esqueleto (mãos na massa)** — copie a estrutura e preencha os `<PLACEHOLDER>`:
```bash
# dentro do projeto destino — cp -Rn NUNCA sobrescreve arquivo existente (colisão = merge
# manual); o rm protege o README do SEU projeto (o do skeleton é doc do esqueleto);
# mktemp evita resíduo de execução anterior (a limpeza fica fora da cadeia &&):
d=$(mktemp -d) && git clone --depth 1 https://github.com/samyrwendel/adas "$d" && rm "$d/skeleton/README.md" && cp -Rn "$d/skeleton/." . ; rm -rf "$d"
# ou, de um clone local (tar xkf = keep-old-files, NÃO sobrescreve; exclui o README na ORIGEM;
# na colisão o tar erra e sai !=0 — é o sinal de merge manual, o resto já foi extraído):
(cd /caminho/do/clone/adas/skeleton && tar cf - --exclude=./README.md .) | tar xkf - -C /caminho/do/projeto/
```

**3) Via raw (rápido)** — puxe só o prompt:
```bash
curl -fsSL https://raw.githubusercontent.com/samyrwendel/adas/main/adas-bootstrap-prompt.md
```

## As 2 regras que fazem ele "colar"
1. **`frontmatter.description` é o roteador.** A faixa só dispara se casar com o que o usuário falou —
   liste todo sinônimo E sintoma ("tá feio", "quebrado", "desalinhado"). Gatilho magro = faixa que nunca acorda.
2. **`.specs/` separado das faixas é nível de estabilidade**, não redundância: constituição rara e
   compartilhada ≠ faixa que evolui com o projeto.

## Licença
MIT — ver [LICENSE](LICENSE).
