/**
 * Layer 1 — strict Zod schemas for every dataset in public/data.
 *
 * `.strict()` everywhere: an unexpected key from the R exporters is a contract
 * break (the TS interfaces in lib/*Types.ts would silently not know about it).
 * Numeric fields carry domain bounds (82-game season, 48-minute games,
 * probabilities in [0,1], percentages in [0,100]).
 */
import { z } from 'zod';
import {
  NBA_TEAMS,
  NBA_CONFERENCES,
  NBA_DIVISIONS,
  NBA_POSITIONS,
  EXPECTED_SHOT_ZONES,
} from '../helpers/datasets';

const teamEnum = z.enum(NBA_TEAMS);
const conferenceEnum = z.enum(NBA_CONFERENCES);
const divisionEnum = z.enum(NBA_DIVISIONS);
const positionEnum = z.enum(NBA_POSITIONS);
const shotZoneEnum = z.enum(EXPECTED_SHOT_ZONES);
/** Draft/transaction positions use the granular form, e.g. "SF", "PG/SG", "PF/C". */
const granularPosition = z
  .string()
  .regex(/^(PG|SG|SF|PF|C|G|F)(\/(PG|SG|SF|PF|C|G|F))?$/, 'unrecognised position');
const prob = z.number().finite().min(0).max(1);
const pct = z.number().finite().min(0).max(100);
const num = z.number().finite();
const wins = num.min(0).max(82);
// Provenance tags the R exporters stamp onto metric blocks. Anything not in this
// set means a builder started emitting a label the site does not know how to show.
const provenanceTag = z.enum([
  'observed_pbp',
  'synthetic_coach_band',
  'model_residual_ensemble_minus_bottom_up',
]);
// A season span an artifact's inputs were observed in: one 'YYYY-YY' label, or
// several joined by ' + ' where a builder pools seasons. This is deliberately NOT
// the season being projected -- see SeasonSourceBadge.
const seasonSpan = z
  .string()
  .regex(/^\d{4}-\d{4}( \+ \d{4}-\d{4})*$/, 'expected e.g. "2025-2026" or "2025-2026 + 2026-2027"');

// ----------------------------------------------------------------------------
// 1. projections_season_teams.json -> TeamProjection[] (lib/types.ts)
// ----------------------------------------------------------------------------
const variantBlock = (prefix: string) => ({
  [`${prefix}_mean_wins`]: wins,
  [`${prefix}_median_wins`]: wins,
  [`${prefix}_sd_wins`]: num.min(0).max(41),
  [`${prefix}_p10`]: wins,
  [`${prefix}_p25`]: wins,
  [`${prefix}_p50`]: wins,
  [`${prefix}_p75`]: wins,
  [`${prefix}_p90`]: wins,
  [`${prefix}_playoff_prob`]: prob,
  [`${prefix}_title_prob`]: prob,
});

export const TeamProjectionSchema = z
  .object({
    rank: z.number().int().min(1).max(30),
    team_id: z.number().int().positive(),
    team: teamEnum,
    team_name: z.string().min(2),
    conference: conferenceEnum,
    division: divisionEnum,
    proj_wins: wins,
    proj_losses: wins,
    win_pct: prob,
    ensemble_mean_wins: wins,
    ensemble_median_wins: wins,
    ensemble_sd_wins: num.min(0).max(41),
    ensemble_p10: wins,
    ensemble_p25: wins,
    ensemble_p50: wins,
    ensemble_p75: wins,
    ensemble_p90: wins,
    ensemble_playoff_prob: prob,
    ensemble_title_prob: prob,
    ...variantBlock('variant_bottom_up'),
    ...variantBlock('variant_rapm'),
    ...variantBlock('variant_shot_fatigue'),
    ...variantBlock('variant_embeddings'),
  })
  .strict();

