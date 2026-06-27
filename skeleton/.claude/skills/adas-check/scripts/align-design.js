#!/usr/bin/env node
'use strict';

/**
 * adas-check — ALIGN faixa Design (fase 1: consistência de cor)
 *
 * Traz o projeto pra pista trocando cada cor rogue pelo token aprovado —
 * MAS só onde o token é inequívoco (distância RGB <= --max-distance). Rogues
 * ambíguos (Δ grande, sem token óbvio) NUNCA são trocados: ficam listados pra
 * decisão humana. Não briga com o volante.
 *
 * DRY-RUN por padrão (só mostra o que mudaria). `--apply` escreve.
 *
 * Uso:
 *   node align-design.js <dir-ui> [--profile example] [--max-distance 24] [--apply]
 *
 * Fase 2 (tokenizar: criar CSS vars e trocar por var(--token)) é separada.
 * Cross-platform: process.execPath + fs, sem shell.
 */

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const UI_EXT = new Set(['.tsx', '.ts', '.jsx', '.js', '.css', '.scss', '.vue', '.svelte']);
const SKIP_DIRS = new Set(['node_modules', 'dist', 'build', 'vendor', '.git', '.next', '.turbo', 'coverage']);

function fail(m) { console.error(`\n✖ ${m}`); process.exit(1); }

function parseArgs(argv) {
  const out = { dir: null, profile: 'example', config: null, maxDistance: 24, apply: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--profile') { out.profile = argv[++i]; continue; }
    if (a === '--config') { out.config = argv[++i]; continue; }
    if (a === '--max-distance') { out.maxDistance = Number(argv[++i]); continue; }
    if (a === '--apply') { out.apply = true; continue; }
    if (a.startsWith('--')) fail(`Argumento desconhecido: ${a}`);
    out.dir = a;
  }
  if (!out.dir) fail('Informe o diretório de UI. Ex.: node align-design.js ./resources/js');
  if (!Number.isFinite(out.maxDistance) || out.maxDistance < 0) fail('--max-distance deve ser número >= 0');
  return out;
}

function getDepartures(dir, profile, config) {
  const checker = path.join(__dirname, 'check-design.js');
  const a = [checker, dir, '--json'];
  if (config) a.push('--config', config);
  a.push('--profile', profile);
  const r = spawnSync(process.execPath, a, { encoding: 'utf8' });
  if (r.status !== 0) fail(`check-design falhou: ${(r.stderr || '').trim()}`);
  return JSON.parse(r.stdout).departures || [];
}

function hexRegex(normHex) {
  // normHex = #rrggbb (lowercase). Casa a forma de 6 dígitos e, quando os pares
  // são repetidos (#rrggbb com r==r, g==g, b==b), também a forma 3 dígitos (#rgb)
  // — porque o código-fonte pode usar #222 onde o check normalizou pra #222222.
  const b = normHex.slice(1);
  const alts = [b];
  if (b[0] === b[1] && b[2] === b[3] && b[4] === b[5]) alts.push(b[0] + b[2] + b[4]);
  return new RegExp('#(?:' + alts.join('|') + ')(?![0-9a-fA-F])', 'gi');
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

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.dir);
  const departures = getDepartures(root, args.profile, args.config);

  const confident = departures.filter((d) => d.distance <= args.maxDistance);
  const ambiguous = departures.filter((d) => d.distance > args.maxDistance);

  // mapa: rogue normalizado (6 dígitos) -> token
  const replaceMap = new Map(confident.map((d) => [d.hex.toLowerCase(), d.token]));

  const files = [];
  walkUi(root, files);

  // por rogue: { occ, files:Set }
  const stats = new Map([...replaceMap.keys()].map((h) => [h, { occ: 0, files: new Set() }]));
  let filesChanged = 0;

  for (const file of files) {
    const orig = fs.readFileSync(file, 'utf8');
    let next = orig;
    for (const [rogue, token] of replaceMap) {
      // casa 6 dígitos (e 3 dígitos quando aplicável) em qualquer caixa, sem pegar 8 dígitos (alpha)
      const re = hexRegex(rogue);
      next = next.replace(re, (m) => {
        const s = stats.get(rogue); s.occ += 1; s.files.add(file);
        return token;
      });
    }
    if (next !== orig) {
      filesChanged += 1;
      if (args.apply) fs.writeFileSync(file, next, 'utf8');
    }
  }

  const totalOcc = [...stats.values()].reduce((n, s) => n + s.occ, 0);
  const mode = args.apply ? 'APLICADO' : 'DRY-RUN (nada escrito)';

  console.log(`\n=== ADAS align · faixa Design · fase 1 (consistência) · ${mode} ===`);
  console.log(`Alvo: ${root} | perfil: ${args.profile} | Δmax: ${args.maxDistance}\n`);

  console.log(`TROCAS ${args.apply ? 'feitas' : 'propostas'}: ${replaceMap.size} cores, ${totalOcc} ocorrências em ${filesChanged} arquivos`);
  for (const [rogue, token] of replaceMap) {
    const s = stats.get(rogue);
    if (s.occ === 0) continue;
    const d = confident.find((x) => x.hex.toLowerCase() === rogue);
    console.log(`   ${rogue} → ${token}  (Δ${d.distance})  ${s.occ}× em ${s.files.size} arq`);
  }

  console.log(`\nREVISAR MANUALMENTE (sem token óbvio, Δ > ${args.maxDistance}): ${ambiguous.length}`);
  for (const d of ambiguous) {
    console.log(`   ${d.hex} (${d.count}×)  candidato ${d.token} Δ${d.distance} — decida você (pode ser cor de marca estranha)`);
  }

  if (!args.apply) {
    console.log(`\nRode com --apply para escrever as ${totalOcc} trocas inequívocas. Depois rode o check-design pra confirmar a queda.`);
  } else {
    console.log(`\n✅ Aplicado. Rode o check-design pra confirmar, e revise os ambíguos acima. Fase 2 (tokenizar em CSS vars) é um passo à parte.`);
  }
}

main();
