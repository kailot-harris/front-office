/**
 * momentum_board.json contract (NBA_analytics#237; consumed by the /momentum
 * page, #238).
 *
 * Written by build_momentum_dataset.R. Checks the shape the page relies on
 * (one board per window, 30 rows each, every value the page shows already
 * computed) and the rules from the issue: the unranked rule, the residual
 * minimum, eleven flags with value / statistic / significant, nulls carry a
 * reason (rank changes included), changes are measured against the games before
 * the window, the default window follows the 80% rule, the methods block
 * documents the weights and Elo rules, and no betting
 * vocabulary anywhere in the file.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import { DATA_DIR, NBA_TEAMS } from '../helpers/datasets';

const FILE = path.join(DATA_DIR, 'momentum_board.json');
const RAW = fs.readFileSync(FILE, 'utf-8');
const DATA = JSON.parse(RAW);

const WINDOWS = [5, 10, 18] as const;
const RESIDUAL_MIN_SHARE = 0.6;
const FORBIDDEN_BETTING_RE =
  /\b(odds|spread|spreads|bet|bets|betting|wager|wagers|parlay|sportsbook|moneyline|over_under|vig|juice|handicap)\b/i;

const num = z.number().finite();
const nnum = num.nullable();
const nint = z.number().int().nullable();

const FlagSchema = z
  .object({
    id: z.number().int().min(1).max(11),
    key: z.string().min(1),
    group: z.enum(['luck', 'context', 'availability']),
    value: nnum,
    statistic: nnum,
    significant: z.boolean(),
    n: nint.optional(),
    value_shrunk: nnum.optional(),
    null_reason: z.string().min(1).optional(),
    detail: z.unknown().optional(),
  })
  .strict();

const BASELINE_MIN_GAMES = 5;
const BASELINE_NULL_REASON = 'too few games before this window';
const DEFAULT_WINDOW_MIN_SHARE = 0.8;
const reason = z.string().min(1).nullable();

const RatingSchema = z
  .object({
    value: num,
    rank: nint,
    season: num,
    before_window: nnum,
    games_before_window: z.number().int().nonnegative(),
    change: nnum,
    change_null_reason: reason,
  })
  .passthrough();

const RowSchema = z
  .object({
    team: z.enum(NBA_TEAMS),
    team_name: z.string().min(1),
    games_played: z.number().int().positive(),
    record: z.object({ wins: z.number().int(), losses: z.number().int() }),
    window: z.number().int(),
    games_in_window: z.number().int().positive(),
    ranked: z.boolean(),
    rank: nint,
    rank_7d_ago: nint,
    rank_7d_ago_null_reason: reason,
    rank_change_7d: nint,
    rank_change_7d_null_reason: reason,
    combined_score: z.object({
      value: nnum,
      rank: nint,
      components: z.object({ form_z: nnum, trend_z: nnum, residual_z: nnum, elo_z: nnum }),
      null_reason: z.string().nullable(),
    }),
    ratings: z.object({ ortg: RatingSchema, drtg: RatingSchema, net: RatingSchema }),
    model_residual: z.object({
      value: nnum,
      residual_games_in_window: z.number().int().nonnegative(),
      ranked: z.boolean(),
      rank: nint,
      basis: z.literal('logged_pregame_model'),
      null_reason: z.string().nullable(),
    }),
    residual_games_in_window: z.number().int().nonnegative(),
    opponent_adjusted_form: z.object({ value: nnum, games: z.number().int(), rank: nint }),
    drivers: z.record(z.unknown()),
    elo: z.object({
      current: num,
      rank: z.number().int(),
      change_7d: num,
      change_14d: num,
      rank_change_7d: z.number().int(),
      rank_change_14d: z.number().int(),
      change_in_window: num,
    }),
    schedule_strength: z.object({
      faced_window: num,
      faced_season: num,
      faced_season_rank: z.number().int(),
      next_week: z.object({
        games: z.number().int().nonnegative(),
        opponent_win_pct: nnum,
        rank: nint,
        null_reason: z.string().nullable(),
        opponents: z.array(
          z.object({ date: z.string(), opponent: z.enum(NBA_TEAMS), home: z.boolean(), opponent_win_pct: num }),
        ),
      }),
    }),
    clutch: z.object({ window: z.record(z.unknown()), season: z.record(z.unknown()) }),
    flags: z.array(FlagSchema).length(11),
    sparkline: z.array(z.object({ date: z.string(), net_rating: num })),
    sort_keys: z.object({
      combined_score: nnum,
      model_residual: nnum,
      net_rating_change: nnum,
      elo_change_7d: nnum,
      elo_change_14d: nnum,
      schedule_strength: nnum,
    }),
    rank_history: z.array(
      z.object({
        week_start: z.string(),
        as_of: z.string(),
        rank: z.number().int(),
        combined_score: num,
        reconstruction: z.boolean(),
      }),
    ),
  })
  .strict();

const PayloadSchema = z
  .object({
    schema_version: z.literal(1),
    generated_at: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/),
    season: z.string().regex(/^\d{4}-\d{2}$/),
    through_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    windows: z.array(z.number().int()),
    default_window: z.number().int(),
    ranked_counts: z.record(z.number().int().nonnegative()),
    sort_options: z.array(z.object({ key: z.string(), label: z.string(), descending: z.boolean() })),
    boards: z.record(
      z.object({
        window: z.number().int(),
        ranked_count: z.number().int(),
        team_count: z.number().int(),
        note: z.string().nullable().optional(),
        rows: z.array(RowSchema),
      }),
    ),
    methods: z.record(z.unknown()),
  })
  .strict();

const boards = () => WINDOWS.map((w) => DATA.boards[String(w)]);

describe('momentum_board.json contract', () => {
  it('matches the payload schema', () => {
    const r = PayloadSchema.safeParse(DATA);
    const msg = r.success
      ? ''
      : r.error.issues.slice(0, 8).map((i) => `[${i.path.join('.')}] ${i.message}`).join('\n');
    expect(r.success, msg).toBe(true);
  });

  it('has one board per window (5, 10, 18) with all 30 teams once', () => {
    expect(DATA.windows).toEqual([...WINDOWS]);
    for (const b of boards()) {
      expect(b.rows).toHaveLength(30);
      expect(new Set(b.rows.map((r: { team: string }) => r.team)).size).toBe(30);
      for (const r of b.rows) expect(r.window).toBe(b.window);
    }
  });

  it('applies the unranked rule: fewer games than the window means ranked=false and no rank', () => {
    for (const b of boards()) {
      let ranked = 0;
      for (const r of b.rows) {
        expect(r.ranked).toBe(r.games_in_window >= b.window);
        expect(r.games_in_window).toBeLessThanOrEqual(b.window);
        if (!r.ranked) {
          expect(r.rank).toBeNull();
          expect(r.ratings.net.rank).toBeNull();
          expect(r.model_residual.rank).toBeNull();
          for (const v of Object.values(r.sort_keys)) expect(v).toBeNull();
        } else {
          ranked += 1;
        }
      }
      expect(b.ranked_count).toBe(ranked);
      expect(DATA.ranked_counts[String(b.window)]).toBe(ranked);
    }
  });

  it('default window is the longest window in which at least 80% of teams are ranked', () => {
    const teams = boards()[0].rows.length;
    const need = Math.ceil(DEFAULT_WINDOW_MIN_SHARE * teams - 1e-9);
    const ok = WINDOWS.filter((w) => DATA.ranked_counts[String(w)] >= need);
    const expected = ok.length ? Math.max(...ok) : Math.min(...WINDOWS);
    expect(DATA.default_window).toBe(expected);
    expect(DATA.methods.windows.default).toBe(DATA.default_window);
    expect(DATA.methods.windows.default_rule).toMatch(/80%/);
  });

  it('changes are measured against the games before the window; too few earlier games means null with a reason', () => {
    for (const b of boards()) {
      for (const r of b.rows) {
        const before = r.games_played - r.games_in_window;
        for (const k of ['ortg', 'drtg', 'net'] as const) {
          const rt = r.ratings[k];
          expect(rt.games_before_window).toBe(before);
          if (before < BASELINE_MIN_GAMES) {
            expect(rt.change).toBeNull();
            expect(rt.change_null_reason).toBe(BASELINE_NULL_REASON);
          } else {
            expect(rt.change).not.toBeNull();
            expect(rt.change_null_reason).toBeNull();
            expect(rt.change).toBeCloseTo(rt.value - rt.before_window, 1);
          }
        }
        const d = r.drivers as Record<string, unknown>;
        expect(d.games_before_window).toBe(before);
        if (before < BASELINE_MIN_GAMES) {
          expect(d.null_reason).toBe(BASELINE_NULL_REASON);
          for (const key of ['efg_offense', 'efg_defense', 'tov_offense', 'unexplained']) expect(d[key]).toBeNull();
          // The trend component is unavailable, so the combined score is null (never imputed).
          expect(r.combined_score.components.trend_z).toBeNull();
          expect(r.combined_score.value).toBeNull();
          expect(r.rank).toBeNull();
          expect(typeof r.combined_score.null_reason).toBe('string');
        } else {
          expect(d.null_reason).toBeUndefined();
          expect(typeof d.efg_offense).toBe('number');
        }
      }
    }
  });

  it('every null rank-change field carries a null_reason', () => {
    for (const b of boards()) {
      for (const r of b.rows) {
        if (r.rank_7d_ago === null) expect(typeof r.rank_7d_ago_null_reason).toBe('string');
        else expect(r.rank_7d_ago_null_reason).toBeNull();
        if (r.rank_change_7d === null) expect(typeof r.rank_change_7d_null_reason).toBe('string');
        else expect(r.rank_change_7d_null_reason).toBeNull();
        if (r.rank === null) expect(typeof r.combined_score.null_reason).toBe('string');
        if (r.ratings.net.change_rank === null && r.ranked && r.ratings.net.change === null) {
          expect(r.ratings.net.change_null_reason).toBe(BASELINE_NULL_REASON);
        }
      }
    }
  });

  it('combined ranks are 1..k over ranked teams and follow the score', () => {
    for (const b of boards()) {
      const rows = b.rows.filter((r: { rank: number | null }) => r.rank !== null);
      const ranks = rows.map((r: { rank: number }) => r.rank).sort((a: number, c: number) => a - c);
      if (ranks.length) expect(ranks[0]).toBe(1);
      for (const r of rows) {
        const ahead = rows.filter(
          (o: { combined_score: { value: number } }) => o.combined_score.value > r.combined_score.value,
        ).length;
        // Scores are published rounded to 3 decimals, so two teams can show the same
        // value while the unrounded scores (which set the rank) differ.
        const tied = rows.filter(
          (o: { team: string; combined_score: { value: number } }) =>
            o.team !== r.team && o.combined_score.value === r.combined_score.value,
        ).length;
        expect(r.rank).toBeGreaterThanOrEqual(ahead + 1);
        expect(r.rank).toBeLessThanOrEqual(ahead + 1 + tied);
      }
    }
  });

  it('model residual counts only logged games and respects the residual minimum', () => {
    for (const b of boards()) {
      const min = Math.ceil(RESIDUAL_MIN_SHARE * b.window);
      for (const r of b.rows) {
        expect(r.residual_games_in_window).toBe(r.model_residual.residual_games_in_window);
        expect(r.residual_games_in_window).toBeLessThanOrEqual(r.games_in_window);
        if (r.model_residual.ranked) {
          expect(r.ranked).toBe(true);
          expect(r.residual_games_in_window).toBeGreaterThanOrEqual(min);
        } else {
          expect(r.model_residual.rank).toBeNull();
          expect(r.sort_keys.model_residual).toBeNull();
        }
        if (r.residual_games_in_window === 0) expect(r.model_residual.value).toBeNull();
      }
    }
  });

  it('carries all 11 flags; a flag without a statistic is not significant and says why', () => {
    for (const b of boards()) {
      for (const r of b.rows) {
        expect(r.flags.map((f: { id: number }) => f.id)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
        for (const f of r.flags) {
          if (f.value === null || f.statistic === null) {
            expect(f.significant).toBe(false);
            expect(typeof f.null_reason).toBe('string');
          }
        }
      }
    }
  });

  it('documents flags, weights, validation and Elo rules in methods', () => {
    const m = DATA.methods;
    expect(m.flags.definitions).toHaveLength(11);
    const weights = m.combined_score.weights as Record<string, number>;
    expect(Object.keys(weights).sort()).toEqual(['elo', 'form', 'residual', 'trend']);
    expect(Object.values(weights).reduce((a, c) => a + c, 0)).toBeCloseTo(1, 6);
    expect(m.combined_score.validation.previous_season.length + m.combined_score.validation.current_season.length).toBeGreaterThan(0);
    expect(m.elo.k).toBeGreaterThan(0);
    expect(typeof m.elo.home_advantage_elo).toBe('number');
    expect(typeof m.elo.margin_multiplier).toBe('string');
    expect(m.rank_history.reconstruction).toBe(false);
    expect(m.flags.availability_source).toMatch(/player box/i);
  });

  it('rank history entries are never labelled reconstructions without saying so', () => {
    for (const b of boards()) {
      for (const r of b.rows) for (const h of r.rank_history) expect(h.reconstruction).toBe(false);
    }
  });

  it('contains no betting vocabulary and no NaN/Infinity/"NA" values', () => {
    expect(RAW).not.toMatch(FORBIDDEN_BETTING_RE);
    expect(RAW).not.toMatch(/:\s*NaN\b/);
    expect(RAW).not.toMatch(/:\s*-?Infinity\b/);
    expect(RAW).not.toMatch(/:\s*"NA"/);
  });
});
