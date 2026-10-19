// ==============================================================================
// playoffTypes.ts
// Type definitions for Interactive WNBA Playoff Series Matchup Simulator
// ==============================================================================

export interface PlayoffPlayer {
  playerId: string | number;
  playerName: string;
  position: string;
  regularMpg: number;
  playoffMpg: number;
  pts: number;
  reb: number;
  ast: number;
  praZscore: number;
  role: 'Starter' | 'Sixth Man' | 'Rotation Bench';
}

export interface TacticalRatings {
  perimeterCreation: number;     // 0-100 (Pull-up 3s & ISO shot-making)
  dropVulnerability: number;     // 0-100 (Susceptibility to pick-and-roll pull-ups)
  interiorDominance: number;     // 0-100 (Rim pressure & offensive glass)
  switchability: number;         // 0-100 (Point-of-attack switch equity)
  clutchExecution: number;       // 0-100 (Half-court late-game PPP)
}

export interface TeamPlayoffProfile {
  teamAbbr: string;
  teamName: string;
  conference: 'East' | 'West';
  regularWins: number;
  regularNetRtg: number;
  playoffNetRtg: number;
  top3TalentBump: number;
  tacticalRatings: TacticalRatings;
  rotation: PlayoffPlayer[];
}

export interface GameOutcomeProb {
  games: number;           // 2, 3 (Bo3), 3, 4, 5 (Bo5), 4, 5, 6, 7 (Bo7)
  winner: string;          // teamAbbr
  probPct: number;         // e.g. 24.5%
}

export interface TacticalEdge {
  title: string;
  advantageTeam: string;
  description: string;
  deltaMargin: number;
}

export interface PlayoffSeriesMatchupResult {
  teamA: string;
  teamB: string;
  hcaTeam: string;
  format?: 'bo3' | 'bo5' | 'bo7';
  ratingDiffRaw: number;
  tacticalMismatchAdjustment: number;
  netRatingMargin: number;
  winProbA: number;
  winProbB: number;
  fairMlA: number;
  fairMlB: number;
  avgGames: number;
  spreadMinus1_5Prob: number;
  sweepProb: number;
  gameDistributions: GameOutcomeProb[];
  tacticalEdges: TacticalEdge[];
}

export interface HistoricalGame {
  gameDate: string;
  teamA: string;
  scoreA: number;
  teamB: string;
  scoreB: number;
}

export interface HistoricalSeries {
  teamA: string;
  teamNameA: string;
  teamB: string;
  teamNameB: string;
  winner: string;
  winnerName: string;
  round: string;
  gamesPlayed: number;
  seriesLength: number;
  games: HistoricalGame[];
}

export interface PlayoffMatchupsCatalog {
  teams: Record<string, TeamPlayoffProfile>;
  sampleMatchups: PlayoffSeriesMatchupResult[];
  historicalBrackets?: Record<string, HistoricalSeries[]>;
}
