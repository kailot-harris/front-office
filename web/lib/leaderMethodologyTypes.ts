/**
 * leader_methodology.json (NBA_analytics#258), built by
 * tools/build_leader_methodology.R from docs/research/leader_reliability_study_results.json
 * (#256) and the owner minimums in config.R (#254). Read by /players/leaders/methodology.
 */

export type LeaderStudyGroup = 'counting' | 'shooting' | 'rates' | 'rapm';
export type LeaderMinimumBucket = 'early' | 'middle' | 'late' | 'attempts' | 'possessions';

export interface LeaderStudySettings {
  seasons: number[];
  rapm_seasons: number[];
  seed: number;
  n_boot: number;
  grid_games: number[];
  grid_attempts: number[];
  grid_minutes: number[];
  rapm_bin_edges_per_side_per_half: number[];
  rapm_thresholds_per_side_per_half: number[];
  reference_bars: number[];
  min_players_per_point: number;
  rapm_lambda: number;
  rapm_rule_poss_per_side: number;
}

export interface LeaderDataAuditRow {
  season: number;
  player_box_source: string;
  regular_season_rows: number;
  did_not_play_rows: number;
  played_but_minutes_missing_rows: number;
  player_games_used: number;
  games: number;
  players: number;
  player_games_missing_any_box_stat: number;
  player_games_missing_team_context: number;
}

export interface LeaderSplitHalfPoint {
  n: number;
  n_players: number;
  n_missing: number;
  mean_realised_units: number | null;
  r: number | null;
  r_lo: number | null;
  r_hi: number | null;
  sb_sample: number;
  r_sb: number | null;
  r_sb_lo: number | null;
  r_sb_hi: number | null;
}

export interface LeaderRestOfSeasonPoint {
  n: number;
  n_players: number;
  n_missing: number;
  mean_realised_units: number | null;
  r: number | null;
  r_lo: number | null;
  r_hi: number | null;
}

export interface LeaderCrossing {
  bar: number;
  point: number | null;
  lo: number | null;
  hi: number | null;
  share_not_reached: number;
}

export interface LeaderStatStudy {
  label: string;
  group: 'counting' | 'shooting' | 'rates';
  unit: string;
  unit_label: string;
  split_half: LeaderSplitHalfPoint[];
  rest_of_season: LeaderRestOfSeasonPoint[];
  crossings: {
    split_half: LeaderCrossing[];
    spearman_brown: LeaderCrossing[];
    rest_of_season: LeaderCrossing[];
  };
}

export interface LeaderRapmPoint {
  measure: 'orapm' | 'drapm' | 'total_rapm';
  kind: 'bin' | 'threshold';
  lo: number;
  hi: number | null;
  n_players: number;
  r: number;
  r_lo: number;
  r_hi: number;
  r_sb: number;
  r_sb_lo: number;
  r_sb_hi: number;
}

export interface LeaderRapmStudy {
  available: boolean;
  seasons_fit: number[];
  seasons_failed: number[];
  audit: unknown[];
  player_seasons: number;
  bins: LeaderRapmPoint[];
  thresholds: LeaderRapmPoint[];
  at_current_rule: LeaderRapmPoint[];
  crossings: Record<
    'orapm' | 'drapm' | 'total_rapm',
    {
      split_half: LeaderCrossing[];
      spearman_brown: LeaderCrossing[];
    }
  >;
}

export interface LeaderMinimumReliability {
  split_half_n: number;
  split_half_r: number;
  split_half_lo: number;
  split_half_hi: number;
  split_half_n_players: number;
  spearman_brown_n: number | null;
  spearman_brown_r: number | null;
  spearman_brown_lo: number | null;
  spearman_brown_hi: number | null;
  spearman_brown_n_players: number | null;
  spearman_brown_null_reason: string | null;
  rest_of_season_r: number | null;
  rest_of_season_lo: number | null;
  rest_of_season_hi: number | null;
  rest_of_season_n_players: number | null;
  rest_of_season_null_reason: string | null;
}

export interface LeaderMethodologyMinimum {
  key: string;
  label: string;
  group: LeaderStudyGroup;
  bucket: LeaderMinimumBucket;
  unit: string;
  unit_label: string;
  constant: string;
  minimum_full_season: number;
  minimum_minutes_constant: string | null;
  minimum_minutes_full_season: number | null;
  noise_note: boolean;
  reliability: LeaderMinimumReliability;
}

export interface LeaderScalingExampleItem {
  key: string;
  label: string;
  unit_label: string;
  minimum_full_season: number;
  required: number;
}

export interface LeaderScalingExample {
  formula: string;
  team_games_played: number;
  base_games: number;
  examples: LeaderScalingExampleItem[];
}

export interface LeaderMethodologyPayload {
  schema_version: number;
  source_commit: string;
  source_sha256: string;
  study_run_date: string | null;
  published_at: string;
  issue: string;
  note: string;
  base_games: number;
  settings: LeaderStudySettings;
  data_audit: LeaderDataAuditRow[];
  player_seasons: number;
  runtime_minutes: number;
  scaling_example: LeaderScalingExample;
  minimums: LeaderMethodologyMinimum[];
  stats: Record<string, LeaderStatStudy>;
  rapm: LeaderRapmStudy;
}