// ----------------------------------------------------------------------------
// 2. projections_season_players.json -> PlayerProjection[] (lib/types.ts)
// ----------------------------------------------------------------------------
const nonNeg = num.min(0);
const games = num.min(0).max(82);
export const PlayerProjectionSchema = z
  .object({
    player_id: z.string().regex(/^\d+$/),
    player_name: z.string().min(2),
    team: teamEnum,
    position: positionEnum,
    proj_games: num.min(1).max(82),
    proj_mpg: num.min(0).max(48),
    proj_min_total: nonNeg,
    proj_pts: num.min(0).max(50),
    proj_reb: num.min(0).max(25),
    proj_ast: num.min(0).max(20),
    proj_pts_total: nonNeg,
    proj_reb_total: nonNeg,
    proj_ast_total: nonNeg,
    pts_p10: nonNeg, pts_p25: nonNeg, pts_p50: nonNeg, pts_p75: nonNeg, pts_p90: nonNeg,
    reb_p10: nonNeg, reb_p25: nonNeg, reb_p50: nonNeg, reb_p75: nonNeg, reb_p90: nonNeg,
    ast_p10: nonNeg, ast_p25: nonNeg, ast_p50: nonNeg, ast_p75: nonNeg, ast_p90: nonNeg,
    games_p10: games, games_p25: games, games_p50: games, games_p75: games, games_p90: games,
    games_sd: nonNeg,
    pts_sd: nonNeg,
    reb_sd: nonNeg,
    ast_sd: nonNeg,
    pts_zscore: num,
    reb_zscore: num,
    ast_zscore: num,
    pra_zscore: num,
    is_outlier: z.boolean(),
  })
  .strict();

// ----------------------------------------------------------------------------
// 3. projections_models_metadata.json -> ModelMetadata (lib/types.ts)
// ----------------------------------------------------------------------------
const VariantMetaSchema = z
  .object({
    name: z.string().min(2),
    weight: prob,
    description: z.string().min(5),
    source_season_label: seasonSpan.optional(),
  })
  .strict();

export const ModelMetadataSchema = z
  .object({
    schema_version: z.string().min(1),
    pipeline_stage: z.string().min(1),
    generated_at: z.string().datetime(),
    season: z.number().int().min(2020).max(2035),
    season_label: seasonSpan,
    n_simulations: z.number().int().positive(),
    margin_sigma: num.positive(),
    home_court_advantage: num,
    total_schedule_games: z.literal(1230),
    teams_count: z.literal(30),
    players_count: z.number().int().positive(),
    models: z
      .object({
        ensemble: z
          .object({
            name: z.string().min(2),
            weights: z.record(z.string(), prob),
            description: z.string().min(5),
          })
          .strict(),
        variant_bottom_up: VariantMetaSchema,
        variant_rapm: VariantMetaSchema,
        variant_shot_fatigue: VariantMetaSchema,
        variant_embeddings: VariantMetaSchema,
      })
      .strict(),
  })
  .strict();

// ----------------------------------------------------------------------------
// 4. projections_diagnostics.json -> ModelDiagnostics (lib/types.ts)
// ----------------------------------------------------------------------------
export const ModelDiagnosticsSchema = z
  .object({
    totalResolvedGames: z.number().int().positive(),
    overallAccuracy: prob,
    brierScore: num.min(0).max(1),
    logLoss: num.positive(),
    homeWinRate: prob,
    calibration: z
      .array(
        z
          .object({
            bin: z.string().min(1),
            midpoint: prob,
            count: z.number().int().min(0),
            meanPredictedProb: prob,
            empiricalWinRate: prob,
          })
          .strict(),
      )
      .min(5),
    accuracyDrift: z
      .array(
        z
          .object({
            season: z.string().regex(/^\d{4}$/),
            games: z.number().int().positive(),
            accuracy: prob,
            brierScore: num.min(0).max(1),
          })
          .strict(),
      )
      .min(1),
    residualDistribution: z
      .array(
        z
          .object({ bucket: z.string().min(1), count: z.number().int().min(0), label: z.string().min(1) })
          .strict(),
      )
      .min(3),
  })
  .strict();

// ----------------------------------------------------------------------------
// 5. cba_cap_sheet.json -> CbaLeagueOverview (lib/cbaTypes.ts)
// ----------------------------------------------------------------------------
export const PlayerContractSchema = z
  .object({
    playerId: z.union([z.string().min(1), z.number().int()]),
    playerName: z.string().min(2),
    position: positionEnum,
    salary2026: nonNeg,
    salary2027: nonNeg,
    salary2028: nonNeg,
    contractType: z.enum(['Guaranteed', 'Player Option', 'Team Option', 'Qualifying Offer', 'Two-Way']),
    notes: z.string().optional(),
  })
  .strict();

