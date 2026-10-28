import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { WEB_ROOT, readJsonFile } from '../helpers/datasets';

function extractInterfaceFields(relFilePath: string, interfaceName: string): Set<string> {
  const src = fs.readFileSync(path.join(WEB_ROOT, relFilePath), 'utf-8');
  const startRegex = new RegExp(`export interface ${interfaceName}\\s*\\{`);
  const match = startRegex.exec(src);
  if (!match) {
    throw new Error(`Interface ${interfaceName} not found in ${relFilePath}`);
  }
  const startIdx = match.index + match[0].length;
  let depth = 1;
  let idx = startIdx;
  let topLevelLines = '';

  while (idx < src.length && depth > 0) {
    const ch = src[idx];
    if (ch === '{') {
      depth++;
    } else if (ch === '}') {
      depth--;
    } else if (depth === 1) {
      topLevelLines += ch;
    }
    idx++;
  }

  const fields = new Set<string>();
  for (const line of topLevelLines.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
      continue;
    }
    const fieldMatch = trimmed.match(/^([a-zA-Z0-9_]+)\??\s*:/);
    if (fieldMatch) {
      fields.add(fieldMatch[1]);
    }
  }
  return fields;
}

function collectJsonKeys(rows: Record<string, unknown>[]): Set<string> {
  const keys = new Set<string>();
  for (const r of rows) {
    for (const k of Object.keys(r)) {
      keys.add(k);
    }
  }
  return keys;
}

describe('TypeScript interface vs JSON payload key parity', () => {
  const arrayCases: Array<{
    file: Parameters<typeof readJsonFile>[0];
    tsFile: string;
    interfaceName: string;
    optionalFields?: string[];
  }> = [
    {
      file: 'projections_season_teams.json',
      tsFile: 'lib/types.ts',
      interfaceName: 'TeamProjection',
      optionalFields: ['rank'],
    },
    {
      file: 'projections_season_players.json',
      tsFile: 'lib/types.ts',
      interfaceName: 'PlayerProjection',
    },
    {
      file: 'clutch_leverage_metrics.json',
      tsFile: 'lib/clutchTypes.ts',
      interfaceName: 'ClutchProfile',
    },
    {
      file: 'coaching_metrics.json',
      tsFile: 'lib/coachingTypes.ts',
      interfaceName: 'CoachingStaffMetric',
      optionalFields: ['season'],
    },
    {
      file: 'defensive_metrics.json',
      tsFile: 'lib/defenseTypes.ts',
      interfaceName: 'DefensiveProfile',
    },
    {
      file: 'player_dna_profiles.json',
      tsFile: 'lib/playerDnaTypes.ts',
      interfaceName: 'PlayerDnaProfile',
    },
    {
      file: 'offseason_draft.json',
      tsFile: 'lib/offseasonTypes.ts',
      interfaceName: 'OffseasonDraftProspect',
      optionalFields: ['trade_note'],
    },
    {
      file: 'offseason_teams.json',
      tsFile: 'lib/offseasonTypes.ts',
      interfaceName: 'OffseasonTeamProfile',
    },
    {
      file: 'offseason_transactions.json',
      tsFile: 'lib/offseasonTypes.ts',
      interfaceName: 'OffseasonTransaction',
      optionalFields: ['trade_details'],
    },
    {
      file: 'shots_index.json',
      tsFile: 'lib/shotTypes.ts',
      interfaceName: 'PlayerCatalogEntry',
    },
  ];

  it.each(arrayCases)(
    '$interfaceName ($tsFile) matches keys in $file without undocumented or missing fields',
    ({ file, tsFile, interfaceName, optionalFields = [] }) => {
      const tsFields = extractInterfaceFields(tsFile, interfaceName);
      const rows = readJsonFile<Record<string, unknown>[]>(file);
      const jsonKeys = collectJsonKeys(rows);

      const missingInJson = [...tsFields].filter(
        (f) => !optionalFields.includes(f) && !jsonKeys.has(f)
      );
      const undocumentedInTs = [...jsonKeys].filter((k) => !tsFields.has(k));

      expect(
        missingInJson,
        `${interfaceName} declares fields missing from ${file}: ${missingInJson.join(', ')}`
      ).toEqual([]);
      expect(
        undocumentedInTs,
        `${file} ships keys not declared on ${interfaceName} in ${tsFile}: ${undocumentedInTs.join(', ')}`
      ).toEqual([]);
    }
  );

  const objectCases: Array<{
    file: Parameters<typeof readJsonFile>[0];
    tsFile: string;
    interfaceName: string;
    optionalFields?: string[];
  }> = [
    {
      file: 'projections_models_metadata.json',
      tsFile: 'lib/types.ts',
      interfaceName: 'ModelMetadata',
    },
    {
      file: 'projections_diagnostics.json',
      tsFile: 'lib/types.ts',
      interfaceName: 'ModelDiagnostics',
      optionalFields: ['generated_at'],
    },
    {
      file: 'cba_cap_sheet.json',
      tsFile: 'lib/cbaTypes.ts',
      interfaceName: 'WnbaCbaLeagueOverview',
      optionalFields: ['generated_at'],
    },
    {
      file: 'playoff_series_matchups.json',
      tsFile: 'lib/playoffTypes.ts',
      interfaceName: 'PlayoffMatchupsCatalog',
      optionalFields: ['updatedAt', 'season', 'generated_at'],
    },
    {
      file: 'playoff_bracket_2026.json',
      tsFile: 'lib/playoffTypes.ts',
      interfaceName: 'PlayoffBracketSeason',
      optionalFields: ['generated_at'],
    },
    {
      file: 'finals_game_predictions_2026.json',
      tsFile: 'lib/playoffTypes.ts',
      interfaceName: 'FinalsGamePredictionSet',
      optionalFields: ['generated_at'],
    },
    {
      file: 'finals_series_backtest_2026.json',
      tsFile: 'lib/playoffTypes.ts',
      interfaceName: 'FinalsSeriesBacktestSet',
      optionalFields: ['generated_at'],
    },
    {
      file: 'shots_metadata.json',
      tsFile: 'lib/shotTypes.ts',
      interfaceName: 'ShotsMetadata',
      optionalFields: ['generated_at'],
    },
  ];

  it.each(objectCases)(
    '$interfaceName ($tsFile) matches top-level keys in $file',
    ({ file, tsFile, interfaceName, optionalFields = [] }) => {
      const tsFields = extractInterfaceFields(tsFile, interfaceName);
      const obj = readJsonFile<Record<string, unknown>>(file);
      const jsonKeys = new Set(Object.keys(obj));

      const missingInJson = [...tsFields].filter(
        (f) => !optionalFields.includes(f) && !jsonKeys.has(f)
      );
      const undocumentedInTs = [...jsonKeys].filter((k) => !tsFields.has(k));

      expect(
        missingInJson,
        `${interfaceName} declares fields missing from ${file}: ${missingInJson.join(', ')}`
      ).toEqual([]);
      expect(
        undocumentedInTs,
        `${file} ships keys not declared on ${interfaceName} in ${tsFile}: ${undocumentedInTs.join(', ')}`
      ).toEqual([]);
    }
  );
});

