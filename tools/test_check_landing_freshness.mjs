#!/usr/bin/env node
// Tests for tools/check_landing_freshness.mjs against the real-shaped
// fixtures in tools/fixtures/landing_freshness/ (read only).
import { join, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, 'check_landing_freshness.mjs');
const fx = join(here, 'fixtures', 'landing_freshness');
let failed = 0;

function run(dir) {
  const r = spawnSync(process.execPath, [script, join(fx, dir)], { encoding: 'utf8' });
  return { status: r.status, out: r.stdout + r.stderr };
}
function t(name, cond) { console.log(`${cond ? 'ok  ' : 'FAIL'} ${name}`); if (!cond) failed++; }

let r = run('stale');
t('a digest behind its scores file fails', r.status === 1);
t('the failure names sport, game, teams and both statuses',
  r.out.includes('>>> [FAIL] nba game_id=401909305 CHA @ ATL: landing_digest status=scheduled (no score), matchups_slates.json is_completed=true (97-111)'));
t('a game not final in the scores file is not flagged', !r.out.includes('401909312'));
t('sports without a digest are skipped', r.out.includes('>>> [SKIP] mlb: no data/landing_digest.json'));

r = run('fresh');
t('digests that agree with their scores files pass', r.status === 0);
t('NBA final compared', /\[OK\] nba: .*1 final in matchups_slates\.json/.test(r.out));
t('NFL final compared', /\[OK\] nfl: .*1 final in matchups_current_week\.json/.test(r.out));
t('a digest ahead of its scores file is not flagged', !r.out.includes('[FAIL]'));

r = run('no_scores');
t('a sport with no scores file is skipped, not failed', r.status === 0 && r.out.includes('>>> [SKIP] wnba: no data/matchups_slates.json'));

r = spawnSync(process.execPath, [script], { encoding: 'utf8' });
t('missing site root is a usage error', r.status === 2);

process.exit(failed ? 1 : 0);
