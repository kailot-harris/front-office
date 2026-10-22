// ==============================================================================
// web/lib/matchupTypes.ts
// Type definitions for the Weekly Matchup Slates dataset (/matchups)
//
// Source: web/public/data/matchups_slates.json, written by
// export_matchup_slates() in tools/export_web_data.R.
// ==============================================================================

/** Where a game's displayed win probability came from. */
export type ProjectionSource =
  /** The Elo engine's pre-game (walk-forward) probability. Gradeable. */
  | 'walk_forward'
  /** Forward-looking projection from current team Elo. Not gradeable. */
  | 'current_elo';

/** A slate's position relative to the most recent week with results. */
export type SlateStatus = 'past' | 'active' | 'future';

export interface Matchup {
  game_pk: number;
  /** Local game date, YYYY-MM-DD. */
  game_date: string;
  /** Monday-anchored week of season; week 1 holds the season's first game. */
  week: number;
  /** MLB game type code: R, F (wild card), D, L (LCS), W (World Series). */
  game_type: string;
  series_description: string;
  /** Raw MLB status, e.g. "Final", "Scheduled", "Postponed", "Cancelled". */
  status_detail: string;
  venue_name: string;

  home_team_id: number;
  home_team_name: string;
  /** Canonical abbreviation for TeamLogo, e.g. "NYY". */
  home_team: string;
  away_team_id: number;
  away_team_name: string;
  away_team: string;

  is_completed: boolean;
  /** Home win probability in [0, 1]; see projection_source for its provenance. */
  home_win_prob: number;
  away_win_prob: number;
  projection_source: ProjectionSource;

  /** Present only when is_completed. */
  home_score: number | null;
  away_score: number | null;
  /**
   * Whether the pre-game pick was right: (home_win_prob > 0.5) === home_won.
   * Null when the game is ungraded — either unplayed, or played without a
   * walk-forward probability (the Elo history covers the regular season only).
   */
  prediction_correct: boolean | null;
}

export interface MatchupSlate {
  week: number;
  /** Human date range, e.g. "Mar 30 - Apr 5". */
  label: string;
  status: SlateStatus;
  /** Week bounds, YYYY-MM-DD (Monday and Sunday). */
  start_date: string;
  end_date: string;
  game_count: number;
  /** Games in this slate carrying a gradeable walk-forward prediction. */
  graded_count: number;
  correct_count: number;
}

export interface MatchupsDataset {
  season: number;
  generated_at: string;
  /** Week holding the most recent date with results. */
  active_week: number;
  total_games: number;
  completed_games: number;
  graded_games: number;
  correct_picks: number;
  /** Season-to-date correct-pick rate in [0, 1]; null when nothing is graded. */
  overall_accuracy: number | null;
  available_weeks: MatchupSlate[];
  matchups: Matchup[];
}