export const FranchiseCbaProfileSchema = z
  .object({
    teamAbbr: teamEnum,
    teamName: z.string().min(2),
    conference: conferenceEnum,
    totalPayroll2026: num.positive(),
    totalPayroll2027: nonNeg,
    totalPayroll2028: nonNeg,
    salaryCap: num.positive(),
    luxuryTaxThreshold: num.positive(),
    firstApron: num.positive(),
    secondApron: num.positive(),
    capSpace2026: nonNeg,
    taxSpace2026: num,
    firstApronSpace2026: num,
    secondApronSpace2026: num,
    cbaTier: z.enum([
      'Under Cap Room',
      'Over Cap (Non-Taxpayer)',
      'Taxpayer (Below Apron 1)',
      'First Apron Team',
      'Second Apron Restricted',
    ]),
    isRepeaterTax: z.boolean(),
    luxuryTaxBill: nonNeg,
    totalFinancialCommitment: num.positive(),
    projectedCapSpace2027: nonNeg,
    projectedCapSpace2028: nonNeg,
    handcuffs: z
      .object({
        frozenPick7Years: z.boolean(),
        noSalaryAggregation: z.boolean(),
        noCashInTrades: z.boolean(),
        noTpmle: z.boolean(),
        tradeSalaryMatchingPct: num.min(100).max(250),
        signAndTradeHardCapped: z.boolean(),
      })
      .strict(),
    contracts: z.array(PlayerContractSchema).min(1),
  })
  .strict();

export const CbaLeagueOverviewSchema = z
  .object({
    season: z.string().regex(/^\d{4}-\d{4}$/),
    cbaThresholdSources: z.string().min(2).optional(),
    salaryCap: num.positive(),
    luxuryTaxThreshold: num.positive(),
    firstApron: num.positive(),
    secondApron: num.positive(),
    averagePayroll: num.positive(),
    totalLeagueTaxRevenue: nonNeg,
    secondApronTeamCount: z.number().int().min(0).max(30),
    firstApronTeamCount: z.number().int().min(0).max(30),
    taxTeamCount: z.number().int().min(0).max(30),
    capRoomTeamCount: z.number().int().min(0).max(30),
    teams: z.array(FranchiseCbaProfileSchema).length(30),
  })
  .strict();

// ----------------------------------------------------------------------------
// 6. clutch_leverage_metrics.json -> ClutchProfile[] (lib/clutchTypes.ts)
// ----------------------------------------------------------------------------
const ShotZoneStatsSchema = z
  .object({ fga: z.number().int().min(0), fgm: z.number().int().min(0), pct })
  .strict();

export const ClutchProfileSchema = z
  .object({
    playerId: z.string().regex(/^\d+$/),
    playerName: z.string().min(2),
    team: teamEnum,
    position: positionEnum,
    clutchArchetype: z.string().min(2),
    clutchMpg: num.min(0).max(5),
    clutchUsgPct: pct,
    clutchTsPct: pct,
    baseTsPct: pct,
    tsDelta: num,
    usciScore: num.min(0).max(150),
    unassistedFgmPct: pct,
    clutchPpp: nonNeg,
    tovFragility: num,
    cDwpa: num,
    shotBreakdown: z
      .object({
        totalClutchFga: z.number().int().min(0),
        rim: ShotZoneStatsSchema,
        mid: ShotZoneStatsSchema,
        three: ShotZoneStatsSchema,
      })
      .strict(),
  })
  .strict();

