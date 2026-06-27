#!/usr/bin/env node
'use strict';

/**
 * adas-debt — COLETOR de débito localizado (atalhos conscientes marcados no código).
 *
 * Padrão importado do ponytail (github.com/DietrichGebert/ponytail, MIT) — o comentário
 * `ponytail:` vira aqui o marcador `adas:`. Quando você toma um atalho consciente, deixa
 * uma migalha NO LUGAR EXATO nomeando o teto + caminho de upgrade:
 *
 *   // adas: gateado só no card; varrer telas irmãs — ver DA-NNN
 *
 * Este script faz o grep desses marcadores e devolve uma lista `arquivo:linha: <texto>`.
 * É o oposto honesto do "relatório que inventa número": só mostra o que VOCÊ marcou — débito
 * REAL e localizado, não estimativa. Complementa o ratchet por contagem e o DECISIONS.md
 * (pesado/deliberado) com a granularidade do "deferi X bem aqui".
 *
 * Uso:
 *   node adas-debt.js [dir]                  # lista (default: cwd)
 *   node adas-debt.js [dir] --json           # { count, items:[{file,line,message}] }
 *   node adas-debt.js [dir] --count-only     # só o inteiro (composição em shell)
 *   node adas-debt.js [dir] --max <N>        # exit 1 se count > N (ratchet do débito)
 *
 * Cross-platform: só fs/path do Node (Windows e Linux/Mac), sem shell.
 */

const fs = require('node:fs');
const path = require('node:path');

// Marcador SÓ vale quando: (a) é o token LOWERCASE `adas:` (não "ADAS:" de prosa/título); e (b) vem
// atrás de um líder de comentário que NÃO seja parte de `://` (lookbehind mata URL `https://adas:`).
//   // adas: …   # adas: …   /* adas: … */   {/* adas: … */}   <!-- adas: … -->   ; adas: …   -- adas: …
const MARKER = /(?<!:)(?:\/\/+|\/\*+|\*+|#+|<!--|;+|--)\s*adas:\s*(.+?)\s*$/;
// limpa fechador de comentário no fim da mensagem ( */   -->   */} )
const TRAILER = /\s*(?:\*\/|-->)\s*\}*\s*$/;

const SKIP_DIRS = new Set([
  'node_modules', '.git', 'dist', 'build', 'out', '.next', 'coverage',
  'vendor', '.cache', '.turbo', 'tmp', '.trash', '_archive',
]);
const SKIP_EXT = new Set([
  '.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.ico', '.pdf', '.lock',
  '.woff', '.woff2', '.ttf', '.eot', '.map', '.min.js', '.zip', '.gz',
]);

function parseArgs(argv) {
  const out = { dir: '.', json: false, countOnly: false, max: null };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--json') { out.json = true; continue; }
    if (a === '--count-only') { out.countOnly = true; continue; }
    if (a === '--max') { out.max = parseInt(argv[++i], 10); continue; }
    if (a.startsWith('--')) { console.error(`✖ argumento desconhecido: ${a}`); process.exit(2); }
    out.dir = a;
  }
  return out;
}

function walk(dir, acc) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return acc; }
  for (const e of entries) {
    if (e.name.startsWith('.') && e.isDirectory() && !['.claude', '.specs', '.adas', '.agents'].includes(e.name)) {
      if (SKIP_DIRS.has(e.name)) continue;
    }
    if (e.isDirectory()) {
      if (SKIP_DIRS.has(e.name)) continue;
      walk(path.join(dir, e.name), acc);
    } else if (e.isFile()) {
      const ext = path.extname(e.name).toLowerCase();
      if (SKIP_EXT.has(ext)) continue;
      acc.push(path.join(dir, e.name));
    }
  }
  return acc;
}

function scan(file, rootForRel) {
  const items = [];
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch { return items; }
  if (text.includes("\u0000")) return items; // binário (byte nulo)
  const rel = path.relative(rootForRel, file) || file;
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    const m = MARKER.exec(lines[i]);
    if (m && m[1]) {
      const message = m[1].replace(TRAILER, '').trim();
      if (message) items.push({ file: rel.split(path.sep).join('/'), line: i + 1, message });
    }
  }
  return items;
}

function main() {
  const opt = parseArgs(process.argv.slice(2));
  const root = path.resolve(opt.dir);
  // O coletor mira CÓDIGO do consumidor — não os arquivos onde a convenção `adas:` é DEFINIDA/ensinada
  // (como um linter não linta os próprios docs/config). Exclui: o motor (adas-check/scripts) + os
  // meta-arquivos de governança do ADAS (ADAS.md/AGENTS.md/CLAUDE.md/DECISIONS.md/SKILL.md/.cursorrules),
  // que trazem o marcador como EXEMPLO. Código real do projeto (.js/.ts/.py…) segue 100% varrido.
  const SELF = path.join('adas-check', 'scripts');
  const META = new Set(['ADAS.md', 'AGENTS.md', 'CLAUDE.md', 'DECISIONS.md', 'SKILL.md', '.cursorrules']);
  const files = walk(root, []).filter((f) => !f.includes(SELF) && !META.has(path.basename(f)));
  const items = [];
  for (const f of files) items.push(...scan(f, root));
  items.sort((a, b) => (a.file === b.file ? a.line - b.line : a.file < b.file ? -1 : 1));

  const count = items.length;
  const overMax = opt.max != null && Number.isFinite(opt.max) && count > opt.max;

  if (opt.countOnly) { process.stdout.write(String(count)); process.exit(overMax ? 1 : 0); }
  if (opt.json) {
    console.log(JSON.stringify({ count, max: opt.max, overMax, items }, null, 2));
    process.exit(overMax ? 1 : 0);
  }

  if (count === 0) {
    console.log("✓ sem débito marcado com 'adas:'.");
    console.log("  (marque atalhos conscientes: // adas: <teto>. <caminho de upgrade>. — vira débito rastreável)");
    process.exit(0);
  }
  console.log(`ADAS — débito localizado (atalhos marcados com \`adas:\`)\n`);
  let cur = null;
  for (const it of items) {
    if (it.file !== cur) { cur = it.file; }
    console.log(`  ${it.file}:${it.line}: ${it.message}`);
  }
  console.log(`\ntotal: ${count} atalho(s) marcado(s)${opt.max != null ? ` (teto ${opt.max})` : ''}.`);
  if (overMax) { console.log(`✗ excedeu o teto (${count} > ${opt.max}) — quite débito ou suba o teto conscientemente.`); process.exit(1); }
  console.log('(débito marcado é honesto: é o que VOCÊ deferiu, não estimativa. Quite antes de fechar a faixa.)');
  process.exit(0);
}

main();
