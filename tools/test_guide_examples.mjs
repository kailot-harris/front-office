// Contract tests for the live examples on /how-it-works/ (front-office#218) and the shared
// staleness module they use with the landing digest (assets/landing/staleness.js).
//   node --test tools/test_guide_examples.mjs
// Real payloads come from the read-only sport subtree mirrors (<sport>/web/public/data).
// Manifests and digests are small inline fixtures, so the fresh/stale/offseason cases are fixed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, mkdtempSync, writeFileSync, mkdirSync, cpSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const S = require('../assets/landing/staleness.js');
const X = require('../assets/guide/examples.js');
const D = require('../assets/landing/digest.js');
const { check: checkHeader } = await import('./check_site_header_drift.mjs');

const dataPath = (lg, f) => join(ROOT, lg, 'web', 'public', 'data', f);
const real = (lg, f) => JSON.parse(readFileSync(dataPath(lg, f), 'utf8'));

const SCHED = '2026-11-20';
const manifest = (file, entry) => ({ schedule_through_date: SCHED, datasets: { [file]: entry } });
const FRESH = { through_date: SCHED, through_date_source: 'payload:x', max_lag_days: 2 };
const STALE = { through_date: '2026-11-01', through_date_source: 'payload:x', max_lag_days: 2 };
const UNDATED = { through_date: null, through_date_source: 'not_game_dated', max_lag_days: 2 };
const IN_SEASON = { season_state: 'regular' };
const OFFSEASON = { season_state: 'offseason' };

// ---- shared staleness ------------------------------------------------------
test('datasetStatus classifies datasets (object and array manifests)', () => {
  assert.equal(S.datasetStatus(manifest('a.json', FRESH), 'a.json'), 'fresh');
  assert.equal(S.datasetStatus(manifest('a.json', STALE), 'a.json'), 'stale');
  assert.equal(S.datasetStatus(manifest('a.json', UNDATED), 'a.json'), 'undated');
  assert.equal(S.datasetStatus(manifest('a.json', { static: true }), 'a.json'), 'static');
  assert.equal(S.datasetStatus(manifest('a.json', FRESH), 'b.json'), 'missing');
  assert.equal(S.datasetStatus(null, 'a.json'), 'missing');
  const arr = { schedule_through_date: SCHED, datasets: [{ file: 'a.json', ...STALE }] };
  assert.equal(S.datasetStatus(arr, 'a.json'), 'stale');
  assert.equal(S.usable(manifest('a.json', STALE), 'a.json'), false);
  assert.equal(S.usable(manifest('a.json', FRESH), 'a.json'), true);
});

test('landing digest freshness is the shared module (same results)', () => {
  for (const lg of X.ORDER) {
    const m = real(lg, 'data_manifest.json');
    assert.deepEqual(D.freshness(m), S.freshness(m));
  }
});

// ---- example contract ------------------------------------------------------
test('6 to 8 examples, each declaring a file and fields per league', () => {
  assert.ok(X.EXAMPLES.length >= 6 && X.EXAMPLES.length <= 8, `got ${X.EXAMPLES.length}`);
  const html = readFileSync(join(ROOT, 'how-it-works', 'index.html'), 'utf8');
  for (const ex of X.EXAMPLES) {
    assert.ok(html.includes(`id="${ex.section}"`), `${ex.id}: section #${ex.section} on the page`);
    assert.ok(html.includes(`<p class="fo-example" data-example="${ex.id}" hidden></p>`), `${ex.id}: hidden slot on the page`);
    for (const [lg, src] of Object.entries(ex.sources)) {
      assert.ok(X.ORDER.includes(lg));
      assert.match(src.file, /^[\w.-]+\.json$/);
      assert.ok(src.fields.length > 0, `${ex.id}/${lg}: fields declared`);
    }
  }
});

