#!/usr/bin/env node
'use strict';

/**
 * adas-check — faixa IDIOMA / i18n (modo compare / drift-check)
 *
 * Três sensores de saída de faixa:
 *  A. Paridade de chaves entre locales (chave em pt-BR sem par em en-US e vice-versa). [alta confiança]
 *  B. Atributos hardcoded (placeholder/aria-label/title/alt/label = "texto literal"). [alta confiança]
 *  C. Texto JSX hardcoded (>texto< fora de {t(...)}). [heurística — revisar]
 *
 * Uso:
 *   node check-i18n.js <dir-ui> [--locales <dir>] [--json]
 *
 * Cross-platform (Windows/Linux): só fs/path do Node.
 */

const fs = require('node:fs');
const path = require('node:path');

const UI_EXT = new Set(['.tsx', '.jsx', '.ts', '.js', '.vue', '.svelte']);
const SKIP_DIRS = new Set(['node_modules', 'dist', 'build', 'vendor', '.git', '.next', '.turbo', 'coverage', 'i18n', 'locales']);
const ATTR_RE = /\b(placeholder|aria-label|title|alt|label)\s*=\s*"([^"{}]*?)"/g;
const JSX_TEXT_RE = />\s*([^<>{}\n]*?[A-Za-zÀ-ÿ]{2,}[^<>{}\n]*?)\s*</g;

function fail(m) { console.error(`\n✖ ${m}`); process.exit(1); }

function parseArgs(argv) {
  const out = { dir: null, locales: null, json: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--locales') { out.locales = argv[++i]; continue; }
    if (a === '--json') { out.json = true; continue; }
    if (a.startsWith('--')) fail(`Argumento desconhecido: ${a}`);
    out.dir = a;
  }
  if (!out.dir) fail('Informe o diretório de UI. Ex.: node check-i18n.js ./resources/js');
  return out;
}

// --- localizar a pasta de locales (contém subpastas de locale com .json) ---
function findLocalesDir(root) {
  let found = null;
  (function walk(dir) {
    if (found) return;
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (!e.isDirectory()) continue;
      if (e.name === 'node_modules' || (e.name.startsWith('.') && e.name !== '.')) continue;
      const full = path.join(dir, e.name);
      if (e.name === 'locales') {
        const subs = fs.readdirSync(full, { withFileTypes: true }).filter((d) => d.isDirectory());
        const withJson = subs.filter((d) => fs.readdirSync(path.join(full, d.name)).some((f) => f.endsWith('.json')));
        if (withJson.length >= 2) { found = full; return; }
      }
      walk(full);
    }
  })(root);
  return found;
}

function flattenKeys(obj, prefix, acc) {
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === 'object' && !Array.isArray(v)) flattenKeys(v, key, acc);
    else acc.add(key);
  }
  return acc;
}

function loadLocales(localesDir) {
  const result = {}; // locale -> namespace -> Set(keys)
  for (const locale of fs.readdirSync(localesDir, { withFileTypes: true }).filter((d) => d.isDirectory())) {
    const nsMap = {};
    for (const file of fs.readdirSync(path.join(localesDir, locale.name)).filter((f) => f.endsWith('.json'))) {
      const ns = path.basename(file, '.json');
      try {
        const json = JSON.parse(fs.readFileSync(path.join(localesDir, locale.name, file), 'utf8'));
        nsMap[ns] = flattenKeys(json, '', new Set());
      } catch { nsMap[ns] = new Set(); }
    }
    result[locale.name] = nsMap;
  }
  return result;
}

function parityDepartures(locales) {
  const names = Object.keys(locales);
  const departures = [];
  if (names.length < 2) return departures;
  const allNs = new Set(names.flatMap((l) => Object.keys(locales[l])));
  for (const ns of allNs) {
    // união de todas as chaves do namespace entre locales
    const union = new Set();
    for (const l of names) for (const k of (locales[l][ns] || new Set())) union.add(k);
    for (const l of names) {
      const have = locales[l][ns] || new Set();
      const missing = [...union].filter((k) => !have.has(k));
      if (missing.length) departures.push({ namespace: ns, locale: l, missing });
    }
  }
  return departures;
}

