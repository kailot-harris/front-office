/**
 * Layer 1 — every dataset exists, parses, and satisfies its strict schema.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import {
  DATA_DIR,
  MATCHUPS_DIR,
  EXPECTED_DATA_FILES,
  OPTIONAL_DATA_FILES,
  LEAGUE,
  loadAllDatasets,
  readMatchupWeekFile,
} from '../helpers/datasets';
import {
  TeamProjectionSchema,
  PlayerProjectionSchema,
  ModelMetadataSchema,
  ModelDiagnosticsSchema,
  PostseasonOpsDataSchema,
  CbtLeagueOverviewSchema,
  ClutchCatalogSchema,
  PlayerDnaCatalogSchema,
  PlayoffMatchupsCatalogSchema,
  MatchupsIndexSchema,
  MatchupSchema,
  WorldSeriesDataSchema,
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

  it('public/data contains no undocumented top-level .json files', () => {
    const onDisk = fs.readdirSync(DATA_DIR).filter((f) => f.endsWith('.json'));
    const allowed = new Set<string>([...EXPECTED_DATA_FILES, ...OPTIONAL_DATA_FILES]);
    const orphans = onDisk.filter((f) => !allowed.has(f));
    expect(orphans, `Orphan data files: ${orphans.join(', ')}`).toEqual([]);
  });
});

describe('Strict Zod schema contracts against public/data/*.json', () => {
  const d = loadAllDatasets();

  it('projections_season_teams.json (30 teams) matches TeamProjectionSchema', () => {
    expect(d.teams).toHaveLength(LEAGUE.TEAM_COUNT);
    assertValid(z.array(TeamProjectionSchema), d.teams, 'projections_season_teams.json');
  });

  it('projections_season_players.json matches PlayerProjectionSchema', () => {
    expect(d.players.length).toBeGreaterThan(500);
    assertValid(z.array(PlayerProjectionSchema), d.players, 'projections_season_players.json');
  });

  it('projections_models_metadata.json matches ModelMetadataSchema', () => {
    assertValid(ModelMetadataSchema, d.metadata, 'projections_models_metadata.json');
  });

  it('projections_diagnostics.json matches ModelDiagnosticsSchema', () => {
    assertValid(ModelDiagnosticsSchema, d.diagnostics, 'projections_diagnostics.json');
  });

  it('projections_postseason_ops.json matches PostseasonOpsDataSchema', () => {
    assertValid(PostseasonOpsDataSchema, d.postseasonOps, 'projections_postseason_ops.json');
  });

  it('cbt_payroll_sheet.json matches CbtLeagueOverviewSchema', () => {
    assertValid(CbtLeagueOverviewSchema, d.cbtSheet, 'cbt_payroll_sheet.json');
  });

  it('clutch_leverage_metrics.json matches ClutchCatalogSchema', () => {
    assertValid(ClutchCatalogSchema, d.clutch, 'clutch_leverage_metrics.json');
  });

  it('player_dna_profiles.json matches PlayerDnaCatalogSchema', () => {
    assertValid(PlayerDnaCatalogSchema, d.playerDna, 'player_dna_profiles.json');
  });

  it('playoff_series_matchups.json matches PlayoffMatchupsCatalogSchema', () => {
    assertValid(PlayoffMatchupsCatalogSchema, d.playoffSeries, 'playoff_series_matchups.json');
  });

  it('matchups_index.json matches MatchupsIndexSchema', () => {
    assertValid(MatchupsIndexSchema, d.matchupsIndex, 'matchups_index.json');
  });

  it('every matchups/week-NN.json file matches MatchupSchema[] and agrees with matchups_index.json', () => {
    expect(fs.existsSync(MATCHUPS_DIR)).toBe(true);
    for (const slate of d.matchupsIndex.available_weeks) {
      const games = readMatchupWeekFile(slate.week);
      expect(games, `week-${slate.week} game count`).toHaveLength(slate.game_count);
      assertValid(z.array(MatchupSchema), games, `matchups/week-${String(slate.week).padStart(2, '0')}.json`);
    }
  });

  it('world_series.json matches WorldSeriesDataSchema', () => {
    assertValid(WorldSeriesDataSchema, d.worldSeries, 'world_series.json');
  });
});
