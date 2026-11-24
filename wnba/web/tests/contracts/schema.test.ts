import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import {
  DATA_DIR,
  SHOTS_DIR,
  EXPECTED_DATA_FILES,
  listTopLevelDataFiles,
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
  FinalsSeriesBacktestSetSchema,
  MatchupsPayloadSchema,
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

describe('No orphan top-level data files', () => {
  it('every top-level public/data/*.json (except data_manifest.json) is in EXPECTED_DATA_FILES', () => {
    const expected = new Set<string>(EXPECTED_DATA_FILES);
    const orphans = listTopLevelDataFiles().filter((f) => !expected.has(f));
    expect(orphans, `Unregistered data files: ${orphans.join(', ')}`).toEqual([]);
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

  it('finals_series_backtest_2026.json matches FinalsSeriesBacktestSetSchema', () => {
    assertValid(
      FinalsSeriesBacktestSetSchema,
      d.finalsSeriesBacktest,
      'finals_series_backtest_2026.json'
    );
  });

  it('shots_index.json matches PlayerCatalogEntrySchema', () => {
    expect(d.shotsIndex.length).toBeGreaterThanOrEqual(150);
    assertValid(z.array(PlayerCatalogEntrySchema), d.shotsIndex, 'shots_index.json');
  });

  it('shots_metadata.json matches ShotsMetadataSchema', () => {
    assertValid(ShotsMetadataSchema, d.shotsMetadata, 'shots_metadata.json');
  });

  it('matchups_slates.json matches MatchupsPayloadSchema', () => {
    assertValid(MatchupsPayloadSchema, d.matchups, 'matchups_slates.json');
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

// The infoSets count rule depends on whether the series is decided: one set per
// decision point means games + 1 while it is live, and exactly games once a team
// has 4 wins (nothing is left to forecast after the deciding game). Fixtures are
// derived from the shipped payload so every other refine still holds.
describe('FinalsSeriesBacktestSetSchema infoSets count vs series state', () => {
  type Backtest = z.infer<typeof FinalsSeriesBacktestSetSchema>;
  const base = loadAllDatasets().finalsSeriesBacktest as Backtest;
  const COUNT_MSG = 'infoSets must number one more than the games played';
  const clone = (): Backtest => JSON.parse(JSON.stringify(base));
  const countIssue = (p: Backtest) => {
    const r = FinalsSeriesBacktestSetSchema.safeParse(p);
    return !r.success && r.error.issues.some((i) => i.message.startsWith(COUNT_MSG));
  };
  const wins = (p: Backtest) => {
    const high = p.games.filter((g) => g.highWon).length;
    return { high, low: p.games.length - high };
  };
  // The first k games of the real series, chosen so neither team has 4 wins yet.
  const undecided = (k: number): Backtest => {
    const p = clone();
    p.games = p.games.slice(0, k);
    p.infoSets = p.infoSets.slice(0, k + 1);
    return p;
  };

  it('fixture sanity: the shipped series is decided, its 4-game prefix is not', () => {
    const w = wins(base);
    expect(Math.max(w.high, w.low)).toBe(4);
    const u = wins(undecided(4));
    expect(Math.max(u.high, u.low)).toBeLessThan(4);
  });

  it('undecided series requires games + 1 information sets', () => {
    const ok = undecided(4);
    expect(ok.infoSets.length).toBe(ok.games.length + 1);
    expect(FinalsSeriesBacktestSetSchema.safeParse(ok).success).toBe(true);

    const short = undecided(4);
    short.infoSets = short.infoSets.slice(0, short.games.length);
    expect(countIssue(short)).toBe(true);
  });

  it('decided series accepts exactly games information sets', () => {
    const p = clone();
    expect(p.infoSets.length).toBe(p.games.length);
    expect(FinalsSeriesBacktestSetSchema.safeParse(p).success).toBe(true);
  });

  it('decided series rejects games + 1 and games - 1 information sets', () => {
    const plus = clone();
    plus.infoSets = [...plus.infoSets, { ...plus.infoSets[plus.infoSets.length - 1] }];
    expect(plus.infoSets.length).toBe(plus.games.length + 1);
    expect(countIssue(plus)).toBe(true);

    const minus = clone();
    minus.infoSets = minus.infoSets.slice(0, minus.games.length - 1);
    expect(countIssue(minus)).toBe(true);
  });
});
