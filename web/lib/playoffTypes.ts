// ==============================================================================
// web/lib/playoffTypes.ts
// Type definitions for Interactive MLB Playoff Series Matchup Simulator (/series)
// ==============================================================================

export interface PlayoffStarter {
  playerId: string;
  mlbamId: string;
  playerName: string;
  rGS: number;
  projEra: number;
  xFip: number;
  kPct: number;
  bbPct: number;
  role: string;
}

export interface PlayoffReliever {
  playerId: string;
  playerName: string;
  projEra: number;
  xFip: number;
  kPct: number;
  role: string;
}

export interface PlayoffHitter {
  playerId: string;
  playerName: string;
  wOBA: number;
  iso: number;
  obp: number;
  hr: number;
  kPct: number;
  bbPct: number;
  slot: string;
}

export interface MlbTacticalRatings {
  rotationDepth: number;     // 0-100: Quality and depth of starting pitching rotation
  bullpenLeverage: number;   // 0-100: Late-inning shutdown capability & fatigue resilience
  powerIso: number;          // 0-100: Lineup power, barrel rate, and home run impact
  contactDiscipline: number; // 0-100: Contact% in zone, low whiff, and K-avoidance
  defenseFielding: number;   // 0-100: Defensive run prevention & catcher framing
}

export interface TeamPlayoffProfile {
  teamAbbr: string;
  teamName: string;
  fullName: string;
  league: 'AL' | 'NL';
  division: string;
  regularWins: number;
  baseElo: number;
  tacticalRatings: MlbTacticalRatings;
  starters: PlayoffStarter[];
  relievers: PlayoffReliever[];
  lineupCore: PlayoffHitter[];
}

export interface GameOutcomeProb {
  games: number;
  winner: string;
  probPct: number;
}

export interface TacticalEdge {
  title: string;
  advantageTeam: string;
  description: string;
  deltaElo: number;
}

export interface GameScheduleDetail {
  gameNumber: number;
  homeTeam: string;
  awayTeam: string;
  starterA: string;
  starterB: string;
  starterArGS: number;
  starterBrGS: number;
  winProbA: number;
  winProbB: number;
}

export interface SeriesSimulationResult {
  teamA: string;
  teamB: string;
  hcaTeam: string;
  seriesLength: number;
  winsToClinch: number;
  baseEloDiff: number;
  tacticalMismatchAdjustment: number;
  winProbA: number;
  winProbB: number;
  fairMlA: number;
  fairMlB: number;
  avgGames: number;
  sweepProb: number;
  gameDistributions: GameOutcomeProb[];
  tacticalEdges: TacticalEdge[];
  gameSchedule: GameScheduleDetail[];
}

export interface PrecomputedMatchup {
  matchupKey: string;
  teamA: string;
  teamB: string;
  hcaTeam: string;
  series7: SeriesSimulationResult;
  series5: SeriesSimulationResult;
  series3: SeriesSimulationResult;
}

export interface PlayoffMatchupsCatalog {
  updatedAt: string;
  nSims: number;
  teams: Record<string, TeamPlayoffProfile>;
  matchups: Record<string, PrecomputedMatchup>;
}
