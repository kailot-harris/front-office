#!/usr/bin/env node
// Unit tests for the pure helpers in assets/landing/digest.js (front-office#202-#204).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const D = require('../assets/landing/digest.js');
const fixture = (s, f) => JSON.parse(readFileSync(new URL(`fixtures/landing/${s}/${f}.json`, import.meta.url)));

test('easternDate uses America/New_York', () => {
  // 03:00 UTC on Nov 20 is still Nov 19 in New York.
  assert.equal(D.easternDate(new Date('2026-11-20T03:00:00Z')), '2026-11-19');
  assert.equal(D.easternDate(new Date('2026-11-20T06:00:00Z')), '2026-11-20');
});

test('isStale compares slate_date with today in Eastern time', () => {
  const now = new Date('2026-11-20T15:00:00Z');
  assert.equal(D.isStale({ slate_date: '2026-11-20' }, now), false);
  assert.equal(D.isStale({ slate_date: '2026-11-19' }, now), true);
  assert.equal(D.isStale(null, now), false);
});

test('formatStart handles missing and invalid times', () => {
  assert.equal(D.formatStart(null), 'Time TBD');
  assert.equal(D.formatStart('nope'), 'Time TBD');
  assert.match(D.formatStart('2026-11-20T00:00:00Z'), /\d/);
});

test('favorite and predictionText', () => {
  const g = { home: 'ATL', away: 'CHA', home_win_prob: 0.71, away_win_prob: 0.29 };
  assert.deepEqual(D.favorite(g), { team: 'ATL', p: 0.71 });
  assert.equal(D.predictionText(g), 'ATL 71%');
  assert.equal(D.predictionText({ home: 'A', away: 'B', home_win_prob: null, prediction_status: 'no_model' }), 'No model prediction');
  assert.equal(D.predictionText({ home: 'A', away: 'B' }), 'Prediction pending');
});

test('hitText covers hit, miss and exclusions', () => {
  assert.equal(D.hitText({ hit: true }), 'Hit');
  assert.equal(D.hitText({ hit: false }), 'Miss');
  assert.equal(D.hitText({ hit: null, status: 'Postponed' }), 'Postponed');
  assert.equal(D.hitText({ hit: null, status: 'cancelled' }), 'Cancelled');
  assert.equal(D.hitText({ hit: null, final: false }), 'Not final');
  assert.equal(D.hitText({ hit: null, final: true }), 'Not graded');
});

test('recordText', () => {
  assert.equal(D.recordText(null), '');
  assert.equal(D.recordText({ season: { hits: 0, games: 0 } }), '');
  assert.equal(D.recordText({ season: { hits: 92, games: 148, excluded: 3 }, last_7: { hits: 10, games: 14 } }),
    'Model: 92–56 season · 10–4 last 7 days · 3 excluded');
});

test('defaultSport picks the first in-season sport in page order', () => {
  assert.equal(D.defaultSport({ wnba: { season_state: 'offseason' }, nba: { season_state: 'regular' } }), 'nba');
  assert.equal(D.defaultSport({ mlb: { season_state: 'offseason' } }), 'mlb');
  assert.equal(D.defaultSport({}), null);
});

test('freshness summarizes a manifest', () => {
  const m = { schedule_through_date: '2026-11-19', datasets: {
    a: { through_date: '2026-11-19', max_lag_days: 1 },
    b: { through_date: '2026-11-10', max_lag_days: 2 },
    c: { through_date_source: 'not_game_dated' },
    d: { static: true } } };
  assert.deepEqual(D.freshness(m), { through: '2026-11-19', stale: 1, undated: 1 });
  assert.equal(D.freshness(null), null);
});

test('real sport fixtures parse and summarize', () => {
  for (const s of D.SPORTS) {
    const dg = fixture(s, 'landing_digest');
    assert.equal(dg.sport.toLowerCase(), s);
    for (const g of [...dg.today, ...dg.yesterday]) assert.equal(typeof D.predictionText(g), 'string');
    assert.ok(D.freshness(fixture(s, 'data_manifest')).through);
  }
});
