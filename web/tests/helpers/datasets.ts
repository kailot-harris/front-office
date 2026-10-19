/**
 * Shared dataset loaders for the vitest suites.
 *
 * Reads the exact same JSON files that `lib/data.ts` serves to the Next.js
 * pages, but without going through `lib/data.ts` itself, so a contract test
 * failure points at the data (produced by `tools/export_web_datasets.R`)
 * rather than at the reader.
 */
import fs from 'fs';
import path from 'path';
import type {
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
} from '../../lib/types';

export const REPO_WEB_ROOT = path.resolve(__dirname, '..', '..');
export const DATA_DIR = path.join(REPO_WEB_ROOT, 'public', 'data');
export const ANIMATIONS_DIR = path.join(REPO_WEB_ROOT, 'public', 'animations');

/** Every dataset file the site reads, keyed by the `lib/data.ts` getter name. */
export const DATASET_FILES = {
  getStandingsData: 'standings_projections.json',
  getMatchupsData: 'matchups_current_week.json',
  getTeamEpaProfiles: 'team_epa_profiles.json',
  getPlayoffPicture: 'playoff_picture.json',
  getQbProfiles: 'player_qb_profiles.json',
  getDiagnosticsData: 'model_diagnostics.json',
  getValueBets: 'value_bets.json',
  getVisualMediaIndex: 'visual_media_index.json',
  getCoachingProfiles: 'coaching_profiles.json',
  getSalaryCapData: 'salary_cap_profiles.json',
} as const;

export function loadRaw(filename: string): unknown {
  const p = path.join(DATA_DIR, filename);
  if (!fs.existsSync(p)) {
    throw new Error(`Dataset missing: ${p}. Run tools/export_web_datasets.R.`);
  }
  return JSON.parse(fs.readFileSync(p, 'utf-8'));
}

export const standings = () => loadRaw(DATASET_FILES.getStandingsData) as StandingsDataset;
export const matchups = () => loadRaw(DATASET_FILES.getMatchupsData) as MatchupsDataset;
export const teamEpa = () => loadRaw(DATASET_FILES.getTeamEpaProfiles) as TeamEpaProfile[];
export const playoffs = () => loadRaw(DATASET_FILES.getPlayoffPicture) as PlayoffDataset;
export const qbs = () => loadRaw(DATASET_FILES.getQbProfiles) as QbProfile[];
export const diagnostics = () => loadRaw(DATASET_FILES.getDiagnosticsData) as DiagnosticsDataset;
export const valueBets = () => loadRaw(DATASET_FILES.getValueBets) as ValueBetsDataset;
export const media = () => loadRaw(DATASET_FILES.getVisualMediaIndex) as VisualMediaItem[];
export const coaching = () => loadRaw(DATASET_FILES.getCoachingProfiles) as CoachProfile[];
export const salaryCap = () => loadRaw(DATASET_FILES.getSalaryCapData) as SalaryCapDataset;

/** Sum helper that keeps float noise out of the assertion messages. */
export const sumBy = <T,>(rows: readonly T[], f: (row: T) => number): number =>
  rows.reduce((acc, row) => acc + f(row), 0);

/** Group rows by a string key. */
export function groupBy<T>(rows: readonly T[], key: (row: T) => string): Record<string, T[]> {
  const out: Record<string, T[]> = {};
  for (const row of rows) {
    const k = key(row);
    (out[k] ||= []).push(row);
  }
  return out;
}

/**
 * Structural league facts. Mirrors the repo-root `config.R` constants
 * (NFL_TEAM_COUNT, NFL_SEASON_GAMES, NFL_PLAYOFF_FIELD). Re-verify against
 * config.R at the start of each season rather than trusting these blindly.
 */
export const LEAGUE = {
  TEAM_COUNT: 32,
  CONFERENCES: ['AFC', 'NFC'] as const,
  DIVISION_COUNT: 8,
  TEAMS_PER_DIVISION: 4,
  SEASON_GAMES: 17,
  REGULAR_SEASON_WEEKS: 18,
  GAMES_PER_SEASON: 272,
  PLAYOFF_FIELD: 14,
  SEEDS_PER_CONFERENCE: 7,
  BYES_PER_CONFERENCE: 1,
} as const;
