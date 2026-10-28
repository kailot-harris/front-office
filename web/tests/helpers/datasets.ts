/**
 * Shared dataset loaders + MLB structural constants for the test suites.
 *
 * Every loader reads the RAW JSON from public/data (never via lib/data.ts) so
 * the contract layers test what the R pipeline actually exported, not what a
 * TypeScript cast claims it exported.
 *
 * League constants mirror config.R and the MLB domain (30 teams, 162 games).
 */
import fs from 'fs';
import path from 'path';
import type {
  TeamProjection,
  PlayerProjection,
  ModelMetadata,
  ModelDiagnostics,
  PostseasonOpsData,
  WorldSeriesData,
} from '@/lib/types';
import type { CbtLeagueOverview } from '@/lib/cbtTypes';
import type { ClutchCatalog } from '@/lib/clutchTypes';
import type { PlayerDnaCatalog } from '@/lib/playerDnaTypes';
import type { PlayoffMatchupsCatalog } from '@/lib/playoffTypes';
import type { MatchupsIndex, Matchup } from '@/lib/matchupTypes';

export const WEB_ROOT = path.resolve(__dirname, '../..');
export const PUBLIC_DIR = path.join(WEB_ROOT, 'public');
export const DATA_DIR = path.join(PUBLIC_DIR, 'data');
export const MATCHUPS_DIR = path.join(DATA_DIR, 'matchups');
export const LOGOS_DIR = path.join(PUBLIC_DIR, 'logos');

export const MLB_TEAMS = [
  'ARI', 'ATH', 'ATL', 'BAL', 'BOS', 'CHC', 'CHW', 'CIN', 'CLE', 'COL',
  'DET', 'HOU', 'KC', 'LAA', 'LAD', 'MIA', 'MIL', 'MIN', 'NYM', 'NYY',
  'PHI', 'PIT', 'SD', 'SEA', 'SF', 'STL', 'TB', 'TEX', 'TOR', 'WSH',
] as const;
export type MlbTeamAbbr = (typeof MLB_TEAMS)[number];

export const MLB_LEAGUES = ['AL', 'NL'] as const;
export const MLB_DIVISIONS = [
  'AL East', 'AL Central', 'AL West', 'NL East', 'NL Central', 'NL West',
] as const;
export const MLB_PLAYER_TYPES = ['Batter', 'Pitcher'] as const;

export const LEAGUE = {
  TEAM_COUNT: 30,
  TEAMS_PER_LEAGUE: 15,
  TEAMS_PER_DIVISION: 5,
  SEASON_GAMES: 162,
  GAMES_PER_SEASON: 2430, // 30 * 162 / 2
  PLAYOFF_FIELD: 12,
  CBT_2026: {
    BASE: 244.0,
    TIER1: 264.0,
    TIER2: 284.0,
    TIER3: 304.0,
  },
} as const;

/**
 * The 10 pipeline-owned datasets from config.R's WEB_DATA_FILES plus
 * world_series.json (owned by refresh_live_results.R).
 */
export const EXPECTED_DATA_FILES = [
  'projections_season_teams.json',
  'projections_season_players.json',
  'projections_models_metadata.json',
  'projections_diagnostics.json',
  'projections_postseason_ops.json',
  'playoff_series_matchups.json',
  'player_dna_profiles.json',
  'clutch_leverage_metrics.json',
  'cbt_payroll_sheet.json',
  'matchups_index.json',
  'world_series.json',
] as const;

/** Optional Statcast spatial artifacts written when Statcast caches are present. */
export const OPTIONAL_DATA_FILES = [
  'statcast_spatial_analytics.json',
  'player_spatial_maps.json',
] as const;

export type DataFileName =
  | (typeof EXPECTED_DATA_FILES)[number]
  | (typeof OPTIONAL_DATA_FILES)[number];

export function readJsonFile<T>(fileName: DataFileName): T {
  const fullPath = path.join(DATA_DIR, fileName);
  return JSON.parse(fs.readFileSync(fullPath, 'utf-8')) as T;
}

export function readMatchupWeekFile(week: number): Matchup[] {
  const fileName = `week-${String(week).padStart(2, '0')}.json`;
  const fullPath = path.join(MATCHUPS_DIR, fileName);
  return JSON.parse(fs.readFileSync(fullPath, 'utf-8')) as Matchup[];
}

export function loadAllDatasets() {
  return {
    teams: readJsonFile<TeamProjection[]>('projections_season_teams.json'),
    players: readJsonFile<PlayerProjection[]>('projections_season_players.json'),
    metadata: readJsonFile<ModelMetadata>('projections_models_metadata.json'),
    diagnostics: readJsonFile<ModelDiagnostics>('projections_diagnostics.json'),
    postseasonOps: readJsonFile<PostseasonOpsData>('projections_postseason_ops.json'),
    playoffSeries: readJsonFile<PlayoffMatchupsCatalog>('playoff_series_matchups.json'),
    playerDna: readJsonFile<PlayerDnaCatalog>('player_dna_profiles.json'),
    clutch: readJsonFile<ClutchCatalog>('clutch_leverage_metrics.json'),
    cbtSheet: readJsonFile<CbtLeagueOverview>('cbt_payroll_sheet.json'),
    matchupsIndex: readJsonFile<MatchupsIndex>('matchups_index.json'),
    worldSeries: readJsonFile<WorldSeriesData>('world_series.json'),
  };
}
