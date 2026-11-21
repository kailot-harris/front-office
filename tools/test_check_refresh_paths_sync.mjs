#!/usr/bin/env node
// Tests for tools/check_refresh_paths_sync.mjs using scratch copies of the
// fixtures in tools/fixtures/refresh_paths/ (never writes the sport mirrors).
import { mkdtempSync, mkdirSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, 'check_refresh_paths_sync.mjs');
const fx = join(here, 'fixtures', 'refresh_paths');
let failed = 0;

function scratch(slotFixture, allowFixture) {
  const d = mkdtempSync(join(tmpdir(), 'refresh-paths-'));
  mkdirSync(join(d, 'tools'));
  copyFileSync(join(fx, slotFixture), join(d, 'tools', 'run_refresh_slot.ps1'));
  for (const sport of ['mlb', 'nba']) {
    mkdirSync(join(d, sport, '.github', 'workflows'), { recursive: true });
    copyFileSync(join(fx, `workflow_${sport}.yml`), join(d, sport, '.github', 'workflows', 'refresh-results.yml'));
  }
  if (allowFixture) copyFileSync(join(fx, allowFixture), join(d, 'tools', 'refresh_paths_allowlist.json'));
  return d;
}
function run(root) {
  const env = { ...process.env };
  if (root) env.CHECK_REFRESH_PATHS_ROOT = root;
  else delete env.CHECK_REFRESH_PATHS_ROOT;
  const r = spawnSync(process.execPath, [script], { env, encoding: 'utf8' });
  return { status: r.status, out: r.stdout + r.stderr };
}
function t(name, cond) { console.log(`${cond ? 'ok  ' : 'FAIL'} ${name}`); if (!cond) failed++; }

let r = run(scratch('slot_in_sync.ps1'));
t('matching lists pass', r.status === 0);

r = run(scratch('slot_missing_digest.ps1'));
t('slot missing the landing digest fails', r.status === 1);
t('failure names the sport and the missing path',
  /nba: tools\/run_refresh_slot\.ps1 does not stage web\/public\/data\/landing_digest\.json/.test(r.out));
t('failure does not blame mlb', !/ mlb:/.test(r.out));

r = run(scratch('slot_extra_path.ps1'));
t('slot staging an extra file fails', r.status === 1);
t('failure names the extra path', /nba: tools\/run_refresh_slot\.ps1 stages web\/public\/data\/data_manifest\.json/.test(r.out));

r = run(scratch('slot_mlb_file_under_dir.ps1'));
t('a directory covers a file under it', r.status === 0);

r = run(scratch('slot_missing_digest.ps1', 'allowlist_nba_digest.json'));
t('an allowlisted gap passes', r.status === 0);
t('an allowlisted gap is printed as a known exception', r.out.includes('>>> [SKIP] known exception -- nba:'));

r = run(scratch('slot_in_sync.ps1', 'allowlist_nba_digest.json'));
t('a stale exception fails', r.status === 1 && r.out.includes('STALE exception in tools/refresh_paths_allowlist.json: nba missing_from_slot web/public/data/landing_digest.json'));

r = run(null);
t('the real slot script and subtree workflows agree', r.status === 0);
t('the NFL hold is reported as a known exception', r.out.includes('>>> [SKIP] known exception -- nfl:') && r.out.includes('held by owner pending NFL work'));

process.exit(failed ? 1 : 0);
