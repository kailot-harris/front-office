// ==============================================================================
// web/lib/shotTypes.ts
// Type definitions for NBA Player Shot Charts, Zones, and Spatial Telemetry
// ==============================================================================

export interface ShotRecord {
  x: number;          // Court width in feet: -25 to +25 (0 = basket center)
  y: number;          // Distance from baseline in feet: 0 to 47
  dist: number;       // Distance from hoop in feet
  val: 2 | 3;         // 2-point or 3-point field goal
  made: boolean;      // True if made, false if missed
  zone: string;       // NBA classified spatial zone
  type: string;       // Play type (e.g. Pullup Jump Shot, Driving Layup)
  period: number;     // 1, 2, 3, 4, or OT
  clock: string;      // Game clock (e.g. "11:23")
}

export interface PlayerShotData {
  player_id: string;
  player_name: string;
  team: string;
  total_shots: number;
  shots: ShotRecord[];
}

export interface ZoneLeagueAverage {
  zone: string;
  total_fga: number;
  total_fgm: number;
  lg_fg_pct: number;
}

export interface ShotsMetadata {
  updated_at: string;
  total_shots_sampled: number;
  /**
   * NBA season(s) the shots were taken in, e.g. '2025-2026'. `updated_at` is when the
   * file was generated, which says nothing about how old the shots are — these two
   * have been several seasons apart. Optional: files written before this field
   * existed do not carry it.
   */
  source_season_label?: string;
  league_averages: ZoneLeagueAverage[];
  zones: string[];
}

export interface PlayerCatalogEntry {
  player_id: string;
  player_name: string;
  team: string;
  total_shots: number;
}

export type ZoneStatus = 'HOT' | 'COLD' | 'NEUTRAL' | 'LOW_SAMPLE';

export interface ZoneMetric {
  zone: string;
  fga: number;
  fgm: number;
  fgPct: number;
  freqPct: number;
  lgPct: number;
  deltaPct: number;
  shrunkPct: number;
  zScore: number;
  status: ZoneStatus;
  pps: number;         // Points per shot
  lgPps: number;       // League points per shot
  deltaPps: number;
}

export interface HexBin {
  id: string;
  x: number;
  y: number;
  fga: number;
  fgm: number;
  fgPct: number;
  lgPct: number;
  deltaPct: number;
  freqPct: number;
  points: string;     // SVG polygon points string
}
