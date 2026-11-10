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
  clutchArchetype: string;
  clutchMpg: number | null;
  clutchUsgPct: number | null;
  clutchTsPct: number | null;
  baseTsPct: number;
  tsDelta: number | null;
  usciScore: number | null; // Unassisted Shot Creation Index
  unassistedFgmPct: number | null;
  clutchPpp: number | null;
  tovFragility: number | null; // Delta TOV% under pressure
  cDwpa: number | null; // Clutch Defensive Win Probability Added (%)
  shotBreakdown: ClutchShotBreakdown;
}