// ----------------------------------------------------------------------------
// 7. coaching_metrics.json -> CoachingStaffMetric[] (lib/coachingTypes.ts)
// ----------------------------------------------------------------------------
export const CoachingStaffMetricSchema = z
  .object({
    teamAbbr: teamEnum,
    teamName: z.string().min(2),
    headCoach: z
      .object({
        name: z.string().min(2),
        tenureYears: z.number().int().min(0),
        careerGames: z.number().int().min(0),
        careerWinPct: prob,
        coachingTree: z.string().min(2),
        tacticalArchetype: z.string().min(2),
      })
      .strict(),
    assistants: z
      .object({
        associateHC: z.string().min(2),
        offensiveCoord: z.string().min(2),
        defensiveCoord: z.string().min(2),
        playerDevLead: z.string().min(2),
      })
      .strict(),
    metrics: z
      .object({
        coachImpactRating: pct,
        talentExpectedWins: wins,
        actualProjectedWins: wins,
        coachingWinsAdded: num,
        atoOffensivePpp: num.positive(),
        atoDefensivePppAllowed: num.positive(),
        challengeSuccessRate: prob,
        challengeWpa: num,
        shotQualityLiftEfg: num,
        rotationStaggerScore: pct,
        playerDevelopmentScore: pct,
      })
      .strict(),
    radarPercentiles: z
      .object({
        atoMastery: pct,
        tacticalInnovation: pct,
        rotationEfficiency: pct,
        inGameWpa: pct,
        playerDevelopment: pct,
      })
      .strict(),
    // Per-field provenance emitted by build_coaching_dataset.R. `synthetic_coach_band`
    // marks a value drawn from a hand-assigned per-coach range rather than measured.
    provenance: z
      .object({
        atoMetrics: provenanceTag,
        challengeMetrics: provenanceTag,
        coachingWinsAdded: provenanceTag,
        shotQualityLift: provenanceTag,
        rotationAndDevelopment: provenanceTag,
        // Season span the observed_pbp fields were measured over, e.g. '2025-2026'.
        // Omitted entirely when nothing on the card is observed, so optional.
        observedSeasons: seasonSpan.nullable().optional(),
        generatedAt: z.string().min(10),
      })
      .strict(),
  })
  .strict();

// ----------------------------------------------------------------------------
// 8. defensive_metrics.json -> DefensiveProfile[] (lib/defenseTypes.ts)
// ----------------------------------------------------------------------------
export const DefensiveProfileSchema = z
  .object({
    playerId: z.string().regex(/^\d+$/),
    playerName: z.string().min(2),
    team: teamEnum,
    position: positionEnum,
    projMpg: num.min(0).max(48),
    defensiveRole: z.string().min(2),
    versatilityScore: pct,
    rimDfgDelta: num,
    rimDeterrenceIndex: nonNeg,
    poaNavigation: pct,
    dRapm: num,
    matchupDist: z
      .object({ pgPct: pct, sgPct: pct, sfPct: pct, pfPct: pct, cPct: pct })
      .strict(),
  })
  .strict();

// ----------------------------------------------------------------------------
// 9. player_dna_profiles.json -> PlayerDnaProfile[] (lib/playerDnaTypes.ts)
// ----------------------------------------------------------------------------
export const PlayerDnaProfileSchema = z
  .object({
    playerId: z.string().regex(/^\d+$/),
    playerName: z.string().min(2),
    team: teamEnum,
    position: positionEnum,
    archetype: z.string().min(2),
    projPts: nonNeg,
    projReb: nonNeg,
    projAst: nonNeg,
    projMpg: num.min(0).max(48),
    overallRating: pct,
    manifoldX: num,
    manifoldY: num,
    skillVector: z
      .object({
        rim_fg: pct, dunks: pct, paint_touches: pct, cns_3p: pct, pullup_3p: pct, ft_pct: pct,
        ast_pct: pct, pot_ast: pct, tov_control: pct, drive_ast: pct, switchability: pct,
        rim_protection: pct, perimeter_havoc: pct, d_rapm: pct, oreb: pct, dreb: pct,
      })
      .strict(),
    categoryScores: z
      .object({ finishing: pct, shooting: pct, playmaking: pct, defense: pct, rebounding: pct })
      .strict(),
    historicalTwins: z
      .array(
        z
          .object({
            compName: z.string().min(2),
            era: z.string().min(4),
            archetype: z.string().min(2),
            position: z.string().min(1),
            similarityPct: pct,
            keySharedTrait: z.string().min(2),
          })
          .strict(),
      )
      .min(1),
  })
  .strict();

