#!/usr/bin/env node
'use strict';

/**
 * adas-check — RUNNER unificado (modo compare do ADAS)
 *
 * Roda todas as faixas implementadas contra um diretório de UI e emite UM
 * relatório consolidado de saída de faixa (o "painel do ADAS"). Orquestra os
 * checadores por faixa via --json (não os reimplementa).
 *
 * Uso:
 *   node adas-check.js <dir-ui> [--profile example] [--lanes design,i18n] [--json]
 *
 * Cross-platform: usa process.execPath (binário do Node) — sem shell, sem PATH.
 */

const { spawnSync } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

const LANES = {
  design: { script: 'check-design.js', label: 'Design' },
  i18n: { script: 'check-i18n.js', label: 'Idioma / i18n' },
};

function fail(m) { console.error(`\n✖ ${m}`); process.exit(1); }

function parseArgs(argv) {
  const out = { dir: null, profile: 'example', config: null, lanes: Object.keys(LANES), json: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--profile') { out.profile = argv[++i]; continue; }
    if (a === '--config') { out.config = argv[++i]; continue; }
    if (a === '--lanes') { out.lanes = String(argv[++i] || '').split(',').map((s) => s.trim()).filter(Boolean); continue; }
    if (a === '--json') { out.json = true; continue; }
    if (a.startsWith('--')) fail(`Argumento desconhecido: ${a}`);
    out.dir = a;
  }
  if (!out.dir) fail('Informe o diretório de UI. Ex.: node adas-check.js ./resources/js');
  for (const l of out.lanes) if (!LANES[l]) fail(`Faixa desconhecida: ${l}. Disponíveis: ${Object.keys(LANES).join(', ')}`);
  return out;
}

function runLane(name, dir, profile, config) {
  const script = path.join(__dirname, LANES[name].script);
  const args = [script, dir, '--json'];
  if (name === 'design') { if (config) args.push('--config', config); args.push('--profile', profile); }
  const r = spawnSync(process.execPath, args, { encoding: 'utf8' });
  if (r.status !== 0) return { error: (r.stderr || `exit ${r.status}`).trim() };
  try { return JSON.parse(r.stdout); } catch (e) { return { error: `JSON inválido: ${e.message}` }; }
}

function severityOfCount(c) { return c >= 20 ? 'major' : c >= 5 ? 'minor' : 'nit'; }

function summarize(name, res) {
  if (res.error) return { error: res.error };
  if (name === 'design') {
    const deps = res.departures || [];
    const s = { major: 0, minor: 0, nit: 0 };
    for (const d of deps) s[severityOfCount(d.count)] += 1;
    return { total: deps.length, ...s, note: `${res.rogueOccurrences} ocorrências em ${res.filesScanned} arquivos`,
      top: deps.slice(0, 5).map((d) => `${d.hex} (${d.count}×) → ${d.token}`) };
  }
  if (name === 'i18n') {
    const parityKeys = (res.parity || []).reduce((n, p) => n + p.missing.length, 0);
    const attrs = (res.attrs || []).length;
    const jsx = (res.jsx || []).length;
    return { total: parityKeys + attrs + jsx, major: parityKeys, minor: attrs, nit: jsx,
      note: res.localesDir ? `locales: ${(res.locales || []).join(', ')}` : 'locales não encontrados',
      top: [
        ...(res.attrs || []).slice(0, 3).map((a) => `${a.attr}="${a.text}" (${a.file}:${a.line})`),
        ...(res.jsx || []).slice(0, 2).map((j) => `>${j.text}< (${j.file}:${j.line})`),
      ] };
  }
  return { total: 0 };
}

function bar(n) { return n === 0 ? '·' : '█'.repeat(Math.min(n, 40)); }

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.dir);
  if (!fs.existsSync(root)) fail(`Diretório não existe: ${root}`);

  const results = {};
  for (const lane of args.lanes) results[lane] = runLane(lane, root, args.profile, args.config);
  const summaries = {};
  for (const lane of args.lanes) summaries[lane] = summarize(lane, results[lane]);

  if (args.json) {
    console.log(JSON.stringify({ project: root, profile: args.profile, lanes: args.lanes, summaries, raw: results }, null, 2));
    return;
  }

  const grand = args.lanes.reduce((n, l) => n + (summaries[l].total || 0), 0);
  console.log(`\n╔══ ADAS · Relatório de Saída de Faixa ══╗`);
  console.log(`Projeto: ${root}`);
  console.log(`Perfil: ${args.profile} | Faixas: ${args.lanes.join(', ')}\n`);

  for (const lane of args.lanes) {
    const s = summaries[lane];
    if (s.error) { console.log(`■ ${LANES[lane].label}: ⚠ erro — ${s.error}\n`); continue; }
    const tag = s.total === 0 ? '✅ na pista' : `${s.total} desvios`;
    console.log(`■ ${LANES[lane].label}: ${tag}  ${s.note ? `(${s.note})` : ''}`);
    if (s.total > 0) {
      console.log(`   major ${String(s.major).padStart(3)} ${bar(s.major)}`);
      console.log(`   minor ${String(s.minor).padStart(3)} ${bar(s.minor)}`);
      console.log(`   nit   ${String(s.nit).padStart(3)} ${bar(s.nit)}`);
      for (const t of (s.top || [])) console.log(`   • ${t}`);
    }
    console.log('');
  }

  console.log(`────────────────────────────────────────`);
  console.log(grand === 0
    ? `✅ PROJETO NA PISTA — nenhuma saída de faixa nas faixas verificadas.`
    : `TOTAL: ${grand} saídas de faixa. Detalhe completo: rode os checadores por faixa (check-<faixa>.js) ou use --json.`);
}

main();
