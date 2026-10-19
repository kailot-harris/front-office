import fs from 'fs';
import path from 'path';
import {
  StandingsDataset,
  MatchupsDataset,
  TeamEpaProfile,
  PlayoffDataset,
  QbProfile,
  DiagnosticsDataset,
  ValueBetsDataset,
  VisualMediaItem,
  CoachProfile,
  SalaryCapDataset,
} from './types';

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

export function getQbProfiles(): QbProfile[] {
  return readJsonFile<QbProfile[]>('player_qb_profiles.json');
}

export function getDiagnosticsData(): DiagnosticsDataset {
  return readJsonFile<DiagnosticsDataset>('model_diagnostics.json');
}

export function getValueBets(): ValueBetsDataset {
  return readJsonFile<ValueBetsDataset>('value_bets.json');
}

export function getVisualMediaIndex(): VisualMediaItem[] {
  return readJsonFile<VisualMediaItem[]>('visual_media_index.json');
}

export function getCoachingProfiles(): CoachProfile[] {
  return readJsonFile<CoachProfile[]>('coaching_profiles.json');
}

export function getSalaryCapData(): SalaryCapDataset {
  return readJsonFile<SalaryCapDataset>('salary_cap_profiles.json');
}
