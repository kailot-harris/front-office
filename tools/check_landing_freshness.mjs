#!/usr/bin/env node
/**
 * Deploy-time freshness check: the landing digest must not show a game as
 * not final when the same sport's scores file already has it final.
 *
 * Each sport publishes two views of last night's games: its scores file
 * (NBA/WNBA matchups_slates.json, NFL matchups_current_week.json, MLB
 * matchups/week-*.json) and data/landing_digest.json, whose yesterday[] list
 * drives the landing page's "Yesterday's results". The score refresh patches
 * both from the same rows, so on a healthy build they agree. On 2026-11-21 the
 * slot refresh committed only the scores file, and the live landing page
 * showed every NBA game of 2026-11-20 as "Not final" while the scores file had
 * seven of them final. Nothing in the deploy noticed.
 *
 * For every game in a digest's yesterday[] that the scores file marks
 * completed with both scores, the digest must say status "final" with the
 * same scores. Any mismatch prints a `>>> [FAIL]` line and exits 1, which
 * fails the deploy job before the Pages upload, so the previous site stays
 * live. Only that direction is checked: a digest that is AHEAD of the scores
 * file (final in the digest, not yet in the scores file) is left alone.
 *
 * A sport with no digest or no comparable scores file is skipped with a
 * `>>> [SKIP]` line; nothing is inferred or filled in.
 *
 * NFL IS WARN-ONLY. The owner is holding NFL's slot refresh change for other
 * NFL work, so slots B/C still do not commit NFL's re-graded digest and an NFL
 * mismatch is expected after a slot run. NFL mismatches print `>>> [WARN]`
 * and do not fail the deploy; NBA, WNBA and MLB still block. See WARN_ONLY.
 *
 * Usage:
 *   node tools/check_landing_freshness.mjs <site-root>
 *
 * <site-root> holds one directory per sport with the published data under
 * <sport>/data/ -- the assembled Pages output (site/), or a download of the
 * live site laid out the same way.
 */

import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SPORTS = ['mlb', 'nba', 'nfl', 'wnba'];

// Sports whose mismatches are reported as `>>> [WARN]` and never fail the
// deploy, with the reason. Remove a sport once its slot refresh commits its
// digest (tools/refresh_paths_allowlist.json holds the matching exception).
export const WARN_ONLY = new Map([
  ['nfl', 'held by owner pending NFL work: the slot refresh does not commit NFL\'s landing digest yet'],
]);

function readJson(p) {
  return JSON.parse(readFileSync(p, 'utf8'));
}

function rowsToIndex(rows, idKey) {
  const byId = new Map();
  for (const r of rows) {
    if (!r || r[idKey] === undefined || r[idKey] === null) continue;
    byId.set(String(r[idKey]), {
      completed: r.is_completed === true,
      home: r.home_team ?? null,
      away: r.away_team ?? null,
      home_score: r.home_score ?? null,
      away_score: r.away_score ?? null,
    });
  }
  return byId;
}

/**
 * Loads a sport's scores file into Map<game_id, row>, or returns
 * { skip: reason } when the sport has nothing comparable.
 */
function loadScores(sport, dataDir) {
  if (sport === 'nba' || sport === 'wnba') {
    const p = join(dataDir, 'matchups_slates.json');
    if (!existsSync(p)) return { skip: 'no data/matchups_slates.json' };
    const j = readJson(p);
    if (!Array.isArray(j.matchups)) return { skip: 'matchups_slates.json has no matchups[]' };
    return { file: 'matchups_slates.json', byId: rowsToIndex(j.matchups, 'game_id') };
  }
  if (sport === 'nfl') {
    const p = join(dataDir, 'matchups_current_week.json');
    if (!existsSync(p)) return { skip: 'no data/matchups_current_week.json' };
    const j = readJson(p);
    if (!Array.isArray(j.matchups)) return { skip: 'matchups_current_week.json has no matchups[]' };
    return { file: 'matchups_current_week.json', byId: rowsToIndex(j.matchups, 'game_id') };
  }
  if (sport === 'mlb') {
    // MLB's digest game_id is the MLB Stats API game_pk (tools/export_landing_digest.R).
    const dir = join(dataDir, 'matchups');
    const weeks = existsSync(dir) ? readdirSync(dir).filter((f) => /^week-\d+\.json$/.test(f)) : [];
    if (weeks.length === 0) return { skip: 'no data/matchups/week-*.json' };
    const rows = [];
    for (const f of weeks) {
      const j = readJson(join(dir, f));
      if (Array.isArray(j)) rows.push(...j);
    }
    return { file: 'matchups/week-*.json', byId: rowsToIndex(rows, 'game_pk') };
  }
  return { skip: 'no known scores file for this sport' };
}

