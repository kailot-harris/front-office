/**
 * player_leaders.json contract (MLB-Analytics#163; leaders panel on /players).
 *
 * Written by build_player_leaders.R and patched by tools/refresh_live_results.R.
 * Verifies schema, 17 MLB stats across batting & pitching, config.R minimums,
 * scaled qualifying rule (minimum * team_games_played / 162), ranking order,
 * top-10 cap, through dates, and zero betting vocabulary.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import { DATA_DIR } from '../helpers/datasets';

const FILE = path.join(DATA_DIR, 'player_leaders.json');
const RAW = fs.readFileSync(FILE, 'utf-8');
const DATA = JSON.parse(RAW);
const CONFIG_R = fs.readFileSync(path.join(process.cwd(), '..', 'config.R'), 'utf-8');

const FORBIDDEN_BETTING_RE =
  /\b(odds|lines?|spreads?|picks?|props?|wagers?|edges?|bets?|betting|sportsbook|moneyline|parlay|vig|juice|handicap)\b/i;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const POSITIONS = ['all', 'IF', 'OF', 'C_DH', 'SP', 'RP'] as const;

const EXPECTED_CARDS: Record<string, string> = {
  avg: 'batting',
  obp: 'batting',
  slg: 'batting',
  ops: 'batting',
  hr: 'batting',
  sb: 'batting',
  woba: 'batting',
  k_pct: 'batting',
  bb_pct: 'batting',
  barrel_pct: 'batting',
  era: 'pitching',
  fip: 'pitching',
  whip: 'pitching',
  p_k_pct: 'pitching',
  p_bb_pct: 'pitching',
  ip: 'pitching',
  saves: 'pitching',
};
const LOWER = new Set(['k_pct', 'era', 'fip', 'whip', 'p_bb_pct']);

function configConstant(name: string): number {
  const m = CONFIG_R.match(new RegExp(`^${name}\\s*<-\\s*(\\d+)L?\\s*$`, 'm'));
  if (!m) throw new Error(`config.R has no ${name}`);
  return Number(m[1]);
}
const BASE = configConstant('LEADERS_FULL_SEASON_GAMES');

const RowSchema = z
  .object({
    rank: z.number().int().positive(),
    player_id: z.string().min(1),
    player: z.string().min(1),
    team: z.string().min(2),
    position: z.string().nullable().optional(),
    position_group: z.enum(['IF', 'OF', 'C_DH', 'SP', 'RP']).nullable().optional(),
    value: z.number().finite(),
    sample: z.number().nonnegative(),
    required: z.number().nonnegative(),
    team_games_played: z.number().int().positive(),
  })
  .strict();

const CardSchema = z
  .object({
    key: z.string(),
    label: z.string().min(1),
    group: z.enum(['batting', 'pitching']),
    kind: z.enum(['rate', 'counting', 'statcast']),
    format: z.enum(['avg', 'era', 'ip', 'pct', 'int']),
    lower_is_better: z.boolean(),
    unit: z.enum(['pa', 'bf', 'app', 'relief_app']),
    unit_label: z.string().min(1),
    minimum_full_season: z.number().positive(),
    minimum_constant: z.string().regex(/^LEADERS_MIN_/),
    through_date: z.string().regex(DATE_RE).nullable(),
    through_date_null_reason: z.string().min(1).nullable().optional(),
    noise_note: z.boolean(),
    noise_note_text: z.string().min(1).nullable().optional(),
    status: z.enum(['ok', 'not_enough_games']),
    status_text: z.string().nullable().optional(),
    null_reason: z.string().min(1).nullable().optional(),
    candidates: z.number().int().nonnegative(),
    qualified_count: z
      .object({
        all: z.number().int(),
        IF: z.number().int(),
        OF: z.number().int(),
        C_DH: z.number().int(),
        SP: z.number().int(),
        RP: z.number().int(),
      })
      .strict(),
    leaders: z
      .object({
        all: z.array(RowSchema),
        IF: z.array(RowSchema),
        OF: z.array(RowSchema),
        C_DH: z.array(RowSchema),
        SP: z.array(RowSchema),
        RP: z.array(RowSchema),
      })
      .strict(),
  })
  .strict();

const PayloadSchema = z
  .object({
    schema_version: z.literal(1),
    generated_at: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/),
    season: z.string().regex(/^\d{4}$/),
    through_date: z.string().regex(DATE_RE).nullable(),
    position_filters: z.array(z.object({ key: z.enum(POSITIONS), label: z.string() }).strict()).length(6),
    groups: z.array(z.object({ key: z.enum(['batting', 'pitching']), label: z.string() }).strict()).length(2),
    cards: z.array(CardSchema),
    methods: z
      .object({
        scaling_rule: z.string(),
        scaling_text: z.string(),
        traded_players: z.string().min(1),
        position_note: z.string().min(1),
        study_source_commit: z.string().regex(/^[0-9a-f]{40}$/),
        base_games: z.number().int(),
        minimums: z.array(
          z.object({ key: z.string(), minimum_full_season: z.number(), constant: z.string() }).passthrough(),
        ),
      })
      .passthrough(),
    sources: z.record(z.string()),
    season_totals: z
      .object({
        description: z.string(),
        game_ids: z.array(z.string()),
        guts: z.record(z.number()),
        team_games: z
          .object({ team_id: z.array(z.string()), team: z.array(z.string()), games: z.array(z.number()) })
          .strict(),
        batters: z.record(z.array(z.union([z.string(), z.number(), z.null()]))),
        pitchers: z.record(z.array(z.union([z.string(), z.number(), z.null()]))),
      })
      .strict(),
  })
  .strict();

describe('player_leaders.json', () => {
  it('matches the schema', () => {
    const r = PayloadSchema.safeParse(DATA);
    expect(r.success, r.success ? '' : JSON.stringify(r.error.issues.slice(0, 5), null, 2)).toBe(true);
  });

  it('has all 17 MLB cards in batting and pitching groups', () => {
    expect(DATA.cards).toHaveLength(17);
    const byKey = Object.fromEntries(DATA.cards.map((c: { key: string; group: string }) => [c.key, c.group]));
    expect(byKey).toEqual(EXPECTED_CARDS);
  });

  it('matches config.R minimums and scaling rule', () => {
    expect(BASE).toBe(162);
    expect(DATA.methods.base_games).toBe(162);
    for (const c of DATA.cards) {
      expect(c.minimum_full_season).toBe(configConstant(c.minimum_constant));
      expect(c.lower_is_better).toBe(LOWER.has(c.key));
      for (const pos of POSITIONS) {
        const rows = c.leaders[pos];
        expect(rows.length).toBeLessThanOrEqual(10);
        for (let i = 0; i < rows.length; i++) {
          const row = rows[i];
          expect(row.sample).toBeGreaterThanOrEqual(row.required - 0.05);
          expect(row.required).toBeCloseTo((c.minimum_full_season * row.team_games_played) / BASE, 1);
          if (i > 0) {
            const prev = rows[i - 1];
            if (c.lower_is_better) expect(row.value).toBeGreaterThanOrEqual(prev.value - 1e-9);
            else expect(row.value).toBeLessThanOrEqual(prev.value + 1e-9);
          }
        }
      }
    }
  });

  it('contains zero betting vocabulary', () => {
    expect(FORBIDDEN_BETTING_RE.test(RAW)).toBe(false);
  });
});