/**
 * playoff_bracket_2026.json is an object whose payload lives in a nested array,
 * so the arrayCases runner above (which needs an array at the file root) cannot
 * reach it and the objectCases runner only checks the four top-level keys. These
 * cases walk the nested interfaces explicitly, which is where the R writer and
 * the TypeScript interface would otherwise be free to drift.
 */
describe('PlayoffBracketSeason nested interface vs JSON key parity', () => {
  const bracket = readJsonFile<{
    series: Array<Record<string, unknown> & { prediction: Record<string, unknown> }>;
  }>('playoff_bracket_2026.json');

  const assertParity = (
    interfaceName: string,
    rows: Record<string, unknown>[],
    optionalFields: string[] = []
  ) => {
    expect(rows.length, `no rows to check for ${interfaceName}`).toBeGreaterThan(0);
    const tsFields = extractInterfaceFields('lib/playoffTypes.ts', interfaceName);
    const jsonKeys = collectJsonKeys(rows);

    const missingInJson = [...tsFields].filter(
      (f) => !optionalFields.includes(f) && !jsonKeys.has(f)
    );
    const undocumentedInTs = [...jsonKeys].filter((k) => !tsFields.has(k));

    expect(
      missingInJson,
      `${interfaceName} declares fields missing from playoff_bracket_2026.json: ${missingInJson.join(', ')}`
    ).toEqual([]);
    expect(
      undocumentedInTs,
      `playoff_bracket_2026.json ships keys not declared on ${interfaceName}: ${undocumentedInTs.join(', ')}`
    ).toEqual([]);
  };

  it('BracketSeries matches the keys of every series row', () => {
    assertParity('BracketSeries', bracket.series);
  });

  it('BracketPrediction matches the keys of every prediction block', () => {
    assertParity(
      'BracketPrediction',
      bracket.series.map((s) => s.prediction)
    );
  });

  it('BracketForecast matches the keys of every non-null forecast', () => {
    const forecasts = bracket.series
      .map((s) => s.prediction.forecast as Record<string, unknown> | null)
      .filter((f): f is Record<string, unknown> => f !== null);
    assertParity('BracketForecast', forecasts);
  });

  it('BracketLengthProb matches the keys of every length-distribution point', () => {
    const points = bracket.series
      .map((s) => s.prediction.forecast as { lengthDistribution?: Record<string, unknown>[] } | null)
      .filter((f): f is { lengthDistribution: Record<string, unknown>[] } => f !== null)
      .flatMap((f) => f.lengthDistribution);
    assertParity('BracketLengthProb', points);
  });
});

