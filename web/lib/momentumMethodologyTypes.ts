/**
 * Shape of public/data/momentum_methodology.json (written by
 * tools/publish_momentum_methodology.R, NFL_analytics#226; contract-tested in
 * tests/contracts/momentum_methodology.contract.test.ts). Every study figure is an
 * extract of docs/research/rolling_window_study_results.json (#227) or
 * docs/research/momentum_measures_study_results.json (#221) at its study commit.
 * The one exception, the NBA-style comparison weights, is read from
 * tools/rolling_window_study.R at the study commit (sources.rolling_window.nba_comparison_weights).
 */
export type MethodologyComponent = 'form' | 'trend' | 'residual' | 'elo_change';
export type Interval = [number, number];

export interface ExtractSpec {
  path: string;
  where?: { field: string; values: string[] };
  fields?: string[];
}

export interface MethodologySource {
  file: string;
  report: string;
  script: string;
  issue: number;
  merged_in: number;
  commit: string;
  commit_config: string;
  sha256_lf: string;
  extracts: ExtractSpec[];
}

export interface ComparisonWeights extends Record<MethodologyComponent, number> {
  provenance: {
    file: string;
    commit: string;
    blob_sha1: string;
    line: number;
    line_text: string;
    grid_line: number;
    grid_line_text: string;
    derived_component: MethodologyComponent;
    rule: string;
    note: string;
  };
}

/* ---------------------------------------------------------- rolling window ---- */

export interface StrongerArmRow {
  feature: string;
  method: string;
  window: string;
  target: string;
  /** null with n = 0: the window had no games to score under that method. */
  score: number | null;
  lo: number | null;
  hi: number | null;
  n: number;
}

export interface StrongerArmSelection {
  feature: string;
  method: string;
  target: string;
  best: string;
  best_score: number;
  best_lo: number;
  best_hi: number;
  chosen: string;
  chosen_score: number;
  windows_within: string;
}

export interface WeightsTableRow {
  method: string;
  window: string;
  target: string;
  rows: number;
  best: string;
  best_r2: number;
  best_lo: number;
  best_hi: number;
  nba_r2: number;
  nba_lo: number;
  nba_hi: number;
  diff_lo: number;
  diff_hi: number;
  nested_r2: number;
  nnls_r2: number;
  form_only_r2: number;
  n_within: number;
}

export interface WeightsDetailRow {
  method: string;
  window: string;
  target: string;
  rows: number;
  best_weights: number[];
  best_r2: number;
  best_ci: Interval;
  nba_r2: number;
  nba_ci: Interval;
  best_minus_nba: number;
  best_minus_nba_ci: Interval;
  equal_r2: number;
  equal_ci: Interval;
  form_only_r2: number;
  form_only_ci: Interval;
  flat_n_within_best_ci: number;
  flat_share_within: number;
  flat_weight_ranges: Record<string, string>;
}

export interface FlagDefinition {
  label: string;
  test: string;
  unit: string;
  per_game: number;
  delta: number;
  effect_basis: string;
  caveat?: string;
  [k: string]: unknown;
}

export interface DetectionRow {
  flag: string;
  window: string;
  games: number;
  typical_count: number;
  simulated_detection_rate: number;
}

export interface RollingWindowExtract {
  meta: {
    issue: number;
    run_at: string;
    n_boot: number;
    n_sim: number;
    seasons_loso: number[];
    offseason_methods: Record<string, string>;
    opponent_adjustment: string;
    elo: string;
    [k: string]: unknown;
  };
  stronger_arm: { selections: StrongerArmSelection[]; selection_rule: string; table: StrongerArmRow[] };
  replication_arm: {
    best: {
      variant: string;
      best_window: number;
      roc_auc: number;
      auc_lo: number;
      auc_hi: number;
      accuracy: number;
      kappa: number;
      test_games: number;
      windows_inside_best_interval: string;
    }[];
    test_season: number;
  };
  weights: {
    grid: string;
    components: string[];
    standardisation: string;
    score: string;
    table: WeightsTableRow[];
    detail: WeightsDetailRow[];
  };
  flags: {
    note: string;
    definitions: Record<string, FlagDefinition>;
    detection: DetectionRow[];
    power_threshold: number;
  };
  availability: {
    fully_covered_from: number;
    covered_threshold: number;
    coverage: { season: number; injury_share: number; snaps_share: number; both_full: boolean; [k: string]: unknown }[];
    key_players: { rate_league: number; team_seasons: number };
  };
}

/* ------------------------------------------------------- momentum measures ---- */

export type MomentumVerdict = 'kept' | 'inconclusive' | 'discarded';

export interface StudyTarget {
  id: string;
  definition: string;
  primary: boolean;
  [k: string]: unknown;
}

export interface StudyMeasure {
  id: string;
  name: string;
  field_of_origin: string;
  forward_only_definition: string;
}

export interface StudySeries {
  id: string;
  name: string;
  definition: string;
  [k: string]: unknown;
}

export interface SingleFeatureResult {
  feature: string;
  series: string;
  measure: string;
  target: string;
  incremental_ic: number;
  ic_metric: string;
  r2_gain: number;
  gain_metric: string;
  ci_95: Interval;
  fdr_q_value: number;
  p_value: number;
  n: number;
  missing_count: number;
  verdict: MomentumVerdict;
  reason: string;
}

export interface MeasuresFlagRow {
  flag: string;
  target: string;
  definition: string;
  rows: number;
  flagged_rows: number;
  /** Absent on descriptive rows (verdict "descriptive"). */
  added_to_baseline?: { model: string; r2_gain: number; ci_95: Interval; p_value: number; n: number; auc_change: number | null };
  verdict: MomentumVerdict | 'descriptive';
  reason: string;
  [k: string]: unknown;
}

export interface MomentumMeasuresExtract {
  study: {
    title: string;
    issue: string;
    run_date: string;
    seasons: { season: string; role: string; games: number; first: string; last: string; [k: string]: unknown }[];
    holdout: string;
    baseline: string;
    protocol: string[];
    [k: string]: unknown;
  };
  targets: StudyTarget[];
  measures: StudyMeasure[];
  series: StudySeries[];
  single_feature_results: SingleFeatureResult[];
  combination_search: {
    target: string;
    rows: number;
    pooled_r2_gain: number;
    pooled_ci_95: Interval;
    comparisons: Record<string, { r2_gain: number; ci: Interval; ic: number }>;
    permutation: { runs: number; p95: number; mean: number; max: number; share_at_or_above_real: number; minutes: number };
    final_choice: { series: string[]; measures: string[]; [k: string]: unknown };
    reliability_checks: Record<string, boolean>;
    final_verdict: string;
  };
  flags: { definitions: Record<string, string>; rows: MeasuresFlagRow[] };
  holdout: { note: string; [k: string]: unknown };
  limits: string[];
}

export interface MomentumMethodologyPayload {
  schema_version: 1;
  publisher: string;
  board_issue: number;
  sources: {
    rolling_window: MethodologySource & { nba_comparison_weights: ComparisonWeights };
    momentum_measures: MethodologySource;
  };
  rolling_window: RollingWindowExtract;
  momentum_measures: MomentumMeasuresExtract;
  board: {
    carry_method: string;
    windows: number[];
    weights_target: string;
    weights_order: MethodologyComponent[];
    selection: string;
    settings_url: string;
  };
}
