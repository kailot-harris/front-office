#!/usr/bin/env node
/**
 * Drift check for the "agreed shared files" (front-office issue #130).
 *
 * Of 95 component/lib files across the four sport repos, 47 exist in more
 * than one sport with different contents and only three are byte-identical
 * (apart from the sport name itself): web/lib/exportSvgAsPng.ts,
 * web/lib/exportToCsv.ts, and web/lib/basePath.ts. This script is the
 * low-risk first step named in that issue: it does NOT attempt a merge, it
 * only keeps those three files from silently drifting apart again now that
 * they're known to agree.
 *
 * Reads each file ONLY from this repo's read-only subtree mirrors
 * (mlb/, nba/, nfl/, wnba/ at the repo root) -- never writes there, since
 * those directories are overwritten by the next `git subtree pull`.
 *
 * "Identical apart from the sport name" (per the issue text) means each
 * file may legitimately differ only in the literal sport token (MLB/NBA/
 * NFL/WNBA in any of their casings: upper, lower, or capitalized). Every
 * other difference is real drift and fails the check.
 *
 * Usage:
 *   node tools/check_shared_file_drift.mjs
 *
 * Exit code is non-zero, with the diverged file/sport pairs named on
 * stderr-equivalent (stdout; this is a CI script, not a stderr-discipline
 * one), if any shared file has diverged between any two sports.
 */

import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
// CHECK_DRIFT_ROOT lets a test point this script at a scratch directory
// instead of the real repo root, so the "does it actually fail on a real
// divergence" check can be exercised WITHOUT ever writing into mlb/, nba/,
// nfl/, or wnba/ -- those are read-only subtree mirrors overwritten by the
// next `git subtree pull` (see README's subtree-sync notes). CI and normal
// local runs never set this, so they always check the real mirrors.
const REPO_ROOT = process.env.CHECK_DRIFT_ROOT
  ? process.env.CHECK_DRIFT_ROOT
  : join(__dirname, '..');

// The sports whose subtree mirrors live at the repo root, and the "agreed
// shared files" list from issue #130. Start small and only add a file here
// once it's actually confirmed byte-identical (apart from sport name) across
// every sport that has it -- this list is a promise being enforced, not an
// aspiration.
const SPORTS = ['mlb', 'nba', 'nfl', 'wnba'];
const SHARED_FILES = [
  'web/lib/exportSvgAsPng.ts',
  'web/lib/exportToCsv.ts',
  'web/lib/basePath.ts',
];

// Replaces every casing of each sport's name with a single placeholder, so
// two files that differ ONLY in which sport they belong to (e.g.
// `/mlb` vs `/nba` in basePath.ts, or "MLB"/"NBA" in a comment) compare as
// equal. Order matters: longest tokens first so e.g. "WNBA" doesn't partially
// match as containing no shorter token by accident (none currently do, but
// this keeps it safe if that changes).
const SPORT_TOKEN_PATTERN = new RegExp(
  ['WNBA', 'MLB', 'NBA', 'NFL', 'wnba', 'mlb', 'nba', 'nfl', 'Wnba', 'Mlb', 'Nba', 'Nfl'].join('|'),
  'g'
);

function normalize(contents) {
  return contents.replace(SPORT_TOKEN_PATTERN, '<SPORT>');
}

function main() {
  const failures = [];
  let comparedAnyPair = false;

  for (const relPath of SHARED_FILES) {
    /** @type {{sport: string, raw: string, normalized: string}[]} */
    const present = [];

    for (const sport of SPORTS) {
      const absPath = join(REPO_ROOT, sport, relPath);
      if (!existsSync(absPath)) continue;
      const raw = readFileSync(absPath, 'utf8');
      present.push({ sport, raw, normalized: normalize(raw) });
    }

    if (present.length < 2) {
      console.log(`[skip] ${relPath}: present in fewer than 2 sports (${present.map((p) => p.sport).join(', ') || 'none'})`);
      continue;
    }

    const reference = present[0];
    for (let i = 1; i < present.length; i++) {
      comparedAnyPair = true;
      const other = present[i];
      if (other.normalized !== reference.normalized) {
        failures.push({
          file: relPath,
          sportA: reference.sport,
          sportB: other.sport,
        });
      }
    }
  }

  if (!comparedAnyPair) {
    console.error('check_shared_file_drift: no comparable pair found for any shared file -- check SHARED_FILES/SPORTS lists');
    process.exit(1);
  }

  if (failures.length > 0) {
    console.error('check_shared_file_drift: FAILED -- shared files have diverged:');
    for (const f of failures) {
      console.error(`  - ${f.file}: ${f.sportA} and ${f.sportB} differ (beyond sport-name substitution)`);
    }
    console.error('');
    console.error('These files are listed in tools/check_shared_file_drift.mjs as "agreed shared files"');
    console.error('(byte-identical apart from sport name, per front-office issue #130). Either make');
    console.error('the copies agree again in each sport repo, or remove the file from SHARED_FILES if');
    console.error('it is no longer meant to be kept in sync.');
    process.exit(1);
  }

  console.log(`check_shared_file_drift: OK -- ${SHARED_FILES.length} shared file(s) agree across all sports that have them`);
}

main();