test('declared files and fields exist in each published sport data set', () => {
  for (const ex of X.EXAMPLES) {
    for (const [lg, src] of Object.entries(ex.sources)) {
      assert.ok(existsSync(dataPath(lg, src.file)), `${ex.id}/${lg}: ${src.file} published`);
      const data = real(lg, src.file);
      for (const f of src.fields) assert.ok(X.hasField(data, f), `${ex.id}/${lg}: ${src.file} has ${f}`);
    }
  }
});

// One league's bundle: in-season digest, a manifest entry for the file, and the real payload.
function bundlesFor(ex, lg, { digest = IN_SEASON, entry = FRESH, data } = {}) {
  const src = ex.sources[lg];
  return { [lg]: { digest, manifest: manifest(src.file, entry), data: data === undefined ? { [src.file]: real(lg, src.file) } : data } };
}

test('present: every example renders a real figure for each league with fresh in-season data', () => {
  for (const ex of X.EXAMPLES) {
    for (const lg of Object.keys(ex.sources)) {
      const hit = X.pick(ex, bundlesFor(ex, lg));
      assert.ok(hit, `${ex.id}/${lg}: renders`);
      assert.equal(hit.league, lg);
      assert.ok(hit.text.includes(X.LABEL[lg]), `${ex.id}/${lg}: names the league`);
      assert.match(hit.text, /\d/, `${ex.id}/${lg}: carries a figure`);
    }
  }
});

test('absent: stale, missing, failed, offseason or empty data renders nothing', () => {
  for (const ex of X.EXAMPLES) {
    for (const lg of Object.keys(ex.sources)) {
      const f = ex.sources[lg].file;
      assert.equal(X.pick(ex, bundlesFor(ex, lg, { entry: STALE })), null, `${ex.id}/${lg}: stale`);
      assert.equal(X.pick(ex, bundlesFor(ex, lg, { digest: OFFSEASON })), null, `${ex.id}/${lg}: offseason`);
      assert.equal(X.pick(ex, bundlesFor(ex, lg, { digest: null })), null, `${ex.id}/${lg}: no digest`);
      assert.equal(X.pick(ex, bundlesFor(ex, lg, { data: {} })), null, `${ex.id}/${lg}: file failed to load`);
      assert.equal(X.pick(ex, bundlesFor(ex, lg, { data: { [f]: null } })), null, `${ex.id}/${lg}: null payload`);
      assert.equal(X.pick(ex, bundlesFor(ex, lg, { data: { [f]: {} } })), null, `${ex.id}/${lg}: empty payload`);
      const b = bundlesFor(ex, lg);
      b[lg].manifest = { schedule_through_date: SCHED, datasets: {} };
      assert.equal(X.pick(ex, b), null, `${ex.id}/${lg}: not in manifest`);
    }
    assert.equal(X.pick(ex, {}), null);
  }
});

test('a stale first league falls through to the next qualifying one', () => {
  const ex = X.EXAMPLES.find((e) => e.sources.nfl && e.sources.nba);
  const b = { ...bundlesFor(ex, 'nfl', { entry: STALE }), ...bundlesFor(ex, 'nba') };
  assert.equal(X.pick(ex, b).league, 'nba');
});

test('one-league sections only use that league', () => {
  const nflOnly = X.EXAMPLES.find((e) => e.id === 'nfl-win-probability-method');
  assert.deepEqual(Object.keys(nflOnly.sources), ['nfl']);
});

// ---- header drift ------------------------------------------------------------
test('site header copies match, and drift is caught', () => {
  assert.deepEqual(checkHeader(ROOT), []);
  const tmp = mkdtempSync(join(tmpdir(), 'hdr-'));
  for (const f of ['index.html', 'guide/index.html', 'how-it-works/index.html']) {
    mkdirSync(dirname(join(tmp, f)), { recursive: true });
    cpSync(join(ROOT, f), join(tmp, f));
  }
  const g = join(tmp, 'guide/index.html');
  writeFileSync(g, readFileSync(g, 'utf8').replace('>MLB</a>', '>Baseball</a>'));
  assert.equal(checkHeader(tmp).length, 1);
});
