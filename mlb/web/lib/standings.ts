import type { ActualTeamRecord, TeamProjection } from './types';
import type { Matchup } from './matchupTypes';

export const MLB_REGULAR_SEASON_GAMES = 162;

export interface EnrichedMlbTeam extends TeamProjection {
  actual: ActualTeamRecord;
  actual_gp: number;
  actual_win_pct: number;
  actual_run_diff: number;
  current_pace: number;
  projected_wins: number;
  performance_delta: number;
}

/**
 * Derive actual regular-season W-L and run differential per team from matchup rows.
 * Only completed regular-season games (`game_type === 'R'`) with numeric scores
 * are counted so October postseason games never inflate the 162-game slate.
 */
export function deriveActualTeamRecords(
  matchups: readonly Matchup[],
): Record<string, ActualTeamRecord> {
  const records: Record<string, ActualTeamRecord> = {};

  const ensureTeam = (abbr: string): ActualTeamRecord => {
    let rec = records[abbr];
    if (!rec) {
      rec = { wins: 0, losses: 0, runsFor: 0, runsAgainst: 0 };
      records[abbr] = rec;
    }
    return rec;
  };

  for (const game of matchups) {
    if (game.game_type !== 'R') continue;
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

    home.runsFor += home_score;
    home.runsAgainst += away_score;
    away.runsFor += away_score;
    away.runsAgainst += home_score;

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

/**
 * Enrich team projections with actual regular-season records, 162-game win pace,
 * run differential, and performance delta (`actual_pace - projected_wins`).
 */
export function enrichTeamsWithActuals(
  teams: readonly TeamProjection[],
  actualRecords: Record<string, ActualTeamRecord>,
): EnrichedMlbTeam[] {
  return teams.map((team) => {
    const actual = actualRecords[team.team] ?? {
      wins: 0,
      losses: 0,
      runsFor: 0,
      runsAgainst: 0,
    };
    const actual_gp = actual.wins + actual.losses;
    const actual_win_pct = actual_gp > 0 ? actual.wins / actual_gp : 0;
    const current_pace =
      actual_gp === MLB_REGULAR_SEASON_GAMES
        ? actual.wins
        : actual_gp > 0
          ? actual_win_pct * MLB_REGULAR_SEASON_GAMES
          : 0;
    const projected_wins = Number.isFinite(team.ensemble_mean_wins)
      ? team.ensemble_mean_wins
      : team.proj_wins;
    const performance_delta = actual_gp > 0 ? current_pace - projected_wins : 0;
    const actual_run_diff = actual.runsFor - actual.runsAgainst;

    return {
      ...team,
      actual,
      actual_gp,
      actual_win_pct,
      actual_run_diff,
      current_pace,
      projected_wins,
      performance_delta,
    };
  });
}
