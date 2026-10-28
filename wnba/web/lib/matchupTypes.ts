// Types for web/public/data/matchups_slates.json, written by the repo root's
// build_matchups_dataset.R (GitHub issue #74).
//
// These mirror that script's payload exactly. Read its header before changing
// anything here -- in particular the PROJECTION BASES and GRADING sections,
// which explain why several of these fields are nullable and why two of the
// booleans look redundant but are not.

/**
 * Which model produced a game's projection. NEVER present two different bases
 * as one number, and never rank or aggregate across them:
 *
 *  - `logged_model` / `logged_model_prob_only`: the real per-game model
 *    prediction, written before the game was played and the ONLY basis that is
 *    ever graded. `_prob_only` means the log had no margin, so the margin shown
 *    is that same logged probability inverted through margin = qnorm(p) * sigma
 *    -- same model, derived field.
 *  - `team_rating_differential`: a season-long net-rating difference plus a flat
 *    home-court constant, used only to fill games the model never predicted.
 *    NEVER graded. Much weaker than the logged bases; label it as such in the UI.
 */
export type ProjectionBasis =
  | 'logged_model'
  | 'logged_model_prob_only'
  | 'team_rating_differential';

/** ESPN season types, labelled by the builder rather than left as integers. */
export type SeasonTypeLabel = 'regular' | 'postseason' | (string & {});

export interface Matchup {
  /** ESPN event id, e.g. "401856890". */
  game_id: string;
  /** Local calendar date, "YYYY-MM-DD". */
  game_date: string;
  /** Week-of-season bucket. A LABEL, not an index -- see MatchupsPayload.available_weeks. */
  week: number;
  season_type: SeasonTypeLabel;
  /** ESPN abbreviations (GS, LA, LV, NY, WSH ...). */
  home_team: string;
  away_team: string;
  home_team_name: string;
  away_team_name: string;

  /**
   * The game has a real final score in the box scores.
   *
   * NOT the same thing as `is_graded`: for the 2026 season 352 games are
   * completed but only 44 are graded, because the prediction logger only
   * started writing on 2026-09-17.
   */
  is_completed: boolean;
  home_score: number | null;
  away_score: number | null;
  /** home_score - away_score. Never 0; basketball plays overtime. */
  actual_margin: number | null;
  /** Observed from the box score. Not a grade. */
  actual_winner: string | null;

  /** Some projection is available (either basis). */
  has_prediction: boolean;
  /**
   * A REAL model prediction was logged before the game (basis A).
   *
   * This is the field that separates "the model got this game wrong" from "no
   * prediction was ever recorded for this game". When false, do not imply the
   * model had a view: ~308 of the 2026 season's completed games are in exactly
   * that state and showing them as misses would fabricate a track record.
   */
  has_logged_prediction: boolean;
  projection_basis: ProjectionBasis | null;
  /** Points, positive favours the home team. */
  projected_margin: number | null;
  /** 0..1. */
  home_win_prob: number | null;
  predicted_winner: string | null;

  /** The accuracy log RESOLVED this game and the box score confirms it was played. */
  is_graded: boolean;
  /** Copied verbatim from the accuracy log. Null unless `is_graded`. */
  prediction_correct: boolean | null;
}

export interface MatchupWeek {
  week: number;
  start_date: string;
  end_date: string;
  /** A week can span both: the postseason break does not align to 7-day boundaries. */
  season_types: SeasonTypeLabel[];
  total_games: number;
  completed_games: number;
  pending_games: number;
  graded_games: number;
  /** Null when the week graded nothing -- render "not graded", never 0 or 0%. */
  correct_games: number | null;
  accuracy_pct: number | null;
}

/** Why a season-level accuracy figure may be absent. */
export type GradingState = 'no_games_graded_yet' | 'partial' | 'complete';

export interface MatchupSummary {
  total_games: number;
  completed_games: number;
  pending_games: number;
  graded_games: number;
  correct_games: number | null;
  accuracy_pct: number | null;
  /** False means NOTHING is graded -- a legitimate state, not an error. */
  graded_games_available: boolean;
  grading_state: GradingState;
  /** Played games with no logged model prediction. Publish this honestly. */
  played_without_logged_prediction: number;
}

/** Measured join/provenance figures, recorded by the builder rather than assumed. */
export interface MatchupProvenance {
  logged_predictions_in_window: number;
  logged_predictions_matched: number;
  logged_predictions_unmatched: number;
  log_match_pct: number;
  games_with_logged_prediction: number;
  hca_points: number;
  margin_sigma: number;
  ratings_source: string;
  basis_counts: Record<string, number>;
}

export interface MatchupsPayload {
  season: number;
  generated_at: string;
  season_start: string;
  season_end: string;
  /** The week the page should open on: the last week containing a played game. */
  active_week: number;
  /**
   * The weeks that actually HAVE games, ascending.
   *
   * NOT a dense 1..N range: the 2026 season is missing week 18 entirely (the
   * pre-playoff break). Always iterate this array; building a ribbon from
   * 1..max() renders a phantom empty week.
   */
  available_weeks: number[];
  summary: MatchupSummary;
  provenance: MatchupProvenance;
  weeks: MatchupWeek[];
  matchups: Matchup[];
}