function fmtScore(away, home) {
  return away === null || away === undefined || home === null || home === undefined ? 'no score' : `${away}-${home}`;
}

/** Returns { failures, warnings, lines, skipped } for one site root. */
export function checkSite(root, { warnOnly = WARN_ONLY } = {}) {
  const failures = [];
  const warnings = [];
  const lines = [];
  const skipped = [];
  for (const sport of SPORTS) {
    const dataDir = join(root, sport, 'data');
    const digestPath = join(dataDir, 'landing_digest.json');
    if (!existsSync(digestPath)) {
      lines.push(`>>> [SKIP] ${sport}: no data/landing_digest.json`);
      skipped.push(sport);
      continue;
    }
    const scores = loadScores(sport, dataDir);
    if (scores.skip) {
      lines.push(`>>> [SKIP] ${sport}: ${scores.skip}`);
      skipped.push(sport);
      continue;
    }
    const digest = readJson(digestPath);
    const yesterday = Array.isArray(digest.yesterday) ? digest.yesterday : [];
    let compared = 0;
    let notInScores = 0;
    let sportFails = 0;
    for (const g of yesterday) {
      const s = scores.byId.get(String(g.game_id));
      if (!s) { notInScores++; continue; }
      if (!s.completed || s.home_score === null || s.away_score === null) continue;
      compared++;
      const ok = g.status === 'final'
        && Number(g.home_score) === Number(s.home_score)
        && Number(g.away_score) === Number(s.away_score)
        && g.home_score !== null && g.away_score !== null;
      if (!ok) {
        sportFails++;
        const isWarnOnly = warnOnly.has(sport);
        const msg = `>>> [${isWarnOnly ? 'WARN' : 'FAIL'}] ${sport} game_id=${g.game_id} ${g.away ?? s.away} @ ${g.home ?? s.home}: `
          + `landing_digest status=${g.status} (${fmtScore(g.away_score, g.home_score)}), `
          + `${scores.file} is_completed=true (${fmtScore(s.away_score, s.home_score)})`;
        (isWarnOnly ? warnings : failures).push(msg);
        lines.push(msg);
      }
    }
    if (sportFails > 0 && warnOnly.has(sport)) {
      lines.push(`>>> [WARN] ${sport}: ${sportFails} mismatch(es) reported but not blocking -- ${sport} is warn-only (${warnOnly.get(sport)})`);
    }
    if (sportFails === 0) {
      lines.push(`>>> [OK] ${sport}: digest generated_at=${digest.generated_at ?? 'unknown'}, `
        + `${yesterday.length} game(s) in yesterday, ${compared} final in ${scores.file} and final in the digest`
        + (notInScores ? `, ${notInScores} not in ${scores.file}` : ''));
    }
  }
  return { failures, warnings, lines, skipped };
}

function main() {
  const root = process.argv[2];
  if (!root || !existsSync(root)) {
    console.error('usage: node tools/check_landing_freshness.mjs <site-root>');
    process.exit(2);
  }
  const { failures, warnings, lines } = checkSite(root);
  for (const l of lines) console.log(l);
  if (warnings.length) {
    console.log(`check_landing_freshness: ${warnings.length} warn-only mismatch(es) above did not block the deploy.`);
  }
  if (failures.length) {
    console.log('');
    console.log(`check_landing_freshness: FAILED -- ${failures.length} game(s) are final in a scores file but not in the landing digest.`);
    console.log('The landing page would show finished games as not final. The deploy is stopped, so the');
    console.log('site already live stays up. Re-run the sport\'s score refresh so it commits');
    console.log('web/public/data/landing_digest.json, then sync and deploy again.');
    process.exit(1);
  }
  console.log('check_landing_freshness: OK');
}

if (process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1])) main();
