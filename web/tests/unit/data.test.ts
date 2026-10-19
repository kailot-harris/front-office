import { describe, it, expect } from 'vitest';
import {
  getTeamsData,
  getPlayersData,
  getMetadata,
  getDiagnostics,
} from '@/lib/data';
import {
  WNBA_TEAMS_METADATA,
  getTeamLogoUrl,
  getTeamColors,
} from '@/lib/teams';

describe('lib/data.ts server data loaders', () => {
  it('getTeamsData() returns all 15 WNBA teams sorted by ensemble_mean_wins descending with rank 1..15', () => {
    const teams = getTeamsData();
    expect(teams).toHaveLength(15);
    expect(teams.map((t) => t.rank)).toEqual(
      Array.from({ length: 15 }, (_, i) => i + 1)
    );
    for (let i = 1; i < teams.length; i++) {
      expect(teams[i - 1].ensemble_mean_wins).toBeGreaterThanOrEqual(
        teams[i].ensemble_mean_wins
      );
    }
  });

  it('getPlayersData() returns active roster projections with numeric stats', () => {
    const players = getPlayersData();
    expect(players.length).toBeGreaterThanOrEqual(180);
    expect(players[0].player_name).toBeTruthy();
    expect(typeof players[0].proj_pts).toBe('number');
  });

  it('getMetadata() returns model metadata with 1,000 simulations and 330 schedule games', () => {
    const meta = getMetadata();
    expect(meta.season).toBe(2026);
    expect(meta.n_simulations).toBe(1000);
    expect(meta.total_schedule_games).toBe(330);
    expect(meta.teams_count).toBe(15);
  });

  it('getDiagnostics() returns resolved game metrics and calibration bins', () => {
    const diag = getDiagnostics();
    expect(diag.totalResolvedGames).toBeGreaterThan(1000);
    expect(diag.calibration.length).toBeGreaterThanOrEqual(5);
    expect(diag.accuracyDrift.length).toBeGreaterThanOrEqual(1);
    expect(diag.residualDistribution.length).toBeGreaterThanOrEqual(3);
  });
});

describe('lib/teams.ts metadata helpers', () => {
  it('getTeamLogoUrl() and getTeamColors() resolve case-insensitively across all 15 WNBA teams', () => {
    expect(WNBA_TEAMS_METADATA.NY.fullName).toBe('New York Liberty');
    expect(WNBA_TEAMS_METADATA.LV.fullName).toBe('Las Vegas Aces');
    expect(getTeamLogoUrl('min')).toBe('/logos/MIN_logo.png');
    expect(getTeamLogoUrl('NY')).toBe('/logos/NY_logo.png');
    expect(getTeamColors('lv').primary).toBe('#000000');
    expect(getTeamColors('UNKNOWN').primary).toBe('#6366f1');
    expect(Object.keys(WNBA_TEAMS_METADATA)).toHaveLength(15);
  });
});
