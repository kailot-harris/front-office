/**
 * Types for web/public/data/games/<game_id>.json, per NFL Matchup Game Detail &
 * Model Attribution Plan (v2 §4.1).
 *
 * Naming convention: identity fields follow cross-sport schema conventions and
 * are camelCase (`teamAbbr`, `teamName`, `playerId`, `playerName`). Every other
 * field is snake_case, matching matchups_current_week.json.
 */

export interface GameDetailEnvelope {
  schema_version: '1.0';
  /** ISO-8601 UTC; changes only when the payload changes. */
  generated_at: string;
  sport: 'nfl';
  endpoint: 'game_detail';
  season: number;
  season_label: string;
  game_id: string;
  data: NflGameDetailPayload;
}

export interface GameTeamSummary {
  teamAbbr: string;
  teamName: string;
  score: number | null;
  is_winner: boolean | null;
}

export interface NflGameForecast {
  projected_margin: number | null;
  home_win_prob: number | null;
  away_win_prob: number | null;
  home_power_rating: number | null;
  away_power_rating: number | null;
  prediction_correct: boolean | null;
}

export type NflEfficiencyFactorKey =
  | 'epa_per_play'
  | 'success_rate'
  | 'dropback_epa'
  | 'rush_epa'
  | 'cpoe'
  | 'yards_per_play'
  | 'early_down_epa'
  | 'late_down_success_rate';

export interface NflEfficiencyFactorItem {
  key: NflEfficiencyFactorKey;
  label: string;
  away_value: number | null;
  home_value: number | null;
  unit: 'epa' | 'pct' | 'yards';
  higher_is_better: boolean;
  description: string;
}

export interface NflTeamComparisonItem {
  stat_key: string;
  label: string;
  away_value: number | string | null;
  home_value: number | string | null;
}

export type NflBoxCategory = 'passing' | 'rushing' | 'receiving' | 'defense' | 'kicking';

export interface NflPlayerBoxRow {
  playerId: string;
  playerName: string;
  teamAbbr: string;
  position: string | null;
  categories: NflBoxCategory[];
  snap_pct: number | null;

  // Passing
  completions?: number;
  attempts?: number;
  passing_yards?: number;
  passing_tds?: number;
  passing_interceptions?: number;
  sacks_suffered?: number;
  sack_yards_lost?: number;
  passing_epa?: number | null;
  passing_cpoe?: number | null;

  // Rushing
  carries?: number;
  rushing_yards?: number;
  rushing_tds?: number;
  rushing_fumbles?: number;
  rushing_fumbles_lost?: number;
  rushing_first_downs?: number;
  rushing_epa?: number | null;

  // Receiving
  receptions?: number;
  targets?: number;
  receiving_yards?: number;
  receiving_tds?: number;
  receiving_fumbles?: number;
  receiving_fumbles_lost?: number;
  receiving_first_downs?: number;
  receiving_epa?: number | null;

  // Defense
  def_tackles_solo?: number;
  def_tackle_assists?: number;
  def_tackles_for_loss?: number;
  def_sacks?: number;
  def_qb_hits?: number;
  def_interceptions?: number;
  def_pass_defended?: number;
  def_fumbles_forced?: number;

  // Kicking
  fg_made?: number;
  fg_att?: number;
  fg_long?: number | null;
  pat_made?: number;
  pat_att?: number;
}

export interface CategoryLeader {
  category: NflBoxCategory;
  teamAbbr: string;
  playerId: string;
  playerName: string;
  stat_line: string;
}

export interface InjuryDesignationRow {
  playerId: string | null;
  playerName: string;
  position: string | null;
  designation: 'Out' | 'IR' | 'Doubtful' | 'Questionable';
  body_part: string | null;
  played: boolean;
}

export interface WaterfallStep {
  key: string;
  label: string;
  points: number;
  description?: string;
}

export interface PointsWaterfallPayload {
  projected_margin: number;
  home_win_prob: number;
  steps: WaterfallStep[];
  rounding: number;
  sigma: number;
  intercept?: number;
}

export interface ShapFactorItem {
  feature: string;
  label: string;
  value: number;
  shap_value: number;
}

export interface SecondaryModelOutOfSampleRecord {
  n_games: number;
  accuracy: number;
  brier: number;
  logloss: number;
}

export interface SecondaryModelSummary {
  model_id: string;
  model_label: string;
  model_win_prob: number;
  logit: number;
  base_value: number;
  factors: ShapFactorItem[];
  out_of_sample_record: SecondaryModelOutOfSampleRecord;
  agreement: 'agree' | 'differ';
}

export interface EfficiencyBaselineComparison {
  metric_key: string;
  metric_label: string;
  team_abbr?: string;
  entering_baseline: number | null;
  realized_value: number | null;
  delta: number | null;
  prior_games_n: number;
  is_low_sample: boolean;
}

export interface GameExplainabilityPayload {
  game_id: string;
  season: number;
  week: number;
  projection_basis?: 'primary_ensemble' | 'logged_pregame' | 'backtest_preweek' | null;
  predicted_margin?: number | null;
  predicted_home_win_prob?: number | null;
  waterfall: PointsWaterfallPayload;
  secondary_model: SecondaryModelSummary | null;
  entering_baselines: EfficiencyBaselineComparison[];
  divergence_note: string | null;
  margin_waterfall?: WaterfallStep[] | null;
}

export type NflGameExplainabilityPayload = GameExplainabilityPayload;

export interface WeeklyAttributionDataset {
  schema_version: '1.0';
  generated_at: string;
  season: number;
  week: number;
  games: GameExplainabilityPayload[];
}

export interface NflGameDetailPayload {
  game_id: string;
  season: number;
  season_label: string;
  week: number;
  week_label: string;
  gameday: string;
  weekday: string;
  gametime: string;
  is_completed: boolean;
  has_box_score: boolean;

  away_team: GameTeamSummary;
  home_team: GameTeamSummary;

  forecast: NflGameForecast | null;
  efficiency_factors: NflEfficiencyFactorItem[] | null;
  team_stats: NflTeamComparisonItem[] | null;
  leaders: CategoryLeader[] | null;

  box_score: {
    away_players: NflPlayerBoxRow[];
    home_players: NflPlayerBoxRow[];
  } | null;

  injury_designations: InjuryDesignationRow[] | null;
  explainability: GameExplainabilityPayload | null;
}
