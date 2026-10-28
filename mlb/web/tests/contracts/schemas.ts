/**
 * Layer 1 — strict Zod schemas for MLB Analytics datasets in public/data.
 *
 * `.strict()` everywhere: an unexpected key from the R exporters is a contract
 * break. Numeric fields carry domain bounds (162-game season, probabilities in
 * [0, 1], percentages in [0, 100]).
 */
import { z } from 'zod';
import {
  MLB_TEAMS,
  MLB_LEAGUES,
  MLB_DIVISIONS,
  MLB_PLAYER_TYPES,
} from '../helpers/datasets';

const teamEnum = z.enum(MLB_TEAMS);
const playerTeamEnum = z.union([teamEnum, z.literal('MLB')]);
const leagueEnum = z.enum(MLB_LEAGUES);
const divisionEnum = z.enum(MLB_DIVISIONS);
const playerTypeEnum = z.enum(MLB_PLAYER_TYPES);
const prob = z.number().finite().min(0).max(1);
const pct = z.number().finite().min(0).max(100);
const num = z.number().finite();
const nonNeg = num.min(0);
const wins = num.min(0).max(162);
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

// ----------------------------------------------------------------------------
// 1. projections_season_teams.json -> TeamProjection[] (lib/types.ts)
// ----------------------------------------------------------------------------
const variantBlock = (prefix: string) => ({
  [`${prefix}_mean_wins`]: wins,
  [`${prefix}_median_wins`]: wins,
  [`${prefix}_sd_wins`]: num.min(0).max(81),
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
    full_name: z.string().min(4),
    conference: leagueEnum,
    league: leagueEnum,
    division: divisionEnum,
    proj_wins: wins,
    proj_losses: wins,
    win_pct: prob,
    ensemble_mean_wins: wins,
    ensemble_median_wins: wins,
    ensemble_sd_wins: num.min(0).max(81),
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
    elo_rating: num.min(1200).max(1800),
    team_rgs: num.min(20).max(80),
    run_differential: num,
    pythag_win_pct: prob,
    luck_wins: num,
    team_woba_pooled: num.min(0.2).max(0.5),
    team_xfip_pooled: num.min(2.0).max(7.0),
    net_talent_score: num,
    bullpen_fatigue: nonNeg,
    bullpen_grade: z.string().min(1),
    make_ds_prob: prob,
    make_lcs_prob: prob,
    win_pennant_prob: prob,
  })
  .strict();

// ----------------------------------------------------------------------------
// 2. projections_season_players.json -> PlayerProjection[] (lib/types.ts)
// ----------------------------------------------------------------------------
export const PlayerProjectionSchema = z
  .object({
    player_id: z.string().min(1),
    mlbam_id: z.string().min(1),
    player_name: z.string().min(2),
    team: playerTeamEnum,
    player_type: playerTypeEnum,
    position: z.enum(['B', 'SP', 'RP']),
    age: num.min(16).max(55),
    observed_workload: nonNeg,
    proj_workload: nonNeg,
    park_factor: num.positive(),
    stat1_label: z.string().min(1),
    stat1_raw: num,
    stat1_pooled: num,
    stat1_p10: num,
    stat1_p25: num,
    stat1_p50: num,
    stat1_p75: num,
    stat1_p90: num,
    stat1_sd: nonNeg,
    stat1_shrinkage: pct,
    stat2_label: z.string().min(1),
    stat2_raw: num,
    stat2_pooled: num,
    stat3_label: z.string().min(1),
    stat3_val: num,
    k_pct_pooled: nonNeg,
    bb_pct_pooled: nonNeg,
    count1_label: z.string().min(1),
    count1_val: nonNeg,
    count1_p10: nonNeg,
    count1_p25: nonNeg,
    count1_p50: nonNeg,
    count1_p75: nonNeg,
    count1_p90: nonNeg,
    count2_label: z.string().min(1),
    count2_val: nonNeg,
    count3_label: z.string().min(1),
    count3_val: nonNeg,
    primary_zscore: num,
    secondary_zscore: num,
    counting_zscore: num,
    composite_zscore: num,
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
  })
  .strict();

