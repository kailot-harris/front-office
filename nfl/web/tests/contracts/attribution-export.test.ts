import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import {
  gameDetailEnvelopeSchema,
  weeklyAttributionDatasetSchema,
  matchupsDatasetSchema,
} from './schemas';
import { GameDetailEnvelope, WeeklyAttributionDataset } from '@/lib/gameDetailTypes';

const REPO_WEB_ROOT = path.resolve(__dirname, '../..');
const GAMES_DIR = path.join(REPO_WEB_ROOT, 'public', 'data', 'games');
const ATTRIBUTION_DIR = path.join(REPO_WEB_ROOT, 'public', 'data', 'week_attribution');
const MATCHUPS_FILE = path.join(REPO_WEB_ROOT, 'public', 'data', 'matchups_current_week.json');

const FORBIDDEN_BETTING_RE =
  /\b(spread|projected_spread|point_spread|moneyline|sportsbook|over_under|parlay|wager|sharp_book|key_number_flag)\b/i;

describe('Attribution & Explainability Export Suite (Issue #115 / 2-6)', () => {
  const gameFiles = fs.existsSync(GAMES_DIR)
    ? fs.readdirSync(GAMES_DIR).filter((f) => f.endsWith('.json'))
    : [];

  const weeklyFiles = fs.existsSync(ATTRIBUTION_DIR)
    ? fs.readdirSync(ATTRIBUTION_DIR).filter((f) => f.endsWith('.json'))
    : [];

  it('finds exactly 145 completed game detail files on disk', () => {
    expect(gameFiles.length).toBe(145);
  });

  it('finds at least 9 weekly attribution files for unplayed weeks (weeks 10-18)', () => {
    expect(weeklyFiles.length).toBeGreaterThanOrEqual(9);
  });

  it('validates every completed game JSON has non-null explainability satisfying gameDetailEnvelopeSchema', () => {
    for (const filename of gameFiles) {
      const filePath = path.join(GAMES_DIR, filename);
      const rawText = fs.readFileSync(filePath, 'utf8');
      const json = JSON.parse(rawText) as GameDetailEnvelope;

      expect(json.data.explainability, `${filename} must have explainability populated`).not.toBeNull();

      const parseResult = gameDetailEnvelopeSchema.safeParse(json);
      expect(
        parseResult.success,
        `${filename} failed gameDetailEnvelopeSchema: ${!parseResult.success ? JSON.stringify(parseResult.error.format()) : ''}`
      ).toBe(true);

      const exp = json.data.explainability!;
      expect(exp.waterfall).toBeDefined();
      expect(exp.waterfall.steps.length).toBe(6);

      // Verify waterfall steps sum equals projected_margin within tolerance 0.02
      const stepSum = exp.waterfall.steps.reduce((sum, s) => sum + s.points, 0);
      expect(
        Math.abs(stepSum - exp.waterfall.projected_margin),
        `${filename} waterfall sum (${stepSum}) deviates from projected_margin (${exp.waterfall.projected_margin}) > 0.02`
      ).toBeLessThanOrEqual(0.02);

      expect(Math.abs(exp.waterfall.rounding)).toBeLessThanOrEqual(0.02);

      // Verify entering baselines structure
      expect(exp.entering_baselines.length).toBe(10);
      for (const b of exp.entering_baselines) {
        if (json.data.week === 1) {
          expect(b.entering_baseline).toBeNull();
          expect(b.prior_games_n).toBe(0);
          expect(b.is_low_sample).toBe(true);
        } else {
          expect(b.entering_baseline).not.toBeNull();
          expect(b.prior_games_n).toBeGreaterThan(0);
          if (b.delta !== null && b.realized_value !== null && b.entering_baseline !== null) {
            expect(Math.abs(b.delta - (b.realized_value - b.entering_baseline))).toBeLessThanOrEqual(0.005);
          }
        }
      }

      if (json.data.week > 1 && json.data.efficiency_factors !== null) {
        expect(exp.divergence_note).toBeTruthy();
      } else {
        expect(exp.divergence_note).toBeNull();
      }
    }
  });

  it('validates every weekly attribution file against weeklyAttributionDatasetSchema', () => {
    for (const filename of weeklyFiles) {
      const filePath = path.join(ATTRIBUTION_DIR, filename);
      const rawText = fs.readFileSync(filePath, 'utf8');
      const json = JSON.parse(rawText) as WeeklyAttributionDataset;

      const parseResult = weeklyAttributionDatasetSchema.safeParse(json);
      expect(
        parseResult.success,
        `${filename} failed weeklyAttributionDatasetSchema: ${!parseResult.success ? JSON.stringify(parseResult.error.format()) : ''}`
      ).toBe(true);

      expect(json.games.length).toBeGreaterThan(0);

      for (const gameExp of json.games) {
        expect(gameExp.waterfall).toBeDefined();
        expect(gameExp.waterfall.steps.length).toBe(6);
        const stepSum = gameExp.waterfall.steps.reduce((sum, s) => sum + s.points, 0);
        expect(
          Math.abs(stepSum - gameExp.waterfall.projected_margin),
          `${filename} game ${gameExp.game_id} waterfall sum (${stepSum}) deviates from margin (${gameExp.waterfall.projected_margin}) > 0.02`
        ).toBeLessThanOrEqual(0.02);

        // Unplayed games must have divergence_note null
        expect(gameExp.divergence_note).toBeNull();
      }
    }
  });

  it('enforces zero banned betting terminology in all weekly attribution files', () => {
    for (const filename of weeklyFiles) {
      const filePath = path.join(ATTRIBUTION_DIR, filename);
      const rawText = fs.readFileSync(filePath, 'utf8');
      const match = rawText.match(FORBIDDEN_BETTING_RE);
      expect(
        match,
        `Forbidden betting term '${match?.[0]}' found in weekly attribution file ${filename}`
      ).toBeNull();
    }
  });

  it('asserts matchups_current_week.json is unbloated and clean', () => {
    const raw = fs.readFileSync(MATCHUPS_FILE, 'utf8');
    const json = JSON.parse(raw);
    const parseRes = matchupsDatasetSchema.safeParse(json);
    expect(parseRes.success).toBe(true);

    // Verify explainability or waterfall is NOT embedded into matchup cards
    for (const m of json.matchups) {
      expect((m as Record<string, unknown>).explainability).toBeUndefined();
      expect((m as Record<string, unknown>).waterfall).toBeUndefined();
      expect((m as Record<string, unknown>).margin_waterfall).toBeUndefined();
    }
  });
});
