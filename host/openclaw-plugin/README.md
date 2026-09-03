# adas-openclaw — plugin ADAS pro OpenClaw

Injeta a governança ADAS (núcleo do `ADAS.md` do repo) a cada turno e bloqueia comandos de shell que
violam a faixa `seguranca-acesso` (ex.: `cat .env` fora do lugar). Não reimplementa nenhuma regra —
chama os scripts do `host/` deste repo (`adas-resolve.sh`, `adas-core.sh`, `adas-secret-guard.sh`)
via subprocess, a MESMA fonte que os hooks do Claude Code usam.

## O que este plugin cobre — e o que NÃO cobre

| Gancho ADAS | Hook OpenClaw usado | Cobre? |
|---|---|---|
| Núcleo injetado por turno (equivalente ao SessionStart do Claude Code) | `before_prompt_build` | Sim — roda A CADA turno, então não tem os "4 buracos de decaimento" que o Claude Code precisa de 3 hooks pra fechar (compactação/resume não apaga nada porque a injeção acontece de novo no próximo turno) |
| Faixa por subagente (SubagentStart) | mesmo `before_prompt_build`, porque também roda pra turnos de subagente | Provavelmente sim — **NÃO PROVADO** contra um subagente real do OpenClaw (sem Gateway isolado testável neste servidor, ver "O que não foi provado" abaixo) |
| Bloqueio de comando proibido | `before_tool_call` com `block: true` | Sim — e é **mais forte** que o Claude Code: o ADAS no Claude Code hoje só injeta contexto no PreToolUse, nunca recusa a ferramenta |
| Faixa por-arquivo no instante da edição (o JIT do PASSO 6, glob por faixa) | — | **NÃO coberto por este plugin.** `before_tool_call` vê o nome/params da ferramenta, não necessariamente um "arquivo sendo editado" no mesmo formato do Claude Code (`Edit\|Write\|MultiEdit` + `file_path`). Ficaria pra uma versão futura mapear `event.derivedPaths`/tool-specific params pra faixa certa. |

## Instalação

```bash
cd host/openclaw-plugin
npm install
npm run build
openclaw plugins install . --link
openclaw plugins enable adas-openclaw
```

Configuração opcional (`~/.openclaw/config.json` ou equivalente do seu profile), se o repo `adas`
não estiver clonado em `~/adas`:

```json
{
  "plugins": {
    "entries": {
      "adas-openclaw": { "config": { "adasHome": "/caminho/pro/clone/do/adas" } }
    }
  }
}
```

Repos governados: mesmo `~/.claude/adas/repos.conf` que o host do Claude Code usa (um caminho
absoluto por linha) — **um `repos.conf` compartilhado entre todos os harnesses instalados na
máquina**, não um por plugin.

## Testar que os ganchos disparam

**Provado neste repo, sem precisar de Gateway nem de sessão viva** (roda de verdade contra
`openclaw/plugin-sdk/plugin-entry`, os scripts do `host/` reais, e um fixture de `ADAS.md`):

```bash
npm test
```

**NÃO provado aqui** (checklist pra quem instalar de verdade):

1. `openclaw plugins install . --link && openclaw plugins inspect adas-openclaw --runtime --json`
   — confirma que o LOADER real do OpenClaw aceita o plugin (não só o `register()` isolado que o
   `npm test` exercita). **Cuidado:** neste servidor, rodar `openclaw --profile <nome> ...` ou
   `openclaw --dev ...` pela primeira vez pode disparar uma migração de estado que toca
   `~/.openclaw/` mesmo com o perfil isolado — leia a saída do comando ATÉ O FIM procurando
   `state-migrations`/`Doctor changes` antes de confiar que ficou isolado (achado real desta
   instalação, não hipotético — se aparecer, faça backup de `~/.openclaw/*.json` primeiro).
2. Um subagente REAL do OpenClaw recebendo o núcleo via `before_prompt_build` (o teste só prova
   que o handler injeta certo quando chamado — não que o runtime chama esse hook pra turnos de
   subagente da mesma forma que chama pra turnos normais).
3. `before_tool_call` bloqueando de verdade um `exec` disparado pelo modelo (o teste chama o
   handler diretamente com um evento sintético — não passou pela política real de aprovação/
   `requireApproval` do OpenClaw em runtime).
