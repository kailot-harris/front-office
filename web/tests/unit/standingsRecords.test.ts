import { describe, expect, it } from 'vitest';
import { deriveActualTeamRecords } from '../../lib/standingsRecords';
import { matchups, standings } from '../helpers/datasets';
import type { MatchupGame } from '../../lib/types';

describe('deriveActualTeamRecords', () => {
  it('derives complete W-L-T, PF, PA for all 32 teams from matchups_current_week.json', () => {
    const matchupsData = matchups();
    const standingsData = standings();
    const records = deriveActualTeamRecords(matchupsData);

    expect(Object.keys(records)).toHaveLength(standingsData.teams.length);

    let totalWins = 0;
    let totalLosses = 0;
    let totalTies = 0;
    let totalPf = 0;
    let totalPa = 0;

    for (const team of standingsData.teams) {
      const rec = records[team.team];
      expect(rec, `missing derived record for ${team.team}`).toBeDefined();
      expect(Number.isInteger(rec.wins) && rec.wins >= 0).toBe(true);
      expect(Number.isInteger(rec.losses) && rec.losses >= 0).toBe(true);
      expect(Number.isInteger(rec.ties) && rec.ties >= 0).toBe(true);
      expect(Number.isFinite(rec.pointsFor) && rec.pointsFor >= 0).toBe(true);
      expect(Number.isFinite(rec.pointsAgainst) && rec.pointsAgainst >= 0).toBe(true);

      const gp = rec.wins + rec.losses + rec.ties;
      expect(gp, `${team.team} games played mismatch`).toBe(team.games_played);

      totalWins += rec.wins;
      totalLosses += rec.losses;
      totalTies += rec.ties;
      totalPf += rec.pointsFor;
      totalPa += rec.pointsAgainst;
    }

    expect(totalWins).toBe(totalLosses);
    expect(totalTies % 2).toBe(0);
    expect(totalPf).toBe(totalPa);
  });

  it('ignores incomplete games and tallies wins, losses, ties, PF, and PA', () => {
    const games: Partial<MatchupGame>[] = [
      {
        home_team: 'SEA',
        away_team: 'NE',
        is_completed: true,
        home_score: 24,
        away_score: 17,
      },
      {
        home_team: 'NE',
        away_team: 'BUF',
        is_completed: true,
        home_score: 20,
        away_score: 20,
      },
      {
        home_team: 'SEA',
        away_team: 'BUF',
        is_completed: false,
        home_score: 99,
        away_score: 0,
      },
      {
        home_team: 'KC',
        away_team: 'DEN',
        is_completed: true,
        home_score: null,
        away_score: 14,
      },
    ];

    const records = deriveActualTeamRecords({ matchups: games as MatchupGame[] });

    expect(records.SEA).toEqual({ wins: 1, losses: 0, ties: 0, pointsFor: 24, pointsAgainst: 17 });
    expect(records.NE).toEqual({ wins: 0, losses: 1, ties: 1, pointsFor: 37, pointsAgainst: 44 });
    expect(records.BUF).toEqual({ wins: 0, losses: 0, ties: 1, pointsFor: 20, pointsAgainst: 20 });
    expect(records.KC).toBeUndefined();
    expect(records.DEN).toBeUndefined();
  });
});
