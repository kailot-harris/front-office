// ==============================================================================
// coachingTypes.ts
// Type definitions for WNBA Coaching Staff & Impact Analytics
// ==============================================================================

export interface HeadCoachInfo {
  name: string;
  tenureYears: number;
  careerGames: number;
  careerWinPct: number;
  coachingTree: string;
  tacticalArchetype: string;
}

export interface AssistantsInfo {
  associateHC: string;
  offensiveCoord: string;
  defensiveCoord: string;
  playerDevLead: string;
}

export interface CoachingMetrics {
  coachImpactRating: number;      // 0-100 composite score
  talentExpectedWins: number;     // Wins predicted strictly from roster talent (44-game scale)
  actualProjectedWins: number;    // Model projection incorporating coaching & market
  coachingWinsAdded: number;      // Marginal win lift (delta)
  atoOffensivePpp: number;        // Points per possession on ATOs
  atoDefensivePppAllowed: number; // Opponent PPP on ATOs
  challengeSuccessRate: number;   // % challenges overturned
  challengeWpa: number;           // Win probability added from challenges
  shotQualityLiftEfg: number;     // eFG% lift over shot quality baseline
  rotationStaggerScore: number;   // 0-100 score for star staggering
  playerDevelopmentScore: number; // 0-100 score for young player growth
}

export interface RadarPercentiles {
  atoMastery: number;
  tacticalInnovation: number;
  rotationEfficiency: number;
  inGameWpa: number;
  playerDevelopment: number;
}

export interface CoachingStaffMetric {
  season?: number;
  teamAbbr: string;
  teamName: string;
  headCoach: HeadCoachInfo;
  assistants: AssistantsInfo;
  metrics: CoachingMetrics;
  radarPercentiles: RadarPercentiles;
}
