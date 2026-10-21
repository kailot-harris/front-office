/**
 * Types for web/public/data/matchups_slates.json, produced by
 * build_matchups_dataset.R at the repo root.
 *
 * DESIGN DECISION 1 - SLATE GRANULARITY: week-of-season buckets, not per-day
 * slates. `slate` is a 1-based index of fixed 7-day windows measured from the
 * season's first game date (see build_matchups_dataset.R). The NBA plays daily,
 * so per-day slates would mean ~170 ribbon entries and an ~8-game sample behind
 * each "X / Y correct (Z%)" accuracy figure; week buckets keep the ribbon
 * navigable and the accuracy stat stable, and match issue #16's week language.
 * This is the only granularity in the dataset or the UI.
 *
 * DESIGN DECISION 2 - FUTURE-GAME PROJECTIONS: a pending game's projection is
 * never invented. It comes from the PENDING row that
 * prediction_accuracy_logger.R already writes into
 * cache/prediction_accuracy_log.rds before tip-off, which carries a real
 * model-produced home win probability. Because those rows leave the margin
 * blank, `predicted_margin` for a pending game is the inversion of that same
 * logged probability through this repo's documented margin -> win-probability
 * map (config.R MARGIN_SIGMA), flagged by `projection_basis:
 * 'margin_from_logged_win_prob'`. If a game has no logged probability at all,
 * every projection field is null rather than filled in.
 */

/** Where a game's projected margin came from. */
export type ProjectionBasis = 'logged_model_margin' | 'margin_from_logged_win_prob';

export interface MatchupGame {
  game_id: string;
  /** Week-of-season bucket index (see DESIGN DECISION 1 above). */
  slate: number;
  game_date: string;
  weekday: string;
  season: number;
  /** Canonical NBA abbreviation, as keyed in lib/teams.ts. */
  home_team: string;
  away_team: string;
  home_team_name: string;
  away_team_name: string;
  is_completed: boolean;
  projection_basis: ProjectionBasis | null;
  predicted_margin: number | null;
  predicted_home_win_prob: number | null;
  predicted_away_win_prob: number | null;
  predicted_winner: string | null;
  /** Result fields are populated for completed games only; null while pending. */
  home_score: number | null;
  away_score: number | null;
  actual_margin: number | null;
  actual_winner: string | null;
  /** Copied verbatim from the accuracy log's `correct` column, never regraded. */
  prediction_correct: boolean | null;
}

export type SlateStatus = 'past' | 'active' | 'future';

export interface MatchupSlate {
  slate: number;
  label: string;
  start_date: string;
  end_date: string;
  status: SlateStatus;
  games_total: number;
  /** Completed, graded games in the slate — the denominator of accuracy_pct. */
  graded_total: number;
  correct_total: number;
  accuracy_pct: number | null;
}

export interface MatchupsDataset {
  season: number;
  generated_at: string;
  slate_granularity: 'week_of_season';
  season_start_date: string;
  active_slate: number;
  available_slates: number[];
  total_games: number;
  completed_games: number;
  pending_games: number;
  slates: MatchupSlate[];
  matchups: MatchupGame[];
}
