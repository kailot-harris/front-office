// ==============================================================================
// web/lib/shotTypes.ts
// Type definitions for WNBA Player Shot Charts, Zones, and Spatial Telemetry
// ==============================================================================

export interface ShotRecord {
  x: number;          // Court width in feet: -25 to +25 (0 = basket center)
  y: number;          // Distance from baseline in feet: 0 to 47
  dist: number;       // Distance from hoop in feet
  val: 2 | 3;         // 2-point or 3-point field goal
  made: boolean;      // True if made, false if missed
  zone: string;       // 14 discrete spatial zone
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
  /**
   * UTC ISO-8601 stamp written by the R exporter for publish_web.R's assertion
   * F. Optional because payloads written before the stamp landed do not carry
   * it; declared here because tests/contracts/types-vs-data.test.ts fails any
   * payload key absent from this interface, so an undeclared stamp would turn
   * the contract suite -- and therefore the fatal publish gate -- red the first
   * time a stamped payload was written. Distinct from the camelCase
   * `generatedAt` some of these payloads already carry: assertion F only ever
   * matches the snake_case key.
   */
  generated_at: string;
  season?: number;
  updated_at: string;
  total_shots_sampled: number;
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
