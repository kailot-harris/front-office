// NFL Analytics Web Application — Core Data Types

export interface TeamStanding {
  team: string;
  team_name: string;
  conference: 'AFC' | 'NFC';
  division: string;
  rank: number;
  games_played: number;
  /**
   * Completed CURRENT_SEASON regular-season games for this team, counted independently
   * off CACHE_SCHEDULES by the R exporter (issue #44). `games_played` comes from the
   * model's team-stats path; this one comes from the schedule. They must be equal, and
   * `tests/contracts/invariants.test.ts` asserts that per team as a staleness gate.
   */
  schedule_games_completed: number;
  power_rating: number;
  prior_season_rating: number;
  off_epa_roll: number;
  def_epa_roll: number;
  net_epa_roll: number;
  points_for: number;
  points_against: number;
  point_diff: number;
  win_pct_pyth: number;
  projected_wins: number;
  wins_p10: number;
  wins_p90: number;
  playoff_prob: number;
  division_title_prob: number;
  first_round_bye_prob: number;
  conf_champ_prob: number;
  super_bowl_prob: number;
}

export interface StandingsDataset {
  season: number;
  generated_at: string;
  total_teams: number;
  teams: TeamStanding[];
}

export interface MatchupGame {
  game_id: string;
  season: number;
  week: number;
  gameday: string;
  weekday: string;
  gametime: string;
  home_team: string;
  home_team_name: string;
  away_team: string;
  away_team_name: string;
  home_power_rating: number | null;
  away_power_rating: number | null;
  has_projection: boolean;
  projected_margin: number | null;
  home_win_prob: number | null;
  away_win_prob: number | null;
  home_rest_days: number;
  away_rest_days: number;
  rest_diff: number;
  home_travel_miles: number;
  away_travel_miles: number;
  is_completed?: boolean;
  has_box_score?: boolean;
  has_game_detail?: boolean;
  home_score?: number | null;
  away_score?: number | null;
  actual_winner?: string | null;
  prediction_correct?: boolean | null;
}

export interface MatchupsDataset {
  generated_at: string;
  active_week: number;
  available_weeks: number[];
  total_games: number;
  matchups: MatchupGame[];
}

export interface TeamEpaProfile {
  generated_at: string;
  team: string;
  team_name: string;
  conference: 'AFC' | 'NFC';
  division: string;
  games_in_sample: number;
  off_epa_per_play: number;
  def_epa_per_play: number;
  net_epa_per_play: number;
  off_success_rate: number;
  def_success_rate: number;
  off_cpoe: number;
  off_early_down_epa: number;
  off_money_down_epa: number;
  def_early_down_epa: number;
  def_money_down_epa: number;
  off_redzone_success: number;
  def_redzone_success: number;
  off_explosive_rate: number;
  def_explosive_rate: number;
}

export interface PlayoffSeed {
  seed: number;
  team: string;
  team_name: string;
  division: string;
  role: string;
  win_pct: number;
  power_rating: number;
  wild_card_win_prob: number;
  divisional_win_prob: number;
  conf_champ_win_prob: number;
  super_bowl_win_prob: number;
}

export interface PlayoffBubbleTeam {
  team: string;
  team_name: string;
  division: string;
  playoff_prob: number;
}

export interface PlayoffDataset {
  season: number;
  generated_at: string;
  n_simulations: number;
  seeding_method: string;
  afc_seeds: PlayoffSeed[];
  nfc_seeds: PlayoffSeed[];
  afc_bubble: PlayoffBubbleTeam[];
  nfc_bubble: PlayoffBubbleTeam[];
}

export interface QbProfile {
  generated_at: string;
  player_name: string;
  team: string;
  jersey_number: number;
  years_exp: number;
  college: string;
  depth_position: string;
  headshot_url: string;
  off_epa_roll: number;
  off_cpoe_roll: number;
  status: string;
  is_starter?: boolean;
  attempts_2026?: number;
}

