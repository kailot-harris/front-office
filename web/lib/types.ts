export interface TeamProjection {
  rank: number;
  team_id: number;
  team: string;
  team_name: string;
  full_name: string;
  conference: 'AL' | 'NL';
  league: 'AL' | 'NL';
  division: string;
  proj_wins: number;
  proj_losses: number;
  win_pct: number;
  ensemble_mean_wins: number;
  ensemble_median_wins: number;
  ensemble_sd_wins: number;
  ensemble_p10: number;
  ensemble_p25: number;
  ensemble_p50: number;
  ensemble_p75: number;
  ensemble_p90: number;
  ensemble_playoff_prob: number;
  ensemble_title_prob: number;
  variant_bottom_up_mean_wins: number;
  variant_bottom_up_median_wins: number;
  variant_bottom_up_sd_wins: number;
  variant_bottom_up_p10: number;
  variant_bottom_up_p25: number;
  variant_bottom_up_p50: number;
  variant_bottom_up_p75: number;
  variant_bottom_up_p90: number;
  variant_bottom_up_playoff_prob: number;
  variant_bottom_up_title_prob: number;
  variant_rapm_mean_wins: number;
  variant_rapm_median_wins: number;
  variant_rapm_sd_wins: number;
  variant_rapm_p10: number;
  variant_rapm_p25: number;
  variant_rapm_p50: number;
  variant_rapm_p75: number;
  variant_rapm_p90: number;
  variant_rapm_playoff_prob: number;
  variant_rapm_title_prob: number;
  variant_shot_fatigue_mean_wins: number;
  variant_shot_fatigue_median_wins: number;
  variant_shot_fatigue_sd_wins: number;
  variant_shot_fatigue_p10: number;
  variant_shot_fatigue_p25: number;
  variant_shot_fatigue_p50: number;
  variant_shot_fatigue_p75: number;
  variant_shot_fatigue_p90: number;
  variant_shot_fatigue_playoff_prob: number;
  variant_shot_fatigue_title_prob: number;
  variant_embeddings_mean_wins: number;
  variant_embeddings_median_wins: number;
  variant_embeddings_sd_wins: number;
  variant_embeddings_p10: number;
  variant_embeddings_p25: number;
  variant_embeddings_p50: number;
  variant_embeddings_p75: number;
  variant_embeddings_p90: number;
  variant_embeddings_playoff_prob: number;
  variant_embeddings_title_prob: number;
  elo_rating: number;
  team_rgs: number;
  run_differential: number;
  pythag_win_pct: number;
  luck_wins: number;
  team_woba_pooled: number;
  team_xfip_pooled: number;
  net_talent_score: number;
  bullpen_fatigue: number;
  bullpen_grade: string;
  make_ds_prob: number;
  make_lcs_prob: number;
  win_pennant_prob: number;
}

export interface PlayerProjection {
  player_id: string;
  mlbam_id: string;
  player_name: string;
  team: string;
  player_type: 'Batter' | 'Pitcher';
  position: 'B' | 'SP' | 'RP';
  age: number;
  observed_workload: number;
  proj_workload: number;
  park_factor: number;
  stat1_label: string;
  stat1_raw: number;
  stat1_pooled: number;
  stat1_p10: number;
  stat1_p25: number;
  stat1_p50: number;
  stat1_p75: number;
  stat1_p90: number;
  stat1_sd: number;
  stat1_shrinkage: number;
  stat2_label: string;
  stat2_raw: number;
  stat2_pooled: number;
  stat3_label: string;
  stat3_val: number;
  k_pct_pooled: number;
  bb_pct_pooled: number;
  count1_label: string;
  count1_val: number;
  count1_p10: number;
  count1_p25: number;
  count1_p50: number;
  count1_p75: number;
  count1_p90: number;
  count2_label: string;
  count2_val: number;
  count3_label: string;
  count3_val: number;
  primary_zscore: number;
  secondary_zscore: number;
  counting_zscore: number;
  composite_zscore: number;
  is_outlier: boolean;
}

export interface ModelMetadata {
  schema_version: string;
  pipeline_stage: string;
  generated_at: string;
  season: number;
  n_simulations: number;
  postseason_sims: number;
  margin_sigma: number;
  home_court_advantage: number;
  pythag_exponent: number;
  total_schedule_games: number;
  teams_count: number;
  players_count: number;
  batters_count: number;
  pitchers_count: number;
  models: {
    ensemble: {
      name: string;
      weights: Record<string, number>;
      description: string;
    };
    variant_bottom_up: {
      name: string;
      weight: number;
      description: string;
    };
    variant_rapm: {
      name: string;
      weight: number;
      description: string;
    };
    variant_shot_fatigue: {
      name: string;
      weight: number;
      description: string;
    };
    variant_embeddings: {
      name: string;
      weight: number;
      description: string;
    };
  };
}

export interface CalibrationBin {
  bin: string;
  midpoint: number;
  count: number;
  meanPredictedProb: number;
  empiricalWinRate: number;
}

export interface AccuracyDrift {
  season: string;
  games: number;
  accuracy: number;
  brierScore: number;
}

export interface ResidualBucket {
  bucket: string;
  count: number;
  label: string;
}

export interface ModelDiagnostics {
  totalResolvedGames: number;
  overallAccuracy: number;
  brierScore: number;
  brierSkillScore?: number;
  logLoss: number;
  homeWinRate: number;
  weightedCalibError?: number;
  calibrationStatus?: string;
  calibration: CalibrationBin[];
  accuracyDrift: AccuracyDrift[];
  residualDistribution: ResidualBucket[];
}

