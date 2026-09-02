# ADAS — Bootstrap Prompt (template reutilizável)

> **ADAS = Anti-Drift Adherence System.** Como o ADAS de carro mantém você na **faixa**, este
> mantém qualquer LLM na **faixa da spec** — em vez de inventar cor, estrutura, escopo, nomenclatura
> ou texto novos. Princípio-mestre: **ADESÃO > INVENÇÃO** (consolidar > reescrever · padronizar >
> inventar · medir antes de substituir · nunca regredir o que funciona).

## A arquitetura (4 camadas + 1 loop)

```
.specs/  (CONSTITUIÇÃO: invariantes mais estáveis + valores crus; compartilhada entre repos)
   │  extraída/adaptada →
.claude/skills/*/SKILL.md  (FAIXAS: escopo do projeto, AUTO-DISPARADAS via frontmatter)
   │  destiladas →
ADAS.md  (PORTÁTIL: cola em qualquer LLM, sem hook/sem repo)
   │  injetada JIT →
.claude/settings.json hook  (REFORÇO no instante da edição — só Claude Code)
   +
DECISIONS.md  (LOG append-only de decisões DA-NNN, com cadeia de supersede)
```

Cada camada **cita a de cima**. Mudou o canônico → propaga pra baixo → regenera. O **loop de
auto-aprimoramento** não é "lembrar de atualizar": é uma **hierarquia de derivação** (o de baixo é
sempre gerado do de cima) + 3 disciplinas:
1. **Mesmo commit** — decisão + faixa + doc andam juntos.
2. **Supersede, não delete** — número nunca reusado; history vira trilha de auditoria.
3. **Regenerar do canônico** — `ADAS.md` é derivado das faixas; faixa é derivada de `.specs/`. Divergiu, regenera.

Os dois pontos finos: **(a)** o `frontmatter.description` é o roteador — gatilho magro = faixa que
nunca dispara; liste todo sinônimo E sintoma ("tá feio", "quebrado", "desalinhado"). **(b)** `.specs/`
separado das faixas não é redundância — é **nível de estabilidade** (constituição rara/compartilhada
≠ faixa que evolui com o projeto).

---

## O PROMPT (cole numa LLM capaz, apontando pro projeto)

