// ==============================================================================
// coachingTypes.ts
// Type definitions for NBA Coaching Staff & Impact Analytics
// ==============================================================================

export interface CoachingMetrics {
  coachImpactRating: number | null;      // 0-100 composite score (null when unobserved)
  talentExpectedWins: number;            // Wins predicted strictly from roster talent
  actualProjectedWins: number;           // Model projection incorporating coaching & market
  coachingWinsAdded: number;             // Marginal win lift (delta)
  atoOffensivePpp: number | null;        // Points per possession on ATOs
  atoDefensivePppAllowed: number | null; // Opponent PPP on ATOs
  challengeSuccessRate: number | null;   // % challenges overturned
  atoOffPossessions: number;             // Sample count of offensive ATO possessions
  atoDefPossessions: number;             // Sample count of defensive ATO possessions
  challengeAttempts: number;             // Sample count of coach's challenge events
}

export interface RadarPercentiles {
  atoMastery: number | null;
  tacticalInnovation: number;
  rotationEfficiency: number;
  inGameWpa: number | null;
  playerDevelopment: number;
}

/**
 * Where each metric block actually came from, emitted by build_coaching_dataset.R.
 *
 * `observed_pbp` means the field was measured from cache/pbp_timeout_cache.rds.
 * `model_residual_ensemble_minus_bottom_up` is the residual between two of the
 * project's own model variants, never a measured coach effect.
 * `unobserved` indicates play-by-play is unavailable and the metric is null.
 */
export type CoachingProvenanceTag =
  | 'observed_pbp'
  | 'model_residual_ensemble_minus_bottom_up'
  | 'unobserved';

export interface CoachingProvenance {
  atoMetrics: CoachingProvenanceTag;
  challengeMetrics: CoachingProvenanceTag;
  coachingWinsAdded: CoachingProvenanceTag;
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
  metrics: CoachingMetrics;
  radarPercentiles: RadarPercentiles;
  provenance: CoachingProvenance;
}