function walkUi(dir, files) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (e.name.startsWith('.') && e.name !== '.') continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name)) walkUi(full, files); }
    else if (UI_EXT.has(path.extname(e.name))) files.push(full);
  }
}

function isWordy(s) { return /[A-Za-zÀ-ÿ]{2,}/.test(s) && !/^[A-Z0-9_]+$/.test(s.trim()); }

function scanStrings(files, root) {
  const attrs = []; // {file,line,attr,text}
  const jsx = [];   // {file,line,text}
  for (const file of files) {
    const rel = path.relative(root, file);
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    lines.forEach((line, idx) => {
      let m;
      ATTR_RE.lastIndex = 0;
      while ((m = ATTR_RE.exec(line)) !== null) {
        const text = m[2].trim();
        if (text && isWordy(text) && text.includes(' ')) attrs.push({ file: rel, line: idx + 1, attr: m[1], text });
        else if (text && isWordy(text) && text.length >= 4) attrs.push({ file: rel, line: idx + 1, attr: m[1], text });
      }
      JSX_TEXT_RE.lastIndex = 0;
      while ((m = JSX_TEXT_RE.exec(line)) !== null) {
        const text = m[1].trim();
        // ruído: pula se contém chamada de função, símbolos de código, ou parece técnico
        if (!isWordy(text)) continue;
        if (/[=;`]|=>|\bt\(|\.\w+\(|https?:|\/\//.test(text)) continue;
        if (text.length < 3) continue;
        jsx.push({ file: rel, line: idx + 1, text: text.slice(0, 60) });
      }
    });
  }
  return { attrs, jsx };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.dir);
  const localesDir = args.locales ? path.resolve(args.locales) : findLocalesDir(root);

  const locales = localesDir ? loadLocales(localesDir) : {};
  const parity = parityDepartures(locales);

  const files = [];
  walkUi(root, files);
  const { attrs, jsx } = scanStrings(files, root);

  if (args.json) {
    console.log(JSON.stringify({ lane: 'i18n', dir: root, localesDir, locales: Object.keys(locales), parity, attrs, jsx }, null, 2));
    return;
  }

  console.log(`\n=== ADAS drift-check · faixa IDIOMA / i18n ===`);
  console.log(`Alvo UI: ${root}`);
  console.log(`Locales: ${localesDir ? `${localesDir} (${Object.keys(locales).join(', ')})` : 'NÃO encontrados'}`);
  console.log(`Arquivos de UI varridos: ${files.length}\n`);

  // A. paridade
  console.log(`A. PARIDADE DE CHAVES entre locales — ${parity.reduce((n, p) => n + p.missing.length, 0)} chaves sem par`);
  if (!parity.length) console.log('   ✅ chaves espelhadas entre todos os locales.');
  for (const p of parity) {
    console.log(`   [major] ${p.namespace} · ${p.locale} faltando ${p.missing.length}: ${p.missing.slice(0, 6).join(', ')}${p.missing.length > 6 ? ' …' : ''}`);
  }

  // B. atributos hardcoded
  console.log(`\nB. ATRIBUTOS HARDCODED (placeholder/aria-label/title/alt/label) — ${attrs.length}`);
  if (!attrs.length) console.log('   ✅ nenhum atributo com texto literal.');
  for (const a of attrs.slice(0, 25)) console.log(`   [minor] ${a.file}:${a.line}  ${a.attr}="${a.text}"`);
  if (attrs.length > 25) console.log(`   … +${attrs.length - 25}`);

  // C. texto JSX hardcoded (heurística)
  console.log(`\nC. TEXTO JSX HARDCODED (heurística — revisar) — ${jsx.length} suspeitos`);
  for (const j of jsx.slice(0, 25)) console.log(`   [nit] ${j.file}:${j.line}  >${j.text}<`);
  if (jsx.length > 25) console.log(`   … +${jsx.length - 25}`);

  console.log(`\nFix: A → adicionar a chave faltante no locale; B/C → trocar o literal por t('ns.secao.elemento') e criar a chave em pt-BR E en-US.`);
}

main();
