# <PROJETO> ADAS — modo MECANISMO
<!-- adas-modo: mecanismo -->

> Aqui não há humano no ato: quem commita é um agente. Documento no contexto não muda o
> que o agente faz; o que muda é gate que nega, check que falha, hook que recusa. Por isso
> **invariante sem gatilho NÃO entra** — `scripts/check-mecanismo.sh` FALHA se uma linha
> numerada abaixo não aponta um mecanismo registrado e um teste que roda. Regra que não
> cabe nesse molde não é regra deste projeto: é consulta (`scripts/da-index.sh show DA-NNN`).

<!-- adas-core-start -->
## Invariantes (cada linha: regra — mecanismo: <arquivo que a cobra> · teste: <arquivo que prova>)

1. **Segredo nunca entra no repo** — mecanismo: scripts/check-secrets.sh · teste: mecanismo/tests/check-secrets.test.sh
2. **<PLACEHOLDER: a regra que já custou um erro neste repo>** — mecanismo: <PLACEHOLDER> · teste: <PLACEHOLDER>
3. **<PLACEHOLDER: outra regra com gatilho>** — mecanismo: <PLACEHOLDER> · teste: <PLACEHOLDER>

Como nasce um invariante: (1) inventário dos erros que JÁ aconteceram aqui (git log, issues,
tarefas falhas); (2) para cada um, o gatilho — hook em `.claude/settings.json`, check no
pre-commit (`scripts/install-hooks.sh`), gate no `package.json`/`Makefile`/CI; (3) uma linha
acima, com o teste; (4) a decisão no `DECISIONS.md` (`scripts/da-new.sh`), com quem decidiu.
<!-- adas-core-end -->

## Enforcement
`bash scripts/check-adas.sh` lê `modo: mecanismo` em `.adas/profile.json` e chama
`scripts/check-mecanismo.sh` — FAIL (exit 1) bloqueia o pre-commit instalado por
`scripts/install-hooks.sh`. Segredo: `scripts/check-secrets.sh` (mecânico) +
`scripts/check-app-security.sh` (as portas com prova em `.adas/seguranca-app.json`).
