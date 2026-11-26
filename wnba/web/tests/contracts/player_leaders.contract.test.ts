/**
 * player_leaders.json contract (WNBA_analytics#268; the leaders panel on /players).
 *
 * Written by build_player_leaders.R (09:00 pipeline) and patched by
 * tools/refresh_live_results.R (evening refreshes). Checks the shape the panel
 * relies on and the rules from the issue: every stat present and grouped, each
 * full-season minimum equal to its config.R constant, every listed player at or
 * above the scaled minimum (minimum x team games played / 44), ranking order
 * (lowest leads for turnovers and turnover rate), top 10 per position filter,
 * a through date per card, the noise-note flags, "Not enough games yet" for empty
 * cards with a reason, and no betting vocabulary anywhere in the file.
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
const POSITIONS = ['all', 'G', 'F', 'C'] as const;
const EXPECTED_CARDS: Record<string, string> = {
  pts: 'scoring', fg3m: 'scoring', usg_pct: 'scoring',
  fg_pct: 'shooting', fg3_pct: 'shooting', ft_pct: 'shooting', efg_pct: 'shooting', ts_pct: 'shooting',
  ast: 'playmaking', ast_pct: 'playmaking', tov: 'playmaking', tov_pct: 'playmaking',
  reb: 'rebounding', oreb: 'rebounding', orb_pct: 'rebounding', drb_pct: 'rebounding',
  stl: 'defense', blk: 'defense',
  orapm: 'impact', drapm: 'impact', total_rapm: 'impact',
};
const NOISE = new Set(['fg3_pct', 'efg_pct', 'ts_pct', 'orapm', 'drapm', 'total_rapm']);
const LOWER = new Set(['tov', 'tov_pct']);

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
    position_group: z.enum(['G', 'F', 'C']).nullable().optional(),
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
    group: z.enum(['scoring', 'shooting', 'playmaking', 'rebounding', 'defense', 'impact']),
    kind: z.enum(['per_game', 'shooting', 'rate', 'rapm']),
    format: z.enum(['per_game', 'pct', 'rate', 'rapm']),
    lower_is_better: z.boolean(),
    unit: z.enum(['games', 'fga', 'fg3a', 'fta', 'minutes', 'possessions_per_side']),
    unit_label: z.string().min(1),
    minimum_full_season: z.number().positive(),
    minimum_constant: z.string().regex(/^LEADERS_MIN_/),
    minimum_minutes_full_season: z.number().positive().nullable().optional(),
    minimum_minutes_constant: z.string().regex(/^LEADERS_MIN_MINUTES_/).nullable().optional(),
    through_date: z.string().regex(DATE_RE).nullable(),
    through_date_null_reason: z.string().min(1).nullable().optional(),
    noise_note: z.boolean(),
    noise_note_text: z.string().min(1).nullable().optional(),
    status: z.enum(['ok', 'not_enough_games']),
    status_text: z.string().nullable().optional(),
    null_reason: z.string().min(1).nullable().optional(),
    candidates: z.number().int().nonnegative(),
    qualified_count: z.object({ all: z.number().int(), G: z.number().int(), F: z.number().int(), C: z.number().int() }).strict(),
    leaders: z.object({ all: z.array(RowSchema), G: z.array(RowSchema), F: z.array(RowSchema), C: z.array(RowSchema) }).strict(),
  })
  .strict();

const PayloadSchema = z
  .object({
    schema_version: z.literal(1),
    generated_at: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/),
    season: z.string().regex(/^\d{4}$/),
    through_date: z.string().regex(DATE_RE).nullable(),
    position_filters: z.array(z.object({ key: z.enum(POSITIONS), label: z.string() }).strict()).length(4),
    groups: z.array(z.object({ key: z.string(), label: z.string() }).strict()).length(6),
    cards: z.array(CardSchema),
    methods: z.object({
      scaling_rule: z.string(),
      scaling_text: z.string(),
      traded_players: z.string().min(1),
      position_note: z.string().min(1),
      study_source_commit: z.string().regex(/^[0-9a-f]{40}$/),
      base_games: z.number().int(),
      minimums: z.array(z.object({ key: z.string(), minimum_full_season: z.number(), constant: z.string() }).passthrough()),
    }).passthrough(),
    sources: z.record(z.string()),
    season_totals: z.object({
      description: z.string(),
      game_ids: z.array(z.string()),
      team_games: z.object({ team_id: z.array(z.string()), team: z.array(z.string()), games: z.array(z.number()) }).strict(),
      players: z.record(z.array(z.union([z.string(), z.number(), z.null()]))),
    }).strict(),
  })
  .strict();

describe('player_leaders.json', () => {
  it('matches the schema', () => {
    const r = PayloadSchema.safeParse(DATA);
    expect(r.success, r.success ? '' : JSON.stringify(r.error.issues.slice(0, 5), null, 2)).toBe(true);
  });

  it('has every #268 stat once, in its group, with the right ranking direction and noise flag', () => {
    const keys = DATA.cards.map((c: { key: string }) => c.key);
    expect(new Set(keys).size).toBe(keys.length);
    expect([...keys].sort()).toEqual(Object.keys(EXPECTED_CARDS).sort());
    for (const c of DATA.cards) {
      expect(c.group, c.key).toBe(EXPECTED_CARDS[c.key]);
      expect(c.lower_is_better, c.key).toBe(LOWER.has(c.key));
      expect(c.noise_note, c.key).toBe(NOISE.has(c.key));
      if (c.noise_note) expect(c.noise_note_text, c.key).toBeTruthy();
    }
  });

  it('uses the config.R minimums, the 44-game base and the study commit', () => {
    expect(BASE).toBe(44);
    expect(DATA.methods.base_games).toBe(BASE);
    expect(DATA.methods.study_source_commit).toBe(
      CONFIG_R.match(/^LEADERS_STUDY_SOURCE_COMMIT\s*<-\s*"([0-9a-f]{40})"/m)![1],
    );
    for (const c of DATA.cards) {
      expect(c.minimum_full_season, c.key).toBe(configConstant(c.minimum_constant));
      if (c.key === 'tov') {
        expect(c.minimum_minutes_constant).toBe('LEADERS_MIN_MINUTES_TOV_PER_GAME');
        expect(c.minimum_minutes_full_season).toBe(configConstant(c.minimum_minutes_constant));
      } else {
        expect(c.minimum_minutes_full_season ?? null, c.key).toBeNull();
      }
    }
  });

  it('lists only players at or above the scaled minimum, ranked in the card direction, top 10 per filter', () => {
    for (const c of DATA.cards) {
      for (const p of POSITIONS) {
        const rows = c.leaders[p];
        expect(rows.length, `${c.key}/${p}`).toBeLessThanOrEqual(10);
        expect(rows.length, `${c.key}/${p}`).toBe(Math.min(10, c.qualified_count[p]));
        for (let i = 0; i < rows.length; i++) {
          const r = rows[i];
          const scaled = (c.minimum_full_season * r.team_games_played) / BASE;
          expect(Math.abs(r.required - scaled), `${c.key} ${r.player} required`).toBeLessThanOrEqual(0.051);
          expect(r.sample + 0.05, `${c.key} ${r.player} sample`).toBeGreaterThanOrEqual(r.required);
          if (p !== 'all') expect(r.position_group, `${c.key}/${p}`).toBe(p);
          if (i > 0) {
            const prev = rows[i - 1];
            if (c.lower_is_better) expect(r.value).toBeGreaterThanOrEqual(prev.value);
            else expect(r.value).toBeLessThanOrEqual(prev.value);
            expect(r.rank).toBeGreaterThanOrEqual(prev.rank);
            if (r.value === prev.value) expect(r.rank).toBe(prev.rank);
          } else {
            expect(r.rank).toBe(1);
          }
        }
      }
    }
  });

  it('gives every box-score card a through date, and empty cards the panel text and a reason', () => {
    for (const c of DATA.cards) {
      if (c.kind !== 'rapm') expect(c.through_date, c.key).toBe(DATA.through_date);
      else if (c.through_date === null) expect(c.through_date_null_reason, c.key).toBeTruthy();
      const empty = c.qualified_count.all === 0;
      expect(c.status, c.key).toBe(empty ? 'not_enough_games' : 'ok');
      if (empty) {
        expect(c.status_text).toBe('Not enough games yet');
        expect(c.null_reason, c.key).toBeTruthy();
      }
    }
  });

  it('never shows a past-season RAPM fit', () => {
    const season = DATA.season as string;
    for (const c of DATA.cards.filter((x: { kind: string }) => x.kind === 'rapm')) {
      if (c.status === 'ok') expect(DATA.sources.rapm, 'RAPM shown from a different season').toContain(season);
    }
  });

  it('season totals agree with the cards (team games, game ids)', () => {
    const tg = DATA.season_totals.team_games;
    expect(tg.team_id.length).toBe(tg.games.length);
    const maxGames = Math.max(...tg.games);
    for (const c of DATA.cards) for (const r of c.leaders.all) expect(r.team_games_played).toBeLessThanOrEqual(maxGames);
    expect(new Set(DATA.season_totals.game_ids).size).toBe(DATA.season_totals.game_ids.length);
  });

  it('carries no betting vocabulary', () => {
    expect(RAW).not.toMatch(FORBIDDEN_BETTING_RE);
  });
});
