import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import type { GameDetailEnvelope, WeeklyAttributionDataset } from '@/lib/gameDetailTypes';

const REPO_WEB_ROOT = path.resolve(__dirname, '../..');
const GAMES_DIR = path.join(REPO_WEB_ROOT, 'public', 'data', 'games');
const ATTRIBUTION_DIR = path.join(REPO_WEB_ROOT, 'public', 'data', 'week_attribution');

const BANNED_BETTING_REGEX =
  /\b(spread|projected_spread|point_spread|moneyline|sportsbook|over_under|parlay|wager|sharp_book|key_number_flag)\b/i;

function sigmoid(z: number): number {
  return 1 / (1 + Math.exp(-z));
}

function normalCdf(z: number): number {
  const p = 0.3275911;
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const sign = z < 0 ? -1 : 1;
  const x = Math.abs(z) / Math.sqrt(2);
  const t = 1.0 / (1.0 + p * x);
  const erf = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x);
  return 0.5 * (1.0 + sign * erf);
}

describe('Contract Suite: Waterfall Sum, Additivity & Entering Baselines (Issue #117 / 2-8)', () => {
  const gameFiles = fs.existsSync(GAMES_DIR)
    ? fs.readdirSync(GAMES_DIR).filter((f) => f.endsWith('.json'))
    : [];

  const weeklyFiles = fs.existsSync(ATTRIBUTION_DIR)
    ? fs.readdirSync(ATTRIBUTION_DIR).filter((f) => f.endsWith('.json'))
    : [];

  it('locates 145 completed game files and 9 unplayed weekly attribution files', () => {
    expect(gameFiles.length).toBe(145);
    expect(weeklyFiles.length).toBeGreaterThanOrEqual(9);
  });

  describe('Waterfall Additivity and 5-Step Points Decomposition', () => {
    const EXPECTED_STEP_KEYS = [
      'step_current_epa',
      'step_prior_epa',
      'step_elo_diff',
      'step_home_field',
      'step_qb_adjustment',
      'step_rounding',
    ];

    it('asserts 5-step waterfall sum equals projected margin to <= 0.02 across all completed games', () => {
      for (const file of gameFiles) {
        const fullPath = path.join(GAMES_DIR, file);
        const envelope = JSON.parse(fs.readFileSync(fullPath, 'utf8')) as GameDetailEnvelope;
        const exp = envelope.data.explainability;

        expect(exp, `${file} is missing explainability payload`).not.toBeNull();
        expect(exp!.waterfall, `${file} is missing waterfall`).toBeDefined();

        const wf = exp!.waterfall;
        const stepKeys = wf.steps.map((s) => s.key);
        expect(stepKeys, `${file} step keys mismatch`).toEqual(EXPECTED_STEP_KEYS);

        // All step values must be finite numbers
        for (const step of wf.steps) {
          expect(Number.isFinite(step.points), `${file} step ${step.key} has non-finite points`).toBe(true);
        }

        // Sum of the 5 steps + rounding must equal projected_margin within <= 0.02 tolerance (plan §5.2)
        const stepSum = wf.steps.reduce((sum, s) => sum + s.points, 0);
        const discrepancy = Math.abs(stepSum - wf.projected_margin);
        expect(
          discrepancy,
          `${file} waterfall sum (${stepSum}) deviates from margin (${wf.projected_margin}) by ${discrepancy} > 0.02`,
        ).toBeLessThanOrEqual(0.02);

        // Rounding step must be at most 0.02
        expect(
          Math.abs(wf.rounding),
          `${file} rounding (${wf.rounding}) exceeds 0.02 threshold`,
        ).toBeLessThanOrEqual(0.02);

        // Margin probability conversion via normal CDF Phi(margin / sigma)
        const sigma = wf.sigma || 14.6;
        const expectedProb = normalCdf(wf.projected_margin / sigma);
        expect(
          Math.abs(wf.home_win_prob - expectedProb),
          `${file} home_win_prob (${wf.home_win_prob}) deviates from Phi(margin / sigma) (${expectedProb}) > 0.015`,
        ).toBeLessThanOrEqual(0.015);
      }
    });

    it('asserts 5-step waterfall sum equals projected margin to <= 0.02 across all unplayed weekly games', () => {
      for (const file of weeklyFiles) {
        const fullPath = path.join(ATTRIBUTION_DIR, file);
        const dataset = JSON.parse(fs.readFileSync(fullPath, 'utf8')) as WeeklyAttributionDataset;

        for (const game of dataset.games) {
          const wf = game.waterfall;
          expect(wf, `${file} game ${game.game_id} missing waterfall`).toBeDefined();

          const stepKeys = wf.steps.map((s) => s.key);
          expect(stepKeys, `${file} game ${game.game_id} step keys mismatch`).toEqual(EXPECTED_STEP_KEYS);

          const stepSum = wf.steps.reduce((sum, s) => sum + s.points, 0);
          const discrepancy = Math.abs(stepSum - wf.projected_margin);
          expect(
            discrepancy,
            `${file} game ${game.game_id} waterfall sum deviates by ${discrepancy} > 0.02`,
          ).toBeLessThanOrEqual(0.02);

          expect(Math.abs(wf.rounding)).toBeLessThanOrEqual(0.02);
        }
      }
    });
  });

  describe('Secondary Model TreeSHAP Additivity and Published Track Record', () => {
    it('verifies TreeSHAP additivity and sigmoid calibration on all completed games', () => {
      for (const file of gameFiles) {
        const fullPath = path.join(GAMES_DIR, file);
        const envelope = JSON.parse(fs.readFileSync(fullPath, 'utf8')) as GameDetailEnvelope;
        const sm = envelope.data.explainability?.secondary_model;

        expect(sm, `${file} missing secondary_model`).not.toBeNull();
        expect(sm!.factors.length, `${file} must contain 12 entering factors`).toBe(12);

        // Sum of SHAP values plus base_value equals logit within rounding tolerance (12 factors * 0.00005 = ~0.0006)
        const shapSum = sm!.factors.reduce((sum, f) => sum + f.shap_value, 0);
        const reconstructedLogit = sm!.base_value + shapSum;
        const shapLogitDiff = Math.abs(reconstructedLogit - sm!.logit);
        expect(
          shapLogitDiff,
          `${file} TreeSHAP sum + base_value (${reconstructedLogit}) deviates from logit (${sm!.logit}) > 3e-4`,
        ).toBeLessThanOrEqual(0.0003);

        // Sigmoid(logit) equals model_win_prob within 3-decimal rounding tolerance <= 5e-4
        const expectedProb = sigmoid(sm!.logit);
        const probDiff = Math.abs(expectedProb - sm!.model_win_prob);
        expect(
          probDiff,
          `${file} Sigmoid(logit) (${expectedProb}) deviates from model_win_prob (${sm!.model_win_prob}) > 5e-4`,
        ).toBeLessThanOrEqual(0.0005);
        expect(Math.round(expectedProb * 1000) / 1000).toBe(sm!.model_win_prob);

        // Published out-of-sample track record must be present and authentic
        const record = sm!.out_of_sample_record;
        expect(record, `${file} missing out_of_sample_record`).toBeDefined();
        expect(record.n_games).toBe(145);
        expect(record.accuracy).toBeGreaterThanOrEqual(55.0);
        expect(record.accuracy).toBeLessThanOrEqual(65.0);
        expect(record.brier).toBeGreaterThan(0.18);
        expect(record.brier).toBeLessThan(0.25);
        expect(record.logloss).toBeGreaterThan(0.55);
        expect(record.logloss).toBeLessThan(0.70);

        // Agreement reflects pick alignment (>= 0.5 favors home)
        const primaryHomeFavored = (envelope.data.forecast?.home_win_prob ?? 0.5) >= 0.5;
        const secondaryHomeFavored = sm!.model_win_prob >= 0.5;
        const expectedAgreement = primaryHomeFavored === secondaryHomeFavored ? 'agree' : 'differ';
        expect(sm!.agreement).toBe(expectedAgreement);
      }
    });

    it('verifies TreeSHAP additivity and sigmoid calibration on all unplayed weekly games', () => {
      for (const file of weeklyFiles) {
        const fullPath = path.join(ATTRIBUTION_DIR, file);
        const dataset = JSON.parse(fs.readFileSync(fullPath, 'utf8')) as WeeklyAttributionDataset;

        for (const game of dataset.games) {
          const sm = game.secondary_model;
          expect(sm, `${file} game ${game.game_id} missing secondary_model`).not.toBeNull();
          expect(sm!.factors.length).toBe(12);

          const shapSum = sm!.factors.reduce((sum, f) => sum + f.shap_value, 0);
          const reconstructedLogit = sm!.base_value + shapSum;
          expect(Math.abs(reconstructedLogit - sm!.logit)).toBeLessThanOrEqual(0.0003);

          const expectedProb = sigmoid(sm!.logit);
          expect(Math.abs(expectedProb - sm!.model_win_prob)).toBeLessThanOrEqual(0.0005);
          expect(Math.round(expectedProb * 1000) / 1000).toBe(sm!.model_win_prob);

          const primaryHomeFavored = (game.predicted_home_win_prob ?? 0.5) >= 0.5;
          const secondaryHomeFavored = sm!.model_win_prob >= 0.5;
          const expectedAgreement = primaryHomeFavored === secondaryHomeFavored ? 'agree' : 'differ';
          expect(sm!.agreement).toBe(expectedAgreement);
        }
      }
    });
  });

  describe('Entering Efficiency Baselines Temporal Integrity', () => {
    it('asserts entering baselines strictly use prior games (week < current_game_week)', () => {
      for (const file of gameFiles) {
        const fullPath = path.join(GAMES_DIR, file);
        const envelope = JSON.parse(fs.readFileSync(fullPath, 'utf8')) as GameDetailEnvelope;
        const week = envelope.data.week;
        const baselines = envelope.data.explainability?.entering_baselines ?? [];

        expect(baselines.length, `${file} must contain exactly 10 entering baseline rows`).toBe(10);

        for (const b of baselines) {
          if (week === 1) {
            // Week 1: strictly no prior games
            expect(b.prior_games_n, `${file} Week 1 prior_games_n must be 0`).toBe(0);
            expect(b.entering_baseline, `${file} Week 1 baseline must be null`).toBeNull();
            expect(b.is_low_sample, `${file} Week 1 must have is_low_sample true`).toBe(true);
          } else {
            // Week W > 1: prior games must strictly be <= W - 1
            expect(
              b.prior_games_n,
              `${file} prior_games_n (${b.prior_games_n}) must be <= week - 1 (${week - 1})`,
            ).toBeLessThanOrEqual(week - 1);
            expect(b.prior_games_n).toBeGreaterThan(0);
            expect(b.entering_baseline, `${file} baseline must be populated`).not.toBeNull();
            expect(Number.isFinite(b.entering_baseline)).toBe(true);

            // Low-sample flag strictly thresholded at N < 4
            expect(b.is_low_sample).toBe(b.prior_games_n < 4);

            // If realized value is available, delta must equal realized - entering
            if (b.realized_value !== null && b.entering_baseline !== null && b.delta !== null) {
              const diff = Math.abs(b.delta - (b.realized_value - b.entering_baseline));
              expect(diff, `${file} delta mismatch for ${b.metric_key}`).toBeLessThanOrEqual(0.005);
            }
          }
        }

        // Divergence note integrity
        const exp = envelope.data.explainability!;
        if (week === 1) {
          expect(exp.divergence_note, `${file} Week 1 divergence_note must be null`).toBeNull();
        } else if (envelope.data.efficiency_factors !== null) {
          expect(exp.divergence_note, `${file} divergence note must be present`).toBeTruthy();
          expect(exp.divergence_note).toContain('divergence from entering baseline');
        } else {
          // Lag state (final score in schedules, but play-by-play not yet ingested)
          expect(exp.divergence_note).toBeNull();
        }
      }
    });

    it('asserts entering baselines strictly use prior games across unplayed weekly attribution files', () => {
      for (const file of weeklyFiles) {
        const fullPath = path.join(ATTRIBUTION_DIR, file);
        const dataset = JSON.parse(fs.readFileSync(fullPath, 'utf8')) as WeeklyAttributionDataset;
        const week = dataset.week;

        for (const game of dataset.games) {
          expect(game.entering_baselines.length).toBe(10);
          expect(game.divergence_note).toBeNull();

          for (const b of game.entering_baselines) {
            expect(b.prior_games_n).toBeLessThanOrEqual(week - 1);
            expect(b.entering_baseline).not.toBeNull();
            expect(b.realized_value).toBeNull();
            expect(b.delta).toBeNull();
            expect(b.is_low_sample).toBe(b.prior_games_n < 4);
          }
        }
      }
    });
  });

  describe('Strict Zero-Betting Vocabulary Enforcement', () => {
    it('asserts zero banned betting terminology in all 145 game detail files', () => {
      for (const file of gameFiles) {
        const fullPath = path.join(GAMES_DIR, file);
        const rawText = fs.readFileSync(fullPath, 'utf8');
        const match = rawText.match(BANNED_BETTING_REGEX);
        expect(
          match,
          `Forbidden betting term '${match?.[0]}' found in game detail file ${file}`,
        ).toBeNull();
      }
    });

    it('asserts zero banned betting terminology in all weekly attribution files', () => {
      for (const file of weeklyFiles) {
        const fullPath = path.join(ATTRIBUTION_DIR, file);
        const rawText = fs.readFileSync(fullPath, 'utf8');
        const match = rawText.match(BANNED_BETTING_REGEX);
        expect(
          match,
          `Forbidden betting term '${match?.[0]}' found in weekly attribution file ${file}`,
        ).toBeNull();
      }
    });

    it('asserts zero banned betting terminology in GameDetailModal component source', () => {
      const modalSourcePath = path.join(REPO_WEB_ROOT, 'components', 'GameDetailModal.tsx');
      const rawText = fs.readFileSync(modalSourcePath, 'utf8');
      const match = rawText.match(BANNED_BETTING_REGEX);
      expect(
        match,
        `Forbidden betting term '${match?.[0]}' found in GameDetailModal.tsx`,
      ).toBeNull();
    });
  });
});
