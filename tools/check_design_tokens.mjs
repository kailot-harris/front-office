#!/usr/bin/env node
/**
 * Design-token drift and contrast check (front-office#201, epic #200).
 *
 * 1. assets/design-tokens.sha256 must match assets/design-tokens.css.
 * 2. Each sport subtree mirror's web/app/design-tokens.css must be byte-identical to the
 *    canonical file. A sport that has not adopted the tokens yet is reported as PENDING,
 *    not a failure; set DESIGN_TOKENS_REQUIRE_ALL=1 once all four sports have merged
 *    their adoption issue, so a missing copy fails too.
 * 3. Every text/background pair used by the sites meets WCAG AA (4.5:1) in light and dark
 *    mode, for every site palette.
 *
 * DESIGN_TOKENS_ROOT points the script at a scratch directory for tests.
 */
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = process.env.DESIGN_TOKENS_ROOT || join(dirname(fileURLToPath(import.meta.url)), '..');
const SPORTS = ['mlb', 'nba', 'nfl', 'wnba'];
const SITES = ['landing', ...SPORTS];
export const SPORT_COPY = 'web/app/design-tokens.css';
const errors = [];
const notes = [];

const sha = (buf) => createHash('sha256').update(buf).digest('hex');
const canonPath = join(ROOT, 'assets', 'design-tokens.css');
const canon = readFileSync(canonPath);
const expected = readFileSync(join(ROOT, 'assets', 'design-tokens.sha256'), 'utf8').trim().split(/\s+/)[0];
if (sha(canon) !== expected) errors.push(`assets/design-tokens.sha256 is stale: file is ${sha(canon)}, sha256 says ${expected}`);

for (const s of SPORTS) {
  const p = join(ROOT, s, SPORT_COPY);
  if (!existsSync(p)) {
    (process.env.DESIGN_TOKENS_REQUIRE_ALL === '1' ? errors : notes).push(`${s}/${SPORT_COPY}: missing (PENDING adoption)`);
    continue;
  }
  const got = sha(readFileSync(p));
  if (got !== expected) errors.push(`${s}/${SPORT_COPY}: drifted (sha256 ${got}, expected ${expected})`);
  else notes.push(`${s}/${SPORT_COPY}: identical`);
}

// --- contrast ---------------------------------------------------------------
const css = canon.toString('utf8');
const darkStart = css.indexOf('@media (prefers-color-scheme: dark)');
const parts = { light: css.slice(0, darkStart), dark: css.slice(darkStart, css.indexOf('/* Shared accessibility utilities */')) };
function block(text, selector) {
  const out = {};
  const re = selector === ':root' ? /:root\s*\{([^}]*)\}/ : new RegExp(`\[data-site="${selector}"\]\s*\{([^}]*)\}`);
  const m = text.match(re);
  if (m) for (const d of m[1].matchAll(/(--fo-[\w-]+)\s*:\s*(#[0-9a-fA-F]{6})/g)) out[d[1]] = d[2];
  return out;
}
const lum = (hex) => {
  const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
};
export const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
const PAIRS = [
  ['--fo-text', '--fo-surface'], ['--fo-text', '--fo-surface-raised'],
  ['--fo-text-muted', '--fo-surface'], ['--fo-text-muted', '--fo-surface-raised'],
  ['--fo-accent', '--fo-surface'], ['--fo-accent', '--fo-surface-raised'],
  ['--fo-on-accent', '--fo-accent'],
  ['--fo-success', '--fo-surface'], ['--fo-warning', '--fo-surface'], ['--fo-danger', '--fo-surface'],
  ['--fo-success', '--fo-success-bg'], ['--fo-warning', '--fo-warning-bg'], ['--fo-danger', '--fo-danger-bg'],
  ['--fo-nfl-accent', '--fo-surface'], ['--fo-nba-accent', '--fo-surface'], ['--fo-wnba-accent', '--fo-surface'], ['--fo-mlb-accent', '--fo-surface'],
];
let checked = 0;
for (const mode of ['light', 'dark']) {
  const root = block(parts[mode], ':root');
  const lightRoot = block(parts.light, ':root');
  for (const site of SITES) {
    const site_ = site === 'landing' ? {} : block(parts[mode], site);
    const lightSite = site === 'landing' ? {} : block(parts.light, site);
    const v = mode === 'light' ? { ...root, ...site_ } : { ...lightRoot, ...lightSite, ...root, ...site_ };
    for (const [fg, bg] of PAIRS) {
      if (!v[fg] || !v[bg]) { errors.push(`${mode}/${site}: ${fg} or ${bg} undefined`); continue; }
      const r = ratio(v[fg], v[bg]);
      checked++;
      if (r < 4.5) errors.push(`${mode}/${site}: ${fg} ${v[fg]} on ${bg} ${v[bg]} is ${r.toFixed(2)}:1 (< 4.5)`);
    }
  }
}
notes.push(`contrast: ${checked} pairs checked`);

for (const n of notes) console.log(`ok   ${n}`);
for (const e of errors) console.log(`FAIL ${e}`);
process.exit(errors.length ? 1 : 0);
