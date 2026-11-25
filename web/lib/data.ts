import fs from 'fs';
import path from 'path';
import {
  StandingsDataset,
  MatchupsDataset,
  TeamEpaProfile,
  PlayoffDataset,
  QbProfile,
  DiagnosticsDataset,
  VisualMediaItem,
  CoachingDataset,
  SalaryCapDataset,
  PassingCatalogEntry,
  PassingMetadata,
  PlayerDnaDataset,
  ClutchProfile,
  GameDetailEnvelope,
} from './types';
import type { PlayerLeadersPayload } from './playerLeadersTypes';

function readJsonFile<T>(filename: string): T {
  const filePath = path.join(process.cwd(), 'public', 'data', filename);
  if (!fs.existsSync(filePath)) {
    throw new Error(`Data file not found: ${filePath}. Please run tools/export_web_datasets.R.`);
  }
  const content = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(content) as T;
}

export function getStandingsData(): StandingsDataset {
  return readJsonFile<StandingsDataset>('standings_projections.json');
}

export function getMatchupsData(): MatchupsDataset {
  return readJsonFile<MatchupsDataset>('matchups_current_week.json');
}

export function getTeamEpaProfiles(): TeamEpaProfile[] {
  return readJsonFile<TeamEpaProfile[]>('team_epa_profiles.json');
}

export function getPlayoffPicture(): PlayoffDataset {
  return readJsonFile<PlayoffDataset>('playoff_picture.json');
}

// League leaders panel (NFL_analytics#230). A missing or unreadable file shows an
// "unavailable" note on /players instead of failing the build.
export function getPlayerLeaders(): PlayerLeadersPayload | null {
  try {
    return readJsonFile<PlayerLeadersPayload>('player_leaders.json');
  } catch (error) {
    console.error('Error reading player_leaders.json:', error);
    return null;
  }
}

export function getQbProfiles(): QbProfile[] {
  return readJsonFile<QbProfile[]>('player_qb_profiles.json');
}

export function getDiagnosticsData(): DiagnosticsDataset {
  return readJsonFile<DiagnosticsDataset>('model_diagnostics.json');
}

export function getVisualMediaIndex(): VisualMediaItem[] {
  return readJsonFile<VisualMediaItem[]>('visual_media_index.json');
}

export function getCoachingProfiles(): CoachingDataset {
  return readJsonFile<CoachingDataset>('coaching_profiles.json');
}

export function getSalaryCapData(): SalaryCapDataset {
  return readJsonFile<SalaryCapDataset>('salary_cap_profiles.json');
}

export function getPassingIndex(): PassingCatalogEntry[] {
  return readJsonFile<PassingCatalogEntry[]>('passing_index.json');
}

export function getPassingMetadata(): PassingMetadata {
  return readJsonFile<PassingMetadata>('passing_metadata.json');
}

export function getPlayerDnaProfiles(): PlayerDnaDataset {
  return readJsonFile<PlayerDnaDataset>('player_dna_profiles.json');
}
export function getClutchData(): ClutchProfile[] {
  return readJsonFile<ClutchProfile[]>('clutch_leverage_metrics.json');
}

export function getGameDetail(gameId: string): GameDetailEnvelope | null {
  const filePath = path.join(process.cwd(), 'public', 'data', 'games', `${gameId}.json`);
  if (!fs.existsSync(filePath)) {
    return null;
  }
  const content = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(content) as GameDetailEnvelope;
}

