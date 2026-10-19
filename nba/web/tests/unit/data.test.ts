import { describe, it, expect } from 'vitest';
import {
  getTeamsData,
  getPlayersData,
  getMetadata,
  getDiagnostics,
} from '@/lib/data';
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
    expect(meta.season).toBe(2026);
    expect(meta.n_simulations).toBe(1000);
    expect(meta.total_schedule_games).toBe(1230);
    expect(meta.teams_count).toBe(30);
  });

  it('getDiagnostics() returns resolved game metrics and calibration bins', () => {
    const diag = getDiagnostics();
    expect(diag.totalResolvedGames).toBe(2631);
    expect(diag.calibration.length).toBeGreaterThanOrEqual(5);
    expect(diag.accuracyDrift.length).toBeGreaterThanOrEqual(1);
    expect(diag.residualDistribution.length).toBeGreaterThanOrEqual(3);
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
