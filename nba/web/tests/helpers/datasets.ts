/**
 * Shared dataset loaders + NBA structural constants for the test suites.
 *
 * Every loader reads the RAW JSON from public/data (never via lib/data.ts) so
 * the contract layers test what the R pipeline actually exported, not what a
 * TypeScript cast claims it exported.
 *
 * League constants mirror config.R and the NBA domain (30 teams, 82 games).
 */
import fs from 'fs';
import path from 'path';
import type {
  TeamProjection,
  PlayerProjection,
  ModelMetadata,
  ModelDiagnostics,
} from '@/lib/types';
import type { CbaLeagueOverview } from '@/lib/cbaTypes';
import type { ClutchProfile } from '@/lib/clutchTypes';
import type { CoachingStaffMetric } from '@/lib/coachingTypes';
import type { DefensiveProfile } from '@/lib/defenseTypes';
import type { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import type {
  OffseasonTransaction,
  TeamOffseasonProfile,
  RookieDraftProfile,
} from '@/lib/offseasonTypes';
import type { PlayoffMatchupsCatalog } from '@/lib/playoffTypes';
import type { PlayerCatalogEntry, PlayerShotData, ShotsMetadata } from '@/lib/shotTypes';
import type { MatchupsDataset } from '@/lib/matchupTypes';

export const WEB_ROOT = path.resolve(__dirname, '../..');
export const PUBLIC_DIR = path.join(WEB_ROOT, 'public');
export const DATA_DIR = path.join(PUBLIC_DIR, 'data');
export const SHOTS_DIR = path.join(DATA_DIR, 'shots');

export const NBA_TEAMS = [
  'ATL', 'BOS', 'BKN', 'CHA', 'CHI', 'CLE', 'DAL', 'DEN', 'DET', 'GSW',
  'HOU', 'IND', 'LAC', 'LAL', 'MEM', 'MIA', 'MIL', 'MIN', 'NOP', 'NYK',
  'OKC', 'ORL', 'PHI', 'PHX', 'POR', 'SAC', 'SAS', 'TOR', 'UTA', 'WAS',
] as const;
export type NbaTeamAbbr = (typeof NBA_TEAMS)[number];

export const NBA_CONFERENCES = ['East', 'West'] as const;
export const NBA_DIVISIONS = [
  'Atlantic', 'Central', 'Southeast', 'Northwest', 'Pacific', 'Southwest',
] as const;
/** Positions used by the projection / clutch / defense / DNA / series datasets. */
export const NBA_POSITIONS = ['G', 'F', 'C'] as const;

/** League structural constants (config.R + NBA rules). */
export const LEAGUE = {
  TEAM_COUNT: 30,
  TEAMS_PER_CONFERENCE: 15,
  TEAMS_PER_DIVISION: 5,
  SEASON_GAMES: 82,
  GAMES_PER_SEASON: 1230, // 30 * 82 / 2
  GAME_MINUTES: 48,
  TEAM_GAME_MINUTES: 240, // 48 * 5
  PLAYOFF_ROTATION_SIZE: 8,
  PLAYERS_PER_TEAM: 11,
  ACTIVE_PLAYER_POOL: 330, // 11 * 30
  PLAYOFF_FIELD: 16,
  MARGIN_SIGMA: 11.8, // config.R MARGIN_SIGMA
  HCA: 2.4,
  SHOT_ZONES_COUNT: 14,
  DRAFT_PICKS: 60,
  CBA_2026: {
    SALARY_CAP: 165.0,
    LUXURY_TAX: 200.4,
    FIRST_APRON: 209.0,
    SECOND_APRON: 221.7,
  },
} as const;

export const EXPECTED_SHOT_ZONES = [
  'Restricted Area',
  'Paint (Low / Floater)',
  'Paint (High / FT)',
  'Left Baseline Mid',
  'Right Baseline Mid',
  'Left Wing Mid',
  'Center Mid',
  'Right Wing Mid',
  'Left Corner 3',
  'Right Corner 3',
  'Left Wing 3',
  'Center 3',
  'Right Wing 3',
  'Deep / Logo 3',
] as const;

export const EXPECTED_DATA_FILES = [
  'projections_season_teams.json',
  'projections_season_players.json',
  'projections_models_metadata.json',
  'projections_diagnostics.json',
  'cba_cap_sheet.json',
  'clutch_leverage_metrics.json',
  'coaching_metrics.json',
  'defensive_metrics.json',
  'player_dna_profiles.json',
  'offseason_draft.json',
  'offseason_teams.json',
  'offseason_transactions.json',
  'playoff_series_matchups.json',
  'matchups_slates.json',
  'shots_index.json',
  'shots_metadata.json',
] as const;
export type DataFileName = (typeof EXPECTED_DATA_FILES)[number];

const cache = new Map<string, unknown>();

export function readJsonFile<T = unknown>(fileName: DataFileName): T {
  if (cache.has(fileName)) return cache.get(fileName) as T;
  const parsed = JSON.parse(fs.readFileSync(path.join(DATA_DIR, fileName), 'utf-8')) as T;
  cache.set(fileName, parsed);
  return parsed;
}

export function readPlayerShotFile(playerId: string): PlayerShotData {
  const key = `shots/${playerId}.json`;
  if (cache.has(key)) return cache.get(key) as PlayerShotData;
  const parsed = JSON.parse(
    fs.readFileSync(path.join(SHOTS_DIR, `${playerId}.json`), 'utf-8'),
  ) as PlayerShotData;
  cache.set(key, parsed);
  return parsed;
}

export function loadAllDatasets() {
  return {
    teams: readJsonFile<TeamProjection[]>('projections_season_teams.json'),
    players: readJsonFile<PlayerProjection[]>('projections_season_players.json'),
    metadata: readJsonFile<ModelMetadata>('projections_models_metadata.json'),
    diagnostics: readJsonFile<ModelDiagnostics>('projections_diagnostics.json'),
    cbaCapSheet: readJsonFile<CbaLeagueOverview>('cba_cap_sheet.json'),
    clutch: readJsonFile<ClutchProfile[]>('clutch_leverage_metrics.json'),
    coaches: readJsonFile<CoachingStaffMetric[]>('coaching_metrics.json'),
    defense: readJsonFile<DefensiveProfile[]>('defensive_metrics.json'),
    playerDna: readJsonFile<PlayerDnaProfile[]>('player_dna_profiles.json'),
    offseasonDraft: readJsonFile<RookieDraftProfile[]>('offseason_draft.json'),
    offseasonTeams: readJsonFile<TeamOffseasonProfile[]>('offseason_teams.json'),
    offseasonTransactions: readJsonFile<OffseasonTransaction[]>('offseason_transactions.json'),
    playoffSeries: readJsonFile<PlayoffMatchupsCatalog>('playoff_series_matchups.json'),
    shotsIndex: readJsonFile<PlayerCatalogEntry[]>('shots_index.json'),
    shotsMetadata: readJsonFile<ShotsMetadata>('shots_metadata.json'),
    matchups: readJsonFile<MatchupsDataset>('matchups_slates.json'),
  };
}
