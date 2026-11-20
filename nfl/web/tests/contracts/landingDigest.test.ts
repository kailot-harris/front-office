/**
 * Landing digest contract (NFL_analytics#182-#185, front-office#200 spec §1).
 *
 * `public/data/landing_digest.json` is written by tools/build_landing_digest.R
 * (slot A) and patched by tools/refresh_live_results.R (slots B/C). The
 * front-office landing page fetches it; this app does not read it.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';
import { z } from 'zod';
import { DATA_DIR, LANDING_DIGEST_FILE, loadRaw } from '../helpers/datasets';

const isoUtc = z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
const ymd = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const prob = z.number().min(0).max(1).nullable();

const game = {
  game_id: z.string().min(1),
  start_time_utc: isoUtc,
  home: z.string().min(1),
  away: z.string().min(1),
  status: z.enum(['scheduled', 'in_progress', 'final', 'postponed', 'cancelled']),
  home_win_prob: prob,
  away_win_prob: prob,
  prediction_status: z.enum(['available', 'no_model', 'not_yet_run']),
};
const tally = z.object({ hits: z.number().int().min(0), games: z.number().int().min(0), excluded: z.number().int().min(0) }).strict();
const moverWindow = z.object({
  compared_to: ymd.nullable(),
  items: z.array(z.object({ team: z.string(), previous: z.number(), current: z.number(), delta: z.number() }).strict()).max(5),
}).strict();

export const LandingDigestSchema = z.object({
  schema_version: z.literal(1),
  sport: z.literal('nfl'),
  generated_at: isoUtc,
  slate_date: ymd,
  season_state: z.enum(['regular', 'postseason', 'offseason', 'preseason']).nullable(),
  next_milestone: z.object({ label: z.string().min(1), date: ymd }).strict().nullable(),
  today: z.array(z.object(game).strict()),
  yesterday: z.array(z.object({
    ...game,
    home_score: z.number().int().nullable(),
    away_score: z.number().int().nullable(),
    final: z.boolean(),
    predicted_winner: z.string().nullable(),
    hit: z.boolean().nullable(),
  }).strict()),
  record: z.object({ season: tally, last_7: tally }).strict(),
  calibration: z.array(z.object({
    lo: z.number(), hi: z.number(),
    predicted_mean: z.number().nullable(), actual_rate: z.number().nullable(),
    games: z.number().int().min(0),
  }).strict()).length(5),
  movers: z.object({
    metric: z.string().min(1),
    windows: z.object({ '1': moverWindow, '7': moverWindow, '21': moverWindow }).strict(),
  }).strict(),
}).strict();

describe('landing_digest.json', () => {
  it('matches the landing digest contract', () => {
    const res = LandingDigestSchema.safeParse(loadRaw(LANDING_DIGEST_FILE));
    if (!res.success) throw new Error(JSON.stringify(res.error.issues.slice(0, 10)));
    expect(res.success).toBe(true);
  });

  it('every hit follows the shared hit rule (>50% side won; 50%, ties, non-finals are null)', () => {
    const d = LandingDigestSchema.parse(loadRaw(LANDING_DIGEST_FILE));
    for (const g of d.yesterday) {
      const p = g.home_win_prob;
      const expected = p === null || !g.final || g.home_score === null || g.away_score === null ||
        g.home_score === g.away_score || p === 0.5
        ? null : (p > 0.5) === (g.home_score > g.away_score);
      expect(g.hit, g.game_id).toBe(expected);
    }
  });

  it('calibration buckets cover 50-100% in steps of 10', () => {
    const d = LandingDigestSchema.parse(loadRaw(LANDING_DIGEST_FILE));
    expect(d.calibration.map((b) => [b.lo, b.hi])).toEqual([[0.5, 0.6], [0.6, 0.7], [0.7, 0.8], [0.8, 0.9], [0.9, 1]]);
  });

  it('carries no betting vocabulary', () => {
    const txt = fs.readFileSync(path.join(DATA_DIR, LANDING_DIGEST_FILE), 'utf-8').toLowerCase();
    expect(txt).not.toMatch(/odds|spread|moneyline|over\/under|sportsbook|wager/);
  });
});
