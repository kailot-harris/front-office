import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import {
  DATA_DIR,
  SHOTS_DIR,
  EXPECTED_DATA_FILES,
  loadAllDatasets,
  readPlayerShotFile,
} from '../helpers/datasets';
import {
  TeamProjectionSchema,
  PlayerProjectionSchema,
  ModelMetadataSchema,
  ModelDiagnosticsSchema,
  WnbaCbaLeagueOverviewSchema,
  ClutchProfileSchema,
  CoachingStaffMetricSchema,
  DefensiveProfileSchema,
  PlayerDnaProfileSchema,
  OffseasonDraftProspectSchema,
  OffseasonTeamProfileSchema,
  OffseasonTransactionSchema,
  PlayoffMatchupsCatalogSchema,
  PlayoffBracketSeasonSchema,
  FinalsGamePredictionSetSchema,
  PlayerCatalogEntrySchema,
  ShotsMetadataSchema,
  PlayerShotDataSchema,
} from './schemas';

function formatIssues(issues: z.ZodIssue[], max = 8): string {
  return (
    issues
      .slice(0, max)
      .map((i) => `  • [${i.path.join('.')}] ${i.message} (${i.code})`)
      .join('\n') +
    (issues.length > max ? `\n  ... and ${issues.length - max} more` : '')
  );
}

function assertValid<T>(schema: z.ZodType<T>, data: unknown, label: string) {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw new Error(
      `${label} failed schema validation (${result.error.issues.length} issue(s)):\n${formatIssues(
        result.error.issues
      )}`
    );
  }
}

describe('JSON data file presence & parseability', () => {
  it.each(EXPECTED_DATA_FILES)('%s exists, is non-empty, and parses as valid JSON', (fileName) => {
    const fullPath = path.join(DATA_DIR, fileName);
    expect(fs.existsSync(fullPath), `Missing data file: ${fullPath}`).toBe(true);
    const stat = fs.statSync(fullPath);
    expect(stat.size, `${fileName} is empty`).toBeGreaterThan(10);
    const raw = fs.readFileSync(fullPath, 'utf-8');
    expect(() => JSON.parse(raw)).not.toThrow();
    expect(raw).not.toMatch(/:\s*NaN\b/);
    expect(raw).not.toMatch(/:\s*-?Infinity\b/);
  });
});

describe('Strict Zod schema contracts against public/data/*.json', () => {
  const d = loadAllDatasets();

  it('projections_season_teams.json (15 teams) matches TeamProjectionSchema', () => {
    expect(d.teams).toHaveLength(15);
    assertValid(z.array(TeamProjectionSchema), d.teams, 'projections_season_teams.json');
  });

  it('projections_season_players.json matches PlayerProjectionSchema', () => {
    expect(d.players.length).toBeGreaterThanOrEqual(180);
    assertValid(z.array(PlayerProjectionSchema), d.players, 'projections_season_players.json');
  });

  it('projections_models_metadata.json matches ModelMetadataSchema', () => {
    assertValid(ModelMetadataSchema, d.metadata, 'projections_models_metadata.json');
  });

  it('projections_diagnostics.json matches ModelDiagnosticsSchema', () => {
    assertValid(ModelDiagnosticsSchema, d.diagnostics, 'projections_diagnostics.json');
  });

  it('cba_cap_sheet.json matches WnbaCbaLeagueOverviewSchema', () => {
    assertValid(WnbaCbaLeagueOverviewSchema, d.cbaCapSheet, 'cba_cap_sheet.json');
  });

  it('clutch_leverage_metrics.json matches ClutchProfileSchema', () => {
    expect(d.clutch.length).toBeGreaterThanOrEqual(180);
    assertValid(z.array(ClutchProfileSchema), d.clutch, 'clutch_leverage_metrics.json');
  });

  it('coaching_metrics.json (15 staffs) matches CoachingStaffMetricSchema', () => {
    expect(d.coaches).toHaveLength(15);
    assertValid(z.array(CoachingStaffMetricSchema), d.coaches, 'coaching_metrics.json');
  });

  it('defensive_metrics.json matches DefensiveProfileSchema', () => {
    expect(d.defense.length).toBeGreaterThanOrEqual(180);
    assertValid(z.array(DefensiveProfileSchema), d.defense, 'defensive_metrics.json');
  });

  it('player_dna_profiles.json matches PlayerDnaProfileSchema', () => {
    expect(d.playerDna.length).toBeGreaterThanOrEqual(180);
    assertValid(z.array(PlayerDnaProfileSchema), d.playerDna, 'player_dna_profiles.json');
  });

  it('offseason_draft.json matches OffseasonDraftProspectSchema', () => {
    expect(d.offseasonDraft).toHaveLength(15);
    assertValid(z.array(OffseasonDraftProspectSchema), d.offseasonDraft, 'offseason_draft.json');
  });

  it('offseason_teams.json (15 teams) matches OffseasonTeamProfileSchema', () => {
    expect(d.offseasonTeams).toHaveLength(15);
    assertValid(z.array(OffseasonTeamProfileSchema), d.offseasonTeams, 'offseason_teams.json');
  });

  it('offseason_transactions.json matches OffseasonTransactionSchema', () => {
    expect(d.offseasonTransactions.length).toBeGreaterThanOrEqual(5);
    assertValid(
      z.array(OffseasonTransactionSchema),
      d.offseasonTransactions,
      'offseason_transactions.json'
    );
  });

  it('playoff_series_matchups.json matches PlayoffMatchupsCatalogSchema', () => {
    assertValid(PlayoffMatchupsCatalogSchema, d.playoffSeries, 'playoff_series_matchups.json');
  });

  it('playoff_bracket_2026.json matches PlayoffBracketSeasonSchema', () => {
    assertValid(PlayoffBracketSeasonSchema, d.playoffBracket2026, 'playoff_bracket_2026.json');
  });

  it('finals_game_predictions_2026.json matches FinalsGamePredictionSetSchema', () => {
    assertValid(
      FinalsGamePredictionSetSchema,
      d.finalsGamePredictions,
      'finals_game_predictions_2026.json'
    );
  });

  it('shots_index.json matches PlayerCatalogEntrySchema', () => {
    expect(d.shotsIndex.length).toBeGreaterThanOrEqual(150);
    assertValid(z.array(PlayerCatalogEntrySchema), d.shotsIndex, 'shots_index.json');
  });

  it('shots_metadata.json matches ShotsMetadataSchema', () => {
    assertValid(ShotsMetadataSchema, d.shotsMetadata, 'shots_metadata.json');
  });

  it('sampled public/data/shots/<player_id>.json files match PlayerShotDataSchema', () => {
    expect(fs.existsSync(SHOTS_DIR)).toBe(true);
    // Validate top 10 shot catalog entries + last 5 entries
    const sampleEntries = [
      ...d.shotsIndex.slice(0, 10),
      ...d.shotsIndex.slice(-5),
    ];
    for (const entry of sampleEntries) {
      const shotData = readPlayerShotFile(entry.player_id);
      assertValid(
        PlayerShotDataSchema,
        shotData,
        `public/data/shots/${entry.player_id}.json (${entry.player_name})`
      );
    }
  });
});
