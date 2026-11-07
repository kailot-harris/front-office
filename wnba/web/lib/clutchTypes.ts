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
  season?: number;
  playerId: string;
  playerName: string;
  team: string;
  position: string;
  clutchArchetype: string;
  clutchFga: number;
  clutchPoints: number | null;
  clutchFgPct: number | null;
  clutchScoringPlays: number | null;
  clutchPpp: number | null;
  provenance: string;
}
