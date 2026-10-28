// ==============================================================================
// playoffTypes.ts
// Type definitions for Interactive 7-Game Playoff Series Matchup Simulator
// ==============================================================================

export interface PlayoffPlayer {
  playerId: number;
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
  games: number;           // 4, 5, 6, 7
  winner: string;          // teamAbbr
  probPct: number;         // e.g. 18.5%
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

export interface PlayoffMatchupsCatalog {
  /**
   * UTC ISO-8601 stamp written by the R exporter for publish_web.R's assertion
   * F. Optional because payloads written before the stamp landed do not carry
   * it; declared here because tests/contracts/types-vs-data.test.ts fails any
   * payload key absent from this interface, so an undeclared stamp would turn
   * the contract suite -- and therefore the fatal publish gate -- red the first
   * time a stamped payload was written.
   */
  generated_at: string;
  teams: Record<string, TeamPlayoffProfile>;
  sampleMatchups: PlayoffSeriesMatchupResult[];
}
