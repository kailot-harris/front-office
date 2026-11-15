/**
 * Types for web/public/data/games/<game_id>.json, per Matchup Game Detail &
 * Explainability Specification (v3 §3).
 *
 * Naming convention: identity fields shared across sports follow
 * cross_sport_schema_spec.md and are camelCase (`teamAbbr`, `teamName`,
 * `playerId`, `playerName`). Every other field is snake_case, matching
 * `matchups_slates.json`.
 */

export interface GameDetailEnvelope {
  schema_version: '1.0';
  /** ISO-8601 UTC; changes only when the payload changes. */
  generated_at: string;
  sport: 'nba' | 'wnba' | 'nfl' | 'mlb';
  endpoint: 'game_detail';
  /** Matches matchups_slates.json, e.g. 2027. */
  season: number;
  /** Human-facing span, e.g. "2026-2027". */
  season_label: string;
  data: GameDetailPayload;
}

export interface GameDetailPayload {
  game_id: string;
  /** Matches MatchupGame.slate. */
  slate: number;
  slate_label: string;
  game_date: string;
  weekday: string;
  is_completed: boolean;
  /** Always true for a file that exists in Phase 1. */
  has_box_score: boolean;

  away_team: GameTeamSummary;
  home_team: GameTeamSummary;

  /** Phase 1 */
  efficiency_factors: EfficiencyFactorItem[] | null;
  /** Phase 1 */
  context_splits: ContextSplitItem[] | null;
  box_score: {
    away_totals: TeamBoxTotals;
    home_totals: TeamBoxTotals;
    away_players: PlayerBoxRow[];
    home_players: PlayerBoxRow[];
    away_inactive: InactivePlayerRow[];
    home_inactive: InactivePlayerRow[];
    top_performers: TopPerformerItem[];
  } | null;

  /** Phase 2; null in Phase 1. */
  explainability: GameExplainabilityPayload | null;
  /** Phase 3; null until then. */
  game_flow: GameFlowPayload | null;
}

export interface GameTeamSummary {
  teamAbbr: string;
  teamName: string;
  score: number | null;
  is_winner: boolean | null;
}

export interface EfficiencyFactorItem {
  key: 'efg_pct' | 'ts_pct' | 'tov_pct' | 'oreb_pct' | 'fta_rate' | 'ortg' | 'drtg' | 'pace';
  label: string;
  away_value: number | null;
  home_value: number | null;
  unit: 'pct' | 'per100fga' | 'per100poss' | 'poss48';
  /** False for tov_pct and drtg, null for pace. */
  higher_is_better: boolean | null;
  /** States the formula in words. */
  description: string;
}

export interface ContextSplitItem {
  key: string;
  label: string;
  away_value: number | null;
  home_value: number | null;
}

export interface TeamBoxTotals {
  minutes: number;
  points: number;
  fgm: number;
  fga: number;
  fg_pct: number | null;
  fg3m: number;
  fg3a: number;
  fg3_pct: number | null;
  ftm: number;
  fta: number;
  ft_pct: number | null;
  oreb: number;
  dreb: number;
  reb: number;
  ast: number;
  stl: number;
  blk: number;
  tov: number;
  team_tov: number;
  total_tov: number;
  pf: number;
  efg_pct: number | null;
  ts_pct: number | null;
  possessions_est: number | null;
  ortg: number | null;
  drtg: number | null;
  pace: number | null;
}

export interface PlayerBoxRow {
  playerId: string;
  playerName: string;
  short_name: string;
  jersey: string | null;
  position: string | null;
  starter: boolean;
  minutes: number;
  points: number;
  oreb: number;
  dreb: number;
  reb: number;
  ast: number;
  stl: number;
  blk: number;
  tov: number;
  pf: number;
  plus_minus: number | null;
  fgm: number;
  fga: number;
  fg_pct: number | null;
  fg3m: number;
  fg3a: number;
  fg3_pct: number | null;
  ftm: number;
  fta: number;
  ft_pct: number | null;
  efg_pct: number | null;
  ts_pct: number | null;
  game_score: number;
}

