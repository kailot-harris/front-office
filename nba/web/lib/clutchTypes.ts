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
  clutchMpg: number;
  clutchUsgPct: number;
  clutchTsPct: number;
  baseTsPct: number;
  tsDelta: number;
  usciScore: number; // Unassisted Shot Creation Index
  unassistedFgmPct: number;
  clutchPpp: number;
  tovFragility: number; // Delta TOV% under pressure
  cDwpa: number; // Clutch Defensive Win Probability Added (%)
  shotBreakdown: ClutchShotBreakdown;
}
