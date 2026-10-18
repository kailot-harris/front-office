import fs from 'fs';
import path from 'path';
import {
  TeamProjection,
  PlayerProjection,
  ModelMetadata,
  ModelDiagnostics,
  PostseasonOpsData,
  StatcastSpatialData,
  PlayerSpatialDictionary,
} from './types';

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

export function getPostseasonOpsData(): PostseasonOpsData {
  const filePath = path.join(process.cwd(), 'public', 'data', 'projections_postseason_ops.json');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as PostseasonOpsData;
}

export function getSpatialData(): StatcastSpatialData {
  const filePath = path.join(process.cwd(), 'public', 'data', 'statcast_spatial_analytics.json');
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as StatcastSpatialData;
}

export function getPlayerSpatialMaps(): PlayerSpatialDictionary {
  const filePath = path.join(process.cwd(), 'public', 'data', 'player_spatial_maps.json');
  if (!fs.existsSync(filePath)) return {};
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as PlayerSpatialDictionary;
}

