import fs from 'fs';
import path from 'path';
import { TeamProjection, PlayerProjection, ModelMetadata, ModelDiagnostics } from './types';
import { MatchupsDataset } from './matchupTypes';

export function getTeamsData(): TeamProjection[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'projections_season_teams.json');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as TeamProjection[];
}

export function getPlayersData(): PlayerProjection[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'projections_season_players.json');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as PlayerProjection[];
}

export function getMetadata(): ModelMetadata {
  const filePath = path.join(process.cwd(), 'public', 'data', 'projections_models_metadata.json');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as ModelMetadata;
}

export function getDiagnostics(): ModelDiagnostics {
  const filePath = path.join(process.cwd(), 'public', 'data', 'projections_diagnostics.json');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as ModelDiagnostics;
}

/** Per-game weekly matchup slates: see build_matchups_dataset.R and lib/matchupTypes.ts. */
export function getMatchupsData(): MatchupsDataset {
  const filePath = path.join(process.cwd(), 'public', 'data', 'matchups_slates.json');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as MatchupsDataset;
}