export const ModelMetadataSchema = z
  .object({
    schema_version: z.string().min(1),
    pipeline_stage: z.string().min(1),
    generated_at: z.string().datetime(),
    season: z.number().int().min(2020).max(2035),
    n_simulations: z.number().int().positive(),
    postseason_sims: z.number().int().positive(),
    margin_sigma: num.positive(),
    home_court_advantage: num,
    pythag_exponent: num.positive(),
    total_schedule_games: z.literal(2430),
    teams_count: z.literal(30),
    players_count: z.number().int().positive(),
    batters_count: z.number().int().positive(),
    pitchers_count: z.number().int().positive(),
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
    generated_at: z.string().datetime(),
    totalResolvedGames: z.number().int().positive(),
    overallAccuracy: prob,
    brierScore: num.min(0).max(1),
    brierSkillScore: num.optional(),
    logLoss: num.positive(),
    homeWinRate: prob,
    weightedCalibError: nonNeg.optional(),
    calibrationStatus: z.string().min(1).optional(),
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
            season: z.string().min(4),
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
          .object({
            bucket: z.string().min(1),
            count: z.number().int().min(0),
            label: z.string().min(1),
          })
          .strict(),
      )
      .min(3),
  })
  .strict();

// ----------------------------------------------------------------------------
// 5. projections_postseason_ops.json -> PostseasonOpsData (lib/types.ts)
// ----------------------------------------------------------------------------
export const PostseasonBracketTeamSchema = z
  .object({
    team_id: z.number().int().positive(),
    team_name: z.string().min(2),
    full_name: z.string().min(4).optional(),
    team: teamEnum,
    league: leagueEnum,
    division: divisionEnum,
    seed: z.number().int().min(1).max(6),
    wins: wins,
    elo_rating: num.min(1200).max(1800),
    make_ds: z.number().int().min(0).max(10000),
    make_lcs: z.number().int().min(0).max(10000),
    win_pennant: z.number().int().min(0).max(10000),
    win_ws: z.number().int().min(0).max(10000),
    pct_ds: pct,
    pct_lcs: pct,
    pct_pennant: pct,
    pct_ws: pct,
  })
  .strict();

export const BullpenStatusRowSchema = z
  .object({
    rank: z.number().int().min(1).max(30),
    team_id: z.number().int().positive(),
    team: teamEnum,
    team_name: z.string().min(2),
    full_name: z.string().min(4),
    league: leagueEnum,
    division: divisionEnum,
    proj_wins: wins,
    elo_rating: num.min(1200).max(1800),
    active_relievers: z.number().int().min(0),
    relievers_fatigued: z.number().int().min(0),
    relievers_exhausted: z.number().int().min(0),
    avg_bullpen_fatigue: nonNeg,
    max_reliever_fatigue: nonNeg,
    b2b_relievers_count: z.number().int().min(0),
    bullpen_vulnerability: nonNeg,
    vulnerability_grade: z.string().min(1),
  })
  .strict();

export const PostseasonOpsDataSchema = z
  .object({
    generated_at: z.string().datetime(),
    season: z.number().int().min(2020).max(2035),
    n_sims: z.number().int().positive(),
    bracket: z.array(PostseasonBracketTeamSchema).length(12),
    bullpen_status: z.array(BullpenStatusRowSchema).length(30),
  })
  .strict();

// ----------------------------------------------------------------------------
// 6. cbt_payroll_sheet.json -> CbtLeagueOverview (lib/cbtTypes.ts)
// ----------------------------------------------------------------------------
export const MlbPlayerContractSchema = z
  .object({
    playerId: z.string().min(1),
    playerName: z.string().min(2),
    position: z.string().min(1),
    salary2026: nonNeg,
    salary2027: nonNeg,
    salary2028: nonNeg,
    contractType: z.enum(['Guaranteed', 'Player Option', 'Club Option', 'Arbitration', 'Pre-Arb']),
    projectedWar: num,
    surplusValue: num,
    notes: z.string().optional(),
  })
  .strict();

