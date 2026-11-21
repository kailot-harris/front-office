// Unit tests for the landing-page "This week's visuals" helpers (front-office#210).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
const require = createRequire(import.meta.url);
const G = require('../assets/landing/gifs.js');
const IDX = JSON.parse(readFileSync(new URL('./fixtures/landing/gifs/indexes.json', import.meta.url)));
const NOW = new Date('2026-11-20T15:00:00Z');
const inSeason = { season_state: 'regular' };
const off = { season_state: 'offseason' };
const iso = ms => new Date(NOW.getTime() - ms).toISOString().replace(/\.\d+Z$/, 'Z');
const DAY = 86400000;

test('isFresh accepts 6 days old, rejects 8 days old', () => {
  assert.equal(G.isFresh(iso(6 * DAY), NOW), true);
  assert.equal(G.isFresh(iso(8 * DAY), NOW), false);
});

test('isFresh rejects bad dates', () => {
  assert.equal(G.isFresh(undefined, NOW), false);
  assert.equal(G.isFresh('not a date', NOW), false);
  assert.equal(G.isFresh(iso(-3600000), NOW), false);
});

test('selectSlides keeps only in-season sports', () => {
  const s = G.selectSlides({ nba: inSeason, wnba: off }, { nba: IDX.nba, wnba: IDX.wnba }, NOW);
  assert.deepEqual([...new Set(s.map(x => x.sport))], ['nba']);
});

test('selectSlides keeps only gif items', () => {
  const s = G.selectSlides({ nba: inSeason }, { nba: IDX.nba }, NOW);
  assert.equal(s.length, 1);
  assert.equal(s[0].src, 'nba/media/gif_elo_rank_bump.gif');
});

test('selectSlides skips sports with missing data', () => {
  const s = G.selectSlides({ nfl: undefined, nba: inSeason }, { nfl: IDX.nfl, nba: undefined }, NOW);
  assert.deepEqual(s, []);
});

test('selectSlides drops stale items and is empty when all are stale', () => {
  const later = new Date('2026-12-20T00:00:00Z');
  const all = { nfl: inSeason, nba: inSeason, wnba: inSeason, mlb: inSeason };
  assert.deepEqual(G.selectSlides(all, IDX, later), []);
});

test('selectSlides builds src and href', () => {
  const s = G.selectSlides({ nfl: inSeason, nba: inSeason }, { nfl: IDX.nfl, nba: IDX.nba }, NOW);
  const nfl = s.find(x => x.sport === 'nfl'), nba = s.find(x => x.sport === 'nba');
  assert.equal(nfl.src, 'nfl/animations/gif_division_pd_area.gif');
  assert.equal(nfl.href, 'nfl/gallery/');
  assert.equal(nba.src, 'nba/media/gif_elo_rank_bump.gif');
  assert.equal(nba.href, 'nba/gallery/');
  assert.equal(nba.title, 'League-Wide Elo Rating & Rank Evolution');
  assert.equal(nba.date, '2026-11-18T14:04:16Z');
  assert.equal(nba.durationMs, 16000);
});

test('selectSlides finds the matching still', () => {
  const s = G.selectSlides({ nfl: inSeason, nba: inSeason, mlb: inSeason },
    { nfl: IDX.nfl, nba: IDX.nba, mlb: IDX.mlb }, NOW);
  assert.equal(s.find(x => x.sport === 'nba').still, 'nba/media/gif_elo_rank_bump.png');
  assert.equal(s.find(x => x.sport === 'mlb').still, 'mlb/media/gif_division_standings_race.png');
  assert.equal(s.find(x => x.sport === 'nfl').still, null);
});

test('shuffle is a permutation and deterministic for a seeded rand', () => {
  const seeded = seed => () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const xs = [1, 2, 3, 4, 5, 6, 7];
  const a = G.shuffle(xs, seeded(42)), b = G.shuffle(xs, seeded(42));
  assert.deepEqual(a, b);
  assert.deepEqual([...a].sort(), xs);
  assert.deepEqual(xs, [1, 2, 3, 4, 5, 6, 7]);
  assert.notEqual(a, xs);
});

test('slideDelay uses duration_ms, else 10000', () => {
  assert.equal(G.slideDelay({ durationMs: 1200 }), 1200);
  assert.equal(G.slideDelay({ durationMs: null }), 10000);
  assert.equal(G.slideDelay({ durationMs: 0 }), 10000);
});

test('mediaUrl uses animations/ for NFL only', () => {
  assert.equal(G.mediaUrl('nfl', 'a.gif'), 'nfl/animations/a.gif');
  assert.equal(G.mediaUrl('mlb', 'a.gif'), 'mlb/media/a.gif');
});
