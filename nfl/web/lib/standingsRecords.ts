import type { MatchupsDataset, NflActualTeamRecord } from './types';

function emptyRecord(): NflActualTeamRecord {
  return {
    wins: 0,
    losses: 0,
    ties: 0,
    pointsFor: 0,
    pointsAgainst: 0,
  };
}

/**
 * Derive actual regular-season team records (W-L-T, PF, PA) from completed
 * games in `matchups_current_week.json`.
 */
export function deriveActualTeamRecords(
  matchupsData: Pick<MatchupsDataset, 'matchups'>,
): Record<string, NflActualTeamRecord> {
  const records: Record<string, NflActualTeamRecord> = {};

  for (const game of matchupsData.matchups) {
    if (!game.is_completed) continue;
    const homeScore = game.home_score;
    const awayScore = game.away_score;
    if (
      typeof homeScore !== 'number' ||
      typeof awayScore !== 'number' ||
      !Number.isFinite(homeScore) ||
      !Number.isFinite(awayScore)
    ) {
      continue;
    }

    const home = (records[game.home_team] ??= emptyRecord());
    const away = (records[game.away_team] ??= emptyRecord());

    home.pointsFor += homeScore;
    home.pointsAgainst += awayScore;
    away.pointsFor += awayScore;
    away.pointsAgainst += homeScore;

    if (homeScore > awayScore) {
      home.wins += 1;
      away.losses += 1;
    } else if (awayScore > homeScore) {
      away.wins += 1;
      home.losses += 1;
    } else {
      home.ties += 1;
      away.ties += 1;
    }
  }

  return records;
}