export const FranchiseCbtProfileSchema = z
  .object({
    teamAbbr: teamEnum,
    teamName: z.string().min(2),
    fullName: z.string().min(4),
    league: leagueEnum,
    division: divisionEnum,
    payroll2026: num.positive(),
    payroll2027: nonNeg,
    payroll2028: nonNeg,
    baseThreshold: num.positive(),
    tier1Threshold: num.positive(),
    tier2Threshold: num.positive(),
    tier3Threshold: num.positive(),
    cbtSpace2026: nonNeg,
    cbtTaxBill: nonNeg,
    totalCommitment: num.positive(),
    cbtTier: z.enum([
      'Under CBT Threshold',
      'Tier 1 Surcharge ($244M-$264M)',
      'Tier 2 Draft Penalty ($264M-$284M)',
      'Tier 3 Cohen Tax ($284M-$304M)',
      'Tier 4 Mega Tax (> $304M)',
    ]),
    isRepeater: z.boolean(),
    penalties: z
      .object({
        draftPickDrop10: z.boolean(),
        internationalPoolReduction: z.boolean(),
        taxRateDescription: z.string().min(1),
        revenueShareEligible: z.boolean(),
      })
      .strict(),
    contracts: z.array(MlbPlayerContractSchema).min(1),
  })
  .strict();

export const CbtLeagueOverviewSchema = z
  .object({
    generated_at: z.string().datetime(),
    season: z.string().min(4),
    baseThreshold: num.positive(),
    tier1Threshold: num.positive(),
    tier2Threshold: num.positive(),
    tier3Threshold: num.positive(),
    totalLeaguePayroll: num.positive(),
    totalLuxuryTaxCollected: nonNeg,
    teams: z.array(FranchiseCbtProfileSchema).length(30),
  })
  .strict();

// ----------------------------------------------------------------------------
// 7. clutch_leverage_metrics.json -> ClutchCatalog (lib/clutchTypes.ts)
// ----------------------------------------------------------------------------
export const ClutchProfileSchema = z
  .object({
    playerId: z.string().min(1),
    mlbamId: z.string().min(1),
    playerName: z.string().min(2),
    team: playerTeamEnum,
    playerType: playerTypeEnum,
    position: z.string().min(1),
    clutchArchetype: z.string().min(2),
    baseMetricLabel: z.string().min(1),
    baseMetricVal: num,
    clutchMetricLabel: z.string().min(1),
    clutchMetricVal: num,
    deltaClutch: num,
    clutchScore: num,
    wpaTotal: num,
    highLiWpa: num,
    avgLeverageIndex: nonNeg,
    leverageBreakdown: z
      .object({
        lowPct: pct,
        medPct: pct,
        highPct: pct,
        extremePct: pct,
      })
      .strict(),
    rispSplit: z
      .object({
        pa: z.number().int().min(0),
        avg: num,
        obp: num,
        slg: num,
        wOBA: num,
        ops: num,
      })
      .strict(),
    firemanStats: z
      .object({
        inheritedRunners: z.number().int().min(0),
        inheritedScored: z.number().int().min(0),
        strandRatePct: pct,
        shutdowns: z.number().int().min(0),
        meltdowns: z.number().int().min(0),
        firemanIndex: num,
      })
      .strict()
      .optional(),
  })
  .strict();

export const ClutchCatalogSchema = z
  .object({
    generated_at: z.string().datetime(),
    updatedAt: z.string().min(1),
    totalProfiles: z.number().int().positive(),
    clutchLeaderBatters: z.array(z.string().min(1)).min(1),
    clutchLeaderPitchers: z.array(z.string().min(1)).min(1),
    profiles: z.array(ClutchProfileSchema).min(1),
  })
  .strict();

