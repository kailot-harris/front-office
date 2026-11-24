// ==============================================================================
// web/lib/playoffTypes.ts
// Type definitions for Interactive MLB Playoff Series Matchup Simulator (/series)
// ==============================================================================

export interface PlayoffStarter {
  playerId: string;
  mlbamId: string;
  playerName: string;
  rGS: number | null;
  projEra: number | null;
  xFip: number | null;
  kPct: number | null;
  bbPct: number | null;
  role: string;
}

export interface PlayoffReliever {
  playerId: string;
  playerName: string;
  projEra: number | null;
  xFip: number | null;
  kPct: number | null;
  role: string;
}

export interface PlayoffHitter {
  playerId: string;
  playerName: string;
  wOBA: number | null;
  iso: number | null;
  obp: number | null;
  hr: number | null;
  kPct: number | null;
  bbPct: number | null;
  slot: string;
}

export interface MlbTacticalRatings {
  rotationDepth: number | null;     // 0-100: Quality and depth of starting pitching rotation
  bullpenLeverage: number;          // 0-100: Late-inning shutdown capability & fatigue resilience
  powerIso: number | null;          // 0-100: Lineup power, barrel rate, and home run impact
  contactDiscipline: number | null; // 0-100: Contact% in zone, low whiff, and K-avoidance
  defenseFielding: number;          // 0-100: Defensive run prevention & catcher framing
}

export interface TeamPlayoffProfile {
  teamAbbr: string;
  teamName: string;
  fullName: string;
  league: 'AL' | 'NL';
  division: string;
  regularWins: number;
  baseElo: number | null;
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
  starterArGS: number | null;
  starterBrGS: number | null;
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
  generated_at: string;
  updatedAt: string;
  nSims: number;
  teams: Record<string, TeamPlayoffProfile>;
  matchups: Record<string, PrecomputedMatchup>;
}