/**
 * finals_game_predictions_2026.json has the same shape problem as the bracket
 * payload: the objectCases runner above only reaches its ten top-level keys, and
 * the interesting fields -- the 25 per-game ones the R writer emits -- live in a
 * nested array. These walk the nested interfaces explicitly, which is the only
 * thing stopping build_finals_game_predictions.R and playoffTypes.ts from drifting
 * apart silently (GitHub issue #94).
 */
describe('FinalsGamePredictionSet nested interface vs JSON key parity', () => {
  const finals = readJsonFile<{
    matchup: Record<string, unknown> | null;
    games: Array<Record<string, unknown>>;
    lengthDistribution: Array<Record<string, unknown>>;
  }>('finals_game_predictions_2026.json');

  const assertParity = (
    interfaceName: string,
    rows: Record<string, unknown>[],
    optionalFields: string[] = []
  ) => {
    expect(rows.length, `no rows to check for ${interfaceName}`).toBeGreaterThan(0);
    const tsFields = extractInterfaceFields('lib/playoffTypes.ts', interfaceName);
    const jsonKeys = collectJsonKeys(rows);

    const missingInJson = [...tsFields].filter(
      (f) => !optionalFields.includes(f) && !jsonKeys.has(f)
    );
    const undocumentedInTs = [...jsonKeys].filter((k) => !tsFields.has(k));

    expect(
      missingInJson,
      `${interfaceName} declares fields missing from finals_game_predictions_2026.json: ${missingInJson.join(', ')}`
    ).toEqual([]);
    expect(
      undocumentedInTs,
      `finals_game_predictions_2026.json ships keys not declared on ${interfaceName}: ${undocumentedInTs.join(', ')}`
    ).toEqual([]);
  };

  it('FinalsGamePrediction matches the keys of every game row', () => {
    // An empty-state payload has no games to check, which is a legitimate state
    // rather than a failure; it is covered by the schema and invariant specs.
    if (finals.games.length === 0) {
      expect(finals.matchup).toBeNull();
      return;
    }
    assertParity('FinalsGamePrediction', finals.games);
  });

  it('FinalsMatchup matches the keys of the matchup block', () => {
    if (finals.matchup === null) {
      expect(finals.games).toHaveLength(0);
      return;
    }
    assertParity('FinalsMatchup', [finals.matchup]);
  });

  it('BracketLengthProb matches the keys of every Finals length-distribution point', () => {
    if (finals.lengthDistribution.length === 0) {
      expect(finals.matchup).toBeNull();
      return;
    }
    assertParity('BracketLengthProb', finals.lengthDistribution);
  });
});

// matchups_slates.json is an OBJECT payload with nested arrays, not a flat
// array, so it cannot go through arrayCases above. Each interface is checked
// against the keys of the corresponding node.
//
// Key parity is a real contract here rather than a formality: the builder emits
// an explicit null for every absent value instead of omitting the key, so a key
// missing from the JSON means the field was genuinely dropped, not merely empty.
describe('TypeScript interface vs JSON payload key parity: matchups_slates.json', () => {
  const payload = readJsonFile<Record<string, unknown>>('matchups_slates.json');

  const assertParity = (
    interfaceName: string,
    rows: Record<string, unknown>[],
    optionalFields: string[] = []
  ) => {
    const tsFields = extractInterfaceFields('lib/matchupTypes.ts', interfaceName);
    const jsonKeys = collectJsonKeys(rows);

    const missingInJson = [...tsFields].filter(
      (f) => !optionalFields.includes(f) && !jsonKeys.has(f)
    );
    const undocumentedInTs = [...jsonKeys].filter((k) => !tsFields.has(k));

    expect(
      missingInJson,
      `${interfaceName} declares fields missing from matchups_slates.json: ${missingInJson.join(', ')}`
    ).toEqual([]);
    expect(
      undocumentedInTs,
      `matchups_slates.json ships keys not declared on ${interfaceName}: ${undocumentedInTs.join(', ')}`
    ).toEqual([]);
  };

  it('MatchupsPayload matches the top-level keys', () => {
    assertParity('MatchupsPayload', [payload]);
  });

  it('Matchup matches the keys of every game row', () => {
    assertParity('Matchup', payload.matchups as Record<string, unknown>[]);
  });

  it('MatchupWeek matches the keys of every week row', () => {
    assertParity('MatchupWeek', payload.weeks as Record<string, unknown>[]);
  });

  it('MatchupSummary matches the keys of the summary block', () => {
    assertParity('MatchupSummary', [payload.summary as Record<string, unknown>]);
  });

  it('MatchupProvenance matches the keys of the provenance block', () => {
    assertParity('MatchupProvenance', [payload.provenance as Record<string, unknown>]);
  });
});