```text
PAPEL: Você é o arquiteto de governança deste projeto. Construa um "ADAS"
(Anti-Drift Adherence System): um conjunto de FAIXAS (guard-rails) que mantêm
qualquer assistente de IA dentro das specs do projeto, em vez de inventar cor,
estrutura, escopo, nomenclatura ou texto novos. Princípio-mestre: ADESÃO > INVENÇÃO
(consolidar>reescrever, padronizar>inventar, medir antes de substituir, nunca
regredir o que funciona).

MODO DE CONTEXTO:
- PROJETO EM ANDAMENTO (já tem código): primeiro AUDITE o repo. Faça o inventário
  dos invariantes REAIS — tokens de design, componentes canônicos, convenções de
  pasta/arquivo, nomenclatura/termos, config/.env, caminhos críticos (dinheiro,
  auth, ações irreversíveis), integrações externas. Derive o ADAS do que EXISTE
  (engenharia reversa); aponte inconsistências; NÃO imponha convenção nova.
- PROJETO NOVO: me entreviste com as perguntas fundadoras (identidade visual?
  stack/arquitetura? escopo in/out? termos canônicos e proibidos? caminho crítico
  e suas regras? idiomas?). Derive das respostas + defaults sensatos; marque toda
  suposição.

SETUP — COPIE O ESQUELETO CANÔNICO (NÃO recrie a estrutura do zero). Rode na RAIZ do
projeto destino, NESTA ORDEM (a checagem de colisão vem ANTES da cópia — de propósito):

  # 1) COLISÕES: liste os arquivos vivos que o esqueleto traria por cima. Se listar
  #    QUALQUER um, PARE e resolva por merge manual ANTES de copiar — projeto JÁ
  #    governado (ADAS.md/DECISIONS.md preenchidos) NUNCA re-copia o esqueleto
  #    (re-execução destruiria o log de decisões). README.md fica FORA da lista:
  #    o esqueleto nunca o traz (o rm do passo 2 o remove na ORIGEM + cp -Rn não sobrescreve).
  for t in AGENTS.md DECISIONS.md ADAS.md .claude/settings.json \
           .claude/hooks/adas-inject.sh .adas/profile.json; do
    [ -e "$t" ] && echo "COLISÃO: $t — merge manual antes de prosseguir"
  done

  # 2) CÓPIA NO-CLOBBER (cp -Rn NUNCA sobrescreve — GNU e BSD; o rm protege o README
  #    do SEU projeto: o do skeleton é doc do esqueleto). mktemp evita resíduo de
  #    execução anterior; a limpeza fica FORA da cadeia && (roda mesmo em falha parcial).
  #    Grava .adas/skeleton-version (commit do esqueleto) — é como o check-adas sabe se
  #    este install ficou atrasado em relação ao canônico.
  #    (coreutils 9.2: cp -n pode sair !=0 ao PULAR arquivo — ignore; o juiz é o passo 3):
  d=$(mktemp -d) && git clone --depth 1 https://github.com/samyrwendel/adas "$d" \
    && rm "$d/skeleton/README.md" && { cp -Rn "$d/skeleton/." . || true; } \
    && mkdir -p .adas && git -C "$d" rev-parse HEAD | cut -c1-7 > .adas/skeleton-version ; rm -rf "$d"
  #  (o `|| true` no cp: o exit!=0 do skip NÃO pode engolir a gravação da versão; o mkdir cobre cópia parcial)

  # 3) CONFIRME a cópia (enumeração completa e mecânica — diz QUAL arquivo falta).
  #    Se falhar o clone ou faltar arquivo: PARE e reporte — NUNCA recrie o esqueleto de memória:
  ok=1; for f in .specs/SKILL.md .specs/tokens.css .claude/settings.json \
    .claude/hooks/adas-inject.sh .claude/skills/_template/SKILL.md \
    .claude/skills/seguranca-acesso/SKILL.md .claude/skills/adas-check/SKILL.md \
    scripts/check-adas.sh scripts/check-secrets.sh scripts/adas-report.sh \
    DECISIONS.md ADAS.md AGENTS.md .adas/profile.json .adas/skeleton-version; do
    [ -f "$f" ] || { echo "FALTA: $f"; ok=0; }
  done; [ "$ok" = 1 ] && echo "esqueleto OK" || echo "FALTA ARQUIVO — pare e reporte"

Os PASSOS abaixo PREENCHEM esses arquivos — não recriam a estrutura.

PASSO 0 — CAMADA .specs/ (CONSTITUIÇÃO): identifique os 1–3 invariantes MAIS estáveis
e compartilhados entre repos/superfícies (tipicamente: identidade visual + tokens
crus; talvez contratos/endereços; talvez vocabulário de marca). PREENCHA os arquivos
JÁ COPIADOS `.specs/SKILL.md` e `.specs/tokens.css` (deixe-os num lugar COMPARTILHADO,
fora das skills de um repo só). As faixas (PASSO 2) são GERADAS daqui e DEVEM citar a
procedência ("extraído de .specs/…"). Liste os ESPELHOS (onde cada valor canônico é
copiado) pra a propagação ser explícita.

PASSO 1 — IDENTIFIQUE AS FAIXAS (só as que se aplicam; faixa = domínio onde o drift
causa retrabalho). Candidatas: Visual/Design · Arquitetura/Padrões de código
(módulos canônicos + lista "reusar-não-recriar" + anti-padrões) · Produto/Escopo ·
Nomenclatura/Termos · Caminho crítico (dinheiro/segurança — regras + testes) ·
Idioma/Copy/i18n · **Segredos & Acesso** (token/.env/chave/repo) · Decisões/Governança
(o protocolo já vem pronto no DECISIONS.md — ver PASSO 5) · <faixa específica do projeto>.
A faixa **Segredos & Acesso** (`.claude/skills/seguranca-acesso/`) já vem PREENCHIDA no esqueleto
(regras universais: nunca commitar segredo, token least-privilege, não caçar credencial, confirmar
op de repo irreversível) + o gate `scripts/check-secrets.sh` — MANTENHA, não recrie; só ajuste o específico do projeto.

PASSO 2 — Para CADA faixa, DUPLIQUE a pasta-modelo `.claude/skills/_template/` →
`.claude/skills/<nome>/` e preencha o `SKILL.md` (apague `_template/` no fim):
  FRONTMATTER no PADRÃO OFICIAL Anthropic Skills (name + description; when_to_use é OPCIONAL/extra):
    - NÃO reinvente o formato da skill — siga `anthropics/skills` (`spec/` + `template/`) + `skill-creator`;
      o ADAS só soma a governança no corpo. (Faixa do ADAS = Anthropic Skill.)
    - description = TODO o triggering e "PUSHY" (guidance oficial p/ combater UNDERtriggering): lista
      exaustiva de gatilhos + SINTOMAS + "use SEMPRE que …, MESMO sem pedir explícito". É o roteador.
    - PISO MECÂNICO obrigatório (o check-adas COBRA — LLMs sistematicamente entregam trigger magro
      mesmo com esta instrução): ≥400 chars; ≥12 gatilhos separados por ,/; (verbos + sinônimos +
      variantes coloquiais); a cláusula "use SEMPRE que"; a negação "MESMO que o usuário não peça";
      ≥2 SINTOMAS entre aspas simples — frases como o usuário REALMENTE fala ('tá quebrado',
      'esse ainda funciona?'), não categorias abstratas. Se o projeto tem histórico de conversa,
      minere os gatilhos das mensagens REAIS do usuário — é o melhor corpus de trigger que existe.
    - Otimize o trigger com o `skill-creator` (description-improver). when_to_use = extra (oficial = tudo no description).
  CORPO com:
    - QUANDO SE APLICA (resumo dos gatilhos)
    - FONTE DA VERDADE (onde vivem os valores/componentes/configs canônicos —
      caminhos exatos; "nunca hardcodar, sempre reusar via X") + PROCEDÊNCIA
      ("extraído de .specs/…")
    - FAÇA / NÃO FAÇA (numerado, incluindo a lista de LEGADOS PROIBIDOS)
    - INVENTÁRIO REUSE-FIRST (o que JÁ existe e DEVE ser reusado antes de criar novo)
    - LEITURAS OBRIGATÓRIAS + TRAVA (padrão do spec-skills, cura da reinvenção):
      preencha `references/mandatory-readings.md` (os arquivos REAIS a ler antes de
      editar nesta faixa) + `references/few-shots/` (exemplos canônicos preenchidos) +
      a seção "Trava obrigatória" (pare na ambiguidade; leia o código real antes de agir).

PASSO 3 — PREENCHA o LOG DE DECISÕES `DECISIONS.md` (já no esqueleto, estilo ADR). Cada entrada:
  "## DA-NNN — Título" + "Status ✅ Aceita | 🔄 Supersedida por DA-MMM · Data" +
  Contexto / Decisão / Consequências (números reais quando der) / Implementação
  (arquivos:linha). Numerar sequencial, NUNCA reusar. Mudar decisão = marcar a
  antiga como Supersedida (nunca apagar). Índice rápido no topo.

PASSO 4 — PREENCHA o doc PORTÁTIL `ADAS.md` (já no esqueleto): autocontido (funciona
colado em QUALQUER LLM, sem acesso ao repo). Cabeçalho: procedência + data + quais decisões
reflete + "fonte da verdade = .specs/ e as faixas; se divergirem, regenere".
Preâmbulo "Como usar": ler ANTES de produzir qualquer coisa; adesão > invenção.
Tabela de roteamento "tarefa → faixa".

PASSO 5 — PROTOCOLO OPERACIONAL (loop de auto-aprimoramento): o texto-base JÁ VEM
preenchido no DECISIONS.md copiado (seção "Protocolo operacional") e destilado na
faixa 5 do ADAS.md — NÃO reescreva; só ajuste exemplos ao projeto. Pra ele DISPARAR
sozinho (recomendado), crie a faixa `.claude/skills/decisoes/` duplicando `_template/`
(é a candidata Decisões/Governança do PASSO 1): description = "toda decisão
tomada/mudada/questionada + todo fix aprovado", corpo CITANDO o DECISIONS.md — não
duplique o texto. O que o protocolo cobre (referência, já está lá):
  - TODA decisão → entrada DA-NNN + dobrar na(s) faixa(s) afetada(s), NO MESMO COMMIT.
  - Fix aprovado de CLASSE (padrão possível em superfície irmã) → regra na faixa
    SENSÍVEL que dispara no momento certo (description/hook/check); doc morto não conta.
  - Mudou .specs/ → propaga espelhos → atualiza faixa → REGENERA o ADAS.md.
  - Supersede, não delete (log append-only = trilha de auditoria).
  - Análise de impacto antes de "feito" (callers/schemas/docs/testes/espelhos no mesmo
    commit; flagar o que ficou de fora de propósito).

PASSO 6 (só Claude Code) — PREENCHA `.claude/hooks/adas-inject.sh` (FONTE ÚNICA, já
registrada no `.claude/settings.json` com matcher `Edit|Write|MultiEdit`): um `case` por
faixa — arquivo que casa com o glob → injeta a spec destilada como additionalContext
(enforcement JIT no momento da edição). O texto fica versionado com o código; NÃO
duplique a regra em string inline no settings (é a triplicação que gera drift).

PASSO 7 (opcional, mas FORTEMENTE recomendado p/ caminho crítico) — FAIXAS EXECUTÁVEIS
+ GATE: transforme cada NÃO-FAÇA crítico (sobretudo do caminho do dinheiro/segurança)
num check RODÁVEL em scripts/check-<nome>.sh (duplique scripts/check-_template.sh; sai
!= 0 quando VIOLA, com mensagem ACIONÁVEL). Wire um gate de pré-deploy/CI:
  - MONEY-PATH e SEGURANÇA bloqueiam (SEVERITY=block, build falha): ex. callback de
    pagamento sem handler, vazamento de RLS, mistura de unidade/moeda.
  - Limpeza/estilo só AVISAM (SEVERITY=warn): ex. botões/handlers órfãos, TODO.
  - Gate no package.json — em LOOP, porque `bash scripts/check-*.sh` rodaria SÓ o
    1º script (os demais viram argumentos $1 $2 dele) — e SEM forçar SEVERITY no loop
    (cada check FIXA a sua internamente: block é o default do template p/ dinheiro/
    segurança; nos de limpeza/estilo hardcode SEVERITY=warn no próprio script — forçar
    block em tudo anularia o tier warn definido acima):
    "deploy": "for f in scripts/check-*.sh; do bash $f || exit 1; done && build && <restart>".
  - SEGREDOS no gate: o check-secrets.sh é staged por default (pré-commit); no deploy
    não há nada staged — o script cai sozinho pra varredura completa nesse caso, mas
    rodando manual prefira `bash scripts/check-secrets.sh --all`.
  - Duplicou o template? REMOVA scripts/check-_template.sh no fim (como o `_template/`
    das skills) — ele casa com o glob `check-*.sh` e entraria no gate.
  Registre o gate como DA-NNN e cite o check na faixa ("enforcement: scripts/check-<nome>.sh").
  O hook pega no momento da EDIÇÃO; o check pega no COMMIT/DEPLOY — as duas pontas.
  ENGINE PRONTO p/ faixas de UI (design/i18n): o esqueleto já traz checadores Node
  profile-driven em `.claude/skills/adas-check/scripts/` — `adas-check.js` (runner/compare),
  `check-design.js` (cor fora do token), `check-i18n.js` (paridade de locale + hardcoded),
  `align-design.js` (auto-fix de cor, dry-run). Defina a "pista" em `.adas/profile.json`
  (ou `check-design.js <dir> --detect-tokens` gera das CSS vars). É o espelho de máquina da `.specs/`.

PASSO 8 (opcional) — AUTO-AUDITORIA DO ADAS (o ADAS governa o ADAS): use o
scripts/check-adas.sh (já vem pronto e genérico) no gate. Pega o modo de falha nº1
desses sistemas — a derivação .specs → faixas → ADAS.md rotar em SILÊNCIO. Checa:
PLACEHOLDER não preenchido; faixa sem frontmatter name/description = BLOCK (não
dispara); faixa sem PROCEDÊNCIA (invariante sem origem = chute); DRIFT (faixa/.specs
commitada DEPOIS do ADAS.md → regenere); DA-NNN citada mas ausente do DECISIONS.md;
e ENFORCEMENT LIGADO (hook JIT do repo registrado + runtime host instalado/registrado/
com este repo no repos.conf — instalação-fantasma NÃO passa em silêncio).
WARN por padrão, exceto frontmatter quebrado.

PASSO 9 (OBRIGATÓRIO — o critério de aceite da SAÍDA cobra a âncora) — ONBOARDING /
ÂNCORA: preencha `AGENTS.md` (já copiado) — o arquivo
que qualquer LLM/ferramenta lê no PRIMEIRO contato e que aponta pro `ADAS.md` ("leia o
ADAS antes de produzir qualquer coisa"). Espelhe (cp) ou symlink pro nome que cada
ferramenta lê no boot: `CLAUDE.md` (Claude Code), `.cursorrules` (Cursor), etc. Sem
âncora, a governança existe mas a ferramenta não a descobre sozinha.

PASSO 10 — NADA A PREENCHER: a escada de decisão, o marcador `adas:` (débito localizado)
e o relatório honesto JÁ vêm embutidos no ADAS.md/AGENTS.md copiados. Ferramentas que
os acompanham (já copiadas): `.claude/skills/adas-check/scripts/adas-debt.js` coleta os
atalhos marcados `adas:` em arquivo:linha; `scripts/adas-report.sh` mostra o estado sem
inventar "% de aderência"; `scripts/da-index.sh` gera o `DECISIONS-INDEX.md` (1 linha
por DA — o DECISIONS.md cresce sem teto e um dia não cabe no contexto; o índice cabe
sempre). O índice NASCE com a DA via hook PostToolUse `da-index-hook.sh` (já registrado
no settings copiado) — não depende de lembrar de rodar comando; anexo por fora do hook
é acusado pelo check-adas (check 10). Detalhe do padrão: github.com/samyrwendel/adas →
README, seção PASSO 10.

PASSO 11 (opcional, só Claude Code — RUNTIME ANTI-DECAIMENTO): o JIT do PASSO 6 injeta
na edição, mas a aderência decai por 4 buracos (sessão que nasce FORA do repo — num hub
multi-repo o settings do repo nem carrega; compactação/resume que evapora o "leia o
ADAS.md"; subagents que nascem sem o contexto do pai; injeção dupla user+project).
Instale a camada host/ do repo adas — ATENÇÃO: host/ NÃO vem no esqueleto e o clone do
SETUP já foi apagado; re-clone e rode o INSTALADOR (idempotente: hooks + repos.conf +
merge no ~/.claude/settings.json preservando o que existe):
  d=$(mktemp -d) && git clone --depth 1 https://github.com/samyrwendel/adas "$d" \
    && bash "$d/host/install.sh" /caminho/deste/projeto ; rm -rf "$d"
A camada faz: reinjeção do NÚCLEO do ADAS.md (delimite-o com <!-- adas-core-start/end -->,
~30-45 linhas) em SessionStart (startup|resume|clear|compact) + SubagentStart, e roteador
PreToolUse user-level que delega ao .claude/hooks/adas-inject.sh do repo (guard anti-dupla).
Se pular este passo, o check-adas vai ACUSAR (warn de ENFORCEMENT) runtime ausente em toda
rodada — pulou consciente, conviva com o aviso; ele existe pra meia-instalação nunca calar.

SAÍDA: PREENCHA os arquivos COPIADOS (.specs/, .claude/skills/<faixa>/SKILL.md,
DECISIONS.md, ADAS.md, AGENTS.md, o hook, scripts/check-*), remova `_template/` E
`scripts/check-_template.sh` (o AGENTS.md copiado já registra de onde duplicar faixa
nova depois disso). CRITÉRIO DE ACEITE obrigatório antes de me mostrar qualquer coisa:
rode `bash scripts/check-adas.sh` e só finalize com saída limpa (zero PLACEHOLDER,
frontmatter ok, âncora apontando pro ADAS.md) — cole a saída no resultado. Então me
mostre o índice e me peça pra confirmar os invariantes que você reverse-engineerou.
```

