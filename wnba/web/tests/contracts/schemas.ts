import { z } from 'zod';
import {
  WNBA_TEAMS,
  WNBA_CONFERENCES,
  WNBA_DIVISIONS,
  WNBA_POSITIONS,
  EXPECTED_SHOT_ZONES,
} from '../helpers/datasets';

const teamEnum = z.enum(WNBA_TEAMS);
const conferenceEnum = z.enum(WNBA_CONFERENCES);
const divisionEnum = z.enum(WNBA_DIVISIONS);
const positionEnum = z.enum([...WNBA_POSITIONS, 'G/F'] as const);
const shotZoneEnum = z.enum(EXPECTED_SHOT_ZONES);
const prob = z.number().finite().min(0).max(1);
const pct = z.number().finite().min(0).max(100);
const finiteNumber = z.number().finite();

// 1. projections_season_teams.json -> TeamProjection[] (lib/types.ts)
export const TeamProjectionSchema = z
  .object({
    rank: z.number().int().min(1).max(15),
    team_id: z.number().int().positive(),
    team: teamEnum,
    team_name: z.string().min(2),
    conference: conferenceEnum,
    division: divisionEnum,
    proj_wins: finiteNumber.min(0).max(44),
    proj_losses: finiteNumber.min(0).max(44),
    win_pct: prob,
    ensemble_mean_wins: finiteNumber.min(0).max(44),
    ensemble_median_wins: finiteNumber.min(0).max(44),
    ensemble_sd_wins: finiteNumber.min(0).max(22),
    ensemble_p10: finiteNumber.min(0).max(44),
    ensemble_p25: finiteNumber.min(0).max(44),
    ensemble_p50: finiteNumber.min(0).max(44),
    ensemble_p75: finiteNumber.min(0).max(44),
    ensemble_p90: finiteNumber.min(0).max(44),
    ensemble_playoff_prob: prob,
    ensemble_title_prob: prob,
    variant_bottom_up_mean_wins: finiteNumber.min(0).max(44),
    variant_bottom_up_median_wins: finiteNumber.min(0).max(44),
    variant_bottom_up_sd_wins: finiteNumber.min(0).max(22),
    variant_bottom_up_p10: finiteNumber.min(0).max(44),
    variant_bottom_up_p25: finiteNumber.min(0).max(44),
    variant_bottom_up_p50: finiteNumber.min(0).max(44),
    variant_bottom_up_p75: finiteNumber.min(0).max(44),
    variant_bottom_up_p90: finiteNumber.min(0).max(44),
    variant_bottom_up_playoff_prob: prob,
    variant_bottom_up_title_prob: prob,
    variant_rapm_mean_wins: finiteNumber.min(0).max(44),
    variant_rapm_median_wins: finiteNumber.min(0).max(44),
    variant_rapm_sd_wins: finiteNumber.min(0).max(22),
    variant_rapm_p10: finiteNumber.min(0).max(44),
    variant_rapm_p25: finiteNumber.min(0).max(44),
    variant_rapm_p50: finiteNumber.min(0).max(44),
    variant_rapm_p75: finiteNumber.min(0).max(44),
    variant_rapm_p90: finiteNumber.min(0).max(44),
    variant_rapm_playoff_prob: prob,
    variant_rapm_title_prob: prob,
    variant_shot_fatigue_mean_wins: finiteNumber.min(0).max(44),
    variant_shot_fatigue_median_wins: finiteNumber.min(0).max(44),
    variant_shot_fatigue_sd_wins: finiteNumber.min(0).max(22),
    variant_shot_fatigue_p10: finiteNumber.min(0).max(44),
    variant_shot_fatigue_p25: finiteNumber.min(0).max(44),
    variant_shot_fatigue_p50: finiteNumber.min(0).max(44),
    variant_shot_fatigue_p75: finiteNumber.min(0).max(44),
    variant_shot_fatigue_p90: finiteNumber.min(0).max(44),
    variant_shot_fatigue_playoff_prob: prob,
    variant_shot_fatigue_title_prob: prob,
    variant_embeddings_mean_wins: finiteNumber.min(0).max(44),
    variant_embeddings_median_wins: finiteNumber.min(0).max(44),
    variant_embeddings_sd_wins: finiteNumber.min(0).max(22),
    variant_embeddings_p10: finiteNumber.min(0).max(44),
    variant_embeddings_p25: finiteNumber.min(0).max(44),
    variant_embeddings_p50: finiteNumber.min(0).max(44),
    variant_embeddings_p75: finiteNumber.min(0).max(44),
    variant_embeddings_p90: finiteNumber.min(0).max(44),
    variant_embeddings_playoff_prob: prob,
    variant_embeddings_title_prob: prob,
    _row: z.string().optional(),
  })
  .strict();

// 2. projections_season_players.json -> PlayerProjection[] (lib/types.ts)
export const PlayerProjectionSchema = z
  .object({
    player_id: z.string().min(1),
    player_name: z.string().min(2),
    team: teamEnum,
    position: positionEnum,
    proj_games: finiteNumber.min(1).max(44),
    proj_mpg: finiteNumber.min(0).max(40),
    proj_min_total: finiteNumber.min(0),
    proj_pts: finiteNumber.min(0).max(40),
    proj_reb: finiteNumber.min(0).max(20),
    proj_ast: finiteNumber.min(0).max(15),
    proj_pts_total: finiteNumber.min(0),
    proj_reb_total: finiteNumber.min(0),
    proj_ast_total: finiteNumber.min(0),
    pts_p10: finiteNumber.min(0),
    pts_p25: finiteNumber.min(0),
    pts_p50: finiteNumber.min(0),
    pts_p75: finiteNumber.min(0),
    pts_p90: finiteNumber.min(0),
    reb_p10: finiteNumber.min(0),
    reb_p25: finiteNumber.min(0),
    reb_p50: finiteNumber.min(0),
    reb_p75: finiteNumber.min(0),
    reb_p90: finiteNumber.min(0),
    ast_p10: finiteNumber.min(0),
    ast_p25: finiteNumber.min(0),
    ast_p50: finiteNumber.min(0),
    ast_p75: finiteNumber.min(0),
    ast_p90: finiteNumber.min(0),
    games_p10: finiteNumber.min(0).max(44),
    games_p25: finiteNumber.min(0).max(44),
    games_p50: finiteNumber.min(0).max(44),
    games_p75: finiteNumber.min(0).max(44),
    games_p90: finiteNumber.min(0).max(44),
    games_sd: finiteNumber.min(0),
    pts_sd: finiteNumber.min(0),
    reb_sd: finiteNumber.min(0),
    ast_sd: finiteNumber.min(0),
    pts_zscore: finiteNumber,
    reb_zscore: finiteNumber,
    ast_zscore: finiteNumber,
    pra_zscore: finiteNumber,
    is_outlier: z.boolean(),
  })
  .strict();

