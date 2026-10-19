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
    },
    {
      file: 'cba_cap_sheet.json',
      tsFile: 'lib/cbaTypes.ts',
      interfaceName: 'WnbaCbaLeagueOverview',
    },
    {
      file: 'playoff_series_matchups.json',
      tsFile: 'lib/playoffTypes.ts',
      interfaceName: 'PlayoffMatchupsCatalog',
      optionalFields: ['updatedAt', 'season'],
    },
    {
      file: 'shots_metadata.json',
      tsFile: 'lib/shotTypes.ts',
      interfaceName: 'ShotsMetadata',
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
