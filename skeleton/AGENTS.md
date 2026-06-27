# <PROJETO> — leia o ADAS antes de produzir qualquer coisa

> Este projeto é governado por um **ADAS** (Anti-Drift Adherence System): faixas/guard-rails que te
> mantêm dentro da spec — em vez de inventar cor, estrutura, escopo, nomenclatura ou texto novos.
> **Princípio-mestre: ADESÃO > INVENÇÃO.** Se já existe token/componente/padrão/decisão, USE o que existe.

## Antes de QUALQUER tarefa
1. Leia **[`ADAS.md`](ADAS.md)** — o pacote portátil de governança (faixas + índice de decisões).
2. A faixa detalhada vive em **`.claude/skills/<faixa>/SKILL.md`**. A constituição (invariantes mais
   estáveis + valores crus) em **`.specs/`**. O histórico de decisões em **[`DECISIONS.md`](DECISIONS.md)**.
3. **Escada de decisão (antes de escrever código novo):** precisa existir? → já existe no projeto? →
   stdlib? → nativo da plataforma? → dependência já instalada? → uma linha? → só então o mínimo. Pare no
   1º degrau que resolve ("o melhor código é o que você não escreve" — padrão do ponytail). Os
   não-negociáveis (validação, erro, segurança, caminho do dinheiro testado) ficam SEMPRE.
4. Tomou/mudou uma decisão? Registre `DA-NNN` no `DECISIONS.md`, dobre na faixa afetada e **regenere o
   `ADAS.md` — no mesmo commit**. Supersede, nunca apaga.
5. **Atalho consciente?** Marque na linha — `// adas: <teto>. <upgrade>.` — vira débito rastreável
   (`node .claude/skills/adas-check/scripts/adas-debt.js .`). Estado geral: `scripts/adas-report.sh`.
6. Caminho crítico (dinheiro/segurança/irreversível): nunca executa sem confirmação explícita; rode
   `scripts/check-*.sh` antes do deploy.

## Multi-ferramenta (este é o arquivo-âncora padrão)
Pra cada ferramenta achar o ADAS sozinha no boot, **espelhe** (cp) ou **symlink** este arquivo:
- Claude Code → `CLAUDE.md`  ·  Cursor → `.cursorrules`  ·  (outros) → o arquivo que ela lê no boot.

```bash
cp AGENTS.md CLAUDE.md   # ou: ln -s AGENTS.md CLAUDE.md
```
Todos apontam pro mesmo `ADAS.md`. Sem âncora, a governança existe mas a ferramenta não a descobre.
