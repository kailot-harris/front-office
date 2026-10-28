/**
 * Runtime schemas for every dataset in `public/data/`.
 *
 * `lib/types.ts` describes these shapes to the compiler, but the files are
 * produced by R (`tools/export_web_datasets.R`) and read with a bare
 * `JSON.parse(...) as T` cast in `lib/data.ts` — so TypeScript proves nothing
 * about them at runtime. These schemas are the actual enforcement point.
 *
 * They are deliberately STRICTER than `lib/types.ts` in two ways:
 *   1. numeric ranges are bounded (probabilities in [0,1], rates in [0,100], ...)
 *   2. `.strict()` rejects unexpected keys, so a field added upstream in R
 *      shows up as a test failure rather than silently going unrendered.
 */
import { z } from 'zod';
import { LEAGUE } from '../helpers/datasets';

const prob = z.number().min(0).max(1);
const pct100 = z.number().min(0).max(100);
const teamCode = z.string().regex(/^[A-Z]{2,3}$/, 'team code must be 2-3 uppercase letters');
const conference = z.enum(['AFC', 'NFC']);
const division = z.enum([
  'AFC East', 'AFC North', 'AFC South', 'AFC West',
  'NFC East', 'NFC North', 'NFC South', 'NFC West',
]);
const isoishDate = z.string().regex(/^\d{4}-\d{2}-\d{2}/, 'expected a YYYY-MM-DD prefix');
const isoUtcStamp = z.string().datetime();

/**
 * Full letter-grade ladder the upstream coaching export can emit, including
 * minus grades. `lib/types.ts` currently declares a narrower union; see
 * tests/contracts/types-vs-data.test.ts.
 */
export const TIMEOUT_GRADES = [
  'A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D+', 'D', 'D-', 'F',
] as const;

export const teamStandingSchema = z.object({
  team: teamCode,
  team_name: z.string().min(3),
  conference,
  division,
  rank: z.number().int().min(1).max(32),
  games_played: z.number().int().min(0).max(LEAGUE.SEASON_GAMES),
  // Schedule-derived twin of games_played (issue #44), published by export_web_datasets.R
  // straight off CACHE_SCHEDULES. Same bounds; invariants.test.ts asserts the two are equal.
  schedule_games_completed: z.number().int().min(0).max(LEAGUE.SEASON_GAMES),
  power_rating: z.number().finite(),
  prior_season_rating: z.number().finite(),
  off_epa_roll: z.number().min(-1).max(1),
  def_epa_roll: z.number().min(-1).max(1),
  net_epa_roll: z.number().min(-2).max(2),
  points_for: z.number().int().min(0),
  points_against: z.number().int().min(0),
  point_diff: z.number().int(),
  win_pct_pyth: prob,
  projected_wins: z.number().min(0).max(17),
  wins_p10: z.number().min(0).max(17),
  wins_p90: z.number().min(0).max(17),
  playoff_prob: prob,
  division_title_prob: prob,
  first_round_bye_prob: prob,
  conf_champ_prob: prob,
  super_bowl_prob: prob,
}).strict();

export const standingsDatasetSchema = z.object({
  generated_at: isoUtcStamp,
  season: z.number().int().min(2020).max(2100),
  total_teams: z.number().int(),
  teams: z.array(teamStandingSchema),
}).strict();

export const matchupGameSchema = z.object({
  game_id: z.string().min(4),
  season: z.number().int(),
  week: z.number().int().min(1).max(22),
  gameday: isoishDate,
  weekday: z.enum(['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']),
  gametime: z.string().regex(/^\d{2}:\d{2}$/, 'expected HH:MM'),
  home_team: teamCode,
  home_team_name: z.string().min(3),
  away_team: teamCode,
  away_team_name: z.string().min(3),
  home_power_rating: z.number().finite(),
  away_power_rating: z.number().finite(),
  projected_margin: z.number().min(-60).max(60),
  projected_spread: z.number().min(-60).max(60),
  projected_total: z.number().min(20).max(80),
  home_win_prob: prob,
  away_win_prob: prob,
  home_rest_days: z.number().int().min(0).max(30),
  away_rest_days: z.number().int().min(0).max(30),
  rest_diff: z.number().int().min(-30).max(30),
  home_travel_miles: z.number().min(0).max(12000),
  away_travel_miles: z.number().min(0).max(12000),
  key_number_flag: z.string(),
  // The R export emits JSON `null` (not an absent key) for games that have not
  // been played. `lib/types.ts` declares these as `?: number` / `?: string`,
  // i.e. `undefined`-able but NOT null-able — so at runtime these fields hold a
  // value the declared type says is impossible. Consumers must therefore use
  // `=== true` / `!= null` style guards, never a bare `!== undefined`.
  is_completed: z.boolean().optional(),
  home_score: z.number().int().min(0).max(100).nullable().optional(),
  away_score: z.number().int().min(0).max(100).nullable().optional(),
  actual_winner: z.string().nullable().optional(),
  prediction_correct: z.boolean().nullable().optional(),
}).strict();

