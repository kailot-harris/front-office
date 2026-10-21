// ==============================================================================
// coachingTypes.ts
// Type definitions for NBA Coaching Staff & Impact Analytics
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
  talentExpectedWins: number;     // Wins predicted strictly from roster talent
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

/**
 * Where each metric block actually came from, emitted by build_coaching_dataset.R.
 *
 * `observed_pbp` means the field was measured from cache/pbp_timeout_cache.rds.
 * `synthetic_coach_band` means it was drawn from a hand-assigned per-coach range
 * and is not an observation. `coachingWinsAdded` is always a residual between two
 * of the project's own model variants, never a measured coach effect.
 */
export type CoachingProvenanceTag =
  | 'observed_pbp'
  | 'synthetic_coach_band'
  | 'model_residual_ensemble_minus_bottom_up';

export interface CoachingProvenance {
  atoMetrics: CoachingProvenanceTag;
  challengeMetrics: CoachingProvenanceTag;
  coachingWinsAdded: CoachingProvenanceTag;
  shotQualityLift: CoachingProvenanceTag;
  rotationAndDevelopment: CoachingProvenanceTag;
  /**
   * Season span the `observed_pbp` fields were measured over, e.g. '2025-2026' or
   * '2025-2026 + 2026-2027'. Absent when nothing on the card is observed — the pooled
   * window usually straddles two seasons, and early in a season almost all of it
   * comes from the previous one.
   */
  observedSeasons?: string | null;
  generatedAt: string;
}

export interface CoachingStaffMetric {
  teamAbbr: string;
  teamName: string;
  headCoach: HeadCoachInfo;
  assistants: AssistantsInfo;
  metrics: CoachingMetrics;
  radarPercentiles: RadarPercentiles;
  provenance: CoachingProvenance;
}
