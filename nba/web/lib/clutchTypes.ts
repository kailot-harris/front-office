/**
 * Minimum clutch field-goal attempts for a player to get clutch rates, a USCI
 * rank and an archetype (NBA#90). Must equal MIN_CLUTCH_FGA in
 * build_clutch_dataset.R. 20 is the default; the value is the owner's to tune.
 */
export const CLUTCH_MIN_FGA = 20;

/**
 * Season the clutch play-by-play covers. build_clutch_dataset.R reads
 * cache/nba_pbp_cache.rds (else cache/nba_pbp_2026.rds); both hold the 2025-26
 * season (games 2025-10-21 to 2026-06-13: regular season, play-in and playoffs).
 */
export const CLUTCH_DATA_SEASON = '2025-2026';
export interface ShotZoneStats {
  fga: number;
  fgm: number;
  pct: number;
}

export interface ClutchShotBreakdown {
  totalClutchFga: number;
  rim: ShotZoneStats;
  mid: ShotZoneStats;
  three: ShotZoneStats;
}

export interface ClutchProfile {
  playerId: string;
  playerName: string;
  team: string;
  position: string;
  /** Clutch field-goal attempts (the sample behind every clutch rate). */
  clutchFga: number;
  /** true when clutchFga >= CLUTCH_MIN_FGA. */
  qualified: boolean;
  /** USCI rank among qualified players (1 = highest); null when not qualified. */
  clutchRank: number | null;
  /** null when the player is under CLUTCH_MIN_FGA. */
  clutchArchetype: string | null;
  clutchMpg: number | null;
  clutchUsgPct: number | null;
  clutchTsPct: number | null;
  baseTsPct: number | null;
  tsDelta: number | null;
  usciScore: number | null; // Unassisted Shot Creation Index
  unassistedFgmPct: number | null;
  clutchPpp: number | null;
  tovFragility: number | null; // Delta TOV% under pressure
  cDwpa: number | null; // Clutch Defensive Win Probability Added (%)
  shotBreakdown: ClutchShotBreakdown;
}
