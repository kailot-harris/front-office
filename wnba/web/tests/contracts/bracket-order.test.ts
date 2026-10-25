import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';

/**
 * Presentation-order contract for /bracket-2026 (#98): the page reads
 * newest-round-first, and the Finals tables/animation are rendered as the
 * Finals round's own content rather than as siblings below the whole tree.
 *
 * Asserted against source text because these are structural/ordering facts of
 * server components, not values in a data payload.
 */
const WEB_ROOT = path.join(__dirname, '..', '..');
const CLIENT = path.join(WEB_ROOT, 'components', 'PlayoffBracket2026Client.tsx');
const PAGE = path.join(WEB_ROOT, 'app', 'bracket-2026', 'page.tsx');

describe('2026 bracket page ordering contract', () => {
  const client = fs.readFileSync(CLIENT, 'utf-8');
  const page = fs.readFileSync(PAGE, 'utf-8');

  it('renders rounds newest-first', () => {
    const match = client.match(/const ROUND_ORDER = \[([^\]]*)\]/);
    expect(match, 'ROUND_ORDER not found').toBeTruthy();
    const order = match![1]
      .split(',')
      .map((s) => s.trim().replace(/^['"]|['"]$/g, ''))
      .filter(Boolean);
    expect(order).toEqual(['Finals', 'Semifinals', 'Round 1']);
  });

  it('still renders unrecognized round labels rather than dropping them', () => {
    expect(client).toMatch(/const extraRounds =/);
    expect(client).toMatch(/const rounds: string\[\] = \[\.\.\.knownRounds, \.\.\.extraRounds/);
  });

  it('keeps per-round provenance derived from that round’s own series', () => {
    expect(client).toContain('rows[0]?.prediction.provenanceLabel');
    expect(client).toContain('<ProvenanceBadge series={series} />');
  });

  it('attaches the Finals tables and trajectory to the Finals round', () => {
    expect(page).toMatch(/roundExtras\s*=\s*\{\s*Finals:/);
    expect(page).toContain('roundExtras={roundExtras}');
    const game = page.indexOf('<FinalsGamePredictions');
    const backtestIdx = page.indexOf('<FinalsSeriesBacktest');
    const traj = page.indexOf('<NetRatingTrajectory');
    expect(game).toBeGreaterThan(-1);
    expect(backtestIdx).toBeGreaterThan(game);
    expect(traj).toBeGreaterThan(backtestIdx);
  });

  it('keeps the trajectory figure gated on hasTrajectoryMedia()', () => {
    expect(page).toMatch(/function hasTrajectoryMedia\(season: number\): boolean/);
    expect(page).toContain('const showTrajectory = hasTrajectoryMedia(backtest.season);');
    expect(page).toContain(
      '{showTrajectory && <NetRatingTrajectory data={backtest} season={backtest.season} />}'
    );
  });

  it('never claims a round was held out', () => {
    // Pattern assembled from parts so this file does not itself contain the
    // forbidden phrase that other greps/tests scan the tree for.
    const forbidden = new RegExp(['out', 'of', 'sample'].join('[-\s]'), 'i');
    for (const src of [client, page]) {
      expect(src).not.toMatch(forbidden);
    }
  });
});
