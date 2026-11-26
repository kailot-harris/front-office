#!/usr/bin/env node
/**
 * Game-end watcher (front-office#240).
 *
 * Reads each watched sport's live landing digest and looks for games that should
 * have ended by now but are not final. For each sport with such games it
 * dispatches that sport repo's refresh-results.yml, waits for the run, and
 * checks whether the sport repo's main branch moved. If any sport's main moved,
 * it dispatches this repo's sync-sports.yml once for those sports; that
 * workflow pulls the subtrees and dispatches deploy.yml when it commits.
 *
 * Tokens (read from the environment):
 *   SUBTREE_TOKEN  calls to the sport repos (needs Actions read/write and
 *                  Contents read on each sport repo)
 *   GITHUB_TOKEN   the sync-sports.yml dispatch on this repo
 * Every call goes through the `gh` CLI.
 *
 * Usage:
 *   node tools/game_end_watch.mjs            # select, dispatch, wait, sync
 *   node tools/game_end_watch.mjs --dry-run  # select and print only
 */

import { execFile } from 'node:child_process';
import { pathToFileURL } from 'node:url';

// Watched sports and expected game length, start to final, in minutes.
// MLB is not watched: its landing digest is built differently (MLB's own
// refresh path patches finished scores), so this game-length rule does not fit.
export const WATCHED_SPORTS = {
  nba: { minutes: 165, repo: 'kailot-harris/NBA_analytics' },
  nfl: { minutes: 210, repo: 'kailot-harris/NFL_analytics' },
  wnba: { minutes: 150, repo: 'kailot-harris/WNBA_analytics' },
};

// Stop retrying a game this long after its expected end; the scheduled refresh
// slots remain the backstop for a game that never goes final.
export const RETRY_CAP_MS = 6 * 60 * 60 * 1000;
export const RUN_WAIT_CAP_MS = 20 * 60 * 1000;
export const REFRESH_WORKFLOW = 'refresh-results.yml';
export const SYNC_WORKFLOW = 'sync-sports.yml';
export const DIGEST_URL = (sport) =>
  `https://kailot-harris.github.io/front-office/${sport}/data/landing_digest.json`;

// ---- pure helpers -----------------------------------------------------------

export function isPostponedOrCancelled(row) {
  const s = String(row.status || '').toLowerCase();
  return s.includes('postpon') || s.includes('cancel');
}

// New-shape rows carry `final`. Old-shape rows (no `final` field) count as final
// only when their status says so.
export function isFinal(row) {
  if (row.final === true) return true;
  if (row.final === undefined) return String(row.status || '').toLowerCase().includes('final');
  return false;
}

/**
 * Games in a digest's `today` and `yesterday` lists that should have ended but
 * are not final. Pure: `now` is a Date or epoch milliseconds.
 * Returns [] for a sport that is not watched (MLB included).
 */
