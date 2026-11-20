#!/usr/bin/env node
/**
 * Unit tests for tools/check_r_offline_imports.mjs.
 *
 * Plain Node (`node:assert/strict`) with isolated temp directories; the sport
 * subtrees (mlb/, nba/, nfl/, wnba/) are never modified.
 *
 * Usage:
 *   node tools/test_check_r_offline_imports.mjs
 */

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const GUARD = join(__dirname, 'check_r_offline_imports.mjs');

function runGuard(env = {}) {
  const res = spawnSync(process.execPath, [GUARD], {
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
  return { status: res.status, out: `${res.stdout}${res.stderr}` };
}

function withWorkspace(files, entries, fn) {
  const root = mkdtempSync(join(tmpdir(), 'fo-r-offline-guard-'));
  try {
    for (const [rel, content] of Object.entries(files)) {
      const p = join(root, rel);
      mkdirSync(dirname(p), { recursive: true });
      writeFileSync(p, content);
    }
    const allow = join(root, 'allowlist.json');
    writeFileSync(allow, JSON.stringify({ schema_version: '1.0', entries }, null, 2));
    return fn(runGuard({ OFFLINE_R_GUARD_ROOT: root, OFFLINE_R_GUARD_ALLOWLIST: allow }));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const tests = [];
const test = (name, fn) => tests.push({ name, fn });

test('current repository passes with seeded allow-list', () => {
  const r = runGuard({ OFFLINE_R_GUARD_ROOT: '', OFFLINE_R_GUARD_ALLOWLIST: '' });
  assert.equal(r.status, 0, r.out);
  assert.match(r.out, /0 violations, 0 stale/);
});

test('fails on un-allowlisted library(hoopR)', () => {
  withWorkspace({ 'nba/x.R': 'x <- 1\nlibrary(hoopR)\n' }, [], (r) => {
    assert.equal(r.status, 1, r.out);
    assert.match(r.out, /nba\/x\.R:2 library\(hoopR\)/);
  });
});

test('fails on un-allowlisted require("nflreadr")', () => {
  withWorkspace({ 'nfl/y.R': 'require("nflreadr")\n' }, [], (r) => {
    assert.equal(r.status, 1, r.out);
    assert.match(r.out, /nfl\/y\.R:1 require\(nflreadr\)/);
  });
});

test('allow-listed hit passes', () => {
  withWorkspace(
    { 'wnba/z.R': 'suppressPackageStartupMessages({\n  library(wehoop)\n})\n' },
    [{ file: 'wnba/z.R', line: 2, package: 'wehoop', reason: 'reviewed legacy import' }],
    (r) => assert.equal(r.status, 0, r.out)
  );
});

test('lazy requireNamespace("hoopR") and non-heavy packages are allowed', () => {
  const src = [
    'if (!requireNamespace("hoopR", quietly = TRUE)) stop("need hoopR")',
    'library(dplyr)',
    'x <- hoopR::load_nba_pbp(2025)',
  ].join('\n');
  withWorkspace({ 'nba/lazy.R': src }, [], (r) => assert.equal(r.status, 0, r.out));
});

test('ignores library() inside # comments and string literals', () => {
  const src = [
    '# library(hoopR)',
    'x <- 1 # require(nflreadr)',
    'msg <- "run library(baseballr) first # not a comment"',
    "y <- 'library(wehoop)'",
  ].join('\n');
  withWorkspace({ 'mlb/c.R': src }, [], (r) => assert.equal(r.status, 0, r.out));
});

test('fails on stale allow-list entry', () => {
  withWorkspace(
    { 'nba/migrated.R': 'requireNamespace("hoopR", quietly = TRUE)\n' },
    [{ file: 'nba/migrated.R', line: 1, package: 'hoopR', reason: 'was library(hoopR) before migration' }],
    (r) => {
      assert.equal(r.status, 1, r.out);
      assert.match(r.out, /STALE allow-list entry nba\/migrated\.R:1/);
    }
  );
});

test('skips tests/, archive/, renv/ directories', () => {
  withWorkspace(
    {
      'nba/tests/t.R': 'library(hoopR)\n',
      'nfl/archive/old.R': 'library(nflfastR)\n',
      'mlb/renv/lib.R': 'library(baseballr)\n',
      'wnba/ok.R': 'x <- 1\n',
    },
    [],
    (r) => assert.equal(r.status, 0, r.out)
  );
});

let failed = 0;
for (const { name, fn } of tests) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    failed += 1;
    console.error(`not ok - ${name}\n  ${err.message}`);
  }
}
console.log(`${tests.length - failed}/${tests.length} tests passed`);
process.exit(failed > 0 ? 1 : 0);
