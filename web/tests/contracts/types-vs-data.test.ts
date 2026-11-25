/**
 * Layer 1b — "type truth".
 *
 * lib/*Types.ts is what the components believe about the data, but every
 * loader does `JSON.parse(...) as T`, so nothing enforces it. This suite parses
 * the TypeScript source itself and checks it against the JSON that ships:
 *
 *   (a) interface field parity  — no undocumented keys, no phantom fields
 *   (b) string-literal unions   — every distinct value in the data is declared
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import {
  WEB_ROOT,
  listGameDetailIds,
  readGameDetailFile,
  readJsonFile,
  type DataFileName,
} from '../helpers/datasets';

const readSrc = (rel: string) => fs.readFileSync(path.join(WEB_ROOT, rel), 'utf-8');

/** Top-level field names of `export interface Name { ... }`. */
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

/** String literals of `export type Name = 'a' | 'b';` */
function extractTypeAliasUnion(relFile: string, name: string): string[] {
  const src = readSrc(relFile);
  const m = new RegExp(`export type ${name}\\s*=([^;]+);`).exec(src);
  if (!m) throw new Error(`type ${name} not found in ${relFile}`);
  return [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
}

/** String literals of an inline union field: `field: 'a' | 'b';` inside an interface. */
function extractFieldUnion(relFile: string, iface: string, field: string): string[] {
  const src = readSrc(relFile);
  const start = src.indexOf(`export interface ${iface}`);
  if (start < 0) throw new Error(`Interface ${iface} not found in ${relFile}`);
  const body = src.slice(start);
  const m = new RegExp(`\\n\\s*${field}\\??\\s*:([^;]+);`).exec(body);
  if (!m) throw new Error(`${iface}.${field} not found in ${relFile}`);
  return [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
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
  /** Pluck the record(s) to compare from the file. */
  pick?: (json: unknown) => Record<string, unknown>[];
}

const parityCases: ParityCase[] = [
  { file: 'projections_season_teams.json', tsFile: 'lib/types.ts', iface: 'TeamProjection' },
  { file: 'projections_season_players.json', tsFile: 'lib/types.ts', iface: 'PlayerProjection' },
  { file: 'projections_models_metadata.json', tsFile: 'lib/types.ts', iface: 'ModelMetadata', pick: (j) => [j as Record<string, unknown>] },
  { file: 'projections_diagnostics.json', tsFile: 'lib/types.ts', iface: 'ModelDiagnostics', pick: (j) => [j as Record<string, unknown>] },
  { file: 'cba_cap_sheet.json', tsFile: 'lib/cbaTypes.ts', iface: 'CbaLeagueOverview', pick: (j) => [j as Record<string, unknown>] },
  { file: 'cba_cap_sheet.json', tsFile: 'lib/cbaTypes.ts', iface: 'FranchiseCbaProfile', pick: (j) => (j as { teams: Record<string, unknown>[] }).teams },
  {
    file: 'cba_cap_sheet.json',
    tsFile: 'lib/cbaTypes.ts',
    iface: 'PlayerContract',
    pick: (j) => (j as { teams: { contracts: Record<string, unknown>[] }[] }).teams.flatMap((t) => t.contracts),
  },
  { file: 'clutch_leverage_metrics.json', tsFile: 'lib/clutchTypes.ts', iface: 'ClutchProfile', pick: (j) => (j as { profiles: Record<string, unknown>[] }).profiles },
  {
    file: 'clutch_leverage_metrics.json',
    tsFile: 'lib/seasonWindow.ts',
    iface: 'SeasonWindow',
    pick: (j) => {
      const { profiles: _profiles, ...window } = j as Record<string, unknown>;
      return [window];
    },
  },
  { file: 'coaching_metrics.json', tsFile: 'lib/coachingTypes.ts', iface: 'CoachingStaffMetric' },
  { file: 'defensive_metrics.json', tsFile: 'lib/defenseTypes.ts', iface: 'DefensiveProfile', pick: (j) => (j as { profiles: Record<string, unknown>[] }).profiles },
  {
    file: 'defensive_metrics.json',
    tsFile: 'lib/seasonWindow.ts',
    iface: 'SeasonWindow',
    pick: (j) => {
      const { profiles: _profiles, ...window } = j as Record<string, unknown>;
      return [window];
    },
  },
  { file: 'player_dna_profiles.json', tsFile: 'lib/playerDnaTypes.ts', iface: 'PlayerDnaProfile', pick: (j) => (j as { profiles: Record<string, unknown>[] }).profiles },
  {
    file: 'player_dna_profiles.json',
    tsFile: 'lib/seasonWindow.ts',
    iface: 'SeasonWindow',
    pick: (j) => {
      const { profiles: _profiles, ...window } = j as Record<string, unknown>;
      return [window];
    },
  },
  { file: 'offseason_draft.json', tsFile: 'lib/offseasonTypes.ts', iface: 'RookieDraftProfile' },
  { file: 'offseason_teams.json', tsFile: 'lib/offseasonTypes.ts', iface: 'TeamOffseasonProfile' },
  { file: 'offseason_transactions.json', tsFile: 'lib/offseasonTypes.ts', iface: 'OffseasonTransaction' },
  { file: 'playoff_series_matchups.json', tsFile: 'lib/playoffTypes.ts', iface: 'PlayoffMatchupsCatalog', pick: (j) => [j as Record<string, unknown>] },
  {
    file: 'playoff_series_matchups.json',
    tsFile: 'lib/playoffTypes.ts',
    iface: 'TeamPlayoffProfile',
    pick: (j) => Object.values((j as { teams: Record<string, Record<string, unknown>> }).teams),
  },
  {
    file: 'playoff_series_matchups.json',
    tsFile: 'lib/playoffTypes.ts',
    iface: 'PlayoffSeriesMatchupResult',
    pick: (j) => (j as { sampleMatchups: Record<string, unknown>[] }).sampleMatchups,
  },
  { file: 'shots_index.json', tsFile: 'lib/shotTypes.ts', iface: 'PlayerCatalogEntry' },
  { file: 'shots_metadata.json', tsFile: 'lib/shotTypes.ts', iface: 'ShotsMetadata', pick: (j) => [j as Record<string, unknown>] },
  { file: 'matchups_slates.json', tsFile: 'lib/matchupTypes.ts', iface: 'MatchupsDataset', pick: (j) => [j as Record<string, unknown>] },
  {
    file: 'matchups_slates.json',
    tsFile: 'lib/matchupTypes.ts',
    iface: 'MatchupSlate',
    pick: (j) => (j as { slates: Record<string, unknown>[] }).slates,
  },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'MomentumMethodologyPayload', pick: (j) => [j as Record<string, unknown>] },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'StudyInfo', pick: (j) => [(j as { study: Record<string, unknown> }).study] },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'StudySeason', pick: (j) => (j as { study: { seasons: Record<string, unknown>[] } }).study.seasons },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'StudyTarget', pick: (j) => (j as { targets: Record<string, unknown>[] }).targets },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'StudyMeasure', pick: (j) => (j as { measures: Record<string, unknown>[] }).measures },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'StudySeries', pick: (j) => (j as { series: Record<string, unknown>[] }).series },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'SingleFeatureResult', pick: (j) => (j as { single_feature_results: Record<string, unknown>[] }).single_feature_results },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'SensitivityResult', pick: (j) => (j as { single_feature_sensitivity_primary: Record<string, unknown>[] }).single_feature_sensitivity_primary },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'StudyFamilies', pick: (j) => [(j as { families: Record<string, unknown> }).families] },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'CombinationSearch', pick: (j) => [(j as { combination_search: Record<string, unknown> }).combination_search] },
  {
    file: 'momentum_methodology.json',
    tsFile: 'lib/momentumMethodologyTypes.ts',
    iface: 'CombinationFold',
    pick: (j) => (j as { combination_search: { folds: Record<string, unknown>[] } }).combination_search.folds,
  },
  {
    file: 'momentum_methodology.json',
    tsFile: 'lib/momentumMethodologyTypes.ts',
    iface: 'SelectionStability',
    pick: (j) => [(j as { combination_search: { selection_stability: Record<string, unknown> } }).combination_search.selection_stability],
  },
  {
    file: 'momentum_methodology.json',
    tsFile: 'lib/momentumMethodologyTypes.ts',
    iface: 'CombinationSensitivity',
    pick: (j) => [(j as { combination_search: { sensitivity_without_2019_20_2020_21: Record<string, unknown> } }).combination_search.sensitivity_without_2019_20_2020_21],
  },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'BlendWindowResult', pick: (j) => (j as { blend_weights: Record<string, unknown>[] }).blend_weights },
  { file: 'momentum_methodology.json', tsFile: 'lib/momentumMethodologyTypes.ts', iface: 'StudyHoldout', pick: (j) => [(j as { holdout: Record<string, unknown> }).holdout] },
  {
    file: 'momentum_methodology.json',
    tsFile: 'lib/momentumMethodologyTypes.ts',
    iface: 'HoldoutCell',
    pick: (j) => {
      const h = (j as { holdout: { part_a: Record<string, Record<string, unknown>>; part_b: Record<string, Record<string, Record<string, unknown>>> } }).holdout;
      return [h.part_a.primary, h.part_a.next5, ...Object.values(h.part_b).flatMap((w) => Object.values(w))];
    },
  },
  {
    file: 'matchups_slates.json',
    tsFile: 'lib/matchupTypes.ts',
    iface: 'MatchupGame',
    pick: (j) => (j as { matchups: Record<string, unknown>[] }).matchups,
  },
  { file: 'leader_methodology.json', tsFile: 'lib/leaderMethodologyTypes.ts', iface: 'LeaderMethodologyPayload', pick: (j) => [j as Record<string, unknown>] },
  { file: 'leader_methodology.json', tsFile: 'lib/leaderMethodologyTypes.ts', iface: 'LeaderStudySettings', pick: (j) => [(j as { settings: Record<string, unknown> }).settings] },
  { file: 'leader_methodology.json', tsFile: 'lib/leaderMethodologyTypes.ts', iface: 'LeaderDataAuditRow', pick: (j) => (j as { data_audit: Record<string, unknown>[] }).data_audit },
  { file: 'leader_methodology.json', tsFile: 'lib/leaderMethodologyTypes.ts', iface: 'LeaderMethodologyMinimum', pick: (j) => (j as { minimums: Record<string, unknown>[] }).minimums },
  { file: 'leader_methodology.json', tsFile: 'lib/leaderMethodologyTypes.ts', iface: 'LeaderMinimumReliability', pick: (j) => (j as { minimums: { reliability: Record<string, unknown> }[] }).minimums.map((m) => m.reliability) },
  { file: 'leader_methodology.json', tsFile: 'lib/leaderMethodologyTypes.ts', iface: 'LeaderScalingExample', pick: (j) => [(j as { scaling_example: Record<string, unknown> }).scaling_example] },
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

  const gameDetails = listGameDetailIds().map((id) => readGameDetailFile(id) as unknown as Record<string, unknown>);
  const gameDetailCases: {
    iface: string;
    pick: (docs: Record<string, unknown>[]) => Record<string, unknown>[];
  }[] = [
    { iface: 'GameDetailEnvelope', pick: (docs) => docs },
    { iface: 'GameDetailPayload', pick: (docs) => docs.map((d) => d.data as Record<string, unknown>) },
    {
      iface: 'GameTeamSummary',
      pick: (docs) =>
        docs.flatMap((d) => {
          const p = d.data as Record<string, Record<string, unknown>>;
          return [p.away_team, p.home_team];
        }),
    },
    {
      iface: 'EfficiencyFactorItem',
      pick: (docs) =>
        docs.flatMap((d) => ((d.data as { efficiency_factors: Record<string, unknown>[] | null }).efficiency_factors ?? [])),
    },
    {
      iface: 'ContextSplitItem',
      pick: (docs) =>
        docs.flatMap((d) => ((d.data as { context_splits: Record<string, unknown>[] | null }).context_splits ?? [])),
    },
    {
      iface: 'TeamBoxTotals',
      pick: (docs) =>
        docs.flatMap((d) => {
          const bs = (d.data as { box_score: Record<string, unknown> | null }).box_score;
          return bs ? [bs.away_totals as Record<string, unknown>, bs.home_totals as Record<string, unknown>] : [];
        }),
    },
    {
      iface: 'PlayerBoxRow',
      pick: (docs) =>
        docs.flatMap((d) => {
          const bs = (d.data as { box_score: { away_players: Record<string, unknown>[]; home_players: Record<string, unknown>[] } | null }).box_score;
          return bs ? [...bs.away_players, ...bs.home_players] : [];
        }),
    },
    {
      iface: 'InactivePlayerRow',
      pick: (docs) =>
        docs.flatMap((d) => {
          const bs = (d.data as { box_score: { away_inactive: Record<string, unknown>[]; home_inactive: Record<string, unknown>[] } | null }).box_score;
          return bs ? [...bs.away_inactive, ...bs.home_inactive] : [];
        }),
    },
    {
      iface: 'TopPerformerItem',
      pick: (docs) =>
        docs.flatMap((d) => {
          const bs = (d.data as { box_score: { top_performers: Record<string, unknown>[] } | null }).box_score;
          return bs ? bs.top_performers : [];
        }),
    },
  ];

  it.each(gameDetailCases)('$iface (lib/gameDetailTypes.ts) matches keys in games/*.json', ({ iface, pick }) => {
    const { all, optional } = extractInterfaceFields('lib/gameDetailTypes.ts', iface);
    const rows = pick(gameDetails);
    expect(rows.length, `Expected at least one ${iface} row in games/*.json`).toBeGreaterThan(0);
    const jsonKeys = keysOf(rows);

    const missingInJson = [...all].filter((f) => !optional.has(f) && !jsonKeys.has(f));
    const undocumented = [...jsonKeys].filter((k) => !all.has(k));

    expect(missingInJson, `${iface} declares required fields absent from games/*.json: ${missingInJson.join(', ')}`).toEqual([]);
    expect(undocumented, `games/*.json ships keys not declared on ${iface} in lib/gameDetailTypes.ts: ${undocumented.join(', ')}`).toEqual([]);
  });
});