export interface InactivePlayerRow {
  playerId: string;
  playerName: string;
  position: string | null;
  /** As given by the source; null when the source gives none. */
  reason: string | null;
}

/**
 * Selection rule: top 3 per game by game_score among players with minutes > 0;
 * ties broken by points, then minutes, then playerName.
 */
export interface TopPerformerItem {
  teamAbbr: string;
  playerId: string;
  playerName: string;
  points: number;
  reb: number;
  ast: number;
  game_score: number;
}

export interface GameExplainabilityPayload {
  projection_basis: 'primary_ensemble' | 'logged_model_margin' | 'margin_from_logged_win_prob' | null;
  /** Home perspective. */
  predicted_margin: number | null;
  predicted_home_win_prob: number | null;
  sigma_game: number | null;
  /** Non-null only when component values for THIS forecast exist (section 4.2). */
  margin_waterfall: MarginWaterfallStep[] | null;
  /** Non-null whenever the number comes from the log; log_source says what kind of row. */
  logged_forecast: {
    prediction_timestamp: string;
    log_source: 'LOGGED_PREGAME' | 'BACKTEST_PREWEEK' | 'BACKTEST_SEEDED';
    brier_component: number | null;
    log_loss_component: number | null;
  } | null;
  entering_baselines: EnteringBaseline[] | null;
  /** Secondary diagnostic TreeSHAP attribution payload; optional/nullable until emitted. */
  xgboost_shap?: XgboostShapPayload | null;
}

export interface MarginWaterfallStep {
  key: 'bottom_up' | 'rapm' | 'shot_fatigue' | 'embeddings' | 'home_court' | 'schedule' | 'rounding';
  label: string;
  /** Signed, home perspective; steps sum to predicted_margin. */
  points: number;
  /** E.g. rest days and travel for the schedule step. */
  detail: string | null;
}

export interface EnteringBaseline {
  teamAbbr: string;
  prior_games_n: number;
  factors: {
    key: string;
    entering: number | null;
    realized: number | null;
    difference: number | null;
  }[];
}

/** The 13 differential/similarity predictors consumed by the secondary XGBoost model. */
export type XgboostShapFactorKey =
  | 'diff_roll_pts'
  | 'diff_roll_efg'
  | 'diff_roll_ts'
  | 'diff_roll_tovp'
  | 'diff_roll_oreb'
  | 'diff_roll_dreb'
  | 'diff_roll_ast'
  | 'diff_roll_stl'
  | 'diff_roll_blk'
  | 'diff_days_rest'
  | 'diff_fatigue_index'
  | 'diff_is_b2b'
  | 'style_similarity';

/** Per-feature TreeSHAP attribution row for a single matchup prediction. */
export interface XgboostShapFactor {
  feature: XgboostShapFactorKey;
  label: string;
  feature_value: number;
  z_score: number;
  shap_log_odds: number;
  shap_prob_approx: number;
}

/** Secondary diagnostic XGBoost TreeSHAP decomposition payload (home perspective). */
export interface XgboostShapPayload {
  model_id: 'xgboost_feature_fusion_v1';
  model_label: string;
  train_seasons_label: string;
  window_games: number;
  away_prior_games_n: number;
  home_prior_games_n: number;
  base_value_log_odds: number;
  total_log_odds: number;
  predicted_home_win_prob: number;
  factors: XgboostShapFactor[];
}

export interface GameFlowPayload {
  linescore: {
    periods: string[];
    away_period_pts: number[];
    home_period_pts: number[];
  };
  largest_lead_home: number;
  largest_lead_away: number;
  lead_changes: number;
  times_tied: number;
  timeline: {
    elapsed_sec: number;
    period: number;
    home_score: number;
    away_score: number;
    margin: number;
    model_home_win_prob: number | null;
  }[];
}
