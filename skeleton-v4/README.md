# ADAS skeleton v4 — esqueleto copiável, dois modos

Estrutura mínima de um **ADAS** (Anti-Drift Adherence System) pra colar num projeto. UM esqueleto;
o **modo** é declarado em `.adas/profile.json` por `scripts/adas-init.sh` e o `check-adas.sh` obedece.

## Dia 0 — três comandos, de dentro do seu repo (git init já feito)
```bash
git clone --depth 1 https://github.com/samyrwendel/adas /tmp/adas-src
(cd /tmp/adas-src/skeleton-v4 && tar cf - --exclude=./README.md .) | tar xkf - -C .
bash scripts/adas-init.sh --modo doc --fonte /tmp/adas-src      # ou: --modo mecanismo
```
`tar xkf` nunca sobrescreve arquivo existente (colisão = o tar avisa e sai ≠ 0: é o sinal do merge
manual). Depois: `bash scripts/check-adas.sh` → **1 aviso** (os placeholders que faltam preencher).

## Quem está no ato? — o único critério do modo
- **`--modo doc`** — há um humano na sessão. Quem aplica a regra é o dono; o check lembra, não impede.
  Fica: `.specs/` → faixas (`.claude/skills/*/SKILL.md`) → `ADAS.md` → hook JIT por glob → diário.
- **`--modo mecanismo`** — agente headless, ou repo commitado por agente. **Invariante sem gatilho não
  entra**: cada linha numerada do núcleo do `ADAS.md` aponta `mecanismo:` (hook/check/gate registrado)
  e `teste:` (arquivo que roda e sai 0), senão `scripts/check-mecanismo.sh` FALHA e o pre-commit
  bloqueia. Modelo em `mecanismo/ADAS.mecanismo.md` (vira o `ADAS.md` no init).

Sem modo declarado, o check audita como `doc` e diz o comando. Trocar de modo = rodar o init de novo
(nada preenchido é sobrescrito).

## O que vem
| Arquivo | Papel |
|---|---|
| `AGENTS.md` | âncora: a ferramenta descobre o ADAS no boot (`cp AGENTS.md CLAUDE.md` para Claude Code) |
| `ADAS.md` | pacote portátil; o bloco `adas-core` é o que o runtime host (opcional) reinjeta |
| `.specs/` | constituição: invariantes + valores crus |
| `.claude/skills/*/SKILL.md` | faixas (formato Anthropic Skill); `seguranca-acesso` vem pronta; `_template/` para as suas |
| `.claude/hooks/` + `settings.json` | JIT por faixa na edição; índice de DAs nasce junto com a DA |
| `DECISIONS.md` | diário append-only; `scripts/da-new.sh` é a porta única; `da-index.sh` gera o índice e os checks |
| `scripts/check-adas.sh` | higiene + modo; `--seal` grava a prova em `.adas/install-check` |
| `scripts/check-secrets.sh`, `check-app-security.sh` | segredo (mecânico) + seis portas do app (com prova) |
| `scripts/install-hooks.sh` | pre-commit: segredo BLOCK · check-adas · índice sincronizado |
| `mecanismo/` | template e teste de referência do modo mecanismo |

Convenções: `check-adas.sh [--seal] [dir]`, `da-index.sh <cmd> [dir]`, `da-new.sh … [dir]` — sem `[dir]`,
todos agem na raiz do projeto do script (nunca no cwd, nunca na sua home).
