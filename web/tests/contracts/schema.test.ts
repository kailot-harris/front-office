/**
 * Layer 1 — every dataset exists, parses, and satisfies its strict schema.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import {
  DATA_DIR,
  SHOTS_DIR,
  EXPECTED_DATA_FILES,
  LEAGUE,
  loadAllDatasets,
  readPlayerShotFile,
} from '../helpers/datasets';
import {
  TeamProjectionSchema,
  PlayerProjectionSchema,
  ModelMetadataSchema,
  ModelDiagnosticsSchema,
  CbaLeagueOverviewSchema,
  ClutchProfileSchema,
  CoachingStaffMetricSchema,
  DefensiveProfileSchema,
  PlayerDnaProfileSchema,
  RookieDraftProfileSchema,
  TeamOffseasonProfileSchema,
  OffseasonTransactionSchema,
  PlayoffMatchupsCatalogSchema,
  PlayerCatalogEntrySchema,
  ShotsMetadataSchema,
  PlayerShotDataSchema,
} from './schemas';

function formatIssues(issues: z.ZodIssue[], max = 8): string {
  return (
    issues
      .slice(0, max)
      .map((i) => `  • [${i.path.join('.')}] ${i.message} (${i.code})`)
      .join('\n') + (issues.length > max ? `\n  ... and ${issues.length - max} more` : '')
  );
}

function assertValid<T>(schema: z.ZodType<T>, data: unknown, label: string) {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw new Error(
      `${label} failed schema validation (${result.error.issues.length} issue(s)):\n${formatIssues(result.error.issues)}`,
    );
  }
}

describe('JSON data file presence & parseability', () => {
  it.each(EXPECTED_DATA_FILES)('%s exists, is non-empty, and parses as valid JSON', (fileName) => {
    const fullPath = path.join(DATA_DIR, fileName);
    expect(fs.existsSync(fullPath), `Missing data file: ${fullPath}`).toBe(true);
    expect(fs.statSync(fullPath).size, `${fileName} is empty`).toBeGreaterThan(10);
    const raw = fs.readFileSync(fullPath, 'utf-8');
    expect(() => JSON.parse(raw)).not.toThrow();
    expect(raw).not.toMatch(/:\s*NaN\b/);
    expect(raw).not.toMatch(/:\s*-?Infinity\b/);
    expect(raw).not.toMatch(/:\s*"NA"/);
  });

  it('public/data contains no orphaned top-level .json files that no route consumes', () => {
    const onDisk = fs.readdirSync(DATA_DIR).filter((f) => f.endsWith('.json'));
    const expected = new Set<string>(EXPECTED_DATA_FILES);
    const orphans = onDisk.filter((f) => !expected.has(f));
    expect(orphans, `Orphan data files: ${orphans.join(', ')}`).toEqual([]);
  });
});

describe('Strict Zod schema contracts against public/data/*.json', () => {
  const d = loadAllDatasets();

  it('projections_season_teams.json (30 teams) matches TeamProjectionSchema', () => {
    expect(d.teams).toHaveLength(LEAGUE.TEAM_COUNT);
    assertValid(z.array(TeamProjectionSchema), d.teams, 'projections_season_teams.json');
  });

  it('projections_season_players.json (330 players) matches PlayerProjectionSchema', () => {
    expect(d.players).toHaveLength(LEAGUE.ACTIVE_PLAYER_POOL);
    assertValid(z.array(PlayerProjectionSchema), d.players, 'projections_season_players.json');
  });

  it('projections_models_metadata.json matches ModelMetadataSchema', () => {
    assertValid(ModelMetadataSchema, d.metadata, 'projections_models_metadata.json');
  });

  it('projections_diagnostics.json matches ModelDiagnosticsSchema', () => {
    assertValid(ModelDiagnosticsSchema, d.diagnostics, 'projections_diagnostics.json');
  });

  it('cba_cap_sheet.json matches CbaLeagueOverviewSchema', () => {
    assertValid(CbaLeagueOverviewSchema, d.cbaCapSheet, 'cba_cap_sheet.json');
  });

  it('clutch_leverage_metrics.json matches ClutchProfileSchema', () => {
    expect(d.clutch).toHaveLength(LEAGUE.ACTIVE_PLAYER_POOL);
    assertValid(z.array(ClutchProfileSchema), d.clutch, 'clutch_leverage_metrics.json');
  });

  it('coaching_metrics.json (30 staffs) matches CoachingStaffMetricSchema', () => {
    expect(d.coaches).toHaveLength(LEAGUE.TEAM_COUNT);
    assertValid(z.array(CoachingStaffMetricSchema), d.coaches, 'coaching_metrics.json');
  });

  it('defensive_metrics.json matches DefensiveProfileSchema', () => {
    expect(d.defense).toHaveLength(LEAGUE.ACTIVE_PLAYER_POOL);
    assertValid(z.array(DefensiveProfileSchema), d.defense, 'defensive_metrics.json');
  });

  it('player_dna_profiles.json matches PlayerDnaProfileSchema', () => {
    expect(d.playerDna).toHaveLength(LEAGUE.ACTIVE_PLAYER_POOL);
    assertValid(z.array(PlayerDnaProfileSchema), d.playerDna, 'player_dna_profiles.json');
  });

  it('offseason_draft.json (60 picks) matches RookieDraftProfileSchema', () => {
    expect(d.offseasonDraft).toHaveLength(LEAGUE.DRAFT_PICKS);
    assertValid(z.array(RookieDraftProfileSchema), d.offseasonDraft, 'offseason_draft.json');
  });

  it('offseason_teams.json (30 teams) matches TeamOffseasonProfileSchema', () => {
    expect(d.offseasonTeams).toHaveLength(LEAGUE.TEAM_COUNT);
    assertValid(z.array(TeamOffseasonProfileSchema), d.offseasonTeams, 'offseason_teams.json');
  });

  it('offseason_transactions.json matches OffseasonTransactionSchema', () => {
    expect(d.offseasonTransactions.length).toBeGreaterThanOrEqual(183);
    assertValid(z.array(OffseasonTransactionSchema), d.offseasonTransactions, 'offseason_transactions.json');
  });

  it('playoff_series_matchups.json matches PlayoffMatchupsCatalogSchema', () => {
    assertValid(PlayoffMatchupsCatalogSchema, d.playoffSeries, 'playoff_series_matchups.json');
  });

  it('shots_index.json matches PlayerCatalogEntrySchema', () => {
    expect(d.shotsIndex.length).toBeGreaterThanOrEqual(200);
    assertValid(z.array(PlayerCatalogEntrySchema), d.shotsIndex, 'shots_index.json');
  });

  it('shots_metadata.json matches ShotsMetadataSchema', () => {
    assertValid(ShotsMetadataSchema, d.shotsMetadata, 'shots_metadata.json');
  });

  it('every public/data/shots/<player_id>.json file matches PlayerShotDataSchema', () => {
    expect(fs.existsSync(SHOTS_DIR)).toBe(true);
    const failures: string[] = [];
    for (const entry of d.shotsIndex) {
      const result = PlayerShotDataSchema.safeParse(readPlayerShotFile(entry.player_id));
      if (!result.success) {
        failures.push(`shots/${entry.player_id}.json (${entry.player_name}):\n${formatIssues(result.error.issues, 3)}`);
      }
    }
    expect(failures, failures.slice(0, 5).join('\n')).toEqual([]);
  });
});