export const matchupsDatasetSchema = z.object({
  generated_at: isoUtcStamp,
  active_week: z.number().int().min(1).max(22),
  available_weeks: z.array(z.number().int().min(1).max(22)).nonempty(),
  total_games: z.number().int().min(0),
  matchups: z.array(matchupGameSchema),
}).strict();

export const teamEpaProfileSchema = z.object({
  generated_at: isoUtcStamp,
  team: teamCode,
  team_name: z.string().min(3),
  conference,
  division,
  games_in_sample: z.number().int().min(0).max(17),
  off_epa_per_play: z.number().min(-1).max(1),
  def_epa_per_play: z.number().min(-1).max(1),
  net_epa_per_play: z.number().min(-2).max(2),
  // NOTE: these five pairs are PERCENTAGE POINTS (0-100), not proportions.
  // TeamsClient renders them with `.toFixed(1)%` and no *100, so a future
  // upstream switch to proportions would silently show "0.5%" instead of "50%".
  off_success_rate: pct100,
  def_success_rate: pct100,
  off_cpoe: z.number().min(-25).max(25),
  off_early_down_epa: z.number().min(-1).max(1),
  off_money_down_epa: z.number().min(-2).max(2),
  def_early_down_epa: z.number().min(-1).max(1),
  def_money_down_epa: z.number().min(-2).max(2),
  off_redzone_success: pct100,
  def_redzone_success: pct100,
  off_explosive_rate: pct100,
  def_explosive_rate: pct100,
}).strict();

export const playoffSeedSchema = z.object({
  seed: z.number().int().min(1).max(7),
  team: teamCode,
  team_name: z.string().min(3),
  division,
  role: z.string().min(1),
  win_pct: prob,
  power_rating: z.number().finite(),
  wild_card_win_prob: prob,
  divisional_win_prob: prob,
  conf_champ_win_prob: prob,
  super_bowl_win_prob: prob,
}).strict();

export const playoffBubbleSchema = z.object({
  team: teamCode,
  team_name: z.string().min(3),
  division,
  playoff_prob: prob,
}).strict();

export const playoffDatasetSchema = z.object({
  generated_at: isoUtcStamp,
  season: z.number().int(),
  n_simulations: z.number().int().min(1),
  seeding_method: z.string().min(1),
  afc_seeds: z.array(playoffSeedSchema).length(7),
  nfc_seeds: z.array(playoffSeedSchema).length(7),
  afc_bubble: z.array(playoffBubbleSchema),
  nfc_bubble: z.array(playoffBubbleSchema),
}).strict();

export const qbProfileSchema = z.object({
  generated_at: isoUtcStamp,
  player_name: z.string().min(2),
  team: teamCode,
  jersey_number: z.number().int().min(0).max(99),
  years_exp: z.number().int().min(0).max(30),
  college: z.string(),
  depth_position: z.string().min(1),
  headshot_url: z.string().url(),
  off_epa_roll: z.number().min(-2).max(2),
  off_cpoe_roll: z.number().min(-30).max(30),
  status: z.string().min(1),
  is_starter: z.boolean().optional(),
  attempts_2026: z.number().int().min(0).optional(),
}).strict();

export const calibrationBinSchema = z.object({
  bin: z.string().min(1),
  predicted_mid: prob,
  actual_win_rate: prob,
  count: z.number().int().min(0),
}).strict();

/**
 * `model_diagnostics.json` ships several fields as ARRAYS (one entry per
 * graded snapshot) even though a reader might expect a scalar. `lib/types.ts`
 * models that with `number | number[]`; the schema mirrors that union so it
 * cannot quietly collapse to one side without a test noticing.
 */
const numberOrArray = z.union([z.number(), z.array(z.number()).nonempty()]);
const stringOrArray = z.union([z.string(), z.array(z.string()).nonempty()]);