export function selectCandidates(sport, digest, now) {
  const cfg = WATCHED_SPORTS[sport];
  if (!cfg || !digest) return [];
  const nowMs = now instanceof Date ? now.getTime() : Number(now);
  const lengthMs = cfg.minutes * 60 * 1000;
  const seen = new Set();
  const out = [];
  for (const list of ['today', 'yesterday']) {
    const rows = Array.isArray(digest[list]) ? digest[list] : [];
    for (const row of rows) {
      if (!row || isFinal(row) || isPostponedOrCancelled(row)) continue;
      const start = Date.parse(row.start_time_utc);
      if (!row.start_time_utc || Number.isNaN(start)) continue;
      const end = start + lengthMs;
      if (nowMs < end || nowMs > end + RETRY_CAP_MS) continue;
      const key = row.game_id != null ? String(row.game_id) : `${row.away}@${row.home}@${row.start_time_utc}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ list, game_id: row.game_id, away: row.away, home: row.home, start_time_utc: row.start_time_utc });
    }
  }
  return out;
}

/** Newest workflow_dispatch run created at or after `sinceMs`, or null. */
export function pickDispatchedRun(runs, sinceMs) {
  const since = Math.floor(sinceMs / 1000) * 1000; // created_at has second resolution
  let best = null;
  for (const r of runs || []) {
    if (r.event !== 'workflow_dispatch') continue;
    const t = Date.parse(r.created_at);
    if (Number.isNaN(t) || t < since) continue;
    if (!best || t > Date.parse(best.created_at)) best = r;
  }
  return best;
}

/** True when a gh failure message is an HTTP 403 or 404. */
export function isAccessError(message) {
  return /HTTP 40[34]\b/.test(String(message || ''));
}

function describe(c) {
  return `${c.away} at ${c.home} (${c.list}, start ${c.start_time_utc})`;
}

// ---- gh / network -----------------------------------------------------------

class AccessError extends Error {}

function gh(args, token) {
  return new Promise((resolve, reject) => {
    const env = { ...process.env };
    if (token) env.GH_TOKEN = token;
    execFile('gh', args, { env, maxBuffer: 16 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (!err) return resolve(stdout.trim());
      const msg = `${stderr || ''} ${err.message || ''}`.trim();
      if (isAccessError(msg)) return reject(new AccessError(msg));
      reject(new Error(msg));
    });
  });
}

function accessHint(repo) {
  return `the token in SUBTREE_TOKEN likely lacks Actions read/write on ${repo} ` +
    '(a fine-grained token whose repository set excludes it returns 404)';
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchDigest(sport) {
  const res = await fetch(`${DIGEST_URL(sport)}?t=${Date.now()}`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function headSha(repo, token) {
  return gh(['api', `repos/${repo}/commits/main`, '--jq', '.sha'], token);
}

async function refreshSport(sport, token, log) {
  const { repo } = WATCHED_SPORTS[sport];
  const before = await headSha(repo, token);
  const since = Date.now();
  await gh(['workflow', 'run', REFRESH_WORKFLOW, '--repo', repo, '--ref', 'main'], token);
  log(`${sport}: dispatched ${REFRESH_WORKFLOW} on ${repo}`);

  const deadline = since + RUN_WAIT_CAP_MS;
  let run = null;
  while (Date.now() < deadline) {
    await sleep(run ? 30000 : 10000);
    const out = await gh(['api',
      `repos/${repo}/actions/workflows/${REFRESH_WORKFLOW}/runs?event=workflow_dispatch&branch=main&per_page=20`,
      '--jq', '.workflow_runs'], token);
    const found = pickDispatchedRun(JSON.parse(out || '[]'), since);
    if (found) run = found;
    if (run && run.status === 'completed') break;
  }
  const after = await headSha(repo, token);
  return {
    runFound: !!run,
    completed: !!run && run.status === 'completed',
    conclusion: run ? run.conclusion : null,
    url: run ? run.html_url : null,
    changed: before !== after,
  };
}

// ---- main -------------------------------------------------------------------

export async function main(argv = process.argv.slice(2)) {
  const dryRun = argv.includes('--dry-run');
  const now = new Date();
  const log = (s) => console.log(s);
  const subtreeToken = process.env.SUBTREE_TOKEN || '';
  const repoToken = process.env.GITHUB_TOKEN || '';
  let failed = false;

  log(`game_end_watch: ${dryRun ? 'dry run, ' : ''}now ${now.toISOString()}`);

  const selections = await Promise.all(Object.keys(WATCHED_SPORTS).map(async (sport) => {
    try {
      return { sport, candidates: selectCandidates(sport, await fetchDigest(sport), now) };
    } catch (err) {
      return { sport, error: `could not fetch the landing digest (${err.message})` };
    }
  }));

  if (dryRun) {
    let total = 0;
    for (const s of selections) {
      if (s.error) { log(`${s.sport}: ${s.error}; would dispatch nothing`); continue; }
      total += s.candidates.length;
      log(s.candidates.length
        ? `${s.sport}: ${s.candidates.length} candidate(s): ${s.candidates.map(describe).join('; ')}; ` +
          `would dispatch ${REFRESH_WORKFLOW} on ${WATCHED_SPORTS[s.sport].repo}`
        : `${s.sport}: 0 candidates; would dispatch nothing`);
    }
    log(total
      ? `sync: would dispatch ${SYNC_WORKFLOW} for the sports whose main moved after the refresh`
      : 'sync: no candidates, would dispatch nothing');
    log(`game_end_watch: dry run done, ${total} candidate(s), nothing dispatched`);
    return 0;
  }

  if (selections.some((s) => s.candidates && s.candidates.length) && !subtreeToken) {
    console.error('game_end_watch: SUBTREE_TOKEN is not set; cannot dispatch to the sport repos');
    return 1;
  }

  const results = await Promise.all(selections.map(async (s) => {
    if (s.error) return { sport: s.sport, summary: `${s.sport}: ${s.error}; dispatched nothing` };
    if (!s.candidates.length) return { sport: s.sport, summary: `${s.sport}: 0 candidates; dispatched nothing` };
    const found = `${s.candidates.length} candidate(s): ${s.candidates.map(describe).join('; ')}`;
    const repo = WATCHED_SPORTS[s.sport].repo;
    try {
      const r = await refreshSport(s.sport, subtreeToken, log);
      let what;
      if (!r.runFound) what = `dispatched ${REFRESH_WORKFLOW} but could not find its run within 20 minutes`;
      else if (!r.completed) what = `${REFRESH_WORKFLOW} did not finish within 20 minutes (${r.url})`;
      else what = `${REFRESH_WORKFLOW} finished: ${r.conclusion} (${r.url})`;
      if (!r.completed || r.conclusion !== 'success') failed = true;
      return { sport: s.sport, changed: r.changed,
        summary: `${s.sport}: ${found}; ${what}; main ${r.changed ? 'moved' : 'unchanged'}` };
    } catch (err) {
      failed = true;
      const why = err instanceof AccessError
        ? `ERROR: GitHub returned 403/404 for ${repo}: ${accessHint(repo)}`
        : `ERROR: ${err.message}`;
      return { sport: s.sport, summary: `${s.sport}: ${found}; ${why}` };
    }
  }));
  for (const r of results) log(r.summary);

  const changed = results.filter((r) => r.changed).map((r) => r.sport);
  if (changed.length) {
    const repo = process.env.GITHUB_REPOSITORY || 'kailot-harris/front-office';
    try {
      await gh(['workflow', 'run', SYNC_WORKFLOW, '--repo', repo, '--ref', 'main',
        '-f', `sports=${changed.join(' ')}`], repoToken || undefined);
      log(`sync: dispatched ${SYNC_WORKFLOW} on ${repo} with sports="${changed.join(' ')}"`);
    } catch (err) {
      failed = true;
      console.error(`sync: ERROR dispatching ${SYNC_WORKFLOW}: ${err.message}`);
    }
  } else {
    log('sync: no sport repo moved, dispatched nothing');
  }
  return failed ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().then((code) => { process.exitCode = code; }, (err) => {
    console.error(`game_end_watch: ${err.stack || err}`);
    process.exitCode = 1;
  });
}
