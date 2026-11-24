/**
 * Shape of public/data/momentum_board.json (written by build_momentum_dataset.R,
 * contract-tested in tests/contracts/momentum_board.contract.test.ts). The page
 * renders these values as published: it sorts, toggles and expands, and never
 * computes or fills a value.
 */
export interface MomentumSortOption {
  key: string;
  label: string;
  descending: boolean;
}

export interface MomentumFlag {
  id: number;
  key: string;
  group: 'luck' | 'context' | 'availability';
  value: number | null;
  statistic: number | null;
  significant: boolean;
  n?: number | null;
  value_shrunk?: number | null;
  null_reason?: string;
  detail?: unknown;
}

export interface MomentumRating {
  value: number;
  rank: number | null;
  season: number;
  before_window?: number | null;
  games_before_window?: number;
  change: number | null;
  change_null_reason?: string | null;
  change_rank?: number | null;
}

export interface MomentumNextWeekGame {
  date: string;
  opponent: string;
  home: boolean;
  opponent_win_pct: number;
}

export interface MomentumRow {
  team: string;
  team_name: string;
  games_played: number;
  record: { wins: number; losses: number };
  window: number;
  games_in_window: number;
  ranked: boolean;
  rank: number | null;
  rank_7d_ago: number | null;
  rank_change_7d: number | null;
  combined_score: {
    value: number | null;
    rank: number | null;
    components: {
      form_z: number | null;
      trend_z: number | null;
      residual_z: number | null;
      elo_z: number | null;
    };
    null_reason: string | null;
  };
  ratings: { ortg: MomentumRating; drtg: MomentumRating; net: MomentumRating };
  model_residual: {
    value: number | null;
    residual_games_in_window: number;
    ranked: boolean;
    rank: number | null;
    basis: string;
    null_reason: string | null;
  };
  residual_games_in_window: number;
  opponent_adjusted_form: { value: number | null; games: number; rank: number | null };
  drivers: Record<string, unknown> & {
    unit?: string;
    shot_profile?: Record<string, number | null>;
  };
  elo: {
    current: number;
    rank: number;
    change_7d: number;
    change_14d: number;
    rank_change_7d: number;
    rank_change_14d: number;
    change_in_window: number;
  };
  schedule_strength: {
    faced_window: number;
    faced_season: number;
    faced_season_rank: number;
    next_week: {
      games: number;
      opponent_win_pct: number | null;
      rank: number | null;
      null_reason: string | null;
      opponents: MomentumNextWeekGame[];
    };
  };
  flags: MomentumFlag[];
  sparkline: { date: string; net_rating: number }[];
  sort_keys: Record<string, number | null>;
  rank_history: {
    week_start: string;
    as_of: string;
    rank: number;
    combined_score: number;
    reconstruction: boolean;
  }[];
}

export interface MomentumBoard {
  window: number;
  ranked_count: number;
  team_count: number;
  note?: string | null;
  rows: MomentumRow[];
}

export interface MomentumFlagDefinition {
  id: number;
  key: string;
  group: string;
  label: string;
  test: string;
}

export interface MomentumValidationSample {
  sample: string;
  available: boolean;
  reason?: string;
  mean_ic?: number;
  equal_weight_mean_ic?: number;
  n_dates?: number;
  date_range?: string[];
  components_used?: string[];
  note?: string;
}

export interface MomentumMethods {
  windows: { sizes: number[]; default: number };
  possessions: string;
  ratings: string;
  model_residual: {
    min_games_for_rank: string;
    coverage: {
      resolved_logged_with_margin: number;
      panel_games: number;
      panel_games_with_margin: number;
    };
  };
  combined_score: {
    weights: { form: number; trend: number; residual: number; elo: number };
    validation: {
      current_season: MomentumValidationSample[];
      previous_season: MomentumValidationSample[];
    };
  };
  elo: {
    k: number;
    home_advantage_elo: number;
    mean: number;
    season_carry: number;
    margin_multiplier: string;
  };
  schedule_strength: string;
  flags: { definitions: MomentumFlagDefinition[] };
  rank_history: { starts: string; reconstruction: boolean };
}

export interface MomentumPayload {
  schema_version: number;
  generated_at: string;
  season: string;
  through_date: string;
  windows: number[];
  default_window: number;
  ranked_counts: Record<string, number>;
  sort_options: MomentumSortOption[];
  boards: Record<string, MomentumBoard>;
  methods: MomentumMethods;
}