export interface CalibrationBin {
  bin: string;
  predicted_mid: number;
  actual_win_rate: number;
  count: number;
}

export interface ModelTrackRecord {
  n_games: number;
  accuracy: number | null;
  brier: number | null;
  logloss: number | null;
}

export interface DiagnosticsDataset {
  generated_at: string;
  season: number | number[];
  last_evaluated: string | string[];
  n_games_graded: number | number[];
  overall_accuracy: number | number[];
  overall_brier: number | number[];
  overall_logloss: number | number[];
  brier_baseline: number;
  brier_improvement: number | number[];
  margin_sigma: number;
  home_field_adv: number;
  ensemble_weights: {
    ridge_massey: number;
    elo_dynamic: number;
    ridge_massey_fallback?: number;
  };
  calibration_curve: CalibrationBin[];
  genuine_pregame: ModelTrackRecord;
  historical_backtest: ModelTrackRecord;
}

export interface VisualMediaItem {
  generated_at: string;
  filename: string;
  title: string;
  category: 'standings' | 'epa' | 'elo' | 'heatmaps' | 'players' | 'general';
  description: string;
  type: 'gif' | 'image';
  size_bytes: number;
}

export interface CoachProfile {
  team: string;
  head_coach: string;
  tenure_years: number;
  offensive_coordinator: string;
  defensive_coordinator: string;
  play_caller: 'Head Coach' | 'Offensive Coordinator' | 'Defensive Coordinator';
  offensive_play_caller?: 'Head Coach' | 'Offensive Coordinator';
  defensive_play_caller?: 'Head Coach' | 'Defensive Coordinator';
  fourth_down_aggression_index: number; // 0 - 100 scale (percentile)
  pass_rate_over_expected: number; // PROE %
  early_down_pass_rate: number; // %
  play_action_rate: number; // %
  pace_seconds_per_play: number; // neutral game-script pace
  offensive_scheme: string;
  defensive_scheme: string;
  timeout_management_grade: 'A+' | 'A' | 'A-' | 'B+' | 'B' | 'B-' | 'C+' | 'C' | 'D';
  challenge_win_pct: number;
  career_record: string;
  super_bowl_wins: number;
}

export interface PositionalSpendingItem {
  apy: number;
  pct: number;
  count: number;
}

export interface TopPaidPlayer {
  player: string;
  position: string;
  apy: number;
  guaranteed: number;
}

export interface TeamCapProfile {
  team: string;
  total_active_contracts: number;
  total_active_apy: number;
  total_guaranteed: number;
  // `estimated_cap_space`, `dead_money` and `cap_health_rating` were removed by
  // issue #48: the exporter generated them from an unseeded random draw rather
  // than from any real cap data, so they are no longer published.
  positional_spending: Record<string, PositionalSpendingItem>;
  top_paid_players: TopPaidPlayer[];
}

export interface LeagueTopContract {
  player: string;
  position: string;
  pos_group: string;
  team: string;
  value: number;
  apy: number;
  guaranteed: number;
  apy_cap_pct: number;
  years: number;
  year_signed: number;
}

export interface SalaryCapDataset {
  generated_at: string;
  season: number;
  cap_ceiling: number;
  source: string;
  last_updated: string;
  teams: TeamCapProfile[];
  top_league_contracts: LeagueTopContract[];
}

// -----------------------------------------------------------------------------
// Passing Charts & Throw Maps (NextGenStats Empirical Analytics)
// -----------------------------------------------------------------------------

export interface PassingZoneMetric {
  zone: string;
  attempts: number;
  completions: number;
  comp_pct: number;
  avg_cpoe: number;
  avg_epa: number;
  pct_of_passes: number;
}

export interface PassRecord {
  air_yards: number;
  pass_location: 'left' | 'middle' | 'right';
  complete_pass: 0 | 1;
  epa: number;
  cpoe?: number | null;
  zone: string;
  week: number;
  down?: number | null;
  ydstogo?: number | null;
  defteam?: string | null;
  game_id: string;
}

