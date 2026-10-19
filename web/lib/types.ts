// NFL Analytics Web Application — Core Data Types

export interface TeamStanding {
  team: string;
  team_name: string;
  conference: 'AFC' | 'NFC';
  division: string;
  rank: number;
  games_played: number;
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
  home_power_rating: number;
  away_power_rating: number;
  projected_margin: number;
  projected_spread: number;
  projected_total: number;
  home_win_prob: number;
  away_win_prob: number;
  home_rest_days: number;
  away_rest_days: number;
  rest_diff: number;
  home_travel_miles: number;
  away_travel_miles: number;
  key_number_flag: string;
  is_completed?: boolean;
  home_score?: number;
  away_score?: number;
  actual_winner?: string;
  prediction_correct?: boolean;
}

export interface MatchupsDataset {
  active_week: number;
  available_weeks: number[];
  total_games: number;
  matchups: MatchupGame[];
}

export interface TeamEpaProfile {
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
}

export interface CalibrationBin {
  bin: string;
  predicted_mid: number;
  actual_win_rate: number;
  count: number;
}

export interface DiagnosticsDataset {
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
    market_blend: number;
  };
  calibration_curve: CalibrationBin[];
}

export interface ValueBet {
  matchup: string;
  recommended_bet: string;
  team: string;
  book: string;
  line: string;
  model_win_prob: number;
  predicted_margin: number;
  ev_percent: number;
  exp_clv: number;
  bankroll_rec: string;
  status: string;
}

export interface ValueBetsDataset {
  total_bets: number;
  active_bets: ValueBet[];
}

export interface VisualMediaItem {
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
  timeout_management_grade: 'A+' | 'A' | 'B+' | 'B' | 'C+' | 'C' | 'D';
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
  estimated_cap_space: number;
  dead_money: number;
  cap_health_rating: 'Healthy' | 'Moderate' | 'Constrained';
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
  season: number;
  cap_ceiling: number;
  source: string;
  last_updated: string;
  teams: TeamCapProfile[];
  top_league_contracts: LeagueTopContract[];
}
