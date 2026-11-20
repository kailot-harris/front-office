#!/usr/bin/env node
// Tests for tools/check_design_tokens.mjs using scratch copies (never writes the sport mirrors).
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..');
const script = join(here, 'check_design_tokens.mjs');
let failed = 0;
function scratch() {
  const d = mkdtempSync(join(tmpdir(), 'tokens-'));
  mkdirSync(join(d, 'assets'));
  copyFileSync(join(repo, 'assets/design-tokens.css'), join(d, 'assets/design-tokens.css'));
  copyFileSync(join(repo, 'assets/design-tokens.sha256'), join(d, 'assets/design-tokens.sha256'));
  return d;
}
function run(d, env = {}) {
  return spawnSync(process.execPath, [script], { env: { ...process.env, DESIGN_TOKENS_ROOT: d, ...env }, encoding: 'utf8' }).status;
}
function sport(d, s, content) {
  mkdirSync(join(d, s, 'web/app'), { recursive: true });
  writeFileSync(join(d, s, 'web/app/design-tokens.css'), content);
}
function t(name, cond) { console.log(`${cond ? 'ok  ' : 'FAIL'} ${name}`); if (!cond) failed++; }

const canon = readFileSync(join(repo, 'assets/design-tokens.css'));
let d = scratch();
t('canonical file passes with sports pending', run(d) === 0);
t('missing sport fails when DESIGN_TOKENS_REQUIRE_ALL=1', run(d, { DESIGN_TOKENS_REQUIRE_ALL: '1' }) === 1);
for (const s of ['mlb', 'nba', 'nfl', 'wnba']) sport(d, s, canon);
t('identical sport copies pass with REQUIRE_ALL', run(d, { DESIGN_TOKENS_REQUIRE_ALL: '1' }) === 0);
sport(d, 'nba', canon.toString() + '\n/* local tweak */\n');
t('a drifted sport copy fails', run(d) === 1);

d = scratch();
writeFileSync(join(d, 'assets/design-tokens.sha256'), '0'.repeat(64) + '  design-tokens.css\n');
t('stale sha256 fails', run(d) === 1);

d = scratch();
writeFileSync(join(d, 'assets/design-tokens.css'), canon.toString().replace('--fo-text-muted: #475569;', '--fo-text-muted: #cbd5e1;'));
const { createHash } = await import('node:crypto');
writeFileSync(join(d, 'assets/design-tokens.sha256'), createHash('sha256').update(readFileSync(join(d, 'assets/design-tokens.css'))).digest('hex') + '  design-tokens.css\n');
t('a low-contrast token fails', run(d) === 1);

process.exit(failed ? 1 : 0);
