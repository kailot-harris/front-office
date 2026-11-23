import test from 'node:test';
import assert from 'node:assert/strict';
import { counts, fill } from './fill_page_counts.mjs';

const C = { nfl: 13, nba: 14, wnba: 15, mlb: 14, all: 56 };

test('counts sums pages per sport', () => {
  const t = { sports: { a: { pages: { '/': 'x', '/b': 'y' } }, b: { pages: { '/': 'x' } } } };
  assert.deepEqual(counts(t), { a: 2, b: 1, all: 3 });
});

test('fills text and listed attributes, leaves others alone', () => {
  const html = '<meta name="d" data-count="all" data-count-attr="content" content="50 pages, 4 leagues">'
    + '<span class="c" data-count="nfl" data-count-attr="aria-label" aria-label="9 modules" title="9">(9)</span>'
    + '<p>Front Office has <span data-count="all">50</span> pages</p>';
  const r = fill(html, C, 'f');
  assert.deepEqual(r.errors, []);
  assert.match(r.html, /content="56 pages, 4 leagues"/);
  assert.match(r.html, /aria-label="13 modules" title="9">\(13\)</);
  assert.match(r.html, /has <span data-count="all">56<\/span> pages/);
  assert.equal(r.changes.length, 4);
});

test('no changes when counts are current', () => {
  const r = fill('<span data-count="mlb">14</span>', C, 'f');
  assert.deepEqual(r.changes, []);
  assert.deepEqual(r.errors, []);
});

test('errors: no markers, unknown key, attribute without a number, text without a number', () => {
  assert.match(fill('<p>56 pages</p>', C, 'f').errors[0], /no data-count markers/);
  assert.match(fill('<span data-count="nhl">3</span>', C, 'f').errors[0], /unknown data-count "nhl"/);
  assert.match(fill('<i data-count="all" data-count-attr="title" title="many">x</i>', C, 'f').errors[0], /attribute title has no number/);
  assert.match(fill('<span data-count="all">many</span>', C, 'f').errors[0], /text has no number/);
});
