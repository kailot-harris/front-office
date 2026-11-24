/**
 * momentum_methodology.json: the momentum measures study's results file plus
 * provenance, copied (never recomputed) by tools/publish_momentum_methodology.R.
 * Read by /momentum/methodology. Every number on that page comes from here.
 */

export type MomentumVerdict = 'kept' | 'discarded' | 'inconclusive';

/** [low, high] 95% interval. */
export type Interval = [number, number];

export interface StudySeason {
  season: string;
  hoopr_season: number;
  role: string;
  games: number;
  team_games: number;
  teams: number;
  first: string;
  last: string;
  neutral_games: number;
}

export interface StudyInfo {
  title: string;
  run_date: string;
  seasons: StudySeason[];
  holdout: string;
  protocol: string[];
  seeds: { study: number; permutation: number; bootstrap: string };
  runtime_minutes: number;
  permutation_minutes: number;
}

export interface StudyTarget {
  id: string;
  definition: string;
  primary: boolean;
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

export interface SensitivityResult {
  feature: string;
  r2_gain: number;
  ci_95: Interval;
  fdr_q_value: number;
  n: number;
  verdict: MomentumVerdict;
}

/** A family is either one id standing alone or a group of ids. */
export type FamilyGroup = string | string[];

export interface StudyFamilies {
  feature_clusters_abs_r_0_7: FamilyGroup[];
  measure_families: FamilyGroup[];
  series_families: FamilyGroup[];
  /** Row per measure id, columns in `measures` order. */
  measure_mean_abs_r: Record<string, number[]>;
  /** Row per series id, columns in `series` order. */
  series_mean_abs_r: Record<string, number[]>;
}

export interface CombinationFold {
  held_out: string;
  series: string[];
  measures: string[];
  ridge_alpha: number;
  top6_series: string[];
  top6_measures: string[];
  inner_r2_gain: number;
  held_out_r2_gain: number;
  held_out_rows: number;
}

export interface ComparisonModel {
  r2_gain: number;
  ci: Interval;
  ic: number;
}

export interface SelectionStability {
  series_counts: Record<string, number>;
  measure_counts: Record<string, number>;
  series_family_counts: Record<string, number>;
  measure_family_counts: Record<string, number>;
  distinct_combinations: number;
  combination_counts: Record<string, number>;
  folds_needed: number;
  stable_exact: boolean;
  stable_family: boolean;
  seasons_with_positive_gain: number;
  of_seasons: number;
}

export interface CombinationSensitivity {
  rows: number;
  folds: CombinationFold[];
  pooled_r2_gain: number;
  pooled_ci_95: Interval;
  comparisons: Record<string, ComparisonModel>;
  selection_stability: SelectionStability;
}

export interface CombinationSearch {
  target: string;
  rows: number;
  folds: CombinationFold[];
  pooled_r2_gain: number;
  pooled_ci_95: Interval;
  pooled_incremental_ic: number;
  comparisons: Record<string, ComparisonModel>;
  combination_vs_board_score: { r2_gain: number; ci_95: Interval };
  greedy_selected_by_fold: Record<string, string[]>;
  elastic_net_nonzero_by_fold: Record<string, number>;
  selection_stability: SelectionStability;
  permutation: {
    runs: number;
    p95: number;
    mean: number;
    max: number;
    share_at_or_above_real: number;
    minutes: number;
  };
  final_choice: {
    series: string[];
    measures: string[];
    ridge_alpha: number;
    inner_r2_gain: number;
    tied_with_best_within_ci: number;
    of_combinations: number;
  };
  reliability_checks: Record<string, boolean>;
  final_verdict: string;
  sensitivity_without_2019_20_2020_21: CombinationSensitivity;
}

export interface BlendWeights {
  form: number;
  trend: number;
  elo: number;
}

export interface Delta {
  delta: number;
  ci_lo: number;
  ci_hi: number;
}

export interface BlendWindowResult {
  window: number;
  target: string;
  rows: number;
  current_weights: BlendWeights;
  current_r2_gain: number;
  current_incremental_ic: number;
  best_weights: BlendWeights;
  best_r2_gain: number;
  best_incremental_ic: number;
  best_vs_current: Delta;
  flatness: { within_ci_of_best: number; of: number };
  loso_selected: { weights_by_fold: Record<string, BlendWeights>; r2_gain: number; vs_current: Delta };
  nonnegative_regression: { weights_by_fold: Record<string, BlendWeights>; r2_gain: number; vs_current: Delta };
  component_alone_r2_gain: BlendWeights;
  next5: { current_r2_gain: number; best_weights: BlendWeights; best_r2_gain: number; best_vs_current: Delta };
  residual_small_sample_check: {
    label: string;
    rows: number;
    teams: number;
    ic_current_4?: number;
    ic_current_3_no_residual?: number;
    ic_residual_alone?: number;
    ic_4_minus_3?: Delta;
  };
  trend_swap: {
    feature: string;
    rows: number;
    best_3_component_on_same_rows: { weights: BlendWeights; r2_gain: number };
    swap: {
      weights: Record<string, number>;
      r2_gain: number;
      vs_best_3_component: Delta;
      loso_selected_vs_current_swap?: Delta;
    };
    join: {
      weights: Record<string, number>;
      r2_gain: number;
      vs_best_3_component: Delta;
      flatness?: { within_ci_of_best: number; of: number };
    };
  };
  sensitivity_without_2019_20_2020_21: {
    best_weights: BlendWeights;
    current_r2_gain: number;
    best_vs_current: Delta;
    loso_selected_vs_current: Delta;
  };
  recommendation: string;
}

export interface HoldoutCell {
  target: string;
  rows: number;
  teams?: number;
  best_weights?: BlendWeights;
  current_r2_gain?: number;
  best_r2_gain?: number;
  result: string;
}

export interface StudyHoldout {
  note: string;
  part_a: {
    choice: { series: string[]; measures: string[]; ridge_alpha: number; reliable: boolean };
    primary: HoldoutCell;
    next5: HoldoutCell;
  };
  /** Keyed by window ("w5") then target id. */
  part_b: Record<string, Record<string, HoldoutCell>>;
}

export interface MomentumMethodologyPayload {
  source_commit: string;
  source_sha256: string;
  published_at: string;
  study: StudyInfo;
  targets: StudyTarget[];
  measures: StudyMeasure[];
  series: StudySeries[];
  single_feature_results: SingleFeatureResult[];
  single_feature_sensitivity_primary: SensitivityResult[];
  families: StudyFamilies;
  combination_search: CombinationSearch;
  blend_weights: BlendWindowResult[];
  holdout: StudyHoldout;
  limits: string[];
}
