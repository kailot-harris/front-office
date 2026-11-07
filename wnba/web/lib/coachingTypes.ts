// ==============================================================================
// coachingTypes.ts
// Type definitions for WNBA Coaching Staff & Impact Analytics (Issues #145, #151)
// ==============================================================================

export interface HeadCoachInfo {
  name: string;
  tenureStart: number;
  tenureYears: number;
  registrySeason: number;
  sourceCitation: string;
  sourceVerifiedDate: string;
}

export interface CoachingMetrics {
  coachImpactRating: number;      // 0-100 composite score
  talentExpectedWins: number;     // Wins predicted strictly from roster talent (44-game scale)
  actualProjectedWins: number;    // Model projection incorporating coaching & market
  coachingWinsAdded: number;      // Marginal win lift (delta)
  atoOffensivePpp: number;        // Points per possession on ATOs
  atoDefensivePppAllowed: number; // Opponent PPP on ATOs
  challengeSuccessRate: number;   // % challenges overturned (0-1 rate)
  atoOffPossessions: number;      // Sample count of offensive ATO possessions
  atoDefPossessions: number;      // Sample count of defensive ATO possessions
  challengeAttempts: number;      // Sample count of coach's challenge events
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
  metrics: CoachingMetrics;
  radarPercentiles: RadarPercentiles;
}
