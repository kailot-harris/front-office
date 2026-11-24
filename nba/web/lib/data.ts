import fs from 'fs';
import path from 'path';
import { TeamProjection, PlayerProjection, ModelMetadata, ModelDiagnostics, ActualTeamRecord } from './types';
import { MatchupsDataset, MatchupGame } from './matchupTypes';
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

/**
 * Derive actual team W-L, pointsFor, and pointsAgainst from completed games in
 * matchups_slates.json. Skips pending games or rows lacking finite scores.
 */
export function deriveActualTeamRecords(
  matchups: readonly MatchupGame[],
): Record<string, ActualTeamRecord> {
  const records: Record<string, ActualTeamRecord> = {};

  const ensureTeam = (abbr: string): ActualTeamRecord => {
    let rec = records[abbr];
    if (!rec) {
      rec = { wins: 0, losses: 0, pointsFor: 0, pointsAgainst: 0 };
      records[abbr] = rec;
    }
    return rec;
  };

  for (const game of matchups) {
    if (!game.is_completed) continue;
    const { home_team, away_team, home_score, away_score } = game;
    if (
      typeof home_score !== 'number' ||
      typeof away_score !== 'number' ||
      !Number.isFinite(home_score) ||
      !Number.isFinite(away_score)
    ) {
      continue;
    }

    const home = ensureTeam(home_team);
    const away = ensureTeam(away_team);

    home.pointsFor += home_score;
    home.pointsAgainst += away_score;
    away.pointsFor += away_score;
    away.pointsAgainst += home_score;

    if (home_score > away_score) {
      home.wins += 1;
      away.losses += 1;
    } else if (away_score > home_score) {
      away.wins += 1;
      home.losses += 1;
    }
  }

  return records;
}

/** Build-time actual team records derived from matchups_slates.json. */
export function getActualTeamRecords(): Record<string, ActualTeamRecord> {
  const { matchups } = getMatchupsData();
  return deriveActualTeamRecords(matchups);
}
