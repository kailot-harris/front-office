import { describe, it, expect } from 'vitest';
import {
  getTeamsData,
  getPlayersData,
  getMetadata,
  getDiagnostics,
  getPostseasonOpsData,
  getCbtPayrollOverview,
  getClutchCatalog,
  getPlayerDnaCatalog,
  getPlayoffSeriesCatalog,
  getMatchupsIndex,
} from '@/lib/data';
import {
  MLB_TEAMS_METADATA,
  getTeamLogoUrl,
  getTeamColors,
} from '@/lib/teams';

describe('lib/data.ts server data loaders', () => {
  it('getTeamsData() returns all 30 MLB teams sorted by rank 1..30', () => {
    const teams = getTeamsData();
    expect(teams).toHaveLength(30);
    expect(teams.map((t) => t.rank)).toEqual(
      Array.from({ length: 30 }, (_, i) => i + 1)
    );
  });

  it('getPlayersData() returns active roster projections matching metadata players_count', () => {
    const players = getPlayersData();
    const meta = getMetadata();
    expect(players).toHaveLength(meta.players_count);
    expect(players[0].player_name).toBeTruthy();
  });

  it('getMetadata() returns model metadata with 1,000 simulations and 2430 schedule games', () => {
    const meta = getMetadata();
    expect(meta.season).toBe(2026);
    expect(meta.n_simulations).toBe(1000);
    expect(meta.postseason_sims).toBe(10000);
    expect(meta.total_schedule_games).toBe(2430);
    expect(meta.teams_count).toBe(30);
  });

  it('getDiagnostics(), getPostseasonOpsData(), getCbtPayrollOverview(), getClutchCatalog(), getPlayerDnaCatalog(), getPlayoffSeriesCatalog(), and getMatchupsIndex() load valid objects with generated_at', () => {
    expect(getDiagnostics().generated_at).toBeTruthy();
    expect(getPostseasonOpsData().generated_at).toBeTruthy();
    expect(getCbtPayrollOverview().generated_at).toBeTruthy();
    expect(getClutchCatalog().generated_at).toBeTruthy();
    expect(getPlayerDnaCatalog().generated_at).toBeTruthy();
    expect(getPlayoffSeriesCatalog().generated_at).toBeTruthy();
    expect(getMatchupsIndex().generated_at).toBeTruthy();
  });
});

describe('lib/teams.ts metadata helpers', () => {
  it('getTeamLogoUrl() and getTeamColors() resolve case-insensitively across all 30 MLB teams', () => {
    expect(MLB_TEAMS_METADATA.LAD.fullName).toBe('Los Angeles Dodgers');
    expect(MLB_TEAMS_METADATA.NYY.fullName).toBe('New York Yankees');
    expect(getTeamLogoUrl('lad')).toContain('/logos/119.png');
    expect(getTeamLogoUrl('NYY')).toContain('/logos/147.png');
    expect(getTeamColors('lad').primary).toBe('#005A9C');
    expect(getTeamColors('UNKNOWN').primary).toBe('#6366f1');
    expect(Object.keys(MLB_TEAMS_METADATA)).toHaveLength(30);
  });
});
