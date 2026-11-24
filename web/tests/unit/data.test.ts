import { describe, it, expect } from 'vitest';
import {
  getTeamsData,
  getPlayersData,
  getMetadata,
  getDiagnostics,
  getMatchupsData,
  getActualTeamRecords,
  deriveActualTeamRecords,
} from '@/lib/data';
import type { MatchupGame } from '@/lib/matchupTypes';
import {
  NBA_TEAMS_METADATA,
  getTeamLogoUrl,
  getTeamColors,
} from '@/lib/teams';

describe('lib/data.ts server data loaders', () => {
  it('getTeamsData() returns all 30 NBA teams sorted by ensemble_mean_wins descending with rank 1..30', () => {
    const teams = getTeamsData();
    expect(teams).toHaveLength(30);
    expect(teams.map((t) => t.rank)).toEqual(
      Array.from({ length: 30 }, (_, i) => i + 1)
    );
    for (let i = 1; i < teams.length; i++) {
      expect(teams[i - 1].ensemble_mean_wins).toBeGreaterThanOrEqual(
        teams[i].ensemble_mean_wins
      );
    }
  });

  it('getPlayersData() returns active roster projections for 330 players', () => {
    const players = getPlayersData();
    expect(players).toHaveLength(330);
    expect(players[0].player_name).toBeTruthy();
    expect(typeof players[0].proj_pts).toBe('number');
  });

  it('getMetadata() returns model metadata with 1,000 simulations and 1230 schedule games', () => {
    const meta = getMetadata();
    // config.R's CURRENT_SEASON is the hoopR end-year for 2026-2027.
    expect(meta.season).toBe(2027);
    expect(meta.n_simulations).toBe(1000);
    expect(meta.total_schedule_games).toBe(1230);
    expect(meta.teams_count).toBe(30);
  });

  it('getDiagnostics() returns resolved game metrics and calibration bins', () => {
    const diag = getDiagnostics();
    // totalResolvedGames grows with every completed game, so assert invariants
    // rather than today's count: it must be a positive integer, and it cannot
    // exceed the games already accounted for across the multi-season accuracy
    // drift history that produced it.
    expect(Number.isInteger(diag.totalResolvedGames)).toBe(true);
    expect(diag.totalResolvedGames).toBeGreaterThan(0);
    expect(diag.totalResolvedGames).toBeLessThanOrEqual(
      diag.accuracyDrift.reduce((sum, d) => sum + d.games, 0)
    );
    // Every resolved game must land in exactly one calibration bin.
    expect(
      diag.calibration.reduce((sum, bin) => sum + bin.count, 0)
    ).toBe(diag.totalResolvedGames);
    expect(diag.calibration.length).toBeGreaterThanOrEqual(5);
    expect(diag.accuracyDrift.length).toBeGreaterThanOrEqual(1);
    expect(diag.residualDistribution.length).toBeGreaterThanOrEqual(3);
  });

  it('getActualTeamRecords() derives W-L, PF, and PA from completed games in matchups_slates.json', () => {
    const { matchups } = getMatchupsData();
    const records = getActualTeamRecords();
    const completed = matchups.filter(
      (g) => g.is_completed && typeof g.home_score === 'number' && typeof g.away_score === 'number'
    );

    const totalWins = Object.values(records).reduce((sum, r) => sum + r.wins, 0);
    const totalLosses = Object.values(records).reduce((sum, r) => sum + r.losses, 0);
    const totalPf = Object.values(records).reduce((sum, r) => sum + r.pointsFor, 0);
    const totalPa = Object.values(records).reduce((sum, r) => sum + r.pointsAgainst, 0);

    expect(completed.length).toBeGreaterThan(0);
    expect(totalWins).toBe(completed.length);
    expect(totalLosses).toBe(completed.length);
    expect(totalPf).toBe(totalPa);

    // Independently check a sample team's record against completed matchups
    const bosGames = completed.filter((g) => g.home_team === 'BOS' || g.away_team === 'BOS');
    let expectedBosWins = 0;
    let expectedBosPf = 0;
    let expectedBosPa = 0;
    for (const g of bosGames) {
      const isHome = g.home_team === 'BOS';
      const pf = isHome ? g.home_score! : g.away_score!;
      const pa = isHome ? g.away_score! : g.home_score!;
      if (pf > pa) expectedBosWins += 1;
      expectedBosPf += pf;
      expectedBosPa += pa;
    }
    expect(records.BOS).toEqual({
      wins: expectedBosWins,
      losses: bosGames.length - expectedBosWins,
      pointsFor: expectedBosPf,
      pointsAgainst: expectedBosPa,
    });
  });

  it('deriveActualTeamRecords() ignores pending games and non-finite scores', () => {
    expect(deriveActualTeamRecords([])).toEqual({});

    const baseGame: MatchupGame = {
      game_id: '1',
      slate: 1,
      game_date: '2026-10-20',
      weekday: 'Tue',
      season: 2027,
      home_team: 'BOS',
      away_team: 'NYK',
      home_team_name: 'Celtics',
      away_team_name: 'Knicks',
      is_completed: false,
      has_projection: false,
      projection_basis: null,
      predicted_margin: null,
      predicted_home_win_prob: null,
      predicted_away_win_prob: null,
      predicted_winner: null,
      home_score: 110,
      away_score: 100,
      actual_margin: null,
      actual_winner: null,
      prediction_correct: null,
    };

    const records = deriveActualTeamRecords([
      baseGame, // pending -> ignored
      { ...baseGame, game_id: '2', is_completed: true, home_score: null, away_score: 100 }, // null score -> ignored
      { ...baseGame, game_id: '3', is_completed: true, home_score: 112, away_score: 105 },
    ]);

    expect(records).toEqual({
      BOS: { wins: 1, losses: 0, pointsFor: 112, pointsAgainst: 105 },
      NYK: { wins: 0, losses: 1, pointsFor: 105, pointsAgainst: 112 },
    });
  });
});

describe('lib/teams.ts metadata helpers', () => {
  it('getTeamLogoUrl() and getTeamColors() resolve case-insensitively across all 30 NBA teams', () => {
    expect(NBA_TEAMS_METADATA.BOS.fullName).toBe('Boston Celtics');
    expect(NBA_TEAMS_METADATA.LAL.fullName).toBe('Los Angeles Lakers');
    expect(getTeamLogoUrl('gsw')).toContain('gsw.png');
    expect(getTeamLogoUrl('NYK')).toContain('nyk.png');
    expect(getTeamColors('lal').primary).toBe('#552583');
    expect(getTeamColors('UNKNOWN').primary).toBe('#6366f1');
    expect(Object.keys(NBA_TEAMS_METADATA)).toHaveLength(30);
  });
});
