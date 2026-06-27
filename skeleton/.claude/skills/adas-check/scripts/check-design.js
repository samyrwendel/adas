#!/usr/bin/env node
'use strict';

/**
 * adas-check — faixa DESIGN (modo compare / drift-check)
 *
 * Sensor de saída de faixa do design system: varre arquivos de UI e reporta
 * cada cor hex que NÃO faz parte do token set aprovado, com arquivo:linha e o
 * token aprovado mais próximo (sugestão de fix). Determinístico, zero LLM.
 *
 * Tokens (a "pista") resolvidos nesta ordem — funciona em QUALQUER projeto:
 *   1. --config <profile.json>      (explícito)
 *   2. .adas/profile.json           (auto, subindo do dir alvo)
 *   3. --profile <builtin>          (example; fallback)
 * Bootstrap: --detect-tokens emite um profile.json a partir das CSS vars do projeto.
 *
 * Uso:
 *   node check-design.js <dir-alvo> [--config <f>] [--profile example] [--json]
 *   node check-design.js <dir-alvo> --detect-tokens   # gera perfil das CSS vars
 *
 * Cross-platform (Windows/Linux): só fs/path do Node, sem shell.
 */

const fs = require('node:fs');
const path = require('node:path');

// --- Perfis built-in (fallback). Holdge = ADAS faixa Design. ---
// Builtin de EXEMPLO (fallback neutro). O real vem de .adas/profile.json (ou --detect-tokens) — troque pelo do seu projeto.
const BUILTIN_PROFILES = {
  example: [
    "#000000", "#0a0a0a", "#121212", "#1f1f1f", "#333333", "#555555",
    "#888888", "#aaaaaa", "#cccccc", "#ffffff",
  ],
};

const UI_EXTENSIONS = new Set(['.tsx', '.ts', '.jsx', '.js', '.css', '.scss', '.vue', '.svelte']);
const SKIP_DIRS = new Set(['node_modules', 'dist', 'build', 'vendor', '.git', '.next', '.turbo', 'coverage']);
const HEX_RE = /#[0-9a-fA-F]{3}\b|#[0-9a-fA-F]{6}\b/g;

function fail(msg) { console.error(`\n✖ ${msg}`); process.exit(1); }

function parseArgs(argv) {
  const out = { dir: null, profile: 'example', config: null, detectTokens: false, json: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--profile') { out.profile = argv[++i]; continue; }
    if (a === '--config') { out.config = argv[++i]; continue; }
    if (a === '--detect-tokens') { out.detectTokens = true; continue; }
    if (a === '--json') { out.json = true; continue; }
    if (a.startsWith('--')) fail(`Argumento desconhecido: ${a}`);
    out.dir = a;
  }
  if (!out.dir) fail('Informe o diretório alvo. Ex.: node check-design.js ./resources/js');
  return out;
}

function normalizeHex(hex) {
  let h = hex.toLowerCase();
  if (h.length === 9) h = h.slice(0, 7); // #rrggbbaa -> #rrggbb (descarta alpha)
  if (h.length === 4) h = '#' + [...h.slice(1)].map((c) => c + c).join(''); // #abc -> #aabbcc
  return h;
}
function hexToRgb(hex) {
  const h = normalizeHex(hex);
  return [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
}
function colorDistance(a, b) {
  const [r1, g1, b1] = hexToRgb(a);
  const [r2, g2, b2] = hexToRgb(b);
  return Math.sqrt((r1 - r2) ** 2 + (g1 - g2) ** 2 + (b1 - b2) ** 2);
}
function nearestToken(hex, approvedList) {
  let best = null, bestD = Infinity;
  for (const t of approvedList) { const d = colorDistance(hex, t); if (d < bestD) { bestD = d; best = t; } }
  return { token: best, distance: Math.round(bestD) };
}

function walk(dir, files) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (e.name.startsWith('.') && e.name !== '.') continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name)) walk(full, files); }
    else if (UI_EXTENSIONS.has(path.extname(e.name))) files.push(full);
  }
}

