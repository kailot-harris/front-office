/**
 * Data window stamped by the clutch, defense and Player DNA builders
 * (front-office#191). Every field is read from the published JSON; pages never
 * hand-type a season label.
 */
export interface SeasonWindow {
  /** Season label derived from CURRENT_SEASON in config.R, e.g. '2026-27'. */
  season: string;
  /** Latest game_date present in the play-by-play input (YYYY-MM-DD). */
  throughDate: string;
  /** UTC ISO timestamp of the builder run. */
  generatedAt: string;
  /** Season the ridge RAPM input was fit on; present only when it can differ from `season`. */
  rapmSeason?: string;
}

/** Window of the payloads that publish ridge RAPM (defense, Player DNA): rapmSeason is always present. */
export interface RapmSeasonWindow extends SeasonWindow {
  rapmSeason: string;
}

/** Top-level envelope of clutch_leverage_metrics.json, defensive_metrics.json and player_dna_profiles.json. */
export interface SeasonWindowPayload<T> extends SeasonWindow {
  profiles: T[];
}

export function splitSeasonPayload<T, W extends SeasonWindow = SeasonWindow>(
  payload: SeasonWindowPayload<T> & W
): { profiles: T[]; seasonWindow: W } {
  const { profiles, ...seasonWindow } = payload;
  return { profiles, seasonWindow: seasonWindow as unknown as W };
}
