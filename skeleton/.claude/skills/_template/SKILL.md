---
name: <faixa-em-kebab-case>
# description = O ROTEADOR. A faixa só dispara se isto casar com o que o usuário falou.
# Liste EXAUSTIVAMENTE: todo sinônimo do domínio + SINTOMAS (como o usuário fala torto:
# "tá feio", "quebrado", "desalinhado", "não aparece", "melhora isso"). Gatilho magro = faixa que nunca acorda.
description: "<O que esta faixa governa> — usar SEMPRE que a tarefa tocar <lista exaustiva de
  gatilhos, palavras-chave, sinônimos e SINTOMAS>. Também ao <consultar histórico / antes de
  refatorar algo decidido conscientemente>."
# when_to_use = cenários concretos + globs de arquivo onde a faixa vale.
when_to_use: "Qualquer tarefa que <…>; vale para arquivos em <glob/da/faixa/**>."
---

# <Nome da Faixa>

> Procedência: extraído de `.specs/<arquivo>` + DA-<NNN>. Fonte da verdade = `.specs/` + esta faixa.
> Se este doc divergir da fonte, regenere.

## Quando se aplica
<resumo dos gatilhos do frontmatter, em 1–2 linhas.>

## Fonte da verdade (NÃO hardcodar)
- Valores canônicos vivem em: `<caminho>` — reusar via `<helper/classe/import>`, nunca valor cru.
- Componentes/módulos canônicos: `<lista>` — REUSAR, nunca recriar.

## Inventário REUSE-FIRST (o que já existe e DEVE ser reusado antes de criar novo)
- `<Componente/Módulo>` — <pra quê serve>. Usar isto em vez de inventar.
- `<…>`

## Regras — FAÇA
1. <regra positiva concreta>
2. <…>

## Regras — NÃO FAÇA
1. NUNCA <anti-padrão>. (Legados PROIBIDOS: `<lista>`.)
2. <…>
