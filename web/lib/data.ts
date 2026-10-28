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
  WorldSeriesData,
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

export function getWorldSeriesData(): WorldSeriesData | null {
  const filePath = path.join(process.cwd(), 'public', 'data', 'world_series.json');
  if (!fs.existsSync(filePath)) return null;
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as WorldSeriesData;
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
import { Matchup, MatchupsIndex } from './matchupTypes';

export function getMatchupsIndex(): MatchupsIndex {
  const filePath = path.join(process.cwd(), 'public', 'data', 'matchups_index.json');
  if (!fs.existsSync(filePath)) {
    return {
      season: new Date().getFullYear(),
      generated_at: new Date().toISOString(),
      active_week: 1,
      total_games: 0,
      completed_games: 0,
      graded_games: 0,
      correct_picks: 0,
      overall_accuracy: null,
      available_weeks: [],
    };
  }
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as MatchupsIndex;
}

/**
 * One slate's matchup rows, read at build time. Only called for the slate the
 * page opens on — every other week is fetched client-side from the same files
 * under public/, which is the whole point of splitting them up.
 */
export function getMatchupsWeek(week: number): Matchup[] {
  const fileName = `week-${String(week).padStart(2, '0')}.json`;
  const filePath = path.join(process.cwd(), 'public', 'data', 'matchups', fileName);
  if (!fs.existsSync(filePath)) return [];
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as Matchup[];
}

export function getPlayoffSeriesCatalog(): PlayoffMatchupsCatalog {
  const filePath = path.join(process.cwd(), 'public', 'data', 'playoff_series_matchups.json');
  if (!fs.existsSync(filePath)) {
    return {
      generated_at: new Date().toISOString(),
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
      generated_at: new Date().toISOString(),
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
import { CbtLeagueOverview } from './cbtTypes';

export function getClutchCatalog(): ClutchCatalog {
  const filePath = path.join(process.cwd(), 'public', 'data', 'clutch_leverage_metrics.json');
  if (!fs.existsSync(filePath)) {
    return {
      generated_at: new Date().toISOString(),
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

export function getCbtPayrollOverview(): CbtLeagueOverview {
  const filePath = path.join(process.cwd(), 'public', 'data', 'cbt_payroll_sheet.json');
  if (!fs.existsSync(filePath)) {
    return {
      generated_at: new Date().toISOString(),
      season: '2026',
      baseThreshold: 244.0,
      tier1Threshold: 264.0,
      tier2Threshold: 284.0,
      tier3Threshold: 304.0,
      totalLeaguePayroll: 0,
      totalLuxuryTaxCollected: 0,
      teams: [],
    };
  }
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as CbtLeagueOverview;
}

