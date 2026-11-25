/**
 * League leaders contract (NFL_analytics#230).
 *
 * public/data/player_leaders.json is written by build_player_leaders.R (09:00
 * pipeline) and its non-model cards are rebuilt by tools/refresh_live_results.R
 * in the evening refreshes. Checks the shape, the owner's minimums (read from
 * config.R, not retyped), the scaling rule, the ranking order and the panel's
 * empty-card wording.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';
import { z } from 'zod';
import { REPO_WEB_ROOT, loadRaw } from '../helpers/datasets';
import type { PlayerLeadersPayload } from '../../lib/playerLeadersTypes';

const FILE = 'player_leaders.json';
const ymd = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const groupKey = z.enum(['passing', 'rushing', 'receiving', 'defense', 'impact']);
const unit = z.enum(['season_total', 'games', 'dropbacks', 'designed_carries', 'targets']);

const row = z
  .object({
    rank: z.number().int().min(1),
    player_id: z.string().min(1),
    player: z.string().min(1),
    team: z.string().min(2),
    position: z.string().nullable(),
    value: z.number().finite(),
    sample: z.number().nonnegative().nullable(),
    required: z.number().nonnegative().nullable(),
    team_games_played: z.number().int().min(1).max(17),
  })
  .strict();

const card = z
  .object({
    key: z.string().min(1),
    label: z.string().min(1),
    group: groupKey,
    kind: z.enum(['total', 'per_game', 'rate']),
    format: z.enum(['per_game', 'count', 'epa_play', 'cpoe', 'pct', 'yards_play', 'epa_total']),
    lower_is_better: z.boolean(),
    unit,
    unit_label: z.string().min(1),
    minimum_full_season: z.number().int().positive().nullable(),
    minimum_constant: z.string().nullable(),
    through_date: ymd.nullable(),
    through_date_null_reason: z.string().nullable(),
    noise_note: z.boolean(),
    noise_note_text: z.string().nullable(),
    status: z.enum(['ok', 'not_enough_games', 'unavailable']),
    status_text: z.string().nullable(),
    null_reason: z.string().nullable(),
    source: z.string().min(1),
    refresh: z.enum(['pipeline_and_evening', 'pipeline_only']),
    formula: z.string().min(1),
    candidates: z.number().int().min(0),
    qualified_count: z.number().int().min(0),
    excluded_no_value: z.number().int().min(0),
    notes: z.string().nullable(),
    leaders: z.array(row).max(10),
  })
  .strict();

const minimumRow = z
  .object({
    key: z.string(),
    label: z.string(),
    group: groupKey,
    unit,
    unit_label: z.string(),
    minimum_full_season: z.number().int().positive().nullable(),
    constant: z.string().nullable(),
    lower_is_better: z.boolean(),
    formula: z.string(),
  })
  .strict();

const payloadSchema = z
  .object({
    schema_version: z.literal(1),
    generated_at: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/),
    season: z.string().regex(/^\d{4}$/),
    season_type: z.literal('REG'),
    through_date: ymd.nullable(),
    groups: z.array(z.object({ key: groupKey, label: z.string() }).strict()).length(5),
    cards: z.array(card).min(1),
    methods: z
      .object({
        scaling_rule: z.string(),
        scaling_text: z.string(),
        traded_players: z.string(),
        ranking: z.string(),
        impact_note: z.string(),
        noise_note: z.string(),
        definitions: z.string(),
        refresh: z.string(),
        sample: z.string(),
        not_available: z.string(),
        study_source_commit: z.string().regex(/^[0-9a-f]{40}$/),
        base_games: z.literal(17),
        minimums: z.array(minimumRow),
        diagnostics: z.record(z.union([z.number(), z.string(), z.null()])),
        nulls: z.string(),
      })
      .strict(),
    sources: z.record(z.string()),
  })
  .strict();

const data = loadRaw(FILE) as PlayerLeadersPayload;
const byKey = Object.fromEntries(data.cards.map((c) => [c.key, c]));

// config.R is the single source of the owner's numbers; read them, never retype them.
const configText = fs.readFileSync(path.resolve(REPO_WEB_ROOT, '..', 'config.R'), 'utf-8');
function configInt(name: string): number {
  const m = configText.match(new RegExp(`^${name}\\s*<-\\s*(\\d+)L?\\b`, 'm'));
  if (!m) throw new Error(`${name} not found in config.R`);
  return Number(m[1]);
}

const EXPECTED_KEYS = {
  passing: ['pass_ypg', 'pass_td', 'pass_epa', 'pass_cpoe', 'pass_succ', 'sack_rate', 'int_rate'],
  rushing: ['rush_ypg', 'rush_epa', 'rush_succ', 'rush_yac'],
  receiving: ['rec_ypg', 'receptions', 'rec_epa', 'catch_rate'],
  defense: ['sacks', 'def_int', 'tfl', 'pressures'],
  impact: ['total_epa'],
};
const TOTALS = ['pass_td', 'receptions', 'sacks', 'def_int', 'tfl', 'pressures', 'total_epa'];
const NOISE = ['int_rate', 'pass_cpoe', 'rush_epa', 'rush_succ', 'rec_epa'];
const LOWER = ['sack_rate', 'int_rate'];

describe('player_leaders.json shape', () => {
  it('matches the schema', () => {
    const r = payloadSchema.safeParse(data);
    const issues = r.success ? [] : r.error.issues.slice(0, 10).map((i) => `${i.path.join('.')}: ${i.message}`);
    expect(issues).toEqual([]);
  });

  it('has exactly the owner-approved cards in each group, and no yards per route run', () => {
    for (const [g, keys] of Object.entries(EXPECTED_KEYS)) {
      expect(data.cards.filter((c) => c.group === g).map((c) => c.key)).toEqual(keys);
    }
    expect(data.cards.some((c) => /route/i.test(c.key) || /route/i.test(c.label))).toBe(false);
  });

  it('is the 2026 regular season only', () => {
    expect(data.season).toBe('2026');
    expect(data.season_type).toBe('REG');
    for (const c of data.cards) if (c.through_date) expect(c.through_date.startsWith('2026')).toBe(true);
  });
});

describe('minimums come from config.R and scale with team games played', () => {
  const base = configInt('LEADERS_FULL_SEASON_GAMES');
  const expected: Record<string, [string, number]> = {
    games: ['LEADERS_MIN_GAMES_YARDS_PER_GAME', 8],
    dropbacks: ['LEADERS_MIN_DROPBACKS_PASSING_RATES', 250],
    designed_carries: ['LEADERS_MIN_DESIGNED_CARRIES_RUSHING_RATES', 100],
    targets: ['LEADERS_MIN_TARGETS_RECEIVING_RATES', 80],
  };

  it('config.R holds the owner decisions (17-game base; 8 / 250 / 100 / 80)', () => {
    expect(base).toBe(17);
    for (const [constant, value] of Object.values(expected)) expect(configInt(constant)).toBe(value);
    expect(data.methods.base_games).toBe(base);
  });

  it('season totals have no minimum', () => {
    for (const k of TOTALS) {
      const c = byKey[k];
      expect(c.kind, k).toBe('total');
      expect(c.minimum_full_season, k).toBeNull();
      expect(c.minimum_constant, k).toBeNull();
      for (const r of c.leaders) expect(r.required, k).toBeNull();
    }
  });

  it('every rate and per-game card uses its group constant, and every leader meets the scaled bar', () => {
    for (const c of data.cards.filter((x) => x.kind !== 'total')) {
      const [constant] = expected[c.unit];
      expect(c.minimum_constant, c.key).toBe(constant);
      expect(c.minimum_full_season, c.key).toBe(configInt(constant));
      for (const r of c.leaders) {
        const required = (c.minimum_full_season as number) * r.team_games_played / base;
        // required is published rounded to 0.1
        expect(Math.abs((r.required as number) - required), `${c.key} ${r.player}`).toBeLessThanOrEqual(0.05 + 1e-9);
        expect(r.sample as number, `${c.key} ${r.player}`).toBeGreaterThanOrEqual((r.required as number) - 1e-9);
      }
    }
  });

  it('records the study commit the definitions match', () => {
    expect(data.methods.study_source_commit).toBe('75998e2d55f705d76f4ee4530829d01f81122894');
    expect(configText).toContain('75998e2d55f705d76f4ee4530829d01f81122894');
  });
});

describe('ranking, notes and empty cards', () => {
  it('ranks highest first, except sack rate and interception rate (lowest first)', () => {
    expect(data.cards.filter((c) => c.lower_is_better).map((c) => c.key).sort()).toEqual([...LOWER].sort());
    for (const c of data.cards) {
      const v = c.leaders.map((r) => r.value);
      for (let i = 1; i < v.length; i++) {
        if (c.lower_is_better) expect(v[i], c.key).toBeGreaterThanOrEqual(v[i - 1]);
        else expect(v[i], c.key).toBeLessThanOrEqual(v[i - 1]);
      }
      c.leaders.forEach((r, i) => {
        if (i === 0) expect(r.rank).toBe(1);
        else expect(r.rank).toBe(r.value === c.leaders[i - 1].value ? c.leaders[i - 1].rank : i + 1);
      });
    }
  });

  it('flags the noisy stats only', () => {
    expect(data.cards.filter((c) => c.noise_note).map((c) => c.key).sort()).toEqual([...NOISE].sort());
    for (const c of data.cards) expect(Boolean(c.noise_note_text), c.key).toBe(c.noise_note);
  });

  it('only total EPA is model-based (pipeline only); the methods note says how it is credited', () => {
    expect(data.cards.filter((c) => c.refresh === 'pipeline_only').map((c) => c.key)).toEqual(['total_epa']);
    expect(data.methods.impact_note).toMatch(/qb_epa/);
    expect(data.methods.impact_note).toMatch(/designed carries/);
    expect(data.methods.impact_note).toMatch(/targets/);
  });

  it('each card has a through date, or a reason when it has none', () => {
    for (const c of data.cards) {
      if (c.through_date === null) expect(c.through_date_null_reason, c.key).toBeTruthy();
    }
  });

  it('status matches the leaders list; empty cards say "Not enough games yet" or give a reason', () => {
    for (const c of data.cards) {
      expect(c.qualified_count, c.key).toBeGreaterThanOrEqual(c.leaders.length);
      if (c.status === 'ok') {
        expect(c.leaders.length, c.key).toBeGreaterThan(0);
        expect(c.status_text, c.key).toBeNull();
      } else {
        expect(c.leaders, c.key).toEqual([]);
        expect(c.null_reason, c.key).toBeTruthy();
        if (c.status === 'not_enough_games') expect(c.status_text).toBe('Not enough games yet');
      }
    }
  });

  it('PFR-sourced cards are null with a reason when unavailable, never filled from another source', () => {
    for (const k of ['rush_yac', 'pressures']) {
      const c = byKey[k];
      expect(c.source, k).toMatch(/load_pfr_advstats/);
      if (c.status === 'unavailable') {
        expect(c.leaders).toEqual([]);
        expect(c.through_date).toBeNull();
      }
    }
  });

  it('has no betting vocabulary and no methodology link', () => {
    const text = JSON.stringify(data).toLowerCase();
    expect(text).not.toMatch(/\b(odds|lines?|spreads?|picks?|props?|wagers?|edges?|betting|sportsbook|moneyline)\b/);
    expect(text).not.toMatch(/methodology|https?:\/\//);
  });
});
