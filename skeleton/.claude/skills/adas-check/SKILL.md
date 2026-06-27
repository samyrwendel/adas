---
name: adas-check
description: "Modo COMPARE/ALIGN do ADAS — sensor de saída de faixa + auto-fix + débito/relatório. Audita o CÓDIGO contra as faixas (lanes) e reporta desvios com severidade + arquivo:linha + fix; o align corrige o mecânico; o debt junta os atalhos marcados `adas:`; o report mostra o estado SEM inventar número. Determinístico onde dá (grep/AST), LLM só pro nuance. Use quando o pedido for auditar/alinhar aderência ao design system, i18n, ou padrões do projeto, ou ver débito/estado do ADAS — em projeto novo ou bagunçado; gatilhos 'tem cor fora do token?', 'mistura de idioma?', 'alinha as cores', 'audita o design', 'drift', 'quanto débito ADAS?', 'lista os atalhos', 'relatório do ADAS', 'estado da governança'."
when_to_use: "Auditar (compare) ou auto-corrigir (align) o código contra as faixas de design/i18n/padrões; coletar débito localizado (adas-debt) ou ver o estado do ADAS (adas-report). Vale pra qualquer projeto; profile em .adas/profile.json."
---

# adas-check — compare/align (engine executável do ADAS)

> Procedência: engine importado de [samyrwendel/spec-skills](https://github.com/samyrwendel/spec-skills)
> (`.agents/skills/adas-check`). Aqui é o **braço executável** universal do método: o `check-adas.sh`
> audita a *governança*; este audita o *código*. Determinístico onde dá; LLM pro nuance.

## Os 3 modos
- **install** — projeto novo **nasce na pista** (skill-pack generativo específico da stack, ex.: o spec-skills p/ TS-fullstack). O `adas` não traz scaffolding de stack — use um consumidor.
- **compare** — detecta **saída de faixa** (drift) em qualquer projeto. ⬅️ este engine.
- **align** — **traz pra pista** (auto-fix do mecânico, flag do que é julgamento; dry-run por padrão).

## Faixas (por DOMÍNIO)
| Faixa | Check determinístico (barato, sem LLM) | Status |
|---|---|---|
| **Design** | hex fora do token set; sugere o token aprovado mais próximo (distância RGB) | ✅ `scripts/check-design.js` |
| **Idioma** | paridade de chaves entre locales; atributos/JSX hardcoded | ✅ `scripts/check-i18n.js` |
| **App / Produto / Decisões** | padrões do projeto; mockado/hardcoded; DA órfã | ⏳ (governança = `check-adas.sh`) |

## Uso
```bash
# runner unificado (todas as faixas) — painel de saída de faixa
node .claude/skills/adas-check/scripts/adas-check.js <dir-ui> [--lanes design,i18n] [--json]

# por faixa (detalhe):
node .claude/skills/adas-check/scripts/check-design.js <dir> [--config .adas/profile.json] [--json]
node .claude/skills/adas-check/scripts/check-i18n.js  <dir> [--locales <dir>] [--json]

# ALIGN (auto-fix de cor — dry-run por padrão; --apply escreve):
node .claude/skills/adas-check/scripts/align-design.js <dir> [--max-distance 24] [--apply]

# DEBT — coletor do marcador `adas:` (atalhos conscientes; débito localizado e honesto):
node .claude/skills/adas-check/scripts/adas-debt.js [dir] [--json] [--count-only] [--max N]

# REPORT — estado do ADAS COM guarda de honestidade (não inventa "% de aderência"):
bash scripts/adas-report.sh
```

## A pista (profile de tokens) — config-driven
Resolução: (1) `--config <profile.json>`; (2) `.adas/profile.json` (subindo do dir alvo); (3) builtin `example` (fallback).
- **Bootstrap:** `node scripts/check-design.js <dir> --detect-tokens` varre as CSS vars do projeto e emite um `profile.json` pronto.
- Cada projeto traz sua pista em `.adas/profile.json` (`{ "design": { "tokens": ["#hex", …] } }`) — é o espelho de máquina da constituição `.specs/`.

## Débito localizado + relatório honesto (PASSO 10 — padrão do ponytail, MIT)
- **`adas-debt.js`** (Node) — junta os atalhos conscientes marcados `// adas: <teto>. <upgrade>.` num
  relatório `arquivo:linha`. Débito **localizado e REAL** (o que VOCÊ deferiu), complementar ao
  `DECISIONS.md` (pesado) e ao ratchet por contagem. `--max N` falha se passar do teto (ratchet do débito).
  *O scanner não varre o próprio motor (`adas-check/scripts`) — exemplos não viram débito-fantasma.*
- **`adas-report.sh`** (bash) — estado do ADAS: conta faixas, DAs, débito `adas:`, placeholders e a saúde
  do `check-adas`. **Guarda de honestidade:** NUNCA imprime "% de aderência"/"% de drift evitado" — não há
  baseline do que a LLM teria inventado; reportar % seria chute. Para impacto real → benchmark A/B
  (com × sem faixas). Espelha o `/ponytail-gain`, que se recusa a inventar número por-repo.

## Cross-platform
Só `fs`/`path` do Node (Windows e Linux/Mac), sem shell POSIX. Requer Node no projeto (faixas de código = web/JS-land).
Auto-auditoria da **governança** (universal, sem Node) fica no `scripts/check-adas.sh` (bash); o `adas-report.sh`
(bash) usa o `adas-debt.js` (Node) só se houver Node — senão mostra o débito como "—".
