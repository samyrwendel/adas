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
DECISIONS.md  (LOG append-only DA-NNN, com cadeia de supersede)
```
Cada camada **cita e é gerada da de cima**. Por isso "auto-aprimorar" é mecânico: decisão entra como
`DA-NNN`, dobra na faixa que afeta, regenera o portátil — **no mesmo commit**; nunca apaga, só *supersede*.

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
| [`skeleton/`](skeleton/) | **Esqueleto vazio** copiável (`.specs/` + `skills/_template/` + `DECISIONS.md` + `ADAS.md` + hook). |

## Como chamar o ADAS em qualquer projeto

**1) Via prompt (qualquer LLM) — recomendado** — aponte a LLM pro seu projeto e cole o conteúdo de
[`adas-bootstrap-prompt.md`](adas-bootstrap-prompt.md). O próprio prompt manda **copiar o esqueleto**
(`git clone … && cp`) pra dentro do projeto, audita o repo e **preenche** as camadas (`.specs/` →
faixas → `ADAS.md` → hook).

**2) Via esqueleto (mãos na massa)** — copie a estrutura e preencha os `<PLACEHOLDER>`:
```bash
# dentro do projeto destino:
git clone https://github.com/samyrwendel/adas /tmp/adas && cp -r /tmp/adas/skeleton/. .
# ou, se você mantém este repo clonado localmente:
cp -r ~/projects/adas-template/skeleton/. /caminho/do/projeto/
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
