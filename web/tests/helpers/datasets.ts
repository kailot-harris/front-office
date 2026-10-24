import fs from 'fs';
import path from 'path';
import type {
  TeamProjection,
  PlayerProjection,
  ModelMetadata,
  ModelDiagnostics,
} from '@/lib/types';
import type { WnbaCbaLeagueOverview } from '@/lib/cbaTypes';
import type { ClutchProfile } from '@/lib/clutchTypes';
import type { CoachingStaffMetric } from '@/lib/coachingTypes';
import type { DefensiveProfile } from '@/lib/defenseTypes';
import type { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import type {
  OffseasonDraftProspect,
  OffseasonTeamProfile,
  OffseasonTransaction,
} from '@/lib/offseasonTypes';
import type {
  PlayoffMatchupsCatalog,
  PlayoffBracketSeason,
  FinalsGamePredictionSet,
} from '@/lib/playoffTypes';
import type {
  PlayerCatalogEntry,
  PlayerShotData,
  ShotsMetadata,
} from '@/lib/shotTypes';

export const WEB_ROOT = path.resolve(__dirname, '../..');
export const PUBLIC_DIR = path.join(WEB_ROOT, 'public');
export const DATA_DIR = path.join(PUBLIC_DIR, 'data');
export const SHOTS_DIR = path.join(DATA_DIR, 'shots');
export const LOGOS_DIR = path.join(PUBLIC_DIR, 'logos');

export const WNBA_TEAMS = [
  'ATL',
  'CHI',
  'CON',
  'DAL',
  'GS',
  'IND',
  'LA',
  'LV',
  'MIN',
  'NY',
  'PHX',
  'POR',
  'SEA',
  'TOR',
  'WSH',
] as const;

export type WnbaTeamAbbr = (typeof WNBA_TEAMS)[number];

export const WNBA_CONFERENCES = ['East', 'West'] as const;
export const WNBA_DIVISIONS = ['Eastern', 'Western'] as const;
export const WNBA_POSITIONS = ['G', 'F', 'C'] as const;

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
  'playoff_bracket_2026.json',
  'finals_game_predictions_2026.json',
  'shots_index.json',
  'shots_metadata.json',
] as const;

export type DataFileName = (typeof EXPECTED_DATA_FILES)[number];

const cache = new Map<string, unknown>();

export function readJsonFile<T = unknown>(fileName: DataFileName): T {
  if (cache.has(fileName)) {
    return cache.get(fileName) as T;
  }
  const fullPath = path.join(DATA_DIR, fileName);
  const raw = fs.readFileSync(fullPath, 'utf-8');
  const parsed = JSON.parse(raw) as T;
  cache.set(fileName, parsed);
  return parsed;
}

export function readPlayerShotFile(playerId: string): PlayerShotData {
  const key = `shots/${playerId}.json`;
  if (cache.has(key)) {
    return cache.get(key) as PlayerShotData;
  }
  const fullPath = path.join(SHOTS_DIR, `${playerId}.json`);
  const raw = fs.readFileSync(fullPath, 'utf-8');
  const parsed = JSON.parse(raw) as PlayerShotData;
  cache.set(key, parsed);
  return parsed;
}

export function loadAllDatasets() {
  return {
    teams: readJsonFile<TeamProjection[]>('projections_season_teams.json'),
    players: readJsonFile<PlayerProjection[]>('projections_season_players.json'),
    metadata: readJsonFile<ModelMetadata>('projections_models_metadata.json'),
    diagnostics: readJsonFile<ModelDiagnostics>('projections_diagnostics.json'),
    cbaCapSheet: readJsonFile<WnbaCbaLeagueOverview>('cba_cap_sheet.json'),
    clutch: readJsonFile<ClutchProfile[]>('clutch_leverage_metrics.json'),
    coaches: readJsonFile<CoachingStaffMetric[]>('coaching_metrics.json'),
    defense: readJsonFile<DefensiveProfile[]>('defensive_metrics.json'),
    playerDna: readJsonFile<PlayerDnaProfile[]>('player_dna_profiles.json'),
    offseasonDraft: readJsonFile<OffseasonDraftProspect[]>('offseason_draft.json'),
    offseasonTeams: readJsonFile<OffseasonTeamProfile[]>('offseason_teams.json'),
    offseasonTransactions: readJsonFile<OffseasonTransaction[]>('offseason_transactions.json'),
    playoffSeries: readJsonFile<PlayoffMatchupsCatalog>('playoff_series_matchups.json'),
    playoffBracket2026: readJsonFile<PlayoffBracketSeason>('playoff_bracket_2026.json'),
    finalsGamePredictions: readJsonFile<FinalsGamePredictionSet>(
      'finals_game_predictions_2026.json'
    ),
    shotsIndex: readJsonFile<PlayerCatalogEntry[]>('shots_index.json'),
    shotsMetadata: readJsonFile<ShotsMetadata>('shots_metadata.json'),
  };
}