// 3. projections_models_metadata.json -> ModelMetadata (lib/types.ts)
const VariantMetadataEntrySchema = z
  .object({
    name: z.string().min(2),
    weight: prob,
    description: z.string().min(5),
  })
  .strict();

export const ModelMetadataSchema = z
  .object({
    schema_version: z.string().min(1),
    pipeline_stage: z.string().min(1),
    generated_at: z.string().datetime(),
    season: z.number().int().min(2020).max(2035),
    n_simulations: z.number().int().positive(),
    margin_sigma: finiteNumber.positive(),
    home_court_advantage: finiteNumber,
    total_schedule_games: z.number().int().positive(),
    teams_count: z.literal(15),
    players_count: z.number().int().min(150),
    models: z
      .object({
        ensemble: z
          .object({
            name: z.string().min(2),
            weights: z.record(z.string(), prob),
            description: z.string().min(5),
          })
          .strict(),
        variant_bottom_up: VariantMetadataEntrySchema,
        variant_rapm: VariantMetadataEntrySchema,
        variant_shot_fatigue: VariantMetadataEntrySchema,
        variant_embeddings: VariantMetadataEntrySchema,
      })
      .strict(),
  })
  .strict();

// 4. projections_diagnostics.json -> ModelDiagnostics (lib/types.ts)
export const CalibrationBinSchema = z
  .object({
    bin: z.string().min(1),
    midpoint: prob,
    count: z.number().int().min(0),
    meanPredictedProb: prob,
    empiricalWinRate: prob,
  })
  .strict();

export const AccuracyDriftEntrySchema = z
  .object({
    season: z.union([z.string().min(4), z.number().int().min(2015).max(2035)]),
    games: z.number().int().positive(),
    accuracy: prob,
    brierScore: finiteNumber.min(0).max(1),
  })
  .strict();

export const ResidualBucketSchema = z
  .object({
    bucket: z.string().min(1),
    count: z.number().int().min(0),
    label: z.string().min(1),
  })
  .strict();

// ----------------------------------------------------------------------------
// `generated_at` on the schemas below
//
// Written by the R exporters for tools/publish_web.R's assertion F (payload
// provenance), which reads a UTC ISO-8601 stamp out of the first 4096 bytes of
// each payload. Every schema that gained the stamp is .strict(), so the field
// has to be declared here or the contract suite rejects the payload -- and
// assertion G runs that suite as a fatal pre-publish check, so an undeclared
// stamp would block the publish it is meant to make verifiable.
//
// Note `generated_at` is NOT the existing camelCase `generatedAt` on the
// bracket/finals/backtest schemas: that one is the upstream cache artifact's own
// local-time timestamp, passed through for display, in a format F cannot parse.
// ----------------------------------------------------------------------------
export const ModelDiagnosticsSchema = z
  .object({
    generated_at: z.string().datetime(),
    totalResolvedGames: z.number().int().positive(),
    overallAccuracy: prob,
    brierScore: finiteNumber.min(0).max(1),
    logLoss: finiteNumber.positive(),
    homeWinRate: prob,
    calibration: z.array(CalibrationBinSchema).min(5),
    accuracyDrift: z.array(AccuracyDriftEntrySchema).min(1),
    residualDistribution: z.array(ResidualBucketSchema).min(3),
  })
  .strict();

// 5. cba_cap_sheet.json -> WnbaCbaLeagueOverview (lib/cbaTypes.ts)
export const WnbaPlayerContractSchema = z
  .object({
    playerId: z.string().min(1),
    playerName: z.string().min(2),
    position: positionEnum,
    salary2026: finiteNumber.min(0),
    salary2027: finiteNumber.min(0),
    salary2028: finiteNumber.min(0),
    contractType: z.string().min(2),
    notes: z.string(),
  })
  .strict();

export const WnbaFranchiseCbaProfileSchema = z
  .object({
    teamAbbr: teamEnum,
    teamName: z.string().min(3),
    conference: conferenceEnum,
    totalPayroll2026: finiteNumber.positive(),
    totalPayroll2027: finiteNumber.min(0),
    totalPayroll2028: finiteNumber.min(0),
    hardSalaryCap: finiteNumber.positive(),
    capFloor: finiteNumber.positive(),
    capSpace2026: finiteNumber,
    rosterCount: z.union([z.literal(11), z.literal(12)]),
    twelfthSpotAvailable: z.boolean(),
    cbaTier: z.enum([
      'Hard Cap Squeeze (11 Roster)',
      'Cap Compliant (12 Roster)',
      'Flexible Cap Room',
      'Maximum Cap Space',
    ]),
    corePlayer: z.string().min(1),
    projectedCapSpace2027: finiteNumber,
    projectedCapSpace2028: finiteNumber,
    hardCapCrunchIndex: finiteNumber.min(0).max(110),
    contracts: z.array(WnbaPlayerContractSchema).min(10).max(20),
  })
  .strict();

