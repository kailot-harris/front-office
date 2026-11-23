#!/usr/bin/env node
// Contract test for nav/switcher.json (front-office#212).
// - Every sport's 'pages' must equal the href/label pairs in that sport's
//   Sidebar.tsx subtree mirror (excluding the /front-office/ home link).
// - Every 'related' source label must be a page in some sport, and every
//   target label must be a page in that target sport.
// - A related entry is pointless (and an error) when the target sport
//   already has the source label as an exact match.
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const table = JSON.parse(readFileSync(join(root, 'nav', 'switcher.json'), 'utf8'));
const SPORTS = ['nfl', 'nba', 'wnba', 'mlb'];
const errors = [];

function sidebarPairs(sport) {
  const src = readFileSync(join(root, sport, 'web', 'components', 'Sidebar.tsx'), 'utf8');
  const re = /href:\s*['"]([^'"]+)['"][\s\S]*?label:\s*['"]([^'"]+)['"]/g;
  const out = {};
  for (const m of src.matchAll(re)) out[m[1]] = m[2];
  return out;
}

for (const s of SPORTS) {
  const entry = table.sports?.[s];
  if (!entry) { errors.push(`${s}: missing from sports`); continue; }
  const mirror = sidebarPairs(s);
  const want = JSON.stringify(Object.entries(mirror).sort());
  const got = JSON.stringify(Object.entries(entry.pages).sort());
  if (want !== got) errors.push(`${s}: pages differ from ${s}/web/components/Sidebar.tsx\n  sidebar: ${want}\n  table:   ${got}`);
  if (entry.pages['/'] !== 'Season Standings') errors.push(`${s}: '/' must be Season Standings`);
}

const labelsOf = (s) => new Set(Object.values(table.sports[s]?.pages ?? {}));
const allLabels = new Set(SPORTS.flatMap((s) => [...labelsOf(s)]));
for (const [src, targets] of Object.entries(table.related ?? {})) {
  if (!allLabels.has(src)) errors.push(`related: source '${src}' is not a page in any sport`);
  for (const [t, label] of Object.entries(targets)) {
    if (!SPORTS.includes(t)) { errors.push(`related.${src}: unknown sport '${t}'`); continue; }
    if (!labelsOf(t).has(label)) errors.push(`related.${src}.${t}: '${label}' is not a ${t} page`);
    if (labelsOf(t).has(src)) errors.push(`related.${src}.${t}: ${t} has an exact '${src}' page; entry is unreachable`);
  }
}

if (errors.length) { console.error(errors.join('\n')); process.exit(1); }
console.log(`switcher table OK (${SPORTS.length} sports, ${Object.keys(table.related).length} related entries)`);
