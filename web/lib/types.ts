export interface TeamProjection {
  rank: number;
  team_id: number;
  team: string;
  team_name: string;
  conference: 'East' | 'West';
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
  _row?: string;
}

export interface PlayerProjection {
  player_id: string;
  player_name: string;
  team: string;
  position: string;
  proj_games: number;
  proj_mpg: number;
  proj_min_total: number;
  proj_pts: number;
  proj_reb: number;
  proj_ast: number;
  proj_pts_total: number;
  proj_reb_total: number;
  proj_ast_total: number;
  pts_p10: number;
  pts_p25: number;
  pts_p50: number;
  pts_p75: number;
  pts_p90: number;
  reb_p10: number;
  reb_p25: number;
  reb_p50: number;
  reb_p75: number;
  reb_p90: number;
  ast_p10: number;
  ast_p25: number;
  ast_p50: number;
  ast_p75: number;
  ast_p90: number;
  games_p10: number;
  games_p25: number;
  games_p50: number;
  games_p75: number;
  games_p90: number;
  games_sd: number;
  pts_sd: number;
  reb_sd: number;
  ast_sd: number;
  pts_zscore: number;
  reb_zscore: number;
  ast_zscore: number;
  pra_zscore: number;
  is_outlier: boolean;
}

export interface ModelMetadata {
  schema_version: string;
  pipeline_stage: string;
  generated_at: string;
  season: number;
  n_simulations: number;
  margin_sigma: number;
  home_court_advantage: number;
  total_schedule_games: number;
  teams_count: number;
  players_count: number;
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
  /**
   * UTC ISO-8601 stamp written by the R exporter for publish_web.R's assertion
   * F. Optional because payloads written before the stamp landed do not carry
   * it; declared here because tests/contracts/types-vs-data.test.ts fails any
   * payload key absent from this interface, so an undeclared stamp would turn
   * the contract suite -- and therefore the fatal publish gate -- red the first
   * time a stamped payload was written. Distinct from the camelCase
   * `generatedAt` some of these payloads already carry: assertion F only ever
   * matches the snake_case key.
   */
  generated_at: string;
  totalResolvedGames: number;
  overallAccuracy: number;
  brierScore: number;
  logLoss: number;
  homeWinRate: number;
  calibration: CalibrationBin[];
  accuracyDrift: AccuracyDrift[];
  residualDistribution: ResidualBucket[];
}