// ----------------------------------------------------------------------------
// 8. player_dna_profiles.json -> PlayerDnaCatalog (lib/playerDnaTypes.ts)
// ----------------------------------------------------------------------------
export const PlayerDnaProfileSchema = z
  .object({
    playerId: z.string().min(1),
    mlbamId: z.string().min(1),
    playerName: z.string().min(2),
    team: playerTeamEnum,
    playerType: playerTypeEnum,
    position: z.string().min(1),
    age: num.min(16).max(55),
    archetype: z.string().min(2),
    headlineStats: z
      .object({
        stat1Label: z.string().min(1),
        stat1Val: z.union([z.string(), num]),
        stat2Label: z.string().min(1),
        stat2Val: z.union([z.string(), num]),
        stat3Label: z.string().min(1),
        stat3Val: z.union([z.string(), num]),
        countLabel: z.string().min(1),
        countVal: z.union([z.string(), num]),
      })
      .strict(),
    compositeZscore: num,
    overallRating: pct,
    manifoldX: num,
    manifoldY: num,
    skillVector: z.record(z.string(), pct),
    categoryScores: z.record(z.string(), pct),
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

export const PlayerDnaCatalogSchema = z
  .object({
    generated_at: z.string().datetime(),
    updatedAt: z.string().min(1),
    eraBaseline: z.string().min(4),
    totalPlayers: z.number().int().positive(),
    batterArchetypes: z.array(z.string().min(1)).min(1),
    pitcherArchetypes: z.array(z.string().min(1)).min(1),
    profiles: z.array(PlayerDnaProfileSchema).min(1),
  })
  .strict();

// ----------------------------------------------------------------------------
// 9. playoff_series_matchups.json -> PlayoffMatchupsCatalog (lib/playoffTypes.ts)
// ----------------------------------------------------------------------------
export const SeriesSimulationResultSchema = z
  .object({
    teamA: teamEnum,
    teamB: teamEnum,
    hcaTeam: teamEnum,
    seriesLength: z.union([z.literal(3), z.literal(5), z.literal(7)]),
    winsToClinch: z.union([z.literal(2), z.literal(3), z.literal(4)]),
    baseEloDiff: num,
    tacticalMismatchAdjustment: num,
    winProbA: prob,
    winProbB: prob,
    fairMlA: z.number().int(),
    fairMlB: z.number().int(),
    avgGames: num.min(2).max(7),
    sweepProb: pct,
    gameDistributions: z
      .array(
        z
          .object({
            games: z.number().int().min(2).max(7),
            winner: teamEnum,
            probPct: pct,
          })
          .strict(),
      )
      .min(4),
    tacticalEdges: z.array(
      z
        .object({
          title: z.string().min(2),
          advantageTeam: teamEnum,
          description: z.string().min(5),
          deltaElo: num,
        })
        .strict(),
    ),
    gameSchedule: z
      .array(
        z
          .object({
            gameNumber: z.number().int().min(1).max(7),
            homeTeam: teamEnum,
            awayTeam: teamEnum,
            starterA: z.string().min(1),
            starterB: z.string().min(1),
            starterArGS: num,
            starterBrGS: num,
            winProbA: prob,
            winProbB: prob,
          })
          .strict(),
      )
      .min(3)
      .max(7),
  })
  .strict();

export const TeamPlayoffProfileSchema = z
  .object({
    teamAbbr: teamEnum,
    teamName: z.string().min(2),
    fullName: z.string().min(4),
    league: leagueEnum,
    division: divisionEnum,
    regularWins: wins,
    baseElo: num.min(1200).max(1800),
    tacticalRatings: z
      .object({
        rotationDepth: pct,
        bullpenLeverage: pct,
        powerIso: pct,
        contactDiscipline: pct,
        defenseFielding: pct,
      })
      .strict(),
    starters: z
      .array(
        z
          .object({
            playerId: z.string().min(1),
            mlbamId: z.string().min(1),
            playerName: z.string().min(2),
            rGS: num,
            projEra: nonNeg,
            xFip: nonNeg,
            kPct: nonNeg,
            bbPct: nonNeg,
            role: z.string().min(1),
          })
          .strict(),
      )
      .min(1),
    relievers: z
      .array(
        z
          .object({
            playerId: z.string().min(1),
            playerName: z.string().min(2),
            projEra: nonNeg,
            xFip: nonNeg,
            kPct: nonNeg,
            role: z.string().min(1),
          })
          .strict(),
      )
      .min(1),
    lineupCore: z
      .array(
        z
          .object({
            playerId: z.string().min(1),
            playerName: z.string().min(2),
            wOBA: nonNeg,
            iso: nonNeg,
            obp: nonNeg,
            hr: nonNeg,
            kPct: nonNeg,
            bbPct: nonNeg,
            slot: z.string().min(1),
          })
          .strict(),
      )
      .min(1),
  })
  .strict();

export const PrecomputedMatchupSchema = z
  .object({
    matchupKey: z.string().min(3),
    teamA: teamEnum,
    teamB: teamEnum,
    hcaTeam: teamEnum,
    series7: SeriesSimulationResultSchema,
    series5: SeriesSimulationResultSchema,
    series3: SeriesSimulationResultSchema,
  })
  .strict();

export const PlayoffMatchupsCatalogSchema = z
  .object({
    generated_at: z.string().datetime(),
    updatedAt: z.string().min(1),
    nSims: z.number().int().positive(),
    teams: z.record(teamEnum, TeamPlayoffProfileSchema),
    matchups: z.record(z.string(), PrecomputedMatchupSchema),
  })
  .strict();

// ----------------------------------------------------------------------------
// 10. matchups_index.json & matchups/week-NN.json (lib/matchupTypes.ts)
// ----------------------------------------------------------------------------
export const MatchupSlateSchema = z
  .object({
    week: z.number().int().positive(),
    label: z.string().min(1),
    status: z.enum(['past', 'active', 'future']),
    start_date: isoDate,
    end_date: isoDate,
    game_count: z.number().int().positive(),
    graded_count: z.number().int().min(0),
    correct_count: z.number().int().min(0),
  })
  .strict()
  .refine((w) => w.graded_count <= w.game_count, 'graded_count <= game_count')
  .refine((w) => w.correct_count <= w.graded_count, 'correct_count <= graded_count')
  .refine((w) => w.start_date <= w.end_date, 'start_date <= end_date');

export const MatchupsIndexSchema = z
  .object({
    season: z.number().int().min(2020).max(2035),
    generated_at: z.string().datetime(),
    active_week: z.number().int().positive(),
    total_games: z.number().int().positive(),
    completed_games: z.number().int().min(0),
    graded_games: z.number().int().min(0),
    correct_picks: z.number().int().min(0),
    overall_accuracy: prob.nullable(),
    available_weeks: z.array(MatchupSlateSchema).min(1),
  })
  .strict();

export const MatchupSchema = z
  .object({
    game_pk: z.number().int().positive(),
    game_date: isoDate,
    week: z.number().int().positive(),
    game_type: z.enum(['R', 'F', 'D', 'L', 'W']),
    series_description: z.string().min(1),
    status_detail: z.string().min(1),
    venue_name: z.string().min(1),
    home_team_id: z.number().int().positive(),
    home_team_name: z.string().min(2),
    home_team: teamEnum,
    away_team_id: z.number().int().positive(),
    away_team_name: z.string().min(2),
    away_team: teamEnum,
    is_completed: z.boolean(),
    home_win_prob: prob,
    away_win_prob: prob,
    projection_source: z.enum(['walk_forward', 'current_elo']),
    home_score: z.number().int().min(0).nullable(),
    away_score: z.number().int().min(0).nullable(),
    prediction_correct: z.boolean().nullable(),
  })
  .strict()
  .refine((g) => g.home_team !== g.away_team, 'home_team !== away_team')
  .refine(
    (g) => Math.abs(g.home_win_prob + g.away_win_prob - 1) <= 1e-3,
    'home_win_prob + away_win_prob must sum to 1',
  );

// ----------------------------------------------------------------------------
// 11. world_series.json -> WorldSeriesData (lib/types.ts)
// ----------------------------------------------------------------------------
export const WorldSeriesGameSchema = z
  .object({
    game_number: z.number().int().min(1).max(7),
    game_pk: z.number().int().positive(),
    game_date: isoDate,
    venue_name: z.string().min(1),
    status_detail: z.string().min(1),
    is_completed: z.boolean(),
    home_team: teamEnum,
    home_team_name: z.string().min(2),
    home_score: z.number().int().min(0).nullable(),
    away_team: teamEnum,
    away_team_name: z.string().min(2),
    away_score: z.number().int().min(0).nullable(),
    home_win_prob: prob,
    winner: teamEnum.nullable(),
  })
  .strict();

export const WorldSeriesDataSchema = z
  .object({
    season: z.number().int().min(2020).max(2035),
    title: z.string().min(2),
    format: z.string().min(2),
    start_date: isoDate,
    end_date: isoDate,
    status: z.enum(['scheduled', 'in_progress', 'complete']),
    games_played: z.number().int().min(0).max(7),
    games_scheduled: z.number().int().min(4).max(7),
    champion: teamEnum.nullable(),
    home_field: z
      .object({
        team: teamEnum,
        team_name: z.string().min(2),
        wins: z.number().int().min(0).max(4),
      })
      .strict(),
    challenger: z
      .object({
        team: teamEnum,
        team_name: z.string().min(2),
        wins: z.number().int().min(0).max(4),
      })
      .strict(),
    games: z.array(WorldSeriesGameSchema).min(4).max(7),
  })
  .strict();
