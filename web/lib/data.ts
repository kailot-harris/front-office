import fs from 'fs';
import path from 'path';
import { TeamProjection, PlayerProjection, ModelMetadata, ModelDiagnostics } from './types';

export function getTeamsData(): TeamProjection[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'projections_season_teams.json');
  if (!fs.existsSync(filePath)) return [];
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as TeamProjection[];
}

export function getPlayersData(): PlayerProjection[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'projections_season_players.json');
  if (!fs.existsSync(filePath)) return [];
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as PlayerProjection[];
}

export function getMetadata(): ModelMetadata {
  const filePath = path.join(process.cwd(), 'public', 'data', 'projections_models_metadata.json');
  if (!fs.existsSync(filePath)) {
    return {
      schema_version: '1.0',
      pipeline_stage: 'season_long_projections',
      generated_at: new Date().toISOString(),
      season: 2026,
      n_simulations: 1000,
      margin_sigma: 14.0,
      home_court_advantage: 2.4,
      total_schedule_games: 330,
      teams_count: 15,
      players_count: 0,
      models: {
        ensemble: {
          name: 'Multi-Model Ensemble Blend',
          weights: {
            variant_bottom_up: 0.35,
            variant_rapm: 0.25,
            variant_shot_fatigue: 0.2,
            variant_embeddings: 0.2,
          },
          description: 'Weighted blend of bottom-up BPM, stint RAPM, shot-fatigue, and latent style embeddings',
        },
        variant_bottom_up: {
          name: 'Production Bottom-Up Rotation BPM',
          weight: 0.35,
          description: 'Minute-weighted player BPM ratings aggregated over 200-minute active roster rotations',
        },
        variant_rapm: {
          name: 'Bayesian Stint-Level RAPM',
          weight: 0.25,
          description: 'Ridge-regularized adjusted plus-minus stint ratings centered across league possessions',
        },
        variant_shot_fatigue: {
          name: 'Shot Quality & Circadian Travel Fatigue',
          weight: 0.2,
          description: 'Ratings adjusted for spatial shot-quality regression and travel/circadian rest fatigue',
        },
        variant_embeddings: {
          name: '16-D Style Latent Embeddings',
          weight: 0.2,
          description: 'Expected win probability modulated by 16-D team stylistic similarity matrix',
        },
      },
    };
  }
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as ModelMetadata;
}

export function getDiagnostics(): ModelDiagnostics {
  const filePath = path.join(process.cwd(), 'public', 'data', 'projections_diagnostics.json');
  if (!fs.existsSync(filePath)) {
    return {
      generated_at: new Date().toISOString(),
      totalResolvedGames: 0,
      overallAccuracy: 0,
      brierScore: 0,
      logLoss: 0,
      homeWinRate: 0,
      calibration: [],
      accuracyDrift: [],
      residualDistribution: [],
    };
  }
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as ModelDiagnostics;
}
