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

import { PlayoffMatchupsCatalog } from './playoffTypes';
import { PlayerDnaCatalog } from './playerDnaTypes';

export function getPlayoffSeriesCatalog(): PlayoffMatchupsCatalog {
  const filePath = path.join(process.cwd(), 'public', 'data', 'playoff_series_matchups.json');
  if (!fs.existsSync(filePath)) {
    return {
      updatedAt: new Date().toISOString(),
      nSims: 10000,
      teams: {},
      matchups: {},
    };
  }
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as PlayoffMatchupsCatalog;
}

export function getPlayerDnaCatalog(): PlayerDnaCatalog {
  const filePath = path.join(process.cwd(), 'public', 'data', 'player_dna_profiles.json');
  if (!fs.existsSync(filePath)) {
    return {
      updatedAt: new Date().toISOString(),
      eraBaseline: '1980-2026',
      totalPlayers: 0,
      batterArchetypes: [],
      pitcherArchetypes: [],
      profiles: [],
    };
  }
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as PlayerDnaCatalog;
}

import { ClutchCatalog } from './clutchTypes';

export function getClutchCatalog(): ClutchCatalog {
  const filePath = path.join(process.cwd(), 'public', 'data', 'clutch_leverage_metrics.json');
  if (!fs.existsSync(filePath)) {
    return {
      updatedAt: new Date().toISOString(),
      totalProfiles: 0,
      clutchLeaderBatters: [],
      clutchLeaderPitchers: [],
      profiles: [],
    };
  }
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as ClutchCatalog;
}

