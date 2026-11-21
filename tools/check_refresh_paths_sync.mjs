#!/usr/bin/env node
/**
 * Keeps the slot B/C score refresh staging the same files as each sport's own
 * refresh workflow.
 *
 * tools/run_refresh_slot.ps1 runs each sport's tools/refresh_live_results.R in
 * a scratch worktree and stages ONLY the files listed in that sport's `Paths`
 * entry of $SPORT_REFRESH. Each sport's .github/workflows/refresh-results.yml
 * does the same job on a hosted runner and stages its own list with `git add`.
 * The two lists are meant to be identical, and nothing enforced it: when the
 * NBA refresh started re-grading web/public/data/landing_digest.json (NBA#211)
 * the workflow's `git add` gained the digest but the slot script's Paths did
 * not, so every slot run wrote the patched digest and never committed it. On
 * 2026-11-21 the landing page showed all nine of the previous night's NBA
 * games as not final while the scores file had them final.
 *
 * This script parses both lists and fails, naming the sport and the missing
 * or extra paths, if they differ. A directory path (MLB stages the whole
 * web/public/data) covers every file under it, in either direction, so a
 * file listed on one side matches a directory that contains it on the other.
 *
 * Reads the workflow from this repo's read-only subtree mirrors
 * (mlb/, nba/, nfl/, wnba/ at the repo root) and never writes there.
 *
 * Usage:
 *   node tools/check_refresh_paths_sync.mjs
 *
 * KNOWN EXCEPTIONS. A gap the owner has decided to keep goes in
 * tools/refresh_paths_allowlist.json as { sport, path, direction, reason }.
 * It is printed as a `>>> [SKIP] known exception` line instead of failing.
 * An entry that no longer matches a real gap fails the check, so it gets
 * removed once the lists agree. As of 2026-11-21 the one entry is NFL's
 * landing_digest.json, held by the owner pending NFL work.
 *
 * CHECK_REFRESH_PATHS_ROOT points the script at a scratch directory instead
 * of the repo root, so tests can exercise a real failure without touching the
 * subtree mirrors. CHECK_REFRESH_PATHS_ALLOWLIST overrides the allowlist path
 * (default: <root>/tools/refresh_paths_allowlist.json; a missing file means no
 * exceptions). CI sets neither.
 */

