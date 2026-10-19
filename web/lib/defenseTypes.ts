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
  defensiveRole: string;
  versatilityScore: number; // Shannon Entropy [0-100]
  rimDfgDelta: number; // Opponent Rim FG% delta (negative is elite)
  rimDeterrenceIndex: number; // Rim attempts suppressed
  poaNavigation: number; // Screen navigation [0-100]
  dRapm: number;
  matchupDist: MatchupDist;
}
