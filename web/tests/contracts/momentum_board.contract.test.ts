/**
 * Momentum Board contract (NFL_analytics#226, data layer).
 *
 * public/data/momentum_board.json is written by build_momentum_board.R. Checks
 * the shape, the owner's settings (windows and weights read from config.R, not
 * retyped), the combined score arithmetic, the carry-over labels, that no flag
 * claims significance, that every null carries a reason, and the wording rules.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';
import { z } from 'zod';
import { REPO_WEB_ROOT, MOMENTUM_BOARD_FILE, loadRaw } from '../helpers/datasets';
import type { MomentumPayload, MomentumRow } from '../../lib/momentumTypes';

const ymd = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const num = z.number().finite();
const numN = num.nullable();
const intN = z.number().int().nullable();
const reason = z.string().min(1).nullable();
const COMPONENTS = ['form', 'trend', 'residual', 'elo_change'] as const;
const weights = z.object({ form: num, trend: num, residual: num, elo_change: num }).strict();

const FLAG_KEYS = [
  'one_score',
  'pythagorean',
  'fumble_recovery',
  'opp_fg_pct',
  'turnover_margin',
  'blowout_skew',
  'opponent_strength',
  'home_share',
  'rest_bye',
  'starting_qb_change',
  'key_players_missing',
] as const;

const flag = z
  .object({
    key: z.enum(FLAG_KEYS),
    group: z.enum(['luck', 'context', 'availability']),
    value: numN,
    n: numN,
    statistic: numN,
    significant: z.literal(false),
    null_reason: z.string().min(1).optional(),
    detail: z.record(z.unknown()).optional(),
  })
  .strict();

const row = z
  .object({
    team: z.string().min(2).max(3),
    team_name: z.string().min(1),
    games_played: z.number().int().min(0),
    record: z.object({ wins: z.number().int(), losses: z.number().int(), ties: z.number().int() }).strict(),
    window: z.number().int(),
    games_in_window: z.number().int().min(0),
    carried_games: z.number().int().min(0),
    current_season_games_in_window: z.number().int().min(0),
    carried_from_season: intN,
    ranked: z.boolean(),
    rank: intN,
    rank_last_week: intN,
    rank_last_week_null_reason: reason,
    rank_change_week: intN,
    rank_change_week_null_reason: reason,
    combined_score: z
      .object({
        value: numN,
        rank: intN,
        components: z
          .object({ form_z: numN, trend_z: numN, residual_z: numN, elo_change_z: numN })
          .strict(),
        raw: z.object({ form: numN, trend: numN, residual: numN, elo_change: numN }).strict(),
        weights,
        null_reason: reason,
      })
      .strict(),
    form: z
      .object({
        epa_per_play: numN,
        rank: intN,
        season_to_date: numN,
        opponent_adjusted_margin: numN,
        opponent_adjusted_margin_rank: intN,
      })
      .strict(),
    epa_splits: z.record(numN),
    residual: z.object({ per_game: numN, basis: z.string().min(1) }).strict(),
    elo: z
      .object({
        current: num,
        rank: z.number().int().min(1),
        change_in_window: numN,
        change_since_last_week: numN,
        change_since_last_week_null_reason: reason,
        rank_change_since_last_week: intN,
      })
      .strict(),
    schedule_strength: z
      .object({
        faced_window: numN,
        faced_season: numN,
        next_opponent: z
          .object({
            week: z.number().int(),
            date: ymd,
            opponent: z.string().min(2),
            home: z.boolean(),
            opponent_elo: numN,
            opponent_elo_rank: intN,
          })
          .strict()
          .nullable(),
        next_opponent_null_reason: reason,
      })
      .strict(),
    flags: z.array(flag).length(FLAG_KEYS.length),
    sparkline: z.array(
      z.object({ week: z.number().int(), game_id: z.string().min(1), opponent: z.string().min(2), form_epa: numN }).strict(),
    ),
    sort_keys: z.record(numN),
    rank_history: z.array(
      z
        .object({
          season: z.number().int(),
          week: z.number().int(),
          through_date: ymd,
          rank: z.number().int().min(1),
          combined_score: num,
          carried_games: z.number().int().min(0),
          reconstruction: z.boolean(),
        })
        .strict(),
    ),
  })
  .strict();

const board = z
  .object({
    window: z.number().int(),
    noisiest: z.boolean(),
    label: z.string().min(1),
    ranked_count: z.number().int().min(0),
    team_count: z.number().int(),
    carried_team_count: z.number().int().min(0),
    rows: z.array(row),
  })
  .strict();

const payloadSchema = z
  .object({
    schema_version: z.literal(1),
    generated_at: z.string().min(1),
    season: z.number().int(),
    season_type: z.literal('REG'),
    through_date: ymd,
    through_week: z.number().int(),
    completed_week: z.number().int(),
    week_complete: z.boolean(),
    season_phase: z.enum(['preseason', 'early_season', 'in_season']),
    windows: z.array(z.number().int()),
    default_window: z.number().int(),
    ranked_counts: z.record(z.number().int()),
    sort_options: z.array(z.object({ key: z.string(), label: z.string(), descending: z.boolean() }).strict()).min(1),
    boards: z.record(board),
    methods: z
      .object({
        summary: z.string().min(1),
        predictive_beyond_elo: z.literal(false),
        source: z.record(z.union([z.string(), z.number()])),
        windows: z.object({}).passthrough(),
        carry_over: z.object({ method: z.string(), keep: num, definition: z.string() }).strict(),
        form: z.string().min(1),
        combined_score: z
          .object({
            components: z.record(z.string()),
            standardisation: z.string(),
            formula: z.string(),
            weights: z.record(weights),
            weights_source: z.string(),
            flat_surface: z.string(),
            refit: z.string(),
          })
          .strict(),
        elo: z.record(z.union([z.string(), z.number()])),
        flags: z
          .object({
            significance_shown: z.literal(false),
            significance_hidden_reason: z.string().min(20),
            context_only: z.array(z.string()),
            definitions: z.array(z.object({}).passthrough()).length(FLAG_KEYS.length),
            detail_source: z.string(),
            key_players_missing: z.string(),
            starting_qb_change: z.string(),
          })
          .strict(),
        rank_history: z.object({}).passthrough(),
      })
      .strict(),
  })
  .strict();

const data = loadRaw(MOMENTUM_BOARD_FILE) as MomentumPayload;
const rawText = fs.readFileSync(path.join(REPO_WEB_ROOT, 'public', 'data', MOMENTUM_BOARD_FILE), 'utf-8');
const allRows: MomentumRow[] = Object.values(data.boards).flatMap((b) => b.rows);

// config.R is the single source of the owner's settings; read them, never retype them.
const configText = fs.readFileSync(path.resolve(REPO_WEB_ROOT, '..', 'config.R'), 'utf-8');
function configWindows(): number[] {
  const m = configText.match(/^MOMENTUM_BOARD_WINDOWS\s*<-\s*c\(([^)]*)\)/m);
  if (!m) throw new Error('MOMENTUM_BOARD_WINDOWS not found in config.R');
  return m[1].split(',').map((s) => Number(s.trim().replace(/L$/, '')));
}
function configWeights(): Record<string, Record<string, number>> {
  const block = configText.match(/^MOMENTUM_BOARD_WEIGHTS\s*<-\s*list\(([\s\S]*?)^\)/m);
  if (!block) throw new Error('MOMENTUM_BOARD_WEIGHTS not found in config.R');
  const out: Record<string, Record<string, number>> = {};
  for (const m of block[1].matchAll(/"(\d+)"\s*=\s*c\(([^)]*)\)/g)) {
    out[m[1]] = Object.fromEntries(
      m[2].split(',').map((kv) => {
        const [k, v] = kv.split('=').map((s) => s.trim());
        return [k, Number(v)];
      }),
    );
  }
  return out;
}
function configInt(name: string): number {
  const m = configText.match(new RegExp(`^${name}\\s*<-\\s*(\\d+)L?\\b`, 'm'));
  if (!m) throw new Error(`${name} not found in config.R`);
  return Number(m[1]);
}

describe('momentum_board.json shape', () => {
  it('matches the schema', () => {
    const r = payloadSchema.safeParse(data);
    const issues = r.success ? [] : r.error.issues.slice(0, 10).map((i) => `${i.path.join('.')}: ${i.message}`);
    expect(issues).toEqual([]);
  });

  it('has the config windows, one board each, 32 teams per board', () => {
    const windows = configWindows();
    expect(windows).toEqual([3, 6, 9]);
    expect(data.windows).toEqual(windows);
    expect(Object.keys(data.boards).map(Number).sort((a, b) => a - b)).toEqual(windows);
    expect(windows).toContain(data.default_window);
    for (const w of windows) {
      const b = data.boards[String(w)];
      expect(b.window).toBe(w);
      expect(b.rows).toHaveLength(32);
      expect(b.team_count).toBe(32);
      expect(new Set(b.rows.map((r) => r.team)).size).toBe(32);
      expect(b.ranked_count).toBe(b.rows.filter((r) => r.ranked).length);
      expect(data.ranked_counts[String(w)]).toBe(b.ranked_count);
      expect(b.noisiest).toBe(w === configInt('MOMENTUM_BOARD_NOISIEST_WINDOW'));
    }
  });

  it('has no NaN or Infinity anywhere', () => {
    expect(rawText).not.toMatch(/\bNaN\b|\bInfinity\b|"NA"/);
  });
});

describe('owner settings', () => {
  it('weights in the JSON equal the config.R constants', () => {
    const cfg = configWeights();
    expect(Object.keys(cfg).sort()).toEqual(['3', '6', '9']);
    expect(data.methods.combined_score.weights).toEqual(cfg);
    for (const b of Object.values(data.boards)) {
      for (const r of b.rows) expect(r.combined_score.weights).toEqual(cfg[String(b.window)]);
    }
  });

  it('combined score is the weighted sum of the published z values', () => {
    let checked = 0;
    for (const r of allRows) {
      const cs = r.combined_score;
      if (cs.value === null) {
        expect(cs.null_reason).toBeTruthy();
        expect(cs.rank).toBeNull();
        continue;
      }
      let sum = 0;
      for (const c of COMPONENTS) {
        const w = cs.weights[c];
        if (w > 0) {
          const zv = cs.components[`${c}_z` as keyof typeof cs.components];
          expect(zv, `${r.team} w${r.window} ${c}_z`).not.toBeNull();
          sum += w * (zv as number);
        }
      }
      // z values are rounded to 3 dp and the score to 4 dp in the file.
      expect(Math.abs(sum - cs.value), `${r.team} w${r.window}`).toBeLessThan(0.003);
      checked++;
    }
    expect(checked).toBeGreaterThan(0);
  });

  it('ranks follow the combined score within each board', () => {
    for (const b of Object.values(data.boards)) {
      const ranked = b.rows.filter((r) => r.ranked).sort((a, c) => (a.rank as number) - (c.rank as number));
      for (let i = 1; i < ranked.length; i++) {
        expect((ranked[i - 1].combined_score.value as number) >= (ranked[i].combined_score.value as number)).toBe(true);
      }
      for (const r of b.rows) {
        expect(r.ranked).toBe(r.rank !== null);
        if (r.ranked) expect(r.combined_score.rank).toBe(r.rank);
      }
    }
  });

  it('no flag is marked significant, and the reason is published', () => {
    for (const r of allRows) for (const f of r.flags) expect(f.significant).toBe(false);
    expect(data.methods.flags.significance_shown).toBe(false);
    expect(data.methods.flags.significance_hidden_reason.length).toBeGreaterThan(20);
  });

  it('every row carries all flags, starting-QB change is always present', () => {
    for (const r of allRows) {
      expect(r.flags.map((f) => f.key)).toEqual([...FLAG_KEYS]);
      const qb = r.flags.find((f) => f.key === 'starting_qb_change');
      expect(qb, `${r.team} w${r.window}`).toBeDefined();
    }
    expect(data.methods.flags.context_only).toContain('starting_qb_change');
  });

  it('carried games are labelled', () => {
    expect(data.methods.carry_over.method).toBe('mean_regress');
    for (const r of allRows) {
      expect(r.games_in_window).toBe(r.carried_games + r.current_season_games_in_window);
      expect(r.games_in_window).toBeLessThanOrEqual(r.window);
      if (r.carried_games > 0) expect(r.carried_from_season).toBe(data.season - 1);
      else expect(r.carried_from_season).toBeNull();
    }
    for (const b of Object.values(data.boards)) {
      expect(b.carried_team_count).toBe(b.rows.filter((r) => r.carried_games > 0).length);
    }
  });

  it('methods block names the study and claims nothing beyond Elo', () => {
    const src = data.methods.source;
    expect(src.study_commit).toMatch(/^[0-9a-f]{40}$/);
    expect(configText).toContain(`MOMENTUM_BOARD_STUDY_COMMIT <- "${src.study_commit}"`);
    expect(src.measures_study_commit).toMatch(/^[0-9a-f]{40}$/);
    expect(data.methods.predictive_beyond_elo).toBe(false);
  });
});

describe('nulls and wording', () => {
  it('every null flag value carries a reason', () => {
    for (const r of allRows) {
      for (const f of r.flags) {
        if (f.value === null) expect(f.null_reason, `${r.team} w${r.window} ${f.key}`).toBeTruthy();
      }
    }
  });

  it('every nullable field with a reason slot has one when null', () => {
    for (const r of allRows) {
      if (r.rank_last_week === null) expect(r.rank_last_week_null_reason).toBeTruthy();
      if (r.rank_change_week === null) expect(r.rank_change_week_null_reason).toBeTruthy();
      if (r.elo.change_since_last_week === null) expect(r.elo.change_since_last_week_null_reason).toBeTruthy();
      if (r.schedule_strength.next_opponent === null) expect(r.schedule_strength.next_opponent_null_reason).toBeTruthy();
    }
  });

  it('uses no betting terms', () => {
    expect(rawText).not.toMatch(/\b(odds|lines?|spreads?|picks?|props?|wagers?|edges?|betting|sportsbook|moneyline|parlay)\b/i);
  });
});
