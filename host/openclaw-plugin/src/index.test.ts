// Prova por efeito, sem Gateway nem sessão viva: `createTestPluginApi` do SDK
// é interno (não exportado pra plugin de terceiro — confirmado lendo
// package.json/exports do pacote openclaw instalado), então este mock
// implementa só o `.on(name, handler, opts)` documentado e captura os
// handlers reais que `register()` registrou — dali em diante é código de
// PRODUÇÃO sendo exercitado, não um dublê da lógica.
import { describe, expect, it, beforeAll } from "vitest";
import { mkdtempSync, writeFileSync, mkdirSync, chmodSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import entry from "./index.js";

type Handler = (event: any) => any;

function mockApi() {
  const handlers = new Map<string, Handler[]>();
  return {
    on(name: string, handler: Handler, _opts?: unknown) {
      const list = handlers.get(name) ?? [];
      list.push(handler);
      handlers.set(name, list);
    },
    get(name: string): Handler {
      const list = handlers.get(name);
      if (!list || list.length === 0) throw new Error(`hook ${name} não registrado`);
      return list[0];
    },
  };
}

// Fixture: um "adasHome" mínimo — só o suficiente pra adas-resolve.sh/
// adas-core.sh/adas-secret-guard.sh reais rodarem (não mocka os scripts,
// exercita os de verdade via subprocess, igual em produção).
function buildAdasHomeFixture(): { adasHome: string; repo: string } {
  const base = mkdtempSync(join(tmpdir(), "adas-oc-test-"));
  const adasHome = join(base, "adas");
  const hostDir = join(adasHome, "host");
  mkdirSync(hostDir, { recursive: true });
  const repo = join(base, "repo");
  mkdirSync(repo, { recursive: true });
  writeFileSync(
    join(repo, "ADAS.md"),
    "# Repo teste\n<!-- adas-core-start -->\nNUCLEO-DE-TESTE\n<!-- adas-core-end -->\n",
  );
  writeFileSync(join(base, "repos.conf"), repo + "\n");
  // Copia os scripts REAIS do host deste repo adas (não reescreve nada).
  const real = join(process.cwd(), "..");
  for (const f of ["adas-lib.sh", "adas-resolve.sh", "adas-core.sh", "adas-secret-guard.sh"]) {
    const src = join(real, f);
    const dst = join(hostDir, f);
    const content = readFileSync(src, "utf8");
    writeFileSync(dst, content);
    chmodSync(dst, 0o755);
  }
  process.env.ADAS_REPOS_CONF = join(base, "repos.conf");
  return { adasHome, repo };
}

describe("adas-openclaw", () => {
  let adasHome: string;
  let repo: string;

  beforeAll(() => {
    ({ adasHome, repo } = buildAdasHomeFixture());
  });

  it("register() instala before_prompt_build e before_tool_call", () => {
    const api = mockApi();
    entry.register(api as any);
    expect(() => api.get("before_prompt_build")).not.toThrow();
    expect(() => api.get("before_tool_call")).not.toThrow();
  });

  it("before_prompt_build injeta o núcleo do ADAS.md do repo resolvido", async () => {
    const api = mockApi();
    entry.register(api as any);
    const handler = api.get("before_prompt_build");
    const result = await handler({
      ctx: { workspaceDir: repo },
      context: { pluginConfig: { adasHome } },
    });
    expect(result?.prependSystemContext).toContain("NUCLEO-DE-TESTE");
  });

  it("before_prompt_build fica em silêncio fora de repo governado (fail-open)", async () => {
    const api = mockApi();
    entry.register(api as any);
    const handler = api.get("before_prompt_build");
    const result = await handler({
      ctx: { workspaceDir: "/tmp/nao-e-governado-" + Date.now() },
      context: { pluginConfig: { adasHome } },
    });
    expect(result).toBeUndefined();
  });

  it("before_tool_call BLOQUEIA exec que lê .env fora do lugar", async () => {
    const api = mockApi();
    entry.register(api as any);
    const handler = api.get("before_tool_call");
    const result = await handler({
      toolName: "exec",
      params: { command: "cat .env" },
      context: { pluginConfig: { adasHome } },
    });
    expect(result?.block).toBe(true);
    expect(result?.blockReason).toContain("seguranca-acesso");
  });

  it("before_tool_call PERMITE exec inofensivo", async () => {
    const api = mockApi();
    entry.register(api as any);
    const handler = api.get("before_tool_call");
    const result = await handler({
      toolName: "exec",
      params: { command: "ls -la" },
      context: { pluginConfig: { adasHome } },
    });
    expect(result).toBeUndefined();
  });

  it("before_tool_call ignora ferramentas que não são shell", async () => {
    const api = mockApi();
    entry.register(api as any);
    const handler = api.get("before_tool_call");
    const result = await handler({
      toolName: "web_search",
      params: { query: "cat .env" },
      context: { pluginConfig: { adasHome } },
    });
    expect(result).toBeUndefined();
  });
});
