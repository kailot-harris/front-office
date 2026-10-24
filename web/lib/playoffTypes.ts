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

// ==============================================================================
// Current-season bracket: prediction beside result (GitHub issue #92)
// Produced by build_playoff_bracket_2026.R, shipped by export_web_json.R as
// public/data/playoff_bracket_2026.json.
// ==============================================================================

/** One point on a series-length distribution, e.g. P(series goes 4 games). */
export interface BracketLengthProb {
  length: number;
  label: string;
  probability: number;
}

/**
 * The numbers behind one series prediction.
 *
 * `ratingBasis` is load-bearing and not decoration: the rounds on this page do
 * NOT share a ratings basis. Round 1 is reconstructed from regular-season games
 * only; the Semifinals carry the 2026-10-04 archived forecast, whose ratings
 * pooled regular-season and Round 1 postseason games. Always render it next to
 * the numbers so a reader knows which they are looking at.
 */
export interface BracketForecast {
  ratingBasis: string;
  /** Date the forecast was made, for archived rounds. Empty for reconstructions. */
  asOf: string;
  format: 'bo3' | 'bo5' | 'bo7';
  formatLabel: string;
  teamHigh: string;
  teamHighAbbr: string;
  teamLow: string;
  teamLowAbbr: string;
  /** Regular-season seed, when the prediction was built from derived seeds. */
  seedHigh: number | null;
  seedLow: number | null;
  netHighAdj: number;
  netLowAdj: number;
  pHighSeedWin: number;
  pLowSeedWin: number;
  predictedWinnerName: string;
  predictedWinner: string;
  expectedGames: number;
  lengthDistribution: BracketLengthProb[];
  /** 'pending' while the series is still being played — not a wrong call. */
  resultStatus: 'correct' | 'incorrect' | 'pending';
  /** Archived rounds only: fair moneyline and average games as stored. */
  fairMlHigh?: number;
  fairMlLow?: number;
  avgSeriesGames?: number;
}

/**
 * `provenance` distinguishes the two deliberately different prediction sources:
 *   - 'round1_reconstruction' — retrodicted now, no archived forecast existed.
 *   - 'archived_forecast'     — copied verbatim from the pre-series archive.
 *   - 'unavailable'           — no prediction recorded; `forecast` is null.
 */
export interface BracketPrediction {
  available: boolean;
  provenance: 'round1_reconstruction' | 'archived_forecast' | 'unavailable';
  provenanceLabel: string;
  forecast: BracketForecast | null;
}

/**
 * Carries the same ten fields as `HistoricalSeries` so this payload and the
 * historical archive speak one shape, plus the current-season extras.
 *
 * `seriesComplete` matters: the box-score feed only contains games already
 * played, so a series in progress is indistinguishable from a short one by
 * games count alone. When it is false, `winner`/`winnerName` mean "currently
 * leading", not "won".
 */
export interface BracketSeries {
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
  winsA: number;
  winsB: number;
  seriesComplete: boolean;
  prediction: BracketPrediction;
}

export interface PlayoffBracketSeason {
  season: number;
  generatedAt: string;
  sourceNote: string;
  series: BracketSeries[];
}
