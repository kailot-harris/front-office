import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import {
  waterfallStepSchema,
  pointsWaterfallPayloadSchema,
  shapFactorItemSchema,
  secondaryModelSummarySchema,
  efficiencyBaselineComparisonSchema,
  gameExplainabilityPayloadSchema,
  weeklyAttributionDatasetSchema,
  gameDetailEnvelopeSchema,
} from './schemas';
import {
  GameExplainabilityPayload,
  WeeklyAttributionDataset,
  GameDetailEnvelope,
} from '@/lib/gameDetailTypes';

describe('Explainability Contracts and Schema Suite (Issue #114 / 2-5)', () => {
  const validSampleExplainability: GameExplainabilityPayload = {
    game_id: '2026_10_KC_BUF',
    season: 2026,
    week: 10,
    projection_basis: 'logged_pregame',
    predicted_margin: 2.85,
    predicted_home_win_prob: 0.578,
    waterfall: {
      projected_margin: 2.85,
      home_win_prob: 0.578,
      sigma: 14.6,
      intercept: 1.5,
      rounding: 0.001,
      steps: [
        {
          key: 'step_current_epa',
          label: 'Current-Season EPA',
          points: 1.25,
          description: 'Current season rolling EPA net differential',
        },
        {
          key: 'step_prior_epa',
          label: 'Pre-Season Prior',
          points: 0.45,
          description: 'Prior season baseline regressed to mean',
        },
        {
          key: 'step_elo_diff',
          label: 'Elo Differential',
          points: 0.65,
          description: 'Elo rating points differential',
        },
        {
          key: 'step_home_field',
          label: 'Home Field Advantage',
          points: 1.85,
          description: 'Neutral site and home field advantage blend',
        },
        {
          key: 'step_qb_adjustment',
          label: 'Starting Quarterback',
          points: -1.35,
          description: 'Quarterback availability and injury adjustment',
        },
        {
          key: 'step_rounding',
          label: 'Rounding',
          points: 0.001,
          description: 'Decomposition residual',
        },
      ],
    },
    secondary_model: {
      model_id: 'xgboost_feature_fusion_v1',
      model_label: 'Secondary Model (XGBoost TreeSHAP)',
      model_win_prob: 0.562,
      logit: 0.25,
      base_value: 0.12,
      agreement: 'agree',
      out_of_sample_record: {
        n_games: 145,
        accuracy: 59.3,
        brier: 0.2232,
        logloss: 0.6541,
      },
      factors: [
        {
          feature: 'diff_raw',
          label: 'Overall EPA/Play Differential',
          value: 0.082,
          shap_value: 0.065,
        },
        {
          feature: 'diff_pass_epa',
          label: 'Passing EPA Differential',
          value: 0.114,
          shap_value: 0.042,
        },
        {
          feature: 'ridge_margin',
          label: 'Primary Ridge Model Projection',
          value: 2.85,
          shap_value: 0.023,
        },
      ],
    },
    entering_baselines: [
      {
        metric_key: 'epa_per_play',
        metric_label: 'EPA / Play',
        team_abbr: 'BUF',
        entering_baseline: 0.095,
        realized_value: 0.112,
        delta: 0.017,
        prior_games_n: 9,
        is_low_sample: false,
      },
      {
        metric_key: 'success_rate',
        metric_label: 'Success Rate',
        team_abbr: 'BUF',
        entering_baseline: 0.468,
        realized_value: 0.442,
        delta: -0.026,
        prior_games_n: 9,
        is_low_sample: false,
      },
    ],
    divergence_note: 'BUF passing EPA exceeded entering baseline by +0.017 EPA/play.',
  };

  it('validates a complete synthetic GameExplainabilityPayload', () => {
    const res = gameExplainabilityPayloadSchema.safeParse(validSampleExplainability);
    expect(res.success).toBe(true);
  });

  it('validates explainability with secondary_model null (e.g. uncalibrated or fallback)', () => {
    const payloadWithoutSecondary: GameExplainabilityPayload = {
      ...validSampleExplainability,
      secondary_model: null,
    };
    const res = gameExplainabilityPayloadSchema.safeParse(payloadWithoutSecondary);
    expect(res.success).toBe(true);
  });

  it('enforces strict schemas: rejects unknown unexpected fields', () => {
    const invalidPayload = {
      ...validSampleExplainability,
      unknown_field: 'illegal_value',
    };
    const res = gameExplainabilityPayloadSchema.safeParse(invalidPayload);
    expect(res.success).toBe(false);
  });

  it('validates WeeklyAttributionDataset schema', () => {
    const dataset: WeeklyAttributionDataset = {
      schema_version: '1.0',
      generated_at: '2026-11-16T12:00:00Z',
      season: 2026,
      week: 10,
      games: [validSampleExplainability],
    };
    const res = weeklyAttributionDatasetSchema.safeParse(dataset);
    expect(res.success).toBe(true);
  });

  it('validates GameDetailEnvelope with non-null explainability payload', () => {
    const sampleEnvelope: GameDetailEnvelope = {
      schema_version: '1.0',
      generated_at: '2026-11-16T12:00:00Z',
      sport: 'nfl',
      endpoint: 'game_detail',
      season: 2026,
      season_label: '2026-2027',
      game_id: '2026_10_KC_BUF',
      data: {
        game_id: '2026_10_KC_BUF',
        season: 2026,
        season_label: '2026-2027',
        week: 10,
        week_label: 'Week 10',
        gameday: '2026-11-17',
        weekday: 'Sunday',
        gametime: '16:25',
        is_completed: true,
        has_box_score: true,
        away_team: {
          teamAbbr: 'KC',
          teamName: 'Kansas City Chiefs',
          score: 21,
          is_winner: false,
        },
        home_team: {
          teamAbbr: 'BUF',
          teamName: 'Buffalo Bills',
          score: 30,
          is_winner: true,
        },
        forecast: {
          projected_margin: 2.85,
          home_win_prob: 0.578,
          away_win_prob: 0.422,
          home_power_rating: 4.8,
          away_power_rating: 4.2,
          prediction_correct: true,
        },
        efficiency_factors: [],
        team_stats: [],
        leaders: [],
        box_score: { away_players: [], home_players: [] },
        injury_designations: [],
        explainability: validSampleExplainability,
      },
    };

    const res = gameDetailEnvelopeSchema.safeParse(sampleEnvelope);
    expect(res.success).toBe(true);
  });

  it('enforces zero banned betting terminology in contracts and schemas', () => {
    const FORBIDDEN_BETTING_RE =
      /\b(spread|projected_spread|point_spread|moneyline|sportsbook|over_under|parlay|wager|sharp_book|key_number_flag)\b/i;

    const gameDetailTypesPath = path.resolve(__dirname, '../../lib/gameDetailTypes.ts');
    const schemasPath = path.resolve(__dirname, './schemas.ts');

    const typesContent = fs.readFileSync(gameDetailTypesPath, 'utf8');
    const schemasContent = fs.readFileSync(schemasPath, 'utf8');

    const matchTypes = typesContent.match(FORBIDDEN_BETTING_RE);
    expect(
      matchTypes,
      `Forbidden betting term '${matchTypes?.[0]}' found in gameDetailTypes.ts`
    ).toBeNull();

    const matchSchemas = schemasContent.match(FORBIDDEN_BETTING_RE);
    expect(
      matchSchemas,
      `Forbidden betting term '${matchSchemas?.[0]}' found in schemas.ts`
    ).toBeNull();
  });
});