export const diagnosticsDatasetSchema = z.object({
  generated_at: isoUtcStamp,
  season: z.union([z.number().int(), z.array(z.number().int()).nonempty()]),
  last_evaluated: stringOrArray,
  n_games_graded: numberOrArray,
  overall_accuracy: numberOrArray,
  overall_brier: numberOrArray,
  overall_logloss: numberOrArray,
  brier_baseline: z.number().min(0).max(1),
  brier_improvement: numberOrArray,
  margin_sigma: z.number().min(5).max(25),
  home_field_adv: z.number().min(0).max(6),
  ensemble_weights: z.object({
    ridge_massey: prob,
    elo_dynamic: prob,
    market_blend: prob,
  }).strict(),
  calibration_curve: z.array(calibrationBinSchema).nonempty(),
}).strict();

export const visualMediaItemSchema = z.object({
  generated_at: isoUtcStamp,
  filename: z.string().regex(/^[\w.\-]+\.(gif|png|jpg|jpeg|webp)$/i, 'unsafe or unexpected filename'),
  title: z.string().min(1),
  category: z.enum(['standings', 'epa', 'elo', 'heatmaps', 'players', 'general']),
  description: z.string(),
  type: z.enum(['gif', 'image']),
  size_bytes: z.number().int().min(1),
}).strict();

export const coachProfileSchema = z.object({
  team: teamCode,
  head_coach: z.string().min(2),
  tenure_years: z.number().min(0).max(40),
  offensive_coordinator: z.string().min(1),
  defensive_coordinator: z.string().min(1),
  play_caller: z.enum(['Head Coach', 'Offensive Coordinator', 'Defensive Coordinator']),
  offensive_play_caller: z.enum(['Head Coach', 'Offensive Coordinator']).optional(),
  defensive_play_caller: z.enum(['Head Coach', 'Defensive Coordinator']).optional(),
  fourth_down_aggression_index: z.number().min(0).max(100),
  pass_rate_over_expected: z.number().min(-20).max(20),
  early_down_pass_rate: pct100,
  play_action_rate: pct100,
  pace_seconds_per_play: z.number().min(15).max(45),
  offensive_scheme: z.string().min(1),
  defensive_scheme: z.string().min(1),
  timeout_management_grade: z.enum(TIMEOUT_GRADES),
  challenge_win_pct: pct100,
  career_record: z.string().regex(/^\d+-\d+(-\d+)?$/, 'expected W-L or W-L-T'),
  super_bowl_wins: z.number().int().min(0).max(10),
}).strict();

export const positionalSpendingItemSchema = z.object({
  apy: z.number().min(0),
  pct: pct100,
  count: z.number().int().min(0),
}).strict();

export const topPaidPlayerSchema = z.object({
  player: z.string().min(2),
  position: z.string().min(1),
  apy: z.number().min(0),
  guaranteed: z.number().min(0),
}).strict();

export const teamCapProfileSchema = z.object({
  team: teamCode,
  total_active_contracts: z.number().int().min(0).max(120),
  total_active_apy: z.number().min(0),
  total_guaranteed: z.number().min(0),
  positional_spending: z.record(z.string(), positionalSpendingItemSchema),
  top_paid_players: z.array(topPaidPlayerSchema),
}).strict();

export const leagueTopContractSchema = z.object({
  player: z.string().min(2),
  position: z.string().min(1),
  pos_group: z.string().min(1),
  team: teamCode,
  value: z.number().min(0),
  apy: z.number().min(0),
  guaranteed: z.number().min(0),
  apy_cap_pct: pct100,
  years: z.number().int().min(1).max(12),
  year_signed: z.number().int().min(2010).max(2100),
}).strict();

export const salaryCapDatasetSchema = z.object({
  generated_at: isoUtcStamp,
  season: z.number().int(),
  cap_ceiling: z.number().min(100).max(1000),
  source: z.string().min(1),
  last_updated: z.string().min(4),
  teams: z.array(teamCapProfileSchema),
  top_league_contracts: z.array(leagueTopContractSchema),
}).strict();

/** Filename -> schema, so one test can iterate every shipped dataset. */
export const DATASET_SCHEMAS = {
  'standings_projections.json': standingsDatasetSchema,
  'matchups_current_week.json': matchupsDatasetSchema,
  'team_epa_profiles.json': z.array(teamEpaProfileSchema),
  'playoff_picture.json': playoffDatasetSchema,
  'player_qb_profiles.json': z.array(qbProfileSchema),
  'model_diagnostics.json': diagnosticsDatasetSchema,
  'visual_media_index.json': z.array(visualMediaItemSchema),
  'coaching_profiles.json': z.array(coachProfileSchema),
  'salary_cap_profiles.json': salaryCapDatasetSchema,
} as const;