export const WnbaCbaLeagueOverviewSchema = z
  .object({
    generated_at: z.string().datetime(), // see note above ModelDiagnosticsSchema
    season: z.string().min(4),
    hardSalaryCap: finiteNumber.positive(),
    capFloor: finiteNumber.positive(),
    supermaxSalary: finiteNumber.positive(),
    vetMaxSalary: finiteNumber.positive(),
    vetMinSalary: finiteNumber.positive(),
    rookieMinSalary: finiteNumber.positive(),
    averagePayroll: finiteNumber.positive(),
    hardCapSqueezeTeamCount: z.number().int().min(0).max(15),
    twelvePlayerTeamCount: z.number().int().min(0).max(15),
    maxCapSpaceTeamCount: z.number().int().min(0).max(15),
    teams: z.array(WnbaFranchiseCbaProfileSchema).length(15),
  })
  .strict();

// 6. clutch_leverage_metrics.json -> ClutchProfile[] (lib/clutchTypes.ts)
const ShotZoneStatsSchema = z
  .object({
    fga: z.number().int().min(0),
    fgm: z.number().int().min(0),
    pct: pct,
  })
  .strict();

export const ClutchProfileSchema = z
  .object({
    season: z.number().int().optional(),
    playerId: z.string().min(1),
    playerName: z.string().min(2),
    team: teamEnum,
    position: positionEnum,
    clutchArchetype: z.string().min(2),
    clutchMpg: finiteNumber.min(0).max(10),
    clutchUsgPct: pct,
    clutchTsPct: pct,
    baseTsPct: pct,
    tsDelta: finiteNumber,
    usciScore: finiteNumber.min(0),
    unassistedFgmPct: pct,
    clutchPpp: finiteNumber.min(0),
    tovFragility: finiteNumber,
    cDwpa: finiteNumber,
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

// 7. coaching_metrics.json -> CoachingStaffMetric[] (lib/coachingTypes.ts)
export const CoachingStaffMetricSchema = z
  .object({
    season: z.number().int().optional(),
    teamAbbr: teamEnum,
    teamName: z.string().min(3),
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
        talentExpectedWins: finiteNumber.min(0).max(44),
        actualProjectedWins: finiteNumber.min(0).max(44),
        coachingWinsAdded: finiteNumber,
        atoOffensivePpp: finiteNumber.positive(),
        atoDefensivePppAllowed: finiteNumber.positive(),
        challengeSuccessRate: pct,
        challengeWpa: finiteNumber,
        shotQualityLiftEfg: finiteNumber,
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
  })
  .strict();

// 8. defensive_metrics.json -> DefensiveProfile[] (lib/defenseTypes.ts)
export const DefensiveProfileSchema = z
  .object({
    season: z.number().int().optional(),
    playerId: z.string().min(1),
    playerName: z.string().min(2),
    team: teamEnum,
    position: positionEnum,
    projMpg: finiteNumber.min(0).max(40),
    defensiveRole: z.string().min(2),
    versatilityScore: pct,
    rimDfgDelta: finiteNumber,
    rimDeterrenceIndex: finiteNumber.min(0),
    poaNavigation: pct,
    dRapm: finiteNumber,
    // Provenance of dRapm (issue #83): the real pooled-2019-2026 ridge fit, or
    // the clearly-labelled rebound/assist heuristic for players the RAPM join
    // cannot match.
    dRapmSource: z.enum([
      'rapm_ridge_pooled',
      'rapm_ridge_pooled_low_sample',
      'heuristic_fallback',
    ]),
    dRapmLowSample: z.boolean(),
    dRapmAmbiguous: z.boolean(),
    matchupDist: z
      .object({
        pgPct: pct,
        sgPct: pct,
        sfPct: pct,
        pfPct: pct,
        cPct: pct,
      })
      .strict(),
  })
  .strict();

// 9. player_dna_profiles.json -> PlayerDnaProfile[] (lib/playerDnaTypes.ts)
export const PlayerDnaProfileSchema = z
  .object({
    season: z.number().int().optional(),
    playerId: z.string().min(1),
    playerName: z.string().min(2),
    team: teamEnum,
    position: positionEnum,
    archetype: z.string().min(2),
    projPts: finiteNumber.min(0),
    projReb: finiteNumber.min(0),
    projAst: finiteNumber.min(0),
    projMpg: finiteNumber.min(0).max(40),
    overallRating: pct,
    manifoldX: finiteNumber,
    manifoldY: finiteNumber,
    skillVector: z
      .object({
        rim_fg: pct,
        paint_power: pct,
        paint_touches: pct,
        cns_3p: pct,
        pullup_3p: pct,
        ft_pct: pct,
        ast_pct: pct,
        pot_ast: pct,
        tov_control: pct,
        drive_ast: pct,
        switchability: pct,
        rim_protection: pct,
        perimeter_havoc: pct,
        d_rapm: pct,
        oreb: pct,
        dreb: pct,
      })
      .strict(),
    categoryScores: z
      .object({
        finishing: pct,
        shooting: pct,
        playmaking: pct,
        defense: pct,
        rebounding: pct,
      })
      .strict(),
    historicalTwins: z
      .array(
        z
          .object({
            compName: z.string().min(2),
            era: z.string().min(4),
            archetype: z.string().min(2),
            position: z.string().min(1),
            similarityPct: finiteNumber.min(0).max(100),
            keySharedTrait: z.string().min(2),
          })
          .strict()
      )
      .min(1),
  })
  .strict();

// 10. offseason_draft.json -> OffseasonDraftProspect[] (lib/offseasonTypes.ts)
export const OffseasonDraftProspectSchema = z
  .object({
    pick: z.number().int().min(1).max(30),
    player_name: z.string().min(2),
    team: teamEnum,
    position: positionEnum,
    school_or_club: z.string().min(2),
    height: z.string().min(3),
    archetype: z.string().min(2),
    projected_bpm_prior: finiteNumber,
    projected_mpg: finiteNumber.min(0).max(40),
    upside_tier: z.string().min(2),
    trade_note: z.union([z.string(), z.record(z.string(), z.unknown())]).optional(),
    strengths: z.array(z.string().min(2)).min(1),
    swing_skills: z.array(z.string().min(2)).min(1),
    comp: z.string().min(2),
  })
  .strict();

// 11. offseason_teams.json -> OffseasonTeamProfile[] (lib/offseasonTypes.ts)
export const OffseasonTeamProfileSchema = z
  .object({
    team: teamEnum,
    team_name: z.string().min(3),
    conference: conferenceEnum,
    division: divisionEnum,
    baseline_wins: finiteNumber.min(0).max(44),
    projected_wins_with_moves: finiteNumber.min(0).max(44),
    net_wins_change: finiteNumber,
    net_bpm_added: finiteNumber,
    roster_continuity_pct: pct,
    grade: z.string().min(1),
    strategic_posture: z.string().min(2),
    additions: z.array(
      z
        .object({
          name: z.string().min(2),
          type: z.string().min(2),
          bpm: finiteNumber,
          pos: positionEnum,
        })
        .strict()
    ),
    departures: z.array(
      z
        .object({
          name: z.string().min(2),
          type: z.string().min(2),
          bpm: finiteNumber,
          pos: positionEnum,
        })
        .strict()
    ),
    draft_picks: z.array(
      z
        .object({
          name: z.string().min(2),
          pick: z.number().int().min(1).max(30),
          school: z.string().min(2),
          archetype: z.string().min(2),
        })
        .strict()
    ),
    offseason_verdict: z.string().min(5),
  })
  .strict();

// 12. offseason_transactions.json -> OffseasonTransaction[] (lib/offseasonTypes.ts)
export const OffseasonTransactionSchema = z
  .object({
    id: z.string().min(1),
    type: z.enum(['trade', 'free_agency', 'extension', 'expansion_draft', 'draft']),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    player_name: z.string().min(2),
    player_id: z.string().optional(),
    position: positionEnum,
    from_team: teamEnum.nullable().optional(),
    to_team: teamEnum,
    contract_terms: z.string().min(2),
    trade_details: z
      .object({
        counterparts_received: z.array(z.string()).optional(),
        draft_assets: z.string().optional(),
      })
      .strict()
      .optional(),
    player_bpm: finiteNumber,
    player_pts: finiteNumber.min(0),
    player_reb: finiteNumber.min(0),
    player_ast: finiteNumber.min(0),
    projected_minutes: finiteNumber.min(0).max(40),
    delta_net_rating: finiteNumber,
    delta_projected_wins: finiteNumber,
    impact_tier: z.enum(['superstar', 'all_star', 'starter', 'rotation']),
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

// 13. playoff_series_matchups.json -> PlayoffMatchupsCatalog (lib/playoffTypes.ts)
const TacticalRatingsSchema = z
  .object({
    perimeterCreation: pct,
    dropVulnerability: pct,
    interiorDominance: pct,
    switchability: pct,
    clutchExecution: pct,
  })
  .strict();

const PlayoffPlayerSchema = z
  .object({
    playerId: z.union([z.string().min(1), z.number().int()]),
    playerName: z.string().min(2),
    position: positionEnum,
    regularMpg: finiteNumber.min(0).max(40),
    playoffMpg: finiteNumber.min(0).max(40),
    pts: finiteNumber.min(0),
    reb: finiteNumber.min(0),
    ast: finiteNumber.min(0),
    praZscore: finiteNumber,
    role: z.enum(['Starter', 'Sixth Man', 'Rotation Bench']),
  })
  .strict();

export const TeamPlayoffProfileSchema = z
  .object({
    teamAbbr: teamEnum,
    teamName: z.string().min(3),
    conference: conferenceEnum,
    regularWins: finiteNumber.min(0).max(44),
    regularNetRtg: finiteNumber,
    playoffNetRtg: finiteNumber,
    top3TalentBump: finiteNumber,
    tacticalRatings: TacticalRatingsSchema,
    rotation: z.array(PlayoffPlayerSchema).length(8),
  })
  .strict();

const GameOutcomeProbSchema = z
  .object({
    games: z.number().int().min(2).max(7),
    winner: teamEnum,
    probPct: pct,
  })
  .strict();

const TacticalEdgeSchema = z
  .object({
    title: z.string().min(2),
    advantageTeam: teamEnum,
    description: z.string().min(5),
    deltaMargin: finiteNumber,
  })
  .strict();

export const PlayoffSeriesMatchupResultSchema = z
  .object({
    teamA: teamEnum,
    teamB: teamEnum,
    hcaTeam: teamEnum,
    format: z.enum(['bo3', 'bo5', 'bo7']).optional(),
    ratingDiffRaw: finiteNumber,
    tacticalMismatchAdjustment: finiteNumber,
    netRatingMargin: finiteNumber,
    winProbA: prob,
    winProbB: prob,
    fairMlA: z.number().int(),
    fairMlB: z.number().int(),
    avgGames: finiteNumber.min(2).max(7),
    spreadMinus1_5Prob: prob,
    sweepProb: pct,
    gameDistributions: z.array(GameOutcomeProbSchema).min(4),
    tacticalEdges: z.array(TacticalEdgeSchema),
  })
  .strict();

const HistoricalSeriesSchema = z
  .object({
    teamA: z.string().min(2),
    teamNameA: z.string().min(2),
    teamB: z.string().min(2),
    teamNameB: z.string().min(2),
    winner: z.string().min(2),
    winnerName: z.string().min(2),
    round: z.string().min(2),
    gamesPlayed: z.number().int().min(2).max(7),
    seriesLength: z.number().int().min(2).max(7),
    games: z
      .array(
        z
          .object({
            gameDate: z.string().min(4),
            teamA: z.string().min(2),
            scoreA: z.number().int().positive(),
            teamB: z.string().min(2),
            scoreB: z.number().int().positive(),
          })
          .strict()
      )
      .min(2)
      .max(7),
  })
  .strict();

export const PlayoffMatchupsCatalogSchema = z
  .object({
    generated_at: z.string().datetime(), // see note above ModelDiagnosticsSchema
    teams: z.record(teamEnum, TeamPlayoffProfileSchema),
    sampleMatchups: z.array(PlayoffSeriesMatchupResultSchema).min(1),
    historicalBrackets: z.record(z.string(), z.array(HistoricalSeriesSchema)).optional(),
  })
  .strict();

// 13b. playoff_bracket_2026.json -> PlayoffBracketSeason (lib/playoffTypes.ts)
//
// Deliberately NOT HistoricalSeriesSchema reused. That schema requires
// gamesPlayed >= 2 and games[].length >= 2, which is right for a completed
// historical season but wrong here: this payload covers the CURRENT season, and
// a series still in progress legitimately has one game in it (the 2026 Finals
// does). The minimums are 1 here, with `seriesComplete` carrying the
// in-progress/finished distinction instead of it being implied by games count.
const BracketLengthProbSchema = z
  .object({
    length: z.number().int().min(1).max(7),
    label: z.string().min(2),
    probability: prob,
  })
  .strict();

const BracketForecastSchema = z
  .object({
    ratingBasis: z.string().min(5),
    asOf: z.string(),
    format: z.enum(['bo3', 'bo5', 'bo7']),
    formatLabel: z.string().min(5),
    teamHigh: z.string().min(2),
    teamHighAbbr: z.string(),
    teamLow: z.string().min(2),
    teamLowAbbr: z.string(),
    seedHigh: z.number().int().min(1).nullable(),
    seedLow: z.number().int().min(1).nullable(),
    netHighAdj: finiteNumber,
    netLowAdj: finiteNumber,
    pHighSeedWin: prob,
    pLowSeedWin: prob,
    predictedWinnerName: z.string().min(2),
    predictedWinner: z.string(),
    expectedGames: finiteNumber.min(1).max(7),
    lengthDistribution: z.array(BracketLengthProbSchema).min(1),
    resultStatus: z.enum(['correct', 'incorrect', 'pending']),
    fairMlHigh: z.number().int().optional(),
    fairMlLow: z.number().int().optional(),
    avgSeriesGames: finiteNumber.min(1).max(7).optional(),
  })
  .strict();

const BracketPredictionSchema = z
  .object({
    available: z.boolean(),
    provenance: z.enum(['round1_reconstruction', 'archived_forecast', 'unavailable']),
    provenanceLabel: z.string().min(5),
    forecast: BracketForecastSchema.nullable(),
  })
  .strict()
  // `available` and `forecast` must agree: an available prediction without
  // numbers, or an unavailable one carrying numbers, is a producer bug.
  .refine((p) => p.available === (p.forecast !== null), {
    message: 'prediction.available must match whether forecast is present',
  });

export const BracketSeriesSchema = z
  .object({
    teamA: z.string().min(2),
    teamNameA: z.string().min(2),
    teamB: z.string().min(2),
    teamNameB: z.string().min(2),
    winner: z.string().min(2),
    winnerName: z.string().min(2),
    round: z.string().min(2),
    gamesPlayed: z.number().int().min(1).max(7),
    seriesLength: z.number().int().min(1).max(7),
    games: z
      .array(
        z
          .object({
            gameDate: z.string().min(4),
            teamA: z.string().min(2),
            scoreA: z.number().int().positive(),
            teamB: z.string().min(2),
            scoreB: z.number().int().positive(),
          })
          .strict()
      )
      .min(1)
      .max(7),
    winsA: z.number().int().min(0).max(4),
    winsB: z.number().int().min(0).max(4),
    seriesComplete: z.boolean(),
    prediction: BracketPredictionSchema,
  })
  .strict();

export const PlayoffBracketSeasonSchema = z
  .object({
    generated_at: z.string().datetime(), // see note above ModelDiagnosticsSchema
    season: z.number().int().min(1997).max(2100),
    generatedAt: z.string(),
    sourceNote: z.string(),
    series: z.array(BracketSeriesSchema),
  })
  .strict();

// ------------------------------------------------------------------------------
// 13c. finals_game_predictions_2026.json -> FinalsGamePredictionSet
//      (lib/playoffTypes.ts, GitHub issue #94)
//
// Grain is one row per GAME of the Finals, not per series, so BracketSeriesSchema
// is deliberately not reused. The rules that matter here and have no analogue
// above are the two probability fields: every game carries a conditional win
// probability AND a P(game played), and the rest fields are all-or-nothing per
// game (`restApplied` false => every rest field null).
// ------------------------------------------------------------------------------
export const FinalsGamePredictionSchema = z
  .object({
    game: z.number().int().min(1).max(7),
    gameDate: z.string(),
    hostAbbr: z.string().min(2),
    hostName: z.string().min(2),
    hostIsHighSeed: z.boolean(),
    hcaSignForHighSeed: z.union([z.literal(1), z.literal(-1)]),
    pHighSeedWinHca: prob,
    pLowSeedWinHca: prob,
    pGamePlayed: prob,
    restApplied: z.boolean(),
    daysRestHigh: finiteNumber.min(0).nullable(),
    daysRestLow: finiteNumber.min(0).nullable(),
    backToBackHigh: z.boolean(),
    backToBackLow: z.boolean(),
    travelMilesHigh: finiteNumber.min(0).nullable(),
    travelMilesLow: finiteNumber.min(0).nullable(),
    fatigueDragHigh: finiteNumber.min(0).nullable(),
    fatigueDragLow: finiteNumber.min(0).nullable(),
    pHighSeedWinWithRest: prob.nullable(),
    pLowSeedWinWithRest: prob.nullable(),
    resultAvailable: z.boolean(),
    scheduleCompleted: z.boolean(),
    scoreHigh: z.number().int().positive().nullable(),
    scoreLow: z.number().int().positive().nullable(),
    resultStatus: z.enum(['correct', 'incorrect', 'pending']),
  })
  .strict()
  // The host flag and the HCA sign are two views of one fact; a disagreement
  // means the host assignment and the probability have come apart.
  .refine((g) => g.hcaSignForHighSeed === (g.hostIsHighSeed ? 1 : -1), {
    message: 'hcaSignForHighSeed must follow hostIsHighSeed',
  })
  // The two conditional probabilities are complements, as are the rest-adjusted pair.
  .refine((g) => Math.abs(g.pHighSeedWinHca + g.pLowSeedWinHca - 1) < 1e-6, {
    message: 'pHighSeedWinHca and pLowSeedWinHca must sum to 1',
  })
  // Rest is all-or-nothing per game: no half-populated rest block.
  .refine(
    (g) =>
      g.restApplied
        ? g.pHighSeedWinWithRest !== null &&
          g.pLowSeedWinWithRest !== null &&
          g.fatigueDragHigh !== null &&
          g.fatigueDragLow !== null
        : g.pHighSeedWinWithRest === null &&
          g.pLowSeedWinWithRest === null &&
          g.fatigueDragHigh === null &&
          g.fatigueDragLow === null,
    { message: 'rest fields must all be present when restApplied, and all null otherwise' }
  )
  // A result and a verdict must agree: no score without a verdict, none with 'pending'.
  .refine(
    (g) =>
      g.resultAvailable
        ? g.scoreHigh !== null && g.scoreLow !== null && g.resultStatus !== 'pending'
        : g.scoreHigh === null && g.scoreLow === null && g.resultStatus === 'pending',
    { message: 'scores and resultStatus must agree with resultAvailable' }
  );

export const FinalsMatchupSchema = z
  .object({
    teamHigh: z.string().min(2),
    teamHighAbbr: z.string().min(2),
    teamLow: z.string().min(2),
    teamLowAbbr: z.string().min(2),
    seedHigh: z.number().int().min(1),
    seedLow: z.number().int().min(1),
    netHighAdj: finiteNumber,
    netLowAdj: finiteNumber,
    winsHigh: z.number().int().min(0).max(4),
    winsLow: z.number().int().min(0).max(4),
    seriesComplete: z.boolean(),
    winThreshold: z.number().int().min(2).max(4),
    expectedGames: finiteNumber.min(1).max(7),
  })
  .strict();

export const FinalsGamePredictionSetSchema = z
  .object({
    generated_at: z.string().datetime(), // see note above ModelDiagnosticsSchema
    season: z.number().int().min(1997).max(2100),
    generatedAt: z.string(),
    sourceNote: z.string(),
    formatKey: z.string(),
    formatLabel: z.string(),
    restApplied: z.boolean(),
    restNote: z.string(),
    matchup: FinalsMatchupSchema.nullable(),
    lengthDistribution: z.array(BracketLengthProbSchema),
    games: z.array(FinalsGamePredictionSchema),
  })
  .strict()
  // Empty state is a real state, but it is all-or-nothing: an undetermined
  // matchup must not ship games, and games must not ship without a matchup.
  .refine((s) => (s.matchup === null ? s.games.length === 0 : s.games.length > 0), {
    message: 'games must be empty when matchup is null, and non-empty when it is not',
  })
  // Payload-level restApplied must agree with at least one game carrying rest.
  .refine(
    (s) => s.games.length === 0 || s.restApplied === s.games.some((g) => g.restApplied),
    { message: 'restApplied must match whether any game carries rest' }
  );

// 13d. finals_series_backtest_2026.json -> FinalsSeriesBacktestSet
//
// Reconstructions, not archived forecasts (see the interface header). Two
// invariants below are the ones that would actually catch a broken backtest, and
// both are asserted rather than trusted:
//   * every length distribution sums to 1 -- the exact DP guarantees it, so a
//     drift here means mass leaked somewhere;
//   * an information set's state wins must equal its gamesPlayed, which is what
//     makes it a WALK-FORWARD set rather than an arbitrary pairing of a score with
//     a cutoff.
export const FinalsBacktestInfoSetSchema = z
  .object({
    label: z.string().min(1),
    cutoffDate: z.string().min(8),
    gamesPlayed: z.number().int().min(0).max(7),
    stateHigh: z.number().int().min(0).max(3),
    stateLow: z.number().int().min(0).max(3),
    nGamesHigh: z.number().int().positive(),
    nGamesLow: z.number().int().positive(),
    netRawHigh: finiteNumber,
    netRawLow: finiteNumber,
    netAdjHigh: finiteNumber,
    netAdjLow: finiteNumber,
    pHighSeries: finiteNumber.min(0).max(1),
    pLowSeries: finiteNumber.min(0).max(1),
    fairMlHigh: z.number().int(),
    fairMlLow: z.number().int(),
    expectedLength: finiteNumber.min(1).max(7),
    lengthDistribution: z
      .array(z.object({ length: z.number().int().min(1).max(7), probability: finiteNumber.min(0).max(1) }).strict())
      .min(1),
    pHighSeriesFromZero: finiteNumber.min(0).max(1).nullable(),
    pHighSeriesRegularSeasonOnly: finiteNumber.min(0).max(1).nullable(),
  })
  .strict()
  .refine((s) => s.stateHigh + s.stateLow === s.gamesPlayed, {
    message: 'stateHigh + stateLow must equal gamesPlayed',
  })
  .refine(
    (s) => Math.abs(s.lengthDistribution.reduce((a, d) => a + d.probability, 0) - 1) < 1e-6,
    { message: 'lengthDistribution must sum to 1' }
  )
  .refine((s) => Math.abs(s.pHighSeries + s.pLowSeries - 1) < 1e-9, {
    message: 'pHighSeries and pLowSeries must sum to 1',
  });

export const FinalsSeriesBacktestSetSchema = z
  .object({
    generated_at: z.string().datetime(), // see note above ModelDiagnosticsSchema
    season: z.number().int().min(1997).max(2100),
    generatedAt: z.string(),
    sourceNote: z.string(),
    provenance: z.string(),
    matchup: z
      .object({
        teamHigh: z.string().min(2),
        teamHighAbbr: z.string().min(2),
        teamLow: z.string().min(2),
        teamLowAbbr: z.string().min(2),
      })
      .strict()
      .nullable(),
    games: z.array(
      z
        .object({
          game: z.number().int().positive(),
          gameDate: z.string().min(8),
          scoreHigh: z.number().int().positive(),
          scoreLow: z.number().int().positive(),
          highWon: z.boolean(),
        })
        .strict()
    ),
    infoSets: z.array(FinalsBacktestInfoSetSchema),
  })
  .strict()
  // Same all-or-nothing empty-state rule the per-game payload uses.
  .refine((s) => (s.matchup === null ? s.infoSets.length === 0 : s.infoSets.length > 0), {
    message: 'infoSets must be empty when matchup is null, and non-empty when it is not',
  })
  // There is exactly one information set per decision point: before G1, then one
  // after each played game. A mismatch means a cutoff was dropped or duplicated.
  .refine((s) => s.infoSets.length === 0 || s.infoSets.length === s.games.length + 1, {
    message: 'infoSets must number one more than the games played',
  })
  // A reconstruction that does not say it is one is the single worst failure mode
  // this artifact has, so an empty provenance string is a schema error.
  .refine((s) => s.infoSets.length === 0 || s.provenance.trim().length > 0, {
    message: 'provenance must be non-empty when information sets are shipped',
  });

// 14. shots_index.json -> PlayerCatalogEntry[] (lib/shotTypes.ts)
export const PlayerCatalogEntrySchema = z
  .object({
    player_id: z.string().min(1),
    player_name: z.string().min(2),
    team: teamEnum,
    total_shots: z.number().int().positive(),
  })
  .strict();

// 15. shots_metadata.json -> ShotsMetadata (lib/shotTypes.ts)
export const ZoneLeagueAverageSchema = z
  .object({
    zone: shotZoneEnum,
    total_fga: z.number().int().positive(),
    total_fgm: z.number().int().min(0),
    lg_fg_pct: prob,
  })
  .strict();

export const ShotsMetadataSchema = z
  .object({
    generated_at: z.string().datetime(), // see note above ModelDiagnosticsSchema
    season: z.number().int().optional(),
    updated_at: z.string().min(1),
    total_shots_sampled: z.number().int().positive(),
    league_averages: z.array(ZoneLeagueAverageSchema).length(14),
    zones: z.array(shotZoneEnum).length(14),
  })
  .strict();

// 16. public/data/shots/<player_id>.json -> PlayerShotData (lib/shotTypes.ts)
export const ShotRecordSchema = z
  .object({
    x: finiteNumber.min(-30).max(30),
    y: finiteNumber.min(-10).max(50),
    dist: finiteNumber.min(0).max(60),
    val: z.union([z.literal(2), z.literal(3)]),
    made: z.boolean(),
    zone: shotZoneEnum,
    type: z.string().min(1),
    period: z.number().int().min(1).max(10),
    clock: z.string().min(1),
  })
  .strict();

export const PlayerShotDataSchema = z
  .object({
    player_id: z.string().min(1),
    player_name: z.string().min(2),
    team: teamEnum,
    total_shots: z.number().int().positive(),
    shots: z.array(ShotRecordSchema).min(1),
  })
  .strict();

// ---------------------------------------------------------------------------
// matchups_slates.json -> MatchupsPayload (lib/matchupTypes.ts)
// Written by the repo root's build_matchups_dataset.R (issue #74).
//
// EVERY nullable field below is `.nullable()` rather than `.optional()` on
// purpose: the builder emits an explicit JSON `null`, never omits the key. That
// distinction is load-bearing -- jsonlite RETAINS a NULL list element and
// serialises it as `{}`, so a field that regressed to an empty object would
// still be "present" and would pass an `.optional()` check while breaking the
// page at render time. `.nullable()` rejects `{}`. This exact regression
// happened while building the page, so the contract is here to catch it again.
// ---------------------------------------------------------------------------
const projectionBasisEnum = z.enum([
  'logged_model',
  'logged_model_prob_only',
  'team_rating_differential',
]);

// Labelled by the builder from ESPN's season_type. An unrecognised value is
// passed through as "unknown_<n>" rather than silently relabelled, so the
// contract accepts that shape instead of failing closed on a new ESPN type.
const seasonTypeLabel = z.union([
  z.enum(['regular', 'postseason']),
  z.string().regex(/^unknown_\d+$/),
]);

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

export const MatchupSchema = z
  .object({
    game_id: z.string().regex(/^\d+$/, 'ESPN event id must be numeric'),
    game_date: isoDate,
    week: z.number().int().min(1).max(40),
    season_type: seasonTypeLabel,
    home_team: teamEnum,
    away_team: teamEnum,
    home_team_name: z.string().min(2),
    away_team_name: z.string().min(2),
    is_completed: z.boolean(),
    home_score: z.number().int().min(0).max(200).nullable(),
    away_score: z.number().int().min(0).max(200).nullable(),
    // Never 0: basketball plays overtime, so a completed game cannot be tied.
    actual_margin: z
      .number()
      .int()
      .refine((n) => n !== 0, 'a completed game cannot be tied')
      .nullable(),
    actual_winner: teamEnum.nullable(),
    has_prediction: z.boolean(),
    has_logged_prediction: z.boolean(),
    projection_basis: projectionBasisEnum.nullable(),
    projected_margin: finiteNumber.min(-60).max(60).nullable(),
    home_win_prob: prob.nullable(),
    predicted_winner: teamEnum.nullable(),
    is_graded: z.boolean(),
    prediction_correct: z.boolean().nullable(),
  })
  .strict()
  .refine((g) => g.home_team !== g.away_team, 'a team cannot play itself')
  // A completed game must carry a full scoreline, and an incomplete one none of
  // it -- a half-populated score is the shape a partially applied patch leaves.
  .refine(
    (g) =>
      g.is_completed
        ? g.home_score !== null && g.away_score !== null && g.actual_winner !== null
        : g.home_score === null && g.away_score === null && g.actual_winner === null,
    'is_completed must agree with the presence of scores and a winner'
  )
  .refine(
    (g) => !g.is_graded || (g.is_completed && g.has_logged_prediction),
    'a graded game must be completed and carry a logged prediction'
  )
  .refine(
    (g) => (g.is_graded ? g.prediction_correct !== null : g.prediction_correct === null),
    'prediction_correct must be present exactly when is_graded'
  )
  // The rating-differential basis is NEVER graded (see build_matchups_dataset.R,
  // PROJECTION BASES). This is the contract that keeps the weaker model out of
  // the published accuracy figure.
  .refine(
    (g) => !(g.projection_basis === 'team_rating_differential' && g.is_graded),
    'the team_rating_differential basis must never be graded'
  )
  .refine(
    (g) =>
      g.has_logged_prediction ===
      (g.projection_basis === 'logged_model' ||
        g.projection_basis === 'logged_model_prob_only'),
    'has_logged_prediction must agree with the projection basis'
  )
  .refine(
    (g) =>
      g.has_prediction
        ? g.projection_basis !== null &&
          g.projected_margin !== null &&
          g.home_win_prob !== null
        : g.projection_basis === null &&
          g.projected_margin === null &&
          g.home_win_prob === null,
    'has_prediction must agree with the presence of projection fields'
  )
  // The margin and the win probability must point the same way, or a card shows
  // a favourite with a sub-50% chance.
  .refine(
    (g) =>
      g.projected_margin === null ||
      g.home_win_prob === null ||
      g.projected_margin === 0 ||
      g.projected_margin > 0 === g.home_win_prob > 0.5,
    'projected_margin and home_win_prob disagree on who is favoured'
  );

export const MatchupWeekSchema = z
  .object({
    week: z.number().int().min(1).max(40),
    start_date: isoDate,
    end_date: isoDate,
    season_types: z.array(seasonTypeLabel).min(1),
    total_games: z.number().int().min(1),
    completed_games: z.number().int().min(0),
    pending_games: z.number().int().min(0),
    graded_games: z.number().int().min(0),
    correct_games: z.number().int().min(0).nullable(),
    accuracy_pct: pct.nullable(),
  })
  .strict()
  .refine(
    (w) => w.completed_games + w.pending_games === w.total_games,
    'completed + pending must equal total'
  )
  .refine(
    (w) => w.graded_games <= w.completed_games,
    'a week cannot grade more games than were played'
  )
  .refine(
    (w) =>
      w.graded_games > 0
        ? w.correct_games !== null && w.accuracy_pct !== null
        : w.correct_games === null && w.accuracy_pct === null,
    'correct_games/accuracy_pct must be present exactly when graded_games > 0'
  )
  .refine(
    (w) => w.correct_games === null || w.correct_games <= w.graded_games,
    'correct_games cannot exceed graded_games'
  )
  .refine((w) => w.start_date <= w.end_date, 'start_date must not follow end_date');

export const MatchupsPayloadSchema = z
  .object({
    season: z.number().int().min(2019).max(2100),
    generated_at: z.string().datetime(),
    season_start: isoDate,
    season_end: isoDate,
    active_week: z.number().int().min(1).max(40),
    available_weeks: z.array(z.number().int().min(1).max(40)).min(1),
    summary: z
      .object({
        total_games: z.number().int().min(1),
        completed_games: z.number().int().min(0),
        pending_games: z.number().int().min(0),
        graded_games: z.number().int().min(0),
        correct_games: z.number().int().min(0).nullable(),
        accuracy_pct: pct.nullable(),
        graded_games_available: z.boolean(),
        grading_state: z.enum(['no_games_graded_yet', 'partial', 'complete']),
        played_without_logged_prediction: z.number().int().min(0),
      })
      .strict()
      .refine(
        (s) => s.completed_games + s.pending_games === s.total_games,
        'completed + pending must equal total'
      )
      .refine(
        (s) => s.graded_games_available === s.graded_games > 0,
        'graded_games_available must agree with graded_games'
      )
      .refine(
        (s) =>
          s.graded_games > 0
            ? s.correct_games !== null && s.accuracy_pct !== null
            : s.correct_games === null && s.accuracy_pct === null,
        'correct_games/accuracy_pct must be present exactly when graded_games > 0'
      )
      .refine(
        (s) =>
          s.grading_state ===
          (s.graded_games === 0
            ? 'no_games_graded_yet'
            : s.graded_games === s.completed_games
              ? 'complete'
              : 'partial'),
        'grading_state must follow from graded_games vs completed_games'
      ),
    provenance: z
      .object({
        logged_predictions_in_window: z.number().int().min(0),
        logged_predictions_matched: z.number().int().min(0),
        logged_predictions_unmatched: z.number().int().min(0),
        log_match_pct: pct,
        games_with_logged_prediction: z.number().int().min(0),
        hca_points: finiteNumber,
        margin_sigma: finiteNumber.positive(),
        ratings_source: z.string().min(4),
        basis_counts: z.record(z.string(), z.number().int().min(0)),
      })
      .strict()
      .refine(
        (p) =>
          p.logged_predictions_matched + p.logged_predictions_unmatched ===
          p.logged_predictions_in_window,
        'matched + unmatched must equal the predictions in the window'
      ),
    weeks: z.array(MatchupWeekSchema).min(1),
    matchups: z.array(MatchupSchema).min(1),
  })
  .strict()
  .refine(
    (p) => p.matchups.length === p.summary.total_games,
    'summary.total_games must equal the matchups array length'
  )
  .refine(
    (p) => p.available_weeks.includes(p.active_week),
    'active_week must be one of available_weeks'
  )
  .refine(
    (p) => p.available_weeks.every((w, i, a) => i === 0 || a[i - 1] < w),
    'available_weeks must be strictly ascending'
  )
  .refine(
    (p) => p.season_start <= p.season_end,
    'season_start must not follow season_end'
  );