export interface PassingCatalogEntry {
  player_id: string;
  player_name: string;
  team: string;
  jersey_number: number | null;
  headshot_url: string | null;
  total_passes: number;
  completions: number;
  comp_pct: number;
  avg_cpoe: number;
  avg_epa: number;
}

export interface PassingChartData {
  player_id: string;
  player_name: string;
  team: string;
  jersey_number: number | null;
  headshot_url: string | null;
  total_passes: number;
  completions: number;
  comp_pct: number;
  avg_cpoe: number;
  avg_epa: number;
  zones: PassingZoneMetric[];
  passes: PassRecord[];
}

export interface PassingMetadata {
  updated_at: string;
  season: number;
  total_passes_sampled: number;
  zones: string[];
  league_averages: PassingZoneMetric[];
}

/** A same-position player from the same season window (never the player themself). */
export interface PlayerDnaPeerComp {
  playerId: string;
  compName: string;
  /** Season of the window, derived from CURRENT_SEASON in the builder. */
  era: string;
  archetype: string | null;
  position: 'QB' | 'WR' | 'RB' | 'TE';
  similarityPct: number;
  keySharedTrait: string;
}

export interface PlayerDnaRadarAxis {
  axis: string;
  label: string;
  /** null when the dimension could not be measured (never imputed). */
  value: number | null;
}

export interface PlayerDnaStatsSummary {
  games: number;
  passYards?: number;
  passTds?: number;
  interceptions?: number;
  rushYards?: number;
  rushTds?: number;
  receptions?: number;
  recYards?: number;
  recTds?: number;
  epaPerPlay: number | null;
}

export interface PlayerDnaProfile {
  playerId: string;
  playerName: string;
  team: string;
  position: 'QB' | 'WR' | 'RB' | 'TE';
  archetype: string | null;
  overallRating: number | null;
  statsSummary: PlayerDnaStatsSummary;
  manifoldX: number | null;
  manifoldY: number | null;
  radarAxes: PlayerDnaRadarAxis[];
  skillVector: Record<string, number | null>;
  categoryScores: Record<string, number | null>;
  peerComps: PlayerDnaPeerComp[];
}

/** player_dna_profiles.json envelope: provenance plus the profiles. */
export interface PlayerDnaDataset {
  season: number;
  /** Last completed regular-season week present in the play-by-play data. */
  throughWeek: number;
  /** ISO UTC build timestamp. */
  generatedAt: string;
  profiles: PlayerDnaProfile[];
}

export interface ClutchProfile {
  playerId: string;
  playerName: string;
  team: string;
  position: string;
  isStarter: boolean;
  headshotUrl: string;
  /** Season the play-by-play covers (builder keeps only season == CURRENT_SEASON). */
  season: number;
  /** Latest week present in that season's play-by-play. */
  throughWeek: number;
  /** MIN_CLUTCH_PASS_ATTEMPTS used for this build: below it, no metrics, rank or archetype. */
  minClutchAttempts: number;
  /** pass_attempt == 1 rows in clutch situations (passes, sacks and spikes). */
  clutchAttempts: number;
  /** pass == 1 | qb_dropback == 1 rows in clutch situations (passes, sacks, and scrambles; no spikes). */
  clutchPlays: number;
  baselineAttempts: number;
  baselinePlays: number;
  clutchEpa: number | null;
  baselineEpa: number | null;
  clutchEpaDelta: number | null;
  clutchSuccessRate: number | null;
  baselineSuccessRate: number | null;
  clutchCpoe: number | null;
  turnoverFragility: number | null;
  /** 4th-down conversion rate (%) across the QB's 4th-down plays, or null when 0 4th-down plays. */
  fourthDownConversionRate?: number | null;
  /** Legacy field name from pre-#168 builds; prefer fourthDownConversionRate. */
  fourthDownAggressiveness?: number | null;
  clutchArchetype: string;
  provenance: string;
}

export * from './gameDetailTypes';


