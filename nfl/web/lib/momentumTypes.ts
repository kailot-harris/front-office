/**
 * Shape of public/data/momentum_board.json (written by build_momentum_board.R,
 * NFL_analytics#226; contract-tested in tests/contracts/momentum_board.contract.test.ts).
 * The /momentum page renders these values as published: it sorts, toggles and
 * expands, and never computes or fills a value. Every null carries a reason.
 */
export type MomentumComponent = 'form' | 'trend' | 'residual' | 'elo_change';
export type MomentumWeights = Record<MomentumComponent, number>;

export interface MomentumSortOption {
  key: string;
  label: string;
  descending: boolean;
}

export interface MomentumFlag {
  key:
    | 'one_score'
    | 'pythagorean'
    | 'fumble_recovery'
    | 'opp_fg_pct'
    | 'turnover_margin'
    | 'blowout_skew'
    | 'opponent_strength'
    | 'home_share'
    | 'rest_bye'
    | 'starting_qb_change'
    | 'key_players_missing';
  group: 'luck' | 'context' | 'availability';
  value: number | null;
  n: number | null;
  statistic: number | null;
  /** Always false: no flag carries a significance badge (owner decision, #226). */
  significant: false;
  null_reason?: string;
  detail?: Record<string, unknown>;
}

export interface MomentumNextOpponent {
  week: number;
  date: string;
  opponent: string;
  home: boolean;
  opponent_elo: number | null;
  opponent_elo_rank: number | null;
}

export interface MomentumRow {
  team: string;
  team_name: string;
  games_played: number;
  record: { wins: number; losses: number; ties: number };
  window: number;
  games_in_window: number;
  /** Last season's games in this window (mean_regress carry-over); label them on the page. */
  carried_games: number;
  current_season_games_in_window: number;
  carried_from_season: number | null;
  ranked: boolean;
  rank: number | null;
  rank_last_week: number | null;
  rank_last_week_null_reason: string | null;
  rank_change_week: number | null;
  rank_change_week_null_reason: string | null;
  combined_score: {
    value: number | null;
    rank: number | null;
    components: { form_z: number | null; trend_z: number | null; residual_z: number | null; elo_change_z: number | null };
    raw: { form: number | null; trend: number | null; residual: number | null; elo_change: number | null };
    weights: MomentumWeights;
    null_reason: string | null;
  };
  form: {
    epa_per_play: number | null;
    rank: number | null;
    season_to_date: number | null;
    opponent_adjusted_margin: number | null;
    opponent_adjusted_margin_rank: number | null;
  };
  epa_splits: {
    offense_adjusted: number | null;
    defense_adjusted: number | null;
    offense_adjusted_change: number | null;
    defense_adjusted_change: number | null;
    offense: number | null;
    defense: number | null;
    pass_offense: number | null;
    rush_offense: number | null;
    pass_defense: number | null;
    rush_defense: number | null;
    success_offense: number | null;
    success_defense: number | null;
  };
  residual: { per_game: number | null; basis: string };
  elo: {
    current: number;
    rank: number;
    change_in_window: number | null;
    change_since_last_week: number | null;
    change_since_last_week_null_reason: string | null;
    rank_change_since_last_week: number | null;
  };
  schedule_strength: {
    faced_window: number | null;
    faced_season: number | null;
    next_opponent: MomentumNextOpponent | null;
    next_opponent_null_reason: string | null;
  };
  flags: MomentumFlag[];
  sparkline: { week: number; game_id: string; opponent: string; form_epa: number | null }[];
  sort_keys: Record<string, number | null>;
  rank_history: {
    season: number;
    week: number;
    through_date: string;
    rank: number;
    combined_score: number;
    carried_games: number;
    reconstruction: boolean;
  }[];
}

export interface MomentumBoard {
  window: number;
  noisiest: boolean;
  label: string;
  ranked_count: number;
  team_count: number;
  carried_team_count: number;
  rows: MomentumRow[];
}

export interface MomentumPayload {
  schema_version: 1;
  generated_at: string;
  season: number;
  season_type: 'REG';
  through_date: string;
  through_week: number;
  completed_week: number;
  week_complete: boolean;
  season_phase: 'preseason' | 'early_season' | 'in_season';
  windows: number[];
  default_window: number;
  ranked_counts: Record<string, number>;
  sort_options: MomentumSortOption[];
  boards: Record<string, MomentumBoard>;
  methods: {
    summary: string;
    predictive_beyond_elo: false;
    source: Record<string, string | number>;
    windows: { sizes: number[]; noisiest: number; default_rule: string; note: string };
    carry_over: { method: string; keep: number; definition: string };
    form: string;
    combined_score: {
      components: Record<MomentumComponent, string>;
      standardisation: string;
      formula: string;
      weights: Record<string, MomentumWeights>;
      weights_source: string;
      flat_surface: string;
      refit: string;
    };
    elo: Record<string, string | number>;
    flags: {
      significance_shown: false;
      significance_hidden_reason: string;
      context_only: string[];
      definitions: { key: string; group: string; label: string; value: string; test: string }[];
      detail_source: string;
      key_players_missing: string;
      starting_qb_change: string;
    };
    rank_history: {
      file: string;
      starts: string | null;
      reconstruction: false;
      written_this_run: boolean;
      note: string | null;
      rule: string;
    };
  };
}
