#!/usr/bin/env node
/**
 * Unit tests for tools/game_end_watch.mjs (front-office#240).
 *
 * Plain Node (`node:assert/strict`), no network and no `gh` calls: only the
 * pure helpers are exercised, with `now` passed in.
 *
 * Usage:
 *   node tools/test_game_end_watch.mjs
 */

import assert from 'node:assert/strict';
import {
  WATCHED_SPORTS,
  selectCandidates,
  isFinal,
  pickDispatchedRun,
  isAccessError,
} from './game_end_watch.mjs';

const START = '2026-11-25T00:00:00Z';
const startMs = Date.parse(START);
const min = (m) => m * 60 * 1000;
const at = (offsetMin) => new Date(startMs + min(offsetMin));

// New-shape row that is not final yet.
function row(extra = {}) {
  return {
    game_id: 'g1', start_time_utc: START, home: 'HOM', away: 'AWY', status: 'scheduled',
    final: false, home_score: null, away_score: null, predicted_winner: 'HOM', hit: null,
    ...extra,
  };
}
const digest = (today = [], yesterday = []) => ({ today, yesterday });

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

test('game past its length and not final is a candidate (today and yesterday)', () => {
  const c = selectCandidates('nba', digest([row()]), at(165));
  assert.equal(c.length, 1);
  assert.equal(c[0].game_id, 'g1');
  assert.equal(c[0].list, 'today');
  const y = selectCandidates('nba', digest([], [row({ game_id: 'g2' })]), at(200));
  assert.deepEqual(y.map((x) => [x.list, x.game_id]), [['yesterday', 'g2']]);
});

test('each sport uses its own game length', () => {
  assert.equal(selectCandidates('wnba', digest([row()]), at(150)).length, 1);
  assert.equal(selectCandidates('nba', digest([row()]), at(150)).length, 0);
  assert.equal(selectCandidates('nfl', digest([row()]), at(209)).length, 0);
  assert.equal(selectCandidates('nfl', digest([row()]), at(210)).length, 1);
});

test('final game is skipped', () => {
  const g = row({ final: true, status: 'final', home_score: 99, away_score: 101, hit: false });
  assert.deepEqual(selectCandidates('nba', digest([g]), at(200)), []);
});

test('postponed and cancelled games are skipped (case-insensitive)', () => {
  for (const status of ['Postponed', 'POSTPONED - rain', 'cancelled', 'Canceled']) {
    assert.deepEqual(selectCandidates('nba', digest([row({ status })]), at(200)), [], status);
  }
});

test('game not yet past its length is skipped', () => {
  assert.deepEqual(selectCandidates('nba', digest([row()]), at(164)), []);
  assert.deepEqual(selectCandidates('nba', digest([row()]), at(-30)), []);
});

test('game past the 6-hour cap is skipped; the cap itself is inclusive', () => {
  assert.equal(selectCandidates('nba', digest([row()]), at(165 + 360)).length, 1);
  assert.deepEqual(selectCandidates('nba', digest([row()]), at(165 + 361)), []);
});

test('unparseable or missing start time is skipped', () => {
  for (const start_time_utc of ['nope', '', null, undefined]) {
    assert.deepEqual(selectCandidates('nba', digest([row({ start_time_utc })]), at(200)), []);
  }
});

test('old-shape rows without `final`: status not final counts as not final', () => {
  const old = { game_id: 'o1', start_time_utc: START, home: 'PHI', away: 'MIA', status: 'scheduled',
    home_win_prob: 0.54, away_win_prob: 0.46, prediction_status: 'available' };
  assert.equal(isFinal(old), false);
  assert.equal(selectCandidates('nba', digest([old]), at(200)).length, 1);
  const oldFinal = { ...old, status: 'final' };
  assert.equal(isFinal(oldFinal), true);
  assert.deepEqual(selectCandidates('nba', digest([oldFinal]), at(200)), []);
  // A missing `yesterday` key (or any list) is tolerated.
  assert.equal(selectCandidates('nba', { today: [old] }, at(200)).length, 1);
});

test('today_pending digest selects from yesterday only', () => {
  const d = { today: [], today_pending: true, yesterday: [row()] };
  assert.equal(selectCandidates('nba', d, at(200)).length, 1);
});

test('a game listed in both today and yesterday is counted once', () => {
  assert.equal(selectCandidates('nba', digest([row()], [row()]), at(200)).length, 1);
});

test('MLB is never selected', () => {
  assert.equal('mlb' in WATCHED_SPORTS, false);
  assert.deepEqual(selectCandidates('mlb', digest([row()], [row({ game_id: 'g2' })]), at(200)), []);
  assert.deepEqual(Object.keys(WATCHED_SPORTS).sort(), ['nba', 'nfl', 'wnba']);
});

test('now may be a Date or epoch milliseconds', () => {
  assert.equal(selectCandidates('nba', digest([row()]), at(200).getTime()).length, 1);
});

test('pickDispatchedRun picks the newest workflow_dispatch run at or after the timestamp', () => {
  const since = Date.parse('2026-11-25T03:00:00.700Z');
  const runs = [
    { id: 1, event: 'workflow_dispatch', created_at: '2026-11-25T02:59:59Z' },
    { id: 2, event: 'schedule', created_at: '2026-11-25T03:00:30Z' },
    { id: 3, event: 'workflow_dispatch', created_at: '2026-11-25T03:00:00Z' },
    { id: 4, event: 'workflow_dispatch', created_at: '2026-11-25T03:00:05Z' },
  ];
  assert.equal(pickDispatchedRun(runs, since).id, 4);
  // Same second as the timestamp counts (created_at has no milliseconds).
  assert.equal(pickDispatchedRun(runs.slice(0, 3), since).id, 3);
  assert.equal(pickDispatchedRun(runs.slice(0, 2), since), null);
  assert.equal(pickDispatchedRun([], since), null);
});

test('isAccessError recognizes 403 and 404 from gh', () => {
  assert.equal(isAccessError('HTTP 404: Not Found (https://api.github.com/repos/x/y)'), true);
  assert.equal(isAccessError('gh: Resource not accessible (HTTP 403)'), true);
  assert.equal(isAccessError('HTTP 500: Server Error'), false);
  assert.equal(isAccessError(''), false);
});

let passed = 0;
for (const { name, fn } of tests) {
  try {
    fn();
    passed += 1;
    console.log(`PASS: ${name}`);
  } catch (err) {
    console.error(`FAIL: ${name}`);
    console.error(err);
    process.exitCode = 1;
  }
}

if (process.exitCode) {
  console.error(`\ntest_game_end_watch: FAILED (${passed}/${tests.length} passed)`);
} else {
  console.log(`\ntest_game_end_watch: OK (${passed}/${tests.length} tests passed)`);
}