import { readFileSync, existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = process.env.CHECK_REFRESH_PATHS_ROOT
  ? process.env.CHECK_REFRESH_PATHS_ROOT
  : join(__dirname, '..');

const SPORTS = ['mlb', 'nba', 'nfl', 'wnba'];
const SLOT_SCRIPT = 'tools/run_refresh_slot.ps1';
const WORKFLOW = '.github/workflows/refresh-results.yml';
const ALLOWLIST = 'tools/refresh_paths_allowlist.json';

/**
 * Parses `$SPORT_REFRESH = [ordered]@{ ... }` into { sport: [paths] }.
 * Each sport is one line of the form
 *   nba = @{ Dir = '...'; Args = @(...); Paths = @('a', 'b') }
 */
export function parseSlotPaths(ps1) {
  const block = ps1.match(/\$SPORT_REFRESH\s*=\s*\[ordered\]@\{([\s\S]*?)\n\}/);
  if (!block) return null;
  const out = {};
  for (const line of block[1].split('\n')) {
    const m = line.match(/^\s*([a-z]+)\s*=\s*@\{.*\bPaths\s*=\s*@\(([^)]*)\)/);
    if (!m) continue;
    out[m[1]] = [...m[2].matchAll(/'([^']*)'|"([^"]*)"/g)].map((x) => x[1] ?? x[2]);
  }
  return out;
}

/** Collects every path passed to `git add` in a workflow file. */
export function parseWorkflowAddPaths(yml) {
  const paths = [];
  for (const line of yml.split('\n')) {
    const m = line.match(/^\s*git\s+add\s+(.+?)\s*$/);
    if (!m) continue;
    for (const tok of m[1].split(/\s+/)) {
      if (!tok || tok === '--' || tok.startsWith('-')) continue;
      paths.push(tok.replace(/^['"]|['"]$/g, '').replace(/\/+$/, ''));
    }
  }
  return paths;
}

function covers(dirOrFile, path) {
  return path === dirOrFile || path.startsWith(`${dirOrFile}/`);
}


/** Paths in `a` that no entry of `b` covers. */
function uncovered(a, b) {
  return a.filter((p) => !b.some((q) => covers(q, p) || covers(p, q)));
}

/**
 * Returns every gap as { sport, path, direction } plus problems that are not
 * per-path (a sport present on only one side).
 */
export function findGaps(slot, workflowBySport) {
  const gaps = [];
  const problems = [];
  for (const [sport, wf] of Object.entries(workflowBySport)) {
    const s = slot[sport];
    if (!s) {
      problems.push(`${sport}: has ${WORKFLOW} but no entry in $SPORT_REFRESH`);
      continue;
    }
    for (const path of uncovered(wf, s)) gaps.push({ sport, path, direction: 'missing_from_slot' });
    for (const path of uncovered(s, wf)) gaps.push({ sport, path, direction: 'extra_in_slot' });
  }
  for (const sport of Object.keys(slot)) {
    if (!workflowBySport[sport]) problems.push(`${sport}: in $SPORT_REFRESH but ${sport}/${WORKFLOW} has no git add paths`);
  }
  return { gaps, problems };
}

function describe(g) {
  return g.direction === 'missing_from_slot'
    ? `${g.sport}: ${SLOT_SCRIPT} does not stage ${g.path} (staged by ${g.sport}/${WORKFLOW})`
    : `${g.sport}: ${SLOT_SCRIPT} stages ${g.path}, which ${g.sport}/${WORKFLOW} does not`;
}

const keyOf = (e) => `${e.sport}\u0000${e.path}\u0000${e.direction}`;

function loadAllowlist() {
  const p = process.env.CHECK_REFRESH_PATHS_ALLOWLIST || join(REPO_ROOT, ALLOWLIST);
  if (!existsSync(p)) return [];
  const parsed = JSON.parse(readFileSync(p, 'utf8'));
  if (!Array.isArray(parsed.entries)) throw new Error(`${ALLOWLIST} must contain an 'entries' array`);
  for (const e of parsed.entries) {
    if (!e.sport || !e.path || !['missing_from_slot', 'extra_in_slot'].includes(e.direction) || !e.reason) {
      throw new Error(`${ALLOWLIST}: every entry needs sport, path, direction (missing_from_slot|extra_in_slot) and reason`);
    }
  }
  return parsed.entries;
}

function main() {
  const ps1Path = join(REPO_ROOT, SLOT_SCRIPT);
  if (!existsSync(ps1Path)) {
    console.error(`check_refresh_paths_sync: FAILED -- ${SLOT_SCRIPT} not found`);
    process.exit(1);
  }
  const slot = parseSlotPaths(readFileSync(ps1Path, 'utf8'));
  if (!slot || Object.keys(slot).length === 0) {
    console.error(`check_refresh_paths_sync: FAILED -- could not parse $SPORT_REFRESH Paths in ${SLOT_SCRIPT}`);
    process.exit(1);
  }

  const workflowBySport = {};
  for (const sport of SPORTS) {
    const p = join(REPO_ROOT, sport, WORKFLOW);
    if (!existsSync(p)) {
      console.log(`[skip] ${sport}: no ${sport}/${WORKFLOW}`);
      continue;
    }
    const paths = parseWorkflowAddPaths(readFileSync(p, 'utf8'));
    if (paths.length) workflowBySport[sport] = paths;
  }

  const allowlist = loadAllowlist();
  const { gaps, problems } = findGaps(slot, workflowBySport);
  const gapKeys = new Set(gaps.map(keyOf));
  const allowKeys = new Set(allowlist.map(keyOf));

  for (const e of allowlist.filter((x) => gapKeys.has(keyOf(x)))) {
    console.log(`>>> [SKIP] known exception -- ${describe(e)}: ${e.reason}`);
  }
  const failures = [
    ...problems,
    ...gaps.filter((g) => !allowKeys.has(keyOf(g))).map(describe),
    ...allowlist.filter((e) => !gapKeys.has(keyOf(e))).map((e) =>
      `STALE exception in ${ALLOWLIST}: ${e.sport} ${e.direction} ${e.path} is no longer a gap; remove the entry`),
  ];

  if (failures.length) {
    console.error('check_refresh_paths_sync: FAILED -- slot refresh and sport refresh workflows stage different files:');
    for (const f of failures) console.error(`  - ${f}`);
    console.error('');
    console.error(`Make the Paths in ${SLOT_SCRIPT} ($SPORT_REFRESH) match the "git add" in each`);
    console.error(`sport's ${WORKFLOW}, or the slot run writes files it never commits. A gap the`);
    console.error(`owner has decided to keep goes in ${ALLOWLIST} with a reason.`);
    process.exit(1);
  }
  const held = allowlist.length ? ` (${allowlist.length} known exception(s) in ${ALLOWLIST})` : '';
  console.log(`check_refresh_paths_sync: OK -- ${Object.keys(workflowBySport).sort().join(', ')} checked, no unexpected gaps${held}`);
}

if (process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1])) main();
