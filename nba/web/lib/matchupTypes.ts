/**
 * Types for web/public/data/matchups_slates.json, produced by
 * build_matchups_dataset.R at the repo root.
 *
 * SEASON SCOPE: the dataset covers EXACTLY ONE NBA season — the one named by
 * `season_label` (e.g. '2026-2027'). `season` is that season in hoopR's end-year
 * numbering (2027 === the 2026-2027 season), which is NOT config.R's
 * CURRENT_SEASON convention and is NOT the accuracy log's `season` column (the
 * log labels two different seasons 2026, so it cannot scope anything). The
 * spine is `schedule_source` — the full hoopR schedule for that one season —
 * so week indices are contiguous from 1 and no game from any other season can
 * appear. See the SEASON SCOPE block in build_matchups_dataset.R.
 *
 * GRADING STATE: a game is graded only once the accuracy log has RESOLVED it
 * and a real box score exists. Early in a season that legitimately means zero
 * graded games, recorded explicitly as `graded_games_available: false` /
 * `grading_state: 'no_games_graded_yet'`, with `accuracy_pct: null` on every
 * week. Consumers must render a "not yet graded" state from this, never 0/0,
 * NaN% or a misleading 0%.
 *
 * DESIGN DECISION 1 - SLATE GRANULARITY: week-of-season buckets, not per-day
 * slates. `slate` is a 1-based index of fixed 7-day windows measured from the
 * season's first game date (see build_matchups_dataset.R). The NBA plays daily,
 * so per-day slates would mean ~170 ribbon entries and an ~8-game sample behind
 * each "X / Y correct (Z%)" accuracy figure; week buckets keep the ribbon
 * navigable and the accuracy stat stable, and match issue #16's week language.
 * This is the only granularity in the dataset or the UI.
 *
 * DESIGN DECISION 2 - TWO PROJECTION BASES, NEVER MIXED. Projections on this
 * page come from TWO DIFFERENT MODELS, and `projection_basis` always says
 * which. They are not interchangeable: do not average them, do not rank or
 * aggregate across them, and never render one as if it were the other (NBA
 * issue #14 is open against exactly that class of defect).
 *
 *  - LOGGED MODEL ('logged_model_margin', 'margin_from_logged_win_prob') —
 *    the richer model. The daily slate engine's win probability, written per
 *    game into cache/prediction_accuracy_log.rds before tip-off by
 *    prediction_accuracy_logger.R and graded there afterwards. This is the only
 *    basis that is ever graded. Covers a few dozen games, since the logger runs
 *    only a few days ahead. A logged projection is never overwritten.
 *  - TEAM RATING DIFFERENTIAL ('team_rating_differential') — the simpler
 *    model, filling every game the log has not predicted. Verbatim the
 *    computation prediction_accuracy_logger.R:142-172 already uses:
 *    (home Net_Rating − away Net_Rating) + 2.40 home-court points, turned into
 *    a win probability by pnorm(margin / MARGIN_SIGMA). No rest, travel or
 *    injury adjustment, and nothing simulated.
 *
 * A game with neither has `has_projection: false` and null in every projection
 * field, never a placeholder number.
 */

/**
 * Which model produced a game's projection. The first two values are the same
 * logged model (the second just derives the margin from its probability); the
 * third is the separate, simpler ratings computation.
 */
export type ProjectionBasis =
  | 'logged_model_margin'
  | 'margin_from_logged_win_prob'
  | 'team_rating_differential';

export interface MatchupGame {
  /** ESPN game id, from the schedule spine. */
  game_id: string;
  /** Week-of-season bucket index (see DESIGN DECISION 1 above). */
  slate: number;
  game_date: string;
  weekday: string;
  /** hoopR end-year season number; identical for every game in the dataset. */
  season: number;
  /** Canonical NBA abbreviation, as keyed in lib/teams.ts. */
  home_team: string;
  away_team: string;
  home_team_name: string;
  away_team_name: string;
  is_completed: boolean;
  /** True when the game carries a projection from either basis. */
  has_projection: boolean;
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
  /** Games in the slate projected by the logged model (either logged basis). */
  logged_projection_total: number;
  /** Games in the slate projected from team rating differential. */
  ratings_projection_total: number;
  /** Completed, graded games in the slate — the denominator of accuracy_pct. */
  graded_total: number;
  correct_total: number;
  /** Null — not 0 — when nothing in the week is graded yet. */
  accuracy_pct: number | null;
}

/** Whether anything in the season has been graded yet. */
export type GradingState = 'graded' | 'no_games_graded_yet';

export interface MatchupsDataset {
  /** hoopR end-year season number (2027 === the 2026-2027 season). */
  season: number;
  /** Human-facing span, e.g. '2026-2027'. */
  season_label: string;
  generated_at: string;
  slate_granularity: 'week_of_season';
  season_start_date: string;
  season_end_date: string;
  /** The hoopR call that produced the single-season schedule spine. */
  schedule_source: string;
  active_slate: number;
  available_slates: number[];
  total_games: number;
  completed_games: number;
  pending_games: number;
  games_with_projection: number;
  games_without_projection: number;
  /** Games projected by the logged model — counted separately, never summed. */
  games_logged_basis: number;
  /** Games projected from team rating differential. */
  games_ratings_basis: number;
  /** Human-readable description of the ratings-derived computation. */
  ratings_source: string;
  /** Share of scheduled games whose two teams were both found in the ratings table. */
  rating_match_rate_pct: number;
  /** Measured join rate of the accuracy log onto the schedule, never assumed. */
  logged_predictions_in_season: number;
  logged_predictions_matched: number;
  join_match_rate_pct: number;
  graded_games_available: boolean;
  grading_state: GradingState;
  slates: MatchupSlate[];
  matchups: MatchupGame[];
}