// --- resolução de tokens (a pista) ---
function findUp(startDir, relPath) {
  let dir = path.resolve(startDir);
  const root = path.parse(dir).root;
  for (;;) {
    const candidate = path.join(dir, relPath);
    if (fs.existsSync(candidate)) return candidate;
    if (dir === root) return null;
    dir = path.dirname(dir);
  }
}
function loadProfileTokens(file) {
  let json;
  try { json = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { fail(`Perfil inválido em ${file}: ${e.message}`); }
  const tokens = (json.design && json.design.tokens) || json.tokens;
  if (!Array.isArray(tokens) || !tokens.length) fail(`Perfil ${file} precisa de "design.tokens" (array de hex).`);
  return tokens.map(normalizeHex);
}
function resolveTokens(args, rootDir) {
  if (args.config) return { source: args.config, tokens: loadProfileTokens(args.config) };
  const found = findUp(rootDir, path.join('.adas', 'profile.json'));
  if (found) return { source: found, tokens: loadProfileTokens(found) };
  if (BUILTIN_PROFILES[args.profile]) return { source: `builtin:${args.profile}`, tokens: BUILTIN_PROFILES[args.profile].map(normalizeHex) };
  fail(`Sem perfil de tokens. Use --config <profile.json>, crie .adas/profile.json, ou --profile <${Object.keys(BUILTIN_PROFILES).join('|')}>. Dica: rode com --detect-tokens pra gerar um perfil das CSS vars.`);
}
function detectCssVarTokens(rootDir) {
  const files = []; walk(rootDir, files);
  const re = /--[\w-]+\s*:\s*(#[0-9a-fA-F]{3,8})\b/g;
  const found = new Set();
  for (const f of files) {
    if (!['.css', '.scss'].includes(path.extname(f))) continue;
    const txt = fs.readFileSync(f, 'utf8');
    let m;
    while ((m = re.exec(txt)) !== null) found.add(normalizeHex(m[1]));
  }
  return [...found].sort();
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const rootDir = path.resolve(args.dir);

  if (args.detectTokens) {
    const tokens = detectCssVarTokens(rootDir);
    console.log(JSON.stringify({ name: path.basename(rootDir), design: { tokens } }, null, 2));
    return;
  }

  const { source, tokens } = resolveTokens(args, rootDir);
  const approved = new Set(tokens);
  const approvedList = [...approved];

  const files = [];
  walk(rootDir, files);

  const rogue = new Map();
  let totalApproved = 0;
  for (const file of files) {
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    lines.forEach((line, idx) => {
      const matches = line.match(HEX_RE);
      if (!matches) return;
      for (const mraw of matches) {
        const norm = normalizeHex(mraw);
        if (approved.has(norm)) { totalApproved += 1; continue; }
        if (!rogue.has(norm)) rogue.set(norm, { count: 0, locations: [] });
        const entry = rogue.get(norm);
        entry.count += 1;
        if (entry.locations.length < 8) entry.locations.push(`${path.relative(rootDir, file)}:${idx + 1}`);
      }
    });
  }

  const rogueSorted = [...rogue.entries()].sort((a, b) => b[1].count - a[1].count);
  const totalRogueOcc = rogueSorted.reduce((n, [, v]) => n + v.count, 0);

  if (args.json) {
    console.log(JSON.stringify({
      lane: 'design', tokenSource: source, dir: rootDir,
      filesScanned: files.length, approvedOccurrences: totalApproved,
      rogueColors: rogueSorted.length, rogueOccurrences: totalRogueOcc,
      departures: rogueSorted.map(([hex, v]) => ({ hex, count: v.count, ...nearestToken(hex, approvedList), sample: v.locations })),
    }, null, 2));
    return;
  }

  console.log(`\n=== ADAS drift-check · faixa DESIGN ===`);
  console.log(`Alvo: ${rootDir}`);
  console.log(`Tokens: ${source} (${approvedList.length} aprovados)`);
  console.log(`Arquivos varridos: ${files.length} | hex aprovados: ${totalApproved}`);
  console.log(`\nSAÍDAS DE FAIXA: ${rogueSorted.length} cores fora do token set (${totalRogueOcc} ocorrências)\n`);

  if (rogueSorted.length === 0) { console.log('✅ Nenhum hex fora da pista. Design system aderente.'); return; }

  for (const [hex, v] of rogueSorted) {
    const { token, distance } = nearestToken(hex, approvedList);
    const sev = v.count >= 20 ? 'major' : v.count >= 5 ? 'minor' : 'nit';
    console.log(`[${sev}] ${hex}  (${v.count}×)  → use ${token} (Δ${distance})`);
    console.log(`        ${v.locations.slice(0, 4).join('  ')}${v.count > 4 ? '  …' : ''}`);
  }
  console.log(`\nFix: trocar cada hex pelo token sugerido (align-design.js), ou centralizar em CSS vars e referenciar var(--token).`);
}

main();
