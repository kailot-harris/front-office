#!/usr/bin/env node
/**
 * predeploy_gate.mjs
 *
 * CI-runnable pre-publish gate for deploy.yml (#98, part of #94 Phase 3.2).
 *
 * This is a deliberately lightweight, repo-local stand-in for the full
 * local-machine auditor at
 * `.agents/skills/front-office-audit/scripts/audit_site.mjs`. That script
 * lives one directory ABOVE this repo, in an untracked tooling directory on
 * a single developer's machine — it is not vendored into any git repo, so a
 * GitHub Actions runner (a fresh, isolated VM with no access to this
 * machine's filesystem) cannot reach it, clone it, or run it. Rather than
 * invent a way to ship that script to CI (there isn't a safe one — it would
 * mean either checking a local path into the workflow, which fails on every
 * runner, or standing up some new distribution channel, which is out of
 * scope for this issue), this script reimplements the two checks #98 calls
 * out as HARD gates using only what the aggregator repo already has
 * checked out in CI: the four vendored sport subtrees (mlb/, nba/, nfl/,
 * wnba/) produced by sync-sports.yml's `git subtree pull`.
 *
 * Hard gates (exit 1 blocks deploy):
 *   1. Uncommitted drift: `git status --porcelain` is non-empty anywhere in
 *      the checked-out tree after the sync/checkout step. On a clean deploy
 *      (the only path deploy.yml runs today) this is always empty, so the
 *      happy path is unaffected.
 *   2. Synthetic-data flags: scans for an explicit, opt-in marker,
 *      `SYNTHETIC-DATA-FLAG` (case-insensitive), in tracked files under the
 *      four sport subtrees and the aggregator's own source. NOTE: as of
 *      #98 there is no established, repo-wide convention for marking
 *      fabricated/synthetic data (see issue #98 and the `synthetic-data`
 *      GitHub label, which tracks issues, not a file-level marker). This
 *      check is intentionally a hook for a marker that does not exist yet
 *      in code today — it will simply find nothing until a convention is
 *      defined and adopted (tracked separately). It is included now, as a
 *      hard gate, so that landing a convention later requires zero workflow
 *      changes — just start writing the marker.
 *
 * Warn-only (never fails the build):
 *   - Accessibility findings are explicitly out of scope here per #98's
 *     acceptance criteria ("should not block on accessibility findings from
 *     #96 initially"). This script does not run any a11y checks at all; if
 *     #96 lands an a11y job, wire its output as a separate, non-blocking
 *     step/annotation rather than adding it here.
 *
 * Usage: node scripts/predeploy_gate.mjs
 * Exit code 0 = clear to deploy. Exit code 1 = blocked, see stdout for why.
 */

import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT_DIR = process.cwd();
const SPORT_DIRS = ['mlb', 'nba', 'nfl', 'wnba'];
const SYNTHETIC_FLAG_PATTERN = /SYNTHETIC-DATA-FLAG/i;
// Keep this scan cheap and signal-only: text-ish source files, skip the
// usual noise directories so a huge node_modules/out/.next tree doesn't
// make every CI run slow.
const SCAN_EXTENSIONS = new Set(['.R', '.ts', '.tsx', '.js', '.jsx', '.mjs', '.md', '.json']);
const SKIP_DIR_NAMES = new Set(['node_modules', '.git', '.next', 'out', 'renv', '.venv', 'dist', 'build']);

function run(cmd, cwd = ROOT_DIR) {
  try {
    return execSync(cmd, { cwd, encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'] });
  } catch (err) {
    // git status/log should not normally throw; surface stderr if it does.
    return (err.stdout ? err.stdout.toString() : '') + (err.stderr ? err.stderr.toString() : '');
  }
}

function checkUncommittedDrift() {
  const findings = [];

  // Whole-tree check: catches drift anywhere, including the aggregator's
  // own files, not just the sport subtrees.
  const porcelain = run('git status --porcelain').trim();
  if (porcelain) {
    const lines = porcelain.split('\n').filter(Boolean);
    findings.push({
      scope: 'repo root',
      files: lines,
    });
  }

  return findings;
}

function walk(dir, visit) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    if (SKIP_DIR_NAMES.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, visit);
    } else if (entry.isFile()) {
      visit(full);
    }
  }
}

function checkSyntheticDataFlags() {
  const flagged = [];
  const scanRoots = [...SPORT_DIRS.map((d) => path.join(ROOT_DIR, d)), ROOT_DIR];
  const seen = new Set();

  for (const root of scanRoots) {
    if (!fs.existsSync(root)) continue;
    walk(root, (filePath) => {
      if (seen.has(filePath)) return;
      const ext = path.extname(filePath);
      if (!SCAN_EXTENSIONS.has(ext)) return;
      // Don't scan this gate script itself (it legitimately mentions the
      // marker string in comments above) or any file under scripts/.
      if (filePath.includes(`${path.sep}scripts${path.sep}`)) return;
      seen.add(filePath);

      let content;
      try {
        content = fs.readFileSync(filePath, 'utf-8');
      } catch {
        return;
      }
      if (SYNTHETIC_FLAG_PATTERN.test(content)) {
        flagged.push(path.relative(ROOT_DIR, filePath));
      }
    });
  }

  return flagged;
}

function main() {
  console.log('=== Pre-publish gate (#98) ===');
  console.log('Hard gates: uncommitted drift, synthetic-data flags.');
  console.log('Warn-only: accessibility (not run by this script; see #96).');
  console.log('');

  let blocked = false;

  // --- Gate 1: uncommitted drift -------------------------------------
  const drift = checkUncommittedDrift();
  if (drift.length > 0) {
    blocked = true;
    console.log('BLOCKED: uncommitted drift detected.');
    for (const d of drift) {
      console.log(`  scope: ${d.scope}`);
      for (const f of d.files.slice(0, 20)) {
        console.log(`    ${f}`);
      }
      if (d.files.length > 20) {
        console.log(`    ... and ${d.files.length - 20} more`);
      }
    }
  } else {
    console.log('OK: no uncommitted drift.');
  }

  // --- Gate 2: synthetic-data flags -----------------------------------
  const flags = checkSyntheticDataFlags();
  if (flags.length > 0) {
    blocked = true;
    console.log('BLOCKED: synthetic-data flag(s) found in tracked source:');
    for (const f of flags.slice(0, 20)) {
      console.log(`  ${f}`);
    }
    if (flags.length > 20) {
      console.log(`  ... and ${flags.length - 20} more`);
    }
  } else {
    console.log('OK: no synthetic-data flags found.');
  }

  console.log('');
  if (blocked) {
    console.log('Result: BLOCKED — deploy will not proceed.');
    process.exitCode = 1;
  } else {
    console.log('Result: CLEAR — proceeding to publish.');
    process.exitCode = 0;
  }
}

main();