---

## O hook (Claude Code — o que faz "colar")

O `settings.json` do esqueleto registra o hook; o texto das faixas vive em
**`.claude/hooks/adas-inject.sh`** (FONTE ÚNICA, versionada com o código — um `case` por faixa; o
mesmo script é chamado pelo roteador user-level do PASSO 11 quando a sessão nasce fora do repo):

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Edit|Write|MultiEdit",
      "hooks": [{
        "type": "command",
        "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/adas-inject.sh\"",
        "timeout": 10,
        "statusMessage": "ADAS"
      }]
    }]
  }
}
```

```bash
# .claude/hooks/adas-inject.sh (esqueleto já traz; um case por faixa)
f="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)"; [ -z "$f" ] && exit 0
case "$f" in
  *"/<glob-da-faixa>/"*) ctx="ADAS <faixa>: <spec destilada, com os PROIBIDOS>. Spec: .claude/skills/<faixa>/SKILL.md" ;;
  *) exit 0 ;;
esac
printf '%s' "$ctx" | jq -Rs '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:.}}' 2>/dev/null || true
```

Em LLM **sem** hook (ChatGPT/Gemini/etc.), o substituto é colar o **`ADAS.md` portátil** como
system/primeiro turno — por isso ele existe separado das faixas.

## Esqueleto canônico (o prompt já manda copiar — ver SETUP)
O esqueleto vive em **github.com/samyrwendel/adas** (`skeleton/`, ~26 arquivos): `.specs/` + 3 skills
(`_template/`, `seguranca-acesso/`, `adas-check/` com o engine) + `scripts/check-*` + `adas-report.sh` +
hook + `DECISIONS.md` + `ADAS.md` + `AGENTS.md` + `.adas/profile.json` — a enumeração operacional é a do
passo 3 do SETUP. O SETUP do prompt já faz o `git clone … && cp` pra dentro do projeto; os PASSOS
preenchem os `<PLACEHOLDER>`. Manual:
```bash
# cp -Rn NUNCA sobrescreve (colisão = merge manual); o rm protege o README do projeto destino;
# mktemp evita resíduo (limpeza fora da cadeia &&); grava .adas/skeleton-version (check 8):
d=$(mktemp -d) && git clone --depth 1 https://github.com/samyrwendel/adas "$d" \
  && rm "$d/skeleton/README.md" && { cp -Rn "$d/skeleton/." . || true; } \
  && mkdir -p .adas && git -C "$d" rev-parse HEAD | cut -c1-7 > .adas/skeleton-version ; rm -rf "$d"
```
