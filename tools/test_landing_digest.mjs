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

test('todayRow shows score and hit/miss for a final game', () => {
  const g = { home: 'HOM', away: 'AWY', home_win_prob: 0.4, away_win_prob: 0.6, start_time_utc: '2026-11-25T00:00:00Z',
    status: 'final', final: true, home_score: 99, away_score: 101, predicted_winner: 'AWY', hit: true };
  assert.deepEqual(D.todayRow(g), { primary: 'AWY 101, HOM 99', secondary: 'Model: AWY 60%', right: 'Hit', rightClass: 'dg-hit' });
  assert.deepEqual(D.todayRow({ ...g, hit: false }).rightClass, 'dg-miss');
  assert.equal(D.todayRow({ ...g, hit: null }).right, 'Not graded');
  // Same rendering as a Yesterday row.
  assert.deepEqual(D.todayRow(g), D.resultRow(g));
});

test('todayRow keeps start time and prediction for non-final and old-shape rows', () => {
  const old = { home: 'PHI', away: 'MIA', start_time_utc: '2026-11-25T22:00:00Z', status: 'scheduled',
    home_win_prob: 0.539, away_win_prob: 0.461, prediction_status: 'available' };
  const r = D.todayRow(old);
  assert.equal(r.primary, 'MIA at PHI');
  assert.equal(r.secondary, D.formatStart(old.start_time_utc));
  assert.equal(r.right, 'PHI 54%');
  assert.equal(r.rightClass, '');
  const notFinal = { ...old, final: false, home_score: null, away_score: null, predicted_winner: 'PHI', hit: null };
  assert.deepEqual(D.todayRow(notFinal), r);
  // final without numeric scores falls back to the scheduled display.
  assert.equal(D.todayRow({ ...old, final: true, home_score: null, away_score: null }).primary, 'MIA at PHI');
  assert.equal(D.todayRow({ home: 'A', away: 'B' }).rightClass, 'dg-muted');
});

test('todayEmptyLine handles today_pending, off-season and old shape', () => {
  assert.equal(D.todayEmptyLine({ today: [], today_pending: true, season_state: 'regular' }),
    'Today’s games and predictions post after the morning update');
  assert.equal(D.todayEmptyLine({ today: [], season_state: 'regular' }), 'No games today');
  assert.equal(D.todayEmptyLine({ today: [], season_state: 'offseason' }), 'Off-season');
  assert.match(D.todayEmptyLine({ today: [], season_state: 'regular', next_milestone: { label: 'Playoffs', date: '2027-04-18' } }),
    /^No games today\. Next: Playoffs /);
});

test('scoreText', () => {
  assert.equal(D.scoreText({ home: 'H', away: 'A', home_score: 3, away_score: 0 }), 'A 0, H 3');
  assert.equal(D.scoreText({ home: 'H', away: 'A', home_score: null, away_score: null }), 'A at H');
});

test('real sport fixtures parse and summarize', () => {
  for (const s of D.SPORTS) {
    const dg = fixture(s, 'landing_digest');
    assert.equal(dg.sport.toLowerCase(), s);
    for (const g of [...dg.today, ...dg.yesterday]) assert.equal(typeof D.predictionText(g), 'string');
    for (const g of dg.today) assert.equal(typeof D.todayRow(g).primary, 'string');
    assert.equal(typeof D.todayEmptyLine(dg), 'string');
    assert.ok(D.freshness(fixture(s, 'data_manifest')).through);
  }
});