// ----------------------------------------------------------------------------
// 10. offseason_draft.json -> RookieDraftProfile[] (lib/offseasonTypes.ts)
// ----------------------------------------------------------------------------
export const RookieDraftProfileSchema = z
  .object({
    round: z.union([z.literal(1), z.literal(2)]),
    pick: z.number().int().min(1).max(60),
    player_name: z.string().min(2),
    original_team: teamEnum.optional(),
    team: teamEnum,
    position: granularPosition,
    school_or_club: z.string().min(2),
    height: z.string().regex(/^\d'\d{1,2}"?$/),
    archetype: z.string().min(2),
    projected_bpm_prior: num,
    projected_mpg: num.min(0).max(48),
    upside_tier: z.enum(['Franchise Pillar', 'Core Starter', 'Specialist', 'Developmental']),
    trade_note: z.string().nullable().optional(),
    strengths: z.array(z.string().min(2)).min(1),
    swing_skills: z.array(z.string().min(2)).min(1),
    comp: z.string().min(2),
  })
  .strict();

// ----------------------------------------------------------------------------
// 11. offseason_teams.json -> TeamOffseasonProfile[] (lib/offseasonTypes.ts)
// ----------------------------------------------------------------------------
const TeamTxSummarySchema = z
  .object({
    name: z.string().min(2),
    type: z.enum(['trade', 'free_agency', 'draft']),
    bpm: num,
    pos: positionEnum,
  })
  .strict();

export const TeamOffseasonProfileSchema = z
  .object({
    team: teamEnum,
    team_name: z.string().min(2),
    conference: conferenceEnum,
    division: divisionEnum,
    baseline_wins: wins,
    projected_wins_with_moves: wins,
    net_wins_change: num,
    net_bpm_added: num,
    roster_continuity_pct: prob,
    grade: z.enum(['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D+', 'D']),
    strategic_posture: z.string().min(2),
    additions: z.array(TeamTxSummarySchema),
    departures: z.array(TeamTxSummarySchema),
    draft_picks: z.array(
      z
        .object({
          name: z.string().min(2),
          pick: z.number().int().min(1).max(60),
          school: z.string().min(2),
          archetype: z.string().min(2),
        })
        .strict(),
    ),
    offseason_verdict: z.string().min(5),
  })
  .strict();

// ----------------------------------------------------------------------------
// 12. offseason_transactions.json -> OffseasonTransaction[] (lib/offseasonTypes.ts)
// ----------------------------------------------------------------------------
export const OffseasonTransactionSchema = z
  .object({
    id: z.string().min(1),
    type: z.enum(['trade', 'free_agency', 'draft']),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    player_name: z.string().min(2),
    player_id: z.string().regex(/^\d+$/).optional(),
    position: granularPosition,
    from_team: teamEnum.optional(),
    to_team: teamEnum,
    contract_terms: z.string().min(2).optional(),
    draft_pick: z
      .object({
        round: z.union([z.literal(1), z.literal(2)]),
        pick: z.number().int().min(1).max(60),
        school_or_club: z.string().min(2),
      })
      .strict()
      .optional(),
    trade_details: z
      .object({
        counterparts_received: z.array(z.string()).optional(),
        draft_assets: z.array(z.string()).optional(),
      })
      .strict()
      .optional(),
    player_bpm: num,
    player_pts: nonNeg,
    player_reb: nonNeg,
    player_ast: nonNeg,
    projected_minutes: num.min(0).max(48),
    delta_net_rating: num,
    delta_projected_wins: num,
    impact_tier: z.enum(['superstar', 'starter', 'rotation', 'depth', 'prospect']),
    fit_score: pct,
    age: z.number().int().min(18).max(45),
    headline: z.string().min(5),
    analysis: z
      .object({
        summary: z.string().min(5),
        offensive_impact: z.string().min(5),
        defensive_impact: z.string().min(5),
        risk_factor: z.string().min(5),
      })
      .strict(),
  })
  .strict();

// ----------------------------------------------------------------------------
// 13. playoff_series_matchups.json -> PlayoffMatchupsCatalog (lib/playoffTypes.ts)
// ----------------------------------------------------------------------------
const PlayoffPlayerSchema = z
  .object({
    playerId: z.union([z.string().min(1), z.number().int()]),
    playerName: z.string().min(2),
    position: positionEnum,
    regularMpg: num.min(0).max(48),
    playoffMpg: num.min(0).max(48),
    pts: nonNeg,
    reb: nonNeg,
    ast: nonNeg,
    praZscore: num,
    role: z.enum(['Starter', 'Sixth Man', 'Rotation Bench']),
  })
  .strict();

export const TeamPlayoffProfileSchema = z
  .object({
    teamAbbr: teamEnum,
    teamName: z.string().min(2),
    conference: conferenceEnum,
    regularWins: wins,
    regularNetRtg: num,
    playoffNetRtg: num,
    top3TalentBump: num,
    tacticalRatings: z
      .object({
        perimeterCreation: pct,
        dropVulnerability: pct,
        interiorDominance: pct,
        switchability: pct,
        clutchExecution: pct,
      })
      .strict(),
    rotation: z.array(PlayoffPlayerSchema).length(8),
  })
  .strict();

export const PlayoffSeriesMatchupResultSchema = z
  .object({
    teamA: teamEnum,
    teamB: teamEnum,
    hcaTeam: teamEnum,
    ratingDiffRaw: num,
    tacticalMismatchAdjustment: num,
    netRatingMargin: num,
    winProbA: prob,
    winProbB: prob,
    fairMlA: z.number().int(),
    fairMlB: z.number().int(),
    avgGames: num.min(4).max(7),
    spreadMinus1_5Prob: prob,
    sweepProb: pct,
    gameDistributions: z
      .array(
        z
          .object({ games: z.number().int().min(4).max(7), winner: teamEnum, probPct: pct })
          .strict(),
      )
      .length(8),
    tacticalEdges: z.array(
      z
        .object({
          title: z.string().min(2),
          advantageTeam: teamEnum,
          description: z.string().min(5),
          deltaMargin: num,
        })
        .strict(),
    ),
  })
  .strict();

export const PlayoffMatchupsCatalogSchema = z
  .object({
    teams: z.record(teamEnum, TeamPlayoffProfileSchema),
    sampleMatchups: z.array(PlayoffSeriesMatchupResultSchema).min(1),
  })
  .strict();

// ----------------------------------------------------------------------------
// 14/15/16. shots_index.json, shots_metadata.json, shots/<id>.json (lib/shotTypes.ts)
// ----------------------------------------------------------------------------
export const PlayerCatalogEntrySchema = z
  .object({
    player_id: z.string().regex(/^\d+$/),
    player_name: z.string().min(2),
    team: teamEnum,
    total_shots: z.number().int().positive(),
  })
  .strict();

export const ShotsMetadataSchema = z
  .object({
    updated_at: z.string().datetime(),
    total_shots_sampled: z.number().int().positive(),
    source_season_label: seasonSpan,
    league_averages: z
      .array(
        z
          .object({
            zone: shotZoneEnum,
            total_fga: z.number().int().positive(),
            total_fgm: z.number().int().min(0),
            lg_fg_pct: prob,
          })
          .strict(),
      )
      .length(14),
    zones: z.array(shotZoneEnum).length(14),
  })
  .strict();

export const ShotRecordSchema = z
  .object({
    x: num.min(-25).max(25),
    y: num.min(0).max(47),
    dist: num.min(0).max(60),
    val: z.union([z.literal(2), z.literal(3)]),
    made: z.boolean(),
    zone: shotZoneEnum,
    type: z.string().min(1),
    period: z.number().int().min(1).max(10),
    clock: z.string().regex(/^\d{1,2}:\d{1,2}(\.\d+)?$/),
  })
  .strict();

export const PlayerShotDataSchema = z
  .object({
    player_id: z.string().regex(/^\d+$/),
    player_name: z.string().min(2),
    team: teamEnum,
    total_shots: z.number().int().positive(),
    shots: z.array(ShotRecordSchema).min(1),
  })
  .strict();
