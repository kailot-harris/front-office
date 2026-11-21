import fs from 'fs';
import path from 'path';
import { TeamProjection, PlayerProjection, ModelMetadata, ModelDiagnostics } from './types';
import { MatchupsDataset } from './matchupTypes';
import type { VisualMediaIndexEntry } from './visualMedia';

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

/** Visual media index (export_visual_media_index.R): the single source for the Gallery page. */
export function getVisualMediaIndex(): VisualMediaIndexEntry[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'visual_media_index.json');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as VisualMediaIndexEntry[];
}