describe('String-literal unions in lib/*Types.ts cover every value in the data', () => {
  const d = {
    teams: readJsonFile<{ conference: string }[]>('projections_season_teams.json'),
    cba: readJsonFile<{ teams: { conference: string; cbaTier: string; contracts: { contractType: string }[] }[] }>('cba_cap_sheet.json'),
    tx: readJsonFile<{ type: string; impact_tier: string }[]>('offseason_transactions.json'),
    offTeams: readJsonFile<{ conference: string; grade: string }[]>('offseason_teams.json'),
    draft: readJsonFile<{ upside_tier: string }[]>('offseason_draft.json'),
    series: readJsonFile<{ teams: Record<string, { conference: string; rotation: { role: string }[] }> }>('playoff_series_matchups.json'),
    matchups: readJsonFile<{
      grading_state: string;
      slates: { status: string }[];
      matchups: { projection_basis: string | null }[];
    }>('matchups_slates.json'),
    methodology: readJsonFile<{
      single_feature_results: { verdict: string }[];
      single_feature_sensitivity_primary: { verdict: string }[];
    }>('momentum_methodology.json'),
  };

  const cases: { label: string; declared: () => string[]; values: () => string[] }[] = [
    { label: 'TeamProjection.conference', declared: () => extractFieldUnion('lib/types.ts', 'TeamProjection', 'conference'), values: () => d.teams.map((t) => t.conference) },
    { label: 'CbaTier', declared: () => extractTypeAliasUnion('lib/cbaTypes.ts', 'CbaTier'), values: () => d.cba.teams.map((t) => t.cbaTier) },
    { label: 'FranchiseCbaProfile.conference', declared: () => extractFieldUnion('lib/cbaTypes.ts', 'FranchiseCbaProfile', 'conference'), values: () => d.cba.teams.map((t) => t.conference) },
    {
      label: 'PlayerContract.contractType',
      declared: () => extractFieldUnion('lib/cbaTypes.ts', 'PlayerContract', 'contractType'),
      values: () => d.cba.teams.flatMap((t) => t.contracts.map((c) => c.contractType)),
    },
    { label: 'TransactionType', declared: () => extractTypeAliasUnion('lib/offseasonTypes.ts', 'TransactionType'), values: () => d.tx.map((t) => t.type) },
    { label: 'ImpactTier', declared: () => extractTypeAliasUnion('lib/offseasonTypes.ts', 'ImpactTier'), values: () => d.tx.map((t) => t.impact_tier) },
    { label: 'TeamOffseasonProfile.grade', declared: () => extractFieldUnion('lib/offseasonTypes.ts', 'TeamOffseasonProfile', 'grade'), values: () => d.offTeams.map((t) => t.grade) },
    { label: 'TeamOffseasonProfile.conference', declared: () => extractFieldUnion('lib/offseasonTypes.ts', 'TeamOffseasonProfile', 'conference'), values: () => d.offTeams.map((t) => t.conference) },
    { label: 'RookieDraftProfile.upside_tier', declared: () => extractFieldUnion('lib/offseasonTypes.ts', 'RookieDraftProfile', 'upside_tier'), values: () => d.draft.map((p) => p.upside_tier) },
    {
      label: 'PlayoffPlayer.role',
      declared: () => extractFieldUnion('lib/playoffTypes.ts', 'PlayoffPlayer', 'role'),
      values: () => Object.values(d.series.teams).flatMap((t) => t.rotation.map((r) => r.role)),
    },
    { label: 'TeamPlayoffProfile.conference', declared: () => extractFieldUnion('lib/playoffTypes.ts', 'TeamPlayoffProfile', 'conference'), values: () => Object.values(d.series.teams).map((t) => t.conference) },
    { label: 'SlateStatus', declared: () => extractTypeAliasUnion('lib/matchupTypes.ts', 'SlateStatus'), values: () => d.matchups.slates.map((s) => s.status) },
    { label: 'GradingState', declared: () => extractTypeAliasUnion('lib/matchupTypes.ts', 'GradingState'), values: () => [d.matchups.grading_state] },
    {
      label: 'ProjectionBasis',
      declared: () => extractTypeAliasUnion('lib/matchupTypes.ts', 'ProjectionBasis'),
      values: () => d.matchups.matchups.map((m) => m.projection_basis).filter((v): v is string => v !== null),
    },
    {
      label: 'MomentumVerdict',
      declared: () => extractTypeAliasUnion('lib/momentumMethodologyTypes.ts', 'MomentumVerdict'),
      values: () => [
        ...d.methodology.single_feature_results.map((r) => r.verdict),
        ...d.methodology.single_feature_sensitivity_primary.map((r) => r.verdict),
      ],
    },
  ];

  it.each(cases)('$label covers every distinct value in the data', ({ label, declared, values }) => {
    const decl = new Set(declared());
    expect(decl.size, `${label}: no string literals parsed from source`).toBeGreaterThan(0);
    const undeclared = [...new Set(values())].filter((v) => !decl.has(v));
    expect(undeclared, `${label} is missing data values: ${undeclared.join(', ')}`).toEqual([]);
  });
});
