// ADAS para OpenClaw — mesma regra do Claude Code (host/adas-*.sh), dois
// ganchos OpenClaw diferentes por natureza da API:
//
//   • CONTEXTO: `session_start` no OpenClaw é OBSERVAÇÃO-ONLY (não injeta —
//     ver docs/plugins/hooks.md, tabela de hooks, `session_start` não está em
//     **negrito**). Quem injeta é `before_prompt_build`, que roda A CADA
//     TURNO — isso cobre "session boundary" E "subagent" NUM SÓ gancho: o
//     Claude Code precisa de 3 hooks (SessionStart/PreToolUse/SubagentStart)
//     porque cada um resolve UM buraco de decaimento (compactação, hub
//     multi-repo, subagent órfão); aqui um único hook por-turno não decai
//     nunca, então não há três buracos pra fechar.
//   • BLOQUEIO: `before_tool_call` PODE bloquear de verdade (`block: true`) —
//     mais forte que o Claude Code, que no ADAS de hoje só injeta contexto no
//     PreToolUse e nunca recusa a ferramenta.
//
// NENHUMA regra é reimplementada em TypeScript: os dois hooks chamam os
// scripts bash do host (adas-resolve.sh / adas-core.sh / adas-secret-guard.sh)
// via subprocess — a MESMA fonte que os hooks do Claude Code chamam. Se a
// regra mudar, muda num lugar só e os dois harnesses veem a mudança.
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// resolveAdasHome: onde vivem os scripts do host/. NÃO É a regra em si —
// é só "onde acha o binário" (mesmo tipo de config que o Claude Code guarda
// em ~/.claude/adas/repos.conf). Configurável via config do plugin
// (`adasHome`) porque o repo adas pode estar clonado em qualquer lugar.
function resolveAdasHome(configured?: string): string | undefined {
  const candidates = [configured, join(homedir(), "adas")].filter(
    (p): p is string => Boolean(p),
  );
  for (const c of candidates) {
    if (existsSync(join(c, "host", "adas-core.sh"))) return c;
  }
  return undefined;
}

function runHostScript(adasHome: string, script: string, args: string[]): string {
  try {
    return execFileSync("bash", [join(adasHome, "host", script), ...args], {
      encoding: "utf8",
      timeout: 2000,
    }).trim();
  } catch {
    // fail-open: sem o host disponível, ADAS fica inerte — nunca quebra o turno.
    return "";
  }
}

export default definePluginEntry({
  id: "adas-openclaw",
  name: "ADAS for OpenClaw",
  description:
    "Injeta a governança ADAS por turno e bloqueia comando proibido pela faixa seguranca-acesso.",
  register(api) {
    api.on(
      "before_prompt_build",
      async (event: any) => {
        const adasHome = resolveAdasHome(event?.context?.pluginConfig?.adasHome);
        if (!adasHome) return;
        const cwd: string = event?.ctx?.workspaceDir ?? process.cwd();
        const repo = runHostScript(adasHome, "adas-resolve.sh", [cwd]);
        if (!repo) return;
        const core = runHostScript(adasHome, "adas-core.sh", [repo]);
        if (!core) return;
        return { prependSystemContext: core };
      },
      { priority: 10 },
    );

    api.on(
      "before_tool_call",
      async (event: any) => {
        // Só olha ferramentas de execução de shell — ADAS não tem opinião
        // sobre outras ferramentas (busca web, mídia, etc.).
        if (event.toolName !== "exec" && event.toolName !== "bash" && event.toolName !== "shell") {
          return;
        }
        const adasHome = resolveAdasHome(event?.context?.pluginConfig?.adasHome);
        if (!adasHome) return;
        const cmd: string =
          (event.params?.command as string) ?? (event.params?.cmd as string) ?? "";
        if (!cmd) return;
        const verdict = runHostScript(adasHome, "adas-secret-guard.sh", [cmd]);
        if (verdict.startsWith("block:")) {
          return { block: true, blockReason: verdict.slice("block:".length) };
        }
        return;
      },
      { priority: 10 },
    );
  },
});
