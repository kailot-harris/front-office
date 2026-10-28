/**
 * Layer 1b — TypeScript interface vs JSON payload key parity.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { WEB_ROOT, readJsonFile, type DataFileName } from '../helpers/datasets';

const readSrc = (rel: string) => fs.readFileSync(path.join(WEB_ROOT, rel), 'utf-8');

function extractInterfaceFields(relFile: string, name: string): { all: Set<string>; optional: Set<string> } {
  const src = readSrc(relFile);
  const m = new RegExp(`export interface ${name}\\s*\\{`).exec(src);
  if (!m) throw new Error(`Interface ${name} not found in ${relFile}`);
  let depth = 1;
  let i = m.index + m[0].length;
  let top = '';
  while (i < src.length && depth > 0) {
    const ch = src[i];
    if (ch === '{') depth++;
    else if (ch === '}') depth--;
    else if (depth === 1) top += ch;
    i++;
  }
  const all = new Set<string>();
  const optional = new Set<string>();
  for (const line of top.split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('//') || t.startsWith('/*') || t.startsWith('*')) continue;
    const f = t.match(/^([A-Za-z0-9_]+)(\?)?\s*:/);
    if (f) {
      all.add(f[1]);
      if (f[2]) optional.add(f[1]);
    }
  }
  return { all, optional };
}

const keysOf = (rows: Record<string, unknown>[]) => {
  const s = new Set<string>();
  for (const r of rows) for (const k of Object.keys(r)) s.add(k);
  return s;
};

interface ParityCase {
  file: DataFileName;
  tsFile: string;
  iface: string;
  pick?: (json: unknown) => Record<string, unknown>[];
}

const parityCases: ParityCase[] = [
  { file: 'projections_season_teams.json', tsFile: 'lib/types.ts', iface: 'TeamProjection' },
  { file: 'projections_season_players.json', tsFile: 'lib/types.ts', iface: 'PlayerProjection' },
  { file: 'projections_models_metadata.json', tsFile: 'lib/types.ts', iface: 'ModelMetadata', pick: (j) => [j as Record<string, unknown>] },
  { file: 'projections_diagnostics.json', tsFile: 'lib/types.ts', iface: 'ModelDiagnostics', pick: (j) => [j as Record<string, unknown>] },
  { file: 'projections_postseason_ops.json', tsFile: 'lib/types.ts', iface: 'PostseasonOpsData', pick: (j) => [j as Record<string, unknown>] },
  {
    file: 'projections_postseason_ops.json',
    tsFile: 'lib/types.ts',
    iface: 'PostseasonBracketTeam',
    pick: (j) => (j as { bracket: Record<string, unknown>[] }).bracket,
  },
  {
    file: 'projections_postseason_ops.json',
    tsFile: 'lib/types.ts',
    iface: 'BullpenStatusRow',
    pick: (j) => (j as { bullpen_status: Record<string, unknown>[] }).bullpen_status,
  },
  { file: 'cbt_payroll_sheet.json', tsFile: 'lib/cbtTypes.ts', iface: 'CbtLeagueOverview', pick: (j) => [j as Record<string, unknown>] },
  {
    file: 'cbt_payroll_sheet.json',
    tsFile: 'lib/cbtTypes.ts',
    iface: 'FranchiseCbtProfile',
    pick: (j) => (j as { teams: Record<string, unknown>[] }).teams,
  },
  {
    file: 'cbt_payroll_sheet.json',
    tsFile: 'lib/cbtTypes.ts',
    iface: 'MlbPlayerContract',
    pick: (j) => (j as { teams: { contracts: Record<string, unknown>[] }[] }).teams.flatMap((t) => t.contracts),
  },
  { file: 'clutch_leverage_metrics.json', tsFile: 'lib/clutchTypes.ts', iface: 'ClutchCatalog', pick: (j) => [j as Record<string, unknown>] },
  {
    file: 'clutch_leverage_metrics.json',
    tsFile: 'lib/clutchTypes.ts',
    iface: 'ClutchProfile',
    pick: (j) => (j as { profiles: Record<string, unknown>[] }).profiles,
  },
  { file: 'player_dna_profiles.json', tsFile: 'lib/playerDnaTypes.ts', iface: 'PlayerDnaCatalog', pick: (j) => [j as Record<string, unknown>] },
  {
    file: 'player_dna_profiles.json',
    tsFile: 'lib/playerDnaTypes.ts',
    iface: 'PlayerDnaProfile',
    pick: (j) => (j as { profiles: Record<string, unknown>[] }).profiles,
  },
  { file: 'playoff_series_matchups.json', tsFile: 'lib/playoffTypes.ts', iface: 'PlayoffMatchupsCatalog', pick: (j) => [j as Record<string, unknown>] },
  {
    file: 'playoff_series_matchups.json',
    tsFile: 'lib/playoffTypes.ts',
    iface: 'TeamPlayoffProfile',
    pick: (j) => Object.values((j as { teams: Record<string, Record<string, unknown>> }).teams),
  },
  { file: 'matchups_index.json', tsFile: 'lib/matchupTypes.ts', iface: 'MatchupsIndex', pick: (j) => [j as Record<string, unknown>] },
  {
    file: 'matchups_index.json',
    tsFile: 'lib/matchupTypes.ts',
    iface: 'MatchupSlate',
    pick: (j) => (j as { available_weeks: Record<string, unknown>[] }).available_weeks,
  },
  { file: 'world_series.json', tsFile: 'lib/types.ts', iface: 'WorldSeriesData', pick: (j) => [j as Record<string, unknown>] },
  {
    file: 'world_series.json',
    tsFile: 'lib/types.ts',
    iface: 'WorldSeriesGame',
    pick: (j) => (j as { games: Record<string, unknown>[] }).games,
  },
];

describe('TypeScript interface vs JSON payload key parity', () => {
  it.each(parityCases)('$iface ($tsFile) matches keys in $file', ({ file, tsFile, iface, pick }) => {
    const { all, optional } = extractInterfaceFields(tsFile, iface);
    const json = readJsonFile<unknown>(file);
    const rows = pick ? pick(json) : (json as Record<string, unknown>[]);
    const jsonKeys = keysOf(rows);

    const missingInJson = [...all].filter((f) => !optional.has(f) && !jsonKeys.has(f));
    const undocumented = [...jsonKeys].filter((k) => !all.has(k));

    expect(missingInJson, `${iface} declares required fields absent from ${file}: ${missingInJson.join(', ')}`).toEqual([]);
    expect(undocumented, `${file} ships keys not declared on ${iface} in ${tsFile}: ${undocumented.join(', ')}`).toEqual([]);
  });
});
