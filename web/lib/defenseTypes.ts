export interface MatchupDist {
  pgPct: number;
  sgPct: number;
  sfPct: number;
  pfPct: number;
  cPct: number;
}

export interface DefensiveProfile {
  playerId: string;
  playerName: string;
  team: string;
  position: string;
  projMpg: number;
  // Every field below is null when its inputs are unobserved (no current-season box row,
  // no observed matchup events, or not in the RAPM fit). Nothing is imputed (#191).
  defensiveRole: string | null;
  versatilityScore: number | null; // Shannon Entropy [0-100]
  rimDfgDelta: number | null; // Opponent Rim FG% delta (negative is elite)
  rimDeterrenceIndex: number | null; // Rim attempts suppressed
  poaNavigation: number | null; // Screen navigation [0-100]
  /** Ridge RAPM from the season named by the payload rapmSeason (not the current season). */
  dRapm: number | null;
  matchupDist: MatchupDist | null;
}
