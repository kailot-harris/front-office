import { describe, it, expect } from 'vitest';
import { deriveActualTeamRecords, getActualTeamRecords, getTeamsData } from '@/lib/data';
import { enrichTeamWithActualRecord, WNBA_SEASON_GAMES } from '@/components/StandingsClient';
import { WNBA_TEAMS } from '../helpers/datasets';

describe('deriveActualTeamRecords & 44G pace enrichment', () => {
  it('accumulates regular-season W-L and points while skipping pending, invalid, and postseason games', () => {
    const records = deriveActualTeamRecords([
      {
        is_completed: true,
        season_type: 'regular',
        home_team: 'NY',
        away_team: 'MIN',
        home_score: 90,
        away_score: 80,
      },
      {
        is_completed: true,
        season_type: 'regular',
        home_team: 'MIN',
        away_team: 'NY',
        home_score: 85,
        away_score: 75,
      },
      {
        is_completed: false,
        season_type: 'regular',
        home_team: 'NY',
        away_team: 'LV',
        home_score: null,
        away_score: null,
      },
      {
        is_completed: true,
        season_type: 'postseason',
        home_team: 'NY',
        away_team: 'MIN',
        home_score: 100,
        away_score: 70,
      },
    ]);

    expect(records.NY).toEqual({ wins: 1, losses: 1, pointsFor: 165, pointsAgainst: 165 });
    expect(records.MIN).toEqual({ wins: 1, losses: 1, pointsFor: 165, pointsAgainst: 165 });
    expect(records.LV).toBeUndefined();
  });

  it('getActualTeamRecords() derives real regular-season records for all 15 WNBA teams', () => {
    const records = getActualTeamRecords();
    expect(Object.keys(records).sort()).toEqual([...WNBA_TEAMS].sort());
    for (const abbr of WNBA_TEAMS) {
      const rec = records[abbr];
      expect(rec.wins + rec.losses).toBeGreaterThanOrEqual(WNBA_SEASON_GAMES);
      expect(rec.pointsFor).toBeGreaterThan(0);
      expect(rec.pointsAgainst).toBeGreaterThan(0);
    }
  });

  it('enrichTeamWithActualRecord() computes 44G pace in-season and equals final wins at 44G', () => {
    const [sampleTeam] = getTeamsData();
    const baseProj = { ...sampleTeam, ensemble_mean_wins: 24.0 };

    // In-season: 15-7 (22 GP) -> 44G pace = 30.0, delta = +6.0
    const inSeason = enrichTeamWithActualRecord(baseProj, {
      wins: 15,
      losses: 7,
      pointsFor: 1850,
      pointsAgainst: 1750,
    });
    expect(inSeason.actual_gp).toBe(22);
    expect(inSeason.actual_win_pct).toBeCloseTo(15 / 22, 6);
    expect(inSeason.current_pace).toBeCloseTo(30.0, 6);
    expect(inSeason.performance_delta).toBeCloseTo(6.0, 6);
    expect(inSeason.point_diff).toBe(100);

    // Post-regular-season: 30-14 (44 GP) -> 44G pace === 30 exactly
    const postRegular = enrichTeamWithActualRecord(baseProj, {
      wins: 30,
      losses: 14,
      pointsFor: 3700,
      pointsAgainst: 3500,
    });
    expect(postRegular.actual_gp).toBe(44);
    expect(postRegular.current_pace).toBe(30);
    expect(postRegular.performance_delta).toBeCloseTo(6.0, 6);

    // Zero games played
    const zeroGp = enrichTeamWithActualRecord(baseProj);
    expect(zeroGp.actual_gp).toBe(0);
    expect(zeroGp.actual_win_pct).toBe(0);
    expect(zeroGp.current_pace).toBe(0);
  });
});