export interface PostseasonBracketTeam {
  team_id: number;
  team_name: string;
  full_name?: string;
  team: string;
  league: 'AL' | 'NL';
  division: string;
  seed: number;
  wins: number;
  elo_rating: number;
  make_ds: number;
  make_lcs: number;
  win_pennant: number;
  win_ws: number;
  pct_ds: number;
  pct_lcs: number;
  pct_pennant: number;
  pct_ws: number;
}

export interface BullpenStatusRow {
  rank: number;
  team_id: number;
  team: string;
  team_name: string;
  full_name: string;
  league: 'AL' | 'NL';
  division: string;
  proj_wins: number;
  elo_rating: number;
  active_relievers: number;
  relievers_fatigued: number;
  relievers_exhausted: number;
  avg_bullpen_fatigue: number;
  max_reliever_fatigue: number;
  b2b_relievers_count: number;
  bullpen_vulnerability: number;
  vulnerability_grade: string;
}

export interface ValueBetRow {
  game_id: string;
  home_team: string;
  away_team: string;
  market: string;
  bet_on: string;
  bookmaker: string;
  odds: number;
  model_prob: number;
  ev: number;
  kelly_stake: number;
  market_data_source: string;
  game_date: string;
  Matchup: string;
  Recommended_Bet: string;
  Team: string;
  Book: string;
  Line: number;
  Model_Win_Prob: number;
  EV_Percent: number;
  Exp_CLV: number;
  Bankroll_Rec: number;
  Status: string;
  edge_flag: string;
  fatigue_adj: number;
}

export interface RiskStateSummary {
  current_bankroll: number;
  current_dd_units: number;
  current_dd_pct: number;
  max_dd_units: number;
  max_dd_pct: number;
  active_kelly_multiplier: number;
  risk_status: string;
  status_message: string;
  rolling_7d_clv_pct: number;
  rolling_30d_clv_pct: number;
  beat_clv_rate_pct: number;
  total_bets_audited: number;
}

export interface PostseasonOpsData {
  season: number;
  n_sims: number;
  bracket: PostseasonBracketTeam[];
  bullpen_status: BullpenStatusRow[];
  value_bets: ValueBetRow[];
  risk_state: RiskStateSummary;
}

// ----------------------------------------------------------------------------
// Statcast 4-Tier Spatial Analytics Interfaces
// ----------------------------------------------------------------------------
export interface BattedBallPoint {
  batter_id: string;
  batter_name: string;
  team: string;
  stand: 'L' | 'R';
  hc_x: number;
  hc_y: number;
  d_x: number;
  d_y: number;
  dist: number;
  bearing: number;
  exit_velocity: number;
  launch_angle: number;
  event: string;
  hit_type: 'Single' | 'Double' | 'Triple' | 'Home Run' | 'Out';
  parks_hr_count: number;
  parks_hr_pct: number;
}

export interface ParkDimension {
  team: string;
  park: string;
  lf: number;
  lcf: number;
  cf: number;
  rcf: number;
  rf: number;
  wall_lf: number;
  wall_cf: number;
  wall_rf: number;
}

export interface ZoneCell {
  zone_index: number;
  row: number;
  col: number;
  label: string;
  x_min: number;
  x_max: number;
  z_min: number;
  z_max: number;
  pitch_count: number;
  pct_of_zone: number;
  swing_rate: number;
  whiff_rate: number;
  called_strike_rate: number;
}

export interface CatcherFramingSummary {
  total_shadow_taken: number;
  called_strikes: number;
  called_balls: number;
  shadow_strike_rate: number;
  league_baseline_rate: number;
}

export interface PitchTypeMovement {
  pitch_type: string;
  count: number;
  name: string;
  velocity: number;
  hb: number;
  ivb: number;
  hb_sd: number;
  ivb_sd: number;
  release_x: number;
  release_z: number;
  release_ext: number;
  whiff_pct: number;
}

export interface PitcherArsenal {
  pitcher_id: number;
  pitcher_name: string;
  team: string;
  hand: 'L' | 'R';
  total_pitches: number;
  avg_release_x: number;
  avg_release_z: number;
  pitches: {
    pitch_type: string;
    count: number;
    name: string;
    velo: number;
    hb: number;
    ivb: number;
    whiff_rate: number;
  }[];
}

export interface DirectionalBabipRow {
  stand: 'L' | 'R';
  spray_dir: 'Pull' | 'Center' | 'Oppo';
  batted_balls: number;
  hits: number;
  babip: number;
  avg_ev: number;
  avg_dist: number;
}

export interface InfieldSector {
  sector: string;
  angle_range: string;
  balls: number;
}

export interface StatcastSpatialData {
  generated_at: string;
  sample_pitches_analyzed: number;
  sample_batted_balls: number;
  tier1_spray: {
    batted_balls: BattedBallPoint[];
    hr_hitters: {
      batter_id: string;
      batter_name: string;
      team: string;
      stand: string;
      total_balls: number;
      actual_hrs: number;
      expected_hrs_30_park_avg: number;
      max_dist: number;
      max_ev: number;
    }[];
    park_dimensions: Record<string, ParkDimension>;
  };
  tier2_zone: {
    zone_grid: ZoneCell[];
    framing_summary: CatcherFramingSummary;
    zone_specs: {
      x_min: number;
      x_max: number;
      z_min: number;
      z_max: number;
    };
  };
  tier3_movement: {
    league_pitch_types: PitchTypeMovement[];
    pitcher_arsenals: PitcherArsenal[];
  };
  tier4_defense: {
    directional_babip: DirectionalBabipRow[];
    infield_sectors: InfieldSector[];
    shift_rule_impact: {
      rule: string;
      lefty_pull_babip_gain: string;
      deep_outfield_shade_pct: string;
    };
  };
}
