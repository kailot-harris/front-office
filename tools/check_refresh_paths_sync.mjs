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
 * CHECK_REFRESH_PATHS_ROOT points the script at a scratch directory instead
 * of the repo root, so tests can exercise a real failure without touching the
 * subtree mirrors. CI never sets it.
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

export function compare(slot, workflowBySport) {
  const failures = [];
  for (const [sport, wf] of Object.entries(workflowBySport)) {
    const s = slot[sport];
    if (!s) {
      failures.push(`${sport}: has ${WORKFLOW} but no entry in $SPORT_REFRESH`);
      continue;
    }
    const missing = uncovered(wf, s);
    const extra = uncovered(s, wf);
    if (missing.length) failures.push(`${sport}: ${SLOT_SCRIPT} does not stage ${missing.join(', ')} (staged by ${sport}/${WORKFLOW})`);
    if (extra.length) failures.push(`${sport}: ${SLOT_SCRIPT} stages ${extra.join(', ')}, which ${sport}/${WORKFLOW} does not`);
  }
  for (const sport of Object.keys(slot)) {
    if (!workflowBySport[sport]) failures.push(`${sport}: in $SPORT_REFRESH but ${sport}/${WORKFLOW} has no git add paths`);
  }
  return failures;
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

  const failures = compare(slot, workflowBySport);
  if (failures.length) {
    console.error('check_refresh_paths_sync: FAILED -- slot refresh and sport refresh workflows stage different files:');
    for (const f of failures) console.error(`  - ${f}`);
    console.error('');
    console.error(`Make the Paths in ${SLOT_SCRIPT} ($SPORT_REFRESH) match the "git add" in each`);
    console.error(`sport's ${WORKFLOW}, or the slot run writes files it never commits.`);
    process.exit(1);
  }
  console.log(`check_refresh_paths_sync: OK -- ${Object.keys(workflowBySport).sort().join(', ')} stage the same files in both places`);
}

if (process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1])) main();
